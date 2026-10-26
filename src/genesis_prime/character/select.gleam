//// Character select: what the server does while a player lists, creates,
//// renames, deletes and plays the characters of the account. A rule: the state
//// and an input in, the new state and the effects out, with no process, no
//// database and no clock; the connection's handler carries the effects out in
//// order and feeds the answers back as inputs.
////
//// The client sends one request at a time and waits for its answer before the
//// next (the states of HandleCharacterSelectMessage 0x140020EA0: it sends only
//// while idle). A request that arrives while the server waits for an answer,
//// before the list was sent or after the player entered the world is a
//// breach, and the connection is closed. A request that cannot be done is
//// answered with the failure result of its own message and logged with its
//// reason, and writes nothing.
////
//// A character is only ever touched through the account's own list: the state
//// holds the characters of the account and a request for any other character
//// is refused. The store's statements also name the account.

import genesis_prime/character/character.{
  type Character, type NewCharacter, type Place, Appearance, NewCharacter,
}
import genesis_prime/character/customisation.{
  type Customisation, type LabelProblem,
}
import genesis_prime/character/name.{type NameError}
import genesis_prime/character/server_message.{
  type ServerMessage, CharacterListed, CreateResult, DeleteResult, PlayRefused,
  RenameResult,
}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/create_character.{type CreateCharacter}
import genesis_prime/message/create_character_result.{
  type CreateCharacterResult, CreateCharacterResult,
}
import genesis_prime/message/delete_character.{type DeleteCharacter}
import genesis_prime/message/delete_character_result.{
  type DeleteCharacterResult, DeleteCharacterResult,
}
import genesis_prime/message/play_character.{type PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/rename_character.{type RenameCharacter}
import genesis_prime/message/rename_character_result.{
  type RenameCharacterResult, RenameCharacterResult,
}
import genesis_prime/table/character_creation.{type CharacterCreation}
import gleam/bool
import gleam/int
import gleam/list
import gleam/result

/// The results of messages 0xDC, 0x14B and 0xE6, each named by its name in
/// PreGameLib.CodeEnumCharacterModifyResults, the enum the client's Lua reads
/// them as.
const delete_ok = 0

const delete_failed = 1

const create_ok = 3

const create_failed = 4

const create_failed_account_full = 9

const create_failed_unique_name = 6

const create_failed_invalid_name = 10

const create_failed_internal = 12

const rename_failed = 13

const rename_failed_internal = 14

const rename_failed_invalid_name = 15

const rename_failed_unique_name = 16

const rename_ok = 18

/// The values of message 0x162, each named by its name in PreGameLib.
/// CodeEnumCharacterSelectResults.
const select_failed_rename = 1

const select_failed = 2

const select_failed_disabled = 3

/// The most customisation values a character holds: the character list reads
/// their count in 4 bits (ReadCharacterListEntry 0x14007F720).
const most_customisations = 15

/// The facts the rule reads beyond its state, made by the connection's handler
/// for each input. `creation` is the client's CharacterCreation table by id.
/// `start` is where a character made from a row starts, and none when the
/// server has no starting place for it. `level_of` is the level an amount of
/// experience gives, as the client works it (GetLevelForExperience
/// 0x140029820; a character starts with the row's `xp`). `server_time` is the server's time as a Windows FILETIME,
/// and `realm_id` the realm the connection is on. `customisation` is what the
/// client's tables say a create request may carry and `character_slots` how
/// many characters an account may hold.
pub type Context {
  Context(
    creation: fn(Int) -> Result(CharacterCreation, Nil),
    start: fn(CharacterCreation) -> Result(Place, Nil),
    level_of: fn(Int) -> Int,
    customisation: Customisation,
    character_slots: Int,
    server_time: Int,
    realm_id: Int,
  )
}

/// What character select is doing.
pub type Status {
  /// The client has not asked for character select yet.
  NotStarted
  /// The server waits for the account's characters.
  Loading
  /// The player may ask for anything.
  Idle
  /// The server waits for the store to create a character.
  Creating
  /// The server waits for the store to rename a character.
  Renaming(character_id: Int)
  /// The server waits for the store to delete a character.
  Deleting(character_id: Int)
  /// The player chose a character: the client leaves character select for the
  /// world, so no request is taken until the entry is refused.
  Entering
  /// A write was answered `Unavailable`, so it may or may not have been done.
  /// The server waits for the account's characters again, and the player is
  /// sent `owed`, the failure of the request, with the list the store holds.
  Reloading(owed: ServerMessage)
}

/// An account's character select.
pub type State {
  State(account_id: Int, characters: List(Character), status: Status)
}

/// A request of the player.
pub type Request {
  CreateRequested(CreateCharacter)
  RenameRequested(RenameCharacter)
  DeleteRequested(DeleteCharacter)
  PlayRequested(PlayCharacter)
}

/// What the store is asked to do.
pub type Command {
  /// Load the account's characters.
  LoadCharacters(account_id: Int)
  /// Save a new character.
  InsertCharacter(NewCharacter)
  /// Give a character of the account a new name.
  RenameStored(account_id: Int, character_id: Int, name: String)
  /// Delete a character of the account.
  DeleteStored(account_id: Int, character_id: Int)
}

/// What the store answers.
pub type Answer {
  Loaded(List(Character))
  Inserted(Character)
  Renamed(Character)
  Deleted(character_id: Int)
  /// Another character has the name.
  NameInUse
  /// The account has no such character.
  NotFound
  /// The database could not do it.
  Unavailable
  /// The command was sent to the database and nothing came back in the longest
  /// time a command can take, so the server cannot tell what it did. Only the
  /// store's worker gives it, never the store.
  Unknown
}

/// What can happen to character select.
pub type Input {
  /// The client sent message 0x7E0: character select starts.
  Started
  /// The player asked for something.
  Requested(Request)
  /// The store answered the last command.
  Stored(Answer)
  /// The world refused the character the player chose to play.
  WorldEntryRefused
}

/// Why a request was refused, for the log. Each is the answer of one result
/// of its message, in one place (`create_result`, `rename_result`,
/// `delete_result` and `play_refused`).
pub type Refusal {
  NameRefused(NameError)
  /// No CharacterCreation row has the id.
  CreationUnknown(creation_id: Int)
  /// The row is not one the account may make a character from: it is not
  /// enabled, it needs an entitlement or it costs account currency, and an
  /// account holds none.
  CreationNotOffered(creation_id: Int)
  PathOutOfRange(path: Int)
  TooManyCustomisations(count: Int)
  /// The server has no place for a character of the row to start in.
  NoStartingPlace(creation_id: Int)
  /// The request holds a number of bone values other than the race and sex's
  /// own, which the real client never sends.
  BoneCountWrong(expected: Int, given: Int)
  /// The request's labels are not ones the real client sends.
  LabelRefused(LabelProblem)
  /// The account holds as many characters as it has slots.
  AccountFull(slots: Int)
  NameTaken
  /// The character is not one of the account's.
  NotYourCharacter(character_id: Int)
  /// The character is disabled, so it cannot be played.
  CharacterDisabled(character_id: Int)
  /// The character must be renamed before it can be played.
  CharacterRequiresRename(character_id: Int)
  /// The database could not do what was asked: an outside failure, not the
  /// player's mistake.
  StoreUnavailable
}

/// The database did not answer when character select needed the account's
/// characters: an outside failure the connection cannot go on without, never
/// the player's breach.
pub type Outage {
  /// The characters of the account could not be loaded for the list.
  ListNotLoaded
  /// The characters could not be loaded again after a write that was answered
  /// `Unavailable`, so the server cannot tell what that write did.
  ListNotReloaded
  /// A write that was sent to the database got no answer in the longest time a
  /// write can take, so the server cannot tell whether it was done.
  WriteNotAnswered
}

/// A message or an answer that a correct client and server never produce.
pub type Breach {
  /// A request before the client started character select.
  RequestBeforeStart
  /// A request while the server waited for an answer or after the player
  /// entered the world.
  RequestWhileBusy(status: Status)
  /// An answer nobody asked for.
  AnswerNobodyAskedFor(status: Status)
  /// A second start.
  StartedTwice
}

/// What the connection's handler must do, in order.
pub type Effect {
  /// Ask the store; its answer comes back as `Stored`.
  Store(Command)
  /// Send the player a message.
  Send(ServerMessage)
  /// Start the world entry for the character the player chose.
  BeginWorldEntry(Character)
  /// Log why a request was refused, with the account: warning for the
  /// player's mistake, error for `StoreUnavailable`.
  Log(Refusal)
  /// Log the breach and close the connection.
  Close(Breach)
  /// Log the outage as an error and close the connection.
  Abandon(Outage)
}

/// Character select of an account that has not started.
pub fn new(account_id account_id: Int) -> State {
  State(account_id:, characters: [], status: NotStarted)
}

/// The state and the effects after an input.
pub fn decide(
  state state: State,
  input input: Input,
  context context: Context,
) -> #(State, List(Effect)) {
  case input {
    Started -> start(state)
    Requested(request) -> requested(state:, request:, context:)
    Stored(answer) -> answered(state:, answer:, context:)
    WorldEntryRefused -> world_entry_refused(state)
  }
}

