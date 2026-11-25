//// The ability a sitting bot is seated to press: which class and level hold it
//// in the faction of the player it presses at, and the character that holds it.
////
//// ```
//// --press "<name or Spell4Base id>"  +  the faction of --at
////    ─▶ choices: each class's abilities at that faction, with the level that gives each
////    ─▶ resolve ─▶ one choice (class, level, Spell4Base id)
////    ─▶ equip: the bot's character becomes that class at that level and faction,
////               holding that class's Novice set, with no saved action bar or tier
//// ```
////
//// - **The bag is the class's and level's alone**: a character holds the class's
////   level-1 abilities, its innate, and each later ability whose level is at or
////   below its own (`genesis_prime/game/ability_book`), so the level that gives an
////   ability is the level the bot is seated at: 1 for a level-1 ability or the
////   innate, else the SpellLevel row's `characterLevel` (`genesis_prime/game/loadout`).
//// - **The faction is the pressed player's**, because a beneficial press at a
////   player of another faction is refused as a hostile target (result 99,
////   `genesis_prime/game/cast/press_target`).
//// - **A name is the ability's Spell4Base name in en-US.bin**, matched in any case
////   and exactly. A name or id that two classes or two bases hold is refused with
////   the choices listed, never guessed.
//// - **The items are the class's Novice set** as character creation gives it
////   (`genesis_prime/game/character_creation.novice_items`), so the bot enters
////   dressed as a new character of that class does.
//// - Gap: facing is not set, so a Targeted spell with an arc of less than 360
////   degrees is refused 101 when the bot stands on its target's own point
////   (`genesis_prime/game/area.faces`).

import genesis_prime/dev_database
import genesis_prime/game/character_creation
import genesis_prime/game/loadout
import genesis_prime/language_file.{type LanguageFile}
import genesis_prime/sitting_bot/sql
import genesis_prime/store/sql as store_sql
import genesis_prime/table/class
import genesis_prime/table/id.{type ClassId, ClassId, Spell4BaseId}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_base
import genesis_prime/table_folder
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog
import simplifile

/// The client's tables as the server loads them, and the language file that
/// names their rows.
pub type Known {
  Known(tables: table_store.Tables, language: LanguageFile)
}

/// Why the tables or the language file could not be read.
pub type LoadFailure {
  TablesUnreadable(error: table_store.LoadError)
  LanguageUnreadable(file: String, reason: String)
}

/// An ability a class holds: the class, the level that gives it, its Spell4Base
/// id and its name.
pub type Choice {
  Choice(class_id: Int, level: Int, spell4_base_id: Int, name: String)
}

/// Why no one ability is the one asked for.
pub type Refusal {
  /// No class holds an ability of that name or id at the faction.
  NoSuchAbility(wanted: String, faction_id: Int)
  /// More than one ability, or more than one class, holds it.
  Ambiguous(wanted: String, choices: List(Choice))
}

/// Reads the server's tables from the folder of the client's extracted tables and
/// the language file of the client's other files.
pub fn load() -> Result(Known, LoadFailure) {
  use tables <- result.try(
    server_table.read(from: table_folder.path())
    |> result.map_error(TablesUnreadable),
  )
  let file = table_folder.client_files_path() <> "/en-US.bin"
  use bytes <- result.try(
    simplifile.read_bits(file)
    |> result.map_error(fn(error) {
      LanguageUnreadable(file:, reason: simplifile.describe_error(error))
    }),
  )
  use language <- result.map(
    language_file.read(bytes:)
    |> result.map_error(fn(refusal) {
      LanguageUnreadable(file:, reason: language_file.describe(refusal:))
    }),
  )
  Known(tables:, language:)
}

/// A sentence that says why the tables or the language file are not there.
pub fn describe_load_failure(failure: LoadFailure) -> String {
  case failure {
    TablesUnreadable(error:) ->
      "the client's tables could not be loaded from "
      <> table_folder.path()
      <> ": "
      <> table_store.describe(error)
    LanguageUnreadable(file:, reason:) ->
      "the language file " <> file <> " could not be read: " <> reason
  }
}

/// The name of an ability's Spell4Base row, or its id as text when the row or
/// the text is missing.
fn name_of(known known: Known, spell4_base_id spell4_base_id: Int) -> String {
  let name =
    spell4_base.get(tables: known.tables, id: Spell4BaseId(spell4_base_id))
    |> result.replace_error(Nil)
    |> result.try(fn(row) {
      language_file.text(
        file: known.language,
        text_id: spell4_base.localized_text_id_name(row).value,
      )
      |> result.replace_error(Nil)
    })
  case name {
    Ok(Some(text)) -> text
    Ok(None) | Error(Nil) -> int.to_string(spell4_base_id)
  }
}

/// Every ability each class holds at the faction, with the level that gives it.
fn choices(known known: Known, faction_id faction_id: Int) -> List(Choice) {
  list.flat_map(class.all(known.tables), fn(row) {
    let class_id = class.id(row)
    case loadout.of(tables: known.tables, class_id:, faction_id:) {
      Error(Nil) -> []
      Ok(held) -> held_choices(known:, class_id:, held:)
    }
  })
}

