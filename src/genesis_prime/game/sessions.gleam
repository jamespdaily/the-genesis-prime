//// The game sessions of the accounts: every live game connection of an
//// account, and the rule that a new one is let in only when no older one is
//// alive. A second login of an account ends the first connection, so the
//// account's character is off the map before the new client is sent its list
//// (the client is built for it: lua.CharacterSelection.OnRemoveCountdown,
//// opcode.0x36a, opcode.0x63d).
////
//// The registry process keeps, for each account, its holders in the order they
//// claimed, and monitors each one until its own end arrives: a holder is never
//// dropped because another claim came in, so a connection that is told to end
//// and does not is still known, and every claim after it still waits for it. A
//// claim tells every holder of the account that is not yet told to end, by a
//// message to it, and the registry answers the claimant when it is the first
//// holder of its account, that is when every holder before it is down. A
//// holder that is told and has not gone down within the eviction deadline is
//// killed, which the monitor then reports, so a claimant that waits longer
//// than the eviction deadline always gets the slot, and an old connection never
//// outlives its account's next login. A claimant that gave up or died is a
//// holder like any other, and leaves the registry on its own end. A restart
//// empties the registry: its holders are not found by a second login until
//// they connect again, so a connection watches the registry and ends when it
//// does (`game_connection`).
////
//// The wait for the answer is in the claimant's own process, within its own
//// deadline; nothing calls a peer while it waits.

import genesis_prime/connection/named_send
import genesis_prime/telemetry/log
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Monitor, type Name, type Pid, type Subject}
import gleam/list
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

/// Why a new connection could not take its account's slot.
pub type NotFreed {
  /// No registry runs.
  RegistryNotAnswering
  /// The claim was not answered within the deadline: an older connection of the
  /// account was still alive, or the registry did not run in time. The
  /// registry kills a connection that does not end within its eviction
  /// deadline, so a claimant that waits longer than that is answered.
  PreviousNotEnding
}

/// Every message the registry receives. Its selector covers all of them;
/// anything else is logged.
pub opaque type Message {
  /// A connection takes its place among the account's holders and is answered
  /// on `reply` when every holder before it is down.
  Claim(
    account_id: Int,
    notice: Subject(Notice),
    owner: Pid,
    reply: Subject(Nil),
  )
  /// A holder went down.
  HolderDown(process.Down)
  /// The eviction deadline of a holder that was told to end has passed.
  Evict(account_id: Int, owner: Pid)
  Unexpected(received: Dynamic)
}

/// A connection that holds, or waits for, a slot of an account: where to tell
/// it to end, the process that owns it, the monitor held on it, the subject to
/// answer it on while it waits, and the timer of its eviction once it has been
/// told.
type Holder {
  Holder(
    notice: Subject(Notice),
    owner: Pid,
    monitor: Monitor,
    waiting: Option(Subject(Nil)),
    eviction: Option(process.Timer),
  )
}

/// The registry's state: the settings it started with, its own subject for the
/// eviction timers, the holders of each account, the oldest first, and the
/// account each holder's process is a holder of.
type State {
  State(
    self: Subject(Message),
    eviction_ms: Int,
    accounts: Dict(Int, List(Holder)),
    accounts_of: Dict(Pid, Int),
  )
}

/// The registry as a child of the game's subtree. `eviction_ms` is how long a
/// holder that was told to end has to go down before it is killed. A restart
/// rebuilds the registry empty.
pub fn supervised(
  name name: Name(Message),
  eviction_ms eviction_ms: Int,
) -> ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name, eviction_ms) })
  |> supervision.timeout(ms: shutdown_milliseconds)
}

