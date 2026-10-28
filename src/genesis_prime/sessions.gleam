//// The sessions: who is logged in to the game server, one slot per account. A
//// game connection claims its account's slot once the hand-off has named the
//// account; when another connection already holds the slot, that connection is
//// told it was taken over, and the client of the old connection is
//// disconnected (opcode.0x036A reason 19, which the old connection's rule
//// writes). The newest login stays connected.
////
//// This is the rule of the sessions service (genesis_prime/service/shell),
//// started under the server's supervisor and found by its name. Its slots live
//// only in the process: a restart loses them, and the game connections
//// rebuild them (below).
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
////   ◀─ Claimed          ◀─ Reply(caller, Claimed)
//// ```
////
//// Takeover, a second connection claims the account c1 holds:
////
//// ```
//// connection c2              Sessions                              c1
////   Claim(account, c2) ─▶ Asked ─▶ slot names c1
////                                  slot = (c2, watch w2)
////                                  Watch(w2, Connection(c2))
////                                  Send(Connection(c1), TakenOver) ─▶ Woken(TakenOver)
////   ◀─ Claimed          ◀─ Reply(caller, Claimed)               c1 writes 0x036A
////                                                                  reason 19 and stops
//// ```
////
//// - **A claim by the holder** answers `Claimed` and changes nothing: the
////   slot, its watch and the connections stay as they are.
//// - **The holder ends.** The watch on it comes back as `WatchEnded(w)`; the
////   slot that names `w` is freed.
//// - **The old holder ends after a takeover.** Its watch `w1` comes back as
////   `WatchEnded(w1)`; the slot names `w2`, so nothing is freed, and `w1` is
////   forgotten.
//// - **Sessions restarts.** The new process has no slots and no watches. Each
////   game connection watches Sessions, so each takes `WatchEnded` and claims
////   again (genesis_prime/game/connection); the claims run in the order they
////   arrive, so the slots match the connections alive. A client that logs in
////   to the account during the gap, before the old connection claims again,
////   is not caught: when the old connection's claim then comes, it takes the
////   slot from the newer one.
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
  type CallerId, type ConnectionId, type Input, type Rule, type Step,
  type WatchId, Answered, AnsweredLate, Asked, Effects, Rule, Socket, Started,
  Stop, Stopping, TimerFired, WatchEnded, Woken,
}
import genesis_prime/store.{type AccountId}
import gleam/dict.{type Dict}

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/sessions"

/// What another process asks Sessions.
pub type Message {
  /// Make `connection` the holder of `account`'s slot. The answer is
  /// `Claimed`, after the previous holder, if there is another, is sent
  /// `TakenOver`.
  Claim(account: AccountId, connection: ConnectionId)
}

/// What Sessions answers and what it sends.
pub type Outgoing {
  /// The answer to a `Claim`: the connection holds the slot.
  Claimed
  /// Sent to the connection that held a slot another connection has claimed:
  /// its client is told the account was disconnected, and it ends.
  TakenOver
}

/// A slot's holder and the watch that tells Sessions when it ends.
type Slot {
  Slot(connection: ConnectionId, watch: WatchId)
}

/// The slots held, by account; each watch Sessions has open, with the
/// account and connection it was opened for, so the end of a connection a
/// takeover replaced is told from the end of the holder; and the number of the
/// next watch.
pub opaque type State {
  State(
    slots: Dict(AccountId, Slot),
    watches: Dict(WatchId, #(AccountId, ConnectionId)),
    next_watch: Int,
  )
}

/// The rule as its service shell runs it.
pub fn rule() -> Rule(Nil, State, Message, Nil, Outgoing, Nil) {
  Rule(name: rule_name, settings: Nil, new:, step:)
}

/// Sessions' first state: no slots and no watches.
pub fn new(_settings: Nil) -> State {
  todo as "the build follows the shape commit"
}

/// One input in, the new state and what the shell must do out. `Asked` with a
/// `Claim` is answered with `Reply`, after the effects the sequences above
/// give; `WatchEnded` frees or forgets as above; `Stopping` stops; `Started`
/// does nothing. An input a service's shell never gives, or a `WatchEnded` for
/// a watch this rule never opened, is a bug, and crashes the process.
pub fn step(
  state state: State,
  input input: Input(Message, Nil),
) -> #(State, Step(Outgoing, Nil)) {
  case input.event {
    Started -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    Asked(caller:, message:) -> claimed(state:, caller:, message:)
    WatchEnded(watch:) -> ended(state:, watch:)
    Socket(..) | Woken(..) | TimerFired(..) | Answered(..) | AnsweredLate(..) ->
      panic as "Sessions takes Started, Asked, WatchEnded and Stopping only; its shell gives no Socket, Woken, TimerFired, Answered or AnsweredLate"
  }
}

fn claimed(
  state state: State,
  caller caller: CallerId,
  message message: Message,
) -> #(State, Step(Outgoing, Nil)) {
  todo as "the build follows the shape commit"
}

fn ended(
  state state: State,
  watch watch: WatchId,
) -> #(State, Step(Outgoing, Nil)) {
  todo as "the build follows the shape commit"
}
