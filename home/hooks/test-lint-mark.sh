#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611261200-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  test-lint-mark.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 22:00 EDT
# @@File             :  test-lint-mark.sh
# @@Description      :  PostToolUse Bash hook: records per session/project that a test-gate or lint-gate command exited 0, pairing with enforce-test-lint-gate.sh.
# @@Changelog        :  Evidence matching is now segment-aware (a command that only echoes/greps/prints a gate command no longer counts), `make lint` counts as lint evidence for non-Go/Rust projects (their *_conventions.md lint target; Go/Rust keep the lint-agent gate), and every marker line carries the epoch so the gate can reject evidence older than the last code change. Earlier: Fixed a bug where this hook never wrote a marker for any command, pass or fail: the success check read a nonexistent .tool_response.exit_code field, which jq always defaulted to 1 via `// 1`. Replaced with a check of whether tool_response is an object (success) vs. a bare error string (nonzero exit) — the field Bash's tool_response actually carries, confirmed live. Previously test/lint patterns and the script-collection manifest disqualifier list were expanded to also recognize Kotlin/Gradle, Java/Maven, Ruby, PHP, Swift, Dart/Flutter, C/C++, .NET, and Elixir — kept in sync with enforce-test-lint-gate.sh's MANIFESTS/TEST_CMD_RE/LINT_CMD_RE.
# @@TODO             :  None
# @@Other              :  Only marks when tool_response is an object and interrupted == false — a failed or timed-out run must never count as passing.
# @@Resource         :  CLAUDE.md - Commit Workflow (Test gate, Lint gate), home/hooks/spec-guard-mark.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611261200-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# Fail open when jq is missing — a broken hook must never crash the tool run
if ! command -v jq >/dev/null 2>&1; then
  printf 'test-lint-mark.sh: jq not found — test/lint mark disabled\n' >&2
  exit 0
fi

# $(cat) is required here — hook stdin is a socket; $(</dev/stdin) re-opens it and fails with ENXIO
TEST_LINT_MARK_INPUT="$(cat)"

# Fail open on an empty, malformed, or non-object payload. Without this, jq
# exits 4/5 and `set -e` propagates that code, which Claude Code surfaces as a
# "hook error" instead of the silent no-op Part 6 requires on a parse failure.
if ! printf '%s' "$TEST_LINT_MARK_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  exit 0
fi

TEST_LINT_MARK_TOOL=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.tool_name) catch "" // ""')
[ "$TEST_LINT_MARK_TOOL" = "Bash" ] || exit 0

# Bash's tool_response has no exit_code field at all (confirmed against live
# transcript data and by triggering a real nonzero-exit command): on success
# it's an object {stdout, stderr, interrupted, isImage, ...}; on a nonzero
# exit it's a bare string like "Error: Exit code 7". A prior version of this
# check read .tool_response.exit_code, which is always absent, so it always
# fell through jq's `// 1` default and the gate below never once matched —
# no marker was ever written, on any command, pass or fail. Object-vs-string
# is the actual, reliable success signal.
TEST_LINT_MARK_RESPONSE_TYPE=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r '(.tool_response | type) // "null"')
[ "$TEST_LINT_MARK_RESPONSE_TYPE" = "object" ] || exit 0
TEST_LINT_MARK_INTERRUPTED=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.tool_response.interrupted) catch false // false')
[ "$TEST_LINT_MARK_INTERRUPTED" = "false" ] || exit 0

TEST_LINT_MARK_CMD=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.tool_input.command) catch "" // ""')
TEST_LINT_MARK_CWD=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.cwd) catch "" // ""')
TEST_LINT_MARK_SESSION_ID=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.session_id) catch "" // ""')
[ -z "$TEST_LINT_MARK_CMD" ] && exit 0
[ -z "$TEST_LINT_MARK_SESSION_ID" ] && exit 0

# __test_lint_mark_matches <regex> <command> — succeeds when any command
# segment (split on && || ; |) that does not start with a reader/printer
# (echo, grep, cat, ...) matches the regex, so a command that merely mentions a
# gate command is never evidence that the gate ran.
__test_lint_mark_matches() {
  local re="$1" cmd="$2" seg first
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [ -z "$seg" ] && continue
    while :; do
      first="${seg%%[[:space:]]*}"
      case "$first" in
        [A-Za-z_]*=*|command|env|exec|nohup|time|sudo|doas|\\*)
          seg="${seg#"$first"}"
          seg="${seg#"${seg%%[![:space:]]*}"}"
          [ -z "$seg" ] && break
          ;;
        *) break ;;
      esac
    done
    [ -z "$seg" ] && continue
    first="${seg%%[[:space:]]*}"
    first="${first##*/}"
    case "$first" in
      echo|printf|cat|grep|egrep|fgrep|rg|less|more|head|tail|sed|awk|man|which|type|whereis|ls|find|jq|wc|diff|git) continue ;;
    esac
    printf '%s' "$seg" | grep -qE -- "$re" && return 0
  done < <(printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
  return 1
}

