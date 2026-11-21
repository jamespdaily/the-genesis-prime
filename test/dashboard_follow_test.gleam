//// The follower of one log file, in two kinds of run. The real reader is run
//// on planted files in a folder of the test's own, one change of the file at a
//// time (the rule: an offset and an inode, since `tail -F` through a port
//// outlives its port). The follower's own rules are run with a reader the test
//// answers, so each read, its cursor and its answer are messages the test
//// sends and no test waits on a clock: the interval is a day, and a tick is
//// `follow.read_now`. Expected values are the follower's rules: it reads only
//// while a page is subscribed, hands each subscriber the newest lines at once,
//// sends one update for one read, shows a read that failed with its reason
//// and keeps the lines, and drops a subscriber that ends.

import dashboard_support
import dashboard_timer_support as timers
import genesis_prime/dashboard/follow.{
  type Cursor, type Fetched, type Followed, type Reader, type Trouble, At,
  Fetched, Gone, NotThere, SubscriberDropped, Unread, Unreadable,
}
import genesis_prime/dashboard/log_lines.{
  LaunchdLog, Line, LogCutShorter, LogReplaced, Marker, UpdaterLog,
}
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import open_wait
import owned_test
import simplifile

/// The first read of a file and each one that follows, in the guess the
/// follower sets: 256 KiB.
const read_limit_bytes = 262_144

// ---------------------------------------------------------------------------
// The real reader, on planted files.

/// A follower of the file at `path`, read by the real reader, and a subscriber
/// of its own. The first update (the subscriber's) is waited for.
fn following(
  path: String,
) -> #(Subject(follow.Message), Subject(Followed), Followed) {
  let assert Ok(started) =
    follow.start(follow.Settings(
      source: UpdaterLog,
      path:,
      reader: follow.file_reader(),
      interval_ms: 86_400_000,
      arm: timers.arm(process.new_subject()),
      watcher: None,
    ))
  let subscriber = process.new_subject()
  follow.subscribe(follower: started.data, subscriber:)
  #(started.data, subscriber, update(subscriber))
}

fn update(subscriber: Subject(Followed)) -> Followed {
  open_wait.received(from: subscriber, what: "an update of the follower")
}

/// The follower has handled everything sent before this, so an update it would
/// have sent is already in the subscriber's mailbox.
fn handled(follower: Subject(follow.Message)) -> Nil {
  let _count = follow.subscriber_count(follower)
  Nil
}

fn nothing_sent(subscriber: Subject(Followed)) -> Bool {
  process.receive(subscriber, 0) == Error(Nil)
}

fn texts(followed: Followed) -> List(String) {
  list.filter_map(followed.entries, fn(entry) {
    case entry {
      Line(text:, ..) -> Ok(text)
      Marker(..) -> Error(Nil)
    }
  })
}

/// Each entry as a line's text or the word of a mark, in order.
fn shown(followed: Followed) -> List(String) {
  list.map(followed.entries, fn(entry) {
    case entry {
      Line(text:, ..) -> text
      Marker(mark: LogReplaced, ..) -> "[replaced]"
      Marker(mark: LogCutShorter, ..) -> "[cut shorter]"
      Marker(mark: log_lines.ContainerReplaced, ..) -> "[container replaced]"
    }
  })
}

/// Reads now and waits for the update it makes.
fn read_and_update(
  follower: Subject(follow.Message),
  subscriber: Subject(Followed),
) -> Followed {
  follow.read_now(follower)
  update(subscriber)
}

