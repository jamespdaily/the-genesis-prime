//// Marks a character as needing a rename in a developer's database, standing
//// in for the game master action a later card gives the server: the client
//// then offers the player a rename instead of playing the character
//// (opcode.0x117, lua.CharacterSelection.OnSelectCharacter).
////
//// `gleam run -m genesis_prime/mark_rename -- <character name>`
////
//// The database is the one the server uses, from PGHOST, PGPORT, PGUSER,
//// PGPASSWORD and PGDATABASE. The name is matched in any case, as names are
//// unique in any case; a name no character has is refused.

import argv
import genesis_prime/dev_database
import genesis_prime/mark_rename/sql
import gleam/int
import gleam/result

/// Why the character was not marked.
type Failure {
  WrongArguments
  NoSuchCharacter(name: String)
  Database(failure: dev_database.Failure)
}

pub fn main() -> Nil {
  dev_database.finish(result: mark(), describe:)
}

fn mark() -> Result(String, Failure) {
  case argv.load().arguments {
    [name] -> {
      use rows <- result.try(
        dev_database.run(sql.mark_for_rename(_, name))
        |> result.map_error(Database),
      )
      case rows {
        [sql.MarkForRenameRow(character_id:)] ->
          Ok(
            "marked the character "
            <> name
            <> " with the id "
            <> int.to_string(character_id),
          )
        _ -> Error(NoSuchCharacter(name:))
      }
    }
    _ -> Error(WrongArguments)
  }
}

fn describe(failure: Failure) -> String {
  case failure {
    WrongArguments ->
      "usage: gleam run -m genesis_prime/mark_rename -- <character name>"
    NoSuchCharacter(name:) -> "no character has the name " <> name
    Database(failure:) ->
      dev_database.describe(failure:, change: "mark the character for a rename")
  }
}
