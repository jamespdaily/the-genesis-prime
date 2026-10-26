---
name: writing-gleam
description: Conventions for Gleam code - format, types, errors, modules, naming, comments, packages, migrations. Use for any Gleam change, written or reviewed.
---

# Writing Gleam

Apply every section to each change, and check the diff against each before it is done.

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
- Ids are typed (`Spell4Id(Int)`), so one id cannot pass as another. A typed id costs about 5% of a hot path's time and 3 words per id held (`dev/genesis_prime/id_cost.gleam`), so a hot path may keep a plain `Int`; its module's doc comment names it as one, with that measurement.
- When the client has a formula, use the client's.

## Errors

- A fallible function returns a `Result` with its module's own error type, whose variants say what went wrong. `Result(a, Nil)` is fine for one obvious failure. Never a `String` error; never a discarded `Error`.
- Each error variant maps to exactly one client result, in one place. An outside failure is never reported as the player's mistake.

## Modules

Length alone is never a reason to split; shared state and shared types are.

- Name and split modules by game domain. Never group by kind (no `types`, `rules` or `utils`), and no module in a folder named for another package.
- Split around a type with rules of its own, behind a small API. A feature with its own state, rules and effects gets its own module, even when one process runs it.
- Each feature module has its own effect type; a process's effect type wraps its features' effects. A process's state holds one field per feature.
- A process module sits beside its pure rule module: the rule decides, the process carries out.
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
- Client evidence stays in comments: a table, a row or a code address, after the plain sentence.
- A gap is stated as what the code does. Change-log words ("now", "no longer", "used to", "not yet", "for now", "so far") and plans stay out.
- No links to issues, pull requests or decisions in code, and no dates, except a patch marker's link to its upstream bug.
- No comparisons with another codebase in code, and no counts of this code. Counts of the client's fixed data are fine.

## Packages

Take the first step that does the job. A lower step wins only when it meets a need the higher one cannot, and its doc comment names that need.

1. OTP and Gleam's core packages: a process, a supervisor, a monitor, a timed message, a persistent term, an ETS table.
2. A Gleam package from Hex.
3. An Erlang package, through one helper file, with a Gleam type for every value.
4. Our own Gleam code.
5. Rust.

- Use the core libraries first (`gleam_stdlib`, `gleam_time`, `gleam_json`, `gleam_http`, `gleam_erlang`, `gleam_otp`). Search `gleam_stdlib` before writing any helper.
- Before adding a package: read its source, check its releases, maintainers, dependencies, licence, Erlang support and native code, and try it in a scratch project. Save its docs on disk once added.
- A broken package is patched in place, each patch marked with its upstream bug, never rewritten.
- Erlang externals only for runtime APIs Gleam lacks, each with an exact Gleam type, never `Dynamic`.
- A package with native code counts as Rust.
- An Elixir package needs a named reason.

## Migrations

- Change the schema only with numbered migration files in the repository. Never edit a migration that has run outside a developer's machine.
