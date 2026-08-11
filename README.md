<div align="center"><h1>V&nbsp;&nbsp;&nbsp;I&nbsp;&nbsp;&nbsp;O&nbsp;&nbsp;&nbsp;L&nbsp;&nbsp;&nbsp;E&nbsp;&nbsp;&nbsp;N&nbsp;&nbsp;&nbsp;C&nbsp;&nbsp;&nbsp;E</h1></div>

---

Declarative AI agent configuration. Instructions, sub-agents, slash commands, and
skills — declared once in Nix, deployed everywhere. Plus a set of typed
multi-agent workflows that drive the agent from the outside.

Two halves, one flake:

- **Prompts** — built on [Flake Prompt](https://gitlab.com/fresheyeball/flake-prompt),
  which renders prompt definitions into the native on-disk formats for Claude
  Code, Codex, opencode, Crush, and Droid.
- **Workflows** — built on `agent-functor`, a typed workflow library (local
  checkout, no remote yet). Workflows are `Flow Text Text` values composed with
  `>>>`; the CLI (`list`/`plan`/`cost`/`run`) and a live TUI for `run` come for
  free.

This README is the entry point. The maintained reference docs live under
[`docs/`](docs/README.md):

| Topic | Doc |
|---|---|
| repository shape and source-of-truth boundaries | [Architecture](docs/architecture.md) |
| workflow inventory, modes, and leaf counts | [Workflows](docs/workflows.md) |
| adding prompts, commands, agents, and skills | [Prompt authoring](docs/prompt-authoring.md) |
| Nix, cabal, goldens, and regression checks | [Testing and packaging](docs/testing-and-packaging.md) |
| deployment, input updates, runtime state, and cleanup | [Operations](docs/operations.md) |

`AGENTS.md` is the condensed editing brief for agents. The `workflows/*.hs`
Haddock is the implementation reference.

## Quickstart

Three commands cover the first five minutes:

```bash
nix build                                     # render prompts/agents/commands/skills into result/
nix run .#agent-functor -- list               # the workflows this repo defines
nix run .#agent-functor -- plan plan-feature  # what one workflow does, offline
```

- Want the prompts on your machines? [Deploying the prompts](#deploying-the-prompts).
- Want to run a workflow against a real request?
  [Running the workflows](#running-the-workflows).
- Want the workflow engine explained? [Workflow vocabulary](#workflow-vocabulary)
  and [The review tiers](#the-review-tiers).

## Structure

```
flake.nix          — every prompt definition + the two packages
agents/            — sub-agent bodies
  voice.md         — personality agent
  code-review.md   — AI-generated-code failure modes only (disabled tests,
                     hallucinated APIs, tests that cannot fail). Defers language,
                     security and performance to the specialists below
  haskell-review.md — the LOCAL Haskell addendum to upstream's haskell-reviewer:
                     newtypes over aliases, smart constructors, IO isolation —
                     and orphan instances are fine here, overruling upstream.
                     NOT a workflow brief: `Incite.Prompts` deliberately does
                     not splice it — it would fire on a repo that is mostly
                     Nix. Deployed as a Claude/Codex agent only
  compiler.md      — Haskell/type-theory specialist (Opus)
  fess-auditor.md  — evidence-backed honesty check on a finished session
commands/          — slash command bodies (frontmatter lives in flake.nix)
  fess.md          — the honesty rubric
                     ALSO read as a workflow brief — see below
  post-commit-audit.md — the ONE description of the post-commit check;
                     /wiggum defers to it in its own text, but neither
                     `wiggum` nor any workflow splices it — it is deployed as
                     `/post-commit-audit` and read back nowhere else
  wiggum.md        — the autonomous loop
                     ALSO read as a workflow brief — see below
skills/            — skill bodies
  fix-all.md       — fix every finding found along the way, no "out of scope"
                     ALSO read as a workflow brief — see below
  pr-review.md     — interactive, strictly read-only PR review in a worktree
  pr-comment.md    — draft one comment into the pending review
  pr-fix.md        — apply one change via a subagent, push to the PR head
workflows/
  Main.hs          — the typed workflows; `passMain` gives them a CLI
docs/              — maintained human-facing reference docs
prompts/           — prompt bodies for the workflows, read at RUN time
  plan.md          — turn exploration findings into a one-step-per-line plan
  plan-step.md     — review one plan step for correctness/completeness/ordering
  plan-denotational.md, plan-risk.md, plan-verification.md — three of
                     `editPlan`'s six code-oriented plan-edit lenses (the other
                     three are `ponytailLadder`, the `lookahead` rubric, and
                     the local `simple-english` lens, all upstream or inline)
  explore/*.md     — the four explore stances: intrepid, skeptic, contemplative,
                     architect
  review/*.md      — the LOCAL review lenses fanned out by `review-lite`/
                     `-heavy`/`-audit`/`-docs`: correctness, complexity, tests,
                     architecture, docs-completeness/structure. Security,
                     performance and Haskell lenses are upstream — see "Upstream
                     prompts" below. Docs accuracy is not a file here: it is
                     `docsAccuracy` in `workflows/Incite/Review.hs`, a
                     reorientation of `commands/fess.md`'s rubric at prose.
                     Three files here are NOT lenses: synthesis.md (the reducer
                     brief) and units.md / sequence.md, which re-express a
                     change for the granularity axis of `review-heavy` and
                     `review-audit` without judging it
  retro/*.md       — the `retro` columns, read over a SESSION rather than a
                     diff: sentiment, went-well, went-wrong, and synthesis.md,
                     the meeting brief that turns them into `## next time`
  upstream/        — NOT IN THIS REPO. A /nix/store path supplied by the
                     `ponytail` and `awesome-prompts` inputs; gitignored, and
                     a devShell symlink locally. See "Upstream prompts" below
incite-workflows.cabal  — builds a binary named `agent-functor`; rooted at the
                          REPO ROOT so a `prompts/…` path means the same thing at
                          compile time and at run time
```

The `prompts` list in `flake.nix` is the authoritative inventory — every prompt
is declared there, so read it rather than counting files.

Two more prompts are read out of the private `macha` input rather than this
repo: the `agentic-philosophy` instructions block and the `fstar-erlang-ell`
command. The four `ponytail-*` skills come out of the `ponytail` input the
same way — see [Upstream prompts](#upstream-prompts).

### Prompts read twice

`agents/`, `skills/` and selected `commands/` do double duty: flake-prompt
renders them to `~/.claude`, *and* the workflows read those same files as briefs
at run time. `agents/code-review.md` is the doctrine reviewer leaf, `skills/fix-all.md`
is the remediation brief, and `commands/{fess,wiggum}.md` are read back by the
workflow beats — `commands/post-commit-audit.md` is bound in `Incite.Prompts`
too, but no workflow leaf splices it; see
[Prompt authoring](docs/prompt-authoring.md#deployed-prompts-reused-by-workflows)
for the authoritative list and why. One copy, no paraphrase, so editing any of
the four spliced files changes both the deployed prompt and the workflow.

The bill for that is real: `code-review.md` is ~10 KB and every leaf using it
sends the whole thing, so a workflow reading it costs materially more per turn
than one with a one-line brief. `workflows/Incite/Prompts.hs` says so at the
binding.
Note that `cost` will *not* show you this — it reports worst-case leaf
executions, the dominating bound and the node count, never tokens, so a leaf
carrying 10 KB and a leaf carrying one line both count as 1.

### Prompt types

| type | renders to |
|---|---|
| `instructions` | `~/.claude/CLAUDE.md` (concatenated in `order`) |
| `agent` | `~/.claude/agents/<name>.md` |
| `command` | `~/.claude/commands/<name>.md` |
| `skill` | `~/.claude/skills/<name>/SKILL.md` |

Per-prompt knobs used here: `order` (instructions only — the concatenation
order in `CLAUDE.md`), `model`, `mode`, `argumentHint`, `extraFrontmatter`
(temperature, tool denials, `agent =` binding, skill `author`/`invocation`),
and `degradation = "skip"` — which drops a prompt on tools that lack the
native concept instead of degrading it into something that collides. Only
`code-review` sets `skip` today: tools without native agents would degrade the
agent into a skill, colliding with the `code-review` *command* already
deployed as a skill there.

### The PR-review trio

`pr-review` is the entry point and the other two are its companions — they are
meant to be invoked *during* a review, not standalone:

- **`/pr-review <pr-number>`** sets up an isolated worktree and walks the diff
  one logical group of hunks at a time, strictly read-only, pausing for
  discussion. Ends with a holistic adversarial pass, then leaves a background
  babysitter keeping the PR mergeable. Understands Graphite stacks — `next`
  advances upstack as a fresh review.
- **`/pr-comment <feedback>`** turns one piece of feedback into a minimal,
  actionable comment on the *pending* GitHub review. Nothing submits until you
  explicitly say so — the whole review posts as one batch.
- **`/pr-fix <change>`** hands one change to a subagent in a *separate*
  worktree and pushes it to the PR head branch. The review worktree stays
  untouched, so reviewing and fixing never fight over the same tree.

The split is deliberate: the reviewer never writes, the fixer never reviews.

## Inputs

| input | source | note |
|---|---|---|
| `flake-prompt` | `gitlab:fresheyeball/flake-prompt` | the renderer |
| `macha` | private ssh, `flake = false` | supplies two prompt bodies |
| `ponytail` | `github:dietrichgebert/ponytail`, `flake = false` | four skills + three workflow briefs |
| `awesome-prompts` | `github:ai-boost/awesome-prompts`, `flake = false` | exactly seven files: `agentic_coder.txt`, `lookahead_planning_specialist.txt`, `code_reviewer_security.txt`, `Technical_Documentation_Strategist.txt`, `stop_slop.txt`, `qa_agent.txt`, `obsidian_vault_operator.txt` |
| `promptdeploy` | `github:jwiegley/promptdeploy`, `flake = false` | the upstream this repo's prompts descend from — pinned to reconcile against, plus four sub-agents |
| `simple-english` | `github:AminBlg/SimpleEnglish`, `flake = false` | ASD-STE100 as a skill, a plan lens, and the `prompt-lint` rubric |
| `agent-functor` | `git+ssh://git@gitlab.com/fresheyeball/agent-functor` | the workflow library, `refs/heads/master` |

`agent-functor` is pinned to its own nixpkgs (its Haskell deps want 24.11), so
it deliberately does *not* `follows` incite's unstable.

It is the one input taken over **ssh from GitLab** rather than `github:`/
`gitlab:`, so evaluating it needs SSH access to `gitlab.com` as `git`. It was
previously `git+file:///home/isaac/_/agent-functor/master`, a local worktree
that no other machine had; the remote is what makes the lock mean the same
thing everywhere.

The consequence to hold on to: `nix flake update agent-functor` reads the
remote, so **push first** — an unpushed local commit re-locks the old revision
and looks like it worked. That rule is in the comment above the input in
`flake.nix`.

### Upstream prompts

Four inputs supply prompt text this repo does not author — ponytail,
awesome-prompts, promptdeploy, and SimpleEnglish — contributing ten files under
`prompts/upstream/` between them. None is taken as a flake — all four come in
with `flake = false` and their files are read directly.

**Nothing is copied into git.** The update path is exactly:

```bash
nix flake update ponytail     # or awesome-prompts, promptdeploy, simple-english
# then rebuild — that's it
```

[ponytail](https://github.com/DietrichGebert/ponytail) lands in two places:

- **Skills.** `ponytail`, `ponytail-review`, `ponytail-audit` and
  `ponytail-debt` are rendered from `${ponytail}/skills/*/SKILL.md` with their
  own YAML frontmatter stripped (flake-prompt writes frontmatter itself). They
  are deployed as *skills* rather than as an always-on `instructions` fragment:
  ponytail's descriptions are written to trigger the model on coding work,
  which is the right activation surface. `ponytail-gain` (a benchmark
  scoreboard) and `ponytail-help` (a card for `/commands` this repo does not
  install) are deliberately left out.
- **Workflow briefs.** `prompts/upstream/ponytail/{ladder,review,audit}.md`.

One name per capability, all the way down — so `ponytail-audit` means the same
thing whether you hit it as a skill in a chat or a file on disk. Neither is a
workflow or MCP tool of its own: `ponytailReviewRubric` and
`ponytailAuditRubric` are lens bodies, spliced into the `ponytail` lens of
`review-lite`/`review-heavy`/`review-audit` (the diff and whole-change forms)
and into `docsAccuracy`'s sibling `ponytailOfDocs` for `review-docs`.

| upstream | skill | prompt file | `Incite.Prompts` binding | used as |
|---|---|---|---|---|
| `skills/ponytail-review` | `ponytail-review` | `ponytail/review.md` | `ponytailReviewRubric` | the `ponytail` lens of `review-lite`/`review-heavy` |
| `skills/ponytail-audit` | `ponytail-audit` | `ponytail/audit.md` | `ponytailAuditRubric` | the `ponytail` lens of `review-audit` |
| `skills/ponytail-debt` | `ponytail-debt` | — | — | — |
| `AGENTS.md` | `ponytail` | `ponytail/ladder.md` | `ponytailLadder` | spliced into the `ship-feature`/`ship-docs` implementer and fixer briefs |

[awesome-prompts](https://github.com/ai-boost/awesome-prompts) supplies exactly
three named files, verbatim:

| upstream | as | drives |
|---|---|---|
| `prompts/agentic_coder.txt` | `awesome-prompts/agentic-coder.md` | the `ship-feature` worker brief |
| `prompts/lookahead_planning_specialist.txt` | `awesome-prompts/lookahead-planning-specialist.md` | the unexposed `plannerAudit` value **and** the `lookahead` lens |
| `prompts/code_reviewer_security.txt` | `awesome-prompts/code-reviewer-security.md` | the `security` lens of `review-heavy` and `review-audit` |

The rest of that 3.5 MB repo is unaudited third-party text and the `upstream`
attrset in `flake.nix` is the allowlist that keeps it out.

#### promptdeploy — the upstream this repo descends from

[promptdeploy](https://github.com/jwiegley/promptdeploy) (BSD 3-Clause, © 2025-2026
John Wiegley) is not a dependency. It is pinned as the **upstream to reconcile
against**: this prompt set descends from John Wiegley's, and until it was pinned
there was no way to tell drift from deliberate divergence.

**The rule is: the local prompt wins unless there is a stated reason it does not.**

| local | upstream | verdict |
|---|---|---|
| `commands/wiggum.md` | `skills/wiggum/SKILL.md` | **ours** — ours is MCP-wired to agent-functor (`fess-audit` / `review-lite` tool calls); theirs depends on Anvil, PAL, Graphite and `doc/observations/` |
| `commands/fess.md` | `commands/fess.md` | **ours** |
| `skills/fix-all.md` | `skills/fix-all/SKILL.md` | **ours** — it is also a workflow brief |
| `agents/fess-auditor.md` | `agents/fess-auditor.md` | **ours** |
| `commands/commit.md` | `commands/commit.md` | **theirs**, plus two re-asserted invariants — see below |
| `agents/code-review.md` | *(no counterpart — split by language)* | **split**, see below |
| `commands/code-review.md` | `commands/code-review.md` | **theirs** |

Two places where "take upstream" is not literal:

- **`commit`.** Upstream's methodology is far richer than the 3-liner it replaced —
  atomic logically-sequenced commits, decomposition categories, message format,
  staging strategy, a quality checklist. But it never mentions `--no-gpg-sign`, and
  the global rules make that mandatory; it also drops the no-assistant-branding
  rule. Both are re-asserted at the top of the file as **Non-negotiable**.
- **`code-review`.** Upstream has no `agents/code-review.md` at all — it splits
  review into per-language agents plus `perf-reviewer` and `security-reviewer`. Our
  523-line agent was two documents glued together, so it was split the same way:
  the Haskell half moved to `agents/haskell-review.md`, the security, performance
  and test-quality halves were deleted as covered by the specialists, and what
  remained — AI-generated-code failure modes, which has no upstream counterpart —
  kept the filename and the `codeReview` binding. 18 KB → ~10 KB, and the
  `doctrine` lens got cheaper as a side effect.

Four sub-agents are deployed from it, and two are read twice (agent *and*
`review-heavy` lens) the way `agents/` and `skills/` already are:

| upstream | deployed as | also a lens? |
|---|---|---|
| `agents/haskell-reviewer.md` | `haskell-reviewer` | yes — `haskell` |
| `agents/perf-reviewer.md` | `perf-reviewer` | yes — `performance` |
| `agents/nix-reviewer.md` | `nix-reviewer` | no |
| `agents/security-reviewer.md` | `security-reviewer` | no (the lens is awesome-prompts' OWASP rubric) |

**Taken as a source, not as a flake**, although it is one. Its `.gitmodules` points
`translate-tool` at `/Users/johnw/work/translation/translate-tool` — an absolute path
on the author's machine — while its flake sets `self.submodules = true`, so a
submodule fetch cannot succeed from here; `flake = false` over a `github:` URL never
looks at submodules. It would also drag its whole closure into our lock (nixpkgs,
home-manager, flake-utils, and a *second* ponytail pin beside ours). And
promptdeploy's own deployer — a Python CLI with SHA-256 manifests and rsync over
SSH — is not adopted: `flake-prompt` is a pure-Nix renderer producing a package
plus the `lib.prompts` inventory nixos-dots consumes, and swapping loses that
for capabilities this repo does not need.

Never pulled in: host-tagged items (the `-- positron` / `-- personal` filetags are
his machines), anything depending on Anvil (his Emacs MCP) or PAL, and the
persian/`translate-tool` material.

#### SimpleEnglish — ASD-STE100

[SimpleEnglish](https://github.com/AminBlg/SimpleEnglish) (MIT, © AminBlg) packages
ASD-STE100 Simplified Technical English: the controlled language aerospace and
defence use for maintenance manuals, so a tired reader who is not a native speaker
cannot misread an instruction. 53 rules — imperative mood, sentence-length caps,
simple tenses only, active voice, one word per meaning, condition before command.

The rule that makes it usable here is STE's own split between **procedural** text
(what the reader must do) and **descriptive** text (explanation). Every prompt this
repo ships is both, and only the procedural half has to survive one read. Applied
unscoped it would flag the explanatory prose too, which is elaborate on purpose.

Three uses, at two grades:

| use | grade | why that grade |
|---|---|---|
| the `simple-english` **skill** | the full skill + its `references/` | deployed by `skillFromDir`; for writing docs, READMEs, runbooks |
| the `simple-english` **plan lens** | `prompts/system-prompt.md` (2,947 B) | enough to *rewrite* a step; cheap enough to run on every plan |
| the `prompt-lint` **workflow** | `SKILL.md` (~19.7 KB) | the only grade carrying the CHECK contract |

**As a plan lens it runs last, and that is the point.** A plan step is procedural
text in STE's exact sense — one instruction, executed by an agent that never sees
the surrounding context. Imperative, ≤20 words, condition before command, one word
per meaning across the whole plan. But it is a *wording* pass, and every lens before
it still changes which steps exist, so rewording ahead of them is wasted. Its brief
says so explicitly: reword only, add nothing, remove nothing, reorder nothing.

**And `checks.ste-prompts` is the regression gate**, using upstream's own
`evals/ste_lint.py` rather than a reimplementation. It runs the linter's
`--self-test` first (upstream ships a slop fixture and a clean one, asserting both
directions), then gates exactly three classes at zero across the prompt files:
`latin_abbrev`, `contraction`, `slop_word`. Those three have no legitimate use
here, so there is no baseline to game.

The other counters are deliberately **not** gated, and the reason is the same one
that shaped the lens: `banned_modal` cannot be zero because "would" carries a real
counterfactual (*"what would still pass if the code were wrong"* **is** the tests
lens), and `sentence_over_limit`/`semicolon` would fire on descriptive rationale,
which is not a defect. The linter cannot tell procedural from descriptive *within*
a file — that judgement is what the `prompt-lint` workflow is for. So the gate
catches the mechanical half and says so; it cannot catch an ambiguous pronoun, and
no regex can.

The allowlist in `stePromptSrc` is explicit rather than a glob: a new prompt gets
gated when someone adds it there, which is also when they decide it is procedural.

**As `prompt-lint` it uses the big grade on purpose.** `SKILL.md` is the only one
of the two that carries the CHECK contract — *report each violation as rule number,
offending text, compliant rewrite* — along with its own warning that the STE
numbering is unintuitive and models cite it from memory (it names an observed case
where an agent invented "Rule 3.1: short sentences"). That grounding is the entire
value of a linter; one citing invented rule numbers is worse than none.

#### How `prompts/upstream/` works without being in the repo

`Agent.Prompt.promptFile` needs its path in two different places: it exists-checks
it against the package root at **compile** time and reads it relative to the
working directory at **run** time. A `/nix/store` path is neither, so each phase
gets pointed at the store separately:

| phase | mechanism |
|---|---|
| `nix build` compile | the `agent-functor` package grafts `${upstreamPrompts}/prompts/upstream` into its `src` |
| `nix run` runtime | the binary is wrapped with `AGENT_FUNCTOR_PROMPTS` set to that same derivation |
| `cabal build` / HLS | the devShell `shellHook` symlinks it to `./prompts/upstream` (gitignored) |

`AGENT_FUNCTOR_PROMPTS` is the *first* candidate a prompt reference resolves
through and the store root holds **only** `prompts/upstream/**` — so the upstream
briefs hit there and every repo-local brief misses and falls through to `$PWD`,
which is what keeps `prompts/plan.md` and `agents/code-review.md` live-editable.
`--set-default`, so an explicit `AGENT_FUNCTOR_PROMPTS=…` still wins.

The one cost: unlike every other prompt here, the upstream four are **not**
live-editable. The store is read-only; changing them means changing the input.

## Deploying the prompts

### Via nixos-dots (dunlap)

The [nixos-dots](https://gitlab.com/fresheyeball/nixos-dots) flake consumes
this one as `inputs.incite`, reads the raw definitions off `lib.prompts`, and
wires them through `services.agent-pm` for the `isaac` user. Changes committed
here take effect on the next:

```bash
sudo nixos-rebuild switch --flake ~/dots#dunlap
```

### Standalone

```bash
nix build
```

`result/` holds one tree per enabled tool — the default package turns on both
`claude` and `codex`:

```
result/.claude/CLAUDE.md               result/.codex/AGENTS.md
result/.claude/agents/<name>.md        result/.codex/prompts/<name>.md
result/.claude/commands/<name>.md      result/.codex/skills/<name>/SKILL.md
result/.claude/skills/<name>/SKILL.md
```

The two trees are deliberately not mirror images. Commands map across one to
one, but codex has no sub-agent concept, so agents degrade into skills there —
`.codex/skills/` ends up holding the real skills *plus* every agent that does
not set `degradation = "skip"`: `voice`, `compiler`, `fess-auditor`,
`haskell-review`, and the four `promptdeploy` specialists
(`haskell-reviewer`, `nix-reviewer`, `perf-reviewer`, `security-reviewer`) —
eight in total, and not `code-review`, per the `skip` above. That asymmetry is
the degradation policy working, not a rendering bug.

## Running the workflows

__Run these from the repo root.__ The workflow prompt bodies are
`Agent.Prompt.promptFile` references — checked when the binary compiles, read
from disk when it runs. A reference resolves through three candidates, first
readable file wins:

1. `$AGENT_FUNCTOR_PROMPTS/<path>` — set this to run from anywhere else
2. `<cwd>/<path>` — the normal case, and why "from the repo root"
3. the compile-time source directory — a live tree under plain `cabal`, a
   deleted `/build/…` under `nix`

A miss dies with every candidate listed, so the error tells you which one you
wanted. The one to watch is #3: a `cabal build` binary finds its prompts from
*any* directory, a `nix`-built one only from the repo root. Same source, two
different behaviours — test the way you deploy.

The upside of reading at run time: edit a `prompts/*.md` (or the `agents/` and
`skills/` bodies the workflows reuse) and re-run. No rebuild. Two prices for
that: a prompt file is deliberately **not** a recompilation dependency, so
deleting or renaming one is a *run*-time failure rather than a build error;
and each body is read once per process, so editing a prompt mid-run does not
take effect until the next run.

```bash
nix run .#agent-functor -- list              # what's defined
nix run .#agent-functor -- plan plan-feature # the flow skeleton, offline
nix run .#agent-functor -- cost plan-feature # worst-case leaf executions, offline
nix run .#agent-functor -- run  plan-feature -i "add a --json flag"
```

`run` flags: `--backend NAME` (default `claude-agent`), `--model KEY`,
`-i/--input TEXT` (prompts on a tty if omitted — and on a workflow with a
baked-in default input, an explicit `-i` replaces that default rather than
steering it), `--sandbox` (isolate a world-acting run in a throwaway worktree
instead of editing in place — the result is committed to an
`agent-functor/run-…` branch; prompt-only flows have nothing to isolate and
always run in place), `--concurrency N` (caps concurrent fan-out sessions;
defaults to 6, or the workflow's own `withConcurrency`; `0` = unbounded, which
can burst a rate-limited backend into an aborting 429). Full detail on every
flag, the known-backend list, and the `claude-agent` model pin lives in
[Operations](docs/operations.md#run-workflows).

`run` picks its front-end off the terminal. On a tty it drives the **live
TUI**: a context header, a stage list that fills in as leaves complete, a
scrolling agent transcript with styled inline tool calls, and modals for the
points where a flow blocks on you — `steer`, `humanGate`, and any permission
prompt answer straight out of the TUI. Piped or in CI it falls back to an
inline transcript and those same blocking points drop to plain stdin asks — but
an unattended run (served over MCP, where `gateAnswer` defaults to `"yes"`)
auto-answers `steer` and `humanGate` rather than stopping: `ship-feature` runs
through to a real `submitPR`, with the PR leaf's title and body currently fixed
constants (`"Add --json flag"` / `"Drafted by the ship-feature workflow."`,
regardless of the actual request) rather than derived from it. `plan` and `cost`
never touch an agent, so they work anywhere.

### Workflow vocabulary

The workflows are `Flow Text Text` values — one text artifact transformed into
another, leaf by leaf. The terms the rest of this section uses:

- **Leaf** — one agent call: a prompt, the artifact so far, and how to use the
  answer. The cheapest unit you can inspect; `cost` reports worst-case leaf
  executions, and a one-line brief and a 10 KB brief both count as 1.
- **Fan-out (`exploreFlows`)** — run several leaves concurrently on the same
  input, then reduce. The review tiers are a fan-out: independent reviewers,
  each pinned to its own backend and read-only (`withMode Plan`).
- **Panel** — one lens × one backend, blocked as `lens@backend`. "The
  21-reviewer panel" is 7 lenses × 3 backends.
- **Lens** — one deliberately narrow reviewer: correctness, security, tests,
  performance, Haskell, ponytail (complexity), AI-generated-code failure modes,
  architecture, and the docs triplet. A lens that wanders into another's
  territory costs a turn and returns a duplicate.
- **Regrouping** — an agent leaf that re-expresses the change (as logical
  units, or as the commits it should have been) so a panel can review a
  different shape of it. The granularity axis, not a third lens.
- **Orchestrator loop (`loopUntil`)** — one worker leaf (the only leaf that
  edits files) is re-run on its own closing summary until it ends on
  `WORK COMPLETE` rather than the `continueMarker`; up to 8 trips.
- **Gate** — where a run blocks on a human: `steer` (before the work starts),
  `humanGate` (before the PR). An unattended run auto-answers them.
- **`execGrant`** — the whitelist of commands a world-acting workflow may run
  (`nix*` here); everything else is denied. The agent's own `git` and `gh` run
  as its own tools, behind its permission modal.

The inventory in `workflows/Main.hs` — each workflow is defined in
`Incite.Feature` or `Incite.Review`, and only what that list names is exposed.
The full table of all 12 workflows and what each does lives in one place:
[`docs/workflows.md`](docs/workflows.md#exposed-inventory).

Two safety facts worth repeating here: four workflows are **world-acting** and
every other one is prompt-only. `ship-feature` and `ship-docs` run under
`actingGrant` (`execGrant ["nix*"]`); `grind-paradox` and `stack-prs` run under
grants derived from their own check lists, so a check and its permission cannot
drift apart. Whichever grant applies, it gates only the commands *we* run — the
agent's own `git`, `gh` and `gt` run as its own tools, behind its permission
modal. Always run from the repository root, since `promptFile` resolves
a path against the package root at compile time and the working directory at
run time, and those must be the same directory.

Where the [upstream briefs](#upstream-prompts) land:

- ponytail's **ladder** — the `ponytail` lens runs **first** in the shared edit
  stage, so the later lenses only annotate steps that survive it, and it rides
  along with `fix-all` on every work beat.
- ponytail's **review** and **audit** rubrics — panel lenses, same tags and
  scoring, pointed at a diff (`review-lite` and the `review-heavy` panel) or at
  the whole change (`review-audit`).
- **agentic-coder** — opens the brief for the implementer in `ship-feature`, the
  first leaf in either workflow that writes to a file. That is where
  read-before-editing and the security checklist have to land, not at the review
  beats after it.

The implementation brief is a three-document composition, each answering a
different question — `agentic-coder` **how** to write it (plan first, read before
editing, tests are not optional), ponytail's ladder **how much** (stop at the
first rung that holds), and `commands/wiggum.md` **how long** (to completion,
with a handoff document, auditing its own commits). ~8 KB per turn: deliberate,
because it is the only leaf where an agent writes code unsupervised.

They pull against each other on purpose — `fix-all` and `wiggum` push for
completeness, the ladder for the shortest diff, `agentic-coder` for the
discipline that keeps a short, complete diff from also being an unread and
untested one.

### The two mid-run checks

After every commit, two tools fire — **both**, concurrently, because they judge
different things and either can pass while the other fails:

| | `fess-audit` | `review-lite` |
|---|---|---|
| judges | **you** — your claims against what you actually did | **the code** — the diff just committed |
| input | your session (see below) | the diff (`git show`) |
| catches | a skipped step reported as done, a test claimed but not written, a dropped caveat | correctness defects and over-engineering |
| a finding means | your account is wrong — fix the record *and* do the work | the code is wrong — fix it |

They are MCP calls back into **this very binary**: both are workflows in the
`workflows` list, served by `agent-functor mcp`. Start both, poll `status`, read
`output`. No subagents, no context snapshot to assemble, and no filesystem
coordination — the old `doc/observations/` protocol is gone.

`fess-audit` is one of two workflows here marked **`withCapturedTranscript`**, and
that mark is what makes it work. A run advertises its own MCP endpoint to the
sessions it opens; a workflow with that mark, called through it, gets the worker's
captured conversation as input instead of whatever the caller passed, and its
input requirement is bypassed. Its subject genuinely *is* the session.

`retro` is the other one, and it carries the mark for the same reason — a
retrospective is about the session or it is about nothing. It is not on this
beat: `fess-audit` asks *is this account true* after every commit, `retro` asks
*how did this session go* once, at the end, and answers with changes to make next
time.

Nothing else declares it, deliberately. The endpoint serves the whole `workflows`
list, so `review-lite` — fired on the same beat — keeps the caller's input and
receives the diff it was handed. That opt-in did not exist until recently:
agent-functor substituted the transcript for *every* workflow started through a
trigger endpoint, which would have handed `review-lite`'s diff-shaped reviewers a
conversation log. Fixed upstream in `Agent.Run` (`withCapturedTranscript` /
`TriggerInput`, rev `800ea38`) and pinned here.

On a plain `agent-functor mcp` server there is no capture, so `withCapturedTranscript`'s
mark is **inert** rather than fess-audit vanishing: `fess-audit` is still callable,
still a `workflowReq` that demands an explicit `-i`/`--input`, and with no
transcript to substitute there is nothing sensible to hand it there — outside a
run, `review-lite`'s `fess` lens is the practical whole of it. `retro` carries the
identical mark and the identical gap; nothing here documents that one separately.

**Findings then go to a subagent running `fix-all`**, not fixed inline. The
checks are tool calls and the fix is a subagent for opposite reasons: a check
needs a different *model* (independence) and the server already holds its context,
while a fix needs a different *context* — `fix-all`'s "no exceptions, no excuses,
no deferrals" standard is exactly what gets quietly traded away for momentum when
applied in the middle of the task it is interrupting, and the cleanup shouldn't
fill the worker's context either. The worker still owns the result: it reads what
the subagent changed, verifies the build itself, and commits. That commit gets
neither check and no second `fix-all` — the loop has to terminate.

**It is said once.** `commands/post-commit-audit.md` is the only description of
which checks to run, what to pass them, and how to poll. It is deployed as the
`/post-commit-audit` slash command, and `wiggum.md`'s own text defers to it by
name rather than restating it — but no workflow leaf splices
`commands/post-commit-audit.md` itself. It is not the third "read twice" prompt
alongside `fess` and `wiggum`: `postCommitAudit` is bound in `Incite.Prompts`
and exported, but nothing in `Incite.Feature` or `Incite.Review` reads it. The
enforcement is `wiggum`'s own text, spliced into the `ship-feature`/`ship-docs`
worker briefs (`implement`, `document`) — not `remediate`, the fixer — telling
the worker to follow the procedure `post-commit-audit.md` describes.

The duplication that arrangement replaced had already drifted: `wiggum` had come
to say one call while the beat said two. What each caller still owns is what the
audit deliberately leaves open — who applies the findings (wiggum: a `fix-all`
subagent) and, in a loop, that the fix commit gets no second subagent either.

### The review tiers

`review-lite`, `review-heavy` and `review-audit` are one shape at three prices:
fan **independent** reviewers over the same artifact concurrently, then reduce.
Every reviewer is read-only (`withMode Plan`) and pinned to its own backend, so
the independence is real rather than one model answering the same question under
several headings.

Leaf counts per tier — lenses × backends × granularities, and how each is
reduced — live in one place:
[`docs/workflows.md`](docs/workflows.md#review-tiers-and-leaf-counts). All
four review tiers are prompt-only and read-only; none holds `actingGrant`.

The tiers escalate along three independent axes, and each buys something different.
**Lenses** buy coverage — `review-lite` spreads four across backends for cheap
independence; `review-heavy` adds security, tests, performance and Haskell;
`review-audit` adds architecture. **Backends** buy confidence: from `review-heavy`
up, every lens is answered by all three models, so agreement is confirmation and
disagreement is signal rather than one model's opinion. **Granularity** re-expresses
the change so a shape of finding the flat diff cannot show becomes visible — and
`review-heavy` already does it, cheaply (below); `review-audit` is the same axis
with the full three-backend panel and an architecture lens behind every view.

#### The granularity axis

`review-heavy` and `review-audit` both re-express the change and re-review the
views; the tier is a price escalation, not a presence. `review-heavy` runs its
7-lens panel over the diff as it landed, then regroups the change and runs the
same lenses over each regrouped view on claude-agent alone; `review-audit` runs
the whole 24-reviewer panel three times, over the same three views:

| view | what the panel reads | what only this view finds |
|---|---|---|
| `full` | the change as it landed | what is wrong with the result |
| `units` | the change regrouped into logical units (`prompts/review/units.md`) | a unit whose hunks span modules that should not change together — invisible in a full diff |
| `sequence` | the change as the commits it *should* have been (`prompts/review/sequence.md`) | its `## divergence` section: hunks that **cannot** be separated name a coupling in the code, and work that cancels itself out shows as a step undoing an earlier one |

Both regroupings are agent leaves, not pure splits — "logical unit" and "ideal
sequence" are semantic judgements, so nothing `T.lines`-shaped can produce them
(unlike a plan, where each lens's own instructions make one line one step, by
convention rather than by a parser). Both are told
to reproduce every hunk exactly once, verbatim, because the panel reads their
output *as* the change: anything elided is invisible to the reviewers of that
view.

**Architecture is reframed for the change.** `prompts/review/architecture.md` is
written whole-tree and says so. Inside `review-audit` it is composed with a
reorientation that keeps its questions — leaking boundaries, arrows pointing the
wrong way, one decision in many homes — and points them at the shape the change
moves toward. The reorientation composes on top of the base file rather than
editing it, so the file itself stays whole-tree, unmodified — there is no
standalone architecture agent deployed to read it that way; today the only
consumer is `review-audit`'s composed `architectureOfChange`.

`planner-audit` is **not** one of these tiers and not a lens inside `review-audit`.
It is a single read-only leaf running `lookahead_planning_specialist.txt`, and its
subject is an agent's *planner* — plan shape (stepwise-greedy / flat / lookahead /
replanning / hierarchical), branching factor, rollout depth, reward estimator and
its failure mode, replan triggers, compute budget. That only makes sense where the
thing being audited *is* an agent; in a general repo audit it would return a design
document about a planner that does not exist.

It defaults to this repo's own `workflows/`, which is exactly its subject matter —
and it has already earned its keep there: `ship-feature`'s work loop used to be a
fixed-depth `workLoop 8` with no replan trigger — a greedy policy in disguise, in
the rubric's terms — which is why it is now `loopUntil`, ended by the worker's
own summary.

The same rubric is *also* the `lookahead` lens in `plan-feature`'s edit stage —
applied to a plan there rather than to a planner. It runs **late** — after
`risk` and `verification`, with only the `simple-english` wording pass behind
it: it reorders for irreversibility and puts cheap reversible checks in front of
the expensive steps, and doing that before the steps' risks are annotated and
checked would be adjusting a sequence about to change anyway. What it asks of a plan: mark the irreversible steps and get a
cheap reversible check in front of them, name the evidence that would show an
approach is wrong and gather it *first*, and cut ordering that is locally
convenient but forecloses a better route later.

That lens carries a **format override, and it is load-bearing**. The prompt ships
its own OUTPUT FORMAT section demanding ten headed sections, while everything
downstream here is line-oriented: `plan.md` says one step per line, and every
lens in `editPlan` re-asserts it in its own instructions and emits the plan the
same way — there is no separate parser enforcing this, only each lens's own
prompt text agreeing to treat one line as one step. Left unoverridden, a
ten-section design document becomes ~150 "plan steps". So the lens instruction
opens by telling it to ignore its own
output format, and sits *after* the rubric where it is read last.

ponytail is **one reviewer among several**, never the whole review. It only hunts
complexity — its own rubric refuses correctness and security work — so shipping
it alone would be a review that structurally cannot find a bug. Correctness,
tests and architecture are this repo's own, in `prompts/review/`, each
deliberately narrow: the value of a fan-out is that reviewers do not overlap, so
a lens that wanders into another's territory costs a turn and returns a
duplicate. Security is upstream — `code_reviewer_security.txt`, an OWASP Top 10
walkthrough that reports severity, attacker payoff, a corrected snippet and the
preventing pattern per finding. It is verbose where the local lenses are terse,
which `synthesis.md` absorbs, and at ~8.3 KB it is the second most expensive
review lens after the doctrine (~10 KB) — not the second most expensive brief
in the repo overall; `steSkill` (~19.7 KB, the `prompt-lint` brief) and the
`lookahead` rubric (~8.4 KB) are both bigger. So it appears only in
`review-heavy`, never in the per-commit `review-lite`.

Haskell and performance are upstream too, from
[promptdeploy](#promptdeploy--the-upstream-this-repo-descends-from), read out of
the same files flake-prompt deploys as sub-agents. Adding them is what let
`agents/code-review.md` be narrowed: it used to carry a Haskell section and a
performance section of its own, so the fan-out was paying one generalist to
restate what a specialist says better. What is left of it — disabled tests,
hallucinated APIs, assertions that cannot fail, mock code on a production path —
is the one lens with no specialist, which is exactly why it is still there.

World-acting runs leave `.agent-functor-worktree-*` / `.agent-functor-worker-*`
directories behind if killed mid-run; they're gitignored, and safe to delete.

## Adding a prompt

Add an attrset to the `prompts` list in `flake.nix`:

```nix
{
  type = "command";            # command | agent | skill | instructions
  name = "my-skill";
  description = "Does the thing";
  body = builtins.readFile ./commands/my-skill.md;
}
```

Commit, then rebuild. Done.

## Adding a workflow

Write a `Workflow` in `Incite.Feature` (request → plan → PR) or `Incite.Review`
(the review and audit tiers), import it, and add it to the `workflows` list in
`workflows/Main.hs` — the one place that decides what exists; a workflow not in
that list is exposed as nothing, no matter how well defined. The CLI picks it
up automatically. Update `docs/workflows.md`'s "Exposed inventory" and "Review
tiers and leaf counts" tables too — they are the one place both live now, and
`test/Spec.hs`'s `docsInventoryTests` fences both against the code: a name or a
leaf count left stale there fails `cabal test`, not just a reader's trust.

```bash
nix develop   # GHC with agent-functor in scope, plus cabal and HLS
```

Put anything longer than a line in `prompts/` and reference it:

```haskell
myBrief :: Prompt
myBrief = [promptFile|prompts/my-brief.md|]        -- checked now, read at run time

refineWith "my-leaf" (brief myBrief) id            -- body, blank line, artifact
refineWith "my-leaf" (\x -> [i|#{myBrief}          -- or interpolate, #{} holes
                              Budget: #{n} steps
                              #{x}|]) id
```

A bad path is a **compile** error. `[promptFile|…|]` and `[i|…|]` both come from
`Agent.Prompt` (agent-functor re-exports `string-interpolate`, so there is no
extra dependency); the module needs `{-# LANGUAGE QuasiQuotes #-}`, already on in
`incite-workflows.cabal`.

A new subdirectory under `prompts/`, `agents/` or `skills/` needs **no** edit to
the `fileset` in `flake.nix` — it unions the cabal file plus `workflows/`,
`prompts/`, `agents/`, `skills/` wholesale, so any new subdirectory under one of
those is already covered. What it does **not** take wholesale is `commands/`: it
lists the three commands read back as briefs individually
(`commands/fess.md`, `commands/post-commit-audit.md`, `commands/wiggum.md`)
rather than the whole directory, so adding an ordinary slash command does not
rebuild the runner — but a new `commands/*.md` file that a workflow needs to
splice as a brief must be added to this `fileset` explicitly, or the nix build
sandbox will not see it and the compile-time check will fail. This union is
shared by name: `librarySrc`
in `flake.nix` is what the runner, `packages.haddock`, and the `unit-test`
check's `testSrc` all build on, so it is defined once rather than three times.
Keeping it a `fileset` rather than `./.` means editing this README or a `flake.nix`
prompt body does not rebuild the runner.

The same directory must also be listed in `extra-source-files` in
`incite-workflows.cabal`. That list is *not* what the nix build reads —
`mkWorkflowRunner` goes through `callCabal2nix`, which copies whatever `src` the
fileset produced — so a directory missing from the cabal file still builds under
nix and only breaks `cabal sdist`. Two lists, one of which fails quietly: keep
them in sync.

Use `workflow` for a workflow with a baked-in input, `workflowReq` for one that
demands an input, and `workflowGReq` when it acts on the world — the extra
argument is the `execGrant` whitelist, and everything not listed is denied.

## Acknowledgments

Hat tip to **John Bargman** and **John Wiegley** — the idea of treating
AI prompts as first-class declarative configuration, and the tooling
([wiggum](https://github.com/jwiegley/wiggum)) that proved it out, made
this whole approach legible. Standing on shoulders.
