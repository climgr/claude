---
name: CI/CD conventions
description: CI/CD rules for all supported providers — GitHub, GitLab, Gitea, Forgejo, Jenkins — including provider detection, workflow file locations, secret scanning, dependency updates, release integrity, and action pinning in CasjaysDev projects
type: user
---

## Multi-Provider CI/CD

Every project targets all five CI/CD providers. The goal is zero vendor lock-in: the same build, test, security, and release gates run correctly regardless of where the code is hosted.

**Exception — `script-collection` and `spec-collection` projects:** repos matching either project type (see `~/.claude/memory/project_type_conventions.md`) do not require CI/CD workflows by default; this entire file is skipped for them unless the user explicitly asks for an automated pipeline (e.g. a release/publish pipeline for scripts, or a link-checker/markdown-lint pipeline for specs). If one is added later, it must still follow this file's rules (SHA-pinned third-party actions, etc.).

### Philosophy

| Principle | Description |
|-----------|-------------|
| **Same gates, different syntax** | Build/test/security/release logic is identical across all providers; only the YAML dialect and runner format differ |
| **No lock-in** | A project that only works on GitHub is not portable — all five workflow formats must be present and passing |
| **Jenkinsfile is the escape hatch** | Jenkins runs anywhere, with or without a hosted CI provider; every project ships a `Jenkinsfile` |
| **Renovate only — never Dependabot** | Renovate (AGPL-3.0, free for self-hosted and public repos) works on all five providers with one config file. Dependabot is GitHub-only and creates duplicate PRs alongside Renovate. Do not add Dependabot to any project |

### Provider Detection

Detect the provider from the git remote URL. For self-hosted instances, fall back to the API version endpoint:

```bash
remote=$(git remote get-url origin 2>/dev/null || echo "")
case "$remote" in
  *github.com*)  PROVIDER=github ;;
  *gitlab.com* | *gitlab.*) PROVIDER=gitlab ;;
  *forgejo.*)    PROVIDER=forgejo ;;
  *gitea.*)      PROVIDER=gitea ;;
  *)
    # Self-hosted: probe the API version endpoint
    base=$(printf '%s' "$remote" | sed -E 's|git@([^:]+):.*|\1|; s|https?://([^/]+)/.*|\1|')
    if curl -qsSf "https://$base/api/v4/version" 2>/dev/null | grep -q '"version"'; then
      PROVIDER=gitlab
    elif curl -qsSf "https://$base/api/v1/version" 2>/dev/null | grep -qi "forgejo"; then
      PROVIDER=forgejo
    elif curl -qsSf "https://$base/api/v1/version" 2>/dev/null | grep -q '"version"'; then
      PROVIDER=gitea
    else
      PROVIDER=unknown
    fi
    ;;
esac
```

For Forgejo vs Gitea (both expose `/api/v1/version`): Forgejo sets an `X-Forgejo-Version` response header and the version string often contains `+gitea-` (e.g. `7.0.0+gitea-1.21.0`). Check the header first.

### Workflow File Locations

| Provider | Workflow location | Syntax / runner |
|----------|------------------|-----------------|
| GitHub | `.github/workflows/*.yml` | GitHub Actions |
| GitLab | `.gitlab-ci.yml` | GitLab CI |
| Gitea | `.gitea/workflows/*.yml` | GitHub Actions (act runner) |
| Forgejo | `.forgejo/workflows/*.yml` | GitHub Actions (act runner) |
| Jenkins | `Jenkinsfile` | Declarative Pipeline (Groovy) |

Gitea and Forgejo use the act runner — their workflow syntax is GitHub Actions-compatible. The same YAML (modulo registry/secret variable names) usually works on GitHub, Gitea, and Forgejo with no changes.

**Runner label exception:** GitHub workflows pin `runs-on: ubuntu-26.04` (the `ubuntu-latest` label moves from 24.04 to 26.04 between 2026-10-19 and 2026-11-19, so an unpinned label changes the image without any edit). Gitea and Forgejo runners match `runs-on` against labels registered on the instance, so the same value only schedules there if that label is registered; otherwise use the instance's own label (commonly `ubuntu-latest`, `docker`, or `native`) in `.gitea/workflows/` and `.forgejo/workflows/`.

### Required Workflow Set Per Provider

Every project must provide the equivalent of three gates on every provider:

| Gate | GitHub | GitLab | Gitea | Forgejo | Jenkins |
|------|--------|--------|-------|---------|---------|
| **Build + Test + Security** | `ci.yml` | `build` + `test` + `security` stages in `.gitlab-ci.yml` | `ci.yml` | `ci.yml` | `Build` + `Test` + `Security` stages in `Jenkinsfile` |
| **Release** | `release.yml` | `release` stage (manual/tag-triggered) | `release.yml` | `release.yml` | `Release` stage (tag-triggered) |
| **Toolchain** | `build-toolchain.yml` | Monthly pipeline schedule | `build-toolchain.yml` | `build-toolchain.yml` | Monthly cron trigger |

### Action / Step Pinning Per Provider

