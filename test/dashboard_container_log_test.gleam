//// What a container's log read is made of: podman's output split into lines
//// and its own words, the cursor that keeps a line from showing twice, the
//// container's id that tells a continued container from a replaced one, and the
//// one reason each failure of podman gives. The rules are pure and run on rows
//// of the texts podman printed (`test/fixture/otp_log`, and the measured error
//// texts); the follower's rules run with a reader the test answers, and the
//// real reader runs the planted fake `podman` of the play service's tests. No
//// test waits on a clock: the interval is a day and a tick is a message.

import dashboard_support
import dashboard_timer_support as timers
import genesis_prime/dashboard/container_follow
import genesis_prime/dashboard/container_log.{
  type Cursor, type Line, Cursor, Line, Plan, Read, Tracking,
}
import genesis_prime/dashboard/follow.{
  type Followed, NotThere, PodmanUnreachable, Unreadable,
}
import genesis_prime/dashboard/log_lines.{
  ContainerReplaced, DatabaseLog, ServerLog,
}
import genesis_prime/dashboard/read_poll
import genesis_prime/dashboard/script.{
  DeadlineReached, Finished, NotExecutable, NotFound, NotStarted,
}
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import open_wait
import owned_test
import play_service_support as play
import qcheck
import simplifile

// ---------------------------------------------------------------------------
// What podman printed becomes lines and podman's own words.

fn bytes(text: String) -> BitArray {
  bit_array.from_string(text)
}

fn line(token: String, text: String) -> Line {
  Line(token:, text: bytes(text))
}

/// A row of the split: what podman printed, the lines it holds and the words
/// that are podman's.
type SplitRow {
  SplitRow(
    name: String,
    output: BitArray,
    lines: List(Line),
    words: List(String),
  )
}

pub fn the_output_of_a_read_is_split_into_lines_with_their_second_and_podmans_own_words_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = [
    SplitRow(
      "prefixed lines give the second's token and the text",
      bytes(
        "2026-11-20T09:10:12-05:00 a notice line\n2026-11-20T09:10:13-05:00 2026-11-09 00:56:22.092 UTC [69] LOG:  checkpoint starting: time\n",
      ),
      [
        line("2026-11-20T09:10:12-05:00", "a notice line"),
        line(
          "2026-11-20T09:10:13-05:00",
          "2026-11-09 00:56:22.092 UTC [69] LOG:  checkpoint starting: time",
        ),
      ],
      [],
    ),
    SplitRow(
      "a prefixed empty text is an empty line",
      bytes("2026-11-20T09:10:12-05:00 \n"),
      [line("2026-11-20T09:10:12-05:00", "")],
      [],
    ),
    SplitRow(
      "an unprefixed line is podman's words, not a line",
      bytes(
        "Error: no container with name or ID \"genesis-play\" found: no such container\n",
      ),
      [],
      [
        "Error: no container with name or ID \"genesis-play\" found: no such container",
      ],
    ),
    SplitRow(
      "podman's words between lines keep their order and the lines theirs",
      bytes(
        "2026-11-20T09:10:12-05:00 one\nCannot connect to Podman.\n2026-11-20T09:10:13-05:00 two\n",
      ),
      [
        line("2026-11-20T09:10:12-05:00", "one"),
        line("2026-11-20T09:10:13-05:00", "two"),
      ],
      ["Cannot connect to Podman."],
    ),
    SplitRow(
      "another offset and Z keep the token whole",
      bytes(
        "2026-11-20T09:10:12+01:00 east\n2026-11-20T14:10:12Z zulu\n2026-11-20T04:10:12-05:30 odd\n",
      ),
      [
        line("2026-11-20T09:10:12+01:00", "east"),
        line("2026-11-20T14:10:12Z", "zulu"),
        line("2026-11-20T04:10:12-05:30", "odd"),
      ],
      [],
    ),
    SplitRow(
      "a text that holds a space and a token keeps both",
      bytes("2026-11-20T09:10:12-05:00 a 2026-11-20T09:10:13-05:00 b\n"),
      [line("2026-11-20T09:10:12-05:00", "a 2026-11-20T09:10:13-05:00 b")],
      [],
    ),
    SplitRow(
      "text that only looks like a token is podman's words",
      bytes(
        "2026-11-20 09:10:12 not a token\n2026-11-20T09:10:12 no zone\n2026-11-2xT09:10:12-05:00 digit\n",
      ),
      [],
      [
        "2026-11-20 09:10:12 not a token",
        "2026-11-20T09:10:12 no zone",
        "2026-11-2xT09:10:12-05:00 digit",
      ],
    ),
    SplitRow(
      "an output that ends without a newline drops its last piece",
      bytes("2026-11-20T09:10:12-05:00 whole\n2026-11-20T09:10:13-05:00 hal"),
      [line("2026-11-20T09:10:12-05:00", "whole")],
      [],
    ),
    SplitRow("zero bytes", <<>>, [], []),
    SplitRow(
      "bytes that are not UTF-8 stay as they are in the text",
      <<"2026-11-20T09:10:12-05:00 ":utf8, 0xFF, 0xFE, "x":utf8, 0x0A>>,
      [
        Line(token: "2026-11-20T09:10:12-05:00", text: <<0xFF, 0xFE, "x":utf8>>),
      ],
      [],
    ),
  ]
  list.each(rows, fn(row) {
    let split = container_log.split(row.output)
    assert split.lines == row.lines as row.name
    assert split.words == row.words as row.name
  })
}

