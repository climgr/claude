---
name: Python conventions
description: Build system, project layout, Makefile targets, and code rules for CasjaysDev Python projects
type: user
---

## Project Layout

```
{project_name}/
├── src/
│   └── {package_name}/     # Python package (underscored name, e.g. my_tool)
│       ├── __init__.py
│       └── main.py
├── tests/                  # pytest test files
│   ├── conftest.py
│   └── test_*.py
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── scripts/
├── pyproject.toml          # project metadata, deps, and tool config
├── uv.lock                 # always committed when using uv
├── Makefile
├── release.txt             # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `src/{package_name}/` — never at repo root. Package name uses underscores (Python convention); project/PyPI name uses hyphens.

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

VERSION    ?= $(shell cat release.txt 2>/dev/null || echo "devel")
BUILD_DATE := $(shell date +"%a %b %d, %Y at %H:%M:%S %Z")
COMMIT_ID  := $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo "N/A")
PLATFORMS  ?= linux/amd64,linux/arm64

PIP_CACHE ?= $(HOME)/.cache/pip
UV_CACHE  ?= $(HOME)/.cache/uv

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

PY_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(PIP_CACHE):/root/.cache/pip \
	-v $(UV_CACHE):/root/.cache/uv \
	-w /build \
	python:alpine
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | Builds wheel + sdist via `python -m build` inside Docker |
| `test` | Runs ruff check, mypy, then pytest inside Docker |
| `dev` | Installs project in editable mode into a local venv for development |
| `lint` | Runs `ruff check` + `ruff format --check` only |
| `docker` | Builds multi-arch image locally via `docker buildx` (no push) |
| `clean` | Removes `dist/`, `__pycache__/`, `.mypy_cache/`, `.ruff_cache/`, `*.egg-info/` |

## Docker Build Pattern

```makefile
PIP_CACHE ?= $(HOME)/.cache/pip
UV_CACHE  ?= $(HOME)/.cache/uv

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

PY_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(PIP_CACHE):/root/.cache/pip \
	-v $(UV_CACHE):/root/.cache/uv \
	-w /build \
	python:alpine
```

- Always `python:alpine` rolling tag — never pinned for dev tooling
- `PIP_CACHE` and `UV_CACHE` use `?=` so host env vars (e.g. custom XDG paths) are honored; defaults are `~/.cache/pip` and `~/.cache/uv`
- Every target that uses `PY_DOCKER` must `@mkdir -p $(PIP_CACHE) $(UV_CACHE)` first so host dirs exist before Docker mounts them and downloaded packages persist across runs
- Dependencies installed inside Docker: `pip install -e .[dev]` or `uv sync --frozen`
- Never run `python`, `pip`, `uv`, `ruff`, or `mypy` directly on host for project builds — always via `make`

## Target Patterns

Every target that invokes `PY_DOCKER` must create the cache dirs as its first step:

```makefile
build:
	@mkdir -p $(PIP_CACHE) $(UV_CACHE)
	$(PY_DOCKER) sh -c 'pip install --quiet -e .[dev] && python -m build'

test:
	@mkdir -p $(PIP_CACHE) $(UV_CACHE)
	$(PY_DOCKER) sh -c 'pip install --quiet -e .[dev] && ruff check . && ruff format --check . && mypy src && pytest'

dev:
	@mkdir -p $(PIP_CACHE) $(UV_CACHE)
	$(PY_DOCKER) sh -c 'pip install -e .[dev]'
	@echo "Project installed in editable mode inside Docker; run via make targets"
```

**Rule — any direct `docker run` with a Python image** must also include the cache mounts and the preceding mkdir.

## pyproject.toml Structure

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "{project_name}"
version = "0.1.0"
description = "..."
readme = "README.md"
license = { text = "MIT" }
requires-python = ">=3.11"
authors = [{ name = "{project_org}" }]
dependencies = []

[project.optional-dependencies]
dev = ["ruff", "mypy", "pytest", "pytest-cov"]

[project.scripts]
{project_name} = "{package_name}.main:main"

[tool.hatch.version]
source = "env"
variable = "BUILD_VERSION"
fallback-version = "0.1.0"

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "N", "W", "UP", "B", "C4", "SIM", "RUF"]
ignore = []

[tool.mypy]
strict = true
python_version = "3.11"
packages = ["{package_name}"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=src --cov-report=term-missing --cov-fail-under=60"
```

## Isolation

- **Always use `uv` or `python3 -m venv`** — never install project deps into the system Python
- `uv` is preferred: `uv sync`, `uv run`, `uv add`
- CI and Docker always install into a clean environment
- `uv.lock` (when using uv) is always committed — reproducible installs
- Never `pip install --user` in CI or Docker

## Type Hints

