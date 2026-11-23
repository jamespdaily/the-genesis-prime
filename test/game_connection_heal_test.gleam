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
//// - Mental Boon (Spell4 33257, SpellLevel 1049, an Esper's at level 18; text 245408, "every
////   0.5s"): its cost of 1 Psi Point of every point held picks the Proxies whose tag is the
////   points spent above the cost. The client's text starts the Esper's Psi Points empty
////   (`class_resource`), so the test earns 3 with three Telekinetic Strikes first.
//// The Medic's tests are skipped where the client's tables are not on the machine.

import cast_support
import client_tables
import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/effect_kind
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_result
import genesis_prime/message/damage_type
import genesis_prime/message/float32
import genesis_prime/message/player_health
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/unit_float_stat_changed
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, OwnEvent, TimerFired,
}
import genesis_prime/table/loader/store as store_tables
import genesis_prime/world_map/map
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table
import spawn_support
import spell_tables
import unitest
import world_entry_support

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
          occasion: strike_tell.AtGo(phase: 0),
          unit_id: connection_support.own_unit_id,
        ),
        from: connection_support.fighter(),
        striker: spawn_support.beast_striker(),
        offence: spawn_support.dealing(
          offence: spawn_support.beast_attack().offence,
          damage:,
        ),
        controls: [],
        gates: [],
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

/// The 0x935s a step writes, decoded.
fn resource_changes(
  taken taken: ConnectionStep(Request),
) -> List(unit_float_stat_changed.UnitFloatStatChanged) {
  list.filter_map(connection_support.written(taken:), fn(frame) {
    case frame.message_id == unit_float_stat_changed.message_id {
      True -> {
        let assert Ok(changed) = unit_float_stat_changed.decode(frame.body)
          as "0x935 decodes"
        Ok(changed)
      }
      False -> Error(Nil)
    }
  })
}

pub fn an_esper_pressing_mental_boon_is_healed_every_500_ms_by_the_tier_its_psi_points_choose_test() -> Nil {
  use <- owned_test.run(120_000)
  // Text 245408: Mental Boon heals "every 0.5s". The Esper (Class 3) earns 3 Psi Points
  // from three Telekinetic Strikes that each hit the Beast (Spell4 32893 gives +1 on a go
  // that struck a foe), and Mental Boon's cost (Spell4 33257's innate cost of type 6)
  // spends every point held, which picks the Proxy of Spell4Effects 76774 (emmValue 2,
  // tickTime 500, durationTime 6000): twelve ticks, each a heal of row 76784.
  let tables = fixture_tables.shared()
  let character =
    world_entry_support.character(class: 3, faction: 166, level: 18)
  let #(_, entered) = world_entry_support.entry(tables:, character:)
  let held = casting.caster_of(tables:, entered:)
  let ticks = 12
  let tick_ms = 500
  // The amount of each heal, which the cast rule works out from the Esper's stats, at the
  // cast layer; the times of the ticks are the client's (500 ms from the go).
  let #(_, steps) =
    cast_support.pressed_and_run(
      spell: spell_tables.client_spell(spell4_id: 33_257),
      caster: cast_state.Caster(
        ..cast_support.hurt(
          caster: cast_support.caster_holding(resources: cast_support.holding(
            class_id: 3,
            value: 3.0,
          )),
        ),
        stats: held.stats,
        heal_scaling: held.heal_scaling,
        player: held.player,
      ),
      press_ms: 1000,
      until_ms: 8000,
    )
  let heals =
    list.flat_map(steps, fn(step) {
      list.filter_map(
        cast_support.caster_change_starts(effects: step.1),
        fn(start) {
          case { start.0 }.effect_id.value, start.1 {
            76_784, cast_state.Heal(vital: effect_kind.Health, amount:) ->
              Ok(amount)
            _, cast_state.Heal(..)
            | _, cast_state.Property(..)
            | _, cast_state.Absorb(..)
            | _, cast_state.Look(..)
            -> Error(Nil)
          }
        },
      )
    })
  let assert [heal, ..] = heals
    as "the rule heals the Esper by row 76784 at each tick"
  assert list.length(heals) == ticks
    && list.all(heals, fn(amount) { amount == heal })
    as "twelve heals of row 76784, each of the same amount"
  assert heal > 0 && 1 + ticks * heal < held.vitals.max_health
    as "the Esper's health, 1 at entry, stays below its maximum through all twelve heals, so every one raises it whole and the count of rises is exact"
  // The connection: the Esper enters empty of Psi Points with the Beast before it.
  let settings = Settings(..connection_support.settings(), tables:)
  let #(state, _) =
    connection_support.entered_at_level(
      settings:,
      class_id: 3,
      level: 18,
      saved_health: Some(1),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.beast_appears(unit_id: 40),
    )
  let bag_index_of = fn(ability) {
    connection_support.bag_index_of(tables:, class_id: 3, level: 18, ability:)
  }
  // Telekinetic Strike is Spell4Base 19102: a bar of 1250 ms (castTime) and the go strikes
  // the Beast. Each is pressed after the one before has gone.
  let #(state, strikes) =
    list.fold([1000, 3000, 5000], #(state, []), fn(so_far, ms) {
      let #(state, done) = so_far
      let #(state, steps) =
        connection_support.pressed_until(
          state:,
          bag_index: bag_index_of(19_102),
          client_cast_id: ms,
          ms:,
          until_ms: ms + 1900,
        )
      #(state, list.append(done, steps))
    })
  assert list.any(
    list.flat_map(strikes, fn(taken) { resource_changes(taken:) }),
    fn(change) { change.stat_id == 3 && change.value == float32.to_bits(3.0) },
  )
    as "opcode.0x935: the third strike raises the Psi Points (slot 1, stat 3) to 3"
  let press_ms = 6500
  let #(state, pressed) =
    connection_support.at(
      state:,
      ms: press_ms,
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id: 1,
            bag_index: bag_index_of(19_258),
            target: 0,
            press: 1,
          ),
        )),
      ),
    )
  let ids = connection_support.written_ids(pressed)
  assert list.contains(ids, 0x07FD) && list.contains(ids, 0x07F4)
    as "opcode.0x7fd, opcode.0x7f4: the client hears the press confirmed and the go of the cast"
  assert connection_support.refusal_results(taken: pressed) == []
    as "the press is accepted: the Esper holds the Psi Points and the Focus"
  let changes = resource_changes(taken: pressed)
  assert list.any(changes, fn(change) {
    change.stat_id == 3 && change.value == float32.to_bits(0.0)
  })
    as "opcode.0x935: the Psi Points (slot 1, stat 3) are spent to 0"
  assert list.any(changes, fn(change) { change.stat_id == 1 })
    as "opcode.0x935: the Focus the cost asks is paid (stat 1)"
  assert healths(taken: pressed) == []
    as "no health rises at the press: the first tick is 500 ms on"
  // The heals land at each tick of the clock, driven in steps of one tick: tick k at
  // 500 ms times k after the go.
  let #(_, _, risen) =
    list.fold(
      list.repeat(Nil, ticks) |> list.index_map(fn(_, index) { index + 1 }),
      #(
        state,
        connection_support.cast_timers(steps: [pressed], ms: press_ms),
        1,
      ),
      fn(so_far, tick) {
        let #(state, pending, health) = so_far
        let at_ms = press_ms + tick * tick_ms
        let #(state, pending, before) =
          connection_support.casts_left(
            state:,
            pending:,
            until_ms: at_ms - 1,
            steps: [],
          )
        assert list.flat_map(before, fn(taken) { healths(taken:) }) == []
          as "no health rises before the tick, 500 ms after the one before"
        let #(state, pending, at) =
          connection_support.casts_left(
            state:,
            pending:,
            until_ms: at_ms,
            steps: [],
          )
        assert list.flat_map(at, fn(taken) { healths(taken:) })
          == [health + heal]
          as "opcode.0x92f: the tick raises the health by the heal of the 3-point tier"
        #(state, pending, health + heal)
      },
    )
  assert risen == 1 + ticks * heal
    as "twelve rises in all, from the 1 health the Esper entered with"
}

