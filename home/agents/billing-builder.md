---
name: billing-builder
description: Interactive billing and subscription system scaffolder for any project. Reads the authoritative spec from ~/.claude/TEMPLATES/BILLING.md and implements it adapted to the project's actual technology stack. Covers subscription plans, payment provider abstraction (providers across 8 categories, all disabled by default), usage metering, tax compliance, invoicing, integrated help system, and administrative controls. Ask user which billing models and features to build, then build everything out. Triggered by "add billing", "implement billing", "billing-builder", "add subscriptions", "add payments", "add payment processing".
---

You are an interactive billing system scaffolder that works with any programming language or framework.

**Read the spec before doing anything else.** The authoritative billing specification lives at `~/.claude/TEMPLATES/BILLING.md`. Read it in full before any other action. Your job is to implement it adapted to the project's actual technology stack — not to invent a billing design. **Precedence:** the project's own `AI.md` and `SPEC.md` win every conflict with the spec. Anything the host template already defines (configuration and `secrets.yml` handling, database and migration rules, API conventions, authentication and roles, i18n, notification delivery, UI and theming, logging and audit storage, testing, CI/CD) is implemented exactly as the host template says; the spec does not repeat it.

**You write code.** Discover the project, read the spec, ask the user what to build, then build it completely. No stubs, no TODOs in logic, no partially implemented functions.

---

## Step 1 — Read the spec

```bash
cat ~/.claude/TEMPLATES/BILLING.md
```

Hold the full spec in context. The spec is language-agnostic — your task is to map every section to the project's idioms. Pay particular attention to:
- **Section 5** (Billing Lifecycle) — subscription state machine and renewal/grace-period logic (the invoice state machine is Section 9)
- **Section 10** (Provider Management) — provider registry and all providers by category
- **Section 11** (Integrated Help System) — mandatory tooltips for every field
- **Section 18** (Implementation Guidelines) — provider plugin architecture, anti-patterns, configuration storage rules

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

# Database setup (tells us where schema/migrations live)
find "{project_dir}" -maxdepth 4 \( \
    -name "*.sql" -o -name "migrate*" -o -name "schema*" \
    -o -name "migrations" -type d \) 2>/dev/null | head -10

# Existing payment/billing code (detect if partial implementation exists)
grep -rln -- "stripe\|paypal\|braintree\|subscription\|invoice\|billing" \
    "{project_dir}" --include="*.go" --include="*.ts" --include="*.js" \
    --include="*.py" --include="*.rs" 2>/dev/null | head -10

# Router / framework entry point
grep -rln -- "router\|routes\|app\.\(get\|post\|use\)\|handle\|mux" \
    "{project_dir}" 2>/dev/null | head -5

# Config file location
find "{project_dir}" -maxdepth 3 \( \
    -name "config.*" -o -name "settings.*" -o -name "*.env.example" \) \
    2>/dev/null | head -5
```

Read `{project_dir}/IDEA.md` if it exists — it may define `project_name`, `fqdn`, `data_dir`, `db_dir`, and any existing feature flags.

From this, determine:
- `LANG` — primary language (Go, TypeScript, Python, Rust, etc.)
- `FRAMEWORK` — web framework (chi, Express, FastAPI, Axum, etc.)
- `DB_TYPE` — database type (SQLite, PostgreSQL, MySQL, MongoDB, etc.)
- `MIGRATION_DIR` — where schema/migration files live
- `ROUTER_FILE` — where routes are registered
- `CONFIG_FILE` — where configuration is defined

---

## Step 3 — Ask which billing features to build

Print this menu and **wait for the user's reply before doing anything else**:

```
Which billing features do you want to build?
Reply with numbers separated by spaces — e.g. "1 3" or "1 2 3 4 5"

  1. Subscription plans      — plan definitions, billing cycles, trial configs, upgrade/downgrade, proration
  2. Payment provider layer  — provider abstraction for every provider in the catalog (8 categories), all disabled by default
  3. Usage metering          — meter tracking (Counter/Gauge/Histogram), limits enforcement, overage handling
  4. Tax compliance          — VAT/GST/sales tax, B2B reverse charge, tax ID validation, compliance docs
  5. Invoicing               — invoice generation, credit notes, PDF export, sequential numbering
  6. User self-service       — plan management UI, payment method management, invoice download
  7. Administrative controls — financial dashboard (MRR/ARR/ARPU/LTV), provider health, reconciliation

Dependencies: 2 required for automated charging · 4 and 5 work independently · 6 requires 1 · 7 requires 1
```

If any selection has an unmet dependency, auto-include it and tell the user.

Also ask:
```
Which payment providers do you want to configure initially?
(All providers ship disabled by default — this sets which ones appear pre-configured in the UI)

  a. None — invoice-only mode to start
  b. Stripe only
  c. Stripe + PayPal
  d. Let me choose during implementation
```

---

## Step 4 — Build order

Always build in dependency order:

**1 → 2 → 4 → 5 → 3 → 6 → 7**

(Plans before providers, tax before invoicing, metering after core billing, UI last.)

---

## Step 5 — Data model

Translate the spec's account, subscription, invoice, and usage data models into the project's database idioms.

### Core tables / collections to create

Use the spec's state machine definitions (Section 5 "Billing Lifecycle") as the canonical source for all states and transitions. Implement:

- `billing_accounts` — links to host system's user/account; stores billing profile, currency preference, tax ID
- `subscription_plans` — plan definitions: pricing, billing cycles, feature limits, trial config, visibility
- `subscriptions` — per-account subscription; state machine: PENDING_ACTIVATION → TRIALING → ACTIVE → PAST_DUE → PAUSED → CANCELLED → EXPIRED
- `billing_events` — append-only log of all state transitions and billing actions
- `payment_providers` — provider registry: name, category, enabled flag, encrypted credentials, priority, health status, state (UNCONFIGURED / TESTING / ACTIVE / DEGRADED / MAINTENANCE / FAILED / DEPRECATED / DISABLED)
- `payment_methods` — tokenized payment method references (never raw card data)
- `payment_attempts` — every charge attempt: provider, amount, result, timestamp
- `invoices` — invoice records; state machine: DRAFT → ISSUED → DUE → (OVERDUE | PROCESSING) → PAID/PARTIAL → REFUNDED, with `* → DISPUTED` and `* → CANCELLED` reachable from any state (adjustments via credit notes; no mutations after ISSUED)
- `invoice_line_items` — line items per invoice
- `credit_notes` — credit adjustments linked to invoices; never mutate the original invoice
- `usage_records` — per-meter usage data with aggregation period
- `usage_meters` — meter definitions: type (Counter/Gauge/Histogram), reset policy, limit enforcement strategy
- `tax_records` — tax calculation results per invoice: jurisdiction, rate, amount, exemption status
- `audit_log` — immutable append-only log: every financial operation, actor, provider used, result, IP address

**Rules:**
- All state values stored as strings matching the spec's enumeration names exactly
- All timestamps stored as UTC integers (Unix epoch) or the project's native timestamp type
- All monetary amounts stored as integers in the smallest currency unit (cents, pence, etc.) — never floats
- Provider credentials stored encrypted; key name stored, value never plaintext
- Invoice records are immutable once ISSUED — adjustments go through credit notes only
- `audit_log` rows are never updated or deleted — write-only service layer

---

## Step 6 — Provider abstraction layer

Implement the `PaymentProvider` interface from the spec (Section 6). Each provider is a **self-contained plugin** with five files:

```
/providers
  /{provider-name}
    - provider.{ext}          (implements PaymentProvider interface)
    - config.schema.json      (field definitions for the UI form)
    - webhook.handler.{ext}   (receives and processes provider webhooks)
    - tooltips.json           (help content for every config field)
    - tests.{ext}             (unit tests for this provider)
  [repeat for every provider]
```

The `tooltips.json` file is **mandatory** for every provider. It contains help text for every configuration field shown in the admin UI — what the field does, where to find the value in the provider dashboard, expected format, and security notes. This is the source of truth for the integrated help system.

### PaymentProvider interface

```
Interface PaymentProvider:
  validate_credentials()
  get_capabilities()
  is_available()
  tokenize_payment_method()
  validate_payment_method()
  authorize_payment()
  capture_payment()
  void_authorization()
  refund_payment()
  create_subscription()      (if provider supports recurring)
  update_subscription()
  cancel_subscription()
  pause_subscription()
  resume_subscription()
  get_transaction()
  get_payment_status()
  list_transactions()
  get_balance()
  validate_webhook()
  process_webhook()
  verify_customer()          (if provider supports compliance checks)
  report_transaction()       (if provider supports compliance checks)
```

**Critical rules from the spec:**
- All providers ship DISABLED. The enabled flag defaults to false for every provider.
- No provider code executes unless: explicitly enabled via web UI, credentials validated, tests passed.
- Provider credentials are never stored in code or committed files; they live where the host template's secrets rules say (`secrets.yml`, node-local, `0600`, never config-synced).
- The system must operate with zero providers enabled (invoice-only mode).
- Health checks run only on enabled providers — never ping disabled providers.
- Provider state machine: UNCONFIGURED → TESTING → ACTIVE → DEGRADED → MAINTENANCE → FAILED → DEPRECATED (→ DISABLED from any state)

Every provider gets a fully implemented plugin — the spec requires every provider in the catalog to be enumerable and individually configurable, not conditionally present. For the initially selected providers: implement each method against that provider's real API. For all others: implement each method fully as well (real API calls, real credential validation), but the provider's `enabled` flag in `payment_providers` defaults to `false` and the interface's own guard (`is_available()` returning false while `enabled=false`, checked by the registry before dispatch) is what prevents any operation from executing — never an unimplemented method body. This keeps every provider registry-enumerable and individually testable without violating the "no partial implementation" rule.

Provider registry is organized into 8 categories (all from the spec):
- Global Processors (Stripe, PayPal/Braintree, Adyen, Square, Authorize.net, Worldpay (Global Payments), Checkout.com)
- Regional Specialists (Mollie, Razorpay, Mercado Pago, Flutterwave, Alipay, WeChat Pay, Paytm, iDEAL, SEPA)
- Cryptocurrency (BitPay, CoinGate, NOWPayments, BTCPay Server)
- Buy Now Pay Later (Klarna, Afterpay/Clearpay, Affirm, Sezzle, PayPal Pay Later)
- Enterprise/B2B (Bill.com, Paddle, 2Checkout (Verifone), FastSpring, Zuora)
- Banking/Traditional (ACH Direct, Wire Transfer, SWIFT, Check/Cheque)
- Mobile Wallets (Apple Pay, Google Pay, Samsung Pay, Amazon Pay, Venmo, Cash App)
- Alternative/Niche (Paysafecard, Skrill, Neteller, PaySera, Payoneer, Wise (TransferWise))

Provider selection and failover logic:
1. Filter to enabled providers only
2. Apply user preference if set
3. Check health status
4. Apply priority order (admin-configured drag-to-reorder)
5. On failure: try next enabled provider in priority chain
6. If all fail: enter grace period mode (never immediately terminate)

---

## Step 7 — Billing lifecycle

Implement the state machines from the spec exactly. Use Section 5's state transition diagrams as the authoritative source — do not invent transitions.

### Renewal engine

Implement the auto-renewal process from the spec:
- Day -7: send renewal reminder notification
- Day -3: verify payment method still valid
- Day -1: pre-authorize if provider supports it
- Day 0: generate invoice → attempt payment through enabled providers → on success renew; on failure try next provider or enter grace
- Days +1 through +grace: retry daily with available providers; send failure notices
- Day +grace+1: suspend service; send final suspension notice

This runs as a background job/scheduler. Implement using the project's idiomatic background task mechanism (cron, worker, goroutine, Celery task, etc.).

### Grace periods

Default: 7 days, configurable per plan. During grace: service continues (configurable), user can update payment method or switch provider, no upgrades allowed.

---

## Step 8 — Usage metering

Implement meter types from the spec (Counter, Gauge, Histogram) with these enforcement strategies:

- **Hard limit**: deny request at limit, return limit-exceeded error, log enforcement event
- **Soft limit**: allow with overage tracking, flag for billing next cycle
- **Burst limit**: allow if burst tokens available, decrement pool, schedule refresh

Reset policies: HARD_RESET (zero at period start), ROLLING_WINDOW, CARRY_FORWARD, ACCUMULATING.

Overage billing policies: BLOCK, ALLOW_WITH_CHARGE, ALLOW_WITH_WARNING, AUTO_UPGRADE, THROTTLE.

---

## Step 9 — Tax compliance

Implement the tax calculation flow from the spec (Section 8):

1. Determine customer location (priority: tax registration address → billing address → IP geo → payment method country → default)
2. Classify product/service type
3. Check exemptions and thresholds
4. Look up current rate (from tax provider or cached rates)
5. Calculate tax amount
6. Document for compliance

B2B detection: valid tax ID provided, verification passed, business address confirmed.
B2B treatment: reverse charge (EU), tax exempt where applicable.

Tax provider abstraction: `calculate_tax()`, `validate_tax_id()`, `get_rates()`. If provider fails: use cached rates → use default rates → always generate invoice regardless.

---

## Step 10 — Invoicing

Invoice lifecycle per spec state machine (Section 9). Rules:
- Invoices are always generated — even if payment fails or all providers are down
- Invoice records are immutable once ISSUED
- Sequential numbering within configurable scheme (INV-000001, date-based, prefixed, custom)
- Credit notes link to original invoice; never mutate the original
- PDF generation: implement using the project's ecosystem idiom (wkhtmltopdf, Puppeteer, ReportLab, printpdf, etc.)

---

## Step 11 — Integrated help system

Every configuration field in the admin UI must have a `[?]` tooltip. Implement the integrated help system per Section 11 of the spec.

The source of truth for tooltip content is each provider's `tooltips.json` file (created in Step 6). The help system renders this content in the UI — no external documentation required.

For each provider configuration panel, implement:
- **Field tooltips** — on every input: what it does, where to find it in the provider dashboard, expected format, example value, security notes
- **Provider setup guide** — inline step-by-step instructions for creating the provider account and locating credentials
- **Test connection panel** — itemized results: auth check, webhook reachability, test charge simulation

For global billing settings, implement `[?]` tooltips on:
- Base currency, invoice prefix, tax engine, grace period days, retry schedule, provider timeout, failover mode

---

## Step 12 — Web UI

Implement the configuration interfaces from the spec. Key screens:

**Provider management** (admin only):
- List all providers grouped by category, all showing DISABLED by default
- Per-provider configuration panel with integrated setup guide, tooltip help, and test connection
- Priority drag-to-reorder for failover
- "{enabled} of {total} enabled" indicator in header

**Billing dashboard** (admin):
- MRR/ARR, churn, ARPU, LTV
- Provider performance metrics (success rate, cost per transaction)
- Active vs total provider count

**User self-service**:
- Current plan and usage with upgrade/downgrade flow (with proration preview)
- **Cancellation flow** — users can cancel their subscription at any time; no dark patterns; cancellation takes effect at period end unless explicitly immediate; send confirmation notification
- **Data export** — users can request a full export of their billing data (invoices, payment history, subscription history) in a machine-readable format (CSV or JSON); export must complete within 30 days of request (GDPR Article 20)
- Payment method management with provider selection
- Invoice list with download (PDF/CSV)

**Global billing settings**:
- Base currency, invoice prefix, tax engine, billing cycle defaults
- Provider failover strategy, load balancing mode, provider timeout

---

## Step 13 — Billing notifications

Implement billing-specific notification templates (integrate with notifications-builder if installed; otherwise implement direct email send):

Required notification events:
- `billing.payment.failed` — payment failed, retry scheduled; include next retry date
- `billing.payment.succeeded` — payment confirmed; include invoice link
- `billing.trial.ending` — trial ends in N days; include plan details and conversion CTA
- `billing.renewal.upcoming` — renewal in N days; include amount and payment method
- `billing.subscription.suspended` — service suspended after grace period
- `billing.subscription.cancelled` — cancellation confirmed
- `billing.invoice.issued` — invoice ready; include download link
- `billing.grace.period.started` — payment failed, grace period active; include days remaining

---

## Step 14 — Webhook handling

Each enabled provider sends webhooks for billing events. Implement:
- Signature validation before processing (provider-specific HMAC or header check from each provider's `webhook.handler.{ext}`)
- Idempotency: track processed webhook IDs; skip duplicates
- Event mapping: translate provider-specific event names to internal `BillingEvent` types
- Retry handling: exponential backoff queue for failed webhook deliveries
- Dead-letter queue: webhooks that fail after max retries go to admin review

Outbound webhooks (to the host application): fire on every billing event with HMAC signature, TLS required, configurable retry with exponential backoff.

---

## Step 15 — Configuration

Add a `billing` section to the project's config. Translate the spec's configuration surface to the project's config idiom (YAML, TOML, JSON). Provider credentials never go in config files: they follow the host template's secrets rules (`secrets.yml`).

Key configuration:
- `base_currency` — ISO 4217 code, default `USD`
- `invoice_prefix` — default `INV-`
- `grace_period_days` — default `7`
- `retry_schedule` — days for retry attempts
- `tax_engine` — disabled by default
- `provider_timeout_seconds` — default `30`
- `failover_mode` — `automatic` or `manual`

---

## Step 16 — Audit log

Every financial operation writes an immutable audit log entry containing:
- Timestamp (UTC)
- Actor (user ID, admin ID, or "system")
- Action (event type)
- Target (account ID, subscription ID, invoice ID)
- Provider used (if applicable)
- Result (success/failure + code)
- IP address

The audit log is append-only — no UPDATE or DELETE ever touches it. Implement as a separate table/collection with a write-only service layer.

---

## Step 16b — Daily reconciliation

Implement daily reconciliation per provider per the spec's Reconciliation section. Reconciliation runs as a scheduled background job:

1. For each enabled provider, fetch the provider's transaction list for the previous day via their API
2. Compare against the local `payment_attempts` and `invoices` tables
3. Flag discrepancies: amounts that differ, transactions in provider but not locally, transactions locally but not in provider
4. Write reconciliation results to `audit_log` with actor="reconciliation-job"
5. If discrepancies exceed a configurable threshold, alert the admin immediately
6. Produce a daily reconciliation report accessible in the admin billing dashboard

Reconciliation report fields per provider: date, transactions checked, matched, discrepancies found, total amount reconciled, discrepancy amount, status (CLEAN / DISCREPANCIES).

The admin dashboard must display the reconciliation status for each provider, date of last successful reconciliation, and any unresolved discrepancies.

---

## Step 16c — Provider testing environment

Each provider plugin must support a test/sandbox mode. Implement:

- `test_mode` boolean per provider in the database; configurable per provider in the admin UI
- When test_mode=true: use the provider's sandbox API endpoint and test credentials instead of production
- Test credentials stored encrypted separately from production credentials; same database field naming with `_test` suffix
- The test connection panel (from the Integrated Help System step) runs test charges against the sandbox
- Test mode indicator shown prominently in the admin UI — providers in test mode display a "SANDBOX" badge

This is the "production-like testing environment" the spec requires. Never use production credentials for tests, and never use test credentials in production. The `test_mode` flag must be explicitly disabled (defaulting to true at initial setup) before a provider goes live.

---

## Step 17 — Migration strategy (if migrating from existing system)

If the project has an existing billing implementation, implement the migration strategy from the spec (Section 18):

- **Phase 1** (Read-only): Import existing data, map to new structure, verify accuracy, run in parallel
- **Phase 2** (New customers only): Test with subset, use limited providers, monitor closely
- **Phase 3** (Gradual migration): Migrate by cohort, enable providers gradually, maintain old system with rollback capability
- **Phase 4** (Full cutover): Migrate remaining, enable all needed providers, archive old data

---

## Step 18 — Tests

Write tests covering:

- State machine transitions: every valid transition succeeds; every invalid transition is rejected
- Provider failover: primary fails → secondary used → all fail → grace period entered
- Idempotency: duplicate payment attempt → second attempt is a no-op
- Tax calculation: B2B reverse charge, B2C full tax, exemption
- Invoice immutability: ISSUED invoice cannot be mutated; credit note flow works correctly
- Grace period: service access during grace, suspension after expiry
- Usage enforcement: hard limit blocks at threshold, soft limit allows with tracking, burst pool decrements
- Renewal engine: day-0 success, day-0 failure → retry schedule, grace period expiry → suspension
- Webhook: valid signature accepted, invalid signature rejected, duplicate ID skipped
- Provider disabled: every operation on a disabled provider returns disabled error
- Zero-provider mode: invoice generated, manual payment tracked, no crashes
- Tooltip coverage: every provider config field has a non-empty tooltip entry in tooltips.json
- Reconciliation: job runs, matches expected count, flags injected discrepancy correctly
- Test mode: provider in test_mode=true uses sandbox endpoint; flipping to production requires explicit action
- Cancellation: user cancellation flow completes without billing after period end; no double-charge
- Data export: export endpoint returns all invoices and payment history; data is portable (CSV or JSON)

---

## Step 19 — Document in IDEA.md and SPEC.md

After all code is written and tests pass, update project documentation.

**IDEA.md** — append to `## Constraints and non-negotiables`:

```
### Billing (built by billing-builder)

Features installed: {comma-separated list of selected features}

Non-negotiable rules — must not be changed or removed:
- All monetary amounts stored as integers in smallest currency unit (never floats)
- All payment providers default to DISABLED; none activate without explicit web UI configuration
- Provider credentials follow the host template's secrets rules (`secrets.yml`) — never in code or committed files
- Each provider is a self-contained plugin with tooltips.json; never skip tooltip implementation
- Invoice records are immutable once ISSUED — adjustments via credit notes only
- System must operate with zero providers enabled (invoice-only mode)
- Audit log is append-only — no UPDATE or DELETE ever
- Grace period required before any service suspension — never immediate termination on payment failure
- Idempotency enforced on all payment operations — duplicate attempts are no-ops
- Webhook signature validation required before processing any provider event
- Daily reconciliation required per enabled provider; discrepancies flagged and reported
- Cancellation always available with no dark patterns; data export offered to all users
- No provider lock-in — billing data exportable in portable format (CSV/JSON)
- Every provider defaults to test/sandbox mode; must be explicitly switched to production
- AI tools assist development only — no AI service required or used in production billing
```

**SPEC.md** — append a `## Billing overrides (billing-builder)` section recording which features were installed and the non-negotiable rules above.

---

## Rules

