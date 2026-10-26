//// The snapshot process, which writes the runtime's numbers to the log while
//// the server runs. Expected values come from three places.
//// - The issue's plan: one info line at a set interval, 10 seconds when no
////   other is given, whose metadata holds total, process, binary and ETS
////   memory, the process and port counts, the run queue length, the
////   scheduler use over the interval and, for each registered kind of busy
////   process, its largest mailbox and heap.
//// - The OTP documentation of `erlang:memory/1` (`total` is the memory of the
////   processes and the system together, and the system holds the binary and
////   ETS memory), of `statistics(scheduler_wall_time)` (the busy and total
////   time of each scheduler, so the use between two readings is the busy time
////   over the total time and lies between 0 and 1) and of `process_info/2`
////   (`message_queue_len` and `total_heap_size`, the words of a process's
////   heap, stack and waiting messages).
//// - The Erlang efficiency guide's Memory chapter: a list holds at least one
////   word per element, so a process that holds a list of 100,000 elements has
////   a heap of at least 100,000 words.
////
//// A test waits for the lines it needs as events from a capture, never for a
//// fixed time. Each snapshot process has a name of its own.

import genesis_prime/telemetry/snapshot
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/list
import log_capture.{type Event, type Field, Fields, Fraction, Text, Whole}
import owned_test

/// The time between two lines in a test, in milliseconds, short so a test
/// waits for events that come soon.
const test_interval_ms = 50

/// How long a test waits for the next line, in milliseconds. A line comes
/// within one interval; the rest is for a loaded machine.
const line_wait_ms = 5000

/// The elements of the list a planted busy process holds, so its heap holds at
/// least this many words.
const planted_list_length = 100_000

/// Every number the plan lists for each line, by the key it is written under.
const numbers_of_every_line = [
  "memory_total_bytes", "memory_processes_bytes", "memory_binary_bytes",
  "memory_ets_bytes", "process_count", "port_count", "run_queue_length",
  "scheduler_use",
]

pub fn the_default_interval_is_ten_seconds_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = snapshot.settings(process.new_name("snapshot_default"))
  assert settings.interval_milliseconds == 10_000
}

pub fn a_snapshot_is_written_at_each_interval_with_every_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let capture = log_capture.start()
  let settings =
    snapshot.Settings(
      name: process.new_name("snapshot_numbers"),
      interval_milliseconds: test_interval_ms,
    )
  let assert Ok(started) = snapshot.start(settings)
    as "the snapshot process did not start"
  let assert Ok(first) = next_snapshot(capture, started.pid)
    as "the first snapshot was not written"
  let assert Ok(second) = next_snapshot(capture, started.pid)
    as "the second snapshot was not written"
  list.each([first, second], fn(snapshot) {
    assert snapshot.level == "info"
    assert dict.get(snapshot.metadata, "process") == Ok(Text("snapshot"))
    let numbers = numbers_of(snapshot)
    assert list.all(numbers_of_every_line, dict.has_key(numbers, _))
      as "a number is missing from the snapshot"
    // The total holds the processes and the system, which holds the binary
    // and ETS memory.
    let assert Ok(Whole(total)) = dict.get(numbers, "memory_total_bytes")
    let assert Ok(Whole(processes)) =
      dict.get(numbers, "memory_processes_bytes")
    let assert Ok(Whole(binary)) = dict.get(numbers, "memory_binary_bytes")
    let assert Ok(Whole(ets)) = dict.get(numbers, "memory_ets_bytes")
    assert processes > 0 && binary > 0 && ets > 0
    assert total >= processes && total >= binary && total >= ets
    let assert Ok(Whole(process_count)) = dict.get(numbers, "process_count")
    let assert Ok(Whole(port_count)) = dict.get(numbers, "port_count")
    let assert Ok(Whole(run_queue)) = dict.get(numbers, "run_queue_length")
    assert process_count >= 1 && port_count >= 0 && run_queue >= 0
    let assert Ok(Fraction(scheduler_use)) = dict.get(numbers, "scheduler_use")
    assert scheduler_use >=. 0.0 && scheduler_use <=. 1.0
  })
}

