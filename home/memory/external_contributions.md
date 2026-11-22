---
name: External contributions
description: Rules for forks, PRs, and fixes to third-party projects the user does not own — upstream conventions win, task-scoped diffs only, our project-shape rules do not apply
type: user
---

## What This Covers

Work on a project the user did not create and does not own: forking an
upstream repo, fixing a bug in someone else's project, enhancing a
third-party tool, or preparing a PR against an external codebase. In
this mode the repo is a guest house — leave it exactly as its owners
keep it, changed only where the task requires.

## Detection

External-contribution mode applies when EITHER:

1. **The user says so explicitly** — "we're fixing upstream X",
   "prepare a PR against Y", "this is their project". The explicit
   statement always wins, in both directions (it can also force a repo
   back to normal mode).
2. **Inferred with caution** from combined signals — task phrasing
   like "fork X so we can …", "fix X", "enhance X" against a repo we
   did not create, AND the tree has no `AI.md` (our projects always
   carry one). `gh repo view --json isFork,parent` (or provider
   equivalent) confirming a fork relationship, or a remote org that is
   not one of the user's orgs, strengthens the inference.

**When the signals are ambiguous, ask — never silently assume either
mode.** A wrong guess in normal mode litters their repo with our
files; a wrong guess in external mode skips our gates on our own code.

## Rules In Effect

| Area | Rule |
|------|------|
| **AI attribution** | Unchanged and absolute — no `Co-Authored-By:`, no AI-tool trailers, no "Generated with X" anywhere. This rule never relaxes in any mode. |
| **Coding conventions** | The upstream project's existing code wins over ALL of our conventions — naming, indentation (match their tabs/spaces exactly), comment style and placement, directory naming, file layout, error-handling idioms, dependency choices. Read neighboring code first; write code indistinguishable from theirs. |
| **Working-set scope** | Files related to the task ONLY. No drive-by refactors, no spelling/grammar sweeps in files the task doesn't touch, no formatting churn on untouched lines — reviewability of the diff in THEIR review process is the priority. The global "fix spelling in files being edited" rule applies only to lines the task already changes. |
| **Our spec/tracking files** | HARD BAN — never create `AI.md`, `IDEA.md`, `SPEC.md`, `CLAUDE.md`, `AGENTS.md`, `TODO.AI.md`, `PLAN.AI.md`, `AUDIT.AI.md`, `.claude/`, or any other claudemgr-system file inside an external repo, not even gitignored. Task notes live in conversation or in our own local scratch area outside their tree. |
| **Required root files** | None of our root-file requirements apply (`Makefile`, `LICENSE.md`, `README.md` sections, `.gitignore` header format, release.txt, Jenkinsfile, workflows). Never add, rename, or restructure their project files to match our layout. |
| **Tests** | Add/extend test files ONLY if the project already has a test suite — then follow its framework, naming, and placement exactly. A project with no tests gets no new test scaffolding from us unless the upstream maintainers asked for it. |
| **Gates** | Upstream gates only — run the project's own linters, formatters, test runner, and CI checks (whatever their docs/CI config define). Our `script-lint`/`go-lint`/`rust-lint` and convention gates do NOT apply where they encode our conventions. If the project defines no gate, verify by building/running per their README. |
| **Commit style** | Upstream's commit-log style, via `gitcommit` — study `git log` for their format (conventional commits, subject casing, body style, sign-offs) and write `COMMIT_MESS` in THAT style. Our emoji title format is never used in an external repo. `gitcommit --dir {dir} all` remains the only commit path. |
| **Branching/PR flow** | Follow the upstream contribution docs (`CONTRIBUTING.md`, PR templates, DCO/CLA requirements). Work on a feature branch, never their default branch. |
| **Sensitive data** | Unchanged — all public-repo credential rules apply at full strength; an external repo is by definition not covered by any private-zone exception. |

## What Never Relaxes

No AI attribution · destructive-op confirmation · secret/credential
rules · hook blocks · agents-never-commit. External mode changes whose
conventions apply — it never lowers safety.
