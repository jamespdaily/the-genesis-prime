//// The ledger of what a unit holds from other units' casts
//// (`genesis_prime/game/held_changes`), run as the pure module it is. Expected values
//// come from these places.
//// - The module's doc comment: a source is held once, by the caster that started it, and
////   each release gives the sources in the order they started.
//// - The creature's failure table (`genesis_prime/world_map/creature`): the same source
////   twice is held once (`creature_test.same_source_started_twice_is_held_once_test`), and a
////   `CasterGone` takes that caster's sources alone
////   (`creature_test.a_creature_drops_the_sources_and_views_of_a_gone_caster_keeps_its_controls_sends_the_property_news_once_and_watches_only_its_run_test`).
//// - Client fact `cast.target_node_end`: a caster's removal finishes its casts, and so ends
////   their buffs on other units, unless the spell's propertyFlags hold 0x100. A source of
////   such a spell stays through its caster's `released_unseen` and goes with its unit.
//// - A caster's unit id is 100 plus its connection number in these tests, as the connection
////   tests' map gives it (`game_connection_support.viewer_unit_id`).

import genesis_prime/game/held_changes.{
  type Held, type Sight, EndsWhenUnseen, KeptWhenUnseen,
}
import genesis_prime/game/unit_casts.{
  type HeldEffect, CastView, EndsAt, HeldEffect, ViewTarget,
}
import genesis_prime/message/spell_effect_info
import genesis_prime/message/spell_target_info
import genesis_prime/shared/spell_plan
import genesis_prime/shared/unit_properties.{type Source, Source}
import genesis_prime/step.{type ConnectionId, ConnectionId}
import genesis_prime/table/id.{type Spell4Id, Spell4EffectsId, Spell4Id}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import owned_test
import qcheck

/// The source of cast `cast_id`'s first row.
fn source(cast_id cast_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(1))
}

/// The spell and the effect the tests' starts tell unless a test states them.
fn any_listing(source source: Source) -> #(Spell4Id, HeldEffect) {
  #(
    Spell4Id(54_806),
    HeldEffect(
      effect_id: source.effect_id,
      starts_ms: 0,
      ends: EndsAt(ms: 10_000),
    ),
  )
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
          spell4_id: any_listing(source: source(cast_id: start.cast_id)).0,
          effect: any_listing(source: source(cast_id: start.cast_id)).1,
          trigger: None,
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
  // What a source lists: told again by its holder (a later go of one cast) it keeps its
  // place and takes the new spell and effect; told by another connection it changes nothing.
  let first = source(cast_id: 1)
  let second = source(cast_id: 2)
  let told = fn(held, by, cast_source: Source, spell, effect) {
    held_changes.started(
      held:,
      by: ConnectionId(by),
      unit_id: 100 + by,
      source: cast_source,
      sight: EndsWhenUnseen,
      spell4_id: Spell4Id(spell),
      effect:,
      trigger: None,
    ).0
  }
  let effect_at = fn(starts, ends) {
    HeldEffect(
      effect_id: first.effect_id,
      starts_ms: starts,
      ends: EndsAt(ends),
    )
  }
  let held =
    held_changes.new()
    |> told(1, first, 100, effect_at(0, 10_000))
    |> told(1, second, 101, effect_at(0, 10_000))
  let listed = fn(held) {
    list.map(
      held_changes.cast_views(held:, holder_unit_id: 5, now_ms: 0),
      fn(view) { #(view.cast_id, view.spell4_id.value, effects_of(view:)) },
    )
  }
  assert listed(held)
    == [
      #(1, 100, [effect_at(0, 10_000)]),
      #(2, 101, [effect_at(0, 10_000)]),
    ]
    as "two sources of two casts are listed in start order"
  let again = held |> told(1, first, 200, effect_at(5000, 15_000))
  assert cast_ids(held_changes.all(held: again)) == [1, 2]
    as "a source told again keeps its place"
  assert listed(again)
    == [
      #(1, 200, [effect_at(5000, 15_000)]),
      #(2, 101, [effect_at(0, 10_000)]),
    ]
    as "and takes the new spell and the new effect"
  assert listed(held |> told(2, first, 300, effect_at(7000, 17_000)))
    == listed(held)
    as "a source told by another connection changes nothing"
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

/// A source of cast `cast_id` for the row `row`: the armor's absorb and the pool are two
/// rows of one cast.
fn row_source(cast_id cast_id: Int, row row: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(row))
}

