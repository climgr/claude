#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  zone-git-commit-push.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Saturday, August 29, 2026 00:00 EDT
# @@File             :  zone-git-commit-push.sh
# @@Description      :  PreToolUse hook: blocks raw `git commit`/`git push` everywhere, with no Local System Management Zone exception — `gitcommit` is the sole commit+push path always; a zone repo that must never push uses a `.no_push` file instead.
# @@Changelog        :  Allow `git -C <abs-dir> push --delete` (never --mirror) as the one raw push; every other raw push stays blocked. Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  git reset stays hard-denied via settings.json; force-push stays blocked everywhere via no-force-push.sh, including inside the zone.
# @@Resource         :  CLAUDE.md - Local System Management Zone
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Fail-open if python3 is missing — a broken hook exits 0 (no-op) so we never silently block every Bash call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'zone-git-commit-push.sh: required command not found: python3\n' >&2
  exit 0
fi

INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$INPUT_TMPFILE"' EXIT
printf '%s' "$INPUT" > "$INPUT_TMPFILE"

python3 - "$INPUT_TMPFILE" <<'PYEOF'
import json
import re
import shlex
import sys

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

if d.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = d.get("tool_input", {}).get("command", "") or ""
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

# Cheap pre-filter: nothing resembling git anywhere -> allow.
if not re.search(r"\bgit\b", cmd):
    sys.exit(0)


GIT_GLOBAL_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def find_git_subcommand(tokens):
    # First non-flag token after "git", skipping the VALUE of any global
    # option that takes one (-C <path>, -c <k>=<v>, --git-dir <path>, etc.)
    # so `git -C /repo commit` cannot hide its subcommand from the scan.
    i = 1
    while i < len(tokens):
        tok = tokens[i]
        if tok in GIT_GLOBAL_OPTS_WITH_VALUE:
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        return tok
    return None


def is_scoped_delete_push(clean_tokens):
    # `git -C <abs-dir> push --delete <remote> <ref>`: a remote-ref delete scoped
    # to one named repo is the only raw push allowed. Every `-C` path must be
    # absolute, and `--mirror` (bulk ref wipe) never qualifies.
    c_dirs = []
    i = 1
    while i < len(clean_tokens):
        tok = clean_tokens[i]
        if tok == "-C":
            if i + 1 >= len(clean_tokens):
                return False
            c_dirs.append(clean_tokens[i + 1])
            i += 2
            continue
        if tok in GIT_GLOBAL_OPTS_WITH_VALUE:
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        break
    if i >= len(clean_tokens) or clean_tokens[i] != "push":
        return False
    if not c_dirs or not all(d.startswith("/") for d in c_dirs):
        return False
    args = clean_tokens[i + 1:]
    if "--mirror" in args:
        return False
    return any(a in ("--delete", "-d") for a in args)


def find_git_subcommand_kind(clean_tokens):
    # Expects argv of one sub-command with wrapper/env prefixes already stripped.
    # Returns "commit", "push", or None.
    if not clean_tokens or clean_tokens[0] != "git":
        return None
    sub = find_git_subcommand(clean_tokens)
    return sub if sub in ("commit", "push") else None


for sub in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub = sub.strip()
    if not sub:
        continue
    try:
        tokens = shlex.split(sub)
    except ValueError:
        tokens = sub.split()

    # Strip wrapper/alias-bypass prefixes and env assignments (any case):
    # \git, command git, env [KEY=VAL...] git, KEY=VAL git
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

    kind = find_git_subcommand_kind(clean)
    if kind == "commit":
        # Raw `git commit` bypasses gitcommit's automatic commit signing —
        # blocked everywhere, with no Local System Management Zone exception.
        msg = (
            "BLOCKED: raw `git commit` is forbidden everywhere, including inside the "
            "Local System Management Zone (~/Projects/local/system/**) — it bypasses "
            "automatic commit signing.\n\n"
            "The only sanctioned commit path is:\n"
            "  gitcommit --dir {project_dir} all\n\n"
            "See CLAUDE.md's Local System Management Zone section."
        )
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)
    if kind == "push" and is_scoped_delete_push(clean):
        continue
    if kind == "push":
        # Raw `git push` also has no Local System Management Zone exception —
        # `gitcommit` is the sole commit+push path everywhere; a zone repo that
        # must never push keeps a `.no_push` file instead of reaching for raw push.
        msg = (
            "BLOCKED: raw `git push` is forbidden everywhere, including inside the "
            "Local System Management Zone (~/Projects/local/system/**).\n\n"
            "The only sanctioned commit+push path is:\n"
            "  gitcommit --dir {project_dir} all\n\n"
            "The one raw push allowed is a scoped remote-ref delete:\n"
            "  git -C {project_dir} push --delete <remote> <ref>\n\n"
            "To prevent a zone repo from ever pushing, use a `.no_push` file instead "
            "of raw `git push` — see CLAUDE.md's Local System Management Zone section."
        )
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)

sys.exit(0)
PYEOF
