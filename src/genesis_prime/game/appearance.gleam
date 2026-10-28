//// A character's body as the client builds it from its look, and the bone
//// values a race and sex carry. A look is the customisation labels with their
//// values that a create request sends (opcode.0x25b); the client turns them
//// into one item display for each body slot of its model, and the server sends
//// the same displays in the character list (0x0117's body visuals), so the
//// select screen shows the model the create screen showed.
////
//// - **The rows a look can use.** Of CharacterCustomization, a row is indexed
////   when its flags have bit 2 set and bit 1 clear (BuildCustomizationIndex
////   0x14001d450); a row whose flags also have bit 4 is a slider's and is not
////   filed. A row is filed under the faction of its first label that names one
////   (CharacterCustomizationLabel's faction2Id), else 0, and a character of
////   a faction has the rows of faction 0 and of its own, for its race and sex.
//// - **The look as the client holds it.** Every label the candidate rows use
////   starts at its lowest value, and each label of the character's look then
////   replaces that, when the label is faction 0's or the character's faction
////   and a candidate row holds the label at that value (ResetLook 0x140030e30,
////   SetLookLabel 0x1400310b0).
//// - **A slot's rows.** The rows a slot may show are its label-free rows, which
////   are the defaults, and the rows whose labels, each with a value other than
////   0, all have that value in the look, with at least one of the row's labels
////   one the look applies. Each slot shows the row with the most positions that
////   hold both a label and a value other than 0, and on a tie the earliest
////   record (PickCustomizationDisplays 0x140031c90, vector.0x140031c90). The
////   client's output has a display of 0 for a slot whose rows were all taken
////   out; a slot with no row at all is left out here.
//// - **The bones.** A create request carries one 32-bit float for each part
////   the race and sex's CustomizationParameterMap rows set in their
////   CustomizationParameter row (opcode.0x25b.counts).

import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/store.{type LookEntry}
import genesis_prime/table/character_customization.{type CharacterCustomization}
import genesis_prime/table/character_customization_label.{
  type CharacterCustomizationLabel,
}
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/id.{type RaceId}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/result

/// The body visuals of a character's look, one for each slot a row shows, in
/// slot order, for the race and sex and faction, from the client's tables.
pub fn body_visuals(
  tables tables: table_store.Tables,
  race_id race_id: RaceId,
  sex sex: Int,
  faction_id faction_id: Int,
  look look: List(LookEntry),
) -> List(ItemVisual) {
  body_visuals_from_rows(
    rows: character_customization.all(tables),
    labels: character_customization_label.all(tables),
    race_id:,
    sex:,
    faction_id:,
    look:,
  )
}

