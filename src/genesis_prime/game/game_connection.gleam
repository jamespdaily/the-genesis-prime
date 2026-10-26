//// One game connection as a process carries it out: the frames the socket's
//// owner has cut go in, the bytes to write come out. It runs the session rule
//// and carries out its effects in order: it redeems the session key in the
//// hand-off, carries out the store's commands in workers, asks the maps to
//// join the character's unit and logs why a connection ends. A map's
//// deliveries reach it as messages to the socket's owner, which wakes the
//// conversation (`socket_owner.Waking`).
////
//// The connection holds its own state and does no socket work: whoever owns
//// the socket writes the bytes it returns, first the hello that `new` gives,
//// and closes the socket when `close` is set. Its subject for the map's
//// deliveries belongs to the process that calls `new`, which must be the
//// socket's owner: the map takes the player's unit off the map when that
//// process ends.

import genesis_prime/character/character.{type Place}
import genesis_prime/character/select
import genesis_prime/character/store_worker
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/socket_owner.{
  type Conversation, type Protocol, type Reaction, BytesRead, FrameRead, Frames,
  Protocol, Reaction, Waking,
}
import genesis_prime/game/game_context
import genesis_prime/game/game_session
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/handoff
import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/maps
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/map/world_map_process
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/telemetry/log
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import pog

/// What a connection asks the rest of the server for.
pub type Services {
  Services(
    /// Redeems a session key of 16 bytes, once.
    redeem_session_key: fn(BitArray) -> Result(Identity, Nil),
    /// Carries out a command of character select against the database and
    /// gives its answer.
    run_store: fn(select.Command) -> select.Answer,
    /// Joins a character's unit to the map of its world, with the subject its
    /// connection receives the map's deliveries on.
    enter_map: fn(Int, Newcomer, Subject(Delivery)) ->
      Result(PlayerUnit, maps.EnterError),
    /// The facts the rules read, as they are when it is called.
    context: fn() -> game_session.Context,
  )
}

/// What the services of a running server are made from.
pub type Settings {
  Settings(
    session_keys: Name(handoff.Message(Identity)),
    workers: store_worker.Workers,
    db: pog.Connection,
    registry: Name(maps.Message),
    tables: Tables,
    start: fn(CharacterCreation) -> Result(Place, Nil),
    realm_id: Int,
    clock: fn() -> Int,
    answer_deadline_ms: Int,
  )
}

/// The services of a running server.
pub fn services(settings settings: Settings) -> Services {
  Services(
    redeem_session_key: fn(key) {
      handoff.redeem(settings.session_keys, key) |> result.replace_error(Nil)
    },
    run_store: fn(command) {
      store_worker.run(
        workers: settings.workers,
        db: settings.db,
        command:,
        within_ms: settings.answer_deadline_ms,
      )
    },
    enter_map: fn(world_id, newcomer, deliveries) {
      maps.enter(
        registry: settings.registry,
        world_id:,
        newcomer:,
        connection: deliveries,
        within_ms: settings.answer_deadline_ms,
      )
    },
    context: fn() {
      game_context.build(
        tables: settings.tables,
        start: settings.start,
        realm_id: settings.realm_id,
        server_time: settings.clock(),
      )
    },
  )
}

/// One connection's state.
type Connection {
  Connection(
    services: Services,
    session: game_session.Session,
    deliveries: Subject(Delivery),
    peer: Option(String),
    account: Option(Int),
  )
}

/// What a connection hands back: itself, the bytes to write to the socket in
/// order, and whether to close the socket after writing them.
type Output {
  Output(connection: Connection, send: List(BitArray), close: Bool)
}

/// A new connection and its first output: the hello. `peer` is the client's
/// address as text, which names it in the log until the key names an account.
fn new(services services: Services, peer peer: Option(String)) -> Output {
  let #(session, effects) = game_session.start()
  run(
    connection: Connection(
      services:,
      session:,
      deliveries: process.new_subject(),
      peer:,
      account: None,
    ),
    effects:,
    context: services.context(),
    sent: [],
  )
}

/// Takes a frame the socket's owner cut.
fn receive(connection connection: Connection, frame frame: Frame) -> Output {
  let context = connection.services.context()
  let #(session, effects) =
    game_session.receive(connection.session, frame, context)
  run(
    connection: Connection(..connection, session:),
    effects:,
    context:,
    sent: [],
  )
}

/// Takes a delivery from the map.
fn delivered(
  connection connection: Connection,
  delivery delivery: Delivery,
) -> Output {
  let context = connection.services.context()
  let #(session, effects) =
    game_session.delivered(connection.session, delivery, context)
  run(
    connection: Connection(..connection, session:),
    effects:,
    context:,
    sent: [],
  )
}

/// Carries out the effects in order. What an effect asks of another process is
/// asked and answered here, and the answer is fed back to the rule, whose
/// effects come before the ones that were left.
fn run(
  connection connection: Connection,
  effects effects: List(game_session.Effect),
  context context: game_session.Context,
  sent sent: List(BitArray),
) -> Output {
  case effects {
    [] -> Output(connection:, send: list.reverse(sent), close: False)
    [effect, ..rest] ->
      case effect {
        game_session.Send(bytes) ->
          run(connection:, effects: rest, context:, sent: [bytes, ..sent])
        game_session.RedeemSessionKey(key) ->
          carry_on(answered: redeem(connection:, key:), rest:, context:, sent:)
        game_session.Store(command) ->
          carry_on(
            answered: ask_store(connection:, command:, context:),
            rest:,
            context:,
            sent:,
          )
        game_session.JoinMap(world_id:, newcomer:) ->
          carry_on(
            answered: join_map(connection:, world_id:, newcomer:, context:),
            rest:,
            context:,
            sent:,
          )
        game_session.Log(level:, text:) -> {
          write(level)(
            who(
              account: connection.account,
              peer: connection.peer,
              message: None,
            ),
            text,
          )
          run(connection:, effects: rest, context:, sent:)
        }
        game_session.End(reason) -> {
          write(game_session.level_of(reason))(
            who(
              account: connection.account,
              peer: connection.peer,
              message: message_of(reason),
            ),
            "the game connection ended: " <> game_session.describe(reason),
          )
          Output(connection:, send: list.reverse(sent), close: True)
        }
      }
  }
}

/// Goes on with the effects after one that was asked of another process: the
/// rule's answer to it comes before the effects that were left.
fn carry_on(
  answered answered: #(Connection, List(game_session.Effect)),
  rest rest: List(game_session.Effect),
  context context: game_session.Context,
  sent sent: List(BitArray),
) -> Output {
  run(
    connection: answered.0,
    effects: list.append(answered.1, rest),
    context:,
    sent:,
  )
}

/// Redeems the session key and tells the rule who it was issued to.
fn redeem(
  connection connection: Connection,
  key key: BitArray,
) -> #(Connection, List(game_session.Effect)) {
  let redeemed = connection.services.redeem_session_key(key)
  let #(session, more) =
    game_session.session_key_redeemed(connection.session, redeemed)
  case redeemed {
    Ok(identity) -> {
      log.info(
        who(account: Some(identity.id), peer: connection.peer, message: None),
        "the player reached the game server with a session key",
      )
      #(Connection(..connection, session:, account: Some(identity.id)), more)
    }
    Error(Nil) -> #(Connection(..connection, session:), more)
  }
}

/// Carries out a command of character select and tells the rule the answer.
fn ask_store(
  connection connection: Connection,
  command command: select.Command,
  context context: game_session.Context,
) -> #(Connection, List(game_session.Effect)) {
  let answer = connection.services.run_store(command)
  let #(session, more) =
    game_session.stored(connection.session, answer, context)
  #(Connection(..connection, session:), more)
}

/// Asks the map to join the character's unit and tells the rule the answer.
fn join_map(
  connection connection: Connection,
  world_id world_id: Int,
  newcomer newcomer: Newcomer,
  context context: game_session.Context,
) -> #(Connection, List(game_session.Effect)) {
  let answer =
    connection.services.enter_map(world_id, newcomer, connection.deliveries)
    |> map_answer
  let #(session, more) =
    game_session.map_answered(connection.session, answer, context)
  #(Connection(..connection, session:), more)
}

/// What the map's answer to a join means to the rule: a unit, the map's refusal
/// of a character that is on it already, or no answer from the map or its
/// registry, which includes a map that could not start.
fn map_answer(
  entered: Result(PlayerUnit, maps.EnterError),
) -> game_session.MapAnswer {
  case entered {
    Ok(unit) -> game_session.MapJoined(unit)
    Error(maps.MapRefused(world_map_process.Refused(_))) ->
      game_session.MapRefusedCharacter
    Error(maps.MapRefused(world_map_process.NotAnswering))
    | Error(maps.MapNotStarted(_))
    | Error(maps.RegistryNotAnswering) -> game_session.MapNotAnswering
  }
}

fn write(level: game_session.Level) -> fn(log.Who, String) -> Nil {
  case level {
    game_session.WarningLevel -> log.warning
    game_session.ErrorLevel -> log.error
  }
}

/// The client message an end is about, when it is about one.
fn message_of(reason: game_session.EndReason) -> Option(log.Message) {
  case reason {
    game_session.UnexpectedMessage(message_id:)
    | game_session.MalformedMessage(message_id:, ..) ->
      Some(log.Numbered(message_id))
    game_session.BadWrapper
    | game_session.SessionKeyRefused
    | game_session.CharacterSelectBreach(_)
    | game_session.WorldEntryBreach(_)
    | game_session.MapAway
    | game_session.AnswerNotBuilt -> None
  }
}

/// Who the connection's log lines are about: the account once the key has
/// named it, and the client's peer address.
fn who(
  account account: Option(Int),
  peer peer: Option(String),
  message message: Option(log.Message),
) -> log.Who {
  log.Who(
    account:,
    actor: None,
    place: Some(log.Process("game_connection")),
    message:,
    peer:,
  )
}

/// What a listener serves for the game: frames, a connection of this module
/// for each client that connects, which writes the hello as it connects.
pub fn protocol(services services: Services) -> Protocol {
  Protocol(mode: Frames, connect: fn(peer) { reaction(new(services:, peer:)) })
}

fn conversation(connection: Connection) -> Conversation {
  Waking(
    handle: fn(input) {
      case input {
        FrameRead(frame:) -> reaction(receive(connection:, frame:))
        BytesRead(..) ->
          Reaction(send: [], close: True, next: conversation(connection))
      }
    },
    wake: process.new_selector()
      |> process.select_map(connection.deliveries, fn(delivery) {
        reaction(delivered(connection:, delivery:))
      }),
  )
}

fn reaction(output: Output) -> Reaction {
  Reaction(
    send: output.send,
    close: output.close,
    next: conversation(output.connection),
  )
}
