{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}

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
-- and 'decideTrip', and 'remediate' is the one leaf that fixes what a panel
-- found. What an acting workflow supplies for itself is its steer label, its
-- worker, its panel, the artifact rule its fixer stands under ('docsRule' or
-- 'codeRule'), and where it stops. Bindings rather than copies for one reason:
-- the workflows cannot drift in anything they share.
--
-- 'stackPRs' is the third acting shape over those same pieces, pointed at one
-- change rather than at a request: it cuts a large diff into an ordered stack of
-- branches. What it adds is a second harness-run gate — 'budgetGate' asks
-- whether a CI slot may be spent at all, with a real exit code, before every
-- trip of the promotion loop.
module Incite.Feature
  ( planFeature
  , shipFeature
  , shipDocs
  , docsPlanLenses
  , grindParadox
  , continueMarker
  , decideContinue
  , decideTrip
  , isRed
  , decideRed
  , asReviewSubject
  , asRetroSubject
  , asDocsSubject
  , asStackSubject
  , document
  , retrospective
  , keeping
  , remediate
  , docsRule
  , codeRule
  , actingGrant
  , closeWithChanges
  , fixerContinuation
  , orchestrate
  , orchestrateWith
  , workerFuel
  , stackFuel
  , repairFuel
  , checkLoop
  , greenGate
  , repairLeaf
  , GrindSpec (..)
  , grindCheckCmd
  , grindChecks
  , grindFlow
  , grindGrant
  , grindGrantFor
  , grindRule
  , grindTests
  , grindTestsChecks
  , grindTestsGrant
  , grindTestsReviewFuel
  , grindTestsRule
  , grindLiveView
  , grindLiveViewChecks
  , grindLiveViewGrant
  , grindLiveViewRanking
  , grindLiveViewRule
  , grindLiveViewSpec
  , paradoxRule
  , stackPRs
  , stackPlanLenses
  , stackRule
  , stackChecks
  , budgetCheck
  , consentCheck
  , consentGate
  , budgetFuel
  , budgetGate
  , stackGrant
  , stackWorker
  , stackPin
  , stackGate
  , stackContinuation
  , blockedMarker
  , Orientation (..)
  , orient
  , preambleOf
  , preambleViolations
  ) where

import Data.Char (isSpace)
import Data.List (nub)
import qualified Data.List.NonEmpty as NE
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import qualified Data.Text as T
import Agent.Backend (claudeAgent, defaultModel, withBackend)
import Agent.Flow (Flow (Id), Mode (Plan), dimap', fanout', left'', second'', withMode, (>>>))
import Agent.Flow.Combinators
  ( exploreFlows
  , hierarchical
  , humanGate
  , lensEdit
  , refineWith
  , steer
  , submitPR
  , verify
  )
import Agent.Flow.Extent (loopUntil)
import Agent.Grant (Grant, execGrant)
import Agent.Op (LeafName)
import Agent.Prompt (Prompt, brief, i, iii, promptText, __i)
import Agent.Run (Workflow, workflowG, workflowGReq, workflowReq)

import Incite.Backend (backends, codexScope, fable5, opencodeScope, reviewer)
import Incite.Review
  ( Subject (OfTree)
  , docsStrategyOfPlan
  , emissionLenses
  , grindName
  , grindSynthesisOver
  , grindTestsLenses
  , grindTestsName
  , grindLiveViewLenses
  , grindLiveViewName
  , lensesOf
  , retroFlow
  , reviewAuditFlow
  , reviewDocsFlow
  , reviewHeavyFlow
  , spread
  )
import Incite.Prompts
    ( intrepid,
      skeptic,
      contemplative,
      architect,
      planBrief,
      planDenotational,
      planRisk,
      planVerification,
      wiggum,
      fixAll,
      ponytailLadder,
      agenticCoder,
      lookaheadPlanningSpecialist,
      paradoxFacts,
      stackDisciplines,
      stackFacts,
      stackPromote,
      stackSlice,
      stackSlicePlan,
      stackTooling,
      stackTriage,
      steRules,
      testsFacts,
      liveViewFacts )

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
      >>> remediate codeRule closeWithChanges
      >>> retrospective
      >>> humanGate "Open a pull request for these changes?"
      >>> submitPR "Add --json flag" "Drafted by the ship-feature workflow."
  where
    -- One worker implements the plan for real, editing this repository in
    -- place. Its standing brief composes 'agenticCoder' (HOW), 'ponytailLadder'
    -- (HOW MUCH) and 'wiggum' (HOW LONG) — ~7 KB, worth it on the one leaf that
    -- writes code unsupervised, and the reason the orchestrator needs no
    -- cadence of its own.
    --
    -- __Pinned, and the only leaf in this workflow that is.__ The lens chains
    -- around it are deliberately left on the run's own backend, because they are
    -- several readings of one text and their argument is that they stay
    -- comparable. This leaf is different in kind: it is the one that writes code
    -- unsupervised, under an orchestrator that will call it again, so its model
    -- is a decision rather than a default. Left unpinned it inherits the run's —
    -- a @run --backend codex@, or an MCP caller passing @backend@, silently
    -- moves the leaf that does the work, and no leaf name, plan skeleton or cost
    -- estimate moves with it.
    --
    -- 'defaultModel' is claude-agent's own default (Claude Opus), deliberately
    -- __not__ 'fable5'. Fable is pinned on the review and planning lenses, where
    -- a fast reader over a fixed text is the point. Implementation is not that.
    implement = withBackend claudeAgent defaultModel implementLeaf

    -- Separated from its scope so the brief's indentation is untouched by it:
    -- the body is a `__i` quasi-quote, and re-indenting a quasi-quote to nest it
    -- one level deeper edits the prompt.
    implementLeaf =
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

-- | Close a run with "Incite.Review".'retroFlow'\'s three columns, appended to
-- the work rather than replacing it.
--
-- __Before the gate, not after the PR.__ 'humanGate' halts the workflow when you
-- decline, so anything downstream of it never runs on a no — and a change you
-- declined is precisely the run worth holding a retrospective on.
--
-- __A fanout, not a plain '>>>'.__ 'submitPR' quotes the value it receives as
-- \"work so far\", and handing that leaf a retrospective would describe the
-- session where it needs the change. So the worker's account flows on untouched
-- and the retro is appended under its own heading, which keeps it in the run's
-- final artifact without becoming the brief for the next leaf.
--
-- Top-level so the merge can be read at all. It changes no leaf's prompt and a
-- @dimap'@ renders in a plan skeleton as a node with no function in it, so a
-- flipped argument order here — the heading wrapped around the work instead of
-- around the retro — is invisible to every other instrument in this repository.
retrospective :: Flow Text Text
retrospective = keeping merge (dimap' asRetroSubject id retroFlow)
  where
    merge work r = work <> "\n\n## retrospective\n\n" <> r

-- | Run @f@, then combine the text that came IN with the text it produced.
--
-- @'dimap'' id merge ('fanout'' 'Id' f)@, named once because two stages want the
-- shape and want different joins: the retrospective appends under a heading, and
-- 'greenGate' keeps the remediation account above the check lines it adds. A
-- separator is a parameter rather than a second copy of the combinator.
--
-- The argument order is 'fanout'' 'Id' f\'s own — @merge incoming produced@.
-- Both are 'Text', so flipping them is not a type error and nothing in a plan
-- skeleton or a cost estimate moves; it would wrap the retrospective heading
-- around the work instead of around the retro. 'retrospective'\'s own test is
-- what reads the result and says which is which.
keeping :: (Text -> Text -> Text) -> Flow Text Text -> Flow Text Text
keeping merge f = dimap' id (uncurry merge) (fanout' Id f)

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
      Explore a documentation request, plan it, edit the plan for documentation
      strategy and plain English, then write under an orchestrator that re-runs
      the worker until it reports the plan finished; review the result with the
      five-lens documentation panel and remediate the findings
    |]
    actingGrant
    $ explorePlan
      >>> lensEdit [(name, brief body) | (name, body) <- docsPlanLenses]
      >>> steer "Review the plan — add any guidance before writing begins"
      >>> orchestrate document
      -- The docs lenses read an artifact; what reaches them is the worker's
      -- closing account. 'asDocsSubject' points them at the files instead.
      >>> dimap' asDocsSubject id reviewDocsFlow
      >>> remediate docsRule closeWithChanges

