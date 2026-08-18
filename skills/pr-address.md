# Mission

The mirror of `/pr-review`: there I am the reviewer, here I am the author.
Coworkers have left review comments across my Graphite PR stack and I want to
work through them **one thread at a time**, with you doing the reading, the
judging, and the fixing, and me making every call that anyone else will see.

You gather every unresolved inbound thread in the stack into one ordered
queue, then walk it. Per thread: show it, show the code as it actually stands
now, tell me plainly whether the comment is right, and wait. On my word you
apply the fix through a subagent in its own worktree and push it. Replies and
resolutions are **drafted and shown, never posted without my explicit
approval** — those are outward-facing and belong to me.

The argument is any PR in the stack (the whole stack gets pulled in either
way). If none was given, infer it from the current branch
(`gh pr list --state open --head $(git branch --show-current)`); if that is
ambiguous, ask and stop.

# Hard constraints

- **Nothing outward-facing without my approval.** No posted reply, no resolved
  thread, no `gh pr comment`, no review submission, no re-request of review,
  until I say so for that specific thread. Pushing an approved fix is the one
  exception — I approve the fix, the push follows immediately (that is the
  point, same as `/pr-fix`).
- **Never resolve a thread you did not get told to resolve.** Resolving is a
  claim that the discussion is over; only the author of the conversation's
  other half or I can decide that.
- **One thread, one fix, one commit.** No drive-by cleanups, no formatting
  sweeps, no fixing the *next* comment because you're already in the file.
- Never force-push and never rewrite an existing commit — append only. The
  sole exception is a Graphite restack, which is gated in Step 5.
- The main checkout stays untouched. All edits happen in per-fix worktrees,
  siblings of the repo, never nested inside it.
- Commits use `--no-gpg-sign`.
- Ignore comments belonging to a **PENDING** (unsubmitted) review — the API
  shows me my own pending review, and shows nothing of anyone else's. A
  pending comment is not feedback yet.
- Do not build, run, or test the whole suite. A fix subagent may run the
  narrowest relevant check; that is all.

# Tone

Non-plussed and concise. Two sentences per thread, not a paragraph. Say
"they're right" or "they're wrong" and why, in one line. Do not soften a bad
comment into a fix, and do not manufacture agreement to keep the queue moving.
If a reviewer misread the code, say so and draft a reply that says so kindly.

# Step 1 — Resolve the stack

1. Verify we're in a git repo and `gh auth status` passes. If not, stop.
2. Resolve the stack. The Graphite bot's stack comment in a PR body/comments
   is canonical — it lists the stack in order. Absent that, chain branches:
   `gh pr list --state open --head <baseRefName>` finds the PR below,
   `gh pr list --state open --base <headRefName>` finds the PR(s) above.
   Walk both directions from the given PR to the ends. `gt log short` is a
   useful cross-check when the local repo is the stack's working copy.
3. For each PR in the stack, capture:
   `gh pr view <n> --json number,title,headRefName,baseRefName,author,state,isDraft,url,mergeable,mergeStateStatus`
   plus `gh pr checks <n>` (nonzero exit on failing/pending is data, not an
   error).
4. Skip merged and closed PRs. Note any PR in the stack authored by someone
   else and ask before touching it — a stack can be shared.

Report the stack compactly, one line per PR: position, number, title, state,
CI, and unresolved-thread count once Step 2 lands.

# Step 2 — Gather every unresolved thread into one queue

REST (`gh api repos/{owner}/{repo}/pulls/<n>/comments`) does **not** report
resolution state, so the queue comes from GraphQL `reviewThreads`. Per PR:

```
gh api graphql -f query='
query($owner:String!,$repo:String!,$n:Int!){
  repository(owner:$owner,name:$repo){ pullRequest(number:$n){
    reviewThreads(first:100){ nodes{
      id isResolved isOutdated isCollapsed path line originalLine diffSide
      comments(first:50){ nodes{
        id databaseId author{login} authorAssociation body createdAt
        outdated url } } } } } } }' \
  -F owner=<owner> -F repo=<repo> -F n=<n>
```

Deliberately no `diffHunk` here: it returns the whole surrounding hunk per
comment and a stack's worth of threads becomes tens of KB of stale diff that
Step 3 reads from current head anyway. Pull `diffHunk` for a single thread only
when it's `[outdated]` and I need to see what they were looking at.

Also pull top-level conversation — `gh pr view <n> --comments` — since real
feedback often lands there with no line anchor; it has no resolution state, so
treat a top-level comment as open unless it's obviously answered downthread.

Build the queue:

- **A thread is one queue item**, however many comments it holds. Never split
  a back-and-forth into separate items.
- **Include** unresolved threads, outdated-but-unresolved threads (flag them
  `[outdated]` — the code moved under the comment), and unanchored top-level
  feedback.
- **Exclude** resolved threads, my own comments on my own PR that nobody
  answered, pure approvals/"LGTM"/emoji, and bot noise (Graphite stack
  comments, coverage bots, CI summaries) — but list what you excluded as a
  one-line tally so I can pull something back in.
- **Order**: downstack-first by stack position, then by path, then by line.
  Downstack first because a lower PR's fix propagates upward and can make an
  upstack comment moot.
- **Cross-link duplicates**: when two reviewers raise the same point, or the
  same point appears on several PRs, mark them as a cluster and offer to
  handle them as one item with one fix and N replies. My call.

Number the queue `[i/N]` and print the plan: one line each —
`[i/N] PR#<n> <path>:<line> @<login> — <5-word gist>` plus `[outdated]` /
`[cluster]` / `[downstack-fix]` tags. If N is large (> ~30), say so and offer
to filter (by PR, by reviewer, by "only the ones that need code changes").

Persist the queue and the running per-thread decisions to a scratch file
**outside** any worktree, e.g. `../wg-pr-<root>-address.md`, so state survives
a long session.

# Step 3 — Walk the queue, one thread at a time

For each item, in order, print `[i/N] PR#<n> <path>:<line> @<login>`, then:

1. **The thread verbatim** — every comment in it, in order, with authors. Do
   not paraphrase what a coworker wrote. Include their ```suggestion block if
   they left one.
2. **The code as it stands now.** Read it from the PR's current head, not from
   the comment's `diffHunk` — the diff hunk is a snapshot from when the
   comment was written. For an `[outdated]` thread, show both: what they were
   looking at, and what is there now. Fetch heads lazily and cache them:
   `git fetch origin pull/<n>/head` and read via
   `git show FETCH_HEAD:<path>`, or use one throwaway worktree per PR for
   real context.
3. **Already fixed?** Check whether current head already satisfies the comment
   (my later commits, or a fix from a downstack item earlier in this queue).
   If so, say so — that item needs a reply and a resolve, not a fix.
4. **Your read, in one or two sentences.** What are they actually asking for,
   and one of:
   - **agree** — they're right; here is the change I'd make (name the files).
   - **agree, but downstack** — the real fix belongs in PR#<m> below this one;
     say so, because that drags in Step 5's restack.
   - **disagree** — they misread it, or the tradeoff was deliberate; here's
     the reply I'd send.
   - **needs your call** — a genuine judgment or taste question. State the
     options and your recommendation; do not pretend it's mechanical.
   - **out of scope** — legitimate but not this PR's job; offer a
     follow-up-issue reply.
   Say if the point overlaps a failing CI check.
5. **Stop and wait.** Then act only on what I say:
   - `fix` / `fix: <amendment>` → Step 4.
   - `reply` → draft the reply, show it, post nothing.
   - `resolve` → only after something has actually been done; still show me
     the exact command first.
   - `skip`, `defer`, `next`/`n`, `back`, `go to <k>` → navigate. `defer`
     moves the item to the end of the queue rather than dropping it.
   Record the decision per item in the scratch file. Never advance on your
   own.

# Step 4 — Apply one fix

Same machinery as `/pr-fix`, once per accepted thread:

1. Fresh head, own branch, sibling worktree, slug from the thread:
   ```
   git fetch origin pull/<n>/head
   git worktree add ../wg-pr-<n>-fix-<slug> -b pr-<n>-fix-<slug> FETCH_HEAD
   ```
2. Spawn a **subagent** to make the change. It has seen none of this
   conversation, so the task is self-contained: the absolute worktree path, the
   reviewer's comment verbatim, the file and line, the change to make and
   nothing else, "match the repo's existing style", the narrowest useful check
   to run, commit atomically with `--no-gpg-sign` and a message that explains
   *why* (it lands in my history under my name — write it as I would, and
   reference the review point, not "address comment"), and **do not push**.
3. **Read the commit yourself** — `git -C <fixdir> show` — and confirm it does
   exactly what the thread asked and nothing more. If it drifted, send the
   subagent back with a correction. Do not push garbage and do not quietly
   expand the change yourself.
4. Push immediately: `git -C <fixdir> push origin HEAD:<headRefName>`. On
   non-fast-forward, re-fetch `pull/<n>/head`, rebase the single fix commit
   once, retry. Still failing → stop and report. Never `--force`.
5. Remove the fix worktree and branch on success; leave them for inspection on
   failure and tell me where.
6. Report the sha and one line of what changed, then hold: the reply and the
   resolve for this thread are both still waiting on my approval.

If the reviewer left a ```suggestion block and I say `fix`, applying their
suggestion verbatim is the default — no subagent needed for a one-line
suggestion, just make the edit in the fix worktree and commit it.

