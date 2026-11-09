//// The fixture beside a wire recording (genesis_prime/wire_recording/fixture):
//// the rows of the session's account, its characters and their held items, and
//// where the id sequences stood, as data-only SQL a replay applies after the
//// migrations.
//// Expected values come from these places.
//// - The rows the tests insert, and the tables' columns in
////   `priv/migrations/0001_account_and_character.sql` through
////   `priv/migrations/0004_character_needs_rename.sql`.
//// - The fixture's own contract in its module doc: the named accounts and their
////   characters only, every column but `created_at`, ids kept as they were (they
////   are identity columns, so the inserts override them), each id sequence set
////   to where the live one stood (its last value and whether it had given one),
////   accounts before the characters that reference them, one transaction when
////   applied.
//// - Postgres: an identity column's sequence gives the value after its last, and
////   gives its first when it has given none; a transaction that fails leaves no
////   row.

import database_support
import genesis_prime/wire_recording/fixture.{
  FileFailed, NoSuchAccount, StatementFailed,
}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import owned_test
import pog
import recording_support
import simplifile

/// A pool on a migrated database of the test's own.
fn pool() -> pog.Connection {
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let assert Ok(started) =
    pog.start(database_support.config(
      for: shared.settings,
      database:,
      pool_name: process.new_name("fixture_pool"),
      pool_size: 2,
    ))
    as "the pool started"
  started.data
}

fn run(pool: pog.Connection, sql: String) -> Nil {
  let assert Ok(_) = pog.query(sql) |> pog.execute(pool)
    as { "the statement ran: " <> sql }
  Nil
}

/// Two accounts and three characters, with a name that holds a quote, bytes that
/// a text literal would mangle, a rename mark, a look and bones, and ids that
/// are not 1 and 2. The ids are given, so the sequences have given nothing.
fn insert_rows(pool: pog.Connection) -> Nil {
  run(
    pool,
    "insert into account (account_id, login_name, srp_salt, srp_verifier, game_account_id) overriding system value values (1, 'genesis', '\\x00005c27ff'::bytea, '\\x0a0d5c'::bytea, '01234567-89ab-cdef-0123-456789abcdef')",
  )
  run(
    pool,
    "insert into account (account_id, login_name, srp_salt, srp_verifier, game_account_id) overriding system value values (4, 'o''brien', '\\x01'::bytea, '\\x02'::bytea, 'fedcba98-7654-3210-fedc-ba9876543210')",
  )
  run(
    pool,
    "insert into character (character_id, account_id, session_epoch, save_sequence, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z, rotation_yaw, rotation_pitch, rotation_roll, look_labels, look_values, bones, needs_rename, health, experience) overriding system value values (1, 1, 3, 4, 'Tess Renamed', 1, 1, 1, 167, 3, 0, 426, 648, 4110.7099609375, -658.6248779296875, -5145.47998046875, 1.5, -0.25, 0.5, '{}', '{}', '{}', false, 512, 2000)",
  )
  run(
    pool,
    "insert into character (character_id, account_id, session_epoch, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z, look_labels, look_values, bones, needs_rename) overriding system value values (2, 1, 0, 'Nova Entry', 0, 1, 1, 167, 1, 0, 3460, 6009, 29.1285991668701, -853.87158203125, -560.18798828125, '{2,4,7}', '{1,2,10}', '{0,1065353216}', true)",
  )
  run(
    pool,
    "insert into character (character_id, account_id, session_epoch, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z, look_labels, look_values, bones, needs_rename) overriding system value values (6, 4, 0, 'Oneil Entry', 0, 1, 1, 167, 1, 0, 3460, 6009, 29.1285991668701, -853.87158203125, -560.18798828125, '{2,4,7}', '{1,2,10}', '{0,1065353216}', true)",
  )
  run(
    pool,
    "insert into character_item (item_guid, character_id, item2_id, location, bag_index, stack_count) overriding system value values (7, 1, 81359, 0, 0, 1), (11, 1, 8534, 0, 15, 2), (12, 2, 81344, 0, 1, 1), (20, 6, 81346, 0, 16, 1)",
  )
}

