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

Build the browsable Haddock for the library modules (`Incite.Prompts`,
`Incite.Backend`, `Incite.Feature`, `Incite.Review`) — this is what "the
`workflows/*.hs` Haddock is the implementation reference" points at:

```bash
nix build .#haddock
nix run .#haddock-serve   # serves it on http://localhost:8000/
```

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

**Prerequisite:** `run` drives a real ACP backend, so the backend's own CLI
must be installed and on `PATH`. The known backends
(`Agent.Backend.knownBackends`) are `claude-agent`, `codex`, `opencode` and
`droid` — all four `Supported` — plus `crush`, which is `Blocked` (no shipped
ACP agent support yet). `nix develop`'s shell does not provide any of these;
`doctor` (below) is the fastest way to check what is actually reachable.

**Also a prerequisite, specific to `claude-agent`:** every `claude-agent` leaf
this repo defines is pinned to a model matching `fable`
(`Incite.Backend.fable5`, resolved by `Agent.Op.matchModelKey` against
whatever `claude-agent-acp` advertises) — `--model` cannot override a leaf
already under a `withBackend` scope (the combinator that pins one sub-flow to
one backend and, optionally, one model), only the leaves outside one. If the
installed `claude-agent-acp` does not advertise a model whose id or name
matches `fable` uniquely, every `claude-agent` leaf refuses at preflight with
no further hint beyond the candidate list it was given. Run `doctor` to see
what is actually advertised and reconcile the installed model name.

Basic commands:

```bash
nix run .#agent-functor -- list
nix run .#agent-functor -- plan review-docs
nix run .#agent-functor -- cost review-heavy
nix run .#agent-functor -- doctor
nix run .#agent-functor -- backends
nix run .#agent-functor -- run ship-docs -i "document the project" --sandbox
nix run .#agent-functor -- mcp
```

`doctor` launches each supported backend, handshakes, and reports what it
actually advertises — the way to tell a missing binary from a working one.
`backends` lists the known backends and their launch commands, offline.
`mcp` serves the `workflows` list to a coding agent as MCP tools over stdio —
this is how a session like the one that wrote this documentation calls
`review-lite`, `review-docs`, and the rest as tools rather than through the CLI.
Running `mcp` on its own only starts the stdio server; the calling agent still
has to be told about it — this repo ships no `.mcp.json`, so register
`nix run .#agent-functor -- mcp` as an MCP server in whatever tool is calling
it (Claude Code's `claude mcp add`, or the equivalent). `--cwd DIR` sets the
directory runs started over MCP use to resolve prompt files and to act in;
omitted, it defaults to `$CLAUDE_PROJECT_DIR`, then the process's current
directory — get this wrong and prompt bodies resolve against the wrong tree
even though the server itself started fine.

`ship-docs` is `workflowGReq` and edits files in place; drop `--sandbox` only
when the edits must land in the real working tree.

Useful `run` flags:

| Flag | Meaning |
|---|---|
| `--backend NAME` | override the default backend (`claude-agent`); must be a `Supported` known backend — `claude-agent`, `codex`, `opencode`, or `droid` (`crush` is `Blocked` and refused) — a leaf under `withBackend` still pins its own backend regardless of this flag |
| `--model KEY` | default model for leaves outside a `withBackend` scope; resolved by `Agent.Op.matchModelKey` in order — exact model id, then exact case-insensitive name, then a unique case-insensitive substring of either. No match, or more than one candidate, is a preflight error naming the candidates it saw |
| `-i`, `--input TEXT` | the workflow input; for a `workflowReq`/`workflowGReq` leaf this is free-form text — the request, feature description, or review scope the first leaf reads, not a structured format. Prompts on a tty if omitted; required (errors) when piped with none given. **Replaces, not steers:** on a workflow with a baked-in default input (a plain `workflow`, e.g. `review-audit`), an explicit `-i` overrides that default outright rather than being appended to it — omit `-i` to keep the baked instruction (`review-audit`'s default is "run `git diff`") |
| `--sandbox` | isolate a world-acting run in a throwaway worktree instead of editing in place |
| `--concurrency N` | cap fan-out concurrency; default 6, or the workflow's own `withConcurrency`; `0` means unbounded — and unbounded opens one live agent session per fan-out position at once, which can burst a rate-limited backend into a 429 that aborts the whole run (fail-fast, no partial-yield policy). Recover by re-running with a bounded `--concurrency`, or by `resume`/`fork`, which continue a stopped run without re-executing the leaves it already recorded |

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

`agent-functor` is different. It comes over ssh from GitLab:

```nix
agent-functor.url = "git+ssh://git@gitlab.com/fresheyeball/agent-functor";
```

`nix flake update agent-functor` fetches that remote, not the local checkout.
Push `master` to the `public` remote before you relock, or the update re-locks
the revision already in `flake.lock` and reports success.

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

`ship-feature`/`ship-docs` runs the worker until it reports `WORK COMPLETE`:

- `orchestrate`'s `workerFuel` is `Nothing` by default — no ceiling — so the
  worker runs until it reports `WORK COMPLETE`. Set `workerFuel = Just n` to
  cap at n trips, after which the last summary yields to the review panel
  rather than aborting;
- `ship-feature-lite` is the capped one: `liteFuel` is `Just 3`. Read its final
  artifact for the marker rather than assuming it finished — the summary an
  exhausted loop yields is the one that asked for a fourth trip, so it still
  ends on `WORK REMAINS` where a converged run ends on `WORK COMPLETE`;
- the run can still abort for reasons the fuel does not cover — a rate-limited
  backend (429) or a backend error — and the work done so far is not lost then
  either: with `--sandbox` it is on the run's `agent-functor/run-…` worktree
  branch, and without it, directly in the working tree — `git status`/`git log`
  there to see what landed;
- `resume`/`fork` can continue a stopped run without **re-executing** the
  leaves the store already recorded — "replaying" is `agent-functor`'s own
  word for exactly that serve-from-record behaviour (see
  `agent-functor fork --help`, which describes `resume` as "replaying every
  leaf it already finished"), so a stopped run's completed leaves are replayed,
  not lost or rerun.

`nix run .#haddock-serve` fails to bind, or serves someone else's docs:

- the script hardcodes port 8000 with no `--port` flag; find and stop whatever
  else is bound there (`lsof -i :8000` or equivalent), or serve the built
  Haddock yourself on a different port: `python3 -m http.server <port>
  --directory $(dirname $(find $(nix build .#haddock --print-out-paths) -name
  index.html))`.

