//// The client's rule for a character's name, against `vector.0x1403e1170.names`
//// (CheckTextRule 0x1403E1170 on rule 0, run on the emulator): the names it
//// passes, the names it refuses, and the letters it lists (IsTextRuleLetter
//// 0x1403E09D0).

import genesis_prime/character/name.{
  Empty, NotALetter, SpaceAtAnEnd, SpacesNotOne, TooLong, TooShort,
}
import gleam/list
import gleam/string
import owned_test

fn thirty_characters() -> String {
  string.repeat("A", 14) <> " " <> string.repeat("B", 15)
}

fn thirty_one_characters() -> String {
  string.repeat("A", 15) <> " " <> string.repeat("B", 15)
}

pub fn the_names_the_clients_rule_passes_are_passed_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      "Ab Cd",
      "Abc Def",
      "abc def",
      "aBC dEF",
      "Ébc Déf",
      thirty_characters(),
    ],
    fn(text) {
      assert name.check(text) == Ok(Nil)
        as { "vector.0x1403e1170.names: rule 0 passes " <> text }
    },
  )
}

pub fn the_names_the_clients_rule_refuses_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      "Abc",
      "Abcd",
      "Ab  Cd",
      "Ab Cd Ef",
      " Abc Def",
      "Abc Def ",
      "Ab1 Cd",
      "Ab-Cd Ef",
      "Ab_Cd Ef",
      "Ab'c Def",
      "Ab.c Def",
      "Abcå Def",
      "AbЖ Cd",
      "Ab Cd\n",
      "",
      thirty_one_characters(),
    ],
    fn(text) {
      assert name.check(text) != Ok(Nil)
        as {
          "vector.0x1403e1170.names: rule 0 refuses " <> string.inspect(text)
        }
    },
  )
}

pub fn a_name_says_why_the_rule_refuses_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert name.check("") == Error(Empty)
    as "CheckTextRule 0x1403E1170: an empty text is refused when the rule's flag 0x80 is not set, and rule 0's flags are 0x506"
  assert name.check("A B") == Error(TooShort(3))
    as "InitTextRules 0x1403E0B60: rule 0 has least length 5 (0x1403e0dc1 mov qword ptr [0x140c89738], 0x5)"
  assert name.check(thirty_one_characters()) == Error(TooLong(31))
    as "InitTextRules 0x1403E0B60: rule 0 has bound 31 (0x1403e0dcc), so 30 characters at most"
  assert name.check("Ab1 Cd") == Error(NotALetter("1"))
    as "vector.0x1403e1170.names: a digit is refused by rule 0 (flag 0x100 refuses every non-letter)"
  assert name.check(" Abc Def") == Error(SpaceAtAnEnd)
    as "vector.0x1403e1170.names: a space first is refused (flag 0x2)"
  assert name.check("Abc Def ") == Error(SpaceAtAnEnd)
    as "vector.0x1403e1170.names: a space last is refused (flag 0x2)"
  assert name.check("Abcdef") == Error(SpacesNotOne(0))
    as "CheckTextRule 0x1403E1170: rule 0's flag 0x400 asks exactly one space, so six letters and no space are refused (the vector refuses 'Abc' and 'Abcd')"
  assert name.check("Ab Cd Ef") == Error(SpacesNotOne(2))
    as "vector.0x1403e1170.names: 'Ab Cd Ef' has two spaces and is refused"
}

pub fn every_latin_letter_the_client_lists_is_a_letter_and_the_others_are_not_test() -> Nil {
  use <- owned_test.run(5000)
  let letters =
    string.to_graphemes("ÀÁÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÖÙÚÛÜÝßàáâäæçèéêëìíîïñòóôöùúûüýÿŒœŸ")
  assert list.length(letters) == 53
    as "IsTextRuleLetter 0x1403E09D0: A to Z, a to z and 53 Latin-1 and Latin Extended letters"
  list.each(letters, fn(letter) {
    assert name.check("Ab" <> letter <> " Cd") == Ok(Nil)
      as { "CheckTextRule rule 0 passes the listed letter " <> letter }
  })
  list.each(["Å", "å", "Ø", "ø", "Ж"], fn(other) {
    assert name.check("Ab" <> other <> " Cd") != Ok(Nil)
      as {
        "vector.0x1403e1170.names: 'Abcå Def' and 'AbЖ Cd' are refused; "
        <> other
        <> " is not on the client's list"
      }
  })
}
