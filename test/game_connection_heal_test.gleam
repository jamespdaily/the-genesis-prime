//// A Medic's heals on the game connection (`genesis_prime/game/connection`), on the
//// client's tables: Energize's shield heal and a health heal, each with the go's heal
//// description, the vital that rises when the heal lands and what its viewers are told.
//// Expected values come from these places.
//// - Spell4Effects 99912 (added here, a copy of 66766 on Paralytic Surge): a type 10 Heal
////   aimed at the caster, 20 ms after the go, whose formula is the caster's level times 40.
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
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/message/damage_type
import genesis_prime/message/player_health
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import genesis_prime/table/loader/store as store_tables
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table
import spawn_support
import unitest

/// A creature's blow of `damage` on the player, before its armor and shield.
fn a_strike_of(
  damage damage: Int,
) -> step.Event(
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
          damage:,
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
            unit_stat_change.InterruptArmor(..)
            | unit_stat_change.Absorption(..)
            | unit_stat_change.Level(..) -> Error(Nil)
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
    connection_support.feed(state:, event: a_strike_of(damage: 1000))
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
  let told = list.flat_map(landed, fn(taken) { told_to_the_viewer(taken:) })
  assert list.count(told, fn(news) {
      news == client_connection.Shield(shield: expected)
    })
    == 1
    as "and the same shield is told to the viewer, once (beside the properties the go's type 11 rows start)"
}

/// The healths the step's 0x92f frames carry, in order.
fn healths(taken taken: ConnectionStep(Request)) -> List(Int) {
  connection_support.decoded(
    connection_support.heard(taken, connection_support.keyed()),
    player_health.message_id,
    player_health.decode,
  )
  |> list.map(fn(told) { told.health })
}

/// The steps of the timers the press started that are the cast's own (numbers from 1000),
/// each fired in order on the state the one before left.
fn fired_after(
  state state: game_connection.State,
  pressed pressed: ConnectionStep(Request),
) -> List(ConnectionStep(Request)) {
  let timers =
    list.filter(support.timers_started(pressed), fn(timer) {
      let step.TimerId(number) = timer
      number >= 1000
    })
  list.fold(timers, #(state, []), fn(so_far, timer) {
    let #(state, taken) = so_far
    let #(state, more) =
      connection_support.feed(state:, event: OwnEvent(TimerFired(timer)))
    #(state, list.append(taken, [more]))
  })
  |> fn(done) { done.1 }
}

/// The heal description amounts and overheals the step's 0x7f4 frames carry for
/// Spell4Effects 99912, with the damage type of each.
fn described_health_heals(
  taken taken: ConnectionStep(Request),
) -> List(#(damage_type.DamageType, Int, Int)) {
  list.filter(
    connection_support.heard(taken, connection_support.keyed()),
    fn(frame) { frame.message_id == spell_go.message_id },
  )
  |> list.flat_map(fn(frame) {
    let assert Ok(go) = spell_go.decode(frame.body) as "a go decodes"
    list.flat_map(go.targets, fn(target) { target.effects })
  })
  |> list.filter(fn(effect) { effect.spell4_effects_id == 99_912 })
  |> list.map(fn(effect) {
    let assert spell_effect_result.Damage(shown) = effect.result
      as "the heal is listed with a damage description"
    #(
      shown.description.damage_type,
      shown.description.health_damage_with_overkill,
      shown.description.overkill,
    )
  })
}

