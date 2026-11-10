//// Character select, the first thing a game connection does once its session
//// key is taken: the account's character list the client shows, and creating
//// a character from it. It has its own state and effects, which the game
//// connection's rule (genesis_prime/game/connection) holds one field of and
//// turns into its own effects.
////
//// ```
//// game rule                              character select             effects
//// the client's 0x07E0, account known ─▶ started(account_id)
////                                                                   ─▶ Ask(ListCharacters(account))
//// the client's 0x025B, decoded       ─▶ create_requested(..)
////                                                                   ─▶ Ask(CreateCharacter(..))
////                                                                      or Send(0x00DC), refused
//// the client's 0x0352, decoded       ─▶ delete_requested(..)
////                                                                   ─▶ Ask(DeleteCharacter(..))
//// the client's 0x0786, decoded       ─▶ rename_requested(..)
////                                                                   ─▶ Ask(RenameCharacter(..))
////                                                                      or Send(0x014B), refused
//// world entry refuses a play        ─▶ play_refused(..)
////                                                                   ─▶ Send(0x0162), Ask(ListCharacters(account))
//// the store's answer                  ─▶ listed(..), created(..), deleted(..) or renamed(..)
////                                                                   ─▶ Send(0x097F), Send(0x0968), Send(0x0036), Send(0x0117)
////                                                                      or Send(0x00DC), Send(0x00E6) or Send(0x014B)
//// ```
////
//// - **The list.** 0x0036 carries the highest level among the account's
////   characters, 0 with none, and 0x0117 follows: the server's time, one entry
////   per character in creation order, the realm's id and `max_characters` from
////   the settings, and 0 in every field the client never reads or that no
////   feature gives yet (opcode.0x36, opcode.0x117, 0x14002167a,
////   opcode.0x117.character_unread). The creation id arrays are empty: the
////   client then offers the CharacterCreation rows its own `enabled` column
////   sets (0x140021bb0). An entry holds each field of the character's row,
////   its body visuals from its look (genesis_prime/game/appearance) and its
////   bone values as sent. Its worn visuals and costume are empty or 0: the
////   client never builds worn visuals from a creation row, and gear is the
////   inventory's (0x14004adb0, 0x140027380).
//// - **The slots.** The client counts its own slots: 2 from its reward
////   property, plus the count of the account's BaseCharacterSlots
////   entitlement (12) when it holds one
////   (lua.CharacterSelection.OnLoadFromCharacter). So the list is preceded by
////   0x097F with the premium tier 1 and 0x0968 with the one entry
////   (12, `character_slots` - 2), a count of 0 at 2 slots. The tier goes first:
////   0x0968 makes the client refresh its tier, which drops from 255 to 0
////   (Basic) unless 0x097F set it, and tier 1 keeps the Signature the client
////   shows today (opcode.0x968, opcode.0x97f,
////   lua.AccountItemLib.GetPremiumTier.users). The server never reads the
////   gmode the client sends in 0x0592, so it sends the same to a client of the
////   VIP system, whose base is 3: that client offers one slot more than the
////   refusal of a create allows.
//// - **What the client does with it.** It shows each character's name, level,
////   the Dominion frame for faction 166 and the Exile frame for any other, the
////   class icon for class 1 to 20 and the path icon for path 0 to 3, and
////   builds the model from race, gender and class; with no characters it shows
////   "no characters found" (lua.CharacterSelection.OnLoadFromCharacter.list).
//// - **Create.** A request is checked (genesis_prime/game/character_creation)
////   and then the store makes the character; 0x00DC answers with the result:
////   CreateOk with the id, name length for a name the table's rule 0 refuses,
////   name unavailable, account full, or the result a refusal maps to, with 0
////   for the character and for the field the client never reads (opcode.0xdc,
////   opcode.0xdc.field_2). A request that fails the checks is refused at once
////   and the store is not asked.
//// - **Delete.** The store deletes the character only when the account has
////   it; 0x00E6 answers with result 0 and a value of 0, which the client reads
////   only for a guild leader's count, or with result 1 and a warning for a
////   character the account does not have. The client removes the character
////   from its own list and rebuilds it, so no 0x0117 follows
////   (opcode.0xe6, opcode.0xe6.value, lua.CharacterSelection.OnCharacterDeleteResult).
//// - **Rename.** The store renames the character when the account has it and it
////   is marked, and clears the mark. 0x014B answers 18 with the id and the stored
////   name, 15 for a name that fails rule 0, which the table refuses, 16 for a name
////   another character has in any case, and 13 with a
////   warning for a character that is not the account's or not marked
////   (opcode.0x14b, lua.CharacterSelection.OnCharacterRenameResult). A
////   character's entry carries the rename bit the client offers a rename by
////   (lua.CharacterSelection.OnSelectCharacter).
//// - **A play world entry refuses.** The client plays a character with 0x07DD
////   and waits for 0xAD or 0x162 with no timeout (genesis_prime/game/world_entry).
////   For a character the account does not have, or one with no saved place,
////   world entry hands back here: the server sends 0x0162 with Failed and the
////   list again, which closes the create screen and the refusal box together
////   (opcode.0x162.after_create). The list selects its character by the
////   client's own rule: the pending in-world character, else among the
////   characters with a last logout the one with the largest, else the first.
////   The character the request named is sent with a last logout of a moment
////   ago, and every other with 0, which is none, so it is the one selected
////   (lua.CharacterSelection.OnLoadFromCharacter.preselect, 0x1401e83a0).
//// - **Its asks and their answers are its own.** It asks the store itself and
////   takes each request's answer in the function of that request (`listed`,
////   `created`, `deleted`, `renamed`), which refuses an answer while no such ask is out. The game connection's rule holds the client's frames
////   while an ask is out (`waiting`), so a second request is taken only after
////   the answer to the first.
//// - **No answer.** The client waits for 0x0117 and for 0x00DC with no
////   timeout (lua.Character.OnCharacterList, opcode.0xdc), so the game
////   connection ends the connection, after telling the client, when an ask
////   every store ask shares fails (the store unavailable, not running, ended
////   or silent); this module is given only the answers its asks get.

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame, type FrameError, Frame}
import genesis_prime/game/appearance
import genesis_prime/game/character_creation
import genesis_prime/game/reward_property
import genesis_prime/game/start_place
import genesis_prime/game_settings
import genesis_prime/message/account_entitlements.{AccountEntitlements}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/character_list_entry.{
  type CharacterListEntry, CharacterListEntry,
}
import genesis_prime/message/character_select_start
import genesis_prime/message/create_character.{type CreateCharacter}
import genesis_prime/message/create_character_carrier
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/create_result.{type CreateResult}
import genesis_prime/message/delete_character.{type DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/delete_result.{type DeleteResult}
import genesis_prime/message/float32
import genesis_prime/message/held_entitlement.{HeldEntitlement}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/play_refusal
import genesis_prime/message/premium_tier.{PremiumTier}
import genesis_prime/message/rename_character.{type RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/rename_result.{type RenameResult}
import genesis_prime/store.{
  type AccountId, type Character, type CharacterId, CharacterId, NameStands,
  NeedsRename,
}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The last logout, in days from now, of the character the client should
/// select: a moment ago, which is not 0 (0 is none) and is above every logout
/// further back (lua.CharacterSelection.OnLoadFromCharacter.preselect,
/// 0x1401e83a0: negative for a past time).
const just_now_days = -0.000001

/// The Entitlement row of BaseCharacterSlots, whose count character select
/// adds to its slots (Entitlement.tbl row 12;
/// lua.CharacterSelection.OnLoadFromCharacter).
const base_character_slots_entitlement_id = 12

/// The client's messages character select takes, in the client's wrapper
/// (genesis_prime/game/routing's table says which id is which).
pub type Message {
  /// 0x07E0: the client starts character select and asks for its list.
  Started
  /// 0x025C, which carries a 0x025B create request.
  CreateAsked
  /// 0x0352, the request to delete a character.
  DeleteAsked
  /// 0x0786, the request to rename a character.
  RenameAsked
}

/// Why a message is refused: the client's own reader would refuse it, or the
/// client never writes it. The connection ends.
pub type Refusal {
  /// A body the client's reader would refuse.
  NotDecoded(undecoded: client_connection.Undecoded)
  /// A 0x025C that holds no whole frame.
  CarrierHoldsNoFrame(error: FrameError)
  /// A 0x025C that holds another message than 0x025B.
  CarrierHolds(message_id: Int)
}

/// What a character select asks or sends; the game connection's rule turns
/// each into its own effect.
pub type Effect {
  /// Ask the store; its answer comes back to the function of that request.
  Ask(request: store.SelectRequest)
  /// Send this message to the client, in the game wrapper under the
  /// connection's current cipher.
  Send(frame: Frame)
  /// Log this as a warning: a request the real client would not send.
  Warn(text: String)
}

/// Where character select is.
pub opaque type State {
  /// No ask is out.
  Resting
  /// The store is asked for the characters, and the list selects the character
  /// named, if any.
  Listing(selected: Option(CharacterId))
  /// The store is asked to make a character.
  Creating
  /// The store is asked to delete the character with this id.
  Deleting(character_id: Int)
  /// The store is asked to rename the character with this id, which the
  /// answer's result names back to the client.
  Renaming(character_id: Int, name: String)
}

/// The state of a connection that has not entered character select.
pub fn new() -> State {
  Resting
}

/// Whether the store's answer is awaited.
pub fn waiting(state state: State) -> Bool {
  case state {
    Listing(..) | Creating | Deleting(..) | Renaming(..) -> True
    Resting -> False
  }
}

/// What one message of the client's does, for this account: its body is
/// decoded and the function of that request decides. 0x025C holds the whole
/// frame of a 0x025B (opcode.0x25c). A body the client's reader would refuse, or
/// a 0x025C with no 0x025B in it, is the refusal that ends the connection.
pub fn take(
  message message: Message,
  account_id account_id: AccountId,
  body body: BitArray,
  tables tables: table_store.Tables,
  character_slots character_slots: Int,
  starting_credits starting_credits: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  case message {
    Started ->
      character_select_start.decode(body)
      |> client_connection.decoded(
        message_id: character_select_start.message_id,
      )
      |> result.map_error(NotDecoded)
      |> result.map(fn(_) { started(account_id:) })
    CreateAsked -> {
      use carrier <- result.try(
        create_character_carrier.decode(body)
        |> client_connection.decoded(
          message_id: create_character_carrier.message_id,
        )
        |> result.map_error(NotDecoded),
      )
      use whole <- result.try(
        frame.parse(carrier.inner_frame)
        |> result.map_error(CarrierHoldsNoFrame),
      )
      use <- bool.guard(
        whole.message_id != create_character.message_id,
        Error(CarrierHolds(message_id: whole.message_id)),
      )
      use request <- result.map(
        create_character.decode(whole.body)
        |> client_connection.decoded(message_id: create_character.message_id)
        |> result.map_error(NotDecoded),
      )
      create_requested(
        account_id:,
        request:,
        tables:,
        character_slots:,
        starting_credits:,
      )
    }
    DeleteAsked ->
      delete_character.decode(body)
      |> client_connection.decoded(message_id: delete_character.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) { delete_requested(account_id:, request:) })
    RenameAsked ->
      rename_character.decode(body)
      |> client_connection.decoded(message_id: rename_character.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) { rename_requested(account_id:, request:) })
  }
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    CarrierHoldsNoFrame(error:) ->
      "0x025C holds no whole frame: " <> frame.describe(error)
    CarrierHolds(message_id:) ->
      "0x025C holds "
      <> client_connection.message_text(message_id:)
      <> ", not 0x025B"
  }
}

