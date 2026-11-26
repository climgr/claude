---
name: C/C++ conventions
description: Build system, project layout, CMake targets, and code rules for CasjaysDev C and C++ projects
type: user
---

## Project Layout

```
{project_name}/
├── src/
│   └── main.c(pp)
├── include/
│   └── {project_name}/
│       └── {project_name}.h(pp)
├── tests/
│   └── main_test.c(pp)
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── CMakeLists.txt
├── conanfile.txt              # or vcpkg.json — only if external deps are needed
├── Makefile
├── release.txt                # current version string (e.g. 0.1.0)
└── AI.md
```

Public headers under `include/{project_name}/`; implementation under `src/`. A header-only library skips `src/` and puts everything under `include/`.

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

CCACHE_DIR ?= $(HOME)/.cache/ccache-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

CPP_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(CCACHE_DIR):/root/.ccache \
	-e CCACHE_DIR=/root/.ccache \
	-w /build \
	gcc:latest
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build` inside Docker |
| `test` | `ctest --test-dir build --output-on-failure` inside Docker |
| `lint` | `clang-tidy` + `cppcheck` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | Removes `build/` |

## Docker Build Pattern

```makefile
CCACHE_DIR ?= $(HOME)/.cache/ccache-docker

CPP_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(CCACHE_DIR):/root/.ccache \
	-e CCACHE_DIR=/root/.ccache \
	-w /build \
	gcc:latest
```

- Official `gcc:latest` image (Debian-based, includes `cmake`/`make`/`g++`); a `Dockerfile.build` layer adding `clang-tidy cppcheck` via `apt-get install` is warranted here since `gcc:latest` doesn't bundle them
- `CCACHE_DIR` uses `?=` so host env vars are honored; mounting `~/.ccache` persists compiled-object cache across runs and meaningfully speeds up rebuild-heavy C/C++ CI
- Every target using `CPP_DOCKER` must `@mkdir -p $(CCACHE_DIR)` first
- Never run `cmake`/`gcc`/`g++`/`clang` directly on host — always via `make`
- Static linking preferred for release binaries (`-static` or musl-based image) to match the single-self-contained-binary default

## Target Patterns

```makefile
build:
	@mkdir -p $(CCACHE_DIR)
	$(CPP_DOCKER) sh -c 'cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j$(nproc)'

test:
	@mkdir -p $(CCACHE_DIR)
	$(CPP_DOCKER) sh -c 'cmake -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build -j$(nproc) && ctest --test-dir build --output-on-failure'

lint:
	@mkdir -p $(CCACHE_DIR)
	$(CPP_DOCKER) sh -c 'clang-tidy src/*.c* -- -Iinclude && cppcheck --error-exitcode=1 --enable=warning,style src/'
```

## CMakeLists.txt Structure

```cmake
cmake_minimum_required(VERSION 3.20)
project({project_name} VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 17)

add_executable({project_name} src/main.cpp)
target_include_directories({project_name} PRIVATE include)

enable_testing()
add_subdirectory(tests)
```

## Isolation

- **Never install dependencies into the host toolchain** — Conan/vcpkg caches are Docker-mounted and project-scoped, never a shared global package cache
- `conanfile.txt`/`vcpkg.json` + their lockfiles (`conan.lock`/`vcpkg-lock.json`) are always committed when used
- Never link against host system libraries at build time inside the container beyond the base image's own toolchain — external deps go through Conan/vcpkg, not `apt-get install lib*-dev` baked ad hoc into a build step

## Memory Safety and Correctness

- **RAII everywhere in C++** — no raw `new`/`delete`; use `std::unique_ptr`/`std::shared_ptr` or stack allocation
- **No raw owning pointers** — a raw pointer parameter/return means "non-owning, may be null-checked by caller," never a transfer of ownership
- **Bounds-checked access** (`.at()` over `operator[]`) in any code path handling untrusted input sizes
- **C: no `gets()`/`strcpy()`/`sprintf()`** — always the bounded variants (`fgets()`, `strncpy()`/`strlcpy()`, `snprintf()`)
- **AddressSanitizer/UBSan** (`-fsanitize=address,undefined`) enabled in the `test` build configuration — memory bugs must surface in CI, not production

```cpp
std::optional<std::array<int, 3>> parseVersion(std::string_view raw) {
    std::array<int, 3> parts{};
    size_t start = 0;
    for (int i = 0; i < 3; ++i) {
        auto dot = raw.find('.', start);
        auto token = raw.substr(start, dot - start);
        auto [ptr, ec] = std::from_chars(token.data(), token.data() + token.size(), parts[i]);
        if (ec != std::errc{}) return std::nullopt;
        if (i < 2 && dot == std::string_view::npos) return std::nullopt;
        start = dot + 1;
    }
    return parts;
}
```

## Linting and Formatting

- **`clang-tidy`** for static analysis (modernize/bugprone/performance checks enabled)
- **`cppcheck`** for additional static analysis coverage clang-tidy misses
- **`clang-format`** for auto-formatting; CI runs `clang-format --dry-run --Werror`
- Project-specific rule overrides live in `.clang-tidy`/`.clang-format`, never inline `// NOLINT` without a comment stating why

## Testing

Use **CTest** as the runner, with **GoogleTest** or **Catch2** as the assertion framework.

```cpp
#include <gtest/gtest.h>
#include "{project_name}/{project_name}.hpp"

TEST(ParseVersion, ReturnsNulloptForMalformedInput) {
    EXPECT_EQ(parseVersion("not-a-version"), std::nullopt);
}
```

- Test files in `tests/`, registered in `tests/CMakeLists.txt` via `add_test()`
- Build the `test` configuration with sanitizers enabled; the `build`/release configuration never ships sanitizer instrumentation

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `getopt_long` (C) or `CLI11`/`cxxopts` (C++) for CLI argument parsing — never hand-roll `argv` scanning beyond that.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```cpp
bool resolveColor(std::string_view flag) {
    if (flag == "yes") return true;
    if (flag == "no") return false;
    return std::getenv("NO_COLOR") == nullptr && isatty(fileno(stdout));
}
```

## Build Info Variables

```cpp
namespace BuildInfo {
    constexpr const char* Version   = BUILD_VERSION_STR;
    constexpr const char* CommitId  = BUILD_COMMIT_STR;
    constexpr const char* BuildDate = BUILD_DATE_STR;
}
```

Injected via `target_compile_definitions({project_name} PRIVATE BUILD_VERSION_STR="...")` in `CMakeLists.txt`, populated from `-D` flags passed at `cmake` configure time — never read from the environment at runtime for values that should be baked into a release artifact.

## Directory Naming

**Plural** for all directories (`handlers/`, `models/`, `routes/`, `tests/`, `scripts/`).

## Code Rules

- **No `using namespace std;` in headers** — pollutes every translation unit that includes the header
- **No C-style casts** — use `static_cast`/`dynamic_cast`/`reinterpret_cast` explicitly so intent is visible and greppable
- **`const`-correctness** on every parameter/method that doesn't mutate
- **No undefined behavior left unchecked** — signed integer overflow, out-of-bounds access, use-after-free are hard defects, not "usually fine"
- **No external cron** — in-process scheduling only (a timer/event-loop primitive, or a proper scheduler library for multiple jobs)
