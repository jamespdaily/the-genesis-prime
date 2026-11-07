# The server

The play server runs as a Podman container on Jim's Mac, rebuilt from main by a launchd updater (`dev/play_service`, the scripts' headers are their contracts). It is the server for Jim to play on: do not start another one beside it, since both want ports 6600, 23115 and 24000.

- `podman ps` shows `genesis-play` (the server) and `genesis-play-postgres` (the play database, `postgres:18`, data in the volume `genesis-play-data`). `podman logs genesis-play` is the server's log.
- `~/.genesis-prime/play-service.log` holds one line per action of the updater: each build, migration and restart, and each commit it left alone and why.
- To stop it by hand: `dev/play_service/stop.sh --hold` (the updater then leaves it alone); `dev/play_service/start.sh` starts it again and releases the hold.
- `scripts/session.sh` stops the container before its run and starts it after, also when the run fails, and the updater does nothing while the live lock is held.

## The play database

`genesis_play` is the database in the `genesis-play-postgres` container, published for the tools on this Mac at `127.0.0.1` port 5434 (`GENESIS_PLAY_PGPORT` overrides the port for the playing-live scripts). Its password is `GENESIS_PLAY_PGPASSWORD` in `~/.genesis-prime/env.sh`; `dev/play_service/install.sh` makes it. Every tool that reads or writes the play database reads these through the variables it already reads:

```
export PGHOST=127.0.0.1 PGPORT=5434 PGUSER=postgres PGPASSWORD=$GENESIS_PLAY_PGPASSWORD PGDATABASE=genesis_play
```

That covers `gleam run -m genesis_prime/add_account`, `add_character`, `mark_rename`, `import_world_data`, `sitting_bot` and `scripts/session.sh`, which makes its run database from `genesis_play` as the template. `./check` and the tests keep their own Postgres (`PGHOST=/tmp PGPORT=5433` from `~/.genesis-prime/env.sh`) and never touch the play database. The updater applies each new `priv/migrations/*.sql` to `genesis_play` before it restarts the server. By hand, from the main checkout:

`PGHOST=127.0.0.1 PGPORT=5434 PGUSER=postgres PGPASSWORD=$GENESIS_PLAY_PGPASSWORD dev/apply_migrations.sh genesis_play`

The script's header covers `--adopt`. The server refuses to start on a database that lacks a migration, ran an edited one or has no migration record.

## A server by hand

For a run that is not the play server (a step's own checks), stop the container first (`dev/play_service/stop.sh --hold`, and `dev/play_service/start.sh` after), then from the main checkout:

```
. setup_check/environment.sh
export PGHOST=127.0.0.1 PGPORT=5434 PGUSER=postgres PGPASSWORD=$GENESIS_PLAY_PGPASSWORD PGDATABASE=genesis_play
export GENESIS_GAME_ADDRESS=$GENESIS_PLAY_ADDRESS GENESIS_REALM_NAME=Genesis GENESIS_PLAY_ACCOUNT
gleam run -m genesis_prime/dev_start -- ~/.genesis-prime/sittings/<date>-<topic>
```

`setup_check/environment.sh` sets `GENESIS_TABLE_DIR`, the table folder the server reads, and reads `GENESIS_PLAY_ACCOUNT` (the login name of the account the client logs in with) from `~/.genesis-prime/env.sh`; `dev_start` refuses to start when it is not exported.

## Every sitting is recorded

The server records each connection into a folder of its own under `~/.genesis-prime/sittings` when `GENESIS_RECORD_DIR` names one (`src/genesis_prime/sitting.gleam`): the container records every start into `<date>-play-<commit>`, and `dev_start` into the folder it is given. A sitting stays there and is never committed unless a step adopts it as a committed session. Read one with:

- `gleam run -m genesis_prime/recording_dump -- <folder or .jsonl> [--from <ms>] [--to <ms>] [--unit <id>]`: the sitting as messages, one line each (its header gives the columns).
- `gleam run -m genesis_prime/unhandled_ranking -- <folder>...`: the client's messages the server does not handle, most frequent first, with their system's group.
- `python3 -I dev/live_watch.py .`: while Jim plays, decodes the newest sitting every 30 s and prints each refused press, cast that struck nobody, and player death once.

A sitting still being recorded is read up to its last whole line, and each of its connections ends with a line saying it has no closing line yet.

## In herdr

When the session runs in a herdr pane (`HERDR_ENV=1`), a server by hand for Jim to watch runs in a tab labelled `server` in the session's own workspace, not as a hidden background process, so Jim sees its log and can stop it himself (Jim, 2026-11-02). Read `herdr --skill` first; the binary is the authority for its syntax.

1. `herdr tab list --workspace "$HERDR_WORKSPACE_ID"`: reuse a `server` tab whose pane is at its shell prompt; otherwise `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label server --cwd <main checkout> --no-focus`, and take the pane id from `.result.root_pane.pane_id`.
2. `herdr pane run <pane> '<the commands under "A server by hand", joined by &&>'`.
3. `herdr pane wait-output <pane> --match 'game tables and serves the STS login' --timeout 120000`: the server's ready line (`ready_line` in `src/genesis_prime.gleam`). On a timeout, `herdr pane read <pane> --source recent --lines 80` shows why.
4. To stop it: SIGTERM to its VM, so the tree stops in order and saves, as `scripts/session.sh` does: the `beam.smp` pid among `herdr pane process-info --pane <pane>`'s `foreground_processes`, then `kill -TERM <pid>`, and check the ports are free (SKILL.md). Ctrl+C in the pane opens the VM's break menu instead. Leave the tab for the next session.

`scripts/session.sh` starts and stops its own server, and the play server's container around it.
