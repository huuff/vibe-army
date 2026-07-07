---
name: new-project
description: Scaffold a new project with a Nix flake export, a standalone devenv shell, pre-commit hooks (secret scanning, static analysis, Conventional Commits), and a nono-sandboxed `claude` wrapper script. Use when the user asks to create, bootstrap, or scaffold a new project.
---

# New project scaffold

Creates a project that is simultaneously:

1. **A flake** — consumable from nix (`packages.default`, `overlays.default`,
   optionally `nixosModules`/`homeManagerModules`).
2. **A devenv shell** — standalone (`devenv.yaml` + `devenv.nix` + `devenv.lock`),
   deliberately **not** via the flake's `devShells`. Rationale: the flake
   integration needs `--impure`, ties devenv to the flake's nixpkgs, and
   restricts devenv features (containers, `devenv up` processes, its own
   per-input lockfile). Keeping them side by side also keeps the flake minimal
   for consumers — dev tooling never leaks into the export.
3. **Guarded by git hooks** — secrets scanning, static analysis, and
   Conventional Commits enforcement, all managed declaratively through
   devenv's `git-hooks` module (installed automatically on shell entry).
4. **Agent-ready** — a `claude` script on the shell's PATH that runs Claude
   Code inside a [nono](https://nono.sh) sandbox using the built-in
   `claude-code` profile.
5. **Secrets via sops** — if the application needs secrets at runtime, they
   are provided with [sops](https://github.com/getsops/sops) (age-encrypted,
   committed to the repo), never as plaintext files or env vars in the shell
   config. See "Runtime secrets" below.

## Workflow

### 1. Gather parameters

Needed before writing anything:

- **Directory / project name** (kebab-case; used as `pname`).
- **One-line description**.
- **Language(s)** — infer from the user's request; if genuinely unknown, ask.

### 2. Copy templates

All templates live in `templates/` next to this file. Copy and rename:

| Template | Destination |
|---|---|
| `templates/flake.nix` | `flake.nix` |
| `templates/nix/package.nix` | `nix/package.nix` |
| `templates/devenv.yaml` | `devenv.yaml` |
| `templates/devenv.nix` | `devenv.nix` |
| `templates/envrc` | `.envrc` |
| `templates/gitignore` | `.gitignore` |

Then replace every `CHANGEME_PNAME` / `CHANGEME_DESCRIPTION` placeholder and
resolve the remaining `# CHANGEME` comments (language blocks, license).

### 3. Adapt to the language

In `devenv.nix`, enable `languages.<lang>` and the matching hooks:

| Language | devenv | extra git-hooks |
|---|---|---|
| Rust | `languages.rust.enable = true;` | `clippy`, `rustfmt` |
| Python | `languages.python.enable = true;` (+ `uv.enable`) | `ruff`, `ruff-format` |
| JS/TS | `languages.javascript = { enable = true; npm.enable = true; };` | `eslint`, `prettier` |
| Go | `languages.go.enable = true;` | `golangci-lint`, `gofmt` |
| Nix-only | `languages.nix.enable = true;` (already on) | already covered |

In `nix/package.nix`, replace the stub with the right builder:

- Rust: `rustPlatform.buildRustPackage { cargoLock.lockFile = ../Cargo.lock; ... }`
- Go: `buildGoModule { vendorHash = ...; ... }`
- Python: `python3Packages.buildPythonApplication { pyproject = true; ... }`
- Node: `buildNpmPackage { npmDepsHash = ...; ... }`
- Pure nix config/modules: drop `nix/package.nix`, export `nixosModules` /
  `homeManagerModules` / `lib` from the flake instead, and point
  `checks` at an eval test or leave only formatting checks.

The stub is intentionally buildable, so the scaffold passes `nix flake check`
before any real code exists.

### 4. Runtime secrets with sops (skip if the app needs none)

Secrets the application needs at runtime are managed with sops + age:
encrypted files are committed, the private key never enters the repo.

1. Uncomment `pkgs.sops` / `pkgs.age` in `devenv.nix` `packages`, and the
   `scripts.with-secrets` block.
2. Ensure the user has an age key (`~/.config/sops/age/keys.txt`); if not:
   `mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt`.
   Never write this key into the project.
3. Create `.sops.yaml` at the repo root with the public recipient
   (from `age-keygen -y ~/.config/sops/age/keys.txt`):

   ```yaml
   creation_rules:
     - path_regex: secrets/.*\.yaml$
       age: age1...publickey...
   ```

4. Create the encrypted file: `sops secrets/dev.yaml` (opens $EDITOR; write
   `KEY: value` pairs). The resulting file is encrypted — committing it is
   safe and expected. Do **not** gitignore `secrets/`.
5. Run the app as `with-secrets '<command>'` — it uses `sops exec-env`, so
   decrypted values exist only in that process's environment, never on disk.

For production/NixOS deployment of the same secrets, point the user at
[sops-nix](https://github.com/Mic92/sops-nix) (`sops.secrets.*` module
options); the encrypted files and `.sops.yaml` carry over unchanged.

Note: inside the nono sandbox the age key is NOT readable — the sandbox is
allowlist-based and `~/.config/sops` is not granted (verify with
`NONO_PROFILE=claude-code nono why --path ~/.config/sops/age/keys.txt --op read`).
This is by design: the agent can edit code that *consumes* secrets but cannot
decrypt them; the user runs `with-secrets` outside the sandbox.

### 5. Initialize and verify

```bash
git init -b main
devenv shell -- true        # builds the shell, writes devenv.lock, installs git hooks
nix flake check --no-build  # flake evaluates
devenv test                 # runs enterTest (nono present, flake evals)
git add -A
git commit -m "chore: scaffold project"   # must pass all hooks, incl. commitizen
```

Commit `devenv.lock` and `flake.lock`; `.pre-commit-config.yaml` and
`.devenv/` are generated and gitignored.

If any hook fails on the initial commit, fix the offending file — do not
bypass with `--no-verify`.

### 6. Hand over

Tell the user: enter with `devenv shell` (or `direnv allow` for automatic
activation), run Claude sandboxed with `claude` from inside the shell,
consume the project via `github:<owner>/<repo>` flake ref.

## Scripts: bash vs nushell

devenv `scripts.*` run with bash by default. Keep bash for trivial one-line
exec wrappers. When a script has real logic — filtering lists, parsing
JSON/structured output, more than a couple of conditionals — write it in
nushell instead; it will usually be clearer. The `claude` wrapper in the
template is the example: its PATH-filtering loop is a `which --all | where`
pipeline in nu instead of bash `while read` + `case` gymnastics.

```nix
scripts.my-script = {
  package = pkgs.nushell; # binary defaults to meta.mainProgram = "nu"
  exec = ''
    http get https://api.example.com/items | where size > 10mb | to md
  '';
};
```

Nushell-specific notes:

- A script that receives CLI arguments needs `def --wrapped main [...args]`;
  `--wrapped` stops nu from parsing flags meant for the wrapped command.
- Nu interpolation is `$"(...)"`, which doesn't collide with nix `''...''`
  strings — no `''${}` escaping needed, unlike bash.
- Nu `mkdir` already has `mkdir -p` semantics: creates parents, no error if
  the directory exists (there is no `-p` flag).

## The sandboxed `claude` script — design notes

Defined as `scripts.claude` in `devenv.nix` (written in nushell), so inside
the shell `claude` transparently means "Claude Code in a nono sandbox":

- `--profile claude-code` (built-in) grants r+w `~/.claude*`, read-only
  `~/.cargo`, `~/.rustup`, `/nix/store`, node/python runtimes, and git
  config; denies credentials, keychains, shell history/configs, and
  browser data. Workdir access level is read+write.
- `--allow-cwd` grants the project dir non-interactively.
- The sandbox never writes the caches host builds trust: the wrapper
  redirects `CARGO_HOME` and `XDG_CACHE_HOME` into
  `~/.cache/agent-sandbox/<project-slug>` (the only extra write grant).
  Sharing the real `~/.cargo` or `~/.cache` would be a poisoning vector —
  cargo does **not** re-verify extracted sources under `registry/src`
  (only `.crate` tarballs are checksummed), and nix trusts its eval
  cache — so a prompt-injected agent could plant code that runs in your
  later *unsandboxed* builds. The cache is keyed per project because
  sandboxes must not share caches with each other either: a compromised
  instance in project A could otherwise poison project B's builds through
  the common cache. Cost of the split: crates and eval caches are
  downloaded once per project for sandboxed use.
- Threat model for grants: what matters is not what runs *inside* the
  sandbox but what processes *outside* it later trust. Whole `~/.cargo`
  is doubly bad (`~/.cargo/bin` is on PATH, `~/.cargo/config.toml` can
  set rustc wrappers), but even the narrow cache subdirs are unsafe, per
  the previous point. Apply the same test to any new grant: "could a
  write here change what runs outside the sandbox?"
- `/nix/var/nix/daemon-socket/socket` is allowed conditionally (multi-user
  nix only) so `nix build` inside the sandbox can reach the daemon.
- The wrapped binary is the **system-installed** Claude Code: the script
  resolves the first `claude` on PATH that is not the wrapper itself
  (calling plain `claude` would recurse). Two candidates are skipped:
  anything under `$DEVENV_PROFILE`, and `/nix/store/*-claude/bin/claude` —
  devenv exposes each script as its own store path named after the script,
  and that raw store-path form never matches a real install (real ones sit
  behind profile paths like `/etc/profiles/...` or `~/.local/bin`). This
  keeps the user's own, self-updating install and avoids pinning the unfree
  `claude-code` nixpkgs package; it requires Claude Code to be installed
  outside the project.
- If a project needs more paths at runtime, discover them with
  `nono learn -- <command>` or explain denials with `nono why <path>`,
  then extend the script — prefer narrow `--read`/`--allow-file` grants
  over broad `--allow`.
