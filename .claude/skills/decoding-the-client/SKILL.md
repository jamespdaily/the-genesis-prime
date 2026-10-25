---
name: decoding-the-client
description: How to find and save facts about the WildStar client (WildStar64.exe, build 16042) in the-genesis-prime - the fact file first, then headless Ghidra recipes, the UI Lua and the .tbl game tables - to learn what a message carries, what a field or enum value means, how the client reacts to a server message, or what a Lua function does, and how to save each fact as a graded record and name its function in the Ghidra project. Use whenever a question only the client can answer comes up - decoding an opcode, checking a layout in the packet schema, naming an unknown field, finding enum values, tracing a handler - even if the request only says "what does the client send when...".
---

# Decoding the client

A client fact is decoded once. It is saved as a record in the fact file, its function is named in the Ghidra project, and every later question searches the fact file first. Unsaved decodes were done again, and facts left in comments and issues were lost.

## The fact file first

The fact file is [references/client-facts.toml](references/client-facts.toml). Search it for the address, opcode, table column, enum or Lua function before opening Ghidra (`grep -n -A6 0x1403c8760`). A record that answers the question ends the search; a record graded below "sure" is a lead to check, not an answer.

Each record is one TOML table, under a `# <Topic>` comment:

```toml
["0x1403c8760"]
name = "HandleExperienceGained"
statement = """Handles 0x01AC. Adds field 0 to the total experience and subtracts field 1, \
the rested experience, from the rest pool, then raises ExperienceGained with the reason \
(field 3) and the unit (field 4)."""
proof = "The handler's decompile at 0x1403c8760, reached from the in-game jump table at 0x1403f1344."
grade = "fairly sure"
```

- **Its key:** a code address in lowercase and in full (`0x1403ec6a0`), an opcode (`0x07F4`), a table column (`Spell4Effects.effectType`), an enum (`Spell4EffectType 3`) or a Lua function (`MailSystemLib.AtMailbox`). An address with little meaning of its own, such as a vtable or a switch case, can sit inside the record of the function that owns it.
- **statement:** what the client does, in the game's or the message's terms: arguments, fields, types, values, sizes in bits. Registers, stack and struct offsets and vtables go in the proof.
- **proof:** the addresses read, and what the instructions there do; or the table rows, recording or live login that showed it.
- **grade:** **sure** (you read the instructions that do it), **fairly sure** (you read the code around it, or a decompile you did not check against the disassembly), or **guess** (an inference you could not check).
- **name:** the function's name in the Ghidra project, only when the key is a function's entry point. `scripts/name_functions.sh` applies the names of records graded "sure" or "fairly sure"; a "guess" record's name waits until its function is read.

**Most records are leads, not facts.** Every record graded "guess" without its own reason came from earlier notes and code comments that nobody has read against the client. A sample of 30 such entries showed where they point is reliable and their detail is not: the main claim held in 29, but 12 needed a detail corrected and 2 had a wrong function name. Before relying on one, read the code it names, then rewrite the record and raise its grade.

From the repository's root, `python3 -I .claude/skills/decoding-the-client/scripts/check_facts.py .claude/skills/decoding-the-client/references/client-facts.toml --cover src test dev` checks the file: the fields, the grades, unique keys and names, no other server's name or issue number, and that every client address the code cites is in the file and every Lua function it cites is a key.

[references/client-opcodes.json](references/client-opcodes.json) is the registration function's dump: every message the client registers, with its struct size and which way it goes. Thirteen of its 1,132 numbers are above 0xFFFF, so they are not ordinary 16-bit opcodes; what they are is not yet decoded.

## Saving a fact

1. Add or correct the record in the fact file, in the same change as the code that uses it.
2. Name the function in the Ghidra project: `GHIDRA_WRITE=1 scripts/ghidra.sh RenameFunction.java <out> <address> <name>`. Use a name that says what it does in the game, such as `HandleExperienceGained`. Run nothing else on the project while it writes. To apply every name in the fact file at once, run `scripts/name_functions.sh`.
3. When the fact names a message, field or type that was a number, rename it everywhere in the same change, as the writing-gleam skill says.

## What is where

