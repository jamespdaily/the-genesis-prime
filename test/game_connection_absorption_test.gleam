//// A player's absorb pool on the game connection (`genesis_prime/game/connection/absorption`,
//// `casting`, `viewers`, `frames`): Spectral Form's Absorption row gives the player a pool
//// for 5000 ms, its client and each viewer's are written stat 22 of 0x938 at the start,
//// after each blow the pool soaks and at the end, and a viewer that first sees the player
//// while it holds is created with it. Expected values come from these places.
//// - Spell4Effects 178144 (`table_rows -- Spell4Effects spellId=58586`): Spectral Form's
////   Absorption row, aimed at the caster, 5000 ms, mask 7, Assault Power x 2.531 and
////   Support Power x 2.531, which a level-1 Novice (Assault Rating 203.0625, Support Rating
////   55.6875, `player.level1_gear_properties`) works out as round(163.72) = 164.
//// - `opcode.0x938` and `0x14064fb40`: stat 22 is the unit's absorption, in 5 bits and
////   32; the client's create of a unit sets it from stat 22 of its 0x262 (`opcode.0x262`
////   tail stats).
//// - `Spell4Effects.effectType.29`: the part of each blow the pool soaks is in the
////   damage description's absorbed field, beside the mitigated part, and the pool falls by
////   what it soaked.
//// - A level-1 Esper's Armor 150 mitigates 0.5996959 of a blow (`player_life_test`:
////   GameFormula 1234, `0x140464240`): a blow of 300 is 120 after mitigation (300 x
////   0.4003041 = 120.09), all of which the pool of 164 takes, leaving 44; the description's
////   absorbed is the 180 mitigated and the 120 soaked, 300, and the shield and the health
////   are untouched.
//// - **The Esper's own Spectral Form runs each owner-side test** on the fixture's rows
////   (`support.settings()`): the innate of the Esper, Spell4 58586, at bag index 3.

import game_connection_support as support
import genesis_prime/client_connection.{type Request, Absorption}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/message/unit_stat_absorption.{UnitStatAbsorption}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/option.{None}
import owned_test

/// A player in the world, in a fight, watched by the viewers 2 and 3, and the bag index of
/// the ability that gives it the pool.
type World {
  World(state: game_connection.State, bag_index: Int)
}

/// An Esper on the fixture's rows, whose Spectral Form is at bag index 3 and asks for a
/// fight (Prerequisite 903, `Spell4.58586`).
fn esper_world() -> World {
  let #(state, _) =
    support.entered_with(
      settings: support.settings(),
      class_id: 3,
      saved_health: None,
    )
  World(
    state: in_a_fight(state: support.watched_by(state:, viewers: [2, 3])),
    bag_index: 3,
  )
}

fn in_a_fight(state state: game_connection.State) -> game_connection.State {
  support.feed(
    state:,
    event: support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
  ).0
}

/// The ability pressed at 1000 ms and the cast timers up to `until_ms`.
fn pooled_until(
  world world: World,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  support.pressed_until(
    state: world.state,
    bag_index: world.bag_index,
    client_cast_id: 1,
    ms: 1000,
    until_ms:,
  )
}

/// The absorption each 0x938 of stat 22 the steps write to the player's client carries,
/// in order.
fn written(steps steps: List(ConnectionStep(Request))) -> List(Int) {
  list.flat_map(steps, fn(taken) {
    support.decoded(
      support.heard(taken, support.keyed()),
      0x0938,
      unit_stat_changed.decode,
    )
  })
  |> list.filter_map(fn(message: unit_stat_changed.UnitStatChanged) {
    assert message.unit_id == support.own_unit_id
      as "the message names the player's own unit (opcode.0x938)"
    case message.change {
      unit_stat_change.Absorption(UnitStatAbsorption(value:)) -> Ok(value)
      unit_stat_change.Shield(..)
      | unit_stat_change.InterruptArmor(..)
      | unit_stat_change.Level(..) -> Error(Nil)
    }
  })
}

/// The absorption of each `Absorption` news the steps tell the viewer connection `viewer`,
/// in order.
fn told(
  steps steps: List(ConnectionStep(Request)),
  viewer viewer: Int,
) -> List(Int) {
  list.flat_map(steps, fn(taken) {
    list.filter_map(support.peer_tells(taken), fn(tell) {
      case tell.0 == viewer, { tell.1 }.news {
        True, Absorption(absorption:) -> Ok(absorption)
        True, _ -> Error(Nil)
        False, _ -> Error(Nil)
      }
    })
  })
}

/// The soaked part of the blow's description the step answers the creature with: its
/// absorbed, shield absorbed and health fields.
fn description_of(taken taken: ConnectionStep(Request)) -> #(Int, Int, Int) {
  let assert [
    #(
      _,
      client_connection.TellStrikeAnswered(answered: strike_tell.Answered(
        outcome: strike_tell.Landed(descriptions: [description], ..),
        ..,
      )),
    ),
  ] = support.told_creatures(taken)
    as "the creature is answered once, with one blow landed"
  let damage = description.damage
  #(damage.absorbed, damage.shield_absorbed, damage.health_damage_with_overkill)
}

// ---- the pool on the player and its viewers ----

