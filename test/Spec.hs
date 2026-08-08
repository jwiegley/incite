module Main (main) where

import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, isSuffixOf, nub, sort, (\\))
import qualified Data.List.NonEmpty as NE
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (listDirectory)
import Test.Tasty
import Test.Tasty.HUnit

import Agent.Cost (Cost (..), renderCost, worstCaseCost)
import Agent.Grant (permitExec)
import Agent.Flow (Flow, Mode (Plan), foldLeavesScoped)
import Agent.Flow.Skeleton (FlowF (..), Rooted (..), toSkeleton)
import Agent.Interpret (LeafHandlers (..), interpret, leafRunner)
import Agent.Op (LeafName, Scope (..), agentSpecText, leafNameOf, leafNameText, opTag, scopeDeclText)
import Agent.Prompt (Prompt, prompt, promptText)
import Agent.Run (Workflow (..))
import Incite.Backend (backends, claudeAgentBackend)
import Incite.Feature
  ( Orientation (..)
  , fixerContinuation
  , closeWithChanges
  , paradoxRule
  , grindChecks
  , grindGrant
  , grindParadox
  , asRetroSubject
  , asDocsSubject
  , asReviewSubject
  , codeRule
  , continueMarker
  , decideContinue
  , decideRed
  , docsRule
  , docsPlanLenses
  , isRed
  , document
  , orient
  , planFeature
  , preambleOf
  , preambleViolations
  , remediate
  , retrospective
  , shipDocs
  , shipFeature
  )
