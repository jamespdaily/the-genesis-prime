//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover creating,
//// deleting and renaming a character and the play that follows.
////
//// Expected values come from these places.
//// - The create path: 0x025C carries the whole frame of 0x025B (opcode.0x25c),
////   the result is 0x00DC (opcode.0xdc, lua.Character.OnCreateCharacterFailed),
////   and after CreateOk the client's 0x07DD (opcode.0x7dd) gets 0x0162 Failed
////   and then the list again, 0x0036 before 0x0117 (opcode.0x162.after_create,
////   opcode.0x36), the new character selected by the client's own rule
////   (lua.CharacterSelection.OnLoadFromCharacter.preselect).

import character_support
import character_tables
import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{
  type Request, AskStore, FromMap, FromStore,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/character_list
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/create_result
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/delete_result
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/play_refusal
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/rename_result
import genesis_prime/step.{
  type ConnectionStep, EndedBeforeAnswer, LogError, LogWarning, NoAnswerInTime,
  NotRunning, StoppedWaiting,
}
import genesis_prime/store.{
  AccountId, Character, CharacterCreated, CharacterDeleted, CharacterId,
  CharacterLoaded, CharacterRenamed, Created, Deleted, ForSelect, ForWorld,
  ListCharacters, Listed, LoadCharacter, LookEntry, NameBreaksRule, NameTaken,
  NewCharacter, NewNameBreaksRule, NewNameTaken, NoFreeSlot, NoSuchCharacter,
  NotRenamable, NotTheAccounts, Renamed, Select, Unavailable, World,
}
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import genesis_prime/world_map/map
import gleam/list
import gleam/option.{None, Some}
import owned_test

// ---- create and the play that follows ----

/// The connection after a create request, with its ask to the store.
fn creating(
  request: create_character.CreateCharacter,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.read(
    game_connection_support.in_select(),
    game_connection_support.create_message(request),
  )
}

/// The one 0x00DC the step writes, decoded.
fn create_result_of(
  taken: ConnectionStep(Request),
) -> create_character_result.CreateCharacterResult {
  character_support.create_result_in(game_connection_support.heard(
    taken,
    game_connection_support.keyed(),
  ))
}

pub fn message_0x025c_with_a_valid_0x025b_asks_the_store_to_make_the_character_and_its_answer_is_0x00dc_create_ok_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    creating(game_connection_support.a_create_request("Ab Cd"))
  assert game_connection_support.ask_request(taken)
    == AskStore(
      store.Select(store.CreateCharacter(
        account_id: AccountId(7),
        character: NewCharacter(
          name: "Ab Cd",
          gender: 1,
          race_id: RaceId(1),
          class_id: ClassId(1),
          faction_id: 167,
          level: 1,
          path: 2,
          place: character_tables.novice_start_place(),
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(label: CharacterCustomizationLabelId(22), value: 2),
          ],
          bones: character_support.bones(46),
          starting_items: [],
        ),
        character_slots: 3,
      )),
    )
    as "opcode.0x25b, CharacterCreation row 466; its PreTutorial start is WorldLocation2 row 51596 (World 3460, zone 6009 and its position); the slot count is the settings'"
  assert support.writes(taken) == []
    as "nothing is written before the store answers"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForSelect(Created(CharacterCreated(CharacterId(11))))),
      ),
    )
  assert create_result_of(taken)
    == CreateCharacterResult(
      character_id: 11,
      field_2: 0,
      result: create_result.CreateOk,
    )
    as "opcode.0xdc: the new character's id and CreateOk"
  assert !support.stops(taken) as "the connection goes on to the play request"
  assert support.asked(taken) == None
}

pub fn a_name_that_fails_rule_0_is_asked_of_the_store_and_its_answer_is_0x00dc_name_length_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    creating(game_connection_support.a_create_request("Abcd"))
  let assert AskStore(store.Select(store.CreateCharacter(character:, ..))) =
    game_connection_support.ask_request(taken)
    as "the name's rule 0 is the table's, so the store is asked like any create"
  assert character.name == "Abcd"
  assert support.writes(taken) == []
    as "nothing is written before the store answers"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Created(NameBreaksRule)))),
    )
  assert create_result_of(taken).result == create_result.NameLength
    as "lua.Character.OnCreateCharacterFailed: 10"
  assert support.logs_of(step: taken, level: LogWarning) == []
    as "a name is a player's to mistype"
  assert !support.stops(taken)
}

pub fn a_name_taken_in_any_case_and_an_account_at_its_slots_are_0x00dc_6_and_9_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    creating(game_connection_support.a_create_request("Ab Cd"))
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Created(NameTaken)))),
    )
  assert create_result_of(taken).result == create_result.NameUnavailable
    as "lua.Character.OnCreateCharacterFailed: 6"
  let #(state, taken) =
    creating(game_connection_support.a_create_request("Ab Cd"))
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Created(NoFreeSlot)))),
    )
  assert create_result_of(taken).result == create_result.AccountFull
    as "lua.Character.OnCreateCharacterFailed: 9"
  assert !support.stops(taken)
}

