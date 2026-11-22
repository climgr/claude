#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220005-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-test-lint-gate.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 22:00 EDT
# @@File             :  enforce-test-lint-gate.sh
# @@Description      :  PreToolUse Bash hook: blocks the commit wrapper's `--dir <path> all` form unless the test and lint gates ran and passed this session for that project.
# @@Changelog        :  A spec-collection project with no root-level .md to re-read (nothing to test or read) no longer blocks the commit. Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  Pairs with test-lint-mark.sh's per-session markers; a project-type heuristic picks the test path (manifest, script-collection re-read, or *.md fallback). TEST_LINT_GATE_OVERRIDE=1 <gitcommit ...> bypasses the gate for that one call — user-directed only, never Claude's own initiative.
# @@Resource         :  CLAUDE.md - Commit Workflow, home/hooks/test-lint-mark.sh, home/hooks/spec-guard.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220005-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'enforce-test-lint-gate.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

# $(cat) is required here — hook stdin is a socket; $(</dev/stdin) re-opens it and fails with ENXIO
ENFORCE_TEST_LINT_GATE_INPUT="$(cat)"

ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE"' EXIT
printf '%s' "$ENFORCE_TEST_LINT_GATE_INPUT" > "$ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE"

python3 - "$ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE" <<'PYEOF'
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
session_id = payload.get("session_id", "")
transcript_path = payload.get("transcript_path", "")
if not cmd or not session_id or not re.search(r"\bgitcommit\b", cmd):
    sys.exit(0)


def find_gitcommit_dir(text):
    # Only the valid `gitcommit --dir <path> all` shape carries a --dir path -
    # malformed shapes are already blocked by enforce-gitcommit-shape.sh.
    for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", text):
        sub_cmd = sub_cmd.strip()
        if not sub_cmd:
            continue
        try:
            tokens = shlex.split(sub_cmd)
        except ValueError:
            tokens = sub_cmd.split()

        clean = []
        override = False
        skipping_prefix = True
        for tok in tokens:
            if skipping_prefix:
                if tok in ("command", "env", "exec", "nohup", "time", "sudo", "doas"):
                    continue
                if tok == "TEST_LINT_GATE_OVERRIDE=1":
                    override = True
                    continue
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                    continue
                if tok.startswith("-"):
                    continue
                skipping_prefix = False
            clean.append(tok.lstrip("\\"))

        if len(clean) == 4 and clean[0] == "gitcommit" and clean[1] == "--dir" and clean[3] == "all":
            yield clean[2], override


targets = list(find_gitcommit_dir(cmd))
if not targets:
    sys.exit(0)

# TEST_LINT_GATE_OVERRIDE=1 <gitcommit ...> — explicit, per-invocation, user-
# directed bypass for the confirmed upstream bug documented below (test-lint-
# mark.sh's PostToolUse marker never firing). Claude sets this prefix only
# when the user's own message explicitly says to bypass/skip the gate after
# confirming they already verified the test/lint run passed — never on its
# own initiative just because the gate blocked (CLAUDE.md: "never auto-bypass
# a hook block"). Same prefix pattern as drift-guard-read.sh's
# DRIFT_GUARD_ALLOW=1.
if any(override for _target, override in targets):
    sys.exit(0)

targets = [target for target, _override in targets]

# Must match the deterministic path test-lint-mark.sh/lint-agent-mark.sh
# write (see those files' comments for why this deviates from
# tempdir_conventions.md's -XXXXXX mktemp-suffix pattern: session_id is
# the lookup key here, so it takes the uniqueness role -XXXXXX would).
#
# `or "/tmp"` rather than a get() default: the writers use bash's
# ${TMPDIR:-/tmp}, which also falls back when TMPDIR is set but EMPTY.
# os.environ.get("TMPDIR", "/tmp") returns "" in that case, making these
# paths relative to the cwd — the reader would then never find markers the
# writers put in /tmp, permanently false-blocking every gitcommit.
tmp_root = os.environ.get("TMPDIR") or "/tmp"
marker_dir = os.path.join(tmp_root, "claude-hooks", "test-lint-guard", session_id)
spec_guard_marker = os.path.join(tmp_root, "claude-hooks", "spec-guard", session_id, "read")


