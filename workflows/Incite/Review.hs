{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | The review and audit tiers: fan independent reviewers over one artifact
-- concurrently, then reduce.
--
-- One shape, escalating along three independent axes, and each buys something
-- different:
--
-- * __lenses__ buy coverage — 'reviewLite' runs four, 'reviewHeavy' seven,
--   'reviewAudit' eight;
-- * __backends__ buy confidence — from 'reviewHeavy' up, every lens is answered
--   by all three models, so agreement is confirmation and disagreement is
--   signal rather than one model's opinion;
-- * __granularity__ buys a kind of finding the others structurally cannot
--   reach, and only 'reviewAudit' pays for it.
--
-- Every reviewer is read-only ('withMode' 'Plan' inside
-- 'Incite.Backend.reviewer'), so no tier can edit what it is reading. ponytail
-- is one lens among several, never the whole review — its own rubric refuses
-- correctness and security work.
module Incite.Review
  ( reviewLite
  , reviewHeavy
  , reviewHeavyFlow
  , reviewAudit
  , fessAudit
  , plannerAudit
  , promptLint
  ) where

import Data.Text (Text)
import Agent.Backend (claudeAgent, codex, defaultModel, opencode, withBackend)
import Agent.Flow (Flow, Mode (Plan), withMode, (>>>))
import Agent.Flow.Combinators (exploreFlows, hierarchical, refineWith, unionFindings)
import Agent.Op (LeafName)
import Agent.Prompt (Prompt, brief, iii, __i)
import Agent.Run (Workflow, withCapturedTranscript, workflow, workflowReq)

import Incite.Backend (backends, fable5, reviewer)
import Incite.Prompts

-- | The cheap tier, fired by @wiggum@ after every commit: four reviewers over
-- one artifact, reduced by a pure fold — one concurrent wave, no synthesis
-- leaf. 'hierarchical' ranks correctness > fess > complexity > ponytail.
--
-- Deliberately __not__ 'withCapturedTranscript' even though fess is a lens
-- here: every 'exploreFlows' leaf reads the same input, so the mark would hand
-- the three code lenses a conversation log too. This fess audits claims
-- against the diff (\"the message says tests were added; are they in it?\");
-- 'fessAudit' is the marked, whole-session version.
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

-- | The thorough tier: the full cross-product — seven review lenses, each run
-- on all three backends, 21 reviewers summed by 'unionFindings' — then a
-- synthesis leaf de-duplicates and ranks. Where 'reviewLite' spreads its
-- lenses across backends for cheap independence, this buys the real thing.
-- Use before a PR, not on a beat.
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

-- | 'reviewHeavy' as a plain 'Flow', so 'Incite.Feature' can run the same panel
-- inline after implementation instead of copying it. One definition, two
-- consumers, no drift — the same reason 'Incite.Feature.explorePlanEdit' is a
-- binding.
reviewHeavyFlow :: Flow Text Text
reviewHeavyFlow =
  panel (lensesOf OfDiff)
    >>> refineWith "synthesis" (brief reviewSynthesis) id

-- | The exhaustive tier: 'reviewHeavy'\'s panel plus a change-reframed
-- architecture lens, run at __three granularities__ — the diff as landed,
-- regrouped into logical units ('reviewUnits'), and re-expressed as the
-- commits it should have been ('reviewSequence', whose @## divergence@ is the
-- finding only that view produces) — then one synthesis over the lot.
-- 75 leaves: run it deliberately, never on a beat.
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
    -- Re-express the change, then put the whole panel on the re-expression.
    regroup name how = refineWith ("regroup:" <> name) (brief how) id >>> panel auditLenses

-- | What a panel is pointed at — the only axis on which the lens set varies.
--
-- Two lenses are subject-dependent and the rest are not, so this is the
-- distinction that decides both: ponytail ships one rubric for a diff and
-- another for a whole tree, and architecture is a question you can only ask of
-- a change (a diff on its own does not show the shape it lands in).
data Subject
  = -- | 'reviewHeavy': the diff, and nothing wider.
    OfDiff
  | -- | 'reviewAudit': the change, and the shape it moves the code toward.
    OfChange

-- | The lenses for a subject. Total in 'Subject', so a third one cannot be
-- added without answering both questions it raises — which is the point of
-- doing this with a type rather than by rewriting entries in a list.
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

-- | 'reviewArchitecture' is whole-tree by its own contract, and says so. This
-- reorientation keeps its questions — leaking boundaries, arrows pointing the
-- wrong way, one decision in many homes — and points them at the shape a change
-- moves toward. The file itself is untouched, so the standalone agent stays
-- whole-tree.
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
panel lenses =
  exploreFlows
    [ reviewer scope (name <> "@" <> backendTag) lens
    | (name, lens) <- lenses
    , (backendTag, scope) <- backends
    ]
    unionFindings

-- | The mid-run honesty auditor: read-only on codex, independent of the
-- claude-agent worker; reports, never edits.
--
-- The one workflow marked 'withCapturedTranscript': called from a run's
-- trigger endpoint, its input becomes the worker's captured conversation and
-- the input requirement is bypassed. Undeclared workflows on the same beat
-- ('reviewLite') keep the caller's input — that distinction is the point. On a
-- plain @agent-functor mcp@ server the mark is inert.
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

-- | Audit an agent's __planner design__ against the lookahead rubric. Defaults
-- to this repo's own @workflows\/@, its real subject; point it elsewhere via
-- the input. Deliberately not a 'reviewAudit' lens — in a general repo it
-- would design a planner that does not exist. Read-only on codex.
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

-- | Check this repo's own prompts against ASD-STE100, in the skill's CHECK mode:
-- rule number, offending text, compliant rewrite.
--
-- On target because __the prompts are the product here__. A brief that reads two
-- ways is a defect with a price — an agent that misreads @Keep one step per
-- line@ wastes a whole run — and unlike prose defects elsewhere, nothing else in
-- this repo looks for it: every review tier reads code.
--
-- Two things keep it from crying wolf, and both are in the brief:
--
-- * __Procedural passages only.__ STE's own split. The instruction an agent
--   executes has to survive one read; the rationale around it is deliberately
--   elaborate and is not a defect. Unscoped, this lens flags the whole repo.
-- * __'steSkill', not 'steRules'.__ The full skill is the only one carrying the
--   CHECK contract, including its warning that the rule numbering is
--   unintuitive and models cite it from memory — it names a real observed case.
--   A linter citing invented rule numbers is worse than no linter.
--
-- Read-only, and it reports rather than rewrites: 'Incite.Feature'\'s
-- @simple-english@ lens is where STE actually edits anything.
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
    $ refineWith "ste" (brief promptLintBrief) id

-- | 'steSkill' plus the scoping that makes a prose rubric usable on a prompt
-- repository.
promptLintBrief :: Prompt
promptLintBrief =
  [__i|
    #{steSkill}

    ---

    CHECK mode, as defined above: report each violation as rule number, the
    offending text quoted exactly, and a compliant rewrite. Cite only rule
    numbers that exist in the text above — the warning above about models
    inventing STE rule numbers applies to you. If you cannot ground a number,
    name the rule instead.

    You are reading the prompt files of a repository whose product IS prompts.
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
