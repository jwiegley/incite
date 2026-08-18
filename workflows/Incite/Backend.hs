{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Which model runs a leaf, and how a leaf gets scoped to one.
--
-- Small on purpose, and shared: the feature pipeline pins its planner to a
-- model, the review tiers fan every lens across all three backends, and both
-- need the same vocabulary. Keeping it here is what stops
-- "Incite.Feature" and "Incite.Review" from importing each other.
--
-- @droid@ is deliberately not among the backends here: upstream ships
-- 'Agent.Backend.droid' but marks its model selection __unverified__, and
-- unverified there means permissive — a @droidModel@ pin would type-check and
-- leave preflight to discover the truth at run time — while @doctor@ on this
-- machine reports droid not installed at all. A roster slot that cannot launch
-- only widens every @panelAcross@ cross-product with a leaf that cannot run.
module Incite.Backend
  ( fable5
  , gpt55
  , backends
  , backendsFor
  , claudeAgentBackend
  , codexBackend
  , codexScope
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
  ( BackendTag (ClaudeAgent, Codex)
  , Model
  , ModelSpec (Named)
  , claudeAgent
  , claudeModel
  , codex
  , codexModel
  , defaultModel
  , fallingBackTo
  , opencode
  , withBackend
  )
import Agent.Flow (Flow, Mode (Plan), withMode)
import Agent.Flow.Combinators (refineWith)
import Agent.Op (LeafName)
import Agent.Prompt (Prompt, brief)

-- | Fable 5 by match key, __falling back to Opus when the Fable allowance is
-- spent__: resolved against what this install's @claude-agent-acp@ advertises
-- ('Agent.Op.matchModelKey'); preflight refuses loudly rather than guessing if
-- either key is ambiguous.
--
-- __What the fallback is for, precisely.__ A Claude subscription meters Fable 5
-- separately, and running out of it is not an error the run can see coming:
-- @agent-functor doctor@ still lists @claude-fable-5[1m]@ in the menu, and
-- @session\/set_config_option@ still succeeds. The refusal arrives at the first
-- @session\/prompt@ —
--
-- > {"code":-32603,
-- >  "message":"Internal error: You've reached your Fable 5 limit. …",
-- >  "data":{"errorKind":"rate_limit"}}
--
-- — and before this pin carried a fallback that killed the whole run. Not one
-- leaf: a throw cancels its siblings, so a @grind-tests@ panel with twelve
-- lenses in flight lost all twelve to an allowance that had nothing to do with
-- any of them. 'Agent.Backend.fallingBackTo' fires on that error kind and only
-- that one, so an ordinary broken turn still halts loudly.
--
-- __Opus rather than Sonnet__, and not for the obvious reason. Every leaf this
-- pin serves is a __reviewer or a planner__ — a lens that misses a defect costs
-- more than the tokens it saved, which is the same argument that puts the codex
-- side of these panels on 'gpt55' at @xhigh@. A fallback that quietly halves the
-- reading is a panel reporting twelve reviewers while running twelve cheaper
-- opinions; if the cheaper answer were good enough here, it would be the pin.
--
-- __The cost, stated.__ @claude-agent\/opus@ is now a preflighted requirement
-- and a second @claude-agent-acp@ process for the whole run, spawned whether or
-- not Fable ever runs dry — that is what makes the fallback real at the moment
-- it is needed rather than a promise checked too late. @opus@ is unambiguous
-- against this install's menu (@[default, opus[1m], claude-fable-5[1m], sonnet,
-- haiku]@); read it off @agent-functor doctor@ before changing either key.
fable5 :: Model 'ClaudeAgent 'Named
fable5 = claudeModel "fable" `fallingBackTo` claudeModel "opus"

