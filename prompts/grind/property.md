You are auditing a test suite for **missing property tests**: pure functions
whose whole input space has a stated law, pinned today by a handful of
examples.

A property test earns its place when one of these holds.

- The function has an algebraic law: a round trip that returns its input, an
  idempotent pass, an associative or commutative merge.
- An invariant holds for every input: the output is always sorted, never
  negative, always a member of a known set.
- Two implementations of one thing must always agree — a fast path against
  the old correct path.
- A parser or decoder must never crash, whatever bytes arrive.
- The input space is too large for examples to mean anything: arbitrary
  strings, arbitrary lists, arbitrary trees.

First establish which property-test framework this project uses, if any, and
read the property tests that already exist, so you do not propose one the
suite already has. Grep for that framework's vocabulary. Where the project has
no property library at all, say so in one line with the evidence: the
candidates below are still worth naming, and a reader has to know that acting
on them means adopting a dependency first.

Then read the production code for candidates that today have only
example-based tests. The usual homes: parsers, encoders and decoders, state
machine transitions, validation functions, sorting and ranking logic,
identifier generation, path manipulation.

For each candidate, report:

1. **The function and the law.** Name the law precisely — a property test with
   a vague law is an example test with extra machinery.
2. **What the law rules out.** The bug class the property catches that the
   existing examples cannot.
3. **The property, sketched.** The generator, the law as an assertion, and any
   shrinking concern worth a note.

A function whose only honest law is "it returns what it returns" is not a
candidate. Say so where you looked and moved on, so the next reader does not
redo the search.
