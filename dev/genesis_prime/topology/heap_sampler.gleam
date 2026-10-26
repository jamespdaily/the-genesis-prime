//// The heap sampler of a load run of prototype C: a process that, every 100
//// milliseconds, reads the heap and the mailbox of every map process and every
//// sender of the run's owners, and keeps the largest it saw for each kind. At
//// each reading it also reads the runtime's binary and ETS memory, which no
//// process heap holds, and keeps their largest. It monitors every process it
//// reads, so it counts the map processes and senders the runtime killed while
//// it ran, which is what a heap limit does to a process that passes it.
////
//// The sampler starts with the prototype, so its kills and replacements cover
//// the whole run, warm-up included. Its peaks cover only the stretch after
//// `begin_measuring`, so the warm-up's burst of load does not count toward the
//// peaks a limit is chosen from.
////
//// A reading takes a process's `total_heap_size`: its heap, stack and waiting
//// messages together, the size `max_heap_size` limits. The sampler reads the
//// owners' process lists afresh at each reading, so a rebuilt process is read
//// from the next reading on; a process that is killed and rebuilt between two
//// readings is counted, because its monitor was set at an earlier one.
////
//// The sampler is linked to the process that starts it, not supervised: a run
//// whose sampler died has nothing to report, so the run stops with it.

import genesis_prime/topology/measurement
import genesis_prime/topology/owner.{type Owner}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor

/// The time between two readings, in milliseconds.
const reading_interval_milliseconds = 100

/// How long the sampler has to start, and to answer a stop, in milliseconds.
const deadline_milliseconds = 5000

/// A running sampler, started by `start` and ended by `stop`.
pub opaque type Sampler {
  Sampler(requests: Subject(Message))
}

/// Every message the sampler can receive. Its selector covers all of them;
/// anything else is logged.
type Message {
  /// The timer for the next reading is due.
  Reading
  /// Forgets the peaks so far, reads once, and replies.
  BeginMeasuring(reply_with: Subject(Nil))
  /// A monitored process is down.
  Down(down: process.Down)
  /// Ends the sampler and asks it to send what it found.
  Stop(reply_with: Subject(Sampled))
}

/// Which kind of process a reading is of.
type Kind {
  MapKind
  SenderKind
}

/// The state of the sampler: the owners it reads, the processes the owners held
/// when it started, the processes it monitors and their kinds, and what it has
/// found.
type State {
  State(
    doors: List(Owner),
    initial: List(#(Pid, Kind)),
    monitored: Dict(Pid, Kind),
    found: Sampled,
    self: Subject(Message),
  )
}

/// The largest sizes one kind of process reached: the most words one process's
/// heap held at a reading, and the most messages one process's mailbox held at
/// a reading. The two peaks may be from different processes and readings.
pub type Peak {
  Peak(heap_words: Int, queue: Int)
}

/// How many processes of each kind the runtime killed while the sampler ran,
/// counted from the monitors' reason `killed`. A process that exits for another
/// reason is not counted.
pub type Killed {
  Killed(maps: Int, senders: Int)
}

/// How many of the processes the owners held when the sampler started are not
/// among the processes they hold when it stops, whatever ended them. It counts
/// an end the monitor does not count as a kill, and an end the sampler missed.
pub type Replaced {
  Replaced(maps: Int, senders: Int)
}

/// What the sampler found between its start and its stop. The binary and ETS
/// bytes are the runtime's whole, not those of the run's processes alone, as
/// the runtime keeps no count for a group of processes.
pub type Sampled {
  Sampled(
    /// The largest map process sizes after `begin_measuring`, over every map
    /// of the run.
    map: Peak,
    /// The largest sender sizes after `begin_measuring`, over every sender of
    /// the run.
    sender: Peak,
    /// The most bytes `erlang:memory(binary)` held at a reading after
    /// `begin_measuring`.
    binary_bytes: Int,
    /// The most bytes `erlang:memory(ets)` held at a reading after
    /// `begin_measuring`.
    ets_bytes: Int,
    /// The kills between the sampler's start and its stop.
    killed: Killed,
    /// The processes of the sampler's start that are gone at its stop.
    replaced: Replaced,
  )
}

/// Starts a sampler of the processes of `doors`, one owner for each map of the
/// run. It reads at once, and then every 100 milliseconds. A process of an
/// owner that is not in `Owner.sender_processes` is a map process. The
/// processes the owners hold now are the ones `stop` counts as replaced if they
/// are gone.
pub fn start(doors doors: List(Owner)) -> Sampler {
  let assert Ok(started) =
    actor.new_with_initialiser(deadline_milliseconds, fn(self) {
      let selector =
        process.new_selector()
        |> process.select(self)
        |> process.select_monitors(Down)
      let state =
        read(State(
          doors:,
          initial: processes_of(doors),
          monitored: dict.new(),
          found: nothing(),
          self:,
        ))
      schedule_reading(state)
      actor.initialised(state)
      |> actor.selecting(selector)
      |> actor.returning(Sampler(requests: self))
      |> Ok
    })
    |> actor.on_message(handle)
    |> actor.start
    as "the heap sampler did not start"
  started.data
}

/// Forgets the peaks found so far and reads once, so the peaks cover only the
/// time from now on. The kills found so far are kept.
pub fn begin_measuring(sampler sampler: Sampler) -> Nil {
  process.call(sampler.requests, deadline_milliseconds, BeginMeasuring)
}

/// Reads once more, ends the sampler and returns what it found.
pub fn stop(sampler sampler: Sampler) -> Sampled {
  process.call(sampler.requests, deadline_milliseconds, Stop)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Reading -> {
      let state = read(state)
      schedule_reading(state)
      actor.continue(state)
    }
    BeginMeasuring(reply_with:) -> {
      let state =
        read(
          State(
            ..state,
            found: Sampled(..nothing(), killed: state.found.killed),
          ),
        )
      process.send(reply_with, Nil)
      actor.continue(state)
    }
    Down(down:) -> actor.continue(note_down(state, down))
    Stop(reply_with:) -> {
      let state = read(state)
      process.send(
        reply_with,
        Sampled(..state.found, replaced: replaced(state)),
      )
      actor.stop()
    }
  }
}

