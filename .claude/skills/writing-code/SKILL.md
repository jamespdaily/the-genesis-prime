---
name: writing-code
description: Conventions for code in any language here - Gleam, Erlang, Python, shell, PowerShell - reuse before writing, modules and files, naming, comments, errors. Use for any code change, written or reviewed; Gleam code also follows writing-gleam.
---

# Writing code

These hold in every language the project uses. Gleam's own conventions are in the writing-gleam skill.

## Reuse

- Before writing a helper, search the project's own code (`src/`, `dev/`, the test support modules and the scripts beside the one you change), the language's standard library (gleam_stdlib and OTP; Python's; the shell's tools) and the packages in use (the choosing-packages skill). Never copy a function from another module or script: move it to the one both callers share.

## Modules and files

Length alone is never a reason to split; shared state and shared types are.

- Name and split modules by game domain. Never group by kind (no `types`, `rules` or `utils`), and no module in a folder named for another package.
- Split around a type with rules of its own, behind a small API. A feature with its own state, rules and effects gets its own module, even when one process runs it.
- Measure the real cost of a large module: build time after a change, how much agents read, cross-topic bugs, branches editing one file.

## Naming

A name says what the thing does in the game, and every client name is earned by evidence. One word means one thing.

- A client value, field, message or type with no evidence is named by its number.
- Write names in full, with no abbreviations. Acronyms are written as one word.
- An opcode is written as four hex digits (`0x037E`); a client code address in full.
- An id is named after the client table it keys: `spell4_id`, `spell4_base_id`.
- A game term is defined once, in the doc comment of its type. No glossary file.
- When the client has a formula, use the client's.

## Errors

- Each error maps to exactly one client result, in one place. An outside failure is never reported as the player's mistake.

## Comments

A comment describes the code as it stands, for a person reading it.

- Every public function and type has a doc comment that says what it does and why, in plain words. Inline comments only for a line whose reason the doc comment cannot carry.
- Client evidence is cited in a comment as a pointer, after the plain sentence: a table, a row or a code address. The fact file holds the fact and its proof, and the fact checker fails a cited address with no record.
- A gap is stated as what the code does. Change-log words ("now", "no longer", "used to", "not yet", "for now", "so far") and plans stay out.
- No links to issues, pull requests or decisions in code, and no dates, except a patch marker's link to its upstream bug.
- No comparisons with another codebase in code, and no counts of this code. Counts of the client's fixed data are fine.
