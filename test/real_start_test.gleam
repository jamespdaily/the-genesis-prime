//// The server's own start, `genesis_prime.run`, on the client's real tables and a
//// fresh migrated database, in a node of its own (`real_start_node`), with a bot that
//// plays the opening of the tutorial inside it. A test that starts the server through
//// test support cannot see a term the real start reads and the real load does not
//// write; this one starts it as the play service does.
//// - The ready line names the number of tables the server loads
////   (`server_table.entries`), and is said only when the server serves.
//// - The opening's expected values are the client's own: Quest2 10513's three
////   places, 10527's hoverboard, finish line and projector, and 10518's first
////   beast, which `game_wire_test`'s tutorial test gives in its chain ("Quest2's
////   chain from 10513"): 10513 and 10527 end in state 3 and 10518 begins in state 1
////   (opcode.0x35c.add_unaccepted); a press is confirmed (opcode.0x7fd) and the kill
////   marks the unit dead (opcode.0x88c); the kill makes 10518's first objective count
////   (opcode.0x35d).
//// - A table folder with no table ends the node with status 1 before its ready line
////   (`genesis_prime.load_tables`), the client's file named; this one needs no
////   client.
//// - A bot that cannot go on ends the node with status 1, and the report the test
////   fails with names the last wait the bot was in.
//// A node needs the client's tables, so the tests that play it skip where
//// `GENESIS_NO_CLIENT=1` (a fork's CI).
//// The boot test, which takes most of a minute, is tagged `real_start`: `./check`
//// runs it in a part of its own beside the other tests.

import client_tables
import content_support
import database_support
import genesis_prime/import_world_data
import genesis_prime/load_player.{Account}
import genesis_prime/table/loader/server_table
import genesis_prime/world_map/spawn.{type Row}
import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import owned_test
import real_start_node
import recording_support
import serving_node.{type Node}
import terrain_support
import unitest

/// The spawns the tutorial's opening needs and a migrated database does not hold: the
/// hoverboard and the projector of World 3460, with the beasts around them.
const spawn_fixture = "test/fixture/world_data_tutorial_path"

/// The start of the ready line after the number of tables: said only when the
/// server serves.
const ready_line_after_the_tables =
  " game tables and serves the STS login on port"

/// The ready line of a server that loaded all the tables the server reads.
fn ready_line() -> String {
  "the server loaded "
  <> int.to_string(list.length(server_table.entries()))
  <> ready_line_after_the_tables
}

/// Starts a node that runs the server on the tables in `tables`, on a migrated
/// database of its own that holds the bot's account and, when `spawns` is true, the
/// spawns of the tutorial's opening, and hands the node to `body`.
fn with_node(
  tables tables: String,
  spawns spawns: Bool,
  body body: fn(Node) -> a,
) -> a {
  let database = database_support.new_database(on: database_support.shared())
  let pool = content_support.connect(database:)
  load_player.seed(pool:, accounts: [
    Account(
      login_name: real_start_node.account_login_name,
      password: real_start_node.account_password,
      seed: real_start_node.account_seed,
      character_name: real_start_node.character_name,
    ),
  ])
  case spawns {
    True -> {
      let assert Ok(_) =
        import_world_data.import_spawns(db: pool, folder: spawn_fixture)
        as "the spawn fixture imports"
      Nil
    }
    False -> Nil
  }
  use terrain <- with_terrain(
    tables:,
    rows: content_support.stored_spawns(database:),
  )
  let settings = database_support.settings()
  let password = case settings.password {
    option.Some(password) -> [#("PGPASSWORD", password)]
    option.None -> []
  }
  body(serving_node.start_node(
    "real_start_node",
    list.append(password, [
      #("PGHOST", settings.tcp_host),
      #("PGPORT", int.to_string(settings.port)),
      #("PGUSER", settings.user),
      #("PGDATABASE", database),
      #("GENESIS_TABLE_DIR", tables),
      #("GENESIS_TERRAIN_DIR", terrain),
      #("GENESIS_GAME_ADDRESS", "127.0.0.1"),
      #("GENESIS_REALM_NAME", "Boot"),
    ]),
  ))
}

/// The terrain folder the node reads: flat ground for every square a spawn of the database
/// stands in, over the client's World table, when the node runs on the client's tables;
/// an empty folder for a node that stops before it reads one.
fn with_terrain(
  tables tables: String,
  rows rows: List(Row),
  body body: fn(String) -> a,
) -> a {
  case tables == client_tables.folder() {
    True ->
      terrain_support.flat_folder_for(
        rows:,
        tables: client_tables.with_content_tables(),
        body:,
      )
    False -> terrain_support.planted_folder(files: [], body:)
  }
}

/// What a failed test says of a node that ended before it printed `wanted`: its exit
/// status, the last quest step its bot started (a step named by its quest number, as
/// `tutorial_bot` names them), the last three waits it named (the innermost is a frame
/// read, the ones before it say what the read was for), and its last lines. The node
/// has ended, so the exit status is read at once.
fn unreached_report(node node: Node, wanted wanted: String) -> String {
  let status = serving_node.await_exit(node)
  let lines = string.split(serving_node.output(node), "\n")
  let waits =
    list.filter(lines, fn(line) { string.starts_with(line, "step: ") })
  let quest_steps = list.filter(waits, is_a_quest_step)
  "the node ended with status "
  <> int.to_string(status)
  <> " before it printed \""
  <> wanted
  <> "\"; the last quest step the bot started:\n"
  <> string.join(list.drop(quest_steps, list.length(quest_steps) - 1), "\n")
  <> "\nthe last waits the bot named:\n"
  <> string.join(list.drop(waits, list.length(waits) - 3), "\n")
  <> "\nits last lines:\n"
  <> string.join(list.drop(lines, list.length(lines) - 25), "\n")
}

/// Whether a `step: ` line of the bot names a quest (`step: 10527: hoverboard ...`),
/// not a frame read or the entry.
fn is_a_quest_step(line: String) -> Bool {
  case
    string.split_once(string.drop_start(line, string.length("step: ")), ": ")
  {
    Ok(#(first, _)) -> result.is_ok(int.parse(first))
    Error(Nil) -> False
  }
}

/// Waits for the node to print `text`, and fails the test with the node's report when it
/// ends first.
fn expect_output(node node: Node, text text: String) -> Nil {
  use <- bool.guard(when: serving_node.await_output(node, text), return: Nil)
  panic as unreached_report(node:, wanted: text)
}

/// The numbers after `prefix` on each line of the output that starts with it.
fn numbers_after(output output: String, prefix prefix: String) -> List(String) {
  string.split(output, "\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(line, prefix) {
      True -> Ok(string.trim(string.drop_start(line, string.length(prefix))))
      False -> Error(Nil)
    }
  })
}

