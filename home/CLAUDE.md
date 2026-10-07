# Claude Rules

## Session Start
Before any work, sync `{project_dir}` with the remote:

1. `git status --porcelain` — check for uncommitted changes
2. If dirty: `git stash push -m "session-start auto-stash"`
3. `git pull`
4. If stashed: `git stash pop`
5. If `stash pop` conflicts: report the conflicting files and wait — never auto-resolve merge conflicts; let the user decide

If the pull fails (no remote, offline, branch diverged): report it and wait — never start work on a potentially stale tree.

**`/clear`** doesn't reliably fire the SessionStart hook (upstream bug) — re-run this sequence yourself after any `/clear`. Detail: `~/.claude/memory/drift_prevention_conventions.md`.

## Global Memory
Read `~/.claude/memory/MEMORY.md` at session start and load referenced files as needed.

**Follow refs after, not during:** when a file references another file ("see `x.md`", "See PART X"), finish the portion you set out to read (whole file, section, or PART slice) first; queue referenced files and load them afterward. A reference never interrupts or replaces the remainder of what you were reading — after reading the referenced content, return to the next line and continue.

Provider-specific convention files (`github_conventions.md`, `gitlab_conventions.md`, `gitea_conventions.md`, `forgejo_conventions.md`) are loaded **on demand only** — detect the provider from `git remote get-url origin` and load only the matching file. Never pre-load all provider files.

**Large memory files load by section, not whole** — for any referenced memory file over ~400 lines, `grep -n "^## "` it first to find the relevant section, then read only that slice (same technique as the `TODO.AI.md` PART-loading rule in Project Files & Naming). Never `Read` the full file for a single-topic question.

## Compaction
Preserve: task goal · files changed · commands run · failing tests/errors · decisions · next actions.
Drop: old exploration paths · repeated logs · irrelevant discussion.

## Communication
Full rules (ask-exceptions, question-detection, general posture): `~/.claude/memory/communication_conventions.md`
- Truthful over agreeable — push back, disagree when warranted; never agree just to be agreeable
- Ask if unsure; never guess or assume, except where asking is physically impossible/meaningless (inaccessible hardware, headless/no-GPU environments, documented reversible build defaults, missing toolchain) — never for business logic/data/feature behavior
- Check the project's own spec (`AI.md`/`IDEA.md`/`SPEC.md`) before asking anything it already answers
- `?`-ending or interrogative-leading messages are questions, not commands — answer, don't act, unless the user re-sends as a statement or says "yes"/"do it"/"go ahead"
- Match user's terminology exactly · `{x}` = placeholder, `x` = literal text

## Spelling & Grammar
Always fix clear spelling and grammar errors in any file being edited. Never alter technical terms, intentional abbreviations, or domain-specific names.

## Drift Prevention
Drift = ignoring project-specific rules and reverting to global defaults or prior-session assumptions. Self-check before any read or write, answered explicitly, not silently assumed: is this path inside `{project_dir}`; does this project have its own version of this file; am I applying THIS project's rule, not a global assumption; is the working set still what the user defined. Post-compaction: never bulk re-read spec files — re-verify lazily, per-section, right before each edit. Full detail (post-compaction technique, project_dir resolution from SessionStart/PostCompact context): `~/.claude/memory/drift_prevention_conventions.md`

---

## Working Directory & Path Resolution

- **CWD is `$PWD`** — all relative paths resolve from there
- **`{project_dir}`** = `git rev-parse --show-toplevel` if inside a git repo; otherwise = `$PWD` at session start
- **`{project_name}`** = `basename {project_dir}` · **`{project_org}`** = `basename $(dirname {project_dir})` · **`{provider_name}`** = `basename $(dirname $(dirname {project_dir}))`
- Projects live at `~/Projects/{provider_name}/{project_org}/{project_name}`. Known providers: `github` (use `gh`) · `gitlab` (use `glab`) · `gitea` / `private` (use `tea`) · `local` (may or may not have a remote, not a public-hosting provider — see below)
- **Provider inference** — detect from `git remote get-url origin` first, infer from the directory name only as a fallback when there's no remote. Full rule and the `~/Projects/local` / Local System Management Zone conditions: `~/.claude/memory/path_resolution_conventions.md`
- **Git gate** — if `{project_dir}/.git` does not exist, never run any git operation. Check for `.git` first.
- **Project files override global** — if `{project_dir}/CLAUDE.md` or `{project_dir}/AI.md` exists, it supersedes this file
- **Stay inside `{project_dir}`** — all writes and edits must target paths within `{project_dir}` unless the user explicitly names an external path. **A problem inside the project is never sufficient justification on its own** — never edit host system files, shell rc files, systemd units, other repos, or global tool configs to work around a build/test/tool issue; fix the project's own code/config instead. **Exception:** under `~/Projects/local/system/**`, an explicitly-authorized external path/repo can be recorded as a durable, repeatable grant instead of needing to be re-named every session

## Code & Files
- **`cd` always uses absolute paths** in scripts, Makefiles, CI steps, and Claude's own Bash tool calls
- **`\command` prefix** only for alias-prone external binaries, never keywords/builtins/hook-governed commands — full rules: `~/.claude/memory/tool_conventions.md`
- Read current file state before any edit
- **Edit fails on old_string mismatch → re-read the target slice once, then re-edit** — never retry an identical failed Edit
- **Working-set discipline** — scope is set when the user names files/dirs; never expand on your own initiative (exception: spelling/grammar in files already being edited); state the specific reason before editing an unnamed file
- **Fix completeness** — when a pattern changes, `grep -rn` the working set before AND after editing; zero remaining matches (or every match named as an intentional exception) before writing COMMIT_MESS
- Match surrounding style: naming, indentation, patterns; use ecosystem idioms and community linter/formatter
- Use existing standards (POSIX exit codes, HTTP status codes, RFCs, semver, ISO 8601) — never invent wire protocols
- Targeted edits only; full rewrites only when asked; required deps just add them; real choice between alternatives: ask first
- **No partially implemented code** — every committed line must work as written; no stubs, no `TODO` placeholders inside logic
- **No TODO/FIXME/HACK in committed code** · **No commented-out code**
- **Comments always ABOVE, never inline** (single line, ≤180 chars) · **never in JSON / `.env` KEY=VALUE / CSV/TSV / any pure data format** · JS/CSS comments must use valid syntax for the language. Full rules: `~/.claude/memory/comment_conventions.md`
- **Directory naming is language-specific** — Go: singular (`handler/`, `model/`, `middleware/`); all other languages: plural. Tooling dirs always plural (`scripts/`, `tests/`, `completions/`)
- **Reuse before creating** — search for an existing function, variable/constant, UI component, or system config entry before writing a new one; only create when nothing existing fits. Full rules (search-before-write for each category): `~/.claude/memory/reuse_conventions.md`
- **Create parent directories before writing** — `mkdir -p "$(dirname -- "$f")"` (shell) · `os.MkdirAll` (Go) · `fs::create_dir_all` (Rust) · `path.parent.mkdir(parents=True)` (Python) · `fs.mkdirSync(path.dirname(f), {recursive:true})` (Node)
- **Every text file ends with a single trailing newline** — exceptions: `~/.claude/memory/file_ending_conventions.md`
- **Indentation: spaces over tabs (2 default, 4 where the ecosystem standard — Python, Rust)** — tabs ONLY where the filetype requires them (Makefile recipes, Go via `gofmt`)

## Sensitive Data
See `~/.claude/memory/sensitive_data.md` for the full credential policy, repo privacy gate, paste-service rules, and env-var overwrite categories.

Key rules always in effect:
- Never commit tokens, API keys, passwords, or private keys — all repos treated as public by default
- Never store tokens in plaintext — hash with SHA-256; never log raw tokens
- Credential masking — preserve the key name, replace value with `xxxxx`

## Project Files & Naming
- See `~/.claude/memory/project_conventions.md` for AI.md / IDEA.md / CLAUDE.md roles, placeholder system, and directory layout
- See `~/.claude/memory/project_files.md` for README.md requirements, LICENSE.md naming, allowed root files, and what must never be created
- **`TODO.AI.md` hygiene** — complete each item fully before removing; never clear while in progress. **`PLAN.AI.md` hygiene** — delete once work is fully committed
- **No issue left only in conversation** — any flagged-but-not-fixed issue (found during an audit, a review, or incidentally while doing something else) must, before moving on to other work, either be fixed immediately or logged as a line item in `TODO.AI.md` (create it if missing). A commit message, a chat reply, or a summary is not a durable record — conversation context can be compacted or lost. This applies regardless of severity or how small the issue seems; the `audit` agent's >5-issues-to-`AUDIT.AI.md` threshold is a separate, additional rule for large batches, not an exemption from logging smaller ones here
- **`TODO.AI.md` PART loading** — `grep -n "^# PART N" AI.md` to find the slice; read only that slice; never load the full spec file; cross-refs inside the slice: finish the slice first, then follow

