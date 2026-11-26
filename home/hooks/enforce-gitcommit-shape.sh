#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611261500-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-gitcommit-shape.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 19:00 EDT
# @@File             :  enforce-gitcommit-shape.sh
# @@Description      :  PreToolUse Bash hook: blocks any commit-wrapper invocation not exactly `--dir <abs-path> all`, `--dir <abs-path> spec` or `--dir <abs-path> push` (CLAUDE.md's Commit Workflow).
# @@Changelog        :  Branch gate: a valid `--dir <abs-path> all|spec|push` is also blocked when that repo (our project shape: AI.md, SPEC.md, IDEA.md, CLAUDE.md or a root spec .md) is not on `main`, per the templates' Definition of Done; a repo with no commits yet and third-party repos are exempt. Earlier: Accept `--dir <abs-path> push` (bare `push` now blocked) and `spec`; block message lists every valid form and the absolute-path rule. Ignore shell redirections (2>&1, >/dev/null, >> log) after a valid invocation — they were counted as extra args and falsely blocked; decode stdin as UTF-8 with replacement and fail open on any parse exception.
# @@TODO             :  None
# @@Other              :  Does not apply to raw git commit/push (governed by zone-git-commit-push.sh instead); the commit wrapper has no zone exception anywhere.
# @@Resource         :  CLAUDE.md - Commit Workflow
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611261500-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'enforce-gitcommit-shape.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

ENFORCE_GITCOMMIT_SHAPE_INPUT="$(cat)"

ENFORCE_GITCOMMIT_SHAPE_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$ENFORCE_GITCOMMIT_SHAPE_INPUT_TMPFILE"' EXIT
printf '%s' "$ENFORCE_GITCOMMIT_SHAPE_INPUT" > "$ENFORCE_GITCOMMIT_SHAPE_INPUT_TMPFILE"

python3 - "$ENFORCE_GITCOMMIT_SHAPE_INPUT_TMPFILE" <<'PYEOF'
import json
import subprocess
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

if payload.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
if not cmd:
    sys.exit(0)

HEREDOC_SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash"}
HEREDOC_CONTAINER_TOOLS = {"docker", "docker-compose", "podman", "podman-compose",
                           "kubectl", "incus", "lxc", "machinectl", "systemd-nspawn",
                           "vagrant", "multipass", "distrobox", "toolbox", "virsh",
                           "nsenter", "chroot"}


def strip_heredoc_bodies(text):
    # Non-shell heredoc bodies are data, not commands - drop them before scanning
    # so a cat/tee/python3 heredoc that merely MENTIONS a blocked command is not a
    # false positive. Bodies fed to a host shell (bash <<EOF) stay fully scanned;
    # container/VM-mediated shells (docker exec -i c bash <<EOF) are exempt - the
    # body runs inside the disposable guest. Fails open to the original text on
    # any parse error so scanning never silently weakens.
    try:
        out = []
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            out.append(line)
            delims = []
            # A pipe, command substitution, or backtick on the line can route
            # a "data" heredoc body into a shell downstream of a non-shell
            # head (e.g. `cat <<EOF | bash`) - never elide on such lines.
            risky_line = bool(re.search(r"\||\$\(|`", line))
            for m in re.finditer(r"(?<!<)<<(?!<)-?\s*(['\"]?)(\w+)\1", line):
                if risky_line:
                    continue
                head = {t.rsplit("/", 1)[-1].lstrip("\\") for t in line[: m.start()].split()}
                if head & HEREDOC_CONTAINER_TOOLS or not (head & HEREDOC_SHELLS):
                    delims.append(m.group(2))
            i += 1
            for delim in delims:
                while i < len(lines):
                    if lines[i].strip() == delim:
                        out.append(lines[i])
                        i += 1
                        break
                    i += 1
        return "\n".join(out)
    except Exception:
        return text


cmd = strip_heredoc_bodies(cmd)

if not re.search(r"\bgitcommit\b", cmd):
    sys.exit(0)

violations = []
gate_failures = []

# Files that mark a repo as one of ours (project shape) or a claudemgr template
# repo (a root spec .md). A third-party repo being contributed to has none of
# these, so its own branch workflow is left alone (external_contributions.md).
NON_SPEC_MD = {
    "README.md", "LICENSE.md", "CHANGELOG.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md",
    "AUTHORS.md", "NOTICE.md", "TODO.md", "TODO.AI.md", "PLAN.md", "PLAN.AI.md",
}


