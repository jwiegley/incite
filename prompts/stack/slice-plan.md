Recut the plan below into a **stack of branches**. Return the same plan,
edited into that shape. Do not write a preamble and do not summarise.

## Inventory first

Run `git diff <trunk>...HEAD --stat`, then read the diff. List every file it
touches and, inside each file, every symbol it adds or modifies: type, function,
class, migration, configuration key, generated artifact.

## Then the dependency graph, and split it in two

For each symbol, record what it depends on and what depends on it. Two kinds,
and the difference between them is the whole trick:

- a **compile-time** dependency is a type or a signature that must exist for the
  file to evaluate and build. It binds absolutely, and it fixes the order.
- a **runtime** dependency is a call site. It is deferrable, because code that
  nothing calls still builds.

Cut on that distinction. Where two branches disagree about ordering, the
compile-time edge decides and the runtime edge waits.

## The layers

Order the cut so that no branch references a symbol introduced above it. The
usual shape, bottom first:

1. Mechanical preparation: renames, file moves, formatter runs, dependency and
   lock file bumps, generated code. Always alone, never mixed with a semantic
   change, and unbounded in size.
2. Schema, migrations, types, interfaces.
3. Pure logic and data access, with their tests.
4. Services, handlers, orchestration, with their tests.
5. User interface, or the public surface.
6. Wiring: entry points, dependency registration, route mounting, the feature
   flag flip. Usually small, and usually the only branch that changes observable
   behaviour.

An intermediate branch may introduce code that nothing calls yet. That is
expected and correct, and it is what makes an independent build reachable
without shuffling hunks across boundaries.

## What each entry must carry

One entry per branch, bottom first, and each one states:

- the branch name;
- a one-line purpose;
- the exact files and hunks it contains;
- the estimated diff size;
- what it deliberately leaves incomplete, and which later branch completes it;
- an unticked checkbox for local verification.

## The rules the cut answers to

- **One logical unit per branch.** A reviewer must be able to hold it in their
  head and approve or reject it on its own merits, without reading the rest of
  the stack.
- **Around 500 diff lines.** This is a consequence of a good boundary and not a
  target to hit by cutting. A 700-line branch on a clean boundary beats two
  350-line branches that split one class in half.
- **Tests ship with the code they test.** A test whose dependency arrives two
  branches later belongs two branches later.
- **Whole files where possible.** Materialise a slice with
  `git checkout <backup> -- <paths>`, and fall back to hunk-level staging only
  where one file genuinely spans two layers. Where a single function is split
  across two branches, the boundary is wrong.
- **Generated paths are isolated.** Each one goes in the mechanical branch, and
  never rides along with a semantic change.

Keep the plan line-oriented and readable in one pass. Emit the revised plan and
nothing else:
