# Workflows

Run workflows from the repository root:

```bash
nix run .#agent-functor -- list
nix run .#agent-functor -- plan <name>
nix run .#agent-functor -- cost <name>
nix run .#agent-functor -- run <name> -i "request text"
```

`plan` and `cost` are offline. `run` drives the configured ACP (Agent Client
Protocol — the interface a backend's own CLI speaks to accept prompts and
stream results) backend. On a tty it uses the live TUI; when piped it prints
an inline transcript and asks through stdin at blocking points.

## Exposed inventory

Only workflows listed in `workflows/Main.hs` are exposed. "SimpleEnglish"
below is ASD-STE100 Simplified Technical English (see
[Testing and packaging](testing-and-packaging.md#ste-checks)) — the aerospace
controlled-language rule set this repo applies to its own procedural prompt
text.

| Workflow | Kind | Shape |
|---|---|---|
| `plan-feature` | prompt-only | explore with four stances, plan, then edit the plan through six code-oriented lenses |
| `ship-feature` | world-acting | `plan-feature`, steer, orchestrated code implementation, `reviewHeavyFlow`, remediation, retrospective, human gate, PR |
| `ship-docs` | world-acting | explore, plan, documentation-strategy and SimpleEnglish plan edits, steer, orchestrated documentation, `reviewDocsFlow`, remediation |
| `grind-paradox` | world-acting | 14-lens whole-tree audit spread one backend per lens, synthesis written to a dated report under `docs/audits/`, orchestrated fixer, then a real-exit-code green gate with `repairFuel` trips |
| `fess-audit` | prompt-only | audits a worker's captured transcript on claude-agent, pinned so the rubric cannot inherit a backend `admits` forbids |
| `retro` | prompt-only | retrospective over a captured transcript: sentiment, went-well, went-wrong, then synthesis |
| `review-lite` | prompt-only | five per-commit reviewers (correctness on claude-agent, fess on claude-agent, complexity on codex, ponytail on codex, qa on opencode), pure fold reduction |
| `review-heavy` | prompt-only | full-diff review by seven lenses on three backends, two regrouped views on claude-agent, then synthesis |
| `review-audit` | prompt-only | eight-lens panel over full, logical-unit, and ideal-sequence views, then synthesis |
| `review-docs` | prompt-only | documentation panel: accuracy, completeness, structure, slop, ponytail, each on three backends except accuracy (the fess rubric, never on codex), then synthesis |
| `prompt-lint` | prompt-only | one SimpleEnglish CHECK-mode pass over procedural prompt text |

`plannerAudit` is defined but not exposed. It is a read-only planner-design audit
over `workflows/`, not a general review tier.

## Workflow constructors

Use the constructor that matches the contract:

| Constructor | Input | World access |
|---|---|---|
| `workflow` | baked-in input | no grant |
| `workflowReq` | caller must provide input | no grant |
| `workflowGReq` | caller must provide input | takes an `execGrant` whitelist |

## Blocking opencode

Some machines cannot reach the opencode backend. Set `BLOCK_OPENCODE` to any
non-empty value and no leaf runs there:

```bash
BLOCK_OPENCODE=1 nix run .#agent-functor -- run review-heavy -i "…"
```

An empty value counts as unset, so `BLOCK_OPENCODE= nix run …` turns it off for
one command. `Incite.Backend.blockOpencode` reads the variable once at process
start; `backendsFor` and `opencodeBackendFor` are pure functions of it.

The substitution replaces the roster **entry** — the name and the scope
together, never the scope alone. `admits` decides whether a backend may answer a
lens by reading its name, and the one pairing it refuses is the fess rubric on
codex. A scope swapped under the name `opencode` would keep that admission and
run the rubric on codex anyway.

Three things change, and all three are consequences of the machine having two
backends instead of three:

- **The panels get narrower.** The roster drops to `claude-agent` and `codex`
  rather than keeping a third slot holding codex twice. A duplicate is not
  cosmetic: `panelAcross` is a lens × backend cross-product, so every lens would
  get two identical `lens@codex` leaves — one model's opinion, paid for twice
  and ranked by the synthesis leaf as two findings. The leaf-count table above
  states what each tier costs either way.
- **The fess rubric always runs on claude.** With codex refused and opencode
  gone, `claude-agent` is the only backend left that admits it. Nothing
  special-cases this; it falls out of `admits`.
- **The explore fan-out loses one axis.** `contemplative` was the opencode
  stance and lands on codex beside `skeptic`, so `plan-feature` runs four
  stances across three distinct agents. Three is all there is: the other two
  stances already hold `claude-agent` and `claude-agent/fable`, so a collision
  is forced rather than chosen.

`ship-feature` and `ship-docs` use `workflowGReq` with `actingGrant`, currently
`execGrant ["nix*"]`. That grant gates `Agent.Op.Exec` leaves. The agent's own
tools, such as git or GitHub operations, are still mediated by the backend's tool
permission flow.

## Planning and acting

`Incite.Feature` splits the feature path into shared pieces:

- `explorePlan`: four read-only exploration stances — intrepid (the path),
  skeptic (the risks), contemplative (the design options), architect (the shape
  of the tree they all land in) — then the planner;
- `editPlan`: code-oriented plan lenses: ponytail, denotational, risk,
  verification, lookahead, SimpleEnglish. Unpinned, so they run on the run's
  own `--backend`, as `docsPlanLenses` does;
- `docsPlanLenses`: the plan lenses `ship-docs` uses — `docs-strategy` then
  `simple-english` — because the code lenses have no useful purchase on a prose
  plan;
- `orchestrate`: run a worker until its last non-empty line is not
  `WORK REMAINS`; `workerFuel` is `Nothing` by default (no ceiling), or
  `Just n` to cap at n trips after which the last summary yields to the
  review panel rather than aborting the run;
- `remediate`: fix ranked review findings under an artifact rule (`codeRule`,
  `docsRule`, or `paradoxRule`) plus a closing clause. The clause is what
  distinguishes a fixer that runs once (`closeWithChanges`) from one running
  under `orchestrate` (`fixerContinuation`, which splices `continueMarker`);
  with no clause the leaf is byte-for-byte what it was before the argument
  existed, and `test/Spec.hs` pins that against a golden recorded beforehand.

## Grinding a whole tree

`grind-paradox` is the same acting shape pointed at a source tree instead of a
change, and at another checkout instead of this one. Four things distinguish it.

- **`spread`, not `panel`.** One backend per lens, cycling, so 14 lenses cost 14
  leaves. A panel over the same lenses costs 42. Coverage rather than agreement:
  three models agreeing about a tree nobody changed is worth less than three
  more questions asked of it. The pairing is positional, so the order of
  `lensesOf OfTree` decides which model reads which lens, and `test/Spec.hs`
  asserts the shipped `lens@backend` leaf names rather than the lens order alone.
- **The facts arrive as a prepend, not as a default input.** `prompts/grind/paradox-facts.md`
  holds every path, build command and repair discipline; a `dimap'` puts it above
  whatever the caller passes. A `workflowG` default input would be *replaced* by
  a caller's text, which would drop the facts the moment somebody steered the
  run. The file opens with a probe that refuses when its paths do not resolve,
  because an audit that reads nothing and a clean tree both report no findings.
- **`grindGrant` is derived from `grindChecks`.** A grant and a check list are
  two statements of one fact. Written separately they drift, and the drift is
  silent in the direction that matters: an ungranted check is denied inside the
  run, the gate never reads a real exit code, and the artifact still carries a
  gate section. The `date` and `mkdir` entries are the synthesis leaf's, for the
  report write.
- **Each check carries its own toolchain.** `execStep` runs argv directly — no
  shell, no profile, no dev shell — so every entry in `grindChecks` opens with
  `nix develop --command`. A rehearsal is what settled this: run bare, Paradox's
  `test.sh` dies on `cabal: command not found`, and past that it builds a binary
  path out of `$GHC_VER` and `$PARADOX_VER`, which only its dev shell sets. The
  gate would have been red on every run for a reason no repair leaf could
  diagnose, and a gate that cannot go green is worse than none.
- **And the checks name targets the project actually has.** With the toolchain
  fixed, cabal rejected the next thing: `lib-tests` is not a suite in Paradox.
  The name was in the retired prompt, in that prompt's own facts block, and in
  the project's `CLAUDE.md` — wrong in all three, and copied forward faithfully
  each time. `cabal test` asks the package for its nine real suites instead, so
  the list has no tenth copy here to go stale.
- **The gate runs the checks itself.** `greenGate` is `verify` under `loopUntil`
  with a repair leaf on the failing branch, and `isRed` reads the `✗` lines
  `execStep` emits — real exit codes, not an agent's claim that it ran the suite.
  Each trip is fed an empty log rather than the previous trip's, because `verify`
  appends and `isRed` is a homomorphism: a stale marker would otherwise make
  every later verdict red. Exhaustion aborts, so a tree still failing after
  `repairFuel` trips fails the run instead of reporting success over a red build.

`workerFuel` (the fixer-loop ceiling) is `Nothing` by default — unbounded.
`repairFuel` (currently 3) bounds the gate. `cost` multiplies through both
loops rather than flattening them, so with the default unbounded fixer loop
the reported worst case is very large; set `workerFuel = Just n` for a finite
ceiling (at `Just 8`, the worst case is 32 leaf executions).

Nothing is committed. The product of a run is a dirty tree and a dated report,
for a person to read. That is why the command drives it with `sandbox=false`:
the dirty tree *is* the deliverable.

`sandbox=true` still works and is the right choice for a rehearsal, but know
what it costs on a compiler. The sandbox is a fresh `git worktree`, and
`dist-newstyle/` is not tracked, so the gate's build check starts cold — a full
compiler build inside an `Exec` leaf, and again for the test binaries, on every
run. In place, those checks reuse the checkout's existing artifacts and finish
in the time an incremental build takes.

The continuation contract is intentionally narrow. `decideContinue` looks only
at the last non-empty line, after stripping the small decoration alphabet tested
in `test/Spec.hs`. A summary that says "no work remains" in prose must not keep
the loop alive.

## Documentation workflow

`ship-docs` is not `ship-feature` with different nouns. It has different safety
properties:

- it edits the plan through `docs-strategy` then `simple-english`, and through
  none of the six code lenses `editPlan` runs;
- the writer and fixer both stand under `docsRule`;
- the docs panel reads documents against code through `asDocsSubject`;
- it stops after remediation;
- it does not open a PR.

The no-PR rule is deliberate. An unattended run can auto-answer gates, and a PR
is an external side effect. The documentation change lands in the working tree;
publishing it stays explicit.

## Review tiers and leaf counts

The counts below are prompt leaves, not tokens. `cost` reports leaf counts and
node bounds, not prompt size.

The second count is the same tier with `BLOCK_OPENCODE` set — see
[Blocking opencode](#blocking-opencode). A tier pinned leaf by leaf costs the
same either way; a tier that fans across the roster gets narrower.

| Tier | Leaves | Leaves, opencode blocked | What the cost buys |
|---|---:|---:|---|
| `review-lite` | 5 | 5 | cheap per-commit independence across correctness, fess, complexity, ponytail, and how the change fails |
| `review-heavy` | 38 | 31 | 21 full-diff reviewers, two regrouping leaves, 14 single-backend regrouped-view reviewers, and synthesis |
| `review-audit` | 75 | 51 | full 24-leaf panel over three views, with regrouping leaves and synthesis |
| `review-docs` | 15 | 10 | five documentation lenses across three backends, less the one pairing `admits` forbids, plus synthesis |
| `prompt-lint` | 1 | 1 | one grounded STE CHECK-mode report |

The regrouping leaves in `review-heavy` and `review-audit` are views, not
judges. They re-express a change as logical units or as an ideal sequence so the
same panel can see coupling that is invisible in the full diff.

## Captured transcripts

`fess-audit` and `retro` use `withCapturedTranscript`. When called through a
run's trigger endpoint, the worker's captured session becomes the workflow input
instead of the caller's text. Other workflows intentionally do not opt in:
`review-lite` must receive the diff it was handed, not a conversation log.

On a plain `agent-functor mcp` server, there is no captured transcript. Use
`review-lite`'s fess lens for diff-shaped honesty checks in that context.

