## Probe first

Before you read anything else, run these five commands from the current working
directory:

```bash
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --git-common-dir
git status --porcelain=v1 --branch
gt --version
```

Then run `gh auth status`.

Six conditions must hold. The first command must print the current working
directory itself. **The second and third must print the same path** — see below.
The fourth must show a branch that is not the trunk. The fifth must print a
Graphite version. The last must report an authenticated account.

**The second and third conditions are the one a probe usually misses.** Inside a
linked git worktree, `git rev-parse --show-toplevel` prints the worktree root, so
the first condition passes and tells you nothing. Only `--git-dir` and
`--git-common-dir` differ there. This matters because Graphite keeps its metadata
in the shared `.git` directory: a stack cut inside a worktree either corrupts
that metadata or lands its branches somewhere the working tree cannot see. A
stacking run must therefore happen in the main checkout, which means it must run
with the sandbox OFF.

If any condition fails, stop. Do not look for the checkout somewhere else, and
do not report that the stack is in good order. Emit this line, alone, as your
whole answer, with the failing condition named:

`STACK PRECONDITIONS UNMET: <condition>. This working directory cannot carry a Graphite stack, so every instruction below names nothing.`

For the worktree condition, name it exactly:

`STACK PRECONDITIONS UNMET: this is a linked git worktree (--git-dir and --git-common-dir differ). Graphite metadata lives in the shared .git, so a stack cut here is either corrupt or invisible. Re-run with the sandbox off, in the main checkout.`

A run that reads no branches reports no work, and a finished stack reports no
work too. That line is what tells the two apart.

## What this repository is, before you plan anything

Three values decide how the diff is cut, and none of them is assumed here. Read
each one now and record it in `.stack-plan.md` under a `## repository facts`
heading.

- **Trunk.** `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`.
  Every diff below is taken against it and no branch ever modifies it.
- **The local gate.** The command that proves one branch builds. Where the
  repository has a `flake.nix`, that command is `nix flake check`. Where it does
  not, read the CI workflow files and take the command they run. Record the fast
  form beside it: `nix flake check --no-build --no-update-lock-file` evaluates
  every output without building one, and it catches the failure that dominates
  during slicing, which is a reference to a symbol introduced further up.
- **Generated paths.** Every path whose content is produced by a tool rather
  than written by hand: lock files, generated sources, formatter output. Each
  one goes in a mechanical branch of its own and never rides along with a
  semantic change, so the cut depends on knowing them.

Everything else this run needs about the repository — what CI runs that the
local gate cannot, whether drafts trigger CI, the binary cache, the review bot,
the job budget — is discovered once by the stage that writes the tooling to
disk, and recorded there. Read `.stack-plan.md` for it rather than re-deriving
it here.

## Operating rules

**Never block on a prompt.** Every command must be non-interactive, or it hangs
until the session dies.

- Export `GIT_EDITOR=true`, `GIT_PAGER=cat` and `PAGER=cat` before anything else.
- Use `gt create -m "<message>"`. A bare `gt create` opens an editor.
- `gt submit` asks for pull request titles. Read `gt submit --help` in this
  installed version, find the non-interactive flag, and let it take the title
  and body from the commit message. Do not assume the flag name.
- `gt sync` asks before it deletes merged branches. Pass its force flag.
- Where nix asks to accept flake configuration settings, pass
  `--accept-flake-config` rather than leaving it to ask.

**Anything that builds goes to the background.** A full local gate outlives the
command timeout and dies mid-build, which reads as a failure and is not one. Run
it detached, then poll it:

```bash
nohup ./verify-stack.sh > /tmp/verify.out 2>&1 &
# poll: tail -n 20 /tmp/verify.out at intervals, and check the process
```

Backgrounding a job does not end your turn. Poll it, and work an independent
branch while it runs.

**Never run `git add -A`.** It sweeps `.stack-plan.md`, `.stack-branches` and
the three scripts into a slice. Stage explicit paths only.

**Never run a Graphite command inside a worktree.** Graphite keeps its metadata
in the shared `.git` directory, and a concurrent write there corrupts the stack.
Worktrees are read-only build scratch. Every `gt` command runs in the main
checkout.

**Re-read `.stack-plan.md` at the start of each branch.** A large diff does not
fit alongside the work. The plan file is authoritative and your recollection is
not.
