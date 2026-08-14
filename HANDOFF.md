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
- [~] 13. Acceptance, offline half DONE — RE-VERIFIED 2026-08-12 after the fourth fix pass, with fresh renders from a binary built off 6e6d568 (captures in `/tmp/grind-residual/`, both roster modes): nix flake check green over everything; `plan grind-tests` renders 12 lens@backend leaves → synthesis → refusal stop → remediate → the full review-audit segment → synthesis → remediate → compile/tests/vitest → repair; `plan grind-live-view` renders 11 lenses → synthesis → refusal stop → remediate → compile/tests/vitest → repair; every grind's plan carries exactly one fuel-1 stop node; `cost` renders positive for all three in both modes (blocked: tests 4611686018427387997, live-view and paradox 4611686018427387927; full: tests 4611686018427388024) — upstream Integer arithmetic killed the wrap, with the one-unbounded-loop law and the sign check as the local layers; `list` shows all three grinds, live-view's description naming the TypeScript gate. grind-paradox's renders sit deliberately OFF the step-1 baseline since the fourth pass: `plan` differs by the stop node alone, `cost` only by the skeleton-node-count line (103→107) with the worst-case number unchanged (diff-verified against `/tmp/grind-baseline/`). STILL OWED (machine with the operation checkout): the step-3 dry run of every rendered argv, then the paid runs (grind-live-view first, clean tree, throwaway branch), then delete both -engine.md files and confirm flake check stays green. NARROWED by step 14 — grind-tests no longer runs any argv that needs the operation checkout, so what is owed there is grind-live-view's three mix commands alone.
- [~] 14. grind-tests made project-agnostic (2026-08-12), after its first paid run refused: pointed at a Haskell checkout it probed `domain/`, all twelve lenses emitted FACTS PATHS UNRESOLVED, and the fuel-1 stop failed the run at the synthesis — the machinery working exactly as step 12 built it, over a workflow that could only ever read one project. `prompts/grind/tests-facts.md` is now a protocol for ESTABLISHING a tree's facts rather than a statement of one tree's: generic probe (`.git` plus a tracked test path), a seven-item discovery order the lens answers before it audits, and an absent-layer rule (report it in one line with its evidence — the derived synthesis brief refuses on an empty block, so silence about a missing mutation runner would stop the run as a backend outage). `grindTestsChecks` is `codeChecks` (`nix flake check`), the only gate a grind can run against a project it was never told the language of, since `grindGrantFor` derives the exec policy at compile time and a discovered command could not be granted; `grindLiveViewChecks` stops aliasing it and spells the three mix commands itself, because that grind is still pointed at one known project. Fences moved with it: the dev-shell case became "every check brings its own toolchain" (two shapes — the `grindCheckCmd` wrapper, or nix building in a sandbox it constructs itself), the gate/facts drift fence picks its needle by check shape rather than always `NE.last`, `testsGrindTail` names `flake-check`, one discipline needle went compile-lock → build-lock. `nix flake check` green, 253/253. Renders (binary off this tree): `cost grind-tests` blocked 4611686018427387991 (was …997), full 4611686018427388018 (was …024) — −6 both ways, which is the two exec leaves the gate lost times the fuel-3 repair loop; node counts 402→391 blocked, and `cost grind-live-view` blocked is 4611686018427387927, unmoved, which is what says the de-aliasing left that grind alone. `docs/grind-baseline/` deliberately NOT re-captured: those six files are the frozen pre-refactor record earlier bullets cite by byte-identity, and grind-paradox's pair already sits off it by the same convention. STILL OWED: the review-audit pass over this change is running; address its findings, then the first paid grind-tests run on a real non-operation checkout.

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
- FIFTH PASS (the operator session's own fix-all subagent, reconciling on
  `32a0c28` in worktree `wg-fix5-reconcile` as designated sole writer; the
  verified branch is handed to the operator for review — nothing here touches
  master). What it changed, and why:
  - AtChange audit-report exclusion, third and final shape: the fourth pass's
    claims-scoped clause is REPLACED by a call-site parameter. The account
    reaching grind-tests' review pass is the FIXER's closing summary, which
    never claims the synthesis's report as its own output — so the
    claims-scoped clause was dead at the one call site that needed an
    exclusion, and the run's own report would again have polluted the fixer's
    review (or been reviewed in place of `no change to audit` after a no-op
    fix). Now: `preambleOf AtChange` carries NO exclusion (fenced from the
    negative side — a change whose only file is an audit report is audited by
    every generic consumer, which was the recovered seventh finding);
    `asReviewSubjectIgnoring` names the run's own artifact paths, and
    grind-tests passes `auditReportDir` — one binding shared with the
    synthesis brief's report path, so the writer and the excluder cannot name
    different directories. Golden re-recorded from the code; both directions
    fenced ("the change orientation carries the no-change-to-audit clause and
    no exclusion", "asReviewSubjectIgnoring names the run's own artifacts
    above the generic frame").
  - The shipped-spec fence now covers all three grinds: `grindTestsSpec` and
    `grindParadoxSpec` hoisted to named bindings the workflows consume, with
    `grindTestsRule`/`paradoxRule` derived through `gsFacts` like
    grind-live-view's, and an all-fields equality case folding over both —
    the same quiet-inline-rebuild hole the live-view fence closed.
  - STE red trials, re-run by this pass with the evidence captured: planting
    `robust` in commands/grind-tests.md failed checks.ste-prompts with
    "ste-gate: FAILED / commands/grind-tests.md: slop_word x1"; the same word
    in commands/grind-live-view.md failed with "commands/grind-live-view.md:
    slop_word x1"; both reverted byte-exactly (git checkout), after which
    "ste-gate: 69 prompt files clean on latin_abbrev, contraction, slop_word"
    (the linter self-test ran first: 12 violations in the slop fixture, 0 in
    the clean one).
  - Verified on this tree: nix flake check green; 233/233 in BOTH roster
    modes; `cost` positive for all three grinds; `plan grind-live-view`
    carries the `exec vitest` leaf; each grind's plan carries exactly one
    fuel-1 stop node. grind-paradox plan+cost diffed against a
    SHA256-guarded copy of the step-1 baseline: the delta is EXACTLY the
    stop node (`loop Fuel 1` over `pure-adapter`/`id`, plus the one `seq`
    its insertion re-brackets) and the skeleton-count line (103 -> 107);
    worst case and dominating bound identical, every leaf identical.
  - Baseline bookkeeping: the step-1 `plan-grind-tests.txt` capture NEVER
    matched 7edd211 — it shows the second fixer's loop at the unbounded
    sentinel where the shipped `Just 12` renders `fuelMax = 12` — so that
    half of the baseline was stale before any stop node existed. Fresh
    captures for BOTH mix grinds (plan+cost) were re-recorded from this
    reconciled tree into /tmp/grind-baseline; the paradox pair is untouched
    (mtimes 02:21, sums match the operator's guard) and stays the step-1
    record, with the stop-node delta above as its documented offset.
  - Arbitration record, final: the operator first ruled the stop leaf and
    `spreadPinned`/`gsPins` stripped (54f650d's conservative line, protecting
    the baseline identity), then reversed on the committed evidence — the
    stop is red-trialed, fenced and disclosed, the baseline break is a
    recorded deliberate decision, and the grind-tests half of the protected
    baseline was stale anyway. Both stay. The fourth pass's AtChange bullet
    above is the one item that pass got wrong, superseded here.
- SIXTH PASS (the consolidated review of the fifth pass's commits, one fix-all
  leaf). What it changed:
  - The own-artifacts exclusion narrowed from a directory to the run's report
    PREFIX: `asReviewSubjectIgnoring` takes one `Text` prefix (the `NonEmpty`
    was one caller passing a singleton) and grind-tests passes
    `auditReportDir <> grindTestsName <> "-"` — exactly the dated file its
    synthesis writes. A fixer's edit to a PRE-EXISTING report under
    `docs/audits/` is part of the change again, and the frame says so
    outright. The fifth pass's directory-wide bullet above is superseded on
    that one point; the call-site-parameter shape stands.
  - The wiring is fenced where it lives: a leaf-prompt traversal over the
    SHIPPED `grindTests` flow (exec leaves answered green) asserts the
    rendered review-pass prompt carries the frame at that prefix — reverting
    the `dimap'` to plain `asReviewSubject` is red now (trialed) — and a
    companion case asserts each grind's leaves render `gsFacts`, closing the
    inline-spec-rebuild hole the field-equality fences cannot see.
  - Acceptance recorded for the b76abc7 agent-functor bump's OTHER behavior
    change, which the arithmetic bullet above did not disclose: `resume`'s
    run argument is now optional and defaults to the newest unarchived run
    (explicit-run resume unchanged; nothing in this tree calls resume, so
    nothing here consumes the default). Accepted as shipped.
  - The step-1/step-13 baseline captures left `/tmp`: committed under
    `docs/grind-baseline/` (all six plan/cost files, bytes identical to the
    `/tmp/grind-baseline/` copies every earlier bullet cites). The
    `/tmp/grind-residual/` renders stay ephemeral on purpose — they are
    re-derivable from any checkout of the committed tree, unlike the
    baseline, which is the diff anchor.

## Adopted from upstream by the 288→307 bump (90fde09) — operator-owned

Three behaviours of `agent-functor` that commit 90fde09 (`5eec06c`→`1fca34f`,
revCount 288→307) brings into every incite run. **None is a defect introduced
by incite** — nothing in this repository changed but `flake.lock` and one
haddock. They are recorded here rather than fixed because each needs a change
in `/home/isaac/_/agent-functor/master` **plus a push**, and push from this
machine is blocked on a smartcard PIN. Owned by the operator.

- **MEDIUM — the empty-turn retry can re-run side effects.** Upstream
  `49f1d20`, `src/Agent/Run.hs:1724`
  (`turnArtifact =<< withEmptyRetry onChunk (modedOutcome (cnLabel conn) Edit
  Nothing <$> promptOn sess onChunk brief)`), policy at
  `src/Agent/Run.hs:3934` `withEmptyRetry` and `:3951` `modedOutcome`.
  Mechanism: a turn is classified `TurnEmpty` on `T.null (T.strip (out t))` —
  **message text alone**. No check for tool activity in the turn. On
  `TurnEmpty` the whole turn is re-issued with the same brief on the same
  session. Concrete failure: incite's world-acting workflows (`shipFeature`,
  `retro`) have the agent run its own `git`/`gh` inside those turns, so a turn
  that commits or pushes and then ends with a bare `end_turn` and no text is
  read as "cleanly empty" and re-prompted — duplicate commits, a second
  `gh pr create`. Before the bump this halted and an operator decided whether
  to `resume`; now the re-execution is silent apart from one parenthetical
  stream line (`asking once more before giving up`). Fix shape: gate the retry
  on a turn that also did no tool work, not on empty text.
- **MEDIUM — a mid-session IOException now loses its label.** Upstream
  `96800fe`, `src/Agent/Acp/Subprocess.hs:75`
  (``bracket (startProcess pc `catch` launchFailed) stopProcess launched``).
  Narrowing the `IOException` catch to the spawn is correct for the
  misdiagnosis it fixes, but the exception that motivated it — an operator-gate
  EOF — is mid-session, so it now propagates unlabelled to the top-level
  handler: `src/Agent/Run.hs:1114`
  `outcomeStatus (Left e) = (RG.Failed (haltReason e), Nothing)` records
  `Failed "<stdin>: hGetLine: end of file"` and drops the run graph
  (`Nothing`). The old message misdiagnosed the cause but carried
  `claude-agent/fable:`; the new one is honest and names neither backend nor
  leaf — in a 21-leaf three-backend `panelAcross` fan-out whose siblings the
  throw cancels. Fix shape: keep the narrowed launch handler and add a
  session-scoped handler that re-labels with `cnLabel`.
- **LOW — the retry adds load exactly when the backend is unwell.** Upstream
  `49f1d20` again. The flake it answers (opencode returning `end_turn` with
  nothing) correlates with backend distress, and a `parList` panel where every
  leaf gains one extra prompt at that moment is extra load on a backend that
  may already be rate-limited — the 429-into-aborted-run mode `AGENTS.md`
  warns about for concurrency. Bounded to one retry per leaf, so tail-case
  only, but it can turn one lost lens into a lost run. Fix shape: back the
  retry off, or make it not fire when a sibling has already retried.

# Bump + context-overflow plan — handoff

Second plan in this file, started 2026-08-14. Two parts: **A** lands the
agent-functor lock bump and records why opencode stays on `defaultModel`;
**B** gives the repo something to do when a payload will not fit a context
window. Part A is done. **Part B is not started.**

## Task list

- [x] 1. Re-confirm the ground facts. DONE — tree was exactly as the plan
  recorded it (`d1ebfe4`, only `flake.lock` dirty at 5eec06c→1fca34f), so no
  re-derivation was needed. Re-checked again after the tree moved to 308: the
  facts below still hold.
- [x] 2. Haddock on `opencodeBackendFor`'s `False` clause recording that
  `defaultModel` is a decision taken WITH `opencodeModel` available. DONE in
  `c23e241`, then **corrected in `c027f4c`** after the audit — see below. The
  plan said the backend advertises 74 models; live `doctor` says **77**, and
  upstream's own haddock still says 74 at `src/Agent/Backend.hs:389`. Both were
  true when written; the number is install-specific and nothing gates it.
- [x] 3. `nix flake check`. DONE, exit 0. Reported per attribute in `9a256a6`'s
  body, not as one word: `checks.unit-test` BUILT and ran; `ste-prompts` was
  previously built; the package and devShell attributes say `(build skipped)`
  — Determinate Nix 3.22.0 evaluates but does not build them under flake check,
  so their ticks are NOT evidence they build.
- [x] 4. Suite in blocked roster mode. DONE. Note the plan assumed
  `BLOCK_OPENCODE` was set on this machine; **it is unset in the shell**, and
  was passed inline (`BLOCK_OPENCODE=1 …`) for the blocked runs.
- [x] 5. Commit lock + haddock. DONE — `c23e241`.
- [x] 6. Post-commit audit + one fix pass. DONE — see below.
- [~] 7. **Compaction on `partitionReview`/`boundedSplit`.** CODE COMPLETE AND
  GREEN IN THE WORKING TREE, **STILL NOT COMMITTED** — the commit was declined
  (see "Step 7 verified and fix-passed" below). The implementation was not
  written by this session; the goldens, the `goldensRead` fix and every check
  below were. Read "Another writer owns `Review.hs` and `Spec.hs`" before
  touching either file.
- [ ] 8. **`--without-backend` + `passMainWith`, upstream.** NOT STARTED.
- [x] 9. **Capture live `usage_update` payloads.** DONE as a design question,
  and the answer **refutes the plan's premise**: a payload DOES carry a
  denominator. See "Step 9 answered" below. What is still owed is a captured
  wire sample for codex and opencode — not needed to unblock step 10 on
  claude-agent.
- [ ] 10. **Escalation target on the scope, upstream.** NOT STARTED, but now
  UNBLOCKED for claude-agent by step 9's answer.

## Handoff notes

- Three commits, oldest first:
  - `c23e241` — the 288→307 bump (`5eec06c`→`1fca34f`) plus the step-2 haddock.
  - `c027f4c` — the audit fix pass. Not itself audited, per the loop's rule.
  - `9a256a6` — the 307→308 bump (`1fca34f`→`9cec91d`, upstream "yolo"),
    observability only: `Agent.Tui.Theme`, `otherToolLines` so a non-shell /
    non-read / non-edit tool call's result reaches the live console, and
    highlight/markdown changes. **This bump is NOT part of the plan** — it
    appeared in the tree mid-session and was committed with its reason recorded
    rather than folded silently into another commit, per the convention the
    267→272 note above set.
- **Closing counts, at `9a256a6`:**
  - `nix flake check` — exit 0, with the per-attribute qualifiers above.
  - `BLOCK_OPENCODE=1 nix develop -c cabal test` — **297 tests, 0 failures**.
  - `nix develop -c cabal test` — **297 tests, 0 failures**.
  - 295 → 297 is the two fences step 6 added. Both roster modes give the same
    count because the roster-dependent cases assert the roster they are in.
- **`.agent-functor/` is gitignored and the tree does not carry it.** It holds
  this session's `review-lite` run-1 transcript and the **25 completed
  `@opencode` leaf records** that `Incite.Backend`'s haddock cites as its
  evidence for "opencode's default resolves and its turns complete". A fresh
  clone has neither, so that haddock sentence is not re-checkable from the tree
  alone — which is why it now names the path it argues from.
- **What the audit caught, because the pattern is the lesson.** Every finding
  was prose claiming more than its evidence, none was a code defect (the diff
  was comment lines):
  - two false statements about where the upstream range lands (`96800fe` is in
    `Agent/Acp/Subprocess.hs`, not `Agent/Run.hs`; `662c17b` is library code
    incite consumes, not the "mutation tooling" the message swept it into);
  - `nix flake check` reported as "all packages" green off ticks that say
    `(build skipped)`;
  - two haddock overreaches quantified across machines nobody had read.
  The commit messages of `c23e241` and `9a256a6` were amended to state what the
  tools actually printed. **Do not report a `(build skipped)` as a build.**
- **Both new fences were red-trialled**, not assumed: reinstating "every
  opencode machine" fails `test/Spec.hs:3651`; weakening the droid header
  sentence fails `test/Spec.hs:5384`. A fence over prose is worth nothing until
  it has been seen to fail.

## Part B — what a successor needs before starting

Ground facts, re-verified at lock 308 unless noted:

- **No context-window tracking exists upstream.** `Capabilities` records
  `capModels`, `capModelSupport`, `capLoadSession`, `capHonorsClientFs` — no
  window size. `Cost.hs` costs leaves and turns, never tokens.
- **`usage_update` is still discarded**, `src/Agent/Acp/Protocol.hs:701`
  ("token bookkeeping; pure noise in the console") — the line moved 700→701 in
  the 308 bump but the behaviour did not. **The premise that followed this in
  earlier drafts — "a bare `totalTokens` with no denominator" — is WRONG; see
  "Step 9 answered" below.**
- **`partitionReview`, `boundedSplit`, `reviewScales`, `joinWindows`,
  `chunksOf`** all exist at `src/Agent/Flow/Combinators.hs:185-222`, and
  `Agent.Bounds` has `Coarsen | FailWidth | Sample`. `boundedSplit` under
  `Coarsen` re-partitions LARGER with no content dropped. incite references
  none of them — `partitionReview split bound name brief reduce` is the whole
  of step 7's fold: split into ≤bound chunks, prompt each, reduce.
- **`BLOCK_OPENCODE` has never existed upstream** — it is incite-local, an
  `unsafePerformIO` CAF at `workflows/Incite/Backend.hs`. Step 8 deletes it.
  There are **53 references** to it across `test/Spec.hs` (31),
  `workflows/Incite/Backend.hs` (14), `docs/workflows.md` (6), `HANDOFF.md` and
  `workflows/Incite/Review.hs` (1 each) — the plan said ~25, so budget for
  twice that.
- **The bare-`Bool` signatures** on `backendsFor`, `opencodeBackendFor` and
  `blockOpencode` are a standing hit under the local Haskell addendum
  (boolean blindness). Deliberately left alone: step 8 removes the parameter
  entirely, and fixing it first would only collide.
- **Live `doctor` on this machine**: `claude-agent` has `opus[1m]` and
  `claude-fable-5[1m]`, so `fable5` already resolves to a 1M model; `codex` has
  20 models and **no 1M sibling to escalate to**; `opencode` is the only
  non-claude 1M home (`google/gemini-3.1-pro-preview`, `google/gemini-3.7-flash`,
  `xai/grok-4.6`); `droid` is not installed (`execvp: does not exist`).

**The blocker on steps 8 and 10**: both land in
`/home/isaac/_/agent-functor/master`, where push is blocked on a smartcard PIN.
An agent can author those commits but cannot push them or re-lock incite
against them, so each ends handed to the operator, with the matching lock bump
a separate commit afterwards. Step 7 is the only Part B item that needs no
upstream change — start there.

**One decision for the operator, which step 7 must not settle in code**:
compacting for uniformity drags a whole panel down to the smallest window in
the roster, so a large diff pulls a 1M `fable5` down to codex's window. A
three-backend panel over a compaction is not obviously better than a
two-backend panel at full fidelity. Ask; do not let the code choose silently.

## Step 9 answered — a live `usage_update` DOES carry a denominator

Session of 2026-08-14. **This refutes the premise steps 9 and 10 were written
on.** The plan assumed a payload is a bare `totalTokens` with nothing to divide
by, so a context-fraction could only ever be estimated. It is not.

Read off the ACP SDK schema that ships inside the adapter incite actually runs
for `claude-agent` — `claude-agent-acp` 0.64.0. Re-find it after any bump with:

```
grep -rl usage_update "$(dirname "$(readlink -f "$(which claude-agent-acp)")")"/../lib/node_modules
# schema:  .../@agentclientprotocol/sdk/schema/schema.json
# typings: .../@agentclientprotocol/sdk/dist/schema/types.gen.d.ts
```

The `SessionUpdate` union carries a `usage_update` variant described **"Context
window and cost update for the session."**, and its payload is:

```
UsageUpdate = { used: uint64   -- "Tokens currently in context."
              , size: uint64   -- "Total context window size in tokens."
              , cost?: Cost|null  -- "Cumulative session cost (optional)."
              }
required: ["used", "size"]
```

`used` and `size` are **both mandatory** (`"required": ["used", "size"]` in
`schema.json`); only `cost` is optional. So the live context fraction is
`used / size`, exact, per session, with no estimation and no model table to
keep current — which is precisely the input step 10's escalation target needs.

**What is NOT established, and do not write it down as if it were:**

- **No captured wire sample exists**, here or anywhere in `.agent-functor/`.
  It cannot: upstream drops the notification at `Protocol.hs:701` before
  anything writes it, so the run store has never held one. The evidence above
  is the protocol contract, which is authoritative for field names, types and
  required-ness — it is not a recording.
- **Whether `codex-acp` and `opencode` emit `usage_update` at all is unknown.**
  Searching `codex-acp` 0.13.0's vendor-staging tree
  (`/nix/store/165mwgzy…-codex-acp-0.13.0-vendor-staging`) finds `UsageUpdate`
  only in codex's OWN app-server SDK (`sdk/python/src/codex_app_server/…`),
  a different protocol, and no ACP `agent-client-protocol` crate carrying the
  variant. That is suggestive, **not** conclusive: a vendor-staging tree is not
  the built binary. Settle it by capturing the wire, not by grepping again.

**Where the wrong premise came from, so nobody re-litigates it.** `totalTokens`
is not a field the ACP schema has anywhere. It appears in exactly three places,
all of them **upstream's own hand-written fixtures**:

```
test/Agent/McpSpec.hs:588           captureUpdate app (OtherUpdate "usage_update" (object ["totalTokens" .= (7 :: Int)]))
test/Agent/Acp/ProtocolSpec.hs:539  summariseUpdate (OtherUpdate "usage_update" (object ["totalTokens" .= (99 :: Int)])) `shouldBe` Nothing
test/Agent/Acp/ProtocolSpec.hs:583  transcriptUpdate (OtherUpdate "usage_update" (object ["totalTokens" .= (5 :: Int)])) `shouldBe` Nothing
```

Those fixtures were read as if they were captured samples. They are not — they
invent a field name for a payload whose schema nobody had opened. And they are
**unfalsifiable**: all three assert `Nothing`, which `summariseUpdate` and
`transcriptUpdate` return for the `usage_update` tag whatever the object holds,
so the fixtures would still pass carrying any field name at all. Do not treat a
fixture in that file as evidence of a wire shape.

**Consequence for step 10, and it is smaller than the plan implies.** Upstream
already parses the notification into `OtherUpdate "usage_update" obj` with the
raw JSON object in hand at the discard site (`Protocol.hs:701`) — there is no
typed decoder to design around, just a discarded `obj` that already contains
`used` and `size`. Step 10 is a typed decode of two mandatory integers plus
somewhere to put them, not a protocol overhaul. Its design is unblocked on
claude-agent and only on claude-agent. A scope-level escalation keyed on `used / size` is exact where
the notification arrives and silent where it does not, so it needs a stated
fallback for a backend that never sends one — do not assume roster-wide cover.

## Another writer owns `Review.hs` and `Spec.hs` — read this before editing them

Session of 2026-08-14, and it cost this session its step-7 work. Observed, in
order:

1. `git status` at session start: **clean**, at `25fc32f`.
2. Partway in, `test/Spec.hs` and `workflows/Incite/Review.hs` held **~378
   uncommitted lines** implementing step 7 as a general `Payload`/`compacted`
   combinator over `partitionReview` — with haddocks, a `compactionTests`
   group, and a deliberate decision NOT to wire it into any shipped tier
   (which respects the operator decision recorded above). **This session did
   not write any of it.**
3. `flake.lock` moved **308 → 309** (`9cec91d` → `ca258f6`) on its own, with no
   action from this session — the same way 308 arrived mid-session before it,
   and it moved again to **310** (`e4aedca`) two minutes after the watch below
   ended. See the next section.
4. This session made one 4-line export edit to `Review.hs`. **It was reverted by
   the other writer**, confirmed by `grep` finding none of the four names in
   either file afterwards.

So edits to those two files may be silently discarded. The prior stash entries
say this is not new — `git stash list` still holds two, both labelled
`UNSOLICITED: … added by an unsandboxed review-lite/review-docs agent session`.

**What a successor must do before resuming step 7:**

- Do **not** `git commit -a`. Commit by explicit pathspec, or you will commit
  another agent's in-flight work under your own message.
- Establish who the writer is and stop it, or take the work into a worktree of
  your own. `ps aux | grep agent-functor` during this session showed a live
  `agent-functor run ship-feature` (PID 1905258), but its `--capture-context`
  path pointed at `/home/isaac/_/flake.engineering/lanes-matic/`, a different
  repository — so it was **not** identified as the writer. Nothing here proves
  what wrote those lines.
- The arrived step-7 code was **unverified and incomplete** when that was
  written. It has since been compiled, completed and run green — see the next
  section. It was still not this session's code, and it is still uncommitted.

## Step 7 verified and fix-passed, still uncommitted — 2026-08-14

**State.** HEAD is still `ca95eee`. Nothing from step 7 is committed. The
working tree holds `workflows/Incite/Review.hs`, `test/Spec.hs` (modified), the
two goldens (staged `A `), and `flake.lock` (modified). The implementation
arrived from another writer; the goldens, the `goldensRead` fix and the fix
pass below are this repo's own work.

**Lock.** `flake.lock` is at agent-functor **310 / `e4aedca`**, not the 309 /
`ca258f6` an earlier draft of this section recorded — the other writer re-locked
at `14:01:46`, after the fingerprint watch that had been reported as
"quiescent" ended at `13:59:39`. That watch proved a quiet ten minutes, not a
stopped writer. The `309 → 310` delta was read before anything was measured
against it: `Agent.Acp.Protocol` gains a cmark-based `unfence`/`consoleBodyLines`
so a tool result's markdown fence never reaches the console as literal
backticks, plus `Agent.Tui.{App,Highlight,Theme}` and their specs. No change to
any API incite's flows call.

**Counts, re-measured on the tree as it stands (lock 310, fix pass applied):**

- `nix develop -c cabal run incite-test` — **317 tests, 0 failures**.
- `BLOCK_OPENCODE=1 nix develop -c cabal run incite-test` — **317, 0**.
- `nix flake check` — **exit 0**; `checks.unit-test` BUILT and ran. The package
  and devShell attributes say `(build skipped)` and are NOT evidence they build.
- 297 → 317 is the arrived `compaction` group (14) plus this pass's six.

**The fix pass (five review findings, all in the compaction code):**

1. `splitFor` cut diffs with `T.lines`, which drops a trailing newline — and
   every real `git show` ends in one. Both kinds now cut with `T.splitOn "\n"`,
   the exact inverse of the `T.intercalate "\n"` that upstream's `Coarsen` uses
   to merge units back, so the reassembly law holds for every input rather than
   only for a sample built without a trailing newline.
2. `splitFor ProsePayload` cut on the blank line, so a JSONL transcript or a log
   — no blank line anywhere — yielded ONE unit, and `Coarsen` only ever merges.
   The single leaf would have been handed the whole oversized artifact the
   combinator exists to avoid handing anyone. Prose now cuts at the line.
3. Nothing checked whether a diff leaf obeyed "keep it verbatim". The original
   now rides an `Id` branch past the fan and `verbatimCheck` counts, in the
   reduce, how many changed lines came back character for character. No leaf is
   sent the original; the count is mechanical, not the model's account of itself.
4. `compactionBanner` carried a local `tshowInt`, duplicating the module's
   `count`. Deleted.
5. `Payload` and `Subject` had bare deriving clauses; both are `deriving stock`.

**Two findings from the same review were rejected, with reasons, so nobody
re-raises them cold.** (a) "A body line beginning `diff --git ` splits a file
mid-hunk" — it cannot: every body line in a unified diff carries a ` `, `+` or
`-` prefix, so a column-zero `diff --git ` is always a real file header. The
finding's own example, `+diff --git a/tests/x.patch …`, does not match the
prefix test it claims to trip. (b) "Delete the whole compaction API, it has no
shipped caller" — the absence of a caller is the recorded operator decision
(compacting for uniformity drags a panel down to the smallest window in the
roster), not an oversight; it is stated in `compacted`'s haddock. Deleting the
step the task list asks for is not a simplification of it.

**Recording the goldens.** There is no re-record harness — goldens are files on
disk, and that repl invocation IS the procedure:

```
nix develop -c cabal repl lib:incite-workflows -v0
TIO.writeFile "test/golden/compaction-diff.txt"  (promptText (compactionBrief DiffPayload  "<<PART>>"))
TIO.writeFile "test/golden/compaction-prose.txt" (promptText (compactionBrief ProsePayload "<<PART>>"))
```

682 and 480 bytes; unchanged by the fix pass, since no brief was reworded. Both
were red-trialled (append a byte → `the briefs are byte-for-byte the recorded
ones` fails; revert → OK, md5 `fa54b7e0007145402226cc4db2f85b42` and
`8db8b506867898e88c35ffed8f14d133`).

**A trap worth the paragraph, because it cost a check cycle.** `cabal test`
reads the working directory; `nix flake check` builds from a source derivation
carrying **git-tracked files only**. With the goldens written but untracked,
`cabal test` was green while `nix flake check` failed both golden fences. `git
add` fixed it. A new golden is invisible to the sandbox until it is staged.
The same rule caught gap 2 of the arrival: the arrived code fenced its goldens
in its own `compactionGoldens` but never added them to `goldensRead`, which the
global `every golden on disk is one this suite fences` case then failed.
`goldensRead` now folds in `map snd compactionGoldens` rather than spelling the
paths a second time.

**Why it is not committed.** Two commit attempts were made in the earlier pass
and both were refused — one blocked by the permission classifier, one declined
by the operator. Neither was retried, and this pass did not retry either. If the
operator wants it committed: `flake.lock` first and alone (308 → 310), then step
7 as one commit over `workflows/Incite/Review.hs`, `test/Spec.hs` and the two
goldens — **by explicit pathspec, never `git commit -a`**, because the tree is
shared with a live writer. The message must say the implementation arrived from
another writer and that this repo verified, completed and fix-passed it rather
than authored it.

**No post-commit audit ran, because no commit landed.** The audit beat is per
commit; there is nothing for it to report on.
