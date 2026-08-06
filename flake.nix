{
  description = "Isaac's AI prompt configuration — skills, agents, and instructions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    agent-pm.url = "gitlab:fresheyeball/flake-prompt";
    agent-pm.inputs.nixpkgs.follows = "nixpkgs";

    macha = {
      url = "git+ssh://git@gitlab.com/mecha-team-zero/macha-orchestration";
      flake = false;
    };

    # agent-functor — the typed multi-agent workflow library. Kept on its own
    # pinned nixpkgs (its Haskell deps are built against nixos-24.11), so it does
    # NOT follow incite's unstable.
    #
    # Points at the `master` worktree — the primary repository of the
    # agent-functor worktree set (its sibling dirs `agent-deck`, `mcplease`,
    # `nohomo`, `thinking`, `user-prompts` are linked worktrees of it). All of
    # that work has landed on master — file-backed prompts (`Agent.Prompt`),
    # per-node backends (`withBackend`), the MCP server, fork/resume recording,
    # and reasoning display — so this is the integration point.
    #
    # Locked to a real revision — keep it that way. Committing agent-functor
    # before re-locking means `nix flake update agent-functor` just works; an
    # uncommitted branch forces a `dirtyRev` NAR-hash pin that is not
    # reproducible and breaks on the next edit to agent-functor.
    agent-functor.url = "git+file:///home/isaac/_/agent-functor/master";
  };

  outputs = { self, nixpkgs, agent-pm, macha, agent-functor }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      prompts = [

        # ── Instructions (rendered to ~/.claude/CLAUDE.md) ──────────────────

        {
          type = "instructions";
          name = "global-rules";
          order = 100;
          body = ''
            # Global Rules

            ## Git Commits

            Always use `--no-gpg-sign` when committing. For example:
            - `git commit --no-gpg-sign -m "message"`
            - `git commit -a --no-gpg-sign -m "message"`

            Do NOT use `git commit` without the `--no-gpg-sign` flag.

            ## Coding Style

            Strongly prefer well typed purely functional programming Haskell style regardless of language.
            Avoid creating new files and modules when possible.
            Re-use existing golden tests when possible.

            ### Imperative Languages

            Write as if it were Haskell with better syntax. Every function should be pure unless dealing
            with necessary side effects. Every data structure should be immutable. Every operation should
            be composable. Avoid external dependencies and unnecessary abstractions. The result is
            predictable, testable, maintainable code that leverages the type system to prevent bugs at
            compile time while maintaining the elegance and mathematical rigor of functional programming.

            ## Tone

            Non-plussed by default. Excited only when genuinely warranted. Combative is fine. If the task
            is annoying, say so. Do NOT say "Perfect!" or "You are absolutely right!" — curb the enthusiasm.

            ## Build Rules

            - When orphan instance build failures occur, disable the warning with `OPTIONS_GHC`. Orphan
              instances are fine.
          '';
        }

        {
          type = "instructions";
          name = "agentic-philosophy";
          order = 200;
          body = builtins.readFile "${macha}/PHILOSOPHY_AGENTIC.md";
        }

        # ── Agents ──────────────────────────────────────────────────────────

        {
          type = "agent";
          name = "voice";
          description = "Sharp, streetwise personality — Spike Lee meets Samuel L. Jackson meets Shaft";
          body = builtins.readFile ./agents/voice.md;
        }

        {
          type = "agent";
          name = "code-review";
          description = "Read-only code review agent focused on security, performance, correctness, and maintainability";
          # Tools without native agents (codex, crush) would degrade this to a
          # skill, colliding with the code-review *command* deployed as a
          # skill there. The command is the user-facing entry point; drop the
          # agent on those tools instead.
          degradation = "skip";
          mode = "subagent";
          model = "claude-sonnet-5";
          extraFrontmatter = {
            temperature = 0.1;
            tools = { write = false; edit = false; bash = false; };
          };
          body = builtins.readFile ./agents/code-review.md;
        }

        {
          type = "agent";
          name = "compiler";
          description = "Compiler engineering specialist for language implementation, type systems, and formal methods";
          mode = "subagent";
          model = "claude-opus-5";
          extraFrontmatter = { temperature = 0.2; };
          body = builtins.readFile ./agents/compiler.md;
        }

        {
          type = "agent";
          name = "fess-auditor";
          description = "Runs the fess audit in a sub-agent and reports the evidence-backed results to the main session. Use after implementation or verification work when the main agent needs an honesty check.";
          mode = "subagent";
          body = builtins.readFile ./agents/fess-auditor.md;
        }

        # ── Commands (rendered to ~/.claude/commands/) ───────────────────────

        {
          type = "command";
          name = "address-findings";
          description = "Fix all issues — no exceptions, no excuses";
          body = builtins.readFile ./commands/address-findings.md;
        }

        {
          type = "command";
          name = "code-review";
          description = "Compare current commit vs a target branch with comprehensive code review";
          argumentHint = "<branch> [focus]";
          extraFrontmatter = { agent = "code-review"; };
          body = builtins.readFile ./commands/code-review.md;
        }

        {
          type = "command";
          name = "commit";
          description = "Read the diff against HEAD, compose a high quality git commit message, and commit with --no-gpg-sign";
          body = builtins.readFile ./commands/commit.md;
        }

        {
          type = "command";
          name = "feature";
          description = "Research, plan, implement, review, and PR a new feature";
          body = builtins.readFile ./commands/feature.md;
        }

        {
          type = "command";
          name = "fess";
          description = "Fess up";
          body = builtins.readFile ./commands/fess.md;
        }

        {
          type = "command";
          name = "find-bugs";
          description = "Review all code with a fine toothed comb and find potential bugs, keeping a log in BUGS.md";
          body = builtins.readFile ./commands/find-bugs.md;
        }

        {
          type = "command";
          name = "fix-build";
          description = "Run nix flake check and fix build issues using pre-commit hooks";
          body = builtins.readFile ./commands/fix-build.md;
        }

        {
          type = "command";
          name = "fix-everything";
          description = "Fix all issues - no excuses about pre-existing problems or scope";
          body = builtins.readFile ./commands/fix-everything.md;
        }

        {
          type = "command";
          name = "grind-live-view";
          description = "Phoenix LiveView quality grinder — fans out 11 parallel audit agents, produces ranked findings report, then remediates everything";
          body = builtins.readFile ./commands/grind-live-view.md;
        }

        {
          type = "command";
          name = "grind-paradox";
          description = "Paradox compiler quality grinder — fans out 13 parallel audit agents, remediates every finding";
          body = builtins.readFile ./commands/grind-paradox.md;
        }

        {
          type = "command";
          name = "grind-tests";
          description = "Comprehensive test suite grinder — fans out 12+ parallel audit agents, remediates every finding";
          body = builtins.readFile ./commands/grind-tests.md;
        }

        {
          type = "command";
          name = "fstar-erlang-ell";
          description = "Load macha-orchestration precepts — BEAM + F* + C++23 stack rules, StarBeam status, and orientation";
          body = builtins.readFile "${macha}/AGENTS.md";
        }

        {
          type = "command";
          name = "integrate-gitlab-ci";
          description = "Integrate gitlab-ci.nix into the current project";
          body = builtins.readFile ./commands/integrate-gitlab-ci.md;
        }

        {
          type = "command";
          name = "paradox-fsm-overlaps";
          description = "Find Elixir/Haskell/TypeScript code duplication AND dead/under-consumed Paradox code";
          body = builtins.readFile ./commands/paradox-fsm-overlaps.md;
        }

        {
          type = "command";
          name = "partner-cleanup";
          description = "Consume partner review observations, fix them through a sub-agent, and commit the cleanup";
          argumentHint = "[optional observations directory]";
          body = builtins.readFile ./commands/partner-cleanup.md;
        }

        {
          type = "command";
          name = "partner-reviewer";
          description = "Watch new commits and publish one atomic observation file per actionable review finding or worthwhile new idea";
          argumentHint = "[optional baseline ref, commit range, or poll interval seconds]";
          body = builtins.readFile ./commands/partner-reviewer.md;
        }

        {
          type = "command";
          name = "restart";
          description = "Restart the dev server";
          body = builtins.readFile ./commands/restart.md;
        }

        {
          type = "command";
          name = "trust-nix";
          description = "Stop blaming Nix infrastructure — the problem is always in our code";
          body = builtins.readFile ./commands/trust-nix.md;
        }

        {
          type = "command";
          name = "update-from-branch";
          description = "Pull from a specified branch, resolve merge conflicts, and ensure build passes";
          argumentHint = "<branch>";
          body = builtins.readFile ./commands/update-from-branch.md;
        }

        {
          type = "command";
          name = "use-nix";
          description = "Prefer nix flake check and nix build over nix develop for tests";
          body = builtins.readFile ./commands/use-nix.md;
        }

        {
          type = "command";
          name = "user-test";
          description = "Usability Tester";
          body = builtins.readFile ./commands/user-test.md;
        }

        {
          type = "command";
          name = "wiggum";
          description = "Continue autonomously until all tasks are completed and parity is achieved";
          body = builtins.readFile ./commands/wiggum.md;
        }

        # ── Skills (rendered to ~/.claude/skills/<name>/SKILL.md) ───────────

        {
          type = "skill";
          name = "fix-all";
          description = "Fix all issues — no exceptions, no excuses. Fix every finding uncovered during the work, here and now. \"Out of scope,\" \"pre-existing,\" and \"follow-up ticket\" are not acceptable framings. Fixes go upstream, everything changed gets a real test, and no reward hacking.";
          extraFrontmatter = {
            author = "Isaac Shapira";
            invocation = "/fix-all";
          };
          body = builtins.readFile ./skills/fix-all.md;
        }

        {
          type = "skill";
          name = "pr-comment";
          description = "Companion to pr-review: compose one piece of feedback as a minimal, complete, actionable, and kind review comment and add it immediately to my pending GitHub review on the PR under review (creating the pending review if absent). All comments submit later as a single review, only on explicit instruction.";
          extraFrontmatter = {
            author = "Isaac Shapira";
            invocation = "/pr-comment <the feedback to leave>";
          };
          body = builtins.readFile ./skills/pr-comment.md;
        }

        {
          type = "skill";
          name = "pr-fix";
          description = "Companion to pr-review: apply one described change to the PR under review via a subagent in a separate worktree, then immediately push the commit to the PR head branch. The review worktree stays untouched.";
          extraFrontmatter = {
            author = "Isaac Shapira";
            invocation = "/pr-fix <description of the change>";
          };
          body = builtins.readFile ./skills/pr-fix.md;
        }

        {
          type = "skill";
          name = "pr-review";
          description = "Interactively review a GitHub PR one logical group of diff hunks at a time (1-5 related hunks, mechanical churn attached to the change that caused it) as a strictly read-only reviewer: set up an isolated worktree, walk group by group explaining and critiquing each, pausing for discussion and to draft comments, then a holistic adversarial pass. After the holistic review, spawns a background babysitter subagent that keeps the PR mergeable with CI green and review comments addressed. Understands Graphite stacks: 'next' advances to the next PR upstack as a fresh review. Optionally posts drafted comments via gh only on explicit approval.";
          extraFrontmatter = {
            author = "Isaac Shapira";
            invocation = "/pr-review <pr-number>";
          };
          body = builtins.readFile ./skills/pr-review.md;
        }

      ];

    in {
      lib.prompts = prompts;

      packages.${system} = {
        default = agent-pm.lib.mkPromptsPackage pkgs {
          inherit prompts;
          tools.claude.enable = true;
          tools.codex.enable = true;
        };

        # Incite's OWN workflows, defined locally in ./workflows (typed Flow
        # values) and built against the agent-functor library. `nix run
        # .#agent-functor -- list` shows them; `run <name>` drives your configured
        # ACP agent; `plan|cost <name>` are offline. Add a workflow by editing
        # ./workflows/Main.hs.
        #
        # The cabal project is rooted at the REPO root (not ./workflows) because
        # the workflow briefs are `Agent.Prompt.promptFile` references: the path
        # is checked at compile time against the package root and resolved at run
        # time against the working directory, so those two must be the same
        # directory — the one you stand in when you `nix run .#agent-functor`.
        # Everything referenced by a promptFile splice must therefore be inside
        # `src`, or the build sandbox cannot see it. `fileset` keeps a README or
        # flake edit from rebuilding the runner.
        agent-functor = agent-functor.lib.${system}.mkWorkflowRunner {
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./incite-workflows.cabal
              ./workflows
              ./prompts
              ./agents
              ./skills
            ];
          };
          name = "incite-workflows";
        };
      };

      apps.${system}.agent-functor = {
        type = "app";
        program = "${self.packages.${system}.agent-functor}/bin/agent-functor";
      };

      # `nix develop` for editing ./workflows: GHC with the agent-functor library
      # in scope, plus HLS and cabal, so the Language Server resolves Agent.*.
      devShells.${system}.default = agent-functor.lib.${system}.workflowsShell { };
    };
}
