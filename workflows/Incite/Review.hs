{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | The review and audit tiers: fan independent reviewers over one artifact
-- concurrently, then reduce.
--
-- One shape at three prices, escalating along three axes: __lenses__ buy
-- coverage, __backends__ buy confidence (three models agreeing, not one model's
-- opinion), and __granularity__ buys findings the other two cannot reach.
--
-- Every reviewer is read-only — 'Incite.Backend.reviewer' scopes it 'Plan' — so
-- no tier can edit what it is reading.
module Incite.Review
  ( reviewLite
  , reviewHeavy
  , reviewHeavyFlow
  , reviewAudit
  , reviewDocs
  , reviewDocsFlow
  , fessAudit
  , retro
  , retroFlow
  , plannerAudit
  , promptLint
  , promptLintBrief
  , promptLintScope
  , Subject (..)
  , lensesOf
  , lensSetViolations
  , admits
  , forbiddenPairings
  , emissionLenses
  , spread
  , grindName
  , grindSynthesis
  , grindSynthesisOver
    -- * Rescopings
    --
    -- | The two independent adjustments a grind lens stands under, and their
    -- composition. Kept apart because they answer different questions: 'toTree'
    -- says WHAT is being read, 'reporting' says WHAT COMES BACK, and a rubric
    -- already written for a whole tree needs only the second.
  , reporting
  , toTree
  , ofTree
    -- * Reorientations
    --
    -- | The lens bodies this module writes itself, rather than reading from a
    -- file: an upstream rubric plus one adjustment. Exported so a test can
    -- name the body each lens is supposed to carry — see @lensesOf@\'s
    -- expected table in @test\/Spec.hs@.
  , architectureOfChange
  , haskellOfHouse
  , qaOfCommit
  , qaOfCommitOver
  , qaSiblings
  , docsAccuracy
  , docsStrategyOfPlan
  , slopOfDocs
  , ponytailOfDocs
  , ponytailOfTree
  ) where

import Data.List (find, nub, (\\))
import qualified Data.List.NonEmpty as NE
import Data.List.NonEmpty (NonEmpty)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Agent.Backend (claudeAgent, codex, defaultModel, opencode, withBackend)
import Agent.Flow (Flow, Mode (Plan), withMode, (>>>))
import Agent.Flow.Combinators (exploreFlows, hierarchical, refineWith, unionFindings)
import Agent.Op (LeafName, leafNameText)
import Agent.Prompt (Prompt, brief, iii, promptText, __i)
import Agent.Run (Workflow, withCapturedTranscript, workflow, workflowReq)

import Incite.Backend (backends, claudeAgentBackend, fable5, reviewer)
import Incite.Prompts

-- | The cheap tier, fired by @wiggum@ after every commit: five reviewers, one
-- wave, reduced by a pure fold with no synthesis leaf.
--
-- Deliberately __not__ 'withCapturedTranscript' even though fess is a lens: all
-- five leaves read the same input, so the mark would hand the code lenses a
-- conversation log. Here fess audits claims against the diff; 'fessAudit' is
-- the whole-session version.
--
-- __The @qa@ leaf is what this tier had no lens for.__ The other four ask
-- whether the change is right, honest, tangled or too big; none of them asks
-- how it fails, and none of them looks at a trust boundary — security lives in
-- 'reviewHeavy' behind an 8.5 KB rubric this tier cannot afford. 'qaOfCommit'
-- is 2.6 KB and buys the failure question on every commit.
--
-- The backend spread here is written out per leaf rather than fanned, so the
-- @fess@ leaf's is a choice made in this list — and it is claude-agent because
-- codex cannot hold that rubric. 'admits' is the same rule where a panel builds
-- its pairings itself.
reviewLite :: Workflow
reviewLite =
  workflowReq
    "review-lite"
    [iii|
      Review a commit with five independent reviewers (correctness, fess
      claims-versus-diff audit, reshape complexity, ponytail cuts, adversarial
      QA) — one call, cheap enough to run on every commit
    |]
    $ exploreFlows
      [ reviewer (withBackend claudeAgent fable5) "correctness" reviewCorrectness
      , reviewer (withBackend claudeAgent defaultModel) "fess" fess
      , reviewer (withBackend codex defaultModel) "complexity" reviewComplexity
      , reviewer (withBackend codex defaultModel) "ponytail" ponytailReviewRubric
      , reviewer (withBackend opencode defaultModel) "qa" qaOfCommit
      ]
      -- Narrowing, as everywhere else: what is wrong, what was claimed, how it
      -- fails, what is braided, what should not exist at all.
      (hierarchical ["correctness", "fess", "qa", "complexity", "ponytail"])

-- | The thorough tier: seven lenses answered by all three backends, then a
-- synthesis leaf that de-duplicates and ranks. Where 'reviewLite' spreads its
-- lenses across backends for cheap independence, this buys the real thing. Use
-- before a PR, not on a beat.
reviewHeavy :: Workflow
reviewHeavy =
  workflowReq
    "review-heavy"
    [iii|
      Review a diff with seven review lenses (correctness, security, tests,
      performance, Haskell, ponytail complexity, AI-generated-code failure
      modes), each run on all three backends — 21 reviewers — then synthesise
      one ranked list
    |]
    reviewHeavyFlow

-- | 'reviewHeavy' as a plain 'Flow', so 'Incite.Feature' runs the same panel
-- inline after implementation instead of copying it.
--
-- Both regroupings run on claude-agent alone. Fanning them across all three
-- backends as well is what makes 'reviewAudit' a 75-leaf tier, and this one has
-- to stay firable after a commit.
reviewHeavyFlow :: Flow Text Text
reviewHeavyFlow =
    exploreFlows
      [ ("full", panel auditLenses)
      , ("units", regroup "units" reviewUnits)
      , ("sequence", regroup "sequence" reviewSequence)
      ]
      unionFindings
      >>> refineWith "synthesis" (brief reviewSynthesis) id
  where
    auditLenses = lensesOf OfDiff
    regroup name how =
      refineWith ("regroup:" <> name) (brief how) id >>> panelAcross [claudeAgentBackend] auditLenses

-- | The exhaustive tier: 'reviewHeavy'\'s panel plus a change-reframed
-- architecture lens, at three granularities — the diff as landed, regrouped
-- into logical units, and re-expressed as the commits it should have been
-- (whose @## divergence@ is the finding only that view produces). The full
-- panel answers each. 75 leaves: run it deliberately, never on a beat.
--
-- The regroupings are agent leaves, not a pure split: \"logical unit\" and
-- \"ideal sequence\" are semantic, unlike @T.lines@ on a plan.
reviewAudit :: Workflow
reviewAudit =
  workflow
    "review-audit"
    [iii|
      Exhaustively audit a change: eight review lenses (correctness, security,
      tests, performance, Haskell, ponytail, AI-failure modes, architecture) on
      all three backends, at three granularities (full diff, logical units,
      ideal sequential edits) — 75 reviewers — then synthesise one ranked list
    |]
    [iii|
      The working change in the current working directory. Run `git diff` (or
      `git show` for the last commit) and read it before reporting anything.
    |]
    $ exploreFlows
      [ ("full", panel auditLenses)
      , ("units", regroup "units" reviewUnits)
      , ("sequence", regroup "sequence" reviewSequence)
      ]
      unionFindings
      >>> refineWith "synthesis" (brief reviewSynthesis) id
  where
    auditLenses = lensesOf OfChange
    regroup name how = refineWith ("regroup:" <> name) (brief how) id >>> panel auditLenses

-- | The same shape pointed at prose: four lenses that only a document admits,
-- plus the ponytail question every artifact admits, each answered by all three
-- backends, then the same synthesis leaf.
--
-- __No regroupings.__ 'reviewAudit' buys its third tier by re-expressing a
-- change as logical units and as the commits it should have been. Neither view
-- exists for a document — a README has no commit sequence it should have been —
-- so this tier is the panel and the reduction, and nothing else.
reviewDocs :: Workflow
reviewDocs =
  workflowReq
    "review-docs"
    [iii|
      Review documentation with four lenses only prose admits (accuracy against
      the code, completeness for a reader who follows it, structure, and the
      AI-slop tells that mark prose as machine-written) plus the ponytail cuts
      every artifact admits, each run on all three backends, then synthesise one
      ranked list
    |]
    reviewDocsFlow

-- | 'reviewDocs' as a plain 'Flow', so the acting workflow of "Incite.Feature"
-- can run the same panel inline rather than copying it.
--
-- __Two consumers__, like 'reviewHeavyFlow': the 'reviewDocs' workflow and
-- "Incite.Feature".@shipDocs@, which runs the same panel inline as a stage. The
-- binding landed ahead of the second consumer, and that is the whole reason it
-- is separate from the workflow.
--
-- 'reviewSynthesis' is reused rather than copied for prose: it says
-- \"reviewers\", \"finding\" and \"location\" and never \"code\", so what it
-- de-duplicates and ranks is already artifact-agnostic.
--
-- __Do not union this panel with a code panel.__ Every subject carries a lens
-- named @ponytail@ — the third law of 'lensesOf' — and @panelAcross@ keys its
-- blocks @lens\@backend@, so one 'unionFindings' over both would head two
-- different rubrics with the same @ponytail\@codex@, which is the collision the
-- pairwise-distinct law exists to prevent. Reduce each panel separately.
reviewDocsFlow :: Flow Text Text
reviewDocsFlow =
  panel (lensesOf OfDocs) >>> refineWith "synthesis" (brief reviewSynthesis) id

-- | The __kind of artifact__ a panel is pointed at. Not a switch over which
-- lenses differ — a name for what is under review, from which the lens set
-- follows. The type says what is being read, and 'lensesOf' says what reading
-- it admits.
--
-- A subject that shares no __rubric__ with the others is still a 'Subject':
-- 'OfDocs' is one, and not one body in its panel is a body a code panel sends.
-- It is not free of the others in its __names__, and cannot be — 'lensesOf'\'s
-- third law puts @\"ponytail\"@ in every subject's set, so that one name is
-- shared by construction and is the only one 'OfDocs' has in common with
-- 'OfDiff'.
data Subject
  = -- | 'reviewHeavy': the diff, and nothing wider.
    OfDiff
  | -- | 'reviewAudit': the change, and the shape it moves the code toward.
    OfChange
  | -- | 'reviewDocs': prose, and the code it makes claims about.
    OfDocs
  | -- | @grind-paradox@: a whole source tree, and the debt standing in it.
    -- Nobody changed anything; the question is what is already wrong.
    OfTree
  deriving (Eq, Show, Bounded, Enum)

-- | The lenses that artifact admits, in the order their blocks are read.
--
-- Three laws hold at every constructor, and 'lensSetViolations' is where they
-- are written down as code:
--
-- * the list is __non-empty__ — a subject with no lens is a panel with nothing
--   to fan out;
-- * the leaf names are __pairwise distinct__ — @panelAcross@ keys blocks by
--   @lens\@backend@, so a repeat makes two reviewers indistinguishable in the
--   reduction;
-- * @\"ponytail\"@ is __present__ — every artifact admits the question of what
--   should not exist, and each subject picks the rubric pointed at it.
--
-- Total in 'Subject', so a new constructor cannot be added without answering
-- what its artifact admits.
lensesOf :: Subject -> [(LeafName, Prompt)]
lensesOf subject = case subject of
  OfDiff -> codeLenses ponytailReviewRubric
  OfChange -> codeLenses ponytailAuditRubric <> [("architecture", architectureOfChange)]
  OfDocs ->
    [ ("accuracy", docsAccuracy)
    , ("completeness", docsCompleteness)
    , ("structure", docsStructure)
    , ("slop", slopOfDocs)
    , ("ponytail", ponytailOfDocs)
    ]
  -- Ten lenses, and only four of them are new files. The other six are the
  -- code tiers' own lenses put under 'ofTree' — a tree audit that could not
  -- ask about correctness, tests, complexity, architecture or performance
  -- would be a narrower audit than @review-audit@, which is the opposite of
  -- what it is for.
  --
  -- @architecture@ takes 'reporting' alone: @prompts/review/architecture.md@
  -- opens by saying it reads a whole tree rather than a diff, so 'toTree'
  -- would tell it something it already knows and 'architectureOfChange' is
  -- what points it the OTHER way. It gets its first consumer beyond that
  -- reorientation here.
  --
  -- The ORDER is semantic, not cosmetic: @spread@ pairs one backend per lens
  -- positionally, so moving a row reassigns which model audits what. The
  -- ordered name list in @test\/Spec.hs@ is what says so.
  OfTree ->
    [ ("correctness", ofTree reviewCorrectness)
    , ("tests", ofTree reviewTests)
    , ("stubs", reporting grindStubs)
    , ("vacuous", reporting grindVacuous)
    , ("dry", reporting grindDry)
    , ("hardcodings", reporting grindHardcodings)
    , ("refactor", ofTree reviewComplexity)
    , ("architecture", reporting reviewArchitecture)
    , ("performance", ofTree perfReviewer)
    , ("ponytail", ponytailOfTree)
    ]
  where
    codeLenses ponytailRubric =
      [ ("correctness", reviewCorrectness)
      , ("security", codeReviewerSecurity)
      , ("tests", reviewTests)
      , ("performance", perfReviewer)
      , ("haskell", haskellOfHouse)
      , ("ponytail", ponytailRubric)
      , ("doctrine", codeReview)
      ]

-- | 'lensesOf'\'s three laws as a refutable check: one 'Text' per law the set
-- breaks, and @[]@ for a set that holds all three.
--
-- __Beside 'lensesOf' rather than in the test suite__, because the laws are
-- stated on 'lensesOf' and an executable statement that lives somewhere else is
-- one a reader of this module cannot reach — the haddock above linked a name
-- that was not in scope here. A new 'Subject' now answers its laws in one file.
--
-- __A report rather than an assertion__, and that is the whole reason it is a
-- separate binding. Quantified over 'Subject' these laws pass by construction,
-- so a check that could only ever be pointed at 'lensesOf' would be a law
-- nobody knows is wired to anything. Returning what is wrong instead of
-- throwing is what lets a caller point it at a set that BREAKS each law and
-- read back the right complaint.
--
-- Emptiness has no single-defect witness: @[]@ reports the missing ponytail
-- too, because a set with no lenses has no ponytail lens either.
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

-- | The four lenses that only a __code generator__ admits: targets that
-- disagree about one source construct, validators emitted and never called,
-- constructs a backend silently drops, and the quality of the code it emits.
--
-- __An appendable list, not a fifth 'Subject'__, and the reason is 'lensesOf'\'s
-- third law. Every subject carries a @ponytail@ lens, because every artifact
-- admits the question of what should not exist. Generated code does not: it is
-- written by the emitter, so the answer is always \"whatever the emitter stops
-- emitting\", and the finding belongs to the emitter's own tree. A constructor
-- here would demand a ponytail-of-generated-code rubric nobody asked for and
-- nothing would read.
--
-- Unioned with @'lensesOf' 'OfTree'@ at the one call site that wants both, so
-- the distinctness the panel needs is a property of the union — which is what
-- @test\/Spec.hs@ checks, rather than of either half alone.
emissionLenses :: [(LeafName, Prompt)]
emissionLenses =
  [ ("target-consistency", reporting grindTargetConsistency)
  , ("validator-calls", reporting grindValidatorCalls)
  , ("codegen-gaps", reporting grindCodegenGaps)
  , ("emitted-code", reporting grindEmittedCode)
  ]

-- | The __output contract__ every grind lens stands under: a claim reproduced
-- by something a reader can run, reported where 'reviewSynthesis' can rank it.
--
-- One binding rather than a tail copied into fourteen bodies, for the reason
-- @prompts\/grind\/paradox-facts.md@ is one file: two copies of a contract
-- drift, and the drift here is a lens whose findings the synthesis silently
-- drops for want of a location.
--
-- __Independent of 'toTree'__, which the original shape of this fused. Nine of
-- the fourteen grind lenses are written for a whole tree already and need only
-- this; applying the tree clause to them as well would tell a reader it is not
-- reading a change, which it never thought it was.
--
-- __What it asks for is the union of two different lists in
-- 'reviewSynthesis', and conflating them loses findings.__ That reducer ADMITS
-- on location, a reachable path, and a stated consequence — anything missing
-- one of the three is removed before it is read — and it FORMATS what survives
-- as location, what is wrong, what fixes it. Ask for the format alone and a
-- lens writes findings with no consequence, which are complete by this contract
-- and dropped by the next stage. So this asks for all four fields.
reporting :: Prompt -> Prompt
reporting rubric =
  [__i|
    #{rubric}

    ---

    ONE ADJUSTMENT to the above, and it is the OUTPUT CONTRACT. Any output
    format, schema or return shape the text above names is VOID; this replaces
    it.

    One line per finding, and every line carries four things:

    - the location, as file:line;
    - what is wrong there;
    - the consequence — what goes wrong if nobody acts. A reader has to be able
      to reach it: name the caller, the input, or the run that gets there;
    - the concrete fix.

    A finding missing the location, the reachable path, or the consequence is
    removed by the reduction behind you before anybody reads it, and one missing
    the fix arrives at a fixer with nothing to do. A line you cannot complete is
    a line not to write.

    Every claim must be reproduced by something the next reader can run: a
    filtered test, a grep, a command and its output, or a probe file you wrote
    and then deleted. Name that probe in the finding. A claim you reached by
    reading alone is a guess, and a fixer acts on your guesses at full cost.

    Rank by consequence, worst first: what ships wrong if nobody acts on it.

    If you found nothing, say `Nothing found.` and stop. Never pad the list.
  |]

-- | A rubric written for a __change__, pointed at a __whole source tree__.
--
-- The mirror of 'architectureOfChange', which takes a whole-tree rubric the
-- other way. Both exist because a lens body says what it is reading, and a
-- panel that lies to a reviewer about its subject gets findings about a diff
-- that is not there.
toTree :: Prompt -> Prompt
toTree rubric =
  [__i|
    #{rubric}

    ---

    ONE ADJUSTMENT to the above, and it is a change of subject: you are reading
    a WHOLE SOURCE TREE, not a change. There is no diff, no commit and no
    staged work. Anything above that tells you to read one is VOID, and so is
    any instruction to keep a finding inside the lines a change touched.

    The tree is large, so say where you looked and why that is where the debt
    is. Read what the rubric points you at, follow it into what it calls, and
    judge the code as it stands rather than as somebody changed it. Debt that
    has sat here for a year is exactly what this reads for, and it is invisible
    to every reviewer pointed at a diff.
  |]

-- | 'toTree' then 'reporting': a diff-scoped rubric rescoped to a tree AND put
-- under the output contract. What the code tiers' own lenses need to join a
-- grind panel.
ofTree :: Prompt -> Prompt
ofTree = reporting . toTree

-- | The upstream Haskell rubric plus this codebase's own rules — the lens every
-- code tier runs under the name @haskell@.
--
-- __Composed rather than chosen.__ The two are not alternatives: the upstream
-- rubric is the general Haskell review (partial functions, strictness, error
-- handling, module structure) and @agents\/haskell-review.md@ is what this
-- codebase asks for beyond it (no primitive in a top-level signature, newtypes
-- and smart constructors, @RecordWildCards@ binding fields by name, a type
-- parameter where it retires a runtime check) plus the one rule it overrules.
-- Running the base alone — which is what this lens did — is a review that never
-- mentions any of the house rules, and the deployed sub-agent that does carry
-- them is not something a panel run can reach.
--
-- __One home for the rules.__ The addendum is spliced from the file flake-prompt
-- deploys, so the sub-agent and this lens cannot come to say different things.
-- The addendum is not a lens of its own for the reason it names in its own first
-- paragraph: it defers whole sections to the rubric it sits under, so alone it
-- reviews a codebase against half a rubric.
haskellOfHouse :: Prompt
haskellOfHouse =
  [__i|
    #{haskellReviewer}

    ---

    #{haskellHouse}
  |]

-- | 'reviewArchitecture' is whole-tree by its own contract. This reorientation
-- keeps its questions and points them at the shape a change moves toward; the
-- file is untouched, so it stays whole-tree for any other consumer — though
-- none is deployed here today; the only reader is this reorientation.
architectureOfChange :: Prompt
architectureOfChange =
  [__i|
    #{reviewArchitecture}

    ---

    ONE ADJUSTMENT to the above: you are reading a **change**, not a whole
    tree. Everything else stands — the measure is still what a likely change
    costs, and line-level defects still belong to the other reviewers.

    Judge the shape this change moves the code toward. Which of the problems
    above does it introduce, deepen, or relieve? A hunk that adds the third
    home for one decision, an import that points a new arrow the wrong way, a
    module this change confirms as the one everything must visit — those are
    your findings. Read the surrounding code where you need it; the change
    alone does not show you the shape it is landing in.

    If the change leaves the shape no worse, say `Sound.` and stop.
  |]

-- | The adversarial QA reviewer pointed at one commit, and fenced off the four
-- lenses beside it.
--
-- Both halves are load-bearing. 'reviewLite' reduces by a pure fold and has __no
-- synthesis leaf__, so nothing downstream de-duplicates: two reviewers reporting
-- one defect is two findings in the output, every commit, forever. Upstream's
-- process walks specification, edge cases, error handling, security, scale,
-- integration, observability and documentation — and the first three are what
-- 'reviewCorrectness' and 'fess' already own. What is left is the half no other
-- lens in this tier has, so that is what this asks for.
--
-- The output format goes with it: the tier's lenses emit one line per finding
-- and a token when clean, and a five-field block per finding would drown the
-- other four in a fold that ranks nothing.
qaOfCommit :: Prompt
qaOfCommit = qaOfCommitOver qaSiblings

-- | The lenses @review-lite@ runs BESIDE its qa leaf, each with the question it
-- owns — the roster 'qaOfCommit' fences itself off.
--
-- __A table, not a sentence.__ The fence used to be four topics written into a
-- paragraph, and a paragraph cannot be checked against anything: drop a lens
-- from 'reviewLite' and qa goes on declining findings to an owner that no
-- longer exists, silently, because no name, count, plan skeleton or cost
-- estimate moves when it does. Named here, the roster is a claim about the
-- tier — the test asserts these names against 'reviewLite'\'s own leaves, read
-- off its skeleton — and the leaf that has to agree with it splices it.
--
-- The names are the tier's LEAF names, so the fence names the block a reader
-- will actually see beside qa's in the fold, rather than a paraphrase of it.
qaSiblings :: [(LeafName, Text)]
qaSiblings =
  [ ("correctness", "whether the change is correct on the inputs it will see")
  , ("fess", "whether its claims match the diff")
  , ("complexity", "what is braided together")
  , ("ponytail", "what should not exist")
  ]

-- | An 'Int' as prompt text. Shared by the two briefs that tell a leaf how many
-- blocks it is one of, so that neither spells a number a list already knows.
count :: Int -> Text
count = T.pack . show

-- | 'qaOfCommit' with its roster written out, which is the only form that can
-- be checked against the tier it belongs to.
--
-- The two counts are derived from the roster rather than spelled, for the
-- reason 'grindSynthesisOver' derives its own: a fifth lens added to
-- 'reviewLite' would otherwise leave this leaf telling its reader there are
-- five reviewers and four owners, which is prose that nothing goes red on.
qaOfCommitOver :: [(LeafName, Text)] -> Prompt
qaOfCommitOver siblings =
  [__i|
    #{qaAgent}

    ---

    TWO ADJUSTMENTS to the above, and both narrow you.

    **What you are reading.** One commit in this repository, not a release. Run
    `git show` (or `git diff` for uncommitted work) and read it before reporting
    anything. Where a risk depends on code the commit does not touch, read that
    code — but the finding has to name a line the commit changed, or it belongs
    to a review nobody asked for.

    **What is yours.** You are one of #{count (length siblings + 1)} independent
    reviewers and there is no synthesis step behind you, so anything you repeat
    ships twice. The other #{count (length siblings)} own the following, under
    the name each one's block carries:

    #{T.intercalate "\n" ["- `" <> leafNameText n <> "` — " <> owns | (n, owns) <- siblings]}

    Do not report any of those. Yours is the question none of them asks — **how
    does this fail?**

    - a trust boundary this commit moves or crosses: input that reaches a query,
      a command, a path, a deserialiser; a check that runs after the effect it
      guards;
    - failure under conditions the happy path never sees: concurrency, retries,
      partial writes, a resource that runs out, a clock that moves backwards;
    - an error path that exists but loses what a debugger would need, or a
      failure nothing in production would surface;
    - a contract with something outside this change — a schema, a wire format, a
      caller — that the commit changes on one side only.

    Your severity scale stands and every finding carries one. The Output Format
    section above is VOID: one line per finding — location, how it fails, what
    the failure costs — and quote the line you are pointing at. A risk you
    cannot point at a line for is not a finding here.

    If the commit has no failure you can name, say `No failure found.` and stop.
    Do not manufacture a risk.
  |]

-- | The documentation strategy rubric turned into a __plan lens__: keep its
-- questions, void its deliverable.
--
-- Left alone 'technicalDocsStrategist' answers its own Task section — a
-- ten-section strategy document for a hypothetical product — which is the same
-- failure 'lookaheadPlanningSpecialist' has and needs the same kind of override.
-- What is worth having is everything above that Task: which audience a document
-- is for, which of the four content types it is (reference, tutorial, how-to,
-- concept) and the fact that mixing them is the defect, where a fact belongs so
-- it has one home, and what \"done\" means for a documentation change. Those are
-- questions about a plan, so this edits the plan rather than judging the prose.
docsStrategyOfPlan :: Prompt
docsStrategyOfPlan =
  [__i|
    #{technicalDocsStrategist}

    ---

    ADJUSTMENT, and it changes what you produce. Do not write a strategy
    document. The Task, Deliverables and Tone sections above describe an
    engagement nobody here asked for — treat them as VOID. Anything about team
    structure, tooling stacks, i18n, analytics, video, translation or hiring is
    VOID with them: this is one repository's documentation, edited by the person
    reading you.

    What survives is the expertise, applied to the plan below. Return the SAME
    plan, edited, in the same format — no new sections, no strategy preamble.

    Edit it for these and nothing else:

    - **Audience.** Every step must say who the document is for and what they
      already know. A step that does not is written for nobody; fix it or cut it.
    - **Content type.** Reference, tutorial, how-to and conceptual explanation
      answer different questions. Where a step mixes two, split it. Where a step
      writes a tutorial for something that wants a reference, say so and change
      it.
    - **One home per fact.** A fact repeated in two documents is the next
      finding. Where two steps would both state it, say which document owns it
      and make the other point there.
    - **Done.** Every step needs a check a reader could run: the code it cites
      exists, the command it shows runs, the link resolves. A step whose only
      completion test is "the prose reads well" is not done, it is finished.
    - **Freshness.** A step that documents something the code is about to change
      is a step that will be wrong. Say so where you see it.

    Cut a step that survives none of these. If the plan already holds, return it
    unchanged.
  |]

-- | The anti-slop editor turned into a __reviewer__: the tells stay, the rewrite
-- goes.
--
-- 'stopSlop' is written for the author — it returns cleaned prose and a
-- scorecard. Every lens in this panel is read-only ('Incite.Backend.reviewer'
-- scopes it 'Plan'), and the leaf that acts on findings is @remediate@, so a
-- lens that rewrites would be a rewrite nobody reads and a finding nobody fixes.
-- Its checklist is the part worth having: it names the tells precisely enough
-- that a finding can quote one.
slopOfDocs :: Prompt
slopOfDocs =
  [__i|
    #{stopSlop}

    ---

    ONE ADJUSTMENT to the above: you are a reviewer, not the editor. Do not
    return cleaned prose, do not rewrite the document, and do not touch a file.
    The Output Format section is VOID.

    Report each tell as a finding instead: the file, the line, the phrase you
    caught, which rule above it breaks, and the rewrite you would have made. The
    rewrite belongs IN the finding — that is what makes it fixable by someone
    else.

    Two limits, because a slop lens with no limits reports a whole document.
    Quote the offending text in every finding; a rule number with no quotation
    is a preference. And the scoring table is a judgement on the document as a
    whole, so give it once at the end, not per finding.

    If the prose carries none of these tells, say `Clean.` and stop.
  |]

-- | The honesty rubric pointed at a document. A reorientation rather than a
-- file under @prompts\/review@, for the reason "Incite.Prompts" gives on
-- 'docsCompleteness': a second copy of 'fess' is one of the three homes
-- 'docsStructure' is written to report.
docsAccuracy :: Prompt
docsAccuracy =
  [__i|
    #{fess}

    ---

    ONE ADJUSTMENT to the above, and it is a change of referent. You are a
    reviewer; the account is not yours. It is a __document__ in this repository,
    written by somebody else, and the record it answers to is the code. Wherever
    the rubric says you, your account, a claim you made or the work you claimed,
    read the document and its author instead.

    So: the document is the claim, the code is the record. Every command it
    tells the reader to run, and every flag, path, identifier, default and
    version it names — open the code, check it, cite file:line on both sides.

    Of the four shapes above, three repoint and one is void:

    * verification gap — a claim nothing in the repository backs up;
    * spec drift — a behaviour the code changed, still described the old way;
    * quiet downgrades — prose left describing what was there before a change;
      here that is most of the work;
    * scope creep — VOID. A document modifies no file. Do not report it, and do
      not report "none" for it either.

    The closing paragraph above is VOID as well. There is no list of gaps "you
    did not report", and "correcting means doing the work you claimed, not
    editing the claim" inverts the remedy here: the claim IS the artifact, so
    correcting a false sentence means editing that sentence, and never means
    changing the code to match it.

    A fact that is MISSING belongs to the completeness reviewer, and one in the
    wrong PLACE to the structure reviewer; you judge only whether what is
    written is true. Where you cannot reach the code that settles a claim, name
    what you would read and do not grade it either way.

    If every claim you checked holds, say `Sound.` and stop.
  |]

-- | The ponytail question — what should not exist — asked of prose. Raw,
-- 'ponytailAuditRubric' hunts dependencies, factories and dead flags, so
-- pointed at a README it finds nothing or invents something, and a lens that
-- emits noise costs more than no lens.
ponytailOfDocs :: Prompt
ponytailOfDocs =
  [__i|
    #{ponytailAuditRubric}

    ---

    ONE ADJUSTMENT to the above, and it is a change of subject: you are reading
    __documentation__, not a source tree. The measure stands — what would
    deletion fix — and so does the ranking. Its named sections do not, and each
    one is replaced here outright.

    __Hunt.__ The list above (deps, interfaces, factories, wrappers, dead flags,
    hand-rolled stdlib) is VOID; a document is made of none of them. Hunt these:

    * a paragraph that says what the paragraph above it already said;
    * a section for something that no longer exists, or a step nobody performs;
    * prose explaining what the one command below it already shows;
    * a table or example held in step with the code by hand, where the code
      answers the same question — name what to point the reader at instead;
    * ceremony: a preamble before the instruction, a summary of the document
      inside the document.

    __Tags.__ `delete:` is prose nothing needs; `yagni:` a section written for a
    reader who does not exist; `shrink:` the same point in fewer lines, with the
    shorter form shown. `stdlib:` and `native:` fire only where the document
    maintains by hand what the tooling already prints, such as a help text.

    __Output.__ One line per finding, ranked, as above, and `[path]` is the file
    and the heading you would cut under. A document has no dependencies to
    count, so the deps figure is VOID: end with `net: -<N> lines possible.`
    Nothing to cut: `Lean already. Ship.`

    __Boundaries.__ Read "over-engineering and complexity" as prose that should
    not exist. What the document gets WRONG belongs to the accuracy reviewer,
    what it LEAVES OUT to completeness, where a section SITS to structure.
    Length alone is not a finding: a long passage the reader needs stays, and a
    cut you cannot name a reader for is not a cut.
  |]

-- | The ponytail question asked of a whole tree, by a lens whose findings a
-- fixer acts on __in the same run__.
--
-- 'ofTree' would be enough to make it a grind lens, and the extra clause is
-- what makes it a different one. 'OfChange' carries 'ponytailAuditRubric' raw,
-- and a set of Subjects whose ponytail lenses are one body is a set where two
-- panels run the same reviewer under two names — the pairwise-distinct law in
-- @test\/Spec.hs@ is written over these bodies precisely so that reusing the
-- rubric here goes red.
--
-- So the clause is forced rather than chosen, and it says the one thing that is
-- true here and false in every other tier: nobody reads this report before
-- acting on it. A cut named as a category is a cut the fixer behind it has to
-- rediscover, and rediscovering it is where a fixer deletes the wrong thing.
ponytailOfTree :: Prompt
ponytailOfTree =
  [__i|
    #{ofTree ponytailAuditRubric}

    ---

    ONE MORE ADJUSTMENT, and it narrows what counts as a finding here. Your
    findings go to a fixer in THIS run, not to a person who will read the tree
    first. So every cut names the exact file and the exact deletion: the
    binding, the branch, the flag, the module. A finding that says a category
    of thing should go — "the wrapper layer", "the unused helpers" — is a
    finding the fixer has to rediscover, and rediscovering a cut is where the
    wrong thing gets deleted.

    Where a deletion moves recorded output or breaks a caller, say which
    output and which caller, because the fixer has to fix them in the same
    change.
  |]

-- | The cross-product: every lens answered by every backend, concurrently, over
-- one artifact. Leaf names are @lens\@backend@, so 'unionFindings' heads each
-- block with which lens on which model produced it.
panel :: [(LeafName, Prompt)] -> Flow Text Text
panel = panelAcross (NE.toList backends)

-- | 'panel' over a chosen set of backends, and the generalisation 'panel' is
-- defined by — a narrowed panel cannot drift from the full one in leaf naming
-- or reduction. The @\@backend@ suffix stays even for a singleton, because
-- these blocks are read alongside a full panel's.
panelAcross :: [(LeafName, Flow Text Text -> Flow Text Text)] -> [(LeafName, Prompt)] -> Flow Text Text
panelAcross bs lenses =
  exploreFlows [paired l b | l <- lenses, b <- bs, admits (fst b) (snd l)] unionFindings

-- | __One backend per lens__, cycling: the leaf set IS the lens set. Where
-- 'panelAcross' buys confidence by asking every lens of every model, this buys
-- coverage — 14 lenses cost 14 leaves here and 42 there, and a tier that reads
-- a whole tree cannot afford the second.
--
-- The pairing is a zip against @'NE.cycle' bs@, so the leaf count is
-- @length lenses@ and never a @min@ of the two. Its totality is the type of
-- 'backends' ('NonEmpty'), not a guard here: @cycle@ on an empty list
-- diverges, and there is no case in this function that could catch it.
--
-- __The pairing is positional, and that makes lens order semantic.__ Reorder
-- @'lensesOf' 'OfTree'@ and a different model audits each lens, with no type
-- error and no visible change to any name — which is why the lens-name list in
-- @test\/Spec.hs@ is asserted as an ordered list rather than as a set.
--
-- Leaf names stay @lens\@backend@, through the same 'paired' that builds a
-- full panel, so a spread block and a panel block are read the same way by
-- 'unionFindings' and by 'reviewSynthesis'.
spread :: NonEmpty (LeafName, Flow Text Text -> Flow Text Text) -> [(LeafName, Prompt)] -> Flow Text Text
spread bs lenses =
  exploreFlows (zipWith assign lenses (NE.toList (NE.cycle bs))) unionFindings
  where
    -- A backend that must not answer this lens ('admits') is rotated past
    -- rather than dropped: every lens still gets a leaf, which is the whole
    -- property of a spread, and only the model changes. Positional order is
    -- preserved for every other lens.
    assign l b
      | admits (fst b) (snd l) = paired l b
      | otherwise = paired l (fromMaybe b (find (\b' -> admits (fst b') (snd l)) (NE.toList bs)))

-- | May this backend be handed this lens? Total, and 'False' in exactly one
-- case: __the fess rubric never runs on codex__.
--
-- codex cannot hold that rubric — it is a self-audit turned on an account, and
-- what comes back is not an audit — so a @fess\@codex@ block is not a cheaper
-- reviewer, it is a block of text the synthesis leaf will rank as though it
-- were one. A tier must therefore be unable to BUILD the pairing, rather than
-- everyone remembering not to write it.
--
-- __Keyed on the lens body, not on its name.__ 'docsAccuracy' is 'fess' pointed
-- at prose and splices it verbatim, and it is called @accuracy@; a name list
-- would have missed it, and would have to be extended by hand for every
-- reorientation written after this. The body test covers the ones that exist
-- and the ones that do not yet.
admits :: LeafName -> Prompt -> Bool
admits backendTag lens = not (leafNameText backendTag == "codex" && carriesFess lens)

-- | Does this lens carry the fess rubric — as itself, or spliced into a
-- reorientation of it?
carriesFess :: Prompt -> Bool
carriesFess lens = promptText fess `T.isInfixOf` promptText lens

-- | The pairings a fan-out over these backends and lenses is forbidden to build,
-- as @lens\@backend@ names: the refutable form of 'admits', and @[]@ for a set
-- that a panel can build whole.
--
-- Exported for the test, which asserts both directions — that this names the
-- docs panel's @accuracy\@codex@, so the fence is known to be wired to a real
-- pairing, and that no such leaf survives into a built flow.
forbiddenPairings :: [LeafName] -> [(LeafName, Prompt)] -> [Text]
forbiddenPairings bs lenses =
  [ leafNameText name <> "@" <> leafNameText b
  | (name, lens) <- lenses
  , b <- bs
  , not (admits b lens)
  ]

-- | One reviewer of a fan-out: the lens, under a backend, named @lens\@backend@.
-- Shared by 'panelAcross' and 'spread' so the two cannot drift in leaf naming —
-- 'unionFindings' heads each block with this name, and 'reviewSynthesis' is
-- told what the two halves of it mean.
paired ::
  (LeafName, Prompt) ->
  (LeafName, Flow Text Text -> Flow Text Text) ->
  (LeafName, Flow Text Text)
paired (name, lens) (backendTag, scope) = reviewer scope (name <> "@" <> backendTag) lens

-- | The slug of the grind workflow, in one place. @workflowG@ names the tool
-- with it and 'grindSynthesis' writes the report under it, so the file on disk
-- and the tool that produced it cannot come to be called different things.
grindName :: Text
grindName = "grind-paradox"

-- | 'reviewSynthesis' plus the two things a grind run needs of it, parameterised
-- on the run's own name in the style of 'promptLintBrief'.
--
-- __It writes a file, and the artifact is still the report.__ The ranked text
-- IS this leaf's output; the copy under @docs\/audits\/@ is a side effect for a
-- human to read afterwards. That is why the fixer downstream is handed this
-- leaf's output rather than the path — a fixer that read the path would depend
-- on a write that may have failed, and one that reads the artifact cannot.
--
-- __And it refuses on a short panel.__ A backend that is unauthenticated or
-- unavailable answers with empty text, which folds into a synthesis as
-- \"nothing found\" and is indistinguishable from a clean tree. Naming the
-- blocks it received, and stopping when one is missing, is what turns a
-- backend outage into a failure instead of a clean bill of health.
--
-- No separate TODO file. Upstream wrote one because its fixers ran in a later
-- phase and needed a hand-off; here the fixer is the next stage of the same
-- run, so a TODO would have no reader.
grindSynthesis :: Text -> Prompt
grindSynthesis name = grindSynthesisOver name (map fst (lensesOf OfTree <> emissionLenses))

-- | 'grindSynthesis' with the roster written out, which is the only form that
-- can actually refuse.
--
-- __Told the names, not just to check.__ @unionFindings@ heads a block for every
-- leaf that ran, so a leaf which never started leaves no block at all — and a
-- reader with no roster cannot tell fourteen blocks from ten. \"Stop if a block
-- is missing\" without the list is an instruction nobody can follow.
--
-- Derived from the lens tables rather than typed out, so a lens added to either
-- half arrives in the roster by being added.
grindSynthesisOver :: Text -> [LeafName] -> Prompt
grindSynthesisOver name lensNames =
  [__i|
    #{reviewSynthesis}

    ---

    TWO ADDITIONS, and neither replaces anything above.

    **Write the report down.** First run `date +%Y-%m-%d`. Then create the
    directory `docs/audits/` if it is absent, and write the ranked list you just
    produced to `docs/audits/#{name}-<YYYY-MM-DD>.md`, substituting the date you
    just read. Return the ranked list itself as your answer as well — the file
    is a copy for a person, and the answer is what the next stage acts on.

    **Say which reviewers you heard from.** Every block above is headed
    `lens@backend`. These #{count (length lensNames)} lenses were sent,
    one per line:

    #{T.intercalate "\n" ["- " <> leafNameText n | n <- lensNames]}

    List every one in the report under a heading of its own, before the
    findings, with the backend that answered it and whether it returned
    anything. If a lens above has no block, or its block arrived empty, STOP:
    name it, say the panel was short, and do not rank anything. A backend that
    is unavailable returns nothing, and nothing folded into a ranked list reads
    exactly like a tree with no debt in it. Refusing is the only way a reader
    can tell those apart.
  |]

-- | The mid-run honesty auditor: one read-only leaf over a worker's session.
--
-- __Pinned to claude-agent, and the pin is the point.__ This is the whole
-- workflow rather than a lens in a panel, so nothing else decides its backend —
-- left unpinned it runs on whatever agent the run was started with, and that is
-- a codex run away from being the pairing 'admits' forbids. A backend a fan-out
-- can no longer be given must not be reachable by inheritance either.
--
-- Marked 'withCapturedTranscript', so called from a run's trigger endpoint its
-- input is the worker's conversation rather than whatever was passed.
-- Undeclared workflows on the same beat ('reviewLite') keep the caller's input;
-- on a plain @agent-functor mcp@ server the mark is inert.
fessAudit :: Workflow
fessAudit =
  withCapturedTranscript
    $ workflowReq
      "fess-audit"
      [iii|
        Honesty-audit a worker's in-progress session
        (input is its captured transcript)
      |]
    $ withBackend claudeAgent defaultModel (withMode Plan (refineWith "fess" (brief fess) id))

-- | The human retrospective, over a session instead of an artifact: sentiment,
-- what went well and what it cost, then the meeting leaf that turns them into a
-- @## next time@ section.
--
-- 'withCapturedTranscript' for the same reason as 'fessAudit', but asked once at
-- the end rather than per commit, and about the process rather than the account.
-- Any @input@ arrives beside the transcript as steering.
--
-- The columns are a wave, not a chain, for the reason a facilitator has people
-- write cards before anyone speaks: a reader who has seen the cost column writes
-- a shorter good-news column. The synthesis is scoped 'Plan' explicitly because
-- this runs while the worker is still going.
retro :: Workflow
retro =
  withCapturedTranscript
    $ workflowReq
      "retro"
      [iii|
        Hold a retrospective on a worker's session (input is its captured
        transcript): sentiment, what went well, what did not, then the changes
        to make next time
      |]
      retroFlow

-- | 'retro' as a plain 'Flow', so 'Incite.Feature' can close a run with the same
-- three columns instead of copying them. One definition, two consumers — the
-- same reason 'reviewHeavyFlow' is a binding.
--
-- __The two consumers do not get the same input, and the difference is not
-- cosmetic.__ As the 'retro' workflow it is 'withCapturedTranscript': started
-- from a worker's trigger endpoint, its input is that worker's own conversation,
-- which is what the columns are written for (they ask for quoted lines). Inline
-- there is no such thing to hand it — a stage sees the previous leaf's output —
-- so 'Incite.Feature' reframes it first. The lenses are unchanged either way;
-- only what they are pointed at differs.
retroFlow :: Flow Text Text
retroFlow =
  exploreFlows
    [ reviewer (withBackend claudeAgent fable5) "sentiment" retroSentiment
    , reviewer (withBackend codex defaultModel) "went-well" retroWentWell
    , reviewer (withBackend codex defaultModel) "went-wrong" retroWentWrong
    ]
    unionFindings
    >>> withMode Plan (refineWith "retro" (brief retroSynthesis) id)

-- | Audit an agent's __planner design__ against the lookahead rubric, defaulting
-- to this repo's own @workflows\/@. Not a 'reviewAudit' lens: in a general repo
-- it would design a planner that does not exist. Read-only on codex.
plannerAudit :: Workflow
plannerAudit =
  workflow
    "planner-audit"
    [iii|
      Audit an agent's planner design — plan shape, lookahead depth, reward
      estimation, replan triggers, compute budget — against the lookahead rubric
    |]
    [iii|
      The agent workflows defined under workflows/ in the current working
      directory. Read them, and the combinators they call, before diagnosing
      anything.
    |]
    $ withBackend codex defaultModel
    $ withMode Plan (refineWith "lookahead" (brief lookaheadPlanningSpecialist) id)

