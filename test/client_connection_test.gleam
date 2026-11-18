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
  AskStore, BurstBelowOne, BurstBelowWait, Continue, Done, PerSecondBelowOne,
}
import genesis_prime/connection/closer
import genesis_prime/game/leaving_save.{Retries}
import genesis_prime/group_registry
import genesis_prime/server
import genesis_prime/step.{
  type ConnectionEffect, type Effect, Ask, AskId, Effects, EffectsThenAsk, Log,
  LogInfo, LogLine, Stop,
}
import genesis_prime/store
import genesis_prime/store/worker
import genesis_prime/world_map/registry as world_map_registry
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import spawn_support

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
  let settings =
    genesis_prime.settings(
      tables: character_tables.shared(),
      spawns: spawn_support.key_without_spawns(),
    )
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

pub fn the_production_leaving_save_settings_are_the_approved_ladder_and_the_stop_budget_test() -> Nil {
  use <- owned_test.run(10_000)
  let settings = production_settings()
  assert settings.game.settings.leaving_save
    == Retries(
      within_ms: 20_000,
      waits_ms: [1000, 2000, 4000, 8000],
      then_ms: 10_000,
    )
    as "the server's choice: 1, 2, 4, 8 s then 10 s, 20 s for a logout"
  assert settings.connection_shutdown_ms == 25_000
    as "Ranch's bound on a connection"
  assert settings.stop_reserve_ms == 10_000
    as "the map ask's 5 s, the notice's write and the socket's close (2 s each) and a margin of 1 s"
}

/// The reserve must cover the longest wait the shell can make before it looks
/// at its mailbox, then the closing notice's write and the socket's close.
/// Every call the shell makes that waits for another process is listed here
/// with its bound: a new one is added to the list, or the reserve may not
/// cover it.
pub fn the_stop_reserve_covers_the_longest_synchronous_call_the_shell_makes_and_the_two_writes_after_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let settings = production_settings()
  let game = settings.game.settings
  let synchronous_calls_ms = [
    // directory: AskMap, a call to Maps (world_map_registry.find_or_start)
    #("the map ask finds or starts the map", game.ask_deadline_ms),
    // directory: AskMapRun, a call to Maps (world_map_registry.ask_run)
    #("the map-run ask finds the run", game.ask_deadline_ms),
    // connection_locate: Watch of a map, a call to Maps (find_run)
    #("the map watch finds the run", settings.world.maps_call_ms),
    // directory: AskStore, AskHandOff, AskSessions and every Tell are sends;
    // locate: the registries' lookups read a local table
    #("the sends and the registry lookups", 0),
  ]
  let longest_ms =
    list.fold(synchronous_calls_ms, 0, fn(longest, call) {
      int.max(longest, call.1)
    })
  assert longest_ms == 5000 as "the map ask's and the map watch's 5 s"
  assert settings.stop_reserve_ms
    >= longest_ms + 2 * settings.send_deadline_ms + 1000
    as "a step in progress at the exit's arrival may wait out the longest call; then the notice's write and the socket's close (a send deadline each) and a second"
}

pub fn a_stops_window_is_the_shutdown_less_the_reserve_so_15_seconds_against_a_logouts_20_test() -> Nil {
  use <- owned_test.run(10_000)
  let settings = production_settings()
  // A logout that is begun before a stop keeps its own deadline only until the
  // stop replaces it.
  let window_ms = settings.connection_shutdown_ms - settings.stop_reserve_ms
  assert window_ms == 15_000
    as "the stop's deadline is taken + 15 s, inside Ranch's 25 s"
  assert window_ms < settings.game.settings.leaving_save.within_ms
    as "shorter than a logout's 20 s"
}

