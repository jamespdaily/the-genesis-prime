//// Entering the world over TCP against the real game listener and the real
//// maps: a scripted client logs in to the game server, chooses a character and
//// is sent the world messages, the map holds the character's unit and tells the
//// client of the players that join and leave it, a character that is on the map
//// is refused, and a map that does not answer closes the connection. The
//// accounts and characters are in a database of the test's own, and the
//// client's own tables are loaded from its files, so the tests skip where
//// `GENESIS_NO_CLIENT=1`.
////
//// Expected values are the client's records: 0x7DD, 0xAD, 0x262, 0x19B, 0xF1,
//// 0xF2 inside 0x38C, 0x61, 0x162 and 0x355 (opcode.0x7dd, opcode.0xad,
//// opcode.0x262, opcode.0x19b, opcode.0xf1, opcode.0xf2, opcode.0x38c,
//// opcode.0x61, opcode.0x162, opcode.0x355), the order CheckWorldLoaded
//// 0x1403E8000 needs, and the movement interval the client defaults to (the
//// bytes at 0x140C3A004: 125 milliseconds). Every wait is for bytes the server
//// writes, a delivery or a line it logs; the deadlines are for a server that
//// does not answer, never a pause.

import environment
import game_client.{type Game}
import game_server
import genesis_prime/character/character.{
  type Character, Appearance, NewCharacter,
}
import genesis_prime/character/select.{Inserted}
import genesis_prime/character/store
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/login/account.{type Account}
import genesis_prime/login/account_store
import genesis_prime/login/handoff
import genesis_prime/map/delivery.{type Delivery, Appeared}
import genesis_prime/map/maps
import genesis_prime/map/position.{Position}
import genesis_prime/map/unit.{type PlayerUnit, Newcomer}
import genesis_prime/message/character_list
import genesis_prime/message/enter_world
import genesis_prime/message/float32
import genesis_prime/message/movement_send_interval
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_is_player
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import log_capture
import owned_test
import template_database
import unitest

/// How long a test waits for what the server must do, in milliseconds.
const wait_ms = 5000

@external(erlang, "erlang", "suspend_process")
fn suspend_process(pid: Pid) -> Bool

/// A character of the account made from the client's own row, in the world
/// the settings start characters in.
fn saved_character(
  database database: template_database.Database,
  running running: game_server.Running,
  account account: Account,
) -> Character {
  let row = running.facts.creation
  let assert Inserted(character) =
    store.run(
      database.connection,
      select.InsertCharacter(NewCharacter(
        account_id: account.id,
        name: "Zed Mara",
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
          customisation_labels: [1, 2],
          customisation_values: [3, 4],
          bone_values: [0x3F800000],
        ),
      )),
    )
    as "the character was saved"
  character
}

/// A connection the account is signed in on, with a session key the auth login
/// would have issued.
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

/// Asks the server to list the characters and to play one, and reads what it
/// answers the play with: the world messages, or the refusal.
fn play(
  game game: Game,
  character character: Character,
  answers answers: Int,
) -> List(Frame) {
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [listed] = game_client.read(game:, count: 1)
    as "the character list"
  assert listed.message_id == 0x0117
  let assert Ok(list_message) = character_list.decode(listed.body)
    as "0x117 decodes"
  assert list.map(list_message.characters, fn(entry) { entry.character_id })
    == [character.id]
    as "opcode.0x117: the list holds the account's character"
  let assert Ok(body) =
    play_character.encode(PlayCharacter(character_id: character.id))
    as "0x7DD encodes"
  game_client.send(game:, message_id: 0x07DD, body:)
  game_client.read(game:, count: answers)
}

/// A player that joins a map from a process of its own, which the map
/// monitors, and what it was told.
type Observer {
  Observer(stop: Subject(Nil), seen: Subject(Delivery))
}

