#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202611220003-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-forbidden-files.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Thursday, May 15, 2026 00:00 EDT
# @@File             :  no-forbidden-files.sh
# @@Description      :  PreToolUse hook: confirm before writing normally-forbidden files
# @@Changelog        :  Allowlist the template root files AGENTS.md, CLAUDE.md, CLAUDE.local.md, mkdocs.yml and .readthedocs.yaml. Earlier: Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error. Parse with strict=False like every other hook so raw control characters inside content strings never abort the scan.
# @@TODO             :  Better docs
# @@Other            :
# @@Resource         :  home/memory/project_files.md
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202611220003-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# Read stdin via the read builtin — $(< /dev/stdin) fails when stdin is a closed/odd fd in the hook runner
IFS= read -r -d '' INPUT || true

# Fail-open if python3 is missing — a broken hook exits 0 (no-op) so we never silently block every Write/Edit call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'no-forbidden-files.sh: required command not found: python3\n' >&2
  exit 0
fi

INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$INPUT_TMPFILE"' EXIT
printf '%s' "$INPUT" > "$INPUT_TMPFILE"

python3 - "$INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
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

tool = payload.get("tool_name", "")
tool_input = payload.get("tool_input", {})

if tool in ("Write", "Edit"):
    # A non-string file_path (number, null, list) reaches os.path.basename
    # below and raises TypeError, which exits 1 and shows as a hook error.
    # Part 6 requires failing open on any unusable payload instead.
    file_path = tool_input.get("file_path", "")
    if not isinstance(file_path, str):
        file_path = ""
else:
    sys.exit(0)

if not file_path:
    sys.exit(0)

basename = os.path.basename(file_path)
norm_path = file_path.replace("\\", "/")

# Root-only forbidden directories must be scoped to the target file's OWN
# git repo root, never the session's process cwd — payload["cwd"] can be a
# parent directory (e.g. a manager repo cwd'd one level above the project),
# which misidentifies the project's own root-level directory name (e.g. a
# repo whose local checkout dir is literally named "config", as this
# repo's used to be) as the forbidden config/ root dir. Resolve via
# `git -C <file_dir> rev-parse --show-toplevel` first; fall back to
# payload["cwd"] only when the file isn't inside a git
# repo (e.g. a not-yet-initialized project).
import subprocess

