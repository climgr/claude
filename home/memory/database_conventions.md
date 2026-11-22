---
name: Database conventions
description: Schema management, parameterized queries, connection pooling, SQLite vs PostgreSQL selection, transaction patterns, and data safety rules
type: user
---

## Database Selection

| Scenario | Database | Rationale |
|----------|----------|-----------|
| Single-node server | **SQLite** — `{db_dir}/server.db` | Zero-config, embedded, no separate process |
| Cluster / multi-node | **PostgreSQL** | Shared state across nodes requires remote DB |
| CLI tool (local state) | SQLite | Same zero-config advantage |
| Library / package | None (caller provides) | Libraries must not own a database |

SQLite is the default. Switch to PostgreSQL only when multi-node cluster support is needed. Document the choice in `{project_dir}/IDEA.md`.

---

## Schema Management — No Migration Files

Use `CREATE TABLE IF NOT EXISTS` and idempotent `ALTER TABLE` statements executed on every startup. No migration table, no version tracking, no migration files.

```go
// EnsureSchema runs on startup — safe to run multiple times
func EnsureSchema(db *sql.DB) error {
    for _, stmt := range createStatements {
        if _, err := db.Exec(stmt); err != nil {
            return fmt.Errorf("create table: %w", err)
        }
    }
    for _, stmt := range schemaUpdates {
        if err := db.Exec(stmt); err != nil {
            if !isAlreadyExistsError(err) {
                return fmt.Errorf("schema update: %w", err)
            }
        }
    }
    return nil
}
```

### Schema update rules

| Rule | Detail |
|------|--------|
| **Always idempotent** | Every statement is safe to run multiple times |
| **Never destructive** | Never `DROP COLUMN`, `DROP TABLE`, or `DELETE` in schema updates |
| **Add only** | Add columns, add tables, add indexes |
| **Defaults required** | New columns must have `DEFAULT` or be `NULL`-able |
| **No renames** | Applies to a project's own columns: add new column, migrate data in application code, leave old column — never drop it. Exception: a column the template renames to its canonical name (scheduler `task_id`→`id`, `task_name`→`name`, `ran_at`→`started_at`) is upgraded in place by a guarded, idempotent `ALTER TABLE ... RENAME COLUMN old TO new`, run only when the column list shows the old name and not the new one (`PRAGMA table_info` on SQLite/libSQL, `information_schema.columns` elsewhere; SQL Server uses `sp_rename`); data is kept, nothing is dropped, and a column missing afterward is added with plain `ADD COLUMN` |
| **Comment the version** | Each schema update entry notes the version that introduced it |

### Cross-database "column already exists" handling

```go
func isAlreadyExistsError(err error) bool {
    msg := strings.ToLower(err.Error())
    // SQLite
    return strings.Contains(msg, "duplicate column") ||
           // PostgreSQL
           strings.Contains(msg, "already exists") ||
           // MySQL
           strings.Contains(msg, "duplicate column name")
}
```

PostgreSQL v9.6+: prefer `ADD COLUMN IF NOT EXISTS` to avoid the error entirely.

---

## Parameterized Queries — Mandatory

**Never build SQL by string concatenation.** Always use parameterized queries.

```go
// WRONG — SQL injection risk
query := "SELECT * FROM users WHERE email = '" + email + "'"

// CORRECT
row := db.QueryRow("SELECT id, name FROM users WHERE email = ?", email)
```

```rust
// CORRECT (sqlx)
let user = sqlx::query_as!(User, "SELECT * FROM users WHERE email = ?", email)
    .fetch_one(&pool)
    .await?;
```

This applies everywhere: `WHERE`, `INSERT`, `UPDATE`, `DELETE`, `LIKE`, `IN` lists. No exceptions.

**`IN` lists**: build a parameterized placeholder list, never concatenate values:
```go
placeholders := strings.Repeat("?,", len(ids))
placeholders = strings.TrimRight(placeholders, ",")
query := fmt.Sprintf("SELECT * FROM users WHERE id IN (%s)", placeholders)
// Pass ids... as args
```

---

## Connection Pooling

Set explicit pool limits. Never use the driver's unlimited defaults in production code.

```go
db, err := sql.Open("sqlite3", dsn)
// or sql.Open("postgres", dsn)
// max simultaneous connections
db.SetMaxOpenConns(25)
// idle connections kept alive
db.SetMaxIdleConns(5)
// max connection age
db.SetConnMaxLifetime(5 * time.Minute)
// max idle time before close
db.SetConnMaxIdleTime(1 * time.Minute)
```

| Setting | SQLite | PostgreSQL |
|---------|--------|-----------|
| `MaxOpenConns` | writeDB 1, readDB pooled (see contract) | 25 (tune per server) |
| `MaxIdleConns` | 1 | 5 |
| `ConnMaxLifetime` | 30 min | 5 min |

SQLite pooling is governed by the SQLite Concurrency Contract below (two handles per file), not by this table.

---

## Transactions

- Wrap multi-step writes in a transaction — never leave the database in a partial-write state
- Always call `tx.Rollback()` in a `defer`; it is a no-op after `tx.Commit()`
- Never hold a transaction open across an HTTP request boundary — finish within the handler