pub fn a_request_the_client_would_not_send_is_0x00dc_create_failed_with_a_warning_naming_the_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    creating(
      CreateCharacter(
        ..game_connection_support.a_create_request("Ab Cd"),
        creation_id: 539,
      ),
    )
  assert support.asked(taken) == None as "nothing is stored"
  assert create_result_of(taken).result == create_result.CreateFailed
    as "lua.Character.OnCreateCharacterFailed: 4 is 'due to an error'; CharacterCreation row 539 is a Level50 row that costs currency the account lacks"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "the refusal is logged once"
  assert support.says(line, "539") as "the warning names the creation row"
  assert line.about.account_id == Some(7)
  assert !support.stops(taken)
}

pub fn a_store_that_gives_no_answer_to_a_create_gets_0x036a_reason_8_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(Unavailable)),
      NoAnswerInTime,
      NotRunning,
      EndedBeforeAnswer,
      StoppedWaiting,
    ],
    fn(outcome) {
      let #(state, taken) =
        creating(game_connection_support.a_create_request("Ab Cd"))
      let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "0x1400168a0 and lua.Character.OnCharacterList: the client waits with no timeout, so a create the store cannot answer ends with 0x036A, reason 8, as a list does"
    },
  )
}

pub fn a_play_of_a_character_the_account_does_not_have_gets_0x0162_failed_then_0x0036_and_0x0117_with_the_character_selected_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.playing(11)
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForWorld(NotTheAccounts))),
    )
  let assert [Frame(message_id: 0x0162, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x162.after_create: the refusal is written first"
  assert play_character_refused.decode(body)
    == Ok(PlayCharacterRefused(result: play_refusal.Failed))
    as "opcode.0x162: 2 Failed is the generic refusal"
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "the list is built again"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "a play the real client would not send is logged once"
  assert support.says(line, "11") as "the warning names the character's id"
  assert line.about.account_id == Some(7)
  let new =
    Character(
      ..game_connection_support.character(id: 11, name: "Ab Cd", seed: 1),
      level: 1,
    )
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForSelect(
            Listed([
              game_connection_support.character(id: 5, name: "Eve", seed: 2),
              new,
            ]),
          ),
        ),
      ),
    )
  let assert [
    Frame(message_id: 0x097F, ..),
    Frame(message_id: 0x0968, ..),
    Frame(message_id: 0x0036, body: level),
    Frame(message_id: 0x0117, body: list_body),
  ] = game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x36 then opcode.0x117, after the tier and the entitlements"
  assert max_character_level.decode(level) == Ok(MaxCharacterLevel(12))
    as "opcode.0x36: the highest level of the account's characters (Eve's 12; the new character's is 1)"
  let assert Ok(sent) = character_list.decode(list_body)
  assert list.map(sent.characters, fn(entry) { entry.name }) == ["Eve", "Ab Cd"]
  let assert [0, chosen] =
    list.map(sent.characters, fn(entry) { entry.last_logged_out_days })
    as "lua.CharacterSelection.OnLoadFromCharacter.preselect: only the character named has a last logout, so the client selects it"
  assert chosen != 0
}

pub fn a_play_of_a_character_with_no_saved_place_is_refused_the_same_way_and_the_map_is_not_asked_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.playing(42)
  let no_place =
    Character(..game_connection_support.world_character(), place: None)
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForWorld(
            CharacterLoaded(no_place, character_support.epoch(1), None, []),
          ),
        ),
      ),
    )
  let assert [Frame(message_id: 0x0162, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "the world 0 a character made before create wrote its start place has no World row, which 0xAD needs (opcode.0xad)"
  assert play_character_refused.decode(body)
    == Ok(PlayCharacterRefused(result: play_refusal.Failed))
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "the list again, and no map is asked"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line, "no saved place")
}

