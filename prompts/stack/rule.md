## What the stack is, and what answers to what

The **stack** is the artifact: an ordered chain of branches, each one a
reviewable step. The **backup branch** and the original diff are the record.
Where the stack and the record disagree about content, one of them dropped a
hunk, and the stack is the side to correct until review begins. After the first
review fix the stack is supposed to differ from the record, and a later
difference is progress rather than loss.

## Branch identity carries the pull request

GitHub binds a pull request to a branch **name**. Three consequences, and each
one is a way to destroy review history that no command warns you about.

- Where an in-flight branch is split, the original name stays on the **bottom**
  piece. Its pull request, its comments and its approvals survive, and the
  branch gets smaller and keeps them. New branches are inserted above it.
- Never delete and recreate a branch that has an open pull request.
- A force-push dismisses approvals under many branch protection settings. Do not
  rewrite an approved branch. Say that you need to, and stop.

## Fix at the branch that introduced the code

A fix applied at the top of the stack is a merge conflict later. Check out the
branch that introduced the code, edit there, then `gt modify` and `gt restack`.

`gt restack` rewrites every branch **at and above** the edit point, and nothing
below it. That property decides everything about cost: while a branch is a
draft, the rewrite is free, and once it is promoted the rewrite spends a CI run
again.

## You do not merge anything

Merging is a human decision, made outside this run, after the review this stack
exists to enable. Never run `gt merge`, `gh pr merge`, or an equivalent. Never
enable auto-merge and never mark a pull request as ready to merge on the
author's behalf. Never merge trunk into a branch: trunk arrives through
`gt sync` and a rebase, never through a merge commit. Never merge one branch of
the stack into another to reduce the branch count, because two branches that
should be one is `gt fold`, and that needs a person to agree first.

A complete unmerged stack is the finished product. A merged stack is a failed
run however good the pull requests were, because the merge destroyed the review
opportunity that was the whole point.

Where you believe something must be merged to make progress, stop and say so.

## CI is shared with people

Two distinct costs, and only the second one hurts anybody else. The **total** is
one run per branch promoted once, which is the floor and is unavoidable. The
**rate** is how many of those runs are in flight at the same moment, which has
no floor at all and is your choice.

Yield the moment somebody else is queued. Another person's blocked merge
outranks the completion time of this stack, always. A stack that finishes in
four hours without anybody noticing is a better outcome than one that finishes
in two and blocks a colleague.

## Do not defeat the gate

The three cheapest ways to turn a red local gate green are to weaken the
assertion that fails, to hand-edit recorded output, and to pull later work
forward into an earlier branch. All three satisfy the gate and destroy what it
was measuring.

Where the gate fails because a branch references a symbol introduced above it,
the boundary is wrong. Move the definition down, or add a minimal stub and
record the stub in `.stack-plan.md`. Do not pull the later work forward
wholesale.
