# 🤖 climgr/claude

Global Claude Code configuration — agents, memory, hooks, and settings deployed to `~/.claude/` on every machine. One installer gets any machine to the same baseline.

> The `climgr` org is strictly for CLI tool configuration repos — mostly AI CLIs, but any CLI tool is in scope. It's unrelated to the `claudemgr` org, which holds only the `{lang|type}` template repos (`go`, `rust`, `android`, `docker`, `mgr`) this repo's agents consume — those stay in `claudemgr`.

## 📦 What's Included

| Path | Purpose |
|------|---------|
| `home/CLAUDE.md` | Global AI rules — always loaded at every session start |
| `home/settings.json` | Claude Code permissions, hook wiring, env (auto-compact threshold, forced subagent model inheritance), and behavior flags |
| `home/agents/` | Custom agent definitions |
| `home/skills/` | Skill definitions (`/{name}`) |
| `home/hooks/` | Hook scripts — gate destructive ops, enforce commit/test/lint discipline, guard project conventions |
| `home/scripts/` | Standalone scripts run by Claude Code itself, e.g. `statusline.sh` |
| `home/memory/` | Convention and standards files loaded on demand |
| `home/TEMPLATES/` | Authoritative feature specs (`BASE.md`, `BILLING.md`, `NOTIFICATIONS.md`, `SUPPORT.md`) |
| `install.sh` | Syncs `home/` → `~/.claude/` |

## 🚀 Install

