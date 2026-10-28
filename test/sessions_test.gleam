//// The sessions rule, pure. Expected values come from the rule's own contract
//// in the doc comment of `genesis_prime/sessions`, as approved on the one
//// login per account card: one slot per account, the newest login keeps it,
//// the connection it replaced is sent `TakenOver`, and Sessions watches each
//// holder, so a holder's end frees the slot and the end of a replaced
//// connection frees nothing. A connection is named by its `ConnectionId`
//// and a watch by its `WatchId`; the effects name both.

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

fn claim(
  state state: State,
  caller caller: Int,
  account account: store.AccountId,
  connection connection: step.ConnectionId,
) -> #(State, step.Step(sessions.Outgoing, Nil)) {
  sessions.step(
    state,
    support.input(Asked(
      caller: CallerId(caller),
      message: Claim(account:, connection:),
    )),
  )
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
    claim(state: sessions.new(Nil), caller: 1, account:, connection: first)
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
    claim(state: sessions.new(Nil), caller: 1, account:, connection: first)
  let #(_, taken) = claim(state:, caller: 2, account:, connection: second)
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
    claim(state: sessions.new(Nil), caller: 1, account:, connection: first)
  let #(state, taken) = claim(state:, caller: 2, account:, connection: first)
  assert taken == Effects([Reply(CallerId(2), Claimed)])
    as "no new watch and nobody told"
  // The slot is still the first connection's: a claim by another takes it from
  // the first, under the second watch the rule has opened.
  let #(_, taken) = claim(state:, caller: 3, account:, connection: second)
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
    claim(state: sessions.new(Nil), caller: 1, account:, connection: first)
  let #(_, taken) =
    claim(state:, caller: 2, account: AccountId(8), connection: second)
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
    claim(state: sessions.new(Nil), caller: 1, account:, connection: first)
  let #(state, taken) = ended(state:, watch: 1)
  assert taken == Effects([]) as "freeing a slot needs no effect"
  let #(_, taken) = claim(state:, caller: 2, account:, connection: second)
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
    claim(state: sessions.new(Nil), caller: 1, account:, connection: first)
  let #(state, _) = claim(state:, caller: 2, account:, connection: second)
  let #(state, taken) = ended(state:, watch: 1)
  assert taken == Effects([])
    as "the old holder's watch ends and nothing follows"
  let #(_, taken) = claim(state:, caller: 3, account:, connection: third)
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
    claim(state: sessions.new(Nil), caller: 1, account:, connection: first)
  let #(state, second_claim) =
    claim(state:, caller: 2, account: AccountId(8), connection: second)
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
  let #(_, taken) = claim(state:, caller: 3, account:, connection: third)
  assert taken
    == Effects([
      Watch(watch: WatchId(3), target: Connection(third)),
      Send(to: Connection(first), message: TakenOver),
      Reply(CallerId(3), Claimed),
    ])
}

pub fn a_stopping_sessions_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    sessions.step(sessions.new(Nil), support.input(Stopping(deadline_ms: 5000)))
  assert taken == Effects([step.Stop])
}
