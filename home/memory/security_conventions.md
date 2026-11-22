---
name: Security conventions
description: Enumeration mitigation, GeoIP, CVE/dependency scanning, blocklists, SECURITY.md rules, protected host paths, destructive-op/systemctl/kill gates, and memory safety — operational security for server and library projects
type: user
---

## Enumeration Mitigation

**The goal:** an attacker who probes your auth surface learns nothing about which accounts exist, how many exist, or what your ID scheme looks like.

### Identical responses for auth failures

Both "wrong password" and "no such user" states MUST return the same user-visible message and the same HTTP status:

| Error Type | User Sees | Log Contains |
|------------|-----------|--------------|
| Login — wrong password | "Invalid credentials" | `auth_failure: user_id=123, reason=invalid_password` |
| Login — no such user | "Invalid credentials" | `auth_failure: email=[redacted], reason=user_not_found` |
| Password reset — email not registered | "If an account exists, a reset email has been sent" | `password_reset: email=[redacted], reason=user_not_found` |
| Account lookup / profile fetch | 404 only when the caller is the owner or an admin | `authz_failure: user_id=..., resource=profile` |

Rules:
- **Never reveal to users:** whether a username/email exists, database structure, internal IPs/hostnames, stack traces, dependency versions, or the specific reason for auth failure
- **Constant-time comparison** — use `crypto/subtle.ConstantTimeCompare` (Go) or `subtle::ConstantTimeEq` (Rust) for credential checks; timing differences can confirm existence even when messages are identical
- **Opaque IDs** — prefer UUIDs (v4 or v7) over sequential integers for any user-visible entity ID; sequential IDs enumerate record counts and insertion order

### Rate limiting on auth-adjacent endpoints

Apply rate limits to every endpoint that reveals account state or touches credentials. Defaults — all configurable in `IDEA.md` per project:

| Endpoint | Default Limit | Window | Response |
|----------|--------------|--------|----------|
| Login attempts | 5 | 15 min | 429 + lockout |
| Password reset requests | 3 | 1 hour | 429 + silent (no email hint) |
| Registration | 5 | 1 hour | 429 |
| File upload | 10 | 1 hour | 429 |
| API (unauthenticated) | Configurable | 1 min | 429 + Retry-After |
| API (authenticated) | Configurable | 1 min | 429 + Retry-After |

- Always include a `Retry-After` header (seconds) on 429 responses
- Silent mode for password reset: never confirm or deny whether an email was sent; always return the same message
- CAPTCHA: apply only after N consecutive failures, never on first try

---

## GeoIP

GeoIP is a **risk signal** — a hint that helps layer defense. It is never the sole access control.

**Why not sole control:** VPNs and proxies trivially bypass country checks. GeoIP is meaningful when combined with other signals (failed auth, unusual patterns, known bad ASNs), not as a standalone gate.

### Database

