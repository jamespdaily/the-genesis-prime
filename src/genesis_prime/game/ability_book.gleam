//// The abilities a character holds at a level, as the ability bag the client's press names
//// by index: the class's level-1 abilities, its innate, then each ability the level has
//// reached. The bag is a function of the class and the level alone, so a character that
//// levels in a session and one that logs in at that level hold the same bag in the same
//// order, and nothing about the bag is saved.
////
//// ```
//// Loadout (abilities, innate, later) + level ─▶ bag(level) ─▶ 0x0111 per slot, 0x01A0 of the book
//// a level rise old ─▶ new                   ─▶ granted(old, new) ─▶ 0x0111 from slot length(bag(old)), 0x01A0
//// ```
////
//// - **The bag** is the level-1 abilities in bar order, the innate at the index the
////   abilities number (3), then the later abilities whose level is at or below the character's, by
////   level then SpellLevel id (genesis_prime/game/loadout). The client's own check of whether an
////   ability is available asks the same rows against the unit's level (`0x1403bb040`).
//// - **A rise grants** the later abilities above the old level and at or below the new one,
////   in the bag's order, so the bag at a level is the bag at a lower level followed by what
////   the rise between them grants.
//// - **A row with a prerequisite** is not a level's grant: the load keeps none of them
////   (`SpellLevel.spell4Id.no_prerequisite`).
//// - **An ability the server cannot plan** is in the bag and in the book like any
////   other, and a press of it is refused unknown (`cast_press.ability_at`; the gap
////   closes with issue #1003);
////   `spell_plan.unplanned` lists them, and `give_unplanned_abilities` in
////   genesis_prime/table/loader/derivation holds the one switch that leaves them out.

import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/table/id.{type Spell4BaseId}
import gleam/list
import gleam/option.{None, Some}

/// The ability bag at a level, as Spell4Base ids by bag index. A press names a bag index.
pub fn bag(loadout loadout: Loadout, level level: Int) -> List(Spell4BaseId) {
  let start = case loadout.innate {
    Some(held) -> list.append(loadout.abilities, [held.active_base])
    None -> loadout.abilities
  }
  list.append(start, granted(loadout:, from_level: 1, to_level: level))
}

/// The abilities a rise from one level to a higher one gives, in bag order; none for a
/// level that is not higher.
pub fn granted(
  loadout loadout: Loadout,
  from_level from_level: Int,
  to_level to_level: Int,
) -> List(Spell4BaseId) {
  loadout.later
  |> list.filter(fn(unlock) {
    unlock.level > from_level && unlock.level <= to_level
  })
  |> list.map(fn(unlock) { unlock.base })
}

/// How many items the bag holds at a level: the next free bag index.
pub fn size(loadout loadout: Loadout, level level: Int) -> Int {
  list.length(bag(loadout:, level:))
}