- **Required on all function signatures** — both arguments and return type
- `mypy --strict` (or `pyright`) runs in CI — type errors are build failures
- No bare `Any` without a comment on the line above stating the reason; `# type: ignore[...]` directive goes on the same line (tool requirement)
- Use `typing.Protocol` over ABC for structural subtyping
- `TypeAlias` and `TypeVar` for generic code; `ParamSpec` for decorator type safety

```python
from pathlib import Path

def read_config(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
```

## Linting and Formatting

- **`ruff`** for both linting and formatting — replaces flake8, isort, black in one tool
- CI runs `ruff check . && ruff format --check .` — zero warnings or format drift allowed
- `ruff check --fix` for auto-fixable issues; never commit lint warnings
- No `# noqa` without an explanatory comment on the line above stating why

## Testing

Use **pytest** for all tests.

```python
# tests/test_utils.py
import pytest
from {package_name}.utils import parse_version

@pytest.mark.parametrize("version,expected", [
    ("1.2.3", (1, 2, 3)),
    ("0.1.0", (0, 1, 0)),
])
def test_parse_version(version: str, expected: tuple[int, int, int]) -> None:
    assert parse_version(version) == expected
```

- Unit tests in `tests/` — one `test_*.py` per module
- Shared fixtures in `tests/conftest.py`
- Coverage via `pytest-cov`; thresholds set in `[tool.pytest.ini_options]`
- Test data in `tests/testdata/` (static) or `tmp_path` pytest fixture (generated)

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output — `auto`: TTY detect; `yes`: force on; `no`: force off |

- `--color auto` detects terminal capability (default); `yes` forces color on; `no` disables it and removes emojis from output.

All flags must support both `--flag value` and `--flag=value` — argparse, typer, and click all handle this natively.

Use `argparse` (stdlib) for simple tools, `typer` (type-hint-driven) for complex CLIs, `click` when typer is insufficient. Never hand-roll argument parsing.

### Toggle flags — `--enable`, `--disable`, `--yes`, `--no`

Never use compound hyphenated flags (`--enable-tls`, `--disable-cache`). The flag takes the feature name as a required argument: `--enable tls`, `--disable cache`. Same for `--yes` and `--no`.

**Exception:** `--color` is the standard three-value enum — `--color auto`, `--color yes`, `--color no`. There is no `--no-color` flag; `--color no` and the `NO_COLOR` env var both disable color.

```python
# argparse example
parser.add_argument("--enable",  metavar="FEATURE", help="Enable a named feature")
parser.add_argument("--disable", metavar="FEATURE", help="Disable a named feature")
parser.add_argument("--yes",     metavar="THING",   help="Confirm yes for a named operation")
parser.add_argument("--no",      metavar="THING",   help="Confirm no for a named operation")
```

## NO_COLOR Support

```python
import os
import sys

def resolve_color(flag: str) -> bool:
    if flag == "yes":
        return True
    if flag == "no":
        return False
    # "auto"
    if "NO_COLOR" in os.environ:
        return False
    return sys.stdout.isatty()
```

Honor `NO_COLOR` — any value set (including empty string) means no color.

## Build Info Variables

```python
# src/{package_name}/version.py
import os

VERSION = os.environ.get("BUILD_VERSION", "devel")
COMMIT_ID = os.environ.get("BUILD_COMMIT", "N/A")
BUILD_DATE = os.environ.get("BUILD_DATE", "N/A")
```

Pass via `--build-arg` in Docker or `--env` at container run time. For installed packages, use `importlib.metadata.version("{package_name}")` as the fallback.

## Directory Naming

**Plural** — all directories use plural names (`handlers/`, `models/`, `routes/`, `utils/`, `views/`). Tooling dirs are also plural (`scripts/`, `tests/`, `completions/`). Python package directories follow Python module naming (underscores, not hyphens) but are still plural when they represent a collection.

## Code Rules

- **`pathlib.Path` over `os.path`** — all filesystem operations use `Path`
- **No `import *`** — explicit imports only
- **No `eval()`, `exec()`, or `__import__()`** with untrusted input — arbitrary code execution
- **No mutable default arguments** — `def fn(items: list[str] = [])` is a bug; use `None` sentinel and initialize inside the body
- **No bare `except:`** — always `except SomeError:` or at minimum `except Exception:`; never swallow silently
- **`with` statements for all resources** — files, sockets, locks; never manual `try/finally` for cleanup
- **f-strings** over `%`-formatting and `.format()`
- **`logging` over `print`** — configure log level at the entry point; library code uses `logging.getLogger(__name__)`; never `print()` in library code
- **No `sys.exit()` in library code** — only in CLI entry points; library code raises exceptions
- **No external cron** — never depend on host cron or systemd timers for application-level scheduling. Use in-process scheduling only: `asyncio.sleep` loop for simple async periodic tasks; `time.sleep` loop for simple sync tasks; `APScheduler` for multiple jobs, cron-expression scheduling, or any non-trivial scheduling need.
