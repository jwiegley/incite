You are the orchestrator of a comprehensive quality audit AND remediation of the Paradox compiler. The goal is not to find a handful of issues — it is to be *exhaustive*, and then to *fix everything found*. Every category below must be dispatched. The outputs are: a ranked findings report at `docs/audits/grind-paradox-<YYYY-MM-DD>.md`, a remediation TODO at `docs/audits/grind-paradox-<YYYY-MM-DD>-todo.md`, and a working tree where EVERY finding has been addressed by fix subagents — no exceptions, no deferrals. The workflow moves from audit to remediation automatically; do not stop for confirmation between phases. Nothing is committed; the user reviews the dirty tree.

Before launching the Workflow, run `pwd` in the Bash tool to capture the current working directory. Pass that path as `args: { root: "<result>" }` when invoking the Workflow tool. Do not perform any research yourself before launching the workflow — the agents will do that work.

The project is the Paradox compiler: a Haskell domain-specification language that compiles `.dox` files to many target languages. Key facts the agents need:
- Build: `cabal build` (fast type check). Full CI-equivalent: `nix flake check` (remote builder, 105 cores) — use only as a final gate, never for iteration.
- Tests: `./test.sh lib-tests` from the repo root. ALWAYS filter with `-p '<pattern>'` during iteration — never run the unfiltered suite except at the final gate.
- Golden tests live in `lib/test/golden/` (CodeGen/, Command/, Strap/, Evaluate/, LSP/, State/, DocTest/). Regenerate with `./test.sh lib-tests -p '<pattern>' --golden-reset` ONLY after fixing the generator and ONLY after reviewing that the new output is correct. NEVER hand-edit golden output files to make a test pass.
- Codegen backends: `lib/src/Paradox/CodeGen/{TypeScript,Haskell,Go,CSharp,Scala,Rust,Python,Java,OCaml,Elixir,Fstar,Cpp,JSON,YAML,Nix,Bash,PostgreSQL,SQLite,Css,HTML}.hs` plus `Command/` and `Rewrites.hs`/`Class.hs` shared machinery.
- Compiler pipeline: `Language.Paradox.Specification.*` (AST/types), `Paradox.Parse.*`, `Paradox.Strap.*` (type checking/validation), `Paradox.Check`, `Paradox.Evaluation`, `Paradox.CodeGen.*` (emission).
- `.dox` semantics: `type` = product, `union` = sum, `valid Type: conditions` = runtime validation rules, `wrap` = newtype with transparent serialization, `interface` = resolved at type-check time via the instance map.
- CRITICAL invariant: NEVER add special Expression ADT constructors for interfaces (no `For` etc.). Interfaces resolve through normal application + instance lookup. This rule overrides any "simplification" instinct.
- Some targets have semantic gates (e.g. Go: generated output must compile and pass `go vet` — see `nix/checks.nix` and `lib/test/Paradox/CodeGenSpec.hs`). Fixes must keep these green; missing gates for other targets are themselves test-gap findings.
- Style: well-typed, purely functional Haskell. Pure core, effects at the edges. Avoid new modules when an existing one fits. If an orphan-instance warning blocks a build, silence it with `{-# OPTIONS_GHC -Wno-orphans #-}` — orphan instances are fine here.

Launch this Workflow script verbatim:

```javascript
export const meta = {
  name: 'grind-paradox',
  description: 'Fan-out Paradox compiler quality audit across 13 parallel agents, synthesize ranked findings report, then remediate every finding',
  phases: [
    { title: 'Audit' },
    { title: 'Synthesize' },
    { title: 'Plan', detail: 'build remediation TODO from all findings, double-check completeness' },
    { title: 'Fix', detail: 'one fix agent per disjoint file bucket — every item, no exceptions' },
    { title: 'Verify', detail: 'adversarially verify each fix, repair stragglers, gate on compile + full suite' },
  ],
}

const ROOT = args && args.root ? args.root : '.'

const FACTS = `
Project facts (Paradox compiler, Haskell, at ${ROOT}):
- Build: cabal build. Tests: ./test.sh lib-tests -p '<pattern>' (ALWAYS filter with -p; full suite only at the final gate).
- Golden tests: ${ROOT}/lib/test/golden/ (CodeGen/, Command/, Strap/, Evaluate/, LSP/, State/, DocTest/). Regenerate with ./test.sh lib-tests -p '<pattern>' --golden-reset ONLY after the generator is fixed and the new output reviewed. NEVER hand-edit golden outputs.
- Codegen backends: ${ROOT}/lib/src/Paradox/CodeGen/*.hs (TypeScript, Haskell, Go, CSharp, Scala, Rust, Python, Java, OCaml, Elixir, Fstar, Cpp, JSON, YAML, Nix, Bash, PostgreSQL, SQLite, Css, HTML) plus Command/, Rewrites.hs, Class.hs.
- Pipeline: Language.Paradox.Specification.* (AST), Paradox.Parse.*, Paradox.Strap.* (type checking), Paradox.Check, Paradox.Evaluation, Paradox.CodeGen.*.
- .dox semantics: type = product, union = sum, valid Type: conditions = validation rules, wrap = transparent newtype, interface = resolved via instance map at check time.
- CRITICAL: never add special Expression ADT constructors for interfaces (no For etc.) — interfaces resolve through normal application.
- Semantic gates exist for some targets (Go: generated code must compile + pass go vet — nix/checks.nix, lib/test/Paradox/CodeGenSpec.hs).
- Style: pure functional Haskell; avoid new modules when an existing one fits; orphan instances OK with -Wno-orphans.
`

const STUBS_SKIPS = `
You are auditing for STUBS, SKIPS, TODOs, AND TEST GAPS in the Paradox compiler at ${ROOT}.
${FACTS}
Search for:
1. Skipped/pending tests:
   grep -rn "pendingWith\\|pending\\b\\|xit \\|xdescribe\\|xcontext" ${ROOT}/lib/test --include="*.hs" 2>/dev/null
2. TODOs/FIXMEs/stubs in production and test code:
   grep -rn "TODO\\|FIXME\\|XXX\\|HACK\\|undefined\\b\\|error \\"not\\|error \\"unimplemented\\|error \\"unsupported" ${ROOT}/lib/src ${ROOT}/lib/test --include="*.hs" 2>/dev/null
3. Catch-all fallbacks in codegen that silently swallow constructs:
   grep -rn "_ -> \\"\\"\\|_ -> mempty\\|_ -> pure ()\\|_ -> \\[\\]" ${ROOT}/lib/src/Paradox/CodeGen --include="*.hs" 2>/dev/null
4. TODO/placeholder text leaking INTO generated output — grep the golden files themselves:
   grep -rn "TODO\\|FIXME\\|unimplemented\\|not implemented" ${ROOT}/lib/test/golden 2>/dev/null | head -60
5. Golden test cases that exist for some targets but are missing for others: list ${ROOT}/lib/test/golden/CodeGen/*/ and compare which target extensions exist per case; read lib/test/Paradox/CodeGenSpec.hs to see which targets each case runs against.