fn start(state: State) -> #(State, List(Effect)) {
  case state.status {
    NotStarted -> #(State(..state, status: Loading), [
      Store(LoadCharacters(account_id: state.account_id)),
    ])
    Loading
    | Idle
    | Creating
    | Renaming(_)
    | Deleting(_)
    | Entering
    | Reloading(_) -> #(state, [Close(StartedTwice)])
  }
}

fn world_entry_refused(state: State) -> #(State, List(Effect)) {
  case state.status {
    Entering -> #(State(..state, status: Idle), [])
    NotStarted
    | Loading
    | Idle
    | Creating
    | Renaming(_)
    | Deleting(_)
    | Reloading(_) -> #(state, [Close(AnswerNobodyAskedFor(state.status))])
  }
}

fn requested(
  state state: State,
  request request: Request,
  context context: Context,
) -> #(State, List(Effect)) {
  case state.status {
    Idle ->
      case request {
        CreateRequested(create) ->
          start_creating(state:, request: create, context:)
        RenameRequested(rename) -> start_renaming(state:, request: rename)
        DeleteRequested(delete) -> start_deleting(state:, request: delete)
        PlayRequested(play) -> start_playing(state:, request: play)
      }
    NotStarted -> #(state, [Close(RequestBeforeStart)])
    Loading | Creating | Renaming(_) | Deleting(_) | Entering | Reloading(_) -> #(
      state,
      [Close(RequestWhileBusy(state.status))],
    )
  }
}

fn start_creating(
  state state: State,
  request request: CreateCharacter,
  context context: Context,
) -> #(State, List(Effect)) {
  case
    plan_creation(
      account_id: state.account_id,
      characters: state.characters,
      request:,
      context:,
    )
  {
    Ok(new) -> #(State(..state, status: Creating), [
      Store(InsertCharacter(new)),
    ])
    Error(refusal) -> #(state, [
      Log(refusal),
      Send(CreateResult(create_failure(refusal))),
    ])
  }
}

/// The character a create request makes, or why it cannot be made: the name
/// passes the client's rule, the CharacterCreation row exists and is one the
/// account may make a character from, the path is 0 to 3 and the customisation
/// fits the character list. A new character has the row's class, race, sex and
/// faction, its experience and the level that gives, and the place the
/// server starts it at.
fn plan_creation(
  account_id account_id: Int,
  characters characters: List(Character),
  request request: CreateCharacter,
  context context: Context,
) -> Result(NewCharacter, Refusal) {
  use Nil <- result.try(
    name.check(request.name) |> result.map_error(NameRefused),
  )
  use row <- result.try(
    context.creation(request.creation_id)
    |> result.replace_error(CreationUnknown(request.creation_id)),
  )
  use Nil <- result.try(check_offered(row))
  use Nil <- result.try(check_slots(characters:, context:))
  use Nil <- result.try(case request.path > 3 {
    True -> Error(PathOutOfRange(request.path))
    False -> Ok(Nil)
  })
  let customisations = list.length(request.customisation_labels)
  use Nil <- result.try(case customisations > most_customisations {
    True -> Error(TooManyCustomisations(customisations))
    False -> Ok(Nil)
  })
  use Nil <- result.try(check_bones(request:, row:, context:))
  use Nil <- result.try(
    customisation.check_labels(
      context.customisation,
      request.customisation_labels,
      row.faction_id,
    )
    |> result.map_error(LabelRefused),
  )
  use place <- result.try(
    context.start(row) |> result.replace_error(NoStartingPlace(row.id)),
  )
  Ok(NewCharacter(
    account_id:,
    name: request.name,
    creation_id: row.id,
    gender: row.sex,
    race_id: row.race_id,
    class_id: row.class_id,
    faction_id: row.faction_id,
    experience: row.xp,
    level: context.level_of(row.xp),
    path: request.path,
    place:,
    appearance: Appearance(
      customisation_labels: request.customisation_labels,
      customisation_values: request.customisation_values,
      bone_values: request.bone_values,
    ),
  ))
}

