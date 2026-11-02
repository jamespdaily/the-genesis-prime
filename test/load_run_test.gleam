//// The load clients (`genesis_prime/load_player`) and one step of the ramp
//// (`genesis_prime/load_run`), played against the server's real tree on a
//// database of the test's own. Expected values come from these places.
//// - The path: STS login, auth login, game hello, character list, create,
////   world entry and the first pong, the stages the card names in order.
//// - The ping: the client sends its first ping with number 0, the next only
////   after the last is answered with the number after it, modulo 20, and at
////   most once every 500 ms (SendNetworkPings, opcode.0x0, opcode.0x1).
//// - An account the database does not hold gets an error reply to LoginStart,
////   so the client fails at its STS login.

import genesis_prime/load_player.{
  AuthLogin, CharacterList, Create, EnterWorld, FirstPong, GameHello, Ping,
  StsLogin,
}
import genesis_prime/load_run.{Failure}
import genesis_prime/load_sample
import gleam/list
import gleam/option.{Some}
import gleam/set
import login_client
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

pub fn three_clients_each_reach_the_world_and_report_their_seven_stage_times_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  use <- owned_test.run(60_000)
  let started = login_support.start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let accounts = load_player.accounts(first: 0, count: 3)
  load_player.seed(pool:, accounts:)
  let outcome =
    load_run.run_step(
      ports: login_support.ports(started),
      accounts:,
      arrival_ms: 300,
      hold_ms: 0,
      sample_server: load_sample.take_node,
    )
  assert outcome.failures == [] as "every client reached the end of its path"
  assert list.length(outcome.stage_times) == 3
  list.each(outcome.stage_times, fn(stage_times) {
    assert list.map(stage_times, fn(stage_time) { stage_time.0 }) == stage_order
      as "each client reports each stage once, in the path's order"
  })
  login_support.stop(started)
}

pub fn an_unknown_account_is_counted_as_a_failure_at_login_and_the_others_go_on_test() -> Nil {
  use <- owned_test.run(5000)
  use <- owned_test.run(60_000)
  let started = login_support.start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let accounts = load_player.accounts(first: 0, count: 3)
  load_player.seed(pool:, accounts: list.take(accounts, 2))
  let outcome =
    load_run.run_step(
      ports: login_support.ports(started),
      accounts:,
      arrival_ms: 300,
      hold_ms: 0,
      sample_server: load_sample.take_node,
    )
  let assert [Failure(player: 2, at: Some(StsLogin), ..)] = outcome.failures
    as "the third account, which no row holds, fails at its STS login and nothing else fails"
  assert list.length(outcome.stage_times) == 2
    as "the other two clients finished, and the collector went on"
  assert outcome.observation.failures == 1
  login_support.stop(started)
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
  assert load_player.next_ping(answered: 19, sent_at_ms: 0, now_ms: 0).number
    == 0
    as "the number after 19 is 0, so numbers 0 to 19 repeat"
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

pub fn seeded_accounts_log_in_with_their_own_names_and_the_one_password_test() -> Nil {
  use <- owned_test.run(5000)
  use <- owned_test.run(60_000)
  let started = login_support.start()
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let accounts = load_player.accounts(first: 7, count: 2)
  load_player.seed(pool:, accounts:)
  let tokens =
    list.map(accounts, fn(account) {
      let login =
        login_client.sts_login(
          ports: login_support.ports(started),
          name: account.login_name,
          password: account.password,
          seed: account.seed,
        )
      login.token
    })
  assert list.length(tokens) == 2
  assert set.size(set.from_list(tokens)) == 2
    as "each login was its own account's, with its own game token"
  login_support.stop(started)
}
