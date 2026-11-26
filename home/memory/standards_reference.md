---
name: Standards reference
description: Authoritative standards (RFCs, ISO, semver, POSIX) applicable to CasjaysDev projects — HTTP, dates, versions, errors, auth, security headers, MIME, UUIDs
type: user
---

## Principle

Use the existing standard. Never invent a custom scheme when an RFC, ISO spec, or established convention already covers it. When in doubt, cite the spec and follow it exactly.

---

## HTTP Status Codes (RFC 9110)

### 2xx — Success

| Code | Name | When to use |
|------|------|-------------|
| `200` | OK | Successful GET, PUT, PATCH, DELETE with body |
| `201` | Created | Successful POST that created a resource; include `Location` header |
| `202` | Accepted | Request accepted for async processing; not yet complete |
| `204` | No Content | Successful DELETE or action with no response body |
| `206` | Partial Content | Range request (file downloads, pagination streaming) |

### 3xx — Redirection

| Code | Name | When to use |
|------|------|-------------|
| `301` | Moved Permanently | Permanent URL change; browser caches redirect |
| `302` | Found | Temporary redirect; do not cache |
| `304` | Not Modified | Conditional GET; client cache is still valid |
| `307` | Temporary Redirect | Temporary; preserves HTTP method (unlike 302) |
| `308` | Permanent Redirect | Permanent; preserves HTTP method (unlike 301) |

### 4xx — Client Error

| Code | Name | When to use |
|------|------|-------------|
| `400` | Bad Request | Malformed request, invalid JSON, failed validation |
| `401` | Unauthorized | Not authenticated — missing or invalid credentials |
| `403` | Forbidden | Authenticated but not authorized for this resource |
| `404` | Not Found | Resource does not exist |
| `405` | Method Not Allowed | HTTP method not supported on this endpoint; include `Allow` header |
| `408` | Request Timeout | Client too slow sending request |
| `409` | Conflict | State conflict — duplicate, version mismatch, optimistic lock fail |
| `410` | Gone | Resource permanently deleted (stronger than 404) |
| `413` | Content Too Large | Request body exceeds limit |
| `415` | Unsupported Media Type | Wrong `Content-Type` |
| `422` | Unprocessable Content | Syntactically valid but semantically invalid (business rule failure) |
| `425` | Too Early | Request sent before server is ready (e.g. TLS early data replay risk) |
| `429` | Too Many Requests | Rate limit exceeded; include `Retry-After` header |

### 5xx — Server Error

| Code | Name | When to use |
|------|------|-------------|
| `500` | Internal Server Error | Unhandled exception, unexpected state |
| `501` | Not Implemented | Feature not yet implemented |
| `502` | Bad Gateway | Upstream/proxy returned invalid response |
| `503` | Service Unavailable | Server overloaded or in maintenance; include `Retry-After` |
| `504` | Gateway Timeout | Upstream/proxy timed out |

### Rules

- **401 vs 403**: 401 = "who are you?", 403 = "I know who you are, you can't do this"
- **404 vs 410**: use 410 when the resource existed and was deliberately removed
- **400 vs 422**: 400 = unparseable, 422 = parsed but invalid business logic
- Never use `200` with an error payload — use the appropriate 4xx/5xx code
- Always return a body on 4xx/5xx — use RFC 7807 Problem Details format (see below)

---

## API Error Body — RFC 7807 Problem Details

```json
{
  "type": "https://example.com/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "The 'email' field must be a valid email address.",
  "instance": "/api/users/register"
}
```

- `type`: URI identifying the error class (may be a docs URL or `about:blank`)
- `title`: short human-readable summary — does not change per occurrence
- `status`: HTTP status code (integer)
- `detail`: human-readable explanation specific to this occurrence
- `instance`: URI of the specific request that failed (optional)
- `Content-Type` header: `application/problem+json`

---

## Dates and Times — ISO 8601 / RFC 3339

- All timestamps in APIs, logs, and filenames: **ISO 8601 / RFC 3339** — `2026-05-13T10:58:00Z` or `2026-05-13T10:58:00-04:00`
- Always store and transmit in **UTC** — convert to local only for display
- Date-only: `2026-05-13`
- Time-only: `10:58:00`
- Duration: `P1Y2M3DT4H5M6S`
- Never use Unix epoch integers in external APIs — use ISO 8601 strings
- Never use locale-specific formats (`05/13/26`, `13-May-2026`) in machine interfaces

---

## Versioning — Semantic Versioning (semver.org)

Format: `MAJOR.MINOR.PATCH[-prerelease][+build]`

| Part | Increment when |
|------|---------------|
| `MAJOR` | Breaking change — existing consumers must update |
| `MINOR` | New backward-compatible feature |
| `PATCH` | Backward-compatible bug fix |

Examples: `1.0.0`, `2.3.1`, `1.0.0-alpha.1`, `1.0.0+20260513`

