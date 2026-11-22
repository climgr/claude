#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220003-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-secrets.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Thursday, May 15, 2026 00:00 EDT
# @@File             :  no-secrets.sh
# @@Description      :  Claude Code PreToolUse hook — scan Write/Edit content for high-confidence secret patterns and block if found
# @@Changelog        :  Block credential-shaped connection strings (scheme://user:password@host) in markdown docs; placeholders like {user}:{password} pass. Earlier: Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error. Parse with strict=False like every other hook so raw control characters inside content strings never abort the scan.
# @@TODO             :  None
# @@Other            :  Applies to Write (content) and Edit (new_string); .env.example/.sample templates and placeholder-text matches (changeme, your_key_here) are skipped.
# @@Resource         :  ~/.claude/memory/sensitive_data.md
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220003-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Fail-open if python3 is missing — a broken hook exits 0 (no-op) so we never silently block every Write/Edit call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'no-secrets.sh: required command not found: python3\n' >&2
  exit 0
fi

INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$INPUT_TMPFILE"' EXIT
printf '%s' "$INPUT" > "$INPUT_TMPFILE"

python3 - "$INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import sys

# Fail-open on malformed payloads — a broken hook must never block every Write/Edit call.
try:
    with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as _f:
        raw = _f.read()
    d = json.loads(raw, strict=False)
except Exception:
    sys.exit(0)

# A JSON scalar or array parses cleanly but has no .get(), so the block
# below would raise AttributeError and exit non-zero. Part 6 requires a
# hook to fail open on any unusable payload, never to surface an error.
if not isinstance(d, dict):
    sys.exit(0)

# Same reasoning one level down: normalise a non-object tool_input /
# tool_response to an empty dict so every downstream .get() chain below
# stays safe without each call site needing its own type check.
for _field in ("tool_input", "tool_response"):
    if _field in d and not isinstance(d[_field], dict):
        d[_field] = {}

