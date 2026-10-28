//// Character select (`genesis_prime/game/character_select`), the feature the
//// game connection's rule holds one field of. Expected values are its doc
//// comment, as approved on the card, and these places.
//// - The create path: a request is checked, then the store is asked to make
////   the character, then 0x00DC answers with the result the store's answer
////   maps to (opcode.0xdc, lua.Character.OnCreateCharacterFailed: 3 CreateOk,
////   6 name unavailable, 9 account full, 10 name length, anything else "due to
////   an error").
//// - The play path after a create: 0x07DD gets 0x0162 Failed, then the list
////   again with 0x0036 before 0x0117 (opcode.0x162.after_create, opcode.0x36).
//// - The list: the character the client's own rule selects is the one with
////   the largest last-logout float among those that have one
////   (lua.CharacterSelection.OnLoadFromCharacter.preselect); 0 is none.
//// - The rows the tests build, and the real CharacterCustomization rows.
//// It asks the store itself and takes each request's answer in the function of
//// that request (`listed`, `created`), which refuses one while no such ask is
//// out. A second 0x07E0 while the
//// store is asked is the game connection's to hold, with the client's other
//// frames (test/game_connection_test.gleam).

import character_support
import character_tables
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/character_select.{Ask, Send, Warn}
import genesis_prime/message/character_list
import genesis_prime/message/character_list_entry.{type CharacterListEntry}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/create_result
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/delete_result
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/play_refusal
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/rename_result
import genesis_prime/store.{
  type Character, AccountId, Character, CharacterCreated, CharacterDeleted,
  CharacterId, CharacterRenamed, CreateCharacter as StoreCreate,
  DeleteCharacter as StoreDelete, ListCharacters, LookEntry, NameStands,
  NameTaken, NeedsRename, NewCharacter, NewNameTaken, NoFreeSlot,
  NoSuchCharacter, NotRenamable, RenameCharacter as StoreRename,
}
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import gleam/list
import gleam/string
import owned_test

const filetime = 133_900_000_000_000_000

fn listed(
  state: character_select.State,
  characters: List(Character),
) -> Result(#(character_select.State, List(character_select.Effect)), Nil) {
  character_select.listed(
    state,
    characters,
    filetime:,
    realm_id: 1,
    max_characters: 2,
    tables: character_tables.shared(),
  )
}

/// A stored character of the account with the given id, name and level; race
/// 1, sex 0 (a human male), class 1, faction 166, no look and no bones.
fn stored(id id: Int, name name: String, level level: Int) -> Character {
  Character(
    character_id: CharacterId(id),
    name:,
    gender: 0,
    race_id: RaceId(1),
    class_id: ClassId(1),
    faction_id: 166,
    level:,
    path: 0,
    world_id: 0,
    world_zone_id: 0,
    position_x: 0.0,
    position_y: 0.0,
    position_z: 0.0,
    look: [],
    bones: [],
    naming: NameStands,
  )
}

/// What the effects send, as frames, in order.
fn sent(effects: List(character_select.Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(frame:) -> Ok(frame)
      Ask(..) | Warn(..) -> Error(Nil)
    }
  })
}

/// The one 0x00DC in the effects, decoded.
fn create_result_of(
  effects: List(character_select.Effect),
) -> create_character_result.CreateCharacterResult {
  character_support.create_result_in(sent(effects))
}

/// A create request for CharacterCreation row 466 with a path of 1 and the
/// look of labels 2 and 22.
fn a_request(name: String) -> create_character.CreateCharacter {
  CreateCharacter(
    ..character_support.create_request(name),
    path: 1,
    customisation_labels: [2, 22],
    customisation_values: [1, 1],
  )
}

fn create(
  request: create_character.CreateCharacter,
) -> #(character_select.State, List(character_select.Effect)) {
  character_select.create_requested(
    account_id: AccountId(7),
    request:,
    tables: character_tables.shared(),
    character_slots: 2,
  )
}

fn delete(
  character_id: Int,
) -> #(character_select.State, List(character_select.Effect)) {
  character_select.delete_requested(
    account_id: AccountId(7),
    request: DeleteCharacter(character_id:),
  )
}

fn rename(
  character_id: Int,
  name: String,
) -> #(character_select.State, List(character_select.Effect)) {
  character_select.rename_requested(
    account_id: AccountId(7),
    request: RenameCharacter(character_id:, name:),
  )
}

