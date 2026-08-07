module Main (main) where

import Data.List (nub, (\\))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Test.Tasty
import Test.Tasty.HUnit

import Agent.Op (LeafName, leafNameText)
import Agent.Prompt (Prompt, brief, promptText)
import Agent.Run (Workflow (..))
import Incite.Backend (backends, claudeAgentBackend)
import Incite.Feature (asReviewSubject, continueMarker, decideContinue)
import Incite.Prompts
  ( codeReview
  , codeReviewerSecurity
  , docsCompleteness
  , docsStructure
  , haskellReviewer
  , perfReviewer
  , ponytailAuditRubric
  , ponytailReviewRubric
  , reviewCorrectness
  , reviewTests
  , steSkill
  )
import Incite.Review
  ( Subject (..)
  , architectureOfChange
  , docsAccuracy
  , lensesOf
  , ponytailOfDocs
  , promptLint
  , promptLintBrief
  , promptLintScope
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "incite-workflows"
    [ decideContinueTests
    , continueMarkerTests
    , asReviewSubjectTests
    , lensSetViolationsTests
    , lensesOfTests
    , promptLintTests
    , backendTests
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
    ]

continueMarkerTests :: TestTree
continueMarkerTests =
  testGroup
    "continueMarker"
    [ testCase "is WORK REMAINS" $
        continueMarker @?= "WORK REMAINS"
    ]

asReviewSubjectTests :: TestTree
asReviewSubjectTests =
  testGroup
    "asReviewSubject"
    [ testCase "prepends review instructions" $
        assertBool "starts with review instruction" $
          T.isPrefixOf "Review the change" (asReviewSubject "summary")
    , testCase "includes the summary verbatim" $
        assertBool "ends with the summary" $
          T.isSuffixOf "summary" (asReviewSubject "summary")
    , testCase "mentions git diff" $
        assertBool "contains git diff instruction" $
          T.isInfixOf "git diff" (asReviewSubject "summary")
    ]

-- | The three laws of 'lensesOf', written as a refutable check: one 'Text' per
-- law the set breaks, and @[]@ for a set that holds all three.
--
-- Separate from the assertions so the laws can be shown to FAIL. Quantified
-- over 'Subject' they pass by construction, and a law that never failed is a
-- law nobody knows is wired to anything.
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

-- | A stand-in body: these fixtures exercise the NAMES, and every law is a
-- statement about names alone.
anyPrompt :: Prompt
anyPrompt = reviewCorrectness

emptyLenses, duplicateLenses, ponytaillessLenses, wellFormedLenses :: [(LeafName, Prompt)]
emptyLenses = []
duplicateLenses = [("correctness", anyPrompt), ("ponytail", anyPrompt), ("correctness", anyPrompt)]
ponytaillessLenses = [("correctness", anyPrompt), ("security", anyPrompt)]
wellFormedLenses = [("correctness", anyPrompt), ("ponytail", anyPrompt)]

lensSetViolationsTests :: TestTree
lensSetViolationsTests =
  testGroup
    "lensSetViolations"
    [ testGroup
        "non-empty"
        [ testCase "empty set is reported" $
            assertBool "expected an emptiness violation" $
              "empty lens set" `elem` lensSetViolations emptyLenses
        , testCase "report stops once the set is non-empty" $
            assertBool "emptiness still reported" $
              "empty lens set" `notElem` lensSetViolations wellFormedLenses
        ]
    , testGroup
        "pairwise distinct"
        [ testCase "a repeated name is reported" $
            assertBool "expected a duplicate violation" $
              any (T.isPrefixOf "duplicate lens names") (lensSetViolations duplicateLenses)
        , testCase "report stops once the repeat is removed" $
            assertBool "duplicates still reported" $
              not (any (T.isPrefixOf "duplicate lens names") (lensSetViolations wellFormedLenses))
        ]
    , testGroup
        "ponytail present"
        [ testCase "a set without ponytail is reported" $
            assertBool "expected a missing-ponytail violation" $
              "no ponytail lens" `elem` lensSetViolations ponytaillessLenses
        , testCase "report stops once ponytail is added" $
            assertBool "missing ponytail still reported" $
              "no ponytail lens" `notElem` lensSetViolations wellFormedLenses
        ]
    , testCase "a well-formed set has no violations" $
        lensSetViolations wellFormedLenses @?= []
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
    [ testCase "OfDiff has 7 lenses" $
        length (lensesOf OfDiff) @?= 7
    , testCase "OfChange has 8 lenses" $
        length (lensesOf OfChange) @?= 8
    , testCase "OfDiff lens names" $
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
    , testCase "OfDocs has 4 lenses" $
        length (lensesOf OfDocs) @?= 4
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
    , testCase "no duplicate names in OfDiff" $
        noDuplicates (map (leafNameText . fst) (lensesOf OfDiff))
    , testCase "no duplicate names in OfChange" $
        noDuplicates (map (leafNameText . fst) (lensesOf OfChange))
    , testCase "OfChange is OfDiff plus architecture" $
        map (leafNameText . fst) (lensesOf OfChange)
          @?= map (leafNameText . fst) (lensesOf OfDiff) <> ["architecture"]
    , -- Over the ENUMERATION, not a hardcoded list: a new constructor is
      -- covered on arrival rather than when someone remembers to add it here.
      testCase "every subject holds all three laws" $
        mapM_
          ( \s ->
              assertBool
                (show s <> " violates: " <> show (lensSetViolations (lensesOf s)))
                (null (lensSetViolations (lensesOf s)))
          )
          [minBound .. maxBound :: Subject]
    , -- The guard on the assertion above. Without it a law quantified over an
      -- enumeration that silently grew stays green over the subjects it used to
      -- cover; this line forces the edit that proves the enumeration is live.
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

-- | The brief @prompt-lint@ ships today. One binding, so parameterising
-- 'promptLintBrief' moves this line and leaves the recorded bytes alone.
shippedPromptLintBrief :: Prompt
shippedPromptLintBrief = promptLintBrief promptLintScope

-- | What @prompt-lint@\'s single leaf actually sends: the brief, a blank line,
-- then the artifact — which on a default run is the workflow\'s own input
-- description.
promptLintLeafText :: Text
promptLintLeafText =
  promptText (brief shippedPromptLintBrief (fromMaybe "" (wfInput promptLint)))

promptLintTests :: TestTree
promptLintTests =
  testGroup
    "promptLint"
    [ testCase "the leaf names every directory it is pointed at" $
        mapM_
          ( \d ->
              assertBool
                (T.unpack d <> " is not in the leaf text")
                (T.isInfixOf d promptLintLeafText)
          )
          ["prompts/", "commands/", "agents/", "skills/"]
    , -- A FENCE, not a smoke test. Nothing else in this repository can see the
      -- text this workflow sends, so an edit to it is invisible everywhere
      -- else. Total equality, so a reordering, a separator change or one
      -- reworded sentence all fail it — a suffix or infix check would not.
      --
      -- The upstream half is NAMED rather than copied. Recording 'steSkill'\'s
      -- ~19 KB here would mirror a flake input into git (which
      -- @prompts\/upstream@ is gitignored to avoid) and go red on
      -- @nix flake update@ — a fence that cries wolf gets regenerated, which is
      -- the one thing it must never be. Every byte this repository owns is in
      -- the golden file, verbatim.
      testCase "the brief is steSkill plus exactly the recorded local text" $ do
        recorded <- TIO.readFile "test/golden/prompt-lint-brief.txt"
        promptText shippedPromptLintBrief @?= promptText steSkill <> recorded
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

noDuplicates :: [Text] -> Assertion
noDuplicates xs =
  let dups = xs \\ nub xs
   in assertBool ("duplicate names: " <> show dups) (null dups)
