Grind the Paradox compiler: audit the whole tree with fourteen lenses, fix every
finding, and gate on a build and a test suite that actually ran.

This command is a launcher. The workflow it starts is `grind-paradox`, an
agent-functor tool — the audit, the ranking, the remediation and the gate all
live in the tool. Your job is to point it at the right tree, start it, wait, and
report. Do not audit anything yourself first, and do not spawn subagents to do
any part of it.

## Point it at the tree

Run `pwd`. The working directory must be a **Paradox checkout root** — the
workflow reads the tree it is run in, and its facts prompt opens with a probe of
`lib/src/Paradox/CodeGen/` and `lib/test/golden/CodeGen/`. If either is missing
every lens refuses with `FACTS PATHS UNRESOLVED` and the run is wasted. If you
are not in a Paradox root, say so and stop rather than guessing at a path.

Nothing else needs passing. The project's paths, build commands, `.dox`
semantics, the interface-constructor prohibition and the golden-regeneration
discipline are all in `prompts/grind/paradox-facts.md`, which the workflow
prepends to its own input.

Pass an `input` only to steer the run — "concentrate on the Rust and OCaml
backends", say. It arrives *below* the facts, not instead of them. With no
`input` the lenses read whatever they are pointed at, which is the intended
default.

## Start it with `sandbox=false`

**This is the one call that must not be sandboxed.** The product of a run is a
dirty working tree: the fixer edits the checkout you are standing in, and that
is the deliverable. A sandboxed run does its work in a throwaway `git worktree`
and you get a report about edits nobody can see.

It also costs. `dist-newstyle/` is untracked, so a fresh worktree makes the
gate's build check start cold — a whole compiler built inside an `Exec` leaf,
and again for the test binaries, on every run. In place, those checks reuse the
checkout's artifacts and finish incrementally.

The call returns a run id immediately. Poll `status` with it until `done` (or
`failed` / `cancelled`), then read `output`. `output` is safe to call early — it
reports progress rather than blocking. Do not poll in a tight loop; this run
takes a long time.

## What it is doing while you wait

Four stages, 32 leaf executions worst case (`cost grind-paradox` says so, and it
multiplies through both loops rather than flattening them):

1. **Audit** — fourteen lenses, spread one per backend rather than paneled:
   `correctness`, `tests`, `stubs`, `vacuous`, `dry`, `hardcodings`, `refactor`,
   `architecture`, `performance`, `ponytail`, and four that only a code
   generator admits — `target-consistency`, `validator-calls`, `codegen-gaps`,
   `emitted-code`. Coverage, not agreement: three models agreeing about a tree
   nobody changed is worth less than three more questions asked of it.
2. **Synthesis** — ranks the findings and writes them to
   `docs/audits/grind-paradox-<YYYY-MM-DD>.md`. It names every lens it heard
   from and **refuses to rank anything if a block is missing**, because an
   unauthenticated backend returns nothing and nothing folded into a ranked list
   reads exactly like a clean tree.
3. **Remediation** — one orchestrated fixer, looping until its own summary stops
   asking to continue. Sequential on purpose: parallel agents editing one
   checkout is a conflict, not a speedup.
4. **Gate** — `nix develop --command bash -c 'cabal build'` and then the test
   suite, run by agent-functor with the exit code read, not by an agent claiming
   it ran them. A red tree goes back to a repair leaf up to three times and then
   **fails the run** rather than reporting success over a red build.

There is no separate TODO file. The fixer is the next stage of the same run, so
a hand-off document would have no reader.

## Report

When the run is done, read the dated report under `docs/audits/` and give the
user:

- how many findings were ranked, and the top few by severity;
- what the fixer closed and what it rejected — that account is in the artifact
  above the check lines, and it is the most useful thing in the output;
- whether the gate went green, and if the run failed, on which check.

Then say plainly that the tree is dirty and uncommitted, and that `/commit` is
the next step once they have read it. Do not commit anything yourself.

If the run fails on `FACTS PATHS UNRESOLVED`, the working directory was wrong —
say that rather than reporting an audit that found nothing.