// ---- the list ----

pub fn the_clients_0x07e0_asks_the_store_for_the_accounts_characters_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) = character_select.started(AccountId(7))
  assert effects == [Ask(request: ListCharacters(account_id: AccountId(7)))]
  assert character_select.waiting(state)
    as "the store's answer is awaited, so the game connection holds the client's frames"
}

pub fn an_answer_that_comes_with_no_ask_of_its_kind_out_is_none_character_select_takes_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = character_select.started(AccountId(7))
  assert character_select.created(
      asking,
      CharacterCreated(character_id: CharacterId(1)),
    )
    == Error(Nil)
    as "a create's answer is none a list ask gets"
  assert listed(character_select.new(), []) == Error(Nil)
    as "rows nobody asked for"
  let assert Ok(#(state, _)) = listed(asking, [])
  assert !character_select.waiting(state) as "the list is sent"
  assert listed(state, []) == Error(Nil) as "one ask has one answer"
  let #(creating, _) = create(a_request("Ab Cd"))
  assert listed(creating, []) == Error(Nil)
    as "a list is none a create ask gets"
}

pub fn a_list_is_0x0036_with_the_accounts_highest_level_and_then_0x0117_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) =
    listed(asking, [
      stored(id: 1, name: "Ab Cd", level: 12),
      stored(id: 2, name: "Ef Gh", level: 50),
      stored(id: 3, name: "Ij Kl", level: 3),
    ])
  let assert [
    Frame(message_id: 0x0036, body: level),
    Frame(message_id: 0x0117, ..),
  ] = sent(effects)
    as "opcode.0x36: the highest level goes to the client before the list it builds the creation choices from (0x140021bb0)"
  assert max_character_level.decode(level) == Ok(MaxCharacterLevel(50))
    as "opcode.0x36: the highest character level the account has reached, here 50"
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) = listed(asking, [])
  let assert [
    Frame(message_id: 0x0036, body: none),
    Frame(message_id: 0x0117, ..),
  ] = sent(effects)
  assert max_character_level.decode(none) == Ok(MaxCharacterLevel(0))
    as "opcode.0x36: an account with no characters has reached level 0, so the Veteran start stays disabled (0x1400266f0)"
}

pub fn a_list_built_from_0x07e0_selects_no_character_by_its_logout_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) =
    listed(asking, [
      stored(id: 1, name: "Ab Cd", level: 1),
      stored(id: 2, name: "Ef Gh", level: 1),
    ])
  assert list.map(entries(effects), fn(entry) { entry.last_logged_out_days })
    == [0, 0]
    as "lua.CharacterSelection.OnLoadFromCharacter.preselect: a character sent with 0 has no last logout, so the client selects the first in the list"
}

// ---- the entry's appearance ----

pub fn an_entry_carries_the_body_visuals_of_its_look_and_its_bones_test() -> Nil {
  use <- owned_test.run(60_000)
  let character =
    Character(
      ..stored(id: 1, name: "Ab Cd", level: 1),
      look: [
        LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
        LookEntry(label: CharacterCustomizationLabelId(21), value: 2),
      ],
      bones: [0x3F800000, 0x40000000],
      naming: NameStands,
    )
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) = listed(asking, [character])
  let assert [entry] = entries(effects)
  assert list.contains(
    entry.body_visuals,
    ItemVisual(slot: 25, display_id: 137, item_color_set_id: 0, dye: 0),
  )
    as "CharacterCustomization row 10 (race 1, sex 0, slot 25, labels 21 = 2 and 2 = 1, display 137): a Dominion human male with that look has display 137 on BodyFace"
  assert entry.worn_visuals == []
    as "0x14004adb0: the client never builds worn visuals from the creation row; gear comes with the inventory in world entry"
  assert entry.bone_values == [0x3F800000, 0x40000000]
    as "opcode.0x25b: the bone values the client sent come back as they were"
  assert entry.costume_slot_mask == 0
    && entry.costume_item_ids == []
    && entry.costume_dyes == []
    as "0x140027380: no costume"
}

// ---- create ----

pub fn a_valid_request_asks_the_store_to_make_the_character_with_the_slot_count_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) = create(a_request("Ab Cd"))
  assert effects
    == [
      Ask(request: StoreCreate(
        account_id: AccountId(7),
        character: NewCharacter(
          name: "Ab Cd",
          gender: 1,
          race_id: RaceId(1),
          class_id: ClassId(1),
          faction_id: 167,
          path: 1,
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(label: CharacterCustomizationLabelId(22), value: 1),
          ],
          bones: character_support.bones(46),
        ),
        character_slots: 2,
      )),
    ]
    as "CharacterCreation row 466 gives class 1, race 1, sex 1 and faction 167; the request gives the name, path, look and bones; the slot count is the account's (lua.CharacterSelection.OnLoadFromCharacter: 2 without an entitlement)"
  assert character_select.waiting(state) as "the store's answer is awaited"
}

pub fn the_stores_answer_to_a_create_becomes_the_result_the_client_shows_test() -> Nil {
  use <- owned_test.run(60_000)
  let result_for = fn(answer) {
    let #(asking, _) = create(a_request("Ab Cd"))
    let assert Ok(#(state, effects)) = character_select.created(asking, answer)
    assert !character_select.waiting(state) as "the result is sent"
    create_result_of(effects)
  }
  assert result_for(CharacterCreated(character_id: CharacterId(0x1_0000_0001)))
    == CreateCharacterResult(
      character_id: 0x1_0000_0001,
      field_2: 0,
      result: create_result.CreateOk,
    )
    as "opcode.0xdc: the new character's id, 0 in the field the client never reads (opcode.0xdc.field_2), and CreateOk"
  assert result_for(NameTaken)
    == CreateCharacterResult(
      character_id: 0,
      field_2: 0,
      result: create_result.NameUnavailable,
    )
    as "lua.Character.OnCreateCharacterFailed: 6, 'that name is not available'"
  assert result_for(NoFreeSlot)
    == CreateCharacterResult(
      character_id: 0,
      field_2: 0,
      result: create_result.AccountFull,
    )
    as "lua.Character.OnCreateCharacterFailed: 9, 'your account is full'"
}

pub fn a_name_that_breaks_rule_0_is_refused_with_name_length_and_the_store_is_not_asked_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) = create(a_request("Abcd"))
  assert create_result_of(effects).result == create_result.NameLength
    as "lua.Character.OnCreateCharacterFailed: 10"
  assert list.all(effects, fn(effect) {
    case effect {
      Ask(..) -> False
      Send(..) | Warn(..) -> True
    }
  })
    as "nothing is stored"
  assert !character_select.waiting(state)
}

pub fn a_request_the_client_would_not_send_is_refused_with_a_warning_naming_the_row_and_nothing_is_asked_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) =
    create(create_character.CreateCharacter(..a_request("Ab Cd"), path: 4))
  assert create_result_of(effects).result == create_result.CreateFailed
    as "lua.Character.OnCreateCharacterFailed: 4 is 'due to an error'"
  let assert [Warn(text:)] =
    list.filter(effects, fn(effect) {
      case effect {
        Warn(..) -> True
        Ask(..) | Send(..) -> False
      }
    })
    as "the refusal is logged once"
  assert string.contains(text, "466") as "the warning names the creation row"
  assert list.all(effects, fn(effect) {
    case effect {
      Ask(..) -> False
      Send(..) | Warn(..) -> True
    }
  })
    as "nothing is stored"
  assert !character_select.waiting(state)
}

// ---- delete ----

/// The warnings among the effects.
fn warnings(effects: List(character_select.Effect)) -> List(String) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Warn(text:) -> Ok(text)
      Ask(..) | Send(..) -> Error(Nil)
    }
  })
}

pub fn the_clients_0x0352_asks_the_store_to_delete_the_character_of_the_account_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) = delete(0x1_0000_0002)
  assert effects
    == [
      Ask(request: StoreDelete(
        account_id: AccountId(7),
        character_id: CharacterId(0x1_0000_0002),
      )),
    ]
    as "opcode.0x352: the request names the character by its id; the store deletes it only if the account has it"
  assert character_select.waiting(state) as "the store's answer is awaited"
}

