//// The development commands on the real store: what a command changes is saved
//// with the place and found by the next login. Expected values come from these
//// places.
//// - XpPerLevel.minXpForLevel: level 3 from 1710, level 4 from 2860.
//// - `save_place.sql` writes the experience and the level the save carries, and
////   `load_character.sql` gives them back (`store.CharacterLoaded`).
//// - The character is `account_store_support.a_new_character`: level 3, experience 1710.

import account_store_support
import game_connection_dev_command_store_support as store_support
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{AskStore, FromStore}
import genesis_prime/game/connection/state as connection_state
import genesis_prime/step
import genesis_prime/store.{
  CharacterLoaded, ForMove, ForWorld, LoadCharacter, Move, PlaceSaved, SavePlace,
  World,
}
import gleam/option.{Some}
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
