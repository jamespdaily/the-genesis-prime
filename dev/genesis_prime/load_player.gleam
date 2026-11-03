//// One load client: a player's whole path on the real protocol, over TCP
//// against the server's listeners, as the client goes it: the STS login, the
//// auth login that hands the player to the game server, the game hello, the
//// character list, the creation of a character, the entry into the world, and
//// then a ping every 500 ms until the step ends. Each player has an account of
//// its own, seeded in the run's database (`seed`), and creates a character of
//// its own, so every step of a run does the whole path for every player.
////
//// A player reports each stage as it finishes it, so a player that fails is
//// known by the last stage it reported. It has no failure of its own: the
//// scripted clients it is made of (`login_client`, `game_client`) stop the
//// process with the reason when the server closes the connection, writes
//// something the client does not expect, or does not answer within 5 s, and
//// the ramp (`genesis_prime/load_run`) takes that end as the player's failure.
//// The player holds all three of its connections, the STS and the auth one too,
//// until it ends, so each listener holds a connection per player.
////
//// With other players in sight (every player starts at the same place) the server
//// also writes their units' 0x262, 0x638 and 0x355 to the player, which it reads
//// and drops among the pongs (`game_client.pong_among_messages`). A walking player
//// (`play`'s `walking`) also sends one 0x0637 every 125 ms, the client's own
//// movement send interval until the server sets one (opcode.0xf1), moving a few
//// units along x and back, so every player in the map is relayed it.
////
//// The pings are the client's own (SendNetworkPings, opcode.0x0, opcode.0x1):
//// the first has number 0, each next is sent only after the last is answered,
//// is the one after it modulo 20, and goes at most once every 500 ms after the
//// last was sent. It is the game connection that is pinged here; the other two
//// are idle.
////
//// A player can also walk and return (`moves_and_returns`): it enters the world,
//// sends one movement message (0x0637, opcode.0x637) that puts it at a position,
//// drops its game connection, logs in again as the same account and reads the
//// position 0x262 places the player at, which is where the server saved it.

import game_client
import genesis_prime/add_account
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/load_sample
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result
import genesis_prime/message/create_result
import genesis_prime/message/game_server_handoff
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/step/runtime
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import login_client.{type Ports}
import mug
import pog

/// A player's account: its login name, the one password every account has, the
/// number its SRP secret is made from, and the name of the character it
/// creates.
pub type Account {
  Account(
    login_name: String,
    password: String,
    seed: Int,
    character_name: String,
  )
}

/// The stages of a player's path, in order.
pub type Stage {
  StsLogin
  AuthLogin
  GameHello
  CharacterList
  Create
  EnterWorld
  FirstPong
}

/// What a player tells the ramp as it goes.
pub type Report {
  /// The player began, this many milliseconds after the time it was to.
  Begun(player: Int, lag_ms: Int)
  /// The player finished a stage, which took this many milliseconds from the
  /// end of the stage before it.
  Reached(player: Int, stage: Stage, took_ms: Int)
  /// The player's step ended, with each ping's round trip in microseconds.
  Finished(player: Int, round_trips_us: List(Int))
}

/// The next ping: its number and how long to wait before sending it.
pub type Ping {
  Ping(number: Int, wait_ms: Int)
}

/// The client's build, which the auth server checks.
const build = 16_042

/// The stages of the path, in the order a player goes them.
pub fn stages() -> List(Stage) {
  [StsLogin, AuthLogin, GameHello, CharacterList, Create, EnterWorld, FirstPong]
}

/// A stage in words, for the run's report.
pub fn describe(stage: Stage) -> String {
  case stage {
    StsLogin -> "the STS login"
    AuthLogin -> "the auth login"
    GameHello -> "the game hello"
    CharacterList -> "the character list"
    Create -> "the create"
    EnterWorld -> "the world entry"
    FirstPong -> "the first pong"
  }
}

/// The accounts numbered `first` up to `count` of them: each its own login
/// name and character name, and a SRP secret of its own.
pub fn accounts(first first: Int, count count: Int) -> List(Account) {
  int.range(from: first + count - 1, to: first - 1, with: [], run: list.prepend)
  |> list.map(fn(index) {
    Account(
      login_name: "load-" <> int.to_string(index),
      password: "load-password",
      seed: index,
      character_name: string.capitalise(letters(index, 5)) <> " Load",
    )
  })
}