def marked(marker_file, project):
    try:
        with open(marker_file) as f:
            return any(line.rstrip("\n") == project for line in f)
    except OSError:
        return False


# Fallback for the confirmed upstream bug (anthropics/claude-code#36310,
# open): PostToolUse on Bash sometimes never spawns, so test-lint-mark.sh's
# marker is never written even though the command genuinely passed.
# transcript_path (documented in Claude Code's hook payload) is written by
# the CLI itself, independent of PostToolUse firing, so scanning it directly
# gives a reliable second signal that a Bash command ran and passed this
# session. This only runs when the command already matched `gitcommit`
# above, so it never adds cost to ordinary Bash calls.
TEST_CMD_RE = re.compile(
    r"\bmake\s+test\b|\bgo\s+test\b|\bcargo\s+test\b|\bpytest\b|\bnpm\s+(run\s+)?test\b"
    r"|\bmake\s+check\b"
    r"|\bgradle\s+test\b|\./gradlew\s+test\b|\bmvn\s+test\b"
    r"|\brspec\b|\bbundle\s+exec\s+rspec\b|\brake\s+test\b"
    r"|\bphpunit\b|\bcomposer\s+test\b"
    r"|\bswift\s+test\b"
    r"|\bflutter\s+test\b|\bdart\s+test\b"
    r"|\bctest\b"
    r"|\bdotnet\s+test\b"
    r"|\bmix\s+test\b"
)
BASHN_RE = re.compile(r"\bbash\s+-n\b")
# Must stay in sync with test-lint-mark.sh's TEST_LINT_MARK_LINT_RE: the lint
# agents (shell/Go/Rust), `npm run lint`/`npx eslint` (Node/TS gate per
# node_typescript_conventions.md), `ruff check`/`ruff format --check` (Python
# gate per python_conventions.md), `make check` (claudemgr/android's
# APPLICATION.md gate — compile + ktlint/detekt lint + JVM unit tests in one
# Docker-run command; ktlint/detekt are never invoked directly on the host),
# and the packaging-type per-format linters (project_type_conventions.md's
# Format matrix).
LINT_CMD_RE = re.compile(
    r"\bscript-lint\b|\bgo-lint\b|\brust-lint\b|\bnpm\s+run\s+lint\b"
    r"|\bnpx\s+eslint\b|\bruff\s+check\b|\bruff\s+format\s+--check\b"
    r"|\blintian\b|\brpmlint\b|\bnamcap\b|\bapkbuild-lint\b"
    r"|\bbrew\s+(audit|style)\b|\bsnapcraft\s+lint\b|\bflatpak-builder-lint\b"
    r"|\bappimagelint\b|\bnix\s+flake\s+check\b|\bstatix\b|\bmake\s+check\b"
    r"|\bgradle\s+(lint|ktlintCheck|detekt)\b|\./gradlew\s+(lint|ktlintCheck|detekt)\b"
    r"|\bmvn\s+checkstyle:check\b|\bmvn\s+spotbugs:check\b"
    r"|\brubocop\b"
    r"|\bphpcs\b|\bphp-cs-fixer\b|\bphpstan\b"
    r"|\bswiftlint\b"
    r"|\bflutter\s+analyze\b|\bdart\s+analyze\b"
    r"|\bclang-tidy\b|\bcppcheck\b"
    r"|\bdotnet\s+format\s+--verify-no-changes\b"
    r"|\bmix\s+credo\b|\bmix\s+format\s+--check-formatted\b"
)
# No new lint-agent subagent_types are added for the languages below —
# coverage is via TEST_CMD_RE/LINT_CMD_RE direct-command matching plus a
# dedicated ~/.claude/memory/{lang}_conventions.md reference file per
# language (see home/CLAUDE.md's Language Constraints section), the same
# pattern already used for Node/TS (npm run lint) and Python (ruff).
# The lint agents are as often launched via the Agent tool (subagent_type
# script-lint/go-lint/rust-lint) as via a literal Bash command — the Bash-only
# scan above missed every Agent-tool run entirely, permanently false-blocking
# gitcommit for anyone who runs the lint agent that way. Same new/pre-existing
# contract lint-agent-mark.sh's SubagentStop hook checks (this PART's own
# Resource note): only a report with a nonzero "N new issue(s) found" line
# disqualifies it — pre-existing findings (outside the lines this session's
# uncommitted changes touch) never block on their own, since the agent's own
# spec requires the calling session to log those to TODO.AI.md instead.
LINT_AGENT_TYPES = {"script-lint", "go-lint", "rust-lint"}
LINT_AGENT_CLEAN_RE = re.compile(r":\s*clean\b|:\s*0\s+new issue\(s\)\s+found\b")
LINT_AGENT_ISSUES_RE = re.compile(r":\s*[1-9][0-9]*\s+new issue\(s\)\s+found\b")