# Every field below is documented as a string but arrives as arbitrary JSON.
# A list `command` or a numeric `cwd` reaches a str-only call (.split(),
# .startswith(), os.path.*) and raises TypeError -> exit 1, which Claude Code
# reports as a hook error on an ordinary tool call. Drop any non-string value
# so the hook no-ops on it instead, per Part 6's "Fail open, always".
for _obj in (d, d.get("tool_input") or {}, d.get("tool_response") or {}):
    for _key in ("command", "file_path", "cwd", "session_id", "transcript_path",
                 "content", "new_string", "old_string", "pattern", "path",
                 "agent_type", "last_assistant_message"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

tool_name  = d.get("tool_name", "")
tool_input = d.get("tool_input", {})

# A non-string file_path (number, null, list) survives `or ""` and reaches
# os.path.basename below, raising TypeError — exit 1, reported as a hook
# error. Part 6 requires failing open on any unusable payload instead.
filepath = tool_input.get("file_path", "") or ""
if not isinstance(filepath, str):
    filepath = ""
basename = os.path.basename(filepath)

# Exempted template/example env files — these are expected to contain placeholder values.
ALLOWED_TEMPLATES = {
    ".env.example",
    ".env.sample",
    "app.env.example",
    "app.env.sample",
    "default.env.example",
    "default.env.sample",
}
if basename in ALLOWED_TEMPLATES:
    sys.exit(0)

# Local System Management Zone (~/Projects/local/system/**, see CLAUDE.md) allows
# plaintext credentials — derived from $HOME at runtime, never hardcoded. This
# cwd-path check is necessary but not sufficient: sensitive_data.md's "The Only
# Exceptions" conditions the zone exemption on confirmed PRIVATE repo visibility,
# which a hook cannot verify (AI.md's hook rules forbid network I/O, and a
# visibility check is network I/O). The Repo privacy gate — run at repo-creation
# and after every push, per CLAUDE.md's zone section — is what actually keeps
# this exemption safe; this hook only narrows scope by path.
cwd = d.get("cwd", "") or ""
zone_root = os.path.join(os.environ.get("HOME", "/root"), "Projects", "local", "system")
if cwd == zone_root or cwd.startswith(zone_root + os.sep):
    sys.exit(0)

# Select content to scan based on tool.
# Write tool uses "content"; Edit tool uses "new_string".
if tool_name == "Write":
    content = tool_input.get("content", "") or ""
elif tool_name == "Edit":
    content = tool_input.get("new_string", "") or ""
else:
    sys.exit(0)

# A numeric/list content survives `or ""` and raises TypeError in re.finditer
# below — exit 1, reported as a hook error. Fail open instead, per Part 6.
if not isinstance(content, str) or not content:
    sys.exit(0)

# High-confidence secret patterns.
PATTERNS = [
    ("AWS Access Key ID",        r"AKIA[0-9A-Z]{16}"),
    ("GitHub Token",             r"gh[pso]_[A-Za-z0-9]{36,}"),
    ("GitHub PAT (new format)",  r"github_pat_[A-Za-z0-9_]{82,}"),
    ("Slack Token",              r"xox[baprs]-[0-9A-Za-z\-]{10,}"),
    ("Stripe Live Secret Key",   r"sk_live_[A-Za-z0-9]{24,}"),
    ("Google API Key",           r"AIza[0-9A-Za-z\-_]{35}"),
    ("SendGrid API Key",         r"SG\.[A-Za-z0-9._\-]{22}\.[A-Za-z0-9._\-]{43}"),
    ("PEM Private Key",          r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"),
    ("Anthropic API Key",        r"sk-ant-[A-Za-z0-9\-_]{40,}"),
    ("OpenAI API Key",           r"sk-proj-[A-Za-z0-9]{40,}"),
    ("npm Access Token",         r"npm_[A-Za-z0-9]{36,}"),
    ("JWT (3-part)",             r"eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"),
    ("HuggingFace Token",        r"hf_[A-Za-z0-9]{34,}"),
    ("GitLab Token",             r"glpat-[A-Za-z0-9\-_]{20,}"),
    ("PyPI API Token",           r"pypi-[A-Za-z0-9_\-]{40,}"),
]

# Placeholder indicators — suppression applies only when one of these patterns
# appears inside the matched secret text itself; surrounding text (comments,
# code braces like {label}) must never mask a real key on a nearby line.
PLACEHOLDER_RE = re.compile(
    r"changeme"
    r"|placeholder"
    r"|your[_-]?(?:api[_-]?)?(?:key|token|secret|password)[_-]?here"
    r"|example"
    r"|dummy"
    r"|fake"
    r"|test[_-]?(?:key|token|secret)"
    r"|xxx+"
    r"|<[A-Za-z_][^>]*>"
    r"|\{[A-Za-z_][^}]*\}"
    r"|TO_BE"
    r"|FILL_IN"
    r"|REPLACE_ME"
    r"|INSERT_HERE"
    r"|YOUR_",
    re.IGNORECASE,
)

def redact(value):
    """Return first 4 chars + asterisks + last 2 chars."""
    if len(value) <= 6:
        return "*" * len(value)
    return value[:4] + "*" * (len(value) - 6) + value[-2:]

findings = []

# Documentation examples never carry a credential-shaped string; connection
# strings use {user}:{password} placeholders (PART 10 Secret Scan Job). Only
# markdown docs are checked — code and tests legitimately build such URLs.
# Userinfo starting with $, {, <, % or ( is a variable/placeholder, not a literal.
if filepath.lower().endswith(".md"):
    for m in re.finditer(r"\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s:/@${<%(\"'`]+:[^\s:/@${<%(\"'`]+@", content):
        if PLACEHOLDER_RE.search(m.group(0)):
            continue
        findings.append(("Credentialed URL in docs (use {user}:{password})", redact(m.group())))

for label, pattern in PATTERNS:
    for m in re.finditer(pattern, content):
        # Suppress only when a placeholder pattern overlaps the matched secret
        # text itself — a genuinely templated value like {your_token_here}.
        if PLACEHOLDER_RE.search(m.group(0)):
            continue
        findings.append((label, redact(m.group())))

if not findings:
    sys.exit(0)

lines = ["BLOCKED: potential secret(s) detected in content being written to disk.\n"]
for label, redacted in findings:
    lines.append(f"  - {label}: {redacted}")
lines.append("")
lines.append(
    "Never write real credentials to source files. "
    "Use environment variables, mounted secrets, or a secrets manager. "
    "See ~/.claude/memory/sensitive_data.md"
)
msg = "\n".join(lines)

# stdout → Claude Code (block reason returned to Claude as context)
print(msg)
# stderr → user terminal
print(msg, file=sys.stderr)

sys.exit(2)
PYEOF
