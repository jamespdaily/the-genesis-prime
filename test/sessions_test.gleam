//// The sessions rule, pure. Expected values come from the rule's own contract
//// in the doc comment of `genesis_prime/sessions`, as approved on the one
//// login per account card: one slot per account, the newest login (the
//// highest `ConnectionId`) keeps it whichever order claims arrive in, the
//// connection it replaced is sent `TakenOver`, a claim older than the holder
//// is answered `TakenOver` and changes nothing, and Sessions watches each
//// holder, so a holder's end frees the slot and the end of a replaced
//// connection frees nothing. A connection is named by its `ConnectionId` and
//// a watch by its `WatchId`; the effects name both.

import connection_rule_support as support
import genesis_prime/sessions.{type State, Claim, Claimed, TakenOver}
import genesis_prime/step.{
  Asked, CallerId, Connection, ConnectionId, Effects, Reply, Send, Stopping,
  Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{AccountId}
import owned_test

const first = ConnectionId(1)

const second = ConnectionId(2)

const third = ConnectionId(3)

const account = AccountId(7)

fn ask(
  state state: State,
  caller caller: Int,
  message message: sessions.Message,
) -> #(State, step.Step(sessions.Outgoing, Nil)) {
  sessions.step(state, support.input(Asked(caller: CallerId(caller), message:)))
}

fn ended(
  state state: State,
  watch watch: Int,
) -> #(State, step.Step(sessions.Outgoing, Nil)) {
  sessions.step(state, support.input(WatchEnded(watch: WatchId(watch))))
}

pub fn a_first_claim_takes_the_slot_answers_claimed_and_watches_the_claimer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: first),
    )
  assert taken
    == Effects([
      Watch(watch: WatchId(1), target: Connection(first)),
      Reply(CallerId(1), Claimed),
    ])
    as "the claimer is watched under a new watch and answered; nobody is sent anything"
}

pub fn a_second_claim_for_the_same_account_answers_claimed_sends_taken_over_to_the_first_and_watches_the_second_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: first),
    )
  let #(_, taken) =
    ask(state:, caller: 2, message: Claim(account:, connection: second))
  assert taken
    == Effects([
      Watch(watch: WatchId(2), target: Connection(second)),
      Send(to: Connection(first), message: TakenOver),
      Reply(CallerId(2), Claimed),
    ])
    as "the new holder is watched, the old one is told, and the claimer is answered, in the order of the sequence in the rule's doc comment"
}

pub fn a_claim_by_the_holder_answers_claimed_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: first),
    )
  let #(state, taken) =
    ask(state:, caller: 2, message: Claim(account:, connection: first))
  assert taken == Effects([Reply(CallerId(2), Claimed)])
    as "no new watch and nobody told"
  // The slot is still the first connection's: a claim by another takes it from
  // the first, under the second watch the rule has opened.
  let #(_, taken) =
    ask(state:, caller: 3, message: Claim(account:, connection: second))
  assert taken
    == Effects([
      Watch(watch: WatchId(2), target: Connection(second)),
      Send(to: Connection(first), message: TakenOver),
      Reply(CallerId(3), Claimed),
    ])
}

pub fn claims_for_different_accounts_do_not_touch_each_other_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: first),
    )
  let #(_, taken) =
    ask(
      state:,
      caller: 2,
      message: Claim(account: AccountId(8), connection: second),
    )
  assert taken
    == Effects([
      Watch(watch: WatchId(2), target: Connection(second)),
      Reply(CallerId(2), Claimed),
    ])
    as "another account's slot is free"
}

pub fn a_holders_end_frees_its_slot_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: first),
    )
  let #(state, taken) = ended(state:, watch: 1)
  assert taken == Effects([]) as "freeing a slot needs no effect"
  let #(_, taken) =
    ask(state:, caller: 2, message: Claim(account:, connection: second))
  assert taken
    == Effects([
      Watch(watch: WatchId(2), target: Connection(second)),
      Reply(CallerId(2), Claimed),
    ])
    as "the slot is free, so no one is sent TakenOver"
}

pub fn an_old_holders_end_after_a_takeover_frees_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: first),
    )
  let #(state, _) =
    ask(state:, caller: 2, message: Claim(account:, connection: second))
  let #(state, taken) = ended(state:, watch: 1)
  assert taken == Effects([])
    as "the old holder's watch ends and nothing follows"
  let #(_, taken) =
    ask(state:, caller: 3, message: Claim(account:, connection: third))
  assert taken
    == Effects([
      Watch(watch: WatchId(3), target: Connection(third)),
      Send(to: Connection(second), message: TakenOver),
      Reply(CallerId(3), Claimed),
    ])
    as "the slot still names the second connection, which is the one told"
}

pub fn a_restarted_sessions_rebuilds_its_slots_from_the_claims_that_arrive_test() -> Nil {
  use <- owned_test.run(5000)
  // Each living connection claims again in a fresh state, in the order its
  // claim arrives.
  let #(state, first_claim) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: first),
    )
  let #(state, second_claim) =
    ask(
      state:,
      caller: 2,
      message: Claim(account: AccountId(8), connection: second),
    )
  assert first_claim
    == Effects([
      Watch(watch: WatchId(1), target: Connection(first)),
      Reply(CallerId(1), Claimed),
    ])
  assert second_claim
    == Effects([
      Watch(watch: WatchId(2), target: Connection(second)),
      Reply(CallerId(2), Claimed),
    ])
    as "no one is told TakenOver: the slots are of different accounts"
  // The slots now match the living connections: a third login to the first
  // account takes it from the first connection, and only from it.
  let #(_, taken) =
    ask(state:, caller: 3, message: Claim(account:, connection: third))
  assert taken
    == Effects([
      Watch(watch: WatchId(3), target: Connection(third)),
      Send(to: Connection(first), message: TakenOver),
      Reply(CallerId(3), Claimed),
    ])
}

/// Claims of one account from an older connection (`first`) and a newer one
/// (`second`, a higher id), arriving at `state` in the order `older_first`
/// says, as they do after Sessions restarts. Returns the state and what each
/// claim did, in arrival order.
fn older_and_newer_claim(
  state state: State,
  older_first older_first: Bool,
) -> #(
  State,
  step.Step(sessions.Outgoing, Nil),
  step.Step(sessions.Outgoing, Nil),
) {
  let older = Claim(account:, connection: first)
  let newer = Claim(account:, connection: second)
  let #(message_one, message_two) = case older_first {
    True -> #(older, newer)
    False -> #(newer, older)
  }
  let #(state, one) = ask(state:, caller: 1, message: message_one)
  let #(state, two) = ask(state:, caller: 2, message: message_two)
  #(state, one, two)
}

pub fn after_a_restart_the_newer_login_keeps_the_slot_when_the_older_claims_first_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, older, newer) =
    older_and_newer_claim(state: sessions.new(Nil), older_first: True)
  assert older
    == Effects([
      Watch(watch: WatchId(1), target: Connection(first)),
      Reply(CallerId(1), Claimed),
    ])
    as "the older connection takes the empty slot"
  assert newer
    == Effects([
      Watch(watch: WatchId(2), target: Connection(second)),
      Send(to: Connection(first), message: TakenOver),
      Reply(CallerId(2), Claimed),
    ])
    as "the newer login's higher id takes the slot and the older holder is told"
  let #(_, taken) =
    ask(state:, caller: 3, message: Claim(account:, connection: third))
  assert taken
    == Effects([
      Watch(watch: WatchId(3), target: Connection(third)),
      Send(to: Connection(second), message: TakenOver),
      Reply(CallerId(3), Claimed),
    ])
    as "the slot names the second connection"
}

pub fn after_a_restart_the_newer_login_keeps_the_slot_when_it_claims_first_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, newer, older) =
    older_and_newer_claim(state: sessions.new(Nil), older_first: False)
  assert newer
    == Effects([
      Watch(watch: WatchId(1), target: Connection(second)),
      Reply(CallerId(1), Claimed),
    ])
  assert older == Effects([Reply(CallerId(2), TakenOver)])
    as "the older connection is answered TakenOver; no watch, and the holder is told nothing"
  let #(_, taken) =
    ask(state:, caller: 3, message: Claim(account:, connection: third))
  assert taken
    == Effects([
      Watch(watch: WatchId(2), target: Connection(third)),
      Send(to: Connection(second), message: TakenOver),
      Reply(CallerId(3), Claimed),
    ])
    as "the slot is still the second connection's, and the refused claim opened no watch, so the next is 2"
}

pub fn after_two_restarts_the_newer_login_keeps_the_slot_when_the_older_claims_first_test() -> Nil {
  use <- owned_test.run(5000)
  // Sessions restarted twice: the newer login claimed in the second one, whose
  // slots are lost with it, so the third starts empty.
  let #(_lost_with_the_second_sessions, taken) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: second),
    )
  assert taken
    == Effects([
      Watch(watch: WatchId(1), target: Connection(second)),
      Reply(CallerId(1), Claimed),
    ])
    as "the second Sessions gave the newer login the slot"
  let #(_, older, newer) =
    older_and_newer_claim(state: sessions.new(Nil), older_first: True)
  assert older
    == Effects([
      Watch(watch: WatchId(1), target: Connection(first)),
      Reply(CallerId(1), Claimed),
    ])
    as "the third Sessions knows nothing of the second's slot"
  assert newer
    == Effects([
      Watch(watch: WatchId(2), target: Connection(second)),
      Send(to: Connection(first), message: TakenOver),
      Reply(CallerId(2), Claimed),
    ])
    as "the older connection's claim came first and the newer login still ends up holding the slot"
}

pub fn after_two_restarts_the_newer_login_keeps_the_slot_when_it_claims_first_test() -> Nil {
  use <- owned_test.run(5000)
  // The newer login claimed in the second Sessions, lost with it, as above.
  let #(_, newer, older) =
    older_and_newer_claim(state: sessions.new(Nil), older_first: False)
  assert newer
    == Effects([
      Watch(watch: WatchId(1), target: Connection(second)),
      Reply(CallerId(1), Claimed),
    ])
  assert older == Effects([Reply(CallerId(2), TakenOver)])
    as "the older connection, which waited through both restarts, is refused"
}

pub fn a_claim_after_the_holder_ended_takes_the_freed_slot_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    ask(
      state: sessions.new(Nil),
      caller: 1,
      message: Claim(account:, connection: second),
    )
  let #(state, _) = ended(state:, watch: 1)
  let #(_, taken) =
    ask(state:, caller: 2, message: Claim(account:, connection: first))
  assert taken
    == Effects([
      Watch(watch: WatchId(2), target: Connection(first)),
      Reply(CallerId(2), Claimed),
    ])
    as "the holder's end freed the slot, so even a lower id takes it and no one is told"
}

pub fn a_stopping_sessions_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    sessions.step(sessions.new(Nil), support.input(Stopping(deadline_ms: 5000)))
  assert taken == Effects([step.Stop])
}
