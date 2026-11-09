//// What the server checks of a create request before it asks the store to
//// make the character. The real client makes most of these checks itself
//// before it sends 0x025B (LuaCreateCharacter 0x140023e90: the name by text
//// rule 0, the CharacterCreation row and its entitlement and cost, a path up
//// to 3), and a client that is not the real one can send anything, so the
//// server makes them again, except the name, which the table's
//// `character_name_follows_rule_0` holds and the store answers
//// (genesis_prime/store), and the request's counts as well (opcode.0x25b,
//// opcode.0x25b.counts: at most 25 labels, each once and in label-id order,
//// the labels and values the race, sex and faction's index holds, and the bone
//// values the race and sex have).
////
//// A request that passes gives the character to make: its gender, race, class
//// and faction are the row's, and its place is its start's
//// (genesis_prime/game/start_place) and its level is the one its xp gives
//// (genesis_prime/game/level). Every refusal is the result 4, "due to an error"
//// (lua.Character.OnCreateCharacterFailed), in one place (`result_of`). A request
//// the real client would not send is no player's mistake, so the caller logs
//// each refusal.

import genesis_prime/game/appearance
import genesis_prime/game/level
import genesis_prime/game/loadout
import genesis_prime/game/start_place
import genesis_prime/message/create_character.{type CreateCharacter}
import genesis_prime/message/create_result.{type CreateResult}
import genesis_prime/store.{
  type LookEntry, type NewCharacter, type NewItem, NewCharacter, NewItem,
}
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/id.{type ClassId, CharacterCreationId}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/list
import gleam/result

/// The most labels a request carries: the label table's 27, less labels 26
/// and 27, which set the race and never enter a look (opcode.0x25b.counts).
const most_labels = 25

/// The highest path a request may name (0x140023e90).
const highest_path = 3

/// Why a create request is refused.
pub type Refusal {
  /// The table has no CharacterCreation row with the id.
  NoSuchRow(creation_id: Int)
  /// The row's enabled column is off.
  RowDisabled(creation_id: Int)
  /// The row is for the create screen's model and makes no character.
  CostumeOnlyRow(creation_id: Int)
  /// The row needs an entitlement, which no account holds yet.
  NeedsEntitlement(creation_id: Int)
  /// The row costs account currency, which no account holds yet.
  CostsCurrency(creation_id: Int)
  /// The path is above 3.
  PathAbove3(creation_id: Int, path: Int)
  /// The request holds more than 25 labels.
  TooManyLabels(creation_id: Int, count: Int)
  /// The request's labels do not strictly increase: a label repeats or comes
  /// before the one that precedes it.
  LabelsNotIncreasing(creation_id: Int, previous: Int, label: Int)
  /// A label has no label row of faction 0 or the row's faction.
  LabelNotAllowed(creation_id: Int, label: Int)
  /// No CharacterCustomization row holds the label at the value for the row's
  /// race, sex and faction.
  LookValueNotHeld(creation_id: Int, label: Int, value: Int)
  /// The request holds another number of bone values than its race and sex
  /// have.
  WrongBoneCount(creation_id: Int, expected: Int, got: Int)
  /// A bone value is a NaN or an infinity, which the real client's bone export
  /// never gives and the list would send back to every client that reads it.
  BoneNotFinite(creation_id: Int)
  /// The row's start, race and faction have no start place
  /// (genesis_prime/game/start_place).
  NoStartPlace(creation_id: Int, start: Int, faction_id: Int, race_id: Int)
  /// The row's xp is no level of the client's XpPerLevel table
  /// (genesis_prime/game/level).
  NoLevelForExperience(creation_id: Int, experience: Int)
}

/// Checks a request against the client's tables: the row it names, then the
/// rest.
pub fn check(
  tables tables: table_store.Tables,
  request request: CreateCharacter,
) -> Result(NewCharacter, Refusal) {
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
  use <- bool.guard(
    list.any(request.bone_values, is_not_finite),
    Error(BoneNotFinite(creation_id:)),
  )
  let race_id = character_creation.race_id(row)
  let look =
    store.look(
      labels: request.customisation_labels,
      values: request.customisation_values,
    )
  use Nil <- result.try(check_look(tables:, row:, request:, look:))
  case
    start_place.of(
      tables:,
      faction_id: row.faction_id,
      race_id:,
      start: start_place.start(enum_value: row.character_creation_start_enum),
    )
  {
    Error(Nil) ->
      Error(NoStartPlace(
        creation_id:,
        start: row.character_creation_start_enum,
        faction_id: row.faction_id,
        race_id: race_id.value,
      ))
    Ok(place) ->
      case level.for_experience(tables:, experience: row.xp) {
        Error(Nil) ->
          Error(NoLevelForExperience(creation_id:, experience: row.xp))
        Ok(level) ->
          Ok(NewCharacter(
            name: request.name,
            gender: row.sex,
            race_id:,
            class_id: character_creation.class_id(row),
            faction_id: row.faction_id,
            level:,
            experience: row.xp,
            path: request.path,
            place:,
            look:,
            bones: request.bone_values,
            starting_items: novice_items(
              tables:,
              class_id: character_creation.class_id(row),
              faction_id: row.faction_id,
            ),
          ))
      }
  }
}

