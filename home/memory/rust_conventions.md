---
name: Rust conventions
description: Build system, project layout, Makefile targets, Cargo profile, and code rules for CasjaysDev Rust projects
type: user
---

## Project Layout

```
{project_name}/
├── src/            # Rust source files
├── tests/          # integration and unit tests
├── binaries/       # compiled output — gitignored
├── releases/       # release archives — gitignored
├── build.rs        # build script (if needed)
├── Cargo.toml
├── Cargo.lock      # always committed (binary crate)
├── Makefile
├── release.txt     # current version string (e.g. 0.1.0)
└── AI.md
```

## Docker Build Pattern

**Rust projects default to NO `docker/Dockerfile.build` or `build-toolchain.yml`** — `casjaysdev/rust:latest` is a comprehensive maintained image. Exceptions: an image declared in IDEA.md/SPEC.md/AI.md wins; a genuine custom need (proprietary SDK, vendor toolchain, exotic system libraries) allows a `Dockerfile.build`, and then it MUST be `FROM casjaysdev/rust:latest` — extend, never replace.

## Toolchain Image Capabilities — casjaysdev/rust:latest

Source: `~/Projects/github/dockersrc/rust`. Alpine-based, rolling tag, stable + nightly toolchains.

**Toolchain**: `rustc`, `cargo`, `rustfmt`, `clippy`, `rust-src`, `rust-analyzer`, `llvm-tools-preview` (stable); `miri`, `rust-src` (nightly, minimal profile — run via `cargo +nightly miri test`)

**Pre-installed tools** (via `cargo-binstall`, prebuilt binaries only — no source compiles):
- Linting/analysis: `cargo-geiger`, `cargo-deny`, `cargo-audit`, `cargo-machete`, `cargo-udeps` (nightly), `cargo-hack`, `cargo-minimal-versions`, `cargo-semver-checks`, `cargo-public-api`, `typos-cli`, `cargo-spellcheck`
- Formatting: `taplo-cli`, `dprint`, `cargo-sort`
- Testing/coverage: `cargo-nextest`, `cargo-llvm-cov`, `cargo-tarpaulin`, `grcov`, `cargo-mutants`
- Benchmarking/profiling: `cargo-criterion`, `hyperfine`, `samply`, `flamegraph` (need `--privileged` or `--cap-add SYS_ADMIN --cap-add PERFMON` at container runtime — cannot be baked into the image), `perf`
- Fuzzing/debugging: `cargo-fuzz`, `gdb` (+ `rust-gdb` wrapper), `cargo-careful`, `probe-rs`
- Code analysis: `cargo-expand`, `cargo-asm`, `cargo-bloat`, `cargo-binutils`, `tokei`
- Build/release: `cargo-make`, `just`, `cargo-release`, `cargo-dist`, `cargo-deb`, `cargo-generate`, `cargo-chef`
- Cross-compilation: `cargo-zigbuild`, `cross`, `cargo-ndk`, `cbindgen`, `flip-link`, `zig` (universal C/C++ cross-toolchain)
- WASM: `wasm-pack`, `wasm-bindgen-cli`, `wasm-tools`, `trunk`, `wasm-opt` (binaryen)
- Docs: `mdbook`, `mdbook-toc`
- Dev loop: `bacon`, `cargo-watch`, `cargo-edit`, `cargo-update`, `cargo-outdated`, `cargo-info`, `cargo-msrv`
- Compilation cache: `sccache`
- Database (best-effort, `rustls`-based): `sqlx-cli`, `sea-orm-cli`

**C/C++ toolchain** (`05-custom.sh`, not the base Alpine `PACK_LIST`): `build-base`, `musl-dev`, `clang`, `clang-dev`, `llvm-dev`, `lld`, `cmake`, `make`, `perl`, `openssl-dev`, `openssl-libs-static`, `pkgconf`, `gdb`, and (best-effort) `mingw-w64-gcc` for Windows GNU cross-compilation.

**Cross-compile — 30 pre-installed targets**, pre-configured in `$CARGO_HOME/config.toml` (`rust-lld` linker for ARM/aarch64/RISC-V/embedded, `*-w64-mingw32-gcc`/`ar` for Windows GNU): Linux musl (x86_64, aarch64, i686, armv7, riscv64gc); Linux glibc (x86_64, aarch64, i686, armv7, arm, riscv64gc, ppc64le, s390x); Windows GNU (x86_64-gnu, i686-gnu, aarch64-gnullvm); macOS (x86_64, aarch64); `x86_64-unknown-freebsd`; WASM (wasm32-unknown-unknown, wasip1, wasip2, unknown-emscripten); embedded ARM/RISC-V; `aarch64-linux-android`. Additional targets: `rustup target add <triple>`.

**Windows MSVC is NOT supported** — the image has no MSVC toolchain, only `mingw-w64-gcc`. Always target `*-pc-windows-gnu` / `*-pc-windows-gnullvm`, never `*-pc-windows-msvc`.

**Cross-compile method by dependency type**: pure-Rust crates → plain `cargo build --target ...`; crates with C deps (`*-sys`, `openssl-sys`, `ring`, etc.) → `cargo zigbuild`; full stdlib/libc needs → `cross` (official cross-rs container via QEMU).

**Env defaults** (set as Docker `ENV`, active for every `docker run`): `RUSTUP_HOME=/usr/local/share/rustup`, `CARGO_HOME=/usr/local/share/cargo`, `RUSTUP_TOOLCHAIN=stable`, `SCCACHE_DIR=/root/.cache/sccache`, `CARGO_INCREMENTAL=0`. **Not** set as image `ENV` (login-shell only, via `/etc/profile.d/rust.sh`): `RUSTC_WRAPPER=sccache` — see the `RUST_DOCKER` macro note below for why it must be passed explicitly. `CARGO_TARGET_DIR` is intentionally unset so each project keeps its own `./target/`.

**`rust-workflow`**: a 4-step pipeline baked into the image (`fmt check → clippy -D warnings → cargo test --all → cargo build --release`), invoked explicitly: `docker run ... casjaysdev/rust:latest rust-workflow`. **Unlike the Go image, a no-args `docker run` does NOT auto-run this pipeline** — it starts the image's background "monitoring mode" instead. `CARGO_WORKDIR` overrides the working dir; `CARGO_BUILD_TARGET` sets the cross-compile triple, both `rust-workflow`-only.

**Miri**: nightly-only interpreter for detecting UB, borrow violations across FFI, and data races — slower than normal test runs; use it targeted on unsafe code or after a refactor, not in the default CI test path.

## Makefile — Standard Variables

```makefile
PROJECT_NAME  := {project_name}
ORGANIZATION  := {project_org}
VERSION       := $(shell cat release.txt 2>/dev/null || echo "devel")
COMMIT_ID     := $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo "N/A")
PLATFORMS     ?= linux/amd64,linux/arm64
BINARIES_DIR  := ./binaries
RELEASES_DIR  := ./releases

CARGO_CACHE   ?= $(HOME)/.cargo
RUSTUP_CACHE  ?= $(HOME)/.rustup
SCCACHE_CACHE ?= $(HOME)/.cache/sccache
CARGO_TARGET  ?= $(HOME)/.cache/cargo-target/$(PROJECT_NAME)

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

RUST_DOCKER := docker run --rm \
	--name $(PROJECT_NAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-e RUSTC_WRAPPER=sccache \
	-v "$(PWD)":/app \
	-v $(CARGO_CACHE):/usr/local/share/cargo \
	-v $(RUSTUP_CACHE):/usr/local/share/rustup \
	-v $(SCCACHE_CACHE):/root/.cache/sccache \
	-v $(CARGO_TARGET):/app/target \
	-w /app \
	casjaysdev/rust:latest
```

