const MAX_BYTES = 1024 * 1024;
const MAX_CONFIG_LENGTH = 128;
const HASH_LEN = 12;
const OPTIONS_FORMAT = "otc-fonticak-config";

const TYPE_INFO = {
  bot: { contentType: "application/zip", extension: "zip" },
  options: { contentType: "application/json; charset=utf-8", extension: "json" },
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...corsHeaders,
      ...extraHeaders,
    },
  });
}

function isValidHash(hash) {
  return typeof hash === "string" && /^[a-f0-9]{12}$/.test(hash);
}

function sanitizeConfigName(value) {
  const cleaned = String(value || "config")
    .trim()
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .replace(/[^\x20-\x7e]/g, "_")
    .replace(/[\\/:*?"<>|]/g, "_")
    .replace(/\s+/g, " ")
    .replace(/^\.+/, "")
    .slice(0, MAX_CONFIG_LENGTH)
    .trim();
  return cleaned || "config";
}

function isZip(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0x50 || bytes[1] !== 0x4b) {
    return false;
  }
  return (
    (bytes[2] === 0x03 && bytes[3] === 0x04) ||
    (bytes[2] === 0x05 && bytes[3] === 0x06) ||
    (bytes[2] === 0x07 && bytes[3] === 0x08)
  );
}

function isOptionsJson(body) {
  try {
    const payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(body));
    return payload !== null && typeof payload === "object" && payload.format === OPTIONS_FORMAT;
  } catch {
    return false;
  }
}

function detectKind(body) {
  const bytes = new Uint8Array(body);
  if (isZip(bytes)) {
    return "bot";
  }
  if (isOptionsJson(body)) {
    return "options";
  }
  return null;
}

async function sha256Hex(buffer) {
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function getStoredEntry(env, hash) {
  const result = await env.CONFIGS.getWithMetadata(hash, { type: "arrayBuffer" });
  if (!result || result.value === null) {
    return null;
  }
  return { value: result.value, metadata: result.metadata || {} };
}

async function handleUpload(request, env) {
  const url = new URL(request.url);
  const requestedKind = (url.searchParams.get("kind") || "").trim().toLowerCase();
  if (requestedKind && !TYPE_INFO[requestedKind]) {
    return jsonResponse({ error: 'Invalid kind; expected "bot" or "options"' }, 400);
  }

  const rawConfig = url.searchParams.get("config");
  if (rawConfig !== null && rawConfig.trim().length > MAX_CONFIG_LENGTH) {
    return jsonResponse({ error: `Config name is too long; max is ${MAX_CONFIG_LENGTH} characters` }, 400);
  }
  const configName = sanitizeConfigName(rawConfig);

  const contentLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(contentLength) && contentLength > MAX_BYTES) {
    return jsonResponse({ error: `Config too large. Max is ${MAX_BYTES} bytes.` }, 413);
  }

  const body = await request.arrayBuffer();
  if (body.byteLength === 0) {
    return jsonResponse({ error: "Empty config" }, 400);
  }
  if (body.byteLength > MAX_BYTES) {
    return jsonResponse({ error: `Config too large. Max is ${MAX_BYTES} bytes.` }, 413);
  }

  const detectedKind = detectKind(body);
  if (!detectedKind) {
    return jsonResponse({ error: "Unsupported config; expected a ZIP or otc-fonticak-config JSON" }, 415);
  }
  if (requestedKind && requestedKind !== detectedKind) {
    return jsonResponse({ error: `Payload does not match kind "${requestedKind}"` }, 400);
  }

  const kind = requestedKind || detectedKind;
  const typeInfo = TYPE_INFO[kind];
  const fullHash = await sha256Hex(body);
  const hash = fullHash.slice(0, HASH_LEN);
  const existing = await getStoredEntry(env, hash);

  if (existing) {
    const existingSha = await sha256Hex(existing.value);
    if (existingSha === fullHash) {
      return jsonResponse({
        hash,
        kind: existing.metadata.kind || kind,
        message: `Config hash: ${hash}\nShare this code so others can download your config.`,
      });
    }
    console.error("SHA-256 prefix collision", { hash, existingSha, incomingSha: fullHash });
    return jsonResponse({ error: "Hash collision; config was not stored" }, 409);
  }

  await env.CONFIGS.put(hash, body, {
    metadata: {
      kind,
      contentType: typeInfo.contentType,
      extension: typeInfo.extension,
      size: body.byteLength,
      createdAt: new Date().toISOString(),
      sha256: fullHash,
      config: configName,
    },
  });

  return jsonResponse({
    hash,
    kind,
    message: `Config hash: ${hash}\nShare this code so others can download your config.`,
  });
}

function normalizeDownloadMetadata(metadata) {
  const kind = metadata.kind === "options" || metadata.kind === "bot" ? metadata.kind : "bot";
  const fallback = TYPE_INFO[kind];
  const extension = metadata.extension === "json" || metadata.extension === "zip"
    ? metadata.extension
    : fallback.extension;
  const contentType = typeof metadata.contentType === "string" && metadata.contentType
    ? metadata.contentType
    : fallback.contentType;
  return { kind, extension, contentType };
}

async function handleDownload(request, env) {
  const url = new URL(request.url);
  const hash = (url.searchParams.get("hash") || "").trim().toLowerCase();
  const requestedKind = (url.searchParams.get("kind") || "").trim().toLowerCase();
  if (!isValidHash(hash)) {
    return jsonResponse({ error: "Invalid hash; expected exactly 12 hexadecimal characters" }, 400);
  }
  if (requestedKind && !TYPE_INFO[requestedKind]) {
    return jsonResponse({ error: 'Invalid kind; expected "bot" or "options"' }, 400);
  }

  const entry = await getStoredEntry(env, hash);
  if (!entry) {
    return jsonResponse({ error: `Config with hash ${hash} was not found` }, 404);
  }
  if (requestedKind && entry.metadata.kind && requestedKind !== entry.metadata.kind) {
    return jsonResponse({ error: `Config ${hash} is "${entry.metadata.kind}", not "${requestedKind}"` }, 409);
  }

  const { contentType, extension } = normalizeDownloadMetadata(entry.metadata);
  const configName = sanitizeConfigName(entry.metadata.config || hash)
    .replace(/\.(zip|json)$/i, "");
  const filename = `${configName || hash}.${extension}`;

  return new Response(entry.value, {
    status: 200,
    headers: {
      "Content-Type": contentType,
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Content-Length": String(entry.value.byteLength),
      "Cache-Control": "public, max-age=31536000, immutable",
      "X-Content-Type-Options": "nosniff",
      ...corsHeaders,
    },
  });
}

const worker = {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    const url = new URL(request.url);
    try {
      if (request.method === "POST") {
        return await handleUpload(request, env);
      }
      if (request.method === "GET") {
        if (url.searchParams.has("hash")) {
          return await handleDownload(request, env);
        }
        return jsonResponse({
          service: env.SERVICE_NAME || "fonticak-bot-config-api",
          usage: {
            upload: "POST ?config=Name[&kind=bot|options]",
            download: "GET ?hash=xxxxxxxxxxxx",
          },
          limits: { bytes: MAX_BYTES, hashLength: HASH_LEN },
        });
      }
      return jsonResponse({ error: "Method not allowed" }, 405, { Allow: "GET, POST, OPTIONS" });
    } catch (error) {
      console.error("Unhandled Worker error", error);
      return jsonResponse({ error: "Internal server error" }, 500);
    }
  },
};

export {
  HASH_LEN,
  MAX_BYTES,
  detectKind,
  isValidHash,
  sanitizeConfigName,
};
export default worker;