pub fn a_registered_kind_reports_its_largest_mailbox_and_heap_in_the_next_snapshot_test() -> Nil {
  use <- owned_test.run(10_000)
  let capture = log_capture.start()
  let settings =
    snapshot.Settings(
      name: process.new_name("snapshot_kind"),
      interval_milliseconds: test_interval_ms,
    )
  let assert Ok(started) = snapshot.start(settings)
    as "the snapshot process did not start"

  // Before the kind is registered, no snapshot reports it.
  let assert Ok(before) = next_snapshot(capture, started.pid)
    as "the snapshot before the registration was not written"
  assert dict.keys(numbers_of(before))
    |> list.all(fn(key) { !is_about_kind(key, "busy") })

  // Two processes of one kind: the first has 3 messages waiting and a small
  // heap, the second 7 messages waiting and a heap with a list in it. The
  // snapshot reports the largest of each, not the sum.
  let small = start_busy_process(waiting: 3, list_length: 0)
  let large = start_busy_process(waiting: 7, list_length: planted_list_length)
  snapshot.register(
    snapshot: settings.name,
    kind: snapshot.Kind(name: "busy", processes: fn() { [small, large] }),
  )
  let assert Ok(after) = next_snapshot_with(capture, started.pid, "busy")
    as "no snapshot after the registration reported the kind"
  let numbers = numbers_of(after)
  assert dict.get(numbers, "busy_largest_queue") == Ok(Whole(7))
  let assert Ok(Whole(heap_words)) =
    dict.get(numbers, "busy_largest_heap_words")
  assert heap_words >= planted_list_length
}

/// The numbers of a snapshot, which every snapshot carries as one map under
/// the key `numbers`.
fn numbers_of(snapshot: Event) -> Dict(String, Field) {
  let assert Ok(Fields(numbers)) = dict.get(snapshot.metadata, "numbers")
    as "the snapshot has no numbers"
  numbers
}

/// The next line the snapshot process wrote.
fn next_snapshot(capture: log_capture.Capture, pid: Pid) -> Result(Event, Nil) {
  log_capture.next_from(capture, from: pid, within: line_wait_ms)
}

/// The next line the snapshot process wrote that reports the kind, skipping
/// the lines written before the kind was registered.
fn next_snapshot_with(
  capture: log_capture.Capture,
  pid: Pid,
  kind: String,
) -> Result(Event, Nil) {
  case next_snapshot(capture, pid) {
    Ok(snapshot) ->
      case list.any(dict.keys(numbers_of(snapshot)), is_about_kind(_, kind)) {
        True -> Ok(snapshot)
        False -> next_snapshot_with(capture, pid, kind)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn is_about_kind(key: String, kind: String) -> Bool {
  key == kind <> "_largest_queue" || key == kind <> "_largest_heap_words"
}

/// A process that holds a list of `list_length` elements and keeps `waiting`
/// messages in its mailbox, which it never reads. It is linked to the test, so
/// it ends with it.
fn start_busy_process(
  waiting waiting: Int,
  list_length list_length: Int,
) -> Pid {
  let reported = process.new_subject()
  let pid =
    process.spawn(fn() {
      let mailbox = process.new_subject()
      let held = list.repeat(1, list_length)
      process.send(reported, mailbox)
      process.sleep_forever()
      // Read after the wait, so the list stays on the process's heap.
      assert list.length(held) == list_length
    })
  let assert Ok(mailbox) = process.receive(reported, line_wait_ms)
    as "the planted process did not report its mailbox"
  list.each(list.repeat(Nil, waiting), fn(message) {
    process.send(mailbox, message)
  })
  pid
}
