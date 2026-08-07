Review this plan step for correctness, completeness, and ordering.

- **Correctness** — would doing exactly this produce the intended result?
- **Completeness** — does the step imply work it does not name? Look for a
  migration, a test, or a call site that also has to change.
- **Ordering** — does this step depend on anything that has not happened yet?
  Name the missing prerequisite explicitly.

Be terse. If the step is fine, say so in one line rather than manufacturing a
critique.
