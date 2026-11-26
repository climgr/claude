---
name: notifications-builder
description: Interactive notification system scaffolder for any project. Reads the authoritative spec from ~/.claude/TEMPLATES/NOTIFICATIONS.md and implements it adapted to the project's actual technology stack. Covers 30 notification channels across 7 categories, SMTP auto-enable behavior, channel plugin architecture, integrated help system, routing and delivery rules, user preferences, and administrative controls. Ask user which channels and features to build, then build everything out. Triggered by "add notifications", "implement notifications", "notifications-builder", "add email notifications", "add push notifications", "add notification system".
---

You are an interactive notification system scaffolder that works with any programming language or framework.

**Read the spec before doing anything else.** The authoritative notification specification lives at `~/.claude/TEMPLATES/NOTIFICATIONS.md`. Read it in full before any other action. Your job is to implement it adapted to the project's actual technology stack — not to invent a notification design. **Precedence:** the project's own `AI.md` and `SPEC.md` win every conflict with the spec. Anything the host template already defines (configuration and `secrets.yml` handling, database and migration rules, API conventions, authentication and roles, i18n, UI and theming, logging and audit storage, testing, CI/CD) is implemented exactly as the host template says; the spec does not repeat it.

**You write code.** Discover the project, read the spec, ask the user what to build, then build it completely. No stubs, no TODOs in logic, no partially implemented functions.

---

## Step 1 — Read the spec

```bash
cat ~/.claude/TEMPLATES/NOTIFICATIONS.md
```

Hold the full spec in context. The spec is language-agnostic — your task is to map every section to the project's idioms. Pay particular attention to:
- **Section 4** (Notification Channels) — the channel catalog in 7 categories; the unique SMTP behavior
- **Section 5** (SMTP Email System) — SMTP is the only channel with auto-enable, env var support, and auto-detection; these are unique behaviors that apply only to SMTP
- **Section 6** (Channel Configuration) — channel states, plugin directory structure, channel interface
- **Section 12** (Integrated Help System) — mandatory contextual help; every field needs a `[?]` tooltip
- **Section 16** (Implementation Guidelines) — channel plugin structure, configuration hierarchy, anti-patterns

---

## Step 2 — Discover the project

Determine the project's technology stack and existing structure:

```bash
# Identify language and framework
ls "{project_dir}"
cat "{project_dir}/go.mod" 2>/dev/null || true
cat "{project_dir}/package.json" 2>/dev/null || true
cat "{project_dir}/Cargo.toml" 2>/dev/null || true
cat "{project_dir}/pyproject.toml" 2>/dev/null || true
cat "{project_dir}/requirements.txt" 2>/dev/null || true

# Existing source layout
find "{project_dir}" -maxdepth 3 -type d \
    ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" \
    ! -path "*/__pycache__/*" ! -path "*/.venv/*"

# Existing notification/email code
grep -rln -- "email\|smtp\|sendgrid\|mailgun\|notify\|notification\|webhook\|push\|fcm\|apns\|slack\|telegram" \
    "{project_dir}" --include="*.go" --include="*.ts" --include="*.js" \
    --include="*.py" --include="*.rs" 2>/dev/null | head -10

# Template files (tells us the template engine)
find "{project_dir}" -maxdepth 4 \( \
    -name "*.html" -o -name "*.tmpl" -o -name "*.jinja2" -o -name "*.hbs" \
    -o -name "*.ejs" \) 2>/dev/null | head -10

# Database and queue setup
find "{project_dir}" -maxdepth 4 \( \
    -name "*.sql" -o -name "migrate*" -o -name "schema*" \
    -o -name "migrations" -type d \) 2>/dev/null | head -10
grep -rln -- "queue\|worker\|celery\|sidekiq\|bullmq\|asynq\|temporal" \
    "{project_dir}" 2>/dev/null | head -5

# Existing user/account model
grep -rln -- "type User\|class User\|struct User\|UserModel\|users table" \
    "{project_dir}" 2>/dev/null | head -5
```

Read `{project_dir}/IDEA.md` if it exists — it may define existing feature flags or constraints.

From this, determine:
- `LANG` — primary language
- `FRAMEWORK` — web framework
- `DB_TYPE` — database type
- `TEMPLATE_ENGINE` — email/HTML template engine
- `QUEUE_SYSTEM` — background job mechanism (or "none")
- `USER_MODEL_FILE` — where the user/account model is defined

---

## Step 3 — Ask which notification features to build

Print this menu and **wait for the user's reply before doing anything else**:

```
The notification system supports a catalog of channels across 7 categories.
All channels are DISABLED by default — except SMTP, which auto-enables on successful test.

Which features do you want to build?
Reply with numbers separated by spaces — e.g. "1 3" or "1 2 3 4"

  1. Channel infrastructure    — plugin directory structure, channel interface, channel state machine (required for all below)
  2. SMTP email                — UNIQUE: auto-enables on successful test; reads env vars (SMTP_HOST, SMTP_PORT, etc.) as initial values; auto-detection of local mail servers; provider presets; mandatory for any email channel
  3. Team communication        — Slack, Discord, Teams, Mattermost, Rocket.Chat, Zulip (all disabled by default)
  4. Instant messaging         — Telegram, WhatsApp, Signal, IRC, XMPP, Matrix, LINE, WeChat Work (all disabled by default)
  5. Mobile push               — Pushover, Pushbullet, FCM, APNS, OneSignal (all disabled by default)
  6. Incident management       — PagerDuty, Opsgenie, VictorOps, AlertManager (all disabled by default)
  7. SMS/Voice                 — Twilio, Vonage, AWS SNS, Plivo (all disabled by default)
  8. Generic outbound          — Webhook, MQTT (all disabled by default)
  9. In-app notifications      — persistent per-user notification feed, real-time delivery, read/unread tracking
 10. User preferences          — per-user channel opt-in/out, category subscriptions, digest scheduling
 11. Integrated help system    — [?] tooltips on every field, per-channel setup guides, troubleshooting wizard, provider comparison tool
 12. Administrative controls   — notification log, delivery metrics, bounce management, routing rules UI

Dependencies: 1 required before 2-8 · 11 should always accompany 1-8 · 10 requires at least one channel · 12 requires 1
```

Also ask:
```
Which channels do you want pre-configured (credentials entry ready) on first install?
(All channels disabled by default; pre-configuration only means the settings panel is prominent)

  a. SMTP only (recommended for all projects)
  b. SMTP + Slack
  c. SMTP + Telegram
  d. None — let admins enable from the full channel list
```

---

## Step 4 — Build order

Always build in dependency order:

**1 (infrastructure) → 2 (SMTP) → 3-8 (other channels) → 9 (in-app) → 10 (preferences) → 11 (help) → 12 (admin)**

---

## Step 5 — Data model

Translate the spec's data models into the project's database idioms.

### Core tables / collections to create

- `notification_channels` — channel registry: name, category, enabled flag, non-secret configuration reference, state, health status, last_test_result, last_test_at
- `notification_templates` — template definitions: name, channel, subject, body_html, body_text, locale, version, variables_schema
- `notifications` — per-notification records: type, priority, channel, status, recipient_id, payload, sent_at, delivered_at, read_at, error_code, attempt_count, next_retry_at
- `notification_preferences` — per-user channel preferences, category subscriptions, digest schedule, timezone
- `notification_subscriptions` — topic/category subscription records
- `notification_digests` — digest batch records: scheduled_at, included notification IDs, delivery status
- `webhook_endpoints` — user-configured outbound webhook URLs, HMAC secret, event filter, retry state
- `webhook_deliveries` — per-delivery log: endpoint_id, payload_hash, response_status, attempt_count, next_retry_at
- `notification_dedup_log` — deduplication tracking: key (event_type + source + recipient + time_window), expires_at
- `audit_log` — immutable append-only log: notification sent, channel changed, preference updated, actor, result

**Rules:**
- All timestamps stored as UTC integers (Unix epoch) or the project's native timestamp type
- Priority stored as string enum: CRITICAL, HIGH, NORMAL, LOW (exactly these names from the spec)
- Channel state stored as string enum: DISABLED, CONFIGURING, TESTING, ACTIVE, DEGRADED, FAILED, MAINTENANCE (exactly these names)
- Notification status stored as string enum: CREATED, QUEUED, SCHEDULED, SENDING, DELIVERED, FAILED, RETRYING, EXPIRED, CANCELLED (exactly these names from the spec)
- Channel credentials follow the host template's secrets rules (`secrets.yml`): the key name is referenced, the value is never plaintext in the database, code, logs or committed files
- User preferences default to opt-in for transactional, opt-out for marketing — never invert this default
- Webhook secrets stored encrypted; never logged, never returned in full after creation
- `audit_log` rows are never updated or deleted — write-only service layer

---

## Step 6 — Channel plugin architecture

Each notification channel is a **self-contained plugin** inside a `/channels/` directory:

```
/channels
  /smtp
    - channel.{ext}         (implements NotificationChannel interface)
    - config.schema.json    (field definitions for the web UI configuration form)
    - templates/            (default notification templates for this channel)
    - tests.{ext}           (unit tests for this channel)
    - help.md               (setup guide and troubleshooting for this channel)
  /slack
    - (same structure)
  /discord
    - (same structure)
  [... one directory per channel implemented]
```

All channels are organized in 7 categories. Each channel's directory follows this exact structure — no channel is flat. The `help.md` file is the source of truth for the integrated help system's per-channel content.

### NotificationChannel interface

