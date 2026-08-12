> Retired Workflow-tool engine, kept as the back-out until the first paid runs of the `grind-tests` agent-functor workflow pass (see HANDOFF.md). The live `/grind-tests` command is `commands/grind-tests.md`. Delete this file when the paid runs pass.

You are the orchestrator of a comprehensive test quality audit AND remediation. The goal is not to find a handful of issues — it is to be *exhaustive*, and then to *fix everything found*. Every category below must be dispatched. The outputs are: a ranked findings report at `docs/audits/grind-tests-<YYYY-MM-DD>.md`, a remediation TODO at `docs/audits/grind-tests-<YYYY-MM-DD>-todo.md`, and a working tree where EVERY finding has been addressed by fix subagents — no exceptions, no deferrals. The workflow moves from audit to remediation automatically; do not stop for confirmation between phases. Nothing is committed; the user reviews the dirty tree.

Before launching the Workflow, run `pwd` in the Bash tool to capture the current working directory. Pass that path as `args: { root: "<result>" }` when invoking the Workflow tool. Do not perform any research yourself before launching the workflow — the agents will do that work.

The project is an Elixir/Phoenix/TypeScript/F* application. Key facts the agents need:
- Test runner: ExUnit + Wallaby (Elixir), Vitest + fast-check (TypeScript)
- Mutation testing: `muex` v0.6 (Elixir), Stryker v9.6 (`npm run mutate`) (TypeScript)
- Coverage: `excoveralls` (Elixir, min 90%), `@vitest/coverage-v8` (TypeScript, `npm run test:coverage`)
- Property testing: `StreamData` (Elixir), `fast-check` (TypeScript)
- Browser tests: Wallaby with `css()` selectors; `OperationWeb.Ids` module supplies stable IDs
- Formal verification: F* `.fst` modules in `fstar/`; called from Elixir via `apply/3`
- Paradox codegen: `.dox` files in `domain/` are source of truth; generated code in `.dox/lib/` and `.dox/ts/`
- OTP app name: `operation` / `OperationWeb`; generated namespace: `Dox.*`

Launch this Workflow script verbatim:

```javascript
export const meta = {
  name: 'grind-tests',
  description: 'Fan-out test quality audit across 12 parallel agents, synthesize ranked findings report, then remediate every finding',
  phases: [
    { title: 'Audit' },
    { title: 'Synthesize' },
    { title: 'Plan', detail: 'build remediation TODO from all findings, double-check completeness' },
    { title: 'Fix', detail: 'one fix agent per disjoint file bucket — every item, no exceptions' },
    { title: 'Verify', detail: 'adversarially verify each fix, repair stragglers, gate on compile + tests' },
  ],
}

const ROOT = args && args.root ? args.root : '.'

const VACUOUS = `
You are auditing for VACUOUS TESTS in an Elixir/Phoenix project at ${ROOT}.

A vacuous test is one that:
- Always passes regardless of implementation (assert true, assert is_map(%{}), assert x == x)
- Tests only that code does not crash, not that it does the right thing
- Has no assertion at all or only trivially-true assertions
- Asserts on the wrong thing (e.g. asserts the input value rather than the output)
- Is a tautology (assert encode(decode(x)) == encode(decode(x)) proves nothing)
- Tests a stub/mock instead of real behavior
- Has a single "happy path" assert where the real danger is the edge cases

Search ALL test files under ${ROOT}/test/ and ${ROOT}/assets/test/ and ${ROOT}/frontend/test/. For each vacuous test found:
1. REPRODUCE: run the test as-is (it should pass)
2. SABOTAGE: break the production code it claims to test (comment out the function body, flip a conditional, return nil). Re-run the test. If it STILL PASSES, it is confirmed vacuous. Document this experiment.
3. Propose a concrete improved test body that would actually catch the sabotaged code.

Return a JSON array of findings:
[{
  "file": "test/...",
  "test_name": "...",
  "line": 42,
  "verdict": "vacuous|suspicious",
  "reason": "...",
  "sabotage_survived": true|false,
  "improved_test": "... elixir/ts code ..."
}]
`

const COVERAGE = `
You are auditing CODE COVERAGE GAPS in an Elixir/Phoenix/TypeScript project at ${ROOT}.

Run the following and read the output:
  cd ${ROOT} && mix coveralls.html 2>&1 | tail -80
  cat ${ROOT}/cover/excoveralls.html 2>/dev/null | grep -A2 "low.*coverage\\|0%" | head -100

Also check TypeScript coverage:
  cd ${ROOT}/assets && npx vitest run --coverage 2>&1 | grep -E "Uncovered|\\| +[0-9]" | head -80