pub fn the_real_reader_follows_a_planted_file_through_every_change_the_file_can_have_test() -> Nil {
  use <- owned_test.run(5000)
  use home <- dashboard_support.with_home
  let path = home <> "/play-service.log"

  // No file: not there, and no lines.
  let #(follower, subscriber, first) = following(path)
  assert first.trouble == Some(NotThere)
  assert first.entries == []
  assert first.path == path
  assert first.source == UpdaterLog

  // Created with three lines: those three.
  let assert Ok(Nil) = simplifile.write(path, "a\nb\nc\n")
  let created = read_and_update(follower, subscriber)
  assert created.trouble == None
  assert shown(created) == ["a", "b", "c"]

  // One line appended: that one, once.
  let assert Ok(Nil) = simplifile.append(path, "d\n")
  let appended = read_and_update(follower, subscriber)
  assert shown(appended) == ["a", "b", "c", "d"]

  // Nothing appended: no update.
  follow.read_now(follower)
  handled(follower)
  assert nothing_sent(subscriber)

  // Half a line appended: not shown. Its rest: one line, once.
  let assert Ok(Nil) = simplifile.append(path, "half")
  follow.read_now(follower)
  handled(follower)
  assert nothing_sent(subscriber) as "half a line is not shown"
  let assert Ok(Nil) = simplifile.append(path, " the rest\n")
  let whole = read_and_update(follower, subscriber)
  assert shown(whole) == ["a", "b", "c", "d", "half the rest"]

  // Truncated and rewritten shorter, in the same file: a mark, and the new
  // content from its start.
  let assert Ok(Nil) = simplifile.write(path, "x\n")
  let cut = read_and_update(follower, subscriber)
  assert shown(cut)
    == ["a", "b", "c", "d", "half the rest", "[cut shorter]", "x"]

  // Renamed away and a new file made at the path: a mark, and the new file
  // from its start.
  let assert Ok(Nil) = simplifile.rename(at: path, to: home <> "/old.log")
  let assert Ok(Nil) = simplifile.write(path, "new one\nnew two\n")
  let replaced = read_and_update(follower, subscriber)
  assert shown(replaced)
    == [
      "a",
      "b",
      "c",
      "d",
      "half the rest",
      "[cut shorter]",
      "x",
      "[replaced]",
      "new one",
      "new two",
    ]

  // Deleted: not there, and the lines stay.
  let assert Ok(Nil) = simplifile.delete(path)
  let removed = read_and_update(follower, subscriber)
  assert removed.trouble == Some(NotThere)
  assert shown(removed) == shown(replaced)

  // Created again: read from its start, after a mark.
  let assert Ok(Nil) = simplifile.write(path, "again\n")
  let again = read_and_update(follower, subscriber)
  assert again.trouble == None
  assert list.drop(shown(again), 10) == ["[replaced]", "again"]

  // A directory at the path: unreadable, with the reason, and the lines stay.
  let assert Ok(Nil) = simplifile.delete(path)
  let _gone = read_and_update(follower, subscriber)
  let assert Ok(Nil) = simplifile.create_directory(path)
  let directory = read_and_update(follower, subscriber)
  assert directory.trouble == Some(Unreadable("eisdir"))
  assert shown(directory) == shown(again)
  let assert Ok(Nil) = simplifile.delete(path)
  let assert Ok(Nil) = simplifile.write(path, "back\n")
  let back = read_and_update(follower, subscriber)
  assert back.trouble == None
  assert list.last(shown(back)) == Ok("back")

  // A file nobody may read (the row needs a user who is not root, which can
  // read it): unreadable with the reason, then lines again once it can be read.
  let assert Ok(Nil) = simplifile.set_permissions_octal(path, 0o000)
  case result.is_ok(simplifile.read(path)) {
    True -> Nil
    False -> {
      let closed = read_and_update(follower, subscriber)
      assert closed.trouble == Some(Unreadable("eacces"))
      assert shown(closed) == shown(back)
    }
  }
  let assert Ok(Nil) = simplifile.set_permissions_octal(path, 0o600)
  let assert Ok(Nil) = simplifile.append(path, "readable again\n")
  let readable = read_and_update(follower, subscriber)
  assert readable.trouble == None
  assert list.last(shown(readable)) == Ok("readable again")

  // A file of 0 bytes: no lines and no error.
  let empty = home <> "/empty.log"
  let assert Ok(Nil) = simplifile.write(empty, "")
  let #(_follower, _subscriber, nothing) = following(empty)
  assert nothing.trouble == None
  assert nothing.entries == []
}

