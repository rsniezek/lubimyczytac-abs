{
  description = "Audiobookshelf custom metadata provider for lubimyczytac.pl";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        lubimyczytac-abs = pkgs.callPackage ./nix/package.nix { };
        default = lubimyczytac-abs;
      });

      nixosModules = {
        lubimyczytac-abs = ./nix/module.nix;
        default = ./nix/module.nix;
      };

      # `nix flake check` builds this, so a stale npmDepsHash fails CI rather
      # than only showing up on the next `nix build`.
      checks = forAllSystems (pkgs: {
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
