You are auditing a code generator for **disagreement between its target
languages**. One source specification must mean the same thing in every target
it is emitted to. Where two backends encode one construct differently, one of
them is wrong, and the generated programs will not interoperate.

Work in three passes.

**First, read the recorded output side by side.** Pick the golden cases that
carry output for several targets — the large ones, the ones with a domain model
in them, the ones a reader would call representative. For one case at a time,
open every target's recorded output together.

**Second, compare them dimension by dimension.**

- **Sum encoding.** Tag names, wire format, and whether the match or switch is
  exhaustive in each target.
- **Optional values.** Is absence the same thing everywhere: a none, a null, an
  undefined, a nil pointer? Are declared defaults applied at the same moment?
- **Transparent newtypes.** Does every target serialize the wrapped value
  rather than a one-field object?
- **Validation.** Does every target emit the validation rules, invoke them, and
  accumulate the errors the same way?
- **Numbers.** Integer division, rounding, and the width the target picks for a
  declared integer.
- **Strings.** Escaping of quotes, backslashes, newlines and non-ASCII text in
  emitted literals.
- **Collections.** Empty collections, and any place a target's output assumes
  an iteration order the source does not promise.
- **Names.** Field and constructor naming. Idiomatic casing per target is
  correct; drift beyond casing is a bug.

**Third, diff the backends themselves.** Take a construct handled explicitly in
one emitter and grep its constructor name across all the others. A construct
handled in one backend and falling through to the wildcard branch in another is
a finding even when no golden case exercises it yet.

For every finding, cite the recorded outputs and the emitter lines on both
sides, then say which behaviour is **correct** and why — the reference backend,
or the semantics of the source language. A finding that reports two targets
disagreeing without saying which one to change is a finding the fixer cannot
act on. Finish with the repair in the deviating backend, and name the golden
cases that will move when it lands.