For each finding report: file:line, what it is, whether it represents real debt or is legitimately intentional, and the concrete fill-in (test body, implementation, or golden case to add).

Return a JSON array of findings:
[{
  "type": "skip|todo|stub|swallowed_construct|leaked_placeholder|missing_golden",
  "file": "lib/...",
  "line": 42,
  "description": "...",
  "intentional": true|false,
  "action": "... concrete fix ..."
}]
`

const VACUOUS = `
You are auditing for VACUOUS TESTS in the Paradox compiler at ${ROOT} — and you must propose the improved replacement for each.
${FACTS}
A vacuous test:
- Always passes regardless of implementation (shouldBe True, x \`shouldBe\` x, shouldSatisfy (const True))
- Only checks that code does not crash / parses / returns *something*, not that the output is right
- Asserts only on length, non-emptiness, or isRight/isJust where the payload is what matters
- Is a tautology (encode (decode x) == encode (decode x))
- Has a golden file that is empty, near-empty, or contains an error message that the test treats as success
- Covers only the happy path of logic whose danger is the edge cases

Search ALL test files under ${ROOT}/lib/test/ (CodeGenSpec, StrapSpec, EvaluationSpec, JSONRoundtripSpec, CommandsSpec, CommandEquivSpec, HooksSpec, SourceMapSpec, LSP, Repl, ...). Also inspect golden files for trivial/empty expected outputs.

For each suspected vacuous test:
1. REPRODUCE: run it filtered (./test.sh lib-tests -p '<pattern>') — it should pass.
2. SABOTAGE: break the production code it claims to test (flip a conditional, return mempty, swap a branch in the relevant CodeGen module). Re-run. If it STILL PASSES, it is confirmed vacuous. REVERT the sabotage. Document the experiment.
3. Propose a concrete improved test body (or stronger golden case) that catches the sabotage.

Return JSON:
[{
  "file": "lib/test/...",
  "test_name": "...",
  "line": 42,
  "verdict": "vacuous|suspicious",
  "reason": "...",
  "sabotage_survived": true|false,
  "improved_test": "... haskell code or golden-case description ..."
}]
`

const TARGET_CONSISTENCY = `
You are auditing for SEMANTIC INCONSISTENCIES BETWEEN TARGET LANGUAGES in the Paradox compiler at ${ROOT}.
${FACTS}
The same .dox source must mean the same thing in every emitted target. Find places where backends disagree.

Method:
1. Pick golden cases under ${ROOT}/lib/test/golden/CodeGen/ that have outputs for several targets (e.g. comprehensive, defaultValues, domainModel, ecommerce). Read each target's output for the SAME case side by side.
2. Compare semantics dimension by dimension:
   - Union/sum encoding: tag names, wire format, exhaustiveness of match/switch
   - Optional/nullable handling: is absence None/null/undefined/pointer-nil consistently? Default values applied identically?
   - wrap types: transparent serialization in every target?
   - Validation: does every target emit AND invoke the same valid-rules, accumulating errors the same way?
   - Numeric semantics: integer division, rounding, overflow width (int vs long vs bigint)
   - String escaping and unicode in literals
   - Empty collection handling, map/array iteration order assumptions
   - Field/constructor naming conventions (drift beyond idiomatic casing is a bug)
3. Then diff the BACKENDS THEMSELVES: for an AST construct handled in one CodeGen module, check the analogous handler in the others (grep the constructor name across ${ROOT}/lib/src/Paradox/CodeGen/*.hs). A construct handled in TypeScript.hs but falling to a catch-all in Go.hs is a finding.

For each inconsistency: cite the golden files and/or backend code lines, state which behavior is CORRECT (per the Haskell backend or the .dox semantics), and the concrete repair in the deviating backend(s).

Return JSON:
[{
  "dimension": "union_encoding|optional|wrap|validation|numeric|escaping|collections|naming|construct_gap",
  "dox_case": "lib/test/golden/CodeGen/<case>",
  "correct_target": "haskell",
  "deviating_targets": ["go", "scala"],
  "evidence": ["file:line", ...],
  "repair": "... concrete change in CodeGen/<X>.hs ...",
  "value": "high|medium"
}]
`

const DRY = `
You are auditing for DRY VIOLATIONS in the Paradox compiler at ${ROOT}. Rule of thumb: repeated 3+ times = centralize it, no matter how small.
${FACTS}
The 20 CodeGen backends are the prime suspect — they grew by copy-paste. Search for:
1. Identical or near-identical helper functions across ${ROOT}/lib/src/Paradox/CodeGen/*.hs (indentation helpers, name sanitizers, reserved-word escapers, camel/snake casing, comma-joining, parenthesization, type-variable rendering). Use grep on function names and on distinctive expression bodies.
2. Repeated case-analysis skeletons over the same AST constructors where only the rendered syntax differs — extract the shared traversal into Class.hs/Rewrites.hs or another EXISTING shared module (avoid new modules when possible).
3. Repeated literal tables: reserved-word lists, builtin-type mappings, escape tables duplicated per backend.
4. In tests: repeated setup/compile/compare boilerplate across spec files that should be one helper; repeated .dox fixture snippets pasted into multiple tests.
5. Repeated string constants 3+ times anywhere in lib/src (grep for distinctive literals, sort | uniq -c).

For each violation: cite ALL occurrences (3+ file:line), and write the centralized form — which existing module it lands in and the call-site rewrite.

Return JSON:
[{
  "pattern": "...",
  "occurrences": [{"file": "lib/src/...", "line": 42}, ...],
  "proposed_centralization": "... haskell code + target module ...",
  "value": "high|medium"
}]
`

const HARDCODINGS = `
You are auditing for INAPPROPRIATE HARDCODINGS in the Paradox compiler at ${ROOT}.
${FACTS}
Look for values baked in where they should be derived, configured, or centralized:
1. Magic numbers (column widths, indent sizes, buffer sizes, arbitrary limits) inline instead of named constants:
   grep -rnE "[^0-9][0-9]{2,}[^0-9]" ${ROOT}/lib/src/Paradox --include="*.hs" | grep -v test | head -80 — then judge each.
2. Hardcoded paths, file extensions, package/module names that must track the target list (a new backend should not require hunting string literals):
   grep -rn '"\\.ts"\\|"\\.hs"\\|"\\.go"\\|"\\.cs"\\|"\\.scala"\\|"\\.py"\\|"\\.rs"' ${ROOT}/lib/src --include="*.hs" 2>/dev/null | head -60
3. Hardcoded lists of target languages or per-target dispatch tables duplicated in more than one place (Target.hs should be the single source — check Commands.hs, Repl.hs, DemoteLang, CodeGenSpec.hs all derive from it rather than re-listing).
4. Hardcoded identifiers in generated output that should come from the .dox source or a naming function (prefixes, suffixes, package names).
5. In tests: hardcoded expected counts, version strings, dates, or absolute paths that will rot.

For each: file:line, why it is inappropriate (what change breaks it silently), and where the value should live instead.

Return JSON:
[{
  "file": "lib/...",
  "line": 42,
  "hardcoded": "...",
  "breaks_when": "...",
  "should_live_in": "...",
  "value": "high|medium"
}]
`

const VALIDATORS = `
You are auditing for MISSED VALIDATOR CALLS IN GENERATED CODE in the Paradox compiler at ${ROOT}.
${FACTS}
.dox 'valid Type: conditions' rules generate validator functions per target (e.g. validateFoo in Scala/C#, accumulating []string errs in Go). The validators existing is not enough — generated code must CALL them at the trust boundaries.

Method:
1. Read how each backend emits validators: grep -rn "valid" ${ROOT}/lib/src/Paradox/CodeGen/*.hs | head -60, then read the relevant emitters.
2. For golden cases that include 'valid' rules (grep -rln "^valid\\|valid " ${ROOT}/lib/test/golden/CodeGen/*/ and example/ for the source .dox), read the generated output per target and check:
   - Decoders/deserializers: is the validator invoked after decode, in EVERY target that has decoders?
   - Constructors/smart constructors: can a caller build an invalid value without ever touching the validator?
   - wrap types with valid rules: is unwrapping/constructing validated?
   - Parametric products: are validators emitted with the right type parameters AND called?
3. Compare targets: if the Haskell or TypeScript output validates on decode but another target does not, that is both a missed-validator finding and a consistency bug — report it here with the repair.
4. Also check the validators themselves are reachable: an emitted-but-never-called validator in every target means the wiring step is missing in the shared emission logic.

Return JSON:
[{
  "target": "go|scala|csharp|...|all",
  "dox_case": "lib/test/golden/CodeGen/<case>",
  "site": "decoder|constructor|wrap|other",
  "evidence": "file:line of generated output lacking the call",
  "repair": "... change in CodeGen/<X>.hs + which golden cases regenerate ...",
  "value": "high|medium"
}]
`

const REFACTOR = `
You are auditing for HIGH-VALUE REFACTOR OPPORTUNITIES in the Paradox compiler at ${ROOT}.
${FACTS}
Not refactoring for its own sake — every suggestion must pay rent: enable a test that cannot currently be written, collapse a class of future bugs, or make adding the next backend/construct mechanically safe.

Look for:
1. PARTIAL FUNCTIONS and incomplete patterns in the pipeline: head/fromJust/irrefutable patterns/error calls reachable from user input. cabal build with -Wincomplete-patterns output is your friend.
2. STRINGLY-TYPED SEAMS: passing rendered code as String/Text between stages where a structured type (doc/AST) would prevent precedence and escaping bugs.
3. GOD FUNCTIONS: 100+ line case expressions in CodeGen modules mixing traversal, naming, and rendering — split pure naming/typing helpers from rendering.
4. BOOLEAN BLINDNESS / primitive obsession in Strap/Check signatures where a sum type would make illegal states unrepresentable.
5. DUPLICATED TRAVERSALS of the AST that could be one generic fold (but RESPECT the interface rule — no new Expression constructors).
6. Type-class or record-of-functions opportunities to make backends share a skeleton (Class.hs may already be the seam — extend it rather than inventing a parallel one).

For each: what breaks or cannot be tested today, the proposed signature/boundary change, and what new test it enables.

Return JSON:
[{
  "file": "lib/src/...",
  "function": "...",
  "line": 42,
  "anti_pattern": "partial|stringly|god_function|boolean_blindness|dup_traversal|missing_abstraction",
  "proposed_refactor": "...",
  "new_test_possible": "...",
  "value": "high|medium"
}]
`

const CODEGEN_GAPS = `
You are auditing for GAPS IN CODEGEN OUTPUT in the Paradox compiler at ${ROOT}.
${FACTS}
A gap = a .dox construct that some backend silently drops, mangles, or rejects while others handle it.

Method:
1. Enumerate the AST constructors (read Language.Paradox.Specification modules and the Expression/Type ADTs).
2. For each backend in ${ROOT}/lib/src/Paradox/CodeGen/, grep each constructor name. Build the support matrix. Catch-all '_ ->' branches that emit nothing/comments/errors are gaps.
3. Cross-check against golden coverage: which constructs have NO golden case exercising them in a given target? (Read lib/test/Paradox/CodeGenSpec.hs for the case-to-target wiring.)
4. Check feature parity for: interfaces/instance resolution, lambdas/closures, pattern matching depth, generics/parametric types, defaults, recursion, map/filter/for rewrites (Rewrites.hs), CSS/HTML/SQL special targets only need their own domain.
5. Write a tiny .dox probe in /tmp for any suspected gap and run the CLI (cabal run paradox -- generate --<target>) to confirm what actually happens — silent wrong output is worse than an error.

For each gap: construct, backend, current behavior (silent drop / error / wrong output), the correct emission (cite how the best existing backend does it), and the golden case that should pin it.

Return JSON:
[{
  "construct": "...",
  "target": "go|rust|...",
  "behavior": "silent_drop|error|wrong_output",
  "evidence": "file:line or CLI output",
  "correct_emission": "... cite reference backend ...",
  "golden_case_needed": "...",
  "value": "high|medium"
}]
`

const TEST_GAPS = `
You are auditing for HIGH-VALUE TEST GAPS in the Paradox compiler at ${ROOT}.
${FACTS}
"High value" = the missing test guards a path where a wrong answer ships silently. Not coverage for coverage's sake.

Look for:
1. SEMANTIC GATES: Go golden output is gated on compiling + go vet (nix/checks.nix, CodeGenSpec.hs). Which other targets emit real code but have NO compile gate (TypeScript via tsc, C# via dotnet, Scala via scalac, Python via py_compile, Rust via rustc...)? Each missing gate that is feasible in the nix env is a finding; check what compilers nix/checks.nix can reach.
2. ROUNDTRIP PROPERTIES: parse . print == id for .dox formatting; encode/decode roundtrips per target wire format (JSONRoundtripSpec exists — what types/targets does it miss?).
3. ERROR-PATH GOLDENS: malformed .dox inputs whose error messages are unpinned (Strap/ golden dir — what error classes have no case?).
4. PIPELINE PROPERTIES: type checking total on arbitrary parse trees (no crash), evaluation fuel-bounded, sourcemap positions valid.
5. NEW/RECENT features with thin coverage: check git log --oneline -30 for recently added constructs/backends, then check golden coverage for them.
6. Boundary inputs: empty .dox, unicode identifiers, deeply nested types, name collisions with target reserved words — is each pinned by a test per target?

For each gap: what bug class it leaves open, and the concrete test (spec body or golden case + which suite file it lands in).

Return JSON:
[{
  "kind": "semantic_gate|roundtrip|error_golden|property|recent_feature|boundary",
  "area": "...",
  "bug_class": "...",
  "proposed_test": "... concrete code or golden case ...",
  "suite_file": "lib/test/...",
  "value": "high|medium"
}]
`

const CORRECTNESS = `
You are auditing for CORRECTNESS ISSUES in the Paradox compiler at ${ROOT}. Real bugs, demonstrated, not style.
${FACTS}
Hunt in priority order:
1. ESCAPING: string literals from .dox flowing into target source — quotes, backslashes, newlines, unicode, target-specific escapes (e.g. Go backticks, Python triple quotes, SQL quoting). Write /tmp probes with hostile strings and run the CLI per target.
2. PRECEDENCE/ASSOCIATIVITY: emitted expressions missing parens — subtraction/division chains, mixed && and ||, lambda bodies, casts. Probe with arithmeticChain-like cases beyond what the golden covers.
3. NAME CAPTURE: .dox identifiers colliding with target reserved words, with generated helper names, or with each other after case-conversion (fooBar vs foo_bar both → FooBar).
4. NUMERIC: integer widths, division semantics, float formatting drift between targets.
5. TYPE CHECKER: unsound or incomplete instance resolution in Strap — can a program check but emit code that does not compile? Can two interfaces clash?
6. EVALUATION: Paradox.Evaluation divergence from emitted-code semantics for the same expression.
7. ORDERING: anywhere Map/Set iteration order leaks into output (nondeterministic golden churn) or into semantics.
Every claim must be REPRODUCED: a /tmp .dox probe + CLI run, or a failing test you wrote and then kept (marked appropriately) — never assert a bug from reading alone.

Return JSON:
[{
  "class": "escaping|precedence|name_capture|numeric|typechecker|evaluation|ordering",
  "file": "lib/src/...",
  "line": 42,
  "repro": "... .dox probe + observed vs expected output ...",
  "fix": "... concrete change ...",
  "pin_test": "... test/golden case that locks the fix ...",
  "value": "high|medium"
}]
`

const COMPILER_PERF = `
You are auditing for PERFORMANCE OPTIMIZATIONS in the Paradox compiler pipeline at ${ROOT}: parsing, type checking (Strap), compilation, and code emission.
${FACTS}
Look for algorithmic and idiomatic Haskell wins — evidence-based, not vibes:
1. Quadratic appends: ++ in folds/loops, String concatenation in emitters (should be Text/Builder):
   grep -rn "++" ${ROOT}/lib/src/Paradox --include="*.hs" | grep -v "import\\|--" | head -80, then judge hot paths.
2. Linear lookups in hot paths: lists used as maps (lookup over [(k,v)]), nub, elem over large lists — should be Map/Set/HashMap.
3. Repeated work: re-parsing, re-checking, or re-traversing the AST per target instead of once; instance-map rebuilt per query in Strap.
4. Laziness leaks: foldl instead of foldl', lazy state in checking loops, missing strictness on accumulator fields.
5. String vs Text vs Builder in CodeGen emitters — what type do they actually build, and where does it get concatenated?
6. MEASURE: build a large synthetic .dox in /tmp (hundreds of types/unions), time the CLI per stage if observable (check, then each generate target). Cite numbers before/after expectations. Note the profiling infrastructure in flake.nix exists if needed.
Optimizations must not change behavior — golden files must remain byte-identical (or the change is also a correctness finding to report separately).

Return JSON:
[{
  "stage": "parse|strap|check|evaluate|emit",
  "file": "lib/src/...",
  "line": 42,
  "issue": "quadratic_append|linear_lookup|repeated_work|laziness|string_type",
  "evidence": "... measurement or complexity argument ...",
  "fix": "... concrete change ...",
  "value": "high|medium"
}]
`

const GEN_CODE_PERF = `
You are auditing for TARGET-LANGUAGE-SPECIFIC OPTIMIZATIONS of the GENERATED code in the Paradox compiler at ${ROOT}.
${FACTS}
The emitted code should be what a competent native author would write. Read the golden outputs per target (lib/test/golden/CodeGen/*/) and the emitters, looking for:
1. Go: string concatenation in loops (want strings.Builder), maps/slices without capacity hints when size is known, unnecessary pointer indirection on small structs, fmt.Sprintf where simple concat works.
2. TypeScript/JS: repeated object spreads in folds, O(n^2) array concat patterns, missing const, re-creating closures/regexes inside loops.
3. C#: LINQ chains re-enumerating, string += in loops (want StringBuilder), boxing of value types in validators.
4. Scala: List where Vector is right (memory says Vector is house style), repeated .toList/.toVector conversions, non-tail recursion in generated helpers.
5. Haskell output: String vs Text, lazy folds, missing bang patterns on accumulators.
6. Python/Java/Rust/OCaml: equivalent idiomatic wins (Rust: clone-happy code, String pushes; Java: StringBuilder; Python: += on str in loops).
7. Cross-cutting: validators that re-validate substructures redundantly; decoders that traverse input twice.
Each fix lands in the EMITTER (CodeGen/<X>.hs), then regenerate the affected goldens. Behavior must be identical — only the emitted idiom changes, and semantic gates (Go compile+vet) must stay green.

Return JSON:
[{
  "target": "go|typescript|...",
  "pattern": "...",
  "emitter": "lib/src/Paradox/CodeGen/<X>.hs:line",
  "golden_evidence": "lib/test/golden/CodeGen/<case>/...",
  "fix": "... emitter change ...",
  "value": "high|medium"
}]
`

const GEN_COMPILE_TIME = `
You are auditing for TARGET-SPECIFIC OPTIMIZATIONS THAT IMPROVE COMPILE TIMES of the GENERATED code, in the Paradox compiler at ${ROOT}.
${FACTS}
Generated code gets compiled by downstream users constantly — emitted-code compile time is a feature. Per target, inspect golden outputs and emitters for:
1. Haskell output: deriving more classes than needed, missing explicit export lists (forces more recompilation), one giant module where the target could split, unnecessary language extensions, INLINE pragmas (or their absence) — also orphan instances that force extra recompiles.
2. TypeScript: types that explode inference (deep conditional/mapped types, huge union literals where an enum/lookup is cheaper for tsc), missing 'interface' vs 'type' choices that affect checking cost, emitting one mega-file vs per-module.
3. Scala: implicit-heavy patterns that slow scalac, large match expressions the optimizer chokes on, unnecessary type ascriptions missing (inference cost).
4. C#: partial classes opportunity, excessive generic nesting.
5. Go: oversized single files, unused imports (gate already catches), unnecessary interface indirection.
6. Rust: monomorphization blowup from generics where dyn/&str would do, derive macros beyond what is needed.
7. Cross-cutting: import/include minimization — does every backend emit only the imports actually used?
Where measurable in the nix env, time the target compiler on a golden output before/after a hand-modified version to validate the win, THEN implement it in the emitter.

Return JSON:
[{
  "target": "haskell|typescript|...",
  "issue": "...",
  "emitter": "lib/src/Paradox/CodeGen/<X>.hs:line",
  "golden_evidence": "...",
  "measured_or_expected_win": "...",
  "fix": "... emitter change ...",
  "value": "high|medium"
}]
`

phase('Audit')
log('Launching 13 parallel audit agents...')

const [
  stubs,
  vacuous,
  consistency,
  dry,
  hardcodings,
  validators,
  refactor,
  codegenGaps,
  testGaps,
  correctness,
  compilerPerf,
  genCodePerf,
  genCompileTime,
] = await parallel([
  () => agent(STUBS_SKIPS, { label: 'stubs-skips-todos', phase: 'Audit' }),
  () => agent(VACUOUS, { label: 'vacuous-tests', phase: 'Audit' }),
  () => agent(TARGET_CONSISTENCY, { label: 'target-consistency', phase: 'Audit' }),
  () => agent(DRY, { label: 'dry-violations', phase: 'Audit' }),
  () => agent(HARDCODINGS, { label: 'hardcodings', phase: 'Audit' }),
  () => agent(VALIDATORS, { label: 'validator-calls', phase: 'Audit' }),
  () => agent(REFACTOR, { label: 'refactor-opportunities', phase: 'Audit' }),
  () => agent(CODEGEN_GAPS, { label: 'codegen-gaps', phase: 'Audit' }),
  () => agent(TEST_GAPS, { label: 'test-gaps', phase: 'Audit' }),
  () => agent(CORRECTNESS, { label: 'correctness', phase: 'Audit' }),
  () => agent(COMPILER_PERF, { label: 'compiler-perf', phase: 'Audit' }),
  () => agent(GEN_CODE_PERF, { label: 'gen-code-perf', phase: 'Audit' }),
  () => agent(GEN_COMPILE_TIME, { label: 'gen-compile-time', phase: 'Audit' }),
])

phase('Synthesize')
log('Synthesizing findings into ranked report...')

const SYNTHESIZE = `
You are the synthesis agent for a comprehensive quality audit of the Paradox compiler at ${ROOT}.

You have received findings from 13 audit agents. Synthesize them into a single ranked report. First run: date +%Y-%m-%d, then write the report to ${ROOT}/docs/audits/grind-paradox-<YYYY-MM-DD>.md (substitute the actual date; create docs/audits/ if needed).

The findings:

## STUBS / SKIPS / TODOS / TEST GAPS
${JSON.stringify(stubs || [])}

## VACUOUS TESTS
${JSON.stringify(vacuous || [])}

## CROSS-TARGET INCONSISTENCIES
${JSON.stringify(consistency || [])}

## DRY VIOLATIONS
${JSON.stringify(dry || [])}

## INAPPROPRIATE HARDCODINGS
${JSON.stringify(hardcodings || [])}

## MISSED VALIDATOR CALLS
${JSON.stringify(validators || [])}

## REFACTOR OPPORTUNITIES
${JSON.stringify(refactor || [])}

## CODEGEN OUTPUT GAPS
${JSON.stringify(codegenGaps || [])}

## HIGH-VALUE TEST GAPS
${JSON.stringify(testGaps || [])}

## CORRECTNESS ISSUES
${JSON.stringify(correctness || [])}

## COMPILER PIPELINE PERFORMANCE
${JSON.stringify(compilerPerf || [])}

## GENERATED-CODE PERFORMANCE
${JSON.stringify(genCodePerf || [])}

## GENERATED-CODE COMPILE TIME
${JSON.stringify(genCompileTime || [])}

Write the report with this structure:

# Paradox Grind Report

## Headline Numbers
- Total findings: X
- High-value findings: X
- (one line per category)

## Priority Queue (Top 25 Action Items)
Ranked by: 1) correctness risk (wrong generated code ships silently), 2) blast radius (how many targets/tests improve), 3) fix cost.
Each item:
### N. <short title>
**Category**: ...
**File**: path:line
**Impact**: one sentence
**Fix**: concrete code or precise instruction
---

## Full Findings by Category
One section per category; every finding gets file:line, description, and a CONCRETE fix — no "consider improving".

Rules:
- Deduplicate overlaps (a missed validator call reported by both the validators and consistency agents is ONE finding, cross-referenced).
- Findings touching the same CodeGen backend get grouped notes so fixers see the whole picture per file.
- If an agent returned null/empty, write "No findings" for that section.
- Write the file with the Write tool.

Return the absolute path of the report you wrote as report_path.
`

const synth = await agent(SYNTHESIZE, { label: 'synthesize', phase: 'Synthesize', schema: {
  type: 'object',
  required: ['report_path', 'total_findings'],
  properties: {
    report_path: { type: 'string' },
    total_findings: { type: 'number' },
  },
} })
const REPORT = synth && synth.report_path ? synth.report_path : `${ROOT}/docs/audits/`
const TODO_PATH = REPORT.replace(/\.md$/, '-todo.md')

// ============ PLAN ============
phase('Plan')
log('Building remediation TODO from every finding...')

const TODO_SCHEMA = {
  type: 'object',
  required: ['items'],
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'title', 'category', 'files', 'fix', 'verify'],
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          category: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          fix: { type: 'string' },
          verify: { type: 'string' },
        },
      },
    },
  },
}

