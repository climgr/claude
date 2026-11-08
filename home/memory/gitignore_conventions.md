---
name: .gitignore conventions
description: Format, structure, and standard entries for .gitignore files in CasjaysDev projects
type: user
---

## Format

**Header line** (first line):
```
# gitignore created on MM/DD/YY at HH:MM
```

**Second line** — always present, suppresses dir-message prompt in some git tools:
```
ignoredirmessage
```

Sections are separated by a blank line and a `# comment` describing the group.

## Standard Entries

Every project `.gitignore` includes these:

```gitignore
# gitignore created on MM/DD/YY at HH:MM
ignoredirmessage

# ignore commit message
**/.gitcommit

# ignore build failure markers
**/.build_failed*

# ignore backup files
**/*.bak

# ignore push/git control files
**/.no_push
**/.no_git

# ignore install markers
**/.installed

# ignore work in progress scripts
**/*.rewrite.sh
**/*.refactor.sh

# ignore dotenv files
.env
app.env
default.env

# ignore log and temp files
*.log
*.tmp
*.temp

# OS generated files
### Linux ###
*~
.fuse_hidden*
.directory
.Trash-*
.nfs*

### macOS ###
.DS_Store?
.AppleDouble
.LSOverride
._*
.DocumentRevisions-V100
.fseventsd
.Spotlight-V100
.TemporaryItems
.Trashes
.VolumeIcon.icns
.com.apple.timemachine.donotpresent
.AppleDB
.AppleDesktop
Network Trash Folder
Temporary Items
.apdisk
*.icloud

### Windows ###
Thumbs.db
Thumbs.db:encryptable
ehthumbs.db
ehthumbs_vista.db
*.stackdump
[Dd]esktop.ini
$RECYCLE.BIN/
*.cab
*.msi
*.msix
*.msm
*.msp
*.lnk
```

## Project-Type Additions

Add these for projects that use them:

```gitignore
# Docker compose local override (auto-loaded by `docker compose`, may contain sensitive data)
compose.override.yml

# rootfs build directory
rootfs

# Go build output
binaries/
releases/

# Rust build output
target/
binaries/
releases/

# Runtime volume data — NEVER commit (see compose rules below)
volumes/
docker/volumes/

# AI tool — Claude Code (personal/secret only)
.claude/settings.local.json
# Claude Code runtime files — session data, edit history, backups, cache
.claude/backups/
.claude/cache/
.claude/file-history/
.claude/history.jsonl
.claude/.credentials.json
.claude/projects/
.claude/statsFile
.claude/*.lock

# AI tool — Cursor (personal/secret only)
.cursor/settings.json

# AI tool — Windsurf (personal/secret only)
.windsurf/settings.json

# AI tool — Aider (history and cache; conf and ignore are committed)
.aider.chat.history.md
.aider.input.history
.aider.llm.history
.aider.tags.cache.v3/

# AI tool — Continue (personal data; config.json is committed)
.continue/dev_data/
.continue/session.json
.continue/index/

# AI tool — Codeium / Windsurf cache
.codeium/

# AI tool — Cline / Roo (cache only; rules files are committed)
.cline/cache/

# AI tool — generic catch-all for personal/secret AI directories
.ai/
```

## AI tool config — committed vs gitignored

The same logic applies to every AI tool: **team config is committed; personal overrides and credentials/cache are gitignored.** The pattern Claude Code uses (`settings.json` committed, `settings.local.json` gitignored) is the model for every other tool.

| Tool | Committed (team config) | Gitignored (personal / cache / secret) |
|------|------------------------|----------------------------------------|
| Claude Code | `.claude/settings.json`, `.claude/CLAUDE.md`, `.claude/commands/`, `.claude/agents/`, `.claude/hooks/`, `.claude/plans/` | `.claude/settings.local.json` |
| Cursor | `.cursor/rules/`, `.cursor/mcp.json`, `.cursorignore`, `.cursorrules` (legacy) | `.cursor/settings.json` |
| Windsurf | `.windsurf/rules/`, `.windsurfrules`, `.codeiumignore` | `.windsurf/settings.json` |
| Aider | `.aider.conf.yml`, `.aiderignore` | `.aider.chat.history.md`, `.aider.input.history`, `.aider.llm.history`, `.aider.tags.cache.v3/` |
| GitHub Copilot | `.github/copilot-instructions.md` | (no personal files in repo) |
| Continue | `.continue/config.json`, `.continue/prompts/` | `.continue/dev_data/`, `.continue/session.json`, `.continue/index/` |
| Codeium | `.codeiumignore` | `.codeium/` |
| Cline / Roo | `.clinerules`, `.roomodes` | `.cline/cache/` |

**Rule:** never gitignore a tool's entire directory — pinpoint only the personal/secret/cache files. Blanket-ignoring `.cursor/` or `.windsurf/` would also ignore the rules/team config that should be committed.

**`.claude/` rule (canonical example):** `.claude/settings.local.json` is gitignored (personal overrides and any local-only credentials). Everything else under `.claude/` — `settings.json`, `CLAUDE.md`, `commands/`, `agents/`, `hooks/`, `plans/` — is committed.

**Docker Compose and `.dockerignore` rules** are in `~/.claude/memory/dockerfile_conventions.md`.

## Language-specific additions

Add these for projects that use them:

```gitignore
# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd
.venv/
venv/
env/
dist/
build/
*.egg-info/
.eggs/
*.egg

# Node.js / JavaScript / TypeScript
node_modules/
.npm/
dist/
.cache/
*.tsbuildinfo
```

## What is NOT ignored

- `.env.example`, `.env.sample`, `app.env.example`, `app.env.sample`, `default.env.example`, `default.env.sample` — committed; they are safe templates
- `!*/README*` — README files are always kept
- `.claude/settings.json`, `.claude/CLAUDE.md`, `.claude/plans/`, `.claude/commands/`, `.claude/agents/`, `.claude/hooks/` — committed; only `settings.local.json` is ignored
- AI tool team rules — `.cursor/rules/`, `.cursorignore`, `.cursorrules`, `.windsurf/rules/`, `.windsurfrules`, `.codeiumignore`, `.aider.conf.yml`, `.aiderignore`, `.github/copilot-instructions.md`, `.continue/config.json`, `.clinerules`, `.roomodes` — committed

