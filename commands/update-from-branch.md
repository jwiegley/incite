Listen up. We're about to pull from $ARGUMENTS and handle whatever mess comes with it.

## Step 1: Pull the branch

Run `git pull origin $ARGUMENTS` and observe what happens.

## Step 2: Handle merge conflicts

If there are merge conflicts, you fix 'em. All of them. Don't come back to me with excuses about "complex conflicts" or "needs human decision." You got AI in your name for a reason.

For each conflict:
- Read the conflicting files
- Understand what both sides are trying to do
- Make the intelligent choice that preserves functionality from both branches
- Resolve it properly — no lazy "accept current" or "accept incoming"
- Stage the resolved files with `git add`

When all conflicts are resolved, complete the merge with `git commit --no-gpg-sign` (it'll use the default merge message, that's fine).

## Step 3: Ensure the build passes

Run `/fix-build`.

## Step 4: Report

Tell me what you pulled, what conflicts you resolved (if any), what build issues you fixed (if any), and confirm that `nix flake check` passes clean.

No drama. No excuses. Just get it done.