/// An account may hold as many characters as it has slots: the Hybrid
/// system's CharacterSlots value (`character_slots`). The client only hides its
/// create entry when the account is full, so the server's own check refuses.
fn check_slots(
  characters characters: List(Character),
  context context: Context,
) -> Result(Nil, Refusal) {
  use <- bool.guard(
    when: list.length(characters) >= context.character_slots,
    return: Error(AccountFull(context.character_slots)),
  )
  Ok(Nil)
}

/// The real client sends one bone value for each entry of the bone list of the
/// race and sex of the row it was asked to create from, so any other number is
/// not its request (opcode.0x25b.counts).
fn check_bones(
  request request: CreateCharacter,
  row row: CharacterCreation,
  context context: Context,
) -> Result(Nil, Refusal) {
  let expected =
    customisation.bone_count(context.customisation, row.race_id, row.sex)
  let given = list.length(request.bone_values)
  use <- bool.guard(
    when: given != expected,
    return: Error(BoneCountWrong(expected:, given:)),
  )
  Ok(Nil)
}

/// A row is offered to an account when it is enabled, needs no entitlement and
/// costs no account currency: the client offers a row that is enabled here or
/// by the server (opcode.0x117), refuses one with an entitlementIdRequired to
/// an account without it and one that costs account currency to an account
/// that cannot pay (LuaCreateCharacter 0x140023E90), and an account holds
/// neither an entitlement nor currency.
fn check_offered(row: CharacterCreation) -> Result(Nil, Refusal) {
  use <- bool.guard(
    when: row.enabled
      && row.entitlement_id_required == 0
      && row.account_currency_amount_cost == 0,
    return: Ok(Nil),
  )
  Error(CreationNotOffered(row.id))
}

fn start_renaming(
  state state: State,
  request request: RenameCharacter,
) -> #(State, List(Effect)) {
  let id = request.character_id
  case owned(state, id) {
    Error(Nil) -> #(state, [
      Log(NotYourCharacter(id)),
      Send(RenameResult(rename_failure(request, NotYourCharacter(id)))),
    ])
    Ok(_) ->
      case name.check(request.name) {
        Error(why) -> #(state, [
          Log(NameRefused(why)),
          Send(RenameResult(rename_failure(request, NameRefused(why)))),
        ])
        Ok(Nil) -> #(State(..state, status: Renaming(id)), [
          Store(RenameStored(
            account_id: state.account_id,
            character_id: id,
            name: request.name,
          )),
        ])
      }
  }
}