def _agent_result_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))
        return "\n".join(parts)
    return ""


def _mentions(text, project):
    if not text or not project:
        return False
    return re.search(re.escape(project) + r"(?![\w.\-])", text) is not None


def transcript_pass(transcript_path, project, allow_bashn_as_test):
    if not transcript_path or not os.path.isfile(transcript_path):
        return False, False
    tool_use_cmds = {}
    lint_agent_ids = {}
    agent_prompts = {}
    test_ok = False
    lint_ok = False
    # Async hand-back delivery is NOT a "user" transcript entry — confirmed
    # against a live transcript (2.1.277): it lands as a "type":"attachment"
    # entry whose rendered[].content carries the "<agent-message from=...>
    # [Subagent hand-back]" text, with no cwd field of its own. Track the
    # most recently seen cwd from any entry so those attachment entries can
    # still be judged cwd_match, same as a "user" entry would be.
    last_cwd_project = ""
    try:
        with open(transcript_path, errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue
                if not isinstance(entry, dict):
                    continue
                etype = entry.get("type")
                # "message" (and its "content") can legitimately be null or a
                # non-list in some transcript entries (e.g. summary/system
                # lines) - .get()'s default only covers a MISSING key, not a
                # present null, so each level is defensively re-checked
                # rather than trusting the transcript's shape (reproduced
                # AttributeError: 'NoneType' object has no attribute 'get').
                if etype == "assistant":
                    msg = entry.get("message")
                    content = msg.get("content") if isinstance(msg, dict) else None
                    for c in content or []:
                        if not isinstance(c, dict):
                            continue
                        if c.get("type") == "tool_use" and c.get("name") == "Bash":
                            inp = c.get("input")
                            cmd_ = inp.get("command", "") if isinstance(inp, dict) else ""
                            if cmd_:
                                tool_use_cmds[c.get("id")] = cmd_
                        elif c.get("type") == "tool_use" and c.get("name") == "Agent":
                            inp = c.get("input")
                            subagent_ = inp.get("subagent_type", "") if isinstance(inp, dict) else ""
                            if subagent_ in LINT_AGENT_TYPES:
                                prompt_ = inp.get("prompt", "") if isinstance(inp, dict) else ""
                                lint_agent_ids[c.get("id")] = prompt_ if isinstance(prompt_, str) else ""
                elif etype == "attachment":
                    rendered = entry.get("rendered")
                    text_ = ""
                    if isinstance(rendered, list) and rendered:
                        first_ = rendered[0]
                        text_ = first_.get("content", "") if isinstance(first_, dict) else ""
                    if not isinstance(text_, str) or "hand-back" not in text_.lower():
                        continue
                    from_ = re.search(r'from="(\w+)"', text_)
                    prompt_ = agent_prompts.get(from_.group(1), "") if from_ else ""
                    cwd_match = bool(last_cwd_project) and last_cwd_project == project
                    if not (cwd_match or _mentions(prompt_, project) or _mentions(text_, project)):
                        continue
                    if LINT_AGENT_CLEAN_RE.search(text_) and not LINT_AGENT_ISSUES_RE.search(text_):
                        lint_ok = True
                elif etype == "user":
                    entry_cwd = entry.get("cwd", "")
                    try:
                        entry_project = os.path.realpath(entry_cwd) if entry_cwd else ""
                        if entry_project:
                            last_cwd_project = entry_project
                    except OSError:
                        entry_project = ""
                    # A session is routinely run from a parent directory while
                    # linting/testing a sibling repo, so the entry's cwd alone
                    # cannot decide relevance: a result also counts for this
                    # project when the command / agent prompt / report names
                    # the project path.
                    cwd_match = entry_project == project
                    tur = entry.get("toolUseResult") or {}
                    if not isinstance(tur, dict):
                        tur = {}
                    if tur.get("interrupted"):
                        continue
                    msg = entry.get("message")
                    content = msg.get("content") if isinstance(msg, dict) else None
                    if isinstance(content, str):
                        content = [{"type": "text", "text": content}]
                    for c in content or []:
                        if not isinstance(c, dict):
                            continue
                        if c.get("type") == "text":
                            # Async Agent-tool runs only return a "launched"
                            # tool_result; the real report arrives later as a
                            # hand-back message keyed by the agent id.
                            text_ = c.get("text", "")
                            if not isinstance(text_, str) or "hand-back" not in text_.lower():
                                continue
                            from_ = re.search(r'from="(\w+)"', text_)
                            prompt_ = agent_prompts.get(from_.group(1), "") if from_ else ""
                            if not (cwd_match or _mentions(prompt_, project) or _mentions(text_, project)):
                                continue
                            if LINT_AGENT_CLEAN_RE.search(text_) and not LINT_AGENT_ISSUES_RE.search(text_):
                                lint_ok = True
                            continue
                        if c.get("type") != "tool_result" or c.get("is_error"):
                            continue
                        tool_use_id_ = c.get("tool_use_id")
                        if tool_use_id_ in lint_agent_ids:
                            report_ = _agent_result_text(c.get("content"))
                            prompt_ = lint_agent_ids[tool_use_id_]
                            launched_ = re.search(r"agentId:\s*(\w+)", report_)
                            if launched_:
                                agent_prompts[launched_.group(1)] = prompt_
                            if not (cwd_match or _mentions(prompt_, project) or _mentions(report_, project)):
                                continue
                            if LINT_AGENT_CLEAN_RE.search(report_) and not LINT_AGENT_ISSUES_RE.search(
                                report_
                            ):
                                lint_ok = True
                            continue
                        cmd_ = tool_use_cmds.get(tool_use_id_)
                        if not cmd_:
                            continue
                        if not (cwd_match or _mentions(cmd_, project)):
                            continue
                        if TEST_CMD_RE.search(cmd_):
                            test_ok = True
                        if allow_bashn_as_test and BASHN_RE.search(cmd_):
                            test_ok = True
                        if LINT_CMD_RE.search(cmd_):
                            lint_ok = True
    except OSError:
        return False, False
    return test_ok, lint_ok


def has_shell_scripts(root):
    # project_type_conventions.md's spec-collection rule scans "anywhere in
    # its tree", unqualified — no depth limit. A bare deploy-only install.sh
    # at the project root does not disqualify spec-collection on its own;
    # any *.sh/*.bash file elsewhere in the tree does.
    skip = {".git", "node_modules", "vendor", ".venv", "target", "dist", "build"}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip]
        for f in filenames:
            if not f.endswith((".sh", ".bash")):
                continue
            if dirpath == root and f == "install.sh":
                continue
            return True
    return False


