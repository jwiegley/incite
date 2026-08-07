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
import Incite.Prompts (reviewCorrectness, steSkill)
import Incite.Review (Subject (..), lensesOf, promptLint, promptLintBrief, promptLintScope)

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