// ---------------------------------------------------------------------------
// The cursor: a second's lines come again with `--since`, and each shows once.

fn at(token: String, number: Int) -> Line {
  line(token, "line " <> int.to_string(number))
}

const t0 = "2026-11-20T09:10:12-05:00"

const t1 = "2026-11-20T09:10:13-05:00"

const t2 = "2026-11-20T09:10:14-05:00"

/// A row of the cursor: the cursor before, the lines podman gave, the lines
/// that are new and the cursor after.
type TakeRow {
  TakeRow(
    name: String,
    cursor: Option(Cursor),
    given: List(Line),
    taken: List(Line),
    after: Option(Cursor),
  )
}

pub fn a_read_drops_the_lines_of_the_cursors_second_that_were_already_taken_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = [
    TakeRow(
      "the cursor holds 2 of the second's 3 lines: the third and the later one are new",
      Some(Cursor(token: t0, taken: 2)),
      [at(t0, 1), at(t0, 2), at(t0, 3), at(t1, 4)],
      [at(t0, 3), at(t1, 4)],
      Some(Cursor(token: t1, taken: 1)),
    ),
    TakeRow(
      "a cursor that took none of its second: all are new",
      Some(Cursor(token: t0, taken: 0)),
      [at(t0, 1), at(t0, 2)],
      [at(t0, 1), at(t0, 2)],
      Some(Cursor(token: t0, taken: 2)),
    ),
    TakeRow(
      "the tail cut the head: no line at the cursor's second, all are new",
      Some(Cursor(token: t0, taken: 2)),
      [at(t1, 3), at(t1, 4), at(t2, 5)],
      [at(t1, 3), at(t1, 4), at(t2, 5)],
      Some(Cursor(token: t2, taken: 1)),
    ),
    TakeRow(
      "an empty output: nothing is new and the cursor stays",
      Some(Cursor(token: t0, taken: 2)),
      [],
      [],
      Some(Cursor(token: t0, taken: 2)),
    ),
    TakeRow(
      "every line was already taken: nothing is new and the cursor stays",
      Some(Cursor(token: t0, taken: 2)),
      [at(t0, 1), at(t0, 2)],
      [],
      Some(Cursor(token: t0, taken: 2)),
    ),
    TakeRow(
      "a cursor second newer than every line: nothing is dropped",
      Some(Cursor(token: t2, taken: 3)),
      [at(t0, 1), at(t1, 2)],
      [at(t0, 1), at(t1, 2)],
      Some(Cursor(token: t1, taken: 1)),
    ),
    TakeRow(
      "the first read: all are taken, the cursor is the last line's second and its count",
      None,
      [at(t0, 1), at(t1, 2), at(t1, 3)],
      [at(t0, 1), at(t1, 2), at(t1, 3)],
      Some(Cursor(token: t1, taken: 2)),
    ),
    TakeRow("the first read of an empty log: no cursor yet", None, [], [], None),
    TakeRow(
      "new lines in the cursor's own second add to its count",
      Some(Cursor(token: t0, taken: 1)),
      [at(t0, 1), at(t0, 2), at(t0, 3)],
      [at(t0, 2), at(t0, 3)],
      Some(Cursor(token: t0, taken: 3)),
    ),
  ]
  list.each(rows, fn(row) {
    let #(taken, after) =
      container_log.take(cursor: row.cursor, lines: row.given)
    assert taken == row.taken as row.name
    assert after == row.after as row.name
  })
}

