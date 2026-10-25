---
name: playing-a-live-login
description: How to run a live login with the real WildStar client in the-genesis-prime - the steps before and after (the launcher that starts the database and the server's runtimes, checks this Mac's address, stops the world so it saves, and shows its dashboard), and how to play from this Mac with the playtest tool - pressing keys, summoning creatures with game master commands, and reading damage, chat replies and errors off screenshots. Use at the end of a step that changes what the client sees or sends, whenever the playtest tool is used, or when Jim asks for a playable server, even if the request only says "try it in game".
---

# Playing a live login

A live login with the real client, played by an agent, ends each step that changes what the client sees or sends. The client runs on Jim's Windows PC, and `tools/playtest/playtest` plays it from this Mac; its docstring lists the commands. Jim's hands are not needed, but ask before starting whether the PC is free.

A server change made for a live login, such as a setting or a start script, first passes a replay test with it turned on. A bug a replay can show must not cost a live login.

## Before and after

1. Stop any other server using ports 6600, 23115 and 24000.
2. Start everything with the launcher: `mkdir -p tmp/playtest`, then `cd launcher && PATH=$HOME/.local/otp/29.1.2-gc210/bin:$PATH exec gleam run > ../tmp/playtest/launcher.log 2>&1` as its own background command, with no `&`. It starts or adopts Postgres, builds, applies the migrations, starts the server's runtimes, and checks this Mac's address. Its log prints one line per change. Wait for every row to read `Healthy`. The dashboard is at http://127.0.0.1:4400/, and each runtime's output goes to `tmp/launcher/<runtime>.log`: watch the world's for errors and warnings.
   - A runtime that already runs, such as one left by an earlier launcher, is adopted and shown with its log, not started twice.
   - A port taken by another program shows its row as `Blocked`, with the program's name.
   - In a worktree, the launcher reuses the main checkout's Postgres.
3. **The address row must match this Mac's address before every login,** not once a session: the router changes it. The row turns `Unhealthy`, with both addresses, when the host of `auth.server` in the development database (`genesis_prime_dev`, port 5433) differs from `ipconfig getifaddr en0`. Its Fix button writes this Mac's address into the row. The playtest tool gives the client this Mac's address itself.
4. `tools/playtest/playtest enter`, then play, reading each screenshot, then `tools/playtest/playtest leave`.
5. Stop with `kill -TERM` on the launcher; it prints the exact command when it starts. It stops the world first, which logs that it is saving every player, then the other runtimes, then exits. Postgres stays up. The dashboard's Stop all does the same and leaves the launcher running. Ctrl-C, or stopping the background task, ends only the launcher: the runtimes keep running, and the next launcher adopts them.

Post what the client showed and what the log showed on the step's issue, with the numbers.

## The development character and database

- **The development character, Gob Stopper, keeps what each login leaves it.** Its place, level, items and credits carry over, so set what this login needs in the development database before entering, while the server is stopped: a running server's save overwrites rows edited under it. Count the free bag slots against a login's rewards, or a full bag ends the reward with an error.
- **Undo a branch's migration after its live login.** Every worktree shares the development database, and the migration table records a migration by its number alone, so two branches that each add the same number clash: the second one's launcher skips its own. After the login, with the server stopped, reverse the migration by hand, delete its row from the migration table, and put back any row its backfill changed.
- **When the development database already records the branch's migration number, apply the branch's file by hand** before starting the launcher, with `psql ... -v ON_ERROR_STOP=1 -f priv/migrations/<file>` and no row in the migration table. After the login, with the server stopped, drop what the file made.
- **With both character slots used, the character screen hides the create button.** Delete a character first to test create.
- **Restart the world between a rehearsal and the live login,** with the dashboard's Restart on the world row. A rehearsal's summoned creature stays on the map while the server runs.

## When it goes wrong

