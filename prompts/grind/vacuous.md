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

Then prove each suspicion, in three steps, and report the experiment.

1. **Reproduce.** Run the test filtered to itself. It must pass.
2. **Sabotage.** Break the production code the test claims to cover. Flip a
   condition, return an empty value, swap one branch of the emitter it
   exercises. Run the test again. A test that still passes is confirmed
   vacuous. A test that fails is doing its job, and you drop the suspicion.
3. **Revert.** Put the production code back exactly as it was, and say in the
   finding that you did.

For every confirmed test, write the replacement: the assertion or the recorded
case that catches the sabotage you just performed. A verdict with no
replacement is half the work, because the next reader has to redo the
experiment to know what to write.

Report a test you suspect but cannot break as suspicious rather than vacuous,
and say what you tried. Never report a test as vacuous on a reading alone.
