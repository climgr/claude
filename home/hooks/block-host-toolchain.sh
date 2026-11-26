#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611261300-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  block-host-toolchain.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Wednesday, May 14, 2026 00:00 EDT
# @@File             :  block-host-toolchain.sh
# @@Description      :  Claude Code PreToolUse hook — block direct host toolchain invocations and suggest the Docker equivalent
# @@Changelog        :  Binary execution also covers the make dev temp build ($BUILD_DIR/..., {tmpdir}/{org}/{name}-XXXXXX/...), and copying, moving, installing or symlinking binaries/ out is blocked (the templates' NEVER Copy or Symlink Binaries rule). Suggested docker runs now carry --cpu-shares, --no-healthcheck and a timeout ceiling (execution_hierarchy.md), and executing a built binary (binaries/, releases/) directly on the host is blocked with a Docker alternative (testing_conventions.md Binary Execution Rule). Also block govulncheck, cargo-clippy/clippy-driver, and ktlint/detekt on the host (Go/Rust/Android templates' No Host Toolchain rules). Earlier: __split_subcommands now reads the command over stdin instead of argv — a very long command line exceeded the kernel argv limit and the hook silently skipped enforcement.
#                        docker run; gradle/gradlew and the Android SDK tools now dispatch to
#                        casjaysdev/android:latest; suggested commands now honor the toolchain-image decision tree
#                        (project-declared image, then docker/Dockerfile.build, then the language default); the
#                        forbidden Ubuntu and Debian latest bases were replaced with a Debian slim base; the
#                        missing Node and Python cache mounts were added; the Rust template gained its sccache
#                        wrapper env flag; virsh, vagrant, distrobox, and nsenter are now exempt from Docker
#                        redirection; a script-collection and spec-collection exemption was added; the printed
#                        tempdir snippet now includes the parent directory creation step; and the suggested
#                        --name now derives from the git toplevel directory instead of the raw working directory.
#                        Post-implementation review caught a severe regression in the item-30 exemption: its
#                        fallback treated "no manifest at project root" alone as sufficient, exempting Ruby,
#                        Java/Gradle, and any other non-Go/Rust/Node/Python project (and manifest-in-subdirectory
#                        monorepos) from Docker-only enforcement entirely. Replaced with the actual structural
#                        signals from project_type_conventions.md (bin/ + root install.sh for script-collection;
#                        root holds only Markdown/metadata with no other *.sh/*.bash in the tree for
#                        spec-collection); also dropped an AI.md substring-match shortcut that produced a false
#                        positive on this repo's own AI.md (which names itself the disqualifying example for
#                        spec-collection in prose); also fixed two unescaped apostrophes in code comments that
#                        broke out of the surrounding bash single-quoted python3 -c string and would have made
#                        the hook fail to parse entirely.
# @@TODO             :  None
# @@Other            :  Commands mediated by docker/incus/podman/kubectl/virsh/vagrant/distrobox/nsenter are exempt; POSIX tools, perl/lua, python/python3 are never blocked, only their package managers; script-collection and spec-collection projects are exempt entirely.
# @@Resource         :  ~/.claude/memory/go_conventions.md, rust_conventions.md, tempdir_conventions.md, execution_hierarchy.md, dockerfile_conventions.md, node_typescript_conventions.md, python_conventions.md, project_type_conventions.md
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611261300-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -

# __require_cmd <name> — bail with a clear error if a required tool is missing.
# A broken hook must exit 0 (no-op) to avoid silently blocking every Bash call.
__require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'block-host-toolchain.sh: required command not found: %s\n' "$1" >&2
    exit 0
  fi
}

# __extract_command — read the JSON payload on stdin, return tool_input.command.
__extract_command() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    print("")
'
}

# __block <tool> <docker_cmd> <convention_ref>
# Emits the block message to BOTH stdout (Claude Code reads this as the block
# reason and feeds it back to Claude) and stderr (visible to the user in the
# terminal), then exits 2 to block the tool call.
#
# The stdout message includes a temp-directory reminder so Claude knows to
# mount build output into a proper temp dir, never into the project tree.
__block() {
  local tool="$1"
  local docker_cmd="$2"
  local ref="$3"
  local msg
  msg="BLOCKED: direct \`${tool}\` invocation is not allowed on the host.

Run inside Docker instead:

${docker_cmd}

Temp directory reminder: any build output or test artifacts must be written
to a temp volume, never into the project tree. Use the pattern:
  mkdir -p \"\${TMPDIR:-/tmp}/{project_org}\"
  \$(mktemp -d \"\${TMPDIR:-/tmp}/{project_org}/{internal_name}-XXXXXX\")
and mount it as an additional -v flag. See ~/.claude/memory/tempdir_conventions.md
"
  if [[ -n "$ref" ]]; then
    msg="${msg}
Convention: ${ref}"
  fi
  # stdout → Claude Code (block reason returned to Claude as context)
  printf '%s\n' "$msg"
  # stderr → user terminal
  printf '%s\n' "$msg" >&2
  exit 2
}

# - - - - - - - - - - - - - - - - - - - - - - - - -
__require_cmd python3
# - - - - - - - - - - - - - - - - - - - - - - - - -

# Resource limits applied to every suggested docker run (execution_hierarchy.md).
BLOCK_HOST_TOOLCHAIN_DOCKER_MEM="${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM:-4g}"
BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS="${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS:-2}"
BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES="${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES:-256}"
BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT="${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT:-3600}"

# __extract_cwd — read the JSON payload on stdin, return the tool_input cwd.
__extract_cwd() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("cwd", ""))
except Exception:
    print("")
'
}

# __toolchain_image <default_image> <project_dir> — resolve the toolchain
# image per dockerfile_conventions.md's decision tree: (1) an image declared
# by the project in AI.md/IDEA.md/SPEC.md, (2) project docker/Dockerfile.build
# if it exists, (3) the given language-default image.
__toolchain_image() {
  python3 -c '
import os, re, sys
default_image, project_dir = sys.argv[1], sys.argv[2]
declared = None
for name in ("AI.md", "IDEA.md", "SPEC.md"):
    path = os.path.join(project_dir, name)
    if not os.path.isfile(path):
        continue
    try:
        with open(path, "r", errors="ignore") as f:
            text = f.read()
    except OSError:
        continue
    m = re.search(r"(?im)^\s*(?:toolchain[_ -]?image|build[_ -]?image)\s*[:=]\s*(\S+)", text)
    if m:
        declared = m.group(1).strip("`\"'"'"'")
        break
if declared:
    print(declared)
elif os.path.isfile(os.path.join(project_dir, "docker", "Dockerfile.build")):
    root = project_dir.rstrip("/") or project_dir
    org = os.path.basename(os.path.dirname(root))
    name = os.path.basename(root)
    print(f"{org}/{name}:build")
else:
    print(default_image)
' "$1" "$2"
}

# __project_type_exempt <project_dir> — true (exit 0) when the project is a
# script-collection or spec-collection per project_type_conventions.md, both
# of which home/CLAUDE.md's Build & Execution section exempts from the
# Docker-only requirement this hook otherwise enforces.
__project_type_exempt() {
  python3 -c '
import os, sys
project_dir = sys.argv[1]

manifests = ("go.mod", "Cargo.toml", "package.json", "pyproject.toml")
if any(os.path.isfile(os.path.join(project_dir, m)) for m in manifests):
    sys.exit(1)

# Absence of a manifest is necessary but not sufficient for either type —
# project_type_conventions.md requires an actual structural signal too, not
# just "no manifest found" (that would wrongly exempt Ruby/Java/PHP/etc.
# projects, or a Go/Rust/Node/Python monorepo with its manifest in a
# subdirectory rather than at the git toplevel). A text search for the
# words "script-collection"/"spec-collection" in AI.md was deliberately
# rejected here — the AI.md Type sections use both words in prose that
# describes what does NOT qualify (see the AI.md in this very repo, which
# names itself as the disqualifying example for spec-collection), so a
# substring match produces false positives on the exact file meant to rule
# it out. Structural signals only, below.

# script-collection detection signals (project_type_conventions.md): a bin/
# directory of standalone entrypoints, driven by a root install.sh — the
# defining structural pair, not merely "no manifest".
has_bin = os.path.isdir(os.path.join(project_dir, "bin"))
has_install_sh = os.path.isfile(os.path.join(project_dir, "install.sh"))
if has_bin and has_install_sh:
    sys.exit(0)

# spec-collection detection signals: the project root holds only Markdown
# plus standard repo metadata (no src/bin/cmd/lib, no manifest — already
# ruled out above), and the only script anywhere in the tree, if any, is a
# deploy-only root install.sh. Any other *.sh/*.bash disqualifies it (that
# repo needs the test/lint gate for those scripts instead).
disqualifying_dirs = ("src", "bin", "cmd", "lib")
has_disqualifying_dir = any(
    os.path.isdir(os.path.join(project_dir, d)) for d in disqualifying_dirs
)
only_root_md_and_metadata = True
saw_md_file = False
allowed_root_files = {"install.sh"}
allowed_root_dirs = {".git", ".github"}
try:
    for entry in os.listdir(project_dir):
        full = os.path.join(project_dir, entry)
        if os.path.isdir(full):
            if entry in allowed_root_dirs:
                continue
            only_root_md_and_metadata = False
            break
        if entry.lower().endswith(".md"):
            saw_md_file = True
            continue
        if entry in allowed_root_files:
            continue
        if entry in (".gitignore", ".gitattributes"):
            continue
        only_root_md_and_metadata = False
        break
except OSError:
    only_root_md_and_metadata = False

# An empty (or metadata-only, no .md) directory is not positive evidence of
# spec-collection — it is the absence of information, not a structural
# signal per project_type_conventions.md, which requires the root to hold
# only .md files (a directory holding zero files satisfies that vacuously).
if not saw_md_file:
    only_root_md_and_metadata = False

has_other_script = False
if only_root_md_and_metadata and not has_disqualifying_dir:
    for root, dirs, files in os.walk(project_dir):
        dirs[:] = [d for d in dirs if d != ".git"]
        for f in files:
            if not (f.endswith(".sh") or f.endswith(".bash")):
                continue
            if root == project_dir and f == "install.sh":
                continue
            has_other_script = True
            break
        if has_other_script:
            break

is_spec_collection = (
    only_root_md_and_metadata
    and not has_disqualifying_dir
    and not has_other_script
)
if is_spec_collection:
    sys.exit(0)

sys.exit(1)
' "$1"
}

# __split_subcommands <cmd> — emit one NUL-terminated record per sub-command,
# each record being "<first_word>\x1f<sub_command>", splitting on ; & && || |
# and newlines so container-runtime exemptions apply per sub-command, never to
# the whole compound string (a leading "docker run ..." must not exempt a
# trailing "; go build").
#
# The split is shell-aware: backslash-newline continuations are joined first,
# operators inside single/double quotes or $(...) substitutions never split
# (so `docker run ... sh -c "go vet && go build"` stays ONE sub-command and
# keeps its container-runtime exemption), and heredoc bodies are dropped so
# their content is never inspected as host commands.
#
# The first word is computed here, in this same single python3 pass, rather
# than by a per-sub-command helper: spawning one interpreter per sub-command
# cost ~1.5s each and pushed this hook past its 10s settings.json timeout on
# any pipeline of roughly a dozen segments, turning a valid command into a
# "hook error" for the user.
__split_subcommands() {
  python3 -c '
import re, sys

# first_word — strip leading KEY=VALUE env assignments, house-style alias-safe
# backslashes, and shell wrapper prefixes, then return the first executable
# token. Handles: CGO_ENABLED=0 go build · \go build · command go build ·
# timeout 600 go build · env -i go build — \go and go are the SAME command
# (backslash only skips aliases) so policy must apply identically.
def first_word(sub):
    text = sub.strip()
    text = re.sub(r"^(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|" + chr(39) + r"[^" + chr(39) + r"]*" + chr(39) + r"|[^\s]*)\s+)*", "", text)
    wrappers = {"command", "builtin", "exec", "env", "nohup", "setsid",
                "nice", "ionice", "stdbuf", "time", "timeout", "sudo", "doas"}
    tokens = text.split()
    i = 0
    while i < len(tokens):
        t = tokens[i].lstrip("\\")
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
            continue
        if t in wrappers:
            i += 1
            # skip the wrapper flags and duration/priority arguments (timeout 600, nice -n 10)
            while i < len(tokens) and (tokens[i].startswith("-") or re.fullmatch(r"[0-9]+(\.[0-9]+)?[smhd]?", tokens[i])):
                i += 1
            continue
        return t
    return ""

SQ = chr(39)
DQ = chr(34)
# stdin, never argv: a very long command line would exceed the kernel per-argument
# limit, python3 would fail to launch, and the hook would silently skip enforcement.
cmd = sys.stdin.buffer.read().decode("utf-8", "replace")
# join backslash-newline continuations into one logical line
cmd = re.sub(r"\\\n\s*", " ", cmd)
# drop heredoc BODY lines so data is not treated as sub-commands; (?<!<)(?!<) avoids matching here-strings <<<
# bodies fed to a HOST shell (bash <<EOF) stay scanned - they execute on the host;
# container/VM-mediated shells (docker exec -i c bash <<EOF) run in the guest and are exempt
heredoc_shells = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash"}
heredoc_container_tools = {"docker", "docker-compose", "podman", "podman-compose",
                           "kubectl", "incus", "lxc", "machinectl", "systemd-nspawn",
                           "vagrant", "multipass", "distrobox", "toolbox", "virsh",
                           "nsenter", "chroot"}
kept = []
delim = None
for line in cmd.split("\n"):
    if delim is not None:
        if line.strip() == delim:
            delim = None
        continue
    m = re.search(r"(?<!<)<<(?!<)-?\s*[\x27\x22]?([A-Za-z_][A-Za-z0-9_]*)", line)
    if m:
        head = {t.rsplit("/", 1)[-1].lstrip("\\") for t in line[: m.start()].split()}
        if head & heredoc_container_tools or not (head & heredoc_shells):
            delim = m.group(1)
    kept.append(line)
cmd = "\n".join(kept)
# quote- and $()-aware operator scan
subs = []
buf = []
quote = None
depth = 0
i = 0
n = len(cmd)
while i < n:
    c = cmd[i]
    if quote is not None:
        if quote == DQ and c == "\\" and i + 1 < n:
            buf.append(cmd[i:i + 2])
            i += 2
            continue
        if c == quote:
            quote = None
        buf.append(c)
        i += 1
        continue
    if c == SQ or c == DQ:
        quote = c
        buf.append(c)
        i += 1
        continue
    if c == "\\" and i + 1 < n:
        buf.append(cmd[i:i + 2])
        i += 2
        continue
    if cmd.startswith("$(", i):
        depth += 1
        buf.append("$(")
        i += 2
        continue
    if depth > 0 and c == "(":
        depth += 1
        buf.append(c)
        i += 1
        continue
    if depth > 0 and c == ")":
        depth -= 1
        buf.append(c)
        i += 1
        continue
    if depth == 0 and c in ";&|\n":
        subs.append("".join(buf))
        buf = []
        i += 1
        while i < n and cmd[i] in ";&|":
            i += 1
        continue
    buf.append(c)
    i += 1
subs.append("".join(buf))
for sub in subs:
    sub = sub.strip()
    if sub:
        sys.stdout.write(first_word(sub) + "\x1f" + sub + "\0")
'
}

BLOCK_HOST_TOOLCHAIN_INPUT="$(cat)"
BLOCK_HOST_TOOLCHAIN_FULL_CMD="$(printf '%s' "$BLOCK_HOST_TOOLCHAIN_INPUT" | __extract_command)"
[[ -z "$BLOCK_HOST_TOOLCHAIN_FULL_CMD" ]] && exit 0

# Resolve the project root from the tool_input cwd (fall back to $PWD), so
# --name and the toolchain-image lookup use the git toplevel basename, never
# a raw $PWD basename that changes with the invoking subdirectory.
BLOCK_HOST_TOOLCHAIN_CWD="$(printf '%s' "$BLOCK_HOST_TOOLCHAIN_INPUT" | __extract_cwd)"
[[ -z "$BLOCK_HOST_TOOLCHAIN_CWD" ]] && BLOCK_HOST_TOOLCHAIN_CWD="$PWD"
BLOCK_HOST_TOOLCHAIN_PROJECT_DIR="$(cd "$BLOCK_HOST_TOOLCHAIN_CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
[[ -z "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR" ]] && BLOCK_HOST_TOOLCHAIN_PROJECT_DIR="$BLOCK_HOST_TOOLCHAIN_CWD"
BLOCK_HOST_TOOLCHAIN_PROJECT_NAME="${BLOCK_HOST_TOOLCHAIN_PROJECT_DIR##*/}"

# script-collection / spec-collection projects are exempt from the
# Docker-only Build & Execution requirement entirely (home/CLAUDE.md); skip
# all toolchain-blocking logic for them.
if __project_type_exempt "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR"; then
  exit 0
fi

# Inspect every sub-command independently; __block exits 2 on the first violation.
# -d '' consumes NUL-delimited records so a quoted multi-line payload (docker run ... sh -c with
# literal newlines) arrives as ONE sub-command instead of being re-split line by line.
# Each record is "<first_word>\x1f<sub_command>", both produced by the same python3 pass.
while IFS= read -r -d '' BLOCK_HOST_TOOLCHAIN_REC; do

BLOCK_HOST_TOOLCHAIN_FIRST="${BLOCK_HOST_TOOLCHAIN_REC%%$'\x1f'*}"
CMD="${BLOCK_HOST_TOOLCHAIN_REC#*$'\x1f'}"

# Sub-commands already mediated by a container/VM runtime are exempt at this
# layer. virsh/vagrant/distrobox/nsenter are exempt on any invocation, not
# just exec/run/shell subcommands — the whole command is already at or above
# the Docker tier in execution_hierarchy.md's QEMU/KVM > Incus > Docker > host
# order, matching the container-prefix recognition in __split_subcommands.
case "$CMD" in
  docker\ exec\ *|docker\ run\ *|docker\ compose\ exec\ *|docker\ compose\ run\ *|\
  docker-compose\ exec\ *|docker-compose\ run\ *|\
  incus\ exec\ *|incus\ shell\ *|lxc\ exec\ *|\
  podman\ exec\ *|podman\ run\ *|\
  kubectl\ exec\ *|\
  virsh\ *|vagrant\ *|distrobox\ *|nsenter\ *)
    continue
    ;;
