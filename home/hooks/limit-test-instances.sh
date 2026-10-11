#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610100001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  limit-test-instances.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Saturday, October 10, 2026 12:00 EDT
# @@File             :  limit-test-instances.sh
# @@Description      :  PreToolUse hook: blocks creating a VM, Incus instance, or detached container when this project already has CLAUDE_MAX_TEST_INSTANCES (default 4) running, and blocks launching instances from a loop.
# @@Changelog        :  New script
# @@TODO             :  None
# @@Other            :  Counts only instances whose name starts with the project directory name, the same prefix enforce-docker-rm.sh requires; fails open when no runtime answers.
# @@Resource         :  home/memory/execution_hierarchy.md - Instance budget
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610100001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Fail-open if python3 is missing — a broken hook exits 0 (no-op) so we never silently block every Bash call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'limit-test-instances.sh: required command not found: python3\n' >&2
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
import subprocess
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

if not isinstance(d.get("tool_input"), dict):
    sys.exit(0)

if d.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = d["tool_input"].get("command", "")
if not isinstance(cmd, str) or not cmd:
    sys.exit(0)

# Cheap pre-filter: nothing that creates an instance anywhere -> allow.
if not re.search(r"\bincus\b|\blxc\b|\bvirt-install\b|qemu-system|\bdocker\b|\bpodman\b", cmd):
    sys.exit(0)

WRAPPERS = {"command", "env", "exec", "nohup", "time", "sudo", "doas", "do", "then", "else", "{", "("}
LOOP_RE = re.compile(r"(^|[;&|\n]|\bdo\b|\bthen\b)\s*(for|while|until)\b|\bxargs\b|\bparallel\b|\bseq\b")


def creates_instance(tokens):
    # argv of one sub-command with wrapper/env prefixes already stripped.
    if not tokens:
        return False
    head = tokens[0].rsplit("/", 1)[-1]
    if head in ("xargs", "parallel"):
        # the launch is an argument of the fan-out tool: scan the rest for a creating call
        for idx, tok in enumerate(tokens[1:], start=1):
            if tok.rsplit("/", 1)[-1] in ("incus", "lxc", "docker", "podman", "virt-install") or tok.startswith("qemu-system"):
                return creates_instance(tokens[idx:])
        return False
    if head in ("incus", "lxc"):
        return len(tokens) > 1 and tokens[1] in ("launch", "init", "copy")
    if head == "virt-install" or head.startswith("qemu-system"):
        return True
    if head in ("docker", "podman"):
        if len(tokens) > 1 and tokens[1] == "run":
            return any(t in ("-d", "--detach") or (t.startswith("-") and not t.startswith("--") and "d" in t[1:])
                       for t in tokens[2:])
        return False
    return False


found = False
for sub in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub = sub.strip()
    if not sub:
        continue
    try:
        tokens = shlex.split(sub)
    except ValueError:
        tokens = sub.split()
    clean = []
    skipping = True
    for tok in tokens:
        if skipping:
            if tok in WRAPPERS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok) or tok.startswith("-"):
                continue
            skipping = False
        clean.append(tok.lstrip("\\"))
    if creates_instance(clean):
        found = True
        break

if not found:
    sys.exit(0)

try:
    cap = int(os.environ.get("CLAUDE_MAX_TEST_INSTANCES", "4"))
    if cap < 1:
        cap = 4
except ValueError:
    cap = 4

if LOOP_RE.search(cmd):
    msg = (
        "BLOCKED: do not launch instances from a loop, xargs, parallel, or seq.\n\n"
        f"A test needs at most {cap} instances (for example 1-2 servers and 2-3 clients),\n"
        "never one per distro or per package. Launch each instance in its own\n"
        "command so the instance cap is checked every time, and ask the user\n"
        "before going over it.\n\n"
        "See execution_hierarchy.md - Instance budget."
    )
    print(msg)
    sys.stderr.write(msg + "\n")
    sys.exit(2)

# Project scope = name of the git top-level dir (or cwd), the prefix enforce-docker-rm.sh requires.
cwd = d.get("cwd", "")
base = cwd if isinstance(cwd, str) and cwd else os.getcwd()
try:
    top = subprocess.run(["git", "-C", base, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=2)
    if top.returncode == 0 and top.stdout.strip():
        base = top.stdout.strip()
except Exception:
    pass
prefix = os.path.basename(base.rstrip("/")) + "-"

DEADLINE = time.monotonic() + 8


def names(argv):
    left = DEADLINE - time.monotonic()
    if left <= 0:
        return None
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=min(2, left))
        if out.returncode != 0:
            return None
        return [ln.strip() for ln in out.stdout.splitlines() if ln.strip()]
    except Exception:
        return None


running = set()
probes = (
    ["incus", "list", "--format", "csv", "-c", "ns"],
    ["lxc", "list", "--format", "csv", "-c", "ns"],
    ["virsh", "list", "--name"],
    ["docker", "ps", "--format", "{{.Names}}"],
    ["podman", "ps", "--format", "{{.Names}}"],
)
answered = False
for argv in probes:
    rows = names(argv)
    if rows is None:
        continue
    answered = True
    for row in rows:
        name, _, state = row.partition(",")
        if state and state.upper() != "RUNNING":
            continue
        if name.startswith(prefix):
            running.add(name)

# Fail open when no runtime answered: never block on a probe failure.
if not answered:
    sys.exit(0)

if len(running) < cap:
    sys.exit(0)

listing = "\n".join("  " + n for n in sorted(running))
msg = (
    f"BLOCKED: {len(running)} instances named {prefix}* are already running (cap {cap}).\n\n"
    f"{listing}\n\n"
    "A test needs a handful of instances (for example 1-2 servers and 2-3\n"
    "clients), never one per distro or per package. Reuse a running instance\n"
    "or remove one you no longer need by name, then retry. Ask the user\n"
    "before going over the cap; the cap is CLAUDE_MAX_TEST_INSTANCES.\n\n"
    "See execution_hierarchy.md - Instance budget."
)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF
