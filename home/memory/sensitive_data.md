---
name: Sensitive data rule
description: Never expose credentials anywhere; masking format; all public destinations (git, pastes, bug reports, chat) treated identically
type: user
---

## Universal Rule

**All public destinations are equally dangerous.** Treat these identically — a credential leaked to any of them is a permanent exposure risk:

| Destination | Examples |
|-------------|---------|
| Git repos | GitHub, GitLab, Gitea (public OR private) |
| Paste services | pastebin.com, GitHub Gist, paste.rs, dpaste, ix.io, termbin |
| Bug trackers | GitHub Issues, Jira, Linear, Sentry |
| Code review | PRs, diffs, review comments |
| Chat / email | Slack, Discord, Teams, email threads |
| Screenshots / recordings | Any image or video that shows a terminal or config |

**"Private" is not a defense** — private repos get breached, private pastes get indexed, private channels get screenshotted. Treat all of them as fully public.

## What Is Sensitive

- Tokens, API keys, personal access tokens, OAuth secrets
- Passwords, passphrases, PINs
- Private keys, certificates, `.pem` / `.key` files
- Session cookies, JWTs, refresh tokens
- Internal hostnames, IP addresses, VPN endpoints
- Database credentials, connection strings with passwords
- PII: names, emails, phone numbers, addresses, SSNs, card numbers

## The Only Exceptions

- A **personal dotfiles repo explicitly designated as private and intended to hold credentials** (env files, SSH keys, global env vars) may contain credentials. Context determines this — do not assume; if unclear, do not add and ask instead.
- **Repos under `~/Projects/local/system/**`** (see `local_system_zone.md`) — personal project/infra/fleet-management tooling. Plaintext tokens/passwords/API keys are allowed there without hashing or masking, **conditioned on the repo's visibility being confirmed private** (see the Repo privacy gate in that file). If visibility is ever unconfirmed or found public, treat the repo as fully public until fixed — the exception does not apply until privacy is restored.
  - **This precondition is enforced procedurally, not by a hook** — `no-secrets.sh`/`bash-content-scan.sh` exempt this zone by cwd path only, because AI.md's hook rules forbid network I/O in any hook, and a live visibility check (`gh repo view --json visibility`) is network I/O. Actually confirming and maintaining private visibility is the Repo privacy gate's job (steps 1-5 in `local_system_zone.md`), run at repo-creation and after every push — the hook's cwd scoping is a necessary but not sufficient condition; the human/workflow step is what makes the exception actually safe to rely on.

## Masking Format

When you must share something that contains or may contain sensitive values — logs, error output, config snippets, bug reports, paste content, screenshots — **mask values but preserve keys**:

```
# Key=value — replace value, keep key
api-token=xxxxx
password=xxxxx
STRIPE_SECRET_KEY=xxxxx

# HTTP headers — keep scheme/prefix, replace credential
Authorization: Bearer xxxxx
Proxy-Authorization: Basic xxxxx

# Connection strings — mask credential, keep host/db for debugging context
db_url=postgres://user:xxxxx@db.internal:5432/myapp

# JSON / YAML / TOML — replace value in-place, keep key
{ "api_key": "xxxxx", "endpoint": "https://api.example.com" }
```

Masking rules:
- Use `xxxxx` (five x's minimum); do not preserve the original length — length is information
- Never show partial values — `sk-abc...xyz` is still a leak
- Last-4 is acceptable only for payment card numbers where the last 4 are intentionally non-secret by PCI design
- A hash (`sha256:abc123…`) is acceptable when the hash itself is non-sensitive and needed for correlation
- Apply before sharing anywhere — paste services, issue trackers, chat, email, screenshots

## How to Handle Credentials at Runtime

- Use environment variables, mounted secrets, or a secrets manager — never hardcode
- Config files that need a credential: use `${VAR_NAME}` as a placeholder, never a real value
- **Never store tokens in plaintext** — hash with SHA-256 before persisting to disk or a database; never log the raw token at any level
- **Password hashing: Argon2id only** — full rule and tuning parameters: `security_conventions.md`
- Scanning generated code for accidental credential leakage is part of every review

## CI / CD Specific Rules

- **`env:` blocks in GitHub Actions** — never print the value of a secret in a `run:` step (e.g. `echo "${{ secrets.TOKEN }}"` leaks to logs); reference secrets only as env vars (`TOKEN: ${{ secrets.TOKEN }}`) and let the tool consume them
- GitHub Actions automatically masks registered secrets in logs, but derived values (slices, transforms, base64 of a secret) are NOT masked — never transform a secret and log the result
- Rotate any secret that appeared in a CI log immediately — assume it is compromised
- Fork PRs do not receive repo secrets by default — confirm this is configured correctly; never grant secrets to untrusted forks via `pull_request_target`

## Git History — Secret Found in History

If a secret is found in git history (even in an old commit or a deleted file):

1. **Rotate the secret immediately** — treat it as compromised regardless of repo visibility
2. Remove it from history with `git filter-repo` (preferred over `BFG`) — this rewrites history
3. Force-push all affected branches; notify all collaborators to re-clone (their local copies still have the old history)
4. Scan for any forks or mirrors that may have pulled the compromised history
5. Document the incident and rotation in `{project_dir}/IDEA.md` if it affected production credentials

Never leave a known secret in history "because it's revoked" — revoked secrets still indicate the project's secret naming and rotation practices to an attacker.

## `.env.example` Placeholder Values

`.env.example` / `.env.sample` files are committed as templates. Their values must be **obviously fake** — not real-looking strings that could be mistaken for real credentials:

```bash
# GOOD — clearly fake
DATABASE_URL=postgres://user:changeme@localhost:5432/myapp
API_KEY=your-api-key-here
SECRET_TOKEN=replace-with-a-random-256-bit-hex-string

# BAD — looks real, could be mistaken for a valid value
DATABASE_URL=postgres://admin:p@ssw0rd123@prod.db.internal:5432/myapp
API_KEY=sk-abc123def456ghi789
```

Never use real-looking tokens, real hostnames, or real-format secrets (e.g. a 40-char hex string that looks like a GitHub token) as example values.

`AI.md`, `IDEA.md`, `README.md` and `docs/` never contain credential-shaped strings; connection strings use `{user}:{password}` placeholders. A flagged example is rewritten, not allowlisted. True false positives in project code or test fixtures use the inline `trufflehog:ignore` comment (see the `cicd_conventions.md` secret-scan row).

## Pre-flight Before Sharing

Before posting to any destination above:

1. Scan for anything in the "What Is Sensitive" list
2. Mask every sensitive value using the format above
3. If you are unsure whether something is sensitive — mask it anyway
4. If the user asks you to post something containing real credentials: stop, flag it, mask first, then post only after confirmation

Paste services additionally: no history audit trail, so a leaked secret is harder to identify and rotate than in a git repo. Apply stricter scrutiny.
