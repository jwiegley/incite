# Testing and packaging

Incite's high-value failures are usually packaging drift, not syntax errors.
The repository can build in a git checkout while an sdist or Nix sandbox is
missing the file that a runtime prompt leaf needs. The tests are shaped around
that risk.

## Checks to run

Use the Nix checks when possible:

```bash
nix build .#checks.x86_64-linux.unit-test --no-link
nix build .#checks.x86_64-linux.ste-prompts --no-link
nix flake check
```

For fast local iteration inside the dev shell:

```bash
nix develop
cabal test
```

`nix build` of the default package verifies prompt rendering. `nix run
.#agent-functor -- plan <workflow>` verifies a workflow is exposed and can render
its skeleton, but it does not show prompt body text.

## What the unit tests fence

`test/Spec.hs` focuses on pure contracts that would otherwise fail silently:

| Area | Failure caught |
|---|---|
| `decideContinue` / `continueMarker` | a worker brief and loop matcher drifting apart |
| `orient` / reframing goldens | panels reading a worker summary as if it were the artifact |
| `document` | documentation worker losing the marker or editing-code prohibition |
| `lensesOf` | a panel keeping the same names while carrying the wrong prompt bodies |
| reorientations | upstream rubric section drift invalidating local adjustments |
| `promptLint` | the shipped workflow sending different STE instructions from the golden |
| packaging coverage | spliced prompt files or goldens omitted from `extra-source-files` |
| backends | backend names drifting from the expected cross-product |

The tests intentionally compare some full prompt bytes. Those goldens are not
formatting trivia; they are the only local fence around text that a workflow
will send to an agent.

## The two packaging lists

Every directory reachable by a workflow `promptFile` splice must be visible to
both packaging systems:

- `incite-workflows.cabal` `extra-source-files`, for cabal sdists;
- `flake.nix` filesets under the workflow runner and test sources, for Nix
  sandbox builds.

They are not cross-validated by tooling. A directory missing from
`extra-source-files` can still build under Nix and fail later in `cabal sdist`.
A directory missing from the Nix fileset can be present in cabal and still fail
at compile time inside the Nix build sandbox.

`test/Spec.hs` checks the cabal list against the prompt splices it can parse from
`Incite.Prompts`. It cannot prove every Nix fileset is complete because those
filesets are Nix expressions, not the cabal package boundary.

## STE checks

`checks.ste-prompts` runs upstream SimpleEnglish's own linter and gates exactly
three violation classes at zero:

- `latin_abbrev`;
- `contraction`;
- `slop_word`.

The gate is intentionally narrow. Other counters can be legitimate in descriptive
prompt rationale, and the regex linter cannot know which sentences are
procedural inside a mixed prompt. Use the `prompt-lint` workflow for the richer
review: it asks an agent to report rule, offending text, and rewrite over
procedural passages only.

## Goldens

Goldens live under `test/golden/` and are package artifacts. If you add one:

1. make the test read it;
2. keep `incite-workflows.cabal`'s `test/golden/*.txt` coverage intact;
3. make sure `packagingTests` still proves every golden on disk is fenced.

Do not add goldens for upstream prompt bodies. Upstream text changes when the
flake input moves, and a golden that cries wolf will get regenerated until it
stops protecting anything. Name upstream bodies in tests when you need to prove
which prompt is wired.

## Troubleshooting

`promptFile` compile failure:

- confirm the path is under the cabal package root;
- confirm the Nix fileset includes the directory;
- for upstream prompts, confirm `upstreamPrompts` grafts the directory.

Runtime prompt resolution failure:

- run from the repo root;
- inspect the candidate paths printed in the error;
- check whether `AGENT_FUNCTOR_PROMPTS` points at the expected upstream root.

Golden failure:

- first decide whether behavior changed or only the recorded bytes changed;
- if behavior changed, update the test expectation with the code change;
- if only wrapping changed, check whether the exact bytes are the contract.

STE failure:

- remove contractions, Latin abbreviations, or slop words from procedural text;
- do not rewrite a precise counterfactual only to satisfy a non-gated counter.

