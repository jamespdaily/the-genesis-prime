//// What the server checks of a create request (`genesis_prime/game/character_creation`)
//// before the store is asked. Expected values come from these places.
//// - The client's create path: IsCharacterNameValid and rule 0 (0x1403e1170),
////   LuaCreateCharacter 0x140023e90 (the checks the real client makes before
////   it sends 0x25B: the row, its entitlement and cost, the path up to 3) and
////   the request's counts and looks (opcode.0x25b, opcode.0x25b.counts: at
////   most 25 labels, each once and in label-id order, only labels allowed for
////   the faction and values the race and sex's index holds; 41, 46 or 48
////   bones by race and sex).
//// - The rows of the client's own CharacterCreation table (the shared load): 466 is a PreTutorial row (class 1, race 1, sex 1, faction 167, no
////   entitlement, no cost, xp 0), 338 and 339 Nexus rows (xp 1710), 539 a
////   Level50 row costing 1 of account currency 13, 536 a Nexus row needing
////   entitlement 61, 21 a disabled Arkship row (start 0) and 530 a
////   costume-only row (class 0).
//// - The level of a created character: the row's xp through GetLevelForExperience
////   0x140029820 (fact `CharacterCreation.xp`): 0 is level 1 and 1710 is level 3.
//// - The results the client's creation Lua names
////   (lua.Character.OnCreateCharacterFailed): 10 for a name, and the text "due
////   to an error" for every other value, 4 CreateFailed among them.

import character_support
import character_tables
import client_tables
import fixture_tables
import genesis_prime/game/appearance
import genesis_prime/game/character_creation.{
  BoneNotFinite, CostsCurrency, CostumeOnlyRow, LabelNotAllowed,
  LabelsNotIncreasing, LookValueNotHeld, NeedsEntitlement, NoLevelForExperience,
  NoStartPlace, NoSuchRow, PathAbove3, RowDisabled, TooManyLabels,
  WrongBoneCount,
}
import genesis_prime/game/start_place.{Level50, Novice, OtherStart, Veteran}
import genesis_prime/message/create_character.{
  type CreateCharacter, CreateCharacter,
}
import genesis_prime/message/create_result
import genesis_prime/store.{LookEntry, NewCharacter}
import genesis_prime/table/character_creation as creation_table
import genesis_prime/table/id.{
  CharacterCreationId, CharacterCustomizationLabelId, ClassId, RaceId,
}
import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import owned_test
import planted_table.{Integer}
import unitest

/// A request for the creation row with the name.
fn request(creation_id: Int, name: String) -> CreateCharacter {
  CreateCharacter(..character_support.create_request(name), creation_id:)
}

pub fn a_name_that_breaks_rule_0_is_the_stores_to_refuse_and_the_row_is_checked_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(character) =
    character_creation.check(tables, request(466, "Abcd"))
    as "the name's rule 0 is held by the table's character_name_follows_rule_0, so this check passes the name on and the store's refusal is the client's 10 (migration 0014)"
  assert character.name == "Abcd"
  assert character_creation.check(tables, request(99_999, "Abcd"))
    == Error(NoSuchRow(creation_id: 99_999))
    as "a request that breaks the name and the row is answered for the row"
}

pub fn a_valid_request_gives_the_new_character_from_its_creation_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let asked =
    CreateCharacter(
      ..request(466, "Ab Cd"),
      path: 2,
      customisation_labels: [2, 22],
      customisation_values: [1, 1],
    )
  assert character_creation.check(tables, asked)
    == Ok(
      NewCharacter(
        name: "Ab Cd",
        gender: 1,
        race_id: RaceId(1),
        class_id: ClassId(1),
        faction_id: 167,
        level: 1,
        path: 2,
        place: character_tables.novice_start_place(),
        look: [
          LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
          LookEntry(label: CharacterCustomizationLabelId(22), value: 1),
        ],
        bones: character_support.bones(46),
        starting_items: [],
      ),
    )
    as "CharacterCreation row 466: class 1, race 1, sex 1, faction 167; the path, the labels with their values and the bone values as the request carries them (opcode.0x25b); xp 0, so level 1 (0x140029820); a PreTutorial start, so the place of WorldLocation2 row 51596: World 3460, zone 6009 and its position"
}

