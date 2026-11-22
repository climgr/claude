#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220004-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  validate-workflows.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, May 17, 2026 00:00 EDT
# @@File             :  validate-workflows.sh
# @@Description      :  PreToolUse hook: validate staged .github/workflows files with act --list before gitcommit
# @@Changelog        :  Honor the user-directed TEST_LINT_GATE_OVERRIDE=1 prefix (workflow validation is a lint-type gate; commit rules stay enforced elsewhere). Pin check now also covers .gitea/.forgejo workflows; new CI-policy block (container jobs need options --user 0:0, secret-scan job is host-runner with no container/needs, release/devel/beta/docker workflows need workflow_dispatch). Earlier: added the header block, timeout wrapping, setupmgr guard, --dir= parsing, and dual-stream BLOCKED output; fixed the license header field to WTFPL.
# @@TODO             :
# @@Other            :  Exit 0 = allow, exit 2 = block (message sent to Claude as context)
# @@Resource         :
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220004-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# __blocked <msg> — emit the block reason to BOTH stdout and stderr, then exit 2.
# On exit 2 Claude Code relays stderr to the model; stdout is shown to the user.
__blocked() {
    printf '%s\n' "$1"
    printf '%s\n' "$1" >&2
    exit 2
}

INPUT="$(cat)"

CMD="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
inp = data.get('tool_input', data.get('input', {}))
print(inp.get('command', ''))
" 2>/dev/null || true)"

[ -z "$CMD" ] && exit 0

# Only fire on gitcommit invocations
printf '%s' "$CMD" | grep -qE -- '\bgitcommit\b' || exit 0

# User-directed bypass: workflow validation is a lint-type gate, so the same
# TEST_LINT_GATE_OVERRIDE=1 prefix that skips the test and lint gates skips it too.
# Every commit rule (command shape, COMMIT_MESS coverage, doc-sync lines, no force
# push, signing) is enforced by other hooks and is not affected by this prefix.
printf '%s' "$CMD" | grep -qE -- '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*TEST_LINT_GATE_OVERRIDE=1[[:space:]]' && exit 0

# Extract --dir argument value (accepts both "--dir /path" and "--dir=/path")
PROJECT_DIR="$(printf '%s' "$CMD" | grep -oE -- '--dir(=|[[:space:]]+)[^[:space:]]+' | head -n1 | sed -E 's/^--dir(=|[[:space:]]+)//' || true)"
[ -z "$PROJECT_DIR" ] && exit 0
[ -d "$PROJECT_DIR" ] || exit 0

# Check if any .github/workflows/ YAML files are staged
ALL_STAGED_WORKFLOWS="$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | grep -E -- '^\.(github|gitea|forgejo)/workflows/.*\.ya?ml$' || true)"
[ -z "$ALL_STAGED_WORKFLOWS" ] && exit 0
# act only understands GitHub workflows; .gitea/.forgejo files get the text/policy checks only
STAGED_WORKFLOWS="$(printf '%s\n' "$ALL_STAGED_WORKFLOWS" | grep -E -- '^\.github/' || true)"

# Third-party action pinning (cicd_conventions.md): every `uses:` on a
# non-local, non-docker:// action must be pinned to a full 40-char commit
# SHA, never a mutable tag/branch. Pure text scan — no network needed.
UNPINNED=()
while IFS= read -r wf; do
    FULL_PATH="$PROJECT_DIR/$wf"
    [ -f "$FULL_PATH" ] || continue
    while IFS= read -r line; do
        REF="$(printf '%s' "$line" | grep -oE -- '@[^[:space:]"'"'"']+$' | sed 's/^@//')"
        [ -z "$REF" ] && continue
        printf '%s' "$REF" | grep -qE -- '^[0-9a-f]{40}$' && continue
        UNPINNED+=("$wf: $line")
    done < <(grep -oE -- '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[^[:space:]"'"'"']+' "$FULL_PATH" || true)
done <<< "$ALL_STAGED_WORKFLOWS"

if [ "${#UNPINNED[@]}" -gt 0 ]; then
    PIN_MSG='BLOCKED: unpinned third-party GitHub Action(s) in staged workflow file(s).