/// The client's 0x07E0 was read for this account: asks the store for its
/// characters, whatever came before.
pub fn started(account_id account_id: AccountId) -> #(State, List(Effect)) {
  #(Listing(selected: None), [
    Ask(request: store.ListCharacters(account_id:)),
  ])
}

/// The client's create request, read for this account: refused at once with
/// 0x00DC when it fails the checks against the client's tables, else the store
/// is asked to make the character, for an account with `character_slots` slots.
/// The name's rule 0 is the table's, so a name that breaks it is the store's to
/// refuse.
pub fn create_requested(
  account_id account_id: AccountId,
  request request: CreateCharacter,
  tables tables: table_store.Tables,
  character_slots character_slots: Int,
  starting_credits starting_credits: Int,
) -> #(State, List(Effect)) {
  case character_creation.check(tables:, request:, starting_credits:) {
    Ok(character) -> #(Creating, [
      Ask(request: store.CreateCharacter(
        account_id:,
        character:,
        character_slots:,
      )),
    ])
    Error(refusal) -> #(Resting, [
      Warn(text: character_creation.describe(refusal)),
      create_result(
        character_id: 0,
        result: character_creation.result_of(refusal),
      ),
    ])
  }
}

/// World entry refused the client's request to play the character with this
/// id: 0x0162 with Failed, and the list is asked for again with that character
/// selected.
pub fn play_refused(
  account_id account_id: AccountId,
  character_id character_id: Int,
) -> #(State, List(Effect)) {
  let assert Ok(body) =
    play_character_refused.encode(PlayCharacterRefused(
      result: play_refusal.Failed,
    ))
    as "a refusal's value fits its field"
  #(Listing(selected: Some(CharacterId(character_id))), [
    Send(frame: Frame(message_id: play_character_refused.message_id, body:)),
    Ask(request: store.ListCharacters(account_id:)),
  ])
}

/// The client's request to delete a character, read for this account: the
/// store is asked to delete it, which it does only for a character the account
/// has.
pub fn delete_requested(
  account_id account_id: AccountId,
  request request: DeleteCharacter,
) -> #(State, List(Effect)) {
  #(Deleting(character_id: request.character_id), [
    Ask(request: store.DeleteCharacter(
      account_id:,
      character_id: CharacterId(request.character_id),
    )),
  ])
}

/// The client's request to rename a character, read for this account: the store
/// is asked to rename the character. The name's rule 0 is the table's, so a name
/// that breaks it is the store's to refuse.
pub fn rename_requested(
  account_id account_id: AccountId,
  request request: RenameCharacter,
) -> #(State, List(Effect)) {
  #(Renaming(character_id: request.character_id, name: request.name), [
    Ask(request: store.RenameCharacter(
      account_id:,
      character_id: CharacterId(request.character_id),
      name: request.name,
    )),
  ])
}

/// The store's answer to the ask for the characters: sends 0x097F and 0x0968,
/// which give the client `character_slots` slots as its sum of 2 and an
/// entitlement count, then 0x0036 and 0x0117 with one entry per character, in
/// the order given. With no list asked for,
/// it is none this module asked for and gives an `Error`. `filetime` is the
/// system time of the input as a Windows FILETIME (genesis_prime/step), the
/// server's time the client keeps the difference from.
pub fn listed(
  state state: State,
  characters characters: List(Character),
  filetime filetime: Int,
  realm_id realm_id: Int,
  max_characters max_characters: Int,
  character_slots character_slots: Int,
  tables tables: table_store.Tables,
) -> Result(#(State, List(Effect)), Nil) {
  case state {
    Listing(selected:) ->
      Ok(#(
        Resting,
        list.append(
          slot_effects(character_slots:),
          list_effects(
            characters:,
            selected:,
            filetime:,
            realm_id:,
            max_characters:,
            tables:,
          ),
        ),
      ))
    Resting | Creating | Deleting(..) | Renaming(..) -> Error(Nil)
  }
}

