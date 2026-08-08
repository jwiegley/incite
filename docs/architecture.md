# Architecture

Incite is a prompt repository with a small Haskell workflow package bolted to
it. The two halves share prompt text deliberately, but they have different
lifecycles and different failure modes.

## System shape

```text
flake.nix prompts list
  -> agent-pm
  -> result/.claude, result/.codex
  -> nixos-dots services.agent-pm on the consuming machine

workflows/Main.hs workflow list
  -> agent-functor runner
  -> CLI subcommands and MCP tools
  -> prompt leaves that read markdown at run time
```

The prompt package is declarative Nix data. The workflow runner is a cabal
package rooted at the repository root, even though its Haskell source lives
under `workflows/`. That root choice is not cosmetic: `[promptFile|...|]`
checks paths relative to the package root at compile time and reads them
relative to the working directory at run time. Both must be the repository root.

## Inventories

There are two inventories and they answer different questions.

`flake.nix`'s `prompts` list answers: what prompt artifacts are deployed by
`agent-pm`? It declares instructions, agents, slash commands, and skills, plus
their metadata. Counting files on disk is wrong because several prompts are read
from flake inputs and some local files are not deployed directly.

`workflows/Main.hs`'s `workflows` list answers: what workflows exist as CLI
subcommands and MCP tools? A `Workflow` value can be defined and still be
private if it is not in this list. `plannerAudit` is the current example: it is
defined in `Incite.Review`, but `Main.hs` leaves it unlisted on purpose.

## Prompt provenance

Workflow prompt bodies come from three places:

| Source | Example | Runtime behavior |
|---|---|---|
| Local workflow prompts | `prompts/plan.md` | live-editable; re-run without rebuilding |
| Deployed prompts reused as briefs | `agents/code-review.md`, `skills/fix-all.md`, `commands/wiggum.md` | one copy drives both deployment and workflow leaves |
| Upstream flake inputs | `prompts/upstream/ponytail/review.md` | not in git; update the input and rebuild |

`workflows/Incite/Prompts.hs` binds all workflow prompt bodies. Keep it as data,
not logic. Composition belongs in `Incite.Feature` or `Incite.Review`.

## Runtime prompt resolution

For a `[promptFile|path/to/file.md|]` reference, the runner tries:

1. `$AGENT_FUNCTOR_PROMPTS/path/to/file.md`
2. `<cwd>/path/to/file.md`
3. the compile-time source directory

The Nix-built runner wraps `AGENT_FUNCTOR_PROMPTS` to point at a store tree that
contains only `prompts/upstream/**`. That gives upstream briefs a stable store
path while local prompts fall through to the working directory and remain
live-editable.

The cabal binary behaves differently: candidate 3 can be a live source tree, so
a cabal-built binary may find prompts from a non-root directory that the Nix
binary cannot. Test the Nix path when you are checking deploy behavior.

## Haskell modules

| Module | Responsibility |
|---|---|
| `Main` | workflow inventory only |
| `Incite.Prompts` | prompt body bindings only |
| `Incite.Backend` | backend and reviewer scoping vocabulary |
| `Incite.Feature` | request-to-plan and acting workflows |
| `Incite.Review` | review, documentation review, retrospectives, and prompt linting |

The most important design pattern is "name the contract once". Examples:

- `continueMarker` is spliced into worker briefs and matched by
  `decideContinue`.
- `reviewHeavyFlow`, `reviewDocsFlow`, and `retroFlow` are plain `Flow` values
  so standalone workflows and acting workflows use the same panel.
- `docsRule` and `codeRule` make the remediation rule explicit instead of
  relying on a default.

## Blast radius of common changes

Adding a new prompt file can affect all of these:

- `flake.nix`, if the prompt is deployed;
- `Incite.Prompts`, if a workflow reads it;
- `incite-workflows.cabal`, if a `promptFile` splice can reach it;
- the runner and test filesets in `flake.nix`, if Nix must see it in the build
  sandbox;
- `stePromptSrc`, if it is procedural prompt prose that should be mechanically
  linted;
- `test/Spec.hs` and `test/golden/*`, if the prompt changes a contract that
  otherwise fails silently.

Adding a workflow affects:

- the defining module, usually `Incite.Feature` or `Incite.Review`;
- `Main.workflows`, if it should be exposed;
- docs and command descriptions, because the CLI and MCP tools are generated
  from that inventory;
- the grant policy, if the workflow acts on the world.

Adding an upstream prompt affects:

- the `upstream` allowlist in `flake.nix`;
- `upstreamPrompts`;
- `Incite.Prompts`;
- `incite-workflows.cabal` globs, if the directory is new;
- README/docs provenance notes, because license and update behavior matter.

