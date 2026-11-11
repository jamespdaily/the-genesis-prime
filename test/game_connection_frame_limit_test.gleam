//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover the limits on
//// what a client may send: the bytes held while a claim waits, the biggest
//// frame the client's reader takes, the burst and refill of the frame bucket,
//// inputs given an earlier time, and frames split into any number of reads.
////

import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/step.{
  type ConnectionStep, LogError, LogWarning, OwnEvent, WatchEnded, WatchId,
}
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test

pub fn bytes_past_the_hold_limit_while_the_claim_waits_end_the_connection_with_an_error_and_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let waiting_on_the_timer =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    ).0
  let claim_out = game_connection_support.claiming().0
  list.each([waiting_on_the_timer, claim_out], fn(state) {
    let #(state, taken) =
      game_connection_support.read(state, <<0:size(support.held_limit * 8)>>)
    assert !support.stops(taken)
      as "bytes up to the limit are kept for after the claim"
    let #(_, taken) = game_connection_support.read(state, <<0>>)
    assert support.stops(taken)
      as "one byte past the limit is more than a whole frame and a read can hold"
    assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    assert support.writes(taken) == []
      as "a connection that sends no frame is no client, so it is told nothing"
    assert support.asked(taken) == None
  })
}

pub fn a_frame_one_byte_over_131070_ends_the_connection_with_an_error_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // The length field counts the whole frame, little-endian: 131,070 is fe ff
  // 01 00 and 131,071 ff ff 01 00 (MessageSizeLimit 0x140335ec0).
  let #(_, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      0xFE,
      0xFF,
      0x01,
      0x00,
      0,
      0,
    >>)
  assert !support.stops(taken)
    as "a frame of 131,070 bytes is the biggest the client's reader takes, so the connection waits for the rest"
  let #(_, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      0xFF,
      0xFF,
      0x01,
      0x00,
      0,
      0,
    >>)
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  assert support.writes(taken) == []
    as "a client whose frame the client's own reader would refuse is told nothing"
  let #(_, taken) =
    game_connection_support.read(game_connection_support.connected(), <<
      0xFF,
      0xFF,
      0x01,
      0x00,
    >>)
  assert support.stops(taken)
    as "the length is refused as soon as its four bytes are here, before the frame's bytes are waited for"
}

fn read_at(
  state state: game_connection.State,
  ms ms: Int,
  bytes bytes: BitArray,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(
    state,
    support.input_at_ms(ms:, event: OwnEvent(step.Read(bytes))),
  )
}

pub fn a_full_burst_of_frames_is_taken_and_one_more_in_the_same_millisecond_ends_the_connection_with_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        rate: support.bucket(burst: 5, per_second: 2),
      ),
    ).0
  let #(state, taken) =
    game_connection_support.read(state, support.pings(count: 5))
  assert support.writes(taken)
    == [
      support.pong(0),
      support.pong(1),
      support.pong(2),
      support.pong(3),
      support.pong(4),
    ]
    as "a connection that has sent nothing holds a full bucket of 5 frames, and each is answered"
  assert !support.stops(taken)
  let #(_, taken) = game_connection_support.read(state, support.ping(5))
  assert support.stops(taken)
  assert support.writes(taken) == []
    as "the frame past the rate is not answered"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line:, words: "faster")
  assert support.logs_of(step: taken, level: LogError) == []
    as "a client that sends too fast is an outside failure the server recovers from, a warning"
  // A client that waited a long time has the burst again and no more.
  let #(state, taken) =
    read_at(
      state: game_connection_support.accepted(
        Settings(
          ..game_connection_support.settings(),
          rate: support.bucket(burst: 5, per_second: 2),
        ),
      ).0,
      ms: support.now_ms + 3_600_000,
      bytes: support.pings(count: 5),
    )
  assert list.length(support.writes(taken)) == 5 && !support.stops(taken)
  let #(_, taken) =
    read_at(state:, ms: support.now_ms + 3_600_000, bytes: support.ping(5))
  assert support.stops(taken)
    as "an hour of waiting does not store more than the burst"
}

