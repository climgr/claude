---
name: Shell script conventions
description: Code standards, performance rules, and documentation requirements for CasjaysDev shell scripts (bash, zsh, sh, fish). Does NOT cover scripting languages such as Python, Ruby, Perl, PHP, or JavaScript.
type: user
---

## Script Header Template

The separator line is exactly: `# - - - - - - - - - - - - - - - - - - - - - - - -` (24 dashes, space-separated). Used between every logical block including after the shellcheck line.

### Header block (same fields for all shells)

```
#!/usr/bin/env {shell}
# shellcheck shell={shell}
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  %Y%m%d%H%M-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  {scriptname --help | README.md}
# @@Copyright        :  Copyright: (c) {year} Jason Hempstead, Casjays Developments
# @@Created          :  {Weekday, Month DD, YYYY HH:MM TZ}
# @@File             :  {file_name}
# @@Description      :  {short one-sentence description}
# @@Changelog        :  {short one-sentence changelog message}
# @@TODO             :  {short list of TODOs}
# @@Other            :  {anything that doesn't fit another field}
# @@Resource         :  {short list of resources, e.g. Stack Overflow links}
# @@Terminal App     :  {yes|no}
# @@sudo/root        :  {yes|no}
# @@Template         :  {template name, or shell/{shell} if no template}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="YYYYMMDDHHMM-git"
```

- **All scripts (bash, sh, zsh, fish, and any other shell) are licensed under WTFPL** — always set `# @@License : WTFPL` in the header; never MIT, Apache, or any other license for shell scripts
- `##@Version` uses double `#` — all other `@@` fields use single `#`
- `@@Created` — full weekday + date + time + timezone: `Wednesday, May 13, 2026 10:58 EDT`
- `@@Template` — template name if used; otherwise `shell/bash`, `shell/sh`, `shell/zsh`, `shell/fish`
- There IS a separator line after the shellcheck disable line
- `VERSION="YYYYMMDDHHMM-git"` is the **literal placeholder string** — AI must write it exactly as `YYYYMMDDHHMM-git` in new scripts, never substitute an actual date/time. The script itself replaces it at runtime via git hook or build step. When `--version` is called, this string is printed as-is unless replaced.
- **Never revert a real timestamp to the placeholder** — if a script already contains a real 12-digit timestamp like `VERSION="202605172147-git"`, that is a valid runtime-stamped value. Never replace it with `YYYYMMDDHHMM-git`. The placeholder is only for newly created scripts that have not yet been stamped.
- **Update the timestamp on every edit** — whenever AI edits an existing script, update exactly two things: (1) the `##@Version` line in the header, and (2) the first `VERSION=` assignment that appears after the header block. Set both to the current timestamp, e.g. `202605172147-git` (run `date +'%Y%m%d%H%M-git'` to get the value). Write the resolved value, not the shell expression. Do not touch any other `VERSION=` occurrences elsewhere in the script.
- The `shellcheck disable` line only appears in shells shellcheck supports — see table below

### Shell-specific differences

| Item | bash | sh | zsh | fish |
|------|------|----|-----|------|
| shellcheck shell line | `# shellcheck shell=bash` | `# shellcheck shell=sh` | *(omit)* | *(omit)* |
| shellcheck disable | `# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329` | same as bash | `# shellcheck disable=all` | *(omit entire line)* |
| `APPNAME` | `"${0##*/}"` | `"${0##*/}"` | `"${0:t}"` | `(path basename (status filename))` |
| `SCRIPT_SRC_DIR` | `"${BASH_SOURCE%/*}"` | `"$(dirname -- "$0")"` | `"${0:A:h}"` | `(path dirname (status filename))` |
| `SET_UID` | `"${UID}"` | `"$(id -u)"` | `"${UID}"` | `(id -u)` |
| `__cmd_exists` | `command -v "$1" &>/dev/null` | `command -v "$1" >/dev/null 2>&1` | `(( $+commands[$1] ))` | `command -q $argv[1]` |
| `__function_exists` | `declare -F "$1" &>/dev/null` | `case "$(type "$1" 2>/dev/null)" in *function*)` | `(( $+functions[$1] ))` | `functions -q $argv[1]` |
| color escapes | `\e[` | `\033[` | `\e[` | `\e[` |
| variables | `VAR=value` | `VAR=value` | `VAR=value` | `set -g VAR value` |
| vim modeline filetype | `filetype=sh` | `filetype=sh` | `filetype=zsh` | `filetype=fish` |

For `.ps1` and `.cmd`/`.bat` scripts: omit shellcheck lines entirely; use platform-native idioms (PowerShell cmdlets / CMD variables) per the Interpreter Detection section below.

### Standard boilerplate variables (after header)

```bash
# or shell-specific equivalent above
APPNAME="${0##*/}"
VERSION="YYYYMMDDHHMM-git"
RUN_USER="${USER}"
# or shell-specific equivalent above
SET_UID="${UID}"
# shell-specific — see table
SCRIPT_SRC_DIR="..."
```

**Section separators** between logical blocks:
```
# - - - - - - - - - - - - - - - - - - - - - - - - -
```

**Vim modeline** — always the last line of the file (filetype varies by shell — see table):
```
# ex: ts=2 sw=2 et filetype=sh
```

## Top-Level Script Structure

Env-var declarations and function definitions are **not freely interleaved** — the canonical scripts (`casjay-dotfiles/scripts/templates/scripts/shell/{bash,sh,zsh,fish}` skeletons, cross-checked against the larger `templates/scripts/bash/{system,user,simple,terminal,mgr-script.*}` templates and real production scripts like `dfmgr`, `devenvmgr`, `apimgr`, `buildx`) follow one fixed order, identical across bash/sh/zsh/fish:

1. **Header block** (`##@Version` + `# @@...` fields, shellcheck lines)
2. **Standard boilerplate + script variables** — `APPNAME`, `VERSION`, `RUN_USER`, `SET_UID`, `SCRIPT_SRC_DIR`, then any script-specific top-level vars (working dir, exit-status var, etc.)
3. **Color variables** (`PRINTF_SET_*` / `NO_COLOR` handling)
4. **Custom/project variables** — project-prefixed vars specific to this script
5. **Shared utility functions** — `__printf_color`, `__cmd_exists`, `__function_exists` (the larger templates insert `set -eo pipefail`, early `--debug`/`--no-color` pre-scans, and shared function-library sourcing — see "Library Scripts" below — around this point too)
6. **Custom functions** — all remaining `__`-prefixed project functions
7. **Trap registration** (`trap '' EXIT`; larger templates also add INT/TERM)
8. **Argument/flag parsing** (larger templates only) — always placed after every function it can call (`__help`, `__version`, etc.) is already defined
9. **Main application body** — executes inline at file scope under a `# Main application` / `# begin main app` marker comment; **no `main()` wrapper function** is used by convention
10. **Exit normalization** — `exit "$EXIT_STATUS"` (or `exitCode`) as the last executable line, before the trailing separator and vim modeline

**Rule of thumb: all variable declarations for a given block come before the functions that consume them, and all functions are fully defined before argument parsing or main-body code calls them.** Don't scatter unrelated `VAR=` assignments between function definitions, and don't write the argument-parsing block before every function it dispatches to exists. Within that constraint, ordering "does not matter" only in the narrow sense that bash executes top-to-bottom and a function only needs to exist before it's *called* — but the established project convention is still to group all vars, then all functions, then parsing, then main, not to interleave them freely.

## Shell Selection by Target Platform

Choose the shell based on where the script will run:

| Target | Correct shell | Reason |
|--------|--------------|--------|
| macOS + Linux + BSD (cross-platform) | `#!/usr/bin/env sh` (POSIX sh) | Lowest common denominator; runs everywhere |
| Linux-only or bash explicitly required | `#!/usr/bin/env bash` | Full bashisms available |
| Zsh environment / oh-my-zsh context | `#!/usr/bin/env zsh` | Full zshisms available |
| Fish shell environment | `#!/usr/bin/env fish` | Fish idioms |
| Windows | `.ps1` (PowerShell) or `.cmd`/`.bat` | Platform native |

**Use the shell's native idioms fully** — bash scripts use bashisms, zsh scripts use zshisms, sh scripts use POSIX only. Never write POSIX-compatible bash "just in case" — pick the right shell for the target and use it properly.

## Interpreter Detection

The shebang line or file extension determines which conventions apply. Always check before editing.

| Shebang / Extension | Interpreter | Idioms to use | Comment char |
|---|---|---|---|
| `#!/usr/bin/env bash` / `#!/bin/bash` | Bash | Bashisms: `[[ ]]`, `(( ))`, arrays, `${var@Q}`, `&>>`, etc. | `#` |
| `#!/usr/bin/env sh` / `#!/bin/sh` | POSIX sh | POSIX only: `[ ]`, `$(...)`, no arrays, no `local`, no `&>>` | `#` |
| `#!/usr/bin/env zsh` | Zsh | Zshisms: `${0:t}`, `(( $+commands ))`, `${0:A:h}`, etc. | `#` |
| `#!/usr/bin/env fish` | Fish | Fish: `set`, `if`/`end`, `function`/`end`, `command -q`, etc. | `#` |
| `#!/usr/bin/env python3` etc. | Python/Ruby/etc. | Language-native conventions and linter | `#` |
| `.ps1` | PowerShell | Cmdlets, `$variables`, `Verb-Noun`, `#Requires` | `#` |
| `.cmd` / `.bat` | Windows CMD | `@echo off`, `%variables%`, `GOTO`, `::` comments | `::` or `REM` |

**When there is no shebang** (e.g. a sourced library), infer from the calling context or ask.

**Header is always added** to every script regardless of shell, using the correct comment character. For `.cmd`/`.bat`, replace `#` with `::` throughout the header block.

## Error Handling — `set -e` and `pipefail`

Use the strictest set of flags your shell supports: `set -eo pipefail` for bash/zsh, `set -e` for POSIX sh. **`-o pipefail` is a bash/ksh/zsh extension — it is not in POSIX and must not appear in `#!/usr/bin/env sh` scripts.** **Do not add `-u` (nounset)** — scripts legitimately use empty or unset variables and `-u` fires false positives constantly. `set -e` itself has well-known false-positive exits that will silently abort a script if not handled. **You must know which commands return non-zero for normal, non-error reasons and guard them explicitly.**

