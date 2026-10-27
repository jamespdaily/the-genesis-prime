//// Character select as a rule: the state and an input in, the new state and the
//// effects out. Expected values come from the client's records: the layouts and
//// results of messages 0x117, 0xdc, 0x14b, 0xe6, 0x7dd and 0x162 (opcode.*), the
//// states the client waits in (HandleCharacterSelectMessage 0x140020EA0: it sends
//// one request while idle and waits for its answer), the client's own refusals
//// in LuaCreateCharacter 0x140023E90 and LuaRenameCharacter 0x140024DD0, and
//// the CharacterCreation row (opcode.0x25b: it gives class, race, sex and
//// faction). The results of 0xdc, 0x14b and 0xe6 are values of
//// PreGameLib.CodeEnumCharacterModifyResults and the value of 0x162 one of
//// PreGameLib.CodeEnumCharacterSelectResults (the fact file's records of those
//// enums), each named by the enum's own name where a test states it.

import character_support
import client_tables
import environment
import genesis_prime/character/character.{
  type Character, Appearance, Character, NewCharacter,
}
import genesis_prime/character/customisation
import genesis_prime/character/name.{TooShort}
import genesis_prime/character/select.{
  type State, AnswerNobodyAskedFor, BeginWorldEntry, Close, CreateRequested,
  CreationNotOffered, CreationUnknown, DeleteRequested, Deleted, Deleting, Idle,
  Inserted, Loaded, Loading, Log, NameInUse, NameRefused, NameTaken,
  NoStartingPlace, NotFound, NotStarted, NotYourCharacter, PathOutOfRange,
  PlayRequested, RenameRequested, Renamed, Renaming, RequestBeforeStart,
  RequestWhileBusy, Requested, Send, Started, StartedTwice, State, Store,
  StoreUnavailable, Stored, TooManyCustomisations, Unavailable,
  WorldEntryRefused,
}
import genesis_prime/character/server_message.{
  type ServerMessage, CharacterListed, CreateResult, DeleteResult, PlayRefused,
  RenameResult,
}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/create_character.{
  type CreateCharacter, CreateCharacter,
}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/table/character_creation
import gleam/int
import gleam/list
import gleam/string
import owned_test
import seeded
import unitest

fn context() -> select.Context {
  character_support.context(rows: [character_support.creation_row()])
}

fn idle(characters: List(Character)) -> State {
  State(account_id: character_support.account_id, characters:, status: Idle)
}

fn own(id: Int, name: String) -> Character {
  character_support.character(id:, name:)
}

fn create_request() -> CreateCharacter {
  CreateCharacter(
    creation_id: 277,
    name: "Ab Cd",
    path: 2,
    customisation_labels: [1, 2],
    customisation_values: [3, 4],
    bone_values: [0x3F800000, 0xBF000000],
  )
}

/// The result of the create answer in a list of effects, or a stop when the
/// effects hold none.
fn create_result_of(effects: List(select.Effect)) -> Int {
  let assert [CreateResult(answer)] = sent(effects)
    as "one create answer is sent"
  answer.result
}

fn assert_failed_without_a_write(
  effects effects: List(select.Effect),
  refusal refusal: select.Refusal,
  result expected: Int,
  why why: String,
) -> Nil {
  assert list.contains(effects, Log(refusal))
    as { why <> ": the reason is logged" }
  assert stored(effects) == [] as { why <> ": nothing is written" }
  assert create_result_of(effects) == expected
    as {
      why
      <> ": PreGameLib.CodeEnumCharacterModifyResults answers with the value the enum names for it"
    }
}

pub fn starting_character_select_asks_the_store_for_the_accounts_characters_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    select.decide(select.new(character_support.account_id), Started, context())
  assert effects == [Store(select.LoadCharacters(character_support.account_id))]
    as "opcode.0x7e0: the client starts character select; its list is the account's characters"
  assert state.status == Loading
}

pub fn the_loaded_characters_are_sent_as_the_character_list_test() -> Nil {
  use <- owned_test.run(5000)
  let first = own(11, "Ab Cd")
  let second = own(12, "Ef Gh")
  let loading =
    State(
      account_id: character_support.account_id,
      characters: [],
      status: Loading,
    )
  let #(state, effects) =
    select.decide(loading, Stored(Loaded([first, second])), context())
  assert state == idle([first, second])
    as "HandleCharacterSelectMessage 0x140020EA0: after the list the client is idle and sends its requests"
  assert effects
    == [
      Send(
        CharacterListed(CharacterList(
          server_time: character_support.server_time,
          characters: [
            character.list_entry(first),
            character.list_entry(second),
          ],
          enabled_creation_ids: [],
          disabled_creation_ids: [],
          realm_id: character_support.realm_id,
          pending_removal_realm_id: 0,
          pending_removal_character_id: 0,
          pending_removal_time: 0,
          reservations: 0,
          field_10: 0,
          field_11: 0,
          faction_restriction: 0,
          free_level_50_available: 0,
        )),
      ),
    ]
    as "opcode.0x117: the server's time, the characters, the realm; a CharacterCreation row is offered when its enabled column is set, so no ids are enabled or disabled here; with no removal pending, no reservations and no restriction every other value is 0, as in vector.opcode.0x117.body's empty list"
}

pub fn an_account_with_no_characters_gets_an_empty_list_test() -> Nil {
  use <- owned_test.run(5000)
  let loading =
    State(
      account_id: character_support.account_id,
      characters: [],
      status: Loading,
    )
  let #(_, effects) = select.decide(loading, Stored(Loaded([])), context())
  let assert [Send(CharacterListed(list))] = effects as "the list is sent"
  assert list.characters == []
    as "vector.opcode.0x117.body: a list of no characters"
}

