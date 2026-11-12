//// What the server chooses for each kind of creature, as the content load checks
//// it: how long a creature that died stays dead, how long a spawn whose creature
//// crashed waits for its next one, and the creature's own attack: the Spell4 it
//// casts and how often, and how long the cast takes. A creature has the kind of its
//// Creature2 row when the table has one, and the default row 0 otherwise.
////
//// ```
//// creature_kind rows (genesis_prime/content/creature_kind) ─▶ select(rows, tables)
////   a row of a Creature2 id the client does not hold      ─▶ Refusal
////   a respawn time below the strike deadline              ─▶ Refusal
////   an attack spell the client's Spell4 does not hold     ─▶ Refusal
////   an attack interval below the strike deadline          ─▶ Refusal
////   an attack spell whose caster prerequisite (prerequisiteIdCasterCast)
////     holds a condition of a type other than 15           ─▶ Refusal naming the row and the type
////   a damage effect of the attack spell whose caster
////     prerequisite is of a type the server does not evaluate ─▶ Refusal
////   a guard without an opening, or an opening without a guard ─▶ Refusal
////   a guard or an opening whose effects the creature does not apply
////     (genesis_prime/world_map/creature_guard_spells `guard_of`)  ─▶ Refusal naming the sentence
////   no row 0                                              ─▶ Refusal
////   otherwise ─▶ Kinds ─▶ kind_of(kinds, creature2 id)    a map's and a creature's reading
//// ```
////
//// - **Row 0 is the default** every creature without a row of its own takes; the
////   table has to hold it, so a creature always has a kind, and a start without it
////   stops.
//// - **Who reads it.** A creature starts its corpse timer from its kind's respawn time, and a
////   map waits that long before it starts a spawn's creature again after a crash, so the
////   one number is the only source of both (genesis_prime/world_map/creature,
////   genesis_prime/world_map/map).
//// - **The respawn time** is a server choice: the client holds none
////   (`death.creature_respawn`). A time longer than the idle stop is allowed: a dead
////   creature told to retire stops at its respawn (genesis_prime/world_map/creature).
//// - **The attack spell** has no link in the client to the creature that casts it
////   (`Spell4.5649`), so it is a server choice. Its damage effects are chosen by
////   their caster prerequisite, which the server evaluates only for type 179, the
////   unit's difficulty (`0x14049eeb0`); a spell with any other type would apply both
////   effects or neither, so the load refuses it.
//// - **The cast time** is the attack spell's own (`Spell4.castTime`, in milliseconds), read
////   with the creature's attack when a spawn starts (genesis_prime/world_map/spawn): 0 is an
////   attack that strikes at once, as every creature's did, and above 0 the creature charges
////   (genesis_prime/world_map/creature_fight).
//// - **The cast prerequisite** (`Spell4.prerequisiteIdCasterCast`) is answered for one
////   condition of type 15, `TargetOfLiveCast`, which is the cast the charge itself is; any
////   other prerequisite is a state a creature does not have, so a spell holding one is
////   refused and not cast as if it passed (genesis_prime/world_map/creature_attack).
//// - **The guard and the opening** are a pair of Spell4 ids, both or neither, a server choice: the
////   client links the creature to neither (`Spell4.85472.trigger`). The kind holds them read
////   (`Kind.guard`), so a creature's start reads no table for them (genesis_prime/world_map/creature_guard).
//// - **The attack interval** is a server choice, never below the strike deadline,
////   so a creature has at most one strike round open (genesis_prime/world_map/creature_fight).
//// - **Every refusal is collected**, one bad row beside its neighbours, as the
////   other content tables' are (genesis_prime/content).

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/game/strike_tell
import genesis_prime/table/creature2
import genesis_prime/table/id.{type Spell4Id, Creature2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/world_map/creature_attack
import genesis_prime/world_map/creature_guard_spells.{type Guard}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The table's name in a refusal.
const table = "creature_kind"

/// One row of the creature_kind table as the load reads it: the Creature2 id the
/// row is for (0 for the default), the respawn time in milliseconds, the
/// creature's attack: its Spell4 and the time between two of its casts in
/// milliseconds, and its guard and opening Spell4s, both or neither.
pub type Row {
  Row(
    creature_id: Int,
    respawn_ms: Int,
    attack_spell4_id: Int,
    attack_interval_ms: Int,
    guard_spell4_id: Option(Int),
    opening_spell4_id: Option(Int),
  )
}

/// What the server chose for a kind of creature: the guard is none for a creature
/// that takes damage always.
pub type Kind {
  Kind(
    respawn_ms: Int,
    attack_spell4_id: Spell4Id,
    attack_interval_ms: Int,
    guard: Option(Guard),
  )
}

/// The kinds the load put in its term: the default and each creature that has a
/// row of its own.
pub type Kinds {
  Kinds(default: Kind, by_creature: Dict(Int, Kind))
}

/// The kinds of the rows, or every row the load refuses: a Creature2 id that has no
/// row in the client's table, a respawn time or an attack interval below the strike
/// deadline (1000 ms), an attack spell the client's Spell4 does not hold, whose
/// damage effects carry a caster prerequisite of a type other than 179, or whose
/// `prerequisiteIdCasterCast` holds a condition of a type other than 15, and a table
/// with no default row.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Kinds, List(Refusal)) {
  let default = list.find(rows, fn(row) { row.creature_id == 0 })
  let missing_default = case default {
    Ok(..) -> []
    Error(Nil) -> [
      Refusal(
        table: table,
        row: RowId(0),
        rule: "the table has no default row 0, which every creature without a row of its own takes",
      ),
    ]
  }
  let refused =
    list.filter_map(rows, fn(row) {
      refusal_of(row:, tables:)
      |> result.map(fn(rule) {
        Refusal(table:, row: RowId(row.creature_id), rule:)
      })
    })
  case list.append(missing_default, refused) {
    [] -> {
      let assert Ok(kinds) = kinds_of(rows:, tables:)
        as "no refusal means the default row is there"
      Ok(kinds)
    }
    refusals -> Error(refusals)
  }
}

