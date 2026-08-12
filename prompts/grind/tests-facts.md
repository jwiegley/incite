## Probe first

Before you read anything else, run these two commands from the current working
directory:

```bash
ls domain/
ls test/
```

Both paths must exist and must not be empty. If either one is absent, stop. Do
not search for the tree somewhere else, and do not report that you found no
problems. Emit this line, alone, as your whole answer:

`FACTS PATHS UNRESOLVED: domain/ or test/ is missing from the working directory. This is not a checkout root of the target project, so every path below names nothing and this audit cannot run.`

An audit that reads no files reports no findings, and a clean suite reports no
findings too. That line is what tells the two apart.

## Project facts

The project is an Elixir/Phoenix/TypeScript/F* application. The OTP app is
`operation`, its web namespace is `OperationWeb`, and every path below is
relative to the working directory you just probed.

- Every build and test command runs inside the project dev shell. Start it once
  with `nix develop`, and work in that shell. If your tools give you no shell
  that persists, put `nix develop --command bash -c '<command>'` around each
  command instead.
- Elixir tests: ExUnit, run with `mix test <path>` while you work and `mix
  test` for the whole suite. Browser tests use Wallaby with `css()` selectors
  and live under `test/operation_web/features/`; the `OperationWeb.Ids` module
  supplies stable DOM ids, and `find lib -name ids.ex` locates it. Shared test
  helpers, factories and case templates live under `test/support/`
  (`OperationWeb.ConnCase`, `OperationWeb.FeatureCase`).
- TypeScript tests: Vitest, run with `cd assets && npx vitest run <path>`.
  TypeScript test files live under `assets/test/` and `frontend/test/`;
  production TypeScript lives under `assets/ts/`.
- Coverage: `excoveralls` on the Elixir side with a 90% minimum — `mix
  coveralls.html` writes `cover/excoveralls.html` — and `@vitest/coverage-v8`
  on the TypeScript side, via `npm run test:coverage` or `npx vitest run
  --coverage`.
- Property testing: `StreamData` with `use ExUnitProperties` and `check all` on
  the Elixir side; `fast-check` with `fc.property` on the TypeScript side.
- Mutation testing: `muex` on the Elixir side — read its recorded audit at
  `muex-web-audit.json`, and the dated `muex` reports under `docs/audits/` —
  and Stryker on the TypeScript side, via `npm run mutate`, with recorded
  reports under `assets/`. A survived mutation is a code change no test
  noticed.
- Formal verification: F* modules in `fstar/*.fst` prove invariants for the
  state machines (CI, dev sessions, group access), crypto helpers, the retry
  policy and HTML sanitization. Elixir calls them through `apply/3`.
- Code generation: `.dox` files under `domain/` are the source of truth.
  Paradox generates Elixir under `.dox/lib/` and TypeScript under `.dox/ts/`,
  in the `Dox.*` namespace. Never audit generated output for style, and never
  edit it by hand — a change that generated code needs is a change to the
  `.dox` source, regenerated.
- Wire strings such as `"pending"`, `"running"`, `"succeeded"`, `"failed"`,
  `"cancelled"`, `"evaluating"` and `"evaluated"` are generated from `domain/`
  union types. A hand-written copy of one of those unions, or a constant map
  keyed by its members, is drift waiting to happen.
- Compile check: `mix compile --warnings-as-errors`. For a pure deletion, that
  compile is the whole verification.
- Async test replacement signals, in place of a sleep: `assert_receive` on a
  Phoenix PubSub broadcast or a process message, a Wallaby `assert_has` retry
  for a LiveView re-render, a mocked animation completion callback (GSAP
  `onComplete`), or a `Repo.get` poll for a database write.
- Style: well-typed, purely functional — a pure core, immutable data, side
  effects at the edges. Avoid a new module where an existing one fits.

## Repair disciplines

Every fact above holds while you repair this suite. These are additional, and
none is a fact about the project.

- The fix hierarchy is fixed: a finding about generated code is repaired in the
  `.dox` source under `domain/` and regenerated; an invariant worth proving
  goes into an `fstar/` module called through `apply/3`; direct Elixir or
  TypeScript is for the cases neither covers.
- Never weaken a test assertion to make it pass. Fix the code, or write the
  stronger test the finding asks for.
- A fix without a test that pins it is half a fix. Write the pinning test, and
  run the one command that proves it.
- On a transient compile lock from a concurrent build, wait a moment and retry.
  Three attempts, then report the lock.