fn schedule_reading(state: State) -> Nil {
  let _timer =
    process.send_after(state.self, reading_interval_milliseconds, Reading)
  Nil
}

/// What a sampler that has read nothing has found.
fn nothing() -> Sampled {
  Sampled(
    map: Peak(heap_words: 0, queue: 0),
    sender: Peak(heap_words: 0, queue: 0),
    binary_bytes: 0,
    ets_bytes: 0,
    killed: Killed(maps: 0, senders: 0),
    replaced: Replaced(maps: 0, senders: 0),
  )
}

/// How many of the processes the sampler started with are not held by the
/// owners now, for each kind.
fn replaced(state: State) -> Replaced {
  let now = list.map(processes_of(state.doors), fn(entry) { entry.0 })
  let gone =
    list.filter(state.initial, fn(entry) { !list.contains(now, entry.0) })
  Replaced(
    maps: list.count(gone, fn(entry) { entry.1 == MapKind }),
    senders: list.count(gone, fn(entry) { entry.1 == SenderKind }),
  )
}

/// Every process the owners hold now, with its kind.
fn processes_of(doors: List(Owner)) -> List(#(Pid, Kind)) {
  list.flat_map(doors, fn(door) {
    let senders = door.sender_processes()
    let maps =
      list.filter(door.owner_processes(), fn(pid) {
        !list.contains(senders, pid)
      })
    list.append(
      list.map(maps, fn(pid) { #(pid, MapKind) }),
      list.map(senders, fn(pid) { #(pid, SenderKind) }),
    )
  })
}

/// One reading of every process the owners hold now, and of the runtime's
/// binary and ETS memory. A process not read before is monitored first, so a
/// process that ends before the next reading is still counted.
fn read(state: State) -> State {
  let processes = processes_of(state.doors)
  let state =
    list.fold(processes, state, fn(state, entry) {
      let #(pid, kind) = entry
      case dict.has_key(state.monitored, pid) {
        True -> state
        False -> {
          let _monitor = process.monitor(pid)
          State(..state, monitored: dict.insert(state.monitored, pid, kind))
        }
      }
    })
  let found =
    list.fold(processes, state.found, fn(found, entry) {
      let #(pid, kind) = entry
      case measurement.process_size(pid) {
        Error(Nil) -> found
        Ok(size) ->
          case kind {
            MapKind -> Sampled(..found, map: larger(found.map, size))
            SenderKind -> Sampled(..found, sender: larger(found.sender, size))
          }
      }
    })
  State(
    ..state,
    found: Sampled(
      ..found,
      binary_bytes: int.max(found.binary_bytes, measurement.binary_bytes()),
      ets_bytes: int.max(found.ets_bytes, measurement.ets_bytes()),
    ),
  )
}

fn larger(peak: Peak, size: measurement.ProcessSize) -> Peak {
  Peak(
    heap_words: int.max(peak.heap_words, size.heap_words),
    queue: int.max(peak.queue, size.queue),
  )
}

/// Counts a monitored process that the runtime killed, and forgets it.
fn note_down(state: State, down: process.Down) -> State {
  case down {
    process.PortDown(..) -> state
    process.ProcessDown(pid:, reason:, ..) -> {
      let kind = dict.get(state.monitored, pid)
      let killed = state.found.killed
      let killed = case reason, kind {
        process.Killed, Ok(MapKind) -> Killed(..killed, maps: killed.maps + 1)
        process.Killed, Ok(SenderKind) ->
          Killed(..killed, senders: killed.senders + 1)
        process.Killed, Error(Nil)
        | process.Normal, _
        | process.Abnormal(_), _
        -> killed
      }
      State(
        ..state,
        monitored: dict.delete(state.monitored, pid),
        found: Sampled(..state.found, killed:),
      )
    }
  }
}