| Command | Normal non-zero exit | Why it happens |
|---------|---------------------|----------------|
| `grep pattern file` | 1 | no match — not an error |
| `diff a b` | 1 | files differ — not an error |
| `[ condition ]` / `[[ condition ]]` | 1 | condition false — not an error |
| `(( expr ))` | 1 | result is zero — not an error |
| `command -v foo` | 1 | command not found — used to check existence |
| `type foo` | 1 | not found — used to check existence |
| `read var` | 1 | EOF reached — expected at end of input |

Every command in the table above will silently kill the script under `set -e` unless guarded. **Guard every one of them — no exceptions.**

```bash
# BAD — silently exits if grep finds no match
grep -- "pattern" file

# GOOD — condition block: set -e never triggers inside if/while/until tests
if grep -q -- "pattern" file; then
  echo "found"
fi

# GOOD — || true when the non-zero exit is genuinely ignorable
grep -- "pattern" file || true

# GOOD — || die when the non-zero exit is a real failure
grep -- "pattern" file || { echo "ERROR: pattern not found" >&2; exit 1; }

# BAD — (( )) exits 1 when result is 0; kills script mid-arithmetic
(( count++ ))

# GOOD — assign separately or use += to avoid the false exit
count=$(( count + 1 ))
```

**Shell settings:**

| Shell | Use | Reason |
|-------|-----|--------|
| bash | `set -eo pipefail` | `-e` exits on real errors, `pipefail` catches pipe failures |
| sh (POSIX) | `set -e` | `pipefail` is a bashism |
| zsh | `set -eo pipefail` | Same as bash |
| fish | Nothing needed | Fish error handling is built-in |

**Do not use `-u` (nounset).** Scripts legitimately use empty or unset variables — optional arguments, accumulator patterns, conditional defaults. `-u` treats an unset variable as an error, which fires false positives constantly. If you want to detect a genuinely unexpected unset variable, check it explicitly:

```bash
# BAD — -u kills the script on optional/empty vars
set -euo pipefail
# dies if not set, even though that's fine
echo "${OPTIONAL_ARG}"

# GOOD — check only where unset is a real bug
: "${REQUIRED_VAR:?REQUIRED_VAR must be set}"

# GOOD — safe default for optional vars
VALUE="${OPTIONAL_ARG:-}"
```

Place the shell flags immediately after the header block: `set -eo pipefail` for bash/zsh; `set -e` for POSIX sh.

**`trap` for cleanup:** use `EXIT` to clean up temp files and resources on any exit — clean or otherwise:

```bash
set -eo pipefail

__cleanup() {
  [ -n "${TEMP_DIR:-}" ] && rm -rf "${TEMP_DIR}"
}
trap '__cleanup' EXIT
```

`EXIT` fires on every exit path including normal completion. `ERR` is for error-specific messages only — not as a substitute for understanding which commands have false-positive exits.

## Signal Handling

### Which signals to trap and why

| Signal | Number | Trigger | When to trap |
|--------|--------|---------|-------------|
| `EXIT` | (pseudo) | Any exit path | **Always** — primary cleanup hook |
| `INT` | 2 | Ctrl-C | When you need to print a "cancelled" message or suppress the default `^C` echo |
| `TERM` | 15 | `kill` / container stop / systemd | When the script holds resources that must be released (sockets, lock files, child processes) |
| `QUIT` | 3 | Ctrl-\ | Rarely trapped — only suppress if core dumps are unwanted in your environment |
| `HUP` | 1 | Terminal closed / `nohup` | Trap in long-running daemons to reload config; ignore in short scripts |
| `WINCH` | 28 | Terminal resize | Only in TUI/interactive scripts that reflow layout based on terminal dimensions |
| `TSTP` | 20 | Ctrl-Z (suspend) | Almost never — let the shell handle job control; only trap if the script holds an exclusive resource |
| `PIPE` | 13 | Broken pipe (reader closed) | Rarely — `pipefail` (bash/zsh) + error handling is usually enough; trap only if you need a custom message |

`Ctrl+X` is not a POSIX signal — it has no special meaning in most terminals and does not raise a signal.

### Standard pattern

Always let `EXIT` do the cleanup. For signals that need extra behaviour (message, exit code), re-raise after cleanup so the caller sees the right `128+N` exit code:

```bash
set -eo pipefail

TEMP_DIR=
__cleanup() {
  [ -n "${TEMP_DIR:-}" ] && rm -rf "${TEMP_DIR}"
}

# Re-raise TERM and INT so callers see 128+15 / 128+2 instead of 0
__on_term() { echo "Terminated." >&2; exit 143; }
__on_int()  { echo "Interrupted." >&2; exit 130; }

trap '__cleanup' EXIT
trap '__on_term' TERM
trap '__on_int'  INT

TEMP_DIR="$(mktemp -d)"
```

`EXIT` fires after `__on_term`/`__on_int` return (or call `exit`), so `__cleanup` always runs exactly once.

### SIGWINCH — terminal resize

Only relevant in interactive/TUI scripts that query terminal dimensions. Re-query `tput` in the handler; never cache `COLS`/`LINES` as globals without a resize hook:

```bash
COLS=$(tput cols)
LINES=$(tput lines)

__on_winch() {
  COLS=$(tput cols)
  LINES=$(tput lines)
  # redraw or reflow here
}
trap '__on_winch' WINCH
```

### SIGHUP — daemon reload

Long-running scripts acting as daemons should trap `HUP` to re-read config without restarting:

```bash
__on_hup() {
  # reload config file, re-open log handles, etc.
  : "reloading config..."
}
trap '__on_hup' HUP
```

Short scripts: ignore `HUP` with `trap '' HUP` or just don't trap it (the default action terminates the process, which is usually fine).

### Rules

- **Always trap `EXIT`** — it is the single reliable cleanup hook; fires on normal exit, error exit, and most signals
- **Trap `TERM` and `INT`** in any script that creates files, starts child processes, holds network connections, or writes to a database — use explicit `exit N` to preserve `128+N` semantics for callers
- **Never swallow `INT`** without re-raising — a script that traps `INT` and exits `0` breaks `Ctrl-C` in pipelines and interactive use
- **`ERR` trap** is for diagnostic messages only (print the failing command, line number); never use it as a substitute for guarding false-positive exits
- **`QUIT`** — do not trap unless you have a specific reason; the default (core dump / terminate) is usually correct
- **`WINCH`** — trap only in scripts that actively render to the terminal; ignore in non-interactive scripts
- **`TSTP`** — do not trap; let the shell handle `Ctrl-Z` normally
- Declare all traps immediately after the shell flags (`set -eo pipefail` / `set -e`), before any code that creates resources
- Do not use `trap - SIGNAL` to reset a signal inside a handler — it is confusing and rarely correct; structure cleanup in `__cleanup` and call it explicitly if needed

## IFS Safety

When splitting strings by a custom delimiter, always save and restore `IFS`:

```bash
# BAD — permanently changes IFS for the rest of the script
IFS=':'
read -ra parts <<< "${value}"

# GOOD — IFS change is scoped to the read command only
# read is a builtin; IFS here is a command prefix, not global
IFS=':' read -ra parts <<< "${value}"

# GOOD — when IFS must be changed for a block, save/restore
old_IFS="${IFS}"
IFS=','
# ... work with comma-split data ...
IFS="${old_IFS}"
```

Never leave `IFS` modified globally — it causes silent splitting bugs in subsequent code that expects word-splitting behavior.

## Idempotent Config Writes

When a script sets a config value in a file that participates in a **drop-in override pattern**, always search all candidate locations before writing:

1. **Search all locations** — grep for the key/setting across every file in the pattern
2. **If found anywhere** — replace/update in place; never add a duplicate
3. **Only if not found anywhere** — append to or create the appropriate drop-in file

This prevents duplicate entries scattered across multiple files, which causes unpredictable precedence and hard-to-debug behaviour.

**Common drop-in patterns:**

| Base file | Drop-in directory |
|-----------|------------------|
| `/etc/sysctl.conf` | `/etc/sysctl.d/*.conf` |
| `/etc/security/limits.conf` | `/etc/security/limits.d/*.conf` |
| `/etc/profile` | `/etc/profile.d/*.sh` |
| `/etc/environment` | `/etc/environment.d/*.conf` (systemd only) |
| `/etc/sudoers` | `/etc/sudoers.d/*` |
| `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config.d/*.conf` |
| `/etc/hosts` | No drop-in — edit directly |
| `/etc/pam.d/{service}` | No drop-in — edit directly |

**Example — setting a sysctl value:**

```bash
_key="net.ipv4.ip_forward"
_val="1"
_setting="${_key} = ${_val}"
_found_in=""

for _f in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
  [ -f "${_f}" ] || continue
  if grep -qF -- "${_key}" "${_f}"; then
    _found_in="${_f}"
    break
  fi
done

if [ -n "${_found_in}" ]; then
  # Found — replace in place
  sed -i "s|^[# ]*${_key}.*|${_setting}|" "${_found_in}"
else
  # Not found anywhere — write a new drop-in
  printf '%s\n' "${_setting}" > /etc/sysctl.d/99-projectname.conf
fi

sysctl -p /etc/sysctl.d/99-projectname.conf 2>/dev/null || true
```

**Rules:**
- Prefer a drop-in file over editing the base file — keeps changes isolated and easy to remove
- Use a consistent drop-in filename (`99-{project_name}.conf`) so the script's changes are identifiable
- Replace with `sed -i` anchored to the key — never line-number-based replacement
- Apply the change immediately after writing when the subsystem supports it (`sysctl -p`, `source`, etc.)
- The same search-before-write logic applies to any structured config: `/etc/hosts` entries, `sudoers` rules, PAM lines, `authorized_keys`, etc.

## Code Standards

