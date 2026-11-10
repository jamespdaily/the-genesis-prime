//// What a rule asks the store and what the store answers. The store runs each
//// ask in a worker of its own (genesis_prime/store/worker); these types are
//// the ask's contract, so a rule can hold them.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/table/id.{
  type CharacterCustomizationLabelId, type ClassId, type Item2Id, type RaceId,
  CharacterCustomizationLabelId,
}
import gleam/bool
import gleam/list
import gleam/option.{type Option}

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

/// How many logins have taken a character: the character's `session_epoch`.
/// Each login that loads the character raises it by one and is told the new
/// value, and a save names the value its login was told, so a save made by an
/// older login finds the epoch moved on and changes nothing. A login's epoch is
/// 1 or more, and only `session_epoch` makes one, so no character id or count
/// passes as an epoch.
pub opaque type SessionEpoch {
  SessionEpoch(Int)
}

/// The epoch with this number, `Error(Nil)` for a number below 1, which no
/// login is told.
pub fn session_epoch(number number: Int) -> Result(SessionEpoch, Nil) {
  use <- bool.guard(when: number < 1, return: Error(Nil))
  Ok(SessionEpoch(number))
}

/// The epoch's number, as the database holds it.
pub fn session_epoch_number(epoch epoch: SessionEpoch) -> Int {
  let SessionEpoch(number) = epoch
  number
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
/// shows paths 0 to 3). `place` is where the character is saved, `None` for a
/// row with world 0, which a character made before create wrote its start
/// place has: world 0 is no World row, so its zone and position mean nothing
/// and are not read (opcode.0xad). `look` and `bones` are what the create
/// request carried: the look's labels with their values, and each bone value as
/// the 32 bits of its float. `naming` is the entry's rename bit.
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
    place: Option(Place),
    look: List(LookEntry),
    bones: List(Int),
    naming: Naming,
  )
}

/// An item a character holds in its equipped slots, inventory or bank, as the
/// character_item table keeps it. `item_guid` is the item's identity for every
/// later message about it: the database made it with the row, never makes it
/// again, and it stays with the item when the item changes place
/// (opcode.0x111.guid). `location` is 0 (equipped), 1 (inventory) or 2 (bank)
/// and `bag_index` the slot in it (the client's own numbers; the table's checks
/// hold the ranges); ability items (location 4) are not stored. `stack_count` is
/// 1 or more.
pub type HeldItem {
  HeldItem(
    item_guid: Int,
    item2_id: Item2Id,
    location: Int,
    bag_index: Int,
    stack_count: Int,
  )
}

/// One quest of a character's log as the character_quest table keeps it, read
/// and written whole: the quest's id (15 bits), its lua QuestState `state` (1 to
/// 7), the Unix seconds it was completed at (`Some` for state 3 and for no other,
/// `character_quest_completed_has_a_time`) and the active entry (`Some` for states
/// 1 and 2 and for no other, `character_quest_active_has_its_entry`). The table's
/// checks hold the ranges; the quest log (genesis_prime/game/quest_log) decodes
/// each row against the client's tables and builds the rows it saves.
pub type QuestRow {
  QuestRow(
    quest_id: Int,
    state: Int,
    completed_at: Option(Int),
    active: Option(ActiveQuest),
  )
}

/// The entry the client's active list carries for a quest (opcode.0x35f): the
/// placeholder objective's id (0 for none), whether the quest is tracked, the done
/// mask (a bit for each of the six objectives), the progress of each objective, the
/// quest's time left and each objective's time left, in milliseconds. There is one
/// timer for each progress value (`character_quest_timers_match_progress`).
pub type ActiveQuest {
  ActiveQuest(
    placeholder_objective_id: Int,
    tracked: Bool,
    done_mask: Int,
    progress: List(Int),
    quest_ms_left: Int,
    objective_ms_left: List(Int),
  )
}

