//// What a creature's held crowd-control states say about its movement
//// (`genesis_prime/world_map/creature_control` `stops_moving`, the mask
//// `genesis_prime/game/crowd_control` `stopping_mask` works out of the client's
//// CCStates table). Expected values come from the client's CCStates rows, read with
//// `table_rows -- CCStates`: the states whose `flags` hold the value 2 are 0 Stun
//// (30), 1 Sleep (30), 2 Root (195), 7 Hold (87), 8 Knockdown (30), 12 Disable (95),
//// 16 Knockback (30), 17 Pushback (22), 18 Pull (30), 19 PositionSwitch (6) and 26
//// DisableCinematic (95); the other 17 rows (3 Disarm 0, 4 Silence 0, 5 Polymorph 0, 6
//// Fear 4, 9 Vulnerability 37, 20 Tether 129, 21 Snare 129 ...) do not. The client's
//// own use of the value is `UnitHasCCStateFlag02` (0x14045e630): the player's own
//// movement input is dropped while a unit holds a state with it.

import crowd_control_support
import fixture_tables
import genesis_prime/game/crowd_control
import genesis_prime/game/hit.{Offence}
import genesis_prime/game/strike_tell.{
  type ControlTell, CreatureStriker, Key, Strike,
}
import genesis_prime/message/crowd_control_state.{
  type CrowdControlState, Fear, Polymorph, Root, Snare, Stun, Tether,
}
import genesis_prime/step
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_life
import gleam/int
import gleam/list
import owned_test

/// The creature holding these states, each landed by its own strike at 0 ms on a
/// creature with no armor.
fn holding(states states: List(CrowdControlState)) -> creature_control.State {
  list.index_fold(states, creature_control.new(), fn(state, held, index) {
    creature_control.land(
      state:,
      tell: strike_for(
        controls: [
          crowd_control_support.holding(
            state: held,
            duration_ms: 2000,
            instance_id: 100 + index,
          ),
        ],
        cast_id: index + 1,
      ),
      armor: creature_life.NoArmor,
      refill_ms: 0,
      now_ms: 0,
    ).state
  })
}

fn strike_for(
  controls controls: List(ControlTell),
  cast_id cast_id: Int,
) -> strike_tell.Tell {
  Strike(
    key: Key(cast_id:, phase: 0, unit_id: 7),
    from: step.Connection(step.ConnectionId(2)),
    striker: CreatureStriker,
    offence: Offence(
      blows: [],
      crit_chance: 0.0,
      crit_severity: 1.5,
      strikethrough: 0.0,
    ),
    controls:,
  )
}

pub fn only_a_flag_two_state_stops_a_creature_moving_test() -> Nil {
  use <- owned_test.run(5000)
  let stopped_by = crowd_control.stopping_mask(tables: fixture_tables.shared())
  assert stopped_by
    == list.fold([0, 1, 2, 7, 8, 12, 16, 17, 18, 19, 26], 0, fn(mask, state) {
      int.bitwise_or(mask, int.bitwise_shift_left(1, state))
    })
    as "the mask is the states whose CCStates flags hold the value 2, none other"
  assert creature_control.stops_moving(
    state: holding(states: [Stun]),
    stopped_by:,
  )
    as "Stun, flags 30"
  assert creature_control.stops_moving(
    state: holding(states: [Root]),
    stopped_by:,
  )
    as "Root, flags 195"
  assert !creature_control.stops_moving(
    state: holding(states: [Snare]),
    stopped_by:,
  )
    as "Snare, flags 129"
  assert !creature_control.stops_moving(
    state: holding(states: [Polymorph]),
    stopped_by:,
  )
    as "Polymorph, flags 0"
  assert !creature_control.stops_moving(
    state: holding(states: [Fear]),
    stopped_by:,
  )
    as "Fear, flags 4"
  assert !creature_control.stops_moving(
    state: holding(states: [Tether]),
    stopped_by:,
  )
    as "Tether, flags 129"
  assert !creature_control.stops_moving(
    state: creature_control.new(),
    stopped_by:,
  )
    as "a creature holding nothing moves"
  assert creature_control.stops_moving(
    state: holding(states: [Snare, Fear, Root]),
    stopped_by:,
  )
    as "one state with the value among others stops it"
}
