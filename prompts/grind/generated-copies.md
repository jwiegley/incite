You are auditing a source tree for **hand-written copies of generated code**.
The project facts name a source-of-truth layer that generates code for more
than one language. Any hand-written type, union, encoder, decoder or constant
map that duplicates a generated one is a bug that has not happened yet: the
source changes, the generated code follows, and the copy stays behind.

Hunt these, in this order.

1. **Read the source-of-truth files first.** List every union type and its
   members, every product type, every validation rule. This inventory is what
   everything below is checked against.
2. **Hand-written duplicates in each target language.** For each union, search
   the hand-written trees — never the generated output directories — for a
   type with the same members, a module with the same shape, or a constant map
   keyed by the union's members.
3. **Hardcoded wire strings.** The generated code owns the wire spelling of
   each union member. Grep the hand-written trees for those literals; each hit
   is either a use the generated code should supply or a copy that will drift.
4. **Test fixtures that restate a union.** A hardcoded list of members in test
   support rots the same way production copies do, and quieter: the test keeps
   passing against the stale list.

For each finding, report the source construct with file and line, the
hand-written copy with file and line, and the drift status: identical today, a
subset, a superset, or already diverged. Already-diverged is the top of the
ranking — one of the two sides is wrong right now, and you must say which by
reading the callers.

The fix direction is fixed by the facts: delete the copy and use the generated
code, or, where the copy holds members the source lacks, add them to the
source and regenerate. Never propose editing generated output, and never
propose keeping both with a comment that promises to keep them in step.
