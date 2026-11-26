#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611261200-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  lint-agent-mark.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 22:00 EDT
# @@File             :  lint-agent-mark.sh
# @@Description      :  SubagentStop hook: records the lint gate satisfied when script-lint/go-lint/rust-lint reports a clean result.
# @@Changelog        :  Marker lines now carry the epoch (`epoch<TAB>project`) so enforce-test-lint-gate.sh can reject lint evidence older than the last code change. Earlier: realpath-normalise the recorded project path so it matches enforce-test-lint-gate.sh's realpath comparison under symlinked checkouts.
# @@TODO             :  None
# @@Other            :  Lint agents always end their report `: clean`, `: 0 new issue(s) found (M pre-existing...)`, or `: N new issue(s) found` — last_assistant_message is checked against that; a nonzero new-issue count skips the marker, pre-existing-only never does.
# @@Resource         :  CLAUDE.md - Commit Workflow (Lint gate), home/hooks/test-lint-mark.sh, home/hooks/enforce-test-lint-gate.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611261200-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  printf 'lint-agent-mark.sh: jq not found — lint agent mark disabled\n' >&2
  exit 0
fi

LINT_AGENT_MARK_INPUT="$(cat)"

# Fail open on an empty, malformed, or non-object payload. Without this, jq
# exits 4/5 and `set -e` propagates that code, which Claude Code surfaces as a
# "hook error" instead of the silent no-op Part 6 requires on a parse failure.
if ! printf '%s' "$LINT_AGENT_MARK_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  exit 0
fi

LINT_AGENT_MARK_TYPE=$(printf '%s' "$LINT_AGENT_MARK_INPUT" | jq -r 'try (.agent_type) catch "" // ""')
case "$LINT_AGENT_MARK_TYPE" in
  script-lint | go-lint | rust-lint) ;;
  *) exit 0 ;;
esac

LINT_AGENT_MARK_CWD=$(printf '%s' "$LINT_AGENT_MARK_INPUT" | jq -r 'try (.cwd) catch "" // ""')
LINT_AGENT_MARK_SESSION_ID=$(printf '%s' "$LINT_AGENT_MARK_INPUT" | jq -r 'try (.session_id) catch "" // ""')
[ -z "$LINT_AGENT_MARK_SESSION_ID" ] && exit 0

# script-lint/go-lint/rust-lint's own Output Format section ends every
# report with `: clean` (nothing at all), `: 0 new issue(s) found`
# (pre-existing findings only — non-blocking), or `: N new issue(s)
# found` (N >= 1, blocking) — one line per file/package/crate. Only
# issues on lines the current uncommitted changes actually touch are
# NEW; pre-existing findings must still be logged to TODO.AI.md by the
# calling session, but never block this gate on their own. A multi-file
# run must have zero NEW anywhere, so any nonzero "N new issue(s)
# found" line disqualifies the whole report.
LINT_AGENT_MARK_MSG=$(printf '%s' "$LINT_AGENT_MARK_INPUT" | jq -r 'try (.last_assistant_message) catch "" // ""')
printf '%s' "$LINT_AGENT_MARK_MSG" | grep -qE -- ': clean\b|: 0 new issue\(s\) found\b' || exit 0
printf '%s' "$LINT_AGENT_MARK_MSG" | grep -qE -- ': [1-9][0-9]* new issue\(s\) found\b' && exit 0

# The lint agent is routinely pointed at a repo other than the session cwd
# (e.g. a session run from a parent dir linting parent/{a,b,c}). Keying the
# marker on cwd alone recorded the wrong project and the gate then reported
# "lint gate has not run" for the repo that was actually linted. Collect every
# distinct git toplevel the agent demonstrably worked on: the cwd's, plus each
# existing absolute path named in the agent's own prompt (first entry of its
# transcript) or in its final report. Symlink-normalised so each line matches
# what enforce-test-lint-gate.sh compares against (os.path.realpath of the
# gitcommit --dir target), exactly.
LINT_AGENT_MARK_PROJECTS=()