pub fn a_deleted_character_is_0x00e6_result_0_with_value_0_and_no_new_list_follows_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = delete(5)
  let assert Ok(#(state, effects)) =
    character_select.deleted(asking, CharacterDeleted)
  assert character_support.delete_result_in(sent(effects))
    == DeleteCharacterResult(result: delete_result.DeleteOk, value: 0)
    as "opcode.0xe6: result 0 removes the character from the client's own list, and the value is read only for result 2 (opcode.0xe6.value), so 0 is safe"
  assert list.length(effects) == 1
    as "lua.CharacterSelection.OnCharacterDeleteResult: the client rebuilds its list itself, so no new 0x0117 is needed"
  assert !character_select.waiting(state) as "the result is sent"
}

pub fn a_character_the_account_does_not_have_is_0x00e6_result_1_with_a_warning_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = delete(5)
  let assert Ok(#(state, effects)) =
    character_select.deleted(asking, NoSuchCharacter)
  assert character_support.delete_result_in(sent(effects))
    == DeleteCharacterResult(result: delete_result.DeleteFailed, value: 0)
    as "lua.CharacterSelection.OnCharacterDeleteResult: 1 DeleteFailed shows 'Something went wrong...'"
  let assert [text] = warnings(effects)
    as "the real client deletes only a listed character, so the request is logged once"
  assert string.contains(text, "5") as "the warning names the character's id"
  assert !character_select.waiting(state)
}

pub fn a_delete_answer_with_no_delete_asked_is_none_character_select_takes_test() -> Nil {
  use <- owned_test.run(60_000)
  assert character_select.deleted(character_select.new(), CharacterDeleted)
    == Error(Nil)
    as "no ask is out"
  let #(listing, _) = character_select.started(AccountId(7))
  assert character_select.deleted(listing, CharacterDeleted) == Error(Nil)
    as "a list is asked for, not a delete"
}

// ---- rename ----

pub fn the_clients_0x0786_with_a_name_that_passes_rule_0_asks_the_store_to_rename_the_character_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) = rename(5, "Ab Cd")
  assert effects
    == [
      Ask(request: StoreRename(
        account_id: AccountId(7),
        character_id: CharacterId(5),
        name: "Ab Cd",
      )),
    ]
    as "opcode.0x786: the character's id and the name the player typed"
  assert character_select.waiting(state)
}

pub fn a_name_that_fails_rule_0_is_0x014b_result_15_with_the_request_and_nothing_is_asked_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) = rename(5, "Abcd")
  assert character_support.rename_result_in(sent(effects))
    == RenameCharacterResult(
      result: rename_result.NameLength,
      character_id: 5,
      name: "Abcd",
    )
    as "lua.CharacterSelection.OnCharacterRenameResult: 15 shows 'Character names may only contain 3 to 20 letters.'"
  assert warnings(effects) == []
    as "a name is a player's to mistype, so no warning, as for a create"
  assert list.length(effects) == 1 as "nothing is asked, so nothing is stored"
  assert !character_select.waiting(state)
}

pub fn the_stores_answer_to_a_rename_becomes_the_result_the_client_shows_test() -> Nil {
  use <- owned_test.run(60_000)
  let result_for = fn(answer) {
    let #(asking, _) = rename(0x1_0000_0001, "Ab Cd")
    let assert Ok(#(state, effects)) = character_select.renamed(asking, answer)
    assert !character_select.waiting(state) as "the result is sent"
    #(character_support.rename_result_in(sent(effects)), warnings(effects))
  }
  assert result_for(CharacterRenamed(name: "Ab Cd"))
    == #(
      RenameCharacterResult(
        result: rename_result.RenameOk,
        character_id: 0x1_0000_0001,
        name: "Ab Cd",
      ),
      [],
    )
    as "opcode.0x14b: 18 gives the listed character with that id the name and clears its mark; the name is the stored one"
  assert result_for(NewNameTaken)
    == #(
      RenameCharacterResult(
        result: rename_result.NameUnavailable,
        character_id: 0x1_0000_0001,
        name: "Ab Cd",
      ),
      [],
    )
    as "lua.CharacterSelection.OnCharacterRenameResult: 16 'The name you picked is unavailable.'"
  let #(refused, logged) = result_for(NotRenamable)
  assert refused
    == RenameCharacterResult(
      result: rename_result.RenameFailed,
      character_id: 0x1_0000_0001,
      name: "Ab Cd",
    )
    as "lua.CharacterSelection.OnCharacterRenameResult: 13 'We are unable to process your request at this time.'"
  assert list.length(logged) == 1
    as "the real client offers a rename only for a marked character of its own list, so the request is logged"
}

