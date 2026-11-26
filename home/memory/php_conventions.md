---
name: PHP conventions
description: Build system, project layout, Composer targets, and code rules for CasjaysDev PHP projects
type: user
---

## Project Layout

```
{project_name}/
├── src/
│   └── {ProjectName}/
│       └── Main.php
├── tests/
│   └── {ProjectName}/
│       └── MainTest.php
├── bin/
│   └── {project_name}          # executable entrypoint, requires autoloader
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── composer.json
├── composer.lock                # always committed
├── phpunit.xml
├── phpstan.neon
├── .php-cs-fixer.php
├── Makefile
├── release.txt                  # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `src/{Namespace}/` with PSR-4 autoloading — never a flat top-level `*.php` sprawl.

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

COMPOSER_CACHE ?= $(HOME)/.cache/composer-docker

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

PHP_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(COMPOSER_CACHE):/tmp/composer-cache \
	-e COMPOSER_CACHE_DIR=/tmp/composer-cache \
	-w /build \
	composer:2
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | `composer install --no-dev --optimize-autoloader` inside Docker |
| `test` | `composer install && vendor/bin/phpunit` inside Docker |
| `lint` | `vendor/bin/phpcs && vendor/bin/phpstan analyse` inside Docker |
| `docker` | Builds multi-arch runtime image locally via `docker buildx` (no push) |
| `clean` | Removes `vendor/`, `.phpunit.cache/` |

## Docker Build Pattern

```makefile
COMPOSER_CACHE ?= $(HOME)/.cache/composer-docker

PHP_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(COMPOSER_CACHE):/tmp/composer-cache \
	-e COMPOSER_CACHE_DIR=/tmp/composer-cache \
	-w /build \
	composer:2
```

- Official `composer:2` image for the toolchain build/test/lint stages (bundles both PHP and Composer)
- `COMPOSER_CACHE` uses `?=` so host env vars are honored; mounting the Composer cache dir persists downloaded packages across runs
- Every target using `PHP_DOCKER` must `@mkdir -p $(COMPOSER_CACHE)` first
- Never run `php`/`composer`/`phpunit` directly on host — always via `make`

## Target Patterns

```makefile
build:
	@mkdir -p $(COMPOSER_CACHE)
	$(PHP_DOCKER) composer install --no-dev --optimize-autoloader

test:
	@mkdir -p $(COMPOSER_CACHE)
	$(PHP_DOCKER) sh -c 'composer install --quiet && vendor/bin/phpunit'

lint:
	@mkdir -p $(COMPOSER_CACHE)
	$(PHP_DOCKER) sh -c 'composer install --quiet && vendor/bin/phpcs && vendor/bin/phpstan analyse'
```

## composer.json Structure

```json
{
  "name": "{project_org}/{project_name}",
  "type": "library",
  "license": "MIT",
  "require": {
    "php": ">=8.2"
  },
  "require-dev": {
    "phpunit/phpunit": "^11.0",
    "squizlabs/php_codesniffer": "^3.10",
    "phpstan/phpstan": "^1.12"
  },
  "autoload": {
    "psr-4": { "{ProjectName}\\": "src/" }
  },
  "autoload-dev": {
    "psr-4": { "{ProjectName}\\Tests\\": "tests/" }
  }
}
```

## Isolation

- **`composer install` always writes to a project- or Docker-scoped cache** (`COMPOSER_CACHE` mount) — never a shared host-wide vendor cache used across unrelated projects
- `composer.lock` is always committed — reproducible installs
- Never `composer global require` inside a project's Docker build

## Type Safety and Correctness

- **`declare(strict_types=1);`** at the top of every `.php` file — PHP's default loose type coercion is a correctness hazard
- **Typed properties and return types** on every method — no untyped `public $foo;`
- **`readonly` properties** for immutable value objects (PHP 8.1+)
- **`?Type` nullable unions**, never returning `null` from a method whose declared return type doesn't say so

```php
<?php

declare(strict_types=1);

function parseVersion(?string $raw): ?array
{
    if ($raw === null) {
        return null;
    }
    $parts = explode('.', $raw);
    if (count($parts) !== 3) {
        return null;
    }
    return array_map('intval', $parts);
}
```

## Linting and Formatting

- **PHP_CodeSniffer (`phpcs`)** for style enforcement (PSR-12 baseline)
- **PHP-CS-Fixer** for auto-formatting
- **PHPStan** (level 8 or higher) for static analysis
- CI runs `phpcs`, `phpstan analyse` — zero errors allowed

## Testing

Use **PHPUnit**.

```php
<?php

declare(strict_types=1);

namespace {ProjectName}\Tests;

use PHPUnit\Framework\TestCase;
use function {ProjectName}\parseVersion;

final class MainTest extends TestCase
{
    public function testParseVersionReturnsNullForMalformedInput(): void
    {
        $this->assertNull(parseVersion('not-a-version'));
    }
}
```

- Test files in `tests/{Namespace}/`, one `*Test.php` per source file
- Coverage via `phpunit --coverage-text` (requires Xdebug or PCOV in the toolchain image)

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output |

All flags support `--flag value` and `--flag=value`. Use `symfony/console` for CLI argument parsing — never hand-roll `$argv` parsing.

### Toggle flags

Never compound hyphenated flags (`--enable-tls`). Use `--enable tls`, `--disable cache`, `--yes thing`, `--no thing`. `--color` stays the three-value enum exception.

## NO_COLOR Support

```php
function resolveColor(string $flag): bool
{
    if ($flag === 'yes') {
        return true;
    }
    if ($flag === 'no') {
        return false;
    }
    return getenv('NO_COLOR') === false && stream_isatty(STDOUT);
}
```

## Build Info Variables

```php
final class BuildInfo
{
    public const VERSION    = '%BUILD_VERSION%';
    public const COMMIT_ID  = '%BUILD_COMMIT%';
    public const BUILD_DATE = '%BUILD_DATE%';
}
```

Values injected at build time by replacing the placeholders (e.g. `sed` in the Makefile) since PHP has no native compile-time constant injection — never read directly from `getenv()` at runtime for values that should be baked into a release artifact.

## Directory Naming

**Plural** for all non-namespace directories (`handlers/`, `models/`, `routes/`, `tests/`, `scripts/`).

## Code Rules

- **No `@` error-suppression operator** — handle the error explicitly or let it propagate
- **No `extract()`/`eval()`/`unserialize()` on untrusted input** — injection and object-injection risk
- **Parameterized queries only** — PDO prepared statements, never string-concatenated SQL
- **No global mutable state** (`global $x`) — pass dependencies explicitly or use a container
- **No external cron** — in-process scheduling only (a long-running worker process with a sleep loop, or a proper job-queue library for multiple jobs)
