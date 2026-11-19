//// What the development command tests on the real store share: a connection's
//// ask made the stored character's own and answered by the store.

import account_store_support.{type Stored}
import genesis_prime/client_connection
import genesis_prime/store.{
  CharacterLoaded, ForWorld, Items, LoadCharacter, Move, SavePlace, World,
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
