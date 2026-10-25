import database_support
import gleam/dynamic/decode
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import owned_test
import pog
import template_database

const create_table =
  "create table saved_account (key integer primary key, marker integer not null)"

/// Code that opens its own `pog.transaction` commits and rolls back as it does
/// in the server: a commit is visible on another connection, and a rollback
/// undoes only the transaction's writes, not what the test wrote before it.
pub fn code_that_opens_its_own_transaction_commits_and_rolls_back_as_in_the_server_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  create_saved_account(database.connection)
  insert_row(on: database.connection, key: 1, marker: 1)
  assert save_accounts(on: database.connection, keys: [10, 11], then_fail: True)
    == Error(pog.TransactionRolledBack(
      "the transaction failed after its writes",
    ))
  assert read_every_row(database.connection) == [#(1, 1)]
  assert save_accounts(
      on: database.connection,
      keys: [10, 11],
      then_fail: False,
    )
    == Ok(Nil)
  let other_pool = process.new_name("other_connection")
  let assert Ok(_) =
    pog.start(template_database.config(database, other_pool, 1))
    as "the second pool did not start"
  assert read_every_row(pog.named_connection(other_pool))
    == [#(1, 1), #(10, 3), #(11, 3)]
}

type Message {
  ReadEveryRow(reply: Subject(List(#(Int, Int))))
}

/// A supervised process the test starts reads, through its own pool, the rows
/// the test wrote, as a save worker reads what the game wrote.
pub fn a_supervised_process_with_its_own_connection_sees_the_tests_data_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  create_saved_account(database.connection)
  insert_row(on: database.connection, key: 50, marker: 4)
  let pool_name = process.new_name("supervised_pool")
  let reader = process.new_name("supervised_reader")
  let connection = pog.named_connection(pool_name)
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(
      pog.supervised(template_database.config(database, pool_name, 1)),
    )
    |> static_supervisor.add(
      supervision.worker(fn() { start_reader(connection, reader) }),
    )
    |> static_supervisor.start
    as "the supervisor did not start"
  let reply = process.new_subject()
  process.send(process.named_subject(reader), ReadEveryRow(reply))
  assert process.receive(reply, 10_000) == Ok([#(50, 4)])
}

/// After a test body that fails and one that hangs past its deadline, no
/// database the helper made and no session on one is left.
pub fn a_failed_and_a_hung_test_leave_no_database_or_session_test() -> Nil {
  use <- owned_test.run(30_000)
  let reports = process.new_subject()
  let failed =
    exit_reason_of(fn() {
      owned_test.run(10_000, fn() {
        use database <- template_database.run
        process.send(reports, database.name)
        create_saved_account(database.connection)
        insert_row(on: database.connection, key: 51, marker: 51)
        panic as "the planted failure"
      })
    })
  assert failed != process.Normal
  let hung =
    exit_reason_of(fn() {
      owned_test.run(300, fn() {
        use database <- template_database.run
        process.send(reports, database.name)
        create_saved_account(database.connection)
        insert_row(on: database.connection, key: 52, marker: 52)
        process.sleep_forever()
      })
    })
  assert hung != process.Normal
  let assert Ok(first) = process.receive(reports, 0)
  let assert Ok(second) = process.receive(reports, 0)
  let names = pog.array(pog.text, [first, second])
  let admin = database_support.shared().admin
  assert becomes_true(fn() {
    count_matching(
      on: admin,
      sql: "select count(*) from pg_database where datname = any($1::text[])",
      names:,
    )
    == 0
  })
    as "a test database was left"
  assert becomes_true(fn() {
    count_matching(
      on: admin,
      sql: "select count(*) from pg_stat_activity where datname = any($1::text[])",
      names:,
    )
    == 0
  })
    as "a session was left on a test database"
}

fn start_reader(
  connection: pog.Connection,
  name: Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(connection)
  |> actor.named(name)
  |> actor.on_message(fn(connection, message) {
    let ReadEveryRow(reply:) = message
    process.send(reply, read_every_row(connection))
    actor.continue(connection)
  })
  |> actor.start
}

fn create_saved_account(connection: pog.Connection) -> Nil {
  let assert Ok(_) = pog.query(create_table) |> pog.execute(on: connection)
    as "the table was not created"
  Nil
}

fn insert_row(
  on connection: pog.Connection,
  key key: Int,
  marker marker: Int,
) -> Nil {
  let assert Ok(_) =
    pog.query("insert into saved_account (key, marker) values ($1, $2)")
    |> pog.parameter(pog.int(key))
    |> pog.parameter(pog.int(marker))
    |> pog.execute(on: connection)
    as "the row was not written"
  Nil
}

fn read_every_row(connection: pog.Connection) -> List(#(Int, Int)) {
  let row = {
    use key <- decode.field(0, decode.int)
    use marker <- decode.field(1, decode.int)
    decode.success(#(key, marker))
  }
  let assert Ok(returned) =
    pog.query("select key, marker from saved_account order by key")
    |> pog.returning(row)
    |> pog.execute(on: connection)
    as "the rows were not read"
  returned.rows
}

/// Writes each key with marker 3 in a transaction the code opens itself,
/// which commits unless `then_fail` is set.
fn save_accounts(
  on connection: pog.Connection,
  keys keys: List(Int),
  then_fail then_fail: Bool,
) -> Result(Nil, pog.TransactionError(String)) {
  pog.transaction(connection, fn(inner) {
    list.each(keys, insert_row(on: inner, key: _, marker: 3))
    case then_fail {
      True -> Error("the transaction failed after its writes")
      False -> Ok(Nil)
    }
  })
}

fn count_matching(
  on connection: pog.Connection,
  sql sql: String,
  names names: pog.Value,
) -> Int {
  let assert Ok(returned) =
    pog.query(sql)
    |> pog.parameter(names)
    |> pog.returning(decode.field(0, decode.int, decode.success))
    |> pog.execute(on: connection)
    as "the count query failed"
  let assert [count] = returned.rows as "a count query returns one row"
  count
}

/// Runs `work` in a separate unlinked process and waits for it to exit, so a
/// panic inside it is seen as a reason and does not fail the caller.
fn exit_reason_of(work: fn() -> a) -> process.ExitReason {
  let worker = process.spawn_unlinked(work)
  let monitor = process.monitor(worker)
  let selected =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 30_000)
  case selected {
    Ok(process.ProcessDown(reason:, ..)) -> reason
    Ok(process.PortDown(..)) -> panic as "a port went down, not the worker"
    Error(Nil) -> panic as "the worker did not exit within 30 seconds"
  }
}

/// True once `condition` holds, checked every 10 ms for up to 5 seconds.
fn becomes_true(condition: fn() -> Bool) -> Bool {
  wait_for(condition, 5000)
}

fn wait_for(condition: fn() -> Bool, remaining: Int) -> Bool {
  case condition(), remaining > 0 {
    True, _ -> True
    False, False -> False
    False, True -> {
      process.sleep(10)
      wait_for(condition, remaining - 10)
    }
  }
}
