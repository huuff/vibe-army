---
name: comments
description: Find and remove low-value comments — the kind LLMs tend to leave. Flags comments about what code DOESN'T do, restatements of the obvious, narration that just echoes the adjacent line, and multi-line instructional blocks masquerading as placeholders. Use when the user runs /comments, asks to clean up or review comments, or when an agent wants a bar for whether a comment it's about to write earns its place.
---

# Comments review

LLMs leave a lot of junk comments. This skill hunts them down. Two modes:
**review** existing comments (the usual case), or **advise** on whether a
comment being written is worth keeping.

## First: figure out the scope

Don't ask if you can infer it. Pick the narrowest scope that fits the
invocation:

1. **Uncommitted changes exist** (`git status` dirty) → review comments in the
   working diff only. This is the default and most common case: the user just
   made changes (often with an agent) and wants the cruft caught before commit.
   Use `git diff` (and `git diff --staged`) to see added/changed lines.
2. **On a feature branch, tree clean** → review comments introduced by the
   branch vs its base (`git diff <base>...HEAD`, base usually `main`).
3. **Explicit target** (a file, dir, or "the whole project" named) → review
   that.
4. **Invoked by an agent mid-task** to vet a comment it's about to write, or
   asked "how should I comment this?" → advise mode: apply the rules below to
   the proposed comment, don't go scanning the repo.

If genuinely ambiguous (e.g. clean tree, no branch, no target), ask once;
otherwise proceed on the inferred scope and say which one you picked.

Only judge comments **in scope**. When reviewing a diff, don't police
pre-existing comments on untouched lines — that's noise the user didn't ask for.

## What counts as a silly comment

Flag these:

- **Negative-space comments** — describing what the code does *not* do, or what
  was removed. Classic LLM residue from an edit: you ask it to drop something
  and it leaves `// no longer handles the retry case` or `// (removed caching)`.
  The code's job is to say what it does; absence needs no monument.
- **Obvious-to-a-practitioner comments** — explaining language/library/stdlib
  behaviour any competent reader already knows. `// increment i`,
  `// import the module`, `i++ // add one`, `// this is a for loop`,
  `// constructor`. Don't talk down to the reader.
- **Echo comments** — restating the line directly below in prose. `// set the
  user's name` above `user.name = name`, `// return the result` above
  `return result`. If the comment is just the code detokenized, it's dead
  weight.
- **Instruction-block comments** — multi-line comments narrating a plan or
  handoff: `// You now need to: 1. wire this up 2. add the handler 3. ...`.
  A short placeholder like `// TODO: handle timeout` or a bare `// FIXME` is
  fine; a paragraph of instructions is not.

## What to keep — don't be a zealot

The goal is signal, not zero comments. The best comment usually captures
**intent — the *why*** — rather than the *what*, especially for **imperative**
code, where the sequence of steps is already on the page but the reason for them
is not. The exception is **declarative** code (config, schemas, data,
rule/DSL definitions), where the "why" is often self-evident but the *what* — the
effect this declaration produces — can be worth stating. Judge a comment against
the grain of the code it sits on.

Leave comments that carry information the code cannot:

- **Why**, not what — rationale, trade-offs, the non-obvious reason a line
  exists (`// use a spinlock here; mutex adds 200ns we can't afford`).
- **Warnings & gotchas** — ordering constraints, off-by-one landmines, "this
  must stay in sync with X", workarounds for upstream bugs (with a link/ref).
- **Genuine intent** where the code is subtle or the domain is unusual.
- **Public API docs / docstrings** following the language's conventions, even
  if a given line reads as "obvious" — that's a different contract.
- **Legally/structurally required** headers, license blocks, directives
  (`// nolint`, `# type: ignore`, pragmas).

When unsure whether a comment is "why" vs "echo", read the code it sits on: if
deleting the comment loses nothing a reader couldn't recover in seconds, cut it.

## How to act

**Review mode:** collect the offenders in scope, then act by how the skill was
invoked:

- If the user wants them fixed (or `/comments` on a dirty tree — the implied
  intent is cleanup), remove/rewrite them directly with edits, grouped
  logically, and give a one-line summary per change. Rewrite when the comment
  gestured at something real but said it badly; delete when it adds nothing.
- If the user only asked to *review*, list findings as `file:line — quote —
  why it's noise (delete / rewrite to X)`, most egregious first, and let them
  decide.

Don't touch code behaviour. Comments only. If removing a comment reveals that
the code genuinely needs explaining, that's a signal to write a *better*
comment, not to keep the bad one.

**Advise mode:** answer whether the proposed comment earns its place against the
rules above. If it doesn't, say so and offer either "no comment" or a tighter
rewrite that captures the *why*.
