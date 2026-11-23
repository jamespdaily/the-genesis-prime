//// The seeds `fixed_seed` gives the connections of a whole-server test. A seed's
//// value is `fixed_seed`'s own derivation, so no test holds a seed's digits: the
//// tests hold what the derivation must keep (the same parts give the same seed, any
//// other part gives another) and that each listener's scripts take the seed of
//// their own parts, compared with `seed_of`.
//// A test that builds a tree's scripts runs its body under a salt of its own
//// (`owned_test.run_under_salt`), so its seeds do not change when a sweep sets
//// GENESIS_TEST_SEED_SALT for the run.

import ask_support
import envoy
import fixed_seed
import fresh_node
import genesis_prime/connection/script.{type Scripts, Issued, Script}
import genesis_prime/seed
import genesis_prime/server.{type Settings}
import genesis_prime/step.{Now}
import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import login_support
import open_wait
import owned_test
import pog
import qcheck
import serving_node

/// The scripts a listener wraps in these tests: its own clock and timers (planted),
/// the seed 9 repeated, and the ordinal it was given.
fn planted_script() -> script.Script {
  let assert Ok(planted) =
    seed.from_bytes(bit_array.concat(list.repeat(<<9>>, seed.byte_count)))
    as "32 bytes are a seed"
  Script(
    seed: planted,
    clock: fn(_input) { Now(monotonic_ms: 4242, filetime: 7) },
    node_monotonic_ms: fn(_now) { 4243 },
    schedule: fn(_subject, _timer, _reference, _after_ms) { fn() { Nil } },
    next_read: fn() { None },
  )
}

/// Scripts that hand out the planted script, always with the ordinal 41.
fn planted_scripts() -> Scripts {
  fn() { Ok(Issued(ordinal: 41, script: planted_script())) }
}

/// The seed of the script `scripts` hands out next, as the 64 hex digits the failure
/// report prints.
fn next_seed_of(scripts: Scripts) -> String {
  let assert Ok(issued) = scripts() as "the scripts hand out a script"
  bit_array.base16_encode(seed.bytes(issued.script.seed))
}

/// The seed of a connection of the test `test`, under the salt "s", as the 64 hex
/// digits `next_seed_of` gives: what `seed_of` makes of its five parts.
fn seed_hex_of(
  test_name test_name: String,
  seed_name seed_name: String,
  listener listener: String,
  ordinal ordinal: Int,
) -> String {
  bit_array.base16_encode(
    seed.bytes(fixed_seed.seed_of(
      name: "fixed_seed_test:" <> test_name,
      salt: "s",
      seed_name:,
      listener:,
      ordinal:,
    )),
  )
}

/// Runs `body` as a test body under the salt "s".
fn under_salt_s(body: fn() -> a) -> a {
  owned_test.run_under_salt(salt: "s", timeout_ms: 60_000, body:)
}

// ---- the derivation ----

/// The five parts of a seed.
type Parts {
  Parts(
    name: String,
    salt: String,
    seed_name: String,
    listener: String,
    ordinal: Int,
  )
}

fn seed_of_parts(parts: Parts) -> BitArray {
  seed.bytes(fixed_seed.seed_of(
    name: parts.name,
    salt: parts.salt,
    seed_name: parts.seed_name,
    listener: parts.listener,
    ordinal: parts.ordinal,
  ))
}

fn parts_generator() -> qcheck.Generator(Parts) {
  let text = qcheck.string_from(qcheck.alphanumeric_ascii_codepoint())
  qcheck.map(
    qcheck.tuple3(
      qcheck.tuple3(text, text, text),
      qcheck.from_generators(qcheck.return("sts"), [
        qcheck.return("auth"),
        qcheck.return("game"),
      ]),
      qcheck.bounded_int(from: 1, to: 1000),
    ),
    fn(made) {
      let #(#(name, salt, seed_name), listener, ordinal) = made
      Parts(name:, salt:, seed_name:, listener:, ordinal:)
    },
  )
}

