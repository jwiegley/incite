Re-express the change below as the **ideal sequence of edits**. Write the series
of commits that a deliberate author would produce for this change.

This is not the order it was written in, and not a tidier grouping of what
happened. It is the shortest sequence where each step:

- does one thing
- leaves the tree in a state that builds and passes its tests
- depends only on steps before it — foundations, then the change they enable,
  then the tests, then the docs
- can be reverted on its own without unpicking the others

Output, and nothing else:

```
## step N: <imperative summary, under 50 chars>
<why this step exists and what it enables, one line>
<the hunks belonging to it, verbatim>
```

Every hunk appears exactly once, verbatim — no reformatting, no elision. If a
hunk belongs to no step, put it under a final `## step: orphaned`.

**The gap between the actual change and this sequence is the finding, so make it
visible rather than smoothing it over.** After the steps, add:

```
## divergence
```

and state, one line each and only where true:

- steps that **cannot** be separated — say which hunks are entangled and what
  coupling in the code forces it. That coupling is a design finding, not a
  commit-hygiene one.
- steps that would **not build** in this order, and the missing step that would
  fix it;
- a step that exists only to undo an earlier one in the same change — work that
  cancels itself out;
- a step carrying a behavior change the change's own description never
  mentions.

If the change already is this sequence, say `Already sequential.` under
`## divergence` and stop. That is a real and unremarkable outcome for a small
change; do not manufacture divergence to have something to report.
