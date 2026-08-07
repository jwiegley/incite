{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Turning a request into a plan, and a plan into a pull request.
--
-- Two workflows over one shared prefix. 'explorePlanEdit' is the analysis
-- half — explore, plan, edit through lenses — and it is a plain 'Flow' value,
-- so 'planFeature' stops there while 'shipFeature' continues into the acting
-- half: the orchestrator loop ('keepGoing'), the findings-fixer ('remediate'),
-- the retrospective and the gate-then-PR tail. The shared pieces are bindings
-- rather than copies for one reason: the two cannot drift in how they analyse.
--
-- The acting half is written to take a second consumer — 'remediate',
-- 'keepGoing' and 'continueMarker' are all top-level and none of them mentions
-- code — but it has only one today.
module Incite.Feature
  ( planFeature
  , shipFeature
  , continueMarker
  , decideContinue
  , asReviewSubject
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Agent.Backend (claudeAgent, codex, defaultModel, opencode, withBackend)
import Agent.Flow (Flow (Id), Mode (Plan), dimap', fanout', withMode, (>>>))
import Agent.Flow.Combinators
  ( exploreFlows
  , hierarchical
  , humanGate
  , lensEdit
  , refineWith
  , steer
  , submitPR
  )
import Agent.Flow.Extent (loopUntil)
import Agent.Grant (execGrant)
import Agent.Prompt (brief, i, iii, __i)
import Agent.Run (Workflow, workflowGReq, workflowReq)

import Incite.Backend (fable5)
import Incite.Review (retroFlow, reviewHeavyFlow)
import Incite.Prompts
    ( intrepid,
      skeptic,
      contemplative,
      planBrief,
      planDenotational,
      planRisk,
      planVerification,
      wiggum,
      fixAll,
      ponytailLadder,
      agenticCoder,
      lookaheadPlanningSpecialist,
      steRules )

-- | The analysis flagship: explore → plan → lens edit. Prompt-only — no
-- worktree, no git, no PR; 'shipFeature' is the acting half.
planFeature :: Workflow
planFeature =
  workflowReq
    "plan-feature"
    [iii|
      Explore a feature request, plan it, edit through lenses, review at scale
    |]
    explorePlanEdit

-- | 'planFeature' plus the acting half: orchestrated implementation → the
-- 'reviewHeavyFlow' panel → remediation → human gate → PR. Runs in an isolated
-- git worktree.
--
-- __The orchestrator is 'loopUntil', not a fixed unroll.__ Trip count is
-- runtime and the worker decides it: each trip is one 'implement' turn taking
-- the previous trip's own summary as its input, and the loop ends the moment
-- that summary does not ask to continue. Fuel is the ceiling, not the plan — a
-- feature finished on trip two costs two turns, where @workLoop n@ always cost
-- @n@ and could not stop.
--
-- The default direction is deliberate. 'loopUntil' __aborts on exhaustion__ by
-- upstream design (there is no yield-what-you-have policy), so 'keepGoing'
-- continues only on an explicit marker and treats everything else as finished:
-- a confused worker ends the loop and gets reviewed, rather than burning the
-- fuel and halting the run with the work stranded.
--
-- Review is the same panel 'reviewHeavy' exposes as a tool — 21 reviewers, then
-- one synthesis — and 'remediate' is the only leaf that acts on it. Reviewers
-- are read-only by construction, so nothing can fix its own findings.
shipFeature :: Workflow
shipFeature =
  workflowGReq
    "ship-feature"
    [iii|
      Explore, plan, then implement under an orchestrator that re-runs the
      worker until it reports the plan finished; review the result with the
      full 21-reviewer panel, remediate the findings, human gate, then a PR
    |]
    -- Gates OUR 'Exec' leaves only. The agent's own git and gh are 'Prompt'
    -- leaves it runs with its own tools, gated by its permission modal.
    (execGrant ["nix*"])
    $ explorePlanEdit
      >>> steer "Review the plan — add any guidance before implementation begins"
      >>> loopUntil 8 (implement >>> keepGoing)
      >>> reviewChange
      >>> remediate
      >>> retrospective
      >>> humanGate "Open a pull request for these changes?"
      >>> submitPR "Add --json flag" "Drafted by the ship-feature workflow."
  where
    -- Fuel, not a schedule: the ceiling on how many times the worker may hand
    -- itself back its own summary before the run is called a runaway.
    -- One worker implements the plan for real, editing this repository in
    -- place. Its standing brief composes 'agenticCoder' (HOW), 'ponytailLadder'
    -- (HOW MUCH) and 'wiggum' (HOW LONG) — ~7 KB, worth it on the one leaf that
    -- writes code unsupervised, and the reason the orchestrator needs no
    -- cadence of its own.
    implement =
      refineWith
        "implement"
        ( brief
            [__i|
              #{agenticCoder}

              #{ponytailLadder}

              #{wiggum}

              Implement this plan fully in the current repository — edit the
              files directly.

              You are running under an orchestrator that will call you again
              with your own summary as its input, so write the summary for your
              successor: what you changed, what is left, and what it needs to
              know to continue.

              End with a status line, alone on the last line:

              - `#{continueMarker}` — the plan is not finished. You will be
                called again.
              - `WORK COMPLETE` — every step is done and the build is green.
                Say what changed; review comes next.
            |]
        )
        id
    -- The panel's lenses are written for a diff, and the artifact here is the
    -- worker's closing summary: 'asReviewSubject' points them at the tree.
    reviewChange = dimap' asReviewSubject id reviewHeavyFlow
    -- Close the run with 'Incite.Review.retroFlow'\'s three columns.
    --
    -- __Before the gate, not after the PR.__ 'humanGate' halts the workflow when
    -- you decline, so anything downstream of it never runs on a no — and a change
    -- you declined is precisely the run worth holding a retrospective on.
    --
    -- __A fanout, not a plain '>>>'.__ 'submitPR' quotes the value it receives as
    -- \"work so far\", and handing that leaf a retrospective would describe the
    -- session where it needs the change. So the worker's account flows on
    -- untouched and the retro is appended under its own heading, which keeps it
    -- in the run's final artifact without becoming the brief for the next leaf.
    retrospective =
      dimap' id merge (fanout' Id (dimap' asRetroSubject id retroFlow))
      where
        merge (work, r) = work <> "\n\n## retrospective\n\n" <> r

-- | The marker a worker ends on to ask the orchestrator for another trip.
-- Bound rather than written twice: the 'implement' brief tells the worker to
-- emit it and 'keepGoing' matches on it, and the two drifting apart would
-- strand the loop. Exported for the same reason — a second worker brief must
-- splice this and not its own spelling.
continueMarker :: Text
continueMarker = "WORK REMAINS"

-- | 'Right' ends an orchestrator loop, 'Left' feeds the worker's summary back
-- as the next trip's input. Continue only on the explicit marker: see the note
-- on exhaustion in 'shipFeature'.
--
-- The match is the briefs' own contract — the marker alone on the last line —
-- not an infix scan of the whole summary: prose like "no work remains"
-- contains the marker and would spin the loop until the fuel aborts it.
decideContinue :: Text -> Either Text Text
decideContinue out
  | lastNonEmptyLine out == T.toLower continueMarker = Left out
  | otherwise = Right out

lastNonEmptyLine :: Text -> Text
lastNonEmptyLine =
  T.toLower
    . T.dropAround (`elem` ("`*_ ." :: String))
    . lastOrDefault T.empty
    . filter (not . T.null . T.strip)
    . T.lines

lastOrDefault :: a -> [a] -> a
lastOrDefault d [] = d
lastOrDefault _ xs = last xs

keepGoing :: Flow Text (Either Text Text)
keepGoing = dimap' id decideContinue Id

-- | Every panel's lenses are written for a diff, and the artifact after an
-- orchestrator loop is the worker's closing summary. A pure prepend points
-- them at the working tree — a leaf to say this would be an agent turn spent
-- on one sentence.
asReviewSubject :: Text -> Text
asReviewSubject summary =
  [i|Review the change in the current working directory. Run `git diff`, `git diff --cached` and `git status` and read the result before reporting anything. The worker's own account of what it did follows — treat it as a claim to check, not as the change itself.

#{summary}|]

-- | The retro's columns are written for a __captured session transcript__, and
-- inline there is none: 'Incite.Review.retro' gets one because the trigger
-- endpoint substitutes it ('Agent.Run.withCapturedTranscript'), but a stage in a
-- chain sees only the previous leaf's output. This says so, rather than letting
-- three lenses infer a conversation from a summary and quote lines nobody wrote.
--
-- It also names where the evidence actually is. The columns ask for grounding —
-- a moment, a quote, a consequence — and here that lives in the run's artifacts:
-- the commits, the review findings the panel raised, and what remediation did
-- with them. A retro on the record rather than on the dialogue is a narrower
-- retro, and saying which one it is beats producing the other one badly.
asRetroSubject :: Text -> Text
asRetroSubject summary =
  [i|Hold the retrospective on the work in the current working directory, not on a conversation: this run's record is what you have, and there is no transcript of the session.

So take your evidence from the record. Run `git log --oneline`, `git diff` and `git status`, and read them. The account below is the closing summary of the review-and-remediation stage — what the panel raised and what was done about it — and it is a claim to check against the commits, not the session itself.

Where a column asks you to quote, quote the record: a commit message, a finding, a line of the summary. Where the evidence for an entry is not in the record, say the record cannot show it and drop the entry — do not reconstruct the dialogue that would have produced it.

#{summary}|]

-- | The one leaf that acts on a panel's findings — shared by both acting
-- workflows, because fixing a doc finding and fixing a code finding is the
-- same contract. Read-only reviewers cannot fix what they find, which is why
-- this exists separately.
remediate :: Flow Text Text
remediate =
  refineWith
    "remediate"
    ( brief
        [__i|
          #{ponytailLadder}

          #{fixAll}

          The ranked review findings follow. Fix every one of them in this
          repository, in the shortest change that fixes it. Where you judge
          a finding wrong, say so and why rather than silently skipping it:
        |]
    )
    id

-- | The shared analysis prefix of both feature workflows.
explorePlanEdit :: Flow Text Text
explorePlanEdit = explore >>> plan >>> edit
  where
    -- Analysis-only, enforced at the session level ('withMode Plan'), and
    -- heterogeneous — one backend per stance, so the perspectives are
    -- genuinely independent.
    explore =
      withMode Plan $
        exploreFlows
          [ ("intrepid", withBackend claudeAgent defaultModel (refineWith "intrepid" (brief intrepid) id))
          , ("skeptic", withBackend codex defaultModel (refineWith "skeptic" (brief skeptic) id))
          , ("contemplative", withBackend opencode defaultModel (refineWith "contemplative" (brief contemplative) id))
          ]
          (hierarchical ["skeptic", "contemplative", "intrepid"])
    -- Read-only, pinned to Fable 5: 'planBrief' leans on both.
    plan =
      withMode Plan
        $ withBackend claudeAgent fable5
        $ refineWith "plan" (brief planBrief) id
    -- Order is the argument: ponytail deletes first so the rest only work on
    -- surviving steps; denotational redesigns (it rewrites what steps ARE, so
    -- before annotation or ordering); risk annotates; verification turns the
    -- annotations into checks; lookahead reorders for irreversibility last.
    -- No scope or sequencing lens: ponytail owns the cuts, and dependency
    -- order is 'planBrief'\'s own format contract.
    edit =
      lensEdit
        [ ("ponytail", brief ponytailLens)
        , ("denotational", brief planDenotational)
        , ("risk", brief planRisk)
        , ("verification", brief planVerification)
        , ("lookahead", brief lookaheadLens)
        , ("simple-english", brief simpleEnglishLens)
        ]

    ponytailLens =
      [__i|
        #{ponytailLadder}

        Apply the ladder above to this plan: drop steps that need not exist,
        collapse steps that a stdlib or native feature already covers, and merge
        steps that are one change. Keep one step per line:
      |]
    -- The format override is load-bearing: the rubric ships a ten-section
    -- OUTPUT FORMAT, and every downstream stage is line-oriented.
    lookaheadLens =
      [__i|
        #{lookaheadPlanningSpecialist}

        ---

        IGNORE the OUTPUT FORMAT section above. It is written for auditing an
        agent's planner; you are editing an implementation plan, and the plan's
        format is fixed. Emit the revised plan and NOTHING else: an ordered list,
        one step per line, no headings, no sections, no preamble, no summary.

        Apply the rubric's THINKING to the plan:

        - Mark every step that is irreversible or expensive to undo, and make
          sure a cheap reversible check runs before it, not after.
        - Where a step commits to an approach that later steps cannot back out
          of, say what would tell you the approach is wrong, and put that
          evidence-gathering step first.
        - Cut greedy ordering: a step that is locally convenient but forecloses a
          better route two steps later gets moved or replaced.
        - Where the plan cannot know something yet, say what the plan does when
          the assumption fails, rather than assuming it holds.

        Do not add steps that only measure or report. Keep one step per line:
      |]
    -- Last, and last on purpose: this is a WORDING pass, and every lens before
    -- it still changes which steps exist. Rewriting prose that ponytail is
    -- about to delete is wasted.
    --
    -- A plan step is procedural text in STE's exact sense — an instruction one
    -- agent picks up and executes without the surrounding context. That is the
    -- register STE was built for, so this lens is a fit rather than a stretch:
    -- imperative, one instruction per sentence, condition before command, and
    -- one word per meaning for the whole plan.
    simpleEnglishLens =
      [__i|
        #{steRules}

        ---

        Apply the PROCEDURAL rules above to this plan. Every step is procedural
        text: imperative, one instruction, maximum 20 words, condition before
        command. The descriptive limits do not apply here — there is no
        descriptive text in a plan.

        This is a rewording pass ONLY. Do not add a step, remove a step, merge
        two steps, reorder anything, or change what any step does. Earlier lenses
        settled all of that. If a step is wrong, leave it wrong and reword it.

        Hold the vocabulary steady across the WHOLE plan, not per step: pick one
        of check/verify/confirm and use only that one, and the same for any other
        set of synonyms the plan rotates through.

        Never touch code identifiers, file paths, module names, command names, or
        quoted output formats. They are exact and each counts as one word.

        Emit the revised plan and nothing else. Keep one step per line:
      |]
