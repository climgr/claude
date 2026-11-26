---
name: Node/TypeScript conventions
description: Build system, project layout, Makefile targets, and code rules for CasjaysDev Node/TypeScript projects
type: user
---

## Project Layout

```
{project_name}/
├── src/            # TypeScript source files
├── tests/          # integration tests and test helpers
├── dist/           # compiled output — gitignored
├── node_modules/   # dependencies — gitignored
├── docker/
│   ├── Dockerfile
│   └── rootfs/
├── scripts/
├── package.json
├── package-lock.json   # always committed
├── tsconfig.json
├── eslint.config.js    # ESLint v9+ flat config (or .eslintrc.json for v8)
├── .prettierrc.json
├── Makefile
├── release.txt     # current version string (e.g. 0.1.0)
└── AI.md
```

Source always under `src/` — never at repo root. Entry point is `src/index.ts` for libraries and `src/main.ts` for CLI/server tools.

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

NPM_CACHE ?= $(HOME)/.npm

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

NODE_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(NPM_CACHE):/root/.npm \
	-w /build \
	node:alpine
```

## Makefile — Standard Targets

| Target | What it does |
|--------|-------------|
| `build` | Compiles TypeScript to `dist/` inside Docker |
| `test` | Runs ESLint, TypeScript check, then test suite inside Docker |
| `dev` | Quick local build into temp dir (Docker internally) |
| `lint` | Runs `eslint --max-warnings 0` + `prettier --check` |
| `docker` | Builds multi-arch image locally via `docker buildx` (no push) |
| `clean` | Removes `dist/`, `node_modules/` |

## Docker Build Pattern

```makefile
NPM_CACHE ?= $(HOME)/.npm

DOCKER_MEM  ?= 4g
DOCKER_CPUS ?= 2

NODE_DOCKER := docker run --rm \
	--name $(PROJECTNAME)-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS) \
	-v $(PWD):/build \
	-v $(NPM_CACHE):/root/.npm \
	-w /build \
	node:alpine
```

- Always `node:alpine` rolling tag — never pinned for dev tooling
- `NPM_CACHE` uses `?=` so a host `NPM_CACHE` env var (e.g. custom XDG path) is honored; default is `~/.npm`
- `npm ci` inside Docker uses the `NPM_CACHE` mount (`/root/.npm`) automatically — no extra flags needed
- Every target that uses `NODE_DOCKER` must `@mkdir -p $(NPM_CACHE)` first so the host dir exists before Docker mounts it and downloaded packages persist across runs
- Never run `node`, `npm`, `npx`, or `tsc` directly on host — always via `make`

## Target Patterns

Every target that invokes `NODE_DOCKER` must create the cache dir as its first step:

```makefile
build:
	@mkdir -p $(NPM_CACHE)
	$(NODE_DOCKER) sh -c 'npm ci && npm run build'

test:
	@mkdir -p $(NPM_CACHE)
	$(NODE_DOCKER) sh -c 'npm ci && npm run lint && npm run typecheck && npm run test'

dev:
	@mkdir -p $(NPM_CACHE)
	@mkdir -p "$${TMPDIR:-/tmp}/$(PROJECTORG)" && \
		BUILD_DIR=$$(mktemp -d "$${TMPDIR:-/tmp}/$(PROJECTORG)/$(PROJECTNAME)-XXXXXX") && \
		echo "Quick dev build..." && \
		$(NODE_DOCKER) sh -c 'npm ci && npm run build' && \
		cp -r dist "$$BUILD_DIR/" && \
		echo "Built: $$BUILD_DIR/dist"
```

**Rule — any direct `docker run` with a Node image** must also include the cache mount and the preceding mkdir.

## TypeScript Configuration

Minimum required `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "skipLibCheck": false,
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

- `strict: true` is non-negotiable — enables `strictNullChecks`, `noImplicitAny`, and all strict checks
- No `any` without an explanatory comment on the line above (`// reason: ...`)
- `noUncheckedIndexedAccess: true` — array index access returns `T | undefined`; handle it

## ESLint Configuration

ESLint v9+ flat config (`eslint.config.js`) preferred for new projects; `.eslintrc.json` acceptable for existing:

```js
// eslint.config.js (ESLint v9+)
import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": "error",
      "no-console": ["warn", { "allow": ["error", "warn"] }],
    },
  }
);
```

- CI runs `eslint --max-warnings 0` — zero warnings allowed; warnings are errors in CI
- Prettier handles formatting; ESLint handles correctness — never use ESLint to enforce formatting
- Prettier config at `.prettierrc.json`; run `prettier --check src` in CI

**Standard `.prettierrc.json`** — use this exact config for all Node/TS/Bun projects:

```json
{
  "useTabs": false,
  "printWidth": 120,
  "tabWidth": 2,
  "singleQuote": true,
  "trailingComma": "all",
  "semi": false
}
```

## Testing

Use **Vitest** for new projects (faster, native ESM, TypeScript-first). Jest is acceptable for existing projects.

