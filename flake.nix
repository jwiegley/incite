{
  description = "Isaac's AI prompt configuration — skills, agents, and instructions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    agent-pm.url = "gitlab:fresheyeball/flake-prompt";
    agent-pm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, agent-pm }:
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
          mode = "subagent";
          model = "anthropic/claude-sonnet-4-20250514";
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
          model = "anthropic/claude-opus-4-20250514";
          extraFrontmatter = { temperature = 0.2; };
          body = builtins.readFile ./agents/compiler.md;
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

      ];

    in {
      lib.prompts = prompts;

      packages.${system}.default = agent-pm.lib.mkPromptsPackage pkgs {
        inherit prompts;
        tools.claude.enable = true;
      };
    };
}
