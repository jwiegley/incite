module Main (main) where

import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, isInfixOf, isSuffixOf, nub, sort, (\\))
import qualified Data.List.NonEmpty as NE
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Maybe (fromMaybe, maybeToList)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (listDirectory)
import Test.Tasty
import Test.Tasty.HUnit

import Control.Exception (ErrorCall (..), evaluate, try)

import Agent.Bounds (Fuel (..))
import Agent.Cost (Cost (..), renderCost, worstCaseCost)
import Agent.Grant (Grant, permitExec)
import Agent.Flow (Flow (Id), Mode (Plan), dimap', foldLeavesScoped, (>>>))
import Agent.Flow.Skeleton (FlowF (..), Rooted (..), toSkeleton)
import Agent.Interpret (LeafHandlers (..), interpret, leafRunner)
import Agent.Op (ExecOutcome (..), LeafName, Scope (..), agentSpecText, leafNameOf, leafNameText, opTag, opTagPrefixed, scopeDeclText)
import Agent.Oracle (Answer (..))
import Agent.Prompt (Prompt, prompt, promptText)
import Agent.Run (Workflow (..))
import Incite.Backend (backends, backendsFor, blockOpencode, claudeAgentBackend, opencodeBackend, opencodeBackendFor, reviewer)
import Incite.Feature
  ( Orientation (..)
  , actingGrant
  , fixerContinuation
  , closeWithChanges
  , paradoxRule
  , GrindSpec (..)
  , grindChecks
  , grindFlow
  , grindGrant
  , grindGrantFor
  , grindParadox
  , grindParadoxSpec
  , grindRule
  , grindTests
  , grindTestsChecks
  , grindTestsGrant
  , grindTestsRule
  , grindTestsSpec
  , grindLiveView
  , grindLiveViewChecks
  , grindLiveViewGrant
  , grindLiveViewRanking
  , grindLiveViewRule
  , grindLiveViewSpec
  , asRetroSubject
  , asDocsSubject
  , asReviewSubject
  , asReviewSubjectIgnoring
  , asStackSubject
  , codeChecks
  , codeRule
  , continueMarker
  , decideContinue
  , decideTrip
  , decideRed
  , decideFactsResolved
  , exhaustionNotice
  , docsRule
  , docsPlanLenses
  , isRed
  , document
  , implement
  , liteFuel
  , orchestrateWith
  , orient
  , planFeature
  , preambleOf
  , preambleViolations
  , remediate
  , retrospective
  , shipDocs
  , shipFeature
  , shipFeatureLite
  , budgetCheck
  , budgetFuel
  , consentCheck
  , stackChecks
  , stackContinuation
  , stackFuel
  , blockedMarker
  , stackGrant
  , stackPRs
  , stackPlanLenses
  , stackRule
  , stackWorker
  )
import Incite.Prompts
  ( alexeyPrinciples
  , alexeyReview
  , alexeyStance
  , codeReview
  , codeReviewerSecurity
  , docsCompleteness
  , docsStructure
  , fess
  , fixAll
  , paradoxFacts
  , testsFacts
  , liveViewFacts
  , liveViewAuth
  , stackDisciplines
  , stackFacts
  , stackPromote
  , stackSlice
  , stackTooling
  , stackTriage
  , grindCodegenGaps
  , grindDry
  , grindEmittedCode
  , grindHardcodings
  , grindStubs
  , grindTargetConsistency
  , grindValidatorCalls
  , grindVacuous
  , haskellReviewer
  , perfReviewer
  , ponytailAuditRubric
  , ponytailLadder
  , ponytailReviewRubric
  , qaAgent
  , reviewSequence
  , retroSynthesis
  , reviewSynthesis
  , reviewUnits
  , reviewArchitecture
  , reviewComplexity
  , reviewCorrectness
  , reviewTests
  , steSkill
  , stopSlop
  , technicalDocsStrategist
  )
import Incite.Review
  ( Subject (..)
  , admits
  , auditReportDir
  , forbiddenPairings
  , grindName
  , grindSynthesis
  , grindSynthesisOver
  , grindTestsLenses
  , grindTestsName
  , grindLiveViewLenses
  , grindLiveViewName
  , toTree
  , architectureOfChange
  , disciplineOfPanel
  , docsAccuracy
  , docsStrategyOfPlan
  , emissionLenses
  , fessAudit
  , haskellOfHouse
  , lensSetViolations
  , lensesOf
  , ofTree
  , ponytailOfDocs
  , ponytailOfTree
  , promptLint
  , promptLintBrief
  , promptLintScope
  , qaOfCommit
  , qaOfCommitOver
  , qaSiblings
  , reporting
  , retro
  , retroGrant
  , retroReport
  , reviewAudit
  , reviewDocs
  , reviewHeavy
  , reviewLite
  , reviewLiteRouters
  , routeHaskell
  , slopOfDocs
  , spread
  , spreadPinned
  , TriageVerdict (..)
  , haskellTriggerExtensions
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "incite-workflows"
    [ decideContinueTests
    , decideTripTests
    , isRedTests
    , continueMarkerTests
    , reframingTests
    , preambleViolationsTests
    , orientTests
    , emptyChangeTests
    , documentTests
    , remediateTests
    , retrospectiveTests
    , retroReportTests
    , lensSetViolationsTests
    , lensesOfTests
    , codexFessTests
    , grindPanelTests
    , stackTests
    , liteTests
    , reorientationTests
    , promptLintTests
    , packagingTests
    , backendTests
    , scopeTests
    , qaFenceTests
    , haskellRouteTests
    , agentToolTests
    , factsFileTests
    , rendererNameTests
    , docsInventoryTests
    , backendProseTests
    , inputAllowlistTests
    ]

decideContinueTests :: TestTree
decideContinueTests =
  testGroup
    "decideContinue"
    [ testGroup
        "continues (Left)"
        [ testCase "bare marker on last line" $
            decideContinue "summary\nWORK REMAINS"
              @?= Left "summary\nWORK REMAINS"
        , testCase "marker with backtick decoration" $
            decideContinue "summary\n`WORK REMAINS`"
              @?= Left "summary\n`WORK REMAINS`"
        , testCase "marker with asterisk decoration" $
            decideContinue "summary\n**WORK REMAINS**"
              @?= Left "summary\n**WORK REMAINS**"
        , testCase "marker with trailing period" $
            decideContinue "summary\nWORK REMAINS."
              @?= Left "summary\nWORK REMAINS."
        , testCase "lowercase marker" $
            decideContinue "summary\nwork remains"
              @?= Left "summary\nwork remains"
        , testCase "marker alone" $
            decideContinue "WORK REMAINS" @?= Left "WORK REMAINS"
        , testCase "trailing empty lines after marker" $
            decideContinue "summary\n\n\nWORK REMAINS\n\n"
              @?= Left "summary\n\n\nWORK REMAINS\n\n"
        , testCase "marker with trailing whitespace" $
            decideContinue "summary\nWORK REMAINS   "
              @?= Left "summary\nWORK REMAINS   "
        , testCase "marker with underscore decoration" $
            decideContinue "summary\n_WORK REMAINS_"
              @?= Left "summary\n_WORK REMAINS_"
        ]
    , testGroup
        "stops (Right)"
        [ testCase "different marker (WORK COMPLETE)" $
            decideContinue "summary\nWORK COMPLETE"
              @?= Right "summary\nWORK COMPLETE"
        , testCase "marker in prose, not last line" $
            decideContinue "no work remains" @?= Right "no work remains"
        , testCase "empty input" $
            decideContinue "" @?= Right ""
        , testCase "whitespace only" $
            decideContinue "   \n  \n  " @?= Right "   \n  \n  "
        , testCase "marker as substring of last line" $
            decideContinue "work remains is done"
              @?= Right "work remains is done"
        , testCase "multi-line summary without marker" $
            decideContinue "line one\nline two\nline three"
              @?= Right "line one\nline two\nline three"
        , testCase "marker on non-last line" $
            decideContinue "WORK REMAINS\nactually done"
              @?= Right "WORK REMAINS\nactually done"
        ]
    , -- The decoration alphabet, stated from BOTH sides. Every case above is
      -- positive: each says one character is stripped, and together they leave
      -- the set open at the top. Widen the strip to @isPunctuation@ and all of
      -- them stay green while "WORK REMAINS?" starts spinning the loop — the
      -- runaway 'decideContinue' exists to prevent.
      --
      -- So the negative rows are the load-bearing half. They are the characters
      -- a model plausibly emits around a status line and which must NOT be
      -- read through.
      testGroup
        "decoration alphabet"
        [ testGroup
            "stripped"
            [ testCase [c] $
                decideContinue (T.pack (c : "WORK REMAINS" <> [c]))
                  @?= Left (T.pack (c : "WORK REMAINS" <> [c]))
            | c <- "`*_ ."
            ]
        , testGroup
            "not stripped"
            [ testCase [c] $
                decideContinue (T.pack (c : "WORK REMAINS" <> [c]))
                  @?= Right (T.pack (c : "WORK REMAINS" <> [c]))
            | c <- "?!:;,)]}>\"'#~-+="
            ]
        ]
    ]

-- | The budget 'orchestrate' threads through 'decideTrip', stated from both
-- sides: the trips that keep the loop alive, and the ones that end it.
--
-- 'Nothing' is the default — no ceiling — so the load-bearing cases are the
-- 'Just' ones: a worker still reporting 'WORK REMAINS' when the budget is
-- spent. Before the budget existed that was the trip 'loopUntil' aborted on,
-- stranding every edit the worker had made; now it is the account the review
-- panel reads. The marker is still present and 'decideContinue' still reads
-- it — what changed is that the budget overrides it, so the loop yields
-- rather than asking for a trip it does not have, and 'exhaustionNotice'
-- rides on the yielded summary so the artifact says the budget cut the loop.
decideTripTests :: TestTree
decideTripTests =
  testGroup
    "decideTrip"
    [ testGroup
        "continues (Left)"
        [ testCase "Nothing — no ceiling, marker present" $
            decideTrip Nothing "summary\nWORK REMAINS"
              @?= Left (Nothing, "summary\nWORK REMAINS")
        , testCase "Just n with budget to spare" $
            decideTrip (Just (Fuel 3)) "summary\nWORK REMAINS"
              @?= Left (Just (Fuel 2), "summary\nWORK REMAINS")
        , testCase "Just n decorated marker, budget to spare" $
            decideTrip (Just (Fuel 2)) "summary\n`WORK REMAINS`"
              @?= Left (Just (Fuel 1), "summary\n`WORK REMAINS`")
        ]
    , testGroup
        "yields (Right)"
        [ -- The case that used to abort: the marker is there, but there is no
          -- trip left to take. The summary survives, so the panel sees the
          -- work — under the exhaustion notice, so a reader of the final
          -- artifact can tell a cut-off worker from a finished one. Both the
          -- exported binding and a hand-written needle, so a notice gutted to
          -- @\"\"@ cannot pass by both sides moving together.
          testCase "Just 1 — marker with the budget spent yields under the notice" $ do
            decideTrip (Just (Fuel 1)) "summary\nWORK REMAINS"
              @?= Right ("summary\nWORK REMAINS\n\n" <> exhaustionNotice)
            assertBool
              "the notice does not open with its own ## heading"
              ("## trip budget exhausted" `T.isPrefixOf` exhaustionNotice)
            assertBool
              "the notice does not call the remainder unresolved"
              ("unresolved work" `T.isInfixOf` exhaustionNotice)
        , -- Nothing never yields on the marker — it ends only on WORK COMPLETE.
          testCase "Nothing — WORK COMPLETE" $
            decideTrip Nothing "summary\nWORK COMPLETE"
              @?= Right "summary\nWORK COMPLETE"
        , -- A worker that finished, whatever the budget: no notice, because
          -- nothing was cut. Same as 'decideContinue'.
          testCase "Just n — WORK COMPLETE with budget to spare" $
            decideTrip (Just (Fuel 3)) "summary\nWORK COMPLETE"
              @?= Right "summary\nWORK COMPLETE"
        , -- A confused worker (no marker) ends on trip one regardless of budget.
          testCase "Nothing — no marker" $
            decideTrip Nothing "no work remains"
              @?= Right "no work remains"
        , -- And spending the LAST trip on a finished worker is not exhaustion:
          -- the budget ran out exactly when the work did, and a notice here
          -- would cry wolf over every job that fit its ceiling.
          testCase "Just 1 — WORK COMPLETE on the last trip carries no notice" $
            decideTrip (Just (Fuel 1)) "summary\nWORK COMPLETE"
              @?= Right "summary\nWORK COMPLETE"
        ]
    ]

-- | The failure marker @Agent.Flow.Combinators.execStep@ emits, recorded from
-- __its source__ rather than from a rendered log.
--
-- @decodeOutcome@ is @(if exit == 0 then \"✓ \" else \"✗ \") <> name <> \" (exit
-- N)\"@, and @execStep@ prepends @\"\\n\"@ — so the marker opens a line, the
-- glyph is U+2717 and the space after it is part of the marker. There is no
-- ANSI anywhere on that path: the value threaded through the flow is
-- @decodeOutcome@\'s plain 'Text', and colour is a renderer's business.
--
-- Getting this wrong is the one failure nothing downstream can catch. A
-- predicate written from a guess certifies a red tree as green, the gate passes,
-- and the run reports a build it never proved.
execFailureLog :: Text
execFailureLog =
  "the remediation account\n✓ build (exit 0)\n✗ tests (exit 1)\n    3 examples, 1 failure"

-- | Fragments the homomorphism table below is built from, __each a whole
-- line__.
--
-- Line-terminated on purpose, and the case beside the table says why: 'isRed'
-- is a homomorphism over concatenation at line boundaries, which is how
-- @execStep@ builds a log (it appends @\"\\n\" <> status@), and it is NOT one
-- over an arbitrary split. Cutting @\"✗ build\"@ into @\"✗\"@ and @\" build\"@
-- gives two fragments that are green apart and red joined.
logFragments :: [Text]
logFragments =
  [ ""
  , "the worker's account\n"
  , "✓ build (exit 0)\n"
  , "✗ tests (exit 1)\n"
  , "    3 examples, 1 failure\n"
  , -- The marker mid-line in prose. A predicate scanning the whole text with
    -- `isInfixOf` reads this as a failing build; one reading line starts does
    -- not, and this is the row that tells them apart.
    "the report explains what a ✗ line means\n"
  , -- And indented, which is where an excerpt's continuation lands.
    "  ✗ tests (exit 1)\n"
  ]

-- | 'isRed' and 'decideRed': the only real judgement in the green gate.
--
-- __A monoid homomorphism from log concatenation into @Any@__, and the law is
-- not decoration. @execStep@ APPENDS its status line to the log it receives, so
-- a trip that fails leaves its @✗@ in the text the next trip starts from —
-- under the law, that stale marker makes every later verdict red and the loop
-- burns its fuel on a tree that is already green. That is what forces the
-- @const mempty@ feed in 'Incite.Feature.greenGate', and it is why the law is
-- tested rather than assumed.
isRedTests :: TestTree
isRedTests =
  testGroup
    "isRed"
    [ testCase "the recorded failure log is red" $
        isRed execFailureLog @?= True
    , testCase "the same log with every check passing is not" $
        isRed (T.replace "✗" "✓" execFailureLog) @?= False
    , -- The unit of the homomorphism. An empty log is not a failing log, which
      -- is the whole reason the gate can feed the loop `mempty`.
      testCase "isRed mempty is False" $
        isRed mempty @?= False
    , -- Hand-enumerated over all pairs, not generated: this suite depends on
      -- tasty and tasty-hunit only, and a QuickCheck dependency is not worth
      -- one law over seven fragments.
      testCase "isRed (a <> b) = isRed a || isRed b, over every pair of fragments" $
        report
          [ "pair " <> tshow (a, b) <> ": joined " <> tshow (isRed (a <> b))
              <> ", separately " <> tshow (isRed a || isRed b)
          | a <- logFragments
          , b <- logFragments
          , isRed (a <> b) /= (isRed a || isRed b)
          ]
    , -- The known ceiling, written down rather than left for somebody to
      -- discover. The law above holds because every fragment ends a line;
      -- concatenation that splits a marker creates a match at the seam, and no
      -- line-oriented predicate can avoid it. It costs nothing here because
      -- `execStep` never splits one.
      testCase "the law does not extend to a split that cuts the marker" $ do
        isRed "✗" @?= False
        isRed " build (exit 1)" @?= False
        isRed ("✗" <> " build (exit 1)") @?= True
    , -- Round trip through the decider. Red continues the loop (Left feeds the
      -- repair leaf), green ends it (Right). Getting this backwards repairs a
      -- green tree and ships a red one.
      testCase "red continues the loop and green ends it" $ do
        decideRed execFailureLog @?= Left execFailureLog
        decideRed "✓ build (exit 0)\n✓ tests (exit 0)"
          @?= Right "✓ build (exit 0)\n✓ tests (exit 0)"
    ]

continueMarkerTests :: TestTree
continueMarkerTests =
  testGroup
    "continueMarker"
    [ testCase "is WORK REMAINS" $
        continueMarker @?= "WORK REMAINS"
    ]

-- | The stand-in summary the reframing goldens are recorded against. Nothing
-- in either frame can contain it, so \"appears exactly once\" is a statement
-- about the splice and not about the prose around it.
summaryMarker :: Text
summaryMarker = "<<SUMMARY>>"

-- | Every reframing "Incite.Feature" applies before handing a worker's closing
-- summary to a panel, each with the file recording its frame.
--
-- All are pure @'Text' -> 'Text'@ and none is reachable from a RUN. The two
-- with consumers are applied by @dimap'@ inside a flow, so no leaf name
-- mentions them and @plan@ renders a flow skeleton that cannot see text;
-- 'asDocsSubject' has no consumer at all yet. An edit to one silently changes
-- what a whole panel is pointed at, and these files are the only thing that
-- would say so.
--
-- __This list covers 'Orientation', and @orientTests@ forces it to.__ Each
-- entry is @'orient' c@ for one constructor, so an orientation with no entry
-- here would be a frame with no golden. Rather than trust that,
-- @every orientation has a recorded frame@ compares the two as sets: a new
-- constructor with no entry fails it, and so does an entry that is not any
-- constructor's frame.
reframings :: [(String, Text -> Text, FilePath)]
reframings =
  [ ("asReviewSubject", asReviewSubject, "test/golden/as-review-subject.txt")
  , ("asRetroSubject", asRetroSubject, "test/golden/as-retro-subject.txt")
  , ("asDocsSubject", asDocsSubject, "test/golden/as-docs-subject.txt")
  , ("asStackSubject", asStackSubject, "test/golden/as-stack-subject.txt")
  ]

-- | Three cases per reframing, and which mutation each one kills is worth
-- writing down exactly, because the three are not interchangeable and the
-- golden alone is none of them.
--
-- Against the __recorded__ bytes case 1 kills everything: any edit to a frame
-- moves them. So the question that decides what the other two are worth is
-- which mutations survive __re-recording__ — which is what happens the moment
-- someone regenerates a golden to get a build green:
--
-- * a frame that dropped its argument, or spliced it twice, dies at __case 2__.
--   Re-recording moves the marker count to 0 or 2 and the count is asserted
--   against 1, not against the file;
-- * a frame that splices the marker faithfully and mangles the summary around
--   it dies at __case 3__, and at nothing else here. That is the one family
--   surviving both a re-record and a marker count, and the reason case 3 is
--   written at all;
-- * a frame that moved the splice to a different paragraph survives all three
--   after a re-record. Splice __position__ is fenced in 'orientTests' instead:
--   @every orientation leaves exactly one blank line above the account@ reads
--   the rendered text and says the account is last, which no re-recording can
--   satisfy. It covers these frames because @every orientation has a recorded
--   frame@ makes each of them an 'orient'.
--
-- Recorded rather than transcribed: each file was written by running its own
-- function, so what it fences is the code and not somebody's copy of it. That
-- is provenance and no case below can prove it — it is written because a golden
-- typed out by hand is a different artifact under the same name, and the
-- difference is invisible afterwards.
reframingTests :: TestTree
reframingTests =
  testGroup
    "reframings"
    [ testGroup
      name
      [ testCase "renders exactly the recorded frame" $ do
          recorded <- TIO.readFile path
          reframe summaryMarker @?= recorded
      , testCase "splices the summary exactly once" $ do
          recorded <- TIO.readFile path
          T.count summaryMarker recorded @?= 1
      , -- NOT \"for any summary\": this is a sample, and it is chosen rather
        -- than representative. 'orient' is affine by construction —
        -- @preambleOf o <> \"\\n\\n\" <> summary@ — so the universal is a
        -- property of the definition, and what these rows fence is that the
        -- definition keeps that shape. Each one is here to kill a named frame,
        -- and a row that kills nothing no other row kills is a row to delete.
        testCase "is that frame with the summary substituted, over a chosen sample" $ do
          recorded <- TIO.readFile path
          mapM_
            (\s -> reframe s @?= T.replace summaryMarker s recorded)
            [ "one line"
            , "several\nlines\nof summary"
            , -- An empty summary still leaves the instructions standing, and
              -- whitespace is not the same as empty.
              ""
            , "   "
            , -- The padded rows. A frame that ran `T.strip` over its argument
              -- passed every other case in this file, including the golden:
              -- `<<SUMMARY>>` has no padding to lose, so nothing else here can
              -- see the difference.
              "  padded  "
            , "\nleading and trailing newlines\n"
            , -- A summary that IS the marker, and one quoting it. A frame that
              -- substituted twice, or that re-scanned its own output, differs
              -- from `T.replace` only on these.
              summaryMarker
            , "a summary quoting " <> summaryMarker <> " inside it"
            , -- The frame's own vocabulary, so a frame that rewrote what it
              -- spliced to match its surrounding prose has somewhere to fail.
              "a summary mentioning `git diff` and WORK REMAINS"
            ]
      ]
    | (name, reframe, path) <- reframings
    ]

-- | The worker briefs, and the contract they share with the orchestrator that
-- calls them.
--
-- __A brief that names the wrong marker strands its loop, and nothing shows
-- it.__ The brief tells the worker how to ask for another trip and
-- 'decideContinue' decides whether it asked; the two agree only because both go
-- through 'continueMarker'. Spell it in a brief instead and the run burns every
-- trip of its fuel and then aborts, with no output anywhere naming the cause.
-- @plan@ cannot see it — it renders leaf names — so this is the check.
--
-- __Both workers, not one.__ 'document' was the only one that could be read
-- here while @implement@ was bound inside 'Incite.Feature.shipFeature'\'s
-- @where@ block. It is top-level now — two workflows run it — so the same three
-- cases are quantified over both, and the house rule below applies to it for the
-- first time.
documentTests :: TestTree
documentTests =
  testGroup
    "the worker briefs"
    $ [ testGroup
          name
          [ testCase "is one leaf" $ do
              sent <- flowLeafPrompts name worker "THE PLAN"
              length sent @?= 1
          , -- Round trip through the decider, not a substring check on the marker.
            -- The brief shows the marker decorated — @`WORK REMAINS`@ — and what
            -- has to hold is that the decorated form the worker copies is one
            -- 'decideContinue' reads as "call me again". It fails if the brief
            -- wraps the marker in something outside the decoration alphabet, or if
            -- the marker itself grows a character that alphabet does not strip.
            --
            -- The bullet's trailing prose is deliberately not fed in: the brief
            -- says the status line stands alone, so the contract is about the
            -- token.
            testCase "the marker as the brief decorates it is one decideContinue accepts" $ do
              leafText <- onlyFlowLeafPrompt name worker "THE PLAN"
              let decorated = "`" <> continueMarker <> "`"
              assertBool
                "the brief does not show the marker in the decoration this asserts"
                (T.isInfixOf decorated leafText)
              decideContinue ("work\n" <> decorated) @?= Left ("work\n" <> decorated)
          , -- The input is the plan, not the findings: a worker sits after @steer@
            -- and inside the loop. Findings are 'Incite.Feature.remediate'\'s
            -- input, downstream of the panel.
            testCase "hands the plan to the worker" $ do
              leafText <- onlyFlowLeafPrompt name worker "THE PLAN"
              assertBool "the input is not in the leaf" (T.isInfixOf "THE PLAN" leafText)
          , -- __The house rule 'Incite.Feature.document'\'s haddock states__: a
            -- top-level worker leaf names no stage that follows it. It held for
            -- @document@ by construction and was stated as the reason @implement@
            -- was allowed to say "review comes next" — it was private to the one
            -- @where@ block that put a review after it. It is not private now, and
            -- 'Incite.Feature.shipFeatureLite' puts a different panel after it, so
            -- the rule is quantified over both briefs and the sentence had to go.
            --
            -- __A phrase list, and it is worth being exact about what that is.__
            -- The rule is semantic and this is not: it refutes the spellings a
            -- worker brief would plausibly reach for, not every sentence that
            -- names a following stage. What makes it more than a pin on the one
            -- deleted sentence is that the list IS a list — a rewording is how
            -- this drift recurs, and a single literal waves every rewording
            -- through. A phrasing outside it still gets past, which is why the
            -- rule stays written down in 'Incite.Feature.document'\'s haddock as
            -- well as here.
            --
            -- Quantified over both briefs though only @implement@ has ever
            -- broken it: @document@'s instance is a standing guarantee rather
            -- than a regression pin, and a rule that covers only the leaf known
            -- to have failed it is not a rule.
            --
            -- __It reads the RENDERED leaf__, which splices 'ponytailLadder',
            -- 'wiggum' and (for @implement@) 'agenticCoder'. An upstream brief
            -- adopting one of these phrasings therefore fails here too. That is
            -- the right polarity — those bytes are in what the worker is told,
            -- whoever wrote them — and the complaint names the phrase, which is
            -- what points a reader at the upstream file rather than at this
            -- repository's own text.
            --
            -- 'proseNormal' rather than a raw substring: rewrapping a paragraph
            -- or backticking a word is not a failure, the sentence being there
            -- is.
            testCase "names no stage that follows it" $ do
              leafText <- onlyFlowLeafPrompt name worker "THE PLAN"
              report
                [ T.pack name <> " tells the worker what runs after it: " <> tshow phrase
                | phrase <-
                    [ "review comes next"
                    , "review follows"
                    , "reviewed next"
                    , "goes to review"
                    , "the panel runs"
                    , "then the reviewers"
                    ]
                , T.isInfixOf phrase (proseNormal leafText)
                ]
          ]
    | (name, worker) <- [("document", document), ("implement", implement)]
    ]
      <> [ -- The same contract on the fixer that runs under an orchestrator, and
           -- the same failure if it drifts. 'grindParadox' wraps @remediate@ in
           -- 'Incite.Feature.orchestrate', so this clause is what asks for
           -- another trip; a marker the decider does not read strands that loop
           -- for its whole fuel with nothing in any output naming the cause.
           --
           -- Round trip through 'decideContinue' rather than a substring check,
           -- for 'documentTests'\'s reason: what has to hold is that the
           -- DECORATED form the brief shows is one the decider accepts.
           testCase "fixerContinuation shows a marker decideContinue accepts" $ do
            let decorated = "`" <> continueMarker <> "`"
            assertBool
              "the fixer clause does not show the marker in the decoration this asserts"
              (says fixerContinuation decorated)
            decideContinue ("work\n" <> decorated) @?= Left ("work\n" <> decorated)
         , -- The other half of the contract: the terminal line, and what it must
           -- claim. A fixer that says WORK COMPLETE without saying what it closed
           -- leaves the gate as the only evidence anything happened.
           testCase "fixerContinuation names the terminal line and what it must carry" $
            report
              [ "fixerContinuation does not say " <> tshow needle
              | needle <- ["WORK COMPLETE", "every finding is fixed or answered"]
              , not (says fixerContinuation needle)
              ]
         , -- The one rule the docs brief exists to carry that @implement@ must
           -- not. Whitespace-normalised, so rewrapping the paragraph is not a
           -- failure — the sentence being gone is.
           testCase "document forbids editing code to make a sentence true" $ do
            leafText <- onlyFlowLeafPrompt "document" document "THE PLAN"
            assertBool
              "the brief does not forbid correcting the code instead of the prose"
              ( T.isInfixOf
                  "never edit code to make a sentence true"
                  (T.unwords (T.words leafText))
              )
         ]

-- | The bytes of the fixer brief that this repository owns, recorded off the
-- shipped flow.
--
-- Same split as 'promptLintGolden' and for the same reason: 'ponytailLadder'
-- and 'fixAll' are named rather than copied, because recording their contents
-- would put a flake input into git and go red on @nix flake update@. Everything
-- below them — the artifact rule and the closing paragraph — is text this repo
-- wrote, and it is here verbatim.
remediateGolden :: FilePath
remediateGolden = goldenDir <> "/remediate-code.txt"

-- | The one leaf that acts on a panel's findings, fenced at the byte.
--
-- __Recorded before the brief was generalised__, and that ordering is the whole
-- point. Nothing else in this repository can see this text: @plan@ renders leaf
-- names, @cost@ counts them, and 'lensBodyMismatches' reads lens tables rather
-- than worker briefs. An expectation written after a refactor pins the new
-- bytes and calls the refactor conservative by construction.
remediateTests :: TestTree
remediateTests =
  testGroup
    "remediate"
    [ testCase "is one leaf" $ do
        sent <- flowLeafPrompts "remediate" (remediate codeRule mempty) "THE FINDINGS"
        length sent @?= 1
    , -- __The conservativity law.__ The closing clause was added as a second
      -- argument after these bytes were recorded, and this is the case that
      -- says the addition changed nothing when the clause is absent. It is only
      -- worth anything because the golden predates the argument — recorded
      -- afterwards it would say the refactor was conservative by construction.
      --
      -- Total equality on everything this repo owns, so a reordering, a
      -- separator change or one reworded sentence all fail it.
      testCase "with no closing clause it is byte-for-byte what it was before the clause existed" $ do
        recorded <- TIO.readFile remediateGolden
        leafText <- onlyFlowLeafPrompt "remediate" (remediate codeRule mempty) "THE FINDINGS"
        leafText
          @?= promptText ponytailLadder
            <> "\n\n"
            <> promptText fixAll
            <> recorded
            <> "\n\n"
            <> "THE FINDINGS"
    , -- And the clause is APPENDED, under one blank line, rather than woven in.
      -- The findings block ends in a colon, so an unconditional splice would
      -- leave that colon pointing at a blank line whenever the clause is empty
      -- — which is why the empty case has its own branch, and why the law above
      -- is stated separately from this one.
      testCase "a closing clause is appended below the findings paragraph" $ do
        bare <- onlyFlowLeafPrompt "remediate" (remediate codeRule mempty) "THE FINDINGS"
        closed <- onlyFlowLeafPrompt "remediate" (remediate codeRule closeWithChanges) "THE FINDINGS"
        closed
          @?= T.replace
            "\n\nTHE FINDINGS"
            ("\n\n" <> promptText closeWithChanges <> "\n\nTHE FINDINGS")
            bare
    , -- The parameterisation, which nothing else checks: splicing the rule and
      -- then ignoring it, or splicing it twice, leaves the assertions above
      -- looking right. And the rule is the ONLY thing that argument moves —
      -- which is what lets both acting workflows and the grind fixer share this
      -- leaf.
      testCase "the artifact rule is the only thing its argument changes" $ do
        underCode <- onlyFlowLeafPrompt "remediate" (remediate codeRule mempty) "THE FINDINGS"
        underDocs <- onlyFlowLeafPrompt "remediate" (remediate docsRule mempty) "THE FINDINGS"
        T.count (promptText codeRule) underCode @?= 1
        underDocs @?= T.replace (promptText codeRule) (promptText docsRule) underCode
    , -- Each derived rule carries its tree's own splice as well as the code
      -- rule, and this leaf is the only route by which the splice reaches a
      -- fixer: the audit half gets the facts from the workflow input, which is
      -- long out of scope by the time a fixer runs on a ranked list of
      -- findings. The fix hierarchy each facts file states — source-of-truth
      -- first, proof layer second, direct code last — travels only here, and a
      -- red gate is cheapest to defeat by ignoring exactly that. One row per
      -- rule a fixer stands under, so the next grind's fixer is fenced by
      -- joining the table.
      testGroup
        "each fixer stands under the code rule and its tree's own splice"
        [ testCase ruleLabel $ do
            leafText <- onlyFlowLeafPrompt "remediate" (remediate rule fixerContinuation) "THE FINDINGS"
            report
              [ T.pack ruleLabel <> "'s fixer does not carry " <> label
              | (label, needle) <-
                  [ ("codeRule", promptText codeRule)
                  , ("its tree's splice", promptText spliced)
                  , ("the continuation clause", promptText fixerContinuation)
                  ]
              , not (T.isInfixOf needle leafText)
              ]
        | (ruleLabel, rule, spliced) <-
            [ ("paradoxRule", paradoxRule, paradoxFacts)
            , ("grindTestsRule", grindTestsRule, testsFacts)
            , ("grindLiveViewRule", grindLiveViewRule, liveViewFacts)
            , ("stackRule", stackRule, stackDisciplines)
            ]
        ]
    ]

-- | The retro report leaf's two contracts: the file it writes, and the grant
-- that lets it read the day first.
--
-- __The grant case is the grind lesson restated.__ A report leaf whose @date@
-- is denied still returns the whole retrospective, so the run reports success
-- with no file on disk — the failure is visible only to a person who goes
-- looking for a file that is not there. 'permitExec' over the exact command the
-- brief tells the leaf to run is what 'grindGrantTests' does, and for the same
-- reason: a membership check on the glob set passes on globs that match
-- nothing.
retroReportTests :: TestTree
retroReportTests =
  testGroup
    "the retro report"
    [ testCase "the brief names the file, the root, and the append rule" $
        report
          [ "retroReport does not say " <> tshow needle
          | needle <- ["RETRO-<YYYY-MM-DD>.md", "repository root", "append", "date +%Y-%m-%d"]
          , not (says retroReport needle)
          ]
    , testCase "retroGrant permits the date read as the brief spells it" $
        report
          [ "denied by retroGrant: " <> tshow line
          | line <- ["date +%Y-%m-%d"]
          , not (permitExec retroGrant line)
          ]
    , testCase "retroGrant denies what no report asked for" $
        report
          [ "retroGrant permits " <> tshow line
          | line <- ["rm -rf /", "mkdir -p docs", "git push origin master"]
          , permitExec retroGrant line
          ]
    , -- Both consumers of 'retroFlow' must be able to run the leaf. The
      -- standalone workflow carries 'retroGrant' bare; 'shipFeature' composes
      -- it with 'actingGrant', and a composition that dropped either half is
      -- exactly what a lattice join cannot catch on its own.
      testCase "ship-feature's grant covers the retro report and the build" $
        report
          [ "denied by ship-feature's grant: " <> tshow line
          | line <- ["date +%Y-%m-%d", "nix flake check"]
          , not (permitExec (wfGrant shipFeature) line)
          ]
    ]

-- | The merge between the work and the retrospective, read off the flow's
-- OUTPUT rather than off any leaf's prompt.
--
-- A pure merge is invisible everywhere else: it changes no leaf text, so
-- 'flowLeafPrompts' cannot see it, and a @dimap'@ reifies as a node with no
-- function in it, so @plan@ cannot either. Both sides of the merge are 'Text',
-- so swapping them is not a type error — it would wrap the retrospective
-- heading around the work and hand the next leaf a retrospective where it
-- wanted the change.
retrospectiveTests :: TestTree
retrospectiveTests =
  testGroup
    "retrospective"
    [ testCase "appends the retro under its own heading, below the work" $ do
        out <- flowOutput "retrospective" retrospective "THE WORK"
        out @?= "THE WORK\n\n## retrospective\n\n" <> leafAnswer
    ]

-- | One row per law of 'preambleOf': a set of preambles that breaks it, the
-- report in full, and the minimal repair of that same set.
--
-- Same shape as 'lensSetLaws' and for the same reason — a membership check
-- passes on a fixture that breaks two other laws as well, so the assertion is
-- on the whole report. The trailing-whitespace row is the one worth reading
-- twice: it is a __byte__ law, and no other check in this repository can see a
-- preamble's last character.
preambleLaws :: [(String, [Text], [Text], [Text])]
preambleLaws =
  [ ("non-empty", ["a", ""], ["empty preamble"], ["a", "b"])
  , ("pairwise distinct", ["a", "a"], ["duplicate preambles"], ["a", "b"])
  ,
    ( "no trailing whitespace"
    , ["a", "b\n"]
    , ["preamble ends in whitespace"]
    , ["a", "b"]
    )
  ]

preambleViolationsTests :: TestTree
preambleViolationsTests =
  testGroup
    "preambleViolations"
    [ testGroup
      law
      [ testCase "a set that breaks it reports exactly this" $
          preambleViolations broken @?= expected
      , testCase "the minimal repair clears the report" $
          preambleViolations repaired @?= []
      ]
    | (law, broken, expected, repaired) <- preambleLaws
    ]

-- | The outcome the change-review path had no way to report: __there was no
-- change__.
--
-- Every lens on that path is written for a diff, and each one has a clean-change
-- ending it is told to fire — @Already sequential.@, @Nothing blocking.@ — so a
-- panel handed an empty tree produces the same artifact as a panel handed a
-- clean one. That is not a hypothetical: it is what most of the review of this
-- very change did, pointed at a working tree with nothing in it, and the run
-- read as a change with nothing wrong.
--
-- The fence is a token per stage, because the fix is prose and prose is what
-- drifts. It cannot assert that a model obeys the sentence; what it can assert
-- is that the sentence is still in the text the stage ships, which is the half
-- that goes missing in an edit. The synthesis row is doubled — both verdicts —
-- since naming one without the other leaves the reducer no way to keep them
-- apart.
emptyChangeTests :: TestTree
emptyChangeTests =
  testGroup
    "the empty change"
    [ testCase "every stage that reads a diff can say there was none" $
        report
          [ stage <> " does not state the empty-change outcome: " <> token
          | (stage, body, token) <-
              [ ("preambleOf AtChange", preambleOf AtChange, "Nothing to review.")
              , ("prompts/review/units.md", promptText reviewUnits, "## no change")
              , ("prompts/review/sequence.md", promptText reviewSequence, "## no change")
              , ("prompts/review/synthesis.md", promptText reviewSynthesis, "Nothing to review.")
              , ("prompts/review/synthesis.md", promptText reviewSynthesis, "Nothing blocking.")
              ]
          , not (T.isInfixOf token body)
          ]
    ]

orientTests :: TestTree
orientTests =
  testGroup
    "orient"
    [ -- Over the ENUMERATION, so a new orientation answers the laws on arrival
      -- rather than when someone remembers to add it here.
      testCase "every orientation's preamble holds all three laws" $
        let ps = map preambleOf ([minBound .. maxBound] :: [Orientation])
         in assertBool
              ("violates: " <> show (preambleViolations ps))
              (null (preambleViolations ps))
    , -- The guard on the assertion above: it defends the hand-listed rows
      -- below, which do go stale, not the quantification, which does not.
      testCase "Orientation enumerates 4 constructors" $
        length ([minBound .. maxBound] :: [Orientation]) @?= 4
    , -- The join as an OBSERVABLE property of the rendered text, not as a
      -- restatement of 'orient'. Asserting @orient o s == preambleOf o <> …@
      -- would be the definition written twice and could never fail; this reads
      -- the result and says what separates the two halves, so it stays a real
      -- statement however 'orient' is written. It goes red on a preamble ending
      -- in a newline, which is what makes the third law load-bearing rather
      -- than decorative.
      testCase "every orientation leaves exactly one blank line above the account" $
        mapM_
          ( \o ->
              let rendered = orient o "ACCOUNT"
               in do
                    assertBool
                      (show o <> " does not end with one blank line then the account")
                      (T.isSuffixOf "\n\nACCOUNT" rendered)
                    assertBool
                      (show o <> " leaves more than one blank line")
                      (not (T.isSuffixOf "\n\n\nACCOUNT" rendered))
          )
          ([minBound .. maxBound] :: [Orientation])
    , -- The named reframings ARE orientations, not copies that drifted.
      -- 'reframingTests' pins their bytes; this pins which constructor each is.
      testCase "each named reframing is its orientation" $ do
        asReviewSubject "x" @?= orient AtChange "x"
        asRetroSubject "x" @?= orient AtRecord "x"
        asDocsSubject "x" @?= orient AtDocs "x"
    , -- The empty-diff clause, as bytes the panels behind 'asReviewSubject'
      -- actually receive. @grind-tests@ points an 84-leaf review pass at its
      -- fixer's change; a fixer that touched nothing leaves that panel a clean
      -- tree and a summary, and without this instruction the leaves review the
      -- account as though it were the diff and call it a completed pass. A
      -- later edit that drops the clause fails here, in CI — nothing else
      -- reads these bytes, so nothing else can.
      --
      -- And the GENERIC orientation carries no artifact exclusion, asserted
      -- from the negative side — 'preambleOf'\'s AtChange note is the
      -- canonical history of the two shared exclusion shapes that died. The
      -- run's own artifacts are excluded at the call site instead — the case
      -- below reads that frame.
      testCase "the change orientation carries the no-change-to-audit clause and no exclusion" $ do
        assertBool
          "preambleOf AtChange does not say \"no change to audit\""
          ("no change to audit" `T.isInfixOf` preambleOf AtChange)
        assertBool
          "preambleOf AtChange excludes docs/audits/ — an audit-report-only change would go unreviewed everywhere"
          (not ("docs/audits" `T.isInfixOf` preambleOf AtChange))
    , -- The own-artifacts frame @grind-tests@ reframes its review pass
      -- through, in both directions: it names the report PREFIX as the run's
      -- own product, keeps it out of the no-change decision, says outright
      -- that every other file — same directory included — is part of the
      -- change, and it is exactly the generic frame above the exclusion — so
      -- the exclusion exists nowhere except where a run says its own
      -- artifacts are. The shipped prefix is pinned where the workflow passes
      -- it ("grind-tests' review pass reads through the own-artifacts frame").
      testCase "asReviewSubjectIgnoring names the run's own artifacts above the generic frame" $ do
        let framed = asReviewSubjectIgnoring "docs/audits/grind-synthetic-" "ACCOUNT"
        report
          [ "the ignoring frame does not say " <> tshow needle
          | needle <-
              [ "files whose path starts with `docs/audits/grind-synthetic-` are the run's own product"
              , "out of the no-change decision"
              , "a tree whose only edits are its own artifacts has no change to audit"
              , "including any other file in the same directory, is part of the change"
              ]
          , not (needle `T.isInfixOf` framed)
          ]
        assertBool
          "the exclusion does not sit ABOVE the untouched generic frame"
          (("\n\n" <> asReviewSubject "ACCOUNT") `T.isSuffixOf` framed)
    , -- What keeps 'reframings' honest. Golden coverage is only as good as the
      -- list naming the goldens, and that list is hand-written: a fourth
      -- orientation would ship with its bytes unfenced and every existing test
      -- still green. Compared as SETS in both directions, so a missing entry
      -- and a stale one both fail.
      testCase "every orientation has a recorded frame, and no frame is orphaned" $
        let framed = [reframe summaryMarker | (_, reframe, _) <- reframings]
            oriented = [orient o summaryMarker | o <- [minBound .. maxBound] :: [Orientation]]
         in do
              (framed \\ oriented) @?= []
              (oriented \\ framed) @?= []
    ]

-- | A stand-in body. Every law 'lensSetViolations' states is a statement about
-- NAMES, so the body here is noise — and an empty one says so, where naming a
-- production prompt would suggest these fixtures had something to do with that
-- reviewer.
anyPrompt :: Prompt
anyPrompt = prompt ""

-- | One row per law: a set that breaks it, the report breaking it produces __in
-- full__, and the __minimal repair__ — the smallest edit to that same set which
-- makes it lawful.
--
-- __The full report, not a membership check.__ \"This fixture has exactly one
-- defect\" is a claim about the whole report, and @elem@ cannot see it: it
-- passes on a fixture breaking two other laws as well. Written out, the
-- non-empty row shows a fact rather than hiding it — @[]@ reports the missing
-- ponytail too, and no fixture can break emptiness alone, because a set with no
-- lenses has no ponytail lens either.
--
-- __A repair per row, not one shared well-formed set.__ Three rows pointed at
-- one lawful fixture are three spellings of a single assertion, and the two
-- laws not under test in a row would carry it. Each repair here is reached from
-- that row's own broken set by the one edit its own law asks for, so the row is
-- the only thing that can make it pass.
lensSetLaws :: [(String, [(LeafName, Prompt)], [Text], [(LeafName, Prompt)])]
lensSetLaws =
  [
    ( "non-empty"
    , []
    , ["empty lens set", "no ponytail lens"]
    , [("ponytail", anyPrompt)]
    )
  ,
    ( "pairwise distinct"
    , [("correctness", anyPrompt), ("ponytail", anyPrompt), ("correctness", anyPrompt)]
    , ["duplicate lens names: [\"correctness\"]"]
    , [("correctness", anyPrompt), ("ponytail", anyPrompt)]
    )
  ,
    ( "ponytail present"
    , [("correctness", anyPrompt), ("security", anyPrompt)]
    , ["no ponytail lens"]
    , [("correctness", anyPrompt), ("security", anyPrompt), ("ponytail", anyPrompt)]
    )
  ]

lensSetViolationsTests :: TestTree
lensSetViolationsTests =
  testGroup
    "lensSetViolations"
    [ testGroup
      law
      [ testCase "a set that breaks it reports exactly this" $
          lensSetViolations broken @?= expected
      , testCase "the minimal repair clears the report" $
          lensSetViolations repaired @?= []
      ]
    | (law, broken, expected, repaired) <- lensSetLaws
    ]

-- | The lens table this repository intends to ship, written out flat: every
-- @(name, body)@ pair named separately, for every 'Subject'.
--
-- __Why a second copy.__ 'lensesOf' shares one @codeLenses@ helper between two
-- constructors, so a body dropped or swapped inside that helper leaves every
-- name in place. Nothing else here can see a lens body: the assertions below
-- read @fst@, and @plan@ renders a flow skeleton — node kinds, refs and leaf
-- names — with no prompt text in it at all. This table is the independent
-- statement the constructed one is checked against, and it is written flat
-- rather than reusing a helper of its own so that no restructuring of
-- 'lensesOf' can move both sides at once.
--
-- __The bodies are NAMED, not copied.__ Six of them are files under the
-- gitignored @prompts\/upstream@, and recording their bytes would make this
-- check go red on @nix flake update@ — the failure mode
-- @test\/golden\/prompt-lint-brief.txt@ is written to avoid. Naming a body pins
-- which brief each lens carries without pinning what upstream wrote in it.
expectedLensesOf :: Subject -> [(LeafName, Prompt)]
expectedLensesOf subject = case subject of
  OfDiff ->
    [ ("correctness", reviewCorrectness)
    , ("security", codeReviewerSecurity)
    , ("tests", reviewTests)
    , ("performance", perfReviewer)
    , ("haskell", haskellOfHouse)
    , ("ponytail", ponytailReviewRubric)
    , ("doctrine", codeReview)
    , ("discipline", disciplineOfPanel)
    ]
  OfChange ->
    [ ("correctness", reviewCorrectness)
    , ("security", codeReviewerSecurity)
    , ("tests", reviewTests)
    , ("performance", perfReviewer)
    , ("haskell", haskellOfHouse)
    , ("ponytail", ponytailAuditRubric)
    , ("doctrine", codeReview)
    , ("discipline", disciplineOfPanel)
    , ("architecture", architectureOfChange)
    ]
  OfDocs ->
    [ ("accuracy", docsAccuracy)
    , ("completeness", docsCompleteness)
    , ("structure", docsStructure)
    , ("slop", slopOfDocs)
    , ("ponytail", ponytailOfDocs)
    ]
  OfTree ->
    [ ("correctness", ofTree reviewCorrectness)
    , ("tests", ofTree reviewTests)
    , ("stubs", reporting grindStubs)
    , ("vacuous", reporting grindVacuous)
    , ("dry", reporting grindDry)
    , ("hardcodings", reporting grindHardcodings)
    , ("refactor", ofTree reviewComplexity)
    , -- 'reporting' alone, NOT 'ofTree': the architecture rubric opens by
      -- saying it reads a whole tree, so the tree clause would be the second
      -- copy of a sentence its own file already carries.
      ("architecture", reporting reviewArchitecture)
    , ("performance", ofTree perfReviewer)
    , ("ponytail", ponytailOfTree)
    ]

-- | Where a lens set disagrees with the table it is supposed to be: one 'Text'
-- per lens carrying the wrong body, and @[]@ for agreement.
--
-- Equality is over the __full__ rendered text. Only the message is abbreviated,
-- because a report that printed two 20 KB briefs verbatim is a report nobody
-- reads.
lensBodyMismatches :: [(LeafName, Prompt)] -> [(LeafName, Prompt)] -> [Text]
lensBodyMismatches expected actual
  | names expected /= names actual =
      [ "lens names differ: expected "
          <> tshow (names expected)
          <> ", got "
          <> tshow (names actual)
      ]
  | otherwise =
      [ leafNameText name
          <> " carries "
          <> bodyTag (promptText got)
          <> ", expected "
          <> bodyTag (promptText want)
      | ((name, want), (_, got)) <- zip expected actual
      , promptText want /= promptText got
      ]
  where
    names = map (leafNameText . fst)

-- | Enough of a body to identify it in a failure message, and no more. Never
-- what equality is decided on.
bodyTag :: Text -> Text
bodyTag body =
  tshow (T.length body) <> " chars starting " <> tshow (T.take 48 (T.unwords (T.words body)))

tshow :: (Show a) => a -> Text
tshow = T.pack . show

-- | Does a prompt contain this text? For fencing a rule a composed lens is
-- supposed to carry, where the whole body is far too big to assert on.
says :: Prompt -> Text -> Bool
says p needle = T.isInfixOf needle (promptText p)

-- | 'says', with whitespace collapsed on both sides.
--
-- For a needle that is a SENTENCE rather than a token. Both these files are
-- hard-wrapped markdown, so \"no reachable path\" is a phrase that exists in the
-- prose and does not exist in the bytes — it straddles a line break. Rewrapping
-- a paragraph is not a change to what a prompt says, and a fence that goes red
-- on rewrapping is one somebody regenerates.
saysLoosely :: Prompt -> Text -> Bool
saysLoosely p needle = T.isInfixOf (norm needle) (norm (promptText p))
  where
    norm = T.unwords . T.words

-- | Run an assertion at every 'Subject', naming the one that failed. A new
-- constructor is covered on arrival rather than when someone remembers.
atEverySubject :: (Subject -> [Text]) -> Assertion
atEverySubject complaints =
  case [ tshow s <> ": " <> T.intercalate "; " cs
       | s <- [minBound .. maxBound :: Subject]
       , let cs = complaints s
       , not (null cs)
       ] of
    [] -> pure ()
    problems -> assertFailure (T.unpack (T.intercalate "\n" problems))

lensesOfTests :: TestTree
lensesOfTests =
  testGroup
    "lensesOf"
    [ -- No @length … \@?= N@ cases here: every lens set below is asserted as a
      -- whole name LIST, which fixes the count and the order and the spelling
      -- at once. A count beside it is a second, weaker statement of the same
      -- thing, and one more line to edit when a lens lands.
      testCase "OfDiff lens names" $
        map (leafNameText . fst) (lensesOf OfDiff)
          @?= [ "correctness"
              , "security"
              , "tests"
              , "performance"
              , "haskell"
              , "ponytail"
              , "doctrine"
              , "discipline"
              ]
    , testCase "OfChange lens names" $
        map (leafNameText . fst) (lensesOf OfChange)
          @?= [ "correctness"
              , "security"
              , "tests"
              , "performance"
              , "haskell"
              , "ponytail"
              , "doctrine"
              , "discipline"
              , "architecture"
              ]
    , testCase "OfDocs lens names" $
        map (leafNameText . fst) (lensesOf OfDocs)
          @?= [ "accuracy"
              , "completeness"
              , "structure"
              , "slop"
              , "ponytail"
              ]
    , -- ORDER is what this asserts, and here order is semantic rather than
      -- cosmetic. @Incite.Review.spread@ pairs one backend per lens by
      -- position, so moving a row moves which model audits that lens, with no
      -- type error and no name anywhere changing. A set comparison could not
      -- see it and neither could a count.
      testCase "OfTree lens names, in the order spread pairs them to backends" $
        map (leafNameText . fst) (lensesOf OfTree)
          @?= [ "correctness"
              , "tests"
              , "stubs"
              , "vacuous"
              , "dry"
              , "hardcodings"
              , "refactor"
              , "architecture"
              , "performance"
              , "ponytail"
              ]
    , -- The point of the docs subject, as an assertion rather than a comment:
      -- its lenses are its own, and @ponytail@ is the only name it shares with
      -- a code panel because every artifact admits that one question.
      testCase "OfDocs shares only ponytail with OfDiff" $
        filter (`elem` map (leafNameText . fst) (lensesOf OfDiff))
          (map (leafNameText . fst) (lensesOf OfDocs))
          @?= ["ponytail"]
    , testCase "OfChange is OfDiff plus architecture" $
        map (leafNameText . fst) (lensesOf OfChange)
          @?= map (leafNameText . fst) (lensesOf OfDiff) <> ["architecture"]
    , -- Over the ENUMERATION, not a hardcoded list: a new constructor is
      -- covered on arrival rather than when someone remembers to add it here.
      --
      -- This subsumes the per-subject duplicate-name cases that used to sit
      -- above it, and strictly: they read a second copy of the distinctness law
      -- written here in the test file, and they covered two subjects where this
      -- covers every one. 'lensSetViolations' is now the single place any of the
      -- three laws is written down.
      testCase "every subject holds all three laws" $
        mapM_
          ( \s ->
              assertBool
                (show s <> " violates: " <> show (lensSetViolations (lensesOf s)))
                (null (lensSetViolations (lensesOf s)))
          )
          [minBound .. maxBound :: Subject]
    , -- The second half of the ponytail law, which nothing else here reads. The
      -- quantified assertion above sees that every subject HAS a ponytail lens;
      -- that each one picks the rubric pointed at it is a claim about bodies,
      -- and every other case in this group reads @fst@. Point two subjects at
      -- one rubric and this is what says so.
      --
      -- __Written as the two laws rather than as the counts that stood in for
      -- them.__ @(length, length . nub) \@?= (3, 3)@ said both things at once
      -- and needed an arithmetic edit on every new constructor — and a
      -- constructor added without that edit went red for the count rather than
      -- for the law, which is a different sentence. Quantified over
      -- @[minBound ..]@, a fourth subject is covered on arrival and the numbers
      -- are nobody's to maintain.
      testCase "every subject contributes exactly one ponytail rubric, and no two share one" $
        let rubrics =
              [ (s, promptText body)
              | s <- [minBound .. maxBound :: Subject]
              , (name, body) <- lensesOf s
              , leafNameText name == "ponytail"
              ]
            bodies = map snd rubrics
         in do
              -- One per subject, in subject order: this is the arithmetic the
              -- count used to do, said as a statement about which subjects
              -- answered rather than about how many did.
              map fst rubrics @?= [minBound .. maxBound :: Subject]
              report
                [ tshow s <> " shares its ponytail rubric with another subject: " <> bodyTag b
                | (s, b) <- rubrics
                , length (filter (== b) bodies) > 1
                ]
    , -- The fence on the BODIES. Every assertion above reads @fst@, and so does
      -- every other check this repository has: swap two entries inside the
      -- shared @codeLenses@ helper and the names, the plan skeletons and the
      -- cost estimates are all byte-identical while two panels quietly run the
      -- wrong reviewer. This is the only check with the resolution to catch
      -- that, so it is the one that must be refutable — see
      -- 'expectedLensesOf'.
      testCase "every subject carries the bodies its lenses name" $
        atEverySubject (\s -> lensBodyMismatches (expectedLensesOf s) (lensesOf s))
    , -- The guard that keeps the fence above load-bearing. Body equality can
      -- only refute a swap while the bodies differ; two lenses rendering the
      -- same text would make a permutation of them undetectable — and would
      -- already be two reviewers doing one reviewer's work under two names.
      testCase "no subject repeats a lens body" $
        atEverySubject $ \s ->
          let bodies = map (promptText . snd) (lensesOf s)
              repeats = bodies \\ nub bodies
           in map (("repeated lens body: " <>) . bodyTag) (nub repeats)
    ]

-- | __The fess rubric never runs on codex.__ "Incite.Review".'admits' is the
-- rule; these are its two halves, and neither is worth much alone.
--
-- The rule is stated over lens BODIES, so it is only as good as its reach: a
-- rule that matched nothing would pass every panel forever. So the first case
-- asserts what it catches — the docs panel's @accuracy@ lens, which is 'fess'
-- pointed at prose under a name no list of \"the fess lenses\" would have had —
-- and the second asserts that what it catches never reaches a built flow.
--
-- The second is the one that binds. 'admits' is a predicate somebody has to
-- CALL, and the tiers that build a cross-product are where the call lives; a
-- future tier that fans lenses across backends its own way would satisfy the
-- predicate's own tests and still build the leaf. Reading the leaf names out of
-- the flows themselves is the check that does not care how they were built.
codexFessTests :: TestTree
codexFessTests =
  testGroup
    "the fess rubric never runs on codex"
    [ testCase "the rule catches the docs panel's accuracy lens, which is fess renamed" $
        forbiddenPairings backendNames (lensesOf OfDocs) @?= ["accuracy@codex"]
    , testCase "and catches fess itself, under any name a tier gives it" $
        forbiddenPairings backendNames [("honesty", fess)] @?= ["honesty@codex"]
    , testCase "a lens that does not carry the rubric is admitted by every backend" $
        forbiddenPairings backendNames [("tests", reviewTests)] @?= []
    , -- Every workflow, not only the ones known to hold a fess lens: the point
      -- is that no tier can build the pairing, including one written later.
      --
      -- Over RESOLVED SCOPES, not leaf names. Only @spread@ suffixes
      -- @\@backend@ onto a name, and the two tiers that pin a fess leaf by hand
      -- — 'reviewLite' and 'fessAudit' — name it bare @fess@. A name reader is
      -- therefore blind at exactly the two sites where reverting the pin would
      -- land: it passed over nothing while @fess@ sat on codex under a name
      -- carrying no @\@@ at all. 'scopedLeaves' reads where a leaf RUNS.
      testCase "no workflow builds a leaf that pairs the rubric with codex" $
        report
          [ wfName wf <> " runs " <> n <> " on " <> agent
          | wf <- mirrorWorkflows
          , (n, agent) <- scopedLeaves (wfFlow wf)
          , fessNamed n
          , isCodex agent
          ]
    , -- The two guards on the case above, and it needs both: it is quantified
      -- over the fess-carrying leaves it can NAME, and refutes through a
      -- predicate on an agent string it has to be able to MATCH. A rename on
      -- either side leaves it passing over nothing.
      testCase "the reader finds the fess leaves, and knows codex when it sees it" $ do
        report
          [ "no fess-named leaf in " <> wfName wf
          | wf <- [reviewLite, fessAudit, reviewDocs]
          , not (any (fessNamed . fst) (scopedLeaves (wfFlow wf)))
          ]
        assertBool "isCodex matches no agent any workflow resolves to" $
          any (isCodex . snd) (concatMap (scopedLeaves . wfFlow) mirrorWorkflows)
    ]
  where
    backendNames = map fst (NE.toList backends)
    isCodex a = backendOf a == "codex"
    -- The leaves whose body is the rubric or a reorientation of it, by the
    -- names the tiers give them: @fess@ in the two code tiers, @accuracy@ in the
    -- docs panel. Panels suffix @\@backend@, so this matches a prefix.
    fessNamed n = any (`T.isPrefixOf` n) ["fess", "accuracy"]

-- | The whole grind panel: the tree subject's lenses and the emission lenses
-- that are appended to them, in the order @grind-paradox@ hands them to
-- @spread@.
grindLenses :: [(LeafName, Prompt)]
grindLenses = lensesOf OfTree <> emissionLenses

-- | 'emissionLenses' written out flat, for the reason 'expectedLensesOf' is
-- written out flat — and with one gap this closes that that one cannot.
--
-- 'expectedLensesOf' is total in 'Subject' and GHC forces a case per
-- constructor. 'emissionLenses' is deliberately __not__ a subject (see
-- "Incite.Review".'emissionLenses'), so nothing forces a second statement of
-- it: swap two entries and every name, plan skeleton and cost estimate is
-- byte-identical while two lenses run each other's rubric. This is the
-- independent copy that says so.
expectedEmissionLenses :: [(LeafName, Prompt)]
expectedEmissionLenses =
  [ ("target-consistency", reporting grindTargetConsistency)
  , ("validator-calls", reporting grindValidatorCalls)
  , ("codegen-gaps", reporting grindCodegenGaps)
  , ("emitted-code", reporting grindEmittedCode)
  ]

-- | The finding contract every grind lens must carry, written HERE as literals
-- rather than read off 'reporting'.
--
-- Deriving it from the binding under test would make the law @x@ contains @x@:
-- it would pass with 'reporting' replaced by 'id', which is the one mutation it
-- exists to catch. Written out, it is a statement about what the panel sends,
-- and it goes red the moment the contract stops being spliced.
--
-- The phrases are 'Incite.Prompts.reviewSynthesis'\'s own admission test —
-- location, what is wrong, what fixes it — because a finding missing any of
-- them is one the reduction behind these lenses drops unread.
grindContract :: [Text]
grindContract = ["file:line", "the consequence", "the concrete fix"]

-- | The sentences 'Incite.Prompts.reviewSynthesis' uses to say what it DROPS,
-- paired with what 'reporting' must therefore ask a lens to supply.
--
-- __Both sides asserted, like 'voidedSentences'.__ 'reporting' is a producer
-- written against one consumer, and its correctness is a statement about text it
-- does not contain: reword the reducer's drop rule and the contract silently
-- stops matching it, with no error anywhere. Asserting the reducer's own words
-- as well is what makes this go red on the upstream edit rather than staying
-- green while lenses write findings the next stage discards.
--
-- This pair is where a real defect lived: the contract asked for location, what
-- is wrong, and the fix — the reducer's OUTPUT format — while the reducer ADMITS
-- on location, a reachable path, and a consequence. A lens obeying the contract
-- could produce a finding that was complete by it and dropped by the stage after
-- it.
synthesisAdmits :: [(Text, Text)]
synthesisAdmits =
  [ ("no location", "file:line")
  , ("no reachable path", "reader has to be able to reach it")
  , ("no stated consequence", "the consequence")
  ]

-- | Every leaf name a 'Flow' reaches, read off its skeleton.
--
-- The skeleton is what @agent-functor plan@ renders, so this is the same view
-- an operator gets before spending anything — and the only one that can count
-- leaves without running them.
leafNames :: Flow Text Text -> [Text]
leafNames flow = [leafNameOf t | FLeaf t <- toList (skeleton (toSkeleton flow))]

-- | How many of a 'Flow'\'s loops carry the unbounded sentinel fuel —
-- @maxBound \`div\` 2@, the value 'orchestrateWith' assigns when its ceiling is
-- 'Nothing'. Read off the skeleton the way 'leafNames' is, so it counts what
-- ships rather than restating any source the flow was built from.
unboundedLoopCount :: Flow Text Text -> Int
unboundedLoopCount flow =
  length
    [ ()
    | FLoop f _ <- toList (skeleton (toSkeleton flow))
    , fuelMax f == maxBound `div` 2
    ]

-- | Every leaf as @\"kind:name\"@ — the run-graph identity, which is the only
-- view that distinguishes a check WE run from a question we ask. A gate written
-- as an 'Agent.Op.Ask' rather than an 'Agent.Op.Exec' sits in the same place in
-- the ordering and protects nothing unattended, so the name alone cannot say
-- whether a gate is real.
leafKinds :: Flow Text Text -> [Text]
leafKinds flow = [opTagPrefixed t | FLeaf t <- toList (skeleton (toSkeleton flow))]

-- | Every leaf a 'Flow' reaches, paired with the __agent it resolves to__:
-- @backend@, or @backend\/model@ where a model is named.
--
-- 'Agent.Flow.foldLeavesScoped' threads the enclosing @withBackend@ and
-- 'Agent.Flow.withMode' declarations exactly as @Agent.Interpret.interpretWith@
-- threads them, so this is where a leaf actually runs rather than where a
-- reader of the source believes it does.
--
-- __Nothing else in this repository can see a backend scope.__ It changes no
-- leaf name, no leaf text, no node count and no cost estimate. So a pin lost in
-- a refactor, or added with no argument for it, is invisible to every other
-- check here — and both happened in one commit.
scopedLeaves :: Flow Text Text -> [(Text, Text)]
scopedLeaves = foldLeavesScoped (\sc op -> [(leafNameOf (opTag op), agentOf sc)])
  where
    agentOf = maybe runDefault agentSpecText . scopeAgent

-- | The backend half of what 'scopedLeaves' reports. 'agentSpecText' renders a
-- named model as @backend\/model@, so a pin like @withBackend codex someModel@
-- has to be recognised as codex exactly as readily as the bare one — and the
-- prose that attributes a lens to a backend names the backend, not the model.
backendOf :: Text -> Text
backendOf = T.takeWhile (/= '/')

-- | What 'scopedLeaves' reports for a leaf under no backend scope at all: it
-- runs on whatever @--backend@ the run was started with.
runDefault :: Text
runDefault = "<run default>"

-- | The leaves a 'Flow' runs in the backend's read-only plan mode.
--
-- The other half of 'scopedLeaves', and the half that says a reviewer cannot
-- edit what it is reading. Read off the resolved 'Scope' rather than off the
-- 'FScope' nodes, so it answers what the runner will do rather than how many
-- wrappers were written to say it.
readOnlyLeaves :: Flow Text Text -> [Text]
readOnlyLeaves =
  foldLeavesScoped (\sc op -> [leafNameOf (opTag op) | scopeMode sc == Plan])

-- | Every scope declaration a 'Flow' __reifies__, in skeleton order — the
-- @scope …@ lines @agent-functor plan@ prints.
--
-- 'readOnlyLeaves' says what a leaf runs under; this says how many nodes were
-- spent saying it. 'Agent.Flow.withMode' is @WithScope . ModeScope@ and
-- 'Agent.Flow.Skeleton.toSkeleton' reifies every @WithScope@ as its own node,
-- so a wrapper around a fan-out whose leaves are already scoped is not a no-op:
-- it is a plan line that constrains nothing under it. This is the only view
-- that can tell the two apart.
scopeDecls :: Flow Text Text -> [Text]
scopeDecls flow = [scopeDeclText d | FScope d _ <- toList (skeleton (toSkeleton flow))]

-- | The panel @grind-paradox@ fans out, and the combinator that fans it.
--
-- __Nothing else in this repository can see any of this.__ @plan@ renders leaf
-- names and no prompt text, so a lens whose body lost its output contract plans
-- identically; @cost@ counts leaves and cannot say which lens sits on which
-- model. The laws below are where the panel's shape is written down.
grindPanelTests :: TestTree
grindPanelTests =
  testGroup
    "grind panel"
    [ -- The union is what the workflow actually fans out, and neither half is
      -- checked by 'lensesOfTests' — that quantifies over 'Subject', and
      -- 'emissionLenses' is deliberately not one. A name colliding across the
      -- two halves would give two reviewers one @lens\@backend@ block.
      testCase "the union of tree lenses and emission lenses holds all three laws" $
        lensSetViolations grindLenses @?= []
    , -- The contract against the reducer it is written for. See
      -- 'synthesisAdmits': the producer and the consumer are two files, and
      -- nothing but this reads them together.
      testCase "the contract supplies every field the synthesis admits on" $
        report
          [ complaint
          | (dropsOn, asksFor) <- synthesisAdmits
          , complaint <-
              concat
                [ [ "reviewSynthesis no longer drops on " <> tshow dropsOn
                  | not (saysLoosely reviewSynthesis dropsOn)
                  ]
                , [ "reporting does not ask for " <> tshow asksFor
                  | not (saysLoosely (reporting anyPrompt) asksFor)
                  ]
                ]
          ]
    , -- The validation step beside those drop rules is prose in the reducer
      -- with no producer coupling at all, so nothing else notices its
      -- deletion. Two tokens it cannot lose: findings checked against what
      -- the code actually says, and reading — not building or running — as
      -- the only admissible evidence.
      testCase "the synthesis validates findings against the code, by reading" $
        report
          [ "reviewSynthesis no longer says " <> tshow needle
          | needle <- ["the code contradicts", "no build, no test run"]
          , not (saysLoosely reviewSynthesis needle)
          ]
    , testCase "emission lenses carry the bodies they name" $
        report (lensBodyMismatches expectedEmissionLenses emissionLenses)
    , -- __The generalization, on a check list no shipped grind has.__ Every
      -- grant case above evaluates 'grindGrantFor' only at 'grindChecks', so a
      -- 'grindGrantFor' that ignored its argument and returned 'grindGrant'
      -- would pass them all — and would hand the next grind a gate whose every
      -- check is denied inside the run. Synthetic heads that are not @nix@ are
      -- what refute that: the derived grant must permit them, keep the
      -- synthesis leaf's two, deny the trio, and NOT permit the paradox heads
      -- its argument never named.
      testCase "grindGrantFor derives its grant from the checks it is given" $
        let checks =
              [ ("fmt", "gofmt" :| ["-l", "."])
              , ("lint", "golangci-lint" :| ["run", "./..."])
              ] ::
                [(LeafName, NonEmpty Text)]
            grant = grindGrantFor checks
         in report
              ( concat
                  [ [ "denied by the derived grant: " <> tshow line
                    | (_, cmd) <- checks
                    , let line = T.unwords (NE.toList cmd)
                    , not (permitExec grant line)
                    ]
                  , [ "denied by the derived grant: " <> tshow line
                    | line <- ["date +%Y-%m-%d", "mkdir -p " <> auditReportDir]
                    , not (permitExec grant line)
                    ]
                  , [ "the derived grant permits " <> tshow line
                    | line <-
                        [ "rm -rf /"
                        , "git push origin master"
                        , "curl example.com"
                        , -- The paradox check head. Permitting it here means the
                          -- derivation read 'grindChecks' instead of its argument.
                          "nix develop --command bash -c 'cabal build'"
                        ]
                    , permitExec grant line
                    ]
                  ]
              )
    , -- __The roster interpolation, on a roster no shipped grind has.__ The
      -- paradox fences only ever evaluate 'grindSynthesisOver' at the shipped
      -- specialization, so a body that interpolated a hard-wired roster — or
      -- dropped a lens, or doubled one — ships green there and surfaces two
      -- steps later attributed to the wrong change. Distinctive synthetic names
      -- pin that the render names the grind's report path and every roster
      -- lens exactly once, and counts the roster it was given.
      testCase "grindSynthesisOver names the grind and every roster lens exactly once" $
        let roster = ["alpha-lens", "beta-lens", "gamma-lens"] :: [LeafName]
            rendered = promptText (grindSynthesisOver "grind-synthetic" roster)
         in report
              ( concat
                  [ [ "the report path does not name the grind"
                    | T.count "docs/audits/grind-synthetic-<YYYY-MM-DD>.md" rendered /= 1
                    ]
                  , [ "roster lens " <> leafNameText n <> " listed " <> tshow k <> " times"
                    | n <- roster
                    , let k = T.count ("- " <> leafNameText n) rendered
                    , k /= 1
                    ]
                  , [ "the roster count is not derived from the roster"
                    | not ("These 3 lenses were sent" `T.isInfixOf` T.unwords (T.words rendered))
                    ]
                  , -- The wrong-checkout refusal. The brief must carry the
                    -- line, and must tell the synthesis to OPEN its refusal
                    -- with it — that opening is the contract the flow's
                    -- refusal stop ('decideFactsResolved') reads, so a brief
                    -- that keeps the line but drops the opening instruction
                    -- leaves a stop nothing ever triggers, and the fixer, the
                    -- review pass and the gate go to work in a tree the audit
                    -- never read.
                    [ "the brief does not refuse on " <> tshow factsRefusalLine
                    | not (factsRefusalLine `T.isInfixOf` rendered)
                    ]
                  , [ "the brief does not tell the refusal to open with the line the stop reads"
                    | not ("Open your answer with the line" `T.isInfixOf` rendered)
                    ]
                  ]
              )
    , -- __The rule derivation, on facts no shipped grind has.__ 'paradoxRule'
      -- and 'grindTestsRule' are both 'grindRule' applications, and the fixer
      -- fences only evaluate those specializations — a 'grindRule' that ignored
      -- its argument and spliced one grind's facts would pass on that grind
      -- alone. Equality rather than infix: the rule IS the code rule above the
      -- facts, under one blank line, and nothing else.
      testCase "grindRule is the code rule above exactly the facts it is given" $
        promptText (grindRule "THE SYNTHETIC FACTS")
          @?= promptText codeRule <> "\n\nTHE SYNTHETIC FACTS"
    , -- __What 'grindFlow' derives from its spec, on a spec no shipped grind
      -- has.__ The fences below pin both shipped grinds' leaves and briefs, but
      -- each supplies exactly the derived synthesis — so a 'grindFlow' that let
      -- a spec's brief and its lens table drift apart, or dropped the suffix
      -- seam the next grind's ranking clause needs, or repaired under facts the
      -- audit never read, would ship green there. Read off the flow's own
      -- leaves: the synthesis brief is 'grindSynthesisOver' at the spec's name
      -- and lens table, a suffix lands below it as the brief's final paragraph
      -- under exactly one blank-line seam and moves nothing else, the fixer
      -- stands under 'grindRule' at the same facts, and the facts sit above
      -- the caller's steer. The seam is what keeps a ranking clause from
      -- fusing onto the derived brief's closing sentence — a paragraph the
      -- model reads as one sentence's tail is a rule it never applies.
      testCase "grindFlow derives its synthesis and its fixer's rule from the spec" $ do
        let lenses = [("alpha-lens", "ALPHA?"), ("beta-lens", "BETA?")] :: [(LeafName, Prompt)]
            specWith suffix =
              GrindSpec
                { gsName = "grind-synthetic"
                , gsFacts = "THE SYNTHETIC FACTS"
                , gsLenses = lenses
                , gsSynthesisSuffix = suffix
                , gsPins = []
                }
            -- Total: name each of the four prompts the flow must send (one per
            -- lens, the synthesis, the fixer) or fail with the count, rather
            -- than reaching for @!!@\/@head@\/@last@ — the bare-partial idiom
            -- 'onlyFlowLeafPrompt' exists to retire, which had crept back here.
            shaped label sent = case sent of
              [firstLens, _, synthesis, fixer] -> pure (firstLens, synthesis, fixer)
              _ ->
                assertFailure
                  ( label
                      <> ": grindFlow sent "
                      <> show (length sent)
                      <> " prompts, expected 4 (two lenses, synthesis, fixer)"
                  )
        (bareFirst, bareSynthesis, bareFixer) <-
          shaped "bare" =<< flowLeafPrompts "grind-synthetic" (grindFlow (specWith mempty)) "STEER"
        (_, suffixedSynthesis, _) <-
          shaped "suffixed" =<< flowLeafPrompts "grind-synthetic" (grindFlow (specWith "THE RANKING CLAUSE")) "STEER"
        let derived = promptText (grindSynthesisOver "grind-synthetic" (map fst lenses))
        assertBool
          "the synthesis brief is not derived from the spec's name and lens table"
          (derived `T.isInfixOf` bareSynthesis)
        suffixedSynthesis
          @?= T.replace derived (derived <> "\n\nTHE RANKING CLAUSE") bareSynthesis
        assertBool
          "the fixer's rule is not derived from the spec's facts"
          (promptText (grindRule "THE SYNTHETIC FACTS") `T.isInfixOf` bareFixer)
        assertBool
          "the facts are not prepended to the caller's steer"
          ("THE SYNTHETIC FACTS\n\nSTEER" `T.isInfixOf` bareFirst)
    , -- __The stop is control flow, on the synthetic spec.__ Every leaf
      -- answers with the probe's refusal line, the way a wrong-checkout panel
      -- does; the synthesis therefore opens with it, and the run must FAIL at
      -- the refusal stop — exactly one prompt after the panel, with the fixer
      -- never reached. Interpreted rather than read off the skeleton, because
      -- the stop is a pure decide inside a loop: no leaf name, no cost, no
      -- plan line can see it. The happy path is the case above, whose empty
      -- answers pass the same stop into the fixer.
      testCase "a refused synthesis stops the run before the fixer" $ do
        let lenses = [("alpha-lens", "ALPHA?"), ("beta-lens", "BETA?")] :: [(LeafName, Prompt)]
            refusing =
              GrindSpec
                { gsName = "grind-synthetic"
                , gsFacts = "THE SYNTHETIC FACTS"
                , gsLenses = lenses
                , gsSynthesisSuffix = mempty
                , gsPins = []
                }
        sent <- newIORef (0 :: Int)
        outcome <-
          try $ do
            (out, _) <-
              interpret
                ( leafRunner
                    LeafHandlers
                      { lhPrompt = \_ ->
                          modifyIORef' sent (+ 1)
                            >> pure (factsRefusalLine <> "\nblocks: alpha-lens@a, beta-lens@b")
                      , lhExec = \cmd -> assertFailure ("the refused grind ran an exec leaf: " <> show cmd)
                      , lhAsk = \_ -> assertFailure "the refused grind reached an ask leaf"
                      }
                )
                (grindFlow refusing)
                "STEER"
            evaluate (T.length out)
        case outcome of
          Right _ -> assertFailure "the flow carried a refusal past the stop instead of failing the run"
          Left (ErrorCall msg) ->
            assertBool
              ("the run failed, but not at a loop's exhaustion: " <> msg)
              ("fuel exhausted" `isInfixOf` msg)
        prompts <- readIORef sent
        -- The panel and the synthesis were paid for; the fixer was not.
        prompts @?= length lenses + 1
    , -- The stop's reader, over the line shapes that reach it: the bare line
      -- the brief demands, the probe's own colon-and-explanation form a
      -- synthesis may quote verbatim, and a decorated spelling — against
      -- ranked text that mentions the refusal mid-sentence, which must pass.
      testCase "decideFactsResolved refuses on the probe's line and passes a ranked report" $ do
        decideFactsResolved ("1. finding one\n2. finding two") @?= Right "1. finding one\n2. finding two"
        decideFactsResolved ("prose that mentions FACTS PATHS UNRESOLVED mid-sentence")
          @?= Right "prose that mentions FACTS PATHS UNRESOLVED mid-sentence"
        decideFactsResolved (factsRefusalLine <> "\nblocks: alpha")
          @?= Left (factsRefusalLine <> "\nblocks: alpha")
        decideFactsResolved ("report:\n" <> factsRefusalLine <> ": domain/ is missing")
          @?= Left ("report:\n" <> factsRefusalLine <> ": domain/ is missing")
        decideFactsResolved ("`" <> factsRefusalLine <> "`")
          @?= Left ("`" <> factsRefusalLine <> "`")
    , -- __The pin is policy, proven where position disagrees.__ The shipped
      -- table happens to seat @auth@ on the claude slot anyway, so only a
      -- synthetic table where the pin and the position name DIFFERENT
      -- backends can show the pin doing anything: the pinned lens moves, its
      -- neighbours keep their positional backends, and a pin naming a backend
      -- the roster lacks falls back to position rather than failing the
      -- build.
      testCase "spreadPinned overrides position for the pinned lens alone" $ do
        let lenses =
              [ ("alpha-lens", "ALPHA?")
              , ("beta-lens", "BETA?")
              , ("gamma-lens", "GAMMA?")
              ] ::
                [(LeafName, Prompt)]
            full = backendsFor False
        leafNames (spreadPinned [("alpha-lens", "codex")] full lenses)
          @?= ["alpha-lens@codex", "beta-lens@codex", "gamma-lens@opencode"]
        leafNames (spreadPinned [("alpha-lens", "no-such-backend")] full lenses)
          @?= ["alpha-lens@claude-agent", "beta-lens@codex", "gamma-lens@opencode"]
        leafNames (spreadPinned [] full lenses)
          @?= leafNames (spread full lenses)
        -- And 'admits' has the last word: a pin cannot seat the fess rubric
        -- on codex, so the pinned lens lands on the first backend that
        -- admits it — a regression that let a pin override 'admits' would
        -- ship the one pairing the panel is forbidden to build.
        leafNames (spreadPinned [("fess", "codex")] full [("fess", fess)])
          @?= ["fess@claude-agent"]
    , -- __The shipped spec, not a copy assembled here.__ The synthetic case
      -- above pins the seam mechanics for any spec; this pins that
      -- @grind-live-view@ actually rides them — its suffix IS the ranking
      -- clause, over the same lens table its panel runs, above the LiveView
      -- facts. Field equality on the named binding covering ALL of it: an
      -- earlier version compared three fields and lens names only, so a spec
      -- quietly rebuilt with @gsFacts = testsFacts@, or with a same-named
      -- lens whose body was swapped, stayed green everywhere. Names AND
      -- bodies per lens row, and the pin as a hand-written literal — the one
      -- statement outside 'Incite.Feature' of which backend the auth lens
      -- must hold.
      testCase "grind-live-view's spec carries the ranking clause over its own lens table" $ do
        promptText (gsSynthesisSuffix grindLiveViewSpec) @?= promptText grindLiveViewRanking
        gsName grindLiveViewSpec @?= grindLiveViewName
        promptText (gsFacts grindLiveViewSpec) @?= promptText liveViewFacts
        map fst (gsLenses grindLiveViewSpec) @?= map fst grindLiveViewLenses
        map (promptText . snd) (gsLenses grindLiveViewSpec)
          @?= map (promptText . snd) grindLiveViewLenses
        gsPins grindLiveViewSpec @?= [("auth", "claude-agent")]
    , -- The other two shipped specs, under the same all-fields law and for
      -- the same reason: until these were named top-level bindings the specs
      -- lived inline in their workflows, where a quiet rebuild — another
      -- tree's facts, a same-named lens with a swapped body — shipped green
      -- while every plan and cost render stayed identical. One fold, so the
      -- next grind's spec joins the law by joining the list.
      testCase "grind-paradox's and grind-tests' specs are exactly their named ingredients" $
        mapM_
          ( \(label, spec, name, facts, lenses) -> do
              assertEqual (label <> ": gsName") name (gsName spec)
              assertEqual (label <> ": gsFacts") (promptText facts) (promptText (gsFacts spec))
              assertEqual (label <> ": lens names") (map fst lenses) (map fst (gsLenses spec))
              assertEqual
                (label <> ": lens bodies")
                (map (promptText . snd) lenses)
                (map (promptText . snd) (gsLenses spec))
              assertEqual (label <> ": suffix") "" (promptText (gsSynthesisSuffix spec))
              assertEqual (label <> ": pins") [] (gsPins spec)
          )
          [ ("grind-paradox", grindParadoxSpec, grindName, paradoxFacts, grindLenses)
          , ("grind-tests", grindTestsSpec, grindTestsName, testsFacts, grindTestsLenses)
          ]
    , -- The severity vocabulary, asserted from both sides — 'synthesisAdmits'\'s
      -- shape, for its reason: the auth lens writes the words and the ranking
      -- clause matches on them, and they live in two files nothing else reads
      -- together. Drop the demand from the lens and auth findings arrive
      -- wordless; drop the words from the clause and the ranking rule reads
      -- nothing — either way an authorization finding sinks below UX noise,
      -- which is exactly the silent failure the clause exists to prevent.
      testCase "the auth lens and the ranking clause share the severity vocabulary" $
        report
          ( concat
              [ [ "liveViewAuth does not demand the severity word " <> tshow w
                | w <- severityWords
                , not (says liveViewAuth w)
                ]
              , [ "the ranking clause does not carry the severity word " <> tshow w
                | w <- severityWords
                , not (says grindLiveViewRanking w)
                ]
              , [ "the ranking clause does not put authorization above performance and UX"
                | not (saysLoosely grindLiveViewRanking "every authorization finding ranks above every performance and UX finding")
                ]
              , [ "the ranking clause does not keep the word on the finding's line"
                | not (saysLoosely grindLiveViewRanking "keep that word on the finding's line")
                ]
              ]
          )
    , -- __The review-pass wiring is a pure adapter, and only a traversal can
      -- see it.__ Revert grind-tests' reframing to plain 'asReviewSubject'
      -- and every leaf name, plan skeleton, fence table and frame-unit test
      -- stays green — the unit test calls the function with its own literal.
      -- So the rendered prompts of the SHIPPED flow are asserted, with the
      -- needle spliced from the same bindings the workflow passes — which
      -- also pins which prefix the shipped review pass excludes.
      testCase "grind-tests' review pass reads through the own-artifacts frame" $ do
        sent <- actingWorkflowLeafPrompts grindTests
        let needle =
              "files whose path starts with `"
                <> auditReportDir
                <> grindTestsName
                <> "-` are the run's own product"
        assertBool "no rendered leaf carries the own-artifacts frame at the run's report prefix" $
          any (needle `T.isInfixOf`) sent
    , -- The shipped specs' CONSUMPTION, which the field-equality cases above
      -- cannot prove: rebuild a spec inline in its workflow with another
      -- tree's facts and every equality fence stays green while the panel
      -- audits under facts the workflow never renders. So the facts must
      -- reach a rendered leaf of each shipped flow.
      testCase "each grind's leaves render the facts its spec names" $
        mapM_
          ( \(wf, facts) -> do
              sent <- actingWorkflowLeafPrompts wf
              assertBool (T.unpack (wfName wf) <> " never renders its facts in any leaf") $
                any (promptText facts `T.isInfixOf`) sent
          )
          [ (grindParadox, paradoxFacts)
          , (grindTests, testsFacts)
          , (grindLiveView, liveViewFacts)
          ]
    , grindFenceTests paradoxGrindFence
    , grindFenceTests testsGrindFence
    , grindFenceTests liveViewGrindFence
    ]

-- | The three severity words 'Incite.Prompts.liveViewAuth' opens findings with
-- and 'Incite.Feature.grindLiveViewRanking' orders them by — literals here,
-- for 'grindContract'\'s reason: both briefs now render the vocabulary from
-- the one binding 'Incite.Prompts.liveViewSeverityWords', so a fence derived
-- from any of them would be @x@ contains @x@ and move with the very edit it
-- exists to catch. This hand copy is the independent statement.
severityWords :: [Text]
severityWords = ["`critical`", "`high`", "`medium`"]

-- | One grind's whole fence, as data: the laws every grind must pin, applied
-- per instantiation by 'grindFenceTests'. A record rather than a per-grind
-- copy of the cases, so a law added here reaches every grind by existing — and
-- so the second grind could not land with fewer fences than the first.
--
-- __Every table is hand-written at the instantiation, never derived.__ A
-- derived expectation is the combinator restated, and moves with any
-- reassignment it is supposed to catch; the whole point of these fields is
-- that a human wrote down which model audits which lens and which leaves act.
data GrindFence = GrindFence
  { gfWorkflow :: Workflow
  -- ^ The shipped workflow whose skeleton the tables are read against, and
  -- whose 'wfName' names the test group — derived, where a label field held a
  -- second copy of the same name.
  , gfLenses :: [(LeafName, Prompt)]
  -- ^ The lens table the grind hands to @spread@, imported from the module
  -- that ships it.
  , gfWidth :: Int
  -- ^ The panel's width as a plain literal, because both sides of every other
  -- law move together when a lens is quietly dropped.
  , gfPanelFull :: [Text]
  -- ^ The @lens\@backend@ pairing over the full three-backend roster.
  , gfPanelBlocked :: [Text]
  -- ^ The same pairing under @BLOCK_OPENCODE@: two backends, alternating —
  -- every lens still gets exactly one leaf, only the model changes.
  , gfActingTailFull :: [Text]
  -- ^ Every leaf from @synthesis@ on, in order, over the full roster. A stage
  -- dropped from the chain — a fixer, a repair leaf, a check — leaves a
  -- workflow that still plans and still costs, and reports a gate it never ran.
  , gfActingTailBlocked :: [Text]
  -- ^ The same tail under @BLOCK_OPENCODE@. Distinct from the full one only
  -- where the tail itself contains a panel, as @grind-tests@'s review-audit
  -- segment does.
  , gfGrant :: Grant
  , gfGrantLabel :: Text
  -- ^ How the grant's failures are reported, so a red case names the Haskell
  -- binding somebody has to edit. A field where 'gfWorkflow'\'s label is
  -- derived, because the binding names are not derivable: @grind-paradox@\'s
  -- grant is 'Incite.Feature.grindGrant', not @grindParadoxGrant@.
  , gfChecks :: [(LeafName, NE.NonEmpty Text)]
  }

-- | The laws of one grind, read off its 'GrindFence'. Factored from the cases
-- @grind-paradox@ accumulated one defect at a time, with each case's original
-- rationale kept where it was learned.
grindFenceTests :: GrindFence -> TestTree
grindFenceTests gf =
  testGroup
    (T.unpack (wfName (gfWorkflow gf)))
    [ -- Two lenses rendering the same text are two leaves doing one leaf's
      -- work on two different models, which reads as agreement in the
      -- synthesis.
      testCase "no grind lens repeats another's body" $
        let bodies = map (promptText . snd) (gfLenses gf)
            repeats = bodies \\ nub bodies
         in report (map (("repeated grind lens body: " <>) . bodyTag) (nub repeats))
    , -- The output contract, as a property of every body the panel sends. See
      -- 'grindContract' for why the needles are literals here.
      testCase "every grind lens carries the finding contract" $
        report
          [ leafNameText name <> " does not say " <> tshow needle
          | (name, body) <- gfLenses gf
          , needle <- grindContract
          , not (says body needle)
          ]
    , -- 'spread' is a zip against a cycled backend list, so the leaf count is
      -- the LENS count — not @min@ of the two, and not the cross-product a
      -- panel would give.
      --
      -- __A law about 'spread', and it needs the table case beside it.__ Both
      -- sides here are derived from the lens table, so a lens deleted from the
      -- panel moves them together and this stays green. What it refutes is
      -- 'spread' itself: point it at @panelAcross@ and the count triples.
      testCase "spread gives one leaf per lens" $
        length (leafNames (spread backends (gfLenses gf))) @?= length (gfLenses gf)
    , -- The panel's WIDTH, as a plain number, because the law above cannot see
      -- it. A lens quietly dropped from the table is a lens nobody runs, and
      -- the run reports a clean tree for the part it never read.
      testCase "the panel is exactly as wide as its table" $
        length (gfLenses gf) @?= gfWidth gf
    , -- __The shipped workflow, not a table assembled here.__ Every case above
      -- reads the lens table; nothing forced the workflow to hand @spread@ the
      -- same thing in the same order. Compose it differently in production and
      -- every law above stays green while a different model audits each lens —
      -- which is exactly the reassignment this ordered list catches.
      --
      -- __Two tables, because the roster is two rosters.__ 'spread' cycles
      -- 'Incite.Backend.backends', which narrows to claude-agent and codex
      -- under @BLOCK_OPENCODE@ — so the pairing genuinely differs and a single
      -- table would fence whoever's shell ran the suite. Both are hand-written
      -- rather than derived from a cycle: a derived expectation is 'spread'
      -- restated, and would move with any reassignment it is supposed to catch.
      testCase "fans out exactly these lens@backend leaves" $ do
        takeWhile (/= "synthesis") (leafNames (wfFlow (gfWorkflow gf)))
          @?= (if blockOpencode then gfPanelBlocked gf else gfPanelFull gf)
        -- Both tables cover every lens, whichever is live: a table that lost a
        -- row would otherwise pass by agreeing with a panel that had lost the
        -- same lens.
        length (gfPanelFull gf) @?= length (gfLenses gf)
        length (gfPanelBlocked gf) @?= length (gfLenses gf)
    , -- The acting half's leaves, in order, after the panel. A stage dropped
      -- from the chain — the fixer, the repair leaf, a check — leaves a
      -- workflow that still plans and still costs, and reports a green gate it
      -- never ran.
      testCase "then synthesises, fixes, and gates on real checks" $
        dropWhile (/= "synthesis") (leafNames (wfFlow (gfWorkflow gf)))
          @?= (if blockOpencode then gfActingTailBlocked gf else gfActingTailFull gf)
    , -- And the pairing preserves distinctness: 'unionFindings' heads each
      -- block by leaf name, so two leaves sharing one would make two reviewers
      -- indistinguishable in the reduction. Distinct LENS names do not imply
      -- distinct LEAF names on their own — the pairing is what appends the
      -- backend tag, and this is the case that reads the result.
      testCase "spread leaf names are distinct" $
        let ns = leafNames (spread backends (gfLenses gf))
         in report
              ["repeated leaf name: " <> n | n <- nub (ns \\ nub ns)]
    , -- __The grant against the checks it is derived from, through the
      -- runtime's own matcher.__ A grant and a check list are two statements
      -- of one fact, and the drift is silent in the direction that matters: an
      -- ungranted check is DENIED inside the run (exit 126, "denied by
      -- grant"), the gate never reads a real exit code, and the artifact still
      -- carries a gate section.
      --
      -- 'permitExec' over @T.unwords@ is exactly what @Agent.Run@ applies to
      -- an 'Agent.Op.Exec' leaf, so this fails on a broken argv rather than
      -- restating the derivation. A membership check on the glob set would
      -- pass on globs that match nothing.
      testCase "the grant permits every check as the runtime spells it" $
        report
          [ "denied by " <> gfGrantLabel gf <> ": " <> tshow line
          | (_, cmd) <- gfChecks gf
          , let line = T.unwords (NE.toList cmd)
          , not (permitExec (gfGrant gf) line)
          ]
    , -- __Every check carries its own toolchain.__ 'execStep' runs argv
      -- directly — no shell, no profile, no dev shell — so a check that needs
      -- the target project's environment has to ask for it in its own argv.
      --
      -- This is not a style rule; a rehearsal found it the expensive way.
      -- Paradox's `test.sh` ends by executing a path built from `$GHC_VER` and
      -- `$PARADOX_VER`, which its dev shell sets and nothing else does. Run
      -- bare it exits non-zero on a tree in perfect health, so the gate is red
      -- on every run, for a reason no repair leaf can fix: `repairFuel` trips
      -- hunting a defect in the code, then an abort. A gate that cannot go
      -- green is worse than no gate.
      --
      -- Nothing else can see this. `plan` renders the leaf NAME, `cost` counts
      -- it, and the grant case above passes either way — an ungranted command
      -- and an unrunnable one both fail, and only one of them is about the
      -- grant.
      testCase "every check runs inside the target project's dev shell" $
        report
          [ leafNameText n <> " runs bare: " <> tshow (T.unwords (NE.toList cmd))
          | (n, cmd) <- gfChecks gf
          , take 3 (NE.toList cmd) /= ["nix", "develop", "--command"]
          ]
    , -- The synthesis leaf's two, which are nobody's check. Without them its
      -- write fails inside the agent while it still returns the whole ranked
      -- report — so the run reports success with no file on disk, and only the
      -- filesystem can tell.
      testCase "the grant permits the report write" $
        report
          [ "denied by " <> gfGrantLabel gf <> ": " <> tshow line
          | -- Derived from 'auditReportDir', so the tested line moves with
            -- the directory the synthesis actually mkdirs.
            line <- ["date +%Y-%m-%d", "mkdir -p " <> auditReportDir]
          , not (permitExec (gfGrant gf) line)
          ]
    , -- And it is not a blanket grant. Deriving from a list is only worth
      -- anything if the derivation still denies what is not on it.
      testCase "the grant denies what no check asked for" $
        report
          [ gfGrantLabel gf <> " permits " <> tshow line
          | line <- ["rm -rf /", "git push origin master", "curl example.com"]
          , permitExec (gfGrant gf) line
          ]
    ]

-- | @grind-paradox@'s fence: the 14-lens union, the plain
-- audit-synthesize-fix-gate tail, and the grant derived from its two checks.
paradoxGrindFence :: GrindFence
paradoxGrindFence =
  GrindFence
    { gfWorkflow = grindParadox
    , gfLenses = grindLenses
    , gfWidth = 14
    , gfPanelFull =
        [ "correctness@claude-agent"
        , "tests@codex"
        , "stubs@opencode"
        , "vacuous@claude-agent"
        , "dry@codex"
        , "hardcodings@opencode"
        , "refactor@claude-agent"
        , "architecture@codex"
        , "performance@opencode"
        , "ponytail@claude-agent"
        , "target-consistency@codex"
        , "validator-calls@opencode"
        , "codegen-gaps@claude-agent"
        , "emitted-code@codex"
        ]
    , gfPanelBlocked =
        [ "correctness@claude-agent"
        , "tests@codex"
        , "stubs@claude-agent"
        , "vacuous@codex"
        , "dry@claude-agent"
        , "hardcodings@codex"
        , "refactor@claude-agent"
        , "architecture@codex"
        , "performance@claude-agent"
        , "ponytail@codex"
        , "target-consistency@claude-agent"
        , "validator-calls@codex"
        , "codegen-gaps@claude-agent"
        , "emitted-code@codex"
        ]
    , gfActingTailFull = ["synthesis", "remediate", "build", "tests", "repair"]
    , gfActingTailBlocked = ["synthesis", "remediate", "build", "tests", "repair"]
    , gfGrant = grindGrant
    , gfGrantLabel = "grindGrant"
    , gfChecks = grindChecks
    }

-- | @grind-tests@'s fence: the 12-lens table, the tail that runs a whole
-- review-audit pass between its two fixers, and the grant derived from its
-- three checks.
--
-- __The review-audit segment is written out literally, never as
-- @leafNames reviewAuditFlow@.__ A fence computed from the code under test
-- accepts any mis-composition of that code — swap in 'reviewHeavyFlow' (whose
-- regrouped views run on claude-agent alone) or a diff-subject panel (which
-- has no @architecture@ lens) and a derived expectation moves with the bug.
-- 'reviewAuditPanelFull' and 'reviewAuditPanelBlocked' are this file's own
-- statement of that tier's cross-product, and the tail is assembled from those
-- literal blocks by concatenation alone.
testsGrindFence :: GrindFence
testsGrindFence =
  GrindFence
    { gfWorkflow = grindTests
    , gfLenses = grindTestsLenses
    , gfWidth = 12
    , gfPanelFull =
        [ "vacuous@claude-agent"
        , "coverage@codex"
        , "property@opencode"
        , "mutation@claude-agent"
        , "stubs@codex"
        , "sleeps@opencode"
        , "generated-copies@claude-agent"
        , "testability@codex"
        , "dry@opencode"
        , "proofs@claude-agent"
        , "selectors@codex"
        , "isolation@opencode"
        ]
    , gfPanelBlocked =
        [ "vacuous@claude-agent"
        , "coverage@codex"
        , "property@claude-agent"
        , "mutation@codex"
        , "stubs@claude-agent"
        , "sleeps@codex"
        , "generated-copies@claude-agent"
        , "testability@codex"
        , "dry@claude-agent"
        , "proofs@codex"
        , "selectors@claude-agent"
        , "isolation@codex"
        ]
    , gfActingTailFull = testsGrindTail reviewAuditPanelFull
    , gfActingTailBlocked = testsGrindTail reviewAuditPanelBlocked
    , gfGrant = grindTestsGrant
    , gfGrantLabel = "grindTestsGrant"
    , gfChecks = grindTestsChecks
    }

-- | @grind-live-view@'s fence: the 11-lens table, the plain
-- audit-synthesize-fix-gate tail, and the grant derived from its three
-- checks — the same three as @grind-tests@, because both grinds gate the
-- same checkout and the @ts-hooks@ lens writes TypeScript the two mix
-- commands cannot see.
--
-- Both tables put @auth@ on claude-agent — the spec's own @gsPins@ states
-- that policy as data, and position seven is the claude slot under either
-- roster anyway. These rows are where the assignment is said out loud:
-- reassign it, by reorder or by pin, and the live column goes red.
liveViewGrindFence :: GrindFence
liveViewGrindFence =
  GrindFence
    { gfWorkflow = grindLiveView
    , gfLenses = grindLiveViewLenses
    , gfWidth = 11
    , gfPanelFull =
        [ "css-hardening@claude-agent"
        , "componentize@codex"
        , "liveness@opencode"
        , "rerender@claude-agent"
        , "pubsub@codex"
        , "best-practices@opencode"
        , "auth@claude-agent"
        , "page-load@codex"
        , "dom-keying@opencode"
        , "assign-bloat@claude-agent"
        , "ts-hooks@codex"
        ]
    , gfPanelBlocked =
        [ "css-hardening@claude-agent"
        , "componentize@codex"
        , "liveness@claude-agent"
        , "rerender@codex"
        , "pubsub@claude-agent"
        , "best-practices@codex"
        , "auth@claude-agent"
        , "page-load@codex"
        , "dom-keying@claude-agent"
        , "assign-bloat@codex"
        , "ts-hooks@claude-agent"
        ]
    , gfActingTailFull = ["synthesis", "remediate", "compile", "tests", "vitest", "repair"]
    , gfActingTailBlocked = ["synthesis", "remediate", "compile", "tests", "vitest", "repair"]
    , gfGrant = grindLiveViewGrant
    , gfGrantLabel = "grindLiveViewGrant"
    , gfChecks = grindLiveViewChecks
    }

-- | @grind-tests@'s acting tail over one hand-written statement of the
-- review-audit panel. The shape is the same on either roster — only the panel
-- block differs — so 'testsGrindFence' passes each literal block through this
-- one assembly rather than spelling the concatenation twice, where the two
-- copies could disagree about the shape they claim to share.
testsGrindTail :: [Text] -> [Text]
testsGrindTail panel =
  ["synthesis", "remediate"]
    <> panel
    <> ("regroup:units" : panel)
    <> ("regroup:sequence" : panel)
    <> ["synthesis", "remediate", "compile", "tests", "vitest", "repair"]

-- | One view's worth of the review-audit panel, as literals: nine change
-- lenses, every backend answering each, in @panelAcross@'s reading order.
-- @grind-tests@ runs this three times — the full diff and the two regrouped
-- views — and 'testsGrindFence' concatenates this block rather than deriving
-- it from the flow it fences.
reviewAuditPanelFull :: [Text]
reviewAuditPanelFull =
  [ "correctness@claude-agent"
  , "correctness@codex"
  , "correctness@opencode"
  , "security@claude-agent"
  , "security@codex"
  , "security@opencode"
  , "tests@claude-agent"
  , "tests@codex"
  , "tests@opencode"
  , "performance@claude-agent"
  , "performance@codex"
  , "performance@opencode"
  , "haskell@claude-agent"
  , "haskell@codex"
  , "haskell@opencode"
  , "ponytail@claude-agent"
  , "ponytail@codex"
  , "ponytail@opencode"
  , "doctrine@claude-agent"
  , "doctrine@codex"
  , "doctrine@opencode"
  , "discipline@claude-agent"
  , "discipline@codex"
  , "discipline@opencode"
  , "architecture@claude-agent"
  , "architecture@codex"
  , "architecture@opencode"
  ]

-- | 'reviewAuditPanelFull' under @BLOCK_OPENCODE@: the same nine lenses on the
-- two-backend roster.
reviewAuditPanelBlocked :: [Text]
reviewAuditPanelBlocked =
  [ "correctness@claude-agent"
  , "correctness@codex"
  , "security@claude-agent"
  , "security@codex"
  , "tests@claude-agent"
  , "tests@codex"
  , "performance@claude-agent"
  , "performance@codex"
  , "haskell@claude-agent"
  , "haskell@codex"
  , "ponytail@claude-agent"
  , "ponytail@codex"
  , "doctrine@claude-agent"
  , "doctrine@codex"
  , "discipline@claude-agent"
  , "discipline@codex"
  , "architecture@claude-agent"
  , "architecture@codex"
  ]

-- | The acting leaves of 'stackPRs', in the order the workflow runs them.
--
-- Written out because the claim is the ORDER and not the membership: every gate
-- here is worth nothing in the wrong place. A @verify-stack@ that moved below
-- the panel means 21 reviewers read branches that do not build; one that moved
-- below the promotion gate means a shared CI slot is spent on a branch a local
-- check already knew would fail; a @ci-budget@ that moved outside the promotion
-- loop means the budget is read once and reused against a queue that has since
-- changed. None of those moves any leaf NAME, any node count or any cost, so
-- this list is the only instrument that can see one.
stackActing :: [Text]
stackActing =
  [ "bootstrap"
  , "cut"
  , "verify-stack"
  , "repair"
  , "remediate"
  , "triage"
  , "verify-stack"
  , "repair"
  , "promotion-consent"
  , "ci-budget"
  , "promote"
  ]

-- | The four leaves 'Incite.Feature.stackWorker' builds, each with the body and
-- the closing clause the workflow hands it.
--
-- A hand-kept mirror, like 'mirrorWorkflows', and the case above is what keeps
-- it honest: those four names are asserted against the shipped flow, so a worker
-- renamed on one side and not the other fails there.
stackWorkers :: [(LeafName, Prompt, Prompt)]
stackWorkers =
  [ ("bootstrap", stackTooling, mempty)
  , ("cut", stackSlice, stackContinuation)
  , ("triage", stackTriage, stackContinuation)
  , ("promote", stackPromote, stackContinuation)
  ]

-- | Fences the workflow whose gates are __ours__.
--
-- Every other acting workflow here trusts an agent with everything except its
-- build. This one also decides, with a real exit code, whether a CI run may be
-- started at all — and that decision lands on whoever else is queued for the
-- same runners. So the structure carrying it is asserted rather than described.
stackTests :: TestTree
stackTests =
  testGroup
    "stack-prs"
    [ testCase "acts in the order its gates are worth anything in" $
        filter (`elem` stackActing) (leafNames (wfFlow stackPRs)) @?= stackActing
    , -- __The tail, which the order above cannot see:__ it filters to the acting
      -- roster, so a stage appended after promotion passes it. That the
      -- promotion loop is LAST is a claim @docs\/workflows.md@ now makes in
      -- prose — an exhausted promotion loop yields to nothing, so a stack left
      -- half promoted ends the run looking like one that finished. Append a
      -- stage there and the sentence is wrong; this is what says so.
      testCase "the promotion loop is the last stage, which is why exhaustion there is silent" $
        last (leafNames (wfFlow stackPRs)) @?= "promote"
    , -- The safety property the whole workflow exists to hold, stated on its
      -- own rather than left as a corollary of the order above. A budget check
      -- reached AFTER the first promotion is a check on a slot already spent.
      testCase "no promotion leaf is reachable before a budget check" $
        assertBool
          "a promote leaf precedes every ci-budget leaf"
          ("ci-budget" `elem` takeWhile (/= "promote") (leafNames (wfFlow stackPRs)))
    , -- Consent is the gate that holds when nobody is watching, so it has to be
      -- an Exec leaf and it has to come first. `humanGate` cannot carry this:
      -- @Agent.Run@ answers every Ask with @gateAnswer@, default "yes", so on
      -- the MCP path the human gate approves itself. Both halves are asserted —
      -- that the check runs before any promotion, and that it is our exec rather
      -- than a question, because an Ask here would pass the ordering case while
      -- protecting nothing.
      testCase "consent is checked by our own exec before anything is promoted" $ do
        let names = leafNames (wfFlow stackPRs)
            consent = leafNameText (fst consentCheck)
        assertBool
          "a promote leaf precedes the consent check"
          (consent `elem` takeWhile (/= "promote") names)
        assertBool
          "the consent check is not an Exec leaf"
          (("exec:" <> consent) `elem` leafKinds (wfFlow stackPRs))
    , -- 'Incite.Feature.stackFuel' is finite because four unbounded loops in
      -- one sequence sum past 'maxBound' and report a NEGATIVE worst case —
      -- which is what @agent-functor cost@ printed for the four loops this
      -- workflow runs in sequence, and it is what an operator reads before
      -- deciding to spend anything. Nothing else here would notice: the flow
      -- builds, plans and runs identically either way.
      --
      -- Both fuels are asserted finite HERE rather than left as literals only a
      -- reader checks: 'stackFuel' being 'Nothing' is the overflow, and
      -- 'budgetFuel' being unbounded is a promotion gate that waits forever
      -- instead of handing a stuck queue to a person.
      --
      -- 'Incite.Feature.liteFuel' gets the same treatment in 'liteTests', where
      -- the workflow it belongs to is.
      testCase "both fuels are finite, which is what keeps the cost a number" $ do
        assertBool "stackFuel is unbounded" (stackFuel /= Nothing)
        assertBool "budgetFuel is not positive" (budgetFuel > 0)
        case worstCaseCost (toSkeleton (wfFlow stackPRs)) of
          Finite n -> assertBool ("worst case is " <> show n) (n > 0)
          other -> assertFailure ("worst case is " <> T.unpack (renderCost other))
    , -- The figure in the prose, against the arithmetic. Same fence as the
      -- review-tier table, and it exists because the Stacking section quoted a
      -- bare number that no check could see going stale: a fuel change, a panel
      -- change or one more stage moves it silently.
      --
      -- 'worstCaseTable' is the reader, shared with the Small changes section
      -- rather than copied for it. It replaced the worked example that stood
      -- here, and only after both of that reader's vacuity modes were provoked
      -- and seen to fail — see its own haddock.
      --
      -- __Two columns, and the live one checked__ — the review-tier table's
      -- treatment, for the review-tier table's reason: 'stackPRs' carries a
      -- review panel, so its worst case moves with @BLOCK_OPENCODE@, and a
      -- single-column table made this fence a statement about whoever's shell
      -- ran the suite.
      testCase "the Stacking worst-case table matches worstCaseCost" $
        worstCaseTable FullAndBlocked "Stacking a change" stackPRs
    , -- Every acting leaf under one pin, read off the SHIPPED flow rather than
      -- off the source. 'remediate' and 'repair' are unpinned in the two
      -- workflows that share them, so nothing but this says they are pinned
      -- here — and a backend scope moves no leaf name, node count or cost.
      testCase "every acting leaf of stack-prs runs on claude-agent" $ do
        -- The two Exec leaves are the harness's own commands, so no backend
        -- runs them and a pin would mean nothing. Their names are derived from
        -- the check lists rather than typed here, so a renamed check cannot
        -- quietly re-enter the set this quantifies over.
        let harnessRun = [leafNameText n | (n, _) <- consentCheck : budgetCheck : stackChecks]
            agentActing = [n | n <- stackActing, n `notElem` harnessRun]
        assertBool "no agent-run acting leaves to check" (not (null agentActing))
        report
          [ "unpinned acting leaf: " <> n <> " runs on " <> agent
          | (n, agent) <- scopedLeaves (wfFlow stackPRs)
          , n `elem` agentActing
          , backendOf agent /= "claude-agent"
          ]
    , -- The third ending, and the reason it is a token rather than prose: the
      -- stage after a blocked worker reads its last line, and a block reported
      -- as completion is how a run spends CI on work a person owed a decision
      -- on. 'decideContinue' must end the loop on it (it is not the continue
      -- marker), and the promotion brief must refuse on it.
      testCase "the blocked ending is terminal, distinct, and refused downstream" $ do
        decideContinue ("work\n" <> blockedMarker) @?= Right ("work\n" <> blockedMarker)
        assertBool "the blocked marker is the continue marker" (blockedMarker /= continueMarker)
        assertBool
          "the continuation clause does not name the blocked marker"
          (says stackContinuation blockedMarker)
        assertBool
          "the promotion brief does not refuse a blocked hand-off"
          (says stackPromote blockedMarker)
    , -- The grant against the checks it is derived from, through the runtime's
      -- own matcher — 'grindGrant'\'s case, and one sharper. An ungranted check
      -- is denied inside the run, so a denied @ci-budget@ leaves a promotion
      -- loop that never asks whether it may promote, while the artifact still
      -- carries a budget section.
      testCase "stackGrant permits both checks as the runtime spells them" $
        report
          [ "denied by stackGrant: " <> tshow line
          | (_, cmd) <- consentCheck : budgetCheck : stackChecks
          , let line = T.unwords (NE.toList cmd)
          , not (permitExec stackGrant line)
          ]
    , testCase "stackGrant denies what no check asked for" $
        report
          [ "stackGrant permits " <> tshow line
          | line <- ["rm -rf /", "git push --force origin main", "gh pr merge 1"]
          , permitExec stackGrant line
          ]
    , -- Every acting leaf stands under the facts and the disciplines, and the
      -- one that can destroy the most is the FIRST — a branch recreated rather
      -- than split takes a pull request's review history with it, long before
      -- any fixer runs. A worker written later that skips 'stackWorker' would
      -- lose both with nothing else going red.
      testCase "every worker carries the facts, the rule, and its own body" $ do
        complaints <-
          mapM
            ( \(name, body, closing) -> do
                let named = leafNameText name
                sent <- flowLeafPrompts (T.unpack named) (stackWorker name body closing) "ARTIFACT"
                pure $ case sent of
                  [leafText] ->
                    [ named <> " drops " <> what
                    | (what, needle) <-
                        [ ("the facts", promptText stackFacts)
                        , ("the code rule", promptText codeRule)
                        , ("the stack disciplines", promptText stackDisciplines)
                        , ("its own body", promptText body)
                        , ("the artifact", "ARTIFACT")
                        , ("its closing clause", promptText closing)
                        ]
                    , not (T.null (T.strip needle))
                    , not (T.isInfixOf needle leafText)
                    ]
                  _ -> [named <> " is not one prompt leaf"]
            )
            stackWorkers
        report (concat complaints)
    , -- The artifact rule, asserted directly. It reaches every worker through
      -- 'stackWorker', so the case above covers it there — but 'remediate' and
      -- the repair leaf take it as an argument, and nothing else would say the
      -- composition still carries both halves.
      testCase "stackRule carries the code rule and the stack disciplines" $
        report
          [ "stackRule drops " <> what
          | (what, needle) <-
              [ ("the code rule", promptText codeRule)
              , ("the stack disciplines", promptText stackDisciplines)
              ]
          , not (says stackRule needle)
          ]
    , -- Round trip through the decider rather than a substring check, for
      -- 'documentTests'\'s reason: the clause shows the marker decorated, and
      -- what has to hold is that the decorated form a worker copies is one
      -- 'decideContinue' reads as "call me again". A clause that spelled the
      -- marker itself would strand every loop in this workflow for its whole
      -- fuel, with nothing in any output naming the cause.
      testCase "the continuation clause decorates a marker decideContinue accepts" $ do
        let decorated = "`" <> continueMarker <> "`"
        assertBool
          "the clause does not show the marker in the decoration this asserts"
          (says stackContinuation decorated)
        decideContinue ("work\n" <> decorated) @?= Left ("work\n" <> decorated)
    , -- The third ending is the reason this clause is not 'fixerContinuation'.
      -- A stacking run can be blocked by something no branch edit reaches — a
      -- design disagreement, an approved branch, a starved runner pool — and a
      -- worker with nowhere to put that either reports a completion it does not
      -- have or spins its fuel.
      testCase "the continuation clause admits the blocked ending" $
        report
          [ "stackContinuation does not say " <> tshow needle
          | needle <-
              [ "cannot continue without a person"
              , "for a person"
              , "Never report a block as completion"
              ]
          , not (saysLoosely stackContinuation needle)
          ]
    , -- The file the harness-run scripts learn this repository from. Q2 was
      -- exactly this drift in the other direction: the brief recorded the job
      -- budget into `.stack-plan.md`, `ci-budget.sh` read an environment
      -- variable, and the gate the workflow exists for enforced a default
      -- nobody chose. Both halves are asserted — the brief says to WRITE it,
      -- and each script says to READ it — because either half alone is a value
      -- with one home and no reader.
      testCase "the config the scripts read is the config the brief writes" $ do
        assertBool
          "the bootstrap brief never says to write .stack-config"
          (says stackTooling ".stack-config")
        report
          [ "the " <> script <> " body does not source .stack-config"
          | (script, marker) <-
              [ ("ci-budget.sh", "may I promote right now")
              , ("verify-stack.sh", "Verify a Graphite stack")
              , ("stack-status.sh", "Status of every branch in the stack")
              ]
          , let body = scriptBody marker (promptText stackTooling)
          , T.null body || not (T.isInfixOf ". \"$ROOT/.stack-config\"" body)
          ]
    , -- @docs/workflows.md@ says which lenses a stacking run edits through, and
      -- a lens joining an inline list moves no name, count or skeleton this file
      -- is checked on. 'Incite.Feature.stackPlanLenses' is the roster it reads —
      -- the same fence, and the same past failure, as the docs chain's.
      testCase "the Stacking a change section names every plan lens stack-prs runs" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let body = sectionBody "Stacking a change" doc
        assertBool "no Stacking a change section found" (not (T.null (T.strip body)))
        report
          [ "docs/workflows.md's Stacking a change section does not name " <> n
          | (name, _) <- stackPlanLenses
          , let n = leafNameText name
          , not (T.isInfixOf n body)
          ]
    ]

-- | Fences the tier that trades coverage for price, on what that trade buys and
-- on what it must not cost.
--
-- Everything else about @ship-feature-lite@ is a composition of bindings the
-- heavy path already fences: 'Incite.Feature.planLeaf',
-- 'Incite.Feature.implement', 'Incite.Feature.asReviewSubject',
-- 'Incite.Review.reviewLiteFlow' and 'Incite.Feature.remediate' are one binding
-- each, so a case here restating their contents would restate a fence rather
-- than add one. What is new is the cap, what the cap does when it runs out,
-- where that shows and where it does not, the grant, and where the chain stops.
liteTests :: TestTree
liteTests =
  testGroup
    "ship-feature-lite"
    [ -- The counterpart of @stack-prs@'s "both fuels are finite" case, and for
      -- the same reason: 'Incite.Feature.liteFuel' being 'Nothing' would make
      -- this tier's whole premise — a small change, priced before it runs —
      -- unstatable, and the flow would build, plan and run identically either
      -- way. The cost is asserted here as well as against the prose, so this
      -- stays a fence when the docs table is absent or when the reader below
      -- matches nothing.
      testCase "the fuel is finite, which is what keeps the cost a number" $ do
        assertBool "liteFuel is unbounded" (liteFuel /= Nothing)
        case worstCaseCost (toSkeleton (wfFlow shipFeatureLite)) of
          Finite n -> assertBool ("worst case is " <> show n) (n > 0)
          other -> assertFailure ("worst case is " <> T.unpack (renderCost other))
    , -- __What separates "converged" on trip three from "gave up" on trip
      -- three.__ Exhaustion yields rather than aborting, by
      -- 'Incite.Feature.orchestrateWith'\'s design, so a capped run that never
      -- finished still reaches the panel, the fixer and the close — and reads
      -- as a complete ship unless the text itself says otherwise.
      --
      -- It does say otherwise, and this is what asserts it: the summary yielded
      -- at trip n is the one that ASKED for trip n+1, so 'continueMarker' is
      -- still in it, and 'Incite.Feature.decideTrip' appends
      -- 'exhaustionNotice' under its own heading. A converged run ends on WORK
      -- COMPLETE and carries no notice. Nothing else in this repository tells
      -- the two outcomes apart. Where that text then goes — and where it does
      -- not — is the third case below, because a notice nobody can reach is
      -- not a distinction an operator has.
      --
      -- The trip number is the assertion, and 'tripWorker' is where that
      -- mechanism is argued for. Driven off 'Incite.Feature.liteFuel' rather
      -- than a literal, so this is an assertion about the constant the workflow
      -- actually passes.
      testCase "an exhausted loop yields the LAST trip's summary under the notice" $ do
        exhausted <- flowOutput "lite" (orchestrateWith liteFuel (tripWorker (const continueMarker))) "THE PLAN"
        exhausted @?= tripSummary (maybe 0 fuelMax liteFuel) continueMarker <> "\n\n" <> exhaustionNotice
    , -- The converged half of the same question, so the case above is a
      -- discrimination rather than a statement that every loop output carries
      -- the marker — and it converges BEFORE the cap, which is the other thing
      -- a loop-free 'Incite.Feature.orchestrateWith' would get wrong: the fuel
      -- is a ceiling, not a schedule, and a job finished on trip two costs two
      -- turns.
      --
      -- __The stopping trip is derived from the fuel, not written as 2.__ A
      -- literal here is an assertion about @'Just' 3@ and nothing else: lower
      -- 'Incite.Feature.liteFuel' to @'Just' 2@ and the case is back on the cap,
      -- where a fuel-as-schedule loop passes it again. One below the cap is
      -- short of it at every fuel, and the margin itself is asserted — a cap of
      -- one leaves no room to converge early and makes this case unstatable
      -- rather than false.
      testCase "a converged loop stops on the trip that said so, short of the cap" $ do
        let cap = maybe 0 fuelMax liteFuel
            stopAt = cap - 1
            doneThen n = if n >= stopAt then "WORK COMPLETE" else continueMarker
        assertBool ("liteFuel is " <> show cap <> ", which leaves no trip short of the cap") (stopAt >= 1)
        converged <- flowOutput "lite" (orchestrateWith liteFuel (tripWorker doneThen)) "THE PLAN"
        converged @?= tripSummary stopAt "WORK COMPLETE"
        decideContinue converged @?= Right converged
        assertBool
          "a converged run carries the exhaustion notice"
          (not (exhaustionNotice `T.isInfixOf` converged))
    , -- __Where the marker is legible, and where it is not.__ The two cases
      -- above fence what the LOOP yields. This one fences what becomes of that
      -- text afterwards, because @docs\/operations.md@ tells an operator where
      -- to read it and the wrong answer there is precisely the failure the
      -- marker exists to prevent — a capped run that gave up, read as a
      -- finished ship.
      --
      -- The loop's yield is an INPUT to the panel: 'Incite.Feature.orient' is a
      -- pure prepend, so 'Incite.Feature.asReviewSubject' points the lenses at
      -- the tree and carries the account in under it. Every stage after the
      -- loop then writes fresh text of its own, so the run's final artifact is
      -- 'Incite.Feature.remediate'\'s closing paragraph and carries neither
      -- marker. Both halves are asserted, and the second is what a relay added
      -- later would fail — which is the day the docs sentence changes.
      --
      -- 'runByLeaf' rather than 'flowOutput' because the question needs every
      -- leaf's answer told apart: one uniform answer is both the marker's source
      -- and the fixer's output, so an assertion about the final artifact would
      -- hold whichever leaf wrote it. Each leaf answers @\<\<its own name\>\>@,
      -- which is what makes @final@ below name the leaf that produced it.
      --
      -- __The relayed text is the whole summary, not the marker.__ Matching the
      -- bare phrase is satisfied by the first post-loop brief that QUOTES the
      -- marker — 'Incite.Feature.preambleOf' does not, but a lens rewritten to
      -- explain the status line would — and that passes with the relay broken,
      -- which is the exact failure this case was written after.
      testCase "the marker reaches the panel and never the final artifact" $ do
        let yielded = "edited three files\n" <> continueMarker
            byLeaf n = if n == "implement" then yielded else "<<" <> n <> ">>"
        (final, sent) <- runByLeaf shipFeatureLite byLeaf "THE PLAN"
        assertBool
          "no leaf after the loop was shown the summary the loop yielded"
          (any (\(n, rendered) -> n /= "implement" && T.isInfixOf yielded rendered) sent)
        -- And it reaches them ORIENTED. Nothing else fences the
        -- @dimap' asReviewSubject id@ around the panel: delete it and all five
        -- lenses review the worker's prose as though it were the change, with
        -- every other case here still green.
        report
          [ "the " <> n <> " lens was not pointed at the change"
          | n <- ["correctness", "fess", "complexity", "ponytail", "qa"]
          , not (any (\(leaf, rendered) -> leaf == n && T.isInfixOf (preambleOf AtChange) rendered) sent)
          ]
        -- The final artifact is the FIXER's own paragraph plus the gate's
        -- verdict under its heading — the loop's status is nowhere in it, which
        -- is why @docs/operations.md@ sends an operator to the transcript
        -- instead. The @✓@ line is upstream's @decodeOutcome@ spelling, written
        -- out for the reason the @ask:gate:@ fragment below is: the coupling is
        -- to another repository's literals and a rename there would otherwise
        -- weaken this to an assertion about nothing.
        final @?= "<<remediate>>\n\n## gate\n\n✓ flake-check (exit 0)"
    , -- __The grant, pinned to the binding the prose names.__ Every other case
      -- here reads 'Agent.Run.wfFlow'; this reads 'Agent.Run.wfGrant', which
      -- nothing else does for this workflow. README, AGENTS.md and
      -- @docs\/workflows.md@ all state that @ship-feature-lite@ runs under
      -- 'Incite.Feature.actingGrant' — swapping @workflowGReq@ for
      -- @workflowReq@ leaves every one of those claims false and the rest of the
      -- suite green.
      testCase "runs under actingGrant, which is what every document says" $
        wfGrant shipFeatureLite @?= actingGrant
    , -- __And what that grant contains__, which the case above cannot see: it
      -- pins the BINDING, so redefining 'Incite.Feature.actingGrant' as
      -- @execGrant [\"*\"]@ keeps it green while falsifying the @nix*@ claim in
      -- README, AGENTS.md and both documents. 'grindGrant' and 'stackGrant'
      -- carry this pair already; the shared grant had neither half.
      --
      -- Through 'permitExec' over @T.unwords@, which is what @Agent.Run@ applies
      -- to an 'Agent.Op.Exec' leaf, and over the gate's own argv rather than a
      -- transcription of it: a check the grant denies is refused inside the run
      -- (exit 126), so the gate reads a red no repair leaf can fix.
      testCase "actingGrant permits the gate's check as the runtime spells it" $
        report
          [ "denied by actingGrant: " <> tshow line
          | (_, cmd) <- codeChecks
          , let line = T.unwords (NE.toList cmd)
          , not (permitExec actingGrant line)
          ]
    , testCase "actingGrant denies what no check asked for" $
        report
          [ "actingGrant permits " <> tshow line
          | line <- ["rm -rf /", "git push origin master", "gh pr merge 1", "curl example.com"]
          , permitExec actingGrant line
          ]
    , -- __What the run ends on, stated as an order and as an absence.__
      --
      -- The order first: the last agent to touch the tree is the fixer, and a
      -- fixer that breaks the build closes its findings and writes a confident
      -- paragraph. Until the gate existed, that paragraph WAS the run's evidence
      -- that the tree still built. So the tail of the chain is asserted whole —
      -- the fixer, then the check we run ourselves, then the leaf that repairs a
      -- red one — and both directions fail: dropping the gate, and appending
      -- anything after it.
      --
      -- 'leafKinds' as well as 'leafNames', because a name cannot say whether a
      -- gate is real. @exec:flake-check@ is 'Agent.Flow.Combinators.verify'
      -- running argv and reading the exit code; the same stage written as an
      -- @agentVerify@ prompt keeps the name, the position and the cost, and asks
      -- an agent whether its own work passed.
      --
      -- Then the absence. 'shipDocs'\'s argument verbatim: an unattended run
      -- auto-answers a gate and @--sandbox@ isolates the working tree but not
      -- the network, so a PR leaf here would be an irreversible action with
      -- nothing in the run able to stop it.
      --
      -- __Not the only fence a gate or a PR leaf would move__, and worth being
      -- exact about the difference: 'Agent.Cost.worstCaseCost' counts every
      -- leaf, @Ask@ included, so an added leaf takes the worst case off the
      -- figure in the prose and @worstCaseTable@ below fails too. But that
      -- failure is repaired by
      -- editing a number in @docs\/workflows.md@ — which would wave the new leaf
      -- straight through. This case is the one whose only repair is removing the
      -- leaf.
      --
      -- __The leaf spellings are upstream's, not ours.__
      -- @Agent.Flow.Combinators.humanGate@ builds
      -- @LeafName (\"gate:\" <> question)@ under an @Ask@, which
      -- 'Agent.Op.opTagPrefixed' renders @ask:gate:…@; @submitPR@ is
      -- @refineWith \"submit-pr\"@. Written down because the coupling is to
      -- another repository's string literals and nothing in this one would
      -- otherwise say where they came from — a rename upstream turns these two
      -- fragments into an assertion that matches nothing, silently.
      testCase "the fixer is followed by the gate and by nothing else" $ do
        let names = leafNames (wfFlow shipFeatureLite)
            kinds = leafKinds (wfFlow shipFeatureLite)
            asks = [k | k <- kinds, T.isPrefixOf "ask:" k]
        assertBool "the flow has no leaves" (not (null names))
        dropWhile (/= "remediate") names @?= ["remediate", "flake-check", "repair"]
        assertBool
          "the gate is not a check we run ourselves"
          ("exec:flake-check" `elem` kinds)
        -- One question, and it is the steer BEFORE the work — the gate that
        -- costs nothing to auto-answer, because answering it wrong spends a
        -- planning turn rather than opening a pull request.
        --
        -- __Which side of the work it sits on is the whole safety argument__,
        -- and the identity of the single ask cannot state it: move the steer
        -- below the loop and it is still one @ask:steer:@, still auto-answered,
        -- and now it asks for guidance on work already done.
        map (T.takeWhile (/= ':') . T.drop 4) asks @?= ["steer"]
        assertBool "the flow has no implement leaf" ("implement" `elem` names)
        assertBool
          "the steer does not precede the implementation it steers"
          (any (T.isPrefixOf "steer:") (takeWhile (/= "implement") names))
        report
          [ "ship-feature-lite carries a " <> what <> " leaf"
          | (what, present) <-
              [ ("human gate", any (T.isPrefixOf "ask:gate:") kinds)
              , ("pull request", any (T.isInfixOf "submit-pr") names)
              ]
          , present
          ]
    , -- The figure in the prose, against the arithmetic — 'worstCaseTable'\'s
      -- second caller, and the reason it is a property rather than a second copy
      -- of the Stacking example.
      testCase "the Small changes worst-case table matches worstCaseCost" $
        worstCaseTable OneCount "Small changes" shipFeatureLite
    ]

-- | A worker stub that can be asked which trip it is on, given a closing status
-- as a function of the trip number.
--
-- __The trip count rides in the summary, because that is where the loop already
-- puts it.__ 'Incite.Feature.orchestrateWith' hands a worker its own previous
-- output as the next trip's input, so a worker that writes its trip number can
-- read the last one back and add one — no 'Data.IORef.IORef', and the counter is
-- carried by exactly the mechanism under test. A stub that ignores its input
-- (@const@) makes every trip identical and cannot tell three trips from one.
--
-- A @dimap'@ over 'Id' rather than a leaf: the fuel accounting is what these
-- cases are about, and a prompt leaf here would add a handler's answer between
-- the loop and the assertion.
tripWorker :: (Int -> Text) -> Flow Text Text
tripWorker close =
  dimap' id (\prev -> let n = tripOf prev + 1 in tripSummary n (close n)) Id

-- | What 'tripWorker' writes on trip @n@. Shared with the assertions so the
-- format is stated once — an expected value spelled out separately is a second
-- copy of the stub, and the two drift.
tripSummary :: Int -> Text -> Text
tripSummary n closing = "trip " <> tshow n <> "\n" <> closing

-- | The trip number 'tripSummary' wrote, or 0 for text it did not write (the
-- loop's first input is the plan, not a summary). Line one, because that is
-- where 'tripSummary' puts it: scanning further would read a number out of a
-- plan that happens to contain the word.
tripOf :: Text -> Int
tripOf prev =
  case reads . T.unpack =<< maybeToList (T.stripPrefix "trip " (T.takeWhile (/= '\n') prev)) of
    (n, "") : _ -> n
    _ -> 0

-- | The lens bodies "Incite.Review" writes as an upstream rubric plus one
-- adjustment, each paired with the rubric it is a delta against.
--
-- __A reorientation is a coupling, and nothing else here can see it.__ Its
-- correctness is a statement about text it does not contain: it repoints part
-- of the base and voids the rest, so an upstream edit breaks it __silently__ —
-- rename the section a delta voids and the voided section is live again; add a
-- fifth shape and nothing maps it, with no error anywhere. These cases are
-- where the base\'s structure is asserted at the point the delta enters it.
reorientations :: [(String, Prompt, Prompt)]
reorientations =
  [ ("docsAccuracy", fess, docsAccuracy)
  , ("ponytailOfDocs", ponytailAuditRubric, ponytailOfDocs)
  , ("architectureOfChange", reviewArchitecture, architectureOfChange)
  , ("haskellOfHouse", haskellReviewer, haskellOfHouse)
  , ("disciplineOfPanel", alexeyReview, disciplineOfPanel)
  , ("qaOfCommit", qaAgent, qaOfCommit)
  , ("docsStrategyOfPlan", technicalDocsStrategist, docsStrategyOfPlan)
  , ("slopOfDocs", stopSlop, slopOfDocs)
  , -- The grind rescopings. Each is an upstream or local rubric plus an
    -- adjustment, so each owes the same prefix property: splice the base
    -- verbatim, then adjust. A rescoping that PARAPHRASED its base would look
    -- fine everywhere else in this suite.
    ("ponytailOfTree", ponytailAuditRubric, ponytailOfTree)
  , ("grindSynthesis", reviewSynthesis, grindSynthesis grindName)
  , ("retroReport", retroSynthesis, retroReport)
  , -- One row per rescoping combinator, over a base each is actually applied to
    -- in `lensesOf OfTree`. 'ofTree' is 'reporting' after 'toTree', so its base
    -- must survive two adjustments rather than one.
    ("ofTree", reviewCorrectness, ofTree reviewCorrectness)
  , ("reporting", reviewArchitecture, reporting reviewArchitecture)
  , ("toTree", perfReviewer, toTree perfReviewer)
  ]

-- | The text a reorientation adds __below__ the rubric it splices. Meaningful
-- only where the base is a prefix, which is what
-- @every reorientation splices its base rubric verbatim@ establishes first.
adjustmentOf :: Prompt -> Prompt -> Text
adjustmentOf base reorientation =
  T.drop (T.length (promptText base)) (promptText reorientation)

-- | The section headings of a rubric, __derived rather than listed__: a line
-- that is entirely a bold span (the shapes 'fess' names) or a markdown @##@
-- heading (the parts 'ponytailAuditRubric' is built from).
--
-- Derived, because a hand-written list is the failure this check exists to
-- stop: a fifth section added upstream must arrive here on its own and go red
-- unmapped, rather than stay unmapped and silent.
sectionsOf :: Text -> [Text]
sectionsOf = concatMap headingOf . map T.strip . T.lines
  where
    headingOf l
      | Just h <- T.stripPrefix "## " l = [T.strip h]
      | T.isPrefixOf "**" l && T.isSuffixOf "**" l && T.length l > 4 =
          [T.strip (T.takeWhile (/= '—') (T.dropEnd 2 (T.drop 2 l)))]
      | otherwise = []

-- | Per reorientation: the sentences of its base that force an answer, and the
-- answer that must be in the adjustment.
--
-- Both sides are asserted. The __base__ needle is what makes the answer
-- necessary, so an upstream edit that drops the sentence goes red here rather
-- than leaving an answer to a question nobody asks any more.
voidedSentences :: [(String, Prompt, Prompt, [(Text, Text)])]
voidedSentences =
  [
    ( "docsAccuracy"
    , fess
    , docsAccuracy
    , -- The self-audit frame, the section with no document analogue, and the
      -- closing rule whose remedy inverts for prose: correcting a false
      -- sentence in a document IS editing the claim.
      [ ("Assume you have been dishonest", "the account is not yours")
      , ("Audit yourself against these", "read the document and its author instead")
      , ("List every file you modified", "scope creep — VOID")
      , ("not editing the claim", "editing that sentence")
      ]
    )
  ,
    ( "ponytailOfDocs"
    , ponytailAuditRubric
    , ponytailOfDocs
    , -- A document has no dependencies, so the output line the rubric fixes
      -- carries a figure prose cannot produce, and its scope sentence names
      -- over-engineering rather than prose.
      [ ("net: -<N> lines, -<M> deps possible.", "net: -<N> lines possible.")
      , ("Deps the stdlib or platform already ships", "is VOID")
      , ("over-engineering and complexity only", "over-engineering and complexity")
      , ("Lean already. Ship.", "Lean already. Ship.")
      ]
    )
  ,
    ( "disciplineOfPanel"
    , alexeyReview
    , disciplineOfPanel
    , -- The instruction the lens cannot follow (there is no `references/`
      -- directory in a prompt), and the three halves of the verdict that have no
      -- reader behind a panel: the GitHub grades, the conditional-approval
      -- formula, and the silent approval that a synthesis step cannot tell apart
      -- from a backend that never ran.
      [ ("Before reviewing, read both references", "spliced above")
      , ("Conflict rule", "conflict rule stands")
      , ("default to COMMENTED outside your competence", "You cast none.")
      , ("Verdict grammar", "Drop the verdict grammar")
      , ("LGTM up to X", "`LGTM up to X` formula")
      ]
    )
  ]

reorientationTests :: TestTree
reorientationTests =
  testGroup
    "reorientations"
    [ testCase "every reorientation splices its base rubric verbatim" $
        report
          [ T.pack label <> " does not start with its base rubric"
          | (label, base, reorientation) <- reorientations
          , not (T.isPrefixOf (promptText base) (promptText reorientation))
          ]
    , -- 'architectureOfChange' is absent on purpose: its delta is TOTAL
      -- (\"Everything else stands\"), so it maps every section at once and has
      -- nothing to enumerate. 'haskellOfHouse' is absent for the opposite
      -- reason — its delta ADDS rules and voids exactly one line of its base,
      -- which the case below is what fences. The two docs deltas void part of
      -- their base, and a part that is neither repointed nor voided is a
      -- section still pointed at code.
      testCase "every voiding reorientation names every section of its base" $
        report
          [ T.pack label <> " leaves section " <> tshow section <> " unmapped"
          | (label, base, reorientation, _) <- voidedSentences
          , let adjustment = T.toLower (adjustmentOf base reorientation)
          , section <- sectionsOf (promptText base)
          , not (T.isInfixOf (T.toLower section) adjustment)
          ]
    , testCase "every reorientation answers the base sentences it voids" $
        report
          [ complaint
          | (label, base, reorientation, pairs) <- voidedSentences
          , let adjustment = adjustmentOf base reorientation
          , (inBase, inAdjustment) <- pairs
          , complaint <-
              concat
                [ [ T.pack label <> ": base no longer says " <> tshow inBase
                  | not (T.isInfixOf inBase (promptText base))
                  ]
                , [ T.pack label <> ": adjustment does not say " <> tshow inAdjustment
                  | not (T.isInfixOf inAdjustment adjustment)
                  ]
                ]
          ]
    , -- 'haskellOfHouse' overrules exactly one rule of its base, and the
      -- override is a statement about text the addendum does not contain: drop
      -- the orphan-instance rule upstream and the addendum spends a section
      -- countermanding a rule nobody states, with nothing else to notice. Both
      -- sides are asserted for the same reason 'voidedSentences' asserts both.
      testCase "haskellOfHouse overrules a rule its base still states" $
        report
          [ complaint
          | complaint <-
              concat
                [ ["haskell-reviewer no longer lists orphan instances" | not (says haskellReviewer "Orphan instances")]
                , ["the house addendum no longer overrules them" | not (says haskellOfHouse "Orphan instances are fine here")]
                , -- The house rules the lens exists to carry: absent from the
                  -- base, so their presence here is the composition working.
                  [ "the haskell lens no longer carries " <> tshow rule
                  | rule <-
                      [ "No primitive in a top-level signature"
                      , "RecordWildCards"
                      , "DataKinds"
                      , "No partial field accessors"
                      , "Generically"
                      , "quickcheck-classes-base"
                      , "StrictData"
                      , "KnownNat"
                      , "genSingletons"
                      ]
                  , not (says haskellOfHouse rule)
                  ]
                ]
          ]
    , -- 'disciplineOfPanel' is a three-file splice, and only ONE of the three is
      -- its base — so every case above sees the skill and none of them can see
      -- whether the references arrived. That is the failure this lens exists to
      -- avoid: the skill's own first instruction is to read both before
      -- reviewing, and a lens carrying the instruction without the text is one
      -- whose reader invents what they said.
      testCase "disciplineOfPanel carries both references the skill demands" $
        report
          [ complaint
          | complaint <-
              concat
                [ [ "the discipline lens no longer carries " <> label
                  | (label, reference) <-
                      [("engineering-principles", alexeyPrinciples), ("stance", alexeyStance)]
                  , not (says disciplineOfPanel (promptText reference))
                  ]
                , -- And the adjustment has to SAY they are here. Splicing them
                  -- silently leaves the skill telling its reader to open a
                  -- directory that does not exist.
                  [ "the adjustment no longer says where the references went"
                  | not (says disciplineOfPanel "Both are spliced above")
                  ]
                ]
          ]
    , -- The guard on the two cases above: both quantify over lists derived from
      -- the bases, and a derivation that silently returned @[]@ would make them
      -- pass over nothing at all.
      testCase "the section reader finds the sections it is quantified over" $ do
        sectionsOf (promptText fess)
          @?= ["Verification gap", "Spec drift", "Scope creep", "Quiet downgrades"]
        sectionsOf (promptText ponytailAuditRubric)
          @?= ["Tags", "Hunt", "Output", "Boundaries"]
        sectionsOf (promptText alexeyReview)
          @?= [ "Identity guardrails (hard rules)"
              , "Review procedure"
              , "Severity gates"
              , "Output register"
              ]
    ]

-- | Fail with every complaint named, or pass on @[]@.
report :: [Text] -> Assertion
report [] = pure ()
report problems = assertFailure (T.unpack (T.intercalate "\n" problems))

-- | Every @promptFile@ path spliced in "Incite.Prompts", read out of the source
-- rather than listed here, so a brief added tomorrow is covered by being
-- written.
--
-- Comment lines are dropped first: the module haddock quotes the splice syntax
-- to explain it, and prose about a splice is not a splice.
splicedPromptPaths :: Text -> [Text]
splicedPromptPaths =
  map (T.takeWhile (/= '|'))
    . drop 1
    . T.splitOn "[promptFile|"
    . T.unlines
    . filter (not . T.isPrefixOf "--" . T.stripStart)
    . T.lines

-- | Where the recorded prompt bytes live, and the golden the @prompt-lint@
-- fence reads. Every other golden is a reframing\'s, named in 'reframings'.
goldenDir :: FilePath
goldenDir = "test/golden"

promptLintGolden :: FilePath
promptLintGolden = goldenDir <> "/prompt-lint-brief.txt"

-- | Every golden this suite reads, as data rather than parsed back out of this
-- file\'s source.
--
-- 'splicedPromptPaths' can read "Incite.Prompts" because a @promptFile@ splice
-- is a quasiquoter and nothing else looks like one. A golden path is an
-- ordinary string literal, which a fixture row or a failure message spells just
-- as well, so the same trick here finds things that are not reads. The list is
-- checked against the __directory__ instead, which is the set
-- @extra-source-files@ has to carry in any case.
goldensRead :: [FilePath]
goldensRead = promptLintGolden : remediateGolden : [path | (_, _, path) <- reframings]

-- | The entries of the cabal file\'s @extra-source-files@ stanza: the indented
-- non-comment lines after it, up to the next column-zero line.
extraSourceFiles :: Text -> [Text]
extraSourceFiles cabalFile =
  [ entry
  | l <- takeWhile indented (drop 1 (dropWhile (not . T.isPrefixOf "extra-source-files:") (T.lines cabalFile)))
  , let entry = T.strip l
  , not (T.null entry)
  , not (T.isPrefixOf "--" entry)
  ]
  where
    indented l = T.null (T.strip l) || T.isPrefixOf " " l

-- | Does one @extra-source-files@ entry carry this path? Two forms appear in
-- the stanza: a literal path, and a @dir\/*.ext@ glob, which matches one
-- directory level and one extension only.
--
-- The extension is read off the entry rather than fixed at @.md@, because the
-- goldens are @.txt@ and a matcher that only understood @.md@ would answer
-- \"not covered\" for every one of them — a cover test that fails loudly is
-- fine, but one that could only ever fail is not a cover.
covers :: Text -> Text -> Bool
covers entry path = case T.breakOn "*" entry of
  (_, "") -> entry == path
  (dirPrefix, star) ->
    let ext = T.drop 1 star
        rest = T.drop (T.length dirPrefix) path
     in T.isPrefixOf dirPrefix path
          && T.isSuffixOf ext rest
          && not (T.isInfixOf "/" rest)

packagingTests :: TestTree
packagingTests =
  testGroup
    "packaging"
    [ -- A `promptFile` path is checked when "Incite.Prompts" COMPILES and read
      -- when a leaf runs, and `extra-source-files` is what an sdist carries. So
      -- a directory spliced from but not listed is a package that builds in a
      -- git checkout and nowhere else — invisible to every other check here,
      -- because they all run in the checkout.
      testCase "extra-source-files carries every spliced prompt file" $ do
        promptsSource <- TIO.readFile "workflows/Incite/Prompts.hs"
        cabalFile <- TIO.readFile "incite-workflows.cabal"
        let paths = splicedPromptPaths promptsSource
            entries = extraSourceFiles cabalFile
        -- Both readers proved before either list is quantified over: an empty
        -- list on either side would make the assertion below pass over nothing.
        assertBool "no promptFile splices read" $
          "prompts/upstream/simple-english/skill.md" `elem` paths
        assertBool "no extra-source-files entries read" $
          "prompts/*.md" `elem` entries
        report
          [ "spliced but not packaged: " <> p
          | p <- paths
          , not (any (`covers` p) entries)
          ]
    , -- The same defect one layer over, and a worse one. A `promptFile` path is
      -- at least checked when "Incite.Prompts" compiles; a golden is read by
      -- `TIO.readFile` at run time, so an sdist that drops one builds green and
      -- then fails the suite with `openFile: does not exist`. Nothing else here
      -- can see it either: `checks.unit-test` copies ./test wholesale, so the
      -- one instrument that could notice is arranged not to.
      --
      -- Quantified over the DIRECTORY, so a golden is covered by existing.
      testCase "extra-source-files carries every golden on disk" $ do
        cabalFile <- TIO.readFile "incite-workflows.cabal"
        onDisk <- listDirectory goldenDir
        let entries = extraSourceFiles cabalFile
        -- The listing proved before it is quantified over: an empty directory
        -- would carry the report below over nothing at all.
        assertBool "no goldens found on disk" (not (null onDisk))
        report
          [ "recorded but not packaged: " <> T.pack g
          | f <- onDisk
          , let g = goldenDir <> "/" <> f
          , not (any (`covers` T.pack g) entries)
          ]
    , -- The same rule again, for the documents this suite reads with
      -- 'TIO.readFile'. It is not theoretical: the renderer-name fence below
      -- was written reading files that only a git checkout has, went green
      -- under @cabal test@, and failed the nix build with
      -- @README.md: openFile: does not exist@ — the exact failure the golden
      -- cover above exists to prevent, one directory over.
      -- Quantified over the @.md@ half of 'rendererProseFiles': the module
      -- haddocks it also reads are library sources, which an sdist carries
      -- because @hs-source-dirs@ names them and at the same paths. A markdown
      -- file has no such carrier.
      --
      -- __And over 'documentsRead' beside it__, because that roster is the gap
      -- this case had: it was quantified over one fence's file list, so a case
      -- added later reading anything else — a command file, @flake.nix@ — was
      -- outside it, and reproduced the very failure the comment above describes.
      testCase "extra-source-files carries every document this suite reads" $ do
        cabalFile <- TIO.readFile "incite-workflows.cabal"
        prose <- filter (".md" `isSuffixOf`) <$> rendererProseFiles
        let paths = nub (prose <> documentsRead)
            entries = extraSourceFiles cabalFile
        assertBool "no documents read" (not (null paths))
        report
          [ "read at run time but not packaged: " <> T.pack p
          | p <- paths
          , not (any (`covers` T.pack p) entries)
          ]
    , -- The same roster against the OTHER source list, because there are two.
      -- @extra-source-files@ is what an sdist carries; @flake.nix@'s @testSrc@
      -- fileset is what the nix build copies, and it is a separate hand-kept
      -- list the case above cannot see. Both readers added with this fence were
      -- missing from it: the suite went green under @cabal test@ with both
      -- cabal entries in place and then died under @nix flake check@ with
      -- @openFile: does not exist@ — the exact failure the case above exists to
      -- prevent, one list over.
      testCase "flake.nix's test fileset copies every document this suite reads" $ do
        nix <- TIO.readFile "flake.nix"
        prose <- filter (".md" `isSuffixOf`) <$> rendererProseFiles
        -- Both blocks, because @testSrc@ copies @librarySrc@ into itself. Read
        -- by marker rather than by "every ./ line in the file": the checks that
        -- render prompts declare filesets of their own, and counting those
        -- would let an entry in an unrelated derivation vouch for a file this
        -- suite reads.
        let entries = filesetOf "librarySrc =" nix <> filesetOf "testSrc =" nix
            covered p =
              let q = "./" <> T.pack p
               in any (\e -> e == q || (e <> "/") `T.isPrefixOf` q) entries
        assertBool "no fileset entries read from flake.nix" (not (null entries))
        report
          [ "read at run time but not in flake.nix's test fileset: " <> T.pack p
          | p <- nub (prose <> documentsRead)
          , not (covered p)
          ]
    , -- What keeps the case above honest in the other direction. Packaging a
      -- golden nothing reads is a file that drifts from the code it was
      -- recorded off with no test to say so, and packaging is exactly the step
      -- that would keep it looking alive. Compared as sorted lists, so a
      -- recorded-but-unfenced file and a read-but-unrecorded path both fail.
      testCase "every golden on disk is one this suite fences" $ do
        onDisk <- listDirectory goldenDir
        sort (map ((goldenDir <> "/") <>) onDisk) @?= sort goldensRead
    , -- The guard on the report above: it is only as strong as `covers`,
      -- and a glob matcher that said True to everything would carry them over
      -- any cabal file at all. One row per way an entry can fail to carry a
      -- path — deeper directory, wrong extension, wrong literal.
      testCase "an entry covers one directory level of one extension" $
        map
          (uncurry covers)
          [ ("prompts/*.md", "prompts/plan.md")
          , ("prompts/*.md", "prompts/explore/deep.md")
          , ("prompts/*.md", "prompts/notes.txt")
          , ("test/golden/*.txt", "test/golden/as-docs-subject.txt")
          , ("test/golden/*.txt", "test/golden/nested/x.txt")
          , ("test/golden/*.txt", "test/golden/as-docs-subject.md")
          , ("commands/fess.md", "commands/fess.md")
          , ("commands/fess.md", "commands/wiggum.md")
          ]
          @?= [True, False, False, True, False, False, True, False]
    ]

-- | The workflows "Main".workflows holds, rebuilt from library exports. This
-- suite cannot import "Main" — it is the executable, not a library module — so
-- this list is a hand-kept mirror of @workflows/Main.hs@'s @workflows@
-- binding, in the same order. A rename or reorder on either side is exactly
-- what 'docsInventoryTests' exists to catch.
mirrorWorkflows :: [Workflow]
mirrorWorkflows =
  [ planFeature
  , shipFeature
  , shipFeatureLite
  , shipDocs
  , stackPRs
  , grindParadox
  , grindTests
  , grindLiveView
  , fessAudit
  , retro
  , reviewLite
  , reviewHeavy
  , reviewAudit
  , reviewDocs
  , promptLint
  ]

-- | The row-level primitive every table reader here builds on: every markdown
-- table row whose first cell opens with a backticked name, paired with that
-- row's remaining cells (unparsed, unfiltered). Written once so the convention
-- for what counts as a row — split on @|@, strip, check the backtick prefix,
-- take the name up to the closing backtick — moves every reader together.
-- Before this was two independent copies, and reformatting the doc convention
-- meant finding and editing both in lockstep or watching them drift.
--
-- __Cells stay unparsed.__ A reader that parsed counts eagerly silently dropped
-- the rows that failed to parse, which is exactly the defect @docsInventoryTests@
-- exists to catch. Parsing — and reporting a parse failure — is the test's job.
tableRows :: Text -> [(Text, [Text])]
tableRows body =
  [ (name, drop 2 cells)
  | l <- T.lines body
  , let cells = T.splitOn "|" l
  , length cells > 1
  , let c1 = T.strip (cells !! 1)
  , T.isPrefixOf "`" c1
  , let name = T.takeWhile (/= '`') (T.drop 1 c1)
  ]

-- | The worst-case figure a @## @ section's table states, against the
-- arithmetic over the shipped flow. Quantified over every row of that table, so
-- a section that grows a second row is covered the day it does.
--
-- __A property standing in for two copies of one example.__ Two sections state
-- a worst case in prose, in tables of the same shape, and a fuel change, a panel
-- change or one more stage moves the number in either with nothing to notice.
--
-- __And it can pass vacuously, which is the whole risk of a Markdown parser as
-- a fence.__ A renamed heading or a changed table shape makes 'tableRows' match
-- nothing and every complaint below quantifies over the empty list. The
-- non-empty guard is what fails instead, and both failure modes were provoked
-- deliberately — the heading renamed, then a stated number perturbed — before
-- the worked example this replaced was deleted.
worstCaseTable :: WorstCaseColumns -> Text -> Workflow -> Assertion
worstCaseTable columns section wf = do
  doc <- TIO.readFile "docs/workflows.md"
  let rows = tableRows (sectionBody section doc)
  assertBool
    (T.unpack ("no worst-case row read from the " <> section <> " section"))
    (not (null rows))
  report
    [ complaint
    | (name, cells) <- rows
    , complaint <- case (name == wfName wf, columns, cells) of
        (False, _, _) -> [name <> ": the " <> section <> " table names a workflow this is not about"]
        (True, OneCount, raw : _) -> counted name raw
        (True, FullAndBlocked, full : blocked : _) ->
          counted name (if blockOpencode then blocked else full)
        (True, OneCount, []) -> [name <> ": the row carries no count"]
        (True, FullAndBlocked, _) -> [name <> ": the row does not carry both counts"]
    ]
  where
    counted name raw = case reads (T.unpack (T.strip raw)) of
      [(n, "")] ->
        let actual = worstCaseCost (toSkeleton (wfFlow wf))
         in [ name <> ": docs/workflows.md says " <> tshow n
                <> ", the flow's worst case is " <> renderCost actual
            | actual /= Finite n
            ]
      _ -> [name <> ": the leaf count " <> tshow raw <> " does not parse as an Int"]

-- | Which count cells a worst-case table carries: one figure, or the
-- full\/opencode-blocked pair whose live column 'blockOpencode' picks. A
-- workflow whose panel is a lens × backend cross-product moves with
-- @BLOCK_OPENCODE@ and must state both; one whose roster is written out per
-- leaf substitutes a backend without changing its count and states one.
data WorstCaseColumns = OneCount | FullAndBlocked

-- | The backticked name in a markdown table row's __first__ cell, for every row
-- that has one. Later cells (a lens name, a bound flow value) are deliberately
-- not read: the first cell is what a table like "Exposed inventory" or "Review
-- tiers and leaf counts" enumerates, and a prose cell may cite other backticked
-- names in passing.
tableFirstColumn :: Text -> [Text]
tableFirstColumn = map fst . tableRows

-- | The body of one @## Heading@ section: everything between it and the next
-- @## @ heading (or end of file). Both tables this suite fences sit under their
-- own @## @ heading, so this is what keeps 'tableFirstColumn' off tables that
-- name something other than a workflow — "Workflow constructors"' function
-- names, for one.
sectionBody :: Text -> Text -> Text
sectionBody heading doc =
  T.unlines
    . takeWhile (not . T.isPrefixOf "## ")
    . drop 1
    . dropWhile (/= ("## " <> heading))
    $ T.lines doc

-- | One fenced @```bash@ block out of the tooling brief, keyed by a line unique
-- to that script. The three scripts are markdown code fences rather than files
-- on disk — that is the whole point of the brief — so a test about their
-- content has to read them the way the agent will.
--
-- __Keyed on a comment line AND on the shebang.__ The file names all appear
-- together in the @.git\/info\/exclude@ block, which is itself a fence, so a
-- name-keyed reader returns that list instead. And the prose introducing a
-- script quotes the same sentence its header comment uses, so the marker alone
-- matches the paragraph above the fence. Requiring the shebang is what makes
-- this read the script rather than something that talks about it.
scriptBody :: Text -> Text -> Text
scriptBody marker doc =
  case [b | b <- T.splitOn "```" doc, T.isInfixOf marker b, T.isInfixOf shebang b] of
    (b : _) -> b
    [] -> T.empty
  where
    shebang = "#!/usr/bin/env bash"

-- | A small count as English prose, for reading a sentence like "eight
-- workflows are world-acting" back against the inventory. Past twenty the
-- sentence should be rewritten, not this extended.
numberWord :: Int -> Text
numberWord n
  | n >= 0 && n < length ws = ws !! n
  | otherwise = tshow n
  where
    ws = ["zero","one","two","three","four","five","six","seven","eight","nine","ten"
         ,"eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen"
         ,"eighteen","nineteen","twenty"]

-- | Fences 'docs/workflows.md' against the two things in it that only code can
-- prove: which workflows exist (in order), and how many leaves a review tier
-- costs. Neither is otherwise cross-validated — "Main".workflows and this file
-- are two hand-kept lists, and a leaf count is arithmetic over a 'Flow' value
-- that nothing forces back into the prose that quotes it.
docsInventoryTests :: TestTree
docsInventoryTests =
  testGroup
    "docs inventory"
    [ -- Direct list equality, not sorted-set equality. The table is meant to
      -- mirror 'mirrorWorkflows'\'s order (it is 'workflows/Main.hs'\'s order),
      -- and a bare set comparison cannot see a reorder: two tables naming the
      -- same thirteen workflows in different sequences would both read as the same
      -- set and this would stay green. Order is exactly what makes the claim on
      -- 'mirrorWorkflows' — "a rename or reorder on either side is exactly what
      -- this test exists to catch" — true.
      --
      -- Its failure output is a location rather than a count: both ordered lists
      -- print in full, so a misplaced entry shows which one moved and where to.
      -- Proved by putting @ship-feature-lite@ last in 'mirrorWorkflows' on
      -- purpose when it was added, and reading what came back.
      testCase "Exposed inventory names exactly the workflows this binary exposes, in order" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let named = tableFirstColumn (sectionBody "Exposed inventory" doc)
        assertBool "no workflow names read from the table" (not (null named))
        named @?= map wfName mirrorWorkflows
    , -- @worstCaseCost@ sums a sequence, and an unbounded orchestrator loop
      -- costs @maxBound `div` 2@ — so a workflow chaining TWO of them
      -- overflows and reports a NEGATIVE worst case: the number an operator
      -- reads before spending anything, going backwards. @grind-tests@
      -- shipped exactly that (its 'grindFlow' fixer plus its post-review
      -- fixer) and only a person running @cost@ by hand noticed.
      --
      -- __A sign check, one of three layers.__ The wrap itself is fixed at
      -- its cause: @Agent.Cost@ carries 'Integer' now, so no chain of loops
      -- can overflow at any count — under 'Int' two or three chained
      -- unbounded loops wrapped negative and landed here, and FOUR wrapped
      -- past 'maxBound' twice back to a small POSITIVE number this check
      -- waved through. The sign check stays because a wrong turn in the
      -- 'Cost' algebra itself still shows up as a sign flip, and the
      -- at-most-one-unbounded-loop law below keeps the render a number an
      -- operator can actually read.
      testCase "no exposed workflow reports a negative worst case" $
        report
          [ wfName wf <> " reports a non-positive worst case: " <> renderCost c
          | wf <- mirrorWorkflows
          , let c = worstCaseCost (toSkeleton (wfFlow wf))
          , case c of
              Finite n -> n <= 0
              Unbounded -> False
          ]
    , -- The policy law beside the sign check: at most ONE loop per chain may
      -- carry the unbounded sentinel (@maxBound `div` 2@). Overflow is gone —
      -- @Agent.Cost@ sums in 'Integer' — but a second sentinel loop still
      -- renders a worst case that reads as noise, and every second loop this
      -- repository has wanted so far was better served by a finite ceiling
      -- ('grindTestsReviewFuel', 'stackFuel'). Counted off each shipped
      -- skeleton the way 'leafNames' reads leaves, so a second unbounded
      -- fixer added to any chain goes red here whatever its cost renders as.
      testCase "no exposed workflow carries two unbounded loops" $
        report
          [ wfName wf <> " carries " <> tshow k <> " unbounded loops"
          | wf <- mirrorWorkflows
          , let k = unboundedLoopCount (wfFlow wf)
          , k > 1
          ]
    , -- The law's reader, refuted on the synthetic shape it exists to forbid
      -- — two unbounded orchestrator loops in sequence, pointed at no shipped
      -- workflow. A counter that missed 'FLoop' nodes, or matched a fuel the
      -- sentinel does not spell, would leave the law above passing over
      -- everything; a capped loop counting as unbounded would make it red on
      -- flows the sum arithmetic handles fine.
      testCase "the unbounded-loop reader sees a synthetic two-loop chain" $ do
        unboundedLoopCount (orchestrateWith Nothing Id) @?= 1
        unboundedLoopCount (orchestrateWith (Just (Fuel 12)) Id) @?= 0
        unboundedLoopCount (orchestrateWith Nothing Id >>> orchestrateWith Nothing Id) @?= 2
    , -- Every row this reads is either checked or turned into a named failure —
      -- never silently skipped. Two rows used to vanish before 'report' ever
      -- saw them: a row naming a workflow absent from 'mirrorWorkflows' (the old
      -- @Just wf <- [find …]@ pattern match failing inside the list
      -- comprehension, which drops that iteration rather than failing it), and a
      -- row whose count cell is not a bare 'Int' (dropped by the reader itself,
      -- back when it parsed eagerly). Both are text at this point — 'tableRows'
      -- does not parse — so both get their own complaint below instead of
      -- disappearing.
      -- __Which column, decided by the environment the suite runs in.__ The
      -- table states each tier twice — the roster with opencode, and the same
      -- tier under @BLOCK_OPENCODE@ — because the flows are built from
      -- 'Incite.Backend.backends', which reads that variable. A single column
      -- would have made this fence a statement about whoever's shell ran the
      -- suite: green under nix (which sandboxes the environment away) and red
      -- on the machine the variable exists for. Both columns are hand-written
      -- and each is checked whenever it is the live one, so neither is a
      -- restatement of the arithmetic it fences.
      testCase "Review tiers and leaf counts matches worstCaseCost . toSkeleton . wfFlow" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let counts =
              [ (name, T.strip (if blockOpencode then blocked else full))
              | (name, full : blocked : _) <- tableRows (sectionBody "Review tiers and leaf counts" doc)
              ]
        assertBool "no leaf-count rows read from the table" (not (null counts))
        report
          [ complaint
          | (name, raw) <- counts
          , complaint <- case find ((== name) . wfName) mirrorWorkflows of
              Nothing ->
                [name <> ": docs/workflows.md names a workflow mirrorWorkflows does not have"]
              Just wf -> case reads (T.unpack raw) of
                [(n, "")] ->
                  let actual = worstCaseCost (toSkeleton (wfFlow wf))
                   in [ name <> ": docs/workflows.md says " <> tshow n
                          <> ", the flow's worst-case leaf count is " <> renderCost actual
                      | actual /= Finite n
                      ]
                _ ->
                  [ name <> ": docs/workflows.md's leaf count " <> tshow raw
                      <> " does not parse as an Int"
                  ]
          ]
    , -- The same prices, quoted where a caller is steered between tiers. The
      -- two command files carried "21 reviewers" and "75 leaves" — two lens
      -- generations stale — because only the docs table above was fenced.
      -- Each needle is derived from the flow it prices, so the next lens
      -- added to the panel goes red here instead of aging in prose.
      testCase "the command files quote the fenced tier prices" $ do
        pca <- TIO.readFile "commands/post-commit-audit.md"
        cr <- TIO.readFile "commands/code-review.md"
        let leavesOf wf = renderCost (worstCaseCost (toSkeleton (wfFlow wf)))
            lensCount = countWord (length (lensesOf OfDiff))
            reviewerCount = tshow (length (lensesOf OfDiff) * length (NE.toList (backendsFor False)))
        report
          [ complaint
          | (path, txt, needle) <-
              [ ("commands/post-commit-audit.md", pca, lensCount <> " lenses")
              , ("commands/post-commit-audit.md", pca, leavesOf reviewAudit <> " leaves")
              , ("commands/code-review.md", cr, reviewerCount <> " reviewers")
              , ("commands/code-review.md", cr, leavesOf reviewHeavy <> " leaves")
              , ("commands/code-review.md", cr, leavesOf reviewAudit <> "-leaf")
              ]
          , let complaint = T.pack path <> " does not say " <> tshow needle
          , not (T.isInfixOf needle (proseNormal txt))
          ]
    , -- The Kind column, against the grants — and the counts in the prose,
      -- against the Kind column. "Five workflows are world-acting" survived two
      -- additions to the inventory because nothing read it: the grinds joined
      -- the table as world-acting and the sentence in README and AGENTS stayed
      -- at five. The ground truth is the grant: a workflow with a non-empty
      -- grant acts on the world, and one with 'mempty' has nothing to act
      -- with. Both halves are read back — each row's Kind cell, and the spelled
      -- count in the two prose files.
      testCase "the Kind column and the world-acting counts follow the grants" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let rows = tableRows (sectionBody "Exposed inventory" doc)
            acting = [wfName wf | wf <- mirrorWorkflows, wfGrant wf /= mempty]
        assertBool "no inventory rows read" (not (null rows))
        report
          [ name <> ": the Kind cell says " <> tshow kind <> ", the grant says " <> tshow want
          | (name, cells) <- rows
          , kind <- take 1 (map T.strip cells)
          , let want = if name `elem` acting then "world-acting" else "prompt-only" :: Text
          , kind /= want
          ]
        readme <- TIO.readFile "README.md"
        agents <- TIO.readFile "AGENTS.md"
        let phrase = numberWord (length acting) <> " workflows are **world-acting**"
        report
          [ T.pack path <> " does not say \"" <> phrase <> "\""
          | (path, txt) <- [("README.md", readme), ("AGENTS.md", agents)]
          -- Whitespace-collapsed on both sides, as 'saysLoosely' does: both
          -- files are hard-wrapped markdown and the phrase straddles a break.
          , not (T.isInfixOf phrase (T.unwords (T.words txt)))
          ]
    , -- The "Documentation workflow" section is where this file says what
      -- distinguishes a docs run, and it said "it uses only the SimpleEnglish
      -- plan lens" for as long as that chain has had two entries — while the
      -- inventory table and the `editPlan` bullet, in the same file, already
      -- said otherwise. Nothing could catch it: a lens joining an inline list
      -- inside a workflow moves no name, count or skeleton that this file is
      -- checked on. 'docsPlanLenses' is the roster it now reads.
      testCase "the Documentation workflow section names every plan lens ship-docs runs" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let body = sectionBody "Documentation workflow" doc
        assertBool "no Documentation workflow section found" (not (T.null (T.strip body)))
        report
          [ "docs/workflows.md's Documentation workflow section does not name " <> n
          | (name, _) <- docsPlanLenses
          , let n = leafNameText name
          , not (T.isInfixOf n body)
          ]
    , -- __The bullet that says where an upstream brief lands, against the flows
      -- that land it.__ README said @agentic-coder@ opens the implementer in
      -- @ship-feature@ while 'Incite.Feature.implement' had been hoisted to
      -- top-level for a second caller — so a reader of that bullet had no way to
      -- know that the same 8 KB brief, and the same unsupervised write access,
      -- is what the lite tier runs too.
      --
      -- The roster is DERIVED from the shipped flows rather than written here,
      -- which is what makes this survive the next tier: a third workflow reusing
      -- the leaf goes red on this case rather than on nothing.
      testCase "README's agentic-coder bullet names every workflow that runs the brief" $ do
        readme <- TIO.readFile "README.md"
        -- The bullet, not the section: its neighbours name workflows of their
        -- own, and a whole-section reader would pass on ponytail's line.
        let bullet = case dropWhile (not . T.isInfixOf "**agentic-coder**") (T.lines readme) of
              [] -> ""
              l : rest -> T.unlines (l : takeWhile (T.isPrefixOf "  ") rest)
            runners = [wfName wf | wf <- mirrorWorkflows, "implement" `elem` leafNames (wfFlow wf)]
        assertBool "no agentic-coder bullet found in README.md" (not (T.null (T.strip bullet)))
        assertBool "no workflow runs the implement leaf" (not (null runners))
        report
          [ "README's agentic-coder bullet does not name `" <> n <> "`"
          | n <- runners
          , not (T.isInfixOf ("`" <> n <> "`") bullet)
          ]
    ]

-- | Fences the prose that says __which backend runs which reviewer__ against
-- the scopes the flows carry.
--
-- This is the drift 'scopedLeaves' predicted and nothing caught. A backend pin
-- moves no leaf name, no node count and no cost, so every other check in this
-- file stays green while the documents go on quoting the old pairing — and they
-- did, in four places at once: @fess@ moved off codex and @qa@ joined the tier,
-- and @post-commit-audit.md@, @code-review.md@ and two rows of
-- @docs\/workflows.md@ all kept describing the tier before both changes. Three
-- of those files are the contract @\/wiggum@ and @ship-feature@ defer to, so the
-- stale text is what an agent acts on.
--
-- The inventory rule below reads a bare mention, so the table's convention is
-- to attribute backends __positively__: name the one a workflow runs on, not
-- the one it avoids. A row that reaches for \"never on codex\" as shorthand for
-- a pin gets a failure telling it to say what the pin IS — which is the more
-- useful cell anyway. (@review-docs@ names codex negatively and passes only
-- because it does run there; the exclusion it describes is one lens of five.)
backendProseTests :: TestTree
backendProseTests =
  testGroup
    "the prose that names backends"
    [ -- Quantified over the WHOLE inventory rather than the rows known to name
      -- a backend, so a row that acquires a backend claim later is covered the
      -- day it does. Rows are keyed by workflow name; a row naming no workflow
      -- needs no complaint here, because the case above already asserts the
      -- table's first column is exactly 'mirrorWorkflows'.
      testCase "no Shape cell names a backend its workflow does not run on" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let rows =
              [ (wf, cells)
              | (name, cells) <- tableRows (sectionBody "Exposed inventory" doc)
              , Just wf <- [find ((== name) . wfName) mirrorWorkflows]
              ]
            mentioned = [(wf, b) | (wf, cells) <- rows, b <- backendNames, any (T.isInfixOf b) cells]
        -- The reader proved before the rule is quantified over it: a table that
        -- named no backend at all would satisfy this rule vacuously, forever.
        assertBool "no Shape cell names any backend — the rule is over nothing" $
          not (null mentioned)
        -- The vocabulary must stay the FULL one under @BLOCK_OPENCODE@ too, or
        -- this rule quietly stops covering the name that blocking is about.
        assertBool "the backend vocabulary narrowed — opencode mentions would go unread" $
          "opencode" `elem` backendNames
        report
          [ wfName wf <> ": docs/workflows.md says " <> b <> ", but its leaves run on "
            <> T.intercalate ", " (runsOn wf)
          | (wf, b) <- mentioned
          , b `notElem` runsOn wf
          ]
    , -- The rule above only refutes a backend the workflow runs NOWHERE, which
      -- is blind to a tier that runs on all three and misattributes one lens —
      -- exactly 'reviewLite'. So the three files that state its roster state it
      -- lens by lens, and this reads the pairings back out of the flow.
      testCase "every file describing review-lite names its reviewers and their backends" $ do
        -- Routers subtracted, as in the qa fence: the documents count and pair
        -- REVIEWERS, and 'haskell-triage' is a branch decision, not a reviewer.
        let lenses =
              [ (n, a)
              | (n, a) <- scopedLeaves (wfFlow reviewLite)
              , n `notElem` map leafNameText reviewLiteRouters
              ]
        assertBool "review-lite has no leaves to describe" (not (null lenses))
        claims <- mapM (\(p, ws) -> (,,) p ws <$> TIO.readFile p) (reviewLiteProse lenses)
        report
          [ T.pack path <> " does not say \"" <> want <> "\""
          | (path, wants, txt) <- claims
          , want <- wants
          , not (T.isInfixOf want (proseNormal txt))
          ]
    ]
  where
    -- __The full roster, not the running one.__ These documents describe the
    -- configuration this repository ships, so the names they may be held to
    -- cannot depend on one machine's environment. Built from @backendsFor
    -- False@: reading 'Incite.Backend.backends' here narrowed the vocabulary to
    -- two names under @BLOCK_OPENCODE@, and the review-lite row's "qa on
    -- opencode" then matched nothing and went unchecked — the rule went dark on
    -- exactly the name blocking is about, and passed while doing it.
    backendNames = map leafNameText (map fst (NE.toList (backendsFor False)))
    -- What a workflow may be said to run on. Under @BLOCK_OPENCODE@ the opencode
    -- slot resolves elsewhere, so a document that correctly describes the
    -- default configuration would otherwise be reported as wrong for saying so.
    -- Adding the slot's default name back is what keeps the rule live for every
    -- OTHER name while blocked, rather than skipping the case wholesale: a row
    -- claiming a backend its workflow never touches is still caught either way.
    runsOn wf =
      let agents = nub (map (backendOf . snd) (scopedLeaves (wfFlow wf)))
       in agents <> ["opencode" | blockOpencode, leafNameText (fst opencodeBackend) `elem` agents]

-- | Fences @README.md@'s inputs table against the only thing that decides what
-- a third-party input can reach: @flake.nix@'s @builtins.readFile@ calls.
--
-- @awesome-prompts@ is 3.5 MB of unaudited leaked and community system prompts,
-- and the flake's named-file list is the whole of the allowlist. The README
-- documented it as three files and stayed at three across four more being
-- added, so the published account of what third-party text reaches a prompt
-- understated it by more than half. Nothing links the two but this.
-- | The one coupling between a command's instructions and the toolset of the
-- agent it deploys onto. @commands/code-review.md@ mandates @git fetch origin@
-- and a merge-base @git diff@; the command runs as the @code-review@ agent
-- (bound in @flake.nix@), whose frontmatter once set @bash = false@ — the
-- reviewer was ordered to run git with the one tool that could do it switched
-- off, and nothing went red. The denial is textual and today unique to that
-- agent, so its absence is what this reads; if another agent ever legitimately
-- denies bash, scope this to the @code-review@ attrset.
agentToolTests :: TestTree
agentToolTests =
  testGroup
    "the code-review agent's tools"
    [ testCase "the agent can run the git its command mandates" $ do
        nix <- TIO.readFile "flake.nix"
        cmd <- TIO.readFile "commands/code-review.md"
        assertBool
          "code-review.md no longer mandates the fetch — retire or repoint this fence"
          ("git fetch origin" `T.isInfixOf` cmd)
        assertBool
          "flake.nix denies bash while commands/code-review.md mandates git"
          (not ("bash = false" `T.isInfixOf` nix))
    ]

inputAllowlistTests :: TestTree
inputAllowlistTests =
  testGroup
    "the third-party prompt allowlist"
    [ testCase "README's awesome-prompts row lists exactly the files flake.nix reads" $ do
        nix <- TIO.readFile "flake.nix"
        readme <- TIO.readFile "README.md"
        let marker = "${awesome-prompts}/prompts/"
            allowed =
              sort . nub $
                [ T.takeWhile (/= '"') (T.drop (T.length marker) m)
                | (_, m) <- T.breakOnAll marker nix
                ]
            note = case [cs | (n, cs) <- tableRows (sectionBody "Inputs" readme), n == "awesome-prompts"] of
              (_ : c : _) : _ -> c
              _ -> ""
            listed = sort (nub [x | (i, x) <- zip [0 :: Int ..] (T.splitOn "`" note), odd i])
        -- Both readers proved before the equality is stated over them: either
        -- one reading nothing would make this an assertion that @[] == []@.
        assertBool "flake.nix reads no awesome-prompts file at all" (not (null allowed))
        assertBool "no awesome-prompts row found in README's Inputs table" (not (T.null note))
        listed @?= allowed
        assertBool ("README does not say " <> T.unpack (countWord (length allowed)) <> " files") $
          T.isInfixOf (countWord (length allowed) <> " files") note
    ]

-- | The files that describe 'reviewLite' in prose, and the phrases each must
-- carry given the tier's resolved leaves: the reviewer count, in the words that
-- file uses for it, and — for the two that go lens by lens — one @lens on
-- backend@ pairing per reviewer.
--
-- @code-review.md@ and @README.md@ each mention the tier in one line, and
-- state only the count, so only the count is required of them. Demanding a
-- full pairing list there would be demanding worse prose.
-- __The pairings are the DEFAULT roster's, and are only demanded of the prose
-- when that is the roster running.__ @qa@ is pinned to the opencode slot, which
-- resolves to codex under @BLOCK_OPENCODE@ — and these documents describe the
-- configuration this repository ships, not one machine's local override. Asking
-- them to say \"qa on codex\" because of an environment variable would be
-- demanding that the documents track a shell.
--
-- The count clause survives blocking, because the reviewer count is the same
-- either way, so neither mode leaves this fence checking nothing.
reviewLiteProse :: [(Text, Text)] -> [(FilePath, [Text])]
reviewLiteProse lenses =
  [ ("commands/post-commit-audit.md", count "independent reviewers" : pairings)
  , ("docs/workflows.md", count "per-commit reviewers" : pairings)
  , ("commands/code-review.md", [count "reviewers"])
  , -- Held to the count alone, like code-review.md: the README describes the
    -- tier in one clause of its lens-axis paragraph. It is in this list at
    -- all because it drifted once — a reviewer count nothing went red on.
    ("README.md", [count "reviewers"])
  ]
  where
    count noun = countWord (length lenses) <> " " <> noun
    pairings
      | blockOpencode = []
      | otherwise = [n <> " on " <> backendOf a | (n, a) <- lenses]

-- | A small count, spelled — which is how the documents write it, and so the
-- only form a substring check can look for.
countWord :: Int -> Text
countWord n = fromMaybe (tshow n) (lookup n (zip [1 ..] ws))
  where
    ws = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

-- | Prose flattened to what a phrase check can see through: markdown emphasis
-- dropped, and all whitespace collapsed to single spaces so a claim that
-- happens to wrap across a line still reads as one phrase.
proseNormal :: Text -> Text
proseNormal = T.unwords . T.words . T.filter (`notElem` ("`*" :: String))

-- | Every prompt a workflow's leaves actually send, in the order the sequential
-- interpretation reaches them — recovered by running the workflow's own 'Flow'
-- with a handler that records the rendered text and answers @\"\"@.
--
-- __This is what makes the golden below a fence on the shipped workflow rather
-- than on a re-derivation of it.__ Reading @'promptLintBrief' 'promptLintScope'@
-- in the test rebuilds the expression the workflow inlines, so rewiring the
-- workflow to a different scope — or to a different brief entirely — leaves
-- every promptLint assertion green. There is nothing else with the resolution to
-- catch that: @plan@ renders a flow SKELETON (node kinds, refs and leaf names),
-- so replacing the whole brief with @\"\"@ leaves its output byte-identical.
--
-- 'interpret' is 'Agent.Interpret.sequentialStrategy', so this is pure and
-- deterministic; the exec and ask handlers fail loudly because a review
-- workflow that grew a world-acting leaf is news.
workflowLeafPrompts :: Workflow -> IO [Text]
workflowLeafPrompts wf =
  flowLeafPrompts (T.unpack (wfName wf)) (wfFlow wf) (fromMaybe "" (wfInput wf))

-- | 'workflowLeafPrompts' for a bare 'Flow', which is what a leaf written ahead
-- of its workflow is. Named only for the failure messages.
flowLeafPrompts :: String -> Flow Text Text -> Text -> IO [Text]
flowLeafPrompts name flow input = do
  sent <- newIORef []
  _ <-
    interpret
      ( leafRunner
          LeafHandlers
            { lhPrompt = \rendered -> modifyIORef' sent (<> [rendered]) >> pure ""
            , lhExec = \cmd -> assertFailure (name <> " ran an exec leaf: " <> show cmd)
            , lhAsk = \_ -> assertFailure (name <> " reached an ask leaf")
            }
      )
      flow
      input
  readIORef sent

-- | 'workflowLeafPrompts' for an ACTING workflow, whose tail is a gate: exec
-- leaves answer a green exit instead of failing the traversal, so the
-- interpretation walks the same leaf sequence a clean run sends. What this
-- fences that nothing else can: a pure reframing stage between two leaves is
-- invisible to every skeleton reader ('flowOutput' says why), but its bytes
-- surface here inside the NEXT leaf's rendered prompt.
actingWorkflowLeafPrompts :: Workflow -> IO [Text]
actingWorkflowLeafPrompts wf = do
  sent <- newIORef []
  _ <-
    interpret
      ( leafRunner
          LeafHandlers
            { lhPrompt = \rendered -> modifyIORef' sent (<> [rendered]) >> pure ""
            , lhExec = \_ -> pure (ExecOutcome 0 "" "")
            , lhAsk = \_ -> assertFailure (T.unpack (wfName wf) <> " reached an ask leaf")
            }
      )
      (wfFlow wf)
      (fromMaybe "" (wfInput wf))
  readIORef sent

-- | What every prompt leaf answers under 'flowOutput'. Distinctive, so a merge
-- that puts an agent's output where the incoming log belongs is tellable from
-- one that does not — @\"\"@ would make both sides of a swap look alike.
leafAnswer :: Text
leafAnswer = "<<LEAF>>"

-- | What a flow RETURNS, rather than what its leaves were sent — the other half
-- of 'flowLeafPrompts'\'s interpretation, run the same way.
--
-- 'flowLeafPrompts' throws this value away, which is exactly why a pure stage
-- between two leaves has no fence anywhere: it changes no prompt, so that
-- helper cannot see it, and it carries no leaf name, so @plan@ cannot either.
flowOutput :: String -> Flow Text Text -> Text -> IO Text
flowOutput name flow input =
  fst
    <$> interpret
      ( leafRunner
          LeafHandlers
            { lhPrompt = \_ -> pure leafAnswer
            , lhExec = \cmd -> assertFailure (name <> " ran an exec leaf: " <> show cmd)
            , lhAsk = \_ -> assertFailure (name <> " reached an ask leaf")
            }
      )
      flow
      input

-- | A whole shipped workflow run with each prompt leaf answered __by name__,
-- returning the final artifact together with every rendered prompt and the leaf
-- it went to.
--
-- __Why not 'flowLeafPrompts' or 'flowOutput'.__ Both answer every leaf the same
-- thing, which cannot ask what one leaf's OUTPUT does to the stages after it: the
-- answer that makes the orchestrator loop exhaust would also be the answer the
-- fixer gives, so an assertion about the final artifact would hold for the wrong
-- reason. Dispatching on 'leafNameOf' is what keeps the worker's text and the
-- fixer's text distinguishable.
--
-- __The ask and exec handlers answer instead of failing__, unlike the two helpers
-- above: those interpret prompt-only flows, where either one is news. This is a
-- shipped acting workflow run unattended — it has a @steer@ the run auto-answers
-- and a gate it runs itself — so both are answered rather than refused.
--
-- The exec answer is @exit 0@: a green tree, which is the run this asks about.
-- It is not a claim that the gate works — 'Agent.Flow.Combinators.checkLoop'
-- owns the red path and 'Incite.Feature.isRed' is fenced directly — it is what
-- lets a caller assert what the stages AFTER a passing check produce.
runByLeaf :: Workflow -> (Text -> Text) -> Text -> IO (Text, [(Text, Text)])
runByLeaf wf answer input = do
  sent <- newIORef []
  final <-
    fst
      <$> interpret
        ( \sc op x ->
            let name = leafNameOf (opTag op)
             in leafRunner
                  LeafHandlers
                    { lhPrompt = \rendered -> do
                        modifyIORef' sent (<> [(name, rendered)])
                        pure (answer name)
                    , lhExec = \_ -> pure (ExecOutcome {eoExit = 0, eoStdout = "", eoStderr = ""})
                    , lhAsk = \_ -> pure (Answer "")
                    }
                  sc
                  op
                  x
        )
        (wfFlow wf)
        input
  (,) final <$> readIORef sent

-- | 'workflowLeafPrompts' for a workflow that is __one leaf__, failing rather
-- than picking one when it is not. @prompt-lint@ is a single @ste@ refinement
-- under two scopes, so a second leaf appearing is a change to what it sends and
-- belongs in the failure, not silently outside the fence.
onlyLeafPrompt :: Workflow -> IO Text
onlyLeafPrompt wf =
  onlyFlowLeafPrompt (T.unpack (wfName wf)) (wfFlow wf) (fromMaybe "" (wfInput wf))

-- | 'onlyLeafPrompt' for a bare 'Flow', for 'flowLeafPrompts'\'s reason — and
-- the binding every one-leaf assertion goes through instead of a
-- @[leafText] <- …@ pattern bind, whose failure is a bare 'MonadFail' pattern
-- error naming a source line and nothing else. A flow that grew a second leaf
-- is a change to what it sends, and the failure should say whose.
onlyFlowLeafPrompt :: String -> Flow Text Text -> Text -> IO Text
onlyFlowLeafPrompt name flow input = do
  sent <- flowLeafPrompts name flow input
  case sent of
    [one] -> pure one
    _ ->
      assertFailure $
        name <> " sends " <> show (length sent) <> " prompts, expected 1"

promptLintTests :: TestTree
promptLintTests =
  testGroup
    "promptLint"
    [ -- Every DIRECTORY a prompt body lives in, @workflows\/@ included.
      -- @checks.ste-prompts@ lints @.md@ files, so the prompt prose written as
      -- Haskell string literals has no other STE reader; dropping
      -- @workflows\/@ from the scope is what silently narrows this workflow to
      -- half the prompts, and no plan skeleton or cost estimate moves when it
      -- does.
      --
      -- Directories, not binding names. A row per reorientation would be a
      -- fourth hand-kept copy of a list this file already owns twice
      -- ('reorientations', 'expectedLensesOf') and the module owns once, and it
      -- would fence nothing the directory does not: it goes green on a renamed
      -- binding and silent on a new one.
      testCase "the leaf names every directory a prompt body lives in" $ do
        leafText <- onlyLeafPrompt promptLint
        mapM_
          ( \d ->
              assertBool
                (T.unpack d <> " is not in the leaf text")
                (T.isInfixOf d leafText)
          )
          [ "prompts/"
          , "commands/"
          , "agents/"
          , "skills/"
          , "workflows/"
          ]
    , -- A FENCE, not a smoke test. Nothing else in this repository can see the
      -- text this workflow sends, so an edit to it is invisible everywhere
      -- else. Total equality, so a reordering, a separator change or one
      -- reworded sentence all fail it — a suffix or infix check would not.
      --
      -- Read off the SHIPPED workflow (see 'workflowLeafPrompts'), so the fence
      -- stands between the recorded bytes and what @prompt-lint@ actually sends,
      -- rather than between the recorded bytes and a second copy of the
      -- expression that produced them.
      --
      -- The upstream half is NAMED rather than copied. Recording 'steSkill'\'s
      -- ~19 KB here would mirror a flake input into git (which
      -- @prompts\/upstream@ is gitignored to avoid) and go red on
      -- @nix flake update@ — a fence that cries wolf gets regenerated, which is
      -- the one thing it must never be. Every byte this repository owns is in
      -- the golden file, verbatim.
      --
      -- The @\\n\\n@ tail is 'Agent.Prompt.brief'\'s separator and the
      -- workflow\'s own input field, not a third copy of the brief.
      testCase "the leaf sends steSkill plus exactly the recorded local text" $ do
        recorded <- TIO.readFile promptLintGolden
        leafText <- onlyLeafPrompt promptLint
        leafText
          @?= promptText steSkill <> recorded <> "\n\n" <> fromMaybe "" (wfInput promptLint)
    , -- The parameterisation itself, which nothing else checks. Splicing the
      -- scope and then ignoring it, or splicing it twice, both leave the shipped
      -- brief looking right to every other assertion here.
      testCase "the scope reaches the brief exactly once" $
        T.count promptLintScope (promptText (promptLintBrief promptLintScope)) @?= 1
    , -- And it is the ONLY thing a scope moves: everything else 'promptLintBrief'
      -- adds is fixed, which is what lets a second panel borrow the rubric.
      testCase "the scope is the only thing a scope changes" $
        let other = "You are reading the reference manuals of a documentation repository."
         in promptText (promptLintBrief other)
              @?= T.replace promptLintScope other (promptText (promptLintBrief promptLintScope))
    ]

-- | The four stances @explorePlan@ fans out, by the names it gives them.
stanceNames :: [Text]
stanceNames = ["intrepid", "skeptic", "contemplative", "architect"]

-- | __Which model reads which leaf__, read off the shipped workflows.
--
-- See 'scopedLeaves': a backend scope moves nothing any other check in this
-- file can see. The two defects below were one commit's, and both were silent.
-- A mechanical rewrite of the stance list onto "Incite.Backend".@reviewer@
-- retyped the architect's backend, putting it on the backend @skeptic@ already
-- had — so a four-way fan-out bought with independence quietly became a
-- three-way one plus a duplicate, while its own comment went on saying the
-- opposite. The same rewrite pinned all six plan-editing lenses to codex with
-- no argument for it anywhere.
scopeTests :: TestTree
scopeTests =
  testGroup
    "backend scopes"
    [ -- The whole analysis half in one list, in the order the interpreter
      -- reaches it. Written out rather than derived, because every derivation
      -- available here reads the same expression the workflow is built from and
      -- would move with it.
      --
      -- @contemplative@ is the opencode stance, so its cell moves with
      -- @BLOCK_OPENCODE@: read off 'opencodeBackend' while opencode exists,
      -- because that binding IS what the stance is scoped to and a second
      -- spelling here could only disagree with it. Blocked, the stance lands
      -- on codex — whose leaf NAME is @codex@ but whose scope carries the
      -- 'Incite.Backend.gpt55' model pin — so that cell is spelled the way
      -- @skeptic@'s pin is, not read off a name that omits the model.
      testCase "plan-feature runs each leaf on the agent its module argues for" $
        scopedLeaves (wfFlow planFeature)
          @?= [ ("intrepid", "claude-agent")
              , -- Pinned, not inherited: an unpinned codex leaf runs on whatever
                -- ~/.codex/config.toml names, and a model codex-acp cannot drive
                -- fails every codex turn at once. See 'Incite.Backend.gpt55'.
                ("skeptic", "codex/gpt-5.5/xhigh")
              , ( "contemplative"
                , if blockOpencode
                    then "codex/gpt-5.5/xhigh"
                    else leafNameText (fst opencodeBackend)
                )
              , ("architect", "claude-agent/fable")
              , ("plan", "claude-agent/fable")
              , ("ponytail", runDefault)
              , ("denotational", runDefault)
              , ("risk", runDefault)
              , ("verification", runDefault)
              , ("lookahead", runDefault)
              , ("simple-english", runDefault)
              ]
    , -- The law the table above is one instance of, and the one that stays
      -- refutable when a fifth stance arrives. Four stances over three
      -- backends, so the fourth independence is bought with a MODEL —
      -- @claude-agent\/fable@ against @claude-agent@ — which is why this reads
      -- the whole agent spec and not the backend tag.
      --
      -- __Under @BLOCK_OPENCODE@ the law weakens, and it has to.__ The stances
      -- hold claude-agent, codex, claude-agent\/fable and opencode; drop
      -- opencode and three distinct agents remain for four stances, so a
      -- collision is FORCED rather than chosen — @contemplative@ lands on codex
      -- beside @skeptic@. What stays refutable is that the fan-out still uses
      -- every agent available to it: a second avoidable collision, or a stance
      -- silently re-pinned, moves this count.
      testCase "no two explore stances share an agent the roster can tell apart" $
        let stances = [a | (n, a) <- scopedLeaves (wfFlow planFeature), n `elem` stanceNames]
         in do
              -- The reader proved before the law is quantified over it: a
              -- renamed stance would otherwise make distinctness a statement
              -- about the empty list.
              length stances @?= length stanceNames
              length (nub stances)
                @?= (if blockOpencode then length stanceNames - 1 else length stanceNames)
    , -- THE UNPINNED BACKEND. A codex leaf that names no model runs on whatever
      -- @~\/.codex\/config.toml@ happens to say, and @codex-acp@ cannot drive a
      -- model it has no built-in metadata for (see 'Incite.Backend.gpt55'). One
      -- line in an interactive tool's settings file therefore failed every codex
      -- leaf in this repository at once — and @review-lite@, then five lenses,
      -- three of them on codex under @BLOCK_OPENCODE@, went on calling itself
      -- five independent reviewers while three of them returned nothing. (The
      -- same telling, at five, is in 'Incite.Backend' at the 'gpt55' pin.)
      --
      -- Quantified over the WHOLE inventory rather than the leaves that happened
      -- to be codex when this was written: the defect was six call sites each
      -- answering the model question for itself, so a law that only knows about
      -- today's six would miss the seventh.
      --
      -- Bare @"codex"@ is the unpinned spelling; @"codex/gpt-5.5/xhigh"@ is a pin.
      testCase "no shipped leaf runs on codex without naming a model" $
        [ (wfName wf, leaf)
        | wf <- mirrorWorkflows
        , (leaf, agent) <- scopedLeaves (wfFlow wf)
        , agent == "codex"
        ]
          @?= []
    , -- The leaf that writes the code, and the only pinned leaf in
      -- 'shipFeature'. Everything else there is deliberately on the run's own
      -- backend (the case below states that for the lens chains), so this one
      -- has to be asserted by name or the pin is indistinguishable from the
      -- default that happens to agree with it today.
      --
      -- @claude-agent@ with no @\/model@ suffix IS the pin: it names
      -- claude-agent's own default, which is Claude Opus. @claude-agent\/fable@
      -- here would mean implementation had been quietly moved onto the model the
      -- review lenses use, and 'runDefault' would mean the pin was dropped and a
      -- @--backend@ can move it again.
      testCase "ship-feature implements on claude-agent's default model, pinned" $
        lookup "implement" (scopedLeaves (wfFlow shipFeature)) @?= Just "claude-agent"
    , -- The same leaf, in the workflow that shares it. 'Incite.Feature.implement'
      -- is one binding, so this cannot drift from the case above by editing —
      -- what it catches is the lite tier acquiring a rescoping of its own, which
      -- a backend scope makes invisible to every other instrument here.
      testCase "ship-feature-lite implements on the same pinned leaf" $
        lookup "implement" (scopedLeaves (wfFlow shipFeatureLite)) @?= Just "claude-agent"
    , -- Read-only, as a statement about the resolved scope rather than about
      -- how many wrappers say so. This is what an outer @withMode Plan@ around
      -- the fan-out was there for, and what @reviewer@ already guarantees at
      -- each stance — so removing that wrapper has to leave this untouched.
      testCase "every analysis leaf is read-only, and only they are" $
        readOnlyLeaves (wfFlow planFeature) @?= stanceNames <> ["plan"]
    , -- And the wrapper is gone. One @mode:plan@ node per plan-mode leaf: a
      -- second wrapper around the fan-out reified a sixth, constraining nothing
      -- under it that @reviewer@ had not already constrained, and no other
      -- instrument here could see it — the case above stays green either way,
      -- and so does every leaf name, count and cost.
      testCase "plan-feature reifies one plan-mode scope per plan-mode leaf" $
        length (filter (== "mode:plan") (scopeDecls (wfFlow planFeature)))
          @?= length (stanceNames <> ["plan"])
    , -- 'editPlan' and 'docsPlanLenses' are two lens chains over one text, and
      -- the argument for leaving both on the run's own backend is that they are
      -- comparable. A pin on one of them is the drift this reads.
      testCase "ship-docs' plan lenses are unpinned, like ship-feature's" $
        let wanted = map (leafNameText . fst) docsPlanLenses
            named = [(n, a) | (n, a) <- scopedLeaves (wfFlow shipDocs), n `elem` wanted]
         in do
              map fst named @?= wanted
              report ["ship-docs pins " <> n <> " to " <> a | (n, a) <- named, a /= runDefault]
    ]

-- | The fence 'qaOfCommit' puts between its own question and its siblings',
-- against the tier that actually runs beside it.
--
-- @review-lite@ reduces by a pure fold with __no synthesis leaf__, so a defect
-- two lenses both report ships twice, on every commit, forever. That fence is
-- the only thing preventing it, and it lives as prose inside a prompt: drop a
-- lens from 'reviewLite' and the qa leaf goes on declining findings to an owner
-- that no longer exists, with no leaf name, count, plan skeleton or cost
-- estimate moving. Its roster is now a table, and this is what reads it against
-- the tier.
qaFenceTests :: TestTree
qaFenceTests =
  testGroup
    "the qa lens' fence"
    [ -- The claim in one line: the lenses qa declines to are exactly the ones
      -- beside it. Sorted, because the fold's order is 'hierarchical'\'s and is
      -- not this roster's business.
      -- The routers are subtracted before the equality: 'haskell-triage' is a
      -- leaf in the skeleton but owns no question, so qa fencing against it
      -- would tell qa to decline findings to a block that never reaches the
      -- fold. 'reviewLiteRouters' is the flow's own statement of which leaves
      -- those are, so a router added without joining that list still fails
      -- here.
      testCase "fences against exactly review-lite's other lenses" $
        sort (map (leafNameText . fst) qaSiblings <> ["qa"])
          @?= sort (filter (`notElem` map leafNameText reviewLiteRouters) (leafNames (wfFlow reviewLite)))
    , -- The roster reaching the SHIPPED leaf, once each. A table spliced and
      -- then ignored, or spliced twice, satisfies the case above and says
      -- nothing to the model.
      testCase "the leaf review-lite sends names every sibling exactly once" $ do
        sent <- workflowLeafPrompts reviewLite
        case filter (T.isInfixOf "No failure found.") sent of
          [qaText] ->
            report
              [ "the qa leaf names " <> n <> " " <> tshow (T.count n qaText) <> " times"
              | (name, _) <- qaSiblings
              , let n = "`" <> leafNameText name <> "`"
              , T.count n qaText /= 1
              ]
          other ->
            assertFailure $
              "review-lite sends " <> show (length other) <> " qa leaves, expected 1"
    , -- The mutation the fence exists to catch, run for real: a lens leaving
      -- the tier must leave the fence with it.
      testCase "a lens dropped from the roster is dropped from the fence" $
        assertBool "ponytail survives its removal from the roster" $
          not (says (qaOfCommitOver (filter ((/= "ponytail") . fst) qaSiblings)) "`ponytail`")
    , -- And the two counts are derived rather than spelled. A fifth lens in the
      -- tier would otherwise leave this leaf telling its reader there are five
      -- reviewers and four owners, which is prose nothing goes red on.
      testCase "the counts move with the roster" $
        report
          [ "a roster of " <> tshow (length roster) <> " does not say " <> tshow needle
          | roster <- [take 2 qaSiblings, take 3 qaSiblings, qaSiblings]
          , needle <-
              [ "one of " <> tshow (length roster + 1) <> " independent reviewers"
              , "The other " <> tshow (length roster) <> " own"
              ]
          , not (saysLoosely (qaOfCommitOver roster) needle)
          ]
    ]

-- | The pure half of review-lite's conditional haskell lens: what the triage
-- verdict does to the input. The routing default is the safety property here —
-- a verdict that is anything but a clean @none@ must run the lens, because the
-- failure mode of skipping is a review that silently never happened. The empty
-- verdict is the case the test interpreter produces for every leaf, so it is
-- also what keeps the haskell brief visible to 'workflowLeafPrompts'.
haskellRouteTests :: TestTree
haskellRouteTests =
  testGroup
    "routeHaskell"
    [ testCase "a clean none skips the lens, however decorated" $
        report
          [ "verdict " <> tshow v <> " did not skip"
          | v <- ["none", "None", "NONE", " none \n", "`none`", "none."]
          , routeHaskell "a docs-only change" (TriageVerdict v) /= Right "No Haskell edits."
          ]
    , testCase "anything else reviews, carrying the input verbatim" $
        report
          [ "verdict " <> tshow v <> " did not route to the lens"
          | v <- ["haskell", "", "Haskell files: none of them compile", "nonetheless, only docs"]
          , routeHaskell "the diff" (TriageVerdict v) /= Left "the diff"
          ]
    , -- The guard on the skip: the one failure the loud default cannot catch
      -- is a WELL-FORMED wrong `none` — a router that looked at the working
      -- tree instead of the diff it was handed, or was steered by text inside
      -- it. Where the input's own diff headers name a Haskell path, the
      -- verdict is overruled. `.cabal` is in the trigger set because the lens
      -- owns dependency-list findings.
      testCase "a none verdict cannot skip a diff that visibly touches Haskell" $
        report
          [ "input with header " <> tshow header <> " was skipped on a none verdict"
          | header <-
              [ "diff --git a/Foo.hs b/Foo.hs"
              , "+++ b/src/Bar.lhs"
              , "rename to Baz.hsc"
              , "+++ b/incite-workflows.cabal"
              ]
          , let input = "prose above\n" <> header <> "\ncontext below"
          , routeHaskell input (TriageVerdict "none") /= Left input
          ]
    , -- And the guard reads only header shapes, so diff CONTENT cannot hold
      -- the lens hostage: a changed line that merely mentions a Haskell file
      -- is not a Haskell edit.
      testCase "a content line naming a .hs file does not overrule the skip" $
        routeHaskell "+ see Foo.hs for the details\n" (TriageVerdict "none")
          @?= Right "No Haskell edits."
    , -- The list the fence and prose tests subtract is a claim about the flow;
      -- this is the other direction — every name it claims is a leaf the tier
      -- actually has, so a renamed triage leaf cannot leave the subtraction
      -- filtering nothing.
      testCase "every named router is a review-lite leaf" $
        report
          [ "review-lite has no leaf named " <> leafNameText r
          | r <- reviewLiteRouters
          , leafNameText r `notElem` leafNames (wfFlow reviewLite)
          ]
    , -- The wiring between the two leaves is a pure adapter, and a pure stage
      -- between two leaves has no fence anywhere else (see 'flowOutput'\'s own
      -- comment): swap the fan-out's pair order and the triage's one-word
      -- verdict is sent into the lens as its input, with every leaf name,
      -- count and cost unchanged and the routeHaskell cases above still green.
      -- So the rendered prompt is asserted. Under the test interpreter the
      -- triage answers @\"\"@, which routes to review, and the lens brief must
      -- then carry the workflow input — not that verdict.
      testCase "the lens leaf is sent the diff, not the triage verdict" $ do
        sent <- flowLeafPrompts "review-lite" (wfFlow reviewLite) "MARKER-diff-under-review"
        case filter (T.isInfixOf "Orphan instances are fine here") sent of
          [lensPrompt] ->
            assertBool "the haskell lens brief does not carry the workflow input" $
              T.isInfixOf "MARKER-diff-under-review" lensPrompt
          other ->
            assertFailure $
              "expected exactly one rendered haskell lens prompt, found " <> show (length other)
    , -- The skip arm, executed. Every other interpretation in this suite
      -- drives the review branch (empty verdicts route loud), so a mangled
      -- Right arm — a \"skip\" that still runs the lens, or one that loses the
      -- stand-in block — passed everything above. Here the handler answers the
      -- router's brief with `none` on an input naming no Haskell, so the skip
      -- must actually happen: the ~30 KB lens brief never renders, and the
      -- fold still prints a haskell block.
      testCase "a none verdict skips the lens and the fold carries the stand-in" $ do
        sentRef <- newIORef []
        (out, _) <-
          interpret
            ( leafRunner
                LeafHandlers
                  { lhPrompt = \rendered -> do
                      modifyIORef' sentRef (<> [rendered])
                      pure (if "You are a router" `T.isInfixOf` rendered then "none" else leafAnswer)
                  , lhExec = \cmd -> assertFailure ("review-lite ran an exec leaf: " <> show cmd)
                  , lhAsk = \_ -> assertFailure "review-lite reached an ask leaf"
                  }
            )
            (wfFlow reviewLite)
            "a docs-only change"
        sent <- readIORef sentRef
        assertBool "the haskell lens rendered despite a clean none" $
          not (any (T.isInfixOf "Orphan instances are fine here") sent)
        assertBool "the fold lost the stand-in block" $
          T.isInfixOf "No Haskell edits." out
    , -- The router's contract lives in its brief, and nothing else reads the
      -- rendered text: reword `none`, the one-word demand, or the extension
      -- set, and every skip silently becomes a paid lens run (or the reverse)
      -- with the whole suite green. The extension needles come from the same
      -- list the brief splices, so the set cannot drift from its guard; the
      -- token needles are the contract 'routeHaskell' actually parses.
      testCase "the triage brief carries its whole vocabulary" $ do
        sent <- workflowLeafPrompts reviewLite
        case filter (T.isInfixOf "You are a router") sent of
          [briefText] ->
            report
              [ "the triage brief does not say " <> tshow needle
              | needle <-
                  ["`none`", "`haskell`", "one word", "--name-only"]
                    <> ["`" <> e <> "`" | e <- haskellTriggerExtensions]
              , not (T.isInfixOf needle briefText)
              ]
          other ->
            assertFailure $
              "expected exactly one rendered triage brief, found " <> show (length other)
    ]

-- | Every @## Heading@ section of a document, in order: the heading text and
-- everything under it up to the next @## @ line.
--
-- 'sectionBody' answers for one known heading; this enumerates, which is what a
-- law quantified over sections needs.
sections :: Text -> [(Text, Text)]
sections = go . dropWhile (not . T.isPrefixOf "## ") . T.lines
  where
    go [] = []
    go (h : rest) =
      let (body, more) = break (T.isPrefixOf "## ") rest
       in (T.drop 3 h, T.unlines body) : go more

-- | One phrase per discipline @prompts\/grind\/paradox-facts.md@ states, chosen
-- so that only the sentence stating that discipline contains it.
--
-- The law they are quantified under is @exactly one section@, which refutes in
-- both directions: two sections is the duplication, and none is a needle that
-- has gone stale and stopped fencing anything.
factDisciplines :: [Text]
factDisciplines =
  [ "hand-edit"
  , "golden-reset"
  , "`Expression` ADT constructors"
  , "final gate"
  ]

-- | 'factDisciplines' for @prompts\/grind\/tests-facts.md@, under the same
-- exactly-one-section law. Its own list, not a shared one: each file's
-- disciplines are its own, and a needle checked against a file that never
-- states it would hold vacuously and fence nothing.
testsFactDisciplines :: [Text]
testsFactDisciplines =
  [ "regenerated"
  , "Never weaken"
  , "half a fix"
  , "compile lock"
  ]

-- | 'factDisciplines' for @prompts\/grind\/live-view-facts.md@, under the same
-- exactly-one-section law and with the same own-list reasoning.
liveViewFactDisciplines :: [Text]
liveViewFactDisciplines =
  [ "repaired in its source"
  , "half a registration"
  , "Never weaken"
  , "half a fix"
  , "compile lock"
  ]

-- | The opening words of every facts file's probe refusal, and the line the
-- derived synthesis brief refuses on. One binding read by both fences, so the
-- probe's cry and the synthesis's ear for it cannot drift apart.
factsRefusalLine :: Text
factsRefusalLine = "FACTS PATHS UNRESOLVED"

-- | Every grind facts file, labelled and carrying its own discipline needles:
-- the roster the structural laws below fold over. A new grind's facts file
-- joins the laws by joining this list — with a needle list of its own, because
-- the dedup law can only fence disciplines somebody wrote down for that file.
data GrindFactsFile = GrindFactsFile
  { gffLabel :: String
  -- ^ How a red case names the file.
  , gffFacts :: Prompt
  , gffDisciplines :: [Text]
  -- ^ The dedup law's needles, hand-written per file.
  }

grindFactsFiles :: [GrindFactsFile]
grindFactsFiles =
  [ GrindFactsFile {gffLabel = "paradox", gffFacts = paradoxFacts, gffDisciplines = factDisciplines}
  , GrindFactsFile {gffLabel = "tests", gffFacts = testsFacts, gffDisciplines = testsFactDisciplines}
  , GrindFactsFile {gffLabel = "live-view", gffFacts = liveViewFacts, gffDisciplines = liveViewFactDisciplines}
  ]

-- | The identifiers that pin a lens body to one repository — hand-listed from
-- the projects the grinds point at, matched case-insensitively. A lens body
-- carrying one belongs in that project's facts file instead.
--
-- @operation@ (the OTP app) subsumes @OperationWeb@ under the case-insensitive
-- infix match, and it is deliberately this broad: one day it will trip on an
-- innocuous English sentence, and that is a fair price, because the failure is
-- read by a human — who either moves a real identifier into the facts file or
-- rewords the sentence.
projectIdentifiers :: [Text]
projectIdentifiers =
  [ "operation"
  , "muex"
  , ".dox"
  , "Wallaby"
  , "excoveralls"
  , "Stryker"
  , "fstar"
  , -- The LiveView project's set. @ui.dox@ needs no entry of its own — the
    -- @.dox@ needle above already matches it.
    "topics.ex"
  , "PhxHook"
  , "assets/ts/hooks"
  ]

-- | The facts files the grinds prepend to every lens and splice into their
-- fixers' rules. No other instrument in this repository reads them: each file
-- is markdown, and 'promptText' is the only thing that ever looks inside one.
--
-- __A fold over the roster, not a case per file__, so the structural law
-- reaches a new facts file by the file joining the list — which is also what
-- keeps the two files one shape, and a fixer reading either one oriented the
-- same way.
factsFileTests :: TestTree
factsFileTests =
  testGroup
    "the grind facts files"
    [ -- The probe is what tells "the audit read nothing" from "the tree is
      -- clean", and it can only do that if the model reaches it before any
      -- path it is meant to check. First section, and nothing before it.
      testCase "every facts file opens with the probe, and holds the refusal line" $
        mapM_
          ( \gff -> do
              assertEqual
                (gffLabel gff <> ": section order")
                ["Probe first", "Project facts", "Repair disciplines"]
                (map fst (sections (promptText (gffFacts gff))))
              assertBool (gffLabel gff <> ": the refusal line is not inside the probe section") $
                T.isInfixOf (factsRefusalLine <> ":") (sectionBody "Probe first" (promptText (gffFacts gff)))
          )
          grindFactsFiles
    , -- The separation law: a grind lens body is repo-agnostic by
      -- construction, and every project identifier lives in the facts file
      -- instead. Nothing but this can see the difference — a lens body naming
      -- one repository's modules reports confident findings about paths that
      -- exist on no other tree, and it plans, costs and renders identically.
      -- The needle list is hand-written; extend it with the next grind's
      -- identifiers when its lenses land.
      testCase "no repo-agnostic grind lens names a project identifier" $
        report
          [ leafNameText name <> " names " <> tshow ident
          | (name, body) <- grindTestsLenses <> grindLiveViewLenses
          , ident <- projectIdentifiers
          , T.isInfixOf (T.toLower ident) (T.toLower (promptText body))
          ]
    , -- One home per fact, in every file. The paradox repair section restated
      -- the golden-reset ordering, the never-hand-edit rule, the
      -- interface-constructor ban and the test-filtering rule, all of which
      -- the facts above it already said — and the tests file stated the
      -- regenerate-never-hand-patch discipline in both its facts and its
      -- repair sections until this fence folded over it. Revised in one
      -- section, a two-home discipline goes stale in the other, inside one
      -- file that a fixer reads whole; each file carries its own needles,
      -- because a needle a file never states holds vacuously.
      -- Whitespace-normalised on both sides, for 'saysLoosely'\'s reason: these
      -- files are hard-wrapped markdown, so a needle is a phrase in the prose
      -- and not necessarily a substring of the bytes. Rewrapping a paragraph
      -- moved "final gate" across a line break and this went red for it — which
      -- is a fence crying wolf, and a fence that cries wolf gets regenerated.
      testCase "no discipline is stated in two sections" $
        let norm = T.unwords . T.words
         in report
              [ T.pack (gffLabel gff) <> " states " <> tshow needle <> " in " <> tshow (map fst hits)
              | gff <- grindFactsFiles
              , needle <- gffDisciplines gff
              , let hits =
                      [ s
                      | s@(_, body) <- sections (promptText (gffFacts gff))
                      , T.isInfixOf (norm needle) (norm body)
                      ]
              , length hits /= 1
              ]
    , -- The gate's argv and the facts file's command guidance are two
      -- statements of one fact for two consumers: the harness runs the argv
      -- ('Incite.Feature.grindTestsChecks', 'Incite.Feature.grindLiveViewChecks')
      -- and the agent reads the prose, and the markdown-on-disk convention
      -- keeps them in two homes on purpose. This is the drift fence between
      -- the homes — a gate command changed on one side goes red until the
      -- facts say the same thing. Both mix grinds, paradox excluded:
      -- paradox's test check carries an env-var prefix its facts file states
      -- as prose rather than verbatim, so a fold over it would demand bytes
      -- that file rightly does not hold.
      testCase "each mix grind's facts state every command its gate runs" $
        report
          [ label <> ": " <> leafNameText n <> "'s gate command is not a stated fact: " <> tshow inner
          | (label, checks, facts) <-
              [ ("tests", grindTestsChecks, testsFacts)
              , ("live-view", grindLiveViewChecks, liveViewFacts)
              ]
          , (n, cmd) <- checks
          , let inner = NE.last cmd
          , not (inner `T.isInfixOf` promptText facts)
          ]
    ]

-- | Every file in this repository whose PROSE names the prompt renderer: the
-- two root documents, the reference manuals, and the module haddocks.
--
-- Enumerated by directory rather than listed, so a document added tomorrow is
-- covered by existing.
--
-- __@flake.nix@ is deliberately not among them.__ It is where the input is
-- declared, so a stale name there is an evaluation error rather than a
-- documentation drift — @nix flake check@ is already the check for it, and
-- reading it here would rebuild this suite on every comment edit to a file
-- nothing else in the derivation depends on.
-- | Every file this suite opens at run time that 'rendererProseFiles' does not
-- already reach, and that an sdist has to be told to carry.
--
-- Built from 'reviewLiteProse' rather than restating its paths, so a file
-- joining that roster is packaged by the same edit that makes the suite read
-- it. Goldens have their own roster ('goldensRead'), and
-- @incite-workflows.cabal@ needs no entry — a package always ships its own
-- description.
documentsRead :: [FilePath]
documentsRead = "flake.nix" : map fst (reviewLiteProse [])

-- | The @./path@ entries of one @lib.fileset.unions@ block in @flake.nix@,
-- named by the binding it belongs to: from the marker to the @];@ that closes
-- the list.
filesetOf :: Text -> Text -> [Text]
filesetOf marker nix =
  [ e
  | l <- takeWhile (not . T.isInfixOf "];") (drop 1 (dropWhile (not . T.isInfixOf marker) (T.lines nix)))
  , let e = T.strip l
  , "./" `T.isPrefixOf` e
  ]

rendererProseFiles :: IO [FilePath]
rendererProseFiles = do
  docs <- listDirectory "docs"
  modules <- listDirectory "workflows/Incite"
  pure $
    ["README.md", "AGENTS.md"]
      <> ["docs/" <> f | f <- docs, ".md" `isSuffixOf` f]
      <> ["workflows/Incite/" <> f | f <- modules, ".hs" `isSuffixOf` f]

-- | __The renderer is called @flake-prompt@__, and has been since the flake
-- input was renamed. @agent-pm@ survives in exactly one shape: the NixOS and
-- home-manager option paths upstream still declares — @services.agent-pm@ and
-- @programs.agent-pm@ — which are that project's names for its modules and not
-- ours to rewrite.
--
-- Worth a test rather than one grep, because the rename landed in @flake.nix@
-- and stopped there: four comments in that file moved and nine references in
-- the documents, the module haddocks and the README did not. Nothing compiles
-- a comment, so the only thing that can hold the two names apart is this.
rendererNameTests :: TestTree
rendererNameTests =
  testGroup
    "the renderer's name"
    [ testCase "nothing calls the renderer by the name the flake input no longer has" $ do
        paths <- rendererProseFiles
        texts <- mapM (\p -> (,) p <$> TIO.readFile p) paths
        -- The reader proved before the report is quantified over it: an option
        -- path is the one legitimate use, so its absence means this is reading
        -- something other than this repository's files.
        assertBool "no `services.agent-pm` found — the reader is reading nothing" $
          any (T.isInfixOf "services.agent-pm" . snd) texts
        report
          [ T.pack path <> " names the renderer `agent-pm`, after \"" <> context <> "\""
          -- 'T.breakOnAll' rather than @init . T.splitOn@: it yields one prefix
          -- per occurrence by construction, where the split needed an @init@ to
          -- drop the trailing non-occurrence — a partial function standing on a
          -- proof ('T.splitOn' never returns @[]@) that lived in a comment.
          | (path, txt) <- texts
          , (before, _) <- T.breakOnAll "agent-pm" txt
          , not (any (`T.isSuffixOf` before) ["services.", "programs."])
          , let context = T.takeEnd 56 (T.unwords (T.words before))
          ]
    ]

backendTests :: TestTree
backendTests =
  testGroup
    "backends"
    [ -- Over 'backendsFor', not over 'backends': the shipped roster reads
      -- @BLOCK_OPENCODE@ through an 'unsafePerformIO' CAF, so an assertion on
      -- it states a property of whoever's shell ran the suite. The pure
      -- function is the same definition with the environment as an argument,
      -- and asking it both questions is what makes either answer a check.
      testCase "with opencode available, three backends" $
        map (leafNameText . fst) (NE.toList (backendsFor False))
          @?= ["claude-agent", "codex", "opencode"]
    , -- __The duplicate is dropped, not aliased.__ 'opencodeBackend' resolves to
      -- codex when blocked, so a roster that kept three slots would hold codex
      -- twice — and @panelAcross@ is a cross-product, so every lens would get
      -- two @lens\@codex@ leaves: one model's opinion, paid for twice and ranked
      -- as two findings. That failure is invisible in a leaf NAME list unless
      -- something asserts distinctness, so this does.
      testCase "with opencode blocked, codex takes its place exactly once" $ do
        let named = map (leafNameText . fst) (NE.toList (backendsFor True))
        named @?= ["claude-agent", "codex"]
        nub named @?= named
    , -- __The whole point of the variable, quantified over the inventory.__
      -- Everything else here fences a consequence of blocking — the roster
      -- shape, which backend answers the fess rubric, what each tier costs.
      -- None of them says the thing @BLOCK_OPENCODE@ exists to guarantee: that
      -- no leaf ANYWHERE resolves to opencode. A tier written later that pins a
      -- leaf with @withBackend opencode@ directly, rather than through
      -- 'opencodeScope', satisfies every other case in this file and still
      -- opens a session against a backend the machine cannot reach.
      --
      -- Both directions are asserted, because the blocked half alone is
      -- unfalsifiable: a repository that reached opencode nowhere would satisfy
      -- it forever. Unblocked, opencode must actually be reachable — which is
      -- what gives the blocked case something to bite on.
      testCase "BLOCK_OPENCODE removes opencode from every workflow, and nothing else does" $
        let agents = nub (map (backendOf . snd) (concatMap (scopedLeaves . wfFlow) mirrorWorkflows))
         in if blockOpencode
              then
                assertBool
                  ("blocked, but these workflows still resolve a leaf to opencode: " <> show agents)
                  ("opencode" `notElem` agents)
              else
                assertBool
                  "unblocked, no workflow reaches opencode at all — the blocked case fences nothing"
                  ("opencode" `elem` agents)
    , -- An environment variable that halves a review panel and is written down
      -- nowhere is a trap: nothing else in this suite reads the documents for
      -- it, and a reader who does not know it exists cannot explain why their
      -- run cost less than the table says. The leaf-count table's second column
      -- is checked by 'docsInventoryTests'; this is what keeps the prose that
      -- explains the column from being deleted out from under it.
      testCase "BLOCK_OPENCODE is documented, with what it costs" $ do
        doc <- proseNormal <$> TIO.readFile "docs/workflows.md"
        report
          [ "docs/workflows.md does not say " <> tshow needle
          | needle <-
              [ "BLOCK_OPENCODE"
              , -- The three consequences, each in the words that section uses.
                "panels get narrower"
              , "fess rubric always runs on claude"
              , "explore fan-out loses one axis"
              ]
          , not (T.isInfixOf needle doc)
          ]
    , -- __The name and the scope of the opencode slot, pinned together.__
      -- 'Incite.Review.admits' refuses the fess rubric to codex by reading a
      -- backend's NAME, so a slot whose name says @opencode@ while its scope
      -- runs codex keeps an admission it should have lost, and the rubric runs
      -- on codex anyway.
      --
      -- Nothing else here catches that. 'backendsFor' never calls
      -- 'opencodeBackendFor' on its blocked branch — it drops the entry — so
      -- the roster cases above stay green under the decoupling. The
      -- resolved-scope check in 'codexFessTests' does catch it, but only when
      -- @BLOCK_OPENCODE@ is set, and nix sandboxes that variable away: in CI
      -- that check has never once run against a blocked roster. This is the
      -- one that runs in both.
      --
      -- The scope is resolved through 'Incite.Backend.reviewer' — the same
      -- builder the shipped stances go through — rather than trusted from the
      -- name beside it. A pair whose two halves are read off each other proves
      -- nothing about either.
      testCase "the opencode slot's name and its scope name the same backend" $
        let resolved (n, scope) =
              (leafNameText n, map snd (scopedLeaves (snd (reviewer scope "probe" anyPrompt))))
         in do
              resolved (opencodeBackendFor False) @?= ("opencode", ["opencode"])
              -- The substituted scope carries codex's model pin with it — a
              -- blocked opencode leaf must land on the same named model as any
              -- other codex leaf, not on the settings file's default.
              resolved (opencodeBackendFor True) @?= ("codex", ["codex/gpt-5.5/xhigh"])
    , -- The fence the substitution leans on, stated where the substitution is.
      -- "Incite.Review".'admits' refuses the fess rubric to codex by reading a
      -- backend's NAME, so the name and the scope have to move together: swap
      -- the scope to codex under the name @opencode@ and the rubric keeps its
      -- admission and runs on codex anyway. With the entry substituted whole,
      -- claude-agent is the only backend left that admits it — which is the
      -- property that makes blocking safe rather than merely quiet.
      testCase "blocked, the fess rubric is left with claude-agent alone" $
        [ b
        | b <- map fst (NE.toList (backendsFor True))
        , admits b fess
        ]
          @?= ["claude-agent"]
    , -- 'NE.head' rather than 'head': the list is 'NonEmpty' so that
      -- @Incite.Review.spread@ can cycle it without a guard, and this case
      -- comes along for free — there is no empty case left to answer.
      testCase "claudeAgentBackend name matches first entry" $
        leafNameText (fst claudeAgentBackend)
          @?= leafNameText (fst (NE.head backends))
    ]