import Incite.Prompts
  ( codeReview
  , codeReviewerSecurity
  , docsCompleteness
  , docsStructure
  , fess
  , fixAll
  , paradoxFacts
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
  , reviewSynthesis
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
  , forbiddenPairings
  , grindName
  , grindSynthesis
  , toTree
  , architectureOfChange
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
  , reviewAudit
  , reviewDocs
  , reviewHeavy
  , reviewLite
  , slopOfDocs
  , spread
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "incite-workflows"
    [ decideContinueTests
    , isRedTests
    , continueMarkerTests
    , reframingTests
    , preambleViolationsTests
    , orientTests
    , documentTests
    , remediateTests
    , retrospectiveTests
    , lensSetViolationsTests
    , lensesOfTests
    , codexFessTests
    , grindPanelTests
    , reorientationTests
    , promptLintTests
    , packagingTests
    , backendTests
    , scopeTests
    , qaFenceTests
    , factsFileTests
    , rendererNameTests
    , docsInventoryTests
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
-- 'document' is the one that can be read here. @implement@ is bound inside
-- 'Incite.Feature.shipFeature', which is why the second worker brief was
-- written top-level.
documentTests :: TestTree
documentTests =
  testGroup
    "document"
    [ testCase "is one leaf" $ do
        sent <- flowLeafPrompts "document" document "THE PLAN"
        length sent @?= 1
    , -- Round trip through the decider, not a substring check on the marker.
      -- The brief shows the marker decorated — @`WORK REMAINS`@ — and what has
      -- to hold is that the decorated form the worker copies is one
      -- 'decideContinue' reads as "call me again". It fails if the brief wraps
      -- the marker in something outside the decoration alphabet, or if the
      -- marker itself grows a character that alphabet does not strip.
      --
      -- The bullet's trailing prose is deliberately not fed in: the brief says
      -- the status line stands alone, so the contract is about the token.
      testCase "the marker as the brief decorates it is one decideContinue accepts" $ do
        [leafText] <- flowLeafPrompts "document" document "THE PLAN"
        let decorated = "`" <> continueMarker <> "`"
        assertBool
          "the brief does not show the marker in the decoration this asserts"
          (T.isInfixOf decorated leafText)
        decideContinue ("work\n" <> decorated) @?= Left ("work\n" <> decorated)
    , -- The input is the plan, not the findings: @document@ sits where
      -- @implement@ sits, after @steer@ and inside the loop. Findings are
      -- 'Incite.Feature.remediate'\'s input, downstream of the panel.
      testCase "hands the plan to the worker" $ do
        [leafText] <- flowLeafPrompts "document" document "THE PLAN"
        assertBool "the input is not in the leaf" (T.isInfixOf "THE PLAN" leafText)
    , -- The same contract on the fixer that runs under an orchestrator, and the
      -- same failure if it drifts. 'grindParadox' wraps @remediate@ in
      -- 'Incite.Feature.orchestrate', so this clause is what asks for another
      -- trip; a marker the decider does not read strands that loop for its whole
      -- fuel with nothing in any output naming the cause.
      --
      -- Round trip through 'decideContinue' rather than a substring check, for
      -- 'documentTests'\'s reason: what has to hold is that the DECORATED form
      -- the brief shows is one the decider accepts.
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
    , -- The one rule this brief exists to carry that @implement@ must not.
      -- Whitespace-normalised, so rewrapping the paragraph is not a failure —
      -- the sentence being gone is.
      testCase "forbids editing code to make a sentence true" $ do
        [leafText] <- flowLeafPrompts "document" document "THE PLAN"
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
        [leafText] <- flowLeafPrompts "remediate" (remediate codeRule mempty) "THE FINDINGS"
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
        [bare] <- flowLeafPrompts "remediate" (remediate codeRule mempty) "THE FINDINGS"
        [closed] <- flowLeafPrompts "remediate" (remediate codeRule closeWithChanges) "THE FINDINGS"
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
        [underCode] <- flowLeafPrompts "remediate" (remediate codeRule mempty) "THE FINDINGS"
        [underDocs] <- flowLeafPrompts "remediate" (remediate docsRule mempty) "THE FINDINGS"
        T.count (promptText codeRule) underCode @?= 1
        underDocs @?= T.replace (promptText codeRule) (promptText docsRule) underCode
    , -- The grind fixer's rule carries the tree's facts as well, and that is
      -- the only route by which they reach it: the audit half gets them from
      -- the workflow input, which is long out of scope by the time a fixer runs
      -- on a ranked list of findings.
      testCase "the grind fixer stands under the code rule and the tree's facts" $ do
        [leafText] <- flowLeafPrompts "remediate" (remediate paradoxRule fixerContinuation) "THE FINDINGS"
        report
          [ "the grind fixer does not carry " <> label
          | (label, needle) <-
              [ ("codeRule", promptText codeRule)
              , ("the facts file", promptText paradoxFacts)
              , ("the continuation clause", promptText fixerContinuation)
              ]
          , not (T.isInfixOf needle leafText)
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
      testCase "Orientation enumerates 3 constructors" $
        length ([minBound .. maxBound] :: [Orientation]) @?= 3
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
    ]
  OfChange ->
    [ ("correctness", reviewCorrectness)
    , ("security", codeReviewerSecurity)
    , ("tests", reviewTests)
    , ("performance", perfReviewer)
    , ("haskell", haskellOfHouse)
    , ("ponytail", ponytailAuditRubric)
    , ("doctrine", codeReview)
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
      testCase "no workflow builds a leaf that pairs the rubric with codex" $
        report
          [ wfName wf <> " builds " <> n
          | wf <- mirrorWorkflows
          , n <- leafNames (wfFlow wf)
          , fessNamed n
          , "@codex" `T.isSuffixOf` n
          ]
    , -- The guard on the case above: it reads leaf NAMES, so it only refutes
      -- while the fess-carrying lenses are still named what this expects. A
      -- panel that renamed them would leave it passing over nothing.
      testCase "the leaf-name reader finds the fess leaves it is quantified over" $
        report
          [ "no fess-named leaf in " <> wfName wf
          | wf <- [reviewLite, fessAudit, reviewDocs]
          , not (any fessNamed (leafNames (wfFlow wf)))
          ]
    ]
  where
    backendNames = map fst (NE.toList backends)
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
    , -- The guard on the body fence below, and on the backend pairing: two
      -- lenses rendering the same text are two leaves doing one leaf's work on
      -- two different models, which reads as agreement in the synthesis.
      testCase "no grind lens repeats another's body" $
        let bodies = map (promptText . snd) grindLenses
            repeats = bodies \\ nub bodies
         in report (map (("repeated grind lens body: " <>) . bodyTag) (nub repeats))
    , -- The output contract, as a property of every body the panel sends. See
      -- 'grindContract' for why the needles are literals here.
      testCase "every grind lens carries the finding contract" $
        report
          [ leafNameText name <> " does not say " <> tshow needle
          | (name, body) <- grindLenses
          , needle <- grindContract
          , not (says body needle)
          ]
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
    , testCase "emission lenses carry the bodies they name" $
        report (lensBodyMismatches expectedEmissionLenses emissionLenses)
    , -- 'spread' is a zip against a cycled backend list, so the leaf count is
      -- the LENS count — not @min@ of the two, and not the cross-product a
      -- panel would give.
      --
      -- __A law about 'spread', and it needs the case below beside it.__ Both
      -- sides here are derived from 'grindLenses', so a lens deleted from the
      -- panel moves them together and this stays green. What it refutes is
      -- 'spread' itself: point it at @panelAcross@ and the count triples.
      testCase "spread gives one leaf per lens" $
        length (leafNames (spread backends grindLenses)) @?= length grindLenses
    , -- The panel's WIDTH, as a plain number, because the law above cannot see
      -- it. 42 leaves is what a full panel over these lenses would cost and 14
      -- is what @grind-paradox@ pays; a lens quietly dropped from either half
      -- of the union is a lens nobody runs, and the run reports a clean tree
      -- for the part it never read.
      testCase "the grind panel is 14 lenses wide" $
        length grindLenses @?= 14
    , -- __The shipped workflow, not a union assembled here.__ Every case above
      -- reads 'grindLenses', which this file composes; nothing forced
      -- @grindParadox@ to compose the same thing in the same order. Union the
      -- two halves the other way round in production and every law above stays
      -- green while a different model audits each lens — which is exactly the
      -- reassignment the ordered name list is supposed to catch.
      --
      -- So this reads the WORKFLOW's own skeleton, and it pins the pairing
      -- rather than the order: a reader can see here that @stubs@ runs on
      -- opencode without executing the zip in their head.
      testCase "grind-paradox fans out exactly these lens@backend leaves" $
        let panelLeaves = takeWhile (/= "synthesis") (leafNames (wfFlow grindParadox))
         in panelLeaves
              @?= [ "correctness@claude-agent"
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
    , -- The acting half's leaves, in order, after the panel. A stage dropped
      -- from the chain — the fixer, the repair leaf, either check — leaves a
      -- workflow that still plans and still costs, and reports a green gate it
      -- never ran.
      testCase "grind-paradox then synthesises, fixes, and gates on real checks" $
        dropWhile (/= "synthesis") (leafNames (wfFlow grindParadox))
          @?= ["synthesis", "remediate", "build", "tests", "repair"]
    , -- And the pairing preserves distinctness: 'unionFindings' heads each
      -- block by leaf name, so two leaves sharing one would make two reviewers
      -- indistinguishable in the reduction. Distinct LENS names do not imply
      -- distinct LEAF names on their own — the pairing is what appends the
      -- backend tag, and this is the case that reads the result.
      testCase "spread leaf names are distinct" $
        let ns = leafNames (spread backends grindLenses)
         in report
              [ "repeated leaf name: " <> n | n <- nub (ns \\ nub ns) ]
    , -- __The grant against the checks it is derived from, through the
      -- runtime's own matcher.__ A grant and a check list are two statements of
      -- one fact, and the drift is silent in the direction that matters: an
      -- ungranted check is DENIED inside the run (exit 126, "denied by grant"),
      -- the gate never reads a real exit code, and the artifact still carries a
      -- gate section.
      --
      -- 'permitExec' over @T.unwords@ is exactly what @Agent.Run@ applies to an
      -- 'Agent.Op.Exec' leaf, so this fails on a broken argv rather than
      -- restating the derivation. A membership check on the glob set would pass
      -- on globs that match nothing.
      testCase "grindGrant permits every check as the runtime spells it" $
        report
          [ "denied by grindGrant: " <> tshow line
          | (_, cmd) <- grindChecks
          , let line = T.unwords (NE.toList cmd)
          , not (permitExec grindGrant line)
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
      -- it, and the grant case below passes either way — an ungranted command
      -- and an unrunnable one both fail, and only one of them is about the
      -- grant.
      testCase "every check runs inside the target project's dev shell" $
        report
          [ leafNameText n <> " runs bare: " <> tshow (T.unwords (NE.toList cmd))
          | (n, cmd) <- grindChecks
          , take 3 (NE.toList cmd) /= ["nix", "develop", "--command"]
          ]
    , -- The synthesis leaf's two, which are nobody's check. Without them its
      -- write fails inside the agent while it still returns the whole ranked
      -- report — so the run reports success with no file on disk, and only the
      -- filesystem can tell.
      testCase "grindGrant permits the report write" $
        report
          [ "denied by grindGrant: " <> tshow line
          | line <- ["date +%Y-%m-%d", "mkdir -p docs/audits"]
          , not (permitExec grindGrant line)
          ]
    , -- And it is not a blanket grant. Deriving from a list is only worth
      -- anything if the derivation still denies what is not on it.
      testCase "grindGrant denies what no check asked for" $
        report
          [ "grindGrant permits " <> tshow line
          | line <- ["rm -rf /", "git push origin master", "curl example.com"]
          , permitExec grindGrant line
          ]
    ]

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
  , ("qaOfCommit", qaAgent, qaOfCommit)
  , ("docsStrategyOfPlan", technicalDocsStrategist, docsStrategyOfPlan)
  , ("slopOfDocs", stopSlop, slopOfDocs)
  , -- The grind rescopings. Each is an upstream or local rubric plus an
    -- adjustment, so each owes the same prefix property: splice the base
    -- verbatim, then adjust. A rescoping that PARAPHRASED its base would look
    -- fine everywhere else in this suite.
    ("ponytailOfTree", ponytailAuditRubric, ponytailOfTree)
  , ("grindSynthesis", reviewSynthesis, grindSynthesis grindName)
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
                  | rule <- ["No primitive in a top-level signature", "RecordWildCards", "DataKinds"]
                  , not (says haskellOfHouse rule)
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
      -- Quantified over the @.md@ half only: the module haddocks it also reads
      -- are library sources, which an sdist carries because @hs-source-dirs@
      -- names them and at the same paths. A markdown file has no such carrier.
      testCase "extra-source-files carries every document this suite reads" $ do
        cabalFile <- TIO.readFile "incite-workflows.cabal"
        paths <- filter (".md" `isSuffixOf`) <$> rendererProseFiles
        let entries = extraSourceFiles cabalFile
        assertBool "no documents read" (not (null paths))
        report
          [ "read at run time but not packaged: " <> T.pack p
          | p <- paths
          , not (any (`covers` T.pack p) entries)
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

-- | The ten workflows "Main".workflows holds, rebuilt from library exports.
-- This suite cannot import "Main" — it is the executable, not a library module
-- — so this list is a hand-kept mirror of @workflows/Main.hs@'s @workflows@
-- binding, in the same order. A rename or reorder on either side is exactly
-- what 'docsInventoryTests' exists to catch.
mirrorWorkflows :: [Workflow]
mirrorWorkflows =
  [ planFeature
  , shipFeature
  , shipDocs
  , grindParadox
  , fessAudit
  , retro
  , reviewLite
  , reviewHeavy
  , reviewAudit
  , reviewDocs
  , promptLint
  ]

-- | The row-level primitive 'tableFirstColumn' and 'tableFirstTwoColumns' both
-- build on: every markdown table row whose first cell opens with a backticked
-- name, paired with that row's remaining cells (unparsed, unfiltered). Written
-- once so the convention for what counts as a row — split on @|@, strip, check
-- the backtick prefix, take the name up to the closing backtick — moves both
-- readers together. Before this was two independent copies, and reformatting
-- the doc convention meant finding and editing both in lockstep or watching
-- them drift.
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

-- | The backticked name in a markdown table row's __first__ cell, for every row
-- that has one. Later cells (a lens name, a bound flow value) are deliberately
-- not read: the first cell is what a table like "Exposed inventory" or "Review
-- tiers and leaf counts" enumerates, and a prose cell may cite other backticked
-- names in passing.
tableFirstColumn :: Text -> [Text]
tableFirstColumn = map fst . tableRows

-- | 'tableRows', plus the __raw text__ of the row's second cell — the shape of
-- "Review tiers and leaf counts"' @| Tier | Leaves | … |@ table.
--
-- Left as 'Text' rather than parsed to 'Int' here, on purpose: a cell that
-- fails to parse used to be silently filtered out by this reader before
-- @docsInventoryTests@ ever saw it (via a failed @reads@ pattern match), which
-- is exactly the defect that check exists to catch. Parsing — and reporting a
-- parse failure — is now the test's job, not this reader's.
tableFirstTwoColumns :: Text -> [(Text, Text)]
tableFirstTwoColumns body =
  [ (name, T.strip c2)
  | (name, c2 : _) <- tableRows body
  ]

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
      -- same ten workflows in different sequences would both read as the same
      -- set and this would stay green. Order is exactly what makes the claim on
      -- 'mirrorWorkflows' — "a rename or reorder on either side is exactly what
      -- this test exists to catch" — true.
      testCase "Exposed inventory names exactly the workflows this binary exposes, in order" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let named = tableFirstColumn (sectionBody "Exposed inventory" doc)
        assertBool "no workflow names read from the table" (not (null named))
        named @?= map wfName mirrorWorkflows
    , -- Every row this reads is either checked or turned into a named failure —
      -- never silently skipped. Two rows used to vanish before 'report' ever
      -- saw them: a row naming a workflow absent from 'mirrorWorkflows' (the old
      -- @Just wf <- [find …]@ pattern match failing inside the list
      -- comprehension, which drops that iteration rather than failing it), and a
      -- row whose count cell is not a bare 'Int' (dropped by
      -- 'tableFirstTwoColumns' itself, back when it parsed eagerly). Both are
      -- text at this point — 'tableFirstTwoColumns' no longer parses — so both
      -- get their own complaint below instead of disappearing.
      testCase "Review tiers and leaf counts matches worstCaseCost . toSkeleton . wfFlow" $ do
        doc <- TIO.readFile "docs/workflows.md"
        let counts = tableFirstTwoColumns (sectionBody "Review tiers and leaf counts" doc)
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
    ]

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

-- | 'workflowLeafPrompts' for a workflow that is __one leaf__, failing rather
-- than picking one when it is not. @prompt-lint@ is a single @ste@ refinement
-- under two scopes, so a second leaf appearing is a change to what it sends and
-- belongs in the failure, not silently outside the fence.
onlyLeafPrompt :: Workflow -> IO Text
onlyLeafPrompt wf = do
  sent <- workflowLeafPrompts wf
  case sent of
    [one] -> pure one
    _ ->
      assertFailure $
        T.unpack (wfName wf) <> " sends " <> show (length sent) <> " prompts, expected 1"

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
      testCase "plan-feature runs each leaf on the agent its module argues for" $
        scopedLeaves (wfFlow planFeature)
          @?= [ ("intrepid", "claude-agent")
              , ("skeptic", "codex")
              , ("contemplative", "opencode")
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
      testCase "no two explore stances share an agent" $
        let stances = [a | (n, a) <- scopedLeaves (wfFlow planFeature), n `elem` stanceNames]
         in do
              -- The reader proved before the law is quantified over it: a
              -- renamed stance would otherwise make distinctness a statement
              -- about the empty list.
              length stances @?= length stanceNames
              nub stances @?= stances
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
      testCase "fences against exactly review-lite's other lenses" $
        sort (map (leafNameText . fst) qaSiblings <> ["qa"])
          @?= sort (leafNames (wfFlow reviewLite))
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

-- | The facts file @grind-paradox@ prepends to every lens and splices into its
-- fixer's rule. Two properties, and no other instrument in this repository
-- reads either: the file is markdown, and 'promptText' is the only thing that
-- ever looks inside it.
factsFileTests :: TestTree
factsFileTests =
  testGroup
    "the grind facts file"
    [ -- The probe is what tells "the audit read nothing" from "the tree is
      -- clean", and it can only do that if the model reaches it before any
      -- path it is meant to check. First section, and nothing before it.
      testCase "the mandatory probe is the first section, and holds the refusal line" $ do
        map fst (sections (promptText paradoxFacts))
          @?= ["Probe first", "Project facts", "Repair disciplines"]
        assertBool "the refusal line is not inside the probe section" $
          T.isInfixOf "FACTS PATHS UNRESOLVED:" (sectionBody "Probe first" (promptText paradoxFacts))
    , -- One home per fact. The repair section restated the golden-reset
      -- ordering, the never-hand-edit rule, the interface-constructor ban and
      -- the test-filtering rule, all of which the facts above it already said —
      -- so a discipline could be revised in one section and left stale in the
      -- other, inside one file that a fixer reads whole.
      testCase "no discipline is stated in two sections" $
        let secs = sections (promptText paradoxFacts)
         in report
              [ "the facts file states " <> tshow needle <> " in " <> tshow (map fst hits)
              | needle <- factDisciplines
              , let hits = [s | s@(_, body) <- secs, T.isInfixOf needle body]
              , length hits /= 1
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
          | (path, txt) <- texts
          , before <- init (T.splitOn "agent-pm" txt)
          , not (any (`T.isSuffixOf` before) ["services.", "programs."])
          , let context = T.takeEnd 56 (T.unwords (T.words before))
          ]
    ]

backendTests :: TestTree
backendTests =
  testGroup
    "backends"
    [ testCase "has three backends" $
        length backends @?= 3
    , testCase "backend names" $
        map (leafNameText . fst) (NE.toList backends)
          @?= ["claude-agent", "codex", "opencode"]
    , -- 'NE.head' rather than 'head': the list is 'NonEmpty' so that
      -- @Incite.Review.spread@ can cycle it without a guard, and this case
      -- comes along for free — there is no empty case left to answer.
      testCase "claudeAgentBackend name matches first entry" $
        leafNameText (fst claudeAgentBackend)
          @?= leafNameText (fst (NE.head backends))
    ]