/// Paralytic Surge (Spell4 42352, bag index 2 of a Medic) with one added row: a type 10
/// Heal aimed at the caster, 20 ms after the go, whose formula is the caster's level
/// (parameter kind 10, `Spell4Effects.effectType.10`: ComputeEffectValue 0x140565600
/// reads kind 10 as the unit's level) times 40, so a level-1 Medic heals 40. Kept edit: no
/// level-1 ability holds a type 10 row.
fn with_the_heal(body body: fn(store_tables.Tables) -> a) -> a {
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 66_766,
    id: 99_912,
    with: [
      #("spellId", planted_table.Integer(42_352)),
      #("targetFlags", planted_table.Integer(1)),
      #("effectType", planted_table.Integer(10)),
      #("damageType", planted_table.Integer(0)),
      #("delayTime", planted_table.Integer(20)),
      #("tickTime", planted_table.Integer(0)),
      #("durationTime", planted_table.Integer(0)),
      #("flags", planted_table.Integer(0)),
      #("dataBits00", planted_table.Integer(1_065_353_216)),
      #("dataBits01", planted_table.Integer(0)),
      #("dataBits02", planted_table.Integer(0)),
      #("dataBits03", planted_table.Integer(0)),
      #("dataBits04", planted_table.Integer(0)),
      #("dataBits05", planted_table.Integer(0)),
      #("dataBits06", planted_table.Integer(0)),
      #("dataBits07", planted_table.Integer(0)),
      #("dataBits08", planted_table.Integer(0)),
      #("dataBits09", planted_table.Integer(0)),
      #("innateCostPerTickType0", planted_table.Integer(0)),
      #("innateCostPerTickType1", planted_table.Integer(0)),
      #("innateCostPerTick0", planted_table.Integer(0)),
      #("innateCostPerTick1", planted_table.Integer(0)),
      #("emmComparison", planted_table.Integer(0)),
      #("emmValue", planted_table.Integer(0)),
      #("spell4EffectGroupListId", planted_table.Integer(0)),
      #("prerequisiteIdCasterApply", planted_table.Integer(0)),
      #("prerequisiteIdTargetApply", planted_table.Integer(0)),
      #("prerequisiteIdCasterPersistence", planted_table.Integer(0)),
      #("prerequisiteIdTargetPersistence", planted_table.Integer(0)),
      #("prerequisiteIdTargetSuspend", planted_table.Integer(0)),
      #("parameterType00", planted_table.Integer(10)),
      #("parameterType01", planted_table.Integer(0)),
      #("parameterType02", planted_table.Integer(0)),
      #("parameterType03", planted_table.Integer(0)),
      #("parameterValue00", planted_table.Float(40.0)),
      #("parameterValue01", planted_table.Float(0.0)),
      #("parameterValue02", planted_table.Float(0.0)),
      #("parameterValue03", planted_table.Float(0.0)),
      #("phaseFlags", planted_table.Integer(-1)),
      #("orderIndex", planted_table.Integer(2)),
    ],
    body:,
  )
}

pub fn pressing_a_heal_sends_the_go_then_the_new_health_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_the_heal
  let state =
    connection_support.watched_by(
      connection_support.medic_with_beast_in_world(tables),
      [2],
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, struck) =
    connection_support.feed(state:, event: a_strike_of(damage: 1000))
  let assert [before] = healths(taken: struck)
    as "the blow lowers the health: one 0x92f"
  let #(state, pressed) =
    connection_support.press_paralytic_surge(state:, client_cast_id: 1)
  let assert [#(40, key)] = connection_support.strikes_told(pressed)
    as "the press strikes the Beast and its round is open: the go waits for the answer"
  let #(state, pressed) =
    connection_support.feed(state:, event: connection_support.landed(key:))
  assert described_health_heals(taken: pressed) == [#(damage_type.Heal, 40, 0)]
    as "the go lists row 99912 as a Heal of 40 (kind 10 x 40 at level 1), no overheal while the health is below its maximum"
  assert healths(taken: pressed) == []
    as "the health has not risen yet: the heal lands 20 ms after the go"
  let landed = fired_after(state:, pressed:)
  assert list.flat_map(landed, fn(taken) { healths(taken:) }) == [before + 40]
    as "the health rises by 40: one 0x92f to the Medic"
  let told = list.flat_map(landed, fn(taken) { told_to_the_viewer(taken:) })
  assert list.count(told, fn(news) {
      news == client_connection.Health(health: before + 40, dead: False)
    })
    == 1
    as "and the viewer is told the same health once (0x937)"
  // The same press, but the player leaves the world (a camp's save) before the heal's
  // timer fires: nothing is written.
  let #(gone, _) =
    connection_support.read(
      state:,
      bytes: connection_support.camp_request_message(True),
    )
  let #(gone, _) =
    connection_support.read(
      state: gone,
      bytes: connection_support.camp_finished_message(),
    )
  let after_leaving = fired_after(state: gone, pressed:)
  assert list.flat_map(after_leaving, fn(taken) { healths(taken:) }) == []
    as "with no player in the world the change is dropped"
}
