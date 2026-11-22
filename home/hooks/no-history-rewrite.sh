#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-history-rewrite.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 16:00 EDT
# @@File             :  no-history-rewrite.sh
# @@Description      :  PreToolUse hook: blocks destructive/history-rewriting git ops everywhere — a hook can only block, not interactively confirm.
# @@Changelog        :  Allow `git -C <abs-dir> push --delete` (never --mirror) and `git -C <abs-dir> stash drop`; stash clear and every unscoped form stay blocked. Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  git rebase --abort/--continue/--skip are exempt — they resolve an already-started rebase rather than starting a new history rewrite.
# @@Resource         :  local_system_zone.md - "Still hard - no exception, ever"
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# A broken hook must fail OPEN (exit 0) so it never silently blocks every Bash call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'no-history-rewrite.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

NO_HISTORY_REWRITE_INPUT="$(cat)"

NO_HISTORY_REWRITE_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$NO_HISTORY_REWRITE_INPUT_TMPFILE"' EXIT
printf '%s' "$NO_HISTORY_REWRITE_INPUT" > "$NO_HISTORY_REWRITE_INPUT_TMPFILE"

python3 - "$NO_HISTORY_REWRITE_INPUT_TMPFILE" <<'PYEOF'
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

# Cheap pre-filter: nothing resembling git/filter-repo anywhere -> allow.
if not re.search(r"\bgit\b|\bfilter-repo\b|\bfilter-branch\b", cmd):
    sys.exit(0)


def has_force_flag(tokens):
    for tok in tokens:
        if tok in ("-f", "--force"):
            return True
        if re.match(r"^-[a-zA-Z]*f[a-zA-Z]*$", tok):
            return True
    return False


def has_tag_delete_flag(tokens):
    # git tag has no -D form (only git branch does) — local_system_zone.md's
    # "Still hard" list names only `git tag -d`. Exact-flag
    # match only (-d/--delete), matching the branch-delete matcher's
    # precision — a combined-flag regex here would also false-match any
    # unrelated short flag that merely contains the letter d.
    for tok in tokens:
        if tok in ("-d", "--delete"):
            return True
    return False


# `git clean -fn`/`-f --dry-run` never deletes anything — it only lists what
# would be removed — so it carries none of the irreversible-data-loss risk
# CLAUDE.md's Verification & Safety section gates on; exempting it here is a
# deliberate carve-out, not a gap in the "git clean -f* blocked everywhere"
# rule (AI.md's no-history-rewrite.sh row, CLAUDE.md's Local System
# Management Zone "Still hard" list).
def is_dry_run(tokens):
    for tok in tokens:
        if tok in ("-n", "--dry-run"):
            return True
        if re.match(r"^-[a-zA-Z]*n[a-zA-Z]*$", tok):
            return True
    return False


GIT_GLOBAL_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def find_git_subcommand(rest):
    # First non-flag token, skipping the VALUE of any global option that
    # takes one (-C <path>, -c <k>=<v>, --git-dir <path>, etc.) so
    # `git -C /repo rebase` cannot hide its subcommand from the scan.
    i = 0
    while i < len(rest):
        tok = rest[i]
        if tok in GIT_GLOBAL_OPTS_WITH_VALUE:
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        return tok, i
    return None, -1


def has_abs_c_dir(pre_tokens):
    # True when the global options before the subcommand carry at least one
    # `-C <path>` and every such path is absolute — the `git -C {dir} ...` form
    # that scopes a delete or stash drop to one named repo.
    dirs = []
    i = 0
    while i < len(pre_tokens):
        tok = pre_tokens[i]
        if tok == "-C":
            if i + 1 >= len(pre_tokens):
                return False
            dirs.append(pre_tokens[i + 1])
            i += 2
            continue
        if tok in GIT_GLOBAL_OPTS_WITH_VALUE:
            i += 2
            continue
        i += 1
    return bool(dirs) and all(d.startswith("/") for d in dirs)