| Provider | Pinning requirement |
|----------|-------------------|
| GitHub | `uses: owner/action@{40-char-sha}` — never a tag or branch |
| GitLab | Docker images pinned by digest: `image: alpine@sha256:{digest}` for production; template `include:` refs pinned to SHA |
| Gitea | Same as GitHub (act runner uses the same `uses:` syntax) |
| Forgejo | Same as GitHub (act runner) |
| Jenkins | Docker images pinned by digest; shared library versions locked in `Jenkinsfile` |

### Secret Scanning Per Provider

truffleHog is the mandatory scanner on all providers (Apache-2.0, no license key, never gitleaks):

| Provider | How to run truffleHog |
|----------|----------------------|
| GitHub / Gitea / Forgejo | `trufflesecurity/trufflehog@{sha}` composite action |
| GitLab | Docker job: `image: trufflesecurity/trufflehog:latest`, `script: trufflehog git file://. --since-commit HEAD~1 --fail` |
| Jenkins | Docker step: `docker.image('trufflesecurity/trufflehog:latest').inside { sh 'trufflehog git file://. --since-commit HEAD~1 --fail' }` |

Always run with `fetch-depth: 0` (GitHub/Gitea/Forgejo) or `GIT_DEPTH: 0` (GitLab) so the full commit history is scanned.

**GitHub / Gitea / Forgejo composite action — required `with:` params:**

```yaml
- uses: trufflesecurity/trufflehog@{sha}
  with:
    base: ${{ github.event.before }}
    head: ${{ github.event.after }}
    extra_args: --only-verified
```

**Never use `base: ${{ github.event.repository.default_branch }}`** — after a push, `default_branch` resolves to the commit that was just pushed (same as HEAD), triggering truffleHog's "BASE and HEAD commits are the same" guard and skipping the scan entirely. Use `github.event.before` / `github.event.after` to pass the actual pre/post-push SHAs.

### Dependency Update Automation

**Renovate** is the only supported tool — AGPL-3.0 licensed, free for self-hosted use and free for public repos via the hosted app. It works on GitHub, GitLab, Gitea, Forgejo, and Bitbucket with a single `renovate.json` config file.

Do not use Dependabot. It is GitHub-only, duplicates Renovate's work on GitHub, and cannot serve the other four providers. Running both on the same repo produces duplicate update PRs.

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "packageRules": [
    {
      "matchManagers": ["github-actions"],
      "pinDigests": true,
      "automerge": false
    }
  ]
}
```

Place `renovate.json` at the repo root. Renovate updates GitHub Actions SHAs, Docker image digests, Go modules, Cargo deps, npm deps, and more — one tool, all providers.

### Container Registry Per Provider

See `~/.claude/memory/github_conventions.md` → "Container Registry" for the full table. Summary:

| Provider | Registry |
|----------|---------|
| GitHub | `ghcr.io/{org}/{name}` |
| GitLab | `registry.gitlab.com/{group}/{project}` |
| Gitea / Forgejo | `{instance}/{org}/{name}` (OCI registry built in) |
| Self-hosted | Any OCI-compliant registry — configure via `REGISTRY` make variable |

Base/toolchain images always pull from `docker.io` regardless of provider.

### GitLab CI Structure (`.gitlab-ci.yml`)

```yaml
stages:
  - build
  - test
  - security
  - release

variables:
  CGO_ENABLED: "0"
  # Build image — toolchain pre-installed; never install tools inline
  BUILD_IMAGE: $CI_REGISTRY_IMAGE:build

build:
  stage: build
  image: $BUILD_IMAGE
  script:
    - go build ./...

test:
  stage: test
  image: $BUILD_IMAGE
  script:
    - go test ./...

secret-scan:
  stage: security
  image: trufflesecurity/trufflehog:latest
  variables:
    GIT_DEPTH: 0
  script:
    - trufflehog git file://. --since-commit HEAD~1 --fail

vuln-scan:
  stage: security
  image: $BUILD_IMAGE
  script:
    - govulncheck ./...

release:
  stage: release
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - # build artifacts, checksums, SBOM, publish
```

Security jobs run in the same stage (parallel by default in GitLab CI).

`$CI_REGISTRY_IMAGE` resolves to the project's registry path automatically on any GitLab/Forgejo instance — no hardcoded org or project name.

### Jenkinsfile Structure

Every project ships a `Jenkinsfile` using the declarative pipeline syntax:

```groovy
pipeline {
    // Build image — toolchain pre-installed; resolve org/name from remote URL, no hardcoding
    agent {
        docker {
            image "${sh(script: "git remote get-url origin | sed -E 's|.*[:/]([^/]+)/([^/.]+)(\\.git)?|\\1/\\2|'", returnStdout: true).trim()}:build"
        }
    }

    options {
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        CGO_ENABLED = '0'
    }

    stages {
        stage('Build') {
            steps {
                sh 'go build ./...'
            }
        }
        stage('Test') {
            steps {
                sh 'go test ./...'
            }
        }
        stage('Security') {
            parallel {
                stage('Secret Scan') {
                    steps {
                        sh 'docker run --rm --name "trufflehog-$(tr -dc \'a-z0-9\' </dev/urandom | head -c8)" -v $PWD:/repo trufflesecurity/trufflehog:latest git file:///repo --since-commit HEAD~1 --fail'
                    }
                }
                stage('Vuln Scan') {
                    steps {
                        sh 'govulncheck ./...'
                    }
                }
            }
        }
        stage('Release') {
            when { tag 'v*' }
            steps {
                sh '# build artifacts, checksums, SBOM, publish'
            }
        }
    }
}
```

Language-specific: `casjaysdev/rust:latest` pre-installs `cargo-audit`, `cargo-deny`, etc. — swap `go build`/`go test`/`govulncheck` for `cargo build`/`cargo test`/`cargo audit`. Rust projects default to no `docker/Dockerfile.build` (see Toolchain Image section for the escape hatch). The agent image resolves dynamically from the git remote — no hardcoded org or project name.

---

## Provider CLI Tools

Prefer provider CLIs over raw `curl` calls for API operations. Fall back to `curl -q -LSsf` only when the CLI is not installed or the operation has no CLI equivalent.

| CLI | Provider | License | Install | Common use |
|-----|----------|---------|---------|------------|
| `gh` | GitHub | Apache-2.0 | `gh` from PATH | Issues, PRs, releases, repo settings, secret management |
| `glab` | GitLab | MIT | `glab` from PATH | MRs, issues, releases, CI status |
| `tea` | Gitea | MIT | `tea` from PATH | Issues, PRs, releases; also works against Forgejo (compatible API) |

**Rules:**
- Always check `command -v gh` / `command -v glab` / `command -v tea` before using — fall back to `curl` if not found
- Use `gh release create` / `glab release create` / `tea release create` for release publishing instead of raw API calls
- Use `gh secret set` / `glab variable set` for secret management — never echo secrets into a `curl -d` body
- `tea` serves both Gitea and Forgejo — the Forgejo API is compatible with the Gitea v1 API

---

## Local Workflow Testing (act)

`act` (nektos/act, MIT licensed, free) runs GitHub Actions workflows locally using Docker. Use it to verify workflow syntax and logic before pushing.

```bash
# Run the default event (push)
act

# Run a specific job
act -j build

# Run with a specific event
act pull_request

# List available jobs
act --list

# Use a specific platform image
act -P ubuntu-26.04=catthehacker/ubuntu:act-latest
```

**Rules:**
- Use `act` to catch syntax errors and logic bugs before they fail in CI
- `act` does not perfectly replicate GitHub-hosted runners — treat passing `act` as a sanity check, not a guarantee
- Never skip pushing to CI because `act` passed — always let the real CI run
- `act` is not available on GitLab, Gitea, or Forgejo — it is GitHub Actions-specific
- For GitLab CI, use `gitlab-runner exec docker {job}` for local testing
- For Gitea/Forgejo act runner, there is no standard local test tool — push to a test branch

---

## Toolchain Image (build-toolchain.yml)

> **Go, Rust, and Android projects default to NO `docker/Dockerfile.build` or `build-toolchain.yml`.** `casjaysdev/go:latest`, `casjaysdev/rust:latest`, and `casjaysdev/android:latest` are comprehensive maintained images — by default all Go, Rust, and Android CI jobs use `container: image: casjaysdev/go:latest` (or `casjaysdev/rust:latest` / `casjaysdev/android:latest`) directly, with no `ensure-build-image` gate and no `build-toolchain.yml`. Exceptions: (1) the project declares its own build image in IDEA.md/SPEC.md/AI.md — the declaration wins; (2) a genuine custom need the casjaysdev image cannot satisfy (proprietary SDK, vendor toolchain, exotic system libraries, exotic pinned NDK) — then `Dockerfile.build` MUST be `FROM` the matching casjaysdev image (extend, never replace) and the project follows the standard `build-toolchain.yml` + `ensure-build-image` pattern like any other language.

For all other languages (Node, Python, and any project with a custom toolchain need), every project maintains a `docker/Dockerfile.build` image tagged `{project_org}/{project_name}:build`. This image is built and pushed monthly so the toolchain stays current. It is the only image workflows use for build, test, lint, and security scan steps — no inline tool installation.

### Build image existence gate — required in every non-Go/Rust/Android workflow

**No workflow may proceed if the build image does not exist.** Every non-Go/Rust/Android workflow (`ci.yml`, `release.yml`) MUST start with an `ensure-build-image` job. All subsequent jobs `needs: ensure-build-image` and use `${{ needs.ensure-build-image.outputs.image }}` as their container.

`ensure-build-image` is **pull-only and fails fast** — it never builds the image inline. If the image is missing, the job fails immediately with a clear error and a zero-waste exit. Building the toolchain image inline wastes CI minutes on an uncontrolled build and masks the root cause (the image was never bootstrapped). The correct response to a missing image is to trigger `build-toolchain.yml` via `workflow_dispatch`.

**Bootstrap order** — when adding `docker/Dockerfile.build` to a project for the first time:
1. Commit only `docker/Dockerfile.build` (no CI workflows yet)
2. Trigger `build-toolchain.yml` via `workflow_dispatch` and verify the image appears in the registry
3. Only then commit `ci.yml` and `release.yml`

```yaml
jobs:
  ensure-build-image:
    runs-on: ubuntu-26.04
    permissions:
      packages: read
    outputs:
      image: ${{ steps.pull.outputs.image }}
    steps:
      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f  # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: pull
        name: Pull build image (fail fast if missing)
        run: |
          IMAGE="ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}:build"
          if ! docker pull "$IMAGE"; then
            echo "::error::Build image $IMAGE not found."
            echo "::error::Trigger the 'Build Toolchain Image' workflow (workflow_dispatch) to create it."
            echo "::error::Never commit ci.yml or release.yml before the build image exists in the registry."
            exit 1
          fi
          echo "image=$IMAGE" >> "$GITHUB_OUTPUT"

  build:
    needs: ensure-build-image
    runs-on: ubuntu-26.04
    container:
      image: ${{ needs.ensure-build-image.outputs.image }}
      options: "--user 0:0"
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - run: go build ./...
      # ... rest of build steps
