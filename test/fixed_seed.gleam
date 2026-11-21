//// The seeds of the connections of a whole-server test: each connection the
//// test's listeners accept is given a seed derived from the test's name, so
//// a run rolls the same dice every time and a failure repeats exactly.
////
//// ```
//// test name ──────────────┐
//// GENESIS_TEST_SEED_SALT ─┤ SHA-256 ─▶ the connection's seed
//// the seed's name ────────┤   (the nth connection of the listener, 1 first)
//// listener, ordinal ──────┘
//// ```
////
//// - A listener's scripts are the server's own with the seed replaced
////   (`genesis_prime/connection/script`), so no rule or shell knows a test runs.
//// - `seeded` puts this on the sts, auth and game listeners of a tree's settings;
////   `login_support` does it wherever it makes settings, so a whole-server test is
////   on fixed seeds without asking.
//// - The seed is the 32 bytes of SHA-256 over the string "genesis-prime fixed seed",
////   the test's name (`module:function`, as `owned_test` names its body), the salt,
////   the seed's name, the listener (`sts`, `auth` or `game`) and the ordinal (64
////   bits), each followed by one 0x00 but the ordinal. A name, a variable value or a
////   listener cannot hold a 0x00, so no two sets of parts give one text.
//// - The salt is `GENESIS_TEST_SEED_SALT`, empty when unset. `dev/repeat_tests.py`
////   gives each of its runs a salt of its own, so a test that depends on a roll
////   still fails in the pull request's repeat job; a person tries one with
////   `GENESIS_TEST_SEED_SALT=any_word gleam test -- test/FILE.gleam` (a sweep of
////   `game_wire_test` takes about 45 seconds a salt), and runs the failing salt again
////   to see the same dice.
//// - A test that needs other rolls than its name gives calls `name_the_seed` at the
////   top of its body, with its reason in a comment beside the call.
//// - Renaming a test changes its seeds; so does connecting its clients in another
////   order, since a listener numbers connections in the order it is asked for
////   scripts (`game_client.connect` returns after the hello, so a test that
////   connects its clients one after the other has a fixed order).
//// - The scripts are built in the test body, which holds the name (`enter`, called by
////   `owned_test`), or in a node a test started, which holds it in
////   GENESIS_TEST_NAME (`node_environment`, passed by the helpers that start nodes);
////   anywhere else they panic naming the cause. A node prints each seed it issues as
////   a line starting `seed `; a test body's seeds are told to the log of its
////   `owned_test.run`, which prints them when the body fails and drops them when it
////   ends.
//// - The live server does not use this: `genesis_prime.run` keeps the operating
////   system's source.

import envoy
import genesis_prime/connection/script.{type Scripts, Issued, Script}
import genesis_prime/seed.{type Seed}
import genesis_prime/server.{type Served, type Settings, Login, Served, Settings}
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The variable that changes every seed of a run: empty when unset.
pub const salt_variable = "GENESIS_TEST_SEED_SALT"

/// The variable that carries a test's name to a node the test starts, which has
/// no test body of its own.
pub const test_variable = "GENESIS_TEST_NAME"

/// Where a test body's seed lines are told, until its `owned_test.run` ends.
pub type Log

/// What a process that builds scripts holds: the name and salt its seeds are
/// derived from, the name the body gave its seeds, and where each seed issued is
/// told (a node has no log and prints its lines).
type Body {
  Body(name: String, salt: String, seed_name: String, log: Option(Log))
}

/// The seed of the `ordinal`th connection (1 first) of the listener `listener`, for
/// the test named `name`, under `salt` and `seed_name`: the 32 bytes of the SHA-256
/// of the parts, so two connections never share a seed and nothing tells of another.
pub fn seed_of(
  name name: String,
  salt salt: String,
  seed_name seed_name: String,
  listener listener: String,
  ordinal ordinal: Int,
) -> Seed {
  let assert Ok(made) =
    seed.from_bytes(
      crypto.hash(crypto.Sha256, <<
        "genesis-prime fixed seed":utf8,
        0,
        name:utf8,
        0,
        salt:utf8,
        0,
        seed_name:utf8,
        0,
        listener:utf8,
        0,
        ordinal:size(64),
      >>),
    )
    as "SHA-256 gives the 32 bytes of a seed"
  made
}

/// The salt of this run: the value of `salt_variable`, empty when unset.
pub fn salt() -> String {
  result.unwrap(envoy.get(salt_variable), "")
}