pub fn a_request_before_character_select_started_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let request = Requested(PlayRequested(PlayCharacter(11)))
  let #(state, effects) =
    select.decide(select.new(character_support.account_id), request, context())
  assert effects == [Close(RequestBeforeStart)]
    as "opcode.0x7e0: the client starts character select before it sends any request"
  assert state.status == NotStarted
}

pub fn a_second_start_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = select.decide(idle([]), Started, context())
  assert effects == [Close(StartedTwice)]
    as "opcode.0x7e0: the client sends it once, when character select starts"
}

pub fn a_create_request_asks_the_store_to_save_a_character_of_the_creation_row_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    select.decide(
      idle([]),
      Requested(CreateRequested(create_request())),
      context(),
    )
  assert effects
    == [
      Store(
        select.InsertCharacter(NewCharacter(
          account_id: character_support.account_id,
          name: "Ab Cd",
          creation_id: 277,
          gender: 1,
          race_id: 1,
          class_id: 3,
          faction_id: 167,
          experience: 1710,
          level: 3,
          path: 2,
          place: character_support.start_place(),
          appearance: Appearance(
            customisation_labels: [1, 2],
            customisation_values: [3, 4],
            bone_values: [0x3F800000, 0xBF000000],
          ),
        )),
      ),
    ]
    as "opcode.0x25b: the CharacterCreation row gives class, race, sex and faction (row words 4, 8, 0xc and 0x10 of CharacterCreation.tbl); a character starts with the row's xp, and the level that experience gives in XpPerLevel (minXpForLevel); that reading rests on the two columns' names, no client code that reads CharacterCreation's xp is decoded"
  assert state.status == select.Creating
}

pub fn a_saved_character_is_answered_with_the_created_result_and_listed_test() -> Nil {
  use <- owned_test.run(5000)
  let saved = own(21, "Ab Cd")
  let creating = State(..idle([]), status: select.Creating)
  let #(state, effects) =
    select.decide(creating, Stored(Inserted(saved)), context())
  assert effects
    == [
      Send(
        CreateResult(CreateCharacterResult(
          character_id: 21,
          field_2: 0,
          result: 3,
        )),
      ),
    ]
    as "opcode.0xdc: the new character's id and result 3, created; the client then plays the new character itself (0x7dd)"
  assert state == idle([saved])
    as "HandleMessage00DC 0x140021FB0: the client is idle again after the answer"
}

pub fn a_name_the_clients_rule_refuses_is_answered_with_result_10_and_nothing_is_written_test() -> Nil {
  use <- owned_test.run(5000)
  let request = CreateCharacter(..create_request(), name: "A B")
  let #(state, effects) =
    select.decide(idle([]), Requested(CreateRequested(request)), context())
  assert effects
    == [
      Log(NameRefused(TooShort(3))),
      Send(
        CreateResult(CreateCharacterResult(
          character_id: 0,
          field_2: 0,
          result: 10,
        )),
      ),
    ]
    as "LuaCreateCharacter 0x140023E90: a name that breaks text rule 0 raises CharacterCreateFailed with code 10; the server checks the same rule and answers with the same code"
  assert state == idle([]) as "the account is idle again and holds nothing new"
}

pub fn a_creation_row_that_does_not_exist_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let request = CreateCharacter(..create_request(), creation_id: 99_999)
  let #(state, effects) =
    select.decide(idle([]), Requested(CreateRequested(request)), context())
  assert_failed_without_a_write(
    effects:,
    refusal: CreationUnknown(99_999),
    result: 4,
    why: "LuaCreateCharacter 0x140023E90: a CharacterCreation row that is missing is refused",
  )
  assert state == idle([])
}

pub fn a_creation_row_that_is_not_enabled_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    character_creation.CharacterCreation(
      ..character_support.creation_row(),
      enabled: False,
    )
  let #(_, effects) =
    select.decide(
      idle([]),
      Requested(CreateRequested(create_request())),
      character_support.context(rows: [row]),
    )
  assert_failed_without_a_write(
    effects:,
    refusal: CreationNotOffered(277),
    result: 4,
    why: "opcode.0x117: a row is offered when its enabled column is set or the server enables it, and this server enables none",
  )
}

pub fn a_creation_row_that_needs_an_entitlement_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    character_creation.CharacterCreation(
      ..character_support.creation_row(),
      entitlement_id_required: 5,
    )
  let #(_, effects) =
    select.decide(
      idle([]),
      Requested(CreateRequested(create_request())),
      character_support.context(rows: [row]),
    )
  assert_failed_without_a_write(
    effects:,
    refusal: CreationNotOffered(277),
    result: 4,
    why: "LuaCreateCharacter 0x140023E90: a row with an entitlementIdRequired is refused to an account without it, and an account holds none",
  )
}

pub fn a_creation_row_that_costs_account_currency_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    character_creation.CharacterCreation(
      ..character_support.creation_row(),
      account_currency_amount_cost: 100,
    )
  let #(_, effects) =
    select.decide(
      idle([]),
      Requested(CreateRequested(create_request())),
      character_support.context(rows: [row]),
    )
  assert_failed_without_a_write(
    effects:,
    refusal: CreationNotOffered(277),
    result: 4,
    why: "LuaCreateCharacter 0x140023E90: a row that costs account currency is refused to an account that cannot pay, and an account holds none",
  )
}

