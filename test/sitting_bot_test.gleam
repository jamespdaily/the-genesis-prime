//// Where the sitting bot (`genesis_prime/sitting_bot`) is seated in a database,
//// which is the database Jim plays on: a character of another account is
//// refused and left as it is, seating twice makes no second account, and a
//// refusal adds nothing. Its whole path against a server is proven in
//// `game_wire_sitting_bot_test`. Expected values come from these places.
//// - The tool's contract, its module doc: `--near` names the character.
//// - A character with no saved place is world 0 (genesis_prime/add_character).

import character_support
import database_support
import fixture_tables
import genesis_prime/add_account
import genesis_prime/dev_database
import genesis_prime/game/item_property
import genesis_prime/sitting_bot.{Place}
import genesis_prime/store.{AccountId}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/option
import open_wait
import owned_test
import pog

/// A pool on a migrated database of the test's own.
fn pool() -> pog.Connection {
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let name = process.new_name("pool")
  let assert Ok(_) =
    pog.start(database_support.config(
      for: shared.settings,
      database:,
      pool_name: name,
      pool_size: 2,
    ))
    as "the pool started"
  pog.named_connection(name)
}

/// A character of an account of its own at world 1387, zone 1100, x 1.5, y 2.5,
/// z 3.5 (`character_support.insert`).
fn insert_named(pool: pog.Connection, name: String) -> Nil {
  let #(_game_account_id, query) =
    add_account.new_account(login_name: "named", password: "named")
  let assert Ok(pog.Returned(rows: [account], ..)) = query(pool)
    as "the account was inserted"
  let _id =
    character_support.insert(
      pool:,
      account: AccountId(account.account_id),
      name:,
      class_id: 4,
      path: 2,
    )
  Nil
}

fn count(pool: pog.Connection, table: String) -> Int {
  let assert Ok(returned) =
    pog.query("select count(*)::int from " <> table)
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(pool)
    as "the count reads"
  let assert [rows] = returned.rows as "a count is one row"
  rows
}

fn bot_row(pool: pog.Connection) -> #(String, Int, Int, Float, Float, Float) {
  let assert Ok(returned) =
    pog.query(
      "select name, world_id, world_zone_id, position_x::float8, position_y::float8, position_z::float8 from character where name = 'Sitting Bot'",
    )
    |> pog.returning({
      use name <- decode.field(0, decode.string)
      use world <- decode.field(1, decode.int)
      use zone <- decode.field(2, decode.int)
      use x <- decode.field(3, decode.float)
      use y <- decode.field(4, decode.float)
      use z <- decode.field(5, decode.float)
      decode.success(#(name, world, zone, x, y, z))
    })
    |> pog.execute(pool)
    as "the row reads"
  let assert [row] = returned.rows as "one character is named Sitting Bot"
  row
}

pub fn the_bot_is_seated_at_the_named_characters_own_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(seat) = sitting_bot.seat(pool:, near: "zed QU")
    as "the named character is found in any case, as names are unique in any case"
  assert seat.place
    == Place(world_id: 1387, world_zone_id: 1100, x: 1.5, y: 2.5, z: 3.5)
    as "the named character's world, zone and position, which the bot walks from"
  assert bot_row(pool) == #("Sitting Bot", 1387, 1100, 1.5, 2.5, 3.5)
    as "the bot character's row holds the place it was seated at"
}

/// What each of the bot's items holds: its Item2 id and the charges stored for it,
/// an error for none stored.
fn bot_items(pool: pog.Connection) -> List(#(Int, Result(Int, Nil))) {
  let assert Ok(returned) =
    pog.query(
      "select item2_id, charges from character_item join character using (character_id) where character.name = 'Sitting Bot' order by bag_index",
    )
    |> pog.returning({
      use item2_id <- decode.field(0, decode.int)
      use charges <- decode.field(1, decode.optional(decode.int))
      decode.success(#(item2_id, option.to_result(charges, Nil)))
    })
    |> pog.execute(pool)
    as "the items read"
  returned.rows
}

/// The Novice set's items are made with their rows' charges, as character creation makes
/// them (`opcode.0x111.charges`), so no row of the bot's holds a null charge count.
pub fn the_bots_novice_items_are_stored_with_their_rows_charges_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(_) = sitting_bot.seat(pool:, near: "Zed Qu")
  let tables = fixture_tables.shared()
  let items = bot_items(pool)
  assert list.map(items, fn(item) { item.0 })
    == [81_359, 81_344, 81_381, 81_345, 81_380, 8534, 81_346]
    as "the bot holds the Novice set's seven items"
  list.each(items, fn(item) {
    let assert Ok(charges) =
      item_property.max_charges(tables:, item2_id: item.0)
      as "the Novice set's items are rows of the Item2 table"
    assert item.1 == Ok(charges)
      as "the item is stored with its row's charges, never null"
  })
}