/// Lines whose seconds never decrease: the numbers of the lines in each
/// second, the seconds counted from the first.
fn lines_of_seconds(per_second: List(Int)) -> List(Line) {
  list.index_map(per_second, fn(count, second) {
    let token =
      "2026-11-20T09:10:"
      <> string.pad_start(int.to_string(second), 2, "0")
      <> "-05:00"
    list.repeat(token, count)
  })
  |> list.flatten
  |> list.index_map(fn(token, number) { at(token, number) })
}

/// What `--since` gives after the cursor: every line from the cursor's second
/// on, up to the line the read ends at.
fn read_after(
  all all: List(Line),
  cursor cursor: Option(Cursor),
  end end: Int,
) -> List(Line) {
  let upto = list.take(all, end)
  case cursor {
    None -> upto
    Some(Cursor(token:, ..)) ->
      list.drop_while(upto, fn(line) { line.token != token })
  }
}

pub fn reads_that_repeat_the_cursors_second_show_every_line_once_and_lose_none_test() -> Nil {
  use <- owned_test.run(120_000)
  qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(200),
    qcheck.tuple2(
      qcheck.list_from(qcheck.bounded_int(from: 0, to: 4)),
      qcheck.list_from(qcheck.bounded_int(from: 0, to: 40)),
    ),
    fn(drawn) {
      let #(per_second, ends) = drawn
      let all = lines_of_seconds(per_second)
      let total = list.length(all)
      // The reads end at the drawn lines, in order, and the last read ends at
      // the end of the log.
      let ends =
        list.map(ends, fn(end) { int.min(end, total) })
        |> list.sort(int.compare)
        |> list.append([total])
      let #(shown, _cursor) =
        list.fold(ends, #([], None), fn(state, end) {
          let #(shown, cursor) = state
          let #(taken, cursor) =
            container_log.take(cursor:, lines: read_after(all:, cursor:, end:))
          #(list.append(shown, taken), cursor)
        })
      assert shown == all as "each line once, in order, none lost"
    },
  )
}

// ---------------------------------------------------------------------------
// The container's id decides between continuing and a replaced container.

const old_id = "1111111111111111111111111111111111111111111111111111111111111111"

const new_id = "2222222222222222222222222222222222222222222222222222222222222222"

/// A row of the plan: what was tracked, the id inspect gave, and what the read
/// does.
type PlanRow {
  PlanRow(
    name: String,
    tracking: container_log.Tracking,
    id: String,
    plan: container_log.Plan,
  )
}

pub fn the_containers_id_decides_between_continuing_and_a_replaced_container_test() -> Nil {
  use <- owned_test.run(60_000)
  let cursor = Cursor(token: "2026-11-20T09:10:12-05:00", taken: 2)
  let continued = [
    "logs",
    "--timestamps",
    "--since",
    "2026-11-20T09:10:12-05:00",
    "--tail",
    "5000",
    "genesis-play",
  ]
  let from_the_tail = [
    "logs",
    "--timestamps",
    "--tail",
    "1000",
    "genesis-play",
  ]
  let rows = [
    PlanRow(
      "the same id continues from the cursor",
      Tracking(id: Some(old_id), cursor: Some(cursor)),
      old_id,
      Plan(
        tracking: Tracking(id: Some(old_id), cursor: Some(cursor)),
        mark: None,
        arguments: continued,
      ),
    ),
    PlanRow(
      "the first read takes the tail, with no mark",
      container_log.unread,
      old_id,
      Plan(
        tracking: Tracking(id: Some(old_id), cursor: None),
        mark: None,
        arguments: from_the_tail,
      ),
    ),
    PlanRow(
      "the same id with no line read yet takes the tail again, with no mark",
      Tracking(id: Some(old_id), cursor: None),
      old_id,
      Plan(
        tracking: Tracking(id: Some(old_id), cursor: None),
        mark: None,
        arguments: from_the_tail,
      ),
    ),
    PlanRow(
      "a new id after reads that gave no line is a replaced container too: the mark",
      Tracking(id: Some(old_id), cursor: None),
      new_id,
      Plan(
        tracking: Tracking(id: Some(new_id), cursor: None),
        mark: Some(ContainerReplaced),
        arguments: from_the_tail,
      ),
    ),
    PlanRow(
      "a new id is a replaced container: the mark, the cursor reset, the tail",
      Tracking(id: Some(old_id), cursor: Some(cursor)),
      new_id,
      Plan(
        tracking: Tracking(id: Some(new_id), cursor: None),
        mark: Some(ContainerReplaced),
        arguments: from_the_tail,
      ),
    ),
  ]
  list.each(rows, fn(row) {
    assert container_log.plan(
        tracking: row.tracking,
        container: container_log.server_container,
        id: row.id,
      )
      == row.plan
      as row.name
  })

  // A container that was missing and is back is the tracked one when its id is
  // the same: a failed read leaves the tracking as it was, so the plan after it
  // is the one before it. A new id after it is a replacement.
  let tracked = Tracking(id: Some(old_id), cursor: Some(cursor))
  assert container_log.plan(
      tracking: tracked,
      container: container_log.server_container,
      id: old_id,
    ).mark
    == None
    as "missing, then back with the same id: continues"
  assert container_log.plan(
      tracking: tracked,
      container: container_log.server_container,
      id: new_id,
    ).mark
    == Some(ContainerReplaced)
    as "missing, then a new id: the mark"

  // The arguments are a list: a token with a space or a leading dash, and a
  // container named with either, stays one argument each.
  let odd = Cursor(token: "-a b", taken: 1)
  let plan =
    container_log.plan(
      tracking: Tracking(id: Some(old_id), cursor: Some(odd)),
      container: "--x y",
      id: old_id,
    )
  assert plan.arguments
    == ["logs", "--timestamps", "--since", "-a b", "--tail", "5000", "--x y"]
    as "each token is one argument"
}

// ---------------------------------------------------------------------------
// What podman says when it cannot answer is one reason each.

fn finished(
  text: String,
  status: Int,
) -> Result(script.Finished, script.Failure) {
  Ok(Finished(output: bytes(text), status:))
}

const no_container_logs =
  "Error: no container with name or ID \"genesis-play\" found: no such container\n"

const no_container_inspect = "Error: no such container \"genesis-play\"\n"

const cannot_connect =
  "Cannot connect to Podman. Please verify your connection to the Linux system using `podman system connection list`, or try `podman machine init` and `podman machine start` to manage a new Linux VM\n"

const socket_missing =
  "Error: unable to connect to Podman socket: Get \"http://d/v6.1.4/libpod/_ping\": dial unix /nonexistent-969.sock: connect: no such file or directory\n"

const socket_refused =
  "Error: unable to connect to Podman socket: Get \"http://d/v6.1.4/libpod/_ping\": dial unix /nonexistent-969.sock: connect: connection refused\n"

/// A row of the reasons: what the call gave and the reason it becomes.
type ReasonRow {
  ReasonRow(
    name: String,
    answer: Result(script.Finished, script.Failure),
    reason: follow.Trouble,
  )
}

pub fn what_podman_says_when_it_cannot_answer_becomes_one_reason_each_test() -> Nil {
  use <- owned_test.run(60_000)
  let unreachable = fn(error_line) { PodmanUnreachable(reason: error_line) }
  let rows = [
    ReasonRow(
      "logs of a missing container",
      finished(no_container_logs, 125),
      NotThere,
    ),
    ReasonRow(
      "inspect of a missing container",
      finished(no_container_inspect, 125),
      NotThere,
    ),
    ReasonRow(
      "no socket file",
      finished(cannot_connect <> socket_missing, 125),
      unreachable(
        "unable to connect to Podman socket: Get \"http://d/v6.1.4/libpod/_ping\": dial unix /nonexistent-969.sock: connect: no such file or directory",
      ),
    ),
    ReasonRow(
      "a socket with no listener",
      finished(cannot_connect <> socket_refused, 125),
      unreachable(
        "unable to connect to Podman socket: Get \"http://d/v6.1.4/libpod/_ping\": dial unix /nonexistent-969.sock: connect: connection refused",
      ),
    ),
    ReasonRow(
      "the connect words with no Error line carry their own line",
      finished(cannot_connect, 125),
      unreachable(
        "Cannot connect to Podman. Please verify your connection to the Linux system using `podman system connection list`, or try `podman machine init` and `podman machine start` to manage a new Linux VM",
      ),
    ),
    ReasonRow(
      "the deadline reached",
      Error(DeadlineReached(deadline_ms: 5000)),
      Unreadable("timed out after 5 s"),
    ),
    ReasonRow(
      "the executable not found",
      Error(NotFound("/opt/homebrew/bin/podman")),
      Unreadable("cannot find /opt/homebrew/bin/podman"),
    ),
    ReasonRow(
      "the executable not executable",
      Error(NotExecutable("/opt/homebrew/bin/podman")),
      Unreadable("cannot run /opt/homebrew/bin/podman: it is not executable"),
    ),
    ReasonRow(
      "the executable not started",
      Error(NotStarted("/opt/homebrew/bin/podman", "emfile")),
      Unreadable("cannot start /opt/homebrew/bin/podman: emfile"),
    ),
    ReasonRow(
      "exit 125 with a text no row names is its first line",
      finished(
        "Error: parsing --since \"notatime\": unable to interpret time value\nmore\n",
        125,
      ),
      Unreadable(
        "Error: parsing --since \"notatime\": unable to interpret time value",
      ),
    ),
    ReasonRow(
      "blank lines before podman's words are not its first line",
      finished("\nError: something\n", 125),
      Unreadable("Error: something"),
    ),
    ReasonRow(
      "a first line over 200 characters is cut at 200",
      finished("Error: " <> string.repeat("x", 300) <> "\n", 125),
      Unreadable(string.slice("Error: " <> string.repeat("x", 300), 0, 200)),
    ),
    ReasonRow(
      "a failure that printed nothing is its status",
      finished("", 3),
      Unreadable("exit status 3"),
    ),
  ]
  list.each(rows, fn(row) {
    assert container_log.container_id(row.answer) == Error(row.reason)
      as { row.name <> " (inspect)" }
    assert result_of_log(row.answer) == Error(row.reason)
      as { row.name <> " (logs)" }
  })

  // An id is 64 hex characters, and what is not one is unreadable.
  assert container_log.container_id(finished(old_id <> "\n", 0)) == Ok(old_id)
  list.each(
    [
      "",
      "\n",
      "abc\n",
      string.repeat("g", 64) <> "\n",
      old_id <> "1\n",
      old_id <> "\nmore\n",
    ],
    fn(text) {
      assert container_log.container_id(finished(text, 0))
        == Error(Unreadable("unreadable answer"))
        as text
    },
  )

  // A read that ends well with podman's own words in it keeps the words out of
  // the lines.
  let assert Ok(split) =
    container_log.log_output(finished("2026-11-20T09:10:12-05:00 a\n", 0))
  assert split.lines == [line("2026-11-20T09:10:12-05:00", "a")]
}

fn result_of_log(
  answer: Result(script.Finished, script.Failure),
) -> Result(container_log.Output, follow.Trouble) {
  container_log.log_output(answer)
}

// ---------------------------------------------------------------------------
// The two containers are the two the scripts name.

pub fn the_followed_containers_are_the_two_the_scripts_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(library) = simplifile.read("dev/play_service/lib.sh")
    as "the play service's library is in the repository"
  let value_of = fn(name) {
    let assert [assignment] =
      string.split(library, "\n")
      |> list.filter(string.starts_with(_, name <> "="))
      as { "lib.sh sets " <> name <> " once" }
    string.drop_start(assignment, string.length(name) + 1)
  }
  assert container_log.server_container == value_of("server_container")
  assert container_log.database_container == value_of("postgres_container")
  assert container_log.container_name(ServerLog)
    == Ok(container_log.server_container)
  assert container_log.container_name(DatabaseLog)
    == Ok(container_log.database_container)
  assert container_log.container_name(log_lines.UpdaterLog) == Error(Nil)
  assert container_log.container_name(log_lines.LaunchdLog) == Error(Nil)
  assert !string.starts_with(container_log.server_container, "-")
  assert !string.starts_with(container_log.database_container, "-")
}

// ---------------------------------------------------------------------------
// The follower, with a reader the test answers.

/// A read the follower started: the tracking it was asked to read with, and the
/// answer function it was handed. The test answers by calling it.
type Call {
  Call(
    tracking: container_log.Tracking,
    answer: fn(Result(container_log.Read, follow.Trouble)) -> Nil,
  )
}

fn following(
  source source: log_lines.Source,
  calls calls: Subject(Call),
  deadline_ms deadline_ms: Int,
) -> Subject(container_follow.Message) {
  let assert Ok(started) =
    container_follow.start(container_follow.Settings(
      source:,
      start_read: fn(tracking, answer) {
        process.send(calls, Call(tracking:, answer:))
      },
      interval_ms: 86_400_000,
      deadline_ms:,
      arm: timers.arm(process.new_subject()),
      watcher: None,
    ))
  started.data
}

fn next_call(calls: Subject(Call)) -> Call {
  open_wait.received(from: calls, what: "the follower to start a read")
}

/// The follower has handled everything sent to it before this, so a read it
/// would have started or an update it would have sent is already in the
/// test's mailbox.
fn handled(follower: Subject(container_follow.Message)) -> Nil {
  let _count = read_poll.subscriber_count(follower)
  Nil
}

