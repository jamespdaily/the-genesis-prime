//// The rows a recorded session starts from, saved beside its recordings as a
//// file of data-only SQL (`INSERT` statements for the account, character,
//// character item, character currency, character quest and character action slot
//// tables, no schema), so a replay applies every migration and then the fixture,
//// and the session finds the same account, characters, held items, currencies,
//// quests and saved action bars it found live.
////
//// - **What is kept.** The accounts the session names by login name, their
////   characters and the items, currencies, quests and action slots those
////   characters hold, never the rest of the database, and every column of the six
////   tables but
////   `created_at`, which no flow reads. The ability tiers and the AMPs a character holds
////   (`character_ability_tier`, `character_action_amp`) are not kept (a gap, listed in `gaps`). The ids and an item's guid are identity
////   columns, so each insert overrides its own. A statement after the rows of each table sets its
////   sequence to where the live database's stood (its last value and whether it
////   had given one), so a row a replay makes gets the id or guid it got live,
////   whatever rows the live database lost since: a deleted character or item, a
////   rolled-back insert, a row of another account. The currency, quest and action
////   slot tables have no id to restore.
//// - **The order.** Accounts first, then the characters that reference them,
////   then the items, currencies, quests and action slots that reference the
////   characters.
//// - **The file.** One statement for each row, each ending in a semicolon and a
////   line feed. A text is quoted by doubling its quotes and a byte string is
////   written in hexadecimal, so no value is read as SQL; the tables' columns
////   hold no line feed followed by a semicolon (a login name or a character
////   name is letters and a space; an item row holds numbers only).
//// - **Applying.** The statements run in one transaction, so a statement the
////   database refuses leaves no row of the file behind. A file with no currency,
////   quest or action slot statement leaves those tables empty, as a file written
////   before they were kept does.

import genesis_prime/gap
import genesis_prime/store/worker
import genesis_prime/wire_recording
import genesis_prime/wire_recording/fixture/sql
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import pog
import simplifile

/// What the fixture leaves undone, for the coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Recorded sessions",
      missing: "a replay's starting rows hold no ability tier and no AMP, so a character that held spent tiers or picked AMPs when the session was recorded enters every ability at tier 1 with no AMP and the replay shows it with its points unspent.",
    ),
  ]
}

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
/// currencies, quests and action slots those characters hold from the database
/// `database` reaches, and where its three sequences stand, as data-only SQL in the file at
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
  use characters <- result.try(read(
    sql.characters_of_accounts_named,
    database,
    login_names,
  ))
  use items <- result.try(read(
    sql.items_of_characters_of_accounts_named,
    database,
    login_names,
  ))
  use currencies <- result.try(read(
    sql.currencies_of_characters_of_accounts_named,
    database,
    login_names,
  ))
  use quests <- result.try(read(
    sql.quests_of_characters_of_accounts_named,
    database,
    login_names,
  ))
  use action_slots <- result.try(read(
    sql.action_slots_of_characters_of_accounts_named,
    database,
    login_names,
  ))
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
      action_slots: action_slots.rows,
    ),
  )
  |> result.map_error(file_failed(path))
}