fn start_deleting(
  state state: State,
  request request: DeleteCharacter,
) -> #(State, List(Effect)) {
  let id = request.character_id
  case owned(state, id) {
    Error(Nil) -> #(state, [
      Log(NotYourCharacter(id)),
      Send(DeleteResult(delete_failure(NotYourCharacter(id)))),
    ])
    Ok(_) -> #(State(..state, status: Deleting(id)), [
      Store(DeleteStored(account_id: state.account_id, character_id: id)),
    ])
  }
}

fn start_playing(
  state state: State,
  request request: PlayCharacter,
) -> #(State, List(Effect)) {
  let id = request.character_id
  case owned(state, id) {
    Error(Nil) -> #(state, [
      Log(NotYourCharacter(id)),
      Send(PlayRefused(PlayCharacterRefused(field_1: select_failed))),
    ])
    Ok(chosen) if chosen.disabled -> #(state, [
      Log(CharacterDisabled(id)),
      Send(PlayRefused(PlayCharacterRefused(field_1: select_failed_disabled))),
    ])
    Ok(chosen) if chosen.requires_rename -> #(state, [
      Log(CharacterRequiresRename(id)),
      Send(PlayRefused(PlayCharacterRefused(field_1: select_failed_rename))),
    ])
    Ok(chosen) -> #(State(..state, status: Entering), [BeginWorldEntry(chosen)])
  }
}

/// The account's character with the id, from the list character select holds.
fn owned(state: State, id: Int) -> Result(Character, Nil) {
  list.find(state.characters, fn(character) { character.id == id })
}

fn answered(
  state state: State,
  answer answer: Answer,
  context context: Context,
) -> #(State, List(Effect)) {
  case state.status {
    Loading -> loaded(state:, answer:, context:)
    Creating -> created(state:, answer:)
    Renaming(id) -> renamed(state:, id:, answer:)
    Deleting(id) -> deleted(state:, id:, answer:)
    Reloading(owed:) -> reloaded(state:, owed:, answer:, context:)
    NotStarted | Idle | Entering -> unexpected(state, answer)
  }
}

fn unexpected(state: State, _answer: Answer) -> #(State, List(Effect)) {
  #(state, [Close(AnswerNobodyAskedFor(state.status))])
}

fn loaded(
  state state: State,
  answer answer: Answer,
  context context: Context,
) -> #(State, List(Effect)) {
  case answer {
    Loaded(characters) -> #(State(..state, characters:, status: Idle), [
      Send(CharacterListed(character_list(characters:, context:))),
    ])
    Unavailable | Unknown -> #(state, [Abandon(ListNotLoaded)])
    Inserted(_) | Renamed(_) | Deleted(_) | NameInUse | NotFound ->
      unexpected(state, answer)
  }
}

/// The answer to the read after a write that was answered `Unavailable`: the
/// characters the store holds, and with them the failure the player is
/// owed, then the list, so the client's list is the store's. A store that is
/// away again leaves the server not knowing what the write did, so the
/// connection ends.
fn reloaded(
  state state: State,
  owed owed: ServerMessage,
  answer answer: Answer,
  context context: Context,
) -> #(State, List(Effect)) {
  case answer {
    Loaded(characters) -> #(State(..state, characters:, status: Idle), [
      Send(owed),
      Send(CharacterListed(character_list(characters:, context:))),
    ])
    Unavailable | Unknown -> #(state, [Abandon(ListNotReloaded)])
    Inserted(_) | Renamed(_) | Deleted(_) | NameInUse | NotFound ->
      unexpected(state, answer)
  }
}

/// A write was answered `Unavailable`: it may have been done after the
/// deadline, so the failure is answered only once the account's characters
/// have been read again.
fn reload(
  state state: State,
  owed owed: ServerMessage,
) -> #(State, List(Effect)) {
  #(State(..state, status: Reloading(owed:)), [
    Log(StoreUnavailable),
    Store(LoadCharacters(account_id: state.account_id)),
  ])
}

