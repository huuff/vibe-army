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
    nixfmt.enable = true; # RFC 166 style; nixfmt >= 1.0 (nixfmt-rfc-style is the deprecated alias)
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
  #   - a sandbox-only cache dir; CARGO_HOME/XDG_CACHE_HOME are redirected
  #     there so the sandbox never writes caches that host builds trust
  #   - the nix daemon socket, so `nix build` & friends work (multi-user nix)
  #
  # Claude runs with --dangerously-skip-permissions: nono is the real
  # enforcement boundary, so Claude's in-app prompts add nothing but friction.
  # The flag is safe *because* of the sandbox, not in spite of it.
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

        # The sandbox gets its own caches, never the ones host builds
        # trust: cargo does not re-verify extracted sources under
        # registry/src, and nix trusts its eval cache, so a write grant on
        # the shared ~/.cargo or ~/.cache would let sandboxed code poison
        # later unsandboxed builds. The cache is keyed per project so one
        # sandboxed instance cannot poison another project's builds either;
        # the grant covers only this project's subdirectory.
        let slug = $env.PWD | str replace --all "/" "-" | str trim --char "-"
        let cache = $"($env.HOME)/.cache/agent-sandbox/($slug)"
        mkdir $"($cache)/cargo" $"($cache)/xdg"
        $env.CARGO_HOME = $"($cache)/cargo"
        $env.XDG_CACHE_HOME = $"($cache)/xdg"
        # Redirect TMPDIR into the per-project cache too, so Claude's own
        # scratch (task output, /tmp/claude-$UID) lands somewhere the sandbox
        # can read. We deliberately do NOT grant the host's /tmp: it holds live
        # IPC sockets (X11, ssh-agent, gpg-agent) that are capabilities, not
        # data, and is a poisoning surface for unsandboxed tools' tempfiles.
        mkdir $"($cache)/tmp"
        $env.TMPDIR = $"($cache)/tmp"
        # Playwright browsers are executables too — same poisoning rules.
        # Pinned explicitly so it doesn't depend on playwright's XDG handling.
        $env.PLAYWRIGHT_BROWSERS_PATH = $"($cache)/ms-playwright"

        let socket = "/nix/var/nix/daemon-socket/socket"
        let socket_grant = if ($socket | path exists) { ["--allow-file" $socket] } else { [] }

        # nono is the enforcement boundary, so Claude's own in-app permission
        # prompts are redundant friction: skip them and let the agent run
        # autonomously inside the sandbox. Put it before ...$args so the user
        # can still override (e.g. pass a stricter --permission-mode).
        exec nono run --profile claude-code --allow-cwd --allow $cache ...$socket_grant -- ($real_claude | first) --dangerously-skip-permissions ...$args
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
