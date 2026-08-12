Grind the test suite: audit it with twelve lenses, fix every finding, review
the fix with the exhaustive panel, fix what the review found, and gate on a
compile and both test suites that actually ran.

This command is a launcher. The workflow it starts is `grind-tests`, an
agent-functor tool — the audit, the ranking, both remediation passes, the
review and the gate all live in the tool. Your job is to point it at the right
tree, start it, wait, and report. Do not audit anything yourself first, and do
not spawn subagents to do any part of it.

## Point it at the tree

Run `pwd`. The working directory must be the **target project's checkout
root** — the workflow reads the tree it is run in, and its facts prompt opens
with a probe of `domain/` and `test/`. If either is missing every lens refuses
with `FACTS PATHS UNRESOLVED` and the synthesis stops the run rather than
ranking twelve refusals. If you are not in the project root, say so and stop
rather than guessing at a path.

Nothing else needs passing. The project's runners, coverage and mutation
tooling, generated-code layout and repair disciplines are all in
`prompts/grind/tests-facts.md`, which the workflow prepends to its own input.

Pass an `input` only to steer the run — "concentrate on the browser tests",
say. It arrives *below* the facts, not instead of them. With no `input` the
lenses read whatever they are pointed at, which is the intended default.

## Start it with `sandbox=false`

**This call must not be sandboxed.** The product of a run is a dirty working
tree: the fixers edit the checkout you are standing in, and that is the
deliverable. A sandboxed run does its work in a throwaway `git worktree` and
you get a report about edits nobody can see. Nothing refuses to start on an
already-dirty tree, so check `git status` first and start from a clean one —
otherwise the review stage reads changes the run did not make.

The call returns a run id immediately. Poll `status` with it until `done` (or
`failed` / `cancelled`), then read `output`. `output` is safe to call early —
it reports progress rather than blocking. Do not poll in a tight loop; this
run takes a long time.

## What it is doing while you wait

Five stages:

1. **Audit** — twelve lenses, spread one per backend: `vacuous`, `coverage`,
   `property`, `mutation`, `stubs`, `sleeps`, `generated-copies`,
   `testability`, `dry`, `proofs`, `selectors`, `isolation`. Coverage, not
   agreement.
2. **Synthesis** — ranks the findings and writes them to
   `docs/audits/grind-tests-<YYYY-MM-DD>.md`. It names every lens it heard
   from and refuses to rank anything if a block is missing, empty, or carries
   the facts-probe refusal line.
3. **Remediation** — one orchestrated fixer, looping until its own summary
   stops asking to continue.
4. **Review of the fix** — the full review-audit panel reads the fixer's
   change: nine lenses on every backend at three granularities, ~84 leaves,
   then a second fixer acts on what the panel raised. This is the expensive
   stage, and it is the point: a test-suite remediation's cheapest failure is
   a weakened assertion, which only a review can see. A fixer that touched
   nothing leaves the panel reporting `no change to audit`.
5. **Gate** — `mix compile --warnings-as-errors`, `mix test`, and the
   TypeScript suite, each inside the project dev shell, run by agent-functor
   with the exit codes read. A red tree goes back to a repair leaf up to three
   times and then **fails the run** rather than reporting success over a red
   suite.

There is no separate TODO file. Each fixer is the next stage of the same run,
so a hand-off document would have no reader.

## Report

When the run is done, read the dated report under `docs/audits/` and give the
user:

- how many findings were ranked, and the top few by severity;
- what each fixer closed and what it rejected — those accounts are in the
  artifact above the check lines;
- whether the gate went green, and if the run failed, on which check.

Then say plainly that the tree is dirty and uncommitted, and that `/commit` is
the next step once they have read it. Do not commit anything yourself.

If the run stops on `FACTS PATHS UNRESOLVED`, the working directory was wrong
— say that rather than reporting an audit that found nothing.
