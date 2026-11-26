---
name: Ruby conventions
description: Build system, project layout, Bundler/Rake targets, and code rules for CasjaysDev Ruby projects
type: user
---

## Project Layout

```
{project_name}/
├── lib/
│   └── {project_name}/
│       └── main.rb
├── bin/
│   └── {project_name}         # executable entrypoint, requires lib/
├── spec/                      # RSpec test files
│   ├── spec_helper.rb
│   └── {project_name}_spec.rb
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── Gemfile
├── Gemfile.lock                # always committed
├── {project_name}.gemspec
├── Rakefile
├── Makefile
├── release.txt                 # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `lib/{project_name}/` — never at repo root. `bin/{project_name}` is a thin executable that `require`s the library.

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

BUNDLE_CACHE ?= $(HOME)/.cache/bundle-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

RUBY_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(BUNDLE_CACHE):/usr/local/bundle \
	-w /build \
	ruby:alpine
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `bundle exec rake build` inside Docker (builds the gem) |
| `test` | `bundle exec rspec` inside Docker |
| `lint` | `bundle exec rubocop` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | Removes `pkg/`, `.rspec_status`, `coverage/` |

## Docker Build Pattern

```makefile
BUNDLE_CACHE ?= $(HOME)/.cache/bundle-docker

RUBY_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(BUNDLE_CACHE):/usr/local/bundle \
	-w /build \
	ruby:alpine
```

- Official `ruby:alpine` image for the toolchain build stage
- `BUNDLE_CACHE` uses `?=` so host env vars are honored; mounting `/usr/local/bundle` persists installed gems across runs
- Every target using `RUBY_DOCKER` must `@mkdir -p $(BUNDLE_CACHE)` first
- Never run `ruby`/`bundle`/`rspec`/`rubocop` directly on host — always via `make`

## Target Patterns

```makefile
build:
	@mkdir -p $(BUNDLE_CACHE)
	$(RUBY_DOCKER) sh -c 'bundle install --quiet && bundle exec rake build'

test:
	@mkdir -p $(BUNDLE_CACHE)
	$(RUBY_DOCKER) sh -c 'bundle install --quiet && bundle exec rspec'

lint:
	@mkdir -p $(BUNDLE_CACHE)
	$(RUBY_DOCKER) sh -c 'bundle install --quiet && bundle exec rubocop'
```

## Gemfile / gemspec Structure

```ruby
# Gemfile
source "https://rubygems.org"
gemspec

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.65"
end
```

```ruby
# {project_name}.gemspec
Gem::Specification.new do |spec|
  spec.name          = "{project_name}"
  spec.version       = ENV.fetch("BUILD_VERSION", "0.1.0")
  spec.summary       = "..."
  spec.authors       = ["{project_org}"]
  spec.license       = "MIT"
  spec.files         = Dir["lib/**/*.rb"]
  spec.executables   = ["{project_name}"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.2"
end
```

## Isolation

- **`bundle install` always writes to a project- or Docker-scoped path** (`BUNDLE_CACHE` mount) — never a shared host GEM_HOME for project builds
- `Gemfile.lock` is always committed — reproducible installs
- Never `gem install` a runtime dependency directly on host or inside the image outside Bundler

## Type Safety and Correctness

- **RBS or Sorbet signatures** (`sig/` directory or inline `sig do...end` blocks) for any public library API — plain Ruby is dynamically typed, but a published gem's public surface should still declare its contract
- **Keyword arguments** for any method with more than one parameter — positional args become ambiguous and error-prone past one
- **`Data.define`** (Ruby 3.2+) for immutable value objects — never a hand-rolled `Struct` subclass with mutable accessors for the same purpose

```ruby
def parse_version(raw)
  return nil if raw.nil?

  parts = raw.split(".").map { |p| Integer(p, exception: false) }
  return nil unless parts.size == 3 && parts.all?

  parts
end
```

## Linting and Formatting

- **RuboCop** for both linting and formatting (`rubocop -a` for auto-correct)
- CI runs `bundle exec rubocop` — zero offenses allowed
- Project-specific rule overrides live in `.rubocop.yml`, never inline `# rubocop:disable` without a comment stating why on the line above

## Testing

Use **RSpec**.

```ruby
# spec/{project_name}_spec.rb
require "spec_helper"

RSpec.describe "#parse_version" do
  it "returns nil for malformed input" do
    expect(parse_version("not-a-version")).to be_nil
  end
end
```

- Spec files in `spec/`, one `{name}_spec.rb` per lib file
- Shared setup in `spec/spec_helper.rb`
- Coverage via `simplecov`; thresholds configured in `spec_helper.rb`

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `OptionParser` (stdlib) or `thor` for complex multi-command CLIs — never hand-roll `ARGV` parsing.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```ruby
def resolve_color(flag)
  return true if flag == "yes"
  return false if flag == "no"

  ENV["NO_COLOR"].nil? && $stdout.tty?
end
```

## Build Info Variables

```ruby
module BuildInfo
  VERSION    = ENV.fetch("BUILD_VERSION", "devel")
  COMMIT_ID  = ENV.fetch("BUILD_COMMIT", "N/A")
  BUILD_DATE = ENV.fetch("BUILD_DATE", "N/A")
end
```

Pass via `--build-arg` in Docker or `-e` at container run time.

## Directory Naming

**Plural** for all directories (`handlers/`, `models/`, `routes/`, `lib/` and `spec/` are Ruby's own fixed convention names and stay as-is).

## Code Rules

- **`frozen_string_literal: true`** magic comment at the top of every `.rb` file
- **No monkey-patching core classes** (`String`, `Array`, `Hash`, etc.) without an explicit refinement (`using`) scoped to the file that needs it
- **No bare `rescue`** — always `rescue SomeError` or at minimum `rescue StandardError`; never swallow silently
- **No `eval`/`instance_eval`/`send`** with untrusted input — arbitrary code execution
- **Blocks over explicit iteration** — `each`/`map`/`select` over manual `for`/`while` loops for collection processing
- **No external cron** — in-process scheduling only (a `sleep`-loop background thread for simple periodic tasks, `rufus-scheduler` for multiple jobs or cron-expression scheduling)
