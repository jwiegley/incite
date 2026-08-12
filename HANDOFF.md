# Grind-tests / grind-live-view plan — handoff

Working doc for the 13-step plan turning `commands/grind-tests.md` and
`commands/grind-live-view.md` into workflow-backed launchers over a shared
`grindFlow`, with `grindGrantFor`, `grindSynthesisOver`, and `reviewAuditFlow`
factored out of the existing grind-paradox / review-audit machinery.

## Task list

- [x] 1. Green `nix flake check`; capture `plan grind-paradox` and `cost grind-paradox` renders to files (pre-refactor baseline). DONE (commit f6c8423's session; captures in /tmp/grind-baseline/).
- [x] 2. Fix denotations: haddock semantics + law + named check for `reviewAuditFlow`, `grindGrantFor`, `grindSynthesisOver`, `grindFlow`. DONE (recorded below and in the haddocks, commit f6c8423).
- [x] 3. Decide `grindCheckCmd` wrapper: nix-develop branch chosen on recorded evidence (commit f6c8423). THE DRY RUN IN THE TARGET CHECKOUT IS STILL OWED — see blocker below.
- [x] 4. Prep refactor, zero behavior change; fences + render diff vs step-1 captures. DONE (commit f6c8423; render diff empty).
- [x] 5. Spec cases for `grindGrantFor` and `grindSynthesisOver` on synthetic inputs. DONE (commit f6c8423).
- [x] 6. `prompts/grind/tests-facts.md` + 9 lens bodies + Prompts.hs bindings + separation-law Spec case; manual fact-inventory tally. DONE (tally below).
- [x] 7. Define grind-tests in Review.hs/Feature.hs; empty-diff clause in the AtChange preamble (golden re-recorded) + Spec case. DONE.
- [x] 8. Register + fence grind-tests; grindPanelTests factored into the `GrindFence` record helper; red trials run on both tables (full table flip → red, blocked table flip → red, both reverted). `factsFileTests` folded over both facts files; tests-grind fixer case added. DONE.
- [x] 9. `prompts/grind/live-view-facts.md` + 11 lens bodies + bindings; severity-word Spec case ("the auth lens and the ranking clause share the severity vocabulary"). DONE.
- [x] 10. Define grind-live-view over `grindFlow grindLiveViewSpec`; the ranking clause rides in as `gsSynthesisSuffix`, grindFlow inserts a one-blank-line seam for a non-empty suffix (pinned by the synthetic-spec case), and the shipped spec is fenced by field equality. `auth` sits at lens position 7 so it lands on claude-agent under BOTH rosters (pinned by the fence tables). DONE.
- [x] 11. Register + fence grind-live-view (Main.hs, mirrorWorkflows, docs inventory row, GrindFence instance, fixer-table row, factsFileTests row with its own needle list, projectIdentifiers extended with topics.ex/PhxHook/assets-ts-hooks); docs pass (grindFlow skeleton, derived-grant sentence, grind-tests splice paragraph); identifier grep over every docs-named binding: zero misses. DONE.
- [x] 12. Both commands rewritten as launchers (91/89 lines, STE-clean), engines preserved as commands/grind-tests-engine.md and commands/grind-live-view-engine.md, flake.nix stePromptSrc + descriptions updated. STE red trials run: a planted slop word in each launcher failed checks.ste-prompts NAMING that file; green after revert. On a wrong checkout the launchers now say what actually happens: grindSynthesisOver refuses to RANK on FACTS PATHS UNRESOLVED (landed in the second audit's fix pass, fenced), but the flow is static — the downstream stages still run, acting on the refusal rather than findings, and the run fails at its gate. The waste is bounded (a fixer handed a refusal has nothing to fix; the gate's checks go red in the wrong checkout; repairFuel caps the repair trips), and the launchers' pwd instruction is the real guard. The earlier "synthesis stops the run" wording overclaimed and is gone. DONE.
- [~] 13. Acceptance, offline half DONE: nix flake check green over everything; `plan grind-tests` renders 12 lens@backend leaves → synthesis → remediate → the full review-audit segment → synthesis → remediate → compile/tests/vitest → repair; `plan grind-live-view` renders 11 lenses → synthesis → remediate → compile/tests → repair; `cost` renders POSITIVE numbers for both (grind-tests' second fixer loop got `grindTestsReviewFuel = Just 12` after `cost` reported a negative worst case — two unbounded loops overflow; a new inventory-wide fence pins positivity); `list` shows both tools; grind-paradox plan+cost renders byte-identical to the step-1 baseline. STILL OWED (machine with the operation checkout): the step-3 dry run of every rendered argv, then the paid runs (grind-live-view first, clean tree, throwaway branch), then delete both -engine.md files and confirm flake check stays green.

## Handoff notes

- Session started 2026-08-12. No prior progress; this doc created at step 1.
- Step 1 DONE: `nix flake check` green; baseline captures in `/tmp/grind-baseline/`
  (plan-grind-paradox.txt, cost-grind-paradox.txt) — NOT committed. Re-anchored
  after commit f6c8423 landed: regenerated from the committed tree with the nix
  noise lines stripped, and diffed identical against the pre-refactor captures,
  so the step-13 acceptance diff traces to the commit. This machine has
  `BLOCK_OPENCODE` set, so local renders show the blocked pairing; the nix
  test sandbox sees the full roster.
- **BLOCKER for steps 3 and 13**: no operation checkout (Elixir/Phoenix app,
  OTP app `operation`) exists on this machine — searched `/home/ishapira`
  exhaustively (no `mix.exs`, no `lib/operation_web`, no `domain/`, no `fstar/`
  anywhere). No Paradox checkout either. Consequences:
  - Step 3's probe and dry run cannot execute here. Decision made on recorded
    evidence instead: `commands/grind-live-view.md`'s own final gate runs
    `nix develop -c mix compile --warnings-as-errors` (with a fallback clause),
    so the target project has a nix dev shell; the paradox precedent —
    `grindCheckCmd`, fenced by the Spec case "every check runs inside the
    target project's dev shell" — uses
    `nix develop --command bash -c <cmd>`. `grindCheckCmd` therefore takes the
    nix-develop branch, bash -c innermost. THE DRY RUN IS STILL OWED: before
    any paid run, execute every rendered argv of both grinds verbatim in the
    operation checkout and reopen this decision if any fails
    environment-shaped. Dry-run owner: also evaluate adding a third
    grind-live-view gate row (vitest or tsc) there — the grind writes TS
    hooks, the retired gate checked none of them, and a command that has
    never run in the checkout risks the permanently-red gate grindCheckCmd's
    haddock names, so the dry run is where such a row earns its place.
  - Step 13's paid runs are deferred to a machine with the operation checkout.
    Per step 12's own rule the JS engines stay until those runs pass; they are
    preserved as `commands/grind-tests-engine.md` and
    `commands/grind-live-view-engine.md` (unregistered) once step 12 lands.
- Step-2 denotations live where they are enforced, not here: `reviewAuditFlow`,
  `grindGrantFor`, `grindSynthesisOver` and `grindFlow` each carry their law in
  their own haddock, pinned by the named Spec cases — "grindGrantFor derives
  its grant from the checks it is given", "grindSynthesisOver names the grind
  and every roster lens exactly once", "grindFlow derives its synthesis and its
  fixer's rule from the spec", and the per-grind `GrindFence` cases.
- `grindFlow` takes a `GrindSpec` record (name, facts, lens table, synthesis
  suffix); the synthesis brief and the fixer's rule are DERIVED from it. The
  seam grind-live-view needs is `gsSynthesisSuffix`: its ranking clause goes
  there, appended below the derived `grindSynthesisOver` brief.
- Step-6 fact inventory (commands/grind-tests.md → prompts/grind/tests-facts.md),
  ticked line by line. Facts found: 24. Facts carried: 21 carried verbatim or
  tightened (stack, runners, mutation/coverage/property tooling and read paths,
  test locations, support/case templates, Wallaby+Ids, F* coverage+apply/3,
  .dox layout+Dox.* namespace, wire strings, sleep-replacement signals incl.
  GSAP onComplete, fix hierarchy, never-weaken, style, verification commands,
  compile check). Deliberately dropped, with reasons: (1) muex v0.6 / Stryker
  v9.6 version pins — versions drift and the read paths are the durable facts,
  same failure class as paradox's stale `lib-tests`; (2) the report/TODO-file
  paths — grindSynthesisOver owns the dated report path, and the grind design
  has no separate TODO file (the fixer is the next stage of the same run);
  (3) the JS-engine orchestration facts (agent counts, wave scheduling,
  schemas) — replaced by the workflow machinery itself.
- Recorded candidate for a future deliberate change (NOT part of this plan):
  make the wrong-checkout stop real by putting a fuel-1 `loopUntil` behind
  each grind's synthesis that aborts the run when the synthesis opens with
  `FACTS PATHS UNRESOLVED` (a pure decide over the synthesis text — no exec
  leaf, no grant change, and `grindSynthesisOver` would need to demand the
  line open the answer). Costs: every grind's `plan` render changes, so the
  pinned grind-paradox baseline identity ends, and the fence tables/goldens
  move. An abandoned in-tree draft of exactly this (`spreadPinned`,
  `decideFactsResolved`, `gsPins`) was found unstaged after the third fix
  pass and discarded in favor of the truthful-prose fix; take the idea, not
  the draft.
- During the third audit, `flake.lock`'s agent-functor input got bumped
  (revCount 267→272) by something outside this session's work; the bump was
  reverted rather than silently committed — every commit here is verified
  against the locked 267. Bump deliberately, on its own, if wanted.
- Post-commit audit per `post-commit-audit` skill after each commit; findings
  fixed via one `fix-all` subagent; fix commits not re-audited.
- Unreported extra work in 7edd211 (the second audit's fix pass), for the
  record the commit message cannot carry: it also removed the `gfLabel` field
  (the test-group label now derives from the fenced workflow), added the
  `testsGrindTail` helper for grind-tests' review-audit acting tail, added the
  gate-command drift fence case ("the tests grind's facts state every command
  its gate runs"), and dropped the then-unused `stackPin` import from
  test/Spec.hs.
- The audit of `7edd211` has now been lost TWICE to agent-functor server
  restarts (`runs` came back empty both times; the second loss ate a run that
  was mid-synthesis with two High findings visible in its tail: one about the
  grind-live-view gate, one about the fixer fuel stop — details unrecoverable).
  Restarted again 2026-08-12 as review-lite run-1 (sandboxed), input pointing
  at `git show 7edd211` plus the plan steps and the claims list. fess-audit
  stays off: the first retry failed permanently (captured transcript ~1.54M
  tokens, over the 1M limit) and the restarts have since discarded the very
  transcript it would audit — review-lite's fess lens is the claims check,
  per the skill. Findings from run-1, if any, get one `fix-all` subagent;
  that fix commit closes the loop unaudited.
- run-1 (the third attempt) COMPLETED 2026-08-12 ~04:45. Six lens reports; the
  full output is preserved in `runs/run-1/transcript.log` (tail) if needed.
  Real findings, all handed VERBATIM to one `fix-all` subagent (running in this
  session, tree edits uncommitted until reviewed): correctness — the launchers'
  "synthesis stops the run" prose overstates the static grindFlow (fixer/gate
  still run after a refusal), the negative-cost fence has a mod-2^64 wrap hole
  (durable fix: checked arithmetic in Agent.Cost), the field-equality case
  covers 3 of 4 GrindSpec fields (gsFacts unchecked, lens names not bodies);
  fess — STE red trials left no artifact (re-run and record), strengthen the
  equality case, record the byte-identical-by-monoid-law correction, disclose
  the vacuous.md bar loosening + the small undisclosed scope items; qa (High) —
  no TypeScript check in the grind-live-view gate though lenses may edit
  assets/ts/hooks, refusal is prompt-text only, fuel=12 exhaustion falls
  through the gate; haskell — bare partials in the synthetic grindFlow case,
  Fuel newtype wanted upstream; complexity — 4 braids (severity vocabulary,
  refusal magic string, lens-order/backend coupling, gate rule not derived
  from the spec); ponytail — cuts, arbitrated: engines STAY (step-12 rule),
  equality case STRENGTHENED not deleted, fuel binding gets the newtype not
  inlined. The recovered Feature.hs:730 AtChange finding (missing from the new
  run) was handed to the fixer as a seventh report. The fixer's commit closes
  the audit loop for 7edd211 — it is NOT re-audited, per the skill.
- RECOVERED from the lost run's on-disk transcript (runs/run-1/transcript.log,
  lines 28257–30419 — the server reuses run ids, so the old stream survives as
  a prefix of the new run's log): the run died mid-verification, no final
  synthesis; one lens had reported (1) High, Feature.hs:1120 — the post-review
  fixer's `grindTestsReviewFuel = Just 12` stop means `decideTrip` yields on
  WORK REMAINS and the gate can pass over known unresolved review findings;
  (2) Medium, Feature.hs:730 — the AtChange docs/audits exclusion also skips a
  legitimate change whose ONLY file is an audit report ("no change to audit"
  on valid input). Cross-check the new run's synthesis against these two; if
  the new run misses either, hand it to the fixer anyway.