pub fn a_path_above_3_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let request = CreateCharacter(..create_request(), path: 4)
  let #(_, effects) =
    select.decide(idle([]), Requested(CreateRequested(request)), context())
  assert_failed_without_a_write(
    effects:,
    refusal: PathOutOfRange(4),
    result: 4,
    why: "LuaCreateCharacter 0x140023E90: a path above 3 is refused",
  )
}

pub fn more_than_15_customisations_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let sixteen = list.repeat(1, 16)
  let request =
    CreateCharacter(
      ..create_request(),
      customisation_labels: sixteen,
      customisation_values: sixteen,
    )
  let #(_, effects) =
    select.decide(idle([]), Requested(CreateRequested(request)), context())
  assert_failed_without_a_write(
    effects:,
    refusal: TooManyCustomisations(16),
    result: 4,
    why: "ReadCharacterListEntry 0x14007F720: a listed character's customisation count is 4 bits, so a character with 16 could not be listed",
  )
}

pub fn a_row_the_server_has_no_starting_place_for_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let no_place = select.Context(..context(), start: fn(_row) { Error(Nil) })
  let #(_, effects) =
    select.decide(
      idle([]),
      Requested(CreateRequested(create_request())),
      no_place,
    )
  assert_failed_without_a_write(
    effects:,
    refusal: NoStartingPlace(277),
    result: 12,
    why: "opcode.0xad: a character enters a world at a position, so a character with none cannot be made",
  )
}

pub fn a_name_another_character_has_is_refused_and_not_listed_test() -> Nil {
  use <- owned_test.run(5000)
  let creating = State(..idle([]), status: select.Creating)
  let #(state, effects) = select.decide(creating, Stored(NameInUse), context())
  assert list.contains(effects, Log(NameTaken)) as "the reason is logged"
  assert create_result_of(effects) == 6
    as "PreGameLib.CodeEnumCharacterModifyResults: 6 is CreateFailed_UniqueName, for which the client shows its own text"
  assert state == idle([]) as "nothing was added"
}

pub fn a_database_that_could_not_save_is_not_the_players_mistake_test() -> Nil {
  use <- owned_test.run(5000)
  let creating = State(..idle([]), status: select.Creating)
  let #(state, effects) =
    select.decide(creating, Stored(Unavailable), context())
  assert list.contains(effects, Log(StoreUnavailable))
    as "an outside failure is logged as one, never as a refusal of the request"
  let #(state, effects) = select.decide(state, Stored(Loaded([])), context())
  let assert [CreateResult(answer), CharacterListed(_)] = sent(effects)
    as "the create answer is sent, then the list"
  assert answer.result == 12
    as "PreGameLib.CodeEnumCharacterModifyResults: 12 is CreateFailed_Internal, the server's failure and not the player's"
  assert state == idle([]) as "nothing was added"
}

pub fn a_rename_of_the_accounts_own_character_asks_the_store_test() -> Nil {
  use <- owned_test.run(5000)
  let request =
    RenameRequested(RenameCharacter(character_id: 11, name: "Ef Gh"))
  let #(state, effects) =
    select.decide(idle([own(11, "Ab Cd")]), Requested(request), context())
  assert effects
    == [Store(select.RenameStored(character_support.account_id, 11, "Ef Gh"))]
    as "opcode.0x786: the character id and the new name"
  assert state.status == Renaming(11)
}

pub fn a_renamed_character_is_answered_with_result_18_and_listed_under_its_new_name_test() -> Nil {
  use <- owned_test.run(5000)
  let renaming =
    State(..idle([own(11, "Ab Cd"), own(12, "Ij Kl")]), status: Renaming(11))
  let renamed = Character(..own(11, "Ef Gh"), requires_rename: False)
  let #(state, effects) =
    select.decide(renaming, Stored(Renamed(renamed)), context())
  assert effects
    == [
      Send(
        RenameResult(RenameCharacterResult(
          result: 18,
          character_id: 11,
          name: "Ef Gh",
        )),
      ),
    ]
    as "opcode.0x14b: result 18 means renamed, with the character's id and its new name"
  assert state == idle([renamed, own(12, "Ij Kl")])
    as "opcode.0x14b: the listed character takes the name; the others are as they were"
}

pub fn a_rename_to_a_name_the_rule_refuses_is_answered_with_result_15_and_nothing_is_written_test() -> Nil {
  use <- owned_test.run(5000)
  let request = RenameRequested(RenameCharacter(character_id: 11, name: "A B"))
  let #(state, effects) =
    select.decide(idle([own(11, "Ab Cd")]), Requested(request), context())
  assert effects
    == [
      Log(NameRefused(TooShort(3))),
      Send(
        RenameResult(RenameCharacterResult(
          result: 15,
          character_id: 11,
          name: "A B",
        )),
      ),
    ]
    as "opcode.0x786 and LuaRenameCharacter 0x140024DD0: a refused name is answered with result 15, which the client's own refusal uses"
  assert state == idle([own(11, "Ab Cd")]) as "the character keeps its name"
}

pub fn a_rename_to_a_name_another_character_has_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let renaming = State(..idle([own(11, "Ab Cd")]), status: Renaming(11))
  let #(state, effects) = select.decide(renaming, Stored(NameInUse), context())
  assert list.contains(effects, Log(NameTaken)) as "the reason is logged"
  let assert [RenameResult(answer)] = sent(effects)
    as "one rename answer is sent"
  assert answer.result == 16
    as "PreGameLib.CodeEnumCharacterModifyResults: 16 is RenameFailed_UniqueName"
  assert state == idle([own(11, "Ab Cd")]) as "the character keeps its name"
}

