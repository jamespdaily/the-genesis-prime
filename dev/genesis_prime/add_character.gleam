//// Adds a character to an account in a developer's database, so the
//// character list has one to show: the character's name, and the race, sex,
//// class and faction of one row of the client's CharacterCreation table
//// (raceId, sex, classId, factionId). The character starts at level 1, path 0,
//// with no world, zone or position, which the character list does not read.
////
//// `gleam run -m genesis_prime/add_character -- <login name> <character name> <race id> <sex> <class id> <faction id>`
////
//// The database is the one the server uses, from PGHOST, PGPORT, PGUSER,
//// PGPASSWORD and PGDATABASE. A login name no account has is refused, and so
//// is a class or path the table's checks do not allow, with the constraint
//// that refused it.

import argv
import genesis_prime/add_character/sql
import genesis_prime/dev_database
import gleam/int
import gleam/result
import gleam/string

/// Why the character was not added.
type Failure {
  WrongArguments
  NotANumber(argument: String)
  NoSuchAccount(login_name: String)
  Database(failure: dev_database.Failure)
}

pub fn main() -> Nil {
  dev_database.finish(result: add(), describe:)
}

fn add() -> Result(String, Failure) {
  case argv.load().arguments {
    [login_name, name, race_id, sex, class_id, faction_id] -> {
      let login_name = string.lowercase(login_name)
      use race_id <- result.try(number(race_id))
      use sex <- result.try(number(sex))
      use class_id <- result.try(number(class_id))
      use faction_id <- result.try(number(faction_id))
      use rows <- result.try(
        dev_database.run(sql.insert_character(
          _,
          login_name,
          name,
          sex,
          race_id,
          class_id,
          faction_id,
        ))
        |> result.map_error(Database),
      )
      case rows {
        [sql.InsertCharacterRow(character_id:)] ->
          Ok(
            "added the character "
            <> name
            <> " with the id "
            <> int.to_string(character_id)
            <> " for "
            <> login_name,
          )
        _ -> Error(NoSuchAccount(login_name:))
      }
    }
    _ -> Error(WrongArguments)
  }
}

fn number(argument: String) -> Result(Int, Failure) {
  int.parse(argument) |> result.replace_error(NotANumber(argument:))
}

fn describe(failure: Failure) -> String {
  case failure {
    WrongArguments ->
      "usage: gleam run -m genesis_prime/add_character -- <login name> <character name> <race id> <sex> <class id> <faction id>"
    NotANumber(argument:) -> "not a number: " <> argument
    NoSuchAccount(login_name:) -> "no account has the login name " <> login_name
    Database(failure:) ->
      dev_database.describe(failure:, change: "add the character")
  }
}
