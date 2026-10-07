# AUDIT.AI.md

Findings from the `audit` agent pass comparing all 27 `home/hooks/*.sh` against
`home/CLAUDE.md`, `AI.md`, and `home/memory/*.md`. Logged per the "No issue
left only in conversation" rule (>5 issues → this file, not TODO.AI.md).
Status: OPEN. Items marked `[x]` are fixed and verified; `[ ]` items are still
outstanding. The hook-scope items (Priority 0–3) are largely closed; the bulk of
what remains is in `home/agents/`, `home/skills/`, and `README.md`, which were
outside the hook-focused passes and have not been worked.

Reliability pass, 2026-09-02 (scope: `home/hooks/*.sh` + `home/settings.json`),
driven by the user report of frequent hook errors and false blocks. Everything
below is fixed and verified unless noted:

- Latency: `no-ai-attribution.sh` spawned a `sed` + `grep` per line, so an 8KB
  file took ~24s against its 10s timeout and failed as a hook error. Now one
  streamed pass — 60KB in ~0.7s, flat. (`block-host-toolchain.sh` had the same
  class of bug, fixed in the prior pass.)
- Fail-open: three distinct `TypeError` classes (non-string `file_path`,
  `command`, `content`/`new_string`, `cwd`) made 15 hooks exit 1 — reported to
  the user as a hook error on an ordinary tool call. A uniform string-field
  normalization now runs in 17 hooks; verified against 25 hostile payloads
  across all 27 hooks, zero non-zero exits.
- False positives: `no-todo-comments.sh` accepted every comment leader for every
  file type and matched bare English keywords, so ordinary prose comments and
  shell `--flag=value` lines blocked. Leaders are now chosen by extension and
  every commented-out-code shape requires code punctuation.
- False positives: `comment-placement-guard.sh` applied the 180-char prose limit
  to `##@Version` / `# @@Field :` header lines, which are a one-line-per-field
  template that cannot wrap — blocked editing any script with a detailed
  changelog. Header field lines are now exempt from the length check only.
- False positives: `bash-content-scan.sh` ran the AI-attribution pattern as an
  unanchored whole-content search despite its header claiming it mirrors
  `no-ai-attribution.sh`, which anchors per line after stripping comment
  leaders. Any heredoc mentioning the phrase mid-sentence was blocked while the
  same text through Write/Edit passed. Now anchored the same way.
- Output protocol: `protect-host.sh` and `no-ai-attribution.sh` wrote the
  BLOCKED reason to stderr only; Part 6's blocking-output format requires both
  streams. Both now write to both.
- Detection gap: `no-read-gitcommit.sh` missed `cat $(command -v gitcommit)` —
  the args tokenize as `$(command`, `-v`, `gitcommit)`, so no literal path was
  ever compared. Resolver substitutions are now matched directly.
- Verified, no change needed: `home/settings.json` wiring (all 27 hooks wired
  under the right event and matcher, no orphans, no missing scripts); both
  marker systems (`spec-guard`, `test-lint-guard`) round-trip correctly between
  writer and reader, including post-compact re-arming; `protect-host.sh` latency
  is flat at ~0.8s (an earlier 5.1s reading was measurement contention, not a
  real cost); every hook's payload field names match the real Claude Code shape.

The following previously-logged items are now STALE and need no work — the code
or the spec changed under them:

- [x] `home/settings.json` uses `$HOME/.claude/hooks/` vs AI.md mandating `~/` —
      AI.md Part 7 now mandates `$HOME` and explicitly forbids a literal `~`.
      settings.json was already correct.
- [x] AI.md `drift-guard-read.sh` row "says it checks for a corresponding
      `home/` source; it doesn't" — the code does check
      (`os.path.exists(source)`), and the row already documents the fail-open.

## Priority 0 — live security bypasses (fix first, no judgment call needed)

