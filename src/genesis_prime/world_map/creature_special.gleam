//// The spells a kind of creature casts besides its attack, as the content load reads
//// them (the creature_special table, genesis_prime/content/creature_special) and
//// checks, and what the kind holds of them (genesis_prime/world_map/creature_kind
//// `Kind.specials`). The client lists no spell for a creature and no cadence
//// (`creature.ai_data`), so each row is a server choice from a retail record, and its
//// cooldown a guess, both marked in the row's `reason`.
////
//// ```
//// creature_special rows ─▶ refusal_of(row, tables) ─▶ Refusal(table: "creature_special", row: RowId(creature_id), rule)
//// creature_kind.select(rows, special_rows, tables) ─▶ refs_of(rows, creature_id) ─▶ Kind.specials
//// ```
////
//// - **A row names a Creature2 the client holds, never row 0**: a special for the default
////   kind would be cast by every creature. A creature with no `creature_kind` row of its own
////   takes the default kind's fields and its own specials (`creature_kind` builds an entry
////   for the union of the two tables' creature ids).
//// - **A row's refusal names its Spell4**: the key is `(creature_id, spell4_id)` and a
////   `RowId` holds one integer, so the sentence carries the Spell4.
//// - **The load refuses** a Spell4 the client lacks; a cooldown below the strike deadline
////   (`strike_tell.deadline_ms`), since two rounds would be open at once; and a spell
////   `creature_attack.special_checked` refuses: no cast time, no readable area, an effect
////   type other than 8 (damage) and 35 (NpcExecutionDelay), no damage phase, several, or
////   one before the last go, a phase flag naming no go, an empty or non-increasing go
////   schedule, a delay row the plan leaves out (aimed at another unit, or with no duration)
////   or one that names a go other than the strike go, a target condition
////   (`spell4CCConditionsIdTarget`) other than 0, and any caster prerequisite the attack
////   rule refuses. A bad row is refused, never left out silently.
//// - **`order_index` is not null and unique for a creature**: it orders the list `chosen`
////   walks (genesis_prime/world_map/creature_fight).

import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list

/// The table's name in a refusal.
pub const table = "creature_special"

/// One row of the creature_special table as the load reads it: the Creature2 id, the
/// Spell4 it casts, its place in the creature's list and the time in milliseconds from a
/// cast's start until it may be cast again.
pub type Row {
  Row(creature_id: Int, spell4_id: Int, order_index: Int, cooldown_ms: Int)
}

/// What a kind holds of one special: the Spell4 and its cooldown. The spawn works the
/// spell out into a `creature_life.Special` (genesis_prime/world_map/spawn).
pub type Ref {
  Ref(spell4_id: Int, cooldown_ms: Int)
}

/// The first rule the row breaks, as the refusal's sentence, or `Error(Nil)` for a row the
/// load takes (as `creature_kind`'s own refusals are read).
pub fn refusal_of(
  row _row: Row,
  tables _tables: table_store.Tables,
) -> Result(String, Nil) {
  panic as "shape: refusal_of is built with the creature_special load"
}

/// The refs of the rows of one creature, in `order_index` order.
pub fn refs_of(
  rows rows: List(Row),
  creature_id creature_id: Int,
) -> List(Ref) {
  rows
  |> list.filter(fn(row) { row.creature_id == creature_id })
  |> list.sort(fn(first, second) {
    int.compare(first.order_index, second.order_index)
  })
  |> list.map(fn(row) {
    Ref(spell4_id: row.spell4_id, cooldown_ms: row.cooldown_ms)
  })
}