/// Every column the fixture keeps, as one text for each row, so two databases
/// are compared by what their rows say.
fn rows(pool: pog.Connection) -> List(String) {
  let accounts =
    query_texts(
      pool,
      "select concat_ws('|', account_id, login_name, encode(srp_salt, 'hex'), encode(srp_verifier, 'hex'), game_account_id) from account order by account_id",
    )
  let characters =
    query_texts(
      pool,
      "select concat_ws('|', character_id, account_id, session_epoch, save_sequence, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x::text, position_y::text, position_z::text, rotation_yaw::text, rotation_pitch::text, rotation_roll::text, look_labels::text, look_values::text, bones::text, needs_rename::text, coalesce(health::text, 'null'), coalesce(experience::text, 'null')) from character order by character_id",
    )
  let items =
    query_texts(
      pool,
      "select concat_ws('|', item_guid, character_id, item2_id, location, bag_index, stack_count) from character_item order by item_guid",
    )
  list.flatten([accounts, characters, items])
}

fn query_texts(pool: pog.Connection, sql: String) -> List(String) {
  let assert Ok(returned) =
    pog.query(sql)
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(pool)
    as { "the query ran: " <> sql }
  returned.rows
}

/// The path of a fixture file in `folder`.
fn path_in(folder: String) -> String {
  folder <> "/" <> fixture.file_name
}

pub fn the_rows_of_the_named_accounts_written_and_applied_to_a_new_database_are_the_same_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis", "o'brien"]) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert rows(target)
    == [
      "1|genesis|00005c27ff|0a0d5c|01234567-89ab-cdef-0123-456789abcdef",
      "4|o'brien|01|02|fedcba98-7654-3210-fedc-ba9876543210",
      "1|1|3|4|Tess Renamed|1|1|1|167|3|0|426|648|4110.71|-658.6249|-5145.48|1.5|-0.25|0.5|{}|{}|{}|false|512|2000",
      "2|1|0|0|Nova Entry|0|1|1|167|1|0|3460|6009|29.1286|-853.8716|-560.188|0|0|0|{2,4,7}|{1,2,10}|{0,1065353216}|true|null|null",
      "6|4|0|0|Oneil Entry|0|1|1|167|1|0|3460|6009|29.1286|-853.8716|-560.188|0|0|0|{2,4,7}|{1,2,10}|{0,1065353216}|true|null|null",
      "7|1|81359|0|0|1",
      "11|1|8534|0|15|2",
      "12|2|81344|0|1|1",
      "20|6|81346|0|16|1",
    ]
    as "every account and character with its id, its bytes, the numbers that fence a save, the way it faces, its look, its rename mark and its saved health and experience (none stays NULL), and every held item with its own guid, character, item, place and stack, as inserted"
  assert rows(source) == rows(target)
    as "and the same as the database the fixture was written from"
}

pub fn the_fixtures_columns_are_the_tables_columns_but_created_at_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let assert Ok(text) = simplifile.read(path) as "the fixture reads"
  list.each(["account", "character", "character_item"], fn(table) {
    let assert Ok(statement) =
      string.split(text, ";\n")
      |> list.find(fn(statement) {
        string.starts_with(statement, "insert into " <> table <> " (")
      })
      as "the fixture inserts into the table"
    let assert [_, after] =
      string.split(statement, "insert into " <> table <> " (")
    let assert [columns, _] = string.split(after, ") overriding")
      as "the insert lists its columns before its values"
    assert list.sort(string.split(columns, ", "), string.compare)
      == query_texts(
        source,
        "select column_name::text from information_schema.columns where table_schema = 'public' and table_name = '"
          <> table
          <> "' and column_name <> 'created_at' order by column_name",
      )
      as {
        "the fixture keeps every column of "
        <> table
        <> " but created_at, the contract of its module doc"
      }
  })
}

pub fn the_fixture_holds_only_the_named_accounts_and_their_characters_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let assert Ok(text) = simplifile.read(path) as "the fixture reads"
  assert !string.contains(text, "o''brien")
    && !string.contains(text, "Oneil Entry")
    && !string.contains(text, "fedcba98")
    as "nothing of the account that was not named is in the file"
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert rows(target)
    == [
      "1|genesis|00005c27ff|0a0d5c|01234567-89ab-cdef-0123-456789abcdef",
      "1|1|3|4|Tess Renamed|1|1|1|167|3|0|426|648|4110.71|-658.6249|-5145.48|1.5|-0.25|0.5|{}|{}|{}|false|512|2000",
      "2|1|0|0|Nova Entry|0|1|1|167|1|0|3460|6009|29.1286|-853.8716|-560.188|0|0|0|{2,4,7}|{1,2,10}|{0,1065353216}|true|null|null",
      "7|1|81359|0|0|1",
      "11|1|8534|0|15|2",
      "12|2|81344|0|1|1",
    ]
    as "the named account, both its characters and their items, and no other account's character or item"
}

