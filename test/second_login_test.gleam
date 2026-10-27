//// A second login of an account replaces the first, over TCP against the real
//// game listener, the sessions' registry and the maps. The client handles
//// 0x36A in every state (records lua.CharacterSelection.OnRemoveCountdown,
//// opcode.0x36a, opcode.0x117, opcode.0x162). The server ends the old
//// connection and takes its unit off the map before it lists for the new one,
//// so the client's own list of a character pending removal is not needed. The
//// reason 19 of 0x36A is a guess: no reason says the account logged in
//// elsewhere, and no recording shows a double login. The accounts and
//// characters are in a database of the test's own and the client's own tables
//// are loaded from its files, so the tests skip where `GENESIS_NO_CLIENT=1`.
//// Every wait is for bytes the server writes or the socket closing; the
//// deadlines are for a server that does not answer.

import environment
import game_client.{type Game}
import game_server
import genesis_prime/character/character.{
  type Character, Appearance, NewCharacter,
}
import genesis_prime/character/select.{Inserted}
import genesis_prime/character/store
import genesis_prime/game/service as game_service
import genesis_prime/game/sessions
import genesis_prime/login/account.{type Account}
import genesis_prime/login/account_store
import genesis_prime/login/handoff
import genesis_prime/message/character_list
import genesis_prime/message/disconnect_notice
import genesis_prime/message/play_character.{PlayCharacter}
import gleam/dict
import gleam/erlang/process.{type Pid}
import gleam/list
import gleam/string
import log_capture
import map_support
import owned_test
import supervisor_children
import tcp_client
import template_database
import unitest

/// How long a test waits for what the server must do, in milliseconds.
const wait_ms = 5000

fn saved_character(
  database database: template_database.Database,
  running running: game_server.Running,
  account account: Account,
  name name: String,
) -> Character {
  let row = running.facts.creation
  let assert Inserted(character) =
    store.run(
      database.connection,
      select.InsertCharacter(NewCharacter(
        account_id: account.id,
        name:,
        creation_id: row.id,
        gender: row.sex,
        race_id: row.race_id,
        class_id: row.class_id,
        faction_id: row.faction_id,
        experience: row.xp,
        level: game_server.level_of(running.facts, row.xp),
        path: 1,
        place: game_server.start_place(world_id: running.facts.world_id),
        appearance: Appearance(
          customisation_labels: [1],
          customisation_values: [3],
          bone_values: list.repeat(0x3F800000, running.facts.bone_count),
        ),
      )),
    )
    as "the character was saved"
  character
}

fn signed_in(
  running running: game_server.Running,
  account account: Account,
) -> Game {
  game_client.connect(
    port: running.game_port,
    session_key: handoff.issue(running.session_keys, account.identity(account)),
    account_name: account.name,
  )
}

fn account_of(
  database database: template_database.Database,
  name name: String,
) -> Account {
  let assert Ok(account) =
    account_store.create(database.connection, name, "secret")
    as "the account is created"
  account
}

/// Asks for the list and reads it.
fn listed(game game: Game) -> character_list.CharacterList {
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [list_frame] = game_client.read(game:, count: 1)
    as "the character list"
  assert list_frame.message_id == 0x0117
    as "opcode.0x117: the first answer is the list, never a message of the old session"
  let assert Ok(decoded) = character_list.decode(list_frame.body)
    as "0x117 decodes"
  decoded
}

fn play(game game: Game, character character: Character) -> Nil {
  let assert Ok(body) =
    play_character.encode(PlayCharacter(character_id: character.id))
    as "0x7DD encodes"
  game_client.send(game:, message_id: 0x07DD, body:)
}

