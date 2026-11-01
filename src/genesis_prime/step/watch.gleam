//// The watches a shell keeps for its rule: each open `Watch` is a monitor held
//// under the rule's `WatchId`, or, for a target no process holds, an id held
//// to end. The service shell (genesis_prime/service/shell) and the connection
//// shell (genesis_prime/connection/shell) carry out `Watch` and `Unwatch` and
//// turn a monitor's DOWN into `WatchEnded` the same way, so the bookkeeping is
//// here and each shell keeps only how its DOWN reaches it and where its loop
//// takes `next_unheld_end`.
////
//// - **Open.** The target's pid is monitored under the id. A target no
////   process holds, `Error(Nil)` from the shell's lookup, is monitored by
////   nothing: its id is held to end, in the order the watches were opened.
////   The shell takes `next_unheld_end` as its next input once the step's
////   effects are carried out, before it reads its mailbox, so the end comes
////   from the shell itself and never from a second sender. A target that ends
////   between the lookup and the monitor fires the monitor at once. An id
////   already open, monitored or held to end, ends the process with an error
////   log: an id is unique among the open watches.
//// - **Close.** The monitor is dropped and its DOWN already waiting is
////   flushed from the mailbox; an id held to end is dropped. No `WatchEnded`
////   follows either way; an id with no open watch does nothing.
//// - **Ended.** A DOWN's monitor gives the id of its watch, which is then
////   forgotten, so a watch ends once; the DOWN of a monitor the shell holds
////   under no id (a closed watch's, or a kept ask's) gives none. An id held
////   to end is given once by `next_unheld_end` and forgotten.

import genesis_prime/step.{type WatchId, LogError}
import genesis_prime/step/runtime
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Monitor, type Pid}
import gleam/list
import gleam/result

/// The open watches of one shell.
pub opaque type Watches {
  Watches(
    monitors: Dict(WatchId, Monitor),
    /// The same watches by monitor, so a DOWN is one lookup.
    by_monitor: Dict(Monitor, WatchId),
    /// The watches of a target no process holds, in the order opened, the
    /// first to end first.
    unheld: List(WatchId),
  )
}

/// No watch open.
pub fn new() -> Watches {
  Watches(monitors: dict.new(), by_monitor: dict.new(), unheld: [])
}

/// Opens watch `watch` on the process the shell found, or, with none, holds
/// the watch to end; `shell` names the shell, for the log line of an id
/// already open.
pub fn open(
  watches watches: Watches,
  watch watch: WatchId,
  target target: Result(Pid, Nil),
  shell shell: String,
) -> Watches {
  case
    dict.has_key(watches.monitors, watch),
    list.contains(watches.unheld, watch)
  {
    False, False ->
      case target {
        Ok(pid) -> {
          let monitor = process.monitor(pid)
          Watches(
            ..watches,
            monitors: dict.insert(watches.monitors, watch, monitor),
            by_monitor: dict.insert(watches.by_monitor, monitor, watch),
          )
        }
        Error(Nil) ->
          Watches(..watches, unheld: list.append(watches.unheld, [watch]))
      }
    _, _ -> {
      runtime.log(
        LogError,
        "a rule opened a watch whose id is already open, which the "
          <> shell
          <> " does not carry out",
        step.no_one,
      )
      panic as "a rule opened a watch whose id is already open"
    }
  }
}

/// Closes watch `watch`: its monitor is dropped and its DOWN flushed, or, for
/// a watch held to end, the hold is dropped.
pub fn close(watches watches: Watches, watch watch: WatchId) -> Watches {
  case dict.get(watches.monitors, watch) {
    Ok(monitor) -> {
      process.demonitor_process(monitor)
      forget(watches:, watch:, monitor:)
    }
    Error(Nil) ->
      Watches(
        ..watches,
        unheld: list.filter(watches.unheld, fn(held) { held != watch }),
      )
  }
}

/// The watch of a target no process holds that was opened first and has not
/// ended, which is forgotten, or `Error(Nil)` when none is held. The shell
/// takes it as `WatchEnded` before it reads its mailbox.
pub fn next_unheld_end(
  watches watches: Watches,
) -> Result(#(WatchId, Watches), Nil) {
  case watches.unheld {
    [watch, ..later] -> Ok(#(watch, Watches(..watches, unheld: later)))
    [] -> Error(Nil)
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
    ..watches,
    monitors: dict.delete(watches.monitors, watch),
    by_monitor: dict.delete(watches.by_monitor, monitor),
  )
}
