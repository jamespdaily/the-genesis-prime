//// The development commands on the real store: what a command changes is saved
//// with the place and found by the next login. Expected values come from these
//// places.
//// - XpPerLevel.minXpForLevel: level 3 from 1710, level 4 from 2860.
//// - `save_place.sql` writes the experience and the level the save carries, and
////   `load_character.sql` gives them back (`store.CharacterLoaded`).
//// - The character is `account_store_support.a_new_character`: level 3, experience 1710.
//// - `save_place.sql` writes the quest log the save carries, a Completed row with its
////   completion time, and `load_character.sql` gives it back (`store.CharacterLoaded.quests`).

import account_store_support
import connection_rule_support as rule_support
import game_connection_dev_command_store_support as store_support
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{AskStore, FromStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step
import genesis_prime/store.{
  CharacterLoaded, ForItems, ForMove, ForWorld, LoadCharacter, Move, PlaceSaved,
  SavePlace, World,
}
import gleam/list
import gleam/option.{None, Some}
import owned_test

pub fn the_level_and_experience_commanded_are_loaded_by_the_next_login_test() -> Nil {
  use <- owned_test.run(120_000)
  let stored = account_store_support.stored_holding(worn: [], items: [])
  let assert ForWorld(CharacterLoaded(character:, saved_experience:, ..)) =
    account_store_support.ask(
      store: stored.store,
      request: World(LoadCharacter(stored.account, stored.character_id, 0)),
    )
    as "the account's character loads"
  assert character.level == 3 && saved_experience == Some(1710)
    as "the stored character starts at level 3, experience 1710"
  let state = dev_support.in_world_as(character:, experience: saved_experience)
  let #(state, _) = dev_support.said(state:, text: "!level 4")
  let #(state, save) =
    support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert AskStore(Move(SavePlace(..)) as asked) = support.ask_request(save)
    as "the save timer asks the store to save the place"
  let answer = store_support.through_the_store(stored:, request: asked)
  assert answer == ForMove(PlaceSaved) as "the store saved the place"
  let #(_, _) =
    support.answer(state:, taken: save, outcome: step.Answer(FromStore(answer)))
  let assert ForWorld(CharacterLoaded(
    character: reloaded,
    saved_experience: reloaded_experience,
    ..,
  )) =
    account_store_support.ask(
      store: stored.store,
      request: World(LoadCharacter(stored.account, stored.character_id, 0)),
    )
    as "the next login loads the character"
  assert reloaded.level == 4 && reloaded_experience == Some(2860)
    as "XpPerLevel: level 4 starts at 2860, which the save kept"
  account_store_support.stop(stored.store)
}

/// A connection of the player the stored character is, holding the currencies its next
/// login finds.
fn connected_to(
  stored stored: account_store_support.Stored,
) -> game_connection.State {
  dev_support.in_world_holding_currencies(
    currencies: store_support.currencies_found(stored:),
  )
}

/// The store's answer to the ask `taken` ends with, as an outcome of the connection.
fn stored_answer(
  stored stored: account_store_support.Stored,
  taken taken: step.ConnectionStep(client_connection.Request),
) -> step.Outcome(client_connection.Answer) {
  step.Answer(
    FromStore(store_support.through_the_store(
      stored:,
      request: store_support.store_request(request: support.ask_request(taken)),
    )),
  )
}

pub fn a_currency_the_command_set_is_loaded_by_the_next_login_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(
    [
      #(
        1000,
        [store.HeldCurrency(currency_type_id: 1, amount: 1000)],
        "a character with a credits row",
      ),
      #(0, [], "a character created with 0 starting credits has no row"),
    ],
    fn(row) {
      let #(starting_credits, rows, why) = row
      let stored = store_support.stored_with_credits(starting_credits:)
      assert store_support.currencies_found(stored:) == rows as why
      let state = connected_to(stored:)
      let #(state, taken) = dev_support.said(state:, text: "!currency 1 5000")
      let outcome = stored_answer(stored:, taken:)
      assert outcome
        == step.Answer(FromStore(ForItems(store.CurrencySet(amount: 5000))))
        as why
      let #(_, answered) = support.answer(state:, taken:, outcome:)
      assert support.written_ids(answered) == [0x0919, 0x00DD, 0x01C8] as why
      assert store_support.currencies_found(stored:)
        == [store.HeldCurrency(currency_type_id: 1, amount: 5000)]
        as { why <> ": the next login's load holds 5000" }
      account_store_support.stop(stored.store)
    },
  )
}

