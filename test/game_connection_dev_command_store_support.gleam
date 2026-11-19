//// What the development command tests on the real store share: a connection's
//// ask made the stored character's own and answered by the store.

import account_store_support.{type Stored}
import genesis_prime/store.{Items, Move, SavePlace}

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
