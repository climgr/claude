---
name: Execution hierarchy
description: QEMU/KVM > Incus > Docker > host; tier purpose, image selection, cleanup rules
type: user
---

Never run anything directly on the host unless no lower option works. Always use the lowest viable level:

1. **QEMU/KVM** — full OS isolation; required when the test needs a real kernel, firmware, or hardware emulation
2. **Incus** — distro-level tests that require systemd or a full init system; preferred for service installs and OS config testing
3. **Docker** — build, unit test, and integration work that does not need systemd; always use the official alpine variant for the stack
4. **Host** — last resort only (e.g. USB device access with no passthrough, host socket that cannot be forwarded)

## Image selection by tier

| Tier | Image to use | When |
|------|-------------|------|
| Docker | Maintained toolchain image: `casjaysdev/go:latest`, `casjaysdev/rust:latest`, `casjaysdev/android:latest`, `node:alpine`, `python:alpine`, etc. | Build, test, debug — never debian/ubuntu based |
| Incus | Distro image matching the target OS | systemd, service installs, OS config, distro compatibility |
| QEMU/KVM | Full OS image matching the target OS | Kernel-level, firmware, hardware emulation, full install testing |

## Cleanup rules

- **Stop and remove immediately** — every container, VM, volume, network, and temp file must be torn down as soon as it is no longer needed. Never leave them running until session end.
- **Track what you start** — note the name/ID of every container or VM before starting it; guarantee it appears in the cleanup step of the same task.
- Only remove resources created by the current project — never `docker system prune` or broad sweeps.
- Identify resources by name/label/prefix before removing; if uncertain, list and ask.

## Instance budget

A test needs a handful of instances, never one per distro or per package.
The tier order above is unchanged; this caps how many of any tier a project
may hold at once.

- **At most 4 running at once per project** across VMs, Incus instances, and
  detached containers (`CLAUDE_MAX_TEST_INSTANCES`, default 4). The shape is
  1-2 servers plus 2-3 clients, never a matrix.
- **Never one instance per distro, per package, or per variant.** Test a
  representative one, or run variants one after another in a single reused
  instance, tearing it down between variants.
- **Never launch from a loop, `xargs`, `parallel`, or `seq`.** One instance
  per command, so the cap is checked on every launch.
- **Over the cap needs the user's say-so.** Ask before raising
  `CLAUDE_MAX_TEST_INSTANCES`; never raise it to get a task done.
- Mechanically enforced by `limit-test-instances.sh`, which counts instances
  named `{project_name}-*` and fails open when no runtime answers. Subagent
  fan-out is capped separately by `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (4).

## Incus Instance Naming

Every Incus instance started by AI must follow the same naming schema as Docker containers:

```
{project_name}-XXXX
```

where `XXXX` is a random 8-character lowercase alphanumeric suffix — identical to the Docker `--name` convention.

```bash
SUFFIX=$(tr -dc 'a-z0-9' </dev/urandom | head -c8)
INSTANCE="{project_name}-${SUFFIX}"

