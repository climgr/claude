#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610070230-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-subagent-gates.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Wednesday, October 07, 2026 12:00 EDT
# @@File             :  no-subagent-gates.sh
# @@Description      :  PreToolUse hook: blocks make and test-runner commands when the top-level agent_id field is present, enforcing "agents never run tests, builds, or gates".
# @@Changelog        :  Log the caller agent_id, agent_type, and payload keys on every block, to diagnose a main session blocked in error.
# @@TODO             :  None
# @@Other            :  Mirrors no-subagent-commit.sh; the main session owns the test gate, the lint gate, and the commit.
# @@Resource         :  CLAUDE.md - Agent Usage - "Agents never run tests, builds, or gates"
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610070230-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Fail-open if python3 is missing — a broken hook exits 0 (no-op) so we never silently block every Bash call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'no-subagent-gates.sh: required command not found: python3\n' >&2
  exit 0
fi

INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$INPUT_TMPFILE"' EXIT
printf '%s' "$INPUT" > "$INPUT_TMPFILE"

python3 - "$INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import sys
import time

try:
    with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as _f:
        raw = _f.read()
    d = json.loads(raw, strict=False)
except Exception:
    sys.exit(0)

if not isinstance(d, dict):
    sys.exit(0)

for _field in ("tool_input", "tool_response"):
    if _field in d and not isinstance(d[_field], dict):
        d[_field] = {}

