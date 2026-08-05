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
  `>>>`; the CLI (`list`/`plan`/`cost`/`run`) comes for free.

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
workflows/
  Main.hs          — the typed workflows; `passMain` gives them a CLI
  *.cabal          — builds a binary named `agent-functor`
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

Per-prompt knobs used here: `model`, `mode`, `argumentHint`,
`extraFrontmatter` (temperature, tool denials, `agent =` binding), and
`degradation = "skip"` — which drops a prompt on tools that lack the native
concept instead of degrading it into something that collides. The standalone
package renders for `claude` and `codex`.

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
result/.claude/CLAUDE.md          result/.codex/AGENTS.md
result/.claude/agents/<name>.md   result/.codex/prompts/<name>.md
result/.claude/commands/<name>.md result/.codex/skills/<name>/SKILL.md
result/.claude/skills/<name>/SKILL.md
```

## Running the workflows

```bash
nix run .#agent-functor -- list              # what's defined
nix run .#agent-functor -- plan ship-feature # the flow skeleton, offline
nix run .#agent-functor -- cost ship-feature # token estimate, offline
nix run .#agent-functor -- run  ship-feature -i "add a --json flag"
```

`run` flags: `--backend NAME` (default `claude-agent`), `-i/--input TEXT`
(prompts on a tty if omitted), `--sandbox` (isolate a world-acting run in a
throwaway worktree instead of editing in place), `--concurrency N` (caps
concurrent fan-out sessions; defaults to 6, or the workflow's own
`withConcurrency`; `0` = unbounded).

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

Use `workflow` for a workflow with a baked-in input, `workflowReq` for one that
demands an input, and `workflowGReq` when it acts on the world — the extra
argument is the `execGrant` whitelist, and everything not listed is denied.

## Acknowledgments

Hat tip to **John Bargman** and **John Wiegley** — the idea of treating
AI prompts as first-class declarative configuration, and the tooling
([wiggum](https://github.com/jwiegley/wiggum)) that proved it out, made
this whole approach legible. Standing on shoulders.
