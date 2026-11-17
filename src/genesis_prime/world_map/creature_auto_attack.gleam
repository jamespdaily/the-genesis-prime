//// The auto-attacks a kind of creature strikes with in turn, as the content load reads
//// them (the creature_auto_attack table, genesis_prime/content/creature_auto_attack) and
//// checks, and what the kind holds of them (genesis_prime/world_map/creature_kind
//// `Kind.attack_spell4_id`, the first, and `Kind.alternate_spell4_ids`, the rest). The
//// client's Spell4 descriptions mark a creature's auto-attacks (`[AUTO-ATTACK]`,
//// "Auto-Attack #1", "#2") but no client table links a creature to a spell
//// (`creature.ai_data`), so each row is a server choice from a retail record, and the
//// order of several marked a guess in the row's `reason`.
////
//// ```
//// creature_auto_attack rows ─▶ refusal_of(row, tables, creatures_with_a_kind_row) ─▶ Refusal(table: "creature_auto_attack", row: RowId(creature_id), rule)
//// creature_kind.select(rows, special_rows, auto_attack_rows, tables) ─▶ refs_of(rows, creature_id) ─▶ the kind's attack and alternates
//// ```
////
//// - **A row names a Creature2 the client holds, never row 0**: an auto-attack for the
////   default kind would be struck by every creature. A creature with no `creature_kind` row
////   of its own takes the default kind's fields and its own auto-attacks.
//// - **A creature with auto-attack rows has no `creature_kind` row of its own**: the kind
////   row names an attack too, and one place names a creature's attack.
//// - **A row's refusal names its Spell4**: the key is `(creature_id, spell4_id)` and a
////   `RowId` holds one integer, so the sentence carries the Spell4.
//// - **The load refuses** a Spell4 the client lacks; a spell with a cast time, since an
////   auto-attack strikes at once (a spell with a cast bar is a special,
////   genesis_prime/world_map/creature_special); a spell `creature_attack.evaluated` refuses
////   (an innate cost, a periodic damage row, a prerequisite of a type the attack rule does
////   not read); and a spell whose damage formula the creature rule does not read for the
////   creature's difficulty (`creature_attack.loadable`), which the spawn load would refuse
////   later. A bad row is refused, never left out silently.
//// - **`order_index` is not null and unique for a creature**: the creature strikes the
////   first listed auto-attack first, then each next, then the first again
////   (genesis_prime/world_map/creature_fight `chosen`).

import genesis_prime/table/creature2
import genesis_prime/table/id.{type Spell4Id, Creature2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/world_map/creature_attack
import gleam/int
import gleam/list
import gleam/set.{type Set}

/// The table's name in a refusal.
pub const table = "creature_auto_attack"

/// One row of the creature_auto_attack table as the load reads it: the Creature2 id, the
/// Spell4 it strikes with and its place in the creature's turn.
pub type Row {
  Row(creature_id: Int, spell4_id: Int, order_index: Int)
}

/// The first rule the row breaks, as the refusal's sentence, or `Error(Nil)` for a row the
/// load takes (as `creature_special.refusal_of`). `kind_creature_ids` are the Creature2 ids
/// of the creature_kind rows. The sentence names the Spell4, since the key `RowId` holds only
/// the creature.
pub fn refusal_of(
  row row: Row,
  tables tables: table_store.Tables,
  kind_creature_ids kind_creature_ids: Set(Int),
) -> Result(String, Nil) {
  let spell = int.to_string(row.spell4_id)
  let creature = int.to_string(row.creature_id)
  let checks = [
    fn() {
      case row.creature_id == 0 {
        True ->
          Ok(
            "the default kind, row 0, would strike with the auto-attack of Spell4 "
            <> spell
            <> " for every creature",
          )
        False -> Error(Nil)
      }
    },
    fn() {
      case creature2.get(tables:, id: Creature2Id(row.creature_id)) {
        Error(Nil) ->
          Ok(
            "the client's Creature2 table has no creature "
            <> creature
            <> ", the striker of Spell4 "
            <> spell,
          )
        Ok(..) -> Error(Nil)
      }
    },
    fn() {
      case spell4.get(tables:, id: Spell4Id(row.spell4_id)) {
        Error(Nil) ->
          Ok(
            "the auto-attack Spell4 "
            <> spell
            <> " of Creature2 "
            <> creature
            <> " has no row in the client's Spell4 table",
          )
        Ok(..) -> Error(Nil)
      }
    },
    fn() {
      case set.contains(kind_creature_ids, row.creature_id) {
        True ->
          Ok(
            "Creature2 "
            <> creature
            <> " has a creature_kind row naming its attack, so its auto-attack Spell4 "
            <> spell
            <> " would be a second place that names it",
          )
        False -> Error(Nil)
      }
    },
    fn() {
      case spell4.get(tables:, id: Spell4Id(row.spell4_id)) {
        Ok(found) if found.cast_time > 0 ->
          Ok(
            "the auto-attack Spell4 "
            <> spell
            <> " of Creature2 "
            <> creature
            <> " has a cast time of "
            <> int.to_string(found.cast_time)
            <> " ms (castTime), and an auto-attack strikes at once",
          )
        Ok(..) | Error(Nil) -> Error(Nil)
      }
    },
    fn() {
      case creature_attack.evaluated(tables:, spell4_id: row.spell4_id) {
        Error(unevaluated) ->
          Ok(
            "the auto-attack Spell4 "
            <> spell
            <> " of Creature2 "
            <> creature
            <> " is refused: "
            <> creature_attack.describe(unevaluated:),
          )
        Ok(Nil) -> Error(Nil)
      }
    },
    fn() {
      let assert Ok(found) =
        creature2.get(tables:, id: Creature2Id(row.creature_id))
        as "the creature's own check came first"
      case
        creature_attack.loadable(
          tables:,
          spell4_id: row.spell4_id,
          difficulty: found.creature2_difficulty_id,
        )
      {
        Error(unevaluated) ->
          Ok(
            "the auto-attack Spell4 "
            <> spell
            <> " of Creature2 "
            <> creature
            <> " is refused for its difficulty "
            <> int.to_string(found.creature2_difficulty_id)
            <> ": "
            <> creature_attack.describe(unevaluated:),
          )
        Ok(Nil) -> Error(Nil)
      }
    },
  ]
  list.find_map(checks, fn(check) { check() })
}

/// The Spell4 ids of the rows of one creature, in `order_index` order: the first is the
/// creature's lead attack and the rest its alternates.
pub fn refs_of(
  rows rows: List(Row),
  creature_id creature_id: Int,
) -> List(Spell4Id) {
  rows
  |> list.filter(fn(row) { row.creature_id == creature_id })
  |> list.sort(fn(first, second) {
    int.compare(first.order_index, second.order_index)
  })
  |> list.map(fn(row) { Spell4Id(row.spell4_id) })
}
