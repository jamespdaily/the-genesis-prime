//// This module contains the code to run the sql queries defined in
//// `./dev/genesis_prime/mark_rename/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `mark_for_rename` query
/// defined in `./dev/genesis_prime/mark_rename/sql/mark_for_rename.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MarkForRenameRow {
  MarkForRenameRow(character_id: Int)
}

/// Marks the character with this name as needing a rename, for a developer's
/// database: the client then offers the player a rename when the character is
/// played. The name is found as the name's unique index finds it, in any case,
/// under the ICU root collation (migration 0005), so no two names differ only in
/// case here either. No character of that name gives no row.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mark_for_rename(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(MarkForRenameRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(MarkForRenameRow(character_id:))
  }

  "-- Marks the character with this name as needing a rename, for a developer's
-- database: the client then offers the player a rename when the character is
-- played. The name is found as the name's unique index finds it, in any case,
-- under the ICU root collation (migration 0005), so no two names differ only in
-- case here either. No character of that name gives no row.
update character
set needs_rename = true
where lower(name collate \"und-x-icu\") = lower($1 collate \"und-x-icu\")
returning character_id;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
