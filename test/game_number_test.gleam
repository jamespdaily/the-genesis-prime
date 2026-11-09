//// The game_number table and its checks (`genesis_prime/world_map/game_number`,
//// `genesis_prime/content/game_number`). Expected values come from these places.
//// - The design of step F (the Design artifact of issue 367, section 2): the four
////   seeded rows, aggro_range 10 units (no client range, `creature.ai_data`),
////   leash_range 55 units (the objective circle's radius, WorldLocation2 51739),
////   aggro_threat 1 threat (any threat above 0 shows hostile, `0x14045a950`) and
////   chase_stop_fraction 0.5 (strictly between 0 and 1: at 0 the creature stops at
////   the edge of its reach, at 1 it runs onto the target); a missing or unknown
////   name, a leash range not above the aggro range and an aggro range not below
////   sight each stop the start, named, and the table refuses a threat of 0 or
////   below, a fraction outside (0, 1) and a name with a unit that is not its own
////   or that no one listed (migration 0014).
//// - Migration 0016: interrupt_armor_refill_ms, 10000 ms, a server choice (no client value
////   says when armor returns, `opcode.0x938.interrupt_armor`), a whole number above 0.
//// - The shared pattern of the content tables (`genesis_prime/content`): every
////   refusal is collected and named by its table, its row and its rule.
//// - Sight is 1024 units (`genesis_prime/world_map/sight.range`, unit.range).

import content_support
import database_support
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/world_map/game_number.{type Row, GameNumbers, Row}
import gleam/list
import gleam/result
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
    Row(name: "daily_quest_reset_ms", value: 36_000_000.0, unit: "ms"),
    Row(name: "health_regen_fraction", value: 0.025, unit: "fraction"),
    Row(name: "health_regen_tick_ms", value: 500.0, unit: "ms"),
    Row(name: "interrupt_armor_refill_ms", value: 10_000.0, unit: "ms"),
    Row(name: "leash_range", value: 55.0, unit: "units"),
    Row(name: "weekly_quest_reset_ms", value: 122_400_000.0, unit: "ms"),
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
      interrupt_armor_refill_ms: 10_000,
      daily_quest_reset_ms: 36_000_000,
      weekly_quest_reset_ms: 122_400_000,
    ))
}

pub fn a_missing_and_an_unknown_number_are_each_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    seeded()
    |> list.filter(fn(row) { row.name != "aggro_threat" })
    |> list.append([Row(name: "evade_range", value: 30.0, unit: "units")])
  let assert Error(refusals) = game_number.select(rows:, sight_range:)
  assert names_of(refusals) == ["evade_range", "aggro_threat"]
    as "one bad row shows its neighbours: the number the server knows no use of, and the missing threat"
}

pub fn a_missing_refill_time_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.filter(seeded(), fn(row) { row.name != "interrupt_armor_refill_ms" })
  let assert Error(refusals) = game_number.select(rows:, sight_range:)
  assert names_of(refusals) == ["interrupt_armor_refill_ms"]
    as "the creature starts a timer of that many milliseconds, and the client holds none"
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

/// The seeded rows with these two reset times, in milliseconds.
fn with_resets(daily daily: Float, weekly weekly: Float) -> List(Row) {
  list.map(seeded(), fn(row) {
    case row.name {
      "daily_quest_reset_ms" -> Row(..row, value: daily)
      "weekly_quest_reset_ms" -> Row(..row, value: weekly)
      _ -> row
    }
  })
}

pub fn a_quest_reset_time_that_is_not_a_whole_second_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  // Both are 500 ms past a whole second, and the weekly one is a day and the
  // daily one's time of day after Monday 00:00, so only the second is wrong. The
  // reset time the quest log sends is whole Unix seconds (opcode.0x362: the
  // client compares it for change), so an instant inside a second is one the
  // message cannot carry.
  let rows = with_resets(daily: 36_000_500.0, weekly: 122_400_500.0)
  let assert Error(refusals) = game_number.select(rows:, sight_range:)
  assert names_of(refusals) == ["daily_quest_reset_ms", "weekly_quest_reset_ms"]
    as "each time that is not a whole number of seconds is named"
  assert list.all(refusals, fn(refused) {
    string.contains(refused.rule, "whole second")
  })
    as "the rule says why"
  assert game_number.select(
      rows: with_resets(daily: 36_001_000.0, weekly: 122_401_000.0),
      sight_range:,
    )
    |> result.is_ok
    as "times of whole seconds are taken"
}

