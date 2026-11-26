//// What a client of a load run read of the other players, from the frames the server
//// wrote it (`genesis_prime/load_player` for a walker, `genesis_prime/load_move_delay` for a
//// probe). Pure: a test plants the frames.
////
//// ```
//// each frame a client reads ─▶ read ─▶ Sight: the players shown and removed, the frames
////                                      read after a unit's removal, the cast frames by
////                                      kind and caster
//// every client's Sight ─▶ players_shown, removals_read, frames_after_removal, cast_frames_read,
////                         held_us
//// the casts the walkers press ─▶ casts_owed ─▶ the casts each probe is owed
//// ```
////
//// - A client is shown a player by a 0x262 of the player's unit and stops being shown it by
////   the unit's 0x355 (`opcode.0x262`, `opcode.0x355`). A 0x262 for a unit already shown is
////   not a second pair, and one after a 0x355 is. The client's own unit, a creature's and a
////   static object's 0x262 are no pair. A player that was shown and was then told removed, and was
////   not shown again, is a removal the client read.
//// - A frame that names a unit after the unit's 0x355 and before its next 0x262 is a frame
////   read after the unit's removal: a 0x638, a 0x937, a 0x88c, a 0x7ff of the unit's cast,
////   and a 0x7f4 or 0x7fe of a cast the unit started (named by cast id; the sight holds each
////   cast's caster from its 0x7ff). `legal_order_support.check_frames` holds the same order
////   for a viewer of a creature. A client that has seen no removal does not decode the frames
////   other than a cast's, which it decodes for the caster.
//// - The gap: a frame that names a unit never created is the client's logged drop
////   (`opcode.0x638`) and is not counted, so a relay that reaches a viewer before its
////   snapshot of the player (`check_frames`' news before creation) is not found. The movement
////   run's walkers never leave one another's sight, so a move that takes a viewer out of
////   sight is not in its scene.
//// - A cast is read as a 0x7ff, a 0x7f4 and a 0x7fe (`opcode.0x7ff`); the sight counts each
////   kind by the caster, which a 0x7f4 and a 0x7fe name through their cast id.
//// - A cast is owed a probe once it finished a settle time before the probes stopped
////   reading, as `load_respawn.needed` owes a respawn for a death.

import game_client
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/unit_death_state
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_health
import genesis_prime/message/unit_movement
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

