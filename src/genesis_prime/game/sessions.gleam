//// The game sessions of the accounts: one live game connection for each
//// account. A second login of an account first ends the first connection, so
//// the account's character is off the map before the new client is sent its
//// list (the client is built for it: lua.CharacterSelection.OnRemoveCountdown,
//// opcode.0x36a, opcode.0x63d).
////
//// The registry process holds, for each account, the connection that holds its
//// slot, and monitors it, so a connection that ends frees its slot. Nothing
//// calls a peer while it waits: a new connection asks the registry who held the
//// slot, tells that connection to end by a message to it, and waits for it
//// to end in its own process, within a deadline. A restart empties the registry:
//// the sessions that were registered are not found by a second login until
//// they connect again, so a second login right after a restart can leave two
//// connections of one account, which the map refuses for one character.

import genesis_prime/connection/clock
import genesis_prime/telemetry/log
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Monitor, type Name, type Pid, type Subject}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// How long the registry has to stop, in milliseconds: it saves nothing.
const shutdown_milliseconds = 1000

/// How long the registry has to start, in milliseconds.
const start_deadline_milliseconds = 5000

/// What a connection is told by a message: its account logged in again, so it
/// ends.
pub type Notice {
  TakeOver
}

/// The connection that held an account's slot: the subject its notice goes to
/// and the process that owns it, which the new connection waits to end.
pub type Previous {
  Previous(notice: Subject(Notice), owner: Pid)
}

/// Why a new connection could not take its account's slot.
pub type NotFreed {
  /// The registry did not answer within the deadline.
  RegistryNotAnswering
  /// The connection that held the slot did not end within the deadline.
  PreviousNotEnding
}

/// Every message the registry receives. Its selector covers all of them;
/// anything else is logged.
pub opaque type Message {
  /// A connection takes the account's slot and is told who held it.
  Claim(
    account_id: Int,
    notice: Subject(Notice),
    owner: Pid,
    reply: Subject(Option(Previous)),
  )
  /// A connection that held a slot ended.
  HolderDown(process.Down)
  Unexpected(received: Dynamic)
}

type Holder {
  Holder(previous: Previous, monitor: Monitor)
}

type State {
  State(holders: Dict(Int, Holder))
}

/// The registry as a child of the game's subtree. A restart rebuilds it empty.
pub fn supervised(
  name name: Name(Message),
) -> ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name) })
  |> supervision.timeout(ms: shutdown_milliseconds)
}

fn start(name: Name(Message)) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_milliseconds, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(HolderDown)
      |> process.select_other(Unexpected)
    actor.initialised(State(holders: dict.new()))
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.named(name)
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Claim(account_id:, notice:, owner:, reply:) -> {
      let held = dict.get(state.holders, account_id)
      let previous = case held {
        Ok(Holder(previous:, monitor:)) -> {
          process.demonitor_process(monitor)
          case process.is_alive(previous.owner) {
            True -> Some(previous)
            False -> None
          }
        }
        Error(Nil) -> None
      }
      let holder =
        Holder(
          previous: Previous(notice:, owner:),
          monitor: process.monitor(owner),
        )
      process.send(reply, previous)
      actor.continue(
        State(holders: dict.insert(state.holders, account_id, holder)),
      )
    }
    HolderDown(process.ProcessDown(monitor:, ..)) ->
      actor.continue(
        State(
          holders: dict.filter(state.holders, fn(_account_id, holder) {
            holder.monitor != monitor
          }),
        ),
      )
    HolderDown(process.PortDown(..)) -> actor.continue(state)
    Unexpected(..) -> {
      log.error(
        log.Who(
          account: None,
          actor: None,
          place: Some(log.Process("sessions")),
          message: None,
          peer: None,
        ),
        "the sessions' registry received a message it does not handle",
      )
      actor.continue(state)
    }
  }
}

/// Takes the account's slot for the calling connection, whose notices arrive on
/// `notice`, and when another connection held it, tells that connection to
/// end and waits for it to end. All within one deadline of `within_ms`
/// milliseconds. Ok once the slot is the caller's and no other connection of
/// the account is left.
pub fn take_over(
  registry registry: Name(Message),
  account_id account_id: Int,
  notice notice: Subject(Notice),
  within_ms within_ms: Int,
) -> Result(Nil, NotFreed) {
  let deadline = clock.monotonic_milliseconds() + within_ms
  use previous <- result.try(claim(registry:, account_id:, notice:, within_ms:))
  case previous {
    None -> Ok(Nil)
    Some(previous) ->
      end_previous(
        previous:,
        within_ms: int.max(0, deadline - clock.monotonic_milliseconds()),
      )
  }
}

fn claim(
  registry registry: Name(Message),
  account_id account_id: Int,
  notice notice: Subject(Notice),
  within_ms within_ms: Int,
) -> Result(Option(Previous), NotFreed) {
  case process.named(registry) {
    Error(Nil) -> Error(RegistryNotAnswering)
    Ok(_) -> {
      let reply = process.new_subject()
      process.send(
        process.named_subject(registry),
        Claim(account_id:, notice:, owner: process.self(), reply:),
      )
      process.receive(reply, within_ms)
      |> result.replace_error(RegistryNotAnswering)
    }
  }
}

/// Tells the connection to end and waits for its process to end.
fn end_previous(
  previous previous: Previous,
  within_ms within_ms: Int,
) -> Result(Nil, NotFreed) {
  let monitor = process.monitor(previous.owner)
  process.send(previous.notice, TakeOver)
  let ended =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_down) { Nil })
    |> process.selector_receive(within: within_ms)
  process.demonitor_process(monitor)
  result.replace_error(ended, PreviousNotEnding)
}
