//// What a client of a load run read of the other players: stub.

import genesis_prime/connection/frame.{type Frame}
import gleam/dict.{type Dict}
import gleam/set.{type Set}

/// What one client read of the other players.
pub type Sight {
  Sight(
    own_unit_id: Int,
    shown: Set(Int),
    removed: Set(Int),
    creates: Int,
    after_removal: Int,
    cast_frames: Dict(Int, Int),
    last_create_us: Int,
  )
}

/// A client that has read nothing: stub.
pub fn new(own_unit_id own_unit_id: Int) -> Sight {
  Sight(
    own_unit_id:,
    shown: set.new(),
    removed: set.new(),
    creates: 0,
    after_removal: 0,
    cast_frames: dict.new(),
    last_create_us: 0,
  )
}

/// The sight after one more frame: stub.
pub fn read(
  sight sight: Sight,
  frame _frame: Frame,
  at_us _at_us: Int,
) -> Sight {
  sight
}

/// The players' creates the sights read: stub.
pub fn players_shown(sights _sights: List(Sight)) -> Int {
  0
}

/// The frames read of a unit after its removal: stub.
pub fn frames_after_removal(sights _sights: List(Sight)) -> Int {
  0
}

/// The frames of the cast message `message_id` the sights read: stub.
pub fn cast_frames_read(
  sights _sights: List(Sight),
  message_id _message_id: Int,
) -> Int {
  0
}

/// The casts each probe is owed: stub.
pub fn casts_owed(
  pressed_ms _pressed_ms: List(Int),
  duration_ms _duration_ms: Int,
  ended_ms _ended_ms: Int,
  settle_ms _settle_ms: Int,
) -> Int {
  0
}
