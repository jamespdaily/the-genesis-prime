//// The watches a shell keeps for its rule: each open `Watch` is a monitor held
//// under the rule's `WatchId`. The service shell (genesis_prime/service/shell)
//// and the connection shell (genesis_prime/connection/shell) carry out
//// `Watch` and `Unwatch` and turn a monitor's DOWN into `WatchEnded` the same
//// way, so the bookkeeping is here and each shell keeps only how its DOWN
//// reaches it.
////
//// - **Open.** The target's pid is monitored under the id. A target no
////   process holds, `Error(Nil)` from the shell's lookup, is watched through a
////   process that has already ended, so its DOWN arrives as the next message,
////   like the DOWN of a target that ends between the lookup and the monitor. An
////   id already open ends the process with an error log: an id is unique
////   among the open watches.
//// - **Close.** The monitor is dropped and its DOWN already waiting is
////   flushed from the mailbox, so no `WatchEnded` follows; an id with no open
////   watch does nothing.
//// - **Ended.** A DOWN's monitor gives the id of its watch, which is then
////   forgotten, so a watch ends once; the DOWN of a monitor the shell holds
////   under no id (a closed watch's, or a kept ask's) gives none.

import genesis_prime/step.{type WatchId, LogError}
import genesis_prime/step/runtime
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Monitor, type Pid}
import gleam/result

/// The open watches of one shell.
pub opaque type Watches {
  Watches(
    monitors: Dict(WatchId, Monitor),
    /// The same watches by monitor, so a DOWN is one lookup.
    by_monitor: Dict(Monitor, WatchId),
  )
}

/// No watch open.
pub fn new() -> Watches {
  Watches(monitors: dict.new(), by_monitor: dict.new())
}

/// Opens watch `watch` on the process the shell found, or on none; `shell`
/// names the shell, for the log line of an id already open.
pub fn open(
  watches watches: Watches,
  watch watch: WatchId,
  target target: Result(Pid, Nil),
  shell shell: String,
) -> Watches {
  case dict.has_key(watches.monitors, watch) {
    True -> {
      runtime.log(
        LogError,
        "a rule opened a watch whose id is already open, which the "
          <> shell
          <> " does not carry out",
        step.no_one,
      )
      panic as "a rule opened a watch whose id is already open"
    }
    False -> {
      let monitor = process.monitor(result.lazy_unwrap(target, ended_process))
      Watches(
        monitors: dict.insert(watches.monitors, watch, monitor),
        by_monitor: dict.insert(watches.by_monitor, monitor, watch),
      )
    }
  }
}

/// A process that has ended or is about to, for the watch of an address no
/// process holds: its monitor's DOWN is on its way either way.
fn ended_process() -> Pid {
  process.spawn_unlinked(fn() { Nil })
}

/// Closes watch `watch`: its monitor is dropped and its DOWN flushed.
pub fn close(watches watches: Watches, watch watch: WatchId) -> Watches {
  case dict.get(watches.monitors, watch) {
    Ok(monitor) -> {
      process.demonitor_process(monitor)
      forget(watches:, watch:, monitor:)
    }
    Error(Nil) -> watches
  }
}

/// The watch a DOWN's monitor belongs to, which is forgotten, or `Error(Nil)`
/// for a monitor held under no watch.
pub fn ended(
  watches watches: Watches,
  monitor monitor: Monitor,
) -> Result(#(WatchId, Watches), Nil) {
  use watch <- result.map(dict.get(watches.by_monitor, monitor))
  #(watch, forget(watches:, watch:, monitor:))
}

fn forget(
  watches watches: Watches,
  watch watch: WatchId,
  monitor monitor: Monitor,
) -> Watches {
  Watches(
    monitors: dict.delete(watches.monitors, watch),
    by_monitor: dict.delete(watches.by_monitor, monitor),
  )
}
