# The client

Each script's header is its contract: what it runs on the PC, what it refuses, and the client facts it rests on. `scripts/client.sh` also runs the PowerShell scripts beside it (`genesis-start.ps1`, `genesis-input.ps1`, `genesis-click.ps1`, `genesis-key.ps1`), whose headers hold the facts of each launch, keystroke and click.

## What the scripts cannot enforce

- For a click at a point the script does not name, or a named one that misses, read the point from a screenshot (`scripts/screenshot.sh`).
- `scripts/client.sh rclick <x> <y> --pc-free` right-clicks a point, as `click` left-clicks it (the same checks and gate); a creature's right-click is its interact and a bag item's is its use. The named points are the login and character-creation screens only.
- The client uploads its error reports to `crash.na.wildstar-online.com`, which still resolves; the PC's hosts file maps it to `0.0.0.0`. A new play PC needs the same line before its first session.
- Save the `client.sh start` line, with the program's SHA-256, in the session folder.

## A session by hand

1. Stop the play server's container (`dev/play_service/stop.sh`), then start the server in record mode (server.md, "A server by hand"): `gleam run -m genesis_prime/dev_start -- <folder>`.
2. `scripts/client-log.sh start <folder>`.
3. `scripts/report.sh install`, before the client starts: the client reads its addons when the world starts.
4. `scripts/client.sh start`.
5. Wait for the auth server's login-accepted log line, or a deadline.
6. `scripts/screenshot.sh <folder>/screen.jpg`.
7. When the report is wanted, enter the world from character select: `scripts/client.sh key enter` (a background key; it plays the first character in the list), or, for another character, the takeover click (`scripts/client.sh click enter-game --pc-free`). Wait about 15 s, then `scripts/report.sh collect <folder>`.
8. `scripts/client-log.sh collect <folder>`.
9. `scripts/client.sh stop`, then `scripts/report.sh remove`, then stop the server, then `dev/play_service/start.sh`.

## A fight played by hand

For what the client's Lua sees second by second while a person plays (the combat flag, Actuators): `scripts/report.sh install --timeline [minutes]` before the client starts, the person starts the client and plays, then `scripts/report.sh collect --by-hand <folder>`. The report is on the PC only after a reload or a camp; the script headers say when the addon asks for one.

## A whole session without a person

`scripts/session.sh <folder>` runs the session above from the server's start to the verdict, into an empty or new folder, with no person and no focus taken; its header lists what it checks and what the folder keeps. A passing folder is committed as a dated folder under `test/wire_recording/`, where the replay tests read every folder. A failed folder also keeps `Logs` and `Errors`, which name the PC's machine: delete them before committing it. `scripts/session.sh --verdict <folder>` judges a folder with no PC, against `genesis_play`.