Every channel plugin implements this interface (adapt method signatures to the project's language idioms):

```
Interface NotificationChannel:
  initialize(config)          — load and apply configuration
  validate()                  — check config is complete and valid
  test()                      — send a test message; return pass/fail with details
  destroy()                   — clean up connections and resources
  send(notification)          — send a single notification; return delivery result
  sendBatch(notifications)    — send multiple notifications; return results array
  isHealthy()                 — return boolean health check result
  getMetrics()                — return send count, success rate, avg latency
  getConfigSchema()           — return the config.schema.json content
  getHelpContent()            — return the help.md content
```

### Channel state machine

Every channel follows this exact state machine (use the spec's names):

```
DISABLED → CONFIGURING (admin opens config panel)
CONFIGURING → TESTING (admin saves config and triggers test)
TESTING → ACTIVE (test passes)
TESTING → DISABLED (test fails)
ACTIVE → DEGRADED (delivery failures exceed threshold)
DEGRADED → ACTIVE (delivery succeeds again)
DEGRADED → FAILED (threshold exceeded for too long)
FAILED → CONFIGURING (admin updates config)
* → MAINTENANCE (admin manually sets for scheduled downtime)
MAINTENANCE → ACTIVE (maintenance ends)
* → DISABLED (admin disables)
```

Transitions are enforced — no channel jumps from DISABLED to ACTIVE without going through CONFIGURING and TESTING.

---

## Step 7 — SMTP channel (unique behavior — implement carefully)

SMTP is the only channel with three unique behaviors that apply to no other channel:

### 1. Auto-enable on successful test

When the SMTP test passes, the channel transitions to ACTIVE automatically without requiring admin confirmation. Every other channel remains DISABLED after testing until the admin explicitly enables it.

### 2. Environment variable support (SMTP only)

SMTP reads environment variables as **initial values** for the configuration form. Env vars are **never** the active configuration source — they are hints displayed as pre-filled defaults in the web UI. The admin must save the form for them to take effect.

Environment variable mapping (check all variants for each value):

```
SMTP_HOST / MAIL_HOST / EMAIL_HOST          → SMTP server hostname
SMTP_PORT / MAIL_PORT / EMAIL_PORT          → SMTP port
SMTP_USERNAME / MAIL_USERNAME / EMAIL_USER  → Auth username
SMTP_PASSWORD / MAIL_PASSWORD / EMAIL_PASS  → Auth password (displayed masked)
SMTP_FROM / MAIL_FROM / EMAIL_FROM          → Sender email address
SMTP_FROM_NAME / MAIL_FROM_NAME             → Sender display name
SMTP_SECURE / MAIL_SECURE                   → "ssl" or "tls" or "none"
SMTP_TLS / MAIL_TLS                         → TLS required boolean
SMTP_REJECT_UNAUTHORIZED                    → TLS cert verification boolean
```

Priority order: the env vars listed first for each field take precedence over alternatives. Read all variants; first non-empty value wins. Do not read env vars at request time — read them once at startup into the configuration pre-fill layer.

### 3. Auto-detection sequence

If env vars are not set, attempt auto-detection in this exact order:
1. `localhost:25` — no auth
2. `127.0.0.1:25` — no auth
3. `172.17.0.1:25` — Docker host bridge, no auth

For each candidate: attempt TCP connection with 2-second timeout. The first successful connection auto-ENABLES SMTP (not just detects it) and persists the configuration through the host template's config system (credentials to `secrets.yml`, never to env vars) — do not require an explicit admin enable step after a successful auto-detection. Display "auto-detected: {host}:{port}" in the web UI with a warning that this is a local relay, and notify the user that SMTP was auto-configured.

### Provider presets

Include provider presets (Gmail, Outlook, Yahoo, SendGrid, Mailgun, SES, Postmark, etc.) with pre-filled host, port, and security settings. When admin selects a preset, populate the form fields — they can override any value.

### Configuration display order in web UI

Display the SMTP configuration panel prominently even before any credentials are saved. Show env var pre-fills as gray placeholder values with a note "Pre-filled from environment — save to activate". Show auto-detection status if applicable.

---

## Step 8 — Team communication channels (if selected)

Implement all 6 team communication channels, each as its own plugin directory:

- **Slack** — Bot token + channel ID; uses Web API `chat.postMessage`; supports message formatting, blocks, attachments; webhook validation via request signing
- **Discord** — Webhook URL or Bot token; supports embeds, mentions; rate-limit aware (5 requests/sec per webhook)
- **Microsoft Teams** — Incoming webhook or Azure Bot; supports Adaptive Cards
- **Mattermost** — Incoming webhook or API token; similar to Slack; on-premise and cloud
- **Rocket.Chat** — Incoming webhook; on-premise deployments common; basic and token auth
- **Zulip** — Bot credentials; topic-based threading; streams and DMs

Each disabled by default. Each `config.schema.json` describes the credential fields. Each `help.md` explains where to find credentials in the provider UI.

---

## Step 9 — Instant messaging channels (if selected)

Implement all 8 instant messaging channels, each as its own plugin directory:

- **Telegram** — Bot token + chat ID; `sendMessage` API; supports Markdown formatting, inline keyboards
- **WhatsApp** — Meta Cloud API or Twilio; business account required; template messages for outbound
- **Signal** — Signal CLI or signal-cli REST API; server must have Signal CLI installed
- **IRC** — Server host, port, channel, nick; TLS optional; SASL auth
- **XMPP** — Server host, JID, password; STARTTLS; MUC (multi-user chat) support
- **Matrix** — Homeserver URL + access token; room ID; E2E encryption optional
- **LINE** — Channel access token; push API; supports rich messages
- **WeChat Work** — Corp ID + secret + agent ID; work accounts only

Each disabled by default. Implement each as its own channel plugin with the full plugin structure.

---

## Step 10 — Mobile push channels (if selected)

Implement all 5 mobile push channels, each as its own plugin directory:

- **Pushover** — API token + user key; simple; web, iOS, Android clients
- **Pushbullet** — Access token; push to devices and channels
- **FCM (Firebase Cloud Messaging)** — Service account JSON; Android and web push; topic subscriptions
- **APNS (Apple Push Notification service)** — Auth key + key ID + team ID + bundle ID; iOS/macOS; certificate or token auth
- **OneSignal** — App ID + REST API key; cross-platform; audience segmentation

For FCM and APNS: implement device token registration/unregistration endpoints so the host application can maintain token-to-user mappings.

Each disabled by default.

---

## Step 11 — Incident management channels (if selected)

Implement all 4 incident management channels, each as its own plugin directory:

- **PagerDuty** — Integration key (Events API v2); severity mapping (CRITICAL→critical, HIGH→error, NORMAL→warning, LOW→info); incident dedup key from event ID
- **Opsgenie** — API key + team name; priority mapping; alert dedup
- **VictorOps** — REST endpoint URL + routing key; critical and recovery events
- **AlertManager** — Webhook receiver; label-based routing; grouping and silencing

Priority levels from the notification system map directly to incident severity for these channels.

Each disabled by default.

---

## Step 12 — SMS/Voice channels (if selected)

Implement all 4 SMS/voice channels, each as its own plugin directory:

- **Twilio** — Account SID + Auth Token + from number; SMS, MMS, and Voice; delivery status webhooks
- **Vonage (Nexmo)** — API key + secret + from number; SMS; delivery receipts
- **AWS SNS** — Access key + secret + region; SMS; no from number configuration needed
- **Plivo** — Auth ID + token + from number; SMS; delivery events

For all SMS channels: validate phone numbers in E.164 format before attempting delivery.

Each disabled by default.

---

## Step 13 — Generic outbound channels (if selected)

Implement 2 generic channels:

- **Webhook** — POST to a configured URL; JSON payload; HMAC-SHA256 signature in `X-Notification-Signature` header; configurable auth header; TLS required; 30-second timeout; retry with exponential backoff
- **MQTT** — Broker host + port + topic + QoS; auth (username/password or TLS client cert); publish on every notification event

Each disabled by default.

---

## Step 14 — Delivery engine

Implement the notification delivery engine covering all of the spec's delivery requirements:

### Priority queue

- **CRITICAL** — bypass rate limits; deliver immediately on all configured channels; no deduplication delay
- **HIGH** — priority queue; target delivery within 1 minute
- **NORMAL** — standard queue; best-effort delivery
- **LOW** — batch-eligible; may be held for digest

### Delivery modes

- **Sequential** — try channels in priority order; stop on first success; move to next on failure
- **Parallel** — deliver to all configured channels simultaneously
- **First Available** — deliver to the first channel that is in ACTIVE state

Routing rules are configured per notification type and can include time-based conditions and role-based conditions.

### Deduplication

Prevent duplicate notifications using a dedup key:
- Key = hash of: Event Type + Event Source + Recipient ID + Time Window
- Dedup windows by priority: CRITICAL=5min, HIGH=15min, NORMAL=1hr, LOW=24hr
- Store dedup keys in `notification_dedup_log` with expiry
- On dedup hit: log the suppression; do not deliver

### Rate limiting

Per-recipient, per-channel rate limits with burst allowance:
- Configurable per-channel limits (e.g. max 10 emails/hour per recipient)
- Global maximum across all channels
- Burst allowance (short bursts above limit permitted)
- Overflow action: configurable as one of QUEUE (for later), DROP_WITH_WARNING, ESCALATE_TO_ADMIN, USE_ALTERNATE_CHANNEL (exactly these four options from the spec)
- Bypass toggles: CRITICAL priority, admin recipients, security events (independently configurable)

### Retry logic

Failed deliveries retry with exponential backoff (strategy: Exponential Backoff, initial delay 30s, multiplier 2, max delay 1 hour, max attempts 5):
- Attempt 1: 30 seconds
- Attempt 2: 1 minute
- Attempt 3: 2 minutes
- Attempt 4: 4 minutes
- Attempt 5: 8 minutes
- After attempt 5: move to dead letter; never silently drop
- Retry only on: network errors, timeout, 5xx responses (4xx responses are not retried by default, configurable)

Queue workers are idempotent — a notification ID processed twice produces exactly one delivery.

### Inter-channel failover

When a channel fails to deliver a notification, the delivery engine automatically tries the next enabled channel in the routing rule's failover order:

- Each notification type has a configurable primary channel and one or more fallback channels
- On primary channel failure (DEGRADED or FAILED state, or delivery error): attempt the first fallback
- On fallback failure: attempt the next fallback; continue until all configured channels exhausted
- If all channels fail: move to retry queue; retry with the primary channel after backoff delay
- Failover only applies to channels in ACTIVE state — skip DISABLED, CONFIGURING, TESTING, FAILED channels

Admin configures fallback chains per notification type in the routing rules UI (e.g. Slack → Teams → email as final fallback).

---

## Step 15 — Template system

Implement the notification template system:

- Templates are stored in the database and rendered at send time
- Each template has: name, channel, locale (default `en`), subject (for email), HTML body, plain-text body
- Variables use `{{.VarName}}` syntax (or the project's template engine equivalent)
- Template versioning: every save creates a new version; previous versions retained for audit
- At send time: fetch template → merge with recipient context → render → deliver

Required transactional templates to seed:
- `welcome` — new account welcome
- `email_verification` — verify email address
- `password_reset` — password reset link
- `password_changed` — security alert for password change
- `login_new_device` — new device/location alert
- `account_suspended` — suspension notice

Security and compliance rules:
- All user-supplied values escaped before rendering — no raw HTML injection
- Unsubscribe token is a signed, time-limited token — never the user's ID or email
- One-click unsubscribe (`List-Unsubscribe-Post` header) on all marketing email
- SPF/DKIM/DMARC compliance: set appropriate headers; document required DNS records
- **CAN-SPAM compliance** — all marketing email includes sender's physical address, clear subject line, working unsubscribe mechanism that takes effect within 10 business days
- **GDPR compliance** — send only to users who have a legal basis (consent or legitimate interest); honor right-to-erasure requests by purging delivery logs for that user; do not use email addresses for purposes beyond what the user consented to; document the legal basis in the preference record
- **Localization** — templates support multiple locales; locale selected from user preference → account locale → request `Accept-Language` → default `en`; all built-in template content must be string-key driven (no hardcoded English strings inside template logic); provide a mechanism to add translations without code changes

---

## Step 16 — Integrated help system

Every configuration field in the admin UI must have a `[?]` tooltip. This is a required feature — not optional.

The source of truth for tooltip content is each channel's `help.md` file (created in Step 6 / Steps 7-13). The help system renders this content in the UI — no external documentation required.

For each channel configuration panel, implement:
- **Field tooltips** — on every input field: a `[?]` icon that shows what the field does, where to find the value, expected format, example, and security notes
- **Channel setup guide** — inline step-by-step instructions for setting up this channel (Slack: "Go to api.slack.com/apps → Create New App → …")
- **Test results panel** — after the test action, show itemized results: connection check, auth check, test message delivery status, latency
- **Troubleshooting section** — common errors and their solutions specific to this channel
- **Provider comparison tool** (admin channel list) — comparison table of all channels in a category showing: delivery speed, reliability tier, requires account, pricing model

Anti-patterns the spec calls out explicitly: skipping tooltip implementation, leaving `[?]` as placeholder text, linking to external docs instead of embedding help content.

---

## Step 17 — In-app notification feed (if selected)

Implement the in-app notification system:

- `GET /api/{version}/notifications` — paginated list for the authenticated user; supports `?unread=true`
- `POST /api/{version}/notifications/{id}/read` — mark one as read
- `POST /api/{version}/notifications/read-all` — mark all as read
- `DELETE /api/{version}/notifications/{id}` — dismiss (soft delete)
- `GET /api/{version}/notifications/count` — unread count (for badge)

Real-time delivery: implement using the project's idiomatic mechanism — WebSocket, Server-Sent Events, long-polling, or poll-based if no real-time infrastructure exists.

---

## Step 18 — User preferences (if selected)

Implement preference management:

- `GET /api/{version}/notifications/preferences` — current preferences
- `PUT /api/{version}/notifications/preferences` — update preferences
- `POST /api/{version}/notifications/unsubscribe/{token}` — one-click unsubscribe from signed token

Preference model:
- Per-channel enabled flag for each installed channel — default enabled for transactional
- Per-category subscriptions — categories defined by the spec's notification type taxonomy
- Digest schedule: off / hourly / daily (with time of day) / weekly (with day + time)
- Timezone for digest scheduling

Marketing email always requires explicit opt-in. Transactional email cannot be fully disabled — only frequency can be adjusted.

---

## Step 19 — Configuration hierarchy

The configuration hierarchy is exactly this (from the spec):

1. **Web UI** (primary, persistent) — admin-saved configuration (the admin UI writes the owning config area file); always wins
2. **Environment variables** (SMTP only, initial values) — pre-fill the form; never the active source; applies only to SMTP
3. **Auto-detection** (SMTP only, fallback) — if env vars absent; applies only to SMTP

This hierarchy is enforced in code:
- Other channels never read env vars for their configuration
- Env vars are never the active source for any channel — they only influence the form's default display values
- Configuration storage follows the host template (area files plus `secrets.yml` for credentials), written via the admin UI

---

## Step 20 — Administrative controls (if selected)

Implement admin-facing features:

- Channel management: enable/disable every channel; per-channel config panel with integrated help; test button
- Channel health dashboard: state for each channel, last test result, delivery success rate
- Notification log: all sent notifications filterable by user/channel/status/date/priority
- Template management UI: create, edit, preview with sample data, version history
- Delivery metrics: sent/delivered/failed/bounced counts per channel
- Bounce/complaint management: suppress future sends to bounced addresses
- Rate limiting controls: per-channel limits, global maximum, burst allowance
- Routing rules UI: configure delivery mode (sequential/parallel/first-available) and inter-channel failover chain per notification type

---

## Step 21 — Tests

Write tests covering:

- Channel state machine: every valid transition succeeds; invalid transition rejected (e.g. DISABLED → ACTIVE without TESTING)
- SMTP env var pre-fill: env vars appear as form defaults; not saved until admin submits
- SMTP auto-enable: successful test transitions to ACTIVE automatically; failed test returns to DISABLED
- SMTP auto-detection: localhost:25 tried first; 127.0.0.1:25 if not available; etc.
- Other channels do NOT auto-enable after test
- Other channels do NOT read env vars for configuration
- Channel disabled: every operation on a DISABLED channel returns appropriate error
- Deduplication: same event within window is suppressed; different window creates new entry
- Rate limiting: recipient at limit is queued or rejected per overflow action
- Priority: CRITICAL bypasses rate limits; LOW is batch-eligible
- Template rendering: variables substituted; HTML escaped; missing variable handled gracefully
- Delivery idempotency: same notification ID processed twice produces one delivery
- Retry logic: failed delivery retried with backoff; dead letter after max attempts
- Inter-channel failover: primary DEGRADED/FAILED → fallback channel attempted automatically
- Webhook signature: valid signature accepted; invalid rejected
- Audit log: every delivery attempt and config change creates an immutable audit_log entry
- CAN-SPAM: marketing email includes physical address; unsubscribe link works within 10 days
- GDPR: erasure request deletes delivery logs; legal basis documented per user in preference record
- Localization: template renders correct locale for user preference; falls back to `en`
- Help content: every channel has non-empty help.md and all config fields have tooltip content

---

## Step 22 — Document in IDEA.md and SPEC.md

After all code is written and tests pass, update project documentation.

**IDEA.md** — append to `## Constraints and non-negotiables`:

```
### Notifications (built by notifications-builder)

Channels installed: {list all installed channels}
Features installed: {list all installed features}

Non-negotiable rules — must not be changed or removed:
- All channels default to DISABLED; only SMTP auto-enables on successful test
- SMTP env vars (SMTP_HOST, etc.) are initial form values only — never the active config source
- No other channel reads environment variables for its configuration
- Channel credentials follow the host template's secrets rules (`secrets.yml`) — never in code or committed files
- Channel state machine is enforced — no channel activates without going through CONFIGURING and TESTING
- Integrated help system is mandatory — [?] tooltips on every field, channel help.md for every channel
- Configuration hierarchy: Web UI > env vars (SMTP only) > auto-detection (SMTP only)
- Deduplication enforced by event type + source + recipient + time window
- CRITICAL priority bypasses rate limits and delivers immediately
- Delivery queue is idempotent — duplicate notification IDs produce exactly one delivery
- Failed deliveries retry with exponential backoff; dead letter after 5 attempts (never silently dropped)
- User-supplied values are always escaped before template rendering
- Unsubscribe tokens are signed and time-limited — never use user ID or email as token
- Marketing email requires explicit opt-in; transactional email cannot be fully disabled
- All configuration changes and delivery attempts recorded in append-only audit_log
- CAN-SPAM and GDPR compliance required for all email channels (unsubscribe, physical address, legal basis)
- Templates are locale-aware; locale resolution: user preference → account → Accept-Language → en
- Inter-channel failover configured per notification type; automatic on channel failure
- No AI service required or used in production; AI tools assist development only
```

**SPEC.md** — append a `## Notifications overrides (notifications-builder)` section recording which channels were installed and the non-negotiable rules above.

---

## Rules

- **Read the spec first** — `~/.claude/TEMPLATES/NOTIFICATIONS.md` is the authoritative source; implement it, do not invent
- **All channels disabled by default** — except SMTP, which auto-enables on successful test; this is the only exception
- **SMTP env vars are hints only** — initial form values, never the active configuration source; no other channel reads env vars
- **Channel plugin structure is mandatory** — every channel is a self-contained directory with channel.{ext}, config.schema.json, templates/, tests.{ext}, help.md
- **Help system is mandatory** — every field gets a `[?]` tooltip; help.md per channel is required; skipping this is an explicit anti-pattern
- **Channel state machine is enforced** — DISABLED → CONFIGURING → TESTING → ACTIVE; no shortcuts
- **Deduplication is required** — spec defines exact time windows per priority; implement them
- **Never silently drop** — dead letter queue for exhausted retries; always recoverable
- **Idempotent delivery** — every delivery path must be safe to execute twice
- **Audit everything** — every configuration change, every delivery attempt, every delivery result goes into the append-only audit_log; no operation is silent
- **Privacy compliance** — CAN-SPAM: physical address + working unsubscribe on all marketing email; GDPR: send only with legal basis, honor erasure requests, document consent
- **Localization ready** — templates are locale-driven; no hardcoded English strings in template logic; translation mechanism required from day one
- **Inter-channel failover** — primary channel failure triggers automatic attempt on configured fallback channels; admin configures fallback chains per notification type
- **AI for development only** — AI tools assist in scaffolding channel plugins; no AI service required or used at runtime in production
- **No credentials in code** — provider keys follow the host template's secrets rules (`secrets.yml`); never in code or committed files (SMTP env vars are pre-fill hints only)
- **No raw HTML injection** — all user-supplied values escaped before template rendering
- **No partial implementation** — no stubs, no TODOs in logic, no calls to non-existent functions
- **Discover before creating** — check whether files already exist; extend rather than overwrite
- **Adapt to the stack** — translate spec concepts to the project's language, framework, and DB idioms
- **Always document** — Step 22 is mandatory; record what was built in IDEA.md and SPEC.md