- **Functions**: ALL functions prefixed with `__` regardless of shell — `__my_function() {}` (bash/sh/zsh), `function __my_function` (fish). No exceptions.
- **Variables**:
  - **Prefixing exists to prevent namespace collisions, not as a style mandate.** Whether a global needs the `{SCRIPTNAME}_{VAR}` prefix (uppercase, e.g. `MYSCRIPT_VAR`; `{SCRIPTNAME}` is the script filename without extension, uppercased) depends on whether it can actually leak into a shell namespace it doesn't own:
    - **Sourced library files** (no shebang, or only ever `source`d / `.`-included) — every global lands directly in the caller's shell. Prefix all globals; never use generic prefixes like `APP_`, `MY_`, `SCRIPT_` — always the actual script/project name.
    - **Executed scripts** (has a shebang, runs as its own process) — prefix vars that cross a process boundary: `export`ed vars, and vars read as a caller-settable override via `${VAR:-default}` (these come from the invoking shell's environment even without being re-exported, so a generic name can still collide with the caller's namespace). Purely internal globals — assigned and consumed only within the script's own execution, never read from the incoming environment and never exported — don't need the prefix.
  - **Resolving `{SCRIPTNAME}` for a generic entry-point filename** — a literal basename is the default, but when the script's own name is a generic bootstrap/lifecycle verb shipped by many unrelated projects (`min.sh`, `bootstrap.sh`, `full.sh`, `uninstall.sh`; `install.sh` and `setup.sh` are exempt from variable naming entirely — see "Setup and Install Script Env Prefix"), using that bare verb defeats the collision-avoidance purpose stated above — `MIN_CONFIG_SETUP` collides just as easily as an unprefixed var, since plenty of unrelated projects also ship a `min.sh`. In that case `{SCRIPTNAME}` resolves to the **enclosing project's own name** (e.g. `pkmgr` for `pkmgr/scripts/min.sh`), not the individual entry-point filename. Whether to additionally fold the entry-point verb in as a disambiguating component then comes down to the variable's *scope*, not its spelling:
    - **Private to this one entry point** — no sibling script in the project reads or sets the same name — the entry-point verb is a legitimate disambiguating component: `PKMGR_MIN_CONFIG_SETUP`.
    - **Shared interface value** — any of the project's entry points (`min.sh`, `full.sh`, …) read/set it identically — drop the entry-point component and use the project name alone: `PKMGR_CONFIG_SETUP`. This is the same "Shared cross-script interface vars" exception below, applied one level up (project family, not just parent/child).
    Telling these apart requires knowing whether the project has sibling entry-point scripts and whether they share that variable — information outside the single line being linted. A lint pass that pattern-matches the line in isolation cannot resolve this; it must actually check the project's other entry-point scripts for the same var name before flagging either form as wrong.
  - **"Enclosing project" is the product/tool family, not always the current repo's own basename** — a git repo's top-level directory name is the default source for the project component, but when the repo is one of several per-target/per-distro variant repos of the same tool, published under a shared org (e.g. `pkmgr/rhel`, `pkmgr/alpine`, `pkmgr/arch`, `pkmgr/ubuntu`, `pkmgr/debian`, `pkmgr/fedora`, `pkmgr/raspbian` — each repo's own basename is just the OS target, not the tool's identity), the repo basename is the wrong answer: `CENTOS_MIN_CONFIG_SETUP` would vary per distro for what is the same tool's same variable, defeating the point of a stable prefix. In that case the project component is the shared org/family name (`PKMGR`), verified by checking that sibling repos under the same org ship the equivalent script with the equivalent variable. A repo whose own basename is a recognizable OS/distro/architecture target name (`centos`, `alpine`, `arch`, `debian`, `ubuntu`, `fedora`, `raspbian`, and similar) sharing an org with other same-shaped repos is the signal to use the org name instead of the repo name; an ordinary single-repo project still uses its own repo basename as before.
  - Function-scoped vars: declare with `local` in bash/zsh; `set -l` in fish; plain assignment in sh (no `local` in POSIX sh unless targeting bash/zsh)
  - Always use `_` (underscore) — never `-` (hyphen) in variable or function names
  - Exceptions to prefix rule (both cases above): well-known globals (`VERSION`, `APPNAME`, `RUN_USER`, `SET_UID`, `SCRIPT_SRC_DIR`, `HOME`, `PATH`, `USER`, `PWD`), loop variables, single-letter scratch vars
  - **Shared cross-script interface vars** — a generic name deliberately left unprefixed because it is a common convention read/set consistently across a script family so parent and child/sourced scripts (and sibling install/setup/uninstall scripts across projects) can interoperate without each needing to know the other's project-name prefix. Confirmed examples, verified recurring verbatim across `casjay-dotfiles/scripts/bin/*`, `casjay-dotfiles/scripts/templates/scripts/*`, and the `*mgr` repo family: `SCRIPTS_PREFIX`, `REPO_BRANCH`, `GIT_REPO_BRANCH`, `USER_HOME` (`"${USER_HOME:-$HOME}"`), `CASJAYSDEVDIR` (`"${CASJAYSDEVDIR:-/usr/local/share/CasjaysDev/scripts}"`), `SCRIPTSAPPFUNCTURL`, `SCRIPTSAPPFUNCTFILE` (both read into the local `SCRIPTSFUNCTURL`/`SCRIPTSFUNCTFILE` vars that fetch/source the shared function library), `SCRIPT_OPTS` (`export SCRIPT_OPTS="--debug"` on `--debug`), `SHOW_RAW` (`export SHOW_RAW="true"` on `--no-color`). Prefixing these would break the shared interface, not improve safety. This is a narrow exception: it applies only to names already established as a shared convention across the family (repeated verbatim across multiple scripts/repos, or literally passed down to a child/sourced script that expects that exact name) — a one-off generic name used by a single script for its own purpose still needs the project prefix. A name seen only inside a single `local` declaration (scoped to one function, not exported or read as a caller override) is not this exception — it's already exempt as a function-scoped var, not because it's a family convention.
  - **System environment variables — read freely, overwrite by category** — reading is always fine; use system vars as fallbacks anywhere (`RUN_USER="${SUDO_USER:-$USER}"`, `MYSCRIPT_FQDN="${MYSCRIPT_FQDN:-$HOSTNAME}"`). Use `{SCRIPTNAME}_{VAR}` for project-specific values. Overwriting rules:
    - **Shell mechanics — never overwrite:** `PS1`–`PS4`, `OPTIND`, `OPTARG`, `SHLVL`, all `BASH_*`/`ZSH_*`/`FISH_*` vars. Exception: `IFS` may be temporarily changed — save and restore, or scope to a subshell: `old_IFS="$IFS"; IFS=:; …; IFS="$old_IFS"` or `( IFS=:; … )`.
    - **Process identity — never overwrite:** `HOME`, `USER`, `LOGNAME`, `SHELL`, `UID`, `EUID`, `GID`, `PATH`, `PWD`, `OLDPWD`. **Container exception:** inside a Dockerfile `ENV` instruction, docker-compose `environment:` block, or a container `entrypoint.sh`, ALL of these are freely settable — the container is an isolated environment being initialized from scratch, not a host process. See `dockerfile_conventions.md`.
    - **Environment preferences — overwrite only when intentional:** `LANG`, `TZ`, `TERM`, `EDITOR`, `VISUAL`, `PAGER`, `HOSTNAME`, `HOST`. Store the value in a project-prefixed var first, then assign the system var from it when downstream processes must inherit it: `MYSCRIPT_LANG="${MYSCRIPT_LANG:-en_US.UTF-8}"; export LANG="${MYSCRIPT_LANG}"`. Never hardcode directly into the system var.
  - **Sane fallbacks** — every project var should have a sane default via `${VAR:-default}`. Build compound defaults from earlier vars where it makes sense:
    ```bash
    MYSCRIPT_FQDN="${MYSCRIPT_FQDN:-$HOSTNAME}"
    MYSCRIPT_DOMAIN="${MYSCRIPT_DOMAIN:-$(hostname -d)}"
    MYSCRIPT_ADMIN_NAME="${MYSCRIPT_ADMIN_NAME:-administrator}"
    MYSCRIPT_ADMIN_EMAIL="${MYSCRIPT_ADMIN_EMAIL:-${MYSCRIPT_ADMIN_NAME}@${MYSCRIPT_FQDN}}"
    MYSCRIPT_EMAIL_FROM_ADDRESS="${MYSCRIPT_EMAIL_FROM_ADDRESS:-no-reply@${MYSCRIPT_FQDN}}"
    MYSCRIPT_EMAIL_FROM_NAME="${MYSCRIPT_EMAIL_FROM_NAME:-My Application}"
    MYSCRIPT_PORT="${MYSCRIPT_PORT:-62080}"
    MYSCRIPT_LOG_LEVEL="${MYSCRIPT_LOG_LEVEL:-info}"
    MYSCRIPT_DATA_DIR="${MYSCRIPT_DATA_DIR:-/var/lib/myscript}"
    ```
    Exceptions — no `${VAR:-literal}` fallback:
    - **Secrets/credentials** (`MYSCRIPT_DB_PASSWORD`, `MYSCRIPT_API_KEY`, `MYSCRIPT_SECRET_KEY`, `MYSCRIPT_JWT_SECRET`) — generate with `__random_password`; if the script is idempotent, save with `__save_credential` (perms `600`, owned by `$RUN_USER:$RUN_USER` or `root:root` depending on context) and show once on first generation. See `__random_password` / `__save_credential` / `__load_credential` in Standard Utility Functions.
    - **Destructive targets** (`MYSCRIPT_BACKUP_DEST`, `MYSCRIPT_DEPLOY_TARGET`) — a wrong default silently operates on the wrong location; script must `exit 1` with a clear error if unset
    - **External service addresses in multi-env deployments** (`MYSCRIPT_DB_HOST`) — defaulting to `localhost` silently breaks in prod; script must `exit 1` with a clear error if unset
  - **Exporting vars for external tools** — when an external app, library, or tool expects a specific variable name (e.g. `DATABASE_URL`, `PGPASSWORD`), bridge from the project var and export only if required: `export DATABASE_URL="${MYAPP_DATABASE_URL}"`. Set the adapter immediately before the call that needs it — never at top-level unless the entire script is a thin wrapper.
