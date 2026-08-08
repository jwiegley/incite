{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Turning a request into a plan, and a plan into the work it asks for: a pull
-- request for code, edited prose for documentation.
--
-- 'planFeature', 'shipFeature' and 'shipDocs' over one shared prefix.
-- @explorePlan@ is the analysis half — explore, plan — and @editPlan@ is the
-- six-lens plan-editing chain; both are plain 'Flow' values, so 'planFeature'
-- stops there while the two acting workflows continue into the acting half.
--
-- __The acting half is shared by name, not by count.__ 'actingGrant' is the
-- exec policy, 'orchestrate' is the fuelled worker loop over 'continueMarker'
-- and @keepGoing@, and 'remediate' is the one leaf that fixes what a panel
-- found. What an acting workflow supplies for itself is its steer label, its
-- worker, its panel, the artifact rule its fixer stands under ('docsRule' or
-- 'codeRule'), and where it stops. Bindings rather than copies for one reason:
-- the workflows cannot drift in anything they share.
module Incite.Feature
  ( planFeature
  , shipFeature
  , shipDocs
  , continueMarker
  , decideContinue
  , asReviewSubject
  , asRetroSubject
  , asDocsSubject
  , document
  , remediate
  , docsRule
  , codeRule
  , actingGrant
  , orchestrate
  , workerFuel
  , Orientation (..)
  , orient
  , preambleOf
  , preambleViolations
  ) where

import Data.Char (isSpace)
import Data.List (nub)
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
import Agent.Grant (Grant, execGrant)
import Agent.Prompt (Prompt, brief, i, iii, __i)
import Agent.Run (Workflow, workflowGReq, workflowReq)

import Incite.Backend (fable5)
import Incite.Review (retroFlow, reviewDocsFlow, reviewHeavyFlow)
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
-- worktree, no git, no PR; 'shipFeature' and 'shipDocs' are the acting halves.
planFeature :: Workflow
planFeature =
  workflowReq
    "plan-feature"
    [iii|
      Explore a feature request, plan it, edit through lenses, review at scale
    |]
    (explorePlan >>> editPlan)

-- | 'planFeature' plus the acting half: orchestrated implementation → the
-- 'reviewHeavyFlow' panel → remediation → human gate → PR. Runs in an isolated
-- git worktree.
--
-- Review is the same panel "Incite.Review".reviewHeavy exposes as a tool — 21
-- reviewers, then one synthesis — and @remediate@ is the only leaf that acts on
-- it. Reviewers are read-only by construction, so nothing can fix its own
-- findings.
shipFeature :: Workflow
shipFeature =
  workflowGReq
    "ship-feature"
    [iii|
      Explore, plan, then implement under an orchestrator that re-runs the
      worker until it reports the plan finished; review the result with the
      full 21-reviewer panel, remediate the findings, human gate, then a PR
    |]
    actingGrant
    $ explorePlan
      >>> editPlan
      >>> steer "Review the plan — add any guidance before implementation begins"
      >>> orchestrate implement
      >>> reviewChange
      >>> remediate codeRule
      >>> retrospective
      >>> humanGate "Open a pull request for these changes?"
      >>> submitPR "Add --json flag" "Drafted by the ship-feature workflow."
  where
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

-- | 'shipFeature' for prose. It shares 'explorePlan', 'actingGrant',
-- 'orchestrate' and 'remediate' with the code path — so the two cannot drift in
-- anything they share — and supplies its own steer label, 'document' as the
-- worker, "Incite.Review".'reviewDocsFlow' as the panel, and 'docsRule' as the
-- rule its fixer stands under.
--
-- __It stops at @remediate@.__ No 'humanGate' and no 'submitPR', and that is a
-- safety property rather than an omission. An unattended run auto-answers the
-- gate — @gateAnswer@ defaults to @\"yes\"@ — and @--sandbox@ isolates the
-- working tree but not the network, so a PR leaf here would be an irreversible
-- action with nothing in the run able to stop it. The change lands in the tree;
-- opening the pull request stays a human's push.
--
-- __And no retrospective.__ 'shipFeature' holds one in front of its gate,
-- because a change you declined is the run worth reflecting on. With no gate
-- there is nothing to sit in front of, and 'retroFlow' is three more leaves.
shipDocs :: Workflow
shipDocs =
  workflowGReq
    "ship-docs"
    [iii|
      Explore a documentation request, plan it, then write under an orchestrator
      that re-runs the worker until it reports the plan finished; review the
      result with the four-lens documentation panel and remediate the findings
    |]
    actingGrant
    $ explorePlan
      >>> lensEdit [("simple-english", brief simpleEnglishLens)]
      >>> steer "Review the plan — add any guidance before writing begins"
      >>> orchestrate document
      -- The docs lenses read an artifact; what reaches them is the worker's
      -- closing account. 'asDocsSubject' points them at the files instead.
      >>> dimap' asDocsSubject id reviewDocsFlow
      >>> remediate docsRule

-- | The worker leaf of a documentation run: the one leaf that edits prose.
--
-- 'shipFeature'\'s @implement@ with the subject changed, and the differences
-- are the whole point of having two. It gets 'ponytailLadder' and 'wiggum' —
-- how much, how long — but __not__ 'agenticCoder', which is a brief about
-- writing code. In its place it stands under 'docsRule', the rule a
-- documentation worker breaks.
--
-- Top-level rather than bound inside its workflow, so that the test can see
-- that it splices 'continueMarker' rather than spelling it. A worker brief that
-- names a marker its orchestrator does not match strands the loop until the
-- fuel runs out, and that is not visible from any output.
--
-- Being top-level, it names __no stage that follows it__ — @implement@ can say
-- \"review comes next\" because it is private to the one @where@ block that
-- puts a review after it, and this is not. A leaf that spells its position is a
-- leaf whose text has to be edited to reuse it, and the edit is prose nothing
-- would flag.
document :: Flow Text Text
document =
  refineWith
    "document"
    ( brief
        [__i|
          #{ponytailLadder}

          #{wiggum}

          Write this documentation plan fully in the current repository — edit
          the documents directly.

          #{docsRule}

          Where the plan asks for something the code does not support, say so
          and why rather than skipping it in silence.

          Prefer deleting a false sentence to rewriting it, and prefer pointing
          the reader at the code to restating what the code says: a fact kept in
          two places is the next finding.

          You are running under an orchestrator that will call you again with
          your own summary as its input, so write the summary for your
          successor: which documents you changed, what you rejected and why, and
          what is left.

          End with a status line, alone on the last line:

          - `#{continueMarker}` — the plan is not finished. You will be called
            again.
          - `WORK COMPLETE` — every part of the plan is written or answered.
            Say which documents you wrote.
        |]
    )
    id

-- | The marker a worker ends on to ask the orchestrator for another trip.
-- Bound rather than written twice: the @implement@ brief tells the worker to
-- emit it and @keepGoing@ matches on it, and the two drifting apart would
-- strand the loop. Exported for the same reason — a second worker brief must
-- splice this and not its own spelling.
continueMarker :: Text
continueMarker = "WORK REMAINS"

-- | 'Right' ends an orchestrator loop, 'Left' feeds the worker's summary back
-- as the next trip's input. Continue only on the explicit marker: see the note
-- on exhaustion in 'orchestrate'.
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

-- | The exec policy every acting workflow runs under.
--
-- One value rather than one spelling per workflow: a grant is the blast radius
-- of a run, and two copies of it drift silently — nothing in a plan skeleton,
-- a cost estimate or a leaf's text moves when one of them widens.
--
-- Gates OUR 'Agent.Op.Exec' leaves only. The agent's own git and gh are
-- 'Agent.Op.Prompt' leaves it runs with its own tools, gated by its permission
-- modal.
actingGrant :: Grant
actingGrant = execGrant ["nix*"]

-- | The ceiling on how many times a worker may hand itself back its own summary
-- before the run is called a runaway. Fuel, not a schedule.
workerFuel :: Int
workerFuel = 8

-- | Run @worker@ under the orchestrator every acting workflow uses: each trip
-- is one worker turn taking the previous trip's own summary as its input, and
-- the loop ends the moment that summary does not ask to continue.
--
-- __'loopUntil', not a fixed unroll.__ Trip count is runtime and the worker
-- decides it. 'workerFuel' is the ceiling, not the plan — a job finished on
-- trip two costs two turns, where @workLoop n@ always cost @n@ and could not
-- stop.
--
-- The default direction is deliberate. 'loopUntil' __aborts on exhaustion__ by
-- upstream design (there is no yield-what-you-have policy), so @keepGoing@
-- continues only on an explicit marker and treats everything else as finished:
-- a confused worker ends the loop and gets reviewed, rather than burning the
-- fuel and halting the run with the work stranded.
orchestrate :: Flow Text Text -> Flow Text Text
orchestrate worker = loopUntil workerFuel (worker >>> keepGoing)

-- | __What a stage is pointed at__ when the artifact reaching it is a worker's
-- closing summary rather than the thing under review.
--
-- Every lens in this repository is written for the artifact itself — a diff, a
-- session, a document. After an orchestrator loop there is no such thing in
-- hand: a stage in a chain sees the previous leaf's output, which is an
-- account. An 'Orientation' names where the evidence actually is, so the lenses
-- go and read it instead of inferring it from the account.
data Orientation
  = -- | The working tree, as a diff. 'shipFeature'\'s review stage.
    AtChange
  | -- | The run's own record — its commits and what the panel did with them.
    -- 'shipFeature'\'s retrospective stage.
    AtRecord
  | -- | The documents in the tree, read against the code they describe. The
    -- docs panel's stage.
    AtDocs
  deriving (Eq, Show, Bounded, Enum)

-- | The preamble that points a stage at an 'Orientation'\'s evidence.
--
-- Three laws hold at every constructor, and 'preambleViolations' is where they
-- are written down as code:
--
-- * each preamble is __non-empty__ — an orientation that says nothing leaves
--   the lenses reading the account as though it were the artifact, which is the
--   whole failure this type exists to prevent;
-- * the preambles are __pairwise distinct__ — two orientations with the same
--   words are one orientation under two names;
-- * no preamble __ends in whitespace__ — 'orient' joins with exactly one blank
--   line, and a trailing newline here makes it two for that constructor alone.
--   Byte drift in a prompt is invisible at every other check.
--
-- Total in 'Orientation', so a new constructor cannot be added without saying
-- where its evidence lives.
preambleOf :: Orientation -> Text
preambleOf o = case o of
  AtChange ->
    [i|Review the change in the current working directory. Run `git diff`, `git diff --cached` and `git status` and read the result before reporting anything. The worker's own account of what it did follows — treat it as a claim to check, not as the change itself.|]
  AtRecord ->
    [i|Hold the retrospective on the work in the current working directory, not on a conversation: this run's record is what you have, and there is no transcript of the session.

So take your evidence from the record. Run `git log --oneline`, `git diff` and `git status`, and read them. The account below is the closing summary of the review-and-remediation stage — what the panel raised and what was done about it — and it is a claim to check against the commits, not the session itself.

Where a column asks you to quote, quote the record: a commit message, a finding, a line of the summary. Where the evidence for an entry is not in the record, say the record cannot show it and drop the entry — do not reconstruct the dialogue that would have produced it.|]
  AtDocs ->
    [i|Review the documentation in the current working directory. The documents are the artifact under review and the code is the record they answer to, so read both: `git ls-files '*.md'` for what there is to read, and the modules, workflows and flake each document describes.

Read the documents themselves before reporting anything. An account of them follows and it is a claim to check, not a substitute for the files — where it and a document disagree, the document is what ships.

Cite the document and the code on both sides of every finding. A statement about prose that you cannot point at a file and a line for is a preference, and a preference is not a finding here.|]

-- | Point a stage at an orientation's evidence and hand it the account beneath.
--
-- A pure prepend, not a leaf: a leaf to say one sentence is an agent turn spent
-- on a sentence. One join for every orientation, so a new one cannot arrive
-- with its own spacing.
orient :: Orientation -> Text -> Text
orient o summary = preambleOf o <> "\n\n" <> summary

-- | The three laws of 'preambleOf', as a refutable check: one 'Text' per law
-- the preamble breaks, and @[]@ for a set that holds all three.
--
-- Takes the whole list rather than one preamble because two of the three laws
-- are statements about the set. Quantified over 'Orientation' the laws pass by
-- construction, which is exactly why the refutable form lives here and is
-- tested against sets that break each one.
preambleViolations :: [Text] -> [Text]
preambleViolations ps =
  concat
    [ ["empty preamble" | any T.null ps]
    , ["duplicate preambles" | length (nub ps) /= length ps]
    , ["preamble ends in whitespace" | any endsInSpace ps]
    ]
  where
    endsInSpace p = not (T.null p) && isSpace (T.last p)

-- | 'orient' at 'AtChange'. Named because "Incite.Review"\'s panel lenses are
-- written for a diff and this is the one place that says which diff.
asReviewSubject :: Text -> Text
asReviewSubject = orient AtChange

-- | 'orient' at 'AtRecord'.
--
-- The retro's columns are written for a __captured session transcript__, and
-- inline there is none: 'Incite.Review.retro' gets one because the trigger
-- endpoint substitutes it ('Agent.Run.withCapturedTranscript'), but a stage in a
-- chain sees only the previous leaf's output. 'AtRecord' says so, rather than
-- letting three lenses infer a conversation from a summary and quote lines
-- nobody wrote. A retro on the record rather than on the dialogue is a narrower
-- retro, and saying which one it is beats producing the other one badly.
asRetroSubject :: Text -> Text
asRetroSubject = orient AtRecord

-- | 'orient' at 'AtDocs', for the docs panel's stage in 'shipDocs'.
--
-- Landed __ahead of its consumer__, together with
-- "Incite.Review".'reviewDocsFlow' and for the same reason: it is the piece the
-- composition needs, and landing it alone is what let its bytes be fenced
-- before anything depended on them.
asDocsSubject :: Text -> Text
asDocsSubject = orient AtDocs

-- | What the artifact is, and which side gives when the artifact and the record
-- it answers to disagree. One clause per acting workflow, and the argument
-- 'remediate' takes.
--
-- __'docsRule' is spliced into 'document' as well__, so a documentation run's
-- two writing leaves stand under one rule rather than two copies of it: the
-- worker writes under it and the fixer repairs under it. Two copies drift, and
-- the drift here has a name — a fixer that closes a \"this sentence is false\"
-- finding by editing the code the sentence describes. That move satisfies the
-- finding, passes every check downstream of it (there is none), and is the one
-- move both 'document' and 'AtDocs' forbid.
--
-- The pair is written out rather than one rule being the default, because
-- \"which one gives\" genuinely __inverts__ between the two: a code run's
-- findings are about the code, and refusing to touch it would leave every one
-- of them unfixed.
docsRule, codeRule :: Prompt
docsRule =
  [__i|
    The document is the artifact and the code is the record. Where the two
    disagree, correct the DOCUMENT — never edit code to make a sentence true.
  |]
codeRule =
  [__i|
    The change in this repository is the artifact and the tests are the record.
    Where a comment or a document has drifted from the code it describes, either
    side may be the wrong one — fix the one that is wrong and say which.
  |]

-- | The one leaf that acts on a panel's findings, standing under the rule for
-- the artifact it is repairing. Read-only reviewers cannot fix what they find,
-- which is why this exists separately.
--
-- __Parameterised, not shared bare.__ Both acting workflows reach it and the
-- ranked-findings half of the brief is identical for either, but the contract
-- is not: see 'docsRule' and 'codeRule'. The panels are already told which
-- artifact they read ('Orientation'); until this took an argument, the one leaf
-- that ACTS on what they said was the only stage of a documentation run that
-- was never told.
remediate :: Prompt -> Flow Text Text
remediate artifactRule =
  refineWith
    "remediate"
    ( brief
        [__i|
          #{ponytailLadder}

          #{fixAll}

          #{artifactRule}

          The ranked review findings follow. Fix every one of them in this
          repository, in the shortest change that fixes it. Where you judge
          a finding wrong, say so and why rather than silently skipping it:
        |]
    )
    id

-- | The shared analysis prefix: explore (three stances) then plan.
explorePlan :: Flow Text Text
explorePlan = explore >>> plan
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

-- | The six-lens plan-editing chain for code implementation plans. Order is the
-- argument: ponytail deletes first so the rest only work on surviving steps;
-- denotational redesigns (it rewrites what steps ARE, so before annotation or
-- ordering); risk annotates; verification turns the annotations into checks;
-- lookahead reorders for irreversibility last. No scope or sequencing lens:
-- ponytail owns the cuts, and dependency order is 'planBrief'\'s own format
-- contract.
editPlan :: Flow Text Text
editPlan =
  lensEdit
    [ ("ponytail", brief ponytailLens)
    , ("denotational", brief planDenotational)
    , ("risk", brief planRisk)
    , ("verification", brief planVerification)
    , ("lookahead", brief lookaheadLens)
    , ("simple-english", brief simpleEnglishLens)
    ]
  where
    ponytailLens =
      [__i|
        #{ponytailLadder}

        Apply the ladder above to this plan: drop steps that need not exist,
        collapse steps that a stdlib or native feature already covers, and merge
        steps that are one change. Emit the revised plan and nothing else: an
        ordered list, no headings, no preamble, no summary. Keep one step per
        line:
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

-- | The STE procedural rewording pass. A plan step is procedural text in STE's
-- exact sense — an instruction one agent picks up and executes without the
-- surrounding context. That is the register STE was built for: imperative, one
-- instruction per sentence, condition before command, and one word per meaning
-- for the whole plan. The only plan-editing lens relevant to documentation,
-- which IS prose; the code-focused lenses (denotational, risk, verification,
-- lookahead) have no purchase on a docs plan.
simpleEnglishLens :: Prompt
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
