//// The characters in Postgres, each test in a database of its own made from the
//// migrated template. A character's statements name its account, so an account
//// reaches only its own; a name is unique; a saved character reads back as it
//// was saved. The expected values are the ones saved, with the floats of
//// vector.opcode.0xad.body (1.0, -2.5 and 100.25, which a 32-bit float and a
//// double both hold exactly).

import character_support
import genesis_prime/character/character.{
  type Character, Appearance, Character, NewCharacter, Place,
}
import genesis_prime/character/select.{
  Deleted, Inserted, Loaded, NameInUse, NotFound, Renamed, Unavailable,
}
import genesis_prime/character/store
import genesis_prime/database/pool
import genesis_prime/map/position.{Position}
import genesis_prime/server
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import owned_test
import pog
import relay
import template_database

/// Adds the account the tests' characters belong to and the account after it,
/// with the ids the tests use: a character's account is a row of `account`.
fn add_accounts(db: pog.Connection) -> Nil {
  let assert Ok(_) =
    pog.query(
      "insert into account (id, name, salt, verifier) overriding system value values ($1, 'first', ''::bytea, ''::bytea), ($2, 'second', ''::bytea, ''::bytea)",
    )
    |> pog.parameter(pog.int(character_support.account_id))
    |> pog.parameter(pog.int(character_support.account_id + 1))
    |> pog.execute(on: db)
    as "the accounts were added"
  Nil
}

fn new_character(name: String) -> character.NewCharacter {
  NewCharacter(
    account_id: character_support.account_id,
    name:,
    creation_id: 277,
    gender: 1,
    race_id: 1,
    class_id: 3,
    faction_id: 167,
    experience: 1710,
    level: 3,
    path: 2,
    place: Place(
      world_id: 51,
      world_zone_id: 9,
      position: Position(x: 1.0, y: -2.5, z: 100.25),
    ),
    appearance: Appearance(
      customisation_labels: [1, 2],
      customisation_values: [3, 4],
      bone_values: [0x3F800000, 0xBF000000],
    ),
  )
}

fn saved(db: pog.Connection, name: String) -> Character {
  let assert Inserted(character) =
    store.run(db, select.InsertCharacter(new_character(name)))
    as "the character was saved"
  character
}

fn listed(db: pog.Connection, account: Int) -> List(Character) {
  let assert Loaded(characters) = store.run(db, select.LoadCharacters(account))
    as "the characters were loaded"
  characters
}

pub fn a_saved_character_reads_back_as_it_was_saved_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let character = saved(database.connection, "Ab Cd")
  assert character
    == Character(
      id: character.id,
      account_id: character_support.account_id,
      name: "Ab Cd",
      creation_id: 277,
      gender: 1,
      race_id: 1,
      class_id: 3,
      faction_id: 167,
      experience: 1710,
      level: 3,
      path: 2,
      place: Place(
        world_id: 51,
        world_zone_id: 9,
        position: Position(x: 1.0, y: -2.5, z: 100.25),
      ),
      appearance: Appearance(
        customisation_labels: [1, 2],
        customisation_values: [3, 4],
        bone_values: [0x3F800000, 0xBF000000],
      ),
      requires_rename: False,
      disabled: False,
    )
    as "a new character has the values it was saved with and neither flag set"
  assert character.id > 0 as "the database gives the character its id"
  assert listed(database.connection, character_support.account_id)
    == [character]
    as "the account's list holds the character as saved"
}

pub fn a_character_with_no_customisation_or_bones_is_saved_and_listed_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let plain =
    NewCharacter(
      ..new_character("Ab Cd"),
      appearance: Appearance(
        customisation_labels: [],
        customisation_values: [],
        bone_values: [],
      ),
    )
  let assert Inserted(character) =
    store.run(database.connection, select.InsertCharacter(plain))
    as "the character was saved"
  assert character.appearance == Appearance([], [], [])
  assert listed(database.connection, character_support.account_id)
    == [character]
}

pub fn an_account_is_listed_its_own_characters_oldest_first_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let first = saved(database.connection, "Ab Cd")
  let second = saved(database.connection, "Ef Gh")
  let assert Inserted(other) =
    store.run(
      database.connection,
      select.InsertCharacter(
        NewCharacter(
          ..new_character("Ij Kl"),
          account_id: character_support.account_id + 1,
        ),
      ),
    )
    as "another account's character was saved"
  assert listed(database.connection, character_support.account_id)
    == [first, second]
    as "an account is listed its own characters in the order they were made"
  assert listed(database.connection, character_support.account_id + 1)
    == [other]
    as "another account is listed only its own"
}

pub fn a_name_another_character_has_is_refused_and_nothing_is_saved_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let first = saved(database.connection, "Ab Cd")
  assert store.run(
      database.connection,
      select.InsertCharacter(
        NewCharacter(
          ..new_character("Ab Cd"),
          account_id: character_support.account_id + 1,
        ),
      ),
    )
    == NameInUse
    as "a name is unique across accounts"
  assert listed(database.connection, character_support.account_id) == [first]
  assert listed(database.connection, character_support.account_id + 1) == []
    as "nothing was saved for the other account"
}