# Authoritative manifest set from project_type_conventions.md's
# script-collection/spec-collection detection signals — one fixed
# filename per language/build-system, each with a documented test/lint
# gate command in TEST_CMD_RE/LINT_CMD_RE above and its own
# ~/.claude/memory/{lang}_conventions.md reference file (home/CLAUDE.md's
# Language Constraints section). dotnet's *.csproj/*.sln are not fixed
# filenames, so they use the has_dotnet_manifest() glob check instead.
MANIFESTS = (
    "go.mod", "Cargo.toml", "package.json", "pyproject.toml",
    "build.gradle", "build.gradle.kts", "pom.xml",
    "Gemfile", "composer.json", "Package.swift", "pubspec.yaml",
    "CMakeLists.txt", "mix.exs",
)


def has_dotnet_manifest(root):
    try:
        return any(f.endswith((".csproj", ".sln")) for f in os.listdir(root))
    except OSError:
        return False


def has_any_manifest(root):
    return (
        any(os.path.isfile(os.path.join(root, m)) for m in MANIFESTS)
        or has_dotnet_manifest(root)
    )


def is_spec_collection(root):
    if has_any_manifest(root):
        return False
    return not has_shell_scripts(root)


# Root-level .md files that spec-guard-mark.sh never records as a spec read.
NON_SPEC_MD = (
    "LICENSE.md", "CLAUDE.md", "IDEA.md", "TODO.AI.md", "TODO.md", "PLAN.AI.md", "PLAN.md",
)