def branch_gate(repo):
    # Definition of Done step 5: gitcommit runs only after the branch gate passes,
    # i.e. the repo is on main (work lands on main before any commit; branches and
    # stashes are local scratch). Fails open on any git error.
    try:
        if not os.path.isdir(os.path.join(repo, ".git")):
            return None
        names = os.listdir(repo)
        ours = any(n in names for n in ("AI.md", "SPEC.md", "IDEA.md", "CLAUDE.md")) or any(
            n.endswith(".md") and n not in NON_SPEC_MD for n in names
        )
        if not ours:
            return None
        head = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "-q", "HEAD"], capture_output=True, timeout=15)
        if head.returncode != 0:
            return None
        cur = subprocess.run(["git", "-C", repo, "branch", "--show-current"], capture_output=True, timeout=15)
        if cur.returncode != 0:
            return None
        branch = cur.stdout.decode("utf-8", "replace").strip()
        if branch == "main":
            return None
        return f"{repo} is on {branch or 'a detached HEAD'}, not main"
    except (OSError, subprocess.SubprocessError):
        return None


for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub_cmd = sub_cmd.strip()
    if not sub_cmd:
        continue
    try:
        tokens = shlex.split(sub_cmd)
    except ValueError:
        tokens = sub_cmd.split()

    # Strip wrapper/alias-bypass prefixes and env assignments (any case):
    # \gitcommit, command gitcommit, env [KEY=VAL...] gitcommit, KEY=VAL gitcommit
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

    if not clean or clean[0] != "gitcommit":
        continue

    # Drop shell redirections (`2>&1`, `>/dev/null`, `>> log`, `< in`, a bare
    # `>` plus its target) so a valid invocation whose output is merely
    # redirected or piped is not reported as a disallowed argument shape.
    args = []
    skip_target = False
    for tok in clean[1:]:
        if skip_target:
            skip_target = False
            continue
        redir = re.match(r"^(\d*|&)(>>?|<)(&?\d*|.*)$", tok)
        if redir:
            skip_target = not redir.group(3)
            continue
        args.append(tok)

    # Valid invocations: gitcommit --dir <path> all | spec | push
    # (`spec` commits only markdown files: AI.md, SPEC.md, IDEA.md, etc.;
    # `push` is the push-retry form after an offline push failure)
    # {dir} must be an absolute path (CLAUDE.md's Commit Workflow) — a
    # relative --dir value is a disallowed shape, not just a missing arg.
    if (
        len(args) == 3
        and args[0] == "--dir"
        and args[2] in ("all", "spec", "push")
        and args[1]
        and args[1].startswith("/")
    ):
        gate_msg = branch_gate(args[1])
        if gate_msg:
            gate_failures.append(gate_msg)
        continue

    violations.append(sub_cmd)

if gate_failures and not violations:
    gate_text = (
        "BLOCKED: branch gate failed - gitcommit runs only from main.\n\n"
        + "\n".join(f"  {g}" for g in gate_failures)
        + "\n\nWork lands on main before any commit (branches and stashes are local scratch and are never\n"
        "pushed). Merge or move the work onto main, switch to main, then retry. A branch gate failure is a\n"
        "named stop reason in the Definition of Done: report it instead of working around it."
    )
    print(gate_text)
    sys.stderr.write(gate_text + "\n")
    sys.exit(2)

if not violations:
    sys.exit(0)

msg = (
    "BLOCKED: gitcommit invoked with a disallowed argument shape.\n\n"
    "The only valid invocations (CLAUDE.md's Commit Workflow) are:\n"
    "  gitcommit --dir {project_dir} all\n"
    "  gitcommit --dir {project_dir} spec   (markdown spec files only)\n"
    "  gitcommit --dir {project_dir} push   (push-retry, after an offline push failure)\n\n"
    "{project_dir} must be an absolute path (starting with /) - a relative\n"
    "path or an unexpanded placeholder such as <project> is rejected.\n\n"
    "Never use -m/--message or any other flag - gitcommit reads the commit\n"
    "message from .git/COMMIT_MESS, which must be written and re-read first.\n\n"
    "Violating command(s):\n"
)
for sub in violations:
    msg += f"  {sub}\n"

print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF
