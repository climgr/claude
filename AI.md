| `no-subagent-gates.sh` | PreToolUse Bash | Blocks `make` and test runners (`go test`, `cargo test`/`nextest`/`clippy`, `pytest`, `npm`/`yarn`/`pnpm` test and `run test|lint|build|check`, `mvn`, `gradle`, `dotnet test`, `mix test`, and the same launched through `docker`/`podman`/`incus` exec) when the tool call's `agent_id` field is set — a subagent never runs the test gate, the lint gate, or `make`; the main session runs them once after reviewing the full diff. Plain builds (`go build`) and `bash -n` are not blocked |
# climgr/claude — Implementation Spec (THE HOW)

This file is read-only during routine work. Placeholders like `{deploy_target}` resolve from `IDEA.md → ## Project variables`.

---

## Part 1: Repository Layout

```
claude/
├── home/                        # mirrors ~/.claude/ exactly
│   ├── CLAUDE.md                # global AI instructions (deployed to ~/.claude/CLAUDE.md)
│   ├── settings.json            # permissions, hooks, Claude Code flags
│   ├── agents/                  # subagent definition files
│   │   └── {name}.md
│   ├── hooks/                   # PreToolUse/PostToolUse hook scripts
│   │   └── {name}.sh
│   ├── scripts/                 # standalone scripts (e.g. statusLine command)
│   │   └── {name}.sh
│   └── memory/                  # convention and standards memory files
│       ├── MEMORY.md            # index — always kept in sync
│       └── {topic}.md
├── AI.md                        # this file — THE HOW
├── IDEA.md                      # THE WHAT
├── CLAUDE.md                    # short loader only
├── install.sh                   # deploys home/ → ~/.claude/
├── README.md
└── LICENSE.md
```

---

## Part 2: install.sh

`install.sh` copies the contents of `home/` to `{deploy_target}` (`~/.claude/`).

- Always `chmod +x` hook scripts and `home/scripts/*.sh` after copy
- Never delete files from `{deploy_target}` that are not in `home/` — additive sync only, unless `--clean` is passed
- Must be idempotent — safe to run multiple times
- Tested on host (no container needed — this configures the host's Claude Code installation)
- Always commit all changes before running `install.sh` — deployed state must match the repo

---

## Part 3: home/CLAUDE.md

The global AI instruction file. Loaded by Claude Code at the start of every session in every project.

**Structure** (sections in this order):

1. `## Global Memory` — instructs AI to read `~/.claude/memory/MEMORY.md` at session start
2. `## Compaction` — what to preserve/drop when context compacts
3. `## Communication` — tone, truthfulness, question handling, terminology rules
4. `## Spelling & Grammar` — fix errors in files being edited
5. `## Working Directory & Path Resolution` — `{project_dir}` resolution, path namespace rules
6. `## Code & Files` — working-set discipline, scope, style matching, no JSON comments, singular dirs
7. `## Sensitive Data` — never commit credentials; all repos public by default; masking format
8. `## Project Files & Naming` — reference to `~/.claude/memory/project_conventions.md`
9. `## Cleanup` — project-scoped cleanup only, never broad ops
10. `## Verification & Safety` — confirm before destructive ops, never auto-bypass hooks; Memory Safety block (8 rules)
11. `## Self-Validation` — verify against ground truth, iterate until passing
12. `## Build & Execution` — rolling tags, execution hierarchy, tini chain, docker-compose zero-.env
13. `## Project Defaults` — MIT license, no feature gating, telemetry opt-in, Argon2id only
14. `## Language Constraints` — absolute Go rules (CGO=0, Docker-only) and Rust rules (Docker-only, no *-sys dynamic)
15. `## Output` — no preamble, tight budget, no emojis in code, no AI attribution
16. `## Tool Preference` — right tool for the job; curl/wget/grep defaults
17. `## Token & Context Discipline` — explorer for broad searches, read narrowly
18. `## Agent Usage` — Haiku for trivial tasks
19. `## Autonomy` — pre-authorized workflows, allowlists
20. `## Commit Workflow` — gitcommit only, pre-commit sequence, message format

**Rules:**
- This file governs all sessions globally — changes are high-impact
- Keep each section tight — no redundancy between sections
- Never add project-specific content here — that belongs in per-project `CLAUDE.md` files
- `{x}` = placeholder; `x` = literal — maintain this convention throughout

---

## Part 4: Memory Files (home/memory/)

Each memory file is a markdown file with YAML frontmatter:

```markdown
---
name: Short display name
description: One sentence describing what this file covers
type: user
---

## Content...
```

`MEMORY.md` is the index — every memory file must have an entry. Format:

```markdown
- [Display name](filename.md) — one-line summary of what it covers
```

**Current memory files and their scope:**

| File | Covers |
|------|--------|
| `MEMORY.md` | Index of all memory files |
| `project_conventions.md` | `{project_dir}/AI.md` / `IDEA.md` / `CLAUDE.md` roles, placeholder system, template system, first-time setup |
| `communication_conventions.md` | Ask-if-unsure exceptions, question-detection rules, general communication posture |
| `drift_prevention_conventions.md` | Pre-edit self-check checklist, post-compaction lazy re-verification, project_dir resolution, `/clear` hook-bug workaround |
| `agent_usage_conventions.md` | Prefer smaller scoped units of work, model routing pointer, agents-never-commit, "no edits" ≠ enforcement, fork/subagent scope discipline |
| `reuse_conventions.md` | Search-before-write for variables/constants, functions, UI components, and host-level system config entries |
| `path_resolution_conventions.md` | Provider inference from git remote host, `~/Projects/local`, full Local System Management Zone conditions |
| `local_system_zone.md` | Rules that relax under `~/Projects/local/system/**` (plaintext credentials, no LICENSE.md, systemctl pre-auth, cross-repo/host-config grants, raw git commands other than `commit`/`push`) and what never relaxes there |
| `model_routing.md` | Route each unit of work to the cheapest capable model (Haiku/Sonnet/Opus/Fable); largest single lever on consumption |
| `execution_hierarchy.md` | VM > Incus > Docker > host; execution scope rules |
| `sensitive_data.md` | All public destinations equal; masking format (`key=xxxxx`); pre-flight checklist |
| `image_conventions.md` | Convert before reading (max 1280px, WebP); fallback chain; URL image workflow |
| `gitcommit_conventions.md` | `gitcommit` path resolution; never hardcode path; pre-commit gate sequence including the doc-sync gate; `TEST_LINT_GATE_OVERRIDE=1`/`DOC_SYNC_GATE_OVERRIDE=1` escape hatches |
| `comment_conventions.md` | Comment placement rules, formats where comments are forbidden, language-specific comment syntax |
| `file_ending_conventions.md` | Every text file ends with exactly one trailing newline; exceptions for secret/verbatim/binary files |
| `shell_lifetime_conventions.md` | Timeout tiers, polling rules, background-process ownership, follow-mode bounds — enforced by `bound-shell-lifetime.sh` |
| `script_conventions.md` | Shebang/extension → interpreter; header template; `__` prefix; NO_COLOR; exit codes; doc triple sync |
| `project_files.md` | Files/dirs that must never be created; README.md/LICENSE.md naming rules |
| `external_contributions.md` | Rules for forks/PRs to third-party projects — upstream conventions win, task-scoped diffs only, no spec files created |
| `standards_reference.md` | HTTP status codes, RFC 7807, ISO 8601, semver, MIME, UUID, TLS, JWT, OAuth2, pagination |
| `gitignore_conventions.md` | Header format, standard entries, project-type additions |
| `dockerfile_conventions.md` | Two-stage builds, OCI labels, tini entrypoint, Docker Compose rules, .dockerignore |
| `nginx_conventions.md` | TLS cert paths, post-renewal deploy hooks, reverse-proxy vhost templates |
| `rpm_conventions.md` | Spec file structure, build workflow, signing, and repo layout for RPM packages |
| `logging_conventions.md` | Log files are pure raw text; format per type; masking in logs |
| `firewall_conventions.md` | Scripts never configure the firewall unless the project's own IDEA.md/SPEC.md/AI.md explicitly requires it — firewall setup is the system admin's job; firewalld/ufw auto-detection, default-allow-with-explicit-drops posture, optional fail2ban-style abuse blocking |
| `tempdir_conventions.md` | Required path structure, per-language creation, guarded cleanup |
| `cicd_conventions.md` | SHA pinning, no `pull_request_target`, branch protection, SBOM, release integrity |
| `go_conventions.md` | Go project layout, Makefile targets, CGO=0, binary naming, module cache |
| `rust_conventions.md` | Rust project layout, Cargo, release profile, static linking |
| `node_typescript_conventions.md` | Build system, project layout, Makefile targets, code rules for Node/TypeScript projects |
| `python_conventions.md` | Build system, project layout, Makefile targets, code rules for Python projects |
| `makefile_conventions.md` | Universal Makefile patterns shared across all project types and languages |
| `version_conventions.md` | How version strings originate in `release.txt` and flow through the build pipeline into binaries/images/releases |
| `github_conventions.md` | CODEOWNERS, branch protection, workflow patterns, issue/PR templates, release automation, registry conventions |
| `gitlab_conventions.md` | GitLab-specific CI/registry/MR conventions; load only when the remote resolves to GitLab |
| `gitea_conventions.md` | Gitea-specific workflow/runner/registry conventions; load only when the remote resolves to Gitea |
| `forgejo_conventions.md` | Forgejo-specific workflow/runner/registry conventions; load only when the remote resolves to Forgejo |
| `ui_ux_conventions.md` | Designer-level UI/UX standards — theme system, accessibility, layout, interaction |
| `project_type_conventions.md` | Rules by project type: server, cli, script-collection, spec-collection, packaging, library, tui, desktop-gui, worker |
| `security_conventions.md` | Enumeration mitigation, GeoIP, CVE/dependency scanning, blocklists, SECURITY.md rules, protected host paths, destructive-op/systemctl/kill gates, memory safety |
| `testing_conventions.md` | Test structure, naming, unit vs integration split, coverage gates, mock strategy |
| `database_conventions.md` | Schema management, parameterized queries, connection pooling, SQLite vs PostgreSQL selection, transaction patterns |
| `api_conventions.md` | REST route naming, versioning, path vs query params, response format, request ID, content negotiation, middleware ordering |
| `tool_conventions.md` | Internet access rules, `\command` alias-bypass prefix, default flags for curl/wget/grep/WebSearch, provider CLI usage |
| `kotlin_conventions.md` | Kotlin/Gradle (non-Android) project layout, Makefile targets, ktlint/detekt, code rules |
| `java_conventions.md` | Java/Maven project layout, Makefile targets, Checkstyle/SpotBugs, code rules |
| `ruby_conventions.md` | Ruby/Bundler project layout, Makefile targets, RuboCop/RSpec, code rules |
| `php_conventions.md` | PHP/Composer project layout, Makefile targets, PHPStan/phpcs/PHPUnit, code rules |
| `swift_conventions.md` | Swift/SwiftPM project layout, Makefile targets, SwiftLint, code rules |
| `dart_conventions.md` | Dart/Flutter/pub project layout, Makefile targets, dart analyze/flutter analyze, code rules |
| `cpp_conventions.md` | C/C++/CMake project layout, Makefile targets, clang-tidy/cppcheck, code rules |
| `csharp_conventions.md` | C#/.NET project layout, Makefile targets, dotnet format/Roslyn analyzers, code rules |
| `elixir_conventions.md` | Elixir/Mix project layout, Makefile targets, Credo/Dialyzer, code rules |

**Adding a new memory file:**
1. Create `home/memory/{topic}.md` with frontmatter
2. Add an entry to `home/memory/MEMORY.md`
3. Commit both in the same commit

---

## Part 5: Agent Files (home/agents/)

Each agent is a markdown file with YAML frontmatter followed by the agent's instructions:

```markdown
---
name: agent-name
description: When to invoke this agent — used by Claude to decide routing
---

Instructions for the agent...
```

**Rules:**
- `description` must be precise — Claude routes to agents based on it; vague descriptions cause mis-routing
- No `model:` frontmatter field — every agent inherits the parent session's model
- Agent instructions follow the same conventions as `home/CLAUDE.md` — no preamble, no AI attribution
- Agent name in the filename must match the `name:` frontmatter field

**Current agents:**

| Agent | Purpose |
|-------|---------|
| `architect.md` | System design, API design, data modeling, architectural tradeoffs |
| `audit.md` | Full project health audit — security, quality, logic, docs, line-by-line AI.md compliance |
| `beta-tester.md` | Structured beta testing — exploratory testing, edge cases, UAT against specs |
| `bootstrap.md` | Bootstrap a project from a spec (`{project_dir}/AI.md`); builds PART 0–6 scaffolding incl. loaders + `.claude/rules/`, enumerates feature PARTs into a complete `TODO.AI.md`, ensures IDEA.md without fabricating it |
| `cicd-maintenance.md` | Renovate PR review (SHA 3-point verification, merge, SHA table update) and `security.yml` audit/fix; flags Travis configs and hands off to `travis-migrator` |
| `claude-code-guide.md` | Answers questions about Claude Code CLI, hooks, MCP servers, Claude API |
| `code-reviewer.md` | Review diffs, PRs, or files before committing or merging |
| `commit-prep.md` | Prepare `COMMIT_MESS` without polluting main conversation with diff output |
| `debugger.md` | Root cause analysis for bugs, crashes, hangs, unexpected behavior |
| `devops.md` | Infrastructure, CI/CD, containers, orchestration, deployment strategies |
| `doc-sync.md` | Sync `__help()`, man page, and completions triple after a script changes |
| `dockersrc-bootstrap.md` | Bootstrap or update a CasjaysDev Docker image repo against the current gen-dockerfile templates |
| `explorer.md` | Fast read-only codebase search — files by pattern, symbol definitions, keywords |
| `general.md` | Catch-all for everyday tasks when no specialist agent fits |
| `go-lint.md` | Lint Go projects for CasjaysDev convention violations |
| `implement.md` | Read a spec from its first word and implement everything in order (following refs); orchestrates scaffold-then-build-all, delegates to scoped builders, never commits or runs the gate |
| `planner.md` | Design an implementation plan before writing code; flags risks |
| `researcher.md` | Multi-step research spanning multiple files or requiring web + code reading |
| `rust-lint.md` | Lint Rust projects for CasjaysDev convention violations |
| `script-lint.md` | Lint bash/sh scripts for CasjaysDev convention violations |
| `security-auditor.md` | Threat modeling, OWASP audits, secrets scanning, auth flows, hardening |
| `spec-migrator.md` | Migrate SPEC.md/CLAUDE.md/AI.md to standard structure; bootstrap wizard |
| `statusline-setup.md` | Configure Claude Code status line fields |
| `test-writer.md` | Write unit, integration, table-driven, and fuzz tests for existing code |
| `travis-migrator.md` | Read an existing `.travis.yml`/`.travis.yaml`, generate the equivalent native workflow for the real CI/CD provider under `cicd_conventions.md`; never touches the Travis file itself; supports single-project and fleet-wide bulk sweeps |

---

## Part 6: Hook Scripts (home/hooks/)

Hooks are bash scripts executed by Claude Code before or after tool use. They communicate back via stdout and exit code.

**Shebang:** `#!/usr/bin/env bash` — always bash, full header per script conventions.

**Exit code protocol:**

| Exit | Meaning |
|------|---------|
| `0` | Allow — tool use proceeds |
| `2` | Block — tool use is cancelled; **stderr** carries the reason |
| other | Non-blocking error — Claude Code surfaces it as "hook error" noise; never exit non-zero for a normal no-op |

**Blocking output format.** On exit `2` from a `PreToolUse` hook, Claude Code
feeds **stderr** back to Claude as the block reason; stdout is *not* shown to
Claude for `PreToolUse`. A hook that writes its reason only to stdout therefore
blocks the call with no visible explanation, which reads to the user as an
unexplained failure and makes Claude retry blindly. Write the message to both
streams — stderr so it reaches Claude and the terminal, stdout so it is also
captured in the transcript:

```bash
printf 'BLOCKED: %s\n' "{reason why it was blocked}"
printf 'BLOCKED: %s\n' "{reason why it was blocked}" >&2
exit 2
```

**Fail open, always.** A malformed, empty, or non-object stdin payload, a
missing interpreter, or any internal error must exit `0` silently. Never let a
`jq` parse failure (`jq` exits 4/5) or a Python `AttributeError` propagate — under
`set -euo pipefail` those become a non-zero exit that Claude Code reports as a
hook error on every tool call.

**Stay fast.** Each hook runs synchronously on every matching tool call and is
killed at its `settings.json` `timeout`. Never spawn an interpreter per
sub-command inside a loop — parse the whole command in one pass, or the hook's
runtime grows with the size of the user's command line and eventually times out.

**Input:** Hook receives tool input as JSON on stdin. Parse with `jq` — a
few hooks (e.g. `block-host-toolchain.sh`) parse with `python3` instead
where its parsing/quoting needs exceed what a `jq` one-liner can express
cleanly; either is fine as long as a missing interpreter fails the hook
open (exit 0), never closed.

**Rules:**
- Hooks must be fast — they run synchronously before/after every matching tool call
- Never do network I/O in a hook
- Never write to files from a hook, except append-only logs and the
  small session-marker files under `${TMPDIR:-/tmp}/claude-hooks/`
  that gate hooks (`spec-guard-mark.sh`, `test-lint-mark.sh`,
  `lint-agent-mark.sh`) use to record session state for a paired
  PreToolUse gate to check — never a project file
- Always handle `jq` parse failures gracefully — malformed input must not crash the hook
- Test hooks by piping sample JSON to them directly: `echo '{...}' | ./hooks/myhook.sh`

**Current hooks:**

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start.sh` | SessionStart (no matcher — fires on every trigger) | Injects project_dir + CLAUDE.md/AI.md/SPEC.md precedence context on session start. Claude Code's own docs list a `clear` matcher value that would scope a hook to just `/clear`, but home/settings.json's entry for this hook sets no matcher at all, and a confirmed upstream bug ([anthropics/claude-code#34072](https://github.com/anthropics/claude-code/issues/34072), closed not-planned) means `SessionStart` hooks do not actually fire on `/clear` as of Claude Code 2.1.231 regardless — CLAUDE.md's own "Session Start" section is the reliable fallback since CLAUDE.md is always reloaded on `/clear` regardless of hooks |
| `post-compact.sh` | SessionStart(compact) | Re-injects project-dir and global context after compaction |
| `drift-guard-read.sh` | PreToolUse Read+Bash | Blocks reading `~/.claude/` deployed copies (Read tool, and `cat`/`less`/`head`/etc. via Bash) when a `home/` source actually exists — fails open (no block) when it doesn't. A `DRIFT_GUARD_ALLOW=1` env-var prefix on the Bash command bypasses the block for that one call, for an explicit user-directed read of the deployed (live) copy — Claude sets it only when the user's own message asked for the deployed file, never on its own initiative; the Read tool has no field to carry the override, so an explicit deployed-copy read must go through Bash |
| `no-read-gitcommit.sh` | PreToolUse Read+Grep+Bash | Blocks reading the `gitcommit` script file (Read tool, Grep tool, and `cat`/`less`/`head`/etc. via Bash) — CLAUDE.md's Commit Workflow says it is "pre-approved and trusted" and must never be inspected, only invoked; no zone exception. Resolves the path from `PATH` rather than hardcoding it, and also catches a read whose path comes from a `$(command -v gitcommit)` / `` `which gitcommit` `` / `$(type -P gitcommit)` substitution, which produces no literal path token to compare |
| `protect-host.sh` | PreToolUse Bash | Blocks destructive host commands: deleting/overwriting auth-critical files (`/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, …), arbitrary writes into core binary dirs (`/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`), wiping `/` or `$HOME` itself, wiping a top-level system dir or its contents, raw block-device writes, `pkill`/`killall`, unscoped container/instance sweeps (unfiltered `docker ps`/`incus list` feeding kill/stop/rm, plus `docker prune`), destructive shell redirects and `find -delete`. Container/VM-mediated commands (`docker exec`/`run`, `incus exec`, `kubectl exec`, `qemu-system-*`, …) are exempt — the blast radius is the disposable guest; `chroot`/`nsenter`/`virsh` are deliberately NOT exempt, since they act on the host namespace. systemctl lifecycle mutation is exempt under `~/Projects/local/system/**` (cwd-scoped, see CLAUDE.md's Local System Management Zone), and separately exempt everywhere for the container/VM runtime daemons themselves (`docker`, `containerd`, `incus`, `lxd`, `libvirtd`, `virtlogd`, `virtlockd`, `virtnetworkd`, `virtstoraged`, `virtqemud`, `podman`) — the engine is infrastructure at the same execution tier as exec/run, not a host application service |
| `block-host-toolchain.sh` | PreToolUse Bash | Blocks direct host toolchain invocations and suggests the Docker equivalent |
| `enforce-docker-rm.sh` | PreToolUse Bash | Blocks `docker run` without `--rm`/`--name` and `incus launch`/`init` without an instance name (prevents orphaned/untargetable containers). `--rm` is exempt on detached (`-d`/`--detach`) containers, for multi-container integration testing (e.g. server/client) that needs to inspect a crashed container's logs before teardown — `--name` stays mandatory |
| `bound-shell-lifetime.sh` | PreToolUse Bash | Blocks unbounded shell lifetimes across five rules: (A) `while`/`until`/`for ((;;))` poll loops that sleep without a bound, (B) open-ended or oversized single `sleep`, (C) detachment that escapes the tool timeout (`nohup`/`setsid`/`disown`), (D) follow-mode readers (`tail -f`, `watch`) outside a `timeout`, (E) `&` backgrounding with neither a `PID=$!` capture nor a closing `wait`. Sentinel polling (waiting on a marker file/flag to appear) is blocked unconditionally, even when the loop itself is bounded |
| `zone-git-commit-push.sh` | PreToolUse Bash | Blocks raw `git commit` and raw `git push` everywhere, including inside `~/Projects/local/system/**` — no zone exception for either, since the user signs every commit and `gitcommit` handles that signing automatically, and `gitcommit` is the sole commit+push path. A zone repo that must never publish keeps a `.no_push` file instead of a raw-push carve-out. `settings.json`'s `permissions.deny` cannot be directory-scoped, so this hook is the actual enforcement point — `git reset` stays hard-denied everywhere via `permissions.deny` |
| `no-subagent-commit.sh` | PreToolUse Bash | Blocks `gitcommit`/`git commit`/`git push` when the tool call's `agent_id` field is set (i.e. it came from a subagent, not the main session) — everywhere, including inside the zone. "Agents never commit" (CLAUDE.md's Agent Usage section) was prose-only with no technical gate until this hook |
| `no-force-push.sh` | PreToolUse Bash | Blocks `git push --force`/`--force=…`/`--force-with-lease*`/`-f`/`+refspec` everywhere, including inside the zone (`gitcommit` is the only sanctioned push path outside the zone; force-push is excluded from the zone's raw-git pre-authorization). Shares the same container-mediated/non-shell heredoc exemption as `bash-content-scan.sh` — a `cat`/`python3` heredoc that merely mentions a force-push is data, not a command |
| `no-history-rewrite.sh` | PreToolUse Bash | Blocks `git clean -f*`, `git rebase` (not `--abort`/`--continue`/`--skip`), `git branch -D`, `git tag -d`, `git filter-repo`, `git filter-branch` everywhere, including inside the zone (all excluded from the zone's raw-git pre-authorization — `local_system_zone.md`'s "Still hard" list). Shares the same container-mediated/non-shell heredoc exemption as `no-force-push.sh` |
| `no-destructive-bypass.sh` | PreToolUse Bash | Re-enforces `settings.json`'s `permissions.deny` for `git reset`, `dd`, `shred`, `mkfs*`, `wipefs` with wrapper-bypass hardening (`\cmd`, `command cmd`, `env KEY=VAL cmd`) — `permissions.deny` only does raw glob matching on the literal command string, so a wrapped invocation slips past it |
| `bash-content-scan.sh` | PreToolUse Bash | Runs `no-secrets.sh`'s secret patterns and `no-ai-attribution.sh`'s attribution patterns against content written by a Bash heredoc or `echo`/`printf` redirect — those two hooks only ever see Write/Edit `tool_input`, so `cat <<EOF > file` bypassed both entirely. Same zone exemption for secrets, no zone exemption for AI attribution, container-mediated heredocs exempt. The attribution match is anchored per line after stripping comment/quote leaders, exactly as `no-ai-attribution.sh` does it — an unanchored whole-content search flags prose that merely discusses the rule |
| `enforce-gitcommit-shape.sh` | PreToolUse Bash | Blocks any `gitcommit` invocation that isn't exactly `gitcommit --dir <path> all` or the documented push-retry form `gitcommit push` — catches `-m`/`--message` and any other flag/argument shape, everywhere including inside the zone (`gitcommit` itself has no zone exception) |
| `enforce-test-lint-gate.sh` | PreToolUse Bash | Blocks `gitcommit --dir <path> all` unless the test gate and lint gate actually ran and passed this session for that project. Checks two independent signals, either satisfies the gate: (1) the markers `test-lint-mark.sh`/`lint-agent-mark.sh` write, or (2) a direct scan of the PreToolUse payload's own `transcript_path` for a passing (`is_error` false, not `interrupted`) Bash `tool_use`/`tool_result` pair this session whose command matches the test/lint pattern and that belongs to the target project — its entry `cwd` matches, OR the command/agent prompt/report names the project path (a session run from a parent dir testing/linting a sibling repo never has a matching `cwd`; matching on `cwd` alone false-blocked every such commit). Agent-tool lint runs count via their `tool_result` or, for async runs (whose `tool_result` is only a "launched" notice), via the later `hand-back` message resolved to its prompt through the `agentId` — a fallback for the upstream PostToolUse bug documented below, added because marker-only enforcement was blocking real passing runs across every project/session. For the lint agents specifically, the gate only requires zero NEW findings (issues on lines the session's own uncommitted changes touch) — a report of only pre-existing findings (outside those lines, logged to TODO.AI.md instead) passes; see `lint-agent-mark.sh`'s row for the exact contract. Spec-collection projects (no Makefile/manifest/`*.sh`) substitute an AI.md/SPEC.md re-read this session instead, reusing `spec-guard.sh`'s marker; a template repo with neither AI.md nor SPEC.md at its root (`claudemgr/{go,rust,android,docker,mgr}`) satisfies this via `spec-guard-mark.sh`'s root-level `*.md` fallback instead. A `TEST_LINT_GATE_OVERRIDE=1` env-var prefix on the `gitcommit` command bypasses the gate for that one call — same pattern as `drift-guard-read.sh`'s `DRIFT_GUARD_ALLOW=1`, only ever set by Claude when the user's own message explicitly directs a bypass after confirming they already verified the run passed, never on Claude's own initiative just because the gate blocked |
| `enforce-commit-mess-coverage.sh` | PreToolUse Bash | Blocks `gitcommit --dir <path> all` when the target repo's working tree has changed/untracked files with no matching `- path: change` bullet in `.git/COMMIT_MESS` (or when COMMIT_MESS is missing/empty while the tree is dirty). `gitcommit all` sweeps the ENTIRE tree, so after a long-running session the message written from recent context under-describes the commit — the "every changed file described" rule (gitcommit_conventions.md) was prose-only until this hook. Coverage is one-directional: every changed file needs a bullet; extra bullets are fine. A directory bullet (`- dir/: ...`) covers files beneath it; `*`/`?` bullets glob-match; rename entries only require the new path. Fails open when git fails, the path isn't a repo, or the tree is clean |
| `enforce-doc-sync.sh` | PreToolUse Bash | Blocks `gitcommit --dir <path> all` unless `.git/COMMIT_MESS` carries an explicit status line for whichever of `IDEA.md`/`README.md` actually exists at the target repo's root — a forced-acknowledgment gate, not a content-diff heuristic: it only checks a line is PRESENT (`- IDEA.md: updated (...)` or `- IDEA.md: N/A — no user-facing change`, same for `README.md`), never that the claim is true, same trust model as `enforce-commit-mess-coverage.sh`'s per-file bullets. Closes the drift problem where AI.md/IDEA.md never gets told about a feature added to code. Repos with neither file at their root (script-collection/spec-collection projects, third-party forks) are exempt automatically since the required-file list is empty. A `DOC_SYNC_GATE_OVERRIDE=1` env-var prefix on the `gitcommit` command bypasses the gate for that one call — same pattern as `TEST_LINT_GATE_OVERRIDE=1`, user-directed only, never Claude's own initiative |
| `test-lint-mark.sh` | PostToolUse Bash | Records, per session and project, that a test-gate or lint-gate command succeeded (and wasn't interrupted) — pairs with `enforce-test-lint-gate.sh`. Success is detected by whether `tool_response` is a JSON object (success: `{stdout, stderr, interrupted, isImage, ...}`) vs. a bare string (nonzero exit: `"Error: Exit code N"`) — Bash's `tool_response` has no `exit_code` field at all, confirmed against live transcript data; an earlier version of this hook read `.tool_response.exit_code`, which is always absent, so it never wrote a marker for any command, pass or fail. A confirmed upstream bug ([anthropics/claude-code#36310](https://github.com/anthropics/claude-code/issues/36310), open) also means `PostToolUse` on `Bash` sometimes never spawns for a real Bash tool call, so the marker can still go unwritten even now — `enforce-test-lint-gate.sh`'s `transcript_path` fallback above covers that remaining case without depending on `PostToolUse` firing at all |
| `lint-agent-mark.sh` | SubagentStop | Records the lint gate as satisfied when the `script-lint`/`go-lint`/`rust-lint` subagent finishes for this project and session with zero NEW findings — the shell/Go/Rust lint gate is run via the Agent tool (a subagent), never as a host CLI command, so `test-lint-mark.sh`'s PostToolUse-on-Bash detection can never see it fire (the Node/TS `npm run lint` and Python `ruff check` gates ARE ordinary Bash commands, which `test-lint-mark.sh` records directly). Parses the SubagentStop payload's `last_assistant_message` against the lint agents' own `: clean` / `: 0 new issue(s) found (...)` / `: N new issue(s) found` report contract — the agents classify each finding as NEW (on a line the session's own uncommitted changes touch) or pre-existing (outside those lines, to be logged in TODO.AI.md by the calling session instead); only a nonzero "N new issue(s) found" anywhere in a multi-file report skips the marker, so a report of only pre-existing findings still passes. Writes the same marker `enforce-test-lint-gate.sh` checks, once per project the agent demonstrably worked on — the payload `cwd`'s git toplevel plus every existing absolute path named in the agent's own prompt (first entry of `agent_transcript_path`) or final report — because a session run from a parent dir routinely lints a sibling repo, and keying on `cwd` alone recorded the wrong project |
| `validate-workflows.sh` | PreToolUse Bash | Blocks staged `.github/workflows` files before `gitcommit` unless every third-party `uses:` is pinned to a full 40-char commit SHA (cicd_conventions.md), and validates them with `act --list`. Never auto-installs `act` — blocks with manual-install instructions if missing, since hooks must never do network I/O |
| `no-ai-attribution.sh` | PreToolUse Write+Edit | Blocks AI attribution phrases in file content |
| `no-secrets.sh` | PreToolUse Write+Edit | Scans Write/Edit content for high-confidence secret patterns and blocks if found; exempt under `~/Projects/local/system/**` (cwd-scoped, see CLAUDE.md's Local System Management Zone). The cwd check is necessary but not sufficient — it cannot verify private repo visibility (a live check is network I/O, forbidden in hooks); the Repo privacy gate is what actually keeps the exemption safe. Same caveat applies to `bash-content-scan.sh`'s duplicated secrets-zone check |
| `no-forbidden-files.sh` | PreToolUse Write+Edit | Confirms before writing normally-forbidden files |
| `no-todo-comments.sh` | PreToolUse Write+Edit | Blocks `TODO`/`FIXME`/`HACK` markers at the start of a comment, and a narrow high-confidence commented-out-code heuristic — exempt for `TODO.AI.md`/`TODO.md`/`PLAN.AI.md`/`PLAN.md`/`COMMIT_MESS`; never matches the `@@TODO` header field (starts `@@`, not the bare word). The comment leader set is chosen by file extension (`--` is a comment only in `.sql`/`.lua`/`.hs`, never in a shell script), and every commented-out-code shape requires code punctuation — a keyword alone is not enough, because `for`, `from`, `return`, `class` and `private` all begin ordinary English comment prose |
| `comment-placement-guard.sh` | PreToolUse Write+Edit | Blocks comment syntax (`//`/`/* */`) written into a `.json` file (string-aware, so `://` inside a JSON string value is never flagged), and blocks inline trailing comments in a fixed extension list of common source files (comment_conventions.md's "comments always ABOVE, never inline") — exempt for `# noqa`/`# type: ignore`/`// nolint` and CI workflow SHA-pin annotations. The 180-char length check skips `##@Version` / `# @@Field :` script-header lines, which are a one-line-per-field template that cannot wrap |
| `spec-guard.sh` | PreToolUse Write+Edit | Blocks Edit/Write on project files until AI.md/SPEC.md was read this session |
| `spec-guard-mark.sh` | PostToolUse Read | Records that AI.md/SPEC.md was read this session, per project; for a project with neither at its root (a `claudemgr/{lang|type}/` template repo), also marks on any root-level `*.md` read that isn't a known non-spec meta filename (README.md, LICENSE.md, CLAUDE.md, IDEA.md, TODO(.AI).md, PLAN(.AI).md) |
| `trailing-newline-guard.sh` | PostToolUse Write+Edit | Read-only check that the file ends with exactly one trailing newline (file_ending_conventions.md); blocks with a remediation message rather than rewriting the file itself, per this section's "never write to files from a hook" rule — exempt for raw-value secret/token files, `VERSION`, lockfiles, and binary content |

**Wiring hooks in settings.json:**

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/protect-host.sh" }]
    }
  ]
}
```

---

## Part 7: settings.json

Controls Claude Code permissions and hook wiring. Structure:

```json
{
  "permissions": {
    "allow": [...],
    "deny": [...],
    "ask": [...]
  },
  "hooks": {
    "PreToolUse": [...],
    "PostToolUse": [...]
  },
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80"
  }
}
```

**Permission entry format:** `"{ToolName}({glob})"` — e.g. `"Edit(**/.git/COMMIT_MESS)"`.

**Rules:**
- Explicit `allow` entries are required for sensitive paths — Claude Code has built-in sensitivity overrides that `allow` globs alone may not bypass (e.g. `.git/**` paths need explicit entries)
- Sensitive files with explicit allows: `.git/COMMIT_MESS`, `.git/COMMIT_EDITMSG`, `CLAUDE.md`, `settings.json`, `settings.local.json`, `.env`, `app.env`, `default.env`
- `deny` takes precedence over `allow`
- Hook commands use `$HOME/.claude/hooks/` paths — never relative paths, and never a literal `~` (unreliable in a JSON command string; `$HOME` expands correctly)
- **Auto-compaction lives in the `env` block.** `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (1-100) is a percentage of the auto-compact window, so `80` compacts at 80% of whatever window the model has; it can only lower the default threshold and applies only to sessions that compact before the model's limit (native 1M windows, about 967K by default). `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is an absolute plain-integer token count (100000-1000000; `500k` is read as 500) that overrides every other window setting — leave it unset so the percentage stays relative
- **Never set `CLAUDE_CODE_DISABLE_1M_CONTEXT` in `env`.** Set to `1` it holds native-1M models (Sonnet 5+, Opus 4.7+, Fable) to a 200K window; the docs define no meaning for `0`, so leave it unset. The `[1m]` model suffix is only needed for Opus/Sonnet 4.6 — native-1M models ignore it
- A top-level `autoCompactWindow` or `modelSettings[model].autoCompactWindow` is an absolute token count that applies to every model (top-level) or one model (per-model); do not add either here unless a fixed absolute threshold is wanted

---

## Part 8: Working on This Repo

- The active working set is `home/` and its subdirectories
- No build or compilation step — all files are deployed as-is
- Test hooks manually before committing, using the real payload field names — Claude Code sends `tool_name`/`tool_input`, so a sample using `tool`/`input` matches nothing and exits `0` no matter what the hook does: `echo '{"tool_name":"Write","tool_input":{"file_path":"test.sh","content":"foo"}}' | bash home/hooks/no-ai-attribution.sh`
- Also pipe a hostile payload to every changed hook — `''`, `'{'`, `'[]'`, `'null'` must each exit `0` silently (Part 6, "Fail open, always"), and a realistically large `content` value must finish well inside the hook's `settings.json` timeout
- Validate `settings.json` with `jq . home/settings.json` before committing
- Validate memory file frontmatter: must have `name`, `description`, `type` fields
- Run `install.sh` after committing to deploy — never deploy uncommitted changes
- Changes here affect every Claude Code session on the machine — test carefully

---

## Part 9: Template Repositories (../{lang|type}/{TYPE}.md)

**Org split:** the `claudemgr` org holds only the `{lang|type}` template repos below — it does not hold this repo. This repo (`climgr/claude`) lives in the separate `climgr` org, which is strictly for CLI tool configuration repos — mostly AI CLIs (Claude Code, etc.), but any CLI tool is in scope. The two orgs are unrelated in content; `climgr/claude` is not a sibling of the template repos on GitHub or on disk, and template repos will never move into `climgr`.

"Templates" refers to the `{lang|type}` spec repos under the `claudemgr` org — `~/Projects/github/claudemgr/{lang|type}/{TYPE}.md` — each a master `AI.md`-style spec copied verbatim into a generated project as that project's `AI.md`. The repo-name segment is not always a programming language — `go`/`rust` are languages, `android` is a device/platform target — so read `{lang|type}` as "whatever the repo is named," never assume it parses as a language.

**Default referent:** an unqualified "the templates" (e.g. "why do the templates say/have/miss X") always means these template repos — `go/`, `rust/`, `android/`, `docker/`, and `home/TEMPLATES/*.md` — and the search/fix scope is all of them. It never means `home/**`/`./home/*`/`./home` (this repo's deployed dotfiles/memory tree) unless the user names one of those paths explicitly.

**Filename convention per app category** (fixed, applies across every `{lang|type}` repo):

| Category | Filename |
|----------|----------|
| Full server (server-rendered HTML + optional REST) | `SERVER.md` |
| API-only (REST/JSON, no frontend) | `API.md` |
| Desktop/GUI/TUI/CLI app, no server component | `APPLICATION.md` (singular — not `APPLICATIONS.md`) |
| Hybrid — application surfaces (GUI/TUI/CLI) plus an embedded full server (frontend + backend) in one binary | `HYBRID.md` |

Not every repo ships every category — `android` is app-only (`APPLICATION.md` only, no `API.md`/`SERVER.md`/`HYBRID.md`), since there's no server-side Android target.

```
~/Projects/github/climgr/
└── claude/                      # this repo — source of ~/.claude/ (github.com/climgr/claude)

~/Projects/github/claudemgr/
├── go/                           # github.com/claudemgr/go — language
│   ├── API.md                    # REST/JSON API server template
│   ├── APPLICATION.md            # GUI/TUI/CLI, no server, template
│   ├── HYBRID.md                 # application + embedded full server template
│   └── SERVER.md                 # full-stack web server template
├── rust/                         # github.com/claudemgr/rust — language
│   ├── API.md
│   ├── APPLICATION.md
│   ├── HYBRID.md
│   └── SERVER.md
├── android/                      # github.com/claudemgr/android — device/platform, app-only
│   └── APPLICATION.md            # no API.md/SERVER.md — app-only ecosystem
└── docker/                       # github.com/claudemgr/docker — Docker repo templates
    ├── DOCKERSRC.md              # master spec for dockersrc/* base-image repos
    ├── CASJAYSDEVDOCKER.md       # master spec for casjaysdevdocker/* app-image repos
    └── COMPOSEMGR.md             # master spec for composemgr/* compose-stack repos
```

More `{lang|type}` repos will be added over time (languages and device/platform targets alike) using this same filename convention — do not invent new filenames per repo.

**Exception — `docker/`:** it holds master specs for Docker *repositories* (`dockersrc/*` and `casjaysdevdocker/*` image repos, `composemgr/*` compose-stack repos), not app projects, so the app-category filenames don't apply. Its files are named per repo family (`DOCKERSRC.md`, `CASJAYSDEVDOCKER.md`, `COMPOSEMGR.md`; more may follow the same `{FAMILY}.md` pattern). Everything else about template repos applies unchanged: copied verbatim into a repo as its `AI.md`, WTFPL-licensed, own remote, own commits, swept by the alignment rule where content overlaps. The image-repo maintenance runbook lives in the `dockersrc-bootstrap` agent, not in the specs; compose repos need no runbook (no generator tooling).

**If a template dir doesn't exist locally**, clone it before reading/editing — never treat a missing dir as "no templates to update":

```bash
git clone https://github.com/claudemgr/{lang|type}.git ~/Projects/github/claudemgr/{lang|type}
```

**Alignment rule:** template repos are separate git repos, each with its own remote, its own `gitcommit --dir {repo} all`, and no dependency on this repo's git history — but their CI/CD, security, and build content MUST stay aligned with `home/**` (especially `home/memory/cicd_conventions.md`, `go_conventions.md`, `rust_conventions.md`). When a rule in `home/**` changes in a way that affects generated projects (e.g. a new CI gate, a new verification step), check the matching template file(s) in every existing `{lang|type}` repo for the same gap and fix them in the same session, as separate commits in their own repos — and sweep `home/TEMPLATES/` for the same gap in the same session (see below).

### Global Templates (home/TEMPLATES/, installed to ~/.claude/TEMPLATES/)

`home/TEMPLATES/` holds two species of template; both are templates in the full sense — every template-authoring rule (no inline comments, no hardcoded versions, placeholder system, templates follow their own rules) applies to them exactly as it does to the repo templates:

| File | Species | Role |
|------|---------|------|
| `BASE.md` | **Project template** | Generic fallback member of the project-template family — copied into a project as its `AI.md` when language/shape is unknown; replaced by a `{lang|type}/{TYPE}.md` once known |
| `BILLING.md`, `NOTIFICATIONS.md`, `SUPPORT.md` | **Feature template** | Authoritative feature-module spec applied INTO an existing project by its builder agent (`billing-builder`, `notifications-builder`, `support-builder`) — never a whole-project spec |

**Terminology:** "project templates" = the `{lang|type}/{TYPE}.md` repo specs plus `BASE.md`; "feature templates" = the builder-agent specs. Unqualified "templates" continues to mean the repo templates.

**Alignment, two tiers:**

- `BASE.md` aligns with the template repos on ALL shared canon (release-flow skeleton, version/build-metadata rules, checksum format, commit workflow, verification gates). It stays language-agnostic — it states the canon generically and defers language-specific mechanics to the `{lang|type}` templates that replace it.
- Feature templates align where they OVERLAP shared canon (CI additions, security rules, DB/config conventions) but defer to the host project's template on build/release matters — a feature template never redefines the release flow.

**Sweep rule:** any canon change that triggers a template-repo sweep also triggers a `home/TEMPLATES/` sweep in the same session (BASE.md always; feature templates when the change touches content they overlap).

Templates are licensed WTFPL (the templates themselves); generated projects ship MIT.

---

## Part 10: Commit Conventions

Follow the global gitcommit workflow from `home/CLAUDE.md`. One logical change per commit.

When adding a memory file: commit both the new file and the updated `MEMORY.md` together.
When adding an agent: commit the agent file; update `AI.md` Part 5 table in the same commit.
When adding a hook: commit the script and the updated `settings.json` wiring together.
