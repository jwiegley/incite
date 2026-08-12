Grind the LiveView layer: audit it with eleven lenses, fix every finding, and
gate on a compile and a test suite that actually ran.

This command is a launcher. The workflow it starts is `grind-live-view`, an
agent-functor tool — the audit, the ranking, the remediation and the gate all
live in the tool. Your job is to point it at the right tree, start it, wait,
and report. Do not audit anything yourself first, and do not spawn subagents
to do any part of it.

## Point it at the tree

Run `pwd`. The working directory must be the **target project's checkout
root** — the workflow reads the tree it is run in, and its facts prompt opens
with a probe of `lib/operation_web/live/` and `domain/`. If either is missing
every lens refuses with `FACTS PATHS UNRESOLVED` and the synthesis stops the
run rather than ranking eleven refusals. If you are not in the project root,
say so and stop rather than guessing at a path.

Nothing else needs passing. The project's view and component layout, the
centralized topics module, the stable-id module, the hook-registration
convention and the repair disciplines are all in
`prompts/grind/live-view-facts.md`, which the workflow prepends to its own
input.

Pass an `input` only to steer the run — "concentrate on the authorization
handlers", say. It arrives *below* the facts, not instead of them. With no
`input` the lenses read whatever they are pointed at, which is the intended
default.

## Start it with `sandbox=false`

**This call must not be sandboxed.** The product of a run is a dirty working
tree: the fixer edits the checkout you are standing in, and that is the
deliverable. A sandboxed run does its work in a throwaway `git worktree` and
you get a report about edits nobody can see. Nothing refuses to start on an
already-dirty tree, so check `git status` first and start from a clean one.

The call returns a run id immediately. Poll `status` with it until `done` (or
`failed` / `cancelled`), then read `output`. `output` is safe to call early —
it reports progress rather than blocking. Do not poll in a tight loop; this
run takes a long time.

## What it is doing while you wait

Four stages:

1. **Audit** — eleven lenses, spread one per backend: `css-hardening`,
   `componentize`, `liveness`, `rerender`, `pubsub`, `best-practices`,
   `auth`, `page-load`, `dom-keying`, `assign-bloat`, `ts-hooks`. Coverage,
   not agreement.
2. **Synthesis** — ranks the findings and writes them to
   `docs/audits/grind-live-view-<YYYY-MM-DD>.md`. Authorization findings rank
   above every performance and UX finding, each keeping the severity word the
   auth lens put on it. The synthesis names every lens it heard from and
   refuses to rank anything if a block is missing, empty, or carries the
   facts-probe refusal line.
3. **Remediation** — one orchestrated fixer, looping until its own summary
   stops asking to continue.
4. **Gate** — `mix compile --warnings-as-errors` and `mix test`, each inside
   the project dev shell, run by agent-functor with the exit codes read. A
   red tree goes back to a repair leaf up to three times and then **fails the
   run** rather than reporting success over a red suite.

There is no review-audit stage and no separate TODO file: the fixer is the
next stage of the same run, and `grind-tests` is the tier that pays for a
panel over its own fix.

## Report

When the run is done, read the dated report under `docs/audits/` and give the
user:

- how many findings were ranked, the authorization findings first with their
  severity words, then the top few of the rest;
- what the fixer closed and what it rejected — that account is in the
  artifact above the check lines;
- whether the gate went green, and if the run failed, on which check.

Then say plainly that the tree is dirty and uncommitted, and that `/commit` is
the next step once they have read it. Do not commit anything yourself.

If the run stops on `FACTS PATHS UNRESOLVED`, the working directory was wrong
— say that rather than reporting an audit that found nothing.
