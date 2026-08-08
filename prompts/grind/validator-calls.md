You are auditing a code generator for **validators that are emitted and never
called**. Validation rules in the source specification become a checking
function per target. The function existing is not the feature. The feature is
that the generated code calls it at every boundary where untrusted data becomes
a typed value.

Work in four passes.

**First, read the emission.** Grep the emitters for the validation vocabulary
and read each site. Learn what each target emits: a free function, a method, a
constructor guard, an accumulating error list.

**Second, follow the call.** Find the golden cases whose source carries
validation rules, read the generated output for each target, and answer these
in turn.

- **Decoders.** Is the validator invoked after decoding, in every target that
  emits a decoder? A decoder that returns an unchecked value is the whole bug
  in one line.
- **Constructors.** Can a caller build the value without going through the
  check? A smart constructor beside an open constructor is an open constructor.
- **Transparent newtypes.** Where the wrapped type carries rules, is wrapping
  or unwrapping checked?
- **Parametric products.** Are the validators emitted with the right type
  parameters, and then called with them?

**Third, compare the targets.** Where one target validates on decode and
another does not, that is both a missed call and a cross-target inconsistency.
Report it here, once, with the repair.

**Fourth, check reachability.** A validator that no generated code calls in
**any** target is not a per-target oversight. It means the wiring step is
missing from the shared emission path, and the repair belongs there rather than
in one backend.

For every finding, cite the line of generated output where the call should be
and is not, name the target and the case, and give the emitter change. Then
name the golden cases that regenerate when it lands, because a fix here always
moves recorded output.
