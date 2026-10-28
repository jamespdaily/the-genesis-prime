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

/// Marks the character with this name, in any case, as needing a rename, for a
/// developer's database: the client then offers the player a rename when the
/// character is played. No character of that name gives no row.
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

  "-- Marks the character with this name, in any case, as needing a rename, for a
-- developer's database: the client then offers the player a rename when the
-- character is played. No character of that name gives no row.
update character
set needs_rename = true
where lower(name) = lower($1)
returning character_id;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
