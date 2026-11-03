---
name: writing-gleam
description: Conventions for Gleam code - format, build, types, errors, module layout. Use for any Gleam change, written or reviewed, together with writing-code.
---

# Writing Gleam

Gleam code also follows the writing-code skill: reuse, module naming and splitting, naming, comments.

## Format and build

- `./check` runs `gleam format --check`, builds with warnings as errors, and runs glinter as configured under `[tools.glinter]` in `gleam.toml`: annotations on module functions, no `todo`, `echo`, `string.inspect`, `String` error or discarded `Result`, and functions called through their module. A rule turned off or a finding suppressed there carries its reason.
- Use `let assert` and `panic` where a crash is the intended result, each with a message.
- All modules sit under the package's own directory.
- Development tool config goes in the Gleam project file under `[tools.<name>]`.

## Types and data

- No catch-all `_` over a type that can gain variants (`test/code_rule/catch_all.gleam`).
- Decode every enum once at the edge (packet, row, table load) into a custom type with an `Other(id)` case, including bit flags and states.
- Make invalid states impossible: fields that belong together sit in one variant; a `Bool` stays for a yes-or-no function, an answer read by its field name, a guard, a table or packet flag passed on, or a codec primitive, and becomes a type that names its states when callers pass a bare `True` or `False` by position.
- A module guards its type's rules behind a small API; other modules cannot build an invalid value.
- None is `Option`, not 0, -1 or an empty string.
- Ids are typed (`Spell4Id(Int)`), so one id cannot pass as another. A typed id costs about 5% of a hot path's time and 3 words per id held (measured on issue #12), so a hot path may keep a plain `Int`; its module's doc comment names it as one, with that measurement.

## Errors

- A fallible function returns a `Result` with its module's own error type, whose variants say what went wrong. `Result(a, Nil)` is fine for one obvious failure.

## Modules

- Module names are singular.
- Each feature module has its own effect type; a process's effect type wraps its features' effects. A process's state holds one field per feature.
- A shell module sits beside its rule module (the designing-processes skill).