fn numbered(first: Int, count: Int) -> String {
  int.range(from: first, to: first + count, with: [], run: fn(all, number) {
    ["line " <> int.to_string(number) <> "\n", ..all]
  })
  |> list.reverse
  |> string.concat
}

/// The numbers in a followed log's lines, which must each be `line N`.
fn numbers(followed: Followed) -> List(Int) {
  list.map(texts(followed), fn(text) {
    let assert Ok(number) = string.drop_start(text, 5) |> int.parse
      as { "the line is not whole: " <> text }
    number
  })
}

pub fn the_first_read_of_a_large_file_reads_only_its_tail_and_shows_whole_lines_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  let path = home <> "/play-service.log"
  // 300,000 lines, about 3.9 MB.
  let count = 300_000
  let assert Ok(Nil) = simplifile.write(path, numbered(0, count))
  let assert Ok(info) = simplifile.file_info(path)
  assert info.size > 3 * 1_048_576

  // The reader gives at most the first-read size, and says the read began
  // inside a line.
  assert follow.read_limit_bytes == read_limit_bytes
  let assert Ok(Fetched(bytes:, starts_inside_a_line:, ..)) =
    follow.file_reader()(path, Unread)
  assert bit_array.byte_size(bytes) <= read_limit_bytes
  assert starts_inside_a_line

  // The ring holds the last lines of the file, each whole, the file's last
  // line last.
  let #(_follower, _subscriber, first) = following(path)
  assert list.length(first.entries) == log_lines.ring_lines
  assert numbers(first)
    == int.range(
      from: count - log_lines.ring_lines,
      to: count,
      with: [],
      run: fn(all, number) { [number, ..all] },
    )
    |> list.reverse
}

// ---------------------------------------------------------------------------
// The follower's rules, with a reader the test answers.

/// A read the follower made: the cursor it gave and where the answer goes.
type Call {
  Call(cursor: Cursor, answer: Subject(Result(Fetched, Trouble)))
}

/// A reader that tells the test of each read and returns the test's answer.
fn asked(calls: Subject(Call)) -> Reader {
  fn(_path, cursor) {
    let answer = process.new_subject()
    process.send(calls, Call(cursor:, answer:))
    process.receive_forever(answer)
  }
}

fn answered_followers(
  source: log_lines.Source,
  watcher: Option(Subject(follow.Event)),
) -> #(Subject(follow.Message), Subject(Call)) {
  let calls = process.new_subject()
  let assert Ok(started) =
    follow.start(follow.Settings(
      source:,
      path: "/planted/play-service.log",
      reader: asked(calls),
      interval_ms: 86_400_000,
      arm: timers.arm(process.new_subject()),
      watcher:,
    ))
  #(started.data, calls)
}

fn next_call(calls: Subject(Call)) -> Call {
  open_wait.received(from: calls, what: "the follower to read")
}

fn no_call(calls: Subject(Call)) -> Bool {
  process.receive(calls, 0) == Error(Nil)
}

/// What came first: the follower's handling of everything sent to it, or a
/// read it started.
type Settled {
  Handled
  Started(Call)
}

/// The first of the follower's handling of everything sent to it before this,
/// and a read it starts. A read waits for the test's answer, so a follower that
/// reads when it should not never handles anything: the wait ends at its read
/// instead of hanging.
fn settled(follower: Subject(follow.Message), calls: Subject(Call)) -> Settled {
  let done = process.new_subject()
  let _helper =
    process.spawn(fn() {
      handled(follower)
      process.send(done, Nil)
    })
  process.new_selector()
  |> process.select_map(done, fn(_) { Handled })
  |> process.select_map(calls, Started)
  |> open_wait.selected(what: "the follower to handle what was sent, or read")
}

/// Whether the follower handled everything sent to it without starting a read.
fn handled_without_a_read(
  follower: Subject(follow.Message),
  calls: Subject(Call),
) -> Bool {
  settled(follower, calls) == Handled
}

/// The read the follower started after what was sent to it; fails when it
/// handled all of it without one.
fn read_started(
  follower: Subject(follow.Message),
  calls: Subject(Call),
) -> Call {
  let assert Started(call) = settled(follower, calls)
    as "the follower started no read"
  call
}

