{-# LANGUAGE QuasiQuotes #-}

-- | Every prompt body the workflows send, in one place.
--
-- This module is __data, not logic__: nothing here composes a 'Flow' or decides
-- anything. It exists so that "what do we say to the agent" is one file you can
-- read end to end, separately from "how are the agents wired together".
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
-- * @agents\/@, @skills\/@, @commands\/@ — the same files agent-pm ships to
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
  , fixAll
    -- * Review lenses
  , reviewCorrectness
  , reviewComplexity
  , reviewTests
  , reviewArchitecture
  , reviewSynthesis
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
    -- * Upstream: promptdeploy
  , haskellReviewer
  , perfReviewer
    -- * Upstream: SimpleEnglish (ASD-STE100)
  , steRules
  , steSkill
  ) where

import Agent.Prompt (Prompt, promptFile)

-- Explore -----------------------------------------------------------------------

intrepid, skeptic, contemplative :: Prompt
intrepid = [promptFile|prompts/explore/intrepid.md|]
skeptic = [promptFile|prompts/explore/skeptic.md|]
contemplative = [promptFile|prompts/explore/contemplative.md|]

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
-- code on a production path. ~9.7 KB — paid in full by every leaf that uses it.
codeReview :: Prompt
codeReview = [promptFile|agents/code-review.md|]

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

-- | Specialists from the @promptdeploy@ input (BSD 3-Clause, © 2025-2026 John
-- Wiegley), read from the same files agent-pm deploys as sub-agents. The
-- repo-specific Haskell addendum (@agents\/haskell-review.md@) is deliberately
-- not a lens: it would fire on a repo that is mostly Nix.
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
-- * 'steRules' — upstream's condensed system-prompt form, ~2 KB. Enough to
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
