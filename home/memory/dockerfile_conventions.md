---
name: Dockerfile conventions
description: Structure, annotations, and patterns for CasjaysDev Dockerfiles
type: user
---

## Location

All Docker assets live under `docker/`. Never in the repo root — that is a forbidden location per `~/.claude/memory/project_files.md`.

**`docker/Dockerfile*` and `docker/rootfs*` are project-specific.** Not every project needs a toolchain image, a devel image, or a rootfs overlay. Include only what the project actually requires:

| File | Tag | Required? |
|------|-----|-----------|
| `docker/Dockerfile` | `:latest` / `:release` | When the project ships a container image |
| `docker/Dockerfile.build` | `:build` | When the project has a CI toolchain image |
| `docker/Dockerfile.dev` | `:devel` | When the project ships a debug-mode image |
| `docker/rootfs/` | — | When the image needs a filesystem overlay |

## Toolchain Image — Decision Tree

**Two different images — do not conflate them:**

| Image | Where it lives | What picks it |
|-------|----------------|---------------|
| Toolchain (CI jobs, `make` container builds, `:build` tag) | `docker/Dockerfile.build` or a maintained image | This decision tree |
| Runtime (what ships) | Final stage of `docker/Dockerfile` | The project — alpine, scratch, distroless, or whatever the project declares; this tree does NOT apply |

**Toolchain image precedence (first match wins):**
1. **Image declared by the project** (IDEA.md, SPEC.md, or AI.md names a build image) — project files override global rules; use it as declared
2. **`docker/Dockerfile.build` exists** → use `{project_org}/{project_name}:build`
3. **Language table default** below

**Go, Rust, and Android default to NO `docker/Dockerfile.build`.** The maintained casjaysdev images cover virtually every need. A `Dockerfile.build` is allowed ONLY when the casjaysdev image genuinely cannot satisfy the need — proprietary SDK, vendor toolchain, exotic system libraries, exotic pinned NDK — and then it MUST be `FROM casjaysdev/go:latest` / `FROM casjaysdev/rust:latest` / `FROM casjaysdev/android:latest`: extend the maintained image, never replace it. Document the reason in a comment at the top of `Dockerfile.build`.

**All other languages:** use the maintained per-language image unless the project has a specific need that the standard image cannot meet.

| Language | Use this image | Notes |
|----------|---------------|-------|
| Go | `casjaysdev/go:latest` | Alpine; latest stable Go; goreleaser, golangci-lint, staticcheck, gofumpt, gotestsum, ko, air, buf, goose, goimports, stringer, gopls, govulncheck, go-licenses, cyclonedx-gomod, dlv, gops, benchstat, wire, mockgen, protoc-gen-go, protoc-gen-go-grpc pre-installed; `CGO_ENABLED=0`; `GOFLAGS=-buildvcs=false`; `GOTOOLCHAIN=auto`; `GOTELEMETRY=off`. **Default: no `docker/Dockerfile.build`** — genuine custom need only, and then `FROM casjaysdev/go:latest`. |
| Rust | `casjaysdev/rust:latest` | Alpine; stable + nightly; rustfmt, clippy, rust-src, rust-analyzer, llvm-tools-preview, miri; C/C++ toolchain (clang, lld, cmake, gdb); mingw-w64-gcc; zig; binaryen; 30+ cross-compile targets (musl/glibc Linux, Windows GNU, macOS, FreeBSD, WASM, embedded ARM/RISC-V, Android); cargo-binstall; 40+ cargo tools (cargo-audit, cargo-deny, cargo-tarpaulin, cargo-llvm-cov, sccache, cargo-zigbuild, wasm-pack, cargo-nextest, cargo-release, cargo-dist, cargo-deb, and more). **Default: no `docker/Dockerfile.build`** — genuine custom need only, and then `FROM casjaysdev/rust:latest`. |
| Android | `casjaysdev/android:latest` | Android SDK + build-tools, Gradle, JDK 17, lint tooling pre-installed; `ANDROID_HOME` preset — never volume-mount over `/opt/android-sdk`; source → `/workspace`, `GRADLE_USER_HOME=/workspace/.gradle`. **Default: no `docker/Dockerfile.build`** — genuine custom need only (e.g. exotic pinned NDK, proprietary vendor SDK), and then `FROM casjaysdev/android:latest`. |
| Node / TypeScript | `node:alpine` | Official Alpine image — add project tools via `npm ci` inside the container |
| Python | `python:alpine` | Official Alpine image; use `python:slim-bookworm` (Debian slim) when a native-dep package fails to build on musl |
| Other | Official Alpine image where one exists, then official Debian slim | Never use a `:latest` Ubuntu or full Debian image |
| Custom need | `docker/Dockerfile.build` | Only when the above options are genuinely insufficient — e.g. a proprietary SDK, a tool with no Alpine/official image, or a multi-language toolchain. **Go/Rust/Android: genuine custom need only, and always `FROM` the casjaysdev image.** |

