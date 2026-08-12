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
- [x] 12. Both commands rewritten as launchers (STE-clean), engines preserved as commands/grind-tests-engine.md and commands/grind-live-view-engine.md, flake.nix stePromptSrc + descriptions updated. STE red trials run and re-run (see the fourth fix pass note below for the recorded evidence). On a wrong checkout the stop is now REAL (fourth fix pass): grindSynthesisOver demands the refusal open with FACTS PATHS UNRESOLVED, and grindFlow's fuel-1 `loopUntil` over `decideFactsResolved` fails the run at the synthesis — the fixer, any review pass and the gate never act on a refusal. The launchers say exactly that, and keep the pwd instruction as the cheap guard (the panel's turns are still spent). DONE.
- [~] 13. Acceptance, offline half DONE — RE-VERIFIED 2026-08-12 after the fourth fix pass, with fresh renders from a binary built off 6e6d568 (captures in `/tmp/grind-residual/`, both roster modes): nix flake check green over everything; `plan grind-tests` renders 12 lens@backend leaves → synthesis → refusal stop → remediate → the full review-audit segment → synthesis → remediate → compile/tests/vitest → repair; `plan grind-live-view` renders 11 lenses → synthesis → refusal stop → remediate → compile/tests/vitest → repair; every grind's plan carries exactly one fuel-1 stop node; `cost` renders positive for all three in both modes (blocked: tests 4611686018427387997, live-view and paradox 4611686018427387927; full: tests 4611686018427388024) — upstream Integer arithmetic killed the wrap, with the one-unbounded-loop law and the sign check as the local layers; `list` shows all three grinds, live-view's description naming the TypeScript gate. grind-paradox's renders sit deliberately OFF the step-1 baseline since the fourth pass: `plan` differs by the stop node alone, `cost` only by the skeleton-node-count line (103→107) with the worst-case number unchanged (diff-verified against `/tmp/grind-baseline/`). STILL OWED (machine with the operation checkout): the step-3 dry run of every rendered argv, then the paid runs (grind-live-view first, clean tree, throwaway branch), then delete both -engine.md files and confirm flake check stays green.

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
    environment-shaped. The fourth fix pass added the vitest row to
    grind-live-view's gate (the grind writes TS hooks the two mix commands
    cannot see, and grind-tests already gates on the identical argv), so the
    dry run now rehearses three commands per grind rather than deciding
    whether the third earns its place.
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
- The "future deliberate change" recorded here after the third fix pass —
  make the wrong-checkout stop real with a fuel-1 `loopUntil` behind each
  grind's synthesis — LANDED in the fourth fix pass (below), under the run-1
  audit's arbitration ("if you can make the flow actually stop, that's the
  upstream fix"). Its recorded cost was paid knowingly: every grind's `plan`
  render gains the loop node, so the pinned grind-paradox plan-baseline
  identity ends at that pass; `cost` is unchanged (the stop's body is `Id` —
  zero leaves, zero worst-case executions). The "abandoned in-tree draft"
  the third pass found unstaged was the fourth pass's own in-flight work,
  interrupted mid-edit by concurrent sessions — not an abandoned draft.
- During the third audit, `flake.lock`'s agent-functor input got bumped
  (revCount 267→272) by something outside this session's work; the bump was
  reverted rather than silently committed. Explained since: it was the fourth
  fix pass landing checked arithmetic upstream (see below); the bump is now
  re-landed deliberately with its reason recorded.
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
- FOURTH FIX PASS (run-1's findings, this session's fix-all subagent; tree
  left uncommitted for review). Dispositions, one per finding:
  - Wrong-checkout stop (correctness 1 / qa High / complexity magic-string):
    made REAL. `factsRefusalLine` is one exported binding in Incite.Review;
    `grindSynthesisOver` splices it and demands the refusal OPEN with it;
    `grindFlow` stops on it (`decideFactsResolved` under a fuel-1 `loopUntil`,
    `Id` body — no leaf, no cost change). Fenced three ways: an interpreted
    run of a synthetic grind whose leaves all answer the refusal must FAIL
    with exactly panel+synthesis prompts spent (red-trialed: removing the
    stop line turned exactly that case red); pure `decideFactsResolved`
    cases over the line shapes; a brief needle for the opening instruction.
    Launchers/docs rewritten to the now-true behavior.
  - Negative-cost wrap hole (correctness 2): fixed UPSTREAM. agent-functor
    b76abc7 ("Cost: exact Integer arithmetic...") — `Finite` carries Integer,
    `mulCost` widens, CostSpec pins both wrap shapes (2 loops negative,
    5 loops wrap-to-positive); pushed to gitlab master, flake.lock re-bumped
    to it. The third pass's ≤1-unbounded-loop law and sign check stay as the
    readability/algebra layers; comments harmonized.
  - Field-equality case (correctness 3 / fess 2, arbitrated STRENGTHEN):
    now all fields — suffix, name, gsFacts, lens names AND bodies, gsPins.
  - STE red trials (fess 1): RE-RUN 2026-08-12 ~05:4x, recorded: planting
    `robust` in commands/grind-tests.md failed checks.ste-prompts with
    "commands/grind-tests.md: slop_word x1"; same word in
    commands/grind-live-view.md failed with "commands/grind-live-view.md:
    slop_word x1"; both reverted byte-exactly (diff-verified), check green
    ("ste-gate: prompt files clean"). Note the linter matches whole words:
    `comprehensively` does NOT trip the `comprehensive` pattern — a first
    trial with it passed, which is why the recorded trials use `robust`.
  - Byte-identical claim (fess 3): corrected for the record — "grind-tests
    (empty suffix) renders byte-identical to before the seam change" was true
    by the monoid law (`base <> mempty ≡ base`), not by any render diff; no
    such diff existed or could exist (plan renders leaf names, not brief
    bytes, and the only capture was post-change).
  - vacuous.md bar change (fess 4), disclosed here: the second fix pass
    relaxed "never report a test as vacuous on a reading alone" to permit
    reading-alone verdicts for tautologies. Kept: the lens is Plan-scoped
    now (it cannot run the sabotage experiment), and a tautology is the one
    case where the reading IS the proof; everything else stays
    suspected-until-the-fixer-runs-the-protocol.
  - Undisclosed scope (fess 5), disclosed here beyond the third pass's note:
    `projectIdentifiers` had "OperationWeb" REMOVED (subsumed by the
    case-insensitive `operation` needle — the haddock says so) where the
    account said only "extended"; the preserved engines carry a 2-line
    retirement banner, so "preserved" means content-preserved, not
    byte-preserved.
  - grind-live-view TS gate (qa High): the vitest row is IN
    (`grindLiveViewChecks = grindTestsChecks` — same checkout, one fact):
    the ts-hooks lens writes TypeScript neither mix command can see, and
    grind-tests already shipped the same unverified-until-dry-run argv, so
    the permanently-red-gate argument cut against the two-command gate, not
    against the row. Fence tables, grant, docs row, launcher and
    live-view-facts.md (vitest command stated verbatim, drift-fenced by the
    generalized gate-command case) all moved together. The owed dry run
    rehearses all three argv.
  - Fuel exhaustion fall-through (qa Medium / recovered High): `decideTrip`
    now yields under `exhaustionNotice` (a `## trip budget exhausted`
    heading naming the remainder unresolved), so a green gate after a
    cut-off fixer is legible as exactly that in the final artifact. Yield
    semantics kept (aborting would strand landed edits and skip the gate).
  - Bare `Maybe Int` fuels (haskell 2, arbitrated: newtype upstream): the
    upstream `Agent.Bounds.Fuel` newtype now types `orchestrateWith`,
    `decideTrip`, `workerFuel`, `stackFuel`, `grindTestsReviewFuel` —
    no threading refactor, the newtype already existed at the boundary.
  - Bare partials in the synthetic grindFlow case (haskell 1): `!!`/`head`/
    `last` replaced by one total 4-prompt shape match that fails with the
    count.
  - AtChange audit-report skip (seventh report, Medium): the exclusion is
    now scoped by the ACCOUNT's claim — a docs/audits report the account
    claims as its own output is excluded; one the account does not claim is
    part of the change like any other file. Golden re-recorded from the
    code; needle case extended with the non-skip clause.
  - Lens-order/backend braid (complexity): `spreadPinned` takes explicit
    `(lens, backend)` pins, `GrindSpec` carries `gsPins`, grind-live-view
    pins `auth -> claude-agent` as data (tables unchanged — position seven
    was already the claude slot; the pin survives a future reorder). Fenced
    on a synthetic table where pin and position disagree.
  - Severity-vocabulary braid (complexity): one home —
    `Incite.Prompts.liveViewSeverityWords`/`liveViewSeverityVocabulary`;
    `liveViewAuth` appends the demand from it (the md keeps the rubric) and
    `grindLiveViewRanking` splices it; the Spec coupling case keeps its own
    hand-written literals as the independent statement.
  - Gate rule not derived from the spec (complexity):
    `grindLiveViewRule = grindRule (gsFacts grindLiveViewSpec)`.
  - ponytail cuts, per arbitration: both -engine.md back-outs STAY (step
    12's recorded rule — they leave when the first paid runs pass, step 13);
    `grindLiveViewSpec` stays top-level (the strengthened fence reads it);
    the fuel binding got the newtype, not inlined.
  - Baseline note for step 13: grind-paradox `plan` render is deliberately
    off the step-1 baseline from this pass (the refusal stop's loop node);
    `cost` numbers and every leaf count are unchanged. 231/231 in both
    roster modes; suite grew by the cases above.
  - Process note for the reviewer: this pass collided with a SECOND audit
    loop of the same commit (session of the 54f650d fix) and with zombie
    leaves of an earlier ship-feature run that reverted in-flight edits;
    the operator session froze the zombies mid-pass and ruled this fixer
    sole writer. The two audits' arbitrations disagreed on the stop
    (prose-only vs real), the TS gate row, the Fuel newtype, AtChange and
    the complexity braids; this pass follows run-1's arbitration, which
    asked for the flow-level fixes, and 54f650d's prose-only versions of
    those findings are superseded above.
- RESIDUAL PASS (after 6e6d568; the 54f650d session's own fixer had worked
  the same run-1 findings in a `/tmp` worktree while the fourth pass held the
  tree — its deliverable survives at `/tmp/wg-audit3/rebase`): the two run-1
  findings the fourth pass left uncovered, landed from that deliverable —
  `grindFactsFiles` is a three-field `GrindFactsFile` record (no positional
  wildcard destructuring remains), and live-view-pubsub.md item 1 says
  "write it in the finding, as the code the fix asks for" (the last
  run/edit-ambiguous phrase in a read-only lens). Step 13's entry above was
  also repaired here: it still claimed the step-1 baseline identity and the
  `Just 12` positivity story that the fourth pass had deliberately
  superseded, and its live-view plan shape predated the vitest row. Renders
  re-verified fresh, per the entry.
