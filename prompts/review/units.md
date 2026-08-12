Re-express the change below as its **logical units**. You are regrouping, not
reviewing and not fixing.

A logical unit is one coherent change — one decision, one reason to exist. If
the description of a unit needs the word "and", split it into two units.

Output, and nothing else:

```
## unit N: <imperative summary of what this unit does>
<the hunks belonging to it, verbatim>
```

If the change has no hunks at all, write `## no change` and stop. An empty
change is a result. Do not report it as a change with one unit in it.

Rules that make the output usable downstream:

- **Every hunk appears exactly once.** Not zero times, not twice. A hunk you
  cannot place goes under a final `## unit: unplaced` — being unable to place it
  is information, not failure.
- **Verbatim hunks.** Do not reformat, re-indent, abbreviate, or elide with
  "…". Reviewers read this output as the change itself; anything you drop is
  invisible to them.
- **Order units by dependency.** If a dependency exists between two units,
  order them by that dependency. Order all other units by size, largest first.
- **No commentary.** No preamble, no summary, no opinions about quality. The
  next stage does the judging.

Two things worth stating in the unit heading itself, because they are the point
of looking at the change this way:

- If a unit's hunks span modules that have no reason to change together, say so
  in the heading, in one clause.
- A unit that is only coherent because of an accident of ordering — say that
  too.
