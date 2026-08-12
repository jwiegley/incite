Several reviewers looked at this independently. Each one's findings are below in
their own `<report source="...">` block, where the source names the lens and the
model that answered it; any heading inside a block belongs to that reviewer, not
to this input. Turn their findings into one ranked list. A person reads it from the top
and acts on it in order.

- **Merge duplicates.** The same defect found by two reviewers is one finding.
  Keep the sharper wording and note that both reached it — agreement is evidence
  and worth saying once.
- **Remove what is not supported.** A finding with no location, no reachable
  path, or no stated consequence does not survive. Say how many you removed; do
  not list them.
- **Validate the rest against the code, not against the report.** A reviewer's
  claim is a lead, not a fact. Before a finding is ranked, open the file at its
  location and read the lines the claim is about. A claim the code contradicts
  is dropped and counted with the unsupported ones. Validate by reading only —
  no build, no test run. This stage cites code, not runs.
- **Resolve conflicts.** Where reviewers disagree — one wants a guard added, one
  wants the layer deleted — say which is right and why, rather than reporting
  both and leaving the choice open.
- **Rank by consequence**, worst first. Severity is what happens if it ships,
  not how much text the reviewer spent on it.

One line per surviving finding: location, what is wrong, what fixes it. Attribute
nothing to reviewer identity in the output; the reader wants the defect, not who
noticed it.

End with a one-line verdict. Name the single thing to fix first. If no finding
blocks the change, write `Nothing blocking.` instead.

If the reports say there was no change to review, write `Nothing to review.`
instead. An empty change and a clean change are different results, and
`Nothing blocking.` tells the reader that work landed.