/// The amount of one currency a character holds, as the character_currency table
/// keeps it: the client's currency type id (1 credits, 2 to 14 the others the client
/// keeps; opcode.0x25e) and the amount, 0 or more. A currency with no row is 0 and is
/// not listed.
pub type HeldCurrency {
  HeldCurrency(currency_type_id: Int, amount: Int)
}

/// A held item before its row gives it a guid: the same place and stack as a
/// `HeldItem`, which the store writes in the same transaction as the character
/// that holds it.
pub type NewItem {
  NewItem(item2_id: Item2Id, location: Int, bag_index: Int, stack_count: Int)
}

/// A character to make, from a create request and the CharacterCreation row it
/// names: the row gives the gender (its sex), race, class and faction, its
/// start the place (genesis_prime/game/start_place) and its experience, which
/// the character is stored with and which makes its level
/// (genesis_prime/game/level). `starting_items` are the items the
/// character holds from its first entry, stored with the character, and
/// `starting_credits` the credits it holds from its first entry (a row of
/// character_currency when above 0).
pub type NewCharacter {
  NewCharacter(
    name: String,
    gender: Int,
    race_id: RaceId,
    class_id: ClassId,
    faction_id: Int,
    level: Int,
    experience: Int,
    path: Int,
    place: Place,
    look: List(LookEntry),
    bones: List(Int),
    starting_items: List(NewItem),
    starting_credits: Int,
  )
}

/// What a rule asks the store, grouped by who asks: the STS login's request,
/// character select's, world entry's, the player's movement's and the player's
/// items', so a rule names only the groups it does not ask as a mismatch.
pub type Request {
  Login(request: LoginRequest)
  Select(request: SelectRequest)
  World(request: WorldRequest)
  Move(request: MoveRequest)
  Items(request: ItemsRequest)
}

/// What world entry asks the store.
pub type WorldRequest {
  /// The account's character with this id, with its saved place, taken by this
  /// login: the character's `session_epoch` is raised by one in the same
  /// statement and returned. The account's id is in the statement, so no other
  /// account's character is taken.
  LoadCharacter(account_id: AccountId, character_id: CharacterId)
}

/// What the player's movement asks the store.
pub type MoveRequest {
  /// Saves where the character stands, only while its `session_epoch` is still
  /// `session_epoch`, the one the login that saves was told when it loaded the
  /// character, and only when `save_sequence` is above the last one stored for
  /// that login. A login numbers its saves from 1, in the order it asks them,
  /// so a save that reaches the database after a newer one of its own changes
  /// nothing. The account's id is in the statement, as for a load. The
  /// character's `health` is written by the same statement: `Some` the health
  /// the player has, 0 while it is dead, and `None` when there is none to keep,
  /// which leaves nothing saved, so the next entry is alive at full health. A
  /// health the table refuses, below 0, is `HealthRefused`. The character's
  /// `experience` and the `level` it makes are written by the same statement, so
  /// the two stand together after a camp and a new login; an experience the
  /// table refuses, below 0, is `ExperienceRefused`. The character's quest log,
  /// `quests`, is the whole log: the same statement writes the rows
  /// that changed and deletes the rows it no longer holds, both under the same
  /// fence, so a refused save changes no quest row. A row a check of the
  /// character_quest table refuses is `QuestLogRefused`, which no log the rule
  /// keeps breaks.
  SavePlace(
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    save_sequence: Int,
    place: Place,
    health: Option(Int),
    experience: Int,
    level: Int,
    quests: List(QuestRow),
  )
}

/// A place in the character's held items: the client's location (0 equipped, 1
/// inventory, 2 bank) and the slot in it, as `HeldItem` keeps them.
pub type ItemPlace {
  ItemPlace(location: Int, bag_index: Int)
}

/// One item's move: the item `item_guid`, held at `from`, goes to `to`. A swap is
/// two moves, each item to the other's place.
pub type ItemMove {
  ItemMove(item_guid: Int, from: ItemPlace, to: ItemPlace)
}