pub fn a_rename_answer_with_no_rename_asked_is_none_character_select_takes_test() -> Nil {
  use <- owned_test.run(60_000)
  assert character_select.renamed(character_select.new(), NewNameTaken)
    == Error(Nil)
  let #(deleting, _) = delete(5)
  assert character_select.renamed(deleting, NotRenamable) == Error(Nil)
    as "a delete is asked for, not a rename"
}

pub fn an_entry_carries_the_rename_bit_from_the_characters_naming_and_the_in_world_fields_are_zeros_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) =
    listed(asking, [
      Character(..stored(id: 1, name: "Ab Cd", level: 1), naming: NeedsRename),
      stored(id: 2, name: "Ef Gh", level: 1),
    ])
  assert list.map(entries(effects), fn(entry) { entry.requires_rename })
    == [1, 0]
    as "lua.CharacterSelection.OnSelectCharacter: bRequiresRename opens the rename form; opcode.0x117 names the entry's bit"
  let assert [_, Frame(message_id: 0x0117, body:)] = sent(effects)
  let assert Ok(list_message) = character_list.decode(body)
  assert list_message.in_world_realm_id == 0
    && list_message.in_world_character_id == 0
    && list_message.in_world_logoff_ms == 0
    as "lua.CharacterSelection.OnRemoveCountdown: the client reads a character still in the world only with a realm and an id that are not 0; no session enters the world yet"
}

// ---- play after a create ----

pub fn a_play_request_is_refused_with_failed_and_the_list_is_asked_for_again_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) =
    character_select.play_requested(
      account_id: AccountId(7),
      request: PlayCharacter(character_id: 42),
    )
  let assert [Send(Frame(message_id: 0x0162, body:)), Ask(request:)] = effects
    as "opcode.0x162.after_create: 0x0162 first, then the store is asked for the list"
  assert play_character_refused.decode(body)
    == Ok(PlayCharacterRefused(result: play_refusal.Failed))
    as "opcode.0x162: 2 Failed is the generic refusal, and the world is not entered yet"
  assert request == ListCharacters(account_id: AccountId(7))
  assert character_select.waiting(state)
}

pub fn after_a_play_request_the_character_it_named_is_selected_by_the_clients_rule_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) =
    character_select.play_requested(
      account_id: AccountId(7),
      request: PlayCharacter(character_id: 2),
    )
  let assert Ok(#(state, effects)) =
    listed(asking, [
      stored(id: 1, name: "Ab Cd", level: 4),
      stored(id: 2, name: "Ef Gh", level: 1),
      stored(id: 3, name: "Ij Kl", level: 9),
    ])
  assert !character_select.waiting(state)
  let assert [Frame(message_id: 0x0036, ..), Frame(message_id: 0x0117, ..)] =
    sent(effects)
    as "opcode.0x36 and opcode.0x117 follow 0x0162, which was sent when the request came"
  let days =
    list.map(entries(effects), fn(entry) { entry.last_logged_out_days })
  let assert [0, chosen, 0] = days
    as "lua.CharacterSelection.OnLoadFromCharacter.preselect: only the character named has a last logout"
  let assert <<value:float-size(32)>> = <<chosen:size(32)>>
  assert value <. 0.0 && value >. -1.0
    as "the entry's float is signed days from now, negative for a past logout (0x1401e83a0): a logout a moment ago is the largest value there can be, and 0 is none"
  assert list.map(entries(effects), fn(entry) { entry.character_id })
    == [1, 2, 3]
    as "the list keeps the store's order"
  // A character the account does not have selects nobody by its logout.
  let #(asking, _) =
    character_select.play_requested(
      account_id: AccountId(7),
      request: PlayCharacter(character_id: 99),
    )
  let assert Ok(#(_, effects)) =
    listed(asking, [stored(id: 1, name: "Ab Cd", level: 4)])
  assert list.map(entries(effects), fn(entry) { entry.last_logged_out_days })
    == [0]
}

/// The entries of the 0x0117 in the effects.
fn entries(effects: List(character_select.Effect)) -> List(CharacterListEntry) {
  let assert Ok(Frame(body:, ..)) =
    list.find(sent(effects), fn(frame) { frame.message_id == 0x0117 })
    as "the effects send 0x0117"
  let assert Ok(list) = character_list.decode(body) as "0x0117 decodes"
  list.characters
}
