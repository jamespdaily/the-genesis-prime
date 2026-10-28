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
//// - **Once for each list.** `index` reads the tables once into an `Index`: the
////   faction of each label and the indexed rows of each race and sex, each
////   with the faction it is filed under. The character list builds it once and
////   every character's body is taken from it.
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
import genesis_prime/table/id.{
  type CharacterCustomizationLabelId, type Faction2Id, type ItemSlotId,
  type RaceId, CharacterCustomizationLabelId, Faction2Id,
}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

/// What the body visuals read of the client's tables, read once for a list of
/// characters: the faction of each label, and the rows the client's index
/// holds for each race and sex, each with the faction it is filed under.
pub opaque type Index {
  Index(
    label_factions: Dict(CharacterCustomizationLabelId, Faction2Id),
    rows: Dict(#(RaceId, Int), List(Filed)),
  )
}

/// A row of CharacterCustomization with the faction it is filed under.
type Filed {
  Filed(faction: Faction2Id, row: CharacterCustomization)
}

/// The index of the client's tables.
pub fn index(tables tables: table_store.Tables) -> Index {
  index_from_rows(
    rows: character_customization.all(tables),
    labels: character_customization_label.all(tables),
  )
}

/// The index of the given rows of CharacterCustomization, in record order,
/// and the given rows of CharacterCustomizationLabel.
pub fn index_from_rows(
  rows rows: List(CharacterCustomization),
  labels labels: List(CharacterCustomizationLabel),
) -> Index {
  let label_factions =
    list.map(labels, fn(label) {
      #(
        character_customization_label.id(label),
        character_customization_label.faction2_id(label),
      )
    })
    |> dict.from_list
  let filed =
    list.filter(rows, is_indexed)
    |> list.fold(dict.new(), fn(filed, row) {
      dict.upsert(
        filed,
        #(character_customization.race_id(row), row.gender),
        fn(found) {
          [
            Filed(faction: row_faction(row, label_factions), row:),
            ..option.unwrap(found, [])
          ]
        },
      )
    })
    |> dict.map_values(fn(_race_and_sex, rows) { list.reverse(rows) })
  Index(label_factions:, rows: filed)
}