/// What the player's items ask the store. Each request changes the character's
/// item rows in one statement, only while the character's `session_epoch` is
/// still `session_epoch`, the one the login that asks was told when it loaded the
/// character, and only when each row it names is as the request holds it (its
/// guid, place and count). The account's id is in the statement, as for a load.
pub type ItemsRequest {
  /// Moves the character's items, all or none, only when each item is at the
  /// place its move leaves. The statement is one UPDATE under the character_item
  /// table's deferrable unique key, so the moves of a swap pass it together.
  MoveItems(
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    moves: List(ItemMove),
  )
  /// Takes `count` off the stack `source` and makes a new stack of them at `to`,
  /// which holds no item: one statement that lowers the source's count and
  /// inserts the new row, answered by `ItemMade` with the new row's guid.
  SplitItem(
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    source: HeldItem,
    count: Int,
    to: ItemPlace,
  )
  /// Puts `count` of the stack `source` onto the stack `target`, of the same
  /// Item2: one statement that adds them to the target and takes them off the
  /// source, deleting the source when none are left.
  MergeItems(
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    source: HeldItem,
    target: HeldItem,
    count: Int,
  )
  /// Destroys the whole stack `item`: one statement that deletes its row.
  DeleteItem(
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    item: HeldItem,
  )
  /// A purchase from a vendor, all or none, only while the character holds exactly
  /// `credits_held` credits (the total the connection holds) and at least `cost`: one
  /// statement that takes `cost` off the credits, raises each stack of `grow` from
  /// its `held_count` to its `new_count`, and inserts a stack of the Item2 `item2_id`
  /// for each of `make`. Answered by `Bought` with the credits left and the rows made.
  BuyFromVendor(
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    credits_held: Int,
    cost: Int,
    grow: List(StackGrowth),
    make: List(NewStack),
    item2_id: Item2Id,
  )
  /// A sale to a vendor, all or none, only while the character holds exactly
  /// `credits_held` credits (the total the connection holds) and each stack of
  /// `sold` is held with its `held_count` at an inventory bag place: one statement
  /// that sets the credits to `credits_after`, deletes each stack sold whole and
  /// lowers each stack sold in part. Answered by `Sold` with the credits held after.
  SellToVendor(
    account_id: AccountId,
    character_id: CharacterId,
    session_epoch: SessionEpoch,
    credits_held: Int,
    credits_after: Int,
    sold: List(SoldStack),
  )
}

/// A held stack a sale sells from: the item `item_guid`, held with `held_count`,
/// has `sold_count` of its items sold; all of them when the two are equal.
pub type SoldStack {
  SoldStack(item_guid: Int, held_count: Int, sold_count: Int)
}

/// A held stack that a purchase fills: the item `item_guid`, held with `held_count`,
/// holds `new_count` after the purchase.
pub type StackGrowth {
  StackGrowth(item_guid: Int, held_count: Int, new_count: Int)
}

/// A stack a purchase makes, at a place that holds no item: the place and the count
/// of the new row, whose Item2 is the request's.
pub type NewStack {
  NewStack(location: Int, bag_index: Int, stack_count: Int)
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
  /// `character_slots` characters, and stores its `starting_items` in the same
  /// transaction, so a refused create leaves no item. The name must be a full
  /// name by the client's text rule 0 and unique ignoring case, and the
  /// account's creates run one at a time, all held by the database.
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
  /// must be a full name by the client's text rule 0 and unique ignoring case,
  /// held by the database.
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
  /// The database could not be reached, or a read waited longer than its
  /// query's timeout for a connection (pog's query timeout bounds that wait,
  /// not the query's run). A list changed nothing, and a load raised the
  /// epoch at most once more than the asker learned, so asking again is safe;
  /// a save that did not run leaves the place saved before it. A
  /// create's statements run on the one connection its transaction holds and
  /// have no query timeout: the asker's deadline bounds them. A create ran in
  /// one transaction, which committed or did not, and the account's list on its
  /// next login shows which.
  Unavailable
  ForLogin(answer: FindAccountAnswer)
  ForSelect(answer: SelectAnswer)
  ForWorld(answer: WorldAnswer)
  ForMove(answer: MoveAnswer)
  ForItems(answer: ItemsAnswer)
}

/// What the store answers world entry.
pub type WorldAnswer {
  /// The account's character, taken by this login, whose `session_epoch` is
  /// `session_epoch` after the raise, the health its last save kept
  /// (`saved_health`: `None` when none was saved), the experience its last save
  /// or its creation kept (`saved_experience`: `None` when none was saved, which
  /// enters at the least experience of its level) and the items it holds, by
  /// location then bag index (none for a character with no stored items) and
  /// the rows of its quest log, in quest id order (none for a character with no
  /// quest) and the currencies it holds, by type (none for a character that holds
  /// none). The rows are read in the transaction that raised the epoch, so no
  /// delete lands between them. Asking again takes the character again and raises
  /// it again.
  CharacterLoaded(
    character: Character,
    session_epoch: SessionEpoch,
    saved_health: Option(Int),
    saved_experience: Option(Int),
    items: List(HeldItem),
    quests: List(QuestRow),
    currencies: List(HeldCurrency),
  )
  /// The account has no character with the id.
  NotTheAccounts
}

/// What the store answers the player's movement.
pub type MoveAnswer {
  /// The place was saved: the character's `session_epoch` was the save's.
  PlaceSaved
  /// Nothing was saved, for one of three causes the statement cannot tell
  /// apart: a later login raised the character's `session_epoch` past the
  /// save's, a newer save of the same login was stored first, or the account
  /// has no such character.
  NothingSaved
  /// The database refused the place for the check constraint of this name,
  /// which no place the rule keeps breaks: a bug of the server's, so nothing
  /// was saved.
  PlaceRefused(constraint: String)
  /// The database refused a quest row of the log for the check constraint of this
  /// name, which no log the rule keeps breaks: a bug of the server's, so nothing
  /// was saved, neither the quest rows nor the place beside them.
  QuestLogRefused(constraint: String)
  /// The database refused the health (`character_health_is_not_negative`),
  /// which the rule never asks to keep below 0: a bug of the server's, so
  /// nothing was saved, neither the health nor the place beside it.
  HealthRefused
  /// The database refused the experience (`character_experience_is_not_negative`),
  /// which the rule never asks to keep below 0: a bug of the server's, so
  /// nothing was saved, neither the experience nor the place beside it.
  ExperienceRefused
}

/// What the store answers the player's items.
pub type ItemsAnswer {
  /// Every row the request changes is changed: the character's `session_epoch`
  /// was the request's and each row was as the request held it.
  ItemsSaved
  /// A split's rows are saved, the new stack's row having this guid, the
  /// database's identity for it.
  ItemMade(item_guid: Int)
  /// A purchase's rows are saved: `credits` is what the character holds after the
  /// cost was taken, and `made` the new stacks, each with the guid the database gave
  /// it.
  Bought(credits: Int, made: List(HeldItem))
  /// A sale's rows are saved: `credits` is what the character holds after it.
  Sold(credits: Int)
  /// Nothing was saved, for one of three causes the statement cannot tell apart:
  /// a later login raised the character's `session_epoch` past the request's, a
  /// row was not as the request held it, or the account has no such character.
  ItemsNotSaved
  /// The database refused the change for the check constraint or unique key of
  /// this name, which no change the rule asks for breaks: a bug of the server's,
  /// so nothing was saved.
  SaveRefused(constraint: String)
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
  /// The name is no full name by the client's text rule 0, which the table's
  /// `character_name_follows_rule_0` holds; nothing was made.
  NameBreaksRule
  /// The account already has as many characters as its slots; nothing was
  /// made.
  NoFreeSlot
  /// The account has no row, so no character was made for it.
  CreateForNoSuchAccount
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
  /// The name is no full name by the client's text rule 0, which the table's
  /// `character_name_follows_rule_0` holds; nothing changed, and the character
  /// is still marked.
  NewNameBreaksRule
  /// The account has no such character, or it is not marked; nothing changed.
  NotRenamable
}
