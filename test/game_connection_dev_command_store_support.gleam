//// What the development command tests on the real store share: a connection's
//// ask made the stored character's own and answered by the store.

import account_store_support.{type Stored, Stored}
import genesis_prime/client_connection
import genesis_prime/store.{
  CharacterCreated, CharacterLoaded, CreateCharacter, Created, ForSelect,
  ForWorld, Items, LoadCharacter, Move, NewCharacter, SavePlace, Select, World,
}
import gleam/int
import gleam/list

/// The store's answer to the connection's ask, made the stored character's
/// own: the ask names the account, character and session epoch the tests'
/// connection holds (account 7, character 42, epoch 1), none of which the real
/// store's character has, so they are replaced by the stored character's and
/// the epoch of a login just before (`account_store_support.loaded`). An items
/// ask and a place save are covered; any other ask is a mistake of the test.
pub fn through_the_store(
  stored stored: Stored,
  request request: store.Request,
) -> store.Answer {
  let own = case request {
    Items(asked) ->
      Items(account_store_support.own_request(stored:, request: asked))
    Move(SavePlace(..) as save) -> {
      let #(epoch, _) = account_store_support.loaded(stored:)
      let assert Ok(session_epoch) = store.session_epoch(epoch)
        as "a login's epoch is 1 or more"
      Move(
        SavePlace(
          ..save,
          account_id: stored.account,
          character_id: stored.character_id,
          session_epoch:,
        ),
      )
    }
    store.Login(..) | store.Select(..) | store.World(..) ->
      panic as "through_the_store makes an items ask and a place save the stored character's"
  }
  account_store_support.ask(store: stored.store, request: own)
}

/// A stored character created with `starting_credits` credits, on a store of its own: with
/// 0 it has no credits row (`create_character.sql` makes the row only for an amount above 0).
pub fn stored_with_credits(starting_credits starting_credits: Int) -> Stored {
  let store = account_store_support.start_store(pool_size: 2)
  let account =
    account_store_support.insert_account(store:, login_name: "login-1")
  let assert ForSelect(Created(CharacterCreated(character_id:))) =
    account_store_support.ask(
      store:,
      request: Select(CreateCharacter(
        account_id: account,
        character: NewCharacter(
          ..account_store_support.a_new_character("Ab Cd"),
          starting_credits:,
        ),
        character_slots: 1,
      )),
    )
    as "a character is created with the starting credits"
  Stored(store:, account:, character_id:)
}

/// The currency rows the stored character's next login finds, sorted by type.
pub fn currencies_found(stored stored: Stored) -> List(store.HeldCurrency) {
  let assert ForWorld(CharacterLoaded(currencies:, ..)) =
    account_store_support.ask(
      store: stored.store,
      request: World(LoadCharacter(stored.account, stored.character_id, 0)),
    )
    as "the account's character loads"
  list.sort(currencies, fn(a, b) {
    int.compare(a.currency_type_id, b.currency_type_id)
  })
}

/// The store request of an ask of the store.
pub fn store_request(
  request request: client_connection.Request,
) -> store.Request {
  let assert client_connection.AskStore(request) = request
    as "the ask is the store's"
  request
}
