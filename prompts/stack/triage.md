Submit the stack as drafts, get it reviewed, and fix what comes back. Every
branch is verified and every finding from the review panel above is either fixed
or answered before this stage begins.

## The arithmetic that decides the cadence

A draft pull request costs no CI in this repository, and you recorded that fact
during discovery. So review rounds are free however many you take, and the only
thing that spends is promotion, which happens after this stage. That inverts the
discipline you would expect: take as many review rounds as you need while the
stack is in draft, and be miserly only about leaving draft.

Every avoidable CI run past the floor of one-per-branch comes from promoting too
early and then rewriting. A branch promoted before the stack settled, and then
restacked by a fix below it, costs a second run for nothing.

## Submit once, as drafts

```bash
gt submit --stack --draft
```

Confirm the flag names with `gt submit --help` where that errors, and keep the
non-interactive flag from the operating rules. Drafts are the working state, and
branches leave it one at a time, bottom first, in the stage after this one.

## Trigger the review bot deliberately, and in one batch

Waiting on a review you did not ask for, on a branch you are about to rewrite,
is pure latency.

Trigger by posting a **new top-level comment in the main conversation** of the
pull request, containing `bugbot run` or `cursor review`:

```bash
gh pr comment <number> --body "bugbot run"
```

It does **not** work as a reply inside an existing comment thread. A reply to
one of the bot's own inline comments silently does nothing. Where you are
answering a thread and want a re-review, reply in the thread with your
explanation, then post the trigger separately as its own top-level comment.

Trigger a branch only where all five of these hold:

- the local gate passed at the branch's current SHA;
- the branch is pushed and in sync with its remote;
- the branch is restacked and it reports no conflict;
- the review panel findings from the stage above are already applied;
- you are not about to restack this branch or anything below it.

Trigger the whole eligible set in one loop, so the reviews run in parallel, and
record the SHA each review is against so that staleness is detectable later:

```bash
for n in <pr numbers>; do
  b=$(gh pr view "$n" --json headRefName --jq .headRefName)
  gh pr comment "$n" --body "bugbot run"
  grep -v "^$b " .stack-bugbot > .stack-bugbot.tmp 2>/dev/null || true
  mv -f .stack-bugbot.tmp .stack-bugbot
  echo "$b $(git rev-parse "$b")" >> .stack-bugbot
done
```

Then wait once, for all of them. Triggering branch by branch and reacting to
each one turns one wait into many.

Do not trigger on a branch you have only just pushed a fix to, until the whole
fix pass across the stack is complete and restacked. Do not trigger twice on the
same unchanged branch, because it costs quota and returns the same findings. Do
not trigger on any branch below one you are still editing.

## When the comments arrive

1. Collect every comment across every pull request before you fix anything.
2. Classify each one: **(a)** a real defect, **(b)** a valid style or
   consistency point, **(c)** a false positive from missing cross-branch
   context, **(d)** a legitimate design disagreement.
3. Group (a) and (b) into fix-classes. Where a pattern is flagged in three
   places, fix every instance of it in the stack, including the unflagged ones.
   Otherwise it returns next round.
4. For (c), reply on the thread with the stack context: what is deferred, and
   which branch completes it. The bot reads earlier comments, so a substantive
   reply suppresses the finding next round and silently resolving the thread
   does not. Where the same false positive appears on three or more branches,
   write a proposed `.cursor/BUGBOT.md` rule into `.stack-plan.md` under
   `## for a person`, and strengthen the deferred-work section of the branch
   description so that a human reviewer does not ask either. Do not commit that
   file: it is repository-wide configuration and it belongs in a mechanical
   branch of its own that somebody agrees to.
5. For (d), do not comply. Record the comment, the change it asks for, and why
   you did not make it, in `.stack-plan.md` under `## for a person`.
6. Apply each fix at the branch that **introduced** the code:

   ```bash
   gt checkout <origin-branch>
   # edit
   gt modify
   gt restack
   ```

   `gt absorb` routes staged fixes to the right branches automatically where
   this version supports it. Read `gt log` either way.
7. Re-run the local gate over the affected suffix:
   `./verify-stack.sh --from <lowest-edited-branch>`.
8. `gt submit --stack` once, when every fix is in. Graphite pushes only the
   branches whose SHA changed. Then trigger the next round across all eligible
   branches, in one batch.

Two rounds is the target. A third means the pattern you are flagged for is
systemic: name the pattern, fix every instance of it across the stack rather
than the flagged ones, and continue.

## Two hazards

**Automatic review mode.** Where the bot reviews every update rather than only
on request, you cannot suppress a review. The sequencing rules still apply to
**when you push**, which is the same lever. Batch the pushes, and do not push
after each individual fix.

**Autofix.** Where it is enabled in "commit to existing branch" mode, it pushes
commits to your branches underneath you, which collides with `gt modify` and
`gt restack` and produces conflicts and diverged branches. Where a branch you
did not touch reports as diverged, suspect autofix, record it under
`## for a person`, and do not resolve it yourself.
