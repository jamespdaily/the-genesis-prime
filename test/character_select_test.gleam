//// Character select as a rule: the state and an input in, the new state and the
//// effects out. Expected values come from the client's records: the layouts and
//// results of messages 0x117, 0xdc, 0x14b, 0xe6, 0x7dd and 0x162 (opcode.*), the
//// states the client waits in (HandleCharacterSelectMessage 0x140020EA0: it sends
//// one request while idle and waits for its answer), the client's own refusals
//// in LuaCreateCharacter 0x140023E90 and LuaRenameCharacter 0x140024DD0, and
//// the CharacterCreation row (opcode.0x25b: it gives class, race, sex and
//// faction). A result the client's code does not give a meaning is tested only
//// for what it must not be: the client shows its general error for any create
//// result but 3 (created) and 6 (HandleMessage00DC 0x140021FB0).

import character_support
import client_tables
import environment
import genesis_prime/character/character.{
  type Character, Appearance, Character, NewCharacter,
}
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
  CharacterListed, CreateResult, DeleteResult, PlayRefused, RenameResult,
}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/create_character.{
  type CreateCharacter, CreateCharacter,
}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/table/character_creation
import genesis_prime/table/loader/store as table_store
import gleam/erlang/reference
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
  let assert [Send(CreateResult(answer))] =
    list.filter(effects, fn(effect) {
      case effect {
        Send(CreateResult(_)) -> True
        _ -> False
      }
    })
    as "one create answer is sent"
  answer.result
}

fn assert_failed_without_a_write(
  effects effects: List(select.Effect),
  refusal refusal: select.Refusal,
  why why: String,
) -> Nil {
  assert list.contains(effects, Log(refusal))
    as { why <> ": the reason is logged" }
  assert !list.any(effects, fn(effect) {
    case effect {
      Store(_) -> True
      _ -> False
    }
  })
    as { why <> ": nothing is written" }
  let result = create_result_of(effects)
  assert result != 3 as { why <> ": the answer is not the result for created" }
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
    why: "opcode.0xad: a character enters a world at a position, so a character with none cannot be made",
  )
}

pub fn a_name_another_character_has_is_refused_and_not_listed_test() -> Nil {
  use <- owned_test.run(5000)
  let creating = State(..idle([]), status: select.Creating)
  let #(state, effects) = select.decide(creating, Stored(NameInUse), context())
  assert list.contains(effects, Log(NameTaken)) as "the reason is logged"
  assert create_result_of(effects) != 3 as "the answer is not created"
  assert state == idle([]) as "nothing was added"
}

pub fn a_database_that_could_not_save_is_not_the_players_mistake_test() -> Nil {
  use <- owned_test.run(5000)
  let creating = State(..idle([]), status: select.Creating)
  let #(state, effects) =
    select.decide(creating, Stored(Unavailable), context())
  assert list.contains(effects, Log(StoreUnavailable))
    as "an outside failure is logged as one, never as a refusal of the request"
  assert create_result_of(effects) != 3 as "the answer is not created"
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
  let assert [Send(RenameResult(answer))] =
    list.filter(effects, fn(effect) {
      case effect {
        Send(_) -> True
        _ -> False
      }
    })
    as "one rename answer is sent"
  assert answer.result != 18 as "opcode.0x14b: only result 18 renames"
  assert state == idle([own(11, "Ab Cd")]) as "the character keeps its name"
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
  let assert [Send(DeleteResult(answer))] =
    list.filter(effects, fn(effect) {
      case effect {
        Send(_) -> True
        _ -> False
      }
    })
    as "one delete answer is sent"
  assert answer.result != 0
    as "opcode.0xe6: only result 0 removes the character"
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
    assert !list.any(effects, fn(effect) {
      case effect {
        Store(_) | BeginWorldEntry(_) -> True
        _ -> False
      }
    })
      as "nothing is written and no world is entered"
  })
  let assert [_, Send(RenameResult(renamed))] = rename
    as "the rename is answered"
  assert renamed.result != 18 as "opcode.0x14b: only result 18 renames"
  let assert [_, Send(DeleteResult(deleted))] = delete
    as "the delete is answered"
  assert deleted.result != 0 as "opcode.0xe6: only result 0 deletes"
  assert list.any(play, fn(effect) {
    case effect {
      Send(PlayRefused(_)) -> True
      _ -> False
    }
  })
    as "opcode.0x162: playing a character that cannot be played is answered with the refusal"
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
      _ -> state
    }
  })
}

pub fn every_row_of_the_clients_character_creation_table_makes_a_character_of_its_own_class_race_sex_and_faction_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let assert Ok(tables) =
    table_store.load(
      under: reference.new(),
      from: client_tables.folder(),
      entries: [character_creation.entry()],
      requirements: [],
    )
    as "the CharacterCreation table did not load from the client's files"
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
    let request = CreateCharacter(..create_request(), creation_id: row.id)
    let #(_, effects) =
      select.decide(
        idle([]),
        Requested(CreateRequested(request)),
        character_support.context(rows: rows),
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
    _ -> 0
  }
}