pub fn a_rename_the_store_could_not_do_is_answered_with_the_results_the_enum_names_test() -> Nil {
  use <- owned_test.run(5000)
  let renaming = State(..idle([own(11, "Ab Cd")]), status: Renaming(11))
  let #(reloading, _) = select.decide(renaming, Stored(Unavailable), context())
  let #(_, unavailable) =
    select.decide(reloading, Stored(Loaded([own(11, "Ab Cd")])), context())
  let assert [RenameResult(answer), _list] = sent(unavailable)
    as "one rename answer is sent, then the list the store holds"
  assert answer.result == 14
    as "PreGameLib.CodeEnumCharacterModifyResults: 14 is RenameFailed_Internal, the server's failure"
  let #(_, not_found) = select.decide(renaming, Stored(NotFound), context())
  let assert [RenameResult(answer)] = sent(not_found)
    as "one rename answer is sent"
  assert answer.result == 13
    as "PreGameLib.CodeEnumCharacterModifyResults: 13 is RenameFailed"
}

pub fn a_delete_of_the_accounts_own_character_asks_the_store_test() -> Nil {
  use <- owned_test.run(5000)
  let request = DeleteRequested(DeleteCharacter(character_id: 11))
  let #(state, effects) =
    select.decide(idle([own(11, "Ab Cd")]), Requested(request), context())
  assert effects
    == [Store(select.DeleteStored(character_support.account_id, 11))]
    as "opcode.0x352: the character id"
  assert state.status == Deleting(11)
}

pub fn a_deleted_character_is_answered_with_result_0_and_no_longer_listed_test() -> Nil {
  use <- owned_test.run(5000)
  let deleting =
    State(..idle([own(11, "Ab Cd"), own(12, "Ij Kl")]), status: Deleting(11))
  let #(state, effects) =
    select.decide(deleting, Stored(Deleted(11)), context())
  assert effects
    == [Send(DeleteResult(DeleteCharacterResult(result: 0, field_2: 0)))]
    as "opcode.0xe6: result 0 removes the character from the client's list"
  assert state == idle([own(12, "Ij Kl")])
}

pub fn a_delete_the_store_could_not_do_is_answered_with_a_result_other_than_0_test() -> Nil {
  use <- owned_test.run(5000)
  let deleting = State(..idle([own(11, "Ab Cd")]), status: Deleting(11))
  let #(state, effects) = select.decide(deleting, Stored(NotFound), context())
  let assert [DeleteResult(answer)] = sent(effects)
    as "one delete answer is sent"
  assert answer.result == 1
    as "PreGameLib.CodeEnumCharacterModifyResults: 1 is DeleteFailed; only 0, DeleteOk, removes the character"
  assert state == idle([own(11, "Ab Cd")]) as "the character is still listed"
}

pub fn a_request_for_a_character_of_another_account_is_refused_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let state = idle([own(11, "Ab Cd")])
  let #(_, rename) =
    select.decide(
      state,
      Requested(
        RenameRequested(RenameCharacter(character_id: 99, name: "Ef Gh")),
      ),
      context(),
    )
  let #(_, delete) =
    select.decide(
      state,
      Requested(DeleteRequested(DeleteCharacter(99))),
      context(),
    )
  let #(_, play) =
    select.decide(state, Requested(PlayRequested(PlayCharacter(99))), context())
  list.each([rename, delete, play], fn(effects) {
    assert list.contains(effects, Log(NotYourCharacter(99)))
      as "the character is not in the account's list, so the reason is logged"
    assert !list.any(effects, writes_or_enters)
      as "nothing is written and no world is entered"
  })
  let assert [_, Send(RenameResult(renamed))] = rename
    as "the rename is answered"
  assert renamed.result == 13
    as "PreGameLib.CodeEnumCharacterModifyResults: 13 is RenameFailed, a character that is not the account's"
  let assert [_, Send(DeleteResult(deleted))] = delete
    as "the delete is answered"
  assert deleted.result == 1
    as "PreGameLib.CodeEnumCharacterModifyResults: 1 is DeleteFailed"
  assert sent(play) == [PlayRefused(PlayCharacterRefused(field_1: 2))]
    as "opcode.0x162: playing a character that cannot be played is answered with the refusal, whose value is PreGameLib.CodeEnumCharacterSelectResults 2, Failed"
  Nil
}

pub fn playing_the_accounts_own_character_starts_the_world_entry_test() -> Nil {
  use <- owned_test.run(5000)
  let chosen = own(11, "Ab Cd")
  let #(state, effects) =
    select.decide(
      idle([own(10, "Ij Kl"), chosen]),
      Requested(PlayRequested(PlayCharacter(11))),
      context(),
    )
  assert effects == [BeginWorldEntry(chosen)]
    as "opcode.0x7dd: the client plays the character and waits for 0xad or 0x162"
  assert state.status == select.Entering
}

pub fn a_world_that_refuses_the_character_returns_character_select_to_idle_test() -> Nil {
  use <- owned_test.run(5000)
  let entering = State(..idle([own(11, "Ab Cd")]), status: select.Entering)
  let #(state, effects) = select.decide(entering, WorldEntryRefused, context())
  assert state == idle([own(11, "Ab Cd")])
    as "HandleCharacterSelectMessage 0x140020EA0: 0x162 sends the client back to idle"
  assert effects == [] as "the refusal message was sent by the world entry"
}

pub fn a_request_while_the_server_waits_or_the_player_enters_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let request = Requested(DeleteRequested(DeleteCharacter(11)))
  list.each(
    [Loading, select.Creating, Renaming(11), Deleting(11), select.Entering],
    fn(status) {
      let #(_, effects) =
        select.decide(
          State(..idle([own(11, "Ab Cd")]), status:),
          request,
          context(),
        )
      assert effects == [Close(RequestWhileBusy(status))]
        as "HandleCharacterSelectMessage 0x140020EA0: the client sends a request only while idle, and waits for its answer"
    },
  )
}

pub fn an_answer_nobody_asked_for_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    select.decide(idle([]), Stored(Inserted(own(1, "Ab Cd"))), context())
  assert effects == [Close(AnswerNobodyAskedFor(Idle))]
    as "the store answers only what the rule asked"
}

pub fn the_log_says_which_character_and_why_test() -> Nil {
  use <- owned_test.run(5000)
  assert string.contains(select.describe_refusal(NotYourCharacter(99)), "99")
    as "a refusal names the character"
  assert string.contains(select.describe_refusal(CreationUnknown(7)), "7")
    as "a refusal names the CharacterCreation row"
  assert string.contains(select.describe_refusal(NameRefused(TooShort(3))), "3")
    as "a refusal names the length of a name that is too short"
  assert select.describe_refusal(StoreUnavailable)
    != select.describe_refusal(NameTaken)
    as "each reason has its own sentence"
  assert string.contains(
    select.describe_breach(RequestWhileBusy(Renaming(11))),
    "11",
  )
    as "a breach names what the server was waiting for"
}

/// The answer the store would give to a command of the account's, for a
/// property test that walks the rule through many requests.
fn store_answer(
  command command: select.Command,
  state state: State,
  next_id next_id: Int,
) -> select.Answer {
  case command {
    select.LoadCharacters(_) -> Loaded(state.characters)
    select.InsertCharacter(new) ->
      Inserted(Character(
        id: next_id,
        account_id: new.account_id,
        name: new.name,
        creation_id: new.creation_id,
        gender: new.gender,
        race_id: new.race_id,
        class_id: new.class_id,
        faction_id: new.faction_id,
        experience: new.experience,
        level: new.level,
        path: new.path,
        place: new.place,
        appearance: new.appearance,
        requires_rename: False,
        disabled: False,
      ))
    select.RenameStored(_, character_id, name) ->
      case list.find(state.characters, fn(found) { found.id == character_id }) {
        Ok(found) -> Renamed(Character(..found, name:))
        Error(Nil) -> NotFound
      }
    select.DeleteStored(_, character_id) -> Deleted(character_id)
  }
}

/// A request drawn from the generator: one of the four kinds, naming a
/// character of the account (ids 11 to 13) or of another (ids 91 to 93).
fn drawn_request(state: Int) -> #(select.Request, Int) {
  let #(kind, state) = seeded.up_to(state:, most: 3)
  let #(pick, state) = seeded.up_to(state:, most: 5)
  let id = case pick {
    0 -> 11
    1 -> 12
    2 -> 13
    3 -> 91
    4 -> 92
    _ -> 93
  }
  let request = case kind {
    0 -> CreateRequested(create_request())
    1 -> RenameRequested(RenameCharacter(character_id: id, name: "Ef Gh"))
    2 -> DeleteRequested(DeleteCharacter(character_id: id))
    _ -> PlayRequested(PlayCharacter(character_id: id))
  }
  #(request, state)
}

pub fn no_sequence_of_requests_touches_a_character_of_another_account_test() -> Nil {
  use <- owned_test.run(60_000)
  let own_ids = [11, 12, 13]
  let start = idle([own(11, "Ab Cd"), own(12, "Ef Gh"), own(13, "Ij Kl")])
  let walked =
    int.range(from: 0, to: 300, with: #(20_261_301, 0), run: fn(random, _) {
      let #(random, writes) = random
      let #(state, random, writes) =
        walk(state: start, random:, steps: 8, own_ids:, writes:)
      assert state.account_id == character_support.account_id
      #(random, writes)
    })
  assert walked.1 > 300
    as "the walks reached the store many times, so the property was checked on real writes"
}

fn walk(
  state state: State,
  random random: Int,
  steps steps: Int,
  own_ids own_ids: List(Int),
  writes writes: Int,
) -> #(State, Int, Int) {
  case steps {
    0 -> #(state, random, writes)
    _ -> {
      let #(request, random) = drawn_request(random)
      let #(state, effects) =
        select.decide(state, Requested(request), context())
      let writes =
        list.fold(effects, writes, fn(writes, effect) {
          writes + writes_of(effect:, own_ids:)
        })
      let state = answer_every_effect(state:, effects:)
      walk(state:, random:, steps: steps - 1, own_ids:, writes:)
    }
  }
}

/// Feeds the rule what the store and the world would answer to each effect, so
/// the walk is back at idle for its next request.
fn answer_every_effect(
  state state: State,
  effects effects: List(select.Effect),
) -> State {
  list.fold(effects, state, fn(state, effect) {
    case effect {
      Store(command) -> {
        let #(next, _) =
          select.decide(
            state,
            Stored(store_answer(
              command:,
              state:,
              next_id: 100 + list.length(state.characters),
            )),
            context(),
          )
        next
      }
      BeginWorldEntry(_) -> {
        let #(next, _) = select.decide(state, WorldEntryRefused, context())
        next
      }
      Send(_) | Log(_) | Close(_) | select.Abandon(_) -> state
    }
  })
}

