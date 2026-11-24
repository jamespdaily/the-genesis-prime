//// The casts a player's client holds that the player's connection must end, and who ends
//// each: a pure record kept in `Entered`, one entry per cast id, so that a cast is in one
//// state at a time.
////
//// ```
//// caster's create or 0x7ff      ─▶ written(cast, caster's unit)      the caster's frames end it
//// an ally's create or start lists it
////                                ─▶ borrow(cast, ally's unit)         the ally's HeldCastEnded ends it
//// the caster's unit removed while the player holds a kept source
////                                ─▶ orphaned([cast])                  the player's own ledger ends it
//// the caster shown again, listing an orphaned cast
////                                ─▶ written(cast, caster's unit)      the caster's finish or the ledger's end,
////                                                                     whichever comes first
//// ```
////
//// - **A written cast** is one its caster's connection told this client the start of: the
////   caster's frames (go, tick, finish, 0x811) are written for it, and its removal finishes
////   the cast (`cast.target_node_end`: the client finishes a removed caster's casts).
//// - **A borrowed cast** is one the client holds from an ally's create (`opcode.0x262.casts`)
////   or from the start the ally tells it (`opcode.0x7ff`) without its caster telling it (`cast.unknown_caster`: the client makes a cast whose
////   caster it does not know). Only the ally ends it, with a 0x811 naming the ally
////   (`opcode.0x811`); the caster's later create, start, frames and removal write nothing for
////   it, so a cast the ally holds a kept change for does not end before the ally's last
////   source of it does. It is dropped with the last ally that listed it.
//// - **An orphaned cast** is one the client holds with no caster, because the caster's unit
////   was removed while this player held a source of the cast that outlives sight
////   (genesis_prime/game/held_changes `kept_casts_of_unit`); the player's connection writes
////   its 0x7fe when the last source ends (genesis_prime/game/connection/landing). When the
////   caster is shown again and lists the cast, it is written too, and the first end forgets
////   it.
//// - A cast listed by an ally that the client holds already, written or orphaned, stays as it
////   is: its own ender is exact, and a second ender would end it twice.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set.{type Set}

/// Who ends a cast the client holds.
type Hold {
  /// Its caster's frames end it; the caster is the unit `caster_unit_id`.
  Written(caster_unit_id: Int)
  /// The player's own ledger ends it.
  Orphaned
  /// An orphaned cast its caster, the unit `caster_unit_id`, listed again: the caster's
  /// frames or the ledger's last source end it, whichever comes first.
  Relisted(caster_unit_id: Int)
  /// The units in `allies` listed it and end it for the client, one 0x811 each.
  Borrowed(allies: Set(Int))
}

/// The casts a client holds, by cast id.
pub opaque type Casts {
  Casts(holds: Dict(Int, Hold))
}

/// A client that holds none.
pub fn new() -> Casts {
  Casts(holds: dict.new())
}

/// The cast `cast_id` of the unit `caster_unit_id`, whose start was written to the client
/// by the caster's own frames. A cast an ally listed stays borrowed.
pub fn written(
  casts casts: Casts,
  cast_id cast_id: Int,
  caster_unit_id caster_unit_id: Int,
) -> Casts {
  let hold = case dict.get(casts.holds, cast_id) {
    Ok(Borrowed(..) as hold) -> hold
    Ok(Orphaned) | Ok(Relisted(..)) -> Relisted(caster_unit_id:)
    Ok(Written(..)) | Error(Nil) -> Written(caster_unit_id:)
  }
  Casts(holds: dict.insert(casts.holds, cast_id, hold))
}

/// The cast `cast_id` as the create of the unit `ally_unit_id` listed it, or as the start it
/// told. A cast the client holds from its caster or with none stays as it is.
pub fn borrow(
  casts casts: Casts,
  cast_id cast_id: Int,
  ally_unit_id ally_unit_id: Int,
) -> Casts {
  let allies = case dict.get(casts.holds, cast_id) {
    Ok(Written(..)) | Ok(Orphaned) | Ok(Relisted(..)) -> Error(Nil)
    Ok(Borrowed(allies:)) -> Ok(set.insert(allies, ally_unit_id))
    Error(Nil) -> Ok(set.from_list([ally_unit_id]))
  }
  case allies {
    Ok(allies) ->
      Casts(holds: dict.insert(casts.holds, cast_id, Borrowed(allies:)))
    Error(Nil) -> casts
  }
}

/// Whether the cast's caster told the client its start, so that the caster's frames end it.
pub fn is_written(casts casts: Casts, cast_id cast_id: Int) -> Bool {
  case dict.get(casts.holds, cast_id) {
    Ok(Written(..)) | Ok(Relisted(..)) -> True
    Ok(Orphaned) | Ok(Borrowed(..)) | Error(Nil) -> False
  }
}

/// Whether the client holds the cast in any state: written by its caster, borrowed from an
/// ally, held with no caster or listed again by its caster. A cast the client holds is not
/// started again (`opcode.0x7ff`: a cast id already live restarts that cast).
pub fn is_held(casts casts: Casts, cast_id cast_id: Int) -> Bool {
  dict.has_key(casts.holds, cast_id)
}

