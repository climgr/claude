---
name: Makefile conventions
description: Universal Makefile patterns shared across all CasjaysDev project types and languages
type: user
---

## Core Rules

- **`.PHONY` is mandatory** — declare every non-file target; prevents collision with files of the same name
- **Never hardcode `PROJECTNAME` or `PROJECTORG`** — always infer from git remote
- **`VERSION` for local builds only** — explicit `VERSION` env (user override, AI never sets it) > non-empty `release.txt` > devel rule (short commit id, `devel` outside git); never hardcode; CI never uses the Makefile or `release.txt`; see `~/.claude/memory/version_conventions.md`
- **`@` prefix suppresses echo** — every recipe line that is not intentional debug output uses `@`
- **`help` is always the first target** — `make` alone prints the help screen
- **Never used in CI** — workflows run explicit commands with all env vars set; they do not call `make`
- **Local only — no outbound writes** — the Makefile is a local developer tool; it must never push, publish, or write to any remote system. Specifically forbidden in any Makefile target: `docker push`, `docker buildx ... --push`, `git commit`, `git push`, `git tag`, `npm publish`, `cargo publish`, `gh release`, `glab release`, or any equivalent. `docker pull` is allowed — fetching images and dependencies (remote → local) is fine; sending artifacts or commits outward (local → remote) is not.

---

## Standard Variables (All Languages)

```makefile
# IDEA.md project variables first (the same source as {project_name}), then the git remote, then the directory path - NEVER hardcode
PROJECTNAME := $(shell sed -n 's/^project_name:[[:space:]]*//p' IDEA.md 2>/dev/null | head -n1 | tr -d '[:space:]')
ifeq ($(PROJECTNAME),)
PROJECTNAME := $(shell git remote get-url origin 2>/dev/null | sed -E 's|.*/([^/]+)$$|\1|; s|\.git$$||' || basename "$$(pwd)")
endif
PROJECTORG := $(shell sed -n 's/^project_org:[[:space:]]*//p' IDEA.md 2>/dev/null | head -n1 | tr -d '[:space:]')
ifeq ($(PROJECTORG),)
PROJECTORG := $(shell git remote get-url origin 2>/dev/null | sed -E 's|.*/([^/]+)/[^/]+$$|\1|' || basename "$$(dirname "$$(pwd)")")
endif

# Local builds only: VERSION env (user override, AI never sets it) > non-empty release.txt > devel rule (short commit id, "devel" outside git)
VERSION       ?= $(shell v=; [ -r release.txt ] && v=$$(tr -d '[:space:]' < release.txt); if [ -n "$$v" ]; then echo "$$v"; else git rev-parse --short=7 HEAD 2>/dev/null || echo devel; fi)
BUILD_EPOCH   := $(shell date -u +%s)
BUILD_DATE    := $(shell date -u -d @$(BUILD_EPOCH) +"%Y-%m-%dT%H:%M:%SZ")
COMMIT_ID     := $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo "N/A")
OFFICIAL_SITE := $(shell [ -f site.txt ] && cat site.txt || echo "$${OFFICIAL_SITE:-}")
PLATFORMS     ?= linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64 freebsd/amd64 freebsd/arm64
```

- `BUILD_EPOCH` is captured ONCE; `BUILD_DATE` (RFC 3339 UTC) is derived from it, never captured independently
- `PLATFORMS` is space-separated (consumed by shell for-loops) across 8 OS/arch pairs: linux, darwin, windows, freebsd x amd64, arm64
- `OFFICIAL_SITE` comes from `site.txt` (single line, URL only), else the env var, else empty — unset means unset: never inferred, never an invented or `example.com` value

Use `:=` (immediate) for shell-computed values — evaluated once at parse time.
Use `?=` for overridable variables — allows `make build VERSION=1.2.3-rc1` or `make docker PLATFORMS=linux/amd64`.
Never use `=` (recursive) for computed values — causes repeated shell invocations on every reference.

---

## Standard Target Names

All projects define these targets (when applicable). All are `.PHONY`.

