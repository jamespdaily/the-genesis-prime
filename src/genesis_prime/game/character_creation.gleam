//// What the server checks of a create request before it asks the store to
//// make the character. The real client makes most of these checks itself
//// before it sends 0x025B (LuaCreateCharacter 0x140023e90: the name by text
//// rule 0, the CharacterCreation row and its entitlement and cost, a path up
//// to 3), and a client that is not the real one can send anything, so the
//// server makes them again, and the request's counts as well (opcode.0x25b,
//// opcode.0x25b.counts: at most 27 labels, and the bone values the race and
//// sex have).
////
//// A request that passes gives the character to make: its gender, race, class
//// and faction are the row's. Each refusal maps to one result the client
//// shows, in one place (`result_of`): a name that fails the rule is 10, "name
//// length", and every other refusal is 4, "due to an error"
//// (lua.Character.OnCreateCharacterFailed). A request the real client would not
//// send is no player's mistake, so the caller logs each refusal but the name's.

import genesis_prime/game/appearance
import genesis_prime/game/character_name
import genesis_prime/message/create_character.{type CreateCharacter}
import genesis_prime/message/create_result.{type CreateResult}
import genesis_prime/store.{type NewCharacter, LookEntry, NewCharacter}
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/id.{
  CharacterCreationId, CharacterCustomizationLabelId,
}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// The characterCreationStartEnum of the Arkship start, whose 64 rows are all
/// disabled in the table (CharacterCreation.accountCurrencyTypeIdCost).
const arkship_start = 0

/// The most labels a request carries: the label table's size (opcode.0x25b.counts).
const most_labels = 27

/// The highest path a request may name (0x140023e90).
const highest_path = 3

/// Why a create request is refused.
pub type Refusal {
  /// The name fails the client's text rule 0.
  NameBreaksRule
  /// The table has no CharacterCreation row with the id.
  NoSuchRow(creation_id: Int)
  /// The row's enabled column is off.
  RowDisabled(creation_id: Int)
  /// The row is of the Arkship start.
  ArkshipRow(creation_id: Int)
  /// The row is for the create screen's model and makes no character.
  CostumeOnlyRow(creation_id: Int)
  /// The row needs an entitlement, which no account holds yet.
  NeedsEntitlement(creation_id: Int)
  /// The row costs account currency, which no account holds yet.
  CostsCurrency(creation_id: Int)
  /// The path is above 3.
  PathAbove3(creation_id: Int, path: Int)
  /// The request holds more than 27 labels.
  TooManyLabels(creation_id: Int, count: Int)
  /// The request holds another number of bone values than its race and sex
  /// have.
  WrongBoneCount(creation_id: Int, expected: Int, got: Int)
}

/// Checks a request against the client's tables: the name, then the row it
/// names, then the rest.
pub fn check(
  tables tables: table_store.Tables,
  request request: CreateCharacter,
) -> Result(NewCharacter, Refusal) {
  use <- bool.guard(
    !character_name.is_valid(request.name),
    Error(NameBreaksRule),
  )
  case
    character_creation.get(
      tables:,
      id: CharacterCreationId(request.creation_id),
    )
  {
    Error(Nil) -> Error(NoSuchRow(creation_id: request.creation_id))
    Ok(row) -> check_row(tables:, row:, request:)
  }
}