# Reply and resolve — both gated

Drafting is free; posting is not. Draft in **my voice**: first person,
casual-professional, contractions fine, addressing the code and never the
person. Minimal, complete, actionable. Reference the fix commit sha when there
is one. Thank a reviewer who caught something real, in one clause, without
gushing. Push back plainly when they were wrong. Never mention or imply AI
authorship, and avoid the tells — no "Great catch!!", no bullet-point
mini-essays, no both-sides padding.

Show me the text and the exact command, and run nothing until I approve:

- Reply in the thread (keeps it threaded, unlike `gh pr comment`):
  ```
  gh api graphql -f query='mutation($t:ID!,$b:String!){
    addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){
      comment{ url } } }' -f t=<thread-id> -f b='<text>'
  ```
- Resolve, only when told, and only for a thread that has actually been
  answered or fixed:
  ```
  gh api graphql -f query='mutation($t:ID!){
    resolveReviewThread(input:{threadId:$t}){ thread{ isResolved } } }' \
    -f t=<thread-id>
  ```
- Unanchored top-level feedback replies with `gh pr comment <n> --body "..."`.

I may approve in batches — "post the replies for 3, 5 and 6" — so keep every
drafted reply in the scratch file keyed by queue index, and echo which ones
went out.

# Step 5 — Downstack fixes and restacking

A fix pushed to a PR below its neighbours leaves everything above it based on
stale commits. Graphite's answer is `gt restack` + `gt submit`, which
**force-pushes the upstack branches** — legitimate for a stack I own, but it
rewrites published history, so it is mine to authorize.

- Never restack on your own initiative. After a downstack fix lands, say
  which upstack PRs are now stale and offer the restack.
- On approval, from the main checkout on the stack's local branches:
  `gt restack` then `gt submit --no-interactive` (or per-branch
  `git push --force-with-lease`), then re-check
  `gh pr view <n> --json mergeable,mergeStateStatus` for each PR above.
- If a restack conflicts, stop and show me the conflict. Do not guess a
  resolution.
- If the local checkout is not the stack's working copy (branches missing),
  say so and stop rather than improvising a restack from worktrees.

# Step 6 — Sweep and close out

When the queue is empty:

1. **Re-fetch the threads** with the Step 2 query and diff against the queue:
   anything new that landed while we worked, anything still unresolved, and
   anything I fixed but never replied to or resolved. Print the leftovers
   explicitly — a fix with no reply is how a reviewer concludes they were
   ignored.
2. **One holistic pass over the feedback as a whole**, not thread by thread:
   what were the reviewers actually circling — a pattern the individual fixes
   each dodged, a design objection that N small comments were symptoms of?
   Ranked shortlist, worst first, concise. This is the part the queue cannot
   see.
3. **CI and mergeability** per PR after the pushes: `gh pr checks <n>`,
   `gh pr view <n> --json mergeable,mergeStateStatus`. Flag anything red. Do
   not fix CI here unless I ask — that is `/pr-fix` or a babysitter's job.
4. Offer, and do not do unasked: re-requesting review from the reviewers whose
   threads are now addressed
   (`gh api repos/{owner}/{repo}/pulls/<n>/requested_reviewers -f reviewers[]=<login>`).
5. Never merge or close a PR. Ever, in this skill.

# Cleanup

On my say-so: remove any lingering fix or context worktrees
(`git worktree remove ../wg-pr-<n>-...`, `git branch -D pr-<n>-fix-<slug>`) and
delete the scratch queue file — after showing me the final state of the queue,
since it is the record of what was decided and what was left. Never remove
anything without being told.