pub fn every_row_of_the_clients_character_creation_table_makes_a_character_of_its_own_class_race_sex_and_faction_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = client_tables.shared()
  let counts = customisation.of(tables)
  let rows = character_creation.all(tables)
  let offered =
    list.filter(rows, fn(row) {
      row.enabled
      && row.entitlement_id_required == 0
      && row.account_currency_amount_cost == 0
    })
  assert offered != []
    as "CharacterCreation.tbl holds rows that are enabled and need no entitlement and no currency, so an account can make a character"
  list.each(offered, fn(row) {
    let request =
      CreateCharacter(
        ..create_request(),
        creation_id: row.id,
        customisation_labels: [1],
        customisation_values: [1],
        bone_values: list.repeat(
          0x3F800000,
          customisation.bone_count(counts, row.race_id, row.sex),
        ),
      )
    let #(_, effects) =
      select.decide(
        idle([]),
        Requested(CreateRequested(request)),
        select.Context(
          ..character_support.context(rows: rows),
          customisation: counts,
        ),
      )
    let assert [Store(select.InsertCharacter(new))] = effects
      as "a row that is offered makes a character"
    assert new.creation_id == row.id
    assert new.class_id == row.class_id
      as "opcode.0x25b: CharacterCreation classId (row word 4)"
    assert new.race_id == row.race_id
      as "opcode.0x25b: CharacterCreation raceId (row word 8)"
    assert new.gender == row.sex
      as "opcode.0x25b: CharacterCreation sex (row word 0xc); HandleMessage00DC 0x140021FB0 passes the row's sex as the gender"
    assert new.faction_id == row.faction_id
      as "opcode.0x25b: CharacterCreation factionId (row word 0x10)"
    assert new.experience == row.xp
      as "CharacterCreation.tbl: the xp column is the experience the character starts with, read from the column's name (no client code that reads it is decoded)"
  })
}

/// 1 for an effect that writes or enters the world, after checking that it
/// touches only a character of the account; 0 for any other.
fn writes_of(effect effect: select.Effect, own_ids own_ids: List(Int)) -> Int {
  case effect {
    Store(select.RenameStored(account, id, _))
    | Store(select.DeleteStored(account, id)) -> {
      assert account == character_support.account_id
        && list.contains(own_ids, id)
        as "a character of another account reached the store"
      1
    }
    Store(select.InsertCharacter(new)) -> {
      assert new.account_id == character_support.account_id
        as "a new character belongs to the account that asked"
      1
    }
    BeginWorldEntry(chosen) -> {
      assert chosen.account_id == character_support.account_id
        && list.contains(own_ids, chosen.id)
        as "a character of another account entered the world"
      1
    }
    Store(select.LoadCharacters(_))
    | Send(_)
    | Log(_)
    | Close(_)
    | select.Abandon(_) -> 0
  }
}

/// The messages a list of effects sends, in order.
fn sent(effects: List(select.Effect)) -> List(ServerMessage) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(message) -> Ok(message)
      Store(_) | BeginWorldEntry(_) | Log(_) | Close(_) | select.Abandon(_) ->
        Error(Nil)
    }
  })
}

/// The commands a list of effects asks the store.
fn stored(effects: List(select.Effect)) -> List(select.Command) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Store(command) -> Ok(command)
      Send(_) | BeginWorldEntry(_) | Log(_) | Close(_) | select.Abandon(_) ->
        Error(Nil)
    }
  })
}

/// Whether an effect writes to the store or starts a world entry.
fn writes_or_enters(effect: select.Effect) -> Bool {
  case effect {
    Store(_) | BeginWorldEntry(_) -> True
    Send(_) | Log(_) | Close(_) | select.Abandon(_) -> False
  }
}

pub fn a_database_that_cannot_give_the_list_is_an_outage_not_the_players_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let loading =
    State(
      account_id: character_support.account_id,
      characters: [],
      status: Loading,
    )
  let #(_, effects) = select.decide(loading, Stored(Unavailable), context())
  assert effects == [select.Abandon(select.ListNotLoaded)]
    as "designing-processes: a database that failed is an outside failure, logged as an error and never as the player's breach; the connection cannot go on without the list"
  let #(_, effects) = select.decide(loading, Stored(NotFound), context())
  assert effects == [Close(AnswerNobodyAskedFor(Loading))]
    as "a store that answers NotFound to the load of a list is a bug, not an outage, and stays a breach of the protocol"
}

pub fn a_write_answered_unavailable_is_followed_by_a_reload_before_the_failure_is_answered_test() -> Nil {
  use <- owned_test.run(5000)
  let mine = [own(11, "Ab Cd")]
  list.each(
    [
      #(select.Creating, "a create"),
      #(Renaming(11), "a rename"),
      #(Deleting(11), "a delete"),
    ],
    fn(waiting) {
      let #(status, what) = waiting
      let #(state, effects) =
        select.decide(
          State(..idle(mine), status:),
          Stored(Unavailable),
          context(),
        )
      assert effects
        == [
          Log(StoreUnavailable),
          Store(select.LoadCharacters(character_support.account_id)),
        ]
        as {
          what
          <> " that was answered Unavailable is followed by a read of the account's characters, so the client's list is the store's; nothing is sent until they are"
        }
      assert case state.status {
        select.Reloading(_) -> True
        select.NotStarted
        | Loading
        | Idle
        | select.Creating
        | Renaming(_)
        | Deleting(_)
        | select.Entering -> False
      }
        as { what <> ": the server waits for the characters" }
    },
  )
}