/// The index as five lower-case letters, so character names (letters and one
/// space, lua rule 0) differ as the indexes do.
fn letters(index: Int, width: Int) -> String {
  case width {
    0 -> ""
    _ ->
      letters(index / 26, width - 1)
      <> string.slice("abcdefghijklmnopqrstuvwxyz", index % 26, 1)
  }
}

/// Inserts the accounts into the database of the pool, each with its SRP
/// verifier and a game account of its own, as the add-account tool does. A
/// refusal of the database stops the program.
pub fn seed(
  pool pool: pog.Connection,
  accounts accounts: List(Account),
) -> Nil {
  list.each(accounts, fn(account) {
    let #(_game_account_id, query) =
      add_account.new_account(
        login_name: account.login_name,
        password: account.password,
      )
    let assert Ok(_) = query(pool) as "the database took the account"
    Nil
  })
}

/// The ping that follows the last one answered, with its number the one after
/// the answered number modulo 20 and its wait the rest of the 500 ms since the
/// last was sent (SendNetworkPings).
pub fn next_ping(
  answered answered: Int,
  sent_at_ms sent_at_ms: Int,
  now_ms now_ms: Int,
) -> Ping {
  Ping(
    number: { answered + 1 } % 20,
    wait_ms: int.max(0, sent_at_ms + 500 - now_ms),
  )
}

/// Plays the whole path as the account's player, beginning at `begin_at_ms` on
/// the monotonic clock and pinging until `until_ms`, telling `report` as it
/// goes. A step of the server that is not what the client expects stops the
/// process.
pub fn play(
  player player: Int,
  account account: Account,
  ports ports: Ports,
  begin_at_ms begin_at_ms: Int,
  until_ms until_ms: Int,
  walking walking: Bool,
  report report: Subject(Report),
) -> Nil {
  process.sleep(int.max(0, begin_at_ms - runtime.now().monotonic_ms))
  let begun = load_sample.microseconds()
  process.send(report, Begun(player:, lag_ms: begun / 1000 - begin_at_ms))
  let reached = fn(stage, since) {
    let now = load_sample.microseconds()
    process.send(
      report,
      Reached(player:, stage:, took_ms: { now - since } / 1000),
    )
    now
  }
  let login =
    login_client.sts_login(
      ports:,
      name: account.login_name,
      password: account.password,
      seed: account.seed,
    )
  let mark = reached(StsLogin, begun)
  let auth = login_client.auth_login(ports:, login:, build:)
  let handed = handed_off(auth)
  let mark = reached(AuthLogin, mark)
  let game =
    game_client.connect(
      port: ports.game_port,
      session_key: handed.session_key,
      account_name: account.login_name,
    )
  let mark = reached(GameHello, mark)
  list_characters(game)
  let mark = reached(CharacterList, mark)
  let character_id = create_character(game:, name: account.character_name)
  let mark = reached(Create, mark)
  let #(_burst, have) = enter_world(game:, character_id:)
  let mark = reached(EnterWorld, mark)
  let sent_at_ms = runtime.now().monotonic_ms
  let #(first, have) = round_trip(game:, have:, number: 0)
  let _mark = reached(FirstPong, mark)
  let trips =
    keep_playing(
      game:,
      have:,
      answered: 0,
      sent_at_ms:,
      until_ms:,
      trips: [first],
      walk: case walking {
        True -> Some(Walk(last_move_ms: sent_at_ms, moves: 0))
        False -> None
      },
    )
  process.send(report, Finished(player:, round_trips_us: trips))
  game_client.close(game:)
  let _closed = mug.shutdown(auth)
  Nil
}

/// Where a player stands: the world position x, y, z, each a 32-bit float.
pub type Position {
  Position(x: Float, y: Float, z: Float)
}