Every `uses:` must be pinned to a full 40-char commit SHA, never a tag/branch:
'
    for u in "${UNPINNED[@]}"; do
        PIN_MSG="${PIN_MSG}
  $u"
    done
    PIN_MSG="${PIN_MSG}

Pin each to its commit SHA (see cicd_conventions.md), then re-run gitcommit."
    __blocked "$PIN_MSG"
fi

# CI policy (cicd_conventions.md / PART 10 CI rules), parsed structurally.
# Fails open when PyYAML or python3 is missing or a file does not parse (act
# below reports syntax errors).
POLICY_MSG="$(
    while IFS= read -r wf; do
        [ -f "$PROJECT_DIR/$wf" ] && printf '%s\n' "$PROJECT_DIR/$wf"
    done <<< "$ALL_STAGED_WORKFLOWS" | python3 -c '
import os, sys
try:
    import yaml
except Exception:
    sys.exit(0)
out = []
for path in sys.stdin.read().split():
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            doc = yaml.safe_load(f)
    except Exception:
        continue
    if not isinstance(doc, dict):
        continue
    name = os.path.basename(path)
    triggers = doc.get("on", doc.get(True))
    if name in ("release.yml", "release.yaml", "devel.yml", "devel.yaml", "beta.yml", "beta.yaml", "docker.yml", "docker.yaml"):
        keys = triggers if isinstance(triggers, (dict, list)) else [triggers]
        if "workflow_dispatch" not in keys:
            out.append(name + ": channel/release workflow is missing the workflow_dispatch trigger")
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        continue
    for jid, job in jobs.items():
        if not isinstance(job, dict):
            continue
        container = job.get("container")
        if container:
            opts = container.get("options", "") if isinstance(container, dict) else ""
            if "--user 0:0" not in str(opts):
                out.append(name + ": job " + str(jid) + " has container: without options: \"--user 0:0\"")
        uses_tfh = any(isinstance(s, dict) and "trufflehog" in str(s.get("uses", "")).lower() for s in (job.get("steps") or []))
        if uses_tfh and (container or job.get("needs")):
            out.append(name + ": job " + str(jid) + " runs trufflehog but has container:/needs: (must be a host-runner job with no needs)")
print("\n".join(out))
' 2>/dev/null || true
)"
if [ -n "$POLICY_MSG" ]; then
    __blocked "BLOCKED: staged workflow file(s) violate the CI rules (cicd_conventions.md):

$POLICY_MSG

Fix them, then re-run gitcommit."
fi

[ -z "$STAGED_WORKFLOWS" ] && exit 0

# Hooks must never do network I/O (AI.md Part 6) — no auto-install here.
# If act is missing, block and tell the user to install it themselves.
if ! command -v act >/dev/null 2>&1; then
    __blocked 'BLOCKED: act is required to validate workflow files before committing.
act is not installed. Install it yourself (e.g. `setupmgr act`, or see
https://github.com/nektos/act), then retry — hooks never perform network
installs on their own.'
fi

# Validate each staged workflow file
FAILED_FILES=()
FAILED_OUTPUT=()

while IFS= read -r wf; do
    FULL_PATH="$PROJECT_DIR/$wf"
    [ -f "$FULL_PATH" ] || continue

    # timeout guards against an act hang freezing gitcommit forever
    OUTPUT="$(timeout 60 act --list -W "$FULL_PATH" 2>&1)" && STATUS=0 || STATUS=$?
    if [ "$STATUS" -eq 124 ]; then
        OUTPUT='act --list timed out after 60 seconds (failing closed)'
    fi
    if [ "$STATUS" -ne 0 ]; then
        FAILED_FILES+=("$wf")
        FAILED_OUTPUT+=("$OUTPUT")
    fi
done <<< "$STAGED_WORKFLOWS"

[ "${#FAILED_FILES[@]}" -eq 0 ] && exit 0

MSG='BLOCKED: GitHub Actions workflow validation failed.

The following staged workflow files did not pass `act --list`:
'
for i in "${!FAILED_FILES[@]}"; do
    MSG="${MSG}
  ${FAILED_FILES[$i]}
$(printf '%s\n' "${FAILED_OUTPUT[$i]}" | sed 's/^/    /')
"
done

MSG="${MSG}
Fix the errors above, then re-run gitcommit."
__blocked "$MSG"
