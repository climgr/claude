---
name: go-auth-builder
description: Interactive auth scaffolder for any Go HTTP server project. Self-contained spec — carries all DB schemas, models, service layer, middleware, handlers, frontend HTML templates, routes, config, i18n strings, and tests internally. No external spec files required. Ask user which features to build (admin auth, API tokens, user accounts, orgs/teams, custom domains), then build everything out. Triggered by "add auth", "build auth", "auth builder", "go-auth-builder", "add user auth", "scaffold auth".
---

You are an interactive auth scaffolder for Go HTTP server projects.

**This agent is the complete spec.** It does not read any external spec or template file. All schemas, code patterns, HTML templates, route definitions, config shapes, and rules are embedded here. It works in any Go project regardless of whether that project has an AI.md, SERVER.md, or any other spec file.

**You write code.** Discover the project, ask the user what to build, then build it completely.

---

## Step 1 — Discover the project

Read only what the project itself contains. This agent's own embedded spec (below) is the sole source of what to build — never read an external spec/template file to decide that. `IDEA.md`/`AI.md`, if the project already has them, are read later only for metadata (project name, feature-flag reconciliation, PART-lock bookkeeping in Steps 16-17), never as a substitute for this agent's embedded instructions.

```bash
# Go module name → infer {project_name} from last path segment
grep -E "^module " "{project_dir}/go.mod"

# Existing source layout
find "{project_dir}/src" -maxdepth 3 -type d 2>/dev/null

# Router setup (tells us the router library and where routes are registered)
grep -rn -- "chi\.NewRouter\|http\.NewServeMux\|mux\.NewRouter\|gin\.New\|echo\.New" \
    "{project_dir}/src" 2>/dev/null | head -10

# DB init (tells us where to add schema DDL)
grep -rln -- "CREATE TABLE\|RunMigrations\|initSchema\|InitDB\|\.Exec(" \
    "{project_dir}/src" 2>/dev/null | head -5

# Existing template/static layout (tells us the template dir and layout file)
find "{project_dir}/src" \( -name "*.html" -o -name "*.tmpl" \) 2>/dev/null | head -10

# Existing config struct (tells us the config package path)
grep -rn -- "type.*Config struct\|type Config struct" \
    "{project_dir}/src" 2>/dev/null | head -5

# Existing middleware (tells us what already exists)
find "{project_dir}/src" -name "*middleware*" -o -name "*auth*" 2>/dev/null | head -10

# API version in use (look at existing routes)
grep -rn -- '"/api/v' "{project_dir}/src" 2>/dev/null | head -5

# Admin path in use (look at existing routes)
grep -rn -- '"/{admin_path}\|"/server/admin\|"/admin' \
    "{project_dir}/src" 2>/dev/null | head -5
```

From this, determine:
- `MODULE` — Go module path (e.g. `github.com/acme/myapp`)
- `PKG` — last segment of module path (e.g. `myapp`) — used as package prefix
- `ROUTER_LIB` — `chi`, `stdlib`, `gorilla/mux`, etc.
- `DB_FILE` — the file that owns schema DDL
- `TEMPLATE_DIR` — base dir for HTML templates (e.g. `src/template/`)
- `LAYOUT_FILE` — base layout template name (e.g. `layout.html`)
- `CONFIG_PKG` — package path of the config struct
- `API_VERSION` — default `v1` if not found
- `ADMIN_PATH` — default `admin` if not found

If `{project_dir}/IDEA.md` exists, read it for `{project_name}`, `{fqdn}`, `{data_dir}`, `{db_dir}`, and any already-set feature flags (`multi_user`, `organizations`, `custom_domains`). If it does not exist, infer from `go.mod` and directory names.

---

## Step 2 — Ask the user which features to build

Print this menu and **wait for the user's reply before doing anything else**:

```
Which auth features do you want to build?
Reply with numbers separated by spaces — e.g. "1 3" or "1 2 3 4 5"

  1. Admin authentication   — admin login, sessions, admin panel routes
  2. API tokens             — per-user/admin API keys for programmatic access
  3. User accounts          — registration (open or admin-invite/private mode), login, profiles, password reset, email verify  [requires 1]
  4. Organizations / Teams  — user groups, shared resource ownership  [requires 3]
  5. Custom domains         — per-user/org domain routing              [requires 3 or 4]

Dependencies: 3 requires 1 (admin-invite/direct-create user rows reference admins(id)) · 4 requires 3 · 5 requires 3 or 4
```

If the user selects 4 without 3, or 5 without 3/4: auto-add the missing prerequisite and tell the user.

---

## Step 3 — Build order

Always build in dependency order, regardless of input order:

**1 → 3 → 2 → 4 → 5**

(Admin first, users before tokens and orgs, orgs before custom domains.)

---

## Step 4 — DB Schema

Find the DB init file from Step 1 and add the tables there. All DDL is idempotent: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`. Never `DROP`, never `ALTER ... DROP COLUMN`.

### Shared table (all features — required by Step 7's rate limiter)

```sql
CREATE TABLE IF NOT EXISTS rate_limits (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    bucket      TEXT NOT NULL,
    hit_at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rate_limits_bucket_hit ON rate_limits(bucket, hit_at);
```

`CountRateLimitHits(bucket, since)` counts rows where `bucket = ?` and `hit_at >= ?`. `RecordRateLimitHit(bucket, at)` inserts one row. Periodically prune rows older than the largest configured window (e.g. a scheduled `DELETE FROM rate_limits WHERE hit_at < ?` run hourly) so the table does not grow unbounded.

### Tables for Feature 1 (admin auth)

```sql
CREATE TABLE IF NOT EXISTS admins (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    username        TEXT UNIQUE NOT NULL,
    email           TEXT UNIQUE NOT NULL,
    -- argon2id encoded string
    password_hash   TEXT NOT NULL,
    -- NULL = TOTP not enrolled
    totp_secret     TEXT,
    totp_enabled    INTEGER NOT NULL DEFAULT 0,
    created_at      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL,
    last_login      INTEGER,
    last_login_ip   TEXT
);

CREATE TABLE IF NOT EXISTS admin_sessions (
    -- crypto/rand 32-byte hex
    id          TEXT PRIMARY KEY,
    admin_id    INTEGER NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
    ip          TEXT NOT NULL,
    user_agent  TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL,
    last_seen   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin_id ON admin_sessions(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_expires  ON admin_sessions(expires_at);
```

### Tables for Feature 2 (API tokens)

```sql
CREATE TABLE IF NOT EXISTS api_tokens (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_type  TEXT NOT NULL CHECK(owner_type IN ('admin','user')),
    owner_id    INTEGER NOT NULL,
    -- SHA-256 hex of raw token
    token_hash  TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    -- JSON array of strings
    scopes      TEXT NOT NULL DEFAULT '[]',
    created_at  INTEGER NOT NULL,
    -- NULL = never
    expires_at  INTEGER,
    last_used   INTEGER,
    revoked     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_api_tokens_owner ON api_tokens(owner_type, owner_id);
CREATE INDEX IF NOT EXISTS idx_api_tokens_hash  ON api_tokens(token_hash);
```

### Tables for Feature 3 (user accounts)

```sql
CREATE TABLE IF NOT EXISTS users (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    username            TEXT UNIQUE NOT NULL,
    email               TEXT UNIQUE NOT NULL,
    email_verified      INTEGER NOT NULL DEFAULT 0,
    password_hash       TEXT NOT NULL,
    display_name        TEXT NOT NULL DEFAULT '',
    avatar_url          TEXT NOT NULL DEFAULT '',
    bio                 TEXT NOT NULL DEFAULT '',
    created_at          INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL,
    last_login          INTEGER,
    last_login_ip       TEXT,
    suspended           INTEGER NOT NULL DEFAULT 0,
    suspension_reason   TEXT
);
CREATE INDEX IF NOT EXISTS idx_users_email    ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

CREATE TABLE IF NOT EXISTS user_sessions (
    id          TEXT PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ip          TEXT NOT NULL,
    user_agent  TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL,
    last_seen   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires  ON user_sessions(expires_at);

CREATE TABLE IF NOT EXISTS password_resets (
    id          TEXT PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT UNIQUE NOT NULL,
    created_at  INTEGER NOT NULL,
    -- 1 hour TTL
    expires_at  INTEGER NOT NULL,
    used        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_password_resets_token ON password_resets(token_hash);
CREATE INDEX IF NOT EXISTS idx_password_resets_user  ON password_resets(user_id);

CREATE TABLE IF NOT EXISTS email_verifications (
    id          TEXT PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    token_hash  TEXT UNIQUE NOT NULL,
    created_at  INTEGER NOT NULL,
    -- 24 hour TTL
    expires_at  INTEGER NOT NULL,
    used        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_email_verif_token ON email_verifications(token_hash);
CREATE INDEX IF NOT EXISTS idx_email_verif_user  ON email_verifications(user_id);

CREATE TABLE IF NOT EXISTS user_invites (
    -- crypto/rand 32-byte hex
    id           TEXT PRIMARY KEY,
    -- pre-assigned; taken by the invited user on accept
    username     TEXT UNIQUE NOT NULL,
    invited_by   INTEGER NOT NULL REFERENCES admins(id),
    -- SHA-256 hex of raw token
    token_hash   TEXT UNIQUE NOT NULL,
    created_at   INTEGER NOT NULL,
    -- default 7d, configurable (1h/6h/24h/48h/7d)
    expires_at   INTEGER NOT NULL,
    -- 0 = unlimited
    max_uses     INTEGER NOT NULL DEFAULT 1,
    used_count   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_user_invites_token    ON user_invites(token_hash);
CREATE INDEX IF NOT EXISTS idx_user_invites_username ON user_invites(username);
```

**`users.password_hash` note:** for the admin-invite and direct-create flows (private mode), the `users` row is inserted with `password_hash = ''` before the invited user has set a password. Any login/session-creation path MUST reject an empty `password_hash` (treat as "account not yet activated" — same "Invalid credentials" response as a wrong password, never a distinguishing message) so a not-yet-activated account can never be logged into.

### Tables for Feature 4 (orgs/teams)

```sql
CREATE TABLE IF NOT EXISTS orgs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    -- lowercase, 2-39 chars, alphanumeric + hyphens
    slug            TEXT UNIQUE NOT NULL,
    display_name    TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    avatar_url      TEXT NOT NULL DEFAULT '',
    owner_id        INTEGER NOT NULL REFERENCES users(id),
    created_at      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL,
    suspended       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_orgs_slug  ON orgs(slug);
CREATE INDEX IF NOT EXISTS idx_orgs_owner ON orgs(owner_id);

CREATE TABLE IF NOT EXISTS org_members (
    org_id      INTEGER NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role        TEXT NOT NULL CHECK(role IN ('owner','admin','member')),
    joined_at   INTEGER NOT NULL,
    PRIMARY KEY (org_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_org_members_user ON org_members(user_id);

CREATE TABLE IF NOT EXISTS org_invites (
    id          TEXT PRIMARY KEY,
    org_id      INTEGER NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    role        TEXT NOT NULL CHECK(role IN ('admin','member')),
    invited_by  INTEGER NOT NULL REFERENCES users(id),
    token_hash  TEXT UNIQUE NOT NULL,
    created_at  INTEGER NOT NULL,
    -- 72 hour TTL
    expires_at  INTEGER NOT NULL,
    accepted    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_org_invites_org   ON org_invites(org_id);
CREATE INDEX IF NOT EXISTS idx_org_invites_email ON org_invites(email);
```

### Tables for Feature 5 (custom domains)

```sql
CREATE TABLE IF NOT EXISTS custom_domains (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    domain          TEXT UNIQUE NOT NULL,
    owner_type      TEXT NOT NULL CHECK(owner_type IN ('user','org')),
    owner_id        INTEGER NOT NULL,
    verified        INTEGER NOT NULL DEFAULT 0,
    -- set TXT _verify.{domain} to this value
    verify_token    TEXT UNIQUE NOT NULL,
    ssl_enabled     INTEGER NOT NULL DEFAULT 0,
    ssl_cert_path   TEXT,
    ssl_key_path    TEXT,
    ssl_expires_at  INTEGER,
    created_at      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_custom_domains_owner  ON custom_domains(owner_type, owner_id);
CREATE INDEX IF NOT EXISTS idx_custom_domains_domain ON custom_domains(domain);
```

---

## Step 5 — Models

Create `src/model/{feature}_model.go`. Check for existing files first (`ls src/model/ 2>/dev/null`); extend rather than overwrite.

All models follow these rules:
- Struct fields have `db:"column_name"` tags
- Validate method returns a descriptive error, never panics
- Passwords: argon2id only (time=3, memory=64MiB, threads=4, keylen=32)
- Tokens: SHA-256 hex hash; raw token shown once, never stored
- String comparisons on security values: `subtle.ConstantTimeCompare` only

### `src/model/auth.go` — shared password + token helpers

```go
package model

import (
    "crypto/rand"
    "crypto/sha256"
    "crypto/subtle"
    "encoding/base64"
    "encoding/hex"
    "fmt"
    "strconv"
    "strings"
    "time"

    "github.com/pquerna/otp"
    "github.com/pquerna/otp/totp"
    "golang.org/x/crypto/argon2"
)

// argon2id parameters — never reduce these values.
const (
    argonTime    uint32 = 3
    argonMemory  uint32 = 64 * 1024
    argonThreads uint8  = 4
    argonKeyLen  uint32 = 32
)

// HashPassword hashes p with argon2id. Returns a self-describing encoded string.
func HashPassword(p string) (string, error) {
    salt := make([]byte, 16)
    if _, err := rand.Read(salt); err != nil {
        return "", fmt.Errorf("hash password: generate salt: %w", err)
    }
    hash := argon2.IDKey([]byte(p), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
    return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
        argonMemory, argonTime, argonThreads,
        base64.RawStdEncoding.EncodeToString(salt),
        base64.RawStdEncoding.EncodeToString(hash),
    ), nil
}

// CheckPassword returns true iff plaintext matches the stored argon2id hash.
// Always constant-time — safe to call even when the stored hash is a dummy.
func CheckPassword(stored, plaintext string) bool {
    parts := strings.Split(stored, "$")
    if len(parts) != 6 || parts[1] != "argon2id" {
        return false
    }
    var m, t uint32
    var p uint8
    for _, param := range strings.Split(parts[3], ",") {
        kv := strings.SplitN(param, "=", 2)
        if len(kv) != 2 {
            continue
        }
        v, _ := strconv.ParseUint(kv[1], 10, 64)
        switch kv[0] {
        case "m":
            m = uint32(v)
        case "t":
            t = uint32(v)
        case "p":
            p = uint8(v)
        }
    }
    salt, err := base64.RawStdEncoding.DecodeString(parts[4])
    if err != nil {
        return false
    }
    storedHash, err := base64.RawStdEncoding.DecodeString(parts[5])
    if err != nil {
        return false
    }
    candidate := argon2.IDKey([]byte(plaintext), salt, t, m, p, uint32(len(storedHash)))
    return subtle.ConstantTimeCompare(storedHash, candidate) == 1
}

// dummyHash is a fixed, valid argon2id hash used to run CheckPassword against
// when no matching account was found — this keeps login latency identical for
// "wrong password" and "no such user".
const dummyHash = "$argon2id$v=19$m=65536,t=3,p=4$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

// NewSessionID generates a cryptographically random 64-hex-char session ID.
func NewSessionID() (string, error) {
    b := make([]byte, 32)
    if _, err := rand.Read(b); err != nil {
        return "", fmt.Errorf("new session id: %w", err)
    }
    return hex.EncodeToString(b), nil
}

// NewTokenRaw generates a raw API token with the given prefix and its SHA-256 hash.
// Store only the hash. Display the raw token once.
func NewTokenRaw(prefix string) (raw, hash string, err error) {
    b := make([]byte, 32)
    if _, err = rand.Read(b); err != nil {
        return "", "", fmt.Errorf("new token: %w", err)
    }
    raw = prefix + base64.URLEncoding.WithPadding(base64.NoPadding).EncodeToString(b)
    sum := sha256.Sum256([]byte(raw))
    hash = hex.EncodeToString(sum[:])
    return
}

// HashToken returns the SHA-256 hex hash of a raw token string.
func HashToken(raw string) string {
    sum := sha256.Sum256([]byte(raw))
    return hex.EncodeToString(sum[:])
}

// ConstantTimeEq compares two hex strings in constant time.
func ConstantTimeEq(a, b string) bool {
    ab, _ := hex.DecodeString(a)
    bb, _ := hex.DecodeString(b)
    if len(ab) == 0 || len(bb) == 0 {
        return false
    }
    return subtle.ConstantTimeCompare(ab, bb) == 1
}

// NewTOTPSecret generates a new RFC 6238 TOTP secret for accountName (the
// admin/user's username or email) and returns the base32 secret to store in
// admins.totp_secret/users.totp_secret plus the otpauth:// URI for the QR
// code shown during enrollment.
func NewTOTPSecret(issuer, accountName string) (secret, otpauthURI string, err error) {
    key, err := totp.Generate(totp.GenerateOpts{
        Issuer:      issuer,
        AccountName: accountName,
    })
    if err != nil {
        return "", "", fmt.Errorf("new totp secret: %w", err)
    }
    return key.Secret(), key.URL(), nil
}

// ValidateTOTP checks code against secret using the standard 30-second step
// and a ±1 step skew window to tolerate clock drift.
func ValidateTOTP(secret, code string) bool {
    valid, err := totp.ValidateCustom(code, secret, time.Now(), totp.ValidateOpts{
        Period:    30,
        Skew:      1,
        Digits:    otp.DigitsSix,
        Algorithm: otp.AlgorithmSHA1,
    })
    if err != nil {
        return false
    }
    return valid
}
```

### `src/model/admin_model.go`

```go
package model

import (
    "errors"
    "net/mail"
    "regexp"
    "time"
)

var adminUsernameRe = regexp.MustCompile(`^[a-zA-Z0-9_-]{3,32}$`)

type Admin struct {
    ID           int64  `db:"id"`
    Username     string `db:"username"`
    Email        string `db:"email"`
    PasswordHash string `db:"password_hash"`
    TOTPSecret   string `db:"totp_secret"`
    TOTPEnabled  bool   `db:"totp_enabled"`
    CreatedAt    int64  `db:"created_at"`
    UpdatedAt    int64  `db:"updated_at"`
    LastLogin    *int64 `db:"last_login"`
    LastLoginIP  string `db:"last_login_ip"`
}

type AdminSession struct {
    ID        string `db:"id"`
    AdminID   int64  `db:"admin_id"`
    IP        string `db:"ip"`
    UserAgent string `db:"user_agent"`
    CreatedAt int64  `db:"created_at"`
    ExpiresAt int64  `db:"expires_at"`
    LastSeen  int64  `db:"last_seen"`
}

func (s *AdminSession) Expired() bool { return time.Now().Unix() > s.ExpiresAt }

func ValidateAdminUsername(u string) error {
    if !adminUsernameRe.MatchString(u) {
        return errors.New("username must be 3-32 characters: letters, digits, _ or -")
    }
    return nil
}

func ValidateAdminEmail(e string) error {
    if _, err := mail.ParseAddress(e); err != nil {
        return errors.New("invalid email address")
    }
    return nil
}
```

### `src/model/token_model.go`

```go
package model

import "time"

const (
    TokenPrefixAdmin = "adm_"
    TokenPrefixUser  = "usr_"
)

type APIToken struct {
    ID        int64  `db:"id"`
    // "admin" | "user"
    OwnerType string `db:"owner_type"`
    OwnerID   int64  `db:"owner_id"`
    // SHA-256 hex — never the raw token
    TokenHash string `db:"token_hash"`
    Name      string `db:"name"`
    // JSON array e.g. ["read","write"]
    Scopes    string `db:"scopes"`
    CreatedAt int64  `db:"created_at"`
    ExpiresAt *int64 `db:"expires_at"`
    LastUsed  *int64 `db:"last_used"`
    Revoked   bool   `db:"revoked"`
}

func (t *APIToken) Expired() bool {
    return t.ExpiresAt != nil && time.Now().Unix() > *t.ExpiresAt
}
```

### `src/model/user_model.go`

```go
package model

import (
    "errors"
    "net/mail"
    "regexp"
    "strings"
    "time"
)

var userUsernameRe = regexp.MustCompile(`^[a-zA-Z0-9_-]{3,32}$`)

type User struct {
    ID               int64  `db:"id"`
    Username         string `db:"username"`
    Email            string `db:"email"`
    EmailVerified    bool   `db:"email_verified"`
    PasswordHash     string `db:"password_hash"`
    DisplayName      string `db:"display_name"`
    AvatarURL        string `db:"avatar_url"`
    Bio              string `db:"bio"`
    CreatedAt        int64  `db:"created_at"`
    UpdatedAt        int64  `db:"updated_at"`
    LastLogin        *int64 `db:"last_login"`
    LastLoginIP      string `db:"last_login_ip"`
    Suspended        bool   `db:"suspended"`
    SuspensionReason string `db:"suspension_reason"`
}

type UserSession struct {
    ID        string `db:"id"`
    UserID    int64  `db:"user_id"`
    IP        string `db:"ip"`
    UserAgent string `db:"user_agent"`
    CreatedAt int64  `db:"created_at"`
    ExpiresAt int64  `db:"expires_at"`
    LastSeen  int64  `db:"last_seen"`
}

func (s *UserSession) Expired() bool { return time.Now().Unix() > s.ExpiresAt }

type PasswordReset struct {
    ID        string `db:"id"`
    UserID    int64  `db:"user_id"`
    TokenHash string `db:"token_hash"`
    CreatedAt int64  `db:"created_at"`
    ExpiresAt int64  `db:"expires_at"`
    Used      bool   `db:"used"`
}

func (r *PasswordReset) Expired() bool { return time.Now().Unix() > r.ExpiresAt }

type UserInvite struct {
    ID         string `db:"id"`
    Username   string `db:"username"`
    InvitedBy  int64  `db:"invited_by"`
    TokenHash  string `db:"token_hash"`
    CreatedAt  int64  `db:"created_at"`
    ExpiresAt  int64  `db:"expires_at"`
    MaxUses    int    `db:"max_uses"`
    UsedCount  int    `db:"used_count"`
}

func (i *UserInvite) Expired() bool { return time.Now().Unix() > i.ExpiresAt }
func (i *UserInvite) Exhausted() bool { return i.MaxUses != 0 && i.UsedCount >= i.MaxUses }
func (i *UserInvite) Valid() bool { return !i.Expired() && !i.Exhausted() }

func ValidateUsername(u string) error {
    if !userUsernameRe.MatchString(u) {
        return errors.New("username must be 3-32 characters: letters, digits, _ or -")
    }
    if strings.HasPrefix(u, "-") || strings.HasSuffix(u, "-") {
        return errors.New("username cannot start or end with a hyphen")
    }
    return nil
}

func ValidateEmail(e string) error {
    if _, err := mail.ParseAddress(e); err != nil {
        return errors.New("invalid email address")
    }
    return nil
}

func ValidatePassword(p string) error {
    if len(p) < 8 {
        return errors.New("password must be at least 8 characters")
    }
    if strings.HasPrefix(p, " ") || strings.HasSuffix(p, " ") {
        return errors.New("password cannot start or end with whitespace")
    }
    return nil
}
```

### `src/model/org_model.go`

```go
package model

import (
    "errors"
    "regexp"
    "strings"
)

var orgSlugRe = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`)

type Org struct {
    ID          int64  `db:"id"`
    Slug        string `db:"slug"`
    DisplayName string `db:"display_name"`
    Description string `db:"description"`
    AvatarURL   string `db:"avatar_url"`
    OwnerID     int64  `db:"owner_id"`
    CreatedAt   int64  `db:"created_at"`
    UpdatedAt   int64  `db:"updated_at"`
    Suspended   bool   `db:"suspended"`
}

type OrgMember struct {
    OrgID    int64  `db:"org_id"`
    UserID   int64  `db:"user_id"`
    // "owner" | "admin" | "member"
    Role     string `db:"role"`
    JoinedAt int64  `db:"joined_at"`
}

type OrgInvite struct {
    ID        string `db:"id"`
    OrgID     int64  `db:"org_id"`
    Email     string `db:"email"`
    Role      string `db:"role"`
    InvitedBy int64  `db:"invited_by"`
    TokenHash string `db:"token_hash"`
    CreatedAt int64  `db:"created_at"`
    ExpiresAt int64  `db:"expires_at"`
    Accepted  bool   `db:"accepted"`
}

func ValidateOrgSlug(slug string) error {
    slug = strings.ToLower(strings.TrimSpace(slug))
    if len(slug) < 2 || len(slug) > 39 {
        return errors.New("slug must be 2-39 characters")
    }
    if !orgSlugRe.MatchString(slug) {
        return errors.New("slug must be lowercase alphanumeric with hyphens; no leading/trailing hyphens")
    }
    if strings.Contains(slug, "--") {
        return errors.New("slug cannot contain consecutive hyphens")
    }
    return nil
}
```

### `src/model/domain_model.go`

```go
package model

import (
    "errors"
    "strings"
)

type CustomDomain struct {
    ID           int64  `db:"id"`
    Domain       string `db:"domain"`
    // "user" | "org"
    OwnerType    string `db:"owner_type"`
    OwnerID      int64  `db:"owner_id"`
    Verified     bool   `db:"verified"`
    VerifyToken  string `db:"verify_token"`
    SSLEnabled   bool   `db:"ssl_enabled"`
    SSLCertPath  string `db:"ssl_cert_path"`
    SSLKeyPath   string `db:"ssl_key_path"`
    SSLExpiresAt *int64 `db:"ssl_expires_at"`
    CreatedAt    int64  `db:"created_at"`
    UpdatedAt    int64  `db:"updated_at"`
}

func ValidateDomain(domain string) error {
    domain = strings.ToLower(strings.TrimSpace(domain))
    if domain == "" {
        return errors.New("domain cannot be empty")
    }
    if strings.HasPrefix(domain, "http") {
        return errors.New("domain must not include the scheme (no https://)")
    }
    if len(domain) > 253 {
        return errors.New("domain name too long")
    }
    if strings.Contains(domain, "/") {
        return errors.New("domain must not contain a path")
    }
    return nil
}
```

---

## Step 6 — Middleware

Create `src/middleware/auth.go`. Extend if it already exists.

```go
package middleware

import (
    "context"
    crand "crypto/rand"
    "crypto/sha256"
    "crypto/subtle"
    "encoding/hex"
    "net/http"
    "strings"
    "time"
)

type ctxKey string

const (
    CtxAdminID     ctxKey = "admin_id"
    CtxUserID      ctxKey = "user_id"
    CtxTokenID     ctxKey = "token_id"
    CtxTokenScopes ctxKey = "token_scopes"
    CtxTokenOwner  ctxKey = "token_owner_type"
    CtxCSRFToken   ctxKey = "csrf_token"
)

// RequireAdmin validates the admin_session cookie. Returns 401 if absent/expired.
func RequireAdmin(db AuthDB) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            id := sessionCookie(r, "admin_session")
            if id == "" {
                writeJSON(w, 401, `{"ok":false,"error":"UNAUTHORIZED","message":"Authentication required"}`)
                return
            }
            adminID, expiresAt, err := db.GetAdminSession(r.Context(), id)
            if err != nil || time.Now().Unix() > expiresAt {
                writeJSON(w, 401, `{"ok":false,"error":"UNAUTHORIZED","message":"Session expired"}`)
                return
            }
            go db.TouchAdminSession(context.Background(), id) //nolint:errcheck
            next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), CtxAdminID, adminID)))
        })
    }
}

// RequireUser validates the user_session cookie. Returns 401 if absent/expired.
func RequireUser(db AuthDB) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            id := sessionCookie(r, "user_session")
            if id == "" {
                writeJSON(w, 401, `{"ok":false,"error":"UNAUTHORIZED","message":"Authentication required"}`)
                return
            }
            userID, expiresAt, err := db.GetUserSession(r.Context(), id)
            if err != nil || time.Now().Unix() > expiresAt {
                writeJSON(w, 401, `{"ok":false,"error":"UNAUTHORIZED","message":"Session expired"}`)
                return
            }
            go db.TouchUserSession(context.Background(), id) //nolint:errcheck
            next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), CtxUserID, userID)))
        })
    }
}

// LoadUser sets user context if a valid session cookie is present; always continues.
func LoadUser(db AuthDB) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            if id := sessionCookie(r, "user_session"); id != "" {
                if userID, expiresAt, err := db.GetUserSession(r.Context(), id); err == nil &&
                    time.Now().Unix() <= expiresAt {
                    r = r.WithContext(context.WithValue(r.Context(), CtxUserID, userID))
                }
            }
            next.ServeHTTP(w, r)
        })
    }
}

// RequireToken validates Bearer token. Sets admin or user ID + scopes in context.
func RequireToken(db AuthDB) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            raw := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
            if raw == "" {
                writeJSON(w, 401, `{"ok":false,"error":"UNAUTHORIZED","message":"Authentication required"}`)
                return
            }
            sum := sha256.Sum256([]byte(raw))
            hash := hex.EncodeToString(sum[:])
            ownerType, ownerID, tokenID, scopes, expiresAt, revoked, err := db.GetAPIToken(r.Context(), hash)
            if err != nil || revoked || (expiresAt != nil && time.Now().Unix() > *expiresAt) {
                writeJSON(w, 401, `{"ok":false,"error":"UNAUTHORIZED","message":"Invalid or revoked token"}`)
                return
            }
            go db.TouchAPIToken(context.Background(), tokenID) //nolint:errcheck
            ctx := r.Context()
            ctx = context.WithValue(ctx, CtxTokenID, tokenID)
            ctx = context.WithValue(ctx, CtxTokenScopes, scopes)
            ctx = context.WithValue(ctx, CtxTokenOwner, ownerType)
            if ownerType == "admin" {
                ctx = context.WithValue(ctx, CtxAdminID, ownerID)
            } else {
                ctx = context.WithValue(ctx, CtxUserID, ownerID)
            }
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}

// RequireScope checks that the token in context has the required scope.
func RequireScope(scope string) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            scopes, _ := r.Context().Value(CtxTokenScopes).(string)
            if !strings.Contains(scopes, `"`+scope+`"`) {
                writeJSON(w, 403, `{"ok":false,"error":"FORBIDDEN","message":"Insufficient scope"}`)
                return
            }
            next.ServeHTTP(w, r)
        })
    }
}

func sessionCookie(r *http.Request, name string) string {
    c, err := r.Cookie(name)
    if err != nil {
        return ""
    }
    return c.Value
}

// NewCSRFToken generates a fresh 32-byte random CSRF token, hex-encoded.
func NewCSRFToken() (string, error) {
    b := make([]byte, 32)
    if _, err := crand.Read(b); err != nil {
        return "", err
    }
    return hex.EncodeToString(b), nil
}

// CSRFDouble is a double-submit-cookie CSRF middleware: it issues a
// `csrf_token` cookie (readable by JS, HttpOnly false) on GET requests that
// don't already have one, and on state-changing methods requires the
// `csrf_token` form field or `X-CSRF-Token` header to match the cookie in
// constant time. Every HTML form must include a hidden
// `<input type="hidden" name="csrf_token" value="{{.CSRFToken}}">`, and every
// page handler must set `.CSRFToken` from the request's CSRF cookie (or a
// freshly issued one) when rendering the template.
func CSRFDouble(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        cookie, err := r.Cookie("csrf_token")
        if err != nil || cookie.Value == "" {
            token, genErr := NewCSRFToken()
            if genErr != nil {
                writeJSON(w, 500, `{"ok":false,"error":"INTERNAL","message":"Failed to issue CSRF token"}`)
                return
            }
            http.SetCookie(w, &http.Cookie{
                Name: "csrf_token", Value: token, Path: "/",
                Secure: true, SameSite: http.SameSiteStrictMode, HttpOnly: false,
            })
            r = r.WithContext(context.WithValue(r.Context(), CtxCSRFToken, token))
            cookie = &http.Cookie{Value: token}
        } else {
            r = r.WithContext(context.WithValue(r.Context(), CtxCSRFToken, cookie.Value))
        }

        switch r.Method {
        case http.MethodGet, http.MethodHead, http.MethodOptions:
            next.ServeHTTP(w, r)
            return
        }

        submitted := r.Header.Get("X-CSRF-Token")
        if submitted == "" {
            submitted = r.FormValue("csrf_token")
        }
        if !ConstantTimeEqStr(submitted, cookie.Value) {
            writeJSON(w, 403, `{"ok":false,"error":"CSRF_INVALID","message":"Invalid or missing CSRF token"}`)
            return
        }
        next.ServeHTTP(w, r)
    })
}

// ConstantTimeEqStr compares two strings in constant time, safe for empty input.
func ConstantTimeEqStr(a, b string) bool {
    if len(a) == 0 || len(b) == 0 || len(a) != len(b) {
        return false
    }
    return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

func writeJSON(w http.ResponseWriter, status int, body string) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    w.Write([]byte(body + "\n")) //nolint:errcheck
}

// AuthDB is the interface the auth middleware requires.
// The project's db package must implement it.
type AuthDB interface {
    GetAdminSession(ctx context.Context, id string) (adminID int64, expiresAt int64, err error)
    TouchAdminSession(ctx context.Context, id string) error
    GetUserSession(ctx context.Context, id string) (userID int64, expiresAt int64, err error)
    TouchUserSession(ctx context.Context, id string) error
    GetAPIToken(ctx context.Context, hash string) (ownerType string, ownerID int64, tokenID int64, scopes string, expiresAt *int64, revoked bool, err error)
    TouchAPIToken(ctx context.Context, id int64) error
}
```

---

## Step 7 — Rate limiter

Create `src/middleware/ratelimit.go` if a rate limiter does not already exist. Use a sliding window counter backed by the `rate_limits` table in the server DB.

```go
package middleware

import (
    "context"
    "fmt"
    "net/http"
    "strings"
    "time"
)

// RateLimit returns middleware that allows at most `max` requests per `windowSecs` per IP.
// key is the endpoint identifier (e.g. "auth.login").
func RateLimit(db RateLimitDB, key string, max int, windowSecs int64) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            ip := clientIP(r)
            bucket := fmt.Sprintf("%s:%s", key, ip)
            now := time.Now().Unix()
            windowStart := now - windowSecs

            count, err := db.CountRateLimitHits(r.Context(), bucket, windowStart)
            if err != nil {
                // Fail closed on DB error — never silently drop rate limiting
                w.Header().Set("Content-Type", "application/json")
                w.WriteHeader(503)
                fmt.Fprintf(w, `{"ok":false,"error":"RATE_LIMIT_UNAVAILABLE","message":"Try again shortly"}`+"\n")
                return
            }
            if count >= int64(max) {
                retryAfter := windowSecs
                w.Header().Set("Retry-After", fmt.Sprintf("%d", retryAfter))
                w.Header().Set("Content-Type", "application/json")
                w.WriteHeader(429)
                fmt.Fprintf(w, `{"ok":false,"error":"RATE_LIMITED","message":"Too many requests","retry_after":%d}`+"\n", retryAfter)
                return
            }
            // Non-fatal if this write fails — the request is already allowed through
            _ = db.RecordRateLimitHit(r.Context(), bucket, now)
            next.ServeHTTP(w, r)
        })
    }
}

func clientIP(r *http.Request) string {
    if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
        // Use only the first (leftmost) address — set by the outermost trusted proxy
        parts := strings.Split(xff, ",")
        if len(parts) > 0 {
            return strings.TrimSpace(parts[0])
        }
    }
    if xri := r.Header.Get("X-Real-IP"); xri != "" {
        return xri
    }
    // Strip port from RemoteAddr
    host := r.RemoteAddr
    for i := len(host) - 1; i >= 0; i-- {
        if host[i] == ':' {
            return host[:i]
        }
    }
    return host
}

// RateLimitDB is the storage interface for the rate limiter.
type RateLimitDB interface {
    CountRateLimitHits(ctx context.Context, bucket string, since int64) (int64, error)
    RecordRateLimitHit(ctx context.Context, bucket string, at int64) error
}
```

Rate limit defaults — baked in as constants, configurable via server config:

| Endpoint | Max | Window |
|----------|-----|--------|
| `auth.admin_login` | 5 | 900s (15 min) |
| `auth.user_login` | 5 | 900s (15 min) |
| `auth.register` | 5 | 3600s (1 hr) |
| `auth.password_reset_request` | 3 | 3600s (1 hr) |
| `auth.password_reset_confirm` | 5 | 3600s (1 hr) |
| `auth.email_verify` | 5 | 3600s (1 hr) |
| `auth.totp_verify` | 10 | 300s (5 min) |
| `auth.password_change` | 3 | 3600s (1 hr) |
| `auth.invite_create` | 20 | 3600s (1 hr) |
| `auth.invite_accept` | 10 | 3600s (1 hr) |
| `api.read` (GET/HEAD) | 120 | 60s |
| `api.write` (POST/PUT/PATCH/DELETE) | 10 | 60s |
| `api.health` | 120 | 60s |
| Global burst (all endpoints combined) | 240 | 60s |

---

## Step 8 — Handlers

Create `src/handler/{feature}_handler.go` for each selected feature.

### Handler rules

- Parse JSON body with `json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))` — cap at 1 MiB
- Validate inputs using model validators before any DB call
- For login flows: **always call the password hash check even when the user is not found** (dummy hash) — prevents timing oracle
- Use identical error messages for "wrong password" and "no such user": `"Invalid credentials"`
- Set session cookies: `HttpOnly; Secure; SameSite=Strict; Path=/`
- JSON success: `{"ok":true,"data":{...}}\n` with status 200/201
- JSON error: `{"ok":false,"error":"CODE","message":"human text"}\n`

### Shared handler scaffolding (`src/handler/handler.go`)

Every handler file below hangs off this one `Handler` struct and these shared
helpers. `{MODULE}` is the Go module path discovered in Step 1.

```go
package handler

import (
    "context"
    "encoding/json"
    "errors"
    "net"
    "net/http"
    "strings"

    "{MODULE}/src/config"
    "{MODULE}/src/middleware"
)

// ErrNotFound is what every Store lookup returns when no row matches.
// The db package must translate sql.ErrNoRows into this error.
var ErrNotFound = errors.New("not found")

// Mailer sends transactional auth mail. Configured reports whether SMTP is set
// up; when it is not, activation/reset links are returned to the caller instead.
type Mailer interface {
    Configured() bool
    Send(ctx context.Context, to, subject, body string) error
}

// Handler carries every dependency the auth handlers need. Wire it up in the
// router file (Step 11): AdminPath is Step 1's ADMIN_PATH, BaseURL is the
// server's external base URL (e.g. "https://{fqdn}").
type Handler struct {
    DB         Store
    Mail       Mailer
    Auth       config.AuthConfig
    ServerName string
    BaseURL    string
    AdminPath  string
}

// dummyPasswordHash mirrors Step 5's unexported model dummy hash. Login paths
// run CheckPassword against it when no account matched so that "no such user"
// and "wrong password" cost the same wall-clock time.
const dummyPasswordHash = "$argon2id$v=19$m=65536,t=3,p=4$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

// Config fallbacks, applied when the YAML left a value at zero (Step 12).
const (
    defaultAdminSessionTimeout = 86400
    defaultUserSessionTimeout  = 2592000
    defaultInviteExpiry        = 604800
    passwordResetTTL           = 3600
    emailVerificationTTL       = 86400
)

type okEnvelope struct {
    OK   bool `json:"ok"`
    Data any  `json:"data,omitempty"`
}

type errEnvelope struct {
    OK      bool   `json:"ok"`
    Error   string `json:"error"`
    Message string `json:"message"`
}

// writeOK emits {"ok":true,"data":{...}}\n. Pass nil data for a bare {"ok":true}.
func writeOK(w http.ResponseWriter, status int, data any) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    _ = json.NewEncoder(w).Encode(okEnvelope{OK: true, Data: data})
}

// writeErr emits {"ok":false,"error":"CODE","message":"human text"}\n.
func writeErr(w http.ResponseWriter, status int, code, message string) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    _ = json.NewEncoder(w).Encode(errEnvelope{OK: false, Error: code, Message: message})
}

func writeNotFound(w http.ResponseWriter) {
    writeErr(w, http.StatusNotFound, "NOT_FOUND", "Not found")
}

func writeInternal(w http.ResponseWriter) {
    writeErr(w, http.StatusInternalServerError, "INTERNAL", "Something went wrong")
}

func writeInvalidCredentials(w http.ResponseWriter) {
    writeErr(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid credentials")
}

// decodeJSON caps the body at 1 MiB and reports whether decoding succeeded.
// It writes the 400 response itself on failure.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
    if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(dst); err != nil {
        writeErr(w, http.StatusBadRequest, "INVALID_JSON", "Request body is not valid JSON")
        return false
    }
    return true
}

// setSessionCookie sets an auth cookie: HttpOnly; Secure; SameSite=Strict.
func setSessionCookie(w http.ResponseWriter, name, value, path string, maxAge int) {
    http.SetCookie(w, &http.Cookie{
        Name:     name,
        Value:    value,
        Path:     path,
        MaxAge:   maxAge,
        HttpOnly: true,
        Secure:   true,
        SameSite: http.SameSiteStrictMode,
    })
}

// clearSessionCookie expires an auth cookie with the attributes it was set with.
func clearSessionCookie(w http.ResponseWriter, name, path string) {
    http.SetCookie(w, &http.Cookie{
        Name:     name,
        Value:    "",
        Path:     path,
        MaxAge:   -1,
        HttpOnly: true,
        Secure:   true,
        SameSite: http.SameSiteStrictMode,
    })
}

func adminIDFrom(r *http.Request) int64 {
    id, _ := r.Context().Value(middleware.CtxAdminID).(int64)
    return id
}

func userIDFrom(r *http.Request) int64 {
    id, _ := r.Context().Value(middleware.CtxUserID).(int64)
    return id
}

// pathParam reads a path wildcard. With the stdlib mux this is r.PathValue;
// with chi replace the body with chi.URLParam(r, name), with gorilla/mux with
// mux.Vars(r)[name].
func pathParam(r *http.Request, name string) string {
    return r.PathValue(name)
}

func orDefault(v, def int) int {
    if v <= 0 {
        return def
    }
    return v
}

// adminCookiePath scopes the admin session cookie to the admin panel only.
func (h *Handler) adminCookiePath() string {
    return "/server/" + h.AdminPath
}

// clientIP mirrors Step 7's rate-limiter helper — leftmost X-Forwarded-For
// entry, then X-Real-IP, then RemoteAddr with the port stripped. It is repeated
// here because the middleware copy is unexported.
func clientIP(r *http.Request) string {
    if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
        return strings.TrimSpace(strings.Split(xff, ",")[0])
    }
    if xri := r.Header.Get("X-Real-IP"); xri != "" {
        return xri
    }
    if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
        return host
    }
    return r.RemoteAddr
}
```

### Store interface (`src/handler/store.go`)

The project's `db` package implements this; it is the handler-side twin of
Step 6's `AuthDB` and Step 7's `RateLimitDB`. Struct types come from Step 5;
`email_verifications` has no model struct in Step 5, so its methods take and
return scalars the same way `AuthDB` does.

```go
package handler

import (
    "context"

    "{MODULE}/src/model"
)

type Store interface {
    // Feature 1 — admins
    GetAdminByID(ctx context.Context, id int64) (*model.Admin, error)
    GetAdminByUsername(ctx context.Context, username string) (*model.Admin, error)
    CreateAdminSession(ctx context.Context, s *model.AdminSession) error
    GetAdminSessionByID(ctx context.Context, id string) (*model.AdminSession, error)
    DeleteAdminSession(ctx context.Context, id string) error
    UpdateAdminLogin(ctx context.Context, adminID, at int64, ip string) error
    UpdateAdminPassword(ctx context.Context, adminID int64, hash string) error
    SetAdminTOTPSecret(ctx context.Context, adminID int64, secret string) error
    SetAdminTOTPEnabled(ctx context.Context, adminID int64, enabled bool) error
    ClearAdminTOTP(ctx context.Context, adminID int64) error

    // Feature 2 — API tokens
    ListAPITokens(ctx context.Context, ownerType string, ownerID int64) ([]model.APIToken, error)
    CreateAPIToken(ctx context.Context, t *model.APIToken) (int64, error)
    GetAPITokenByID(ctx context.Context, id int64) (*model.APIToken, error)
    RevokeAPIToken(ctx context.Context, id int64) error

    // Feature 3 — users
    GetUserByID(ctx context.Context, id int64) (*model.User, error)
    GetUserByUsername(ctx context.Context, username string) (*model.User, error)
    GetUserByEmail(ctx context.Context, email string) (*model.User, error)
    GetUserByLogin(ctx context.Context, login string) (*model.User, error)
    CreateUser(ctx context.Context, u *model.User) (int64, error)
    UpdateUserProfile(ctx context.Context, userID int64, displayName, bio, avatarURL string, at int64) error
    UpdateUserPassword(ctx context.Context, userID int64, hash string, at int64) error
    UpdateUserLogin(ctx context.Context, userID, at int64, ip string) error
    SetUserEmailVerified(ctx context.Context, userID int64) error
    CreateUserSession(ctx context.Context, s *model.UserSession) error
    DeleteUserSession(ctx context.Context, id string) error
    CreatePasswordReset(ctx context.Context, p *model.PasswordReset) error
    GetPasswordResetByTokenHash(ctx context.Context, hash string) (*model.PasswordReset, error)
    MarkPasswordResetUsed(ctx context.Context, id string) error
    CreateEmailVerification(ctx context.Context, id string, userID int64, email, tokenHash string, createdAt, expiresAt int64) error
    GetEmailVerification(ctx context.Context, tokenHash string) (id string, userID int64, email string, expiresAt int64, used bool, err error)
    MarkEmailVerificationUsed(ctx context.Context, id string) error
    CreateUserInvite(ctx context.Context, i *model.UserInvite) error
    GetUserInviteByTokenHash(ctx context.Context, hash string) (*model.UserInvite, error)
    GetUserInviteByUsername(ctx context.Context, username string) (*model.UserInvite, error)
    IncrementUserInviteUse(ctx context.Context, id string) error

    // Feature 4 — orgs
    ListOrgsForUser(ctx context.Context, userID int64) ([]model.Org, error)
    CreateOrg(ctx context.Context, o *model.Org) (int64, error)
    GetOrgBySlug(ctx context.Context, slug string) (*model.Org, error)
    UpdateOrg(ctx context.Context, o *model.Org) error
    DeleteOrg(ctx context.Context, orgID int64) error
    ListOrgMembers(ctx context.Context, orgID int64) ([]model.OrgMember, error)
    GetOrgMember(ctx context.Context, orgID, userID int64) (*model.OrgMember, error)
    AddOrgMember(ctx context.Context, m *model.OrgMember) error
    UpdateOrgMemberRole(ctx context.Context, orgID, userID int64, role string) error
    RemoveOrgMember(ctx context.Context, orgID, userID int64) error
    CreateOrgInvite(ctx context.Context, i *model.OrgInvite) error
    GetOrgInviteByTokenHash(ctx context.Context, hash string) (*model.OrgInvite, error)
    MarkOrgInviteAccepted(ctx context.Context, id string) error

    // Feature 5 — custom domains
    ListDomains(ctx context.Context, ownerType string, ownerID int64) ([]model.CustomDomain, error)
    CreateDomain(ctx context.Context, d *model.CustomDomain) (int64, error)
    GetDomainByName(ctx context.Context, domain string) (*model.CustomDomain, error)
    DeleteDomain(ctx context.Context, id int64) error
    SetDomainVerified(ctx context.Context, id, at int64) error
}
```

### Feature 1 — Admin auth handler (`src/handler/admin_auth_handler.go`)

Routes: `POST /server/{admin_path}/auth/login` (rate limit key `auth.admin_login`,
5 / 900s) · `POST /server/{admin_path}/auth/logout` · `GET /server/{admin_path}/auth/session` ·
`POST /server/{admin_path}/auth/password/change` (`auth.password_change`, 3 / 3600s) ·
`POST /server/{admin_path}/auth/totp/enable` · `POST /server/{admin_path}/auth/totp/confirm`
(`auth.totp_verify`, 10 / 300s) · `POST /server/{admin_path}/auth/totp/disable`.
Every route except login is wrapped in `middleware.RequireAdmin`; rate limits are
applied with `middleware.RateLimit` at registration time (Step 11), not inside
the handler.

```go
package handler

import (
    "errors"
    "net/http"
    "time"

    "{MODULE}/src/model"
)

type adminLoginRequest struct {
    Username string `json:"username"`
    Password string `json:"password"`
    TOTPCode string `json:"totp_code"`
}

// AdminLogin handles POST /server/{admin_path}/auth/login.
func (h *Handler) AdminLogin(w http.ResponseWriter, r *http.Request) {
    var req adminLoginRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if req.Username == "" || req.Password == "" {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Username and password are required")
        return
    }

    admin, err := h.DB.GetAdminByUsername(r.Context(), req.Username)
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return
    }

    // Always spend the argon2id cost, even when no admin matched.
    stored := dummyPasswordHash
    if admin != nil && admin.PasswordHash != "" {
        stored = admin.PasswordHash
    }
    passwordOK := model.CheckPassword(stored, req.Password)
    if admin == nil || admin.PasswordHash == "" || !passwordOK {
        writeInvalidCredentials(w)
        return
    }

    if admin.TOTPEnabled {
        if req.TOTPCode == "" {
            writeErr(w, http.StatusUnauthorized, "TOTP_REQUIRED", "Two-factor authentication code required")
            return
        }
        if !model.ValidateTOTP(admin.TOTPSecret, req.TOTPCode) {
            writeErr(w, http.StatusUnauthorized, "TOTP_INVALID", "Invalid authenticator code")
            return
        }
    }

    sid, err := model.NewSessionID()
    if err != nil {
        writeInternal(w)
        return
    }
    now := time.Now().Unix()
    ttl := orDefault(h.Auth.Admin.SessionTimeout, defaultAdminSessionTimeout)
    session := &model.AdminSession{
        ID:        sid,
        AdminID:   admin.ID,
        IP:        clientIP(r),
        UserAgent: r.UserAgent(),
        CreatedAt: now,
        ExpiresAt: now + int64(ttl),
        LastSeen:  now,
    }
    if err := h.DB.CreateAdminSession(r.Context(), session); err != nil {
        writeInternal(w)
        return
    }
    setSessionCookie(w, "admin_session", sid, h.adminCookiePath(), ttl)

    if err := h.DB.UpdateAdminLogin(r.Context(), admin.ID, now, session.IP); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{
        "admin_id": admin.ID,
        "username": admin.Username,
    })
}

// AdminLogout handles POST /server/{admin_path}/auth/logout.
func (h *Handler) AdminLogout(w http.ResponseWriter, r *http.Request) {
    if c, err := r.Cookie("admin_session"); err == nil && c.Value != "" {
        if err := h.DB.DeleteAdminSession(r.Context(), c.Value); err != nil {
            writeInternal(w)
            return
        }
    }
    clearSessionCookie(w, "admin_session", h.adminCookiePath())
    writeOK(w, http.StatusOK, nil)
}

// AdminSession handles GET /server/{admin_path}/auth/session.
func (h *Handler) AdminSession(w http.ResponseWriter, r *http.Request) {
    c, err := r.Cookie("admin_session")
    if err != nil || c.Value == "" {
        writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
        return
    }
    session, err := h.DB.GetAdminSessionByID(r.Context(), c.Value)
    if err != nil {
        writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Session expired")
        return
    }
    admin, err := h.DB.GetAdminByID(r.Context(), session.AdminID)
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{
        "admin_id":   admin.ID,
        "username":   admin.Username,
        "expires_at": session.ExpiresAt,
    })
}

type passwordChangeRequest struct {
    CurrentPassword string `json:"current_password"`
    NewPassword     string `json:"new_password"`
}

// AdminPasswordChange handles POST /server/{admin_path}/auth/password/change.
func (h *Handler) AdminPasswordChange(w http.ResponseWriter, r *http.Request) {
    var req passwordChangeRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidatePassword(req.NewPassword); err != nil {
        writeErr(w, http.StatusBadRequest, "PASSWORD_INVALID", err.Error())
        return
    }
    admin, err := h.DB.GetAdminByID(r.Context(), adminIDFrom(r))
    if err != nil {
        writeInternal(w)
        return
    }
    if !model.CheckPassword(admin.PasswordHash, req.CurrentPassword) {
        writeInvalidCredentials(w)
        return
    }
    hash, err := model.HashPassword(req.NewPassword)
    if err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.UpdateAdminPassword(r.Context(), admin.ID, hash); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}

// AdminTOTPEnable handles POST /server/{admin_path}/auth/totp/enable. The secret
// is stored but totp_enabled stays 0 until AdminTOTPConfirm succeeds.
func (h *Handler) AdminTOTPEnable(w http.ResponseWriter, r *http.Request) {
    admin, err := h.DB.GetAdminByID(r.Context(), adminIDFrom(r))
    if err != nil {
        writeInternal(w)
        return
    }
    secret, uri, err := model.NewTOTPSecret(h.ServerName, admin.Username)
    if err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.SetAdminTOTPSecret(r.Context(), admin.ID, secret); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{"otpauth_uri": uri})
}

type totpCodeRequest struct {
    Code string `json:"code"`
}

// AdminTOTPConfirm handles POST /server/{admin_path}/auth/totp/confirm.
func (h *Handler) AdminTOTPConfirm(w http.ResponseWriter, r *http.Request) {
    var req totpCodeRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    admin, err := h.DB.GetAdminByID(r.Context(), adminIDFrom(r))
    if err != nil {
        writeInternal(w)
        return
    }
    if admin.TOTPSecret == "" || !model.ValidateTOTP(admin.TOTPSecret, req.Code) {
        writeErr(w, http.StatusUnauthorized, "TOTP_INVALID", "Invalid authenticator code")
        return
    }
    if err := h.DB.SetAdminTOTPEnabled(r.Context(), admin.ID, true); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}

type totpDisableRequest struct {
    Password string `json:"password"`
    Code     string `json:"code"`
}

// AdminTOTPDisable handles POST /server/{admin_path}/auth/totp/disable.
func (h *Handler) AdminTOTPDisable(w http.ResponseWriter, r *http.Request) {
    var req totpDisableRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    admin, err := h.DB.GetAdminByID(r.Context(), adminIDFrom(r))
    if err != nil {
        writeInternal(w)
        return
    }
    if !model.CheckPassword(admin.PasswordHash, req.Password) {
        writeInvalidCredentials(w)
        return
    }
    if !model.ValidateTOTP(admin.TOTPSecret, req.Code) {
        writeErr(w, http.StatusUnauthorized, "TOTP_INVALID", "Invalid authenticator code")
        return
    }
    if err := h.DB.ClearAdminTOTP(r.Context(), admin.ID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}
```

### Feature 3 — User auth handler (`src/handler/user_auth_handler.go`)

Routes: `POST /api/{api_version}/auth/register` (`auth.register`, 5 / 3600s) ·
`POST /server/{admin_path}/users/invite` (`auth.invite_create`, 20 / 3600s, RequireAdmin) ·
`POST /server/{admin_path}/users/create` (RequireAdmin) ·
`POST /api/{api_version}/auth/invite/{token}/accept` (`auth.invite_accept`, 10 / 3600s) ·
`POST /api/{api_version}/auth/login` (`auth.user_login`, 5 / 900s) ·
`POST /api/{api_version}/auth/logout` (RequireUser) ·
`GET|PUT /api/{api_version}/auth/me` (RequireUser) ·
`POST /api/{api_version}/auth/password/change` (RequireUser, `auth.password_change`, 3 / 3600s) ·
`POST /api/{api_version}/auth/password/reset/request` (`auth.password_reset_request`, 3 / 3600s) ·
`POST /api/{api_version}/auth/password/reset/confirm` (`auth.password_reset_confirm`, 5 / 3600s) ·
`POST /api/{api_version}/auth/email/verify` (`auth.email_verify`, 5 / 3600s).

Admin invite and direct-create are reachable in BOTH registration modes — the
mode gates only the public `/auth/register` form. The password-setup page itself
is the SSR route `GET /auth/invite/{token}` (Step 10), not a `/api/` endpoint;
that page handler validates the token before rendering the form and shows the
same generic "This invite link is no longer valid" state for unknown, expired
and already-used tokens alike.

```go
package handler

import (
    "errors"
    "fmt"
    "net/http"
    "time"

    "{MODULE}/src/model"
)

type publicUser struct {
    ID            int64  `json:"id"`
    Username      string `json:"username"`
    Email         string `json:"email"`
    EmailVerified bool   `json:"email_verified"`
    DisplayName   string `json:"display_name"`
    AvatarURL     string `json:"avatar_url"`
    Bio           string `json:"bio"`
    CreatedAt     int64  `json:"created_at"`
    LastLogin     *int64 `json:"last_login"`
}

// toPublicUser strips password_hash and the suspension fields from a user row.
func toPublicUser(u *model.User) publicUser {
    return publicUser{
        ID:            u.ID,
        Username:      u.Username,
        Email:         u.Email,
        EmailVerified: u.EmailVerified,
        DisplayName:   u.DisplayName,
        AvatarURL:     u.AvatarURL,
        Bio:           u.Bio,
        CreatedAt:     u.CreatedAt,
        LastLogin:     u.LastLogin,
    }
}

// startUserSession creates a user_sessions row and sets the session cookie.
func (h *Handler) startUserSession(w http.ResponseWriter, r *http.Request, userID int64) error {
    sid, err := model.NewSessionID()
    if err != nil {
        return err
    }
    now := time.Now().Unix()
    ttl := orDefault(h.Auth.Users.SessionTimeout, defaultUserSessionTimeout)
    if err := h.DB.CreateUserSession(r.Context(), &model.UserSession{
        ID:        sid,
        UserID:    userID,
        IP:        clientIP(r),
        UserAgent: r.UserAgent(),
        CreatedAt: now,
        ExpiresAt: now + int64(ttl),
        LastSeen:  now,
    }); err != nil {
        return err
    }
    setSessionCookie(w, "user_session", sid, "/", ttl)
    return nil
}

// sendEmailVerification issues a verification token and mails the link.
func (h *Handler) sendEmailVerification(r *http.Request, userID int64, email string) error {
    raw, err := model.NewSessionID()
    if err != nil {
        return err
    }
    id, err := model.NewSessionID()
    if err != nil {
        return err
    }
    now := time.Now().Unix()
    if err := h.DB.CreateEmailVerification(r.Context(), id, userID, email,
        model.HashToken(raw), now, now+emailVerificationTTL); err != nil {
        return err
    }
    if h.Mail == nil || !h.Mail.Configured() {
        return nil
    }
    link := fmt.Sprintf("%s/auth/email/verify?token=%s", h.BaseURL, raw)
    return h.Mail.Send(r.Context(), email, "Verify your email address",
        "Confirm your email address: "+link)
}

type registerRequest struct {
    Username string `json:"username"`
    Email    string `json:"email"`
    Password string `json:"password"`
}

// UserRegister handles POST /api/{api_version}/auth/register. The mode check
// runs before body parsing so that in "private" mode the route is
// indistinguishable from one that does not exist.
func (h *Handler) UserRegister(w http.ResponseWriter, r *http.Request) {
    if h.Auth.Users.Registration.Mode != "open" {
        writeNotFound(w)
        return
    }
    var req registerRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidateUsername(req.Username); err != nil {
        writeErr(w, http.StatusBadRequest, "USERNAME_INVALID", err.Error())
        return
    }
    if err := model.ValidateEmail(req.Email); err != nil {
        writeErr(w, http.StatusBadRequest, "EMAIL_INVALID", err.Error())
        return
    }
    if err := model.ValidatePassword(req.Password); err != nil {
        writeErr(w, http.StatusBadRequest, "PASSWORD_INVALID", err.Error())
        return
    }

    // Both lookups always run so the response time never reveals which of the
    // two collided.
    byName, nameErr := h.DB.GetUserByUsername(r.Context(), req.Username)
    byEmail, emailErr := h.DB.GetUserByEmail(r.Context(), req.Email)
    if (nameErr != nil && !errors.Is(nameErr, ErrNotFound)) ||
        (emailErr != nil && !errors.Is(emailErr, ErrNotFound)) {
        writeInternal(w)
        return
    }
    if byName != nil {
        writeErr(w, http.StatusConflict, "USERNAME_TAKEN", "That username is already taken")
        return
    }
    if byEmail != nil {
        writeErr(w, http.StatusConflict, "EMAIL_TAKEN", "An account with that email already exists")
        return
    }

    hash, err := model.HashPassword(req.Password)
    if err != nil {
        writeInternal(w)
        return
    }
    now := time.Now().Unix()
    userID, err := h.DB.CreateUser(r.Context(), &model.User{
        Username:     req.Username,
        Email:        req.Email,
        PasswordHash: hash,
        CreatedAt:    now,
        UpdatedAt:    now,
    })
    if err != nil {
        writeInternal(w)
        return
    }
    if h.Auth.Users.RequireEmailVerification {
        if err := h.sendEmailVerification(r, userID, req.Email); err != nil {
            writeInternal(w)
            return
        }
    }
    if err := h.startUserSession(w, r, userID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusCreated, map[string]any{
        "user_id":                     userID,
        "username":                    req.Username,
        "email_verification_required": h.Auth.Users.RequireEmailVerification,
    })
}

// newInvite mints an invite token and stores only its hash.
func (h *Handler) newInvite(r *http.Request, adminID int64, username string) (raw string, expiresAt int64, err error) {
    raw, hash, err := model.NewTokenRaw("")
    if err != nil {
        return "", 0, err
    }
    id, err := model.NewSessionID()
    if err != nil {
        return "", 0, err
    }
    now := time.Now().Unix()
    expiresAt = now + int64(orDefault(h.Auth.Users.InviteExpiry, defaultInviteExpiry))
    if err := h.DB.CreateUserInvite(r.Context(), &model.UserInvite{
        ID:        id,
        Username:  username,
        InvitedBy: adminID,
        TokenHash: hash,
        CreatedAt: now,
        ExpiresAt: expiresAt,
        MaxUses:   1,
    }); err != nil {
        return "", 0, err
    }
    return raw, expiresAt, nil
}

type inviteCreateRequest struct {
    Username string `json:"username"`
}

// AdminInviteUser handles POST /server/{admin_path}/users/invite. The raw token
// is returned once for the admin to share; only its hash is stored.
func (h *Handler) AdminInviteUser(w http.ResponseWriter, r *http.Request) {
    var req inviteCreateRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidateUsername(req.Username); err != nil {
        writeErr(w, http.StatusBadRequest, "USERNAME_INVALID", err.Error())
        return
    }
    existing, err := h.DB.GetUserByUsername(r.Context(), req.Username)
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return
    }
    pending, err := h.DB.GetUserInviteByUsername(r.Context(), req.Username)
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return
    }
    if existing != nil || (pending != nil && pending.Valid()) {
        writeErr(w, http.StatusConflict, "USERNAME_TAKEN",
            "That username already has a pending or active account")
        return
    }
    raw, expiresAt, err := h.newInvite(r, adminIDFrom(r), req.Username)
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusCreated, map[string]any{
        "username":   req.Username,
        "invite_url": fmt.Sprintf("%s/auth/invite/%s", h.BaseURL, raw),
        "expires_at": expiresAt,
    })
}

type userCreateRequest struct {
    Username string `json:"username"`
    Email    string `json:"email"`
}

// AdminCreateUser handles POST /server/{admin_path}/users/create. The users row
// is inserted with an empty password_hash — no login path accepts it until the
// invited user sets a password through the accept flow.
func (h *Handler) AdminCreateUser(w http.ResponseWriter, r *http.Request) {
    var req userCreateRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidateUsername(req.Username); err != nil {
        writeErr(w, http.StatusBadRequest, "USERNAME_INVALID", err.Error())
        return
    }
    if err := model.ValidateEmail(req.Email); err != nil {
        writeErr(w, http.StatusBadRequest, "EMAIL_INVALID", err.Error())
        return
    }
    byName, nameErr := h.DB.GetUserByUsername(r.Context(), req.Username)
    byEmail, emailErr := h.DB.GetUserByEmail(r.Context(), req.Email)
    if (nameErr != nil && !errors.Is(nameErr, ErrNotFound)) ||
        (emailErr != nil && !errors.Is(emailErr, ErrNotFound)) {
        writeInternal(w)
        return
    }
    if byName != nil {
        writeErr(w, http.StatusConflict, "USERNAME_TAKEN", "That username is already taken")
        return
    }
    if byEmail != nil {
        writeErr(w, http.StatusConflict, "EMAIL_TAKEN", "An account with that email already exists")
        return
    }

    now := time.Now().Unix()
    userID, err := h.DB.CreateUser(r.Context(), &model.User{
        Username:     req.Username,
        Email:        req.Email,
        PasswordHash: "",
        CreatedAt:    now,
        UpdatedAt:    now,
    })
    if err != nil {
        writeInternal(w)
        return
    }
    raw, _, err := h.newInvite(r, adminIDFrom(r), req.Username)
    if err != nil {
        writeInternal(w)
        return
    }
    activationURL := fmt.Sprintf("%s/auth/invite/%s", h.BaseURL, raw)

    data := map[string]any{"user_id": userID, "username": req.Username}
    if h.Mail != nil && h.Mail.Configured() {
        if err := h.Mail.Send(r.Context(), req.Email, "Activate your account",
            "Set your password to activate your account: "+activationURL); err != nil {
            writeInternal(w)
            return
        }
    } else {
        data["activation_url"] = activationURL
    }
    writeOK(w, http.StatusCreated, data)
}

type inviteAcceptRequest struct {
    Password string `json:"password"`
    // Used only by the pure-invite flow, where no users row exists yet; ignored
    // when the admin already created the row through /users/create.
    Email string `json:"email"`
}

// UserAcceptInvite handles POST /api/{api_version}/auth/invite/{token}/accept.
func (h *Handler) UserAcceptInvite(w http.ResponseWriter, r *http.Request) {
    var req inviteAcceptRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    invite, err := h.DB.GetUserInviteByTokenHash(r.Context(), model.HashToken(pathParam(r, "token")))
    if err != nil || invite == nil || !invite.Valid() {
        writeErr(w, http.StatusBadRequest, "INVITE_INVALID", "This invite link is no longer valid")
        return
    }
    if err := model.ValidatePassword(req.Password); err != nil {
        writeErr(w, http.StatusBadRequest, "PASSWORD_INVALID", err.Error())
        return
    }
    hash, err := model.HashPassword(req.Password)
    if err != nil {
        writeInternal(w)
        return
    }

    now := time.Now().Unix()
    user, err := h.DB.GetUserByUsername(r.Context(), invite.Username)
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return
    }
    var userID int64
    if user != nil {
        userID = user.ID
        if err := h.DB.UpdateUserPassword(r.Context(), userID, hash, now); err != nil {
            writeInternal(w)
            return
        }
    } else {
        if err := model.ValidateEmail(req.Email); err != nil {
            writeErr(w, http.StatusBadRequest, "EMAIL_INVALID", err.Error())
            return
        }
        userID, err = h.DB.CreateUser(r.Context(), &model.User{
            Username:     invite.Username,
            Email:        req.Email,
            PasswordHash: hash,
            CreatedAt:    now,
            UpdatedAt:    now,
        })
        if err != nil {
            writeInternal(w)
            return
        }
    }
    if err := h.DB.IncrementUserInviteUse(r.Context(), invite.ID); err != nil {
        writeInternal(w)
        return
    }
    if err := h.startUserSession(w, r, userID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{"user_id": userID, "username": invite.Username})
}

type userLoginRequest struct {
    // Username or email.
    Login    string `json:"login"`
    Password string `json:"password"`
}

// UserLogin handles POST /api/{api_version}/auth/login with the same
// constant-time pattern as AdminLogin.
func (h *Handler) UserLogin(w http.ResponseWriter, r *http.Request) {
    var req userLoginRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if req.Login == "" || req.Password == "" {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Login and password are required")
        return
    }
    user, err := h.DB.GetUserByLogin(r.Context(), req.Login)
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return
    }
    stored := dummyPasswordHash
    if user != nil && user.PasswordHash != "" {
        stored = user.PasswordHash
    }
    passwordOK := model.CheckPassword(stored, req.Password)
    if user == nil || user.PasswordHash == "" || !passwordOK {
        writeInvalidCredentials(w)
        return
    }
    if user.Suspended {
        writeErr(w, http.StatusForbidden, "ACCOUNT_SUSPENDED", "Your account has been suspended")
        return
    }
    if err := h.startUserSession(w, r, user.ID); err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.UpdateUserLogin(r.Context(), user.ID, time.Now().Unix(), clientIP(r)); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{"user_id": user.ID, "username": user.Username})
}

// UserLogout handles POST /api/{api_version}/auth/logout.
func (h *Handler) UserLogout(w http.ResponseWriter, r *http.Request) {
    if c, err := r.Cookie("user_session"); err == nil && c.Value != "" {
        if err := h.DB.DeleteUserSession(r.Context(), c.Value); err != nil {
            writeInternal(w)
            return
        }
    }
    clearSessionCookie(w, "user_session", "/")
    writeOK(w, http.StatusOK, nil)
}

// UserMe handles GET /api/{api_version}/auth/me.
func (h *Handler) UserMe(w http.ResponseWriter, r *http.Request) {
    user, err := h.DB.GetUserByID(r.Context(), userIDFrom(r))
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, toPublicUser(user))
}

type updateMeRequest struct {
    DisplayName string `json:"display_name"`
    Bio         string `json:"bio"`
    AvatarURL   string `json:"avatar_url"`
}

// UserUpdateMe handles PUT /api/{api_version}/auth/me. Only profile fields are
// updatable here; username and email changes have their own flows.
func (h *Handler) UserUpdateMe(w http.ResponseWriter, r *http.Request) {
    var req updateMeRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    userID := userIDFrom(r)
    if err := h.DB.UpdateUserProfile(r.Context(), userID, req.DisplayName, req.Bio,
        req.AvatarURL, time.Now().Unix()); err != nil {
        writeInternal(w)
        return
    }
    user, err := h.DB.GetUserByID(r.Context(), userID)
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, toPublicUser(user))
}

// UserPasswordChange handles POST /api/{api_version}/auth/password/change.
func (h *Handler) UserPasswordChange(w http.ResponseWriter, r *http.Request) {
    var req passwordChangeRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidatePassword(req.NewPassword); err != nil {
        writeErr(w, http.StatusBadRequest, "PASSWORD_INVALID", err.Error())
        return
    }
    user, err := h.DB.GetUserByID(r.Context(), userIDFrom(r))
    if err != nil {
        writeInternal(w)
        return
    }
    if user.PasswordHash == "" || !model.CheckPassword(user.PasswordHash, req.CurrentPassword) {
        writeInvalidCredentials(w)
        return
    }
    hash, err := model.HashPassword(req.NewPassword)
    if err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.UpdateUserPassword(r.Context(), user.ID, hash, time.Now().Unix()); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}

type passwordResetRequest struct {
    Email string `json:"email"`
}

// UserPasswordResetRequest handles POST /api/{api_version}/auth/password/reset/request.
// Every path returns the same body — the response never confirms whether the
// address has an account.
func (h *Handler) UserPasswordResetRequest(w http.ResponseWriter, r *http.Request) {
    const generic = "If an account exists, a reset link was sent"

    var req passwordResetRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidateEmail(req.Email); err != nil {
        writeOK(w, http.StatusOK, map[string]any{"message": generic})
        return
    }
    user, err := h.DB.GetUserByEmail(r.Context(), req.Email)
    if err != nil || user == nil {
        writeOK(w, http.StatusOK, map[string]any{"message": generic})
        return
    }
    raw, hash, err := model.NewTokenRaw("")
    if err != nil {
        writeOK(w, http.StatusOK, map[string]any{"message": generic})
        return
    }
    id, err := model.NewSessionID()
    if err != nil {
        writeOK(w, http.StatusOK, map[string]any{"message": generic})
        return
    }
    now := time.Now().Unix()
    if err := h.DB.CreatePasswordReset(r.Context(), &model.PasswordReset{
        ID:        id,
        UserID:    user.ID,
        TokenHash: hash,
        CreatedAt: now,
        ExpiresAt: now + passwordResetTTL,
    }); err == nil && h.Mail != nil && h.Mail.Configured() {
        link := fmt.Sprintf("%s/auth/password/reset/confirm?token=%s", h.BaseURL, raw)
        _ = h.Mail.Send(r.Context(), user.Email, "Reset your password",
            "Reset your password: "+link)
    }
    writeOK(w, http.StatusOK, map[string]any{"message": generic})
}

type passwordResetConfirmRequest struct {
    Token       string `json:"token"`
    NewPassword string `json:"new_password"`
}

// UserPasswordResetConfirm handles POST /api/{api_version}/auth/password/reset/confirm.
func (h *Handler) UserPasswordResetConfirm(w http.ResponseWriter, r *http.Request) {
    var req passwordResetConfirmRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidatePassword(req.NewPassword); err != nil {
        writeErr(w, http.StatusBadRequest, "PASSWORD_INVALID", err.Error())
        return
    }
    reset, err := h.DB.GetPasswordResetByTokenHash(r.Context(), model.HashToken(req.Token))
    if err != nil || reset == nil {
        writeErr(w, http.StatusBadRequest, "RESET_INVALID", "This reset link is no longer valid")
        return
    }
    if reset.Used {
        writeErr(w, http.StatusBadRequest, "RESET_USED", "This reset link has already been used")
        return
    }
    if reset.Expired() {
        writeErr(w, http.StatusBadRequest, "RESET_EXPIRED",
            "This reset link has expired. Please request a new one")
        return
    }
    hash, err := model.HashPassword(req.NewPassword)
    if err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.UpdateUserPassword(r.Context(), reset.UserID, hash, time.Now().Unix()); err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.MarkPasswordResetUsed(r.Context(), reset.ID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}

type emailVerifyRequest struct {
    Token string `json:"token"`
}

// UserEmailVerify handles POST /api/{api_version}/auth/email/verify.
func (h *Handler) UserEmailVerify(w http.ResponseWriter, r *http.Request) {
    var req emailVerifyRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    id, userID, _, expiresAt, used, err := h.DB.GetEmailVerification(r.Context(), model.HashToken(req.Token))
    if err != nil || used {
        writeErr(w, http.StatusBadRequest, "VERIFICATION_INVALID",
            "This verification link is no longer valid")
        return
    }
    if time.Now().Unix() > expiresAt {
        writeErr(w, http.StatusBadRequest, "VERIFICATION_EXPIRED",
            "This verification link has expired. Please request a new one")
        return
    }
    if err := h.DB.SetUserEmailVerified(r.Context(), userID); err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.MarkEmailVerificationUsed(r.Context(), id); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{"message": "Email address verified"})
}
```

### Feature 2 — API token handler (`src/handler/token_handler.go`)

Routes: `GET /api/{api_version}/auth/tokens` · `POST /api/{api_version}/auth/tokens` ·
`DELETE /api/{api_version}/auth/tokens/{id}` — each behind `RequireUser` or
`RequireAdmin`, whichever the route group uses; the owner is resolved from
whichever ID the middleware put in the context.

```go
package handler

import (
    "encoding/json"
    "net/http"
    "strconv"
    "time"

    "{MODULE}/src/model"
)

type tokenResponse struct {
    ID        int64    `json:"id"`
    Name      string   `json:"name"`
    Scopes    []string `json:"scopes"`
    CreatedAt int64    `json:"created_at"`
    ExpiresAt *int64   `json:"expires_at"`
    LastUsed  *int64   `json:"last_used"`
    Revoked   bool     `json:"revoked"`
}

// toTokenResponse never exposes token_hash.
func toTokenResponse(t *model.APIToken) tokenResponse {
    scopes := []string{}
    _ = json.Unmarshal([]byte(t.Scopes), &scopes)
    return tokenResponse{
        ID:        t.ID,
        Name:      t.Name,
        Scopes:    scopes,
        CreatedAt: t.CreatedAt,
        ExpiresAt: t.ExpiresAt,
        LastUsed:  t.LastUsed,
        Revoked:   t.Revoked,
    }
}

// tokenOwner resolves the authenticated caller into an api_tokens owner pair.
func tokenOwner(r *http.Request) (ownerType string, ownerID int64, ok bool) {
    if id := adminIDFrom(r); id != 0 {
        return "admin", id, true
    }
    if id := userIDFrom(r); id != 0 {
        return "user", id, true
    }
    return "", 0, false
}

// ListTokens handles GET /api/{api_version}/auth/tokens.
func (h *Handler) ListTokens(w http.ResponseWriter, r *http.Request) {
    ownerType, ownerID, ok := tokenOwner(r)
    if !ok {
        writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
        return
    }
    tokens, err := h.DB.ListAPITokens(r.Context(), ownerType, ownerID)
    if err != nil {
        writeInternal(w)
        return
    }
    out := make([]tokenResponse, 0, len(tokens))
    for i := range tokens {
        out = append(out, toTokenResponse(&tokens[i]))
    }
    writeOK(w, http.StatusOK, out)
}

type createTokenRequest struct {
    Name      string   `json:"name"`
    Scopes    []string `json:"scopes"`
    ExpiresAt *int64   `json:"expires_at"`
}

// CreateToken handles POST /api/{api_version}/auth/tokens. The raw token is
// returned once here and never again — only its SHA-256 hash is stored.
func (h *Handler) CreateToken(w http.ResponseWriter, r *http.Request) {
    ownerType, ownerID, ok := tokenOwner(r)
    if !ok {
        writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
        return
    }
    var req createTokenRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if req.Name == "" {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Token name is required")
        return
    }
    if req.Scopes == nil {
        req.Scopes = []string{}
    }
    scopesJSON, err := json.Marshal(req.Scopes)
    if err != nil {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Scopes must be a list of strings")
        return
    }

    prefix := model.TokenPrefixUser
    if ownerType == "admin" {
        prefix = model.TokenPrefixAdmin
    }
    raw, hash, err := model.NewTokenRaw(prefix)
    if err != nil {
        writeInternal(w)
        return
    }
    now := time.Now().Unix()
    expiresAt := req.ExpiresAt
    if expiresAt == nil && h.Auth.Tokens.DefaultExpiry > 0 {
        exp := now + int64(h.Auth.Tokens.DefaultExpiry)
        expiresAt = &exp
    }
    id, err := h.DB.CreateAPIToken(r.Context(), &model.APIToken{
        OwnerType: ownerType,
        OwnerID:   ownerID,
        TokenHash: hash,
        Name:      req.Name,
        Scopes:    string(scopesJSON),
        CreatedAt: now,
        ExpiresAt: expiresAt,
    })
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusCreated, map[string]any{
        "id":     id,
        "name":   req.Name,
        "token":  raw,
        "scopes": req.Scopes,
    })
}

// RevokeToken handles DELETE /api/{api_version}/auth/tokens/{id}.
func (h *Handler) RevokeToken(w http.ResponseWriter, r *http.Request) {
    ownerType, ownerID, ok := tokenOwner(r)
    if !ok {
        writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
        return
    }
    id, err := strconv.ParseInt(pathParam(r, "id"), 10, 64)
    if err != nil {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Token id must be an integer")
        return
    }
    token, err := h.DB.GetAPITokenByID(r.Context(), id)
    if err != nil || token.OwnerType != ownerType || token.OwnerID != ownerID {
        writeErr(w, http.StatusNotFound, "TOKEN_NOT_FOUND", "Token not found")
        return
    }
    if err := h.DB.RevokeAPIToken(r.Context(), id); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}
```

### Feature 4 — Org handler (`src/handler/org_handler.go`)

Routes, all behind `RequireUser`: `GET|POST /api/{api_version}/orgs` ·
`GET|PUT|DELETE /api/{api_version}/orgs/{slug}` ·
`GET|POST /api/{api_version}/orgs/{slug}/members` ·
`PUT|DELETE /api/{api_version}/orgs/{slug}/members/{username}` ·
`POST /api/{api_version}/orgs/{slug}/invites` ·
`GET /api/{api_version}/orgs/invites/{token}`.

```go
package handler

import (
    "errors"
    "fmt"
    "net/http"
    "strings"
    "time"

    "{MODULE}/src/model"
)

const orgInviteTTL = 72 * 3600

// orgContext loads the org named in the path plus the caller's membership.
func (h *Handler) orgContext(w http.ResponseWriter, r *http.Request) (*model.Org, *model.OrgMember, bool) {
    org, err := h.DB.GetOrgBySlug(r.Context(), strings.ToLower(pathParam(r, "slug")))
    if err != nil || org == nil {
        writeErr(w, http.StatusNotFound, "ORG_NOT_FOUND", "Organization not found")
        return nil, nil, false
    }
    member, err := h.DB.GetOrgMember(r.Context(), org.ID, userIDFrom(r))
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return nil, nil, false
    }
    if member == nil {
        // Non-members must not learn that the org exists.
        writeErr(w, http.StatusNotFound, "ORG_NOT_FOUND", "Organization not found")
        return nil, nil, false
    }
    return org, member, true
}

func canManageOrg(m *model.OrgMember) bool {
    return m != nil && (m.Role == "owner" || m.Role == "admin")
}

// ListOrgs handles GET /api/{api_version}/orgs.
func (h *Handler) ListOrgs(w http.ResponseWriter, r *http.Request) {
    orgs, err := h.DB.ListOrgsForUser(r.Context(), userIDFrom(r))
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, orgs)
}

type createOrgRequest struct {
    Slug        string `json:"slug"`
    DisplayName string `json:"display_name"`
    Description string `json:"description"`
}

// CreateOrg handles POST /api/{api_version}/orgs.
func (h *Handler) CreateOrg(w http.ResponseWriter, r *http.Request) {
    var req createOrgRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    slug := strings.ToLower(strings.TrimSpace(req.Slug))
    if err := model.ValidateOrgSlug(slug); err != nil {
        writeErr(w, http.StatusBadRequest, "ORG_SLUG_INVALID", err.Error())
        return
    }
    if req.DisplayName == "" {
        req.DisplayName = slug
    }
    existing, err := h.DB.GetOrgBySlug(r.Context(), slug)
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return
    }
    if existing != nil {
        writeErr(w, http.StatusConflict, "ORG_SLUG_TAKEN", "That organization name is already taken")
        return
    }
    now := time.Now().Unix()
    userID := userIDFrom(r)
    orgID, err := h.DB.CreateOrg(r.Context(), &model.Org{
        Slug:        slug,
        DisplayName: req.DisplayName,
        Description: req.Description,
        OwnerID:     userID,
        CreatedAt:   now,
        UpdatedAt:   now,
    })
    if err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.AddOrgMember(r.Context(), &model.OrgMember{
        OrgID:    orgID,
        UserID:   userID,
        Role:     "owner",
        JoinedAt: now,
    }); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusCreated, map[string]any{"id": orgID, "slug": slug})
}

// GetOrg handles GET /api/{api_version}/orgs/{slug}.
func (h *Handler) GetOrg(w http.ResponseWriter, r *http.Request) {
    org, _, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    writeOK(w, http.StatusOK, org)
}

type updateOrgRequest struct {
    DisplayName string `json:"display_name"`
    Description string `json:"description"`
    AvatarURL   string `json:"avatar_url"`
}

// UpdateOrg handles PUT /api/{api_version}/orgs/{slug} — owner or org-admin only.
func (h *Handler) UpdateOrg(w http.ResponseWriter, r *http.Request) {
    org, member, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    if !canManageOrg(member) {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
        return
    }
    var req updateOrgRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if req.DisplayName != "" {
        org.DisplayName = req.DisplayName
    }
    org.Description = req.Description
    org.AvatarURL = req.AvatarURL
    org.UpdatedAt = time.Now().Unix()
    if err := h.DB.UpdateOrg(r.Context(), org); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, org)
}

// DeleteOrg handles DELETE /api/{api_version}/orgs/{slug} — owner only.
func (h *Handler) DeleteOrg(w http.ResponseWriter, r *http.Request) {
    org, member, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    if member.Role != "owner" {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Only the owner can delete an organization")
        return
    }
    if err := h.DB.DeleteOrg(r.Context(), org.ID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}

// ListOrgMembers handles GET /api/{api_version}/orgs/{slug}/members.
func (h *Handler) ListOrgMembers(w http.ResponseWriter, r *http.Request) {
    org, _, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    members, err := h.DB.ListOrgMembers(r.Context(), org.ID)
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, members)
}

type addMemberRequest struct {
    Username string `json:"username"`
    Role     string `json:"role"`
}

// AddOrgMember handles POST /api/{api_version}/orgs/{slug}/members — owner or
// org-admin adds an existing account straight into the org.
func (h *Handler) AddOrgMember(w http.ResponseWriter, r *http.Request) {
    org, member, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    if !canManageOrg(member) {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
        return
    }
    var req addMemberRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if req.Role != "admin" && req.Role != "member" {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Role must be admin or member")
        return
    }
    user, err := h.DB.GetUserByUsername(r.Context(), req.Username)
    if err != nil || user == nil {
        writeErr(w, http.StatusNotFound, "MEMBER_NOT_FOUND", "Member not found")
        return
    }
    if err := h.DB.AddOrgMember(r.Context(), &model.OrgMember{
        OrgID:    org.ID,
        UserID:   user.ID,
        Role:     req.Role,
        JoinedAt: time.Now().Unix(),
    }); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusCreated, map[string]any{"username": user.Username, "role": req.Role})
}

type changeRoleRequest struct {
    Role string `json:"role"`
}

// ChangeOrgMemberRole handles PUT /api/{api_version}/orgs/{slug}/members/{username}.
func (h *Handler) ChangeOrgMemberRole(w http.ResponseWriter, r *http.Request) {
    org, member, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    if !canManageOrg(member) {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
        return
    }
    var req changeRoleRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if req.Role != "owner" && req.Role != "admin" && req.Role != "member" {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Role must be owner, admin or member")
        return
    }
    if req.Role == "owner" && member.Role != "owner" {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Only the owner can transfer ownership")
        return
    }
    target, err := h.DB.GetUserByUsername(r.Context(), pathParam(r, "username"))
    if err != nil || target == nil {
        writeErr(w, http.StatusNotFound, "MEMBER_NOT_FOUND", "Member not found")
        return
    }
    if _, err := h.DB.GetOrgMember(r.Context(), org.ID, target.ID); err != nil {
        writeErr(w, http.StatusNotFound, "MEMBER_NOT_FOUND", "Member not found")
        return
    }
    if err := h.DB.UpdateOrgMemberRole(r.Context(), org.ID, target.ID, req.Role); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{"username": target.Username, "role": req.Role})
}

// RemoveOrgMember handles DELETE /api/{api_version}/orgs/{slug}/members/{username}.
// Owners and org-admins can remove anyone; any member can remove themselves.
func (h *Handler) RemoveOrgMember(w http.ResponseWriter, r *http.Request) {
    org, member, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    target, err := h.DB.GetUserByUsername(r.Context(), pathParam(r, "username"))
    if err != nil || target == nil {
        writeErr(w, http.StatusNotFound, "MEMBER_NOT_FOUND", "Member not found")
        return
    }
    self := target.ID == userIDFrom(r)
    if !self && !canManageOrg(member) {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
        return
    }
    if target.ID == org.OwnerID {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "The owner cannot be removed")
        return
    }
    if err := h.DB.RemoveOrgMember(r.Context(), org.ID, target.ID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}

type orgInviteRequest struct {
    Email string `json:"email"`
    Role  string `json:"role"`
}

// CreateOrgInvite handles POST /api/{api_version}/orgs/{slug}/invites.
func (h *Handler) CreateOrgInvite(w http.ResponseWriter, r *http.Request) {
    org, member, ok := h.orgContext(w, r)
    if !ok {
        return
    }
    if !canManageOrg(member) {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
        return
    }
    var req orgInviteRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    if err := model.ValidateEmail(req.Email); err != nil {
        writeErr(w, http.StatusBadRequest, "EMAIL_INVALID", err.Error())
        return
    }
    if req.Role != "admin" && req.Role != "member" {
        writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "Role must be admin or member")
        return
    }
    raw, hash, err := model.NewTokenRaw("")
    if err != nil {
        writeInternal(w)
        return
    }
    id, err := model.NewSessionID()
    if err != nil {
        writeInternal(w)
        return
    }
    now := time.Now().Unix()
    if err := h.DB.CreateOrgInvite(r.Context(), &model.OrgInvite{
        ID:        id,
        OrgID:     org.ID,
        Email:     req.Email,
        Role:      req.Role,
        InvitedBy: userIDFrom(r),
        TokenHash: hash,
        CreatedAt: now,
        ExpiresAt: now + orgInviteTTL,
    }); err != nil {
        writeInternal(w)
        return
    }
    link := fmt.Sprintf("%s/api/{api_version}/orgs/invites/%s", h.BaseURL, raw)
    data := map[string]any{"email": req.Email, "role": req.Role, "expires_at": now + orgInviteTTL}
    if h.Mail != nil && h.Mail.Configured() {
        if err := h.Mail.Send(r.Context(), req.Email,
            "You have been invited to "+org.DisplayName, "Accept the invite: "+link); err != nil {
            writeInternal(w)
            return
        }
    } else {
        data["invite_url"] = link
    }
    writeOK(w, http.StatusCreated, data)
}

// AcceptOrgInvite handles GET /api/{api_version}/orgs/invites/{token} for any
// logged-in user.
func (h *Handler) AcceptOrgInvite(w http.ResponseWriter, r *http.Request) {
    invite, err := h.DB.GetOrgInviteByTokenHash(r.Context(), model.HashToken(pathParam(r, "token")))
    if err != nil || invite == nil || invite.Accepted {
        writeErr(w, http.StatusBadRequest, "INVITE_INVALID", "This invite link is no longer valid")
        return
    }
    if time.Now().Unix() > invite.ExpiresAt {
        writeErr(w, http.StatusBadRequest, "INVITE_EXPIRED", "This invite has expired")
        return
    }
    if err := h.DB.AddOrgMember(r.Context(), &model.OrgMember{
        OrgID:    invite.OrgID,
        UserID:   userIDFrom(r),
        Role:     invite.Role,
        JoinedAt: time.Now().Unix(),
    }); err != nil {
        writeInternal(w)
        return
    }
    if err := h.DB.MarkOrgInviteAccepted(r.Context(), invite.ID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{
        "org_id":  invite.OrgID,
        "role":    invite.Role,
        "message": "Invite accepted. Welcome to the organization",
    })
}
```

### Feature 5 — Domain handler (`src/handler/domain_handler.go`)

Routes, all behind `RequireUser`: `GET|POST /api/{api_version}/domains` ·
`GET|DELETE /api/{api_version}/domains/{domain}` ·
`POST /api/{api_version}/domains/{domain}/verify`.

```go
package handler

import (
    "context"
    "errors"
    "net"
    "net/http"
    "strconv"
    "strings"
    "time"

    "{MODULE}/src/middleware"
    "{MODULE}/src/model"
)

const dnsVerifyTimeout = 10 * time.Second

// authorizeOwner reports whether the caller may act for (ownerType, ownerID):
// their own user row, or an org they own or administer.
func (h *Handler) authorizeOwner(r *http.Request, ownerType string, ownerID int64) (bool, error) {
    userID := userIDFrom(r)
    switch ownerType {
    case "user":
        return ownerID == userID, nil
    case "org":
        member, err := h.DB.GetOrgMember(r.Context(), ownerID, userID)
        if err != nil && !errors.Is(err, ErrNotFound) {
            return false, err
        }
        return canManageOrg(member), nil
    default:
        return false, nil
    }
}

// ListDomains handles GET /api/{api_version}/domains. Defaults to the caller's
// own domains; ?owner_type=org&owner_id=N lists an org's domains.
func (h *Handler) ListDomains(w http.ResponseWriter, r *http.Request) {
    ownerType := r.URL.Query().Get("owner_type")
    ownerID := userIDFrom(r)
    if ownerType == "" {
        ownerType = "user"
    }
    if ownerType == "org" {
        parsed, err := strconv.ParseInt(r.URL.Query().Get("owner_id"), 10, 64)
        if err != nil {
            writeErr(w, http.StatusBadRequest, "INVALID_REQUEST", "owner_id must be an integer")
            return
        }
        ownerID = parsed
    }
    allowed, err := h.authorizeOwner(r, ownerType, ownerID)
    if err != nil {
        writeInternal(w)
        return
    }
    if !allowed {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
        return
    }
    domains, err := h.DB.ListDomains(r.Context(), ownerType, ownerID)
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, domains)
}

type addDomainRequest struct {
    Domain    string `json:"domain"`
    OwnerType string `json:"owner_type"`
    OwnerID   int64  `json:"owner_id"`
}

// AddDomain handles POST /api/{api_version}/domains.
func (h *Handler) AddDomain(w http.ResponseWriter, r *http.Request) {
    var req addDomainRequest
    if !decodeJSON(w, r, &req) {
        return
    }
    domain := strings.ToLower(strings.TrimSpace(req.Domain))
    if err := model.ValidateDomain(domain); err != nil {
        writeErr(w, http.StatusBadRequest, "DOMAIN_INVALID", err.Error())
        return
    }
    if req.OwnerType == "" {
        req.OwnerType = "user"
        req.OwnerID = userIDFrom(r)
    }
    allowed, err := h.authorizeOwner(r, req.OwnerType, req.OwnerID)
    if err != nil {
        writeInternal(w)
        return
    }
    if !allowed {
        writeErr(w, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions")
        return
    }
    existing, err := h.DB.GetDomainByName(r.Context(), domain)
    if err != nil && !errors.Is(err, ErrNotFound) {
        writeInternal(w)
        return
    }
    if existing != nil {
        writeErr(w, http.StatusConflict, "DOMAIN_TAKEN", "That domain is already registered")
        return
    }
    verifyToken, err := model.NewSessionID()
    if err != nil {
        writeInternal(w)
        return
    }
    now := time.Now().Unix()
    id, err := h.DB.CreateDomain(r.Context(), &model.CustomDomain{
        Domain:      domain,
        OwnerType:   req.OwnerType,
        OwnerID:     req.OwnerID,
        VerifyToken: verifyToken,
        CreatedAt:   now,
        UpdatedAt:   now,
    })
    if err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusCreated, map[string]any{
        "id":          id,
        "domain":      domain,
        "verify_host": "_verify." + domain,
        "verify_txt":  verifyToken,
    })
}

// loadOwnedDomain fetches the path domain and checks the caller may act on it.
func (h *Handler) loadOwnedDomain(w http.ResponseWriter, r *http.Request) (*model.CustomDomain, bool) {
    domain, err := h.DB.GetDomainByName(r.Context(), strings.ToLower(pathParam(r, "domain")))
    if err != nil || domain == nil {
        writeErr(w, http.StatusNotFound, "DOMAIN_NOT_FOUND", "Domain not found")
        return nil, false
    }
    allowed, err := h.authorizeOwner(r, domain.OwnerType, domain.OwnerID)
    if err != nil {
        writeInternal(w)
        return nil, false
    }
    if !allowed {
        writeErr(w, http.StatusNotFound, "DOMAIN_NOT_FOUND", "Domain not found")
        return nil, false
    }
    return domain, true
}

// GetDomain handles GET /api/{api_version}/domains/{domain}.
func (h *Handler) GetDomain(w http.ResponseWriter, r *http.Request) {
    domain, ok := h.loadOwnedDomain(w, r)
    if !ok {
        return
    }
    writeOK(w, http.StatusOK, domain)
}

// DeleteDomain handles DELETE /api/{api_version}/domains/{domain}.
func (h *Handler) DeleteDomain(w http.ResponseWriter, r *http.Request) {
    domain, ok := h.loadOwnedDomain(w, r)
    if !ok {
        return
    }
    if err := h.DB.DeleteDomain(r.Context(), domain.ID); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, nil)
}

// VerifyDomain handles POST /api/{api_version}/domains/{domain}/verify: it looks
// up TXT _verify.{domain} with a 10s timeout and matches the stored token.
func (h *Handler) VerifyDomain(w http.ResponseWriter, r *http.Request) {
    domain, ok := h.loadOwnedDomain(w, r)
    if !ok {
        return
    }
    ctx, cancel := context.WithTimeout(r.Context(), dnsVerifyTimeout)
    defer cancel()

    var resolver net.Resolver
    records, err := resolver.LookupTXT(ctx, "_verify."+domain.Domain)
    if err != nil {
        writeErr(w, http.StatusBadRequest, "DOMAIN_VERIFY_FAILED",
            "DNS verification failed. Check the TXT record and try again")
        return
    }
    matched := false
    for _, rec := range records {
        if middleware.ConstantTimeEqStr(strings.TrimSpace(rec), domain.VerifyToken) {
            matched = true
            break
        }
    }
    if !matched {
        writeErr(w, http.StatusBadRequest, "DOMAIN_VERIFY_FAILED",
            "DNS verification failed. Check the TXT record and try again")
        return
    }
    if err := h.DB.SetDomainVerified(r.Context(), domain.ID, time.Now().Unix()); err != nil {
        writeInternal(w)
        return
    }
    writeOK(w, http.StatusOK, map[string]any{"domain": domain.Domain, "verified": true})
}
```

Certificate issuance for a freshly verified domain is the project's existing TLS
concern — call whatever ACME/Let's Encrypt helper the project already has right
after `SetDomainVerified`, and leave `ssl_enabled`/`ssl_cert_path`/`ssl_key_path`
untouched when the project has none.

---

## Step 9 — Frontend HTML templates

Create under `{TEMPLATE_DIR}/auth/`. Discover the project's existing layout template name from Step 1 and extend it. If no layout exists, create a minimal standalone layout for the auth pages.

All templates use Go's `html/template` package. All user-supplied values are `{{.Field}}` — never `template.HTML`. Wrap the frontend route group in `middleware.CSRFDouble` (Step 6) so every GET issues a `csrf_token` cookie and every POST/PUT/PATCH/DELETE verifies it; each page handler reads the token back out of the request context (`r.Context().Value(middleware.CtxCSRFToken)` — cast to `string`) and sets it as `.CSRFToken` on the template data before rendering. CSRF token is injected as `{{.CSRFToken}}` on every form.

### Admin login — `{TEMPLATE_DIR}/auth/admin_login.html`

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    <h1 class="auth-title">Admin Sign In</h1>
    {{if .Error}}
    <div class="alert alert-error" role="alert">{{.Error}}</div>
    {{end}}
    <form method="POST" action="/server/{{.AdminPath}}/auth/login" autocomplete="off">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <div class="field">
        <label for="username">Username</label>
        <input id="username" type="text" name="username" value="{{.Username}}"
               autocomplete="username" required autofocus>
      </div>
      <div class="field">
        <label for="password">Password</label>
        <input id="password" type="password" name="password"
               autocomplete="current-password" required>
      </div>
      {{if .TOTPRequired}}
      <div class="field">
        <label for="totp_code">Authenticator code</label>
        <input id="totp_code" type="text" name="totp_code" inputmode="numeric"
               pattern="[0-9]{6}" autocomplete="one-time-code" placeholder="000000">
      </div>
      {{end}}
      <button type="submit" class="btn btn-primary btn-full">Sign in</button>
    </form>
  </div>
</div>
{{end}}
```

### User registration — `{TEMPLATE_DIR}/auth/register.html`

**Only rendered when `users.registration.mode == "open"`** — the route handler returns 404 before this template is invoked when `mode == "private"`.

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    <h1 class="auth-title">Create an account</h1>
    {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}
    <form method="POST" action="/api/{{.APIVersion}}/auth/register">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <div class="field">
        <label for="username">Username</label>
        <input id="username" type="text" name="username" value="{{.Username}}"
               pattern="[a-zA-Z0-9_\-]{3,32}" autocomplete="username" required autofocus>
        <span class="field-hint">3-32 characters: letters, digits, _ or -</span>
      </div>
      <div class="field">
        <label for="email">Email</label>
        <input id="email" type="email" name="email" value="{{.Email}}"
               autocomplete="email" required>
      </div>
      <div class="field">
        <label for="password">Password</label>
        <input id="password" type="password" name="password" minlength="8"
               autocomplete="new-password" required>
        <span class="field-hint">At least 8 characters</span>
      </div>
      <button type="submit" class="btn btn-primary btn-full">Create account</button>
    </form>
    <p class="auth-footer">Already have an account? <a href="/auth/login">Sign in</a></p>
  </div>
</div>
{{end}}
```

### User login — `{TEMPLATE_DIR}/auth/login.html`

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    <h1 class="auth-title">Sign in</h1>
    {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}
    <form method="POST" action="/api/{{.APIVersion}}/auth/login">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <input type="hidden" name="redirect" value="{{.Redirect}}">
      <div class="field">
        <label for="login">Username or email</label>
        <input id="login" type="text" name="login" value="{{.Login}}"
               autocomplete="username" required autofocus>
      </div>
      <div class="field">
        <label for="password">
          Password
          <a href="/auth/password/reset" class="field-label-action">Forgot password?</a>
        </label>
        <input id="password" type="password" name="password"
               autocomplete="current-password" required>
      </div>
      <button type="submit" class="btn btn-primary btn-full">Sign in</button>
    </form>
    <p class="auth-footer">No account? <a href="/auth/register">Create one</a></p>
  </div>
</div>
{{end}}
```

### Password reset request — `{TEMPLATE_DIR}/auth/password_reset_request.html`

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    <h1 class="auth-title">Reset your password</h1>
    {{if .Success}}
    <div class="alert alert-success" role="status">
      If an account exists for that email, a reset link has been sent.
    </div>
    {{else}}
    {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}
    <form method="POST" action="/api/{{.APIVersion}}/auth/password/reset/request">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <div class="field">
        <label for="email">Email address</label>
        <input id="email" type="email" name="email" value="{{.Email}}"
               autocomplete="email" required autofocus>
      </div>
      <button type="submit" class="btn btn-primary btn-full">Send reset link</button>
    </form>
    {{end}}
    <p class="auth-footer"><a href="/auth/login">Back to sign in</a></p>
  </div>
</div>
{{end}}
```

### Password reset confirm — `{TEMPLATE_DIR}/auth/password_reset_confirm.html`

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    <h1 class="auth-title">Set new password</h1>
    {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}
    <form method="POST" action="/api/{{.APIVersion}}/auth/password/reset/confirm">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <input type="hidden" name="token" value="{{.Token}}">
      <div class="field">
        <label for="new_password">New password</label>
        <input id="new_password" type="password" name="new_password"
               minlength="8" autocomplete="new-password" required autofocus>
        <span class="field-hint">At least 8 characters</span>
      </div>
      <button type="submit" class="btn btn-primary btn-full">Set password</button>
    </form>
  </div>
</div>
{{end}}
```

### Invite / activation accept — `{TEMPLATE_DIR}/auth/invite_accept.html`

Rendered for both the admin-invite and direct-create private-mode flows (Step 4/8) — the token identifies which; the form is identical either way. If the token is invalid/expired/used, render the generic invalid state instead of this form (never distinguish the reason).

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    {{if .InviteValid}}
    <h1 class="auth-title">Welcome, {{.Username}}</h1>
    <p>Set a password to activate your account.</p>
    {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}
    <form method="POST" action="/api/{{.APIVersion}}/auth/invite/{{.Token}}/accept">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <div class="field">
        <label for="password">Password</label>
        <input id="password" type="password" name="password" minlength="8"
               autocomplete="new-password" required autofocus>
        <span class="field-hint">At least 8 characters</span>
      </div>
      <button type="submit" class="btn btn-primary btn-full">Activate account</button>
    </form>
    {{else}}
    <h1 class="auth-title">This invite link is no longer valid</h1>
    <p class="auth-footer">Ask your administrator for a new invite.</p>
    {{end}}
  </div>
</div>
{{end}}
```

### User profile — `{TEMPLATE_DIR}/auth/profile.html`

```html
{{template "layout" .}}
{{define "content"}}
<div class="profile-container">
  <h1 class="page-title">Profile</h1>
  {{if .Success}}<div class="alert alert-success" role="status">{{.Success}}</div>{{end}}
  {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}

  <section class="profile-section">
    <h2>Account</h2>
    <dl class="profile-info">
      <dt>Username</dt><dd>{{.User.Username}}</dd>
      <dt>Email</dt>
      <dd>{{.User.Email}}
        {{if not .User.EmailVerified}}
        <span class="badge badge-warning">unverified</span>
        {{end}}
      </dd>
      <dt>Member since</dt><dd>{{.User.CreatedAt | formatDate}}</dd>
    </dl>
  </section>

  <section class="profile-section">
    <h2>Edit profile</h2>
    <form method="POST" action="/api/{{.APIVersion}}/auth/me">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <input type="hidden" name="_method" value="PUT">
      <div class="field">
        <label for="display_name">Display name</label>
        <input id="display_name" type="text" name="display_name"
               value="{{.User.DisplayName}}" maxlength="100">
      </div>
      <div class="field">
        <label for="bio">Bio</label>
        <textarea id="bio" name="bio" rows="3" maxlength="500">{{.User.Bio}}</textarea>
      </div>
      <button type="submit" class="btn btn-primary">Save changes</button>
    </form>
  </section>

  <section class="profile-section">
    <h2>API tokens</h2>
    {{if .Tokens}}
    <table class="table">
      <thead><tr><th>Name</th><th>Created</th><th>Last used</th><th></th></tr></thead>
      <tbody>
        {{range .Tokens}}
        <tr>
          <td>{{.Name}}</td>
          <td>{{.CreatedAt | formatDate}}</td>
          <td>{{if .LastUsed}}{{.LastUsed | formatDate}}{{else}}Never{{end}}</td>
          <td>
            <form method="POST" action="/api/{{$.APIVersion}}/auth/tokens/{{.ID}}"
                  data-confirm="revoke-token-{{.ID}}">
              <input type="hidden" name="csrf_token" value="{{$.CSRFToken}}">
              <input type="hidden" name="_method" value="DELETE">
              <button type="submit" class="btn btn-danger btn-sm">Revoke</button>
            </form>
            <!-- Native dialog: focus trap, Escape, and ::backdrop are built in; Cancel closes with zero JS via form method="dialog". -->
            <!-- External JS (addEventListener on [data-confirm]) intercepts submit and calls showModal(); without JS the form submits directly — never inline onclick/confirm() (blocked by CSP). -->
            <dialog id="revoke-token-{{.ID}}" aria-labelledby="revoke-token-title-{{.ID}}">
              <p id="revoke-token-title-{{.ID}}">Revoke this token? Applications using it will stop working immediately.</p>
              <form method="dialog">
                <button value="cancel" class="btn btn-secondary btn-sm">Cancel</button>
                <button value="confirm" class="btn btn-danger btn-sm">Revoke</button>
              </form>
            </dialog>
          </td>
        </tr>
        {{end}}
      </tbody>
    </table>
    {{else}}
    <p class="empty-state">No API tokens yet.</p>
    {{end}}
    <form method="POST" action="/api/{{.APIVersion}}/auth/tokens" class="inline-form">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <input type="text" name="name" placeholder="Token name" required>
      <button type="submit" class="btn btn-secondary">Create token</button>
    </form>
    {{if .NewToken}}
    <div class="alert alert-info token-reveal" role="status">
      <strong>Copy this token now — it will not be shown again:</strong>
      <code class="token-value">{{.NewToken}}</code>
    </div>
    {{end}}
  </section>
</div>
{{end}}
```

### Org creation — `{TEMPLATE_DIR}/auth/org_new.html`

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    <h1 class="auth-title">Create an organization</h1>
    {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}
    <form method="POST" action="/api/{{.APIVersion}}/orgs">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <div class="field">
        <label for="slug">Organization name (URL slug)</label>
        <input id="slug" type="text" name="slug" value="{{.Slug}}"
               pattern="[a-z0-9][a-z0-9\-]*[a-z0-9]" minlength="2" maxlength="39"
               autocomplete="off" required autofocus>
        <span class="field-hint">2-39 lowercase letters, digits, or hyphens</span>
      </div>
      <div class="field">
        <label for="display_name">Display name</label>
        <input id="display_name" type="text" name="display_name"
               value="{{.DisplayName}}" required>
      </div>
      <div class="field">
        <label for="description">Description <span class="optional">(optional)</span></label>
        <textarea id="description" name="description" rows="2">{{.Description}}</textarea>
      </div>
      <button type="submit" class="btn btn-primary btn-full">Create organization</button>
    </form>
  </div>
</div>
{{end}}
```

### Custom domain add — `{TEMPLATE_DIR}/auth/domain_add.html`

```html
{{template "layout" .}}
{{define "content"}}
<div class="auth-container">
  <div class="auth-card">
    <h1 class="auth-title">Add custom domain</h1>
    {{if .Error}}<div class="alert alert-error" role="alert">{{.Error}}</div>{{end}}
    <form method="POST" action="/api/{{.APIVersion}}/domains">
      <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
      <div class="field">
        <label for="domain">Domain name</label>
        <input id="domain" type="text" name="domain" value="{{.Domain}}"
               placeholder="example.com" autocomplete="off" required autofocus>
        <span class="field-hint">Enter the domain without https://</span>
      </div>
      <button type="submit" class="btn btn-primary btn-full">Add domain</button>
    </form>
    {{if .VerifyToken}}
    <div class="alert alert-info">
      <strong>DNS verification required.</strong>
      Add this TXT record to your domain:
      <dl class="dns-record">
        <dt>Name</dt><dd><code>_verify.{{.Domain}}</code></dd>
        <dt>Value</dt><dd><code>{{.VerifyToken}}</code></dd>
      </dl>
      <form method="POST" action="/api/{{.APIVersion}}/domains/{{.Domain}}/verify">
        <input type="hidden" name="csrf_token" value="{{.CSRFToken}}">
        <button type="submit" class="btn btn-secondary">Verify DNS</button>
      </form>
    </div>
    {{end}}
  </div>
</div>
{{end}}
```

---

## Step 10 — Frontend routes (HTML page routes)

Register HTML-serving routes alongside the API routes. Each HTML route renders the corresponding template with a page-data struct. These are GET routes; POST submits go to the API routes and redirect on success.

| Method | Path | Template | Auth |
|--------|------|----------|------|
| GET | `/server/{admin_path}/auth/login` | `auth/admin_login.html` | none |
| GET | `/auth/register` | `auth/register.html` (404 when `users.registration.mode == "private"`) | none |
| GET | `/auth/login` | `auth/login.html` | none |
| GET | `/auth/password/reset` | `auth/password_reset_request.html` | none |
| GET | `/auth/password/reset/confirm` | `auth/password_reset_confirm.html` | none |
| GET | `/auth/invite/{token}` | `auth/invite_accept.html` | none |
| GET | `/auth/me` | `auth/profile.html` | RequireUser |
| GET | `/orgs/new` | `auth/org_new.html` | RequireUser |
| GET | `/domains/add` | `auth/domain_add.html` | RequireUser |

---

## Step 11 — Route registration

Find the router file. Add these route groups in middleware order:

```
Allowlist → Blocklist → RateLimit → GeoIP → CSRF → Auth → Handler
```

Admin routes use the admin session middleware. User routes use the user session or token middleware. Public auth routes (login, register, reset) have no auth middleware but have rate limiting. `middleware.CSRFDouble` wraps every route in Step 9's frontend group and every non-token-authenticated route in Step 8's API group (i.e. everything reachable from a browser form) — it must sit outside `RequireAdmin`/`RequireUser` so the token check still runs, but does not need to wrap `RequireToken`-protected API routes, since Bearer-token clients are not vulnerable to cross-site form submission.

---

## Step 12 — Config

Extend the project's config struct and YAML example:

```go
type AuthConfig struct {
    Admin   AdminAuthConfig   `yaml:"admin"`
    Users   UsersAuthConfig   `yaml:"users"`
    Tokens  TokensAuthConfig  `yaml:"tokens"`
}

type AdminAuthConfig struct {
    // default: 86400 (24h)
    SessionTimeout     int  `yaml:"session_timeout"`
    // default: 3600 (1h idle)
    SessionIdleTimeout int  `yaml:"session_idle_timeout"`
    // default: false
    RequireTOTP        bool `yaml:"require_totp"`
    // default: 5
    MaxSessions        int  `yaml:"max_sessions"`
}

type UsersAuthConfig struct {
    Registration              RegistrationConfig `yaml:"registration"`
    // default: true
    RequireEmailVerification bool `yaml:"require_email_verification"`
    // default: 2592000 (30d)
    SessionTimeout           int  `yaml:"session_timeout"`
    // default: 86400 (24h)
    SessionIdleTimeout       int  `yaml:"session_idle_timeout"`
    // default: 10
    MaxSessionsPerUser       int  `yaml:"max_sessions_per_user"`
    // default: 604800 (7d); seconds — invite/activation link TTL
    InviteExpiry             int  `yaml:"invite_expiry"`
}

type RegistrationConfig struct {
    // "open" (anyone can self-register, default) or "private" (admin invite/create only —
    // /auth/register returns 404). There is no "disabled" mode: to stop growth under
    // "private", the admin simply stops inviting/creating users. Admin invite and direct-create
    // are available in BOTH modes — this setting only gates the public self-registration form.
    Mode string `yaml:"mode"`
}

type TokensAuthConfig struct {
    // default: 0 (never); seconds
    DefaultExpiry int `yaml:"default_expiry"`
}
```

```yaml
server:
  auth:
    admin:
      session_timeout: 86400
      session_idle_timeout: 3600
      require_totp: false
      max_sessions: 5
    users:
      registration:
        # open | private
        mode: open
      require_email_verification: true
      session_timeout: 2592000
      session_idle_timeout: 86400
      max_sessions_per_user: 10
      invite_expiry: 604800
    tokens:
      default_expiry: 0
```

---

## Step 13 — i18n strings

Find the project's i18n translation files (`find src -name "*.json" -path "*/i18n/*" -o -name "*.json" -path "*/locales/*"`). Add an `"auth"` key:

```json
"auth": {
  "invalid_credentials":          "Invalid credentials",
  "account_suspended":            "Your account has been suspended",
  "email_not_verified":           "Please verify your email address before signing in",
  "session_expired":              "Your session has expired. Please sign in again",
  "rate_limited":                 "Too many attempts. Try again in {minutes} minutes",
  "password_too_short":           "Password must be at least 8 characters",
  "password_whitespace":          "Password cannot start or end with whitespace",
  "username_invalid":             "Username must be 3-32 characters: letters, digits, _ or -",
  "email_invalid":                "Please enter a valid email address",
  "email_taken":                  "An account with that email already exists",
  "username_taken":               "That username is already taken",
  "registration_closed":          "Registration is currently by invitation only",
  "invite_invalid":               "This invite link is no longer valid",
  "invite_sent":                  "Invite created — share the link with the new user",
  "invite_username_taken":        "That username already has a pending or active account",
  "password_reset_sent":          "If an account exists for that email, a reset link has been sent",
  "password_reset_expired":       "This reset link has expired. Please request a new one",
  "password_reset_used":          "This reset link has already been used",
  "email_verification_sent":      "Verification email sent. Check your inbox",
  "email_verification_expired":   "This verification link has expired. Please request a new one",
  "email_verification_success":   "Email address verified",
  "totp_required":                "Two-factor authentication code required",
  "totp_invalid":                 "Invalid authenticator code",
  "totp_enabled":                 "Two-factor authentication enabled",
  "totp_disabled":                "Two-factor authentication disabled",
  "token_created":                "API token created. Copy it now — it will not be shown again",
  "token_revoked":                "Token revoked",
  "token_not_found":              "Token not found",
  "org_slug_invalid":             "Organization name must be 2-39 lowercase letters, digits, or hyphens",
  "org_slug_taken":               "That organization name is already taken",
  "org_not_found":                "Organization not found",
  "org_member_not_found":         "Member not found",
  "org_invite_expired":           "This invite has expired",
  "org_invite_accepted":          "Invite accepted. Welcome to the organization",
  "domain_invalid":               "Please enter a valid domain name (e.g. example.com)",
  "domain_taken":                 "That domain is already registered",
  "domain_not_verified":          "Domain ownership not yet verified",
  "domain_verify_success":        "Domain verified",
  "domain_verify_failed":         "DNS verification failed. Check the TXT record and try again"
}
```

---

## Step 14 — Tests

Write table-driven tests with the standard `testing` package and
`net/http/httptest` — no third-party test framework. Every category below is
covered concretely for admin login and for user login/register; apply the exact
same pattern to every other handler from Step 8.

### Shared test doubles (`src/handler/handler_test.go`)

`stubStore` embeds the `Store` interface so only the methods a given test needs
have to be written; any unimplemented method panics, which correctly fails a
test that calls something it did not stub.

```go
package handler

import (
    "context"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"

    "{MODULE}/src/config"
    "{MODULE}/src/model"
)

// stubStore satisfies Store by embedding it; each test fills in only the hooks
// the handler under test actually calls.
type stubStore struct {
    Store

    adminByUsername func(ctx context.Context, username string) (*model.Admin, error)
    adminByID       func(ctx context.Context, id int64) (*model.Admin, error)
    createAdminSess func(ctx context.Context, s *model.AdminSession) error
    adminSessByID   func(ctx context.Context, id string) (*model.AdminSession, error)
    updateAdminLog  func(ctx context.Context, adminID, at int64, ip string) error

    userByLogin    func(ctx context.Context, login string) (*model.User, error)
    userByUsername func(ctx context.Context, username string) (*model.User, error)
    userByEmail    func(ctx context.Context, email string) (*model.User, error)
    createUser     func(ctx context.Context, u *model.User) (int64, error)
    createUserSess func(ctx context.Context, s *model.UserSession) error
    updateUserLog  func(ctx context.Context, userID, at int64, ip string) error
}

func (s *stubStore) GetAdminByUsername(ctx context.Context, username string) (*model.Admin, error) {
    return s.adminByUsername(ctx, username)
}

func (s *stubStore) GetAdminByID(ctx context.Context, id int64) (*model.Admin, error) {
    return s.adminByID(ctx, id)
}

func (s *stubStore) CreateAdminSession(ctx context.Context, sess *model.AdminSession) error {
    if s.createAdminSess == nil {
        return nil
    }
    return s.createAdminSess(ctx, sess)
}

func (s *stubStore) GetAdminSessionByID(ctx context.Context, id string) (*model.AdminSession, error) {
    return s.adminSessByID(ctx, id)
}

func (s *stubStore) UpdateAdminLogin(ctx context.Context, adminID, at int64, ip string) error {
    if s.updateAdminLog == nil {
        return nil
    }
    return s.updateAdminLog(ctx, adminID, at, ip)
}

func (s *stubStore) GetUserByLogin(ctx context.Context, login string) (*model.User, error) {
    return s.userByLogin(ctx, login)
}

func (s *stubStore) GetUserByUsername(ctx context.Context, username string) (*model.User, error) {
    return s.userByUsername(ctx, username)
}

func (s *stubStore) GetUserByEmail(ctx context.Context, email string) (*model.User, error) {
    return s.userByEmail(ctx, email)
}

func (s *stubStore) CreateUser(ctx context.Context, u *model.User) (int64, error) {
    return s.createUser(ctx, u)
}

func (s *stubStore) CreateUserSession(ctx context.Context, sess *model.UserSession) error {
    if s.createUserSess == nil {
        return nil
    }
    return s.createUserSess(ctx, sess)
}

func (s *stubStore) UpdateUserLogin(ctx context.Context, userID, at int64, ip string) error {
    if s.updateUserLog == nil {
        return nil
    }
    return s.updateUserLog(ctx, userID, at, ip)
}

// newTestHandler builds a Handler with sane defaults for the auth config.
func newTestHandler(store Store) *Handler {
    h := &Handler{
        DB:         store,
        Auth:       config.AuthConfig{},
        ServerName: "{project_name}",
        BaseURL:    "https://example.test",
        AdminPath:  "{admin_path}",
    }
    h.Auth.Admin.SessionTimeout = defaultAdminSessionTimeout
    h.Auth.Users.SessionTimeout = defaultUserSessionTimeout
    h.Auth.Users.Registration.Mode = "open"
    return h
}

// mustHash produces a real argon2id hash so CheckPassword is exercised for real.
func mustHash(t *testing.T, password string) string {
    t.Helper()
    hash, err := model.HashPassword(password)
    if err != nil {
        t.Fatalf("HashPassword: %v", err)
    }
    return hash
}

// postJSON runs a handler against a JSON POST and returns the recorder.
func postJSON(h http.HandlerFunc, path, body string) *httptest.ResponseRecorder {
    r := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
    r.Header.Set("Content-Type", "application/json")
    r.RemoteAddr = "203.0.113.10:54321"
    w := httptest.NewRecorder()
    h(w, r)
    return w
}

// decodeEnvelope reads the {"ok":...} envelope common to every handler.
func decodeEnvelope(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
    t.Helper()
    var out map[string]any
    if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
        t.Fatalf("response is not JSON: %v (%q)", err, w.Body.String())
    }
    return out
}

// cookieNamed returns the Set-Cookie entry with the given name, or nil.
func cookieNamed(w *httptest.ResponseRecorder, name string) *http.Cookie {
    for _, c := range w.Result().Cookies() {
        if c.Name == name {
            return c
        }
    }
    return nil
}
```

### Admin login (`src/handler/admin_auth_handler_test.go`)

Covers happy path, invalid input, wrong credentials, unknown account (identical
response), and an account created by admin with an empty `password_hash`.

```go
package handler

import (
    "context"
    "net/http"
    "net/http/httptest"
    "testing"

    "{MODULE}/src/model"
)

func TestAdminLogin(t *testing.T) {
    const password = "correct-horse-battery-staple"
    hash := mustHash(t, password)

    admin := &model.Admin{ID: 1, Username: "root", PasswordHash: hash}
    pendingAdmin := &model.Admin{ID: 2, Username: "pending", PasswordHash: ""}

    tests := []struct {
        name       string
        body       string
        lookup     func(ctx context.Context, username string) (*model.Admin, error)
        wantStatus int
        wantCode   string
        wantCookie bool
    }{
        {
            name: "happy path issues a session cookie",
            body: `{"username":"root","password":"` + password + `"}`,
            lookup: func(context.Context, string) (*model.Admin, error) {
                return admin, nil
            },
            wantStatus: http.StatusOK,
            wantCookie: true,
        },
        {
            name: "malformed json is rejected",
            body: `{"username":`,
            lookup: func(context.Context, string) (*model.Admin, error) {
                t.Fatal("store must not be reached for malformed JSON")
                return nil, nil
            },
            wantStatus: http.StatusBadRequest,
            wantCode:   "INVALID_JSON",
        },
        {
            name: "missing password is rejected before any lookup",
            body: `{"username":"root"}`,
            lookup: func(context.Context, string) (*model.Admin, error) {
                t.Fatal("store must not be reached without a password")
                return nil, nil
            },
            wantStatus: http.StatusBadRequest,
            wantCode:   "INVALID_REQUEST",
        },
        {
            name: "wrong password",
            body: `{"username":"root","password":"wrong"}`,
            lookup: func(context.Context, string) (*model.Admin, error) {
                return admin, nil
            },
            wantStatus: http.StatusUnauthorized,
            wantCode:   "INVALID_CREDENTIALS",
        },
        {
            name: "unknown username gives the same answer as a wrong password",
            body: `{"username":"nobody","password":"` + password + `"}`,
            lookup: func(context.Context, string) (*model.Admin, error) {
                return nil, ErrNotFound
            },
            wantStatus: http.StatusUnauthorized,
            wantCode:   "INVALID_CREDENTIALS",
        },
        {
            name: "empty stored hash can never authenticate",
            body: `{"username":"pending","password":""}`,
            lookup: func(context.Context, string) (*model.Admin, error) {
                return pendingAdmin, nil
            },
            wantStatus: http.StatusBadRequest,
            wantCode:   "INVALID_REQUEST",
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            h := newTestHandler(&stubStore{adminByUsername: tc.lookup})
            w := postJSON(h.AdminLogin, "/server/{admin_path}/auth/login", tc.body)

            if w.Code != tc.wantStatus {
                t.Fatalf("status = %d, want %d (body %q)", w.Code, tc.wantStatus, w.Body.String())
            }
            env := decodeEnvelope(t, w)
            if tc.wantCode == "" {
                if env["ok"] != true {
                    t.Fatalf("ok = %v, want true", env["ok"])
                }
            } else {
                if env["ok"] != false {
                    t.Fatalf("ok = %v, want false", env["ok"])
                }
                if env["error"] != tc.wantCode {
                    t.Fatalf("error = %v, want %q", env["error"], tc.wantCode)
                }
                if env["message"] == "" || env["message"] == nil {
                    t.Fatal("error envelope is missing a human message")
                }
            }

            cookie := cookieNamed(w, "admin_session")
            if tc.wantCookie {
                if cookie == nil {
                    t.Fatal("admin_session cookie was not set")
                }
                if !cookie.HttpOnly || !cookie.Secure || cookie.SameSite != http.SameSiteStrictMode {
                    t.Fatalf("cookie attributes = HttpOnly:%v Secure:%v SameSite:%v, want true/true/Strict",
                        cookie.HttpOnly, cookie.Secure, cookie.SameSite)
                }
                if cookie.Path != h.adminCookiePath() {
                    t.Fatalf("cookie path = %q, want %q", cookie.Path, h.adminCookiePath())
                }
            } else if cookie != nil {
                t.Fatal("a session cookie was issued for a failed login")
            }
        })
    }
}

// TestAdminLoginRejectsUnknownAndWrongIdentically pins the two failure bodies
// together so a future edit cannot make them distinguishable.
func TestAdminLoginRejectsUnknownAndWrongIdentically(t *testing.T) {
    hash := mustHash(t, "correct-horse-battery-staple")

    known := newTestHandler(&stubStore{
        adminByUsername: func(context.Context, string) (*model.Admin, error) {
            return &model.Admin{ID: 1, Username: "root", PasswordHash: hash}, nil
        },
    })
    unknown := newTestHandler(&stubStore{
        adminByUsername: func(context.Context, string) (*model.Admin, error) {
            return nil, ErrNotFound
        },
    })

    a := postJSON(known.AdminLogin, "/server/{admin_path}/auth/login", `{"username":"root","password":"nope"}`)
    b := postJSON(unknown.AdminLogin, "/server/{admin_path}/auth/login", `{"username":"ghost","password":"nope"}`)

    if a.Code != b.Code {
        t.Fatalf("status differs: %d vs %d", a.Code, b.Code)
    }
    if a.Body.String() != b.Body.String() {
        t.Fatalf("body differs:\n%q\n%q", a.Body.String(), b.Body.String())
    }
}

// TestAdminSessionAuthFailure covers the auth-failure category: no cookie, an
// unknown session id, and a session the store rejects as expired.
func TestAdminSessionAuthFailure(t *testing.T) {
    tests := []struct {
        name   string
        cookie string
        lookup func(ctx context.Context, id string) (*model.AdminSession, error)
    }{
        {
            name:   "no cookie at all",
            cookie: "",
            lookup: func(context.Context, string) (*model.AdminSession, error) {
                t.Fatal("store must not be reached without a cookie")
                return nil, nil
            },
        },
        {
            name:   "unknown session id",
            cookie: "deadbeef",
            lookup: func(context.Context, string) (*model.AdminSession, error) { return nil, ErrNotFound },
        },
        {
            name:   "expired session",
            cookie: "expired",
            lookup: func(context.Context, string) (*model.AdminSession, error) { return nil, ErrNotFound },
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            h := newTestHandler(&stubStore{adminSessByID: tc.lookup})
            r := httptest.NewRequest(http.MethodGet, "/server/{admin_path}/auth/session", nil)
            if tc.cookie != "" {
                r.AddCookie(&http.Cookie{Name: "admin_session", Value: tc.cookie})
            }
            w := httptest.NewRecorder()
            h.AdminSession(w, r)

            if w.Code != http.StatusUnauthorized {
                t.Fatalf("status = %d, want 401 (body %q)", w.Code, w.Body.String())
            }
            if env := decodeEnvelope(t, w); env["error"] != "UNAUTHORIZED" {
                t.Fatalf("error = %v, want UNAUTHORIZED", env["error"])
            }
        })
    }
}

// TestAdminTOTPRequired covers the second authentication factor.
func TestAdminTOTPRequired(t *testing.T) {
    const password = "correct-horse-battery-staple"
    secret, _, err := model.NewTOTPSecret("{project_name}", "root")
    if err != nil {
        t.Fatalf("NewTOTPSecret: %v", err)
    }
    admin := &model.Admin{
        ID: 1, Username: "root", PasswordHash: mustHash(t, password),
        TOTPSecret: secret, TOTPEnabled: true,
    }
    h := newTestHandler(&stubStore{
        adminByUsername: func(context.Context, string) (*model.Admin, error) { return admin, nil },
    })

    t.Run("missing code", func(t *testing.T) {
        w := postJSON(h.AdminLogin, "/server/{admin_path}/auth/login",
            `{"username":"root","password":"`+password+`"}`)
        if w.Code != http.StatusUnauthorized {
            t.Fatalf("status = %d, want 401", w.Code)
        }
        if env := decodeEnvelope(t, w); env["error"] != "TOTP_REQUIRED" {
            t.Fatalf("error = %v, want TOTP_REQUIRED", env["error"])
        }
    })

    t.Run("wrong code", func(t *testing.T) {
        w := postJSON(h.AdminLogin, "/server/{admin_path}/auth/login",
            `{"username":"root","password":"`+password+`","totp_code":"000000"}`)
        if w.Code != http.StatusUnauthorized {
            t.Fatalf("status = %d, want 401", w.Code)
        }
        if env := decodeEnvelope(t, w); env["error"] != "TOTP_INVALID" {
            t.Fatalf("error = %v, want TOTP_INVALID", env["error"])
        }
        if cookieNamed(w, "admin_session") != nil {
            t.Fatal("a session cookie was issued without a valid TOTP code")
        }
    })
}
```

### User login and registration (`src/handler/user_auth_handler_test.go`)

```go
package handler

import (
    "context"
    "net/http"
    "strings"
    "testing"

    "{MODULE}/src/model"
)

func TestUserLogin(t *testing.T) {
    const password = "correct-horse-battery-staple"
    active := &model.User{ID: 7, Username: "alice", Email: "alice@example.test", PasswordHash: mustHash(t, password)}
    invited := &model.User{ID: 8, Username: "bob", Email: "bob@example.test", PasswordHash: ""}
    banned := &model.User{ID: 9, Username: "mallory", Email: "m@example.test", PasswordHash: mustHash(t, password), Suspended: true}

    tests := []struct {
        name       string
        body       string
        lookup     func(ctx context.Context, login string) (*model.User, error)
        wantStatus int
        wantCode   string
        wantCookie bool
    }{
        {
            name:       "happy path by username",
            body:       `{"login":"alice","password":"` + password + `"}`,
            lookup:     func(context.Context, string) (*model.User, error) { return active, nil },
            wantStatus: http.StatusOK,
            wantCookie: true,
        },
        {
            name:       "happy path by email",
            body:       `{"login":"alice@example.test","password":"` + password + `"}`,
            lookup:     func(context.Context, string) (*model.User, error) { return active, nil },
            wantStatus: http.StatusOK,
            wantCookie: true,
        },
        {
            name:       "empty body is a bad request",
            body:       `{}`,
            lookup:     func(context.Context, string) (*model.User, error) { t.Fatal("unexpected lookup"); return nil, nil },
            wantStatus: http.StatusBadRequest,
            wantCode:   "INVALID_REQUEST",
        },
        {
            name:       "wrong password",
            body:       `{"login":"alice","password":"wrong"}`,
            lookup:     func(context.Context, string) (*model.User, error) { return active, nil },
            wantStatus: http.StatusUnauthorized,
            wantCode:   "INVALID_CREDENTIALS",
        },
        {
            name:       "unknown account is indistinguishable",
            body:       `{"login":"ghost","password":"` + password + `"}`,
            lookup:     func(context.Context, string) (*model.User, error) { return nil, ErrNotFound },
            wantStatus: http.StatusUnauthorized,
            wantCode:   "INVALID_CREDENTIALS",
        },
        {
            name:       "invited account with no password set cannot log in",
            body:       `{"login":"bob","password":"` + password + `"}`,
            lookup:     func(context.Context, string) (*model.User, error) { return invited, nil },
            wantStatus: http.StatusUnauthorized,
            wantCode:   "INVALID_CREDENTIALS",
        },
        {
            name:       "suspended account is refused after the password check",
            body:       `{"login":"mallory","password":"` + password + `"}`,
            lookup:     func(context.Context, string) (*model.User, error) { return banned, nil },
            wantStatus: http.StatusForbidden,
            wantCode:   "ACCOUNT_SUSPENDED",
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            h := newTestHandler(&stubStore{userByLogin: tc.lookup})
            w := postJSON(h.UserLogin, "/api/{api_version}/auth/login", tc.body)

            if w.Code != tc.wantStatus {
                t.Fatalf("status = %d, want %d (body %q)", w.Code, tc.wantStatus, w.Body.String())
            }
            env := decodeEnvelope(t, w)
            if tc.wantCode == "" {
                if env["ok"] != true {
                    t.Fatalf("ok = %v, want true", env["ok"])
                }
            } else if env["error"] != tc.wantCode {
                t.Fatalf("error = %v, want %q", env["error"], tc.wantCode)
            }

            cookie := cookieNamed(w, "user_session")
            if tc.wantCookie {
                if cookie == nil {
                    t.Fatal("user_session cookie was not set")
                }
                if !cookie.HttpOnly || !cookie.Secure || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/" {
                    t.Fatalf("cookie attributes = HttpOnly:%v Secure:%v SameSite:%v Path:%q",
                        cookie.HttpOnly, cookie.Secure, cookie.SameSite, cookie.Path)
                }
            } else if cookie != nil {
                t.Fatal("a session cookie was issued for a failed login")
            }
        })
    }
}

func TestUserRegister(t *testing.T) {
    notFound := func(context.Context, string) (*model.User, error) { return nil, ErrNotFound }
    taken := func(u *model.User) func(context.Context, string) (*model.User, error) {
        return func(context.Context, string) (*model.User, error) { return u, nil }
    }
    existing := &model.User{ID: 1, Username: "alice", Email: "alice@example.test"}

    tests := []struct {
        name        string
        mode        string
        body        string
        byUsername  func(ctx context.Context, username string) (*model.User, error)
        byEmail     func(ctx context.Context, email string) (*model.User, error)
        wantStatus  int
        wantCode    string
        wantCreated bool
    }{
        {
            name: "happy path creates the account and logs it in", mode: "open",
            body:       `{"username":"newbie","email":"newbie@example.test","password":"correct-horse-battery-staple"}`,
            byUsername: notFound, byEmail: notFound,
            wantStatus: http.StatusCreated, wantCreated: true,
        },
        {
            name: "private mode hides the route entirely", mode: "private",
            body:       `{"username":"newbie","email":"newbie@example.test","password":"correct-horse-battery-staple"}`,
            wantStatus: http.StatusNotFound, wantCode: "NOT_FOUND",
        },
        {
            name: "invalid username", mode: "open",
            body:       `{"username":"a","email":"newbie@example.test","password":"correct-horse-battery-staple"}`,
            wantStatus: http.StatusBadRequest, wantCode: "USERNAME_INVALID",
        },
        {
            name: "invalid email", mode: "open",
            body:       `{"username":"newbie","email":"not-an-email","password":"correct-horse-battery-staple"}`,
            wantStatus: http.StatusBadRequest, wantCode: "EMAIL_INVALID",
        },
        {
            name: "weak password", mode: "open",
            body:       `{"username":"newbie","email":"newbie@example.test","password":"short"}`,
            wantStatus: http.StatusBadRequest, wantCode: "PASSWORD_INVALID",
        },
        {
            name: "duplicate username", mode: "open",
            body:       `{"username":"alice","email":"newbie@example.test","password":"correct-horse-battery-staple"}`,
            byUsername: taken(existing), byEmail: notFound,
            wantStatus: http.StatusConflict, wantCode: "USERNAME_TAKEN",
        },
        {
            name: "duplicate email", mode: "open",
            body:       `{"username":"newbie","email":"alice@example.test","password":"correct-horse-battery-staple"}`,
            byUsername: notFound, byEmail: taken(existing),
            wantStatus: http.StatusConflict, wantCode: "EMAIL_TAKEN",
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            var created *model.User
            store := &stubStore{
                userByUsername: tc.byUsername,
                userByEmail:    tc.byEmail,
                createUser: func(_ context.Context, u *model.User) (int64, error) {
                    created = u
                    return 42, nil
                },
            }
            h := newTestHandler(store)
            h.Auth.Users.Registration.Mode = tc.mode

            w := postJSON(h.UserRegister, "/api/{api_version}/auth/register", tc.body)
            if w.Code != tc.wantStatus {
                t.Fatalf("status = %d, want %d (body %q)", w.Code, tc.wantStatus, w.Body.String())
            }
            env := decodeEnvelope(t, w)
            if tc.wantCode != "" && env["error"] != tc.wantCode {
                t.Fatalf("error = %v, want %q", env["error"], tc.wantCode)
            }

            if !tc.wantCreated {
                if created != nil {
                    t.Fatal("a user row was created for a rejected request")
                }
                return
            }
            if created == nil {
                t.Fatal("no user row was created")
            }
            if created.PasswordHash == "" || created.PasswordHash == "correct-horse-battery-staple" {
                t.Fatalf("password was not hashed: %q", created.PasswordHash)
            }
            if !model.CheckPassword(created.PasswordHash, "correct-horse-battery-staple") {
                t.Fatal("stored hash does not verify against the submitted password")
            }
            if cookieNamed(w, "user_session") == nil {
                t.Fatal("registration did not start a session")
            }
        })
    }
}

// TestDecodeJSONBodyLimit proves the 1 MiB MaxBytesReader cap is enforced.
func TestDecodeJSONBodyLimit(t *testing.T) {
    h := newTestHandler(&stubStore{
        userByLogin: func(context.Context, string) (*model.User, error) {
            t.Fatal("an oversized body must never reach the store")
            return nil, nil
        },
    })
    body := `{"login":"alice","password":"` + strings.Repeat("A", 2<<20) + `"}`
    w := postJSON(h.UserLogin, "/api/{api_version}/auth/login", body)
    if w.Code != http.StatusBadRequest {
        t.Fatalf("status = %d, want 400", w.Code)
    }
    if env := decodeEnvelope(t, w); env["error"] != "INVALID_JSON" {
        t.Fatalf("error = %v, want INVALID_JSON", env["error"])
    }
}
```

### Rate limit and scope (`src/middleware/middleware_test.go`)

These two categories live in the middleware package because Step 6 and Step 7
own them; the handlers are wrapped by them at registration time (Step 11).

```go
package middleware

import (
    "context"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"
)

type stubRateLimitDB struct {
    count    int64
    countErr error
    recorded int
}

func (s *stubRateLimitDB) CountRateLimitHits(context.Context, string, int64) (int64, error) {
    return s.count, s.countErr
}

func (s *stubRateLimitDB) RecordRateLimitHit(context.Context, string, int64) error {
    s.recorded++
    return nil
}

func TestRateLimit(t *testing.T) {
    tests := []struct {
        name         string
        db           *stubRateLimitDB
        max          int
        wantStatus   int
        wantReached  bool
        wantRecorded int
    }{
        {
            name: "under the limit passes through",
            db:   &stubRateLimitDB{count: 4}, max: 5,
            wantStatus: http.StatusOK, wantReached: true, wantRecorded: 1,
        },
        {
            name: "at the limit is rejected",
            db:   &stubRateLimitDB{count: 5}, max: 5,
            wantStatus: http.StatusTooManyRequests,
        },
        {
            name: "over the limit is rejected",
            db:   &stubRateLimitDB{count: 99}, max: 5,
            wantStatus: http.StatusTooManyRequests,
        },
        {
            name: "a store error fails closed",
            db:   &stubRateLimitDB{countErr: context.DeadlineExceeded}, max: 5,
            wantStatus: http.StatusServiceUnavailable,
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            reached := false
            next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                reached = true
                w.WriteHeader(http.StatusOK)
            })
            handler := RateLimit(tc.db, "auth.user_login", tc.max, 900)(next)

            r := httptest.NewRequest(http.MethodPost, "/api/{api_version}/auth/login", nil)
            r.RemoteAddr = "203.0.113.10:54321"
            w := httptest.NewRecorder()
            handler.ServeHTTP(w, r)

            if w.Code != tc.wantStatus {
                t.Fatalf("status = %d, want %d", w.Code, tc.wantStatus)
            }
            if reached != tc.wantReached {
                t.Fatalf("handler reached = %v, want %v", reached, tc.wantReached)
            }
            if tc.db.recorded != tc.wantRecorded {
                t.Fatalf("recorded hits = %d, want %d", tc.db.recorded, tc.wantRecorded)
            }
            if tc.wantStatus == http.StatusTooManyRequests && w.Header().Get("Retry-After") == "" {
                t.Fatal("a 429 must carry a Retry-After header")
            }
        })
    }
}

func TestRequireScope(t *testing.T) {
    tests := []struct {
        name       string
        scopes     any
        required   string
        wantStatus int
    }{
        {name: "exact scope present", scopes: `["read","write"]`, required: "write", wantStatus: http.StatusOK},
        {name: "scope absent", scopes: `["read"]`, required: "write", wantStatus: http.StatusForbidden},
        {name: "no scopes at all", scopes: `[]`, required: "read", wantStatus: http.StatusForbidden},
        {name: "no token in context", scopes: nil, required: "read", wantStatus: http.StatusForbidden},
        {name: "prefix must not match", scopes: `["writer"]`, required: "write", wantStatus: http.StatusForbidden},
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.WriteHeader(http.StatusOK)
            })
            handler := RequireScope(tc.required)(next)

            r := httptest.NewRequest(http.MethodGet, "/api/{api_version}/{feature}", nil)
            if tc.scopes != nil {
                r = r.WithContext(context.WithValue(r.Context(), CtxTokenScopes, tc.scopes))
            }
            w := httptest.NewRecorder()
            handler.ServeHTTP(w, r)

            if w.Code != tc.wantStatus {
                t.Fatalf("status = %d, want %d", w.Code, tc.wantStatus)
            }
            if tc.wantStatus == http.StatusForbidden {
                var env map[string]any
                if err := json.Unmarshal(w.Body.Bytes(), &env); err != nil {
                    t.Fatalf("response is not JSON: %v", err)
                }
                if env["error"] != "FORBIDDEN" {
                    t.Fatalf("error = %v, want FORBIDDEN", env["error"])
                }
            }
        })
    }
}
```

### Apply the same pattern everywhere else

Every remaining Step 8 handler gets a table-driven test file built exactly like
the two above — one `stubStore` hook per store call the handler makes, one table
row per outcome:

- `AdminLogout`, `AdminSession`, `AdminPasswordChange`, `AdminTOTPEnable`,
  `AdminTOTPConfirm`, `AdminTOTPDisable`
- `AdminInviteUser`, `AdminCreateUser`, `UserAcceptInvite`, `UserLogout`,
  `UserMe`, `UserUpdateMe`, `UserPasswordChange`, `UserPasswordResetRequest`,
  `UserPasswordResetConfirm`, `UserEmailVerify`
- `ListTokens`, `CreateToken`, `RevokeToken`
- `ListOrgs`, `CreateOrg`, `GetOrg`, `UpdateOrg`, `DeleteOrg`, `ListOrgMembers`,
  `AddOrgMember`, `ChangeOrgMemberRole`, `RemoveOrgMember`, `CreateOrgInvite`,
  `AcceptOrgInvite`
- `ListDomains`, `AddDomain`, `GetDomain`, `DeleteDomain`, `VerifyDomain`

For handlers behind `RequireAdmin`/`RequireUser`, inject the identity the
middleware would have set before calling the handler:

```go
r = r.WithContext(context.WithValue(r.Context(), middleware.CtxUserID, int64(7)))
```

Fixed rules to assert in every relevant table: token endpoints never return
`token_hash` and return the raw token exactly once, on creation; single-use
tokens (invite, password reset, email verification) are rejected the second
time; expired tokens are rejected; and one owner can never read or mutate
another owner's org, member, or domain rows.

---

## Step 15 — Final checks

Subagents never run these commands (`no-subagent-gates.sh` blocks `make`, tests, and gates): report back and list the commands below for the main session to run.

```bash
# Compile check
make build

# Tests
make test

# Confirm no raw tokens in DB (sanity)
# Confirm no bcrypt imports
grep -rn -- "golang.org/x/crypto/bcrypt" "{project_dir}/src" 2>/dev/null | grep -v "_test"
# Should return nothing
```

---

## Step 16 — Update IDEA.md

After all code is written and `make build` passes, record the auth implementation as constraints in
`{project_dir}/IDEA.md`.

If `IDEA.md` does not exist, create it with the required three-section layout:

```markdown
## What this project is

{project_name} — {one-sentence description inferred from go.mod and package names}

## Project variables

project_name: {project_name}
internal_name: {project_name}
internal_org: {org from go.mod module path}
fqdn: {fqdn if discoverable, else "localhost"}
data_dir: {data_dir}
db_dir: {db_dir}

## Constraints and non-negotiables
```

If `IDEA.md` already exists, read it first. Locate the `## Constraints and non-negotiables` section
(or add it if missing). Append a block — never overwrite existing constraints:

```markdown
### Auth (built by go-auth-builder)

Features installed: {comma-separated list of selected features}

Non-negotiable rules — must not be changed or removed:
- Password hashing: Argon2id only (time=3, memory=64MiB, threads=4, keyLen=32)
- API token storage: SHA-256 hex hash only; raw token shown once then discarded
- All password/token equality checks use subtle.ConstantTimeCompare
- Auth error responses: identical body ("Invalid credentials") for wrong password and no-such-user
- Dummy hash is always evaluated even when the user record is not found (timing defence)
- Every auth endpoint is rate-limited with a sliding-window per-IP limiter
- All SQL queries are parameterized; no string concatenation in query construction
- Session cookies: HttpOnly + Secure + SameSite=Strict always set
- No bcrypt, scrypt, MD5, or any SHA variant for password storage
```

---

## Step 17 — Update SPEC.md

After IDEA.md is written, open `{project_dir}/SPEC.md`. If it does not exist, create it (empty is
fine — SPEC.md is allowed to exist with no content until a rule override is needed).

Locate or create a section headed `## Auth overrides (go-auth-builder)`. Write the following block,
replacing the feature list and PART numbers with what was actually built. The PART numbers come from
grepping `{project_dir}/AI.md` for headers that match auth, users, admin, tokens, orgs, or domains:

```bash
# Identify which PARTs in AI.md cover the built auth features
grep -n "^# PART" "{project_dir}/AI.md" | grep -iE -- "auth|admin|user|token|org|domain|session"
```

If AI.md does not exist or has no matching PART headers, omit the PART-lock section and write only
the rule overrides below.

Write to SPEC.md:

```markdown
## Auth overrides (go-auth-builder)

Features installed: {comma-separated list}
PARTs locked (do not modify without re-running go-auth-builder): {PART numbers found above, or "n/a"}

### Non-negotiable rules — these override AI.md

These rules were established when go-auth-builder scaffolded auth for this project. They must not
be contradicted by AI.md updates or future template copies.

- Password hashing: **Argon2id only** — never bcrypt, scrypt, or any MD5/SHA variant
- Token storage: SHA-256 hex hash only; raw token is single-use and never stored or logged
- Equality: `subtle.ConstantTimeCompare` on every hash or token comparison — no `==`
- Anti-enumeration: identical 401 body and always-hash-on-miss regardless of lookup result
- Rate limiting: sliding-window per-IP on every auth endpoint (see src/middleware/ratelimit.go)
- SQL: parameterized queries everywhere — no string interpolation in any query
- Session cookies: HttpOnly + Secure + SameSite=Strict — no exceptions
- Scope: token endpoints enforce explicit scope list; missing scope → 403, not 401
```

SPEC.md wins over AI.md by convention. Writing these rules here means template re-copies of AI.md
cannot silently revert these security decisions.

---

## Rules

- **Argon2id only** — never bcrypt, scrypt, MD5/SHA for passwords (time=3, mem=64MiB, threads=4)
- **SHA-256 for tokens** — store only hex hash; raw token shown once then discarded
- **Constant-time comparison** — `subtle.ConstantTimeCompare` on every hash or token equality check
- **Identical auth error messages** — `"Invalid credentials"` for wrong password AND no such user
- **Always hash even on miss** — call `CheckPassword(dummyHash, input)` even when user not found
- **Rate limit every auth endpoint** — use the defaults in Step 7; wire rate limiter before handler
- **Parameterized queries** — never string concatenation in SQL, anywhere
- **HttpOnly + Secure + SameSite=Strict** — on every session cookie
- **No partial implementation** — no stubs, no TODOs in logic, no calls to non-existent functions
- **Discover before creating** — check whether files already exist; extend rather than overwrite
- **Build order** — 1 → 3 → 2 → 4 → 5 (respect dependencies)
- **Self-contained** — this agent carries its complete spec; never read any external spec or template file
- **Always write IDEA.md and SPEC.md** — Steps 16 and 17 are mandatory; never skip them even if build or tests fail (record what was built regardless)
- **Append, never overwrite** — both IDEA.md and SPEC.md may already have content; add to them, do not replace existing sections