Identify the 15 highest-value gaps — modules where coverage is lowest AND the code path is non-trivial (not generated .dox/ code, not config/, not test support). "High value" means: the uncovered path is a branch that could produce a wrong answer in production, not just an error handler for an impossible case.

For each gap:
1. What lines are uncovered?
2. Why does it matter (what bug class does it leave open)?
3. What test would cover it? (sketch the test body)

Return JSON:
[{
  "module": "lib/...",
  "lines_uncovered": [12, 45, 67],
  "coverage_pct": 73,
  "value": "high|medium",
  "reason": "...",
  "proposed_test": "... code ..."
}]
`

const PROPERTY = `
You are auditing for MISSING PROPERTY TEST OPPORTUNITIES in an Elixir/Phoenix/TypeScript project at ${ROOT}.

Property tests (StreamData in Elixir, fast-check in TypeScript) shine when:
- A function has an algebraic law: encode(decode(x)) == x, sort(sort(x)) == sort(x), merge is associative
- The input space is large (arbitrary strings, integers, lists)
- A function has a known invariant regardless of input (output is always sorted, never negative, always a member of a known set)
- Two implementations of the same thing should always agree (a new fast path vs the old correct path)
- A parser must never crash (fuzz with arbitrary strings)

Read all existing property tests:
  grep -r "use ExUnitProperties\\|check all\\|StreamData\\|fast-check\\|fc\\.property\\|forAll" ${ROOT}/test ${ROOT}/assets/test ${ROOT}/frontend/test --include="*.exs" --include="*.ts" -l 2>/dev/null

Then read the production code under ${ROOT}/lib/ and ${ROOT}/assets/ts/ for pure functions that currently only have example-based tests but are ideal candidates. Focus on: parsers, encoders/decoders, state machine transitions, validation functions, sorting/ranking logic, ID generation, path manipulation.

Return JSON:
[{
  "function": "Operation.X.f/2",
  "file": "lib/...",
  "line": 42,
  "law": "round-trip|idempotent|monotone|total|invariant|...",
  "property_sketch": "... StreamData/fast-check code ...",
  "value": "high|medium"
}]
`

const MUTATION = `
You are auditing MUTATION TEST RESULTS for an Elixir/Phoenix/TypeScript project at ${ROOT}.

READ the existing mutation audit files first:
  cat ${ROOT}/muex-web-audit.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); [print(m['file'],m['line'],m['status']) for m in d.get('mutations',[])]" 2>/dev/null | grep -i "survived\\|escaped" | head -60
  ls ${ROOT}/docs/audits/ 2>/dev/null | grep muex | sort | tail -3 | xargs -I{} cat ${ROOT}/docs/audits/{} 2>/dev/null | head -200

Also check Stryker results if they exist:
  find ${ROOT}/assets -name "mutation-report*" -o -name "stryker-report*" 2>/dev/null | head -5

A survived mutation is a code change that DIDN'T break any test — meaning the test suite is blind to that change. Focus on survived mutations in CRITICAL paths: state transitions, access control checks, data validation, cryptographic helpers, parsing logic.

For each critical survived mutation:
1. What mutation survived? (e.g. "changed > to >=", "removed a guard clause")
2. What bug would this represent in production?
3. What test would kill it?

Return JSON:
[{
  "file": "lib/...",
  "line": 42,
  "mutation": "...",
  "production_bug": "...",
  "killing_test": "... code ...",
  "value": "high|medium"
}]
`

const STUBS_SKIPS = `
You are auditing for STUBS, SKIPS, FALLBACKS, and UNUSED CODE in an Elixir/Phoenix/TypeScript project at ${ROOT}.

Search for:
1. Skipped/pending tests:
   grep -rn "@tag :skip\\|skip()\\|:skip\\|pending\\|@moduletag :skip\\|xit(\\|xdescribe(\\|it.skip\\|describe.skip\\|test.skip" ${ROOT}/test ${ROOT}/assets/test ${ROOT}/frontend/test --include="*.exs" --include="*.ts" 2>/dev/null

2. Application.put_env stubs and process-dict overrides that might be hiding real behavior:
   grep -rn "Application.put_env\\|Process.put\\|:stub\\|stub_pid" ${ROOT}/test --include="*.exs" 2>/dev/null

3. Hardcoded stub return values that bypass the real implementation:
   grep -rn "fn _.*-> :ok\\|fn _.*-> nil\\|fn _.*-> \[\]\\|fn _.*-> %{}" ${ROOT}/test --include="*.exs" 2>/dev/null | grep -v "#"

4. Unused test support modules:
   ls ${ROOT}/test/support/ 2>/dev/null
   grep -rn "use.*Case\\|import.*Test\\|alias.*Factory" ${ROOT}/test --include="*.exs" 2>/dev/null | grep -oP "(?<=use |import |alias )[A-Za-z\\.]*" | sort | uniq -c | sort -rn | tail -20