/// The scripts of one listener: those of `over` with each seed derived from the
/// calling test's name. The calling process must be a test body, or a node that
/// holds `test_variable`; the count of connections starts at 1 here.
pub fn scripts(listener listener: String, over over: Scripts) -> Scripts {
  let body = current()
  let counter = new_counter()
  fn() {
    use issued <- result.map(over())
    let ordinal = next(counter)
    let seed =
      seed_of(
        name: body.name,
        salt: body.salt,
        seed_name: body.seed_name,
        listener:,
        ordinal:,
      )
    told(
      body.log,
      "connection "
        <> int.to_string(ordinal)
        <> " of the "
        <> listener
        <> " listener: "
        <> bit_array.base16_encode(seed.bytes(seed)),
    )
    Issued(..issued, script: Script(..issued.script, seed:))
  }
}

/// The settings with the sts, auth and game listeners handing each connection
/// a derived seed, over the scripts each already has.
pub fn seeded(settings settings: Settings) -> Settings {
  Settings(
    ..settings,
    login: Login(
      sts: seeded_listener(settings.login.sts, "sts"),
      auth: seeded_listener(settings.login.auth, "auth"),
    ),
    game: seeded_listener(settings.game, "game"),
  )
}

fn seeded_listener(served: Served(a), listener: String) -> Served(a) {
  Served(..served, scripts: scripts(listener:, over: served.scripts))
}

/// Gives the seeds of the calling test body another name, so its connections
/// roll other dice than the ones its own name gives. Called at the top of the
/// body, before its tree starts, with the reason the default rolls do not
/// serve in a comment beside the call.
pub fn name_the_seed(name name: String) -> Nil {
  let body = current()
  put_body(body.name, Body(..body, seed_name: name))
  case body.log {
    Some(log) -> log_seed_name(log, name)
    None -> Nil
  }
}

/// Makes the calling process the body of the test `name`, under `salt`, with its
/// seeds told to `log`.
pub fn enter(name name: String, salt salt: String, log log: Log) -> Nil {
  put_body(name, Body(name:, salt:, seed_name: "", log: Some(log)))
}

/// An empty log for a test body's seed lines.
@external(erlang, "fixed_seed_ffi", "new_log")
pub fn new_log() -> Log

/// Drops the log: a seed told to it afterwards is told to nothing.
@external(erlang, "fixed_seed_ffi", "drop_log")
pub fn drop_log(log log: Log) -> Nil

/// The text a failed body's report ends with: the name, the salt and the seed name
/// its seeds were made under, the command that repeats the run, and each seed in
/// the order issued. Empty when no connection took a seed.
pub fn report(log log: Log, name name: String, salt salt: String) -> String {
  let #(seed_name, lines) = log_contents(log)
  case lines {
    [] -> ""
    _ ->
      string.join(
        [
          "the seeds of the connections of " <> name <> ":",
          "  "
            <> salt_variable
            <> ": "
            <> case salt {
            "" -> "unset"
            _ -> salt
          },
          "  seed name: "
            <> case seed_name {
            "" -> "none"
            _ -> seed_name
          },
          "  repeat it: "
            <> case salt {
            "" -> ""
            _ -> salt_variable <> "=" <> salt <> " "
          }
            <> "gleam test -- "
            <> test_file_of(name),
          ..lines
        ],
        "\n",
      )
  }
}

/// The file of the test `module:function` names.
fn test_file_of(name: String) -> String {
  let module = case string.split_once(name, ":") {
    Ok(#(module, _function)) -> module
    Error(Nil) -> name
  }
  "test/" <> string.replace(module, "@", "/") <> ".gleam"
}

/// The name of the test the calling process is the body of, or of the test that
/// started this node.
pub fn test_name() -> String {
  current().name
}

fn current() -> Body {
  case get_body() {
    Ok(body) -> body
    Error(Nil) ->
      case envoy.get(test_variable) {
        Ok(name) -> Body(name:, salt: salt(), seed_name: "", log: None)
        Error(Nil) ->
          panic as "no test name for the seeds: build the settings inside the test body (owned_test.run) or in a node that holds GENESIS_TEST_NAME"
      }
  }
}

/// Tells one seed line: to the body's log, or by printing it in a node.
fn told(log: Option(Log), line: String) -> Nil {
  case log {
    Some(log) -> log_line(log, line)
    None -> io.println("seed " <> line)
  }
}

type Counter

@external(erlang, "fixed_seed_ffi", "put_body")
fn put_body(name: String, body: Body) -> Nil

@external(erlang, "fixed_seed_ffi", "get_body")
fn get_body() -> Result(Body, Nil)

@external(erlang, "fixed_seed_ffi", "new_counter")
fn new_counter() -> Counter

@external(erlang, "fixed_seed_ffi", "next")
fn next(counter: Counter) -> Int

@external(erlang, "fixed_seed_ffi", "log_line")
fn log_line(log: Log, line: String) -> Nil

@external(erlang, "fixed_seed_ffi", "log_seed_name")
fn log_seed_name(log: Log, name: String) -> Nil

@external(erlang, "fixed_seed_ffi", "log_contents")
fn log_contents(log: Log) -> #(String, List(String))