/// Message 0x117 for the characters: the server's time, the characters and
/// the realm, with nothing enabled or disabled beyond the rows' own enabled
/// column, no removal pending (the server ends an account's old session and its
/// unit before it lists, so no character of the account is in the world), no
/// reservations, no restriction and none of the values whose meaning the
/// client's code does not show.
fn character_list(
  characters characters: List(Character),
  context context: Context,
) -> character_list.CharacterList {
  CharacterList(
    server_time: context.server_time,
    characters: list.map(characters, character.list_entry),
    enabled_creation_ids: [],
    disabled_creation_ids: [],
    realm_id: context.realm_id,
    pending_removal_realm_id: 0,
    pending_removal_character_id: 0,
    pending_removal_time: 0,
    reservations: 0,
    field_10: 0,
    field_11: 0,
    faction_restriction: 0,
    free_level_50_available: 0,
  )
}

fn created(
  state state: State,
  answer answer: Answer,
) -> #(State, List(Effect)) {
  case answer {
    Inserted(new) -> #(
      State(
        ..state,
        characters: list.append(state.characters, [new]),
        status: Idle,
      ),
      [
        Send(
          CreateResult(CreateCharacterResult(
            character_id: new.id,
            field_2: 0,
            result: create_ok,
          )),
        ),
      ],
    )
    NameInUse -> create_refused(state, NameTaken)
    Unavailable ->
      reload(state:, owed: CreateResult(create_failure(StoreUnavailable)))
    Unknown -> write_not_answered(state)
    Loaded(_) | Renamed(_) | Deleted(_) | NotFound -> unexpected(state, answer)
  }
}

/// A write got no answer in the longest time a write can take, so what it did
/// is not known and the player is told nothing about it: the connection ends,
/// and the client's next connection lists the characters the store holds.
fn write_not_answered(state: State) -> #(State, List(Effect)) {
  #(state, [Abandon(WriteNotAnswered)])
}

fn create_refused(state: State, refusal: Refusal) -> #(State, List(Effect)) {
  #(State(..state, status: Idle), [
    Log(refusal),
    Send(CreateResult(create_failure(refusal))),
  ])
}

fn renamed(
  state state: State,
  id id: Int,
  answer answer: Answer,
) -> #(State, List(Effect)) {
  case answer {
    Renamed(character) -> #(
      State(
        ..state,
        characters: list.map(state.characters, fn(listed) {
          case listed.id == character.id {
            True -> character
            False -> listed
          }
        }),
        status: Idle,
      ),
      [
        Send(
          RenameResult(RenameCharacterResult(
            result: rename_ok,
            character_id: character.id,
            name: character.name,
          )),
        ),
      ],
    )
    NameInUse -> rename_refused(state:, id:, refusal: NameTaken)
    NotFound -> rename_refused(state:, id:, refusal: NotYourCharacter(id))
    Unavailable ->
      reload(
        state:,
        owed: RenameResult(rename_failure_of(
          state:,
          id:,
          refusal: StoreUnavailable,
        )),
      )
    Unknown -> write_not_answered(state)
    Loaded(_) | Inserted(_) | Deleted(_) -> unexpected(state, answer)
  }
}

fn rename_refused(
  state state: State,
  id id: Int,
  refusal refusal: Refusal,
) -> #(State, List(Effect)) {
  #(State(..state, status: Idle), [
    Log(refusal),
    Send(RenameResult(rename_failure_of(state:, id:, refusal:))),
  ])
}

/// The answer to a rename the store did not do: the result of the refusal
/// with the name the character has in the list.
fn rename_failure_of(
  state state: State,
  id id: Int,
  refusal refusal: Refusal,
) -> RenameCharacterResult {
  let name = case owned(state, id) {
    Ok(character) -> character.name
    Error(Nil) -> ""
  }
  RenameCharacterResult(result: rename_result(refusal), character_id: id, name:)
}