def has_readable_spec(root):
    # A spec-collection project can only satisfy the spec re-read when it has a
    # root-level .md that spec-guard-mark.sh records (AI.md, SPEC.md, a template
    # *.md, or a lone README.md). With none, there is nothing to re-read and no
    # test to run, so the gate has nothing to require and must not block.
    try:
        return any(
            f.endswith(".md") and f not in NON_SPEC_MD and os.path.isfile(os.path.join(root, f))
            for f in os.listdir(root)
        )
    except OSError:
        return False


blocked = []
for target in targets:
    project = os.path.realpath(os.path.expanduser(target))
    if not os.path.isdir(project):
        continue

    if is_spec_collection(project):
        if not has_readable_spec(project):
            continue
        if not marked(spec_guard_marker, project):
            blocked.append(
                f"{project}: spec-collection project — AI.md/SPEC.md (or, for a template repo with "
                f"neither, its root-level *.md spec file) has not been re-read this session "
                f"(CLAUDE.md's substitute for a test runner here)."
            )
        continue

    manifests_present = has_any_manifest(project)
    transcript_test_ok, transcript_lint_ok = transcript_pass(
        transcript_path, project, allow_bashn_as_test=not manifests_present
    )

    missing = []
    if not marked(os.path.join(marker_dir, "test"), project) and not transcript_test_ok:
        missing.append("test gate")
    # Every manifest language has a documented lint gate — go-lint/rust-lint/
    # script-lint agents for Go/Rust/shell, `npm run lint` for Node/TS
    # (node_typescript_conventions.md), `ruff check` + `ruff format --check`
    # for Python (python_conventions.md), and the direct lint commands in
    # LINT_CMD_RE above for every other manifest language — so any manifest
    # or shell script in the tree means the lint gate is both defined and
    # satisfiable.
    has_defined_lint_target = manifests_present or has_shell_scripts(project)
    if (
        has_defined_lint_target
        and not marked(os.path.join(marker_dir, "lint"), project)
        and not transcript_lint_ok
    ):
        missing.append("lint gate")
    if missing:
        blocked.append(f"{project}: {' and '.join(missing)} has not run (and passed) this session")

if not blocked:
    sys.exit(0)

msg_lines = ["BLOCKED: gitcommit requires the test/lint gate to have run and passed this session.\n"]
for b in blocked:
    msg_lines.append(f"  - {b}")
msg_lines.append("")
msg_lines.append(
    "Run the project's test gate (make test / go test ./... / cargo test / pytest /\n"
    "npm test / bash -n for script-collection) and lint gate (script-lint / go-lint /\n"
    "rust-lint via the Agent tool — or `npm run lint` for Node/TS, `ruff check` +\n"
    "`ruff format --check` for Python; never `make lint`) first, then retry gitcommit."
)
msg = "\n".join(msg_lines)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF
