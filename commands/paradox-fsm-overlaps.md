Audit the codebase for three classes of paradox-related findings:

1. **State machines** implemented in Elixir, Haskell, and/or TypeScript that should consolidate into a single Paradox `.dox` FSM.
2. **Mirroring** — hand-written types, wire encoders/decoders, validation rules, or constant maps that re-state something Paradox already generates (or should generate) from a `.dox` source. The pattern: a TS `interface PipelineStatus { ... }` next to an Elixir `defmodule Dox.Ci.PipelineStatus` next to a Haskell `data PipelineStatus = ...` when one `.dox` union could feed all three.
3. **Dead or under-consumed paradox** — `.dox` declarations that emit codegen no source file imports (dead), or that get consumed in one language while the others hand-roll equivalents (under-consumed). This is the inverse of Class 2: not "the mirror is the bug" but "the paradox source isn't being used where it could be."

Classes 1 and 2 share a drift cost: a rename in one layer breaks the other layers silently. Class 3 is a different cost — paradox carrying weight it doesn't pull for the project. All three have the same shape of fix: align the consumer surface to the `.dox` source (delete dead `.dox`, declare missing `.dox`, replace mirrors with imports).

This is a research task. Produce a triaged report at `docs/audits/paradox-fsm-overlaps-<YYYY-MM-DD>.md`. Do not change SUT code in this pass — surface candidates and prioritize them. A follow-up `/address-findings` pass picks up the rewrite work.

## Why this matters

The project rule (see `/address-findings`'s "Language / stack hierarchy" section):

> Hierarchy: 1. Paradox `.dox` — default for any shared domain logic. 2. F* with proofs. 3. Elixir / TS / Rust direct — last resort.

State machines that exist in multiple languages are the most expensive class of drift: a transition added in Elixir but missed in TS produces wire desyncs that look like runtime bugs. A status atom renamed in Haskell but stale in Elixir produces ETL silent-corruption. Paradox FSMs solve this — one declaration, three codegen targets.

## What a Paradox FSM looks like

Read `domain/ci/evaluation_fsm.dox` and `domain/ci/job_fsm.dox` for current examples. The shape:

```
union EventName
  startEval
  evalCompleted
  ...

type StateContext
  field1: T1
  ...

transitionName: Transition State Event Context
  Transition:
    event: Event.eventName
    target: State.targetState
    guard: ()

stateConfig: StateConfig State Event Context
  StateConfig:
    transitions: [ ... ]

fsmName: Fsm State Event Context
  Fsm:
    states: { State.x: xConfig, State.y: yConfig, ... }
    initial: State.x
    initialContext: defaultContext
```

If you find a candidate that doesn't fit (e.g. effectful transitions, hierarchical states, time-based transitions paradox doesn't model yet), flag that as an upstream paradox feature gap — that's its own valuable output.

## What to look for

### Class 1 — state machines

#### Elixir signals
- `GenServer` callbacks (`handle_call/3`, `handle_cast/2`, `handle_info/2`) where the clause head pattern-matches on a state field and the body returns a new state
- `gen_statem` callbacks
- `case {state, event} do ... end` style central dispatch
- Modules named `*Machine`, `*FSM`, `*StateMachine`, `*Transitions`
- Modules with `transition/2`, `valid_transition?/2`, `terminal?/1` functions
- A status field on an Ecto schema with hand-rolled transition validation in a wrapper function
- Atoms or strings repeated across modules that look like states: `:pending`, `:running`, `:succeeded`, `:failed`, `:cancelled`

### Haskell signals
- ADTs whose constructors look like states: `data Status = Pending | Running | Succeeded | Failed`
- Functions of shape `Event -> State -> State` or `State -> Event -> Maybe State`
- Type-class-based state machines (`class State s where transition :: ...`)
- Indexed monads or singleton-typed state encodings
- Files named `*FSM.hs`, `*StateMachine.hs`, `*Transitions.hs`

### TypeScript signals
- Reducers `(state, action) => state` (Redux-style, useReducer, XState)
- Discriminated unions on `kind`/`type`/`status` field with switch statements that produce next-state objects
- XState-shaped objects (`createMachine({ states: ..., on: ... })`)
- Phoenix LiveView hooks holding `currentStatus` with `handleEvent("update", ...)` setting new status
- D3 / animation state encoded as `enum`-like `const X = { Idle: ..., Animating: ..., Done: ... }`

#### Cross-language FSM overlap signals
- The same status name appearing as `:atom` (Elixir), `Constructor` (Haskell), and `"string"` (TS wire form). Paradox's lowercase-tag rule means the wire form is the canonical name — grep for it across all three.
- Wire formats encoded by hand in multiple places. If `Dox.X.PrStatus.to_json/from_json` exists but TS has its own `prStatusFromString`, that's a duplication.
- An event name that crosses an HTTP boundary or a WebSocket boundary and gets handled in both an Elixir GenServer AND a TS hook.

### Class 2 — mirroring (hand-written code that should be Paradox codegen output)

This class is broader than FSMs. Anything that *re-states* a Paradox declaration in hand-written code is mirroring. The clue is structural: a hand-written shape that has a 1:1 correspondence with a `.dox` definition (or could have one).

#### Shape A — already-in-paradox, mirrored anyway
A `.dox` source exists; Paradox emits something for it; but a hand-written copy also exists. The hand-written copy is the bug. Examples:
- `Dox.Ci.PipelineStatus` (Elixir, paradox-generated) co-exists with `type PipelineStatus = "pending" | "running" | ...` in `assets/ts/types.ts` (hand-written).
- Paradox emits `Dox.Ui.ChannelEvent.to_json(:log_line) → "logLine"`, but a TS file has `const CHANNEL_EVENTS = { logLine: "logLine", ... }` re-stating the wire mapping.
- A Haskell `data Visibility = Public | Private | Internal` next to `Dox.Visibility` — the Haskell version is hand-written but Paradox already generates the Elixir equivalent.

How to find:
- For each `.dox` union or type: grep for the constructor names + wire forms across .ex (excluding `.dox/lib/`), .ts, .hs.
- Compare member sets. A hand-written copy with EXACTLY the same members is the obvious case; a hand-written copy with a SUBSET is drift waiting to happen; a hand-written copy with EXTRA members is a fork that needs reconciliation.

##### Shape A fix pattern: handwritten is ALWAYS the duplicate

When a `.dox` source AND a handwritten module both define the same shape, the handwritten module is the bug — **always**. The fix is mechanical: delete the handwritten file, consume the codegen output directly. There is never a case where a handwritten "duplicate of a `.dox` declaration" is the canonical form. Paradox emits to `.dox/lib/dox/<area>.ex` (Elixir), `.dox/<area>.ts` (TS), `.dox/Dox/<Area>.hs` (Haskell), `.dox/lib/dox/schemas/*.ex` (Ecto), `.dox/lib/operation_web/...` (Phoenix LiveView / Layouts / routes), etc. All of those are the source of truth for their respective layers.

Watch for codegen targets beyond unions/types — the same pattern applies to:
- **Ecto schemas** (`Dox.Schemas.*`): paradox-ecto emits these from `.dox` types; any handwritten `Dox.Schemas.Foo` in `lib/dox/schemas/` is a duplicate to delete.
- **Phoenix layouts / components / routes** (`Dox.Web.*`): paradox-phoenix emits these from `.dox` URI declarations + `--phoenix-live:` config in `main.dox`. If `.dox/lib/operation_web/components/layouts.ex` defines `Dox.Web.Layouts` AND a handwritten `lib/operation_web/components/layouts.ex` also defines `Dox.Web.Layouts`, **delete the handwritten one**.
- **CSS palettes / themes**: emitted via paradox `--css` (e.g. `.dox/theme.css`). A handwritten `assets/css/brand-colors.css` that re-states the same palette is the duplicate; the workflow should consume the codegen output.
- **Nix JSON exports**: emitted via paradox `--json defaultPalette`. Any `nix/...-palette.nix` that hardcodes the same values is the duplicate.
- **Haskell CLI default values**: paradox emits `Dox.Command.settingsParser` with `value defaultX` defaults. Any handwritten parser that hardcodes the same defaults is the duplicate.

Reframing: when an /address-findings task surfaces a "duplicate module collision", the brief should NEVER be "fix paradox to stop emitting" or "guard with `Code.ensure_loaded?`". It should always be "delete the handwritten module; the codegen output is what we want". The collision IS the signal that the handwritten file needs to go.

This also applies when a `.dox` regen *introduces* a new collision because paradox's codegen newly covers something the project used to hand-roll. That's not a regression — that's the project graduating to the dox-emitted version. Delete the handwritten file in the same commit that bumps the flake input.