fn deleted(
  state state: State,
  id id: Int,
  answer answer: Answer,
) -> #(State, List(Effect)) {
  case answer {
    Deleted(character_id) -> #(
      State(
        ..state,
        characters: list.filter(state.characters, fn(listed) {
          listed.id != character_id
        }),
        status: Idle,
      ),
      [
        Send(DeleteResult(DeleteCharacterResult(result: delete_ok, field_2: 0))),
      ],
    )
    NotFound -> delete_refused(state, NotYourCharacter(id))
    Unavailable ->
      reload(state:, owed: DeleteResult(delete_failure(StoreUnavailable)))
    Unknown -> write_not_answered(state)
    Loaded(_) | Inserted(_) | Renamed(_) | NameInUse ->
      unexpected(state, answer)
  }
}

fn delete_refused(state: State, refusal: Refusal) -> #(State, List(Effect)) {
  #(State(..state, status: Idle), [
    Log(refusal),
    Send(DeleteResult(delete_failure(refusal))),
  ])
}

/// The one result of message 0xDC each refusal is answered with, in one
/// place. A name the rule refuses is the client's own InvalidName, and a name
/// another character has is UniqueName. A row, path or customisation the
/// client's own creation never sends is the general CreateFailed. What the
/// server cannot do (no starting place, a database that failed) is Internal,
/// never the player's mistake.
fn create_failure(refusal: Refusal) -> CreateCharacterResult {
  let result = case refusal {
    NameRefused(_) -> create_failed_invalid_name
    NameTaken -> create_failed_unique_name
    CreationUnknown(_)
    | CreationNotOffered(_)
    | PathOutOfRange(_)
    | TooManyCustomisations(_)
    | NotYourCharacter(_)
    | CharacterDisabled(_)
    | CharacterRequiresRename(_)
    | BoneCountWrong(..)
    | LabelRefused(_) -> create_failed
    AccountFull(_) -> create_failed_account_full
    NoStartingPlace(_) | StoreUnavailable -> create_failed_internal
  }
  CreateCharacterResult(character_id: 0, field_2: 0, result:)
}

/// The one result of message 0x14B each refusal is answered with: never
/// RenameOk, which renames. A name the rule refuses is the client's own
/// RenameFailed_InvalidName, a name another character has is UniqueName and a
/// database that failed is Internal; any other refusal is the general
/// RenameFailed.
fn rename_result(refusal: Refusal) -> Int {
  case refusal {
    NameRefused(_) -> rename_failed_invalid_name
    NameTaken -> rename_failed_unique_name
    StoreUnavailable -> rename_failed_internal
    CreationUnknown(_)
    | CreationNotOffered(_)
    | PathOutOfRange(_)
    | TooManyCustomisations(_)
    | NoStartingPlace(_)
    | NotYourCharacter(_)
    | CharacterDisabled(_)
    | CharacterRequiresRename(_)
    | BoneCountWrong(..)
    | LabelRefused(_)
    | AccountFull(_) -> rename_failed
  }
}

fn rename_failure(
  request: RenameCharacter,
  refusal: Refusal,
) -> RenameCharacterResult {
  RenameCharacterResult(
    result: rename_result(refusal),
    character_id: request.character_id,
    name: request.name,
  )
}

/// The result of message 0xE6 for every refusal: DeleteFailed, never
/// DeleteOk, which deletes.
fn delete_failure(refusal: Refusal) -> DeleteCharacterResult {
  let result = case refusal {
    NameRefused(_)
    | CreationUnknown(_)
    | CreationNotOffered(_)
    | PathOutOfRange(_)
    | TooManyCustomisations(_)
    | NoStartingPlace(_)
    | BoneCountWrong(..)
    | LabelRefused(_)
    | AccountFull(_)
    | NameTaken
    | NotYourCharacter(_)
    | CharacterDisabled(_)
    | CharacterRequiresRename(_)
    | StoreUnavailable -> delete_failed
  }
  DeleteCharacterResult(result:, field_2: 0)
}