-- | The plan lenses 'shipDocs' edits through, and the whole of what it puts
-- between the planner and the steer. 'editPlan'\'s six have no purchase on a
-- prose plan, so this is a different chain rather than a narrowing of that one.
--
-- __Strategy first, then English.__ 'Incite.Review.docsStrategyOfPlan' splits
-- and cuts steps — who each document is for, which content type it is, which
-- document owns a fact — and 'simpleEnglishLens' rewords what survives. The
-- other order spends the rewrite on steps the strategy lens then deletes.
--
-- A named table rather than a list inlined into the workflow, because
-- @docs\/workflows.md@ says which lenses a documentation run edits through and
-- there is nothing else a test could read that against: a lens added to an
-- inline list changes no other name, count or skeleton the prose is checked on.
-- That drift is what the sentence \"it uses only the SimpleEnglish plan lens\"
-- was, after this chain grew its second entry.
docsPlanLenses :: [(LeafName, Prompt)]
docsPlanLenses =
  [ ("docs-strategy", docsStrategyOfPlan)
  , ("simple-english", simpleEnglishLens)
  ]

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
          #{wiggum}

          Write this documentation plan fully in the current repository — edit
          the documents directly.

          #{docsRule}
          #{steRules}

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
-- emit it and 'decideTrip' matches on it, and the two drifting apart would
-- strand the loop. Exported for the same reason — a second worker brief must
-- splice this and not its own spelling.
continueMarker :: Text
continueMarker = "WORK REMAINS"

-- | The pure marker predicate: 'Right' ends the loop, 'Left' keeps it going.
-- Continue only on the explicit marker — see 'decideTrip' for the budget that
-- backs it.
--
-- The match is the briefs' own contract — the marker alone on the last line —
-- not an infix scan of the whole summary: prose like "no work remains"
-- contains the marker and would otherwise ask for another trip every time.
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

-- | The trip-budgeted continuation decision 'orchestrate' loops on. 'Left'
-- hands the worker's summary back as the next trip's input; 'Right' ends the
-- loop and yields the summary to the stage after it.
--
-- 'Nothing' is no ceiling: the loop continues as long as 'decideContinue'\'s
-- marker is present and ends the moment it is not — the worker decides trip
-- count. @'Just' n@ caps it: once n trips are spent the last summary yields
-- rather than asking for a trip the budget does not have, so a large job still
-- reaches review instead of aborting with its edits stranded.
decideTrip :: Maybe Int -> Text -> Either (Maybe Int, Text) Text
decideTrip fuel out = case decideContinue out of
  Left _ -> case fuel of
    Nothing -> Left (Nothing, out)
    Just n
      | n > 1 -> Left (Just (n - 1), out)
      | otherwise -> Right out
  Right _ -> Right out

-- | Is this check log a __failing__ one? True exactly when some line, ANSI
-- stripped and whitespace stripped, opens with the marker
-- @Agent.Flow.Combinators.execStep@ writes for a non-zero exit.
--
-- __The marker is read off that emitter, not guessed.__ @decodeOutcome@ emits
-- @\"✗ \" <> name <> \" (exit N)\"@ and @execStep@ prepends a newline, so the
-- marker opens a line. The ANSI strip is defensive rather than necessary — the
-- value threaded through a 'Flow' is that plain 'Text' and colour belongs to a
-- renderer — and it costs one pass over a log nobody else reads.
--
-- __Line starts, not an infix scan.__ The gate's own report says what a @✗@
-- line means, and a synthesis leaf quotes check output; an @isInfixOf@ here
-- would read prose about a failure as a failure and spin the loop until the
-- fuel aborts the run. Same reasoning as 'decideContinue', same failure.
--
-- It is a monoid homomorphism from log concatenation into @Any@ —
-- @isRed mempty = False@ and @isRed (a <> b) = isRed a || isRed b@ at a line
-- boundary — which is exactly why 'greenGate' feeds its loop @mempty@: 'verify'
-- APPENDS to the log it receives, so a stale marker from an earlier trip would
-- otherwise poison every verdict after it.
isRed :: Text -> Bool
isRed = any (T.isPrefixOf failureMarker . T.strip . stripAnsi) . T.lines
  where
    failureMarker = "✗ "

