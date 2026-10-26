//// Character select over TCP against the real game listener: a scripted client
//// (`login_client`, `game_client`, written from the fact file's records) logs
//// in, is handed to the game listener, sends 0x58F with the session key and
//// lists, creates, renames and deletes a character, each change read back from
//// the database; and a session key nobody issued, a key used already and a
//// malformed message each end with the reason logged and nothing written. The
//// accounts and characters are in a database of the test's own, and the
//// client's own tables are loaded from its files, so the tests skip where
//// `GENESIS_NO_CLIENT=1`.
////
//// Expected values are the client's records: 0x58F, 0x7E0, 0x117, 0x25B inside
//// 0x25C, 0xDC, 0x786, 0x14B, 0x352 and 0xE6 (opcode.0x58f, opcode.0x7e0,
//// opcode.0x117, opcode.0x25b, opcode.0x25c, opcode.0xdc, opcode.0x786,
//// opcode.0x14b, opcode.0x352, opcode.0xe6), and the CharacterCreation row a
//// character is made from (opcode.0x25b: class, race, sex and faction).
//// Every wait is for bytes the server writes, a line it logs or the socket
//// closing; the deadlines are for a server that does not answer, never a pause.

import environment
import game_client
import game_server
import genesis_prime/character/character.{type Character}
import genesis_prime/character/select.{Loaded}
import genesis_prime/character/store
import genesis_prime/login/account.{type Account}
import genesis_prime/login/account_store
import genesis_prime/login/handoff
import genesis_prime/message/character_list
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_result
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result
import genesis_prime/message/game_server_handoff
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result
import gleam/dict
import gleam/list
import gleam/string
import log_capture.{type Event}
import login_client
import owned_test
import template_database
import unitest

/// How long a test waits for a line the server must log, in milliseconds.
const wait_ms = 5000

fn characters_of(
  database database: template_database.Database,
  account account: Account,
) -> List(Character) {
  let assert Loaded(characters) =
    store.run(database.connection, select.LoadCharacters(account.id))
    as "the account's characters were read"
  characters
}

/// A key the auth login would have issued for the account, which the game
/// server redeems in 0x58F.
fn issued_key(
  running running: game_server.Running,
  account account: Account,
) -> BitArray {
  handoff.issue(running.session_keys, account.identity(account))
}

fn warning_about(text: String) -> fn(Event) -> Bool {
  fn(event: Event) {
    event.level == "warning" && string.contains(event.text, text)
  }
}

pub fn a_player_logs_in_and_lists_creates_renames_and_deletes_characters_over_tcp_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let assert Ok(account) =
    account_store.create(database.connection, "Jim", "secret")
    as "the account is created"
  let login =
    login_client.sts_login(
      ports: running.ports,
      name: "Jim",
      password: "secret",
      seed: 0x40,
    )
  let auth =
    login_client.auth_login(ports: running.ports, login:, build: 16_042)
  let assert [_, handed] =
    login_client.read_frames(client: auth, have: <<>>, count: 2)
    |> list.map(login_client.as_the_client_reads)
    as "0x591 and 0x3DB"
  let assert Ok(handoff_message) = game_server_handoff.decode(handed.body)
    as "the hand-off decodes"
  let game =
    game_client.connect(
      port: running.game_port,
      session_key: handoff_message.session_key,
      account_name: "jim",
    )

  // 0x7E0: the list of an account with no characters.
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [listed] = game_client.read(game:, count: 1)
    as "the character list"
  assert listed.message_id == 0x0117
  let assert Ok(list_message) = character_list.decode(listed.body)
    as "0x117 decodes"
  assert list_message.server_time == game_server.server_time
    as "opcode.0x117: the server's time as a 64-bit FILETIME, here the game clock the test planted"
  assert list_message.characters == [] as "a new account has no characters"
  assert list_message.realm_id == game_server.realm_id
    as "opcode.0x117: the realm id the client takes as its current realm"

  // 0x25B inside 0x25C: a character made from the client's own row.
  let row = running.facts.creation
  let assert Ok(create) =
    create_character.encode(
      CreateCharacter(
        creation_id: row.id,
        name: "Zed Mara",
        path: 1,
        customisation_labels: [1, 2],
        customisation_values: [3, 4],
        bone_values: [0x3F800000],
      ),
    )
    as "0x25B encodes"
  game_client.send_create(game:, body: create)
  let assert [created] = game_client.read(game:, count: 1)
    as "the create result"
  assert created.message_id == 0x00DC
  let assert Ok(created_message) = create_character_result.decode(created.body)
    as "0xDC decodes"
  assert created_message.result == 3 as "opcode.0xdc: result 3 means created"
  let assert [stored] = characters_of(database:, account:)
    as "the character is in the database"
  assert stored.id == created_message.character_id
    as "opcode.0xdc: the result names the new character by its id"
  assert stored.account_id == account.id && stored.name == "Zed Mara"
    as "the character belongs to the account that asked, under the name it chose"
  assert stored.class_id == row.class_id
    && stored.race_id == row.race_id
    && stored.gender == row.sex
    && stored.faction_id == row.faction_id
    as "opcode.0x25b: the CharacterCreation row gives class, race, sex and faction"
  assert stored.experience == row.xp
    && stored.level == game_server.level_of(running.facts, row.xp)
    as "CharacterCreation.tbl: the xp column is the experience a character starts with, and XpPerLevel gives its level"
  assert stored.place == game_server.start_place(running.facts.world_id)
    && stored.path == 1
    as "the place is the one the settings gave and the path the request's"

  // 0x786: a rename.
  let assert Ok(rename) =
    rename_character.encode(RenameCharacter(
      character_id: stored.id,
      name: "Zed Mira",
    ))
    as "0x786 encodes"
  game_client.send(game:, message_id: 0x0786, body: rename)
  let assert [renamed] = game_client.read(game:, count: 1)
    as "the rename result"
  assert renamed.message_id == 0x014B
  let assert Ok(renamed_message) = rename_character_result.decode(renamed.body)
    as "0x14B decodes"
  assert renamed_message.result == 18
    && renamed_message.character_id == stored.id
    && renamed_message.name == "Zed Mira"
    as "opcode.0x14b: result 18 means renamed, with the character's id and its new name"
  let assert [after_rename] = characters_of(database:, account:)
    as "the character is still the account's"
  assert after_rename == character.Character(..stored, name: "Zed Mira")
    as "the new name is in the database and nothing else changed"

  // 0x352: a delete.
  let assert Ok(delete) =
    delete_character.encode(DeleteCharacter(character_id: stored.id))
    as "0x352 encodes"
  game_client.send(game:, message_id: 0x0352, body: delete)
  let assert [deleted] = game_client.read(game:, count: 1)
    as "the delete result"
  assert deleted.message_id == 0x00E6
  let assert Ok(deleted_message) = delete_character_result.decode(deleted.body)
    as "0xE6 decodes"
  assert deleted_message.result == 0
    as "opcode.0xe6: result 0 removes the character from the client's list"
  assert characters_of(database:, account:) == []
    as "the character is gone from the database"
}

pub fn a_session_key_nobody_issued_closes_the_connection_and_logs_the_reason_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let capture = log_capture.start()
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let game =
    game_client.connect(
      port: running.game_port,
      session_key: <<16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1>>,
      account_name: "jim",
    )
  assert game_client.closed(game)
    as "opcode.0x58f: the key is the proof of the login, so a key the auth login never issued gets no game connection"
  let assert Ok(line) =
    log_capture.next_matching(
      capture:,
      within: wait_ms,
      matching: warning_about("session key"),
    )
    as "the reason is logged as a warning"
  assert dict.has_key(line.metadata, "peer")
    as "the line says whose connection it is"
}

