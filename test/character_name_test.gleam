//// A character's name as the game folds it (`genesis_prime/game/character_name`).
//// The rule that says which texts are names is the table's
//// (`character_name_follows_rule_0`, migration 0014), tested against Postgres in
//// `account_store_test` with the emulator vector vector.0x1403e1170.names; this
//// module tests the fold the whisper's group key takes, which must agree with
//// the unique index's.

import database_support
import genesis_prime/game/character_name
import gleam/int
import gleam/list
import gleam/string
import owned_test

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