fn a_struck_pool_falls_for_the_player_and_its_viewer(
  world world: World,
  left_after left_after: Int,
) -> Nil {
  let #(holding, early) = pooled_until(world:, until_ms: 1500)
  assert written(steps: early) == [164]
    as "0x938 stat 22 = 164 at the go: round(2.531 x 50.765625 + 2.531 x 13.921875)"
  assert told(steps: early, viewer: 2) == [164]
    as "a viewer is told the same sum"
  let #(_, struck) =
    support.at(
      state: holding,
      ms: 2000,
      event: support.a_creatures_blow(
        unit_id: support.own_unit_id,
        damage_type: 3,
        damage: 300,
      ),
    )
  let assert [left] = written(steps: [struck])
    as "one 0x938 of stat 22 after the blow, and none of stat 20: the shield is untouched"
  assert left == left_after as "164 less what the pool soaked of the blow"
  assert told(steps: [struck], viewer: 2) == [left]
    as "the viewer is told the same value"
  assert told(steps: [struck], viewer: 3) == [left]
  assert list.map(support.heard(struck, support.keyed()), fn(frame) {
      frame.message_id
    })
    == [0x0938, 0x092F]
    as "stat 22 first, then the health (the shield did not move)"
  let #(absorbed, shield_absorbed, health) = description_of(taken: struck)
  assert absorbed == 300
    as "the description's absorbed holds the mitigated part and the soaked part: the whole blow"
  assert shield_absorbed == 0 && health == 0
    as "the shield and the health took nothing"
}

pub fn an_esper_struck_through_its_absorb_sees_stat_22_fall_and_so_does_its_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  // 164 less 120 is 44, worked by hand in the module's doc.
  a_struck_pool_falls_for_the_player_and_its_viewer(
    world: esper_world(),
    left_after: 44,
  )
}

fn an_absorb_that_ends_tells_zero(world world: World) -> Nil {
  let #(_, whole) = pooled_until(world:, until_ms: 20_000)
  assert written(steps: whole) == [164, 0]
    as "stat 22 = 164 at the go and 0 when the 5000 ms end"
  assert told(steps: whole, viewer: 2) == [164, 0]
    as "each viewer is told the same two"
  assert told(steps: whole, viewer: 3) == [164, 0]
  let #(_, holding) = pooled_until(world:, until_ms: 5900)
  assert written(steps: holding) == [164]
    as "nothing has ended by 5900 ms: the end comes 5000 ms after the go at 1000"
}

pub fn an_esper_whose_absorb_ends_tells_zero_to_the_client_and_viewers_test() -> Nil {
  use <- owned_test.run(60_000)
  an_absorb_that_ends_tells_zero(world: esper_world())
}

// ---- a viewer that arrives, and the viewer's side ----

fn a_late_viewer_is_created_with_the_pool(world world: World) -> Nil {
  let #(holding, _) = pooled_until(world:, until_ms: 1500)
  assert unit_fields.stat(
      tail: support.created_for(state: holding, viewer: 4).tail,
      stat_id: 22,
    )
    == Ok(164)
    as "stat 22 is listed while the sum is above 0 (opcode.0x938: the client's create reads stat 22 of the 0x262)"
  let #(ended, _) = pooled_until(world:, until_ms: 20_000)
  assert unit_fields.stat(
      tail: support.created_for(state: ended, viewer: 5).tail,
      stat_id: 22,
    )
    == Error(Nil)
    as "no pool, no stat 22"
}

pub fn an_esper_viewer_arriving_while_an_absorb_holds_is_created_with_stat_22_test() -> Nil {
  use <- owned_test.run(60_000)
  a_late_viewer_is_created_with_the_pool(world: esper_world())
}

pub fn absorption_news_for_a_unit_the_viewer_does_not_show_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let shown =
    support.feed(support.in_world(), support.event_of(support.Appears)).0
  let #(_, taken) =
    support.feed(
      shown,
      support.news_sent_by_a_peer(unit_id: 9, news: Absorption(absorption: 50)),
    )
  let assert [frame] = support.heard(taken, support.keyed())
  assert frame.message_id == 0x0938
  assert unit_stat_changed.decode(frame.body)
    == Ok(UnitStatChanged(
      unit_id: 9,
      change: unit_stat_change.Absorption(UnitStatAbsorption(value: 50)),
    ))
    as "the viewer writes the same sum under the unit it shows (opcode.0x938)"
  let #(_, early) =
    support.feed(
      support.in_world(),
      support.news_sent_by_a_peer(unit_id: 9, news: Absorption(absorption: 50)),
    )
  assert support.heard(early, support.keyed()) == []
    as "a news before the unit's 0x262 finds no unit shown, and the client would ignore an unknown unit (the shown guard, as for Shield)"
  let #(gone, _) =
    support.feed(
      shown,
      support.news_sent_by_a_peer(unit_id: 9, news: client_connection.Removed),
    )
  let #(_, late) =
    support.feed(
      gone,
      support.news_sent_by_a_peer(unit_id: 9, news: Absorption(absorption: 0)),
    )
  assert support.heard(late, support.keyed()) == []
    as "a news after the unit was removed writes nothing"
}
