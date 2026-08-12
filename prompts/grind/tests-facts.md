## Probe first

Before you read anything else, establish that you are standing in the target
project's checkout root and that there is a suite here to grind:

```bash
ls -d .git flake.nix
git ls-files
```

The first command must succeed for both paths. The second must list at least
one path that marks a test: a `test/`, `tests/` or `spec/` directory, a file
named `*_test.*`, `*_spec.*`, `*.test.*` or `*.spec.*`, or whatever suite path
this project's own build configuration names. A missing `.git` means this is
not a checkout root. No test path means there is no suite to audit. A missing
`flake.nix` means the run's own gate — `nix flake check` — cannot run at all,
so the whole grind would end red for a reason no repair could fix. On any of
the three, stop. Do not search for the tree somewhere else, and do not report
that you found no problems. Emit this line, alone, as your whole answer:

`FACTS PATHS UNRESOLVED: the working directory is not a checkout root with a flake and a test suite in it, so every path below names nothing and this audit cannot run.`

An audit that reads no files reports no findings, and a clean suite reports no
findings too. That line is what tells the two apart.

## Project facts

You are told nothing about this project. Every fact your lens needs — what the
language is, what runs the suite, where the tests live, whether there is a
coverage tool, a property library, a mutation runner, a browser driver, a
proof layer, a code generator — you establish yourself from the tree you just
probed, before you audit anything.

Read the build configuration first. It names the language, the suite and the
command that runs it: `mix.exs`, `package.json`, `*.cabal` or `stack.yaml`,
`Cargo.toml`, `pyproject.toml`, `go.mod`, `pom.xml`, `Gemfile`, `flake.nix`,
`Makefile`. A tree with several is several stacks, and each one owns a suite
you must find separately.

Settle these, in this order, and open your report with a short block saying
what you found and which file told you:

1. **The suite and its runner.** The exact command that runs one test file and
   the exact command that runs everything, as this project spells them.
2. **The dev shell, if any.** A `flake.nix` with a `devShells` output, a
   `shell.nix`, a `.envrc` or a container definition means the toolchain is
   not on your bare PATH. Run project commands inside it — `nix develop
   --command bash -c '<command>'` around each one where the shell is a flake
   and your tools give you no shell that persists.
3. **Coverage, property, mutation.** Whether each exists, what invokes it, and
   where it writes. A recorded report already in the tree is evidence; an
   absent tool is a fact about the project, not a gap for you to fill.
4. **Browser or integration tests.** The driver, where its tests live, and
   whether the codebase supplies a stable-identifier module for them.
5. **Generated code and its source of truth.** A generator's output directory,
   the schema or IDL it comes from, and the namespace it emits into. Never
   audit generated output for style.
6. **A formal-proof layer.** Proof modules, what they already prove, and how
   the application calls into them.
7. **The compile check, and the gate behind you.** The command that fails on a
   warning, where the project has one — for a pure deletion, that compile is
   the whole verification. The run itself ends on `nix flake check`, which the
   harness runs and reads the exit code of rather than taking your word for.
   A project whose flake check does not run its suite gates on less than you
   audited: say so in your report, because it is a fact about this tree that
   changes what the run's green means.

Two rules about the facts you establish.

**Report what is absent as absent.** Your lens may ask about a layer this
project does not have — no mutation runner, no browser tests, no proofs. Say
so in one line, name the evidence that settles it, and stop. Do not propose
adopting the tool, and do not substitute a different subject. An absent layer
is a short block, and a short block is not an empty one: the synthesis refuses
on a lens that returned nothing at all, so answering is not optional.

**Cite what you read.** Every finding names a file and a line that exists in
this tree. A finding whose path you inferred from a convention rather than
read from the tree is the failure this probe exists to prevent.

Style, everywhere: well-typed and purely functional — a pure core, immutable
data, side effects at the edges. Prefer an existing module to a new one.

## Repair disciplines

Every fact you established above holds while you repair this suite. These are
additional, and none is a fact about the project.

- The fix hierarchy follows the source of truth you found: a finding about
  generated code is repaired in the schema it comes from and the output
  regenerated, never hand-patched; an invariant worth proving goes into the
  proof layer where the project has one; direct code is for the cases neither
  covers.
- Never weaken a test assertion to make it pass. Fix the code, or write the
  stronger test the finding asks for.
- A fix without a test that pins it is half a fix. Write the pinning test, and
  run the one command that proves it — the command you established above, not
  one you assume.
- On a transient build lock from a concurrent build, wait a moment and retry.
  Three attempts, then report the lock.