-- | Drop ANSI SGR sequences. @\\ESC[…m@ and nothing else, because nothing else
-- appears on this path and a general terminal-escape parser here would be a
-- parser nobody needs.
stripAnsi :: Text -> Text
stripAnsi t = case T.breakOn "\ESC[" t of
  (before, "") -> before
  (before, rest) -> before <> stripAnsi (T.drop 1 (T.dropWhile (/= 'm') rest))

-- | 'Left' keeps the repair loop going, 'Right' ends it — the mirror of
-- 'decideContinue', and the opposite polarity for the opposite reason. A worker
-- asks to continue; a tree is asked whether it still fails.
decideRed :: Text -> Either Text Text
decideRed t = if isRed t then Left t else Right t

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

-- | The ceiling on how many times a worker may hand itself back its own summary.
-- 'Nothing' — the default — is no ceiling: the worker runs until it reports
-- WORK COMPLETE. @'Just' n@ caps it at n trips, after which the last summary
-- yields to the next stage rather than aborting.
workerFuel :: Maybe Int
workerFuel = Nothing

-- | The checks the grind gate runs __itself__, as argv rather than as a shell
-- string: the target tree's own build and its own test harness.
--
-- These are the Paradox project's commands, not this repository's. That is the
-- whole point of the gate — @grind-paradox@ is pointed at another checkout, and
-- what makes its verdict worth anything is that agent-functor runs these and
-- reads the exit code, rather than an agent reporting that it did.
--
-- 'NonEmpty' because a check with no command is not a check, and because
-- 'grindGrant' takes each one's head. A total head is the difference between a
-- grant derived from this list and a grant that agrees with it today.
grindChecks :: [(LeafName, NonEmpty Text)]
grindChecks =
  [ ("build", grindCheckCmd "cabal build")
  , ("tests", grindCheckCmd "export paradox_datadir=$PWD/lib; cabal test")
  ]

-- | What a grind check's argv MEANS, decided once for every grind: the command,
-- run inside the __target project's own dev shell__, with @bash -c@ innermost
-- so metacharacters and exports survive the wrapper.
--
-- __This is not ceremony, and a rehearsal is what proved it.__ 'execStep' runs
-- argv directly: no shell, no profile, no @nix develop@. Paradox's @test.sh@
-- ends by executing
-- @dist-newstyle\/build\/…\/ghc-$GHC_VER\/paradox-$PARADOX_VER\/…@, and those
-- two variables are set by its dev shell and by nothing else. Run bare, the
-- path collapses to @ghc-\/paradox-\/@, the script exits non-zero, and it does
-- so on a tree in perfect health.
--
-- The gate would then be red on every run, for a reason no repair leaf could
-- fix — it would spend 'repairFuel' trips looking for a defect in the code and
-- then abort. A permanently red gate is worse than none: it teaches a reader
-- that the gate means nothing.
--
-- The Elixir checks ('grindTestsChecks') make the same bet on the same
-- evidence: the driver they retire gated on @nix develop -c mix compile@, so
-- that project too keeps its toolchain in a dev shell. Only a dry run in the
-- target checkout can prove the wrapper — execute every rendered argv verbatim
-- there before the first paid run, and reopen this choice if a check dies
-- environment-shaped (@command not found@, a missing env var, a nix eval
-- error) rather than on its own content.
--
-- @nix@ as every check's head also lines each derived grant ('grindGrantFor')
-- up with 'actingGrant'\'s @nix*@, which is the same bargain the other acting
-- workflows already make: we run nothing ourselves that the project cannot
-- reproduce.
--
-- __And @cabal test@ rather than the project's @test.sh@.__ That script takes
-- ONE suite name, and the name every document about this project reaches for —
-- @lib-tests@ — is not a suite it has. The real ones are @parse-tests@,
-- @codegen-tests@, @eval-tests@, @strap-tests@, @lsp-tests@, @atlas-tests@,
-- @repl-tests@, @json-roundtrip-tests@ and @state-tests@; asking cabal for the
-- package's tests gets all nine without this file keeping a tenth copy of that
-- list. @paradox_datadir@ is the one thing @test.sh@ exports that the suites
-- genuinely need, so it is exported here too.
grindCheckCmd :: Text -> NonEmpty Text
grindCheckCmd cmd = "nix" :| ["develop", "--command", "bash", "-c", cmd]

-- | The exec policy a grind derives from its own check list, rather than
-- writing beside it.
--
-- A grant and a check list are two statements of one fact, and the failure when
-- they drift is silent in the direction that matters: an ungranted check is
-- denied inside the run, the gate never sees a real exit code, and the artifact
-- still reads like a gate ran. Deriving it means the check list is the only
-- place either can change.
--
-- __It permits by head-glob__ — @'NE.head' cmd <> \"*\"@ per check — never by
-- rendered check line. The stricter reading would deny the very argv the gate
-- runs (the fences in @test\/Spec.hs@ run 'Agent.Grant.permitExec' over each
-- whole rendered line, and a line is not its own head), and a grant that
-- denies its own gate invites editing the fence to match wrong prose.
--
-- A head-glob is wide on purpose: with 'grindCheckCmd' every head is @nix@, so
-- the derived @nix*@ admits any dev-shell command, not only the checks. That
-- is 'actingGrant'\'s own @nix*@ bargain, and @docs\/workflows.md@ documents
-- the layering: a grant gates the 'Agent.Op.Exec' leaves the harness runs
-- itself, and the agent's tools stand under the backend's own permissioning.
--
-- @date@ and @mkdir@ are the synthesis leaf's, not a check's — it reads the day
-- and creates @docs\/audits\/@ before writing the report. They are named here
-- because this is a grind's whole exec policy, and a leaf whose write
-- fails still returns the full ranked report, so the run would report success
-- with no file on disk.
grindGrantFor :: [(LeafName, NonEmpty Text)] -> Grant
grindGrantFor checks =
  execGrant ([NE.head cmd <> "*" | (_, cmd) <- checks] <> ["date*", "mkdir*"])

-- | 'grindGrantFor' at 'grindChecks': the exec policy 'grindParadox' runs
-- under, and the specialization the derivation is pinned by — the grant fences
-- in @test\/Spec.hs@ read this binding through the runtime's own matcher.
grindGrant :: Grant
grindGrant = grindGrantFor grindChecks

-- | What a grind fixer stands under: the code rule, plus the tree's own facts
-- and repair disciplines.
--
-- The facts reach the audit half through the workflow's input reframing, which
-- is out of scope by the time the fixer runs — a stage in a chain sees the
-- previous leaf's output, and that is a ranked list of findings. Splicing them
-- into the rule is how the fixer learns that a golden is regenerated and never
-- hand-edited, which is the discipline a red gate is cheapest to defeat by
-- breaking.
--
-- __One derivation, because audit facts and repair facts are one fact.__
-- 'grindFlow' builds its own fixer's rule from 'gsFacts' through this, and the
-- named rules ('paradoxRule', 'grindTestsRule') are the same application —
-- kept as bindings because a grind's second fixer and its 'greenGate' consume
-- them outside 'grindFlow'. Two spellings of the splice would drift silently,
-- one grind at a time. 'stackRule' is the same splice outside any grind —
-- what it splices is disciplines rather than tree facts, and the shared shape
-- is the point of it being one binding.
grindRule :: Prompt -> Prompt
grindRule facts =
  [__i|
    #{codeRule}

    #{facts}
  |]

-- | 'grindRule' at 'Incite.Prompts.paradoxFacts': what 'grindParadox'\'s fixer
-- and its gate's repair leaf stand under.
paradoxRule :: Prompt
paradoxRule = grindRule paradoxFacts

-- | Run @worker@ under the orchestrator every acting workflow uses: each trip
-- is one worker turn taking the previous trip's own summary as its input, and
-- the loop ends the moment that summary does not ask to continue.
--
-- __'loopUntil', not a fixed unroll.__ Trip count is runtime and the worker
-- decides it. 'workerFuel' is the ceiling ('Nothing' = no ceiling), not the
-- plan — a job finished on trip two costs two turns.
--
-- __Yields on exhaustion, never aborts.__ 'loopUntil' aborts on exhaustion by
-- upstream design, and for an acting loop that is the wrong policy: a worker
-- or fixer that needs more than its ceiling has still edited the tree on every
-- trip it took, and an abort there strands every one of those edits — the
-- review panel never sees them in 'shipFeature'\/'shipDocs', and the gate
-- never runs in 'grindParadox'. So when 'workerFuel' is @'Just' n@ the loop
-- threads a trip budget ('decideTrip') that yields the last summary at trip n,
-- and whatever stage follows reads what landed. When 'workerFuel' is 'Nothing'
-- there is no budget — the loop runs until the worker reports WORK COMPLETE.
--
-- The 'loopUntil' fuel mirrors 'workerFuel': @'maxBound' \`div\` 2@ when
-- 'Nothing' — practically infinite, and the largest value that keeps
-- 'Agent.Cost.worstCaseCost' arithmetic from overflowing — and n when
-- @'Just' n@.
--
-- @second''@ carries the budget alongside the summary so the worker itself only
-- ever sees its own text — the briefs' \"your own summary as input\" contract
-- is unchanged, and the accounting is plumbing beside it, not inside it.
orchestrate :: Flow Text Text -> Flow Text Text
orchestrate = orchestrateWith workerFuel

-- | 'orchestrate' with the ceiling as an argument, and the binding 'orchestrate'
-- is defined by — so a capped loop cannot drift from the default one in shape,
-- in what the worker sees, or in what exhaustion does.
--
-- __A parameter because a workflow's fuel is a property of the workflow.__
-- 'workerFuel' is 'Nothing' for the two that finish when their worker says so.
-- 'stackFuel' is finite for the one that runs four of these loops in one chain:
-- @Agent.Cost.worstCaseCost@ sums a sequence and multiplies through a loop, and
-- four unbounded loops in a row sum past 'maxBound' and report a NEGATIVE worst
-- case. A cost estimate that goes backwards is worse than a large one, because
-- it is the number an operator reads before deciding to spend anything.
orchestrateWith :: Maybe Int -> Flow Text Text -> Flow Text Text
orchestrateWith fuel worker =
  dimap' (\summary -> (fuel, summary)) id
    ( loopUntil (maybe (maxBound `div` 2) id fuel)
        ( second'' worker >>> dimap' id (uncurry decideTrip) Id )
    )

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
  | -- | The branches of a Graphite stack, each read against its own parent.
    -- 'stackPRs'\'s review stage.
    AtStack
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
--
-- 'AtChange'\'s @docs\/audits\/@ exclusion is deliberately categorical across
-- every consumer of the orientation: it names only the dated reports a run
-- writes for itself, and one preamble per orientation is the trade this type
-- makes against per-call-site ignored-path parameters.
preambleOf :: Orientation -> Text
preambleOf o = case o of
  AtChange ->
    [i|Review the change in the current working directory. Run `git diff`, `git diff --cached` and `git status` and read the result before reporting anything. A dated report under `docs/audits/` is this run's own artifact, not part of the change: leave it out of the review, and leave it out of the no-change decision — a tree whose only edit is that report has no change to audit. If all three show no change — nothing modified, nothing staged, nothing untracked — say `no change to audit` and stop: an empty diff is a fact to report, never a licence to review the account below in its place. The worker's own account of what it did follows — treat it as a claim to check, not as the change itself.|]
  AtRecord ->
    [i|Hold the retrospective on the work in the current working directory, not on a conversation: this run's record is what you have, and there is no transcript of the session.

So take your evidence from the record. Run `git log --oneline`, `git diff` and `git status`, and read them. The account below is the closing summary of the review-and-remediation stage — what the panel raised and what was done about it — and it is a claim to check against the commits, not the session itself.

Where a column asks you to quote, quote the record: a commit message, a finding, a line of the summary. Where the evidence for an entry is not in the record, say the record cannot show it and drop the entry — do not reconstruct the dialogue that would have produced it.|]
  AtDocs ->
    [i|Review the documentation in the current working directory. The documents are the artifact under review and the code is the record they answer to, so read both: `git ls-files --cached --others --exclude-standard '*.md'` for what there is to read, and the modules, workflows and flake each document describes.

Read the documents themselves before reporting anything. An account of them follows and it is a claim to check, not a substitute for the files — where it and a document disagree, the document is what ships.

Cite the document and the code on both sides of every finding. A statement about prose that you cannot point at a file and a line for is a preference, and a preference is not a finding here.|]
  AtStack ->
    [i|Review the stack of branches in the current working directory, one branch at a time. `.stack-branches` lists them bottom first, and a branch's own change is `git diff <parent>...<branch>` where the parent is the line above it in that file — never a diff against the trunk, which shows you every branch below it as well.

Read the branches before reporting anything, and name the branch in every finding. A finding belongs to the branch that INTRODUCED the code, never to the top of the stack: a fix applied at the top is a merge conflict later.

Two things are findings here that are not findings in a single diff, and one thing is not.

* A branch that does not build on its own is a defect even when the whole stack builds, because each branch is reviewed and merged alone.
* A branch a reviewer cannot judge without reading the rest of the stack is a defect, whatever its size.
* Code that nothing calls yet is CORRECT here. Read `.stack-plan.md` first: where it names the later branch that calls the code, say nothing. Report the plan, not the code, where it names none.

The account below is the closing summary of the stage that built the stack. It is a claim to check against the branches, not the branches themselves.|]

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

-- | 'orient' at 'AtStack', for 'stackPRs'\'s review stage.
--
-- __One panel over the whole stack, not one panel per branch.__ A branch count
-- is a runtime fact and @panelAcross@ is a static cross-product, so a panel per
-- branch would need a fan-out over a number nothing knows when the 'Flow' is
-- built — the same bound "Incite.Review".@spread@ exists to avoid, and the
-- reason @grind-paradox@ audits a whole tree with one panel rather than one per
-- module. What the preamble buys instead is attribution: the lenses read the
-- branches one at a time and every finding names the branch that introduced the
-- code, which is the branch a fix has to land on.
asStackSubject :: Text -> Text
asStackSubject = orient AtStack

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
remediate :: Prompt -> Prompt -> Flow Text Text
remediate artifactRule closing = refineWith "remediate" (brief body) id
  where
    findings =
      [__i|
        #{ponytailLadder}

        #{fixAll}

        #{artifactRule}

        The ranked review findings follow. Fix every one of them in this
        repository, in the shortest change that fixes it. Where you judge
        a finding wrong, say so and why rather than silently skipping it:
      |]
    -- An own branch for the empty clause, rather than splicing @mempty@ into a
    -- template. The findings block ends in a colon, and 'brief' adds the blank
    -- line before the artifact, so an unconditional @"\\n\\n" <> closing@ would
    -- leave two blank lines and a colon pointing at nothing whenever the clause
    -- is absent. That is byte drift in a prompt, which no check outside this
    -- module's own pin can see — and \"conservative\" would then be true only
    -- because the pin had been re-recorded.
    body
      | T.null (T.strip (promptText closing)) = findings
      | otherwise =
          [__i|
            #{findings}

            #{closing}
          |]

-- | The closing clause a fixer running __once__ stands under: 'shipFeature'\'s
-- and 'shipDocs'\'s. There is no next trip, so there is no marker to emit and
-- nothing to hand a successor — only the account.
closeWithChanges :: Prompt
closeWithChanges =
  [__i|
    Close with what you changed and what you rejected, in one paragraph. This
    leaf runs once and nothing calls it again, so a finding you leave open
    leaves the run with it open.
  |]

-- | The closing clause a fixer running under 'orchestrate' stands under: the
-- same continuation contract the worker briefs carry, pointed at findings
-- instead of at a plan.
--
-- __Splices 'continueMarker' rather than spelling it__, for the reason
-- 'document' does: the brief tells the fixer how to ask for another trip and
-- 'decideContinue' decides whether it asked, and the two agree only because
-- both go through that binding. Spelled out here, a rename would strand the
-- loop for its whole fuel with nothing in any output naming the cause.
fixerContinuation :: Prompt
fixerContinuation =
  [__i|
    You are running under an orchestrator that will call you again with your own
    summary as its input, so write the summary for your successor: which
    findings you closed, which you rejected and why, and which are left.

    End with a status line, alone on the last line:

    - `#{continueMarker}` — findings are still open. You will be called again.
    - `WORK COMPLETE` — every finding is fixed or answered; say what changed.
  |]

-- | Audit a whole source tree with fourteen lenses, rank what they found, fix
-- every finding, and then prove the tree still builds and its tests still pass
-- — with our own exec, reading real exit codes.
--
-- __The subject is another checkout.__ Every path, build command and repair
-- discipline lives in 'Incite.Prompts.paradoxFacts', prepended to whatever the
-- caller passes — 'grindFlow' owns the prepend and says why it is a prepend.
--
-- __One backend per lens, not every backend on every lens.__ 'Incite.Review.spread'
-- buys coverage where 'Incite.Review.panel' buys confidence: 14 leaves against
-- 42. A tier that reads a whole tree cannot afford the second, and three models
-- agreeing about a tree nobody changed is worth less than three more questions
-- asked of it.
--
-- __Sequential orchestrated remediation, deliberately__, and it replaces a
-- file-disjoint parallel wave scheduler with per-fix adversarial verifiers.
-- Parallel agents editing one checkout is the conflict that scheduler existed
-- to dodge, worker-worktree leaves can report fixes that never merge, and
-- dynamic fan-out over a runtime finding count needs a static bound — which
-- either drops findings or stops the run after the audit spend. The fuelled
-- loop is slower on a large finding set, and honest about what it closed.
--
-- The gate's 'Agent.Op.Exec' leaves make @hasWorldActing@ true, so @--sandbox@
-- engages when asked for. The product of a real run is a dirty tree, so the
-- command that drives it passes @sandbox=false@ on purpose.
grindParadox :: Workflow
grindParadox =
  workflowG
    grindName
    [iii|
      Audit a whole source tree with fourteen lenses spread one per backend
      (correctness, tests, stubs, vacuous tests, repetition, hardcodings,
      refactors, architecture, performance, ponytail cuts, and four that only a
      code generator admits), write a dated ranked report, fix every finding
      under an orchestrated fixer, then gate on a real build and test suite
    |]
    [iii|
      Audit the whole source tree in the current working directory. No focus:
      read what the lenses point you at.
    |]
    grindGrant
    $ grindFlow
      GrindSpec
        { gsName = grindName
        , gsFacts = paradoxFacts
        , gsLenses = lensesOf OfTree <> emissionLenses
        , gsSynthesisSuffix = mempty
        }
      >>> greenGate paradoxRule grindChecks

-- | Everything one grind supplies for itself, by name. A record with one
-- constructor rather than positional arguments, because the positional form
-- read @facts@, @synthesis@ and @rule@ as three bare 'Prompt's — a caller
-- swapping any two type-checks, and the defect surfaces as a fixer standing
-- under the synthesis brief.
data GrindSpec = GrindSpec
  { gsName :: Text
  -- ^ The grind's slug ('Incite.Review.grindName' and kin): the tool's name,
  -- and the dated report path the derived synthesis writes under.
  , gsFacts :: Prompt
  -- ^ The target tree's facts file. 'grindFlow' prepends it to the caller's
  -- steer and splices it into the fixer's rule ('grindRule') — one field,
  -- so the audit half and the repair half cannot read different facts.
  , gsLenses :: [(LeafName, Prompt)]
  -- ^ The lens table handed to 'Incite.Review.spread', whose ORDER is
  -- semantic — 'spread' pairs backends positionally. The synthesis roster is
  -- derived from this same table, so a lens the panel runs is a lens the
  -- synthesis can refuse on.
  , gsSynthesisSuffix :: Prompt
  -- ^ Appended below the derived synthesis brief; 'mempty' for a grind with
  -- nothing to add. The seam exists so a grind can EXTEND the shared brief —
  -- a ranking clause, say — without replacing the derived roster, which is
  -- what keeps a short panel refusable in every grind.
  }

-- | The shared grind prefix: the tree's facts prepended to the caller's steer,
-- a 'spread' panel over the lenses, one synthesis, then an orchestrated fixer
-- under the artifact rule. Every grind is this flow plus whatever it gates on —
-- one binding, so a second grind cannot drift from 'grindParadox' in the shape
-- they share.
--
-- The facts arrive as a __pure prepend, not as @workflowG@\'s default input__,
-- because a caller's @input@ REPLACES that default — which would drop the facts
-- the moment somebody steered the run — and rather than a wrap per lens,
-- because one 'dimap'' covers every leaf of the panel and leaves the caller's
-- text as a genuine focus steer.
--
-- __The synthesis brief and the fixer's rule are derived, not passed.__
-- 'Incite.Review.grindSynthesisOver' over the spec's own name and lens table,
-- and 'grindRule' over the spec's own facts — so no grind can hand the
-- synthesis a roster its panel does not run (a backend outage would fold into
-- that as a clean tree), and no grind can audit under one set of facts and
-- repair under another. The unchanged 'grindParadox' fences in @test\/Spec.hs@
-- and the render recorded at the hoist are what pin this binding to the shape
-- that workflow always had.
grindFlow :: GrindSpec -> Flow Text Text
grindFlow GrindSpec {..} =
  dimap' withFacts id (spread backends gsLenses)
    >>> refineWith "synthesis" (brief synthesis) id
    >>> orchestrate (remediate (grindRule gsFacts) fixerContinuation)
  where
    base = grindSynthesisOver gsName (map fst gsLenses)
    -- An own branch for the empty clause, for 'remediate'\'s reason: the seam
    -- is exactly one blank line, so the suffix lands as the brief's final
    -- paragraph rather than fusing onto its closing sentence — and a grind
    -- with nothing to add leaves the derived brief byte-identical, with no
    -- trailing separator that no other check could see.
    synthesis
      | T.null (T.strip (promptText gsSynthesisSuffix)) = base
      | otherwise =
          [__i|
            #{base}

            #{gsSynthesisSuffix}
          |]
    withFacts steerText = promptText gsFacts <> "\n\n" <> steerText

