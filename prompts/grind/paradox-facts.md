## Probe first

Before you read anything else, run these two commands from the current working
directory:

```bash
ls lib/src/Paradox/CodeGen/
ls lib/test/golden/CodeGen/
```

Both paths must exist and must not be empty. If either one is absent, stop. Do
not search for the tree somewhere else, and do not report that you found no
problems. Emit this line, alone, as your whole answer:

`FACTS PATHS UNRESOLVED: lib/src/Paradox/CodeGen/ or lib/test/golden/CodeGen/ is missing from the working directory. This is not a Paradox checkout root, so every path below names nothing and this audit cannot run.`

An audit that reads no files reports no findings, and a clean tree reports no
findings too. That line is what tells the two apart.

## Project facts

The project is the Paradox compiler: a Haskell domain-specification language
that compiles `.dox` files to many target languages. Every path below is
relative to the working directory you just probed.

- Build: `cabal build`. Tests: `./test.sh lib-tests -p '<pattern>'`. Always
  filter with `-p` while you work. Run the full suite only at the final gate.
- Golden tests: `lib/test/golden/` (`CodeGen/`, `Command/`, `Strap/`,
  `Evaluate/`, `LSP/`, `State/`, `DocTest/`). The order to regenerate one is
  fixed: fix the emitter, confirm the fix compiles, run
  `./test.sh lib-tests -p '<pattern>' --golden-reset`, then read the golden
  diff. Never hand-edit a golden output file, and never run `--golden-reset`
  before the emitter fix compiles.
- Codegen backends: `lib/src/Paradox/CodeGen/*.hs` (TypeScript, Haskell, Go,
  CSharp, Scala, Rust, Python, Java, OCaml, Elixir, Fstar, Cpp, JSON, YAML, Nix,
  Bash, PostgreSQL, SQLite, Css, HTML) plus `Command/`, `Rewrites.hs`,
  `Class.hs`.
- Pipeline: `Language.Paradox.Specification.*` (AST), `Paradox.Parse.*`,
  `Paradox.Strap.*` (type checking), `Paradox.Check`, `Paradox.Evaluation`,
  `Paradox.CodeGen.*`.
- `.dox` semantics: `type` is a product, `union` is a sum, `valid Type:
  conditions` are validation rules, `wrap` is a transparent newtype, `interface`
  resolves through the instance map at check time.
- CRITICAL: never add special `Expression` ADT constructors for interfaces. No
  `For` constructor, and no constructor like it. Interfaces resolve through
  normal application. This rule overrules any instinct to make the code smaller.
- Semantic gates exist for some targets. Go output must compile and must pass
  `go vet` (`nix/checks.nix`, `lib/test/Paradox/CodeGenSpec.hs`). A target with
  no gate is itself a test-gap finding.
- The compiler supports 20 target languages (the `TargetLanguage` enum):
  TypeScript, Haskell, Rust, Elixir, Python, Cpp, Scala, Csharp, Ocaml, Nix,
  BashLang, Java, Fstar, Golang, Json, Yaml, Html, Css, Sqlite, Postgresql.
  Every codegen target belongs in every test suite that runs per language. The
  suites are codegen-tests, eval-tests, strap-tests, parse-tests, state-tests,
  repl-tests, json-roundtrip-tests, atlas-tests, command-equiv (inside
  codegen-tests), and lsp-tests.
- Style: pure functional Haskell. Avoid a new module where an existing one
  fits. Orphan instances are fine here; silence the warning with
  `{-# OPTIONS_GHC -Wno-orphans #-}` rather than restructuring the code.

## Repair disciplines

Every fact above holds while you repair this tree. These two are additional, and
neither one is a fact about the project.

- A fix without a test that pins it is half a fix. Write the pinning test.
- On a `dist-newstyle` build lock, wait a moment and retry. Three attempts, then
  report the lock.