const PLANNER = `
You are the remediation planner for a Paradox compiler quality audit of ${ROOT}.

Read the FULL audit report at ${REPORT} — every priority queue item AND every entry under "Full Findings by Category", not just the top 25.

Convert EVERY finding into a work item. No exceptions:
- Findings judged intentional still get an item (fix = "document the intent with a comment at the site").
- Medium-value findings are NOT skippable. Performance findings are NOT skippable.
- Merge findings that touch the same file into ONE work item so no file appears in two items (fixers run concurrently and must not collide). In this repo that especially means: all findings against the same CodeGen/<X>.hs become one item, and that item's files list includes EVERY golden directory its regeneration will touch (lib/test/golden/CodeGen/<case>/...). Treat lib/test/Paradox/CodeGenSpec.hs and nix/checks.nix as shared hot files — at most ONE item may list each.
- "files": EVERY existing file the fix will touch — emitters, pipeline modules, spec files, golden files/dirs, nix files. Be exhaustive; fixers may only touch listed files plus brand-new files they create.
- "fix": concrete instructions, embedding the report's code snippets verbatim where they exist. For codegen fixes always include: fix the emitter, then regenerate scoped goldens with ./test.sh lib-tests -p '<case-pattern>' --golden-reset, then REVIEW the golden diff for correctness.
- "verify": exact command(s), e.g. "./test.sh lib-tests -p 'CodeGen.go'" or "cabal build 2>&1 | tail -5". Always filtered — never the bare full suite.
- "id": short kebab slug, "category": the audit category.

Also Write the TODO as a human-readable checklist to ${TODO_PATH} (one "- [ ] id — title (files)" line per item).

Return JSON matching the schema.
`

