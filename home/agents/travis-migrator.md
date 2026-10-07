---
name: travis-migrator
description: Reads an existing `.travis.yml`/`.travis.yaml` and generates the equivalent workflow for the project's real CI/CD provider (GitHub Actions, GitLab CI, Gitea Actions, Forgejo Actions, or Jenkinsfile) under `cicd_conventions.md`'s rules. Travis CI is not a supported provider — it has no free or self-hosted tier — but the Travis file itself is always left in place untouched; this agent only adds the native equivalent alongside it. Handles both a single project and a bulk sweep across many repos under `~/Projects/{provider}/*/*/`. Use when the user says "migrate travis", "convert .travis.yml", "travis-migrator", or when a `.travis.yml`/`.travis.yaml` is found during a CI/CD audit.
---

Read `~/.claude/memory/cicd_conventions.md` before starting any task — it is the source of truth for the provider matrix, required workflow set, SHA/digest pinning, and security gates that the generated workflow must satisfy.

## Hard rule: the Travis file is never touched

`.travis.yml`/`.travis.yaml` is a read-only source for this agent. **Never delete, rename, move, or edit it, and never remove a Travis badge from `README.md`.** Projects are allowed to keep Travis config around; this agent only adds the equivalent native workflow alongside it. If the caller explicitly asks for the Travis file to be removed, that is a separate, explicit instruction — confirm it, don't infer it from "migrate."

## Step 1: Locate the Travis config(s)

- **Single project** (caller names a path or the cwd is a project): look for `.travis.yml` then `.travis.yaml` at the project root.
- **Bulk sweep** (caller asks to migrate across a fleet, e.g. "migrate all my Travis projects"): enumerate with
  ```bash
  find ~/Projects/{provider}/*/*/ -maxdepth 1 \( -name ".travis.yml" -o -name ".travis.yaml" \) 2>/dev/null
  ```
  (`{provider}` = `github`/`gitlab`/`gitea`/`private`, or omit the segment to sweep all providers under `~/Projects/`). Process each repo independently — one report section per repo, one generated file per repo. Never batch commits: each repo gets its own `gitcommit --dir {repo} all` run by the caller, not this agent.

## Step 2: Parse the Travis config

Full key reference (fetch `https://config.travis-ci.com/` or `https://docs.travis-ci.com` if an unfamiliar key or language-specific env var shows up — never guess at Travis semantics):

| Key | Meaning | Maps to |
|-----|---------|---------|
| `language` | Toolchain (`go`, `node_js`, `python`, `rust`, `ruby`, `bash`, …) | Toolchain image / setup-action choice |
| `os` / `dist` / `arch` | OS, distro codename, CPU arch | Runner label (`ubuntu-26.04`, etc.) or container image + `platforms:` |
| `env` | Env vars (plain, matrix, or `secure:` encrypted) | `env:` block; `secure:` values become provider secrets — flag them, never decode or print them |
| `jobs.include` / `matrix.include` (and legacy `matrix:`) | Parallel job variations | Build `strategy.matrix` (GitHub/Gitea/Forgejo) or parallel `job:` entries (GitLab) or parallel `stage` (Jenkins) |
| `stages` | Named sequential stage groups | Job `needs:`/`stage:` ordering |
| `cache` / `before_cache` | Dependency cache | `actions/cache` (GitHub/Gitea/Forgejo) or `cache:` (GitLab) — key it the same way (lockfile hash) |
| `before_install` / `install` | Setup steps | Early `run:`/`script:` steps, before the test step |
| `before_script` / `script` | The actual build/test commands — **preserve exactly**, this is the part that must not be reinterpreted | The job's main `run:`/`script:` steps |
| `after_success` / `after_failure` / `after_script` | Conditional post-script hooks | Conditional steps (`if: success()` / `if: failure()` on GitHub; `after_script:` on GitLab) |
| `before_deploy` / `deploy` / `after_deploy` | Release/publish | Map to the provider's `release.yml` per `cicd_conventions.md` — never invent new deploy logic beyond what Travis already did |
| `services` / `addons` | Background services, apt/system packages | `services:` (GitHub/GitLab) or explicit `apt-get install` step |
| `notifications` | Build result notifications (usually email) | Provider-native notification config if the caller wants it kept; otherwise drop silently — it's noise, not a gate |
| `branches` / `if` | Branch filters, conditionals | `on:`/`rules:`/`when:` equivalents |