/// Checks the row the request names and the request's path, labels and bone
/// values, and gives the character to make.
pub fn check_row(
  tables tables: table_store.Tables,
  row row: CharacterCreation,
  request request: CreateCharacter,
) -> Result(NewCharacter, Refusal) {
  let creation_id = row.id
  let labels = list.length(request.customisation_labels)
  use <- bool.guard(!row.enabled, Error(RowDisabled(creation_id:)))
  use <- bool.guard(
    row.character_creation_start_enum == arkship_start,
    Error(ArkshipRow(creation_id:)),
  )
  use <- bool.guard(row.costume_only, Error(CostumeOnlyRow(creation_id:)))
  use <- bool.guard(
    row.entitlement_id_required != 0,
    Error(NeedsEntitlement(creation_id:)),
  )
  use <- bool.guard(
    row.account_currency_amount_cost != 0,
    Error(CostsCurrency(creation_id:)),
  )
  use <- bool.guard(
    request.path > highest_path,
    Error(PathAbove3(creation_id:, path: request.path)),
  )
  use <- bool.guard(
    labels > most_labels,
    Error(TooManyLabels(creation_id:, count: labels)),
  )
  let expected =
    appearance.bone_count(
      tables:,
      race_id: character_creation.race_id(row),
      sex: row.sex,
    )
  let got = list.length(request.bone_values)
  use <- bool.guard(
    got != expected,
    Error(WrongBoneCount(creation_id:, expected:, got:)),
  )
  Ok(NewCharacter(
    name: request.name,
    gender: row.sex,
    race_id: character_creation.race_id(row),
    class_id: character_creation.class_id(row),
    faction_id: row.faction_id,
    path: request.path,
    look: list.zip(request.customisation_labels, request.customisation_values)
      |> list.map(fn(pair) {
        LookEntry(label: CharacterCustomizationLabelId(pair.0), value: pair.1)
      }),
    bones: request.bone_values,
  ))
}

/// The result the client shows for a refusal.
pub fn result_of(refusal: Refusal) -> CreateResult {
  case refusal {
    NameBreaksRule -> create_result.NameLength
    NoSuchRow(..)
    | RowDisabled(..)
    | ArkshipRow(..)
    | CostumeOnlyRow(..)
    | NeedsEntitlement(..)
    | CostsCurrency(..)
    | PathAbove3(..)
    | TooManyLabels(..)
    | WrongBoneCount(..) -> create_result.CreateFailed
  }
}

/// The sentence the caller logs as a warning for a refusal: none for a name
/// that fails the rule, which a player can type, and for every other refusal
/// the sentence of `describe`.
pub fn warning(refusal: Refusal) -> Option(String) {
  case refusal {
    NameBreaksRule -> None
    NoSuchRow(..)
    | RowDisabled(..)
    | ArkshipRow(..)
    | CostumeOnlyRow(..)
    | NeedsEntitlement(..)
    | CostsCurrency(..)
    | PathAbove3(..)
    | TooManyLabels(..)
    | WrongBoneCount(..) -> Some(describe(refusal))
  }
}

/// A sentence for the log that says why the request was refused, naming the
/// creation row.
pub fn describe(refusal: Refusal) -> String {
  case refusal {
    NameBreaksRule -> "the name fails the client's text rule 0"
    NoSuchRow(creation_id:) ->
      "creation row " <> int.to_string(creation_id) <> " does not exist"
    RowDisabled(creation_id:) ->
      "creation row " <> int.to_string(creation_id) <> " is disabled"
    ArkshipRow(creation_id:) ->
      "creation row " <> int.to_string(creation_id) <> " is an Arkship row"
    CostumeOnlyRow(creation_id:) ->
      "creation row " <> int.to_string(creation_id) <> " is costume only"
    NeedsEntitlement(creation_id:) ->
      "creation row "
      <> int.to_string(creation_id)
      <> " needs an entitlement the account does not hold"
    CostsCurrency(creation_id:) ->
      "creation row "
      <> int.to_string(creation_id)
      <> " costs account currency the account does not hold"
    PathAbove3(creation_id:, path:) ->
      "creation row "
      <> int.to_string(creation_id)
      <> " was asked with path "
      <> int.to_string(path)
    TooManyLabels(creation_id:, count:) ->
      "creation row "
      <> int.to_string(creation_id)
      <> " was asked with "
      <> int.to_string(count)
      <> " customisation labels"
    WrongBoneCount(creation_id:, expected:, got:) ->
      "creation row "
      <> int.to_string(creation_id)
      <> " was asked with "
      <> int.to_string(got)
      <> " bone values, not "
      <> int.to_string(expected)
  }
}