pub fn a_currency_set_that_committed_and_was_not_acknowledged_is_loaded_by_the_next_login_test() -> Nil {
  use <- owned_test.run(120_000)
  let stored = store_support.stored_with_credits(starting_credits: 1000)
  let state = connected_to(stored:)
  let #(state, taken) = dev_support.said(state:, text: "!currency 1 5000")
  assert stored_answer(stored:, taken:)
    == step.Answer(FromStore(ForItems(store.CurrencySet(amount: 5000))))
    as "the store ran the request and committed it"
  let #(state, answered) =
    support.answer(state:, taken:, outcome: step.NoAnswerInTime)
  assert support.written_ids(answered) == []
    as "the connection never wrote the amount: no 0x919 for a set it was not told of"
  let #(_, saved) =
    support.answer(
      state:,
      taken: answered,
      outcome: stored_answer(stored:, taken: answered),
    )
  assert support.disconnect(saved, support.keyed()) == LostUserServer
    as "the connection ends with reason 8 after the place is saved"
  assert rule_support.stops(saved)
  assert store_support.currencies_found(stored:)
    == [store.HeldCurrency(currency_type_id: 1, amount: 5000)]
    as "the database holds the committed amount, which the next login's load gives"
  account_store_support.stop(stored.store)
}

pub fn two_currency_commands_in_a_row_leave_the_second_total_test() -> Nil {
  use <- owned_test.run(120_000)
  let stored = store_support.stored_with_credits(starting_credits: 1000)
  let state = connected_to(stored:)
  let #(state, first) = dev_support.said(state:, text: "!currency 1 5000")
  let #(state, _) = dev_support.said(state:, text: "!currency 1 100")
  let #(state, second) =
    support.answer(
      state:,
      taken: first,
      outcome: stored_answer(stored:, taken: first),
    )
  let #(_, _) =
    support.answer(
      state:,
      taken: second,
      outcome: stored_answer(stored:, taken: second),
    )
  assert store_support.currencies_found(stored:)
    == [store.HeldCurrency(currency_type_id: 1, amount: 100)]
    as "the second line waited for the first answer, was read with 5000 held, and set 100"
  account_store_support.stop(stored.store)
}

pub fn the_quest_commanded_is_loaded_by_the_next_login_test() -> Nil {
  use <- owned_test.run(120_000)
  let stored = account_store_support.stored_holding(worn: [], items: [])
  let assert ForWorld(CharacterLoaded(
    character:,
    saved_experience:,
    quests:,
    ..,
  )) =
    account_store_support.ask(
      store: stored.store,
      request: World(LoadCharacter(stored.account, stored.character_id, 0)),
    )
    as "the account's character loads"
  assert quests == [] as "the stored character holds no quest"
  let state = dev_support.in_world_as(character:, experience: saved_experience)
  let #(state, _) = dev_support.said(state:, text: "!quest 5972 done")
  let #(state, save) =
    support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert AskStore(Move(SavePlace(..)) as asked) = support.ask_request(save)
    as "the save timer asks the store to save the place and the quests"
  let answer = store_support.through_the_store(stored:, request: asked)
  assert answer == ForMove(PlaceSaved) as "the store saved the place"
  let #(_, _) =
    support.answer(state:, taken: save, outcome: step.Answer(FromStore(answer)))
  let assert ForWorld(CharacterLoaded(quests: reloaded, ..)) =
    account_store_support.ask(
      store: stored.store,
      request: World(LoadCharacter(stored.account, stored.character_id, 0)),
    )
    as "the next login loads the character"
  let assert [row] = reloaded as "the next login holds the one quest"
  assert row.quest_id == 5972 && row.state == 3 && row.active == None
    as "quest 5972 is Completed, in no active entry"
  assert option.is_some(row.completed_at)
    as "save_place.sql: a Completed row keeps its completion time"
  account_store_support.stop(stored.store)
}