/// The sentence the log line of a refusal holds.
pub fn describe_refusal(refusal refusal: Refusal) -> String {
  case refusal {
    NameRefused(name.Empty) -> "the name is empty"
    NameRefused(name.TooShort(characters:)) ->
      "the name has "
      <> int.to_string(characters)
      <> " characters, fewer than the client's rule allows"
    NameRefused(name.TooLong(characters:)) ->
      "the name has "
      <> int.to_string(characters)
      <> " characters, more than the client's rule allows"
    NameRefused(name.NotALetter(character:)) ->
      "the name holds "
      <> character
      <> ", which is neither a letter nor a space"
    NameRefused(name.SpaceAtAnEnd) -> "the name starts or ends with a space"
    NameRefused(name.SpacesNotOne(spaces:)) ->
      "the name holds "
      <> int.to_string(spaces)
      <> " spaces, and the client's rule asks for one"
    CreationUnknown(creation_id:) ->
      "no CharacterCreation row has the id " <> int.to_string(creation_id)
    CreationNotOffered(creation_id:) ->
      "the CharacterCreation row "
      <> int.to_string(creation_id)
      <> " is not enabled, or needs an entitlement or account currency"
    PathOutOfRange(path:) -> "the path " <> int.to_string(path) <> " is above 3"
    TooManyCustomisations(count:) ->
      "the character has "
      <> int.to_string(count)
      <> " customisations, more than the character list holds"
    NoStartingPlace(creation_id:) ->
      "the server has no starting place for the CharacterCreation row "
      <> int.to_string(creation_id)
    BoneCountWrong(expected:, given:) ->
      "the request holds "
      <> int.to_string(given)
      <> " bone values, and the race and sex have "
      <> int.to_string(expected)
    LabelRefused(customisation.LabelRepeated(label_id:)) ->
      "the customisation label " <> int.to_string(label_id) <> " is given twice"
    LabelRefused(customisation.LabelUnknown(label_id:)) ->
      "the customisation label "
      <> int.to_string(label_id)
      <> " is not in the client's table"
    LabelRefused(customisation.LabelOfAnotherFaction(label_id:)) ->
      "the customisation label "
      <> int.to_string(label_id)
      <> " is for the other faction"
    AccountFull(slots:) ->
      "the account holds "
      <> int.to_string(slots)
      <> " characters, as many as it has slots"
    NameTaken -> "another character has the name"
    NotYourCharacter(character_id:) ->
      "the character " <> int.to_string(character_id) <> " is not the account's"
    CharacterDisabled(character_id:) ->
      "the character " <> int.to_string(character_id) <> " is disabled"
    CharacterRequiresRename(character_id:) ->
      "the character "
      <> int.to_string(character_id)
      <> " must be renamed before it can be played"
    StoreUnavailable -> "the database could not do it"
  }
}

/// The sentence the log line of an outage holds.
pub fn describe_outage(outage outage: Outage) -> String {
  case outage {
    ListNotLoaded ->
      "the database did not give the account's characters for the list"
    ListNotReloaded ->
      "the database did not give the account's characters again after a write it did not answer, so what the write did is not known"
    WriteNotAnswered ->
      "a write was sent to the database and no answer came in the longest time a write can take, so what it did is not known"
  }
}

/// The sentence the log line of a breach holds.
pub fn describe_breach(breach breach: Breach) -> String {
  case breach {
    RequestBeforeStart ->
      "a request came before the client started character select (message 0x7E0)"
    RequestWhileBusy(status:) ->
      "a request came while character select was " <> describe_status(status)
    AnswerNobodyAskedFor(status:) ->
      "an answer came while character select was " <> describe_status(status)
    StartedTwice -> "the client started character select twice"
  }
}

fn describe_status(status: Status) -> String {
  case status {
    NotStarted -> "not started"
    Loading -> "waiting for the account's characters"
    Idle -> "idle"
    Creating -> "waiting for a character to be created"
    Renaming(character_id:) ->
      "waiting for the character "
      <> int.to_string(character_id)
      <> " to be renamed"
    Deleting(character_id:) ->
      "waiting for the character "
      <> int.to_string(character_id)
      <> " to be deleted"
    Entering -> "entering the world"
    Reloading(_) -> "waiting for the account's characters after a write failed"
  }
}
