//// A character's full name by the client's text rule 0
//// (`genesis_prime/game/character_name`). Expected values are the emulator
//// vector vector.0x1403e1170.names, which ran CheckTextRule 0x1403e1170 on each
//// text, and the rule's own description (0x1403e1170: letters and exactly one
//// space, not first or last, 5 to 30 characters in all, case free).

import database_support
import genesis_prime/game/character_name
import gleam/int
import gleam/list
import gleam/string
import owned_test

pub fn the_names_the_client_accepts_pass_rule_0_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      "Ab Cd",
      "Abc Def",
      "abc def",
      "aBC dEF",
      "Ébc Déf",
      string.repeat("A", 14) <> " " <> string.repeat("B", 15),
    ],
    fn(name) {
      assert character_name.is_valid(name)
        as { "vector.0x1403e1170.names passes " <> name }
    },
  )
}

pub fn the_names_the_client_refuses_fail_rule_0_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #("Abc", "too short and no space"),
      #("Abcd", "too short and no space"),
      #("Ab  Cd", "two spaces"),
      #("Ab Cd Ef", "two spaces"),
      #(" Abc Def", "a space first"),
      #("Abc Def ", "a space last"),
      #("Ab1 Cd", "a digit"),
      #("Ab-Cd Ef", "a hyphen"),
      #("Ab_Cd Ef", "an underscore"),
      #("Ab'c Def", "an apostrophe"),
      #("Ab.c Def", "a full stop"),
      #("Abcå Def", "a letter the client does not list"),
      #("AbЖ Cd", "a Cyrillic letter"),
      #("Ab\nCd", "a line break"),
      #("", "no text"),
      #(
        string.repeat("A", 15) <> " " <> string.repeat("B", 15),
        "31 characters",
      ),
    ],
    fn(refused) {
      let #(name, why) = refused
      assert !character_name.is_valid(name)
        as { "vector.0x1403e1170.names refuses " <> why }
    },
  )
}

pub fn a_name_is_measured_in_characters_not_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x1403e1170: the bound counts wide characters, and the letters the client
  // lists include two-byte ones, so 15 'É', a space and 14 'é' is 30 characters.
  assert character_name.is_valid(
    string.repeat("É", 15) <> " " <> string.repeat("é", 14),
  )
    as "30 characters, 59 bytes: the client counts characters"
}

pub fn the_fold_of_a_name_is_the_databases_icu_lower_for_every_letter_the_rule_takes_test() -> Nil {
  use <- owned_test.run(60_000)
  let letters =
    list.append(
      string.to_graphemes(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
      ),
      string.to_graphemes(character_name.listed_letters),
    )
  assert list.length(letters) == 52 + 53
    as "A to Z, a to z and the client's 53 listed letters (IsTextRuleLetter 0x1403e09d0)"
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let numbers =
    list.map(letters, fn(letter) {
      let assert [codepoint] = string.to_utf_codepoints(letter)
      int.to_string(string.utf_codepoint_to_int(codepoint))
    })
  let assert Ok(printed) =
    database_support.psql(with: shared.settings, database:, arguments: [
      "-At",
      "-c",
      "select string_agg(ascii(lower(chr(code) collate \"und-x-icu\"))::text, ',' order by position) from unnest(array["
        <> string.join(numbers, ",")
        <> "]) with ordinality as letters(code, position)",
    ])
    as "the database folds the letters (their code points go in as numbers, so no shell turns them into other bytes)"
  assert string.trim(printed)
    == string.join(
      list.map(letters, fn(letter) {
        let assert [folded] =
          string.to_utf_codepoints(character_name.fold(letter))
        int.to_string(string.utf_codepoint_to_int(folded))
      }),
      ",",
    )
    as "migration 0005: the unique index folds a name with ICU's lower, so the whisper's group key must agree with it for every letter a name can hold"
}
