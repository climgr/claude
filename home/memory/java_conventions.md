---
name: Java conventions
description: Build system, project layout, Maven targets, and code rules for CasjaysDev Java projects (non-Android)
type: user
---

## Project Layout

```
{project_name}/
├── src/
│   ├── main/
│   │   └── java/{org}/{project_name}/
│   │       └── Main.java
│   └── test/
│       └── java/{org}/{project_name}/
│           └── MainTest.java
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── scripts/
├── pom.xml
├── Makefile
├── release.txt             # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `src/main/java/{package}/` — package path mirrors reverse-domain org (e.g. `pro.casjaysdev.{project_name}`). Maven's standard layout (`src/main`, `src/test`) is mandatory — never a flattened `src/` without the `main`/`test` split.

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

MAVEN_CACHE ?= $(HOME)/.cache/m2-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

JAVA_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(MAVEN_CACHE):/root/.m2 \
	-w /build \
	maven:alpine
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `mvn -q package` inside Docker |
| `test` | `mvn -q test` inside Docker |
| `lint` | `mvn -q checkstyle:check spotbugs:check` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | `mvn -q clean` — removes `target/` |

## Docker Build Pattern

```makefile
MAVEN_CACHE ?= $(HOME)/.cache/m2-docker

JAVA_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(MAVEN_CACHE):/root/.m2 \
	-w /build \
	maven:alpine
```

- Official `maven:alpine` image for the toolchain build stage
- `MAVEN_CACHE` uses `?=` so host env vars are honored; mounting `~/.m2` persists downloaded dependencies across runs
- Every target using `JAVA_DOCKER` must `@mkdir -p $(MAVEN_CACHE)` first
- Never run `mvn`/`javac` directly on host — always via `make`

## Target Patterns

```makefile
build:
	@mkdir -p $(MAVEN_CACHE)
	$(JAVA_DOCKER) mvn -q -B package -DskipTests

test:
	@mkdir -p $(MAVEN_CACHE)
	$(JAVA_DOCKER) mvn -q -B test

lint:
	@mkdir -p $(MAVEN_CACHE)
	$(JAVA_DOCKER) mvn -q -B checkstyle:check spotbugs:check
```

`-B` (batch mode) is required in Docker — Maven's interactive progress output otherwise floods CI logs.

## pom.xml Structure

```xml
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>pro.casjaysdev</groupId>
  <artifactId>{project_name}</artifactId>
  <version>${env.BUILD_VERSION}</version>
  <packaging>jar</packaging>

  <properties>
    <maven.compiler.release>21</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>5.11.0</version>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-checkstyle-plugin</artifactId>
      </plugin>
      <plugin>
        <groupId>com.github.spotbugs</groupId>
        <artifactId>spotbugs-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
```

## Isolation

- **Never install dependencies into a shared host `~/.m2`** for project builds — the Docker-mounted `MAVEN_CACHE` is project-scoped via `-v`
- `mvnw`/`mvnw.cmd`/`.mvn/wrapper/` (Maven Wrapper) committed when reproducible Maven-version pinning matters
- CI and Docker always build in batch mode (`-B`)

## Type Safety and Correctness

- **`@NonNull`/`@Nullable`** (JSR-305 or JetBrains annotations) on every public method parameter and return type
- **No raw types** — always parameterize generics (`List<String>`, never `List`)
- **`Optional<T>`** for a method's return type when "no value" is a valid outcome — never return `null` from a method whose signature doesn't make that explicit via `Optional`
- **Records** (`record Point(int x, int y) {}`) for immutable data carriers — never a hand-written class with only getters, equals, hashCode, toString
- **`var`** for local-variable type inference only when the right-hand side already makes the type obvious; never for public API surfaces
- **Visibility**: package-private/`private` by default; a member is `public` only when it is genuinely part of the module's external API

```java
public Optional<Version> parseVersion(String raw) {
    if (raw == null) {
        return Optional.empty();
    }
    String[] parts = raw.split("\\.");
    if (parts.length != 3) {
        return Optional.empty();
    }
    return Optional.of(new Version(parts[0], parts[1], parts[2]));
}
```

## Linting and Formatting

- **Checkstyle** for style enforcement (Google Java Style or a documented project-specific ruleset)
- **SpotBugs** for static bug-pattern analysis
- CI runs `mvn checkstyle:check spotbugs:check` — zero warnings allowed
- `google-java-format` (or the IDE's built-in formatter matching the same style) for auto-formatting; never commit format drift

## Testing

Use **JUnit 5**.

```java
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;

class MainTest {
    @Test
    void parseVersionReturnsEmptyForMalformedInput() {
        assertEquals(Optional.empty(), parseVersion("not-a-version"));
    }
}
```

- Unit tests in `src/test/java/{package}/` mirroring `src/main/java/{package}/`
- **Mockito** for mocking
- Coverage via **JaCoCo** Maven plugin when a threshold is required

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `picocli` for CLI argument parsing — never hand-roll.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```java
static boolean resolveColor(String flag) {
    if ("yes".equals(flag)) return true;
    if ("no".equals(flag)) return false;
    return System.getenv("NO_COLOR") == null && System.console() != null;
}
```

## Build Info Variables

```java
public final class BuildInfo {
    public static final String VERSION = System.getenv().getOrDefault("BUILD_VERSION", "devel");
    public static final String COMMIT_ID = System.getenv().getOrDefault("BUILD_COMMIT", "N/A");
    public static final String BUILD_DATE = System.getenv().getOrDefault("BUILD_DATE", "N/A");
    private BuildInfo() {}
}
```

Pass via `--build-arg` in Docker or `-e` at container run time.

## Directory Naming

**Plural** for all non-package directories (`handlers/`, `models/`, `routes/`, `scripts/`, `tests/`). Package directories follow the reverse-domain convention.

## Code Rules

- **No checked-exception swallowing** — an empty `catch (Exception e) {}` is a hard defect; at minimum log and rethrow or handle explicitly
- **Try-with-resources** for all `AutoCloseable` resources — never manual `finally { close(); }`
- **Immutable objects by default** — `final` fields, defensive copies for mutable collection fields returned from getters
- **No `System.out.println` in library code** — use `java.util.logging`, SLF4J, or the project's chosen logging facade; `println` only in CLI entry points
- **No `Class.forName()`/reflection-based instantiation** with untrusted input
- **No external cron** — in-process scheduling only (`ScheduledExecutorService` for simple periodic tasks, Quartz for multiple jobs or cron-expression scheduling)
