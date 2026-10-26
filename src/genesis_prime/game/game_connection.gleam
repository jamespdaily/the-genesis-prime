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
import genesis_prime/connection/socket_owner.{type Protocol}
import genesis_prime/game/game_session
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/handoff
import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/maps
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/loader/store.{type Tables}
import gleam/erlang/process.{type Name, type Subject}
import gleam/option.{type Option}
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
  todo as "the services of a running server"
}

/// One connection's state.
pub opaque type Connection {
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
pub type Output {
  Output(connection: Connection, send: List(BitArray), close: Bool)
}

/// A new connection and its first output: the hello. `peer` is the client's
/// address as text, which names it in the log until the key names an account.
pub fn new(services services: Services, peer peer: Option(String)) -> Output {
  todo as "a new connection"
}

/// Takes a frame the socket's owner cut.
pub fn receive(
  connection connection: Connection,
  frame frame: Frame,
) -> Output {
  todo as "a frame"
}

/// Takes a delivery from the map.
pub fn delivered(
  connection connection: Connection,
  delivery delivery: Delivery,
) -> Output {
  todo as "a delivery"
}

/// What a listener serves for the game: frames, a connection of this module
/// for each client that connects, which writes the hello as it connects.
pub fn protocol(services services: Services) -> Protocol {
  todo as "the game's protocol"
}
