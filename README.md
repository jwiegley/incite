<div align="center"><h1>V&nbsp;&nbsp;&nbsp;I&nbsp;&nbsp;&nbsp;O&nbsp;&nbsp;&nbsp;L&nbsp;&nbsp;&nbsp;E&nbsp;&nbsp;&nbsp;N&nbsp;&nbsp;&nbsp;C&nbsp;&nbsp;&nbsp;E</h1></div>

---

Declarative AI agent configuration. Instructions, sub-agents, slash commands, and
skills — declared once in Nix, deployed everywhere. Plus a set of typed
multi-agent workflows that drive the agent from the outside.

Two halves, one flake:

- **Prompts** — built on [Flake Prompt](https://gitlab.com/fresheyeball/flake-prompt),
  which renders prompt definitions into the native on-disk formats for Claude
  Code, Codex, opencode, Crush, and Droid.
- **Workflows** — built on `agent-functor`, a typed workflow library (local
  checkout, no remote yet). Workflows are `Flow Text Text` values composed with
  `>>>`; the CLI (`list`/`plan`/`cost`/`run`) and a live TUI for `run` come for
  free.

## Structure

```
flake.nix          — every prompt definition + the two packages
agents/            — sub-agent bodies
  voice.md         — personality agent
  code-review.md   — read-only security/correctness reviewer (Sonnet, no write/edit/bash)
  compiler.md      — Haskell/type-theory specialist (Opus)
  fess-auditor.md  — evidence-backed honesty check on a finished session
commands/          — slash command bodies (frontmatter lives in flake.nix)
skills/            — skill bodies
  fix-all.md       — fix every finding found along the way, no "out of scope"
  pr-review.md     — interactive, strictly read-only PR review in a worktree
  pr-comment.md    — draft one comment into the pending review
  pr-fix.md        — apply one change via a subagent, push to the PR head
workflows/
  Main.hs          — the typed workflows; `passMain` gives them a CLI
prompts/           — prompt bodies for the workflows, read at RUN time
  plan.md          — turn exploration findings into a one-step-per-line plan
  pick-best.md     — merge three racing workers' worktrees into this repo
  review-step.md   — review one plan step for correctness/completeness/ordering
  explore/*.md     — the three explore stances: intrepid, skeptic, contemplative
incite-workflows.cabal  — builds a binary named `agent-functor`; rooted at the
                          REPO ROOT so a `prompts/…` path means the same thing at
                          compile time and at run time
```

The `prompts` list in `flake.nix` is the authoritative inventory — every prompt
is declared there, so read it rather than counting files.

Two more prompts are read out of the private `macha` input rather than this
repo: the `agentic-philosophy` instructions block and the `fstar-erlang-ell`
command.

### Prompt types

| type | renders to |
|---|---|
| `instructions` | `~/.claude/CLAUDE.md` (concatenated in `order`) |
| `agent` | `~/.claude/agents/<name>.md` |
| `command` | `~/.claude/commands/<name>.md` |
| `skill` | `~/.claude/skills/<name>/SKILL.md` |

Per-prompt knobs used here: `order` (instructions only — the concatenation
order in `CLAUDE.md`), `model`, `mode`, `argumentHint`, `extraFrontmatter`
(temperature, tool denials, `agent =` binding, skill `author`/`invocation`),
and `degradation = "skip"` — which drops a prompt on tools that lack the
native concept instead of degrading it into something that collides. Only
`code-review` sets `skip` today: tools without native agents would degrade the
agent into a skill, colliding with the `code-review` *command* already
deployed as a skill there.

### The PR-review trio

`pr-review` is the entry point and the other two are its companions — they are
meant to be invoked *during* a review, not standalone:

- **`/pr-review <pr-number>`** sets up an isolated worktree and walks the diff
  one logical group of hunks at a time, strictly read-only, pausing for
  discussion. Ends with a holistic adversarial pass, then leaves a background
  babysitter keeping the PR mergeable. Understands Graphite stacks — `next`
  advances upstack as a fresh review.
- **`/pr-comment <feedback>`** turns one piece of feedback into a minimal,
  actionable comment on the *pending* GitHub review. Nothing submits until you
  explicitly say so — the whole review posts as one batch.
- **`/pr-fix <change>`** hands one change to a subagent in a *separate*
  worktree and pushes it to the PR head branch. The review worktree stays
  untouched, so reviewing and fixing never fight over the same tree.

The split is deliberate: the reviewer never writes, the fixer never reviews.

## Inputs

| input | source | note |
|---|---|---|
| `agent-pm` | `gitlab:fresheyeball/flake-prompt` | the renderer |
| `macha` | private ssh, `flake = false` | supplies two prompt bodies |
| `agent-functor` | `git+file:///home/isaac/_/agent-functor` | **local path** |

`agent-functor` is pinned to its own nixpkgs (its Haskell deps want 24.11), so
it deliberately does *not* `follows` incite's unstable. It is also a local
filesystem input: this flake will not evaluate on a machine without
`/home/isaac/_/agent-functor` checked out.

## Deploying the prompts

### Via nixos-dots (dunlap)

The [nixos-dots](https://gitlab.com/fresheyeball/nixos-dots) flake consumes
this one as `inputs.incite`, reads the raw definitions off `lib.prompts`, and
wires them through `services.agent-pm` for the `isaac` user. Changes committed
here take effect on the next:

```bash
sudo nixos-rebuild switch --flake ~/dots#dunlap
```

### Standalone

```bash
nix build
```

`result/` holds one tree per enabled tool — the default package turns on both
`claude` and `codex`:

```
result/.claude/CLAUDE.md               result/.codex/AGENTS.md
result/.claude/agents/<name>.md        result/.codex/prompts/<name>.md
result/.claude/commands/<name>.md      result/.codex/skills/<name>/SKILL.md
result/.claude/skills/<name>/SKILL.md
```

The two trees are deliberately not mirror images. Commands map across one to
one, but codex has no sub-agent concept, so agents degrade into skills there —
`.codex/skills/` ends up holding the real skills *plus* `voice`, `compiler`
and `fess-auditor` (and not `code-review`, per the `skip` above). That
asymmetry is the degradation policy working, not a rendering bug.

## Running the workflows

__Run these from the repo root.__ The workflow prompt bodies are
`Agent.Prompt.promptFile` references — checked when the binary compiles, read
from disk when it runs — and they resolve relative to the working directory. From
anywhere else, set `AGENT_FUNCTOR_PROMPTS=/path/to/incite`; the error message
tells you so, and lists every path it tried.

The upside of reading at run time: edit a `prompts/*.md` (or the `agents/` and
`skills/` bodies the workflows reuse) and re-run. No rebuild.

```bash
nix run .#agent-functor -- list              # what's defined
nix run .#agent-functor -- plan ship-feature # the flow skeleton, offline
nix run .#agent-functor -- cost ship-feature # token estimate, offline
nix run .#agent-functor -- run  ship-feature -i "add a --json flag"
```

`run` flags: `--backend NAME` (default `claude-agent`), `-i/--input TEXT`
(prompts on a tty if omitted), `--sandbox` (isolate a world-acting run in a
throwaway worktree instead of editing in place — the result is committed to an
`agent-functor/run-…` branch; prompt-only flows have nothing to isolate and
always run in place), `--concurrency N` (caps concurrent fan-out sessions;
defaults to 6, or the workflow's own `withConcurrency`; `0` = unbounded).

`run` picks its front-end off the terminal. On a tty it drives the **live
TUI**: a context header, a stage list that fills in as leaves complete, a
scrolling agent transcript with styled inline tool calls, and modals for the
points where a flow blocks on you — `steer`, `humanGate`, and any permission
prompt answer straight out of the TUI. Piped or in CI it falls back to an
inline transcript and those same blocking points drop to plain stdin asks, so
an unattended `ship-feature-full` still stops at its gate. `plan` and `cost`
never touch an agent, so they work anywhere.

Currently defined in `workflows/Main.hs`:

| workflow | what it does |
|---|---|
| `ship-feature` | explore (3 stances) → plan → lens edits → multi-scale review. Prompt-only: touches nothing |
| `ship-feature-full` | the above, then implement via 3 racing workers in separate worktrees, an 8-beat build/commit/review loop, a human gate, and a PR. World-acting; `execGrant` permits only `git`/`cabal`/`gh` |
| `haskell-review` | review a function, then rewrite it fixing the issues |
| `explain` | explain code in plain English |
| `test-writer` | draft hspec tests → critique → finalize |

World-acting runs leave `.agent-functor-worktree-*` / `.agent-functor-worker-*`
directories behind if killed mid-run; they're gitignored, and safe to delete.

## Adding a prompt

Add an attrset to the `prompts` list in `flake.nix`:

```nix
{
  type = "command";            # command | agent | skill | instructions
  name = "my-skill";
  description = "Does the thing";
  body = builtins.readFile ./commands/my-skill.md;
}
```

Commit, then rebuild. Done.

## Adding a workflow

Write another `Workflow` in `workflows/Main.hs` and list it in `workflows`. The
CLI picks it up automatically.

```bash
nix develop   # GHC with agent-functor in scope, plus cabal and HLS
```

Put anything longer than a line in `prompts/` and reference it:

```haskell
myBrief :: Prompt
myBrief = [promptFile|prompts/my-brief.md|]        -- checked now, read at run time

refineWith "my-leaf" (brief myBrief) id            -- body, blank line, artifact
refineWith "my-leaf" (\x -> [i|#{myBrief}          -- or interpolate, #{} holes
                              Budget: #{n} steps
                              #{x}|]) id
```

A bad path is a **compile** error. `[promptFile|…|]` and `[i|…|]` both come from
`Agent.Prompt` (agent-functor re-exports `string-interpolate`, so there is no
extra dependency); the module needs `{-# LANGUAGE QuasiQuotes #-}`, already on in
`incite-workflows.cabal`.

A new prompt directory must be added to the `fileset` in `flake.nix`, or the nix
build sandbox will not see it and the compile-time check will fail.

Use `workflow` for a workflow with a baked-in input, `workflowReq` for one that
demands an input, and `workflowGReq` when it acts on the world — the extra
argument is the `execGrant` whitelist, and everything not listed is denied.

## Acknowledgments

Hat tip to **John Bargman** and **John Wiegley** — the idea of treating
AI prompts as first-class declarative configuration, and the tooling
([wiggum](https://github.com/jwiegley/wiggum)) that proved it out, made
this whole approach legible. Standing on shoulders.
