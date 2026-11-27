//// What a creature's held crowd-control states say about its movement
//// (`genesis_prime/world_map/creature_control` `stops_moving`, the mask
//// `genesis_prime/shared/crowd_control` `stopping_mask` works out of the client's
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
import genesis_prime/game/strike_tell.{type ControlTell, Key, Strike}
import genesis_prime/game/unit_news
import genesis_prime/message/crowd_control_state.{
  type CrowdControlState, Fear, Polymorph, Root, Snare, Stun, Tether,
}
import genesis_prime/shared/crowd_control
import genesis_prime/shared/hit.{Offence}
import genesis_prime/step
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_life
import gleam/int
import gleam/list
import owned_test
import spawn_support

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
  strike_by(connection: 2, controls:, cast_id:)
}

/// A strike of the player of this connection's cast `cast_id`.
fn strike_by(
  connection connection: Int,
  controls controls: List(ControlTell),
  cast_id cast_id: Int,
) -> strike_tell.Tell {
  Strike(
    key: Key(cast_id:, occasion: strike_tell.AtGo(phase: 0), unit_id: 7),
    from: step.Connection(step.ConnectionId(connection)),
    striker: spawn_support.beast_striker(),
    offence: Offence(
      blows: [],
      crit_chance: 0.0,
      crit_severity: 1.5,
      strikethrough: 0.0,
    ),
    controls:,
    gates: [],
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

pub fn only_a_stun_a_knockdown_or_a_knockback_lets_a_creature_cast_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let hard =
    int.range(from: 27, to: -1, with: [], run: fn(found, number) {
      case
        creature_control.hard_held(
          state: holding(states: [crowd_control_state.from_value(number)]),
        )
      {
        True -> [number, ..found]
        False -> found
      }
    })
  assert hard == [0, 8, 16]
    as "the retail record (WildStar wiki, Combat, Moment of Opportunity) names Stun 0, Knockdown 8 and Knockback 16, and no other of the 28 states"
  assert !creature_control.hard_held(state: creature_control.new())
    as "a creature holding nothing casts"
  assert creature_control.hard_held(state: holding(states: [Snare, Fear, Stun]))
    as "one of the three among others refuses every cast"
}

/// What the creature holds when player 2's cast 1 landed a Stun (instance 101) and a Snare
/// (102), player 2's cast 2 a Stun (103) and player 3's cast 1 a Stun (104), each at 0 ms on
/// a creature with no armor; the controls are numbered 1 to 4 in that order.
fn held_by_two_players() -> creature_control.State {
  let land = fn(state, tell) {
    creature_control.land(
      state:,
      tell:,
      armor: creature_life.NoArmor,
      refill_ms: 0,
      now_ms: 0,
    ).state
  }
  let holding = fn(state, instance_id) {
    crowd_control_support.holding(state:, duration_ms: 2000, instance_id:)
  }
  creature_control.new()
  |> land(
    strike_by(connection: 2, cast_id: 1, controls: [
      holding(Stun, 101),
      holding(Snare, 102),
    ]),
  )
  |> land(strike_by(connection: 2, cast_id: 2, controls: [holding(Stun, 103)]))
  |> land(strike_by(connection: 3, cast_id: 1, controls: [holding(Stun, 104)]))
}

/// The 0x880 each effect of `ended_by` asks for (state, cast id, instance id) and the numbers
/// of the controls whose timers it cancels, in order.
fn ended_in(
  effects effects: List(creature_control.Effect),
) -> #(List(#(CrowdControlState, Int, Int)), List(Int)) {
  #(
    list.filter_map(effects, fn(effect) {
      case effect {
        creature_control.ToViewers(unit_news.CrowdControlEnded(
          state:,
          cast_id:,
          instance_id:,
        )) -> Ok(#(state, cast_id, instance_id))
        creature_control.ToViewers(_)
        | creature_control.StartTimer(..)
        | creature_control.CancelTimer(..)
        | creature_control.StartRefill(..)
        | creature_control.CancelRefill -> Error(Nil)
      }
    }),
    list.filter_map(effects, fn(effect) {
      case effect {
        creature_control.CancelTimer(control:) -> Ok(control)
        creature_control.ToViewers(_)
        | creature_control.StartTimer(..)
        | creature_control.StartRefill(..)
        | creature_control.CancelRefill -> Error(Nil)
      }
    }),
  )
}

pub fn a_caster_ending_its_cast_ends_the_states_that_cast_landed_and_no_other_state_test() -> Nil {
  use <- owned_test.run(5000)
  // Each state of the cast ends with its own 0x880 naming the cast and the instance the go
  // gave it (`opcode.0x880`), and its timer is cancelled; a state of the same player's other
  // cast, or of another player's cast of the same id, stays (a cast id names its caster's).
  let mask = fn(state) {
    int.bitwise_shift_left(1, crowd_control_state.to_value(state))
  }
  list.each(
    [
      #(
        2,
        1,
        [#(Stun, 1, 101), #(Snare, 1, 102)],
        [1, 2],
        True,
        False,
        "both states of player 2's cast 1 end, in the order they landed, and the Stuns of player 2's cast 2 and player 3's cast 1 stay",
      ),
      #(
        3,
        1,
        [#(Stun, 1, 104)],
        [4],
        True,
        True,
        "player 3's cast 1 ends its one Stun, though player 2 holds states of a cast with the same id",
      ),
      #(
        2,
        2,
        [#(Stun, 2, 103)],
        [3],
        True,
        True,
        "player 2's cast 2 ends its Stun alone",
      ),
      #(2, 3, [], [], True, True, "a cast that landed no state ends nothing"),
      #(9, 1, [], [], True, True, "a player that landed no state ends nothing"),
    ],
    fn(row) {
      let #(connection, cast_id, ended, cancelled, holds_stun, holds_snare, why) =
        row
      let caster = step.Connection(step.ConnectionId(connection))
      let #(state, effects) =
        creature_control.ended_by(
          state: held_by_two_players(),
          caster:,
          cast_id:,
        )
      assert ended_in(effects:) == #(ended, cancelled) as why
      assert creature_control.refuses(state:, mask: mask(Stun)) == holds_stun
        as { "Stun held afterwards: " <> why }
      assert creature_control.refuses(state:, mask: mask(Snare)) == holds_snare
        as { "Snare held afterwards: " <> why }
      let #(_, again) = creature_control.ended_by(state:, caster:, cast_id:)
      assert again == []
        as { "a second end of the same cast does nothing: " <> why }
    },
  )
}