/// The items a new character of the class and faction holds: its Novice set's
/// armor pieces and shield, each at the bag index of its slot, and its weapon in
/// slot 16, all equipped (location 0), a stack of 1 each
/// (`opcode.0x111.equipped_set`, `Item2.novice_set`).
fn novice_items(
  tables tables: table_store.Tables,
  class_id class_id: ClassId,
  faction_id faction_id: Int,
) -> List(NewItem) {
  let assert Ok(loadout) = loadout.of(tables:, class_id:, faction_id:)
    as "the content load refuses a table with no Novice set for a class and faction a row can create"
  let armor =
    list.map(loadout.armor, fn(piece) {
      NewItem(
        item2_id: piece.item,
        location: equipped_location,
        bag_index: piece.bag_index,
        stack_count: 1,
      )
    })
  list.append(armor, [
    NewItem(
      item2_id: loadout.weapon,
      location: equipped_location,
      bag_index: loadout.weapon_slot,
      stack_count: 1,
    ),
  ])
}

/// The location of the items a character wears and wields (`opcode.0x111.equipped_set`).
const equipped_location = 0

/// Checks the request's look: its labels strictly increase (each label at most
/// once, in label-id order), each label is allowed for the row's faction and
/// each value is one the index holds for the row's race and sex
/// (opcode.0x25b.counts, SetLookLabel 0x1400310b0, SetLookValue 0x14002ec40).
fn check_look(
  tables tables: table_store.Tables,
  row row: CharacterCreation,
  request request: CreateCharacter,
  look look: List(LookEntry),
) -> Result(Nil, Refusal) {
  let creation_id = row.id
  case
    list.window_by_2(request.customisation_labels)
    |> list.find(fn(pair) { pair.0 >= pair.1 })
  {
    Ok(#(previous, label)) ->
      Error(LabelsNotIncreasing(creation_id:, previous:, label:))
    Error(Nil) ->
      case
        appearance.check_look(
          index: appearance.index(tables:),
          race_id: character_creation.race_id(row),
          sex: row.sex,
          faction_id: row.faction_id,
          look:,
        )
      {
        Ok(Nil) -> Ok(Nil)
        Error(appearance.LabelNotAllowed(label:)) ->
          Error(LabelNotAllowed(creation_id:, label: label.value))
        Error(appearance.ValueNotHeld(label:, value:)) ->
          Error(LookValueNotHeld(creation_id:, label: label.value, value:))
      }
  }
}

/// Whether the 32 bits are a NaN or an infinity: an exponent of all ones
/// (IEEE 754 single precision, which ReadFloat 0x14006c1c0 keeps as it is).
fn is_not_finite(bits: Int) -> Bool {
  int.bitwise_and(bits, exponent_mask) == exponent_mask
}

/// The exponent bits of a 32-bit float.
const exponent_mask = 0x7F800000

/// The result the client shows for a refusal.
pub fn result_of(refusal: Refusal) -> CreateResult {
  case refusal {
    NoSuchRow(..)
    | RowDisabled(..)
    | CostumeOnlyRow(..)
    | NeedsEntitlement(..)
    | CostsCurrency(..)
    | PathAbove3(..)
    | TooManyLabels(..)
    | LabelsNotIncreasing(..)
    | LabelNotAllowed(..)
    | LookValueNotHeld(..)
    | WrongBoneCount(..)
    | BoneNotFinite(..)
    | NoStartPlace(..)
    | NoLevelForExperience(..) -> create_result.CreateFailed
  }
}

/// A sentence for the log that says why the request was refused, naming the
/// creation row.
pub fn describe(refusal: Refusal) -> String {
  case refusal {
    NoSuchRow(creation_id:) -> row_text(creation_id) <> " does not exist"
    RowDisabled(creation_id:) -> row_text(creation_id) <> " is disabled"
    CostumeOnlyRow(creation_id:) -> row_text(creation_id) <> " is costume only"
    NeedsEntitlement(creation_id:) ->
      row_text(creation_id) <> " needs an entitlement the account does not hold"
    CostsCurrency(creation_id:) ->
      row_text(creation_id)
      <> " costs account currency the account does not hold"
    PathAbove3(creation_id:, path:) ->
      row_text(creation_id) <> " was asked with path " <> int.to_string(path)
    TooManyLabels(creation_id:, count:) ->
      row_text(creation_id)
      <> " was asked with "
      <> int.to_string(count)
      <> " customisation labels"
    LabelsNotIncreasing(creation_id:, previous:, label:) ->
      row_text(creation_id)
      <> " was asked with label "
      <> int.to_string(label)
      <> " after label "
      <> int.to_string(previous)
    LabelNotAllowed(creation_id:, label:) ->
      row_text(creation_id)
      <> " was asked with label "
      <> int.to_string(label)
      <> ", which has no label row for its faction"
    LookValueNotHeld(creation_id:, label:, value:) ->
      row_text(creation_id)
      <> " was asked with label "
      <> int.to_string(label)
      <> " at value "
      <> int.to_string(value)
      <> ", which no customization row of its race and sex holds"
    WrongBoneCount(creation_id:, expected:, got:) ->
      row_text(creation_id)
      <> " was asked with "
      <> int.to_string(got)
      <> " bone values, not "
      <> int.to_string(expected)
    BoneNotFinite(creation_id:) ->
      row_text(creation_id)
      <> " was asked with a bone value that is no finite float"
    NoStartPlace(creation_id:, start:, faction_id:, race_id:) ->
      row_text(creation_id)
      <> " has no start place: start "
      <> int.to_string(start)
      <> ", faction "
      <> int.to_string(faction_id)
      <> ", race "
      <> int.to_string(race_id)
    NoLevelForExperience(creation_id:, experience:) ->
      row_text(creation_id)
      <> " has experience "
      <> int.to_string(experience)
      <> ", which is no level of the client's XpPerLevel table"
  }
}

/// How a sentence of `describe` names the creation row.
fn row_text(creation_id: Int) -> String {
  "creation row " <> int.to_string(creation_id)
}