/// Plays the path as the account's player to the world, sends one movement
/// message that puts the player at `to`, drops the game connection, calls
/// `after_the_drop` (which returns once the server has taken the drop), logs in
/// again as the same account, plays the same character and reads the position
/// of the unit the server creates (0x262's kind 2). A step of the server that is
/// not what the client expects stops the process.
pub fn moves_and_returns(
  account account: Account,
  ports ports: Ports,
  to to: Position,
  after_the_drop after_the_drop: fn() -> Nil,
) -> Position {
  let #(game, auth) = log_in(account:, ports:)
  list_characters(game)
  let character_id = create_character(game:, name: account.character_name)
  let _burst = enter_world(game:, character_id:).0
  game_client.send_world(game:, message_id: 0x0637, body: move_to(to))
  game_client.close(game:)
  let _closed = mug.shutdown(auth)
  after_the_drop()
  let #(game, auth) = log_in(account:, ports:)
  list_characters(game)
  let burst = enter_world(game:, character_id:).0
  game_client.close(game:)
  let _closed = mug.shutdown(auth)
  placed_at(burst)
}

/// The STS login, the auth login and the game hello of the account's player: its
/// game connection and its auth connection.
pub fn log_in(
  account account: Account,
  ports ports: Ports,
) -> #(game_client.Game, mug.Socket) {
  let login =
    login_client.sts_login(
      ports:,
      name: account.login_name,
      password: account.password,
      seed: account.seed,
    )
  let auth = login_client.auth_login(ports:, login:, build:)
  let handed = handed_off(auth)
  let game =
    game_client.connect(
      port: ports.game_port,
      session_key: handed.session_key,
      account_name: account.login_name,
    )
  #(game, auth)
}

/// What the auth server hands the player to the game server with: 0x0591 and
/// 0x03DB answer the login, and 0x03DB carries the session key.
fn handed_off(auth: mug.Socket) -> game_server_handoff.GameServerHandoff {
  let assert [_accepted, handoff] =
    login_client.read_frames(client: auth, have: <<>>, count: 2)
    as "the auth server answers a login with 0x0591 and 0x03DB"
  let assert Ok(handed) =
    game_server_handoff.decode(login_client.in_the_auth_wrapper(handoff).body)
    as "0x03DB decodes"
  handed
}

/// Asks for the character list, which 0x097F, 0x0968, 0x0036 and 0x0117
/// answer.
pub fn list_characters(game: game_client.Game) -> Nil {
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_tier, _entitlements, _level, _list] =
    game_client.read(game:, count: 4)
    as "0x097F, 0x0968, 0x0036 and 0x0117 answer 0x07E0"
  Nil
}

/// Creates the player's character, and its id.
fn create_character(game game: game_client.Game, name name: String) -> Int {
  game_client.send_create(game:, body: create_request(name))
  let assert [created] = game_client.read(game:, count: 1)
    as "one 0x00DC answers a create"
  let assert Ok(created) = create_character_result.decode(created.body)
    as "0x00DC decodes"
  assert created.result == create_result.CreateOk
    as "the server created the character"
  created.character_id
}

/// Plays the character into the world, and the messages that put it there,
/// with the bytes the server wrote after them.
pub fn enter_world(
  game game: game_client.Game,
  character_id character_id: Int,
) -> #(List(Frame), BitArray) {
  let assert Ok(play_body) = play_character.encode(PlayCharacter(character_id:))
    as "0x07DD encodes"
  game_client.send(game:, message_id: 0x07DD, body: play_body)
  let #(burst, have) =
    game_client.read_kept(
      game:,
      have: <<>>,
      count: list.length(game_client.world_entry_ids),
    )
  assert list.map(burst, fn(frame) { frame.message_id })
    == game_client.world_entry_ids
    as "the player enters the world with 0xAD, 0x262, 0x19B, 0x6BC, 0x636, 0xF1, 0x61, 0x1DA and 0x1BC"
  #(burst, have)
}

/// The body of 0x0637 that moves the player to the position: one kind 2 command
/// with its bit clear (opcode.0x637, 0x1400ad350).
fn move_to(position: Position) -> BitArray {
  game_client.moves_body(client_clock: 0, commands: [
    game_client.position_command(x: position.x, y: position.y, z: position.z),
  ])
}

/// The position the burst of an entry places the player at: the kind 2 command
/// of 0x262, which the server writes first (0x1404586e0).
fn placed_at(burst: List(Frame)) -> Position {
  let #(x, y, z) =
    game_client.placed_at(unit: game_client.unit_create_player_in(frames: burst))
  Position(x:, y:, z:)
}

