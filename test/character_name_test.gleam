//// A character's full name by the client's text rule 0
//// (`genesis_prime/game/character_name`). Expected values are the emulator
//// vector vector.0x1403e1170.names, which ran CheckTextRule 0x1403e1170 on each
//// text, and the rule's own description (0x1403e1170: letters and exactly one
//// space, not first or last, 5 to 30 characters in all, case free).

import genesis_prime/game/character_name
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
