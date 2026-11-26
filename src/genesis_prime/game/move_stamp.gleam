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
////   memory outlives the owner's `Gone`, and a sight that ends at an older generation
////   than the one held leaves the newer sight held.
//// - A unit's hold is at most `most_held_chunks` (16) chunks: a guess, a mover's 8
////   moves a second for 2 seconds (the load tool's rate), since no client or recording
////   says how long a map may be behind. The 17th drops the oldest and the hold is
////   warned of once for as long as its oldest generation stays the same. Every hold and every memory ends with the viewer's stay.
//// - The unit's owner ending (`gone`) keeps the memory of the last sight, so the
////   viewing is the only judge of a late move after it.
//// - A snapshot older than the generation the viewer holds, or at most the one it
////   remembers as ended, is refused: the map relays notices of one pair in the order
////   it issues their generations, so the viewer shows nothing for it.

import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/world_map/generation.{type Generation}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result

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
pub type Viewing {
  Viewing(sights: Dict(Int, Sight), holds: Dict(Int, Waiting))
}

/// The chunks held of one unit, oldest first, and whether the hold was warned of
/// (`Viewing.holds`).
pub type Waiting {
  Waiting(moves: List(Move), warned_of: Bool)
}

/// What a viewer does with a move.
pub type Verdict {
  /// Write it and move the picture.
  Apply
  /// Write nothing.
  Drop
  /// Keep it for the notice of its generation.
  Hold
  /// Keep it; the hold was full and its oldest chunk was dropped for it, which was
  /// warned of already.
  HoldDroppingOldest
  /// Keep it; the hold was full and its oldest chunk was dropped for it, the first
  /// time for the hold: the viewer warns of it, naming the sight it holds of the unit.
  HoldFirstOverflow(sight: Option(Sight))
}

/// The most commands one 0x638 holds: its count is 5 bits (opcode.0x638).
const most_commands_in_a_chunk = 31

/// The chunks a move is sent as: its `commands` in order, at most 31 to a chunk, and
/// none for no command, each stamped alike.
pub fn moves(
  unit_id unit_id: Int,
  generation generation: Generation,
  server_time_ms server_time_ms: Int,
  commands commands: List(RelayedMovement),
) -> List(Move) {
  list.sized_chunk(commands, most_commands_in_a_chunk)
  |> list.map(fn(chunk) {
    Move(unit_id:, generation:, server_time_ms:, commands: chunk)
  })
}

/// A viewer that holds nothing.
pub fn new() -> Viewing {
  Viewing(sights: dict.new(), holds: dict.new())
}

/// What the viewer does with `move`, and what it holds after.
pub fn take(viewing viewing: Viewing, move move: Move) -> #(Viewing, Verdict) {
  let sight = dict.get(viewing.sights, move.unit_id)
  case sight {
    Ok(Held(generation:)) ->
      case generation.compare(first: move.generation, second: generation) {
        order.Eq -> #(viewing, Apply)
        order.Lt -> #(viewing, Drop)
        order.Gt -> hold(viewing:, move:)
      }
    Ok(Departed(generation:)) ->
      case generation.compare(first: move.generation, second: generation) {
        order.Gt -> hold(viewing:, move:)
        order.Eq | order.Lt -> #(viewing, Drop)
      }
    Error(Nil) -> hold(viewing:, move:)
  }
}

/// The move kept at the end of its unit's hold; the oldest chunk goes when the hold
/// is full.
fn hold(viewing viewing: Viewing, move move: Move) -> #(Viewing, Verdict) {
  let waiting =
    dict.get(viewing.holds, move.unit_id)
    |> result.unwrap(Waiting(moves: [], warned_of: False))
  let #(kept, verdict) = case list.length(waiting.moves) >= most_held_chunks {
    False -> #(waiting.moves, Hold)
    True -> #(list.drop(waiting.moves, 1), case waiting.warned_of {
      True -> HoldDroppingOldest
      False ->
        HoldFirstOverflow(
          sight: option.from_result(dict.get(viewing.sights, move.unit_id)),
        )
    })
  }
  let warned_of = waiting.warned_of || verdict != Hold
  #(
    Viewing(
      ..viewing,
      holds: dict.insert(
        viewing.holds,
        move.unit_id,
        Waiting(moves: list.append(kept, [move]), warned_of:),
      ),
    ),
    verdict,
  )
}

