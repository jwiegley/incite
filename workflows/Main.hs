{-# LANGUAGE OverloadedStrings #-}

-- | Isaac's local @pass@ workflows.
--
-- This package consumes the @pass@ library (agent-functor) and defines its own
-- workflows as typed 'Flow' values. Add a workflow by writing another 'Workflow'
-- and listing it in 'workflows' — the CLI (@list@\/@plan@\/@cost@\/@run@) comes
-- for free from 'passMain'. Nothing here forks agent-functor; it's a downstream
-- consumer of the library.
module Main (main) where

import Data.Text (Text)
import qualified Data.Text as T
import Pass.Flow ((>>>))
import Pass.Flow.Combinators (refineWith)
import Pass.Run (Workflow, passMain, workflow)

main :: IO ()
main = passMain workflows

workflows :: [Workflow]
workflows =
  [ haskellReview
  , explainCode
  , testWriter
  ]

-- | Review a Haskell function for bugs\/style, then rewrite it fixing the issues.
haskellReview :: Workflow
haskellReview =
  workflow "haskell-review" "Review a Haskell function, then rewrite it fixing the issues" sampleCode $
    refineWith "reviewer" (\code -> "Review this Haskell for bugs and style, terse bullet points:\n\n" <> code)
      >>> refineWith "reviser" (\review -> "Given this review, rewrite the function fixing the issues. Output ONLY the corrected Haskell code:\n\n" <> review)

-- | Explain a piece of code in plain English for a newcomer.
explainCode :: Workflow
explainCode =
  workflow "explain" "Explain a piece of code in plain English" sampleCode $
    refineWith "explainer" (\code -> "Explain what this code does in plain English, for a newcomer. Be concise:\n\n" <> code)

-- | Draft tests, critique them, then finalize — a three-stage chain.
testWriter :: Workflow
testWriter =
  workflow "test-writer" "Draft hspec tests, critique them, then finalize" sampleCode $
    refineWith "draft" (\code -> "Write hspec tests covering the edge cases of this function:\n\n" <> code)
      >>> refineWith "critic" (\tests -> "Critique these tests: what cases are missing or wrong? Terse bullet points:\n\n" <> tests)
      >>> refineWith "finalize" (\critique -> "Apply this critique and output ONLY the final, complete hspec test module:\n\n" <> critique)

-- | The artifact fed into each workflow above.
sampleCode :: Text
sampleCode =
  T.unlines
    [ "average :: [Int] -> Int"
    , "average xs = sum xs `div` length xs"
    ]
