---
name: writing-gleam
description: How to write Gleam in the-genesis-prime - Gleam's own conventions, choosing OTP, a package, our own code or Rust, adding and patching packages, types and data, naming, modules, comments, errors, Erlang helpers, what the check holds, and the checklist for reviewing a diff, with the traps of the runtime and our packages as a reference. Use whenever writing, changing or reviewing a .gleam file, an Erlang helper (.erl), a squirrel .sql query or gleam.toml, even for a one-line change.
---

# Writing Gleam

## Read the docs on disk

Gleam 1.19's docs and the docs of our packages are saved as text in `~/Projects/reference/gleam-1.19/text/`:

- `site/tour_everything.md`: the whole language tour.
- `site/documentation_conventions-patterns-and-anti-patterns.md`: Gleam's conventions page, the source of most rules below.
- `site/documentation_externals.md`: Erlang helpers.
- `packages/<name>-<version>/`: each package's module docs, such as `gleam_otp-1.3.0/gleam/otp/actor.md`.

Read the page before using a function you have not used in this session. Never guess a signature. A package missing from the folder is added there first, with `scripts/hexdocs_to_text.py`; its docstring gives the commands. Hex docs unpack with no read permission: run `chmod -R u+rwX,go+rX` on the extracted folder before converting it.

The traps of the runtime and of our packages (glisten, pgo and pog, squirrel, generated code, glinter, scripted edits) are in [references/traps.md](references/traps.md). Read the section for what you touch.

## Gleam's conventions

- Annotate every function's arguments and return type.
- Call other modules' functions and constants qualified. Types and record constructors may be imported unqualified.
- Name modules in the singular, and write acronyms as words: `Json`, not `JSON`. Write every name in full, with no abbreviations.
- Name conversions `x_to_y`, leaving out the type's name when the module already says it.
- Name a function that returns a `Result` for the job it does, such as `parse_json`. Use the `try_` prefix only for a result version of an existing function, such as `try_map` beside `map`.
- Use the core packages' types, such as `gleam_time`'s `Timestamp`, instead of making new ones.
- Put tool settings in `gleam.toml` under `tools.<name>`. `src/` holds the server, `test/` the tests, `dev/` the generators and scripts. Every module sits under `src/genesis_prime/`.
- Build a record with many optional fields through a builder: `new` with the required fields, then functions that set the rest.
- Never check a value and then assert it. Match on it, or use `result.try`.
- `panic`, and a `let assert` whose match can fail, appear only inside a process's message handler, which catches the error as the designing-processes skill says. A `let assert` whose match can never fail may go anywhere, with an `as` message saying why it holds. `main` may `let assert` to stop when start-up fails.
- Write concrete functions, never abstractions from category theory.

## Choosing what to build on

Take the first step that does the job. A lower step wins only when it meets a need the higher one cannot, and the doc comment of what you build names that need.

1. OTP and Gleam's core packages: a process, a supervisor, a monitor, a timed message, a persistent term, an ETS table.
2. A Gleam package from Hex.
3. An Erlang package, through the one helper file, with a Gleam type for every value.
4. Our own Gleam code.
5. Rust, only with the four numbers `CLAUDE.md` names.

