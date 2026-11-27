---
name: storing-data
description: Sets the rules for Postgres here - SQL files, migrations, constraints, saves, transfers and server-owned content tables. Use for any change that reads or writes the database or changes its schema.
---

# Storing data

- Plain SQL in `.sql` files, typed by squirrel. A row held whole is decoded into its own record where it is read.
- Change the schema only with numbered migration files in the repository. Never edit a migration that has run outside a developer's machine.
- What Postgres does, Postgres does: uniqueness, foreign keys, checks, transactions and fencing a stale writer (an epoch column) live in the schema, not in Gleam checks run before the write.
- A failed write reports which constraint failed, mapped to its own error, not one error for every failure.
- Saves are versioned, so an older save never overwrites a newer one, and idempotent, so a retry is safe.
- Moves between two owners (trade, mail with an item, auction, group loot) have one source of truth: a database transaction or a coordinator. Each transfer has a test, including failure halfway.
- Data the server owns (spawns, patrol paths, per-creature values, vendor stock, loot, server-choice numbers such as aggro range) goes in content tables with a source on each row, loaded once into persistent terms at start; client tables stay files, and rules and formulas stay in code. Anything that can live in the database instead of code goes there.
- A table's or column's comment says what it is and means in plain words: no sources, scripts, paths, id lists, step names or history.
- A step that touches Postgres shows Jim, in its Design and closing summary, each table touched as a DDL block (columns, keys, checks), its indexes with the query each serves, and the Postgres features used (constraints, transactions, upserts, partial indexes); narrow enough for Discord.
