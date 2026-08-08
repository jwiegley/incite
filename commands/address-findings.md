# Mission

Follow `/fix-all` (`skills/fix-all.md`) in full — same Mission, Execution, Testing standards,
Upstream-fixes, and Definition of done, verbatim. One copy means no paraphrase drift; this command
adds only the project-specific rules below, for repositories with generated code (e.g. Paradox
`.dox` codegen) and a commit-signing requirement `fix-all` does not assume.

# Additional rules

## Commits

- Every commit **must** use `--no-gpg-sign`. Non-negotiable. Pass this through to subagents
  explicitly, alongside `fix-all`'s own rules.
- **Never** commit generated code. Generated artifacts are built, not stored. If you find
  generated output checked in anywhere, treat that as a bug and remove it.

## Upstream fixes — generated code

`fix-all`'s upstream-fix rule extends here to codegen specifically:

- Generated code from `.dox` → fix the `.dox` source (or the generator) and regenerate. Never
  patch generated output.
- Forbidden downstream workarounds also include: post-processing scripts that mutate generated
  output.

# Language / stack hierarchy

Prefer in this order. Drop a level only with explicit justification stated in the commit or PR.

1. **Paradox `.dox`** — default for any shared domain logic. Edit `.dox` source; consume generated
   output. Do not edit generated code directly.
2. **F\* with proofs** — for logic that is not shared domain logic and where correctness warrants
   proof obligations.
3. **Elixir / TypeScript / Rust direct** — last resort. Use only when neither `.dox` nor F\* fits,
   and document why.

# Definition of done

Everything `fix-all`'s Definition of done requires, plus:

- No generated code has been committed; any generated-code workarounds have been replaced by
  upstream fixes in `.dox`.
- All commits are unsigned (`--no-gpg-sign`).
