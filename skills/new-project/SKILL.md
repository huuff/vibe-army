---
name: new-project
description: Scaffold a new project with a Nix flake export, a standalone devenv shell, pre-commit hooks (secret scanning, static analysis, Conventional Commits), and a nono-sandboxed `claude` wrapper script. Use when the user asks to create, bootstrap, or scaffold a new project.
---

# New project scaffold

Creates a project that is simultaneously:

1. **A flake** — consumable from nix. It always exports *something* useful, but
   **what** depends on the project: a build (`packages.default` +
   `overlays.default`) only when the project actually produces a buildable
   artifact. For config-only projects (Terraform/OpenTofu, dotfiles, plain
   scripts, docs) a `packages.default` that just copies the files into the store
   is useless — export `nixosModules`/`homeManagerModules`/`lib`, dev tooling,
   or nothing at all instead. When unsure whether a package export makes sense,
   **ask the user**. See step 3.
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

First decide whether a `packages.default` even belongs here. Export a package
**only when the project produces a real buildable artifact** (a binary, a
library, a bundled app). For projects that are just config or files consumed by
some other tool — Terraform/OpenTofu, Ansible, k8s manifests, dotfiles, docs —
a derivation that copies those files into the nix store buys nothing; skip it
and use the "Pure nix config/modules" branch below (export modules/`lib`, or
just the devenv shell + hooks). If it's genuinely unclear which case you're in,
**ask the user before writing `nix/package.nix`** rather than defaulting to a
useless copy-to-store derivation.

When a package does make sense, replace the stub in `nix/package.nix` with the
right builder:

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
- Claude is launched with `--dangerously-skip-permissions`. This is the whole
  point of the sandbox: nono enforces access at the OS level, so Claude's own
  in-app permission prompts are redundant friction. The flag is safe *because*
  it runs inside nono, not in spite of it — never add it to an unsandboxed
  `claude`. It sits before the user's `...$args` so a caller can still override
  (e.g. a stricter `--permission-mode`).
- The sandbox never writes the caches host builds trust: the wrapper
  redirects `CARGO_HOME`, `XDG_CACHE_HOME` and `TMPDIR` into
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
- `TMPDIR` is redirected (not `/tmp` granted) on purpose. Claude Code writes
  its own scratch — task output, `/tmp/claude-$UID` — under `TMPDIR`, and the
  sandbox must be able to read it back, or every tool's stdout comes back
  "output unavailable". Pointing `TMPDIR` at the per-project cache fixes that
  with no new grant. Do **not** `--allow /tmp` to solve this: the host `/tmp`
  holds live IPC sockets that are *capabilities, not data* — X11
  (`/tmp/.X11-unix` → keylogging, screen capture, input injection),
  ssh-agent/gpg-agent sockets (sign auth challenges → lateral movement without
  ever reading a key) — plus it's a poisoning surface for other tools'
  predictably-named tempfiles. That re-opens exactly what the profile denies.
  nono has no private-tmpfs option, so redirection is the clean fix; if some
  subprocess hardcodes `/tmp`, grant a narrow subpath, never the whole dir.
- Threat model for grants: what matters is not what runs *inside* the
  sandbox but what processes *outside* it later trust. Whole `~/.cargo`
  is doubly bad (`~/.cargo/bin` is on PATH, `~/.cargo/config.toml` can
  set rustc wrappers), but even the narrow cache subdirs are unsafe, per
  the previous point. Apply the same test to any new grant: "could a
  write here change what runs outside the sandbox?"
- `/nix/var/nix/daemon-socket/socket` is allowed conditionally (multi-user
  nix only) so `nix build` inside the sandbox can reach the daemon.
- Playwright (e.g. Claude's playwright-cli skill) works inside the sandbox:
  `PLAYWRIGHT_BROWSERS_PATH` is pinned into the per-project cache, so
  browsers install and run without extra grants. Never point it at the
  host's `~/.cache/ms-playwright` — browser binaries are executables, and
  a swapped one would run unsandboxed the next time the *host* uses
  playwright. If per-project browser downloads (~400MB+) hurt, a shared
  `~/.cache/agent-sandbox/ms-playwright` for all sandboxes is the middle
  ground — it accepts that one instance could tamper with browsers another
  instance executes (inside its own sandbox).
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
- The `CARGO_HOME`/`XDG_CACHE_HOME` redirection relies on nono passing
  env vars into the sandbox (it does — it even injects credentials via
  env). The failure mode is loud, not silent: if the vars didn't
  propagate, cargo would hit the read-only `~/.cargo` and error. Still,
  sanity-check the first `cargo build` through the wrapper.

### Residual risks (accepted, know them)

- **`~/.claude` is shared r+w across ALL sandboxed instances** (profile
  grant; Claude can't function without its state dir). One instance could
  in principle tamper with state other sessions consume — the classic
  vector is `settings.json` hooks, which execute shell commands. Managing
  `settings.json` declaratively (home-manager/nix, read-only) closes that
  hole; transcripts and `~/.claude/local` (self-update) remain shared.
- **The project directory itself.** The agent can edit `devenv.nix`,
  `.envrc`, or anything that runs when *you* enter the shell, and
  artifacts it builds (`target/`, etc.) are attacker-controlled if the
  session was compromised. direnv's re-`allow` prompt after `.envrc`
  changes is a guard; reviewing diffs before re-entering the shell or
  running artifacts is the habit that matters. This is the irreducible
  trust boundary of any coding agent.
- **Outbound network is open by default**, so exfiltration of anything
  readable in the sandbox is possible in principle. For sensitive
  projects add `--block-net` or `--network-profile`/`--allow-domain`
  filtering to the wrapper.
- The nix daemon socket is safe by design — the daemon validates store
  writes — but it does let the sandbox realize arbitrary derivations
  (i.e. download and build things).
