//// A threshold row's class cost on the game connection: the release of Charged
//// Shot's charge pays the row's cost from the Spellslinger's Spell Power, written as
//// 0x935, or is refused 175 when the vital holds less. Expected values come from
//// these places:
//// - `opcode.0x935`: the class resource's change is written to the player's own client
////   as a 32-bit unit, a 5-bit stat and a float; stat n + 2 is slot n, so Spell Power
////   (slot 4 of the Spellslinger) is stat 6 (`opcode.0x262.resource_stats`).
//// - `CheckThresholdRowCosts 0x1403c0620`: a row cost of type 19 must be at most the
////   vital's value, and a vital with nothing in it gives 175 (the client's own result
////   for a vital no slot holds above 0).
//// - The cost planted: the client's Spell4Thresholds 123 (the charge's level 1) holds a
////   cost of 0 in every column, so the test plants (19, 25) in it, the amount the
////   client's Spell4.76002 holds as an innate cost of type 19. The Spellslinger's
////   100 Spell Power is the class's own maximum (migration 0018).

import cast_support
import class_resource_support
import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_result
import genesis_prime/message/float32
import genesis_prime/message/spell_go
import genesis_prime/message/unit_float_stat_changed.{
  type UnitFloatStatChanged, UnitFloatStatChanged,
}
import genesis_prime/shared/class_resource
import genesis_prime/shared/loadout
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import genesis_prime/table/loader/store as store_tables
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table.{Integer}
import server_proxy_support

const charged_shot_base = 20_684

/// The Spellslinger in the world, its Spell Power emptying after combat as the Esper's,
/// its unit id and Charged Shot's bag index, on the tables with Spell4Thresholds 123
/// (the charge's level 1) given this cost.
fn charging(
  cost cost: #(Int, Int),
  body body: fn(game_connection.State, Int, Int) -> a,
) -> a {
  fixture_tables.changed(
    table: "Spell4Thresholds",
    id: 123,
    with: [
      #("vitalEnumCostType00", Integer(cost.0)),
      #("vitalCostValue00", Integer(cost.1)),
    ],
    body: fn(tables) {
      let #(state, taken) =
        connection_support.entered_with(
          settings: Settings(
            ..connection_support.settings(),
            tables:,
            class_resources: class_resource_support.spellslinger_emptying_after_combat(),
            server_proxies: server_proxy_support.none(),
          ),
          class_id: 7,
          saved_health: None,
        )
      let assert Ok(set) = bag_of(tables:)
        as "the tables hold the Spellslinger's Novice set"
      let assert Ok(bag_index) =
        list.index_map(set, fn(base, index) { #(base, index) })
        |> list.key_find(Spell4BaseId(charged_shot_base))
        as "a level-1 Spellslinger holds Charged Shot"
      body(state, connection_support.player_in(taken).unit_id, bag_index)
    },
  )
}

fn bag_of(
  tables tables: store_tables.Tables,
) -> Result(List(id.Spell4BaseId), Nil) {
  case loadout.of(tables:, class_id: ClassId(7), faction_id: 166) {
    Ok(set) -> Ok(set.abilities)
    Error(_) -> Error(Nil)
  }
}

fn press_at(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.at(
    state:,
    ms:,
    event: OwnEvent(
      step.Read(connection_support.world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id:,
          bag_index:,
          target: 0,
          press: 1,
        ),
      )),
    ),
  )
}

/// The 0x935s a step writes, decoded.
fn resource_changes(
  taken taken: ConnectionStep(Request),
) -> List(UnitFloatStatChanged) {
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

/// Charged Shot pressed at 1000 ms and its charge taken to level 1 (its timer fired at
/// 2000 ms, Spell4Thresholds 123's thresholdDuration 1000 later); the next press is
/// the release.
fn charged_to_level_1(
  state state: game_connection.State,
  bag_index bag_index: Int,
) -> game_connection.State {
  let #(state, pressed) =
    press_at(state:, bag_index:, client_cast_id: 9, ms: 1000)
  let assert [timer] =
    list.filter(support.timers_started(pressed), cast_state.owns)
    as "the press opens the charge: one timer of the cast rule, the level 1 timer"
  let #(state, _) = connection_support.fired_at(state:, timer:, ms: 2000)
  state
}

pub fn a_charged_shot_release_pays_its_planted_row_cost_from_spell_power_test() -> Nil {
  use <- owned_test.run(120_000)
  use state, unit_id, bag_index <- charging(cost: #(19, 25))
  let state = charged_to_level_1(state:, bag_index:)
  let #(_, released) =
    press_at(state:, bag_index:, client_cast_id: 10, ms: 2100)
  assert connection_support.refusal_results(taken: released) == []
    as "the release is not refused"
  let frames = connection_support.written(taken: released)
  let gos =
    connection_support.decoded(frames, spell_go.message_id, spell_go.decode)
  assert list.map(gos, fn(go) {
      list.flat_map(go.targets, fn(target) {
        list.map(target.effects, fn(effect) { effect.spell4_effects_id })
      })
    })
    == [[80_979]]
    as "the release's go is stage 34722's (Spell4Thresholds 123's to_cast): it lists Spell4Effects 80979, whose spellId is 34722"
  assert list.filter(list.map(frames, fn(frame) { frame.message_id }), fn(id) {
      id == spell_go.message_id || id == unit_float_stat_changed.message_id
    })
    == [unit_float_stat_changed.message_id, spell_go.message_id]
    as "the payment is written before the go it is paid for: a go that is at once pays as its strike begins, so the go's own gates read the paid caster (`cast` module doc, 'A cost is checked at the accept and paid at the cast's first go'; the server's choice, the client shows only what 0x935 says)"
  assert resource_changes(taken: released)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 6, value: float32.to_bits(75.0)),
    ]
    as "100 Spell Power less the row's 25, as 0x935 of stat 6 (slot 4) to the player's own client"
}

pub fn a_charged_shot_release_at_no_spell_power_is_refused_175_test() -> Nil {
  use <- owned_test.run(120_000)
  use state, unit_id, bag_index <- charging(cost: #(19, 25))
  // The combat flag set and cleared, then the wait that empties the slot ends.
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 9, life: 3)),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Released(unit_id: 9)),
    )
  let #(state, emptied) =
    connection_support.feed(
      state:,
      event: OwnEvent(TimerFired(timer: class_resource.empty_timer)),
    )
  assert resource_changes(taken: emptied)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 6, value: float32.to_bits(0.0)),
    ]
    as "the wait empties Spell Power: the test's start"
  let state = charged_to_level_1(state:, bag_index:)
  let #(_, released) =
    press_at(state:, bag_index:, client_cast_id: 10, ms: 2100)
  assert list.map(
      connection_support.refusal_results(taken: released),
      cast_result.to_value,
    )
    == [175]
    as "0x1403c0620: the row's cost of 25 of a vital holding 0 gives 175, which the release's 0x7fc carries"
  assert resource_changes(taken: released) == []
    as "a refused release pays nothing"
  Nil
}
