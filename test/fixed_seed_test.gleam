//// The seeds `fixed_seed` gives the connections of a whole-server test. Every
//// expected seed is the SHA-256 of its parts, written out here as upper-case
//// hex and computed by Python's `hashlib` over
//// `"genesis-prime fixed seed" 0x00 test 0x00 salt 0x00 seed name 0x00 listener 0x00 ordinal:64`
//// (the material the module doc of `fixed_seed` states), never by `fixed_seed`.
//// One exception, named where it is: a test that counts 20 connections compares
//// with `seed_of`, whose vectors the first test holds.
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

/// Runs `body` as a test body under the salt "s".
fn under_salt_s(body: fn() -> a) -> a {
  owned_test.run_under_salt(salt: "s", timeout_ms: 60_000, body:)
}

// ---- the derivation ----

pub fn a_seed_is_the_sha256_of_its_five_parts_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows = [
    #(
      "the base",
      "",
      "",
      "game",
      1,
      "79104566B5F5B4D0BB1ED16AF1A25AD12F956F11E9AED1DA047F9ECB3D6D2647",
    ),
    #(
      "the ordinal differs",
      "",
      "",
      "game",
      2,
      "CE76710EE28778A95F26C15BC1503089DE6D0821F0F2F54245204DFFB97264E7",
    ),
    #(
      "the salt differs",
      "b",
      "",
      "game",
      1,
      "96E0F98DF64BC00E98CDA3C28F8E31C5AE660C742A5421627369B0B153FC6F82",
    ),
    #(
      "the seed name differs",
      "",
      "again",
      "game",
      1,
      "8464EAEDDC33848BBFFF3BA2A8291EF7D98AD0BB56F5A536DFD1DEBD783D2B0C",
    ),
    #(
      "the listener differs",
      "",
      "",
      "auth",
      1,
      "5786A37EEAE27A4FB2F083642EC97FC9D3B5900656B0114F925CA7F5E80264CB",
    ),
  ]
  use #(row, salt, seed_name, listener, ordinal, digest) <- list.each(rows)
  let made =
    fixed_seed.seed_of(
      name: "game_wire_test:a_t",
      salt:,
      seed_name:,
      listener:,
      ordinal:,
    )
  assert bit_array.base16_encode(seed.bytes(made)) == digest
    as { row <> ": the SHA-256 of the five parts, 32 bytes (seed.byte_count)" }
}

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

pub fn a_seed_differs_when_any_one_part_differs_test() -> Nil {
  use <- owned_test.run(60_000)
  // The second set of parts is the first with its name and salt cut at another
  // place: the text that joins them is the same, so only the separator tells them
  // apart ("ab", "c" against "a", "bc").
  use #(first, second, cut) <- qcheck.given(qcheck.tuple3(
    parts_generator(),
    parts_generator(),
    qcheck.bounded_int(from: 0, to: 40),
  ))
  assert first == second || seed_of_parts(first) != seed_of_parts(second)
    as "two different sets of parts give two different seeds, so no two connections share their dice"
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
    == [
      "D04AC470EACB0D459542BA9FCFE129BA733E70CDF7A3DA5F037D925B63C6B454",
      "611BEAF75E52A1EFBF60E1D6B4210649E89692E58B119521B5C9BE3862B738C0",
      "E329ABF05DB24FB83BA2F70165B2B6FD1DC1EDF235F786F6E72F204FCF4CF5C7",
    ]
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
  // `seed_of` is the oracle here: its vectors are the first test's.
  let wanted =
    connections()
    |> list.map(fn(ordinal) {
      bit_array.base16_encode(
        seed.bytes(fixed_seed.seed_of(
          name: "fixed_seed_test:a_listener_counts_connections_taken_in_other_processes_test",
          salt: "s",
          seed_name: "",
          listener: "game",
          ordinal:,
        )),
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
  assert named
    == "794C97FD8C60A0328C0C92B584338E477129A46224BC7CA8AEDBA1C75CE9BECA"
    as "the seed name x is a part of the seed"
  assert unnamed
    == "DB995EA918C3F4B38F81BB9DFA1F800E6F19ABD790D1DD9BEC887B402515A9A8"
    as "a body of another run that names nothing has the seeds its name gives"
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
        "connection 1 of the game listener: 794C97FD8C60A0328C0C92B584338E477129A46224BC7CA8AEDBA1C75CE9BECA",
      ],
      "\n",
    ),
  )
    as "a failure report says which seed name its seeds were made under"
}

// ---- the tree's settings ----

fn tree_settings() -> Settings {
  login_support.settings(pool: pog.default_config(process.new_name("pool")))
}

pub fn the_trees_settings_seed_the_sts_auth_and_game_listeners_each_on_its_own_test() -> Nil {
  use <- owned_test.run(60_000)
  let makers = [
    #("login_support.settings", tree_settings),
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
    == [
      #(
        "sts",
        "2E3D9B9E58C5607EE7410239749AD732617C974DFB6A310BC4A19134F2C89F4C",
      ),
      #(
        "auth",
        "2C7B5D7A292D21F403BABB478F8AC5A94A3EB4ED406A95FF8D30FA704ABE07D1",
      ),
      #(
        "game",
        "513A2B377513635295B16FFBBFE5697D199B09E1FD5490EBEBF36784C9054F84",
      ),
    ]
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
