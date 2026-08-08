{
  description = "Isaac's AI prompt configuration — skills, agents, and instructions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-prompt.url = "gitlab:fresheyeball/flake-prompt";
    flake-prompt.inputs.nixpkgs.follows = "nixpkgs";

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

    # ponytail — the "lazy senior dev" prompt pack: a ladder (does this need to
    # exist → already here → stdlib → native → installed dep → one line → the
    # minimum) plus skills that apply it to a diff, a repo, and its own deferral
    # comments. Not a flake (no flake.nix), so `flake = false` and we read its
    # markdown directly, exactly like `macha`.
    ponytail = {
      url = "github:dietrichgebert/ponytail";
      flake = false;
    };

    # awesome-prompts — a ~3.5 MB grab bag of leaked and community system
    # prompts. We want exactly ONE file out of it: `prompts/agentic_coder.txt`,
    # the plan-first / read-before-editing / security-checklist / tests-are-not-
    # optional coding brief. Nothing else in the repo is referenced, and the
    # vendor check below is what keeps that true — the rest of the tree is
    # unaudited third-party text and must not leak into a prompt by accident.
    awesome-prompts = {
      url = "github:ai-boost/awesome-prompts";
      flake = false;
    };

    # promptdeploy — John Wiegley's prompt set (BSD 3-Clause, © 2025-2026 John
    # Wiegley). This repo's prompts descend from his, so it is pinned as the
    # __upstream to reconcile against__ rather than as a dependency: for every
    # prompt that exists in both, the local one wins unless there is a stated
    # reason it does not. See "Upstream prompts" in the README for the verdicts.
    #
    # It IS a real flake, and is deliberately taken as a plain source anyway:
    #
    #   * its `.gitmodules` points `translate-tool` at
    #     /Users/johnw/work/translation/translate-tool — an absolute path on the
    #     author's machine — while its flake sets `self.submodules = true`, so a
    #     submodule fetch from here cannot succeed. `flake = false` over a
    #     `github:` URL never looks at submodules, which sidesteps it entirely;
    #   * as a flake input it would drag its whole closure into our lock —
    #     nixpkgs, home-manager, flake-utils, and a SECOND ponytail pin beside
    #     ours;
    #   * we want its markdown and nothing else.
    #
    # Not adopted as a deployer. flake-prompt is a pure-Nix renderer producing a
    # package plus the `lib.prompts` inventory nixos-dots consumes; promptdeploy
    # is a stateful Python CLI with SHA-256 manifests and rsync-over-SSH. Swapping
    # loses the pure-Nix property for capabilities this repo does not need.
    #
    # Never pull in: host-tagged items (the `-- positron` / `-- personal`
    # filetags are his machines), anything depending on Anvil (his Emacs MCP) or
    # PAL consensus, and the persian/translate-tool material.
    promptdeploy = {
      url = "github:jwiegley/promptdeploy";
      flake = false;
    };

    # SimpleEnglish — ASD-STE100 Simplified Technical English as a skill (MIT,
    # © AminBlg): the aerospace controlled language, 53 rules, applied to
    # technical writing. We take `skills/simple-english/` and nothing else.
    simple-english = {
      url = "github:AminBlg/SimpleEnglish";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-prompt, macha, agent-functor, ponytail, awesome-prompts, promptdeploy, simple-english }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;

      # ponytail's markdown carries its own YAML frontmatter; flake-prompt renders
      # frontmatter itself from `name`/`description`, so passing the file through
      # verbatim would emit two `---` blocks. Keep the body only.
      #
      # Split on "\n---\n" rather than the first two lines: the opening fence has
      # no leading newline so it never matches, and rejoining the tail leaves any
      # `---` horizontal rule inside the body intact.
      stripFrontmatter =
        text:
        let
          parts = lib.splitString "\n---\n" text;
        in
        if lib.hasPrefix "---\n" text && builtins.length parts > 1 then
          lib.removePrefix "\n" (lib.concatStringsSep "\n---\n" (builtins.tail parts))
        else
          text;

      # A ponytail skill, rendered from the pinned input. The description is
      # written here rather than parsed out of the file's folded YAML scalar — a
      # YAML parser in Nix to recover four strings is precisely the kind of thing
      # ponytail exists to talk you out of. Bodies are never copied.
      ponytailSkill = name: description: {
        type = "skill";
        inherit name description;
        body = stripFrontmatter (builtins.readFile "${ponytail}/skills/${name}/SKILL.md");
      };

      # A promptdeploy sub-agent, rendered from the pinned input — same shape and
      # same reasoning as `ponytailSkill`, including the hand-written description.
      # These are the specialists the trimmed local `code-review` agent now defers
      # to rather than duplicating.
      promptdeployAgent = name: description: {
        type = "agent";
        inherit name description;
        mode = "subagent";
        extraFrontmatter = {
          tools = {
            write = false;
            edit = false;
          };
        };
        body = stripFrontmatter (builtins.readFile "${promptdeploy}/agents/${name}.md");
      };

      # Upstream briefs that `workflows/Main.hs` consumes, keyed by the path a
      # `promptFile` reference uses. NOTHING is copied into the repo: this is a
      # store path, `nix flake update ponytail` moves it, and a rebuild picks the
      # new one up with no file in git to re-sync and no chance of a stale copy.
      #
      # Also the allowlist for `awesome-prompts`: one named file out of a 3.5 MB
      # repo of unaudited third-party text, and nothing else can reach a prompt.
      #
      # The layout is rooted so that `$out` IS a prompt root — see
      # `AGENT_FUNCTOR_PROMPTS` on the runner below.
      #
      # __One name per capability, all the way down.__ A ponytail capability is
      # called the same thing at every layer it appears in:
      #
      #   upstream file            skill        prompt file    workflow / MCP tool
      #   skills/ponytail-review   ponytail-review   ponytail/review.md   ponytail-review
      #   skills/ponytail-audit    ponytail-audit    ponytail/audit.md    ponytail-audit
      #   AGENTS.md (the ladder)   ponytail         ponytail/ladder.md   — (a brief, not a flow)
      #
      # so `ponytail-audit` names the same thing whether you hit it as a skill in
      # a chat, a file on disk, or a tool over MCP. `workflows/Main.hs` carries
      # the same scheme into its identifiers.
      upstream = {
        "prompts/upstream/ponytail/ladder.md" = stripFrontmatter (
          builtins.readFile "${ponytail}/AGENTS.md"
        );
        "prompts/upstream/ponytail/review.md" = stripFrontmatter (
          builtins.readFile "${ponytail}/skills/ponytail-review/SKILL.md"
        );
        "prompts/upstream/ponytail/audit.md" = stripFrontmatter (
          builtins.readFile "${ponytail}/skills/ponytail-audit/SKILL.md"
        );
        # Verbatim, header and `<system_prompt>` tags included.
        "prompts/upstream/awesome-prompts/agentic-coder.md" =
          builtins.readFile "${awesome-prompts}/prompts/agentic_coder.txt";
        "prompts/upstream/awesome-prompts/lookahead-planning-specialist.md" =
          builtins.readFile "${awesome-prompts}/prompts/lookahead_planning_specialist.txt";
        "prompts/upstream/awesome-prompts/code-reviewer-security.md" =
          builtins.readFile "${awesome-prompts}/prompts/code_reviewer_security.txt";
        # The two documentation prompts `ship-docs` runs: a strategy rubric for
        # the plan, and a prose editor for the panel. Both are reoriented in
        # `Incite.Review` rather than used bare — see `docsStrategyOfPlan` and
        # `slopOfDocs` for what each one is pointed at instead.
        "prompts/upstream/awesome-prompts/technical-documentation-strategist.md" =
          builtins.readFile "${awesome-prompts}/prompts/Technical_Documentation_Strategist.txt";
        "prompts/upstream/awesome-prompts/stop-slop.md" =
          builtins.readFile "${awesome-prompts}/prompts/stop_slop.txt";
        # The fifth `review-lite` reviewer, reoriented to a commit by
        # `Incite.Review.qaOfCommit`.
        "prompts/upstream/awesome-prompts/qa-agent.md" =
          builtins.readFile "${awesome-prompts}/prompts/qa_agent.txt";
        # promptdeploy's per-language and cross-cutting reviewers, used as lenses
        # in `review-heavy`. Same files flake-prompt deploys as sub-agents below —
        # one copy, read twice, exactly like `agents/` and `skills/`.
        "prompts/upstream/promptdeploy/haskell-reviewer.md" = stripFrontmatter (
          builtins.readFile "${promptdeploy}/agents/haskell-reviewer.md"
        );
        "prompts/upstream/promptdeploy/perf-reviewer.md" = stripFrontmatter (
          builtins.readFile "${promptdeploy}/agents/perf-reviewer.md"
        );
        # SimpleEnglish at two grades, because the two uses want different
        # things. `rules.md` is upstream's condensed system-prompt form (2,947 B) —
        # enough to REWRITE a plan step, cheap enough for a lens that runs on
        # every plan. `skill.md` is the full 19.7 KB skill, which is what the
        # CHECK mode lives in ("report each violation as: rule number, the
        # offending text, a compliant rewrite", plus its own warning that models
        # invent STE rule numbers from memory) — that grounding is the whole
        # value for a linter, and worth the size on a workflow you run
        # deliberately. Same files flake-prompt deploys as the `simple-english`
        # skill below.
        "prompts/upstream/simple-english/rules.md" =
          builtins.readFile "${simple-english}/prompts/system-prompt.md";
        "prompts/upstream/simple-english/skill.md" = stripFrontmatter (
          builtins.readFile "${simple-english}/skills/simple-english/SKILL.md"
        );
      };

      # The prompt files `checks.ste-prompts` gates: exactly the ones the
      # workflows send to an agent. An allowlist, not a glob — a new prompt is
      # gated when someone adds it here, which is also when they decide it is
      # procedural.
      stePromptSrc = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.unions [
          ./prompts/plan.md
          ./prompts/plan-step.md
          ./prompts/plan-denotational.md
          ./prompts/plan-risk.md
          ./prompts/plan-verification.md
          ./prompts/explore
          ./prompts/review
          ./prompts/retro
          ./prompts/grind
          ./commands/fess.md
          ./commands/grind-paradox.md
          ./commands/post-commit-audit.md
          ./commands/wiggum.md
          ./skills/fix-all.md
          ./agents/code-review.md
          ./agents/haskell-review.md
        ];
      };

      # The gate itself. Loads upstream's linter as a module rather than parsing
      # its JSON, so a change to its output shape is a build error here instead
      # of a silently-passing check.
      steGate = pkgs.writeText "ste-gate.py" ''
        import importlib.util, pathlib, sys

        spec = importlib.util.spec_from_file_location("ste_lint", sys.argv[1])
        ste = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ste)

        # Only classes with no legitimate use in a prompt file. See the comment
        # on checks.ste-prompts for why the other counters are not gated.
        GATED = ["latin_abbrev", "contraction", "slop_word"]

        root = pathlib.Path(sys.argv[2])
        files = sorted(root.rglob("*.md"))
        if not files:
            sys.exit("ste-gate: no prompt files found under " + str(root))

        bad = []
        for path in files:
            counts = ste.lint(path.read_text(), "procedural")["violations"]
            for cls in GATED:
                if counts[cls]:
                    bad.append("  %s: %s x%d" % (path.relative_to(root), cls, counts[cls]))

        if bad:
            print("ste-gate: FAILED\n" + "\n".join(bad))
            print("\nThese three classes are gated at zero: " + ", ".join(GATED) + ".")
            sys.exit(1)

        print("ste-gate: %d prompt files clean on %s" % (len(files), ", ".join(GATED)))
      '';

      upstreamPrompts = pkgs.runCommand "upstream-prompts" { } (
        lib.concatStrings (
          lib.mapAttrsToList (path: text: ''
            install -Dm644 ${pkgs.writeText (baseNameOf path) text} $out/${path}
          '') upstream
        )
      );

      # The library-source inventory every Haskell consumer below needs: the
      # cabal file, the library modules, the four prompt/skill directories,
      # and the three commands read back as workflow briefs (named one by one
      # rather than taking ./commands wholesale, so adding a slash command
      # does not rebuild anything downstream of this), plus the
      # `prompts/upstream` graft so `promptFile` splices resolve at build
      # time. Defined ONCE here so `packages.agent-functor`'s runner,
      # `packages.haddock`, and `checks.unit-test` build on the same source
      # instead of each hand-writing the same 8-entry union — the runner and
      # `haddock` need nothing beyond this and use it directly; `unit-test`
      # extends it below with `./test` and `./docs/workflows.md`.
      librarySrc = pkgs.runCommand "incite-library-src" { } ''
        cp -r --no-preserve=mode,ownership ${
          pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./incite-workflows.cabal
              ./workflows
              ./prompts
              ./agents
              ./skills
              ./commands/fess.md
              ./commands/post-commit-audit.md
              ./commands/wiggum.md
            ];
          }
        } $out
        cp -r --no-preserve=mode,ownership ${upstreamPrompts}/prompts/upstream $out/prompts/upstream
      '';

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

        # The local half of the Haskell reviewer: what this codebase asks for
        # beyond `haskell-reviewer` below, plus the one place it overrules it
        # (orphan instances are fine here — see the global rules above).
        # Migrated out of `code-review` when that agent was narrowed to
        # AI-generated-code failure modes.
        {
          type = "agent";
          name = "haskell-review";
          description = "Local Haskell review addendum, to run alongside haskell-reviewer rather than instead of it: no bare primitive in a top-level signature, newtypes over type aliases for domain concepts, smart constructors with the raw constructor unexported, sum types where a String stands in for a closed set, RecordWildCards binding fields by their own names, DataKinds and GADT indices where they retire a runtime check, pure logic extracted out of IO, and totality and strict accumulation as absolutes. Overrules the upstream rubric on orphan instances, which are fine in this codebase.";
          mode = "subagent";
          extraFrontmatter = {
            tools = {
              write = false;
              edit = false;
            };
          };
          body = builtins.readFile ./agents/haskell-review.md;
        }

        # ── promptdeploy specialists (upstream, from the pinned input) ───────
        #
        # BSD 3-Clause, © 2025-2026 John Wiegley. Deployed as read-only
        # sub-agents; `haskell-reviewer` and `perf-reviewer` are also read as
        # `review-heavy` lenses out of the same files.

        (promptdeployAgent "haskell-reviewer" "Expert Haskell reviewer: partial functions, space leaks and strictness (foldl vs foldl', Writer, lazy State, unbanged accumulators), type safety, error handling, String vs Text, module structure. Use when reviewing Haskell changes; pair with haskell-review for this codebase's own rules.")

        (promptdeployAgent "nix-reviewer" "Expert Nix reviewer: flake and derivation hygiene, impurity, overlays, formatting and idiom. Use when reviewing .nix changes.")

        (promptdeployAgent "perf-reviewer" "Cross-language performance reviewer: algorithmic complexity, resource leaks, allocation in hot paths, I/O and concurrency bottlenecks, build overhead. Use for a performance pass over a changeset, after or alongside language-specific review.")

        (promptdeployAgent "security-reviewer" "Security reviewer for a changeset: trust boundaries, injection, secrets, authorization, unsafe execution. Use for a focused security pass; the review-heavy workflow runs an OWASP-structured lens over diffs separately.")

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
          name = "fess";
          description = "Fess up";
          body = builtins.readFile ./commands/fess.md;
        }

        # Read twice, like `fess` and `wiggum`: deployed as `/post-commit-audit`
        # AND read as the brief for `ship-feature`'s commit beat. `wiggum` defers
        # to it rather than restating the procedure, which is why it has to be
        # reachable as a command in an ordinary session and not just as a
        # workflow brief.
        {
          type = "command";
          name = "post-commit-audit";
          description = "Get the commit you just made independently checked: which checks to run, what to pass them, and how to poll. The single description of the post-commit beat — /wiggum and ship-feature's work loop both defer to it.";
          body = builtins.readFile ./commands/post-commit-audit.md;
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
          description = "Run nix flake check and fix build issues using nix fmt";
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
          description = "Paradox compiler quality grinder — launches the grind-paradox workflow: fourteen lenses over the whole tree, ranked report, remediation, and a real build/test gate";
          body = builtins.readFile ./commands/grind-paradox.md;
        }

        {
          type = "command";
          name = "grind-tests";
          description = "Comprehensive test suite grinder — fans out 12+ parallel audit agents, remediates every finding";
          body = builtins.readFile ./commands/grind-tests.md;
        }

        # Upstream, read straight from the pinned input like `fstar-erlang-ell`
        # below: no local copy to drift, and `nix flake update awesome-prompts`
        # is the whole update path. A command rather than an agent because a
        # vault is where the operator works, not a lens over a changeset —
        # nothing in the workflows reads it.
        {
          type = "command";
          name = "obsidian-vault";
          description = "Operate an Obsidian vault: Obsidian Flavored Markdown (wikilinks, embeds, callouts, properties), the Obsidian CLI, JSON Canvas, Bases queries, and Defuddle web extraction. Use for creating, editing, navigating, or restructuring notes in a vault rather than generic Markdown.";
          body = builtins.readFile "${awesome-prompts}/prompts/obsidian_vault_operator.txt";
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

        # ── ponytail (upstream, from the pinned flake input) ─────────────────
        #
        # Deployed as skills, not as an `instructions` fragment: the ladder as
        # always-on global context would apply to every session including the
        # ones that are not writing code, whereas ponytail's own descriptions are
        # written to trigger the model on coding work and nothing else. That is
        # its intended activation surface — keep it.
        #
        # `ponytail-gain` (a benchmark scoreboard) and `ponytail-help` (a card
        # listing the /commands we do not install) are deliberately not deployed.

        (ponytailSkill "ponytail" "Lazy senior dev mode. Climb the ladder before writing code — does this need to exist (YAGNI), is it already in this codebase, does the stdlib or a native platform feature cover it, is one line enough — and stop at the first rung that holds. Use on any coding task: writing, refactoring, fixing, reviewing, or picking a dependency, and whenever the user says \"be lazy\", \"yagni\", \"simplest solution\", or complains about bloat, boilerplate, or over-engineering. Never simplifies away validation, error handling, security, or accessibility."
        // {
          extraFrontmatter = {
            argument-hint = "[lite|full|ultra]";
            license = "MIT";
          };
        })

        (ponytailSkill "ponytail-review" "Review a diff for over-engineering only: what to delete, what the stdlib or platform already does, which abstraction has one implementation, which lines shrink. One line per finding, ending in a net line count. Complements a correctness review rather than replacing it; lists fixes, never applies them.")

        (ponytailSkill "ponytail-audit" "ponytail-review across the whole repository instead of a diff: a ranked list of what to delete, simplify, or replace with a stdlib or native equivalent. Use for \"audit this codebase for over-engineering\" or \"find the bloat\". One-shot report, applies nothing.")

        (ponytailSkill "ponytail-debt" "Harvest every `ponytail:` comment in the tree into a debt ledger, so the shortcuts ponytail deliberately marked with a ceiling and an upgrade path get tracked instead of rotting. One-shot report, changes nothing.")

        # ── SimpleEnglish (upstream, from the pinned input) ──────────────────
        #
        # Captured with `skillFromDir`, so its references/ (use-cases,
        # checklist) deploy beside SKILL.md. The description is declared here:
        # the upstream frontmatter is a `|` block scalar, which flake-prompt's
        # single-line YAML parser cannot read — same reasoning as ponytail's.
        (flake-prompt.lib.skillFromDir {
          dir = "${simple-english}/skills/simple-english";
          name = "simple-english";
          keepExtraFrontmatter = false;
          description = "Write or rewrite technical text with the rules of ASD-STE100 Simplified Technical English so it is clear, unambiguous, and free of AI slop. Use for documentation, READMEs, runbooks, procedures, error messages, release notes, incident reports, and API guides. Also use when the user says \"STE\", \"Simplified Technical English\", \"ASD-STE100\", \"de-slop\", \"make this readable\", \"write for non-native readers\", or asks for docs that translate well. Enforces the standard's 53 rules: 20/25-word sentence limits, one word one meaning, simple tenses, active voice, condition before command.";
          extraFrontmatter = { license = "MIT"; };
        })

      ];

    in {
      lib.prompts = prompts;

      packages.${system} = {
        default = flake-prompt.lib.mkPromptsPackage pkgs {
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
        # The upstream briefs are the one thing this src does NOT get from the
        # repo — `prompts/upstream/` is grafted in from `upstreamPrompts` so the
        # compile-time `promptFile` check can see it, and the wrapper below
        # points the run-time resolver at the same store path. So the pinned
        # revs are the only source of truth in both phases; there is no copy in
        # git, and `nix flake update ponytail` + rebuild is the whole update.
        agent-functor =
          let
            runner = agent-functor.lib.${system}.mkWorkflowRunner {
              # `librarySrc` (defined above, near `upstreamPrompts`) IS this
              # runner's source verbatim — no extras needed beyond the shared
              # inventory and its upstream graft.
              src = librarySrc;
              name = "incite-workflows";
            };
          in
          # `AGENT_FUNCTOR_PROMPTS` is the FIRST candidate a prompt reference
          # resolves through, then `$PWD`, then the (deleted) build directory.
          # Pointing it at a root that holds ONLY `prompts/upstream/**` is what
          # makes both halves work: the upstream briefs hit in the store, and
          # every repo-local brief misses there and falls through to the working
          # directory — so editing `prompts/plan.md` or `agents/code-review.md`
          # and re-running still takes effect with no rebuild.
          #
          # `--set-default`, so `AGENT_FUNCTOR_PROMPTS=… nix run` still wins.
          pkgs.symlinkJoin {
            name = "incite-workflows";
            paths = [ runner ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/agent-functor \
                --set-default AGENT_FUNCTOR_PROMPTS ${upstreamPrompts}
            '';
          };

        # Browsable Haddock for the library modules (`Incite.Prompts`,
        # `Incite.Backend`, `Incite.Feature`, `Incite.Review`) — the same
        # `afHpkgs.callCabal2nix` pattern `unit-test` below uses, pointed at
        # `librarySrc` (defined above) as-is: no `./test`, so `dontCheck`
        # needs nothing else to build; no new dependency, since GHC ships
        # haddock. `.doc` is the output `pkgs.haskell.lib` attaches the
        # generated HTML to, so `nix build .#haddock` puts it straight under
        # `result/`.
        haddock =
          (pkgs.haskell.lib.dontCheck (
            pkgs.haskell.lib.doHaddock (
              agent-functor.lib.${system}.afHpkgs.callCabal2nix "incite-workflows" librarySrc { }
            )
          )).doc;
      };

      apps.${system} = {
        agent-functor = {
          type = "app";
          program = "${self.packages.${system}.agent-functor}/bin/agent-functor";
        };

        # `nix run .#haddock-serve` — serve `packages.haddock`'s HTML on
        # localhost so `nix build .#haddock` is browsable without knowing its
        # store path. Finds `index.html` at run time rather than hardcoding
        # the `share/doc/…` layout, so a nixpkgs haddock-output-path change
        # does not silently break this — and fails loudly if the search comes
        # up empty rather than falling through: an unchecked `find | head
        # -n1` on a miss prints nothing, `dirname ""` evaluates to `.`, and
        # the script would silently serve the current directory instead.
        haddock-serve = {
          type = "app";
          program = "${pkgs.writeShellScript "haddock-serve" ''
            set -euo pipefail
            indexHtml=$(find ${self.packages.${system}.haddock} -name index.html | head -n1)
            if [ -z "$indexHtml" ]; then
              echo "haddock-serve: no index.html found under ${self.packages.${system}.haddock}" >&2
              exit 1
            fi
            dir=$(dirname "$indexHtml")
            echo "Serving Haddock at http://localhost:8000/ (Ctrl-C to stop)" >&2
            exec ${pkgs.python3}/bin/python3 -m http.server 8000 --directory "$dir"
          ''}";
        };
      };

      # The regression gate for the prompts, using __upstream's own__ linter
      # (`simple-english`'s `evals/ste_lint.py`) rather than a reimplementation.
      #
      # It exists because an ASD-STE100 pass over these files found 66 defects,
      # several of them expensive — an `e.g.` that turned a mandatory worktree
      # prefix into an example, so a `wg-*` cleanup grep passed on worktrees the
      # agent had named otherwise. This is the check that would have caught that
      # class, and it stops it coming back.
      #
      # __Honest scope.__ It gates exactly three classes, and only three:
      # `latin_abbrev`, `contraction` and `slop_word`. Those have no legitimate
      # use in these files, so the gate is a hard zero with no baseline to game.
      # Everything else the linter counts is deliberately NOT gated:
      #
      #   * `banned_modal` — \"would\" carries a real counterfactual here
      #     (\"what would still pass if the code were wrong\" IS the tests lens),
      #     so a zero would force the lens to be rewritten wrong;
      #   * `sentence_over_limit`, `semicolon` — the rationale prose in these
      #     files is descriptive, deliberately long, and not a defect. The
      #     linter cannot tell procedural from descriptive WITHIN a file; that
      #     judgement is what the `prompt-lint` workflow is for.
      #
      # So this catches the mechanical half and says so. It cannot catch an
      # ambiguous pronoun or a garden-path sentence — no regex can, and the
      # linter's own docstring says as much.
      checks.${system} = {
        ste-prompts =
          pkgs.runCommand "ste-prompts-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            # Prove the linter before trusting it — upstream ships its own fixture
            # pair (a slop paragraph and a clean one) and asserts both directions.
            python3 ${simple-english}/evals/ste_lint.py --self-test
            python3 ${steGate} ${simple-english}/evals/ste_lint.py ${stePromptSrc}
            touch $out
          '';

        # The unit test suite for the pure workflow logic: `decideContinue` and
        # `continueMarker` (the orchestrator loop's continuation contract, from
        # both sides — the decorations that are read through and the ones that
        # are not), `orient` with `preambleOf`/`preambleViolations` and the three
        # named reframings (their bytes recorded under `test/golden/`),
        # `document`'s worker brief, `lensesOf` with `lensSetViolations` (review
        # panel composition per `Subject`, names AND bodies), the reorientation
        # deltas against the upstream rubrics they splice, `promptLint`'s shipped
        # leaf text, the `extra-source-files` cover, and backend structure.
        #
        # `test/golden/` is read with `TIO.readFile` relative to the package
        # root, which is why `./test` is copied whole below rather than as
        # `./test/Spec.hs`. Built with
        # `afHpkgs` (agent-functor's pinned nixpkgs) so the `agent-functor`
        # library dependency resolves correctly; `callCabal2nix` defaults to
        # `doCheck = true`, which runs the test-suite's `cabal test` phase.
        unit-test =
          let
            # `librarySrc` (defined above) plus the extras this suite alone
            # needs: `./test` itself, and every document it reads at run time
            # with `TIO.readFile`. `./docs` is the docs-inventory fence's
            # `workflows.md` plus the manuals the renderer-name fence reads;
            # `./README.md` and `./AGENTS.md` are that same fence's. These are
            # the `extra-source-files` entries beside the goldens, and for the
            # same reason: a file read at run time is checked by nothing at
            # compile time, so dropping one here builds clean and then fails
            # the suite with `openFile: does not exist`.
            #
            # `./flake.nix` is deliberately absent. It declares the input, so a
            # stale renderer name in it is an evaluation error rather than
            # documentation drift, and copying it in would rebuild this suite
            # on every comment edit to it.
            testSrc = pkgs.runCommand "incite-test-src" { } ''
              cp -r --no-preserve=mode,ownership ${librarySrc} $out
              cp -r --no-preserve=mode,ownership ${
                pkgs.lib.fileset.toSource {
                  root = ./.;
                  fileset = pkgs.lib.fileset.unions [
                    ./test
                    ./docs
                    ./README.md
                    ./AGENTS.md
                  ];
                }
              }/. $out/
            '';
          in
          agent-functor.lib.${system}.afHpkgs.callCabal2nix "incite-workflows-test" testSrc { };
      };

      # `nix develop` for editing ./workflows: GHC with the agent-functor library
      # in scope, plus HLS and cabal, so the Language Server resolves Agent.*.
      #
      # The shellHook re-points `prompts/upstream` at the current store path.
      # Under `nix build` that directory is grafted into `src`; under a plain
      # `cabal build` there is no graft, and `promptFile`'s compile-time
      # `doesFileExist` would fail — so the symlink is what keeps cabal and HLS
      # agreeing with nix. It is a symlink to /nix/store and gitignored: not a
      # copy, nothing to keep in sync, and it moves on its own after a
      # `nix flake update ponytail`.
      devShells.${system}.default = (agent-functor.lib.${system}.workflowsShell {
        extra = hp: [ hp.tasty hp.tasty-hunit ];
      }).overrideAttrs (old: {
        # Guarded on the .cabal file: `nix develop /path/to/incite` from another
        # directory is a normal thing to do, and an unguarded `ln` there fails
        # (no ./prompts to put it in) and dirties the shell with an error.
        shellHook = (old.shellHook or "") + ''
          if [ -f incite-workflows.cabal ]; then
            ln -sfn ${upstreamPrompts}/prompts/upstream prompts/upstream
          fi
        '';
      });
    };
}
