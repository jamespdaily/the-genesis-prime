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

/// A character, keyed by the character table's id.
pub type CharacterId {
  CharacterId(Int)
}

/// A character as the character list needs it: what the client's list shows
/// of it (lua.CharacterSelection.OnLoadFromCharacter.list) and what the list's
/// entry carries (opcode.0x117). Each id keys the client table of its name;
/// `gender` and `path` are the client's own numbers (the client shows paths 0
/// to 3). The appearance is not here: nothing writes it yet.
pub type Character {
  Character(
    character_id: CharacterId,
    name: String,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    level: Int,
    path: Int,
    world_id: Int,
    world_zone_id: Int,
    position_x: Float,
    position_y: Float,
    position_z: Float,
  )
}

/// What a rule asks the store.
pub type Request {
  /// The account with this login name.
  FindAccount(login_name: String)
  /// The account's characters, in the order they were created.
  ListCharacters(account_id: AccountId)
}

/// What the store answers.
pub type Answer {
  AccountFound(account: Account)
  NoSuchAccount
  /// The account's characters, in the order they were created; none when it
  /// has none, or when no such account exists.
  Characters(characters: List(Character))
  /// The database could not be reached, or did not answer within the
  /// query's own timeout. A read changed nothing, so asking again is safe.
  Unavailable
}