/// The sight of the unit begins or renews at `generation`: the unit's moves held for
/// it, in the order they arrived, which the viewer now applies, and how many held
/// moves of an older sight were dropped. A `generation` older than the one held, or
/// at most the one remembered as ended, is refused with `Error(Nil)` and changes
/// nothing.
pub fn snapshot(
  viewing viewing: Viewing,
  unit_id unit_id: Int,
  generation generation: Generation,
) -> Result(#(Viewing, List(Move), Int), Nil) {
  let is_stale = case dict.get(viewing.sights, unit_id) {
    Ok(Held(generation: held)) ->
      generation.compare(first: generation, second: held) == order.Lt
    Ok(Departed(generation: ended)) ->
      generation.compare(first: generation, second: ended) != order.Gt
    Error(Nil) -> False
  }
  case is_stale {
    True -> Error(Nil)
    False -> {
      let moves = held_moves(viewing:, unit_id:)
      let #(released, others) =
        list.partition(moves, fn(move) {
          generation.compare(first: move.generation, second: generation)
          == order.Eq
        })
      let #(newer, older) =
        list.partition(others, fn(move) {
          generation.compare(first: move.generation, second: generation)
          == order.Gt
        })
      Ok(#(
        Viewing(
          sights: dict.insert(viewing.sights, unit_id, Held(generation:)),
          holds: with_held(viewing:, unit_id:, moves: newer),
        ),
        released,
        list.length(older),
      ))
    }
  }
}

/// The sight of the unit ends at `generation`: it is remembered as ended unless the
/// viewer holds or remembers a later sight, and the moves held for it of that
/// generation or an older one are dropped; their number is returned.
pub fn departed(
  viewing viewing: Viewing,
  unit_id unit_id: Int,
  generation generation: Generation,
) -> #(Viewing, Int) {
  let later_than_this = fn(held: Generation) {
    generation.compare(first: held, second: generation) == order.Gt
  }
  let sight = case dict.get(viewing.sights, unit_id) {
    Ok(Held(generation: held)) ->
      case later_than_this(held) {
        True -> Held(generation: held)
        False -> Departed(generation:)
      }
    Ok(Departed(generation: held)) ->
      case later_than_this(held) {
        True -> Departed(generation: held)
        False -> Departed(generation:)
      }
    Error(Nil) -> Departed(generation:)
  }
  let moves = held_moves(viewing:, unit_id:)
  let newer = list.filter(moves, fn(move) { later_than_this(move.generation) })
  #(
    Viewing(
      sights: dict.insert(viewing.sights, unit_id, sight),
      holds: with_held(viewing:, unit_id:, moves: newer),
    ),
    list.length(moves) - list.length(newer),
  )
}

/// The unit has no owner any more: what is held for it is dropped, and the sight it
/// is held at is remembered as ended. The number of moves dropped is returned.
pub fn gone(viewing viewing: Viewing, unit_id unit_id: Int) -> #(Viewing, Int) {
  let sights = case dict.get(viewing.sights, unit_id) {
    Ok(Held(generation:)) ->
      dict.insert(viewing.sights, unit_id, Departed(generation:))
    Ok(Departed(..)) | Error(Nil) -> viewing.sights
  }
  let dropped = list.length(held_moves(viewing:, unit_id:))
  #(Viewing(sights:, holds: dict.delete(viewing.holds, unit_id)), dropped)
}

fn held_moves(viewing viewing: Viewing, unit_id unit_id: Int) -> List(Move) {
  case dict.get(viewing.holds, unit_id) {
    Ok(waiting) -> waiting.moves
    Error(Nil) -> []
  }
}

/// The holds with the unit's replaced by `moves`, and gone when `moves` is empty. The
/// hold keeps its warning only while its oldest chunk is of the generation it was.
fn with_held(
  viewing viewing: Viewing,
  unit_id unit_id: Int,
  moves moves: List(Move),
) -> Dict(Int, Waiting) {
  case moves, dict.get(viewing.holds, unit_id) {
    [], _ | _, Error(Nil) -> dict.delete(viewing.holds, unit_id)
    [kept, ..], Ok(waiting) -> {
      let same_oldest = case waiting.moves {
        [was, ..] ->
          generation.compare(first: kept.generation, second: was.generation)
          == order.Eq
        [] -> False
      }
      dict.insert(
        viewing.holds,
        unit_id,
        Waiting(moves:, warned_of: waiting.warned_of && same_oldest),
      )
    }
  }
}