/// The rows one of the fixture's queries reads for the characters of the accounts
/// with these login names.
fn read(
  query: fn(pog.Connection, List(String)) ->
    Result(pog.Returned(row), pog.QueryError),
  database: pog.Connection,
  login_names: List(String),
) -> Result(pog.Returned(row), FixtureError) {
  query(database, login_names) |> result.map_error(database_failed)
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
/// and each quest and action slot.
fn render(
  accounts accounts: List(sql.AccountsNamedRow),
  account_sequence account_sequence: Sequence,
  characters characters: List(sql.CharactersOfAccountsNamedRow),
  character_sequence character_sequence: Sequence,
  items items: List(sql.ItemsOfCharactersOfAccountsNamedRow),
  item_sequence item_sequence: Sequence,
  currencies currencies: List(sql.CurrenciesOfCharactersOfAccountsNamedRow),
  quests quests: List(sql.QuestsOfCharactersOfAccountsNamedRow),
  action_slots action_slots: List(sql.ActionSlotsOfCharactersOfAccountsNamedRow),
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
      list.map(action_slots, action_slot_statement),
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

/// The statement that inserts one row into `table`: `values` are the literals of
/// `columns`, in order. `identity` is true for a table whose id is an identity
/// column, which the insert then overrides with the row's own.
fn insert_statement(
  table table: String,
  identity identity: Bool,
  columns columns: List(String),
  values values: List(String),
) -> String {
  "insert into "
  <> table
  <> " ("
  <> string.join(columns, ", ")
  <> ")"
  <> case identity {
    True -> " overriding system value"
    False -> ""
  }
  <> " values ("
  <> string.join(values, ", ")
  <> ");\n"
}

fn account_statement(row: sql.AccountsNamedRow) -> String {
  insert_statement(
    table: "account",
    identity: True,
    columns: [
      "account_id", "login_name", "srp_salt", "srp_verifier", "game_account_id",
    ],
    values: [
      int.to_string(row.account_id),
      text(row.login_name),
      bytes(row.srp_salt),
      bytes(row.srp_verifier),
      text(row.game_account_id),
    ],
  )
}

fn character_statement(row: sql.CharactersOfAccountsNamedRow) -> String {
  insert_statement(
    table: "character",
    identity: True,
    columns: [
      "character_id", "account_id", "session_epoch", "save_sequence", "name",
      "gender", "race_id", "class_id", "faction_id", "level", "path", "world_id",
      "world_zone_id", "position_x", "position_y", "position_z", "rotation_yaw",
      "rotation_pitch", "rotation_roll", "look_labels", "look_values", "bones",
      "needs_rename", "health", "experience",
    ],
    values: [
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
      nullable(row.health, int.to_string),
      nullable(row.experience, int.to_string),
    ],
  )
}

fn item_statement(row: sql.ItemsOfCharactersOfAccountsNamedRow) -> String {
  insert_statement(
    table: "character_item",
    identity: True,
    columns: [
      "item_guid", "character_id", "item2_id", "location", "bag_index",
      "stack_count", "random_stats", "charges", "item_flags",
      "expires_at_unix_ms",
    ],
    values: [
      int.to_string(row.item_guid),
      int.to_string(row.character_id),
      int.to_string(row.item2_id),
      int.to_string(row.location),
      int.to_string(row.bag_index),
      int.to_string(row.stack_count),
      int.to_string(row.random_stats),
      nullable(row.charges, int.to_string),
      int.to_string(row.item_flags),
      nullable(row.expires_at_unix_ms, int.to_string),
    ],
  )
}

fn currency_statement(
  row: sql.CurrenciesOfCharactersOfAccountsNamedRow,
) -> String {
  insert_statement(
    table: "character_currency",
    identity: False,
    columns: ["character_id", "currency_type_id", "amount"],
    values: [
      int.to_string(row.character_id),
      int.to_string(row.currency_type_id),
      int.to_string(row.amount),
    ],
  )
}

/// The state of a completed quest, the only state whose row holds a time
/// (`character_quest_completed_has_a_time`, migration 0021).
const completed_quest_state = 3

fn quest_statement(row: sql.QuestsOfCharactersOfAccountsNamedRow) -> String {
  insert_statement(
    table: "character_quest",
    identity: False,
    columns: [
      "character_id", "quest_id", "state", "completed_at",
      "placeholder_objective_id", "tracked", "done_mask", "progress",
      "quest_ms_left", "objective_ms_left", "kill_mask", "used_objective",
      "used_spawn",
    ],
    values: [
      int.to_string(row.character_id),
      int.to_string(row.quest_id),
      int.to_string(row.state),
      case row.state == completed_quest_state {
        True -> instant(row.completed_at_microseconds)
        False -> "null"
      },
      nullable(row.placeholder_objective_id, int.to_string),
      nullable(row.tracked, bool),
      nullable(row.done_mask, int.to_string),
      nullable(row.progress, integers),
      nullable(row.quest_ms_left, int.to_string),
      nullable(row.objective_ms_left, integers),
      nullable(row.kill_mask, integers),
      integers(row.used_objective),
      integers(row.used_spawn),
    ],
  )
}

fn action_slot_statement(
  row: sql.ActionSlotsOfCharactersOfAccountsNamedRow,
) -> String {
  insert_statement(
    table: "character_action_slot",
    identity: False,
    columns: ["character_id", "action_set", "slot", "spell4_base_id"],
    values: [
      int.to_string(row.character_id),
      int.to_string(row.action_set),
      int.to_string(row.slot),
      nullable(row.spell4_base_id, int.to_string),
    ],
  )
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

/// A nullable column's value: `render` of its value, or NULL when there is none.
fn nullable(value: Option(a), render: fn(a) -> String) -> String {
  value |> option.map(render) |> option.unwrap("null")
}

/// A `timestamptz` column's value from its Unix time in whole microseconds, the
/// column's own precision, as an interval after the epoch so no float rounds it.
fn instant(microseconds: Int) -> String {
  "'epoch'::timestamptz + '"
  <> int.to_string(microseconds)
  <> " microseconds'::interval"
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