TEST_LINT_MARK_IS_TEST=0
TEST_LINT_MARK_IS_LINT=0
TEST_LINT_MARK_IS_BASHN=0
TEST_LINT_MARK_IS_MAKELINT=0
TEST_LINT_MARK_TEST_RE='\bmake[[:space:]]+test\b|\bgo[[:space:]]+test\b'
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bcargo[[:space:]]+test\b|\bpytest\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bnpm[[:space:]]+(run[[:space:]]+)?test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bmake[[:space:]]+check\b"
# Must stay in sync with enforce-test-lint-gate.sh's TEST_CMD_RE.
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bgradle[[:space:]]+test\b|\./gradlew[[:space:]]+test\b|\bmvn[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\brspec\b|\bbundle[[:space:]]+exec[[:space:]]+rspec\b|\brake[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bphpunit\b|\bcomposer[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bswift[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bflutter[[:space:]]+test\b|\bdart[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bctest\b|\bdotnet[[:space:]]+test\b|\bmix[[:space:]]+test\b"
__test_lint_mark_matches "$TEST_LINT_MARK_TEST_RE" "$TEST_LINT_MARK_CMD" && TEST_LINT_MARK_IS_TEST=1
__test_lint_mark_matches '\bbash[[:space:]]+-n\b' "$TEST_LINT_MARK_CMD" && TEST_LINT_MARK_IS_BASHN=1
# Lint gates: script-lint/go-lint/rust-lint agents (shell/Go/Rust), `npm run
# lint` (node_typescript_conventions.md's Node/TS gate, `npx eslint` as its
# direct form), `ruff check` / `ruff format --check` (python_conventions.md's
# Python gate), `make check` (claudemgr/android's APPLICATION.md gate —
# compile + ktlint/detekt lint + JVM unit tests in one Docker-run command;
# ktlint/detekt are never invoked directly on the host, so there is no
# separate bare-tool pattern to match), and the packaging-type per-format
# linters (project_type_conventions.md's Format matrix). Must stay in sync
# with enforce-test-lint-gate.sh's LINT_CMD_RE.
TEST_LINT_MARK_LINT_RE='\bscript-lint\b|\bgo-lint\b|\brust-lint\b'
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bnpm[[:space:]]+run[[:space:]]+lint\b|\bnpx[[:space:]]+eslint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bruff[[:space:]]+check\b|\bruff[[:space:]]+format[[:space:]]+--check\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bmake[[:space:]]+check\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\blintian\b|\brpmlint\b|\bnamcap\b|\bapkbuild-lint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bbrew[[:space:]]+(audit|style)\b|\bsnapcraft[[:space:]]+lint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bflatpak-builder-lint\b|\bappimagelint\b|\bnix[[:space:]]+flake[[:space:]]+check\b|\bstatix\b"
# Kotlin/Gradle, Java/Maven, Ruby, PHP, Swift, Dart/Flutter, C/C++,
# .NET, Elixir — must stay in sync with enforce-test-lint-gate.sh's
# LINT_CMD_RE, and each has its own ~/.claude/memory/{lang}_conventions.md.
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bgradle[[:space:]]+(lint|ktlintCheck|detekt)\b|\./gradlew[[:space:]]+(lint|ktlintCheck|detekt)\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bmvn[[:space:]]+checkstyle:check\b|\bmvn[[:space:]]+spotbugs:check\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\brubocop\b|\bphpcs\b|\bphp-cs-fixer\b|\bphpstan\b|\bswiftlint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bflutter[[:space:]]+analyze\b|\bdart[[:space:]]+analyze\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bclang-tidy\b|\bcppcheck\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bdotnet[[:space:]]+format[[:space:]]+--verify-no-changes\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bmix[[:space:]]+credo\b|\bmix[[:space:]]+format[[:space:]]+--check-formatted\b"
__test_lint_mark_matches "$TEST_LINT_MARK_LINT_RE" "$TEST_LINT_MARK_CMD" && TEST_LINT_MARK_IS_LINT=1
# `make lint` is the lint target the Node/TS, Python, Kotlin, Java, Ruby, PHP,
# Swift, Dart, C/C++, .NET and Elixir *_conventions.md files define (it runs
# the linters inside Docker). Go, Rust and shell keep the lint-agent gate, so
# `make lint` only counts once the project is known not to be one of those.
__test_lint_mark_matches '\bmake[[:space:]]+lint\b' "$TEST_LINT_MARK_CMD" && TEST_LINT_MARK_IS_MAKELINT=1

[ "$TEST_LINT_MARK_IS_TEST" = "1" ] || [ "$TEST_LINT_MARK_IS_BASHN" = "1" ] || [ "$TEST_LINT_MARK_IS_LINT" = "1" ] || [ "$TEST_LINT_MARK_IS_MAKELINT" = "1" ] || exit 0

TEST_LINT_MARK_PROJECT=$(git -C "${TEST_LINT_MARK_CWD:-.}" rev-parse --show-toplevel 2>/dev/null) \
  || TEST_LINT_MARK_PROJECT="$TEST_LINT_MARK_CWD"
[ -z "$TEST_LINT_MARK_PROJECT" ] && exit 0
# Normalize the same way enforce-test-lint-gate.sh's reader normalizes its
# --dir lookup key (Python os.path.realpath) — without this, a marker
# written under a symlinked/un-normalized path never matches the reader's
# realpath'd key and the gate falsely reports the test/lint gate as unrun.
TEST_LINT_MARK_PROJECT=$(realpath -- "$TEST_LINT_MARK_PROJECT" 2>/dev/null) || :

if [ "$TEST_LINT_MARK_IS_MAKELINT" = "1" ] && [ ! -f "$TEST_LINT_MARK_PROJECT/go.mod" ] && [ ! -f "$TEST_LINT_MARK_PROJECT/Cargo.toml" ]; then
  TEST_LINT_MARK_IS_LINT=1
fi

# `bash -n` only satisfies the test gate for script-collection projects
# (home/CLAUDE.md's Test gate line) — a project with a real test runner
# (project_type_conventions.md's authoritative manifest set) must not have
# its test gate satisfied by syntax-checking an unrelated script. Must stay
# in sync with enforce-test-lint-gate.sh's MANIFESTS tuple.
if [ "$TEST_LINT_MARK_IS_BASHN" = "1" ] && [ "$TEST_LINT_MARK_IS_TEST" != "1" ]; then
  TEST_LINT_MARK_IS_SCRIPT_COLLECTION=1
  for TEST_LINT_MARK_MANIFEST in \
    go.mod Cargo.toml package.json pyproject.toml \
    build.gradle build.gradle.kts pom.xml \
    Gemfile composer.json Package.swift pubspec.yaml \
    CMakeLists.txt mix.exs; do
    [ -f "$TEST_LINT_MARK_PROJECT/$TEST_LINT_MARK_MANIFEST" ] && TEST_LINT_MARK_IS_SCRIPT_COLLECTION=0 && break
  done
  if [ "$TEST_LINT_MARK_IS_SCRIPT_COLLECTION" = "1" ] \
    && compgen -G "$TEST_LINT_MARK_PROJECT/*.csproj" >/dev/null 2>&1; then
    TEST_LINT_MARK_IS_SCRIPT_COLLECTION=0
  fi
  if [ "$TEST_LINT_MARK_IS_SCRIPT_COLLECTION" = "1" ] \
    && compgen -G "$TEST_LINT_MARK_PROJECT/*.sln" >/dev/null 2>&1; then
    TEST_LINT_MARK_IS_SCRIPT_COLLECTION=0
  fi
  if [ "$TEST_LINT_MARK_IS_SCRIPT_COLLECTION" = "1" ]; then
    TEST_LINT_MARK_IS_TEST=1
  fi
fi
[ "$TEST_LINT_MARK_IS_TEST" = "1" ] || [ "$TEST_LINT_MARK_IS_LINT" = "1" ] || exit 0

# This marker must be a deterministic, reconstructable path so
# enforce-test-lint-gate.sh's reader can look it up again by session_id
# alone. session_id serves as the uniqueness key here. The namespace is
# claude-hooks, not a repo name — these hooks deploy to ~/.claude/hooks
# and run for every project's session, not just this one.
TEST_LINT_MARK_DIR="${TMPDIR:-/tmp}/claude-hooks/test-lint-guard/${TEST_LINT_MARK_SESSION_ID}"
mkdir -p "$TEST_LINT_MARK_DIR"
chmod 700 "${TMPDIR:-/tmp}/claude-hooks/test-lint-guard" "$TEST_LINT_MARK_DIR" 2>/dev/null || true

# Prune marker dirs older than 1 day — scoped only to this tool's own temp namespace
find "${TMPDIR:-/tmp}/claude-hooks/test-lint-guard" -maxdepth 1 -type d -mtime +1 -exec rm -rf -- {} + 2>/dev/null || true

if [ "$TEST_LINT_MARK_IS_TEST" = "1" ]; then
  TEST_LINT_MARK_TEST_MARKER="$TEST_LINT_MARK_DIR/test"
  printf '%s\t%s\n' "$(date +%s)" "$TEST_LINT_MARK_PROJECT" >>"$TEST_LINT_MARK_TEST_MARKER"
fi

if [ "$TEST_LINT_MARK_IS_LINT" = "1" ]; then
  TEST_LINT_MARK_LINT_MARKER="$TEST_LINT_MARK_DIR/lint"
  printf '%s\t%s\n' "$(date +%s)" "$TEST_LINT_MARK_PROJECT" >>"$TEST_LINT_MARK_LINT_MARKER"
fi

exit 0
