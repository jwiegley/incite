# AGENTS.md

Declarative AI agent configuration: prompts (rendered to `~/.claude`, `~/.codex`,
etc.) plus typed Haskell multi-agent workflows. Two halves, one Nix flake.

**Read `flake.nix` first.** Its `prompts` list is the authoritative inventory of
every prompt — count it, not the directories. The README is detailed and largely
accurate; this file covers the gotchas the README assumes you already know.

## The one critical invariant

**The cabal package is rooted at the repo root, not at `./workflows/`,** even
though the only Haskell source is `workflows/Main.hs`. This is deliberate:
`[promptFile|prompts/foo.md|]` checks the path at compile time against the
package root and resolves it at run time against the working directory, so those
two must be the same directory — the one you stand in when you run the binary.
**Always `nix run` / `cabal run` from the repo root.**

## Two lists that must stay in sync

Every directory that a `promptFile` splice can reach must appear in **both**:

1. `extra-source-files` in `incite-workflows.cabal`
2. The `fileset` union in `flake.nix` (under `mkWorkflowRunner`)

They are not cross-validated. A directory missing from the cabal list still
builds under nix and only breaks `cabal sdist` — a **quiet** failure. When you
add a new prompt directory, update both. Today both lists cover `workflows/`,
`prompts/`, `agents/`, `skills/`, plus `commands/fess.md` (which a workflow
splices in as a brief).

## Prompts are read at run time, not compiled in

A `[promptFile|…|]` quasiquote is a **compile-time existence check + run-time
read**. Consequences:

- Editing any `prompts/*.md`, `agents/*.md`, `skills/*.md`, or `commands/fess.md`
  takes effect on the next `run` with **no rebuild**.
- Prompt files are deliberately **not** recompilation dependencies, so
  deleting/renaming one is a *run-time* failure, not a build error.
- Each prompt body is read once per process; editing mid-run does nothing until
  the next run.

If a prompt path can't resolve, the binary dies listing every candidate it tried
(`$AGENT_FUNCTOR_PROMPTS/<path>`, `<cwd>/<path>`, the compile-time source dir).
Set `AGENT_FUNCTOR_PROMPTS` to run from elsewhere.

## cabal vs nix binary behave differently

