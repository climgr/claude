---
name: Temp directory conventions
description: Rules for creating and using temporary directories in all languages; project directory is source code only
type: user
---

## Core Rule

**The project directory is for SOURCE CODE ONLY.** All runtime data, test data, and build artifacts go to the OS temp directory. Never write runtime or test output into the project tree.

## Required Pattern

The ONLY acceptable temp directory structure:

```
${TMPDIR:-/tmp}/{project_org}/{internal_name}-XXXXXX/
```

- `${TMPDIR:-/tmp}` — always use the OS env var; never hardcode `/tmp`
- `{project_org}/` — organization prefix so dirs are identifiable and cleanable by project
- `{internal_name}-XXXXXX` — project name + random suffix from `mktemp`

`{internal_name}` is used (not `{project_name}`) because it is stable across ordinary project renames.

## FORBIDDEN

| Pattern | Why |
|---------|-----|
| `/tmp/myfile` | Bare root tmp — unidentifiable, collides |
| `/tmp/{project_name}` | Missing org prefix |
| `mktemp -d` | No org/project structure |
| `/tmp/test-data/` | Generic path — not namespaced |
| Hardcoded org name | Must be detected, never hardcoded |
| Writing test/runtime data into project dir | Project dir = source code only |

## Creating Temp Directories — Per Language

### Shell / Bash

```bash
mkdir -p "${TMPDIR:-/tmp}/${PROJECT_ORG}"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_ORG}/${INTERNAL_NAME}-XXXXXX")
```

### Go

```go
base := filepath.Join(os.TempDir(), projectOrg)
os.MkdirAll(base, 0755)
dir, err := os.MkdirTemp(base, projectName+"-")
```

Never call `os.TempDir()` alone — always nest under `{project_org}/`.

### Rust

```rust
let base = std::env::temp_dir().join(&project_org);
std::fs::create_dir_all(&base)?;
// tempfile crate:
let dir = tempfile::Builder::new()
    .prefix(&format!("{}-", project_name))
    .tempdir_in(&base)?;
```

Or without the `tempfile` crate:

```rust
let base = std::env::temp_dir().join(&project_org);
std::fs::create_dir_all(&base)?;
let dir = base.join(format!("{}-{}", project_name, random_suffix()));
std::fs::create_dir_all(&dir)?;
```

Never call `std::env::temp_dir()` alone — always nest under `{project_org}/`.

### Python

```python
import os
import tempfile

base = os.path.join(tempfile.gettempdir(), project_org)
os.makedirs(base, exist_ok=True)
temp_dir = tempfile.mkdtemp(prefix=f"{project_name}-", dir=base)
```

Never call `tempfile.mkdtemp()` alone — always pass `dir=` to nest under `{project_org}/`.

## Directory Permissions

Temp directories must be created with mode `0700` (owner-only access) when they may contain sensitive data (tokens, private keys, intermediate build artifacts with embedded secrets). Use `0755` only for non-sensitive build output that other processes legitimately need to read.

| Contents | Mode |
|----------|------|
| Sensitive data (keys, tokens, credentials) | `0700` |
| Non-sensitive build output | `0755` |

In Go, `os.MkdirTemp` creates with `0700` by default — do not change this for sensitive dirs. In shell, `mktemp -d` creates with `0700` by default — same rule applies.

## OS Temp Directories

| OS | Default | Env var |
|----|---------|---------|
| Linux | `/tmp` | `$TMPDIR` |
| macOS | `/var/folders/…/T/` | `$TMPDIR` |
| Windows | `%LocalAppData%\Temp` | `%TEMP%` |
| FreeBSD | `/tmp` | `$TMPDIR` |

Always use `${TMPDIR:-/tmp}` (shell) or `os.TempDir()` / `std::env::temp_dir()` — never hardcode the path.

## Directory Structure Inside the Temp Root

| Purpose | Pattern |
|---------|---------|
| Dev / test runtime | `{tempdir}/{project_org}/{internal_name}-XXXXXX/` |
| Config volume | `{tempdir}/{project_org}/{internal_name}-XXXXXX/volumes/config/` |
| Data volume | `{tempdir}/{project_org}/{internal_name}-XXXXXX/volumes/data/` |
| DB volume | `{tempdir}/{project_org}/{internal_name}-XXXXXX/volumes/db/` |
| Screenshots / downloads | `{tempdir}/{project_org}/{internal_name}-XXXXXX/` with filename |

## Cleanup

```bash
# List all temp dirs for this org
ls -la "${TMPDIR:-/tmp}/${PROJECT_ORG}/"

# Remove all temp dirs for this project (guard both vars — empty var → rm -rf /tmp/*)
[ -n "${PROJECT_ORG}" ] && [ -n "${INTERNAL_NAME}" ] && \
  rm -rf "${TMPDIR:-/tmp}/${PROJECT_ORG}/${INTERNAL_NAME}-"*

# Remove entire org temp tree (only when certain nothing else uses it)
[ -n "${PROJECT_ORG}" ] && rm -rf "${TMPDIR:-/tmp}/${PROJECT_ORG}/"
```

## AI-Specific Rules

- **NEVER** create or modify files in the project directory during testing — all runtime output goes to the temp dir
- **Coverage files are test output** — never write `coverage.out` or any coverage artifact to `$PWD`/the project tree. Where it goes depends on context:
  - **Single container invocation** (Makefile `sh -c "…"`): use `mkdir -p "/tmp/$(PROJECTORG)"` then `COVDIR=$(mktemp -d "/tmp/$(PROJECTORG)/$(PROJECTNAME)-XXXXXX")` — `$(PROJECTORG)` and `$(PROJECTNAME)` expand at Make-time, so the full structure is available. Write `-coverprofile="$COVDIR/coverage.out"`.
  - **CI `container:` job** (all steps share one container instance): `mkdir -p "/tmp/${{ github.repository_owner }}"`, `COVDIR=$(mktemp -d "/tmp/${{ github.repository_owner }}/$(basename "${{ github.repository }}")-XXXXXX")`, then `echo "COVDIR=$COVDIR" >> "$GITHUB_ENV"` so subsequent steps can read it.
  - **Multi-step `docker run` pattern** (step 1 writes via one `docker run`, step 2 reads via a separate `docker run`): `/tmp` is NOT shared across separate container invocations — write to the workspace-mounted path (e.g. `coverage.out` inside `-w /app`) so it persists between the two runs. The runner workspace is ephemeral and exempt.
  - **On the host (outside any container)**: follow the full tempdir convention — `${TMPDIR:-/tmp}/{project_org}/{internal_name}-XXXXXX/coverage.out`.
- **`$PWD` not `$(pwd)` in docker `-v` flags** — `$(pwd)` is a shell command substitution that Claude Code's static analyzer cannot resolve, triggering a permission prompt on every invocation. `$PWD` is statically analyzable and identical in value. In Makefiles, `$(PWD)` is the correct Makefile variable form.
- For Docker Compose testing rules, see `~/.claude/memory/dockerfile_conventions.md § AI Docker Compose rules`
