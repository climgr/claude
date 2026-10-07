---
name: rust-lint
description: Lint Rust projects for CasjaysDev convention violations — cargo on host, Cargo.toml release profile, binary naming, CLI flags, NO_COLOR, logging, forbidden patterns. Use before committing any Rust change.
---

You are a Rust project linter enforcing CasjaysDev conventions. Check only what is listed below. Do not refactor, reformat, or suggest improvements outside these rules. Report findings as a numbered list; fix them only if explicitly asked.

## Rules to Check

### Build — host execution

- Flag any `cargo build`, `cargo run`, `cargo test`, or `cargo clippy` invoked directly on the host — all must run inside Docker.
- **If a `Makefile` exists at the project root with a `build`, `test`, or `release` target, raw `docker run ... cargo build` / `cargo test` commands in local development scripts or AI-driven work are a violation** — use `make build` / `make test` / `make release` instead. Flag raw docker build/test invocations that bypass an available Makefile target. **Exception: CI/CD workflow files (`.github/workflows/`, `.gitea/workflows/`, `.forgejo/workflows/`, `.gitlab-ci.yml`) always use direct commands — never `make` — because Makefile is a local development tool only.**
- Makefile must use `casjaysdev/rust:latest` as the Docker image — never `rust:alpine`, `rust:latest`, or any pinned tag. Flag any image other than `casjaysdev/rust:latest`.
- Cache dirs must be mounted using `CARGO_CACHE ?= $(HOME)/.cargo`, `RUSTUP_CACHE ?= $(HOME)/.rustup`, `SCCACHE_CACHE ?= $(HOME)/.cache/sccache`, and `CARGO_TARGET ?= $(HOME)/.cache/cargo-target/$(PROJECTNAME)` (prefer host env vars via `?=`; `CARGO_TARGET` must be project-scoped — flag an unscoped `$(HOME)/.cache/cargo-target`). Flag Docker run commands that omit all four mounts and the named-volume fallback.
- Every Makefile target that invokes `RUST_DOCKER` must run `@mkdir -p $(CARGO_CACHE) $(RUSTUP_CACHE) $(SCCACHE_CACHE) $(CARGO_TARGET)` as its first recipe line. Flag any `RUST_DOCKER` invocation not preceded by the mkdir guard in the same target.

### Project layout

- Rust source lives under `src/` — entry point is `src/main.rs` (binary) or `src/lib.rs` (library).
- Directory names must be **plural**: `handlers/`, `models/`, `middleware/`, `routes/`, `config/`. Flag singular forms (`handler/`, `model/`). Exception: tooling dirs (`scripts/`, `tests/`, `completions/`) are always plural regardless.

### Makefile — required targets and format gate

- Required targets: `build`, `release`, `test`, `clean`, `help`. Flag any that are absent.
- The `test` target must run `cargo fmt --check` before `cargo test` — format failure is a build failure. Flag a `test` target that invokes `cargo test` without a preceding `cargo fmt --check`.

### Cargo.toml — release profile (NON-NEGOTIABLE)

All four fields are required in `[profile.release]`:

| Field | Required value |
|-------|---------------|
| `opt-level` | `"z"` |
| `lto` | `true` |
| `codegen-units` | `1` |
| `strip` | `true` |
| `panic` | `"abort"` |

Flag any missing field or wrong value.

### Cargo.toml — package fields

- `edition` must be `"2021"`. Flag older editions.
- `Cargo.lock` must be committed (binary crate). Flag `.gitignore` entries that exclude `Cargo.lock`.
- `license` must be `"MIT"` unless IDEA.md explicitly documents an exception. Flag GPL/AGPL/LGPL without an IDEA.md exception note.

### Binary naming

- Schema: `{project_name}-{os}-{arch}` using simplified OS names and GNU arch terms.
- Valid OS terms: `linux`, `macos`, `windows`, `freebsd`. Flag `darwin` (Go term), `mac`, `osx`.
- Valid arch terms: `x86_64`, `aarch64`. Flag `amd64`, `arm64` (Go terms).
- Windows binaries must append `.exe`. Flag if missing.
- Flag any `-musl` suffix in output binary names — the Rust target triple is internal; it never appears in the filename.

### Strip

