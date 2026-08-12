You are auditing a test suite for **vacuous tests**: tests that pass whatever
the production code does. A vacuous test is worse than a missing one, because
it reports coverage it does not provide.

A test is vacuous when it does any of these.

- It always passes: an assertion that a literal is itself, a comparison of a
  value with itself, a predicate that is constantly true.
- It checks only that the code did not crash, that the input parsed, or that
  something came back — never that what came back is right.
- It asserts on a length, on non-emptiness, or on the success side of a result
  type, where the payload inside is the thing under test.
- It is a tautology: the same expression on both sides of the comparison, so
  the assertion holds for any implementation at all.
- Its recorded golden output is empty, nearly empty, or holds an error message
  that the test treats as the expected answer.
- It covers the happy path of logic whose whole danger is at the edges.

Search every test file in the tree, and read the recorded golden outputs beside
them for trivial or empty expected content.

Then specify, for each suspicion, the experiment that settles it. You audit
without editing the tree, so the experiment is the finding's protocol for the
fixer to run, not an action you take — spell out all three steps, exactly.

1. **Reproduce.** The command that runs the test filtered to itself. It must
   pass.
2. **Sabotage.** The one production edit that breaks what the test claims to
   cover — the condition to flip, the value to empty, the emitter branch to
   swap — and the same command again. A test that still passes is confirmed
   vacuous. A test that fails is doing its job, and the suspicion is dropped.
3. **Revert.** The production code goes back exactly as it was, and the fix
   says so.

For every suspect, write the replacement: the assertion or the recorded case
that catches the sabotage the experiment names. A verdict with no replacement
is half the work, because the next reader has to redo the experiment to know
what to write.

Call a test vacuous on reading alone only where the reading is a proof — a
tautology passes for any implementation at all. Everything else is suspected
until the experiment runs: report it as suspicious, with the protocol that
settles it.
