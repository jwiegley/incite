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
  , backendsFor
  , claudeAgentBackend
  , codexBackend
  , opencodeBackend
  , opencodeBackendFor
  , opencodeScope
  , blockOpencode
  , reviewer
  ) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
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
--
-- __'NonEmpty' rather than a list__, and it buys a real theorem rather than
-- documentation. "Incite.Review".@spread@ pairs one backend per lens by zipping
-- against @cycle@, which diverges on an empty list; here the type retires that
-- check, so @spread@ needs no guard and no partial head match. It also makes
-- 'claudeAgentBackend' being the first entry a fact of the definition rather
-- than of a @head@ nobody proved was safe.
backends :: NonEmpty (LeafName, Flow Text Text -> Flow Text Text)
backends = backendsFor blockOpencode

-- | 'backends' as a __pure function of whether opencode is blocked__, so the
-- roster this repo actually ships and the roster a test can ask about are one
-- definition. Everything below is stated of this; 'backends' is its application
-- to the environment.
--
-- __Blocked drops the entry, rather than aliasing it to codex.__ When
-- 'opencodeBackend' resolves to codex, keeping a third slot would put codex in
-- the roster twice — and a duplicate here is not cosmetic. @panelAcross@ builds
-- a lens × backend cross-product, so every lens would get two leaves with the
-- same @lens\@codex@ name, the same prompt and the same model: the run pays for
-- one review twice and the synthesis leaf reads one finding as two, which is
-- how a single reviewer's opinion gets double-ranked. Two honest backends beat
-- three slots holding two models.
--
-- __What this costs, said plainly.__ The panels narrow from three answers per
-- lens to two, so @review-heavy@ is 14 reviewers rather than 21 and the fan-out
-- buys correspondingly less. That is the true state of a machine without
-- opencode, and the alternative — a third slot that is codex wearing opencode's
-- name — would report 21 reviewers while running 14 models' worth of opinion.
backendsFor :: Bool -> NonEmpty (LeafName, Flow Text Text -> Flow Text Text)
backendsFor blocked =
  claudeAgentBackend :| ([codexBackend] <> [opencodeBackendFor blocked | not blocked])

-- | The claude-agent entry of 'backends', named so a flow can scope to just
-- this one without indexing into that list. 'backends' is built from it, so tag
-- and scope cannot drift between the fan-out and the single-backend use.
claudeAgentBackend :: (LeafName, Flow Text Text -> Flow Text Text)
claudeAgentBackend = ("claude-agent", withBackend claudeAgent fable5)

-- | The codex entry, named for 'backendsFor'\'s sake: it is what
-- 'opencodeBackend' becomes under @BLOCK_OPENCODE@, and the two being one
-- binding is what makes the duplicate 'backendsFor' drops a fact of the
-- definition rather than of a name matching by eye.
codexBackend :: (LeafName, Flow Text Text -> Flow Text Text)
codexBackend = ("codex", withBackend codex defaultModel)

-- | The opencode entry — __or codex, where this install cannot reach
-- opencode__. See 'blockOpencode' for the switch.
--
-- __The name moves with the scope, and that is the whole of the safety here.__
-- "Incite.Review".@admits@ decides whether a backend may answer a lens by
-- reading this name, and it refuses exactly one pairing: the fess rubric never
-- runs on codex. Swap the scope to codex while leaving the name @opencode@ and
-- that fence reads a label instead of a model — it would keep admitting the
-- rubric, and the leaf would run on codex anyway. The substitution is therefore
-- of the __entry__, never of the scope alone.
--
-- What that buys, given 'backendsFor' then drops the duplicate: a fess-carrying
-- lens is left with claude-agent as the only backend that admits it, so under
-- @BLOCK_OPENCODE@ the rubric always runs on claude — which is the one model
-- with the context window to hold it. No special case states that; it falls out
-- of the fence that was already there.
opencodeBackend :: (LeafName, Flow Text Text -> Flow Text Text)
opencodeBackend = opencodeBackendFor blockOpencode

-- | 'opencodeBackend' as a pure function of the switch, for 'backendsFor'\'s
-- reason and one sharper than it: a function that takes @blocked@ as an
-- argument while its callee reads the global answers a question nobody asked.
-- @backendsFor False@ built on the CAF returned @[claude-agent, codex, codex]@
-- under @BLOCK_OPENCODE@ — the very duplicate 'backendsFor' documents itself as
-- dropping — so the one test written to be environment-independent was not.
opencodeBackendFor :: Bool -> (LeafName, Flow Text Text -> Flow Text Text)
opencodeBackendFor True = codexBackend
opencodeBackendFor False = ("opencode", withBackend opencode defaultModel)

-- | 'opencodeBackend'\'s scope alone, for the two leaves pinned to opencode by
-- hand rather than through the roster — @review-lite@\'s @qa@ and the
-- @contemplative@ explore stance. They take a scope function, not an entry.
--
-- Neither carries the fess rubric, so neither is what the name/scope coupling
-- in 'opencodeBackend' protects; they go through this binding so that one
-- switch still moves every opencode leaf in the repository.
opencodeScope :: Flow Text Text -> Flow Text Text
opencodeScope = snd opencodeBackend

-- | Does this machine have to avoid opencode? True when @BLOCK_OPENCODE@ is set
-- to any non-empty value.
--
-- __An 'unsafePerformIO' CAF, deliberately.__ A workflow is a pure 'Flow' value
-- built at the top level, and the whole inventory is a CAF reached long before
-- anything runs; threading an environment through 'backendsFor',
-- "Incite.Feature" and "Incite.Review" would put an @IO@ (or a reader argument)
-- into every workflow signature to carry one process-constant 'Bool'. The
-- @NOINLINE@ is what makes it constant: without it GHC may float the read to
-- each use site, and a flag that answers differently at two use sites is worse
-- than either answer.
--
-- Empty counts as unset, so @BLOCK_OPENCODE= nix run …@ turns it off for one
-- command without unsetting it in the shell.
--
-- Everything that reads this is a pure function of it ('backendsFor',
-- 'opencodeBackend'), so the impurity is one line and the behaviour it selects
-- is testable in both directions without touching the environment.
blockOpencode :: Bool
blockOpencode =
  maybe False (not . T.null . T.strip . T.pack) (unsafePerformIO (lookupEnv "BLOCK_OPENCODE"))
{-# NOINLINE blockOpencode #-}

-- | One reviewer in a fan-out: named, read-only, under a backend scope — built
-- once here so no reviewer can drift in shape or acquire write access.
--
-- Takes the scope function __already applied__ (@'reviewer' ('withBackend'
-- codex 'defaultModel') …@) for the same reason 'backends' does: threading
-- @Backend b@ \/ @Model b m@ through would drag @AcceptsModel@ and the promoted
-- model kind into this signature for no gain.
reviewer :: (Flow Text Text -> Flow Text Text) -> LeafName -> Prompt -> (LeafName, Flow Text Text)
reviewer scope name lens = (name, scope (withMode Plan (refineWith name (brief lens) id)))
