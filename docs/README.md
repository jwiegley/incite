# Incite documentation

Incite has two products in one flake:

- a declarative prompt package rendered by `agent-pm`;
- a typed `agent-functor` workflow runner exposed as `nix run .#agent-functor`.

The source of truth is split by contract:

- prompt inventory: `flake.nix`'s `prompts` list;
- workflow inventory: `workflows/Main.hs`'s `workflows` list;
- workflow prompt bodies: `workflows/Incite/Prompts.hs`;
- package coverage for prompt files and goldens: `incite-workflows.cabal`;
- Nix build inputs for the runner and tests: the filesets in `flake.nix`.

Read the documents by what you need to change:

| Need | Read |
|---|---|
| Understand the shape of the repository | [Architecture](architecture.md) |
| Run, expose, or modify workflows | [Workflows](workflows.md) |
| Add prompts, commands, agents, or skills | [Prompt authoring](prompt-authoring.md) |
| Keep Nix, cabal, goldens, and checks aligned | [Testing and packaging](testing-and-packaging.md) |
| Deploy prompts, run workflows, update inputs, or clean run state | [Operations](operations.md) |

The short rule: when a markdown file becomes a workflow brief, it is no longer
only documentation. It becomes runtime input to an agent, a cabal packaging
artifact, and usually a Nix fileset member. Update all of the contracts together
or the failure will be late and annoying.

