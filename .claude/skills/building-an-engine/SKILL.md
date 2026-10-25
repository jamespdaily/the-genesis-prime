---
name: building-an-engine
description: How to build and extend an engine in the-genesis-prime - the modules that own one kind of client type for every feature (prerequisites, quest objectives, spell effects, unit types) and the routing of client messages - with one classifier per type, one path for every effect, declared types, logging what is unhandled, server-side checks, maps and instances, and the coverage measure that counts what the client uses. Use when working on an engine area, adding a game type, routing a client message, or reading or posting the coverage measure, even if the request only names one prerequisite or effect type.
---

# Building an engine

Each engine owns its kind. A feature never does an engine's work: the main debt of earlier code was missing shared pieces, so features checked conditions and applied effects themselves, in drifting copies. Which engines exist is a starting default; these rules hold for any of them.

## The kinds the client uses

| Kind | Client column | Weight |
|---|---|---|
| Spell effect types | Spell4Effects `effectType` (type 0, no effect, left out) | Spell4Effects rows of the type |
| Prerequisite types | Prerequisite `prerequisiteTypeId0` to `2` (type 0, an empty clause, left out) | Clause slots of the type |
| Quest objective types | QuestObjective `type` | QuestObjective rows of the type |
| Unit types | Creature2 `CreationTypeEnum` (type 0, NonPlayer, counted) | Creature2 rows of the type |
| Client messages | Every opcode the client sends | One each |

## Rules

- **An engine decodes its type, decides what it does, and applies it.** A feature calls the engine and never re-implements a check or an effect. Effects once landed on units in three drifting copies, and a creature took only damage.
- **Each engine has one classifier per type,** so a new type is added in one place. Five one-question functions each matched all 20 effect types before.
- **An effect lands on any unit (caster, creature, player) through one path.** Adding one effect type once touched 19 places.
- **An engine declares the types it handles,** and the coverage measure reads that list. A test holds the list to the classifier, so a type cannot be declared without a case.
- **The prerequisite engine sees any unit and live state, not a player snapshot.** Quests, the tutorial and creature spells each once checked conditions by hand.
- **One world can have many maps.** Instances are part of the map design from the start; one map per world blocked dungeons, expeditions and housing.
- **Client messages reach their feature rule in one hop, through one routing table.** Three hops and about 237 silent message types came before.
- **The server decides; the client asks.** Speed, range, cooldowns and costs are checked server-side, since any value the client sends can be forged.

## Unhandled types

**Nothing is dropped silently.** An unhandled type, message or interaction is logged once per type for each run of a process, with the type's number. Once per type keeps about 237 unrouted message types from flooding a per-message log, and the log line is what makes "missing" a yes-or-no question (`CLAUDE.md`).

An unhandled type stays `Other(id)` until a decode in the fact file says what the client does with it. Its engine then gains a named case, its classifier entry, its declared type and its tests, in one change.

## Adding a type

1. Search the fact file for the type's number. When it has no record, use the decoding-the-client skill first.
2. Count the client's rows of the type, and read a sample of them with their owners: which spells, quests or creatures use it, and with what values.
3. Write the test list from those rows: what the type does, its edge values, and an unknown id inside it.
4. Add the named case, the classifier entry and the declared type, then the behaviour.
5. Run the coverage measure and post its row for the kind on the issue.

## The coverage measure

The coverage measure prints one Markdown report, ready to post as an issue comment: the date and commit, then one row per kind with the types the client uses, how many are handled, read only and missing, and each class's share of the kind's weight. A collapsed section per kind lists every type that is not handled, heaviest first.

- **Handled:** the engine declares it.
- **Read only:** decoded into a named case, but not declared, so the rules treat it as unknown.
- **Missing:** decoded as `Other(id)`.

Post every run on the issue it measures. A milestone's end condition reads its numbers, so a number that is not posted does not count.
