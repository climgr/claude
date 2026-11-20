---
name: Logging conventions
description: Log file format, content rules, and log-type standards for all CasjaysDev projects (scripts, Go, Rust)
type: user
---

## Universal Rules

- **Log files are always pure raw text** — no ANSI escape codes, no emojis, no Unicode decorations, no terminal control sequences. Ever.
- Color and emojis are for terminal output only. The log file path and the terminal output path must be separate code paths.
- Log files must be human-readable with standard tools: `cat`, `grep`, `tail -f`, `awk`, `fail2ban`, `logwatch`, syslog parsers.
- **Timestamps are always ISO 8601** (`2026-05-13T10:58:00-04:00`) or syslog format (`May 13 10:58:00`) — never free-form date strings.
- Log lines are **one line per event** — no multi-line log entries unless the format explicitly defines them (e.g. stack traces in an error log must be indented continuation lines, not embedded newlines in the first field).

## Log Types and Formats

### access.log — HTTP request log

Apache Combined Log Format:

```
{remote_host} {ident} {auth_user} [{day}/{month}/{year}:{hour}:{min}:{sec} {tz}] "{method} {path} {protocol}" {status} {bytes} "{referer}" "{user_agent}"
```

Example:
```
192.168.1.1 - - [13/May/2026:10:58:00 -0400] "GET /server/healthz HTTP/1.1" 200 42 "-" "curl/8.5.0"
```

Default format is `apache`; `nginx` and `json` are also available. Use this format for any HTTP-facing service. Keeps compatibility with `fail2ban`, `goaccess`, `awstats`, and standard log analysis tools.

### security.log — Security and authentication events

Default format `fail2ban` (also `syslog`, `cef`, `json`, `text`). Syslog-style example:

```
{Month} {DD} {HH}:{MM}:{SS} {hostname} {program}[{pid}]: {message}
```

Example:
```
May 13 10:58:00 myhost casci[1234]: Failed login for user admin from 192.168.1.50
May 13 10:58:05 myhost casci[1234]: Successful login for user admin from 192.168.1.1
```

Log: failed logins, successful logins, token issuance, privilege escalation, password changes, lockouts. This format is recognized by `fail2ban` and OS log aggregators.

### error.log — Application errors

```
{ISO8601} [{LEVEL}] {message}
```

Example:
```
2026-05-13T10:58:00-04:00 [ERROR] database connection failed: dial tcp 127.0.0.1:5432: connection refused
2026-05-13T10:58:01-04:00 [WARN]  retrying in 5s (attempt 2/3)
```

Levels (uppercase, bracket-wrapped): `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`.

### server.log — Application events (text or json)

logfmt (key=value pairs) — machine-readable, human-scannable, grep-friendly:

```
time=2026-05-13T10:58:00-04:00 level=INFO msg="server started" addr=[::]:{port} version=1.2.0
time=2026-05-13T10:58:05-04:00 level=WARN msg="rate limit hit" ip=10.0.0.5 path=/api/upload
```

Alternatively, plain timestamped lines for simpler scripts:

```
2026-05-13T10:58:00-04:00 INFO  server started on [::]:{port}
2026-05-13T10:58:05-04:00 WARN  rate limit hit for 10.0.0.5
```

### syslog / journald passthrough

When writing to syslog or journald directly (via `logger`, Go's `log/syslog`, or Rust's `syslog` crate), omit the timestamp and hostname — the journal adds them. Message only:

```
casci[1234]: Failed login for user admin from 192.168.1.50
```

### Health-check requests

Successful (2xx) health requests are never written to `access.log` or to the console request line, with no setting to turn it off. Non-2xx health responses are always logged.

### Startup output

- One event = one line, as a plain-text log line; no decorated duplicates (`✅ ...`, `📡 ...`) — the banner is the only decorated output
- Only the banner and log lines go to the console at startup; no separate "Ready" or "feature enabled" lines
- The banner is built as one string and written in ONE write while holding the logger lock, so no log line lands inside it
- Banner header: `{app} · {version}`
- A disabled optional feature logs nothing at INFO or above
- A failure of an enabled feature logs `Failed to start {feature}: {reason}` once at WARN

## What Belongs in Each Log

| Log file | What to log | What NOT to log |
|----------|------------|-----------------|
| `access.log` | Every HTTP request/response | Request bodies, passwords, tokens |
| `security.log` | Login attempts, token events, lockouts | Passwords, raw tokens, session keys |
| `error.log` | Errors, warnings, panics, retries | Debug noise in production, PII |
| `audit.log` | Security events (`json` only, machine-parseable) | Passwords, raw tokens |
| `debug.log` | Debug output (dev mode; `text` or `json`) | Anything in production |
| `server.log` | Startup, shutdown, config reload, background jobs | Verbose per-request debug in production |

**Never log:** passwords, raw tokens, API keys, session cookies, credit card numbers, SSNs, or any credential. When the event itself must be recorded, **mask the value but preserve the key** — context stays, secret goes:

```
api-token=xxxxx
password=xxxxx
Authorization: Bearer xxxxx
db_password=xxxxx
```

