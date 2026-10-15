#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-read-gitcommit.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 20:00 EDT
# @@File             :  no-read-gitcommit.sh
# @@Description      :  PreToolUse Read+Grep+Bash hook: blocks reading the commit wrapper script (Read/Grep tools, cat/less/head/etc via Bash), a previously prose-only rule.
# @@Changelog        :  Allow reads and edits when the session's git repo contains the resolved gitcommit file (its source repo / installed clone). Previously: decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  Resolves the symlink target so both paths are blocked; the zone's raw-git pre-authorization never covers the commit wrapper itself.
# @@Resource         :  CLAUDE.md - Commit Workflow, home/hooks/drift-guard-read.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610150001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'no-read-gitcommit.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

NO_READ_GITCOMMIT_INPUT="$(cat)"

NO_READ_GITCOMMIT_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$NO_READ_GITCOMMIT_INPUT_TMPFILE"' EXIT
printf '%s' "$NO_READ_GITCOMMIT_INPUT" > "$NO_READ_GITCOMMIT_INPUT_TMPFILE"

python3 - "$NO_READ_GITCOMMIT_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import shutil
import sys

with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as _f:
    raw = _f.read()
try:
    payload = json.loads(raw, strict=False)
except Exception:
    sys.exit(0)

# A JSON scalar or array parses cleanly but has no .get(), so the block
# below would raise AttributeError and exit non-zero. Part 6 requires a
# hook to fail open on any unusable payload, never to surface an error.
if not isinstance(payload, dict):
    sys.exit(0)

# Same reasoning one level down: normalise a non-object tool_input /
# tool_response to an empty dict so every downstream .get() chain below
# stays safe without each call site needing its own type check.
for _field in ("tool_input", "tool_response"):
    if _field in payload and not isinstance(payload[_field], dict):
        payload[_field] = {}

# Every field below is documented as a string but arrives as arbitrary JSON.
# A list `command` or a numeric `cwd` reaches a str-only call (.split(),
# .startswith(), os.path.*) and raises TypeError -> exit 1, which Claude Code
# reports as a hook error on an ordinary tool call. Drop any non-string value
# so the hook no-ops on it instead, per Part 6's "Fail open, always".
for _obj in (payload, payload.get("tool_input") or {}, payload.get("tool_response") or {}):
    for _key in ("command", "file_path", "cwd", "session_id", "transcript_path",
                 "content", "new_string", "old_string", "pattern", "path",
                 "agent_type", "last_assistant_message"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

tool_name = payload.get("tool_name", "")

# gitcommit_conventions.md:7 forbids hardcoding the gitcommit path (e.g.
# /usr/local/bin/gitcommit) verbatim - it may live in ~/.local/bin,
# /usr/bin, or elsewhere depending on the machine, and "it's always in
# PATH" per that same rule. Resolve it from PATH instead of a fixed list.
GITCOMMIT_RESOLVED = None
_which = shutil.which("gitcommit")
if _which:
    GITCOMMIT_RESOLVED = os.path.realpath(_which)


# The block exists so ordinary projects never inspect the commit wrapper. When
# the session's own git repo contains the wrapper (its source repo, including
# the installed clone the PATH symlink points into), the wrapper is the
# project's own code and must be readable and editable. Any error resolving the
# repo root leaves OWNING_REPO_ROOT unset, so the block stays in place.
OWNING_REPO_ROOT = None
if GITCOMMIT_RESOLVED:
    try:
        import subprocess

        _cwd = payload.get("cwd", "") or os.getcwd()
        _top = subprocess.run(
            ["git", "-C", _cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5, check=False,
        ).stdout.strip()
        if _top:
            _top = os.path.realpath(_top)
            if _top not in ("/", os.path.realpath(os.path.expanduser("~"))):
                if GITCOMMIT_RESOLVED.startswith(_top + os.sep):
                    OWNING_REPO_ROOT = _top
    except Exception:
        OWNING_REPO_ROOT = None


def is_gitcommit_path(path):
    if not path or not GITCOMMIT_RESOLVED:
        return False
    if OWNING_REPO_ROOT:
        return False
    resolved = os.path.realpath(path)
    return path == GITCOMMIT_RESOLVED or resolved == GITCOMMIT_RESOLVED


msg = (
    "BLOCKED: reading the gitcommit script file is forbidden.\n\n"
    "CLAUDE.md's Commit Workflow: \"Never read the gitcommit script file -\n"
    "it is pre-approved and trusted.\" It is invoked, never inspected."
)

if tool_name == "Read":
    file_path = payload.get("tool_input", {}).get("file_path", "") or ""
    if is_gitcommit_path(file_path):
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)
    sys.exit(0)

if tool_name == "Grep":
    grep_path = payload.get("tool_input", {}).get("path", "") or ""
    if is_gitcommit_path(grep_path):
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)
    sys.exit(0)

if tool_name != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
if not cmd or not re.search(r"gitcommit", cmd):
    sys.exit(0)

# Display/pager/editor verbs only — matches AI.md's "cat/less/head/etc."
# row (Part 6, Hook Scripts table). cp/diff read the file too but they
# are file-manipulation/comparison tools, not display tools, so they are
# out of this rule's scope per the audit's Priority 2 classification.
READ_VERBS = {"cat", "less", "more", "head", "tail", "vim", "vi", "nano",
              "view", "bat", "sed", "awk", "grep", "rg", "xxd", "od",
              "strings", "nl", "tac", "cut", "wc", "file", ".", "source"}

# `$(command -v gitcommit)`, `` `which gitcommit` ``, `$(type -P gitcommit)`
# and their whitespace variants all expand to the resolved gitcommit path.
RESOLVER_SUBST_RE = re.compile(
    r"(?:\$\(|`)\s*(?:\\?command\s+-v|\\?which|\\?type\s+-[pP])\s+\\?gitcommit\b"
)

for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub_cmd = sub_cmd.strip()
    if not sub_cmd:
        continue
    try:
        tokens = shlex.split(sub_cmd)
    except ValueError:
        tokens = sub_cmd.split()

    clean = []
    skipping_prefix = True
    for tok in tokens:
        if skipping_prefix:
            if tok in ("command", "env", "exec", "nohup", "time", "sudo", "doas"):
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                continue
            if tok.startswith("-"):
                continue
            skipping_prefix = False
        clean.append(tok.lstrip("\\"))

    if not clean:
        continue

    head = clean[0]
    if head not in READ_VERBS:
        continue

    # `cat $(command -v gitcommit)` never yields a literal path token — the
    # args tokenize as `$(command`, `-v`, `gitcommit)`, so the per-arg check
    # below sees no gitcommit path and the read goes through. Match the
    # resolver substitution itself against the raw sub-command instead.
    # Scoped to a read verb, so `gitcommit --dir $(pwd) all` is untouched.
    if RESOLVER_SUBST_RE.search(sub_cmd):
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)

    for arg in clean[1:]:
        if arg.startswith("-"):
            continue
        if is_gitcommit_path(arg):
            print(msg)
            sys.stderr.write(msg + "\n")
            sys.exit(2)

sys.exit(0)
PYEOF