## External Contributions
Forks, PRs, and fixes to third-party projects the user does not own follow `~/.claude/memory/external_contributions.md`, which overrides our project-shape and style rules for that repo. Key rules always in effect:
- **Detection** — explicit user statement always wins; otherwise infer with caution ("fork/fix/enhance X" phrasing + repo we didn't create + no `AI.md` in the tree); ambiguous → ask, never assume
- **Upstream conventions win** — match their code style, layout, comments, and indentation exactly; our root-file requirements and convention linters do not apply
- **Task-scoped diffs only** — no drive-by refactors, spelling sweeps, or formatting churn outside lines the task changes
- **Never create our spec/tracking files** (`AI.md`, `TODO.AI.md`, `CLAUDE.md`, `.claude/`, etc.) in their tree — hard ban, not even gitignored
- **Commits still go through `gitcommit`**, but `COMMIT_MESS` is written in the upstream's commit-log style, never our emoji format
- No AI attribution, sensitive-data rules, and destructive-op confirmation never relax in any mode

## Cleanup
- Stop/remove every container, VM, volume, network, and temp file as soon as it is no longer needed
- Track what you start — note name/ID before spinning anything up
- Only remove project-specific resources; never broad sweeps (`docker system prune`, `rm -rf /tmp/*`)
- Full rules: `~/.claude/memory/execution_hierarchy.md`

## Shell Lifetime & Timeouts
Every shell command must be bounded — enforced by `bound-shell-lifetime.sh`. Full rules: `~/.claude/memory/shell_lifetime_conventions.md`
- **The Bash tool `timeout` parameter is in MILLISECONDS** — 60s = `60000`, 300s = `300000`, 600s = `600000`; a raw seconds value (e.g. `30`) means 30 ms and kills the command instantly
- **Timeout tiers** — lookups/status ≤60s · network/package ops ≤300s · builds/tests ≤600s (tool hard max); explicit `timeout` on every Bash call
- **Expected to exceed 600s → run_in_background** from the start; **after a timeout kill, never retry with the same value** — jump a tier or go background
- Never poll harness-tracked work (task-notifications resume it) · bounded polling only · no open-ended sleeps · no `nohup`/`setsid`/`disown` (use run_in_background) · `&` requires `PID=$!` ownership · `tail -f`/`watch` only inside `timeout {n}`

## Verification & Safety
Full rules (temp-dir confirmation exception, hard-denied destructive commands, git-status-deletion caveat, systemctl gate, kill scoping, memory safety): `~/.claude/memory/security_conventions.md`
- Confirm before: `rm -rf`, force pushes, dropping tables/branches, anything irreversible — except disposable project-owned temp/cache dirs
- **Never run unrequested destructive ops, even to "fix"** — stop and ask; a `git status` deletion is not automatically an error to fix
- **Never auto-bypass a hook block** — if a PreToolUse hook returns `BLOCKED:`, tell the user; only they decide whether to proceed
- Verify APIs/flags exist before using them; run code before calling it done; iterate until verification passes

## Self-Validation
- **Define success up front**, then **verify against ground truth** (UI → design; logic → expected output; data → spot-check a sample) and **iterate until passing** — don't stop at "compiles"
- **Add tests for new behavior** — a test that fails before and passes after, then run it
- **One run, then fix** — don't loop on flaky failures without a hypothesis
- **Verification statement required** — before declaring a task done, state the specific ground-truth check performed and its actual result (e.g. "ran `go test ./...`, all pass" or "diffed output against expected.json, matches"); "looks right" or "should work" is not a check and does not count as done

## Build & Execution
- Full rules: `~/.claude/memory/execution_hierarchy.md` · Hierarchy: QEMU/KVM > Incus > Docker > host
- **Never build on the host** — always Docker. Toolchain image selection (project-declared → `Dockerfile.build` → language default, e.g. `casjaysdev/go:latest`) picks the TOOLCHAIN image only, never the runtime image. Full decision tree: `~/.claude/memory/dockerfile_conventions.md` → Toolchain Image — Decision Tree
- **Go, Rust, and Android projects default to NO `docker/Dockerfile.build` or `build-toolchain.yml`** — the casjaysdev images cover virtually every need; a custom `Dockerfile.build` must `FROM` the casjaysdev image (extend, never replace)
- **`$PWD` not `$(pwd)` in shell docker `-v` flags** — `$(pwd)` triggers a permission prompt; in Makefiles `$(PWD)` is correct
- **Go Docker builds require `-e GOFLAGS=-buildvcs=false`** — mounted `.git` UID mismatch fails `go build` with "exit status 128"; full pattern: `~/.claude/memory/go_conventions.md § Docker Build Pattern`
- **Coverage and test output never go to the project tree** — full `{project_org}/{internal_name}-XXXXXX/` tempdir structure: `~/.claude/memory/tempdir_conventions.md`
- Target `linux/amd64` + `linux/arm64` by default; builds reproducible in containers
- **Only one `make` invocation at a time, ever** — never start a second `make` (foreground or background, any target, any repo) while another is still running; concurrent makes race on shared caches, module dirs, and Docker build contexts. `make`'s own internal `-j` parallelism within a single invocation is fine. Wait for the running make to finish (or kill it per kill-scoping rules) before starting the next
- **Script-collection and spec-collection projects are exempt from this section** — no Makefile, no Docker toolchain build, no CI/CD workflow by default; detection criteria and replacement gates: `~/.claude/memory/project_type_conventions.md § Type: script-collection` / `§ Type: spec-collection`
- **Packaging projects (distro/platform package metadata repos): Makefile and CI/CD are optional, not exempt** — builds still always run in per-format containers with format linters as the gate; format matrix and rules: `~/.claude/memory/project_type_conventions.md § Type: packaging`

## UI/UX
- Designer-level intent · dark mode default (support dark/light/auto) · never hardcode colors — CSS custom properties (web) or shared theme struct (desktop/TUI)
- Non-trivial UI tasks → `designer` agent. Full rules: `~/.claude/memory/ui_ux_conventions.md`

## Security & Project Defaults
- Security-by-design rules and memory safety: `~/.claude/memory/security_conventions.md`
- License: MIT · Single self-contained binary · First-run works with zero config
- No feature gating · Telemetry opt-in only · Web UIs mobile-responsive from day one
- Security in code: parameterized queries, constant-time comparison, CSRF/XSS/SSRF/IDOR/path-traversal guards

## Language Constraints
Load the matching file on demand — only when actively working in that language:
- **Go:** `~/.claude/memory/go_conventions.md`
- **Node / TypeScript:** `~/.claude/memory/node_typescript_conventions.md`
- **Python:** `~/.claude/memory/python_conventions.md`
- **Rust:** `~/.claude/memory/rust_conventions.md`
- **Kotlin (non-Android):** `~/.claude/memory/kotlin_conventions.md`
- **Java:** `~/.claude/memory/java_conventions.md`
- **Ruby:** `~/.claude/memory/ruby_conventions.md`
- **PHP:** `~/.claude/memory/php_conventions.md`
- **Swift:** `~/.claude/memory/swift_conventions.md`
- **Dart / Flutter:** `~/.claude/memory/dart_conventions.md`
- **C / C++:** `~/.claude/memory/cpp_conventions.md`
- **C# / .NET:** `~/.claude/memory/csharp_conventions.md`
- **Elixir:** `~/.claude/memory/elixir_conventions.md`

## Output
- No preamble, no reflexive agreement, no closing recap
- Concise but complete — give enough context to understand, but no filler; one clear explanation beats three hedged ones
- **Tight output budget** — status updates: 1–3 sentences max; no headers/bullets unless the task requires structured output
- Show diffs, not prose retellings of changes
- No emojis in code or inline tool output unless asked; emojis are appropriate in READMEs, docs, and commit messages
- **Assume a narrow terminal (~70 columns)** — short lines, no wide tables, compact bullets; prefer stacked prose over side-by-side layouts
- **No AI attribution** — no `Co-Authored-By:`, AI-tool trailers, or "Generated with X" footers anywhere
- Next step is clear → do it; pause only for genuine blockers or destructive-op confirmation

## Tool Preference
See `~/.claude/memory/tool_conventions.md` for internet access rules, curl/wget/grep defaults, provider CLI auto-install rules, `act` usage, and image handling.

Key rules always in effect:
- **Internet access is available and must be used** — fetch docs, versions, READMEs, and any fact that changes over time; never say "I don't have internet access"
- Use the right tool if installed: `jq` (JSON), `yq` (YAML), `bc` (math), `grep`/`sed`/`awk` (text)
- Provider CLIs (`gh`, `glab`, `tea`) over raw `curl` for provider API ops
- `grep` always with `--` before the query; never `egrep`/`fgrep`/`rgrep`

## Token & Context Discipline
- **Explorer subagent for broad searches** — 3+ files, unknown locations, or multiple naming conventions
- **Read files narrowly** — files >500 lines: use `offset`/`limit` or grep first; don't load 2000 lines for 50
- **No speculative reads** — only read files the current task directly requires
- **Don't re-read after editing** — exception: re-read `COMMIT_MESS` once before `gitcommit` to verify it matches the diff
- **Don't spawn agents for small tasks** — 2–3 direct tool calls: do it inline
- **Plan mode for genuine ambiguity only** — not for file count; mechanical changes across many files don't need a plan
- **Parallelize independent research** — spawn agents in parallel (single message, multiple Agent calls)

## Agent Usage
Full rules (smaller scoped units of work, model inheritance, no-subagent-commit, "no edits" ≠ enforcement, fork/subagent scope discipline): `~/.claude/memory/agent_usage_conventions.md`
- **Prefer smaller, scoped units of work** — one file/finding/subtask per dispatch, batch large diffs instead of one sprawling change
- **Model inheritance** — the user picks the model; agents inherit it. Never set `model:` in agent frontmatter, pass a per-spawn `model` override, or pin `model`/`fallbackModel` in settings unless the user asks
- **Agents never commit — hard rule, no exceptions**, mechanically enforced by `no-subagent-commit.sh`
- **Agents never run tests, builds, or gates — hard rule**, mechanically enforced by `no-subagent-gates.sh`: no `make`, test runner, lint gate, or commit gate from a subagent. Self-Validation and the pre-commit gates are the main session's job, run once after the full diff is reviewed; a subagent edits its scoped files and reports back (partial work is never committed because only the main session commits)
- A "no edits" instruction in a prompt is a request, not enforcement — an agent/fork keeps Edit/Write regardless of wording; use `explorer`/`Explore` for a mechanical guarantee
- Fork/subagent scope is exactly what its prompt names — no self-directed coordination, no editing outside scope

## Autonomy
- Action commands ("fix all issues", "run the tests", "deploy") → execute fully without step-by-step confirmation
- "Run X" pre-authorizes X and its entire workflow (subcommands, loops, retries, pipes) for this session — but not a *different* command, and not a destructive/irreversible action X doesn't plainly imply (e.g. "run the tests" does not pre-authorize a force-push, a schema migration, or deleting a branch); if a step falls outside what X plainly means, stop and ask
- Write/Edit allowlists are in `{project_dir}/.claude/settings.json` — pre-approved paths: `.git/COMMIT_MESS`, `CLAUDE.md`, `AI.md`, `SPEC.md`, `IDEA.md`, `TODO.AI.md`, `TODO.md`, `PLAN.AI.md`, `PLAN.md`, `.claude/settings.json`, `.claude/settings.local.json`, `.env`/`app.env`/`default.env`, `.no_push`, `.dockerignore`, `.gitignore`, `.gitattributes`, `.editorconfig`, `.npmignore`, `.eslintignore`, `.prettierignore`

## Task Dependency Ordering
- Dependency graph beats label order (numbered sequence is a tiebreaker only); topological-sort stated dependencies before starting; a task is "ready" only when all prerequisites are complete
- 3+ dependencies → document the resolved order at the top of TODO.AI.md or PLAN.AI.md

## Commit Workflow
`gitcommit --dir {dir} all` (`{dir}` = absolute project root, `all` is the only command, never `-m`/`--message`) is the **only** commit/push path — raw `git commit`/`git push` are denied everywhere, including under the Local System Management Zone's raw-git exception (that exception covers other git commands, never `commit`/`push`; a zone repo that must never publish keeps `.no_push` instead). Never read the `gitcommit` script file — pre-approved and trusted. Creates the remote automatically if missing.

**Pre-commit gates (test, lint, the override escape hatch), COMMIT_MESS format/emoji map, commit-grouping decision order, who-commits, and push behavior:** `~/.claude/memory/gitcommit_conventions.md` — follow it exactly; never commit with a failing test or a NEW lint violation.

**Post-push CI check:** if the project has CI config, check the triggered run's status after every push — a failing build is fixed immediately, never left for later; never report a task done while the pushed build is red or still running. Full check and the workflow gate/creation order: `~/.claude/memory/cicd_conventions.md`.
