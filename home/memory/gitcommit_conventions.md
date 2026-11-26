---
name: gitcommit conventions
description: gitcommit invocation rules, COMMIT_MESS message format, emoji map, cadence, push behavior, and the pre-commit test/lint gate sequence
type: user
---

Never hardcode the path to `gitcommit` (e.g., `/usr/local/bin/gitcommit`).

**Why:** The binary may live in `~/.local/bin`, `/usr/bin`, or elsewhere depending on the machine. It's always in PATH, so just reference it as `gitcommit`.

**How to apply:** In `{project_dir}/CLAUDE.md`, documentation, or any instruction that references the gitcommit wrapper, write `gitcommit` without a path prefix.

---

**`gitcommit` creates the remote repo automatically.** If the GitHub remote does not exist, `gitcommit` creates it and sets the upstream — no manual `gh repo create` or `git remote set-url` step is needed before or after.

---

**Never read the `gitcommit` script itself.** It is a pre-approved, trusted command — invoke it as documented; never inspect the script file before use. Reading it is a speculative read violation. The invocation contract is fully specified in the Commit Workflow section of `~/.claude/CLAUDE.md`; the script internals are irrelevant.

---

**Never use bare `@` in a commit message body.** Any `@username` in a commit message body creates a GitHub contributor notification and links the handle — even if the intent is just to reference a name. Only use `@username` when intentionally crediting a real contributor. Otherwise write the name without `@`, or wrap it in backticks to prevent GitHub from parsing it as a mention.

---

## Message Format

`{emoji} Title (≤64 chars) {emoji}` + blank line + body + `- path: change` bullets per file.

Emoji map: ✨ feat · 🐛 fix · 📝 docs · 🎨 style · ♻️ refactor · ⚡ perf · ✅ test · 🔧 chore · 🔒 security · 🗑️ remove · 🚀 deploy · 📦 deps

Write `{dir}/.git/COMMIT_MESS` from `git status --porcelain` + `git diff --stat` output — every changed or untracked file described; never write from memory. Re-read `COMMIT_MESS` and compare against the diff before committing — rewrite if anything is missing or wrong. Mechanically enforced by `enforce-commit-mess-coverage.sh`: `gitcommit --dir {dir} all` is blocked while any changed/untracked file in the tree lacks a `- path: change` bullet (a `- dir/: ...` bullet covers files beneath it) — especially relevant after long-running tasks, where the tree accumulates far more files than recent context remembers.

No bare `@` handles and no AI attribution trailers (see above). `gitcommit --dir {dir} spec` commits only markdown spec files; never `-m`/`--message`.

**Never invent a third-party role label** (`operator decision`, `owner decision`, `admin approved`, etc.) to describe who made a change. Claude Code runs as the user's own agent, not a separate operator/service — there is no third party. State the fact plainly instead: "removed at the user's request," "user-deleted, not a regression," or just describe the change with no attribution clause at all when the reason is self-evident from context.

## Cadence

**One commit per "logical change" — but "logical change" means the resolved scope from the grouping decision order below, never "one fix" or "one file" by default.** Do not commit after each individual fix as you go; finish resolving the full scope the decision order below assigns to one commit, then commit once. Mid-task inconsistent state → do NOT commit.

**Grouping decision order — evaluate top to bottom; the first rule that matches decides and sets the commit's scope; the rest never get consulted. Determine the scope BEFORE fixing anything, so you know upfront whether you're building toward one commit or several — never commit reflexively after each individual fix lands:**

1. **User single-commit override.** If the user's request states or implies a single commit — "one commit", "commit it all together", "single commit for this", or equivalent — every change made to satisfy that request goes into exactly one commit, full stop. This overrides every rule below, including the findings-based one-per-finding default and the coupled/independent split test. It never overrides the test gate, the lint gate, or "never commit a broken/inconsistent state" — those still apply before the single commit is made.
2. **Ad hoc "fix X, and fix anything else you find" requests** (not a numbered findings list, not an audit/review output): fix everything found for that request, then make **one commit** covering the primary fix plus whatever related issues were fixed alongside it. This is not a findings-based fix-list (rule 4) even though multiple issues are involved — it is one user request with one scope.
3. **Bug fixes spanning multiple files/dirs — group by actual coupling, not by request wording or session:**
   - **Independent** (fixing bug A in `file1` does not require touching, does not depend on, and is not blocked by bug B in `dir1`) → **separate commits**, one per independent unit.
   - **Coupled** (bug B blocks bug A from being fixable, fixing A requires changes in `dir1` too, or the bugs share a root cause) → **one commit** covering every file the coupled fix touches, described as one bug-fix group.
   - Judge coupling from actual code/dependency relationships (call graph, shared state, blocking order) — never from "found in the same session" or "same file extension/directory."
