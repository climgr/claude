#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220006-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-doc-sync.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, Sep 27, 2026 EDT
# @@File             :  enforce-doc-sync.sh
# @@Description      :  PreToolUse Bash hook: blocks `gitcommit --dir <path> all` unless .git/COMMIT_MESS carries an explicit IDEA.md and README.md status line, for any repo where that file exists.
# @@Changelog        :  The status line text after the colon must start with updated or N/A; an ordinary per-file change bullet no longer satisfies the gate. Initial version.
# @@TODO             :  None
# @@Other            :  Forced-acknowledgment gate, not a content-diff heuristic: only checks that a status line is PRESENT, never that its claim is true (same trust model as enforce-commit-mess-coverage.sh's per-file bullets). Accepted forms: `- IDEA.md: updated (...)` or `- IDEA.md: N/A - no user-facing change` (same for README.md). DOC_SYNC_GATE_OVERRIDE=1 <gitcommit ...> bypasses for that one call - user-directed only, never Claude's own initiative.
# @@Resource         :  CLAUDE.md - Commit Workflow · home/memory/gitcommit_conventions.md · home/memory/project_conventions.md
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220006-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'enforce-doc-sync.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

ENFORCE_DOC_SYNC_INPUT="$(cat)"

ENFORCE_DOC_SYNC_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$ENFORCE_DOC_SYNC_INPUT_TMPFILE"' EXIT
printf '%s' "$ENFORCE_DOC_SYNC_INPUT" > "$ENFORCE_DOC_SYNC_INPUT_TMPFILE"

python3 - "$ENFORCE_DOC_SYNC_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import sys

with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as _f:
    raw = _f.read()
try:
    payload = json.loads(raw, strict=False)
except Exception:
    sys.exit(0)

if not isinstance(payload, dict):
    sys.exit(0)

if "tool_input" in payload and not isinstance(payload["tool_input"], dict):
    payload["tool_input"] = {}

for _obj in (payload, payload.get("tool_input") or {}):
    for _key in ("command", "cwd", "session_id", "transcript_path"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

if payload.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
if not cmd or not re.search(r"\bgitcommit\b", cmd):
    sys.exit(0)


def find_gitcommit_dir(text):
    # Only the valid `gitcommit --dir <path> all` shape carries a --dir path -
    # malformed shapes are already blocked by enforce-gitcommit-shape.sh.
    for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", text):
        sub_cmd = sub_cmd.strip()
        if not sub_cmd:
            continue
        try:
            tokens = shlex.split(sub_cmd)
        except ValueError:
            tokens = sub_cmd.split()

        clean = []
        override = False
        skipping_prefix = True
        for tok in tokens:
            if skipping_prefix:
                if tok in ("command", "env", "exec", "nohup", "time", "sudo", "doas"):
                    continue
                if tok == "DOC_SYNC_GATE_OVERRIDE=1":
                    override = True
                    continue
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                    continue
                if tok.startswith("-"):
                    continue
                skipping_prefix = False
            clean.append(tok.lstrip("\\"))

        if len(clean) == 4 and clean[0] == "gitcommit" and clean[1] == "--dir" \
                and clean[3] == "all" and clean[2].startswith("/"):
            yield clean[2], override


targets = list(find_gitcommit_dir(cmd))
if not targets:
    sys.exit(0)

# DOC_SYNC_GATE_OVERRIDE=1 <gitcommit ...> - explicit, per-invocation, user-
# directed bypass. Claude sets this prefix only when the user's own message
# explicitly says to bypass/skip the doc-sync gate for this commit - never on
# its own initiative just because the gate blocked (CLAUDE.md: "never
# auto-bypass a hook block"). Same prefix pattern as
# enforce-test-lint-gate.sh's TEST_LINT_GATE_OVERRIDE=1.
if any(override for _target, override in targets):
    sys.exit(0)


def status_line_present(mess_text, filename):
    # Accepted forms:
    #   - IDEA.md: updated (added X to Business Logic)
    #   - IDEA.md: N/A - no user-facing change
    # Presence-only check - it never verifies the claim is true, but the text after
    # the colon must start with `updated` or `N/A`, so an ordinary per-file change
    # bullet (`- README.md: add a row`) does not count as the doc-sync status line.
    pattern = r"^\s*-\s*`?" + re.escape(filename) + r"`?\s*:\s*(?:updated|N/A)\b"
    for line in mess_text.split("\n"):
        if re.match(pattern, line, re.IGNORECASE):
            return True
    return False


problems = []
for repo, _override in targets:
    if not os.path.isdir(os.path.join(repo, ".git")):
        continue
    required = [f for f in ("IDEA.md", "README.md") if os.path.isfile(os.path.join(repo, f))]
    if not required:
        continue
    mess_path = os.path.join(repo, ".git", "COMMIT_MESS")
    try:
        with open(mess_path, "r", encoding="utf-8", errors="replace") as f:
            mess = f.read()
    except OSError:
        mess = ""
    missing = [f for f in required if not status_line_present(mess, f)]
    if missing:
        problems.append((repo, missing))

if not problems:
    sys.exit(0)

msg = "BLOCKED: gitcommit is missing a doc-sync status line in COMMIT_MESS.\n\n"
for repo, missing in problems:
    msg += f"{repo}: missing status line for: {', '.join(missing)}\n"
msg += (
    "\nEvery commit must record, for each doc that exists in the repo, whether "
    "it needed updating - this is what closes the IDEA.md/code drift problem "
    "(a feature gets added to code but IDEA.md never gets told). Add one line "
    "per missing file to .git/COMMIT_MESS, either form:\n"
    "  - IDEA.md: updated (<what changed in Business Logic>)\n"
    "  - IDEA.md: N/A - no user-facing change\n"
    "  - README.md: updated (<what changed>)\n"
    "  - README.md: N/A - no user-facing change\n"
    "This only checks the line is present, not that the claim is accurate - "
    "make the real call before writing it. DOC_SYNC_GATE_OVERRIDE=1 prefix "
    "bypasses this for one call, user-directed only, never on your own "
    "initiative.\n"
)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF
