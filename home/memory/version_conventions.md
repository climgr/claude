---
name: Version conventions
description: How version strings originate (CI channel rule, local release.txt), flow through the build pipeline, and land in binaries, Docker images, and GitHub releases
type: user
---

## Source of Truth: CI tag/channel; `release.txt` for local builds

CI derives the version from the channel (see CI/CD Version Precedence). `release.txt` at the project root is the optional version source for local Makefile builds only:

```
1.3.0
```

- One line, semver format (`MAJOR.MINOR.PATCH`), no `v` prefix
- Never hardcode the version string anywhere else in source code
- Optional: empty or missing means the devel rule
- Only the Makefile reads it (local testing and debugging); CI/CD never reads it
- Makefile: `VERSION ?= $(shell v=; [ -r release.txt ] && v=$$(tr -d '[:space:]' < release.txt); if [ -n "$$v" ]; then echo "$$v"; else git rev-parse --short=7 HEAD 2>/dev/null || echo devel; fi)`
- `?=` lets an explicitly set `VERSION` env var override it: `make build VERSION=1.3.1-rc1` (user only; AI never sets `VERSION`)
- If `release.txt` is empty or missing, the devel rule applies: the short commit id, or `devel` outside a git checkout. The reported version (`--version`) is SemVer for a release, `YYYYMMDDHHMMSS-beta` for a beta, and the short commit id for a devel build inside a git checkout; the word `devel` appears only for a local build outside a git checkout, and `dev` only when none of these apply

---

## Version Flow

```
release.txt
    └─> Makefile VERSION variable
            ├─> Binary  — LDFLAGS / env var → --version output
            ├─> Docker  — image tags: :{version}, :latest, :YYMM, :{commit}
            └─> Release — GitHub release tag v{version}, checksum file, SBOM
```

Every downstream consumer reads from the single Makefile `VERSION` variable (local builds) — never re-reads `release.txt` directly. CI computes `VERSION` per channel and never reads `release.txt`.

---

## Binary Version Variables

### Go

```go
// main.go — set by LDFLAGS at build time
var (
    // -X 'main.Version=$(VERSION)'
    Version   = "devel"
    // -X 'main.CommitID=$(COMMIT_ID)'
    CommitID  = "unknown"
    // -X 'main.BuildEpoch=$(BUILD_EPOCH)'
    BuildEpoch = "0"
    // -X 'main.OfficialSite=$(OFFICIAL_SITE)'
    OfficialSite = ""
    // derived from BuildEpoch in init(); not an ldflag
    BuildDate = "unknown"
)
```

`BuildEpoch` (Unix seconds, UTC) is the only build-time ldflag for the build time; `BuildDate` is derived from it in `init()`.

`--version` output: `{project_name} {Version} ({CommitID}) built {BuildDate}`

### Rust

```rust
// build.rs emits VERSION, BUILD_EPOCH, COMMIT_ID and OFFICIAL_SITE from the build environment:
// println!("cargo:rustc-env=VERSION={}", std::env::var("VERSION").unwrap_or_else(|_| env!("CARGO_PKG_VERSION").into()));
pub const VERSION: &str = env!("VERSION");
pub const COMMIT_ID: &str = env!("COMMIT_ID");
```

`VERSION` comes from the build environment (the Makefile for local builds, the pushed tag in CI); the `Cargo.toml` `[package] version` is only the fallback when `VERSION` is unset, so it does not have to track `release.txt`.

### Node / TypeScript

```typescript
// src/version.ts
export const VERSION = process.env["BUILD_VERSION"] ?? "dev";
export const COMMIT_ID = process.env["BUILD_COMMIT"] ?? "unknown";
export const BUILD_DATE = process.env["BUILD_DATE"] ?? "unknown";
```

Pass via `--build-arg` in Docker or `--env` at container start.

### Python

```python
# src/{package_name}/version.py
import importlib.metadata
import os

VERSION = os.environ.get("BUILD_VERSION") or importlib.metadata.version("{package_name}")
COMMIT_ID = os.environ.get("BUILD_COMMIT", "unknown")
BUILD_DATE = os.environ.get("BUILD_DATE", "unknown")
```

---

## Docker Image Tags

| Context | Tags applied |
|---------|-------------|
| Any push | `:{commit_id}` only |
| Beta branch push | `:beta`, `:{commit_id}` |
| Tagged release | `:{version}`, `:latest`, `:YYMM`, `:{commit_sha_short}` |

- `YYMM` = two-digit year + two-digit month (e.g. `2505` for May 2025) — monthly snapshot pin
- **Never tag a non-release build as `:latest`** — `:latest` is for tagged releases only
- `:{commit_sha_short}` on every push enables pinning to a specific build
- `:devel` is NOT part of the push tags: it comes from a separate `build-devel` job inside `docker.yml` (daily schedule + `workflow_dispatch` + push, gated by `if:` to `main`/`master` only; there is no `devel` or `dev` branch), built from `docker/Dockerfile.dev`

---

## Git Release Tag Convention

A stable git tag may be `v1.2.3` or `1.2.3`; CI strips a leading `v` to get the version, and `release.txt` (local builds) never carries the `v`. The tag below uses the `v` form:

```
release.txt: 1.3.0
git tag:     v1.3.0
```

A beta release name has no `v` (`20251205-beta`). The devel release is ONE rolling release named `devel`: each devel build deletes and replaces the previous one.

CI detects a tagged release via `startsWith(github.ref, 'refs/tags/v')`.

---

## Bumping the Version

1. Edit `release.txt` (if the project keeps one) — update to the new semver string
2. For Rust: `[package] version` in `Cargo.toml` is only the fallback when `VERSION` is unset — bump it only when the project keeps it current
3. Commit: `📦 Bump version to {version} 📦` — standalone commit, no other changes
4. CI tags on release: `git tag v{version}` (triggered by the release workflow or manually for hotfixes)

Never mix a version bump with feature or fix changes — version bump is always its own commit.

---

## CI/CD Version Precedence

CI/CD (workflows never read `release.txt` or the `VERSION` env var):

1. Release (tag push): the pushed tag with a leading `v` stripped (`v1.2.3` and `1.2.3` both give `1.2.3`)
2. Devel: `git rev-parse --short=7 HEAD`
3. Beta: the `YYYYMMDDHHMMSS-beta` tag version

Local builds (Makefile only — testing and debugging):

1. `VERSION` environment variable, only when explicitly set by the user (AI never sets it)
2. `release.txt`, when present and non-empty
3. Otherwise the devel rule: short commit id, or `devel` outside a git checkout

---

## Semver Rules for This Project

| Change type | Version bump |
|-------------|-------------|
| Bug fix, security patch | Patch (`1.2.3` → `1.2.4`) |
| New feature, new option, new endpoint (backward-compatible) | Minor (`1.2.x` → `1.3.0`) |
| Breaking API change, removed functionality, incompatible behavior change | Major (`1.x.y` → `2.0.0`) |
| Tests, docs, CI, dependency bumps (no behavior change) | **None** — not a version bump |
| Dependency security update (CVE fix, no API change) | Patch |