pub fn the_reload_after_a_failed_write_answers_the_failure_and_sends_the_list_the_store_holds_test() -> Nil {
  use <- owned_test.run(5000)
  let before = [own(11, "Ab Cd")]
  // The create committed after the deadline: the store holds a character the
  // server was told nothing of.
  let created = [own(11, "Ab Cd"), own(12, "Ef Gh")]
  let #(reloading, _) =
    select.decide(
      State(..idle(before), status: select.Creating),
      Stored(Unavailable),
      context(),
    )
  let #(state, effects) =
    select.decide(reloading, Stored(Loaded(created)), context())
  assert state == idle(created)
    as "the list is the store's, so a character the write did commit is listed"
  let assert [CreateResult(failure), CharacterListed(listed)] = sent(effects)
    as "the failure is answered, then the list"
  assert failure.result == 12
    as "PreGameLib.CodeEnumCharacterModifyResults: 12 is CreateFailed_Internal"
  assert listed.characters == list.map(created, character.list_entry)
    as "opcode.0x117: the client replaces its list with the one it is sent, so the next 0x117 matches the store"
  let #(reloaded_for_rename, _) =
    select.decide(
      State(..idle(before), status: Renaming(11)),
      Stored(Unavailable),
      context(),
    )
  let #(_, answered) =
    select.decide(reloaded_for_rename, Stored(Loaded(before)), context())
  let assert [RenameResult(rename), CharacterListed(_)] = sent(answered)
    as "the rename failure is answered, then the list"
  assert rename.result == 14
    as "PreGameLib.CodeEnumCharacterModifyResults: 14 is RenameFailed_Internal"
  let #(reloaded_for_delete, _) =
    select.decide(
      State(..idle(before), status: Deleting(11)),
      Stored(Unavailable),
      context(),
    )
  let #(_, answered) =
    select.decide(reloaded_for_delete, Stored(Loaded([])), context())
  let assert [DeleteResult(delete), CharacterListed(emptied)] = sent(answered)
    as "the delete failure is answered, then the list"
  assert delete.result == 1
    as "PreGameLib.CodeEnumCharacterModifyResults: 1 is DeleteFailed; the write did commit, and the list says so"
  assert emptied.characters == []
}

pub fn a_reload_that_the_database_cannot_do_either_ends_the_connection_as_an_outage_test() -> Nil {
  use <- owned_test.run(5000)
  let #(reloading, _) =
    select.decide(
      State(..idle([own(11, "Ab Cd")]), status: select.Creating),
      Stored(Unavailable),
      context(),
    )
  let #(_, effects) = select.decide(reloading, Stored(Unavailable), context())
  assert effects == [select.Abandon(select.ListNotReloaded)]
    as "what the write did is not known and the list cannot be read, so the connection ends and the next login reads the store"
}

pub fn a_command_that_got_no_answer_ends_the_connection_and_is_never_answered_as_unavailable_test() -> Nil {
  use <- owned_test.run(5000)
  let mine = [own(11, "Ab Cd")]
  list.each(
    [
      #(select.Creating, "a create"),
      #(Renaming(11), "a rename"),
      #(Deleting(11), "a delete"),
    ],
    fn(waiting) {
      let #(status, what) = waiting
      let #(state, effects) =
        select.decide(
          State(..idle(mine), status:),
          Stored(select.Unknown),
          context(),
        )
      assert effects == [select.Abandon(select.WriteNotAnswered)]
        as {
          what
          <> " that was sent and got no answer in the longest a write can take may or may not have been done: the connection ends with a logged error, so the client connects again and lists the store's characters, and the player is told nothing that may be untrue"
        }
      assert state.status == status
        as { what <> ": nothing is decided about the characters" }
    },
  )
}

pub fn a_list_that_got_no_answer_ends_the_connection_as_an_outage_test() -> Nil {
  use <- owned_test.run(5000)
  let loading =
    State(
      account_id: character_support.account_id,
      characters: [],
      status: Loading,
    )
  let #(_, effects) = select.decide(loading, Stored(select.Unknown), context())
  assert effects == [select.Abandon(select.ListNotLoaded)]
    as "the connection cannot go on without the list, and the next login reads the store"
  let #(reloading, _) =
    select.decide(
      State(..idle([own(11, "Ab Cd")]), status: select.Creating),
      Stored(Unavailable),
      context(),
    )
  let #(_, effects) =
    select.decide(reloading, Stored(select.Unknown), context())
  assert effects == [select.Abandon(select.ListNotReloaded)]
    as "what the write did is not known and the list cannot be read, so the connection ends"
}

pub fn a_request_while_the_list_is_read_again_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(reloading, _) =
    select.decide(
      State(..idle([own(11, "Ab Cd")]), status: select.Creating),
      Stored(Unavailable),
      context(),
    )
  let #(_, effects) =
    select.decide(
      reloading,
      Requested(DeleteRequested(DeleteCharacter(11))),
      context(),
    )
  assert effects == [Close(RequestWhileBusy(reloading.status))]
    as "HandleCharacterSelectMessage 0x140020EA0: the client sends a request only while idle, and it was answered nothing yet"
}