/// The update the follower sent after what was sent to it, once its reads are
/// answered; fails when it sent none.
fn update_sent(
  follower: Subject(follow.Message),
  subscriber: Subject(Followed),
) -> Followed {
  handled(follower)
  let assert Ok(followed) = process.receive(subscriber, 0)
    as "the follower sent no update"
  followed
}

fn lines_read(cursor: Cursor, text: String) -> Result(Fetched, Trouble) {
  Ok(Fetched(
    cursor:,
    bytes: bit_array.from_string(text),
    mark: None,
    starts_inside_a_line: False,
  ))
}

pub fn a_follower_reads_only_while_a_page_is_subscribed_and_hands_each_subscriber_the_newest_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(follower, calls) = answered_followers(UpdaterLog, None)

  // Nobody subscribed: a read now reads nothing.
  follow.read_now(follower)
  assert handled_without_a_read(follower, calls)

  // The first subscriber: one read, from the start, and the newest lines.
  let first = process.new_subject()
  follow.subscribe(follower:, subscriber: first)
  let call = read_started(follower, calls)
  assert call.cursor == Unread
  process.send(call.answer, lines_read(At(inode: 7, offset: 6), "a\nb\nc\n"))
  assert shown(update_sent(follower, first)) == ["a", "b", "c"]

  // A second subscriber: the newest at once, and no new read.
  let second = process.new_subject()
  follow.subscribe(follower:, subscriber: second)
  assert shown(update_sent(follower, second)) == ["a", "b", "c"]
  assert no_call(calls)
  assert nothing_sent(first) as "the first is not sent the same lines again"

  // Both leave: ticks read nothing.
  follow.unsubscribe(follower:, subscriber: first)
  follow.unsubscribe(follower:, subscriber: second)
  follow.read_now(follower)
  assert handled_without_a_read(follower, calls)

  // Subscribing again reads the tail again, from nothing: a line written while
  // nobody watched is there, and the lines of before are not kept.
  let third = process.new_subject()
  follow.subscribe(follower:, subscriber: third)
  let again = read_started(follower, calls)
  assert again.cursor == Unread
  process.send(
    again.answer,
    lines_read(
      At(inode: 7, offset: 8),
      "a\nb\nc\nwritten while nobody watched\n",
    ),
  )
  assert shown(update_sent(follower, third))
    == ["a", "b", "c", "written while nobody watched"]
}

pub fn new_lines_reach_each_subscriber_once_and_a_burst_is_one_update_test() -> Nil {
  use <- owned_test.run(60_000)

  // A read of 10,000 lines is one update, and the ring holds the last cap.
  let #(follower, calls) = answered_followers(UpdaterLog, None)
  let subscriber = process.new_subject()
  follow.subscribe(follower:, subscriber:)
  let call = next_call(calls)
  process.send(
    call.answer,
    lines_read(At(inode: 1, offset: 100_000), numbered(0, 10_000)),
  )
  let burst = update(subscriber)
  assert list.length(burst.entries) == log_lines.ring_lines
  assert numbers(burst)
    == int.range(from: 9500, to: 10_000, with: [], run: fn(all, number) {
      [number, ..all]
    })
    |> list.reverse
  handled(follower)
  assert nothing_sent(subscriber) as "10,000 lines are one update, not 10,000"

  // Two sources: the lines of one never reach the other's subscribers.
  let #(launchd, launchd_calls) = answered_followers(LaunchdLog, None)
  let other = process.new_subject()
  follow.subscribe(follower: launchd, subscriber: other)
  let other_call = next_call(launchd_calls)
  process.send(other_call.answer, lines_read(At(inode: 2, offset: 6), "own\n"))
  assert texts(update(other)) == ["own"]
  handled(launchd)
  assert nothing_sent(other)
  assert !list.contains(texts(burst), "own")

  // A file that grew by much more than a read: the reader gives at most the
  // limit at each call, whatever is left waits for the next, and the pieces
  // are the bytes appended, in order.
  use home <- dashboard_support.with_home
  let path = home <> "/play-service.log"
  let assert Ok(Nil) = simplifile.write(path, "line 0\n")
  let reader = follow.file_reader()
  let assert Ok(Fetched(cursor: start, ..)) = reader(path, Unread)
  let grown = numbered(1, 70_000)
  let assert Ok(Nil) = simplifile.append(path, grown)
  let pieces = pieces_from(reader:, path:, cursor: start, pieces: [])
  assert list.length(pieces) > 1 as "the backlog was not read in one go"
  list.each(pieces, fn(piece) {
    assert bit_array.byte_size(piece) <= read_limit_bytes
  })
  assert bit_array.concat(pieces) == bit_array.from_string(grown)
}