- **Use the core libraries first, and never rebuild what they hold:** gleam_stdlib, gleam_time, gleam_json, gleam_http, gleam_erlang, gleam_otp. Search gleam_stdlib before writing any helper.
- **Before adding a package,** read its source, not only its README. Check its releases and maintainers, how many packages it pulls in, its licence, that it runs on Erlang with our core library versions, and whether it carries native code. Try it on our case in a scratch project. Once added, save its docs on disk. One test runner pulled in six more packages; a Postgres driver needed three patches to survive an outage.
- **A broken package is patched in place, never rewritten.** Its copy lives in `vendor/`, and each patch is marked with a comment linking its upstream bug, so the copy can go back to Hex once a release fixes it.
- **A package with native code counts as Rust.** A crash in native code takes down the whole runtime (Erlang's NIF docs).
- **An Elixir package needs a named reason** on the issue: what it does that no Gleam or Erlang package does. It needs Elixir installed, and its nils and structs reach Gleam untyped.

### Erlang helpers

- They live in one file, `src/genesis_prime_ffi.erl`, and hold only what no package does.
- Each value that crosses into Erlang gets its own Gleam type, never `Dynamic`.
- Each helper has its own test, unless its callers' tests reach every path of it.

## Types and data

- **Decode every enum once at the edge** (the packet, the row, the table load) into a custom type with an `Other(id)` case, bit flags and states included. Raw flags re-tested with masks spread through three modules before.
- **A value with no evidence keeps its number, as `Other(id)`.** Never invent a name: an honest unknown beats a guessed name.
- **A number that keys a large game table stays a number,** not a custom type. A faction keys the 1,189-row Faction2 table, so a type would put almost every value in `Other`. Its 0 for "none" still becomes an `Option`.
- **Make invalid states impossible.** Fields that belong together sit in one variant. Two fields that each pick a state become one type: a cast method (7 values) and a status (6) as separate fields allowed impossible pairs.
- **Replace a `Bool` with a type that names its states:** `role: Role` with `Student` and `Teacher`, not `is_student: Bool`; `send(message, Whisper)`, not `send(message, True)`. A function that answers a yes-or-no question, such as `is_dead`, still returns `Bool`, as do a guard's condition, a packet flag passed straight on and a codec primitive.
- **A module guards its type's rules behind a small API.** Other modules cannot build an invalid value.
- **"None" is `Option`,** never 0, -1, 0xFFFFFFFF or an empty string.
- **Ids are typed:** a wrapper such as `Spell4Id(Int)` stops one id being passed as another. In hot data, where a number keys a large table, weigh the cost first; the typed-ids trial on its Milestone 0 issue holds the measured cost.
- **No catch-all `_` over a type that can gain variants.** The code rule test holds this in `src/` and `dev/`.
- **When the client has a formula, use the client's.** The client's own rating formula matched its character sheet; another counted ratings 100 times too much.
- **A guard such as `x if x == some_const` against an `Int` constant means a type is missing.** A guard that compares two values the game sets while it runs, such as pids or unit ids, is fine.

## Errors

- **A fallible function returns a `Result` with its module's own error type,** whose named variants carry what went wrong. `Result(a, Nil)` is fine when there is one obvious failure, as in the stdlib. glinter refuses a `String` error and a discarded `Error`.
- **Each error variant maps to exactly one client result, in one place.** An outside failure is never reported as the player's mistake: a database outage was once answered as a wrong password.

## Naming

A name says what the thing does in the game, and every client name is earned by evidence. One word means one thing.

- **A client value, field, message or type with no evidence is named by its number,** such as `Message081A` or `field_at_bit_96`. It is renamed only when a decode saves what the client does with it in the fact file, and then everywhere in the same change: schema, code and fact file. The number stays in the doc comment. Placeholder names such as `Unknown47` look like knowledge.
- **An opcode is four hex digits** (`0x037E`); a client code address is written in full (`0x1403ec6a0`).
- **An id is named after the client table it keys:** `spell4_id`, `spell4_base_id`.
- **A game term is defined once,** in the doc comment of the type that is that thing. A work term is one line in `CLAUDE.md`. There is no glossary file.

## Modules

From Gleam's conventions page ("Fragmented modules", "Grouping by design pattern") and the talk it cites, "The Life of a File".

- **Length alone is never a reason to split;** shared state and shared types are.
- **Never group by kind:** no `types`, `rules` or `utils` module or folder. No module sits in a folder named for another package.
- **Split around a type with rules of its own, behind a small API.** A feature with its own state, rules and effects gets its own module, even when one process runs it. Mail, chat, friends and groups once lived in one player rule module of about 2,350 lines.
- **Each feature module has its own effect type;** a process's effect type wraps its features' effects, and a process's state holds one field per feature. One 29-variant effect type broke 10 test lists in 5 files, and one state record grew to 45 fields.
- **A process module sits beside its pure rule module:** the rule decides, the process carries out (the sans-io pattern).
- **Measure the real pain of a large module** before splitting it: build time after a change, how much agents read, bugs where one topic touches another's state, and how many branches edit the file. One module was touched by 125 of 284 commits.

## Comments

A comment describes the code as it stands, for a person reading it. Nothing in it may go stale.

- **A doc comment says what the code does and why,** in plain words, true while the code is unchanged. Put the what and the why in the `///` doc comment of the function or type. Write an inline `//` only for a line whose reason the doc comment cannot carry.
- **Client evidence stays:** a table, a row or a code address, after the plain sentence. The client never changes, so it cannot go stale.
- **Counts of the client's fixed data are fine; counts of this code are not,** since they change whenever the code does. No comparisons with another codebase.
- The code rule test refuses change-log words ("now", "no longer", "used to", "not yet", "for now", "so far"), plans, issue and pull request links, and dates; a patch marker's link to its upstream bug is the one exception. State a gap as what the code does: "an unknown interaction is logged and ignored".

## What the check holds

`./check` runs glinter with the rules `gleam.toml` turns on: every function annotated, no unused public function, no `String` error, no discarded `Error`, no `echo` or `todo`, no unqualified function import, no `panic` without a message. The code rule test holds the comment rules, pure rules, no catch-all over a growable type, no database work while an actor's starter waits, and every process supervised. A review need not look for those.

- **Read what a new or changed check flags before trusting its count.** Look at a sample of its findings and the rewrites they would force. A first catch-all check counted 121 findings and forced worse code in four places, from bugs a sample showed.
- **A suppression is never the default.** Write `// nolint: rule -- reason` only when the flagged code is already right and every rewrite is worse; the reason says why. A rule that needs more than a few suppressions is turned off in `gleam.toml`, with the reason. Name each new suppression in the pull request.

## Reviewing a diff

Work down every row, run its check, and fix each finding before `./check` runs. Reading the diff with this skill loaded is not a review: a rule whose evidence lies outside the diff needs its search.

| Rule | Check |
|---|---|
| A type that names its states | Every `True` or `False` the diff passes by position, and every `Bool` it matches inside a tuple |
| Enums decoded once at the edge | Every new `if x == ...` guard against a constant, and every bit mask outside a decoder |
| Names in full, numbers until earned | Every new name in the diff; every new client name has its fact-file record |
| `Result` with a named error | Every new `let assert`, `panic` and `Error(`; each `case` on a `Bool` followed by an assert |
| Evidence in the doc comment | Every new constant, variant and field cites the table and row, the client address or the recording |
| Docs that still hold | For every name the diff removes or behaviour it changes, search `src/`, `test/` and `dev/` for the name and for phrases that describe the old behaviour |
| Comments in doc comments | Every new inline `//` |
| Module boundaries | Every new message type sits in its process's module; every new module marks a type with rules of its own or a feature |
| Build on the lowest step that works | Every new dependency, `@external`, Erlang helper and Rust function, and every hand-written lock, cache, timer loop or retry loop, names in its doc why the steps above it could not do the job |
| The process rules | Every new process, message and handler against the designing-processes skill's review rows |
| Tests | Every new test against the writing-tests skill: evidence named, waits for events, failure paths covered |
| A shortcut is a bug, not a choice | Every behaviour the diff makes simpler than what it models: a state that changes only on some other event instead of when it is due, a check skipped, a case left out. Each is fixed, or Jim approves it by name before the merge. Judge it by what the player sees, never by what the fix costs |

## Before saying a change is done

Run `./check` as `CLAUDE.md` says, and give what it printed.