incus launch {image} "${INSTANCE}" --network {project_name}-test-net
incus exec "${INSTANCE}" -- {command}
# ... work ...
incus delete --force "${INSTANCE}"
```

Rules:
- Always generate the suffix before the launch command; store it in a variable
- The instance name is the primary key for cleanup — record it immediately after launch
- Never use generic names (`test`, `temp`, `dev`) that cannot be traced to a project
- In Makefile targets: `SUFFIX=$$(tr -dc 'a-z0-9' </dev/urandom | head -c8)`

## Incus Network Isolation

Test instances must run on an isolated network — never on the default bridge:

```bash
incus network create {project_name}-test-net
incus launch {image} {project_name}-XXXX --network {project_name}-test-net
# ... run tests ...
incus delete --force {project_name}-XXXX
incus network delete {project_name}-test-net
```

Rules:
- Create a dedicated network before the first test instance starts; delete it after the last instance stops
- Never attach test instances to `lxdbr0` or any shared bridge
- Instances in the test network can reach each other by instance name via Incus DNS; no host port forwarding needed for inter-instance traffic
- Track the network name alongside instance names for cleanup

## Container Network Isolation

Test containers must run on an isolated network — never on the default bridge:

```bash
docker network create --driver bridge {project_name}-test-net
# ... run containers with --network {project_name}-test-net ...
# clean up immediately after
docker network rm {project_name}-test-net
```

Rules:
- Create a named network before the first test container starts; tear it down after the last container stops
- Never use `--network host` in tests — it exposes the container to the host network and other services
- Containers in the test network can communicate by service name; no host port mapping required for inter-container traffic
- Track the network name/ID alongside container IDs for cleanup

## Container / Instance Lifetime

Every container or Incus instance started by AI must have an explicit lifetime — never leave one running indefinitely:

- **Test containers / instances:** stop and remove immediately after the test completes (pass or fail)
- **Build containers:** `--rm --name {project_name}-XXXX` on all `docker run` invocations; self-remove on exit. `XXXX` is a random 8-char lowercase alphanumeric suffix (`$(tr -dc 'a-z0-9' </dev/urandom | head -c8)`) — the suffix prevents "container name already in use" collisions when multiple agents run concurrently, and the name makes targeted cleanup (`docker stop {project_name}-XXXX`) possible when a container hangs. Never launch an unnamed container — an anonymous `--rm` container that hangs can only be found by image-grepping `docker ps`.
- **Incus instances:** `incus launch {image} {project_name}-XXXX`; `incus delete --force {project_name}-XXXX` when done; same 8-char random suffix convention as Docker
- **Long-running service containers (integration tests):** set a `--stop-timeout` and enforce it; if a container has not exited within 60s of `docker stop`, force-kill with `docker kill`
- **`--rm` exception for multi-container/multi-instance integration testing:** `--rm` (Docker) is required on every build/one-off/unit-test container, no exception. It is optional only on a **detached** (`-d`/`--detach`) container that is part of a comprehensive integration test — e.g. a server container a client container or test suite talks to across several steps. A crashed `--rm` container is wiped before its logs/state can be inspected, which is what makes that kind of testing "impossible" with `--rm` forced; enforced by `enforce-docker-rm.sh`, which exempts `--rm` only when `-d`/`--detach` is present. `--name` stays mandatory in every case, exempt or not. Anything launched without `--rm` still must be torn down explicitly (`docker rm`/`docker rm -f`) once inspection is done, before the task ends — the exception drops the auto-remove flag, never the cleanup obligation. Incus instances are unaffected here: they were never required to pass an ephemeral (`--ephemeral`/`-e`) flag, so a persistent test instance already follows this same "keep it for inspection, delete it explicitly when done" pattern with no hook change needed.
- **No containers or instances survive a session end** — everything started during a session must be stopped before the session ends

If a container must remain running after the session (e.g. a dev environment started at user request), document its name/ID explicitly and tell the user — never leave one silently running.

## Scope

**This applies to everything:** build toolchains (`cargo`, `gradle`, `go build`), project binaries, `./scripts/`, `./tests/`, and system install scripts.

**Why:** install scripts modify OS config and install system services — running them on the host trashes the developer's machine.

**Scripts that seem to require host access** (`install-to-device.sh`, `dev-shell.sh`, some `./tests/*`): still check whether a VM or container can satisfy the requirement (USB passthrough, socket forwarding, Docker-in-Docker) before falling back to host.

---

## Project Toolchain Image

> **Go, Rust, and Android projects default to no `docker/Dockerfile.build`.** For Go use `casjaysdev/go:latest` directly; for Rust use `casjaysdev/rust:latest` directly; for Android use `casjaysdev/android:latest` directly. Exceptions: an image declared in IDEA.md/SPEC.md/AI.md wins; if `docker/Dockerfile.build` exists (genuine custom need, `FROM` the casjaysdev image), use its `:build` image like any other language.

For all other languages: before running any build, test, lint, or tool command, check whether the project has a `docker/Dockerfile.build`. If it does, the project ships a toolchain image tagged `{project_org}/{project_name}:build` (typically `ghcr.io/{org}/{name}:build`). Pull and run inside that image — never on the host, never in a generic `node:alpine` / `python:alpine` container. Generic alpine variants are only a fallback for projects without `docker/Dockerfile.build`.

If the image is not in the registry, do not build it inline — stop and tell the user to trigger `build-toolchain.yml` via `workflow_dispatch`.

**Bootstrap order** — when adding `docker/Dockerfile.build` to a non-Go/Rust/Android project: commit it alone first, trigger `build-toolchain.yml` via `workflow_dispatch`, verify the image is in the registry, then commit `ci.yml`/`release.yml`. Never commit a CI workflow that uses the build image before the image exists.

## Docker Run Conventions

- **`docker run` must use `--rm --name {project_name}-XXXX`** — every batch build/one-off/unit-test container must self-remove on exit AND carry a name for targeted cleanup. `XXXX` = random 8-char lowercase alphanumeric suffix (`$(tr -dc 'a-z0-9' </dev/urandom | head -c8)`; in Makefiles: `$$(tr -dc 'a-z0-9' </dev/urandom | head -c8)`). The random suffix makes concurrent runs collision-free, and `docker stop {project_name}-XXXX` / `docker ps --filter name={project_name}-` gives precise cleanup without broad sweeps. Never use `-it` for batch commands (breaks CI — no TTY); `-it` is only for interactive shells. **Exception:** a detached (`-d`/`--detach`) container in a multi-container integration test may omit `--rm` (see "Container / Instance Lifetime" above) — `--name` is still required.
- **Resource limits on all toolchain containers** — always pass `--memory=$(DOCKER_MEM) --cpus=$(DOCKER_CPUS)` where both vars default to `4g` and `2` respectively (overrideable per project or per machine). When many Claude Code instances each spawn multiple agents that each launch containers, the machine runs out of CPU/memory without per-container caps.
- **Go build cache must be project-scoped** — `GO_BUILD ?= $(HOME)/.cache/go-build/$(PROJECTNAME)`. The Go compile cache (`~/.cache/go-build`) is NOT safe for concurrent writes from separate `go` processes; a shared path across projects causes corruption and stalls. The module download cache (`GO_CACHE = ~/go/pkg/mod`) IS safe to share (Go uses file locking for writes). Rust's sccache and cargo registry are also safe to share; the Cargo target dir is NOT — scope it per project (`CARGO_TARGET ?= $(HOME)/.cache/cargo-target/$(PROJECTNAME)`).
- **Dev images: rolling tags** — never pinned
- **Target `linux/amd64` + `linux/arm64`** by default
- **Container startup chain: `tini → entrypoint.sh → app`** — never override or bypass; all startup customization goes in `entrypoint.sh`
- **Test container network isolation** — always create a named bridge network for tests; never use the default bridge or `--network host`
- **Toolchain containers must mount their package cache** — declare cache paths with `?=` so host env vars with custom locations are honored; `@mkdir -p $(CACHE_DIR)` before every `docker run`; see `makefile_conventions.md` for the full cache-mount table

## Port Binding

**Internal (container-to-container) ports — keep the standard port.** Services that are never exposed to the host (databases, caches, internal APIs, message queues) use their canonical port on the container network (`5432`, `3306`, `6379`, `5672`, etc.). No host binding, no random port.

**Exposed (host-facing) ports — always use a random port in the `62000`–`64999` range.** This applies to any service with a `ports:` mapping to the host: HTTP/HTTPS apps, reverse proxies, admin UIs, and any other endpoint a browser or external tool connects to directly.

- Bind to `172.17.0.1:{random_port}:{internal_port}` (Docker bridge gateway). Never `0.0.0.0`, `localhost`, or `127.0.0.x` — `0.0.0.0` exposes to all interfaces; `127.0.0.x` is host-only and excludes container-to-host reach.
- Pick the port at runtime using `__random_port`. When the port must survive between runs — save it to the project's config file on first generation and reload on subsequent runs. Use `__save_credential` / `__load_credential` for `KEY=VALUE` stores.

`docker-compose.yml` must work out of the box with zero configuration — every settable value has a sane default as a fallback so a missing or empty `.env` never breaks the stack. Users may override any value via `.env` or environment variables; if a value is unset or misconfigured the default takes over. Never require `.env` to exist, never fail silently on a bad value.

## Reverse Proxy

When a service needs a host-level nginx reverse proxy, generate the vhost at `/etc/nginx/vhosts.d/{hostname}.conf` following the template in `nginx_conventions.md`. TLS cert always at `/etc/letsencrypt/live/domain/` (literal `domain` directory).

## Temp Dirs

Never hardcode `/tmp`; use `$TMPDIR` / `os.TempDir()` / `std::env::temp_dir()`; always org-prefixed — see `tempdir_conventions.md`.

## Image Cleanup

Never remove base images (`golang`, `alpine`, `ubuntu`, etc.) — only `{project_org}/{internal_name}:*` images.
