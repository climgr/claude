---
name: Testing conventions
description: Test structure, naming, unit vs integration split, coverage gates, mock strategy, and timing rules across Go, Rust, Node/TypeScript, Python, and shell projects
type: user
---

## Core Principle

Tests are written in the same work pass as the code they cover — never deferred to the end. If you add or change logic in a package, update the matching test file before moving on.

---

## Two Test Phases

All projects have exactly two test phases. They are distinct in purpose, command, and when they are required.

| Phase | Command | What It Tests | Runs in | Invocation |
|-------|---------|--------------|---------|------------|
| **Phase 1 — Toolchain Gate** | `make test` | Source-code logic via the language toolchain (`go test`, `cargo test`, etc.) — unit coverage, validation, error paths | Docker — `casjaysdev/go:latest` or `casjaysdev/rust:latest` | Automatic — required before every commit |
| **Phase 2 — Binary Validation** | `./tests/run_tests.sh` (basic tier, Docker only); `incus.sh`, optional `virt.sh` and `e2e.sh` are separate explicit runs | Compiled binary behavior — routes, auth flows, CLI/server interaction, service installs, container/Incus scenarios | Docker (`alpine:latest`), Incus containers (`debian/trixie` + `alpine`), optional Incus VMs | **Manual only** — developer-initiated |

- **Phase 1 is the commit gate** — `make test` must pass before every `gitcommit`. No exceptions.
- **Phase 2 is manual** — never run automatically; always developer-initiated after a binary is built (`make dev` / `make local`).
- **Both phases run in containers.** Neither runs directly on the host.

### Binary Execution Rule

**Never execute a built binary directly on the host.** This applies to AI and to human-readable instructions alike.

| NEVER | ALWAYS |
|-------|--------|
| `/path/to/binary --flag` on the host | `docker run --rm -v "$BUILD_DIR:/app" alpine:latest /app/{project_name} --flag` |
| `./binaries/{project_name}` on the host | Phase 2: `./tests/docker.sh` or `./tests/incus.sh` |
| `{project_name} serve` on the host | `make dev` → binary in temp dir → run inside Docker |

Run the binary in Docker (`alpine:latest`) for quick checks or in Incus (`debian:latest`) for full systemd/service testing. The Phase 2 scripts (`./tests/run_tests.sh`, `./tests/docker.sh`, `./tests/incus.sh`) handle this correctly — prefer them over ad-hoc `docker run` invocations.

### Phase 2 Trigger Phrases

When the user says any of the following, run Phase 2:

| Phrase | Action |
|--------|--------|
| "debug binary" / "binary debug" / "binary debug*" | `./tests/run_tests.sh` (basic tier, Docker only) |
| "test binary" / "binary test" / "binary test*" | `./tests/run_tests.sh` (basic tier, Docker only) |
| "run binary tests" | `./tests/run_tests.sh` |
| "binary validation" / "run phase 2" | `./tests/run_tests.sh` |

Test script tiers:

| Script | Tier |
|--------|------|
| `tests/run_tests.sh` | Basic tier: runs `docker.sh` only, never selects Incus |
| `tests/docker.sh` | Binary-validation suite in `alpine:latest`: starts, answers, endpoints, CLI, Tor/I2P health; no init system or service lifecycle |
| `tests/incus.sh [systemd\|openrc\|all]` | Full-app check in Incus CONTAINERS: `debian/trixie` (systemd) + `alpine/{latest_stable}` (OpenRC): the same suite plus service lifecycle, reboot persistence, Tor and I2P |
| `tests/virt.sh [systemd\|openrc\|all]` | OPTIONAL clean-OS check in real VMs, standalone |
| `tests/e2e.sh` | Browser E2E (Docker + Chromium), standalone |

`incus.sh`, `virt.sh` and `e2e.sh` are explicit developer runs; fall back to `./tests/docker.sh` where Incus is unavailable. Every operator-token route is tested with five requests in `docker.sh` and `incus.sh` alike (no header `401`, wrong token `401`, owner token `403`, real token `200`, token in the query string `401`), the token is never echoed, and the CLI is tested against the running server with a linked token (exit `0` plus one bad-token failure case).

**Test copies:** `tests/*.sh` may push the binary into a Docker/Incus test container and copy it under another name there (rename test); that copy lives only inside the container, is removed when the test ends, and `binaries/` is never modified. Copying or symlinking a binary anywhere on the host (`/tmp`, `/usr/local/bin`, `releases/` by hand) stays prohibited.