```

Every job that uses the build image must follow this pattern:
- `needs: ensure-build-image`
- `container: image: ${{ needs.ensure-build-image.outputs.image }}`
- `options: "--user 0:0"` on the `container:` block — the runner (and actions/checkout's post-job cleanup) execs into the job container (e.g. `cat /etc/*release` OS diagnostics) as a user the image's `/etc/passwd` may not define, failing/flaking the job after all real work passed; numeric `0:0` needs no passwd lookup, so it is immune regardless of the image's user table. This applies to EVERY `container:` job (casjaysdev images included), not just `ensure-build-image` consumers

### Required workflow: `.github/workflows/build-toolchain.yml`

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

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-26.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1

      - uses: docker/setup-qemu-action@99012661954931238ded8c8b007157a8430204e1  # v4.4.0

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069  # v4.4.1

      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f  # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc  # v7.4.0
        with:
          context: .
          file: docker/Dockerfile.build
          platforms: linux/amd64,linux/arm64
          push: true
          provenance: false
          tags: ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}:build
```

- No hardcoded org or project name — `github.repository_owner` and `github.event.repository.name` resolve correctly after a fork
- `cancel-in-progress: false` — toolchain pushes must not be interrupted mid-push
- `linux/amd64,linux/arm64` always — the toolchain image must match the platforms the project targets
- `provenance: false` always — the default `provenance: true` injects an OCI attestation manifest that registries render as a spurious `unknown/unknown` platform entry alongside `linux/amd64`/`linux/arm64`; use `actions/attest-build-provenance` for release binary attestation instead

### Equivalent on other providers

| Provider | How |
|----------|-----|
| GitLab | Monthly pipeline schedule → job using `$CI_REGISTRY_IMAGE:build` target and `kaniko` or `docker:dind` |
| Gitea / Forgejo | Same GitHub Actions YAML with `${{ gitea.repository_owner }}` / `${{ gitea.event.repository.name }}` |
| Jenkins | Monthly cron trigger: `cron('0 4 1 * *')` → `docker.build("${org}/${name}:build", "-f docker/Dockerfile.build .")` then `docker.push()` |

---

## General Rules

| Rule | Description |
|------|-------------|
| **NEVER use Makefile in CI** | Workflows have explicit commands with all env vars |
| **Multi-platform parity** | All five providers must match — same platforms, same env vars, same logic |
| **VERSION precedence** | `release.txt` wins when present; otherwise use the workflow/build-specific fallback (tag, beta timestamp, etc.) |
| **LDFLAGS** | `-s -w -X 'main.Version=...' -X 'main.CommitID=...' -X 'main.BuildDate=...' -X 'main.OfficialSite=...'` |
| **Docker builds on every push** | Any branch push triggers Docker image build |
| **Docker tags** | Any push → `devel`, `{commit}`; beta → adds `beta`; tag → `{version}`, `latest`, `YYMM`, `{commit}` |
| **Workflow permissions** | Default to read-only / least privilege; grant write only to the specific release/publish job that needs it |
| **Use build image — never install tools inline** | Workflows pull `{project_org}/{project_name}:build` for all build/test/lint/scan steps. Never `apk add`, `apt-get`, `go install`, `cargo install`, or any inline tool install in a workflow step. All tooling lives in `docker/Dockerfile.build`, rebuilt monthly |
| **Workflow portability — no hardcoded values** | Org name, project name, registry, official site: never hardcoded. Use provider-supplied variables so the workflow works after a fork without edits. GitHub: `github.repository_owner` / `github.event.repository.name`. GitLab: `$CI_REGISTRY_IMAGE` / `$CI_PROJECT_NAMESPACE` / `$CI_PROJECT_NAME`. Jenkins: parse from `${env.GIT_URL}` |
| **Manual trigger on every workflow** | Every workflow must be runnable on demand, in addition to its normal trigger(s), so it can be re-run without a dummy commit. GitHub/Gitea/Forgejo: add `workflow_dispatch:` to every `on:` block (`ci.yml`, `release.yml` — with a tag input, `build-toolchain.yml` — already required). GitLab: pipelines are always manually runnable from the UI; add a `when: manual` rule only for a stage that should NOT run automatically. Jenkins: declarative pipelines are always manually triggerable ("Build with Parameters") — no extra config needed |

## Workflow Permissions

Set `contents: read` at the workflow level as the read-only baseline. Grant write permissions only on the specific job that performs the release or publish step — never workflow-wide.

| Permission | Scope | Why |
|------------|-------|-----|
| `contents: read` | All jobs (baseline) | Checkout |
| `contents: write` | Release job only | Create GitHub release, upload assets |
| `packages: write` | Release job only | Push images to `ghcr.io` |
| `id-token: write` | Release job only | OIDC token for Sigstore/cosign artifact signing |
| `attestations: write` | Release job only | GitHub artifact attestation (SBOM, provenance) |

```yaml
# Workflow-level: read-only baseline
permissions:
  contents: read

jobs:
  build:
    # Inherits read-only — no overrides needed
    runs-on: ubuntu-26.04
    ...

  release:
    needs: build
    permissions:
      # create GitHub release + upload assets
      contents: write
      # push to ghcr.io
      packages: write
      # OIDC token for cosign signing
      id-token: write
      # GitHub artifact attestations (SBOM, provenance)
      attestations: write
    ...
```

Third-party registry publishing uses repository secrets, not GitHub token permissions:
- npm → `NODE_AUTH_TOKEN` secret
- crates.io → `CARGO_REGISTRY_TOKEN` secret

---

## Workflow Job Ordering

GitHub Actions runs all jobs in parallel by default. Use `needs:` to enforce ordering when a job depends on another's output or must not run if a prior job failed.

### `ci.yml` job order

```
ensure-build-image
├── lint              (needs: ensure-build-image; skipped on schedule)
├── test              (needs: ensure-build-image; skipped on schedule)
├── secret-scan       (needs: ensure-build-image; always runs)
├── workflow-policy   (needs: ensure-build-image; always runs)
├── vuln-scan         (needs: ensure-build-image; conditional on manifest; always runs)
├── build             (needs: [lint, test]; skipped on schedule)
├── coverage          (needs: test; skipped on schedule)
├── image-scan        (needs: build; conditional on Dockerfile; skipped on schedule)
└── upload-artifacts  (needs: build; skipped on schedule)
```

`ci.yml` triggers on push to `main`, pull_request, a weekly schedule (`cron: '0 6 * * 1'`), and `workflow_dispatch` for manual re-runs. On the schedule event, `lint`, `test`, `build`, `coverage`, `image-scan`, and `upload-artifacts` skip via `if: github.event_name != 'schedule'` — only the security jobs (`secret-scan`, `workflow-policy`, `vuln-scan`) run. This ensures the security posture is checked weekly even without a code push. `workflow_dispatch` runs are treated like a push event (nothing skips) since they are an explicit manual request for a full run.

`ensure-build-image` always runs regardless of trigger — it is the gate for all other jobs. Security jobs (`secret-scan`, `workflow-policy`, `vuln-scan`) each independently `needs: ensure-build-image`, giving them parallelism among themselves while all depending on the gate. They do not depend on each other.

### `release.yml` job order

```
ensure-build-image ──→ build ──→ release (needs: build)
```

- `release` `needs: build` — never publish without a successful build + test
- `build` job uses read-only permissions; `release` job has elevated permissions scoped to it only
- `release.yml` always re-runs its own build inline — never relies on artifacts from a prior workflow run
- `release.yml` owns its own `ensure-build-image` job — it does not depend on `ci.yml`

### Docker image ordering

Standard multi-stage Dockerfiles (single `docker/build-push-action` step) need no special job ordering — BuildKit handles stage sequencing internally.

When a custom builder or base image is published separately and referenced by a downstream image:

```yaml
jobs:
  build-base:
    # Builds and pushes ghcr.io/{org}/{name}-builder:latest
    ...
  build-app:
    # app Dockerfile FROM references the builder image
    needs: build-base
    ...
```

### Cross-workflow ordering

GitHub Actions has no native cross-workflow `needs:`. Use branch protection instead:

- `ci.yml` runs on push/PR — branch protection requires it to pass before merge. Because `ci.yml` contains both build/test and security jobs in a single workflow with proper `needs:` ordering, there is no cross-workflow race: `ensure-build-image` gates everything, security jobs run in parallel after the gate, and `build` runs only after `lint` and `test` pass.
- `release.yml` triggers on tag — by the time a tag is cut, `ci.yml` has already passed on `main` (build + test + security all verified). `release.yml` is self-contained with its own `ensure-build-image` job.
- `build-toolchain.yml` runs on a monthly schedule — it is independent and does not interact with `ci.yml` or `release.yml` job ordering.
- Never use `workflow_run` to chain workflows — it is complex, fragile, and bypasses branch protection intent.

---

## Workflow Best Practices

### Concurrency groups

Every workflow that runs on push or pull_request must define a concurrency group to cancel stale runs:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Exception: `release.yml` must NOT cancel in progress — use `cancel-in-progress: false` to prevent a partial publish. `build-toolchain.yml` likewise uses `cancel-in-progress: false` — a toolchain push must not be interrupted mid-push.

### Caching

Cache language dependencies between runs. Add to every build job:

**Go:**
```yaml
- uses: actions/cache@{sha}
  with:
    path: |
      ~/.cache/go-build
      ~/go/pkg/mod
    key: go-${{ runner.os }}-${{ hashFiles('**/go.sum') }}
    restore-keys: go-${{ runner.os }}-