pub fn a_sitting_bot_character_of_another_account_is_refused_and_left_as_it_is_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  // Another account owns the character named "Sitting Bot", in another case.
  let #(_game_account_id, query) =
    add_account.new_account(login_name: "other", password: "other")
  let assert Ok(pog.Returned(rows: [other], ..)) = query(pool)
    as "the other account was inserted"
  let owned =
    character_support.insert(
      pool:,
      account: AccountId(other.account_id),
      name: "sitting BOT",
      class_id: 4,
      path: 2,
    )
  let assert Error(sitting_bot.Database(failure: dev_database.Refused(_))) =
    sitting_bot.seat(pool:, near: "Zed Qu")
    as "the name is taken by a character of another account, so the bot's is not made"
  let place = character_support.place_row(pool:, character_id: owned)
  assert place.position == #(1.5, 2.5, 3.5) && place.world_id == 1387
    as "the other account's character was not moved"
  assert count(pool, "character") == 2 as "no character was made for the bot"
}

pub fn seating_the_bot_again_reuses_its_account_and_character_and_moves_it_to_the_new_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(first) = sitting_bot.seat(pool:, near: "Zed Qu")
  let assert Ok(_) =
    pog.query("update character set position_x = 100.5 where name = 'Zed Qu'")
    |> pog.execute(pool)
  let assert Ok(second) = sitting_bot.seat(pool:, near: "Zed Qu")
  assert second.character_id == first.character_id
    as "the same character, not a second one"
  assert count(pool, "account") == 2
    as "the named character's account and the bot's one"
  assert count(pool, "character") == 2
  assert bot_row(pool).3 == 100.5
    as "the bot is moved to where the named character is now"
}

pub fn seating_the_bot_twice_at_once_leaves_one_account_and_one_character_for_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let seated = process.new_subject()
  list.each([1, 2], fn(_) {
    process.spawn(fn() {
      process.send(seated, sitting_bot.seat(pool:, near: "Zed Qu"))
    })
  })
  let first = open_wait.received(from: seated, what: "the first seat's answer")
  let second =
    open_wait.received(from: seated, what: "the second seat's answer")
  let assert Ok(first) = first
    as "a seat that runs beside another still finds or makes the bot's character"
  let assert Ok(second) = second as "so does the other"
  assert first.character_id == second.character_id
    as "both seats are of the one character"
  assert count(pool, "account") == 2
    as "the named character's account and one account for the bot"
  assert count(pool, "character") == 2
    as "the named character and one character for the bot"
}

pub fn a_bot_account_with_no_character_gets_its_character_and_no_second_account_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let #(_game_account_id, query) =
    add_account.new_account(login_name: "sitting-bot", password: "sitting-bot")
  let assert Ok(_) = query(pool) as "the bot's account was inserted alone"
  let assert Ok(_) = sitting_bot.seat(pool:, near: "Zed Qu")
  assert count(pool, "account") == 2
    as "the bot's account was used, not made again"
  assert count(pool, "character") == 2 as "the bot's character was made for it"
  assert bot_row(pool).0 == "Sitting Bot"
}

pub fn a_named_character_that_does_not_exist_is_refused_and_nothing_is_added_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  assert sitting_bot.seat(pool:, near: "No One")
    == Error(sitting_bot.NoSuchCharacter(name: "No One"))
  assert count(pool, "account") == 0 && count(pool, "character") == 0
    as "a refused seat leaves no bot account or character"
}

pub fn a_named_character_with_no_saved_place_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pool()
  insert_named(pool, "Zed Qu")
  let assert Ok(_) =
    pog.query(
      "update character set world_id = 0, world_zone_id = 0, position_x = 0, position_y = 0, position_z = 0 where name = 'Zed Qu'",
    )
    |> pog.execute(pool)
  assert sitting_bot.seat(pool:, near: "Zed Qu")
    == Error(sitting_bot.NoSavedPlace(name: "Zed Qu"))
    as "world 0 is no place, so there is no world to seat the bot in"
}
