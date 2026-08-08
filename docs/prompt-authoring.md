# Prompt authoring

This repository treats prompts as deployable artifacts. A prompt change can
change an installed Claude/Codex prompt, a workflow leaf, an upstream allowlist,
or a package boundary. Start by deciding which contract you are changing.

## Prompt kinds

| Kind | Declared in | Body lives in | Rendered to |
|---|---|---|---|
| `instructions` | `flake.nix` | inline or input file | `CLAUDE.md` / `AGENTS.md`-style global instructions |
| `agent` | `flake.nix` | `agents/*.md` or upstream input | native agents where supported; skills where degraded |
| `command` | `flake.nix` | `commands/*.md` or upstream input | slash command files |
| `skill` | `flake.nix` | `skills/*.md` or upstream skill dirs | skill directories |

The `prompts` list in `flake.nix` is authoritative for deployment. File layout is
only storage.

## Local workflow prompts

Use `prompts/` for markdown written specifically for workflows. Bind each body
once in `Incite.Prompts`:

```haskell
myBrief :: Prompt
myBrief = [promptFile|prompts/my-brief.md|]
```

Then compose it in `Incite.Feature` or `Incite.Review`:

```haskell
refineWith "my-leaf" (brief myBrief) id
```

If you add a new directory under `prompts/`, the Nix filesets need **no** edit:
`librarySrc` in `flake.nix` takes `./prompts` wholesale, and both the runner
and `testSrc` build on it, so any new subdirectory is already covered. What
does need an edit:

- `incite-workflows.cabal` `extra-source-files` — a new one-level glob
  (`prompts/newdir/*.md`), since cabal globs do not recurse;
- `stePromptSrc` in `flake.nix`, the fileset `checks.ste-prompts` lints (see
  [Testing and packaging](testing-and-packaging.md#ste-checks)), if the file
  contains procedural prompt instructions.

The unit test suite checks the cabal side for spliced prompt files, so a
missing `extra-source-files` glob fails `cabal test`, not just `cabal sdist`.

## Deployed prompts reused by workflows

This is the one place that lists it — README.md and AGENTS.md point here rather
than keeping their own copy.

Some deployed prompts are also workflow briefs, spliced into a `Flow` by
`Incite.Feature` or `Incite.Review`:

- `agents/code-review.md` — the `doctrine` review lens;
- `skills/fix-all.md` — the `remediate` brief;
- `commands/fess.md` — the `fess` review lens and the `fess-audit` workflow;
- `commands/wiggum.md` — the `implement`/`document` worker briefs.

This is intentional: one copy means no paraphrase drift. The cost is blast
radius. Editing one of these changes both the installed prompt and every workflow
leaf that splices it.

Two deployed prompts are `[promptFile|…|]`-bound in `Incite.Prompts` but are
**not** in the list above, and it matters why:

- `agents/haskell-review.md` is deliberately **not** bound at all — the repo
  comment on it says so: it would fire on a repo that is mostly Nix, so no
  workflow reads it. It is deployed as an agent and nothing more.
- `commands/post-commit-audit.md` **is** bound (`postCommitAudit`) so its
  compile-time `promptFile` check runs and it must stay in both packaging
  lists (see [Testing and packaging](testing-and-packaging.md)), but the bound
  value is never spliced into any `Flow` — `wiggum.md`'s own text defers to it
  by name instead of a workflow leaf reading it. Binding is not splicing;
  only the four files above are read twice.

When you add another deployed prompt that a workflow reads, make the dual use
visible in three places:

- the binding comment in `Incite.Prompts`;
- the relevant README/docs section;
- `incite-workflows.cabal` and the Nix filesets, if the file or directory is not
  already covered.

## Upstream prompt inputs

Upstream prompt text is not copied into git. `flake.nix` builds an
`upstreamPrompts` store tree from an explicit allowlist:

- `ponytail`;
- `awesome-prompts`;
- `promptdeploy`;
- `simple-english`.

To add an upstream prompt:

1. Add exactly the needed source file to the `upstream` attrset in `flake.nix`.
2. Bind it in `Incite.Prompts` under `prompts/upstream/...`.
3. Add or confirm the `extra-source-files` glob for that upstream directory.
4. Document the provenance, license, and why the file is allowed.
5. Rebuild through Nix so the grafted compile-time path and wrapped runtime path
   agree.

Do not vendor a copy under `prompts/upstream/`. In dev shells that path is a
gitignored symlink to the store.

## Frontmatter and degradation

Metadata lives in `flake.nix`, not in the body files:

- `order` controls instruction concatenation;
- `model` and `mode` select agent behavior where the tool supports it;
- `argumentHint` documents slash command arguments;
- `extraFrontmatter` carries tool-specific fields;
- `degradation = "skip"` prevents a prompt from degrading into the wrong native
  concept.

The current `code-review` agent uses `degradation = "skip"` because tools
without native agents would otherwise turn it into a skill and collide with the
`code-review` command.

## Authoring checklist

Before you finish a prompt change, check:

- Is the body declared in `flake.nix` if it is deployed?
- Is it bound in `Incite.Prompts` if a workflow reads it?
- Does every `promptFile` directory exist in `extra-source-files`?
- Can the runner and test Nix filesets see the file?
- Should `checks.ste-prompts` lint it mechanically?
- Does a workflow contract need a golden or pure test fence?
- Did you update docs for any prompt that is read twice?
- Did you avoid copying upstream text into git?