/// What the reader gives from `cursor` on, call after call, until a call
/// gives nothing.
fn pieces_from(
  reader reader: Reader,
  path path: String,
  cursor cursor: Cursor,
  pieces pieces: List(BitArray),
) -> List(BitArray) {
  let assert Ok(Fetched(cursor: next, bytes:, ..)) = reader(path, cursor)
  case bit_array.byte_size(bytes) {
    0 -> list.reverse(pieces)
    _ -> pieces_from(reader:, path:, cursor: next, pieces: [bytes, ..pieces])
  }
}

pub fn a_failed_read_is_sent_with_its_reason_and_the_next_tick_tries_again_test() -> Nil {
  use <- owned_test.run(5000)

  // The reader fails after good reads: the same lines, marked unreadable with
  // the reason; the cursor of the good read is given again.
  let #(follower, calls) = answered_followers(UpdaterLog, None)
  let subscriber = process.new_subject()
  follow.subscribe(follower:, subscriber:)
  let good = At(inode: 3, offset: 4)
  let first = next_call(calls)
  assert first.cursor == Unread
  process.send(first.answer, lines_read(good, "x\ny\n"))
  let fine = update(subscriber)
  assert fine.trouble == None
  assert shown(fine) == ["x", "y"]

  follow.read_now(follower)
  let failing = next_call(calls)
  assert failing.cursor == good
  process.send(failing.answer, Error(Unreadable("eacces")))
  let failed = update(subscriber)
  assert failed.trouble == Some(Unreadable("eacces"))
  assert shown(failed) == ["x", "y"] as "the lines stay"

  // The next good read, with nothing new, is sent: it marks the file fine.
  follow.read_now(follower)
  let recovering = next_call(calls)
  assert recovering.cursor == good as "a failed read leaves the cursor"
  process.send(recovering.answer, lines_read(good, ""))
  let recovered = update(subscriber)
  assert recovered.trouble == None
  assert shown(recovered) == ["x", "y"]

  // The file is not there: sent, with the lines kept; the lines that come
  // after are read from the start.
  follow.read_now(follower)
  let missing = next_call(calls)
  process.send(missing.answer, Error(NotThere))
  let gone = update(subscriber)
  assert gone.trouble == Some(NotThere)
  assert shown(gone) == ["x", "y"]
  follow.read_now(follower)
  let returned = next_call(calls)
  assert returned.cursor == Gone
  process.send(
    returned.answer,
    Ok(Fetched(
      cursor: At(inode: 9, offset: 2),
      bytes: <<"z\n":utf8>>,
      mark: Some(LogReplaced),
      starts_inside_a_line: False,
    )),
  )
  let back = update(subscriber)
  assert back.trouble == None
  assert shown(back) == ["x", "y", "[replaced]", "z"]

  // A failure on the first read: no lines, the reason, and the next read
  // starts again.
  let #(other, other_calls) = answered_followers(UpdaterLog, None)
  let opened = process.new_subject()
  follow.subscribe(follower: other, subscriber: opened)
  let start = next_call(other_calls)
  process.send(start.answer, Error(Unreadable("eacces")))
  let refused = update(opened)
  assert refused.entries == []
  assert refused.trouble == Some(Unreadable("eacces"))
  follow.read_now(other)
  let retry = next_call(other_calls)
  assert retry.cursor == Unread
  process.send(retry.answer, Error(NotThere))
  assert update(opened).trouble == Some(NotThere)
  follow.read_now(other)
  let after = next_call(other_calls)
  assert after.cursor == Unread
    as "a file that was never there is read from its start"
}

