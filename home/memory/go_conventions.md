---
name: Go conventions
description: Build system, project layout, Makefile targets, and code rules for CasjaysDev Go projects
type: user
---

## Project Layout

```
{project_name}/
├── src/            # all Go source files (package main lives here)
├── binaries/       # compiled output — gitignored
├── releases/       # release archives — gitignored
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── scripts/
├── tests/
├── go.mod
├── go.sum
├── Makefile
├── release.txt     # local-build version (optional, e.g. 0.1.0)
└── AI.md
```

Source always under `src/` — never at repo root. `package main` entry point is `./src`.

## Makefile — Standard Variables

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

LDFLAGS := -s -w \
	-X 'main.Version=$(VERSION)' \
	-X 'main.CommitID=$(COMMIT_ID)' \
	-X 'main.BuildEpoch=$(BUILD_EPOCH)' \
	-X 'main.OfficialSite=$(OFFICIAL_SITE)'

BINDIR    := binaries
RELDIR    := releases
REGISTRY  := ghcr.io/$(PROJECTORG)/$(PROJECTNAME)

GO_CACHE  ?= $(HOME)/go/pkg/mod
GO_BUILD  ?= $(HOME)/.cache/go-build/$(PROJECTNAME)

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2
DOCKER_CPU_SHARES ?= 256
DOCKER_TIMEOUT ?= 3600