```typescript
// Unit test — alongside source: src/utils.test.ts
import { describe, it, expect } from "vitest";
import { parseVersion } from "./utils.js";

describe("parseVersion", () => {
  it("parses semver string", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  it.each([
    ["1.0.0", { major: 1, minor: 0, patch: 0 }],
    ["0.1.0", { major: 0, minor: 1, patch: 0 }],
  ])("parses %s correctly", (input, expected) => {
    expect(parseVersion(input)).toEqual(expected);
  });
});
```

- Unit tests alongside source (`src/utils.test.ts`) — not in a separate `tests/unit/` tree
- Integration tests in `tests/`
- `vitest --coverage` generates coverage; thresholds in `vitest.config.ts`

## package.json Conventions

```json
{
  "type": "module",
  "scripts": {
    "build": "tsc",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "eslint src --max-warnings 0",
    "lint:fix": "eslint src --fix",
    "format": "prettier --write src",
    "format:check": "prettier --check src",
    "typecheck": "tsc --noEmit"
  }
}
```

- All scripts use `./node_modules/.bin/` binaries — never require global installs
- `npm ci` in CI (reproducible); `npm install` for local dev only
- No `<script src="https://...">` CDN scripts in HTML — bundle all assets at build time
- `package-lock.json` always committed

## Error Handling

- Extend `Error` for custom errors — always set `this.name` in the constructor
- Never `throw new Error("message")` in library code without a typed subclass
- Async: always `await` or `.catch()` — never ignore a rejected promise
- Never empty `catch` blocks — log and re-throw, or handle meaningfully
- Log the error at the boundary where it is caught, not at every layer it passes through

```typescript
class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly cause?: unknown
  ) {
    super(message);
    this.name = "AppError";
  }
}
```

## CLI Flags — Standard Interface

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 |
| `--version` | `-v` | — | Print version and exit 0 |
| `--debug` | — | — | Enable debug output |
| `--color` | — | `auto` (default) / `yes` / `no` | Color output — `auto`: TTY detect; `yes`: force on; `no`: force off |

- `--color auto` detects terminal capability (default); `yes` forces color on; `no` disables it and removes emojis from output.

All flags must support both `--flag value` and `--flag=value` — commander handles this natively.

Use `commander` for simple CLIs, `oclif` for multi-command plugin-style tools. Never hand-roll argument parsing.

### Toggle flags — `--enable`, `--disable`, `--yes`, `--no`

Never use compound hyphenated flags (`--enable-tls`, `--disable-cache`). The flag takes the feature name as a required argument: `--enable tls`, `--disable cache`. Same for `--yes` and `--no`.

**Exception:** `--color` is the standard three-value enum — `--color auto`, `--color yes`, `--color no`. There is no `--no-color` flag; `--color no` and the `NO_COLOR` env var both disable color.

```typescript
// commander example — flag takes a required argument
program.option("--enable <feature>",  "Enable a named feature");
program.option("--disable <feature>", "Disable a named feature");
program.option("--yes <thing>",       "Confirm yes for a named operation");
program.option("--no-op <thing>",     "Confirm no for a named operation");
// Note: commander treats --no-X as a boolean negation; use --no-op or a different name
// if the argument conflicts. In practice, prefer --disable over --no for Node CLIs.
```

## NO_COLOR Support

```typescript
function resolveColor(flag: string): boolean {
  if (flag === "yes") return true;
  if (flag === "no") return false;
  // "auto"
  if (process.env["NO_COLOR"] !== undefined) return false;
  return process.stdout.isTTY === true;
}
```

Honor `NO_COLOR` — any value set (including empty string) means no color.

## Build Info Variables

```typescript
// src/version.ts
export const VERSION = process.env["BUILD_VERSION"] ?? "devel";
export const COMMIT_ID = process.env["BUILD_COMMIT"] ?? "N/A";
export const BUILD_DATE = process.env["BUILD_DATE"] ?? "N/A";
```

Pass via `--build-arg` in Docker or `--env` at container run time. Never hardcode version strings.

## Directory Naming

**Plural** — all directories use plural names (`handlers/`, `models/`, `routes/`, `middlewares/`, `utils/`). Tooling dirs are also plural (`scripts/`, `tests/`, `completions/`).

## Code Rules

- **`import` only** — never `require()` in TypeScript; `"moduleResolution": "bundler"` or `"node16"` in tsconfig
- **No `process.exit()` in library code** — only in CLI entry points
- **Never log `req`, `res`, `ctx`, or `socket` objects** — they contain credentials; log only specific safe fields
- **No `eval()` or `new Function()`** with untrusted input — arbitrary code execution
- **No global state mutations in library code** — no side effects on `import`
- **`const` over `let`; never `var`**
- **Explicit return types on all exported functions** — inferred types are fine for unexported helpers
- **No `@ts-ignore`** — use `@ts-expect-error` with an explanatory comment on the line above when suppression is genuinely needed
- **No external cron** — never depend on host cron or systemd timers for application-level scheduling. Use in-process scheduling only: `setInterval`/`setTimeout` for simple intervals; `node-schedule` for cron-expression scheduling and date-based jobs.