const planned = await agent(PLANNER, { label: 'plan-todo', phase: 'Plan', schema: TODO_SCHEMA })
let items = (planned && planned.items) || []
log(`Planner produced ${items.length} work items — double-checking completeness...`)

for (let round = 1; round <= 3; round++) {
  const check = await agent(`
You are the completeness checker for a remediation plan. Read the audit report at ${REPORT} in full.

Here is the current TODO (id, title, category, files only):
${JSON.stringify(items.map(i => ({ id: i.id, title: i.title, category: i.category, files: i.files })))}

Go finding-by-finding through the ENTIRE report (priority queue AND full findings sections). For every finding NOT covered by any TODO item, produce a new work item in the same schema (id, title, category, files, fix with the report's code verbatim, verify command). If a finding shares files with an existing item but isn't plausibly covered by its title/fix, emit a new item with the same files — the orchestrator serializes overlapping items into later waves.

Return {"items": []} ONLY if literally every finding is covered.
`, { label: `check-todo-${round}`, phase: 'Plan', schema: TODO_SCHEMA })
  const missing = (check && check.items) || []
  if (missing.length === 0) { log(`Completeness check round ${round}: TODO is complete (${items.length} items)`); break }
  log(`Completeness check round ${round}: ${missing.length} uncovered findings — adding`)
  items = items.concat(missing)
}

// ============ FIX ============
phase('Fix')
log(`Dispatching fixers for ${items.length} work items in file-disjoint waves...`)

const FIX_RESULT = {
  type: 'object',
  required: ['id', 'status', 'notes'],
  properties: {
    id: { type: 'string' },
    status: { type: 'string', enum: ['fixed', 'blocked'] },
    notes: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
  },
}

const fixerPrompt = (item) => `
You are a fix agent for a Paradox compiler quality remediation at ${ROOT}. The full audit report is at ${REPORT}.
${FACTS}
WORK ITEM ${item.id}: ${item.title}
Category: ${item.category}
Files in scope: ${(item.files || []).join(', ')}
Fix instructions:
${item.fix}

Verification: ${item.verify}

Non-negotiable rules:
- Address the finding COMPLETELY. No skipping, no deferring, no watering down. "Pre-existing problem" and "out of scope" are not acceptable outcomes. Add tests where appropriate — a fix without a pinning test is half a fix.
- Codegen hierarchy: fix the EMITTER in lib/src/Paradox/CodeGen/, then regenerate affected goldens with ./test.sh lib-tests -p '<pattern>' --golden-reset, then READ the golden diff (git diff) and confirm every changed line is intended. NEVER hand-edit golden output files. NEVER --golden-reset before the emitter fix compiles.
- Never weaken a test assertion to make it pass. Never simplify a test to dodge a bug — fix the bug (this is house law).
- NEVER add special Expression ADT constructors for interfaces. Interfaces resolve via the instance map.
- Style: pure functional Haskell; avoid new modules when an existing one fits; orphan-instance warnings get OPTIONS_GHC -Wno-orphans, not restructuring.
- Touch ONLY the files listed above, plus brand-new files you create. Other fixers run concurrently on other files.
- Git is READ-ONLY for you: no commit, no reset, no stash, no checkout/restore of paths. The orchestrator owns the tree.
- The cabal build dir is shared. If you hit a dist-newstyle lock or "another process" error, wait briefly and retry — up to 3 times.
- Run the verification command (ALWAYS with -p filtering) and make it pass.
- "blocked" is permitted ONLY when the fix requires changes outside this repository; exhaust every in-repo option first and include a concrete unblock plan in notes.

Return JSON: {"id": "${item.id}", "status": "fixed|blocked", "notes": "...", "files_changed": ["..."]}
`

