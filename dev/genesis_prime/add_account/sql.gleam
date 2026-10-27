//// This module contains the code to run the sql queries defined in
//// `./dev/genesis_prime/add_account/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `insert_account` query
/// defined in `./dev/genesis_prime/add_account/sql/insert_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertAccountRow {
  InsertAccountRow(account_id: Int)
}

/// Adds an account; the database makes its id. The game account id is given
/// as its 8-4-4-4-12 text, a text parameter, so no UUID package is needed.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_account(
  db: pog.Connection,
  arg_1: String,
  arg_2: BitArray,
  arg_3: BitArray,
  arg_4: String,
) -> Result(pog.Returned(InsertAccountRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    decode.success(InsertAccountRow(account_id:))
  }

  "-- Adds an account; the database makes its id. The game account id is given
-- as its 8-4-4-4-12 text, a text parameter, so no UUID package is needed.
insert into account (login_name, srp_salt, srp_verifier, game_account_id)
values ($1, $2, $3, $4::text::uuid)
returning account_id;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.bytea(arg_2))
  |> pog.parameter(pog.bytea(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
