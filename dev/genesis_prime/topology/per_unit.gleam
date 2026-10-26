//// Prototype A: every creature and every player's unit is a process of its
//// own, with its position in a shared ETS table that other processes read to
//// find who is near.
////
//// The supervision tree is one supervisor with two children, started in this
//// order and restarted together (rest for one): the table owner, which owns
//// the table and cleans up after dead units, and a factory supervisor of
//// unit processes. A unit process that crashes is restarted alone from the
//// spawn list and writes its rows again; its players see it vanish and
//// reappear. A table owner that crashes loses every row, and nothing
//// rebuilds the units already running, so a run in which it crashed is
//// discarded.

import genesis_prime/topology/measurement.{type Counter}
import genesis_prime/topology/owner.{type Owner, Owner}
import genesis_prime/topology/per_unit/table.{type Table}
import genesis_prime/topology/per_unit/table_owner
import genesis_prime/topology/per_unit/unit_process
import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/update.{type Delivery}
import genesis_prime/topology/workload.{type Workload}
import gleam/dict
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/result

/// How many restarts the top supervisor allows in `restart_period_seconds`.
const restart_intensity = 100

/// The period of the top supervisor's restart limit, in seconds.
const restart_period_seconds = 5

/// How long a unit process has to stop when told to, in milliseconds.
const unit_shutdown_milliseconds = 1000

/// Starts the prototype: the table owner, the unit supervisor and one unit
/// process for every unit of the spawn list kept under `spawn_list_key`.
/// Players' connections join afterwards through the `Owner`. The supervisor
/// is linked to the calling process; the data is the `Owner` the players act
/// through.
pub fn start(
  workload workload: Workload,
  spawn_list_key spawn_list_key: Reference,
) -> Result(actor.Started(Owner), actor.StartError) {
  use parts <- result.map(start_parts(workload, spawn_list_key))
  parts.started
}

/// Kills one creature's process and returns the microseconds until the
/// rebuilt process handles a message again. It starts its own prototype with
/// no players from the spawn list kept under `spawn_list_key` and stops it.
pub fn crash_cost(
  workload workload: Workload,
  spawn_list_key spawn_list_key: Reference,
) -> Int {
  let assert Ok(parts) = start_parts(workload, spawn_list_key)
    as "the prototype did not start"
  let creature_id = workload.players + 1
  let assert Ok(row) = table.find(parts.table, creature_id)
    as "the first creature is not on the map"
  let assert Ok(victim) = process.subject_owner(row.owner)
    as "a unit's subject has an owner"
  let started_at = measurement.monotonic_microseconds()
  process.kill(victim)
  await_rebuilt(table: parts.table, unit_id: creature_id, victim:)
  let elapsed = measurement.monotonic_microseconds() - started_at
  owner.stop_supervisor(parts.started.pid)
  elapsed
}

/// The prototype as started, and the table its units share.
type Parts {
  Parts(started: actor.Started(Owner), table: Table(unit_process.Message))
}

fn start_parts(
  workload: Workload,
  spawn_list_key: Reference,
) -> Result(Parts, actor.StartError) {
  let handled = measurement.new_counter()
  let table_ready = process.new_subject()
  let factory_ready = process.new_subject()
  let factory =
    unit_process.factory()
    |> factory_supervisor.timeout(ms: unit_shutdown_milliseconds)
    |> factory_supervisor.restart_tolerance(
      intensity: restart_intensity,
      period: restart_period_seconds,
    )
    |> factory_supervisor.supervised
  use supervisor <- result.try(
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.restart_tolerance(
      intensity: restart_intensity,
      period: restart_period_seconds,
    )
    |> static_supervisor.add(table_owner.supervised(
      workload.visibility_range,
      table_ready,
    ))
    |> static_supervisor.add(owner.reporting(factory, factory_ready))
    |> static_supervisor.start,
  )
  let assert Ok(table_owner.TableOwner(table:, control:)) =
    process.receive(table_ready, 5000)
    as "the table owner did not report its table"
  let assert Ok(factory) = process.receive(factory_ready, 5000)
    as "the unit supervisor did not report itself"
  let shared =
    unit_process.Shared(
      workload:,
      spawn_list_key:,
      table:,
      table_owner: control,
      handled:,
    )
  measurement.spawn_list(spawn_list_key)
  |> dict.keys
  |> list.each(fn(unit_id) {
    let assert Ok(_) =
      factory_supervisor.start_child(
        factory,
        unit_process.Start(unit_id:, shared:),
      )
      as "a unit process did not start"
  })
  Ok(Parts(
    started: actor.Started(
      pid: supervisor.pid,
      data: door(
        supervisor: supervisor.pid,
        table:,
        table_owner: control,
        handled:,
      ),
    ),
    table:,
  ))
}

/// The `Owner` of a running prototype.
fn door(
  supervisor supervisor: Pid,
  table table: Table(unit_process.Message),
  table_owner table_owner: Subject(table_owner.Message),
  handled handled: Counter,
) -> Owner {
  let processes = fn() {
    process.call(table_owner, 5000, table_owner.TrackedProcesses)
  }
  Owner(
    join: fn(unit_id: Int, connection: Subject(Delivery)) {
      send_to_unit(table:, unit_id:, message: unit_process.Join(connection:))
    },
    move: fn(unit_id: Int, position: Position, sent_at: Int) {
      send_to_unit(
        table:,
        unit_id:,
        message: unit_process.Move(position:, sent_at:),
      )
    },
    attack_nearest_creature: fn(unit_id: Int, sent_at: Int) {
      send_to_unit(table:, unit_id:, message: unit_process.Attack(sent_at:))
    },
    owner_processes: processes,
    sender_processes: fn() { [] },
    messages_handled: fn() { measurement.counter_value(handled) },
    memory_words: fn() {
      list.fold(processes(), table.memory_words(table), fn(words, pid) {
        words + result.unwrap(measurement.process_memory_words(pid), 0)
      })
    },
    stop: fn() { owner.stop_supervisor(supervisor) },
  )
}

fn send_to_unit(
  table table: Table(unit_process.Message),
  unit_id unit_id: Int,
  message message: unit_process.Message,
) -> Nil {
  let assert Ok(row) = table.find(table, unit_id)
    as "the unit is not on the map"
  process.send(row.owner, message)
}

/// Waits until the table holds a row for `unit_id` owned by a process other
/// than `victim`, and that process answers a probe.
fn await_rebuilt(
  table table: Table(unit_process.Message),
  unit_id unit_id: Int,
  victim victim: Pid,
) -> Nil {
  let rebuilt = case table.find(table, unit_id) {
    Ok(row) ->
      case process.subject_owner(row.owner) {
        Ok(pid) if pid != victim -> Ok(row.owner)
        Ok(_) | Error(Nil) -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
  case rebuilt {
    Ok(subject) -> process.call(subject, 5000, unit_process.Probe)
    Error(Nil) -> await_rebuilt(table:, unit_id:, victim:)
  }
}
