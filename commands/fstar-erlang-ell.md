You are working in the `fsharp-erlang-hell` / `macha-orchestration` codebase — a BEAM + F* + C++23 agentic orchestration platform. Load these precepts before doing anything else.

## Terminology

- **Agent**: An LLM invocation (provider + model + system-prompt + prompt). NOT a BEAM process.
- **Orchestrator**: Deterministic decision-making engine. NOT an LLM itself.
- **Foreman**: Local C++ execution supervisor. Bridges the orchestrator to heterogeneous endpoints.
- **Session**: Cached LLM context over time (prompt → output → toolcall → …).
- **Task**: Unit of work. States: `Fail | Succeed | Wait`.

## Inviolable Rules

1. **F* is Source of Truth** — When an F* module covers a domain, it is the sole implementation. There is no Elixir fallback.
2. **No Runtime F* Loading** — All F* modules compile to BEAM bytecode at build time via StarBeam. Nothing loads `.fst` at runtime.
3. **Fail Hard** — If a verified BEAM module is missing or its exports are incomplete at boot, crash. No graceful degradation.
4. **Fix StarBeam Upstream** — Never work around a StarBeam bug in application code. Fix it in StarBeam and consume the fix.
5. **Per-Module Migration** — A module enters the F* migration track only when it is pure AND has 100% test coverage. Document the plan; enforce crash-on-failure from day one of migration.
6. **Agent ≠ BEAM process** — The Orchestrator is deterministic BEAM. The Agent is the LLM it calls.
7. **Never modify Nix derivations directly** — All build changes go through `flake.nix`.
8. **BEAM is immutable in behavior** — Use OTP supervision patterns for failure, not defensive branches.

## StarBeam Status

| Module | Status |
|---|---|
| `BashValidator.fst` | ✅ Live — compiled to `:bashvalidator` BEAM module |
| `AgentValidation.fst` | ⏳ Pending — blocked by FStarBeam OCaml parser issue |
| `SkillValidation.fst` | ⏳ Pending |
| `DecisionNode.fst` | ⏳ Pending |
| `PipelineSerialization.fst` | ⏳ Pending |

**Blocker**: FStarBeam OCaml parser rejects type-annotated extracted code for complex dependent types beyond BashValidator's complexity. Fix it upstream — do not work around it.

## Orientation

```
elixir/lib/fsharp_erlang_hell/
  pipeline/      — execution engine (GenServer-based)
  foreman/       — WebSocket registry, job dispatch, heartbeat
  http/handlers/ — REST endpoints
  opencode/      — opencode CLI wrapper
fstar/verified/  — F* modules awaiting StarBeam compilation
fstar/compiled/  — StarBeam output (BEAM bytecode)
cpp/foreman/     — C++23 Foreman client (WebSocket, Ed25519, SQLite)
nix/modules/     — NixOS modules for server, foreman, client
```

## Build Commands

```bash
# Server
nix develop
mix test
mix credo
mix format

# Client (C++)
cd cpp/foreman && mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release .. && make
make test

# Full check
nix flake check

# F* proofs
fstar --verify fstar/proofs/*.fst
```

$ARGUMENTS
