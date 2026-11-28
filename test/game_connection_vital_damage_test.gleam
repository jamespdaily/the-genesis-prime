//// A player's damage whose formula names the caster's own vitals, on the game connection
//// (`genesis_prime/game/connection/casting`): the strike reads the player's health as it
//// stands when the go or the tick asks for it, not as it stood when the cast began.
//// Expected values come from these places.
//// - Spell4Effects 96125 (`table_rows -- Spell4Effects 96125`): Paralytic Surge's damage
////   row, aimed at the area (targetFlags 4), dataBits00 1065353216 (0x3f800000, a
////   multiplier of 1.0) and dataBits01 0. Kept edits: its three parameters become one,
////   type 23 at 0.5, so its value is 0.5 times the caster's health; and, for the go test,
////   the spell's castTime (Spell4 42352, 0) becomes 1500, so a blow can land between the
////   press and the go.
//// - `0x140566ad0`: formula parameter type 23 is the caster's current health and
////   `0x140565600` works the value as multiplier x (stat part + (base + sum) x dataBits00),
////   rounded to a whole number as the stat part is (`0x140566d40`). A level-1 Medic's
////   health the client shows is the 0x92f the blow writes (`opcode.0x92f`), so the
////   expected values are taken from the health the client was told.

import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/map/message as map_message
import genesis_prime/shared/hit.{Worked}
import genesis_prime/shared/strike_tell
import genesis_prime/step.{type ConnectionStep, OwnEffect}
import genesis_prime/table/loader/store as store_tables
import gleam/float
import gleam/int
import gleam/list
import owned_test
import planted_table.{Float, Integer}

/// Paralytic Surge's damage row, whose parameters are one: 0.5 of the caster's health
/// (type 23), as a periodic row of `ticks` ticks a second apart when `ticks` is more than
/// 0. The spell casts for `cast_ms`.
fn with_the_surge_reading_health(
  cast_ms cast_ms: Int,
  ticks ticks: Int,
  body body: fn(store_tables.Tables) -> a,
) -> a {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4",
      id: 42_352,
      with: [#("castTime", Integer(cast_ms))],
    )
    as "the fixture holds Spell4 42352"
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "Spell4Effects", id: 96_125, with: [
      #("parameterType00", Integer(23)),
      #("parameterType01", Integer(0)),
      #("parameterType02", Integer(0)),
      #("parameterValue00", Float(0.5)),
      #("parameterValue01", Float(0.0)),
      #("parameterValue02", Float(0.0)),
      #(
        "tickTime",
        Integer(case ticks > 0 {
          True -> 1000
          False -> 0
        }),
      ),
      #("durationTime", Integer(1000 * ticks)),
    ])
    as "the fixture holds Spell4Effects 96125"
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// The Medic of these tables in the world with the Beast, unit 40, in front of it, in a
/// fight (a creature's threat), and the health the client was first shown.
fn medic_in_a_fight(
  tables tables: store_tables.Tables,
) -> game_connection.State {
  connection_support.feed(
    state: connection_support.medic_with_beast_in_world(tables),
    event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
  ).0
}

/// The amount of each blow the steps tell the creatures, in order.
fn amounts_told(
  steps steps: List(ConnectionStep(Request)),
) -> List(hit.Amount) {
  list.flat_map(steps, fn(taken) {
    list.flat_map(support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(step.Tell(
          request: client_connection.TellCreature(
            payload: map_message.Strike(tell:),
            ..,
          ),
          ..,
        )) -> list.map(tell.offence.blows, fn(blow) { blow.damage })
        OwnEffect(_)
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | step.Stop -> []
      }
    })
  })
}

/// Half of a health, rounded as the client rounds a stat part.
fn half_of(health health: Int) -> Int {
  float.round(0.5 *. int.to_float(health))
}

pub fn the_go_reads_the_casters_health_as_it_is_at_the_go_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_the_surge_reading_health(cast_ms: 1500, ticks: 0)
  let state = medic_in_a_fight(tables:)
  // The press at 1000 ms starts a cast of 1500 ms: its go is due at 2500 ms.
  let #(state, pressed) =
    connection_support.press_paralytic_surge_at(
      state:,
      client_cast_id: 1,
      ms: 1000,
    )
  assert amounts_told(steps: [pressed]) == []
    as "the cast has a time, so the press strikes nobody: the go is the strike"
  let timers = connection_support.cast_timers(steps: [pressed], ms: 1000)
  // A creature's blow of 1000 lands at 1500 ms, during the cast: it is more than the
  // shield holds, so the health falls.
  let #(state, struck) =
    connection_support.at(
      state:,
      ms: 1500,
      event: connection_support.a_creatures_blow(
        unit_id: connection_support.own_unit_id,
        damage_type: 3,
        damage: 1000,
      ),
    )
  let assert [after_the_blow] = connection_support.healths(taken: struck)
    as "the blow lowers the health: one 0x92f tells the client the new value"
  let #(_, steps) =
    connection_support.casts_run(
      state:,
      pending: timers,
      until_ms: 2500,
      steps: [],
    )
  assert amounts_told(steps:) == [Worked(half_of(health: after_the_blow))]
    as "the go's blow is 0.5 x the health the client was told at 1500 ms, not the health the cast began with"
}

pub fn a_tick_reads_the_casters_vitals_at_that_tick_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_the_surge_reading_health(cast_ms: 0, ticks: 3)
  let state = medic_in_a_fight(tables:)
  let #(state, pressed) =
    connection_support.press_paralytic_surge_at(
      state:,
      client_cast_id: 1,
      ms: 1000,
    )
  // The press strikes the Beast with no blow of its own (the row is periodic), and the
  // Beast answers that it landed, which arms the ticks, a second apart.
  let #(state, go) =
    connection_support.landing(state:, ms: 1000, taken: pressed)
  let timers = connection_support.cast_timers(steps: go, ms: 1000)
  // The first tick is due at 2000 ms.
  let #(state, timers, first) =
    connection_support.casts_left(
      state:,
      pending: timers,
      until_ms: 2000,
      steps: [],
    )
  let assert [first_amount, ..] = amounts_told(steps: first)
    as "the first tick strikes the Beast"
  // A creature's blow of 1000 lands at 2100 ms, between the first tick and the second.
  let #(state, struck) =
    connection_support.at(
      state:,
      ms: 2100,
      event: connection_support.a_creatures_blow(
        unit_id: connection_support.own_unit_id,
        damage_type: 3,
        damage: 1000,
      ),
    )
  let assert [after_the_blow] = connection_support.healths(taken: struck)
    as "the blow lowers the health: one 0x92f"
  let #(_, rest) =
    connection_support.casts_run(
      state:,
      pending: timers,
      until_ms: 5000,
      steps: [],
    )
  let later = amounts_told(steps: rest)
  assert list.first(later) == Ok(Worked(half_of(health: after_the_blow)))
    as "the next tick reads the health as it stands at that tick: 0.5 x the health the client was told at 2100 ms"
  assert list.all(later, fn(amount) { amount != first_amount })
    as "no later tick repeats the first tick's value, which was worked from the full health"
}
