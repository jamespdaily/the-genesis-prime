//// An Esper's Spectral Form on the game connection (`genesis_prime/game/connection`), on
//// the client's tables: the Interrupt Armor its child gives, what the player's client
//// and its viewers are told, and what a viewer that arrives while it holds is created
//// with. Expected values come from these places.
//// - Spell4Effects 199192 (`table_rows -- Spell4Effects spellId=76766`): +1 Interrupt
////   Armor for 5000 ms, dataBits01 0, aimed at the primary target of 76766, which
////   Proxy 178143 of Spectral Form (58586) starts on the caster; the client refuses
////   Spectral Form out of combat (Prerequisite 903, `Spell4.58586`).
//// - `opcode.0x938.interrupt_armor`: stat 21 is the current armor, which the client
////   clamps to 0 and the unit's maximum (UnitProperty2 44, default 0.0) when a 0x938
////   arrives, and the create's stat list sets it; so the maximum (0x93a, `opcode.0x93a`)
////   is sent before the armor rises and the armor before the maximum falls.
//// - `opcode.0x93a.other_unit` and `opcode.0x938`: a viewer is told the same entries
////   as the unit's owner, as the news `PropertiesChanged` and `InterruptArmor`.
//// - `Class` row 3 is the Esper (`game_connection_innate_test`).
//// Skipped where the client's tables are not on the machine.

