# Replace `_:` with `{ pkgs, ... }:` etc. when module args are first needed.
_:

{
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
  # `claude` on PATH that is not this wrapper itself (everything under
  # $DEVENV_PROFILE is skipped, otherwise the script would recurse).
  scripts.claude = {
    description = "Claude Code inside a nono sandbox";
    exec = ''
      real_claude=""
      while IFS= read -r candidate; do
        case "$candidate" in
          "$DEVENV_PROFILE"/*) continue ;; # this wrapper, via the profile
          /nix/store/*-claude/bin/claude) continue ;; # this wrapper, via its own store path
        esac
        real_claude="$candidate"
        break
      done < <(type -ap claude)
      if [ -z "$real_claude" ]; then
        echo "error: no claude found on PATH outside the devenv profile; install Claude Code system-wide" >&2
        exit 127
      fi

      extra=()
      if [ -S /nix/var/nix/daemon-socket/socket ]; then
        extra+=(--allow-file /nix/var/nix/daemon-socket/socket)
      fi
      exec nono run --profile claude-code \
        --allow-cwd \
        --allow "$HOME/.cargo" \
        --allow "$HOME/.cache/nix" \
        --allow "$HOME/.cache/devenv" \
        --allow "$HOME/.cache/pre-commit" \
        "''${extra[@]}" \
        -- "$real_claude" "$@"
    '';
  };

  enterTest = ''
    nono --version
    nix flake check --no-build
  '';
}
