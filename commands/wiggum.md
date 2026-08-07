If you have a known target, continue autonomously until you complete every task
and reach parity with that target. Parity means that the implementation matches
the named target in behavior and in test coverage. If you have no known target,
continue until you complete and verify every objective in the current plan.

As you work, maintain one document. It records the task list and the handoff
notes, so that we always know exactly what has been done, what remains, and
where and how we can pick up the task and execute it to completion if anything
happens to the machine and we need to start a fresh AI session.

## After each commit: run the post-commit audit

Follow the **`post-commit-audit`** procedure. It is the single description of which
checks to run, what to pass them, and how to poll — do not restate or improvise it
here, and do not substitute your own idea of a check for it.

Two things it leaves to you, because they belong to this loop and not to the audit:

- **How the findings get fixed** — see below. The audit hands them back; it does
  not say who applies them.
- **When to stop auditing.** Its rule is that a commit fixing an audit finding is
  not itself audited. In this loop that also means it gets no `fix-all` subagent —
  the loop has to terminate.

If the audit returns nothing actionable, say so in one line. Then return to
work — no subagent, nothing to fix.

## Then: fix the findings in a subagent

When the audit returns something real, do **not** fix it inline. Spawn **one**
subagent running the `fix-all` skill and give it the findings.

That skill is the whole point of the handoff: "no exceptions, no excuses, no
deferrals — *out of scope*, *pre-existing* and *follow-up ticket* are not
acceptable framings", one TODO per finding, a real test for everything changed,
fixes pushed upstream rather than patched at the call site, and no reward
hacking. Applied inline, in the middle of your own task, that standard is exactly
what gets quietly traded away for momentum. In its own agent it does not compete
with your task, and your context stays on the work rather than filling with the
cleanup.

What to hand it, because it has none of your context:

- **The findings verbatim** — the whole `output`, every lens, not your summary of
  it. A paraphrase is where a finding loses the detail that made it actionable.
- **The commit** it is fixing (SHA and `git show`), and where the work sits in
  the plan.
- **Its boundary**: fix these findings and stop. It is not to continue your task,
  restructure beyond what a finding names, or start the next item.

Wait for the subagent. Read the diff it produced — you own the result, not the
subagent. Run the build and the tests yourself. Then commit its work as one
logical change. If it deferred anything, that is a `fix-all` violation: send it
back rather than accepting the deferral.

Then resume — that commit is not audited again and gets no second subagent, per
the rule above. Perfect is the enemy of good.
