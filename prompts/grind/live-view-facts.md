## Probe first

Before you read anything else, run these two commands from the current working
directory:

```bash
ls lib/operation_web/live/
ls domain/
```

Both paths must exist and must not be empty. If either one is absent, stop. Do
not search for the tree somewhere else, and do not report that you found no
problems. Emit this line, alone, as your whole answer:

`FACTS PATHS UNRESOLVED: lib/operation_web/live/ or domain/ is missing from the working directory. This is not a checkout root of the target project, so every path below names nothing and this audit cannot run.`

An audit that reads no files reports no findings, and a clean tree reports no
findings too. That line is what tells the two apart.

## Project facts

The project is an Elixir/Phoenix/TypeScript application. The OTP app is
`operation`, its web namespace is `OperationWeb`, and every path below is
relative to the working directory you just probed.

- Every build and test command runs inside the project dev shell. Start it once
  with `nix develop`, and work in that shell. If your tools give you no shell
  that persists, put `nix develop --command bash -c '<command>'` around each
  command instead.
- LiveViews live under `lib/operation_web/live/`. Function components and
  LiveComponents live under `lib/operation_web/components/`.
- PubSub topics are centralized in `lib/operation/topics.ex`. A topic string
  spelled anywhere else is a finding for whichever lens meets it.
- The `OperationWeb.Ids` module provides stable DOM ids; `find lib -name
  ids.ex` locates it. Templates and hooks locate elements through it rather
  than through raw string ids.
- TypeScript hooks live under `assets/ts/hooks/`, and the `PhxHook` union in
  `domain/ui/ui.dox` is their registry.
- Code generation: `.dox` files under `domain/` are the source of truth, and
  Paradox generates code under `.dox/lib/` and `.dox/ts/`. Never audit
  generated output for style; the fix hierarchy under Repair disciplines says
  where a change to it goes.
- Compile check: `mix compile --warnings-as-errors`. Tests: `mix test <path>`
  while you work, `mix test` for the whole suite. The suite runs in seconds,
  not minutes.
- Style: well-typed, purely functional — a pure core, immutable data, side
  effects at the edges. Match the surrounding code, and avoid a new module or
  file where an existing one fits.

## Repair disciplines

Every fact above holds while you repair this tree. These are additional, and
none is a fact about the project.

- A finding about generated code is repaired in its source under `domain/` and
  regenerated. A new TypeScript hook lands in `assets/ts/hooks/` AND in the
  `PhxHook` union — half a registration is a hook that never fires.
- Never weaken a test assertion to make it pass, and never leave a TODO or
  FIXME comment as a substitute for the work.
- A fix without a test that pins it is half a fix, where a test can pin it.
  Auth guards and pure logic can be pinned; write those tests. A markup-only
  change is proved by the compile.
- On a transient compile lock from a concurrent build, wait a moment and retry.
  Three attempts, then report the lock.