/// Joins the map of the world as a character at the start place from a new
/// process, which keeps the deliveries it is sent until it is stopped.
fn join_as_observer(
  running running: game_server.Running,
  character_id character_id: Int,
) -> #(Observer, PlayerUnit) {
  let started = process.new_subject()
  let seen = process.new_subject()
  process.spawn(fn() {
    let deliveries = process.new_subject()
    let stop = process.new_subject()
    let entered =
      maps.enter(
        registry: running.game.maps.registry,
        world_id: running.facts.world_id,
        newcomer: Newcomer(
          character_id:,
          name: "Obs Erver",
          race_id: 1,
          class_id: 3,
          gender: 1,
          path: 2,
          position: Position(x: 1.5, y: 2.5, z: 3.5),
        ),
        connection: deliveries,
        within_ms: wait_ms,
      )
    process.send(started, #(entered, stop))
    keep(
      selector: process.new_selector()
        |> process.select_map(deliveries, fn(received) { Some(received) })
        |> process.select_map(stop, fn(_) { None }),
      seen:,
    )
  })
  let assert Ok(#(Ok(joined), stop)) = process.receive(started, wait_ms)
    as "the observer entered the map"
  #(Observer(stop:, seen:), joined)
}

fn keep(
  selector selector: process.Selector(Option(Delivery)),
  seen seen: Subject(Delivery),
) -> Nil {
  case process.selector_receive_forever(selector) {
    Some(received) -> {
      process.send(seen, received)
      keep(selector:, seen:)
    }
    None -> Nil
  }
}

pub fn a_player_who_plays_a_character_is_sent_the_world_messages_and_the_map_holds_its_unit_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let character = saved_character(database:, running:, account:)
  let game = signed_in(running:, account:)
  let assert [entered, created, is_player, interval] =
    play(game:, character:, answers: 4)
    as "0xAD, 0x262, 0x19B and 0xF1"
  assert list.map([entered, created, is_player, interval], fn(sent) {
      sent.message_id
    })
    == [0x00AD, 0x0262, 0x019B, 0x00F1]
    as "CheckWorldLoaded 0x1403E8000: the world, the player's unit, the unit that is the player, then the movement interval"
  let assert Ok(world) = enter_world.decode(entered.body) as "0xAD decodes"
  assert world.world_id == running.facts.world_id
    && world.position_x == float32.to_bits(1.5)
    && world.position_y == float32.to_bits(2.5)
    && world.position_z == float32.to_bits(3.5)
    as "opcode.0xad: the world and the position the client loads it at are the character's place"
  let assert Ok(unit_message) = unit_create_player.decode(created.body)
    as "0x262 decodes"
  assert unit_message.unit_id == 1
    && unit_message.character_id == character.id
    && unit_message.name == "Zed Mara"
    && unit_message.realm_id == game_server.realm_id
    as "opcode.0x262: the map gave the character's unit its first id; the unit is the character's, on the connection's realm"
  let assert Ok(player) = unit_is_player.decode(is_player.body)
    as "0x19B decodes"
  assert player.unit_id == 1
    as "opcode.0x19b: the unit that is the player is the one just created"
  let assert Ok(movement) = movement_send_interval.decode(interval.body)
    as "0xF1 decodes"
  assert movement.interval_milliseconds == 125
    as "the bytes at 0x140C3A004: the client's own default"

  // 0xF2 inside 0x38C: the terrain is loaded, and 0x61 is the answer.
  let assert Ok(loaded) = terrain_loaded.encode(TerrainLoaded(field_1: 9))
    as "0xF2 encodes"
  game_client.send_world(game:, message_id: 0x00F2, body: loaded)
  let assert [player_entered] = game_client.read(game:, count: 1) as "0x61"
  assert player_entered.message_id == 0x0061
    as "opcode.0xf2: the client's 0xF2 is answered with the 0x61 the end of loading waits for"

  // The map holds the unit: a player that joins is told of it, and the client
  // is told of the player, then of its leaving.
  let #(observer, joined) = join_as_observer(running:, character_id: 77)
  assert joined.id == 2
    as "the map gave the first unit the id 1, so the observer's is the second"
  let assert Ok(Appeared(seen)) = process.receive(observer.seen, wait_ms)
    as "the observer was told of the player"
  assert seen.id == 1 && seen.character_id == character.id
    as "the map holds the character's unit"
  let assert [appeared] = game_client.read(game:, count: 1)
    as "0x262 for the observer"
  assert appeared.message_id == 0x0262
  let assert Ok(appeared_message) = unit_create_player.decode(appeared.body)
    as "0x262 decodes"
  assert appeared_message.unit_id == 2 && appeared_message.character_id == 77
    as "opcode.0x262: a player in range is created on the client"
  process.send(observer.stop, Nil)
  let assert [removed] = game_client.read(game:, count: 1) as "0x355"
  assert removed.message_id == 0x0355
  let assert Ok(removed_message) = unit_destroyed.decode(removed.body)
    as "0x355 decodes"
  assert removed_message.unit_id == 2
    as "opcode.0x355: a player that left is removed from the client"
}

pub fn a_character_that_is_on_the_map_is_refused_the_second_time_and_the_player_may_choose_again_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let character = saved_character(database:, running:, account:)
  let first = signed_in(running:, account:)
  let assert [_, _, _, _] = play(game: first, character:, answers: 4)
    as "the first connection entered the world"
  let second = signed_in(running:, account:)
  let assert [refused] = play(game: second, character:, answers: 1)
    as "the second connection's answer"
  assert refused.message_id == 0x0162
    as "opcode.0x162: a world that refuses a character answers 0x162, on which the client returns to idle character select"
  let assert Ok(refusal) = play_character_refused.decode(refused.body)
    as "0x162 decodes"
  assert refusal.field_1 == 2
    as "PreGameLib.CodeEnumCharacterSelectResults: 2 is Failed"
  let assert Ok(body) =
    play_character.encode(PlayCharacter(character_id: character.id))
    as "0x7DD encodes"
  game_client.send(game: second, message_id: 0x07DD, body:)
  let assert [refused_again] = game_client.read(game: second, count: 1)
    as "the player chose again and was answered again"
  assert refused_again.message_id == 0x0162
    as "character select is idle again after a refusal, so the second request is taken, not a breach"
}

pub fn a_map_that_does_not_answer_closes_the_connection_and_logs_an_error_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let capture = log_capture.start()
  let running = game_server.start(database:, answer_deadline_ms: 1000)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let character = saved_character(database:, running:, account:)
  let assert Ok(registry) = process.named(running.game.maps.registry)
    as "the maps' registry is registered"
  assert suspend_process(registry) as "the registry was suspended"
  let game = signed_in(running:, account:)
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_listed] = game_client.read(game:, count: 1) as "the list"
  let assert Ok(body) =
    play_character.encode(PlayCharacter(character_id: character.id))
    as "0x7DD encodes"
  game_client.send(game:, message_id: 0x07DD, body:)
  assert game_client.closed(game)
    as "designing-processes: a map that does not answer by the deadline may hold the unit, so the connection ends and the map takes the unit off with it"
  let assert Ok(_) =
    log_capture.next_matching(capture:, within: wait_ms, matching: fn(event) {
      event.level == "error" && string.contains(event.text, "map")
    })
    as "the reason is logged as an error: an outside failure is never the player's mistake"
  Nil
}