-- | The model every codex leaf in this repository runs on, __named rather than
-- inherited__.
--
-- Leaving this as 'defaultModel' means \"whatever @~\/.codex\/config.toml@
-- happens to say\", and that is not a free choice: @codex-acp@ (0.13.0 and
-- 0.16.0, its newest) cannot drive a model it has no built-in metadata for, and
-- it cannot fetch metadata at all because one unknown reasoning-effort level
-- (@max@) fails its decode of the whole models response. A global default of
-- @gpt-5.6-sol@ therefore fails __every__ codex turn with @Internal error@ —
-- see @Agent.Backend.codex@ for the full diagnosis.
--
-- That took out three of @review-lite@\'s five lenses at once (both codex
-- reviewers, plus @qa@, which is codex under @BLOCK_OPENCODE@) while the tier
-- went on describing itself as five independent reviewers. A review panel must
-- not be hostage to an interactive tool's settings file, so it names its model
-- here — exactly as 'fable5' does for claude-agent.
--
-- @gpt-5.5@ is verified to complete a turn through @codex-acp@; @gpt-5.6-sol@ is
-- verified not to — and note that @codex-acp@ __advertises @gpt-5.6-sol@__, so
-- nothing but running a turn tells the two apart. Revisit when the adapter
-- vendors a newer @codex-core@.
--
-- __The effort suffix is part of the id, not decoration.__ This backend splits
-- one model into one entry per reasoning level — @gpt-5.5\/low@,
-- @gpt-5.5\/medium@, @gpt-5.5\/high@, @gpt-5.5\/xhigh@ — so the bare key
-- @gpt-5.5@ is a substring of four of them and 'Agent.Op.matchModelKey' refuses
-- an ambiguous key rather than picking one. Preflight catches that before a run
-- spends anything, which is the whole point of it; read the ids off
-- @agent-functor doctor@.
--
-- @xhigh@ because these are __reviewers__: a lens that misses a defect costs
-- more than the tokens it saved, and the claude-agent side of the same panels is
-- pinned to 'fable5' for the same reason. It is the level the codex leaves are
-- costed at.
gpt55 :: Model 'Codex 'Named
gpt55 = codexModel "gpt-5.5/xhigh"

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
codexBackend = ("codex", withBackend codex gpt55)

-- | 'codexBackend'\'s scope alone, for the leaves pinned to codex by hand rather
-- than through the roster. The counterpart of 'opencodeScope', and it exists for
-- the same reason: __one switch moves every codex leaf in the repository__.
--
-- Six call sites wrote @'withBackend' codex 'defaultModel'@ out by hand, so the
-- model question was answered independently in seven places and the answer in
-- every one of them was \"ask the settings file\". When that file named a model
-- @codex-acp@ cannot drive, all seven failed together and nothing named the
-- shared cause. Route through this and the pin in 'gpt55' is the only thing
-- there is to change.
codexScope :: Flow Text Text -> Flow Text Text
codexScope = snd codexBackend

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
--
-- __The unblocked entry stays on 'defaultModel' by decision, not by absence of
-- an alternative.__ @opencodeModel@ is legal — upstream moved
-- @SelectsModel \'Opencode@ off its @TypeError@ branch to @()@ in @c879ee1@ —
-- and @doctor@ on this machine reports 77 wire-selectable opencode models
-- against codex's 20. What stops a pin is that __opencode ids are
-- provider-qualified and install-specific__: @google\/gemini-3.1-pro-preview@,
-- @xai\/grok-4.6@. Which ids exist depends on the credentials of the install,
-- so one is readable only off a @doctor@ run on a machine that has opencode,
-- while a pin is a single repository-wide constant. On any machine whose own
-- @doctor@ menu lacks the pinned id, 'Agent.Op.matchModelKey' finds no match
-- and preflight refuses __every opencode leaf on that machine__.
--
-- 'gpt55' is the counter-precedent only because its failure had already been
-- observed — its own haddock records it — and that asymmetry of evidence is the
-- whole argument. What is known here is narrower than the fleet: on this
-- machine opencode's default resolves and its turns complete, in 25 completed
-- @\@opencode@ leaf records under @.agent-functor\/runs@; no such failure has
-- been __reported__ from another machine, which is not the same as none having
-- occurred on one nobody has read. Revisit when a specific opencode default is
-- __observed__ to fail a turn, and pin the id read off that machine's own
-- @doctor@.
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
