module Main (main) where

import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, nub, sort, (\\))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (listDirectory)
import Test.Tasty
import Test.Tasty.HUnit

import Agent.Cost (Cost (..), renderCost, worstCaseCost)
import Agent.Flow (Flow)
import Agent.Flow.Skeleton (toSkeleton)
import Agent.Interpret (LeafHandlers (..), interpret, leafRunner)
import Agent.Op (LeafName, leafNameText)
import Agent.Prompt (Prompt, prompt, promptText)
import Agent.Run (Workflow (..))
import Incite.Backend (backends, claudeAgentBackend)
import Incite.Feature
  ( Orientation (..)
  , asRetroSubject
  , asDocsSubject
  , asReviewSubject
  , continueMarker
  , decideContinue
  , document
  , orient
  , planFeature
  , preambleOf
  , preambleViolations
  , shipDocs
  , shipFeature
  )
import Incite.Prompts
  ( codeReview
  , codeReviewerSecurity
  , docsCompleteness
  , docsStructure
  , fess
  , haskellReviewer
  , perfReviewer
  , ponytailAuditRubric
  , ponytailReviewRubric
  , reviewArchitecture
  , reviewCorrectness
  , reviewTests
  , steSkill
  )
import Incite.Review
  ( Subject (..)
  , architectureOfChange
  , docsAccuracy
  , fessAudit
  , lensSetViolations
  , lensesOf
  , ponytailOfDocs
  , promptLint
  , promptLintBrief
  , promptLintScope
  , retro
  , reviewAudit
  , reviewDocs
  , reviewHeavy
  , reviewLite
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "incite-workflows"
    [ decideContinueTests
    , continueMarkerTests
    , reframingTests
    , preambleViolationsTests
    , orientTests
    , documentTests
    , lensSetViolationsTests
    , lensesOfTests
    , reorientationTests
    , promptLintTests
    , packagingTests
    , backendTests
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
    , ("haskell", haskellReviewer)
    , ("ponytail", ponytailReviewRubric)
    , ("doctrine", codeReview)
    ]
  OfChange ->
    [ ("correctness", reviewCorrectness)
    , ("security", codeReviewerSecurity)
    , ("tests", reviewTests)
    , ("performance", perfReviewer)
    , ("haskell", haskellReviewer)
    , ("ponytail", ponytailAuditRubric)
    , ("doctrine", codeReview)
    , ("architecture", architectureOfChange)
    ]
  OfDocs ->
    [ ("accuracy", docsAccuracy)
    , ("completeness", docsCompleteness)
    , ("structure", docsStructure)
    , ("ponytail", ponytailOfDocs)
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
      testCase "each subject's ponytail lens is its own rubric" $
        let rubrics =
              [ promptText body
              | s <- [minBound .. maxBound :: Subject]
              , (name, body) <- lensesOf s
              , leafNameText name == "ponytail"
              ]
         in (length rubrics, length (nub rubrics)) @?= (3, 3)
    , -- The guard on the hardcoded name lists above, NOT on the quantified law.
      -- The law needs no guard: @[minBound .. maxBound]@ picks up a constructor
      -- by itself, which is how @OfDocs@ arrived already covered by it. The name
      -- lists are written one per constructor and go stale in silence, and so
      -- does the rubric count on the case above. This line is what forces the
      -- edit that notices a subject has appeared.
      testCase "Subject enumerates 3 constructors" $
        length ([minBound .. maxBound] :: [Subject]) @?= 3
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
      -- nothing to enumerate. The two docs deltas void part of their base, and
      -- a part that is neither repointed nor voided is a section still pointed
      -- at code.
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
goldensRead = promptLintGolden : [path | (_, _, path) <- reframings]

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

backendTests :: TestTree
backendTests =
  testGroup
    "backends"
    [ testCase "has three backends" $
        length backends @?= 3
    , testCase "backend names" $
        map (leafNameText . fst) backends
          @?= ["claude-agent", "codex", "opencode"]
    , testCase "claudeAgentBackend name matches first entry" $
        leafNameText (fst claudeAgentBackend)
          @?= leafNameText (fst (head backends))
    ]