pub fn the_bucket_refills_exactly_with_no_drift_over_10000_frames_sent_at_exactly_the_rate_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3 frames a second: a frame is due every 333 1/3 ms, which no whole
  // millisecond holds, so a bucket that rounds each refill drifts. Frame k is
  // sent at the first whole millisecond by which k/3 of a second has passed.
  let state =
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        rate: support.bucket(burst: 2, per_second: 3),
      ),
    ).0
  let start = support.now_ms
  let #(state, taken) =
    read_at(state:, ms: start, bytes: support.pings(count: 2))
  assert list.length(support.writes(taken)) == 2 && !support.stops(taken)
    as "the burst of 2 empties the bucket"
  let due = fn(k) { start + { k * 1000 + 2 } / 3 }
  let state =
    int.range(from: 1, to: 10_001, with: state, run: fn(state, k) {
      let #(state, taken) =
        read_at(state:, ms: due(k), bytes: support.ping(k % 20))
      assert support.writes(taken) == [support.pong(k)]
        as "a frame sent at exactly the rate is taken, however many came before"
      assert !support.stops(taken)
      state
    })
  let #(_, taken) = read_at(state:, ms: due(10_001) - 1, bytes: support.ping(0))
  assert support.stops(taken)
    as "a frame one millisecond before it is due is refused: no frame is let through early either"
}

pub fn an_input_with_an_earlier_time_credits_no_time_twice_test() -> Nil {
  use <- owned_test.run(10_000)
  // 100 a second is one frame every 10 ms. The bucket holds 3, which it is
  // full of at the hello, at `start`.
  let start = support.now_ms
  let state =
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        rate: support.bucket(burst: 3, per_second: 100),
      ),
    ).0
  // Times 10 ms on, then 10 ms back, then 10 ms on again: the clock never goes
  // back, but an input is given its time as the shell read it, and a rule that
  // is given an earlier one must not count the same 10 ms twice.
  let #(state, taken) = read_at(state:, ms: start + 10, bytes: support.ping(0))
  assert support.writes(taken) == [support.pong(0)]
  let #(state, taken) = read_at(state:, ms: start, bytes: support.ping(1))
  assert support.writes(taken) == [support.pong(1)]
  let #(state, taken) = read_at(state:, ms: start + 10, bytes: support.ping(2))
  assert support.writes(taken) == [support.pong(2)]
  let #(_, taken) = read_at(state:, ms: start + 10, bytes: support.ping(3))
  assert support.stops(taken)
    as "3 frames were sent and the bucket held 3; the 10 ms between the first and the last input is credited once, and the bucket was already full then"
}

pub fn frames_sent_byte_by_byte_or_in_one_read_are_refused_at_the_same_frame_test() -> Nil {
  use <- owned_test.run(10_000)
  let rate = support.bucket(burst: 4, per_second: 1)
  let bytes = support.pings(count: 7)
  let #(_, whole) =
    game_connection_support.read(
      game_connection_support.accepted(
        Settings(..game_connection_support.settings(), rate:),
      ).0,
      bytes,
    )
  let answered = [
    support.pong(0),
    support.pong(1),
    support.pong(2),
    support.pong(3),
  ]
  assert support.writes(whole) == answered
    as "the 4 frames of the burst are answered and the 5th ends the connection"
  assert support.stops(whole)
  let #(fed, written) =
    fed_byte_by_byte(
      state: game_connection_support.accepted(
        Settings(..game_connection_support.settings(), rate:),
      ).0,
      bytes:,
      fed: 0,
      written: [],
    )
  assert written == answered
    as "the same frames are answered however the bytes were split"
  assert fed == 5 * 7
    as "a ping is 7 bytes: the 5th frame ends the connection on its last byte, and no earlier"
}

/// Feeds the bytes one at a time until a step stops the connection: how many
/// bytes were fed and the writes of every step, in order.
fn fed_byte_by_byte(
  state state: game_connection.State,
  bytes bytes: BitArray,
  fed fed: Int,
  written written: List(BitArray),
) -> #(Int, List(BitArray)) {
  case bytes {
    <<byte, rest:bytes>> -> {
      let #(state, taken) = game_connection_support.read(state, <<byte>>)
      let written = list.append(written, support.writes(taken))
      case support.stops(taken) {
        True -> #(fed + 1, written)
        False -> fed_byte_by_byte(state:, bytes: rest, fed: fed + 1, written:)
      }
    }
    _ -> #(fed, written)
  }
}
