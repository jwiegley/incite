You are auditing the **generated code** of a code generator, on two axes at
once: how fast it runs, and how fast it compiles. They are one lens because
they have one method and one repair. Both are read off the recorded golden
output per target, and both are fixed in the emitter and nowhere else.

The measure for the first axis is what a competent native author of that target
would have written. The measure for the second is that downstream users compile
this output constantly, so its compile cost is a feature of the generator.

## Run time of the generated code

- **Go.** String concatenation inside a loop where a builder belongs. Maps and
  slices allocated with no capacity hint where the size is known. Pointer
  indirection on a small struct that wants a value. Formatted printing where
  plain concatenation says the same thing.
- **TypeScript.** Repeated object spreads inside a fold. Array concatenation
  that is quadratic in the number of elements. Bindings that are reassigned
  never and declared mutable anyway. Closures and regular expressions rebuilt
  on every pass of a loop.
- **C#.** Query chains that re-enumerate the same sequence more than once.
  String accumulation with an operator inside a loop where a builder belongs.
  Boxing of value types on the validation path.
- **Scala.** A linked list where an indexed sequence is the right structure.
  Repeated conversions back and forth between collection types. Recursion in a
  generated helper that is not in tail position.
- **Haskell.** Character lists where packed text belongs. Lazy left folds.
  Accumulator fields with no strictness annotation.
- **Python, Java, Rust, OCaml.** The same wins in each idiom: copying a value
  that could be borrowed and pushing onto an owned string in Rust, string
  accumulation with an operator in Java and Python where a builder or a join
  belongs, repeated list appends in OCaml.
- **Across every target.** Validators that re-check a substructure their caller
  already checked. Decoders that walk their input twice where one pass carries
  both the shape and the values.

## Compile time of the generated code

- **Haskell.** More derived classes than the output uses. A missing explicit
  export list, which widens what a downstream change recompiles. One large
  module where the output divides cleanly. Language extensions nothing in the
  file needs. Inlining pragmas present where they cost, or absent where they
  pay. Orphan instances that force extra recompilation downstream.
- **TypeScript.** Types that explode inference: deep conditional types, deep
  mapped types, and enormous literal unions where a lookup table checks faster.
  The choice between an interface and a type alias, which changes checking
  cost. One enormous emitted file where separate modules would let the checker
  do less.
- **Scala.** Implicit-heavy patterns that the compiler resolves slowly. Match
  expressions large enough to defeat the optimizer. Places where an explicit
  type ascription is cheaper than the inference it replaces.
- **C#.** Output that would divide into partial classes. Generic nesting deeper
  than the code uses.
- **Go.** Single files far larger than they need to be. Imports the file does
  not use. Interface indirection with exactly one implementation.
- **Rust.** Generic code that monomorphizes into many copies where dynamic
  dispatch or a borrowed slice would do. Derive macros beyond what the output
  calls for.
- **Across every target.** Import and include minimization. Does each backend
  emit only what the file uses, or a fixed preamble it emits everywhere?

## What a finding costs and what it must carry

Where the target compiler is reachable from this environment, measure before
you claim: time the compiler on the recorded output, then on a version you
edited by hand, and quote both numbers. Where it is not reachable, say the
expectation is an argument rather than a measurement, and give the argument.

Every fix lands in the emitter, and then the affected golden outputs are
regenerated and read. Behaviour must be identical: only the emitted idiom
changes, and the semantic gates on targets that have them must stay green. A
change that moves behaviour is a correctness finding, and belongs in the report
as one rather than being folded in here.
