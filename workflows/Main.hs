-- | Isaac's local @agent-functor@ workflows: typed 'Flow' values, served as a
-- CLI and MCP tools by 'passMain'.
--
-- This module is deliberately only the __inventory__ — the list below is the
-- one place that decides what exists. Everything it names lives in a module of
-- its own:
--
-- * "Incite.Prompts" — every prompt body, and nothing else. Data, not logic.
-- * "Incite.Backend" — which model runs a leaf, and how a leaf is scoped to one.
-- * "Incite.Feature" — request → plan → the work it asks for: a pull request
--   for code, edited prose for documentation, or — where the request is a whole
--   tree rather than a change — an audit, a ranked report, and a fixer run
--   against it until a real build and test suite go green.
-- * "Incite.Review"  — the review and audit tiers.
--
-- Two conventions that hold across all of them. __Prompt bodies live on disk__:
-- @[promptFile|…|]@ is checked at compile time and read at run time, with paths
-- relative to the repo root (both the package root and the run-time cwd), so
-- editing the markdown needs no rebuild — and the path is unaffected by which
-- module the splice sits in. __Inline text uses the interpolation
-- quasiquoters__: @[__i|…|]@ keeps linebreaks and unindents only the literal
-- (interpolated markdown keeps its own indentation), @[iii|…|]@ collapses to one
-- line, @[i|…|]@ is verbatim. A 'Agent.Prompt.Prompt' hole splices the document
-- itself, not a 'Show' rendering of it.
module Main (main) where

import Agent.Run (Workflow, passMain)

import Incite.Feature (grindParadox, planFeature, shipDocs, shipFeature)
import Incite.Review (fessAudit, promptLint, retro, reviewAudit, reviewDocs, reviewHeavy, reviewLite)

main :: IO ()
main = passMain workflows

-- | The inventory. Adding a workflow is one line here plus its definition; a
-- workflow not in this list is not exposed as a subcommand or an MCP tool, no
-- matter how well defined it is.
--
-- Not listed, on purpose: "Incite.Review"'s @plannerAudit@.
workflows :: [Workflow]
workflows =
  [ planFeature
  , shipFeature
  , shipDocs
  , grindParadox
  , fessAudit
  , retro
  , reviewLite
  , reviewHeavy
  , reviewAudit
  , reviewDocs
  , promptLint
  ]
