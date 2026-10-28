//// Character select (`genesis_prime/game/character_select`), the feature the
//// game connection's rule holds one field of. Expected values are its doc
//// comment, as approved on the card: it asks the store for the account's
//// characters once for each 0x07E0, and a second 0x07E0 while the store is
//// asked adds no second ask.

import genesis_prime/game/character_select.{AskCharacters}
import genesis_prime/store.{AccountId}
import owned_test

pub fn the_clients_0x07e0_asks_the_store_for_the_accounts_characters_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    character_select.started(character_select.new(), AccountId(7))
  assert effects == [AskCharacters(account_id: AccountId(7))]
}

pub fn a_0x07e0_while_the_store_is_asked_adds_no_second_ask_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    character_select.started(character_select.new(), AccountId(7))
  let #(_, effects) = character_select.started(state, AccountId(7))
  assert effects == []
    as "the store's one answer is awaited; asking twice would send two lists for one request"
}
