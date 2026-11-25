# The server

The play server runs as a Podman container on Jim's Mac, rebuilt from main by a launchd updater every 2 minutes (`dev/play_service`; each script's header is its contract). It is the server Jim plays on: never start another beside it, since both want ports 6600, 23115 and 24000.

- `podman ps` shows `genesis-play` (the server) and `genesis-play-postgres` (the play database); `podman logs genesis-play` is the server's log.
- `~/.genesis-prime/play-service.log` has one line per updater action: each build, migration and restart, and each commit it left alone and why.
- Before a stop by hand, check no player is connected: `lsof -nP -iTCP:24000 -sTCP:ESTABLISHED`. Stop with `dev/play_service/stop.sh --hold` (the updater then leaves it alone); `dev/play_service/start.sh` starts it and releases the hold.
- A merge during a sitting restarts the server within minutes, players connected or not: hold it first or tell Jim; never promise the old build stays.
- `scripts/session.sh` stops the container before its run and starts it after, also when the run fails; the updater does nothing while the live lock is held.

## The play database

`genesis_play`, in the `genesis-play-postgres` container, is published at `127.0.0.1` port 5434 (`GENESIS_PLAY_PGPORT` overrides it for this skill's scripts). Its password is `GENESIS_PLAY_PGPASSWORD` in `~/.genesis-prime/env.sh`, made by `dev/play_service/install.sh`. Every tool that reads or writes it (`gleam run -m genesis_prime/add_account`, `add_character`, `mark_rename`, `import_world_data`, `sitting_bot`) reads the usual variables:

```
export PGHOST=127.0.0.1 PGPORT=5434 PGUSER=postgres PGPASSWORD=$GENESIS_PLAY_PGPASSWORD PGDATABASE=genesis_play
```

`./check` and the tests keep their own Postgres (`PGHOST=/tmp PGPORT=5433`) and never touch the play database. The updater applies each new `priv/migrations/*.sql` before it restarts the server; by hand, from the main checkout, with the variables above: `dev/apply_migrations.sh genesis_play` (its header covers `--adopt`). The server refuses a database that lacks a migration, ran an edited one or has no migration record.

## A server by hand

For a run that is not the play server (a step's own checks): `dev/play_service/stop.sh --hold`, then from the main checkout:

```
. setup_check/environment.sh
export PGHOST=127.0.0.1 PGPORT=5434 PGUSER=postgres PGPASSWORD=$GENESIS_PLAY_PGPASSWORD PGDATABASE=genesis_play
export GENESIS_GAME_ADDRESS=$GENESIS_PLAY_ADDRESS GENESIS_REALM_NAME=Genesis GENESIS_PLAY_ACCOUNT
gleam run -m genesis_prime/dev_start -- ~/.genesis-prime/sittings/<date>-<topic>
```

and `dev/play_service/start.sh` after. `setup_check/environment.sh` sets `GENESIS_TABLE_DIR` and reads `GENESIS_PLAY_ACCOUNT` (the client's login name) from env.sh; `dev_start` refuses to start without it exported.

## Every sitting is recorded

With `GENESIS_RECORD_DIR` set, the server records each connection under `~/.genesis-prime/sittings` (`src/genesis_prime/sitting.gleam`): the container into `<date>-play-<commit>`, `dev_start` into the folder it is given. A sitting is never committed unless a step adopts it as a committed session. A sitting still being recorded is read up to its last whole line. Read one with:

- `gleam run -m genesis_prime/recording_dump -- <folder or .jsonl> [--from <ms>] [--to <ms>] [--unit <id>]`: one line per message.
- `gleam run -m genesis_prime/unhandled_ranking -- <folder>...`: the client's messages the server does not handle, most frequent first.
- `python3 -I dev/live_watch.py .`: while Jim plays, every 30 s prints each refused press, cast that struck nobody, and player death in the newest sitting.

## In herdr

When the session runs in a herdr pane (`HERDR_ENV=1`), a server by hand for Jim to watch runs in a tab labelled `server` in the session's own workspace, never as a hidden background process, so Jim sees its log and can stop it. Read `herdr --skill` first; the binary is the authority for its syntax.

1. `herdr tab list --workspace "$HERDR_WORKSPACE_ID"`: reuse a `server` tab whose pane is at its prompt; otherwise `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label server --cwd <main checkout> --no-focus`, and take the pane id from `.result.root_pane.pane_id`.
2. `herdr pane run <pane> '<the commands under "A server by hand", joined by &&>'`.
3. `herdr pane wait-output <pane> --match 'game tables and serves the STS login' --timeout 120000` (`ready_line` in `src/genesis_prime.gleam`). On a timeout, `herdr pane read <pane> --source recent --lines 80` shows why.
4. To stop it, SIGTERM its VM so the tree stops in order and saves: the `beam.smp` pid among `herdr pane process-info --pane <pane>`'s `foreground_processes`, then `kill -TERM <pid>`, then check the ports are free (SKILL.md). Ctrl+C opens the VM's break menu instead. Leave the tab for the next session.
