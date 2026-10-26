//// The process that owns one world's map and its senders. A player's connection
//// asks it to join; it holds the player's unit and tells the players in range
//// through the sender pool. The expected values come from the issue's plan
//// (#40: a map process for a character's world holding the player's unit,
//// with the sender pool #28 chose, the heap ceilings #31 chose, the supervisor
//// settings #34 chose and a registration with the snapshot #44 made), the
//// designing-processes skill (cleanup that must happen runs in a process that
//// monitors the dying one; every process starts under a supervisor; a
//// restarted map starts empty) and the topology trial's crash cost (rest for
//// one: a sender that crashes takes the map with it, the map alone does not
//// take the senders). A test waits for the events it needs, never a fixed
//// time.

import genesis_prime/map/delivery.{type Delivery, Appeared, Disappeared}
import genesis_prime/map/heap_limit
import genesis_prime/map/unit.{type PlayerUnit}
import genesis_prime/map/world_map.{CharacterAlreadyOnMap}
import genesis_prime/map/world_map_process.{NotAnswering, Refused}
import genesis_prime/telemetry/snapshot
import gleam/dict
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/otp/static_supervisor
import log_capture.{Fields, Whole}
import map_support
import owned_test
import spawn_watch
import supervisor_children
import supervisor_flags

/// How long a test waits for something the map does, in milliseconds. The
/// event comes at once; the rest is for a loaded machine.
const event_wait_ms = 5000

fn start_map(
  world_id world_id: Int,
  limits limits: heap_limit.HeapLimits,
) -> #(world_map_process.Settings, Pid) {
  let settings =
    map_support.settings(
      world_id:,
      snapshot: map_support.start_snapshot(),
      limits:,
    )
  let assert Ok(started) = world_map_process.start(settings)
    as "the map did not start"
  #(settings, started.pid)
}

fn map_of(
  settings: world_map_process.Settings,
) -> Subject(world_map_process.Message) {
  process.named_subject(settings.map)
}

fn join(
  settings settings: world_map_process.Settings,
  character_id character_id: Int,
  x x: Float,
  connection connection: Subject(Delivery),
) -> PlayerUnit {
  let assert Ok(unit) =
    world_map_process.join(
      map: map_of(settings),
      newcomer: map_support.newcomer(character_id:, x:),
      connection:,
      within_ms: event_wait_ms,
    )
    as "the character joined the map"
  unit
}

pub fn a_map_started_for_a_world_holds_the_unit_of_a_character_that_joins_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_map(world_id: 7, limits: map_support.no_limits())
  assert world_map_process.units(map_of(settings), event_wait_ms) == Ok([])
    as "a new map holds no unit"
  let unit =
    join(settings:, character_id: 11, x: 0.0, connection: process.new_subject())
  assert unit.id == 1 && unit.character_id == 11
    as "the first unit of a map has id 1 and the character's id"
  assert world_map_process.units(map_of(settings), event_wait_ms) == Ok([unit])
    as "the map holds the unit"
}

pub fn a_character_is_one_unit_on_a_map_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_map(world_id: 7, limits: map_support.no_limits())
  let unit =
    join(settings:, character_id: 11, x: 0.0, connection: process.new_subject())
  assert world_map_process.join(
      map: map_of(settings),
      newcomer: map_support.newcomer(character_id: 11, x: 5.0),
      connection: process.new_subject(),
      within_ms: event_wait_ms,
    )
    == Error(Refused(CharacterAlreadyOnMap(unit_id: unit.id)))
    as "a character that is on the map cannot join it again"
  assert world_map_process.units(map_of(settings), event_wait_ms) == Ok([unit])
}

pub fn a_player_in_range_is_told_of_the_newcomer_and_the_newcomer_of_the_player_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_map(world_id: 7, limits: map_support.no_limits())
  let first_connection = process.new_subject()
  let second_connection = process.new_subject()
  let first =
    join(settings:, character_id: 11, x: 0.0, connection: first_connection)
  let second =
    join(settings:, character_id: 12, x: 60.0, connection: second_connection)
  assert process.receive(first_connection, event_wait_ms)
    == Ok(Appeared(second))
    as "the first player is told that the second appeared"
  assert process.receive(second_connection, event_wait_ms)
    == Ok(Appeared(first))
    as "the second player is told of the first"
}

pub fn a_player_out_of_range_is_told_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_map(world_id: 7, limits: map_support.no_limits())
  let near_connection = process.new_subject()
  let far_connection = process.new_subject()
  let _near =
    join(settings:, character_id: 11, x: 0.0, connection: near_connection)
  let _far =
    join(settings:, character_id: 12, x: 900.0, connection: far_connection)
  let #(third_process, third_connection) = start_connection_process()
  let third =
    join(settings:, character_id: 13, x: 30.0, connection: third_connection)
  process.kill(third_process)
  // Everything said about the third unit passes through one sender, in order:
  // that it appeared, then that it went. When the near player has heard both,
  // the sender has sent everything it was going to send about that unit, so a
  // delivery to the far player would be in its mailbox by now.
  assert process.receive(near_connection, event_wait_ms) == Ok(Appeared(third))
  assert process.receive(near_connection, event_wait_ms)
    == Ok(Disappeared(third.id))
  assert process.receive(far_connection, 0) == Error(Nil)
    as "the player 900 metres away was told nothing of a unit 870 metres from it"
}