esac

[[ -z "$BLOCK_HOST_TOOLCHAIN_FIRST" ]] && continue

# Normalise: strip any leading path component so /usr/local/go/bin/go → go
BLOCK_HOST_TOOLCHAIN_FIRST_BASE="${BLOCK_HOST_TOOLCHAIN_FIRST##*/}"

# Binary Execution Rule (testing_conventions.md): a built binary never runs
# directly on the host. Only the command word is inspected, so ls, cp,
# sha256sum and friends on binaries/ stay allowed; docker/incus runs were
# exempted above.
# Quotes and braces are stripped one character at a time (a } inside a bracket expression ends the
# expansion) so "$BUILD_DIR"/x and ${BUILD_DIR}/x match the same pattern as $BUILD_DIR/x.
BLOCK_HOST_TOOLCHAIN_FIRST_NORM="${BLOCK_HOST_TOOLCHAIN_FIRST//\"/}"
BLOCK_HOST_TOOLCHAIN_FIRST_NORM="${BLOCK_HOST_TOOLCHAIN_FIRST_NORM//\'/}"
BLOCK_HOST_TOOLCHAIN_FIRST_NORM="${BLOCK_HOST_TOOLCHAIN_FIRST_NORM//\{/}"
BLOCK_HOST_TOOLCHAIN_FIRST_NORM="${BLOCK_HOST_TOOLCHAIN_FIRST_NORM//\}/}"
case "$BLOCK_HOST_TOOLCHAIN_FIRST_NORM" in
  ./binaries/*|binaries/*|*/binaries/*|./releases/*|releases/*|\$BUILD_DIR/*|\$TMPDIR*/*-??????/*|/tmp/*/*-??????/*|/var/tmp/*/*-??????/*)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$(dirname -- ${BLOCK_HOST_TOOLCHAIN_FIRST})\":/app:ro \\
    alpine:latest /app/\$(basename -- ${BLOCK_HOST_TOOLCHAIN_FIRST}) ...

  or run the Phase 2 scripts, which handle this correctly: ./tests/run_tests.sh (basic tier), ./tests/incus.sh, ./tests/docker.sh"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" "~/.claude/memory/testing_conventions.md (Binary Execution Rule)"
    ;;
esac

# NEVER Copy or Symlink Binaries (the templates' Directory Rules): ln, cp, mv
# and install never take binaries/ as a source or link target. A copy inside a
# container (docker cp, incus file push) is exempt because those commands were
# exempted above. Only the arguments are inspected, so ls and sha256sum on
# binaries/ stay allowed.
case "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" in
  ln|cp|mv|install)
    read -r -a BLOCK_HOST_TOOLCHAIN_ARGS <<<"$CMD"
    BLOCK_HOST_TOOLCHAIN_HIT=0
    BLOCK_HOST_TOOLCHAIN_NARGS=0
    for BLOCK_HOST_TOOLCHAIN_ARG in "${BLOCK_HOST_TOOLCHAIN_ARGS[@]:1}"; do
      case "$BLOCK_HOST_TOOLCHAIN_ARG" in -*) continue ;; esac
      BLOCK_HOST_TOOLCHAIN_NARGS=$((BLOCK_HOST_TOOLCHAIN_NARGS + 1))
      BLOCK_HOST_TOOLCHAIN_ARG_NORM="${BLOCK_HOST_TOOLCHAIN_ARG//\"/}"
      BLOCK_HOST_TOOLCHAIN_ARG_NORM="${BLOCK_HOST_TOOLCHAIN_ARG_NORM//\'/}"
      BLOCK_HOST_TOOLCHAIN_ARG_NORM="${BLOCK_HOST_TOOLCHAIN_ARG_NORM//\{/}"
      BLOCK_HOST_TOOLCHAIN_ARG_NORM="${BLOCK_HOST_TOOLCHAIN_ARG_NORM//\}/}"
      case "$BLOCK_HOST_TOOLCHAIN_ARG_NORM" in
        binaries/*|./binaries/*|*/binaries/*|\$BUILD_DIR/*)
          # for ln, any binaries/ argument; for cp/mv/install, the source (not the last argument)
          BLOCK_HOST_TOOLCHAIN_HIT=$BLOCK_HOST_TOOLCHAIN_NARGS
          BLOCK_HOST_TOOLCHAIN_HIT_ARG="$BLOCK_HOST_TOOLCHAIN_ARG"
          ;;
      esac
    done
    if [[ "$BLOCK_HOST_TOOLCHAIN_HIT" -gt 0 ]] \
      && { [[ "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" = "ln" ]] || [[ "$BLOCK_HOST_TOOLCHAIN_HIT" -lt "$BLOCK_HOST_TOOLCHAIN_NARGS" ]]; }; then
      BLOCK_HOST_TOOLCHAIN_COPY_MSG="  Binaries are never copied, moved, installed or symlinked; they stay in binaries/ (build output)
  until CI/CD or make release stages them. Run the binary inside a container or use the Phase 2 scripts:
  ./tests/run_tests.sh, ./tests/incus.sh, ./tests/docker.sh"
      __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_COPY_MSG" "~/.claude/memory/testing_conventions.md (Binary Execution Rule)"
    fi
    ;;
esac

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Toolchain dispatch
#
# Image selection: prefer :alpine; fall back to :debian or :latest when no
# Alpine variant exists. Never pin a specific version number.
#
# NOT blocked (pure POSIX / system / infra tools — always allowed on host):
#   make, ninja, curl, wget, jq, yq, grep, sed, awk, find, sort, git, ssh,
#   rsync, docker, podman, incus, kubectl, helm, openssl, bash, sh,
#   python / python3 (scripting; pip/uv/poetry etc. are blocked separately),
#   perl / lua (system scripting; cpan/luarocks are blocked separately),
#   systemctl, journalctl, ps, kill, df, du, tar, zip, unzip, …
# - - - - - - - - - - - - - - - - - - - - - - - - -

case "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" in

  # ── Go ────────────────────────────────────────────────────────────────────
  go|gofmt|goimports|golangci-lint|govulncheck|gopls|godoc)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -v \"\${GO_CACHE:-\${HOME}/go/pkg/mod}\":/usr/local/share/go/pkg/mod \\
    -v \"\${GO_BUILD:-\${HOME}/.cache/go-build/\${PWD##*/}}\":/usr/local/share/go/cache \\
    -w /app \\
    -e CGO_ENABLED=0 \\
    -e GOFLAGS=-buildvcs=false \\
    $(__toolchain_image "casjaysdev/go:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" "~/.claude/memory/go_conventions.md"
    ;;

  # ── Rust ──────────────────────────────────────────────────────────────────
  cargo|cargo-clippy|clippy-driver|rustc|rustup|rustfmt|wasm-pack)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -v \"\${CARGO_CACHE:-\${HOME}/.cargo}\":/usr/local/share/cargo \\
    -v \"\${RUSTUP_CACHE:-\${HOME}/.rustup}\":/usr/local/share/rustup \\
    -v \"\${SCCACHE_CACHE:-\${HOME}/.cache/sccache}\":/root/.cache/sccache \\
    -v \"\${CARGO_TARGET:-\${HOME}/.cache/cargo-target/\${PWD##*/}}\":/app/target \\
    -w /app \\
    -e RUSTC_WRAPPER=sccache \\
    $(__toolchain_image "casjaysdev/rust:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" "~/.claude/memory/rust_conventions.md"
    ;;

  # ── Node / JavaScript / TypeScript runtime & package managers ─────────────
  # Mount target matches the Go/Rust arms' /app for internal consistency.
  # makefile_conventions.md documents /app as the project mount point while
  # node_typescript_conventions.md/python_conventions.md's own Docker Build
  # Pattern examples show /build - that source-doc mismatch is a separate,
  # unresolved documentation inconsistency; not fixed here, only not made worse.
  node|npm|npx|yarn|pnpm|corepack)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -v \"\${NPM_CACHE:-\${HOME}/.npm}\":/root/.npm \\
    -w /app \\
    $(__toolchain_image "node:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" "~/.claude/memory/node_typescript_conventions.md"
    ;;

  # ── TypeScript compiler and JS build / lint tools ─────────────────────────
  # All run inside node:alpine; most are installed via npx or project deps.
  tsc|ts-node|tsx|ts-blank|babel|webpack|rollup|vite|parcel|esbuild|\
  turbo|turborepo|eslint|prettier|biome|oxlint|jshint|standard|xo|\
  swc|tsup|unbuild|pkgroll)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -v \"\${NPM_CACHE:-\${HOME}/.npm}\":/root/.npm \\
    -w /app \\
    $(__toolchain_image "node:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'npm install --prefer-offline && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" "~/.claude/memory/node_typescript_conventions.md"
    ;;

  # ── Alt JS runtimes ───────────────────────────────────────────────────────
  bun)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "oven/bun:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "bun" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  deno)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "denoland/deno:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "deno" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Compile-to-JS / JS-ecosystem languages ────────────────────────────────
  # Elm, PureScript, ReScript, CoffeeScript, AssemblyScript — all installed
  # via npm; use node:alpine and install the toolchain inside the container.
  elm|spago|purs|rescript|coffee|asc)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "node:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'npm install --prefer-offline && npx ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Python — build / packaging tools ─────────────────────────────────────
  # python / python3 themselves are NOT blocked (scripting use is legitimate
  # and this hook uses python3 internally). Only package managers and build
  # frontends are blocked.
  pip|pip3|pip3.[0-9]*|uv|poetry|pipenv|hatch|pdm|tox|nox|flit|twine|\
  pyproject-build|setuptools|conda|mamba|micromamba)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -v \"\${PIP_CACHE:-\${HOME}/.cache/pip}\":/root/.cache/pip \\
    -v \"\${UV_CACHE:-\${HOME}/.cache/uv}\":/root/.cache/uv \\
    -w /app \\
    $(__toolchain_image "python:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" "~/.claude/memory/python_conventions.md"
    ;;

  # ── Ruby ──────────────────────────────────────────────────────────────────
  gem|bundle|bundler|rake|rspec|rubocop|standardrb|sorbet|srb)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "ruby:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Android (Gradle wrapper + SDK command-line tools) ────────────────────
  # Routed to casjaysdev/android:latest, never gradle:alpine — the Android SDK
  # tools require the Android toolchain image, not a bare JVM/Gradle image.
  # Source is mounted at /workspace, never over /opt/android-sdk (the image's
  # own SDK install path).
  gradle|gradlew|adb|sdkmanager|apksigner|zipalign|d8|r8|aapt2|ktlint|detekt)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -v \"\${HOME}/.gradle\":/root/.gradle \\
    -e GRADLE_USER_HOME=/workspace/.gradle \\
    -w /workspace \\
    $(__toolchain_image "casjaysdev/android:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" "~/.claude/memory/dockerfile_conventions.md"
    ;;

  # ── JVM build tools (Maven / Ant) ────────────────────────────────────────
  mvn|mvnw|ant)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -v \"\${HOME}/.m2\":/root/.m2 \\
    -w /workspace \\
    $(__toolchain_image "gradle:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Java / JDK tools ──────────────────────────────────────────────────────
  java|javac|jar|javap|jshell|jlink|jpackage|javadoc|javaws|\
  jmap|jstack|jinfo|jcmd|jps|jstat|jfr|jdb)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "eclipse-temurin:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── GraalVM native-image ──────────────────────────────────────────────────
  native-image|gu)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "ghcr.io/graalvm/native-image:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Kotlin ────────────────────────────────────────────────────────────────
  kotlin|kotlinc|kotlinc-jvm|kotlinc-js)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "eclipse-temurin:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache kotlin && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Scala / SBT ───────────────────────────────────────────────────────────
  scala|scalac|scala3|scalac3|sbt)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -v \"\${HOME}/.ivy2\":/root/.ivy2 \\
    -v \"\${HOME}/.sbt\":/root/.sbt \\
    -w /workspace \\
    $(__toolchain_image "eclipse-temurin:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache scala && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Clojure / Leiningen ───────────────────────────────────────────────────
  lein|clojure|clj|clj-kondo)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -v \"\${HOME}/.m2\":/root/.m2 \\
    -w /workspace \\
    $(__toolchain_image "clojure:tools-alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Groovy ────────────────────────────────────────────────────────────────
  groovy|groovyc|groovysh)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "groovy:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── PHP ───────────────────────────────────────────────────────────────────
  php|php[0-9]*|composer|phpunit|phpcs|phpmd|phpstan|psalm|phpbrew|phive)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "php:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── .NET / C# / F# / VB ──────────────────────────────────────────────────
  dotnet|msbuild|nuget|csc|fsc|vbc|dotnet-script|dotnet-ef)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "mcr.microsoft.com/dotnet/sdk:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Elixir / Erlang ───────────────────────────────────────────────────────
  mix|elixir|elixirc|erl|erlc|escript|rebar3|dialyzer)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "elixir:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Gleam (BEAM / Erlang VM language) ────────────────────────────────────
  gleam)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "ghcr.io/gleam-lang/gleam:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "gleam" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Haskell ───────────────────────────────────────────────────────────────
  # No official Alpine image — uses Debian-based :latest.
  ghc|ghci|runghc|runhaskell|cabal|stack|haddock|hoogle)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "haskell:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Swift ─────────────────────────────────────────────────────────────────
  # No official Alpine image — uses Ubuntu-based :latest.
  swift|swiftc|swift-package|swift-build|swift-test|swift-run)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "swift:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Dart / Flutter ────────────────────────────────────────────────────────
  # No official Alpine image — uses Debian-based :latest.
  dart|flutter|pub)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "dart:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Zig ───────────────────────────────────────────────────────────────────
  # Zig is in Alpine edge; no separate official Docker image.
  zig)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine:edge" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache zig && ${CMD}'"
    __block "zig" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Crystal ───────────────────────────────────────────────────────────────
  crystal|shards)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "crystallang/crystal:latest-alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── OCaml / OPAM / Dune ───────────────────────────────────────────────────
  ocaml|ocamlopt|ocamlfind|ocamlbuild|opam|dune)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "ocaml/opam:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── D language ────────────────────────────────────────────────────────────
  dmd|dub|ldc|ldc2|gdc|rdmd)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "dlangcommunity/docker-dmd:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Julia ─────────────────────────────────────────────────────────────────
  # No official Alpine image — uses Debian-based :latest.
  julia)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -v \"\${HOME}/.julia\":/root/.julia \\
    -w /workspace \\
    $(__toolchain_image "julia:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "julia" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── R ─────────────────────────────────────────────────────────────────────
  # No official Alpine image — uses Debian-based :latest.
  R|Rscript|renv)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "r-base:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Nim ───────────────────────────────────────────────────────────────────
  nim|nimble|nimgrep|nimpretty|testament)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "nimlang/nim:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── V language ────────────────────────────────────────────────────────────
  # Bare "v" is not blocked — it collides with a common shell alias name.
  vpm)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "vlang/vlang:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Odin ──────────────────────────────────────────────────────────────────
  # No official Docker image and no Alpine package — install from a Debian
  # slim base (never a :latest Ubuntu/Debian image, per dockerfile_conventions.md).
  odin)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "debian:bookworm-slim" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apt-get update && apt-get install -y odin && ${CMD}'"
    __block "odin" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Lua — package manager / compiler only ────────────────────────────────
  # lua itself is a common system scripting tool and is NOT blocked.
  luarocks|luac)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache lua5.4 lua5.4-dev luarocks5.4 && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Janet (small Lisp/C hybrid, in Alpine repos) ─────────────────────────
  janet|jpm)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache janet && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Fennel (Lisp dialect for Lua, in Alpine repos) ───────────────────────
  fennel)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache lua5.4 fennel && ${CMD}'"
    __block "fennel" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Perl — package managers / build tools only ───────────────────────────
  # perl itself is a system scripting tool and is NOT blocked.
  cpan|cpanm|cpm|carton|prove|plackup|morbo)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/app \\
    -w /app \\
    $(__toolchain_image "perl:alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Fortran ───────────────────────────────────────────────────────────────
  gfortran|flang|ifort|ifx|f77|f95|fort77)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache gfortran && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── COBOL ─────────────────────────────────────────────────────────────────
  cobc|cobcrun|cob-config)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache gnucobol && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Ada / GNAT ────────────────────────────────────────────────────────────
  gnat|gnatmake|gprbuild|gnatclean|gnatbind|gnatlink|gnatfind|gnatxref)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache gcc-gnat gnat && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Emscripten — C / C++ to WebAssembly ──────────────────────────────────
  emcc|em++|emcmake|emmake|emar|emranlib|emstrip|emrun|emdump|emsize)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "emscripten/emsdk:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Common Lisp ───────────────────────────────────────────────────────────
  # No Alpine image; use a Debian slim base, never :latest.
  sbcl|clisp|ecl|abcl|gcl|ccl|acl)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "debian:bookworm-slim" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apt-get update && apt-get install -y sbcl && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Racket ────────────────────────────────────────────────────────────────
  # No Alpine image; official image is Debian-based.
  racket|raco)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "racket/racket:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Scheme (Guile, Chicken, MIT, Chibi) ──────────────────────────────────
  # No Alpine image for most; use a Debian slim base, never :latest.
  # Note: csi = Chicken Scheme Interpreter (csc conflicts with C# compiler).
  guile|chicken|chicken-install|chicken-status|csi|\
  mit-scheme|chibi-scheme|chezscheme|chez|petite-chez)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "debian:bookworm-slim" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apt-get update && apt-get install -y guile-3.0 && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Prolog ────────────────────────────────────────────────────────────────
  # No Alpine image; official SWI-Prolog image is Debian-based.
  swipl|swipl-ld|gprolog|yap|xsb|clingo|spass)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "swipl:latest" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    ${CMD}"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Bazel / Bazelisk ──────────────────────────────────────────────────────
  # No Alpine image; use a Debian slim base, never :latest.
  bazel|bazelisk|ibazel)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -v \"\${HOME}/.cache/bazel\":/root/.cache/bazel \\
    -w /workspace \\
    $(__toolchain_image "debian:bookworm-slim" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apt-get update && apt-get install -y bazel && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── C / C++ compilers ────────────────────────────────────────────────────
  gcc|g++|cc|c++|clang|clang++|clang-[0-9]*|clang++-[0-9]*|\
  x86_64-linux-gnu-gcc|x86_64-linux-gnu-g++|\
  aarch64-linux-gnu-gcc|aarch64-linux-gnu-g++|\
  arm-linux-gnueabihf-gcc|arm-linux-gnueabihf-g++|\
  riscv64-linux-gnu-gcc|riscv64-linux-gnu-g++)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache build-base && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── C / C++ build generators and configuration tools ─────────────────────
  # make and ninja are NOT blocked — they act as build runners, not compilers,
  # and make drives Docker-based builds in this project.
  cmake|meson|autoconf|automake|autoreconf|configure)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache build-base cmake && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

  # ── Assembler / linker (part of C/C++ toolchain) ─────────────────────────
  # strip is not blocked — settings.json allowlists it and it is used on non-C artifacts.
  as|ld|ar|ranlib|objcopy)
    BLOCK_HOST_TOOLCHAIN_DOCKER_CMD="  timeout -k 30 ${BLOCK_HOST_TOOLCHAIN_DOCKER_TIMEOUT} docker run --rm --no-healthcheck \\
    --name \"${BLOCK_HOST_TOOLCHAIN_PROJECT_NAME}-\$(tr -dc 'a-z0-9' </dev/urandom | head -c8)\" \\
    --memory=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_MEM}\" --cpus=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPUS}\" --cpu-shares=\"${BLOCK_HOST_TOOLCHAIN_DOCKER_CPU_SHARES}\" \\
    -v \"\$PWD\":/workspace \\
    -w /workspace \\
    $(__toolchain_image "alpine" "$BLOCK_HOST_TOOLCHAIN_PROJECT_DIR") \\
    sh -c 'apk add --no-cache build-base binutils && ${CMD}'"
    __block "$BLOCK_HOST_TOOLCHAIN_FIRST_BASE" "$BLOCK_HOST_TOOLCHAIN_DOCKER_CMD" ""
    ;;

esac

done < <(printf '%s' "$BLOCK_HOST_TOOLCHAIN_FULL_CMD" | __split_subcommands)

exit 0
