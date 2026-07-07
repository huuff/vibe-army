# Add `lib` etc. to the lambda args when first needed (deadnix rejects
# unused args, statix rejects empty `{ ... }` patterns — use `_:` if no
# args remain).
{ pkgs, ... }:

{
  # Extra tools in the shell, on top of what `languages.*` bring in.
  packages = [
    # Uncomment if the app needs runtime secrets (see "Runtime secrets" in SKILL.md):
    # pkgs.sops
    # pkgs.age
  ];

  # CHANGEME: enable the project's language(s). Examples:
  # languages.rust.enable = true;
  # languages.python.enable = true;
  # languages.javascript = { enable = true; npm.enable = true; };
  # languages.go.enable = true;
  languages.nix.enable = true;

  git-hooks.hooks = {
    # --- secrets: never commit credentials ---
    ripsecrets.enable = true; # scans staged changes for API keys/tokens
    detect-private-keys.enable = true;

    # --- hygiene ---
    check-added-large-files.enable = true;
    check-merge-conflicts.enable = true;
    end-of-file-fixer.enable = true;
    trim-trailing-whitespace.enable = true;

    # --- static analysis: nix ---
    nixfmt-rfc-style.enable = true;
    statix.enable = true;
    deadnix.enable = true;

    # --- static analysis: shell ---
    shellcheck.enable = true;
    shfmt.enable = true;

    # --- commit messages: Conventional Commits (feat:, fix:, chore:, ...) ---
    commitizen.enable = true;

    # CHANGEME: language-specific analyzers/formatters, e.g.:
    # clippy.enable = true;          # rust
    # rustfmt.enable = true;
    # ruff.enable = true;            # python
    # ruff-format.enable = true;
    # eslint.enable = true;          # js/ts
    # golangci-lint.enable = true;   # go
    # gofmt.enable = true;
  };

  # `claude` inside this shell = Claude Code wrapped in a nono sandbox.
  #
  # The built-in `claude-code` nono profile already grants r+w to
  # ~/.claude*, read-only access to ~/.cargo, ~/.rustup, the nix store,
  # node/python runtimes and git config, and denies credentials, shell
  # history, keychains and browser data. On top of that we grant:
  #   - the project directory (profile sets workdir access to read+write)
  #   - caches that builds running inside the sandbox must write
  #   - the nix daemon socket, so `nix build` & friends work (multi-user nix)
  #
  # The wrapped binary is the system-installed Claude Code: the first
  # `claude` on PATH that is not this wrapper itself. The wrapper shows up
  # twice, via the devenv profile and via its own store path (a raw
  # /nix/store/*-claude/bin/claude never matches a real install — those sit
  # behind profile paths like /etc/profiles or ~/.local/bin).
  scripts.claude = {
    description = "Claude Code inside a nono sandbox";
    package = pkgs.nushell;
    exec = ''
      def --wrapped main [...args] {
        let real_claude = which --all claude
          | where type == "external"
          | get path
          | where {|p| not ($p | str starts-with $"($env.DEVENV_PROFILE)/") }
          | where {|p| $p !~ '^/nix/store/[^/]+-claude/bin/claude$' }
        if ($real_claude | is-empty) {
          error make { msg: "no claude found on PATH outside the devenv profile; install Claude Code system-wide" }
        }

        # Write grants for build caches only. Deliberately NOT all of
        # ~/.cargo: writable ~/.cargo/bin (on PATH) or ~/.cargo/config.toml
        # (rustc wrappers/runners) would let sandboxed code plant something
        # that later runs unsandboxed.
        let cache_grants = [
          $"($env.HOME)/.cargo/registry"
          $"($env.HOME)/.cargo/git"
          $"($env.HOME)/.cache/nix"
          $"($env.HOME)/.cache/devenv"
          $"($env.HOME)/.cache/pre-commit"
        ] | where {|p| $p | path exists } | each {|p| ["--allow" $p] } | flatten

        let socket = "/nix/var/nix/daemon-socket/socket"
        let socket_grant = if ($socket | path exists) { ["--allow-file" $socket] } else { [] }

        exec nono run --profile claude-code --allow-cwd ...$cache_grants ...$socket_grant -- ($real_claude | first) ...$args
      }
    '';
  };

  # Uncomment if the app needs runtime secrets: decrypts secrets/dev.yaml with
  # sops and execs the given command with the secrets as environment variables.
  # scripts.with-secrets = {
  #   description = "Run a command with sops-decrypted secrets in the env";
  #   exec = ''
  #     exec sops exec-env secrets/dev.yaml "$*"
  #   '';
  # };

  enterTest = ''
    nono --version
    nix flake check --no-build
  '';
}