/// A subscriber in a process of its own, which the test can end. Gives the
/// subject and the process.
fn ended_subscriber() -> #(Subject(Followed), process.Pid) {
  let made = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let subject = process.new_subject()
      process.send(made, subject)
      process.receive_forever(process.new_subject())
    })
  #(open_wait.received(from: made, what: "a subscriber"), pid)
}

/// The next event the follower told its watcher of.
fn next_event(watcher: Subject(follow.Event)) -> follow.Event {
  open_wait.received(from: watcher, what: "the follower's report")
}

pub fn a_subscriber_that_ends_mid_follow_is_dropped_and_the_last_one_ends_the_reads_test() -> Nil {
  use <- owned_test.run(5000)
  let watcher = process.new_subject()
  let #(follower, calls) = answered_followers(UpdaterLog, Some(watcher))
  let #(leaving, leaving_pid) = ended_subscriber()
  let staying = process.new_subject()
  follow.subscribe(follower:, subscriber: leaving)
  let first = read_started(follower, calls)
  process.send(first.answer, lines_read(At(inode: 1, offset: 2), "a\n"))
  assert next_event(watcher) == follow.ReadMade(UpdaterLog)
  follow.subscribe(follower:, subscriber: staying)
  assert texts(update_sent(follower, staying)) == ["a"]

  // One subscriber ends between a read and the next: the follower tells the
  // watcher it dropped one, does not crash, and the other still gets lines.
  process.kill(leaving_pid)
  assert next_event(watcher) == SubscriberDropped(UpdaterLog)
  assert follow.subscriber_count(follower) == 1
  follow.read_now(follower)
  let second = read_started(follower, calls)
  process.send(second.answer, lines_read(At(inode: 1, offset: 4), "b\n"))
  assert texts(update_sent(follower, staying)) == ["a", "b"]
  assert next_event(watcher) == follow.ReadMade(UpdaterLog)

  // The last one ends: reads stop, and a new subscriber gets the tail again.
  let #(last, last_pid) = ended_subscriber()
  follow.subscribe(follower:, subscriber: last)
  process.kill(last_pid)
  assert next_event(watcher) == SubscriberDropped(UpdaterLog)
  follow.unsubscribe(follower:, subscriber: staying)
  assert follow.subscriber_count(follower) == 0
  follow.read_now(follower)
  assert handled_without_a_read(follower, calls)
    as "no read once the last subscriber is gone"
  let fresh = process.new_subject()
  follow.subscribe(follower:, subscriber: fresh)
  let again = read_started(follower, calls)
  assert again.cursor == Unread
  process.send(again.answer, lines_read(At(inode: 1, offset: 2), "c\n"))
  assert shown(update_sent(follower, fresh)) == ["c"]
}

// ---------------------------------------------------------------------------
// The follower's timer, driven by the test.

/// The interval the driven follower is set to; its timers are armed for it.
const driven_interval_ms = 1000

/// A reader that tells the test the cursor of each read and gives an empty
/// read, so a read changes nothing the page shows.
fn counted(reads: Subject(Cursor)) -> Reader {
  fn(_path, cursor) {
    process.send(reads, cursor)
    let offset = case cursor {
      At(offset:, ..) -> offset + 1
      Unread | Gone -> 1
    }
    Ok(Fetched(
      cursor: At(inode: 1, offset:),
      bytes: <<>>,
      mark: None,
      starts_inside_a_line: False,
    ))
  }
}

/// A follower whose timers are the test's (`timers`), and whose reads are the
/// cursors sent to `reads`.
fn driven() -> #(
  Subject(follow.Message),
  Subject(Cursor),
  Subject(timers.Event),
) {
  let reads = process.new_subject()
  let events = process.new_subject()
  let assert Ok(started) =
    follow.start(follow.Settings(
      source: UpdaterLog,
      path: "/planted/play-service.log",
      reader: counted(reads),
      interval_ms: driven_interval_ms,
      arm: timers.arm(events),
      watcher: None,
    ))
  #(started.data, reads, events)
}

