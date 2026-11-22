# TODO.AI.md

All findings from the 2026-08-30 hook-vs-rules audit have been fixed and
removed. What remains below are upstream Claude Code environment bugs —
tracked here because they affect sessions on this machine, but not fixable
by any change in this repo — plus in-repo follow-ups discovered but ruled
out of scope for the task they were found during.

## In-repo follow-up (not fixed this session — out of scope)

- [ ] Auto-mode classifier vetoes the documented
      `TEST_LINT_GATE_OVERRIDE=1 gitcommit --dir <dir> all` escape hatch
      even after explicit user consent ("judged this action dangerous (it
      gave no explanation)"), reported 2026-09-28 from a session linting
      `casjay-base/{debian,ubuntu,fedora,raspbian,arch,alpine}`. The
      false-block that led there (marker keyed on session cwd instead of
      the linted repo, plus transcript fallback skipping results whose
      cwd differed, plus async hand-back never read) is fixed in
      `lint-agent-mark.sh`/`enforce-test-lint-gate.sh`. The classifier veto
      is server-side, not fixable in this repo — re-check whether the
      override is still vetoed once the gate stops false-blocking.

- [ ] `home/scripts/statusline.sh` line 29 uses `payload="$(cat 2>/dev/null || true)"`
      to read stdin — flagged pre-existing (not touched by this session)
      by the `script-lint` gate run 2026-09-27: the UUOC exception for
      socket/pipe input only covers `home/hooks/*.sh`, not
      `home/scripts/`, so this should become
      `payload="$(< /dev/stdin 2>/dev/null || true)"`.