import client_tables
import game_connection_support as support
import genesis_prime/client_connection.{
  type News, type Request, InterruptArmor, PropertiesChanged,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/message/float32
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_interrupt_armor.{UnitStatInterruptArmor}
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/option.{None}
import owned_test
import unitest

/// Property 44 as a 0x93a entry: its base and value as 32-bit floats.
fn property_44(base base: Float, value value: Float) -> UnitProperty {
  UnitProperty(
    property_id: 44,
    base: float32.to_bits(base),
    value: float32.to_bits(value),
  )
}

/// The player's own armor writes among a step's frames, in order: each 0x93a entry of
/// property 44 as the entry and each 0x938 of stat 21 as the armor.
type Written {
  Maximum(entry: UnitProperty)
  Armor(value: Int)
}

fn written(taken taken: ConnectionStep(Request)) -> List(Written) {
  list.flat_map(support.heard(taken, support.keyed()), written_by)
}

/// What one frame writes of the armor.
fn written_by(frame frame: Frame) -> List(Written) {
  case frame.message_id {
    0x093A -> {
      let assert Ok(changed) = unit_properties_changed.decode(frame.body)
        as "a 0x93a decodes"
      list.filter(changed.properties, fn(entry) { entry.property_id == 44 })
      |> list.map(fn(entry) { Maximum(entry:) })
    }
    0x0938 -> {
      let assert Ok(changed) = unit_stat_changed.decode(frame.body)
        as "a 0x938 decodes"
      armor_of(change: changed.change)
    }
    _ -> []
  }
}

/// The armor a 0x938 carries, none for another stat.
fn armor_of(change change: unit_stat_change.UnitStatChange) -> List(Written) {
  case change {
    unit_stat_change.InterruptArmor(UnitStatInterruptArmor(value:)) -> [
      Armor(value:),
    ]
    unit_stat_change.Shield(..) | unit_stat_change.Absorption(..) -> []
  }
}

/// The news the viewer 2 is told in a step, in order.
fn told_to_the_viewer(taken taken: ConnectionStep(Request)) -> List(News) {
  list.filter_map(support.peer_tells(taken), fn(tell) {
    case tell.0 == 2 {
      True -> Ok({ tell.1 }.news)
      False -> Error(Nil)
    }
  })
}

/// The armor news among what a viewer is told: the maximum's entry and the armor.
fn armor_news(steps steps: List(ConnectionStep(Request))) -> List(News) {
  list.flat_map(steps, fn(taken) { told_to_the_viewer(taken:) })
  |> list.filter(fn(news) {
    list.contains(
      [
        PropertiesChanged(properties: [property_44(base: 0.0, value: 1.0)]),
        PropertiesChanged(properties: [property_44(base: 0.0, value: 0.0)]),
        InterruptArmor(armor: 1),
        InterruptArmor(armor: 0),
      ],
      news,
    )
  })
}

/// An Esper in the world, in a fight (Spectral Form asks for one), watched by viewer 2.
fn esper_in_a_fight() -> game_connection.State {
  let #(state, _) =
    support.entered_on_the_clients_tables(class_id: 3, saved_health: None)
  let state = support.watched_by(state:, viewers: [2])
  let #(state, _) =
    support.feed(
      state:,
      event: support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  state
}

/// The Esper's innate, at bag index 3, pressed at 1000 ms, and the cast timers it
/// leads to up to `until_ms`.
fn spectral_form_until(
  state state: game_connection.State,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  support.pressed_until(
    state:,
    bag_index: 3,
    client_cast_id: 1,
    ms: 1000,
    until_ms:,
  )
}

pub fn an_esper_pressing_spectral_form_shows_one_interrupt_armor_for_five_seconds_to_itself_and_its_viewers_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let state = esper_in_a_fight()
  // The child's armor starts in the press's own millisecond or just after it and ends
  // 5000 ms later: nothing has ended by 5900 ms, everything has by 20000.
  let #(_, early) = spectral_form_until(state:, until_ms: 5900)
  assert list.flat_map(early, fn(taken) { written(taken:) })
    == [Maximum(entry: property_44(base: 0.0, value: 1.0)), Armor(value: 1)]
    as "0x93a {44, 0, 1} then 0x938 stat 21 = 1: the maximum first, which the client's clamp needs"
  assert armor_news(steps: early)
    == [
      PropertiesChanged(properties: [property_44(base: 0.0, value: 1.0)]),
      InterruptArmor(armor: 1),
    ]
    as "a viewer gets the same two in the same order"
  let #(_, whole) = spectral_form_until(state:, until_ms: 20_000)
  assert list.flat_map(whole, fn(taken) { written(taken:) })
    == [
      Maximum(entry: property_44(base: 0.0, value: 1.0)),
      Armor(value: 1),
      Armor(value: 0),
      Maximum(entry: property_44(base: 0.0, value: 0.0)),
    ]
    as "after 5000 ms 0x938 stat 21 = 0 then 0x93a {44, 0, 0}: the armor first, then the maximum"
  assert armor_news(steps: whole)
    == [
      PropertiesChanged(properties: [property_44(base: 0.0, value: 1.0)]),
      InterruptArmor(armor: 1),
      InterruptArmor(armor: 0),
      PropertiesChanged(properties: [property_44(base: 0.0, value: 0.0)]),
    ]
    as "and the viewer gets the same four in the same order"
}

pub fn a_viewer_arriving_while_the_armor_holds_is_created_with_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(holding, _) =
    spectral_form_until(state: esper_in_a_fight(), until_ms: 5900)
  let created = support.created_for(state: holding, viewer: 4)
  assert unit_fields.stat(tail: created.tail, stat_id: 21) == Ok(1)
    as "stat 21 is listed while the armor is above 0 (opcode.0x938.interrupt_armor: the create's stat list sets it)"
  assert list.find(created.tail.properties, fn(property) {
      property.property_id == 44
    })
    == Ok(property_44(base: 0.0, value: 1.0))
    as "and property 44 is at the maximum the armor needs, which the client holds as sent"
  // Once it has ended the next viewer is created with neither.
  let #(ended, _) =
    spectral_form_until(state: esper_in_a_fight(), until_ms: 20_000)
  let later = support.created_for(state: ended, viewer: 5)
  assert unit_fields.stat(tail: later.tail, stat_id: 21) == Error(Nil)
    as "no armor, no stat 21"
}
