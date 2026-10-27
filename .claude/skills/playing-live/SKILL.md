---
name: playing-live
description: How to run the server for the real client and see the client's screen without touching Jim's window. Use for a live login or a playable server.
---

# Playing live

The machine's values live in `~/.genesis-prime/env.sh`, never in the repository, which is public: `GENESIS_PLAY_PC` (the ssh login of the PC that runs the client) and `GENESIS_PLAY_ADDRESS` (this machine's address on the PC's network). A script that needs one fails naming it when it is missing.

## Ports

The server listens on 6600 (STS), 23115 (auth) and 24000 (game); a recording relay uses 25000. Before binding any of them, check that no live server holds them:

`lsof -nP -iTCP -sTCP:LISTEN | grep -E ':(6600|23115|24000|25000)'`

## The server

From the main checkout, with every new `priv/migrations/*.sql` applied to the `genesis_live` database first:

```
. setup_check/environment.sh
export PGHOST=::1 PGPORT=5433 PGUSER=postgres PGDATABASE=genesis_live
gleam run
```

The server reads the table folder from `GENESIS_TABLE_DIR`, which `setup_check/environment.sh` sets.

## The client's log

Start the client with `-logFile -logFlush` on its command line, so it writes a log file. Run `scripts/client-log.sh start <folder>` before a session and `scripts/client-log.sh collect <folder>` after it: the script copies the session's log and error reports back and lists each message the client failed to handle, by id. It needs `GENESIS_PLAY_CLIENT_DIR`, the client's install folder on the PC.

The client uploads its error reports to `crash.na.wildstar-online.com`, which still resolves; the PC's hosts file maps it to `0.0.0.0`. A new play PC needs the same line before its first session.

## Seeing the screen

`scripts/screenshot.sh` captures the client's window on the PC through a scheduled task that runs hidden, copies the picture back and always deletes the task. It never brings a window forward or moves focus: Jim may be using the PC.
