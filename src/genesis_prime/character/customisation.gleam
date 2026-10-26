//// What the client's tables say a create request may carry: how many bone
//// values it holds for a race and sex, and which customisation labels exist
//// and for which faction. The real client puts in a request one float for each
//// entry of the chosen race and sex's bone list, which it builds from
//// CustomizationParameterMap, and one label and value for each look the player
//// set, each label once and only a label whose faction2Id is 0 or the
//// character's faction (opcode.0x25b.counts, LuaCreateCharacter 0x140023E90,
//// BuildBoneCustomizationTable 0x14043F8C0, SetLook 0x14004AAD0).

import genesis_prime/message/bit_stream.{type DecodeError, UnexpectedValue}
import genesis_prime/table/character_customization_label
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/loader/store.{type Tables}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set

/// The counts and the labels the tables give, made once from the loaded
/// tables. `bone_counts` is the number of bone values of a race and sex,
/// `label_factions` the faction2Id of each label, `most_bones` the largest
/// bone count of any race and sex and `most_labels` the number of labels the
/// table holds, which is the most a request can carry because the client sends
/// each label at most once.
pub type Customisation {
  Customisation(
    bone_counts: Dict(#(Int, Int), Int),
    label_factions: Dict(Int, Int),
    most_bones: Int,
    most_labels: Int,
  )
}

/// Why a request's labels are not ones the real client sends.
pub type LabelProblem {
  /// The label is given more than once.
  LabelRepeated(label_id: Int)
  /// The CharacterCustomizationLabel table has no row for the label.
  LabelUnknown(label_id: Int)
  /// The label is for the other faction: its faction2Id is neither 0 nor the
  /// character's faction.
  LabelOfAnotherFaction(label_id: Int)
}

/// The rows the server requires of the tables for `of`: a CustomizationParameter
/// row for every parameter a CustomizationParameterMap row names. A map row
/// whose parameter is missing would count no bone values for its part, so the
/// load fails instead.
pub fn requirements() -> List(store.Requirement) {
  [
    store.Requirement(
      from_table: "CustomizationParameterMap",
      column: "customizationParameterId",
      to_table: "CustomizationParameter",
      missing: fn(tables) {
        customization_parameter_map.all(tables)
        |> list.map(fn(row) { row.customization_parameter_id })
        |> list.unique
        |> list.filter(fn(id) {
          result.is_error(customization_parameter.get(tables, id))
        })
      },
    ),
  ]
}

/// A customisation with no race, no label and no room for a request, for a
/// server that loads no game tables and so refuses every create request.
pub fn empty() -> Customisation {
  Customisation(
    bone_counts: dict.new(),
    label_factions: dict.new(),
    most_bones: 0,
    most_labels: 0,
  )
}

/// The counts and labels of the loaded tables. A bone value is counted for
/// each part (sclX to posZ) that the CustomizationParameter row of a map row
/// sets, which is a part with a value other than 0. The load checked that the
/// row exists (`requirements`).
pub fn of(tables tables: Tables) -> Customisation {
  let bone_counts =
    list.fold(
      customization_parameter_map.all(tables),
      dict.new(),
      fn(counts, row) {
        let assert Ok(parameter) =
          customization_parameter.get(tables, row.customization_parameter_id)
          as "the load checked that every parameter a map row names has a row"
        let parts = parts_set(parameter)
        dict.upsert(counts, #(row.race_id, row.gender_enum), fn(found) {
          case found {
            Some(count) -> count + parts
            None -> parts
          }
        })
      },
    )
  let labels = character_customization_label.all(tables)
  Customisation(
    bone_counts:,
    label_factions: dict.from_list(
      list.map(labels, fn(label) { #(label.id, label.faction2_id) }),
    ),
    most_bones: list.fold(dict.values(bone_counts), 0, int.max),
    most_labels: list.length(labels),
  )
}

fn parts_set(parameter: customization_parameter.CustomizationParameter) -> Int {
  list.count(
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
    ],
    fn(part) { part != 0 },
  )
}

/// The number of bone values the real client sends for a race and sex: the
/// count of the map's rows for them, and 0 for a race or sex the map has no
/// row for (the client takes an empty list for a race above 16 or a sex above
/// 2).
pub fn bone_count(
  customisation customisation: Customisation,
  race_id race_id: Int,
  sex sex: Int,
) -> Int {
  dict.get(customisation.bone_counts, #(race_id, sex)) |> result.unwrap(0)
}

/// Whether a request holds no more labels and bone values than the real client
/// can send: more is bad input, a decode failure that ends the connection.
pub fn within_limits(
  customisation customisation: Customisation,
  labels labels: Int,
  bones bones: Int,
) -> Result(Nil, DecodeError) {
  case labels > customisation.most_labels, bones > customisation.most_bones {
    True, _ -> Error(UnexpectedValue("customisation_labels", labels))
    False, True -> Error(UnexpectedValue("bone_values", bones))
    False, False -> Ok(Nil)
  }
}

/// Whether the labels of a request are ones the real client sends for a
/// character of the faction: each once, each in the table, each for no faction
/// or the character's. The first that is not is the problem.
pub fn check_labels(
  customisation customisation: Customisation,
  labels labels: List(Int),
  faction_id faction_id: Int,
) -> Result(Nil, LabelProblem) {
  check_labels_loop(customisation:, labels:, faction_id:, seen: set.new())
}

fn check_labels_loop(
  customisation customisation: Customisation,
  labels labels: List(Int),
  faction_id faction_id: Int,
  seen seen: set.Set(Int),
) -> Result(Nil, LabelProblem) {
  case labels {
    [] -> Ok(Nil)
    [label_id, ..rest] ->
      case set.contains(seen, label_id) {
        True -> Error(LabelRepeated(label_id))
        False ->
          case dict.get(customisation.label_factions, label_id) {
            Error(Nil) -> Error(LabelUnknown(label_id))
            Ok(faction) if faction != 0 && faction != faction_id ->
              Error(LabelOfAnotherFaction(label_id))
            Ok(_) ->
              check_labels_loop(
                customisation:,
                labels: rest,
                faction_id:,
                seen: set.insert(seen, label_id),
              )
          }
      }
  }
}