/// A process that owns a subject for deliveries until it is killed, and the
/// subject: a connection that can end.
fn start_connection_process() -> #(Pid, Subject(Delivery)) {
  let reported = process.new_subject()
  let connection_process =
    process.spawn_unlinked(fn() {
      let connection = process.new_subject()
      process.send(reported, connection)
      process.sleep_forever()
    })
  let assert Ok(connection) = process.receive(reported, event_wait_ms)
    as "the connection process did not start"
  #(connection_process, connection)
}

pub fn a_unit_leaves_the_map_when_its_connection_ends_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_map(world_id: 7, limits: map_support.no_limits())
  let observer = process.new_subject()
  let _watcher = join(settings:, character_id: 11, x: 0.0, connection: observer)
  let #(connection_process, connection) = start_connection_process()
  let leaving = join(settings:, character_id: 12, x: 40.0, connection:)
  assert process.receive(observer, event_wait_ms) == Ok(Appeared(leaving))
  process.kill(connection_process)
  assert process.receive(observer, event_wait_ms) == Ok(Disappeared(leaving.id))
    as "the map monitors the connection of each player, and takes the unit off the map and tells the players in range when it ends"
  let assert Ok(units) =
    world_map_process.units(map_of(settings), event_wait_ms)
  assert list.map(units, fn(unit) { unit.character_id }) == [11]
    as "only the observer's unit is left"
}

pub fn the_map_and_each_sender_are_killed_at_the_ceilings_the_trial_chose_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, supervisor) =
    start_map(world_id: 7, limits: heap_limit.measured)
  let assert Ok(map_pid) = process.named(settings.map)
    as "the map is registered under its name"
  assert map_support.max_heap_words(map_pid) == 8_388_608
    as "#31: the map process's ceiling is 4 times its largest sampled peak, 8,388,608 words (64 MB)"
  let children = supervisor_children.in_start_order(supervisor)
  let senders = list.take(children, list.length(children) - 1)
  assert senders != [] as "the map has senders"
  list.each(senders, fn(sender) {
    assert map_support.max_heap_words(sender) == 131_072
      as "#31: a sender's ceiling is 131,072 words (1 MB)"
  })
}

pub fn a_map_has_one_sender_for_each_scheduler_online_started_before_the_map_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, supervisor) =
    start_map(world_id: 7, limits: map_support.no_limits())
  let assert Ok(map_pid) = process.named(settings.map)
    as "the map is registered under its name"
  let children = supervisor_children.in_start_order(supervisor)
  assert list.length(children) == map_support.schedulers_online() + 1
    as "#28's choice: the map hands each delivery to a pool of one sender for each scheduler online"
  assert list.last(children) == Ok(map_pid)
    as "the senders start first and the map process last, so a rebuilt map reaches the rebuilt senders"
}

pub fn a_map_is_one_supervisor_that_restarts_rest_for_one_3_in_5_seconds_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(_, supervisor) = start_map(world_id: 7, limits: map_support.no_limits())
  assert supervisor_flags.read(supervisor)
    == supervisor_flags.Flags(
      strategy: static_supervisor.RestForOne,
      intensity: 3,
      period: 5,
    )
    as "#34: a map subtree is rest for one, senders first, 3 restarts in 5 seconds; a rebuild takes milliseconds (#28's crash cost)"
}

pub fn every_process_of_a_map_is_supervised_test() -> Nil {
  use <- owned_test.run(30_000)
  let watch = spawn_watch.begin()
  let #(_, supervisor) = start_map(world_id: 7, limits: map_support.no_limits())
  assert spawn_watch.unsupervised(watch, supervisor) == []
    as "designing-processes: every process starts under a supervisor"
}

pub fn a_sender_that_dies_takes_the_map_down_and_the_map_starts_again_empty_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, supervisor) =
    start_map(world_id: 7, limits: map_support.no_limits())
  let _unit =
    join(settings:, character_id: 11, x: 0.0, connection: process.new_subject())
  let assert Ok(map_before) = process.named(settings.map)
    as "the map is registered under its name"
  let assert [sender, ..] = supervisor_children.in_start_order(supervisor)
    as "the map has senders"
  let map_monitor = process.monitor(map_before)
  process.kill(sender)
  let assert Ok(Nil) =
    process.new_selector()
    |> process.select_specific_monitor(map_monitor, fn(_down) { Nil })
    |> process.selector_receive(within: event_wait_ms)
    as "the map did not stop with its sender"
  let assert Ok(units) = await_units(settings) as "the rebuilt map answers"
  assert units == []
    as "designing-processes: a restarted map starts empty; every player must join again"
}

