---
name: writing-code
description: Conventions for code in any language here - Gleam, Erlang, Elixir (for a tool or a package the package rule chose), Python, shell, PowerShell - reuse before writing, modules and files, naming, comments, errors. Use for any code change, written or reviewed; Gleam code also follows writing-gleam.
---

# Writing code

These hold in every language the project uses. Gleam's own conventions are in the writing-gleam skill.

## Reuse

- Before writing a helper, search the project's own code (`src/`, `dev/`, the test support modules and the scripts beside the one you change), the language's standard library (gleam_stdlib and OTP; Python's; the shell's tools) and the packages in use (the choosing-packages skill). A function two callers need moves to the module both share rather than being copied.
- Reuse what a module shares by importing it or moving it to a shared module; copying a module's glue and tests is what to avoid.

## Modules and files

Split for shared state and shared types, not for length alone.

- Name and split modules by game domain, not by kind (no `types`, `rules` or `utils`), and keep modules out of a folder named for another package.
- Split around a type with rules of its own, behind a small API. A feature with its own state, rules and effects gets its own module, even when one process runs it.
- Measure the real cost of a large module: build time after a change, how much agents read, cross-topic bugs, branches editing one file.

## Naming

A name says what the thing does in the game, and a client name needs evidence. One word means one thing.

- A client value, field, message or type with no evidence is named by its number.
- Write names in full, with no abbreviations. Acronyms are written as one word. A unit suffix such as `_ms` is part of a full name.
- An opcode is written as four hex digits (`0x037E`); a client code address in full.
- An id is named after the client table it keys: `spell4_id`, `spell4_base_id`.
- A game term is defined once, in the doc comment of its type. No glossary file.
- When the client has a formula, use the client's.

## Errors

- Each error maps to one client result, in one place. An outside failure is reported as the server's, not as the player's mistake.

## Comments

A comment describes the code as it stands, for a person reading it.

- A public function or type has a doc comment that says what it does and why, in plain words. An inline comment is for a line whose reason the doc comment cannot carry.
- A module's doc comment holds what the module is for, one diagram of its flow, and one line per rule with its evidence. How each case behaves is a test named for that case, not a paragraph; a paragraph a test's name already says is cut.
- Client evidence is cited in a comment as a pointer, after the plain sentence: a table, a row or a code address. The fact file holds the fact and its proof, and the fact checker fails a cited address with no record.
- A gap is stated as what the code does. Change-log words ("now", "no longer", "used to", "not yet", "for now", "so far") and plans stay out.
- No links to issues, pull requests or decisions in code, and no dates, except a patch marker's link to its upstream bug.
- No comparisons with another codebase in code, and no counts of this code. Counts of the client's fixed data are fine.
- A script's docstring or header is its contract: what an operator runs, when, and what it refuses. Guidance points to it rather than repeating it.
