---
name: playing-live
description: How to run the server for the real client and see the client's screen without touching Jim's window. Use for a live login or a playable server.
---

# Playing live

The machine's values live in `~/.genesis-prime/env.sh`, never in the repository, which is public: `GENESIS_PLAY_PC` (the ssh login of the PC that runs the client) and `GENESIS_PLAY_ADDRESS` (this machine's address on the PC's network). The commands that drive the client also read `GENESIS_PLAY_CLIENT_DIR` (the client's install folder on the PC, for example `C:\WildStar-HD`) and, to log in from the command line, `GENESIS_PLAY_ACCOUNT` and `GENESIS_PLAY_PASSWORD`. A script that needs one fails naming it when it is missing.

## Ports

The server listens on 6600 (STS), 23115 (auth) and 24000 (game); a recording relay uses 25000. Before binding any of them, check that no live server holds them:

`lsof -nP -iTCP -sTCP:LISTEN | grep -E ':(6600|23115|24000|25000)'`

## The server

From the main checkout, with every new `priv/migrations/*.sql` applied to the `genesis_play` database first:

```
. setup_check/environment.sh
export PGHOST=::1 PGPORT=5433 PGUSER=postgres PGDATABASE=genesis_play
gleam run
```

The server reads the table folder from `GENESIS_TABLE_DIR`, which `setup_check/environment.sh` sets.

## The client's log

Start the client with `-logFile -logFlush` on its command line, so it writes a log file. Run `scripts/client-log.sh start <folder>` before a session and `scripts/client-log.sh collect <folder>` after it: the script copies the session's log and error reports back and lists each message the client failed to handle, by id. It needs `GENESIS_PLAY_CLIENT_DIR`, the client's install folder on the PC.

The client uploads its error reports to `crash.na.wildstar-online.com`, which still resolves; the PC's hosts file maps it to `0.0.0.0`. A new play PC needs the same line before its first session.

## Seeing the screen

`scripts/screenshot.sh` captures the client's window on the PC through a scheduled task that runs hidden, copies the picture back and always deletes the task. It never brings a window forward or moves focus: Jim may be using the PC.

## Driving the client

`scripts/client.sh` starts, types into and closes the client on the PC in the person's session, through hidden scheduled tasks that it always deletes. It never takes focus: no SendInput, no SetForegroundWindow, and each start and each typing records the foreground window before and after and fails if it moved.

- `client.sh start` refuses, changing nothing, when any WildStar64 process runs: Jim may be playing. Otherwise it starts the client from `GENESIS_PLAY_CLIENT_DIR` pointed at `GENESIS_PLAY_ADDRESS`, logged in from its command line with the account and password, and prints the pid, the program's SHA-256 and the window's style. Keep the client borderless: started behind the person's window it keeps drawing and takes posted input. The command line begins with `/auth` and the host because the client starts its launcher otherwise (fact 0x14000ae77).
- `client.sh start --type-login` starts it without an account or password. Then `client.sh type <text>` and `client.sh key tab|enter` post the characters to its window one by one (facts 0x140112a60, 0x140111030, 0x1400e67a0).
- `client.sh stop` closes the client that `start` recorded, by pid, and no other.

A session, in order:

1. Start the server in record mode: `gleam run -m genesis_prime/dev_start -- <folder>`.
2. `scripts/client-log.sh start <folder>`.
3. `scripts/client.sh start`.
4. Wait for the auth server's login-accepted log line, or a deadline.
5. `scripts/screenshot.sh <folder>/screen.png`.
6. `scripts/client-log.sh collect <folder>`.
7. `scripts/client.sh stop`, then stop the server.

Save the `client.sh start` line, with the program's SHA-256, in the session folder.