/// Whether a printed count is a number above 0.
fn is_above_zero(count: String) -> Bool {
  case int.parse(count) {
    Ok(count) -> count > 0
    Error(Nil) -> False
  }
}

pub fn the_real_server_boots_and_a_bot_plays_the_opening_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_start")
  use <- unitest.guard(client_tables.present())
  use node <- with_node(tables: client_tables.folder(), spawns: True)
  expect_output(node:, text: ready_line())
  expect_output(node:, text: "scenario passed")
  let printed = serving_node.output(node)
  let states = numbers_after(output: printed, prefix: "quest_state ")
  assert list.contains(states, "10513 3")
    as "opcode.0x35c: Quest2 10513 is told Completed"
  assert list.contains(states, "10527 3")
    as "opcode.0x35c: Quest2 10527 is told Completed"
  assert list.contains(states, "10518 1")
    as "opcode.0x35c: Quest2 10518 is told accepted, as the hoverboard's 10527 ends"
  let progress =
    numbers_after(output: printed, prefix: "quest_progress 10518 0 ")
  assert list.any(progress, fn(count) {
    case int.parse(count) {
      Ok(count) -> count >= 1
      Error(Nil) -> False
    }
  })
    as "opcode.0x35d: the first beast's kill counts for 10518's objective 0"
  let confirmed_casts =
    numbers_after(output: printed, prefix: "confirmed_casts ")
  assert confirmed_casts != [] && list.all(confirmed_casts, is_above_zero)
    as "opcode.0x7fd: a press is confirmed"
  let dead_units = numbers_after(output: printed, prefix: "dead_units ")
  assert dead_units != [] && list.all(dead_units, is_above_zero)
    as "opcode.0x88c: the kill marks a unit dead"
  serving_node.terminate(node)
  assert serving_node.await_exit(node) == 0
    as "SIGTERM ends the node with status 0, the bot still connected"
}

pub fn a_folder_with_no_tables_ends_the_node_before_its_ready_line_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("registry")
  use empty <- recording_support.in_folder
  use node <- with_node(tables: empty, spawns: False)
  assert !serving_node.await_output(node, ready_line())
    as "the node ended without the ready line"
  let report = unreached_report(node:, wanted: ready_line())
  assert string.contains(report, "the node ended with status 1")
    as "the report names the exit status"
  assert string.contains(report, "CCStateAdditionalData.tbl could not be read")
    as "the report holds the node's last lines, naming the first table file"
}

pub fn a_bot_that_cannot_go_on_names_its_last_step_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  use node <- with_node(tables: client_tables.folder(), spawns: False)
  expect_output(node:, text: ready_line())
  assert !serving_node.await_output(node, "scenario passed")
    as "the bot cannot finish the opening on a database with no spawns"
  let report = unreached_report(node:, wanted: "scenario passed")
  assert string.contains(report, "the node ended with status 1")
    as "the report names the exit status"
  assert string.contains(
    report,
    "the last quest step the bot started:\nstep: 10527: hoverboard, finish line, projector\n",
  )
    as report
  assert string.contains(report, "step: 0x262 of a unit of Creature2 73419")
    as report
}
