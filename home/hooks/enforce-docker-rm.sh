#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611261200-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-docker-rm.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Thursday, May 15, 2026 00:00 EDT
# @@File             :  enforce-docker-rm.sh
# @@Description      :  PreToolUse hook: block docker run without --rm/--name and incus launch/init without an instance name (prevents orphaned/untargetable containers)
# @@Changelog        :  incus launch/init now also requires the resource caps the template test scripts set (limits.cpu, limits.memory and, for containers, limits.cpu.priority) unless a profile is given. Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error. Never elide a heredoc body on a line with a pipe, $( or backtick (cat <<EOF | bash routes the body into a host shell), matching the other heredoc-aware hooks.
# @@TODO             :  None
# @@Other            :  --rm is exempt for detached (-d/--detach) containers so tests can inspect a crashed container's logs before teardown; --name stays mandatory either way
# @@Resource         :
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611261200-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# __require_cmd <name> - bail with a clear error if a required tool is missing.
# A broken hook exits 0 (no-op) so we never silently block every Bash call.
__require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'enforce-docker-rm.sh: required command not found: %s\n' "$1" >&2
    exit 0
  fi
}

__require_cmd python3

# $(cat) is required here — hook stdin is a socket; $(</dev/stdin) re-opens it and fails with ENXIO
ENFORCE_DOCKER_RM_INPUT="$(cat)"

ENFORCE_DOCKER_RM_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$ENFORCE_DOCKER_RM_INPUT_TMPFILE"' EXIT
printf '%s' "$ENFORCE_DOCKER_RM_INPUT" > "$ENFORCE_DOCKER_RM_INPUT_TMPFILE"

python3 - "$ENFORCE_DOCKER_RM_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import sys

with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as _f:
    raw = _f.read()
# strict=False accepts raw control characters (tabs/newlines) inside strings
# so a payload with an embedded tab cannot bypass the hook via a parse failure
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

tool = payload.get("tool_name", "")
if tool != "Bash":
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
    # so a cat/tee/python3 heredoc that merely MENTIONS "docker run" is not a
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

# Only inspect commands that contain docker run or incus launch|init
# (any whitespace: spaces, tabs, or backslash-newline continuations)
if not re.search(r"docker\s+run|incus\s+(launch|init)", cmd):
    sys.exit(0)

# Tokenise with shlex; split on pipes/semicolons/&&/newlines first
# so we examine each sub-command independently - newlines are separators too,
# so a multi-line command cannot hide a docker run on line 2+ (data heredoc
# bodies are already stripped above, so data lines never reach this split)
sub_cmds = re.split(r"[|;&\n]|\&\&|\|\|", cmd)

violations = []
for sub in sub_cmds:
    sub = sub.strip()
    # Does this sub-command invoke docker run?
    try:
        tokens = shlex.split(sub)
    except ValueError:
        tokens = sub.split()

    # Find "docker run" (possibly with env-var prefixes: KEY=VAL docker run)
    # Skip leading KEY=VALUE tokens
    clean = [t for t in tokens if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', t)]

    if not clean:
        continue

    # See through house-style alias-safe backslashes and shell wrapper
    # prefixes so \docker run, command docker run, and timeout 60 docker run
    # are enforced identically to the bare form. shlex already unescapes
    # \docker; the raw-split fallback does not.
    wrappers = {"command", "builtin", "exec", "env", "nohup", "setsid",
                "nice", "ionice", "stdbuf", "time", "timeout", "sudo", "doas"}
    while clean:
        head = clean[0].lstrip("\\")
        if head != clean[0]:
            clean[0] = head
            continue
        if head in wrappers:
            clean.pop(0)
            # skip the wrapper flags and duration/priority arguments (timeout 600)
            while clean and (clean[0].startswith("-")
                             or re.fullmatch(r"[0-9]+(\.[0-9]+)?[smhd]?", clean[0])):
                clean.pop(0)
            continue
        break

    if not clean:
        continue

    # Normalise: handle "docker  run" with extra spaces already split away
    if clean[0] not in ("docker", "incus"):
        continue

    # incus launch|init: an omitted instance name makes incus assign a
    # random one — unscoped and untargetable. Require an explicit name so
    # every instance is project-scoped, same policy as docker --name.
    if clean[0] == "incus":
        if len(clean) < 2 or clean[1] not in ("launch", "init"):
            continue
        if any(t in ("--help", "-h") for t in clean[2:]):
            continue
        # Positional tokens after the verb: first is the image, second is the
        # instance name. Skip flags, values of known value-taking flags, and
        # key=value tokens; unknown value-taking flags fail open — acceptable.
        value_flags = {
            "-p", "--profile", "-n", "--network", "-s", "--storage",
            "-t", "--type", "-d", "--device", "-c", "--config",
            "--target", "--project",
        }
        positionals = []
        skip_next = False
        for t in clean[2:]:
            if skip_next:
                skip_next = False
                continue
            if t.startswith("-"):
                if t in value_flags:
                    skip_next = True
                continue
            if "=" in t:
                continue
            positionals.append(t)
        if len(positionals) < 2:
            short = " ".join(clean[:6]) + (" ..." if len(clean) > 6 else "")
            violations.append((short, ["instance name"]))
        # Resource caps (execution_hierarchy.md): a test instance must not
        # starve the host, so every launch carries limits.cpu and
        # limits.memory, plus limits.cpu.priority for a container (the
        # priority key is container-only; a VM relies on the two caps). A
        # named profile may carry the limits, so it skips the check.
        cfg_keys = set()
        has_profile = False
        args = clean[2:]
        for idx, t in enumerate(args):
            if t in ("-p", "--profile") or t.startswith("--profile="):
                has_profile = True
            val = None
            if t in ("-c", "--config") and idx + 1 < len(args):
                val = args[idx + 1]
            elif t.startswith("--config="):
                val = t.split("=", 1)[1]
            if val and "=" in val:
                cfg_keys.add(val.split("=", 1)[0])
        if not has_profile:
            is_vm = "--vm" in args
            needed = ["limits.cpu", "limits.memory"] + ([] if is_vm else ["limits.cpu.priority"])
            lacking = [k for k in needed if k not in cfg_keys]
            if lacking:
                short = " ".join(clean[:6]) + (" ..." if len(clean) > 6 else "")
                violations.append((short, ["-c " + k + "=..." for k in lacking]))
        continue

    if len(clean) < 2 or clean[1] != "run":
        continue

    # Check for --rm in the argument list
    # Also accept --rm=true
    has_rm = any(t in ("--rm", "--rm=true") for t in clean[2:])

    # Detached (-d/--detach) containers are exempt from --rm: multi-container
    # integration testing (e.g. a server container a client container talks
    # to) needs the server to survive past its own foreground lifetime so its
    # logs/state can be inspected after a failure - --rm would wipe a crashed
    # container before that inspection happens. --name stays mandatory either
    # way, and anything launched without --rm must still be torn down
    # explicitly before the task ends (see execution_hierarchy.md's Cleanup
    # rules) - this exempts the flag, not the cleanup obligation.
    is_detached = any(t in ("-d", "--detach", "--detach=true") for t in clean[2:])

    # Check for --name in the argument list
    # Accept both "--name value" and "--name=value" forms
    has_name = any(t == "--name" or t.startswith("--name=") for t in clean[2:])

    # docker run --help and dry-run forms are fine
    is_help = any(t in ("--help", "-h") for t in clean[2:])

    if is_help:
        continue

    missing = []
    if not has_rm and not is_detached:
        missing.append("--rm")
    if not has_name:
        missing.append("--name")

    if missing:
        # Reconstruct a short form for the message
        short = " ".join(clean[:6]) + (" ..." if len(clean) > 6 else "")
        violations.append((short, missing))

if not violations:
    sys.exit(0)

msg = (
    "BLOCKED: container/instance launch missing required naming or resource caps.\n\n"
    "Every docker container must use --rm (self-remove on exit, no orphans) and\n"
    "--name {project_name}-XXXX; every incus instance must be launched with\n"
    "an explicit {project_name}-XXXX instance name (targeted cleanup by name).\n"
    "XXXX = random 8-char lowercase alphanumeric suffix.\n\n"
    "Every incus launch also carries resource caps so a test never starves the host:\n"
    "-c limits.cpu=2 -c limits.memory=4GiB (and -c limits.cpu.priority=2 for a\n"
    "container; a --vm has no priority key). A -p/--profile that sets them is fine.\n\n"
    "--rm is only exempt for detached (-d/--detach) containers - e.g. a server\n"
    "container a client container/test talks to, kept alive so its logs/state\n"
    "can be inspected after a failure. --name is still mandatory, and anything\n"
    "launched without --rm must still be explicitly `docker rm`'d before the\n"
    "task ends (see execution_hierarchy.md's Cleanup rules).\n\n"
    "Violating command(s):\n"
)
for short, missing in violations:
    msg += f"  {short}  (missing: {', '.join(missing)})\n"

msg += (
    "\nFix patterns:\n"
    "  docker run --rm --name \"{project_name}-$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" [OPTIONS] IMAGE [COMMAND]\n"
    "  docker run -d --name \"{project_name}-$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" [OPTIONS] IMAGE [COMMAND]  # integration test, --rm optional\n"
    "  incus launch IMAGE \"$(basename \"$PWD\")-$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" -c limits.cpu=2 -c limits.memory=4GiB -c limits.cpu.priority=2\n\n"
    "If this container must persist after the session (e.g. a user-requested dev environment),\n"
    "confirm with the user first and document the container name/ID."
)

print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF
