//// Character select (`genesis_prime/game/character_select`), the feature the
//// game connection's rule holds one field of. Expected values are its doc
//// comment, as approved on the card: it asks the store for the account's
//// characters once for each 0x07E0, and takes the store's answer itself, an
//// answer of a kind it did not ask for being none it takes. A second 0x07E0
//// while the store is asked is the game connection's to hold, with the
//// client's other frames (test/game_connection_test.gleam).

import genesis_prime/game/character_select.{Ask}
import genesis_prime/store.{
  AccountId, Characters, ListCharacters, NoSuchAccount, Unavailable,
}
import owned_test

pub fn the_clients_0x07e0_asks_the_store_for_the_accounts_characters_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) = character_select.started(AccountId(7))
  assert effects == [Ask(request: ListCharacters(account_id: AccountId(7)))]
  assert character_select.waiting(state)
    as "the store's answer is awaited, so the game connection holds the client's frames"
}

pub fn an_answer_that_is_no_list_or_comes_with_no_ask_out_is_none_character_select_takes_test() -> Nil {
  use <- owned_test.run(5000)
  let #(asking, _) = character_select.started(AccountId(7))
  let answered = fn(state, answer) {
    character_select.answered(
      state,
      answer,
      filetime: 0,
      realm_id: 1,
      max_characters: 2,
    )
  }
  assert answered(asking, NoSuchAccount) == Error(Nil)
    as "a login name's answer is none a list ask gets"
  assert answered(asking, Unavailable) == Error(Nil)
    as "the failures every store ask shares are the game connection's to handle"
  assert answered(character_select.new(), Characters([])) == Error(Nil)
    as "rows nobody asked for"
  let assert Ok(#(state, _)) = answered(asking, Characters([]))
  assert !character_select.waiting(state) as "the list is sent"
  assert answered(state, Characters([])) == Error(Nil)
    as "one ask has one answer"
}
