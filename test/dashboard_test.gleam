//// The dashboard as a whole, on a free loopback port. Expected values are the
//// rules of a page that holds a key: the start prints the key once and logs it
//// never, the listener is bound to the loopback address only, and a websocket
//// handshake with no key is answered 400, also when the first ask of the
//// page's runtime was answered 503, and the runtime it started ends.

import dashboard_support
import event_wait
import genesis_prime/dashboard
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import open_wait
import owned_test
import simplifile

fn started(settings: dashboard.Settings) -> dashboard.Running {
  let assert Ok(running) = dashboard.start(settings)
    as "the dashboard did not start"
  running
}

fn plant_logs(
  home home: String,
  updater updater: String,
  launchd launchd: String,
) -> Nil {
  let assert Ok(Nil) = simplifile.write(home <> "/play-service.log", updater)
  let assert Ok(Nil) =
    simplifile.write(home <> "/play-service.launchd.log", launchd)
  Nil
}

pub fn the_start_report_prints_the_key_once_and_logs_it_never_test() -> Nil {
  use <- owned_test.run(5000)
  let gate = dashboard_support.gate()
  let report = dashboard.start_report(gate)
  assert string.contains(
    report.print_line,
    "http://127.0.0.1:7700/k/" <> dashboard_support.key <> "/",
  )
  assert report.log_lines != [] as "the start logs that it serves"
  list.each(report.log_lines, fn(line) {
    assert !string.contains(line, dashboard_support.key)
      as "a log line holds the key"
  })
}

pub fn the_dashboard_binds_the_loopback_address_only_test() -> Nil {
  use <- owned_test.run(5000)
  use home <- dashboard_support.with_home
  let settings = dashboard_support.settings(home)
  let _running = started(settings)
  assert dashboard_support.accepts(settings.port)
  // A socket bound to every address would show 0.0.0.0, and one bound to the
  // machine's network address that address.
  assert dashboard_support.bound_addresses(settings.port) == ["127.0.0.1"]
}

pub fn a_handshake_with_no_key_is_answered_400_when_its_first_ask_is_answered_503_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  plant_logs(home:, updater: "one\n", launchd: "alpha\n")
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)
  let answers = process.new_subject()

  // The factory holds the first ask and dies with it waiting: that ask is
  // answered 503, and the call under test asks again.
  dashboard_support.with_factory_held(
    runtimes: running.runtimes,
    during: fn(start_asked) {
      let _asking =
        process.spawn(fn() {
          let #(connection, reply) =
            dashboard_support.handshake_without_key(
              port: settings.port,
              path: "/k/" <> key <> "/ws",
              headers: [
                #("Origin", "http://127.0.0.1:" <> int.to_string(settings.port)),
                ..dashboard_support.browser(port: settings.port)
              ],
            )
          dashboard_support.close(connection)
          process.send(answers, reply.status)
        })
      start_asked()
      dashboard_support.kill_factory(running.runtimes)
    },
  )
  assert open_wait.received(from: answers, what: "the call's answer") == 400
  event_wait.until("the runtime of the refused handshake to end", fn() {
    dashboard.runtime_count(running) == 0
  })
}
