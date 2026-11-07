//// The Scale (18) and UnitPropertyConversion (145) rows on the game connection
//// (`genesis_prime/game/connection`), on the client's tables. Expected values come from
//// these places:
//// - `Spell4Effects` rows of 42908 (`table_rows -- Spell4Effects spellId=42908`): 109482 is
////   a Scale row aimed at the caster (targetFlags 1) for 8000 ms, which Onslaught's Proxy
////   127637 starts, so a level-1 Warrior's press of Onslaught (46867, the innate at bag
////   index 3) writes 42908's 0x7f4 with it in the caster's target info
////   (`Spell4Effects.effectType.18`: the client grows the unit when the go names the
////   effect on it).
//// - The viewers' rule (`genesis_prime/game/connection/viewers`): a viewer writes the go
////   of a cast whose start it wrote, the same SpellGo the caster's client got.
//// - `Spell4Effects` rows of 45000: 229304 converts property 47 into property 60 at 0.25
////   until removed (`table_rows -- Spell4Effects spellId=45000`), `UnitProperty2` 47's
////   default is 0.0 and no type 11 row of the level-1 trees changes 47
////   (`Spell4Effects.effectType.145`), so a level-1 Engineer holds 0 of property 47 and the
////   conversion adds 0: no 0x93a for property 60 (`opcode.0x93a`).
//// Skipped where the client's tables are not on the machine.

import cast_support
import client_tables
import connection_rule_support
import game_connection_support as support
import genesis_prime/client_connection.{type Request, CastStarted, CastWent}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/spell_go.{type SpellGo}
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/message/unit_properties_changed
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import gleam/list
import gleam/option.{None}
import owned_test
import unitest

/// A press of the bag index, as the client sends it.
fn pressed(
  state state: game_connection.State,
  bag_index bag_index: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.read(
    state:,
    bytes: support.world_message(
      message_id: 0x009A,
      body: cast_support.press_body(
        client_cast_id: 1,
        bag_index:,
        target: 0,
        press: 1,
      ),
    ),
  )
}

/// The timers a step starts for casts: the cast rule's ids begin at 1000.
fn cast_timers_started(
  taken taken: ConnectionStep(Request),
) -> List(step.TimerId) {
  list.filter(connection_rule_support.timers_started(taken), fn(timer) {
    let step.TimerId(number) = timer
    number >= 1000
  })
}

/// The gos of a press's frames, in order.
fn gos_in(frames frames: List(Frame)) -> List(SpellGo) {
  support.decoded(frames, spell_go.message_id, spell_go.decode)
}

/// The Spell4Effects ids a go lists on the unit.
fn listed_on(go go: SpellGo, unit_id unit_id: Int) -> List(Int) {
  list.filter(go.targets, fn(target) { target.unit_id == unit_id })
  |> list.flat_map(fn(target) {
    list.map(target.effects, fn(effect) { effect.spell4_effects_id })
  })
}

pub fn a_warriors_onslaught_press_writes_42908s_go_with_the_scale_row_and_a_viewer_gets_the_same_go_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, _) =
    support.entered_on_the_clients_tables(class_id: 1, saved_health: None)
  let state = support.watched_by(state:, viewers: [2])
  let #(state, press) = pressed(state:, bag_index: 3)
  // Proxy 127637 of 46867 starts 42908 after its delayTime of 1 ms, a timer of the cast
  // rule (`table_rows -- Spell4Effects spellId=46867`).
  let assert [timer] = cast_timers_started(taken: press)
    as "the one cast timer the press starts: the Proxy's delay"
  let #(_, taken) = support.feed(state:, event: OwnEvent(TimerFired(timer)))
  let frames = support.written(taken:)
  let assert [go] =
    list.filter(gos_in(frames:), fn(go) {
      list.contains(listed_on(go:, unit_id: support.own_unit_id), 109_482)
    })
    as "one go lists the Scale row 109482 on the caster's unit: Spell4Effects 109482 is aimed at the caster (42908)"
  // The viewer: it is told the start of the cast, then the go, and writes the same go.
  let assert [start] =
    list.filter(
      support.decoded(frames, spell_started.message_id, spell_started.decode),
      fn(start) { start.cast_id == go.cast_id },
    )
    as "the caster's client reads the start of the cast that went"
  let told = support.news_told(taken:, viewer: 2)
  assert list.contains(told, CastStarted(start:))
    as "each viewer is told the start of the cast"
  assert list.contains(told, CastWent(go:)) as "and the same go"
  let viewer =
    support.feed(support.in_world(), support.event_of(support.Appears)).0
  let #(viewer, _) = feed_started(viewer:, start:)
  let #(_, seen) =
    support.feed(
      viewer,
      support.sent_by_a_peer(support.news_of(unit_id: 9, news: CastWent(go:))),
    )
  let assert [seen_go] =
    support.decoded(
      support.heard(seen, support.keyed()),
      spell_go.message_id,
      spell_go.decode,
    )
    as "the viewer writes the go of a cast whose start it wrote"
  assert listed_on(go: seen_go, unit_id: support.own_unit_id)
    == listed_on(go:, unit_id: support.own_unit_id)
  assert seen_go == go as "the viewer's 0x7f4 is the caster's"
}

fn feed_started(
  viewer viewer: game_connection.State,
  start start: SpellStarted,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.feed(
    viewer,
    support.sent_by_a_peer(support.news_of(
      unit_id: 9,
      news: CastStarted(start:),
    )),
  )
}

pub fn an_engineers_entry_starts_the_passive_with_its_conversion_and_writes_no_0x93a_for_property_60_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(_, taken) =
    support.entered_on_the_clients_tables(class_id: 2, saved_health: None)
  let frames = support.written(taken:)
  assert list.any(gos_in(frames:), fn(go) {
    list.contains(listed_on(go:, unit_id: support.own_unit_id), 229_304)
  })
    as "the passive 45000's go lists 229304 on the caster"
  let properties =
    support.decoded(frames, 0x093A, unit_properties_changed.decode)
    |> list.flat_map(fn(message: unit_properties_changed.UnitPropertiesChanged) {
      message.properties
    })
  assert list.filter(properties, fn(entry) { entry.property_id == 60 }) == []
    as "UnitProperty2 47 holds 0.0 and no row changes it, so the conversion adds 0 and property 60 does not move"
}
