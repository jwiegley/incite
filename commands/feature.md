# Feature Implementation Workflow


**Feature request**: $ARGUMENTS

## Before anything else

1. **Create the Claude Code TODO list** with all 8 workflow steps below (Research,
   Questions, Plan, Implement, Self-review 1, Fix CI, Self-review 2, PR). This
   lets the user track where you are in the process.

2. **Create a progress file** at `.feature-progress/<slug>.md`
   (where `<slug>` is a short kebab-case identifier for this feature) using the
   template in the "Progress file template" section below. This file is the
   **central communication hub** — you and all sub-agents read from and write to it.

   **Important**: Use a unique slug (e.g. `whitelabel-emails.md`),
   never a generic name — multiple sessions may run concurrently.

3. **After any context compaction**, re-read both your progress file AND
   `~/.claude/commands/feature.md` to reload workflow state and instructions.

## Your role: orchestrator

You are a **project manager**, not a developer. Your job:

- Maintain the progress file's Status section
- Handle user interaction (Steps 2 & 3)
- Break work into batches and dispatch sub-agents
- Read the progress file between batches to resolve coordination requests
- Create the final PR

**Delegate the bulk of file reading and code writing to sub-agents.** You may read
key files when needed for architectural decisions, plan design, or evaluating how
sub-agent work fits together — but avoid reading broadly. The goal is to keep your
context focused: sub-agents handle the volume, you handle the judgment calls.

## Sub-agent protocol

Every sub-agent you launch MUST receive these instructions in their prompt (copy the
relevant parts):

> ### Your coordination protocol
>
> 1. **Read the progress file FIRST** (`.feature-progress/<slug>.md`)
>    to understand current state, what other agents have done, and your assignment.
>    Pay special attention to the **Agent Log** — it contains context from previous
>    agents that you may depend on.
>
> 2. **Only modify files assigned to you** (listed in your task below). If you need
>    a change to a file you don't own, add a request under **Coordination Requests**
>    in the progress file. Do NOT make the change yourself.
>
> 3. **Update the progress file when done**:
>    - Append a new entry to the **Agent Log** with: what you did, key decisions you
>      made, and anything the next agent needs to know (e.g. "I exported `fooWidget`
>      from Handler.Foo — the template agent will need to import it")
>    - Mark your files as Done in the **File Ownership** table
>
> 4. **Never run** `git checkout`, `git restore`, or `git stash drop` — other agents
>    or sessions may have uncommitted changes in files you didn't touch.

### Sub-agent types

- **Explore** — Codebase research (read-only, returns summaries)
- **mecha-nick** — Haskell code (handlers, models, algorithms, tests)
- **Horatio** — Frontend (Hamlet templates, Julius scripts, CSS)
- **general-purpose** — Anything else (web research, review analysis)

## Progress file template

Initialize the progress file with this structure (replace placeholders):

    # Feature: <name>

    ## Request

    <paste the feature request>

    ## Status

    Current step: 1
    Active agents: none

    ## Research Findings

    <!-- Explore agents append their findings here, each under a ### heading -->

    ## Approved Plan

    <!-- Filled in after Step 3. Must include the File Ownership table. -->

    ## Agent Log

    <!-- Chronological entries from all agents. Each agent appends a new ### block:

    ### <Agent task name> (Batch N)
    - **What I did**: ...
    - **Key decisions**: ...
    - **For next agents**: ... (e.g., exports added, types defined, conventions chosen)
    -->

    ## Coordination Requests

    <!-- Agents post requests here when they need changes to files they don't own:
    - [ ] `<file path>`: <what needs to change> (requested by: <agent task>)
    The orchestrator resolves these between batches.
    -->

    ## Review Findings

    <!-- Self-review findings go here (Step 5 & 7) -->

## Important notes

- Keep going until the end of the workflow. Do not stop anywhere to ask for
  feedback or questions except for directly after Step 2. Any concerns or
  suggestions that come up after that should be communicated within the PR you
  create at the end.
- Always use mecha-nick for Haskell and Horatio for frontend.
- Between agent batches, **always** read the progress file to check for
  coordination requests and resolve them before dispatching the next batch.

## Step 1: Research

Spawn 2–3 **Explore** agents in parallel, each investigating a different aspect of
the feature. Good splits:

- Handler/route/template patterns for similar existing pages
- Data model and algorithm layer relevant to the feature
- UI/UX patterns, CSS conventions, or web research for design decisions

Each agent writes a summary under **Research Findings** in the progress file
(each under its own `###` heading).

After all agents complete, read ONLY the Research Findings section of the progress
file. Do not read source files yourself.

## Step 2: Ask questions

Based on the research summaries, ask all clarifying questions at once — about
requirements, edge cases, UX decisions, and implementation approach. Front-load
everything so there are no surprises later.

Wait for answers before proceeding.

## Step 3: Propose a plan

Based on the research summaries and user answers, propose a detailed implementation
plan. Include:

- Which files will be created/modified
- Data model changes (if any)
- Route additions (if any)
- Key implementation decisions and trade-offs
- **File ownership table**: assign each file to a batch and agent type
- **Batch ordering**: list which changes must complete before the next batch starts

The file ownership table determines which agent may modify which files. Design
batches so that:

- **Batch 1** (sequential, single agent): foundational changes — DB models, types,
  routes, shared utilities. Everything later batches depend on.
- **Batch 2+** (parallel): independent implementation units — handlers, templates,
  CSS, tests. Each unit assigned to the appropriate agent type.

Save the approved plan (including file ownership table) to the **Approved Plan**
section of the progress file.

Wait for feedback and approval before proceeding.

## Step 4: Implement

Execute the approved plan in dependency-ordered batches.

### Batch 1: Foundational changes

Dispatch a **single** mecha-nick sub-agent with:
- All foundational file assignments (DB models, types, routes, shared utilities)
- The sub-agent protocol
- The progress file path

Wait for completion. Read the progress file to check Agent Log and Coordination
Requests before proceeding.

### Batch 2+: Parallel implementation

Each agent's prompt must include:
- Their specific task and assigned files
- The sub-agent protocol (copied from above)
- The progress file path
- A note to read the Agent Log for Batch 1 context (types defined, exports, etc.)

Between batches:
1. Read the progress file
2. Resolve any **Coordination Requests** (dispatch a small fix agent or fold into
   next batch)
3. Update the Status section

### Testing

Include tests where appropriate — check existing test patterns to calibrate scope.
Tests can be assigned to a dedicated mecha-nick agent or bundled with the handler
agent's assignment.

## Step 5: Self-review (round 1)

Dispatch a **general-purpose** sub-agent to analyze the changes:
- Read `docs/code-review/init.md` and all files in `docs/code-review/*.md`
- Read the git diff of all changes (`git diff HEAD`)
- Write findings to the **Review Findings** section of the progress file

Then dispatch mecha-nick / Horatio sub-agents to implement the fixes. Each fix
agent reads Review Findings from the progress file plus the Agent Log for context.

**Important**: Do not present findings to the user. All findings must be implemented
directly.

## Step 6: Fix Build

/fix-build

## Step 7: Self-review (round 2) + final CI

Same as Step 5: dispatch a review agent, then fix agents for any findings.
If changes were made, re-run `/build`.

## Step 8: Commit and PR

1. Check the current branch name. If it aligns with the feature you just
   implemented (i.e. the branch was already created for this work), commit
   directly to it and push. **Never push directly to `master`.**

   If the current branch is `master` or doesn't match the feature:
   - Create a new branch with an appropriate name
   - The PR targets `origin/master` (or the current branch if it's not
     `master`)

2. Commit all changes with a clear commit message

3. Push and create a PR. In the PR description, include:
   - Summary of what was implemented
   - Things I should manually check (visual and code review)
   - Any remaining questions, suggestions, or advice

4. **Delete the progress file** — it's no longer needed
