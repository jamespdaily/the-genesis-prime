---
name: writing-code
description: Sets this project's conventions for code - Gleam first, and Erlang, Elixir, Python, shell and PowerShell tools - covering reuse, modules, naming, comments, errors, types and the Gleam build. Use for any code change, written or reviewed.
---

# Writing code

## Reuse

- Before writing a helper, search the project's own code (`src/`, `dev/`, the test support modules, the scripts beside the one you change), the standard library (gleam_stdlib and OTP; Python's; the shell's tools) and the packages in use (the choosing-packages skill).
- A function two callers need moves to the module both share; never copy a module's glue or tests.

## Modules and files

Split for shared state and shared types, not for length alone.

- Name and split modules by game domain, not by kind (no `types`, `rules` or `utils`); keep modules out of a folder named for another package. Module names are singular, and all sit under the package's own directory.
- A type with rules of its own sits behind a small API, so other modules cannot build an invalid value. A feature with its own state, rules and effects gets its own module, even when one process runs it.
- Each feature module has its own effect type; a process's effect type wraps its features' effects, and its state holds one field per feature. A shell module sits beside its rule module (the designing-processes skill).
- Weigh a large module by its real cost: build time after a change, how much agents read, cross-topic bugs, branches editing one file.

## Naming

A name says what the thing does in the game; a client name needs evidence. One word means one thing.

- A client value, field, message or type with no evidence is named by its number.
- Names in full, no abbreviations; an acronym is one word; a unit suffix such as `_ms` is part of the name.
- An opcode is four hex digits (`0x037E`); a client code address is written in full.
- An id is named after the client table it keys: `spell4_id`, `spell4_base_id`.
- A game term is defined once, in its type's doc comment. No glossary file.
- When the client has a formula, use the client's.

## Comments

A comment describes the code as it stands, for a person reading it, and reads true without any other text.

- A public function or type has a doc comment saying what it does and why. An inline comment is for a line whose reason the doc comment cannot carry.
- A module's doc comment holds its purpose, one diagram of its flow, and one line per rule with its evidence. How each case behaves is a test named for that case, not a paragraph.
- Client evidence is cited after the plain sentence, as a pointer: a table, a row or a code address. The fact file holds the fact and its proof; the fact checker fails a cited address with no record.
- A module's doc comment is at most 40 lines and a function's or type's at most 10, a line past 100 columns counting as several; `test/code_rule/comment_size.gleam` enforces it, and its list (`comment_sizes.txt`) holds the longer blocks and can only shrink.
- A gap is stated as what the code does, and its module lists it for the coverage measure.
- Never: change-log words ("now", "no longer", "used to", "not yet", "for now", "so far"), plans, links to issues or pull requests, dates, comparisons with another codebase, or counts of this code (counts of the client's fixed data are fine).
- A script's docstring or header is its contract: what an operator runs, when, and what it refuses. Guidance points to it rather than repeating it.

## Errors

- A fallible function returns a `Result` with its module's own error type, whose variants say what went wrong; `Result(a, Nil)` is fine for one obvious failure.
- Each error maps to one client result, in one place. An outside failure is reported as the server's, not as the player's mistake.
- `let assert` and `panic` only where a crash is the intended result, each with a message.

## Gleam build

- `./check fast` runs `gleam format --check`, builds with warnings as errors, and runs glinter as configured under `[tools.glinter]` in `gleam.toml`. A rule turned off or a finding suppressed there carries its reason.
- Development tool config goes in `gleam.toml` under `[tools.<name>]`.

## Gleam types and data

- No catch-all `_` over a type that can gain variants in `src/` and `dev/` (`test/code_rule/catch_all.gleam`); a test may use `_` to pick one case.
- Decode every enum once at the edge (packet, row, table load) into a custom type with an `Other(id)` case, bit flags and states included.
- Make invalid states impossible: fields that belong together sit in one variant. A `Bool` stays for a yes-or-no function, an answer read by its field name, a guard, a table or packet flag passed on, or a codec primitive; it becomes a type naming its states when callers pass a bare `True` or `False` by position.
- None is `Option`, not 0, -1 or an empty string.
- Ids are typed (`Spell4Id(Int)`). A typed id costs about 5% of a hot path's time and 3 words per id held (issue #12), so a hot path may keep a plain `Int`; its module's doc comment says so, with that measurement.
