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
import Agent.Flow (Flow, (>>>))
import Agent.Flow.Combinators (commit, exploreWith, hierarchical, humanGate, lensEdit, raceN, refineWith, reviewScales, steer, submitPR, verify, workLoop)
import Agent.Flow.Extent (coarsenTo)
import Agent.Grant (execGrant)
import Agent.Run (Workflow, passMain, workflow, workflowGReq, workflowReq)

main :: IO ()
main = passMain workflows

workflows :: [Workflow]
workflows =
  [ shipFeature
  , shipFeatureFull
  , haskellReview
  , explainCode
  , testWriter
  ]

-- | The analysis flagship: turn a feature request into a reviewed implementation
-- plan. Multi-agent explore → plan → lens edit → multi-scale review. Prompt-only,
-- so it runs against your agent without touching the filesystem — no worktree, no
-- git, no PR. 'shipFeatureFull' adds the world-acting half.
shipFeature :: Workflow
shipFeature =
  workflowReq "ship-feature" "Explore a feature request, plan it, edit through lenses, review at scale" $
    explorePlanEdit >>> review
  where
    -- Review the edited plan at three scales: whole, joined neighbours, per step.
    review =
      reviewScales
        T.lines
        (coarsenTo 40)
        (\unit -> "Review this plan step for correctness, completeness, and ordering. Note any missing prerequisite:\n\n" <> unit)

-- | Full ship-feature parity: explore → plan → edit → __implement__ → a work loop
-- (build\/commit\/work cadence) → human approval → open a PR. World-acting, so it
-- runs inside an isolated git worktree; its 'execGrant' permits only @git@,
-- @cabal@ and @gh@ (every other command is denied). Needs a real git repo + your
-- agent + credentials; the human gate asks before opening the PR.
shipFeatureFull :: Workflow
shipFeatureFull =
  workflowGReq
    "ship-feature-full"
    "Explore, plan, implement, build/commit in a loop, then (with approval) open a PR"
    (execGrant ["git*", "cabal*", "gh*"])
    $ explorePlanEdit
      >>> steer "Review the plan — add any guidance before implementation begins"
      >>> implement
      >>> workLoop 8 step
      >>> humanGate "Open a pull request for these changes?"
      >>> submitPR "Add --json flag" "Drafted by the ship-feature workflow."
  where
    -- TRUE parallel workers: 3 workers each implement the plan for real, in their
    -- OWN isolated git worktree (concurrently, no conflicts); then a merge prompt
    -- inspects all three worktrees, picks the best (or synthesises), and applies it
    -- here in place.
    implement =
      raceN
        3
        (\plan -> "Implement this plan fully in the current repository — edit the files directly, then summarise what you changed:\n\n" <> plan)
        "pick-best"
        ( \results ->
            T.unlines
              [ "Three workers each implemented the plan in their OWN git worktree (summaries + worktree paths below)."
              , "Inspect the three worktrees, pick the best implementation (or synthesise across them), and apply it in the CURRENT repository — edit the files directly. Summarise what you applied and why."
              , ""
              , results
              ]
        )
    -- The cadence, unrolled by ordinary Haskell (§0.2), mirroring the legacy
    -- ShipFeature loop: commit on a 5-beat, build on a 3-beat, review on a 2-beat,
    -- otherwise keep working. All world-acting; only git/cabal/gh are granted.
    step n
      | n `mod` 5 == 0 = commit ("ship-feature: checkpoint " <> T.pack (show n))
      | n `mod` 3 == 0 = verify [("build", ["cabal", "build"])]
      | n `mod` 2 == 0 =
          refineWith "review" (\sofar ->
            "Review the changes you have made so far for correctness and style. List anything to fix:\n\n" <> sofar) id
      | otherwise =
          refineWith "work" (\sofar ->
            "Continue implementing the plan and fix any build errors. Summarise the delta:\n\n" <> sofar) id

-- The shared analysis prefix of both ship-feature workflows: three-stance explore,
-- plan, then lens edits — a reusable 'Flow' value.
explorePlanEdit :: Flow Text Text
explorePlanEdit = explore >>> plan >>> edit
  where
    explore =
      exploreWith
        [ ("intrepid", \req -> "You are bold and ambitious. Sketch the most direct way to ship this feature and what it unlocks:\n\n" <> req)
        , ("skeptic", \req -> "You are a skeptic. Enumerate the risks, edge cases, and failure modes of this feature:\n\n" <> req)
        , ("contemplative", \req -> "You are thoughtful. Weigh design alternatives and long-term consequences:\n\n" <> req)
        ]
        (hierarchical ["skeptic", "contemplative", "intrepid"])
    plan =
      refineWith "plan" (\findings ->
        "From these exploration findings, write a concrete implementation plan as an ordered list — ONE step per line, each a self-contained unit of work:\n\n" <> findings) id
    edit =
      lensEdit
        [ ("scope", \p -> "Tighten SCOPE: cut any step not essential to shipping. Keep one step per line:\n\n" <> p)
        , ("risk", \p -> "Annotate each step with its RISK and a one-line mitigation. Keep one step per line:\n\n" <> p)
        , ("sequencing", \p -> "Reorder the steps into correct dependency SEQUENCE. Keep one step per line:\n\n" <> p)
        ]

-- | Review a Haskell function for bugs\/style, then rewrite it fixing the issues.
haskellReview :: Workflow
haskellReview =
  workflow "haskell-review" "Review a Haskell function, then rewrite it fixing the issues" sampleCode $
    refineWith "reviewer" (\code -> "Review this Haskell for bugs and style, terse bullet points:\n\n" <> code) id
      >>> refineWith "reviser" (\review -> "Given this review, rewrite the function fixing the issues. Output ONLY the corrected Haskell code:\n\n" <> review) id

-- | Explain a piece of code in plain English for a newcomer.
explainCode :: Workflow
explainCode =
  workflow "explain" "Explain a piece of code in plain English" sampleCode $
    refineWith "explainer" (\code -> "Explain what this code does in plain English, for a newcomer. Be concise:\n\n" <> code) id

-- | Draft tests, critique them, then finalize — a three-stage chain.
testWriter :: Workflow
testWriter =
  workflow "test-writer" "Draft hspec tests, critique them, then finalize" sampleCode $
    refineWith "draft" (\code -> "Write hspec tests covering the edge cases of this function:\n\n" <> code) id
      >>> refineWith "critic" (\tests -> "Critique these tests: what cases are missing or wrong? Terse bullet points:\n\n" <> tests) id
      >>> refineWith "finalize" (\critique -> "Apply this critique and output ONLY the final, complete hspec test module:\n\n" <> critique) id

-- | The artifact fed into the code workflows above.
sampleCode :: Text
sampleCode =
  T.unlines
    [ "average :: [Int] -> Int"
    , "average xs = sum xs `div` length xs"
    ]
