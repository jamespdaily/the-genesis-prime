//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/store/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `find_account` query
/// defined in `./src/genesis_prime/store/sql/find_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type FindAccountRow {
  FindAccountRow(
    account_id: Int,
    login_name: String,
    srp_salt: BitArray,
    srp_verifier: BitArray,
    game_account_id: String,
  )
}

/// The account with this login name, as the STS login needs it. The game
/// account id is read as its 8-4-4-4-12 text, the form the STS login's GUIDs
/// are parsed from.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn find_account(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(FindAccountRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    use login_name <- decode.field(1, decode.string)
    use srp_salt <- decode.field(2, decode.bit_array)
    use srp_verifier <- decode.field(3, decode.bit_array)
    use game_account_id <- decode.field(4, decode.string)
    decode.success(FindAccountRow(
      account_id:,
      login_name:,
      srp_salt:,
      srp_verifier:,
      game_account_id:,
    ))
  }

  "-- The account with this login name, as the STS login needs it. The game
-- account id is read as its 8-4-4-4-12 text, the form the STS login's GUIDs
-- are parsed from.
select
  account_id,
  login_name,
  srp_salt,
  srp_verifier,
  game_account_id::text as game_account_id
from account
where login_name = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
