---
name: playing-live
description: How to run the server for the real client and see the client's screen without touching Jim's window. Use for a live login or a playable server.
---

# Playing live

This skill runs the server for the real client on Jim's PC, drives the client, and sees its screen without touching Jim's window. The scripts are in this skill's `scripts/` folder; each script's header is its contract.

## Every time

- The machine's values live in `~/.genesis-prime/env.sh`, never in the repository, which is public. Each script's header names the values it reads.
- The play account's password is used nowhere but the play server: a recording's fixture holds the account's SRP verifier, and recordings are committed to this public repository, which also sees the play address the auth server hands the client (Jim, 2026-11-02).
- The server listens on 6600 (STS), 23115 (auth) and 24000 (game). Before binding them, check that no live server holds them: `lsof -nP -iTCP -sTCP:LISTEN | grep -E ':(6600|23115|24000)'`.
- Jim may be using the PC. The scripts take no focus, except `scripts/client.sh click` and `scripts/client.sh key <scan> --pc-free`, which bring the client forward (click also moves the real mouse, key presses a real key): run them only when Jim has said the PC is free.
- The live lock (`~/.genesis-prime/live.lock/`) gives the PC's client to one holder at a time. A lock whose owner is gone is never taken over: `scripts/session.sh --recover` ends what the owner started and releases it.

## Which file to read

- [server.md](server.md): the play database, starting and stopping a server, and a server for Jim in herdr. Read it when Jim asks for a playable server, or before a session by hand.
- [client.md](client.md): the client's log, its screen, driving it, a session by hand, and `scripts/session.sh`, a whole session with no person. Read it before any session.
