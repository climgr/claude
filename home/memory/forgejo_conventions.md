---
name: Forgejo conventions
description: Forgejo-specific conventions for CasjaysDev projects — .forgejo/workflows/ patterns, act runner, predefined variables, package registry, federation, branch protection, and self-hosted setup. Load only when the project remote resolves to a Forgejo instance.
type: user
---

## When to Load

Load this file when the response to `GET {host}/api/v1/version` includes an `X-Forgejo-Version` response header, OR when the version string contains `+gitea-` (e.g. `7.0.0+gitea-1.21.0`). Either signal confirms Forgejo — use `X-Forgejo-Version` as the primary signal since it is set on all Forgejo releases.

---

## Workflow Location

Forgejo uses the Forgejo runner (compatible with act runner). Workflow files live at:

```
.forgejo/workflows/ci.yml
.forgejo/workflows/release.yml
.forgejo/workflows/build-toolchain.yml
```

Syntax is GitHub Actions-compatible. Files in `.forgejo/workflows/` take precedence over `.gitea/workflows/` on Forgejo instances.

---

## Predefined Variables

Forgejo exposes both `forgejo.*` and `github.*` namespaces in workflows. Use `forgejo.*` for clarity on Forgejo-specific deployments:

| Variable | Value |
|----------|-------|
| `${{ forgejo.sha }}` | Full commit SHA |
| `${{ forgejo.ref }}` | Full ref (`refs/heads/main`, `refs/tags/v1.0.0`) |
| `${{ forgejo.ref_name }}` | Short branch or tag name |
| `${{ forgejo.repository }}` | `{owner}/{repo}` |
| `${{ forgejo.repository_owner }}` | Owner login |
| `${{ forgejo.server_url }}` | Instance URL (e.g. `https://codeberg.org`) |
| `${{ forgejo.token }}` | Short-lived job token |
| `${{ forgejo.actor }}` | Username who triggered the workflow |
| `${{ forgejo.event_name }}` | `push`, `pull_request`, `schedule`, `workflow_dispatch` |
| `${{ forgejo.workspace }}` | Runner workspace path |

`github.*` aliases work identically — use `forgejo.*` to make provider intent explicit.

---

## Build Image Gate (`ensure-build-image`)

> **Go, Rust, and Android projects default to no `ensure-build-image` and no `build-toolchain.yml`.** Go CI jobs use `container: image: casjaysdev/go:latest` directly; Rust CI jobs use `container: image: casjaysdev/rust:latest` directly; Android CI jobs use `container: image: casjaysdev/android:latest` directly. Exception: a project-declared build image or a genuine custom need (`docker/Dockerfile.build` `FROM` the casjaysdev image) follows the standard toolchain pattern like any other language.

For all other languages: every workflow in `.forgejo/workflows/` must start with an `ensure-build-image` job that confirms `{project_org}/{project_name}:build` exists in the Forgejo package registry and builds + pushes it from `docker/Dockerfile.build` if missing. All other jobs `needs: ensure-build-image` and run inside `${{ needs.ensure-build-image.outputs.image }}`.

A separate scheduled workflow at `.forgejo/workflows/build-toolchain.yml` rebuilds the `:build` image monthly so the toolchain stays current — analogous to the GitHub `build-toolchain.yml` documented in `cicd_conventions.md`. Push it to the Forgejo registry using `${{ secrets.FORGEJO_TOKEN }}` as the registry password.

OCI annotations on every image pushed by these workflows: `org.opencontainers.image.source`, `org.opencontainers.image.revision`, `org.opencontainers.image.created`, `org.opencontainers.image.licenses` — populate from `${{ forgejo.repository }}`, `${{ forgejo.sha }}`, build timestamp, and the project license.

**Never install tooling inline** — no `apk add`, `go install`, `cargo install`, or `npm install -g` in a workflow step. All tools live in the `:build` image (or the maintained language image for Go/Rust/Android).

---

## Workflow Skeleton

```yaml
name: CI

on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]

jobs:
  build:
    runs-on: docker
    container:
      # Go projects always use this directly — never golang:alpine
      image: casjaysdev/go:latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - name: Build
        run: go build ./...
```

Forgejo runner labels differ from GitHub-hosted runners. Common self-hosted labels: `docker`, `ubuntu-latest`, `native`. Check the instance's runner configuration — do not assume `ubuntu-latest` is available on every Forgejo deployment.

**SHA pinning:** Pin actions to a full commit SHA:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
```

Forgejo instances may mirror `actions/` from Codeberg, Forgejo's own action cache, or a configured upstream. Confirm with the instance admin which action mirror is in use. Tags are mutable regardless of source — always pin to the SHA.

---

## Secret Scanning (truffleHog)

Use the `trufflesecurity/trufflehog@{sha}` composite action — never `apk add` + `docker run` inline. For Go/Rust/Android projects use the maintained image directly; for other languages use the `:build` toolchain image via `ensure-build-image`.

```yaml
# Go/Rust/Android: use maintained image directly — no ensure-build-image
secret-scan:
  runs-on: docker
  container:
    # or casjaysdev/rust:latest
    image: casjaysdev/go:latest
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      with:
        fetch-depth: 0
    - uses: trufflesecurity/trufflehog@{sha}
      with:
        base: ${{ forgejo.event.before }}
        head: ${{ forgejo.event.after }}
        extra_args: --only-verified

# Other languages: gate on ensure-build-image
secret-scan:
  needs: ensure-build-image
  runs-on: docker
  container:
    image: ${{ needs.ensure-build-image.outputs.image }}
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      with:
        fetch-depth: 0
    - uses: trufflesecurity/trufflehog@{sha}
      with:
        base: ${{ forgejo.event.before }}
        head: ${{ forgejo.event.after }}
        extra_args: --only-verified
```

truffleHog is Apache-2.0 — no license key required. Never substitute gitleaks (commercial license for org repos).

---

## Package Registry

Forgejo has a built-in package registry supporting Docker, Go modules, npm, PyPI, Cargo, Helm, and more — same API surface as Gitea.

**Docker registry:**

```
{forgejo_host}/{owner}/{repo}:{tag}
```

Login:

```bash
docker login {forgejo_host} -u {username} -p {token}
```

In CI:

```yaml
- name: Login to Forgejo registry
  run: |
    docker login "${{ forgejo.server_url }}" \
      -u "${{ forgejo.repository_owner }}" \
      -p "${{ secrets.FORGEJO_TOKEN }}"
- name: Build and push
  run: |
    IMAGE="${{ forgejo.server_url }}/${{ forgejo.repository }}:${{ forgejo.sha }}"
    docker build -t "$IMAGE" .
    docker push "$IMAGE"
```

**Go module proxy:** `{host}/api/packages/{owner}/go` — same as Gitea.

---

## Federation (Forgejo-specific)

Forgejo 7.0+ supports ActivityPub federation for repositories. This enables following repos across instances and mirroring stars/forks. No workflow changes are needed — federation is instance-level configuration. Relevant only when coordinating cross-instance contribution or visibility.

---

## Branch Protection

Via Forgejo API (v1, identical to Gitea API):

```bash
curl -qsSf -X POST \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  "{host}/api/v1/repos/{owner}/{repo}/branches/main/protection" \
  -d '{
    "branch_name": "main",
    "enable_push": false,
    "enable_status_check": true,
    "status_check_contexts": ["build", "security"],
    "required_approvals": 1,
    "dismiss_stale_approvals": true,
    "block_on_outdated_branch": true
  }'
```

---

## Pull Request Templates

Location: `.forgejo/PULL_REQUEST_TEMPLATE.md` (preferred on Forgejo) or `.gitea/PULL_REQUEST_TEMPLATE.md` (fallback):

```markdown
## Summary

<!-- What does this PR do? Link the issue it closes: Closes #N -->

## Changes

-

## Testing