pub fn a_nexus_row_gives_the_character_the_place_of_its_veteran_start_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(character) =
    character_creation.check(tables, request(338, "Ab Cd"))
    as "CharacterCreation row 338 is an enabled Nexus row with no entitlement and no cost"
  assert character_tables.is_the_place_of(
    place: character.place,
    row: character_tables.start_row(42_074),
  )
    as "row 338 is the Veteran start (3) of Exile (167) Human (1): WorldLocation2 row 42074, World 426, zone 648 (Quest2.10528.links, whose text sends the Exile humans and Granok there), facing the client's yaw of the row"
}

pub fn a_row_that_is_missing_disabled_arkship_costume_only_or_needs_what_the_account_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert character_creation.check(tables, request(99_999, "Ab Cd"))
    == Error(NoSuchRow(creation_id: 99_999))
    as "LuaCreateCharacter 0x140023e90: a missing row is refused"
  let assert Ok(row) = creation_table.get(tables:, id: CharacterCreationId(466))
    as "CharacterCreation row 466 exists"
  let check_row = fn(changed) {
    character_creation.check_row(tables, changed, request(466, "Ab Cd"))
  }
  assert check_row(creation_table.CharacterCreation(..row, enabled: False))
    == Error(RowDisabled(creation_id: 466))
    as "the enabled column: a disabled row is no choice"
  assert check_row(creation_table.CharacterCreation(..row, costume_only: True))
    == Error(CostumeOnlyRow(creation_id: 466))
    as "a costume-only row is for the create screen's model and makes no character (rows 530 and 531 have class 0)"
  assert character_creation.check(tables, request(21, "Ab Cd"))
    == Error(RowDisabled(creation_id: 21))
    as "CharacterCreation row 21 is a disabled Arkship row (start 0), which is refused for its enabled column"
  assert character_creation.check(tables, request(530, "Ab Cd"))
    == Error(CostumeOnlyRow(creation_id: 530))
    as "CharacterCreation row 530: costume only, class 0"
  assert character_creation.check(tables, request(536, "Ab Cd"))
    == Error(NeedsEntitlement(creation_id: 536))
    as "CharacterCreation row 536: a Nexus row needing entitlement 61, which no account holds yet (0x140023e90)"
  assert character_creation.check(tables, request(539, "Ab Cd"))
    == Error(CostsCurrency(creation_id: 539))
    as "CharacterCreation row 539: a Level50 row costing 1 of account currency 13, which no account holds yet (0x140023e90)"
}

pub fn a_path_above_3_or_the_wrong_bone_count_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert result.is_ok(character_creation.check(
    tables,
    CreateCharacter(..request(466, "Ab Cd"), path: 3),
  ))
    as "0x140023e90: path 3 is allowed"
  assert character_creation.check(
      tables,
      CreateCharacter(..request(466, "Ab Cd"), path: 4),
    )
    == Error(PathAbove3(creation_id: 466, path: 4))
    as "0x140023e90: a path above 3 is refused"
  assert character_creation.check(
      tables,
      CreateCharacter(
        ..request(466, "Ab Cd"),
        bone_values: character_support.bones(45),
      ),
    )
    == Error(WrongBoneCount(creation_id: 466, expected: 46, got: 45))
    as "opcode.0x25b.counts: race 1, sex 1 carries 46 bone values"
  assert character_creation.check(
      tables,
      CreateCharacter(
        ..request(339, "Ab Cd"),
        bone_values: character_support.bones(46),
      ),
    )
    == Error(WrongBoneCount(creation_id: 339, expected: 48, got: 46))
    as "opcode.0x25b.counts: race 1, sex 0 carries 48"
  assert result.is_ok(character_creation.check(
    tables,
    CreateCharacter(
      ..request(339, "Ab Cd"),
      bone_values: character_support.bones(48),
    ),
  ))
    as "race 1, sex 0 with 48 bone values"
}

/// The client's rows edited into a look that holds all 27 labels. Kept edit:
/// no client look holds 25 labels, since a faction's labels number 22 at most
/// (the 17 labels of faction 0 and the 5 of faction 167), so every label is made
/// faction 0 and each is held, at the value 1, by an added row of race 1, sex 1.
fn rows_with_a_look_of_every_label() -> fixture_tables.Rows {
  let labels = character_support.numbers(27)
  let assert Ok(rows) =
    list.try_fold(labels, fixture_tables.rows(), fn(rows, label) {
      fixture_tables.change(
        rows:,
        table: "CharacterCustomizationLabel",
        id: label,
        with: [#("faction2Id", Integer(0))],
      )
    })
    as "the client's CharacterCustomizationLabel holds labels 1 to 27"
  let assert Ok(rows) =
    list.try_fold(labels, rows, fn(rows, label) {
      fixture_tables.add(
        rows:,
        table: "CharacterCustomization",
        copy_of: 603,
        id: 900_000 + label,
        with: [
          #("itemDisplayId", Integer(2000 + label)),
          #("characterCustomizationLabelId00", Integer(label)),
          #("value00", Integer(1)),
          #("characterCustomizationLabelId01", Integer(0)),
          #("value01", Integer(0)),
        ],
      )
    })
    as "the client's CharacterCustomization holds row 603, of race 1 and sex 1"
  rows
}

pub fn a_request_with_more_than_25_look_labels_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.on_rows(
    rows: rows_with_a_look_of_every_label(),
    reaching: [],
  )
  let with_labels = fn(count) {
    CreateCharacter(
      ..request(466, "Ab Cd"),
      customisation_labels: character_support.numbers(count),
      customisation_values: list.repeat(1, count),
    )
  }
  assert result.is_ok(character_creation.check(tables, with_labels(25)))
    as "opcode.0x25b.counts: a look holds at most 25 labels (labels 26 and 27 set the race and never enter a look), so 25 labels each held by the index are accepted"
  assert character_creation.check(tables, with_labels(26))
    == Error(TooManyLabels(creation_id: 466, count: 26))
    as "opcode.0x25b.counts: at most 25 labels"
  assert character_creation.check(tables, with_labels(27))
    == Error(TooManyLabels(creation_id: 466, count: 27))
    as "opcode.0x25b.counts: at most 25 labels, not the label table's 27"
}