fn nothing_sent(subject: Subject(a)) -> Bool {
  process.receive(subject, 0) == Error(Nil)
}

fn update(subscriber: Subject(Followed)) -> Followed {
  open_wait.received(from: subscriber, what: "an update of the follower")
}

fn shown(followed: Followed) -> List(String) {
  list.map(followed.entries, fn(entry) {
    case entry {
      log_lines.Line(text:, ..) -> text
      log_lines.Marker(mark: ContainerReplaced, ..) -> "[container replaced]"
      log_lines.Marker(..) -> "[mark]"
    }
  })
}

fn gave(
  tracking tracking: container_log.Tracking,
  mark mark: Option(log_lines.Mark),
  text text: String,
) -> Result(container_log.Read, follow.Trouble) {
  Ok(Read(tracking:, mark:, bytes: bytes(text)))
}

fn tracked(
  id id: String,
  token token: String,
  taken taken: Int,
) -> container_log.Tracking {
  Tracking(id: Some(id), cursor: Some(Cursor(token:, taken:)))
}

pub fn a_failed_container_read_keeps_the_lines_and_says_why_and_a_good_read_continues_test() -> Nil {
  use <- owned_test.run(20_000)
  let calls = process.new_subject()
  let follower =
    following(source: ServerLog, calls: calls, deadline_ms: 86_400_000)
  let subscriber = process.new_subject()
  read_poll.subscribe(poll: follower, subscriber:)

  // The first read is of a container not read yet; nothing is sent before it
  // is answered, and then the three lines, once.
  let first = next_call(calls)
  assert first.tracking == container_log.unread
  handled(follower)
  assert nothing_sent(subscriber) as "nothing is sent before a read answers"
  let after_three = tracked(id: old_id, token: t0, taken: 3)
  first.answer(gave(tracking: after_three, mark: None, text: "a\nb\nc\n"))
  let three = update(subscriber)
  assert shown(three) == ["a", "b", "c"]
  assert three.trouble == None
  assert three.source == ServerLog
  assert three.path == "podman logs genesis-play"

  // Podman not reachable: the same lines, with the trouble; the tracking of the
  // last good read is what the next read is asked with.
  read_poll.read_now(follower)
  let second = next_call(calls)
  assert second.tracking == after_three
  second.answer(Error(PodmanUnreachable("down")))
  let unreachable = update(subscriber)
  assert shown(unreachable) == ["a", "b", "c"]
  assert unreachable.trouble == Some(PodmanUnreachable("down"))

  // A good read with one more line: that line once, and the trouble gone.
  read_poll.read_now(follower)
  let third = next_call(calls)
  assert third.tracking == after_three
  let after_four = tracked(id: old_id, token: t1, taken: 1)
  third.answer(gave(tracking: after_four, mark: None, text: "d\n"))
  let four = update(subscriber)
  assert shown(four) == ["a", "b", "c", "d"]
  assert four.trouble == None

  // A read that changes nothing sends nothing.
  read_poll.read_now(follower)
  next_call(calls).answer(gave(tracking: after_four, mark: None, text: ""))
  handled(follower)
  assert nothing_sent(subscriber) as "a read that gave nothing sends nothing"

  // The container is not there: the lines stay with the trouble. A new id after
  // it: the mark, then the new lines.
  read_poll.read_now(follower)
  next_call(calls).answer(Error(NotThere))
  let missing = update(subscriber)
  assert shown(missing) == ["a", "b", "c", "d"]
  assert missing.trouble == Some(NotThere)
  read_poll.read_now(follower)
  let fifth = next_call(calls)
  assert fifth.tracking == after_four
  fifth.answer(gave(
    tracking: tracked(id: new_id, token: t2, taken: 1),
    mark: Some(ContainerReplaced),
    text: "x\n",
  ))
  let replaced = update(subscriber)
  assert shown(replaced) == ["a", "b", "c", "d", "[container replaced]", "x"]
  assert replaced.trouble == None

  // A failed first read: no lines and the reason.
  let more_calls = process.new_subject()
  let other =
    following(source: DatabaseLog, calls: more_calls, deadline_ms: 86_400_000)
  let other_subscriber = process.new_subject()
  read_poll.subscribe(poll: other, subscriber: other_subscriber)
  next_call(more_calls).answer(Error(Unreadable("timed out after 5 s")))
  let unreadable = update(other_subscriber)
  assert unreadable.entries == []
  assert unreadable.trouble == Some(Unreadable("timed out after 5 s"))
  assert unreadable.path == "podman logs genesis-play-postgres"
  assert unreadable.source == DatabaseLog
}

