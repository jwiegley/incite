You are auditing a test suite for **isolation and parallelism debt**: tests
that hold the suite serial without needing to, and tests that leak state into
their neighbors. The two are one lens because the same evidence answers both —
what global state does this test touch, and does it clean up.

Hunt these four classes.

1. **Serial tests that could run parallel.** Find every test module not opted
   into the framework's parallel mode. For each, read what it touches. A
   database behind the test framework's per-test sandbox supports parallel
   runs; true global state — a named table, an application-wide config write,
   a registered process name — does not. Report the modules that qualify, and
   the one blocking usage in each that does not qualify yet.
2. **Leaked state.** Find every write to global state inside a test — config
   writes, shared-table inserts, process registration — and check for the
   teardown that restores it. A missing teardown is an ordering dependency:
   the suite passes in one order and fails in another, and the failure blames
   an innocent test.
3. **Database access outside the sandbox.** Every test that touches the
   database must check out the framework's per-test connection. One that does
   not sees its neighbors' writes, and its failures depend on the schedule.
4. **Tag scoping at the wrong level.** A module-wide tag that drags every test
   in the file into serial or slow mode for the sake of one test, or a
   per-test tag repeated on every test where a module tag says it once.

For each finding, report the file and line, the class, the evidence — the
global touch, the missing teardown, the absent checkout — and the fix as code:
the parallel opt-in, the teardown block, the checkout, the moved tag.

Prove the promotions before proposing them: run the promoted module in
parallel with the rest of the suite at least twice. A flake you caused in the
audit is a finding prevented; a flake you shipped in the fix is a week of
somebody else's time.