- **The dashboard shows what a screenshot cannot:** where every creature and player is by the server's positions, and each warning and error a runtime logs. Kill and Start on a runtime test an outage during a login.
- **When the server seems to receive nothing, read its recording,** as the using-recordings skill says.
- **A client that times out, or drops back to the login screen, while the server logs nothing** has usually lost this Mac's address: check the address row first.
- **A client that stops at "Invalid account name or password" or "Unhandled NC Platform Error 15"** needs `playtest account`: the development account's password has changed. Then close the client with `playtest do 'Get-Process WildStar64 -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }'`, because `enter` stops when a client is already running.
- **A Win32 error from `playtest`, or a client back at the login screen, can mean someone used the PC during the run.** The helper loses the window: ask, then close the client and enter again. An elevated program in the PC's foreground blocks the helper the same way: `SetCursorPos` returns false, and keys and clicks do nothing without an error.
- **The PC holds one copy of `tools/playtest/pc` for every checkout.** A branch made before a change to it cannot drive the PC's copy: `enter` stops with `ParameterArgumentTransformationError`. Merge main into the branch. Never `playtest install` from an older branch: it replaces the copy another session uses.
- **When every `playtest` command hangs with no output, a stale SSH control link is the cause.** Kill the SSH mux process that holds `/tmp/playtest-ssh-*`, then remove the socket. Wrap each `playtest` call in `timeout` so a hang ends on its own.
- The development server's logout timer is 0, so `/camp` reaches the character screen in about half a second. The server saves when the logout is confirmed or the client closes.

**A burst of connections from the PC tests the listeners.** This makes 100 plain closes and 100 resets at each of the three ports, with this Mac's address from `ipconfig getifaddr en0`; each 100 took about 1.1 s. The world's log then shows one warning per dropped connection, and must show no acceptor stop and no supervisor report:

    timeout 120 tools/playtest/playtest do '$h="<mac address>"; foreach ($p in 6600,23115,24000) { foreach ($mode in "plain","reset") { $ok=0; $sw=[Diagnostics.Stopwatch]::StartNew(); 1..100 | ForEach-Object { try { $t=New-Object Net.Sockets.TcpClient; $t.Connect($h,$p); if ($mode -eq "reset") { $t.Client.LingerState = New-Object Net.Sockets.LingerOption($true,0) }; $t.Close(); $ok++ } catch {} }; "$p $mode connected=$ok ms=$($sw.ElapsedMilliseconds)" } }'

## Reading the screen

- **The player, Gob Stopper, is the small stalker nearest the camera.** Its claws show on its forearms while its weapons are drawn, in combat, and are gone once it sheathes them.
- `playtest shot <name>` saves `<name>.jpg` at 3840×2160 and `<name>-small.jpg` 1280 wide in `tmp/playtest`. Read the small one first.
- **`playtest shot` brings the client to the front first.** The client minimizes whenever it loses the focus, so with two clients a shot of one minimizes the other; a restored client gets half a second to draw before the shot. The key, click, type and chat commands bring it to the front too.
- **Take the screenshot straight after the key press.** Damage numbers fade within about a second, so press, shoot, and press again.
- **Read exact numbers from chat, not from the screen.** `!entity vitals` and `!entity properties` print the selected unit's, or the player's own, in the chat window at the bottom left. The report is about the server's selection, which can differ from the target frame, so read its first line before its numbers: the player's says `CreatureID: 0`. Crop the full screenshot to read it, such as `sips -c 160 700 --cropOffset 1670 0 shot.jpg --out chat.jpg` for the last four lines. The order is `-c <height> <width> --cropOffset <y> <x>`; an offset of `0 0` is ignored and crops the centre, so use `1 1` for the top left corner.
- **To read the player's own vitals, click its portrait first:** `playtest click 1410 1734`. Escape does not clear the server's selection.
- A creature's nameplate shows its health over its head once it is hurt.
- **After `/camp`, wait 2 seconds on the character screen before clicking Enter** (`[EldanScreen]::Click(1920, 2076)`). A click as soon as `Wait-Screen "character"` returns is lost. In a `playtest do` script, call `[EldanScreen]::Front() | Out-Null` before the click, as `playtest click` does.
- **`Wait-Screen` needs its timeout:** `Wait-Screen "world" 60`. Without it the timeout is 0 s, and it returns -1 at once. The names are `login`, `character`, `world` and `welcome` (`tools/playtest/pc/screen.ps1`).

## Topic notes

Read the note for the topic before the login starts.

- [references/fights.md](references/fights.md): fighting a creature, casting a spell, testing an ability on the bar, pressing keys, summoning a creature or dying.
- [references/items-and-vendors.md](references/items-and-vendors.md): the bag, using, equipping, selling, splitting or deleting an item, a vendor; also sending a right-click, drag or wheel.
- [references/mail.md](references/mail.md): sending or reading mail at a mailbox.
- [references/quests.md](references/quests.md): taking, playing or turning in a quest.
- [references/other-players.md](references/other-players.md): simulated players, chat channels with them, and the friends list.
- [references/paths.md](references/paths.md): the Path Log, path experience and changing the active path.
- [references/screen.md](references/screen.md): damage numbers, health, buffs or timings off screenshots, `!entity properties` reports, and presses closer than 0.7 s.