/// A start of the source of row `row` of cast `cast_id`, held for the caster of unit
/// `unit_id` with the sight `sight`.
type HeldRow {
  HeldRow(unit_id: Int, cast_id: Int, row: Int, sight: Sight)
}

pub fn the_casts_a_player_holds_kept_from_a_caster_unit_and_whether_it_holds_a_cast_are_read_from_its_ledger_test() -> Nil {
  use <- owned_test.run(5000)
  // Rows: the sources held in start order, the sources released after, the unit asked
  // about, the kept casts of it, and the cast ids that are held with the casts asked.
  // The 0x100 rule (fact `cast.target_node_end`): only a source of a spell with
  // propertyFlags 0x100 is kept, and a cast is held while any of its sources is.
  let rows = [
    #(
      "the armor and the pool of one cast, both kept, give the cast once",
      [
        HeldRow(101, 100, 1, KeptWhenUnseen),
        HeldRow(101, 100, 2, KeptWhenUnseen),
      ],
      [],
      101,
      [100],
      [#(100, True)],
    ),
    #(
      "a source that ends with sight gives no kept cast",
      [
        HeldRow(101, 100, 1, KeptWhenUnseen),
        HeldRow(101, 101, 1, EndsWhenUnseen),
      ],
      [],
      101,
      [100],
      [#(100, True)],
    ),
    #(
      "a kept source of another unit gives nothing for this one",
      [HeldRow(102, 100, 1, KeptWhenUnseen)],
      [],
      101,
      [],
      [#(100, True)],
    ),
    #("nothing held gives no kept cast and holds no cast", [], [], 101, [], [
      #(100, False),
    ]),
    #(
      "a cast is held until its last source is released",
      [
        HeldRow(101, 100, 1, KeptWhenUnseen),
        HeldRow(101, 100, 2, KeptWhenUnseen),
      ],
      [row_source(cast_id: 100, row: 2)],
      101,
      [100],
      [#(100, True)],
    ),
    #(
      "a cast whose every source is released is not held and is no longer kept",
      [
        HeldRow(101, 100, 1, KeptWhenUnseen),
        HeldRow(101, 100, 2, KeptWhenUnseen),
      ],
      [row_source(cast_id: 100, row: 2), row_source(cast_id: 100, row: 1)],
      101,
      [],
      [#(100, False)],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, starts, releases, unit_id, kept, holding) = row
    let held =
      list.fold(starts, held_changes.new(), fn(held, start: HeldRow) {
        let #(held, _) =
          held_changes.started(
            held:,
            by: ConnectionId(start.unit_id - 100),
            unit_id: start.unit_id,
            source: row_source(cast_id: start.cast_id, row: start.row),
            sight: start.sight,
            spell4_id: any_listing(source: row_source(
              cast_id: start.cast_id,
              row: start.row,
            )).0,
            effect: any_listing(source: row_source(
              cast_id: start.cast_id,
              row: start.row,
            )).1,
            trigger: None,
          )
        held
      })
    let held =
      list.fold(releases, held, fn(held, source) {
        let assert Ok(#(held, _)) = held_changes.released(held:, source:)
        held
      })
    assert held_changes.kept_casts_of_unit(held:, unit_id:) == kept as reason
    list.each(holding, fn(asked) {
      assert held_changes.holds_cast(held:, cast_id: asked.0) == asked.1
        as reason
    })
  })
}

/// The effects of the one target of a listed cast.
fn effects_of(view view: unit_casts.CastView) -> List(HeldEffect) {
  case view.targets {
    [target] -> target.effects
    _ -> []
  }
}

/// One source a player holds for a create: the caster's connection number, the cast and the
/// Spell4Effects row, the cast's spell, and the effect as the caster's go told it.
type Listed {
  Listed(
    caster: Int,
    cast_id: Int,
    row: Int,
    spell4_id: Int,
    starts_ms: Int,
    ends_ms: Int,
  )
}

fn held_listed(listed listed: List(Listed)) -> Held {
  list.fold(listed, held_changes.new(), fn(held, one) {
    held_changes.started(
      held:,
      by: ConnectionId(one.caster),
      unit_id: 100 + one.caster,
      source: row_source(cast_id: one.cast_id, row: one.row),
      sight: KeptWhenUnseen,
      spell4_id: Spell4Id(one.spell4_id),
      effect: HeldEffect(
        effect_id: Spell4EffectsId(one.row),
        starts_ms: one.starts_ms,
        ends: EndsAt(ms: one.ends_ms),
      ),
      trigger: None,
    ).0
  })
}

