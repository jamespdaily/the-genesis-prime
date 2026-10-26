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
  type Character, type NewCharacter, type Place,
}
import genesis_prime/character/name.{type NameError}
import genesis_prime/character/server_message.{type ServerMessage}
import genesis_prime/message/create_character.{type CreateCharacter}
import genesis_prime/message/delete_character.{type DeleteCharacter}
import genesis_prime/message/play_character.{type PlayCharacter}
import genesis_prime/message/rename_character.{type RenameCharacter}
import genesis_prime/table/character_creation.{type CharacterCreation}

/// The most customisation values a character holds: the character list reads
/// their count in 4 bits (ReadCharacterListEntry 0x14007F720).
pub const most_customisations = 15

/// The facts the rule reads beyond its state, made by the connection's handler
/// for each input. `creation` is the client's CharacterCreation table by id.
/// `start` is where a character made from a row starts, and none when the
/// server has no starting place for it. `level_of` is the level an amount of
/// experience gives, by the client's XpPerLevel table (a character starts with
/// the row's `xp`). `server_time` is the server's time as a Windows FILETIME,
/// and `realm_id` the realm the connection is on.
pub type Context {
  Context(
    creation: fn(Int) -> Result(CharacterCreation, Nil),
    start: fn(CharacterCreation) -> Result(Place, Nil),
    level_of: fn(Int) -> Int,
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
  NameTaken
  /// The character is not one of the account's.
  NotYourCharacter(character_id: Int)
  /// The database could not do what was asked: an outside failure, not the
  /// player's mistake.
  StoreUnavailable
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
}

/// Character select of an account that has not started.
pub fn new(account_id account_id: Int) -> State {
  todo as "character select of an account"
}

/// The state and the effects after an input.
pub fn decide(
  state state: State,
  input input: Input,
  context context: Context,
) -> #(State, List(Effect)) {
  todo as "the rule of character select"
}

/// The sentence the log line of a refusal holds.
pub fn describe_refusal(refusal refusal: Refusal) -> String {
  todo as "the log text of a refusal"
}

/// The sentence the log line of a breach holds.
pub fn describe_breach(breach breach: Breach) -> String {
  todo as "the log text of a breach"
}
