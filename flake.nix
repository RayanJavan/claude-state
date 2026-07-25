{
  description = "Reproducible, snapshottable state management for an AI coding agent's environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f {
          inherit system;
          pkgs = nixpkgs.legacyPackages.${system};
        });

      manifest = import ./classification.nix;

      classifyFor = pkgs: import ./lib/classify.nix {
        inherit pkgs;
        classification = manifest;
      };

      cliFor = pkgs: import ./pkgs/claude-state {
        inherit pkgs;
        classify = classifyFor pkgs;
      };
    in
    {
      # The manifest itself, exposed so a consuming flake can inspect or extend
      # the classification without importing a private path.
      lib = {
        classification = manifest;
        inherit classifyFor;
      };

      packages = forAllSystems ({ pkgs, ... }: {
        claude-state = cliFor pkgs;
        classification = (classifyFor pkgs).out;
        default = cliFor pkgs;
      });

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = [
            (cliFor pkgs)
            pkgs.restic
            pkgs.jq
            pkgs.gh
            pkgs.shellcheck
          ];
          shellHook = ''
            echo "claude-state dev shell — run 'claude-state verify' to start"
          '';
        };
      });

      checks = forAllSystems ({ pkgs, ... }: import ./checks {
        inherit pkgs;
        classify = classifyFor pkgs;
        cli = cliFor pkgs;
      });
    };
}