GO_DOCKER := timeout -k 30 $(DOCKER_TIMEOUT) docker run --rm --no-healthcheck \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) --cpu-shares=$(DOCKER_CPU_SHARES) \
	-v $(PWD):/app \
	-v $(GO_CACHE):/usr/local/share/go/pkg/mod \
	-v $(GO_BUILD):/usr/local/share/go/cache \
	-w /app \
	-e CGO_ENABLED=0 \
	-e GOFLAGS=-buildvcs=false \
	casjaysdev/go:latest
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | All 8 platforms + host binary; outputs to `binaries/`; tidy, download and every platform run in ONE container (one `sh -c` loop, never a container per platform) |
| `release` | Prepares release archives in `releases/`; first prerequisite is `release-check` |
| `release-check` | Internal helper: exit `78` with `ERROR:` on stderr unless `release.txt` is a stable `X.Y.Z` |
| `beta` | Tags the clean `main` commit `YYYYMMDDHHMMSS-beta` and pushes the tag; CI publishes the beta |
| `docker` | Builds the host platform only via `docker buildx build --load` (no push, no multi-arch: multi-arch publishing is CI/CD's job) |
| `test` | Runs `go vet ./...`, `govulncheck ./...`, then `TMPDIR="$COVDIR" go test -v -cover ./... -args -test.gocoverdir="$COVDIR/data"` inside Docker; the total comes from `go tool covdata textfmt` then `go tool cover -func` (never `-coverprofile`), gate at 60% |
| `dev` | Quick host-platform-only build into `mktemp` temp dir |
| `clean` | Removes `binaries/` and `releases/` |

## Build Targets and Binary Naming

8 platforms — uses Go's native GOOS/GOARCH terms directly:

| GOOS | GOARCH | Output binary |
|------|--------|--------------|
| `linux` | `amd64` | `{name}-linux-amd64` |
| `linux` | `arm64` | `{name}-linux-arm64` |
| `darwin` | `amd64` | `{name}-darwin-amd64` |
| `darwin` | `arm64` | `{name}-darwin-arm64` |
| `windows` | `amd64` | `{name}-windows-amd64.exe` |
| `windows` | `arm64` | `{name}-windows-arm64.exe` |
| `freebsd` | `amd64` | `{name}-freebsd-amd64` |
| `freebsd` | `arm64` | `{name}-freebsd-arm64` |

Schema: **`{project_name}-{GOOS}-{GOARCH}`** — windows appends `.exe`. macOS is always `darwin`, never `macos`. The host-platform binary (no suffix) is also built: `{project_name}` (or `{project_name}.exe` on Windows host).

## Toolchain Image Capabilities — `casjaysdev/go:latest`

Source: `~/Projects/github/dockersrc/go`. Image defaults (Docker `ENV`, already set — never re-declare in templates except as a safety net): `CGO_ENABLED=0`, `GOFLAGS=-buildvcs=false`, `GOTOOLCHAIN=auto`, `GOTELEMETRY=off`, `GOPROXY=https://proxy.golang.org,direct`.

Pre-installed tools:

- Latest stable Go toolchain (`go`, `gofmt`)
- `golangci-lint`, `staticcheck`, `gofumpt`, `goimports` — linting and formatting
- `govulncheck` — vulnerability scanner
- `go-licenses` — dependency license reporter
- `cyclonedx-gomod` — CycloneDX SBOM generator
- `goreleaser` — release automation
- `gotestsum` — structured test runner
- `gopls` — official Go language server
- `dlv` (Delve) — source-level debugger
- `ko` — build container images from Go source without a Dockerfile
- `air` — live-reload dev server
- `buf`, `protoc` — protobuf toolchain; `protoc-gen-go`, `protoc-gen-go-grpc`
- `goose` — DB migration runner
- `wire` — compile-time dependency injection
- `mockgen` (uber/mock) — interface mock generator
- `stringer` — `String()` method generator for iota types
- `benchstat` — statistically sound benchmark comparison
- `gops` — live Go process diagnostics

**Default entrypoint behavior** (only relevant to a bare `docker run casjaysdev/go:latest` with no command — templates never rely on this, they always invoke explicit `go`/tool commands via `GO_DOCKER`): with no arguments the container runs `go mod tidy → gofmt -w . → go vet ./... → govulncheck ./... → go test ./... → go build ./...` against `/app`. `GO_MODE=prod` (or `production`) strips release binaries (`-trimpath -ldflags=-s -w`) in that default workflow; templates apply the same stripping explicitly via `LDFLAGS` (see "Build Info Variables" below) so `GO_MODE` is not needed for Makefile-driven builds.

## Docker Build Pattern

**Go projects default to NO `docker/Dockerfile.build` or `build-toolchain.yml`** — `casjaysdev/go:latest` is a comprehensive maintained image. Exceptions: an image declared in IDEA.md/SPEC.md/AI.md wins; a genuine custom need (proprietary SDK, vendor toolchain, exotic system libraries) allows a `Dockerfile.build`, and then it MUST be `FROM casjaysdev/go:latest` — extend, never replace.

```makefile
GO_CACHE  ?= $(HOME)/go/pkg/mod
GO_BUILD  ?= $(HOME)/.cache/go-build/$(PROJECTNAME)

GO_DOCKER := timeout -k 30 $(DOCKER_TIMEOUT) docker run --rm --no-healthcheck \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) --cpu-shares=$(DOCKER_CPU_SHARES) \
	-v $(PWD):/app \
	-v $(GO_CACHE):/usr/local/share/go/pkg/mod \
	-v $(GO_BUILD):/usr/local/share/go/cache \
	-w /app \
	-e CGO_ENABLED=0 \
	-e GOFLAGS=-buildvcs=false \
	casjaysdev/go:latest
```

- `DOCKER_CPU_SHARES ?= 256` and `DOCKER_TIMEOUT ?= 3600` (seconds) are declared beside `DOCKER_MEM`/`DOCKER_CPUS`; `--no-healthcheck` keeps the image's service HEALTHCHECK from polling a one-shot build container
- Always `casjaysdev/go:latest` (rolling tag — never pinned)
- `CGO_ENABLED=0` and `GOFLAGS=-buildvcs=false` are `casjaysdev/go:latest` image defaults (Docker `ENV`); set explicitly in `GO_DOCKER` for clarity and as a safety net if the image ever changes. `GOTELEMETRY=off`, `GOTOOLCHAIN=auto`, and `GOPROXY=https://proxy.golang.org,direct` are also image defaults — do not set them in templates.
- `-e GOFLAGS=-buildvcs=false` — **required reason**: when `-v $PWD:/app` mounts `.git` into the container, Git 2.35.2+ rejects it as an "unsafe directory" because the host file owner (UID 1000) differs from the container user (root, UID 0). `go build` calls git internally to stamp VCS info and fails with "exit status 128". `GOFLAGS=-buildvcs=false` suppresses VCS stamping globally for all `go build` and `go test` calls inside the container. This is safe because version info is already embedded via `-X main.Version=...` LDFLAGS.
- `GO_CACHE` and `GO_BUILD` use `?=` so a host-set `GO_CACHE`/`GO_BUILD` (custom XDG or toolchain path) overrides the defaults; defaults are `~/go/pkg/mod` and `~/.cache/go-build/$(PROJECTNAME)` — the compile cache is project-scoped because it is not safe for concurrent writes across projects (see `execution_hierarchy.md`)
- Every target that uses `GO_DOCKER` must `@mkdir -p $(GO_CACHE) $(GO_BUILD)` first so host dirs exist before Docker mounts them
- Project source is mounted at `/app`; output dirs (`binaries/`) are subdirs of `/app` and land on the host automatically
- See **Module Cache** section for the named-volume fallback (`go-state`) when bind-mounting is not desired

**Timeout sizing for dockerized builds/tests** (full rules: `shell_lifetime_conventions.md`):
- First `make test`/`make build` of a session = cold cache (image pull + module download + full compile) — size at 600s (`600000` ms) or run_in_background from the start
- If a timeout kills it anyway, the ONLY retry is run_in_background — never foreground again, never a lower timeout
- Warm-cache repeat runs may drop a tier; after a partial pass re-run only the failing package (`go test ./pkg/...`), never the full suite; never re-run a suite that already passed

## Target Patterns

Every target that uses `GO_DOCKER` must create the cache dirs as its first step:

```makefile
build:
	@mkdir -p $(BINDIR) $(GO_CACHE) $(GO_BUILD)
	$(GO_DOCKER) go build -buildvcs=false -trimpath -ldflags "$(LDFLAGS)" -o $(BINDIR)/$(PROJECTNAME) ./src

test:
	@mkdir -p $(GO_CACHE) $(GO_BUILD)
	$(GO_DOCKER) go vet ./...
	$(GO_DOCKER) govulncheck ./...
	$(GO_DOCKER) go test -v -cover ./...

dev:
	@mkdir -p $(GO_CACHE) $(GO_BUILD) "$${TMPDIR:-/tmp}/$(PROJECTORG)" && \
		BUILD_DIR=$$(mktemp -d "$${TMPDIR:-/tmp}/$(PROJECTORG)/$(PROJECTNAME)-XXXXXX") && \
		echo "Quick dev build..." && \
		$(GO_DOCKER) go build -buildvcs=false -o $$BUILD_DIR/$(PROJECTNAME) ./src && \
		echo "Built: $$BUILD_DIR/$(PROJECTNAME)" && \
		echo "Test:  docker run --rm --name $(PROJECTNAME)-test -v $$BUILD_DIR:/app alpine:latest /app/$(PROJECTNAME) --help"
```

Always builds into a temp dir for `dev`, never to a hardcoded path.

**Rule — any direct `docker run` with a Go toolchain image** (not via `GO_DOCKER` macro) must include the source and cache mounts:

```makefile
some-target:
	@mkdir -p $(GO_CACHE) $(GO_BUILD)
	@timeout -k 30 $(DOCKER_TIMEOUT) docker run --rm --no-healthcheck \
		--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
		-v $(PWD):/app \
		-v $(GO_CACHE):/usr/local/share/go/pkg/mod \
		-v $(GO_BUILD):/usr/local/share/go/cache \
		-w /app \
		casjaysdev/go:latest \
		go ...
```

Never omit the cache mounts — every invocation that downloads or compiles modules must persist results across runs.

## Build Info Variables

Declare in `src/version.go` (the process entry `src/main.go` holds only `main()`, see "Thin process entry") as package-level vars set by ldflags:

```go
var (
    Version      = "devel"
    CommitID     = "N/A"
    BuildEpoch   = "0"
    OfficialSite = ""
    BuildDate    = "N/A"
)
```

`BuildEpoch` and `OfficialSite` are ldflags; `BuildDate` is NOT an ldflag — derive it from `BuildEpoch` in `init()`.

Never use `VCS_REF` as an alias — `CommitID` is the canonical name.

## Registry

Always `ghcr.io/{PROJECTORG}/{PROJECTNAME}` — a release is tagged `:{VERSION}`, `:latest`, `:YYMM` and `:{commit_id}`; a push to `main` gets `:{commit_id}` only, a `*-beta` tag adds `:beta`, and `:devel` comes from the separate `build-devel` job in `docker.yml` (built from `Dockerfile.dev`).

Docker target uses `docker buildx build --load` for the host platform only — no `--push`, no multi-arch; pushing and multi-arch publishing are CI/CD's responsibility, not the Makefile's. `PLATFORMS` (space-separated, all 8 OS/arch pairs: linux, darwin, windows, freebsd x amd64, arm64) drives the binary `build` target, not `docker`.

## Minimum Go Version

Set `go` directive in `go.mod` to the minimum required version. New projects start with the current stable release. Never set it lower than needed just to broaden compatibility — use the version that matches the features the code actually uses.

```
go 1.22
```

Update when a feature from a newer version is adopted.

## Dependency Version Policy

Never hardcode specific version numbers in spec or template files — they go stale immediately. Use `{version}` as a placeholder everywhere a module version appears in documentation, spec files, or examples. Actual versions are resolved at project creation time with `go get module@latest` and managed by `go mod tidy`.

## Linting & Vetting

- **`go vet`** runs as part of the `test` target (before `go test`); CI fails on any vet warning
- **`golangci-lint`** is required for all projects; config lives at `{project_dir}/.golangci.yml`; CI runs it in `ci.yml`; minimum enabled linters: `errcheck`, `govet`, `staticcheck`, `unused`, `gosimple`
- Never suppress a lint warning with a `//nolint` directive without an explanatory comment on the line above stating why

## Formatting & Line Width

- **`gofmt`** (or `goimports`) is the canonical formatter — always run before committing; no manual style debates
- **`gofmt` does not enforce a line length** — the Go community has no official limit; do not wrap lines artificially
- For `golangci-lint`, set `lll.line-length: 120` in `.golangci.yml` as a soft guide — CI warns but does not fail on lines between 120–180; lines over 180 are always a violation
- Long lines that are the result of `gofmt` formatting (e.g. function signatures, struct literals) are acceptable; only hand-written prose-style comments should be kept under 120

## Error Handling

- Wrap errors with context using `fmt.Errorf("operation: %w", err)` — always wrap, never discard
- Sentinel errors are defined as `var ErrFoo = errors.New("foo")` at package level; use `errors.Is` / `errors.As` to check, never string comparison
- Custom error types implement the `error` interface; use when the caller needs to inspect error fields
- Never use `log.Fatal` as a substitute for a proper exit code — `log.Fatal` calls `os.Exit(1)` with no cleanup

## Code Rules

- **CGO_ENABLED=0** — always; pure Go, no C, no exceptions
- **Strip release binaries** — always pass `-s -w` in LDFLAGS for `build`, `release`, and `docker` targets; `-s` strips the symbol table, `-w` strips DWARF debug info. The `dev` target (quick local build) omits `-s -w` to preserve debug symbols
- **No `-musl` suffix** — never include `-musl` in the output binary name; the binary naming schema is `{name}-{GOOS}-{GOARCH}` regardless of libc used to build
- **No `go build` on host** — always via `make dev`, `make build`, `make test` (Docker internally)
- **No external cron** — never depend on host cron or systemd timers for application-level scheduling. Use in-process scheduling only: `time.Ticker` or `time.Sleep` loop for simple periodic tasks; `go-co-op/gocron/v2` for multiple jobs or cron-expression scheduling.
- **No `strconv.ParseBool()`** — use `config.ParseBool()` which handles 40+ variations
- **No client-side rendering** — server-side Go templates only
- **Single static binary** — `go:embed` for assets; zero runtime file deps
- **Go embed** — assets bundled at build time; binary works air-gapped

## Thin process entry

`src/main.go` holds only `main()`: it parses flags, builds the configuration (copying `Version`, `CommitID`, `BuildEpoch`, `OfficialSite` from `src/version.go`) and calls `run(ctx, cfg) error`. `run` (startup, signal handling, graceful shutdown) lives in a package under `src/` that unit tests reach and that never imports `main`; a test calls it with a cancelable context and a listener on `127.0.0.1:0`, makes one request, cancels, and asserts a clean return. Orchestration left in `main()` counts against the 60% unit gate while only the compiled binary can reach it.

## Optional GUI client

A GUI client (`src/client/gui/`) is a separate, dynamically linked artifact built only for Linux, macOS and Windows, never BSD: `go build -tags gui -o {project_name}-cli-gui-{GOOS}-{GOARCH}[.exe] ./src/client`, uploaded as its own artifact. The default `-cli` binary stays static and pure Go (`CGO_ENABLED=0`).

## Exit Codes

Use standard POSIX / sysexits codes via `os.Exit(N)` — never invent custom schemes. Full table and the output-stream rules (errors to stderr, data to stdout) are in `~/.claude/memory/script_conventions.md`. `--help` and `--version` always exit `0`; usage errors exit `2` (`64` is not used); a missing capability exits `69`, bad config `78`; signal exits are `128 + signal` (SIGINT=130, SIGTERM=143). `--status` returns only `0` or `1`.

For Go, import `golang.org/x/sys/unix` or define sysexits constants locally — the stdlib does not export them. Never use `log.Fatal` as a substitute for a proper exit code.

## CLI Flags — Standard Interface

### Standard flags (all Go TUI/CLI binaries)

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 — never escalate privileges |
| `--version` | `-v` | — | Print version and exit 0 — never escalate privileges |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output — `auto`: TTY detect; `yes`: force on; `no`: force off |

- `--color auto` detects terminal capability (default); `yes` forces color; `no` disables it and removes emojis from output.
- All flags must support both `--flag value` and `--flag=value` — cobra/pflag handles this natively.
- `--help` and `--version` must never require root — always exit immediately with the requested output.
- `help` (bare, no `--`) must be a recognized command at every level — `myapp help` and `myapp subcmd help` produce the same output as their `--help` equivalents.
- **No escalation** — help at every level (main, subcommand, nested) must never call `sudo`, require root/admin, or check privilege state; exit immediately with the help text.

### Toggle flags — `--enable`, `--disable`, `--yes`, `--no`

Never use compound hyphenated flags (`--enable-tls`, `--disable-cache`). Instead the flag takes the feature name as a required argument: `--enable tls`, `--disable cache`. Use the same pattern for `--yes` and `--no`. This keeps the flag set small and routes all toggle intent through one handler.

**Exception:** `--color` is the standard three-value enum — `--color auto`, `--color yes`, `--color no`. There is no `--no-color` flag; `--color no` and the `NO_COLOR` env var both disable color.

```go
// Declare flags that take the thing-to-toggle as an argument.
// Never: --enable-tls, --disable-cache, --yes-overwrite
// Always: --enable tls, --disable cache, --yes overwrite
rootCmd.Flags().StringVar(&enableFeature,  "enable",  "", "Enable a named feature")
rootCmd.Flags().StringVar(&disableFeature, "disable", "", "Disable a named feature")
rootCmd.Flags().StringVar(&yesTarget,      "yes",     "", "Confirm yes for a named operation")
rootCmd.Flags().StringVar(&noTarget,       "no",      "", "Confirm no for a named operation")
```

Both `--enable featurename` and `--enable=featurename` work — cobra/pflag handles both natively.

### Help output format

**Applies everywhere help is shown** — `--help`, `help` (bare subcommand), and `subcommand help`. All produce identical output via the same function.

Item left-aligned in a 38-character field, then `- `, then description ≤ 100 chars (140 max per line):

```
--help                                - Show this help message and exit
--version                             - Show version and exit
init                                  - Initialize a new project
```

Implement a shared `printHelp(usage string, sections []HelpSection)` helper (or equivalent) that all commands and subcommands call — never duplicate the formatting logic. With `cobra` or `flag`, override the usage function to emit this format; never rely on default auto-generated help.

`help` (bare, no `--`) must be registered as a command/alias at every level and call the same help function as `--help`:
- `myapp help` == `myapp --help`
- `myapp subcmd help` == `myapp subcmd --help`

### NO_COLOR support

Every Go TUI/CLI binary must honor the `NO_COLOR` environment variable ([no-color.org](https://no-color.org/)):

```go
// Color resolution order (highest precedence first):
// 1. --color=no  or  --color=yes
// 2. NO_COLOR env var present (any value) → disable color and emojis
// 3. --color=auto → check os.Stdout isatty
func resolveColor(flag string) bool {
    switch flag {
    case "yes":
        return true
    case "no":
        return false
    // "auto"
    default:
        if _, set := os.LookupEnv("NO_COLOR"); set {
            return false
        }
        return isatty(os.Stdout.Fd())
    }
}
```

### Flag parsing — use `flag` stdlib or `pflag`

Use the standard `flag` package or `pflag` (cobra/viper) — never hand-roll argument parsing. `pflag` supports `--flag=value` and `--flag value` natively.

Recommended for multi-command CLIs: `cobra` + `viper`. Recommended for single-command binaries: stdlib `flag`.

```go
// cobra example — color flag on root command
rootCmd.PersistentFlags().String("color", "auto", "Color output: auto, yes, no")
```

## Terminal Display — Alt Buffer and ANSI Escapes

Any Go binary that is a TUI or acts as a TUI must use the alternate screen buffer. Use raw ANSI escape sequences written to `os.Stdout` — never shell out to `tput`.

### Constants

```go
const (
    // enter alternate screen buffer
    AltBufEnter   = "\033[?1049h"
    // leave alternate screen buffer
    AltBufLeave   = "\033[?1049l"
    // blinking I-beam (preferred)
    CursorBlink   = "\033[5 q"
    // restore terminal default cursor
    CursorRestore = "\033[0 q"
    CursorHide    = "\033[?25l"
    CursorShow    = "\033[?25h"
    ClearScreen   = "\033[2J\033[H"
)
```

### Enter / leave pattern

```go
func enterTUI() {
    fmt.Fprint(os.Stdout, AltBufEnter+CursorBlink)
}

func leaveTUI() {
    fmt.Fprint(os.Stdout, AltBufLeave+CursorRestore)
}
```

Always call `leaveTUI()` via `defer` **and** from a signal handler so the terminal is restored on Ctrl-C:

```go
enterTUI()
defer leaveTUI()

sigs := make(chan os.Signal, 1)
signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
go func() {
    <-sigs
    leaveTUI()
    os.Exit(130)
}()
```

### bubbletea shortcut

If using `github.com/charmbracelet/bubbletea`, pass `tea.WithAltScreen()` — it manages alt buffer and cursor automatically:

```go
p := tea.NewProgram(model, tea.WithAltScreen())
```

Do not manually call `enterTUI`/`leaveTUI` when using bubbletea — it handles setup and teardown internally.

### NO_COLOR

Suppress all ANSI output (colors, cursor sequences) when `NO_COLOR` is set or `--color=no` is in effect. Use the `resolveColor` function from the CLI Flags section — do not emit any escape sequence when color is disabled.

---

## Directory Naming

**Singular** — Go package names and their directories are singular (`handler/`, `model/`, `middleware/`, `route/`). The directory name equals the package name; plural breaks that contract. Tooling dirs are always plural (`scripts/`, `tests/`, `completions/`).

## Module Cache

`casjaysdev/go:latest` consolidates GOPATH, GOCACHE, and GOMODCACHE under `/usr/local/share/go`.

**Prefer host env vars over the named volume** — if `GOMODCACHE` or `GOCACHE` are set in the host environment, bind-mount those host paths instead of using the `go-state` named volume. This lets the user's existing cache be reused and respects custom XDG or toolchain layouts:

```makefile
GO_CACHE  ?= $(HOME)/go/pkg/mod
GO_BUILD  ?= $(HOME)/.cache/go-build/$(PROJECTNAME)

GO_DOCKER := timeout -k 30 $(DOCKER_TIMEOUT) docker run --rm --no-healthcheck \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) --cpu-shares=$(DOCKER_CPU_SHARES) \
	-v $(PWD):/app \
	-v $(GO_CACHE):/usr/local/share/go/pkg/mod \
	-v $(GO_BUILD):/usr/local/share/go/cache \
	-w /app \
	-e CGO_ENABLED=0 \
	-e GOFLAGS=-buildvcs=false \
	casjaysdev/go:latest
```

Use `?=` so a host-set `GO_CACHE` or `GO_BUILD` env var (pointing at custom `GOMODCACHE`/`GOCACHE` paths) overrides the defaults. Run `@mkdir -p $(GO_CACHE) $(GO_BUILD)` at the top of every target that uses `GO_DOCKER` so the host dirs exist before Docker mounts them.

**Fallback — named volume** — when no host cache dirs are defined and bind-mounting is not desired, use the `go-state` named volume. Docker creates named volumes automatically — no `mkdir -p` needed:

```makefile
GO_VOL := go-state

GO_DOCKER := timeout -k 30 $(DOCKER_TIMEOUT) docker run --rm --no-healthcheck \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	-v $(PWD):/app \
	-v $(GO_VOL):/usr/local/share/go \
	-w /app \
	-e CGO_ENABLED=0 \
	-e GOFLAGS=-buildvcs=false \
	casjaysdev/go:latest
```

```
go-state (named volume)  →  /usr/local/share/go  in container
                              ├── pkg/mod/         (GOMODCACHE)
                              ├── cache/           (GOCACHE)
                              └── bin/             (installed tools)
```

The named volume is shared across all Go projects on the same machine — this is intentional. The module cache is content-addressed and safe to share. If isolation per project is needed, use `go-state-$(PROJECTNAME)` as the volume name instead.

## Version Source

`release.txt` is the optional local-build version file — single line, semver (e.g. `0.1.0`). Only the Makefile reads it, for local builds, when present and non-empty; empty or missing means the devel rule (short commit id, `devel` outside git), and an explicit `VERSION` env var (user only, AI never sets it) overrides it. CI never reads it. Never hardcode the version in the Makefile.
