{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.vibe-army;

  # Enumerate skills from the flake source at eval time (no IFD); the
  # actual files are linked from the built package so consumers can
  # override `package`.
  skillNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../skills)
  );

  mkHarnessOption =
    name: defaultDir:
    lib.mkOption {
      default = { };
      description = "Skill linking for ${name}.";
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "linking the skills into ${name}'s skill directory";
          directory = lib.mkOption {
            type = lib.types.str;
            default = defaultDir;
            description = "Skill directory, relative to the home directory.";
          };
        };
      };
    };

  enabledDirs = map (h: h.directory) (
    lib.filter (h: h.enable) [
      cfg.claude-code
      cfg.opencode
    ]
  );
in
{
  options.vibe-army = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vibe-army or (pkgs.callPackage ./package.nix { });
      defaultText = lib.literalExpression "pkgs.vibe-army";
      description = "Package providing share/vibe-army/skills.";
    };

    # opencode also discovers skills in ~/.claude/skills, so enabling
    # claude-code alone covers both harnesses.
    claude-code = mkHarnessOption "Claude Code" ".claude/skills";
    opencode = mkHarnessOption "opencode" ".config/opencode/skills";
  };

  config = {
    home.file = lib.listToAttrs (
      lib.concatMap (
        dir:
        map (name: {
          name = "${dir}/${name}";
          value.source = "${cfg.package}/share/vibe-army/skills/${name}";
        }) skillNames
      ) enabledDirs
    );
  };
}