- [x] D1 (FIXED): `no-destructive-bypass.sh` now masks quoted strings
      (same technique as `bound-shell-lifetime.sh`'s `mask_quotes`) before
      splitting on separators, then slices the original text by the masked
      match positions — a `|` inside a quoted string (e.g. a `grep`
      pattern) no longer causes a false-positive split/block.
- [x] D2 (FIXED): `no-destructive-bypass.sh` now peels a wrapping
      subshell/command-substitution `(dd …)`/`$(dd …)`/`` `dd …` ``
      before tokenizing, recurses into `xargs`'s trailing command (after
      skipping xargs's own flags), recurses into `bash -c '…'`/`sh -c
      "…"` payloads (re-splitting and re-scanning them), and normalizes
      the command basename (`/bin/dd` → `dd`, `/usr/bin/git` → `git`)
      before comparison — closing all four bypasses.
- [x] D3 (FIXED): `protect-host.sh` removed `chroot`/`nsenter`/`virsh`
      from the container-prefix exemption list — these are
      host-namespace-entering or host-side tools, not guest isolation,
      so `chroot /mnt rm -rf /etc` and `nsenter -t 1 -m rm -rf /etc` are
      now blocked like any other destructive host command.
- [x] D4 (FIXED): `protect-host.sh`'s sweep escape valve now extracts
      just the `ps`/`ls`/`list` segment of the command (up to the next
      `;`/`&`/`|`) and checks `--filter`/`name=`/`label=` only within
      that segment, instead of against the whole raw command string — an
      unrelated `name=` substring elsewhere in the pipeline (e.g. inside
      the kill/stop/rm target list) no longer satisfies the check.

## Priority 1 — needs a decision (delete the rule vs. add the missing spec line)

`protect-host.sh` enforces five entire rule families with no spec backing
anywhere in `home/CLAUDE.md` or `home/memory/*.md`:
- [x] Auth-critical file protection (`/etc/passwd`, `/etc/shadow`,
      `/etc/sudoers`, …) — formalized into `security_conventions.md`'s
      new "Protected Host Paths" section
- [x] 15-entry top-level system-dir list vs. spec's 6-entry floor
      (`/`,`/boot`,`/sys`,`/proc`,`/dev`,partition/bootloader) —
      formalized into the same new section
- [x] Delete-on `/bin`,`/usr/bin`,`/sbin`,`/usr/sbin` (write-half is
      sourced at `project_files.md:86`, delete-half is not) —
      formalized into the same new section
- [x] Shell-redirect rule + pseudo-device allowlist — formalized into
      the same new section
- [x] `find -delete` / `find -exec rm` rule — formalized into the same
      new section
- [x] `systemctl isolate`/`kill` in the confirm-gate (spec lists
      `restart|stop|start|reload|disable|enable|mask|unmask|edit|
      set-property` only) — formalized: added `isolate`/`kill` to
      `home/CLAUDE.md`'s systemctl gate rule and "Still hard" zone list
      (same blast-radius risk class as `mask`/`unmask`/`edit`/
      `set-property`)
- [x] `pkill`/`killall`/`pgrep` blocking — already sourced: matches
      `home/CLAUDE.md`'s "kill scoping" rule ("`kill $PID` only when
      `$PID` was captured at launch") verbatim; no change needed, this
      was a missing-citation false positive, not an actual gap

`no-forbidden-files.sh` — entire forbidden-name set has no source in
`project_files.md`, AND allowlists what the spec actually forbids:
- [x] Unsourced: `FORBIDDEN_BASENAMES` (`.netrc`, `credentials.json`,
      `id_rsa`, `.ds_store`, `thumbs.db`, …) — formalized into
      `project_files.md`'s new "Forbidden Basenames & Extensions" section
- [x] Unsourced: `.p12`/`.pfx`/`.jks`/`.p8`/`.ppk` — formalized in the
      same new `project_files.md` section
- [x] Wrong direction: blocks `id_rsa.pub`/`id_ed25519.pub` (public keys;
      spec names private keys only) — removed from
      `FORBIDDEN_BASENAMES`, `.ssh/id_` path pattern now excludes `*.pub`
- [x] Unsourced: blocks `.aws/config` (holds no credentials) — removed
      from `FORBIDDEN_PATH_PATTERNS`
- [x] Unsourced: `docs/` MkDocs carve-out (zero `mkdocs` hits in spec) —
      formalized into `project_files.md`
- [x] Contradiction: allows `Dockerfile`/`docker-compose.yml` at repo
      root; spec requires `docker/` — removed from always-allow,
      `LOCATION_RESTRICTED_DOCKER_BASENAMES` now requires a `docker/`
      path
- [x] Contradiction: allowlists `/vendor/`, `/node_modules/`; spec
      forbids both dirs — removed from always-allow, added to
      `FORBIDDEN_PATH_PATTERNS`
- [x] Contradiction: allows `.env.template`, not in spec's exception set
      — removed; `app.env.*`/`default.env.*` variants the spec does name
      were added
- [x] Missing: hook enforces none of spec's actual forbidden entries
      (`SUMMARY.md`, `COMPLIANCE.md`, `NOTES.md`, `AUDIT.md`, `REPORT.md`,
      `ANALYSIS.md`, all 11 forbidden directories) — added
      `FORBIDDEN_REPORT_BASENAMES` (exact-match, `AUDIT.AI.md` stays
      exempt) and cwd-scoped `FORBIDDEN_ROOT_DIRNAMES` via the hook
      payload's `cwd` field

- [x] `no-destructive-bypass.sh:140-154` blocks `dd`/`shred`/`mkfs*`/`wipefs`
      unconditionally with no confirm path; `home/CLAUDE.md:88,97` frames
      these as "confirm first", not deny — NOT a hook bug: `settings.json`'s
      `permissions.deny` already hard-denies `git reset`/`dd`/`shred`/
      `mkfs*`/`wipefs` with no confirm path at the permission layer, and the
      hook correctly re-enforces that stricter deny (against wrapper
      bypasses `permissions.deny`'s raw glob match can't catch). Formalized
      by adding a clarifying line to `home/CLAUDE.md`'s Verification &
      Safety section: these five are hard-denied, not confirm-gated,
      overriding the general "confirm before irreversible" default.
- [x] `no-secrets.sh:59-68` and `bash-content-scan.sh:166-171` exempt
      `.env.example`/zone paths without checking repo-visibility-confirmed-
      private, which `sensitive_data.md:35` and `home/CLAUDE.md:89-94`
      require as a precondition — NOT fixable as a live hook check: AI.md
      Part 6's hook rules forbid network I/O (`gh repo view` would be
      network I/O), so a hook can never verify visibility itself.
      Formalized in `sensitive_data.md`: the precondition is enforced
      procedurally by the Repo privacy gate (steps 1-5), not technically by
      these hooks — cwd scoping is necessary but not sufficient; the
      privacy-gate workflow is what makes the exemption actually safe.

## Priority 2 — invented enforcement, narrower scope (no judgment call, just fix)

- [x] `enforce-test-lint-gate.sh:126,129-131` — 4-level depth limit on the
      script scan; spec says "anywhere in its tree", unqualified. Fixed:
      depth limit removed.
- [x] `enforce-test-lint-gate.sh:160-165` — a manifest-only project
      (e.g. only `package.json`) can never satisfy the lint gate, since a
      lint marker only comes from script-lint/go-lint/rust-lint. Verified:
      unsatisfiable deadlock for Node/Python-only projects. Fixed: lint
      gate skipped for projects with no defined lint agent.
- [x] `enforce-test-lint-gate.sh:137-141` / AI.md:226 — no carve-out for
      `install.sh`-only spec-collection repos; `project_type_conventions.md
      :182` says an `install.sh` alone does not disqualify spec-collection.
      Fixed: install.sh-only carve-out added.
- [x] `enforce-test-lint-gate.sh:150-157` — spec-collection substitute
      checks "AI.md/SPEC.md was read", spec requires re-reading the
      edited/changed file(s) instead. Fixed.
- [x] `enforce-test-lint-gate.sh:138` / `test-lint-mark.sh:100` — adds
      `Makefile`/`setup.py` to the manifest list beyond spec's
      go.mod/Cargo.toml/package.json/pyproject.toml. Fixed: manifest list
      narrowed to spec's four.
- [x] `bound-shell-lifetime.sh:209` — sentinel tokens `.output`/`/tasks/`
      unsourced; spec only names `*.done`. Fixed: narrowed to `*.done`.
- [x] `bound-shell-lifetime.sh:206-213` — blocks sentinel polls even when
      wrapped in `timeout {n}`; spec exempts anything under `timeout {n}`
      with no carve-out. Verified live. Fixed: the blanket bounded-check
      now runs before the sentinel-specific check.
- [x] `enforce-docker-rm.sh:107,156,162` — enforces `lxc launch|init`;
      spec (`execution_hierarchy.md:29-37,96`) says Incus only. Fixed:
      lxc dropped from the launch/init naming enforcement.
- [x] `no-history-rewrite.sh:132-133,173-176` — undocumented `git clean
      -fn` dry-run carve-out (behaviorally fine, not written anywhere).
      Fixed: documented, and is_dry_run() now also matches combined
      short flags (-fn/-nf), which the original carve-out missed.
- [x] `no-history-rewrite.sh:123-129,189-192` — tag-delete matching
      extended to `-D`/combined flags; spec names `-d` only. Inconsistent
      with same file's branch-delete matcher (correctly `-D` only). Fixed:
      narrowed to -d/--delete (and combined flags carrying lowercase d).
- [x] `no-ai-attribution.sh:52` — bare regex match on the phrase itself
      with no scope check; spec scopes the rule to trailers/footers, this
      blocks any file merely discussing that phrase as a topic (this file
      had to be reworded once already while being written, to avoid the
      hook self-triggering on a description of its own bug). Fixed:
      matching anchored to line-start after stripping comment/quote
      leaders.
- [x] `no-read-gitcommit.sh:91-93` — `cp`/`diff` added to READ_VERBS
      beyond spec's `cat/less/head/etc`. Fixed: cp/diff dropped.
- [x] `no-read-gitcommit.sh:57-60` — hardcodes `/usr/local/bin/gitcommit`;
      spec (`gitcommit_conventions.md:7`) forbids this exact pattern
      verbatim, using that path as its own counter-example. Fixed:
      resolved dynamically via shutil.which("gitcommit").
- [x] Marker temp paths (`test-lint-mark.sh:109`, `lint-agent-mark.sh:63`,
      `enforce-test-lint-gate.sh:112-113`) use
      `${TMPDIR}/claude-test-lint-guard/…`, not the mandated
      `${TMPDIR}/{project_org}/{internal_name}-XXXXXX/` shape
      (`tempdir_conventions.md:16,30,32` names this exact shape FORBIDDEN).
      Fixed: moved to `${TMPDIR}/climgr/claude/test-lint-guard/${session_id}`
      — session_id takes the -XXXXXX uniqueness role since the marker must
      stay reconstructable by session_id alone; org/internal_name namespacing
      now matches the mandated shape.
- [x] `trailing-newline-guard.sh:70` — exempts `.pem`/`.key`/`.crt`/`.der`;
      spec requires trailing newline on PEM keys specifically.
      Fixed: dropped `.pem`/`.key`/`.crt` from `EXEMPT_EXT` — they're text
      (base64/PEM-armored), not binary; `.der`/`.p12`/`.pfx` stay exempt as
      genuinely binary encodings, per `file_ending_conventions.md:12`.
- [x] `no-todo-comments.sh:76-92` — runs on every file type, not just
      code; a Markdown `# TODO` heading or `* key = value` bullet false-
      positives as commented-out code.
      Fixed: for `.md` files, comment-prefix matching now scoped to `<!--`
      only, and the commented-out-code heuristic is skipped entirely —
      Markdown headings/bullets aren't comment syntax.
- [x] `comment-placement-guard.sh:137` — SHA-pin exemption limited to
      `.github/workflows/`; spec also covers `.gitea/workflows/` and
      `.forgejo/workflows/`.
      Fixed: `IS_WORKFLOW` now checks all three workflow directories.
- [ ] `lint-agent-mark.sh:50-72` — marks lint gate satisfied on subagent
      completion with no pass/fail signal; spec requires "never commit
      with violations". Also derives project from hook's own cwd, not the
      directory the lint agent actually inspected.
- [ ] `block-host-toolchain.sh` — hardcoded tier-3 images at every
      `__block` call, ignoring spec's project-declared-image-first order;
      no `--memory`/`--cpus` in any suggestion; several suggestions use
      debian/ubuntu images against spec's alpine-only rule (justified only
      by lack of official Alpine image — undocumented exception); exempts
      `python`/`python3` and has no branch for `ruff`/`mypy` at all,
      against `python_conventions.md:93`; Rust suggestion omits
      `-e RUSTC_WRAPPER=sccache`; Node/Python suggestions omit cache
      mounts spec requires.
- [x] `protect-host.sh` — wrote the BLOCKED message to stderr only; Part 6's
      blocking-output format mandates both streams.
      Fixed: `__block()` now writes the reason to stdout and stderr.
      Same fix applied to `no-ai-attribution.sh`, which had the identical bug.
- [ ] `protect-host.sh` / `no-destructive-bypass.sh` — both parse with
      python3, not `jq` as AI.md:198 specifies.
- [ ] `test-lint-mark.sh:110-114` / `lint-agent-mark.sh:64-68` — hooks
      delete files (`find … -exec rm -rf`); AI.md:203 says hooks may only
      append to logs. Scoped to own namespace so not unsafe, but still a
      Part 6 documentation violation.

## Priority 3 — AI.md Part 6 table corrections (doc-only, no logic change)

- [x] AI.md (`protect-host.sh`) row severely under-described actual behavior.
      Fixed: the row now lists auth-critical files, core binary dirs, root/home
      wipes, block-device writes, pkill/killall, unscoped container sweeps and
      prune, redirects and find-delete, plus the container/VM exemption and the
      deliberate non-exemption of chroot/nsenter/virsh.
- [x] AI.md (`drift-guard-read.sh`) — claim was itself wrong; the code does
      check `os.path.exists(source)` and the row documents the fail-open. STALE.
- [x] AI.md (`bound-shell-lifetime.sh`) — omitted rule E and sentinel polling.
      Fixed: the row now enumerates all five rules A-E and states that sentinel
      polling is blocked unconditionally, even when the loop is bounded.
- [x] AI.md (`no-force-push.sh`) row incomplete re: `--force-with-lease`.
      Fixed: the row now lists `--force`/`--force=...`/`--force-with-lease*`/
      `-f`/`+refspec`.
- [x] AI.md — container-mediated heredoc exemption was documented only for
      `bash-content-scan.sh`.
      Fixed: both the `no-force-push.sh` and `no-history-rewrite.sh` rows now
      state that they share the same exemption.
- [ ] AI.md:226 — repeats the incorrect spec-collection test description
      (see Priority 2 `enforce-test-lint-gate.sh:150-157` item).
- [ ] AI.md:216 (`block-host-toolchain.sh`) — doesn't mention suggestions
      are fixed tier-3 images rather than the project's declared one.
- [ ] `no-destructive-bypass.sh:23-26` header claims container-mediated
      invocations are denied unconditionally; code never looks past the
      head token, so `docker run … alpine dd if=…` is actually allowed.
- [ ] `spec-guard.sh:18` header's exempt-file list omits the seven files
      actually exempted at `:46-47`.
- [x] `home/settings.json` `$HOME` vs `~` — AI.md Part 7 now mandates `$HOME`
      and forbids a literal `~`; settings.json was already correct. STALE.
- [ ] `home/memory/file_ending_conventions.md` has no YAML frontmatter,
      violating AI.md:80-90 / the pre-commit validation step at AI.md:288.
- [ ] Spec self-contradiction: `project_type_conventions.md:23` lists
      `climgr/claude` as a spec-collection example; `:178` says it is
      not one. Hooks correctly follow `:178` — the `:23` line needs fixing.

## Priority 4 — documented gaps, no hook coverage (informational, no fix required unless requested)

`execution_hierarchy.md` (`--memory`/`--cpus`, `--network host`, `-it`,
`{project_name}-XXXX` naming, `docker compose up -d`) unchecked by
`enforce-docker-rm.sh`; `comment_conventions.md` (`.env`, CSV/TSV, CSS
`//`) unchecked; `sensitive_data.md` (passwords, internal hostnames/IPs,
DB connection strings) has no `no-secrets.sh` pattern; per-call `timeout`
requirement (`shell_lifetime_conventions.md:11-12`) never inspected.

---

Deployment note: all fixes must be `cp`'d from `home/hooks/*.sh` to
`~/.claude/hooks/*.sh` after editing — the deployed copy is what the
harness actually executes; the source-only edit has zero live effect
until deployed (this was the actual cause of the "still blocked" report
resolved earlier this session).

---

# Agents & Skills content audit

Read-only pass over all 32 `home/agents/*.md` and all 10
`home/skills/*/SKILL.md`. Content correctness only — deployment sync was
verified separately and is not in scope here. Nothing below is fixed yet.

Grounding: AI.md Part 5 governs only packaging shape (frontmatter fields,
filename/`name:` match, the "Current agents" table) — findings A0/A1. The
substance of what each agent instructs is judged against the global rules
at `/root/.claude/CLAUDE.md` and `/root/.claude/memory/*.md`. `diff -q`
and `diff -rq` confirm `home/CLAUDE.md` and every file in `home/memory/`
are byte-identical to their deployed global counterparts, so every
convention citation below (`script_conventions.md`, `go_conventions.md`,
`rust_conventions.md`, `security_conventions.md`, `tempdir_conventions.md`,
`cicd_conventions.md`, `rpm_conventions.md`, `model_routing.md`,
`gitignore_conventions.md`, `makefile_conventions.md`, `project_files.md`)
is simultaneously a citation of the live global rule.

Global sweeps that came back clean: no agent or skill instructs
`git commit`/`git push` outside the `gitcommit` path; no `egrep`/`fgrep`/
`rgrep` outside script-lint's own detection table; no `nohup`/`setsid`/
`disown`; every file in `home/agents/` and `home/skills/` ends with a
single trailing newline; every cross-referenced agent name resolves to a
real file; only one host-toolchain violation exists (A5, rust-auth-builder
`cargo build`/`cargo test`).

## A0 — spec coverage gaps in AI.md itself

- [ ] AI.md:149-174 "Current agents" table lists 24 agents; `home/agents/`
      holds 32. Missing rows: `billing-builder`, `designer`,
      `go-auth-builder`, `go-server-to-api`, `notifications-builder`,
      `rpm-builder`, `rust-auth-builder`, `support-builder`. Fix: add the
      eight rows with their actual `model:` values.
- [ ] AI.md has no Part covering `home/skills/` and no mention of the word
      "skill" anywhere, yet `install.sh` deploys `home/skills/` to
      `~/.claude/skills/`. Fix: add a Part specifying SKILL.md frontmatter
      and the delegating-wrapper pattern.
- [ ] AI.md Part 1 repo-layout tree omits `home/skills/` and
      `home/TEMPLATES/`. Fix: add both.
- [ ] AI.md:135 frontmatter template allows only `haiku|sonnet|opus`;
      `home/memory/model_routing.md` defines a fourth tier, `fable`, for
      visual/design work. `fable` appears in zero agent files. Fix: add
      `fable` to the allowed values in Part 5.
- [ ] AI.md:155 describes `cicd-maintenance` as "Dependabot PR review";
      the agent's own description says Renovate. Fix: correct AI.md to
      Renovate.

## A1 — frontmatter defects

- [ ] `home/agents/designer.md` has no `model:` field at all. It is the
      one purely visual agent and `model_routing.md` routes visual/design
      work to Fable. Fix: `model: fable`.
- [ ] `home/agents/designer.md:3` description ends with a stray
      `(Tools: All tools)` artifact — the only agent file containing that
      string. Fix: delete it.

Verified clean: all 32 `name:` fields match their filenames; all `model:`
values match the AI.md table wherever a row exists; every
`~/.claude/memory/*.md` and `~/.claude/TEMPLATES/*.md` reference in
`home/agents/` and `home/skills/` resolves to a real file; no AI
attribution anywhere; all 10 skill `name:` fields match their directory
names and all 9 delegating wrappers name agents that exist.

## A2 — lint agents contradict their own convention files

- [ ] `home/agents/rust-lint.md:51-53,120-121` has the OS/arch naming rule
      exactly inverted vs `home/memory/rust_conventions.md:172-174`. The
      agent flags `darwin`/`amd64`/`arm64` and demands
      `macos`/`x86_64`/`aarch64`; the convention mandates the opposite.
      Fix: invert the agent's rule to match rust_conventions.md.
- [ ] `home/agents/rust-lint.md:31` says "All four fields are required"
      above a five-row table. Fix: five.
- [ ] `home/agents/rust-lint.md:16` uses `$(PROJECTNAME)`; Rust convention
      is `$(PROJECT_NAME)`. Fix: rename.
- [ ] `home/agents/rust-lint.md:46` Cargo.lock rule misfires on library
      crates (`rust_conventions.md:218`). Fix: scope to binary crates.
- [ ] `home/agents/rust-lint.md` never checks MSRV `rust-version`
      (`rust_conventions.md:209,217`). Fix: add the check.
- [ ] `home/agents/go-lint.md:23,25,26` VERSION fallback is `echo "0.1.0"`;
      `home/memory/go_conventions.md:35` is `echo "devel"`. Fix: `devel`.
- [ ] `home/agents/go-lint.md:83` requires `-trimpath` in LDFLAGS;
      `go_conventions.md:38-45` LDFLAGS is `-s -w` plus `-X` only.
      Fix: drop the `-trimpath` LDFLAGS assertion.
- [ ] `home/agents/go-lint.md:90` required-targets list omits `help`,
      mandatory per `makefile_conventions.md:13,46`. Fix: add `help`.
- [ ] `home/agents/go-lint.md:97` rule names the Makefile var `COMMIT_ID`
      but the output example tells the user to "rename to `CommitID`".
      Fix: make both `COMMIT_ID`.
- [ ] `home/agents/script-lint.md:98` flags `$((...))` as a bashism for
      POSIX sh. It is POSIX. Fix: remove from the bashism list.
- [ ] `home/agents/script-lint.md:113,115` says bash uses external GNU
      `getopt`; `script_conventions.md:695-706,736` mandates the `getopts`
      builtin with the `-:` trick. Fix: match the convention.
- [ ] `home/agents/script-lint.md:127` exit-code range `0-2, 64-78,
      128-143` is narrower than `script_conventions.md:467` (`0-78` or
      `128-143`). Fix: widen.
- [ ] `home/agents/script-lint.md:174` unconditionally exempts everything
      under `scripts/` from triple sync; the convention exempts only hook
      scripts, sourced libraries, and non-interactive scripts. Fix: scope
      the exemption to those three.
- [ ] `home/agents/script-lint.md:184` output example prints
      `header @@Version`; the correct stamp is `##@Version`. Fix: correct
      the example.

## A3 — agent-vs-agent and agent-vs-CLAUDE.md contradictions

- [ ] `home/agents/doc-sync.md:288-294` says never create `man/` or
      `completions/` and only sync if they already exist. That contradicts
      `script_conventions.md:954-961` (all three updated in the same
      commit) and `home/agents/audit.md` Pass 4, which requires
      `man/{scriptname}.1` to exist. Fix: create the dirs when the script
      is interactive.
- [ ] `home/agents/audit.md:216` forbids plural source dirs
      (`handlers/`, `models/`). `home/CLAUDE.md` requires singular only
      for Go and plural for every other language. Fix: make the rule
      language-specific.
- [ ] `home/agents/audit.md:219` "No `.env` files anywhere in repo" vs
      `project_files.md:41` (never *committed*) and CLAUDE.md's
      pre-approved `.env` write paths. Fix: change to "never committed".
- [ ] `home/agents/audit.md:27` says read AI.md in Pre-Flight; `:206` says
      "never attempt a single full-file Read". Fix: make Pre-Flight the
      PART-sliced read.
- [ ] `home/agents/audit.md:383` requires deleting an AUDIT.AI.md entry
      only after it is "fully resolved and committed", but CLAUDE.md says
      agents never commit. Unsatisfiable. Fix: drop "and committed".
- [ ] `home/agents/general.md` hand-off list omits `designer`, which
      `home/CLAUDE.md` mandates for non-trivial UI work (also omits
      bootstrap/implement/audit/doc-sync/lint/builders/cicd-maintenance/
      spec-migrator/dockersrc-bootstrap/rpm-builder). Fix: add at minimum
      `designer`.
- [ ] `home/agents/bootstrap.md:151,214` requires running the Docker build
      and fixing failures; `home/agents/implement.md:22,44,77` forbids
      every spawned helper from running any build/test/lint — and
      implement delegates scaffolding to bootstrap. Fix: reconcile.
- [ ] `home/agents/bootstrap.md:172` and `implement.md:66` route auth
      PARTs only to `go-auth-builder`; `rust-auth-builder` exists and is
      never named. Fix: route by stack.
- [ ] TODO.AI.md item format diverges: `bootstrap.md:176-177` uses
      `## [ ] {title}` / `Read: AI.md PART 14`; `go-server-to-api.md:112`
      uses `## TODO: {title}`. Fix: pick one.
- [ ] `home/agents/go-server-to-api.md:128,130` (Group A) says keep admin
      API routes and admin API token auth; `:149-151` (Group D, same
      direction) says remove all admin API routes and remove auth
      middleware; `:240` sides with Group D. Fix: make Group A match.
- [ ] `home/agents/spec-migrator.md:104,105,147,148` enumerates only
      `SERVER.md`, `API.md`, `APPLICATION.md`. `HYBRID.md` exists in both
      `claudemgr/go/` and `claudemgr/rust/` and is spec'd in AI.md Part 9.
      Fix: add `HYBRID.md`.
- [ ] `home/agents/spec-migrator.md:175` is a self-cancelling step. Fix.
- [ ] `home/agents/statusline-setup.md` claims 5-hour/weekly token counts
      are "server-side only, NOT available" and documents a default
      command without them; `home/settings.json:26-29` already ships a
      statusline reading `.rate_limits.five_hour.used_percentage` and
      `.rate_limits.seven_day.used_percentage`. Fix: correct the claim and
      sync the documented default to the shipped one.

## A4 — cicd-maintenance / dockersrc-bootstrap / rpm-builder

- [ ] `home/agents/cicd-maintenance.md:238,244-249` SHA table disagrees
      with `home/memory/cicd_conventions.md:701,708-714` on six actions
      (checkout, login-action, build-push-action, setup-buildx-action,
      setup-qemu-action, action-gh-release). The agent's own `:233` points
      at the memory file. Fix: single source — delete the agent's table.
- [ ] `home/agents/cicd-maintenance.md:3,161,186` audits `security.yml`,
      which no memory file defines; `cicd_conventions.md:69,614,730-733`
      puts the security gates in `ci.yml`. Fix: retarget to `ci.yml`.
- [ ] `home/agents/cicd-maintenance.md:88-93` edits without committing,
      then `:118-135` merges the PR — the fix is stranded in the working
      tree while the unfixed branch merges. Fix: reorder.
- [ ] `home/agents/cicd-maintenance.md:139,145` instructs writing to
      `~/.claude/memory/cicd_conventions.md`, outside `{project_dir}`, and
      the caller's `gitcommit --dir {project_dir} all` cannot capture it.
      Fix: report instead of writing.
- [ ] `home/agents/dockersrc-bootstrap.md:56-63,74` — a new repo can never
      resolve to `REPO_TYPE=base`, because base detection requires
      pre-existing `Dockerfile.*` while Mode A requires none. Fix the
      detection order.
- [ ] `home/agents/dockersrc-bootstrap.md:15,121` hardcodes `/tmp/...` and
      `mktemp -d /tmp/gen-${name}-XXXXXX`; `tempdir_conventions.md:16,19`
      mandates `${TMPDIR:-/tmp}/{project_org}/{internal_name}-XXXXXX/` and
      `:30-31` lists these exact forms as wrong. Fix both.
- [ ] `home/agents/dockersrc-bootstrap.md:224,229,230` dead-function regex
      `__[a-zA-Z_]+` has no digits, so its own canonical example at `:238`
      (`__get_ip` → `__get_ip4`) is silently missed. Fix: add `0-9`.
- [ ] `home/agents/rpm-builder.md:46` "every package built for x86_64 and
      aarch64, no exceptions" vs `:315` building only
      `eol/centos-7-x86_64`; `rpm_conventions.md:229` includes
      `eol/centos-7-aarch64`. Fix: add the arch.
- [ ] `home/agents/rpm-builder.md:271-273` says `createrepo_c` ships in the
      image with no setup step; `:356-357` then runs `dnf install -y
      createrepo_c`. Fix: drop the install.
- [ ] `home/agents/rpm-builder.md:119-121` uses `%if 0%{?rhel} <= 7`, which
      is true on Fedora (undefined `%rhel` → 0), so the EL7 error fires on
      every Fedora build; `:246` mislabels it and `:254` states the correct
      rule. Same defect at `rpm_conventions.md:154` — fix both together.
- [ ] `home/agents/rpm-builder.md:22` `Vendor:` uses plain `http://`;
      `:360` publishes to `~/Documents/builds/sourceforge/RHEL/el9/…`
      while `rpm_conventions.md:385` uses `~/Documents/builds/RHEL/9/…`.

## A5 — go-auth-builder / rust-auth-builder

- [ ] Shared correctness bug: `retry_after` is always 0.
      `window_start = now - window_secs`, then
      `retry_after = window_secs - (now - window_start)` — algebraically
      zero (`go-auth-builder.md:880,889`; `rust-auth-builder.md:1000,1008`).
      Fix: `retry_after = window_secs`.
- [ ] Shared: the rate limiter fails **open** on DB error
      (`go:883-887`, `rust:1002-1006`), removing brute-force protection
      from login while both files assert every auth endpoint is limited.
      Fix: fail closed.
- [ ] `rust-auth-builder.md:1843,1846` runs bare `cargo build` / `cargo
      test` on the host, against `home/CLAUDE.md` Build & Execution and
      `rust_conventions.md:186`. Go's equivalent (`go:1694-1697`) uses
      `make build`/`make test`. Fix: mirror Go.
- [ ] `rust-auth-builder.md:1851-1852` permits bcrypt "as a one-time
      migration path", against `security_conventions.md:260` (Argon2id
      only, never bcrypt) and against `rust:1898,1933,1950` in the same
      file. `go:1700-1702` bans it outright. Fix: remove the exception.
- [ ] `rust-auth-builder.md:1286,1698` cite `SERVER.md`, which does not
      exist anywhere in this repo. Fix: remove or repoint.
- [ ] `go-auth-builder.md:1033` and `rust-auth-builder.md:1159` say "see
      PART 34 note below"; neither file contains any PART heading.
- [ ] `rust-auth-builder.md:1686` points at "Step 6/7 code comments" for a
      layering pattern; Steps 6-7 (`:764-1056`) contain no such comment.
- [ ] Both descriptions (`:3`) claim "carries all DB schemas, models,
      service layer, middleware, handlers … and tests internally. No
      external spec files required." All four claims fail: no service
      layer section exists; Step 8 "Handlers" (`go:970-1152`,
      `rust:1094-1278`) is prose inside code fences with no handler code;
      Step 14 "Tests" (`go:1678-1686`, `rust:1827-1835`) is a six-bullet
      checklist with no tests; and `go:63`/`rust:67`, `go:1731`/
      `rust:1881`, `go:1764`/`rust:1914` read IDEA.md and AI.md while
      `go:17-18`/`rust:17` say "Do not read spec files". Fix: correct the
      descriptions or add the missing content.
- [ ] Embedded code calls undefined things: `go:908` `splitComma()`/
      `trim()` (not stdlib, never defined, `strings` not imported —
      violates the file's own `go:1808`); `go:976,1804` `dummyHash`
      (rust defines it at `rust:354`); TOTP validation
      (`go:978,1000-1011`, `rust:1103,1125-1136`) has no implementation or
      crate; CSRF tokens injected into every template (`go:1160`,
      `rust:1286`) with no generation or verification; the `rate_limits`
      table the limiter queries (`go:860`, `rust:965`) is absent from
      Step 4's DDL.
- [ ] Lint gates would fail on the agents' own emitted code:
      `go:896-898` is an empty `if err != nil` branch (staticcheck SA9003);
      `rust:456` `EmailAddress::is_valid(e) == false` trips
      `clippy::bool_comparison` under `-D warnings` (the sibling validator
      at `rust:614` gets it right).
- [ ] `rust:299` and `rust:1958` forbid `unwrap()`/`panic!`; `rust:405,
      507,641,1018` use `unwrap()`, including on the rate-limit path.
- [ ] Inline comments in emitted files, against `home/CLAUDE.md`:
      `go:1614`/`rust:1763` emit `mode: open           # open | private`
      into `server.yml`; every SQL DDL block uses trailing `-- …`
      (`go:109-116,138,189`; `rust:115-121,144,195`).
- [ ] Invite page route defined twice: `go:1052`
      `GET /api/{api_version}/auth/invite/{token}` vs `go:1535`
      `GET /auth/invite/{token}`, while the emitted link at `go:1039` uses
      the latter. Identical at `rust:1178` / `:1677` / `:1165`.
- [ ] Rate limits specified "per admin" (`go:1034`, `rust:1160`) but
      bucketed by client IP only (`go:877-878`, `rust:997-998`); the
      Step 7 default table (`go:934-948`, `rust:1058-1072`) omits
      `auth.password_change` 3/3600, invite-create 20/3600, and
      invite-accept 10/3600 that the handlers require.
- [ ] Feature menu dependency graph (`go:78-81`, `rust:82-85`) states only
      "4 requires 3 · 5 requires 3 or 4", but Feature 3's
      `user_invites.invited_by … REFERENCES admins(id)` (`go:210`,
      `rust:216`) makes Feature 3 hard-depend on Feature 1.
- [ ] Cross-agent disagreements to reconcile: dummy-hash timing defence
      (undefined in Go, defined in Rust); password verify (hand-rolled PHC
      parse at `go:340-372` never checks the algorithm field is
      `argon2id`, vs crate verifier at `rust:342-349`); TOTP disable writes
      `totp_secret=""` (`go:1011`) vs `NULL` (`rust:1136`); i18n discovery
      path `*/i18n/*` (`go:1628`) vs `*locales*` (`rust:1777`); JSON
      framing trailing newline required (`go:963-964`) vs none
      (`rust:1087-1088`).

## A6 — billing / notifications / support builders

- [ ] `home/agents/billing-builder.md:209-216` provider roster diverges
      from `home/TEMPLATES/BILLING.md:519-810`: 13 providers appear that
      the spec does not contain (PayU, Bancontact, Sofort, OpenNode, Zip,
      Chargebee, Recurly, BACS, Perfect Money, WebMoney, Payeer, plus
      Braintree and 2Checkout miscategorized) and 9 spec providers are
      dropped (Worldpay, Checkout.com, Flutterwave, Alipay, WeChat Pay,
      BTCPay Server, PayPal Pay Later, Zuora, Amazon Pay, PaySera,
      Payoneer, Wise). Fix: regenerate from the spec.
- [ ] `home/agents/billing-builder.md:3` claims "47+ providers"; the eight
      lists total 47 line items but 46 unique — PayPal is counted at both
      `:209` and `:215`.
- [ ] `home/agents/billing-builder.md:133` subscription state machine adds
      `SUSPENDED`, which `BILLING.md:375-383` does not define (7 states).
      Violates the agent's own `:147` and `:230`.
- [ ] `home/agents/billing-builder.md:138` invoice state machine drops
      `OVERDUE`, `PARTIAL`, `DISPUTED`, `CANCELLED`
      (`BILLING.md:1265-1276` defines 10).
- [ ] `home/agents/billing-builder.md:135,204` provider state machine
      drops `MAINTENANCE` and `DEPRECATED`
      (`BILLING.md:1329-1337` defines 8).
- [ ] `home/agents/billing-builder.md:176-196` `PaymentProvider` interface
      has 19 methods; `BILLING.md:880-912` defines 22 — `get_balance()`,
      `verify_customer()`, `report_transaction()` are missing.
- [ ] `home/agents/billing-builder.md:11,513` forbid stubs; `:206` orders
      "create stub plugin files". Also collides with `home/CLAUDE.md`
      "No partially implemented code".
- [ ] `home/agents/billing-builder.md:24` attributes the invoice state
      machine to Section 5; it is Section 9 (`BILLING.md:1263`), which the
      same file cites correctly at `:284`.
- [ ] `home/agents/notifications-builder.md:25` cites "Section 11
      (Integrated Help System)"; Section 11 is Administrative Controls,
      Integrated Help System is Section 12 (`NOTIFICATIONS.md:1184`).
- [ ] `home/agents/notifications-builder.md:151` status enum
      (`PENDING, QUEUED, SENT, DELIVERED, FAILED, BOUNCED, READ`) does not
      match `NOTIFICATIONS.md:676-685` (`CREATED, QUEUED, SCHEDULED,
      SENDING, DELIVERED, FAILED, RETRYING, EXPIRED, CANCELLED`), while
      `:149-150` demands spec-exact names for the adjacent enums.
- [ ] `home/agents/notifications-builder.md:394-399` retry schedule
      (immediate → 1m → 5m → 30m → 2h) falls outside
      `NOTIFICATIONS.md:983-990` (initial 30s, multiplier 2, max 1h).
- [ ] `home/agents/notifications-builder.md:389` offers overflow actions
      `QUEUE`/`DROP_LOW_PRIORITY`; `NOTIFICATIONS.md:965-970` defines four
      options, neither of those identifiers among them.
- [ ] `home/agents/notifications-builder.md:248-255` SMTP auto-detect only
      displays the detected host; `NOTIFICATIONS.md:456-463` requires SMTP
      be auto-ENABLED and the config saved to the database.
- [ ] `home/agents/support-builder.md:200-205` says GUEST "cannot create
      tickets"; `SUPPORT.md:101-105` grants guests ticket submission with
      email verification plus bot access. The error is baked into a test
      at `:625` under a heading (`:197`) claiming it reproduces "the
      spec's 4-role system exactly".
- [ ] `home/agents/support-builder.md:347-358` omits
      `* → CLOSED: Admin force close` (`SUPPORT.md:697`), and `:626`
      instructs writing a test asserting `OPEN → CLOSED` is invalid — that
      test fails against a spec-conformant implementation.
- [ ] `home/agents/support-builder.md:314-320` sends a rejected
      100%-confidence bot match straight to the ticket form;
      `SUPPORT.md:528-530` requires up to 2 more attempts, and the agent's
      own `:325` says the bot never escalates before 3 attempts.
- [ ] `home/agents/support-builder.md:85,118` write source files before
      the mandatory user gate at `:124`, and before knowing whether
      feature 1 — which the bot is bundled with (`:141`) — was selected.
- [ ] `home/agents/support-builder.md:143,690` call support mode
      mandatory, but it ships only with menu item 2 (`:132`), which `:128`
      lets the user decline.
- [ ] `home/agents/support-builder.md` table name inconsistent:
      `audit_logs` at `:170` vs `audit_log` at `:665` and `:700`.
- [ ] `home/agents/support-builder.md:159` says the spec defines "a
      minimum of 11 entities … implement all of them", then lists 12
      (`:165-174`); the extra `support_agents` is not in
      `SUPPORT.md:1720-1731`.
- [ ] Spec-side, inherited by `notifications-builder.md:259`:
      `home/TEMPLATES/NOTIFICATIONS.md:475` claims "40+ providers" for
      SMTP presets while its own breakdown at `:549-556` totals 30.

## A7 — skills

- [ ] `home/skills/bootstrap-script/SKILL.md` `.gitignore` block omits
      `.claude/.credentials.json`, required by
      `home/memory/gitignore_conventions.md:133`, and uses `.no_push`
      where the convention uses `**/.no_push`. Fix both.
- [ ] `home/skills/bootstrap-script/SKILL.md` references
      `script_conventions.md` and `project_files.md` by bare filename;
      every other file in the repo uses the `~/.claude/memory/` path.
- [ ] `home/skills/bootstrap-script/SKILL.md` tells the user to create an
      MIT `LICENSE.md` authored "Jason Hempstead, Casjays Developments",
      while this repo's own `LICENSE.md` is WTFPL © "casjay
      <git-admin@casjaysdev.pro>". Confirm which is intended.

## A8 — README

- [ ] `README.md` Agents section lists 29 of 32 — missing `implement`,
      `dockersrc-bootstrap`, `rust-auth-builder`.
- [ ] `README.md` `planner` row says "Use when a task touches 3+ files",
      directly contradicting `home/agents/planner.md`'s own description
      ("Do NOT invoke simply because a task touches many files") and
      `home/CLAUDE.md` ("Plan mode for genuine ambiguity only — not for
      file count").
- [ ] `README.md` directory-layout tree omits `home/skills/` and
      `home/TEMPLATES/`; there is no Skills section at all.
