{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | The ship-feature workflow, authored in the pass eDSL. This is CONTENT you
-- own and iterate on: the composition (below), the prompt bodies (@prompts/@) and
-- the base packs (@packs/@). The framework (@pass@) is a library dependency.
--
-- The work loop is unrolled by ordinary Haskell — the cadence is your code.
module Incite.ShipFeature
  ( shipFeatureE
  , checkEnv
  ) where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedDir)
import Data.Function ((&))
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Pass.Check (CheckEnv (..))
import Pass.Dsl
import Pass.IR hiding (Ref)
import Pass.Skill (countTokens)
import Pass.Violation (Violation)
import System.FilePath (splitDirectories, takeBaseName)

-- ---------------------------------------------------------------------------
-- The workflow. 'workflow' returns Either so a build-time invariant break
-- (duplicate name, phantom mismatch) surfaces as a Left rather than a bottom.
-- ---------------------------------------------------------------------------

shipFeatureE :: Either [Violation] Workflow
shipFeatureE = workflow "ship-feature" (defaults opus [tribalProject, tribalTone]) $ \srcs -> do
  request <- input "request" :: Builder (Ref 'TyText)
  let srcDiff = workingDiff srcs
      srcConv = parentContext srcs
      adv = head_ & withLens adversary
      pony = head_ & withLens ponytail
      sec = head_ & withLens security & withGrant readNet & readsFrom "deps" (manifest srcDiff)
      advHaiku = adv & withModel haiku
      ponyHaiku = pony & withModel haiku

  findings <- explore "findings"
    [ ("intrepid", head_ & withAgent intrepid)
    , ("skeptic", head_ & withAgent skeptic)
    , ("contemplative", head_ & withAgent contemplative)
    ]
    unionWithConflicts request

  draft <- plan "draft" pert opus request findings

  plan' <- runPass
             ( edit "edited"
                 [ ("scope", head_ & withLens scope)
                 , ("risk", head_ & withLens risk & withModel opus)
                 , ("sequencing", head_ & withLens sequencing)
                 , ("feasibility", head_ & withLens feasibility & withGrant readNet)
                 ]
                 architect (Just human)
               <> normalizeWith "plan" haiku
             ) draft

  units <- partition "units" logicalUnit 40 Coarsen srcDiff

  reviewA <- reduce @'TyReport "review"
    -- Head priority for the per-scale verdict: the honesty audit (fess) is
    -- authoritative, then security, then the adversarial reviewers, then the
    -- structural/sentiment lenses. (The reducer runs per scale and keys on head
    -- names; names absent from a given scale are simply skipped there.) The
    -- priority only changes the outcome when the heads DISAGREE; the deterministic
    -- mock approves unanimously, so under `run-mock` this reduces to a plain
    -- approve — the ordering matters against a real, disagreeing model.
    -- CONTRIBUTOR heads only: a gate (sentiment) never reaches the reducer, so
    -- naming one here is a silent no-op — rule 10 rejects it.
    (hierarchical ["fess", "security", "adversary", "ponytail", "architecture"])
    ( fanoutScales
        [ scale "whole" (onWhole srcDiff)
            [ ("fess", head_ & withLens fess & withAgent skeptic
                             & readsFrom "conversation" (full srcConv)
                             & readsFrom "code" (whole srcDiff))
            , ("adversary", adv)
            , ("ponytail", pony)
            , ("security", sec)
            , ("architecture", head_ & withLens architecture & readsFrom "code" (moduleGraph srcDiff))
            , ("sentiment", head_ & withLens sentiment
                                  & readsFrom "conversation" (full srcConv)
                                  & gate Escalate)
            ]
        , scale "joined" (onWindow 2 1 units)
            [ ("adversary", adv), ("ponytail", pony), ("security", sec) ]
        , scale "unit" (onEach units)
            [ ("adversary", advHaiku), ("ponytail", ponyHaiku) ]
        ]
        & withSources
            [ ("conversation", rawRef srcConv)
            , ("diff", rawRef srcDiff)
            , ("units", rawRef units)
            ]
        & withQuorum 4 ["security"]
        & withBound 40
    )

  -- The work loop, unrolled by ordinary Haskell: the cadence is code.
  seed <- implement plan'
  let step :: Int -> Pass 'TyCodebase
      step n | n `mod` 5 == 0 = commit
             | n `mod` 3 == 0 = verify [fmt, build, gitHealth]
             | n `mod` 2 == 0 = review reviewA
             | otherwise      = work
  built <- runPass (foldMap step [1 .. 8 :: Int]) seed

  submitPRs "prs" built

-- ---------------------------------------------------------------------------
-- The check environment, built from the embedded prompt/pack content + the
-- registry. `pass check` runs `Pass.Check.check checkEnv shipFeature`.
-- ---------------------------------------------------------------------------

promptFiles :: [(FilePath, ByteString)]
promptFiles = $(embedDir "prompts")

packFiles :: [(FilePath, ByteString)]
packFiles = $(embedDir "packs")

-- | The check environment. Everything the checker validates against — the
-- lens/agent/model/backend/reducer/… vocabulary and backend feature sets — is
-- derived from the framework registry ('baseCheckEnv'), so it cannot drift from
-- what the interpreter actually ships. This workflow supplies only what is
-- genuinely its own: the prompt bodies and the skill-pack token counts.
checkEnv :: CheckEnv
checkEnv = baseCheckEnv
  { ceTemplates = Map.fromList [ (TemplateRef (T.pack p), TE.decodeUtf8 bs) | (p, bs) <- promptFiles ]
  , cePacks = packTokens
  }
  where
    packTokens = Map.fromListWith Map.union
      [ (T.pack pack, Map.singleton (T.pack (takeBaseName path)) (countTokens (TE.decodeUtf8 bs)))
      | (path, bs) <- packFiles
      , pack <- take 1 (splitDirectories path)
      ]
