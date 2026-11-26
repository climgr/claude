---
name: Elixir conventions
description: Build system, project layout, Mix targets, and code rules for CasjaysDev Elixir projects
type: user
---

## Project Layout

```
{project_name}/
├── lib/
│   └── {project_name}/
│       └── main.ex
├── test/
│   ├── test_helper.exs
│   └── {project_name}_test.exs
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── mix.exs
├── mix.lock                      # always committed
├── .formatter.exs
├── .credo.exs
├── Makefile
├── release.txt                   # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `lib/{project_name}/` — module names mirror the directory path (`{ProjectName}.Main` in `lib/{project_name}/main.ex`).

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

MIX_CACHE ?= $(HOME)/.cache/mix-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

ELIXIR_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(MIX_CACHE):/root/.hex \
	-v $(MIX_CACHE):/root/.mix \
	-w /build \
	elixir:alpine
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `mix deps.get && MIX_ENV=prod mix release` inside Docker |
| `test` | `mix deps.get && mix test` inside Docker |
| `lint` | `mix format --check-formatted && mix credo --strict` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | `mix clean` — removes `_build/`, `deps/` |

## Docker Build Pattern

```makefile
MIX_CACHE ?= $(HOME)/.cache/mix-docker

ELIXIR_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(MIX_CACHE):/root/.hex \
	-v $(MIX_CACHE):/root/.mix \
	-w /build \
	elixir:alpine
```

- Official `elixir:alpine` image for the toolchain build stage (bundles Erlang/OTP + Elixir + Mix)
- `MIX_CACHE` uses `?=` so host env vars are honored; mounting `~/.hex`/`~/.mix` persists fetched Hex packages and installed archives across runs
- Every target using `ELIXIR_DOCKER` must `@mkdir -p $(MIX_CACHE)` first
- Never run `mix`/`iex`/`elixir` directly on host — always via `make`

## Target Patterns

```makefile
build:
	@mkdir -p $(MIX_CACHE)
	$(ELIXIR_DOCKER) sh -c 'mix deps.get && MIX_ENV=prod mix release'

test:
	@mkdir -p $(MIX_CACHE)
	$(ELIXIR_DOCKER) sh -c 'mix deps.get && mix test'

lint:
	@mkdir -p $(MIX_CACHE)
	$(ELIXIR_DOCKER) sh -c 'mix deps.get && mix format --check-formatted && mix credo --strict'
```

## mix.exs Structure

```elixir
defmodule {ProjectName}.MixProject do
  use Mix.Project

  def project do
    [
      app: :{project_name},
      version: System.get_env("BUILD_VERSION", "0.1.0"),
      elixir: "~> 1.17",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
```

## Isolation

- **Never fetch Hex packages into a shared host `~/.hex`/`~/.mix`** for project builds — the Docker-mounted `MIX_CACHE` is project-scoped via `-v`
- `mix.lock` is always committed — reproducible dependency resolution
- Never `mix archive.install` inside a project's CI build step — archives belong in the toolchain image, not a per-build install

## Correctness and Fault Tolerance

- **Pattern matching over conditionals** — a function head matching each shape beats a body full of `if`/`cond`
- **`{:ok, result}` / `{:error, reason}` tuples** for fallible operations — never a bare value that silently means both success and absence
- **"Let it crash"** — supervised processes handle failure via restart strategy, not defensive `try/rescue` sprinkled through business logic; `rescue` only at genuine boundary points (parsing untrusted input, external API calls)
- **`GenServer`/`Supervisor`** for stateful/long-running processes — never a raw unsupervised `spawn`

```elixir
def parse_version(nil), do: {:error, :missing}

def parse_version(raw) when is_binary(raw) do
  case String.split(raw, ".") do
    [maj, min, patch] ->
      with {maj_i, ""} <- Integer.parse(maj),
           {min_i, ""} <- Integer.parse(min),
           {patch_i, ""} <- Integer.parse(patch) do
        {:ok, {maj_i, min_i, patch_i}}
      else
        _ -> {:error, :invalid}
      end

    _ ->
      {:error, :invalid}
  end
end
```

## Linting and Formatting

- **`mix format`** for formatting — CI runs `mix format --check-formatted`, zero drift allowed
- **Credo** (`--strict`) for style/lint enforcement
- **Dialyzer** (`mix dialyzer`) for static type-discrepancy analysis when the project's complexity warrants it
- Project-specific rule overrides live in `.credo.exs`, never inline `# credo:disable-for-next-line` without a comment stating why on the line above

## Testing

Use **ExUnit**.

```elixir
defmodule {ProjectName}Test do
  use ExUnit.Case, async: true

  test "parse_version returns error for malformed input" do
    assert {:error, :invalid} = {ProjectName}.parse_version("not-a-version")
  end
end
```

- Test files in `test/`, one `{name}_test.exs` per lib file, `async: true` unless shared mutable state forbids it
- **Mox** for mocking behaviours (never mocking concrete modules directly)
- Coverage via `mix test --cover` (ExCoveralls for reports)

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `OptionParser` (stdlib) for CLI argument parsing — never hand-roll `System.argv()` scanning.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```elixir
def resolve_color("yes"), do: true
def resolve_color("no"), do: false
def resolve_color(_), do: is_nil(System.get_env("NO_COLOR")) and IO.ANSI.enabled?()
```

## Build Info Variables

```elixir
defmodule BuildInfo do
  @version System.get_env("BUILD_VERSION", "devel")
  @commit_id System.get_env("BUILD_COMMIT", "N/A")
  @build_date System.get_env("BUILD_DATE", "N/A")

  def version, do: @version
  def commit_id, do: @commit_id
  def build_date, do: @build_date
end
```

Module attributes capture the env values at compile time — pass via `--build-arg` in Docker or `-e` at build/release time.

## Directory Naming

**Plural** for all non-OTP-mandated directories (`handlers/`, `models/`, `routes/`, `scripts/`). `lib/`, `test/` are Elixir's own fixed convention names and stay as-is.

## Code Rules

- **No unsupervised `spawn`/`spawn_link`** for anything long-running — use a `Task`, `GenServer`, or `Supervisor` tree
- **No `String.to_atom/1` on untrusted input** — unbounded atom creation exhausts the atom table (a process-crashing DoS vector); use `String.to_existing_atom/1` or a mapping
- **No blocking calls inside a `GenServer.handle_call/3`** that could stall the process for an unbounded time — offload to a `Task` and reply asynchronously
- **Pipe operator (`|>`)** for sequential data transformations over deeply nested function calls
- **No external cron** — in-process scheduling only (`Process.send_after/3` for simple periodic tasks, the `quantum` library for cron-expression scheduling)