Never use a language-specific image (`casjaysdev/go`, `casjaysdev/rust`, etc.) for a project that is not written in that language.

## Dockerfile.build — Custom Toolchain Image

Only create `docker/Dockerfile.build` when the decision tree above leads to "Custom need". It is tagged `{project_org}/{project_name}:build` and contains the entire toolchain required to build, test, lint, and scan the project.

### Rules

- **Base is always an official or maintained image** — `casjaysdev/go:latest` for Go extensions, `node:alpine` for Node extensions, etc. Never use a generic Alpine or Debian base without a toolchain pre-loaded unless that is the point.
- **Must be fully functional before committing any CI workflow that uses it.** Bootstrap order: (1) commit only `docker/Dockerfile.build`; (2) trigger `build-toolchain.yml` via `workflow_dispatch` and verify the image is in the registry; (3) only then commit `ci.yml`, `release.yml`, and any other workflow that pulls it. CI workflows that arrive before the image exists will fail immediately with no recovery path.
- **CI workflows pull, never build, this image.** The `ensure-build-image` job is pull-only and fails fast if the image is missing — it never builds inline. If the image is absent, the job fails with an actionable error telling the operator to trigger `build-toolchain.yml`. Wasting CI minutes on an uncontrolled inline build is forbidden.
- **Built monthly** via a dedicated `.github/workflows/build-toolchain.yml` (and equivalent on other providers). Pushed to the registry on schedule and on `workflow_dispatch`.
- **Tag is always `:build`** — never pinned to a version tag; always the latest monthly build.
- **Fork-portable** — the workflow that builds this image uses `github.repository_owner` / `github.event.repository.name` (or equivalent provider variables), never hardcoded org or project name.

### Monthly build workflow (GitHub Actions pattern)

```yaml
name: Build Toolchain Image
on:
  schedule:
    # 1st of each month at 04:00 UTC
    - cron: '0 4 1 * *'
  workflow_dispatch:

permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-26.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1

      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f  # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069  # v4.4.1

      - uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc  # v7.4.0
        with:
          context: .
          file: docker/Dockerfile.build
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}:build
```

---

## Structure

Two-stage build: `builder` compiles the binary; runtime stage is minimal Alpine by default. **Exception: `Dockerfile.aio`** (all-in-one variant bundling PostgreSQL + Valkey + Tor) must use `debian:latest` — those services require glibc and system libraries unavailable on Alpine/musl. Never use Alpine for AIO images.

Section headers use `=` fence comments:
```dockerfile
# =============================================================================
# Build Stage - Compile Go binary
# =============================================================================
```

## Build Stage

```dockerfile
FROM casjaysdev/go:latest AS builder

ARG TARGETARCH
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build \
    -ldflags "-s -w -X 'main.Version=${VERSION}' -X 'main.CommitID=${VCS_REF}' -X 'main.BuildDate=${BUILD_DATE}'" \
    -o /app ./src
```

- Always pass `TARGETARCH` for multi-arch builds
- `CGO_ENABLED=0` always (no exceptions — see NEVER rules)
- Rolling `casjaysdev/go:latest` tag (never pinned for dev tooling)

## Runtime Stage

```dockerfile
FROM alpine:latest

ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
ARG LICENSE=MIT
```

**No `LABEL` blocks in the Dockerfile.** Metadata is applied as OCI annotations at build time — see [OCI Annotations](#oci-annotations) below. `LABEL` applies only to the individual per-platform image layer; multiarch manifest indexes do not inherit labels, so they appear missing on multiarch pulls. Annotations are the correct mechanism for multiarch image metadata.

## OCI Annotations

All image metadata uses OCI annotations applied via `--annotation` flags on `docker buildx build`, not `LABEL` in the Dockerfile. Annotations attach to the manifest index (the multiarch top-level manifest) and are visible on all platforms.

### Annotations passed at build time

Split into static (names, URLs) and dynamic (version, date, revision) — pass both sets to every `docker buildx build` invocation:

**Static annotations** (substituted from build-time variables — never hardcoded):
```
--annotation "maintainer={project_org} <{project_org}@casjay.pro>"
--annotation "org.opencontainers.image.vendor={project_org}"
--annotation "org.opencontainers.image.authors={project_org}"
--annotation "org.opencontainers.image.title={project_name}"
--annotation "org.opencontainers.image.base.name={project_name}"
--annotation "org.opencontainers.image.description=Containerized version of {project_name}"
--annotation "org.opencontainers.image.url=https://github.com/{project_org}/{project_name}"
--annotation "org.opencontainers.image.source=https://github.com/{project_org}/{project_name}"
--annotation "org.opencontainers.image.documentation=https://github.com/{project_org}/{project_name}"
--annotation "org.opencontainers.image.vcs-type=Git"
--annotation "com.github.containers.toolbox=false"
```

**Dynamic annotations** (from build-time environment):
```
--annotation "org.opencontainers.image.licenses=${LICENSE}"
--annotation "org.opencontainers.image.created=${BUILD_DATE}"
--annotation "org.opencontainers.image.version=${VERSION}"
--annotation "org.opencontainers.image.schema-version=${VERSION}"
--annotation "org.opencontainers.image.revision=${VCS_REF}"
```

### In GitHub Actions — use `docker/metadata-action` annotations output

```yaml
- uses: docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302  # v6.2.0
  id: meta
  with:
    images: ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}
    annotations: |
      maintainer=${{ github.repository_owner }} <${{ github.repository_owner }}@casjay.pro>
      org.opencontainers.image.vendor=${{ github.repository_owner }}
      org.opencontainers.image.authors=${{ github.repository_owner }}
      org.opencontainers.image.title=${{ github.event.repository.name }}
      org.opencontainers.image.description=Containerized version of ${{ github.event.repository.name }}
      org.opencontainers.image.url=${{ github.event.repository.html_url }}
      org.opencontainers.image.source=${{ github.event.repository.html_url }}
      org.opencontainers.image.documentation=${{ github.event.repository.html_url }}
      org.opencontainers.image.vcs-type=Git
      com.github.containers.toolbox=false

- uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc  # v7.4.0
  with:
    annotations: ${{ steps.meta.outputs.annotations }}
    # no labels — annotations only
    labels: ""
    tags: ${{ steps.meta.outputs.tags }}
```

Note: `github.repository_owner`, `github.event.repository.name`, and `github.event.repository.html_url` are dynamic — they work correctly after a fork without any changes.

## Portability Rule

**No hardcoded org, project name, site, or registry values anywhere in Dockerfiles, workflows, or Makefiles** (comments and license files exempt). Use build-time ARGs, environment variables, or provider-supplied context variables:

| Context | How to reference |
|---------|-----------------|
| Dockerfile | `ARG PROJECT_ORG` / `ARG PROJECT_NAME` — passed via `--build-arg` |
| GitHub Actions | `${{ github.repository_owner }}` / `${{ github.event.repository.name }}` |
| GitLab CI | `$CI_REGISTRY_IMAGE`, `$CI_PROJECT_NAMESPACE`, `$CI_PROJECT_NAME` |
| Jenkinsfile | `${env.JOB_NAME}`, `${env.GIT_URL}` — parse org/name from these |
| Makefile | `PROJECT_ORG ?= $(shell git remote get-url origin | ...)` |

This ensures workflows function correctly after a fork without editing any values.

## Required Patterns

```dockerfile
# Install packages
RUN apk add --no-cache bash tini ...

# Create runtime directories
RUN mkdir -p /config /data/...

# Copy binary from builder
COPY --from=builder /app /usr/local/bin/{name}

# Copy rootfs overlay (mirrors Linux FHS)
COPY docker/rootfs/ /

# Copy Dockerfile into image for reference
# NOTE: if the image declares a non-root USER (see "Non-root User" below), /root/Dockerfile is
# not readable by the runtime user. In that case copy to a world-readable path instead, e.g.
# COPY docker/Dockerfile /usr/local/share/{name}/Dockerfile
COPY docker/Dockerfile /root/Dockerfile

# Make all binaries executable
RUN chmod 755 /usr/local/bin/*

# Expose internal port (always 80 internally)
EXPOSE 80

# Graceful shutdown signal
STOPSIGNAL SIGRTMIN+3

# Health check
HEALTHCHECK --start-period=10m --interval=5m --timeout=15s --retries=3 \
    CMD /usr/local/bin/{name} --status || exit 1

# tini as PID 1 with SIGTERM propagation
ENTRYPOINT [ "tini", "-p", "SIGTERM", "--", "/usr/local/bin/entrypoint.sh" ]
```

## Rules

- `tini` is always PID 1 — never use bare binary as entrypoint
- `ENTRYPOINT` always delegates to `entrypoint.sh` — never bypass (see NEVER rules)
- Internal port is always 80; host mapping is in `docker-compose.yml`
- `docker/rootfs/` mirrors Linux FHS — files placed there are `COPY`'d into the image at `/`
- `apk add --no-cache` — never without `--no-cache`
- No secrets, credentials, or `.env` values baked into the image

## Non-root User

Containers must not run as root unless the process genuinely requires it. Add to the runtime stage after `chmod`:

```dockerfile
# Create a non-root user for runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```

If the app must bind to port 80 (or other privileged ports): use `tini` + `setcap` or remap to an unprivileged port (≥1024) inside the container and map externally via `docker-compose.yml`. Exceptions (filesystem mounts, device access, service management) must be documented in `{project_dir}/IDEA.md`.

## entrypoint.sh

`docker/rootfs/usr/local/bin/entrypoint.sh` is the only file that should live between `tini` and the application binary. Minimum required content:

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# entrypoint.sh — container startup script
# Called by: tini → entrypoint.sh → app
# Add pre-start setup here (env checks, migrations, etc.)
exec "$@"
```

Rules:
- Must end with `exec "$@"` — replaces the shell process with the app so PID 1 signal handling is preserved
- Never `source` secrets or credentials — use environment variables injected at runtime
- Always executable (`chmod 755`)

## Dockerfile.dev — Devel Image

`docker/Dockerfile.dev` builds the `:devel` image. It is structurally identical to the production `Dockerfile` (same base, same binary, same entrypoint) but runs the binary in debug mode — verbose logging, debug flags enabled, assertions active, no production hardening.

Rules:

- **Same image structure as release** — not a toolchain image; the compiled binary is baked in, not mounted at runtime
- **Binary runs in debug mode** — pass debug flags via `ENV` or `CMD`; do not change the image structure
- **`MODE=devel`** — set via `ENV` in `Dockerfile.dev` (not the release `Dockerfile`). The application must accept `dev`, `devel`, and `development` as synonymous valid values for `MODE`
- **Pushed to the registry** as `{project_org}/{project_name}:devel` — built by a `build-devel` **job inside the same `docker.yml`** workflow that builds the standard image (never a separate `docker-devel.yml` file). `docker.yml`'s `on:` block gains a `schedule: - cron: '0 4 * * *'` trigger alongside its existing push/tag/`workflow_dispatch` triggers; `build-devel` runs on that schedule plus every non-tag push, while `build-standard` runs on every push except the schedule event. One file, shared triggers/env/concurrency group, no duplicated workflow boilerplate. Where an all-in-one image exists (`docker/Dockerfile.aio`), it is *also* a single-file, multi-job workflow (`docker-aio.yml`) — the AIO image is the only image type that gets its own dedicated workflow file, because it is a materially different image (different base, different service composition), not just a different build mode. There is no `Dockerfile.dev.aio` by default, so `docker-aio.yml` normally has no devel job/tag unless a project explicitly adds that variant
- **No source mount, no hot-reload** — source is compiled into the image at build time; for live-reload development use the compose dev service with the `:devel` image
- Starts with `tini → entrypoint.sh → {binary} --debug` (or equivalent debug flag for the project)

### Devel build folded into docker.yml (GitHub Actions pattern)

```yaml
name: Docker Build
on:
  push:
    branches: ['**']
    tags:
      - 'v*'
      - '*.*.*'
  schedule:
    - cron: '0 4 * * *'
  workflow_dispatch:

permissions:
  contents: read
  packages: write

jobs:
  build-standard:
    runs-on: ubuntu-26.04
    if: github.event_name != 'schedule'
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1

      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f  # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069  # v4.4.1

      - id: vars
        run: echo "sha_short=${GITHUB_SHA:0:7}" >> "$GITHUB_OUTPUT"

      - uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc  # v7.4.0
        with:
          context: .
          file: docker/Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}:${{ steps.vars.outputs.sha_short }}
          # + latest/version/YYMM on tag push, + beta on beta branch push

  build-devel:
    runs-on: ubuntu-26.04
    if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && !startsWith(github.ref, 'refs/tags/'))
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1

      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f  # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069  # v4.4.1

      - uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc  # v7.4.0
        with:
          context: .
          file: docker/Dockerfile.dev
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}:devel
```

---

## Docker Compose

### File locations

All compose files live in `docker/`:
- `docker/docker-compose.yml` — production/human runtime
- `docker/docker-compose.dev.yml` — human development only (debug/devel; never used by AI)
- `docker/docker-compose.test.yml` — automated testing; AI's preferred interface is the `tests/` scripts, not invoking this file directly (see "AI Docker Compose rules" below)

All three follow the same layout: `name:` → `x-logging` anchor → `services:` → env map → `volumes:` → `ports:` → `healthcheck:` → `depends_on:` → `networks:` → top-level `networks:` block.

**Environment variables always use map style (`KEY: value`), never list style (`- KEY=value`).**

**`172.17.0.1:` bind** is reserved for the http/https port publish and appears only in `docker-compose.test.yml` and `docker-compose.yml` (production-shaped). `docker-compose.dev.yml` never uses it.

**`PORT: 80`** — the container's internal port is always `80`; only the published host-side port varies.

**valkey (cache)** — `docker-compose.test.yml` and `docker-compose.yml` include a valkey cache service; `docker-compose.dev.yml` never does.

### Volumes — path resolution

Compose files always use `./volumes` for bind-mount paths. `./volumes` is **relative to the compose file's location** — so it resolves to `docker/volumes/` when the compose file lives in `docker/`. In standalone deployment the compose file is copied to a separate directory and `./volumes` resolves there.

Both `volumes/` and `docker/volumes/` are gitignored — runtime data is never committed.

### Dev Compose (`docker-compose.dev.yml`)

Human debug/devel only. Uses the `:devel` image (built from `docker/Dockerfile.dev`). `DEBUG` on, `MODE: dev`, no `172.17.0.1:` bind, no valkey.

```yaml
name: {name}-dev