A `cabal build` binary resolves prompts from **any** working directory (candidate
#3 is a live source tree). A `nix`-built binary only finds them from the repo
root (candidate #3 is a deleted `/build/...` path). **Test the way you deploy**
— nix is the deploy path here.

## Commands

```bash
nix build                                       # build both packages; result/ holds the prompt trees
nix run .#agent-functor -- list                 # list defined workflows
nix run .#agent-functor -- plan <name>          # offline: print the flow skeleton
nix run .#agent-functor -- cost <name>          # offline: worst-case leaf-execution count + node count
nix run .#agent-functor -- run <name> -i "..."  # drive an agent; live TUI on a tty, inline when piped
nix develop                                     # GHC + agent-functor library + cabal + HLS for editing workflows
nix develop -c cabal test                       # run the unit test suite (see "Tests" below)
```

`plan` and `cost` never touch an agent — safe to run anytime. `cost` reports
worst-case leaf executions and node count, **never tokens**; a leaf carrying 18 KB
of brief and a leaf carrying one line both count as 1. (See `codeReview` below.)

`run` flags: `--backend NAME` (default `claude-agent`), `-i/--input TEXT`
(prompts on tty if omitted), `--sandbox` (isolate world-acting runs in a
throwaway worktree; prompt-only flows ignore it), `--concurrency N` (fan-out
cap, default 6, `0` = unbounded).

## The `agent-functor` input — two landmines

`agent-functor` is the typed workflow library. In `flake.nix` it points at a
**local filesystem worktree** (`git+file:///home/isaac/_/agent-functor/master`),
on its **own pinned nixpkgs** (its Haskell deps need 24.11), so it deliberately
does **not** `follows` incite's unstable nixpkgs.

- This flake **will not evaluate on any machine** without that exact worktree
  checked out. No fallback, no remote.
- Keep it locked to a **committed** revision. Committing agent-functor before
  `nix flake update agent-functor` makes the relock just work; an uncommitted
  branch forces a non-reproducible `dirtyRev` NAR hash that breaks on the next
  edit. The rule is documented in the comment above the input.

## Prompts do double duty

`agents/` and `skills/` are each read by **two** consumers:

1. `agent-pm` renders them to `~/.claude/{agents,skills}/...`
2. The workflows splice them in verbatim as briefs (`codeReview`, `fixAll`,
   `fess`).

There is exactly one copy of each. Editing `agents/code-review.md` changes both
the deployed Claude agent **and** the workflow leaf that sends it. The bill is
real: `agents/code-review.md` is ~18 KB and every leaf using it sends the whole
thing — a workflow reading it costs materially more per turn than a one-line
brief. `workflows/Main.hs` calls this out at the binding.

## Adding things

**A prompt** (instructions / agent / command / skill): add an attrset to the
`prompts` list in `flake.nix`. Per-prompt knobs used here: `order`
(instructions only — concatenation order in `CLAUDE.md`), `model`, `mode`,
`argumentHint`, `extraFrontmatter` (temperature, tool denials, `agent =` binding,
skill `author`/`invocation`), and `degradation = "skip"` (drop on tools that lack
the native concept rather than degrading into a collision — only `code-review`
sets this today). Commit + rebuild. Done.

**A workflow**: define a `Workflow` in `workflows/Incite/Feature.hs` (request →
plan → PR) or `workflows/Incite/Review.hs` (the review and audit tiers), and add
it to the `workflows` inventory list in `workflows/Main.hs` — a workflow not in
that list is not exposed as a subcommand or MCP tool, no matter how well
defined. Use `workflow` (baked-in input), `workflowReq` (demands input), or
`workflowGReq` (acts on the world; the extra arg is the `execGrant` whitelist,
everything not listed is denied). Prompt bodies live in files under `prompts/`,
bound once in `Incite.Prompts` with `[promptFile|prompts/...|]`; a NEW prompt
directory also needs a glob in `incite-workflows.cabal`'s `extra-source-files`
and, to be STE-linted, a line in `flake.nix`'s `stePromptSrc` fileset.
`string-interpolate` is re-exported by agent-functor as `i` for `#{}` holes.

## Defined workflows

The `workflows` list in `workflows/Main.hs` is the inventory; this table follows
it.

| name | kind | notes |
|---|---|---|
| `plan-feature` | prompt-only | explore (3 stances) → plan → 6 lens edits. Touches nothing. |
| `ship-feature` | world-acting | the above, then implement in place under an orchestrator loop of up to 8 trips, the 21-reviewer panel, remediation, a human gate, and a PR. `execGrant` permits only `nix*`. |
| `fess-audit` | prompt-only | honesty audit of a worker's captured transcript; read-only on codex. The worker fires it over MCP after each commit. |
| `retro` | prompt-only | retrospective over a captured session: sentiment / went-well / went-wrong columns, then a `## next time` synthesis. |
| `review-lite` | prompt-only | a commit through 4 reviewers, one lens per backend, reduced by a pure fold; the per-commit beat. |
| `review-heavy` | prompt-only | a diff through 7 lenses on all 3 backends plus regroupings, then one synthesis; pre-PR. |
| `review-audit` | prompt-only | 8 lenses × 3 backends × 3 granularities — 75 leaves. Deliberate, never on a beat. |
| `prompt-lint` | prompt-only | ASD-STE100 check over this repo's own prompts, procedural passages only. |

World-acting runs leave `.agent-functor-worktree-*` / `.agent-functor-worker-*`
directories behind if killed mid-run; gitignored, safe to delete. The
`.agent-functor/` run-record store is also gitignored.

## Conventions

- **Git commits**: always use `--no-gpg-sign` (`git commit --no-gpg-sign -m "..."`).
  This rule is baked into the deployed `global-rules` instructions.
- **Coding style** (from `global-rules`): prefer purely functional, Haskell-style
  code regardless of language; immutable data, pure functions, leverage the type
  system. Avoid creating new modules when possible; reuse existing golden tests.
- **Orphan instance** build failures are fixed with `OPTIONS_GHC` to disable the
  warning — orphans are fine.
- **Tone** (deployed to agents, applies here too): non-plussed by default, combative
  is fine, curb the enthusiasm — no "Perfect!" / "You are absolutely right!".
- Commit messages are sentence-case, present-tense, one logical change each
  (e.g. `Relock agent-functor to master (2ac7a6e)`).

## Tests

A unit test suite (`test/Spec.hs`, tasty + HUnit) covers the pure logic that was
previously untestable because it was buried in `where` clauses:

- `decideContinue` and `continueMarker` — the orchestrator loop's continuation
  contract, stated from both sides: the decorations read through *and* the ones
  that must not be.
- `orient`, `preambleOf`, `preambleViolations` and the three named reframings
  (`asReviewSubject`, `asRetroSubject`, `asDocsSubject`) — their bytes recorded
  under `test/golden/`, with the golden table forced to cover the whole
  `Orientation` enumeration.
- `document` — the documentation worker's brief, round-tripped through
  `decideContinue`.
- `lensesOf` and `lensSetViolations` — review panel composition per `Subject`,
  lens names *and* lens bodies.
- The reorientations (`docsAccuracy`, `ponytailOfDocs`, `architectureOfChange`)
  against the upstream rubrics they splice.
- `promptLint` — the leaf text the shipped workflow actually sends, against
  `test/golden/prompt-lint-brief.txt`.
- Packaging — that `extra-source-files` carries every spliced prompt file and
  every golden the suite reads, which is the one defect class no other check in
  this repo can see (they all run in a git checkout).
- Backend structure.

The workflows themselves — the `Flow` values and combinators — remain under test
in the `agent-functor` library repo. The suite runs as
`checks.${system}.unit-test` in the flake; the dev shell includes `tasty` and
`tasty-hunit` so `cabal test` works too.

## What is *not* here

- No CI config in this repo — deployment flows through the consuming
  `nixos-dots` flake (`services.agent-pm` for the `isaac` user).
- Two prompt bodies live outside this repo: the `agentic-philosophy` instructions
  block and the `fstar-erlang-ell` command body, both read from the private
  `macha` input (`flake = false`, ssh-fetched).
