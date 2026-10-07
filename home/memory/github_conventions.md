---
name: GitHub conventions
description: CODEOWNERS, branch protection, workflow patterns, issue/PR templates, release automation, and container registry conventions for CasjaysDev GitHub projects
type: user
---

## CODEOWNERS

Every public repo must have `.github/CODEOWNERS`. Minimum template:

```
# Global owners — review required for everything not covered below
* @{project_org}

# Workflow changes require maintainer sign-off
.github/ @{project_org}

# Security-sensitive files
SECURITY.md @{project_org}
docker/ @{project_org}
```

Rules:
- `*` must always have at least one owner — no orphaned files
- `.github/` always owner-gated — workflow modification by contributors requires review
- CODEOWNERS is only enforced when branch protection has "Require review from Code Owners" enabled

---

## Branch Protection

The default branch (`main`) must be protected. Apply via `gh api` or the GitHub UI:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["build", "test", "security"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

- `enforce_admins: false` — allows maintainer hotfix; emergency bypasses must be followed by a retrospective fix commit
- All required checks must pass; never merge with a skipped check
- Stale review dismissal on new push — fresh approval required after each change

---

## Issue Templates

`.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug report
about: Something is not working as expected
labels: bug
---

**What happened?**

**Expected behavior:**

**Steps to reproduce:**
1.
2.
3.

**Environment:**
- OS:
- Version (`{project_name} --version`):
```

`.github/ISSUE_TEMPLATE/feature_request.md`:

```markdown
---
name: Feature request
about: Suggest a new capability
labels: enhancement
---

**What problem does this solve?**

**Proposed solution:**

**Alternatives considered:**
```

---

## Pull Request Template

`.github/pull_request_template.md`:

```markdown
## Summary

<!-- What does this PR do? Link the issue it closes: Closes #N -->

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

## Reusable Workflows

Extract shared logic into `.github/workflows/reusable-*.yml`:

```yaml
# .github/workflows/reusable-build.yml
on:
  workflow_call:
    inputs:
      platform:
        required: false
        type: string
        default: "linux/amd64,linux/arm64"
```

Call from other workflows:

```yaml
jobs:
  build:
    # same-repo reuse
    uses: ./.github/workflows/reusable-build.yml
    with:
      platform: "linux/amd64"
```

Third-party reusable workflows (external repos) are pinned to a full commit SHA like all other third-party actions.

---

## Matrix Strategy

For multi-platform or multi-version builds:

```yaml
strategy:
  # never cancel other matrix cells when one fails
  fail-fast: false
  matrix:
    os: [ubuntu-26.04]
    # test current + prior stable release
    go: ["stable", "oldstable"]
```

`fail-fast: false` is always required — see all failures in one run, not just the first.

---

## Secret Management

- Secrets via `secrets.{NAME}` — never hardcoded, never logged
- `GITHUB_TOKEN` is automatic — use it for `ghcr.io` pushes and GitHub API calls
- Cross-repo shared secrets (Docker Hub, cloud creds) defined at the org level
- Never print secrets in workflow logs — a secret that appears in a step name or `echo` is immediately compromised; use `::add-mask::${{ secrets.FOO }}` when a secret must be referenced dynamically

---

## Release Automation (`release.yml`)

Triggered by `push: tags: ['v*']`. Standard steps:

1. Checkout at the tagged commit
2. Build all platform binaries
3. Run `govulncheck`/`cargo audit`/`npm audit` — fail on critical/high CVE
4. Generate SHA-256 checksums for all artifacts
5. Generate CycloneDX or SPDX JSON SBOM
6. Create GitHub Release: binaries + checksums + SBOM + generated release notes
7. Push Docker image: `:{version}`, `:latest`, `:YYMM`, `:{commit}`

Never create a GitHub Release from a non-tagged commit.

---

## Container Registry

Registry URL is determined by the git provider. **Never hardcode** the registry URL in Dockerfiles — use `ARG REGISTRY` and pass it from the Makefile.

| Provider | Registry prefix | Full image path |
|----------|----------------|----------------|
| GitHub | `ghcr.io` | `ghcr.io/{project_org}/{project_name}:{tag}` |
| GitLab | `registry.gitlab.com` | `registry.gitlab.com/{project_org}/{project_name}:{tag}` |
| Forgejo/Gitea | `{instance}` | `{instance}/{project_org}/{project_name}:{tag}` |

**Base images and toolchains always pull from `docker.io`** (the implicit default):
- Toolchain images: `casjaysdev/go:latest`, `casjaysdev/rust:latest`, `node:alpine`, `python:alpine`
- Base runtime images: `alpine:latest`, `ubuntu:{version}`, `debian:{version}`
- Never prefix these with `ghcr.io` or any other registry — they are upstream official images on `docker.io`

**Makefile `REGISTRY` variable** (Go example, other languages follow same pattern):

```makefile
# For GitHub-hosted projects:
REGISTRY := ghcr.io/$(PROJECTORG)/$(PROJECTNAME)
# For GitLab: REGISTRY := registry.gitlab.com/$(PROJECTORG)/$(PROJECTNAME)
```

The Docker target uses `$(REGISTRY):{tag}` — never a hardcoded full image path.

---

## SECURITY.md

Required for all public repos. Full requirements in `~/.claude/memory/security_conventions.md`. Key sections:

- **Supported versions** — table of which versions receive security fixes
- **Reporting** — email/contact for private disclosure, response SLA (acknowledge in 48h, patch in 14 days for critical)
- **Disclosure timeline** — coordinated disclosure policy
- **Out of scope** — what is not considered a vulnerability for this project

Never publish CVE details in `SECURITY.md` — those belong in GitHub Security Advisories after the fix is released.
