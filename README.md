# vibe-army

My repo for AI stuff: skills, agent configuration, and the scaffolding
conventions I want every agent-assisted project to follow.

Everything here is **harness-agnostic**: skills live in plain `skills/`, not
in any tool-specific dotfolder, so they work with Claude Code, opencode, or
whatever else comes along. `.claude/skills` is just a symlink into `skills/`
so Claude Code auto-discovers them.

## Layout

| Path | What |
|---|---|
| `skills/` | Agent skills, one directory per skill (`SKILL.md` + support files) |
| `skills/new-project/` | Scaffold a new project: flake export, standalone devenv, git hooks, sandboxed `claude`, sops secrets |
| `flake.nix` / `nix/` | Exports this repo as a nix package (`share/vibe-army/skills`) |
| `devenv.nix` | Dev shell for working on this repo, including the sandboxed `claude` wrapper |

## Usage

Enter the dev shell with `devenv shell` (or `direnv allow` once for automatic
activation). Inside it, `claude` runs Claude Code wrapped in a
[nono](https://nono.sh) sandbox — the agent gets this project directory, a
per-project cache, and not much else. The reasoning behind every grant is in
`skills/new-project/SKILL.md` under "design notes" and "Residual risks".

Consume the skills elsewhere via the flake:

```bash
nix build github:<owner>/vibe-army   # -> result/share/vibe-army/skills
```

Or let Home Manager link every skill into your harnesses:

```nix
{
  imports = [ vibe-army.homeManagerModules.default ];
  vibe-army.claude-code.enable = true;
  # opencode also reads ~/.claude/skills, so this is only needed
  # if you want ~/.config/opencode/skills populated independently:
  vibe-army.opencode.enable = true;
}
```

## Conventions

Commits follow [Conventional Commits](https://www.conventionalcommits.org)
(`feat:`, `fix:`, `chore:`, ...), enforced by a commit-msg hook. The
pre-commit hooks also scan for secrets (ripsecrets, detect-private-keys) and
lint nix and shell (nixfmt, statix, deadnix, shellcheck, shfmt). Hooks are
installed automatically when you enter the dev shell — don't bypass them
with `--no-verify`.

New projects should be started with the `new-project` skill so they share
these conventions from the first commit.
