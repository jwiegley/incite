{-# LANGUAGE OverloadedStrings #-}

-- | Isaac's local @agent-functor@ workflows.
--
-- This package consumes the @agent-functor@ library and defines its own
-- workflows as typed 'Flow' values. Add a workflow by writing another 'Workflow'
-- and listing it in 'workflows' — the CLI (@list@\/@plan@\/@cost@\/@run@) comes
-- for free from 'passMain'. Nothing here forks agent-functor; it's a downstream
-- consumer of the library.
module Main (main) where

import Data.Text (Text)
import qualified Data.Text as T
import Agent.Flow ((>>>))
import Agent.Flow.Combinators (exploreWith, hierarchical, lensEdit, refineWith, reviewScales)
import Agent.Flow.Extent (coarsenTo)
import Agent.Run (Workflow, passMain, workflow)

main :: IO ()
main = passMain workflows

workflows :: [Workflow]
workflows =
  [ shipFeature
  , haskellReview
  , explainCode
  , testWriter
  ]

-- | The flagship: turn a feature request into a reviewed implementation plan.
-- Multi-agent explore → plan → lens edit → multi-scale review — the analysis half
-- of ship-feature, composed from the agent-functor combinators (prompt-only; the
-- world-acting work loop of implement/verify/commit/PR is a later stage).
shipFeature :: Workflow
shipFeature =
  workflow "ship-feature" "Explore a feature request, plan it, edit through lenses, review at scale" featureRequest $
    explore
      >>> plan
      >>> edit
      >>> review
  where
    -- Three agents explore the request from different stances; findings are
    -- ordered by priority (skeptic's risks first) and unioned.
    explore =
      exploreWith
        [ ("intrepid", \req -> "You are bold and ambitious. Sketch the most direct way to ship this feature and what it unlocks:\n\n" <> req)
        , ("skeptic", \req -> "You are a skeptic. Enumerate the risks, edge cases, and failure modes of this feature:\n\n" <> req)
        , ("contemplative", \req -> "You are thoughtful. Weigh design alternatives and long-term consequences:\n\n" <> req)
        ]
        (hierarchical ["skeptic", "contemplative", "intrepid"])

    -- Turn the exploration into a concrete, ordered plan (one unit per line).
    plan =
      refineWith "plan" $ \findings ->
        "From these exploration findings, write a concrete implementation plan as an ordered list — ONE step per line, each a self-contained unit of work:\n\n" <> findings

    -- Refine the plan through lenses, in dependency order.
    edit =
      lensEdit
        [ ("scope", \p -> "Tighten SCOPE: cut any step not essential to shipping. Keep one step per line:\n\n" <> p)
        , ("risk", \p -> "Annotate each step with its RISK and a one-line mitigation. Keep one step per line:\n\n" <> p)
        , ("sequencing", \p -> "Reorder the steps into correct dependency SEQUENCE. Keep one step per line:\n\n" <> p)
        ]

    -- Review the plan at three scales: whole, joined neighbours, and per step.
    review =
      reviewScales
        T.lines
        (coarsenTo 40)
        (\unit -> "Review this plan step for correctness, completeness, and ordering. Note any missing prerequisite:\n\n" <> unit)

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

-- | The artifact fed into the code workflows above.
sampleCode :: Text
sampleCode =
  T.unlines
    [ "average :: [Int] -> Int"
    , "average xs = sum xs `div` length xs"
    ]

-- | The feature request fed into 'shipFeature'.
featureRequest :: Text
featureRequest =
  T.unlines
    [ "Add a `--json` flag to the CLI so every command can emit machine-readable"
    , "output instead of the human-formatted text, without breaking existing usage."
    ]
