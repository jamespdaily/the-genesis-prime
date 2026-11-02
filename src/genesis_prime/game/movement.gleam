//// The player's movement in the world, a feature of the game connection's rule
//// (genesis_prime/game/connection) as character select and world entry are:
//// where the connection last heard the client say the player stands, which of
//// the client's commands it refuses, and the save of that place. The rule
//// turns its effects into the store's ask and log lines.
////
//// ```
//// 0x637, decoded          ─▶ moved        ─▶ the place kept, or a refusal that ends the connection
//// the 60 s timer          ─▶ save         ─▶ Ask store SavePlace(account, character, epoch, place)
//// the store's answer      ─▶ saved        ─▶ a log line when nothing was saved
//// ```
////
//// - **What is kept** is the last position and the last rotation the client
////   sent while it stood in the world's own frame (kind 1 is 0); a position or
////   rotation sent while kind 1 names a platform unit is in that unit's frame
////   and is not kept (opcode.0x637). The frame is kept between messages, since
////   the client sends only the commands that changed.
//// - **The place** is `genesis_prime/game/start_place`'s, so the world and the
////   zone never change here and a moved place is never in world 0.
//// - **The epoch** is the one the login was told when it loaded the character
////   (genesis_prime/store `SessionEpoch`); a save names it.

import genesis_prime/game/start_place.{type Facing, type Place}
import genesis_prime/store.{
  type AccountId, type CharacterId, type MoveAnswer, type MoveRequest,
  type SessionEpoch, SavePlace,
}

/// What the movement asks or logs; the game connection's rule turns each into
/// its own effect.
pub type Effect {
  /// Ask the store; its answer comes back to `saved`.
  AskStore(request: MoveRequest)
  /// Log a warning: an outside failure the server recovered from.
  Warn(text: String)
  /// Log at info.
  Note(text: String)
}

/// The frame the client's position is in: the world's, or the frame of the
/// unit the player stands on, which the client names in kind 1 (0 for none).
pub type Footing {
  OnTheWorld
  OnPlatform(unit_id: Int)
}

/// Where the player stands and how it is held: the last place the client's
/// commands put it, in the world's own frame, the frame the client's later
/// commands are in, and the epoch its login was told.
pub opaque type State {
  State(place: Place, footing: Footing, session_epoch: SessionEpoch)
}

/// One command of a 0x637 the rule acts on. The floats are the 32 bits the
/// message carries them as, so a value that is no finite float is one the rule
/// can refuse; the commands the rule does not act on are `Other`.
pub type Command {
  /// Kind 1: the frame the commands after it are in.
  Standing(footing: Footing)
  /// Kind 2: the position x, y, z.
  Position(x: Int, y: Int, z: Int)
  /// Kind 14: the rotation yaw, pitch, roll.
  Rotation(yaw: Int, pitch: Int, roll: Int)
  /// Kind 24: the unit's state flags.
  StateFlags(flags: Int)
  /// Kind 27: the movement mode.
  Mode(mode: Int)
  /// Any other kind, its data read and not kept: kind 0 is the client's own
  /// clock, which nothing compares with the server's.
  Other(kind: Int)
}

/// A 0x637 as the connection decodes it from the client's bytes: the client's
/// clock in milliseconds and its commands in the order they were sent.
pub type Moves {
  Moves(client_clock: Int, commands: List(Command))
}

/// Why a command is refused, which ends the connection: the client's own code
/// never sends it.
pub type Refusal {
  /// A position or rotation float that is infinite or not a number.
  NotFinite(kind: Int)
  /// A height below -2048, which the client raises to -2048 before it sends
  /// (movement_command.position_bound).
  BelowTheWorld(y: Float)
  /// State flags above 0x3ffff (movement_command.kind_24).
  UnknownStateFlags(flags: Int)
  /// A mode other than 0, 1 and 3 (movement_command.kind_27).
  UnknownMode(mode: Int)
  /// A move speed setting above 2 (0x140c45dd0).
  UnknownSpeedSetting(setting: Int)
}

/// How long after the player enters the world, and after each save, the
/// place is saved again: 60 seconds, a server choice. A connection whose own
/// save fails, or that crashes, loses at most this much movement.
pub const save_period_ms = 60_000

/// The movement of a player that enters the world at `place` as the login whose
/// epoch is `session_epoch`: in the world's own frame.
pub fn entered(
  place place: Place,
  session_epoch session_epoch: SessionEpoch,
) -> State {
  State(place:, footing: OnTheWorld, session_epoch:)
}

/// The place the player last stood at in the world's own frame, with the way
/// it faced.
pub fn place(state state: State) -> Place {
  state.place
}

/// The way the player last faced in the world's own frame.
pub fn facing(state state: State) -> Facing {
  start_place.facing(state.place)
}

/// What a 0x637 does to where the player stands, command by command in the
/// order sent: the frame of kind 1 holds for the commands after it and for later
/// messages; a position or rotation in the world's frame is kept; a command
/// the client's own code never sends is refused, and then nothing of the
/// message is kept.
pub fn moved(
  state _state: State,
  moves _moves: Moves,
) -> Result(State, Refusal) {
  panic as "built in the next commit"
}

/// Whether a move speed setting is one the client has: 0 to 2 (0x140c45dd0).
pub fn speed_setting(setting _setting: Int) -> Result(Nil, Refusal) {
  panic as "built in the next commit"
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal _refusal: Refusal) -> String {
  panic as "built in the next commit"
}

/// The save of where the player stands now, named by the login's epoch.
pub fn save(
  state state: State,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
) -> Effect {
  AskStore(request: SavePlace(
    account_id:,
    character_id:,
    session_epoch: state.session_epoch,
    place: state.place,
  ))
}

/// What the store's answer to the save says: nothing for a saved place, a note
/// for a save that changed nothing because a later login holds the character.
pub fn saved(answer _answer: MoveAnswer) -> List(Effect) {
  panic as "built in the next commit"
}