#### Shape B — should-be-in-paradox, never made it
A domain type is hand-written in 2+ languages, but no `.dox` source exists for it. The fix is to add the `.dox` declaration and consume the codegen. Examples:
- An Elixir `@type role :: :owner | :admin | :member | :guest` next to a TS `type Role = "owner" | "admin" | "member" | "guest"` next to a Haskell `data Role = Owner | Admin | Member | Guest`. None reference Paradox.
- Wire-format encoders hand-rolled on both sides of an HTTP/WebSocket boundary (`role_to_string/1` in Elixir, `roleFromString` in TS).
- Validation rules that mirror each other ("non-empty string of length ≤ 64" appearing in Elixir Ecto changeset, TS Zod schema, and Haskell smart constructor).

How to find:
- Grep for `@type` / `@spec` Elixir aliases that look domain-shaped (status, role, kind, mode, phase, scope, action).
- Grep for `data X = | Y | Z` Haskell ADTs in domain-y modules.
- Grep for `type X = "a" | "b" | "c"` TS string-literal unions.
- Cross-reference by member-name overlap.

##### Shape B fix pattern: add the dox declaration, delete all hand-written copies in the same commit set

The fix is two-step: (1) write the `.dox` source — union/type/wrap — and let `paradox start` regenerate; (2) replace every hand-written copy with an import of the codegen output. Both steps must land before merging — leaving any hand-written copy in place produces immediate drift. The natural commit boundary is: `domain/x.dox` + main.dox registration first; per-language consumption second (or per-language third/fourth if scope is large). Wire-form: paradox's lowercase-tag rule means the union members ARE the wire strings — pick the member names so the wire form is what you'd want on the wire. Don't shape the members around what the existing hand-rolled Elixir atoms or TS strings look like; shape them around the canonical domain vocabulary.

#### Shape C — wire-format duplication
Even without union duplication, the encoder/decoder pair is often duplicated. Paradox emits `to_json` / `from_json` per union; if TS or Haskell hand-rolls the same mapping, that's mirroring.

How to find:
- Each `Dox.*.to_json/1` function in `.dox/lib/`: grep for the literal wire strings it produces (e.g. `"logLine"`, `"jobStatus"`) across hand-written code. Each hit is a candidate.
- Each `from_json/1`: same exercise.

##### Shape C fix pattern: replace the hand-rolled encoder/decoder with the codegen helper

The hand-rolled `xToString` / `xFromString` / `parse_x` / `dump_x` function gets deleted; its call sites switch to the paradox-emitted `<dox-module>.to_json/1` / `from_json/1` (Elixir) or `<unionName>ToJson` / `<unionName>FromJson` (TS) or the Haskell ToJSON/FromJSON instance. No transitional `import _ as _legacy` shims — the hand-rolled version goes away entirely. If the hand-rolled version handled some edge case the paradox emit doesn't (e.g. a synonym tag that maps to the same atom), that edge case either belongs in the union as an `illuminate` block, or doesn't belong in the wire surface at all. Don't keep the hand-roll alive for it.

#### Shape D — constant maps masquerading as types
Sometimes hand-written code uses a const object/map keyed by union members as a poor-man's exhaustive switch. Paradox-generated unions + a generated match-helper would replace it.

How to find:
- TS `const X_LABELS = { foo: "...", bar: "..." }` where the keys overlap a Paradox union's members. Replace with a paradox-emitted helper.
- Elixir maps like `@status_colors %{pending: "yellow", running: "blue", ...}` mirroring a `.dox` enum.
- Haskell `statusColor :: Status -> Color` total functions over an ADT that already has a `.dox` twin.

##### Shape D fix pattern: the map values become a paradox `illuminate` block

If `@status_colors %{pending: "yellow", running: "blue", ...}` keys a Paradox union, the values are the Shape-D fix target. Add an `illuminate <UnionName>Color` block in the same `.dox` file as the union, with one entry per union member. Paradox emits an `illuminate<UnionName>Color/1` helper across all targets (Elixir, TS, Haskell). The hand-written const map goes away. Two specific things to watch for: (1) Shape D maps where the keys are RUNTIME-extended (e.g. add a new color when a new theme variant ships) — those are NOT Shape D; they're real runtime state and don't belong in `illuminate`. (2) Shape D maps where the keys are a STRICT subset of the union — usually a bug, surface it. The fix is either: extend the map to cover every member (so consumers can rely on totality), or narrow the union to just the keyed members.

### Class 3 — dead or under-consumed paradox

For each `.dox` declaration, count the consumers across the three languages. The pathological cases:

#### Shape E — dead `.dox` (zero consumers)
A union / type / fsm / helper exists in `.dox` and emits generated modules, but no source file imports or references anything generated from it. The declaration is carrying weight nothing reads. The fix is to delete the `.dox` source (after confirming no test fixture, no migration, no runtime introspection consumes it). Examples to watch for:
- `Dox.X.Y` module that nothing aliases / nothing calls
- A union whose member tags (`Dox.X.Y.to_json(:foo)` results) never appear as wire strings in any source
- An `.dox` file added speculatively for a planned feature that never landed

#### Shape F — under-consumed (consumed in 1 language, hand-rolled in others)
This overlaps with Class 2 Shape A but is the inverse framing — the audit point is the PARADOX side, not the mirror. Useful when the user is auditing `domain/` to understand what's pulling weight. Examples:
- `domain/ci/types.dox` defines `PipelineStatus`; Elixir consumes via `Dox.Ci.PipelineStatus`; TS has its own hand-rolled `type PipelineStatus = "..." | "..."`; Haskell has `data PipelineStatus = ...`. From the `.dox` POV: 1 of 3 codegen targets actually consumed.
- An `.dox` union with `--typescript` codegen enabled but no TS file imports the generated module — under-consumed on TS specifically.

#### Shape G — codegen target enabled but unconsumed
A codegen target (`--haskell`, `--typescript`, `--ecto`, etc.) is enabled in `main.dox` but for a SPECIFIC declaration, that target's output is never imported anywhere. The fix is either to consume it (Class 2 Shape A cleanup on the language side) or to scope the target down (don't emit for this declaration).

How to find Class 3:
- For each `.dox` declaration: enumerate the symbol names paradox emits per target (e.g. `Dox.Ci.PipelineStatus` for Elixir, `pipelineStatus` for TS, `PipelineStatus` for Haskell).
- Grep across the three language source trees (excluding generated `.dox/lib/`, `assets/.dox/`, etc.) for those symbols.
- Bucket the result:
  - 0 references anywhere → Shape E (dead)
  - References in 1 language only AND a hand-written twin exists in another → Shape F (under-consumed; cross-reference Class 2 Shape A findings)
  - References in 1 language AND no hand-written twin anywhere else → not under-consumed; just genuinely only needed in that one language (drop)
  - Specific target's symbol has 0 references but other targets are consumed → Shape G (target-specific under-consumption)

Use the paradox-source agent's inventory as the iteration seed.

## How to look (parallelize)

Dispatch FOUR subagents in parallel — three per-language inventory passes plus one paradox-source pass. The synthesis agent reads all four and produces TWO outputs: one for Classes 1+2 (drift findings) and one for Class 3 (dead/under-consumed paradox).

### Per-language agents (Elixir / Haskell / TypeScript)
Each agent's brief:

> Inventory two classes of candidates in {Elixir under lib + test | Haskell under runner + bench | TypeScript under assets/ts}:
>
> **Class 1 (state machines)**: any code that encodes state transitions — file:line of the state definition + file:line of the transition logic + a one-line description of the domain + the status/event vocabulary.
>
> **Class 2 (mirroring)**: any hand-written type, union, validation rule, wire-format encoder/decoder, or constant map that looks like it duplicates a Paradox declaration. For each: file:line + member vocabulary + a one-line description of what it represents. Flag candidates that EXACTLY match an existing `.dox` union vs candidates that have no `.dox` source yet.
>
> **Class 3 input — reference index**: ALSO build a reference index of every paradox-generated symbol the source consumes. For Elixir: every `Dox.*` module aliased or fully-qualified call. For TS: every import from `../.dox/...` or `@dox/*`. For Haskell: every `import Dox.*` (if/when haskell codegen consumed). Emit as a separate JSON: `consumes.json` with `{"symbol": "Dox.Ci.PipelineStatus", "from_file": "lib/operation/ci/...", "line": 42}` entries. The synthesis pass diffs this against the paradox inventory to find dead/under-consumed `.dox` declarations.
>
> Skip code that is clearly UI-local (no wire/domain meaning) or vendored.

