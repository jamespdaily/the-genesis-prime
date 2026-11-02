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
//// The pings are the client's own (SendNetworkPings, opcode.0x0, opcode.0x1):
//// the first has number 0, each next is sent only after the last is answered,
//// is the one after it modulo 20, and goes at most once every 500 ms after the
//// last was sent. It is the game connection that is pinged here; the other two
//// are idle.

import game_client
import genesis_prime/add_account/sql
import genesis_prime/load_sample
import genesis_prime/login/guid
import genesis_prime/login/srp
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result
import genesis_prime/message/create_result
import genesis_prime/message/game_server_handoff
import genesis_prime/message/play_character.{PlayCharacter}
import gleam/crypto
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
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
  list.map(numbers(first:, count:), fn(index) {
    Account(
      login_name: "load-" <> int.to_string(index),
      password: "load-password",
      seed: index,
      character_name: string.capitalise(letters(index)) <> " Load",
    )
  })
}

/// `count` whole numbers from `first`.
fn numbers(first first: Int, count count: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, count), fn(_, offset) { first + offset })
}

/// The index as five lower-case letters, so character names (letters and one
/// space, lua rule 0) differ as the indexes do.
fn letters(index: Int) -> String {
  let assert Ok(digits) = int.to_base_string(index, 26)
    as "26 is a base the standard library writes"
  digits
  |> string.pad_start(to: 5, with: "0")
  |> string.to_graphemes
  |> list.map(fn(digit) {
    let assert Ok(value) = int.base_parse(digit, 26) as "a base 26 digit"
    string.slice("abcdefghijklmnopqrstuvwxyz", value, 1)
  })
  |> string.join("")
}

/// Inserts the accounts into the database of the pool, each with its SRP
/// verifier and a game account of its own, as the add-account tool does. A
/// refusal of the database stops the program.
pub fn seed(
  pool pool: pog.Connection,
  accounts accounts: List(Account),
) -> Nil {
  list.each(accounts, fn(account) {
    let salt = crypto.strong_random_bytes(32)
    let assert Ok(game_account_id) =
      guid.from_wire(crypto.strong_random_bytes(16))
      as "sixteen bytes are a GUID"
    let assert Ok(_) =
      sql.insert_account(
        pool,
        account.login_name,
        salt,
        srp.verifier(
          name: account.login_name,
          password: account.password,
          salt:,
        ),
        guid.to_text(game_account_id),
      )
      as "the database took the account"
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
  report report: Subject(Report),
) -> Nil {
  process.sleep(int.max(0, begin_at_ms - load_sample.milliseconds()))
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
  let assert [_accepted, handoff] =
    login_client.read_frames(client: auth, have: <<>>, count: 2)
    as "the auth server answers a login with 0x0591 and 0x03DB"
  let assert Ok(handed) =
    game_server_handoff.decode(login_client.in_the_auth_wrapper(handoff).body)
    as "0x03DB decodes"
  let mark = reached(AuthLogin, mark)
  let game =
    game_client.connect(
      port: ports.game_port,
      session_key: handed.session_key,
      account_name: account.login_name,
    )
  let mark = reached(GameHello, mark)
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_level, _list] = game_client.read(game:, count: 2)
    as "0x0036 and 0x0117 answer 0x07E0"
  let mark = reached(CharacterList, mark)
  game_client.send_create(game:, body: create_request(account.character_name))
  let assert [created] = game_client.read(game:, count: 1)
    as "one 0x00DC answers a create"
  let assert Ok(created) = create_character_result.decode(created.body)
    as "0x00DC decodes"
  assert created.result == create_result.CreateOk
    as "the server created the character"
  let mark = reached(Create, mark)
  let assert Ok(play_body) =
    play_character.encode(PlayCharacter(character_id: created.character_id))
    as "0x07DD encodes"
  game_client.send(game:, message_id: 0x07DD, body: play_body)
  let assert [_, _, _, _, _, _, _] = game_client.read(game:, count: 7)
    as "the player enters the world with 0xAD, 0x262, 0x19B, 0x6BC, 0x636, 0xF1 and 0x61"
  let mark = reached(EnterWorld, mark)
  let sent_at_ms = load_sample.milliseconds()
  let first = round_trip(game:, number: 0)
  let _mark = reached(FirstPong, mark)
  let trips =
    keep_pinging(game:, answered: 0, sent_at_ms:, until_ms:, trips: [first])
  process.send(report, Finished(player:, round_trips_us: trips))
  game_client.close(game:)
  let _closed = mug.shutdown(auth)
  Nil
}

/// Pings until the step ends, each ping as the client's rule has it.
fn keep_pinging(
  game game: game_client.Game,
  answered answered: Int,
  sent_at_ms sent_at_ms: Int,
  until_ms until_ms: Int,
  trips trips: List(Int),
) -> List(Int) {
  let ping =
    next_ping(answered:, sent_at_ms:, now_ms: load_sample.milliseconds())
  case load_sample.milliseconds() + ping.wait_ms >= until_ms {
    True -> trips
    False -> {
      process.sleep(ping.wait_ms)
      let sent_at_ms = load_sample.milliseconds()
      let trip = round_trip(game:, number: ping.number)
      keep_pinging(game:, answered: ping.number, sent_at_ms:, until_ms:, trips: [
        trip,
        ..trips
      ])
    }
  }
}

/// Sends a ping and waits for its pong, which must carry the ping's number; the
/// round trip in microseconds.
fn round_trip(game game: game_client.Game, number number: Int) -> Int {
  let sent = load_sample.microseconds()
  game_client.send_ping(game:, number:)
  assert game_client.read_pong(game:) == number
    as "opcode.0x1: the pong carries the ping's number"
  load_sample.microseconds() - sent
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
