//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/game_master/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `give_first_permission` query
/// defined in `./src/genesis_prime/game_master/sql/give_first_permission.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GiveFirstPermissionRow {
  GiveFirstPermissionRow(account_id: Int)
}

/// Gives an account a permission only while no account holds it, and returns
/// the account id when it did. The advisory lock on the permission's name
/// makes two first grants of it wait for one another, so both cannot find it
/// unheld.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn give_first_permission(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
) -> Result(pog.Returned(GiveFirstPermissionRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    decode.success(GiveFirstPermissionRow(account_id:))
  }

  "-- Gives an account a permission only while no account holds it, and returns
-- the account id when it did. The advisory lock on the permission's name
-- makes two first grants of it wait for one another, so both cannot find it
-- unheld.
with locked as (
  select pg_advisory_xact_lock(hashtext($2::text))
)
insert into permission (account_id, name)
select $1::bigint, $2::text
from locked
where not exists (select 1 from permission where name = $2::text)
returning account_id as \"account_id!\";
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Gives an account a permission; an account that holds it already keeps it.
/// An account that does not exist breaks the foreign key.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn give_permission(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Gives an account a permission; an account that holds it already keeps it.
-- An account that does not exist breaks the foreign key.
insert into permission (account_id, name)
values ($1, $2)
on conflict do nothing;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `operator_uses` query
/// defined in `./src/genesis_prime/game_master/sql/operator_uses.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type OperatorUsesRow {
  OperatorUsesRow(
    command: String,
    arguments: String,
    outcome: String,
    refusal: Option(String),
    refusal_permission: Option(String),
  )
}

/// Every use made by the database's operator and not by an account, oldest
/// first: the first grants.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn operator_uses(
  db: pog.Connection,
) -> Result(pog.Returned(OperatorUsesRow), pog.QueryError) {
  let decoder = {
    use command <- decode.field(0, decode.string)
    use arguments <- decode.field(1, decode.string)
    use outcome <- decode.field(2, decode.string)
    use refusal <- decode.field(3, decode.optional(decode.string))
    use refusal_permission <- decode.field(4, decode.optional(decode.string))
    decode.success(OperatorUsesRow(
      command:,
      arguments:,
      outcome:,
      refusal:,
      refusal_permission:,
    ))
  }

  "-- Every use made by the database's operator and not by an account, oldest
-- first: the first grants.
select
  command,
  arguments,
  outcome,
  refusal,
  refusal_permission
from game_master_use
where account_id is null
order by id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `permissions_of_account` query
/// defined in `./src/genesis_prime/game_master/sql/permissions_of_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PermissionsOfAccountRow {
  PermissionsOfAccountRow(name: String)
}

/// The names of the permissions an account holds.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn permissions_of_account(
  db: pog.Connection,
  account_id: Int,
) -> Result(pog.Returned(PermissionsOfAccountRow), pog.QueryError) {
  let decoder = {
    use name <- decode.field(0, decode.string)
    decode.success(PermissionsOfAccountRow(name:))
  }

  "-- The names of the permissions an account holds.
select name
from permission
where account_id = $1
order by name;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Records one use of a command by an account that the rule allowed.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn record_allowed_use(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Records one use of a command by an account that the rule allowed.
insert into game_master_use (account_id, command, arguments, outcome)
values ($1, $2, $3, 'allowed');
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Records a first grant that gave a permission. The database's operator made
/// it, so no account is named; `arguments` names the account that was given
/// the permission.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn record_first_grant(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Records a first grant that gave a permission. The database's operator made
-- it, so no account is named; `arguments` names the account that was given
-- the permission.
insert into game_master_use (command, arguments, outcome)
values ('first_grant', $1, 'allowed');
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Records a first grant that was refused because an account holds the
/// permission already. `arguments` names the account that was to be given it,
/// and the permission is the one that was held.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn record_refused_first_grant(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Records a first grant that was refused because an account holds the
-- permission already. `arguments` names the account that was to be given it,
-- and the permission is the one that was held.
insert into game_master_use (
  command, arguments, outcome, refusal, refusal_permission
)
values ('first_grant', $1, 'refused', 'first_grant_over', $2);
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Records one use of a command by an account that the rule refused, with why
/// and the permission the refusal is about.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn record_refused_use(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Records one use of a command by an account that the rule refused, with why
-- and the permission the refusal is about.
insert into game_master_use (
  account_id, command, arguments, outcome, refusal, refusal_permission
)
values ($1, $2, $3, 'refused', $4, $5);
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Takes a permission from an account; an account that does not hold it is
/// left as it is.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn take_permission(
  db: pog.Connection,
  account_id: Int,
  arg_2: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Takes a permission from an account; an account that does not hold it is
-- left as it is.
delete from permission
where account_id = $1 and name = $2;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `uses_of_account` query
/// defined in `./src/genesis_prime/game_master/sql/uses_of_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UsesOfAccountRow {
  UsesOfAccountRow(
    account_id: Int,
    command: String,
    arguments: String,
    outcome: String,
    refusal: Option(String),
    refusal_permission: Option(String),
  )
}

/// Every use of a command by an account, oldest first.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn uses_of_account(
  db: pog.Connection,
  account_id: Int,
) -> Result(pog.Returned(UsesOfAccountRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    use command <- decode.field(1, decode.string)
    use arguments <- decode.field(2, decode.string)
    use outcome <- decode.field(3, decode.string)
    use refusal <- decode.field(4, decode.optional(decode.string))
    use refusal_permission <- decode.field(5, decode.optional(decode.string))
    decode.success(UsesOfAccountRow(
      account_id:,
      command:,
      arguments:,
      outcome:,
      refusal:,
      refusal_permission:,
    ))
  }

  "-- Every use of a command by an account, oldest first.
select
  account_id as \"account_id!\",
  command,
  arguments,
  outcome,
  refusal,
  refusal_permission
from game_master_use
where account_id = $1
order by id;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
