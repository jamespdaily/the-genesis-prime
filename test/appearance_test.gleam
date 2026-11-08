//// A character's body visuals from its stored look, and the bone count a race
//// and sex have (`genesis_prime/game/appearance`). Expected values come from
//// these places.
//// - The client's rule: PickCustomizationDisplays 0x140031c90 and the emulator
////   vector vector.0x140031c90 (the most label-value pairs win, the earliest
////   row breaks a tie, a label-free row is the default), the look's rows
////   (CharacterCustomization.flags, SetLookLabel 0x1400310b0, ResetLook
////   0x140030e30, BuildCustomizationIndex 0x14001d450) and the bone counts
////   (opcode.0x25b.counts).
//// - The rows of the client's own CharacterCustomization and
////   CharacterCustomizationLabel tables, read from the real files.
//// The vector gives a slot's rows in the order the client's set holds them;
//// a planted table lists its rows in that order, the order of the table's
//// records.

import character_tables
import client_tables
import fixture_tables
import genesis_prime/game/appearance
import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/store.{LookEntry}
import genesis_prime/table/character_customization.{
  type CharacterCustomization, CharacterCustomization,
}
import genesis_prime/table/character_customization_label.{
  type CharacterCustomizationLabel, CharacterCustomizationLabel,
}
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/id.{
  CharacterCustomizationId, CharacterCustomizationLabelId, RaceId,
}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import owned_test
import planted_table.{Integer}
import unitest

/// A face (slot 25) row of race 1, sex 0 that the index holds (flags 2), with
/// its labels and values (0 for none).
fn row(
  id id: Int,
  display display: Int,
  labels labels: List(#(Int, Int)),
) -> CharacterCustomization {
  row_in(id:, slot: 25, display:, labels:)
}

fn row_in(
  id id: Int,
  slot slot: Int,
  display display: Int,
  labels labels: List(#(Int, Int)),
) -> CharacterCustomization {
  let #(first, first_value) = case labels {
    [pair, ..] -> pair
    [] -> #(0, 0)
  }
  let #(second, second_value) = case labels {
    [_, pair, ..] -> pair
    _ -> #(0, 0)
  }
  CharacterCustomization(
    id:,
    race_id: 1,
    gender: 0,
    item_slot_id: slot,
    item_display_id: display,
    flags: 2,
    character_customization_label_id00: first,
    character_customization_label_id01: second,
    value00: first_value,
    value01: second_value,
  )
}

/// A label the player may set whatever the faction (faction2Id 0).
fn label(id: Int) -> CharacterCustomizationLabel {
  label_of(id:, faction: 0)
}

fn label_of(id id: Int, faction faction: Int) -> CharacterCustomizationLabel {
  CharacterCustomizationLabel(
    id:,
    localized_text_id: 0,
    faction2_id: faction,
    display_index: 0,
  )
}

fn look(pairs: List(#(Int, Int))) -> List(store.LookEntry) {
  list.map(pairs, fn(pair) {
    LookEntry(label: CharacterCustomizationLabelId(pair.0), value: pair.1)
  })
}

fn visuals(
  rows rows: List(CharacterCustomization),
  labels labels: List(CharacterCustomizationLabel),
  faction faction: Int,
  look pairs: List(#(Int, Int)),
) -> List(item_visual.ItemVisual) {
  appearance.body_visuals(
    index: appearance.index_from_rows(rows:, labels:),
    race_id: RaceId(1),
    sex: 0,
    faction_id: faction,
    look: look(pairs),
  )
}

fn face(display: Int) -> ItemVisual {
  ItemVisual(slot: 25, display_id: display, item_color_set_id: 0, dye: 0)
}

// ---- the emulator vector, vector.0x140031c90 ----

pub fn the_row_with_the_most_pairs_wins_a_slot_test() -> Nil {
  use <- owned_test.run(5000)
  // vector.0x140031c90: a label-free row (101), a row with one pair (102) and
  // a row with two pairs (103) give 103.
  let rows = [
    row(id: 1, display: 101, labels: []),
    row(id: 2, display: 102, labels: [#(1, 1)]),
    row(id: 3, display: 103, labels: [#(1, 1), #(2, 1)]),
  ]
  assert visuals(rows:, labels: [label(1), label(2)], faction: 166, look: [
      #(1, 1),
      #(2, 1),
    ])
    == [face(103)]
    as "vector.0x140031c90: two pairs beat one pair, which beats the default"
}

pub fn the_earliest_row_breaks_a_tie_between_rows_with_as_many_pairs_test() -> Nil {
  use <- owned_test.run(5000)
  // vector.0x140031c90: a label-free row, then two rows with two pairs each
  // (102, 103) give 102.
  let rows = [
    row(id: 1, display: 101, labels: []),
    row(id: 2, display: 102, labels: [#(1, 1), #(2, 1)]),
    row(id: 3, display: 103, labels: [#(1, 1), #(2, 1)]),
  ]
  assert visuals(rows:, labels: [label(1), label(2)], faction: 166, look: [
      #(1, 1),
      #(2, 1),
    ])
    == [face(102)]
    as "vector.0x140031c90: on a tie the first row of the slot's set wins; the sets are ordered by the rows' address, which is the table's record order"
}

pub fn a_label_at_value_0_in_a_row_is_no_pair_and_does_not_constrain_it_test() -> Nil {
  use <- owned_test.run(5000)
  // vector.0x140031c90: a row with one pair and one label at value 0 (101), a
  // label-free row (102) and a row with one pair (103) give 101: the first of
  // the two rows with one pair.
  let rows = [
    row(id: 1, display: 101, labels: [#(1, 1), #(2, 0)]),
    row(id: 2, display: 102, labels: []),
    row(id: 3, display: 103, labels: [#(1, 1)]),
  ]
  assert visuals(rows:, labels: [label(1), label(2)], faction: 166, look: [
      #(1, 1),
    ])
    == [face(101)]
    as "vector.0x140031c90, CharacterCustomization.flags: a label at value 0 in the row counts no pair and does not constrain it"
}

pub fn three_label_free_rows_give_the_first_test() -> Nil {
  use <- owned_test.run(5000)
  // vector.0x140031c90: three label-free rows give the first (101).
  let rows = [
    row(id: 1, display: 101, labels: []),
    row(id: 2, display: 102, labels: []),
    row(id: 3, display: 103, labels: []),
  ]
  assert visuals(rows:, labels: [], faction: 166, look: []) == [face(101)]
    as "vector.0x140031c90: no pairs anywhere, so the earliest row"
}

// ---- the look ----

pub fn the_label_free_row_fills_a_slot_no_pair_matches_and_a_slot_with_no_row_is_left_out_test() -> Nil {
  use <- owned_test.run(5000)
  // Slot 24 has a default (50) and a row for label 1 at value 3 (51); slot 26
  // has one row, for label 1 at value 2 (52); slot 27 has only a row for label
  // 1 at value 3 (53).
  let rows = [
    row_in(id: 1, slot: 24, display: 50, labels: []),
    row_in(id: 2, slot: 24, display: 51, labels: [#(1, 3)]),
    row_in(id: 3, slot: 26, display: 52, labels: [#(1, 2)]),
    row_in(id: 4, slot: 27, display: 53, labels: [#(1, 3)]),
  ]
  assert visuals(rows:, labels: [label(1)], faction: 166, look: [#(1, 2)])
    == [
      ItemVisual(slot: 24, display_id: 50, item_color_set_id: 0, dye: 0),
      ItemVisual(slot: 26, display_id: 52, item_color_set_id: 0, dye: 0),
    ]
    as "CharacterCustomization.flags: the label-free row is the default of slot 24; slot 26's row matches; slot 27 has no row that matches and no default, so it has none (0x140030e30)"
  assert visuals(rows:, labels: [label(1)], faction: 166, look: [#(1, 3)])
    == [
      ItemVisual(slot: 24, display_id: 51, item_color_set_id: 0, dye: 0),
      ItemVisual(slot: 27, display_id: 53, item_color_set_id: 0, dye: 0),
    ]
    as "label 1 at value 3 selects slot 24's row for it over the default, and slot 27's"
}

pub fn a_label_the_look_does_not_name_takes_its_lowest_value_test() -> Nil {
  use <- owned_test.run(5000)
  // ResetLook 0x140030e30 sets every label the race and sex have to its lowest
  // value before it applies the look.
  let rows = [
    row_in(id: 1, slot: 26, display: 52, labels: [#(1, 2)]),
    row_in(id: 2, slot: 26, display: 54, labels: [#(1, 3)]),
  ]
  assert visuals(rows:, labels: [label(1)], faction: 166, look: [])
    == [ItemVisual(slot: 26, display_id: 52, item_color_set_id: 0, dye: 0)]
    as "ResetLook 0x140030e30: label 1's lowest value is 2"
}

pub fn a_look_value_no_row_has_for_the_label_is_ignored_test() -> Nil {
  use <- owned_test.run(5000)
  // SetLookLabel 0x1400310b0 does nothing unless the index holds the label
  // and value for the race and sex.
  let rows = [
    row_in(id: 1, slot: 26, display: 52, labels: [#(1, 2)]),
    row_in(id: 2, slot: 26, display: 54, labels: [#(1, 3)]),
  ]
  assert visuals(rows:, labels: [label(1)], faction: 166, look: [#(1, 9)])
    == [ItemVisual(slot: 26, display_id: 52, item_color_set_id: 0, dye: 0)]
    as "SetLookLabel 0x1400310b0: value 9 is held by no row, so label 1 keeps its lowest value"
}

pub fn a_label_of_the_other_faction_is_ignored_and_its_rows_are_not_candidates_test() -> Nil {
  use <- owned_test.run(5000)
  // CharacterCustomizationLabel: label 21 is faction 166's, label 22 faction
  // 167's (faction2Id). SetLookLabel 0x1400310b0 refuses a label whose faction
  // is neither 0 nor the look's; BuildCustomizationIndex 0x14001d450 files a
  // row under the faction of its first label that names one.
  let rows = [
    row(id: 1, display: 135, labels: [#(22, 1), #(2, 1)]),
    row(id: 2, display: 137, labels: [#(21, 2), #(2, 1)]),
  ]
  let labels = [
    label(2),
    label_of(id: 21, faction: 166),
    label_of(id: 22, faction: 167),
  ]
  assert visuals(rows:, labels:, faction: 166, look: [
      #(2, 1),
      #(21, 2),
      #(22, 1),
    ])
    == [face(137)]
    as "a Dominion look keeps its own faction's row and never gets the Exile row"
  assert visuals(rows:, labels:, faction: 167, look: [
      #(2, 1),
      #(21, 2),
      #(22, 1),
    ])
    == [face(135)]
    as "an Exile look keeps its own faction's row"
}

// ---- a look checked against the index ----

/// The fault, if any, in a look for the race, sex and faction, against the
/// index of the rows and labels.
fn look_fault(
  rows rows: List(CharacterCustomization),
  labels labels: List(CharacterCustomizationLabel),
  race race: Int,
  sex sex: Int,
  faction faction: Int,
  look pairs: List(#(Int, Int)),
) -> Result(Nil, appearance.LookFault) {
  appearance.check_look(
    index: appearance.index_from_rows(rows:, labels:),
    race_id: RaceId(race),
    sex:,
    faction_id: faction,
    look: look(pairs),
  )
}

pub fn a_look_is_held_by_the_index_of_its_race_and_sex_test() -> Nil {
  use <- owned_test.run(5000)
  // SetLookValue 0x14002ec40 and SetLookLabel 0x1400310b0 accept a (label,
  // value) only when the index holds it for the race and sex; the index files
  // each row under its race and sex (BuildCustomizationIndex 0x14001d450).
  let rows = [
    row(id: 1, display: 10, labels: [#(5, 1)]),
    CharacterCustomization(
      ..row(id: 2, display: 11, labels: [#(5, 2)]),
      gender: 1,
    ),
    CharacterCustomization(
      ..row(id: 3, display: 12, labels: [#(5, 3)]),
      race_id: 2,
    ),
  ]
  let labels = [label(5)]
  let fault = fn(pairs, race, sex) {
    look_fault(rows:, labels:, race:, sex:, faction: 167, look: pairs)
  }
  assert fault([#(5, 1)], 1, 0) == Ok(Nil)
    as "row 1 holds label 5 at 1 for race 1, sex 0"
  assert fault([#(5, 2)], 1, 0)
    == Error(appearance.ValueNotHeld(
      label: CharacterCustomizationLabelId(5),
      value: 2,
    ))
    as "label 5 at 2 is held only for race 1, sex 1 (row 2)"
  assert fault([#(5, 2)], 1, 1) == Ok(Nil)
    as "row 2 holds label 5 at 2 for race 1, sex 1"
  assert fault([#(5, 3)], 1, 1)
    == Error(appearance.ValueNotHeld(
      label: CharacterCustomizationLabelId(5),
      value: 3,
    ))
    as "label 5 at 3 is held only for race 2 (row 3)"
  assert fault([#(5, 3)], 2, 0) == Ok(Nil)
    as "row 3 holds label 5 at 3 for race 2, sex 0"
  assert fault([], 1, 0) == Ok(Nil) as "a look with no label has no fault"
}

pub fn a_look_label_of_another_faction_or_with_no_label_row_has_a_fault_test() -> Nil {
  use <- owned_test.run(5000)
  // CharacterCustomizationLabel: label 21 is faction 166's, label 22 faction
  // 167's (faction2Id); SetLookLabel 0x1400310b0 refuses a label whose faction
  // is neither 0 nor the look's, and a label with no row.
  let rows = [
    row(id: 1, display: 135, labels: [#(22, 1), #(2, 1)]),
    row(id: 2, display: 137, labels: [#(21, 2), #(2, 1)]),
  ]
  let labels = [
    label(2),
    label_of(id: 21, faction: 166),
    label_of(id: 22, faction: 167),
  ]
  let fault = fn(faction, pairs) {
    look_fault(rows:, labels:, race: 1, sex: 0, faction:, look: pairs)
  }
  assert fault(167, [#(2, 1), #(22, 1)]) == Ok(Nil)
    as "label 2 is every faction's and label 22 is Exile's"
  assert fault(167, [#(21, 2)])
    == Error(appearance.LabelNotAllowed(CharacterCustomizationLabelId(21)))
    as "label 21 is Dominion's"
  assert fault(166, [#(22, 1)])
    == Error(appearance.LabelNotAllowed(CharacterCustomizationLabelId(22)))
    as "label 22 is Exile's"
  assert fault(166, [#(2, 1), #(21, 2)]) == Ok(Nil)
    as "label 21 at 2 is Dominion's row 2"
  assert fault(166, [#(9, 1)])
    == Error(appearance.LabelNotAllowed(CharacterCustomizationLabelId(9)))
    as "label 9 has no CharacterCustomizationLabel row"
}

// ---- the real rows ----

/// The four looks of a human male's face, checked against the index the
/// tables' load built. CharacterCustomization rows 2, 9 and 10 (race 1, sex 0,
/// slot 25): row 2 labels 22 = 1 and 2 = 1, display 135; row 9 labels 22 = 2
/// and 2 = 1, display 136; row 10 labels 21 = 2 and 2 = 1, display 137.
/// CharacterCustomizationLabel: 21 is faction 166's, 22 faction 167's.
fn assert_the_faces_follow_the_looks_labels(tables: table_store.Tables) -> Nil {
  let index = appearance.index(tables:)
  let face_of = fn(faction, pairs) {
    let visuals =
      appearance.body_visuals(
        index:,
        race_id: RaceId(1),
        sex: 0,
        faction_id: faction,
        look: look(pairs),
      )
    let assert Ok(visual) = list.find(visuals, fn(v) { v.slot == 25 })
      as "the face slot has a display"
    visual.display_id
  }
  assert face_of(167, [#(2, 1), #(22, 1)]) == 135
    as "CharacterCustomization row 2: an Exile with labels 22 = 1 and 2 = 1"
  assert face_of(167, [#(2, 1), #(22, 2)]) == 136
    as "CharacterCustomization row 9: labels 22 = 2 and 2 = 1"
  assert face_of(166, [#(2, 1), #(21, 2)]) == 137
    as "CharacterCustomization row 10: a Dominion with labels 21 = 2 and 2 = 1"
  assert face_of(166, [#(2, 1), #(21, 2), #(22, 1)]) == 137
    as "label 22 is faction 167's, so a Dominion look ignores it"
  let assert Ok(row_10) =
    character_customization.get(tables:, id: CharacterCustomizationId(10))
    as "row 10 exists"
  assert row_10.item_display_id == 137 && row_10.item_slot_id == 25
    as "the real row the expected 137 comes from"
}

pub fn the_index_a_load_builds_gives_a_human_males_face_from_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  assert_the_faces_follow_the_looks_labels(fixture_tables.shared())
}

pub fn every_slot_of_a_real_look_is_listed_once_in_slot_order_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let slots =
    appearance.body_visuals(
      index: appearance.index(tables:),
      race_id: RaceId(1),
      sex: 0,
      faction_id: 166,
      look: look([#(2, 1), #(21, 2)]),
    )
    |> list.map(fn(visual) { visual.slot })
  assert slots == list.unique(slots) && slots == list.sort(slots, int.compare)
    as "PickCustomizationDisplays 0x140031c90 gives one display for each slot of the slot map, in slot order"
  assert list.contains(slots, 25) && list.contains(slots, 24)
    as "BodySkin 24 and BodyFace 25 are dressed (CharacterCustomization.flags)"
}

// ---- the bone count ----

pub fn a_race_and_sex_have_the_bone_count_the_clients_create_request_carries_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // opcode.0x25b.counts: 48 for race 1, 3 and 12 male; 46 for race 1 and 3
  // female, races 4 and 5 both sexes, race 13 male and race 16 both sexes; 41
  // for race 12 female.
  list.each(
    [
      #(1, 0, 48),
      #(3, 0, 48),
      #(12, 0, 48),
      #(1, 1, 46),
      #(3, 1, 46),
      #(4, 0, 46),
      #(4, 1, 46),
      #(5, 0, 46),
      #(5, 1, 46),
      #(13, 0, 46),
      #(16, 0, 46),
      #(16, 1, 46),
      #(12, 1, 41),
    ],
    fn(case_) {
      let #(race, sex, count) = case_
      assert appearance.bone_count(tables:, race_id: RaceId(race), sex:)
        == count
        as "opcode.0x25b.counts: the bone values a create request carries for this race and sex"
    },
  )
}

// ---- the rows the load requires ----

/// Loads a CustomizationParameterMap with one map naming parameter id 7 and a
/// CustomizationParameter table with the rows of these ids, with the
/// appearance's requirements.
fn load_a_map_naming_parameter_7(
  parameters parameters: List(Int),
) -> Result(table_store.Tables, table_store.LoadError) {
  load_appearance_tables(replacing: [
    character_tables.map_file_naming(parameter_id: 7),
    planted_table.file(
      customization_parameter.schema,
      list.map(parameters, fn(id) {
        planted_table.row(customization_parameter.schema, [
          #("ID", Integer(id)),
        ])
      }),
    ),
  ])
}

pub fn the_load_fails_when_a_map_names_a_customization_parameter_row_that_is_missing_test() -> Nil {
  use <- owned_test.run(60_000)
  assert load_a_map_naming_parameter_7(parameters: [1, 8])
    == Error(table_store.RowMissing(
      from_table: "CustomizationParameterMap",
      column: "customizationParameterId",
      to_table: "CustomizationParameter",
      id: 7,
    ))
    as "a create request's bone count reads the CustomizationParameter row each map of the race and sex names (opcode.0x25b.counts), so a load without that row fails, naming it"
  let assert Ok(_) = load_a_map_naming_parameter_7(parameters: [1, 7, 8])
    as "the row the map names is there, so the load holds"
  Nil
}

/// Loads a CharacterCustomization table with one row of these flags and
/// labels, and a label table with a row of each of these ids, with the
/// appearance's requirements.
fn load_a_row_naming_labels(
  flags flags: Int,
  labels labels: #(Int, Int),
  label_rows label_rows: List(Int),
) -> Result(table_store.Tables, table_store.LoadError) {
  load_appearance_tables(replacing: [
    planted_table.file(character_customization.schema, [
      planted_table.row(character_customization.schema, [
        #("ID", Integer(1)),
        #("flags", Integer(flags)),
        #("characterCustomizationLabelId00", Integer(labels.0)),
        #("characterCustomizationLabelId01", Integer(labels.1)),
      ]),
    ]),
    planted_table.file(
      character_customization_label.schema,
      list.map(label_rows, fn(id) {
        planted_table.row(character_customization_label.schema, [
          #("ID", Integer(id)),
        ])
      }),
    ),
  ])
}

/// Loads the four tables the appearance's requirements read, each of no rows
/// but for the planted files that replace it, with those requirements.
fn load_appearance_tables(
  replacing replacing: List(#(String, BitArray)),
) -> Result(table_store.Tables, table_store.LoadError) {
  let files =
    list.fold(
      replacing,
      [
        planted_table.file(character_customization.schema, []),
        planted_table.file(character_customization_label.schema, []),
        planted_table.file(customization_parameter_map.schema, []),
        planted_table.file(customization_parameter.schema, []),
      ],
      fn(files, file) { list.key_set(files, file.0, file.1) },
    )
  use folder <- planted_table.in_folder(files)
  table_store.read(
    from: folder,
    entries: [
      character_customization.entry(),
      character_customization_label.entry(),
      customization_parameter_map.entry(),
      customization_parameter.entry(),
    ],
    requirements: appearance.requirements(),
    derivations: [],
  )
}

pub fn the_load_fails_when_an_indexed_rows_label_has_no_label_row_test() -> Nil {
  use <- owned_test.run(60_000)
  assert load_a_row_naming_labels(flags: 2, labels: #(77, 0), label_rows: [2])
    == Error(table_store.RowMissing(
      from_table: "CharacterCustomization",
      column: "characterCustomizationLabelId00",
      to_table: "CharacterCustomizationLabel",
      id: 77,
    ))
    as "BuildCustomizationIndex 0x14001d450 files a row with flags bit 2 set, so its first label is followed into CharacterCustomizationLabel"
  assert load_a_row_naming_labels(flags: 2, labels: #(2, 78), label_rows: [2])
    == Error(table_store.RowMissing(
      from_table: "CharacterCustomization",
      column: "characterCustomizationLabelId01",
      to_table: "CharacterCustomizationLabel",
      id: 78,
    ))
    as "the row's second label is followed too"
  let assert Ok(_) =
    load_a_row_naming_labels(flags: 2, labels: #(2, 0), label_rows: [2])
    as "label 0 is none, and label 2 has its row"
  Nil
}

pub fn a_row_the_index_does_not_hold_may_name_a_label_with_no_row_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([1, 3, 4, 6], fn(flags) {
    let assert Ok(_) =
      load_a_row_naming_labels(flags:, labels: #(77, 0), label_rows: [2])
      as {
        "BuildCustomizationIndex 0x14001d450 files a row only with flags bit 2 set and bits 1 and 4 clear, so a row of flags "
        <> int.to_string(flags)
        <> " is never read through its label"
      }
  })
}

pub fn the_client_has_every_row_the_appearance_requirements_name_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(appearance.requirements(), fn(requirement) {
    assert requirement.missing(tables) == []
      as {
        "the client's "
        <> requirement.from_table
        <> " "
        <> requirement.column
        <> " names a row of "
        <> requirement.to_table
        <> " in every row, so the server's table load holds"
      }
  })
}