/// Whether the client holds the cast from an ally's create or start.
pub fn is_borrowed(casts casts: Casts, cast_id cast_id: Int) -> Bool {
  case dict.get(casts.holds, cast_id) {
    Ok(Borrowed(..)) -> True
    Ok(Written(..)) | Ok(Orphaned) | Ok(Relisted(..)) | Error(Nil) -> False
  }
}

/// The cast `cast_id` forgotten, once its caster's frames have ended it.
pub fn finished(casts casts: Casts, cast_id cast_id: Int) -> Casts {
  case dict.get(casts.holds, cast_id) {
    Ok(Written(..)) | Ok(Relisted(..)) ->
      Casts(holds: dict.delete(casts.holds, cast_id))
    Ok(Orphaned) | Ok(Borrowed(..)) | Error(Nil) -> casts
  }
}

/// The cast ids of the unit `unit_id`'s written casts, in cast id order.
pub fn written_of_unit(casts casts: Casts, unit_id unit_id: Int) -> List(Int) {
  dict.to_list(casts.holds)
  |> list.filter_map(fn(held) {
    case held.1 {
      Written(caster_unit_id:)
        | Relisted(caster_unit_id:)
        if caster_unit_id == unit_id
      -> Ok(held.0)
      Written(..) | Relisted(..) | Orphaned | Borrowed(..) -> Error(Nil)
    }
  })
  |> list.sort(int.compare)
}

/// The unit `unit_id` no longer shown: the casts it wrote are forgotten, except an orphaned
/// cast it listed again, which is held with no caster as before; it no longer holds the
/// casts it listed (the client destroys the nodes on a removed unit, and a cast left with no
/// target), and a cast that no ally lists any more is forgotten.
pub fn unit_forgotten(casts casts: Casts, unit_id unit_id: Int) -> Casts {
  Casts(
    holds: dict.fold(casts.holds, casts.holds, fn(holds, cast_id, hold) {
      case hold {
        Written(caster_unit_id:) if caster_unit_id == unit_id ->
          dict.delete(holds, cast_id)
        Relisted(caster_unit_id:) if caster_unit_id == unit_id ->
          dict.insert(holds, cast_id, Orphaned)
        Borrowed(allies:) ->
          case set.delete(allies, unit_id) {
            left if left == allies -> holds
            left ->
              case set.is_empty(left) {
                True -> dict.delete(holds, cast_id)
                False -> dict.insert(holds, cast_id, Borrowed(allies: left))
              }
          }
        Written(..) | Relisted(..) | Orphaned -> holds
      }
    }),
  )
}

/// The casts `cast_ids` marked as held with no caster.
pub fn orphaned(casts casts: Casts, cast_ids cast_ids: List(Int)) -> Casts {
  Casts(
    holds: list.fold(cast_ids, casts.holds, fn(holds, cast_id) {
      dict.insert(holds, cast_id, Orphaned)
    }),
  )
}

/// The cast ids held with no caster, listed again by their caster or not, in cast id order.
pub fn orphans(casts casts: Casts) -> List(Int) {
  dict.to_list(casts.holds)
  |> list.filter_map(fn(held) {
    case held.1 {
      Orphaned | Relisted(..) -> Ok(held.0)
      Written(..) | Borrowed(..) -> Error(Nil)
    }
  })
  |> list.sort(int.compare)
}

/// The orphaned casts `cast_ids` forgotten, once the client has been written their end.
pub fn orphans_ended(
  casts casts: Casts,
  cast_ids cast_ids: List(Int),
) -> Casts {
  Casts(
    holds: list.fold(cast_ids, casts.holds, fn(holds, cast_id) {
      case dict.get(holds, cast_id) {
        Ok(Orphaned) | Ok(Relisted(..)) -> dict.delete(holds, cast_id)
        Ok(Written(..)) | Ok(Borrowed(..)) | Error(Nil) -> holds
      }
    }),
  )
}

/// The cast `cast_id` ended on the ally `ally_unit_id`, which listed it to the client: the
/// ally is no longer held for it, and the cast is forgotten with the last. `Error` when the
/// client did not borrow the cast from that ally, so no 0x811 is owed.
pub fn ally_ended(
  casts casts: Casts,
  cast_id cast_id: Int,
  ally_unit_id ally_unit_id: Int,
) -> Result(Casts, Nil) {
  case dict.get(casts.holds, cast_id) {
    Ok(Borrowed(allies:)) ->
      case set.contains(allies, ally_unit_id) {
        False -> Error(Nil)
        True -> {
          let left = set.delete(allies, ally_unit_id)
          case set.is_empty(left) {
            True -> Ok(Casts(holds: dict.delete(casts.holds, cast_id)))
            False ->
              Ok(
                Casts(holds: dict.insert(
                  casts.holds,
                  cast_id,
                  Borrowed(allies: left),
                )),
              )
          }
        }
      }
    Ok(Written(..)) | Ok(Orphaned) | Ok(Relisted(..)) | Error(Nil) -> Error(Nil)
  }
}
