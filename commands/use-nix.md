Listen up. When running tests, builds, or checks on this project, you need to favor `nix flake check` and `nix build` over dropping into `nix develop` and running commands manually.

Here's the deal:
- My local machine is a 16-core i9 — respectable, but not what we're working with here
- The Nix remote builder is a 105-core beast that eats builds for breakfast
- When you use `nix flake check` or `nix build`, the work gets distributed to the remote builder
- When you use `nix develop` and run tests locally, you're wasting time on my little machine

So unless there's a specific reason you need an interactive shell or local tooling, always reach for:
- `nix flake check` for running the full test suite and checks
- `nix build .#somePackage` for building specific outputs
- `nix build` for the default build

Only use `nix develop --command ...` when you absolutely need local tooling that isn't exposed through flake outputs.

$ARGUMENTS
