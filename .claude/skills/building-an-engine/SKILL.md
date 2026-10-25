---
name: building-an-engine
description: Rules for engines - routing client messages, unhandled types, effects, classifiers, the coverage measure, maps. Use when working in an engine area or adding a new game type.
---

# Building an engine

Each engine owns its kind. Which engines exist is decided in Milestone 1; these rules hold for any of them.

Apply every rule to each change, and check the diff against each before it is done.

- Client messages reach their feature rule in one hop, through one routing table.
- The server decides; the client asks. Speed, range, cooldowns, costs, damage and loot are checked server-side.
- Nothing is dropped silently: an unhandled type, message or interaction is logged once per type for each run of a process.
- An effect lands on any unit (caster, creature, player) through one path.
- Each engine has one classifier per type, so a new type is added in one place.
- An engine declares the types it handles, and the coverage measure reads that list. A test checks the declaration.
- The prerequisite engine sees any unit and live state, not a player snapshot.
- One world can have many maps: instances are part of the map design from the start.