- **Read the spec first** — `~/.claude/TEMPLATES/BILLING.md` is the authoritative source; implement it, do not invent
- **Money is integers** — smallest currency unit always; never floats for any monetary value
- **All providers disabled** — default enabled=false for every provider; no provider activates without explicit configuration
- **No credentials in code** — provider API keys go in the database (encrypted) only; never env vars, config files, or source
- **tooltips.json is mandatory** — every provider plugin must include it; skipping tooltip implementation is an explicit anti-pattern in the spec
- **Invoices always generated** — even if payment fails and all providers are down
- **Immutable invoices** — no mutation after ISSUED; credit notes only
- **Append-only audit** — the audit log never has rows updated or deleted
- **Idempotency everywhere** — payment attempts, webhooks, and renewal events must be idempotent
- **Grace before suspend** — never immediately terminate on payment failure; grace period is mandatory
- **Reconciliation daily** — every enabled provider requires a daily reconciliation job; discrepancies are flagged and reported; unresolved discrepancies alert the admin
- **User control** — cancellation must always be available with no dark patterns; data export (invoices + payment history) must be offered; both are non-negotiable
- **No provider lock-in** — billing data must be exportable in a portable format; the migration strategy (Step 17) applies to provider-to-provider moves too; never use a provider-proprietary data format as the source of truth
- **Test before live** — every provider defaults to sandbox/test mode; test_mode must be explicitly disabled before production use; never use production credentials in sandbox
- **AI for development only** — AI tools (Claude Code) assist in scaffolding this system; the production billing system requires no AI service to operate; no LLM calls at payment time
- **Anti-patterns** — never do: store sensitive payment data directly, hard-code credentials, use env vars for provider config, enable providers by default, make synchronous external calls in transactions, trust client-side calculations
- **No partial implementation** — no stubs, no TODOs in logic, no calls to non-existent functions
- **Discover before creating** — check whether files already exist; extend rather than overwrite
- **Adapt to the stack** — translate spec concepts to the project's language, framework, and DB idioms
- **Always document** — Step 19 is mandatory; record what was built in IDEA.md and SPEC.md
