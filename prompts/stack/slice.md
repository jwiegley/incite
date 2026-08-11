Build the stack the plan describes. `.stack-plan.md` and `.stack-branches` are
already on disk and they are authoritative; re-read them at the start of every
branch rather than working from memory.

## Say which mode you are in, before the first command

**Split** is one unmerged branch with a large diff against trunk and nothing
submitted. The procedure below applies as written.

**Repair** is a stack that already exists, possibly with open pull requests.
Read this before you touch anything.

- Learn what is already submitted: `gt log`, plus `gh pr list --head <branch>`
  for each branch. A branch with an open pull request carries review history.
- Use `gt split` on the branch in question rather than the rebuild-from-backup
  flow below, which is for unsubmitted work only. Run `gt split --help` first
  and find out which granularity flags this version offers.
- Diff a branch against its parent, never against trunk.
- Where the existing stack is sound and needs only review triage, write the two
  ledger files from `gt log` (checked by eye against the pull request parent
  chain) and go straight to the review stage.

Never run the backup-and-rebuild flow against a submitted stack.

## Preserve the original first

```bash
git branch <feature>-backup
git rev-parse <feature>-backup
```

Record that SHA in `.stack-plan.md`. Everything below is recoverable from it.

## One branch at a time, bottom first

For each entry in the plan, in order:

```bash
gt checkout <parent>          # trunk, for the first branch
# stage that slice's contents, explicit paths only
gt create <branch-name> -m "<the commit message from the section below>"
nix flake check --no-build --no-update-lock-file
```

Materialise a slice with whole files where you can:
`git checkout <feature>-backup -- <paths>`. Fall back to hunk-level staging only
where one file genuinely spans two layers.

The fast gate evaluates every output without building one, so it answers in
seconds and it catches the failure that dominates here: a reference to a symbol
introduced further up. Do not run the full gate in this loop. A harness runs
that once, over every branch, after you finish.

Tick the plan checkbox for a branch only after a clean fast gate.

## When the fast gate fails

- **A symbol from a later layer is missing.** The boundary is wrong. Move the
  definition down, or add a minimal stub and record the stub in the plan. Do not
  pull later work forward wholesale.
- **An unused import or an unused export warns.** Expected in an intermediate
  branch. Suppress it narrowly at the declaration, with a comment naming the
  branch that will use it. Never disable the rule for the whole repository.
- **A test fails because its dependency does not exist yet.** The test belongs
  in a later branch, with the code it tests.

## The commit message is the pull request

A non-interactive `gt submit` takes the pull request title from the commit
subject and the body from the commit body, so a description that exists only in
your head becomes a prompt that hangs the session. Write it into the commit
message when you create the branch.

Subject: `<scope>: <imperative change>`, specific enough to tell this branch
apart from its neighbours in the stack.

Body, in this order:

- **What changes.** Two or three sentences of substance. No preamble about the
  pull request itself, and no restatement of the diff line by line.
- **Why**, where the title does not already answer it.
- **Deliberately deferred.** What is intentionally unwired or unused here, and
  which branch completes it. Write this on every branch except the top one. It
  removes a whole class of review comment before anybody writes it.
- Any non-obvious decision a reviewer would otherwise have to ask about.

State the goal of the whole stack once, in the bottom branch. The Graphite stack
view carries the rest.

## The equivalence check, once, at the end

When every branch exists, `git diff <feature>-backup <top-of-stack>` must be
empty. Where it is not, you dropped or duplicated something: reconcile it now.

Run this check once. From the first review fix onward the stack is supposed to
differ from the backup, so do not run it again and do not repair the stack back
toward the backup.