/// The body visuals from the given rows of CharacterCustomization, in record
/// order, and the given rows of CharacterCustomizationLabel.
pub fn body_visuals_from_rows(
  rows rows: List(CharacterCustomization),
  labels labels: List(CharacterCustomizationLabel),
  race_id race_id: RaceId,
  sex sex: Int,
  faction_id faction_id: Int,
  look look: List(LookEntry),
) -> List(ItemVisual) {
  let label_factions =
    list.map(labels, fn(label) { #(label.id, label.faction2_id) })
    |> dict.from_list
  let candidates =
    list.filter(rows, fn(row) {
      row.race_id == race_id.value
      && row.gender == sex
      && is_indexed(row)
      && faction_allows(
        faction_id:,
        row_faction: row_faction(row, label_factions),
      )
    })
  let held = held_values(candidates)
  let current =
    list.fold(look, lowest_values(held), fn(current, entry) {
      let label = entry.label.value
      case
        label_allowed(label:, label_factions:, faction_id:)
        && list.contains(
          dict.get(held, label) |> result.unwrap([]),
          entry.value,
        )
      {
        True -> dict.insert(current, label, entry.value)
        False -> current
      }
    })
  let shown =
    list.filter(candidates, fn(row) {
      shows(row:, current:, label_factions:, faction_id:)
    })
  let slots =
    list.map(shown, fn(row) { row.item_slot_id })
    |> list.unique
    |> list.sort(int.compare)
  list.map(slots, fn(slot) {
    let assert Ok(row) =
      best(list.filter(shown, fn(row) { row.item_slot_id == slot }))
      as "a slot taken from the shown rows has a row"
    ItemVisual(
      slot:,
      display_id: row.item_display_id,
      item_color_set_id: 0,
      dye: 0,
    )
  })
}

/// The number of bone values a create request carries for the race and sex:
/// for each CustomizationParameterMap row of the race and sex, the parts its
/// CustomizationParameter row sets (scale, rotation and position on each of
/// three axes, each 0 or 1 in the table).
pub fn bone_count(
  tables tables: table_store.Tables,
  race_id race_id: RaceId,
  sex sex: Int,
) -> Int {
  let parts =
    customization_parameter.all(tables)
    |> list.map(fn(parameter) { #(parameter.id, parts_set(parameter)) })
    |> dict.from_list
  customization_parameter_map.all(tables)
  |> list.filter(fn(map) {
    map.race_id == race_id.value && map.gender_enum == sex
  })
  |> list.map(fn(map) {
    dict.get(parts, map.customization_parameter_id) |> result.unwrap(0)
  })
  |> int.sum
}

fn parts_set(parameter: customization_parameter.CustomizationParameter) -> Int {
  [
    parameter.scl_x,
    parameter.scl_y,
    parameter.scl_z,
    parameter.rot_x,
    parameter.rot_y,
    parameter.rot_z,
    parameter.pos_x,
    parameter.pos_y,
    parameter.pos_z,
  ]
  |> list.count(fn(part) { part != 0 })
}

/// Whether the index holds the row: flags bit 2 set, bit 1 clear, and bit 4
/// clear, which marks a slider's row (BuildCustomizationIndex 0x14001d450).
fn is_indexed(row: CharacterCustomization) -> Bool {
  int.bitwise_and(row.flags, 2) != 0
  && int.bitwise_and(row.flags, 1) == 0
  && int.bitwise_and(row.flags, 4) == 0
}

/// The faction a row is filed under: the faction of its first label that names
/// one, else 0.
fn row_faction(
  row: CharacterCustomization,
  label_factions: Dict(Int, Int),
) -> Int {
  [
    row.character_customization_label_id00,
    row.character_customization_label_id01,
  ]
  |> list.filter_map(fn(label) {
    case dict.get(label_factions, label) {
      Ok(faction) if faction != 0 -> Ok(faction)
      Ok(_) | Error(Nil) -> Error(Nil)
    }
  })
  |> list.first
  |> result.unwrap(0)
}

fn faction_allows(
  faction_id faction_id: Int,
  row_faction row_faction: Int,
) -> Bool {
  row_faction == 0 || row_faction == faction_id
}

/// Whether the label may be set for the faction: the label has a row of
/// CharacterCustomizationLabel with faction 0 or the faction (SetLookLabel
/// 0x1400310b0).
fn label_allowed(
  label label: Int,
  label_factions label_factions: Dict(Int, Int),
  faction_id faction_id: Int,
) -> Bool {
  case dict.get(label_factions, label) {
    Ok(faction) -> faction == 0 || faction == faction_id
    Error(Nil) -> False
  }
}

/// The (label, value) pairs of a row, of its two label positions.
fn pairs(row: CharacterCustomization) -> List(#(Int, Int)) {
  [
    #(row.character_customization_label_id00, row.value00),
    #(row.character_customization_label_id01, row.value01),
  ]
}

/// The values the candidate rows hold for each label they use.
fn held_values(
  candidates: List(CharacterCustomization),
) -> Dict(Int, List(Int)) {
  list.flat_map(candidates, pairs)
  |> list.filter(fn(pair) { pair.0 != 0 })
  |> list.fold(dict.new(), fn(held, pair) {
    dict.upsert(held, pair.0, fn(values) {
      [pair.1, ..option.unwrap(values, [])]
    })
  })
}

/// Each label at the lowest value a candidate row holds for it
/// (ResetLook 0x140030e30).
fn lowest_values(held: Dict(Int, List(Int))) -> Dict(Int, Int) {
  dict.map_values(held, fn(_label, values) {
    case values {
      [first, ..rest] -> list.fold(rest, first, int.min)
      [] -> 0
    }
  })
}

/// Whether the row is among a slot's rows for the look: a row with no label
/// always is; any other is when each of its labels at a value other than 0 has
/// that value in the look, and one of its labels is one the look applies.
fn shows(
  row row: CharacterCustomization,
  current current: Dict(Int, Int),
  label_factions label_factions: Dict(Int, Int),
  faction_id faction_id: Int,
) -> Bool {
  let labelled = list.filter(pairs(row), fn(pair) { pair.0 != 0 })
  case labelled {
    [] -> True
    _ ->
      list.all(labelled, fn(pair) {
        pair.1 == 0 || dict.get(current, pair.0) == Ok(pair.1)
      })
      && list.any(labelled, fn(pair) {
        label_allowed(label: pair.0, label_factions:, faction_id:)
        && dict.get(current, pair.0) == Ok(pair.1)
      })
  }
}

/// The row with the most positions that hold both a label and a value other
/// than 0; the first of them in record order on a tie.
fn best(
  rows: List(CharacterCustomization),
) -> Result(CharacterCustomization, Nil) {
  list.fold(rows, Error(Nil), fn(found, row) {
    case found {
      Error(Nil) -> Ok(row)
      Ok(held) ->
        case score(row) > score(held) {
          True -> Ok(row)
          False -> Ok(held)
        }
    }
  })
}

fn score(row: CharacterCustomization) -> Int {
  list.count(pairs(row), fn(pair) { pair.0 != 0 && pair.1 != 0 })
}