fn start(
  name: Name(Message),
  eviction_ms: Int,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_milliseconds, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(HolderDown)
      |> process.select_other(Unexpected)
    actor.initialised(State(
      self:,
      eviction_ms:,
      accounts: dict.new(),
      accounts_of: dict.new(),
    ))
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
    Claim(account_id:, notice:, owner:, reply:) ->
      actor.continue(claimed(state:, account_id:, notice:, owner:, reply:))
    HolderDown(process.ProcessDown(pid:, ..)) ->
      actor.continue(went_down(state:, owner: pid))
    HolderDown(process.PortDown(..)) -> actor.continue(state)
    Evict(account_id:, owner:) -> {
      evict(state:, account_id:, owner:)
      actor.continue(state)
    }
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

/// A connection claims its account's slot: every holder of the account that is
/// not told yet is told to end, with its eviction timer started, and the
/// claimant joins the holders after them.
fn claimed(
  state state: State,
  account_id account_id: Int,
  notice notice: Subject(Notice),
  owner owner: Pid,
  reply reply: Subject(Nil),
) -> State {
  let before =
    dict.get(state.accounts, account_id)
    |> result.unwrap([])
    |> list.map(fn(holder) { told(state:, account_id:, holder:) })
  let claimant =
    Holder(
      notice:,
      owner:,
      monitor: process.monitor(owner),
      waiting: Some(reply),
      eviction: None,
    )
  State(
    ..state,
    accounts: dict.insert(
      state.accounts,
      account_id,
      answered(list.append(before, [claimant])),
    ),
    accounts_of: dict.insert(state.accounts_of, owner, account_id),
  )
}

/// The holder, told to end and given its eviction deadline when it has not
/// been told already.
fn told(
  state state: State,
  account_id account_id: Int,
  holder holder: Holder,
) -> Holder {
  case holder.eviction {
    Some(_) -> holder
    None -> {
      process.send(holder.notice, TakeOver)
      Holder(
        ..holder,
        eviction: Some(process.send_after(
          state.self,
          state.eviction_ms,
          Evict(account_id:, owner: holder.owner),
        )),
      )
    }
  }
}

/// The holders with the first one answered when it is waiting: it is the one
/// holder no other is before, so no holder before it is alive.
fn answered(holders: List(Holder)) -> List(Holder) {
  case holders {
    [Holder(waiting: Some(reply), ..) as first, ..rest] -> {
      process.send(reply, Nil)
      [Holder(..first, waiting: None), ..rest]
    }
    [_, ..] | [] -> holders
  }
}

/// A holder went down: it leaves its account's holders, its eviction timer is
/// cancelled, and the holder that is now first is answered when it waits.
fn went_down(state state: State, owner owner: Pid) -> State {
  case dict.get(state.accounts_of, owner) {
    Error(Nil) -> state
    Ok(account_id) -> {
      let holders = dict.get(state.accounts, account_id) |> result.unwrap([])
      let #(gone, left) =
        list.partition(holders, fn(holder) { holder.owner == owner })
      list.each(gone, fn(holder) {
        case holder.eviction {
          Some(timer) -> {
            process.cancel_timer(timer)
            Nil
          }
          None -> Nil
        }
      })
      let accounts = case answered(left) {
        [] -> dict.delete(state.accounts, account_id)
        left -> dict.insert(state.accounts, account_id, left)
      }
      State(
        ..state,
        accounts:,
        accounts_of: dict.delete(state.accounts_of, owner),
      )
    }
  }
}

/// The eviction deadline of a holder passed: a holder that is still tracked has
/// not gone down since it was told, so it is killed, and its end is what removes
/// it.
fn evict(
  state state: State,
  account_id account_id: Int,
  owner owner: Pid,
) -> Nil {
  let holds =
    dict.get(state.accounts, account_id)
    |> result.unwrap([])
    |> list.any(fn(holder) { holder.owner == owner })
  case holds {
    True -> process.kill(owner)
    False -> Nil
  }
}

/// Takes a place among the holders of the account for the calling connection,
/// whose notices arrive on `notice`, and waits up to `within_ms` milliseconds
/// for the registry to say that every older holder of the account is down. Ok
/// once none is alive. A connection claims once: the process is a holder until
/// it ends.
pub fn take_over(
  registry registry: Name(Message),
  account_id account_id: Int,
  notice notice: Subject(Notice),
  within_ms within_ms: Int,
) -> Result(Nil, NotFreed) {
  use _ <- result.try(
    process.named(registry) |> result.replace_error(RegistryNotAnswering),
  )
  let reply = process.new_subject()
  named_send.send(
    process.named_subject(registry),
    Claim(account_id:, notice:, owner: process.self(), reply:),
  )
  process.receive(reply, within_ms)
  |> result.replace_error(PreviousNotEnding)
}
