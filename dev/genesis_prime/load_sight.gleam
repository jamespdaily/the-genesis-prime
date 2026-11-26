//// What a client of a load run read of the other players, from the frames the server
//// wrote it (`genesis_prime/load_player` for a walker, `genesis_prime/load_move_delay` for a
//// probe). Pure: a test plants the frames.
////
//// ```
//// each frame a client reads ─▶ read ─▶ Sight: the players shown, the frames read after a
////                                      unit's removal, the cast frames by kind
//// every client's Sight ─▶ players_shown, frames_after_removal, cast_frames_read
//// the casts the walkers press ─▶ casts_owed ─▶ the casts each probe is owed
//// ```
////
//// - A client is shown a player by a 0x262 of the player's unit and stops being shown it by
////   the unit's 0x355 (`opcode.0x262`, `opcode.0x355`). A 0x262 for a unit already shown is
////   not a second pair, and one after a 0x355 is. The client's own unit, a creature's and a
////   static object's 0x262 are no pair.
//// - A 0x638 for a unit after its 0x355 and before its next 0x262 is a frame read after the
////   unit's removal (`legal_order_support.check_frames` holds the same order for a viewer);
////   a 0x638 for a unit never created is the client's logged drop (`opcode.0x638`) and is not
////   counted. Only a 0x638 is read for this, so a client that has seen no removal does not
////   decode them.
//// - A cast is read as a 0x7ff, a 0x7f4 and a 0x7fe (`opcode.0x7ff`); the sight counts each
////   kind, whoever cast.
//// - A cast is owed a probe once it finished a settle time before the probes stopped
////   reading, as `load_respawn.needed` owes a respawn for a death.

import game_client
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_movement
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

/// What one client read of the other players: the players it is shown now, those it was
/// shown and then told were removed, how many 0x262 of players it read, how many 0x638 it
/// read for a removed unit, the cast frames by message id, and when it read its last
/// 0x262 of a player, in microseconds.
pub type Sight {
  Sight(
    own_unit_id: Int,
    shown: Set(Int),
    removed: Set(Int),
    creates: Int,
    after_removal: Int,
    cast_frames: Dict(Int, Int),
    last_create_us: Option(Int),
  )
}

/// A client with `own_unit_id` that has read nothing.
pub fn new(own_unit_id own_unit_id: Int) -> Sight {
  Sight(
    own_unit_id:,
    shown: set.new(),
    removed: set.new(),
    creates: 0,
    after_removal: 0,
    cast_frames: dict.new(),
    last_create_us: None,
  )
}

/// The sight after the client read `frame` at `at_us`.
pub fn read(sight sight: Sight, frame frame: Frame, at_us at_us: Int) -> Sight {
  case frame.message_id {
    0x0262 -> created(sight:, frame:, at_us:)
    0x0355 -> removed(sight:, frame:)
    0x0638 -> moved(sight:, frame:)
    0x07FF | 0x07F4 | 0x07FE ->
      Sight(
        ..sight,
        cast_frames: dict.upsert(sight.cast_frames, frame.message_id, fn(found) {
          option.unwrap(found, 0) + 1
        }),
      )
    _ -> sight
  }
}

fn created(sight sight: Sight, frame frame: Frame, at_us at_us: Int) -> Sight {
  let assert Ok(unit) = game_client.created_unit(body: frame.body)
    as "0x0262 decodes as a player's, a creature's or a static object's"
  case unit {
    game_client.PlayerCreated(unit:) ->
      case
        unit.unit_id == sight.own_unit_id
        || set.contains(sight.shown, unit.unit_id)
      {
        True -> sight
        False ->
          Sight(
            ..sight,
            shown: set.insert(sight.shown, unit.unit_id),
            removed: set.delete(sight.removed, unit.unit_id),
            creates: sight.creates + 1,
            last_create_us: Some(at_us),
          )
      }
    game_client.CreatureCreated(..) | game_client.ObjectCreated(..) -> sight
  }
}

fn removed(sight sight: Sight, frame frame: Frame) -> Sight {
  let assert Ok(gone) = unit_destroyed.decode(frame.body) as "0x0355 decodes"
  case set.contains(sight.shown, gone.unit_id) {
    True ->
      Sight(
        ..sight,
        shown: set.delete(sight.shown, gone.unit_id),
        removed: set.insert(sight.removed, gone.unit_id),
      )
    False -> sight
  }
}

fn moved(sight sight: Sight, frame frame: Frame) -> Sight {
  use <- bool.guard(when: set.is_empty(sight.removed), return: sight)
  let assert Ok(moved) = unit_movement.decode(frame.body) as "0x0638 decodes"
  case set.contains(sight.removed, moved.unit_id) {
    True -> Sight(..sight, after_removal: sight.after_removal + 1)
    False -> sight
  }
}

/// The 0x262 of players the clients read, each counted once while the player was shown.
pub fn players_shown(sights sights: List(Sight)) -> Int {
  list.fold(sights, 0, fn(sum, sight) { sum + sight.creates })
}

/// The frames the clients read for a unit after its removal.
pub fn frames_after_removal(sights sights: List(Sight)) -> Int {
  list.fold(sights, 0, fn(sum, sight) { sum + sight.after_removal })
}

/// The frames with `message_id` (0x07FF, 0x07F4 or 0x07FE) the clients read.
pub fn cast_frames_read(
  sights sights: List(Sight),
  message_id message_id: Int,
) -> Int {
  list.fold(sights, 0, fn(sum, sight) {
    sum
    + option.unwrap(
      option.from_result(dict.get(sight.cast_frames, message_id)),
      0,
    )
  })
}

/// The casts each probe is owed, of the casts pressed at `pressed_ms` that last
/// `duration_ms`: those that finished at least `settle_ms` before the probes stopped
/// reading at `ended_ms`, and at least 1.
pub fn casts_owed(
  pressed_ms pressed_ms: List(Int),
  duration_ms duration_ms: Int,
  ended_ms ended_ms: Int,
  settle_ms settle_ms: Int,
) -> Int {
  int.max(
    1,
    list.count(pressed_ms, fn(at_ms) {
      at_ms + duration_ms <= ended_ms - settle_ms
    }),
  )
}
