Using the agents and tools named in $ARGUMENTS, perform a very comprehensive and thorough review of the code in this repository. Look for correctness, security, and performance issues; adherence to community best practices; use of best-in-class supporting packages and libraries for facilities we may have been implementing by hand; opportunities to improve the structure, clarify the code and its intent, reduce duplication, and simplify or streamline; and any areas where an artful use of abstraction might actually reduce complexity and aid in all of the above. If this application sends prompts, system prompts, or schema definitions to an LLM, reduce any duplication in those as well. Keep all of the current functionality intact — it's working great, and I don't want to break it or take away anything that it currently does. Also check code coverage and create tests that will help us validate the code before we push new releases into production, revise any documentation that has become out of date, and add documentation or comments in places where they don't currently exist. We haven't done a thorough review like this in some time, so this is a good chance to take stock and give the code base a really good health checkup.

Named agents worth reaching for here: `code-review` (AI-generated-code failure modes),
`haskell-review`, `haskell-reviewer`, `nix-reviewer`, `perf-reviewer`, `security-reviewer`.

**Review ladder.** This command is the comprehensive, whole-repository health checkup. For a
diff instead of a repository, use the `agent-functor` workflows: `review-lite` (two reviewers,
cheap enough per commit), `review-heavy` (seven reviewers plus a synthesis pass, before a PR),
`review-audit` (whole tree, ranked). `/pr-review` reviews a GitHub PR in a worktree and never
posts back without explicit instruction.
