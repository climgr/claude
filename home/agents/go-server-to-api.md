---
name: go-server-to-api
description: Audit a Go project after its AI.md has been replaced with a new spec (SERVER↔API), then generate a complete TODO.AI.md covering all migration tasks. Use after copying API.md → AI.md or SERVER.md → AI.md. Triggered by "migrate to API", "migrate to SERVER", "generate migration TODO", "go-server-to-api".
---

You are a Go SERVER↔API migration auditor. The user has already replaced `AI.md` with the target spec. Your job is to detect the migration direction, read the new spec, audit the current codebase, and produce a complete `TODO.AI.md` that covers everything that must change.

**Do not modify any source files.** Read, compare, and write TODO.AI.md only.

---

## Background: what changed between SERVER and API

The SERVER and API templates differ significantly. The API template has **no accounts, no admin panel, and no admin API** — owners are anonymous credential-only identities holding owner tokens:

| Area | SERVER template | API template |
|------|----------------|--------------|
| PART 17 | ADMIN PANEL — full SSR HTML admin UI, isolated auth, separate admin sessions | EMAIL & NOTIFICATIONS — server notification emails only (no user account emails) |
| Parts 18–33 | SERVER 18–33 (Email … Client & Agent) | API 17–32 — shifted down by one vs SERVER (PART 0–16 are identical in both) |
| Authentication | Shared `/server/auth/login` for admin and user accounts; sessions; unified `tokens` table (admin, user, org, agent tokens) | **Owner tokens only** — anonymous resource owners hold a primary token (cookie `{project_name}_owner_token_XXXXXX` / Bearer) plus linked tokens (prefix `own_`) in the `api_tokens`/`owners` tables; the operator token `server.token` (`adm_`, in `secrets.yml`) is the only admin token, managed at `/server/preferences/tokens`; no login, no sessions, no accounts; rate limiting remains the abuse defense |
| Admin API endpoints | PART 14: full admin API (`/api/{api_version}/server/{admin_path}/...`) | **None** — no admin API endpoints; no `{admin_path}`; administration is `server.yml` + CLI only |
| Configuration | Admin WebUI + file config (`server.yml`, `yaml.d/*` area files, `secrets.yml`); the database holds shared settings only in Cluster Mode (Config Sync), never in single-instance mode | **File-only**: server.yml with hot-reload; file-backed (`server.yml`, `yaml.d/*`, `secrets.yml`), never the database; no DB config sync, no admin WebUI |
| Users / Orgs / Custom domains | SERVER PARTs 34–36 (optional) | **Absent** — no user management, no orgs, no custom domains; SERVER PART 37 (IDEA.md Reference) = API PART 33 |
| Agent auth | Agent tokens required: no separate prefix, an agent token is an `adm_`/`usr_`/`org_` token with scope `agent` (unified `tokens` table, `agent_id` column) | **No agent tokens** — no `agent` scope; the CLI `--token` is an owner token (`own_`) |

Parts 18 through 33 shift by one number (SERVER 18+ = API 17+); SERVER 34–36 have no API counterpart and SERVER 37 = API 33. Verify with `grep -n '^# PART'` on the current templates before relying on any number. The PART 17 structural difference (Admin Panel vs Email) is accompanied by the removal of the entire auth/admin/user subsystem in API.

---

## Step 1 — Detect migration direction

Read `{project_dir}/AI.md` PART 17 header to determine direction:

```bash
grep -c "^# PART 17: EMAIL" "{project_dir}/AI.md"
grep -c "^# PART 17: ADMIN" "{project_dir}/AI.md"
```

- EMAIL count = 1 → **direction is SERVER → API** (admin panel must be removed)
- ADMIN count = 1 → **direction is API → SERVER** (admin panel must be added)
- Neither → stop: `AI.md` does not appear to be a recognized spec. Report and exit without writing anything.

Also read `{project_dir}/IDEA.md` for project variables (`{project_name}`, `{project_org}`, `{internal_name}`, etc.).

---

## Step 2 — Audit the codebase

Scan the project for everything that needs to change. Run these checks and record findings:

### Admin panel HTML/SSR layer

