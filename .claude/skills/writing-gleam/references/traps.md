# Traps of Gleam on Erlang and of our packages

Each trap below was met and measured. The traps that shape a process's design (the monotonic clock, heap size, persistent terms, actor start-up, selectors, `process.call`) are rules in the designing-processes skill instead.

## The runtime

- **Division by zero returns 0,** for ints and floats alike. Where zero is possible, use `int.divide` or `float.divide`, which return a `Result`.
- **`/` on ints rounds toward zero,** so `-101 / 4000` is 0, not -1, and a time before a start lands in the first bucket. Where the dividend can be negative, use `int.floor_divide`.
- **Bit arrays cut oversized values without an error, and read the high bit first.** Packet fields go only through the generated codec, which checks widths. Never write a packet's bit pattern by hand.
- **The BEAM has no NaN or infinity.** Packet floats use the protocol's raw-bits type.
- **A Gleam `Set` is `{set, Map}` on the BEAM,** not a bare map, so `map_size` on it fails. A `Dict` is a bare map.
- **Look in `gleam_stdlib` before writing a helper.** `int.compare`, `float.compare`, `result.replace_error` and `list.key_find` exist. `list.range` does not; `int.range` folds over a range whose end is left out.
- **A pure module takes trigonometry from `gleam_community_maths` and random numbers from `prng`,** whose seeds keep a rule repeatable.

## glisten

- **glisten is a patched copy of 9.0.1 in `vendor/glisten`.** Read its source there, not the Hex docs, for what the acceptor and handler do.
- **glisten catches only a `throw` in a connection's callback** (`rescue` in `vendor/glisten/src/glisten_ffi.erl` is a bare `catch`). A panic or any other error ends the connection process, and its close callback never runs. glisten runs the close callback only when the client closes the socket, not on `glisten.stop()`. Return `glisten.stop()` on an error instead of crashing, and on that path do what the close callback would do.
- **glisten ignores a selector returned after a connection starts.** Select everything in `on_init`; `process.select_monitors` catches every later monitor.
- **glisten runs `on_init` while the acceptor waits,** so a slow `on_init` holds up the next connection. Send the connection a message to itself there, and do the slow work when it arrives.

## pgo and pog

- **pgo, pog's Postgres driver, is a patched copy of 0.20.0 in `vendor/pgo`,** wrapped in a `gleam.toml` because a path dependency must be a Gleam package. Without its three patches, a connection crashed when Postgres closed its socket, and the pool kept handing out the dead socket: about every other query failed for 20 s or more after an outage. erleans/pgo#132, a fix for the crash alone, was closed unmerged.
- **Switching pgo between the vendored copy and Hex's does not rebuild it.** Delete `build/dev/erlang/pgo` after pointing `gleam.toml` at the other copy, or the old build keeps running.
- **pog reports a closed socket as `QueryTimeout`** (`pog_ffi.erl`, `convert_error(closed)`), so a `QueryTimeout` that came at once was a closed connection, not a slow query. pog has no clause for `einval`, and a caller that meets it crashes with `function_clause`.

## Squirrel and queries

- **Each query is a `.sql` file in a `sql` folder,** such as `src/genesis_prime/account/sql/`. Squirrel turns each folder into a `sql.gleam` module of typed functions; never edit those by hand. The comment at the top of a query becomes its function's doc comment. Migrations stay plain SQL in `priv/migrations`.
- **Squirrel reads types from a live database.** Regenerate after the tests have made the test database, with `DATABASE_URL` pointing at it and `gleam run -m squirrel`.
- **Squirrel cannot read `timestamptz`, take a domain such as `u16` as a parameter, or name a column `type`.** Read times `at time zone 'UTC'`, cast parameters (`$1::integer`), and rename columns with `as`.
- **Squirrel turns a Postgres enum into a Gleam custom type.** Make the enum in the public schema: `character` is a type keyword, so `COMMENT ON TYPE character.x` and `$1::character.x[]` fail to parse.
- **Squirrel takes a computed column to be never null,** so a null fails when the row is decoded. Return a flag beside a computed column that can be null.
- **Squirrel names parameters in a `set` list `arg_2`, `arg_3`, and so on.** Wrap such a query in a function that takes a record.
- **Changing a query's columns breaks the build squirrel needs,** because `gleam run -m squirrel` compiles `src/` first and the Gleam code already reads the new columns. Copy the new caller aside, restore the old one from git, run squirrel, then put the new caller back.
- **A migration's number is taken only when its branch merges.** The migration table records migrations by number alone, so two open branches can each add the same number. The branch that merges second renumbers its file after merging main.

## Generated code and the check

- **The message codec and its default test are generated from the schema.** After the schema or the generator changes, run the generator, then `gleam format` on both files. `./check` fails when they drift.
- **`gleam run -m` compiles all of `src/` first,** so a generator in `dev/` cannot run while the module it writes fails to compile. Never delete the generated module to regenerate it: restore it from git, then run the generator.
- **A changed signature breaks the generated module.** When a function the generated code calls changes, restoring the module from git does not help, as the old module calls the old signature too. Rewrite the calls in the generated module mechanically, run the generator, and compare its output with main's rewritten the same way: only the lines you meant to change may differ.
- **`./check` compares generated files and `.sql` queries with the git index.** One that changed and is not staged fails its `git diff --exit-code`. Stage the change, then run `./check`.
- **A `let assert` whose value the compiler can see never matches is a warning,** and warnings fail the check. To test a failed assert, match a value the compiler cannot see through, such as `int.parse("forty")`.
- **glinter cannot see a call by name.** `unused_exports` flags a public function that only another runtime calls over RPC. Ignore the rule for that file in `gleam.toml`, with the reason; do not make the function private.
- **`gleam format` puts a blank line between a `// nolint:` comment and the function under a doc comment,** and glinter then no longer applies it. Put a function's suppression in `gleam.toml`'s `[tools.glinter.ignore]` instead.

## Scripted edits

- **A scripted edit's anchor must be unique in the file.** A doc line copied from one function's comment also opened a variant's doc, and a cut between two such anchors duplicated 1,200 lines. Check each anchor's count before cutting.
- **A scripted edit's anchor must match the file as `gleam format` left it.** Format reflows long lines and calls. Read the current text first, or edit before formatting.
- **Format the files you changed by name, never the whole project.** `gleam format src test dev` also rewrites untracked files that are not yours, such as another session's scratch module.