| Thing | Location |
|---|---|
| Ghidra project (already analysed) | `~/Coding/wildstar/ghidra`, project `WildStar`, program `WildStar64.exe`. Local only, never in git |
| Ghidra scripts | `ghidra/scripts/*.java` in this skill's folder. Each docstring says what it does and takes; when it lists no arguments, read the script's `run()` |
| Message registration dump | `~/Coding/wildstar/ghidra/register_fn.txt` (the registration function's disassembly, local only) |
| Game tables | `~/Coding/wildstar/client-data/ClientData/DB/*.tbl`, which the server loads too. Read one with `~/Coding/wildstar/scripts/wstbl.py` (`wstbl.rows(path)` yields dicts with the file's own column names). Extract them again as `scripts/wsarchive.py`'s docstring says |
| Client archives | `~/Coding/wildstar/client/WildStar/Patch/*.index` and `.archive`; extract with `scripts/wsarchive.py` |
| UI Lua | `~/Coding/wildstar/ui-extract/ClientData/UI/` |
| English text table | `~/Coding/wildstar/client-data/ClientDataEN/en-US.bin`: a 96-byte header, records of id and offset, then UTF-16 strings |
| Map area files | `~/Coding/wildstar/client-data/ClientData/Map/<asset>/<name>.<zz><xx>.area`, 15,051 files, 14 GB. The two hex pairs are the grid's z, then x. The zone converter in `dev/` reads them; its docstring gives the format |
| Textures and changing the archives | The `wildstar-hd-textures` skill in `~/Coding/wildstar/.claude/skills` |
| Table helpers | `scripts/`, each run as `python3 -I <script> <arguments>` with its docstring giving them: `english_text.py <text id>...`; `prereq_stats.py <clause type>...` (how Prerequisite rows use a clause type); `prereq_users.py <clause type>...` (the columns that name a Prerequisite row with it); `quest_objectives.py <objective type> [<sample size>]` |

## Running a Ghidra script

```bash
~/Projects/the-genesis-prime/.claude/skills/decoding-the-client/scripts/ghidra.sh Decompile.java <out-file> 140450970 1400a1a80
```

- The first script argument is nearly always the output file; write it to the session's scratch folder. `DumpFunction.java` is the exception: it takes `<address> <out-file> <max instructions>`. `DumpRange.java` takes `<out-file> <max instructions> <address>...` and stops at the first `RET`, so use `DumpFunction` for a function with early returns.
- Each run takes about half a minute, so put several addresses in one call.
- A one-off script goes in the scratch folder, passed in `GHIDRA_EXTRA_SCRIPTS`. Move it to `ghidra/scripts` if it proves reusable.
- The wrapper prints the first script error and the full log's path.

## Recipes

**Message layout from an opcode.** In `register_fn.txt`, find `MOV EDX,0x<opcode>` (lowercase hex) and read the eight lines above it. `[RSP+0x20]` is the writer (the client sends), loaded through RCX just before; when R9 holds a different address, it is not the writer. `[RSP+0x28]` is the reader (the client receives); R8D is the struct size. Decompile the writer. If it says "no function", it is usually a thunk: run `DumpRange.java` on it to find the `JMP`. Read bit sizes from the bit-writer calls the fact file lists.

**What each field means.** Find who sends the message: save the opcode as `0x825` in a file, one per line, then run `FindImmediates.java <out> <that file>`. The sender fills a struct of locals and calls a send function. Map each local's stack offset to the struct offset the writer reads, then follow each value back to its source: a Lua argument, a global, or a Windows API call.

**Lua function to native code.** Run `Strings.java <out> s:FunctionName` to find the name string, then `Refs.java` on its address: the hit is a `{name ptr, fn ptr}` row in a binding table, printed with its neighbours. Decompile the function pointer. The Lua argument readers are in the fact file.

**Lua enum values.** Run `Strings.java` on the enum's name, then `Refs.java` to find the function that registers it. Before a loop that calls 0x1400f06f0, a `LEA` loads the row table and a counter holds the row count. Read the table with `EnumTable.java <out> <table addr> <count> 16`.

**How the client handles a received message.** Start from the handler for the opcode's range in the fact file. Decompile its switch case, then the reader, then whatever raises the Lua event. Ghidra often cannot follow the in-game handler's jump table: read the entry from the file on disk with `python3 -I scripts/jump_table.py <opcode hex>`, then run `DumpRange.java` on the case address to find the call. Any other switch whose table holds 4-byte offsets from the image base reads the same way, with `jump_table.py --table <table address hex> <index>...`.

**What the client does with a spell effect.** A go's effects become client effect objects in 0x140718120, which picks a class by Spell4EffectType. A few types have a class of their own, and most get the default class, whose execute (vtable +0x10) is a bare `RET`. Find the type's `case` there, list its vtable with `VTable.java`, and decompile slot +0x10.

**What the UI does with it.** The UI Lua names arguments and events, which is often the fastest source of field names. Grep `~/Coding/wildstar/ui-extract/ClientData/UI/` for the `*Lib.Function(` call or `RegisterEventHandler("EventName"`. To extract it again (about 20 seconds):

```bash
python3 -I ~/Projects/the-genesis-prime/.claude/skills/decoding-the-client/scripts/wsarchive.py ~/Coding/wildstar/client/WildStar/Patch 'ui/*.lua' ~/Coding/wildstar/ui-extract
```

Asking for `ui/*` instead pulls 1.8 GB of images, and `*` the whole client, about 39 GB.

**Code that shows a message or uses a text.** Run `python3 -I scripts/find_wstring.py "<text>"`. It prints each address where the text occurs, as UTF-16 and as ASCII. Pass those addresses to `DataRefs.java <out> <addr>...` to list every instruction that uses them and its function. To list a function's callers, run `Refs.java` on its entry address.

**Check a data format against a ground truth before trusting it.** Look for a column that already states the answer before reaching for Ghidra. A throwaway reader of the `.area` files placed 88 to 92 percent of spawns in their recorded zone with the grid's z first, and 1 in 26,977 with x first, which settled the file name order.

**Count before stating how common something is.** Use `wstbl.rows` for tables.

## Pitfalls that have cost time

- **Text searches that only see ASCII.** Much of the client's text, error messages included, is UTF-16. `Strings.java` and the macOS `strings` tool find only ASCII; the macOS `strings` has no `-e` option, and with `2>/dev/null` it fails silently. A miss from either proves nothing; use `find_wstring.py`.
- **Hidden float arguments.** The decompiler drops or retypes float arguments (XMM registers), so its parameter list can be wrong. When a value's origin matters, read the caller's disassembly with `DumpRange.java` or `DumpFunction.java`.
- **Hidden float constants.** The decompiler shows a float constant as a data address. Read it with `ReadConst.java <out-file> <address>...`, which prints the dword, float, double and qword there.
- **`FindImmediates` input** needs a `0x` prefix (`Long.decode`); plain `82e` throws.
- **Decompiler output is not ground truth.** Confirm a field's size from the bit-count constant in the writer call, not from the C type Ghidra guessed.
- **Read an exact boundary exactly:** whether a comparison is `<`, `<=` or `==`, a field's bit width, signed or unsigned, and what happens at zero. Those are the facts a server gets wrong.
- **Deprecated items.** An Item2 row with flag 0x4000 is rebuilt by the client from placeholder Item2 74201 (0x1404445d0): its quality and ItemSpecial come from there, so it has no spell and cannot be used.
- **Read a prerequisite type's case from the jump table, not from Ghidra.** Ghidra's case labels on the evaluator's switch are wrong.
- **A unit with no F prompt may be hidden by its own prerequisite.** Read the Creature2 row's `prerequisiteIdAnimState` and evaluate it for the character before blaming the server: a faction clause or a quest state can hide it.
- **`Refs.java` does not always show the in-game dispatcher's cases.** Scan `.text` for E8 and E9 rel32 calls to the function, then map each call site to a `jump_table.py` case.
- **A silent client is not proof the path was skipped.** Use and cast failures show only as a floater over the player for about 1.3 s (0x1403a12a0), never in chat.
- **A comment or a name in code is a claim to check against the client,** never the answer. So is another program's model of a message.
