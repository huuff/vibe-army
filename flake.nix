{
  description = "Agent setup: skills, templates, and scaffolding for AI coding harnesses";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { };
      });

      overlays.default = final: _prev: {
        vibe-army = final.callPackage ./nix/package.nix { };
      };

      homeManagerModules.default =
        { pkgs, lib, ... }:
        {
          imports = [ ./nix/hm-module.nix ];
          vibe-army.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };

      checks = forAllSystems (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });
    };
}
