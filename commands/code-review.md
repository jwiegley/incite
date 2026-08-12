Arguments: `$1` is the branch or ref to compare the current commit against; `$2`, if given, narrows
the review to a focus area (e.g. "security", "the migration in db/"). Diff the current commit
against `$1` and perform a very comprehensive and thorough review of that diff. Look for
correctness, security, and performance issues; adherence to community best practices; use of
best-in-class supporting packages and libraries for facilities we may have been implementing by
hand; opportunities to improve the structure, clarify the code and its intent, reduce duplication,
and simplify or streamline; and any areas where an artful use of abstraction might actually reduce
complexity and aid in all of the above. If this application sends prompts, system prompts, or
schema definitions to an LLM, reduce any duplication in those as well. Keep all of the current
functionality intact — it's working great, and I don't want to break it or take away anything that
it currently does. Also check code coverage and create tests that will help us validate the code
before we push new releases into production, revise any documentation that has become out of date,
and add documentation or comments in places where they don't currently exist.

**Diff hygiene.** Run `git fetch origin` first, then diff with the merge-base form —
`git diff "$1"...HEAD` (three dots) — so the review sees only this branch's changes, not what
the base gained since the branch point. Prefer the remote-tracking ref (`origin/main`, never a
local `main` that may be stale). For a stacked PR, `$1` is the stack parent
(`origin/feature-part-1`), not the trunk — against the trunk the diff includes every parent
PR's changes and the review drowns in them.

This command runs as the `code-review` agent (AI-generated-code failure modes: disabled tests,
hallucinated APIs, assertions that cannot fail, mock code on a production path). Reach for the
other specialists directly where the diff calls for them: `haskell-review`, `haskell-reviewer`,
`nix-reviewer`, `perf-reviewer`, `security-reviewer`.

**Review ladder.** This command reviews one diff — the current commit against `$1`. For a
whole-repository audit instead, or for a diff reviewed by more than one backend, use the
`agent-functor` workflows: `review-lite` (six reviewers, the Haskell lens only when the diff
touches Haskell, cheap enough per commit), `review-heavy`
(24 reviewers plus regrouped views and a synthesis pass — 43 leaves, or 35 leaves with
opencode blocked — before a PR), `review-audit` (84-leaf — 57-leaf with opencode blocked —
whole-change audit across three granularities). `/pr-review` reviews a GitHub PR in a worktree
and never posts back without explicit instruction.