x-logging: &default-logging
  driver: json-file
  options:
    max-size: "5m"
    max-file: "1"

services:
  {name}:
    image: ghcr.io/{org}/{name}:devel
    container_name: {name}-dev
    hostname: {name}
    restart: always
    pull_policy: always
    logging: *default-logging
    environment:
      DEBUG: 1
      MODE: dev
      PORT: 80
      TZ: ${TZ:-America/New_York}
    volumes:
      - ./volumes/config:/config:z
      - ./volumes/data:/data:z
    ports:
      - "{port}:80"
    healthcheck:
      test: ["CMD", "/usr/local/bin/{name}", "--status"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 90s
    networks:
      - {name}-dev

networks:
  {name}-dev:
    name: {name}-dev
    external: false
```

### Production Compose (`docker-compose.yml`)

No `DEBUG`/`MODE` vars. Uses `172.17.0.1:` bind and valkey.

```yaml
# nginx proxy address - http://172.17.0.1:{port}

name: {project_name}

x-logging: &default-logging
  driver: json-file
  options:
    max-size: "5m"
    max-file: "1"

services:
  {name}:
    # replace with provider registry at deploy time
    image: ghcr.io/{org}/{name}:latest
    container_name: {name}-app
    hostname: {name}
    restart: always
    pull_policy: always
    logging: *default-logging
    environment:
      PORT: 80
      TZ: ${TZ:-America/New_York}
      CONTAINER_NAME: {name}-app
      HOSTNAME: ${BASE_HOST_NAME:-$HOSTNAME}
      CACHE_URL: valkey://{name}-cache:6379
    volumes:
      - ./volumes/config:/config:z
      - ./volumes/data:/data:z
    ports:
      - "172.17.0.1:{port}:80"
    healthcheck:
      test: ["CMD", "/usr/local/bin/{name}", "--status"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 90s
    depends_on:
      {name}-cache:
        condition: service_healthy
    networks:
      - {project_name}

  {name}-cache:
    image: valkey/valkey:alpine
    container_name: {name}-cache
    restart: always
    pull_policy: always
    logging: *default-logging
    volumes:
      - ./volumes/data/db/valkey:/data:z
    healthcheck:
      test: ["CMD-SHELL", "valkey-cli ping || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
    networks:
      - {project_name}

networks:
  {project_name}:
    name: {project_name}
    external: false
```

### Deployment Compose (third-party services, e.g. composemgr)

For deploying an external service rather than your own built image. **Three separate, standalone files — never one file with conditional network membership.** Each file is a complete compose stack a user runs on its own; they are deployment-mode alternatives, not layers meant to be combined with `-f`. Reference layout: `composemgr/template`.

| File | Reverse-proxy mode | Network | Labels | Port publish |
|---|---|---|---|---|
| `docker-compose.yaml` | none — plain nginx reverse proxy on the host | `{project_name}` only | none | yes — `172.17.0.1:{port}:{internal_port}` |
| `docker-compose.traefik.yaml` | traefik | `traefik` (external) | traefik routing labels | no |
| `docker-compose.tunnel.yaml` | Cloudflare tunnel | `cloudflare` (external) | cloudflare labels | no |

**`docker-compose.yaml` is the default and is the one nginx proxies to** — host-port-published, no reverse-proxy labels, no external network. `docker-compose.traefik.yaml` and `docker-compose.tunnel.yaml` swap the app service's networking for their respective proxy and drop the port publish; everything else (image, environment, volumes, DB service if any) stays identical across all three files.

```yaml
# nginx proxy address - http://172.17.0.1:{port}

name: {project_name}
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "5m"
    max-file: "1"

services:
  app:
    image: {upstream_image}:latest
    pull_policy: always
    container_name: {project_name}-app
    restart: always
    logging: *default-logging
    networks:
      - {project_name}
    ports:
      - "172.17.0.1:{port}:{internal_port}"
    environment:
      TZ: ${TZ:-America/New_York}
      CONTAINER_NAME: {project_name}-app
      HOSTNAME: ${BASE_HOST_NAME:-$HOSTNAME}
      # app-specific vars...
    volumes:
      - ./volumes/data/{project_name}:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      {project_name}-db:
        condition: service_healthy

  {project_name}-db:
    image: postgres:latest
    pull_policy: always
    container_name: {project_name}-db
    restart: always
    logging: *default-logging
    networks:
      # DB on project network only — never traefik/cloudflare
      - {project_name}
    environment:
      TZ: ${TZ:-America/New_York}
      POSTGRES_DB: ${DB_CREATE_DATABASE_NAME:-{project_name}}
      POSTGRES_USER: ${DB_USER_NAME:-{project_name}}
      POSTGRES_PASSWORD: ${DB_USER_PASS:-changeme_db_password}
      CONTAINER_NAME: {project_name}-db
    volumes:
      - ./volumes/data/db/postgres/{project_name}:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER_NAME:-{project_name}} -d ${DB_CREATE_DATABASE_NAME:-{project_name}}"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  {project_name}:
    name: {project_name}
    external: false
```

`docker-compose.traefik.yaml` — same file, app service's `networks`/`ports` replaced:

```yaml
    networks:
      - traefik
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik'
      - 'traefik.http.routers.{project_name}-app.entrypoints=http'
      - 'traefik.http.routers.{project_name}-app-secure.tls=true'
      - 'traefik.http.routers.{project_name}-app.rule=Host(${BASE_HOST_NAME:-$HOSTNAME})'
      - 'traefik.http.middlewares.{project_name}-app-https-redirect.redirectscheme.scheme=https'
      - 'traefik.http.routers.{project_name}-app.middlewares={project_name}-app-https-redirect'
      - 'traefik.http.routers.{project_name}-app-secure.entrypoints=https'
      - 'traefik.http.routers.{project_name}-secure.rule=Host(${BASE_HOST_NAME:-$HOSTNAME})'
      - 'traefik.http.routers.{project_name}-secure.tls.certresolver=cloudflare'
      - 'traefik.http.routers.{project_name}-secure.service={project_name}'
      - 'traefik.http.services.{project_name}.loadbalancer.server.port={internal_port}'
# (no ports: block — traefik owns ingress)

networks:
  traefik:
    external: true
```

`docker-compose.tunnel.yaml` — same file, app service's `networks`/`ports` replaced:

```yaml
    networks:
      - cloudflare
    labels:
      - 'cloudflare.enable=true'
      - 'cloudflare.service=http://{project_name}-app:{internal_port}'
      - 'cloudflare.hostname={project_name}.${CLOUDFLARE_ZONE_NAME:-}'
# (no ports: block — the tunnel owns ingress)

networks:
  cloudflare:
    external: true
```

Rules:
- **No `version:` field** — the top-level `version:` key is deprecated and ignored by all current Docker Compose versions; never include it
- **Three standalone files, never one file with conditional/optional network membership** — `docker-compose.yaml` (default, nginx-proxied via host port publish), `docker-compose.traefik.yaml`, `docker-compose.tunnel.yaml`. A repo only needs the alternates it actually supports — omit `docker-compose.traefik.yaml`/`docker-compose.tunnel.yaml` entirely rather than leaving an empty/unused variant.
- **Spell it `traefik`, never `traefix`** — filename, network name, and every `traefik.*` label key
- **Network name is always `{project_name}`** (base file) or the bare proxy name `traefik`/`cloudflare` (external, in the alternates) — never `{project_name}-net`, `{project_name}-app`, or any other suffix. The `name:` field under the network must match in the base file.
- **DB services join only the project network** — never `traefik` or `cloudflare`, in any of the three files
- **Healthcheck cadence** — `interval: 30s`, `timeout: 10s`, `retries: 3` for all DB services
- **Port comment** is the FIRST line of `docker-compose.yaml` only: `# nginx proxy address - http://172.17.0.1:{port}` — nothing above it, not even a description comment. `{port}` must match the actual `ports:` publish on the `app` service exactly (the external/host-side port, not the internal one).
- **`docker-compose.traefik.yaml`/`docker-compose.tunnel.yaml` never carry this comment** — they don't publish a port, so there's no external port for it to reference
- **`pull_policy: always`** on every service — ensures latest image on each `docker compose up`
- **`restart: always`** on every service
- **`x-logging` anchor** — apply to all services via `logging: *default-logging`
- **Only the base `docker-compose.yaml` publishes a port** — `docker-compose.traefik.yaml`/`docker-compose.tunnel.yaml` never carry a `ports:` block on the app service; the proxy owns ingress instead

### Test Compose (`docker-compose.test.yml`)

Testing the built binary/server. `DEBUG` on, `MODE: dev`, `172.17.0.1:` bind, valkey included.

```yaml
# nginx proxy address - http://172.17.0.1:{port}

name: {name}-test

x-logging: &default-logging
  driver: json-file
  options:
    max-size: "5m"
    max-file: "1"

services:
  {name}:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: {name}-test
    hostname: {name}
    restart: "no"
    logging: *default-logging
    environment:
      DEBUG: 1
      MODE: dev
      PORT: 80
      TZ: ${TZ:-America/New_York}
      CACHE_URL: valkey://{name}-cache-test:6379
    volumes:
      - ./volumes/config:/config:z
      - ./volumes/data:/data:z
    ports:
      - "172.17.0.1:{port}:80"
    healthcheck:
      test: ["CMD", "/usr/local/bin/{name}", "--status"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 90s
    depends_on:
      {name}-cache-test:
        condition: service_healthy
    networks:
      - {name}-test

  {name}-cache-test:
    image: valkey/valkey:alpine
    container_name: {name}-cache-test
    restart: "no"
    logging: *default-logging
    tmpfs:
      # ephemeral — always clean state
      - /data
    healthcheck:
      test: ["CMD-SHELL", "valkey-cli ping || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
    networks:
      - {name}-test

networks:
  {name}-test:
    driver: bridge
    # explicit name for reliable cleanup
    name: {name}-test
```

Test Compose rules:
- AI copies `docker-compose.test.yml` to a temp dir before running — `./volumes` resolves to `{tempdir}/volumes/`
- Named bridge network for all test services — never `--network host` or default bridge
- The valkey cache service uses `tmpfs` — no persistent volume, always starts clean
- Network name is explicit so `docker network rm {name}-test` cleans up reliably
- Never mount `./volumes/` or any project directory path at runtime during tests

### AI Docker Compose rules

- **NEVER** run `docker compose up` with `docker-compose.yml` or `docker-compose.dev.yml` — those are human-only
- **NEVER** mount `./volumes/` or any project-directory path at runtime when testing
- **`tests/` scripts are AI's preferred interface for testing** — prefer the project's `tests/` directory scripts over invoking `docker-compose.test.yml` directly; those scripts wrap the temp-dir copy/run/cleanup sequence below
- When a direct compose invocation is unavoidable (e.g. no `tests/` script exists yet): copy `docker/docker-compose.test.yml` to a temp dir and run from there — `./volumes` then resolves to `{tempdir}/volumes/`
- **NEVER** create or modify files in the project directory during testing

---

## Container ENV Conventions

### Process identity vars — container exception

Inside a Dockerfile `ENV` instruction, docker-compose `environment:` block, or a container `entrypoint.sh`, **all** environment variables are freely settable — including `HOME`, `USER`, `HOSTNAME`, `SHELL`, `PATH`, `TZ`, `LANG`, `UID`, etc. The host-script rule "never overwrite process identity vars" does not apply here. The container is an isolated environment being initialized from scratch; configuring these vars is correct and expected.

```yaml
# docker-compose environment: — all vars are fair game
environment:
  TZ: ${TZ:-America/New_York}
  HOSTNAME: ${BASE_HOST_NAME:-$HOSTNAME}
  CONTAINER_NAME: {project_name}-app
  HOME: /root
  USER: root
```

### Precedence order (highest to lowest)

1. Host environment variable or shell export (set before `docker compose up`)
2. `app.env` — app-specific overrides (KEY=VALUE, no `export`)
3. `default.env` — global stack defaults (shell script, all vars `export`ed, sourced by composemgr)
4. Inline `${VAR:-default}` fallback in `docker-compose.yml`
5. Dockerfile `ENV` instruction (baked into image — lowest precedence at runtime)

The stack must work at level 4 alone — all inline defaults must be sane enough to start the service without any env file.

### `default.env` and `app.env` pattern

Every deployable compose stack ships two sample env files:

| File | Format | Purpose |
|------|--------|---------|
| `default.env.sample` | Shell script — all vars `export`ed | Global stack defaults; sourced by composemgr as a shell script; covers TZ, domain, host IPs, DB URLs, credentials, email, tokens |
| `app.env.sample` | KEY=VALUE (no `export`) | App-specific overrides; read directly by docker-compose; overrides `default.env` for this service |

Users copy the samples and fill in values:
```sh
cp default.env.sample default.env
cp app.env.sample app.env
```

Both files are gitignored and excluded from Docker build context (listed in `.gitignore` and `.dockerignore`). Samples are committed; actual `.env` files never are.

### What goes in each file

**`default.env`** (global, all services share):
- `TZ`, `BASE_DOMAIN_NAME`, `BASE_HOST_NAME`
- `HOST_IP_4`, `HOST_IP_6` — host IP so containers can reach the host
- DB connection URLs (`REDIS_URL`, `POSTGRESQL_URL`, etc.) — use service name as default (`redis`, `postgres`)
- DB credentials (`DB_ADMIN_NAME`, `DB_ADMIN_PASS`, `DB_USER_NAME`, `DB_USER_PASS`)
- App credentials (`APP_ADMIN_USER`, `APP_ADMIN_PASS`, `APP_JWT_TOKEN`, `APP_API_TOKEN`, secrets)
- Email relay settings, Cloudflare settings, DNS settings

**`app.env`** (this service only — overrides default.env):
- `TZ`, `BASE_DOMAIN_NAME`, `BASE_HOST_NAME` (when this service needs a different value)
- Any service-specific vars that differ from the global defaults

### Credential placeholders in sample files

For any var that requires a generated value (passwords, tokens, secrets), include a commented generation command in `default.env.sample`:

```sh
# create a random secret:      openssl rand -hex 8
# create a random password:    head -n50 /dev/random | tr -dc 'a-zA-Z0-9[!@-]' | tr -d '[:space:]\042\047\134' | fold -w 32 | head -n 1
# create a bcrypt password:    htpasswd -nbBC 9 pass pass | sed 's|pass:||g'

export APP_JWT_TOKEN=""
export APP_SECRET_KEY=""
```

Never generate and commit a value in the sample — leave it blank with the generation command as a comment.

### Internal service vars — no random ports

Database, cache, queue, and other backend services that are **not** exposed to the host use their canonical port inside the container network (`5432`, `3306`, `6379`, etc.). No random port, no host binding. Their connection strings in `default.env` use the compose service name as hostname:

```sh
# connects to the 'redis' service on the compose network
export REDIS_URL="redis"
# connects to the 'postgres' service on the compose network
export POSTGRESQL_URL="postgres"
```

---

## .dockerignore

Same header format as `.gitignore`. Excludes everything that should not enter the Docker build context — version control, build artifacts, secrets, and local config.

**Build context is always the project root** — `docker build -f docker/Dockerfile .`. The `docker/` directory contains the Dockerfile and `rootfs/`; it is **never excluded** from the build context.

**Header:**
```
# .dockerignore created on MM/DD/YY at HH:MM
```

### Standard entries (all projects)

```dockerignore
# .dockerignore created on MM/DD/YY at HH:MM

# version control
.git/
.gitignore
.gitattributes

# local and secret config
.env
app.env
default.env
.claude/

# build artifacts
binaries/
releases/

# runtime volume data (never in image)
volumes/
docker/volumes/

# OS files
.DS_Store
Thumbs.db

# docs and meta (not needed in image)
*.md
LICENSE*
```

### Go project additions

```dockerignore
# Go toolchain cache (mounted at build time, not baked in)
vendor/
```

### Rust project additions

```dockerignore
# Rust build cache (rebuilt inside container)
target/
```

### What is NEVER excluded from Docker context

- `docker/` — contains the Dockerfile and `rootfs/`; always included, never excluded
- `src/` — all source code
- `go.mod`, `go.sum` — Go module files
- `Cargo.toml`, `Cargo.lock` — Rust manifest and lockfile
- `build.rs` — Rust build script
- `release.txt` — version string read at build time