pub fn a_map_that_dies_alone_leaves_its_senders_running_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, supervisor) =
    start_map(world_id: 7, limits: map_support.no_limits())
  let before = supervisor_children.in_start_order(supervisor)
  let assert Ok(map_before) = process.named(settings.map)
    as "the map is registered under its name"
  let map_monitor = process.monitor(map_before)
  process.kill(map_before)
  let assert Ok(Nil) =
    process.new_selector()
    |> process.select_specific_monitor(map_monitor, fn(_down) { Nil })
    |> process.selector_receive(within: event_wait_ms)
    as "the map did not die"
  let assert Ok(_) = await_units(settings) as "the rebuilt map answers"
  let after = supervisor_children.in_start_order(supervisor)
  assert list.take(after, list.length(after) - 1)
    == list.take(before, list.length(before) - 1)
    as "rest for one: the map starts after the senders, so a map that dies restarts alone"
}

/// Asks the rebuilt map for its units until it answers, a name that is not
/// registered yet being no answer, for at most the event wait.
fn await_units(
  settings: world_map_process.Settings,
) -> Result(List(PlayerUnit), Nil) {
  let expired = process.new_subject()
  let _timer = process.send_after(expired, event_wait_ms, Nil)
  ask_units_until(settings, expired)
}

fn ask_units_until(
  settings: world_map_process.Settings,
  expired: Subject(Nil),
) -> Result(List(PlayerUnit), Nil) {
  case process.named(settings.map) {
    Ok(_) ->
      case world_map_process.units(map_of(settings), 200) {
        Ok(units) -> Ok(units)
        Error(Nil) -> retry_unless_expired(settings, expired)
      }
    Error(Nil) -> retry_unless_expired(settings, expired)
  }
}

fn retry_unless_expired(
  settings: world_map_process.Settings,
  expired: Subject(Nil),
) -> Result(List(PlayerUnit), Nil) {
  case process.receive(expired, 0) {
    Ok(Nil) -> Error(Nil)
    Error(Nil) -> ask_units_until(settings, expired)
  }
}

pub fn a_map_that_does_not_answer_is_not_a_crash_of_the_asker_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_map(world_id: 7, limits: map_support.no_limits())
  let assert Ok(map_pid) = process.named(settings.map) as "the map is running"
  suspend(map_pid)
  assert world_map_process.join(
      map: map_of(settings),
      newcomer: map_support.newcomer(character_id: 11, x: 0.0),
      connection: process.new_subject(),
      within_ms: 50,
    )
    == Error(NotAnswering)
    as "designing-processes: a request carries a chosen deadline when the asker must not block; a late reply is expected and handled"
  resume(map_pid)
  let assert Ok(units) =
    world_map_process.units(map_of(settings), event_wait_ms)
    as "the map answers after the late request: it is not harmed by a request whose asker has gone"
  assert list.map(units, fn(unit) { unit.character_id }) == [11]
    as "the late request was still handled, so its asker, which gave up, must close its connection: the map takes the unit off the map when that connection ends"
}

pub fn the_map_registers_its_processes_with_the_snapshot_test() -> Nil {
  use <- owned_test.run(30_000)
  let capture = log_capture.start()
  let name = process.new_name("snapshot_of_a_map")
  let assert Ok(snapshot_started) =
    snapshot.start(snapshot.Settings(name:, interval_milliseconds: 50))
    as "the snapshot process did not start"
  let settings =
    map_support.settings(
      world_id: 7,
      snapshot: name,
      limits: map_support.no_limits(),
    )
  let assert Ok(_) = world_map_process.start(settings)
    as "the map did not start"
  let assert Ok(line) =
    next_line_about_the_map(
      capture:,
      snapshot: snapshot_started.pid,
      key: "map_7_largest_queue",
    )
    as "no snapshot line reported the map's largest mailbox"
  let assert Ok(Fields(numbers)) = dict.get(line.metadata, "numbers")
    as "the snapshot has numbers"
  assert dict.has_key(numbers, "map_7_largest_heap_words")
    as "#44: a kind of busy process reports its largest mailbox and its largest heap; the map and its senders are one kind named for the world"
  let assert Ok(Whole(heap)) = dict.get(numbers, "map_7_largest_heap_words")
    as "the heap is a whole number of words"
  assert heap > 0 as "a process holds at least a word"
}

fn next_line_about_the_map(
  capture capture: log_capture.Capture,
  snapshot pid: Pid,
  key key: String,
) -> Result(log_capture.Event, Nil) {
  case log_capture.next_from(capture, from: pid, within: event_wait_ms) {
    Ok(line) ->
      case dict.get(line.metadata, "numbers") {
        Ok(Fields(numbers)) ->
          case dict.has_key(numbers, key) {
            True -> Ok(line)
            False -> next_line_about_the_map(capture:, snapshot: pid, key:)
          }
        _ -> next_line_about_the_map(capture:, snapshot: pid, key:)
      }
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "map_support_ffi", "suspend")
fn suspend(pid: Pid) -> Nil

@external(erlang, "map_support_ffi", "resume")
fn resume(pid: Pid) -> Nil
