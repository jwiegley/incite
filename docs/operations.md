# Operations

This document covers day-to-day commands, deployment paths, input updates, and
run-state cleanup.

## Build products

Build the prompt package:

```bash
nix build
```

The default package renders both Claude and Codex trees under `result/`.

Build and run the workflow runner:

```bash
nix build .#agent-functor
nix run .#agent-functor -- list
```

Run from the repository root unless you set `AGENT_FUNCTOR_PROMPTS` yourself.

## Deploy prompts

Standalone:

```bash
nix build
```

Then inspect `result/`:

```text
result/.claude/CLAUDE.md
result/.claude/agents/<name>.md
result/.claude/commands/<name>.md
result/.claude/skills/<name>/SKILL.md
result/.codex/AGENTS.md
result/.codex/prompts/<name>.md
result/.codex/skills/<name>/SKILL.md
```

On `dunlap`, deployment flows through the consuming `nixos-dots` flake, which
reads `inputs.incite.lib.prompts` and wires them through `services.agent-pm` for
the `isaac` user:

```bash
sudo nixos-rebuild switch --flake ~/dots#dunlap
```

There is no CI config in this repository.

## Run workflows

Basic commands:

```bash
nix run .#agent-functor -- list
nix run .#agent-functor -- plan review-docs
nix run .#agent-functor -- cost review-heavy
nix run .#agent-functor -- run ship-docs -i "document the project" --sandbox
```

`ship-docs` is `workflowGReq` and edits files in place; drop `--sandbox` only
when the edits must land in the real working tree.

Useful `run` flags:

| Flag | Meaning |
|---|---|
| `--backend NAME` | override the default backend |
| `-i`, `--input TEXT` | pass the workflow input |
| `--sandbox` | isolate a world-acting run in a throwaway worktree |
| `--concurrency N` | cap fan-out concurrency; `0` means unbounded |

World-acting runs use the workflow's grant. In this repo, acting workflows share
`actingGrant = execGrant ["nix*"]`.

## Update inputs

Upstream prompt inputs:

```bash
nix flake update ponytail
nix flake update awesome-prompts
nix flake update promptdeploy
nix flake update simple-english
```

After an upstream update, rebuild and run tests that cover the affected wiring.
If a local reorientation splices an upstream rubric, inspect the reorientation
tests first; they are designed to catch section drift.

`agent-functor` is different. It is a local filesystem input:

```nix
agent-functor.url = "git+file:///home/isaac/_/agent-functor/master";
```

Keep that worktree committed before relocking. A dirty filesystem input can
produce a non-reproducible `dirtyRev` lock that breaks on the next edit.

## Development shell

Use:

```bash
nix develop
```

The shell provides GHC, cabal, HLS, the `agent-functor` library, and test
dependencies. Its hook symlinks `prompts/upstream` to the current Nix store
upstream prompt tree so cabal and HLS can see the same paths the Nix build
grafts into `src`.

That symlink is gitignored and should not be committed.

## Runtime state and cleanup

Workflow runs can leave local state:

| Path | Meaning |
|---|---|
| `.agent-functor/` | run records |
| `.agent-functor-worktree-*` | throwaway worktrees from interrupted or sandboxed runs |
| `.agent-functor-worker-*` | worker directories from interrupted runs |

Those paths are gitignored. They are safe to delete when no run is using them.
Do not delete them while a workflow is active.

## Common operational failures

Prompt path works under cabal but not Nix:

- you are relying on cabal's live compile-time source fallback;
- run from the repo root with the Nix-built runner;
- check the Nix fileset and upstream graft.

Workflow does not appear in `list`:

- the `Workflow` value exists but is not in `Main.workflows`;
- add it there if it should be public.

Prompt edit does not affect a running workflow:

- prompt files are read once per process;
- stop and start a new run.

Codex and Claude rendered trees differ:

- that is expected where native concepts differ;
- agents can degrade into skills unless `degradation = "skip"` prevents it.

