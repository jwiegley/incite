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

## Read the configuration out of the repository

Every value below is a property of the target repository, and none of it is
assumed here. Read each one, then write all of them into `.stack-plan.md` under
a `## repository facts` heading before you touch git.

**Discovery happens once.** The stage that writes the plan to disk performs it.
Every later worker reads `.stack-plan.md` instead of running these commands
again — the block below tells you what is recorded there and where it came from,
not that you should re-derive it.

- **Trunk.** `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`.
- **The local gate.** The command that proves a branch builds. Where the
  repository has a `flake.nix`, that command is `nix flake check`. Where it does
  not, read the CI workflow files and take the command they run. Record the fast
  form as well: `nix flake check --no-build --no-update-lock-file` evaluates
  every output without building one, and it catches the failure that dominates
  during slicing, which is a reference to a symbol introduced further up.
- **What the local gate cannot see.** Run `nix flake show` once, and read the CI
  workflow files. Record which checks CI runs that the local gate does not.
  A local pass is a filter against known-bad promotions. It is not a prediction
  of success, and no branch is called green on the strength of one.
- **Whether draft pull requests trigger CI.** Read the `on:` block of every
  workflow file. A workflow that filters on `types:` without `ready_for_review`
  does not run on a draft. Record the answer, because the whole plan below
  depends on it: where drafts are free, review costs nothing and only promotion
  spends.
- **A binary cache.** Look in `flake.nix` under `nixConfig.extra-substituters`,
  in `/etc/nix/nix.conf`, and in the CI configuration. Where a Cachix or attic
  instance exists and you hold push credentials, run the local gate under
  `cachix watch-exec <cache>` so local verification populates it and CI resolves
  the same derivations as cache hits. Where none exists, say so plainly. On an
  overtaxed runner that one fact is worth more than every other saving here.
- **The review bot and its trigger mode.** Read one existing pull request's
  comments to learn the bot account name:
  `gh api "repos/{owner}/{repo}/pulls/<n>/comments" --jq '.[].user.login' | sort -u`.
  Assume the bot reviews every update until you confirm otherwise, and plan
  pushes on that assumption.
- **Generated paths.** List every path whose content is produced by a tool
  rather than written by hand: lock files, generated sources, formatter output.
  Each one goes in a mechanical pull request of its own and never rides along
  with a semantic change.
- **The concurrent job budget.** Six is a sane default, four is safer, and the
  number is a cap on CI jobs belonging to this stack, not on pull requests. One
  pull request can be a ten-job matrix.

  Record it in **two** places: in `.stack-plan.md` for a person, and as the bare
  number alone on one line in a file named `.stack-budget` at the repository
  root. The harness runs the budget gate itself and reads that file. A number
  written only into the plan is a number the gate never sees, and the gate then
  enforces its own default rather than the budget you discovered.

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
