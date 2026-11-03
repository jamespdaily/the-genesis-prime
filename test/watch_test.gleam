//// The watches a shell keeps for its rule (`genesis_prime/step/watch`).
//// Expected values come from the module's doc comment, as approved on the one
//// login per account card and on the watch order card: a watched process's end
//// gives the id of its watch once, an address no process holds is held to end
//// as the shell's next input, in the order the watches were opened, a closed
//// watch gives nothing, and an id already open, monitored or held, ends the
//// process with an error log. The test process is the shell: its monitors'
//// DOWNs arrive in its mailbox.

import ask_support
import genesis_prime/step.{Map, Sessions, WatchId}
import genesis_prime/step/watch
import genesis_prime/world_map/map_id.{MapId}
import gleam/erlang/process.{type Monitor, type Pid}
import gleam/list
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
      address: Sessions,
      target: Ok(watch.Watched(target)),
      shell: "test shell",
    )
  process.kill(target)
  let monitor = next_down()
  let assert Ok(#(WatchId(1), watches)) = watch.ended(watches:, monitor:)
    as "the DOWN's monitor is watch 1's"
  assert watch.ended(watches:, monitor:) == Error(Nil)
    as "the watch is forgotten, so it ends once"
}

pub fn a_watch_on_no_process_is_held_to_end_once_as_the_shells_next_input_test() -> Nil {
  use <- owned_test.run(30_000)
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(2),
      address: Sessions,
      target: Error(Nil),
      shell: "test shell",
    )
  let assert Ok(#(WatchId(2), watches)) = watch.next_unheld_end(watches)
    as "an address no process holds comes back as the watch's end"
  assert watch.next_unheld_end(watches) == Error(Nil) as "the end comes once"
}

pub fn a_watch_on_no_process_that_is_closed_gives_no_end_test() -> Nil {
  use <- owned_test.run(30_000)
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(5),
      address: Sessions,
      target: Error(Nil),
      shell: "test shell",
    )
  let watches = watch.close(watches:, watch: WatchId(5))
  assert watch.next_unheld_end(watches) == Error(Nil)
    as "a watch closed before its end was taken gives none"
  assert watches == watch.new() as "and the id is free again"
}

pub fn watches_on_no_process_end_in_the_order_opened_test() -> Nil {
  use <- owned_test.run(30_000)
  let watches =
    [WatchId(7), WatchId(3), WatchId(9)]
    |> list.fold(watch.new(), fn(watches, id) {
      watch.open(
        watches:,
        watch: id,
        address: Sessions,
        target: Error(Nil),
        shell: "test shell",
      )
    })
  let assert Ok(#(WatchId(7), watches)) = watch.next_unheld_end(watches)
    as "the first opened ends first, whatever its number"
  let assert Ok(#(WatchId(3), watches)) = watch.next_unheld_end(watches)
  let assert Ok(#(WatchId(9), watches)) = watch.next_unheld_end(watches)
  assert watch.next_unheld_end(watches) == Error(Nil)
}

pub fn a_closed_watch_gives_no_end_and_a_monitor_held_under_no_watch_gives_none_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = a_process()
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(3),
      address: Sessions,
      target: Ok(watch.Watched(target)),
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
  opening_twice_ends_the_process(
    first: Ok(watch.Watched(target)),
    again: Ok(watch.Watched(target)),
  )
  process.kill(target)
}

pub fn a_watch_id_held_to_end_is_open_and_opening_it_again_ends_the_process_test() -> Nil {
  use <- owned_test.run(30_000)
  opening_twice_ends_the_process(first: Error(Nil), again: Error(Nil))
}

/// Opens watch 4 on `first`, then again on `again`, in a process of its own,
/// and checks that the process ended with an error log naming the open id and
/// the shell.
fn opening_twice_ends_the_process(
  first first: Result(watch.Found(Nil), Nil),
  again again: Result(watch.Found(Nil), Nil),
) -> Nil {
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
          address: Sessions,
          target: first,
          shell: "test shell",
        )
      let _again =
        watch.open(
          watches:,
          watch: WatchId(4),
          address: Sessions,
          target: again,
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
}

pub fn a_watch_that_found_a_way_to_tell_gives_it_at_its_address_until_the_watch_is_closed_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = a_process()
  let run = Map(map: MapId(world_id: 3460, instance: 0), incarnation: 5)
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(1),
      address: run,
      target: Ok(watch.Tellable(pid: target, sender: "the way to run 5")),
      shell: "test shell",
    )
  assert watch.sender_at(watches:, address: run) == Ok("the way to run 5")
  assert watch.sender_at(watches:, address: Sessions) == Error(Nil)
    as "another address has none"
  let watches = watch.close(watches:, watch: WatchId(1))
  assert watch.sender_at(watches:, address: run) == Error(Nil)
    as "a closed watch takes its way with it"
  process.kill(target)
}

pub fn a_watch_that_found_a_way_to_tell_loses_it_when_the_process_ends_test() -> Nil {
  use <- owned_test.run(30_000)
  let target = a_process()
  let watches =
    watch.open(
      watches: watch.new(),
      watch: WatchId(1),
      address: Sessions,
      target: Ok(watch.Tellable(pid: target, sender: "the way")),
      shell: "test shell",
    )
  process.kill(target)
  let monitor = next_down()
  let assert Ok(#(WatchId(1), watches)) = watch.ended(watches:, monitor:)
  assert watch.sender_at(watches:, address: Sessions) == Error(Nil)
    as "the end of the process takes the way to it with the watch"
}
