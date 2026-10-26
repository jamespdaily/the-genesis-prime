//// The heap sampler of a load run of prototype C: a process that, every 100
//// milliseconds, reads the heap and the mailbox of every map process and every
//// sender of the run's owners, and keeps the largest it saw for each kind. At
//// each reading it also reads the runtime's binary and ETS memory, which no
//// process heap holds, and keeps their largest. It monitors every process it
//// reads, so it counts the map processes and senders the runtime killed while
//// it ran, which is what a heap limit does to a process that passes it.
////
//// A reading takes a process's `total_heap_size`: its heap, stack and waiting
//// messages together, the size `max_heap_size` limits. The sampler reads the
//// owners' process lists afresh at each reading, so a rebuilt process is read
//// from the next reading on; a process that is killed and rebuilt between two
//// readings is counted, because its monitor was set at an earlier one.
////
//// The sampler is linked to the process that starts it, not supervised: a run
//// whose sampler died has nothing to report, so the run stops with it.

import genesis_prime/topology/owner.{type Owner}
import gleam/erlang/process.{type Subject}

/// A running sampler, started by `start` and ended by `stop`.
pub opaque type Sampler {
  Sampler(requests: Subject(Message))
}

/// Every message the sampler can receive. Its selector covers all of them;
/// anything else is logged.
type Message {
  /// The timer for the next reading is due.
  Reading
  /// A monitored process is down.
  Down(down: process.Down)
  /// Ends the sampler and asks it to send what it found.
  Stop(reply_with: Subject(Sampled))
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

/// What the sampler found between its start and its stop. The binary and ETS
/// bytes are the runtime's whole, not those of the run's processes alone, as
/// the runtime keeps no count for a group of processes.
pub type Sampled {
  Sampled(
    /// The largest map process sizes, over every map of the run.
    map: Peak,
    /// The largest sender sizes, over every sender of the run.
    sender: Peak,
    /// The most bytes `erlang:memory(binary)` held at a reading.
    binary_bytes: Int,
    /// The most bytes `erlang:memory(ets)` held at a reading.
    ets_bytes: Int,
    killed: Killed,
  )
}

/// Starts a sampler of the processes of `doors`, one owner for each map of the
/// run. It reads at once, and then every 100 milliseconds. A process of an
/// owner that is not in `Owner.sender_processes` is a map process.
pub fn start(doors doors: List(Owner)) -> Sampler {
  todo as "body in the build commit"
}

/// Reads once more, ends the sampler and returns what it found.
pub fn stop(sampler sampler: Sampler) -> Sampled {
  todo as "body in the build commit"
}