const runWaves = async (work) => {
  const results = []
  let queue = work.slice()
  let wave = 0
  while (queue.length > 0) {
    wave += 1
    const claimed = new Set()
    const now = []
    const later = []
    for (const it of queue) {
      const fs = it.files || []
      if (fs.some(f => claimed.has(f))) { later.push(it) } else { fs.forEach(f => claimed.add(f)); now.push(it) }
    }
    log(`Fix wave ${wave}: ${now.length} items running, ${later.length} deferred (file overlap)`)
    const res = await parallel(now.map(it => () => agent(fixerPrompt(it), { label: `fix:${it.id}`, phase: 'Fix', schema: FIX_RESULT })))
    results.push(...res.filter(Boolean))
    queue = later
  }
  return results
}

let fixResults = await runWaves(items)
const itemById = {}
items.forEach(i => { itemById[i.id] = i })

// ============ VERIFY ============
phase('Verify')
log('Adversarially verifying every fix...')

for (let round = 1; round <= 3; round++) {
  const verdicts = await parallel(fixResults.filter(r => r.status === 'fixed').map(r => () => agent(`
You are an adversarial verifier for the Paradox compiler at ${ROOT}. A fix agent claims it completed this work item:

${JSON.stringify(itemById[r.id] || r)}

Its claim: ${JSON.stringify(r)}

Try to REFUTE the claim. Read the actual files, run the verification command (${(itemById[r.id] || {}).verify || 'the item verify command'}), and check:
- the fix is real and complete (not a weakened assertion, not a deleted check, not a hand-edited golden file hiding an emitter bug — diff the goldens against what the emitter actually produces)
- a pinning test exists where the item called for one
- for codegen items: the golden diff is semantically correct, not just "tests pass"
Default to refuted=true if uncertain.

Return JSON: {"id": "${r.id}", "refuted": true|false, "reason": "..."}
`, { label: `verify:${r.id}`, phase: 'Verify', schema: {
    type: 'object', required: ['id', 'refuted', 'reason'],
    properties: { id: { type: 'string' }, refuted: { type: 'boolean' }, reason: { type: 'string' } },
  } })))
  const refuted = verdicts.filter(Boolean).filter(v => v.refuted)
  if (refuted.length === 0) { log(`Verify round ${round}: all fixes confirmed`); break }
  log(`Verify round ${round}: ${refuted.length} fixes refuted — re-dispatching with verifier feedback`)
  const rework = refuted.map(v => {
    const base = itemById[v.id] || { id: v.id, title: v.id, category: 'rework', files: [], verify: './test.sh lib-tests -p CodeGen' }
    return { ...base, fix: `${base.fix}\n\nPREVIOUS ATTEMPT WAS REFUTED BY A VERIFIER: ${v.reason}\nAddress the refutation fully.` }
  })
  const redone = await runWaves(rework)
  const redoneIds = new Set(redone.map(r => r.id))
  fixResults = fixResults.filter(r => !redoneIds.has(r.id)).concat(redone)
}

log('Gating on full compile + test suite...')
const gate = await agent(`
You are the final gate for a Paradox compiler quality remediation at ${ROOT}. Many fix agents have edited the tree.
${FACTS}
1. Run: cd ${ROOT} && cabal build 2>&1 | tail -30
2. Run: cd ${ROOT} && ./test.sh lib-tests 2>&1 | tail -60   (the ONE permitted unfiltered run)
3. Repair ANY failure: these are integration breaks between individually-verified fixes. Never weaken an assertion or hand-edit a golden; fix the actual conflict (emitter conflicts → re-fix emitter, then scoped --golden-reset, then review the diff). Re-run until green.
4. Sanity-check semantic gates still hold for targets that have them (Go compile + vet wiring in nix/checks.nix / CodeGenSpec.hs) — run the relevant filtered tests.
5. Update the TODO at ${TODO_PATH}: mark every completed item "- [x]", annotate blocked items with their unblock plans.
6. Append a "## Remediation" section to ${REPORT}: a table of work item id, title, status (fixed/blocked), files changed. Source rows from ${TODO_PATH}; use git -C ${ROOT} status --short and git -C ${ROOT} diff --stat for files changed. Do NOT commit anything.

Return JSON: {"suite_green": true|false, "summary": "what passed, what was repaired, anything still red and why"}
`, { label: 'final-gate', phase: 'Verify', schema: {
  type: 'object', required: ['suite_green', 'summary'],
  properties: { suite_green: { type: 'boolean' }, summary: { type: 'string' } },
} })

return {
  done: true,
  report: REPORT,
  todo: TODO_PATH,
  items: items.length,
  fixed: fixResults.filter(r => r.status === 'fixed').length,
  blocked: fixResults.filter(r => r.status === 'blocked').length,
  suite_green: gate ? gate.suite_green : null,
  gate_summary: gate ? gate.summary : 'gate agent returned null',
}
```

After the Workflow completes, read the generated report and TODO files and present a concise summary to the user: total findings, items fixed vs blocked (with unblock plans for blocked ones), whether the final compile + test gate is green, the top 5 priority items that were addressed, and the full paths to the report and TODO. Remind the user the tree is dirty and uncommitted for their review (suggest /commit when they're satisfied).