pub fn a_login_name_the_database_has_no_account_for_is_refused_and_no_file_is_made_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis", "nobody"])
    == Error(NoSuchAccount(login_name: "nobody"))
    as "the session's account is not in the database, so the fixture would not hold it"
  assert simplifile.is_file(path) == Ok(False)
    as "a fixture that cannot be whole is not left behind"
}

pub fn the_fixture_is_data_only_sql_with_the_accounts_before_the_characters_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis", "o'brien"]) == Ok(Nil)
  let assert Ok(text) = simplifile.read(path) as "the fixture reads"
  let statements = string.split(text, ";\n") |> list.filter(fn(s) { s != "" })
  assert list.all(statements, fn(statement) {
    string.starts_with(statement, "insert into ")
    || string.starts_with(statement, "select setval(")
  })
    as "every statement inserts a row or sets a sequence: no schema, no drop"
  let first_character =
    list.index_map(statements, fn(statement, index) { #(index, statement) })
    |> list.find(fn(entry) {
      string.starts_with(entry.1, "insert into character ")
    })
  let last_account =
    list.index_map(statements, fn(statement, index) { #(index, statement) })
    |> list.filter(fn(entry) {
      string.starts_with(entry.1, "insert into account ")
    })
    |> list.last
  let assert Ok(#(character_at, _)) = first_character as "a character"
  let assert Ok(#(account_at, _)) = last_account as "an account"
  assert account_at < character_at
    as "a character's account is inserted before it, whatever the foreign key"
  let first_item =
    list.index_map(statements, fn(statement, index) { #(index, statement) })
    |> list.find(fn(entry) {
      string.starts_with(entry.1, "insert into character_item ")
    })
  let last_character =
    list.index_map(statements, fn(statement, index) { #(index, statement) })
    |> list.filter(fn(entry) {
      string.starts_with(entry.1, "insert into character ")
    })
    |> list.last
  let assert Ok(#(item_at, _)) = first_item as "an item"
  let assert Ok(#(last_character_at, _)) = last_character as "a character"
  assert last_character_at < item_at
    as "an item's character is inserted before it, whatever the foreign key"
}

/// Inserts an account by sequence, with the one name the sequence tests use.
fn insert_account_by_sequence(pool: pog.Connection) -> Nil {
  run(
    pool,
    "insert into account (login_name, srp_salt, srp_verifier, game_account_id) values ('genesis', '\\x01'::bytea, '\\x02'::bytea, '01234567-89ab-cdef-0123-456789abcdef')",
  )
}

/// A character of account 1 with this name, inserted as the server inserts one:
/// its id comes from the sequence.
fn insert_character(pool: pog.Connection, name: String) -> Nil {
  run(
    pool,
    "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values (1, '"
      <> name
      <> "', 0, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0)",
  )
}

/// The id the next character of the database gets.
fn next_character_id(pool: pog.Connection) -> String {
  let assert [id] =
    query_texts(
      pool,
      "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values (1, 'Next Ab', 0, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0) returning character_id::text",
    )
    as "the insert gives its id"
  id
}

pub fn a_sequence_that_is_ahead_of_the_largest_kept_id_is_restored_as_it_was_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_account_by_sequence(source)
  insert_character(source, "One Ab")
  insert_character(source, "Two Ab")
  insert_character(source, "Three Ab")
  run(source, "delete from character where name = 'Three Ab'")
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert next_character_id(target) == "4"
    as "the live sequence had given 1, 2 and 3, so its next value is 4, though the largest id left is 2"
}

pub fn a_sequence_of_a_table_left_with_no_rows_is_restored_as_it_was_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_account_by_sequence(source)
  insert_character(source, "One Ab")
  insert_character(source, "Two Ab")
  run(source, "delete from character")
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert next_character_id(target) == "3"
    as "two ids were given and no row is left: the next is 3, not 1"
}

pub fn a_sequence_that_was_never_used_gives_1_after_the_fixture_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_account_by_sequence(source)
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert next_character_id(target) == "1"
    as "no character id was ever given: the next is 1"
}

/// An item of character 1 at this bag index of the equipped slots, inserted as
/// the server inserts one: its guid comes from the sequence.
fn insert_item(pool: pog.Connection, bag_index: Int) -> Nil {
  run(
    pool,
    "insert into character_item (character_id, item2_id, location, bag_index, stack_count) values (1, 81359, 0, "
      <> int.to_string(bag_index)
      <> ", 1)",
  )
}

/// The guid the next item of the database gets.
fn next_item_guid(pool: pog.Connection) -> String {
  let assert [guid] =
    query_texts(
      pool,
      "insert into character_item (character_id, item2_id, location, bag_index, stack_count) values (1, 81359, 1, 0, 1) returning item_guid::text",
    )
    as "the insert gives its guid"
  guid
}

pub fn an_item_guid_sequence_that_is_ahead_of_the_largest_kept_guid_is_restored_as_it_was_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_account_by_sequence(source)
  insert_character(source, "One Ab")
  insert_item(source, 0)
  insert_item(source, 1)
  insert_item(source, 2)
  run(source, "delete from character_item where bag_index = 2")
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert query_texts(
      target,
      "select item_guid::text from character_item order by item_guid",
    )
    == ["1", "2"]
    as "the two items left keep the guids they had"
  assert next_item_guid(target) == "4"
    as "the live sequence had given 1, 2 and 3, so a session that makes an item gets 4, though the largest guid left is 2"
}

pub fn an_item_guid_sequence_that_was_never_used_gives_1_after_the_fixture_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_account_by_sequence(source)
  insert_character(source, "One Ab")
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert next_item_guid(target) == "1"
    as "no guid was ever given: the next is 1"
}

pub fn the_sequences_of_other_accounts_rows_still_count_after_the_fixture_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_account_by_sequence(source)
  run(
    source,
    "insert into account (login_name, srp_salt, srp_verifier, game_account_id) values ('other', '\\x01'::bytea, '\\x02'::bytea, '11111111-2222-3333-4444-555555555555')",
  )
  insert_character(source, "Mine Ab")
  run(
    source,
    "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values (2, 'Theirs Ab', 0, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0)",
  )
  let path = path_in(folder)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert rows(target)
    == [
      "1|genesis|01|02|01234567-89ab-cdef-0123-456789abcdef",
      "1|1|0|0|Mine Ab|0|1|1|167|1|0|0|0|0|0|0|0|0|0|{}|{}|{}|false|null|null",
    ]
    as "only the named account's rows"
  assert next_character_id(target) == "3"
    as "the other account's character took id 2 live, so the next character gets 3"
}

pub fn a_fixture_with_a_statement_the_database_refuses_leaves_no_row_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let path = path_in(folder)
  let refused = "insert into account (login_name) values ('')"
  let assert Ok(Nil) =
    simplifile.write(
      path,
      "insert into account (account_id, login_name, srp_salt, srp_verifier, game_account_id) overriding system value values (1, 'genesis', '\\x01'::bytea, '\\x02'::bytea, '01234567-89ab-cdef-0123-456789abcdef');\n"
        <> refused
        <> ";\n",
    )
    as "the fixture was written"
  let target = pool()
  let assert Error(StatementFailed(statement:, ..)) =
    fixture.apply(target, path)
    as "the second statement is refused"
  assert statement == refused as "the error names the statement"
  assert rows(target) == []
    as "the first statement's row was rolled back with the transaction"
}

pub fn a_fixture_is_never_overwritten_and_a_missing_one_is_a_file_failure_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let path = path_in(folder)
  let source = pool()
  insert_account_by_sequence(source)
  assert fixture.write(source, path, ["genesis"]) == Ok(Nil)
  let assert Error(FileFailed(path: failed, ..)) =
    fixture.write(source, path, ["genesis"])
    as "a file already there is never overwritten"
  assert failed == path
  let assert Error(FileFailed(path: missing, ..)) =
    fixture.apply(source, folder <> "/none.sql")
    as "a fixture that is not there cannot be applied"
  assert missing == folder <> "/none.sql"
}
