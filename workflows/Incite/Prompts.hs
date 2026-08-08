{-# LANGUAGE QuasiQuotes #-}

-- | Every prompt body the workflows send, in one place.
--
-- This module is __data, not logic__: nothing here composes a "Agent.Flow".Flow
-- or decides anything. It exists so that "what do we say to the agent" is one
-- file you can read end to end, separately from "how are the agents wired
-- together".
--
-- Each binding is a top-level CAF, so each file is read once per process.
-- @[promptFile|…|]@ is checked when this module compiles and read when a leaf
-- runs, with paths relative to the __repo root__ — the cabal package root at
-- compile time, the working directory at run time. Those paths are unaffected by
-- which module the splice sits in, so moving a binding between modules is safe;
-- moving the markdown is not.
--
-- Three provenances, and the difference matters:
--
-- * @prompts\/@ — written for these workflows, live-editable.
-- * @agents\/@, @skills\/@, @commands\/@ — the same files flake-prompt ships to
--   @~\/.claude@, read a second time here rather than paraphrased, so there is
--   exactly one copy of each.
-- * @prompts\/upstream\/@ — from flake inputs, a @\/nix\/store@ path at both
--   compile and run time, so __not__ live-editable. @nix flake update <input>@
--   plus a rebuild is the whole update path.
module Incite.Prompts
  ( -- * Explore stances
    intrepid
  , skeptic
  , contemplative
  , architect
    -- * Planning
  , planBrief
  , planStep
  , planDenotational
  , planRisk
  , planVerification
    -- * Deployed prompts, read a second time as briefs
  , fess
  , postCommitAudit
  , wiggum
  , codeReview
  , haskellHouse
  , fixAll
    -- * Review lenses
  , reviewCorrectness
  , reviewComplexity
  , reviewTests
  , reviewArchitecture
  , reviewSynthesis
  , docsCompleteness
  , docsStructure
    -- * Grind lenses
  , paradoxFacts
  , grindStubs
  , grindVacuous
  , grindDry
  , grindHardcodings
  , grindTargetConsistency
  , grindValidatorCalls
  , grindCodegenGaps
  , grindEmittedCode
    -- * Review regroupings (views, not judges)
  , reviewUnits
  , reviewSequence
    -- * Retrospective columns
  , retroSentiment
  , retroWentWell
  , retroWentWrong
  , retroSynthesis
    -- * Upstream: ponytail
  , ponytailLadder
  , ponytailReviewRubric
  , ponytailAuditRubric
    -- * Upstream: awesome-prompts
  , agenticCoder
  , lookaheadPlanningSpecialist
  , codeReviewerSecurity
  , technicalDocsStrategist
  , stopSlop
  , qaAgent
    -- * Upstream: promptdeploy
  , haskellReviewer
  , perfReviewer
    -- * Upstream: SimpleEnglish (ASD-STE100)
  , steRules
  , steSkill
  ) where

import Agent.Prompt (Prompt, promptFile)

-- Explore -----------------------------------------------------------------------

intrepid, skeptic, contemplative, architect :: Prompt
intrepid = [promptFile|prompts/explore/intrepid.md|]
skeptic = [promptFile|prompts/explore/skeptic.md|]
contemplative = [promptFile|prompts/explore/contemplative.md|]
architect = [promptFile|prompts/explore/architect.md|]

-- Planning ----------------------------------------------------------------------

planBrief, planStep :: Prompt
planBrief = [promptFile|prompts/plan.md|]
planStep = [promptFile|prompts/plan-step.md|]

-- | Kmett\/Elliott plan-edit lens: what does each step mean, and does its
-- machinery already have a lawful name?
planDenotational :: Prompt
planDenotational = [promptFile|prompts/plan-denotational.md|]

-- | Risk plan-edit lens: annotate each step in place with
-- @RISK(low|med|high): mechanism. MITIGATION: clause.@ — written to be
-- consumed by 'planVerification' (checks) and the lookahead lens (ordering).
planRisk :: Prompt
planRisk = [promptFile|prompts/plan-risk.md|]

-- | Verification plan-edit lens: an observable check for every
-- behaviour-changing step, reusing the repo's existing harness.
planVerification :: Prompt
planVerification = [promptFile|prompts/plan-verification.md|]

-- Deployed prompts, read twice -----------------------------------------------------

-- | The @fess@ honesty rubric; agent-functor prepends the worker's captured
-- transcript, so it audits what the worker actually did.
fess :: Prompt
fess = [promptFile|commands/fess.md|]

-- | Post-commit brief: fire the mid-run checks over MCP. Deliberately duplicates
-- wiggum's standing instruction — the beat fires whether or not the worker
-- listened.
postCommitAudit :: Prompt
postCommitAudit = [promptFile|commands/post-commit-audit.md|]

-- | The @wiggum@ command: keep going to completion, audit every commit, hand
-- findings to a 'fixAll' subagent. The duration half of the implementation
-- brief; 'agenticCoder' and 'ponytailLadder' are the per-change half.
wiggum :: Prompt
wiggum = [promptFile|commands/wiggum.md|]

-- | The repo's @code-review@ agent, narrowed to AI-generated-code failure
-- modes: disabled tests, hallucinated APIs, assertions that cannot fail, mock
-- code on a production path. ~10 KB — paid in full by every leaf that uses it.
codeReview :: Prompt
codeReview = [promptFile|agents/code-review.md|]

-- | The repo's @haskell-review@ agent: what this codebase asks for beyond the
-- upstream Haskell rubric — no primitive in a top-level signature, newtypes and
-- smart constructors for domain values, @RecordWildCards@ binding fields by their
-- own names, a type parameter wherever it retires a runtime check, totality and
-- strict accumulation as absolutes — and the one rule it overrules, orphan
-- instances.
--
-- Read here as well as deployed, so the review panel enforces the same rules the
-- sub-agent does. It is an addendum by construction, which is why it reaches the
-- panel only through 'Incite.Review.haskellOfHouse' and never as a lens of its
-- own: alone it would report a codebase against half a rubric.
haskellHouse :: Prompt
haskellHouse = [promptFile|agents/haskell-review.md|]

-- | The @fix-all@ skill: \"fix every issue, no exceptions\". ~4 KB per leaf.
fixAll :: Prompt
fixAll = [promptFile|skills/fix-all.md|]

-- Review lenses -------------------------------------------------------------------

-- | The locally-authored review lenses, one narrow reviewer each; security,
-- performance and Haskell come from upstream. 'reviewComplexity' splits the
-- complexity beat with ponytail by remedy — ponytail reports what a deletion
-- fixes, it reports what a reshape fixes — so the two share a fan-out without
-- duplicating. 'reviewSynthesis' is the reducer brief, not a lens.
reviewCorrectness, reviewComplexity, reviewTests, reviewArchitecture, reviewSynthesis :: Prompt
reviewCorrectness = [promptFile|prompts/review/correctness.md|]
reviewComplexity = [promptFile|prompts/review/complexity.md|]
reviewTests = [promptFile|prompts/review/tests.md|]
reviewArchitecture = [promptFile|prompts/review/architecture.md|]
reviewSynthesis = [promptFile|prompts/review/synthesis.md|]

-- | The documentation review lenses, and the pair that only a prose artifact
-- admits. 'docsCompleteness' reads for what a reader cannot do — the unstated
-- prerequisite, the undescribed parameter, the failure with no recovery, the
-- term used before it is defined. 'docsStructure' reads the shape instead: the
-- order, the headings, the fact stated three times, and whether this is the
-- right kind of document at all.
--
-- Neither judges whether a claim is TRUE. That is the accuracy lens, which is
-- 'fess' pointed at prose ("Incite.Review".@docsAccuracy@) rather than a file
-- of its own — the honesty rubric already reads a claim against the record, and
-- a second copy of it here would be one of the three homes 'docsStructure' is
-- written to report.
docsCompleteness, docsStructure :: Prompt
docsCompleteness = [promptFile|prompts/review/docs-completeness.md|]
docsStructure = [promptFile|prompts/review/docs-structure.md|]

-- Grind lenses ---------------------------------------------------------------------

-- | Everything a leaf of the grind panel needs to know about the tree it is
-- reading: how to build it, how to run one filtered test, where the recorded
-- golden output lives, what the source language means, and the disciplines a
-- repair stands under.
--
-- __One file, read by both halves of the run.__ The audit leaves receive it
-- beneath their lens and the fixer receives it beneath 'Incite.Feature.codeRule',
-- because a fixer told to regenerate a golden without being told never to
-- hand-edit one is a fixer with a cheap way to turn the gate green.
--
-- __Paths are relative to the working directory__, and the file opens with a
-- probe that proves two of them before anything else runs. A leaf started
-- somewhere other than the checkout root would otherwise resolve every path to
-- nothing and report no findings, which reads exactly like a clean tree.
paradoxFacts :: Prompt
paradoxFacts = [promptFile|prompts/grind/paradox-facts.md|]

-- | The four whole-tree grind lenses: unfinished work, tests that cannot fail,
-- one decision written three times, and values baked in where they must be
-- derived.
--
-- Repo-agnostic by construction — every path, suite name and build command
-- lives in 'paradoxFacts' instead, which each leaf receives beneath its lens.
-- A lens that named this tree's directories would report confident findings
-- about paths that exist on no other one.
grindStubs, grindVacuous, grindDry, grindHardcodings :: Prompt
grindStubs = [promptFile|prompts/grind/stubs.md|]
grindVacuous = [promptFile|prompts/grind/vacuous.md|]
grindDry = [promptFile|prompts/grind/dry.md|]
grindHardcodings = [promptFile|prompts/grind/hardcodings.md|]

-- | The four grind lenses that only a __code generator__ admits: targets that
-- disagree about one source construct, validators emitted and never called,
-- constructs a backend silently drops, and the quality of the emitted code
-- itself.
--
-- 'grindEmittedCode' is one lens where upstream had two. Run time and compile
-- time of generated code were split by accident: both read the recorded golden
-- output, both repair the emitter, and both regenerate the same cases. Split,
-- they draw two backends to do one read.
--
-- These sit in 'Incite.Review.emissionLenses' rather than under a 'Subject' of
-- their own, because a subject owes a ponytail lens and nobody asked what
-- should not exist in generated code.
grindTargetConsistency, grindValidatorCalls, grindCodegenGaps, grindEmittedCode :: Prompt
grindTargetConsistency = [promptFile|prompts/grind/target-consistency.md|]
grindValidatorCalls = [promptFile|prompts/grind/validator-calls.md|]
grindCodegenGaps = [promptFile|prompts/grind/codegen-gaps.md|]
grindEmittedCode = [promptFile|prompts/grind/emitted-code.md|]

-- | The review-audit regroupings: re-express the change into logical units, or
-- into the commits it should have been. Views, not judges — except
-- 'reviewSequence'\'s own @## divergence@ report.
reviewUnits, reviewSequence :: Prompt
reviewUnits = [promptFile|prompts/review/units.md|]
reviewSequence = [promptFile|prompts/review/sequence.md|]

-- Retrospective columns -----------------------------------------------------------

-- | The retrospective columns, read over a __session__ rather than a diff, plus
-- the meeting brief that turns them into changes.
--
-- Two rules in the briefs keep them out of the review lenses' work. The subject
-- is the __process__ — a code defect is a review finding, and reaches here only
-- where the process let it through. The output is a __change__, not a grade:
-- 'retroWentWell' drops any entry that cannot name what should trigger it again.
-- 'retroSentiment' reports quoted text, never an inferred inner state.
retroSentiment, retroWentWell, retroWentWrong, retroSynthesis :: Prompt
retroSentiment = [promptFile|prompts/retro/sentiment.md|]
retroWentWell = [promptFile|prompts/retro/went-well.md|]
retroWentWrong = [promptFile|prompts/retro/went-wrong.md|]
retroSynthesis = [promptFile|prompts/retro/synthesis.md|]

-- Upstream ------------------------------------------------------------------------

-- | The counterweight to 'fixAll' in the work beat: every issue fixed, in the
-- shortest change that fixes it.
ponytailLadder :: Prompt
ponytailLadder = [promptFile|prompts/upstream/ponytail/ladder.md|]

-- | The ponytail report rubrics: same tags and scoring, pointed at a diff
-- ('ponytailReviewRubric') or a whole tree ('ponytailAuditRubric').
ponytailReviewRubric, ponytailAuditRubric :: Prompt
ponytailReviewRubric = [promptFile|prompts/upstream/ponytail/review.md|]
ponytailAuditRubric = [promptFile|prompts/upstream/ponytail/audit.md|]

-- | From @awesome-prompts@: plan first, read before editing, tests are not
-- optional, minimal footprint, then a security checklist and a PR-summary
-- format. Opens the implementation brief — the first leaf that writes to a
-- file, so the rules land there.
agenticCoder :: Prompt
agenticCoder = [promptFile|prompts/upstream/awesome-prompts/agentic-coder.md|]

-- | The lookahead rubric — about __planners__, not plans: left alone it emits a
-- ten-section design document. Hence the load-bearing format override in the
-- lookahead plan lens, and the planner audit as its native use.
lookaheadPlanningSpecialist :: Prompt
lookaheadPlanningSpecialist = [promptFile|prompts/upstream/awesome-prompts/lookahead-planning-specialist.md|]

-- | The security lens, from upstream: an OWASP category walk, a block per
-- finding where the local lenses emit a line ('reviewSynthesis' normalises
-- that). ~8.5 KB, which is why it never runs in the cheap tier.
codeReviewerSecurity :: Prompt
codeReviewerSecurity = [promptFile|prompts/upstream/awesome-prompts/code-reviewer-security.md|]

-- | The documentation strategy rubric: audiences, information architecture,
-- content types (reference, tutorial, how-to, concept), docs-as-code, quality
-- gates, and what a documentation task's definition of done is.
--
-- Left alone it does what its own Task section asks for — designs a ten-section
-- strategy for a hypothetical SaaS product, which is a deliverable no repository
-- wants. It reaches a workflow only through
-- 'Incite.Review.docsStrategyOfPlan', for the same reason
-- 'lookaheadPlanningSpecialist' needs its format override.
technicalDocsStrategist :: Prompt
technicalDocsStrategist = [promptFile|prompts/upstream/awesome-prompts/technical-documentation-strategist.md|]

-- | The anti-slop prose editor: filler openers, adverbs, the @not X but Y@
-- contrast, passive voice, inanimate subjects doing human verbs, metronomic
-- sentence rhythm, pull-quote endings.
--
-- An __editor__ upstream — it returns rewritten prose — and the docs panel is
-- read-only by construction, so it reaches the panel only through
-- 'Incite.Review.slopOfDocs', which turns the rewrite into findings.
stopSlop :: Prompt
stopSlop = [promptFile|prompts/upstream/awesome-prompts/stop-slop.md|]

-- | The adversarial QA reviewer: assume the code fails and find how. Edge cases,
-- error paths, an OWASP walk, scaling, integration contracts, observability,
-- each finding carrying a severity.
--
-- 2.6 KB, which is what makes it affordable in the cheap tier where
-- 'codeReviewerSecurity' at 8.5 KB is not. It reaches 'Incite.Review.reviewLite'
-- through 'Incite.Review.qaOfCommit', which points it at a commit and fences it
-- off the four lenses beside it — that tier reduces by a pure fold, so nothing
-- downstream de-duplicates two reviewers reporting one defect.
qaAgent :: Prompt
qaAgent = [promptFile|prompts/upstream/awesome-prompts/qa-agent.md|]

-- | Specialists from the @promptdeploy@ input (BSD 3-Clause, © 2025-2026 John
-- Wiegley), read from the same files flake-prompt deploys as sub-agents.
--
-- 'haskellReviewer' is the __base__ of the panel's Haskell lens, not the lens:
-- 'Incite.Review.haskellOfHouse' splices 'haskellHouse' under it, so a review
-- carries this codebase's own rules rather than the upstream rubric alone.
haskellReviewer, perfReviewer :: Prompt
haskellReviewer = [promptFile|prompts/upstream/promptdeploy/haskell-reviewer.md|]
perfReviewer = [promptFile|prompts/upstream/promptdeploy/perf-reviewer.md|]

-- | ASD-STE100 Simplified Technical English (MIT, © AminBlg), at two grades.
--
-- The distinction that makes STE useful here is its own: __procedural__ text
-- tells the reader what to do (imperative, ≤20 words, one instruction per
-- sentence, condition before command), __descriptive__ text explains (≤25
-- words, simple tenses). Every prompt this repo ships is both, and only the
-- procedural half has to survive one read by a tired model.
--
-- * 'steRules' — upstream's condensed system-prompt form, 2,947 B. Enough to
--   rewrite a plan step, cheap enough to run on every plan.
-- * 'steSkill' — the full skill, ~19.7 KB, and the only one of the two that
--   carries the CHECK contract: report each violation as rule number, offending
--   text, compliant rewrite — and do not cite a rule number from memory,
--   because the numbering is unintuitive and models invent it. That grounding
--   is what a linter is buying, and why the size is worth it there and nowhere
--   else.
steRules, steSkill :: Prompt
steRules = [promptFile|prompts/upstream/simple-english/rules.md|]
steSkill = [promptFile|prompts/upstream/simple-english/skill.md|]