/// The kinds of the rows `select` takes, leaving out the ones it refuses, or
/// `Error(Nil)` when the default row is missing or refused. The content load checks
/// the spawns with these when it refuses a kind row, so the one start names a bad
/// spawn too (genesis_prime/content).
pub fn taken(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Kinds, Nil) {
  kinds_of(
    rows: list.filter(rows, fn(row) {
      result.is_error(refusal_of(row:, tables:))
    }),
    tables:,
  )
}

/// The kinds of the rows, or `Error(Nil)` with no default row among them.
fn kinds_of(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Kinds, Nil) {
  use default <- result.map(list.find(rows, fn(row) { row.creature_id == 0 }))
  Kinds(
    default: kind_of_row(row: default, tables:),
    by_creature: list.filter(rows, fn(row) { row.creature_id != 0 })
      |> list.map(fn(row) { #(row.creature_id, kind_of_row(row:, tables:)) })
      |> dict.from_list,
  )
}

/// The first rule the row breaks, in the order of `select`'s doc, or `Error(Nil)`
/// for a row the load takes.
fn refusal_of(
  row row: Row,
  tables tables: table_store.Tables,
) -> Result(String, Nil) {
  let deadline = int.to_string(strike_tell.deadline_ms)
  let checks = [
    fn() {
      case
        row.creature_id != 0
        && result.is_error(creature2.get(
          tables:,
          id: Creature2Id(row.creature_id),
        ))
      {
        True -> Ok("the client's Creature2 table has no such creature")
        False -> Error(Nil)
      }
    },
    fn() {
      case row.respawn_ms < strike_tell.deadline_ms {
        True ->
          Ok(
            "a respawn time of "
            <> int.to_string(row.respawn_ms)
            <> " ms is below the strike deadline of "
            <> deadline
            <> " ms",
          )
        False -> Error(Nil)
      }
    },
    fn() {
      case spell4.get(tables:, id: Spell4Id(row.attack_spell4_id)) {
        Error(Nil) ->
          Ok(
            "the attack spell "
            <> int.to_string(row.attack_spell4_id)
            <> " has no row in the client's Spell4 table",
          )
        Ok(..) -> Error(Nil)
      }
    },
    fn() {
      case row.attack_interval_ms < strike_tell.deadline_ms {
        True ->
          Ok(
            "an attack interval of "
            <> int.to_string(row.attack_interval_ms)
            <> " ms is below the strike deadline of "
            <> deadline
            <> " ms, so two of the creature's strike rounds would be open at once",
          )
        False -> Error(Nil)
      }
    },
    fn() {
      case creature_attack.evaluated(tables:, spell4_id: row.attack_spell4_id) {
        Error(unevaluated) -> Ok(creature_attack.describe(unevaluated:))
        Ok(Nil) -> Error(Nil)
      }
    },
    fn() {
      case row.guard_spell4_id, row.opening_spell4_id {
        Some(guard_spell4_id), Some(opening_spell4_id) ->
          case
            creature_guard_spells.guard_of(
              guard_spell4_id:,
              opening_spell4_id:,
              tables:,
            )
          {
            Error(unapplied) -> Ok(creature_guard_spells.describe(unapplied:))
            Ok(..) -> Error(Nil)
          }
        None, None -> Error(Nil)
        Some(..), None | None, Some(..) ->
          Ok("a guard and an opening are both set or both left out")
      }
    },
  ]
  list.find_map(checks, fn(check) { check() })
}

fn kind_of_row(row row: Row, tables tables: table_store.Tables) -> Kind {
  Kind(
    respawn_ms: row.respawn_ms,
    attack_spell4_id: Spell4Id(row.attack_spell4_id),
    attack_interval_ms: row.attack_interval_ms,
    guard: case row.guard_spell4_id, row.opening_spell4_id {
      Some(guard_spell4_id), Some(opening_spell4_id) -> {
        let assert Ok(guard) =
          creature_guard_spells.guard_of(
            guard_spell4_id:,
            opening_spell4_id:,
            tables:,
          )
          as "the load checked the guard before it took the row"
        Some(guard)
      }
      Some(..), None | None, Some(..) | None, None -> None
    },
  )
}

/// The kind of a creature: its own row's when it has one, else the default.
pub fn kind_of(kinds kinds: Kinds, creature2_id creature2_id: Int) -> Kind {
  dict.get(kinds.by_creature, creature2_id)
  |> result.unwrap(kinds.default)
}
