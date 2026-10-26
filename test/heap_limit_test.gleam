//// The heap ceiling of prototype C's processes. A process past its ceiling is
//// killed by the runtime and rebuilt by its supervisor, and a ceiling of no
//// words cannot be made, because the runtime reads 0 words as no ceiling.
////
//// Source of the expected values: `erlang:process_flag(max_heap_size, ...)`
//// with `kill` true ends a process whose heap needs more than the limit, the
//// messages waiting in its mailbox included, with reason `killed`, and a
//// limit of 0 means no limit. The rebuild is the prototype's own supervisor
//// restarting the map process from the spawn list (`map_process`'s module
//// doc).

import genesis_prime/topology/heap_limit.{HeapLimits}
import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/position.{Position}
import genesis_prime/topology/update
import genesis_prime/topology/workload.{Workload}
import gleam/dict
import gleam/erlang/process.{type Pid}
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/result
import owned_test

/// The map process's ceiling, in words. A map of this test's workload (1
/// player and 10 creatures), idle, holds between 1,200 words right after its
/// start and 4,400 words at the most over the next two seconds
/// (`total_heap_size`, read every 100 ms), and the limit is applied first in
/// the initialiser, so the build of its state must fit under it: 20,000 words
/// is more than 4 times the largest of those. The flood of moves passes it by
/// the messages that wait in the map's mailbox.
const ceiling_words = 20_000

pub fn a_map_process_past_its_heap_ceiling_is_killed_and_rebuilt_test() -> Nil {
  use <- owned_test.run(10_000)
  let workload =
    Workload(..workload.default(), players: 1, creatures: 10, map_size: 20.0)
  let key = reference.new()
  measurement.put_spawn_list(
    key,
    workload.spawn_list(workload)
      |> list.map(fn(unit) { #(unit.id, unit) })
      |> dict.from_list,
  )
  let assert Ok(ceiling) = heap_limit.words(ceiling_words)
    as "the ceiling can be made"
  let assert Ok(started) =
    map_process.start(
      workload,
      key,
      map_process.SenderPool,
      HeapLimits(map: ceiling, sender: heap_limit.no_limit),
    )
    as "a map that holds far less than its ceiling starts"
  let prototype = started.data
  let senders = prototype.sender_processes()
  let assert Ok(first_map) = map_process_of(prototype)
    as "the started prototype has a map process"
  assert !list.contains(senders, first_map) as "the map is not a sender"
  let first_connection = process.new_subject()
  prototype.join(1, first_connection)
  let assert Ok(joined) = process.receive(first_connection, within: 2000)
    as "the started map answers a join"
  assert joined == update.Joined(unit_id: 1)
    as "the map joins the player to its own unit"

  let map_monitor = process.monitor(first_map)
  let flooder = process.spawn_unlinked(fn() { flood_with_moves(prototype, 0) })
  let assert Ok(ended) =
    process.new_selector()
    |> process.select_specific_monitor(map_monitor, down_reason)
    |> process.selector_receive(within: 5000)
    as "the map did not end under a flood of moves"
  assert ended == process.Killed
    as "a map past its heap ceiling is killed with reason killed"
  stop_flooding(flooder)

  let rebuilt_map = await_rebuilt(prototype, first_map)
  assert rebuilt_map != first_map as "the map process is a new process"
  assert prototype.sender_processes() == senders
    as "only the map process is rebuilt, the senders are the same processes"
  let connection = process.new_subject()
  prototype.join(1, connection)
  let assert Ok(delivery) = process.receive(connection, within: 2000)
    as "the rebuilt map answers a join"
  assert delivery == update.Joined(unit_id: 1)
    as "the rebuilt map joins the player to its own unit"

  prototype.stop()
  measurement.erase_spawn_list(key)
}

pub fn a_heap_limit_below_one_word_cannot_be_built_test() -> Nil {
  use <- owned_test.run(1000)
  assert heap_limit.words(0) == Error(Nil)
    as "0 words is not a limit, the runtime reads it as no limit"
  assert heap_limit.words(-1) == Error(Nil) as "a negative count is not a limit"
  assert result.is_ok(heap_limit.words(1)) as "1 word is the smallest limit"
}

/// The pid of the prototype's map process, which is the owner process that is
/// not a sender, or an error while no map process holds the map's name.
fn map_process_of(prototype: Owner) -> Result(Pid, Nil) {
  let senders = prototype.sender_processes()
  list.find(prototype.owner_processes(), fn(pid) {
    !list.contains(senders, pid)
  })
}

fn down_reason(down: process.Down) -> process.ExitReason {
  case down {
    process.ProcessDown(reason:, ..) -> reason
    process.PortDown(reason:, ..) -> reason
  }
}

/// Moves player 1 back and forth over and over with no waiting, so moves reach
/// the map faster than it handles them and its mailbox grows. It never ends on
/// its own: after the map is killed its next send finds no process under the
/// map's name and crashes, which is its expected end, and the test kills it
/// at once if it is still running, so it never floods the rebuilt map.
fn flood_with_moves(prototype: Owner, count: Int) -> Nil {
  prototype.move(
    1,
    Position(x: int.to_float(count % 20), y: 5.0),
    measurement.monotonic_microseconds(),
  )
  flood_with_moves(prototype, count + 1)
}

/// Kills the flooding process, or does nothing when it has already crashed,
/// and returns once it is gone.
fn stop_flooding(flooder: Pid) -> Nil {
  let monitor = process.monitor(flooder)
  process.kill(flooder)
  let assert Ok(_down) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 2000)
    as "the flooding process did not stop"
  Nil
}

/// Waits until a map process other than `ended` holds the map's name, and
/// returns it. The runtime sends no message when a name is taken, so this reads
/// the prototype's own list of processes until it changes; the test's deadline
/// bounds it.
fn await_rebuilt(prototype: Owner, ended: Pid) -> Pid {
  case map_process_of(prototype) {
    Ok(pid) if pid != ended -> pid
    Ok(_) | Error(Nil) -> await_rebuilt(prototype, ended)
  }
}