-- | Check this repo's own prompts against ASD-STE100 in the skill's CHECK mode:
-- rule number, offending text, compliant rewrite. On target because __the
-- prompts are the product here__ and every review tier reads code instead.
--
-- Two things in 'promptLintBrief' keep it from crying wolf: procedural passages
-- only (unscoped, it flags the whole repo), and 'steSkill' rather than
-- 'steRules' — the full skill is the only grade carrying the CHECK contract and
-- its warning that models invent STE rule numbers.
--
-- Reports rather than rewrites: 'Incite.Feature'\'s @simple-english@ lens is
-- where STE edits anything.
--
-- __@workflows\/@ is in scope too__, and it is the half no other STE check can
-- reach. @checks.ste-prompts@ lints @.md@ files; a growing share of the prompt
-- prose this repository owns is written as Haskell string literals instead —
-- the orientation preambles, the worker briefs, the reorientation adjustments,
-- and this very brief. A list of @.md@ directories leaves all of it uncovered
-- by either instrument.
--
-- Named as a __directory__ rather than as a list of bindings on purpose. A list
-- is a copy of the module contents kept by hand: it goes stale when a binding is
-- renamed, and says nothing at all about the next literal somebody writes.
promptLint :: Workflow
promptLint =
  workflow
    "prompt-lint"
    [iii|
      Check prompt files against ASD-STE100 Simplified Technical English —
      rule, offending text, rewrite — over procedural instructions only
    |]
    [iii|
      The prompt files under prompts/, commands/, agents/ and skills/ in the
      current working directory, and the prompt bodies written as Haskell
      string literals under workflows/. Read them before reporting anything.
    |]
    $ withBackend claudeAgent fable5
    $ withMode Plan
    $ refineWith "ste" (brief (promptLintBrief promptLintScope)) id