pub fn a_join_the_map_refuses_hands_the_client_back_to_character_select_with_no_watch_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.joining()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(
          map.NotJoined(reason: map.NoLoadout(class_id: 2, faction_id: 166)),
        ),
      ),
    )
  let assert [Frame(message_id: 0x0162, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "the play is refused as one with no saved place is (opcode.0x162.after_create): the player is in no map"
  assert play_character_refused.decode(body)
    == Ok(PlayCharacterRefused(result: play_refusal.Failed))
  assert game_connection_support.ask_request(taken)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "the list again, and the client is in character select"
  assert support.watches(taken) == []
    as "no watch is opened on a map that holds no player of this connection"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert support.says(line, "the map refused the join of character 42")
}

pub fn a_second_request_waits_for_the_create_answer_and_is_then_taken_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(game_connection_support.in_select(), <<
      game_connection_support.create_message(
        game_connection_support.a_create_request("Ab Cd"),
      ):bits,
      game_connection_support.play_message(11):bits,
    >>)
  assert game_connection_support.ask_request(taken)
    == AskStore(
      store.Select(store.CreateCharacter(
        account_id: AccountId(7),
        character: NewCharacter(
          name: "Ab Cd",
          gender: 1,
          race_id: RaceId(1),
          class_id: ClassId(1),
          faction_id: 167,
          level: 1,
          path: 2,
          place: character_tables.novice_start_place(),
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(label: CharacterCustomizationLabelId(22), value: 2),
          ],
          bones: character_support.bones(46),
          starting_items: [],
        ),
        character_slots: 3,
      )),
    )
    as "only the create is asked while its answer is out"
  assert support.writes(taken) == []
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForSelect(Created(CharacterCreated(CharacterId(11))))),
      ),
    )
  let assert [Frame(message_id: 0x00DC, ..)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "the result first"
  assert game_connection_support.ask_request(taken)
    == AskStore(World(LoadCharacter(AccountId(7), CharacterId(11))))
    as "then the play that waited: the character the create made is read for the world"
}

// ---- delete and rename ----

fn delete_message(character_id: Int) -> BitArray {
  let assert Ok(body) = delete_character.encode(DeleteCharacter(character_id:))
    as "0x0352 encodes"
  game_connection_support.keyed_message(0x0352, body)
}

fn rename_message(character_id: Int, name: String) -> BitArray {
  let assert Ok(body) =
    rename_character.encode(RenameCharacter(character_id:, name:))
    as "0x0786 encodes"
  game_connection_support.keyed_message(0x0786, body)
}

/// The connection after a delete request, with its ask to the store.
fn deleting(
  character_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.read(
    game_connection_support.in_select(),
    delete_message(character_id),
  )
}

/// The connection after a rename request, with its ask to the store.
fn renaming(
  character_id: Int,
  name: String,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.read(
    game_connection_support.in_select(),
    rename_message(character_id, name),
  )
}

pub fn message_0x0352_asks_the_store_to_delete_the_character_and_its_answer_is_0x00e6_result_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = deleting(11)
  assert game_connection_support.ask_request(taken)
    == AskStore(
      store.Select(store.DeleteCharacter(
        account_id: AccountId(7),
        character_id: CharacterId(11),
      )),
    )
    as "opcode.0x352: the character's id, and the holder's account, which scopes the delete"
  assert support.writes(taken) == []
    as "nothing is written before the store answers"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Deleted(CharacterDeleted)))),
    )
  assert character_support.delete_result_in(game_connection_support.heard(
      taken,
      game_connection_support.keyed(),
    ))
    == DeleteCharacterResult(result: delete_result.DeleteOk, value: 0)
    as "opcode.0xe6: result 0 and the value nothing reads (opcode.0xe6.value)"
  assert !support.stops(taken) as "the connection goes on"
  assert support.asked(taken) == None
    as "lua.CharacterSelection.OnCharacterDeleteResult: the client rebuilds its list, so the store is not asked for it again"
}

pub fn a_delete_of_a_character_the_account_does_not_have_is_0x00e6_result_1_and_a_warning_with_the_account_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = deleting(11)
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Deleted(NoSuchCharacter)))),
    )
  assert character_support.delete_result_in(game_connection_support.heard(
      taken,
      game_connection_support.keyed(),
    ))
    == DeleteCharacterResult(result: delete_result.DeleteFailed, value: 0)
    as "lua.CharacterSelection.OnCharacterDeleteResult: 1 shows 'Something went wrong...'"
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
    as "a request the real client would not send is logged once"
  assert support.says(line, "11") as "the warning names the character's id"
  assert line.about.account_id == Some(7)
  assert !support.stops(taken)
}

pub fn message_0x0786_asks_the_store_to_rename_the_character_and_its_answer_is_0x014b_result_18_with_the_stored_name_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = renaming(11, "Ab Cd")
  assert game_connection_support.ask_request(taken)
    == AskStore(
      store.Select(store.RenameCharacter(
        account_id: AccountId(7),
        character_id: CharacterId(11),
        name: "Ab Cd",
      )),
    )
    as "opcode.0x786: the character's id and the typed name"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(ForSelect(Renamed(CharacterRenamed(name: "Ab Cd")))),
      ),
    )
  assert character_support.rename_result_in(game_connection_support.heard(
      taken,
      game_connection_support.keyed(),
    ))
    == RenameCharacterResult(
      result: rename_result.RenameOk,
      character_id: 11,
      name: "Ab Cd",
    )
    as "opcode.0x14b: result 18 with the id and the name"
  assert !support.stops(taken)
}