```

**Rust:**
```yaml
- uses: actions/cache@{sha}
  with:
    path: |
      ~/.cargo/registry
      ~/.cargo/git
      target/
    key: rust-${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}
    restore-keys: rust-${{ runner.os }}-
```

Always pin `actions/cache` to a full commit SHA per the third-party pinning rule.

### Artifact retention

Always set an explicit retention period on `actions/upload-artifact` — never rely on the 90-day default:

```yaml
- uses: actions/upload-artifact@{sha}
  with:
    name: binaries
    path: binaries/
    # build artifacts; use 30 for release staging
    retention-days: 7
```

Use 7 days for transient build artifacts; 30 days for release staging artifacts that may need re-download before a release is finalized.

### Coverage gates

`ci.yml` must enforce a minimum coverage threshold. The threshold is defined in `{project_dir}/IDEA.md` under `## Business logic`. If not specified, default is 60%. CI must fail when coverage drops below the threshold — a passing build with uncovered code is a silent regression.

**Go:** use `go test -cover -coverprofile="$COVDIR/coverage.out" ./...` then `go tool cover -func="$COVDIR/coverage.out"` to parse the total; fail if below threshold. Always follow the full tempdir convention: `mkdir -p "/tmp/{project_org}"` then `COVDIR=$(mktemp -d "/tmp/{project_org}/{internal_name}-XXXXXX")`. In a CI `container:` job write `COVDIR` to `$GITHUB_ENV` so subsequent steps can read it. In a Makefile `sh -c`, expand `$(PROJECTORG)` and `$(PROJECTNAME)` at Make-time.
**Rust:** use `cargo tarpaulin` or `cargo llvm-cov`; fail if below threshold.

