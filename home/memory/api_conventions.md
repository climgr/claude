---
name: API conventions
description: REST route naming, versioning, path vs query params, response format, request ID, content negotiation, and middleware ordering for HTTP APIs
type: user
---

## Route Naming

All API routes follow these rules — no exceptions:

| Rule | Wrong | Correct |
|------|-------|---------|
| Always versioned (exceptions: see Unversioned aliases) | `/api/users` | `/api/v1/users` |
| Plural nouns | `/api/v1/user` | `/api/v1/users` |
| Lowercase | `/api/v1/Users` | `/api/v1/users` |
| Hyphens for multi-word | `/api/v1/saved_searches` | `/api/v1/saved-searches` |
| No trailing slash | `/api/v1/users/` | `/api/v1/users` |
| Nouns not verbs | `/api/v1/getUsers` | `GET /api/v1/users` |

Use `{api_version}` (project variable, default `v1`) — never hardcode the version literal in route registration code; use a constant or config value so it can be bumped in one place.

### Standard route scopes

| Scope | Web | API |
|-------|-----|-----|
| Public server pages | `/server/*` | `/api/{api_version}/server/*` |
| Auth | `/server/auth/*` | `/api/{api_version}/server/auth/*` |
| Current user resources | `/users/*` | `/api/{api_version}/users/*` (ID from session, not URL) |
| Admin | `/server/{admin_path}/*` | `/api/{api_version}/server/{admin_path}/*` |
| Project-specific | `/*` | `/api/{api_version}/*` |

### Unversioned aliases (exhaustive)

The ONLY unversioned API-class paths are: `/api/swagger`, `/api/graphql`, `/api/healthz`, `/api/metrics`, `/api/mcp`, `/api/debug/*`, `/mcp` and `/api/autodiscover`. Any other unversioned `/api/...` route is a defect.

- Aliases mount the SAME handler as the canonical versioned route — never a redirect
- Each alias has one parity test asserting the same status, headers and body as its canonical route
- Docs, examples, tests and client code name the canonical versioned route
- `/api/autodiscover` is unversioned by design (clients call it before they know the version) and has no versioned form

### Health routes

| Route | Behavior |
|-------|----------|
| `/server/healthz` | Frontend: content negotiation — HTML for browsers, JSON for API clients, text for CLI |
| `/api/{api_version}/server/healthz` | API: JSON by default |
| `/api/healthz` | Unversioned alias (see above) |
| `/healthz` | Optional root alias, only when `server.healthz.root.enabled: true` (default `false`); direct handler, never a redirect |

---

## Path vs Query Parameters

| Use case | Parameter type | Example |
|----------|---------------|---------|
| Identifying a specific resource | Path | `/api/{api_version}/users/{id}` |
| Category, type, slug | Path | `/api/{api_version}/jokes/programming` |
| Pagination | Query | `?page=2&per_page=20` or `?cursor=...&limit=20` |
| Sorting | Query | `?sort=created_at&order=desc` |
| Filtering / search options | Query | `?status=active&role=admin` |

Prefer path params for resource identity; query params for modifiers. Never duplicate a path param as a query param.

Pagination defaults: `per_page=20`, max `per_page=100` — never unlimited. See `standards_reference.md` for cursor-based and offset-based response shapes.

---

## Response Format

### JSON API responses

- `Content-Type: application/json`
- 2-space indented (`json.MarshalIndent(v, "", "  ")`)
- Single trailing newline after the closing `}`
- Never emit bare arrays as root — always wrap: `{ "data": [...] }`

### Success envelope (non-paginated)

```json
{
  "ok": true,
  "data": { ... }
}
```

### Error body — RFC 7807 Problem Details

See `standards_reference.md` for the full format. Short reference:

```json
{
  "ok": false,
  "error": "VALIDATION_ERROR",
  "message": "Please enter a valid email address",
  "details": { "field": "email" }
}
```

- `error`: machine-readable code (SCREAMING_SNAKE_CASE)
- `message`: human-readable, safe to display to the user — no internals
- `details`: optional structured context for the client; never include stack traces, DB errors, or internal hostnames
- `Retry-After` on 429: HTTP header only — never a body field
- Always return a body on 4xx/5xx — never an empty response

### Audit / log format

The error that reaches the user is not the same as what is logged. Internally, log the full reason:
- Wrong password → user sees "Invalid credentials"; log `auth_failure: user_id=123, reason=invalid_password`
- No such user → user sees "Invalid credentials"; log `auth_failure: email=[redacted], reason=user_not_found`

Never log raw credentials, full email, or PII in error details — see `sensitive_data.md` for masking rules.

---

## Request ID Propagation

Every request must carry a unique `X-Request-ID` header for correlation across logs, admin panels, and error reports:

- If the client sends `X-Request-ID`: validate format (UUID or printable ASCII ≤ 128 chars), use it
- If absent: generate a UUID v4 server-side
- Echo back in every response: `X-Request-ID: {id}`
- Include `request_id` in every structured log line for this request
- Include `request_id` in error response bodies so users can reference it in bug reports

---

## Content Negotiation

| Condition | Response format |
|-----------|----------------|
| `Accept: application/json` | JSON |
| `Accept: text/plain` | Plain text (raw data, no HTML conversion) |
| `.txt` extension on API route | Plain text |
| Non-interactive client detected (curl, wget, etc.) | Plain text |
| Default for `/api/**` | JSON |
| Default for `/**` (frontend) | HTML (smart detection handles CLI → text) |

The negotiation priority for API routes: `.txt` extension → `Accept: application/json` → `Accept: text/plain` → default (JSON).

**Frontend routes** use smart client detection — curl/wget automatically get formatted text without needing `.txt` or an `Accept` header.

---

## Middleware Ordering

Apply middleware in this order (innermost = earliest to run):

```
// 4 — mark trusted IPs (bypasses blocklist/rate/geoip, not auth)
AllowlistMiddleware
// 5 — reject known-bad IPs/domains
BlocklistMiddleware
// 6 — rate limit by IP and endpoint
RateLimitMiddleware
// 7 — country block/allow (signal, not sole gate)
GeoIPMiddleware
// 8+ — authentication
AuthMiddleware
// 9+ — authorization / RBAC
AuthorizationMiddleware
// inject/echo X-Request-ID (runs before auth)
RequestIDMiddleware
// access log (runs after request ID is set)
LoggingMiddleware
```

Notes:
- Allowlisted IPs bypass blocklist, rate limiting, and GeoIP — they do NOT bypass auth/authz
- GeoIP is a signal layer — never the last line of defense
- RequestID middleware runs early so every log line has an ID

---

## API-First Rule

The API is the source of truth. Every user-facing feature that exists in the API must also have a working frontend route, and every frontend form must submit to the API. No feature is "API-only" for user-facing functionality — if a user can do it in the API they can do it in the browser.

Exceptions (API-only by design):
- Agent/CLI endpoints (`/api/{api_version}/*/agents/*`)
- Cluster node-to-node endpoints

---

## What Not to Do

- Never keep legacy/deprecated endpoint code "for backward compatibility" — delete old routes when they change
- Never add new routes without updating Swagger/OpenAPI annotations or GraphQL schema
- Never return `200 OK` for an error — use the correct 4xx/5xx status
- Never omit `Content-Type` — set it on every response
- Never reflect the `Origin` header directly as `Access-Control-Allow-Origin` without allowlist validation
- Never put business logic in middleware — middleware is cross-cutting concerns only
