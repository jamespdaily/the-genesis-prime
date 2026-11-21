//// A node of its own that runs the server's own start, `genesis_prime.run`, as `gleam
//// run` does: the client's tables from GENESIS_TABLE_DIR, the content load, the
//// server's settings and tree, and the ready line. Only the three listener ports (the
//// system picks them) and the two clocks (a driven clock, so a bot does not wait out
//// a recharge) are changed. When the ready line is said, a bot plays the opening of
//// the tutorial through the listeners, and the node prints what it did for the test
//// that started it (`real_start_test`).
////
//// ```
//// run ─ load tables ─ load content ─ settings ─ tree ─ ready line ─▶ bot process
////                                                                    login ─ create a Medic
////                                                                    enter ─ play_opening
//// prints: step: <wait>, quest_state ..., quest_progress ..., scenario passed
//// ```
////
//// A bot that stops, or a step that cannot go on, ends the node with status 1 (the bot
//// is linked to the node's main), and the last `step:` line names the wait it was in.

import bot_frames
import character_support
import driven_time
import fixed_seed
import game_client
import genesis_prime
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/listener
import genesis_prime/load_player.{Account}
import genesis_prime/message/create_result
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/quest_objective_progress
import genesis_prime/message/quest_state
import genesis_prime/server
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import login_client.{Ports}
import login_support
import open_wait
import tutorial_bot

/// The account the test seeds: its login name, password and SRP seed, and the name of
/// the Medic it creates.
pub const account_login_name = "boot-bot"

/// The login name's password.
pub const account_password = "boot-password"

/// The SRP seed of the account.
pub const account_seed = 1

/// The Medic's name.
pub const character_name = "Zed Qu"

/// The recharge of Paralytic Surge on the client's own row: Spell4 42352's
/// `spellCoolDown`, 25 000 ms.
const paralytic_surge_recharge_ms = 25_000

/// What the node runs.
pub fn main() -> Nil {
  let time = driven_time.new()
  let held = process.new_subject()
  genesis_prime.run(
    change: fn(settings) {
      let settings =
        login_support.on_the_clock(settings: fixed_seed.seeded(settings), time:)
      let settings = on_ports_the_system_picks(settings)
      process.send(held, settings)
      settings
    },
    say: fn(line) {
      io.println(line)
      let assert Ok(settings) = process.receive(held, 0)
        as "the settings the server runs on were held before the ready line"
      let _bot = process.spawn(fn() { play(settings:, time:) })
      Nil
    },
  )
}

/// The settings with the STS, auth and game listeners asking the system for a port.
fn on_ports_the_system_picks(settings: server.Settings) -> server.Settings {
  server.Settings(
    ..settings,
    login: server.Login(
      sts: server.Served(..settings.login.sts, port: 0),
      auth: server.Served(..settings.login.auth, port: 0),
    ),
    game: server.Served(..settings.game, port: 0),
  )
}

/// The bot: logs in over the listeners, creates a Medic, enters World 3460 and plays the
/// opening of the tutorial, then prints what the server told it and holds its connection
/// until the node ends. A step it cannot go on from ends the node.
fn play(
  settings settings: server.Settings,
  time time: driven_time.Time,
) -> Nil {
  open_wait.reporting(
    slot: open_wait.Wait,
    opened: fn(what) { io.println("step: " <> what) },
    closed: fn() { Nil },
  )
  let ports = ports_of(settings)
  let #(game, _auth) =
    load_player.log_in(
      account: Account(
        login_name: account_login_name,
        password: account_password,
        seed: account_seed,
        character_name:,
      ),
      ports:,
    )
  load_player.list_characters(game)
  game_client.send_create(
    game:,
    body: character_support.medic_create_request(character_name),
  )
  let created =
    character_support.create_result_in(game_client.read(game:, count: 1))
  assert created.result == create_result.CreateOk
    as "the server created the Medic"
  let assert Ok(play_body) =
    play_character.encode(PlayCharacter(character_id: created.character_id))
    as "0x07DD encodes"
  game_client.send(game:, message_id: 0x07DD, body: play_body)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      has_message(frames, 0x01BC) && has_message(frames, 0x035C)
    })
  let played =
    tutorial_bot.play_opening(
      game:,
      have:,
      entry:,
      env: tutorial_bot.Env(
        advance: fn(ms) { driven_time.advance(time:, ms:) },
        recharge_ms: paralytic_surge_recharge_ms,
        settled: fn(unit_id) {
          character_support.marker_creature_settled(settings:, unit_id:)
        },
      ),
    )
  case played {
    Ok(played) -> {
      print_what_the_server_told(played.frames)
      io.println("scenario passed")
      process.sleep_forever()
    }
    Error(tutorial_bot.Stuck(step:, reason:)) ->
      panic as { "the bot stopped in " <> step <> ": " <> reason }
  }
}

fn ports_of(settings: server.Settings) -> login_client.Ports {
  let assert Ok(sts_port) = listener.port(settings.login.sts.listener)
    as "the STS listener has a port"
  let assert Ok(auth_port) = listener.port(settings.login.auth.listener)
    as "the auth listener has a port"
  let assert Ok(game_port) = listener.port(settings.game.listener)
    as "the game listener has a port"
  Ports(sts_port:, auth_port:, game_port:)
}

fn has_message(frames: List(Frame), message_id: Int) -> Bool {
  list.any(frames, fn(frame) { frame.message_id == message_id })
}

/// Prints one line for each quest state (0x035C) and objective progress (0x035D) the
/// server wrote, and how many casts it confirmed (0x07FD) and units it marked dead
/// (0x088C).
fn print_what_the_server_told(frames: List(Frame)) -> Nil {
  list.each(
    bot_frames.decoded(frames, quest_state.message_id, quest_state.decode),
    fn(told) {
      io.println(
        "quest_state "
        <> int.to_string(told.quest_id)
        <> " "
        <> int.to_string(told.state),
      )
    },
  )
  list.each(
    bot_frames.decoded(
      frames,
      quest_objective_progress.message_id,
      quest_objective_progress.decode,
    ),
    fn(told) {
      io.println(
        "quest_progress "
        <> int.to_string(told.quest_id)
        <> " "
        <> int.to_string(told.objective_index)
        <> " "
        <> int.to_string(told.progress),
      )
    },
  )
  io.println(
    "confirmed_casts "
    <> int.to_string(
      list.count(frames, fn(frame) { frame.message_id == 0x07FD }),
    ),
  )
  io.println(
    "dead_units "
    <> int.to_string(
      list.count(frames, fn(frame) { frame.message_id == 0x088C }),
    ),
  )
}
