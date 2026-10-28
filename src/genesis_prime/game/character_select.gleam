//// Character select, the first thing a game connection does once its session
//// key is taken: the account's character list the client shows. It has its
//// own state and effects, which the game connection's rule
//// (genesis_prime/game/connection) holds one field of and turns into its own
//// effects.
////
//// ```
//// game rule                              character select             effects
//// the client's 0x07E0, account known ─▶ started(state, account_id)
////                                                                   ─▶ AskCharacters(account)
//// the store's rows                    ─▶ listed(state, ..)
////                                                                   ─▶ Send(0x0117)
//// ```
////
//// - **The list.** 0x0117 carries the server's time, one entry per character
////   in creation order, the realm's id and `max_characters` from the settings,
////   and 0 in every field the client never reads or that no feature gives yet
////   (opcode.0x117, 0x14002167a, opcode.0x117.character_unread). The creation
////   id arrays are empty: the client then offers the CharacterCreation rows
////   its own `enabled` column sets (0x140021bb0). An entry holds each field
////   of the character's row; its two visual arrays and customisation values
////   are empty, since nothing writes an appearance yet, so the model may draw
////   dark.
//// - **What the client does with it.** It shows each character's name, level,
////   the Dominion frame for faction 166 and the Exile frame for any other, the
////   class icon for class 1 to 20 and the path icon for path 0 to 3, and
////   builds the model from race, gender and class; with no characters it shows
////   "no characters found" (lua.CharacterSelection.OnLoadFromCharacter.list).
//// - **No answer.** The client waits for 0x0117 with no timeout
////   (lua.Character.OnCharacterList), so the game connection ends the
////   connection when the store gives none; this module is given only rows.
//// - **A second 0x07E0.** It asks the store again and sends a new list.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/store.{type AccountId, type Character}

/// What a character select asks or sends; the game connection's rule turns
/// each into its own effect.
pub type Effect {
  /// Ask the store for the account's characters; its answer comes back to
  /// `listed`.
  AskCharacters(account_id: AccountId)
  /// Send this message to the client, in the game wrapper under the
  /// connection's current cipher.
  Send(frame: Frame)
}

/// Where character select is.
pub opaque type State {
  /// The client has not asked for the list.
  NotStarted
  /// The store is asked for the characters.
  Listing
  /// The list is sent.
  Listed
}

/// The state of a connection that has not entered character select.
pub fn new() -> State {
  todo as "the build follows the shape commit"
}

/// The client's 0x07E0 was read for this account: asks the store for its
/// characters.
pub fn started(
  state state: State,
  account_id account_id: AccountId,
) -> #(State, List(Effect)) {
  todo as "the build follows the shape commit"
}

/// The store's rows for the account: sends 0x0117 with one entry per
/// character, in the order given. `filetime` is the system time of the input
/// as a Windows FILETIME (genesis_prime/step), the server's time the client
/// keeps the difference from.
pub fn listed(
  state state: State,
  filetime filetime: Int,
  realm_id realm_id: Int,
  max_characters max_characters: Int,
  characters characters: List(Character),
) -> #(State, List(Effect)) {
  todo as "the build follows the shape commit"
}