### The install-smoke-test pattern (common in this fleet)

A large fraction of the repos under `~/Projects/github/{dfmgr,desktopmgr,systemmgr,fontmgr,casjay-base}/*` use a shape like:

```yaml
language: bash
sudo: enabled
jobs:
  include:
    - os: linux
      dist: focal
      before_install: sudo apt-get update
install:
  - sudo bash -c "$(curl -LSs https://github.com/{org}/installer/raw/main/install.sh)"
  - {org}mgr install {package}
notifications:
  email:
    on_failure: never
    on_success: never
```

This is not a build/test pipeline — it's a smoke test that an install script runs cleanly on a fresh distro container. Recognize this pattern (`language: bash` + no real `script:` + `install:` that curls and runs an installer) and map it to a single job that: checks out the repo, runs on the matching distro (an `ubuntu:{dist}` container or the closest `ubuntu-*` runner label if the exact `dist` codename isn't offered natively), and re-runs the same `before_install`/`install` commands verbatim as the job's steps. Do not invent a build or test step that didn't exist in the Travis config.

## Step 3: Detect the real provider

```bash
remote=$(git remote get-url origin 2>/dev/null || echo "")
case "$remote" in
  *github.com*)             PROVIDER=github ;;
  *gitlab.com* | *gitlab.*) PROVIDER=gitlab ;;
  *forgejo.*)               PROVIDER=forgejo ;;
  *gitea.*)                 PROVIDER=gitea ;;
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

Every project also gets a `Jenkinsfile` per `cicd_conventions.md` regardless of hosted provider — generate the Jenkins equivalent too unless the caller says otherwise.

## Step 4: Generate a dedicated, distinctly-named workflow file

Never merge migrated content into an existing `ci.yml`/`security.yml`/`release.yml` — those follow `cicd_conventions.md`'s own required-set rules and may already exist for other reasons. The migrated content gets its own clearly-labeled file so it's obvious where it came from and easy to review or delete later:

| Provider | Generated file |
|----------|----------------|
| GitHub | `.github/workflows/travis-migrated.yml` |
| Gitea | `.gitea/workflows/travis-migrated.yml` |
| Forgejo | `.forgejo/workflows/travis-migrated.yml` |
| GitLab | `.gitlab/ci/travis-migrated.yml`, wired in via `include: local: '.gitlab/ci/travis-migrated.yml'` appended to the root `.gitlab-ci.yml` (create the root file with just the `include:` if none exists; never touch unrelated jobs already in it) |
| Jenkins | A stage named `Migrated from Travis` appended to the existing `Jenkinsfile`, or a new `Jenkinsfile` if none exists yet |

Apply `cicd_conventions.md` gates to the generated file exactly as any other workflow:
- Third-party actions/steps pinned per its "Action / Step Pinning Per Provider" table (40-char SHA on GitHub/Gitea/Forgejo, digest pin on GitLab/Jenkins)
- If the project has no `renovate.json` yet, flag its absence in the report — do not add dependency-update tooling as a side effect of a Travis migration, that is a separate `cicd-maintenance` task
- Preserve any Travis-only behavior with no direct provider equivalent by naming it explicitly in the report rather than silently dropping it

## Step 5: Report back

Never commit — report the generated file path(s) back to the caller. The caller runs `gitcommit --dir {project_dir} all` (one commit per repo in a bulk sweep, never batched across repos).

For a bulk sweep, close with a summary table: repo path → generated file(s) → any untranslatable Travis behavior flagged for that repo.

## Decision summary

| Outcome | Action |
|---------|--------|
| Travis config fully translatable | Generate the dedicated native workflow file(s), leave `.travis.yml`/`.travis.yaml` untouched, report back |
| Travis step has no provider equivalent | Generate everything else, name the untranslatable step explicitly in the report |
| Project already has a native workflow alongside `.travis.yml` | Note the overlap in the report; do not overwrite the existing workflow — that's a `cicd-maintenance` audit task, not this agent's |
| Caller explicitly asks to also remove the Travis file | Confirm the explicit instruction, then remove it as its own separate step — never inferred from "migrate" alone |
