---
name: GitLab conventions
description: GitLab-specific conventions for CasjaysDev projects — .gitlab-ci.yml patterns, predefined variables, MR templates, registry auth, branch protection, and self-hosted setup. Load only when the project remote is a GitLab instance.
type: user
---

## When to Load

Load this file when `git remote get-url origin` contains `gitlab.com` or resolves to a GitLab instance (API probe: `GET /api/v4/version` returns `{"version":"..."}`).

---

## `.gitlab-ci.yml` Structure

GitLab CI uses stages. Jobs in the same stage run in parallel; stages run sequentially.

```yaml
stages:
  - lint
  - security
  - build
  - test
  - package
  - release
  - docker

variables:
  CGO_ENABLED: "0"
  DOCKER_DRIVER: overlay2
  # Go/Rust/Android projects: BUILD_IMAGE is casjaysdev/go:latest, casjaysdev/rust:latest, or casjaysdev/android:latest (no Dockerfile.build)
  # Other languages: BUILD_IMAGE is $CI_REGISTRY_IMAGE:build (from docker/Dockerfile.build)
  BUILD_IMAGE: "$CI_REGISTRY_IMAGE:build"

default:
  # Go/Rust/Android: use the matching casjaysdev image directly; others: toolchain image baked from docker/Dockerfile.build
  image: $BUILD_IMAGE
```

> **Go, Rust, and Android projects default to no `docker/Dockerfile.build` or `build-toolchain` pipeline.** For Go set `BUILD_IMAGE: casjaysdev/go:latest`; for Rust set `BUILD_IMAGE: casjaysdev/rust:latest`; for Android set `BUILD_IMAGE: casjaysdev/android:latest`. No `ensure-build-image` gate. Exception: a project-declared build image or a genuine custom need (`Dockerfile.build` `FROM` the casjaysdev image) follows the standard toolchain pattern like any other language.

**Toolchain image gate (`ensure-build-image`):** for all non-Go/Rust/Android projects, every pipeline must begin with a job that confirms `$BUILD_IMAGE` exists in the registry and builds + pushes it from `docker/Dockerfile.build` if missing — analogous to the GitHub Actions `ensure-build-image` job in `cicd_conventions.md`. Subsequent jobs `needs: [ensure-build-image]` and run inside `$BUILD_IMAGE`. **Never `apk add` / `go install` / `cargo install` inline** — all tooling lives in the build image, rebuilt monthly via the equivalent `build-toolchain` scheduled pipeline.

**Trigger rules:**
- Branch pushes: `rules: - if: $CI_COMMIT_BRANCH`
- Tag releases: `rules: - if: $CI_COMMIT_TAG =~ /^v/`
- MRs: `rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"`

Never use `only:` / `except:` — they are deprecated. Always use `rules:`.

---

## Predefined Variables (Key Ones)

| Variable | Value |
|----------|-------|
| `$CI_COMMIT_SHA` | Full 40-char commit SHA |
| `$CI_COMMIT_SHORT_SHA` | 8-char short SHA — GitLab hardcodes 8; use `${CI_COMMIT_SHA:0:7}` instead to match the 7-char short-SHA standard used everywhere else |
| `$CI_COMMIT_TAG` | Tag name (set only on tag pipelines) |
| `$CI_COMMIT_BRANCH` | Branch name (unset on tag pipelines) |
| `$CI_DEFAULT_BRANCH` | Default branch (`main`) |
| `$CI_REGISTRY` | `registry.gitlab.com` (or self-hosted equivalent) |
| `$CI_REGISTRY_IMAGE` | `registry.gitlab.com/{group}/{project}` |
| `$CI_REGISTRY_USER` | Token username for registry login |
| `$CI_REGISTRY_PASSWORD` | Token password for registry login |
| `$CI_JOB_TOKEN` | Short-lived token for API/registry access within the job |
| `$CI_PROJECT_ID` | Numeric project ID |
| `$CI_PROJECT_PATH` | `{group}/{project}` |
| `$CI_PIPELINE_SOURCE` | `push`, `merge_request_event`, `schedule`, `web`, `trigger` |
| `$GITLAB_USER_LOGIN` | Username of the user who triggered the pipeline |

---

## Container Registry

```yaml
build-image:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  variables:
    SHORT_SHA: ${CI_COMMIT_SHA:0:7}
  script:
    - docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" "$CI_REGISTRY"
    - docker build -t "$CI_REGISTRY_IMAGE:$SHORT_SHA" .
    - docker push "$CI_REGISTRY_IMAGE:$SHORT_SHA"
```

**Tag matrix on release:**
```yaml
release-image:
  stage: release
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  variables:
    SHORT_SHA: ${CI_COMMIT_SHA:0:7}
  script:
    - docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" "$CI_REGISTRY"
    - docker pull "$CI_REGISTRY_IMAGE:$SHORT_SHA"
    - docker tag "$CI_REGISTRY_IMAGE:$SHORT_SHA" "$CI_REGISTRY_IMAGE:$CI_COMMIT_TAG"
    - docker tag "$CI_REGISTRY_IMAGE:$SHORT_SHA" "$CI_REGISTRY_IMAGE:latest"
    - docker push "$CI_REGISTRY_IMAGE:$CI_COMMIT_TAG"
    - docker push "$CI_REGISTRY_IMAGE:latest"
```

Use `$SHORT_SHA` (7 chars, matches the standard used in Makefiles/GitHub Actions), never the raw `$CI_COMMIT_SHORT_SHA` (GitLab hardcodes 8).

Never hardcode the registry URL — always use `$CI_REGISTRY` and `$CI_REGISTRY_IMAGE`.

**Generated text is fully expanded:** GitLab keywords outside `script:` (`release:` name, description and assets, `artifacts:paths`) expand only `$VAR` / `${VAR}`, never `${VAR:0:7}` or `${VAR#v}`. Compute the value in an upstream job and pass it with a dotenv report (for the rolling devel release: `echo "RELEASE_VERSION=${COMMIT_ID}" > release.env` with `artifacts: reports: dotenv: release.env`, then `name: "Devel Build ${RELEASE_VERSION}"`). The `:devel` image job and the devel release run only on `$CI_COMMIT_BRANCH == "main" || $CI_COMMIT_BRANCH == "master"` plus the daily schedule; there is no `devel`/`dev` branch.

---

## Security Stage

```yaml
secret-scan:
  stage: security
  image: trufflesecurity/trufflehog:latest
  variables:
    # full history required
    GIT_DEPTH: 0
  script:
    - trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --exclude-paths=.github/trufflehog-exclude.txt --fail
  rules:
    - if: $CI_COMMIT_BRANCH
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

vuln-scan:
  stage: security
  # govulncheck/cargo-audit/npm audit pre-installed in the build image
  image: $BUILD_IMAGE
  script:
    - govulncheck ./...
  rules:
    - if: $CI_COMMIT_BRANCH
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - exists:
        - go.sum

policy-check:
  stage: security
  image: alpine:latest
  script:
    - |
      fail=0
      # Verify no Docker image references are floating (no digest pinning check — add if images are pinned)
      if grep -rE 'image:\s+\S+:latest' .gitlab-ci.yml 2>/dev/null | grep -v '#'; then
        echo "ERROR: ':latest' tag in production CI image reference — pin to a specific version or digest"
        fail=1
      fi
      if grep -rE '\$CI_JOB_TOKEN' .gitlab-ci.yml 2>/dev/null | grep -i 'write\|push\|deploy'; then
        echo "ERROR: CI_JOB_TOKEN with write access detected — review fork MR security"
        fail=1
      fi
      exit $fail
  rules:
    - if: $CI_COMMIT_BRANCH
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

Range scans block on `verified` and `unknown`; a full-history scan (schedule) uses `--results=verified` instead. See `cicd_conventions.md` "Secret Scanning Per Provider" for the exclude file and allowlist rules.

**Security rules specific to GitLab:**
- Never use `CI_JOB_TOKEN` with write access (registry push, API write) in pipelines triggered by fork MRs
- Use `rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"` not `pull_request_target` equivalent
- Image pinning: prefer `image: alpine:3.21` over `image: alpine:latest` in production jobs; pin by digest for highest assurance

---

## MR Templates

Location: `.gitlab/merge_request_templates/Default.md`

```markdown
## Summary

<!-- What does this MR do? Link the issue it closes: Closes #N -->

## Changes

-

## Testing

<!-- How was this tested? Were tests added or updated? -->

## Checklist

- [ ] Tests added/updated
- [ ] `make test` passes locally
- [ ] No TODO/FIXME left in committed code
- [ ] SECURITY.md updated if this change is security-relevant
```

---

## CODEOWNERS

GitLab CODEOWNERS lives at the **repo root** (not `.github/`): `CODEOWNERS`

```
# Global owners
* @{project_org}

# CI/CD changes require maintainer review
.gitlab-ci.yml @{project_org}
.gitlab/ @{project_org}

# Security-sensitive files
SECURITY.md @{project_org}
docker/ @{project_org}
```

Enable in **Settings → Repository → Protected branches → Code owner approval**.

---

## Branch Protection

Apply via GitLab API or UI. Equivalent to GitHub's branch protection:

```bash
# Protect main branch — requires MR + passing CI
curl -qsSf -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/{id}/protected_branches" \
  -d "name=main&push_access_level=0&merge_access_level=40&allow_force_push=false&code_owner_approval_required=true"
```

Access levels: `0`=No one, `30`=Developer, `40`=Maintainer, `60`=Admin.

Required status checks are enforced via **Settings → General → Merge requests → Pipelines must succeed**.

---

## Release (Semantic Release / Manual Tag)

```yaml
release:
  stage: release
  image: alpine:latest
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - |
      tag="$CI_COMMIT_TAG"
      # Validate tag format
      if ! printf '%s' "$tag" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]'; then
        echo "ERROR: Tag '$tag' is not a valid semver tag (expected vX.Y.Z)"
        exit 1
      fi
      # Build, checksum, SBOM, publish steps here
```

GitLab has a native Releases API — use it instead of a third-party action:

```bash
curl -qsSf -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/$CI_PROJECT_ID/releases" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$CI_COMMIT_TAG\",\"tag_name\":\"$CI_COMMIT_TAG\",\"description\":\"Release $CI_COMMIT_TAG\"}"
```

---

## Dependency Updates (Renovate)

GitLab supports Renovate bot natively. `renovate.json` at repo root; enable the Renovate GitLab app or self-host `renovate` as a scheduled CI job:

```yaml
renovate:
  image: renovate/renovate:latest
  stage: build
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
  variables:
    RENOVATE_TOKEN: $RENOVATE_TOKEN
    RENOVATE_PLATFORM: gitlab
    RENOVATE_ENDPOINT: https://gitlab.com/api/v4
    RENOVATE_REPOSITORIES: $CI_PROJECT_PATH
  script:
    - renovate
```

---

## Self-Hosted GitLab Notes

- Registry URL: `registry.{your-domain}` — expose via `$CI_REGISTRY` automatically
- GitLab Runner: register with `gitlab-runner register` — use Docker executor for container-based jobs
- OIDC / Workload Identity: available in GitLab 17+ — use instead of long-lived tokens where supported
- Instance-level variables set in **Admin → CI/CD → Variables** are available to all projects
