//// The rows a recorded session starts from, saved beside its recordings as a
//// file of data-only SQL (`INSERT` statements for the account, character,
//// character item, character currency and character quest tables, no schema), so
//// a replay applies every migration and then the fixture, and the session finds
//// the same account, characters, held items, currencies and quests it found live.
////
//// - **What is kept.** The accounts the session names by login name, their
////   characters and the items, currencies and quests those characters hold, never
////   the rest of the database, and every column of the five tables but
////   `created_at`, which no flow reads. The ids and an item's guid are identity columns, so each insert
////   overrides its own. A statement after the rows of each table sets its
////   sequence to where the live database's stood (its last value and whether it
////   had given one), so a row a replay makes gets the id or guid it got live,
////   whatever rows the live database lost since: a deleted character or item, a
////   rolled-back insert, a row of another account. The currency and quest tables
////   have no id to restore.
//// - **The order.** Accounts first, then the characters that reference them,
////   then the items, currencies and quests that reference the characters.
//// - **The file.** One statement for each row, each ending in a semicolon and a
////   line feed. A text is quoted by doubling its quotes and a byte string is
////   written in hexadecimal, so no value is read as SQL; the tables' columns
////   hold no line feed followed by a semicolon (a login name or a character
////   name is letters and a space; an item row holds numbers only).
//// - **Applying.** The statements run in one transaction, so a statement the
////   database refuses leaves no row of the file behind. A file with no currency
////   or quest statement leaves those tables empty, as a file written before they
////   were kept does.

import genesis_prime/store/worker
import genesis_prime/wire_recording
import genesis_prime/wire_recording/fixture/sql
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pog
import simplifile

/// Why the fixture could not be written or applied.
pub type FixtureError {
  /// The file could not be read or written.
  FileFailed(path: String, reason: String)
  /// The database refused a statement, naming it.
  StatementFailed(statement: String, reason: String)
  /// The database holds no account with this login name, so the session's
  /// fixture would hold nothing of it.
  NoSuchAccount(login_name: String)
  /// The database could not be asked for its rows, or could not be reached.
  DatabaseFailed(reason: String)
}

/// Saves the accounts of `login_names`, their characters and the items,
/// currencies and quests those characters hold from the database `database`
/// reaches, and where its three sequences stand, as data-only SQL in the file at
/// `path`, in an order that satisfies each table's references. A
/// login name the database has no account for is `NoSuchAccount`, and a file
/// already there is never overwritten. A sitting writes it before it accepts
/// the first connection (genesis_prime/sitting).
pub fn write(
  database database: pog.Connection,
  path path: String,
  login_names login_names: List(String),
) -> Result(Nil, FixtureError) {
  use accounts <- result.try(
    sql.accounts_named(database, login_names)
    |> result.map_error(database_failed),
  )
  use Nil <- result.try(
    list.try_each(login_names, fn(login_name) {
      case list.any(accounts.rows, fn(row) { row.login_name == login_name }) {
        True -> Ok(Nil)
        False -> Error(NoSuchAccount(login_name:))
      }
    }),
  )
  use characters <- result.try(
    sql.characters_of_accounts_named(database, login_names)
    |> result.map_error(database_failed),
  )
  use items <- result.try(
    sql.items_of_characters_of_accounts_named(database, login_names)
    |> result.map_error(database_failed),
  )
  use currencies <- result.try(
    sql.currencies_of_characters_of_accounts_named(database, login_names)
    |> result.map_error(database_failed),
  )
  use quests <- result.try(
    sql.quests_of_characters_of_accounts_named(database, login_names)
    |> result.map_error(database_failed),
  )
  use account_sequence <- result.try(
    sql.account_sequence(database) |> result.map_error(database_failed),
  )
  use character_sequence <- result.try(
    sql.character_sequence(database) |> result.map_error(database_failed),
  )
  use item_sequence <- result.try(
    sql.character_item_sequence(database) |> result.map_error(database_failed),
  )
  let assert [account_sequence] = account_sequence.rows
    as "a sequence holds one row"
  let assert [character_sequence] = character_sequence.rows
    as "a sequence holds one row"
  let assert [item_sequence] = item_sequence.rows as "a sequence holds one row"
  use Nil <- result.try(
    simplifile.create_file(path) |> result.map_error(file_failed(path)),
  )
  simplifile.write(
    path,
    render(
      accounts: accounts.rows,
      account_sequence: Sequence(
        last_value: account_sequence.last_value,
        is_called: account_sequence.is_called,
      ),
      characters: characters.rows,
      character_sequence: Sequence(
        last_value: character_sequence.last_value,
        is_called: character_sequence.is_called,
      ),
      items: items.rows,
      item_sequence: Sequence(
        last_value: item_sequence.last_value,
        is_called: item_sequence.is_called,
      ),
      currencies: currencies.rows,
      quests: quests.rows,
    ),
  )
  |> result.map_error(file_failed(path))
}

