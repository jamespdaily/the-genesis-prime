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
import game_connection_dev_command_store_support as store_support
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{type Request, AskStore, FromStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/item_added
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store.{
  CharacterLoaded, ForItems, ForMove, ForWorld, LoadCharacter, Move, PlaceSaved,
  SavePlace, World,
}
import genesis_prime/table/id.{Item2Id}
import gleam/list
import gleam/option.{None, Some}
import item_expiry_support
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

// ---- !item ----
//
// The character is created with no starting credits, so it has no credits row, as the
// connection's `in_world_as` holds none (`create_character.sql` makes the row only above 0).
// Item2 90021 has maxCharges 5 and 37649 expirationTimeMinutes 30 (the client's rows).

/// The character of the stored account as the next login loads it, in the world with the
/// development commands on.
fn entered(
  stored stored: account_store_support.Stored,
) -> game_connection.State {
  let assert ForWorld(CharacterLoaded(character:, saved_experience:, ..)) =
    account_store_support.ask(
      store: stored.store,
      request: World(LoadCharacter(stored.account, stored.character_id, 0)),
    )
    as "the account's character loads"
  dev_support.in_world_as(character:, experience: saved_experience)
}

/// The guid the answer's 0x111 gave the one stack made.
fn guid_told(taken taken: ConnectionStep(Request)) -> Int {
  let assert [added] =
    list.filter(support.written(taken), fn(frame) {
      frame.message_id == item_added.message_id
    })
    as "one 0x111"
  let assert Ok(item_added.ItemAdded(held_item:)) =
    item_added.decode(added.body)
    as "0x111 decodes"
  held_item.item.item_guid
}

pub fn an_item_the_command_gave_is_loaded_by_the_next_login_with_its_guid_charges_and_expiry_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(
    [
      #(
        "!item 90021",
        90_021,
        5,
        None,
        "maxCharges 5, an item that never runs out",
      ),
      #(
        "!item 37649",
        37_649,
        1,
        Some(item_expiry_support.unix_at(30 * 60_000)),
        "expirationTimeMinutes 30 after the command, maxCharges 1",
      ),
    ],
    fn(row) {
      let stored =
        account_store_support.stored_holding_credits(
          worn: [],
          items: [],
          starting_credits: 0,
        )
      let #(state, taken) =
        dev_support.said(state: entered(stored:), text: row.0)
      let assert AskStore(request) = support.ask_request(taken)
        as "the command asks the store"
      let answer = store_support.through_the_store(stored:, request:)
      let #(_, answered) =
        support.answer(state:, taken:, outcome: step.Answer(FromStore(answer)))
      let guid = guid_told(taken: answered)
      let #(_, items) = account_store_support.loaded(stored:)
      let assert [loaded] = items as "the next login holds the one stack"
      assert loaded.item_guid == guid as "the guid the client was told"
      assert loaded.item2_id == Item2Id(row.1) as row.4
      assert loaded.stack_count == 1
      assert loaded.words.charges == row.2 as row.4
      assert loaded.words.expires_at_unix_ms == row.3 as row.4
      account_store_support.stop(stored.store)
    },
  )
}

pub fn an_item_that_committed_and_was_not_acknowledged_is_loaded_by_the_next_login_test() -> Nil {
  use <- owned_test.run(120_000)
  let stored =
    account_store_support.stored_holding_credits(
      worn: [],
      items: [],
      starting_credits: 0,
    )
  let #(state, taken) =
    dev_support.said(state: entered(stored:), text: "!item 90021")
  let assert AskStore(request) = support.ask_request(taken)
    as "the command asks the store"
  let assert ForItems(store.Bought(..)) =
    store_support.through_the_store(stored:, request:)
    as "the store ran the request and committed it"
  let #(state, answered) =
    support.answer(state:, taken:, outcome: step.NoAnswerInTime)
  assert support.written_ids(answered) == []
    as "the connection never showed the stack"
  let assert AskStore(Move(SavePlace(..)) as save) =
    support.ask_request(answered)
    as "the place is saved once before the end"
  let saved = store_support.through_the_store(stored:, request: save)
  let #(_, ended) =
    support.answer(
      state:,
      taken: answered,
      outcome: step.Answer(FromStore(saved)),
    )
  assert support.disconnect(ended, support.keyed()) == LostUserServer
    as "0x036A reason 8"
  let #(_, items) = account_store_support.loaded(stored:)
  let assert [loaded] = items
    as "the next login holds the stack the store committed"
  assert loaded.item2_id == Item2Id(90_021)
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
