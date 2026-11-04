//// The sessions: who is logged in to the game server, one slot per account. A
//// game connection claims its account's slot once the hand-off has named the
//// account; when an older connection already holds the slot, that connection
//// is told it was taken over, and the client of the old connection is
//// disconnected (opcode.0x036A reason 19, which the old connection's rule
//// writes). The newest login stays connected.
////
//// The newest login is the one with the highest `ConnectionId`. A connection's
//// id is `erlang:unique_integer([positive, monotonic])`, taken as the
//// connection starts (src/genesis_prime_step_runtime_ffi.erl `unique_id`), which is unique
//// and strictly increasing on the node for as long as it runs, so a login made
//// later has a higher id, whichever order claims reach Sessions in. A node
//// restart drops every connection, so the counter starting again never
//// matters.
////
//// This is the rule of the sessions service (genesis_prime/service/shell),
//// started under the server's supervisor and found by its name. Its slots live
//// only in the process: a restart loses them, and the game connections claim
//// again, in any order, and the ids settle which login keeps each slot.
////
//// Each sequence, from Sessions' side. `Watch`, `Send` and `Reply` are effects
//// its service shell carries out; a connection is named by its `ConnectionId`,
//// never by a process (genesis_prime/step, genesis_prime/connection/registry).
////
//// First claim:
////
//// ```
//// connection c1              Sessions                              shell
////   Claim(account, c1) ─▶ Asked ─▶ no slot for the account
////                                  slot = (c1, watch w1)
////                                  Watch(w1, Connection(c1))   ─▶ monitors c1
////   ◀─ Claimed          ◀─ OwnEffect(Reply(caller, Claimed))
//// ```
////
//// Takeover, a newer connection claims the account c1 holds (c2 > c1):
////
//// ```
//// connection c2              Sessions                              c1
////   Claim(account, c2) ─▶ Asked ─▶ slot names c1
////                                  slot = (c2, watch w2)
////                                  Watch(w2, Connection(c2))
////                                  OwnEffect(Send(Connection(c1), TakenOver)) ─▶ Woken(TakenOver)
////   ◀─ Claimed          ◀─ OwnEffect(Reply(caller, Claimed))               c1 writes 0x036A
////                                                                  reason 19 and stops
//// ```
////
//// An older connection claims the account c2 holds (c1 < c2), as after a
//// restart in which c2 claimed first:
////
//// ```
//// connection c1 (older)      Sessions                              c2
////   Claim(account, c1) ─▶ Asked ─▶ slot names c2
////                                  nothing changes
////   ◀─ TakenOver        ◀─ OwnEffect(Reply(caller, TakenOver))
//// c1 writes 0x036A reason 19 and stops
//// ```
////
//// - **A claim by the holder** answers `Claimed` and changes nothing: the
////   slot, its watch and the connections stay as they are.
//// - **A claim with a higher id than the holder's** is the takeover above.
//// - **A claim with a lower id than the holder's** is answered `TakenOver`
////   and changes nothing: no slot, no watch, and the holder is told nothing.
//// - **The holder ends.** The watch on it comes back as `WatchEnded(w)`; the
////   slot that names `w` is freed.
//// - **The old holder ends after a takeover.** Its watch `w1` comes back as
////   `WatchEnded(w1)`; the slot names `w2`, so nothing is freed, and `w1` is
////   forgotten.
//// - **Sessions restarts.** The new process has no slots and no watches. Each
////   game connection watches Sessions, so each takes `WatchEnded` and, after a
////   short wait, claims its account again (genesis_prime/game/connection).
////   Whatever order the claims arrive in, and however many restarts the
////   connections lived through, the highest id of an account's connections
////   holds its slot at the end and each lower one ends with reason 19.
//// - **A claim with no answer.** The claimer gives up at its deadline and
////   ends, which frees its slot when Sessions did act on the claim; a holder
////   told `TakenOver` for a claim whose claimer gave up is disconnected all
////   the same. Sessions never knows its asker's deadline.
//// - **A process dying.** A watched connection's death is the `WatchEnded`
////   above, also when it was not running as the watch began. A caller that
////   ended before its answer is dropped by the shell.
//// - **The server stopping.** `Stopping` stops the rule at once; its state
////   goes with the process.
////
//// A watch id is chosen here, from a counter in the state that does not go
//// back, so a watch is never taken for an older one.

