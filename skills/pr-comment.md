# Mission

Companion to `/pr-review`: turn a piece of feedback into a GitHub review
comment on the PR under review, added immediately to my **pending review** —
creating that pending review if it doesn't exist yet. Comments accumulate
there across invocations; when I say the review is done, they all go out as
one review. Never post a standalone or immediately-published comment.

The argument is the feedback to leave. If it's missing, or I haven't made
clear what code it's about, ask and stop.

# The comment

Compose it, don't transcribe me — I give you the concern, you produce the
comment a good colleague would write:

- **Minimal, complete, actionable.** The problem, why it matters (one clause,
  and only if it isn't obvious), and a concrete way forward. Nothing else. If
  the fix is a small, certain edit, include a GitHub ```suggestion block so
  it's one click to apply.
- **Kind.** A human wrote this code and a human will read this comment.
  Address the code, never the author. Prefer "could we…", "I think…", or a
  genuine question over commands. No snark, no lectures, no rubric-speak.
  Direct is fine — cold is not.
- **In my voice.** It must read like me, an engineer, typing in the review
  box: first person, casual-professional, contractions fine. Never mention or
  imply that it was AI-generated, and avoid AI tells — no "Great work
  overall!", no bullet-pointed mini-essays, no over-hedged both-sides padding.
- **Humor is welcome** when it lands naturally. Never at the author's expense,
  and never forced — a dry aside beats a performance.

Pending comments are visible only to me until submission, so add immediately —
no approval gate — then echo back exactly what was added and where. I can ask
you to reword or drop any pending comment afterward; nothing is public yet.

# Mechanics

1. Identify the PR from the review context (the `wg-pr-<n>-review` worktree or
   `pr-<n>` branch); ask if ambiguous.
2. Anchor the comment: `path`, `line`, and `side` (`RIGHT` for added/changed
   lines, `LEFT` for deletions) taken from the diff under discussion; use
   `startLine` for multi-line ranges. If the anchor is unclear, ask.
3. Find my pending review:
   `gh api repos/{owner}/{repo}/pulls/<n>/reviews` and look for
   `"state": "PENDING"` (the REST API only ever shows me my own pending
   review). At most one pending review per user exists on a PR.
4. If there is none, create it — pending, no event:
   ```
   gh api graphql -f query='mutation($pr: ID!) {
     addPullRequestReview(input: {pullRequestId: $pr}) {
       pullRequestReview { id } } }' -f pr=<pr-node-id>
   ```
   (`gh pr view <n> --json id` gives the PR node id.)
5. Add the comment to the pending review:
   ```
   gh api graphql -f query='mutation($rev: ID!, $path: String!, $body: String!) {
     addPullRequestReviewThread(input: {
       pullRequestReviewId: $rev, path: $path, line: <line>,
       side: RIGHT, body: $body}) { thread { id } } }' ...
   ```
   Do NOT use `gh pr comment` or `POST .../pulls/<n>/comments` — those publish
   immediately, outside the review.
6. Confirm: the comment text, its anchor, and the running count of comments
   now sitting in the pending review.

# Revising

On request, reword or delete any pending comment
(`updatePullRequestReviewComment` / `deletePullRequestReviewComment`
mutations). Safe at any time before submission.

# Submitting

Only when I explicitly say the review is done: submit the pending review so
every comment lands as **one review** —

```
gh api repos/{owner}/{repo}/pulls/<n>/reviews/<review-id>/events -f event=COMMENT
```

`COMMENT` is the default; use `REQUEST_CHANGES` or `APPROVE` only if I say so.
If I provide a summary, it goes in the review body under the same tone rules.
Before submitting, show me the full set one last time. Never submit on your
own initiative — submission is the only outward-facing step in this skill.
