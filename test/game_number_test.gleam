//// The game_number table and its checks (`genesis_prime/world_map/game_number`,
//// `genesis_prime/content/game_number`). Expected values come from these places.
//// - The design of step F (the Design artifact of issue 367, section 2): the four
////   seeded rows, aggro_range 10 units (no client range, `creature.ai_data`),
////   leash_range 55 units (the objective circle's radius, WorldLocation2 51739),
////   aggro_threat 1 threat (any threat above 0 shows hostile, `0x14045a950`) and
////   chase_stop_fraction 0.5; a missing, unknown or mis-united name, a leash range
////   not above the aggro range and an aggro range not below sight each stop the
////   start, named.
//// - The shared pattern of the content tables (`genesis_prime/content`): every
////   refusal is collected and named by its table, its row and its rule.
//// - Sight is 1024 units (`genesis_prime/world_map/sight.range`, unit.range).

import content_support
import database_support
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/world_map/game_number.{type Row, GameNumbers, Row}
import gleam/list
import gleam/string
import owned_key
import owned_test

/// The sight range, 1024 units (unit.range).
const sight_range = 1024.0

fn seeded() -> List(Row) {
  [
    Row(name: "aggro_range", value: 10.0, unit: "units"),
    Row(name: "aggro_threat", value: 1.0, unit: "threat"),
    Row(name: "chase_stop_fraction", value: 0.5, unit: "fraction"),
    Row(name: "health_regen_fraction", value: 0.025, unit: "fraction"),
    Row(name: "health_regen_tick_ms", value: 500.0, unit: "ms"),
    Row(name: "leash_range", value: 55.0, unit: "units"),
  ]
}

fn names_of(refusals: List(Refusal)) -> List(String) {
  list.map(refusals, fn(refused) {
    let assert Refusal(table: "game_number", row: RowName(name), ..) = refused
      as "a game number is refused by its name"
    name
  })
}

pub fn the_seeded_rows_select_into_the_numbers_a_fight_reads_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_number.select(rows: seeded(), sight_range:)
    == Ok(GameNumbers(
      aggro_range: 10.0,
      leash_range: 55.0,
      aggro_threat: 1.0,
      chase_stop_fraction: 0.5,
      health_regen_fraction: 0.025,
      health_regen_tick_ms: 500,
    ))
}

pub fn a_missing_an_unknown_and_a_mis_united_number_are_each_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    seeded()
    |> list.filter(fn(row) { row.name != "aggro_threat" })
    |> list.map(fn(row) {
      case row.name {
        "leash_range" -> Row(..row, unit: "ms")
        _ -> row
      }
    })
    |> list.append([Row(name: "evade_range", value: 30.0, unit: "units")])
  let assert Error(refusals) = game_number.select(rows:, sight_range:)
  assert names_of(refusals) == ["leash_range", "evade_range", "aggro_threat"]
    as "one bad row shows its neighbours: the leash range in ms, the number the server knows no use of, and the missing threat"
}

pub fn a_leash_range_not_above_the_aggro_range_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.map(seeded(), fn(row) {
      case row.name {
        "leash_range" -> Row(..row, value: 10.0)
        _ -> row
      }
    })
  let assert Error(refusals) = game_number.select(rows:, sight_range:)
  assert names_of(refusals) == ["leash_range"]
    as "a creature at home with a player in its ring would leash at once"
}

pub fn an_aggro_threat_not_above_0_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.map(seeded(), fn(row) {
      case row.name {
        "aggro_threat" -> Row(..row, value: 0.0)
        _ -> row
      }
    })
  let assert Error([refused]) = game_number.select(rows:, sight_range:)
  assert refused
    == Refusal(
      table: "game_number",
      row: RowName("aggro_threat"),
      rule: "an aggro threat of 0.0 is not above 0",
    )
    as "an entry of 0 threat is no foe the client shows hostile (0x14045a950)"
}

pub fn a_chase_stop_fraction_of_0_or_1_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let with_fraction = fn(fraction) {
    list.map(seeded(), fn(row) {
      case row.name {
        "chase_stop_fraction" -> Row(..row, value: fraction)
        _ -> row
      }
    })
  }
  assert game_number.select(rows: with_fraction(0.0), sight_range:)
    == Error([
      Refusal(
        table: "game_number",
        row: RowName("chase_stop_fraction"),
        rule: "a chase stop fraction of 0.0 is not between 0 and 1",
      ),
    ])
    as "at 0 the creature stops at the edge of its reach"
  assert game_number.select(rows: with_fraction(1.0), sight_range:)
    == Error([
      Refusal(
        table: "game_number",
        row: RowName("chase_stop_fraction"),
        rule: "a chase stop fraction of 1.0 is not between 0 and 1",
      ),
    ])
    as "at 1 it runs onto the target's own place"
  let assert Ok(_) = game_number.select(rows: with_fraction(0.99), sight_range:)
    as "a fraction inside (0, 1) is taken"
  Nil
}

