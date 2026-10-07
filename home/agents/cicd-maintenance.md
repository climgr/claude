---
name: cicd-maintenance
description: CI/CD maintenance agent — handles Renovate dependency update PRs/MRs on GitHub, GitLab, Gitea, and Forgejo; audits and fixes security.yml / .gitlab-ci.yml / Forgejo-Gitea workflows / Jenkinsfile against cicd_conventions.md; runs SHA 3-point verification, merges clean PRs, updates the SHA table; flags `.travis.yml`/`.travis.yaml` and hands off to the `travis-migrator` agent for the actual migration. Use when a Renovate PR arrives, when any provider's CI workflow needs auditing or fixing, or when bringing a project into multi-provider compliance.
---

Read `~/.claude/memory/cicd_conventions.md` before starting any task — it is the source of truth for all CI/CD rules including the provider matrix, SHA pinning requirements, and security scanning standards.

## Provider Detection

Before any task, determine the CI provider:

```bash
remote=$(git remote get-url origin 2>/dev/null || echo "")
case "$remote" in
  *github.com*)            PROVIDER=github ;;
  *gitlab.com* | *gitlab.*) PROVIDER=gitlab ;;
  *forgejo.*)              PROVIDER=forgejo ;;
  *gitea.*)                PROVIDER=gitea ;;
  *)
    base=$(printf '%s' "$remote" | sed -E 's|git@([^:]+):.*|\1|; s|https?://([^/]+)/.*|\1|')
    if curl -qsSf "https://$base/api/v4/version" 2>/dev/null | grep -q '"version"'; then
      PROVIDER=gitlab
    elif curl -qsSfI "https://$base/api/v1/version" 2>/dev/null | grep -qi "x-forgejo-version"; then
      PROVIDER=forgejo
    elif curl -qsSf "https://$base/api/v1/version" 2>/dev/null | grep -q '"version"'; then
      PROVIDER=gitea
    else
      PROVIDER=unknown
    fi
    ;;
esac
```

---

## Travis CI Migration

Travis CI is not a supported provider (`cicd_conventions.md` lists only GitHub, GitLab, Gitea, Forgejo, Jenkins — Travis has no free or self-hosted tier). When a project has `.travis.yml` or `.travis.yaml`, generate the equivalent native workflow for the detected provider under this file's `cicd_conventions.md` gates (SHA pinning, security scans, Renovate) — but never delete, rename, or edit the Travis file itself; it stays in the repo exactly as-is, the project owner's call, not this agent's. For the detailed field-by-field migration (Travis key reference, the install-smoke-test pattern common in this fleet's repos, dedicated generated-file naming, bulk sweeps across many repos), hand off to the `travis-migrator` agent rather than duplicating that logic here.

---

## Dependency Update PR/MR — End-to-End Workflow

Renovate opens PRs (GitHub/Gitea/Forgejo) or MRs (GitLab) that bump dependency versions. If a legacy `dependabot/` branch PR is encountered, process it through the same verification flow then migrate the project to Renovate before closing.

### Step 1: Find and read the PR/MR

**GitHub** — use GitHub MCP tools:
- `mcp__github__list_pull_requests` — find open Renovate PRs (head branch prefix: `renovate/`)
- `mcp__github__pull_request_read` — read diff and changed files

**GitLab** — use the REST API:
```bash
curl -qsSf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/{id}/merge_requests?state=opened&source_branch=renovate"
```

**Gitea / Forgejo** — compatible API (same shape as GitHub):
```bash
curl -qsSf -H "Authorization: token $GITEA_TOKEN" \
  "https://{instance}/api/v1/repos/{owner}/{repo}/pulls?state=open"
```

Extract every dependency line that changed. For GitHub Actions bumps, find every `uses: owner/action@{new-sha}` line where the SHA changed.

### Step 2: 3-point SHA verification (GitHub Actions bumps only)

For each GitHub Actions SHA that changed — required on GitHub, Gitea, and Forgejo (all use act runner):

**1. Action is still maintained**
- Check the upstream repo: not archived, not deprecated, not abandoned
- If archived/deprecated: comment explaining the issue, do not merge, flag a replacement

**2. Runtime is still supported**
- Fetch `action.yml` at the new SHA:
  `https://raw.githubusercontent.com/{owner}/{repo}/{new-sha}/action.yml`