/// Where a walking player is: when it sent its last 0x0637, and how many it has
/// sent.
type Walk {
  Walk(last_move_ms: Int, moves: Int)
}

/// How often a walking player sends its movement, in milliseconds: the client's
/// own movement send interval until the server sets one (opcode.0xf1).
const move_every_ms = 125

/// How many units a walking player steps along x before it steps back.
const steps_out = 10

/// Pings until the step ends, each ping as the client's rule has it, and, for a
/// walking player, sends a 0x0637 every `move_every_ms`; what else the server
/// writes meanwhile is read and dropped.
fn keep_playing(
  game game: game_client.Game,
  have have: BitArray,
  answered answered: Int,
  sent_at_ms sent_at_ms: Int,
  until_ms until_ms: Int,
  trips trips: List(Int),
  walk walk: Option(Walk),
) -> List(Int) {
  let now = runtime.now().monotonic_ms
  let ping = next_ping(answered:, sent_at_ms:, now_ms: now)
  let ping_at = now + ping.wait_ms
  let move_at = case walk {
    Some(Walk(last_move_ms:, ..)) -> last_move_ms + move_every_ms
    None -> ping_at
  }
  let next_at = int.min(ping_at, move_at)
  case next_at >= until_ms {
    True -> trips
    False -> {
      process.sleep(int.max(0, next_at - now))
      let #(walk, have) = case walk {
        Some(Walk(moves:, ..)) if move_at <= next_at -> {
          game_client.send_world(
            game:,
            message_id: 0x0637,
            body: step_of_the_walk(moves),
          )
          #(
            Some(Walk(
              last_move_ms: runtime.now().monotonic_ms,
              moves: moves + 1,
            )),
            game_client.drain(game:, have:),
          )
        }
        Some(_) | None -> #(walk, have)
      }
      case ping_at <= next_at {
        True -> {
          let sent_at_ms = runtime.now().monotonic_ms
          let #(trip, have) = round_trip(game:, have:, number: ping.number)
          keep_playing(
            game:,
            have:,
            answered: ping.number,
            sent_at_ms:,
            until_ms:,
            trips: [trip, ..trips],
            walk:,
          )
        }
        False ->
          keep_playing(
            game:,
            have:,
            answered:,
            sent_at_ms:,
            until_ms:,
            trips:,
            walk:,
          )
      }
    }
  }
}

/// The 0x0637 of a walking player's `moves`th step: one kind 2 command at a
/// place a few units along x from where the characters start (World 3460, the
/// WorldLocation2 row 51596 position), out and back.
fn step_of_the_walk(moves: Int) -> BitArray {
  let along = moves % { 2 * steps_out }
  let offset = case along <= steps_out {
    True -> along
    False -> 2 * steps_out - along
  }
  game_client.moves_body(client_clock: moves * move_every_ms, commands: [
    game_client.position_command(
      x: 29.128599166870117 +. int.to_float(offset),
      y: -853.87158203125,
      z: -560.18798828125,
    ),
  ])
}

/// Sends a ping and waits for its pong, which must carry the ping's number, the
/// other players' messages that come first read and dropped; the round trip in
/// microseconds and the bytes read beyond the pong.
fn round_trip(
  game game: game_client.Game,
  have have: BitArray,
  number number: Int,
) -> #(Int, BitArray) {
  let sent = load_sample.microseconds()
  game_client.send_ping(game:, number:)
  let #(answered, have) = game_client.pong_among_messages(game:, have:)
  assert answered == number as "opcode.0x1: the pong carries the ping's number"
  #(load_sample.microseconds() - sent, have)
}

/// The create request of CharacterCreation row 466 (class 1, race 1, sex 1, a
/// PreTutorial start with no entitlement and no cost) for a path of 1, the look
/// of labels 2 and 22, and the 46 bone values race 1, sex 1 carries
/// (opcode.0x25b.counts), each the float 1.0 plus one step (0x3F800001).
fn create_request(name: String) -> BitArray {
  let assert Ok(body) =
    create_character.encode(CreateCharacter(
      creation_id: 466,
      name:,
      path: 1,
      customisation_labels: [2, 22],
      customisation_values: [1, 1],
      bone_values: list.repeat(0x3F800001, 46),
    ))
    as "the request encodes"
  body
}