- `release.txt` contains the current semver string, one line, no `v` prefix
- Git tags use `v` prefix: `v1.0.0` — the `v` is for git, not part of the version
- Pre-1.0: anything may change; `0.x.y` — minor bumps may break
- API versioning in URLs: `/api/v1/`, `/api/v2/` — integer major only, no minor in URL

---

## Content Types — MIME (RFC 2045, RFC 6838)

| Type | Use |
|------|-----|
| `application/json` | JSON API responses |
| `application/problem+json` | RFC 7807 error responses |
| `application/octet-stream` | Binary / unknown file download |
| `application/x-www-form-urlencoded` | HTML form POST |
| `multipart/form-data` | File upload forms |
| `text/plain; charset=utf-8` | Plain text responses |
| `text/html; charset=utf-8` | HTML responses |
| `text/csv; charset=utf-8` | CSV export |
| `image/png`, `image/jpeg`, `image/webp` | Images |
| `application/pdf` | PDF |

- Always include `; charset=utf-8` on text types
- Always set `Content-Type` on every response — never omit it
- Validate `Content-Type` on incoming requests — return `415` if wrong

---

## UUIDs — RFC 4122 / RFC 9562

- Use **UUID v4** (random) for most IDs — `550e8400-e29b-41d4-a716-446655440000`
- Use **UUID v7** (time-ordered random) when sort order matters (database primary keys, event IDs) — preferred over v4 for new projects
- Never use UUID v1 (MAC address leaks), v3, or v5 unless specifically needed for namespaced deterministic IDs
- Always lowercase, always hyphenated — never uppercase, never strip hyphens
- Store as `UUID` type in PostgreSQL, `CHAR(36)` or `BINARY(16)` in MySQL

---

## HTTP Security Headers

Always set on every HTTP response from a web-facing service:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevent MIME sniffing |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` | Clickjacking protection |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limit referrer leakage |
| `Content-Security-Policy` | project-specific | XSS mitigation |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | Restrict browser APIs |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` | Force HTTPS (2 years) |

- `HSTS` only on HTTPS responses — never on HTTP
- `CSP` must be defined per project in `{project_dir}/IDEA.md` — no global default (too project-specific)

---

## TLS — RFC 8446