## Security Requirements

| Rule | Description |
|------|-------------|
| **Third-party action pinning** | External actions MUST be pinned to a full commit SHA — never float on `@main`, `@master`, or broad tags; verify runtime and maintenance status on every SHA update |
| **No unsafe PR triggers** | Do NOT use `pull_request_target` for untrusted code execution, build, test, or artifact upload paths |
| **Secrets never exposed to forks** | Fork PR workflows run without repo secrets, write tokens, publish steps, or deployment credentials |
| **Secret scanning is mandatory** | Public repos run `truffleHog` on push/PR/schedule via `ci.yml`; findings are blockers, not warnings. Use `trufflesecurity/trufflehog` (Apache-2.0, no license key). Never use `gitleaks` — requires a commercial license for org repos |
| **Dependency updates are automated** | Public repos include dependency update automation for every ecosystem in use |
| **Vulnerability scanning is mandatory** | `ci.yml` MUST run the appropriate scanner(s) for every language in the repo; critical/high CVEs in direct deps are build blockers |

### Third-party Action Pinning

Every external action (`uses: owner/action@...`) MUST be pinned to a full commit SHA — never a mutable tag or branch:

```yaml
# Wrong — tag can silently change or be deleted
- uses: actions/checkout@v4

# Correct — SHA is immutable
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
```

**The trailing `# vX.Y.Z` version annotation is required and stays inline** — this is an explicit exception to the comments-above rule. Renovate reads and rewrites the same-line comment when bumping pins; moving it above the `uses:` line breaks that automation and loses the human-readable version at a glance.

**When updating a pinned SHA**, verify three things:

1. **Action is still maintained** — check the upstream repo is not archived, deprecated, or abandoned
2. **Runtime is still supported** — open the action's `action.yml` at the new SHA and check `runs.using`; if it names a runtime that GitHub has deprecated or scheduled for removal, the action will silently fail after that date. Example: `node20` is removed from GitHub-hosted runners on **2026-09-23** — any action still on `node20` must be updated to a SHA where it has migrated to `node24` (all common `actions/*` and `docker/*` actions have already done so; see the Common Action Reference SHAs table below)
3. **No supply-chain change** — skim the diff between the old and new SHA; unexpected new dependencies, changed entrypoints, or network calls added to setup steps are red flags

Renovate covers `github-actions` ecosystem updates automatically via `pinDigests: true` — but it only updates the SHA, not the runtime verification. The runtime check is always manual.

### Vulnerability scanning in `ci.yml`

The security jobs within `ci.yml` always run on push, pull_request, and the weekly schedule. Jobs are split into two tiers:

**Always-required jobs (every public repo, no conditions):**

| Job | Scanner | Notes |
|-----|---------|-------|
| `secret-scan` | truffleHog | `trufflesecurity/trufflehog@{sha}` — Apache-2.0, no license key; `fetch-depth: 0` required |
| `workflow-policy` | inline shell | Verifies all `uses:` lines are pinned to a 40-char SHA; blocks `pull_request_target` |

**Conditional jobs (only when the manifest file exists in the repo):**

| Job | Scanner | Condition | Command |
|-----|---------|-----------|---------|
| `vuln-scan` (Go) | govulncheck | `go.sum` present | `govulncheck ./...` |
| `vuln-scan` (Rust) | cargo audit | `Cargo.lock` present | `cargo audit` |
| `vuln-scan` (Node) | npm audit | `package-lock.json` present | `npm audit --audit-level=high` |
| `image-scan` | Trivy | Dockerfile present | See per-provider examples below |