- `casjaysdev/rust:latest` rolling tag — never pinned; Alpine-based with stable + nightly toolchains, 30 cross-compile targets, and every common Cargo tool pre-installed
- `PROJECT_NAME` and `ORGANIZATION` are literal here (not inferred from git); keep in sync with `Cargo.toml`
- `CARGO_CACHE`, `RUSTUP_CACHE`, and `SCCACHE_CACHE` use `?=` so host env vars (`CARGO_HOME`, `RUSTUP_HOME`, custom XDG paths) are honored; defaults are `~/.cargo`, `~/.rustup`, and `~/.cache/sccache`
- `CARGO_TARGET ?= $(HOME)/.cache/cargo-target/$(PROJECT_NAME)` mounts the Cargo target dir at `/app/target` — scoped per project because target artifacts are not safe to share across projects, and it keeps `target/` out of the source tree
- Every target that uses `RUST_DOCKER` must `@mkdir -p $(CARGO_CACHE) $(RUSTUP_CACHE) $(SCCACHE_CACHE) $(CARGO_TARGET)` first so host dirs exist before Docker mounts them and downloaded crates persist across runs
- `CARGO_HOME` is `/usr/local/share/cargo` inside the image (not `/usr/local/cargo` as in the official `rust:alpine`)
- `RUSTUP_HOME` is `/usr/local/share/rustup`; sccache cache is at `/root/.cache/sccache`
- `CARGO_INCREMENTAL=0` is a `casjaysdev/rust:latest` image `ENV` default (active for every `docker run`, forced off because it conflicts with sccache). `RUSTC_WRAPPER=sccache` is **not** set as an image `ENV` — it is only exported by `/etc/profile.d/rust.sh`, which fires for interactive login shells, not for a plain `docker run cargo ...`. `RUST_DOCKER` above sets `-e RUSTC_WRAPPER=sccache` explicitly so non-interactive Makefile invocations still get compiler caching. Mount `SCCACHE_CACHE` to persist the cache; omit the mount and every build starts cold. To opt out: `-e RUSTC_WRAPPER=`
- See **Named Volume Fallback** below for when bind-mounting is not desired

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | Builds all platforms inside Docker; outputs to `binaries/` |
| `release` | Prepares release archives in `releases/` |
| `test` | Runs `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo audit`, then `cargo test --lib --no-fail-fast` inside Docker |
| `clean` | Removes `binaries/`, `releases/`, and `target/` |
| `help` | Prints target list and current version |

## Build Pattern

All cargo invocations run inside Docker — never directly on host. Every target that uses `RUST_DOCKER` must create the cache dirs first:

```makefile
build:
	@mkdir -p $(BINARIES_DIR) $(CARGO_CACHE) $(RUSTUP_CACHE) $(SCCACHE_CACHE) $(CARGO_TARGET)
	$(RUST_DOCKER) bash -c ' \
	    cargo build --release && \
	    strip target/release/$(PROJECT_NAME) 2>/dev/null || true && \
	    cp target/release/$(PROJECT_NAME) /app/$(BINARIES_DIR)/$(PROJECT_NAME)-{os}-{arch} && \
	    chmod 755 /app/$(BINARIES_DIR)/$(PROJECT_NAME)-{os}-{arch}'
```

Binary naming: `{project_name}-{os}-{arch}` (e.g. `cascolor-linux-amd64`).

**Rule — any `docker run` with a Rust/Cargo image** must include all three cache mounts. Never omit them — every invocation that fetches or compiles crates must persist results across runs.

**Timeout sizing for dockerized builds/tests** (full rules: `shell_lifetime_conventions.md`):
- First `make test`/`make build` of a session = cold cache (image pull + crate download + full compile) — size at 600s (`600000` ms) or run_in_background from the start
- If a timeout kills it anyway, the ONLY retry is run_in_background — never foreground again, never a lower timeout
- Warm-cache repeat runs may drop a tier; after a partial pass re-run only the failing crate/test (`cargo test -p {crate}`), never the full suite; never re-run a suite that already passed

