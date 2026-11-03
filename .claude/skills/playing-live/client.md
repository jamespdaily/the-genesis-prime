# The client

Each script's header is its contract: what it runs on the PC, what it refuses, and the client facts it rests on. `scripts/client.sh` also runs the PowerShell scripts beside it (`genesis-start.ps1`, `genesis-input.ps1`, `genesis-click.ps1`), whose headers hold the facts of each launch, keystroke and click.

## What the scripts cannot enforce

- `scripts/client.sh click <x> <y> --pc-free` (or a named target such as `enter-game`) is takeover mode, for the screens where the client reads the real cursor. Pass `--pc-free`, or set `GENESIS_PC_FREE=1`, only when Jim has said the PC is free. For a point the script does not name, or a named one that misses, read the point from a screenshot (`scripts/screenshot.sh`).
- `scripts/client.sh start` refuses while any WildStar64 runs, since it may be Jim's own client; leave his client alone.
- The client uploads its error reports to `crash.na.wildstar-online.com`, which still resolves; the PC's hosts file maps it to `0.0.0.0`. A new play PC needs the same line before its first session.
- Save the `client.sh start` line, with the program's SHA-256, in the session folder.

## A session by hand

1. Start the server in record mode: `gleam run -m genesis_prime/dev_start -- <folder>`.
2. `scripts/client-log.sh start <folder>`.
3. `scripts/report.sh install`, before the client starts: the client reads its addons when the world starts.
4. `scripts/client.sh start`.
5. Wait for the auth server's login-accepted log line, or a deadline.
6. `scripts/screenshot.sh <folder>/screen.jpg`.
7. When the report is wanted, enter the world from character select: `scripts/client.sh key enter` (a background key; it plays the first character in the list), or, for another character, the takeover click (`scripts/client.sh click enter-game --pc-free`). Wait about 15 s, then `scripts/report.sh collect <folder>`.
8. `scripts/client-log.sh collect <folder>`.
9. `scripts/client.sh stop`, then `scripts/report.sh remove`, then stop the server.

## A whole session without a person

`scripts/session.sh <folder>` runs the session above from the server's start to the verdict, into an empty or new folder, with no person and no focus taken; its header lists what it checks and what the folder keeps. A passing folder is committed as a dated folder under `test/wire_recording/`, where the replay tests read every folder. A failed folder also keeps `Logs` and `Errors`, which name the PC's machine: delete them before committing it. `scripts/session.sh --verdict <folder>` judges a folder with no PC, against `genesis_play`.