def violation(clean_tokens):
    # Expects argv of one sub-command with wrapper/env prefixes already stripped.
    if not clean_tokens:
        return None

    if clean_tokens[0] in ("filter-repo", "git-filter-repo"):
        return "filter-repo rewrites every commit in history"

    if clean_tokens[0] != "git":
        return None

    rest = clean_tokens[1:]
    sub, sub_idx = find_git_subcommand(rest)
    if sub is None:
        return None
    args = rest[sub_idx + 1:]
    pre = rest[:sub_idx]

    if sub == "clean":
        if has_force_flag(args) and not is_dry_run(args):
            return "git clean -f discards untracked files irreversibly"
        return None

    if sub == "rebase":
        if any(a in ("--abort", "--continue", "--skip") for a in args):
            return None
        return "git rebase rewrites commit history"

    if sub == "branch":
        for a in args:
            if a == "-D" or re.match(r"^-[a-zA-Z]*D[a-zA-Z]*$", a):
                return "git branch -D force-deletes a branch, possibly losing unmerged commits"
        return None

    if sub == "tag":
        if has_tag_delete_flag(args):
            return "git tag -d deletes a tag pointer"
        return None

    if sub == "filter-branch":
        return "filter-branch rewrites every commit in history"

    if sub == "filter-repo":
        return "filter-repo rewrites every commit in history"

    if sub == "commit":
        if "--amend" in args:
            return "git commit --amend rewrites the previous commit"
        return None

    if sub == "stash":
        if args and args[0] == "clear":
            return "git stash clear discards every stashed entry (bulk clear stays blocked)"
        if args and args[0] == "drop" and not has_abs_c_dir(pre):
            return "git stash drop is allowed only as git -C {dir} stash drop"
        return None

    if sub == "push":
        if any(a == "--delete" or a == "-d" for a in args):
            if "--mirror" in args:
                return "git push --mirror --delete wipes remote refs in bulk"
            if not has_abs_c_dir(pre):
                return "git push --delete is allowed only as git -C {dir} push --delete"
        return None

    if sub == "update-ref":
        if args and args[0] == "-d":
            return "git update-ref -d discards a ref"
        return None

    if sub == "reflog":
        if args and args[0] == "expire":
            return "git reflog expire discards unreachable commit history"
        return None

    if sub == "gc":
        if any(a == "--prune" or a.startswith("--prune=") for a in args):
            return "git gc --prune permanently deletes unreachable objects"
        return None

    return None


# Examine each sub-command independently; newlines are separators too,
# so multi-line commands cannot hide a violation on line 2+.
for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub_cmd = sub_cmd.strip()
    if not sub_cmd:
        continue
    try:
        tokens = shlex.split(sub_cmd)
    except ValueError:
        tokens = sub_cmd.split()

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

    reason = violation(clean)
    if reason:
        msg = (
            f"BLOCKED: history-rewriting/destructive git operation ({reason}).\n\n"
            "git clean -f*, git rebase, git branch -D, git tag -d, git filter-repo,\n"
            "git filter-branch, git commit --amend, git stash clear, git update-ref -d,\n"
            "git reflog expire, and git gc --prune all discard commits/work or rewrite\n"
            "history, so they require explicit user\n"
            "confirmation before ever running - even inside the Local System\n"
            "Management Zone, where raw git is otherwise pre-authorized (see\n"
            "local_system_zone.md's \"Still hard\" list, and its catch-all: \"any\n"
            "other command that discards commits, discards uncommitted work, or\n"
            "rewrites history\").\n\n"
            "Allowed with an absolute repo path: git -C {dir} push --delete <remote>\n"
            "<ref> and git -C {dir} stash drop (never --mirror, never stash clear).\n\n"
            "Ask the user to confirm, then have them run the command manually -\n"
            "this hook cannot grant a one-time exception."
        )
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)

sys.exit(0)
PYEOF
