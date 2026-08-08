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
| `fess-audit` | prompt-only | audits a worker's captured transcript on codex |
| `retro` | prompt-only | retrospective over a captured transcript: sentiment, went-well, went-wrong, then synthesis |
| `review-lite` | prompt-only | five per-commit reviewers (correctness on claude-agent, fess, complexity and ponytail on codex, adversarial QA on opencode), pure fold reduction |
| `review-heavy` | prompt-only | full-diff review by seven lenses on three backends, two regrouped views on claude-agent, then synthesis |
| `review-audit` | prompt-only | eight-lens panel over full, logical-unit, and ideal-sequence views, then synthesis |
| `review-docs` | prompt-only | documentation panel: accuracy, completeness, structure, slop, ponytail, each on three backends, then synthesis |
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
  verification, lookahead, SimpleEnglish;
- `docsStrategyOfPlan` and `simpleEnglishLens`: the plan lenses `ship-docs` uses, because the code
  lenses have no useful purchase on a prose plan;
- `orchestrate`: run a worker until its last non-empty line is not
  `WORK REMAINS`, capped by `workerFuel`;
- `remediate`: fix ranked review findings under either `codeRule` or `docsRule`.

The continuation contract is intentionally narrow. `decideContinue` looks only
at the last non-empty line, after stripping the small decoration alphabet tested
in `test/Spec.hs`. A summary that says "no work remains" in prose must not keep
the loop alive.

## Documentation workflow

`ship-docs` is not `ship-feature` with different nouns. It has different safety
properties:

- it uses only the SimpleEnglish plan lens after planning;
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

| Tier | Leaves | What the cost buys |
|---|---:|---|
| `review-lite` | 5 | cheap per-commit independence across correctness, fess, complexity, ponytail, and how the change fails |
| `review-heavy` | 38 | 21 full-diff reviewers, two regrouping leaves, 14 single-backend regrouped-view reviewers, and synthesis |
| `review-audit` | 75 | full 24-leaf panel over three views, with regrouping leaves and synthesis |
| `review-docs` | 16 | five documentation lenses across three backends, plus synthesis |
| `prompt-lint` | 1 | one grounded STE CHECK-mode report |

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