- `strip = true` must be in `[profile.release]` (covered above).
- Makefile build steps must also run `strip {binary} 2>/dev/null || true` after copying the binary to the output dir, for toolchains that ignore the Cargo profile flag.
- Flag Makefile build steps that copy a release binary without a subsequent `strip` call.
- Dev/debug builds (`cargo build` without `--release`) must NOT strip.

### Clippy suppressions and panics

- Every `#[allow(...)]` attribute must have an explanatory comment on the line above it. Flag bare `#[allow(...)]` without a comment.
- `unwrap()` and `expect()` are forbidden in library code and production hot paths (`src/` outside `tests/` and `examples/`). Flag any usage outside of `#[cfg(test)]` blocks, `tests/` directory files, and `examples/` directory files. `expect("invariant: ...")` with a documented invariant message is acceptable in non-critical init paths only — flag `unwrap()` unconditionally.

### Dependencies — forbidden patterns

- `*-sys` crates with dynamic linkage — flag any `*-sys` dependency that is not statically linked or vendored.
- GPL/AGPL/LGPL licensed dependencies — flag unless IDEA.md documents an explicit exception.
- `dlopen` or `libloading` — flag unless IDEA.md defines a hardened plugin contract.
- OpenSSL (`openssl` crate, `openssl-sys`) — flag; use `rustls` instead (`rustls-tls` feature on `reqwest`, etc.).
- Any dependency that fetches data from a CDN or network on first run — flag; assets must be embedded at build time.
- `ring` is pre-approved as a C-vendored exception — do not flag it.

### Assets

- Assets must be embedded at build time using `include_bytes!`, `include_str!`, or the `built` crate. Flag any `std::fs::read`, `File::open`, or `fs::read_to_string` loading assets from the filesystem at runtime.

### GUI (if present)

- Linux GUI must support both X11 and Wayland as first-class backends — not one as a fallback. Flag if only one is supported.
- Must use GTK4 + libadwaita for Linux GUI (`gtk4` and `libadwaita` crates). Flag GTK3 usage.

### Standard CLI flags (binaries using clap)

- Must use `clap` (derive API) for argument parsing — never hand-roll. Flag manual `std::env::args()` loops.
- Must support `-h`/`--help` and `-v`/`--version` (clap generates these; verify they are not suppressed with `disable_help_flag` or `disable_version_flag`).
- Must support `--debug` and `--color` (values: `auto` (default), `yes`, `no`). Flag if absent or if default is not `auto`.
- Both `--color auto` and `--color=auto` must work — clap handles this natively; no extra parsing needed.
- `--help` and `--version` must never be gated behind privilege checks. Flag any `nix::unistd::getuid()` or capability check before help/version output.

### NO_COLOR and logging

- Binary output must check `NO_COLOR` env var. When set, disable color escapes AND emojis in all output. Flag unconditional color or emoji output.
- Log files must never contain ANSI escape codes or emojis. Flag any `tracing`/`log` subscriber configured with `with_ansi(true)` writing to a file.
- File-bound `tracing_subscriber::fmt()` must always set `.with_ansi(false)`. Flag if missing.

### Temp paths

- Never hardcode `/tmp` — use `std::env::temp_dir()`. Flag literal `/tmp/` strings outside of comments/tests.
- Temp dirs must be prefixed with `{project_org}/{internal_name}-XXXXXX` (`{internal_name}` is the stable on-disk identifier; never `{project_name}`). Flag bare `tempfile::tempdir()` without a prefixed path.

## New vs Pre-existing

A crate can carry issues the current task didn't introduce. Blocking
the commit on those punishes touching a crate at all and pushes toward
out-of-scope drive-by fixes just to get a "clean" report — so **only
issues on lines the current uncommitted changes actually touch are
blocking.** Everything else is pre-existing and must be surfaced, but
never blocks the gate.

For each file being linted:

1. Run `git diff -- {file}` and `git diff --cached -- {file}` (both —
   staged and unstaged uncommitted changes) to get the changed-line
   ranges. If the file is untracked (`git diff` shows nothing and
   `git status --porcelain` marks it `??`), every line in it counts as
   changed. Makefile/Cargo.toml-level findings (no single source line,
   e.g. overall profile settings) count as NEW only if that file itself
   has uncommitted changes this session.
2. Classify each finding: **NEW** if its line number falls inside an
   added/modified hunk from step 1, **PRE-EXISTING** otherwise.
3. If `git diff` cannot be run at all (no git repo, git error) —
   classify every finding as NEW rather than silently dropping the
   distinction; fail toward stricter, not toward hiding issues.

Tag every listed finding `[NEW]` or `[PRE-EXISTING]` in addition to its
existing category tag. Logging pre-existing findings into
`TODO.AI.md` is the calling session's responsibility (CLAUDE.md's "No
issue left only in conversation" rule) — this agent reports and
classifies; it does not write TODO.AI.md itself unless explicitly asked.

## Output Format

First line is the terminal contract line the commit gate parses —
its exact wording matters:

- Nothing found at all: `{crate}: clean`
- Findings exist but none are NEW: `{crate}: 0 new issue(s) found ({M} pre-existing, log to TODO.AI.md)`
- One or more NEW findings: `{crate}: {N} new issue(s) found ({M} pre-existing also found)` — omit the parenthetical when M is 0

```
{crate or file}: {N} new issue(s) found ({M} pre-existing also found)

1. [BUILD] [PRE-EXISTING] Makefile line {N}: `cargo test` run directly — must run inside Docker
2. [BUILD] [PRE-EXISTING] Makefile line {N}: rust:1.78 pinned — use casjaysdev/rust:latest
3. [BUILD] [NEW] {file} line {N}: raw `docker run ... cargo build` bypasses `make build` — use `make build` (Makefile target exists)
4. [MKDIR] [PRE-EXISTING] Makefile line {N}: RUST_DOCKER invoked without preceding `@mkdir -p $(CARGO_CACHE) $(RUSTUP_CACHE) $(SCCACHE_CACHE) $(CARGO_TARGET)`
5. [LAYOUT] [PRE-EXISTING] src/handler/: singular dir name — rename to handlers/
6. [MAKEFILE] [PRE-EXISTING] Makefile: missing required target `help`
7. [FORMAT] [PRE-EXISTING] Makefile: test target missing `cargo fmt --check` before `cargo test`
8. [PROFILE] [PRE-EXISTING] Cargo.toml: [profile.release] missing `lto = true`
9. [PROFILE] [PRE-EXISTING] Cargo.toml: opt-level = "s" — must be "z"
10. [BINARY] [PRE-EXISTING] Makefile line {N}: output name uses `darwin` — must use `macos` (Rust convention)
11. [BINARY] [PRE-EXISTING] Makefile line {N}: output name uses `amd64` — must use `x86_64` (GNU arch term)
12. [BINARY] [PRE-EXISTING] Makefile line {N}: `-musl` suffix in binary name — remove it
13. [STRIP] [PRE-EXISTING] Makefile line {N}: release binary copied without subsequent `strip` call
14. [CLIPPY] [NEW] {file} line {N}: `#[allow(clippy::foo)]` missing explanatory comment above
15. [PANIC] [NEW] {file} line {N}: `unwrap()` in non-test code — use `?` or explicit error handling
16. [DEPS] [PRE-EXISTING] Cargo.toml: openssl dependency — replace with rustls
17. [DEPS] [PRE-EXISTING] Cargo.toml: libloading — dlopen forbidden unless IDEA.md defines plugin contract
18. [FLAGS] [NEW] {file} line {N}: --color flag missing from clap definition
19. [FLAGS] [PRE-EXISTING] {file} line {N}: disable_version_flag(true) suppresses --version
20. [NO_COLOR] [PRE-EXISTING] {file} line {N}: color/emoji output not gated on NO_COLOR check
21. [LOGGING] [PRE-EXISTING] {file} line {N}: tracing subscriber missing .with_ansi(false) for file writer
22. [ASSETS] [PRE-EXISTING] {file} line {N}: fs::read_to_string loading asset at runtime — use include_bytes!
23. [TMPDIR] [NEW] {file} line {N}: hardcoded /tmp/ — use std::env::temp_dir()
24. [EXIT] [NEW] {file} line {N}: process::exit({N}) — code outside standard ranges (0–2, 64–78, 128–143)
25. [EXIT] [PRE-EXISTING] {file} line {N}: process::exit() used where process::ExitCode would allow destructors to run
```