pub fn a_name_taken_a_name_failing_rule_0_and_a_character_that_is_not_renamable_are_0x014b_16_15_and_13_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = renaming(11, "Ab Cd")
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Renamed(NewNameTaken)))),
    )
  assert character_support.rename_result_in(game_connection_support.heard(
      taken,
      game_connection_support.keyed(),
    )).result
    == rename_result.NameUnavailable
    as "lua.CharacterSelection.OnCharacterRenameResult: 16"
  let #(state, taken) = renaming(11, "Abcd")
  assert game_connection_support.ask_request(taken)
    == AskStore(
      store.Select(store.RenameCharacter(
        account_id: AccountId(7),
        character_id: CharacterId(11),
        name: "Abcd",
      )),
    )
    as "the name's rule 0 is the table's, so the store is asked like any rename"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Renamed(NewNameBreaksRule)))),
    )
  assert character_support.rename_result_in(game_connection_support.heard(
      taken,
      game_connection_support.keyed(),
    )).result
    == rename_result.NameLength
    as "lua.CharacterSelection.OnCharacterRenameResult: 15"
  assert support.logs_of(step: taken, level: LogWarning) == []
    as "a name is a player's to mistype"
  let #(state, taken) = renaming(11, "Ab Cd")
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Renamed(NotRenamable)))),
    )
  assert character_support.rename_result_in(game_connection_support.heard(
      taken,
      game_connection_support.keyed(),
    )).result
    == rename_result.RenameFailed
    as "lua.CharacterSelection.OnCharacterRenameResult: 13"
  assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
  assert !support.stops(taken)
}

pub fn a_store_that_gives_no_answer_to_a_delete_or_a_rename_gets_0x036a_reason_8_and_the_connection_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(Unavailable)),
      NoAnswerInTime,
      NotRunning,
      EndedBeforeAnswer,
      StoppedWaiting,
    ],
    fn(outcome) {
      list.each([deleting(11), renaming(11, "Ab Cd")], fn(asked) {
        let #(state, taken) = asked
        let #(_, taken) =
          game_connection_support.answer(state:, taken:, outcome:)
        assert game_connection_support.disconnect(
            taken,
            game_connection_support.keyed(),
          )
          == LostUserServer
          as "0x1400168a0 and opcode.0xe6, opcode.0x14b: the client waits for the result with no timeout, so a request the store cannot answer ends with 0x036A, reason 8"
        assert support.stops(taken)
      })
    },
  )
}

pub fn a_store_answer_to_another_ask_than_a_delete_or_a_rename_is_a_bug_that_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(deleting(11), ForSelect(Renamed(NewNameTaken))),
      #(renaming(11, "Ab Cd"), ForSelect(Deleted(CharacterDeleted))),
    ],
    fn(asked) {
      let #(#(state, taken), wrong) = asked
      let #(_, taken) =
        game_connection_support.answer(
          state:,
          taken:,
          outcome: step.Answer(FromStore(wrong)),
        )
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_0x0352_or_0x0786_the_clients_reader_would_refuse_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      // opcode.0x352: 64 bits.
      game_connection_support.keyed_message(0x0352, <<1, 2>>),
      // opcode.0x786: 64 bits and a wide text.
      game_connection_support.keyed_message(0x0786, <<1, 2>>),
    ],
    fn(cut) {
      let #(_, taken) =
        game_connection_support.read(game_connection_support.in_select(), cut)
      assert support.stops(taken)
      assert support.asked(taken) == None
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    },
  )
}

pub fn a_0x025c_or_0x07dd_the_clients_reader_would_refuse_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  // The carrier's whole frame is not a frame.
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      game_connection_support.keyed_message(0x025C, <<1, 2, 3>>),
    )
  assert support.stops(taken)
    as "opcode.0x25c: the carrier holds a whole frame the client wrote"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  // The carrier holds another message than 0x025B.
  let assert Ok(other) = frame.encode(0x07DD, <<0, 0, 0, 0, 0, 0, 0, 0>>)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      game_connection_support.keyed_message(0x025C, other),
    )
  assert support.stops(taken) as "opcode.0x25c carries 0x025B and nothing else"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  // A 0x025B body that is cut short.
  let assert Ok(cut) = frame.encode(0x025B, <<1, 2>>)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      game_connection_support.keyed_message(0x025C, cut),
    )
  assert support.stops(taken)
  assert support.asked(taken) == None
  // A 0x07DD body that is cut short (opcode.0x7dd: 64 bits).
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      game_connection_support.keyed_message(0x07DD, <<1, 2>>),
    )
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}
