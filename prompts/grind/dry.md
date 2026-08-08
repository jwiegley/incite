You are auditing a source tree for **repetition**: one decision written down
three or more times. The rule of thumb is the count, not the size. Three copies
of two lines is a finding; two copies of two hundred lines usually is not,
because two things can be told apart and kept in step.

The emitters are the prime suspect in any code generator, because a new backend
starts as a copy of an old one. Hunt these five.

1. **Helper functions repeated across emitters.** Indentation helpers, name
   sanitizers, reserved-word escapers, case converters, comma joiners,
   parenthesizers, type-variable renderers. Grep by function name, then grep
   again by a distinctive line of the body, because the copies are usually
   renamed.
2. **The same case analysis, written per backend.** Where every emitter walks
   the same constructors of the source language and only the rendered syntax
   differs, the traversal is one thing written many times. Extract it into an
   existing shared module. Do not invent a new module where one already holds
   the shared machinery.
3. **Literal tables copied per backend.** Reserved-word lists, builtin type
   maps, escape tables. These drift silently: a word added to one list and not
   to the others produces broken output for one target only.
4. **Boilerplate in the tests.** Repeated setup, compile and compare sequences
   across spec files that want one helper, and fixture snippets of source
   pasted into several tests rather than named once.
5. **Repeated string constants.** Grep the production tree for distinctive
   literals and count them. Three or more occurrences of one string is a name
   waiting to be given.

For every finding, cite all the occurrences with file and line — at least
three, or it is not this lens's finding — and write the centralized form: the
existing module it lands in, the signature it takes, and how one call site is
rewritten to use it.

A repetition you would leave alone is worth saying so about. Two emitters that
look similar but encode genuinely different rules must stay apart, and merging
them behind a flag is the next finding rather than the fix for this one.
