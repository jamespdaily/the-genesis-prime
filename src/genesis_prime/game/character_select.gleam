//// Character select, the first thing a game connection does once its session
//// key is taken: the account's character list the client shows. It has its
//// own state and effects, which the game connection's rule
//// (genesis_prime/game/connection) holds one field of and turns into its own
//// effects.
////
//// ```
//// game rule                              character select             effects
//// the client's 0x07E0, account known ─▶ started(account_id)
////                                                                   ─▶ Ask(ListCharacters(account))
//// the store's answer                  ─▶ answered(state, answer, ..)
////                                                                   ─▶ Send(0x0117)
//// ```
////
//// - **The list.** 0x0117 carries the server's time, one entry per character
////   in creation order, the realm's id and `max_characters` from the settings,
////   and 0 in every field the client never reads or that no feature gives yet
////   (opcode.0x117, 0x14002167a, opcode.0x117.character_unread). The creation
////   id arrays are empty: the client then offers the CharacterCreation rows
////   its own `enabled` column sets (0x140021bb0). An entry holds each field
////   of the character's row. Its two visual lists, costume slot mask,
////   costume item ids and costume dyes are empty or 0, since no character has
////   an appearance stored, so the client dresses its model in no costume slot
////   (0x140027380) and the model may draw dark.
//// - **What the client does with it.** It shows each character's name, level,
////   the Dominion frame for faction 166 and the Exile frame for any other, the
////   class icon for class 1 to 20 and the path icon for path 0 to 3, and
////   builds the model from race, gender and class; with no characters it shows
////   "no characters found" (lua.CharacterSelection.OnLoadFromCharacter.list).
//// - **Its asks and their answers are its own.** It asks the store itself and
////   takes the store's answer in `answered`, which refuses an answer of a kind
////   it did not ask for. The game connection's rule holds the client's frames
////   while an ask is out (`waiting`), so a second 0x07E0 is taken only after
////   the list is sent, and asks the store again.
//// - **No answer.** The client waits for 0x0117 with no timeout
////   (lua.Character.OnCharacterList), so the game connection ends the
////   connection, after telling the client, when an ask every store ask shares
////   fails (the store unavailable, not running, ended or silent); this module
////   is given only the answers a list gets.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/character_list_entry.{
  type CharacterListEntry, CharacterListEntry,
}
import genesis_prime/message/float32
import genesis_prime/store.{type AccountId, type Character, CharacterId}
import gleam/list

/// What a character select asks or sends; the game connection's rule turns
/// each into its own effect.
pub type Effect {
  /// Ask the store; its answer comes back to `answered`.
  Ask(request: store.Request)
  /// Send this message to the client, in the game wrapper under the
  /// connection's current cipher.
  Send(frame: Frame)
}

/// Where character select is.
pub opaque type State {
  /// No ask is out.
  Resting
  /// The store is asked for the characters.
  Asking
}

/// The state of a connection that has not entered character select.
pub fn new() -> State {
  Resting
}

/// Whether the store's answer is awaited.
pub fn waiting(state state: State) -> Bool {
  case state {
    Asking -> True
    Resting -> False
  }
}

/// The client's 0x07E0 was read for this account: asks the store for its
/// characters, whatever came before.
pub fn started(account_id account_id: AccountId) -> #(State, List(Effect)) {
  #(Asking, [Ask(request: store.ListCharacters(account_id:))])
}

/// The store's answer to an ask: for the characters, sends 0x0117 with one
/// entry per character, in the order given. Another answer, or any answer
/// while no ask is out, is none this module asked for and gives an `Error`.
/// `filetime` is the system time of the input as a Windows FILETIME
/// (genesis_prime/step), the server's time the client keeps the difference
/// from.
pub fn answered(
  state state: State,
  answer answer: store.Answer,
  filetime filetime: Int,
  realm_id realm_id: Int,
  max_characters max_characters: Int,
) -> Result(#(State, List(Effect)), Nil) {
  case state, answer {
    Asking, store.Characters(characters:) -> {
      let assert Ok(body) =
        character_list.encode(CharacterList(
          server_time: filetime,
          characters: list.map(characters, entry),
          enabled_creation_ids: [],
          disabled_creation_ids: [],
          realm_id:,
          pending_removal_realm_id: 0,
          pending_removal_character_id: 0,
          pending_removal_time: 0,
          reservations: 0,
          max_characters:,
          field_11: 0,
          faction_restriction: 0,
          free_level_50_available: 0,
        ))
        as "the list's values fit their fields: the table's checks hold each row's"
      Ok(
        #(Resting, [Send(Frame(message_id: character_list.message_id, body:))]),
      )
    }
    Resting, _
    | Asking, store.Unavailable
    | Asking, store.AccountFound(..)
    | Asking, store.NoSuchAccount
    -> Error(Nil)
  }
}

/// One character as its entry in the list: each field of the row, no
/// disabled or rename flag, 0 in the three fields the client never reads, and
/// no costume slot (a mask of 0 and no items or dyes, 0x140027380) and no
/// bones, since no character has an appearance stored.
fn entry(character: Character) -> CharacterListEntry {
  let CharacterId(character_id) = character.character_id
  CharacterListEntry(
    character_id:,
    name: character.name,
    gender: character.gender,
    race_id: character.race_id,
    class_id: character.class_id,
    faction_id: character.faction_id,
    level: character.level,
    body_visuals: [],
    worn_visuals: [],
    world_id: character.world_id,
    world_zone_id: character.world_zone_id,
    field_12: 0,
    position_x: float32.to_bits(character.position_x),
    position_y: float32.to_bits(character.position_y),
    position_z: float32.to_bits(character.position_z),
    field_16: 0,
    field_17: 0,
    path: character.path,
    disabled: 0,
    requires_rename: 0,
    costume_slot_mask: 0,
    costume_item_ids: [],
    costume_dyes: [],
    bone_values: [],
    last_logged_out_days: 0,
  )
}