- Find `runs.using`. Acceptable: `node24`, `composite`, `docker`
- Blocked (do not merge): `node20` (removed 2026-09-23), `node16`, `node12`
- If blocked: comment on the PR/MR with the specific runtime issue

**3. No supply-chain change**
- Diff old SHA → new SHA: look for new network calls in setup steps, new external dependencies fetched at runtime, changed entrypoints, new permissions
- If red flags: comment with the specific concern, do not merge

For **GitLab CI** bumps: verify Docker image digests are pinned and unchanged base image (no image hop to an unknown registry).

For **Renovate `go.mod` / `Cargo.toml` / `package.json` bumps**: run `govulncheck` / `cargo audit` / `npm audit` locally after the bump to confirm no CVE is introduced.

### Step 3: Fix the workflow files

If all checks pass:

1. Check out the branch: `git fetch origin {branch} && git checkout {branch}`
2. For GitHub Actions bumps, update stale inline tag comments to match the new version:
   ```
   uses: actions/checkout@{new-sha}  # v6.0.2   ← update from v6.0.1
   ```
3. Report the edited file(s) back to the caller. Do not commit — the caller runs `gitcommit --dir {project_dir} all` with message: `🔧 Fix stale action tag comment after Renovate bump 🔧`

### Step 4: Verify CI build status (if the project has workflows)

Static checks (Steps 1-3) are necessary but not sufficient — a project can pass every static check and still have a red CI build. If the project has any CI config (`.github/workflows/`, `.gitlab-ci.yml`, `.gitea/workflows/`, `.forgejo/workflows/`, `Jenkinsfile`), the actual build/check-run status on the PR/MR's head commit must be checked before merging. Skipping this makes the merge decision a no-op with respect to CI — the PR/MR can look clean statically while the real build is failing or still running.

**GitHub**: `gh pr checks {number} --repo {owner}/{repo}` (or the check-runs API: `GET /repos/{owner}/{repo}/commits/{sha}/check-runs`)

**GitLab**:
```bash
curl -qsSf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/{id}/merge_requests/{iid}/pipelines"
```

**Gitea / Forgejo**:
```bash
curl -qsSf -H "Authorization: token $GITEA_TOKEN" \
  "https://{instance}/api/v1/repos/{owner}/{repo}/commits/{sha}/status"
```

- All required checks `success`/`passed` → proceed to merge
- Any check `failure`/`failed`/`error` → do not merge, comment with the failing job name and log excerpt
- Any check `pending`/`running` → wait and re-check; do not merge on a pending build
- No CI config in the repo → this step is a no-op, proceed to merge

### Step 5: Merge

**GitHub**: `mcp__github__merge_pull_request` with `merge_method: squash`

**GitLab**:
```bash
curl -qsSf -X PUT -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/{id}/merge_requests/{iid}/merge" \
  -d "squash=true"
```

**Gitea / Forgejo**:
```bash
curl -qsSf -X POST -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  "https://{instance}/api/v1/repos/{owner}/{repo}/pulls/{index}/merge" \
  -d '{"Do":"squash"}'
```

### Step 6: Update the SHA table

After merging, update `~/.claude/memory/cicd_conventions.md` — "Common Action Reference SHAs" table — for every action that was updated:

```
| `owner/action-name` | vX.Y.Z | `{new-40-char-sha}` |
```

Report the updated SHA table row(s) back to the caller. Do not commit — the caller runs `gitcommit --dir {project_dir} all`.

### Merge decision summary

| Outcome | Action |
|---------|--------|
| All static checks pass, CI build green (or no CI config) | Fix stale comment → merge → update SHA table |
| Action archived / deprecated | Comment on PR/MR, do not merge, flag replacement |
| Runtime blocked (`node20` etc.) | Comment with specific runtime issue, do not merge |
| Supply-chain red flag | Comment with specific concern, do not merge |
| CVE introduced by dep bump | Comment with CVE ID and severity, do not merge |
| CI build failing | Comment with failing job name and log excerpt, do not merge |
| CI build pending/running | Wait and re-check; do not merge on a pending build |

---

## Multi-Provider `security.yml` / CI Security Audit

### Always-required gates (every provider, every public repo)

