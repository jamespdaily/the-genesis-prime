---
name: building-an-engine
description: Rules for engines - routing client messages, unhandled types, effects, classifiers, the coverage measure, maps. Use when working in an engine area or adding a new game type.
---

# Building an engine

An engine is the one module that owns a kind of game data: it decodes, decides and applies it. Which engines exist is decided in Milestone 1; these rules hold for any of them.

Apply every rule to each change, and check the diff against each before it is done.

- Client messages reach their feature rule in one hop, through one routing table.
- The server decides; the client asks. Speed, range, cooldowns, costs, damage and loot are checked server-side.
- Nothing is dropped silently: an unhandled type, message or interaction is logged once per type for each run of a process.
- An effect lands on any unit (caster, creature, player) through one path.
- Each engine has one classifier per type, so a new type is added in one place.
- An engine declares the types it handles, and the coverage measure reads that list. A test checks the declaration.
- The prerequisite engine sees any unit and live state, not a player snapshot.
- One world can have many maps: a map is keyed by world and instance (the designing-processes skill).
- A feature calls the engine for its kind; it never re-implements a check or an effect.
- Scripted content is data, or a pure script module looked up by id. No creature, quest or spell id is written into a rule.
- A game master command checks the account's permission in its rule before it acts, and each use is logged. A new account has no permissions.
