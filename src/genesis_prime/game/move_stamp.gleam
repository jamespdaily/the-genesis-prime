//// A player's move on its way to a viewer, stamped with the sight number, and the
//// viewer's rule for taking it.
////
//// ```
//// mover's connection                         viewer's connection
//// accepted 0x637 ─▶ moves(chunks of 31) ─▶ TellMove(stay, Move(g)) ─▶ take
////                                                                       Held(g), m = g ─▶ Apply
////                                                                       Held(g), m < g ─▶ Drop
////                                                                       Held(g), m > g ─▶ Hold
////                                                                       Departed(g), m <= g ─▶ Drop
////                                                                       Departed(g), m > g ─▶ Hold
////                                                                       nothing ─▶ Hold
//// map ─▶ mover ─▶ viewer: Appeared(unit, n)  ─▶ snapshot: Held(n), the held moves of n are released
//// map ─▶ mover ─▶ viewer: Departed(n)        ─▶ departed: Departed(n), the held moves <= n are dropped
//// ```
////
//// - A move carries the generation of the relation (genesis_prime/world_map/generation)
////   the mover's copy of its viewers holds for that viewer, which only the map makes.
//// - A viewer applies a move only for the generation it holds, drops an older one,
////   and holds a newer one, or one for a unit it holds no sight of, until the notice
////   of its generation: the snapshot (the 0x262) releases the held moves of that
////   generation in the order they arrived, drops the older and keeps the newer.
//// - A unit that left is remembered by the last generation that ended, so a late move
////   of that sight is dropped and not held for a notice that never comes. The
////   memory outlives the owner's `Gone`.
//// - A unit's hold is at most `most_held_chunks` (16) chunks: a guess, a mover's 8
////   moves a second for 2 seconds (the load tool's rate), since no client or recording
////   says how long a map may be behind. The 17th drops the oldest and the hold is
////   warned of once. Every hold and every memory ends with the viewer's stay.

import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/world_map/generation.{type Generation}
import gleam/dict.{type Dict}

/// The most chunks a viewer holds of one unit; a guess (the module doc).
pub const most_held_chunks = 16

/// One chunk of a move of the unit `unit_id`, of at most 31 relayed commands in the
/// order sent, stamped with the generation of the relation it was sent for and the
/// map's clock at the move.
pub type Move {
  Move(
    unit_id: Int,
    generation: Generation,
    server_time_ms: Int,
    commands: List(RelayedMovement),
  )
}

/// What a viewer holds of a unit's sight: the generation it was shown at, or the last
/// generation that ended.
pub type Sight {
  Held(generation: Generation)
  Departed(generation: Generation)
}

/// What a viewer holds of the moves of players' units: the sight of each unit and the
/// chunks held for the notice of their generation.
pub type Stamp {
  Stamp(sights: Dict(Int, Sight), holds: Dict(Int, Waiting))
}

/// The chunks held of one unit, oldest first, and whether the hold was warned of
/// (`Stamp.holds`).
pub type Waiting {
  Waiting(moves: List(Move), warned: Bool)
}

/// What a viewer does with a move.
pub type Verdict {
  /// Write it and move the picture.
  Apply
  /// Write nothing.
  Drop
  /// Keep it for the notice of its generation; `overflowed` when the hold was
  /// full and its oldest chunk was dropped for it, the first time for the hold.
  Hold(overflowed: Bool)
}

/// A viewer that holds nothing.
pub fn new() -> Stamp {
  Stamp(sights: dict.new(), holds: dict.new())
}

/// What the viewer does with `move`, and what it holds after.
pub fn take(stamp stamp: Stamp, move _move: Move) -> #(Stamp, Verdict) {
  #(stamp, Apply)
}

/// The sight of the unit begins or renews at `generation`: the unit's moves held for
/// it, in the order they arrived, which the viewer now applies.
pub fn snapshot(
  stamp stamp: Stamp,
  unit_id _unit_id: Int,
  generation _generation: Generation,
) -> #(Stamp, List(Move)) {
  #(stamp, [])
}

/// The sight of the unit ends at `generation`.
pub fn departed(
  stamp stamp: Stamp,
  unit_id _unit_id: Int,
  generation _generation: Generation,
) -> Stamp {
  stamp
}

/// The unit has no owner any more: what is held for it is dropped, and the last
/// generation it was shown at is remembered as ended.
pub fn gone(stamp stamp: Stamp, unit_id _unit_id: Int) -> Stamp {
  stamp
}
