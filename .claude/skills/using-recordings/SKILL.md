---
name: using-recordings
description: How to use packet recordings in the-genesis-prime as test fixtures and as evidence - what a recording proves and what it does not, where they are, what their times mean, decoding a window of one, reading a server's inputs off it, replaying its client messages through the rules or a running server, and the replay traps. Use when a test or a decision needs what the real client sent or accepted, when a step replays a session, or when the server seems to receive nothing in a live login, even if the request only says "check the recording".
---

# Using recordings

A recording holds every packet of one connection, both ways, one JSON line each, with its time in milliseconds. It ranks second as evidence, after the client's own code and tables.

## What a recording proves

- **Its client messages are the real client's:** what it sends, in what order, with what values, at what pace. That is evidence for a layout, a sequence and a client's timing.
- **Its server messages show only what the client accepted:** a layout it decoded and a sequence it went on from. They never show that an answer was right. A value the server chose, such as a damage number or a cooldown, is checked against the client's code and tables, never copied from a recording.
- **A recording with a value nobody can explain is a question for the client,** not a fixture to match.

## Where they are

| Recordings | Made by | Times |
|---|---|---|
| `test/golden_packets/<name>/` | Sessions recorded before this server existed, some with the real client and some with scripted clients. Each folder holds one file per player | A client packet when that server's 33 ms tick handled it, a server packet when it was queued, so times fall on ticks and show no network jitter |
| `~/Coding/wildstar/eldan-recordings` | This server's world, which records every connection; the newest file is the latest login | Off the monotonic clock: a client packet when its connection received it, a server packet when the connection queued it |

Compare the two kinds by order and content, never by exact time. Each file of a session with several players has its own clock: read a time from the file of the player the test plays, and name the file beside any time posted on an issue. One brief once gave a caster's times from its target's clock, and a 0.5 ms gap read as 55 ms.

## Reading one

- **List message kinds and times first,** with `python3 -I` over the JSON lines, to find the window.
- **Decode the window with the project's own decoder.** A scratch module with a `main` reads the file, keeps the window, and prints each packet's time, name and `string.inspect` of its decoded message. Send the output to a file, not straight into `grep`: a grep that matches nothing hides a compile error or a crash. Delete the module afterwards.
- **A `Float32` prints as its raw bits.** Read one with the protocol's conversion, or by hand: `python3 -c "import struct; print(struct.unpack('>f', struct.pack('>I', BITS))[0])"`.
- **Read the server's inputs off the recording before guessing at them.** A spell start carries the caster's position and facing; a spell go carries each unit's initial position and each telegraph's position and facing. Only a value the recording does not carry is a guess.
- **Read the system channel too.** Chat lines on the system channel can carry facts no other message does, such as the zone a login found.

## Replaying one

- **Play the recorded client through the rules** for a whole exchange in a pure test: feed each recorded client message to the rule at its time, answer what the rule asks for, and collect what the player is sent.
- **Compare the right slice,** over the same time window on both sides, with ids that the server chooses (casts, effects, items) renumbered. Assert equality and the message count on each side, so an empty stream cannot pass.
- **The replay client sends without the recorded gaps,** all at once after the world loads. A press that came seconds after the last one in the recording then lands in a cooldown. Send such presses at their recorded times, or name the difference in the test.
- **Drain before closing.** A test client that closes its socket with data still unread resets the connection, and the server can then lose the client's last packets at random.
- **Nothing can be read after a replay stops at a message.** It drops the bytes after that message, and the cipher is a stream, so a later read decrypts the wrong bytes. Read on with the replay functions that keep reading.
- **Wait for the save before stopping a server after a client leaves.** Stopping it at once can kill the save worker, which looks like a server bug and comes and goes between runs.
- **The player's unit id changes with each session.** Read it from the session's own messages before filtering a log by unit.

## When the server seems to receive nothing

Read its recording. The world records every packet of each connection, both ways, so the newest file shows whether the client sent the message and what the server answered.
