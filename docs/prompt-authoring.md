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

If you add a new directory under `prompts/`, update:

- `incite-workflows.cabal` `extra-source-files`;
- the runner fileset in `flake.nix`;
- the test fileset in `flake.nix`, if tests need the prompt;
- `stePromptSrc`, if the file contains procedural prompt instructions.

The unit test suite checks the cabal side for spliced prompt files. It does not
prove the Nix fileset is complete for a brand-new directory until the build tries
to compile the splice in the sandbox.

## Deployed prompts reused by workflows

Some deployed prompts are also workflow briefs:

- `agents/code-review.md`;
- `agents/haskell-review.md`;
- `skills/fix-all.md`;
- `commands/fess.md`;
- `commands/post-commit-audit.md`;
- `commands/wiggum.md`.

This is intentional: one copy means no paraphrase drift. The cost is blast
radius. Editing one of these changes both the installed prompt and every workflow
leaf that splices it.

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

