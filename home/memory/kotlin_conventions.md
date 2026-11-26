---
name: Kotlin conventions
description: Build system, project layout, Gradle targets, and code rules for CasjaysDev Kotlin projects (non-Android; Android-specific layout stays in the claudemgr/android template repo)
type: user
---

## Project Layout

```
{project_name}/
├── src/
│   ├── main/
│   │   └── kotlin/{org}/{project_name}/
│   │       └── Main.kt
│   └── test/
│       └── kotlin/{org}/{project_name}/
│           └── MainTest.kt
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── scripts/
├── build.gradle.kts        # Kotlin DSL, preferred over build.gradle (Groovy)
├── settings.gradle.kts
├── gradle.properties
├── gradlew / gradlew.bat / gradle/wrapper/
├── Makefile
├── release.txt             # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `src/main/kotlin/{package}/` — package path mirrors reverse-domain org (e.g. `pro.casjaysdev.{project_name}`).

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

GRADLE_CACHE ?= $(HOME)/.cache/gradle-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

KOTLIN_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(GRADLE_CACHE):/root/.gradle \
	-w /build \
	gradle:jdk-alpine
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `./gradlew build` inside Docker (compile + assemble jar) |
| `test` | `./gradlew test` inside Docker (JVM unit tests) |
| `lint` | `./gradlew ktlintCheck detekt` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | `./gradlew clean` — removes `build/` |

## Docker Build Pattern

```makefile
GRADLE_CACHE ?= $(HOME)/.cache/gradle-docker

KOTLIN_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(GRADLE_CACHE):/root/.gradle \
	-w /build \
	gradle:jdk-alpine
```

- `gradle:jdk-alpine` official image for non-Android Kotlin/JVM builds; Android projects use `casjaysdev/android:latest` instead (never this file's image)
- `GRADLE_CACHE` uses `?=` so host env vars are honored; mounting `~/.gradle` persists the dependency cache across runs
- Every target using `KOTLIN_DOCKER` must `@mkdir -p $(GRADLE_CACHE)` first
- Never run `gradle`/`kotlinc` directly on host — always via `make`, and always `./gradlew` (wrapper) inside the container, never a bare `gradle` binary, for reproducible builds

## Target Patterns

```makefile
build:
	@mkdir -p $(GRADLE_CACHE)
	$(KOTLIN_DOCKER) ./gradlew build --no-daemon

test:
	@mkdir -p $(GRADLE_CACHE)
	$(KOTLIN_DOCKER) ./gradlew test --no-daemon

lint:
	@mkdir -p $(GRADLE_CACHE)
	$(KOTLIN_DOCKER) ./gradlew ktlintCheck detekt --no-daemon
```

`--no-daemon` is required in Docker — a lingering Gradle daemon outlives the container's `--rm` cleanup on the host bind mount otherwise.

## build.gradle.kts Structure

```kotlin
plugins {
    kotlin("jvm") version "2.0.20"
    application
    id("org.jlleitschuh.gradle.ktlint") version "12.1.1"
    id("io.gitlab.arturbosch.detekt") version "1.23.6"
}

group = "pro.casjaysdev"
version = System.getenv("BUILD_VERSION") ?: "0.1.0"

repositories { mavenCentral() }

dependencies {
    testImplementation(kotlin("test"))
}

application {
    mainClass.set("pro.casjaysdev.{project_name}.MainKt")
}

tasks.test {
    useJUnitPlatform()
}

