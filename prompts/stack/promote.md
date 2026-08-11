Promote the stack out of draft, bottom first. This is the only stage that spends
CI, and CI is shared with people.

## Stop before you start, if the stage below you was blocked

Read the account you were given. Where it ends `WORK BLOCKED`, or where
`.stack-plan.md` has open items under `## for a person`, promote **nothing**.
A block is a decision somebody has to make, and CI spent on branches that are
waiting for that decision is CI spent twice. Repeat the block in your own
summary, end `WORK BLOCKED` yourself, and stop.

## The budget gate already ran for this turn

A harness outside this session ran `./ci-budget.sh --wait` immediately before
this turn and read its exit code. You are here because it allowed a promotion.
It enforces the cap and the yield rule for you, out of `.stack-config`, so you
do not need to reason about either.

What it cannot do is cover a turn it did not run in. Runs start and finish
between turns, so run `./ci-budget.sh` yourself, in the same turn, before every
`gh pr ready` after the first. Never promote on a budget you did not just read.

## What makes a branch promotable

A restack rewrites every branch at and above the edit point and nothing below
it. So a branch is safe to promote as soon as it and everything below it has
settled, and churn higher in the stack cannot reach it. Eligibility is a
downward-looking question, never a whole-stack one.

For the branch and for every branch below it, all four must hold:

1. **The local gate passes at the branch's current SHA.** A stale result
   describes code that no longer exists. A local failure guarantees a CI
   failure, so promoting without a current pass throws the slot away.
2. **It is pushed**, restacked, and free of conflicts. Otherwise CI tests
   something other than what you have.
3. **The review bot was triggered at this SHA and returned nothing new.** A
   review recorded against an older SHA describes code that no longer exists,
   exactly as a stale local result does. Retrigger and wait.
4. **No unaddressed comments**, including items you tracked by hand in
   `.stack-plan.md`.

Promote the longest prefix that satisfies all four **and fits the budget**, in
that order. Leave the rest in draft, including branches that are settled and
merely unaffordable. A settled branch sitting in draft costs nothing and loses
nothing. It is the throttle working, not a delay.

Passing all four does not mean CI passes. It means every failure you could
detect without CI is gone, which is the most this stage can do. Promotion is how
you learn the rest, and that is its purpose rather than a fallback.

```bash
gh pr ready <pr>        # promote
gh pr ready --undo <pr> # demote back to draft
```

## The first promotion is a measurement

Hardware-specific checks and anything else outside the local gate are invisible
until a pull request leaves draft, and so is the number of jobs one pull request
spawns. Promote **exactly one** branch, the bottom one, and wait for it to
finish. Then count the jobs:

```bash
gh run list --branch <branch> --json databaseId --jq '.[].databaseId' \
  | xargs -r -n1 -I{} gh run view {} --json jobs --jq '.jobs|length' \
  | paste -sd+ - | bc
```

Record that number in `.stack-plan.md` as the jobs-per-pull-request figure,
beside every CI-only check the run revealed. From then on the maximum number of
simultaneously promoted, still-running pull requests is the budget divided by
that figure, and never less than one. Where one pull request exceeds the whole
budget on its own, say so plainly: the workflow matrix is the real problem and
it belongs to whoever owns that file.

Never promote a second branch before the probe finishes. Where the figure turns
out larger than you assumed, an unmeasured batch has already overshot by the
time you find out.

## When a promoted branch fails CI

Read the failing job before you touch a branch. Three cases, and they are
handled differently.

- **A check the local gate also covers.** This should not have reached CI. The
  local gate was stale, skipped, or run against a different SHA. Find out which,
  and fix that, rather than only fixing the branch.
- **A CI-only check.** Hardware-specific tests, integration suites, anything
  outside the local gate. Expected, and not a process failure: it is the
  information you promoted to get. Demote the branch, fix it, re-run the local
  gate, and re-promote that branch alone before resuming the prefix. Record the
  check in `.stack-plan.md`, and where it turns out to be reproducible locally,
  say so: moving it into the local gate converts an expensive discovery into a
  cheap one for every stack after this.
- **CI cannot run at all.** Covered below, and it is not a fact about your code.

Converting a pull request to draft does not cancel a running workflow. Where you
demote a branch whose run is already doomed, cancel the run so the runner
returns to the pool:

```bash
gh run list --branch <branch> --status in_progress --json databaseId --jq '.[].databaseId' \
  | xargs -r -n1 gh run cancel
```

Where a fix has to touch a promoted branch or anything below it, demote that
branch and every promoted branch above it first, then fix, then re-verify
locally, then re-promote the prefix. Pushing a restack into promoted branches
turns one fix into many CI runs.

## When CI cannot run at all

Polling has a deadline. Where a check sits queued or running for roughly ten
minutes with no progress, investigate rather than poll:

```bash
gh run view <run-id> --json jobs \
  --jq '.jobs[] | {name, status, conclusion, runner_name, started_at, labels: .labels}'
```

Read it for structure.

- A job queued with an empty runner name is waiting for a runner that is not
  coming. Note which pool its labels ask for. Hosted pools and self-hosted pools
  starve independently, and one being healthy says nothing about the other.
- Walk the dependency chain between jobs. A cheap gating job that cannot get a
  runner kills every job downstream of it, including jobs whose own pool has
  capacity. The failure you see may not be the failure.
- Get a contrast case. Find a recent successful run of the same workflow with
  `gh run list --workflow <name> --status success`, and compare where each job
  ran and how long it queued.
- Separate your own cancellations out first. A push while a run is in flight
  cancels that run where the workflow sets cancel-in-progress, and the signature
  is a cancel within seconds of your push. Starvation looks different: a long
  queue, no runner assigned, then a timeout. Check your push timestamps against
  the cancellations, and say which ones were yours.

Where the diagnosis is infrastructure: do not retry into a starved pool, because
a retry consumes queue position to reproduce a known result. One retry rules out
a transient failure, and systematic retrying does not. Do not demote and fix,
because there is nothing in the branch to fix and churning it destroys the
review and verification state you built. Freeze promotion where it is, leave the
affected pull requests alone, and finish everything that does not need CI.

Then write the diagnosis into `.stack-plan.md` under `## for a person`: which
job, which runner pool, the chain it gates, the contrast case, and the cheapest
fix. That fix is usually a relabel onto a pool with headroom, or cutting a
dependency edge so a cheap check cannot take down expensive independent jobs.
**Workflow files are repository-wide, team-owned configuration.** Propose the
change and never commit it. A concurrency group in the workflow file is the
durable fix for the rate problem, and it belongs to the same rule.

## Stop at promotion

The run ends when every branch is promoted and CI reports a pass on it. Do not
merge anything, do not enable auto-merge, and do not treat a passing run or an
approval as permission to proceed. A complete unmerged stack is the finished
product.