5. Dead test helper functions (defined in test/support but never called):
   Look for functions in ${ROOT}/test/support/*.ex that are defined but grep shows zero calls in ${ROOT}/test/**/*.exs

For each finding report: file:line, what it is, and whether it represents real coverage debt or is legitimately intentional.

Return JSON:
[{
  "type": "skip|stub|fallback|dead_helper",
  "file": "test/...",
  "line": 42,
  "description": "...",
  "intentional": true|false,
  "action": "remove|replace_with_real_impl|document_intent"
}]
`

const SLEEPS = `
You are auditing for MAGIC TIMEOUTS and SLEEPS in the test suite of an Elixir/Phoenix/TypeScript project at ${ROOT}.

These are enemies of fast, deterministic tests. Every sleep is a lie — it says "wait X ms and hope the thing happened" instead of "wait for the thing to actually happen."

Find all of them:
  grep -rn "Process.sleep\\|:timer.sleep\\|setTimeout\\|setInterval\\|await new Promise.*resolve.*setTimeout\\|sleep(" ${ROOT}/test ${ROOT}/assets/test ${ROOT}/frontend/test --include="*.exs" --include="*.ts" -n 2>/dev/null

Also find magic numeric timeouts that are longer than the suite-wide defaults:
  grep -rn "assert_receive.*[0-9]\\{4,\\}\\|refute_receive.*[0-9]\\{4,\\}\\|timeout:.*[0-9]\\{4,\\}" ${ROOT}/test --include="*.exs" 2>/dev/null

For each sleep or magic timeout, identify:
1. WHY was it added — what async event is it waiting for?
2. What is the RIGHT signal to wait for instead? Options:
   - Phoenix PubSub broadcast (assert_receive)
   - LiveView re-render (Wallaby assert_has with retry)
   - Process message (assert_receive)
   - GSAP onComplete callback (mock)
   - Database mutation visible via poll (Repo.get with retry)
3. Write the replacement code.

Return JSON:
[{
  "file": "test/...",
  "line": 42,
  "sleep_ms": 300,
  "waiting_for": "...",
  "replacement": "... elixir/ts code ...",
  "value": "high|medium"
}]
`

const DOX_COPIES = `
You are auditing for HAND-WRITTEN COPIES OF .DOX GENERATED CODE in an Elixir/Phoenix/TypeScript project at ${ROOT}.

The rule: .dox files in domain/ are the source of truth. Paradox generates Elixir under .dox/lib/, TypeScript under .dox/ts/ (or assets/.dox/). Any hand-written code that duplicates a generated type, union, encoder, decoder, or constant map is a bug.