/// What one client read of the other players: the players it is shown now, those it was
/// shown and then told were removed (and not shown again), how many 0x262 of players it
/// read, how many frames it read for a removed unit, the caster and read time of each cast it
/// was told (by cast id), how long each cast it read start to end was held (the caster and
/// the microseconds between its 0x7ff and its 0x7fe), the cast frames by message id and
/// caster, and when it read its last 0x262 of a player, in microseconds.
pub type Sight {
  Sight(
    own_unit_id: Int,
    shown: Set(Int),
    removed: Set(Int),
    creates: Int,
    after_removal: Int,
    casts: Dict(Int, Told),
    held_us: List(#(Int, Int)),
    cast_frames: Dict(#(Int, Int), Int),
    last_create_us: Option(Int),
  )
}

/// A cast the client was told: its caster and when it read the 0x7ff, in microseconds.
pub type Told {
  Told(caster: Int, started_us: Int)
}

/// A client with `own_unit_id` that has read nothing.
pub fn new(own_unit_id own_unit_id: Int) -> Sight {
  Sight(
    own_unit_id:,
    shown: set.new(),
    removed: set.new(),
    creates: 0,
    after_removal: 0,
    casts: dict.new(),
    held_us: [],
    cast_frames: dict.new(),
    last_create_us: None,
  )
}

/// The sight after the client read `frame` at `at_us`.
pub fn read(sight sight: Sight, frame frame: Frame, at_us at_us: Int) -> Sight {
  case frame.message_id {
    0x0262 -> created(sight:, frame:, at_us:)
    0x0355 -> removed(sight:, frame:)
    0x0638 -> {
      use <- bool.guard(when: set.is_empty(sight.removed), return: sight)
      let assert Ok(moved) = unit_movement.decode(frame.body)
        as "0x0638 decodes"
      named(sight:, unit_id: moved.unit_id)
    }
    0x0937 -> {
      use <- bool.guard(when: set.is_empty(sight.removed), return: sight)
      let assert Ok(health) = unit_health.decode(frame.body) as "0x0937 decodes"
      named(sight:, unit_id: health.unit_id)
    }
    0x088C -> {
      use <- bool.guard(when: set.is_empty(sight.removed), return: sight)
      let assert Ok(death) = unit_death_state.decode(frame.body)
        as "0x088C decodes"
      named(sight:, unit_id: death.unit_id)
    }
    0x07FF -> {
      let assert Ok(started) = spell_started.decode(frame.body)
        as "0x07FF decodes"
      cast_frame_of(
        sight: Sight(
          ..sight,
          casts: dict.insert(
            sight.casts,
            started.cast_id,
            Told(caster: started.caster_unit_id, started_us: at_us),
          ),
        ),
        message_id: 0x07FF,
        caster: started.caster_unit_id,
      )
    }
    0x07F4 -> {
      let assert Ok(go) = spell_go.decode(frame.body) as "0x07F4 decodes"
      cast_frame_by_cast_id(sight:, message_id: 0x07F4, cast_id: go.cast_id)
    }
    0x07FE -> {
      let assert Ok(finished) = spell_finished.decode(frame.body)
        as "0x07FE decodes"
      let sight =
        cast_frame_by_cast_id(
          sight:,
          message_id: 0x07FE,
          cast_id: finished.cast_id,
        )
      case dict.get(sight.casts, finished.cast_id) {
        Ok(Told(caster:, started_us:)) ->
          Sight(..sight, held_us: [
            #(caster, at_us - started_us),
            ..sight.held_us
          ])
        Error(Nil) -> sight
      }
    }
    _ -> sight
  }
}

/// The sight after a cast frame of `message_id` the unit `caster` cast: counted by kind and
/// caster, and a frame read after the caster's removal.
fn cast_frame_of(
  sight sight: Sight,
  message_id message_id: Int,
  caster caster: Int,
) -> Sight {
  named(
    sight: Sight(
      ..sight,
      cast_frames: dict.upsert(
        sight.cast_frames,
        #(message_id, caster),
        fn(found) { option.unwrap(found, 0) + 1 },
      ),
    ),
    unit_id: caster,
  )
}

/// The sight after a cast frame that names its cast by id, counted for the caster the
/// sight was told the cast by; a cast it was not told is counted for none.
fn cast_frame_by_cast_id(
  sight sight: Sight,
  message_id message_id: Int,
  cast_id cast_id: Int,
) -> Sight {
  case dict.get(sight.casts, cast_id) {
    Ok(Told(caster:, ..)) -> cast_frame_of(sight:, message_id:, caster:)
    Error(Nil) -> sight
  }
}

/// The sight after the client read each of `frames`, in order, at `at_us`.
pub fn read_all(
  sight sight: Sight,
  frames frames: List(Frame),
  at_us at_us: Int,
) -> Sight {
  list.fold(frames, sight, fn(sight, frame) { read(sight:, frame:, at_us:) })
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

/// The sight after a frame that names the unit `unit_id`: a frame read after the unit's
/// removal when the unit was removed and not created again.
fn named(sight sight: Sight, unit_id unit_id: Int) -> Sight {
  use <- bool.guard(when: !set.contains(sight.removed, unit_id), return: sight)
  Sight(..sight, after_removal: sight.after_removal + 1)
}

/// The 0x262 of players the clients read, each counted once while the player was shown.
pub fn players_shown(sights sights: List(Sight)) -> Int {
  list.fold(sights, 0, fn(sum, sight) { sum + sight.creates })
}

/// The removals the clients read of the players `units`: each client counts a player of
/// `units` it was shown and then told was removed.
pub fn removals_read(sights sights: List(Sight), of units: Set(Int)) -> Int {
  list.fold(sights, 0, fn(sum, sight) {
    sum + set.size(set.intersection(sight.removed, units))
  })
}

/// How long each cast of the units `casters` was held at the clients that read it start to
/// end, in microseconds: from the client's read of its 0x7ff to its read of its 0x7fe.
pub fn held_us(
  sights sights: List(Sight),
  casters casters: Set(Int),
) -> List(Int) {
  list.flat_map(sights, fn(sight) {
    list.filter_map(sight.held_us, fn(held) {
      case set.contains(casters, held.0) {
        True -> Ok(held.1)
        False -> Error(Nil)
      }
    })
  })
}

/// The frames the clients read for a unit after its removal.
pub fn frames_after_removal(sights sights: List(Sight)) -> Int {
  list.fold(sights, 0, fn(sum, sight) { sum + sight.after_removal })
}

/// The frames with `message_id` (0x07FF, 0x07F4 or 0x07FE) of the casts of the units
/// `casters` that the clients read.
pub fn cast_frames_read(
  sights sights: List(Sight),
  message_id message_id: Int,
  casters casters: Set(Int),
) -> Int {
  list.fold(sights, 0, fn(sum, sight) {
    dict.fold(sight.cast_frames, sum, fn(sum, key, count) {
      case key.0 == message_id && set.contains(casters, key.1) {
        True -> sum + count
        False -> sum
      }
    })
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
