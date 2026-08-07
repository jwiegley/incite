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
                     and orphan instances are fine here, overruling upstream
                     ALSO read as a workflow brief — see below
  compiler.md      — Haskell/type-theory specialist (Opus)
  fess-auditor.md  — evidence-backed honesty check on a finished session
commands/          — slash command bodies (frontmatter lives in flake.nix)
  fess.md          — the honesty rubric
                     ALSO read as a workflow brief — see below
  post-commit-audit.md — the ONE description of the post-commit check; /wiggum
                     defers to it and ship-feature's work loop fires it
                     ALSO read as a workflow brief — see below
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
prompts/           — prompt bodies for the workflows, read at RUN time
  plan.md          — turn exploration findings into a one-step-per-line plan
  plan-step.md     — review one plan step for correctness/completeness/ordering
  explore/*.md     — the three explore stances: intrepid, skeptic, contemplative
  review/*.md      — the LOCAL review lenses fanned out by `review-lite`/
                     `-heavy`/`-audit`: correctness, complexity, tests,
                     architecture. Security, performance and Haskell lenses are
                     upstream — see "Upstream prompts" below. Three files here
                     are NOT lenses: synthesis.md (the reducer brief) and
                     units.md / sequence.md, which re-express a change for
                     `review-audit`'s granularity axis without judging it
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

`agents/` and `skills/` do double duty: agent-pm renders them to `~/.claude`,
*and* the workflows read those same files as briefs at run time —
`agents/code-review.md` is the reviewer leaf, `skills/fix-all.md` is the work
beat of `ship-feature`'s loop. One copy, no paraphrase, so editing either
file changes both the deployed prompt and the workflow.

The bill for that is real: `code-review.md` is ~18 KB and every leaf using it
sends the whole thing, so a workflow reading it costs materially more per turn
than one with a one-line brief. `workflows/Main.hs` says so at the binding.
Note that `cost` will *not* show you this — it reports worst-case leaf
executions, the dominating bound and the node count, never tokens, so a leaf
carrying 18 KB and a leaf carrying one line both count as 1.

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
| `agent-pm` | `gitlab:fresheyeball/flake-prompt` | the renderer |
| `macha` | private ssh, `flake = false` | supplies two prompt bodies |
| `ponytail` | `github:dietrichgebert/ponytail`, `flake = false` | four skills + three workflow briefs |
| `awesome-prompts` | `github:ai-boost/awesome-prompts`, `flake = false` | exactly three files: `agentic_coder.txt`, `lookahead_planning_specialist.txt`, `code_reviewer_security.txt` |
| `promptdeploy` | `github:jwiegley/promptdeploy`, `flake = false` | the upstream this repo's prompts descend from — pinned to reconcile against, plus four sub-agents |
| `simple-english` | `github:AminBlg/SimpleEnglish`, `flake = false` | ASD-STE100 as a skill, a plan lens, and the `prompt-lint` rubric |
| `agent-functor` | `git+file:///home/isaac/_/agent-functor/master` | local worktree input, `refs/heads/master` |

`agent-functor` is pinned to its own nixpkgs (its Haskell deps want 24.11), so
it deliberately does *not* `follows` incite's unstable.

It is also a **local filesystem input**, which is two separate landmines:

- The URL is the `master` *worktree*, not `/home/isaac/_/agent-functor` — that
  parent path is a container of worktrees rather than a repository, so nix
  cannot fetch or update it at all.
- This flake will not evaluate on any machine without that exact worktree
  checked out. There is no fallback and no remote.

Why that branch, and the rule for re-locking it, are in the comment above the
input in `flake.nix`.

### Upstream prompts

Three inputs supply prompt text this repo does not author. None is taken as a
flake — all three come in with `flake = false` and their files are read directly.

**Nothing is copied into git.** The update path is exactly:

```bash
nix flake update ponytail     # or awesome-prompts
# then rebuild — that's it
```

[ponytail](https://github.com/DietrichGebert/ponytail) lands in two places:

- **Skills.** `ponytail`, `ponytail-review`, `ponytail-audit` and
  `ponytail-debt` are rendered from `${ponytail}/skills/*/SKILL.md` with their
  own YAML frontmatter stripped (agent-pm writes frontmatter itself). They are
  deployed as *skills* rather than as an always-on `instructions` fragment:
  ponytail's descriptions are written to trigger the model on coding work,
  which is the right activation surface. `ponytail-gain` (a benchmark
  scoreboard) and `ponytail-help` (a card for `/commands` this repo does not
  install) are deliberately left out.
- **Workflow briefs.** `prompts/upstream/ponytail/{ladder,review,audit}.md`.

One name per capability, all the way down — so `ponytail-audit` means the same
thing whether you hit it as a skill in a chat, a file on disk, or an MCP tool:

| upstream | skill | prompt file | workflow / MCP tool | `Main.hs` |
|---|---|---|---|---|
| `skills/ponytail-review` | `ponytail-review` | `ponytail/review.md` | `ponytail-review` | `ponytailReviewRubric` → `ponytailReview` |
| `skills/ponytail-audit` | `ponytail-audit` | `ponytail/audit.md` | `ponytail-audit` | `ponytailAuditRubric` → `ponytailAudit` |
| `skills/ponytail-debt` | `ponytail-debt` | — | — | — |
| `AGENTS.md` | `ponytail` | `ponytail/ladder.md` | — (a brief, not a flow) | `ponytailLadder` |

[awesome-prompts](https://github.com/ai-boost/awesome-prompts) supplies exactly
three named files, verbatim:

| upstream | as | drives |
|---|---|---|
| `prompts/agentic_coder.txt` | `awesome-prompts/agentic-coder.md` | the `ship-feature` worker brief |
| `prompts/lookahead_planning_specialist.txt` | `awesome-prompts/lookahead-planning-specialist.md` | the `planner-audit` workflow **and** the `lookahead` lens |
| `prompts/code_reviewer_security.txt` | `awesome-prompts/code-reviewer-security.md` | the `security` lens of `review-heavy` |

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
| `commands/partner-{reviewer,cleanup}.md` | same names | **ours** |
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
  kept the filename and the `codeReview` binding. 18 KB → 9.7 KB, and the
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
SSH — is not adopted: `agent-pm` is a pure-Nix renderer producing a package plus the
`lib.prompts` inventory nixos-dots consumes, and swapping loses that for
capabilities this repo does not need.

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
| the `simple-english` **plan lens** | `prompts/system-prompt.md` (~2 KB) | enough to *rewrite* a step; cheap enough to run on every plan |
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

The one cost: unlike every other prompt here, the upstream two are **not**
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
`.codex/skills/` ends up holding the real skills *plus* `voice`, `compiler`
and `fess-auditor` (and not `code-review`, per the `skip` above). That
asymmetry is the degradation policy working, not a rendering bug.

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

`run` flags: `--backend NAME` (default `claude-agent`), `-i/--input TEXT`
(prompts on a tty if omitted), `--sandbox` (isolate a world-acting run in a
throwaway worktree instead of editing in place — the result is committed to an
`agent-functor/run-…` branch; prompt-only flows have nothing to isolate and
always run in place), `--concurrency N` (caps concurrent fan-out sessions;
defaults to 6, or the workflow's own `withConcurrency`; `0` = unbounded).

`run` picks its front-end off the terminal. On a tty it drives the **live
TUI**: a context header, a stage list that fills in as leaves complete, a
scrolling agent transcript with styled inline tool calls, and modals for the
points where a flow blocks on you — `steer`, `humanGate`, and any permission
prompt answer straight out of the TUI. Piped or in CI it falls back to an
inline transcript and those same blocking points drop to plain stdin asks, so
an unattended `ship-feature` still stops at its gate. `plan` and `cost`
never touch an agent, so they work anywhere.

Currently defined in `workflows/Main.hs`:

| workflow | what it does |
|---|---|
| `plan-feature` | explore (3 stances) → plan → 6 lens edits (`ponytail`, `denotational`, `risk`, `verification`, `lookahead`, `simple-english`). Prompt-only: touches nothing |
| `ship-feature` | the above, then implement in place, an 8-beat build/commit/review loop, a human gate, and a PR. The implementer is briefed with `agentic-coder` + ponytail's ladder + `commands/wiggum.md`; review beats send `agents/code-review.md`, work beats send `skills/fix-all.md` + the ladder. World-acting; `execGrant` permits only `git`/`cabal`/`gh` |
| `fess-audit` | honesty-audit a worker's in-progress session; read-only, on codex. Fired over MCP by the worker after each commit |
| `ponytail-review` | review a diff for over-engineering only — what to delete, what the stdlib or platform already does — ending in a net line count. Read-only, on codex, also callable over MCP |
| `ponytail-audit` | the same cuts over a whole tree instead of a diff, ranked biggest first. Input defaults to "the repository in the current working directory", so it needs no argument. Read-only, on codex, also callable over MCP |
| `review-lite` | a diff through 2 concurrent reviewers — correctness + ponytail complexity — reduced by a *pure* fold, correctness first. No synthesis leaf: two turns total, cheap enough for a per-commit beat, which is what `wiggum` uses it for |
| `review-heavy` | a diff through 7 concurrent reviewers — correctness, security, tests, performance, Haskell, ponytail complexity, and AI-generated-code failure modes — then an agent synthesises one ranked, de-duplicated list. Pre-PR, not per-commit |
| `review-audit` | the exhaustive tier: `review-heavy`'s panel **plus architecture** — 8 lenses × 3 backends — run over the change **three times at three granularities** (full diff, logical units, ideal sequential edits), then one synthesis. **75 leaves.** Deliberate, never on a beat |
| `planner-audit` | audits an agent's **planner design**, not its code: plan shape, lookahead depth, reward estimation, replan triggers, compute budget. Input defaults to this repo's own `workflows/`. Read-only, on codex |
| `prompt-lint` | checks the **prompts** against ASD-STE100 — rule, offending text, rewrite — over *procedural* instructions only. On target because the prompts are the product here, and every review tier reads code instead. Read-only |
| `haskell-review` | review a function with the full `code-review` agent prompt, then rewrite it fixing the issues |
| `explain` | explain code in plain English |
| `test-writer` | draft hspec tests → critique → finalize |

Where the [upstream briefs](#upstream-prompts) land:

- ponytail's **ladder** — the `ponytail` lens runs **first** in the shared edit
  stage, so the later lenses only annotate steps that survive it, and it rides
  along with `fix-all` on every work beat.
- ponytail's **review** and **audit** rubrics — one workflow each, same shape,
  differing only in what they are pointed at.
- **agentic-coder** — opens the brief for the implementer in `ship-feature`, the
  first leaf in either workflow that writes to a file. That is where
  read-before-editing and the security checklist have to land, not at the review
  beats after it.

The implementation brief is a three-document composition, each answering a
different question — `agentic-coder` **how** to write it (plan first, read before
editing, tests are not optional), ponytail's ladder **how much** (stop at the
first rung that holds), and `commands/wiggum.md` **how long** (to completion,
with a handoff document, auditing its own commits). ~7 KB per turn: deliberate,
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

`fess-audit` is the only workflow here marked **`withCapturedTranscript`**, and
that mark is what makes it work. A run advertises its own MCP endpoint to the
sessions it opens; a workflow with that mark, called through it, gets the worker's
captured conversation as input instead of whatever the caller passed, and its
input requirement is bypassed. Its subject genuinely *is* the session.

Nothing else declares it, deliberately. The endpoint serves the whole `workflows`
list, so `review-lite` — fired on the same beat — keeps the caller's input and
receives the diff it was handed. That opt-in did not exist until recently:
agent-functor substituted the transcript for *every* workflow started through a
trigger endpoint, which would have handed `review-lite`'s diff-shaped reviewers a
conversation log. Fixed upstream in `Agent.Run` (`withCapturedTranscript` /
`TriggerInput`, rev `800ea38`) and pinned here.

On a plain `agent-functor mcp` server there is no capture, so `fess-audit` is not
available at all — outside a run, `review-lite`'s `fess` lens is the whole of it.

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
which checks to run, what to pass them, and how to poll. `/wiggum` defers to it
rather than restating it, and `ship-feature`'s work loop fires the same file as
its commit beat — the third "read twice" prompt alongside `fess` and `wiggum`,
deployed as `/post-commit-audit` and read as a brief from one copy.

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

| tier | lenses | × backends | × granularities | leaves | reduce |
|---|--:|--:|--:|--:|---|
| `review-lite` | 4 | 1 (spread) | 1 | 4 | pure `hierarchical`, correctness first |
| `review-heavy` | 7 | 3 (all) | 1 | 22 | agent `synthesis` leaf |
| `review-audit` | 8 | 3 (all) | 3 | 75 | agent `synthesis` leaf |

The tiers escalate along three independent axes, and each buys something different.
**Lenses** buy coverage — `review-lite` spreads four across backends for cheap
independence; `review-heavy` adds security, tests, performance and Haskell;
`review-audit` adds architecture. **Backends** buy confidence: from `review-heavy`
up, every lens is answered by all three models, so agreement is confirmation and
disagreement is signal rather than one model's opinion. **Granularity**, only in
`review-audit`, buys a kind of finding the others structurally cannot reach.

#### The granularity axis

`review-audit` runs its whole 24-reviewer panel three times, over three
re-expressions of the same change:

| view | what the panel reads | what only this view finds |
|---|---|---|
| `full` | the change as it landed | what is wrong with the result |
| `units` | the change regrouped into logical units (`prompts/review/units.md`) | a unit whose hunks span modules that should not change together — invisible in a full diff |
| `sequence` | the change as the commits it *should* have been (`prompts/review/sequence.md`) | its `## divergence` section: hunks that **cannot** be separated name a coupling in the code, and work that cancels itself out shows as a step undoing an earlier one |

Both regroupings are agent leaves, not pure splits — "logical unit" and "ideal
sequence" are semantic judgements, so nothing `T.lines`-shaped can produce them
(unlike `reviewScales` over a plan, where a line really is a step). Both are told
to reproduce every hunk exactly once, verbatim, because the panel reads their
output *as* the change: anything elided is invisible to 24 reviewers.

**Architecture is reframed for the change.** `prompts/review/architecture.md` is
written whole-tree and says so. Inside `review-audit` it is composed with a
reorientation that keeps its questions — leaking boundaries, arrows pointing the
wrong way, one decision in many homes — and points them at the shape the change
moves toward. It stays whole-tree when run as a standalone agent.

`planner-audit` is **not** one of these tiers and not a lens inside `review-audit`.
It is a single read-only leaf running `lookahead_planning_specialist.txt`, and its
subject is an agent's *planner* — plan shape (stepwise-greedy / flat / lookahead /
replanning / hierarchical), branching factor, rollout depth, reward estimator and
its failure mode, replan triggers, compute budget. That only makes sense where the
thing being audited *is* an agent; in a general repo audit it would return a design
document about a planner that does not exist.

It defaults to this repo's own `workflows/`, which is exactly its subject matter —
and it has something to say there: `ship-feature`'s `workLoop 8` is a
fixed-depth unrolled loop with no replan trigger, which the rubric calls "a greedy
policy in disguise."

The same rubric is *also* the `lookahead` lens in `plan-feature`'s edit stage —
applied to a plan there rather than to a planner. It runs **last**, after
`sequencing`: it reorders for irreversibility and inserts checkpoints, and doing
that before the dependency order is right would be adjusting a sequence about to
change anyway. What it asks of a plan: mark the irreversible steps and get a
cheap reversible check in front of them, name the evidence that would show an
approach is wrong and gather it *first*, and cut ordering that is locally
convenient but forecloses a better route later.

That lens carries a **format override, and it is load-bearing**. The prompt ships
its own OUTPUT FORMAT section demanding ten headed sections, while everything
downstream here is line-oriented: `plan.md` says one step per line, every sibling
lens re-asserts it, and the review stage is `reviewScales T.lines`, which treats
each line as a step. Left unoverridden, a ten-section design document becomes
~150 "plan steps". So the lens instruction opens by telling it to ignore its own
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
which `synthesis.md` absorbs, and at ~8.5 KB it is the second most expensive
brief here after the doctrine — so it appears only in `review-heavy`, never in
the per-commit `review-lite`.

Haskell and performance are upstream too, from
[promptdeploy](#promptdeploy--the-upstream-this-repo-descends-from), read out of
the same files agent-pm deploys as sub-agents. Adding them is what let
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

Write another `Workflow` in `workflows/Main.hs` and list it in `workflows`. The
CLI picks it up automatically.

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

A new prompt directory must be added to the `fileset` in `flake.nix`, or the nix
build sandbox will not see it and the compile-time check will fail. It currently
unions the cabal file plus `workflows/`, `prompts/`, `agents/` and `skills/` —
the last two are there precisely because workflows splice prompts out of them.
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
