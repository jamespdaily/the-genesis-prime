//// The process that owns the one-process-per-unit prototype's table. Units
//// write their own rows; this process creates the table, monitors every unit
//// process and removes the rows of one that died, so the table never holds a
//// dead unit.

import genesis_prime/topology/per_unit/table.{type Table}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// Every message the table owner can receive. Its selector covers these and
/// the down messages of the processes it monitors.
pub type Message {
  /// A unit process has written its rows and is to be watched.
  Track(unit_id: Int, owner: Pid)
  /// Asks for the processes now watched, one per live unit.
  TrackedProcesses(reply_with: Subject(List(Pid)))
}

/// What the owner tells whoever starts it: the table, and where to send it
/// messages.
pub type TableOwner(mailbox) {
  TableOwner(table: Table(mailbox), control: Subject(Message))
}

/// The state of the table owner: the table, the cell width its cleanup needs,
/// and the unit each watched process owns.
type State(mailbox) {
  State(table: Table(mailbox), cell_size: Float, watched: Dict(Pid, Int))
}

/// The child specification for the table owner. Once the table exists the
/// owner sends a `TableOwner` on `ready`. A restart creates an empty table and
/// sends again, and the units of the old table are not rebuilt by it, so the
/// run that saw it is not measured.
pub fn supervised(
  cell_size cell_size: Float,
  ready ready: Subject(TableOwner(mailbox)),
) -> ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(cell_size, ready) })
}

/// What the table owner's process receives: a message from a unit or from the
/// harness, or the news that a watched process has died.
type Input {
  Control(Message)
  Down(process.Down)
}

fn start(
  cell_size: Float,
  ready: Subject(TableOwner(mailbox)),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(1000, fn(_default) {
    let table = table.new()
    let control = process.new_subject()
    let selector =
      process.new_selector()
      |> process.select_map(control, Control)
      |> process.select_monitors(Down)
    process.send(ready, TableOwner(table:, control:))
    actor.initialised(State(table:, cell_size:, watched: dict.new()))
    |> actor.selecting(selector)
    |> actor.returning(control)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(
  state: State(mailbox),
  input: Input,
) -> actor.Next(State(mailbox), Input) {
  case input {
    Control(Track(unit_id:, owner:)) -> {
      let _monitor = process.monitor(owner)
      actor.continue(
        State(..state, watched: dict.insert(state.watched, owner, unit_id)),
      )
    }
    Control(TrackedProcesses(reply_with:)) -> {
      process.send(reply_with, dict.keys(state.watched))
      actor.continue(state)
    }
    Down(process.ProcessDown(pid:, ..)) ->
      case dict.get(state.watched, pid) {
        Ok(unit_id) -> {
          table.delete_unit(state.table, unit_id, pid, state.cell_size)
          actor.continue(
            State(..state, watched: dict.delete(state.watched, pid)),
          )
        }
        Error(Nil) -> actor.continue(state)
      }
    Down(process.PortDown(..)) -> actor.continue(state)
  }
}