for _obj in (d, d.get("tool_input") or {}, d.get("tool_response") or {}):
    for _key in ("command", "file_path", "cwd", "session_id", "transcript_path",
                 "content", "new_string", "old_string", "pattern", "path",
                 "agent_type", "last_assistant_message"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

if d.get("tool_name", "") != "Bash":
    sys.exit(0)

# agent_id is present only on tool calls made from inside a subagent —
# absent for the main session. No agent_id -> not our concern.
if not d.get("agent_id", ""):
    sys.exit(0)

cmd = d.get("tool_input", {}).get("command", "") or ""
if not cmd:
    sys.exit(0)

HEREDOC_SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash"}
HEREDOC_CONTAINER_TOOLS = {"docker", "docker-compose", "podman", "podman-compose",
                           "kubectl", "incus", "lxc", "machinectl", "systemd-nspawn",
                           "vagrant", "multipass", "distrobox", "toolbox", "virsh",
                           "nsenter", "chroot"}
WRAPPER_PREFIXES = {"command", "env", "exec", "nohup", "time", "sudo", "doas"}
CONTAINER_HEADS = {"docker", "podman", "incus", "lxc", "nsenter", "chroot", "distrobox", "toolbox"}
BARE_RUNNERS = {"make", "gmake", "pytest", "py.test", "rspec", "phpunit", "ctest", "nosetests", "tox"}
JS_RUNNERS = {"npm", "yarn", "pnpm", "bun"}


def strip_heredoc_bodies(text):
    # Non-shell heredoc bodies are data, not commands - drop them before scanning
    # so a cat/tee/python3 heredoc that merely MENTIONS a blocked command is not a
    # false positive. Bodies fed to a host shell stay fully scanned. Fails open to
    # the original text on any parse error so scanning never silently weakens.
    try:
        out = []
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            out.append(line)
            delims = []
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

# Cheap pre-filter: nothing resembling a gate command anywhere -> allow.
if not re.search(r"\b(make|gmake|pytest|py\.test|rspec|phpunit|ctest|nosetests|tox|test|nextest|clippy|mvn|gradle|dotnet|mix)\b", cmd):
    sys.exit(0)


def has_pair(tokens, first, seconds):
    # True when `first` is directly followed by one of `seconds` (flags between
    # them are skipped so `go -C dir test` and `cargo +nightly test` still match).
    for idx, tok in enumerate(tokens):
        if tok != first:
            continue
        for nxt in tokens[idx + 1:idx + 6]:
            if nxt.startswith("-") or nxt.startswith("+"):
                continue
            if nxt in seconds:
                return True
            break
    return False


def is_gate(tokens):
    # Expects argv of one sub-command with wrapper/env prefixes already stripped.
    if not tokens:
        return False
    head = tokens[0].rsplit("/", 1)[-1]
    if head in BARE_RUNNERS:
        return True
    if head == "go":
        return has_pair(tokens, "go", {"test"})
    if head == "cargo":
        return has_pair(tokens, "cargo", {"test", "nextest", "clippy"})
    if head in JS_RUNNERS:
        if has_pair(tokens, head, {"test", "t", "tst"}):
            return True
        if has_pair(tokens, head, {"run", "run-script"}):
            idx = tokens.index(head)
            rest = [t for t in tokens[idx + 1:] if not t.startswith("-")]
            return len(rest) >= 2 and re.match(r"^(test|lint|build|check)(:|$)", rest[1]) is not None
        return False
    if head == "mvn" or head == "mvnw":
        return any(t in ("test", "verify", "install") for t in tokens[1:])
    if head in ("gradle", "gradlew"):
        return any(t in ("test", "check", "build") for t in tokens[1:])
    if head == "dotnet":
        return has_pair(tokens, "dotnet", {"test"})
    if head == "mix":
        return has_pair(tokens, "mix", {"test"})
    if head in CONTAINER_HEADS:
        # docker run/exec ... make test, podman exec ... go test, etc: the gate
        # runs inside the container but is still a gate the subagent launched.
        rest = tokens[1:]
        if any(t.rsplit("/", 1)[-1] in BARE_RUNNERS for t in rest):
            return True
        for first, seconds in (("go", {"test"}), ("cargo", {"test", "nextest", "clippy"}),
                               ("npm", {"test"}), ("yarn", {"test"}), ("pnpm", {"test"})):
            if has_pair(rest, first, seconds):
                return True
    return False


found = ""
for sub in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub = sub.strip()
    if not sub:
        continue
    try:
        tokens = shlex.split(sub)
    except ValueError:
        tokens = sub.split()

    # Strip wrapper/alias-bypass prefixes and env assignments (any case):
    # \make, command make, env [KEY=VAL...] make, KEY=VAL make
    clean = []
    skipping_prefix = True
    for tok in tokens:
        if skipping_prefix:
            if tok in WRAPPER_PREFIXES:
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                continue
            if tok.startswith("-"):
                continue
            skipping_prefix = False
        clean.append(tok.lstrip("\\"))

    if is_gate(clean):
        found = " ".join(clean[:4])
        break

if not found:
    sys.exit(0)

# Record who was blocked so a wrongly blocked main session can be diagnosed from the log.
try:
    log_dir = os.path.join(os.environ.get("TMPDIR") or "/tmp", "claude-hooks", "no-subagent-gates")
    os.makedirs(log_dir, exist_ok=True)
    log_name = re.sub(r"[^A-Za-z0-9_.-]", "_", d.get("session_id", "") or "unknown") + ".log"
    with open(os.path.join(log_dir, log_name), "a", encoding="utf-8") as lf:
        lf.write(json.dumps({
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "agent_id": d.get("agent_id", ""),
            "agent_type": d.get("agent_type", ""),
            "permission_mode": d.get("permission_mode", ""),
            "cwd": d.get("cwd", ""),
            "payload_keys": sorted(d.keys()),
            "matched": found,
            "command": (d.get("tool_input", {}).get("command", "") or "")[:200],
        }) + "\n")
except Exception:
    pass

agent_type = d.get("agent_type", "") or "unknown"
msg = (
    f"BLOCKED: subagents never run make, tests, or build/lint gates (agent_type: {agent_type}).\n"
    f"Command: {found}\n\n"
    "Edit the files in your scope and report back — the main session runs\n"
    "the test gate and lint gate once, after reviewing the whole diff.\n\n"
    "See CLAUDE.md's Agent Usage section: \"Agents never run tests, builds, or gates\"."
)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF
