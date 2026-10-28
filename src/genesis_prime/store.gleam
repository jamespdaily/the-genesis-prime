//// What a rule asks the store and what the store answers. The store runs each
//// ask in a worker of its own (genesis_prime/store/worker); these types are
//// the ask's contract, so a rule can hold them.

import genesis_prime/login/guid.{type Guid}
import genesis_prime/table/id.{
  type CharacterCustomizationLabelId, type ClassId, type RaceId,
}

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

/// One label of a character's look with the value it was given: the client's
/// own customisation of its model (a label of CharacterCustomizationLabel and
/// one of the values CharacterCustomization lists for it, opcode.0x25b).
pub type LookEntry {
  LookEntry(label: CharacterCustomizationLabelId, value: Int)
}

/// A character as the character list needs it: what the client's list shows
/// of it (lua.CharacterSelection.OnLoadFromCharacter.list) and what the list's
/// entry carries (opcode.0x117). Each id keys the client table of its name,
/// except `faction_id`, a Faction2 id the CharacterCreation table does not
/// name as one; `gender` and `path` are the client's own numbers (the client
/// shows paths 0 to 3). `look` and `bones` are what the create request carried:
/// the look's labels with their values, and each bone value as the 32 bits of
/// its float.
pub type Character {
  Character(
    character_id: CharacterId,
    name: String,
    gender: Int,
    race_id: RaceId,
    class_id: ClassId,
    faction_id: Int,
    level: Int,
    path: Int,
    world_id: Int,
    world_zone_id: Int,
    position_x: Float,
    position_y: Float,
    position_z: Float,
    look: List(LookEntry),
    bones: List(Int),
  )
}

/// A character to make, from a create request and the CharacterCreation row it
/// names: the row gives the gender (its sex), race, class and faction.
/// Everything else a new character has is the store's: level 1 and no world,
/// zone or position until world entry.
pub type NewCharacter {
  NewCharacter(
    name: String,
    gender: Int,
    race_id: RaceId,
    class_id: ClassId,
    faction_id: Int,
    path: Int,
    look: List(LookEntry),
    bones: List(Int),
  )
}

/// What a rule asks the store.
pub type Request {
  /// The account with this login name.
  FindAccount(login_name: String)
  /// The account's characters, in the order they were created.
  ListCharacters(account_id: AccountId)
  /// Makes the character for the account unless it already has
  /// `character_slots` characters. The name must be unique ignoring case, and
  /// the account's creates run one at a time, both held by the database.
  CreateCharacter(
    account_id: AccountId,
    character: NewCharacter,
    character_slots: Int,
  )
}

/// What the store answers.
pub type Answer {
  AccountFound(account: Account)
  NoSuchAccount
  /// The account's characters, in the order they were created; none when it
  /// has none, or when no such account exists.
  Characters(characters: List(Character))
  /// The character was made, with this id.
  CharacterCreated(character_id: CharacterId)
  /// Another character has the name, in any case; nothing was made.
  NameTaken
  /// The account already has as many characters as its slots; nothing was
  /// made.
  NoFreeSlot
  /// The database could not be reached, or did not answer within the
  /// query's own timeout. A read changed nothing, so asking again is safe; a
  /// create ran in one transaction, which committed or did not, and the
  /// account's list on its next login shows which.
  Unavailable
}