1. Read the domain/*.dox files and identify all union types and their members:
   find ${ROOT}/domain -name "*.dox" 2>/dev/null | head -30

2. For each union, search for hand-written duplicates:
   - In Elixir ${ROOT}/lib/ (NOT .dox/lib/): look for defmodule with same name, @type with same members, or constant maps keyed by union members
   - In TypeScript ${ROOT}/assets/ts/ (NOT .dox/ts/): look for type X = "a" | "b" | "c" unions, const X = { ... } objects with union member keys
   - In test support files: look for hardcoded lists of union members that will rot

3. Also search for hardcoded wire strings that Paradox generates:
   grep -rn '"pending"\\|"running"\\|"succeeded"\\|"failed"\\|"cancelled"\\|"evaluating"\\|"evaluated"' ${ROOT}/lib ${ROOT}/assets/ts --include="*.ex" --include="*.ts" 2>/dev/null | grep -v ".dox/" | grep -v "migration"

Return JSON:
[{
  "dox_source": "domain/ci/types.dox:12",
  "union_name": "PipelineStatus",
  "hand_written_copy": "lib/operation/ci/status.ex:45",
  "language": "elixir|typescript",
  "drift": "same|subset|superset|diverged",
  "action": "delete_handwritten|add_to_dox|investigate"
}]
`

const REFACTOR = `
You are auditing for HIGH-VALUE REFACTOR OPPORTUNITIES that would ENABLE MORE TESTING in an Elixir/Phoenix/TypeScript project at ${ROOT}.

The goal is not refactoring for its own sake. Every suggestion must directly enable a test that currently cannot be written.

Look for these patterns:

1. UNTESTABLE SIDE-EFFECT MIXTURES: functions that mix pure computation with IO/DB/HTTP, making it impossible to test the logic without the infrastructure. Split them: pure core + thin shell.
   grep -rn "Repo\\.\\|HTTPoison\\.\\|:httpc\\." ${ROOT}/lib --include="*.ex" 2>/dev/null | grep -v test | grep -v ".dox" | head -80

2. PRIVATE FUNCTION HELL: critical logic buried in defp that can't be tested directly. If a defp function is >10 lines of business logic, it needs its own module.

3. HARDCODED DEPENDENCIES: modules that call other modules directly instead of receiving them as arguments or reading from config. These can't be replaced in tests.
   grep -rn "Operation\\." ${ROOT}/lib --include="*.ex" 2>/dev/null | grep -v test | grep -v ".dox" | grep -v "alias" | head -80

4. STATEFUL GENSERVER LOGIC: GenServers where the business logic is inseparable from the process state. Extract the pure state machine into a plain module.

5. UNTESTABLE WALLABY FLOWS: test steps that require a full browser session because the logic runs in JavaScript with no server-side equivalent. These need a server-side extraction or a TypeScript unit test.

For each opportunity:
- What prevents testing it now?
- What is the proposed refactor? (function signature or module boundary change)
- What new test becomes possible after the refactor?

Return JSON:
[{
  "file": "lib/...",
  "function": "...",
  "line": 42,
  "anti_pattern": "side_effect_mixture|private_hell|hardcoded_dep|stateful_genserver|untestable_js",
  "proposed_refactor": "...",
  "new_test_possible": "...",
  "value": "high|medium"
}]
`

const DRY = `
You are auditing for DRYNESS VIOLATIONS in the test suite and production code of an Elixir/Phoenix/TypeScript project at ${ROOT}.

Rule of thumb: 3+ occurrences = centralize it. This includes cross-language opportunities via Paradox.

Search for:

1. REPEATED TEST SETUP BLOCKS: identical or near-identical setup code across multiple test files that should be a shared fixture, factory, or setup helper.
   Look in ${ROOT}/test/support/ — what factory/fixture helpers are missing?
   grep -rn "insert!\\|create_\\|build(" ${ROOT}/test --include="*.exs" 2>/dev/null | grep -v "support/" | sort | uniq -c | sort -rn | head -30

2. REPEATED ASSERTION PATTERNS: custom assertion logic repeated 3+ times that should be a defmacro or helper function.
   grep -rn "assert.*==\\|refute.*==" ${ROOT}/test --include="*.exs" 2>/dev/null | grep -oP "assert.*" | sort | uniq -c | sort -rn | head -30

3. REPEATED WALLABY NAVIGATION: repeated visit("/path") + login + click flows that should be a helper.
   grep -rn "visit\\|login\\|fill_in" ${ROOT}/test/operation_web/features --include="*.exs" 2>/dev/null | grep -oP '"[^"]*"' | sort | uniq -c | sort -rn | head -20

4. REPEATED TS TEST UTILS: identical mock setup, vi.fn() patterns, or DOM fixture construction copied across TypeScript test files.

5. CROSS-LANGUAGE DRY: identical constant lists appearing in Elixir test fixtures AND TypeScript test fixtures that could both be generated from a single .dox source.
   Look for: lists of CI statuses, permission levels, hook names, event types hardcoded in both ${ROOT}/test/support and ${ROOT}/assets/test.

For each violation:
- File:line citations for all 3+ occurrences
- What the centralized form would look like
- Cross-language? Flag if Paradox could eliminate it entirely

Return JSON:
[{
  "pattern": "...",
  "occurrences": [{"file": "test/...", "line": 42}, ...],
  "proposed_centralization": "... code ...",
  "cross_language": true|false,
  "paradox_opportunity": "... if cross_language, what .dox addition would eliminate all copies ..."
}]
`

const FSTAR = `
You are auditing for HIGH-VALUE OPPORTUNITIES TO MOVE ELIXIR CODE INTO F* in an Elixir/Phoenix/TypeScript project at ${ROOT}.

Context: The project already has F* modules in ${ROOT}/fstar/ proving invariants for state machines (CI, dev-sessions, group access), crypto, retry policy, HTML sanitization, etc. Elixir calls them via apply/3.

You are looking for Elixir modules that would BENEFIT from F* proofs — where a non-trivial invariant can be stated and the proof prevents a class of production bugs.

Signals that Elixir code is a good F* candidate:
1. PURE FUNCTIONS with complex invariants: functions that take data and return data with a guarantee that's hard to test exhaustively (termination, monotonicity, ordering, membership)
2. SECURITY-CRITICAL PATHS: access control decisions, permission checks, key validation — where "always true" or "always false" bugs are catastrophic
3. STATE MACHINE LOGIC not yet covered by existing .fst files
4. PARSER/VALIDATOR logic where you want to prove "output is always a valid X" or "this never crashes on malformed input"
5. CRYPTOGRAPHIC HELPERS beyond what's already in ${ROOT}/fstar/

Steps:
1. Read the existing F* modules to understand what's already covered:
   ls ${ROOT}/fstar/*.fst 2>/dev/null

2. Search for Elixir pure functions that are NOT already mirrored in F*:
   grep -rn "@spec.*->" ${ROOT}/lib --include="*.ex" 2>/dev/null | grep -v test | head -80

3. Search for access control and permission logic:
   grep -rn "can?\\|permitted?\\|authorized?\\|has_permission\\|check_access\\|role ==" ${ROOT}/lib --include="*.ex" 2>/dev/null | grep -v test | grep -v ".dox" | head -40

4. Search for validation logic:
   grep -rn "def valid\\|changeset\\|validate_" ${ROOT}/lib --include="*.ex" 2>/dev/null | grep -v test | grep -v ".dox" | head -40

For each candidate, propose:
- What invariant would be stated as a lemma?
- What class of production bug does the proof prevent?
- Sketch the F* type signature and lemma statement

Return JSON:
[{
  "elixir_file": "lib/...",
  "function": "Operation.X.f/2",
  "line": 42,
  "invariant": "...",
  "proposed_lemma": "val f: x:T -> y:T{invariant y}",
  "bug_class_prevented": "...",
  "value": "high|medium"
}]
`

const WALLABY = `
You are auditing for FRAGILE WALLABY SELECTORS in an Elixir/Phoenix/TypeScript project at ${ROOT}.

Context: Wallaby browser tests use css() selectors. The project has an OperationWeb.Ids module that provides stable, centralized IDs. Tests should use Ids.* functions rather than raw CSS class/text selectors that break when styling changes.

1. Find the Ids module:
   find ${ROOT}/lib -name "ids.ex" 2>/dev/null | head -5

2. Find all Wallaby tests and audit their selectors:
   grep -rn 'css("\\.' ${ROOT}/test/operation_web/features --include="*.exs" 2>/dev/null | head -40
   grep -rn 'css("button\\|css("form\\|css("div\\|css("span\\|css("a\\|css("h[1-6]' ${ROOT}/test/operation_web/features --include="*.exs" 2>/dev/null | head -40
   grep -rn 'text:' ${ROOT}/test/operation_web/features --include="*.exs" 2>/dev/null | grep -v "Ids\\." | head -40

3. For each fragile selector, determine:
   - Is there an existing Ids.* function that covers it?
   - If not, what Ids function SHOULD be added?
   - What is the stable selector replacement?

4. Also check for:
   - Selectors that assume DOM structure (nth-child, >, +) — break on any layout change
   - Selectors on generated class names (Tailwind-generated, scoped CSS)
   - Selectors hardcoding user-visible text that will break on copy changes

The right pattern is: Ids.button_id(:submit_login) → css("#\#{Ids.button_id(:submit_login)}")
Or Paradox-generated data-testid attributes: css("[data-testid=submit-login]")

Return JSON:
[{
  "file": "test/operation_web/features/...",
  "line": 42,
  "selector": "css(\\".btn-primary\\")",
  "fragility": "class|tag|text|structure",
  "stable_replacement": "css(\\"#\#{Ids.submit_button()}\\")",
  "ids_function_needed": "Ids.submit_button/0",
  "value": "high|medium"
}]
`

const ASYNC_ISOLATION = `
You are auditing for ASYNC AND ISOLATION ISSUES in Elixir tests in an Elixir/Phoenix/TypeScript project at ${ROOT}.

CLASS A — MISSING async: true
Many ExUnit tests could run in parallel (async: true) but don't. Each non-async test holds the entire suite's parallelism hostage. Look for:
  grep -rn "use ExUnit.Case$\\|use ExUnit.Case," ${ROOT}/test --include="*.exs" 2>/dev/null | grep -v "async: true" | head -40
For each, assess: does it touch the DB (requires Sandbox, which supports async)? Does it touch global state (ETS, Application.put_env without cleanup)? If not, it can be async.

CLASS B — LEAKING STATE
Tests that set global state without cleaning it up, causing interference:
  grep -rn "Application.put_env\\|:ets.insert\\|Process.register" ${ROOT}/test --include="*.exs" 2>/dev/null | grep -v "on_exit\\|setup_all" | head -40
For each Application.put_env, verify there's an on_exit that restores it. Missing cleanup is a test ordering dependency.

CLASS C — MISSING SANDBOX
LiveView tests that use Ecto without SQL.Sandbox checkout — ensure all DB-touching tests use the sandbox properly:
  grep -rn "use OperationWeb.ConnCase\\|use OperationWeb.FeatureCase" ${ROOT}/test --include="*.exs" 2>/dev/null | head -10

CLASS D — WRONG TAG SCOPING
Tests tagged with @moduletag that should be per-test @tag, or vice versa. A slow test dragging the whole module into serial mode.

Return JSON:
[{
  "type": "missing_async|leaking_state|missing_sandbox|wrong_tag_scope",
  "file": "test/...",
  "line": 42,
  "description": "...",
  "fix": "... code ...",
  "value": "high|medium"
}]
`

phase('Audit')
log('Launching 12 parallel audit agents...')

const [
  vacuous,
  coverage,
  property,
  mutation,
  stubs,
  sleeps,
  doxCopies,
  refactor,
  dry,
  fstar,
  wallaby,
  asyncIsolation,
] = await parallel([
  () => agent(VACUOUS, { label: 'vacuous-tests', phase: 'Audit' }),
  () => agent(COVERAGE, { label: 'coverage-gaps', phase: 'Audit' }),
  () => agent(PROPERTY, { label: 'property-tests', phase: 'Audit' }),
  () => agent(MUTATION, { label: 'mutation-gaps', phase: 'Audit' }),
  () => agent(STUBS_SKIPS, { label: 'stubs-skips', phase: 'Audit' }),
  () => agent(SLEEPS, { label: 'magic-sleeps', phase: 'Audit' }),
  () => agent(DOX_COPIES, { label: 'dox-copies', phase: 'Audit' }),
  () => agent(REFACTOR, { label: 'refactor-opportunities', phase: 'Audit' }),
  () => agent(DRY, { label: 'dry-violations', phase: 'Audit' }),
  () => agent(FSTAR, { label: 'fstar-candidates', phase: 'Audit' }),
  () => agent(WALLABY, { label: 'wallaby-selectors', phase: 'Audit' }),
  () => agent(ASYNC_ISOLATION, { label: 'async-isolation', phase: 'Audit' }),
])

phase('Synthesize')
log('Synthesizing findings into ranked report...')

const SYNTHESIZE = `
You are the synthesis agent for a comprehensive test quality audit of ${ROOT}.

You have received findings from 12 audit agents. Your job is to synthesize them into a single ranked report. First run: date +%Y-%m-%d to get today's date, then write the report to ${ROOT}/docs/audits/grind-tests-<YYYY-MM-DD>.md (substitute the actual date). Create the docs/audits/ directory if it doesn't exist.

The findings:

## VACUOUS TESTS
${JSON.stringify(vacuous || [])}

## COVERAGE GAPS
${JSON.stringify(coverage || [])}

## PROPERTY TEST OPPORTUNITIES
${JSON.stringify(property || [])}

## MUTATION TEST GAPS
${JSON.stringify(mutation || [])}

## STUBS / SKIPS / DEAD CODE
${JSON.stringify(stubs || [])}

## MAGIC SLEEPS AND TIMEOUTS
${JSON.stringify(sleeps || [])}

## HAND-WRITTEN DOX COPIES
${JSON.stringify(doxCopies || [])}

## REFACTOR OPPORTUNITIES
${JSON.stringify(refactor || [])}

## DRY VIOLATIONS
${JSON.stringify(dry || [])}

## F* MIGRATION CANDIDATES
${JSON.stringify(fstar || [])}

## FRAGILE WALLABY SELECTORS
${JSON.stringify(wallaby || [])}

## ASYNC / ISOLATION ISSUES
${JSON.stringify(asyncIsolation || [])}

Write the report with this structure:

# Test Grind Report

## Headline Numbers
- Total findings: X
- High-value findings: X
- Vacuous tests confirmed: X
- Coverage gaps identified: X
- (etc. for each category)

## Priority Queue (Top 20 Action Items)
A ranked list of the 20 most impactful things to fix, sorted by:
1. Production risk (could a bug hide behind this?)
2. Fix cost (how easy is it to fix?)
3. Blast radius (how many tests/paths does fixing this improve?)

Each item:
### N. <short title>
**Category**: vacuous|coverage|property|mutation|stubs|sleeps|dox_copies|refactor|dry|fstar|wallaby|async
**File**: path:line
**Impact**: one sentence on why this matters
**Fix**: concrete code snippet or prose instruction
---

## Full Findings by Category
One section per category. Each finding gets:
- file:line citation
- description
- proposed fix (always concrete — no "consider refactoring", give actual code)

Rules:
- No finding without a concrete fix.
- No vague "this could be improved" — every finding is a specific change.
- If an agent returned null or empty results, say "No findings" for that section.
- Cross-reference findings where they overlap (e.g. a vacuous test that also represents a coverage gap).
- Paradox opportunities get flagged with [PARADOX] prefix.
- F* opportunities get flagged with [FSTAR] prefix.
- Write the file to disk using the Write tool (create the docs/audits/ directory if needed).

Return the absolute path of the report file you wrote as report_path.
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

// Log bugs found from each audit agent
const categories = [
  { name: 'vacuous tests', data: vacuous },
  { name: 'coverage gaps', data: coverage },
  { name: 'property test opportunities', data: property },
  { name: 'mutation gaps', data: mutation },
  { name: 'stubs/skips', data: stubs },
  { name: 'magic sleeps', data: sleeps },
  { name: 'hand-written dox copies', data: doxCopies },
  { name: 'refactor opportunities', data: refactor },
  { name: 'dry violations', data: dry },
  { name: 'f* migration candidates', data: fstar },
  { name: 'fragile wallaby selectors', data: wallaby },
  { name: 'async/isolation issues', data: asyncIsolation },
]
for (const cat of categories) {
  const count = (cat.data && Array.isArray(cat.data)) ? cat.data.length : (cat.data ? 1 : 0)
  if (count > 0) log(`Found ${count} ${cat.name}`)
}
log(`Total: ${synth && synth.total_findings ? synth.total_findings : '?'} bugs found`)

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
You are the remediation planner for a test quality audit of ${ROOT}.

Read the FULL audit report at ${REPORT} — every priority queue item AND every entry under "Full Findings by Category", not just the top 20.

Convert EVERY finding into a work item. No exceptions:
- Findings the audit judged intentional still get an item (fix = "document the intent with a comment at the site").
- Medium-value findings are NOT skippable. F*/Paradox candidates are NOT skippable — their fix is the actual .fst module or .dox edit plus wiring.
- Merge findings that touch the same file into ONE work item so no file appears in two items (fixers run concurrently and must not collide).
- "files": EVERY existing file the fix will touch — production code, test files, .dox sources, .fst modules, test/support. Be exhaustive; fixers may only touch listed files plus brand-new files they create.
- "fix": concrete instructions, embedding the code snippets from the report verbatim where they exist.
- "verify": the exact command(s) that prove the fix, e.g. "mix test test/operation/foo_test.exs" or "cd ${ROOT}/assets && npx vitest run test/bar.test.ts". For pure deletions: "mix compile --warnings-as-errors".
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

