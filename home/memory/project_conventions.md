---
name: Project file conventions
description: Full spec for AI.md, IDEA.md, CLAUDE.md, and related files; template system in claudemgr
type: user
---

## Project root (`{project_dir}`)

`{project_dir}` is resolved once at session start:
- Inside a git repo → `git rev-parse --show-toplevel` (the git root)
- Not a git repo → the directory Claude was launched from (`$PWD` at session start)

All relative file references (`AI.md`, `./src`, `./`) resolve from `$PWD`. Absolute paths (`/…`, `~…`) are taken as-is.

**Project files override global:** if `{project_dir}/CLAUDE.md` or `{project_dir}/AI.md` exists, it is the source of truth for that session and supersedes any global equivalent.

**Stay inside `{project_dir}`:** all writes and edits must target paths within `{project_dir}` unless the user explicitly names an external path. Never reach outside the project tree (e.g. `~/.claude/`, `/etc/`, another repo) on own initiative, even when a file there "should" be updated as a side effect of the task.

---

## File roles

| File | Role | Mutable during work? |
|------|------|----------------------|
| **AI.md** | THE HOW — implementation spec, readonly copy of the type template (go/ or rust/). Never modified after initial copy. Placeholders resolve from IDEA.md at runtime. When the template is updated in claudemgr, re-copy this file — no merge needed because it was never touched. | No |
| **SPEC.md** | Project-specific rule overrides — the only place where project rules may contradict the template or global conventions. Created at project setup (may be empty); content added only when a rule must actively differ. SPEC.md wins over AI.md which wins over global CLAUDE.md. | Yes — only when adding or changing rule overrides |
| **IDEA.md** | THE WHAT — project intent, goal, and constraints only. Never the HOW. Three required sections (see below). | Yes |
| **TODO.AI.md** | AI-owned task list. Required when working on more than 2 items. Completed items are REMOVED (not marked done and left). | Yes |
| **TODO.md** | Human-owned task list; AI **must** mark done when completed (leaving unmarked is misleading), never delete/empty entries | Limited |
| **PLAN.AI.md** | AI-owned implementation plan — delete when the work it describes is fully committed | Yes |
| **PLAN.md** | Human-owned plan; AI **must** mark done when completed, never delete entries or rewrite wholesale | Limited |
| **CLAUDE.md** | Short loader pointing at AI.md and IDEA.md. No project-specific spec or rule content. | No |

## Rule hierarchy (highest precedence first)

```
SPEC.md          ← project-specific rule overrides (wins over everything below)
AI.md            ← type template (wins over global)
Global CLAUDE.md ← baseline for all projects
```

SPEC.md > AI.md > global CLAUDE.md. When files conflict, fix the lower-precedence file.

**If SPEC.md and AI.md conflict, SPEC.md wins — that is its purpose.**
**If AI.md and IDEA.md conflict, AI.md wins. Fix IDEA.md.**

**The WHAT/HOW boundary is strict:**
- IDEA.md answers: what is this project, what must it do, what must it never do, what must it be compatible with
- AI.md answers: how to build it, how to structure the code, how to test it, which tools and patterns to use
- If content describes an implementation decision → it belongs in AI.md, not IDEA.md

### AI tool config files (Claude Code, Cursor, Windsurf, Aider, Copilot, Continue, etc.)

All AI tool configs follow the same split: **team config is committed; personal overrides, history, and cache are gitignored.** The canonical example is `.claude/settings.json` (committed) vs `.claude/settings.local.json` (gitignored). The same rule applies to every other tool. The full per-tool table — what to commit and what to ignore — is in `~/.claude/memory/gitignore_conventions.md`.

**New project detection:** if AI.md or IDEA.md is missing → new project. Plan first: create IDEA.md, copy TEMPLATE.md as AI.md, write PLAN.AI.md and TODO.AI.md before touching code.

**Partial IDEA.md:** if IDEA.md exists but is missing one or more of the three required sections, do not proceed with work — add the missing sections first. Ask the user for the missing information rather than guessing. A partial IDEA.md is treated as absent for the section(s) it is missing.

## IDEA.md required layout (exactly three top-level sections, in this order)

```
## Project description
(Elevator pitch — who, what, why. Free-form prose. What the project IS, not how it works.)

## Project variables
(key: value pairs, lower_snake_case keys. Minimum required: project_name, project_org,
internal_name, internal_org. Add extras as needed: app_name, official_site, etc.)

## Business logic
(THE WHAT only — never the HOW. Valid content:
  - Features the project must have
  - Features it must NOT have
  - Compatibility requirements: "must be 100% compatible with X", "must interoperate with Y"
  - Feature parity requirements: "feature 1:1+ with Z" (at least as capable, can exceed)
  - Roles and user types that exist (not how auth is implemented)
  - Constraints and non-negotiables: "must work offline", "must run on single binary"
  - Trust boundaries: what is trusted, what is untrusted
  - Abuse cases and threat actors the project must defend against

Invalid in IDEA.md (belongs in AI.md):
  - Data models and schema definitions
  - API route structure
  - Implementation patterns or technology choices
  - Security implementation decisions (how to achieve a security property, not what it must be)
  - Anything describing HOW the project is built)
```

## Placeholder system

Placeholders in AI.md (e.g., `{project_name}`, `{PROJECT_ORG}`) are **reference tokens resolved at runtime from IDEA.md `## Project variables`**. AI.md itself stays read-only — placeholders are NOT substituted into the file at copy time.