/// The abilities of one class's loadout: the level-1 abilities and the innate at
/// level 1, and each later ability at its unlock level.
fn held_choices(
  known known: Known,
  class_id class_id: ClassId,
  held held: loadout.Loadout,
) -> List(Choice) {
  let level_one = list.map(held.abilities, fn(base) { #(1, base) })
  let innate = case held.innate {
    Some(innate) -> [#(1, innate.active_base)]
    None -> []
  }
  let later = list.map(held.later, fn(unlock) { #(unlock.level, unlock.base) })
  list.map(list.flatten([level_one, innate, later]), fn(held_at) {
    let #(level, base) = held_at
    Choice(
      class_id: class_id.value,
      level:,
      spell4_base_id: base.value,
      name: name_of(known:, spell4_base_id: base.value),
    )
  })
}

/// The one ability the text names at the faction: a Spell4Base id, or a name in
/// any case.
pub fn resolve(
  known known: Known,
  wanted wanted: String,
  faction_id faction_id: Int,
) -> Result(Choice, Refusal) {
  let held = choices(known:, faction_id:)
  let matching = case int.parse(wanted) {
    Ok(spell4_base_id) ->
      list.filter(held, fn(choice) { choice.spell4_base_id == spell4_base_id })
    Error(Nil) ->
      list.filter(held, fn(choice) {
        string.lowercase(choice.name) == string.lowercase(wanted)
      })
  }
  case matching {
    [] -> Error(NoSuchAbility(wanted:, faction_id:))
    [only] -> Ok(only)
    [_, _, ..] -> Error(Ambiguous(wanted:, choices: matching))
  }
}

/// A sentence that says why, and lists what the faction's classes do hold.
pub fn describe_refusal(refusal refusal: Refusal) -> String {
  case refusal {
    NoSuchAbility(wanted:, faction_id:) ->
      "no class of faction "
      <> int.to_string(faction_id)
      <> " holds an ability named or numbered \""
      <> wanted
      <> "\""
    Ambiguous(wanted:, choices:) ->
      "\""
      <> wanted
      <> "\" is held more than one way: "
      <> string.join(list.map(choices, describe_choice), ", ")
      <> "; name it by its Spell4Base id to take the one that is meant"
  }
}

fn describe_choice(choice: Choice) -> String {
  choice.name
  <> " (Spell4Base "
  <> int.to_string(choice.spell4_base_id)
  <> ", class "
  <> int.to_string(choice.class_id)
  <> ", level "
  <> int.to_string(choice.level)
  <> ")"
}

/// Makes the bot's character a character of the choice's class and level in the
/// faction, holding the class's Novice set, with no saved action bar, ability tier or AMP, in one
/// transaction: all of it or none. Only a character of the account with the
/// login name is changed.
pub fn equip(
  pool pool: pog.Connection,
  known known: Known,
  character_id character_id: Int,
  login_name login_name: String,
  choice choice: Choice,
  faction_id faction_id: Int,
) -> Result(Nil, dev_database.Failure) {
  let items =
    character_creation.novice_items(
      tables: known.tables,
      class_id: ClassId(choice.class_id),
      faction_id:,
    )
  pog.transaction(pool, fn(connection) {
    use changed <- result.try(sql.equip_bot_character(
      connection,
      character_id,
      choice.class_id,
      faction_id,
      choice.level,
      login_name,
    ))
    use _ <- result.try(sql.delete_bot_items(
      connection,
      character_id,
      login_name,
    ))
    use _ <- result.try(sql.delete_bot_action_sets(
      connection,
      character_id,
      login_name,
    ))
    case changed.rows {
      [] -> Ok(False)
      [_, ..] ->
        store_sql.create_character_items(
          connection,
          character_id,
          list.map(items, fn(item) { item.item2_id.value }),
          list.map(items, fn(item) { item.location }),
          list.map(items, fn(item) { item.bag_index }),
          list.map(items, fn(item) { item.stack_count }),
          list.map(items, fn(item) { item.charges }),
        )
        |> result.replace(True)
    }
  })
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionQueryError(error) | pog.TransactionRolledBack(error) ->
        dev_database.failure_of(error:)
    }
  })
  |> result.try(fn(changed) {
    case changed {
      True -> Ok(Nil)
      False ->
        Error(dev_database.NotChanged(
          "the bot's character is not a character of the bot's account",
        ))
    }
  })
}

/// The faction of the character with the name, or `Error(Nil)` for none.
pub fn faction_of(
  pool pool: pog.Connection,
  name name: String,
) -> Result(Result(Int, Nil), dev_database.Failure) {
  sql.character_faction(pool, name)
  |> result.map_error(fn(error) { dev_database.failure_of(error:) })
  |> result.map(fn(returned) {
    case returned.rows {
      [row, ..] -> Ok(row.faction_id)
      [] -> Error(Nil)
    }
  })
}