/// The player that holds the changes.
const holder = 5

/// The cast a player holding the change of `caster` lists: gone (bit 0), the player its
/// primary target and its one target, one stack, not the cast bar.
fn view_of(
  caster caster: Int,
  cast_id cast_id: Int,
  spell4_id spell4_id: Int,
  effects effects: List(HeldEffect),
) -> unit_casts.CastView {
  CastView(
    caster_unit_id: 100 + caster,
    cast_id:,
    spell4_id: Spell4Id(spell4_id),
    primary_target: holder,
    gone: True,
    current: False,
    targets: [ViewTarget(unit_id: holder, count: 1, effects:)],
  )
}

fn effect_of_row(
  row row: Int,
  starts_ms starts_ms: Int,
  ends_ms ends_ms: Int,
) -> HeldEffect {
  HeldEffect(
    effect_id: Spell4EffectsId(row),
    starts_ms:,
    ends: EndsAt(ms: ends_ms),
  )
}

pub fn the_casts_a_player_holds_are_listed_for_a_create_from_its_ledger_test() -> Nil {
  use <- owned_test.run(5000)
  // Rows: the sources held in start order, the sources released after, the clock of the
  // create, and the casts listed. A cast is one view with the holder as its one target
  // (`opcode.0x262.casts`); a landed change is told at the go, so the cast has gone
  // (bit 0). A start is a monotonic time and the clock can be negative
  // (`step.Now.monotonic_ms`).
  let rows = [
    #("nothing held lists no cast", [], [], 1000, []),
    #(
      "one source lists one cast: its caster's unit, id and spell, the holder as the primary and the one target, with the source's effect",
      [Listed(3, 7, 1, 54_806, 1000, 11_000)],
      [],
      2000,
      [
        view_of(caster: 3, cast_id: 7, spell4_id: 54_806, effects: [
          effect_of_row(row: 1, starts_ms: 1000, ends_ms: 11_000),
        ]),
      ],
    ),
    #(
      "two sources of one cast list one cast with both effects in start order",
      [
        Listed(3, 7, 2, 54_806, 1000, 11_000),
        Listed(3, 7, 1, 54_806, 1000, 11_000),
      ],
      [],
      2000,
      [
        view_of(caster: 3, cast_id: 7, spell4_id: 54_806, effects: [
          effect_of_row(row: 2, starts_ms: 1000, ends_ms: 11_000),
          effect_of_row(row: 1, starts_ms: 1000, ends_ms: 11_000),
        ]),
      ],
    ),
    #(
      "two casts are listed one view each, in cast id order, whoever started first",
      [
        Listed(2, 9, 1, 76_766, 1000, 6000),
        Listed(3, 7, 1, 54_806, 1000, 11_000),
      ],
      [],
      2000,
      [
        view_of(caster: 3, cast_id: 7, spell4_id: 54_806, effects: [
          effect_of_row(row: 1, starts_ms: 1000, ends_ms: 11_000),
        ]),
        view_of(caster: 2, cast_id: 9, spell4_id: 76_766, effects: [
          effect_of_row(row: 1, starts_ms: 1000, ends_ms: 6000),
        ]),
      ],
    ),
    #(
      "a source released by its end tell is not listed, the cast's other source is",
      [
        Listed(3, 7, 1, 54_806, 1000, 11_000),
        Listed(3, 7, 2, 54_806, 1000, 11_000),
      ],
      [row_source(cast_id: 7, row: 1)],
      2000,
      [
        view_of(caster: 3, cast_id: 7, spell4_id: 54_806, effects: [
          effect_of_row(row: 2, starts_ms: 1000, ends_ms: 11_000),
        ]),
      ],
    ),
    #(
      "a change told at the go's time -5000 for 10 000 ms and listed at -2000 is listed as told: the start is a time, not a delay",
      [Listed(3, 7, 1, 54_806, -5000, 5000)],
      [],
      -2000,
      [
        view_of(caster: 3, cast_id: 7, spell4_id: 54_806, effects: [
          effect_of_row(row: 1, starts_ms: -5000, ends_ms: 5000),
        ]),
      ],
    ),
    #(
      "an effect whose end is at the create's time is not listed, and one an instant after it is",
      [
        Listed(3, 7, 1, 54_806, 1000, 11_000),
        Listed(3, 8, 1, 54_806, 1000, 11_001),
      ],
      [],
      11_000,
      [
        view_of(caster: 3, cast_id: 8, spell4_id: 54_806, effects: [
          effect_of_row(row: 1, starts_ms: 1000, ends_ms: 11_001),
        ]),
      ],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, listed, releases, now_ms, expected) = row
    let held =
      list.fold(releases, held_listed(listed:), fn(held, source) {
        let assert Ok(#(held, _)) = held_changes.released(held:, source:)
        held
      })
    assert held_changes.cast_views(held:, holder_unit_id: holder, now_ms:)
      == expected
      as reason
  })
  // A source with no caster unit (a creature's) is held but listed to nobody.
  let #(held, _) =
    held_changes.started_by_connection(
      held: held_changes.new(),
      by: ConnectionId(3),
      source: source(cast_id: 7),
    )
  assert held_changes.cast_views(held:, holder_unit_id: holder, now_ms: 0) == []
    as "a source with no caster unit is not listed"
  // What the client is told of the listed change at a negative clock and at the go's own
  // time: no delay, and the time left counted from the end (`opcode.0x7f4.effect_delay`,
  // `opcode.0x7f4.effect_time`). Read at the clock -2000 a start of 0 would be told a delay
  // of 2000.
  let held = held_listed(listed: [Listed(3, 7, 1, 54_806, -5000, 5000)])
  assert told_effects(held:, now_ms: -2000) == [#(1, 0, 7000)]
    as "a create at a negative clock tells delay 0 and the time left from the end"
  let held = held_listed(listed: [Listed(3, 7, 1, 54_806, 1000, 11_000)])
  assert told_effects(held:, now_ms: 1000) == [#(1, 0, 10_000)]
    as "a create at the go's own time tells delay 0 and the whole duration"
}

/// Each effect the one cast of the held changes tells at `now_ms`: the row, the delay and
/// the lifetime.
fn told_effects(held held: Held, now_ms now_ms: Int) -> List(#(Int, Int, Int)) {
  let assert [view] =
    held_changes.cast_views(held:, holder_unit_id: holder, now_ms:)
  let assert Ok(entry) = unit_casts.entry_of(view:, now_ms:)
  let assert [spell_target_info.SpellTargetInfo(effects:, ..)] = entry.targets
  list.map(effects, fn(effect: spell_effect_info.SpellEffectInfo) {
    #(effect.spell4_effects_id, effect.delay_ms, effect.lifetime_ms)
  })
}

/// The ally ends a cast for its viewers when the ledger's last source of it leaves (the
/// module's doc comment): a release names each cast it left with no source once, in cast id
/// order, and names nothing for a cast that still has a source.
pub fn the_casts_a_release_leaves_with_no_source_are_named_once_each_in_cast_id_order_test() -> Nil {
  use <- owned_test.run(5000)
  // Rows: the sources held in start order as (cast, row), the releases in order as lists of
  // (cast, row), and the casts each release names.
  let rows = [
    #(
      "two sources of one cast released together name the cast once",
      [#(7, 1), #(7, 2)],
      [[#(7, 1), #(7, 2)]],
      [[7]],
    ),
    #(
      "one of two sources released names nothing and the second then names the cast",
      [#(7, 1), #(7, 2)],
      [[#(7, 1)], [#(7, 2)]],
      [[], [7]],
    ),
    #(
      "sources of two casts released together name both in cast id order, not start order",
      [#(9, 1), #(3, 1), #(9, 2)],
      [[#(9, 1), #(3, 1), #(9, 2)]],
      [[3, 9]],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, sources, releases, named) = row
    let held =
      held_listed(
        listed: list.map(sources, fn(one) {
          Listed(
            caster: 3,
            cast_id: one.0,
            row: one.1,
            spell4_id: 54_806,
            starts_ms: 0,
            ends_ms: 10_000,
          )
        }),
      )
    let #(_, got) =
      list.fold(releases, #(held, []), fn(so_far, release) {
        let #(held, got) = so_far
        let released =
          list.map(release, fn(one) { row_source(cast_id: one.0, row: one.1) })
        let held =
          list.fold(released, held, fn(held, source) {
            let assert Ok(#(held, _)) = held_changes.released(held:, source:)
              as "the source is held"
            held
          })
        #(held, [held_changes.casts_left(held:, released:), ..got])
      })
    assert list.reverse(got) == named as reason
  })
}

/// A start of the cast `cast_id` by caster `caster` that waits for `trigger` (none for a
/// change the player applies), kept when its caster is unseen only when `sight` says so.
fn waiting(
  held held: Held,
  caster caster: Int,
  cast_id cast_id: Int,
  trigger trigger: option.Option(spell_plan.Trigger),
  sight sight: Sight,
) -> Held {
  held_changes.started(
    held:,
    by: ConnectionId(caster),
    unit_id: 100 + caster,
    source: source(cast_id:),
    sight:,
    spell4_id: any_listing(source: source(cast_id:)).0,
    effect: any_listing(source: source(cast_id:)).1,
    trigger:,
  ).0
}

/// What `events_awaited` answers as connection numbers with their triggers.
fn awaited(held held: Held) -> List(#(Int, List(spell_plan.Trigger))) {
  list.map(held_changes.events_awaited(held:), fn(waiting) {
    #(number_of(by: waiting.0), waiting.1)
  })
}

pub fn events_awaited_name_each_caster_that_holds_a_proc_source_once_with_the_triggers_it_waits_for_in_start_order_and_none_after_a_release_test() -> Nil {
  use <- owned_test.run(5000)
  // Caster 1 waits for TakesDamage (cast 1, kept when unseen), SuffersCritical (cast 3) and
  // TakesDamage again (cast 5); caster 2 for DeflectsAttack (cast 2, ends when unseen); caster
  // 3 holds a source it applies (cast 4) and waits for nothing. The ledger names each waiting
  // caster once in the order its first source started, with its triggers in start order, each
  // once.
  let ledger =
    held_changes.new()
    |> waiting(
      caster: 1,
      cast_id: 1,
      trigger: Some(spell_plan.TakesDamage),
      sight: KeptWhenUnseen,
    )
    |> waiting(
      caster: 2,
      cast_id: 2,
      trigger: Some(spell_plan.DeflectsAttack),
      sight: EndsWhenUnseen,
    )
    |> waiting(
      caster: 1,
      cast_id: 3,
      trigger: Some(spell_plan.SuffersCritical),
      sight: KeptWhenUnseen,
    )
    |> waiting(caster: 3, cast_id: 4, trigger: None, sight: EndsWhenUnseen)
    |> waiting(
      caster: 1,
      cast_id: 5,
      trigger: Some(spell_plan.TakesDamage),
      sight: KeptWhenUnseen,
    )
  let everyone = [
    #(1, [spell_plan.TakesDamage, spell_plan.SuffersCritical]),
    #(2, [spell_plan.DeflectsAttack]),
  ]
  assert awaited(held: ledger) == everyone
    as "each waiting caster once in the order its first source started, its triggers in start order and each once, and the caster that applies its change not at all"
  // The same source told again by its holder keeps the trigger it waits for, and told by
  // another connection changes nothing.
  let told_again =
    ledger
    |> waiting(caster: 1, cast_id: 1, trigger: None, sight: KeptWhenUnseen)
    |> waiting(
      caster: 2,
      cast_id: 1,
      trigger: Some(spell_plan.DeflectsAttack),
      sight: KeptWhenUnseen,
    )
  assert awaited(held: told_again) == everyone
    as "a source told again keeps the trigger of its first start, and another caster's start of it is refused"
  let rows = [
    #(
      "a released source is no longer awaited, and its caster keeps the others, now after caster 2 whose source started before its first remaining one",
      fn(held) {
        let assert Ok(#(held, _)) =
          held_changes.released(held:, source: source(cast_id: 1))
        held
      },
      [
        #(2, [spell_plan.DeflectsAttack]),
        #(1, [spell_plan.SuffersCritical, spell_plan.TakesDamage]),
      ],
    ),
    #(
      "the sources of a caster no longer seen that end when it is unseen are not awaited, and a source kept when unseen stays awaited",
      fn(held) {
        let #(held, _) =
          held_changes.released_unseen(held:, by: ConnectionId(2))
        held_changes.released_unseen(held:, by: ConnectionId(1)).0
      },
      [#(1, [spell_plan.TakesDamage, spell_plan.SuffersCritical])],
    ),
    #(
      "a caster's unit gone takes every source of it, kept when unseen or not",
      fn(held) { held_changes.released_with_unit(held:, unit_id: 101).0 },
      [#(2, [spell_plan.DeflectsAttack])],
    ),
    #(
      "a caster's connection ending takes every source of it",
      fn(held) { held_changes.released_by(held:, by: ConnectionId(2)).0 },
      [#(1, [spell_plan.TakesDamage, spell_plan.SuffersCritical])],
    ),
    #(
      "the holder's death starts a ledger of nothing",
      fn(_) { held_changes.new() },
      [],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, release, remaining) = row
    assert awaited(held: release(ledger)) == remaining as reason
  })
}
