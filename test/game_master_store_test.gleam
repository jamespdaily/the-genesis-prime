//// The game master data in Postgres (tests 1, 3, 4 and 5 of the step's list).
//// Each test has a database of its own made from the migrated template
//// (`template_database`). No client evidence exists for game master commands;
//// the expected values are the issue's rules and the approved list: a new
//// account holds no permission, granting and revoking need the `grant`
//// permission and each write their permission row and their log row, a
//// refused use writes only its log row, every use is logged with the account,
//// the command and its arguments, allowed or refused, and written through the
//// logging module at info, and the first `grant` is given only while no
//// account holds it. A use is made as the dev tool makes it: the account's
//// permissions are read, the rule decides, and the store carries the decision
//// out and logs it.

import genesis_prime/game_master/command.{
  type LoggedUse, type Outcome, Allowed, FirstGrantOver, LoggedUse,
  MissingPermission, Refused, UnknownPermission,
}
import genesis_prime/game_master/grant.{
  GivePermission, GrantPermission, RevokePermission,
}
import genesis_prime/game_master/permission.{type Permission, Grant, Other}
import genesis_prime/game_master/store.{AlreadyHeld, QueryFailed}
import genesis_prime/login/account_store
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string
import log_capture.{Text, Whole}
import owned_test
import pog
import template_database.{type Database}

/// How long a test waits for a line its own process has already written, in
/// milliseconds. The line is delivered before the call that wrote it returns.
const line_wait_ms = 1000

/// An id no account has: the table's ids are numbered from 1.
const no_such_account = 987_654

/// Adds an account and gives its id.
fn account(database: Database, name: String) -> Int {
  let assert Ok(created) =
    account_store.create(database.connection, name, "secret")
    as "the account is created"
  created.id
}

/// Gives an account `grant` without a command, so a test starts from an
/// account that may grant.
fn holds_grant(database: Database, account: Int) -> Nil {
  let assert Ok(Nil) =
    store.apply_grant(
      connection: database.connection,
      effect: GivePermission(account:, permission: Grant),
    )
    as "the permission is given"
  Nil
}

/// The use of a grant or revoke command by an account, made as the dev tool
/// makes it.
fn use_command(
  database database: Database,
  by actor: Int,
  command command: grant.Command,
) -> Result(Outcome, store.StoreError) {
  let assert Ok(permissions) =
    store.permissions_of(connection: database.connection, account: actor)
    as "the account's permissions are read"
  store.carry_out(
    connection: database.connection,
    used: grant.to_use(account: actor, command:),
    decision: grant.rule(permissions:, command:),
    apply: store.apply_grant,
  )
}

fn permissions_of(database: Database, account: Int) -> Set(Permission) {
  let assert Ok(permissions) =
    store.permissions_of(connection: database.connection, account:)
    as "the account's permissions are read"
  permissions
}

fn uses_of(database: Database, account: Int) -> List(LoggedUse) {
  let assert Ok(uses) = store.uses_of(connection: database.connection, account:)
    as "the account's uses are read"
  uses
}

fn operator_uses(database: Database) -> List(LoggedUse) {
  let assert Ok(uses) = store.operator_uses(connection: database.connection)
    as "the operator's uses are read"
  uses
}

// Test 1.

pub fn a_new_account_has_no_permissions_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  assert permissions_of(database, jim) == set.new()
    as "the issue: a new account has no permissions"
  assert uses_of(database, jim) == [] as "a new account has used no command"
}

pub fn a_saved_permission_name_the_code_does_not_know_is_read_as_other_and_gives_no_right_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  let assert Ok(_) =
    pog.query("insert into permission (account_id, name) values ($1, $2)")
    |> pog.parameter(pog.int(jim))
    |> pog.parameter(pog.text("teleport"))
    |> pog.execute(on: database.connection)
    as "a row of a name the code does not know is saved, as an older or newer server could have saved it"
  assert permissions_of(database, jim) == set.from_list([Other("teleport")])
    as "the issue: a name read that the code does not know is Other(name), decoded at the edge and not lost"
  assert use_command(
      database:,
      by: jim,
      command: GrantPermission(target: sam, permission: Grant),
    )
    == Ok(Refused(MissingPermission(required: Grant)))
    as "named permissions grant exactly what is listed: an unknown name is not `grant`"
  assert permissions_of(database, sam) == set.new()
    as "the refused grant writes no permission row"
}

// Test 3.

