#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220003-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  spec-guard.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Monday, July 20, 2026 00:00 EDT
# @@File             :  spec-guard.sh
# @@Description      :  PreToolUse hook: block Edit/Write on project files until AI.md/SPEC.md was read this session
# @@Changelog        :  Also exempt CLAUDE.local.md; exempt AGENTS.md; a project with only CLAUDE.md or AGENTS.md is ungoverned (no broken-bootstrap block); user-directed bypass: a no-op Bash command prefixed SPEC_GUARD_ALLOW=1 records the session marker (also registered on PreToolUse Bash). Wrapped two long BLOCKED message strings onto multiple lines to fix line-length violations.
# @@TODO             :
# @@Other            :  Gates repos with AI.md/SPEC.md; exempt: meta/spec, AGENTS.md, README/LICENSE, COMMIT_MESS, env, .no_push; bypass: user-directed SPEC_GUARD_ALLOW=1 Bash prefix only.
# @@Resource         :  ~/.claude/memory/project_conventions.md
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220003-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -

set -euo pipefail

# Fail open when jq is missing — a broken hook must never block every Edit/Write
if ! command -v jq >/dev/null 2>&1; then
  printf 'spec-guard.sh: jq not found — spec guard disabled\n' >&2
  exit 0
fi

SPEC_GUARD_INPUT="$(cat)"

# Fail open on an empty, malformed, or non-object payload. Without this, jq
# exits 4/5 and `set -e` propagates that code, which Claude Code surfaces as a
# "hook error" instead of the silent no-op Part 6 requires on a parse failure.
if ! printf '%s' "$SPEC_GUARD_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  exit 0
fi

SPEC_GUARD_TOOL_NAME=$(printf '%s' "$SPEC_GUARD_INPUT" | jq -r 'try (.tool_name) catch "" // ""')
SPEC_GUARD_SESSION_ID=$(printf '%s' "$SPEC_GUARD_INPUT" | jq -r '.session_id // ""')
[ -z "$SPEC_GUARD_SESSION_ID" ] && exit 0

# User-directed bypass. When the user explicitly tells Claude to bypass the spec
# guard, Claude runs a no-op Bash command prefixed with SPEC_GUARD_ALLOW=1, for
# example `SPEC_GUARD_ALLOW=1 true` or `SPEC_GUARD_ALLOW=1 true /abs/project`.
# This hook then records the same session marker a Read of AI.md would, for the
# cwd project and for every absolute directory named after the prefix. Claude
# never uses the prefix on its own initiative.
if [ "$SPEC_GUARD_TOOL_NAME" = "Bash" ]; then
  SPEC_GUARD_COMMAND=$(printf '%s' "$SPEC_GUARD_INPUT" | jq -r 'try (.tool_input.command) catch "" // ""')
  case "$SPEC_GUARD_COMMAND" in
    "SPEC_GUARD_ALLOW=1 "*) ;;
    *) exit 0 ;;
  esac
  SPEC_GUARD_CWD=$(printf '%s' "$SPEC_GUARD_INPUT" | jq -r 'try (.cwd) catch "" // ""')
  read -r -a SPEC_GUARD_WORDS <<<"$SPEC_GUARD_COMMAND"
  SPEC_GUARD_DIRS=("$SPEC_GUARD_CWD")
  for SPEC_GUARD_WORD in "${SPEC_GUARD_WORDS[@]:1}"; do
    case "$SPEC_GUARD_WORD" in
      /*) [ -d "$SPEC_GUARD_WORD" ] && SPEC_GUARD_DIRS+=("$SPEC_GUARD_WORD") ;;
    esac
  done
  SPEC_GUARD_BYPASS_DIR="${TMPDIR:-/tmp}/claude-hooks/spec-guard/${SPEC_GUARD_SESSION_ID}"
  mkdir -p "$SPEC_GUARD_BYPASS_DIR"
  chmod 700 "${TMPDIR:-/tmp}/claude-hooks/spec-guard" "$SPEC_GUARD_BYPASS_DIR" 2>/dev/null || true
  for SPEC_GUARD_DIR in "${SPEC_GUARD_DIRS[@]}"; do
    [ -n "$SPEC_GUARD_DIR" ] || continue
    SPEC_GUARD_BYPASS_PROJECT=$(git -C "$SPEC_GUARD_DIR" rev-parse --show-toplevel 2>/dev/null) || continue
    SPEC_GUARD_BYPASS_PROJECT=$(realpath -- "$SPEC_GUARD_BYPASS_PROJECT" 2>/dev/null) || continue
    grep -qxF -- "$SPEC_GUARD_BYPASS_PROJECT" "$SPEC_GUARD_BYPASS_DIR/read" 2>/dev/null || printf '%s\n' "$SPEC_GUARD_BYPASS_PROJECT" >>"$SPEC_GUARD_BYPASS_DIR/read"
  done
  exit 0
fi

SPEC_GUARD_FILE_PATH=$(printf '%s' "$SPEC_GUARD_INPUT" | jq -r 'try (.tool_input.file_path) catch "" // ""')
[ -z "$SPEC_GUARD_FILE_PATH" ] && exit 0

# Exempt meta/spec files — these are pre-approved to edit without having read AI.md first
# (editing AI.md itself, or IDEA.md/SPEC.md/TODO/PLAN, is not "implementing against the spec")
case "$SPEC_GUARD_FILE_PATH" in
  */.git/* | */.claude/*) exit 0 ;;
esac
case "${SPEC_GUARD_FILE_PATH##*/}" in
  AI.md | IDEA.md | SPEC.md | CLAUDE.md | CLAUDE.local.md | AGENTS.md | TODO.AI.md | TODO.md | PLAN.AI.md | PLAN.md \
    | COMMIT_MESS | .env | app.env | default.env | .no_push | README.md | LICENSE.md)
    exit 0
    ;;
esac

SPEC_GUARD_PROJECT=$(git -C "${SPEC_GUARD_FILE_PATH%/*}" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Existence precedence: AI.md (THE HOW, primary spec) > SPEC.md (project-rule
# overrides; gates on its own if AI.md is absent too). A project with neither
# is ungoverned, including one that only has a CLAUDE.md or AGENTS.md.
if [ -f "$SPEC_GUARD_PROJECT/AI.md" ]; then
  :
elif [ ! -f "$SPEC_GUARD_PROJECT/SPEC.md" ]; then
  exit 0
fi

SPEC_GUARD_MARKER="${TMPDIR:-/tmp}/claude-hooks/spec-guard/${SPEC_GUARD_SESSION_ID}/read"
grep -qxF -- "$SPEC_GUARD_PROJECT" "$SPEC_GUARD_MARKER" 2>/dev/null && exit 0

SPEC_GUARD_MSG="BLOCKED: Spec guard — AI.md/SPEC.md for this project has not been read yet this session.
project_dir: ${SPEC_GUARD_PROJECT}
Before editing project files: search AI.md for the section relevant to
this task — it may use '## Part N' headings, '# PART N' headings, or no
headings at all (if short, just Read the whole file). Read that section
(and SPEC.md if present), then retry this edit.
This gate re-arms after every compaction — re-read the spec again after a compact before resuming edits."

printf '%s\n' "$SPEC_GUARD_MSG"
printf '%s\n' "$SPEC_GUARD_MSG" >&2
exit 2