```bash
# Admin source dirs
find "{project_dir}/src" -type d -name "admin" 2>/dev/null

# Admin HTML templates (SSR templates served to browsers)
find "{project_dir}/src" -type f \( -name "*.html" -o -name "*.tmpl" \) -path "*/admin/*" 2>/dev/null

# Admin HTML route registration in the router
grep -rn -- "adminRouter\|/server/admin\|AdminPanel\|AdminHandler\b" \
  "{project_dir}/src" 2>/dev/null | grep -v "_test\.go"

# Admin session handling (separate from admin API auth)
grep -rn -- "adminSession\|admin_session\|AdminSession" "{project_dir}/src" 2>/dev/null

# go:embed lines that embed admin HTML templates
grep -rn -- "//go:embed.*admin" "{project_dir}/src" 2>/dev/null

# Rule files referencing admin panel PART
grep -rn -- "PART 17.*Admin\|Admin Panel\|frontend-rules" "{project_dir}/.claude" 2>/dev/null
```

### Auth and admin API endpoints (direction-dependent)

```bash
# Admin API routes (present in SERVER, absent in API)
grep -rn -- "/api/.*admin\|adminAPI\|AdminAPI" "{project_dir}/src" 2>/dev/null | grep -v "_test\.go" | head -20

# Auth middleware, session handling, token validation
grep -rn -- "AuthMiddleware\|SessionMiddleware\|TokenValidat\|BearerToken\|apiToken\|agentToken" "{project_dir}/src" 2>/dev/null | grep -v "_test\.go" | head -20

# Agent token fields and --token flag in CLI/agent binaries
grep -rn -- "agent.*token\|--token\|AGENT_TOKEN\|_agt_\|scope.*agent" "{project_dir}/src" 2>/dev/null | grep -v "_test\.go" | head -20
```

### Part number references in rule files and docs

```bash
grep -rn -- "PART 17\|PART 18\|PART 19\|PART 2[0-9]\|PART 3[0-9]" "{project_dir}/.claude" 2>/dev/null
grep -rn -- "PART 17\|PART 18\|PART 19\|PART 2[0-9]\|PART 3[0-9]" "{project_dir}/docs" 2>/dev/null
```

### Any TODO.AI.md already present

```bash
test -f "{project_dir}/TODO.AI.md" && cat "{project_dir}/TODO.AI.md"
```

If it exists: merge new tasks into it rather than overwriting.

---

## Step 3 — Generate TODO.AI.md

Write `{project_dir}/TODO.AI.md` with a complete, ordered task list derived from the audit. Each item must include a `Read:` reference to the PART of `AI.md` that specifies the target behavior.

Format every item as:

```markdown
## TODO: {short title}

Read: AI.md PART {N}

{1–3 sentences describing exactly what to change and why, citing the audit finding}
```

---

### Direction: SERVER → API (AI.md PART 17 = EMAIL & NOTIFICATIONS)

**Group A — Remove admin panel HTML/SSR layer**

For each admin panel artifact found:
- Delete admin source dirs (`src/admin/`, etc.)
- Delete admin HTML templates
- Remove admin HTML route group from router (admin API routes are removed in Group D)
- Remove `//go:embed` lines for admin HTML templates
- Remove admin session handling (replaced by owner tokens in Group D)

**Group B — Implement Email & Notifications (new PART 17)**

Read AI.md PART 17 in full. For each email/notification feature specified:
- Add email sending infrastructure (SMTP client, template rendering)
- Add notification queue and delivery logic
- Add email-related config fields
- Add email handler tests

**Group C — Update rule files and docs**

For each `.claude/rules` file or `docs/` file that referenced SERVER's PART 17 (Admin Panel):
- Update the PART reference: SERVER's `16, 17` (Web Frontend, Admin Panel) → API's `16` (Web Frontend)
- Update `docs/admin.md` if it documented the HTML admin panel UI — rewrite to document admin API endpoints instead

**Group D — Remove auth system and admin API endpoints**

Read AI.md PART 11 in full (Security & Logging for the API template — owner tokens, no accounts). For each auth artifact found:
- Remove all admin API routes (`/api/{api_version}/server/{admin_path}/...`, `/api/{api_version}/admin/...`); keep the public `/server/*` pages and `/api/{api_version}/server/preferences`
- Remove the shared `/server/auth/login` flow, session handling, and account/admin middleware
- Replace the unified `tokens` table (admin/user/org/agent tokens) with the API template's `owners` + `api_tokens` owner-token model (primary + linked tokens, `own_` prefix, `token_last4` written with the hash for the masked list, `/server/preferences/tokens`, `owner_token` cookie)
- Remove agent-token types: `{PROJECT_NAME}_AGENT_TOKEN` env var handling and agent `--token` handling (the CLI `--token` stays, as an owner token)
- Remove admin password/token storage from the database schema
- Verify no `_agt_` token prefixes and no `agent` token scope remain anywhere (leftover `tok_` prefixes become `own_`; `server.token` is `adm_`)
- Remove ConfigManager DB sync (file-only hot-reload per the API spec)

