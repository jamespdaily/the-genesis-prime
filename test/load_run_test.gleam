//// The load clients (`genesis_prime/load_player`) and the steps of the ramp
//// (`genesis_prime/load_run`), played against the server's real tree on a
//// database of the test's own. Expected values come from these places.
//// - The path: STS login, auth login, game hello, character list, create,
////   world entry and the first pong, the stages the card names in order.
//// - The ping: the client sends its first ping with number 0, the next only
////   after the last is answered with the number after it, modulo 20, and at
////   most once every 500 ms (SendNetworkPings, opcode.0x0, opcode.0x1).
//// - An account the database does not hold gets an error reply to LoginStart,
////   so the client fails at its STS login.
//// - The ramp: 50 players, doubling to 12,800, and after the first step that is
////   not kept one step halfway back to the last that was, rounded to 50: the
////   card's design.
//// - `eaddrnotavail` is the operating system's answer when the machine has no
////   local port to connect from.

import ask_support
import event_wait
import genesis_prime/load_player.{
  AuthLogin, CharacterList, Create, EnterWorld, FirstPong, GameHello, Ping,
  Position, StsLogin,
}
import genesis_prime/load_run.{Failure}
import genesis_prime/load_sample
import genesis_prime/load_step.{ClientsLimited, Failed, Kept, PlayerFailed}
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import login_support
import owned_test
import pog

const stage_order = [
  StsLogin,
  AuthLogin,
  GameHello,
  CharacterList,
  Create,
  EnterWorld,
  FirstPong,
]

/// Starts the server's tree, seeds the first `seeded` of three accounts and
/// plays a step of the three, and stops the tree.
fn step_of_three(seeded seeded: Int) -> load_run.Outcome {
  let started = login_support.start()
  let accounts = load_player.accounts(first: 0, count: 3)
  load_player.seed(
    pool: pog.named_connection(started.settings.pool.pool_name),
    accounts: list.take(accounts, seeded),
  )
  let outcome =
    load_run.run_step(
      ports: login_support.ports(started),
      accounts:,
      arrival_ms: 300,
      hold_ms: 0,
      sample_server: load_sample.take_node,
    )
  login_support.stop(started)
  outcome
}

pub fn three_clients_each_reach_the_world_and_report_their_seven_stage_times_in_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let outcome = step_of_three(seeded: 3)
  assert outcome.failures == [] as "every client reached the end of its path"
  assert list.length(outcome.stage_times) == 3
  list.each(outcome.stage_times, fn(stage_times) {
    assert list.map(stage_times, fn(stage_time) { stage_time.0 }) == stage_order
      as "each client reports each stage once, in the path's order"
  })
}

pub fn a_player_that_moves_drops_and_logs_in_again_reads_back_the_position_it_sent_test() -> Nil {
  use <- owned_test.run(60_000)
  let started = login_support.start()
  let accounts = load_player.accounts(first: 0, count: 1)
  load_player.seed(
    pool: pog.named_connection(started.settings.pool.pool_name),
    accounts:,
  )
  let assert [account] = accounts
  let to = Position(x: 100.5, y: -20.25, z: 300.125)
  let back =
    load_player.moves_and_returns(
      account:,
      ports: login_support.ports(started),
      to:,
      after_the_drop: fn() {
        event_wait.until("the game listener's connection ended", fn() {
          ask_support.connections_of(started.settings.game.listener) == []
        })
      },
    )
  assert back == to
    as "the unit the server created at the second login stands where the first login's movement put it: 0x637 kept, saved at the drop and read back (opcode.0x637, 0x1404586e0); the values are exact 32-bit floats"
  login_support.stop(started)
}

pub fn an_unknown_account_is_counted_as_a_failure_at_login_and_the_others_go_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let outcome = step_of_three(seeded: 2)
  let assert [Failure(player: 2, at: Some(StsLogin), ..)] = outcome.failures
    as "the third account, which no row holds, fails at its STS login and nothing else fails"
  assert list.length(outcome.stage_times) == 2
    as "the other two clients finished, and the collector went on"
  assert outcome.observation.failures == 1
}

