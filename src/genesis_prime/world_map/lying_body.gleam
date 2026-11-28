//// Which creatures take part in combat: a creature the client draws as a lying body does
//// not, unless a kill objective names it. The load asks it once for each shared combat
//// (`spawn`), and the answer is `creature_life.Combat.fights`.
////
//// ```
//// the tables' kill objectives ─▶ kill_named ─▶ the creature ids they name
//// Creature2 row + that set    ─▶ fights     ─▶ False: aggroes no one (map ring), no strike or approach
////                                                     starts a fight (creature_fight), no area picks it (shown)
////                                              True:  as every creature fights
//// ```
////
//// - A creature whose uiFlags has bit 8 is created dead-posed at health 0, whatever health
////   its 0x262 carries, and no health write changes it (`Creature2.uiFlags.bit8`,
////   `0x140456960`, `0x1404602e0`). The server keeps such a creature standing, so the client
////   draws what the data says: a body that does nothing.
//// - A creature a kill objective names keeps fighting. Which creatures an objective names is
////   the mapping the objective's creatures are placed by (`target_group.placed_creatures`):
////   the creature of a type 2 objective and the creatures its type 8 or 16 TargetGroup lists.
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

/// Whether the creature of the Creature2 row takes part in combat: a creature the client
/// draws as a lying body does not, unless a kill objective names it (`kill_named`).
pub fn fights(
  kill_named kill_named: Set(Int),
  has_attack_row has_attack_row: Bool,
  creature creature: Creature2,
) -> Bool {
  {
    int.bitwise_and(creature.ui_flags, drawn_dead_flag) == 0
    || set.contains(kill_named, creature.id)
  }
  && has_attack_row
}

/// What the rule leaves undone, for the coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Creatures that cannot be attacked",
      missing: "a creature whose Creature2 flags have bit 0 and not uiFlags bit 8 (a guard, a trap, a quest giver, a vendor, a captive) aggroes and fights a player on sight, though the client refuses every cast of a player's at it that has no cast group: only a spell its cast group names, or its own activate spell, reaches it; of the world database's 48,170 NonPlayer spawns, 6,216 (2,337 creature rows) are Hostile to a player faction, have no kill objective and are such a creature, 198 of them with retail-recorded spells",
    ),
    gap.Entry(
      area: "Creatures drawn dead",
      missing: "a creature drawn as a lying body is still struck by a single-target strike: it takes damage, dies, pays kill credit and is thrown, because only the area pick (shown) and the fight's start read `fights`; the client refuses a player's cast at a unit whose Creature2 flags have bit 0 (0x1403b44b0), so only a creature's own process or a crafted client reaches one",
    ),
  ]
}