/// Where an id sequence stands: the last value it gave, or the value it gives
/// first when `is_called` is false.
type Sequence {
  Sequence(last_value: Int, is_called: Bool)
}

/// The text of a fixture file for these rows: an insert for each account, the
/// statement that sets the account id sequence, an insert for each character, the
/// statement that sets the character id sequence, an insert for each item, the
/// statement that sets the item guid sequence, and an insert for each currency
/// and each quest.
fn render(
  accounts accounts: List(sql.AccountsNamedRow),
  account_sequence account_sequence: Sequence,
  characters characters: List(sql.CharactersOfAccountsNamedRow),
  character_sequence character_sequence: Sequence,
  items items: List(sql.ItemsOfCharactersOfAccountsNamedRow),
  item_sequence item_sequence: Sequence,
  currencies currencies: List(sql.CurrenciesOfCharactersOfAccountsNamedRow),
  quests quests: List(sql.QuestsOfCharactersOfAccountsNamedRow),
) -> String {
  string.concat(
    list.flatten([
      list.map(accounts, account_statement),
      [
        sequence_statement(
          table: "account",
          column: "account_id",
          state: account_sequence,
        ),
      ],
      list.map(characters, character_statement),
      [
        sequence_statement(
          table: "character",
          column: "character_id",
          state: character_sequence,
        ),
      ],
      list.map(items, item_statement),
      [
        sequence_statement(
          table: "character_item",
          column: "item_guid",
          state: item_sequence,
        ),
      ],
      list.map(currencies, currency_statement),
      list.map(quests, quest_statement),
    ]),
  )
}

/// Runs the statements of the fixture file at `path`, in one transaction, on
/// the database `database` reaches, which holds the schema and no rows.
pub fn apply(
  database database: pog.Connection,
  path path: String,
) -> Result(Nil, FixtureError) {
  use text <- result.try(
    simplifile.read(path) |> result.map_error(file_failed(path)),
  )
  let statements =
    string.split(text, ";\n") |> list.filter(fn(statement) { statement != "" })
  pog.transaction(database, fn(connection) {
    list.try_each(statements, fn(statement) {
      pog.query(statement)
      |> pog.execute(connection)
      |> result.map(fn(_returned) { Nil })
      |> result.map_error(fn(error) {
        StatementFailed(statement:, reason: worker.describe_query_error(error))
      })
    })
  })
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionRolledBack(failed) -> failed
      pog.TransactionQueryError(error) ->
        DatabaseFailed(reason: worker.describe_query_error(error))
    }
  })
}

/// The name of the fixture's file inside a recording folder.
pub const file_name = "fixture.sql"

fn account_statement(row: sql.AccountsNamedRow) -> String {
  "insert into account (account_id, login_name, srp_salt, srp_verifier, game_account_id) overriding system value values ("
  <> string.join(
    [
      int.to_string(row.account_id),
      text(row.login_name),
      bytes(row.srp_salt),
      bytes(row.srp_verifier),
      text(row.game_account_id),
    ],
    ", ",
  )
  <> ");\n"
}

fn character_statement(row: sql.CharactersOfAccountsNamedRow) -> String {
  "insert into character (character_id, account_id, session_epoch, save_sequence, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z, rotation_yaw, rotation_pitch, rotation_roll, look_labels, look_values, bones, needs_rename, health, experience) overriding system value values ("
  <> string.join(
    [
      int.to_string(row.character_id),
      int.to_string(row.account_id),
      int.to_string(row.session_epoch),
      int.to_string(row.save_sequence),
      text(row.name),
      int.to_string(row.gender),
      int.to_string(row.race_id),
      int.to_string(row.class_id),
      int.to_string(row.faction_id),
      int.to_string(row.level),
      int.to_string(row.path),
      int.to_string(row.world_id),
      int.to_string(row.world_zone_id),
      real(row.position_x),
      real(row.position_y),
      real(row.position_z),
      real(row.rotation_yaw),
      real(row.rotation_pitch),
      real(row.rotation_roll),
      integers(row.look_labels),
      integers(row.look_values),
      integers(row.bones),
      bool(row.needs_rename),
      optional_integer(row.health),
      optional_integer(row.experience),
    ],
    ", ",
  )
  <> ");\n"
}