pub fn a_session_key_used_already_closes_the_second_connection_and_logs_the_reason_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let capture = log_capture.start()
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let key = issued_key(running:, account:)
  let first =
    game_client.connect(
      port: running.game_port,
      session_key: key,
      account_name: "jim",
    )
  game_client.send(game: first, message_id: 0x07E0, body: <<>>)
  let assert [_listed] = game_client.read(game: first, count: 1)
    as "the first connection with the key reaches character select"
  let second =
    game_client.connect(
      port: running.game_port,
      session_key: key,
      account_name: "jim",
    )
  assert game_client.closed(second)
    as "a session key is redeemed once: the second connection with it is closed"
  let assert Ok(_) =
    log_capture.next_matching(
      capture:,
      within: wait_ms,
      matching: warning_about("session key"),
    )
    as "the reason is logged as a warning"
  Nil
}

pub fn a_malformed_message_ends_the_connection_with_the_reason_logged_and_nothing_written_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let capture = log_capture.start()
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let game =
    game_client.connect(
      port: running.game_port,
      session_key: issued_key(running:, account:),
      account_name: "jim",
    )
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_listed] = game_client.read(game:, count: 1)
    as "the character list"
  game_client.send_create(game:, body: <<1>>)
  assert game_client.closed(game)
    as "a message that does not decode ends the connection"
  let assert Ok(_) =
    log_capture.next_matching(
      capture:,
      within: wait_ms,
      matching: warning_about("0x025B"),
    )
    as "the reason is logged, naming the message by its number"
  assert characters_of(database:, account:) == [] as "nothing was written"
}

/// A create request for the row the tests make characters from.
fn create_request(
  running running: game_server.Running,
  name name: String,
) -> BitArray {
  let assert Ok(body) =
    create_character.encode(
      CreateCharacter(
        creation_id: running.facts.creation.id,
        name:,
        path: 1,
        customisation_labels: [1, 2],
        customisation_values: [3, 4],
        bone_values: [0x3F800000],
      ),
    )
    as "0x25B encodes"
  body
}

pub fn a_name_another_character_has_in_other_case_is_refused_on_create_and_rename_over_tcp_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let game =
    game_client.connect(
      port: running.game_port,
      session_key: issued_key(running:, account:),
      account_name: "jim",
    )
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_listed] = game_client.read(game:, count: 1)
    as "the character list"
  game_client.send_create(
    game:,
    body: create_request(running:, name: "Zed Mara"),
  )
  let assert [first] = game_client.read(game:, count: 1) as "the create result"
  let assert Ok(first_result) = create_character_result.decode(first.body)
    as "0xDC decodes"
  assert first_result.result == 3 as "opcode.0xdc: result 3 means created"
  game_client.send_create(
    game:,
    body: create_request(running:, name: "zed mara"),
  )
  let assert [second] = game_client.read(game:, count: 1)
    as "the second create result"
  let assert Ok(second_result) = create_character_result.decode(second.body)
    as "0xDC decodes"
  assert second_result.result == 6
    as "PreGameLib.CodeEnumCharacterModifyResults: 6 is CreateFailed_UniqueName; names are unique regardless of case (Jim's decision)"
  game_client.send_create(game:, body: create_request(running:, name: "Ab Cd"))
  let assert [third] = game_client.read(game:, count: 1)
    as "the third create result"
  let assert Ok(third_result) = create_character_result.decode(third.body)
    as "0xDC decodes"
  assert third_result.result == 3 as "a name no character has is created"
  let assert Ok(rename) =
    rename_character.encode(RenameCharacter(
      character_id: third_result.character_id,
      name: "ZED MARA",
    ))
    as "0x786 encodes"
  game_client.send(game:, message_id: 0x0786, body: rename)
  let assert [renamed] = game_client.read(game:, count: 1)
    as "the rename result"
  let assert Ok(renamed_message) = rename_character_result.decode(renamed.body)
    as "0x14B decodes"
  assert renamed_message.result == 16
    as "PreGameLib.CodeEnumCharacterModifyResults: 16 is RenameFailed_UniqueName; names are unique regardless of case (Jim's decision)"
  assert list.map(characters_of(database:, account:), fn(stored) { stored.name })
    == ["Zed Mara", "Ab Cd"]
    as "the names are shown as they were typed, and the refused ones changed nothing"
}