/// The store's answer to the ask to make a character: sends 0x00DC with the
/// result. With no create asked for, it is none this module asked for and
/// gives an `Error`.
pub fn created(
  state state: State,
  answer answer: store.CreateAnswer,
) -> Result(#(State, List(Effect)), Nil) {
  case state {
    Creating ->
      Ok(case answer {
        store.CharacterCreated(character_id: CharacterId(character_id)) ->
          created_with(character_id:, result: create_result.CreateOk)
        store.NameTaken ->
          created_with(character_id: 0, result: create_result.NameUnavailable)
        store.NameBreaksRule ->
          created_with(character_id: 0, result: create_result.NameLength)
        store.NoFreeSlot ->
          created_with(character_id: 0, result: create_result.AccountFull)
        store.CreateForNoSuchAccount -> #(Resting, [
          Warn(text: "a create for an account the store has no row for"),
          create_result(character_id: 0, result: create_result.CreateFailed),
        ])
      })
    Resting | Listing(..) | Deleting(..) | Renaming(..) -> Error(Nil)
  }
}

/// The store's answer to the ask to delete a character: sends 0x00E6 with the
/// result. The client removes the character from its own list on result 0 and
/// rebuilds the list, so no 0x0117 follows. For a character the account does
/// not have the result is 1, and a warning says so, since the real client
/// deletes only a character of its list. With no delete asked for, it is none
/// this module asked for and gives an `Error`.
pub fn deleted(
  state state: State,
  answer answer: store.DeleteAnswer,
) -> Result(#(State, List(Effect)), Nil) {
  case state {
    Deleting(character_id:) -> {
      let #(warning, result) = case answer {
        store.CharacterDeleted -> #([], delete_result.DeleteOk)
        store.NoSuchCharacter -> #(
          [
            Warn(
              text: "a delete of character "
              <> int.to_string(character_id)
              <> ", which the account does not have",
            ),
          ],
          delete_result.DeleteFailed,
        )
      }
      Ok(#(Resting, list.append(warning, [delete_result(result:)])))
    }
    Resting | Listing(..) | Creating | Renaming(..) -> Error(Nil)
  }
}

/// The store's answer to the ask to rename a character: sends 0x014B with the
/// result, the character's id and the name: the stored one for result 18,
/// which the client gives the listed character, else the request's. A
/// character the account does not have or that is not marked is 13 with a
/// warning, since the real client offers a rename only for a marked character
/// of its list. With no rename asked for, it is none this module asked for and
/// gives an `Error`.
pub fn renamed(
  state state: State,
  answer answer: store.RenameAnswer,
) -> Result(#(State, List(Effect)), Nil) {
  case state {
    Renaming(character_id:, name: asked) -> {
      let #(warning, name, result) = case answer {
        store.CharacterRenamed(name: stored) -> #(
          [],
          stored,
          rename_result.RenameOk,
        )
        store.NewNameTaken -> #([], asked, rename_result.NameUnavailable)
        store.NewNameBreaksRule -> #([], asked, rename_result.NameLength)
        store.NotRenamable -> #(
          [
            Warn(
              text: "a rename of character "
              <> int.to_string(character_id)
              <> ", which the account does not have or which is not marked",
            ),
          ],
          asked,
          rename_result.RenameFailed,
        )
      }
      Ok(#(
        Resting,
        list.append(warning, [rename_result(character_id:, name:, result:)]),
      ))
    }
    Resting | Listing(..) | Creating | Deleting(..) -> Error(Nil)
  }
}

/// The transition a create's answer makes: the create is done, and 0x00DC
/// tells the client the result.
fn created_with(
  character_id character_id: Int,
  result result: CreateResult,
) -> #(State, List(Effect)) {
  #(Resting, [create_result(character_id:, result:)])
}

/// 0x00DC with the character's id (0 for none) and the result.
fn create_result(
  character_id character_id: Int,
  result result: CreateResult,
) -> Effect {
  let assert Ok(body) =
    create_character_result.encode(CreateCharacterResult(
      character_id:,
      field_2: 0,
      result:,
    ))
    as "an id of the table's 64 bits and a result of 6 bits fit their fields"
  Send(frame: Frame(message_id: create_character_result.message_id, body:))
}

/// 0x00E6 with the result and 0 in the value, which the client reads only for
/// a guild leader's count (opcode.0xe6.value).
fn delete_result(result result: DeleteResult) -> Effect {
  let assert Ok(body) =
    delete_character_result.encode(DeleteCharacterResult(result:, value: 0))
    as "a result of 6 bits and a value of 32 bits fit their fields"
  Send(frame: Frame(message_id: delete_character_result.message_id, body:))
}

/// 0x014B with the result, the character's id and the name.
fn rename_result(
  character_id character_id: Int,
  name name: String,
  result result: RenameResult,
) -> Effect {
  let assert Ok(body) =
    rename_character_result.encode(RenameCharacterResult(
      result:,
      character_id:,
      name:,
    ))
    as "an id of 64 bits, a result of 6 bits and a name the client or the store gave fit their fields"
  Send(frame: Frame(message_id: rename_character_result.message_id, body:))
}

/// 0x097F with the premium tier and 0x0968 with the BaseCharacterSlots
/// entitlement that raises the client's own 2 slots to `character_slots`. The
/// entry is sent at 2 slots too, with a count of 0, which the client counts as
/// absent (0x1404e4960): 0x0968 sets only the entries it lists, so a count
/// the client still holds from an earlier list is overwritten
/// (SetAccountEntitlement 0x1400062c0).
fn slot_effects(character_slots character_slots: Int) -> List(Effect) {
  let assert Ok(tier) =
    premium_tier.encode(PremiumTier(tier: reward_property.signature_tier))
    as "a tier of 1 fits its 5 bits"
  let assert Ok(entitlements) =
    account_entitlements.encode(
      AccountEntitlements(entitlements: [
        HeldEntitlement(
          entitlement_id: base_character_slots_entitlement_id,
          count: character_slots - game_settings.client_base_character_slots,
        ),
      ]),
    )
    as "an entitlement id and a count of the settings' range fit their 32 bits"
  [
    Send(frame: Frame(message_id: premium_tier.message_id, body: tier)),
    Send(frame: Frame(
      message_id: account_entitlements.message_id,
      body: entitlements,
    )),
  ]
}

/// 0x0036 with the highest level and 0x0117 with the list.
fn list_effects(
  characters characters: List(Character),
  selected selected: Option(CharacterId),
  filetime filetime: Int,
  realm_id realm_id: Int,
  max_characters max_characters: Int,
  tables tables: table_store.Tables,
) -> List(Effect) {
  let assert Ok(level) =
    max_character_level.encode(
      MaxCharacterLevel(
        highest_level: list.fold(characters, 0, fn(highest, character) {
          int.max(highest, character.level)
        }),
      ),
    )
    as "a level of the table's checks fits its 32 bits"
  let index = appearance.index(tables:)
  let assert Ok(body) =
    character_list.encode(CharacterList(
      server_time: filetime,
      characters: list.map(characters, fn(character) {
        entry(character:, selected:, index:)
      }),
      enabled_creation_ids: [],
      disabled_creation_ids: [],
      realm_id:,
      in_world_realm_id: 0,
      in_world_character_id: 0,
      in_world_logoff_ms: 0,
      reservations: 0,
      max_characters:,
      field_11: 0,
      faction_restriction: 0,
      free_level_50_available: 0,
    ))
    as "the list's values fit their fields: the table's checks hold each row's"
  [
    Send(frame: Frame(message_id: max_character_level.message_id, body: level)),
    Send(frame: Frame(message_id: character_list.message_id, body:)),
  ]
}

/// One character as its entry in the list: each field of the row, the body
/// visuals of its look, no disabled flag, its rename bit from its naming, 0 in the three fields the
/// client never reads, no worn visuals and no costume slot (a mask of 0 and no
/// items or dyes), and its bone values; a last logout only for the selected
/// character.
fn entry(
  character character: Character,
  selected selected: Option(CharacterId),
  index index: appearance.Index,
) -> CharacterListEntry {
  let CharacterId(character_id) = character.character_id
  let #(world_id, world_zone_id, position_x, position_y, position_z) = case
    character.place
  {
    Some(place) -> #(
      start_place.world_id(place),
      start_place.world_zone_id(place),
      float32.to_bits(start_place.x(place)),
      float32.to_bits(start_place.y(place)),
      float32.to_bits(start_place.z(place)),
    )
    None -> #(0, 0, 0, 0, 0)
  }
  CharacterListEntry(
    character_id:,
    name: character.name,
    gender: character.gender,
    race_id: character.race_id.value,
    class_id: character.class_id.value,
    faction_id: character.faction_id,
    level: character.level,
    body_visuals: appearance.character_body_visuals(index:, character:),
    worn_visuals: [],
    world_id:,
    world_zone_id:,
    field_12: 0,
    position_x:,
    position_y:,
    position_z:,
    field_16: 0,
    field_17: 0,
    path: character.path,
    disabled: 0,
    requires_rename: case character.naming {
      NeedsRename -> 1
      NameStands -> 0
    },
    costume_slot_mask: 0,
    costume_item_ids: [],
    costume_dyes: [],
    bone_values: character.bones,
    last_logged_out_days: case selected == Some(character.character_id) {
      True -> float32.to_bits(just_now_days)
      False -> 0
    },
  )
}
