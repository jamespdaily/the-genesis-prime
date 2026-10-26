//// Entering the world: what the server sends, and in which order, from the
//// moment a player chose a character until the client shows the player in the
//// world. A rule: state and input in, new state and effects out.
////
//// The order is the one the client's own end of loading needs
//// (CheckWorldLoaded 0x1403E8000). The map gives the character's unit an id.
//// The server then sends 0xAD (the world and the position the client loads),
//// 0x262 (the player's unit), 0x19B (that unit is the player; the client
//// reports an error and never finishes loading when the unit does not exist
//// yet) and 0xF1 (the movement send interval, whose handler sets a flag the end
//// of loading waits for). The client sends 0xF2 when the terrain near the player
//// is ready; only then does the server send 0x61, which the client reads the
//// player's position for and which must come after 0x19B.

import genesis_prime/character/character.{type Character}
import genesis_prime/character/server_message.{type ServerMessage}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}

/// The movement send interval the server sets, in milliseconds: the client's
/// own default, 125 (the bytes at 0x140C3A004), so a client that is given none
/// moves at the same rate.
pub const movement_send_interval_milliseconds = 125

/// The facts the rule reads beyond its state: `realm_id` is the realm the
/// connection is on, which the player's unit carries, and `world_exists` tells
/// whether a World row has the id, because the client fails to load a world
/// with none.
pub type Context {
  Context(realm_id: Int, world_exists: fn(Int) -> Bool)
}

/// Where the entry has got to.
pub type State {
  /// The player has not chosen a character.
  Waiting
  /// The map was asked to join the character's unit.
  AwaitingMap(character: Character)
  /// The client has the world messages and loads the terrain; the server waits
  /// for 0xF2.
  AwaitingTerrain(unit: PlayerUnit)
  /// The client has the player in the world.
  Entered
}

/// What can happen to the entry.
pub type Input {
  /// The player chose this character (message 0x7DD).
  Begin(Character)
  /// The map gave the character's unit.
  Joined(PlayerUnit)
  /// The map would not take the character.
  MapRefused
  /// The client sent message 0xF2: the terrain near the player is loaded.
  TerrainLoaded
}

/// A message or an answer that a correct client and map never produce.
pub type Breach {
  /// A begin while a character is already entering.
  BeganTwice
  /// An answer from the map nobody asked for.
  AnswerNobodyAskedFor
  /// Message 0xF2 before the server sent the world messages, or a second one.
  TerrainLoadedOutOfOrder
}

/// What the connection's handler must do, in order.
pub type Effect {
  /// Ask the world's map to join the character; its answer comes back as
  /// `Joined` or `MapRefused`.
  JoinMap(world_id: Int, newcomer: Newcomer)
  /// Send the player a message.
  Send(ServerMessage)
  /// The character cannot enter: the player was sent message 0x162 and may
  /// choose again.
  Failed
  /// Log the breach and close the connection.
  Close(Breach)
}

/// An entry that has not begun.
pub fn new() -> State {
  Waiting
}

/// The state and the effects after an input.
pub fn decide(
  state state: State,
  input input: Input,
  context context: Context,
) -> #(State, List(Effect)) {
  todo as "the rule of entering the world"
}

/// The sentence the log line of a breach holds.
pub fn describe_breach(breach breach: Breach) -> String {
  todo as "the log text of a breach"
}