Go finding-by-finding through the ENTIRE report (priority queue AND full findings sections). For every finding that is NOT covered by any TODO item, produce a new work item in the same schema (id, title, category, files, fix with the report's code verbatim, verify command). A finding sharing a file with an existing item still needs its fix text covered — if the existing item's title doesn't plausibly include it, emit a new item but reuse NO files already claimed; instead emit it with the same files and the orchestrator will serialize them.

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
You are a fix agent for a test quality remediation of the project at ${ROOT}. The full audit report is at ${REPORT}.

WORK ITEM ${item.id}: ${item.title}
Category: ${item.category}
Files in scope: ${(item.files || []).join(', ')}
Fix instructions:
${item.fix}

Verification: ${item.verify}

Non-negotiable rules:
- Address the finding COMPLETELY. No skipping, no deferring, no watering down. "Pre-existing problem" and "out of scope" are not acceptable outcomes.
- Project hierarchy: .dox files in domain/ are the source of truth — edit them and regenerate, NEVER patch generated .dox/ output. F* invariants go in fstar/ .fst modules called via apply/3. Direct Elixir/TS only when neither applies.
- Never weaken a test assertion to make it pass. Fix the code or write the stronger test the report asks for.
- Style: well-typed, purely functional — pure core, immutable data, side effects at the edges.
- Touch ONLY the files listed above, plus brand-new files you create. Other fixers run concurrently on other files.
- Git is READ-ONLY for you: no commit, no reset, no stash, no checkout/restore of paths. The orchestrator owns the tree.
- Run the verification command and make it pass. Concurrent fixers share the build — if you hit a transient compile lock, retry once.
- "blocked" is permitted ONLY when the fix requires changes outside this repository (e.g. upstream paradox); exhaust every in-repo option first and include a concrete unblock plan in notes.

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
    for (const it of now) {
      log(`  Fixing: [${it.category}] ${it.title}`)
    }
    const res = await parallel(now.map(it => () => agent(fixerPrompt(it), { label: `fix:${it.id}`, phase: 'Fix', schema: FIX_RESULT })))
    results.push(...res.filter(Boolean))
    queue = later
  }
  return results
}

let fixResults = await runWaves(items)
const itemById = {}
items.forEach(i => { itemById[i.id] = i })

// Log fixes that were applied
for (const result of fixResults) {
  if (result.status === 'fixed') {
    const item = itemById[result.id]
    log(`Fixed: [${item.category}] ${item.title}`)
  } else if (result.status === 'blocked') {
    const item = itemById[result.id]
    log(`Blocked: [${item.category}] ${item.title} — ${result.notes}`)
  }
}

// ============ VERIFY ============
phase('Verify')
log('Adversarially verifying every fix...')
log(`Verifying ${fixResults.filter(r => r.status === 'fixed').length} fixed items`)

for (let round = 1; round <= 3; round++) {
  const verdicts = await parallel(fixResults.filter(r => r.status === 'fixed').map(r => () => agent(`
You are an adversarial verifier. A fix agent claims it completed this work item in ${ROOT}:

${JSON.stringify(itemById[r.id] || r)}

Its claim: ${JSON.stringify(r)}

Try to REFUTE the claim. Read the actual files, run the verification command (${(itemById[r.id] || {}).verify || 'the item verify command'}), and check the fix is real, complete, and didn't weaken any assertion or merely delete the failing check. Default to refuted=true if uncertain.

Return JSON: {"id": "${r.id}", "refuted": true|false, "reason": "..."}
`, { label: `verify:${r.id}`, phase: 'Verify', schema: {
    type: 'object', required: ['id', 'refuted', 'reason'],
    properties: { id: { type: 'string' }, refuted: { type: 'boolean' }, reason: { type: 'string' } },
  } })))
  const refuted = verdicts.filter(Boolean).filter(v => v.refuted)
  const confirmed = verdicts.filter(Boolean).filter(v => !v.refuted)
  if (refuted.length === 0) { 
    log(`Verify round ${round}: ${confirmed.length} fixes confirmed`)
    break 
  }
  log(`Verify round ${round}: ${confirmed.length} confirmed, ${refuted.length} refuted — re-dispatching with verifier feedback`)
  const rework = refuted.map(v => {
    const base = itemById[v.id] || { id: v.id, title: v.id, category: 'rework', files: [], verify: 'mix test' }
    return { ...base, fix: `${base.fix}\n\nPREVIOUS ATTEMPT WAS REFUTED BY A VERIFIER: ${v.reason}\nAddress the refutation fully.` }
  })
  const redone = await runWaves(rework)
  const redoneIds = new Set(redone.map(r => r.id))
  fixResults = fixResults.filter(r => !redoneIds.has(r.id)).concat(redone)
}