pub fn a_weekly_reset_at_another_time_of_day_than_the_daily_one_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  // The weekly reset on Tuesday at 11:00 UTC against a daily reset at 10:00: the
  // monthly and yearly resets run on the daily reset's time of day, and the
  // quest log's design holds the weekly one to the same time of day.
  let rows = with_resets(daily: 36_000_000.0, weekly: 126_000_000.0)
  let assert Error([refused]) = game_number.select(rows:, sight_range:)
  assert names_of([refused]) == ["weekly_quest_reset_ms"]
    as "the weekly time is the one that does not match"
  assert string.contains(refused.rule, "time of day")
    as "the rule says what does not match"
}

pub fn a_missing_health_regeneration_number_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let without = fn(name) { list.filter(seeded(), fn(row) { row.name != name }) }
  list.each(["health_regen_fraction", "health_regen_tick_ms"], fn(name) {
    let assert Error(refusals) =
      game_number.select(rows: without(name), sight_range:)
      as "a player's health tick reads the row: a missing one stops the start"
    assert refusals
      == [
        Refusal(
          table: "game_number",
          row: RowName(name),
          rule: "the table has no such row, which the server reads",
        ),
      ]
  })
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

pub fn a_migrated_database_holds_the_nine_seeded_numbers_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_game_number.rows(db: content_support.connect(database:))
    as "the query ran"
  assert rows == seeded()
    as "migration 0010's four rows, migration 0015's two, migration 0016's refill time and migration 0021's two quest reset times, in name order"
  assert content_support.count(
      database:,
      sql: "select count(*) from game_number where source = 'server_choice' and reason is not null",
    )
    == 9
    as "each is a server choice that states its reason"
}

pub fn the_database_refuses_each_bad_row_under_its_own_constraint_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  // A name is one insert into the reference table, so the rows below name
  // numbers the table lists, and each bad row breaks one rule only.
  let assert Ok(_) =
    database_support.psql(
      with: database_support.settings(),
      database:,
      arguments: [
        "-c",
        "insert into game_number_name (name, unit) values ('evade', 'units'), ('flee', 'units')",
      ],
    )
    as "the names were listed"
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
      #(
        "insert into game_number (name, value, unit, source, reason) values ('evade', 1, 'ms', 'server_choice', 'x')",
        "game_number_name_has_its_unit",
      ),
      #(
        "insert into game_number (name, value, unit, source, reason) values ('nobody_listed', 1, 'units', 'server_choice', 'x')",
        "game_number_name_has_its_unit",
      ),
      #(
        "update game_number set value = 0 where name = 'aggro_threat'",
        "game_number_aggro_threat_is_positive",
      ),
      #(
        "update game_number set value = -1 where name = 'aggro_threat'",
        "game_number_aggro_threat_is_positive",
      ),
      #(
        "update game_number set value = 0 where name = 'chase_stop_fraction'",
        "game_number_chase_stop_fraction_is_between_0_and_1",
      ),
      #(
        "update game_number set value = 1 where name = 'chase_stop_fraction'",
        "game_number_chase_stop_fraction_is_between_0_and_1",
      ),
      #(
        "update game_number set value = 0 where name = 'health_regen_fraction'",
        "game_number_health_regen_fraction_is_between_0_and_1",
      ),
      #(
        "update game_number set value = 1 where name = 'health_regen_fraction'",
        "game_number_health_regen_fraction_is_between_0_and_1",
      ),
      #(
        "update game_number set value = 0 where name = 'health_regen_tick_ms'",
        "game_number_health_regen_tick_ms_is_a_whole_positive_ms",
      ),
      #(
        "update game_number set value = 500.4 where name = 'health_regen_tick_ms'",
        "game_number_health_regen_tick_ms_is_a_whole_positive_ms",
      ),
      #(
        "update game_number set unit = 'units' where name = 'health_regen_fraction'",
        "game_number_name_has_its_unit",
      ),
      #(
        "update game_number set unit = 'fraction' where name = 'health_regen_tick_ms'",
        "game_number_name_has_its_unit",
      ),
      #(
        "update game_number set value = 0 where name = 'interrupt_armor_refill_ms'",
        "game_number_interrupt_armor_refill_ms_is_a_whole_positive_ms",
      ),
      #(
        "update game_number set value = 1500.5 where name = 'interrupt_armor_refill_ms'",
        "game_number_interrupt_armor_refill_ms_is_a_whole_positive_ms",
      ),
      #(
        "update game_number set unit = 'units' where name = 'interrupt_armor_refill_ms'",
        "game_number_name_has_its_unit",
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
      interrupt_armor_refill_ms: 10_000,
      daily_quest_reset_ms: 36_000_000,
      weekly_quest_reset_ms: 122_400_000,
    )
  content_game_number.put(key:, numbers:)
  assert content_game_number.numbers(key:) == numbers
    as "one term for the whole table, put once"
  owned_key.erase(key)
}