import genesis_prime/step.{
  type CallerId, type ConnectionId, type ServiceInput, type ServiceRule,
  type ServiceStep, type WatchId, Asked, Connection, ConnectionId,
  CreatureNotStarted, Effects, OwnEffect, OwnEvent, Reply, Rule, Send,
  ServiceTimerFired, Started, Stop, Stopping, Told, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{type AccountId}
import gleam/dict.{type Dict}
import gleam/list

/// The rule's name: its module path.
const rule_name = "genesis_prime/account_session"

/// What another process asks Sessions.
pub type Message {
  /// Make `connection` the holder of `account`'s slot: a new login's first
  /// claim, or a connection's claim again after Sessions restarted. The slot
  /// goes to the higher id: a claim on an empty slot, or with a higher id than
  /// the holder's, takes it and the answer is `Claimed`, after the previous
  /// holder, if there is another, is sent `TakenOver`; a claim with a lower id
  /// than the holder's is answered `TakenOver` and nothing else changes.
  Claim(account: AccountId, connection: ConnectionId)
}

/// What Sessions answers and what it sends.
pub type Outgoing {
  /// The answer to a `Claim`: the connection holds the slot.
  Claimed
  /// Sent to the connection that held a slot a newer connection has claimed,
  /// and the answer to a `Claim` of a slot a newer connection holds: the
  /// connection's client is told the account was disconnected, and it ends.
  TakenOver
}

/// A slot's holder and the watch that tells Sessions when it ends.
type Slot {
  Slot(connection: ConnectionId, watch: WatchId)
}

/// The slots held, by account; each watch Sessions has open, with the account
/// it was opened for, so the end of a connection a takeover replaced is told
/// from the end of the holder; and the number of the next watch.
pub opaque type State {
  State(
    slots: Dict(AccountId, Slot),
    watches: Dict(WatchId, AccountId),
    next_watch: Int,
  )
}

/// The rule as its service shell runs it.
pub fn rule() -> ServiceRule(Nil, State, Message, Outgoing) {
  Rule(name: rule_name, settings: Nil, new:, step:)
}

/// Sessions' first state: no slots and no watches.
pub fn new(_settings: Nil) -> State {
  State(slots: dict.new(), watches: dict.new(), next_watch: 1)
}

/// One input in, the new state and what the shell must do out. `Asked` with a
/// `Claim` is answered with `Reply`, after the effects the sequences above
/// give; `WatchEnded` frees or forgets as above; `Stopping` stops; `Started`
/// does nothing. An input a service's shell never gives, or a `WatchEnded` for
/// a watch this rule never opened, is a bug, and crashes the process.
pub fn step(
  state state: State,
  input input: ServiceInput(Message),
) -> #(State, ServiceStep(Outgoing)) {
  case input.event {
    OwnEvent(Started) -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Asked(caller:, message: Claim(account:, connection:))) ->
      claimed(state:, caller:, account:, connection:)
    OwnEvent(Told(..)) ->
      panic as "Sessions takes Started, Asked and Stopping only; nothing tells it"
    OwnEvent(ServiceTimerFired(..)) | OwnEvent(CreatureNotStarted(..)) ->
      panic as "Sessions starts no timer and no creature"
    WatchEnded(watch:) -> ended(state:, watch:)
  }
}

/// A claim takes the slot when it is empty or the claimer's id is higher than
/// the holder's; the holder, if another, is told `TakenOver`. A claim by the
/// holder changes nothing, and a claim with a lower id than the holder's is
/// answered `TakenOver` and changes nothing.
fn claimed(
  state state: State,
  caller caller: CallerId,
  account account: AccountId,
  connection connection: ConnectionId,
) -> #(State, ServiceStep(Outgoing)) {
  let held = dict.get(state.slots, account)
  let ConnectionId(claimer) = connection
  case held {
    Ok(Slot(connection: holder, ..)) if holder == connection -> #(
      state,
      Effects([OwnEffect(Reply(caller, Claimed))]),
    )
    Ok(Slot(connection: ConnectionId(holder), ..)) if holder > claimer -> #(
      state,
      Effects([OwnEffect(Reply(caller, TakenOver))]),
    )
    Ok(Slot(..)) | Error(Nil) -> {
      let told = case held {
        Ok(Slot(connection: previous, ..)) -> [
          OwnEffect(Send(to: Connection(previous), message: TakenOver)),
        ]
        Error(Nil) -> []
      }
      let watch = WatchId(state.next_watch)
      #(
        State(
          slots: dict.insert(state.slots, account, Slot(connection:, watch:)),
          watches: dict.insert(state.watches, watch, account),
          next_watch: state.next_watch + 1,
        ),
        Effects(
          list.flatten([
            [Watch(watch:, target: Connection(connection))],
            told,
            [OwnEffect(Reply(caller, Claimed))],
          ]),
        ),
      )
    }
  }
}

fn ended(
  state state: State,
  watch watch: WatchId,
) -> #(State, ServiceStep(Outgoing)) {
  let assert Ok(account) = dict.get(state.watches, watch)
    as "a watch ends only if Sessions opened it and has not seen it end"
  let watches = dict.delete(state.watches, watch)
  let slots = case dict.get(state.slots, account) {
    Ok(Slot(watch: held, ..)) if held == watch ->
      dict.delete(state.slots, account)
    Ok(Slot(..)) | Error(Nil) -> state.slots
  }
  #(State(..state, slots:, watches:), Effects([]))
}
