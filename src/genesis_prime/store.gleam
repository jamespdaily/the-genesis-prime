//// What a rule asks the store and what the store answers. The store runs each
//// ask in a worker of its own (genesis_prime/store/worker); these types are
//// the ask's contract, so a rule can hold them.

import genesis_prime/login/guid.{type Guid}

/// An account, keyed by the account table's id.
pub type AccountId {
  AccountId(Int)
}

/// An account as the STS login needs it.
pub type Account {
  Account(
    account_id: AccountId,
    /// The login name, in lower case, as the client sends it in LoginStart.
    login_name: String,
    /// The SRP salt and verifier the password is checked against; the
    /// password itself is never kept.
    srp_salt: BitArray,
    srp_verifier: BitArray,
    /// The game account's GUID, which the STS login names in the client's
    /// list of game accounts.
    game_account_id: Guid,
  )
}

/// What a rule asks the store.
pub type Request {
  /// The account with this login name.
  FindAccount(login_name: String)
}

/// What the store answers.
pub type Answer {
  AccountFound(account: Account)
  NoSuchAccount
  /// The database could not be reached, or did not answer within the
  /// query's own timeout. A read changed nothing, so asking again is safe.
  Unavailable
}