pub fn a_tick_while_a_container_read_runs_starts_no_second_read_test() -> Nil {
  use <- owned_test.run(20_000)
  let calls = process.new_subject()
  let follower = following(source: ServerLog, calls: calls, deadline_ms: 15_000)
  let subscriber = process.new_subject()
  read_poll.subscribe(poll: follower, subscriber:)
  let first = next_call(calls)

  // The follower hands the shared read one start, and a tick starts no second.
  read_poll.read_now(follower)
  handled(follower)
  assert nothing_sent(calls) as "a tick starts no second read"

  // The read's deadline comes: the follower shows it as failed, and the answer
  // that comes after is dropped.
  read_poll.deadline_now(follower)
  let timed_out = update(subscriber)
  assert timed_out.entries == []
  assert timed_out.trouble == Some(Unreadable("timed out after 15 s"))
  first.answer(gave(
    tracking: tracked(id: old_id, token: t0, taken: 1),
    mark: None,
    text: "late\n",
  ))
  handled(follower)
  assert nothing_sent(subscriber) as "an answer after the deadline is dropped"

  // The next tick reads again, from what was tracked before the dropped read.
  read_poll.read_now(follower)
  let second = next_call(calls)
  assert second.tracking == container_log.unread
  second.answer(gave(
    tracking: tracked(id: old_id, token: t1, taken: 1),
    mark: None,
    text: "fresh\n",
  ))
  assert shown(update(subscriber)) == ["fresh"]

  // The last page leaves while a read runs: the follower drops its tracking, so
  // the read a page gets next starts from nothing and the old read's answer,
  // which would continue from the dropped tracking, is not shown.
  read_poll.read_now(follower)
  let running = next_call(calls)
  read_poll.unsubscribe(poll: follower, subscriber:)
  let later = process.new_subject()
  read_poll.subscribe(poll: follower, subscriber: later)
  running.answer(gave(
    tracking: tracked(id: old_id, token: t2, taken: 1),
    mark: None,
    text: "stale\n",
  ))
  handled(follower)
  assert nothing_sent(later) as "the answer of the dropped read was shown"
  let assert Ok(fresh) = process.receive(calls, 0)
    as "the returning page was given no read of its own"
  assert fresh.tracking == container_log.unread
  fresh.answer(gave(
    tracking: tracked(id: new_id, token: t2, taken: 1),
    mark: None,
    text: "new\n",
  ))
  assert shown(update(later)) == ["new"]
  assert nothing_sent(subscriber) as "a page that left is sent nothing"
}

// ---------------------------------------------------------------------------
// The real reader, through the play service tests' fake `podman`.

fn read_of(
  podman podman: String,
  container container: String,
  tracking tracking: container_log.Tracking,
  deadline_ms deadline_ms: Int,
) -> Result(container_log.Read, follow.Trouble) {
  container_follow.read_container(
    podman:,
    container:,
    call_deadline_ms: deadline_ms,
    tracking:,
  )
}

/// Reads with a blocked `logs` until the fake has recorded its process id;
/// gives the answer and the id.
fn blocked_read(
  scene scene: play.Scene,
  podman podman: String,
  tracking tracking: container_log.Tracking,
  deadline_ms deadline_ms: Int,
) -> #(Result(container_log.Read, follow.Trouble), Int) {
  dashboard_support.until_pid_recorded(
    run: fn(deadline_ms) {
      read_of(podman:, container: "genesis-play", tracking:, deadline_ms:)
    },
    recorded: fn() { play.blocked_pids(scene:, key: "logs.genesis-play") },
    deadline_ms:,
  )
}