pub fn the_same_parts_give_the_same_seed_and_any_other_parts_another_test() -> Nil {
  use <- owned_test.run(60_000)
  // The second set of parts is the first with its name and salt cut at another
  // place: the text that joins them is the same, so only the separator tells them
  // apart ("ab", "c" against "a", "bc").
  use #(first, second, cut) <- qcheck.given(qcheck.tuple3(
    parts_generator(),
    parts_generator(),
    qcheck.bounded_int(from: 0, to: 40),
  ))
  assert seed_of_parts(first) == seed_of_parts(first)
    as "the same parts give the same seed, so a failure's seeds can be made again"
  assert first == second || seed_of_parts(first) != seed_of_parts(second)
    as "two different sets of parts give two different seeds, so no two connections share their dice"
  let one_part_other = [
    #("the name", Parts(..first, name: second.name)),
    #("the salt", Parts(..first, salt: second.salt)),
    #("the seed name", Parts(..first, seed_name: second.seed_name)),
    #("the listener", Parts(..first, listener: second.listener)),
    #("the ordinal", Parts(..first, ordinal: second.ordinal)),
  ]
  list.each(one_part_other, fn(row) {
    let #(part, other) = row
    assert other == first || seed_of_parts(first) != seed_of_parts(other)
      as {
        "parts that differ in " <> part <> " alone give two different seeds"
      }
  })
  let joined = first.name <> first.salt
  let cut_at = fn(at) {
    Parts(
      ..first,
      name: string.slice(joined, 0, at),
      salt: string.drop_start(joined, at),
    )
  }
  assert cut >= string.length(joined)
    || seed_of_parts(cut_at(cut)) != seed_of_parts(cut_at(cut + 1))
    as "the same text cut at two places gives two seeds: the 0x00 between the parts cannot be moved"
}

// ---- the scripts of one listener ----

pub fn a_listeners_scripts_number_its_connections_from_1_and_keep_the_rest_of_the_script_test() -> Nil {
  use <- owned_test.run(10_000)
  let given = process.new_subject()
  process.send(given, Ok(Issued(ordinal: 41, script: planted_script())))
  process.send(given, Ok(Issued(ordinal: 42, script: planted_script())))
  process.send(given, Error(Nil))
  process.send(given, Ok(Issued(ordinal: 43, script: planted_script())))
  let scripts =
    under_salt_s(fn() {
      fixed_seed.scripts(listener: "game", over: fn() {
        let assert Ok(next) = process.receive(given, 0)
          as "the test planted four results"
        next
      })
    })
  let planted = planted_script()
  let handed = [scripts(), scripts(), scripts(), scripts()]
  let assert [Ok(first), Ok(second), Error(Nil), Ok(third)] = handed
    as "an Error from the wrapped scripts passes through"
  assert [first.ordinal, second.ordinal, third.ordinal] == [41, 42, 43]
    as "the ordinal of the wrapped script is the script's own"
  assert list.map([first, second, third], fn(issued) {
      bit_array.base16_encode(seed.bytes(issued.script.seed))
    })
    == list.map([1, 2, 3], fn(ordinal) {
      seed_hex_of(
        test_name: "a_listeners_scripts_number_its_connections_from_1_and_keep_the_rest_of_the_script_test",
        seed_name: "",
        listener: "game",
        ordinal:,
      )
    })
    as "the seeds are those of ordinals 1, 2 and 3: the Error took no ordinal"
  assert list.all([first, second, third], fn(issued) {
    Script(..issued.script, seed: planted.seed) == planted
  })
    as "the clock, the node's reading, the scheduler and the read size are the wrapped script's"
}

/// The ordinals 1 to 20.
fn connections() -> List(Int) {
  list.reverse(
    int.range(from: 1, to: 21, with: [], run: fn(all, ordinal) {
      [ordinal, ..all]
    }),
  )
}

pub fn a_listener_counts_connections_taken_in_other_processes_test() -> Nil {
  use <- owned_test.run(60_000)
  let scripts =
    under_salt_s(fn() {
      fixed_seed.scripts(listener: "game", over: planted_scripts())
    })
  let taken = process.new_subject()
  connections()
  |> list.each(fn(_connection) {
    process.spawn(fn() { process.send(taken, next_seed_of(scripts)) })
  })
  let seeds =
    connections()
    |> list.map(fn(_connection) {
      open_wait.received(from: taken, what: "a connection's seed")
    })
  let wanted =
    connections()
    |> list.map(fn(ordinal) {
      seed_hex_of(
        test_name: "a_listener_counts_connections_taken_in_other_processes_test",
        seed_name: "",
        listener: "game",
        ordinal:,
      )
    })
  assert list.sort(seeds, string.compare) == list.sort(wanted, string.compare)
    as "20 connections that take their scripts at once get the seeds of ordinals 1 to 20, each once"
}

pub fn scripts_built_where_no_test_name_is_held_refuse_naming_the_cause_test() -> Nil {
  use <- owned_test.run(10_000)
  assert envoy.get(fixed_seed.test_variable) == Error(Nil)
    as "GENESIS_TEST_NAME is set in this shell: unset it, it names a node's test"
  let ended =
    ask_support.ended_running(fn() {
      let _scripts =
        fixed_seed.scripts(listener: "game", over: planted_scripts())
      Nil
    })
  assert string.contains(
    ask_support.panic_message(ask_support.raised(ended)),
    "no test name for the seeds: build the settings inside the test body",
  )
    as "a process that is no test body and holds no name panics naming the cause"
}

