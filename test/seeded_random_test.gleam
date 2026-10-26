//// The seeded random source of the dev start. The expected values are the
//// issue's test 1 and the reason for the source: a recorded session can be
//// played again only if a server started with the same seed draws the same
//// SRP secrets and session keys in the same order, and another seed draws
//// others. A "server" here is the login's own draws, taken the way a running
//// login takes them: the STS connection's secret (32 bytes,
//// `sts_connection.Services.draw_secret`) and the one-time keys of the two
//// hand-offs (16 bytes each, `handoff.issue`: the game token of the STS login
//// and the session key of the auth login), all from the one source the
//// settings give.

import genesis_prime/login/account.{Identity}
import genesis_prime/login/guid
import genesis_prime/login/handoff
import genesis_prime/login/random_source.{type RandomSource}
import genesis_prime/login/sts_connection
import genesis_prime/seeded_random
import gleam/bit_array
import gleam/erlang/process
import gleam/list
import gleam/otp/static_supervisor
import owned_test
import pog

/// How many logins' draws a server makes in these tests.
const logins = 3

/// The draws of `logins` logins on a server seeded with `seed`, in the order a
/// login makes them: the secret, the game token, the session key.
fn draws_of_a_server_seeded_with(seed: Int) -> List(BitArray) {
  let source_name = process.new_name("seeded_source")
  let game_tokens = process.new_name("seeded_game_tokens")
  let session_keys = process.new_name("seeded_session_keys")
  let random = seeded_random.source(source_name)
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(seeded_random.supervised(name: source_name, seed:))
    |> static_supervisor.add(handoff.supervised(hand_off(game_tokens, random)))
    |> static_supervisor.add(handoff.supervised(hand_off(session_keys, random)))
    |> static_supervisor.start
    as "the seeded server's processes did not start"
  let services =
    sts_connection.services(
      // The STS services hold a connection to the database for the lookups of
      // accounts; no draw uses it.
      connection: pog.named_connection(process.new_name("seeded_unused_pool")),
      game_tokens:,
      random:,
    )
  let assert Ok(user_id) = guid.from_wire(<<0:size(128)>>) as "16 bytes"
  let identity = Identity(id: 7, name: "jim", user_id:)
  list.flat_map(list.repeat(Nil, logins), fn(_login) {
    let secret = services.draw_secret()
    let token = services.issue_game_token(identity)
    let key = handoff.issue(session_keys, identity)
    [secret, token, key]
  })
}

fn hand_off(
  name: process.Name(handoff.Message(account.Identity)),
  random: RandomSource,
) -> handoff.Settings(account.Identity) {
  handoff.Settings(
    name:,
    expiry_milliseconds: 60_000,
    clock: fn() { 0 },
    random:,
  )
}

pub fn two_servers_started_with_one_seed_draw_the_same_secrets_and_session_keys_in_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let first = draws_of_a_server_seeded_with(72)
  let second = draws_of_a_server_seeded_with(72)
  assert list.map(first, bit_array.bit_size)
    == [256, 128, 128, 256, 128, 128, 256, 128, 128]
    as "a secret is 32 bytes and a game token or session key is 16, three logins in order"
  assert first == second
    as "one seed gives one sequence of draws, in the order the login takes them"
  assert list.unique(first) == first as "no draw of one server repeats another"
}

pub fn a_server_started_with_another_seed_draws_other_secrets_and_session_keys_test() -> Nil {
  use <- owned_test.run(10_000)
  let first = draws_of_a_server_seeded_with(72)
  let other = draws_of_a_server_seeded_with(73)
  assert list.map2(first, other, fn(draw, another) { draw == another })
    |> list.all(fn(same) { !same })
    as "every draw of another seed differs from the draw at the same place"
}
