//// The rate bucket every client connection rule keeps
//// (`genesis_prime/client_connection.bucket`) and the buckets the server
//// starts with. Expected values come from these places.
//// - The bucket's rule: a bucket holds at least one request or frame and
////   fills by at least one a second, and frames that wait for an ask are
////   counted only when the ask is answered, so a client that sends at the
////   rate through the rule's longest wait sends `per_second` times that wait
////   in seconds, rounded up, and the burst must hold it.
//// - The rules' longest waits, in their doc comments: STS one ask; auth two
////   asks in a row; game two asks in a row and five claim retries of 100 ms.

import character_tables
import envoy
import genesis_prime
import genesis_prime/client_connection.{
  BurstBelowOne, BurstBelowWait, PerSecondBelowOne,
}
import owned_test

pub fn a_bucket_that_holds_less_than_one_or_never_fills_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_connection.bucket(burst: 0, per_second: 5, longest_wait_ms: 0)
    == Error(BurstBelowOne(0))
    as "a bucket of 0 refuses every client"
  assert client_connection.bucket(burst: -3, per_second: 5, longest_wait_ms: 0)
    == Error(BurstBelowOne(-3))
  assert client_connection.bucket(burst: 5, per_second: 0, longest_wait_ms: 0)
    == Error(PerSecondBelowOne(0))
    as "a bucket that fills by 0 a second refuses every client once its burst is spent"
  assert client_connection.bucket(burst: 5, per_second: -1, longest_wait_ms: 0)
    == Error(PerSecondBelowOne(-1))
  let assert Ok(bucket) =
    client_connection.bucket(burst: 1, per_second: 1, longest_wait_ms: 0)
    as "one and one a second are the least a bucket may be"
  assert client_connection.burst(bucket) == 1
  assert client_connection.per_second(bucket) == 1
}

pub fn a_burst_below_what_a_client_sends_at_the_rate_through_the_longest_wait_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  // 4 a second through 5 s is 20 frames.
  assert client_connection.bucket(
      burst: 19,
      per_second: 4,
      longest_wait_ms: 5000,
    )
    == Error(BurstBelowWait(burst: 19, needed: 20))
  let assert Ok(_) =
    client_connection.bucket(burst: 20, per_second: 4, longest_wait_ms: 5000)
    as "20 holds what a client sending at the rate sends in 5 s"
  // 3 a second through 5.001 s is 15.003 frames, so 16 are sent.
  assert client_connection.bucket(
      burst: 15,
      per_second: 3,
      longest_wait_ms: 5001,
    )
    == Error(BurstBelowWait(burst: 15, needed: 16))
    as "a part of a frame is a frame the client may send"
}

pub fn each_rules_bucket_in_the_servers_settings_holds_what_a_client_sends_at_the_rate_through_its_longest_wait_test() -> Nil {
  use <- owned_test.run(10_000)
  // The settings read these two variables, which the test gives values; a
  // server that is started sets them for real.
  envoy.set("GENESIS_GAME_ADDRESS", "127.0.0.1")
  envoy.set("GENESIS_REALM_NAME", "Test")
  let settings = genesis_prime.settings(tables: character_tables.shared())
  let sts = settings.login.sts.settings
  let auth = settings.login.auth.settings
  let game = settings.game.settings
  // The waits are the rules' own: see their doc comments.
  let sent_through = fn(rate, wait_ms) {
    { client_connection.per_second(rate) * wait_ms + 999 } / 1000
  }
  assert client_connection.burst(sts.rate)
    >= sent_through(sts.rate, sts.ask_deadline_ms)
    as "STS makes one ask at a time"
  assert client_connection.burst(auth.rate)
    >= sent_through(auth.rate, 2 * auth.ask_deadline_ms)
    as "auth asks the hand-off twice in a row"
  assert client_connection.burst(game.rate)
    >= sent_through(game.rate, 2 * game.ask_deadline_ms + 5 * 100)
    as "game asks twice in a row, and a Sessions that is not running is claimed from five times, 100 ms apart"
}