pub fn a_test_that_names_its_seed_gets_other_seeds_than_its_name_gives_test() -> Nil {
  use <- owned_test.run(60_000)
  let game_seed = fn(scripts: fn() -> Scripts) { next_seed_of(scripts()) }
  let named =
    under_salt_s(fn() {
      fixed_seed.name_the_seed(name: "x")
      game_seed(fn() {
        fixed_seed.scripts(listener: "game", over: planted_scripts())
      })
    })
  let unnamed =
    under_salt_s(fn() {
      game_seed(fn() {
        fixed_seed.scripts(listener: "game", over: planted_scripts())
      })
    })
  let of_seed_name = fn(seed_name) {
    seed_hex_of(
      test_name: "a_test_that_names_its_seed_gets_other_seeds_than_its_name_gives_test",
      seed_name:,
      listener: "game",
      ordinal: 1,
    )
  }
  assert named == of_seed_name("x") as "the seed name x is a part of the seed"
  assert unnamed == of_seed_name("")
    as "a body of another run that names nothing has the seeds its name gives"
  assert named != unnamed
    as "a test that names its seed gets other seeds than its name gives"
  let ended =
    ask_support.ended_running(fn() {
      under_salt_s(fn() {
        fixed_seed.name_the_seed(name: "x")
        let _seed =
          next_seed_of(fixed_seed.scripts(
            listener: "game",
            over: planted_scripts(),
          ))
        panic as "the planted crash of the body"
      })
    })
  assert string.ends_with(
    ask_support.panic_message(ask_support.raised(ended)),
    string.join(
      [
        "the seeds of the connections of fixed_seed_test:a_test_that_names_its_seed_gets_other_seeds_than_its_name_gives_test:",
        "  GENESIS_TEST_SEED_SALT: s",
        "  seed name: x",
        "  repeat it: GENESIS_TEST_SEED_SALT=s gleam test -- test/fixed_seed_test.gleam",
        "connection 1 of the game listener: " <> named,
      ],
      "\n",
    ),
  )
    as "a failure report says which seed name its seeds were made under"
}

// ---- the tree's settings ----

fn tree_settings() -> Settings {
  serving_node.real_settings(pool: pog.default_config(process.new_name("pool")))
}

pub fn the_trees_settings_seed_the_sts_auth_and_game_listeners_each_on_its_own_test() -> Nil {
  use <- owned_test.run(60_000)
  let makers = [
    #("serving_node.real_settings", tree_settings),
    #("login_support.servers_settings", login_support.servers_settings),
  ]
  let first_seeds =
    under_salt_s(fn() {
      list.map(makers, fn(maker) {
        let settings = { maker.1 }()
        #(maker.0, [
          #("sts", next_seed_of(settings.login.sts.scripts)),
          #("auth", next_seed_of(settings.login.auth.scripts)),
          #("game", next_seed_of(settings.game.scripts)),
        ])
      })
    })
  use #(maker, listeners) <- list.each(first_seeds)
  assert listeners
    == list.map(["sts", "auth", "game"], fn(listener) {
      #(
        listener,
        seed_hex_of(
          test_name: "the_trees_settings_seed_the_sts_auth_and_game_listeners_each_on_its_own_test",
          seed_name: "",
          listener:,
          ordinal: 1,
        ),
      )
    })
    as {
      maker
      <> ": each listener's first connection takes the seed of its listener and ordinal 1"
    }
}

// ---- a node the test starts ----

pub fn a_fresh_node_a_test_starts_holds_the_tests_name_test() -> Nil {
  use <- owned_test.run(60_000)
  fresh_node.must_return(
    module: "fixed_seed_test",
    function: "name_in_a_fresh_node",
  )
}

/// Run in a fresh node, which the test started.
pub fn name_in_a_fresh_node() -> Nil {
  assert fixed_seed.test_name()
    == "fixed_seed_test:a_fresh_node_a_test_starts_holds_the_tests_name_test"
    as "the node holds the name of the test that started it, so the settings it builds are seeded"
}

pub fn a_fresh_node_gets_the_seeds_of_the_body_that_started_it_test() -> Nil {
  use <- owned_test.run(180_000)
  let rows = [
    #("the body names no seed", "", "s"),
    #("the body names its seed", "x", "s"),
    #("the body is under another salt", "x", "t"),
  ]
  use #(reason, seed_name, salt) <- list.each(rows)
  owned_test.run_under_salt(salt:, timeout_ms: 100_000, body: fn() {
    case seed_name {
      "" -> Nil
      _ -> fixed_seed.name_the_seed(name: seed_name)
    }
    let game_seed = fn() {
      next_seed_of(fixed_seed.scripts(listener: "game", over: planted_scripts()))
    }
    let in_main = game_seed()
    fresh_node.must_return_function(fn() {
      assert game_seed() == in_main
        as {
          reason
          <> ": the node issues the seed the main VM issues for the same name, seed name and salt"
        }
    })
  })
}