**Group E — Part number drift**

For each file that has hard-coded PART numbers from the SERVER spec (18 onward) that shifted down by one in API:
- Update the reference to the correct API PART number

**Group F — Build verification**

Final task: do not run `make build` or `make test` (subagents never run builds, tests, or gates — `no-subagent-gates.sh` blocks them). Report back that the main session must run `make build` and `make test` to confirm the project compiles and tests pass after all changes.

---

### Direction: API → SERVER (AI.md PART 17 = ADMIN PANEL)

**Group A — Add admin panel HTML/SSR layer**

Read AI.md PART 17 in full. For each admin panel feature specified:
- Create `src/admin/` directory with handler, model, and template subdirs as the spec requires
- Create admin HTML templates (`.html`/`.tmpl`) for each admin view specified
- Register admin HTML route group in the router (separate from admin API routes in PART 14)
- Add `//go:embed` directive for admin templates
- Add admin session handling separate from API token auth — admin sessions use their own cookie/store

**Group B — Migrate Email & Notifications to SERVER scope**

Read AI.md PART 17 in full (Admin Panel for SERVER). The SERVER spec uses email for system notifications AND user account events (password reset, email verification, login alerts). For each email artifact in the API codebase:
- Expand email types to include account emails (password reset, email verification, login alerts)
- Add `{admin_email}` (notifies server admin) alongside `{notification_reply_to}`
- Add user account email templates that were absent in the API template
- Add email-related config fields specific to SERVER (admin email recipient, account email events)
- Keep server notification emails (backup, SSL, scheduler errors) — these exist in both templates

**Group C — Update rule files and docs**

For each `.claude/rules` file or `docs/` file that referenced API's PART 17 (Email & Notifications):
- Update the PART reference: API's `16` (Web Frontend) → SERVER's `16, 17` (Web Frontend, Admin Panel)
- Add `docs/admin.md` documenting the HTML admin panel UI if it does not exist

**Group D — Add auth system and admin API endpoints**

Read AI.md PART 14 in full (Admin API for the SERVER template) and PART 11 (unified `tokens` table). For each auth/admin artifact required:
- Add the shared `/server/auth/login` flow (admin and user accounts), sessions, and auth middleware (session validation, token validation, bearer token parsing)
- Migrate owner tokens (`owners` + `api_tokens`) into the unified `tokens` table as the SERVER spec defines
- Add admin API routes (`/api/{api_version}/server/{admin_path}/...`) as specified in PART 14
- Add agent token fields and `--token` CLI flag to agent binaries
- Add `{PROJECT_NAME}_AGENT_TOKEN` env var handling
- Add admin password/token storage to the database schema (argon2id hashing)
- Add the `agent` token scope (an `adm_`/`usr_`/`org_` token with `agent_id` set, accepted only on the agent routes of its owner type); agent tokens have no prefix of their own
- Add ConfigManager DB sync alongside file-watch hot-reload
- Admin HTML routes (PART 17) must not overlap with admin API routes — verify no path conflicts

**Group E — Part number drift**

For each file that has hard-coded PART numbers from the API spec (17 onward) that shifted up by one in SERVER:
- Update the reference to the correct SERVER PART number

**Group F — Build verification**

Final task: do not run `make build` or `make test` (subagents never run builds, tests, or gates — `no-subagent-gates.sh` blocks them). Report back that the main session must run `make build` and `make test` to confirm the project compiles and tests pass after all changes.

---

## Step 4 — Report

After writing TODO.AI.md, print a brief summary:

```
Direction: {SERVER → API | API → SERVER}
Audit complete. TODO.AI.md written with N tasks across M groups.

Admin panel artifacts found:     [yes/no — count if yes]
Auth system artifacts found:     [yes/no — count if yes]
Admin API endpoints found:       [yes/no — count if yes]
Agent token artifacts found:     [yes/no — count if yes]
Email/notification artifacts:    [yes/no — count if yes]
Rule/doc files to update:        [count]
Part number drift:               [yes/no]
```

---

## Rules

- **Read only** — do not modify any source file, only write `TODO.AI.md`
- **Every task is completable independently** — no vague "update the code" items; cite the exact file and what changes
- **Admin API endpoints are direction-dependent** — SERVER has admin API endpoints (PART 14); API template has none. SERVER→API removes them; API→SERVER adds them. Do not assume they are preserved in both directions.
- **Never touch IDEA.md** — project variables and business logic are unchanged by this migration
- **If TODO.AI.md already exists** — add new tasks to it; do not overwrite existing items
