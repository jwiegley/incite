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

Run `nix flake check -L` and observe any problems. If the errors come from pre-commit hooks, then run `pre-commit run -a` as it will automatically fix most pre-commit errors.

Note: When no pre-commit hook with `nix fmt` is present, the command will still attempt to resolve formatting errors to ensure code consistency.

Avoid removing functionality and tests to make the build pass. Everything that is there now should be in a working state, not stubbed 'for now' to make the build pass. Repeat until the build passes. Use mecha-nick, auto-Kever, and robo-bobzvan respectively to handle language-specific, infrastructure, and functional programming style fixes.

## Step 4: Report

Tell me what you pulled, what conflicts you resolved (if any), what build issues you fixed (if any), and confirm that `nix flake check` passes clean.

No drama. No excuses. Just get it done.
