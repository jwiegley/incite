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

This command runs as the `code-review` agent (AI-generated-code failure modes: disabled tests,
hallucinated APIs, assertions that cannot fail, mock code on a production path). Reach for the
other specialists directly where the diff calls for them: `haskell-review`, `haskell-reviewer`,
`nix-reviewer`, `perf-reviewer`, `security-reviewer`.

**Review ladder.** This command reviews one diff — the current commit against `$1`. For a
whole-repository audit instead, or for a diff reviewed by more than one backend, use the
`agent-functor` workflows: `review-lite` (five reviewers, cheap enough per commit), `review-heavy`
(21 reviewers plus a synthesis pass, before a PR), `review-audit` (75-leaf whole-change audit
across three granularities). `/pr-review` reviews a GitHub PR in a worktree and never posts back
without explicit instruction.
