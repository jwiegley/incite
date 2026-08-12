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
- [ ] 9. `prompts/grind/live-view-facts.md` + 11 lens bodies + bindings; severity-word Spec case.
- [ ] 10. Define grind-live-view; ranking-clause seam Spec case.
- [ ] 11. Register + fence grind-live-view; docs pass; identifier grep with zero misses.
- [ ] 12. Convert both commands to launchers, register in flake.nix stePromptSrc; STE red trials. Keep JS engines.
- [ ] 13. Acceptance: flake check, offline plan/cost renders, list, re-run step-3 dry run, paid runs (live-view first), then delete JS engines.

## Handoff notes

- Session started 2026-08-12. No prior progress; this doc created at step 1.
- Step 1 DONE: `nix flake check` green; baseline captures in `/tmp/grind-baseline/`
  (plan-grind-paradox.txt, cost-grind-paradox.txt) — NOT committed. This machine
  has `BLOCK_OPENCODE` set, so local renders show the blocked pairing; the nix
  test sandbox sees the full roster.
- **BLOCKER for steps 3 and 13**: no operation checkout (Elixir/Phoenix app,
  OTP app `operation`) exists on this machine — searched `/home/ishapira`
  exhaustively (no `mix.exs`, no `lib/operation_web`, no `domain/`, no `fstar/`
  anywhere). No Paradox checkout either. Consequences:
  - Step 3's probe and dry run cannot execute here. Decision made on recorded
    evidence instead: `commands/grind-live-view.md`'s own final gate runs
    `nix develop -c mix compile --warnings-as-errors` (with a fallback clause),
    so the target project has a nix dev shell; the paradox precedent
    (`devShell`, Spec fence at Spec.hs:1483) uses
    `nix develop --command bash -c <cmd>`. `grindCheckCmd` therefore takes the
    nix-develop branch, bash -c innermost. THE DRY RUN IS STILL OWED: before
    any paid run, execute every rendered argv of both grinds verbatim in the
    operation checkout and reopen this decision if any fails
    environment-shaped.
  - Step 13's paid runs are deferred to a machine with the operation checkout.
    Per step 12's own rule the JS engines stay until those runs pass; they are
    preserved as `commands/grind-tests-engine.md` and
    `commands/grind-live-view-engine.md` (unregistered) once step 12 lands.
- Step 2 denotations (each law and its named check):
  - `reviewAuditFlow :: Flow Text Text` ≡ the flow `reviewAudit` runs today:
    `lensesOf OfChange`, regroups over the FULL panel (not
    `panelAcross [claudeAgentBackend]` — that is `reviewHeavyFlow`'s
    narrowing), then synthesis. Pinned by the step-4 render diff and the docs
    84/57 leaf-count row.
  - `grindGrantFor :: [(LeafName, NonEmpty Text)] -> Grant` grants by
    head-glob per Feature.hs:555 (`NE.head cmd <> "*"` plus `date*`/`mkdir*`,
    denies the deny-list trio). NOT the stricter rendered-check-lines reading —
    that trips Spec.hs:1460-1506. Law: `grindGrantFor grindChecks ≡ grindGrant`,
    pinned by the existing grindGrant fences; step 5 pins the generalization.
  - `grindSynthesisOver` already existed (Review.hs:1172) with
    `grindSynthesis grindName` as its byte-identical specialization; pinned by
    grindPanelTests and step 5.
  - `grindFlow` = shared grind prefix (facts prepend → spread panel →
    synthesis → orchestrated fixer). Pinned by the unchanged grindParadox
    fences and the step-4 render diff.
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
- Post-commit audit per `post-commit-audit` skill after each commit; findings
  fixed via one `fix-all` subagent; fix commits not re-audited.
