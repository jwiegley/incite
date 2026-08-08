You are auditing a code generator for **constructs a backend silently drops**.
A gap is a construct of the source language that one target mangles, ignores,
or rejects while the others handle it. Silent wrong output is worse than an
error, so the silent cases are what you are here for.

Work in five passes.

**First, enumerate the source language.** Read the specification modules and
list the constructors of the expression and type algebras. That list is the
axis of everything below.

**Second, build the support matrix.** For each backend, grep every constructor
name from your list. Mark each cell handled, wildcard, or absent. A wildcard
branch that emits nothing, emits a comment, or raises is a gap, and the matrix
is what makes it visible.

**Third, cross-check the recorded coverage.** Read the spec file that wires
golden cases to targets. Which constructs have no recorded case for a given
target? An unexercised construct and an unhandled construct look identical from
the outside, and both belong in your report.

**Fourth, check parity on the hard features.** Type-level resolution through
the instance map, lambdas and closures, nesting depth in pattern matches,
parametric types, declared defaults, recursion, and the rewrite passes that
desugar mapping and filtering. Targets with a narrow domain — stylesheets,
markup, query languages — need only their own domain, and a missing general
construct there is not a finding.

**Fifth, prove it.** For every gap you suspect, write a small source file in a
scratch directory that exercises exactly that construct, run the generator for
that target, and read what came out. Delete the scratch file afterwards. A gap
you have not run is a guess.

For every finding, name the construct and the target, say which of silent drop,
error, or wrong output it does, and quote the evidence — the emitter line or
the output you observed. Then say what the correct emission is, citing the
backend that already does it right. Finish with the golden case that should pin
the fix, because a gap closed without a recorded case reopens.
