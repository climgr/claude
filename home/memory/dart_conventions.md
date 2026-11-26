---
name: Dart/Flutter conventions
description: Build system, project layout, pub/flutter targets, and code rules for CasjaysDev Dart and Flutter projects
type: user
---

## Project Layout

```
{project_name}/
├── lib/
│   ├── main.dart                 # Flutter app entrypoint, or CLI entrypoint
│   └── src/
│       └── {project_name}_base.dart
├── test/
│   └── {project_name}_test.dart
├── bin/
│   └── {project_name}.dart       # pure-Dart CLI entrypoint (non-Flutter)
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── pubspec.yaml
├── pubspec.lock                  # always committed
├── analysis_options.yaml
├── Makefile
├── release.txt                   # current version string (e.g. 0.1.0)
└── AI.md
```

Library code under `lib/src/`, with `lib/{project_name}.dart` as the single public-export barrel file — never expose `lib/src/**` paths directly to consumers.

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

PUB_CACHE ?= $(HOME)/.cache/pub-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

DART_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(PUB_CACHE):/root/.pub-cache \
	-w /build \
	dart:stable
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `dart pub get && dart compile exe bin/{project_name}.dart` (pure Dart) or `flutter build` (Flutter app) inside Docker |
| `test` | `dart test` (pure Dart) or `flutter test` (Flutter) inside Docker |
| `lint` | `dart analyze` (or `flutter analyze`) inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | Removes `.dart_tool/`, `build/` |

## Docker Build Pattern

```makefile
PUB_CACHE ?= $(HOME)/.cache/pub-docker

DART_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(PUB_CACHE):/root/.pub-cache \
	-w /build \
	dart:stable
```

- Official `dart:stable` image for pure-Dart projects; Flutter apps use `ghcr.io/cirruslabs/flutter:stable` (the community-maintained official-equivalent Flutter CI image) instead, since there is no `dart:stable`-equivalent official Flutter image
- `PUB_CACHE` uses `?=` so host env vars are honored; mounting `~/.pub-cache` persists resolved packages across runs
- Every target using `DART_DOCKER` must `@mkdir -p $(PUB_CACHE)` first
- Never run `dart`/`flutter`/`pub` directly on host — always via `make`

## Target Patterns

```makefile
build:
	@mkdir -p $(PUB_CACHE)
	$(DART_DOCKER) sh -c 'dart pub get && dart compile exe bin/$(PROJECTNAME).dart -o build/$(PROJECTNAME)'

test:
	@mkdir -p $(PUB_CACHE)
	$(DART_DOCKER) sh -c 'dart pub get && dart test'

lint:
	@mkdir -p $(PUB_CACHE)
	$(DART_DOCKER) sh -c 'dart pub get && dart analyze'
```

Flutter projects substitute `flutter pub get`/`flutter build <platform>`/`flutter test`/`flutter analyze` for the `dart` equivalents above, using the Flutter Docker image in place of `dart:stable`.

## pubspec.yaml Structure

```yaml
name: {project_name}
description: One-sentence package description.
version: 0.1.0
environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  args: ^2.5.0

dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0
```

## Isolation

- **Never resolve packages into a shared host `~/.pub-cache`** for project builds — the Docker-mounted `PUB_CACHE` is project-scoped via `-v`
- `pubspec.lock` is always committed for applications (Flutter apps, CLI tools); libraries may omit it per `pub` convention, but this project set always commits it for reproducibility
- Never `dart pub global activate` inside a project's CI build step

## Null Safety and Correctness

- **Sound null safety is mandatory** — no `// @dart=2.9` opt-outs, no legacy non-null-safe code
- **No `!` non-null assertion** without a comment on the line above stating why the value is guaranteed non-null — prefer `?.`, `??`, or an explicit null check
- **`final`/`const` over mutable fields** wherever the value doesn't need reassignment
- **Sealed classes** (Dart 3+) for closed result/state hierarchies instead of a manual `is`-chain

```dart
List<int>? parseVersion(String? raw) {
  if (raw == null) return null;
  final parts = raw.split('.').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((p) => p == null)) return null;
  return parts.cast<int>();
}
```

## Linting and Formatting

- **`dart analyze`** (or `flutter analyze`) with the `lints`/`flutter_lints` package enabled in `analysis_options.yaml` — zero issues allowed
- **`dart format`** for auto-formatting; CI runs `dart format --output=none --set-exit-if-changed .`
- Project-specific rule overrides live in `analysis_options.yaml`, never inline `// ignore:` without a comment stating why on the line above

## Testing

Use **`package:test`** (pure Dart) or **`flutter_test`** (Flutter widgets).

```dart
import 'package:test/test.dart';
import 'package:{project_name}/{project_name}.dart';

void main() {
  test('parseVersion returns null for malformed input', () {
    expect(parseVersion('not-a-version'), isNull);
  });
}
```

- Test files in `test/`, mirroring `lib/` structure, one `*_test.dart` per source file
- Flutter widget tests use `testWidgets()` + `WidgetTester`
- Coverage via `dart test --coverage` / `flutter test --coverage`

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `package:args` for CLI argument parsing — never hand-roll.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```dart
bool resolveColor(String flag) {
  if (flag == 'yes') return true;
  if (flag == 'no') return false;
  return Platform.environment['NO_COLOR'] == null && stdout.hasTerminal;
}
```

## Build Info Variables

```dart
class BuildInfo {
  static const version = String.fromEnvironment('BUILD_VERSION', defaultValue: 'devel');
  static const commitId = String.fromEnvironment('BUILD_COMMIT', defaultValue: 'N/A');
  static const buildDate = String.fromEnvironment('BUILD_DATE', defaultValue: 'N/A');
}
```

Pass via `--dart-define=BUILD_VERSION=... ` at compile time (`dart compile`/`flutter build`), never read from `Platform.environment` at runtime for values that should be baked into a release artifact.

## Directory Naming

**Plural** for all non-SDK-mandated directories (`handlers/`, `models/`, `routes/`, `scripts/`). `lib/`, `bin/`, `test/` are Dart's own fixed convention names and stay as-is.

## Code Rules

- **No `dynamic`** unless interfacing with genuinely dynamic data (JSON decode boundary) — type everything else explicitly
- **`const` constructors** on Flutter widgets wherever possible — avoids unnecessary rebuilds
- **No `setState()` calls buried in async callbacks without a `mounted` check** — a disposed widget calling `setState` throws
- **No business logic in widget `build()` methods** — extract to a model/provider/bloc layer
- **No external cron** — in-process scheduling only (`Timer.periodic` for simple periodic tasks, `workmanager` for background Flutter tasks requiring OS scheduling)
