//// The fixture beside a wire recording (genesis_prime/wire_recording/fixture):
//// the account and character rows a session started from, as data-only SQL a
//// replay applies after the migrations. Expected values come from these
//// places.
//// - The rows the tests insert, and the tables' columns in
////   `priv/migrations/0001_account_and_character.sql` through
////   `priv/migrations/0004_character_needs_rename.sql`.
//// - The fixture's own contract in its module doc: every column but
////   `created_at`, ids kept as they were (they are identity columns, so the
////   inserts override them and the sequences go on from the largest), accounts
////   before the characters that reference them, one transaction when applied.
//// - Postgres: a transaction that fails leaves no row.

import database_support
import genesis_prime/wire_recording/fixture.{FileFailed, StatementFailed}
import gleam/dynamic/decode
import gleam/erlang/process
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

/// Rows with a name that holds a quote, bytes that a text literal would
/// mangle, a rename mark, a look and bones, and ids that are not 1 and 2.
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
    "insert into character (character_id, account_id, session_epoch, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z, look_labels, look_values, bones, needs_rename) overriding system value values (1, 1, 3, 'Tess Renamed', 1, 1, 1, 167, 3, 0, 426, 648, 4110.7099609375, -658.6248779296875, -5145.47998046875, '{}', '{}', '{}', false)",
  )
  run(
    pool,
    "insert into character (character_id, account_id, session_epoch, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z, look_labels, look_values, bones, needs_rename) overriding system value values (6, 4, 0, 'O''Neil Entry', 0, 1, 1, 167, 1, 0, 3460, 6009, 29.1285991668701, -853.87158203125, -560.18798828125, '{2,4,7}', '{1,2,10}', '{0,1065353216}', true)",
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
      "select concat_ws('|', character_id, account_id, session_epoch, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x::text, position_y::text, position_z::text, look_labels::text, look_values::text, bones::text, needs_rename::text) from character order by character_id",
    )
  list.append(accounts, characters)
}

fn query_texts(pool: pog.Connection, sql: String) -> List(String) {
  let assert Ok(returned) =
    pog.query(sql)
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(pool)
    as { "the query ran: " <> sql }
  returned.rows
}

pub fn the_rows_of_a_database_written_and_applied_to_a_new_one_are_the_same_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = folder <> "/" <> fixture.file_name
  assert fixture.write(source, path) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert rows(target)
    == [
      "1|genesis|00005c27ff|0a0d5c|01234567-89ab-cdef-0123-456789abcdef",
      "4|o'brien|01|02|fedcba98-7654-3210-fedc-ba9876543210",
      "1|1|3|Tess Renamed|1|1|1|167|3|0|426|648|4110.71|-658.6249|-5145.48|{}|{}|{}|false",
      "6|4|0|O'Neil Entry|0|1|1|167|1|0|3460|6009|29.1286|-853.8716|-560.188|{2,4,7}|{1,2,10}|{0,1065353216}|true",
    ]
    as "every account and character with its id, its bytes, its look and its rename mark, as inserted"
  assert rows(source) == rows(target)
    as "and the same as the database the fixture was written from"
}

pub fn the_fixture_is_data_only_sql_with_the_accounts_before_the_characters_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = folder <> "/" <> fixture.file_name
  assert fixture.write(source, path) == Ok(Nil)
  let assert Ok(text) = simplifile.read(path) as "the fixture reads"
  let statements = string.split(text, ";\n") |> list.filter(fn(s) { s != "" })
  assert list.all(statements, fn(statement) {
    string.starts_with(statement, "insert into ")
    || string.starts_with(statement, "select setval(")
  })
    as "every statement inserts a row or moves a sequence: no schema, no drop"
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
}

pub fn a_row_inserted_after_the_fixture_gets_an_id_above_the_largest_kept_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let source = pool()
  insert_rows(source)
  let path = folder <> "/" <> fixture.file_name
  assert fixture.write(source, path) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  let ids =
    query_texts(
      target,
      "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values (1, 'Later', 0, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0) returning character_id::text",
    )
  assert ids == ["7"]
    as "the character sequence goes on after 6, the largest id the fixture holds"
  let assert Ok(account) =
    pog.query(
      "insert into account (login_name, srp_salt, srp_verifier, game_account_id) values ('later', '\\x01'::bytea, '\\x02'::bytea, '11111111-2222-3333-4444-555555555555') returning account_id",
    )
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(target)
    as "an account was inserted"
  assert account.rows == [5] as "and the account sequence after 4"
}

pub fn a_database_with_no_rows_gives_a_fixture_that_applies_as_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let path = folder <> "/" <> fixture.file_name
  assert fixture.write(pool(), path) == Ok(Nil)
  let target = pool()
  assert fixture.apply(target, path) == Ok(Nil)
  assert rows(target) == [] as "no row was made"
}

pub fn a_fixture_with_a_statement_the_database_refuses_leaves_no_row_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let path = folder <> "/" <> fixture.file_name
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
  let path = folder <> "/" <> fixture.file_name
  let source = pool()
  assert fixture.write(source, path) == Ok(Nil)
  let assert Error(FileFailed(path: failed, ..)) = fixture.write(source, path)
    as "a file already there is never overwritten"
  assert failed == path
  let assert Error(FileFailed(path: missing, ..)) =
    fixture.apply(source, folder <> "/none.sql")
    as "a fixture that is not there cannot be applied"
  assert missing == folder <> "/none.sql"
}