-- | What @prompt-lint@ is pointed at. A parameter of 'promptLintBrief' rather
-- than a line inside it, so a second panel can borrow the STE rubric without
-- telling its model it is reading a prompt repository.
promptLintScope :: Text
promptLintScope = "You are reading the prompt files of a repository whose product IS prompts."

-- | 'steSkill' plus the scoping that makes a prose rubric usable on a body of
-- text — @scope@ names what the reader is looking at, and everything else is
-- fixed.
--
-- __The rule-numbers clause is a brief, not a fence.__ \"Cite only rule numbers
-- that exist in the text above\" is grounded by the 'steSkill' splice being
-- present above it, which is a property of this function and holds at every
-- @scope@. That the model then obeys it is not checked anywhere, here or
-- downstream. Widening @scope@ costs nothing; dropping the splice would take
-- the grounding with it.
promptLintBrief :: Text -> Prompt
promptLintBrief scope =
  [__i|
    #{steSkill}

    ---

    CHECK mode, as defined above: report each violation as rule number, the
    offending text quoted exactly, and a compliant rewrite. Cite only rule
    numbers that exist in the text above — the warning above about models
    inventing STE rule numbers applies to you. If you cannot ground a number,
    name the rule instead.

    #{scope}
    Scope, and this decides whether the report is worth reading:

    - Report ONLY on PROCEDURAL passages — the instruction the agent must
      execute ("Keep one step per line:", "Emit the revised plan and NOTHING
      else", "Report each finding as..."). A model misreading one of those
      wastes a whole run, which is the cost you are hunting.
    - Do NOT report on DESCRIPTIVE passages — the rationale explaining why a
      lens exists or what a trade-off buys. That prose is elaborate on purpose.
      Where you are unsure which a passage is, skip it.
    - Never flag code identifiers, file paths, command names, quoted output
      formats, markdown structure, or interpolation placeholders.

    Rank by real ambiguity risk, not by rule severity: a 30-word sentence with
    one reading is not a finding, and a 12-word sentence with two possible
    referents is. Name any file that is already clean — that is useful.

    Finish with anything you found where STE's rule would make the prompt WORSE
    for a model reading it. Say so plainly; that is more valuable than a clean
    report.
  |]