pub fn the_first_ping_is_number_0_and_each_next_is_the_one_after_the_answer_modulo_20_test() -> Nil {
  use <- owned_test.run(5000)
  // A connection starts with its last answered number 19, so its next is 0.
  assert load_player.next_ping(answered: 19, sent_at_ms: 0, now_ms: 0).number
    == 0
  assert load_player.next_ping(answered: 0, sent_at_ms: 0, now_ms: 0).number
    == 1
  assert load_player.next_ping(answered: 18, sent_at_ms: 0, now_ms: 0).number
    == 19
}

pub fn the_next_ping_waits_until_500_ms_after_the_last_one_was_sent_test() -> Nil {
  use <- owned_test.run(5000)
  assert load_player.next_ping(answered: 3, sent_at_ms: 1000, now_ms: 1120)
    == Ping(number: 4, wait_ms: 380)
  assert load_player.next_ping(answered: 3, sent_at_ms: 1000, now_ms: 1500)
    == Ping(number: 4, wait_ms: 0)
  assert load_player.next_ping(answered: 3, sent_at_ms: 1000, now_ms: 1900)
    == Ping(number: 4, wait_ms: 0)
    as "a ping answered late goes at once, not 500 ms after the answer"
}

fn connect_failed(value: a) -> Result(Nil, a) {
  Error(value)
}

/// What a process that fails the assertion with this value exits with.
fn exit_of_failed(value: String) -> process.ExitReason {
  let pid =
    process.spawn_unlinked(fn() {
      let assert Ok(Nil) = connect_failed(#(string.repeat("x", 1000), value))
        as "the connect failed"
      Nil
    })
  let monitor = process.monitor(pid)
  let assert Ok(process.ProcessDown(reason:, ..)) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 5000)
    as "the process ended"
  reason
}

pub fn an_exit_with_eaddrnotavail_deep_in_a_long_term_is_no_local_port_test() -> Nil {
  use <- owned_test.run(10_000)
  assert load_run.no_local_port(exit_of_failed("eaddrnotavail"))
    as "past the first 240 bytes of the exit's text, as proc_lib wraps it"
  assert !load_run.no_local_port(exit_of_failed("econnrefused"))
    as "another failure to connect is the server's"
}

pub fn the_ramp_doubles_from_50_to_12800_and_then_stops_test() -> Nil {
  use <- owned_test.run(5000)
  assert load_run.next_players([]) == Some(50)
  assert load_run.next_players([#(50, Kept)]) == Some(100)
  assert load_run.next_players([#(50, Kept), #(100, Kept), #(200, Kept)])
    == Some(400)
  assert load_run.next_players([#(6400, Kept)]) == Some(12_800)
  assert load_run.next_players([#(12_800, Kept)]) == None
    as "12,800 is the most the ramp tries"
}

pub fn the_first_step_not_kept_is_followed_by_one_halfway_back_rounded_to_50_test() -> Nil {
  use <- owned_test.run(5000)
  let failed = Failed([PlayerFailed])
  assert load_run.next_players([#(50, Kept), #(100, Kept), #(200, failed)])
    == Some(150)
  assert load_run.next_players([#(3200, Kept), #(6400, ClientsLimited)])
    == Some(4800)
  assert load_run.next_players([#(800, Kept), #(1600, failed)]) == Some(1200)
  assert load_run.next_players([#(100, Kept), #(250, failed)]) == Some(150)
    as "175 rounds down to 150"
  assert load_run.next_players([#(50, Kept), #(100, failed)]) == None
    as "halfway rounds to the last kept step, which is no new one"
  assert load_run.next_players([#(50, failed)]) == None
    as "no step was kept, so none lies halfway"
}

pub fn the_ramp_ends_after_the_halfway_step_test() -> Nil {
  use <- owned_test.run(5000)
  let failed = Failed([PlayerFailed])
  assert load_run.next_players([
      #(3200, Kept),
      #(6400, ClientsLimited),
      #(4800, Kept),
    ])
    == None
  assert load_run.next_players([#(3200, Kept), #(6400, failed), #(4800, failed)])
    == None
}

pub fn the_maximum_is_the_most_players_of_any_kept_step_test() -> Nil {
  use <- owned_test.run(5000)
  let failed = Failed([PlayerFailed])
  assert load_run.maximum([
      #(3200, Kept),
      #(6400, ClientsLimited),
      #(4800, Kept),
    ])
    == 4800
  assert load_run.maximum([#(3200, Kept), #(6400, failed), #(4800, failed)])
    == 3200
  assert load_run.maximum([#(50, failed)]) == 0 as "no step was kept"
}
