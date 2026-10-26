//// What a create request may carry, from the client's own tables: the bone
//// values of each race and sex, the customisation labels and the character
//// slots of an account. The expected values are the fact file's records
//// opcode.0x25b.counts (the counts per race and sex, from
//// CustomizationParameterMap and CustomizationParameter, and the table of 27
//// labels), lua.CharacterSelection.OnLoadFromCharacter and
//// RewardPropertyPremiumModifier.rewardPropertyId (the slots: Hybrid row 117
//// gives 2). The tests read the client's files, so they skip where
//// `GENESIS_NO_CLIENT=1`.

import client_tables
import environment
import genesis_prime/character/character_slots
import genesis_prime/character/customisation.{
  LabelOfAnotherFaction, LabelRepeated, LabelUnknown,
}
import genesis_prime/table/character_customization_label
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/loader/store.{type Tables, RowMissing}
import genesis_prime/table/reward_property_premium_modifier
import gleam/erlang/reference
import gleam/list
import owned_test
import planted_table.{Integer}
import unitest

fn loaded() -> Tables {
  let assert Ok(tables) =
    store.load(
      under: reference.new(),
      from: client_tables.folder(),
      entries: [
        character_customization_label.entry(),
        customization_parameter.entry(),
        customization_parameter_map.entry(),
        reward_property_premium_modifier.entry(),
      ],
      requirements: [],
    )
    as "the client's tables did not load"
  tables
}

/// The sexes of CustomizationParameterMap.genderEnum: 0 male, 1 female.
const male = 0

const female = 1

pub fn the_bone_values_of_each_race_and_sex_are_counted_as_the_client_builds_its_list_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let counts = customisation.of(loaded())
  let expected = [
    #(1, male, 48),
    #(3, male, 48),
    #(12, male, 48),
    #(1, female, 46),
    #(3, female, 46),
    #(4, male, 46),
    #(4, female, 46),
    #(5, male, 46),
    #(5, female, 46),
    #(13, male, 46),
    #(16, male, 46),
    #(16, female, 46),
    #(12, female, 41),
  ]
  list.each(expected, fn(case_) {
    let #(race, sex, count) = case_
    assert customisation.bone_count(counts, race, sex) == count
      as "opcode.0x25b.counts: one bone value for each part the CustomizationParameter row of each CustomizationParameterMap row of the race and sex sets: 48 for race 1 male, 46 for race 1 female, 41 for race 12 female"
  })
  assert counts.most_bones == 48 as "opcode.0x25b.counts: 48 is the most"
  assert customisation.bone_count(counts, 17, male) == 0
    && customisation.bone_count(counts, 1, 3) == 0
    as "opcode.0x25b.counts: a race above 16 or a sex above 2 gets the empty default entry"
}

pub fn a_request_holds_at_most_as_many_labels_as_the_label_table_has_rows_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = loaded()
  let counts = customisation.of(tables)
  assert counts.most_labels
    == list.length(character_customization_label.all(tables))
    as "opcode.0x25b.counts: each label at most once, so no more than the table holds"
  assert counts.most_labels == 27
    as "opcode.0x25b.counts: CharacterCustomizationLabel.tbl has 27 rows"
}

pub fn a_label_is_one_the_client_sends_only_once_and_for_no_faction_or_the_characters_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let counts = customisation.of(loaded())
  assert customisation.check_labels(counts, [1, 2, 3], 167) == Ok(Nil)
    as "CharacterCustomizationLabel rows 1, 2 and 3 are for faction 0: any faction has them"
  assert customisation.check_labels(counts, [16, 20], 167) == Ok(Nil)
    as "CharacterCustomizationLabel rows 16 and 20 are for faction 167"
  assert customisation.check_labels(counts, [15], 167)
    == Error(LabelOfAnotherFaction(15))
    as "CharacterCustomizationLabel row 15 is for faction 166: the client stores a label only when its faction2Id is 0 or the character's"
  assert customisation.check_labels(counts, [1, 2, 1], 166)
    == Error(LabelRepeated(1))
    as "opcode.0x25b.counts: each label at most once"
  assert customisation.check_labels(counts, [1, 28], 166)
    == Error(LabelUnknown(28))
    as "opcode.0x25b.counts: the client stores a label only when CharacterCustomizationLabel has the row"
}

pub fn an_account_has_the_hybrid_systems_character_slots_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  let tables = loaded()
  assert character_slots.hybrid(tables) == 2
    as "RewardPropertyPremiumModifier row 117: Hybrid, tier 0, CharacterSlots (29), modifierValueInt 2; row 118 adds an entitlement to the most slots only; VIP row 119 is another system"
  let assert Ok(row) =
    list.find(reward_property_premium_modifier.all(tables), fn(row) {
      row.id == 117
    })
    as "the table holds row 117"
  assert character_slots.hybrid(tables) == row.modifier_value_int
    as "the slots are the table's value, not a number in the code"
}

