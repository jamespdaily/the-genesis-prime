//// Character rows for the tests that need a character in a database: one
//// insert with the same race, gender, faction, level, world, zone and
//// position for each row, so a test varies only the name, the class and the
//// path it checks.

import genesis_prime/store.{type AccountId, AccountId}
import gleam/dynamic/decode
import gleam/result
import pog

/// Why an insert gave no row.
pub type Refused {
  /// The table's constraint of this name refused the row.
  Refused(constraint: String)
  /// The insert failed for another reason.
  NotAConstraint
}

/// Inserts one character row for the account, and gives its id or why the
/// table refused it.
pub fn try_insert(
  pool pool: pog.Connection,
  account account: AccountId,
  name name: String,
  class_id class_id: Int,
  path path: Int,
) -> Result(Int, Refused) {
  let AccountId(account_id) = account
  pog.query(
    "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values ($1, $2, 1, 3, $3, 166, 9, $4, 1387, 1100, 1.5, 2.5, 3.5) returning character_id",
  )
  |> pog.parameter(pog.int(account_id))
  |> pog.parameter(pog.text(name))
  |> pog.parameter(pog.int(class_id))
  |> pog.parameter(pog.int(path))
  |> pog.returning(decode.at([0], decode.int))
  |> pog.execute(pool)
  |> result.map_error(fn(error) {
    case error {
      pog.ConstraintViolated(constraint:, ..) -> Refused(constraint:)
      pog.ConnectionUnavailable
      | pog.QueryTimeout
      | pog.PostgresqlError(..)
      | pog.UnexpectedArgumentCount(..)
      | pog.UnexpectedArgumentType(..)
      | pog.UnexpectedResultType(..) -> NotAConstraint
    }
  })
  |> result.map(fn(returned) {
    let assert [id] = returned.rows as "one row inserted"
    id
  })
}

/// Inserts one character row for the account, which the table accepts, and
/// gives its id.
pub fn insert(
  pool pool: pog.Connection,
  account account: AccountId,
  name name: String,
  class_id class_id: Int,
  path path: Int,
) -> Int {
  let assert Ok(id) = try_insert(pool:, account:, name:, class_id:, path:)
    as "the character was inserted"
  id
}