| Gate | GitHub / Gitea / Forgejo | GitLab | Jenkins |
|------|--------------------------|--------|---------|
| Secret scan | `trufflesecurity/trufflehog@{sha}` action; `with: base: ${{ github.event.before }}, head: ${{ github.event.after }}`; `fetch-depth: 0` — **never** `base: ${{ github.event.repository.default_branch }}` (resolves to HEAD after push, skips scan) | Docker job: `trufflesecurity/trufflehog:latest`; `GIT_DEPTH: 0` | Docker step inside `Security` stage |
| Workflow policy | Shell step: verify all `uses:` are 40-char SHA; block `pull_request_target` | Script step: verify Docker image digests are pinned; block untrusted variable injection | Groovy step: verify Docker image digests in `Jenkinsfile` |

### Conditional gates (add only when manifest exists)

| Gate | Condition | Command |
|------|-----------|---------|
| Go vuln scan | `go.sum` present | `govulncheck ./...` |
| Rust vuln scan | `Cargo.lock` present | `cargo audit` |
| Node vuln scan | `package-lock.json` present | `npm audit --audit-level=high` |
| Container scan | Dockerfile present | `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.70.0 image --exit-code 1 --severity CRITICAL,HIGH {image}` (GitLab: use `image: aquasec/trivy:0.70.0` job image instead) |

### Hard rules

- **Never use `gitleaks`** — requires a commercial license for org repos. Always use truffleHog
- **GitHub / Gitea / Forgejo**: every `uses:` must be a 40-char SHA — never `@v4`, `@main`, `@master`
- **GitLab / Jenkins**: every Docker image must be pinned by digest — never `:latest` in production CI jobs
- **Never use `pull_request_target`** (GitHub/Gitea/Forgejo) for untrusted code paths
- **GitLab**: never use `CI_JOB_TOKEN` with write access in MR pipelines from forks
- **Workflow-level permissions baseline** (GitHub): `contents: read` — no job in `security.yml` needs write access
- **All security jobs run in parallel** — no `needs:` (GitHub) or stage-level parallelism (GitLab) required between them
- **All public repos must have `renovate.json` at root** — Renovate is the only supported dependency update tool. Flag its absence when auditing. Never add Dependabot (`.github/dependabot.yml`) — it is GitHub-only and duplicates Renovate's work. Flag and remove `dependabot.yml` if present; migrate the project to Renovate.
- **`docker/build-push-action` must always set `provenance: false`** — without it, Docker BuildKit injects an OCI attestation manifest that registries render as a spurious `unknown/unknown` platform entry alongside `linux/amd64`/`linux/arm64`. Use `actions/attest-build-provenance` for release binary attestation instead. Flag any `docker/build-push-action` step missing `provenance: false`.

### Correct `workflow-policy` check (GitHub / Gitea / Forgejo)

```yaml
- name: Verify all third-party actions are pinned to a full SHA
  run: |
    set -e
    fail=0
    while IFS= read -r line; do
      ref=$(printf '%s' "$line" | sed -E 's/.*uses:[[:space:]]*([^[:space:]#]+).*/\1/')
      case "$ref" in
        ./*) continue ;;
        */*@*)
          sha=${ref#*@}
          if ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
            echo "::error::UNPINNED: $line"
            fail=1
          fi
          ;;
      esac
    done < <(grep -rhnE '^[[:space:]]*-?[[:space:]]*uses:' .github/workflows/ .gitea/workflows/ .forgejo/workflows/ 2>/dev/null)
    if [ $fail -ne 0 ]; then
      echo "::error::All third-party actions must be pinned to a 40-char commit SHA"
      exit 1
    fi
    echo "OK: all third-party actions pinned to full SHA"
```

Note the grep covers `.github/workflows/`, `.gitea/workflows/`, and `.forgejo/workflows/` in one pass.

### Error messaging

Use `::error::` workflow commands on GitHub/Gitea/Forgejo for red annotations on the summary page:
```bash
echo "::error::UNPINNED: uses: actions/checkout@v4"
```

GitLab and Jenkins: `echo "ERROR: ..."` with a non-zero exit code — CI surfaces this as a failed step.

---

## Common Action Reference SHAs (current)

Always cross-reference `~/.claude/memory/cicd_conventions.md` — this table may lag if Renovate PRs have been merged:

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