/// A request for row 466 (race 1, sex 1, faction 167) with the look.
fn looking(pairs: List(#(Int, Int))) -> CreateCharacter {
  CreateCharacter(
    ..request(466, "Ab Cd"),
    customisation_labels: list.map(pairs, pair.first),
    customisation_values: list.map(pairs, pair.second),
  )
}

pub fn a_label_that_repeats_is_refused_and_says_which_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert character_creation.check(tables, looking([#(2, 1), #(2, 1)]))
    == Error(LabelsNotIncreasing(creation_id: 466, previous: 2, label: 2))
    as "opcode.0x25b.counts: each label at most once; CharacterCustomization rows 603 and 604 hold label 2 at 1, so only the repeat refuses it"
  assert result.is_ok(character_creation.check(tables, looking([#(2, 1)])))
    as "label 2 at value 1 is held by CharacterCustomization row 603 (race 1, sex 1)"
}

pub fn labels_out_of_label_id_order_are_refused_and_say_which_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert character_creation.check(tables, looking([#(22, 1), #(2, 1)]))
    == Error(LabelsNotIncreasing(creation_id: 466, previous: 22, label: 2))
    as "opcode.0x25b.counts: labels in label-id order; labels 2 and 22 at 1 are held by CharacterCustomization row 603 and allowed for faction 167, so only the order refuses it"
  assert result.is_ok(character_creation.check(
    tables,
    looking([#(2, 1), #(22, 1)]),
  ))
    as "the same look in label-id order is accepted"
}

pub fn a_label_of_another_faction_is_refused_and_says_which_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert character_creation.check(tables, looking([#(2, 1), #(21, 2)]))
    == Error(LabelNotAllowed(creation_id: 466, label: 21))
    as "CharacterCustomizationLabel row 21 is faction 166's, and row 466 is faction 167 (SetLookLabel 0x1400310b0)"
  assert character_creation.check(tables, looking([#(28, 1)]))
    == Error(LabelNotAllowed(creation_id: 466, label: 28))
    as "the client's CharacterCustomizationLabel has no row 28, and a label with no row can be set for no faction (SetLookLabel 0x1400310b0)"
}

pub fn the_race_labels_are_allowed_for_their_faction_only_and_no_look_holds_them_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(row) = creation_table.get(tables:, id: CharacterCreationId(466))
    as "CharacterCreation row 466 exists"
  let of_faction = fn(faction_id, label) {
    character_creation.check_row(
      tables,
      creation_table.CharacterCreation(..row, faction_id:),
      CreateCharacter(
        ..request(466, "Ab Cd"),
        customisation_labels: [label],
        customisation_values: [1],
      ),
    )
  }
  assert of_faction(166, 26)
    == Error(LookValueNotHeld(creation_id: 466, label: 26, value: 1))
    as "CharacterCustomizationLabel row 26 is faction 166's, so the label is allowed there; labels 26 and 27 set the race and never enter a look (opcode.0x25b.counts), so no CharacterCustomization row holds them"
  assert of_faction(167, 26)
    == Error(LabelNotAllowed(creation_id: 466, label: 26))
    as "label 26 is faction 166's, so it is not allowed for faction 167 (SetLookLabel 0x1400310b0)"
  assert of_faction(167, 27)
    == Error(LookValueNotHeld(creation_id: 466, label: 27, value: 1))
    as "CharacterCustomizationLabel row 27 is faction 167's, and no look holds it"
  assert of_faction(166, 27)
    == Error(LabelNotAllowed(creation_id: 466, label: 27))
    as "label 27 is faction 167's, so it is not allowed for faction 166"
}

pub fn a_value_the_index_does_not_hold_is_refused_and_says_which_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert character_creation.check(tables, looking([#(2, 1), #(22, 3)]))
    == Error(LookValueNotHeld(creation_id: 466, label: 22, value: 3))
    as "CharacterCustomization rows 603 and 604 hold label 22 at 1 and 2 for race 1, sex 1, so 3 is no value of the index (SetLookValue 0x14002ec40)"
  assert result.is_ok(character_creation.check(tables, looking([#(22, 2)])))
    as "label 22 at 2 is held by CharacterCustomization row 604 (race 1, sex 1)"
}

pub fn a_start_race_or_faction_with_no_start_place_is_refused_and_says_which_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(row) = creation_table.get(tables:, id: CharacterCreationId(466))
    as "CharacterCreation row 466 exists"
  let check_row = fn(changed) {
    character_creation.check_row(tables, changed, request(466, "Ab Cd"))
  }
  assert check_row(
      creation_table.CharacterCreation(..row, character_creation_start_enum: 7),
    )
    == Error(NoStartPlace(
      creation_id: 466,
      start: 7,
      faction_id: 167,
      race_id: 1,
    ))
    as "no start of the start places is 7 (genesis_prime/game/start_place): a start with no place is refused"
  assert check_row(creation_table.CharacterCreation(..row, faction_id: 168))
    == Error(NoStartPlace(
      creation_id: 466,
      start: 4,
      faction_id: 168,
      race_id: 1,
    ))
    as "no start place is of a faction other than 166 and 167"
  assert check_row(
      creation_table.CharacterCreation(..row, character_creation_start_enum: 0),
    )
    == Error(NoStartPlace(
      creation_id: 466,
      start: 0,
      faction_id: 167,
      race_id: 1,
    ))
    as "the Arkship start (0) has no start place, so an enabled row of it would be refused here"
  assert character_creation.result_of(NoStartPlace(
      creation_id: 466,
      start: 7,
      faction_id: 167,
      race_id: 1,
    ))
    == create_result.CreateFailed
    as "lua.Character.OnCreateCharacterFailed: 4 is shown as 'due to an error'"
}

pub fn a_bone_value_that_is_not_a_finite_float_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let with_bone = fn(bits) {
    CreateCharacter(..request(466, "Ab Cd"), bone_values: [
      bits,
      ..list.drop(character_support.bones(46), 1)
    ])
  }
  list.each(
    [
      #(0x7FC00000, "a quiet NaN"),
      #(0x7F800001, "a signalling NaN"),
      #(0xFFC00001, "a negative NaN"),
      #(0x7F800000, "positive infinity"),
      #(0xFF800000, "negative infinity"),
    ],
    fn(case_) {
      let #(bits, name) = case_
      assert character_creation.check(tables, with_bone(bits))
        == Error(BoneNotFinite(creation_id: 466))
        as { "IEEE 754 single precision: an exponent of all ones is " <> name }
    },
  )
  assert result.is_ok(character_creation.check(tables, with_bone(0x7F7FFFFF)))
    as "IEEE 754 single precision: 0x7F7FFFFF is the largest finite float"
  assert result.is_ok(character_creation.check(tables, with_bone(0xFF7FFFFF)))
    as "IEEE 754 single precision: 0xFF7FFFFF is the most negative finite float"
  assert result.is_ok(character_creation.check(tables, with_bone(0x00000000)))
    as "ExportBoneValues 0x1401e3580: a part the actor holds no adjustment for is 0.0"
}

pub fn every_refusal_but_the_name_is_create_failed_and_says_the_row_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      NoSuchRow(creation_id: 7),
      RowDisabled(creation_id: 7),
      CostumeOnlyRow(creation_id: 7),
      NeedsEntitlement(creation_id: 7),
      CostsCurrency(creation_id: 7),
      PathAbove3(creation_id: 7, path: 4),
      TooManyLabels(creation_id: 7, count: 26),
      LabelsNotIncreasing(creation_id: 7, previous: 22, label: 2),
      LabelNotAllowed(creation_id: 7, label: 21),
      LookValueNotHeld(creation_id: 7, label: 22, value: 3),
      WrongBoneCount(creation_id: 7, expected: 46, got: 45),
      BoneNotFinite(creation_id: 7),
      NoStartPlace(creation_id: 7, start: 7, faction_id: 167, race_id: 1),
      NoLevelForExperience(creation_id: 7, experience: -1),
    ],
    fn(refusal) {
      assert character_creation.result_of(refusal) == create_result.CreateFailed
        as "lua.Character.OnCreateCharacterFailed: 4 CreateFailed is shown as 'due to an error'"
      assert string.contains(character_creation.describe(refusal), "7")
        as "the warning names the creation row"
    },
  )
}

pub fn a_veteran_row_makes_a_level_3_character_and_a_novice_row_a_level_1_character_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let level_of = fn(creation_id) {
    let assert Ok(character) =
      character_creation.check(tables, request(creation_id, "Ab Cd"))
      as "the row is an enabled row with no entitlement and no cost"
    character.level
  }
  assert level_of(338) == 3
    as "CharacterCreation row 338 is a Nexus (Veteran) row, xp 1710, which GetLevelForExperience 0x140029820 makes level 3"
  assert level_of(466) == 1
    as "CharacterCreation row 466 is a PreTutorial (Novice) row, xp 0: level 1"
}

pub fn a_novice_character_of_every_class_is_made_on_the_shared_load_with_the_clients_look_place_and_level_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let novices =
    list.filter(character_support.novice_and_veteran_rows(tables), fn(row) {
      start_place.start(enum_value: row.character_creation_start_enum) == Novice
    })
  assert list.map(novices, fn(row) { creation_table.class_id(row).value })
    |> list.unique
    |> list.sort(int.compare)
    == [1, 2, 3, 4, 5, 7]
    as "the client's enabled PreTutorial rows hold every class the client makes: Warrior 1, Engineer 2, Esper 3, Medic 4, Stalker 5 and Spellslinger 7"
  list.each(novices, fn(row) {
    let character = character_support.new_character_of_row(tables:, row:)
    assert character.level == 1
      as {
        "CharacterCreation row "
        <> int.to_string(row.id)
        <> " is a PreTutorial row, xp 0: XpPerLevel record 1, level 1"
      }
    assert character_tables.is_the_place_of(
      place: character.place,
      row: character_tables.start_row(51_596),
    )
      as {
        "CharacterCreation row "
        <> int.to_string(row.id)
        <> " starts at WorldLocation2 row 51596"
      }
  })
  // CharacterCreation row 479: a Dominion human male Engineer, which row 10's
  // look (labels 2 = 1 and 21 = 2) is the look of.
  let assert Ok(row) = creation_table.get(tables:, id: CharacterCreationId(479))
    as "the client's CharacterCreation holds row 479"
  let look = character_tables.row_10_look()
  let assert Ok(_) =
    character_creation.check_row(
      tables,
      row,
      CreateCharacter(
        ..request(479, "Ab Cd"),
        customisation_labels: list.map(look, fn(entry) { entry.label.value }),
        customisation_values: list.map(look, fn(entry) { entry.value }),
        bone_values: list.repeat(
          0,
          appearance.bone_count(
            tables:,
            race_id: creation_table.race_id(row),
            sex: row.sex,
          ),
        ),
      ),
    )
    as "a Dominion human male's create with CharacterCustomization row 10's look passes the checks"
  // What the look shows (display 137 on slot 25) is checked by
  // `character_select_test`, from the client's rows.
  Nil
}

pub fn a_row_whose_xp_is_no_level_is_refused_and_says_which_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(row) = creation_table.get(tables:, id: CharacterCreationId(466))
    as "CharacterCreation row 466 exists"
  assert character_creation.check_row(
      tables,
      creation_table.CharacterCreation(..row, xp: -1),
      request(466, "Ab Cd"),
    )
    == Error(NoLevelForExperience(creation_id: 466, experience: -1))
    as "0x140029870 jl: an experience below XpPerLevel record 0's minXpForLevel gives -3, which is no level"
  assert character_creation.result_of(NoLevelForExperience(
      creation_id: 466,
      experience: -1,
    ))
    == create_result.CreateFailed
    as "lua.Character.OnCreateCharacterFailed: 4 is shown as 'due to an error'"
}

pub fn every_enabled_novice_and_veteran_row_of_the_clients_table_makes_the_level_its_start_gives_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = character_support.novice_and_veteran_rows(tables)
  assert rows != [] as "the client's table has enabled Novice and Veteran rows"
  list.each(rows, fn(row) {
    let #(expected, why) = case
      start_place.start(enum_value: row.character_creation_start_enum)
    {
      Veteran -> #(
        3,
        "Veteran (Nexus) rows have xp 1710 (fact CharacterCreation.xp), level 3",
      )
      Novice -> #(
        1,
        "Novice (PreTutorial) rows have xp 0 (fact CharacterCreation.xp), level 1",
      )
      Level50 | OtherStart(..) ->
        panic as "novice_and_veteran_rows holds only these two starts"
    }
    assert character_support.new_character_of_row(tables:, row:).level
      == expected
      as { "CharacterCreation row " <> int.to_string(row.id) <> ": " <> why }
  })
}

pub fn every_arkship_row_of_the_clients_table_is_disabled_so_the_enabled_check_refuses_it_first_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let arkship =
    list.filter(creation_table.all(tables), fn(row) {
      row.character_creation_start_enum == 0
    })
  assert list.length(arkship) == 64
    as "fact CharacterCreation.characterCreationStartEnum: 64 rows have start 0 (Arkship)"
  assert list.all(arkship, fn(row) { !row.enabled })
    as "fact CharacterCreation.characterCreationStartEnum: every Arkship row is disabled, so RowDisabled refuses it before its start is read"
  list.each(arkship, fn(row) {
    assert character_creation.check_row(tables, row, request(row.id, "Ab Cd"))
      == Error(RowDisabled(creation_id: row.id))
      as "a disabled Arkship row is refused for its enabled column"
  })
}
