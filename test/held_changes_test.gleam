//// The ledger of what a unit holds from other units' casts
//// (`genesis_prime/game/held_changes`), run as the pure module it is. Expected values
//// come from these places.
//// - The module's doc comment: a source is held once, by the caster that started it, and
////   each release gives the sources in the order they started.
//// - The creature's failure table (`genesis_prime/world_map/creature`): the same source
////   twice is held once (`creature_test.same_source_started_twice_is_held_once_test`), and a
////   caster's connection ending takes that caster's sources alone
////   (`creature_test.caster_connection_end_removes_its_modifiers_test`).
//// - Client fact `cast.target_node_end`: a caster's removal finishes its casts, and so ends
////   their buffs on other units, unless the spell's propertyFlags hold 0x100. A source of
////   such a spell stays through its caster's `released_unseen` and goes with its unit.
//// - A caster's unit id is 100 plus its connection number in these tests, as the connection
////   tests' map gives it (`game_connection_support.viewer_unit_id`).

import genesis_prime/game/held_changes.{
  type Held, type Sight, EndsWhenUnseen, KeptWhenUnseen,
}
import genesis_prime/game/unit_properties.{type Source, Source}
import genesis_prime/step.{type ConnectionId, ConnectionId}
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/list
import gleam/result
import owned_test
import qcheck

/// The source of cast `cast_id`'s first row.
fn source(cast_id cast_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(1))
}

/// A start: the caster's connection number, how its spell keeps its change, and the cast.
type Start {
  Start(caster: Int, sight: Sight, cast_id: Int)
}

fn held_after(starts starts: List(Start)) -> #(Held, List(Bool)) {
  let #(held, flags) =
    list.fold(starts, #(held_changes.new(), []), fn(so_far, start) {
      let #(held, flags) = so_far
      let #(held, started) =
        held_changes.started(
          held:,
          by: ConnectionId(start.caster),
          unit_id: 100 + start.caster,
          source: source(cast_id: start.cast_id),
          sight: start.sight,
        )
      #(held, [started, ..flags])
    })
  #(held, list.reverse(flags))
}

fn cast_ids(sources: List(Source)) -> List(Int) {
  list.map(sources, fn(source) { source.cast_id })
}

fn number_of(by by: ConnectionId) -> Int {
  let ConnectionId(number) = by
  number
}

fn connection_numbers(held held: Held) -> List(Int) {
  list.map(held_changes.connections(held:), fn(by) { number_of(by:) })
}

pub fn a_source_started_twice_is_held_once_and_each_casters_sources_keep_their_start_order_test() -> Nil {
  use <- owned_test.run(5000)
  // starts, the flag each start returns, every source held, and the holder of cast 1.
  let rows = [
    #(
      "a source started twice by one caster is held once",
      [Start(1, EndsWhenUnseen, 1), Start(1, EndsWhenUnseen, 1)],
      [True, False],
      [1],
      Ok(1),
    ),
    #(
      "two casters starting interleaved keep the order of the starts",
      [
        Start(1, EndsWhenUnseen, 1),
        Start(2, EndsWhenUnseen, 2),
        Start(1, EndsWhenUnseen, 3),
      ],
      [True, True, True],
      [1, 2, 3],
      Ok(1),
    ),
    #(
      "the same source started by a second caster is refused and the first holder stays",
      [Start(1, EndsWhenUnseen, 1), Start(2, EndsWhenUnseen, 1)],
      [True, False],
      [1],
      Ok(1),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, starts, flags, all, holder) = row
    let #(held, started) = held_after(starts:)
    assert started == flags as reason
    assert cast_ids(held_changes.all(held:)) == all as reason
    assert result.map(
        held_changes.holder_of(held:, source: source(cast_id: 1)),
        fn(by) { number_of(by:) },
      )
      == holder
      as reason
  })
}

pub fn ending_a_source_gives_the_caster_that_held_it_and_a_source_not_held_gives_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let starts = [
    Start(1, EndsWhenUnseen, 1),
    Start(2, EndsWhenUnseen, 2),
    Start(1, EndsWhenUnseen, 3),
  ]
  // The sources released one after the other, the caster each release gives, and what
  // is held after them.
  let rows = [
    #("a held source gives its holder", [1], [Ok(1)], [2, 3]),
    #("a second release of it gives nothing", [1, 1], [Ok(1), Error(Nil)], [
      2,
      3,
    ]),
    #("a source never started gives nothing", [9], [Error(Nil)], [1, 2, 3]),
    #(
      "releasing one source leaves the same caster's other source and the other caster's",
      [2],
      [Ok(2)],
      [1, 3],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, releases, givens, remaining) = row
    let #(held, _) = held_after(starts:)
    let #(held, given) =
      list.fold(releases, #(held, []), fn(so_far, cast_id) {
        let #(held, given) = so_far
        case held_changes.released(held:, source: source(cast_id:)) {
          Ok(#(held, by)) -> #(held, [Ok(number_of(by:)), ..given])
          Error(Nil) -> #(held, [Error(Nil), ..given])
        }
      })
    assert list.reverse(given) == givens as reason
    assert cast_ids(held_changes.all(held:)) == remaining as reason
  })
}

/// How a row of `ending_every_source_of_a_caster_takes_that_casters_alone_in_start_order_test`
/// releases.
type Release {
  By(caster: Int)
  Unseen(caster: Int)
  WithUnit(unit_id: Int)
}

pub fn ending_every_source_of_a_caster_takes_that_casters_alone_in_start_order_test() -> Nil {
  use <- owned_test.run(5000)
  let starts = [
    Start(1, EndsWhenUnseen, 1),
    Start(2, KeptWhenUnseen, 2),
    Start(1, KeptWhenUnseen, 3),
    Start(1, EndsWhenUnseen, 4),
  ]
  // The release, the sources it takes, the sources still held and the casters that still
  // hold one.
  let rows = [
    #(
      "a caster's connection ending takes every source of it, whatever its spell keeps",
      By(1),
      [1, 3, 4],
      [2],
      [2],
    ),
    #("a caster that holds nothing takes nothing", By(9), [], [1, 2, 3, 4], [
      1,
      2,
    ]),
    #(
      "a caster out of sight takes the sources that end with sight and keeps the other",
      Unseen(1),
      [1, 4],
      [2, 3],
      [2, 1],
    ),
    #(
      "a caster out of sight whose sources all outlive sight takes none",
      Unseen(2),
      [],
      [1, 2, 3, 4],
      [1, 2],
    ),
    #(
      "a caster's unit gone takes every source of it, the ones that outlive sight too",
      WithUnit(unit_id: 101),
      [1, 3, 4],
      [2],
      [2],
    ),
    #(
      "a unit no caster owns takes nothing",
      WithUnit(unit_id: 150),
      [],
      [1, 2, 3, 4],
      [1, 2],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, release, taken, remaining, casters) = row
    let #(held, _) = held_after(starts:)
    let #(held, given) = case release {
      By(caster:) -> held_changes.released_by(held:, by: ConnectionId(caster))
      Unseen(caster:) ->
        held_changes.released_unseen(held:, by: ConnectionId(caster))
      WithUnit(unit_id:) -> held_changes.released_with_unit(held:, unit_id:)
    }
    assert cast_ids(given) == taken as reason
    assert cast_ids(held_changes.all(held:)) == remaining as reason
    assert connection_numbers(held:) == casters as reason
  })
}

/// A release, as a number the property draws: 0 a caster's connection ending, 1 a caster out
/// of sight, 2 a caster's unit gone.
fn released_as(
  held held: Held,
  kind kind: Int,
  caster caster: Int,
) -> #(Held, List(Source)) {
  case kind {
    0 -> held_changes.released_by(held:, by: ConnectionId(caster))
    1 -> held_changes.released_unseen(held:, by: ConnectionId(caster))
    _ -> held_changes.released_with_unit(held:, unit_id: 100 + caster)
  }
}

pub fn a_source_is_held_once_by_its_first_caster_and_every_release_takes_that_casters_sources_in_start_order_and_loses_none_test() -> Nil {
  use <- owned_test.run(10_000)
  // The module's doc comment: a source is held once, by the caster that started it first, and
  // a release gives the sources in the order they started. The model below is that sentence:
  // the first start of each cast id, in start order, with its caster and how it keeps.
  qcheck.given(
    qcheck.tuple3(
      qcheck.list_from(qcheck.tuple3(
        qcheck.bounded_int(from: 1, to: 3),
        qcheck.bool(),
        qcheck.bounded_int(from: 1, to: 6),
      )),
      qcheck.bounded_int(from: 0, to: 2),
      qcheck.bounded_int(from: 1, to: 3),
    ),
    fn(drawn) {
      let #(drawn_starts, kind, caster) = drawn
      let starts =
        list.map(drawn_starts, fn(start) {
          let #(by, kept, cast_id) = start
          Start(
            by,
            case kept {
              True -> KeptWhenUnseen
              False -> EndsWhenUnseen
            },
            cast_id,
          )
        })
      let #(held, flags) = held_after(starts:)
      let model =
        list.fold(starts, [], fn(first_starts: List(Start), start: Start) {
          case
            list.any(first_starts, fn(first: Start) {
              first.cast_id == start.cast_id
            })
          {
            True -> first_starts
            False -> list.append(first_starts, [start])
          }
        })
      assert cast_ids(held_changes.all(held:))
        == list.map(model, fn(start: Start) { start.cast_id })
        as "each source is held once, in the order of its first start"
      assert list.count(flags, fn(started) { started }) == list.length(model)
        as "a start is new exactly once for each source"
      let #(after, taken) = released_as(held:, kind:, caster:)
      let taken_by_the_model =
        list.filter(model, fn(start: Start) {
          start.caster == caster
          && case kind {
            1 -> start.sight == EndsWhenUnseen
            _ -> True
          }
        })
        |> list.map(fn(start) { start.cast_id })
      assert cast_ids(taken) == taken_by_the_model
        as "a release takes the sources of its caster that it ends, in start order"
      assert cast_ids(held_changes.all(held: after))
        == list.filter(
          list.map(model, fn(start: Start) { start.cast_id }),
          fn(cast_id) { !list.contains(taken_by_the_model, cast_id) },
        )
        as "and keeps every other source, in start order"
    },
  )
}