### Named Volume Fallback

When bind-mounting host cache dirs is not desired, use named volumes instead. Docker creates named volumes automatically — no `mkdir -p` needed:

```makefile
RUST_CARGO_VOL   := rust-cargo
RUST_RUSTUP_VOL  := rust-rustup
RUST_SCCACHE_VOL := rust-sccache

RUST_DOCKER := docker run --rm \
	--name $(PROJECT_NAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-e RUSTC_WRAPPER=sccache \
	-v "$(PWD)":/app \
	-v $(RUST_CARGO_VOL):/usr/local/share/cargo \
	-v $(RUST_RUSTUP_VOL):/usr/local/share/rustup \
	-v $(RUST_SCCACHE_VOL):/root/.cache/sccache \
	-w /app \
	casjaysdev/rust:latest
```

## Platform Targets and Binary Naming

Uses unified Go OS/arch terms (not the full Rust target triple) for the output filename:

| Rust target triple | Output binary | Notes |
|-------------------|--------------|-------|
| `x86_64-unknown-linux-gnu` | `{name}-linux-amd64` | Docker Linux/amd64 |
| `aarch64-unknown-linux-gnu` | `{name}-linux-arm64` | Requires native ARM64 or QEMU |
| `x86_64-pc-windows-gnu` | `{name}-windows-amd64.exe` | MinGW cross (GTK4 not supported via MinGW) |
| `x86_64-apple-darwin` | `{name}-darwin-amd64` | macOS host required |
| `aarch64-apple-darwin` | `{name}-darwin-arm64` | macOS host required |
| `x86_64-unknown-freebsd` | `{name}-freebsd-amd64` | FreeBSD host required |

Schema: **`{project_name}-{os}-{arch}`** where:
- OS: `linux` / `darwin` / `windows` / `freebsd` (Go terms — macOS is `darwin`, never `macos`)
- Arch: `amd64` / `arm64` (Go terms — never `x86_64` or `aarch64` in artifact names)
- Windows appends `.exe`

macOS and FreeBSD cross-compilation from Linux is generally not supported — document as skipped with a note in the Makefile output.

## Test Target Pattern

```makefile
test:
	$(RUST_DOCKER) bash -c \
	    'cargo fmt --check && cargo clippy -- -D warnings && cargo audit && cargo test --lib --no-fail-fast'
```

Always inside Docker. Never `cargo test` directly on host.

## Cargo.toml — Release Profile (NON-NEGOTIABLE)

```toml
[profile.release]
# optimize for size
opt-level     = "z"
lto           = true
codegen-units = 1
strip         = true
panic         = "abort"
```

Always optimize for size (`opt-level = "z"`), always strip, always LTO — for release builds only. Dev/debug builds use Cargo defaults (no stripping, debug symbols preserved).

## Cargo.toml — Package Fields

```toml
[package]
name        = "{project_name}"
version     = "0.1.0"
edition     = "2021"
rust-version = "1.70"
authors     = ["{project_org}"]
license     = "MIT"
description = "..."
repository  = "https://github.com/{project_org}/{project_name}"
```

- Edition is always `2021`
- `rust-version` (MSRV) is required; set to the oldest Rust release the code compiles against; CI must test against this version
- `Cargo.lock` is always committed for binary crates; library crates should NOT commit `Cargo.lock` (allows consumers to use their own resolution)

## Exit Codes

Use standard POSIX / sysexits codes — never invent custom schemes. Full table is in `~/.claude/memory/script_conventions.md`. `--help` and `--version` always exit `0`; signal exits are `128 + signal` (SIGINT=130, SIGTERM=143).

For Rust, use the `sysexits` crate or define constants locally. `clap` exits `2` on parse errors automatically — do not override this. Use `std::process::ExitCode` (stable since 1.61) over `std::process::exit()` where possible to allow destructors to run.

## CLI Flags — Standard Interface

### Standard flags (all Rust TUI/CLI binaries)

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 — never escalate privileges |
| `--version` | `-v` | — | Print version and exit 0 — never escalate privileges |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output — `auto`: TTY detect; `yes`: force on; `no`: force off |

- `--color auto` detects terminal capability (default); `yes` forces color; `no` disables it and removes emojis from output.
- All flags must support both `--flag value` and `--flag=value` — clap handles this natively.
- `--help` and `--version` must never require root — always exit immediately with the requested output.
- `help` (bare, no `--`) must be a registered subcommand at every level — `myapp help` and `myapp subcmd help` produce the same output as their `--help` equivalents.
- **No escalation** — help at every level (main, subcommand, nested) must never call `sudo`, require root/admin, or check privilege state; exit immediately with the help text.

### Toggle flags — `--enable`, `--disable`, `--yes`, `--no`

Never use compound hyphenated flags (`--enable-tls`, `--disable-cache`). The flag takes the feature name as a required argument: `--enable tls`, `--disable cache`. Same pattern for `--yes` and `--no`.

**Exception:** `--color` is the standard three-value enum — `--color auto`, `--color yes`, `--color no`. There is no `--no-color` flag; `--color no` and the `NO_COLOR` env var both disable color.

```rust
// Declare toggle flags with clap derive — never compound hyphenated names.
#[derive(Parser)]
struct Cli {
    /// Enable a named feature
    #[arg(long, value_name = "FEATURE")]
    enable: Option<String>,

    /// Disable a named feature
    #[arg(long, value_name = "FEATURE")]
    disable: Option<String>,

    /// Confirm yes for a named operation
    #[arg(long, value_name = "THING")]
    yes: Option<String>,

    /// Confirm no for a named operation
    #[arg(long, value_name = "THING")]
    no: Option<String>,
}
```

Both `--enable featurename` and `--enable=featurename` work — clap handles both natively.

### Help output format

**Applies everywhere help is shown** — `--help`, `help` (bare subcommand), and `subcommand help`. All produce identical output via the same function.

Item left-aligned in a 38-character field, then `- `, then description ≤ 100 chars (140 max per line):

```
--help                                - Show this help message and exit
--version                             - Show version and exit
init                                  - Initialize a new project
```

Set a custom `clap` `HelpTemplate` on the root command and every subcommand to match this format — `clap`'s built-in template does not follow the 38-char alignment. Define the template string as a shared constant so it is applied consistently everywhere.

`help` (bare, no `--`) must be a registered subcommand at every level that calls the same help output as `--help`:
- `myapp help` == `myapp --help`
- `myapp subcmd help` == `myapp subcmd --help`

### NO_COLOR support

Every Rust TUI/CLI binary must honor the `NO_COLOR` environment variable ([no-color.org](https://no-color.org/)):

```rust
// Color resolution order (highest precedence first):
// 1. --color=no  or  --color=yes
// 2. NO_COLOR env var present (any value) → disable color and emojis
// 3. --color=auto → check atty::is(Stream::Stdout)
fn resolve_color(flag: &str) -> bool {
    match flag {
        "yes" => true,
        "no"  => false,
        // "auto"
        _     => {
            if std::env::var_os("NO_COLOR").is_some() {
                return false;
            }
            atty::is(atty::Stream::Stdout)
        }
    }
}
```

### Flag parsing — use `clap`

Use `clap` (derive API) for all argument parsing — never hand-roll. `clap` supports `--flag=value` and `--flag value` natively; `--help` and `--version` are generated automatically.

```rust
#[derive(Parser)]
#[command(name = env!("CARGO_PKG_NAME"), version, about, long_about = None)]
struct Cli {
    /// Color output: auto, yes, no
    #[arg(long, default_value = "auto", value_parser = ["auto", "yes", "no"])]
    color: String,

    /// Enable debug output
    #[arg(long)]
    debug: bool,
}
```

`clap` derive generates `-h`/`--help` and `-V`/`--version` by default. Override `-V` to `-v` with `#[command(version, short_flag = 'v')]` if needed to match the convention.

## Terminal Display — Alt Buffer and Crossterm

Any Rust binary that is a TUI or acts as a TUI must use the alternate screen buffer. Use `crossterm` — never write raw ANSI strings or shell out to `tput`.

Add to `Cargo.toml`:
```toml
crossterm = "0.28"
```

### Enter / leave functions

```rust
use crossterm::{
    cursor, execute,
    terminal::{self, EnterAlternateScreen, LeaveAlternateScreen},
};
use std::io::{self, Write};

fn enter_tui() -> io::Result<()> {
    terminal::enable_raw_mode()?;
    execute!(
        io::stdout(),
        EnterAlternateScreen,
        cursor::SetCursorStyle::BlinkingBar,
    )
}

fn leave_tui() -> io::Result<()> {
    execute!(
        io::stdout(),
        LeaveAlternateScreen,
        cursor::SetCursorStyle::DefaultUserShape,
    )?;
    terminal::disable_raw_mode()
}
```

`SetCursorStyle::BlinkingBar` is the I-beam blinking cursor. `DefaultUserShape` restores the terminal's configured default on exit.

### Cleanup guard

Implement `Drop` so the terminal is always restored, including on panic:

```rust
struct TuiGuard;

impl Drop for TuiGuard {
    fn drop(&mut self) {
        let _ = leave_tui();
    }
}
```

Call `enter_tui()` once at startup, then bind `let _guard = TuiGuard;` — the guard restores the terminal when it drops, regardless of exit path.

### ratatui shortcut

If using `ratatui`, use its init/restore helpers — they wrap crossterm and handle alt buffer, raw mode, and cursor automatically:

```rust
let mut terminal = ratatui::init();
// ... run app ...
ratatui::restore();
```

Do not manually call `enter_tui`/`leave_tui` when using ratatui — it manages setup and teardown.

### NO_COLOR

Suppress all terminal styling (colors, cursor changes) when `NO_COLOR` is set or `--color=no` is in effect. Check before emitting any `SetForegroundColor`, `SetAttribute`, or cursor style command. Use the `resolve_color` function from the CLI Flags section.

---

## Dependency Rules

- **No `*-sys` dynamic linkage** — vendored C deps must be statically linked; no `.so`/`.dylib`/`.dll` at runtime
- **No GPL/AGPL/LGPL without exception** — static linking would relicense the binary; requires explicit `{project_dir}/IDEA.md` exception
- **No `dlopen` or runtime extension loading** — unless `{project_dir}/IDEA.md` defines a hardened plugin contract
- **No CDN/network fetch on first run** — all assets embedded at build time; binary works air-gapped
- **`ring` is pre-approved** as a C-vendored exception (crypto)
- Prefer `rustls` over OpenSSL: `reqwest = { ..., features = ["rustls-tls"], default-features = false }`

## GUI Rules

GUI surfaces must support **both X11 and Wayland** as first-class backends — not one as fallback:
- Linux: GTK4 + libadwaita (`gtk4`, `libadwaita` crates)
- macOS: system frameworks (Cocoa/AppKit)
- Windows: Win32 or WinUI

## Static Binary Rules

- Linux: musl target for fully static binary (`x86_64-unknown-linux-musl`) where no native libs needed
- Windows: static CRT via MinGW GNU targets (`x86_64-pc-windows-gnu`, `aarch64-pc-windows-gnullvm`) — `casjaysdev/rust:latest` ships no MSVC toolchain, so `*-pc-windows-msvc` is not buildable in the standard image
- macOS: link against system frameworks — no dylib vendoring
- `strip = true` in release profile handles symbol stripping

## Linting & Formatting

- **`cargo fmt`** — enforced; run `cargo fmt --check` in CI; a format failure is a build failure. Commit `rustfmt.toml` at project root if non-default settings are needed.
- **`cargo clippy`** — enforced; always run with `-D warnings` (warnings are errors); no `#[allow(...)]` suppressions without an explanatory comment on the line above
- Never suppress a clippy lint project-wide in `Cargo.toml` without documenting the reason in `{project_dir}/IDEA.md`
- **Line width:** `rustfmt` default — `max_width = 100`. Do not override unless `rustfmt.toml` explicitly sets a different value. Never add a `rustfmt.toml` just to change the width; only create one when other non-default settings are genuinely needed.

## Error Handling

- **`anyhow` for application (binary) crates** — use `anyhow::Result` as the return type in `main()` and internal functions that aren't public API; `context()` / `with_context()` to annotate errors with call-site meaning
- **`thiserror` for library crates** — define custom error types with `#[derive(thiserror::Error)]`; each variant carries a human-readable `#[error("...")]` message; no `anyhow` in library public API
- **No `unwrap()` or `expect()` in library or production hot-path code** — return `Result` instead; `unwrap()`/`expect()` are only acceptable in tests, examples, and build scripts where a panic is the right failure mode
- **`?` for propagation** — always use `?` to propagate errors up the call stack; never `.unwrap()` where a `?` would work
- **`Box<dyn Error>` is acceptable only in tests and throwaway scripts** — never in library public API or long-lived production code
- **Structured error context** — add context at every boundary crossing (IO, network, DB, subprocess); bare errors like `"No such file or directory"` are useless without context: prefer `fs::read(&path).with_context(|| format!("reading config from {path:?}"))`
- **No silent error swallowing** — never `let _ = fallible_call()` unless the error is genuinely irrelevant; document why with a comment when it is

```toml
# Cargo.toml — standard error handling deps
[dependencies]
# application crates
anyhow  = "1"
# library crates (pick one, not both)
thiserror = "2"
```

---

## Directory Naming

**Plural** — all directories use plural names (`handlers/`, `models/`, `routes/`, `utils/`). Tooling dirs are also plural (`scripts/`, `tests/`, `completions/`). Rust module names (inside `src/`) follow the same rule — `src/handlers/mod.rs` not `src/handler/mod.rs`.

## Code Rules

- **No bare `cargo` on host** — all cargo invocations run inside Docker
- **Strip release binaries** — `strip = true` in `[profile.release]` (handled by Cargo) plus an explicit `strip {binary} 2>/dev/null || true` in the Makefile after copy, for toolchains that ignore the profile flag. Debug/dev builds (`cargo build` without `--release`) are never stripped — debug symbols are preserved intentionally
- **No `-musl` suffix** — never include `-musl` in the output binary name; schema is `{name}-{os}-{arch}` regardless of target triple (e.g. `x86_64-unknown-linux-musl` still outputs `{name}-linux-amd64`)
- **Rust-only source** — no C/C++ in the binary (ring is the pre-approved exception)
- **Embed assets at build time** — use `include_bytes!`, `include_str!`, or the `built` crate; never load from filesystem at runtime
- **No hardcoded temp paths** — use `std::env::temp_dir()` and always prefix with `{project_org}/{internal_name}-XXXXXX` (`{internal_name}` is the stable on-disk identifier; never `{project_name}` which may change). See `tempdir_conventions.md`.
- **No external cron** — never depend on host cron or systemd timers for application-level scheduling. Use in-process scheduling only: `tokio::time::interval` / `tokio::time::sleep` for async periodic tasks; a `std::thread::sleep` loop for sync periodic tasks; the `cron` crate for cron-expression parsing. Never `std::process::Command::new("cron")` or similar.