pub fn the_login_listeners_have_five_seconds_and_the_stops_bounds_in_order_fit_the_hosts_sixty_seconds_test() -> Nil {
  use <- owned_test.run(10_000)
  let settings = production_settings()
  assert settings.login_connection_shutdown_ms == 5000
    as "a login connection holds no save: a late take and the close (2 + 2 s) fit 5 s"
  // The tree stops its children in reverse start order, and a supervisor's
  // children one after another, so the worst case is every bound waited out in
  // turn (server.start, server.add_world): the closer, the game subtree (the
  // listener's connections, then the connection registry), the login subtree
  // (the auth listener's connections, then the STS listener's), the world
  // subtree (the map supervisor's maps, the creature supervisor's creatures,
  // Maps, the creatures' registry), Sessions, the hand-off, the store's
  // workers. The pool is the tree's first child and stops last, after every
  // save: a kill during its stop loses none, so its bound is not counted. The
  // host stops the service after 60 s (dev/play_service/lib.sh
  // `--stop-timeout 60`).
  let stop_ms =
    [
      closer.shutdown_ms,
      settings.connection_shutdown_ms,
      group_registry.shutdown_ms,
      settings.login_connection_shutdown_ms,
      settings.login_connection_shutdown_ms,
      settings.world.map_shutdown_ms,
      settings.world.creature_shutdown_ms,
      world_map_registry.shutdown_ms,
      group_registry.shutdown_ms,
      settings.sessions_shutdown_ms,
      settings.hand_off_shutdown_ms,
      worker.shutdown_ms,
    ]
    |> int.sum
  assert stop_ms == 55_000 as "2 + 25 + 1 + 5 + 5 + 2 + 2 + 1 + 1 + 5 + 5 + 1 s"
  assert stop_ms < 60_000 as "the host's stop-timeout"
}

fn production_settings() -> server.Settings {
  envoy.set("GENESIS_GAME_ADDRESS", "127.0.0.1")
  envoy.set("GENESIS_REALM_NAME", "Test")
  genesis_prime.settings(
    tables: character_tables.shared(),
    spawns: spawn_support.key_without_spawns(),
  )
}

/// A flow over a session that is its unread bytes, each byte one item. A 1
/// goes on after the log lines "first" and "second"; a 2 asks after its own
/// line "own"; a 3 ends the connection after "own".
fn byte_flow() -> client_connection.Flow(BitArray, Int, Nil, Nil) {
  client_connection.Flow(
    pending: fn(bytes) { bytes },
    take: fn(bytes) {
      case bytes {
        <<>> -> Ok(None)
        <<byte, rest:bytes>> -> Ok(Some(#(byte, rest)))
        _ -> Error(Nil)
      }
    },
    taking: fn(_bytes, byte, rest) {
      case byte {
        1 -> Continue(rest, [a_line("first"), a_line("second")])
        2 -> client_connection.Asking(rest, [a_line("own")], an_ask())
        _ -> Done(rest, [a_line("own"), Stop])
      }
    },
    refused: fn(bytes, _error) { Done(bytes, [Stop]) },
    charged: fn(bytes) { Ok(bytes) },
    connected: fn(_bytes) { Nil },
  )
}

fn a_line(text: String) -> Effect(ConnectionEffect(client_connection.Request)) {
  Log(LogLine(level: LogInfo, text:, about: step.no_one))
}

fn an_ask() -> step.Ask(client_connection.Request) {
  Ask(
    ask: AskId(1),
    request: AskStore(store.Login(store.FindAccount("an-account"))),
    deadline_ms: 100,
  )
}

pub fn the_effects_of_items_before_an_item_that_asks_leave_before_its_own_and_in_the_order_taken_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    client_connection.drive(
      session: <<1, 1, 2, 1>>,
      flow: byte_flow(),
      carried: [],
    )
  assert taken
    == EffectsThenAsk(
      [
        a_line("first"),
        a_line("second"),
        a_line("first"),
        a_line("second"),
        a_line("own"),
      ],
      an_ask(),
    )
    as "drive's contract: each item's effects leave in the order the items came, the asking item's own last, and the item after the ask waits"
}

pub fn the_effects_of_items_before_an_item_that_ends_the_connection_leave_before_its_own_and_in_the_order_taken_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    client_connection.drive(
      session: <<1, 3, 1>>,
      flow: byte_flow(),
      carried: [],
    )
  assert taken
    == Effects([a_line("first"), a_line("second"), a_line("own"), Stop])
    as "drive's contract: the effects of the items before the ending item, then its own, with Stop last"
}