pub fn a_second_login_ends_the_first_connection_with_0x36a_reason_19_and_then_lists_and_plays_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let account = account_of(database:, name: "jim")
  let character =
    saved_character(database:, running:, account:, name: "Zed Mara")
  let first = signed_in(running:, account:)
  assert listed(game: first).characters != []
    as "the first connection lists the account's character"
  play(game: first, character:)
  let assert [_, _, _, _, _] = game_client.read(game: first, count: 5)
    as "opcode.0x636: the first connection entered the world: 0xAD, 0x262, 0x19B, 0x636 and 0xF1, in the order CheckWorldLoaded 0x1403E8000 needs"

  let second = signed_in(running:, account:)
  let assert [notice] = game_client.read(game: first, count: 1)
    as "the first connection is told it is disconnected"
  assert notice.message_id == 0x036A
    as "opcode.0x36a: a game server tells the client it is being disconnected"
  let assert Ok(decoded) = disconnect_notice.decode(notice.body)
    as "0x36A decodes"
  assert decoded.reason == 19
    as "opcode.0x36a: 19 is 'This account has been disconnected'; that retail used it is a guess"
  assert game_client.closed(first)
    as "the first connection ends after the notice"

  let list_message = listed(game: second)
  assert list.map(list_message.characters, fn(entry) { entry.character_id })
    == [character.id]
    as "opcode.0x117: the second login is answered with the account's list"
  assert list_message.pending_removal_character_id == 0
    as "the character is off the map when the list is sent, so the new client never sees it still in the world"
  play(game: second, character:)
  let assert [entered, ..] = game_client.read(game: second, count: 5)
    as "the second connection plays the character the first held"
  assert entered.message_id == 0x00AD
    as "opcode.0xad: the world is loaded, not refused with 0x162 as for a character that is on the map"
}

pub fn the_slot_is_freed_when_a_connection_dies_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let account = account_of(database:, name: "jim")
  let first = signed_in(running:, account:)
  assert listed(game: first).characters == []
    as "the first connection lists the account's characters"
  game_client.close(first)
  let second = signed_in(running:, account:)
  assert listed(game: second).characters == []
    as "opcode.0x117: the slot of a connection that died is free, so the second login is answered with the list"
}

pub fn connections_of_different_accounts_do_not_affect_each_other_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let jim = account_of(database:, name: "jim")
  let ann = account_of(database:, name: "ann")
  let first = signed_in(running:, account: jim)
  let second = signed_in(running:, account: ann)
  assert listed(game: first).characters == []
    as "the first account is answered with its list, with no notice of a login of another account before it"
  assert listed(game: second).characters == []
    as "the second account is answered with its list"
}

/// The process of the only map the server runs: the last child of the map's
/// supervisor, which the factory runs.
fn the_map_process(running: game_server.Running) -> Pid {
  let assert Ok(factory) = process.named(running.game.maps.factory)
    as "the factory supervisor is registered under its name"
  let assert [map_subtree] = supervisor_children.in_start_order(factory)
    as "the world has one map subtree"
  let assert Ok(map) =
    list.last(supervisor_children.in_start_order(map_subtree))
    as "a map's supervisor runs the map process after its senders"
  map
}

/// The server's settings with the three deadlines of a second login, in
/// milliseconds.
fn with_deadlines(
  leave leave: Int,
  eviction eviction: Int,
  claim claim: Int,
) -> fn(game_service.Settings) -> game_service.Settings {
  fn(settings) {
    game_service.Settings(
      ..settings,
      leave_deadline_ms: leave,
      eviction_deadline_ms: eviction,
      claim_deadline_ms: claim,
    )
  }
}

/// The first connection of the account is in the world, and the map that holds
/// its unit does not run, so it cannot answer the leave of the first connection.
/// Returns the first connection, the map's process and the character.
fn in_the_world_with_a_map_that_does_not_run(
  running running: game_server.Running,
  account account: Account,
  character character: Character,
) -> #(Game, Pid) {
  let first = signed_in(running:, account:)
  assert listed(game: first).characters != []
    as "the first connection lists the account's character"
  play(game: first, character:)
  let assert [_, _, _, _, _] = game_client.read(game: first, count: 5)
    as "opcode.0x636: the first connection entered the world: 0xAD, 0x262, 0x19B, 0x636 and 0xF1, in the order CheckWorldLoaded 0x1403E8000 needs"
  let map = the_map_process(running)
  map_support.suspend(map)
  #(first, map)
}

