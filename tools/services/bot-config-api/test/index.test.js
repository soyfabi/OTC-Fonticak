import assert from "node:assert/strict";
import test from "node:test";

import worker from "../src/index.js";

class MemoryKv {
  constructor() {
    this.entries = new Map();
    this.putCount = 0;
  }

  async put(key, value, options = {}) {
    this.putCount += 1;
    this.entries.set(key, {
      value: value.slice(0),
      metadata: structuredClone(options.metadata || {}),
    });
  }

  async getWithMetadata(key) {
    const entry = this.entries.get(key);
    return entry
      ? { value: entry.value.slice(0), metadata: structuredClone(entry.metadata) }
      : { value: null, metadata: null };
  }
}

function env() {
  return { CONFIGS: new MemoryKv(), SERVICE_NAME: "test-config-api" };
}

function zipBody() {
  return Uint8Array.from([0x50, 0x4b, 0x03, 0x04, 0x01, 0x02]);
}

test("stores and downloads bot ZIPs with exact 12-hex hashes", async () => {
  const testEnv = env();
  const upload = await worker.fetch(
    new Request("https://example.test/?config=My%20Bot&kind=bot", {
      method: "POST",
      body: zipBody(),
    }),
    testEnv,
  );
  assert.equal(upload.status, 200);
  const result = await upload.json();
  assert.match(result.hash, /^[a-f0-9]{12}$/);
  assert.equal(result.kind, "bot");

  const stored = testEnv.CONFIGS.entries.get(result.hash);
  assert.equal(stored.metadata.contentType, "application/zip");
  assert.equal(stored.metadata.extension, "zip");
  assert.equal(stored.metadata.size, zipBody().byteLength);
  assert.match(stored.metadata.sha256, /^[a-f0-9]{64}$/);

  const download = await worker.fetch(
    new Request(`https://example.test/?hash=${result.hash}`),
    testEnv,
  );
  assert.equal(download.status, 200);
  assert.equal(download.headers.get("Content-Type"), "application/zip");
  assert.equal(download.headers.get("Content-Disposition"), 'attachment; filename="My Bot.zip"');
  assert.match(download.headers.get("Cache-Control"), /immutable/);
});

test("detects options JSON without kind and is idempotent", async () => {
  const testEnv = env();
  const body = JSON.stringify({
    format: "otc-fonticak-config",
    version: 1,
    category: "graphics",
    data: {},
  });
  const request = () =>
    new Request("https://example.test/?config=graphics", { method: "POST", body });

  const first = await worker.fetch(request(), testEnv);
  const firstResult = await first.json();
  const second = await worker.fetch(request(), testEnv);
  const secondResult = await second.json();

  assert.equal(firstResult.kind, "options");
  assert.equal(secondResult.hash, firstResult.hash);
  assert.equal(testEnv.CONFIGS.putCount, 1);

  const download = await worker.fetch(
    new Request(`https://example.test/?hash=${firstResult.hash}`),
    testEnv,
  );
  assert.match(download.headers.get("Content-Type"), /^application\/json/);
  assert.equal(download.headers.get("Content-Disposition"), 'attachment; filename="graphics.json"');

  const wrongClient = await worker.fetch(
    new Request(`https://example.test/?hash=${firstResult.hash}&kind=bot`),
    testEnv,
  );
  assert.equal(wrongClient.status, 409);
});

test("rejects invalid hashes, mismatched kinds, and prefix collisions", async () => {
  const testEnv = env();
  const invalidHash = await worker.fetch(
    new Request("https://example.test/?hash=abc"),
    testEnv,
  );
  assert.equal(invalidHash.status, 400);

  const mismatch = await worker.fetch(
    new Request("https://example.test/?config=x&kind=options", {
      method: "POST",
      body: zipBody(),
    }),
    testEnv,
  );
  assert.equal(mismatch.status, 400);

  const initial = await worker.fetch(
    new Request("https://example.test/?config=x", { method: "POST", body: zipBody() }),
    testEnv,
  );
  const { hash } = await initial.json();
  testEnv.CONFIGS.entries.get(hash).value = Uint8Array.from([
    0x50, 0x4b, 0x03, 0x04, 0xff,
  ]).buffer;

  const collision = await worker.fetch(
    new Request("https://example.test/?config=x", { method: "POST", body: zipBody() }),
    testEnv,
  );
  assert.equal(collision.status, 409);
  assert.equal(testEnv.CONFIGS.putCount, 1);
});

test("serves metadata-free legacy entries as ZIP", async () => {
  const testEnv = env();
  const hash = "0123456789ab";
  testEnv.CONFIGS.entries.set(hash, { value: zipBody().buffer, metadata: {} });

  const response = await worker.fetch(
    new Request(`https://example.test/?hash=${hash}`),
    testEnv,
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Type"), "application/zip");
  assert.equal(response.headers.get("Content-Disposition"), `attachment; filename="${hash}.zip"`);
});
