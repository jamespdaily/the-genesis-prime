//// What a rule asks the store and what the store answers. The store runs each
//// ask in a worker of its own (genesis_prime/store/worker); these types are
//// the ask's contract, so a rule can hold them.

import genesis_prime/login/guid.{type Guid}
import genesis_prime/table/id.{
  type CharacterCustomizationLabelId, type ClassId, type RaceId,
  CharacterCustomizationLabelId,
}
import gleam/list

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

/// The look of parallel lists of label ids and values, as the client's create
/// request and the character's row hold them, each label with the value at
/// its position; the longer list's extra items are left out.
pub fn look(
  labels labels: List(Int),
  values values: List(Int),
) -> List(LookEntry) {
  list.zip(labels, values)
  |> list.map(fn(pair) {
    LookEntry(label: CharacterCustomizationLabelId(pair.0), value: pair.1)
  })
}

/// Whether a character's name stands or its player must pick another before
/// playing it. The client offers a rename, not play, for a character whose
/// list entry carries the needs-a-rename bit (bRequiresRename; opcode.0x117,
/// lua.CharacterSelection.OnSelectCharacter), and a rename clears it
/// (opcode.0x14b).
pub type Naming {
  NameStands
  NeedsRename
}

/// A character as the character list needs it: what the client's list shows
/// of it (lua.CharacterSelection.OnLoadFromCharacter.list) and what the list's
/// entry carries (opcode.0x117). Each id keys the client table of its name,
/// except `faction_id`, a Faction2 id the CharacterCreation table does not
/// name as one; `gender` and `path` are the client's own numbers (the client
/// shows paths 0 to 3). `look` and `bones` are what the create request carried:
/// the look's labels with their values, and each bone value as the 32 bits of
/// its float. `naming` is the entry's rename bit.
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
    naming: Naming,
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

/// What a rule asks the store, grouped by who asks: the STS login's request
/// and the character select's, so a rule names only the group it does not ask
/// as a mismatch.
pub type Request {
  Login(request: LoginRequest)
  Select(request: SelectRequest)
}

/// What the STS login asks the store.
pub type LoginRequest {
  /// The account with this login name.
  FindAccount(login_name: String)
}

/// What character select asks the store.
pub type SelectRequest {
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
  /// Deletes the account's character. The account's id is in the delete, so
  /// no other account's character can be touched.
  DeleteCharacter(account_id: AccountId, character_id: CharacterId)
  /// Gives the account's character the name and clears its rename mark, in
  /// one update, when the account has the character and it is marked. The name
  /// must be unique ignoring case, held by the database.
  RenameCharacter(
    account_id: AccountId,
    character_id: CharacterId,
    name: String,
  )
}

/// What the store answers: the failure every request shares, or the answer to
/// the group of the request asked, so a rule that asks one group takes only
/// that group's answers and names the other group once.
pub type Answer {
  /// The database could not be reached, or did not answer within the
  /// query's own timeout. A read changed nothing, so asking again is safe; a
  /// create ran in one transaction, which committed or did not, and the
  /// account's list on its next login shows which.
  Unavailable
  ForLogin(answer: FindAccountAnswer)
  ForSelect(answer: SelectAnswer)
}

/// What the store answers character select, one variant for each of its
/// requests.
pub type SelectAnswer {
  /// The account's characters, in the order they were created; none when it
  /// has none, or when no such account exists.
  Listed(characters: List(Character))
  Created(answer: CreateAnswer)
  Deleted(answer: DeleteAnswer)
  Renamed(answer: RenameAnswer)
}

/// What the store answers a `FindAccount`.
pub type FindAccountAnswer {
  AccountFound(account: Account)
  NoSuchAccount
}

/// What the store answers a `CreateCharacter`.
pub type CreateAnswer {
  /// The character was made, with this id.
  CharacterCreated(character_id: CharacterId)
  /// Another character has the name, in any case; nothing was made.
  NameTaken
  /// The account already has as many characters as its slots; nothing was
  /// made.
  NoFreeSlot
}

/// What the store answers a `DeleteCharacter`.
pub type DeleteAnswer {
  /// The character was deleted.
  CharacterDeleted
  /// The account has no such character; nothing was deleted.
  NoSuchCharacter
}

/// What the store answers a `RenameCharacter`.
pub type RenameAnswer {
  /// The character has the name, as stored, and is no longer marked.
  CharacterRenamed(name: String)
  /// Another character has the name, in any case; nothing changed, and the
  /// character is still marked.
  NewNameTaken
  /// The account has no such character, or it is not marked; nothing changed.
  NotRenamable
}
