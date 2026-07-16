Let me be crystal clear about something.

Stop. Blaming. The. Infrastructure.

When something fails, it is NOT:
- The Nix cache being stale or corrupted
- The remote builder acting up
- Nix itself being flaky
- Missing dependencies that "should be there"
- Some phantom network issue
- A cache invalidation problem
- Nix flake lock being out of sync

The infrastructure is bulletproof. It has been tested. It works. Every single time.

When a build fails, when a test fails, when something doesn't compile — the problem is in OUR code. Period.

All dependencies are provided:
- If it's a dev shell, the dependencies are in `devShells` or `devShell`
- If it's a build, the dependencies are declared in the Nix derivation
- If something is "missing", that means WE forgot to add it, not that Nix forgot to provide it

So when you see an error, your FIRST instinct should be "what did we break?" not "maybe the cache is bad." Your SECOND instinct should also be "what did we break?" And your third.

The answer is always in the code. Find it.

$ARGUMENTS
