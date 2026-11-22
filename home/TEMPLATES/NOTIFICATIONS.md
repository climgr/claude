# 📬 Universal Notification System Specification v2.0

## 📖 Table of Contents
1. [Purpose & Scope](#purpose--scope)
2. [Core Design Principles](#core-design-principles)
3. [System Architecture](#system-architecture)
4. [Notification Channels](#notification-channels)
5. [SMTP Email System](#smtp-email-system)
6. [Channel Configuration](#channel-configuration)
7. [Notification Lifecycle](#notification-lifecycle)
8. [Template Management](#template-management)
9. [Routing & Delivery](#routing--delivery)
10. [User Preferences](#user-preferences)
11. [Administrative Controls](#administrative-controls)
12. [Integrated Help System](#integrated-help-system)
13. [Testing & Validation](#testing--validation)
14. [Security & Compliance](#security--compliance)
15. [Failure Handling & Recovery](#failure-handling--recovery)
16. [Audit & Logging](#audit--logging)
17. [Integration Points](#integration-points)
18. [AI Development Guidelines](#ai-development-guidelines)
19. [Implementation Guidelines](#implementation-guidelines)
20. [Appendix](#appendix)

---

## 🎯 Purpose & Scope

### Purpose
This specification defines a complete notification system designed to be integrated into any type of project—web applications, APIs, microservices, enterprise systems, or IoT platforms. It provides multi-channel notification delivery with 30+ channels (all disabled by default except SMTP on successful test), template management, user preferences, and comprehensive delivery guarantees.

### Scope
- **Language/Framework Agnostic**: Implementable in any programming language
- **Database Agnostic**: Works with any storage system
- **Transport Agnostic**: Supports any communication protocol
- **Deployment Agnostic**: Cloud, on-premise, edge, or hybrid
- **Scale Agnostic**: Single user to millions of recipients

### What This Specification Defines
- Notification channels and their configuration
- Delivery state machines and guarantees
- Template system and customization
- User preference management
- Administrative controls
- Security and compliance requirements
- Failure handling and recovery
- Integrated help and documentation

### What This Specification Does NOT Define
- Specific API endpoints or routes
- Database schemas or table structures
- Message queue implementations
- Specific encryption algorithms
- Visual design or UI layouts
- Third-party service credentials
- Cron expressions or scheduling syntax

---

## 🏗️ Core Design Principles

### 1. Secure by Default
**Principle**: All channels start disabled. Credentials are never exposed.
- All notification channels disabled on installation (except SMTP on test success)
- Settings live in `server.yml` / `yaml.d/` (`yaml.d/` area files are synced through the database in cluster mode; `server.yml` and `secrets.yml` are node-local); credentials live in `secrets.yml` (mode `0600`); the admin UI writes the owning area file
- All user-facing strings are translated; keys follow the `errors.*` / `notifications.*` pattern
- Credentials kept only in `secrets.yml` (mode `0600`), never in `server.yml` or `yaml.d/`
- No sensitive data in logs
- Automatic credential rotation support

### 2. User Control
**Principle**: Users maintain control over their notification preferences.
- Users can manage their own channels (if allowed)
- Granular preference controls
- Unsubscribe mechanisms
- Data portability
- Privacy-first design

### 3. Delivery Reliability
**Principle**: Notifications must be delivered or explicitly failed.
- Automatic retries with backoff
- Failover to alternate channels
- Delivery confirmation tracking
- Dead letter queue for failures
- Audit trail for all attempts

### 4. Self-Contained Documentation
**Principle**: All configuration help is within the UI.
- Integrated tooltips on every field
- Channel setup guides in-UI
- Interactive testing tools
- No external documentation needed
- Provider-specific instructions included

### 5. Graceful Degradation
**Principle**: System continues functioning despite channel failures.
- Channel failures don't block operations
- Automatic failover to backup channels
- Queue overflow handling
- Service continuity during outages
- Clear failure notifications

### 6. Template Flexibility
**Principle**: Notifications adapt to channel capabilities.
- Channel-specific formatting
- Rich media support where available
- Graceful downgrade for simple channels
- User-customizable templates
- Localization support

---

## 🏛️ System Architecture

### Component Overview

```
Notification System
├── Channel Manager (30+ channels, all disabled by default)
├── Template Engine (per-channel templates)
├── Delivery Engine (state machine, retries)
├── Queue System (priority, deduplication)
├── Preference Manager (user/admin settings)
├── Credential Store (encrypted)
├── Audit Logger (all operations)
└── Help System (integrated guides)
```

### Notification Flow

```
1. Event Triggered
   ↓
2. Load Recipients & Preferences
   ↓
3. Apply Templates
   ↓
4. Queue for Delivery
   ↓
5. Select Channel(s)
   ↓
6. Attempt Delivery
   ↓
7. Handle Success/Failure
   ↓
8. Audit & Confirm
```

### Configuration Hierarchy

```
System Defaults
  ↓ (overridden by)
Admin Configuration
  ↓ (overridden by)
Team/Project Settings (if applicable)
  ↓ (overridden by)
User Preferences
```

---

## 📢 Notification Channels

### Channel Overview

**CRITICAL**: All 30+ notification channels ship DISABLED by default. Each must be explicitly configured via the admin UI (which writes the config files). SMTP is re-tested every startup; failure disables email, logs a warning, and retries next start.
**EXCEPTION**: SMTP automatically enables upon successful test connection.

### Available Channels by Category

#### Email Channels (1 channel, special handling)
```yaml
SMTP:
  - Universal email protocol
  - 30+ provider presets
  - Auto-enables on successful test
  - Custom configuration support
  - Local server auto-detection
```

#### Team Communication (6 channels)
```yaml
Slack:
  - Workspace messaging
  - Rich formatting, blocks
  - Threads, mentions
  - File attachments
  
Discord:
  - Community messaging
  - Embeds, reactions
  - Voice channel alerts
  - Role mentions
  
Microsoft Teams:
  - Enterprise messaging
  - Adaptive cards
  - Channel/chat support
  - Office 365 integration
  
Mattermost:
  - Self-hosted Slack alternative
  - Open source
  - Webhooks, slash commands
  - Plugin support
  
Rocket.Chat:
  - Self-hosted team chat
  - Real-time messaging
  - Integration framework
  - Video conferencing
  
Zulip:
  - Topic-threaded chat
  - Open source option
  - Email gateway
  - Mobile apps
```

#### Instant Messaging (8 channels)
```yaml
Telegram:
  - Bot-based messaging
  - Groups, channels
  - Rich media support
  - Global reach
  
WhatsApp Business:
  - Business messaging
  - Template messages
  - Media support
  - End-to-end encryption
  
Signal:
  - Privacy-focused
  - End-to-end encryption
  - Group messaging
  - Self-hosted option
  
IRC:
  - Legacy protocol
  - Minimal dependencies
  - Text-only
  - Wide client support
  
XMPP/Jabber:
  - Federated messaging
  - Self-hostable
  - Extensible protocol
  - Multi-client support
  
Matrix:
  - Decentralized protocol
  - Bridging support
  - End-to-end encryption
  - Federation
  
LINE:
  - Popular in Asia
  - Rich messages
  - Stickers, media
  - Business accounts
  
WeChat Work:
  - Enterprise WeChat
  - Chinese market
  - Rich interactions
  - Mini programs
```

#### Mobile Push (5 channels)
```yaml
Pushover:
  - Personal notifications
  - Priority levels
  - Simple API
  - Device targeting
  
Pushbullet:
  - Multi-device sync
  - File sharing
  - SMS integration
  - Browser extension
  
Firebase Cloud Messaging:
  - Android/iOS/Web push
  - Topic messaging
  - Device groups
  - Analytics
  
Apple Push Notification Service:
  - iOS/macOS native
  - Silent notifications
  - Rich notifications
  - Provisional auth
  
OneSignal:
  - Cross-platform push
  - Segmentation
  - A/B testing
  - In-app messaging
```

#### Incident Management (4 channels)
```yaml
PagerDuty:
  - Incident response
  - Escalation policies
  - On-call scheduling
  - Service dependencies
  
Opsgenie:
  - Alert management
  - Team routing
  - Escalation rules
  - Integration hub
  
VictorOps:
  - Incident collaboration
  - Timeline tracking
  - Team communication
  - Runbook integration
  
AlertManager:
  - Prometheus integration
  - Alert grouping
  - Silencing rules
  - Clustering support
```

#### SMS/Voice (4 channels)
```yaml
Twilio:
  - SMS, MMS, Voice
  - Global coverage
  - Programmable messaging
  - Number provisioning
  
Vonage (Nexmo):
  - SMS, Voice APIs
  - Number verification
  - Global reach
  - Failover support
  
AWS SNS:
  - SMS capability
  - Topic subscriptions
  - Cross-region
  - Cost effective
  
Plivo:
  - SMS, Voice platform
  - Global coverage
  - Number management
  - Conference calls
```

#### Generic Integrations (2 channels)
```yaml
Webhook:
  - Custom HTTP endpoints
  - Flexible payload
  - Headers, auth
  - Any REST API
  
MQTT:
  - IoT messaging
  - Pub/sub model
  - QoS levels
  - Lightweight protocol
```

### Channel States

Each channel can be in one of these states:

```
DISABLED: Not configured (default for all)
CONFIGURING: Setup in progress
TESTING: Validation running
ACTIVE: Fully operational
DEGRADED: Partial failures
FAILED: Not operational
MAINTENANCE: Temporarily offline
```

---

## 📧 SMTP Email System

### SMTP Special Handling

**UNIQUE BEHAVIOR**: SMTP is the only channel that auto-enables upon successful test. The connection is re-tested on every startup; failure disables email, logs a warning, and is retried next start.

### SMTP Configuration

#### Configuration Methods (Priority Order)

SMTP can be configured through multiple methods, checked in this order:

1. **Environment Variables** (`SMTP_*`; override file settings)
2. **Configuration Files** (`server.yml` / `yaml.d/`, credentials in `secrets.yml`; the admin UI writes the owning area file)
3. **Auto-Detection** (Automatic local server detection; the detected `host:port` is saved to `server.yml`)

#### Environment Variable Support (Optional)

**Standard SMTP Environment Variables**:
```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=user@example.com
SMTP_PASSWORD=secret
SMTP_TLS=auto
SMTP_FROM_NAME="System Notifications"
SMTP_FROM_EMAIL=noreply@example.com
```

`SMTP_TLS` is a mode: `auto`, `starttls`, `tls`, or `none` (default `auto`). No other aliases are supported.

**Environment Variable Behavior**:
- `SMTP_*` environment variables override the same settings in the configuration files
- The admin UI writes the owning area file (`server.yml` / `yaml.d/`), with credentials in `secrets.yml`
- Useful for containerized deployments and infrastructure-as-code

#### Auto-Detection Sequence
When no SMTP host is configured (neither files nor environment), the system tries each host on ports 25, 465, 587, in priority order:

| Priority | Host |
|----------|------|
| 1 | `127.0.0.1` (loopback) |
| 2 | `172.17.0.1` (Docker bridge gateway) |
| 3 | `{gateway_ip}` (default gateway) |
| 4 | `{fqdn}` (detected FQDN) |
| 5 | `{global_ipv4}` (global IPv4, if available) |
| 6 | `mail.{fqdn}` |
| 7 | `smtp.{fqdn}` |

The first successful SMTP handshake (EHLO) wins:
  - SMTP is automatically ENABLED
  - The detected `host:port` is saved to `server.yml`
  - User is notified of auto-configuration
  - If all fail, email features stay disabled (not an error)

#### Connection Test
- When a host is set, the connection is re-tested on every startup (EHLO)
- Failure disables email, logs a warning, and the server keeps running; the test is retried on the next start

#### TLS Mode `auto`
`tls: auto` (the default) is decided per port: 25 and 587 (and any other port) start plain and upgrade with STARTTLS when offered; 465 is implicit TLS. A TLS hello is never sent to port 25. `AUTH` is sent only after TLS is established. Certificate verification is skipped only when `smtp.host` is a private-range IP literal; hostnames are always verified.

#### Configuration Priority
```
1. Environment Variables (SMTP_*) - Always win
2. Configuration files (server.yml / yaml.d/, secrets.yml)
3. Auto-detection (if neither) - Tests and saves to server.yml
```

#### SMTP Configuration Fields
```
Configuration:
├── Provider: [Custom ▼] (default, attempts auto-detect)
├── Host: [___________] [?] Server address
│   [ℹ️ From env: SMTP_HOST=smtp.gmail.com]
├── Port: [___________] [?] Usually 25, 587, or 465
│   [ℹ️ From env: SMTP_PORT=587]
├── Security: [None/STARTTLS/SSL ▼] [?] Encryption type
├── Username: [___________] [?] Often full email address
│   [ℹ️ From env: SMTP_USERNAME set]
├── Password: [***hidden***] [?] App password may be required
│   [ℹ️ From env: SMTP_PASSWORD set]
├── From Name: [___________] [?] Sender display name
│   [ℹ️ From env: SMTP_FROM_NAME="Notifications"]
├── From Address: [___________] [?] Must be valid email
│   [ℹ️ From env: SMTP_FROM_EMAIL=noreply@example.com]
├── Reply-To: [___________] [?] Optional reply address
└── [Test Connection] [Save]

Environment Variable Notice:
┌─────────────────────────────────────────────┐
│ ℹ️ Environment variables detected and loaded │
│ These values override the config files.     │
│ Env-provided fields are read-only here.     │
│ To change them, edit the env and restart.   │
└─────────────────────────────────────────────┘

Test Results:
✓ Connection established
✓ Authentication successful
✓ Test email sent
✓ SMTP AUTOMATICALLY ENABLED
```

**UI Behavior with Environment Variables**:
- Fields show the effective value; small info text shows which env var provided it
- Password fields show as masked if env var is set
- Environment variables override file values, so an env-provided field is read-only in the UI
- Saving writes the owning area file; credentials go to `secrets.yml`

### SMTP Provider Categories

#### Provider Selection Interface
```
Provider Selection
━━━━━━━━━━━━━━━━
Categories:
├── Custom (Default) [Auto-detects local]
├── Major Providers (5)
├── Business Email (4)
├── Transactional (7)
├── Regional (5)
├── ISP Providers (5)
└── Self-Hosted (4)

[Search providers...]
```

---

## ⚙️ Channel Configuration

### Configuration Access Models

Projects must choose who configures notifications:

#### Model A: Admin-Only Configuration
```
Location: Admin panel
Access: System administrators only
Scope: Global notification settings
Channels: Shared credentials for all users

Example Flow:
1. Admin configures Slack webhook
2. All alerts go to #alerts channel
3. Users cannot modify settings
```

#### Model B: User Self-Service
```
Location: User settings/profile
Access: Each user configures own channels
Scope: Personal notification preferences
Channels: Individual credentials per user

Example Flow:
1. User adds personal Telegram bot
2. User configures own email
3. User manages channel priorities
```

#### Model C: Hybrid Model
```
Admin Location: System-wide channels
User Location: Personal preferences
Scope: Admin provides, users customize

Example Flow:
1. Admin sets company Slack
2. Users add personal email
3. Users choose channel preferences
```

### Channel Configuration Interface

#### Generic Channel Setup
```
Channel Configuration: [Channel Name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Status: ○ Disabled ● Enabled

[?] Setup Guide ────────────────────────
│ 1. Create account at [provider]
│ 2. Generate API token/webhook
│ 3. Configure permissions
│ 4. Copy credentials below
│ 5. Test connection
│ Need help? [View detailed guide ↗]
└────────────────────────────────────────

Configuration:
├── [Channel-specific fields with tooltips]
├── [Test Connection]
├── [Save Configuration]
└── [Disable Channel]
```

### Channel-Specific Configuration Examples

#### Slack Configuration
```
[?] Setup Guide ────────────────────────
│ 1. Go to api.slack.com/apps
│ 2. Create new app or select existing
│ 3. Add "Incoming Webhook" feature
│ 4. Select channel for notifications
│ 5. Copy webhook URL
│ Tips: Use separate webhooks per environment
└────────────────────────────────────────

Webhook URL: [___________] [?] Starts with https://hooks.slack.com
Channel Override: [___________] [?] Optional, #channel or @user
Username: [___________] [?] Bot display name
Icon: [___________] [?] :emoji: or image URL
[Test in Slack]
```

#### Telegram Configuration
```
[?] Setup Guide ────────────────────────
│ 1. Message @BotFather on Telegram
│ 2. Send /newbot command
│ 3. Choose bot name and username
│ 4. Copy the bot token
│ 5. Get chat ID (message @userinfobot)
│ Note: Bot must be added to group/channel
└────────────────────────────────────────

Bot Token: [___________] [?] Format: 123456:ABC-DEF...
Chat ID: [___________] [?] Number or @channelname
Parse Mode: [Markdown ▼] [?] Message formatting
Silent: ☐ [?] Deliver without sound
[Send Test Message]
```

---

## 🔄 Notification Lifecycle

### Notification States

```
CREATED: Notification generated
QUEUED: In delivery queue
SCHEDULED: Delayed delivery
SENDING: Delivery in progress
DELIVERED: Successfully sent
FAILED: Delivery failed
RETRYING: In retry loop
EXPIRED: Max retries exceeded
CANCELLED: Manually cancelled
```

### State Transitions

```
[CREATED]
    ↓
[QUEUED] → [SCHEDULED]
    ↓           ↓
[SENDING] ←─────┘
    ├─→ [DELIVERED]
    ├─→ [FAILED] → [RETRYING] → [SENDING]
    └─→ [CANCELLED]              ↓
                             [EXPIRED]
```

### Delivery Process

#### Phase 1: Creation
```
1. Event triggers notification
2. Load recipient preferences
3. Apply business rules
4. Create notification record
5. Set priority and TTL
```

#### Phase 2: Queueing
```
1. Add to appropriate queue
2. Check for duplicates
3. Apply rate limiting
4. Set delivery window
5. Calculate retry policy
```

#### Phase 3: Delivery
```
1. Select channel(s)
2. Apply template
3. Attempt send
4. Record result
5. Handle response
```

#### Phase 4: Confirmation
```
1. Update delivery status
2. Log attempt details
3. Trigger webhooks
4. Update metrics
5. Clean up resources
```

### Priority Levels

```yaml
CRITICAL:
  - Immediate delivery
  - Bypass rate limits
  - All channels attempted
  - Escalation if failed
  
HIGH:
  - Quick delivery (< 1 min)
  - Priority queue
  - Multiple channels
  - Standard retries
  
NORMAL:
  - Standard delivery
  - Regular queue
  - Configured channels
  - Default retries
  
LOW:
  - Batch delivery allowed
  - Can be delayed
  - Single channel OK
  - Limited retries
```

---

## 📝 Template Management

### Template System Architecture

```
Template Engine
├── Base Templates (system defaults)
├── Channel Templates (per channel format)
├── Custom Templates (user-defined)
├── Variable Engine (data injection)
├── Formatter (channel adaptation)
└── Localization (multi-language)
```

### Template Variables

Variable names below are catalog-only (channel-agnostic); actual delimiter syntax is per-channel/per-engine — see each channel's template example (Email defers to the host project's `{variable}` engine when one exists; Slack/SMS shown here use `{{variable}}` since they have no host-engine equivalent).

#### System Variables
```
{{notification_id}} - Unique identifier
{{timestamp}} - ISO 8601 timestamp
{{priority}} - Priority level
{{event_type}} - Type of event
{{event_id}} - Event identifier
{{system_name}} - System identifier
{{environment}} - Dev/staging/prod
```

#### Event Variables
```
{{title}} - Notification title
{{message}} - Main content
{{description}} - Detailed description
{{action_url}} - Action link
{{action_text}} - Action button text
{{category}} - Event category
{{tags}} - Associated tags
```

#### Recipient Variables
```
{{recipient_name}} - User's name
{{recipient_email}} - User's email
{{recipient_id}} - User identifier
{{recipient_timezone}} - User's timezone
{{recipient_language}} - Preferred language
{{unsubscribe_url}} - Opt-out link
```

### Channel-Specific Templates

#### Email Template

**When the host project already ships an email-template engine** (Go/Rust `SERVER.md`/`API.md`/`HYBRID.md` § EMAIL & NOTIFICATIONS), defer to it — do not introduce a second, incompatible engine. That engine uses plain `{variable}` string substitution only (no template-side conditionals/loops); optional sections like an action link are handled by the caller choosing which template variant to render, not by an inline `{{#if}}` block:

```
Subject: [{priority}] {title}
---
{title}

{message}

Time: {timestamp}

{action_text}: {action_url}

--
Unsubscribe: {unsubscribe_url}
```

**When no host template engine exists** (e.g. non-Go/Rust project), the notifications-builder may implement any variable-substitution engine it chooses, documenting the actual syntax used — never assume Handlebars-style `{{variable}}`/`{{#if}}` without confirming the target stack supports it.

#### Slack Template
```json
{
  "text": "{{title}}",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "{{title}}"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "{{message}}"
      }
    }
  ]
}
```

#### SMS Template
```
{{title}}
{{message|truncate:140}}
Reply STOP to opt out
```

### Template Management UI

```
Template Editor
━━━━━━━━━━━━━━
Channel: [Slack ▼]
Event Type: [Alert ▼]
Language: [English ▼]

[Template Editor with syntax highlighting]
[Variable Reference] [Preview]

Preview:
┌─────────────────────────┐
│ [Live preview window]   │
└─────────────────────────┘

[Test with Sample Data] [Save Template]
```

---

## 🚦 Routing & Delivery

### Routing Rules

#### Rule Configuration
```
Routing Rules
━━━━━━━━━━━━
Event Type: [System Alert ▼]
Priority: [High ▼]

Channels (in order):
1. [Email] [↑↓]
2. [Slack] [↑↓]  
3. [SMS]   [↑↓]

Delivery Mode:
○ Sequential (failover)
● Parallel (all at once)
○ First available

Conditions:
[+ Add Condition]
├── If time between 22:00-08:00
│   └── Use only: [Email]
├── If user.role = "admin"
│   └── Also send to: [PagerDuty]
└── If failure_count > 3
    └── Escalate to: [Phone Call]

[Save Rules]
```

### Deduplication

#### Deduplication Rules
```yaml
Deduplication Key:
  - Event Type
  - Event Source  
  - Recipient
  - Time Window
  
Time Windows:
  CRITICAL: 5 minutes
  HIGH: 15 minutes
  NORMAL: 1 hour
  LOW: 24 hours
  
On Duplicate:
  - Increment counter
  - Update last_seen
  - Skip delivery
  - Log occurrence
```

### Rate Limiting

#### Rate Limit Configuration
```
Rate Limiting
━━━━━━━━━━━━
Channel: [Email ▼]

Limits:
├── Per Recipient: [10] per [hour ▼]
├── Per Channel: [1000] per [hour ▼]
├── Burst Allowance: [20] messages
└── Global Maximum: [5000] per [day ▼]

On Limit Exceeded:
○ Queue for later
● Drop with warning
○ Escalate to admin
○ Use alternate channel

Bypass for:
☑ CRITICAL priority
☐ Admin recipients
☑ Security events
```

### Retry Strategy

#### Retry Configuration
```
Retry Policy
━━━━━━━━━━━
Channel: [All ▼]

Strategy: [Exponential Backoff ▼]
Max Attempts: [5]
Initial Delay: [30] seconds
Max Delay: [1] hours
Multiplier: [2]

Retry On:
☑ Network errors
☑ Timeout
☑ 5xx responses
☐ 4xx responses
☐ Rate limits

After Max Retries:
● Move to dead letter queue
○ Escalate to admin
○ Silently fail
○ Try alternate channel
```

---

## 👤 User Preferences

### Preference Management

#### User Preference Interface
```
Notification Preferences
━━━━━━━━━━━━━━━━━━━━━━

My Channels:
├── ✓ Email (john@example.com)
├── ✓ Slack (via company workspace)
├── ✗ SMS (not configured) [Setup]
└── ✓ Telegram (@johndoe) [Edit]

Channel Priority:
1. Telegram (instant messages)
2. Email (important notices)
3. Slack (work hours only)
[Reorder]

Quiet Hours:
☑ Enable quiet hours
From: [22:00] To: [08:00]
Timezone: [America/New_York ▼]
Override for: ☑ Critical alerts

Categories:
☑ Security Alerts → Email, Telegram
☑ System Updates → Email
☐ Marketing → None
☑ Account Activity → Telegram
[Manage Categories]
```

### Subscription Management

#### Opt-in/Opt-out Controls
```
Subscription Settings
━━━━━━━━━━━━━━━━━━━

Global:
○ All notifications enabled
○ Critical only
○ All notifications disabled

By Category:
├── Security: ● On ○ Off
├── Billing: ● On ○ Off
├── Updates: ○ On ● Off
└── Marketing: ○ On ● Off

By Channel:
├── Email: ● All ○ Critical ○ None
├── SMS: ○ All ● Critical ○ None
└── Push: ● All ○ Critical ○ None

[Update Preferences]
```

### Preference Storage

```yaml
User Preferences:
  user_id: unique_identifier
  channels:
    - type: email
      address: user@example.com
      verified: true
      enabled: true
    - type: telegram
      chat_id: 123456789
      enabled: true
  quiet_hours:
    enabled: true
    start: "22:00"
    end: "08:00"
    timezone: "America/New_York"
    override_priority: ["critical"]
  categories:
    security: ["email", "telegram"]
    billing: ["email"]
    marketing: []
  language: "en"
  format_preference: "html"
```

---

## 👨‍💼 Administrative Controls

### Dashboard Overview

```
Notification System Dashboard
━━━━━━━━━━━━━━━━━━━━━━━━━━━

Statistics (Last 24 Hours):
├── Sent: 12,456
├── Delivered: 12,001 (96.3%)
├── Failed: 455 (3.7%)
├── Pending: 234
└── Retry Queue: 89

Channel Health:
├── ✓ Email (SMTP) - Auto-enabled
├── ✓ Slack - Healthy
├── ⚠ SMS - Degraded (rate limited)
├── ✗ Discord - Failed (invalid webhook)
└── ○ 26 channels disabled

Top Events:
1. User Login (4,234)
2. Password Reset (892)
3. System Alert (445)
[View All]

[Manage Channels] [View Logs] [Settings]
```

### Channel Management

```
Channel Management
━━━━━━━━━━━━━━━━━
Total Available: 30 channels
Currently Enabled: 4 (including auto-enabled SMTP)

Quick Actions:
[Test All Channels] [Disable All] [Export Config]

Channel List:
┌─────────────────────────────────────┐
│ Channel     Status      Health  Actions│
├─────────────────────────────────────┤
│ SMTP        Enabled*    ✓       [View]│
│ Slack       Enabled     ✓       [Edit]│
│ Discord     Enabled     ✗       [Fix] │
│ SMS         Enabled     ⚠       [View]│
│ Telegram    Disabled    -       [Setup]│
│ [... 25 more disabled channels ...]   │
└─────────────────────────────────────┘
*Auto-enabled on successful test
```

### Global Settings

```
Global Configuration
━━━━━━━━━━━━━━━━━━
System Settings:
├── Default Priority: [Normal ▼]
├── Retry Attempts: [3]
├── Queue Size: [10000]
├── TTL: [24] hours
└── Dead Letter Action: [Alert Admin ▼]

Features:
☑ Enable notifications
☑ Allow user preferences
☑ Deduplication
☑ Rate limiting
☐ Digest mode
☑ Audit logging

Compliance:
☑ GDPR compliant
☑ Include unsubscribe
☑ Honor quiet hours
☑ Log retention: [90] days

[Save Settings]
```

---

## 📚 Integrated Help System

### Contextual Help

#### Tooltip System
```
Every field includes [?] tooltips:
- What the field does
- Expected format
- Common values
- Security notes
- Provider-specific tips
```

#### Channel Setup Guides

**Example: Setting up Slack**
```
[?] Slack Setup Guide ─────────────────
│ Step-by-Step Instructions:
│ 
│ 1. Create Slack App
│    • Go to api.slack.com/apps
│    • Click "Create New App"
│    • Choose "From scratch"
│    • Name: "Notifications"
│    • Select your workspace
│ 
│ 2. Add Webhook Feature
│    • Click "Incoming Webhooks"
│    • Toggle "Activate"
│    • Click "Add New Webhook"
│    • Choose channel (#alerts)
│    • Copy webhook URL
│ 
│ 3. Configure Here
│    • Paste webhook URL below
│    • Set custom username (optional)
│    • Choose icon (optional)
│    • Test connection
│ 
│ Common Issues:
│ • "Invalid webhook" - Check URL format
│ • "Channel not found" - Verify channel exists
│ • "No permission" - Check app installation
│ 
│ [View Video Tutorial] [Slack Docs ↗]
└──────────────────────────────────────
```

### Troubleshooting Wizard

```
Notification Troubleshooting
━━━━━━━━━━━━━━━━━━━━━━━━━

What's the issue?
○ Notifications not sending
● Channel configuration failing
○ Delayed notifications
○ Wrong recipients
○ Template problems

Which channel? [Slack ▼]

Error Message:
[Invalid webhook URL___________]

[Diagnose Problem]

Diagnosis:
⚠️ Webhook URL format is incorrect

Solution:
1. Webhook should start with https://hooks.slack.com/
2. Check for extra spaces or characters
3. Regenerate webhook if needed
4. Test with curl command below:

[Copy Test Command] [Try Again]
```

### Provider Comparison

```
Channel Comparison Tool
━━━━━━━━━━━━━━━━━━━━━

Compare: [Slack] vs [Discord] vs [Teams]

                    Slack  | Discord | Teams
Setup Difficulty    Easy   | Easy    | Medium
Cost               Free*   | Free    | Free*
Rate Limits        1/sec   | 5/sec   | 60/min
Rich Formatting    ✓✓✓    | ✓✓✓     | ✓✓
File Attachments   ✓       | ✓       | ✓
Threading          ✓       | ✓       | ✗
Mobile App         ✓       | ✓       | ✓
Self-Hosted        ✗       | ✗       | ✗

*Paid plans required for some features

[View Detailed Comparison]
```

---

## 🧪 Testing & Validation

### Channel Testing

#### Test Interface
```
Channel Test
━━━━━━━━━━━
Channel: [Slack ▼]

Test Type:
● Basic connectivity
○ Full notification
○ Load test
○ Failure simulation

Test Message:
[This is a test notification from {{system_name}}]

Additional Options:
☐ Include timestamp
☐ Test all configured channels
☐ Verify delivery receipt

[Send Test]

Test Results:
✓ Connection established (45ms)
✓ Authentication successful
✓ Message sent
✓ Delivery confirmed
✓ Channel is healthy

[View Details] [Download Report]
```

### SMTP Auto-Test

#### Special SMTP Testing Behavior
```
SMTP Configuration Test
━━━━━━━━━━━━━━━━━━━━━━

Testing Configuration...
[████████████████░░░░] 80%

✓ Checking localhost:25... Success!
✓ Authentication: Not required
✓ Sending test email... Delivered
✓ Verifying receipt... Confirmed

⚠️ SMTP AUTOMATICALLY ENABLED
   Configuration saved and activated

Your SMTP configuration:
Host: localhost
Port: 25
Security: None
Status: ACTIVE (auto-enabled)

[View Configuration] [Send Another Test]
```

### Validation Rules

#### Configuration Validation
```yaml
Email Validation:
  - RFC 5322 compliance
  - MX record verification
  - Deliverability check
  - Blacklist check
  
Webhook Validation:
  - URL format check
  - HTTPS requirement
  - Endpoint reachability
  - Response verification
  
Token Validation:
  - Format verification
  - API test call
  - Permission check
  - Expiry monitoring
```

---

## 🔐 Security & Compliance

### Credential Management

#### Encryption
```yaml
Storage:
  - AES-256 encryption at rest
  - Unique key per credential
  - Key rotation support
  - Hardware security module (optional)
  
Access:
  - Role-based access control
  - Audit on every access
  - Masked display in UI
  - No export capability
  
Rotation:
  - Automated rotation available
  - Zero-downtime updates
  - Version history maintained
  - Rollback capability
```

### Privacy Compliance

#### GDPR Requirements
```
Data Protection:
  - Explicit consent for marketing
  - Right to erasure (delete all prefs)
  - Data portability (export prefs)
  - Privacy by design
  - Audit trail of consent
  
Unsubscribe:
  - One-click unsubscribe
  - Immediate effect
  - Confirmation message
  - Preference center link
```

#### Regional Compliance
```yaml
CAN-SPAM (US):
  - Physical address required
  - Clear identification
  - Opt-out mechanism
  - 10-day processing
  
CASL (Canada):
  - Express consent required
  - Unsubscribe in all messages
  - Contact information
  
PECR (UK):
  - Soft opt-in allowed
  - Clear sender identity
  - Valid unsubscribe
```

### Security Measures

#### Access Control
```
Authentication:
  - Multi-factor for admin
  - Session management
  - IP restrictions (optional)
  - API key rotation
  
Authorization:
  - Granular permissions
  - Team-based access
  - Channel-specific rights
  - Audit requirements
```

#### Threat Protection
```yaml
Rate Limiting:
  - Per-user limits
  - Per-IP limits
  - Per-channel limits
  - DDoS protection
  
Input Validation:
  - Template injection prevention
  - XSS protection
  - SQL injection prevention
  - Command injection prevention
  
Monitoring:
  - Anomaly detection
  - Suspicious pattern alerts
  - Failed auth tracking
  - Audit log analysis
```

---

## 🚨 Failure Handling & Recovery

### Channel Failure Handling

#### Failure Detection
```yaml
Health Checks:
  - Periodic connectivity tests
  - API availability monitoring
  - Credential validity checks
  - Rate limit tracking
  
Failure Indicators:
  - Connection timeout
  - Authentication failure
  - Rate limit exceeded
  - Invalid response
  - Service outage
```

#### Recovery Strategies
```
On Channel Failure:
  
1. Immediate Retry:
   - For transient errors
   - Network timeouts
   - Temporary unavailability
   
2. Exponential Backoff:
   - For rate limits
   - Service degradation
   - Persistent errors
   
3. Failover:
   - Switch to backup channel
   - Follow priority order
   - Maintain delivery guarantee
   
4. Queue & Retry:
   - Store for later delivery
   - Retry when healthy
   - Honor TTL limits
   
5. Dead Letter Queue:
   - After max retries
   - Admin notification
   - Manual intervention
```

### System Recovery

#### Graceful Degradation
```yaml
Service Levels:
  Full Service:
    - All channels operational
    - Real-time delivery
    - All features available
    
  Degraded Service:
    - Some channels failed
    - Delayed delivery
    - Failover active
    
  Minimal Service:
    - Only SMTP working
    - Queue building up
    - Manual intervention needed
    
  Maintenance Mode:
    - Notifications queued
    - No delivery attempts
    - Admin access only
```

#### Disaster Recovery
```
Backup Strategy:
  - Configuration backup
  - Credential backup (encrypted)
  - Queue state backup
  - Template backup
  
Recovery Process:
  1. Restore configuration
  2. Validate credentials
  3. Test channels
  4. Process queued messages
  5. Resume normal operation
```

---

## 📊 Audit & Logging

### Audit Trail

#### Logged Events
```yaml
Configuration Changes:
  - Channel enabled/disabled
  - Credential updates
  - Template modifications
  - Rule changes
  - User preference updates
  
Delivery Events:
  - Notification created
  - Queue operations
  - Delivery attempts
  - Success/failure
  - Retries
  
Security Events:
  - Login attempts
  - Permission changes
  - Credential access
  - Failed authentications
  - Suspicious activities
```

#### Log Format
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "event_type": "notification.sent",
  "channel": "slack",
  "recipient": "user_123",
  "status": "success",
  "metadata": {
    "message_id": "msg_abc123",
    "priority": "high",
    "retry_count": 0,
    "delivery_time_ms": 245
  },
  "actor": "system",
  "ip_address": "10.0.0.1"
}
```

### Reporting

#### Delivery Reports
```
Delivery Report
━━━━━━━━━━━━━━
Period: Last 7 Days

Summary:
├── Total Sent: 84,234
├── Delivered: 81,456 (96.7%)
├── Failed: 2,778 (3.3%)
└── Pending: 145

By Channel:
├── Email: 45,234 (98.2% success)
├── Slack: 23,456 (97.1% success)
├── SMS: 12,344 (94.5% success)
└── Discord: 3,200 (91.2% success)

Top Failures:
1. Rate limit exceeded (1,234)
2. Invalid credentials (567)
3. Network timeout (234)

[Export CSV] [View Details]
```

#### Analytics Dashboard
```yaml
Metrics Tracked:
  - Delivery rate by channel
  - Average delivery time
  - Retry success rate
  - Channel availability
  - User engagement rates
  - Template performance
  - Cost per channel (SMS)
  
Visualizations:
  - Time series graphs
  - Channel comparison
  - Geographic distribution
  - Event type breakdown
  - Failure analysis
```

---

## 🔌 Integration Points

### Event Integration

#### Event Sources
```yaml
Application Events:
  - User actions
  - System events
  - Scheduled tasks
  - External triggers
  - API calls
  
Event Format:
  type: "event.type"
  priority: "high"
  recipients: ["user_id", "group_id"]
  data: 
    title: "Event Title"
    message: "Event message"
    metadata: {}
  options:
    channels: ["email", "slack"]
    schedule: "2024-01-15T10:00:00Z"
    ttl: 3600
```

### API Design

#### RESTful Endpoints (Example Structure)
```yaml
Notifications:
  POST /notifications - Send notification
  GET /notifications/:id - Get status
  DELETE /notifications/:id - Cancel
  
Channels:
  GET /channels - List all channels
  GET /channels/:type - Get channel config
  PUT /channels/:type - Update config
  POST /channels/:type/test - Test channel
  
Preferences:
  GET /preferences - Get user preferences
  PUT /preferences - Update preferences
  POST /preferences/unsubscribe - Opt out
  
Templates:
  GET /templates - List templates
  GET /templates/:id - Get template
  PUT /templates/:id - Update template
  POST /templates/test - Test render
```

### Webhook Integration

#### Incoming Webhooks
```yaml
Status Webhooks:
  - Delivery confirmation
  - Failure notification
  - Bounce handling
  - Unsubscribe events
  
Format:
  POST /webhooks/[provider]/[event]
  Headers:
    X-Signature: HMAC-SHA256
    X-Event-Type: delivery.success
  Body:
    Standardized event payload
```

---

## 🤖 AI Development Guidelines (DEVELOPMENT ONLY)

### ⚠️ CRITICAL: AI is for Development, NOT Required in Production

**AI tools are used ONLY during development to:**
- Generate channel integrations
- Create notification templates
- Build retry logic
- Generate test cases
- Create documentation

**The production system:**
- May or may not use AI (implementation choice)
- All notification routing is rule-based
- Channel selection is deterministic
- No AI required for operation

### Using AI Development Tools

#### Initial Setup with AI
```bash
# Example using Claude Code
$ claude-code "Implement notification system with:
  - 30+ channels (all disabled except SMTP on test)
  - Configuration in server.yml / yaml.d / secrets.yml, written by the admin UI
  - Integrated help system
  - Template management
  - User preferences"
```

#### Channel Integration Generation
```bash
# Generate channel integration
$ claude-code "Create Slack notification channel:
  - Webhook support
  - Rich formatting
  - Attachment support
  - Thread replies
  - Retry logic
  - Test functionality"

# Generate all channel stubs
$ claude-code "Generate integration stubs for all 30 channels"
```

#### Template Generation
```bash
# Generate responsive email template
$ claude-code "Create email template with:
  - Responsive HTML
  - Plain text fallback
  - Variable substitution
  - Unsubscribe link"
```

### AI Best Practices

**DO:**
- Use AI to generate boilerplate channel integrations
- Have AI create comprehensive test suites
- Let AI generate template variations
- Use AI for documentation generation
- Generate retry logic patterns

**DON'T:**
- Rely on AI for routing decisions in production
- Use AI for credential management
- Let AI determine security policies
- Generate production credentials with AI
- Use AI for compliance decisions

---

## 💡 Implementation Guidelines

### Architecture Patterns

#### Recommended Patterns
```yaml
Event-Driven:
  - Event bus for notifications
  - Async processing
  - Queue-based delivery
  
Microservices:
  - Notification service separate
  - Channel plugins
  - API gateway
  
Plugin Architecture:
  - Each channel as plugin
  - Dynamic loading
  - Interface compliance
  
Configuration Hierarchy:
  - Environment Variables (SMTP only, override files)
  - Configuration files (persistent)
  - Auto-detection (fallback)
```

#### Anti-Patterns to Avoid
```
DON'T:
  - Store credentials in code
  - Use env vars as primary config (except SMTP hints)
  - Hard-code channel configurations
  - Skip delivery confirmation
  - Ignore rate limits
  - Block on notification send
  - Trust external services blindly
  - Log sensitive data
  - Skip retry logic
```

### SMTP Environment Variable Handling

#### Implementation Requirements
```javascript
// Example SMTP configuration loader
function loadSMTPConfig() {
  // 1. Merge configuration files (server.yml, yaml.d/, secrets.yml)
  const fileConfig = config.get('server.notifications.email.smtp');

  // 2. Environment variables override file values
  const merged = {
    ...fileConfig,
    ...definedOnly({
      host: process.env.SMTP_HOST,
      port: process.env.SMTP_PORT,
      username: process.env.SMTP_USERNAME,
      password: process.env.SMTP_PASSWORD,
      tls: process.env.SMTP_TLS,
    }),
  };

  if (merged.host) {
    return merged;
  }

  // 3. Auto-detection (saves the detected host:port to server.yml)
  return autoDetectSMTP();
}
```

#### Security Considerations
```yaml
Environment Variables:
  - Only for SMTP, not other channels
  - Never log password values
  - Mask in UI display
  - Don't expose in API responses
  - Environment variables override file values
  
Storage:
  - Save config to the owning area file when modified (credentials to `secrets.yml`)
  - Encrypt sensitive values at rest
  - Don't write back to env vars
  - Clear separation of concerns
```

### Channel Implementation

#### Channel Plugin Structure
```
/channels
  /smtp
    - channel.js (implements interface)
    - config.schema.json
    - templates/
    - tests/
    - help.md
  /slack
    - channel.js
    - config.schema.json
    - templates/
    - tests/
    - help.md
  [... 28 more channels]
```

#### Channel Interface
```javascript
interface NotificationChannel {
  // Lifecycle
  initialize(config)
  validate()
  test()
  destroy()
  
  // Delivery
  send(notification)
  sendBatch(notifications)
  
  // Status
  isHealthy()
  getMetrics()
  
  // Configuration
  getConfigSchema()
  getHelpContent()
}
```

### Testing Strategy

#### Required Tests
```yaml
Unit Tests:
  - Channel integrations
  - Template rendering
  - Retry logic
  - Rate limiting
  
Integration Tests:
  - Channel delivery
  - Queue processing
  - Preference management
  - API endpoints
  
End-to-End Tests:
  - Complete notification flow
  - Multi-channel delivery
  - Failure scenarios
  - User preference flow
```

---

## 📋 Appendix

### Channel Quick Reference

#### Channel Categories
- **Email**: 1 channel (SMTP - auto-enables on test)
- **Team Communication**: 6 channels
- **Instant Messaging**: 8 channels  
- **Mobile Push**: 5 channels
- **Incident Management**: 4 channels
- **SMS/Voice**: 4 channels
- **Generic**: 2 channels

**Total Available**: 30 channels
**Default Enabled**: 0 (SMTP auto-enables on successful test)
**Configuration Method**: `server.yml` / `yaml.d/` / `secrets.yml`, written by the admin UI; `SMTP_*` env vars override

### State Diagrams

#### Notification State Machine
```
[CREATED] → [QUEUED] → [SENDING] → [DELIVERED]
              ↓           ↓            
         [SCHEDULED]   [FAILED]        
              ↓           ↓            
         [SENDING]    [RETRYING]       
                          ↓            
                      [EXPIRED]        
```

#### Channel State Machine
```
[DISABLED] → [CONFIGURING] → [TESTING] → [ACTIVE]
                  ↓              ↓          ↓
              [DISABLED]     [FAILED]  [DEGRADED]
                                ↓          ↓
                            [DISABLED] [MAINTENANCE]
```

### Common Error Codes

```yaml
NOTIF-001: Channel not configured
NOTIF-002: Delivery failed
NOTIF-003: Rate limit exceeded
NOTIF-004: Invalid recipient
NOTIF-005: Template error
NOTIF-006: Channel unavailable
NOTIF-007: Credential invalid
NOTIF-008: Network timeout
NOTIF-009: Queue full
NOTIF-010: TTL expired
```

### Glossary

- **Channel**: A communication method (email, Slack, SMS, etc.)
- **Template**: Message format for a channel
- **TTL**: Time-to-live for a notification
- **DLQ**: Dead letter queue for failed messages
- **Webhook**: HTTP callback for events
- **Deduplication**: Preventing duplicate notifications
- **Quiet Hours**: User's do-not-disturb period
- **Failover**: Switching to backup channel
- **Rate Limiting**: Controlling message frequency
- **Batching**: Grouping notifications for efficiency

---

## 📝 Critical Implementation Notes

1. **All Channels Disabled by Default**: System ships with 30+ channels, ALL disabled
2. **SMTP Auto-Enables on Test**: Unique behavior - SMTP enables automatically on successful test
3. **SMTP Environment Variables**: Optional support for standard SMTP env vars (override file values)
4. **Files Are the Source of Truth**: env vars override files; the admin UI writes the owning area file
5. **Integrated Help Required**: All channel setup instructions in-UI with tooltips
6. **Delivery Guarantee**: Every notification must be delivered or explicitly failed
7. **User Control**: Clear preference management and unsubscribe options
8. **Audit Everything**: Every configuration change and delivery attempt logged
9. **Security First**: All credentials encrypted, never exposed
10. **Template Flexibility**: Support channel-specific formatting
11. **Graceful Degradation**: System continues despite channel failures
12. **Testing Built-in**: Every channel must have test functionality
13. **Privacy Compliance**: GDPR, CAN-SPAM, and other regulations
14. **Retry Logic Required**: Automatic retries with exponential backoff
15. **Rate Limit Respect**: Honor provider rate limits
16. **Plugin Architecture**: Each channel is self-contained
17. **AI for Development Only**: AI assists development but not required for production
18. **Help Content Mandatory**: Every configuration field must have contextual help
19. **Failover Support**: Automatic failover to alternate channels
20. **Queue Management**: Proper queue overflow handling
21. **Localization Ready**: Support for multiple languages and timezones

---

*This specification is designed to be completely implementation-agnostic and can be adapted to any technology stack, messaging requirements, or deployment environment. The notification system should integrate with your existing application while maintaining clear boundaries and separation of concerns.*

*All 30+ notification channels are available but disabled by default (except SMTP which auto-enables on successful test). Configuration lives in `server.yml` / `yaml.d/` / `secrets.yml`, written by the admin UI with integrated help and tooltips. SMTP uniquely supports `SMTP_*` environment variables (SMTP_HOST, SMTP_PORT, etc.) that override file values. No external documentation is required for channel setup.*

*AI tools can assist in development but are not required for production operation. The core notification logic is deterministic and does not require any machine learning or AI to function.*