pub fn a_missing_or_mis_united_health_regeneration_number_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let without = fn(name) { list.filter(seeded(), fn(row) { row.name != name }) }
  let assert Error(refusals) =
    game_number.select(rows: without("health_regen_fraction"), sight_range:)
  assert refusals
    == [
      Refusal(
        table: "game_number",
        row: RowName("health_regen_fraction"),
        rule: "the table has no such row, which the server reads",
      ),
    ]
    as "a player's health tick reads the fraction: a missing row stops the start"
  let assert Error(refusals) =
    game_number.select(rows: without("health_regen_tick_ms"), sight_range:)
  assert refusals
    == [
      Refusal(
        table: "game_number",
        row: RowName("health_regen_tick_ms"),
        rule: "the table has no such row, which the server reads",
      ),
    ]
    as "and so does the tick"
  let in_unit = fn(name, unit) {
    list.map(seeded(), fn(row) {
      case row.name == name {
        True -> Row(..row, unit:)
        False -> row
      }
    })
  }
  assert game_number.select(
      rows: in_unit("health_regen_fraction", "units"),
      sight_range:,
    )
    == Error([
      Refusal(
        table: "game_number",
        row: RowName("health_regen_fraction"),
        rule: "its unit is units, not fraction",
      ),
    ])
    as "a fraction in units is not the fraction the rule multiplies by"
  assert game_number.select(
      rows: in_unit("health_regen_tick_ms", "fraction"),
      sight_range:,
    )
    == Error([
      Refusal(
        table: "game_number",
        row: RowName("health_regen_tick_ms"),
        rule: "its unit is fraction, not ms",
      ),
    ])
    as "a tick in fractions is not a time"
}

pub fn a_health_regeneration_a_player_cannot_tick_by_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let refused_with = fn(name, value) {
    let rows =
      list.map(seeded(), fn(row) {
        case row.name == name {
          True -> Row(..row, value:)
          False -> row
        }
      })
    let assert Error(refusals) = game_number.select(rows:, sight_range:)
      as "the row's value is refused"
    names_of(refusals)
  }
  assert refused_with("health_regen_fraction", 1.0) == ["health_regen_fraction"]
    as "a fraction of 1 would refill the player in one tick"
  assert refused_with("health_regen_fraction", 0.0) == ["health_regen_fraction"]
    as "a fraction of 0 never regenerates"
  assert refused_with("health_regen_tick_ms", 0.0) == ["health_regen_tick_ms"]
    as "a tick of 0 ms would fire again at once"
}

pub fn an_aggro_range_not_below_sight_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.map(seeded(), fn(row) {
      case row.name {
        "aggro_range" -> Row(..row, value: 1024.0)
        "leash_range" -> Row(..row, value: 2000.0)
        _ -> row
      }
    })
  let assert Error([refused]) = game_number.select(rows:, sight_range:)
  assert names_of([refused]) == ["aggro_range"]
    as "a ring must lie inside sight, so its creature is Live"
  assert string.contains(refused.rule, "1024")
}

pub fn a_migrated_database_holds_the_six_seeded_numbers_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_game_number.rows(db: content_support.connect(database:))
    as "the query ran"
  assert rows == seeded()
    as "migration 0010's four rows and migration 0015's two, in name order"
  assert content_support.count(
      database:,
      sql: "select count(*) from game_number where source = 'server_choice' and reason is not null",
    )
    == 6
    as "each is a server choice that states its reason"
}

pub fn the_database_refuses_each_bad_row_under_its_own_constraint_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  list.each(
    [
      #(
        "insert into game_number (name, value, unit, source, reason) values ('Evade', 1, 'units', 'server_choice', 'x')",
        "game_number_name_is_snake_case",
      ),
      #(
        "insert into game_number (name, value, unit, source, reason) values ('evade', 'NaN', 'units', 'server_choice', 'x')",
        "game_number_value_is_finite",
      ),
      #(
        "insert into game_number (name, value, unit, source, reason) values ('evade', 1, 'metres', 'server_choice', 'x')",
        "game_number_unit_is_known",
      ),
      #(
        "insert into game_number (name, value, unit, source, reason) values ('evade', 1, 'units', 'nobody', 'x')",
        "game_number_source_is_a_content_source",
      ),
      #(
        "insert into game_number (name, value, unit, source) values ('evade', 1, 'units', 'server_choice')",
        "game_number_other_source_states_its_reason",
      ),
      #(
        "insert into game_number (name, value, unit, source, reason) values ('evade', 1, 'units', 'server_choice', ' ')",
        "game_number_reason_says_something",
      ),
      #(
        "insert into game_number (name, value, unit, source, source_row) values ('evade', 1, 'units', 'world_database', null)",
        "game_number_world_database_row_has_a_source_row",
      ),
      #(
        "insert into game_number (name, value, unit, source, source_row) values ('evade', 1, 'units', 'world_database', 0)",
        "game_number_source_row_is_positive",
      ),
      #(
        "insert into game_number (name, value, unit, source, source_row) values ('evade', 1, 'units', 'world_database', 1), ('flee', 1, 'units', 'world_database', 1)",
        "game_number_source_row_is_unique",
      ),
      #(
        "insert into game_number (name, value, unit, source, reason) values ('aggro_range', 1, 'units', 'server_choice', 'x')",
        "game_number_pkey",
      ),
    ],
    fn(bad) {
      let assert Error(failed) =
        database_support.psql(
          with: database_support.settings(),
          database:,
          arguments: ["-c", bad.0],
        )
        as "the database refuses the row"
      assert string.contains(failed.output, bad.1)
        as "the refusal names its constraint"
    },
  )
}

pub fn the_numbers_put_under_a_key_are_read_back_test() -> Nil {
  use <- owned_test.run(5000)
  let key = owned_key.new_key()
  let numbers =
    GameNumbers(
      aggro_range: 10.0,
      leash_range: 55.0,
      aggro_threat: 1.0,
      chase_stop_fraction: 0.5,
      health_regen_fraction: 0.025,
      health_regen_tick_ms: 500,
    )
  content_game_number.put(key:, numbers:)
  assert content_game_number.numbers(key:) == numbers
    as "one term for the whole table, put once"
  owned_key.erase(key)
}