> Clones this repo and copies all config to `~/.claude/`. Installs no plugins or MCP servers, and removes the `github`/`fetch` MCP servers and the LSP/`security-guidance` plugins earlier versions installed, if present. Safe to re-run — fully idempotent.
>
> 📄 [View the raw install script](https://raw.githubusercontent.com/climgr/claude/main/install.sh) before running.

```sh
curl -fsSL https://raw.githubusercontent.com/climgr/claude/main/install.sh | sh
```

### Prerequisites

| Tool | Required | Notes |
|------|----------|-------|
| `claude` | ✅ Yes | [Claude Code CLI](https://claude.ai/code) |
| `git` | ✅ Yes | For cloning and updating |

---

## 🤖 Agents

Agents are specialized sub-models invoked automatically based on what you ask, or explicitly with `@agent-name`. Each is tuned for a specific kind of task.

### 🏗️ Project Lifecycle

| Agent | When to use |
|-------|-------------|
| `bootstrap` | Start a new project from a spec file (`{project_dir}/AI.md`), or re-bootstrap after a spec change. Reads PART 0–6 of the spec and executes everything — directory layout, build system, config, metadata. Reconciles `TODO.AI.md` if it exists. |
| `spec-migrator` | Migrate a project with `SPEC.md`, a project-spec `CLAUDE.md`, or a sparse `AI.md` to the standard `AI.md` + `IDEA.md` + `CLAUDE.md` loader structure. Also runs a bootstrap wizard for projects with no spec files at all. |
| `go-server-to-api` | Audit a Go project after its AI.md has been replaced with a new spec (SERVER↔API), then generate a complete `TODO.AI.md` covering all migration tasks. |
| `planner` | Design an implementation plan before writing code. Use when a task has genuinely ambiguous requirements or needs architectural tradeoffs evaluated — not simply because it touches many files. Returns a step-by-step plan and flags risks. Does not write code. |
| `implement` | Read a project spec (`AI.md`/`SPEC.md`/`CLAUDE.md`) and implement everything it prescribes, in order, until nothing defined in the spec is left unbuilt. Ensures PART 0–6 scaffolding exists, then drives every feature PART to done, delegating auth/billing/notifications/support to their scoped builder agents. |
| `commit-prep` | Prepare a `COMMIT_MESS` file for the current git working tree without polluting the main conversation with raw diff output. |

### 🔍 Code Quality

| Agent | When to use |
|-------|-------------|
| `audit` | Full project health audit — security, code quality, logic correctness, documentation completeness, spec compliance. Fixes issues directly. Triggered by "audit", "check compliance", or "verify project". |
| `code-reviewer` | Review diffs, PRs, specific files, or functions before committing or merging. |
| `security-auditor` | Threat modeling, OWASP audits, secrets scanning, dependency CVEs, auth flows, and hardening reviews. Best run on a PR or feature before it ships. |
| `beta-tester` | Structured beta testing from a user perspective — exploratory testing, edge case discovery, UAT against specs. Use before a release or after a major feature lands. |
| `test-writer` | Write tests for existing code — unit, integration, table-driven, fuzz targets. |
| `designer` | Designer-level UI/UX implementation for web, desktop, mobile, and TUI. Use for new screens, component design, theme systems, layout, and accessibility audits. |

### 🔎 Research & Exploration

| Agent | When to use |
|-------|-------------|
| `architect` | System design, API design, data modeling, architectural tradeoffs. Use when designing a new system or reviewing an existing design for scalability and maintainability. |
| `debugger` | Root cause analysis for bugs, crashes, hangs, and unexpected behavior. Use when you have an error message, stack trace, or reproducible failure. |
| `researcher` | Multi-step research spanning multiple files or locations, or tasks requiring web research combined with code reading. |
| `explorer` | Fast read-only codebase search — find files by pattern, locate symbol definitions, grep for keywords. Specify breadth: "quick", "medium", or "very thorough". |

### 🛠️ Linting

| Agent | When to use |
|-------|-------------|
| `go-lint` | Lint Go projects for convention violations — CGO, binary naming, strip flags, Makefile pattern, CLI flags, NO_COLOR, logging. Run before committing any Go change. |
| `rust-lint` | Lint Rust projects — Cargo.toml release profile, binary naming, CLI flags, NO_COLOR, forbidden patterns. Run before committing any Rust change. |
| `script-lint` | Lint bash/sh scripts — UUOC, naming, version stamps, inline comments, line length, missing triple-sync. Run before committing any script change. |

### ⚙️ Infrastructure & Tooling

| Agent | When to use |
|-------|-------------|
| `devops` | Infrastructure, CI/CD, containers, orchestration — Dockerfile review, Kubernetes manifests, CI pipeline design, secrets management, deployment strategies. |
| `cicd-maintenance` | Handle Renovate dependency update PRs/MRs on GitHub/GitLab/Gitea/Forgejo; audit and fix CI workflow files; run SHA 3-point verification; merge clean PRs; update the SHA table. |
| `rpm-builder` | RPM spec file authoring and build workflow for CasjaysDev packages — own binaries, scripts, services, and third-party repackaging. Generates spec files, Docker build commands, signing steps, and `createrepo_c` invocations. |
| `doc-sync` | Sync the `__help()`, man page, and completions triple after a bash script changes. Also syncs `README.md` when feature or CLI changes warrant it. |
| `statusline-setup` | Configure the Claude Code status line — add, remove, or fix fields. |
| `claude-code-guide` | Answers questions about Claude Code CLI features, hooks, slash commands, MCP servers, settings, and the Claude API. Use when the question is about how Claude Code works, not about a project. |
| `general` | Catch-all for everyday tasks — writing, editing, research, coding — when no specialist agent fits. |

### 🏗️ Scaffolding

| Agent | When to use |
|-------|-------------|
| `billing-builder` | Interactive billing and subscription system scaffolder. Covers subscription plans, payment provider abstraction (47+ providers across 8 categories), usage metering, tax compliance, invoicing, and administrative controls. |
| `notifications-builder` | Interactive notification system scaffolder. Covers 30 channels across 7 categories, SMTP auto-enable behavior, channel plugin architecture, routing rules, user preferences, and administrative controls. |
| `support-builder` | Interactive customer support system scaffolder. Covers ticketing (9-state machine), live chat, knowledge base, deterministic bot automation, SLA management, canned responses, and agent workspace. |
| `go-auth-builder` | Interactive auth scaffolder for Go HTTP server projects. Covers admin auth, API tokens, user accounts, orgs/teams, custom domains, DB schemas, middleware, handlers, HTML templates, routes, and i18n. |
| `rust-auth-builder` | Interactive auth scaffolder for Rust Axum HTTP server projects. Covers admin auth, API tokens, user accounts, orgs/teams, custom domains, DB schemas, middleware, handlers, HTML templates, routes, and i18n. |
| `dockersrc-bootstrap` | Bootstrap or update a CasjaysDev Docker image repo (base/toolchain images, also `casjaysdevdocker` app repos). Regenerates `gen-dockerfile`-managed files after template changes, preserves hand-crafted content, audits for dead variable/function references. |
| `travis-migrator` | Read an existing `.travis.yml`/`.travis.yaml` and generate the equivalent workflow for the project's real CI/CD provider (GitHub Actions, GitLab CI, Gitea/Forgejo Actions, Jenkinsfile). Leaves the Travis file in place untouched. Handles a single project or a bulk sweep across `~/Projects/{provider}/*/*/`. |

---

## 🧩 Skills

Skills are invoked with `/{name}` or auto-triggered when the task matches. Defined in `home/skills/{name}/SKILL.md`.

| Skill | When to use |
|-------|-------------|
| `audit` | Comprehensive project health audit — security, code quality, logic correctness, documentation completeness, spec compliance. Fixes issues directly; tracks >5 issues in `AUDIT.AI.md`. |
| `bootstrap-script` | Bootstrap a new or existing script-only project — main script, `.editorconfig`, `.shellcheckrc`, and standard project files. No workflows, no toolchain, no Makefile. |
| `doc-sync` | Sync the `__help()`, man page, and completions triple after a bash script changes; also syncs `README.md` when warranted. |
| `go-lint` | Lint the current Go project for convention violations. |
| `review` | Review the current diff (staged + unstaged) or a specific file/function for correctness, security, reliability, and style. |
| `rpm-build` | Author an RPM spec file and run the full build workflow for a CasjaysDev package. |
| `rust-lint` | Lint the current Rust project for convention violations. |
| `script-lint` | Lint bash/sh scripts in the current project for convention violations. |
| `security-audit` | Security-focused review — threat modeling, OWASP audits, secrets scanning, dependency CVEs, auth flows, hardening. |
| `test-write` | Write tests for existing code — unit, integration, table-driven, fuzz targets. |

---

## 🪝 Hooks

Hook scripts in `home/hooks/` run synchronously before or after a matching tool call, wired in `home/settings.json`. `PreToolUse` hooks can block a call (exit `2`); `PostToolUse`/`SubagentStop` hooks are observers. Full behavioral detail for each is in `AI.md` Part 6 — this table is the quick index.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start.sh` | SessionStart | Injects project_dir + CLAUDE.md/AI.md/SPEC.md precedence context |
| `post-compact.sh` | SessionStart(compact) | Re-injects project-dir and global context after compaction |
| `drift-guard-read.sh` | PreToolUse Read+Bash | Blocks reading `~/.claude/` deployed copies when a `home/` source exists |
| `no-read-gitcommit.sh` | PreToolUse Read+Grep+Bash | Blocks reading the `gitcommit` script itself |
| `protect-host.sh` | PreToolUse Bash | Blocks destructive host commands (auth files, core binary dirs, wiping `/`/`$HOME`, `pkill`/`killall`, unscoped container sweeps) |
| `block-host-toolchain.sh` | PreToolUse Bash | Blocks direct host toolchain invocations, suggests the Docker equivalent |
| `enforce-docker-rm.sh` | PreToolUse Bash | Blocks `docker run` without `--rm`/`--name` and unnamed `incus launch`/`init` |
| `bound-shell-lifetime.sh` | PreToolUse Bash | Blocks unbounded shell lifetimes — unbounded poll loops, open-ended sleeps, `nohup`/`setsid`/`disown`, unbounded `tail -f`/`watch`, unmanaged `&` |
| `zone-git-commit-push.sh` | PreToolUse Bash | Blocks raw `git commit` and raw `git push` everywhere, no zone exception for either — commit signing and push must always go through `gitcommit`; a zone repo that must never publish keeps a `.no_push` file instead |
| `no-subagent-commit.sh` | PreToolUse Bash | Blocks `gitcommit`/`git commit`/`git push` when called from a subagent |
| `no-subagent-gates.sh` | PreToolUse Bash | Blocks `make` and test runners (`go test`, `cargo test`, `pytest`, `npm test`, and the same through `docker`/`podman`/`incus`) when called from a subagent; the main session runs the gates once |
| `no-force-push.sh` | PreToolUse Bash | Blocks all force-push forms everywhere, including inside the zone |
| `no-history-rewrite.sh` | PreToolUse Bash | Blocks `git clean -f*`, `rebase`, `branch -D`, `tag -d`, `filter-repo`/`filter-branch` everywhere |
| `no-destructive-bypass.sh` | PreToolUse Bash | Re-enforces the `git reset`/`dd`/`shred`/`mkfs*`/`wipefs` deny list against wrapper bypasses |
| `bash-content-scan.sh` | PreToolUse Bash | Runs the secrets/AI-attribution scans against heredoc and `echo`/`printf` redirect content |
| `enforce-gitcommit-shape.sh` | PreToolUse Bash | Blocks any `gitcommit` invocation that isn't exactly `--dir <path> all` or `push` |
| `enforce-test-lint-gate.sh` | PreToolUse Bash | Blocks `gitcommit` unless the test and lint gates ran and passed this session |
| `enforce-commit-mess-coverage.sh` | PreToolUse Bash | Blocks `gitcommit` when changed files have no matching bullet in `COMMIT_MESS` |
| `enforce-doc-sync.sh` | PreToolUse Bash | Blocks `gitcommit` unless `COMMIT_MESS` carries an explicit `IDEA.md`/`README.md` status line for whichever of those files exists at the target repo's root |
| `test-lint-mark.sh` | PostToolUse Bash | Records that a test/lint command exited 0 this session |
| `lint-agent-mark.sh` | SubagentStop | Records the lint gate satisfied when a lint subagent finishes clean |
| `validate-workflows.sh` | PreToolUse Bash | Blocks staged workflow files unless third-party Actions are SHA-pinned and `act --list` passes |
| `no-ai-attribution.sh` | PreToolUse Write+Edit | Blocks AI attribution phrases in file content |
| `no-secrets.sh` | PreToolUse Write+Edit | Scans Write/Edit content for high-confidence secret patterns |
| `no-forbidden-files.sh` | PreToolUse Write+Edit | Confirms before writing normally-forbidden files |
| `no-todo-comments.sh` | PreToolUse Write+Edit | Blocks `TODO`/`FIXME`/`HACK` markers and commented-out code |
| `comment-placement-guard.sh` | PreToolUse Write+Edit | Blocks comments in JSON and inline trailing comments in source files |
| `spec-guard.sh` | PreToolUse Write+Edit | Blocks Edit/Write on project files until AI.md/SPEC.md was read this session |
| `spec-guard-mark.sh` | PostToolUse Read | Records that AI.md/SPEC.md was read this session |
| `trailing-newline-guard.sh` | PostToolUse Write+Edit | Checks the file ends with exactly one trailing newline |

---

## 📊 Status Line

`home/scripts/statusline.sh` renders the two-line status bar Claude Code shows at the bottom of every session (wired via `statusLine.command` in `home/settings.json`). It reads the JSON payload Claude Code feeds it on stdin and fails open (`[?]` / `?`) on a missing `jq` or malformed payload. Honors `NO_COLOR` — disables both ANSI color and emoji.

| Item | Line | Source field | Notes |
|------|------|---------------|-------|
| Model | 1 | `.model.display_name` | Shown as `🧠 [name]`, bold cyan |
| Context window used % | 1 | `.context_window.used_percentage` | `📊 N% ctx`; green <50, yellow 50–79, red ≥80 |
| 5-hour rate limit used % | 1 | `.rate_limits.five_hour.used_percentage` | `⏱ 5h N%`; same threshold coloring |
| 7-day rate limit used % | 1 | `.rate_limits.seven_day.used_percentage` | Labeled `W N%` (week); same threshold coloring |
| Spend limit used % | 1 | `.rate_limits.spend_limit.used_percentage` | Only shown when present; same threshold coloring |
| Session cost | 1 | `.cost.total_cost_usd` | `💰 $N`, rounded to cents, green |
| Effort level | 1 | `.effort.level` (falls back to `$CLAUDE_CODE_EFFORT_LEVEL`) | `🎚 level`, magenta |
| Working directory | 2 | `.workspace.current_dir` / `.cwd` (falls back to `$PWD`) | `📁 path`, `$HOME` collapsed to `~`, dim |
| Lines added/removed | 2 | `.cost.total_lines_added` / `.cost.total_lines_removed` | `✏️ +N/-N`; omitted when both are `0` |
| Active agent | 2 | `.agent.name` | `🧩 name`; omitted when no agent is active |
| Active worktree | 2 | `.worktree.name` | `🌳 name`; omitted when no worktree is active |

Git branch/status is deliberately not shown — shelling out to `git` on every statusline refresh is too resource-intensive across many concurrent sessions.

---

## 🧠 Memory System

Files in `home/memory/` are loaded on demand at session start via `MEMORY.md`. They provide persistent convention and standards context without bloating `CLAUDE.md`.

| File | Contents |
|------|---------|
| `MEMORY.md` | Index — entry for every memory file |
| `project_conventions.md` | `{project_dir}/AI.md` / `{project_dir}/IDEA.md` / `{project_dir}/CLAUDE.md` roles, placeholder system, first-time setup flow |
| `project_files.md` | Forbidden files/dirs, allowed root files, README.md layout and content requirements, doc sync rules |
| `project_type_conventions.md` | Cross-language rules by project type: server, cli, library, tui, desktop-gui, worker, script-collection, spec-collection, packaging |
| `execution_hierarchy.md` | QEMU/KVM > Incus > Docker > host — where to run commands |
| `sensitive_data.md` | All public destinations treated identically; masking format (`key=xxxxx`); pre-flight checklist |
| `image_conventions.md` | Convert before reading (max 1280px, WebP); fallback chain; URL viewing workflow |
| `gitcommit_conventions.md` | `gitcommit` invocation rules, COMMIT_MESS format, emoji map, cadence, push behavior |
| `script_conventions.md` | Shebang/extension → interpreter; header template; `__` prefix; NO_COLOR; exit codes; doc triple sync |
| `go_conventions.md` | Go project layout, Makefile targets, CGO=0, binary naming, module cache |
| `rust_conventions.md` | Rust project layout, Cargo, release profile, static linking |
| `node_typescript_conventions.md` | Node/TypeScript build system, project layout, Makefile targets, code rules |
| `python_conventions.md` | Python build system, project layout, Makefile targets, code rules |
| `logging_conventions.md` | Log files are pure raw text; format per type; masking in logs |
| `dockerfile_conventions.md` | Two-stage builds, OCI labels, tini entrypoint, Docker Compose rules, `.dockerignore` |
| `gitignore_conventions.md` | Header format, standard entries, project-type additions |
| `tempdir_conventions.md` | Required path structure, per-language creation, guarded cleanup |
| `cicd_conventions.md` | SHA pinning, no `pull_request_target`, branch protection, SBOM, release integrity across all providers |
| `github_conventions.md` | CODEOWNERS, branch protection, workflow patterns, issue/PR templates, release automation, registry |
| `gitlab_conventions.md` | `.gitlab-ci.yml` patterns, predefined variables, MR templates, registry auth, self-hosted setup |
| `gitea_conventions.md` | `.gitea/workflows/` patterns, act runner, predefined variables, registry, self-hosted setup |
| `forgejo_conventions.md` | `.forgejo/workflows/` patterns, act runner, predefined variables, federation, self-hosted setup |
| `makefile_conventions.md` | Universal Makefile patterns shared across all project types and languages |
| `rpm_conventions.md` | Spec file structure, build workflow, signing, and repo layout for RPM packages |
| `api_conventions.md` | REST route naming, versioning, path vs query params, response format, request ID, middleware ordering |
| `database_conventions.md` | Schema management, parameterized queries, connection pooling, SQLite vs PostgreSQL, transactions |
| `nginx_conventions.md` | TLS/Let's Encrypt cert paths, reverse proxy and server-block conventions |
| `security_conventions.md` | Enumeration mitigation, GeoIP, CVE/dependency scanning, blocklists, `SECURITY.md` rules |
| `testing_conventions.md` | Test structure, naming, unit vs integration split, coverage gates, mock strategy, timing rules |
| `shell_lifetime_conventions.md` | Timeout tiers, polling rules, background-process ownership, follow-mode bounds |
| `comment_conventions.md` | Comment placement, formats where comments are forbidden, language-specific comment syntax |
| `file_ending_conventions.md` | Trailing-newline rule and its exceptions |
| `tool_conventions.md` | Internet access rules, `curl`/`wget`/`grep` defaults, provider CLIs, `act`, image handling |
| `ui_ux_conventions.md` | Designer-level UI/UX standards for web, desktop, mobile, TUI — theme, accessibility, layout |
| `external_contributions.md` | Rules for forks/PRs/fixes to third-party projects — upstream conventions win, task-scoped diffs only |
| `version_conventions.md` | How version strings originate in `release.txt` and flow through build, binaries, images, releases |
| `standards_reference.md` | HTTP status codes, RFC 7807, ISO 8601, semver, MIME, UUID, TLS, JWT, OAuth2, pagination |

---

## 🔒 Source of Truth Order

When rules conflict, the highest level wins:

1. **`{project_dir}/AI.md`** — full project spec; overrides everything when complete
2. **`{project_dir}/CLAUDE.md`** — project-level overrides
3. **`~/.claude/CLAUDE.md`** — global baseline (this repo)

A sparse or minimal `{project_dir}/AI.md` defers to global rules for anything it doesn't cover. A full spec (one that defines the complete implementation for its project type) is authoritative.

---

## 📁 Directory Layout

```
config/
├── install.sh              # Syncs home/ → ~/.claude/
├── home/                   # Mirrors ~/.claude/ exactly
│   ├── CLAUDE.md           # Global AI rules
│   ├── settings.json       # Permissions and hook wiring
│   ├── agents/             # Agent definition files ({name}.md)
│   ├── skills/             # Skill definitions ({name}/SKILL.md)
│   ├── TEMPLATES/          # Authoritative feature specs (BILLING.md, NOTIFICATIONS.md, SUPPORT.md, BASE.md)
│   ├── hooks/              # Hook scripts ({name}.sh)
│   ├── scripts/            # Standalone scripts (statusline.sh)
│   └── memory/             # Convention and standards files
│       ├── MEMORY.md       # Index
│       └── {topic}.md
├── AI.md                   # Project spec (THE HOW)
├── IDEA.md                 # Project plan (THE WHAT)
├── CLAUDE.md               # Short loader
├── README.md
└── LICENSE.md
```

## 🔄 Updating

```sh
curl -fsSL https://raw.githubusercontent.com/climgr/claude/main/install.sh | sh
```

## 👤 Author

**Jason Hempstead** · [GitHub](https://github.com/casjay) · [Casjays Developments](https://casjaysdev.pro)

## 📄 License

MIT — see [LICENSE.md](LICENSE.md)
