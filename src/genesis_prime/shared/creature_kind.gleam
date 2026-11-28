//// What the server chooses for each kind of creature, as the content load checks
//// it: how long a creature that died stays dead, how long a spawn whose creature
//// crashed waits for its next one, and the creature's own attack: the Spell4 it
//// casts and how often, and how long the cast takes. A creature has the kind of its
//// Creature2 row when the table has one, and the default row 0 otherwise.
////
//// ```
//// creature_kind rows (genesis_prime/content/creature_kind) ─▶ select(rows, special_rows, tables)
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
////     (genesis_prime/shared/creature_guard_spells `guard_of`)  ─▶ Refusal naming the sentence
////   no row 0                                              ─▶ Refusal
////   a creature_special row the client's tables refuse     ─▶ Refusal naming the special's Spell4
////     (genesis_prime/shared/creature_special `refusal_of`)
////   a creature_auto_attack row the client's tables refuse ─▶ Refusal naming the auto-attack's Spell4
////     (genesis_prime/shared/creature_auto_attack `refusal_of`)
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
////   refused and not cast as if it passed (genesis_prime/shared/creature_attack).
//// - **The guard and the opening** are a pair of Spell4 ids, both or neither, a server choice: the
////   client links the creature to neither (`Spell4.85472.trigger`). The kind holds them read
////   (`Kind.guard`), so a creature's start reads no table for them (genesis_prime/world_map/creature_guard).
//// - **The attack interval** is a server choice, never below the strike deadline,
////   so a creature has at most one strike round open (genesis_prime/world_map/creature_fight).
//// - **The specials** (genesis_prime/shared/creature_special) are the spells a kind casts
////   besides its attack, in the order the creature tries them. A creature with specials and no
////   row of its own takes the default row's fields and its own specials, so `by_creature`
////   holds the creatures of both tables. `taken` keeps the specials the load takes.
//// - **The auto-attacks** (genesis_prime/shared/creature_auto_attack) are the spells a creature
////   strikes with in turn. A creature with some and no row of its own takes the default row's
////   fields, its first auto-attack as `attack_spell4_id` and the rest as `alternate_spell4_ids`;
////   a creature with none keeps the attack of its row, the default's 5649 unless it names
////   another. A creature with both auto-attack rows and a row of its own is refused.
//// - **Every refusal is collected**, one bad row beside its neighbours, as the
////   other content tables' are (genesis_prime/content).

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/shared/creature_attack
import genesis_prime/shared/creature_auto_attack
import genesis_prime/shared/creature_guard_spells.{type Guard}
import genesis_prime/shared/creature_special
import genesis_prime/shared/spell_plan
import genesis_prime/shared/strike_tell
import genesis_prime/table/creature2
import genesis_prime/table/id.{type Spell4Id, Creature2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set

/// The table's name in a refusal.
const table = "creature_kind"

/// One row of the creature_kind table as the load reads it: the Creature2 id the
/// row is for (0 for the default), the respawn time in milliseconds, the
/// creature's attack: its Spell4 and the time between two of its casts in
/// milliseconds, and its guard and opening Spell4s, which the table's
/// `creature_kind_guard_and_opening_together` holds both set or both left out.
pub type Row {
  Row(
    creature_id: Int,
    respawn_ms: Int,
    attack_spell4_id: Int,
    attack_interval_ms: Int,
    guard: Option(GuardSpells),
  )
}

/// The two Spell4s a creature kind row names for its guard: the guard spell and the
/// opening spell that ends it (genesis_prime/shared/creature_guard_spells).
pub type GuardSpells {
  GuardSpells(guard_spell4_id: Int, opening_spell4_id: Int)
}

/// What the server chose for a kind of creature: the guard is none for a creature
/// that takes damage always; `attack_spell4_id` is the lead attack, the creature's first
/// auto-attack, and `alternate_spell4_ids` the auto-attacks it strikes with after it in
/// turn, empty for a creature with one attack (genesis_prime/shared/creature_auto_attack);
/// `specials` are the spells it casts besides its attacks, in the order it tries them
/// (genesis_prime/shared/creature_special).
pub type Kind {
  Kind(
    respawn_ms: Int,
    attack_spell4_id: Spell4Id,
    alternate_spell4_ids: List(Spell4Id),
    attack_interval_ms: Int,
    guard: Option(Guard),
    specials: List(creature_special.Ref),
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
/// with no default row. `special_rows` are the creature_special rows and
/// `auto_attack_rows` the creature_auto_attack rows: each `creature_special.refusal_of` and
/// `creature_auto_attack.refusal_of` refuses is collected with the rest.
pub fn select(
  rows rows: List(Row),
  special_rows special_rows: List(creature_special.Row),
  auto_attack_rows auto_attack_rows: List(creature_auto_attack.Row),
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
    refusals_of(
      table:,
      refused: list.filter_map(rows, fn(row) {
        refusal_of(row:, tables:)
        |> result.map(fn(rule) { #(row.creature_id, rule) })
      }),
    )
  let special_refused =
    refusals_of(
      table: creature_special.table,
      refused: list.map(special_refusals(special_rows:, tables:), fn(refused) {
        #({ refused.0 }.creature_id, refused.1)
      }),
    )
  let auto_attack_refused =
    refusals_of(
      table: creature_auto_attack.table,
      refused: list.map(
        auto_attack_refusals(rows:, auto_attack_rows:, tables:),
        fn(refused) { #({ refused.0 }.creature_id, refused.1) },
      ),
    )
  case
    list.flatten([
      missing_default,
      refused,
      special_refused,
      auto_attack_refused,
    ])
  {
    [] -> {
      let assert Ok(kinds) =
        kinds_of(rows:, special_rows:, auto_attack_rows:, tables:)
        as "no refusal means the default row is there and every guard holds"
      Ok(kinds)
    }
    refusals -> Error(refusals)
  }
}

/// The load's refusals of a table's rows, each given by its creature's Creature2 id and
/// the sentence of the rule it breaks.
fn refusals_of(
  table table: String,
  refused refused: List(#(Int, String)),
) -> List(Refusal) {
  list.map(refused, fn(row) { Refusal(table:, row: RowId(row.0), rule: row.1) })
}

/// The kinds of the rows `select` takes, leaving out the ones it refuses, or
/// `Error(Nil)` when the default row is missing or refused. The content load checks
/// the spawns with these when it refuses a kind row, so the one start names a bad
/// spawn too (genesis_prime/content). It keeps the specials of the rows `select` takes.
pub fn taken(
  rows rows: List(Row),
  special_rows special_rows: List(creature_special.Row),
  auto_attack_rows auto_attack_rows: List(creature_auto_attack.Row),
  tables tables: table_store.Tables,
) -> Result(Kinds, Nil) {
  let refused_specials = special_refusals(special_rows:, tables:)
  let refused_auto_attacks =
    auto_attack_refusals(rows:, auto_attack_rows:, tables:)
  kinds_of(
    rows: list.filter(rows, fn(row) {
      result.is_error(refusal_of(row:, tables:))
    }),
    special_rows: list.filter(special_rows, fn(row) {
      !list.any(refused_specials, fn(refused) { refused.0 == row })
    }),
    auto_attack_rows: list.filter(auto_attack_rows, fn(row) {
      !list.any(refused_auto_attacks, fn(refused) { refused.0 == row })
    }),
    tables:,
  )
}

/// Each auto-attack row the check refuses, with its sentence. A creature with a kind row of
/// its own and auto-attack rows has every one refused.
fn auto_attack_refusals(
  rows rows: List(Row),
  auto_attack_rows auto_attack_rows: List(creature_auto_attack.Row),
  tables tables: table_store.Tables,
) -> List(#(creature_auto_attack.Row, String)) {
  let kind_creature_ids =
    set.from_list(list.map(rows, fn(row) { row.creature_id }))
  list.filter_map(auto_attack_rows, fn(row) {
    creature_auto_attack.refusal_of(row:, tables:, kind_creature_ids:)
    |> result.map(fn(rule) { #(row, rule) })
  })
}

/// Each special row the check refuses, with its sentence. The plan's rows are grouped once,
/// and only when a row is there to check.
fn special_refusals(
  special_rows special_rows: List(creature_special.Row),
  tables tables: table_store.Tables,
) -> List(#(creature_special.Row, String)) {
  case special_rows {
    [] -> []
    _ -> {
      let sources = spell_plan.sources_of(tables:)
      list.filter_map(special_rows, fn(row) {
        creature_special.refusal_of(row:, tables:, sources:)
        |> result.map(fn(rule) { #(row, rule) })
      })
    }
  }
}

/// The kinds of the rows, or `Error(Nil)` with no default row among them or a row whose
/// guard the client's tables do not hold. A creature with
/// specials and no row of its own takes the default's fields and its own specials.
fn kinds_of(
  rows rows: List(Row),
  special_rows special_rows: List(creature_special.Row),
  auto_attack_rows auto_attack_rows: List(creature_auto_attack.Row),
  tables tables: table_store.Tables,
) -> Result(Kinds, Nil) {
  use default_row <- result.try(
    list.find(rows, fn(row) { row.creature_id == 0 }),
  )
  use default <- result.try(kind_of_row(
    row: default_row,
    special_rows:,
    tables:,
  ))
  let creature_ids =
    list.append(
      list.map(rows, fn(row) { row.creature_id }),
      list.append(
        list.map(special_rows, fn(row) { row.creature_id }),
        list.map(auto_attack_rows, fn(row) { row.creature_id }),
      ),
    )
    |> list.unique
    |> list.filter(fn(creature_id) { creature_id != 0 })
  use by_creature <- result.map(
    list.try_map(creature_ids, fn(creature_id) {
      case list.find(rows, fn(row) { row.creature_id == creature_id }) {
        Ok(row) ->
          kind_of_row(row:, special_rows:, tables:)
          |> result.map(fn(kind) { #(creature_id, kind) })
        Error(Nil) ->
          Ok(#(
            creature_id,
            with_auto_attacks(
              kind: Kind(
                ..default,
                specials: creature_special.refs_of(
                  rows: special_rows,
                  creature_id:,
                ),
              ),
              auto_attack_rows:,
              creature_id:,
            ),
          ))
      }
    }),
  )
  Kinds(default:, by_creature: dict.from_list(by_creature))
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
      case row.guard {
        Some(GuardSpells(guard_spell4_id:, opening_spell4_id:)) ->
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
        None -> Error(Nil)
      }
    },
  ]
  list.find_map(checks, fn(check) { check() })
}

/// The kind of a row, or `Error(Nil)` when the client's tables do not hold its guard
/// (`refusal_of` names why).
fn kind_of_row(
  row row: Row,
  special_rows special_rows: List(creature_special.Row),
  tables tables: table_store.Tables,
) -> Result(Kind, Nil) {
  use guard <- result.map(case row.guard {
    Some(GuardSpells(guard_spell4_id:, opening_spell4_id:)) ->
      creature_guard_spells.guard_of(
        guard_spell4_id:,
        opening_spell4_id:,
        tables:,
      )
      |> result.map(Some)
      |> result.replace_error(Nil)
    None -> Ok(None)
  })
  Kind(
    respawn_ms: row.respawn_ms,
    attack_spell4_id: Spell4Id(row.attack_spell4_id),
    alternate_spell4_ids: [],
    attack_interval_ms: row.attack_interval_ms,
    guard:,
    specials: creature_special.refs_of(
      rows: special_rows,
      creature_id: row.creature_id,
    ),
  )
}

/// The kind with the creature's auto-attacks in turn: the first is its attack and the rest its
/// alternates; a creature with none keeps the kind's attack.
fn with_auto_attacks(
  kind kind: Kind,
  auto_attack_rows auto_attack_rows: List(creature_auto_attack.Row),
  creature_id creature_id: Int,
) -> Kind {
  case creature_auto_attack.refs_of(rows: auto_attack_rows, creature_id:) {
    [] -> kind
    [lead, ..alternates] ->
      Kind(..kind, attack_spell4_id: lead, alternate_spell4_ids: alternates)
  }
}

/// The kind of a creature: its own row's when it has one, else the default.
pub fn kind_of(kinds kinds: Kinds, creature2_id creature2_id: Int) -> Kind {
  dict.get(kinds.by_creature, creature2_id)
  |> result.unwrap(kinds.default)
}

/// Whether the creature has an attack row of its own: a kind row, an auto-attack row or a
/// special row. The default row 0 is no creature's own.
pub fn has_row(kinds kinds: Kinds, creature2_id creature2_id: Int) -> Bool {
  dict.has_key(kinds.by_creature, creature2_id)
}
