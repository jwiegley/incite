{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Isaac's local @agent-functor@ workflows.
--
-- This package consumes the @agent-functor@ library and defines its own
-- workflows as typed 'Flow' values. Add a workflow by writing another 'Workflow'
-- and listing it in 'workflows' — the CLI (@list@\/@plan@\/@cost@\/@run@) comes
-- for free from 'passMain'. Nothing here forks agent-functor; it's a downstream
-- consumer of the library.
--
-- __Prompt bodies live on disk__, not in string literals: a @[promptFile|…|]@ is
-- checked when this module compiles and read when the workflow runs, so editing
-- the markdown and re-running picks the change up with no rebuild. Paths are
-- relative to the repo root — which is both the cabal package root (compile
-- time) and where you stand to run the binary (run time). That includes the
-- @agents\/@ and @skills\/@ prompts this repo already ships to @~\/.claude@:
-- 'codeReview' and 'fixAll' below are the same files agent-pm renders, reused
-- verbatim as workflow briefs.
module Main (main) where

import Data.Text (Text)
import qualified Data.Text as T
import Agent.Flow (Flow, Mode (Plan), withMode, (>>>))
import Agent.Flow.Combinators (commit, exploreWith, hierarchical, humanGate, lensEdit, raceN, refineWith, reviewScales, steer, submitPR, verify, workLoop)
import Agent.Flow.Extent (coarsenTo)
import Agent.Grant (execGrant)
import Agent.Prompt (Prompt, brief, i, promptFile)
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

-- Prompt bodies -----------------------------------------------------------------
--
-- Bound at the top level, so each file is read once per process. Written against
-- the repo root: `prompts/` holds briefs authored for these workflows, while
-- `agents/` and `skills/` are the prompts this repo already ships to ~/.claude —
-- reused here rather than paraphrased, so there is exactly one copy of each.

intrepid, skeptic, contemplative :: Prompt
intrepid = [promptFile|prompts/explore/intrepid.md|]
skeptic = [promptFile|prompts/explore/skeptic.md|]
contemplative = [promptFile|prompts/explore/contemplative.md|]

planBrief, pickBest, reviewStep :: Prompt
planBrief = [promptFile|prompts/plan.md|]
pickBest = [promptFile|prompts/pick-best.md|]
reviewStep = [promptFile|prompts/review-step.md|]

-- | The reviewer agent this repo installs as @~\/.claude\/agents\/code-review.md@,
-- used directly as a workflow brief.
--
-- __This is a big prompt__ (~18 KB). Every leaf that uses it sends the whole
-- thing, so a workflow reading it is materially more expensive per turn than one
-- with a one-line brief. That is the trade being made deliberately: the reviewer
-- gets the repo's real, maintained review doctrine instead of a paraphrase of it,
-- and there is exactly one copy to keep current.
codeReview :: Prompt
codeReview = [promptFile|agents/code-review.md|]

-- | The @fix-all@ skill (@~\/.claude\/skills\/fix-all.md@) — \"fix every issue, no
-- exceptions\" — driving the work beat of the implementation loop. ~4 KB per
-- leaf that uses it.
fixAll :: Prompt
fixAll = [promptFile|skills/fix-all.md|]

-- Workflows ----------------------------------------------------------------------

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
    review = reviewScales T.lines (coarsenTo 40) (brief reviewStep)

-- | Full ship-feature parity: explore → plan → edit → __implement__ → a work loop
-- (build\/commit\/work cadence) → human approval → open a PR. World-acting, so it
-- runs inside an isolated git worktree; its 'execGrant' permits only @git@,
-- @cabal@ and @gh@ (every other command is denied). Needs a real git repo + your
-- agent + credentials; the human gate asks before opening the PR.
shipFeatureFull :: Workflow
shipFeatureFull =
  workflowGReq
    "ship-feature-full"
    "Explore, plan, implement, then loop build/commit with the code-review agent and fix-all skill; human gate, then a PR"
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
        (brief "Implement this plan fully in the current repository — edit the files directly, then summarise what you changed:")
        "pick-best"
        (brief pickBest)
    -- The cadence, unrolled by ordinary Haskell (§0.2): commit on a 5-beat,
    -- build on a 3-beat, review on a 2-beat, otherwise keep working.
    -- All world-acting; only git/cabal/gh are granted.
    --
    -- Cost note: over 8 beats this is 3 review leaves (~18 KB each) and 2 work
    -- leaves (~4 KB each) of brief alone, before the threaded artifact.
    step n
      | n `mod` 5 == 0 = commit [i|ship-feature: checkpoint #{n}|]
      | n `mod` 3 == 0 = verify [("build", ["cabal", "build"])]
      | n `mod` 2 == 0 = refineWith "review" (brief codeReview) id
      | otherwise = refineWith "work" (brief fixAll) id

-- The shared analysis prefix of both ship-feature workflows: three-stance explore,
-- plan, then lens edits — a reusable 'Flow' value.
explorePlanEdit :: Flow Text Text
explorePlanEdit = explore >>> plan >>> edit
  where
    -- Analysis-only: the three stances READ the codebase, they never edit it.
    -- 'withMode Plan' runs every leaf here in the backend's read-only/plan mode,
    -- so the constraint is enforced at the session level rather than trusted to
    -- the prompt. Downstream 'plan'\/'edit' stay in the default Edit mode.
    explore =
      withMode Plan $
        exploreWith
          [ ("intrepid", brief intrepid)
          , ("skeptic", brief skeptic)
          , ("contemplative", brief contemplative)
          ]
          (hierarchical ["skeptic", "contemplative", "intrepid"])
    plan = refineWith "plan" (brief planBrief) id
    -- One-line lenses stay literal: a file would be indirection for its own sake.
    edit =
      lensEdit
        [ ("scope", brief "Tighten SCOPE: cut any step not essential to shipping. Keep one step per line:")
        , ("risk", brief "Annotate each step with its RISK and a one-line mitigation. Keep one step per line:")
        , ("sequencing", brief "Reorder the steps into correct dependency SEQUENCE. Keep one step per line:")
        ]

-- | Review a Haskell function for bugs\/style, then rewrite it fixing the issues.
-- The reviewer runs the repo's own @code-review@ agent prompt.
haskellReview :: Workflow
haskellReview =
  workflow "haskell-review" "Review a Haskell function with the code-review agent prompt, then rewrite it fixing the issues" sampleCode $
    refineWith "reviewer" (brief codeReview) id
      >>> refineWith "reviser" (brief "Given this review, rewrite the function fixing the issues. Output ONLY the corrected Haskell code:") id

-- | Explain a piece of code in plain English for a newcomer.
explainCode :: Workflow
explainCode =
  workflow "explain" "Explain a piece of code in plain English" sampleCode $
    refineWith "explainer" (brief "Explain what this code does in plain English, for a newcomer. Be concise:") id

-- | Draft tests, critique them, then finalize — a three-stage chain.
testWriter :: Workflow
testWriter =
  workflow "test-writer" "Draft hspec tests, critique them, then finalize" sampleCode $
    refineWith "draft" (brief "Write hspec tests covering the edge cases of this function:") id
      >>> refineWith "critic" (brief "Critique these tests: what cases are missing or wrong? Terse bullet points:") id
      >>> refineWith "finalize" (brief "Apply this critique and output ONLY the final, complete hspec test module:") id

-- | The artifact fed into the code workflows above.
sampleCode :: Text
sampleCode =
  T.unlines
    [ "average :: [Int] -> Int"
    , "average xs = sum xs `div` length xs"
    ]