fn item_statement(row: sql.ItemsOfCharactersOfAccountsNamedRow) -> String {
  "insert into character_item (item_guid, character_id, item2_id, location, bag_index, stack_count) overriding system value values ("
  <> string.join(
    [
      int.to_string(row.item_guid),
      int.to_string(row.character_id),
      int.to_string(row.item2_id),
      int.to_string(row.location),
      int.to_string(row.bag_index),
      int.to_string(row.stack_count),
    ],
    ", ",
  )
  <> ");\n"
}

fn currency_statement(
  row: sql.CurrenciesOfCharactersOfAccountsNamedRow,
) -> String {
  "insert into character_currency (character_id, currency_type_id, amount) values ("
  <> string.join(
    [
      int.to_string(row.character_id),
      int.to_string(row.currency_type_id),
      int.to_string(row.amount),
    ],
    ", ",
  )
  <> ");\n"
}

/// The state of a completed quest, the only state whose row holds a time
/// (`character_quest_completed_has_a_time`, migration 0021).
const completed_quest_state = 3

fn quest_statement(row: sql.QuestsOfCharactersOfAccountsNamedRow) -> String {
  "insert into character_quest (character_id, quest_id, state, completed_at, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left) values ("
  <> string.join(
    [
      int.to_string(row.character_id),
      int.to_string(row.quest_id),
      int.to_string(row.state),
      case row.state == completed_quest_state {
        True -> instant(row.completed_at_microseconds)
        False -> "null"
      },
      optional_integer(row.placeholder_objective_id),
      optional_bool(row.tracked),
      optional_integer(row.done_mask),
      optional_integers(row.progress),
      optional_integer(row.quest_ms_left),
      optional_integers(row.objective_ms_left),
    ],
    ", ",
  )
  <> ");\n"
}

/// The statement that sets the id sequence of `table` to `state`.
fn sequence_statement(
  table table: String,
  column column: String,
  state state: Sequence,
) -> String {
  "select setval(pg_get_serial_sequence('"
  <> table
  <> "', '"
  <> column
  <> "'), "
  <> int.to_string(state.last_value)
  <> ", "
  <> bool(state.is_called)
  <> ");\n"
}

/// A text as an SQL literal, its quotes doubled.
fn text(value: String) -> String {
  "'" <> string.replace(value, "'", "''") <> "'"
}

/// A byte string as the call of `decode` on its hexadecimal, which does not
/// depend on how the database reads backslashes in a literal.
fn bytes(value: BitArray) -> String {
  "decode('" <> wire_recording.hex(value) <> "', 'hex')"
}

/// A `real` column's value as a literal of its own type: the float is the
/// column's 32 bits widened, so writing it back gives the same 32 bits.
fn real(value: Float) -> String {
  "'" <> float.to_string(value) <> "'::real"
}

/// A nullable `integer` column's value: its number, or NULL when there is none.
fn optional_integer(value: Option(Int)) -> String {
  case value {
    Some(value) -> int.to_string(value)
    None -> "null"
  }
}

/// A `timestamptz` column's value from its Unix time in whole microseconds, the
/// column's own precision, as an interval after the epoch so no float rounds it.
fn instant(microseconds: Int) -> String {
  "'epoch'::timestamptz + '"
  <> int.to_string(microseconds)
  <> " microseconds'::interval"
}

/// A nullable `boolean` column's value: true or false, or NULL when there is none.
fn optional_bool(value: Option(Bool)) -> String {
  case value {
    Some(value) -> bool(value)
    None -> "null"
  }
}

/// A nullable `integer[]` column's value: its numbers, or NULL when there is none.
fn optional_integers(values: Option(List(Int))) -> String {
  case values {
    Some(values) ->
      "'{"
      <> string.join(list.map(values, int.to_string), ",")
      <> "}'::integer[]"
    None -> "null"
  }
}

fn integers(values: List(Int)) -> String {
  "'{" <> string.join(list.map(values, int.to_string), ",") <> "}'::bigint[]"
}

fn bool(value: Bool) -> String {
  string.lowercase(bool.to_string(value))
}

fn file_failed(path: String) -> fn(simplifile.FileError) -> FixtureError {
  fn(error) { FileFailed(path:, reason: simplifile.describe_error(error)) }
}

fn database_failed(error: pog.QueryError) -> FixtureError {
  DatabaseFailed(reason: worker.describe_query_error(error))
}