4. **Findings-based work** (audits, code reviews, punch lists, numbered user fix-lists) is never "one logical change" by default. Each finding is independently fixable and independently verifiable — batching N findings into one commit because they share a file, subsystem, or session hides which findings actually landed and makes a bad fix silently swallow a good one. Default to **one commit per finding**; only combine findings when they are genuinely inseparable (the same line/block, or fixing one is impossible without the other) — this is the same coupling test as rule 3, applied at finding granularity.
5. **Feature work** — one commit for the whole feature: implement it completely, fix every bug that is part of, blocks, or directly affects that feature, then make one commit. Do not split a single feature into per-part, per-subtask, or per-file commits; the feature is the logical unit, not its internals. Bugs found incidentally that are unrelated to the feature do not go in the feature commit — see below.

**Before writing COMMIT_MESS for findings-based work:** re-list every finding by its original ID/number, then for each one grep/diff-check that its specific fix is actually present in the working tree — not just described in a prior message or agent report. A finding with no matching diff hunk is not fixed; do not include it in COMMIT_MESS as done, and do not commit until it's resolved or explicitly deferred (say so to the user, don't silently drop it).

**Unrelated bugs found while building a feature:** do not fix them inline and do not fold them into the feature commit. Log them to `TODO.AI.md` for a later, separate fix.

**Exception — app-breaking bugs found mid-feature:** if the bug breaks the build, crashes the app, or blocks the feature/app from functioning, fix it immediately, in place, before continuing. Committing a broken project is itself a bug — it violates "no partially implemented code."

## Who Commits

**Only the main session ever runs `gitcommit` or raw `git commit`/`git push`.** Agents and subagents — of any type, including forked agents — never commit and never push, under any circumstance, even inside the Local System Management Zone's raw-git exception. Agents also never write `COMMIT_MESS` and never run `make`, tests, lint, or any gate. An agent's job ends at editing its scoped files and reporting back; the main session is the only place that reviews the full diff, writes `COMMIT_MESS`, and invokes the commit. This is a hard rule, mechanically enforced by `no-subagent-commit.sh` (blocks the attempt) — it is not a preference an agent can reason its way around.

## TODO.AI.md Completion

**A committed TODO file must be true at the moment of the commit.** A list that still shows finished work, or already hides unfinished work, is misleading, so the list changes in the same commit as the work.

| Rule | Requirement |
|------|-------------|
| **Same commit** | The item is deleted from `TODO.AI.md` in the same change that completes it, BEFORE `COMMIT_MESS` is written. The commit that resolves a task never leaves that task in the committed file |
| **Fail closed** | The removal lands only with a SUCCESSFUL commit. If a gate, hook or push fails, the task is not done: put the item back, fix the cause, repeat. An item never disappears while its work is uncommitted or failing |
| **Partly done** | An item only partly done is rewritten to the REMAINING work in that commit: never deleted, never left unchanged |
| **Already satisfied** | An item found already satisfied (the code already does it) is removed in the commit that verifies it, and the message names it |
| **New work** | A task discovered while working is added in the commit that discovers it (or fixed immediately), never held back for later |
| **Removed, not marked** | A completed item in `TODO.AI.md` is deleted, never struck through or checked off. In the human-owned `TODO.md` the item is marked done IN PLACE in that same commit, never deleted or emptied by AI |
| **Before every commit** | Re-read `TODO.AI.md`, `TODO.md` and `PLAN.AI.md` (when they exist) and confirm: nothing this commit completes is still open, nothing is listed done that is not implemented, and nothing was removed whose work is not in the commit. `git diff -- TODO.AI.md` shows each removal next to the code that justifies it |
| **Subagents** | A subagent never edits or commits a TODO file; the parent does, after reviewing the diff |

Commit sequence (one order): (1) implement the task. (2) Delete its item from `TODO.AI.md` in that same change, before `COMMIT_MESS` is written. (3) Run `gitcommit`. (4) If the commit fails, put the item back, fix the cause, repeat. (5) The commit that deletes the LAST item uses the title `✅ all todo items have been completed ✅` and a body summarizing what was accomplished, so the file is empty only in that commit.

## Push Behavior