- Minimum TLS version: **TLS 1.2** — TLS 1.0 and 1.1 are forbidden
- Preferred: **TLS 1.3** only where clients support it
- Cipher suites: follow Mozilla Intermediate or Modern profile ([ssl-config.mozilla.org](https://ssl-config.mozilla.org/))
- Never self-signed in production — use Let's Encrypt (ACME, RFC 8555)
- Certificate pinning: only if `{project_dir}/IDEA.md` explicitly defines it

---

## Authentication and Tokens

### JWT — RFC 7519

- Algorithm: **RS256** or **ES256** — never `none`, never `HS256` in multi-service environments (shared secret required)
- Claims: always validate `exp`, `iat`, `iss`, `aud`
- Never store sensitive data in the payload — JWTs are base64, not encrypted
- Keep short-lived: access tokens ≤ 15 minutes; refresh tokens ≤ 30 days

### OAuth 2.0 — RFC 6749

- Always **authorization code flow** with PKCE (RFC 7636) for user-facing apps
- Never implicit flow (deprecated, RFC 9700)
- Never embed client secrets in mobile/SPA apps
- Token endpoint: always over HTTPS

### Passwords

- Hash with **Argon2id** — never a new bcrypt hash (a legacy bcrypt hash is verified, then rehashed), never MD5/SHA-* alone
- Never store plaintext passwords
- Never log passwords or raw tokens — hash with SHA-256 before logging if the event must be recorded

---

## URLs — RFC 3986

- Always lowercase path segments: `/api/users/profile` not `/api/Users/Profile`
- Use hyphens in URL paths: `/api/user-profile` not `/api/user_profile` or `/api/userProfile`
- Query parameters: `snake_case` or `camelCase` — be consistent within a project; document in API spec
- Never expose internal IDs that reveal implementation (sequential integers for user IDs = enumeration risk) — use UUIDs or opaque tokens
- Trailing slash: pick one convention per project and enforce it; redirect the other form with 308

---

## Pagination

No single RFC; use the established convention for the API style:

### Cursor-based (preferred for large / real-time datasets)

```json
{
  "data": [...],
  "next_cursor": "eyJpZCI6MTIzfQ==",
  "has_more": true
}
```

Query params: `?cursor={token}&limit={n}`

### Offset-based (acceptable for small stable datasets)

```json
{
  "data": [...],
  "total": 1000,
  "page": 2,
  "per_page": 20
}
```

Query params: `?page={n}&per_page={n}`

- Default page size: 20; maximum: 100 — never unlimited
- Always include `Link` header (RFC 8288) with `rel=next`, `rel=prev`, `rel=first`, `rel=last`

---

## DNS — RFC 1035

- Hostname labels: lowercase letters, digits, hyphens only — no underscores in public hostnames
- Max label length: 63 characters; max total FQDN: 253 characters
- Always validate hostnames against this before accepting user input (SSRF prevention)
- Internal/private hostnames may use underscores in some systems but never rely on resolution

---

## Encoding — RFC 4648

- **Base64**: standard alphabet (`A-Za-z0-9+/`) with `=` padding — for binary-in-text
- **Base64url**: URL-safe alphabet (`A-Za-z0-9-_`) without padding — for JWTs, URL tokens, filenames
- Never use standard Base64 in URLs — always Base64url
- **Hex**: lowercase (`deadbeef`) — never uppercase in machine interfaces; uppercase only in human-facing display if project style requires it

---

## Caching — HTTP Cache-Control

Use `Cache-Control` on every response. Never rely on heuristic caching.

| Resource type | Directive | Rationale |
|---------------|-----------|-----------|
| HTML pages | `no-cache` | Always revalidate; content changes with deploys |
| API responses | `no-store` | Never cache; data is per-user or real-time |
| Versioned static assets (JS, CSS, images with hash in URL) | `public, max-age=31536000, immutable` | Hash in URL ensures cache-busting; safe to cache forever |
| Non-versioned static assets | `public, max-age=3600` | Revalidated hourly |
| Auth-gated resources | `private, no-store` | Must not be stored in shared caches |

Always include `Vary: Accept-Encoding` when serving compressed content.

### Conditional requests — ETag / Last-Modified

Support conditional requests on cacheable resources to enable 304 Not Modified responses:

- `ETag`: preferred; use a hash of the response content; compare with `If-None-Match`
- `Last-Modified`: fallback; use ISO 8601 / HTTP date format; compare with `If-Modified-Since`
- Return `304 No Content` (no body) when the client's cached version is still valid
- ETag takes precedence over Last-Modified when both are present

---

## CORS — Cross-Origin Resource Sharing

- **Never use `Access-Control-Allow-Origin: *` with `Access-Control-Allow-Credentials: true`** — browsers block this; it is also a security risk
- For public APIs with no credentials: `Access-Control-Allow-Origin: *` is acceptable
- For credentialed requests: specify the exact origin(s) explicitly; use a server-side allowlist; never reflect the `Origin` header back without validation
- Allowed methods: specify only the methods the endpoint actually supports (`GET, POST` not `*`)
- Allowed headers: specify only headers the endpoint reads; avoid `*` for headers
- Preflight cache: `Access-Control-Max-Age: 86400` (24 hours) to reduce preflight round-trips
- CORS is not a substitute for authentication — a CORS-permitted origin can still make requests; validate authorization server-side on every request

---

## WebSocket — RFC 6455

- WebSocket upgrade is always over TLS (`wss://`) in production — never plain `ws://`
- Authenticate the WebSocket connection at upgrade time (HTTP 101 handshake) via a short-lived token in the query string or an initial auth message — not via cookie alone (CSRF risk)
- **Ping/Pong keepalive**: server sends a `Ping` frame every 30s; close the connection if no `Pong` is received within 10s
- **Close codes** (RFC 6455 §7.4):

  | Code | Meaning | When to send |
  |------|---------|-------------|
  | `1000` | Normal closure | Clean server or client shutdown |
  | `1001` | Going away | Server restarting / client navigating away |
  | `1008` | Policy violation | Auth failure, rate limit |
  | `1011` | Internal error | Unhandled server error |
  | `1012` | Service restart | Graceful server restart — client should reconnect |

- Always send a Close frame before closing the TCP connection; never drop the socket without a close handshake
- Cap message size server-side — reject (close with `1009 Message Too Big`) any frame exceeding the project-defined limit (default 1 MiB)
- Per-connection state lives in the connection handler; never in package-level globals

---

## gRPC — gRPC Status Codes

Use gRPC status codes (not HTTP codes) for gRPC services:

| Code | Name | When to use |
|------|------|-------------|
| `0` | `OK` | Success |
| `1` | `CANCELLED` | Client cancelled the request |
| `2` | `UNKNOWN` | Unrecognized error — use sparingly |
| `3` | `INVALID_ARGUMENT` | Bad input from caller |
| `4` | `DEADLINE_EXCEEDED` | Timeout |
| `5` | `NOT_FOUND` | Resource does not exist |
| `6` | `ALREADY_EXISTS` | Duplicate create |
| `7` | `PERMISSION_DENIED` | Authorized but not allowed |
| `8` | `RESOURCE_EXHAUSTED` | Rate limit, quota exceeded |
| `12` | `UNIMPLEMENTED` | Method not implemented |
| `13` | `INTERNAL` | Internal server error |
| `14` | `UNAVAILABLE` | Server temporarily unavailable — client should retry with backoff |
| `16` | `UNAUTHENTICATED` | Not authenticated |

- Always return a status message alongside the code — codes alone are not debuggable
- Map gRPC errors to HTTP equivalents at the gateway layer (gRPC-Gateway or Envoy transcoder); do not expose raw gRPC codes to browser clients
- Proto files live in `proto/` at project root; generated code lives in a dedicated package (`gen/`, `pb/`) — never commit generated files alongside their source proto in the same directory