pub fn granting_gives_the_target_the_permission_and_logs_the_use_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  holds_grant(database, jim)
  assert use_command(
      database:,
      by: jim,
      command: GrantPermission(target: sam, permission: Grant),
    )
    == Ok(Allowed)
    as "test 3: an account that holds `grant` may grant"
  assert permissions_of(database, sam) == set.from_list([Grant])
    as "test 3: a grant writes the permission row"
  assert uses_of(database, jim)
    == [
      LoggedUse(
        actor: Some(jim),
        command: "grant",
        arguments: "target=" <> int.to_string(sam) <> " permission=grant",
        outcome: Allowed,
      ),
    ]
    as "test 3: a grant writes its log row, with the account, the command and its arguments"
}

pub fn revoking_takes_the_permission_from_the_target_and_logs_the_use_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  holds_grant(database, jim)
  holds_grant(database, sam)
  assert use_command(
      database:,
      by: jim,
      command: RevokePermission(target: sam, permission: Grant),
    )
    == Ok(Allowed)
    as "test 3: an account that holds `grant` may revoke"
  assert permissions_of(database, sam) == set.new()
    as "test 3: a revoke removes the permission row"
  assert permissions_of(database, jim) == set.from_list([Grant])
    as "a revoke takes the permission from the target only"
  assert uses_of(database, jim)
    == [
      LoggedUse(
        actor: Some(jim),
        command: "revoke",
        arguments: "target=" <> int.to_string(sam) <> " permission=grant",
        outcome: Allowed,
      ),
    ]
    as "test 3: a revoke writes its log row"
}

pub fn a_refused_grant_writes_only_the_log_row_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  assert use_command(
      database:,
      by: sam,
      command: GrantPermission(target: jim, permission: Grant),
    )
    == Ok(Refused(MissingPermission(required: Grant)))
    as "test 3: an account without `grant` is refused, and the use ends without an error"
  assert permissions_of(database, jim) == set.new()
    as "test 3: a refused grant writes no permission row"
  assert permissions_of(database, sam) == set.new()
    as "a refused grant gives the account that asked nothing either"
  assert uses_of(database, sam)
    == [
      LoggedUse(
        actor: Some(sam),
        command: "grant",
        arguments: "target=" <> int.to_string(jim) <> " permission=grant",
        outcome: Refused(MissingPermission(required: Grant)),
      ),
    ]
    as "test 3: a refused grant writes its log row"
}

pub fn granting_a_permission_held_and_revoking_one_not_held_change_nothing_and_are_allowed_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  holds_grant(database, jim)
  holds_grant(database, sam)
  assert use_command(
      database:,
      by: jim,
      command: GrantPermission(target: sam, permission: Grant),
    )
    == Ok(Allowed)
    as "a grant of a permission the target holds is allowed"
  assert permissions_of(database, sam) == set.from_list([Grant])
    as "the target holds the permission once"
  let lee = account(database, "lee")
  assert use_command(
      database:,
      by: jim,
      command: RevokePermission(target: lee, permission: Grant),
    )
    == Ok(Allowed)
    as "a revoke of a permission the target does not hold is allowed"
  assert permissions_of(database, lee) == set.new()
    as "the target still holds nothing"
  assert list.length(uses_of(database, jim)) == 2
    as "each of the two uses is logged"
}

// Test 4.

pub fn every_use_is_logged_in_order_allowed_or_refused_with_its_reason_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  let sam_text = int.to_string(sam)
  let assert Ok(_) =
    use_command(
      database:,
      by: jim,
      command: GrantPermission(target: sam, permission: Grant),
    )
    as "the use is made and ends without a database error"
  holds_grant(database, jim)
  let assert Ok(_) =
    use_command(
      database:,
      by: jim,
      command: GrantPermission(target: sam, permission: Other("teleport")),
    )
    as "the use is made and ends without a database error"
  let assert Ok(_) =
    use_command(
      database:,
      by: jim,
      command: GrantPermission(target: sam, permission: Grant),
    )
    as "the use is made and ends without a database error"
  assert uses_of(database, jim)
    == [
      LoggedUse(
        actor: Some(jim),
        command: "grant",
        arguments: "target=" <> sam_text <> " permission=grant",
        outcome: Refused(MissingPermission(required: Grant)),
      ),
      LoggedUse(
        actor: Some(jim),
        command: "grant",
        arguments: "target=" <> sam_text <> " permission=teleport",
        outcome: Refused(UnknownPermission(name: "teleport")),
      ),
      LoggedUse(
        actor: Some(jim),
        command: "grant",
        arguments: "target=" <> sam_text <> " permission=grant",
        outcome: Allowed,
      ),
    ]
    as "test 4: each use is logged in the order it was made, with its outcome and, when refused, why"
}