Push is immediate and irreversible, and `gitcommit` creates the remote if missing. To skip: `touch .no_push` (confirm with user first). If push fails offline: run `gitcommit --dir {dir} push` later — do NOT recreate `COMMIT_MESS`.

## Pre-Commit Gates

**Sequence, every commit:**
1. `git status --porcelain` + `git diff --stat` — see actual changes
2. **Test gate** — `make test` (or language equivalent: `go test ./...`, `cargo test`, `pytest`, `npm test`; `script-collection` projects use `bash -n` plus the `script-lint` Agent instead; `spec-collection` projects have no runnable test — verify by re-reading the changed content) must pass — no exceptions, never skip to "save time"
3. **Lint gate** — the `script-lint`/`go-lint`/`rust-lint` Agents (spawn via the Agent tool, never as a shell command — there is no CLI binary by that name) · `npm run lint` (Node/TS) · `ruff check` + `ruff format --check` (Python) · per-format linters for `packaging` projects (`~/.claude/memory/project_type_conventions.md` § Type: packaging). The three Agent-based linters classify each finding as NEW (on a line this session's own uncommitted changes touch) or pre-existing; only NEW findings block — a report ending `0 new issue(s) found` passes even with pre-existing findings listed, which still must be logged to `TODO.AI.md` before moving on. `npm run lint`/`ruff check` have no such split — any output from those still blocks.
4. Write `{dir}/.git/COMMIT_MESS` from that output — every changed file described; never write from memory
5. **Doc-sync line** — for whichever of `IDEA.md`/`README.md` actually exists at `{dir}`'s root, add a status line: `- IDEA.md: updated (<what changed in Business Logic>)` or `- IDEA.md: N/A — no user-facing change` (same for `README.md`) — required by `enforce-doc-sync.sh`
6. Re-read `COMMIT_MESS` and compare against the diff — rewrite if anything is missing or wrong
7. Run `gitcommit --dir {dir} all`

**Hook blocks:** a hook that blocks a commit (test/lint gate, doc-sync, `COMMIT_MESS` coverage) is reported to the user and never bypassed automatically; the override prefixes below are for a user who explicitly directs the bypass after confirming the check passed.

**Explicit bypass — `TEST_LINT_GATE_OVERRIDE=1`:** when the user explicitly says to bypass (skip tests, skip linters, "just commit it", or equivalent), prefix the commit: `TEST_LINT_GATE_OVERRIDE=1 gitcommit --dir {dir} all`. That single prefix skips the test gate, the lint gate and staged-workflow validation (`enforce-test-lint-gate.sh`, `validate-workflows.sh`) so the repo can be committed. It does NOT skip any commit rule: the command shape (`enforce-gitcommit-shape.sh`), `COMMIT_MESS` coverage of every changed file, the doc-sync status lines, the message format, no force-push or history rewrite, and signing through `gitcommit` all still apply. The user's plain statement is enough — no extra confirmation that they verified anything. Never set it on Claude's own initiative just because a gate blocked; "never auto-bypass a hook block" still applies. Background: `enforce-test-lint-gate.sh` blocks `gitcommit` unless the gates ran and passed this session (via `test-lint-mark.sh`'s marker, or its `transcript_path` fallback), and a confirmed upstream Claude Code bug (`anthropics/claude-code#6305`, open) means the marker sometimes never fires even for a genuinely passing run.

**Doc-sync gate (`enforce-doc-sync.sh`):** blocks `gitcommit --dir {dir} all` unless `{dir}/.git/COMMIT_MESS` carries an explicit status line for whichever of `IDEA.md`/`README.md` actually exists at `{dir}`'s root — a forced-acknowledgment gate, not a content-diff heuristic: it only checks a line is PRESENT, never that the claim is true. Accepted forms per file: `- IDEA.md: updated (<what changed in Business Logic>)` or `- IDEA.md: N/A — no user-facing change` (identically for `README.md`). Remember IDEA.md's own WHAT/HOW boundary — only Business Logic changes count as "updated"; a pure tooling/HOW change (e.g. a new hook, a build-script tweak) is legitimately `N/A`. A repo missing one or both files (script-collection/spec-collection projects, third-party forks) only needs to acknowledge whichever file is actually present — never both unconditionally. `DOC_SYNC_GATE_OVERRIDE=1` prefix (e.g. `DOC_SYNC_GATE_OVERRIDE=1 gitcommit --dir {dir} all`) bypasses the gate for that one call, but only when the user specifically directs skipping doc-sync — the doc-sync lines are a commit rule, so a general "bypass tests/linters" never implies it. Never on Claude's own initiative.
