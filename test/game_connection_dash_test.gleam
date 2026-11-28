//// The client's 0x015C on the game connection (`genesis_prime/game/connection`): the
//// payment of the dash and what the player's client is told, what is dropped, what ends
//// the connection, and the refill's timer. The rule's decisions are `dash_test`'s and
//// `class_resource_test`'s; this tests the connection's own job, one case per path.
//// Expected values come from these places:
//// - `opcode.0x15c`: the client sends a 3-bit direction, 1 to 4, only when its press
////   check of the dash spell passes (100 or more of slot 7); it creates no cast for a
////   dash, moves itself and reports the move in 0x637.
//// - `opcode.0x935`: a 32-bit unit, a 5-bit stat and a float; stat 9 is slot 7.
//// - Spell4 28770 to 28773: innate cost type 16 of 100.
//// - The server's choices: the dash energy starts full at 200, refills 25 a second
////   in 250 ms ticks, and a dash the server cannot pay is dropped with a log line and
////   the true value sent again.

import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request, AskStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/float32
import genesis_prime/message/unit_float_stat_changed.{UnitFloatStatChanged}
import genesis_prime/shared/class_resource
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import genesis_prime/store.{CharacterId, Move, SavePlace}
import gleam/list
import owned_test
import resource_frames_support

/// A 0x015C of this direction, inside 0x038C: the direction in 3 bits.
fn dash_message(direction direction: Int) -> BitArray {
  connection_support.world_message(message_id: 0x015C, body: <<direction>>)
}

/// The tests' player in the world, with the unit id of its 0x262.
fn in_world() -> #(game_connection.State, Int) {
  let #(state, burst) = connection_support.entered()
  #(state, connection_support.player_in(burst).unit_id)
}

/// Whether a step tells another process anything: a viewer is told through the map.
fn tells(taken: ConnectionStep(Request)) -> Bool {
  list.any(support.effects_of(taken), fn(effect) {
    case effect {
      step.OwnEffect(step.Tell(..)) | step.OwnEffect(step.TellWatched(..)) ->
        True
      step.OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> False
    }
  })
}

pub fn a_dash_pays_100_writes_0x935_of_stat_9_to_the_player_only_and_tells_no_viewer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, unit_id) = in_world()
  let #(_, taken) =
    connection_support.read(state:, bytes: dash_message(direction: 1))
  assert connection_support.written_ids(taken) == [0x0935]
    as "one frame to the player's own client: no 0x07FF, since the client holds no cast of a dash"
  assert resource_frames_support.changes_written(taken)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 9, value: float32.to_bits(100.0)),
    ]
    as "200 less 100, as 0x935 of stat 9"
  assert resource_frames_support.resource_timers_started(taken)
    == [#(class_resource.dash_timer, 250)]
    as "the refill starts, 250 ms ticks"
  assert !tells(taken)
    as "its movement reaches viewers in the client's own 0x637, not here"
  assert support.logs(taken) == [] && !support.stops(taken)
}

pub fn a_dash_with_less_than_100_or_by_a_dead_player_is_dropped_with_a_log_and_the_true_value_is_sent_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, unit_id) = in_world()
  let #(state, _) =
    connection_support.read(state:, bytes: dash_message(direction: 1))
  let #(state, second) =
    connection_support.read(state:, bytes: dash_message(direction: 3))
  assert resource_frames_support.changes_written(second)
    == [UnitFloatStatChanged(unit_id:, stat_id: 9, value: float32.to_bits(0.0))]
    as "the second dash empties it"
  let #(_, stale) =
    connection_support.read(state:, bytes: dash_message(direction: 2))
  let assert [line] = support.logs_of(step: stale, level: step.LogWarning)
    as "one log line: the client's own press check refuses a dash below 100 before sending it, so this client holds a stale value"
  assert support.says(line, "0x015C")
  assert resource_frames_support.changes_written(stale)
    == [UnitFloatStatChanged(unit_id:, stat_id: 9, value: float32.to_bits(0.0))]
    as "the true value, 0, is sent again so the client's meter is corrected"
  assert !support.stops(stale) as "a stale client is not ended"
  let #(dead, _) = connection_support.killed(in_world().0)
  let #(_, by_dead) =
    connection_support.read(state: dead, bytes: dash_message(direction: 4))
  let assert [dead_line] =
    support.logs_of(step: by_dead, level: step.LogWarning)
    as "a dead player's dash is dropped with a line: the client's press check refuses it"
  assert support.says(dead_line, "0x015C")
  assert resource_frames_support.changes_written(by_dead)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 9, value: float32.to_bits(200.0)),
    ]
    as "nothing is paid, the true value, 200, is sent again"
  assert resource_frames_support.resource_timers_started(by_dead) == []
}

pub fn a_dash_direction_the_client_never_sends_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = in_world()
  list.each([0, 5, 7], fn(direction) {
    let #(_, taken) =
      connection_support.read(state:, bytes: dash_message(direction:))
    let assert [line] = support.logs_of(step: taken, level: step.LogError)
      as "0x14039f590 maps only the directions 1 to 4, and RequestDash returns on 0"
    assert support.says(line, "0x015C")
    assert support.writes(taken) == []
    let assert AskStore(Move(SavePlace(character_id: CharacterId(42), ..))) =
      connection_support.ask_request(taken)
      as "the place is saved as for any refused message, then the connection ends"
  })
}

pub fn the_dash_timer_fires_through_the_connection_and_writes_0x935_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, unit_id) = in_world()
  let #(state, _) =
    connection_support.read(state:, bytes: dash_message(direction: 1))
  let #(_, ticked) =
    connection_support.feed(
      state,
      OwnEvent(TimerFired(timer: class_resource.dash_timer)),
    )
  assert resource_frames_support.changes_written(ticked)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 9, value: float32.to_bits(106.25)),
    ]
    as "the refill's tick, a timer of the connection: 25 a second in 250 ms ticks is 6.25"
  assert resource_frames_support.resource_timers_started(ticked)
    == [#(class_resource.dash_timer, 250)]
}