pub fn the_real_reader_reads_both_commands_through_a_fake_podman_and_leaves_none_behind_test() -> Nil {
  use <- owned_test.run(60_000)
  use scene <- play.with_scene
  let podman = play.plant_podman(scene)
  let name = container_log.server_container
  play.plant_identity(scene:, name:, id: old_id)
  play.plant_container_log(
    scene:,
    name:,
    text: "2026-11-20T09:10:12-05:00 a\n2026-11-20T09:10:12-05:00 b\n2026-11-20T09:10:13-05:00 c\n",
  )

  // The first read: inspect, then the tail; the lines and the cursor.
  let assert Ok(first) =
    read_of(
      podman:,
      container: name,
      tracking: container_log.unread,
      deadline_ms: 5000,
    )
  assert first.bytes == bytes("a\nb\nc\n")
  assert first.mark == None
  assert first.tracking
    == tracked(id: old_id, token: "2026-11-20T09:10:13-05:00", taken: 1)
  assert play.calls(scene)
    == [
      "podman container inspect --format {{.Id}} genesis-play",
      "podman logs --timestamps --tail 1000 genesis-play",
    ]

  // The second read asks since the last line's token, and the line podman
  // gives again is not shown twice.
  play.plant_container_log(
    scene:,
    name:,
    text: "2026-11-20T09:10:13-05:00 c\n2026-11-20T09:10:14-05:00 d\n",
  )
  let assert Ok(second) =
    read_of(
      podman:,
      container: name,
      tracking: first.tracking,
      deadline_ms: 5000,
    )
  assert second.bytes == bytes("d\n")
  assert second.tracking
    == tracked(id: old_id, token: "2026-11-20T09:10:14-05:00", taken: 1)
  assert list.drop(play.calls(scene), 2)
    == [
      "podman container inspect --format {{.Id}} genesis-play",
      "podman logs --timestamps --since 2026-11-20T09:10:13-05:00 --tail 5000 genesis-play",
    ]

  // A `logs` that blocks: unreadable, timed out, and the fake is not alive.
  play.plant_block(scene:, key: "logs." <> name)
  let #(blocked, pid) =
    blocked_read(scene:, podman:, tracking: second.tracking, deadline_ms: 200)
  let assert Error(Unreadable(reason)) = blocked
  assert string.starts_with(reason, "timed out after ")
  assert !play.alive(pid) as "the blocked call is still running"
  let assert Ok(Nil) =
    simplifile.delete(scene.fakes <> "/answers/logs." <> name <> ".block")

  // `logs` exits 125 with the unreachable text: podman is not reachable, and
  // the log text it printed is not taken.
  play.plant(
    scene:,
    key: "logs." <> name,
    answer: play.Answer(
      exits: [125],
      output: "2026-11-20T09:10:15-05:00 not taken\n",
      error: cannot_connect <> socket_missing,
    ),
  )
  let assert Error(PodmanUnreachable(reason)) =
    read_of(
      podman:,
      container: name,
      tracking: second.tracking,
      deadline_ms: 5000,
    )
  assert string.contains(reason, "no such file or directory")

  // A good read after it: the lines logged meanwhile, once.
  play.plant_container_log(
    scene:,
    name:,
    text: "2026-11-20T09:10:14-05:00 d\n2026-11-20T09:10:15-05:00 e\n2026-11-20T09:10:15-05:00 f\n",
  )
  let assert Ok(third) =
    read_of(
      podman:,
      container: name,
      tracking: second.tracking,
      deadline_ms: 5000,
    )
  assert third.bytes == bytes("e\nf\n")
  assert third.tracking
    == tracked(id: old_id, token: "2026-11-20T09:10:15-05:00", taken: 2)

  // The container was replaced between two reads: the mark and its tail.
  play.plant_identity(scene:, name:, id: new_id)
  play.plant_container_log(
    scene:,
    name:,
    text: "2026-11-20T09:10:16-05:00 new\n",
  )
  let assert Ok(replaced) =
    read_of(
      podman:,
      container: name,
      tracking: third.tracking,
      deadline_ms: 5000,
    )
  assert replaced.mark == Some(ContainerReplaced)
  assert replaced.bytes == bytes("new\n")

  // The database's container is read the same way, and a container that is not
  // there is `NotThere`.
  let database = container_log.database_container
  play.plant_identity(scene:, name: database, id: old_id)
  play.plant_container_log(
    scene:,
    name: database,
    text: "2026-11-20T09:10:12-05:00 LOG\n",
  )
  let assert Ok(from_database) =
    read_of(
      podman:,
      container: database,
      tracking: container_log.unread,
      deadline_ms: 5000,
    )
  assert from_database.bytes == bytes("LOG\n")
  play.plant(
    scene:,
    key: "identity." <> name,
    answer: play.Answer(
      exits: [125],
      output: "",
      error: "Error: no such container \"genesis-play\"\n",
    ),
  )
  assert read_of(
      podman:,
      container: name,
      tracking: replaced.tracking,
      deadline_ms: 5000,
    )
    == Error(NotThere)

  // Every call named one of the two containers, and only `container inspect`
  // and `logs`.
  list.each(play.calls(scene), fn(call) {
    assert string.starts_with(
        call,
        "podman container inspect --format {{.Id}} ",
      )
      || string.starts_with(call, "podman logs --timestamps ")
      as call
    assert string.ends_with(call, " genesis-play")
      || string.ends_with(call, " genesis-play-postgres")
      as call
  })
}
