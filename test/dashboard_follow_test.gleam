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
import genesis_prime/dashboard/follow.{type Followed, NotThere, Unreadable}
import genesis_prime/dashboard/log_lines.{
  Line, LogCutShorter, LogReplaced, Marker, UpdaterLog,
}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import open_wait
import owned_test
import simplifile

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

  // The reader's own answer to a first read: the file's bytes, from the start
  // of a line.
  let assert Ok(follow.Fetched(bytes:, starts_inside_a_line: False, ..)) =
    follow.file_reader()(path, follow.Unread)
  assert bytes == <<"a\nb\nc\n":utf8>>

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
