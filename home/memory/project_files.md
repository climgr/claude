---
name: Project file rules
description: Forbidden files/dirs, allowed root files, README.md layout and content requirements, documentation sync rules
type: user
---

## Enforcement Rule

**Forbidden = flag and report, not auto-delete.**

When a forbidden file or directory is found:
1. Tell the user: what it is, why it's forbidden, and where it belongs instead (if anywhere)
2. Wait for explicit confirmation before removing or moving anything
3. Never silently delete — a forbidden file might contain unreplicated work

The only exception: report-only files created by AI itself during the current session (`AUDIT.AI.md` when all issues are resolved, `PLAN.AI.md` scratch files, etc.) may be deleted without confirmation because AI created them and knows their contents.

---

## File Naming Rules

- Documentation is **always** `README.md` — no other casing or name
- License is **always** `LICENSE.md` — project license first, third-party attributions at the bottom

## Forbidden Files

| File | Reason |
|------|--------|
| `SUMMARY.md` | Unnecessary — `AI.md` is the spec |
| `COMPLIANCE.md` | Unnecessary — compliance is in `AI.md` |
| `NOTES.md` | Use `PLAN.md`, `PLAN.AI.md`, `TODO.md`, or `TODO.AI.md` as appropriate |
| `AUDIT.md`, `REPORT.md`, `ANALYSIS.md` | Don't create report-only docs — fix issues directly. Temporary `AUDIT.AI.md` is the explicit-audit exception |
| `CONTRIBUTING.md` in root | Belongs in `.github/` (allowed there) |
| `CODE_OF_CONDUCT.md` in root | Belongs in `.github/` (allowed there) |
| `SECURITY.md` in root | Belongs in `.github/` (allowed there) |
| `PULL_REQUEST_TEMPLATE.md` in root | Belongs in `.github/` (allowed there) |
| `Dockerfile` in root | Belongs in `docker/Dockerfile`. **Exception:** `{project_dir}/Dockerfile*` (e.g. `Dockerfile`, `Dockerfile.build`, `Dockerfile.10-dev`) is allowed at root when the repo has no language-project manifest at root (no `go.mod`, `package.json`, `Cargo.toml`, etc.) — such a repo has no `docker/` convention to conflict with, since the whole repo IS the Docker build context. This holds for any repo shaped that way, not a fixed list of names |
| `compose.yml` in root | Belongs in `docker/compose.yml`. **Exception:** `{project_dir}/*compose*.y?ml` (e.g. `compose.yml`, `compose.dev.yml`) is allowed at root under the same no-language-manifest exception as `Dockerfile*` above |
| `*.example.*`, `*.sample.*` | No example files — defaults are embedded in the binary. **Exception:** `.env.example`, `.env.sample`, `app.env.example`, `app.env.sample`, `default.env.example`, `default.env.sample` are allowed — they are safe templates for users to copy |
| `server.yml`, `cli.yml` | Config files are runtime-generated, never in repo |
| `.env`, `app.env`, `default.env` | Never committed — must always be in `.gitignore`. Use `.env.example` / `.env.sample` variants for committed templates |
| `.claude/settings.local.json` | Personal Claude Code overrides — gitignored, never committed |
| `.claude/backups/`, `.claude/cache/`, `.claude/file-history/`, `.claude/history.jsonl`, `.claude/projects/`, `.claude/statsFile`, `.claude/*.lock` | Claude Code runtime files — gitignored, never committed |
| `.cursor/settings.json` | Personal Cursor settings — gitignored, never committed |
| `.windsurf/settings.json` | Personal Windsurf settings — gitignored, never committed |
| `.aider.chat.history.md`, `.aider.input.history`, `.aider.llm.history` | Aider personal history — gitignored, never committed |
| `.aider.tags.cache.v3/` | Aider symbol cache — gitignored, never committed |
| `.continue/dev_data/`, `.continue/session.json`, `.continue/index/` | Continue personal data and indexes — gitignored, never committed |
| `.codeium/` | Codeium auth/cache — gitignored, never committed |

**`CHANGELOG.md` is allowed** at any path — root, `.github/`, or anywhere else. It is not a forbidden report-only doc; it is a release log distinct from GitHub/Gitea releases and may coexist with them.

`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `PULL_REQUEST_TEMPLATE.md` are also allowed under `docs/` (MkDocs/static-site content pages, e.g. `docs/security.md`) in addition to `.github/` — a docs-site page with one of these names is not the GitHub community-health file it shares a name with.

## Forbidden Basenames & Extensions (credentials / OS detritus)

Writing any of these requires explicit user confirmation first, regardless of directory — deny wins over any allowlist above:

| Basename (case-insensitive) | Reason |
|------|--------|
| `.netrc` | Plaintext credential store |
| `credentials.json`, `service-account.json`, `service_account.json` | Cloud provider credential files |
| `secrets.json`, `secrets.yaml`, `secrets.yml` | Generic secrets files |
| `id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa` | SSH private keys. **Not** their `.pub` counterparts — public keys are not secrets and are always allowed |
| `.ds_store`, `thumbs.db`, `desktop.ini` | OS detritus — belongs in `.gitignore` (`gitignore_conventions.md`), and is also blocked at write-time here as defense in depth |

| Extension (case-insensitive) | Reason |
|------|--------|
| `.pem`, `.key`, `.p12`, `.pfx`, `.jks`, `.p8`, `.ppk` | Private key / certificate bundle formats |

| Path pattern | Reason |
|------|--------|
| `.aws/credentials` | AWS credential file |
| `.ssh/id_*` (excluding `.pub`) | SSH private key by path |

## Forbidden Directories

| Directory | Reason |
|-----------|--------|
| `config/` in root | Config is embedded, runtime-generated in OS dirs |
| `data/` in root | Data goes to OS data directory at runtime |
| `logs/` in root | Logs go to OS log directory at runtime |
| `tmp/`, `temp/` in root | Use `/tmp/{project_org}/{internal_name}-XXXXXX/` |
| `test-data/` in root | Test data goes to temp directories |
| `build/`, `dist/`, `out/` | Use `binaries/` (gitignored) |
| `vendor/` | Use language module system (Go modules, Cargo.lock) |
| `node_modules/` | Never committed |
| `lib/`, `libs/` at repo root | Use proper language package structure; `lib/` nested under `src/` or similar is acceptable |
| `utils/`, `common/` | Use specific, descriptive package names |

**Note:** `src/data/` is allowed for static files embedded in the binary. Only root-level `data/` is forbidden.

**Scope:** this table assumes a {lang}/{framework} shippable-binary project (its rationale column — "embedded, runtime-generated in OS dirs", "proper language package structure" — presumes a compiled runtime and an OS install target). It does not apply to `script-collection` or `spec-collection` repos (`~/.claude/memory/project_type_conventions.md`), which have no compiled runtime and can legitimately ship a root-level `config/`, `data/`, `lib/`, etc. as part of what they distribute — `no-forbidden-files.sh` detects this by checking for a language manifest file (`go.mod`, `Cargo.toml`, `package.json`, `pyproject.toml`, etc.) at the repo root and skips this directory check when none is present.

## `docker/rootfs/` Contents

`docker/rootfs/` mirrors the Linux FHS — it is `COPY`'d into the image at `/`. Acceptable paths inside it:

| Path | Purpose |
|------|---------|
| `etc/logrotate.d/{project_name}` | logrotate config |
| `etc/systemd/system/{project_name}.service` | systemd unit (Incus/VM builds only) |
| `etc/cron.d/{project_name}` | cron job (if needed) |
| `usr/local/bin/entrypoint.sh` | Required — container startup script |
| `usr/local/bin/{additional_scripts}` | Helper scripts bundled with the image |
| `usr/local/share/{project_name}/` | Static data files |

**Never place in `docker/rootfs/`:**
- Source code (belongs in `src/`)
- Credentials or `.env` files
- Files that belong in the OS package manager (`/usr/bin/`, `/bin/`) — use `/usr/local/bin/` instead
- Large binary blobs — embed them in the binary at build time instead

## Allowed Root Files

This table covers files Claude actively manages and files with non-obvious placement rules. It is **not exhaustive** — language module files (`go.mod`, `Cargo.toml`, `package.json`, etc.), standard tooling configs, and project source directories (`src/`, `cmd/`, `docker/`, etc.) are implicitly allowed. Unknown files are **not** automatically forbidden; only files listed in the Forbidden tables above are flagged.

| File / Dir | Category | Required | Purpose |
|------------|----------|:--------:|---------|
| `AI.md` | Spec | ✓ | Project specification (THE HOW) — readonly template copy |
| `IDEA.md` | Spec | ✓ | Project description, variables, business logic (THE WHAT) |
| `SPEC.md` | Spec | | Project-specific rule overrides — only add content when a rule must contradict the template or global default |
| `CLAUDE.md` | Spec | ✓ | Short loader — points at `AI.md` and `IDEA.md` |
| `README.md` | Docs | ✓ | Public documentation |
| `LICENSE.md` | Docs | ✓ | Project license + third-party attributions — not required under `~/Projects/local/system/**` (see `local_system_zone.md`) |
| `CHANGELOG.md` | Docs | | Release history — allowed at any path (root, `.github/`, etc.) |
| `Makefile` | Build | ✓ | Build entrypoint |
| `release.txt` | Version | | Canonical version string |
| `version.txt` | Version | | Alias for `release.txt` — some projects use this name |
| `site.txt` | Meta | | Official site/homepage URL |
| `PLAN.md` | Planning | | Human-owned project plan |
| `PLAN.AI.md` | Planning | | AI-owned implementation plan — deleted once work is fully committed |
| `TODO.md` | Planning | | Human-owned task list |
| `TODO.AI.md` | Planning | | AI-owned task list — required when tracking 3+ tasks |
| `.gitignore` | VCS | ✓ | Git ignore rules |
| `.gitattributes` | VCS | | Git attribute overrides (line endings, diff drivers, linguist hints) |
| `.github/` | VCS | | GitHub-specific files (workflows, issue/PR templates, etc.) |
| `.claude/` | AI tool | | Project-level Claude Code config — `settings.json` committed; `settings.local.json` gitignored |
| `.aider.conf.yml` | AI tool | | Aider config — committed |
| `.aiderignore` | AI tool | | Aider ignore rules — committed |
| `.cursorrules` | AI tool | | Cursor rules — committed |
| `.editorconfig` | Tool config | | Editor formatting rules — settings must match the project's existing style |
| `.no_push` | Flag file | | Signals `gitcommit` to commit locally without pushing — gitignored, never committed |
| `.no_git` | Flag file | | Signals tooling to skip git operations entirely — gitignored, never committed |
| `.installed` | Flag file | | Marks a project as installed on this machine — gitignored, never committed |
| `install.sh` | Script | | Standalone installer — allowed when the repo is primarily an install script |
| `contrib/` | Dir | | Community contributions, examples, and third-party integrations — not covered by the main test/lint gates |
| `deps/` | Dir | | Optional, committed, project-specific support files not part of the build/release output itself (e.g. scripts or Dockerfiles for building a dependency) — never a cache or temp/output dir; usage documented in README/SPEC/IDEA or the dir itself |

---

## README.md Requirements

`README.md` is public documentation — written for users, not developers. Apply designer-level intent: clear, scannable, and complete. Emojis are welcome where they aid readability or navigation.

**Always valid Markdown** — README.md must be syntactically correct Markdown at all times. No bare HTML, no broken link syntax, no unclosed fences.

**Always in sync** — README.md reflects the current state of the project. Stale docs are a bug.

**Production before development** — users who want to run the project should never have to scroll past dev setup to find the install instructions.

### Canonical section order

```
# {Project Name}

{one-paragraph description — what it does, for whom, why it exists}

🌐 **Site:** {official URL}   ← only if site.txt exists; omit otherwise

---

## 📦 Install

{platform-complete download/install instructions — see platform coverage rule below}

---

## 🐳 Docker                ← only if docker/compose.yml exists

{docker compose up / pull instructions; image name; env var overrides}

---

## 🖥️ {Client CLI}          ← only if the project ships a CLI client binary

{usage, flags table, example invocations}

---

## 🤖 {Agent}               ← only if the project ships an agent / daemon / server

{how to run, config, systemd/launchd unit if applicable}

---

## {Other sections}         ← API docs, web UI, configuration reference, etc. as needed

---

## 🛠️ Development

{build from source, prerequisites, make targets table, test commands}

### 🐳 Docker build          ← only if docker/ directory exists

{how to build and run the image locally; docker buildx command; image tag convention}

---

## 📄 License

{license name} — see [LICENSE.md](LICENSE.md)
```

**Section rules:**

- `# {Project Name}` is always H1 — the only H1 in the file
- Description paragraph immediately follows the H1 — no section header wrapping it
- Official site line is present only when `site.txt` exists at the project root; read it and use the URL verbatim
- `## Install` (or equivalent production section) comes **before** `## Development` — always
- Conditional sections (`Docker`, `Client CLI`, `Agent`) are included only when the project actually ships that component; detect by checking for `docker/compose.yml` (Docker section) and `docker/Dockerfile` (Docker build subsection); omit entirely if not applicable
- `## Development` is always the last substantive section, immediately before `## License`
- `## License` is always the final section — omitted entirely under `~/Projects/local/system/**`, where `LICENSE.md` is not required (see `local_system_zone.md`)
- Emojis in section headers are appropriate and encouraged; keep them consistent within a file
- No `## Table of Contents` — headings are the navigation; ToC adds noise for short-to-medium READMEs

### Badges

Badges appear at the top of the README, immediately after the H1 title and description paragraph.

**Every badge MUST be a linked badge** — `[![alt](image_url)](link_url)` is the only valid form. A bare `![alt](image_url)` with no wrapping link is never acceptable for a badge. A badge that does not link anywhere is useless noise.

**Each badge links to the resource it represents:**

| Badge | Links to |
|-------|----------|
| CI / build status | CI runs page (e.g. `…/actions/workflows/ci.yml`, `…/-/pipelines`, Jenkins job page) |
| Release / version | Releases page (e.g. `…/releases`) |
| License | `LICENSE.md` in the repo root |
| Docs | Documentation site URL |
| Any other badge | The most relevant page for the metric being displayed |

**The CI badge MUST match the actual hosting platform** — detect by checking for workflow files: `.github/workflows/*.yml` → GitHub Actions; `.gitea/workflows/*.yml` → Gitea/Forgejo; `.gitlab-ci.yml` → GitLab CI; `Jenkinsfile` → Jenkins. Never use a GitHub Actions badge for a GitLab or Gitea project.

### Install section — platform coverage rule

**The install section MUST cover every platform the project builds for.** Covering one platform when the Makefile builds eight is a documentation bug.

**How to determine the build matrix:**

- **Go projects** — inspect the Makefile for GOOS/GOARCH loops or explicit platform targets. Default is 8 platforms (see `go_conventions.md`): linux/darwin/windows/freebsd × amd64/arm64.
- **Rust projects** — inspect the Makefile for target triples. Default platforms are in `rust_conventions.md`.
- If in doubt, run `grep -E 'GOOS|GOARCH|target.*triple|linux|darwin|windows|freebsd' Makefile` and document what you find.

**Required install section structure:**

```markdown
## Install

Download the latest release from [GitHub Releases](https://github.com/{org}/{project}/releases/latest).

### Linux
| Arch | Binary |
|------|--------|
| amd64 | `{project_name}-linux-amd64` |
| arm64 | `{project_name}-linux-arm64` |

```bash
curl -LSsf https://github.com/{org}/{project}/releases/latest/download/{project_name}-linux-amd64 \
  -o /usr/local/bin/{project_name} && chmod +x /usr/local/bin/{project_name}
```

### macOS
| Arch | Binary |
|------|--------|
| Intel (x86_64) | `{project_name}-darwin-amd64` |
| Apple Silicon (arm64) | `{project_name}-darwin-arm64` |

```bash
# Detect arch automatically
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
curl -LSsf "https://github.com/{org}/{project}/releases/latest/download/{project_name}-darwin-${ARCH}" \
  -o /usr/local/bin/{project_name} && chmod +x /usr/local/bin/{project_name}
# Remove macOS quarantine flag
xattr -d com.apple.quarantine /usr/local/bin/{project_name} 2>/dev/null || true
```

### Windows
| Arch | Binary |
|------|--------|
| amd64 | `{project_name}-windows-amd64.exe` |
| arm64 | `{project_name}-windows-arm64.exe` |

Download and add to `%PATH%`.

### FreeBSD
| Arch | Binary |
|------|--------|
| amd64 | `{project_name}-freebsd-amd64` |
| arm64 | `{project_name}-freebsd-arm64` |
```

**Rules:**

- Never document only one platform when the build matrix is wider — omission is a bug
- Never hardcode a version number in download URLs — always use `/releases/latest/download/`
- Always include the `xattr` quarantine removal step for macOS
- Always include `chmod +x` for every Unix binary
- Windows binaries get `.exe`; no other platforms do
- Rust binary naming uses OS names `linux/macos/windows/freebsd` (not `darwin`) and arch names `x86_64/aarch64` (not `amd64/arm64`) — match what the Makefile actually produces
- Go binary naming uses `darwin` (never `macos`) and `amd64`/`arm64` — match what the Makefile actually produces
- If a platform is conditionally built (e.g. macOS cross-compile requires a macOS host), note the constraint; do not silently omit the platform

### README.md sync rule

README.md must be updated **in the same commit** when any of the following change:

- New binary added, renamed, or removed
- New platform or architecture added to or removed from the build matrix
- New CLI flag, subcommand, or config option added
- Build prerequisites change
- Project name, org, or repo path changes
- New component added (CLI client, agent, web UI, Docker compose, etc.)
- Official site URL defined or changed (`site.txt`)

Use the `doc-sync` agent when CLI or feature changes require README updates.

**Never leave README.md in a state where the section order violates the canonical layout** — if a prior session added a Development section before Install, fix the order in the same commit that touches README.md.