-- | The checks the test-suite grind gates on: the target project's own compile
-- (warnings as errors), its Elixir suite, and its TypeScript suite — each
-- through 'grindCheckCmd', run by us with the exit code read.
grindTestsChecks :: [(LeafName, NonEmpty Text)]
grindTestsChecks =
  [ ("compile", grindCheckCmd "mix compile --warnings-as-errors")
  , ("tests", grindCheckCmd "mix test")
  , ("vitest", grindCheckCmd "cd assets && npx vitest run")
  ]

-- | 'grindGrantFor' at 'grindTestsChecks', for 'grindGrant'\'s reason: the
-- check list is the only place either statement of the policy can change.
grindTestsGrant :: Grant
grindTestsGrant = grindGrantFor grindTestsChecks

-- | 'grindRule' at 'Incite.Prompts.testsFacts': what the test-suite grind's
-- fixers stand under — the one inside 'grindFlow', the second one acting on
-- the review panel's findings, and the gate's repair leaf. Splicing the facts
-- is how a fixer learns the fix hierarchy (source-of-truth first, proof layer
-- second, direct code last) that a red gate is cheapest to defeat by ignoring.
grindTestsRule :: Prompt
grindTestsRule = grindRule testsFacts

-- | Audit a test suite with twelve lenses, rank and fix what they found, audit
-- the FIX with the exhaustive review panel, fix what that found, then prove
-- the suites still pass with our own exec.
--
-- 'grindParadox'\'s shape over 'grindFlow', plus the one segment that workflow
-- does not run: a full 'Incite.Review.reviewAuditFlow' pass over the fixer's
-- change, reframed through 'asReviewSubject', with a second orchestrated fixer
-- acting on what the panel raised. A test-suite remediation is the change most
-- worth that price — its cheapest failure mode is a fix that weakens what a
-- test asserts, which is invisible to a green gate and exactly what a review
-- panel reads diffs for. 'asReviewSubject'\'s own no-change clause is what
-- keeps the pass honest when the fixer touched nothing: the panel reports
-- @no change to audit@ rather than reviewing the account as though it were a
-- diff.
grindTests :: Workflow
grindTests =
  workflowG
    grindTestsName
    [iii|
      Audit a test suite with twelve lenses spread one per backend (vacuous
      tests, coverage gaps, missing property tests, survived mutations, stubs
      and skips, sleeps and magic timeouts, hand-written copies of generated
      code, testability reshapes, repetition, machine-checked-proof candidates,
      fragile browser selectors, async and isolation debt), write a dated
      ranked report, fix every finding under an orchestrated fixer, audit the
      fix with the exhaustive review panel and remediate what it finds, then
      gate on the project's real compile and test suites
    |]
    [iii|
      Audit the test suite in the current working directory. No focus: read
      what the lenses point you at.
    |]
    grindTestsGrant
    $ grindFlow
      GrindSpec
        { gsName = grindTestsName
        , gsFacts = testsFacts
        , gsLenses = grindTestsLenses
        , gsSynthesisSuffix = mempty
        }
      >>> dimap' asReviewSubject id reviewAuditFlow
      >>> orchestrateWith grindTestsReviewFuel (remediate grindTestsRule fixerContinuation)
      >>> greenGate grindTestsRule grindTestsChecks

-- | The ceiling on @grind-tests@'s second fixer — the one acting on the
-- review panel's findings. Finite for 'stackFuel'\'s cost reason: this
-- workflow already runs one unbounded fixer loop inside 'grindFlow', and
-- @worstCaseCost@ sums a sequence, so a second unbounded loop pushed the sum
-- past 'maxBound' and @cost grind-tests@ reported a NEGATIVE worst case — the
-- number an operator reads before spending anything, going backwards.
--
-- And finite is right on its own terms: the first fixer faces a whole
-- suite's findings and the worker decides its trips, but this one faces the
-- review of ONE change — a finding set that outlives twelve trips wants a
-- person reading the panel's report, not a thirteenth trip. Exhaustion
-- yields ('orchestrateWith'), so the gate still runs over whatever landed.
grindTestsReviewFuel :: Maybe Int
grindTestsReviewFuel = Just 12

-- | The checks the LiveView grind gates on: the target project's own compile
-- (warnings as errors) and its test suite, each through 'grindCheckCmd', run
-- by us with the exit code read. No TypeScript check, and that is a gap for a
-- grind whose @ts-hooks@ lens writes hook code: the retired gate had none, and
-- a command unverifiable without the target checkout risks the permanently-red
-- gate 'grindCheckCmd'\'s haddock names — the owed dry run (see @HANDOFF.md@)
-- is where a third row (vitest or tsc) earns its place.
grindLiveViewChecks :: [(LeafName, NonEmpty Text)]
grindLiveViewChecks =
  [ ("compile", grindCheckCmd "mix compile --warnings-as-errors")
  , ("tests", grindCheckCmd "mix test")
  ]

-- | 'grindGrantFor' at 'grindLiveViewChecks', for 'grindGrant'\'s reason.
grindLiveViewGrant :: Grant
grindLiveViewGrant = grindGrantFor grindLiveViewChecks

-- | 'grindRule' at 'Incite.Prompts.liveViewFacts': what the LiveView grind's
-- fixer and its gate's repair leaf stand under. Splicing the facts is how a
-- fixer learns the registration convention a half-landed hook silently
-- breaks.
grindLiveViewRule :: Prompt
grindLiveViewRule = grindRule liveViewFacts

-- | The one thing the LiveView grind adds to the derived synthesis brief, and
-- the reason 'GrindSpec' has a suffix seam at all.
--
-- __It rides on the severity words 'Incite.Prompts.liveViewAuth' demands.__
-- That lens opens every finding with @critical@, @high@ or @medium@; this
-- clause matches on those words to hold every authorization finding above
-- every performance and UX finding, whatever the consequence ranking says.
-- The coupling is fenced in @test\/Spec.hs@ — drop the words from either side
-- and the case goes red, because an auth finding that sinks below UX noise is
-- exactly the silent failure the clause exists to prevent.
grindLiveViewRanking :: Prompt
grindLiveViewRanking =
  [__i|
    ONE RANKING RULE on top of the ranking above: every authorization finding
    ranks above every performance and UX finding, whatever their consequences
    score. The auth lens opens each of its findings with a severity word —
    `critical`, `high` or `medium` — keep that word on the finding's line, and
    order the authorization findings by it among themselves.
  |]

-- | Everything the LiveView grind supplies for itself, named at the top level
-- so the fences in @test\/Spec.hs@ read the shipped spec rather than a copy:
-- the suffix really is 'grindLiveViewRanking', over the same lens table the
-- panel runs.
grindLiveViewSpec :: GrindSpec
grindLiveViewSpec =
  GrindSpec
    { gsName = grindLiveViewName
    , gsFacts = liveViewFacts
    , gsLenses = grindLiveViewLenses
    , gsSynthesisSuffix = grindLiveViewRanking
    }

-- | Audit a LiveView layer with eleven lenses, rank what they found with
-- authorization on top, fix every finding, and prove the tree still compiles
-- and its tests still pass — 'grindParadox'\'s shape at a different subject,
-- plus the ranking clause riding in through the spec's suffix seam.
--
-- No review-audit segment: 'grindTests' pays that price because a test-suite
-- remediation's cheapest failure is a weakened assertion, and this grind's
-- edits stand under the same compile and test gate that catches a LiveView
-- regression the cheap way.
grindLiveView :: Workflow
grindLiveView =
  workflowG
    grindLiveViewName
    [iii|
      Audit a Phoenix LiveView layer with eleven lenses spread one per backend
      (component CSS hardening, componentization, liveness gaps, needless
      re-renders, spammy PubSub, framework best practices, per-event
      authorization, page load cost, DOM keying, assign bloat, client-hook
      round trips), write a dated ranked report with authorization findings
      above every performance and UX finding, fix every finding under an
      orchestrated fixer, then gate on the project's real compile and tests
    |]
    [iii|
      Audit the LiveView layer in the current working directory. No focus:
      read what the lenses point you at.
    |]
    grindLiveViewGrant
    $ grindFlow grindLiveViewSpec
      >>> greenGate grindLiveViewRule grindLiveViewChecks

