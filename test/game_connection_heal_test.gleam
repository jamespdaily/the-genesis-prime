//// A Medic's Energize on the game connection (`genesis_prime/game/connection`), on the
//// client's tables: the go's heal description, the shield that rises when the heal lands
//// and what its viewers are told. Expected values come from these places.
//// - Spell4Effects 228914 (`table_rows -- Spell4Effects spellId=69450`): 0.3 of the
////   missing shield, aimed at the caster, 10 ms after the go.
//// - `Spell4Effects.effectType.118`: the client shows the go's description and never
////   changes the shield, so the server sends the new shield as stat 20 of 0x938
////   (`opcode.0x938`): to the Medic's client and, as the `Shield` news, to each viewer.
//// - `player.level1_gear_properties`: a level-1 Medic's ShieldCapacityMax is 450.
//// Skipped where the client's tables are not on the machine.

import cast_support
import client_tables
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/strike_tell
import genesis_prime/message/damage_type
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import gleam/list
import gleam/option.{None}
import owned_test
import spawn_support
import unitest

/// A creature's blow of 1000 on the player, whatever its armor leaves of it.
fn a_heavy_strike() -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  connection_support.foe(
    strike_tell.Attacks(
      tell: strike_tell.Strike(
        key: strike_tell.Key(
          cast_id: 2_147_500_000,
          phase: 0,
          unit_id: connection_support.own_unit_id,
        ),
        from: connection_support.fighter(),
        striker: strike_tell.CreatureStriker,
        offence: spawn_support.dealing(
          offence: spawn_support.beast_attack().offence,
          damage: 1000,
        ),
        controls: [],
      ),
    ),
  )
}

/// The shields the step's 0x938 frames carry, in order.
fn shields(taken taken: ConnectionStep(Request)) -> List(Int) {
  list.filter_map(
    connection_support.heard(taken, connection_support.keyed()),
    fn(frame: Frame) {
      case frame.message_id == 0x0938 {
        True -> {
          let assert Ok(changed) = unit_stat_changed.decode(frame.body)
            as "a 0x938 decodes"
          case changed.change {
            unit_stat_change.Shield(UnitStatShield(value:)) -> Ok(value)
            unit_stat_change.InterruptArmor(..) -> Error(Nil)
          }
        }
        False -> Error(Nil)
      }
    },
  )
}

/// The news the viewer 2 is told in the step, in order.
fn told_to_the_viewer(
  taken taken: ConnectionStep(Request),
) -> List(client_connection.News) {
  list.filter_map(connection_support.peer_tells(taken), fn(tell) {
    case tell.0 == 2 {
      True -> Ok({ tell.1 }.news)
      False -> Error(Nil)
    }
  })
}

/// The heal description amount the step's 0x7f4 frames carry for Spell4Effects 228914.
fn described_heals(taken taken: ConnectionStep(Request)) -> List(Int) {
  list.filter(
    connection_support.heard(taken, connection_support.keyed()),
    fn(frame) { frame.message_id == spell_go.message_id },
  )
  |> list.flat_map(fn(frame) {
    let assert Ok(go) = spell_go.decode(frame.body) as "a go decodes"
    list.flat_map(go.targets, fn(target) { target.effects })
  })
  |> list.filter(fn(effect) { effect.spell4_effects_id == 228_914 })
  |> list.map(fn(effect) {
    let assert spell_effect_result.Damage(shown) = effect.result
      as "the heal is listed with a damage description"
    assert shown.description.damage_type == damage_type.HealShields
    shown.description.health_damage_with_overkill
  })
}

pub fn a_struck_medic_pressing_energize_sees_the_heal_and_its_shield_rise_and_so_do_its_viewers_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, _) =
    connection_support.entered_on_the_clients_tables(
      class_id: 4,
      saved_health: None,
    )
  let state = connection_support.watched_by(state:, viewers: [2])
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, struck) =
    connection_support.feed(state:, event: a_heavy_strike())
  let assert [shield] = shields(taken: struck)
    as "the blow lowers the shield: one 0x938"
  assert shield < 450 as "from the 450 of a level-1 Medic"
  // round(0.3 x missing) for a whole missing shield, half up: (3 x missing + 5) / 10.
  let amount = { 3 * { 450 - shield } + 5 } / 10
  let #(state, pressed) =
    connection_support.read(
      state:,
      bytes: connection_support.world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id: 1,
          bag_index: 3,
          target: 0,
          press: 1,
        ),
      ),
    )
  assert described_heals(taken: pressed) == [amount]
    as "Spell4Effects 228914: the go's description carries round(0.3 x (450 - shield))"
  assert shields(taken: pressed) == []
    as "the shield has not risen yet: the heal lands 10 ms after the go"
  let timers =
    list.filter(support.timers_started(pressed), fn(timer) {
      let step.TimerId(number) = timer
      number >= 1000
    })
  let #(_, landed) =
    list.fold(timers, #(state, []), fn(so_far, timer) {
      let #(state, taken) = so_far
      let #(state, more) =
        connection_support.feed(state:, event: OwnEvent(TimerFired(timer)))
      #(state, list.append(taken, [more]))
    })
  let healed = list.flat_map(landed, fn(taken) { shields(taken:) })
  let expected = case shield + amount > 450 {
    True -> 450
    False -> shield + amount
  }
  assert healed == [expected]
    as "the shield rises by the amount, capped at 450: one 0x938 to the Medic"
  assert list.flat_map(landed, fn(taken) { told_to_the_viewer(taken:) })
    == [client_connection.Shield(shield: expected)]
    as "and the same shield is told to the viewer"
}
