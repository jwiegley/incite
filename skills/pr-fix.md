# Mission

Companion to `/pr-review`: apply one specific change to the PR under review,
without breaking the review session's read-only stance. I describe the change;
a subagent makes it in its own worktree; the resulting commit is pushed to the
PR head branch immediately. The review worktree is never touched.

The argument is my description of the desired change. If it's missing or too
vague to act on, ask and stop.

# Hard constraints

- The review worktree (`wg-pr-<n>-review`) and the main checkout stay
  untouched. All edits happen in a dedicated fix worktree.
- One change per invocation — the change I described, nothing else. No
  drive-by cleanups, no formatting sweeps.
- Never force-push. Never rewrite existing PR commits; only append.
- Commits use `--no-gpg-sign`.

# Step 1 — Identify the PR

Infer the PR number from the current review context (the `wg-pr-<n>-review`
worktree or `pr-<n>` branch); if it isn't unambiguous, ask. Then:

```
gh pr view <n> --json headRefName,baseRefName,isCrossRepository,headRepositoryOwner,headRepository,maintainerCanModify
```

If it's a cross-repository (fork) PR without `maintainerCanModify`, say the
push will be impossible and stop before doing any work.

# Step 2 — Fix worktree on the latest head

The PR may have moved since the review snapshot, so base on a fresh fetch —
and the `pr-<n>` branch is already checked out in the review worktree, so the
fix gets its own branch:

```
git fetch origin pull/<n>/head
git worktree add ../wg-pr-<n>-fix-<slug> -b pr-<n>-fix-<slug> FETCH_HEAD
```

`<slug>` is a short kebab-case tag derived from the change description, unique
per invocation so parallel fixes never collide.

# Step 3 — Spawn the subagent

Delegate the edit to a subagent. It has seen neither this prompt nor the
review conversation, so the task must be self-contained. Include:

- The absolute path of the fix worktree — it works only there.
- The change description verbatim, plus the review context it needs (file,
  line, the concern that motivated the change).
- Scope: make ONLY the described change. Match the repo's existing style.
- If the change is testable cheaply, run the narrowest relevant check
  (typecheck, the one test file). Do not launch a full suite.
- Commit atomically with `--no-gpg-sign`; the message explains *why* (it will
  appear in the PR's history under my name — write it like I would).
- Do NOT push. Report back: what changed, what was checked, the commit sha.

# Step 4 — Verify, then push immediately

Read the commit yourself — `git -C <fixdir> show` — and confirm it does what I
asked and nothing else. If it's wrong, send the subagent back with the
correction; do not push garbage and do not silently fix it yourself beyond
trivial amendments.

Once it matches, push without asking — that is the point of this skill:

- Same-repo PR: `git -C <fixdir> push origin HEAD:<headRefName>`
- Fork PR: push to the fork,
  `git -C <fixdir> push <fork-remote-or-url> HEAD:<headRefName>`

If the push is rejected as non-fast-forward (someone pushed meanwhile), fetch
`pull/<n>/head` again, rebase the fix commit onto it once, and retry. If it
still fails, stop and report — never `--force`.

# Step 5 — Report and clean up

Report: the commit sha, a one-line summary of the change, confirmation it's on
the PR. Remind me that the review session's saved diff is now stale — hunk
numbering still refers to the snapshot, and gets re-fetched only when I ask.

After a successful push, remove the fix worktree and its branch
(`git worktree remove ../wg-pr-<n>-fix-<slug>`, `git branch -D
pr-<n>-fix-<slug>`). On failure, leave them in place for inspection and tell
me where they are.