/// The body visuals of a character's look, one for each slot a row shows, in
/// slot order, for the race and sex and faction.
pub fn body_visuals(
  index index: Index,
  race_id race_id: RaceId,
  sex sex: Int,
  faction_id faction_id: Int,
  look look: List(LookEntry),
) -> List(ItemVisual) {
  let faction = Faction2Id(faction_id)
  let label_factions = index.label_factions
  let candidates =
    dict.get(index.rows, #(race_id, sex))
    |> result.unwrap([])
    |> list.filter(fn(filed) {
      faction_allows(faction:, row_faction: filed.faction)
    })
    |> list.map(fn(filed) { filed.row })
  let held = held_values(candidates)
  let current =
    list.fold(look, lowest_values(held), fn(current, entry) {
      case
        label_allowed(label: entry.label, label_factions:, faction:)
        && list.contains(
          dict.get(held, entry.label) |> result.unwrap([]),
          entry.value,
        )
      {
        True -> dict.insert(current, entry.label, entry.value)
        False -> current
      }
    })
  list.fold(candidates, dict.new(), fn(winners, row) {
    case shows(row:, current:, label_factions:, faction:) {
      False -> winners
      True ->
        dict.upsert(winners, character_customization.item_slot_id(row), winner(
          _,
          row,
        ))
    }
  })
  |> dict.to_list
  |> list.sort(fn(first, second) { slot_order(first.0, second.0) })
  |> list.map(fn(slot_and_row) {
    let #(slot, row) = slot_and_row
    ItemVisual(
      slot: slot.value,
      display_id: row.item_display_id,
      item_color_set_id: 0,
      dye: 0,
    )
  })
}

/// The row a slot shows once `row` is considered: the row already found,
/// unless `row` has strictly more pairs, so the earliest row wins a tie.
fn winner(
  found: Option(CharacterCustomization),
  row: CharacterCustomization,
) -> CharacterCustomization {
  case found {
    None -> row
    Some(held) ->
      case score(row) > score(held) {
        True -> row
        False -> held
      }
  }
}

fn slot_order(first: ItemSlotId, second: ItemSlotId) -> order.Order {
  int.compare(first.value, second.value)
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
  customization_parameter_map.all(tables)
  |> list.filter(fn(map) {
    customization_parameter_map.race_id(map) == race_id
    && map.gender_enum == sex
  })
  |> list.filter_map(fn(map) {
    customization_parameter.get(
      tables:,
      id: customization_parameter_map.customization_parameter_id(map),
    )
  })
  |> list.map(parts_set)
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
  label_factions: Dict(CharacterCustomizationLabelId, Faction2Id),
) -> Faction2Id {
  labelled(row)
  |> list.filter_map(fn(pair) {
    case dict.get(label_factions, pair.0) {
      Ok(faction) if faction != Faction2Id(0) -> Ok(faction)
      Ok(_) | Error(Nil) -> Error(Nil)
    }
  })
  |> list.first
  |> result.unwrap(Faction2Id(0))
}

fn faction_allows(
  faction faction: Faction2Id,
  row_faction row_faction: Faction2Id,
) -> Bool {
  row_faction == Faction2Id(0) || row_faction == faction
}

/// Whether the label may be set for the faction: the label has a row of
/// CharacterCustomizationLabel with faction 0 or the faction (SetLookLabel
/// 0x1400310b0).
fn label_allowed(
  label label: CharacterCustomizationLabelId,
  label_factions label_factions: Dict(CharacterCustomizationLabelId, Faction2Id),
  faction faction: Faction2Id,
) -> Bool {
  case dict.get(label_factions, label) {
    Ok(label_faction) -> faction_allows(faction:, row_faction: label_faction)
    Error(Nil) -> False
  }
}

/// The (label, value) pairs of a row that have a label; the table's label 0
/// is none.
fn labelled(
  row: CharacterCustomization,
) -> List(#(CharacterCustomizationLabelId, Int)) {
  [
    #(
      character_customization.character_customization_label_id00(row),
      row.value00,
    ),
    #(
      character_customization.character_customization_label_id01(row),
      row.value01,
    ),
  ]
  |> list.filter(fn(pair) { pair.0 != CharacterCustomizationLabelId(0) })
}

/// The values the candidate rows hold for each label they use.
fn held_values(
  candidates: List(CharacterCustomization),
) -> Dict(CharacterCustomizationLabelId, List(Int)) {
  list.flat_map(candidates, labelled)
  |> list.fold(dict.new(), fn(held, pair) {
    dict.upsert(held, pair.0, fn(values) {
      [pair.1, ..option.unwrap(values, [])]
    })
  })
}

/// Each label at the lowest value a candidate row holds for it
/// (ResetLook 0x140030e30).
fn lowest_values(
  held: Dict(CharacterCustomizationLabelId, List(Int)),
) -> Dict(CharacterCustomizationLabelId, Int) {
  dict.to_list(held)
  |> list.filter_map(fn(entry) {
    list.reduce(entry.1, int.min)
    |> result.map(fn(lowest) { #(entry.0, lowest) })
  })
  |> dict.from_list
}

/// Whether the row is among a slot's rows for the look: a row with no label
/// always is; any other is when each of its labels at a value other than 0 has
/// that value in the look, and one of its labels is one the look applies.
fn shows(
  row row: CharacterCustomization,
  current current: Dict(CharacterCustomizationLabelId, Int),
  label_factions label_factions: Dict(CharacterCustomizationLabelId, Faction2Id),
  faction faction: Faction2Id,
) -> Bool {
  case labelled(row) {
    [] -> True
    pairs ->
      list.all(pairs, fn(pair) {
        pair.1 == 0 || dict.get(current, pair.0) == Ok(pair.1)
      })
      && list.any(pairs, fn(pair) {
        label_allowed(label: pair.0, label_factions:, faction:)
        && dict.get(current, pair.0) == Ok(pair.1)
      })
  }
}

/// How many positions of the row hold both a label and a value other than 0;
/// the row with the most wins its slot.
fn score(row: CharacterCustomization) -> Int {
  list.count(labelled(row), fn(pair) { pair.1 != 0 })
}