file_dir = os.path.dirname(file_path) or "."
repo_root = ""
try:
    result = subprocess.run(
        ["git", "-C", file_dir, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, timeout=5,
    )
    if result.returncode == 0:
        repo_root = result.stdout.strip()
except Exception:
    repo_root = ""

hook_cwd = (repo_root or payload.get("cwd", "")).replace("\\", "/").rstrip("/")
root_rel_path = None
if hook_cwd and norm_path.startswith(hook_cwd + "/"):
    root_rel_path = norm_path[len(hook_cwd) + 1:]

# ------------------------------------------------------------------
# ALLOWLIST — toolchain-required files that are never blocked
# ------------------------------------------------------------------
ALWAYS_ALLOW_BASENAMES = {
    # Make / Autotools
    "Makefile", "GNUmakefile", "makefile",
    "Makefile.am", "Makefile.in", "Makefile.dist",
    "configure.ac", "configure.in", "configure",
    "autogen.sh", "bootstrap.sh", "autoclean.sh",
    "aclocal.m4", "config.h.in",
    # CMake
    "CMakeLists.txt", "CMakeCache.txt",
    # Go
    "go.mod", "go.sum", "go.work", "go.work.sum",
    # Rust
    "Cargo.toml", "Cargo.lock",
    # Node / JS / TS
    "package.json", "package-lock.json",
    "yarn.lock", "yarn.config.js", "yarn.config.cjs",
    "bun.lockb", "bun.lock",
    "pnpm-lock.yaml", "pnpm-workspace.yaml",
    "tsconfig.json", "tsconfig.base.json", "tsconfig.node.json",
    "jsconfig.json",
    "webpack.config.js", "webpack.config.ts",
    "vite.config.js", "vite.config.ts",
    "rollup.config.js", "rollup.config.ts", "rollup.config.mjs",
    "babel.config.js", "babel.config.json", "babel.config.ts",
    ".babelrc", ".babelrc.js", ".babelrc.json",
    "jest.config.js", "jest.config.ts", "jest.config.json",
    "vitest.config.js", "vitest.config.ts",
    ".eslintrc", ".eslintrc.js", ".eslintrc.json", ".eslintrc.yaml", ".eslintrc.yml",
    ".eslintignore",
    "eslint.config.js", "eslint.config.ts", "eslint.config.mjs",
    ".prettierrc", ".prettierrc.js", ".prettierrc.json",
    ".prettierignore",
    "prettier.config.js", "prettier.config.ts",
    "biome.json",
    "deno.json", "deno.jsonc", "deno.lock",
    # Python
    "pyproject.toml", "setup.py", "setup.cfg",
    "requirements.txt", "requirements-dev.txt", "requirements-test.txt",
    "Pipfile", "Pipfile.lock",
    "poetry.lock",
    "tox.ini", "noxfile.py",
    "MANIFEST.in",
    ".flake8", ".pylintrc", "mypy.ini",
    "pyrightconfig.json",
    # Ruby
    "Gemfile", "Gemfile.lock", "Rakefile",
    # Java / Maven / Gradle
    "pom.xml",
    "build.gradle", "build.gradle.kts",
    "settings.gradle", "settings.gradle.kts",
    "gradle.properties", "gradlew", "gradlew.bat",
    # Bazel
    "BUILD", "BUILD.bazel", "WORKSPACE", "WORKSPACE.bazel",
    "WORKSPACE.bzlmod", "MODULE.bazel",
    ".bazelrc", ".bazelignore", ".bazelversion",
    # Zig
    "build.zig", "build.zig.zon",
    # D / DUB
    "dub.json", "dub.sdl",
    # Elixir / Erlang
    "mix.exs", "mix.lock", "rebar.config", "rebar.lock",
    # PHP
    "composer.json", "composer.lock",
    ".php-cs-fixer.php", ".php-cs-fixer.dist.php",
    "phpunit.xml", "phpunit.xml.dist",
    "phpstan.neon", "phpstan.dist.neon",
    # .NET / C#
    "global.json", "NuGet.Config", "nuget.config",
    "Directory.Build.props", "Directory.Build.targets",
    # Haskell
    "stack.yaml", "stack.yaml.lock", "cabal.project", "cabal.project.freeze",
    # Swift
    "Package.swift", "Package.resolved",
    # Dart / Flutter
    "pubspec.yaml", "pubspec.lock", "analysis_options.yaml",
    # OCaml
    "dune", "dune-project", "dune-workspace",
    # Scala / sbt
    "build.sbt",
    # Clojure
    "project.clj", "deps.edn", "bb.edn",
    # Crystal
    "shard.yml", "shard.lock",
    # Julia
    "Project.toml", "Manifest.toml",
    # CI / CD
    ".travis.yml", "Jenkinsfile",
    "appveyor.yml",
    ".gitlab-ci.yml",
    ".drone.yml",
    ".woodpecker.yml", ".woodpecker.yaml",
    "azure-pipelines.yml", "azure-pipelines.yaml",
    "bitbucket-pipelines.yml",
    "cloudbuild.yaml", "cloudbuild.yml",
    ".pre-commit-config.yaml",
    "codecov.yml", ".codecov.yml",
    ".goreleaser.yml", ".goreleaser.yaml",
    "renovate.json", "renovate.json5",
    ".renovaterc", ".renovaterc.json", ".renovaterc.json5",
    # Security / SCA scanner configs
    ".trivyignore", ".trivyignore.yaml", "trivy.yaml",
    ".grype.yaml", ".syft.yaml",
    ".snyk",
    ".gitleaks.toml", ".gitleaksignore",
    ".semgrepignore",
    ".hadolint.yaml", ".hadolint.yml",
    ".checkov.yaml", ".checkov.yml",
    ".osv-scanner.toml",
    ".dockleignore",
    # Linter / formatter dot-configs
    ".shellcheckrc",
    ".yamllint", ".yamllint.yml", ".yamllint.yaml",
    ".markdownlint.json", ".markdownlint.yaml", ".markdownlint.yml",
    ".markdownlintignore",
    # Tooling dot-configs
    ".gitignore", ".gitattributes", ".gitmodules",
    ".editorconfig",
    ".dockerignore",
    ".env.example", ".env.sample",
    "app.env.example", "app.env.sample",
    "default.env.example", "default.env.sample",
    # Nix
    "flake.nix", "flake.lock", "default.nix", "shell.nix",
    # Docs (project-standard names)
    # CHANGELOG.md / CHANGES.md are explicitly allowed at any path (root or .github/).
    "CHANGELOG.md", "CHANGELOG.txt", "CHANGES.md", "CHANGES.txt",
    # CONTRIBUTING / CODE_OF_CONDUCT / SECURITY / PULL_REQUEST_TEMPLATE
    # are only auto-allowed when nested under .github/ (or other dotfile dirs
    # in ALWAYS_ALLOW_PATH_PATTERNS). At repo root they fall through to the
    # confirmation prompt below.
    "AUTHORS", "AUTHORS.md", "CONTRIBUTORS", "CONTRIBUTORS.md",
    "NOTICE", "NOTICE.md", "NOTICE.txt",
    "LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING",
    # Loader files and documentation-site config (templates' allowed root files)
    "AGENTS.md", "CLAUDE.md", "CLAUDE.local.md", "mkdocs.yml", ".readthedocs.yaml", ".readthedocs.yml",
    # Misc project root files
    "VERSION", "VERSION.txt", "version.txt",
    ".npmignore", ".npmrc", ".nvmrc", ".node-version",
    ".ruby-version", ".python-version", ".tool-versions",
    ".golangci.yml", ".golangci.yaml",
    # Nim
    "config.nims",
    # R package
    "DESCRIPTION",
    # R package
    "NAMESPACE",
}

ALWAYS_ALLOW_EXTENSIONS = {
    # Protocol Buffers
    ".proto",
    # Thrift
    ".thrift",
    # Avro schema
    ".avsc",
    # Cap'n Proto
    ".capnp",
    # FlatBuffers
    ".fbs",
    # Nim package manifest
    ".nimble",
    # Haskell Cabal
    ".cabal",
    # OCaml OPAM
    ".opam",
    # Ruby gemspec
    ".gemspec",
    # CocoaPods
    ".podspec",
    # LuaRocks
    ".rockspec",
    # Terraform
    ".tf",
    # Terraform vars
    ".tfvars",
    # HCL config
    ".hcl",
    # Solidity
    ".sol",
    # Vyper
    ".vy",
}

ALWAYS_ALLOW_PATH_PATTERNS = [
    r"\.github/",
    r"\.gitlab/",
    r"\.gitea/",
    r"\.forgejo/",
    r"\.circleci/",
    r"\.woodpecker/",
    r"\.buildkite/",
    r"\.cargo/",
    r"/gradle/wrapper/",
    r"/\.mvn/",
    r"/__pycache__/",
    r"/\.git/",
]

# Doc/config basenames that are only auto-allowed under one specific
# directory (project_files.md's Forbidden Files table) — forbidden with a
# confirmation prompt anywhere else, including repo root.
LOCATION_RESTRICTED_DOC_BASENAMES = {
    "contributing.md", "code_of_conduct.md",
    "security.md", "pull_request_template.md",
}
LOCATION_RESTRICTED_DOCKER_BASENAMES = {
    "dockerfile", "containerfile",
    "docker-compose.yml", "docker-compose.yaml",
    "docker-compose.override.yml", "docker-compose.override.yaml",
}
# project_files.md's documented exception scope is glob-based (Dockerfile*,
# *compose*.y?ml), wider than the flat basename set above (e.g. it also
# covers Dockerfile.build/Dockerfile.10-dev variant names and compose.yml
# without the docker- prefix) — matched separately so a name only this
# pattern catches still goes through the same root/docker-dir gate below.
DOCKER_BASENAME_PATTERN = re.compile(
    r"^(dockerfile(\..+)?|containerfile(\..+)?|[a-z0-9._-]*compose[a-z0-9._-]*\.ya?ml)$"
)

def is_allowed(fp, bn):
    if bn in ALWAYS_ALLOW_BASENAMES:
        return True
    _, ext = os.path.splitext(bn)
    if ext in ALWAYS_ALLOW_EXTENSIONS:
        return True
    for pat in ALWAYS_ALLOW_PATH_PATTERNS:
        if re.search(pat, fp):
            return True
    return False

# ------------------------------------------------------------------
# FORBIDDEN FILE PATTERNS — prompt confirmation before writing
# Deny wins over allow: these checks run BEFORE the allowlist so that
# credential files under allowlisted paths (.github/, vendor/, ...) still block.
# Patterns are split across variables to avoid triggering other hooks
# when this script itself is written.
# ------------------------------------------------------------------

# All entries lowercase — compared case-insensitively against basename.lower().
FORBIDDEN_BASENAMES = {
    ".netrc",
    "credentials.json", "service-account.json", "service_account.json",
    "secrets.json", "secrets.yaml", "secrets.yml",
    "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa",
    ".ds_store", "thumbs.db", "desktop.ini",
    ".env", "app.env", "default.env",
    "server.yml", "cli.yml",
}

# Report-only / redundant doc basenames forbidden by project_files.md's
# Forbidden Files table — AUDIT.md is exact-match only, so the explicit
# AUDIT.AI.md exception it names is never caught by this set.
FORBIDDEN_REPORT_BASENAMES = {
    "summary.md", "compliance.md", "notes.md",
    "audit.md", "report.md", "analysis.md",
}

# Root-only forbidden directories (project_files.md's Forbidden
# Directories table) — checked relative to the file's own git repo root
# (root_rel_path above), since lib/, build/, etc. are only forbidden at
# repo root (nested, e.g. src/lib/, is acceptable — root_rel_path already
# only ever holds the path relative to repo root, so a nested dir never
# matches here regardless of depth).
#
# project_files.md's own rationale column ("Config is embedded,
# runtime-generated in OS dirs", "Use proper language package structure")
# is written for a {lang}/{framework} shippable-binary project — it does
# not hold for a script-collection or spec-collection repo, which has no
# compiled runtime, no OS install dirs, and often legitimately ships a
# root-level config/ or data/ directory as part of what it distributes
# (see project_type_conventions.md's script-collection/spec-collection
# sections). Skip this specific check — and only this check, every other
# forbidden-file/credential/vendor check below still applies — when the
# repo has none of the manifest files that mark it as a language project.
FORBIDDEN_ROOT_DIRNAMES = {
    "config", "data", "logs", "tmp", "temp", "test-data",
    "build", "dist", "out", "lib", "libs", "utils", "common",
}

LANGUAGE_PROJECT_MANIFESTS = {
    "go.mod", "Cargo.toml", "package.json", "pyproject.toml",
    "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle",
    "CMakeLists.txt", "Gemfile", "composer.json", "mix.exs",
    "Package.swift", "pubspec.yaml", "build.zig", "dune-project",
    "build.sbt", "project.clj", "deps.edn", "*.csproj", "*.sln",
}

def is_docker_root_project(root):
    # Generic, name-agnostic signal: a repo whose root has NO language-project
    # manifest (is_language_project() below — go.mod, package.json, etc.) has
    # no docker/ subdirectory convention to conflict with, so its Dockerfile/
    # compose files legitimately live at the repo root. This covers any repo
    # whose entire purpose is a Docker image/compose build living at root —
    # dockersrc/casjaysdevdocker/composemgr-style repos and any third-party
    # equivalent — without hardcoding org or repo names, so it holds for any
    # user of this public convention, not just this machine's own repos.
    return not is_language_project(root)

def is_language_project(root):
    if not root or not os.path.isdir(root):
        # Unknown repo root — fail toward the stricter, pre-existing
        # behavior rather than silently widening the exception.
        return True
    try:
        entries = os.listdir(root)
    except OSError:
        return True
    for name in entries:
        if name in LANGUAGE_PROJECT_MANIFESTS:
            return True
        if name.endswith(".csproj") or name.endswith(".sln"):
            return True
    return False

FORBIDDEN_EXTENSIONS = {
    # private keys / certificates
    ".pem",
    # private key (generic)
    ".key",
    # PKCS#12 bundle
    ".p12",
    # PFX bundle
    ".pfx",
    # Java KeyStore
    ".jks",
    # Apple private key
    ".p8",
    # PuTTY private key
    ".ppk",
}

# .claude/settings.local.json is deliberately NOT in this list. CLAUDE.md's
# Autonomy section pre-approves Write/Edit to it explicitly (it is the
# mechanism the Local System Management Zone's own grant-recording flow
# writes to) — blocking it here contradicted that pre-approval. It also
# can't be fixed by asking: this hook's exit-2 block is a hard, stateless
# deny with no way to record "the user already said yes" for a retry, so a
# path matched here can never actually be unblocked by user confirmation,
# only ever definitively refused. Keep genuinely-undesired personal-tool
# files (Cursor/Windsurf/Aider/etc. below) hard-blocked; do not add a path
# here unless it is meant to be refused outright, never written at all.

# Patterns split to avoid triggering sibling hooks on this file itself
_ca = "co-authored-by"
_ai_tools = ["claude", "copilot", "chatgpt", "gpt"]
FORBIDDEN_PATH_PATTERNS = [
    (_ca + r".*(" + "|".join(_ai_tools) + r")", "AI attribution trailer in path"),
    (r"generated (with|by) (" + "|".join(_ai_tools) + r"|openai|anthropic)", "AI attribution phrase in path"),
    (r"/\.aws/credentials", "AWS credential file"),
    (r"/\.ssh/id_(?!.*\.pub$)", "SSH private key"),
    (r"(^|/)vendor/", "vendor/ directory is forbidden — use language module system"),
    (r"(^|/)node_modules/", "node_modules/ is forbidden — never committed"),
    (r"(^|/)\.claude/(backups|cache|file-history|projects)/", ".claude/ runtime directory — gitignored, never committed"),
    (r"(^|/)\.claude/history\.jsonl$", ".claude/ runtime file — gitignored, never committed"),
    (r"(^|/)\.claude/statsfile$", ".claude/ runtime file — gitignored, never committed"),
    (r"(^|/)\.claude/[^/]*\.lock$", ".claude/ runtime lockfile — gitignored, never committed"),
    (r"(^|/)\.cursor/settings\.json$", "personal Cursor settings — gitignored, never committed"),
    (r"(^|/)\.windsurf/settings\.json$", "personal Windsurf settings — gitignored, never committed"),
    (r"(^|/)\.aider\.(chat\.history\.md|input\.history|llm\.history)$", "Aider personal history — gitignored, never committed"),
    (r"(^|/)\.aider\.tags\.cache\.v3/", "Aider symbol cache — gitignored, never committed"),
    (r"(^|/)\.continue/(dev_data|index)/", "Continue personal data/index — gitignored, never committed"),
    (r"(^|/)\.continue/session\.json$", "Continue personal session — gitignored, never committed"),
    (r"(^|/)\.codeium/", "Codeium auth/cache — gitignored, never committed"),
]

def is_forbidden(fp, bn, root_rel):
    # Basename and extension checks are case-insensitive (ID_RSA, cert.PEM, Secrets.json).
    bn_lower = bn.lower()
    if bn_lower in FORBIDDEN_BASENAMES:
        return bn, "credential/secrets/OS-detritus file"
    if bn_lower in FORBIDDEN_REPORT_BASENAMES:
        return bn, "report-only/redundant doc — fix issues directly, use AI.md/TODO.AI.md"
    _, ext = os.path.splitext(bn_lower)
    if ext in FORBIDDEN_EXTENSIONS:
        return bn, "private key or certificate file"
    fp_lower = fp.lower()
    for pat, label in FORBIDDEN_PATH_PATTERNS:
        if re.search(pat, fp_lower):
            return fp, label
    if root_rel is not None and is_language_project(hook_cwd):
        top = root_rel.split("/", 1)[0].lower()
        if top in FORBIDDEN_ROOT_DIRNAMES:
            return root_rel, f"{top}/ at repo root is a forbidden directory"
    return None, None

matched_name, reason = is_forbidden(norm_path, basename, root_rel_path)

# Allowlist only rescues files NOT forbidden by name/extension/path — deny wins over allow.
if matched_name is None and is_allowed(norm_path, basename):
    sys.exit(0)

# Location-restricted docs under allowlisted paths were rescued above; anywhere else they need confirmation.
# Exception: paths under docs/ are MkDocs content pages (e.g. docs/security.md), not GitHub community-health files.
if matched_name is None and basename.lower() in LOCATION_RESTRICTED_DOC_BASENAMES:
    if not re.search(r"(^|/)docs/", norm_path):
        matched_name, reason = basename, "doc file only auto-allowed under .github/ or docs/"

# Docker/Container files belong under docker/ (project_files.md) — anywhere
# else, including repo root, needs confirmation. Exception 1: repos with no
# language-project manifest at root legitimately place these files at the
# repo root itself — see is_docker_root_project() above. Exception 2: a
# compose/ directory is dockerfile_conventions.md's own documented second
# home for compose files ("Deployment Compose", reference layout
# composemgr/template) — a third-party-service compose file, or a
# management directory that groups several independent per-service compose
# deployments each in their own subdirectory (e.g.
# compose/{service}/docker-compose.yaml), belongs there just as validly as
# under docker/. Only compose*.y?ml basenames get this second exception —
# a bare Dockerfile/Containerfile has no such alternate documented home and
# still requires docker/.
_docker_basename_match = (
    basename.lower() in LOCATION_RESTRICTED_DOCKER_BASENAMES
    or DOCKER_BASENAME_PATTERN.match(basename.lower())
)
_is_compose_basename = "compose" in basename.lower()
if matched_name is None and _docker_basename_match:
    at_repo_root = root_rel_path is not None and "/" not in root_rel_path
    docker_project_root_exempt = at_repo_root and is_docker_root_project(hook_cwd)
    _location_ok = re.search(r"(^|/)docker/", norm_path) or (
        _is_compose_basename and re.search(r"(^|/)compose/", norm_path)
    )
    if not _location_ok and not docker_project_root_exempt:
        matched_name, reason = basename, "Dockerfile/compose file only allowed under docker/ (or compose/ for a compose file)"

if matched_name is None:
    sys.exit(0)

msg = (
    f"BLOCKED: confirm required before writing {file_path}\n\n"
    f"Reason: matches forbidden-file pattern — {reason}\n\n"
    "Per project conventions this file should not be created without explicit user approval.\n\n"
    "Please ask the user:\n"
    f'  "I\'m about to write \'{file_path}\' which matches a forbidden-file pattern ({reason}).\n'
    '   Do you want me to proceed, or should I use a different path/approach?"\n\n'
    "Only proceed if the user explicitly says yes."
)

print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF
