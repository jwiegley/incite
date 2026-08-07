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
  , reviewDocs
  , reviewDocsFlow
  , fessAudit
  , retro
  , retroFlow
  , plannerAudit
  , promptLint
  , promptLintBrief
  , promptLintScope
  , Subject (..)
  , lensesOf
  , lensSetViolations
    -- * Reorientations
    --
    -- | The lens bodies this module writes itself, rather than reading from a
    -- file: an upstream rubric plus one adjustment. Exported so a test can
    -- name the body each lens is supposed to carry — see @lensesOf@\'s
    -- expected table in @test\/Spec.hs@.
  , architectureOfChange
  , docsAccuracy
  , ponytailOfDocs
  ) where

import Data.List (nub, (\\))
import Data.Text (Text)
import qualified Data.Text as T
import Agent.Backend (claudeAgent, codex, defaultModel, opencode, withBackend)
import Agent.Flow (Flow, Mode (Plan), withMode, (>>>))
import Agent.Flow.Combinators (exploreFlows, hierarchical, refineWith, unionFindings)
import Agent.Op (LeafName, leafNameText)
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

-- | The same shape pointed at prose: three lenses that only a document admits,
-- plus the ponytail question every artifact admits, each answered by all three
-- backends, then the same synthesis leaf.
--
-- __No regroupings.__ 'reviewAudit' buys its third tier by re-expressing a
-- change as logical units and as the commits it should have been. Neither view
-- exists for a document — a README has no commit sequence it should have been —
-- so this tier is the panel and the reduction, and nothing else.
reviewDocs :: Workflow
reviewDocs =
  workflowReq
    "review-docs"
    [iii|
      Review documentation with three lenses only prose admits (accuracy against
      the code, completeness for a reader who follows it, structure) plus the
      ponytail cuts every artifact admits, each run on all three backends, then
      synthesise one ranked list
    |]
    reviewDocsFlow

-- | 'reviewDocs' as a plain 'Flow', so the acting workflow of "Incite.Feature"
-- can run the same panel inline rather than copying it.
--
-- __One consumer today__, unlike 'reviewHeavyFlow'\'s two: 'reviewDocs' is the
-- only caller. The binding is written ahead of the second consumer, and that is
-- the whole reason it is separate from the workflow.
--
-- 'reviewSynthesis' is reused rather than copied for prose: it says
-- \"reviewers\", \"finding\" and \"location\" and never \"code\", so what it
-- de-duplicates and ranks is already artifact-agnostic.
--
-- __Do not union this panel with a code panel.__ Every subject carries a lens
-- named @ponytail@ — the third law of 'lensesOf' — and @panelAcross@ keys its
-- blocks @lens\@backend@, so one 'unionFindings' over both would head two
-- different rubrics with the same @ponytail\@codex@, which is the collision the
-- pairwise-distinct law exists to prevent. Reduce each panel separately.
reviewDocsFlow :: Flow Text Text
reviewDocsFlow =
  panel (lensesOf OfDocs) >>> refineWith "synthesis" (brief reviewSynthesis) id

-- | The __kind of artifact__ a panel is pointed at. Not a switch over which
-- lenses differ — a name for what is under review, from which the lens set
-- follows. The type says what is being read, and 'lensesOf' says what reading
-- it admits.
--
-- A subject that shares no __rubric__ with the others is still a 'Subject':
-- 'OfDocs' is one, and not one body in its panel is a body a code panel sends.
-- It is not free of the others in its __names__, and cannot be — 'lensesOf'\'s
-- third law puts @\"ponytail\"@ in every subject's set, so that one name is
-- shared by construction and is the only one 'OfDocs' has in common with
-- 'OfDiff'.
data Subject
  = -- | 'reviewHeavy': the diff, and nothing wider.
    OfDiff
  | -- | 'reviewAudit': the change, and the shape it moves the code toward.
    OfChange
  | -- | 'reviewDocs': prose, and the code it makes claims about.
    OfDocs
  deriving (Eq, Show, Bounded, Enum)

-- | The lenses that artifact admits, in the order their blocks are read.
--
-- Three laws hold at every constructor, and 'lensSetViolations' is where they
-- are written down as code:
--
-- * the list is __non-empty__ — a subject with no lens is a panel with nothing
--   to fan out;
-- * the leaf names are __pairwise distinct__ — @panelAcross@ keys blocks by
--   @lens\@backend@, so a repeat makes two reviewers indistinguishable in the
--   reduction;
-- * @\"ponytail\"@ is __present__ — every artifact admits the question of what
--   should not exist, and each subject picks the rubric pointed at it.
--
-- Total in 'Subject', so a new constructor cannot be added without answering
-- what its artifact admits.
lensesOf :: Subject -> [(LeafName, Prompt)]
lensesOf subject = case subject of
  OfDiff -> codeLenses ponytailReviewRubric
  OfChange -> codeLenses ponytailAuditRubric <> [("architecture", architectureOfChange)]
  OfDocs ->
    [ ("accuracy", docsAccuracy)
    , ("completeness", docsCompleteness)
    , ("structure", docsStructure)
    , ("ponytail", ponytailOfDocs)
    ]
  where
    codeLenses ponytailRubric =
      [ ("correctness", reviewCorrectness)
      , ("security", codeReviewerSecurity)
      , ("tests", reviewTests)
      , ("performance", perfReviewer)
      , ("haskell", haskellReviewer)
      , ("ponytail", ponytailRubric)
      , ("doctrine", codeReview)
      ]

-- | 'lensesOf'\'s three laws as a refutable check: one 'Text' per law the set
-- breaks, and @[]@ for a set that holds all three.
--
-- __Beside 'lensesOf' rather than in the test suite__, because the laws are
-- stated on 'lensesOf' and an executable statement that lives somewhere else is
-- one a reader of this module cannot reach — the haddock above linked a name
-- that was not in scope here. A new 'Subject' now answers its laws in one file.
--
-- __A report rather than an assertion__, and that is the whole reason it is a
-- separate binding. Quantified over 'Subject' these laws pass by construction,
-- so a check that could only ever be pointed at 'lensesOf' would be a law
-- nobody knows is wired to anything. Returning what is wrong instead of
-- throwing is what lets a caller point it at a set that BREAKS each law and
-- read back the right complaint.
--
-- Emptiness has no single-defect witness: @[]@ reports the missing ponytail
-- too, because a set with no lenses has no ponytail lens either.
lensSetViolations :: [(LeafName, Prompt)] -> [Text]
lensSetViolations lenses =
  concat
    [ ["empty lens set" | null names]
    , ["duplicate lens names: " <> T.pack (show dups) | not (null dups)]
    , ["no ponytail lens" | "ponytail" `notElem` names]
    ]
  where
    names = map (leafNameText . fst) lenses
    dups = names \\ nub names

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

-- | The honesty rubric pointed at a document. A reorientation rather than a
-- file under @prompts\/review@, for the reason "Incite.Prompts" gives on
-- 'docsCompleteness': a second copy of 'fess' is one of the three homes
-- 'docsStructure' is written to report.
docsAccuracy :: Prompt
docsAccuracy =
  [__i|
    #{fess}

    ---

    ONE ADJUSTMENT to the above, and it is a change of referent. You are a
    reviewer; the account is not yours. It is a __document__ in this repository,
    written by somebody else, and the record it answers to is the code. Wherever
    the rubric says you, your account, a claim you made or the work you claimed,
    read the document and its author instead.

    So: the document is the claim, the code is the record. Every command it
    tells the reader to run, and every flag, path, identifier, default and
    version it names — open the code, check it, cite file:line on both sides.

    Of the four shapes above, three repoint and one is void:

    * verification gap — a claim nothing in the repository backs up;
    * spec drift — a behaviour the code changed, still described the old way;
    * quiet downgrades — prose left describing what was there before a change;
      here that is most of the work;
    * scope creep — VOID. A document modifies no file. Do not report it, and do
      not report "none" for it either.

    The closing paragraph above is VOID as well. There is no list of gaps "you
    did not report", and "correcting means doing the work you claimed, not
    editing the claim" inverts the remedy here: the claim IS the artifact, so
    correcting a false sentence means editing that sentence, and never means
    changing the code to match it.

    A fact that is MISSING belongs to the completeness reviewer, and one in the
    wrong PLACE to the structure reviewer; you judge only whether what is
    written is true. Where you cannot reach the code that settles a claim, name
    what you would read and do not grade it either way.

    If every claim you checked holds, say `Sound.` and stop.
  |]

-- | The ponytail question — what should not exist — asked of prose. Raw,
-- 'ponytailAuditRubric' hunts dependencies, factories and dead flags, so
-- pointed at a README it finds nothing or invents something, and a lens that
-- emits noise costs more than no lens.
ponytailOfDocs :: Prompt
ponytailOfDocs =
  [__i|
    #{ponytailAuditRubric}

    ---

    ONE ADJUSTMENT to the above, and it is a change of subject: you are reading
    __documentation__, not a source tree. The measure stands — what would
    deletion fix — and so does the ranking. Its named sections do not, and each
    one is replaced here outright.

    __Hunt.__ The list above (deps, interfaces, factories, wrappers, dead flags,
    hand-rolled stdlib) is VOID; a document is made of none of them. Hunt these:

    * a paragraph that says what the paragraph above it already said;
    * a section for something that no longer exists, or a step nobody performs;
    * prose explaining what the one command below it already shows;
    * a table or example held in step with the code by hand, where the code
      answers the same question — name what to point the reader at instead;
    * ceremony: a preamble before the instruction, a summary of the document
      inside the document.

    __Tags.__ `delete:` is prose nothing needs; `yagni:` a section written for a
    reader who does not exist; `shrink:` the same point in fewer lines, with the
    shorter form shown. `stdlib:` and `native:` fire only where the document
    maintains by hand what the tooling already prints, such as a help text.

    __Output.__ One line per finding, ranked, as above, and `[path]` is the file
    and the heading you would cut under. A document has no dependencies to
    count, so the deps figure is VOID: end with `net: -<N> lines possible.`
    Nothing to cut: `Lean already. Ship.`

    __Boundaries.__ Read "over-engineering and complexity" as prose that should
    not exist. What the document gets WRONG belongs to the accuracy reviewer,
    what it LEAVES OUT to completeness, where a section SITS to structure.
    Length alone is not a finding: a long passage the reader needs stays, and a
    cut you cannot name a reader for is not a cut.
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
--
-- __The reorientations are named explicitly__, because they are the prompts no
-- other STE check can reach: @checks.ste-prompts@ lints @.md@ files, and these
-- three are Haskell literals in this module, so a directory list alone leaves
-- the only prompt bodies this repository writes in code with no coverage at
-- all.
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
      current working directory, and the prompt bodies written as Haskell
      literals in workflows/Incite/Review.hs — architectureOfChange,
      docsAccuracy and ponytailOfDocs — whose adjustment text is the only
      prompt prose here that is in no .md file. Read them before reporting
      anything.
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
