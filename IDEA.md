## Project description

climgr/claude is the source repository for global Claude Code configuration — agents, hooks, memory files, and settings deployed to `~/.claude/` on every machine where Claude Code is used. It is the single source of truth for how Claude Code behaves across all projects and sessions. The `home/` directory mirrors `~/.claude/` exactly; `install.sh` syncs it to the live location.

The `climgr` org is strictly for CLI tool configuration repos — mostly AI CLIs (this repo is Claude Code's), but any CLI tool is in scope. It is unrelated to the `claudemgr` org, which holds only the `{lang|type}` template repos (`go`, `rust`, `android`, `docker`, `mgr`) consumed by this repo's agents — those stay in `claudemgr` and are not moving.

## Project variables

project_name: claude
project_org: climgr
internal_name: claude
internal_org: climgr
deploy_target: ~/.claude
source_dir: home

## Business logic

- `home/` mirrors `~/.claude/` exactly — every file/dir inside maps 1:1 to the deployed path
- `home/CLAUDE.md` → `~/.claude/CLAUDE.md` — global AI instructions loaded at every session start across all projects
- `home/memory/` → `~/.claude/memory/` — convention and standards files the AI loads for context; `MEMORY.md` is the index
- `home/agents/` → `~/.claude/agents/` — 21 specialized subagent definitions (frontmatter + instructions markdown); agents span the full development lifecycle from spec migration and bootstrapping through linting, auditing, testing, debugging, and deployment
- `home/hooks/` → `~/.claude/hooks/` — bash scripts executed by Claude Code as PreToolUse/PostToolUse hooks
- `home/settings.json` → `~/.claude/settings.json` — permissions (allow/deny/ask lists), hook wiring, and Claude Code behavior flags
- `install.sh` copies `home/` to `~/.claude/` — always commit changes here before deploying
- Deployed configuration is global: affects every Claude Code session, every project, every repo on the machine
- No build step, no compilation — this repo is purely configuration and shell scripts
- Changes here are high-impact: a broken hook or bad permission can block all Claude Code tool use

**Source-of-truth order (highest wins):**
1. `{project_dir}/AI.md` — full project spec; overrides everything when complete
2. `{project_dir}/CLAUDE.md` — project-level overrides
3. `~/.claude/CLAUDE.md` — global baseline (this repo)

A sparse or minimal `{project_dir}/AI.md` defers to global rules for anything it doesn't cover. A full spec (one that defines the complete implementation for its project type) is authoritative and overrides the global baseline.