| Placeholder | Mutability | On-disk use? |
|-------------|------------|--------------|
| `{project_name}` / `{PROJECT_NAME}` | Mutable (project may rename) | No |
| `{project_org}` / `{PROJECT_ORG}` | Mutable | No |
| `{internal_name}` / `{INTERNAL_NAME}` | **Stable** at first-time setup | Yes — config/data/cache dirs, systemd units |
| `{internal_org}` / `{INTERNAL_ORG}` | **Stable** at first-time setup | Yes — Bundle IDs, package IDs |
| `{plist_name}` | Derived, not stored: `io.github.{internal_org}.{internal_name}` | Yes |

**internal_name and internal_org are set once (initial value = project_name/project_org) and stay stable across ordinary renames. They reset only on an explicit user-directed org/repo rename (update IDEA.md, grep every consumer, migrate on-disk paths and units) or at a fork's first setup (reset to the fork's own `{project_name}`/`{project_org}`); a reset of a shipped project must migrate on-disk identifiers.**

## Template system

- There are Go, Rust, and Android project templates. When starting a new project, copy the appropriate template as `AI.md`
- The copied `AI.md` is immediately read-only; project-specific values go in `IDEA.md`
- Also create an empty `SPEC.md` at project setup — it stays empty until a rule must contradict the template or global
- Template updates: re-copy the template over `AI.md` directly (no merge needed — `AI.md` was never modified)

## First-time setup flow

1. Check if IDEA.md exists with all required `## Project variables` entries
2. If not: detect values from directory structure (`basename "$PWD"`, `basename "$(dirname "$PWD")"`) — never guess
3. Confirm with user before writing
4. Create/update IDEA.md; set internal_name = project_name and internal_org = project_org (stable immediately)
5. If an existing CLAUDE.md has real project details, migrate them into IDEA.md; keep CLAUDE.md as a short loader only

## Directory layout

```
{project_name}/
├── src/          # source code (Go, Rust, etc.)
├── app/          # source code (Android/Kotlin)
├── scripts/      # dev and install scripts (always committed)
├── tests/        # test runners and helpers (always committed)
├── deps/         # optional; committed, project-specific support files not
│                 # part of the build/release output itself (e.g. scripts or
│                 # Dockerfiles for building a dependency) — never a cache,
│                 # never temp/output; document its use in README/SPEC/IDEA
│                 # or the dir itself
├── docker/
│   ├── Dockerfile
│   ├── Dockerfile.dev
│   ├── docker-compose.yml
│   └── rootfs/   # files ADDed into image, mirroring Linux FHS
│       ├── etc/
│       └── usr/local/bin/   # entrypoint.sh, etc.
├── AI.md
├── IDEA.md
├── CLAUDE.md
└── ...
```

Temp, debug, and test output: `/tmp/{project_org}/{internal_name}-XXXXXX` — never committed. (`{internal_name}` is the stable on-disk identifier, never `{project_name}` which may change.)

## Task dependency ordering

When a task list has dependencies, execution order must respect them before sequence order.

**Rule:** resolve the dependency graph first; numbered/lettered order is a default tiebreaker only, not an execution mandate.

**Example:** tasks 1, 2, 3 and a, b, c where c→2 and a→2 (c and a must complete before 2):

```
Correct order: 1, a, c, 2, b, 3   (a and c unblock 2; 1 has no deps so runs first)
Wrong order:   1, 2, 3, a, b, c   (2 runs before its prerequisites)
```

**Rules:**
- Before starting any task list, scan for stated dependencies ("X before Y", "requires X", "needs X first")
- Build a mental dependency graph; topological-sort it; use label order only to break ties among tasks at the same depth
- If a dependency is ambiguous, ask before executing — never assume order
- Document the resolved order at the top of TODO.AI.md or PLAN.AI.md when the graph is non-trivial (3+ dependencies)
- A task is only "ready" when all its prerequisites are in a completed state

---

## Compliance schedule (per AI.md)

- Session start: read AI.md if starting a new project, returning after a long break, or after context compaction — otherwise load only what the current task requires
- Before each task: read only the parts of the spec directly relevant to what you are about to implement; do not pre-load the whole file speculatively
- Every 3–5 changes: verify the work against spec by reading only the sections that cover those changes
- Before task completion: check compliance against the relevant spec sections
- When uncertain about a spec requirement: read that specific section — never guess, never rely on memory of a prior session

**Hook-enforced, not just advisory:** this closes the gap where the schedule above was previously prose-only and easy to drift from.
- **What's gated:** in any project with an `AI.md` or `SPEC.md` at its root, `spec-guard.sh` (PreToolUse on Write/Edit) blocks edits to project files until `spec-guard-mark.sh` (PostToolUse on Read) has recorded a Read of that project's `AI.md` or `SPEC.md` this session.
- **What's exempt:** meta files (`AI.md`, `IDEA.md`, `SPEC.md`, `CLAUDE.md`, `TODO(.AI).md`, `PLAN(.AI).md`, `.claude/*`, `.git/*`, etc.) — only implementation files are gated.
- **When the marker clears:** `post-compact.sh` clears the marker on every compaction, so the spec must be re-read after each compact before edits resume.

**Existence precedence in the gate:** `AI.md` (THE HOW, primary spec) > `CLAUDE.md` (loader — its presence without `AI.md`/`SPEC.md` means a broken bootstrap, not an ungoverned project) > `SPEC.md` (rule overrides; gates on its own if `AI.md` is absent too). A project with none of the three is treated as ungoverned and never gated. A project with a `CLAUDE.md` loader but no `AI.md`/`SPEC.md` is blocked with a distinct message telling the AI to bootstrap `AI.md` first — per this file's own `CLAUDE.md` definition (a loader always implies a spec it points at), a loader with nothing to load is a broken setup, not a green light for unrestricted edits.

## Language-specific implementation rules

For language-specific build rules, binary naming, Makefile targets, and code conventions see the dedicated files: `~/.claude/memory/go_conventions.md` and `~/.claude/memory/rust_conventions.md`.