pub fn a_map_that_does_not_answer_the_leave_does_not_stop_the_second_login_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running =
    game_server.start_with(
      database:,
      answer_deadline_ms: 5000,
      change: with_deadlines(leave: 300, eviction: 900, claim: 3000),
    )
  let account = account_of(database:, name: "jim")
  let character =
    saved_character(database:, running:, account:, name: "Zed Mara")
  let #(first, map) =
    in_the_world_with_a_map_that_does_not_run(running:, account:, character:)

  let second = signed_in(running:, account:)
  let assert [notice] = game_client.read(game: first, count: 1)
    as "the first connection is told it is disconnected although the map did not answer its leave"
  assert notice.message_id == 0x036A
    as "opcode.0x36a: a connection that could not leave the map in its deadline still tells the player and ends"
  assert game_client.closed(first)
    as "the first connection ends within the leave deadline, not at the shared answer deadline of 5 seconds"
  assert list.map(listed(game: second).characters, fn(entry) {
      entry.character_id
    })
    == [character.id]
    as "the new login is answered with the list: a slow map does not end both connections"
  map_support.resume(map)
  play(game: second, character:)
  let assert [entered, ..] = game_client.read(game: second, count: 5)
    as "the new connection plays the character once the map answers: the map took the old unit off when it handled the old connection's end"
  assert entered.message_id == 0x00AD
    as "opcode.0xad: the world is loaded, not refused with 0x162 for a character that is on the map"
}

pub fn a_connection_that_is_still_leaving_at_the_eviction_deadline_is_killed_and_the_second_login_goes_on_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  // The leave deadline is longer than the eviction deadline here, the other way
  // round from the server's own, so the first connection is still waiting for
  // the map when the registry kills it.
  let running =
    game_server.start_with(
      database:,
      answer_deadline_ms: 5000,
      change: with_deadlines(leave: 4000, eviction: 300, claim: 3000),
    )
  let account = account_of(database:, name: "jim")
  let character =
    saved_character(database:, running:, account:, name: "Zed Mara")
  let #(first, map) =
    in_the_world_with_a_map_that_does_not_run(running:, account:, character:)

  let second = signed_in(running:, account:)
  assert game_client.closed(first)
    as "the registry killed the first connection at the eviction deadline, so its socket closed"
  assert list.map(listed(game: second).characters, fn(entry) {
      entry.character_id
    })
    == [character.id]
    as "the new login is answered with the list once the old connection is dead"
  map_support.resume(map)
  play(game: second, character:)
  let assert [entered, ..] = game_client.read(game: second, count: 5)
    as "the map took the killed connection's unit off when it saw the connection go down"
  assert entered.message_id == 0x00AD
    as "opcode.0xad: the world is loaded for the new connection"
}

/// The pid the name is registered to once it is not `old`. The restarted
/// registry registers its name as it starts, and nothing announces that, so the
/// name is looked up until it names a new process, for at most `wait_ms`.
fn wait_for_a_new_registry(
  name: process.Name(sessions.Message),
  old: Pid,
) -> Result(Pid, Nil) {
  let expired = process.new_subject()
  let _timer = process.send_after(expired, wait_ms, Nil)
  look_for_a_new_registry(name:, old:, expired:)
}

fn look_for_a_new_registry(
  name name: process.Name(sessions.Message),
  old old: Pid,
  expired expired: process.Subject(Nil),
) -> Result(Pid, Nil) {
  case process.named(name), process.receive(expired, 0) {
    Ok(pid), _ if pid != old -> Ok(pid)
    _, Error(Nil) -> look_for_a_new_registry(name:, old:, expired:)
    _, Ok(Nil) -> Error(Nil)
  }
}

pub fn a_registry_that_starts_again_ends_the_connections_that_held_slots_and_logs_a_warning_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let capture = log_capture.start()
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let account = account_of(database:, name: "jim")
  let first = signed_in(running:, account:)
  assert listed(game: first).characters == []
    as "the first connection holds the account's slot"
  let peer = tcp_client.own_address(first.socket)
  let assert Ok(old) = process.named(running.game.sessions)
    as "the sessions' registry is registered"
  process.kill(old)
  assert game_client.closed(first)
    as "a registry that starts again forgets its holders, so the connections it held end: the second login of the account could not find them"
  let assert Ok(line) =
    log_capture.next_matching(capture:, within: wait_ms, matching: fn(event) {
      dict.get(event.metadata, "peer") == Ok(log_capture.Text(peer))
      && string.contains(event.text, "sessions")
    })
    as "the end is logged by the connection"
  assert line.level == "warning"
    as "designing-processes: an outside failure the server recovered from is a warning; a map that ended is logged the same way"
  let assert Ok(_) = wait_for_a_new_registry(running.game.sessions, old)
    as "the game subtree started the registry again"
  let second = signed_in(running:, account:)
  assert listed(game: second).characters == []
    as "the new registry takes the next login of the account"
}
