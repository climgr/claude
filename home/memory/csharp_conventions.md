---
name: C#/.NET conventions
description: Build system, project layout, dotnet CLI targets, and code rules for CasjaysDev C#/.NET projects
type: user
---

## Project Layout

```
{project_name}/
├── src/
│   └── {ProjectName}/
│       ├── Program.cs
│       └── {ProjectName}.csproj
├── tests/
│   └── {ProjectName}.Tests/
│       ├── MainTests.cs
│       └── {ProjectName}.Tests.csproj
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── {project_name}.sln
├── Directory.Build.props        # shared MSBuild properties across projects
├── .editorconfig
├── Makefile
├── release.txt                  # current version string (e.g. 0.1.0)
└── AI.md
```

Every project lives under `src/{ProjectName}/` or `tests/{ProjectName}.Tests/` with its own `.csproj` — never a single flat `.csproj` mixing app and test code.

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

NUGET_CACHE ?= $(HOME)/.cache/nuget-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

DOTNET_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(NUGET_CACHE):/root/.nuget/packages \
	-w /build \
	mcr.microsoft.com/dotnet/sdk:alpine
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `dotnet build -c Release` inside Docker |
| `test` | `dotnet test` inside Docker |
| `lint` | `dotnet format --verify-no-changes` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | `dotnet clean` — removes `bin/`, `obj/` |

## Docker Build Pattern

```makefile
NUGET_CACHE ?= $(HOME)/.cache/nuget-docker

DOTNET_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(NUGET_CACHE):/root/.nuget/packages \
	-w /build \
	mcr.microsoft.com/dotnet/sdk:alpine
```

- Official `mcr.microsoft.com/dotnet/sdk:alpine` image for the toolchain build stage
- `NUGET_CACHE` uses `?=` so host env vars are honored; mounting `~/.nuget/packages` persists restored packages across runs
- Every target using `DOTNET_DOCKER` must `@mkdir -p $(NUGET_CACHE)` first
- Never run `dotnet` directly on host — always via `make`

## Target Patterns

```makefile
build:
	@mkdir -p $(NUGET_CACHE)
	$(DOTNET_DOCKER) dotnet build -c Release -warnaserror

test:
	@mkdir -p $(NUGET_CACHE)
	$(DOTNET_DOCKER) dotnet test

lint:
	@mkdir -p $(NUGET_CACHE)
	$(DOTNET_DOCKER) dotnet format --verify-no-changes
```

## .csproj Structure

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>
</Project>
```

## Isolation

- **Never restore packages into a shared host `~/.nuget/packages`** for project builds — the Docker-mounted `NUGET_CACHE` is project-scoped via `-v`
- `packages.lock.json` committed when `<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>` is set — reproducible restores
- Never `dotnet nuget push` from inside a build/test target — publishing is a separate, explicit release step

## Nullability and Correctness

- **`<Nullable>enable</Nullable>`** in every `.csproj` — nullable reference types are mandatory, not optional
- **No `!` null-forgiving operator** without a comment on the line above stating why the value is guaranteed non-null
- **`record` types** for immutable data carriers — never a class with only auto-properties and no behavior
- **`async`/`await` all the way down** — never `.Result`/`.Wait()` on a `Task`, which risks deadlock in synchronization-context-bound code

```csharp
public static (int, int, int)? ParseVersion(string? raw)
{
    if (raw is null) return null;
    var parts = raw.Split('.');
    if (parts.Length != 3) return null;
    if (!int.TryParse(parts[0], out var major)) return null;
    if (!int.TryParse(parts[1], out var minor)) return null;
    if (!int.TryParse(parts[2], out var patch)) return null;
    return (major, minor, patch);
}
```

## Linting and Formatting

- **`dotnet format`** for style enforcement and auto-formatting, driven by `.editorconfig`
- **Roslyn analyzers** (`Microsoft.CodeAnalysis.NetAnalyzers`, enabled by default in the SDK) with `TreatWarningsAsErrors` — zero warnings allowed
- Project-specific rule overrides live in `.editorconfig`, never inline `#pragma warning disable` without a comment stating why on the line above

## Testing

Use **xUnit**.

```csharp
using Xunit;

public class MainTests
{
    [Fact]
    public void ParseVersion_ReturnsNull_ForMalformedInput()
    {
        Assert.Null(Program.ParseVersion("not-a-version"));
    }
}
```

- Test projects in `tests/{ProjectName}.Tests/`, one per source project, referenced via `<ProjectReference>`
- **Moq** or **NSubstitute** for mocking
- Coverage via `dotnet test --collect:"XPlat Code Coverage"` (coverlet)

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `System.CommandLine` for CLI argument parsing — never hand-roll `args[]` scanning.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```csharp
static bool ResolveColor(string flag) => flag switch
{
    "yes" => true,
    "no" => false,
    _ => Environment.GetEnvironmentVariable("NO_COLOR") is null && !Console.IsOutputRedirected,
};
```

## Build Info Variables

```csharp
public static class BuildInfo
{
    public const string Version   = ThisAssembly.Git.Tag;
    public const string CommitId  = ThisAssembly.Git.Commit;
    public const string BuildDate = ThisAssembly.Git.CommitDate;
}
```

Populated at compile time via the `GitInfo`/`Nerdbank.GitVersioning` NuGet package, or injected via MSBuild `-p:Version=...` — never read from environment variables at runtime for values that should be baked into a release artifact.

## Directory Naming

**Plural** for all non-project directories (`handlers/`, `models/`, `routes/`, `scripts/`).

## Code Rules

- **No empty `catch {}`** — an empty catch swallowing all exceptions is a hard defect; at minimum log and rethrow or handle explicitly
- **`using` declarations** for all `IDisposable` resources — never manual `Dispose()` calls in a `finally` block when a `using` would do
- **Immutable-by-default DTOs** — `record`/`init`-only setters over mutable POCOs
- **No `dynamic`** unless interfacing with genuinely dynamic data (COM interop, reflection-heavy scenarios)
- **No external cron** — in-process scheduling only (`PeriodicTimer` for simple periodic tasks, Quartz.NET or Hangfire for multiple jobs)