-- | Run @checks@ __ourselves__ until they pass, doing @repair@ between trips,
-- and keep the account that came in under a @## heading@ of its own.
--
-- Two gates are built from this and they differ in exactly one argument, which
-- is the whole reason it is a binding: 'greenGate' repairs a red tree with a
-- leaf, and 'budgetGate' has nothing to repair and passes 'Id'
-- (@'left'' 'Id' = 'Id'@, so that loop carries no extra node at all). Everything
-- else below is subtle enough that a second copy of it would be a second place
-- to get it wrong.
--
-- __The account survives the gate.__ What reaches this stage is the previous
-- leaf's own summary, and it is the most useful thing in the run's final
-- artifact. 'keeping' puts it above the check lines rather than letting 'verify'
-- overwrite it with a log.
--
-- __The @const mempty@ is the unit the homomorphism demands, not a scrubber
-- bolted on.__ @Agent.Flow.Combinators.execStep@ APPENDS its status line to the
-- log it receives, and 'isRed' is a monoid homomorphism into @Any@ — so a @✗@
-- from trip one is still in the text trip two produces, every later verdict is
-- red, and the loop burns its fuel and aborts a run whose tree went green on
-- trip two. Feeding each trip the empty log is what makes the verdict a
-- statement about THIS trip.
--
-- __Exhaustion aborts, by upstream design.__ 'loopUntil' offers no
-- yield-what-you-have policy (at its type the loop holds only an @a@ and must
-- produce a @b@), so a tree still red after the fuel runs out fails the run
-- rather than falling through into 'keeping' and reporting success over a
-- failing check. That is the behaviour both gates want — see 'orchestrate',
-- which points the same default the other way on purpose.
checkLoop :: Text -> Int -> Flow Text Text -> [(LeafName, NonEmpty Text)] -> Flow Text Text
checkLoop heading fuel repair checks = keeping accountThenLog gateLoop
  where
    accountThenLog account gateLog = account <> "\n\n## " <> heading <> "\n" <> gateLog
    gateLoop =
      loopUntil
        fuel
        ( dimap' (const mempty) id (verify [(n, NE.toList cmd) | (n, cmd) <- checks])
            >>> dimap' id decideRed Id
            >>> left'' repair
        )

-- | The ceiling on how many times the gate may hand a still-red tree to a
-- repair leaf. Fuel, not a schedule — a finite 'Int' where 'workerFuel' is a
-- 'Maybe', and much smaller: a failing check after three repairs is an
-- integration problem a person should look at, not one more turn.
repairFuel :: Int
repairFuel = 3

-- | 'checkLoop' with the leaf that acts on a red gate: run @checks@ ourselves
-- until they pass, repairing between trips.
greenGate :: Prompt -> [(LeafName, NonEmpty Text)] -> Flow Text Text
greenGate artifactRule = checkLoop "gate" repairFuel (repairLeaf artifactRule)

-- | The one leaf that acts on a red gate. Under the artifact rule, because the
-- cheapest way to turn a failing check green is to weaken the assertion that
-- fails — and that move satisfies the gate, passes everything downstream of it
-- (there is nothing), and is exactly what the disciplines spliced into the rule
-- forbid.
repairLeaf :: Prompt -> Flow Text Text
repairLeaf artifactRule =
  refineWith
    "repair"
    ( brief
        [__i|
          #{artifactRule}

          The checks below were run by the harness, not by an agent, and the
          exit codes are real. Fix every failing one.

          Three rules, and they are the whole point of a gate:

          - Never weaken an assertion, delete a test, or narrow a filter to
            make a check pass. A check that fails is telling you something.
          - Never hand-edit recorded output. Fix what generates it, then
            regenerate, then read the diff.
          - Where two individually-correct fixes conflict, repair the
            conflict rather than reverting either one, and say which two.

          The check log follows:
        |]
    )
    id

-- | Cut one large diff into a Graphite stack of reviewable branches, prove every
-- branch builds with a real exit code, review the stack, submit it as drafts,
-- triage what the review bot says, and promote it bottom-first under a CI budget
-- that yields to anybody else.
--
-- __The third acting shape, and it shares the analysis half by name.__
-- 'shipFeature' turns a request into a change, @grind-paradox@ turns a tree into
-- a repaired tree, and this turns one change into an ordered sequence of them.
-- It reuses 'explorePlan', 'orchestrate', 'remediate', 'greenGate' and
-- 'reviewHeavyFlow' rather than copying any of them, so it cannot drift from the
-- other two in anything they share.
--
-- __Two gates run our own exec, and that is the whole reason this is a 'Flow'
-- rather than one long brief.__ 'stackChecks' proves a stack builds and
-- 'budgetCheck' decides whether a promotion may happen at all — both through
-- @Agent.Flow.Combinators.verify@, so the exit codes are real. An agent asked to
-- run @ci-budget.sh@ before each promotion is an agent that reports having run
-- it; a 'budgetGate' in front of every trip of the promotion loop is a fact
-- about the run. The gate that yields to a colleague's queued job is exactly the
-- one worth taking out of an agent's hands.
--
-- __Where each gate sits is an argument, not an arrangement.__ The first
-- 'greenGate' stands between the slicing loop and the panel, because 21
-- reviewers reading branches that do not build is the most expensive way to
-- learn they do not build. The second stands between the review rounds and
-- promotion, because that is the last moment a local failure is still cheap: a
-- branch that fails locally is guaranteed to fail CI, so promoting it spends a
-- shared slot on a known answer.
--
-- __And a local pass is still not a prediction.__ CI runs checks no local gate
-- can, which is why the promotion stage treats its first branch as a
-- measurement rather than a formality. Nothing in this workflow calls a branch
-- green on the strength of 'stackChecks' alone.
--
-- __It promotes, and it never merges.__ Promotion is where the run spends
-- somebody else's CI, so it sits behind a 'humanGate' as well as behind the
-- budget — but be exact about which of the two protects an unattended run.
-- @Agent.Run@ auto-answers every 'Agent.Op.Ask' with @gateAnswer@, which
-- defaults to @"yes"@, so on the MCP path and on any headless run the gate
-- approves itself. The gate is real for an operator at a terminal and is
-- decoration without one. 'budgetGate' is the protection that holds either way,
-- because it is an 'Agent.Op.Exec' leaf reading a real exit code rather than a
-- question somebody has to be present to answer. Merging is refused outright: 'stackDisciplines' forbids it at every
-- acting leaf, because a merged stack destroys the review opportunity the whole
-- run exists to create.
stackPRs :: Workflow
stackPRs =
  workflowGReq
    "stack-prs"
    [iii|
      Cut one large diff into a Graphite stack of roughly 500-line branches on
      compile-time dependency boundaries, write the plan and its three scripts to
      disk, prove every branch builds with a real exit code, review the stack
      with the full panel, submit it as drafts, triage the review bot's findings,
      and promote it bottom-first under a CI budget that yields to anybody else
    |]
    stackGrant
    $ dimap' withStackFacts id explorePlan
      >>> lensEdit [(name, brief body) | (name, body) <- stackPlanLenses]
      >>> steer "Review the slice plan — every branch, what it holds, and what it defers"
      >>> humanGate "Build the stack from this plan?"
      >>> stackWorker "bootstrap" stackTooling mempty
      >>> orchestrateWith stackFuel (stackWorker "cut" stackSlice stackContinuation)
      >>> stackGate
      >>> dimap' asStackSubject id reviewHeavyFlow
      >>> orchestrateWith stackFuel (stackPin (remediate stackRule fixerContinuation))
      >>> orchestrateWith stackFuel (stackWorker "triage" stackTriage stackContinuation)
      >>> stackGate
      >>> humanGate "Promote this stack out of draft? Each branch spends a CI run on a shared runner."
      >>> consentGate
      >>> orchestrateWith stackFuel (budgetGate >>> stackWorker "promote" stackPromote stackContinuation)
  where
    -- The same prepend @grind-paradox@ makes, for a related reason and not the
    -- identical one. There the facts would be REPLACED by a caller's input,
    -- because that workflow carries a default; here input is required, so
    -- nothing is at risk of replacement and the prepend is only how the facts
    -- reach the explore stances. What it buys is the same either way: the
    -- caller's text stays a genuine steer rather than becoming the only place
    -- the run learns which repository it is in.
    withStackFacts steerText = promptText stackFacts <> "\n\n" <> steerText

-- | The ceiling on every loop in 'stackPRs'. Finite where 'workerFuel' is not,
-- and for two reasons that point the same way.
--
-- __Cost.__ Four orchestrated loops run in sequence here. @worstCaseCost@ sums
-- a sequence, so four unbounded loops overflow 'maxBound' and report a negative
-- worst case; four capped ones report a number an operator can read before
-- spending anything.
--
-- __And exhaustion is safe here.__ 'orchestrateWith' yields the last summary at
-- trip n rather than aborting, so a stack that needs more trips than this
-- reaches the next stage with every branch it did cut, rather than stranding
-- them. Twelve is generous against a stack of the size this workflow is for: a
-- diff wanting more than twelve trips of cutting wants a person to look at the
-- plan.
stackFuel :: Maybe Int
stackFuel = Just 12

-- | The plan lenses a stacking run edits through, and the whole of what it puts
-- between the planner and the steer.
--
-- 'editPlan'\'s six are written for an implementation plan — steps that will be
-- carried out — and a slice plan is a different artifact: its entries are
-- branches, and the only question about them is where the cuts fall. So this is
-- a different chain rather than a narrowing of that one, exactly as
-- 'docsPlanLenses' is.
--
-- __The cut first, then the English.__ 'stackSlicePlan' decides what each branch
-- holds, and @simple-english@ rewords what survives. The other order spends the
-- rewrite on entries the slice lens then merges away.
--
-- A named table rather than a list inlined into the workflow, for
-- 'docsPlanLenses'\'s reason: @docs\/workflows.md@ says which lenses a stacking
-- run edits through, and a lens added to an inline list changes no other name,
-- count or skeleton that the prose is checked on.
stackPlanLenses :: [(LeafName, Prompt)]
stackPlanLenses =
  [ ("slice", stackSlicePlan)
  , ("simple-english", simpleEnglishLens)
  ]

-- | What a stacking run's fixers stand under: 'grindRule' at
-- 'Incite.Prompts.stackDisciplines' — the code rule, plus the disciplines that
-- only a stack has. Not a grind, and what is spliced is disciplines rather
-- than tree facts, but the splice is the same splice for the same reason:
-- 'codeRule' answers which side gives when the code and the record disagree,
-- and it is silent about everything a stack can lose that a single change
-- cannot — a review thread destroyed by recreating a branch, an approval
-- dismissed by a force-push, a fix applied at the top of the stack that
-- becomes a conflict, a merge that ends the review before it starts. A second
-- spelling of the splice would drift from the first silently.
--
-- __Spliced into every acting leaf, not only the fixers.__ 'stackWorker' puts it
-- above each worker's own brief, because the leaf most able to destroy review
-- history is the one cutting branches, and it runs long before any fixer does.
stackRule :: Prompt
stackRule = grindRule stackDisciplines

-- | The check that proves a stack builds: the script the bootstrap leaf writes,
-- run by __us__, over every branch in @.stack-branches@.
--
-- One entry rather than one per branch, because the branch list is a runtime
-- fact and a 'Flow' is built before the run. The script owns the fan-out, the
-- serial warm-up of the bottom branch, and the per-branch ledger the status
-- table reads; what this owns is the exit code.
--
-- __Argv, no shell.__ @execStep@ runs the command directly, so the leading
-- @.\/@ is load-bearing and the script must be executable. A missing or
-- unexecutable script is a red gate, which 'repairLeaf' can fix — the bootstrap
-- leaf writing it is what makes that the rare case rather than the first one.
stackChecks :: [(LeafName, NonEmpty Text)]
stackChecks = [("verify-stack", "./verify-stack.sh" :| [])]

-- | The check that decides whether a promotion may happen at all: may I spend a
-- CI slot right now?
--
-- __@--wait@ rather than a bare call__, so a held budget is waited out inside
-- one exec rather than spun on by an agent. The script polls, and it fails
-- closed: a queued run belonging to anybody else holds it unconditionally, and a
-- job count it cannot read counts as a full budget rather than an empty one.
--
-- Separate from 'stackChecks' because the two answer different questions and
-- fail differently. A red 'stackChecks' is a defect in the stack and a leaf can
-- repair it; a red budget is somebody else's job queued ahead of yours, and the
-- only correct response is to not promote.
budgetCheck :: (LeafName, NonEmpty Text)
budgetCheck = ("ci-budget", "./ci-budget.sh" :| ["--wait"])

-- | The check that asks whether a person agreed to spend CI at all: does
-- @.stack-promote-approved@ exist?
--
-- __An 'Agent.Op.Exec' leaf because the 'humanGate' beside it is not one.__
-- @Agent.Run@ answers every 'Agent.Op.Ask' with @gateAnswer@, which defaults to
-- @\"yes\"@, so on the MCP path and on any headless run the gate in front of
-- spending a shared runner approves itself — it protects an operator at a
-- terminal and nobody else. This is the same question asked in the one currency
-- an unattended run cannot forge on its own behalf: an exit code. Absent file,
-- non-zero, and 'consentGate' aborts the run.
--
-- __A file rather than a flag__, because a flag would have to be threaded
-- through a caller that may be a cron entry. A file is created by whoever is
-- actually willing to spend the CI, out of band, before the run reaches here.
-- 'Incite.Prompts.stackDisciplines' forbids the agent from creating it, which is
-- the same class of rule as "never merge" and holds for the same reason.
consentCheck :: (LeafName, NonEmpty Text)
consentCheck = ("promotion-consent", "test" :| ["-f", ".stack-promote-approved"])

-- | 'consentCheck' as a gate, and the one place in this workflow where a single
-- red check ends the run rather than starting a repair.
--
-- Fuel of one: 'checkLoop' runs the check once and 'loopUntil' aborts on
-- exhaustion, so a missing approval file stops the run before any branch leaves
-- draft. There is nothing for a repair leaf to do — the answer is a person's,
-- not a defect — so the loop passes 'Id', exactly as 'budgetGate' does.
consentGate :: Flow Text Text
consentGate = checkLoop "consent" 1 Id [consentCheck]

-- | The ceiling on how many times the promotion loop may wait out a held budget
-- before the run fails.
--
-- Two, and the unit is not a poll — 'budgetCheck' passes @--wait@, so one trip
-- is one full waiting period of the script's own (30 minutes, by its default),
-- and the ceiling is therefore about an hour. Beyond that the runners are held
-- by something this run cannot influence, and a person should read the queue
-- rather than a loop spending fuel on it.
budgetFuel :: Int
budgetFuel = 2

-- | Run 'budgetCheck' __ourselves__ and let nothing downstream promote until it
-- exits zero.
--
-- __'Id' as the repair, and it is not a placeholder.__ There is nothing in the
-- repository to fix: the gate is red because somebody else is queued, or because
-- this stack already holds its budget. So the loop simply waits again, and
-- @'left'' 'Id' = 'Id'@ means it does that without an extra node, an extra leaf,
-- or an agent turn spent on the word \"waiting\".
--
-- __Exhaustion aborts, and that is the point.__ 'checkLoop' inherits
-- 'loopUntil'\'s abort-on-exhaustion, so a budget still held after 'budgetFuel'
-- waits fails the run rather than falling through into a promotion. A gate that
-- gives up and lets the work past is not a gate, and this is the one whose
-- failure lands on somebody else.
--
-- It sits inside the promotion loop rather than in front of it, so it is
-- re-answered before every trip. A clearance read once and reused is a
-- clearance about a queue that has since changed.
budgetGate :: Flow Text Text
budgetGate = checkLoop "budget" budgetFuel Id [budgetCheck]

-- | The exec policy 'stackPRs' runs under, __derived from the checks__ rather
-- than written beside them, for the reason 'grindGrant' is.
--
-- A grant and a check list are two statements of one fact, and they drift
-- silently in the direction that matters: an ungranted check is denied inside
-- the run, the gate never reads a real exit code, and the artifact still carries
-- a section that looks like a gate ran. Here the second of the two is the budget
-- gate, so the drift would be a promotion loop that never actually asks whether
-- it may promote.
--
-- Narrower than 'actingGrant': this workflow runs no build of its own. Every
-- @git@, @gt@, @gh@ and @nix@ command belongs to the agent's own tools, gated by
-- its permission flow, or to a child of one of these two scripts.
stackGrant :: Grant
stackGrant = execGrant [NE.head cmd <> "*" | (_, cmd) <- consentCheck : budgetCheck : stackChecks]

-- | The pin every acting leaf of a stacking run stands under.
--
-- __Named once, because the argument for it is one argument.__ These leaves cut
-- branches, force pushes and spend CI on a shared runner. Left unpinned they
-- inherit the run's backend, so a @run --backend codex@ or an MCP caller passing
-- @backend@ silently moves a leaf that rewrites git history — and no leaf name,
-- plan skeleton or cost estimate moves with it.
--
-- 'defaultModel' is claude-agent's own default, deliberately __not__ 'fable5':
-- fable is pinned where a fast reader over a fixed text is the point, and none
-- of these leaves is that.
--
-- __It covers the fixers too, not only the workers.__ 'remediate' and
-- 'repairLeaf' are unpinned where 'shipFeature' and @grind-paradox@ use them,
-- which is right there — a lens chain and a repair over one tree are readings,
-- not rewrites. In a stacking run they are neither: @remediate@ edits at the
-- branch that introduced the code and runs @gt restack@, and @repair@ fixes a
-- red @verify-stack.sh@ the same way. A pin on the workers alone would have left
-- the two leaves that rewrite the most history running on whatever the caller
-- passed, while the documentation said every acting leaf was pinned.
stackPin :: Flow Text Text -> Flow Text Text
stackPin = withBackend claudeAgent defaultModel

-- | 'greenGate' with its repair leaf under 'stackPin', which is the only thing
-- that distinguishes it. Bound rather than written twice because 'stackPRs' runs
-- it at both of its gate positions.
stackGate :: Flow Text Text
stackGate = checkLoop "gate" repairFuel (stackPin (repairLeaf stackRule)) stackChecks

-- | One acting leaf of a stacking run: its own brief, under the facts and the
-- rule, pinned to a model.
--
-- __Built once rather than four times__, so no worker can lose the disciplines
-- or acquire a different backend by being written later. What each leaf supplies
-- is its name, its body, and the closing clause that says whether anything will
-- call it again.
--
-- __Pinned through 'stackPin'__, which is where the argument for the pin lives
-- and which the fixers go through as well, so "every acting leaf is pinned" is
-- a property of one binding rather than of remembering to wrap each one.
--
-- __The bill is real.__ 'stackFacts' and 'stackRule' come to roughly 8 KB, and
-- every trip of every loop pays them. That is the price of a worker that cannot
-- forget which repository it is in or what it may not do, and it is why
-- 'Incite.Prompts.stackTooling' is a leaf of its own rather than a fifth
-- standing brief.
stackWorker :: LeafName -> Prompt -> Prompt -> Flow Text Text
stackWorker name body closing =
  stackPin (refineWith name (brief standing) id)
  where
    opening =
      [__i|
        #{stackFacts}

        #{stackRule}

        #{body}
      |]
    -- An own branch for the empty clause rather than splicing @mempty@ into a
    -- template, for 'remediate'\'s reason: each body file closes with a sentence
    -- of its own, and an unconditional @"\\n\\n" <> closing@ would leave a leaf
    -- that runs once trailing two blank lines. Byte drift in a prompt is
    -- invisible to every other instrument in this repository.
    standing
      | T.null (T.strip (promptText closing)) = opening
      | otherwise =
          [__i|
            #{opening}

            #{closing}
          |]

-- | The continuation contract every 'stackWorker' running under 'orchestrate'
-- stands under.
--
-- __Splices 'continueMarker' rather than spelling it__, for the reason
-- 'document' and 'fixerContinuation' do: the brief tells a worker how to ask for
-- another trip and 'decideContinue' decides whether it asked, and the two agree
-- only because both go through that binding.
--
-- __And it names the blocked ending explicitly.__ The other continuation clauses
-- offer two endings, more work or finished, because their stages can always take
-- one more step. A stacking run has a third: a design disagreement it must not
-- settle alone, an approved branch it must not rewrite, a starved runner pool no
-- branch edit can fix. Without somewhere to put that, a blocked worker either
-- reports completion it does not have or spins its fuel. So the clause admits
-- it, requires it in writing under a heading a person will read, and makes
-- saying which of the two endings this is part of the contract.
stackContinuation :: Prompt
stackContinuation =
  [__i|
    You are running under an orchestrator that will call you again with your own
    summary as its input, so write the summary for your successor: what you did,
    which branches it touched, what is left, and what a stranger would need in
    order to continue. Anything a person has to decide goes in `.stack-plan.md`
    under `\#\# for a person`, not into this summary alone.

    End with a status line, alone on the last line, and it is one of three:

    - `#{continueMarker}` — work remains at this stage. You will be called again.
    - `#{blockedMarker}` — you cannot continue without a person: a design
      disagreement, an approved branch you must not rewrite, a runner pool no
      branch edit can fix. Write the block under `\#\# for a person` first.
    - `WORK COMPLETE` — this stage is finished, and nothing is waiting on
      anybody.

    Never report a block as completion. A later stage reads this line and a
    block reported as `WORK COMPLETE` is how a run spends CI on work a person
    was supposed to decide first.
  |]

-- | The marker a worker ends on when it cannot continue without a person.
--
-- __A third ending, because two were not enough.__ 'decideContinue' asks one
-- question — another trip, or not — and a stacking run can stop for a reason
-- that is neither. A worker with nowhere to put "an approved branch I must not
-- rewrite" either reports a completion it does not have, and the promotion
-- stage then spends CI on it, or spins its fuel until the loop aborts.
--
-- __Terminal to the loop, and visible to the stage after it.__ Anything that is
-- not 'continueMarker' already ends the loop, so this changes no control flow;
-- what it adds is a token the promotion brief can refuse on and a person can
-- grep for. The distinction was prose before, and prose is not something the
-- next stage can read.
blockedMarker :: Text
blockedMarker = "WORK BLOCKED"

-- | The shared analysis prefix: explore (three stances) then plan.
explorePlan :: Flow Text Text
explorePlan = explore >>> plan
  where
    -- Analysis-only and heterogeneous — one agent spec per stance, so the
    -- perspectives are genuinely independent. Four stances over three
    -- backends, so the fourth is a distinct MODEL rather than a distinct
    -- backend; @claude-agent\/fable@ and @claude-agent@ are two agents to
    -- everything downstream of 'Agent.Op.AgentSpec'.
    --
    -- The architect is the fourth stance and reads the tree, not the request:
    -- the other three all argue about the change, and none of them was asked
    -- what shape it has to land in. It is on Fable 5 rather than sharing a
    -- backend with a sibling — a whole-tree structural read is the heaviest
    -- thinking here, and a shared backend would cost the fan-out the
    -- independence it exists for.
    --
    -- 'reviewer' builds each stance: named once, read-only, under a backend
    -- scope. Same shape the review panels are built from, so a stance cannot
    -- drift from a reviewer in mode or acquire write access.
    --
    -- __No 'withMode' 'Plan' around the fan-out.__ Read-only is 'reviewer'\'s
    -- to say and it says it at every stance, so an outer wrapper adds no
    -- constraint — and it is not free: 'withMode' is @WithScope . ModeScope@
    -- and 'Agent.Flow.Skeleton.toSkeleton' reifies every 'Agent.Flow.WithScope'
    -- as its own @FScope@ node, so it buys a second @scope mode:plan@ line in
    -- @agent-functor plan@ that constrains nothing under it. The reduction is
    -- pure ('hierarchical'), so there is no leaf out here for it to reach in
    -- any case.
    explore =
      exploreFlows
        [ reviewer (withBackend claudeAgent defaultModel) "intrepid" intrepid
        , reviewer codexScope "skeptic" skeptic
        , reviewer opencodeScope "contemplative" contemplative
        , reviewer (withBackend claudeAgent fable5) "architect" architect
        ]
        -- Narrowing, not ranking by importance: what breaks, then the shape it
        -- lands in, then which design, then the moves. The architect precedes
        -- the design stance because the design stance is told to build on its
        -- map.
        $ hierarchical ["skeptic", "architect", "contemplative", "intrepid"]
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
--
-- __Unpinned, on purpose.__ Every other backend scope in this module is
-- argued for at the leaf it wraps — 'plan' on Fable 5 because 'planBrief'
-- leans on it, each explore stance on its own agent because the fan-out is
-- bought with independence. A lens chain is neither: it is six sequential
-- rewrites of one text, so a pin here buys no independence, and there is no
-- brief among them that only one model can hold. Left alone they run on the
-- run's own @--backend@, which is what 'shipDocs'\'s 'docsPlanLenses' chain
-- does as well — and the two chains being scoped the same way is the whole
-- reason a reader can compare them.
--
-- A pin added here without that argument is invisible: it changes no leaf's
-- text and no leaf's name, so only a scope-reading test can see it. There is
-- one, in @test\/Spec.hs@.
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