| Field | Value |
|-------|-------|
| Source | [ip-location-db](https://github.com/sapics/ip-location-db) — GitHub Releases (mixed licenses: PDDL, CC BY 4.0, CC BY-SA 4.0) |
| Formats | ASN (`.mmdb`), country (`.mmdb`), city (`.mmdb` — IPv4/IPv6 split only) |
| Storage path | `{data_dir}/security/geoip/` |
| Update cadence | Daily (PDDL), monthly (CC BY 4.0), twice weekly (GeoLite2/CC BY-SA 4.0) |
| On first run | Download databases before serving any GeoIP-dependent request |

MMDB files are downloaded from GitHub Releases. The npm/jsDelivr distribution was deprecated June 18, 2026. Base URL:

```
https://github.com/sapics/ip-location-db/releases/download/latest/{filename}
```

Representative files (all tiers, all enabled by default):

```
# Country — PDDL (daily, no attribution)
user-country.mmdb        server-country.mmdb        iptoasn-country.mmdb
# Country — CC BY 4.0 (monthly, credit: DB-IP.com)
dbip-country.mmdb
# Country — GeoLite2/CC BY-SA 4.0 (twice weekly; free redistribution, no MaxMind account)
geolite2-country.mmdb

# City — CC BY 4.0 (monthly; IPv4 and IPv6 separate — no combined MMDB available)
dbip-city-ipv4.mmdb      dbip-city-ipv6.mmdb
# City — GeoLite2/CC BY-SA 4.0 (twice weekly)
geolite2-city-ipv4.mmdb  geolite2-city-ipv6.mmdb

# ASN — PDDL (daily, no attribution)
origin-asn.mmdb          iptoasn-asn.mmdb
# ASN — CC BY 4.0 (monthly, credit: DB-IP.com)
dbip-asn.mmdb
# ASN — GeoLite2/CC BY-SA 4.0 (twice weekly)
geolite2-asn.mmdb
```

### Middleware order

GeoIP applies **after** the allowlist. Allowlisted IPs bypass blocklist, rate limit, and GeoIP — they do NOT bypass authentication or authorization.

```
Allowlist(4) → RateLimit(6) → GeoIP(7) → Auth(8+)
```

Numbers match a priority-ordered middleware chain; adapt to your framework's conventions.

### Configuration

- `deny_countries`: ISO 3166-1 alpha-2 list — block these countries
- `allow_countries`: whitelist mode — only allow these countries (overrides deny)
- Both default to empty (off); opt-in from admin panel or config file
- Document the active policy in `{project_dir}/IDEA.md` for any production deployment that uses country blocking

### Privacy

IP-derived location is **PII under GDPR** and similar regulations in most jurisdictions:
- Never log a user's resolved country, city, or ASN alongside their user ID or email — treat it as transient signal only
- Do not persist IP-to-location mappings beyond the current request unless explicitly required and documented in `IDEA.md`
- Geo data used for blocking: log the block event (`geoip_block: ip=[redacted], country=XX`) but do not retain a location history per user

### Go Implementation

**Do NOT use `geoip2-golang`** (`github.com/oschwald/geoip2-golang`) with ip-location-db files. That library enforces an allowlist of MaxMind-branded `database_type` strings (`GeoLite2-ASN`, `GeoIP2-City`, etc.). ip-location-db uses its own type strings — `geoip2.Open()` returns `InvalidDatabaseError`.

**Use `maxminddb-golang`** (`github.com/oschwald/maxminddb-golang`) directly — the underlying low-level library with no type restriction.

#### `database_type` strings (embedded in the MMDB binary)

| File pattern | `database_type` |
|---|---|
| `*-asn-ipv4.mmdb` | `asn ipv4` |
| `*-asn-ipv6.mmdb` | `asn ipv6` |
| `*-asn.mmdb` (combined) | `asn ipvAll` |
| `*-country-ipv4.mmdb` | `country ipv4` |
| `*-country-ipv6.mmdb` | `country ipv6` |
| `*-country.mmdb` (combined) | `country ipvAll` |
| `*-city-ipv4.mmdb` | `city ipv4` |
| `*-city-ipv6.mmdb` | `city ipv6` |

#### Go struct definitions (tag names match actual MMDB field names)

```go
import "github.com/oschwald/maxminddb-golang"

// ASN lookup
type ASNRecord struct {
    ASN uint32 `maxminddb:"autonomous_system_number"`
    Org string `maxminddb:"autonomous_system_organization"`
}

// Country lookup
type CountryRecord struct {
    // ISO 3166-1 alpha-2
    CountryCode string `maxminddb:"country_code"`
}

// City lookup — all fields are present; empty string when not populated
type CityRecord struct {
    City        string  `maxminddb:"city"`
    CountryCode string  `maxminddb:"country_code"`
    Latitude    float64 `maxminddb:"latitude"`
    Longitude   float64 `maxminddb:"longitude"`
    Postcode    string  `maxminddb:"postcode"`
    // region / province
    State1      string  `maxminddb:"state1"`
    // sub-region
    State2      string  `maxminddb:"state2"`
    Timezone    string  `maxminddb:"timezone"`
}
```

#### Usage pattern

```go
db, err := maxminddb.Open(path)
if err != nil {
    return fmt.Errorf("open geoip db: %w", err)
}
defer db.Close()

ip := net.ParseIP("8.8.8.8")

var record ASNRecord
if err := db.Lookup(ip, &record); err != nil {
    return fmt.Errorf("geoip lookup: %w", err)
}
// record.ASN == 15169, record.Org == "Google LLC"
```

Use separate `db` handles for IPv4 and IPv6 files when splitting by protocol, or the combined `asn.mmdb` / `country.mmdb` for both. The combined files accept both address families.

---

## CVE / Dependency Scanning

### Pre-flight before adding a dependency

Before adding any new third-party dependency, check its vulnerability status:

| Ecosystem | Command |
|-----------|---------|
| Go | `govulncheck ./...` (run inside Docker per Go conventions) |
| Rust | `cargo audit` (run inside Docker per Rust conventions) |
| Node | `npm audit` |
| Container images | `trivy image {image}:{tag}` |

Do not add a dependency with an unpatched critical or high CVE. If no unaffected version exists, document the decision and the mitigating controls in `{project_dir}/IDEA.md`.

### Pre-commit lint gate

Run the vulnerability scanner as part of the commit pre-flight (alongside the lint gate):
- Go: `govulncheck ./...` must exit 0
- Rust: `cargo audit` must exit 0
- Never commit with a known critical/high CVE in direct dependencies

### Database storage

| Database | Storage path | Source | Cadence |
|----------|-------------|--------|---------|
| NVD/NIST CVE feeds | `{data_dir}/security/cve/` | NIST NVD | Daily |
| Trivy DB | `{data_dir}/security/trivy/` | `ghcr.io/aquasecurity/trivy-db` | Daily |
| IP Blocklists | `{data_dir}/security/blocklists/` | Configurable per project | Daily |

Update all security databases on a built-in scheduler. Never depend on host cron or systemd timers.

---

## IP/Domain Blocklists

Blocklists complement rate limiting and GeoIP — they block known-bad IPs and domains outright:

- Storage: `{data_dir}/security/blocklists/` — separate files for IP and domain lists
- Sources: configurable per project; document chosen feeds in `IDEA.md`
- Update cadence: daily, via built-in scheduler
- Freshness: no per-source age field; every source shares one fixed `max_age` of 72 hours (three missed daily runs); past it the health check reports `degraded` (never `error`) and the last good copy stays in use
- Middleware order: Blocklist check runs after Allowlist (allowlisted IPs are not blocked) and before RateLimit and GeoIP
- On hit: return 403 with a generic message; log `blocklist_hit: ip=..., list=...` at INFO level

---

## SECURITY.md for Public Repos

Every public-facing repo MUST have `.github/SECURITY.md` defining:

- Supported versions or the supported release policy
- The security reporting path — GitHub private vulnerability reporting (`https://github.com/{project_org}/{project_name}/security/advisories/new`, the repo's Security tab → "Report a vulnerability") is the PRIMARY channel; the security email is a secondary/CC contact only, never the main way. NOT a public issue tracker
- That vulnerabilities MUST NOT be filed as public bug reports
- Expected disclosure/response timeline (e.g. acknowledge within 48h, patch within 90 days)
- Links to `/.well-known/security.txt` and the project's contact page when those features exist

CODEOWNERS MUST list explicit owners for security-sensitive paths: workflows, Dockerfile/release files, auth/crypto/update code.

---

## Security by Design

Security is first-class from day one — never bolted on after. It must also be user-friendly: friction-free for honest users, hard for attackers.

- **Secure default** — the safe path is the easy path. Insecure options require explicit opt-in; never make the user work harder to be secure
- **Fail closed** — when in doubt, deny and explain clearly; never silently allow
- **Least privilege** — request only the permissions actually needed; drop them as soon as they are no longer needed
- **Explicit trust boundaries** — document what is trusted (authenticated session, signed payload, internal network) and what is not; never assume
- **No security through obscurity** — assume the attacker knows your code, your schema, and your algorithm choices; security must hold even so
- **Defense in depth** — no single control is the last line; layer authentication, authorization, input validation, output encoding, and rate limiting independently
- **No security theater** — do not impose friction that punishes honest users without meaningfully stopping attackers (e.g. forced password rotation on a schedule unrelated to breach, CAPTCHA on low-risk flows, MFA on non-sensitive pages)
- **Clear security errors** — when a request is blocked or fails a security check, tell the user what happened and what to do next; never return a bare 403 or "access denied" with no context
- **Password hashing: Argon2id only** — never bcrypt, never scrypt, never MD5/SHA for passwords; tuning: time=3, memory=64MiB, threads=4, keyLen=32
- **Audit log security-relevant events** — auth success/failure, permission changes, admin actions, data exports; logs are append-only and never contain raw credentials

---

## Template hardening rules

Cross-project rules the shape templates (go/rust `SERVER.md`) carry; details live there.

- **Private paths** — `server.yml`, `secrets.yml`, `yaml.d/` and other private dirs/files are `0600` (files) / `0700` (dirs), enforced before the config is first read (shape template: PART 8, "Directory Validation Rules")
- **Generated secrets** — written to `secrets.yml` atomically at `0600`; the audit log records the key name only; never synced across a cluster (shape template: "Secrets File")
- **systemd unit** — `ProtectSystem=true`, never `full`/`strict`, so `/etc` stays writable for account setup and the privilege drop (shape template: systemd unit)
- **Client IP** — resolve by walking the proxy chain from the right (nearest hop first); the leftmost entry is never trusted alone (shape template: client IP resolution)
- **Contact/report forms** — HTML form posts reject a present `Origin` (or `Referer`) that is not this site; form tokens are single-use; captcha on every anonymous submit (shape template: "Contact form")
- **Connection strings** — a TLS request auto-enables TLS and the certificate is not verified by default; verification is opt-in (shape template: "Connection Strings")

---

## Protected Host Paths

Beyond the Core OS paths floor (`~/.claude/CLAUDE.md`'s "Working Directory & Path Resolution": `/`, `/boot/**`, `/sys/**`, `/proc/**`, `/dev/**`, partition tables, bootloader config), the following also require user confirmation before any write/destructive Bash op — enforced by `protect-host.sh`:

- **Auth-critical files** — `/etc/passwd`, `/etc/shadow`, `/etc/sudoers` (and `/etc/sudoers.d/*`, `/etc/pam.d/*`, `/etc/group`) — corrupting or overwriting these locks out or compromises the host, not just the current project
- **Top-level system directories** — the standard FHS set (`/bin`, `/boot`, `/dev`, `/etc`, `/lib`, `/lib32`, `/lib64`, `/opt`, `/proc`, `/root`, `/run`, `/sbin`, `/srv`, `/sys`, `/usr`, `/var`) — a destructive op (`rm -rf`, `mkfs`, etc.) targeting one of these directly, or any subpath under `/boot`, `/dev`, `/proc`, `/sys` specifically, is never legitimate project work
- **`/sbin`, `/usr/sbin` deletion** — write access to these paths is already established (`project_files.md:37`'s `Dockerfile`-in-root-forbidden table references standard FHS layout); deletion carries the identical host-breaking risk as write and is gated the same way
- **Shell redirects to auth-critical/system-binary paths** — `>`/`>>` targeting any of the paths above is equivalent to a destructive write and gated identically; `/dev/null`, `/dev/std{in,out,err}`, `/dev/tty`, `/dev/fd/N`, `/dev/pts/N` are always safe and exempt
- **`find -delete` / `find -exec rm`** — a `find` invocation whose action deletes matched files is a destructive op regardless of the starting path; gated the same as a direct `rm`

These formalize `protect-host.sh`'s existing enforcement — they are not new restrictions, but the written source of truth the hook implements.

---

## Destructive Operation Gates

- **Temp/cache/build dirs never need confirmation** — `rm -rf` targeting a path under `${TMPDIR:-/tmp}/{project_org}/` (the recognized tempdir structure, see `tempdir_conventions.md`) is disposable and project-scoped; run it directly. Never extends to `/tmp` itself, `/tmp/*`, or any path outside the project's own `{project_org}/` subtree — those still require confirmation
- **`dd`/`shred`/`mkfs*`/`wipefs`/`git reset` are hard-denied, not confirm-gated** — `settings.json`'s `permissions.deny` list blocks these outright with no confirm path; `no-destructive-bypass.sh` enforces this
- **A `git status` deletion is not automatically an error to fix** — `git restore`, `git checkout -- <path>`, and any additive-restore/deploy step (e.g. `install.sh` copying `home/` → `~/.claude/`) undo the user's own uncommitted change. Never run one of these on a file the user didn't ask to have restored just because it shows as deleted/modified — deliberate cleanup (pending regeneration via `bootstrap`) is more likely than damage. Ask first before reverting anything the user didn't report as broken. Exception: the Session Start stash/pull/pop sequence's own `git stash pop` is separately pre-authorized
- **systemctl gate** — `status`/`is-active`/`is-enabled`/`cat`/`show` and `--user` variants are always OK; `restart`/`stop`/`start`/`reload`/`disable`/`enable`/`mask`/`isolate`/`kill` on host services require user confirmation — `isolate` tears down every unit outside the target's dependency tree, and `kill` signals a unit's processes directly, so both carry the same blast-radius risk as `restart`/`stop`. **Exception:** under `~/Projects/local/system/**`, `start`/`stop`/`restart`/`reload`/`reload-or-restart`/`try-restart`/`enable`/`disable`/`reset-failed`/`daemon-reload` are pre-authorized without per-call confirmation; `mask`/`unmask`/`edit`/`set-property`/`isolate`/`kill` still require confirmation everywhere, including in the zone
- **kill scoping** — `kill $PID` only when `$PID` was captured at launch in the current task (`PID=$!`)

---

## Memory Safety

These apply to every line of code in every language:

- `unsafe` (Rust) / `import "unsafe"` (Go) requires a justification comment at the call site and a note in `{project_dir}/IDEA.md`
- Never spawn unbounded goroutines/threads — always cap with a semaphore, worker pool, or context cancellation
- Never spawn processes inside an unthrottled loop — every subprocess spawn must have a concurrency limit
- Never call `ulimit -u unlimited`, `setrlimit(RLIM_INFINITY)`, or equivalent — raise limits to a specific documented ceiling only
- Every network call, DB query, subprocess wait, channel receive, and lock acquisition must have a timeout or deadline — infinite block = eventual hang
- Every opened file, socket, or pipe must be closed — `defer f.Close()` (Go), RAII/`Drop` (Rust), `trap`/explicit close (shell)
- Never `rm -rf "$VAR/"` without a `[ -n "$VAR" ]` guard; never `DROP TABLE` or `DELETE FROM` without a `WHERE`
- Size-cap all untrusted input before buffering — no `ReadAll`/`read_to_string` on an unbounded network stream without a `LimitedReader`/`take()` guard