```go
tx, err := db.BeginTx(ctx, nil)
if err != nil {
    return err
}
// no-op after Commit
defer tx.Rollback()

// ... multiple operations ...

return tx.Commit()
```

- Use `context.Context` for deadlines on every query — `db.QueryContext(ctx, ...)`, `db.ExecContext(ctx, ...)`. An undeadlined query is an eventual hang.

---

## Data Safety Rules

- `DELETE FROM` without a `WHERE` is forbidden — always filter by at least one column
- `DROP TABLE` / `DROP COLUMN` in application code is forbidden — schema changes are additive only
- Never `SELECT *` in application code — list columns explicitly; `*` breaks when schema evolves
- Index every foreign key column and every column used in a `WHERE` clause in hot queries
- Never store raw passwords — Argon2id only (see `sensitive_data.md`)
- Never store raw tokens — hash with SHA-256 before persisting; store the hash
- Encrypt at-rest when the database contains PII — document the encryption method in `IDEA.md`

---

## SQLite-Specific

- Default database path: `{db_dir}/server.db` and `{db_dir}/users.db` (see `{project_dir}/IDEA.md` for platform-specific `{db_dir}`)
- Concurrency, WAL, busy timeout, handles: see "SQLite Concurrency Contract" below
- Always open with `?_foreign_keys=on` to enforce FK constraints
- Use `VACUUM` sparingly — only on user request or scheduled maintenance, never inline
- Backups: `sqlite3 src.db ".backup dst.db"` or the `VACUUM INTO` statement — never `cp` an open database file

---

## Query Patterns

Prefer small, focused queries over large JOINs when the join fan-out is unbounded. Fetch related rows in a second query and join in application code when the result set could be large.

Row-not-found is not an error in most cases — check `sql.ErrNoRows` explicitly and return a domain-level not-found value, not a 500.

```go
var user User
err := db.QueryRowContext(ctx, "SELECT id, name FROM users WHERE id = ?", id).Scan(&user.ID, &user.Name)
if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrNotFound
}
if err != nil {
    return nil, fmt.Errorf("get user: %w", err)
}
return &user, nil
```

---

## SQLite Concurrency Contract

Fixes `database is locked` (`SQLITE_BUSY`). Applies to every SQLite file the application opens; libsql/Turso is remote and not covered.

- `journal_mode=WAL` and `synchronous=NORMAL` set on open; check the `journal_mode` pragma result — anything other than `wal` logs an ERROR and refuses to start
- `busy_timeout=10000` on EVERY connection (set through the DSN so each pooled connection gets it)
- Two handles per SQLite file: `writeDB` (1 open conn, `_txlock=immediate`) and `readDB` (`query_only(1)`, pooled). Only the store layer sees them, through `Write(ctx, fn)` and `Read(ctx)`
- All writes (and any read-then-write flow) run inside ONE `Write` transaction
- `Write` retries `SQLITE_BUSY`/`SQLITE_LOCKED` up to 5 times with exponential backoff and jitter
- Cleanup, retention and import work in batches of at most 500 rows per transaction
- Hot counters (rate limits, metrics, `last_used`) live in memory and are flushed periodically and on shutdown — never written per request
- On shutdown: `PRAGMA wal_checkpoint(TRUNCATE)`, then close `readDB`, then `writeDB`
- Local disk only — never NFS, SMB or FUSE
- A concurrency test runs 20 writer + 20 reader goroutines against a temporary database and asserts zero `database is locked` errors

---

## Connection Strings

The database and cache each accept ONE full URL: `server.database.url` and `server.cache.url`.

- `DATABASE_URL`, `CACHE_URL` and `DATABASE_DRIVER` are first-run (init-only) seeds and are ignored afterwards
- The URL scheme picks the driver: `sqlite` (file path) or `libsql`/`turso` (remote) for API and HYBRID projects (single-instance scope: no PostgreSQL, MySQL or MongoDB); SERVER projects add the remote SQL drivers their template lists; cache: `valkey`/`redis`
- TLS is on only when the URL asks for it, then enabled automatically; the certificate is NOT verified by default (verification is opt-in)
- Passwords are accepted as typed — the user does not encode them
- A URL that carries a credential (userinfo, or a `password`, `pwd`, `token` or `authToken` query value) is saved to `secrets.yml`; a URL without one stays in `server.yml`
- Logs and output show only the redacted form (`scheme://user:********@host:port/name`)
- A rejected URL never falls back to another database
- The libSQL driver is `github.com/tursodatabase/libsql-client-go` (remote, pure Go, `CGO_ENABLED=0`) in Go projects; it is deprecated upstream but stays required, and `go-libsql` (CGO, four platforms only) is forbidden

---

## Config Files

`secrets.yml` (mode `0600`) holds credentials; `server.yml` and `yaml.d/` are node config. Merge order: defaults, `server.yml`, `yaml.d/` drop-ins in byte-wise filename order, `secrets.yml`; CLI flags and environment variables rank above all of them.

---

## Credentials Storage

API credentials live in a single `tokens` table, stored hashed (SHA-256); there is no separate `api_keys` table.
