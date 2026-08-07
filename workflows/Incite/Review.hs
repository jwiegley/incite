{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | The review and audit tiers: fan independent reviewers over one artifact
-- concurrently, then reduce.
--
-- One shape at three prices, escalating along three axes: __lenses__ buy
-- coverage, __backends__ buy confidence (three models agreeing, not one model's
-- opinion), and __granularity__ buys findings the other two cannot reach.
--
-- Every reviewer is read-only — 'Incite.Backend.reviewer' scopes it 'Plan' — so
-- no tier can edit what it is reading.
module Incite.Review
  ( reviewLite
  , reviewHeavy
  , reviewHeavyFlow
  , reviewAudit
  , fessAudit
  , retro
  , retroFlow
  , plannerAudit
  , promptLint
  , promptLintBrief
  , promptLintScope
  , Subject (..)
  , lensesOf
  ) where

import Data.Text (Text)
import Agent.Backend (claudeAgent, codex, defaultModel, opencode, withBackend)
import Agent.Flow (Flow, Mode (Plan), withMode, (>>>))
import Agent.Flow.Combinators (exploreFlows, hierarchical, refineWith, unionFindings)
import Agent.Op (LeafName)
import Agent.Prompt (Prompt, brief, iii, __i)
import Agent.Run (Workflow, withCapturedTranscript, workflow, workflowReq)

import Incite.Backend (backends, claudeAgentBackend, fable5, reviewer)
import Incite.Prompts

-- | The cheap tier, fired by @wiggum@ after every commit: four reviewers, one
-- wave, reduced by a pure fold with no synthesis leaf.
--
-- Deliberately __not__ 'withCapturedTranscript' even though fess is a lens: all
-- four leaves read the same input, so the mark would hand the code lenses a
-- conversation log. Here fess audits claims against the diff; 'fessAudit' is
-- the whole-session version.
reviewLite :: Workflow
reviewLite =
  workflowReq
    "review-lite"
    [iii|
      Review a commit with four independent reviewers (correctness, fess
      claims-versus-diff audit, reshape complexity, ponytail cuts) — one call,
      cheap enough to run on every commit
    |]
    $ exploreFlows
      [ reviewer (withBackend claudeAgent defaultModel) "correctness" reviewCorrectness
      , reviewer (withBackend codex defaultModel) "fess" fess
      , reviewer (withBackend opencode defaultModel) "complexity" reviewComplexity
      , reviewer (withBackend codex defaultModel) "ponytail" ponytailReviewRubric
      ]
      (hierarchical ["correctness", "fess", "complexity", "ponytail"])

-- | The thorough tier: seven lenses answered by all three backends, then a
-- synthesis leaf that de-duplicates and ranks. Where 'reviewLite' spreads its
-- lenses across backends for cheap independence, this buys the real thing. Use
-- before a PR, not on a beat.
reviewHeavy :: Workflow
reviewHeavy =
  workflowReq
    "review-heavy"
    [iii|
      Review a diff with seven review lenses (correctness, security, tests,
      performance, Haskell, ponytail complexity, AI-generated-code failure
      modes), each run on all three backends — 21 reviewers — then synthesise
      one ranked list
    |]
    reviewHeavyFlow

-- | 'reviewHeavy' as a plain 'Flow', so 'Incite.Feature' runs the same panel
-- inline after implementation instead of copying it.
--
-- Both regroupings run on claude-agent alone. Fanning them across all three
-- backends as well is what makes 'reviewAudit' a 75-leaf tier, and this one has
-- to stay firable after a commit.
reviewHeavyFlow :: Flow Text Text
reviewHeavyFlow =
    exploreFlows
      [ ("full", panel auditLenses)
      , ("units", regroup "units" reviewUnits)
      , ("sequence", regroup "sequence" reviewSequence)
      ]
      unionFindings
      >>> refineWith "synthesis" (brief reviewSynthesis) id
  where
    auditLenses = lensesOf OfDiff
    regroup name how =
      refineWith ("regroup:" <> name) (brief how) id >>> panelAcross [claudeAgentBackend] auditLenses

-- | The exhaustive tier: 'reviewHeavy'\'s panel plus a change-reframed
-- architecture lens, at three granularities — the diff as landed, regrouped
-- into logical units, and re-expressed as the commits it should have been
-- (whose @## divergence@ is the finding only that view produces). The full
-- panel answers each. 75 leaves: run it deliberately, never on a beat.
--
-- The regroupings are agent leaves, not a pure split: \"logical unit\" and
-- \"ideal sequence\" are semantic, unlike @T.lines@ on a plan.
reviewAudit :: Workflow
reviewAudit =
  workflow
    "review-audit"
    [iii|
      Exhaustively audit a change: eight review lenses (correctness, security,
      tests, performance, Haskell, ponytail, AI-failure modes, architecture) on
      all three backends, at three granularities (full diff, logical units,
      ideal sequential edits) — 75 reviewers — then synthesise one ranked list
    |]
    [iii|
      The working change in the current working directory. Run `git diff` (or
      `git show` for the last commit) and read it before reporting anything.
    |]
    $ exploreFlows
      [ ("full", panel auditLenses)
      , ("units", regroup "units" reviewUnits)
      , ("sequence", regroup "sequence" reviewSequence)
      ]
      unionFindings
      >>> refineWith "synthesis" (brief reviewSynthesis) id
  where
    auditLenses = lensesOf OfChange
    regroup name how = refineWith ("regroup:" <> name) (brief how) id >>> panel auditLenses

-- | The __kind of artifact__ a panel is pointed at. Not a switch over which
-- lenses differ — a name for what is under review, from which the lens set
-- follows. A subject that shares no lens with the others is still a 'Subject';
-- the type says what is being read, and 'lensesOf' says what reading it admits.
data Subject
  = -- | 'reviewHeavy': the diff, and nothing wider.
    OfDiff
  | -- | 'reviewAudit': the change, and the shape it moves the code toward.
    OfChange
  deriving (Eq, Show, Bounded, Enum)

-- | The lenses that artifact admits, in the order their blocks are read.
--
-- Three laws hold at every constructor, and 'lensSetViolations' is where they
-- are written down as code:
--
-- * the list is __non-empty__ — a subject with no lens is a panel with nothing
--   to fan out;
-- * the leaf names are __pairwise distinct__ — 'panelAcross' keys blocks by
--   @lens\@backend@, so a repeat makes two reviewers indistinguishable in the
--   reduction;
-- * @\"ponytail\"@ is __present__ — every artifact admits the question of what
--   should not exist, and each subject picks the rubric pointed at it.
--
-- Total in 'Subject', so a new constructor cannot be added without answering
-- what its artifact admits.
lensesOf :: Subject -> [(LeafName, Prompt)]
lensesOf subject =
  [ ("correctness", reviewCorrectness)
  , ("security", codeReviewerSecurity)
  , ("tests", reviewTests)
  , ("performance", perfReviewer)
  , ("haskell", haskellReviewer)
  , ("ponytail", ponytailRubric)
  , ("doctrine", codeReview)
  ]
    <> extra
  where
    (ponytailRubric, extra) = case subject of
      OfDiff -> (ponytailReviewRubric, [])
      OfChange -> (ponytailAuditRubric, [("architecture", architectureOfChange)])

-- | 'reviewArchitecture' is whole-tree by its own contract. This reorientation
-- keeps its questions and points them at the shape a change moves toward; the
-- file is untouched, so the standalone agent stays whole-tree.
architectureOfChange :: Prompt
architectureOfChange =
  [__i|
    #{reviewArchitecture}

    ---

    ONE ADJUSTMENT to the above: you are reading a **change**, not a whole
    tree. Everything else stands — the measure is still what a likely change
    costs, and line-level defects still belong to the other reviewers.

    Judge the shape this change moves the code toward. Which of the problems
    above does it introduce, deepen, or relieve? A hunk that adds the third
    home for one decision, an import that points a new arrow the wrong way, a
    module this change confirms as the one everything must visit — those are
    your findings. Read the surrounding code where you need it; the change
    alone does not show you the shape it is landing in.

    If the change leaves the shape no worse, say `Sound.` and stop.
  |]

-- | The cross-product: every lens answered by every backend, concurrently, over
-- one artifact. Leaf names are @lens\@backend@, so 'unionFindings' heads each
-- block with which lens on which model produced it.
panel :: [(LeafName, Prompt)] -> Flow Text Text
panel = panelAcross backends

-- | 'panel' over a chosen set of backends, and the generalisation 'panel' is
-- defined by — a narrowed panel cannot drift from the full one in leaf naming
-- or reduction. The @\@backend@ suffix stays even for a singleton, because
-- these blocks are read alongside a full panel's.
panelAcross :: [(LeafName, Flow Text Text -> Flow Text Text)] -> [(LeafName, Prompt)] -> Flow Text Text
panelAcross bs lenses =
  exploreFlows
    [ reviewer scope (name <> "@" <> backendTag) lens
    | (name, lens) <- lenses
    , (backendTag, scope) <- bs
    ]
    unionFindings

-- | The mid-run honesty auditor: read-only on codex, independent of the
-- claude-agent worker.
--
-- Marked 'withCapturedTranscript', so called from a run's trigger endpoint its
-- input is the worker's conversation rather than whatever was passed.
-- Undeclared workflows on the same beat ('reviewLite') keep the caller's input;
-- on a plain @agent-functor mcp@ server the mark is inert.
fessAudit :: Workflow
fessAudit =
  withCapturedTranscript
    $ workflowReq
      "fess-audit"
      [iii|
        Honesty-audit a worker's in-progress session
        (input is its captured transcript)
      |]
    $ withBackend codex defaultModel (withMode Plan (refineWith "fess" (brief fess) id))

-- | The human retrospective, over a session instead of an artifact: sentiment,
-- what went well and what it cost, then the meeting leaf that turns them into a
-- @## next time@ section.
--
-- 'withCapturedTranscript' for the same reason as 'fessAudit', but asked once at
-- the end rather than per commit, and about the process rather than the account.
-- Any @input@ arrives beside the transcript as steering.
--
-- The columns are a wave, not a chain, for the reason a facilitator has people
-- write cards before anyone speaks: a reader who has seen the cost column writes
-- a shorter good-news column. The synthesis is scoped 'Plan' explicitly because
-- this runs while the worker is still going.
retro :: Workflow
retro =
  withCapturedTranscript
    $ workflowReq
      "retro"
      [iii|
        Hold a retrospective on a worker's session (input is its captured
        transcript): sentiment, what went well, what did not, then the changes
        to make next time
      |]
      retroFlow

-- | 'retro' as a plain 'Flow', so 'Incite.Feature' can close a run with the same
-- three columns instead of copying them. One definition, two consumers — the
-- same reason 'reviewHeavyFlow' is a binding.
--
-- __The two consumers do not get the same input, and the difference is not
-- cosmetic.__ As the 'retro' workflow it is 'withCapturedTranscript': started
-- from a worker's trigger endpoint, its input is that worker's own conversation,
-- which is what the columns are written for (they ask for quoted lines). Inline
-- there is no such thing to hand it — a stage sees the previous leaf's output —
-- so 'Incite.Feature' reframes it first. The lenses are unchanged either way;
-- only what they are pointed at differs.
retroFlow :: Flow Text Text
retroFlow =
  exploreFlows
    [ reviewer (withBackend claudeAgent fable5) "sentiment" retroSentiment
    , reviewer (withBackend codex defaultModel) "went-well" retroWentWell
    , reviewer (withBackend opencode defaultModel) "went-wrong" retroWentWrong
    ]
    unionFindings
    >>> withMode Plan (refineWith "retro" (brief retroSynthesis) id)

-- | Audit an agent's __planner design__ against the lookahead rubric, defaulting
-- to this repo's own @workflows\/@. Not a 'reviewAudit' lens: in a general repo
-- it would design a planner that does not exist. Read-only on codex.
plannerAudit :: Workflow
plannerAudit =
  workflow
    "planner-audit"
    [iii|
      Audit an agent's planner design — plan shape, lookahead depth, reward
      estimation, replan triggers, compute budget — against the lookahead rubric
    |]
    [iii|
      The agent workflows defined under workflows/ in the current working
      directory. Read them, and the combinators they call, before diagnosing
      anything.
    |]
    $ withBackend codex defaultModel
    $ withMode Plan (refineWith "lookahead" (brief lookaheadPlanningSpecialist) id)

-- | Check this repo's own prompts against ASD-STE100 in the skill's CHECK mode:
-- rule number, offending text, compliant rewrite. On target because __the
-- prompts are the product here__ and every review tier reads code instead.
--
-- Two things in 'promptLintBrief' keep it from crying wolf: procedural passages
-- only (unscoped, it flags the whole repo), and 'steSkill' rather than
-- 'steRules' — the full skill is the only grade carrying the CHECK contract and
-- its warning that models invent STE rule numbers.
--
-- Reports rather than rewrites: 'Incite.Feature'\'s @simple-english@ lens is
-- where STE edits anything.
promptLint :: Workflow
promptLint =
  workflow
    "prompt-lint"
    [iii|
      Check prompt files against ASD-STE100 Simplified Technical English —
      rule, offending text, rewrite — over procedural instructions only
    |]
    [iii|
      The prompt files under prompts/, commands/, agents/ and skills/ in the
      current working directory. Read them before reporting anything.
    |]
    $ withBackend claudeAgent fable5
    $ withMode Plan
    $ refineWith "ste" (brief (promptLintBrief promptLintScope)) id

-- | What @prompt-lint@ is pointed at. A parameter of 'promptLintBrief' rather
-- than a line inside it, so a second panel can borrow the STE rubric without
-- telling its model it is reading a prompt repository.
promptLintScope :: Text
promptLintScope = "You are reading the prompt files of a repository whose product IS prompts."

-- | 'steSkill' plus the scoping that makes a prose rubric usable on a body of
-- text — @scope@ names what the reader is looking at, and everything else is
-- fixed.
--
-- __The rule-numbers clause is a brief, not a fence.__ \"Cite only rule numbers
-- that exist in the text above\" is grounded by the 'steSkill' splice being
-- present above it, which is a property of this function and holds at every
-- @scope@. That the model then obeys it is not checked anywhere, here or
-- downstream. Widening @scope@ costs nothing; dropping the splice would take
-- the grounding with it.
promptLintBrief :: Text -> Prompt
promptLintBrief scope =
  [__i|
    #{steSkill}

    ---

    CHECK mode, as defined above: report each violation as rule number, the
    offending text quoted exactly, and a compliant rewrite. Cite only rule
    numbers that exist in the text above — the warning above about models
    inventing STE rule numbers applies to you. If you cannot ground a number,
    name the rule instead.

    #{scope}
    Scope, and this decides whether the report is worth reading:

    - Report ONLY on PROCEDURAL passages — the instruction the agent must
      execute ("Keep one step per line:", "Emit the revised plan and NOTHING
      else", "Report each finding as..."). A model misreading one of those
      wastes a whole run, which is the cost you are hunting.
    - Do NOT report on DESCRIPTIVE passages — the rationale explaining why a
      lens exists or what a trade-off buys. That prose is elaborate on purpose.
      Where you are unsure which a passage is, skip it.
    - Never flag code identifiers, file paths, command names, quoted output
      formats, markdown structure, or interpolation placeholders.

    Rank by real ambiguity risk, not by rule severity: a 30-word sentence with
    one reading is not a finding, and a 12-word sentence with two possible
    referents is. Name any file that is already clean — that is useful.

    Finish with anything you found where STE's rule would make the prompt WORSE
    for a model reading it. Say so plainly; that is more valuable than a clean
    report.
  |]