pub fn each_use_is_written_through_the_logging_module_at_info_with_its_account_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  let capture = log_capture.start()
  let assert Ok(_) =
    use_command(
      database:,
      by: sam,
      command: GrantPermission(target: jim, permission: Grant),
    )
    as "the use is made and ends without a database error"
  let assert Ok(refused) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "a refused use is logged"
  assert refused.level == "info"
    as "the issue: each use is logged through the logging module at info"
  assert dict.get(refused.metadata, "account") == Ok(Whole(sam))
    as "designing-processes, Logging: the line carries the account"
  assert dict.get(refused.metadata, "process") == Ok(Text("game_master"))
    as "designing-processes, Logging: the line carries where it is written from"
  assert string.contains(refused.text, "refused")
    as "the line says how the use ended"
  assert string.contains(refused.text, "grant") as "the line names the command"
  assert string.contains(
    refused.text,
    "target=" <> int.to_string(jim) <> " permission=grant",
  )
    as "the line gives the arguments"
  holds_grant(database, sam)
  let assert Ok(_) =
    use_command(
      database:,
      by: sam,
      command: GrantPermission(target: jim, permission: Grant),
    )
    as "the use is made and ends without a database error"
  let assert Ok(allowed) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "an allowed use is logged"
  assert allowed.level == "info"
  assert string.contains(allowed.text, "allowed")
    as "the line says how the use ended"
}

pub fn an_allowed_command_whose_effect_fails_is_logged_at_warning_and_writes_no_row_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  holds_grant(database, jim)
  let capture = log_capture.start()
  let result =
    use_command(
      database:,
      by: jim,
      command: GrantPermission(target: no_such_account, permission: Grant),
    )
  assert case result {
    Error(QueryFailed(pog.ConstraintViolated(..))) -> True
    _ -> False
  }
    as "migration 0003: a permission row names an account that exists, so the write fails"
  assert uses_of(database, jim) == []
    as "the transaction is rolled back, so no log row is written"
  let assert Ok(line) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the failure is logged, so no use goes unlogged"
  assert line.level == "warning"
    as "designing-processes, Logging: an outside failure is a warning"
  assert dict.get(line.metadata, "account") == Ok(Whole(jim))
    as "the line carries the account that used the command"
  assert string.contains(line.text, "grant") as "the line names the command"
  assert string.contains(
    line.text,
    "target=" <> int.to_string(no_such_account) <> " permission=grant",
  )
    as "the line gives the arguments"
}

// Test 5.

pub fn the_first_grant_is_given_while_no_account_holds_it_and_is_logged_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  assert store.give_first(
      connection: database.connection,
      account: jim,
      permission: Grant,
    )
    == Ok(Nil)
    as "test 5: the first grant is given while no account holds `grant`"
  assert permissions_of(database, jim) == set.from_list([Grant])
    as "test 5: the account holds `grant` afterwards"
  assert operator_uses(database)
    == [
      LoggedUse(
        actor: None,
        command: "first_grant",
        arguments: "account=" <> int.to_string(jim) <> " permission=grant",
        outcome: Allowed,
      ),
    ]
    as "the first grant is a use, logged with no acting account and the account it gave the permission to"
}

pub fn a_first_grant_is_refused_and_logged_once_an_account_holds_grant_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let sam = account(database, "sam")
  let assert Ok(Nil) =
    store.give_first(
      connection: database.connection,
      account: jim,
      permission: Grant,
    )
    as "the first grant is given"
  assert store.give_first(
      connection: database.connection,
      account: sam,
      permission: Grant,
    )
    == Error(AlreadyHeld)
    as "test 5: after an account holds `grant`, the first grant is refused"
  assert permissions_of(database, sam) == set.new()
    as "a refused first grant writes no permission row"
  assert operator_uses(database)
    == [
      LoggedUse(
        actor: None,
        command: "first_grant",
        arguments: "account=" <> int.to_string(jim) <> " permission=grant",
        outcome: Allowed,
      ),
      LoggedUse(
        actor: None,
        command: "first_grant",
        arguments: "account=" <> int.to_string(sam) <> " permission=grant",
        outcome: Refused(FirstGrantOver(permission: Grant)),
      ),
    ]
    as "a refused first grant is logged as refused, after the one that was allowed"
}

pub fn a_first_grant_is_written_through_the_logging_module_at_info_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let jim = account(database, "jim")
  let capture = log_capture.start()
  let assert Ok(Nil) =
    store.give_first(
      connection: database.connection,
      account: jim,
      permission: Grant,
    )
    as "the first grant is given"
  let assert Ok(line) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the first grant is logged"
  assert line.level == "info"
    as "the issue: each use is logged through the logging module at info"
  assert dict.has_key(line.metadata, "account") == False
    as "the database's operator, and no account, made the first grant"
  assert string.contains(line.text, "first_grant")
    as "the line names the command"
  assert string.contains(
    line.text,
    "account=" <> int.to_string(jim) <> " permission=grant",
  )
    as "the line names the account given the permission"
}
