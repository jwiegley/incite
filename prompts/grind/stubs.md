You are auditing a source tree for **stubs, skips, and unfinished work**: the
places where somebody wrote the shape of a thing and left the thing itself for
later.

Hunt these six, in this order.

1. **Skipped and pending tests.** Grep the test tree for the skip vocabulary of
   its framework: `pendingWith`, `pending`, `xit`, `xdescribe`, `xcontext`,
   `skip`, `ignore`, `focus` markers that exclude everything else. A test that
   is compiled but never run is a test that has stopped guarding its subject.
2. **Markers in production and test code.** Grep for `TODO`, `FIXME`, `XXX`,
   `HACK`, `undefined`, and error calls whose message says the case is not
   implemented or not supported. Read each one. Some are honest notes about
   work that belongs elsewhere; some are a hole in a live path.
3. **Catch-all branches that swallow a construct.** In every emitter, find the
   final wildcard branch of a case analysis over the source language: the one
   that returns the empty string, the empty list, an empty document, or a unit.
   That branch turns an unhandled construct into silence, and silence in a
   generator ships as missing output rather than as an error.
4. **Placeholder text that reaches the generated output.** Grep the recorded
   golden outputs themselves for `TODO`, `FIXME`, `unimplemented`, and `not
   implemented`. A placeholder in a golden file is a placeholder somebody
   accepted as correct.
5. **Golden cases present for some targets and missing for others.** List the
   golden directory per case and compare which target extensions exist. Then
   read the spec file that wires cases to targets. A case recorded for three
   targets and not for a fourth means the fourth target has no pin for that
   construct at all.
6. **A target missing from a whole suite.** For every suite that runs once per
   target language, work out which targets take part. Read the spec file rather
   than the directory listing: an opt-in gate, a conditional branch, or a
   check for a file that does not exist will exclude a target while looking
   deliberate. A target present in the golden suite and absent from a
   roundtrip, evaluation, or equivalence suite is the highest finding in this
   lens, because every regression that suite would have caught ships unseen.

For each finding, say whether it is real debt or a deliberate and reasonable
gap, and say which on the evidence rather than on the tone of the comment
beside it. Then give the fill-in: the test body, the missing branch, or the
golden case to add.
