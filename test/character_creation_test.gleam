//// What the server checks of a create request (`genesis_prime/game/character_creation`)
//// before the store is asked. Expected values come from these places.
//// - The client's create path: IsCharacterNameValid and rule 0 (0x1403e1170),
////   LuaCreateCharacter 0x140023e90 (the checks the real client makes before
////   it sends 0x25B: the row, its entitlement and cost, the path up to 3) and
////   the request's counts (opcode.0x25b, opcode.0x25b.counts: at most 27
////   labels, 41, 46 or 48 bones by race and sex).
//// - The rows of the client's own CharacterCreation table, read from the real
////   file: 466 is a PreTutorial row (class 1, race 1, sex 1, faction 167, no
////   entitlement, no cost), 338 and 339 Nexus rows, 539 a Level50 row costing
////   1 of account currency 13, 536 a Nexus row needing entitlement 61, 21 a
////   disabled Arkship row (start 0) and 530 a costume-only row (class 0).
//// - The results the client's creation Lua names
////   (lua.Character.OnCreateCharacterFailed): 10 for a name, and the text "due
////   to an error" for every other value, 4 CreateFailed among them.

import character_support
import client_tables
import genesis_prime/game/character_creation.{
  ArkshipRow, BoneNotFinite, CostsCurrency, CostumeOnlyRow, NameBreaksRule,
  NeedsEntitlement, NoSuchRow, PathAbove3, RowDisabled, TooManyLabels,
  WrongBoneCount,
}
import genesis_prime/message/create_character.{
  type CreateCharacter, CreateCharacter,
}
import genesis_prime/message/create_result
import genesis_prime/store.{LookEntry, NewCharacter}
import genesis_prime/table/character_creation as creation_table
import genesis_prime/table/id.{
  CharacterCreationId, CharacterCustomizationLabelId, ClassId, RaceId,
}
import gleam/list
import gleam/result
import gleam/string
import owned_test

/// A request for the creation row with the name.
fn request(creation_id: Int, name: String) -> CreateCharacter {
  CreateCharacter(..character_support.create_request(name), creation_id:)
}

pub fn a_name_that_breaks_rule_0_is_name_length_before_the_row_is_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = client_tables.shared()
  assert character_creation.check(tables, request(99_999, "Abcd"))
    == Error(NameBreaksRule)
    as "0x1403e1170: 'Abcd' is no name by rule 0, and the client checks the name before the row (0x140023e90)"
  assert character_creation.result_of(NameBreaksRule)
    == create_result.NameLength
    as "lua.Character.OnCreateCharacterFailed: 10 is the name's text"
}

pub fn a_valid_request_gives_the_new_character_from_its_creation_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = client_tables.shared()
  let asked =
    CreateCharacter(
      ..request(466, "Ab Cd"),
      path: 2,
      customisation_labels: [2, 22],
      customisation_values: [1, 1],
    )
  assert character_creation.check(tables, asked)
    == Ok(NewCharacter(
      name: "Ab Cd",
      gender: 1,
      race_id: RaceId(1),
      class_id: ClassId(1),
      faction_id: 167,
      path: 2,
      look: [
        LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
        LookEntry(label: CharacterCustomizationLabelId(22), value: 1),
      ],
      bones: character_support.bones(46),
    ))
    as "CharacterCreation row 466: class 1, race 1, sex 1, faction 167; the path, the labels with their values and the bone values as the request carries them (opcode.0x25b)"
}

pub fn a_row_that_is_missing_disabled_arkship_costume_only_or_needs_what_the_account_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = client_tables.shared()
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
  assert check_row(
      creation_table.CharacterCreation(..row, character_creation_start_enum: 0),
    )
    == Error(ArkshipRow(creation_id: 466))
    as "characterCreationStartEnum 0 is the Arkship start, which the server does not offer even when a row is enabled"
  assert check_row(creation_table.CharacterCreation(..row, costume_only: True))
    == Error(CostumeOnlyRow(creation_id: 466))
    as "a costume-only row is for the create screen's model and makes no character (rows 530 and 531 have class 0)"
  let assert Ok(arkship) =
    creation_table.get(tables:, id: CharacterCreationId(21))
    as "CharacterCreation row 21 exists"
  assert arkship.character_creation_start_enum == 0 && !arkship.enabled
    as "the real Arkship row 21 is disabled"
  assert character_creation.check(tables, request(21, "Ab Cd"))
    == Error(RowDisabled(creation_id: 21))
    as "a real Arkship row is refused"
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

pub fn a_path_above_3_too_many_labels_or_the_wrong_bone_count_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = client_tables.shared()
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
  let many = fn(count) {
    CreateCharacter(
      ..request(466, "Ab Cd"),
      customisation_labels: character_support.numbers(count),
      customisation_values: list.repeat(1, count),
    )
  }
  assert result.is_ok(character_creation.check(tables, many(27)))
    as "opcode.0x25b.counts: the label table allows 27"
  assert character_creation.check(tables, many(28))
    == Error(TooManyLabels(creation_id: 466, count: 28))
    as "opcode.0x25b.counts: at most 27 labels"
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

pub fn a_bone_value_that_is_not_a_finite_float_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = client_tables.shared()
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
      ArkshipRow(creation_id: 7),
      CostumeOnlyRow(creation_id: 7),
      NeedsEntitlement(creation_id: 7),
      CostsCurrency(creation_id: 7),
      PathAbove3(creation_id: 7, path: 4),
      TooManyLabels(creation_id: 7, count: 28),
      WrongBoneCount(creation_id: 7, expected: 46, got: 45),
      BoneNotFinite(creation_id: 7),
    ],
    fn(refusal) {
      assert character_creation.result_of(refusal) == create_result.CreateFailed
        as "lua.Character.OnCreateCharacterFailed: 4 CreateFailed is shown as 'due to an error'"
      assert string.contains(character_creation.describe(refusal), "7")
        as "the warning names the creation row"
    },
  )
}