/// The primary target each 0x7fd and each 0x7ff the step writes names: the 0x7fds first.
fn primary_targets(taken taken: ConnectionStep(Request)) -> List(Int) {
  let frames = connection_support.heard(taken, connection_support.keyed())
  list.append(
    connection_support.decoded(
      frames,
      spell_cast_confirmed.message_id,
      spell_cast_confirmed.decode,
    )
      |> list.map(fn(confirmed) { confirmed.primary_target_unit_id }),
    connection_support.decoded(
      frames,
      spell_started.message_id,
      spell_started.decode,
    )
      |> list.map(fn(started) { started.primary_target_unit_id }),
  )
}

pub fn a_press_at_a_player_the_map_showed_starts_the_cast_on_that_player_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Mind Over Body (Spell4Base 19030, an Esper's at level 6) is the Targeted kind
  // (Spell4TargetMechanics row 4). The other player is the unit 9 that the map's SeenBy of
  // connection 3 names and that connection's 0x262 creates in the picture.
  let tables = client_tables.shared()
  let settings = Settings(..connection_support.settings(), tables:)
  let #(state, _) =
    connection_support.entered_at_level(
      settings:,
      class_id: 3,
      level: 6,
      saved_health: None,
    )
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_030,
    )
  let press = fn(state, ms, target) {
    connection_support.at(
      state:,
      ms:,
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id: ms,
            bag_index:,
            target:,
            press: 1,
          ),
        )),
      ),
    )
  }
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(map.SeenBy(
        by: ConnectionId(3),
        stay: connection_support.viewer_stay(3),
        unit_id: 9,
      )),
    )
  let #(state, early) = press(state, 1000, 9)
  assert list.map(
      connection_support.refusal_results(taken: early),
      cast_result.to_value,
    )
    == [91]
    as "the picture does not show the unit 9 yet: the map's notice alone is no unit the client holds"
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.event_of(connection_support.Appears),
    )
  let #(state, pressed) = press(state, 2000, 9)
  assert connection_support.refusal_results(taken: pressed) == []
    as "the press at the other player is accepted"
  assert primary_targets(taken: pressed) == [9]
    as "opcode.0x9a: the caster's client takes the primary target from the 0x7fd, which names the other player (the caster is sent no 0x7ff, opcode.0x7ff.after_confirm)"
  assert list.map(
      connection_support.cast_starts(connection_support.news_told(
        taken: pressed,
        viewer: 3,
      )),
      fn(started) { started.primary_target_unit_id },
    )
    == [9]
    as "opcode.0x7ff: the other player's client is told the cast and takes the cast's primary target from the 0x7ff, which names that player (Unit.GetBuffs reads it)"
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(
        map.UnseenBy(by: ConnectionId(3)),
      ),
    )
  let #(_, unseen) = press(state, 30_000, 9)
  assert list.map(
      connection_support.refusal_results(taken: unseen),
      cast_result.to_value,
    )
    == [91]
    as "the map told the connection the player no longer sees it: the unit has no address, so the press is refused 91"
}