/// Loads planted CustomizationParameterMap and CustomizationParameter tables
/// with the requirements of the customisation, and the planted
/// RewardPropertyPremiumModifier table with those of the character slots.
fn load_planted(
  map map: List(List(planted_table.Cell)),
  parameters parameters: List(List(planted_table.Cell)),
  modifiers modifiers: List(List(planted_table.Cell)),
  requirements requirements: List(store.Requirement),
  then then: fn(Result(Tables, store.LoadError)) -> a,
) -> a {
  use folder <- planted_table.in_folder([
    #(
      "CustomizationParameterMap",
      planted_table.bytes(planted_table.table(
        customization_parameter_map.schema,
        map,
      )),
    ),
    #(
      "CustomizationParameter",
      planted_table.bytes(planted_table.table(
        customization_parameter.schema,
        parameters,
      )),
    ),
    #(
      "RewardPropertyPremiumModifier",
      planted_table.bytes(planted_table.table(
        reward_property_premium_modifier.schema,
        modifiers,
      )),
    ),
    #(
      "CharacterCustomizationLabel",
      planted_table.bytes(
        planted_table.table(character_customization_label.schema, []),
      ),
    ),
  ])
  then(store.load(
    under: reference.new(),
    from: folder,
    entries: [
      character_customization_label.entry(),
      customization_parameter_map.entry(),
      customization_parameter.entry(),
      reward_property_premium_modifier.entry(),
    ],
    requirements:,
  ))
}

fn map_row(parameter_id parameter_id: Int) -> List(planted_table.Cell) {
  planted_table.row(customization_parameter_map.schema, [
    #("ID", Integer(1)),
    #("raceId", Integer(1)),
    #("genderEnum", Integer(male)),
    #("customizationParameterId", Integer(parameter_id)),
  ])
}

fn parameter_row(id id: Int, scl_x scl_x: Int) -> List(planted_table.Cell) {
  planted_table.row(customization_parameter.schema, [
    #("ID", Integer(id)),
    #("sclX", Integer(scl_x)),
  ])
}

fn slots_row(
  id id: Int,
  property property: Int,
  slots slots: Int,
) -> List(planted_table.Cell) {
  planted_table.row(reward_property_premium_modifier.schema, [
    #("ID", Integer(id)),
    #("premiumSystemEnum", Integer(1)),
    #("tier", Integer(0)),
    #("rewardPropertyId", Integer(property)),
    #("modifierValueInt", Integer(slots)),
  ])
}

pub fn the_load_fails_when_a_map_row_names_a_parameter_the_table_has_no_row_for_test() -> Nil {
  use <- owned_test.run(30_000)
  use loaded <- load_planted(
    map: [map_row(parameter_id: 5)],
    parameters: [parameter_row(id: 1, scl_x: 1)],
    modifiers: [],
    requirements: customisation.requirements(),
  )
  assert loaded
    == Error(RowMissing(
      from_table: "CustomizationParameterMap",
      column: "customizationParameterId",
      to_table: "CustomizationParameter",
      id: 5,
    ))
    as "CLAUDE.md: game tables load once at start into named records; a missing row fails the load, and a parameter row that is missing is no 0 bone values (opcode.0x25b.counts: the client counts a bone value for each part the CustomizationParameter row of each map row sets)"
}

pub fn the_load_passes_and_the_parts_are_counted_when_every_parameter_row_is_there_test() -> Nil {
  use <- owned_test.run(30_000)
  use loaded <- load_planted(
    map: [map_row(parameter_id: 5)],
    parameters: [parameter_row(id: 5, scl_x: 7)],
    modifiers: [],
    requirements: customisation.requirements(),
  )
  let assert Ok(tables) = loaded as "every parameter the map names has a row"
  assert customisation.bone_count(customisation.of(tables), 1, male) == 1
    as "opcode.0x25b.counts: one bone value for the one part (sclX) the row sets"
}

pub fn the_load_fails_when_the_hybrid_character_slots_row_is_missing_test() -> Nil {
  use <- owned_test.run(30_000)
  use loaded <- load_planted(
    map: [],
    parameters: [],
    modifiers: [slots_row(id: 1, property: 28, slots: 2)],
    requirements: character_slots.requirements(),
  )
  assert loaded
    == Error(RowMissing(
      from_table: "the server's character slots",
      column: "rewardPropertyId",
      to_table: "RewardPropertyPremiumModifier",
      id: 29,
    ))
    as "CLAUDE.md: a missing row fails the load; an account with no CharacterSlots row of the Hybrid system at the base tier has no slots to give (AccountItemLib.CodeEnumRewardProperty: 29 is CharacterSlots)"
}

pub fn the_load_passes_and_the_slots_are_the_rows_value_when_the_row_is_there_test() -> Nil {
  use <- owned_test.run(30_000)
  use loaded <- load_planted(
    map: [],
    parameters: [],
    modifiers: [slots_row(id: 117, property: 29, slots: 2)],
    requirements: character_slots.requirements(),
  )
  let assert Ok(tables) = loaded as "the CharacterSlots row is there"
  assert character_slots.hybrid(tables) == 2
    as "RewardPropertyPremiumModifier row 117: the Hybrid system's CharacterSlots at the base tier is 2"
}