- **`cd` always uses absolute paths** — never `cd relative/path` or `cd ../foo`; always `cd /full/path/to/dir`. Applies to all executable contexts: scripts, Makefiles, CI steps. Not applicable in user-facing documentation where relative or `~/`-based paths are clearer.
- **`\command` prefix only for alias-prone external binaries** — `\curl`, `\grep`, `\chmod`, `\mkdir`, `\cp`, `\mv`, `\rm`, `\ls`, `\cat`, `\sed`, `\diff`, etc. The backslash suppresses alias expansion only (use `command cmd` to also bypass shell functions; in fish use `command curl` — fish does not support `\` bypass). Never prefix shell keywords (`time`, `if`, `while`, `for`, `[[` — the backslash breaks keyword recognition and changes semantics), never prefix builtins (`cd`, `export`, `set` — the prefix is a no-op), and never prefix the first word of an allowlisted, pre-authorized, or hook-governed command (`gitcommit`, `git`, `make`, `docker`, `incus`, `podman`, `qemu-*`, `virsh`, `systemctl`). Permission rules match on literal text, so the backslash breaks prefix-matching and triggers avoidable prompts; PreToolUse hooks (`enforce-docker-rm.sh`, `block-host-toolchain.sh`) also key on the bare command name, and a `\` prefix must never be a way to slip past them. Container/VM aliases like `docker`→`podman` are deliberate environment configuration — bypassing them changes behavior, unlike suppressing a cosmetic `ls --color` alias.
- **Comments**: always ABOVE the code they describe — NEVER inline at end of line
- **Control flow**: always use `if/elif/else` — never `&&`/`||` chains for logic flow. `&&`/`||` are acceptable only for one-liner guards (`command || return 1`) not as substitutes for `if/elif/else` blocks
- **Newlines**: always add a newline at end of file
- **Headers**: update `##@Version` to the current timestamp (`date +'%Y%m%d%H%M-git'`) and the first `VERSION=` assignment after the header on every change — only those two, nothing else
- **Line length**: if a complete command is ≤180 characters, write it on a single line — including pipelines. Only split when the line exceeds 180 characters, or when the command contains an embedded program that inherently spans lines (e.g. a multi-line `awk` or `sed` script)

## Setup and Install Script Env Prefix

**Exempt: any script named exactly `install.sh` or `setup.sh` is excluded from variable naming — every var name is valid there, no prefix required.** These scripts share a family-wide variable vocabulary with the sourced installer framework (`mgr-installers.bash` and similar) and with generated unit/config text (systemd `ExecStart`/`WantedBy`/`User` keys, package lists such as `SYSTEM_PACKAGES`, `APPNAME`, `PLUGIN_DIR`, `BUILD_NAME`), so their var names are an interface to that framework, not a collision risk. Verified across `scriptmgr/*/install.sh`, `dfmgr/*/install.sh`, and `dfprivate/*/(install,setup).sh`. All other rules still apply to them.

Uninstall and other generic bootstrap/lifecycle entry-point scripts (`min.sh`, `full.sh`, `bootstrap.sh`, and similar — any filename that is itself a generic verb many unrelated projects also ship) must prefix every environment variable that is exported or read as a caller-settable override with `{PROJECT_NAME}_` (uppercased) — this is the case where the variable is meant to interface with the outside. Never use generic prefixes like `INSTALL_`, `SETUP_`, `UNINSTALL_`, `MIN_`, `FULL_`, or `BOOTSTRAP_` — they collide across projects and give no namespace. Purely internal vars used only within the script's own process follow the standard executed-script exemption above. The **shared cross-script interface vars** exemption above also applies here: a name like `SCRIPTS_PREFIX` or `REPO_BRANCH`/`GIT_REPO_BRANCH` that is passed down to a child/sourced script as an established family-wide convention stays unprefixed even inside one of these scripts.

`{PROJECT_NAME}` here is the same value as `{SCRIPTNAME}` resolves to under "Resolving `{SCRIPTNAME}` for a generic entry-point filename" and "'Enclosing project' is the product/tool family..." above (Code Standards → Variables) — read those two bullets for: whether to additionally fold the entry-point verb in as a disambiguating component (depends on the variable's scope — private to one entry point vs shared across sibling entry points), and how to derive the project name itself when the repo is a per-distro/per-target variant in a shared-org fleet (use the org name, not the repo's own basename, in that case).

```bash
# Correct — namespaced to the project
MYAPP_PORT="${MYAPP_PORT:-8080}"
MYAPP_CONFIG_DIR="${MYAPP_CONFIG_DIR:-/etc/myapp}"
MYAPP_SKIP_CONFIRM="${MYAPP_SKIP_CONFIRM:-0}"

# Wrong — generic, collides across projects
MIN_PORT="${MIN_PORT:-8080}"
UNINSTALL_CONFIG_DIR="${UNINSTALL_CONFIG_DIR:-/etc/myapp}"
```

The variable name after the prefix follows UPPER_SNAKE_CASE. Default values via `${VAR:-default}` are always provided for optional settings.

## Exit Codes

Use standard POSIX and sysexits codes — never invent custom schemes.

### POSIX core (all shells, Go, Rust)

| Code | Meaning | When to use |
|------|---------|-------------|
| `0` | Success | Command completed successfully |
| `1` | General error | Unspecified runtime failure |
| `2` | Misuse | Bad arguments, unknown flag, wrong usage — also what `getopt`/`getopts` returns on parse error |

### sysexits.h (preferred for scripts and CLI tools)

| Code | Name | When to use |
|------|------|-------------|
| `64` | `EX_USAGE` | Wrong number of arguments or invalid flag |
| `65` | `EX_DATAERR` | Input data malformed or invalid |
| `66` | `EX_NOINPUT` | Input file not found or not readable |
| `67` | `EX_NOUSER` | User not found |
| `68` | `EX_NOHOST` | Host not found |
| `69` | `EX_UNAVAILABLE` | Required service or resource unavailable |
| `70` | `EX_SOFTWARE` | Internal software error |
| `71` | `EX_OSERR` | OS-level error (fork failed, out of memory, etc.) |
| `72` | `EX_OSFILE` | System file missing or unreadable |
| `73` | `EX_CANTCREAT` | Output file cannot be created |
| `74` | `EX_IOERR` | I/O error |
| `75` | `EX_TEMPFAIL` | Temporary failure — caller may retry |
| `76` | `EX_PROTOCOL` | Remote protocol error |
| `77` | `EX_NOPERM` | Insufficient permissions (not root, missing capability) |
| `78` | `EX_CONFIG` | Configuration error |

### Signal-terminated processes

Processes killed by a signal exit with `128 + {signal}`:

| Code | Signal | Common cause |
|------|--------|-------------|
| `130` | `128+2` SIGINT | Ctrl-C |
| `137` | `128+9` SIGKILL | Forced kill |
| `143` | `128+15` SIGTERM | Graceful shutdown request |

### Rules

- `--help` and `--version` always exit `0`
- Unknown flag or bad argument: exit `2` (POSIX misuse) or `64` (EX_USAGE) — be consistent within a project
- Missing required file: exit `66` (EX_NOINPUT)
- Missing permission: exit `77` (EX_NOPERM)
- Config file invalid: exit `78` (EX_CONFIG)
- Never use exit codes outside `0–78` or `128–143` for your own errors — those ranges are reserved
- Scripts: use bare integer `exit N`; Go: `os.Exit(N)`; Rust: `std::process::exit(N)` or `clap` exit handling

## CLI Flags and Argument Parsing

### Standard flags (all interactive scripts, all shells)

| Flag | Short | Values | Behavior |
|------|-------|--------|----------|
| `--help` | `-h` | — | Print help and exit 0 — never escalate privileges |
| `--version` | `-v` | — | Print version and exit 0 — never escalate privileges |
| `--debug` | *(none)* | — | Enable debug output |
| `--color` | *(none)* | `auto` (default) / `yes` / `no` | Color output — `auto`: TTY detect; `yes`: force on; `no`: force off |

- `-h` and `-v` are the **only** short flags defined by default. No other short flags unless explicitly specified in `{project_dir}/IDEA.md`.
- `--debug` and `--color` have no short equivalents.
- `--color auto` detects terminal capability (default); `yes` forces color on; `no` disables it and removes emojis from output.
- `--help` and `--version` must **never** require root/sudo — exit immediately with the requested output, regardless of privilege state.

### Help output format

**Applies everywhere help is shown.** Every context uses identical formatting. No exceptions.

**Shell scripts** — `--help`/`-h` at the main level only; subcommands use bare `help` (no `--`). Shell native parsers (`getopts`, `zparseopts`, `argparse`) get complicated inside subcommand handlers, so `--` flags are avoided there.

**Go / Rust / compiled languages** — `--help` and `help` both work at every level; the argument parser (clap, cobra, etc.) handles it cleanly.

```
{item}                                - {description}
```

- **Item column:** left-aligned, padded to exactly **38 characters** with spaces
- **Separator:** `- ` (dash + one space) immediately after the 38-char field
- **Description:** plain text, ≤ **100 characters**
- **Max line length:** 38 + 2 + 100 = **140 characters**

#### Reusable primitives

Define these four functions once (in a shared `helpers.sh` or at the top of every script) and build all help output from them — never call `printf` directly inside a help function:

```bash
__help_header() {
  # Usage line — call once at the top of every help block
  printf '\n\033[1;37mUsage:\033[0m %s\n' "$1"
}

__help_section() {
  # Section heading (Options, Commands, Arguments, etc.)
  printf '\n\033[1;37m%s:\033[0m\n' "$1"
}

__help_line() {
  # One item — item in 38-char field, then "- description"
  printf '  %-38s- %s\n' "$1" "$2"
}

__help_footer() {
  # Trailing blank line
  printf '\n'
}
```

#### Building a help block

Every help function (main, per-subcommand, nested) is assembled from the same four primitives:

```bash
# Main help
__help() {
  __help_header "${APPNAME} [options] [command]"
  __help_section "Options"
  __help_line "--help"       "Show this help message and exit"
  __help_line "--version"    "Show version and exit"
  __help_line "--debug"      "Enable debug output"
  __help_line "--color auto" "Control color output (auto|yes|no)"
  __help_section "Commands"
  __help_line "init"       "Initialize a new project"
  __help_line "build"      "Build the project"
  __help_line "help"       "Show this help message"
  __help_footer
}

# Subcommand help — no --help here; subcommands use bare "help" only
__help_init() {
  __help_header "${APPNAME} init <name> [help]"
  __help_section "Arguments"
  __help_line "<name>"  "Name of the project to initialize"
  __help_line "help"    "Show this help message"
  __help_section "Options"
  __help_line "--force" "Overwrite existing files"
  __help_footer
}
```

#### Help dispatching

Main level handles `-h`, `--help`, and bare `help`. Subcommand level handles bare `help` only — no `--help` inside subcommand handlers:

```bash
# Main argument parsing — --help and bare "help" both work
case "${1:-}" in
  -h|--help|help) __help; exit 0 ;;
esac

# Subcommand dispatch — bare "help" only inside subcommands
case "${subcmd}" in
  init)
    case "${2:-}" in
      help) __help_init; exit 0 ;;
    esac
    cmd_init "$@"
    ;;
  help|"") __help; exit 0 ;;
esac
```

Rules:
- **Main level:** `-h`, `--help`, and `help` are all equivalent — call the same `__help` function
- **Subcommand level:** `help` only (no `--help`) — avoids shell parser complexity inside subcommand handlers
- `help` with no subcommand shows the parent-level help
- Never write separate implementations for each trigger — all must call the same `__help*` function
- **No escalation** — help at every level (main, subcommand, nested) must never call `sudo`, require root, or check privilege state; exit immediately with the help text

### Toggle flags — `--enable`, `--disable`, `--yes`, `--no`

Never use compound hyphenated flags (`--enable-tls`, `--disable-cache`). Instead the flag takes the feature name as a required argument: `--enable tls`, `--disable cache`. Use the same pattern for `--yes` and `--no`. Both `--flag=value` and `--flag value` forms must work.

**Exception:** `--color` is the standard three-value enum (`auto`/`yes`/`no`) — handled the same way.

```bash
# bash — both --flag=value and --flag value supported
while getopts ":hv-:" opt; do
  case "${opt}" in
    -)
      flag="${OPTARG%%=*}"
      case "${flag}" in
        debug)   SCRIPTNAME_DEBUG=1; continue ;;
        help)    __help; exit 0 ;;
        version) __version; exit 0 ;;
      esac
      if [[ "${OPTARG}" == *=* ]]; then
        val="${OPTARG#*=}"
      else
        val="${!OPTIND}"; OPTIND=$(( OPTIND + 1 ))
      fi
      case "${flag}" in
        color)   COLOR_FLAG="${val}"     ;;
        enable)  ENABLE_TARGET="${val}"  ;;
        disable) DISABLE_TARGET="${val}" ;;
        yes)     YES_TARGET="${val}"     ;;
        no)      NO_TARGET="${val}"      ;;
        *) printf 'Unknown option: --%s\n' "${flag}" >&2; exit 2 ;;
      esac ;;
    h) __help; exit 0    ;;
    v) __version; exit 0 ;;
    *) printf 'Unknown option: -%s\n' "${OPTARG}" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
```

```sh
# POSIX sh — eval to consume next positional when no = present
while getopts ":hv-:" opt; do
  case "${opt}" in
    -)
      flag="${OPTARG%%=*}"
      case "${flag}" in
        debug)   SCRIPTNAME_DEBUG=1; continue ;;
        help)    __help; exit 0 ;;
        version) __version; exit 0 ;;
      esac
      if [ "${OPTARG}" != "${flag}" ]; then
        val="${OPTARG#*=}"
      else
        eval "val=\${$OPTIND}"
        OPTIND=$(( OPTIND + 1 ))
      fi
      case "${flag}" in
        color)   COLOR_FLAG="${val}"     ;;
        enable)  ENABLE_TARGET="${val}"  ;;
        disable) DISABLE_TARGET="${val}" ;;
        yes)     YES_TARGET="${val}"     ;;
        no)      NO_TARGET="${val}"      ;;
        *) printf 'Unknown option: --%s\n' "${flag}" >&2; exit 2 ;;
      esac ;;
    h) __help; exit 0    ;;
    v) __version; exit 0 ;;
    *) printf 'Unknown option: -%s\n' "${OPTARG}" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
```

```zsh
# zsh — zparseopts, = optional; both forms supported natively
zparseopts -D -E -- -color:=opt_color -enable:=opt_enable -disable:=opt_disable -yes:=opt_yes -no:=opt_no
COLOR_FLAG="${opt_color[2]}"
ENABLE_TARGET="${opt_enable[2]}"
DISABLE_TARGET="${opt_disable[2]}"
```

```fish
# fish — argparse; both forms supported natively
argparse 'color=' 'enable=' 'disable=' 'yes=' 'no=' -- $argv
set COLOR_FLAG $_flag_color
set ENABLE_TARGET $_flag_enable
set DISABLE_TARGET $_flag_disable
```

### NO_COLOR support

Every interactive script must honor the `NO_COLOR` environment variable ([no-color.org](https://no-color.org/)):

```bash
# At the top of the script, after variable declarations
if [[ -n "${NO_COLOR}" ]]; then
  # disable all color output
  COLOR_RESET=""
  COLOR_RED=""
  # ... all color vars set to empty string
fi
```

`--color no` sets the same state as `NO_COLOR` being present. Both must be checked; either disables color and emojis in output.

All scripts and compiled binaries use `--color auto|yes|no`. `--no-color` is not a valid flag anywhere — `--color no` covers it and is unambiguous.

### Argument parsing — use the shell's native builtin parser

**Always use the shell's native builtin argument parser.** Never use a manual `while [[ $# -gt 0 ]]; do ... shift; done` loop — that pattern is fragile, inconsistent, and impossible to unit-test cleanly. Each shell has its own builtin; use it everywhere flags are needed.

| Shell | Parser | Long option support |
|-------|--------|-------------------|
| bash | `getopts` built-in with `-:` trick | Short (`-h`) + long (`--help`) + `--flag=value` + `--flag value` |
| sh (POSIX) | `getopts` built-in with `-:` trick | Same as bash |
| zsh | `zparseopts` built-in | Yes — including `--flag=value` |
| fish | `argparse` built-in | Yes |

**bash / sh — `getopts` with `-:` trick (short + long flags, both `--flag=value` and `--flag value`):**

```bash
while getopts ":hv-:" opt; do
  case "${opt}" in
    h) __help; exit 0 ;;
    v) __version; exit 0 ;;
    -)
      flag="${OPTARG%%=*}"
      case "${flag}" in
        help)    __help; exit 0    ;;
        version) __version; exit 0 ;;
        debug)   SCRIPTNAME_DEBUG=1; continue ;;
      esac
      # value-taking flags — detect = inline vs space-separated
      if [[ "${OPTARG}" == *=* ]]; then
        val="${OPTARG#*=}"
      else
        val="${!OPTIND}"; OPTIND=$(( OPTIND + 1 ))
      fi
      case "${flag}" in
        color) COLOR_FLAG="${val}" ;;
        *) printf 'Unknown option: --%s\n' "${flag}" >&2; exit 2 ;;
      esac ;;
    *) printf 'Unknown option: -%s\n' "${OPTARG}" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
```

The `-:` in the optstring tells `getopts` to treat `-` as a valid option character; `${OPTARG}` holds the rest after `--`. For value-taking flags, detect `=` in OPTARG to distinguish `--flag=value` from `--flag value`. Boolean flags (`--debug`) must be handled before the value-consuming block. POSIX sh uses `eval "val=\${$OPTIND}"` instead of `${!OPTIND}`.

**zsh — `zparseopts` pattern:**

```zsh
zparseopts -D -E -- h=opt_help -help=opt_help v=opt_version -version=opt_version -debug=opt_debug -color:=opt_color
[[ -n "${opt_help}" ]]    && { __help; exit 0 }
[[ -n "${opt_version}" ]] && { __version; exit 0 }
[[ -n "${opt_debug}" ]]   && SCRIPTNAME_DEBUG=1
[[ -n "${opt_color}" ]]   && COLOR_FLAG="${opt_color[2]}"
```

**fish — `argparse` pattern:**

```fish
argparse h/help v/version debug 'color=' -- $argv
or return 1
if set -q _flag_help;    __help; return 0; end
if set -q _flag_version; __version; return 0; end
if set -q _flag_debug;   set -g SCRIPTNAME_DEBUG 1; end
if set -q _flag_color;   set -g COLOR_FLAG $_flag_color; end
```

## Library Scripts — Sourced vs Direct Execution

Every library/shared script must detect whether it is being sourced or run directly and act accordingly — sourced libraries define functions and variables only; direct execution can show help, run self-tests, or error out.

Per-shell detection pattern:

**bash:**
```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # running directly
  __main "$@"
fi
```

**sh (POSIX):**
```sh
# $0 is the interpreter name when sourced (e.g. "sh" or "-sh")
# Use parameter expansion (no basename fork) — strip leading path; compare to bare $0
_self="${0##*/}"
case "$0" in
  *"${_self}")
    # running directly — $0 matches the script name
    __main "$@"
    ;;
esac
```

**zsh:**
```zsh
if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  # running directly
  __main "$@"
fi
```

**fish:**
```fish
if status is-script
  # running directly (not sourced)
  __main $argv
end
```

When sourced: only define functions and set variables — do not execute side effects, print output, or exit.
When run directly: print help, run self-tests, or call `__main`.

## Performance — No UUOC, Minimize Forks

Every `$(...)`, pipe, and external command spawns a subprocess. Minimize forks in all shells by preferring built-ins and parameter expansion over external commands. These rules apply universally — bash, sh, zsh, fish.

**File reading:**
```bash
# BAD
contents="$(cat file)"
cat file | grep pattern

# GOOD
contents="$(< file)"
grep pattern file
```

**Exception:** hook scripts (`home/hooks/*.sh`) reading their JSON stdin payload — hook
stdin is a socket, so `$(< /dev/stdin)` fails with `ENXIO: No such device or address`;
bare `$(cat)` (no filename) is the only correct read and is not a UUOC violation there.
```bash
# BAD — fails with ENXIO, hook stdin is a socket
INPUT="$(< /dev/stdin)"

# REQUIRED in hooks
INPUT="$(cat)"
```

**Path manipulation — parameter expansion, NOT basename/dirname:**
```bash
# BAD
name="$(basename -- "$path")"
dir="$(dirname -- "$path")"

# GOOD
# basename
name="${path##*/}"
# dirname
dir="${path%/*}"
# strip extension
stem="${name%.ext}"
```

**String matching — `[[ ]]`, NOT `echo | grep`:**
```bash
# BAD
if echo "$var" | grep -q "pattern"; then

# GOOD
if [[ "$var" == *"pattern"* ]]; then
```

**Regex — `=~` + `BASH_REMATCH`, NOT `echo | grep -E`:**
```bash
if [[ "$url" =~ ^(https?):// ]]; then
  protocol="${BASH_REMATCH[1]}"
fi
```

**Splitting — parameter expansion, NOT `echo | cut`:**
```bash
# BAD:  echo "$ver" | cut -d. -f1
# GOOD: "${ver%%.*}"
```

**Parsing — `read`, NOT `cat | awk` when bash suffices:**
```bash
# BAD:  cat /proc/loadavg | awk '{print $1}'
# GOOD: read -r load1 load5 _ _ _ < /proc/loadavg
```

**Stdin — let tools read directly, do NOT `cat - |` into them:**
```bash
# BAD:  cat - | sed 's/x/y/'
# GOOD: sed 's/x/y/'
```

**grep — always use `--` before the query:**
```bash
# BAD:  grep -r "pattern" file
# BAD:  grep "pattern" file
# GOOD: grep -r -- "pattern" file
```

`--` signals end of options, preventing a query that starts with `-` from being misinterpreted as a flag. Apply to all `grep` invocations.

**Never use grep aliases — they may not exist:**

| Never | Use instead |
|-------|------------|
| `egrep` | `grep -E` |
| `fgrep` | `grep -F` |
| `rgrep` | `grep -r` |

Always `grep {flags} -- {query}` — no exceptions.

## Terminal Display — Alt Buffer and ANSI Escapes

### Alt buffer

Any script that is a TUI or acts as a TUI (interactive menus, full-screen output, progress UIs) **must** use the alternate screen buffer. This preserves the user's scrollback and restores the terminal cleanly on exit.

```bash
# Enter alt buffer + set blinking I-beam cursor
printf '\e[?1049h\e[5 q'

# Always restore on exit — use a trap so it fires even on Ctrl-C
trap 'printf "\e[?1049l\e[0 q"' EXIT
```

- `\e[?1049h` — enter alternate screen buffer
- `\e[?1049l` — leave alternate screen buffer (restore normal screen)
- `\e[5 q` — blinking I-beam cursor (preferred)
- `\e[0 q` — restore terminal default cursor on exit

The `EXIT` trap must be set **before** entering the alt buffer so it fires on all exit paths including signals.

Non-TUI scripts (one-shot output, batch processing, log writers) must NOT enter the alt buffer.

### ANSI escapes — never tput

`tput` forks a subprocess for every call — forbidden under the minimize-forks rule. Use ANSI escape sequences directly via `printf`.

| tput call | ANSI equivalent |
|-----------|----------------|
| `tput smcup` | `printf '\e[?1049h'` |
| `tput rmcup` | `printf '\e[?1049l'` |
| `tput clear` | `printf '\e[2J\e[H'` |
| `tput cup R C` | `printf '\e[%d;%dH' $((R+1)) $((C+1))'` |
| `tput civis` | `printf '\e[?25l'` |
| `tput cnorm` | `printf '\e[?25h'` |
| `tput bold` | `printf '\e[1m'` |
| `tput sgr0` | `printf '\e[0m'` |
| `tput setaf 1` | `printf '\e[31m'` |
| `tput setab 2` | `printf '\e[42m'` |

Use `printf` — never `echo -e` (not portable) or `echo -n` for escape sequences.

Color and cursor sequences must be suppressed when `NO_COLOR` is set or `--color no` is passed — wrap them in a helper:

```bash
__ansi() {
  # Emit ANSI escape only when color is enabled
  if [[ -z "${NO_COLOR}" ]]; then
    printf '%s' "$1"
  fi
}
```

---

## Documentation Triple Sync

Every script change requires updating all three in the same commit:
1. `__help()` inside the script itself
2. `man/{script}.1`
3. Completions for every supported shell: `completions/_{script}_completions.bash`, `completions/_{script}_completions.zsh`, `completions/{script}.fish` (fish's filename has no underscore prefix or `_completions` suffix — see "Zsh and fish completions" below)

**Exempt from triple sync:** hook scripts, sourced library files, and non-interactive scripts that are not user-facing commands. These do not have `__help()`, man pages, or completions.

**Project-level exemption — don't invent `man/` or `completions/` where a project doesn't already have them.** Triple sync applies only when the project already maintains that documentation surface (an existing `man/` dir, an existing `completions/` dir, or `IDEA.md`/`AI.md` says to ship them). A single-script repo, a `script-collection`-type project, or any project that has never shipped man pages or shell completions does not gain a new `man/`/`completions/` directory just because a script inside it grew a new flag — that's out-of-scope directory creation, not doc sync. `__help()` itself stays mandatory for every user-facing command regardless — it costs nothing and lives inside the script; the file-tree obligations (`man/`, `completions/`) are the part that's conditional on the project already having them.

**Internal structure of the completion file** — verified against `casjay-dotfiles/scripts/templates/scripts/completions/*.bash`: the whole file is one `_{script}_completion() { ... }` function (single leading underscore — distinct from the `__` prefix used everywhere else in a script). Inside it: a single `local` block declaring every working variable up front, then `_init_completion || return`, then any inner one-off helpers defined with a **triple**-underscore prefix (`___jq`, `___find_cmd`, `___grep_env`, etc.) — this `___` prefix is unique to completion-file inner helpers and does not apply anywhere else; it exists specifically to avoid colliding with the script's own `__`-prefixed functions when both get sourced into the same shell during completion.

### Zsh and fish completions

**No existing casjay-dotfiles precedent exists for zsh or fish completions** — `gen-completion` only emits bash, and the only fish `completions/` reference found (`server/etc/skel/.config/fish/config.fish`'s `make_completion`) is a generic "borrow another command's completions" trick, not a per-script completion author pattern. The templates below are a deliberate adaptation of the real bash `simple.bash`/`system.bash` structure into each shell's native completion idiom — same variable roles, same `___`-prefixed private-helper convention, same semantic-correctness rules from "Completion Accuracy" below — not a copy of an observed pattern. Flag this section for review once real zsh/fish completions exist in casjay-dotfiles to confirm or correct it.

**Filename convention:**

| Shell | Installed filename | Why |
|-------|---------------------|-----|
| bash | `_{script}_completions.bash` | existing convention; sourced by a generated loader (`install.sh` writes a loop over `completions/*.bash`), not bash's own autoload |
| zsh | `_{script}_completions.zsh` | same custom-loader model as bash — mirrors the naming pattern since `compdef` registers correctly however the file gets sourced |
| fish | `{script}.fish` — **no underscore prefix, no `_completions` suffix** | fish's own autoloader requires the filename to exactly match the command name (`completions/{cmd}.fish`) if ever dropped into a fish `completions/` directory on `$fish_complete_path`; breaking this forfeits fish's free native autoload for no benefit |

**Concept mapping** (bash var/mechanism → zsh → fish):

| Bash | Zsh | Fish |
|------|-----|------|
| entry function `_{script}_completion` | entry function `_{script}_completion`, registered via `compdef _{script}_completion {script}` | no wrapper function required; `complete -c {script} ...` lines are the unit, with shared logic in a private `__{script}_comp_*`-prefixed function when reused |
| `LONGOPTS`/`SHORTOPTS` (flag list) | `local -a LONGOPTS`/`SHORTOPTS`, fed to `_arguments -s` | one `complete -c {script} -l {flag} -d '{description}'` per long flag, `-s {short}` for the short form |
| `ARRAY` (first-positional candidates, e.g. subcommands) | `_describe` branch on `state == first` | `complete -c {script} -n '__{script}_no_subcommand' -a "$ARRAY"` |
| `LIST` (later-positional candidates) | `_describe` branch on `state == rest` | `complete -c {script} -n 'not __{script}_no_subcommand' -a "$LIST"` |
| `--no-*`/`--yes-*` toggle handling | `'*--no-[TARGET]:target:->no_targets'`-style spec in `_arguments`, or a plain glob entry in `LONGOPTS` | `complete -c {script} -l no- -d 'disable a target'` (fish matches `-l` by prefix when the flag itself is a prefix form) |
| `___`-prefixed private helpers | same `___`-prefixed helpers, defined as zsh functions inside the entry function | same `___`-prefixed helpers, defined as fish functions (fish has no nested-function scoping, so give them the full `___{script}_name` form to avoid collisions) |
| `complete -F _{script}_completion -o default {script}` (registration) | `compdef _{script}_completion {script}` | registration is implicit — each `complete -c {script}` line registers itself |

**Zsh template** (adapted from `completions/simple.bash`):

```zsh
#!/usr/bin/env zsh
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  GEN_SCRIPT_REPLACE_VERSION
# @@Author           :  GEN_SCRIPT_REPLACE_AUTHOR
# @@Contact          :  GEN_SCRIPT_REPLACE_EMAIL
# @@License          :  GEN_SCRIPT_REPLACE_LICENSE
# @@ReadME           :  GEN_SCRIPT_REPLACE_FILENAME --help
# @@Copyright        :  GEN_SCRIPT_REPLACE_COPYRIGHT
# @@Created          :  GEN_SCRIPT_REPLACE_DATE
# @@File             :  GEN_SCRIPT_REPLACE_FILENAME
# @@Description      :  GEN_SCRIPT_REPLACE_DESC
# @@Changelog        :  GEN_SCRIPT_REPLACE_CHANGELOG
# @@TODO             :  GEN_SCRIPT_REPLACE_TODO
# @@Other            :  GEN_SCRIPT_REPLACE_OTHER
# @@Resource         :  GEN_SCRIPT_REPLACE_RES
# @@Terminal App     :  GEN_SCRIPT_REPLACE_TERMINAL
# @@sudo/root        :  GEN_SCRIPT_REPLACE_SUDO
# @@Template         :  completions/zsh
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=all
# - - - - - - - - - - - - - - - - - - - - - - - - -
#compdef GEN_SCRIPT_REPLACE_FILENAME

_GEN_SCRIPT_REPLACE_FILENAME_completion() {
  #####################################################################
  local -a LONGOPTS ARRAY LIST OPTS_NO OPTS_YES
  local curcontext="$curcontext" state
  #####################################################################
  ___jq() { jq -rc "$@" 2>/dev/null; }
  ___find_cmd() { find -L "${1:-$CONFDIR/}" -maxdepth ${3:-3} -type ${2:-f} 2>/dev/null; }
  #####################################################################
  LONGOPTS=(
    '--completions[list completion styles]'
    '--config[edit config]'
    '(-h --help)'{-h,--help}'[show help]'
    '(-v --version)'{-v,--version}'[show version]'
    '--debug[enable debug output]'
    '*--no-[disable a target]:target:'
    '*--yes-[enable a target]:target:'
  )
  ARRAY=()
  LIST=()
  #####################################################################
  _arguments -C -s \
    $LONGOPTS \
    '1: :->first' \
    '*: :->rest'

  case $state in
    first) _describe 'command' ARRAY ;;
    rest)  _describe 'argument' LIST ;;
  esac
}

compdef _GEN_SCRIPT_REPLACE_FILENAME_completion GEN_SCRIPT_REPLACE_FILENAME
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=zsh
```

**Fish template** (adapted from `completions/simple.bash`):

```fish
#!/usr/bin/env fish
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  GEN_SCRIPT_REPLACE_VERSION
# @@Author           :  GEN_SCRIPT_REPLACE_AUTHOR
# @@Contact          :  GEN_SCRIPT_REPLACE_EMAIL
# @@License          :  GEN_SCRIPT_REPLACE_LICENSE
# @@ReadME           :  GEN_SCRIPT_REPLACE_FILENAME --help
# @@Copyright        :  GEN_SCRIPT_REPLACE_COPYRIGHT
# @@Created          :  GEN_SCRIPT_REPLACE_DATE
# @@File             :  GEN_SCRIPT_REPLACE_FILENAME
# @@Description      :  GEN_SCRIPT_REPLACE_DESC
# @@Changelog        :  GEN_SCRIPT_REPLACE_CHANGELOG
# @@TODO             :  GEN_SCRIPT_REPLACE_TODO
# @@Other            :  GEN_SCRIPT_REPLACE_OTHER
# @@Resource         :  GEN_SCRIPT_REPLACE_RES
# @@Terminal App     :  GEN_SCRIPT_REPLACE_TERMINAL
# @@sudo/root        :  GEN_SCRIPT_REPLACE_SUDO
# @@Template         :  completions/fish
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -l LONGOPTS --completions --config --debug --help --version
set -l ARRAY
set -l LIST

function ___GEN_SCRIPT_REPLACE_FILENAME_no_subcommand
  set -l cmd (commandline -opc)
  test (count $cmd) -eq 1
end

for opt in $LONGOPTS
  complete -c GEN_SCRIPT_REPLACE_FILENAME -l $opt
end
complete -c GEN_SCRIPT_REPLACE_FILENAME -s h -l help -d 'show help'
complete -c GEN_SCRIPT_REPLACE_FILENAME -s v -l version -d 'show version'
complete -c GEN_SCRIPT_REPLACE_FILENAME -l no- -d 'disable a target'
complete -c GEN_SCRIPT_REPLACE_FILENAME -l yes- -d 'enable a target'

complete -c GEN_SCRIPT_REPLACE_FILENAME -n ___GEN_SCRIPT_REPLACE_FILENAME_no_subcommand -a "$ARRAY"
complete -c GEN_SCRIPT_REPLACE_FILENAME -n 'not ___GEN_SCRIPT_REPLACE_FILENAME_no_subcommand' -a "$LIST"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=fish
```

## Completion Accuracy

Completions must be **semantically correct for the flag or argument's expected input type**. A completion that offers the wrong type of candidates is worse than no completion — it misleads the user into selecting something the script will reject.

**Type mapping — use the right completion action for the flag:**

| Flag expects | bash (`compgen`/`complete`) | zsh (`compadd`/`_arguments`) | fish |
|---|---|---|---|
| Any file | `_filedir` / `complete -f` | `_files` | `__fish_complete_path` |
| Specific file extension | `_filedir '*.ext'` | `_files -g '*.ext'` | `__fish_complete_path "*.ext"` |
| Directory only | `_filedir -d` / `complete -d` | `_files -/` | `__fish_complete_directories` |
| Fixed choices | `COMPREPLY=($(compgen -W "a b c"))` | `compadd a b c` | `echo -e "a\nb\nc"` |
| Hostname | `compgen -A hostname` | `_hosts` | `__fish_print_hostnames` |
| Username | `compgen -A user` | `_users` | `__fish_complete_users` |
| PID | `compgen -A pid` | `_pids` | `__fish_complete_pids` |
| Running service | `systemctl list-units --type=service` | `_systemd_units` | `__fish_systemctl_services` |
| Nothing / flag only | no completion registered for value | `()` (no action) | no value completion |

**Rules:**
- **Never complete files for a flag that does not accept a file path** — `--verbose`, `--dry-run`, `--count 3` do not need filesystem completion
- **Never complete directories for a flag that expects a file**, and vice versa
- **Fixed-value flags must only offer their valid values** — `--format json|yaml|toml` must complete exactly those three; do not fall back to files
- **Flags with no argument (boolean/switch flags) must not offer any value completion** at all
- **Positional arguments follow the same rules** as named flags — complete the type the script actually accepts at that position
- **Subcommand completions** must be derived from the script's actual subcommand list — never hardcoded stubs that diverge from `__help()` output
- **No over-completion** — do not offer completions "just in case"; if you are unsure what a flag accepts, read the script's argument handling before writing the completion

## Self-Contained Scripts

Scripts must bundle all logic they need — no `source` or `.` includes:

```bash
# BAD
source /path/to/lib.sh
. "$SCRIPT_SRC_DIR/helpers.sh"

# GOOD — inline the required logic
```

**Exception:** profile/shell init scripts are explicitly designed to source files: `.bashrc`, `.bash_profile`, `.profile`, `.zshrc`, `.zshenv`, `.zprofile`, `.fishrc`, and analogues. These may use `source`/`.` freely.

## Standard Utility Functions

These functions are defined in scripts when needed — not included by default. Copy verbatim; do not rename or alter signatures. All variables are `local`; functions work as direct calls or in command substitution (`var="$(__determine_domain_name)"`).

### `__determine_domain_name`

Returns the runtime domain name. Tries `hostname -d` first; falls back to stripping the first label from `hostname -f`. Returns 1 if both fail.

```bash
__determine_domain_name() {
  local domain
  domain="$(hostname -d 2>/dev/null)"
  if [[ -n "$domain" ]]; then
    printf '%s\n' "$domain"
    return 0
  fi
  local fqdn
  fqdn="$(hostname -f 2>/dev/null)"
  if [[ -n "$fqdn" ]] && [[ "$fqdn" == *.* ]]; then
    printf '%s\n' "${fqdn#*.}"
    return 0
  fi
  return 1
}
```

### `__determine_hostname_name`

Returns the runtime FQDN via `hostname -f`. Returns 1 if unavailable.

```bash
__determine_hostname_name() {
  local fqdn
  fqdn="$(hostname -f 2>/dev/null)"
  if [[ -n "$fqdn" ]]; then
    printf '%s\n' "$fqdn"
    return 0
  fi
  return 1
}
```

### `__validate__hosts_fqdn`

Returns 0 if `$1` is a valid FQDN (`domain.tld` or `host.domain.tld`, etc.), 1 otherwise. Enforces: at least two labels, each label 1–63 chars, alphanumeric + interior hyphens only, total length ≤ 253.

```bash
__validate__hosts_fqdn() {
  local fqdn="${1:-}"
  [[ -z "$fqdn" ]] && return 1
  [[ ${#fqdn} -gt 253 ]] && return 1
  [[ "$fqdn" != *.* ]] && return 1
  local label labels
  local IFS='.'
  read -ra labels <<< "$fqdn"
  for label in "${labels[@]}"; do
    [[ -z "$label" ]] && return 1
    [[ ${#label} -gt 63 ]] && return 1
    [[ "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || return 1
  done
  return 0
}
```

### `__download_all_scripts_from_github`

Downloads every file from the `scripts/` directory of a GitHub repo via the API (paginated) and saves them to `$1` with `chmod 755`. Requires `curl` and `jq`.

- `GITHUB_RAW_REPO` — `{userORorg}/{repo}` path; defaults to `{project_org}/{project_name}`
- `$1` — destination directory; typically `/usr/local/bin` (system) or `~/.local/bin` (user)

```bash
__download_all_scripts_from_github() {
  local dest="${1:?Usage: __download_all_scripts_from_github <dest_dir>}"
  local GITHUB_RAW_REPO="${GITHUB_RAW_REPO:-{project_org}/{project_name}}"
  local api_base="https://api.github.com/repos/${GITHUB_RAW_REPO}/contents/scripts"
  local raw_base="https://raw.githubusercontent.com/${GITHUB_RAW_REPO}/main/scripts"
  local page=1
  local files file response

  mkdir -p "$dest" || return 1

  while :; do
    response="$(curl -q -LSs "${api_base}?per_page=100&page=${page}")" || return 1
    mapfile -t files < <(printf '%s' "$response" | jq -r '.[] | select(.type=="file") | .name')
    [[ ${#files[@]} -eq 0 ]] && break
    for file in "${files[@]}"; do
      curl -q -LSs "${raw_base}/${file}" -o "${dest}/${file}" || return 1
      chmod 755 "${dest}/${file}"
    done
    (( ${#files[@]} < 100 )) && break
    (( page++ ))
  done
}
```

### `__does_host_have_valid_ip6`

Returns 0 if the host has at least one global-scope IPv6 address, 1 otherwise.

```bash
__does_host_have_valid_ip6() {
  local addr
  addr="$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2; exit}')"
  [[ -n "$addr" ]] && return 0
  return 1
}
```

### `__get_network_device`

Returns the name of the network device that holds the global default route. Accepted prefixes: `eth*`, `en*`, `wg*`, `br*`, `vmbr*`. Excluded: `incus*`, `docker*`, `lo`, `veth*`, and all other virtual devices. Returns 1 if no suitable device is found.

```bash
__get_network_device() {
  local dev candidate
  # Prefer the device on the default IPv4 route
  candidate="$(ip route show default 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  case "${candidate:-}" in
    eth*|en*|wg*|br*|vmbr*) printf '%s\n' "$candidate"; return 0 ;;
  esac
  # Fallback: first UP device matching allowed prefixes
  while IFS= read -r dev; do
    case "$dev" in
      eth*|en*|wg*|br*|vmbr*) printf '%s\n' "$dev"; return 0 ;;
    esac
  done < <(ip link show up 2>/dev/null | awk -F': ' '/^[0-9]+:/ {print $2}' | cut -d'@' -f1)
  return 1
}
```

### `__is_ip4_public`

Returns 0 if `$1` is a public (globally routable) IPv4 address, 1 if private, reserved, or invalid. Covers RFC1918, loopback, link-local, CGNAT (100.64/10), and multicast/reserved (224+).

```bash
__is_ip4_public() {
  local ip="${1:-}"
  [[ -z "$ip" ]] && return 1
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local a b c d
  IFS='.' read -r a b c d <<< "$ip"
  # 0.0.0.0/8
  (( a == 0 )) && return 1
  # 10.0.0.0/8
  (( a == 10 )) && return 1
  # 127.0.0.0/8 loopback
  (( a == 127 )) && return 1
  # 100.64.0.0/10 CGNAT
  (( a == 100 && b >= 64 && b <= 127 )) && return 1
  # 169.254.0.0/16 link-local
  (( a == 169 && b == 254 )) && return 1
  # 172.16.0.0/12
  (( a == 172 && b >= 16 && b <= 31 )) && return 1
  # 192.0.0.0/24 IETF protocol
  (( a == 192 && b == 0 && c == 0 )) && return 1
  # 192.0.2.0/24 TEST-NET-1
  (( a == 192 && b == 0 && c == 2 )) && return 1
  # 192.168.0.0/16
  (( a == 192 && b == 168 )) && return 1
  # 198.51.100.0/24 TEST-NET-2
  (( a == 198 && b == 51 && c == 100 )) && return 1
  # 203.0.113.0/24 TEST-NET-3
  (( a == 203 && b == 0 && c == 113 )) && return 1
  # 224.0.0.0+ multicast/reserved
  (( a >= 224 )) && return 1
  return 0
}
```

### `__is_ip6_public`

Returns 0 if `$1` is a public (globally routable) IPv6 address, 1 if private, reserved, or invalid. Excludes loopback (`::1`), unspecified (`::`), link-local (`fe80::/10`), unique-local (`fc00::/7`), and IPv4-mapped (`::ffff:`). Accepts only global unicast (`2000::/3`, i.e. addresses starting with `2` or `3`).

```bash
__is_ip6_public() {
  local ip="${1:-}"
  [[ -z "$ip" ]] && return 1
  # strip zone ID (e.g. fe80::1%eth0)
  ip="${ip%%\%*}"
  # lowercase for pattern matching
  local low="${ip,,}"
  [[ "$low" == "::" || "$low" == "::1" ]] && return 1
  # fe80::/10 link-local
  [[ "$low" =~ ^fe[89ab][0-9a-f]?:  ]] && return 1
  # fc00::/7  unique-local
  [[ "$low" =~ ^f[cd]               ]] && return 1
  # IPv4-mapped
  [[ "$low" =~ ^::ffff:             ]] && return 1
  # must be global unicast
  [[ "$low" =~ ^[23]                ]] || return 1
  return 0
}
```

### `__get_hosts_ip4_address`

Returns the host's public IPv4 address. If `IP4_ADDRESS` is already set in the environment, returns it immediately (no curl). Otherwise tries `ifcfg.us` → `ifconfig.co` → `checkip.amazonaws.com` in order, forcing IPv4 with `curl -4`. Returns 1 if all sources fail.

```bash
__get_hosts_ip4_address() {
  if [[ -n "${IP4_ADDRESS:-}" ]]; then
    printf '%s\n' "$IP4_ADDRESS"
    return 0
  fi
  local ip url
  for url in "https://ifcfg.us/ip" "https://ifconfig.co/ip" "https://checkip.amazonaws.com"; do
    ip="$(curl -4 -q -LSs --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$ip" ]] && __is_ip4_public "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  return 1
}
```

### `__get_hosts_ip6_address`

Returns the host's public IPv6 address. Skips entirely (returns 1) if `__does_host_have_valid_ip6` fails. If `IP6_ADDRESS` is already set in the environment, returns it immediately. Otherwise tries `ifcfg.us` → `ifconfig.co` → `api6.ipify.org` in order, forcing IPv6 with `curl -6`. Returns 1 if all sources fail.

```bash
__get_hosts_ip6_address() {
  __does_host_have_valid_ip6 || return 1
  if [[ -n "${IP6_ADDRESS:-}" ]]; then
    printf '%s\n' "$IP6_ADDRESS"
    return 0
  fi
  local ip url
  for url in "https://ifcfg.us/ip" "https://ifconfig.co/ip" "https://api6.ipify.org"; do
    ip="$(curl -6 -q -LSs --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$ip" ]] && __is_ip6_public "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  return 1
}
```

### `__random_password`

Generates a cryptographically random password from `/dev/urandom`. Accepts an optional length argument (default 32). Uses alphanumeric + common special characters safe for most password fields. Prints the password without a trailing newline so it can be captured cleanly with `$()`.

```bash
__random_password() {
  local length="${1:-32}"
  tr -dc 'A-Za-z0-9!@#$%^&*_+-' </dev/urandom | head -c "${length}"
}
```

### `__random_port`

Returns a random unused port in the `62000`–`64999` range. This range avoids all commonly used service ports (8080, 3000, 5432, etc.) and is not assigned to any well-known services. Checks availability with `ss -tlnp` before returning. Loops until a free port is found. Port is detected at runtime on every call.

When the port must survive between runs (idempotent script, docker-compose with a reverse proxy in front, any service where the port must stay stable), save it to the project's config file on first generation and reload it on subsequent runs. The project decides the file — `.env`, `settings.conf`, `docker-compose.yml`, etc. Use `__save_credential` / `__load_credential` when the file is a `KEY=VALUE` store:

```bash
CRED_FILE="${MYSCRIPT_CONFIG_DIR:-/etc/myscript}/settings.conf"
MYSCRIPT_PORT="$(__load_credential "$CRED_FILE" MYSCRIPT_PORT)" || {
  MYSCRIPT_PORT="$(__random_port)"
  __save_credential "$CRED_FILE" MYSCRIPT_PORT "$MYSCRIPT_PORT"
}
```

If the project writes a structured file (docker-compose.yml, nginx.conf, etc.), generate it once with the chosen port and do not regenerate unless explicitly requested.

```bash
__random_port() {
  local port
  while :; do
    port=$(( 62000 + RANDOM % 3000 ))
    if ! \ss -tlnp 2>/dev/null | \grep -q ":${port} "; then
      printf '%s\n' "$port"
      return 0
    fi
  done
}
```

Port binding convention — always `172.17.0.1:{port}:{internal_port}`:
- Never `0.0.0.0` — exposes the port on all interfaces including public ones
- Never `localhost` or `127.0.0.x` — host-only, excludes container-to-host reach
- `172.17.0.1` is the Docker bridge gateway: reachable from the host and other containers on the default bridge, not exposed externally

### `__save_credential`

Saves a key=value pair to a credentials file. Creates the file and parent directory if needed. Sets permissions to `600` and ownership to `root:root` when running as root, or `$RUN_USER:$RUN_USER` otherwise. If the key already exists in the file it is replaced in-place; it is appended if not. Shows the value to the user once on first save (stdout) with a note of the file path.

```bash
__save_credential() {
  local file="${1:?Usage: __save_credential <file> <key> <value>}"
  local key="${2:?}"
  local value="${3:?}"
  mkdir -p "$(dirname -- "$file")"
  if [[ -f "$file" ]] && grep -q "^${key}=" "$file"; then
    local tmp
    tmp="$(mktemp)"
    grep -v "^${key}=" "$file" > "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
    printf 'Generated %s: %s\n' "$key" "$value"
    printf 'Saved to: %s\n' "$file"
  fi
  chmod 600 "$file"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    chown root:root "$file"
  else
    chown "${RUN_USER}:${RUN_USER}" "$file"
  fi
}
```

### `__load_credential`

Loads a key's value from a credentials file. Prints the value and returns 0 if found; returns 1 if the file does not exist or the key is absent.

```bash
__load_credential() {
  local file="${1:?Usage: __load_credential <file> <key>}"
  local key="${2:?}"
  [[ -f "$file" ]] || return 1
  local val
  val="$(grep "^${key}=" "$file" | tail -n1 | cut -d= -f2-)"
  [[ -n "$val" ]] || return 1
  printf '%s\n' "$val"
}
```

**Secret var pattern** — for any credential var, load from the credentials file first; generate, save, and show once if absent:

```bash
CRED_FILE="${MYSCRIPT_CONFIG_DIR:-/etc/myscript}/.credentials"
MYSCRIPT_DB_PASSWORD="$(__load_credential "$CRED_FILE" MYSCRIPT_DB_PASSWORD)" || {
  MYSCRIPT_DB_PASSWORD="$(__random_password)"
  __save_credential "$CRED_FILE" MYSCRIPT_DB_PASSWORD "$MYSCRIPT_DB_PASSWORD"
}
```

## Testing

Syntax checking is interpreter-aware — use the right tool per shebang:

| Shebang | Syntax check | Linter |
|---------|-------------|--------|
| `#!/usr/bin/env bash` / `#!/bin/bash` | `bash -n scriptname` | `shellcheck -s bash scriptname` |
| `#!/usr/bin/env sh` / `#!/bin/sh` | `sh -n scriptname` | `shellcheck -s sh scriptname` |
| `#!/usr/bin/env zsh` | `zsh -n scriptname` | no shellcheck (unsupported) |
| `#!/usr/bin/env fish` | `fish -n scriptname` | no shellcheck (unsupported) |
| `#!/usr/bin/env python3` etc. | language-specific (`python3 -m py_compile`) | language-specific linter |
| `.ps1` | `pwsh -NonInteractive -File scriptname` | PSScriptAnalyzer |
| `.cmd` / `.bat` | no standard checker | no standard linter |

- Syntax checks (`bash -n`, `sh -n`, `zsh -n`, `fish -n`) and `--help`/`--version` invocations are safe to run directly on the host — they only print and exit 0, with no side effects
- Functional testing (anything that mutates state, installs, calls external services, or runs as root) must run inside Incus (preferred) or Docker — never directly on host

## Security

- No `curl -q -LSsf {url} | sh` inside scripts — never pipe a fetched URL into a shell from within a script where the user can't inspect what's being executed
- `curl -q -LSsf {url} | sh` **is acceptable in documentation** (README, install docs) — it is better UX than `curl -o && chmod +x && ./script`. When used in docs, always place immediately above the code block:
  1. A plain-language note explaining what the script does
  2. A direct link to the raw script URL so users can inspect it before running
- **The shell in the pipe must match the script's interpreter** — check the shebang and use the correct shell. `curl -q -LSsf {url} | bash` for bash scripts, `curl -q -LSsf {url} | zsh` for zsh scripts, etc. Never pipe a script into a mismatched shell (e.g. piping a fish script into `bash` will break or silently misbehave)
- Use `sudo tee` instead of redirect for privileged writes

## Pipe Safety

Scripts **should** be pipe-safe — safe to run via `curl … | sh` or any pipeline without hanging or misbehaving.

**Rules:**
- Never read from stdin unconditionally — always check first
- Never prompt interactively (e.g. `read -p`) without confirming stdin is a terminal
- Side-effect-free by default: no writes, no installs, no destructive ops before the user has had a chance to inspect (satisfied by the doc-link requirement in Security above)

**Stdin detection — use `[ -t 0 ]` (POSIX, works on Linux/macOS/BSD):**

```sh
if [ -t 0 ]; then
  # stdin is a terminal — interactive input is safe
else
  # stdin is a pipe or redirect — skip prompts, use defaults
fi
```

**Cross-platform notes:**

| Platform | Detection | Notes |
|----------|-----------|-------|
| Linux / macOS / BSD | `[ -t 0 ]` | POSIX; works in sh, bash, zsh, dash |
| Windows (pwsh) | `[Console]::IsInputRedirected` | PowerShell only |
| Windows (cmd) | Not reliably detectable | Avoid interactive reads in `.cmd` scripts entirely |

**Scripts that accept piped input** (e.g. `cat file | script`) should auto-detect and switch modes — interactive prompts become no-ops or use flag-supplied defaults; output stays machine-readable (no color, no spinners) when stdout is not a terminal (`[ -t 1 ]`).