pub fn a_disabled_character_is_refused_with_result_3_and_nothing_is_entered_test() -> Nil {
  use <- owned_test.run(5000)
  let disabled = Character(..own(11, "Ab Cd"), disabled: True)
  let #(state, effects) =
    select.decide(
      idle([disabled]),
      Requested(PlayRequested(PlayCharacter(11))),
      context(),
    )
  assert effects
    == [
      Log(select.CharacterDisabled(11)),
      Send(PlayRefused(PlayCharacterRefused(field_1: 3))),
    ]
    as "opcode.0x162: the value is PreGameLib.CodeEnumCharacterSelectResults 3, FailedDisabled"
  assert state == idle([disabled])
    as "the client returns to idle character select, so a request is taken again"
}

pub fn a_character_that_must_be_renamed_is_refused_with_result_1_and_nothing_is_entered_test() -> Nil {
  use <- owned_test.run(5000)
  let unnamed = Character(..own(11, "Ab Cd"), requires_rename: True)
  let #(state, effects) =
    select.decide(
      idle([unnamed]),
      Requested(PlayRequested(PlayCharacter(11))),
      context(),
    )
  assert effects
    == [
      Log(select.CharacterRequiresRename(11)),
      Send(PlayRefused(PlayCharacterRefused(field_1: 1))),
    ]
    as "opcode.0x162: the value is PreGameLib.CodeEnumCharacterSelectResults 1, FailedRename"
  assert state == idle([unnamed])
    as "the client returns to idle character select, so the rename it is asked for can be asked"
}

pub fn a_disabled_character_that_must_also_be_renamed_is_refused_as_disabled_test() -> Nil {
  use <- owned_test.run(5000)
  let both =
    Character(..own(11, "Ab Cd"), disabled: True, requires_rename: True)
  let #(_, effects) =
    select.decide(
      idle([both]),
      Requested(PlayRequested(PlayCharacter(11))),
      context(),
    )
  assert sent(effects) == [PlayRefused(PlayCharacterRefused(field_1: 3))]
    as "a rename does not make a disabled character playable, so the player is told it is disabled"
}

fn create_with(
  bone_values bone_values: List(Int),
  labels labels: List(Int),
  characters characters: List(Character),
  slots slots: Int,
) -> #(State, List(select.Effect)) {
  select.decide(
    idle(characters),
    Requested(CreateRequested(
      CreateCharacter(
        ..create_request(),
        customisation_labels: labels,
        customisation_values: list.map(labels, fn(_) { 1 }),
        bone_values:,
      ),
    )),
    select.Context(..context(), character_slots: slots),
  )
}

pub fn a_number_of_bone_values_other_than_the_race_and_sexs_is_refused_with_result_4_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([[], [0x3F800000], [1, 2, 3]], fn(bones) {
    let #(state, effects) =
      create_with(bone_values: bones, labels: [1], characters: [], slots: 2)
    assert_failed_without_a_write(
      effects:,
      refusal: select.BoneCountWrong(expected: 2, given: list.length(bones)),
      result: 4,
      why: "opcode.0x25b.counts: the real client sends one float for each entry of the race and sex's bone list, here 2, so another number is not its request",
    )
    assert state == idle([])
  })
  let #(_, effects) =
    create_with(
      bone_values: [0x3F800000, 0xBF000000],
      labels: [1],
      characters: [],
      slots: 2,
    )
  assert stored(effects) != []
    as "opcode.0x25b.counts: the race and sex's own number is accepted"
}

pub fn labels_the_client_does_not_send_are_refused_with_result_4_test() -> Nil {
  use <- owned_test.run(5000)
  let bones = [0x3F800000, 0xBF000000]
  let refused = fn(labels, refusal, why) {
    let #(_, effects) =
      create_with(bone_values: bones, labels:, characters: [], slots: 2)
    assert_failed_without_a_write(effects:, refusal:, result: 4, why:)
  }
  refused(
    [1, 2, 1],
    select.LabelRefused(customisation.LabelRepeated(1)),
    "opcode.0x25b.counts: each label at most once",
  )
  refused(
    [9],
    select.LabelRefused(customisation.LabelUnknown(9)),
    "opcode.0x25b.counts: only a label the CharacterCustomizationLabel table holds",
  )
  refused(
    [3],
    select.LabelRefused(customisation.LabelOfAnotherFaction(3)),
    "opcode.0x25b.counts: only a label whose faction2Id is 0 or the character's faction, here 167 (label 3 is for 166)",
  )
  let #(_, effects) =
    create_with(bone_values: bones, labels: [1, 4], characters: [], slots: 2)
  assert stored(effects) != []
    as "labels for no faction and for the character's faction are accepted"
}

pub fn an_account_that_holds_as_many_characters_as_it_has_slots_is_refused_with_result_9_test() -> Nil {
  use <- owned_test.run(5000)
  let bones = [0x3F800000, 0xBF000000]
  let #(state, effects) =
    create_with(
      bone_values: bones,
      labels: [1],
      characters: [own(11, "Ab Cd"), own(12, "Ef Gh")],
      slots: 2,
    )
  assert_failed_without_a_write(
    effects:,
    refusal: select.AccountFull(2),
    result: 9,
    why: "lua.CharacterSelection.OnLoadFromCharacter: the client offers a create only while the slots exceed the characters; the server's own check answers CreateFailed_AccountFull, 9",
  )
  assert state == idle([own(11, "Ab Cd"), own(12, "Ef Gh")])
  let #(_, effects) =
    create_with(
      bone_values: bones,
      labels: [1],
      characters: [own(11, "Ab Cd")],
      slots: 2,
    )
  assert stored(effects) != [] as "an account with a free slot may create"
}
