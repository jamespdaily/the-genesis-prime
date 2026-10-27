---
name: writing-gleam
description: Conventions for Gleam code - format, types, errors, modules, naming, comments. Use for any Gleam change, written or reviewed.
---

# Writing Gleam

## Format and build

- Code is formatted by `gleam format`; CI runs `gleam format --check`.
- Build with `--warnings-as-errors`.
- glinter runs on every check, configured in the Gleam project file. A rule is turned off or a finding suppressed only with a written reason.
- Every module function has type annotations on all arguments and its return type.
- Use `let assert` and `panic` only where a crash is the intended result, each with a message.
- No `todo`, `echo` or `string.inspect` in merged code.
- Call functions from other modules with the module name; import only types and constructors unqualified.
- All modules sit under the package's own directory.
- Development tool config goes in the Gleam project file under `[tools.<name>]`.

## Types and data

- No catch-all `_` over a type that can gain variants.
- Decode every enum once at the edge (packet, row, table load) into a custom type with an `Other(id)` case, including bit flags and states.
- Make invalid states impossible: fields that belong together sit in one variant; replace a `Bool` with a type that names its states.
- A module guards its type's rules behind a small API; other modules cannot build an invalid value.
- None is `Option`, never 0, -1 or an empty string.
- Ids are typed (`Spell4Id(Int)`), so one id cannot pass as another. A typed id costs about 5% of a hot path's time and 3 words per id held (measured on issue #12), so a hot path may keep a plain `Int`; its module's doc comment names it as one, with that measurement.
- When the client has a formula, use the client's.

## Errors

- A fallible function returns a `Result` with its module's own error type, whose variants say what went wrong. `Result(a, Nil)` is fine for one obvious failure. Never a `String` error; never a discarded `Error`.
- Each error variant maps to exactly one client result, in one place. An outside failure is never reported as the player's mistake.

## Modules

Length alone is never a reason to split; shared state and shared types are.

- Name and split modules by game domain. Never group by kind (no `types`, `rules` or `utils`), and no module in a folder named for another package.
- Split around a type with rules of its own, behind a small API. A feature with its own state, rules and effects gets its own module, even when one process runs it.
- Each feature module has its own effect type; a process's effect type wraps its features' effects. A process's state holds one field per feature.
- A shell module sits beside its rule module: the rule decides, the shell carries out (the designing-processes skill).
- Measure the real cost of a large module: build time after a change, how much agents read, cross-topic bugs, branches editing one file.

## Naming

A name says what the thing does in the game, and every client name is earned by evidence. One word means one thing.

- A client value, field, message or type with no evidence is named by its number.
- Write names in full, with no abbreviations. Module names are singular; acronyms are written as one word.
- An opcode is written as four hex digits (`0x037E`); a client code address in full.
- An id is named after the client table it keys: `spell4_id`, `spell4_base_id`.
- A game term is defined once, in the doc comment of its type. No glossary file.

## Comments

A comment describes the code as it stands, for a person reading it.

- Every public function and type has a doc comment that says what it does and why, in plain words. Inline comments only for a line whose reason the doc comment cannot carry.
- Client evidence is cited in a comment as a pointer, after the plain sentence: a table, a row or a code address. The fact file holds the fact and its proof, and the fact checker fails a cited address with no record.
- A gap is stated as what the code does. Change-log words ("now", "no longer", "used to", "not yet", "for now", "so far") and plans stay out.
- No links to issues, pull requests or decisions in code, and no dates, except a patch marker's link to its upstream bug.
- No comparisons with another codebase in code, and no counts of this code. Counts of the client's fixed data are fine.