/// The cursors of the reads made since the last look, after the follower has
/// handled what was sent to it.
fn reads_made(
  follower: Subject(follow.Message),
  reads: Subject(Cursor),
) -> List(Cursor) {
  handled(follower)
  receive_all(reads, [])
}

/// What the follower did to its timers since the last look, after it has
/// handled what was sent to it.
fn timers_changed(
  follower: Subject(follow.Message),
  events: Subject(timers.Event),
) -> List(timers.Event) {
  handled(follower)
  receive_all(events, [])
}

fn receive_all(subject: Subject(a), found: List(a)) -> List(a) {
  case process.receive(subject, 0) {
    Ok(next) -> receive_all(subject, [next, ..found])
    Error(Nil) -> list.reverse(found)
  }
}

/// The timer that is the only change, which is armed for the interval.
fn the_one_timer_armed(changes: List(timers.Event)) -> timers.Event {
  let assert [armed] = changes
    as "one timer should have been armed, and nothing else"
  let assert timers.Armed(after_ms:, ..) = armed
    as "the change is not an arming"
  assert after_ms == driven_interval_ms
  armed
}

pub fn each_tick_reads_once_and_arms_the_next_tick_for_as_long_as_a_page_is_subscribed_test() -> Nil {
  use <- owned_test.run(5000)
  let #(follower, reads, events) = driven()
  follow.subscribe(follower:, subscriber: process.new_subject())
  assert reads_made(follower, reads) == [Unread]
  let first = the_one_timer_armed(timers_changed(follower, events))

  // Each tick reads once from where the last read ended and arms the next.
  timers.fire(first)
  assert reads_made(follower, reads) == [At(inode: 1, offset: 1)]
  let second = the_one_timer_armed(timers_changed(follower, events))
  timers.fire(second)
  assert reads_made(follower, reads) == [At(inode: 1, offset: 2)]
  let _third = the_one_timer_armed(timers_changed(follower, events))
  Nil
}

pub fn the_last_page_to_leave_cancels_the_timer_and_a_later_tick_of_it_reads_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(follower, reads, events) = driven()
  let page = process.new_subject()
  follow.subscribe(follower:, subscriber: page)
  let armed = the_one_timer_armed(timers_changed(follower, events))
  assert reads_made(follower, reads) == [Unread]

  follow.unsubscribe(follower:, subscriber: page)
  let assert timers.Armed(timer:, ..) = armed
  assert timers_changed(follower, events) == [timers.Cancelled(timer:)]

  // A tick already sent when the timer was cancelled reads nothing and arms
  // nothing.
  timers.fire(armed)
  assert reads_made(follower, reads) == []
  assert timers_changed(follower, events) == []
}

pub fn a_tick_sent_before_its_timer_was_cancelled_starts_no_second_timer_chain_test() -> Nil {
  use <- owned_test.run(5000)
  let #(follower, reads, events) = driven()
  let leaving = process.new_subject()
  follow.subscribe(follower:, subscriber: leaving)
  let stale = the_one_timer_armed(timers_changed(follower, events))
  follow.unsubscribe(follower:, subscriber: leaving)
  follow.subscribe(follower:, subscriber: process.new_subject())
  assert reads_made(follower, reads) == [Unread, Unread]
  let assert [timers.Cancelled(..), current] = timers_changed(follower, events)
    as "the first timer was cancelled and a second was armed"

  // The first timer's tick is in the mailbox: it is dropped, no timer is
  // armed, and nothing is read.
  timers.fire(stale)
  assert reads_made(follower, reads) == []
  assert timers_changed(follower, events) == []

  // The second timer's tick reads once and arms one timer.
  timers.fire(current)
  assert reads_made(follower, reads) == [At(inode: 1, offset: 1)]
  let _next = the_one_timer_armed(timers_changed(follower, events))
  Nil
}
