<div align="center"><h1>V&nbsp;&nbsp;&nbsp;I&nbsp;&nbsp;&nbsp;O&nbsp;&nbsp;&nbsp;L&nbsp;&nbsp;&nbsp;E&nbsp;&nbsp;&nbsp;N&nbsp;&nbsp;&nbsp;C&nbsp;&nbsp;&nbsp;E</h1></div>

---

Declarative AI agent configuration. Skills, sub-agents, and global instructions — declared once in Nix, deployed everywhere.

Built on [Flake Prompt](https://gitlab.com/fresheyeball/flake-prompt), which
renders prompt definitions into the native on-disk formats for Claude Code, Codex, opencode, Crush, and Droid.

## Structure

```
flake.nix          — all prompt definitions + lib.prompts export
agents/
  voice.md         — personality agent body
  code-review.md   — read-only security/correctness reviewer (Sonnet)
  compiler.md      — Haskell/type-theory specialist (Opus)
commands/          — 18 slash command bodies (stripped frontmatter)
```

### Prompt types

| type | renders to |
|---|---|
| `instructions` | `~/.claude/CLAUDE.md` |
| `agent` | `~/.claude/agents/<name>.md` |
| `command` | `~/.claude/commands/<name>.md` |

## Deploying

### Via nixos-dots (dunlap)

The [nixos-dots](https://gitlab.com/fresheyeball/nixos-dots) flake
consumes this one as `inputs.incite` and wires it through
`services.agent-pm` for the `isaac` user. Changes committed here take
effect on the next:

```bash
sudo nixos-rebuild switch --flake ~/dots#dunlap
```

### Standalone

```bash
nix build
# result/.claude/ contains the full rendered layout
```

## Adding a prompt

Add an attrset to the `prompts` list in `flake.nix`:

```nix
{
  type = "command";            # command | agent | instructions
  name = "my-skill";
  description = "Does the thing";
  body = builtins.readFile ./commands/my-skill.md;
}
```

Commit, then rebuild. Done.

## Acknowledgments

Hat tip to **John Bargman** and **John Wiegley** — the idea of treating
AI prompts as first-class declarative configuration, and the tooling
([wiggum](https://github.com/jwiegley/wiggum)) that proved it out, made
this whole approach legible. Standing on shoulders.
