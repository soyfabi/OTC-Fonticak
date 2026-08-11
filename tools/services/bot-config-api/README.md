# Fonticak config API (free)

Cloudflare Worker + KV for sharing both:

- bot profiles as ZIP archives (`kind=bot`);
- client options and hotkeys as `otc-fonticak-config` JSON (`kind=options`).

An upload returns a 12-character hexadecimal content hash. Anyone with that hash can download the same immutable content.

## Requirements

- Free [Cloudflare](https://dash.cloudflare.com/sign-up) account
- Node.js 18+ (only for deploy with Wrangler)

No paid plan needed. Free KV limits are enough for personal/friend sharing.

## Deploy

```bash
cd tools/services/bot-config-api
npm install
npx wrangler login
npm run kv:create
```

Copy the printed KV namespace **id** into `wrangler.toml`:

```toml
[[kv_namespaces]]
binding = "CONFIGS"
id = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
preview_id = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Deploy:

```bash
npm run deploy
```

Wrangler prints a URL like:

```text
https://fonticak-configs.<your-subdomain>.workers.dev
```

## Wire the clients

The bot and Options share one URL from `modules/corelib/config_share.lua`:

```lua
https://fonticak-configs.<your-subdomain>.workers.dev/
```

Keep the trailing `/`.

Bot ZIP support also requires a client build with `createArchive` /
`decompressArchive`.

## API

### Upload

```text
POST ?config=Name&kind=bot
POST ?config=Name&kind=options
```

The request body is a raw ZIP for `bot`, or a JSON document whose top-level
`format` is `"otc-fonticak-config"` for `options`. A successful response keeps
the original client contract:

```json
{
  "hash": "0123456789ab",
  "kind": "bot",
  "message": "Config hash: 0123456789ab\nShare this code so others can download your config."
}
```

`kind` is optional. When omitted, the Worker detects a ZIP as `bot` or the
Fonticak JSON marker as `options`. This preserves existing
`POST ?config=Name` clients.

Uploading identical bytes is idempotent and returns the same hash without
writing another object. If different content ever has the same 12-character
SHA-256 prefix, the Worker returns `409` and does not overwrite the existing
object.

### Download

```text
GET ?hash=0123456789ab
GET ?hash=0123456789ab&kind=bot
GET ?hash=0123456789ab&kind=options
```

Hashes are exactly 12 hexadecimal characters. New objects are returned with
the stored media type and extension (`application/zip` + `.zip`, or
`application/json` + `.json`). Older KV objects without the new metadata remain
downloadable and default to ZIP. When `kind` is supplied, new typed entries of
the wrong kind are rejected before their body is downloaded.

Max size: **1024 KB** (same as the bot UI).

## Stored metadata

Each new KV object stores:

- `kind`, `contentType`, `extension`;
- `size`, ISO-8601 `createdAt`, and the full `sha256`;
- a sanitized `config` name, limited to 128 characters.

The short key remains the first 12 lowercase hexadecimal characters of SHA-256.

## Compatibility and security

- Existing `POST ?config=` and `GET ?hash=` URLs and 12-character hashes are
  unchanged.
- Upload content is validated instead of trusting the query or media type.
- Bodies larger than 1 MiB are rejected; the `config` value is bounded and
  sanitized before storage or use in download filenames.
- Successful content-addressed downloads use one-year immutable caching.
  API, validation, and error responses use `no-store`.
- CORS permits `GET`, `POST`, and `OPTIONS` with `Content-Type`; no credentials
  are accepted.
- Unexpected failures are logged server-side, while callers receive only a
  generic internal-error message.
- The service is intentionally public: possession of a hash grants download
  access. Do not upload secrets, tokens, passwords, or private account data.

## Manual test checklist

1. Deploy Worker + KV and set `ConfigShare.url`.
2. Rebuild OTClient/Fonticak (C++ ZIP support).
3. Upload and download a bot ZIP; confirm scripts and UI load.
4. Upload and download an options category; confirm the JSON imports.
5. Upload the same body twice and confirm both responses return the same hash.
6. Confirm malformed JSON, non-ZIP data, oversized bodies, and non-12-character
   hashes are rejected.

## Local dev

```bash
npm run dev
```

Then temporarily point `configManagerUrl` to the local Wrangler URL (usually `http://127.0.0.1:8787/`).

Run the dependency-free checks with:

```bash
npm test
```