Masking rules:
- Key=value pairs: replace the value with `xxxxx` (five x's minimum; length does not leak info)
- Header values: replace everything after the scheme/prefix (`Bearer xxxxx`, `Basic xxxxx`)
- Last-4 acceptable only for card numbers where the last 4 are intentionally non-secret
- Hash (`sha256:abc123…`) acceptable when the hash itself is non-sensitive and useful for correlation
- Never truncate, never show partial values — a partial token is still a token

## Log File Location

Follow XDG / OS conventions:

| Context | Path |
|---------|------|
| System service | `/var/log/{project_org}/{project_name}/` |
| User-mode / XDG | `${XDG_STATE_HOME:-~/.local/state}/{project_name}/` |
| Docker container | stdout/stderr (no file) — let the container runtime collect logs |
| Scripts (one-off) | `/tmp/{project_org}/{internal_name}-XXXXXX/` (temp, not committed) |

In Docker: write to stdout (access, app) and stderr (errors) — never to a file inside the container. The runtime collects and rotates.

## Log Levels — Default by Environment

| Environment | Default level | Rationale |
|-------------|--------------|-----------|
| Production | `INFO` | Debug noise creates storage and security risk in prod |
| Development (local) | `DEBUG` | Full visibility while developing |
| CI / test | `WARN` | Reduce noise; tests assert behavior, not log verbosity |

Override via env var: `LOG_LEVEL=debug` / `LOG_LEVEL=info` / etc. The env var always wins over the compiled default. Never require a recompile to change log level.

## Request / Trace ID Propagation

Every inbound request in a server must be assigned a unique request ID. This ID must appear on every log line emitted during that request's lifetime.

- Generate at the entry point (middleware / handler) using UUID v7 (time-ordered) or a short random hex
- Accept `X-Request-ID` from upstream if present and trusted; otherwise generate one
- Propagate downstream via context: include in outbound HTTP calls as `X-Request-ID`, in gRPC calls as metadata, in queue messages as a field
- Log field name: `request_id` (logfmt) or `"request_id"` (JSON)

```
# logfmt — request_id on every line in the request scope
time=2026-05-13T10:58:00Z level=INFO msg="handler start" request_id=01HZ3X... path=/api/users
time=2026-05-13T10:58:00Z level=INFO msg="db query ok" request_id=01HZ3X... rows=5
```

## Structured Logging in Containers (Kubernetes / Cloud)

When the container runtime is Kubernetes or a cloud log aggregator (CloudWatch, GCP Logging, Datadog):

- Output **JSON** to stdout/stderr instead of logfmt — aggregators parse structured JSON natively
- Field names must be stable across versions — renaming a field breaks dashboards and alerts
- Required JSON fields: `time` (RFC 3339), `level`, `msg`, `request_id` (when in request scope), `version`
- Never embed newlines inside a JSON log line — multi-line stack traces must be a single JSON string value
- Detect at runtime: if `LOG_FORMAT=json` env var is set, switch to JSON output; otherwise use logfmt/plain text

## Log Rotation

System services must ship a `logrotate` config at `docker/rootfs/etc/logrotate.d/{project_name}`:

```
/var/log/{project_org}/{project_name}/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        systemctl kill -s HUP {project_name}.service 2>/dev/null || \
        kill -HUP "$(cat /var/run/{project_name}.pid 2>/dev/null)" 2>/dev/null || true
    endscript
}
```

## Implementation Notes

### Scripts

```bash
# BAD — ANSI leaks into log
echo -e "\e[31mERROR\e[0m: something failed" | tee -a /var/log/myapp/error.log

# GOOD — strip color for log, keep for terminal
__log_error() {
  local msg="$1"
  # always plain text to log file
  printf '%s [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${msg}" >> "${MYAPP_LOG_FILE}"
  # color only when going to a terminal
  if [[ -t 2 && -z "${NO_COLOR}" ]]; then
    printf '\e[31m[ERROR]\e[0m %s\n' "${msg}" >&2
  else
    printf '[ERROR] %s\n' "${msg}" >&2
  fi
}
```

### Go

Use `log/slog` (stdlib, Go 1.21+) with a plain text handler for files and an optional color handler for terminal:

```go
// File handler — plain text, no color
fileHandler := slog.NewTextHandler(logFile, &slog.HandlerOptions{Level: slog.LevelInfo})

// Terminal handler — can use a color-capable handler; falls back to plain when NO_COLOR set
slog.SetDefault(slog.New(fileHandler))
```

Never write ANSI codes into the `slog` message or attributes — they end up in the log file.

### Rust

Use `tracing` + `tracing-subscriber` with a plain formatter for file output:

```rust
// File appender — always plain text
let file_appender = tracing_appender::rolling::daily("/var/log/myapp", "server.log");
let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

tracing_subscriber::fmt()
    // no ANSI in log file — ever
    .with_ansi(false)
    .with_writer(non_blocking)
    .init();
```

For terminal output, `with_ansi(true)` only when color is enabled (check `NO_COLOR` + isatty first).