<!-- How was this tested? Were tests added or updated? -->

## Checklist

- [ ] Tests added/updated
- [ ] Tests pass locally inside the `:build` toolchain image
- [ ] No TODO/FIXME left in committed code
- [ ] SECURITY.md updated if this change is security-relevant
```

---

## CODEOWNERS

Location: `CODEOWNERS` (repo root):

```
* @{project_org}
.forgejo/workflows/ @{project_org}
SECURITY.md @{project_org}
docker/ @{project_org}
```

---

## Release

Forgejo uses the same Releases API as Gitea (v1):

```bash
curl -qsSf -X POST \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  "{host}/api/v1/repos/{owner}/{repo}/releases" \
  -d "{
    \"tag_name\": \"$TAG\",
    \"name\": \"$TAG\",
    \"body\": \"Release $TAG\",
    \"draft\": false,
    \"prerelease\": false
  }"
```

In workflow:

```yaml
release:
  runs-on: docker
  if: startsWith(forgejo.ref, 'refs/tags/v')
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
    - name: Validate tag
      run: |
        tag="${{ forgejo.ref_name }}"
        if ! printf '%s' "$tag" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+'; then
          echo "::error::Tag '$tag' is not a valid semver tag (expected vX.Y.Z)"
          exit 1
        fi
    - name: Build release binaries
      run: go build -o "binaries/${{ forgejo.event.repository.name }}-${{ forgejo.ref_name }}" ./...
    - name: Create Forgejo release
      env:
        FORGEJO_TOKEN: ${{ secrets.FORGEJO_TOKEN }}
      run: |
        tag="${{ forgejo.ref_name }}"
        curl -qsSf -X POST \
          -H "Authorization: token $FORGEJO_TOKEN" \
          -H "Content-Type: application/json" \
          "${{ forgejo.server_url }}/api/v1/repos/${{ forgejo.repository }}/releases" \
          -d "{\"tag_name\":\"$tag\",\"name\":\"$tag\",\"body\":\"Release $tag\"}"
```

---

## Dependency Updates (Renovate)

Forgejo supports Renovate. Run as a scheduled workflow:

```yaml
renovate:
  runs-on: docker
  container:
    image: renovate/renovate:latest
  if: forgejo.event_name == 'schedule'
  steps:
    - name: Self-hosted Renovate
      env:
        RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN }}
        RENOVATE_PLATFORM: gitea
        RENOVATE_ENDPOINT: ${{ forgejo.server_url }}
        RENOVATE_REPOSITORIES: ${{ forgejo.repository }}
      run: renovate
```

Renovate uses `platform: gitea` for Forgejo — the API is compatible. `renovate.json` at repo root:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:base"],
  "platform": "gitea",
  "gitAuthor": "Renovate Bot <renovate@example.com>",
  "prCreation": "immediate",
  "automerge": false
}
```

---

## Self-Hosted Forgejo Notes

- **Version detection:** `GET /api/v1/version` response header `X-Forgejo-Version: {version}` — presence of this header = Forgejo. Version string `7.x.x+gitea-1.21.x` is a secondary indicator.
- **Runner registration:** `forgejo-runner register --instance {url} --token {token}` — or use the act runner binary (`act_runner`) which is also compatible
- **Runner labels:** configure labels in `config.yml`; common: `docker`, `native`, `ubuntu-latest` (if using an ubuntu-based runner image)
- **Action cache:** Forgejo can serve as its own action cache at `{host}/_gitea/actions/` — configure in `app.ini` under `[actions]`
- **Codeberg:** `codeberg.org` is a public Forgejo instance — same API, same workflow syntax; `X-Forgejo-Version` header is present
- **Webhook secret:** verify `X-Forgejo-Signature` header (HMAC-SHA256) on incoming webhooks — same signature format as Gitea
- **SSH push secrets:** Forgejo supports `FORGEJO_TOKEN` for API access; for CI push-back (e.g. bumping version files), use a deploy key scoped to the specific repo rather than a personal token