A critical or high CVE in a direct dependency is a hard build failure — not a warning. The `image-scan` job requires the image to be built first; run it after `docker/build-push-action` in the same job or declare `needs: build`.

**Trivy invocation per provider** — always use the Docker image, never `wget` a release binary (versions disappear from releases):

```yaml
# GitHub / Gitea / Forgejo (Actions step)
- name: Scan image
  run: |
    docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      aquasec/trivy:0.70.0 image \
      --exit-code 1 --severity CRITICAL,HIGH {image}
```

```yaml
# GitLab CI job
image-scan:
  stage: security
  image: aquasec/trivy:0.70.0
  script:
    - trivy image --exit-code 1 --severity CRITICAL,HIGH {image}
```

```groovy
// Jenkins declarative pipeline step
docker.image('aquasec/trivy:0.70.0').inside('--entrypoint="" -v /var/run/docker.sock:/var/run/docker.sock') {
    sh 'trivy image --exit-code 1 --severity CRITICAL,HIGH {image}'
}
```

Current stable Trivy version: **0.70.0**. Update this when Renovate opens a digest bump PR for `aquasec/trivy`.

See `~/.claude/memory/security_conventions.md` for CVE database paths, pre-commit checks, and the full vulnerability scanning policy.

## Common Action Reference SHAs

Verified node24 SHAs as of 2026-10-06. All common `actions/*` and `docker/*` actions have migrated directly to node24 (skipping node22). Update these when Renovate opens a PR — always re-verify the runtime after updating.

| Action | Tag | SHA |
|--------|-----|-----|
| `trufflesecurity/trufflehog` | v3.99.0 | `b2b0a92070f206ab7b5a1105d82a7f2f48d92341` |
| `actions/checkout` | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/upload-artifact` | v7.0.1 | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/download-artifact` | v8.0.1 | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `actions/cache` | v6.1.0 | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `actions/setup-go` | v7.0.0 | `b7ad1dad31e06c5925ef5d2fc7ad053ef454303e` |
| `actions/setup-node` | v7.0.0 | `820762786026740c76f36085b0efc47a31fe5020` |
| `docker/login-action` | v4.6.0 | `dbcb813823bdd20940b903addbd779551569679f` |
| `docker/build-push-action` | v7.4.0 | `c3c9e263c25d99ce0380d002d59b67737d91b0dc` |
| `docker/metadata-action` | v6.2.0 | `dc802804100637a589fabce1cb79ff13a1411302` |
| `docker/setup-buildx-action` | v4.4.1 | `f87e5991a6d7451dcb8d9637bfbc97413f497069` |
| `docker/setup-qemu-action` | v4.4.0 | `99012661954931238ded8c8b007157a8430204e1` |
| `softprops/action-gh-release` | v3.0.3 | `efb35369e0ad2afab669f228072c1b0d510eae64` |

## Branch Protection (Public Repos)

The default branch MUST be protected. Required rules:

- Pull requests required for normal changes
- Passing build/test/security checks before merge
- CODEOWNERS review for owned paths
- Force-push and branch-deletion protection disabled

Direct pushes to the default branch are forbidden except explicit maintainer emergency action. Emergency bypasses MUST be followed by an audit/fix pass.

## Required Workflows (Public Repos)

| Workflow | Purpose |
|----------|---------|
| `.github/workflows/ci.yml` | Build, test, coverage, secret scan, vulnerability scan, and workflow policy — all push/PR work in dependency order |
| `.github/workflows/release.yml` | Tagged/manual release build and publish |
| `.github/workflows/build-toolchain.yml` | Monthly rebuild of the `:build` toolchain image |

All three workflows are required on every public repo regardless of language. `ci.yml` always contains at minimum `secret-scan` (truffleHog) and `workflow-policy` (action pinning check); dependency vulnerability jobs are added only when the corresponding manifest files exist.

If the project also supports Gitea/Forgejo or Jenkins, the equivalent workflows/pipelines MUST enforce the same gates — not a weaker subset. CI MUST fail when required tests, coverage gates, secret scans, dependency checks, or release validation fail.

## Dependency Update Automation (Public Repos)

All public repos MUST configure Renovate (`renovate.json` at repo root). Do not add Dependabot — it is GitHub-only and duplicates Renovate's work. See the "Dependency Update Automation" section above for the `renovate.json` template.

Renovate MUST cover at minimum: Go modules, GitHub Actions SHAs, Docker base image digests, Cargo deps, npm deps (whichever apply to the project).

Security updates are high priority and MUST go through the same test/security gates as manual changes. Never silently change dependency strategy, ignore failing update PRs, or disable update automation to "get green."

## Workflow Error Messaging

GitHub Actions surfaces failures in three ways — use the right one:

| Technique | When to use | Syntax |
|-----------|-------------|--------|
| `::error::` workflow command | Any pre-flight or validation failure — appears as a red annotation on the Actions summary page, not just in logs | `echo "::error::Tag 'foo' is not a valid tag"` |
| `::error file=...,line=N::` | When the failure is tied to a specific file (e.g., lint, format, policy check) | `echo "::error file=.github/workflows/release.yml,line=12::message"` |
| `echo "ERROR: ..." && exit 1` | Steps where the annotation is less important than a clear log line | Standard shell pattern |

Always write the message so a developer reading only the step name + message can understand what failed and what to do next — never output a bare non-zero exit with no explanation.

### Release pre-flight validation

The GitHub Releases API returns HTTP 422 with `"tag_name is not a valid tag"` when the tag does not exist in the repository at the time of the API call, or when the tag name is malformed. The correct fix is not to *validate* that the tag exists but for the **release job to own the tag** — delete it if it exists, then create it fresh. This ensures the tag always points to the correct commit and makes the workflow idempotent (re-runnable on failure).

The `release` job needs `contents: write` to push the tag — it already has this permission per the workflow permissions pattern.

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
  with:
    # required: full history needed to inspect and push tags
    fetch-depth: 0

- name: Ensure release tag
  run: |
    ref="${{ github.ref }}"
    # Must be triggered by a tag push or workflow_dispatch with a tag input
    if [[ "$ref" != refs/tags/* ]]; then
      echo "::error::release.yml triggered on non-tag ref '$ref'. Releases require a tag push (refs/tags/v...)."
      exit 1
    fi
    tag="${ref#refs/tags/}"
    # Reject malformed tag names before touching the remote
    if printf '%s' "$tag" | grep -qP '[[:space:][:cntrl:]]'; then
      echo "::error::Tag '$tag' contains whitespace or control characters and is not a valid GitHub tag name."
      exit 1
    fi
    # Delete existing tag (local + remote) then recreate at current HEAD
    git tag -d "$tag" 2>/dev/null || true
    git push origin ":refs/tags/$tag" 2>/dev/null || true
    git tag "$tag"
    git push origin "refs/tags/$tag"
    echo "Tag '$tag' ensured at $(git rev-parse HEAD)"
```

## Release Integrity

- Tagged releases MUST publish a machine-readable checksum file for all release artifacts (SHA-256)
- Tagged releases MUST publish release notes describing the actual change set with breaking changes called out explicitly
- Public releases MUST include a release-level SBOM (`CycloneDX` or `SPDX JSON`)
- Releases MUST include build provenance/attestation via `actions/attest-build-provenance` (stored in GitHub's attestation store, not embedded in the image manifest). All `docker/build-push-action` steps MUST set `provenance: false` — without it, Docker BuildKit injects an OCI attestation manifest that registries render as a spurious `unknown/unknown` platform entry
- AI MUST NOT fake signatures, fake attestations, or claim a release is signed/verified when the required keys/platform support do not exist
- If signing or attestation is required but the necessary keys/permissions are unavailable: stop and ask, do not bypass

## Pre-Commit Workflow Gate

If `.github/workflows/` files are staged, `act --list -W {file}` must pass on each before `gitcommit`. Third-party Actions must be pinned to a full commit SHA — never a tag (see Third-Party Action Pinning above for the 3-point verification on every SHA update).

`act --list` and a local `make test` pass only prove the workflow's syntax/job graph is valid and the code works in the local environment — they are not the real CI build. The real build runs on the provider's infrastructure with real secrets, real matrix jobs, and the real `:build` toolchain image; any of those can fail even when every local check passed.

## Post-Push CI Verification

Every push — a normal feature-branch push or an emergency direct push to the default branch (see Branch Protection above) — triggers a real CI run if the project has workflows. That run is ground truth and MUST be checked; treating "local checks passed" as equivalent to "the build is green" is itself a bug.

**After every `gitcommit --dir {dir} all` push**, if the project has CI config (`.github/workflows/`, `.gitlab-ci.yml`, `.gitea/workflows/`, `.forgejo/workflows/`, `Jenkinsfile`):

1. Resolve the provider (see Provider Detection above) and the pushed commit SHA
2. Check the triggered run's status:
   - **GitHub**: `gh run list --branch {branch} --commit {sha} --limit 1` then `gh run watch {run-id}` (or `gh run view {run-id} --json status,conclusion`)
   - **GitLab**: `curl -qsSf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" ".../repository/commits/{sha}/statuses"`
   - **Gitea / Forgejo**: `curl -qsSf -H "Authorization: token $TOKEN" ".../commits/{sha}/status"`
   - **Jenkins**: poll the job's `lastBuild/api/json` for `result`
3. **Build failed** → this is a bug, not a note for later. Diagnose the root cause (missing env var, toolchain drift, flaky test, secret unavailable in CI, platform-specific failure) and fix it with a normal follow-up `gitcommit` — never leave the default branch red
4. **Build pending/running** → the task is not done yet; wait and re-check rather than reporting success
5. **No CI config in the project** → this step is a no-op

## Workflow Creation Order

Not all workflow files carry the same risk — create them in this order:

1. **Security-only workflows** (secret scan, SHA/digest policy, dependency audit) — no build dependency; safe to add anytime
2. **`build-toolchain.yml`** (`:build` image) — **only if the project has a `docker/Dockerfile.build`**. Add once it builds successfully locally. Skip for projects that use a standard maintained image and have no `docker/Dockerfile.build`
3. **`ci.yml` and `release.yml`** — add **last**, only after all code is complete, `make test` passes, and the lint gate is clean; these trigger a full build on push and will fail immediately if the code is not ready
