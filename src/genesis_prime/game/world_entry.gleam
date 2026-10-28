//// Entering the world: the client's request to play a character, from the
//// store's read of it, through its map's join, to the messages that put the
//// player in the world. Like character select it is a feature of the game
//// connection's rule (genesis_prime/game/connection): it makes its own asks
//// and takes their answers, and the rule turns its effects into writes, log
//// lines, asks and its watch on the map.
////
//// ```
//// 0x07DD play, character id  ─▶ play_requested ─▶ Ask store LoadCharacter(account, id)
//// Loaded(character)          ─▶ loaded         ─▶ Ask map MapId(world, 0): Join(connection, id)
////                                                 (or Refused: the rule hands back to select)
//// Joined(unit id)            ─▶ joined         ─▶ Send 0xAD, 0x262, 0x19B, 0x636, 0xF1, 0x61
////                                                 Entered(map, unit id): the rule watches the map
//// ```
////
//// - **The order** is the client's: 0xAD first; 0x262 before 0x19B; 0x19B
////   before 0x636 and 0x61 (0x1403b5ad0, 0x14057a630, 0x1403c74d0). 0xF1
////   sets the flag loading's last stage waits on (0x1403b67e0).
//// - **0xAD** carries the saved world and position, and 0.0 in its last two
////   floats, which neither entry path reads (opcode.0xad.last_floats).
//// - **0x636** carries the player's unit id, the value 0 and the reset bit
////   1 (vector.opcode.0x636.body); the client echoes the value in 0x635.
//// - **0xF1:** Normal difficulty 0, prime level 0, flags 0, for an open world
////   (opcode.0xf1.fields).
//// - **0x19B:** the player's unit id; its second value is never read, 0
////   (opcode.0x19b.second_value).
//// - **Refused.** A character the account does not have, or one with no
////   saved place (world 0, made before create wrote the start place), is not
////   entered: a warning, and the rule hands back to character select, which
////   sends 0x0162 Failed and the list again, as before world entry
////   (opcode.0x162.after_create).
//// - **Instance 0** for every world: open worlds share one instance
////   (genesis_prime/world_map/map_id). An instanced start world is not met
////   yet.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/play_character.{type PlayCharacter}
import genesis_prime/step.{type ConnectionId}
import genesis_prime/store.{type AccountId, type Character}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId}

/// What world entry asks or sends; the game connection's rule turns each into
/// its own effect.
pub type Effect {
  /// Ask the store; its answer comes back to `loaded`.
  AskStore(request: store.WorldRequest)
  /// Ask the map; its answer comes back to `joined`.
  AskMap(map: MapId, message: map.Message)
  /// Send this message to the client, in the game wrapper under the
  /// connection's cipher.
  Send(frame: Frame)
  /// Log this as a warning: a request the real client would not send.
  Warn(text: String)
}

/// Where world entry is.
pub opaque type State {
  /// The store is asked for the character.
  Loading(character_id: Int)
  /// The map is asked to take the character.
  Joining(character: Character, map: MapId)
}

/// What the store's read of the character leads to.
pub type Loaded {
  /// The map is asked to take the player.
  Join(state: State, effects: List(Effect))
  /// The character is not entered; character select refuses the play.
  Refused(character_id: Int, warning: String)
}

/// A player in the world: its map, the run of the map that took it, which
/// the rule watches as `Map(map, incarnation)`, and its unit id.
pub type Entered {
  Entered(map: MapId, incarnation: Int, unit_id: Int)
}

/// The client's 0x07DD, read for this account: the store is asked for the
/// character.
pub fn play_requested(
  account_id account_id: AccountId,
  request request: PlayCharacter,
) -> #(State, List(Effect)) {
  todo as "built in the build"
}

/// The store's answer to `play_requested`'s ask.
pub fn loaded(
  state state: State,
  answer answer: store.WorldAnswer,
  connection connection: ConnectionId,
) -> Loaded {
  todo as "built in the build"
}

/// The map's answer to `loaded`'s ask: the messages that put the player in
/// the world, in the client's order.
pub fn joined(
  state state: State,
  answer answer: map.Outgoing,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
) -> #(Entered, List(Effect)) {
  todo as "built in the build"
}
