//// The casts a player's client holds (`genesis_prime/game/client_casts`), as a pure record:
//// a cast its caster's frames finished is kept as an ended hold, so the viewer's own ledger
//// answers for the cast id until the unit is forgotten.

import genesis_prime/game/client_casts.{type Casts}
import gleam/int
import gleam/list
import owned_test

const cast_id = 5

const caster = 7

const ally = 9

/// The monotonic time the finishes of these rows are made at, and how long a finish holds the id.
const finish_ms = 1000

const hold_ms = 5000

/// What the record answers for the cast `cast_id` and the units `caster` and `ally`.
type Held {
  Held(
    is_held: Bool,
    is_written: Bool,
    is_borrowed: Bool,
    written_of_caster: List(Int),
    orphans: List(Int),
    ended_by_ally: Bool,
  )
}

fn held_of(casts casts: Casts) -> Held {
  Held(
    is_held: client_casts.is_held(casts:, cast_id:, now_ms: finish_ms),
    is_written: client_casts.is_written(casts:, cast_id:),
    is_borrowed: client_casts.is_borrowed(casts:, cast_id:),
    written_of_caster: client_casts.written_of_unit(casts:, unit_id: caster),
    orphans: client_casts.orphans(casts:),
    ended_by_ally: case
      client_casts.ally_ended(casts:, cast_id:, ally_unit_id: ally)
    {
      Ok(_) -> True
      Error(Nil) -> False
    },
  )
}

fn finish(casts casts: Casts, cast_id cast_id: Int) -> Casts {
  client_casts.finished(casts:, cast_id:, now_ms: finish_ms, hold_ms:)
}

fn written() -> Casts {
  client_casts.written(
    casts: client_casts.new(),
    cast_id:,
    caster_unit_id: caster,
  )
}

/// A cast its caster's frames finished is an ended hold: held, so that no start of the id is
/// taken for a new cast and no ally's start is written; not written, so that no frame of the
/// caster is written for it again; skipped by the caster's written casts, the orphans and an
/// ally's end. A new start of the id, a create that lists it as an ally's, or the caster's
/// removal replaces or deletes it.
pub fn a_finished_written_cast_is_an_ended_hold_that_counts_for_is_held_not_for_is_written_and_a_new_start_or_a_create_replaces_it_and_the_forgotten_unit_deletes_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let ended = finish(casts: written(), cast_id:)
  let rows = [
    #("written", written(), Held(True, True, False, [cast_id], [], False)),
    #(
      "finished: an ended hold, held and not written, skipped by the three",
      ended,
      Held(True, False, False, [], [], False),
    ),
    #(
      "a cast held with no caster and listed again by its caster, then finished: an ended hold too",
      finish(
        casts: client_casts.written(
          casts: client_casts.orphaned(casts: client_casts.new(), cast_ids: [
            cast_id,
          ]),
          cast_id:,
          caster_unit_id: caster,
        ),
        cast_id:,
      ),
      Held(True, False, False, [], [], False),
    ),
    #(
      "a new start of the reused id replaces the ended hold",
      client_casts.written(casts: ended, cast_id:, caster_unit_id: caster),
      Held(True, True, False, [cast_id], [], False),
    ),
    #(
      "a create that lists the id as an ally's replaces it by a borrowed cast",
      client_casts.borrow(casts: ended, cast_id:, ally_unit_id: ally),
      Held(True, False, True, [], [], True),
    ),
    #(
      "the caster's removal deletes it",
      client_casts.unit_forgotten(casts: ended, unit_id: caster),
      Held(False, False, False, [], [], False),
    ),
    #(
      "another unit's removal leaves it",
      client_casts.unit_forgotten(casts: ended, unit_id: ally),
      Held(True, False, False, [], [], False),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, casts, expected) = row
    assert held_of(casts:) == expected as reason
  })
}

/// An ally's start can be late only while that ally waits on an ask, so an ended hold lasts
/// the connection's longest ask deadline after the finish and no longer: held until then,
/// not at it, and a later finish of any cast forgets the holds that have run out, so a caster
/// that finishes many casts in sight leaves none older than the deadline.
pub fn an_ended_hold_lasts_the_longest_ask_deadline_after_the_finish_and_each_finish_forgets_the_older_ones_test() -> Nil {
  use <- owned_test.run(10_000)
  let ended = finish(casts: written(), cast_id:)
  let held_at = fn(now_ms) {
    client_casts.is_held(casts: ended, cast_id:, now_ms:)
  }
  assert held_at(finish_ms + hold_ms - 1)
    as "one millisecond before the deadline the late start is still dropped"
  assert !held_at(finish_ms + hold_ms)
    as "at the deadline the id is free for a new cast"
  let ids =
    int.range(from: 1, to: 51, with: [], run: fn(ids, id) { [id, ..ids] })
  let many =
    list.fold(list.reverse(ids), client_casts.new(), fn(casts, id) {
      client_casts.finished(
        casts: client_casts.written(casts:, cast_id: id, caster_unit_id: caster),
        cast_id: id,
        now_ms: id * 1000,
        hold_ms:,
      )
    })
  let last_ms = 50 * 1000
  let kept =
    list.filter(ids, fn(id) {
      client_casts.is_held(casts: many, cast_id: id, now_ms: 0)
    })
  assert list.all(kept, fn(id) { id * 1000 + hold_ms > last_ms })
    as "no ended hold is left that the deadline has passed since its finish"
  assert list.contains(kept, 50) as "the latest finish is held"
}
