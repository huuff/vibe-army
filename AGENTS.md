# Agent instructions

## Skills are harness-agnostic

Skills live in `skills/`, one directory per skill (`SKILL.md` + support
files). **Never** create skills or other shared agent assets inside
`.claude/` or any other harness-specific folder — this repo serves multiple
harnesses (Claude Code, opencode, ...), so the plain `skills/` directory is
the single source of truth.

Harness-specific discovery is handled with symlinks pointing *into*
`skills/`, e.g. `.claude/skills -> ../skills`. Add a new symlink for a new
harness; don't copy files.
