# The server

Run it from the main checkout, on the `genesis_play` database with every new `priv/migrations/*.sql` applied and recorded first, by the script `./check` uses:

`PGHOST=::1 PGPORT=5433 PGUSER=postgres dev/apply_migrations.sh genesis_play`

The script's header covers a new play database (made empty with `createdb`) and `--adopt` for one made before the migration record. The server refuses to start on a database that lacks a migration, ran an edited one or has no migration record. `scripts/session.sh` copies `genesis_play` as its template, so its run database starts migrated.

```
. setup_check/environment.sh
export PGHOST=::1 PGPORT=5433 PGUSER=postgres PGDATABASE=genesis_play
export GENESIS_GAME_ADDRESS=$GENESIS_PLAY_ADDRESS GENESIS_REALM_NAME=Genesis
gleam run
```

`setup_check/environment.sh` sets `GENESIS_TABLE_DIR`, the table folder the server reads.

## In herdr

When the session runs in a herdr pane (`HERDR_ENV=1`), a server for Jim to play on runs in a tab labelled `server` in the session's own workspace, not as a hidden background process, so Jim sees its log and can stop it himself (Jim, 2026-11-02). Read `herdr --skill` first; the binary is the authority for its syntax.

1. `herdr tab list --workspace "$HERDR_WORKSPACE_ID"`: reuse a `server` tab whose pane is at its shell prompt; otherwise `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label server --cwd <main checkout> --no-focus`, and take the pane id from `.result.root_pane.pane_id`.
2. `herdr pane run <pane> '<the commands above, joined by &&>'`.
3. `herdr pane wait-output <pane> --match 'game tables and serves the STS login' --timeout 120000`: the server's ready line (`ready_line` in `src/genesis_prime.gleam`). On a timeout, `herdr pane read <pane> --source recent --lines 80` shows why.
4. To stop it: SIGTERM to its VM, so the tree stops in order and saves, as `scripts/session.sh` does: the `beam.smp` pid among `herdr pane process-info --pane <pane>`'s `foreground_processes`, then `kill -TERM <pid>`, and check the ports are free (SKILL.md). Ctrl+C in the pane opens the VM's break menu instead. Leave the tab for the next session.

`scripts/session.sh` starts and stops its own server.
