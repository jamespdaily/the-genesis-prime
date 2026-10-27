---
name: storing-data
description: Rules for Postgres - SQL, migrations, constraints, saves and transfers. Use for any change that reads or writes the database or changes its schema.
---

# Storing data

- Plain SQL in `.sql` files, typed by squirrel. A row held whole is decoded into its own record where it is read.
- Change the schema only with numbered migration files in the repository. Never edit a migration that has run outside a developer's machine.
- What Postgres does, Postgres does: uniqueness, foreign keys, checks, transactions and fencing a stale writer (an epoch column) live in the schema, not in Gleam checks run before the write.
- A failed write reports which constraint failed, mapped to its own error; never one error for every failure.
- Saves are versioned, so an older save never overwrites a newer one, and idempotent, so a retry is safe.
- Moves between two owners (trade, mail with an item, auction, group loot) have one source of truth: a database transaction or a coordinator. Each transfer has a test, including failure halfway.
