//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/login/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `create_account` query
/// defined in `./src/genesis_prime/login/sql/create_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CreateAccountRow {
  CreateAccountRow(id: Int, user_id: String, created: String)
}

/// Adds an account and returns the GUID the database gave it and its creation
/// time, as text.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_account(
  db: pog.Connection,
  arg_1: String,
  arg_2: BitArray,
  arg_3: BitArray,
) -> Result(pog.Returned(CreateAccountRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use user_id <- decode.field(1, decode.string)
    use created <- decode.field(2, decode.string)
    decode.success(CreateAccountRow(id:, user_id:, created:))
  }

  "-- Adds an account and returns the GUID the database gave it and its creation
-- time, as text.
insert into account (name, salt, verifier)
values ($1, $2, $3)
returning
  id as \"id!\",
  user_id::text as \"user_id!\",
  to_char(created_at at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') as \"created!\";
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.bytea(arg_2))
  |> pog.parameter(pog.bytea(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `find_account` query
/// defined in `./src/genesis_prime/login/sql/find_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type FindAccountRow {
  FindAccountRow(
    id: Int,
    name: String,
    salt: BitArray,
    verifier: BitArray,
    user_id: String,
    created: String,
  )
}

/// The account of a lower-case name, if there is one. Its GUID and its
/// creation time are returned as text.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn find_account(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(FindAccountRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use salt <- decode.field(2, decode.bit_array)
    use verifier <- decode.field(3, decode.bit_array)
    use user_id <- decode.field(4, decode.string)
    use created <- decode.field(5, decode.string)
    decode.success(FindAccountRow(
      id:,
      name:,
      salt:,
      verifier:,
      user_id:,
      created:,
    ))
  }

  "-- The account of a lower-case name, if there is one. Its GUID and its
-- creation time are returned as text.
select
  id,
  name,
  salt,
  verifier,
  user_id::text as \"user_id!\",
  to_char(created_at at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') as \"created!\"
from account
where name = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