kotlin {
    jvmToolchain(21)
}
```

## Isolation

- **Never install Gradle/JDK dependencies into a shared host `~/.m2`/`~/.gradle`** for project builds — the Docker-mounted `GRADLE_CACHE` is project-scoped via `-v`
- `gradle/wrapper/gradle-wrapper.jar` + `gradle-wrapper.properties` are always committed — reproducible builds pin the exact Gradle version
- CI and Docker always build with `--no-daemon`

## Null Safety and Correctness

- **No `!!` (not-null assertion)** without a comment on the line above stating why the value is guaranteed non-null — prefer `?.let {}`, `requireNotNull()`, or a proper null check
- **`val` over `var`** — immutability by default; `var` only when reassignment is the actual intent
- Data classes for plain data holders — never a class with only fields and no behavior
- Sealed classes/interfaces for closed hierarchies (state machines, result types) instead of open inheritance
- Coroutines (`kotlinx.coroutines`) for async work — never raw `Thread` unless interfacing with blocking Java code that requires it
- **Structured concurrency**: never `GlobalScope.launch` — every coroutine is scoped to an explicit `CoroutineScope` tied to the lifecycle of the component/resource that owns it, and cancelled with it
- **Visibility**: `private`/`internal` by default; a member is `public` only when it is genuinely part of the module's external API
- **Scope functions**: `let`/`run`/`with`/`apply`/`also` used for their idiomatic purpose (null-check unwrap, object configuration, side effects) — never chained more than two deep, and never used to smuggle multi-statement logic into what reads like a one-liner
- **Naming**: standard Kotlin conventions — `UpperCamelCase` types, `lowerCamelCase` members/functions, `SCREAMING_SNAKE_CASE` top-level/companion `const val`s; no Hungarian notation, no `m`/`s` prefixes

```kotlin
fun parseVersion(raw: String?): Triple<Int, Int, Int>? {
    val value = raw ?: return null
    val parts = value.split(".").mapNotNull { it.toIntOrNull() }
    return if (parts.size == 3) Triple(parts[0], parts[1], parts[2]) else null
}
```

## Linting and Formatting

- **`ktlint`** for formatting/style (via the `ktlintCheck`/`ktlintFormat` Gradle tasks)
- **`detekt`** for static analysis (complexity, code smells)
- CI runs `./gradlew ktlintCheck detekt` — zero warnings allowed
- `./gradlew ktlintFormat` for auto-fixable style issues; never commit lint warnings

## Testing

Use **kotlin.test** + **JUnit 5** (`useJUnitPlatform()`).

```kotlin
import kotlin.test.Test
import kotlin.test.assertEquals

class MainTest {
    @Test
    fun `parseVersion returns null for malformed input`() {
        assertEquals(null, parseVersion("not-a-version"))
    }
}
```

- Unit tests in `src/test/kotlin/{package}/` mirroring `src/main/kotlin/{package}/`
- `MockK` for mocking (never Mockito's Kotlin-unfriendly API)
- Coverage via `kover` Gradle plugin when a threshold is required

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `clikt` for CLI argument parsing — never hand-roll.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception (see python_conventions.md's identical rule).

## NO_COLOR Support

```kotlin
fun resolveColor(flag: String): Boolean = when (flag) {
    "yes" -> true
    "no" -> false
    else -> System.getenv("NO_COLOR") == null && System.console() != null
}
```

## Build Info Variables

```kotlin
object BuildInfo {
    val VERSION: String = System.getenv("BUILD_VERSION") ?: "devel"
    val COMMIT_ID: String = System.getenv("BUILD_COMMIT") ?: "N/A"
    val BUILD_DATE: String = System.getenv("BUILD_DATE") ?: "N/A"
}
```

Pass via `--build-arg` in Docker or `-e` at container run time.

## Directory Naming

**Plural** for all non-package directories (`handlers/`, `models/`, `routes/`, `scripts/`, `tests/`). Package directories follow the reverse-domain convention and are singular per Java/Kotlin package-naming norms.

## Code Rules

- **No `lateinit var`** without a comment stating the initialization guarantee — prefer constructor injection or a nullable + lazy pattern
- **No `Thread.sleep()` in coroutine code** — use `delay()` instead, it doesn't block the underlying thread
- **Extension functions** over utility classes with static-style methods
- **`when` must be exhaustive** on sealed types — no `else -> {}` catch-all that silently swallows a future case
- **No external cron** — in-process scheduling only (`kotlinx-coroutines` delay loop, or a proper scheduler library for multiple jobs)
