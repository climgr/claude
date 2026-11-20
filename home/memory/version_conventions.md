---
name: Version conventions
description: How version strings originate in release.txt, flow through the build pipeline, and land in binaries, Docker images, and GitHub releases
type: user
---

## Source of Truth: `release.txt`

`release.txt` at the project root is the canonical version source for all projects:

```
1.3.0
```

- One line, semver format (`MAJOR.MINOR.PATCH`), no `v` prefix
- Never hardcode the version string anywhere else in source code
- Makefile reads it: `VERSION ?= $(shell cat release.txt 2>/dev/null || echo "devel")`
- `?=` allows one-time override: `make build VERSION=1.3.1-rc1`
- If `release.txt` is absent, the build falls back to `devel` — signals an unversioned build. The reported version (`--version`) is SemVer for a release, `YYYYMMDDHHMMSS-beta` for a beta, and the short commit id for a devel build; never the word `devel`, and `dev` only when none of these apply

---

## Version Flow

```
release.txt
    └─> Makefile VERSION variable
            ├─> Binary  — LDFLAGS / env var → --version output
            ├─> Docker  — image tags: :{version}, :latest, :YYMM, :{commit}
            └─> Release — GitHub release tag v{version}, checksum file, SBOM
```

Every downstream consumer reads from the single Makefile `VERSION` variable — never re-reads `release.txt` directly.

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
// version set from Cargo.toml [package] version field;
// CommitID and BuildDate injected via build.rs reading env vars:
// println!("cargo:rustc-env=COMMIT_ID={}", std::env::var("COMMIT_ID").unwrap_or_default());
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const COMMIT_ID: &str = env!("COMMIT_ID");
pub const BUILD_DATE: &str = env!("BUILD_DATE");
```

Keep `Cargo.toml` version in sync with `release.txt` — they must match.

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
- `:devel` is NOT part of the push tags: it comes from a separate `build-devel` job inside `docker.yml` (schedule + non-tag push, gated by `if:`), built from `docker/Dockerfile.dev`

---

## Git Release Tag Convention

A stable git tag may be `v1.2.3` or `1.2.3`; `release.txt` never carries the `v`. The tag below uses the `v` form:

```
release.txt: 1.3.0
git tag:     v1.3.0
```

A beta release name has no `v` (`20251205-beta`). The devel release is ONE rolling release named `devel`: each devel build deletes and replaces the previous one.

CI detects a tagged release via `startsWith(github.ref, 'refs/tags/v')`.

---

## Bumping the Version

1. Edit `release.txt` — update to the new semver string
2. For Rust: update `[package] version` in `Cargo.toml` to match
3. Commit: `📦 Bump version to {version} 📦` — standalone commit, no other changes
4. CI tags on release: `git tag v{version}` (triggered by the release workflow or manually for hotfixes)

Never mix a version bump with feature or fix changes — version bump is always its own commit.

---

## CI/CD Version Precedence

| Source | Priority | When used |
|--------|----------|-----------|
| `VERSION` environment variable | Highest (wins over `release.txt` when set) | Explicit override |
| `release.txt` | High | Normal projects — always present |
| Git tag (`v*`) | Fallback | `release.txt` absent; running from a tag |
| `git describe` | Fallback | No tag on this commit |
| `"0.1.0-dev"` | Last resort | New project, no release yet |

---

## Semver Rules for This Project

| Change type | Version bump |
|-------------|-------------|
| Bug fix, security patch | Patch (`1.2.3` → `1.2.4`) |
| New feature, new option, new endpoint (backward-compatible) | Minor (`1.2.x` → `1.3.0`) |
| Breaking API change, removed functionality, incompatible behavior change | Major (`1.x.y` → `2.0.0`) |
| Tests, docs, CI, dependency bumps (no behavior change) | **None** — not a version bump |
| Dependency security update (CVE fix, no API change) | Patch |
