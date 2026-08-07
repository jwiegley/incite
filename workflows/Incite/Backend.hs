{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Which model runs a leaf, and how a leaf gets scoped to one.
--
-- Small on purpose, and shared: the feature pipeline pins its planner to a
-- model, the review tiers fan every lens across all three backends, and both
-- need the same vocabulary. Keeping it here is what stops
-- "Incite.Feature" and "Incite.Review" from importing each other.
module Incite.Backend
  ( fable5
  , backends
  , claudeAgentBackend
  , reviewer
  ) where

import Data.Text (Text)
import Agent.Backend
  ( BackendTag (ClaudeAgent)
  , Model
  , ModelSpec (Named)
  , claudeAgent
  , claudeModel
  , codex
  , defaultModel
  , opencode
  , withBackend
  )
import Agent.Flow (Flow, Mode (Plan), withMode)
import Agent.Flow.Combinators (refineWith)
import Agent.Op (LeafName)
import Agent.Prompt (Prompt, brief)

-- | Fable 5 by match key: resolved against what this install's
-- @claude-agent-acp@ advertises ('Agent.Op.matchModelKey'); preflight refuses
-- loudly rather than guessing if the key is ambiguous.
fable5 :: Model 'ClaudeAgent 'Named
fable5 = claudeModel "fable"

-- | Every backend this repo drives, as __erased scope functions__. The
-- @Backend b@ \/ @Model b m@ pair is type-indexed, so the tokens cannot sit in a
-- list together; applied, each is an ordinary
-- @'Flow' 'Text' 'Text' -> 'Flow' 'Text' 'Text'@ and can.
--
-- That erasure is what makes a lens × backend cross-product expressible as a
-- list comprehension rather than three hand-written copies.
backends :: [(LeafName, Flow Text Text -> Flow Text Text)]
backends =
  [ claudeAgentBackend
  , ("codex", withBackend codex defaultModel)
  , ("opencode", withBackend opencode defaultModel)
  ]

-- | The claude-agent entry of 'backends', named so a flow can scope to just
-- this one without indexing into that list. 'backends' is built from it, so tag
-- and scope cannot drift between the fan-out and the single-backend use.
claudeAgentBackend :: (LeafName, Flow Text Text -> Flow Text Text)
claudeAgentBackend = ("claude-agent", withBackend claudeAgent fable5)

-- | One reviewer in a fan-out: named, read-only, under a backend scope — built
-- once here so no reviewer can drift in shape or acquire write access.
--
-- Takes the scope function __already applied__ (@'reviewer' ('withBackend'
-- codex 'defaultModel') …@) for the same reason 'backends' does: threading
-- @Backend b@ \/ @Model b m@ through would drag @AcceptsModel@ and the promoted
-- model kind into this signature for no gain.
reviewer :: (Flow Text Text -> Flow Text Text) -> LeafName -> Prompt -> (LeafName, Flow Text Text)
reviewer scope name lens = (name, scope (withMode Plan (refineWith name (brief lens) id)))