log('Gating on full compile + test suites...')
const gate = await agent(`
You are the final gate for a test quality remediation of ${ROOT}. Many fix agents have edited the tree.

1. Run: cd ${ROOT} && mix compile --warnings-as-errors 2>&1 | tail -30
2. Run: cd ${ROOT} && mix test 2>&1 | tail -40
3. Run: cd ${ROOT}/assets && npx vitest run 2>&1 | tail -30 (skip if no assets/ test setup)
4. Repair ANY failure: these are integration breaks between individually-verified fixes. Never weaken an assertion; fix the actual conflict. Re-run until green.
5. Update the TODO at ${TODO_PATH}: mark every completed item "- [x]", annotate blocked items with their unblock plans.
6. Append a "## Remediation" section to ${REPORT}: a table of work item id, title, status (fixed/blocked), files changed.
   Source the rows from ${TODO_PATH}, and use git -C ${ROOT} status --short plus git -C ${ROOT} diff --stat for the files-changed column. Do NOT commit anything.

Return JSON: {"suite_green": true|false, "summary": "what passed, what was repaired, anything still red and why"}
`, { label: 'final-gate', phase: 'Verify', schema: {
  type: 'object', required: ['suite_green', 'summary'],
  properties: { suite_green: { type: 'boolean' }, summary: { type: 'string' } },
} })

const numFixed = fixResults.filter(r => r.status === 'fixed').length
const numBlocked = fixResults.filter(r => r.status === 'blocked').length
log(`\n=== REMEDIATION COMPLETE ===`)
log(`Fixed: ${numFixed} issues`)
log(`Blocked: ${numBlocked} issues`)
log(`Suite green: ${gate ? gate.suite_green : 'unknown'}`)
log(`Report: ${REPORT}`)
log(`TODO: ${TODO_PATH}`)

return {
  done: true,
  report: REPORT,
  todo: TODO_PATH,
  items: items.length,
  fixed: numFixed,
  blocked: numBlocked,
  suite_green: gate ? gate.suite_green : null,
  gate_summary: gate ? gate.summary : 'gate agent returned null',
}
```

After the Workflow completes, read the generated report and TODO files and present a concise summary to the user: total findings, items fixed vs blocked (with unblock plans for blocked ones), whether the final compile + test gate is green, the top 5 priority items that were addressed, and the full paths to the report and TODO. Remind the user the tree is dirty and uncommitted for their review (suggest /commit when they're satisfied).