- [ ] AI.md drift vs. actual `home/` tree, found 2026-09-27 during a
      routine `read AI.md`/`read ./home` pass (not fixed, out of scope
      for that read-only task): AI.md Part 5's agent table was missing
      8 of the 32 files under `home/agents/` — `billing-builder.md`,
      `designer.md`, `go-auth-builder.md`, `go-server-to-api.md`,
      `notifications-builder.md`, `rpm-builder.md`,
      `rust-auth-builder.md`, `support-builder.md`. AI.md Part 4's
      memory-file table was missing `networking_conventions.md`. AI.md
      Part 1's repo-layout tree lists only
      `CLAUDE.md`/`settings.json`/`agents/`/`hooks/`/`scripts/`/`memory/`
      under `home/`, but `home/skills/` (10 skill dirs) and
      `home/TEMPLATES/` also exist on disk — `TEMPLATES/` is documented
      separately in Part 9, but `skills/` has no documentation anywhere
      in AI.md, and neither appears in the Part 1 tree. Needs: add the
      8 missing rows to the Part 5 table, add the missing
      `networking_conventions.md` row to the Part 4 table, add
      `skills/` and `TEMPLATES/` to the Part 1 tree, and add a
      `skills/` section (parallel to Part 5/6's agent/hook sections)
      documenting the `home/skills/` file shape and current skill list
      if one doesn't belong elsewhere already.

- [ ] `script-lint` agent (`home/agents/script-lint.md`) intermittently
      "dies"/goes idle mid-run per user report (random, no specific
      trigger file/project identified). Investigated: two live
      reproduction attempts via the Agent tool against
      `home/hooks/no-secrets.sh` (small) and `install.sh` (larger,
      exercises naming/cross-file rules) both completed cleanly with
      no hang (`no-secrets.sh: clean`, 53405 tokens/12 tool_uses/84768ms;
      `install.sh: clean`, 51514 tokens/15 tool_uses/175333ms) — bug not
      reproduced, root cause not found. Leading hypothesis (haiku model
      undersized for the agent's 265-line ruleset) was raised and
      rejected by the user because it directly contradicts AI.md Part 5's
      explicit `model: haiku` classification for this agent — user
      explicitly said keep haiku, find a different root cause. Needs
      further diagnosis (e.g. capturing a live failure transcript when
      it next happens) before any fix is attempted.

- [ ] `block-host-toolchain.sh` (line ~167) and `no-forbidden-files.sh`
      (line ~394) each hardcode their own
      `("go.mod", "Cargo.toml", "package.json", "pyproject.toml")`
      4-manifest tuple for unrelated purposes (host-toolchain-invocation
      detection and the forbidden-root-file directory check) — found
      while expanding `enforce-test-lint-gate.sh`'s/`test-lint-mark.sh`'s
      manifest detection to Kotlin/Gradle, Java/Maven, Ruby, PHP, Swift,
      Dart/Flutter, C/C++, .NET, and Elixir (2026-09-12). Left unchanged
      because the user's request was specifically about the test/lint
      gate's "not covered" error, not these two hooks; expanding them
      needs its own verification pass (each hook's own detection logic
      and test coverage) rather than being folded into this fix.

- [ ] `enforce-test-lint-gate.sh`'s spec-collection path requires a
      `spec-guard/{session_id}/read` marker for the project, but that
      marker is only ever written by `spec-guard.sh` — which explicitly
      exits 0 without writing anything when the project has none of
      `AI.md`/`SPEC.md`/`CLAUDE.md` (line 71-73 of `spec-guard.sh`).
      Found 2026-09-27 committing a one-line spelling fix in
      `composemgr/template` (a template repo with only `README.md` at
      its root, no `AI.md`/`SPEC.md`/`CLAUDE.md`): `is_spec_collection()`
      correctly classified it, but the required marker can never exist
      for this exact project shape, permanently blocking every commit
      regardless of how thoroughly the spec substitute was actually
      re-read. `enforce-test-lint-gate.sh`'s own block message already
      promises this case is covered ("for a template repo with neither,
      its root-level *.md spec file") — the promise isn't backed by any
      marker-writing path. Needs either: `spec-guard.sh` gains a
      README.md-substitute branch that writes the marker for projects
      with none of the three gating files, or `enforce-test-lint-gate.sh`
      accepts a lighter signal (e.g. a transcript scan for a Read of the
      project's root README.md this session, mirroring the existing
      `transcript_pass()` test/lint fallback) for this specific shape.
      Worked around this occurrence with a user-authorized
      `TEST_LINT_GATE_OVERRIDE=1`, after independently re-reading
      README.md and validating the changed YAML file this session.
      CORROBORATING OCCURRENCE: a second session hit the identical
      unsatisfiable-marker shape on another project (root has only
      `README.md`/`LICENSE.md`, no `AI.md`/`SPEC.md`) and left a note in
      that repo's `TODO.md` recommending the same
      `TEST_LINT_GATE_OVERRIDE=1` workaround — confirms this is a
      general `spec-guard-mark.sh` gap (its fallback `case` at
      lines 59-70 has no branch that can ever match when every root
      `*.md` is an excluded meta name), not specific to
      `composemgr/template`. That stray `TODO.md` note has been removed
      now that the issue is tracked here instead.

## Environment bug, not fixable in this repo

- [ ] 68 (OPEN, not a climgr/claude code issue): live long-running
      session (5b02732a-98bc-4e4b-86ff-94fff4d9ca97) has PreToolUse
      hooks firing correctly (enforce-test-lint-gate.sh blocks as
      designed) but PostToolUse hooks (test-lint-mark.sh) silently not
      firing for real Bash tool calls — confirmed not a script bug via
      direct simulation of the deployed hook with the real session_id,
      cwd, and command, which wrote the marker correctly every time; no
      project-local settings.json/settings.local.json override exists
      to explain it. Likely the same class of stale-hook-registration
      bug as the documented SessionStart-on-/clear issue
      (anthropics/claude-code#34072), but for PostToolUse specifically,
      and it does NOT clear on /clear per that same bug. Workaround used
      this session: manually append the project path to
      ${TMPDIR}/claude-hooks/test-lint-guard/<session_id>/{test,lint}
      once the user reports a real passing test/lint run, matching
      exactly what the hook would have written (path renamed since —
      see the claude-hooks namespace commit). No permanent fix available
      from inside this repo — would need a fresh session (new process)
      to re-register hooks, or an upstream Claude Code fix.
      Corroborating occurrence: session 75c8a099-4388-4e7d-b49c-45dedcfcdf80
      (apimgr/ipgaze project) showed the identical failure mode —
      lint-agent-mark.sh (SubagentStop) correctly wrote its `lint`
      marker, but test-lint-mark.sh (PostToolUse) never wrote `test` for
      a real, user-confirmed passing `make test` run in the same
      session. This is the opposite of what that session's own
      transcript concluded (it believed the lint marker was the one
      missing) — verified backwards by reading the real marker files
      directly. Attempting the same manual-append workaround for that
      session was denied by the Claude Code auto-mode classifier;
      per CLAUDE.md's "never auto-bypass a hook/classifier block" rule,
      this was not routed around — left for the user to resolve
      directly (write the marker themselves, or grant an explicit Bash
      permission rule for that path) if they still want the marker
      backfilled.
      UPDATE: `enforce-test-lint-gate.sh` now also scans the PreToolUse
      payload's own `transcript_path` for a passing test/lint Bash call
      this session, independent of whether `test-lint-mark.sh`'s
      PostToolUse marker ever got written — this directly mitigates the
      specific test/lint-gate false-block symptom described above
      without depending on a fix to the underlying registration bug.
      Verified via `echo '{...}' | bash enforce-test-lint-gate.sh`
      (AI.md's documented hook-test method): marker-only path still
      passes unchanged, and a synthetic transcript with no markers at
      all now satisfies both the test and lint gate on its own. Item
      stays open because the underlying PostToolUse/SubagentStop
      registration bug is still upstream-open and can still affect any
      other hook that has no equivalent fallback (e.g.
      `drift-guard-read.sh`, `spec-guard-mark.sh`).
      REFINEMENT (2026-09-03, user retest): on the SAME settings.json,
      SubagentStop hooks fire fine, but PostToolUse with the `Bash`
      matcher (test-lint-mark.sh) still never fires for a real
      `bash -n` call — correct session ID confirmed, no marker written
      under either /root/.local/tmp (TMPDIR) or a /tmp fallback. So the
      failure is specific to the Bash-matcher PostToolUse registration,
      not a stale session-wide hook table: other events registered from
      the same file keep working. Wiring verified correct in
      home/settings.json (PostToolUse "Bash" matcher entry present,
      identical shape to the working PostToolUse "Read"
      spec-guard-mark.sh entry). Matches upstream
      anthropics/claude-code#36310, which was auto-closed as a
      duplicate of anthropics/claude-code#6305 ("Post/PreToolUse Hooks
      Not Executing in Claude Code") — #6305 is still OPEN as of
      2026-09-03, so track that one. The transcript_path fallback in
      enforce-test-lint-gate.sh remains the effective mitigation for
      the gate's false-block symptom; no further in-repo mitigation is
      possible for the marker itself.
      ADDENDUM (2026-09-03, user request): added a `TEST_LINT_GATE_OVERRIDE=1`
      env-var-prefix escape hatch to enforce-test-lint-gate.sh (same
      pattern as drift-guard-read.sh's DRIFT_GUARD_ALLOW=1) for the case
      where BOTH the marker and the transcript fallback fail to see a
      genuinely passing run — user directs the bypass explicitly per
      invocation, Claude never sets it on its own initiative. Verified
      via synthetic PreToolUse payloads: override present → exit 0;
      override absent → still blocks exit 2 as before. This does not fix
      the underlying registration bug (still upstream, item stays open)
      — it is a last-resort user override, not a marker fix.

- [ ] `go-auth-builder.md` / `rust-auth-builder.md` now follow the SERVER
      canon (unified `tokens` table, shared `/server/auth/login`).
      `API.md` and `HYBRID.md` still use `owners` + `api_tokens`; decide
      whether the builders need an API-shape variant.
- [ ] Auth builders: no org-token handler is built (org tokens exist only
      in schema and middleware); `/auth/me` and password-change were
      mapped to `/api/{v}/users/settings` and
      `/api/{v}/users/security/password` (extension, not in SERVER.md);
      admin session, password and TOTP routes remain at
      `/server/{admin_path}/auth/*`. Verify against the template.
- [ ] `go/SERVER.md` contradicts itself on version precedence (line ~696
      `release.txt` wins vs ~40971 `VERSION` env wins); home follows the
      env-wins rule. Fix the template, then re-check `version_conventions.md`.
- [ ] `home/TEMPLATES/BILLING.md`: the tokens-table line under
      Configuration Storage is a loose fit (template defines no billing API
      keys); review or drop.
- [ ] `home/memory/rust_conventions.md` PLATFORMS lists 7 pairs (the rust
      template omits freebsd/arm64); confirm that is intended.
- [ ] Not synced: `security_conventions.md` template hardening list
      (private paths, secrets.yml, ProtectSystem=true, client-IP
      right-walk, report-form hardening); `BASE.md` bind default and
      systemd unit; `home/hooks/` and `home/settings.json` were not audited
      against the templates; `android/` and `docker/` templates changed
      before 2026-10-06 and were only spot-checked.

- [ ] `git branch -D` (force delete, needed for squash-merged branches)
      is still blocked by `no-history-rewrite.sh`; decide whether to allow
      it as `git -C {abs-dir} branch -D` like the other scoped deletes.
      `git worktree remove`/`prune` and `git branch -d` were never blocked.