**Auth in tests:** use the setup token to create the admin, then test login; auth is tested, never bypassed (`--debug` never bypasses it). Fixtures live only in `testdata/`, hold obviously fake values, and a credential-shaped string needed by a test is built at run time in test code.

---

## Test Types and Where They Live

| Type | Location | Purpose | Measured by |
|------|----------|---------|-------------|
| **Unit tests** (Go) | `*_test.go` alongside source | Pure logic, validation, parsing, config, transforms, error mapping, handler logic with mocks/httptest | `go test -cover` |
| **Integration tests** | `tests/` at repo root | Full binary behavior: routes, auth flows, content negotiation, CLI↔server interaction, service installs | Shell scripts (`run_tests.sh`, `docker.sh`, `incus.sh`) |
| **Unit tests** (Rust) | `#[cfg(test)]` blocks in `src/` | Same scope as Go unit tests | `cargo test` |
| **Integration tests** (Rust) | `tests/` at crate root | Full binary/library integration | `cargo test --test '*'` |
| **Unit tests** (Node/TS) | `src/*.test.ts` alongside source | Pure logic, parsing, transforms, component logic | `vitest --coverage` |
| **Integration tests** (Node/TS) | `tests/` at repo root | Full server/CLI behavior, route responses, auth flows | Shell scripts or Vitest with `--pool=forks` |
| **Unit tests** (Python) | `tests/test_*.py` | Pure logic, validation, parsing, transforms | `pytest --cov` |
| **Integration tests** (Python) | `tests/integration/` | Full server/CLI behavior against a running service | `pytest tests/integration/` |

### What goes where

**Unit tests test logic — not infrastructure:**
- ✓ Function inputs/outputs, edge cases, error handling
- ✓ Validation and parsing logic
- ✓ Data transformations and business rules
- ✓ Handler logic using mock requests (`httptest.NewRecorder`) or stubs
- ✗ Full HTTP requests against a running server
- ✗ A remote or shared database (libSQL/Turso, any server the test does not start itself)
- ✓ A local SQLite database the test creates itself (in-memory or in `t.TempDir()`) is a unit test and counts toward coverage
- ✗ External service calls
- ✗ Auth flows that require session state

**Integration tests test behavior — not logic:**
- ✓ Every route returns the correct status, headers, and body
- ✓ Auth flows (login, logout, 2FA, tokens)
- ✓ Content negotiation (browser → HTML, curl → text, API client → JSON)
- ✓ Rate limiting and lockout behavior
- ✓ CLI ↔ server interaction
- ✓ Docker / Incus startup and smoke-test

---

## Go Test Structure

### File naming

| File | What it covers |
|------|---------------|
| `config_test.go` | Config loading, validation, defaults |
| `server_test.go` | Route registration, middleware chain |
| `auth_handler_test.go` | Auth handler logic |
| `{feature}_test.go` | Feature-specific logic |

### Table-driven tests — always preferred

```go
func TestValidate(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        wantErr bool
    }{
        {name: "empty", input: "", wantErr: true},
        {name: "too long", input: strings.Repeat("x", 101), wantErr: true},
        {name: "valid", input: "hello", wantErr: false},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := Validate(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("Validate(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
            }
        })
    }
}
```

Rules:
- Always use `t.Run(tt.name, ...)` for sub-tests — enables `go test -run TestValidate/empty`
- Name cases clearly: `"empty"`, `"too long"`, `"valid"` — not `"case1"`, `"case2"`
- Include both happy paths and all error paths in the table

### Running Go tests

```bash
# runs inside Docker; enforces coverage threshold
make test
```

Never run `go test` directly on host — always via `make test` (Docker internally).

---

## Rust Test Structure

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_empty() {
        assert!(validate("").is_err());
    }

    #[test]
    fn test_validate_valid() {
        assert!(validate("hello").is_ok());
    }
}
```

Running Rust tests — always inside Docker:
```bash
# cargo fmt --check → cargo clippy -- -D warnings → cargo test --lib --no-fail-fast
make test
```

---

## Node/TypeScript Test Structure

Use **Vitest** for new projects — faster, native ESM, TypeScript-first. Jest is acceptable for existing projects.

### Parameterized tests — preferred over repeated `it()` blocks

```typescript
// src/utils.test.ts — unit test alongside source
import { describe, it, expect } from "vitest";
import { parseVersion } from "./utils.js";

describe("parseVersion", () => {
  it.each([
    ["1.0.0", { major: 1, minor: 0, patch: 0 }],
    ["0.1.0", { major: 0, minor: 1, patch: 0 }],
    ["2.3.4", { major: 2, minor: 3, patch: 4 }],
  ])("parses %s", (input, expected) => {
    expect(parseVersion(input)).toEqual(expected);
  });

  it("throws on invalid input", () => {
    expect(() => parseVersion("not-semver")).toThrow();
  });
});
```

### vitest.config.ts — coverage thresholds

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      thresholds: { lines: 60, functions: 60, branches: 60 },
    },
  },
});
```

Rules:
- Unit tests live alongside source (`src/utils.test.ts`) — not in a separate tree
- Use `it.each` for table-driven cases; name cases clearly
- Integration tests in `tests/` — full server or CLI behavior
- Always `make test` (Docker internally) — never `npx vitest` directly on host

---

## Python Test Structure

Use **pytest** for all tests.

### Parametrized tests — always preferred

```python
# tests/test_utils.py
import pytest
from {package_name}.utils import parse_version

@pytest.mark.parametrize("version,expected", [
    ("1.0.0", (1, 0, 0)),
    ("0.1.0", (0, 1, 0)),
    ("2.3.4", (2, 3, 4)),
])
def test_parse_version(version: str, expected: tuple[int, int, int]) -> None:
    assert parse_version(version) == expected

def test_parse_version_invalid() -> None:
    with pytest.raises(ValueError):
        parse_version("not-semver")
```

### conftest.py — shared fixtures

```python
# tests/conftest.py
import pytest
from pathlib import Path

@pytest.fixture
def tmp_config(tmp_path: Path) -> Path:
    cfg = tmp_path / "config.toml"
    cfg.write_text('[server]\nport = 8080\n')
    return cfg
```

Rules:
- Tests in `tests/test_*.py` — one file per module
- Shared fixtures in `tests/conftest.py` — never copy fixtures between test files
- Use `tmp_path` (pytest built-in) for temp files; never hardcode `/tmp`
- Integration tests in `tests/integration/` when they require a running service
- Always `make test` (Docker internally) — never `pytest` directly on host

Coverage thresholds in `pyproject.toml`:
```toml
[tool.pytest.ini_options]
addopts = "--cov=src --cov-report=term-missing --cov-fail-under=60"
```

---

## Mock Strategy

| Dependency | How to mock |
|------------|------------|
| External HTTP service | `httptest.NewServer` (Go) / `mockito` equivalent |
| Database | Interface-based mock; never an in-memory substitute for integration tests |
| File system | `os.TempDir()` / test temp directories; clean up with `t.Cleanup` |
| Time | Inject a `clock` interface; never call `time.Now()` directly in logic under test |
| Configuration | Construct the config struct directly in the test; don't read files |

**Prefer interfaces over mocking frameworks.** Define a small interface for any dependency that needs mocking; implement it with both the real and mock versions. Mocking frameworks that generate code from interfaces are acceptable but not required.

---

## Coverage Gates

| Project type | Minimum coverage | Source |
|-------------|-----------------|--------|
| Go projects | 60% (override in `IDEA.md` under `## Business logic`) | CI gate |
| Rust projects | 60% (override in `IDEA.md`) | `cargo tarpaulin` or `cargo llvm-cov` |
| Node/TypeScript projects | 60% lines/functions/branches (override in `IDEA.md`) | `vitest --coverage` (v8 provider) |
| Python projects | 60% (override in `IDEA.md`) | `pytest --cov` + `--cov-fail-under` in `pyproject.toml` |

The threshold is defined in `{project_dir}/IDEA.md`. CI fails when coverage drops below it — a passing build with uncovered code is a silent regression. If no threshold is set in `IDEA.md`, default is 60%.

Coverage is measured on unit tests only (`*_test.go` / `#[cfg(test)]`). Integration test coverage is tracked separately by verifying that every route and endpoint has at least one integration test.

---

## Test Data

- **No test data at repo root** — use `os.TempDir()` / `t.TempDir()` (auto-cleaned by Go)
- **Fixtures**: small static files go in `tests/testdata/` — never in `src/`
- **Generated data**: create in temp dirs; never commit generated test artifacts
- **Database state**: create fresh schema per test run; never share state between tests
- **Secrets in tests**: use obviously fake values (`test-api-key-xxxxx`, not real-looking strings)

---

## AI Rules

- **Never defer tests** — write the test file in the same commit as the implementation
- **Never skip tests to "ship faster"** — a feature without tests is incomplete
- **Never write tests that only test the mock** — if every assertion would pass with any implementation, the test is worthless
- **Never commit with `t.Skip()`** left in without a comment explaining why and a linked issue
- **Test every error path** — not just the happy path; coverage gates enforce this