### Paradox-source agent
> Inventory the `.dox` corpus under `domain/`. For each union / type / fsm / wrap / helper: name, members or fields, codegen targets (`--elixir`, `--typescript`, `--haskell`, `--ecto`, etc.), AND the symbol names paradox is expected to emit per target (e.g. `Dox.Ci.PipelineStatus` for Elixir, `pipelineStatus` for TS, `Dox.Ci.PipelineStatus` for Haskell — names depend on the codegen target's naming convention; consult `domain/.dox/` output to verify).
>
> Output two files:
> - `paradox.json` — the existing per-declaration record (kind, name, members, fields, codegen_targets)
> - `paradox-emitted-symbols.json` — per-declaration map of `{target → expected_symbol_name(s)}` so the synthesis pass can grep across languages

### Synthesis pass
1. Read the four inventories plus the three per-language `consumes.json` reference indexes.
2. For each Class 2 candidate from any per-language agent: check the paradox lookup.
   - If a matching `.dox` exists → Shape A (mirroring already-paradox code; immediate fix is to delete the hand-written copy and import the codegen).
   - If no matching `.dox` exists but 2+ languages have a hand-written twin → Shape B (net-new `.dox` source needed).
   - If only 1 language has the shape but the codegen target is broken/missing → Paradox feature gap (Shape D edge case or codegen-target gap).
3. For each Class 1 candidate: cross-reference by shared status/event names.
4. For each `.dox` declaration (Class 3 pass):
   - Look up the expected emitted symbols in `paradox-emitted-symbols.json`.
   - Grep each symbol across the three `consumes.json` indexes.
   - 0 hits total → Shape E (dead). Flag for deletion confirmation.
   - 1 language consumes, ≥1 other has a Class 2 Shape A finding for it → Shape F (under-consumed; under-consumed-by-LANG list).
   - 1 language consumes, no Class 2 twin elsewhere → not under-consumed; the declaration is just legitimately mono-language.
   - Specific codegen target enabled in main.dox but its emitted symbols have 0 hits → Shape G (target-specific under-consumption). The fix is either consume or scope the target.
5. Rank Classes 1+2 by drift risk:
   - **Wire-crossing**: HTTP/WS boundaries with hand-written encoders on both sides. Drift = wire desync = silent runtime breakage. Highest.
   - **Persisted**: status enums on Ecto schemas that drift from TS rendering. Drift = display incorrectness, mis-classification, broken filters.
   - **Internal**: a function dispatcher mirroring an enum's members. Drift = stale UI when a new case is added but the dispatcher isn't updated.
   - **UI-local**: animation timelines / loading spinners. Drift mostly cosmetic.
6. Rank Class 3 by cost:
   - **High cost dead**: an entire `.dox` file with all consumers gone — keeping it loads paradox-ecto migrations, runs codegen every `paradox start`, and confuses readers.
   - **Medium**: individual unions/types within a still-needed `.dox` file that are themselves dead.
   - **Low**: lone unused helpers (`derive` calls, partial saturated sets).

## Output: `docs/audits/paradox-fsm-overlaps-<YYYY-MM-DD>.md`

Sections:

### 1. Headline
- Class 1 (FSM) clusters found
- Class 2 (mirroring) candidates found, split by Shape A / B / C / D
- Class 3 (dead / under-consumed paradox) findings, split by Shape E / F / G
- Already-in-Paradox declarations referenced (the healthy baseline)
- Total LOC the consolidation would remove (Classes 1+2) + total `.dox` LOC removable (Class 3 Shape E)

### 2. FSM cluster table
| Domain | Elixir | Haskell | TypeScript | Drift risk | Existing Paradox? |
|---|---|---|---|---|---|

### 3. Mirroring candidate table
| Shape | What | Elixir | Haskell | TypeScript | `.dox` source | Drift risk |
|---|---|---|---|---|---|---|

Shape column is A/B/C/D per the definitions above.

### 4. Dead / under-consumed paradox table
| Shape | `.dox` declaration | Codegen targets enabled | Consumed by | Cost |
|---|---|---|---|---|

Shape column is E/F/G. "Consumed by" lists which languages have non-zero references (or "none" for Shape E).

### 5. Per-FSM-cluster detail
For each Class 1 cluster, in order of drift risk descending:
- **Domain**: what does this FSM model? (one sentence)
- **Current implementations**: file:line citations across all three languages
- **Status / event vocabulary**: actual names found, grouped by which match cross-language and which drift
- **Proposed Paradox shape**: sketch of the `.dox` declaration (states, events, transitions) following the existing `evaluation_fsm.dox` / `job_fsm.dox` pattern
- **Migration cost**: rough estimate of LOC removed per language + new `.dox` LOC added
- **Why it's worth it**: which specific drift bug class disappears

### 6. Per-mirroring-cluster detail
For each Class 2 candidate, in order of drift risk descending:
- **Shape** (A/B/C/D)
- **What it represents**: one sentence
- **Hand-written copies**: file:line per language + the literal member set each carries
- **Existing `.dox`** (if Shape A): path + line of the union/type — and what's stale on the hand-written side (extra members, missing members, renamed members)
- **Proposed `.dox`** (if Shape B): sketch of the union/type + which codegen targets to enable in `main.dox`
- **Wire-format observability** (if Shape C): the actual wire string the hand-written code emits vs what Paradox's `to_json` produces
- **Migration cost**: LOC removed per language + (for Shape B) new `.dox` LOC

### 7. Per-dead/under-consumed detail
For each Class 3 finding, in order of cost descending:
- **Shape** (E/F/G)
- **Declaration**: name + `domain/x.dox:line`
- **Codegen targets enabled** for it in `main.dox`
- **Expected emitted symbols** per target
- **Reference search result**: per target — the symbols' hit count across the language's source tree, with the top 3 file:line hits if any, or "0 hits" if none
- **Verdict** (Shape E): safe to delete? If not, what still references the generated output (introspection? migrations? test fixtures?). If yes, the deletion includes which `.dox` lines and which generated files become unnecessary.
- **Verdict** (Shape F): which languages need to switch from hand-written twin → paradox import. Cross-reference the Class 2 Shape A entry that proves the twin exists.
- **Verdict** (Shape G): scope the codegen target down OR consume it. Pick one.

### 8. Paradox feature gaps
For candidates where Paradox can't yet represent the shape cleanly (effectful transitions, hierarchical states, parallel regions, runtime-parameterised unions, etc.) — describe what would need to land in `/home/isaac/_/paradox/live` to unblock. Cite the candidate that surfaced the gap.

### 9. Non-candidates
Hand-written code that LOOKS like mirroring but legitimately should NOT consolidate. Examples that belong here:
- Animation timelines / loading spinners local to one UI hook (UI-only, no domain meaning).
- F\*-verified state in star-beam where proof obligations matter more than wire sharing.
- Tooling-internal types (e.g. compiler intermediate forms, test fixtures, debugging helpers).
- Hand-written types in third-party stub files / type declarations for vendored deps.
- `.dox` declarations consumed in only one language where that's the right answer (e.g. ecto-only migration shapes that genuinely have no TS analogue).

Brief justification each.

## Rules

- This is a SURVEY pass. Do not edit SUT files. The deliverable is the markdown + the agent inventories.
- Commit the markdown to `docs/audits/paradox-fsm-overlaps-<YYYY-MM-DD>.md` with `--no-gpg-sign`. Per-language inventories AND consumption indexes go in `docs/audits/paradox-fsm-overlaps-<YYYY-MM-DD>/{elixir,haskell,typescript,paradox,elixir-consumes,haskell-consumes,typescript-consumes,paradox-emitted-symbols}.json`.
- Cite file:line everywhere. No vague "X module has a state machine" or "TS has a status type."
- If you find an obvious bug along the way (e.g. Elixir handles event X but TS doesn't — silent state desync, or a hand-written copy is one member short of the `.dox` source, or a `.dox` union has one member nothing anywhere references) surface it explicitly. Don't fix it; surface it.
- Do not parallelize the SYNTHESIS pass. Inventories run in parallel, synthesis is one agent reading all of them.
- When citing a hand-written shape that overlaps a `.dox` definition, include BOTH file:line citations side-by-side so the reader can see the divergence without rereading either file.
- Class 3 Shape E findings must include a verdict on whether deletion is safe. Don't just list "0 references" — check for introspection (`Code.ensure_loaded?`, `apply/3` with module-as-data), test fixtures, migration references, and serialised data that might depend on the shape even when no source code does.

## Out of scope

- Rewriting any FSM or union into Paradox, or deleting any `.dox` declaration. That's a follow-up (`/address-findings` or a feature-shaped task).
- Paradox upstream patches. Surface gaps; the actual work lives in `/home/isaac/_/paradox/live`.
- Adding new `.dox` codegen targets (e.g. enabling `--haskell` if it's gated). Surface the need; don't enable.
- Non-domain duplication: utility helpers, formatting code, framework glue. The skill targets domain shapes — types, transitions, validations, wire formats.

End with a short summary message including the markdown path, the FSM cluster count, the mirroring candidate count (split by shape A/B/C/D), and the dead/under-consumed paradox count (split by shape E/F/G).
