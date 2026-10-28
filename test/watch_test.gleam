//// The watches a shell keeps for its rule (`genesis_prime/step/watch`).
//// Expected values come from the module's doc comment, as approved on the one
//// login per account card: a watched process's end gives the id of its watch
//// once, an address no process holds ends the watch at once, a closed watch
//// gives nothing, and an id already open ends the process with an error log.
//// The test process is the shell: its monitors' DOWNs arrive in its mailbox.

import ask_support
import genesis_prime/step.{WatchId}
import genesis_prime/step/watch
import gleam/erlang/process.{type Monitor, type Pid}
import gleam/string
import log_capture
import owned_test
import socket_watch

fn a_process() -> Pid {
  process.spawn_unlinked(process.sleep_forever)
}

/// Waits for the next DOWN in the mailbox and gives its monitor.
fn next_down() -> Monitor {
  let assert Ok(process.ProcessDown(monitor:, ..)) =
    process.new_selector()
    |> process.select_monitors(fn(down) { down })
    |> process.selector_receive(within: ask_support.event_wait_ms)
    as "a monitored process ended"
  monitor
}

pub fn a_watched_process_that_ends_gives_its_watchs_id_once_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = a_process()
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(1),
      target: Ok(target),
      shell: "test shell",
    )
  process.kill(target)
  let monitor = next_down()
  let assert Ok(#(WatchId(1), watches)) = watch.ended(watches:, monitor:)
    as "the DOWN's monitor is watch 1's"
  assert watch.ended(watches:, monitor:) == Error(Nil)
    as "the watch is forgotten, so it ends once"
}

pub fn a_watch_on_no_process_ends_at_once_test() -> Nil {
  use <- owned_test.run(30_000)
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(2),
      target: Error(Nil),
      shell: "test shell",
    )
  let monitor = next_down()
  let assert Ok(#(WatchId(2), _)) = watch.ended(watches:, monitor:)
    as "an address no process holds comes back as the watch's end"
  Nil
}

pub fn a_closed_watch_gives_no_end_and_a_monitor_held_under_no_watch_gives_none_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = a_process()
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(3),
      target: Ok(target),
      shell: "test shell",
    )
  let watches = watch.close(watches:, watch: WatchId(3))
  let ours = process.monitor(target)
  process.kill(target)
  assert next_down() == ours
    as "the one DOWN waiting is the test's own: the closed watch's was dropped"
  assert socket_watch.mailbox_length(process.self()) == 0
    as "and none other follows"
  assert watch.ended(watches:, monitor: ours) == Error(Nil)
    as "a monitor held under no watch is no watch's end"
  assert watch.close(watches:, watch: WatchId(9)) == watches
    as "closing an id with no open watch does nothing"
}

pub fn a_watch_id_already_open_ends_the_process_with_an_error_log_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = a_process()
  let ready = process.new_subject()
  let opener =
    process.spawn_unlinked(fn() {
      let go = process.new_subject()
      process.send(ready, go)
      process.receive_forever(go)
      let watches =
        watch.open(
          watches: watch.new(),
          watch: WatchId(4),
          target: Ok(target),
          shell: "test shell",
        )
      let _again =
        watch.open(
          watches:,
          watch: WatchId(4),
          target: Ok(target),
          shell: "test shell",
        )
      Nil
    })
  let assert Ok(go) = process.receive(ready, within: ask_support.event_wait_ms)
    as "the process started"
  let logged = process.new_subject()
  let capture = log_capture.start(from: opener, into: logged)
  let ended = process.monitor(opener)
  process.send(go, Nil)
  let assert process.Abnormal(_) = ask_support.ended(ended)
    as "opening an id already open ended the process"
  let assert Ok(#("error", text)) =
    process.receive(logged, within: ask_support.event_wait_ms)
    as "the first thing logged is an error"
  assert string.contains(text, "already open")
    && string.contains(text, "test shell")
    as "it names the open id and the shell that does not carry it out"
  log_capture.stop(capture)
  process.kill(target)
}