| Target | Description |
|--------|-------------|
| `help` | Print target list and current version — **always first** |
| `build` | Compile/package into `binaries/` or `dist/` |
| `test` | Lint + vet + test suite |
| `dev` | Quick single-platform build into a temp dir for local testing |
| `lint` | Linter/formatter check only (no test suite) |
| `docker` | Build multi-arch Docker image locally (no push) |
| `release` | Prepare release archives in `releases/`; first prerequisite is `release-check` |
| `release-check` | Internal helper, never a workflow entry point: fails with `ERROR:` on stderr and exit `78` unless `release.txt` is a stable `X.Y.Z` (devel ids and prereleases come from CI, never `make release`) |
| `beta` | Tag the current clean `main` commit `YYYYMMDDHHMMSS-beta` and push the tag; CI builds and publishes the beta (Go/Rust templates) |
| `clean` | Remove build output — never source, `.git`, or base images |

---

## `.PHONY` Declaration

```makefile
.PHONY: help build test dev lint docker release release-check beta clean
```

Declare all non-file targets together near the top of the Makefile (or immediately before each target group).

---

## `help` Target Pattern

```makefile
.PHONY: help
help: ## Show this help message
	@printf '\n\033[1;37m  %s v%s\033[0m\n\n' "$(PROJECTNAME)" "$(VERSION)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-38s\033[0m- %s\n", $$1, $$2}'
	@printf '\n'
```

Targets self-document with `## description` inline comments. The `help` target greps for them automatically — no manual maintenance.

Output follows the standard help format: item left-aligned in 38 characters, then `- `, then description ≤ 100 chars (140 max per line).

---

## Recipe Rules

- `@` prefix on every recipe line that does not need to be echoed
- Multi-line recipes: use `\` continuation with tab-indented continuation lines
- Use `$(MAKE)` not `make` when recursing — preserves `-j`, `-n`, and other flags
- Chain with `&&` not `;` when subsequent steps must not run after a failure
- Temp files created in recipes: use `mktemp` and clean up in the same recipe block

---

## Variable Hygiene

| Assignment | When to use |
|-----------|-------------|
| `:=` | Shell-computed or string values — evaluated once at parse time |
| `?=` | User-overridable values — `VERSION ?= ...`, `PORT ?= 8080` |
| `=` | Only for values that must re-expand on each use (rare) |

Never put `$(shell ...)` inside a recipe — use variables defined outside recipes so evaluation happens once.

Never `export` Makefile variables globally — pass them explicitly to Docker containers with `-e VAR=$(VAR)`.

---

## Docker Run Pattern

All build-time tool invocations run inside Docker — language files define the specific image and mounts:

```makefile
# Shared pattern — each language substitutes its own image, cache vars, and mounts
# ?= honors host env var override
CACHE_DIR ?= $(HOME)/.cache/{lang}
# resource limits, overridable
DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2
# CPU weight under contention (Docker default 1024): a build never starves the host's other work
DOCKER_CPU_SHARES ?= 256
# hard ceiling in seconds for ONE container run, so a hung step never holds a container for hours
DOCKER_TIMEOUT ?= 3600

# --no-healthcheck: the toolchain image's service HEALTHCHECK must not poll a one-shot build container
# timeout -k 30: a hung run is stopped after DOCKER_TIMEOUT seconds and the signal reaches the container
LANG_DOCKER := timeout -k 30 $(DOCKER_TIMEOUT) docker run --rm --no-healthcheck \
    --name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
    --memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) --cpu-shares=$(DOCKER_CPU_SHARES) \
    -v $(PWD):/app \
    -v $(CACHE_DIR):/root/.cache/{lang} \
    -w /app \
    {lang}:alpine
```

**One container per Makefile target.** A target runs its whole sequence (tidy, download, every platform) in ONE `sh -c` container, never a container per step or per platform. `docker buildx` uses the single shared `multiarch-builder` builder, never one builder per project (every builder is a long-lived buildkit container).

### Cache mount rules (apply to every toolchain container)

1. **Declare cache paths with `?=`** — `VAR ?= $(HOME)/.cache/...` so the host env var is honored when set (e.g. custom XDG paths). Never hardcode a path that a user may have relocated.
2. **`@mkdir -p` before every `docker run`** — Docker silently creates missing dirs as root, breaking cache ownership and persistence. Always create the host dirs first:
   ```makefile
   build:
       @mkdir -p $(CACHE_DIR)
       $(LANG_DOCKER) ...
   ```
3. **Mount with `-v $(VAR):/container/path`** — the host path resolves from the `?=` variable; the container path is the fixed location for that toolchain image.

| Language | Cache mechanism | Variable | Container path |
|----------|----------------|----------|----------------|
| Go (primary) | Host bind-mount | `GO_CACHE ?= $(HOME)/go/pkg/mod` + `GO_BUILD ?= $(HOME)/.cache/go-build/$(PROJECTNAME)` | `/usr/local/share/go/pkg/mod` + `/usr/local/share/go/cache` |
| Go (fallback) | Named volume | `GO_VOL := go-state` | `/usr/local/share/go` (GOPATH + GOCACHE + GOMODCACHE combined) |
| Rust (cargo) | Named volume | `RUST_CARGO_VOL := rust-cargo` | `/usr/local/share/cargo` |
| Rust (rustup) | Named volume | `RUST_RUSTUP_VOL := rust-rustup` | `/usr/local/share/rustup` |
| Rust (sccache) | Named volume | `RUST_SCCACHE_VOL := rust-sccache` | `/root/.cache/sccache` |
| Node | Host dir | `NPM_CACHE ?= $(HOME)/.npm` | `/root/.npm` |
| Python (pip) | Host dir | `PIP_CACHE ?= $(HOME)/.cache/pip` | `/root/.cache/pip` |
| Python (uv) | Host dir | `UV_CACHE ?= $(HOME)/.cache/uv` | `/root/.cache/uv` |

Go **primary** uses **host bind-mounts** (`GO_CACHE`, `GO_BUILD`) — always `@mkdir -p $(GO_CACHE) $(GO_BUILD)` before the docker run; **fallback** uses the `go-state` named volume (Docker creates it automatically). Rust uses **named volumes** — Docker creates them automatically; no `mkdir -p` needed. Node and Python use **host dir mounts** — always `@mkdir -p` the host dir before the docker run.

- Always `--rm --name $(PROJECTNAME)-XXXX` — never leave build containers running; the name enables targeted cleanup (`docker stop $(PROJECTNAME)-XXXX`); `XXXX` is a random suffix: `$$(tr -dc 'a-z0-9' </dev/urandom | head -c8)`. Never add `-it` to batch build/test targets (breaks CI — no TTY); `-it` only on explicit interactive-shell targets (e.g. `make shell`)
- Always `-w /app` — explicit working directory
- Mount project root at `/app`; output dirs (`binaries/`, `dist/`) are subdirs of `/app`

Language-specific Docker variables and full cache mount patterns are in each language's conventions file:
- Go: `~/.claude/memory/go_conventions.md`
- Rust: `~/.claude/memory/rust_conventions.md`
- Node/TypeScript: `~/.claude/memory/node_typescript_conventions.md`
- Python: `~/.claude/memory/python_conventions.md`

---

## Cross-Platform Pitfalls

All build commands run inside Docker, so host OS differences are mostly irrelevant. Variable definitions (evaluated on the host) must be portable:

| Pitfall | Fix |
|---------|-----|
| `sed -i` needs `-i ''` on macOS | Run sed-using recipes inside Docker |
| `date` format varies (GNU vs BSD macOS) | `date +"%Y-%m-%dT%H:%M:%SZ"` works on both |
| `readlink -f` not available on macOS | Use `realpath` or run inside Docker |
| Tabs vs spaces in recipes | Makefiles require real tabs — never spaces in recipes |

---

## What `clean` Must Never Remove

- Source files (`src/`, `tests/`, `*.go`, `*.rs`, `*.ts`, `*.py`)
- `.git/` directory
- Base Docker images (`casjaysdev/go:latest`, `casjaysdev/rust:latest`, `node:alpine`, etc.) — only project images are cleaned
- `AI.md`, `IDEA.md`, `CLAUDE.md`, `release.txt` (optional), `Makefile`

`clean` removes only build artifacts: `binaries/`, `releases/`, `dist/`, language caches (`target/`, `__pycache__/`, `.mypy_cache/`, `node_modules/`).