pub fn a_rename_changes_the_name_and_clears_the_need_to_rename_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let character = saved(database.connection, "Ab Cd")
  let assert Ok(_) =
    pog.query("update character set requires_rename = true where id = $1")
    |> pog.parameter(pog.int(character.id))
    |> pog.execute(on: database.connection)
    as "the character was marked as needing a rename"
  assert store.run(
      database.connection,
      select.RenameStored(character_support.account_id, character.id, "Ef Gh"),
    )
    == Renamed(Character(..character, name: "Ef Gh", requires_rename: False))
    as "opcode.0x14b: the listed character takes the name and loses its needs-a-rename flag"
  assert listed(database.connection, character_support.account_id)
    == [Character(..character, name: "Ef Gh", requires_rename: False)]
}

pub fn a_rename_to_a_name_another_character_has_is_refused_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let first = saved(database.connection, "Ab Cd")
  let _second = saved(database.connection, "Ef Gh")
  assert store.run(
      database.connection,
      select.RenameStored(character_support.account_id, first.id, "Ef Gh"),
    )
    == NameInUse
  assert list.map(
      listed(database.connection, character_support.account_id),
      fn(found) { found.name },
    )
    == ["Ab Cd", "Ef Gh"]
    as "no name changed"
}

pub fn an_account_cannot_rename_a_character_of_another_account_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let character = saved(database.connection, "Ab Cd")
  assert store.run(
      database.connection,
      select.RenameStored(
        character_support.account_id + 1,
        character.id,
        "Ef Gh",
      ),
    )
    == NotFound
    as "the statement names the account, so the character is not found for another"
  assert listed(database.connection, character_support.account_id)
    == [character]
    as "the name is unchanged"
}

pub fn a_deleted_character_is_gone_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let character = saved(database.connection, "Ab Cd")
  let kept = saved(database.connection, "Ef Gh")
  assert store.run(
      database.connection,
      select.DeleteStored(character_support.account_id, character.id),
    )
    == Deleted(character.id)
  assert listed(database.connection, character_support.account_id) == [kept]
}

pub fn an_account_cannot_delete_a_character_of_another_account_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let character = saved(database.connection, "Ab Cd")
  assert store.run(
      database.connection,
      select.DeleteStored(character_support.account_id + 1, character.id),
    )
    == NotFound
    as "the statement names the account, so the character is not found for another"
  assert listed(database.connection, character_support.account_id)
    == [character]
    as "the character is still there"
  assert store.run(
      database.connection,
      select.DeleteStored(character_support.account_id, character.id + 1000),
    )
    == NotFound
    as "an id no character has is not found"
}

pub fn a_database_that_is_away_is_unavailable_not_a_refusal_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let assert Ok(away) =
    relay.refusing(to: relay.Target(
      host: database.settings.tcp_host,
      port: database.settings.port,
    ))
    as "the relay did not get a port"
  let settings =
    pool.Settings(
      ..template_database.pool_settings(
        for: database,
        pool_name: process.new_name("character_store_away"),
        pool_size: 2,
      ),
      host: away.host,
      port: away.port,
    )
  let assert Ok(_) = server.start(template_database.tree_settings(settings))
    as "the tree did not start with the database away"
  let connection = pool.connection(settings)
  assert store.run(
      connection,
      select.LoadCharacters(character_support.account_id),
    )
    == Unavailable
    as "a query with the database away gets no connection: an outside failure"
  assert store.run(connection, select.InsertCharacter(new_character("Ab Cd")))
    == Unavailable
    as "so does a save"
}

pub fn the_database_holds_as_many_customisation_values_as_labels_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let attempt =
    pog.query(
      "insert into character (account_id, name, creation_id, gender, race_id, class_id, faction_id, experience, level, path, world_id, world_zone_id, position_x, position_y, position_z, customisation_labels, customisation_values, bone_values) values (7, 'Ab Cd', 1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 0, 0, '{1,2}', '{3}', '{}')",
    )
    |> pog.returning(decode.success(Nil))
    |> pog.execute(on: database.connection)
  let assert Error(pog.ConstraintViolated(..)) = attempt
    as "opcode.0x25b: one value for each label; a row with other counts is no character the client's list could hold"
  Nil
}

pub fn a_name_that_differs_only_in_case_is_a_name_another_character_has_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let first = saved(database.connection, "Ab Cd")
  list.each(["ab cd", "AB CD", "aB cD"], fn(name) {
    assert store.run(
        database.connection,
        select.InsertCharacter(
          NewCharacter(
            ..new_character(name),
            account_id: character_support.account_id + 1,
          ),
        ),
      )
      == NameInUse
      as "Jim's decision on the world issue: names are unique regardless of case"
  })
  assert listed(database.connection, character_support.account_id) == [first]
    as "the name is shown as it was typed"
  assert listed(database.connection, character_support.account_id + 1) == []
    as "nothing was saved for the other account"
}

pub fn a_rename_to_a_name_that_differs_only_in_case_is_refused_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let first = saved(database.connection, "Ab Cd")
  let _second = saved(database.connection, "Ef Gh")
  assert store.run(
      database.connection,
      select.RenameStored(character_support.account_id, first.id, "eF gH"),
    )
    == NameInUse
    as "Jim's decision on the world issue: names are unique regardless of case"
  assert list.map(
      listed(database.connection, character_support.account_id),
      fn(found) { found.name },
    )
    == ["Ab Cd", "Ef Gh"]
    as "no name changed"
}

pub fn a_rename_that_changes_only_the_case_of_the_characters_own_name_is_allowed_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  add_accounts(database.connection)
  let character = saved(database.connection, "Ab Cd")
  assert store.run(
      database.connection,
      select.RenameStored(character_support.account_id, character.id, "ab cd"),
    )
    == Renamed(Character(..character, name: "ab cd"))
    as "a character is not another character, so it may take its own name in another case, which is shown as typed"
}
