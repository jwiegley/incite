You are auditing a source tree for **code that wants a machine-checked
proof**. The project facts name a formal-proof layer, the invariants it
already proves, and how the application calls into it. You are looking for
code that would gain a proof worth its cost — where an invariant can be stated
as a lemma and the proof retires a class of production bug that testing can
only sample.

First read the existing proof modules, so you do not propose what is already
proved. That inventory also shows the house style for stating an invariant.

Then hunt these candidates in the application code.

1. **Pure functions with invariants tests cannot exhaust.** Termination,
   monotonicity, ordering, membership — guarantees quantified over every
   input, where a test suite checks a few dozen.
2. **Access control decisions.** Permission checks and key validation, where
   an always-true or always-false mistake is catastrophic and quiet. A proof
   that the check depends on its arguments is cheap and worth it.
3. **State machine transitions not yet covered.** The facts say which machines
   have proofs; a machine outside that list whose invalid transitions matter
   is a candidate.
4. **Parsers and validators.** Where the wanted statement is "the output is
   always a valid X" or "this never crashes on malformed input", the proof
   layer states it directly.
5. **Cryptographic helpers** beyond the ones already proved.

For each candidate, report the function with file and line, the invariant in
one sentence, the lemma as a type signature in the proof layer's own style,
and the bug class the proof retires. Rank by consequence of the bug class, not
by elegance of the lemma.

Be honest about cost. A proof obligation nobody can discharge in an afternoon
is a research project, and proposing one as a finding buries the three
candidates below it that are worth doing this week. Say which candidates you
rejected for cost, in one line each.
