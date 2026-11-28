//// Which creatures take part in combat. A creature the client draws as a lying body is no
//// target of a player's area and fights no one; one a player cannot target that has no attack
//// row of its own fights no one either, though an area may still pick it. A kill objective
//// that names a creature keeps it in both. The load asks it once for each shared combat
//// (`spawn`), and the answers are `creature_combat.Combat.area_pickable` and
//// `creature_combat.Combat.fights`.
////
//// ```
//// the tables' kill objectives ─▶ kill_named    ─▶ the creature ids they name
//// Creature2 row, that set     ─▶ area_pickable ─▶ False: no area picks it (shown)
//// Creature2 row, that set,
//// and whether the kinds hold
//// a row of its own for it     ─▶ fights        ─▶ False: aggroes no one (map ring), no strike or approach
////                                                        starts a fight (creature_fight)
//// ```
////
//// - A creature whose uiFlags has bit 8 is created dead-posed at health 0, whatever health
////   its 0x262 carries, and no health write changes it (`Creature2.uiFlags.bit8`,
////   `0x140456960`, `0x1404602e0`). The server keeps such a creature standing, so the client
////   draws what the data says: a body that does nothing, which no area picks and which fights
////   no one.
//// - A creature whose flags have bit 0 is one a player cannot target: only its own activate
////   spell, or a spell whose cast group names it, reaches it (`Creature2.flags.bit0`,
////   `0x1403b44b0`). The client holds no attack for any creature, so without a row of its
////   own in `creature_kind`, `creature_auto_attack` or `creature_special` (the retail record;
////   the default row 0 is no creature's own) such a creature fights no one: a server choice.
////   The area picks of a player's spell stay as the lying-body rule has them, so a spell whose
////   target group names such a creature still reaches it.
//// - A creature a kill objective names keeps fighting and stays pickable. Which creatures an
////   objective names is the mapping the objective's creatures are placed by
////   (`target_group.placed_creatures`): the creature of a type 2 objective and the creatures
////   its type 8 or 16 TargetGroup lists.
//// - A body that only a faction or race group, a reward pane or a kill script names stays out
////   of combat: the client draws it lying dead, so a player cannot attack it as one of a
////   group's members. The bodies of the "[CORPSE] Nursery" quest objective (QuestObjective
////   18873, Creature2 54312 to 54314, 58 spawns) and of quest giver 11067 (QuestObjective
////   18988) are such bodies.
//// - The creature's faction is not touched: `hostile_to` and `attackable` stay the faction's,
////   so a click, a quest offer and a refusal code read what they read for any creature.

import genesis_prime/game/objective_kind
import genesis_prime/game/target_group
import genesis_prime/gap
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import gleam/int
import gleam/list
import gleam/set.{type Set}

/// The Creature2 uiFlags bit the client draws a lying body by (`Creature2.uiFlags.bit8`).
const drawn_dead_flag = 0x100

/// The Creature2 flags bit that lets only a creature's own activate spell, or a spell whose
/// cast group names it, target it (`Creature2.flags.bit0`, `0x1403b44b0`).
const untargetable_flag = 0x1

/// The Creature2 ids the kill objectives of the tables name, for `fights`, read once for a
/// load.
pub fn kill_named(tables tables: table_store.Tables) -> Set(Int) {
  quest_objective.all(tables)
  |> list.filter_map(fn(row) {
    objective_kind.placed_target(objective_kind.of_row(row))
  })
  |> list.flat_map(fn(placed) {
    target_group.placed_creatures(tables:, placed:)
  })
  |> set.from_list
}

/// Whether a player's area may pick the creature of the Creature2 row: a creature the client
/// draws as a lying body is no pick unless a kill objective names it (`kill_named`).
pub fn area_pickable(
  kill_named kill_named: Set(Int),
  creature creature: Creature2,
) -> Bool {
  int.bitwise_and(creature.ui_flags, drawn_dead_flag) == 0
  || set.contains(kill_named, creature.id)
}

/// Whether the creature of the Creature2 row takes part in combat. A creature a kill objective
/// names does (`kill_named`). Any other does not when the client draws it as a lying body, or
/// when its flags have bit 0 (a player cannot target it) and it has no attack row of its own
/// (`has_attack_row`, `creature_kind.has_row`): the client holds no attack for a creature, so
/// only a retail record gives one.
pub fn fights(
  kill_named kill_named: Set(Int),
  has_attack_row has_attack_row: Bool,
  creature creature: Creature2,
) -> Bool {
  let untargetable_and_unarmed =
    int.bitwise_and(creature.flags, untargetable_flag) != 0 && !has_attack_row
  area_pickable(kill_named:, creature:)
  && { set.contains(kill_named, creature.id) || !untargetable_and_unarmed }
}

/// What the rule leaves undone, for the coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Creatures that cannot be attacked and strike",
      missing: "a creature whose Creature2 flags have bit 0 and that has no attack row of its own (kind, auto-attack or special) never aggroes, approaches, strikes or casts, since the client holds no creature attack and a player cannot target it. The retail record (database genesis_929r) gives a row to 64 such creatures that are hostile to a player and spawned in the world database, listed by Creature2 id in the test over them; 4 of them a kill objective names, so those fight whatever the rows, and in a database without the retail rows the other 60 strike no one. A hazard, mine or security beam with no retail row has no known strike: its source is an open question",
    ),
    gap.Entry(
      area: "Creatures drawn dead",
      missing: "a creature drawn as a lying body is still struck by a single-target strike: it takes damage, dies, pays kill credit and is thrown, because only the area pick (shown) reads `area_pickable` and only the fight's start reads `fights`; the client refuses a player's cast at a unit whose Creature2 flags have bit 0 (0x1403b44b0), so only a creature's own process or a crafted client reaches one",
    ),
  ]
}
