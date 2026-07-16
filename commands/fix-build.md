Run `nix flake check -L` and observe any problems. If the errors come from formatting, then run `nix fmt -L` as it will automatically fix most formatting errors.

Avoid removing functionality and tests to make the build pass. Everything that is there now should be in a working state, not stubbed 'for now' to make the build pass. Repeat until the build passes.
