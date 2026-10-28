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
//// It asks the store itself and takes the store's answer in `answered`, which
//// refuses an answer of a kind it did not ask for. A second 0x07E0 while the
//// store is asked is the game connection's to hold, with the client's other
//// frames (test/game_connection_test.gleam).

import client_tables
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/character_select.{Ask, Send, Warn}
import genesis_prime/message/character_list
import genesis_prime/message/character_list_entry.{type CharacterListEntry}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/create_result
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/play_refusal
import genesis_prime/store.{
  type Character, AccountId, Character, CharacterCreated, CharacterId,
  Characters, CreateCharacter as StoreCreate, ListCharacters, LookEntry,
  NameTaken, NewCharacter, NoFreeSlot, NoSuchAccount, Unavailable,
}
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import gleam/list
import gleam/string
import owned_test

const filetime = 133_900_000_000_000_000

fn answered(
  state: character_select.State,
  answer: store.Answer,
) -> Result(#(character_select.State, List(character_select.Effect)), Nil) {
  character_select.answered(
    state,
    answer,
    filetime:,
    realm_id: 1,
    max_characters: 2,
    tables: client_tables.shared(),
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
  let assert [Frame(message_id: 0x00DC, body:)] = sent(effects)
    as "opcode.0xdc: one result"
  let assert Ok(result) = create_character_result.decode(body)
    as "0x00DC decodes"
  result
}

fn a_request(name: String) -> create_character.CreateCharacter {
  // CharacterCreation row 466: class 1, race 1, sex 1, faction 167, a
  // PreTutorial row with no entitlement and no cost; race 1, sex 1 carries 46
  // bone values (opcode.0x25b.counts).
  CreateCharacter(
    creation_id: 466,
    name:,
    path: 1,
    customisation_labels: [2, 22],
    customisation_values: [1, 1],
    bone_values: list.repeat(0x3F800000, 46),
  )
}

fn create(
  request: create_character.CreateCharacter,
) -> #(character_select.State, List(character_select.Effect)) {
  character_select.create_requested(
    account_id: AccountId(7),
    request:,
    tables: client_tables.shared(),
    character_slots: 2,
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

pub fn an_answer_that_is_no_list_or_comes_with_no_ask_out_is_none_character_select_takes_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = character_select.started(AccountId(7))
  assert answered(asking, NoSuchAccount) == Error(Nil)
    as "a login name's answer is none a list ask gets"
  assert answered(asking, Unavailable) == Error(Nil)
    as "the failures every store ask shares are the game connection's to handle"
  assert answered(asking, CharacterCreated(character_id: CharacterId(1)))
    == Error(Nil)
    as "a create's answer is none a list ask gets"
  assert answered(character_select.new(), Characters([])) == Error(Nil)
    as "rows nobody asked for"
  let assert Ok(#(state, _)) = answered(asking, Characters([]))
  assert !character_select.waiting(state) as "the list is sent"
  assert answered(state, Characters([])) == Error(Nil)
    as "one ask has one answer"
}

pub fn a_list_is_0x0036_with_the_accounts_highest_level_and_then_0x0117_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) =
    answered(
      asking,
      Characters([
        stored(id: 1, name: "Ab Cd", level: 12),
        stored(id: 2, name: "Ef Gh", level: 50),
        stored(id: 3, name: "Ij Kl", level: 3),
      ]),
    )
  let assert [
    Frame(message_id: 0x0036, body: level),
    Frame(message_id: 0x0117, ..),
  ] = sent(effects)
    as "opcode.0x36: the highest level goes to the client before the list it builds the creation choices from (0x140021bb0)"
  assert max_character_level.decode(level) == Ok(MaxCharacterLevel(50))
    as "opcode.0x36: the highest character level the account has reached, here 50"
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) = answered(asking, Characters([]))
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
    answered(
      asking,
      Characters([
        stored(id: 1, name: "Ab Cd", level: 1),
        stored(id: 2, name: "Ef Gh", level: 1),
      ]),
    )
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
    )
  let #(asking, _) = character_select.started(AccountId(7))
  let assert Ok(#(_, effects)) = answered(asking, Characters([character]))
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
          bones: list.repeat(0x3F800000, 46),
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
    let assert Ok(#(state, effects)) = answered(asking, answer)
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
    answered(
      asking,
      Characters([
        stored(id: 1, name: "Ab Cd", level: 4),
        stored(id: 2, name: "Ef Gh", level: 1),
        stored(id: 3, name: "Ij Kl", level: 9),
      ]),
    )
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
    answered(asking, Characters([stored(id: 1, name: "Ab Cd", level: 4)]))
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