__lint_agent_mark_add() {
  local p="$1" d top e
  [ -e "$p" ] || return 0
  if [ -d "$p" ]; then d="$p"; else d="${p%/*}"; fi
  [ -d "$d" ] || return 0
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || return 0
  top=$(realpath -- "$top" 2>/dev/null) || return 0
  [ -n "$top" ] || return 0
  for e in "${LINT_AGENT_MARK_PROJECTS[@]:-}"; do
    [ "$e" = "$top" ] && return 0
  done
  LINT_AGENT_MARK_PROJECTS+=("$top")
}

__lint_agent_mark_scan() {
  local text="$1" p n=0
  while IFS= read -r p; do
    p="${p%%.}"
    [ -n "$p" ] || continue
    n=$((n + 1))
    [ "$n" -gt 60 ] && break
    __lint_agent_mark_add "$p"
  done < <(printf '%s' "$text" | grep -oE -- '/[A-Za-z0-9._+@%~-]+(/[A-Za-z0-9._+@%~-]+)*' | sort -u)
}

if [ -n "$LINT_AGENT_MARK_CWD" ]; then
  __lint_agent_mark_add "$LINT_AGENT_MARK_CWD"
fi

LINT_AGENT_MARK_AGENT_TRANSCRIPT=$(printf '%s' "$LINT_AGENT_MARK_INPUT" | jq -r 'try (.agent_transcript_path) catch "" // ""')
if [ -n "$LINT_AGENT_MARK_AGENT_TRANSCRIPT" ] && [ -f "$LINT_AGENT_MARK_AGENT_TRANSCRIPT" ]; then
  LINT_AGENT_MARK_PROMPT=$(head -n 3 -- "$LINT_AGENT_MARK_AGENT_TRANSCRIPT" 2>/dev/null \
    | jq -r 'try (select(.type == "user") | .message.content | if type == "array" then map(.text? // "") | join(" ") else . end) catch ""' 2>/dev/null \
    | head -c 20000) || LINT_AGENT_MARK_PROMPT=""
  [ -n "$LINT_AGENT_MARK_PROMPT" ] && __lint_agent_mark_scan "$LINT_AGENT_MARK_PROMPT"
fi

__lint_agent_mark_scan "$LINT_AGENT_MARK_MSG"

[ "${#LINT_AGENT_MARK_PROJECTS[@]}" -eq 0 ] && exit 0

# This marker must be a deterministic, reconstructable path so
# enforce-test-lint-gate.sh's reader can look it up again by session_id
# alone (and so it matches the same path test-lint-mark.sh writes).
# session_id serves as the uniqueness key here. The namespace is
# claude-hooks, not a repo name — these hooks deploy to ~/.claude/hooks
# and run for every project's session, not just this one.
LINT_AGENT_MARK_DIR="${TMPDIR:-/tmp}/claude-hooks/test-lint-guard/${LINT_AGENT_MARK_SESSION_ID}"
mkdir -p "$LINT_AGENT_MARK_DIR"
chmod 700 "${TMPDIR:-/tmp}/claude-hooks/test-lint-guard" "$LINT_AGENT_MARK_DIR" 2>/dev/null || true

# Prune marker dirs older than 1 day — scoped only to this tool's own temp namespace
find "${TMPDIR:-/tmp}/claude-hooks/test-lint-guard" -maxdepth 1 -type d -mtime +1 -exec rm -rf -- {} + 2>/dev/null || true

LINT_AGENT_MARK_MARKER="$LINT_AGENT_MARK_DIR/lint"
for LINT_AGENT_MARK_PROJECT in "${LINT_AGENT_MARK_PROJECTS[@]}"; do
  printf '%s\t%s\n' "$(date +%s)" "$LINT_AGENT_MARK_PROJECT" >>"$LINT_AGENT_MARK_MARKER"
done

exit 0
