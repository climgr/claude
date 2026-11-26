---
name: Swift conventions
description: Build system, project layout, Swift Package Manager targets, and code rules for CasjaysDev Swift projects
type: user
---

## Project Layout

```
{project_name}/
├── Sources/
│   └── {ProjectName}/
│       └── main.swift
├── Tests/
│   └── {ProjectName}Tests/
│       └── MainTests.swift
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── Package.swift
├── Package.resolved              # always committed
├── Makefile
├── release.txt                   # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `Sources/{ProjectName}/` per Swift Package Manager's mandatory layout — never a flattened top-level `*.swift` sprawl.

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

SWIFT_CACHE ?= $(HOME)/.cache/swiftpm-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

SWIFT_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(SWIFT_CACHE):/root/.cache/org.swift.swiftpm \
	-w /build \
	swift:slim
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `swift build -c release` inside Docker |
| `test` | `swift test` inside Docker |
| `lint` | `swiftlint` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | `swift package clean` — removes `.build/` |

## Docker Build Pattern

```makefile
SWIFT_CACHE ?= $(HOME)/.cache/swiftpm-docker

SWIFT_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(SWIFT_CACHE):/root/.cache/org.swift.swiftpm \
	-w /build \
	swift:slim
```

- Official `swift:slim` image for the toolchain build stage; `swiftlint` must be installed into the same image via a `Dockerfile.build` layer (`apt-get install -y swiftlint` on `swift:slim`'s Ubuntu base) since it's not bundled — this is the one narrow case where a `Dockerfile.build` `FROM swift:slim` is warranted for a non-Go/Rust/Android language
- `SWIFT_CACHE` uses `?=` so host env vars are honored; mounting SwiftPM's cache dir persists resolved packages across runs
- Every target using `SWIFT_DOCKER` must `@mkdir -p $(SWIFT_CACHE)` first
- Never run `swift`/`swiftlint` directly on host — always via `make`

## Target Patterns

```makefile
build:
	@mkdir -p $(SWIFT_CACHE)
	$(SWIFT_DOCKER) swift build -c release

test:
	@mkdir -p $(SWIFT_CACHE)
	$(SWIFT_DOCKER) swift test

lint:
	@mkdir -p $(SWIFT_CACHE)
	$(SWIFT_DOCKER) swiftlint
```

## Package.swift Structure

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "{project_name}",
    targets: [
        .executableTarget(name: "{ProjectName}"),
        .testTarget(name: "{ProjectName}Tests", dependencies: ["{ProjectName}"]),
    ]
)
```

## Isolation

- **Never resolve packages into a shared host SwiftPM cache** for project builds — the Docker-mounted `SWIFT_CACHE` is project-scoped via `-v`
- `Package.resolved` is always committed — reproducible dependency resolution
- Never run `swift package update` inside a project's CI build step (only locally, deliberately, then commit the resulting `Package.resolved`)

## Optionality and Correctness

- **No force-unwrap (`!`)** without a comment on the line above stating why the value is guaranteed non-nil — prefer `if let`, `guard let`, or `??`
- **`struct` over `class`** for value types — reach for `class` only when reference semantics or inheritance is the actual requirement
- **`enum` with associated values** for state/result modeling instead of a class hierarchy
- **Structured concurrency** (`async`/`await`, `Task`) for async work — never `DispatchSemaphore`-based blocking unless bridging legacy callback APIs requires it

```swift
func parseVersion(_ raw: String?) -> (Int, Int, Int)? {
    guard let raw else { return nil }
    let parts = raw.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return (parts[0], parts[1], parts[2])
}
```

## Linting and Formatting

- **SwiftLint** for style/lint enforcement — zero violations in CI
- **`swift-format`** (or SwiftLint's `--fix`) for auto-formatting
- Project-specific rule overrides live in `.swiftlint.yml`, never inline `// swiftlint:disable` without a comment stating why on the line above

## Testing

Use **Swift Testing** (or `XCTest` for targets that must run on older toolchains).

```swift
import Testing
@testable import {ProjectName}

@Test func parseVersionReturnsNilForMalformedInput() {
    #expect(parseVersion("not-a-version") == nil)
}
```

- Test files in `Tests/{ProjectName}Tests/`, one file per source file under test
- Coverage via `swift test --enable-code-coverage`

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `swift-argument-parser` for CLI argument parsing — never hand-roll `CommandLine.arguments` parsing.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```swift
func resolveColor(_ flag: String) -> Bool {
    if flag == "yes" { return true }
    if flag == "no" { return false }
    return ProcessInfo.processInfo.environment["NO_COLOR"] == nil && isatty(1) != 0
}
```

## Build Info Variables

```swift
enum BuildInfo {
    static let version = ProcessInfo.processInfo.environment["BUILD_VERSION"] ?? "devel"
    static let commitID = ProcessInfo.processInfo.environment["BUILD_COMMIT"] ?? "N/A"
    static let buildDate = ProcessInfo.processInfo.environment["BUILD_DATE"] ?? "N/A"
}
```

Pass via `--build-arg` in Docker or `-e` at container run time.

## Directory Naming

**Plural** for all non-SwiftPM-mandated directories (`handlers/`, `models/`, `routes/`, `scripts/`). `Sources/`/`Tests/` are SwiftPM's own fixed convention names and stay as-is.

## Code Rules

- **No `as!` force-cast** without a comment stating why the cast is guaranteed to succeed — prefer `as?` with explicit handling
- **No `print()` in library code** — use `os.Logger` (or the project's chosen logging facade); `print` only in CLI entry points
- **`Sendable` conformance** on types crossing concurrency-domain boundaries — do not silently disable strict concurrency checking
- **No retain cycles** — `[weak self]`/`[unowned self]` in closures held by a longer-lived object
- **No external cron** — in-process scheduling only (`Task.sleep` loop for simple periodic tasks, `DispatchSourceTimer` for multiple jobs)
