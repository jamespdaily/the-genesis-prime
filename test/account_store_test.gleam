//// The account store: one worker per ask, on pog's pool, against a migrated
//// database of the test's own (`test/database_support.gleam`). Expected values
//// come from these places.
//// - The rows the tests insert, and the table's columns in
////   `priv/migrations/0001_account_and_character.sql`,
////   `priv/migrations/0002_character_list_columns.sql` and
////   `priv/migrations/0003_character_look.sql`.
//// - The create: a new character has the values of its CharacterCreation row
////   at the level the create gave (3, the level of a Veteran row's xp 1710 by
////   GetLevelForExperience 0x140029820), with its path, look and bones as the client sent them
////   (opcode.0x25b); a name is unique ignoring case and an account holds at
////   most its slots (lua.CharacterSelection.OnLoadFromCharacter), each held by
////   Postgres, so a create that is refused stores nothing.
//// - The client's character list: class icons for the classes 1 to 20 and path
////   icons for the paths 0 to 3 (lua.CharacterSelection.OnLoadFromCharacter.list).
//// - The GUID's wire bytes: `genesis_prime/login/guid` (the first three groups
////   of the text are little-endian integers, the last two groups raw bytes;
////   opcode.0x592).
//// - The store's contract in the doc comments of `genesis_prime/store` and
////   `genesis_prime/store/worker`, and the shell's in `genesis_prime/connection/
////   shell`, as approved on the login processes card.
//// Every wait is for an event, with a deadline a passing test never reaches,
//// except the asks that are about a deadline passing.

import ask_support
import asking_rule
import character_support
import database_support
import genesis_prime/add_character/sql as add_character_sql
import genesis_prime/game/character_name
import genesis_prime/game/start_place.{Facing}
import genesis_prime/login/guid
import genesis_prime/service.{ToWorker}
import genesis_prime/store.{
  type AccountId, type ActiveQuest, type QuestRow, Account, AccountFound,
  AccountId, ActiveQuest, Character, CharacterCreated, CharacterDeleted,
  CharacterId, CharacterLoaded, CharacterRenamed, CreateCharacter,
  CreateForNoSuchAccount, Created, DeleteCharacter, Deleted, ExperienceRefused,
  FindAccount, ForItems, ForLogin, ForMove, ForSelect, ForWorld, HealthRefused,
  HeldItem, ItemMove, ItemPlace, Items, ItemsMoved, ListCharacters, Listed,
  LoadCharacter, Login, LookEntry, Move, MoveItems, MoveRefused, NameBreaksRule,
  NameStands, NameTaken, NeedsRename, NewCharacter, NewItem, NewNameBreaksRule,
  NewNameTaken, NoFreeSlot, NoSuchAccount, NoSuchCharacter, NotRenamable,
  NotTheAccounts, NothingMoved, NothingSaved, PlaceRefused, PlaceSaved,
  QuestLogRefused, QuestRow, RenameCharacter, Renamed, SavePlace, Select,
  Unavailable, World,
}
import genesis_prime/store/worker
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import gleam/bool
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import gleam/result
import gleam/string
import login_support
import owned_test
import place_support
import pog
import readiness_support
import relay

pub fn a_stored_login_name_gives_its_account_id_salt_verifier_and_game_account_id_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let id =
    login_support.insert_account(
      pool: store.pool,
      login_name: "login-1",
      salt: <<1, 2, 3>>,
      verifier: <<4, 5, 6, 7>>,
      game_account_id: a_game_account_id(),
    )
  // The GUID's wire bytes: 01234567 and the two 16-bit groups little-endian,
  // then the last 8 bytes as written.
  let assert Ok(game_account_id) =
    guid.from_wire(<<
      0x67, 0x45, 0x23, 0x01, 0xAB, 0x89, 0xEF, 0xCD, 0x01, 0x23, 0x45, 0x67,
      0x89, 0xAB, 0xCD, 0xEF,
    >>)
    as "sixteen bytes are a GUID"
  assert ask(store, Login(FindAccount("login-1")))
    == ForLogin(
      AccountFound(Account(
        account_id: AccountId(id),
        login_name: "login-1",
        srp_salt: <<1, 2, 3>>,
        srp_verifier: <<4, 5, 6, 7>>,
        game_account_id:,
      )),
    )
    as "the row the test inserted, as the STS login needs it"
  stop(store)
}

pub fn an_unknown_login_name_gives_no_such_account_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let _id =
    login_support.insert_account(
      pool: store.pool,
      login_name: "login-1",
      salt: <<1>>,
      verifier: <<2>>,
      game_account_id: a_game_account_id(),
    )
  assert ask(store, Login(FindAccount("login-2"))) == ForLogin(NoSuchAccount)
    as "no row has that login name"
  stop(store)
}

pub fn with_no_database_connection_the_answer_is_unavailable_and_the_asking_connection_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let settings = database_support.settings()
  let assert Ok(away) =
    relay.refusing(to: relay.Target(
      host: settings.tcp_host,
      port: settings.port,
    ))
    as "a port with nothing listening"
  // The queue's targets are short so the pool gives up on a request quickly.
  let config =
    database_support.config(
      for: settings,
      database: "postgres",
      pool_name: process.new_name("account_pool"),
      pool_size: 1,
    )
    |> pog.host(away.host)
    |> pog.port(away.port)
    |> pog.queue_target(50)
    |> pog.queue_interval(100)
  let store = start_store_on(config)
  let server = start_asker(store, ask_support.unreported)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.store_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_unavailable
    as "the pool has no connection to the database"
  ask_support.command(client, asking_rule.ping_command, 9, wait_ms: 0)
  assert ask_support.read_pong(client) == <<0x70, 9>>
    as "the connection goes on"
  ask_support.stop(server)
  stop(store)
}

pub fn a_query_still_running_at_the_askers_deadline_has_its_worker_ended_and_the_asker_gets_no_answer_in_time_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 3)
  let workers = process.new_subject()
  // The connection's directory reports the worker and waits for the test to
  // have its monitor on it, so the worker's end is seen as `shutdown` however
  // slow the machine is: the asker ends the worker only after the report.
  let server =
    start_asker(store, fn(sent) {
      case sent {
        ToWorker(pid:) -> {
          let monitored = process.new_subject()
          process.send(workers, #(pid, monitored))
          let assert Ok(Nil) =
            process.receive(monitored, within: ask_support.event_wait_ms)
            as "the test monitored the worker"
          Nil
        }
        service.ToService(..) | service.NoReplyInTime -> Nil
      }
    })
  let client = ask_support.connect(server)
  // A transaction in another connection locks the table, so the query waits.
  let lock = lock_table(store.pool)
  ask_support.command(client, asking_rule.store_command, 1, wait_ms: 300)
  let assert Ok(#(worker_pid, monitored)) =
    process.receive(workers, within: ask_support.event_wait_ms)
    as "the ask started a worker"
  let worker_ended = process.monitor(worker_pid)
  process.send(monitored, Nil)
  let _asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_no_answer_in_time
    as "the query was still waiting for the lock at the deadline"
  assert ask_support.ended(worker_ended) == ask_support.shutdown()
    as "the asker ended the worker with exit shutdown, the lock still held"
  release_lock(lock)
  ask_support.stop(server)
  stop(store)
}

/// The pool is stopped the moment the lock is released, as a test's end does;
/// the locking transaction's commit must already be done, or it reads a closed
/// socket (`query_timeout`) and its crash ends the test.
pub fn a_lock_released_and_the_pool_stopped_at_once_does_not_crash_the_test_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(list.repeat(Nil, 20), fn(_) {
    let store = start_store(pool_size: 2)
    release_lock(lock_table(store.pool))
    stop(store)
  })
}

pub fn a_worker_that_crashes_gives_ended_before_answer_and_the_store_goes_on_serving_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let server = start_asker(store, ask_support.unreported)
  let client = ask_support.connect(server)
  // With the table gone the query fails in the database, which is a bug in
  // the schema or the query and not an outside failure: the worker crashes.
  execute(store.pool, "alter table account rename to account_away")
  ask_support.command(
    client,
    asking_rule.store_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let crashed = ask_support.read_record(client)
  assert crashed.code == asking_rule.code_ended_before_answer
    as "the worker crashed on the failed query"
  execute(store.pool, "alter table account_away rename to account")
  ask_support.command(
    client,
    asking_rule.store_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let next = ask_support.read_record(client)
  assert next.code == asking_rule.code_no_such_account
    as "the store answers the next ask"
  ask_support.stop(server)
  stop(store)
}

pub fn with_the_stores_supervisor_not_running_an_ask_to_the_store_gives_not_running_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  // No process is started under this name.
  let absent = process.new_name("store")
  let server =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: ask_support.directory(
        gate: process.new_name("gate"),
        store: Some(absent),
        sent: ask_support.unreported,
      ),
      shutdown_ms: 1000,
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.store_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_not_running
    as "no process holds the store's name"
  ask_support.command(client, asking_rule.ping_command, 9, wait_ms: 0)
  assert ask_support.read_pong(client) == <<0x70, 9>>
    as "the connection goes on"
  ask_support.stop(server)
}

pub fn with_the_database_pool_not_running_an_ask_to_the_store_gives_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  // The store runs on a pool name no process holds.
  let pool = pog.named_connection(process.new_name("absent_pool"))
  let name = process.new_name("store")
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(worker.supervised(name:, pool:))
    |> supervisor.start
    as "the store started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  let store = Store(tree: started.pid, pool:, name:)
  assert ask(store, Login(FindAccount("login-1"))) == Unavailable
    as "the pool is not running, so the query cannot reach the database"
  stop(store)
}

pub fn the_list_gives_the_accounts_characters_in_creation_order_and_no_other_accounts_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  // Created in this order; their names sort the other way.
  let first =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let second =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Abe Qu",
      class_id: 12,
      path: 0,
    )
  let _theirs =
    character_support.insert(
      pool: store.pool,
      account: other,
      name: "Cal Qu",
      class_id: 1,
      path: 1,
    )
  assert ask(store, Select(ListCharacters(account)))
    == ForSelect(
      Listed([
        Character(
          character_id: CharacterId(first),
          name: "Zed Qu",
          gender: 1,
          race_id: RaceId(3),
          class_id: ClassId(4),
          faction_id: 166,
          level: 9,
          path: 2,
          place: Some(place_support.at(
            world_id: 1387,
            world_zone_id: 1100,
            x: 1.5,
            y: 2.5,
            z: 3.5,
          )),
          look: [],
          bones: [],
          naming: NameStands,
        ),
        Character(
          character_id: CharacterId(second),
          name: "Abe Qu",
          gender: 1,
          race_id: RaceId(3),
          class_id: ClassId(12),
          faction_id: 166,
          level: 9,
          path: 0,
          place: Some(place_support.at(
            world_id: 1387,
            world_zone_id: 1100,
            x: 1.5,
            y: 2.5,
            z: 3.5,
          )),
          look: [],
          bones: [],
          naming: NameStands,
        ),
      ]),
    )
    as "the account's two rows as inserted, in the order of their ids, and not the other account's row"
  stop(store)
}

pub fn an_account_with_no_characters_or_no_account_gives_an_empty_list_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  assert ask(store, Select(ListCharacters(account))) == ForSelect(Listed([]))
    as "no row has that account's id"
  assert ask(store, Select(ListCharacters(AccountId(account_id_nobody_has))))
    == ForSelect(Listed([]))
    as "the contract of store.Characters: none when no such account exists"
  stop(store)
}

pub fn with_the_database_pool_not_running_a_list_of_characters_gives_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pog.named_connection(process.new_name("absent_pool"))
  let name = process.new_name("store")
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(worker.supervised(name:, pool:))
    |> supervisor.start
    as "the store started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  let store = Store(tree: started.pid, pool:, name:)
  assert ask(store, Select(ListCharacters(AccountId(1)))) == Unavailable
    as "the pool is not running, so the query cannot reach the database"
  assert ask(store, Select(DeleteCharacter(AccountId(1), CharacterId(1))))
    == Unavailable
    as "a delete the database cannot be reached for is unavailable, not a character that is none"
  assert ask(
      store,
      Select(RenameCharacter(AccountId(1), CharacterId(1), "Ab Cd")),
    )
    == Unavailable
    as "and so is a rename"
  stop(store)
}

pub fn the_table_refuses_a_class_outside_1_to_20_and_a_path_outside_0_to_3_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let refused = fn(name, class_id, path) {
    refusal_of(store:, account:, name:, class_id:, path:)
  }
  assert refused("Eve Qu", 0, 0) == "character_class_shown_by_the_client"
    as "the client shows ClassIcon_<class> for the classes 1 to 20, so class 0 has no icon"
  assert refused("Eve Qu", 21, 0) == "character_class_shown_by_the_client"
    as "and class 21 has none"
  assert refused("Eve Qu", 1, 4) == "character_path_shown_by_the_client"
    as "the client shows PathIcon_<path + 1> up to 4, so path 4 has no icon"
  assert refused("Eve Qu", 1, -1) == "character_path_shown_by_the_client"
  // The edges the client does show are taken, each with a name of its own: a
  // name is unique ignoring case (migrations 0003 and 0005).
  assert refused("Eve Qu", 1, 0) == "accepted"
  assert refused("Eva Qu", 20, 3) == "accepted"
  stop(store)
}

/// What the table said of a character row with the name, class and path:
/// "accepted", the name of the constraint that refused it, or a note that the
/// failure was no constraint.
fn refusal_of(
  store store: Store,
  account account: AccountId,
  name name: String,
  class_id class_id: Int,
  path path: Int,
) -> String {
  case
    character_support.try_insert(
      pool: store.pool,
      account:,
      name:,
      class_id:,
      path:,
    )
  {
    Ok(_) -> "accepted"
    Error(character_support.Refused(constraint:)) -> constraint
    Error(character_support.NotAConstraint) -> "a failure that is no constraint"
  }
}

pub fn the_table_refuses_a_name_that_breaks_text_rule_0_by_character_name_follows_rule_0_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let refused = fn(name) {
    refusal_of(store:, account:, name:, class_id: 1, path: 0)
  }
  // vector.0x1403e1170.names: the emulator ran CheckTextRule 0x1403e1170 on each
  // text, which is letters and exactly one space, not first or last, 5 to 30
  // characters in all.
  list.each(
    [
      #("Ab C", "4 characters"),
      #("Abcd", "4 characters and no space"),
      #("Abc", "too short and no space"),
      #("Abcde", "5 characters and no space"),
      #("Ab  Cd", "two spaces"),
      #("Ab Cd Ef", "two spaces"),
      #(" Abc Def", "a space first"),
      #("Abc Def ", "a space last"),
      #("Ab1 Cd", "a digit"),
      #("Ab-Cd Ef", "a hyphen"),
      #("Ab_Cd Ef", "an underscore"),
      #("Ab'c Def", "an apostrophe"),
      #("Ab.c Def", "a full stop"),
      #("Abcå Def", "a letter the client does not list (å is not in its list)"),
      #("AbЖ Cd", "a Cyrillic letter"),
      #("Ab\nCd", "a line break"),
      #("Ab Cd\n", "a line break at the end"),
      #("", "no text"),
      #(
        string.repeat("A", 15) <> " " <> string.repeat("B", 15),
        "31 characters",
      ),
      #(
        string.repeat("é", 16) <> " " <> string.repeat("é", 15),
        "32 characters, 63 bytes: the table counts characters",
      ),
    ],
    fn(refused_name) {
      let #(name, why) = refused_name
      assert refused(name) == "character_name_follows_rule_0"
        as { "vector.0x1403e1170.names refuses " <> why }
    },
  )
  // A name at the edges and with each letter the client lists is taken, each
  // with a name of its own (a name is unique ignoring case).
  assert refused("Ab Cd") == "accepted" as "5 characters, the fewest"
  assert refused(string.repeat("A", 14) <> " " <> string.repeat("B", 15))
    == "accepted"
    as "30 characters, the most"
  assert refused(string.repeat("É", 15) <> " " <> string.repeat("é", 14))
    == "accepted"
    as "0x1403e1170: the bound counts characters, and 30 of these are 59 bytes"
  let letters =
    list.append(
      string.to_graphemes(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
      ),
      string.to_graphemes(character_name.listed_letters),
    )
  assert list.length(letters) == 52 + 53
    as "A to Z, a to z and the client's 53 listed letters (IsTextRuleLetter 0x1403e09d0)"
  list.each(letters, fn(letter) {
    // The letter is first on one side of the space and last on the other, so
    // the pattern takes it on each side. A capital and its small letter fold to
    // one name, so each pair's two names differ in a letter beside it.
    let case_mark = case string.lowercase(letter) == letter {
      True -> "l"
      False -> "u"
    }
    assert refused(case_mark <> letter <> "x " <> "zw" <> letter) == "accepted"
      as { "a letter the client lists is accepted: " <> letter }
  })
  // Every other character of Latin-1 and Latin Extended-A and -B is refused: the
  // client's list is these 53 letters and no more.
  list.each(character_support.numbers(0x24F), fn(number) {
    use <- bool.guard(number < 0x80, Nil)
    let assert Ok(codepoint) = string.utf_codepoint(number)
    let character = string.from_utf_codepoints([codepoint])
    use <- bool.guard(list.contains(letters, character), Nil)
    assert refused("Ab" <> character <> " Cd")
      == "character_name_follows_rule_0"
      as { "a character the client does not list is refused: " <> character }
  })
  stop(store)
}

pub fn a_character_the_developer_tool_adds_is_listed_with_the_values_it_was_given_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  // Sex 1, race 1, class 1 and faction 167, as CharacterCreation rows 21, 338,
  // 402, 466 and 539 give them; the tool's other columns are its defaults.
  let assert Ok(returned) =
    add_character_sql.insert_character(
      store.pool,
      "login-1",
      "Dev Qu",
      1,
      1,
      1,
      167,
    )
    as "the tool's query ran"
  let assert [add_character_sql.InsertCharacterRow(character_id:)] =
    returned.rows
    as "the account of that login name got one row"
  assert ask(store, Select(ListCharacters(account)))
    == ForSelect(
      Listed([
        Character(
          character_id: CharacterId(character_id),
          name: "Dev Qu",
          gender: 1,
          race_id: RaceId(1),
          class_id: ClassId(1),
          faction_id: 167,
          level: 1,
          path: 0,
          place: None,
          look: [],
          bones: [],
          naming: NameStands,
        ),
      ]),
    )
    as "the tool's doc comment: level 1, path 0, no world, zone or position"
  let assert Ok(none) =
    add_character_sql.insert_character(
      store.pool,
      "nobody",
      "Dev Qu",
      1,
      1,
      1,
      167,
    )
    as "the query ran"
  assert none.rows == [] as "no account of that name gives no row"
  stop(store)
}

// ---- delete and rename ----

/// The names of the account's characters, in the order they were created.
fn names_listed(store: Store, account: AccountId) -> List(String) {
  let assert ForSelect(Listed(characters)) =
    ask(store, Select(ListCharacters(account)))
    as "a list is answered with a list"
  list.map(characters, fn(character) { character.name })
}

fn deleted(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
) -> store.DeleteAnswer {
  let assert ForSelect(Deleted(answer)) =
    ask(store, Select(DeleteCharacter(account, CharacterId(character_id))))
    as "a delete is answered with a delete's answer"
  answer
}

fn renamed(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
  name name: String,
) -> store.RenameAnswer {
  let assert ForSelect(Renamed(answer)) =
    ask(
      store,
      Select(RenameCharacter(account, CharacterId(character_id), name)),
    )
    as "a rename is answered with a rename's answer"
  answer
}

pub fn a_delete_removes_the_accounts_character_and_the_list_omits_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let zed =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let _abe =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Abe Qu",
      class_id: 4,
      path: 2,
    )
  assert deleted(store:, account: account, character_id: zed)
    == CharacterDeleted
    as "lua.CharacterSelection.OnCharacterDeleteResult: the character is removed and the result is 0"
  assert names_listed(store, account) == ["Abe Qu"]
    as "the next list omits it and keeps the account's other character"
  assert deleted(store:, account: account, character_id: zed) == NoSuchCharacter
    as "a character deleted is gone, so a repeated delete finds none"
  stop(store)
}

pub fn a_delete_of_another_accounts_character_or_of_none_is_no_such_character_and_deletes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let theirs =
    character_support.insert(
      pool: store.pool,
      account: other,
      name: "Cal Qu",
      class_id: 1,
      path: 1,
    )
  assert deleted(store:, account: account, character_id: theirs)
    == NoSuchCharacter
    as "CLAUDE.md: a modified client could send any id, so the statement is scoped by the account's id"
  assert deleted(store:, account: account, character_id: account_id_nobody_has)
    == NoSuchCharacter
  assert names_listed(store, other) == ["Cal Qu"]
    as "the other account's character is untouched"
  stop(store)
}

pub fn a_rename_of_a_marked_character_stores_the_name_clears_the_mark_and_answers_the_stored_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let zed =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  assert naming_of(store, account) == [NameStands]
    as "a character the table inserts needs no rename"
  character_support.mark_for_rename(pool: store.pool, name: "Zed Qu")
  assert naming_of(store, account) == [NeedsRename]
    as "opcode.0x117 carries the rename bit the client offers a rename by (lua.CharacterSelection.OnSelectCharacter)"
  assert renamed(store:, account: account, character_id: zed, name: "Ab Cd")
    == CharacterRenamed("Ab Cd")
    as "opcode.0x14b: result 18 gives the id and the name the character now has"
  assert names_listed(store, account) == ["Ab Cd"]
  assert naming_of(store, account) == [NameStands]
    as "opcode.0x14b: the character loses its needs-a-rename mark with the rename"
  assert renamed(store:, account: account, character_id: zed, name: "Ef Gh")
    == NotRenamable
    as "the mark is cleared, so a second rename is none the client offers"
  assert names_listed(store, account) == ["Ab Cd"]
  stop(store)
}

/// How each of the account's characters stands for a rename, in the order they
/// were created.
fn naming_of(store: Store, account: AccountId) -> List(store.Naming) {
  let assert ForSelect(Listed(characters)) =
    ask(store, Select(ListCharacters(account)))
    as "a list is answered with a list"
  list.map(characters, fn(character) { character.naming })
}

pub fn a_rename_to_a_name_taken_in_any_case_is_new_name_taken_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let zed =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let _abe =
    character_support.insert(
      pool: store.pool,
      account: other,
      name: "Abe Qu",
      class_id: 4,
      path: 2,
    )
  character_support.mark_for_rename(pool: store.pool, name: "Zed Qu")
  assert renamed(store:, account: account, character_id: zed, name: "aBE qU")
    == NewNameTaken
    as "lua.CharacterSelection.OnCharacterRenameResult: 16; a name is unique ignoring case, across accounts, held by the unique index on the lower-cased name (migrations 0003 and 0005)"
  assert names_listed(store, account) == ["Zed Qu"]
  assert naming_of(store, account) == [NeedsRename]
    as "the refused rename left the mark, so the player can pick another name"
  assert renamed(store:, account: account, character_id: zed, name: "Ab Cd")
    == CharacterRenamed("Ab Cd")
    as "and another name is taken"
  stop(store)
}

pub fn a_rename_of_an_unmarked_or_another_accounts_character_or_of_none_is_not_renamable_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let mine =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  let theirs =
    character_support.insert(
      pool: store.pool,
      account: other,
      name: "Abe Qu",
      class_id: 4,
      path: 2,
    )
  character_support.mark_for_rename(pool: store.pool, name: "Abe Qu")
  assert renamed(store:, account: account, character_id: mine, name: "Ab Cd")
    == NotRenamable
    as "lua.CharacterSelection.OnSelectCharacter: the client offers a rename only for a marked character"
  assert renamed(store:, account: account, character_id: theirs, name: "Ab Cd")
    == NotRenamable
    as "a modified client could send any id: the update is scoped by the account's id, whatever the mark"
  assert renamed(
      store:,
      account: account,
      character_id: account_id_nobody_has,
      name: "Ab Cd",
    )
    == NotRenamable
  assert names_listed(store, account) == ["Zed Qu"]
  assert names_listed(store, other) == ["Abe Qu"]
  assert naming_of(store, other) == [NeedsRename]
    as "the other account's character keeps its mark"
  stop(store)
}

// ---- create ----

/// A new character with the values of CharacterCreation row 466 (class 1,
/// race 1, sex 1, faction 167), the level 3 of a Veteran row's xp 1710, the
/// path 2, the start place of WorldLocation2 row 51596 and a look and bones.
fn a_new_character(name: String) -> store.NewCharacter {
  NewCharacter(
    name:,
    gender: 1,
    race_id: RaceId(1),
    class_id: ClassId(1),
    faction_id: 167,
    level: 3,
    experience: 1710,
    path: 2,
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.128599166870117,
      y: -853.87158203125,
      z: -560.18798828125,
    ),
    look: [
      LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
      LookEntry(label: CharacterCustomizationLabelId(22), value: 4_000_000_000),
    ],
    // 0xBF800000 is -1.0 and has its top bit set; 0x3F800000 is 1.0.
    bones: [0xBF800000, 0x3F800000, 0],
    starting_items: [],
  )
}

fn create(
  store store: Store,
  account account: AccountId,
  name name: String,
  slots slots: Int,
) -> store.CreateAnswer {
  create_holding(store:, account:, name:, slots:, items: [])
}

/// A create of the character that starts with these items.
fn create_holding(
  store store: Store,
  account account: AccountId,
  name name: String,
  slots slots: Int,
  items items: List(store.NewItem),
) -> store.CreateAnswer {
  let assert ForSelect(Created(answer)) =
    ask(
      store,
      Select(CreateCharacter(
        account_id: account,
        character: NewCharacter(..a_new_character(name), starting_items: items),
        character_slots: slots,
      )),
    )
    as "a create is answered with a create's answer"
  answer
}

pub fn a_create_stores_the_character_at_the_level_it_was_given_with_the_values_it_was_given_and_the_list_returns_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(character_id:) =
    create(store:, account: account, name: "Ab Cd", slots: 2)
    as "the first create of an account with 2 slots is stored"
  assert ask(store, Select(ListCharacters(account)))
    == ForSelect(
      Listed([
        Character(
          character_id:,
          name: "Ab Cd",
          gender: 1,
          race_id: RaceId(1),
          class_id: ClassId(1),
          faction_id: 167,
          level: 3,
          path: 2,
          place: Some(place_support.at(
            world_id: 3460,
            world_zone_id: 6009,
            x: 29.128599166870117,
            y: -853.87158203125,
            z: -560.18798828125,
          )),
          look: [
            LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
            LookEntry(
              label: CharacterCustomizationLabelId(22),
              value: 4_000_000_000,
            ),
          ],
          bones: [0xBF800000, 0x3F800000, 0],
          naming: NameStands,
        ),
      ]),
    )
    as "the create's result: race, sex, class and faction from the creation row, the level the create gave (3, not 1), the start place the create gave (World 3460, zone 6009 and the position of WorldLocation2 row 51596, as 32-bit floats), the look and the bones as the client sent them (32-bit values come back as they went in)"
  stop(store)
}

pub fn a_stored_character_with_world_0_loads_as_no_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let AccountId(id) = account
  let assert Ok(pog.Returned(rows: [character_id], ..)) =
    pog.query(
      "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values ($1, 'Ab Cd', 1, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0) returning character_id",
    )
    |> pog.parameter(pog.int(id))
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(store.pool)
    as "the table allows world 0 with no zone and no position"
  let character =
    Character(
      character_id: CharacterId(character_id),
      name: "Ab Cd",
      gender: 1,
      race_id: RaceId(1),
      class_id: ClassId(1),
      faction_id: 167,
      level: 1,
      path: 0,
      place: None,
      look: [],
      bones: [],
      naming: NameStands,
    )
  assert ask(store, Select(ListCharacters(account)))
    == ForSelect(Listed([character]))
    as "world 0 is no World row, which 0xAD needs (opcode.0xad), so the list reads no place"
  assert ask(store, World(LoadCharacter(account, CharacterId(character_id))))
    == ForWorld(
      CharacterLoaded(character, character_support.epoch(1), None, None, [], []),
    )
    as "the load reads the same row the same way, and raises the epoch of a character made at 0 to 1"
  stop(store)
}

pub fn the_table_refuses_a_character_with_no_world_that_has_a_zone_or_a_position_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let AccountId(id) = account
  let insert = fn(name, world_id, world_zone_id, x, y, z) {
    pog.query(
      "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values ($1, $2, 1, 1, 1, 167, 1, 0, $3, $4, $5, $6, $7)",
    )
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.text(name))
    |> pog.parameter(pog.int(world_id))
    |> pog.parameter(pog.int(world_zone_id))
    |> pog.parameter(pog.float(x))
    |> pog.parameter(pog.float(y))
    |> pog.parameter(pog.float(z))
    |> pog.execute(store.pool)
    |> result.map_error(fn(error) {
      let assert pog.ConstraintViolated(constraint:, ..) = error
        as "the table refused with a constraint"
      constraint
    })
    |> result.replace(Nil)
  }
  let refused = Error("character_no_world_has_no_zone_or_position")
  assert insert("Zone Ab", 0, 7, 0.0, 0.0, 0.0) == refused
    as "world 0 is no World row (opcode.0xad), so a zone of it means nothing"
  assert insert("Xxx Ab", 0, 0, 1.5, 0.0, 0.0) == refused
  assert insert("Yyy Ab", 0, 0, 0.0, 2.5, 0.0) == refused
  assert insert("Zzz Ab", 0, 0, 0.0, 0.0, 3.5) == refused
    as "nor does any one coordinate"
  assert insert("None Ab", 0, 0, 0.0, 0.0, 0.0) == Ok(Nil)
    as "a character with no place is world 0, zone 0 and position 0"
  assert insert("Placed Ab", 1387, 1100, 1.5, 2.5, 3.5) == Ok(Nil)
    as "a character with a world keeps its zone and position"
  stop(store)
}

pub fn a_load_gives_the_accounts_character_with_its_saved_place_and_not_another_accounts_or_a_missing_one_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  // Class 12 has no Dominion Novice set, so the characters hold no item and
  // this test checks the place, the epoch and the health alone.
  let mine =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 12,
      path: 2,
    )
  let theirs =
    character_support.insert(
      pool: store.pool,
      account: other,
      name: "Abe Qu",
      class_id: 12,
      path: 2,
    )
  assert ask(store, World(LoadCharacter(account, CharacterId(mine))))
    == ForWorld(
      CharacterLoaded(
        Character(
          character_id: CharacterId(mine),
          name: "Zed Qu",
          gender: 1,
          race_id: RaceId(3),
          class_id: ClassId(12),
          faction_id: 166,
          level: 9,
          path: 2,
          place: Some(place_support.at(
            world_id: 1387,
            world_zone_id: 1100,
            x: 1.5,
            y: 2.5,
            z: 3.5,
          )),
          look: [],
          bones: [],
          naming: NameStands,
        ),
        character_support.epoch(1),
        None,
        None,
        [],
        [],
      ),
    )
    as "the row as character_support inserted it: the saved world, zone and position come with it, the epoch the load raised from 0 to 1, and no saved health: a character never saved enters at full health"
  assert ask(store, World(LoadCharacter(account, CharacterId(theirs))))
    == ForWorld(NotTheAccounts)
    as "a modified client could name any id: the read is scoped by the account's id (genesis_prime/store)"
  assert ask(
      store,
      World(LoadCharacter(account, CharacterId(account_id_nobody_has))),
    )
    == ForWorld(NotTheAccounts)
    as "no row has the id"
  stop(store)
}

pub fn a_name_taken_in_any_case_is_name_taken_and_nothing_is_stored_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let assert CharacterCreated(_) =
    create(store:, account: account, name: "Ab Cd", slots: 2)
  assert create(store:, account: other, name: "aB cD", slots: 2) == NameTaken
    as "lua.Character.OnCreateCharacterFailed: 6; a name is unique ignoring case, across accounts, held by a unique index on the lower-cased name"
  assert create(store:, account: account, name: "AB CD", slots: 2) == NameTaken
    as "the same account too"
  assert ask(store, Select(ListCharacters(other))) == ForSelect(Listed([]))
    as "nothing was stored for the refused create"
  let assert ForSelect(Listed([_])) =
    ask(store, Select(ListCharacters(account)))
    as "the account still holds its one character"
  let assert CharacterCreated(_) =
    create(store:, account: other, name: "Éb Cd", slots: 2)
  assert create(store:, account: account, name: "éB cD", slots: 2) == NameTaken
    as "the Latin-1 letters the client lists fold too (IsTextRuleLetter 0x1403e09d0), so 'É' and 'é' are one letter"
  stop(store)
}

pub fn a_name_taken_in_any_case_is_refused_on_a_database_made_with_the_c_locale_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let store =
    start_store_in(
      database: database_support.new_database_with_locale(
        on: shared,
        locale: "C",
      ),
      pool_size: 2,
    )
  let assert Ok(pog.Returned(rows: ["C c"], ..)) =
    pog.query(
      "select datcollate || ' ' || datlocprovider::text from pg_database where datname = current_database()",
    )
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(store.pool)
    as "the database says it was made with the C locale and the libc provider, not the ICU one the index folds under"
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let assert CharacterCreated(_) =
    create(store:, account: account, name: "Éb Cd", slots: 2)
  assert create(store:, account: other, name: "éB cD", slots: 2) == NameTaken
    as "lua.Character.OnCreateCharacterFailed: 6; a name is unique ignoring case on any database locale, and the Latin-1 letters the client lists fold too (IsTextRuleLetter 0x1403e09d0), so 'É' and 'é' are one letter, though the C locale's own lower() leaves 'É' alone"
  assert ask(store, Select(ListCharacters(other))) == ForSelect(Listed([]))
    as "nothing was stored for the refused create"
  stop(store)
}

pub fn an_account_at_its_slot_count_gets_no_free_slot_and_nothing_is_stored_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let assert CharacterCreated(_) =
    create(store:, account: account, name: "Ab Cd", slots: 2)
  let assert CharacterCreated(_) =
    create(store:, account: account, name: "Ef Gh", slots: 2)
  assert create(store:, account: account, name: "Ij Kl", slots: 2) == NoFreeSlot
    as "lua.CharacterSelection.OnLoadFromCharacter: 2 slots without an entitlement; a create past them is account full (9)"
  let assert ForSelect(Listed([_, _])) =
    ask(store, Select(ListCharacters(account)))
    as "nothing was stored for the refused create"
  let assert CharacterCreated(_) =
    create(store:, account: other, name: "Mn Op", slots: 2)
    as "another account's slots are its own"
  assert create(store:, account: account, name: "Ij Kl", slots: 3)
    |> is_created
    as "with 3 slots the same account may make a third"
  stop(store)
}

pub fn with_6_slots_an_account_with_6_characters_gets_no_free_slot_and_with_5_gets_one_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let names = ["Ab Cd", "Ef Gh", "Ij Kl", "Mn Op", "Qr St", "Uv Wx"]
  list.each(list.take(names, 5), fn(name) {
    let assert CharacterCreated(_) =
      create(store:, account: account, name: name, slots: 6)
      as "5 characters are below 6 slots, so the create is accepted"
  })
  let assert CharacterCreated(_) =
    create(store:, account: account, name: "Uv Wx", slots: 6)
    as "with 5 characters and 6 slots the sixth is accepted"
  assert create(store:, account: account, name: "Yz Ab", slots: 6) == NoFreeSlot
    as "lua.CharacterSelection.OnLoadFromCharacter: 2 slots and an entitlement 12 of 4 are 6; the client shows no create entry at 6 of 6, and the server's refusal is account full (9)"
  let assert ForSelect(Listed(six)) =
    ask(store, Select(ListCharacters(account)))
    as "the characters are listed"
  assert list.length(six) == 6 as "nothing was stored for the refused create"
  stop(store)
}

pub fn two_creates_at_once_for_an_account_with_one_slot_make_one_character_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 4)
  let account = insert_account(store, "login-1")
  let answers = process.new_subject()
  list.each(["Ab Cd", "Ef Gh", "Ij Kl", "Mn Op"], fn(name) {
    let _spawned =
      process.spawn(fn() {
        process.send(answers, create(store:, account:, name:, slots: 1))
      })
  })
  let received =
    list.map(character_support.numbers(4), fn(_) {
      let assert Ok(answer) = process.receive(answers, within: 30_000)
        as "every create is answered"
      answer
    })
  assert list.count(received, is_created) == 1
    as "storing-data: the slot count is held by Postgres, in one statement under the account's row lock, so racing creates of one account make one character"
  assert list.count(received, fn(answer) { answer == NoFreeSlot }) == 3
  let assert ForSelect(Listed([_])) =
    ask(store, Select(ListCharacters(account)))
  stop(store)
}

pub fn the_table_refuses_a_look_whose_labels_and_values_differ_in_number_and_a_third_in_bones_beyond_48_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let AccountId(id) = account
  let insert = fn(labels, values, bones) {
    pog.query(
      "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z, look_labels, look_values, bones) values ($1, 'Ab Cd', 1, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0, $2::bigint[], $3::bigint[], $4::bigint[])",
    )
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.array(pog.int, labels))
    |> pog.parameter(pog.array(pog.int, values))
    |> pog.parameter(pog.array(pog.int, bones))
    |> pog.execute(store.pool)
    |> result.map_error(fn(error) {
      let assert pog.ConstraintViolated(constraint:, ..) = error
        as "the table refused with a constraint"
      constraint
    })
    |> result.replace(Nil)
  }
  assert insert([1, 2], [1], []) == Error("character_look_pairs")
    as "a look is label and value pairs"
  assert insert(
      character_support.numbers(28),
      character_support.numbers(28),
      [],
    )
    == Error("character_look_pairs")
    as "opcode.0x25b.counts: the label table allows at most 27"
  assert insert([], [], list.repeat(0, 49))
    == Error("character_bones_at_most_48")
    as "opcode.0x25b.counts: at most 48 bone values"
  assert insert(
      character_support.numbers(27),
      character_support.numbers(27),
      list.repeat(0, 48),
    )
    == Ok(Nil)
    as "27 pairs and 48 bones are the most a request carries"
  stop(store)
}

// ---- the epoch and the save of the player's place ----

/// The epoch a character's load answers with, for a character that exists.
fn epoch_of_load(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
) -> Int {
  let assert ForWorld(CharacterLoaded(session_epoch:, ..)) =
    ask(store, World(LoadCharacter(account, CharacterId(character_id))))
    as "the account has the character"
  store.session_epoch_number(session_epoch)
}

/// Saves the place under the epoch and sequence of a login, with no health to
/// keep.
fn save(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
  epoch epoch: Int,
  sequence sequence: Int,
  place place: start_place.Place,
) -> store.Answer {
  save_keeping(
    store:,
    account:,
    character_id:,
    epoch:,
    sequence:,
    place:,
    health: None,
  )
}

/// Saves the place under the epoch and sequence of a login, with the health. The
/// experience and level it saves with are the stored characters' own level 9 and
/// no experience beyond it: these tests are about the place and the health.
fn save_keeping(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
  epoch epoch: Int,
  sequence sequence: Int,
  place place: start_place.Place,
  health health: Option(Int),
) -> store.Answer {
  save_progress(
    store:,
    account:,
    character_id:,
    epoch:,
    sequence:,
    place:,
    health:,
    experience: 0,
    level: 9,
  )
}

/// Saves the place under the epoch and sequence of a login, with the experience
/// and level the player has made.
fn save_progress(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
  epoch epoch: Int,
  sequence sequence: Int,
  place place: start_place.Place,
  health health: Option(Int),
  experience experience: Int,
  level level: Int,
) -> store.Answer {
  ask(
    store,
    Move(
      SavePlace(
        account_id: account,
        character_id: CharacterId(character_id),
        session_epoch: character_support.epoch(epoch),
        save_sequence: sequence,
        place:,
        health:,
        experience:,
        level:,
        quests: [],
      ),
    ),
  )
}

/// The experience and level the character's next load answers with (which raises
/// the epoch), as a pair.
fn experience_and_level_loaded(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
) -> #(Option(Int), Int) {
  let assert ForWorld(CharacterLoaded(character:, saved_experience:, ..)) =
    ask(store, World(LoadCharacter(account, CharacterId(character_id))))
    as "the account has the character"
  #(saved_experience, character.level)
}

/// The health the character's row holds and the saved health its next load
/// answers with (which raises the epoch), as a pair.
fn health_row_and_load(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
) -> #(Option(Int), Option(Int)) {
  let row = character_support.place_row(pool: store.pool, character_id:)
  let assert ForWorld(CharacterLoaded(saved_health:, ..)) =
    ask(store, World(LoadCharacter(account, CharacterId(character_id))))
    as "the account has the character"
  #(row.health, saved_health)
}

/// A place in World 3460, zone 6009, at x, y, z (each exactly a 32-bit float)
/// facing yaw, pitch, roll.
fn place_facing(
  x x: Float,
  y y: Float,
  z z: Float,
  yaw yaw: Float,
  pitch pitch: Float,
  roll roll: Float,
) -> start_place.Place {
  start_place.turned(
    place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:),
    Facing(yaw:, pitch:, roll:),
  )
}

/// An account with one character that the account's first login holds, and
/// the character's id.
fn one_character(store store: Store) -> #(AccountId, Int) {
  let account = insert_account(store, "login-1")
  let id =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  #(account, id)
}

pub fn a_session_epoch_is_1_or_more_and_only_that_makes_one_test() -> Nil {
  use <- owned_test.run(5000)
  assert store.session_epoch(0) == Error(Nil)
    as "no login is told 0: a load raises the epoch by one from 0 at least"
  assert store.session_epoch(-4) == Error(Nil)
  let assert Ok(epoch) = store.session_epoch(7)
  assert store.session_epoch_number(epoch) == 7
}

pub fn each_load_raises_the_epoch_by_one_and_starts_the_saves_of_its_login_again_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  assert epoch_of_load(store:, account:, character_id: id) == 1
    as "a character that was never loaded is at 0, and the first login raises it to 1"
  let here =
    place_facing(x: 1.5, y: 2.5, z: 3.5, yaw: 0.5, pitch: 0.0, roll: 0.0)
  assert save(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 4,
      place: here,
    )
    == ForMove(PlaceSaved)
  assert character_support.place_row(pool: store.pool, character_id: id).save_sequence
    == 4
  assert epoch_of_load(store:, account:, character_id: id) == 2
    as "the next login raises it again"
  let row = character_support.place_row(pool: store.pool, character_id: id)
  assert row.session_epoch == 2 && row.save_sequence == 0
    as "and its saves are numbered from 1 again, whatever the last login reached"
  assert epoch_of_load(store:, account:, character_id: id) == 3
  stop(store)
}

pub fn a_save_stores_the_place_and_the_facing_and_the_next_load_reads_them_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let _epoch = epoch_of_load(store:, account:, character_id: id)
  let here =
    place_facing(
      x: 4110.7099609375,
      y: -658.6248779296875,
      z: -5145.47998046875,
      yaw: 1.5,
      pitch: -0.25,
      roll: 0.5,
    )
  assert save(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: here,
    )
    == ForMove(PlaceSaved)
    as "the epoch is the login's and the sequence is its first"
  assert character_support.place_row(pool: store.pool, character_id: id)
    == character_support.PlaceRow(
      world_id: 3460,
      world_zone_id: 6009,
      position: #(4110.7099609375, -658.6248779296875, -5145.47998046875),
      rotation: #(1.5, -0.25, 0.5),
      session_epoch: 1,
      save_sequence: 1,
      health: None,
    )
    as "the world, zone, position and facing of the save, in the row, and the login's numbers; a save with no health to keep leaves none"
  let assert ForWorld(CharacterLoaded(character:, ..)) =
    ask(store, World(LoadCharacter(account, CharacterId(id))))
  assert character.place == Some(here)
    as "the next login finds the character where the last one left it, facing the way it faced"
  stop(store)
}

pub fn a_save_naming_an_older_epoch_changes_nothing_and_the_newer_logins_saves_do_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let first =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  let second =
    place_facing(x: 11.0, y: 21.0, z: 31.0, yaw: 1.0, pitch: 0.0, roll: 0.0)
  let _first_login = epoch_of_load(store:, account:, character_id: id)
  let _second_login = epoch_of_load(store:, account:, character_id: id)
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: first,
      health: Some(400),
    )
    == ForMove(NothingSaved)
    as "the first login's epoch is 1 and the character is at 2: a save of an older login changes nothing (opcode.0x36a reason 19: the older connection was taken over)"
  assert character_support.place_row(pool: store.pool, character_id: id).position
    == #(1.5, 2.5, 3.5)
    as "the row still holds the place it was made at"
  assert character_support.place_row(pool: store.pool, character_id: id).health
    == None
    as "and none of the health the older login's save carried"
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 2,
      sequence: 1,
      place: second,
      health: Some(250),
    )
    == ForMove(PlaceSaved)
    as "the newer login's save is written"
  let row = character_support.place_row(pool: store.pool, character_id: id)
  assert row.position == #(11.0, 21.0, 31.0)
  assert row.health == Some(250) as "with its health"
  stop(store)
}

pub fn a_save_that_reaches_the_database_after_a_newer_one_of_its_login_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let older =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  let newer =
    place_facing(x: 11.0, y: 21.0, z: 31.0, yaw: 1.0, pitch: 0.0, roll: 0.0)
  let _login = epoch_of_load(store:, account:, character_id: id)
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 2,
      place: newer,
      health: Some(500),
    )
    == ForMove(PlaceSaved)
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: older,
      health: Some(300),
    )
    == ForMove(NothingSaved)
    as "a save cut short by a stop can still commit after the next one: the sequence it was asked under is older, so it changes nothing"
  let row = character_support.place_row(pool: store.pool, character_id: id)
  assert row.position == #(11.0, 21.0, 31.0)
    as "the place of the newer save stands"
  assert row.health == Some(500)
    as "and so does its health: an older save writes neither"
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 2,
      place: older,
      health: Some(300),
    )
    == ForMove(NothingSaved)
    as "the same sequence twice is no newer, for the place and for the health"
  assert character_support.place_row(pool: store.pool, character_id: id).health
    == Some(500)
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 3,
      place: older,
      health: Some(200),
    )
    == ForMove(PlaceSaved)
    as "a newer one is written"
  let row = character_support.place_row(pool: store.pool, character_id: id)
  assert row.save_sequence == 3
  assert row.health == Some(200)
  stop(store)
}

pub fn a_save_for_a_character_the_account_does_not_have_or_that_does_not_exist_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let other = insert_account(store, "login-2")
  let _login = epoch_of_load(store:, account:, character_id: id)
  let there =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save(
      store:,
      account: other,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: there,
    )
    == ForMove(NothingSaved)
    as "the save names the account too, so a modified client's id of another account's character is never written"
  assert save(
      store:,
      account:,
      character_id: id + 1000,
      epoch: 1,
      sequence: 1,
      place: there,
    )
    == ForMove(NothingSaved)
    as "no such character"
  assert character_support.place_row(pool: store.pool, character_id: id).position
    == #(1.5, 2.5, 3.5)
  stop(store)
}

pub fn the_table_refuses_a_position_a_rotation_or_a_save_sequence_it_cannot_hold_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(_account, id) = one_character(store:)
  let update = fn(set) {
    pog.query("update character set " <> set <> " where character_id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.execute(store.pool)
    |> result.map_error(fn(error) {
      let assert pog.ConstraintViolated(constraint:, ..) = error
        as "the table refused with a constraint"
      constraint
    })
    |> result.replace(Nil)
  }
  list.each(["'Infinity'", "'-Infinity'", "'NaN'"], fn(value) {
    assert update("position_x = " <> value <> "::real")
      == Error("character_position_is_finite")
      as "the client places the player by the saved position, and the server never writes one that is no number"
    assert update("position_z = " <> value <> "::real")
      == Error("character_position_is_finite")
    assert update("rotation_pitch = " <> value <> "::real")
      == Error("character_rotation_is_finite")
  })
  assert update("health = -1") == Error("character_health_is_not_negative")
    as "a saved health is never below 0"
  assert update("health = 0") == Ok(Nil)
    as "0 is a player who left dead (the client's own meaning: health 0 is dead)"
  assert update("health = 1") == Ok(Nil)
    as "the least health a living player has"
  assert update("health = null") == Ok(Nil)
    as "NULL is nothing saved, which a check passes: the character enters alive at full health"
  assert update("save_sequence = -1")
    == Error("character_save_sequence_is_not_negative")
  assert update("position_y = -2048, rotation_yaw = 3.5, save_sequence = 0")
    == Ok(Nil)
    as "any finite place is held"
  stop(store)
}

pub fn the_health_column_is_a_nullable_integer_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let assert Ok(returned) =
    pog.query(
      "select data_type, is_nullable from information_schema.columns where table_name = 'character' and column_name = 'health'",
    )
    |> pog.returning({
      use data_type <- decode.field(0, decode.string)
      use is_nullable <- decode.field(1, decode.string)
      decode.success(#(data_type, is_nullable))
    })
    |> pog.execute(store.pool)
    as "the catalog reads"
  assert returned.rows == [#("integer", "YES")]
    as "NULL is nothing saved, so existing rows need no backfill"
  stop(store)
}

pub fn a_save_writes_the_health_with_the_place_and_the_next_load_reads_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let here =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert health_row_and_load(store:, account:, character_id: id)
    == #(None, None)
    as "a character never saved has no health: it enters at full health"
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: here,
      health: Some(512),
    )
    == ForMove(PlaceSaved)
  assert health_row_and_load(store:, account:, character_id: id)
    == #(Some(512), Some(512))
    as "the save wrote the health with the place, and the next login's load answers it"
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 2,
      sequence: 1,
      place: here,
      health: Some(0),
    )
    == ForMove(PlaceSaved)
  assert health_row_and_load(store:, account:, character_id: id)
    == #(Some(0), Some(0))
    as "a dead player's save writes 0 with the place, and the next login's load answers 0, which enters dead"
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 3,
      sequence: 1,
      place: here,
      health: None,
    )
    == ForMove(PlaceSaved)
  assert health_row_and_load(store:, account:, character_id: id)
    == #(None, None)
    as "a save that asks to keep no health clears the saved one: nothing saved enters alive at full health"
  stop(store)
}

pub fn a_save_with_a_health_the_table_refuses_is_answered_health_refused_and_saves_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let _login = epoch_of_load(store:, account:, character_id: id)
  let there =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: there,
      health: Some(-1),
    )
    == ForMove(HealthRefused)
    as "character_health_is_not_negative refused a -1 planted straight into the query: its own answer, not the place's, and the worker does not crash"
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: there,
      health: Some(-5),
    )
    == ForMove(HealthRefused)
  let row = character_support.place_row(pool: store.pool, character_id: id)
  assert row.position == #(1.5, 2.5, 3.5) && row.health == None
    as "the statement is one: the place beside the refused health was not written either"
  assert row.save_sequence == 0 as "and the refused save took no sequence"
  assert save_keeping(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: there,
      health: Some(1),
    )
    == ForMove(PlaceSaved)
    as "the store answers the next save"
  stop(store)
}

pub fn a_save_keeps_the_experience_and_level_for_the_next_load_and_a_create_writes_its_xp_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(CharacterId(created)) =
    create(store:, account:, name: "Ab Cd", slots: 2)
    as "the account has a free slot"
  assert experience_and_level_loaded(store:, account:, character_id: created)
    == #(Some(1710), 3)
    as "a create writes the experience of its level 3 row (xp 1710) and its level, which the first load answers"
  let there =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save_progress(
      store:,
      account:,
      character_id: created,
      epoch: 1,
      sequence: 1,
      place: there,
      health: None,
      experience: 1840,
      level: 4,
    )
    == ForMove(PlaceSaved)
  assert experience_and_level_loaded(store:, account:, character_id: created)
    == #(Some(1840), 4)
    as "the save's experience and level, which the next login enters with"
  stop(store)
}

pub fn a_save_with_an_experience_the_table_refuses_is_answered_experience_refused_and_saves_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let _login = epoch_of_load(store:, account:, character_id: id)
  let there =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save_progress(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: there,
      health: None,
      experience: -1,
      level: 4,
    )
    == ForMove(ExperienceRefused)
    as "character_experience_is_not_negative refused a -1 planted straight into the query: its own answer, and the worker does not crash"
  let row = character_support.place_row(pool: store.pool, character_id: id)
  assert row.position == #(1.5, 2.5, 3.5) && row.save_sequence == 0
    as "the statement is one: neither the place nor the sequence beside the refused experience was written"
  assert experience_and_level_loaded(store:, account:, character_id: id)
    == #(None, 9)
    as "and the level beside it was not written either"
  stop(store)
}

pub fn a_save_the_database_refuses_for_a_check_is_answered_place_refused_with_the_constraints_name_and_the_store_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let _login = epoch_of_load(store:, account:, character_id: id)
  execute(
    store.pool,
    "alter table character add constraint test_refuses_far_x check (position_x < 1000), add constraint test_refuses_far_y check (position_y < 1000)",
  )
  let far_x =
    place_facing(x: 2000.0, y: 0.0, z: 0.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: far_x,
    )
    == ForMove(PlaceRefused(constraint: "test_refuses_far_x"))
    as "a constraint the database holds refused the place: the asker is told which, and the worker does not crash"
  let far_y =
    place_facing(x: 0.0, y: 2000.0, z: 0.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: far_y,
    )
    == ForMove(PlaceRefused(constraint: "test_refuses_far_y"))
    as "another constraint is named as itself"
  assert character_support.place_row(pool: store.pool, character_id: id).position
    == #(1.5, 2.5, 3.5)
  let near =
    place_facing(x: 5.0, y: 0.0, z: 0.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      place: near,
    )
    == ForMove(PlaceSaved)
    as "the store answers the next save, and the refused ones took no sequence"
  stop(store)
}

pub fn a_create_with_a_name_that_breaks_rule_0_is_name_breaks_rule_and_nothing_is_stored_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  list.each(["Abcd", "Ab  Cd", "Ab1 Cd", " Ab Cd", ""], fn(name) {
    assert create(store:, account:, name:, slots: 2) == NameBreaksRule
      as "lua.Character.OnCreateCharacterFailed: 10, the name's length; CheckTextRule 0x1403e1170 refuses it, and the table's check is the one copy of the rule"
  })
  assert ask(store, Select(ListCharacters(account))) == ForSelect(Listed([]))
    as "nothing was stored for a refused create"
  let assert CharacterCreated(_) =
    create(store:, account:, name: "Ab Cd", slots: 2)
    as "the store answers the next create, so the refusal did not crash its worker"
  stop(store)
}

pub fn a_rename_to_a_name_that_breaks_rule_0_is_new_name_breaks_rule_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let zed =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Zed Qu",
      class_id: 4,
      path: 2,
    )
  character_support.mark_for_rename(pool: store.pool, name: "Zed Qu")
  list.each(["Abcd", "Ab  Cd", "Ab1 Cd", " Ab Cd"], fn(name) {
    assert renamed(store:, account: account, character_id: zed, name:)
      == NewNameBreaksRule
      as "lua.CharacterSelection.OnCharacterRenameResult: 15, the name's length; CheckTextRule 0x1403e1170 refuses it, and the table's check is the one copy of the rule"
  })
  assert names_listed(store, account) == ["Zed Qu"]
  assert naming_of(store, account) == [NeedsRename]
    as "the refused rename left the mark, so the player can pick another name"
  assert renamed(store:, account: account, character_id: zed, name: "Ab Cd")
    == CharacterRenamed("Ab Cd")
    as "and another name is taken"
  stop(store)
}

pub fn a_create_for_an_account_that_does_not_exist_is_create_for_no_such_account_and_the_store_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  assert create(
      store:,
      account: AccountId(account_id_nobody_has),
      name: "Ab Cd",
      slots: 2,
    )
    == CreateForNoSuchAccount
    as "the lock of the account's row finds no row, so no character is inserted to break the foreign key"
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(_) =
    create(store:, account:, name: "Ab Cd", slots: 2)
    as "the store answers the next create: the worker did not crash"
  stop(store)
}

pub fn every_constraint_the_worker_maps_exists_in_the_schema_by_that_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  assert worker.mapped_constraints()
    == [
      "character_name_unique",
      "character_name_follows_rule_0",
      "character_health_is_not_negative",
      "character_experience_is_not_negative",
      "character_quest_id_fits_15_bits",
      "character_quest_state_is_known",
      "character_quest_completed_has_a_time",
      "character_quest_active_has_its_entry",
      "character_quest_done_mask_fits_six_objectives",
      "character_quest_progress_fits_six_objectives",
      "character_quest_progress_is_not_negative",
      "character_quest_timers_match_progress",
      "character_quest_times_are_not_negative",
      "character_quest_placeholder_is_not_negative",
    ]
    as "the refusals the worker answers for: a name taken, a name that breaks rule 0, a health below 0, an experience below 0 and each check of a quest row"
  list.each(worker.mapped_constraints(), fn(name) {
    let assert Ok(returned) =
      pog.query(
        "select count(*)::int from (select conname::text as name from pg_constraint union all select c.relname::text from pg_class c where c.relkind = 'i') as names where name = $1",
      )
      |> pog.parameter(pog.text(name))
      |> pog.returning(decode.at([0], decode.int))
      |> pog.execute(store.pool)
      as "the catalogue was read"
    assert returned.rows == [1]
      as { "the schema has one constraint or unique index named " <> name }
  })
  stop(store)
}

pub fn the_schema_names_its_constraints_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let named = fn(table, constraint) {
    let assert Ok(returned) =
      pog.query(
        "select count(*)::int from pg_constraint where conrelid = $1::text::regclass and conname = $2",
      )
      |> pog.parameter(pog.text(table))
      |> pog.parameter(pog.text(constraint))
      |> pog.returning(decode.at([0], decode.int))
      |> pog.execute(store.pool)
      as "the catalogue was read"
    assert returned.rows == [1]
      as { table <> " has the constraint " <> constraint }
  }
  named("account", "account_login_name_is_unique")
  named("account", "account_game_account_id_is_unique")
  named("account", "account_login_name_is_not_empty")
  named("account", "account_srp_salt_is_not_empty")
  named("account", "account_srp_verifier_is_not_empty")
  named("character", "character_session_epoch_is_not_negative")
  named("character", "character_account_is_an_account")
  named("spawn_stat", "spawn_stat_spawn_is_a_spawn")
  stop(store)
}

pub fn the_table_refuses_an_empty_login_name_and_a_second_account_with_one_by_their_names_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let attempt = fn(login_name) {
    case
      pog.query(
        "insert into account (login_name, srp_salt, srp_verifier, game_account_id) values ($1, '\\x01', '\\x02', gen_random_uuid())",
      )
      |> pog.parameter(pog.text(login_name))
      |> pog.execute(store.pool)
    {
      Ok(_) -> "accepted"
      Error(pog.ConstraintViolated(constraint:, ..)) -> constraint
      Error(error) -> worker.describe_query_error(error)
    }
  }
  assert attempt("") == "account_login_name_is_not_empty"
    as "an account with no login name has none to log in by"
  assert attempt("login-1") == "accepted"
  assert attempt("login-1") == "account_login_name_is_unique"
    as "a login name is held by one account"
  stop(store)
}

pub fn a_save_with_the_database_pool_not_running_is_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  let pool = pog.named_connection(process.new_name("absent_pool"))
  let name = process.new_name("store")
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(worker.supervised(name:, pool:))
    |> supervisor.start
    as "the store started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  let store = Store(tree: started.pid, pool:, name:)
  let there =
    place_facing(x: 10.0, y: 20.0, z: 30.0, yaw: 0.0, pitch: 0.0, roll: 0.0)
  assert save(
      store:,
      account: AccountId(1),
      character_id: 1,
      epoch: 1,
      sequence: 1,
      place: there,
    )
    == Unavailable
    as "the pool is not running, so the save cannot reach the database, and the place saved before it stands"
  stop(store)
}

fn is_created(answer: store.CreateAnswer) -> Bool {
  case answer {
    CharacterCreated(..) -> True
    NameTaken | NameBreaksRule | NoFreeSlot | CreateForNoSuchAccount -> False
  }
}

// ---- helpers ----

/// An account id no test account has.
const account_id_nobody_has = 999_999

fn insert_account(store: Store, login_name: String) -> AccountId {
  AccountId(login_support.insert_account(
    pool: store.pool,
    login_name:,
    salt: <<1>>,
    verifier: <<2>>,
    game_account_id: game_account_id_of(login_name),
  ))
}

/// A game account id for each login name, so two accounts differ.
fn game_account_id_of(login_name: String) -> guid.Guid {
  let assert Ok(game_account_id) = case login_name {
    "login-1" -> guid.from_text("01234567-89ab-cdef-0123-456789abcdef")
    _ -> guid.from_text("76543210-89ab-cdef-0123-456789abcdef")
  }
    as "the text is a GUID"
  game_account_id
}

/// A running pool and store: the tree they run in, the pool as a connection
/// for queries and the store's name.
type Store {
  Store(
    tree: process.Pid,
    pool: pog.Connection,
    name: process.Name(factory_supervisor.Message(worker.Job, Nil)),
  )
}

/// A pool of `pool_size` connections to a migrated database of its own, and the
/// store on it, started once the pool has its connections.
fn start_store(pool_size pool_size: Int) -> Store {
  let shared = database_support.shared()
  start_store_in(
    database: database_support.new_database(on: shared),
    pool_size:,
  )
}

/// A pool of `pool_size` connections to `database`, a migrated database, and
/// the store on it, started once the pool has its connections.
fn start_store_in(
  database database: String,
  pool_size pool_size: Int,
) -> Store {
  let config =
    database_support.config(
      for: database_support.shared().settings,
      database:,
      pool_name: process.new_name("account_pool"),
      pool_size:,
    )
  let store = start_store_on(config)
  readiness_support.await(tree: store.tree, store: store.name)
  store
}

/// The pool `config` describes and the store on it, as children of a tree.
fn start_store_on(config: pog.Config) -> Store {
  let name = process.new_name("store")
  let pool = pog.named_connection(config.pool_name)
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(pog.supervised(config))
    |> supervisor.add(worker.supervised(name:, pool:))
    |> supervisor.start
    as "the pool and the store started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  Store(tree: started.pid, pool:, name:)
}

fn stop(store: Store) -> Nil {
  let _reason = ask_support.stop_tree(store.tree)
  Nil
}

/// Starts a listener whose connections ask this store, and report each worker
/// they ask to `sent`.
fn start_asker(
  store: Store,
  sent: fn(service.Sent) -> Nil,
) -> ask_support.Server {
  ask_support.start(
    rule: asking_rule.rule(),
    directory: ask_support.directory(
      gate: process.new_name("gate"),
      store: Some(store.name),
      sent:,
    ),
    shutdown_ms: 1000,
    with: fn(builder) { builder },
  )
}

/// Asks the store and waits for the answer.
fn ask(store: Store, request: store.Request) -> store.Answer {
  let #(sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      worker.ask(store.name, request, reply)
    })
  let assert ToWorker(_) = sent as "the store started a worker"
  answer
}

/// The GUID of the text the tests insert as an account's game account id.
fn a_game_account_id() -> guid.Guid {
  let assert Ok(game_account_id) =
    guid.from_text("01234567-89ab-cdef-0123-456789abcdef")
    as "the text is a GUID"
  game_account_id
}

fn execute(pool: pog.Connection, sql: String) -> Nil {
  let assert Ok(_) = pog.query(sql) |> pog.execute(pool) as "the statement ran"
  Nil
}

/// A lock on the account table held by a transaction of another connection.
type Lock {
  Lock(release: process.Subject(Nil), committed: process.Subject(Nil))
}

/// Locks the account table in a transaction of another connection, until
/// `release_lock`. Returns once the lock is held.
fn lock_table(pool: pog.Connection) -> Lock {
  let locked = process.new_subject()
  let committed = process.new_subject()
  let _locker =
    process.spawn(fn() {
      let release = process.new_subject()
      let assert Ok(Nil) =
        pog.transaction(pool, fn(connection) {
          let assert Ok(_) =
            pog.query("lock table account in access exclusive mode")
            |> pog.execute(connection)
            as "the table was locked"
          process.send(locked, release)
          let assert Ok(Nil) = process.receive(release, within: 30_000)
            as "the test released the lock"
          Ok(Nil)
        })
        as "the locking transaction ran"
      process.send(committed, Nil)
    })
  let assert Ok(release) =
    process.receive(locked, within: ask_support.event_wait_ms)
    as "the table is locked"
  Lock(release:, committed:)
}

/// Releases the lock and returns once its transaction has committed, so the
/// pool the test stops next has no commit still on the wire.
fn release_lock(lock: Lock) -> Nil {
  process.send(lock.release, Nil)
  let assert Ok(Nil) =
    process.receive(lock.committed, within: ask_support.event_wait_ms)
    as "the locking transaction committed"
  Nil
}

// ---- held items ----

/// The items the store loads for the character, in the order it sends them.
fn held_by(
  store store: Store,
  account account: AccountId,
  character_id character_id: store.CharacterId,
) -> List(store.HeldItem) {
  let assert ForWorld(CharacterLoaded(items:, ..)) =
    ask(store, World(LoadCharacter(account, character_id)))
    as "the account's character loads"
  items
}

/// An item as the create gave it: what a row holds besides its guid.
fn without_guid(item: store.HeldItem) -> store.NewItem {
  NewItem(
    item2_id: item.item2_id,
    location: item.location,
    bag_index: item.bag_index,
    stack_count: item.stack_count,
  )
}

/// How many item rows the table holds, for every character.
fn item_rows(store store: Store) -> Int {
  let assert Ok(pog.Returned(rows: [count], ..)) =
    pog.query("select count(*)::int from character_item")
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(store.pool)
    as "the item table was counted"
  count
}

/// The table refused an item row, by the name of the check that did.
type ItemRefused {
  ItemRefused(constraint: String)
}

/// Inserts one item row straight into the table, answering the guid it was given
/// or the name of the check that refused it.
fn put_item(
  store store: Store,
  character_id character_id: store.CharacterId,
  item2_id item2_id: Int,
  location location: Int,
  bag_index bag_index: Int,
  stack_count stack_count: Int,
) -> Result(Int, ItemRefused) {
  let CharacterId(number) = character_id
  pog.query(
    "insert into character_item (character_id, item2_id, location, bag_index, stack_count) values ($1, $2, $3::int, $4, $5) returning item_guid",
  )
  |> pog.parameter(pog.int(number))
  |> pog.parameter(pog.int(item2_id))
  |> pog.parameter(pog.int(location))
  |> pog.parameter(pog.int(bag_index))
  |> pog.parameter(pog.int(stack_count))
  |> pog.returning(decode.at([0], decode.int))
  |> pog.execute(store.pool)
  |> result.map(fn(returned) {
    let assert [guid] = returned.rows as "one row was inserted"
    guid
  })
  |> result.map_error(fn(error) {
    let assert pog.ConstraintViolated(constraint:, ..) = error
      as "the table refused with a constraint"
    ItemRefused(constraint:)
  })
}

pub fn a_create_stores_the_novice_set_with_new_guids_and_the_load_returns_them_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(character_id: first) =
    create_holding(
      store:,
      account:,
      name: "Ab Cd",
      slots: 2,
      items: character_support.row_466_items(),
    )
    as "a create with the Novice set is stored"
  let assert CharacterCreated(character_id: second) =
    create_holding(
      store:,
      account:,
      name: "Ef Gh",
      slots: 2,
      items: character_support.row_466_items(),
    )
    as "a second character gets the same set"
  let first_items = held_by(store:, account:, character_id: first)
  let second_items = held_by(store:, account:, character_id: second)
  assert list.map(first_items, without_guid)
    == character_support.row_466_items()
    as "opcode.0x111.equipped_set: seven items at location 0 in the bag indexes 0, 1, 3, 4, 5, 15 and 16, as the create gave them, in the order of their places"
  assert list.map(second_items, without_guid)
    == character_support.row_466_items()
  let guids =
    list.map(list.append(first_items, second_items), fn(item) { item.item_guid })
  assert list.all(guids, fn(guid) { guid != 0 })
    as "opcode.0x111.equipped_set: a held item's guid is never 0"
  assert list.length(list.unique(guids)) == 14
    as "opcode.0x111.guid: every item has a guid of its own, and the second character's differ from the first's"
  stop(store)
}

pub fn a_refused_create_stores_no_items_and_a_delete_removes_the_characters_items_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let assert CharacterCreated(character_id: kept) =
    create_holding(
      store:,
      account:,
      name: "Ab Cd",
      slots: 1,
      items: character_support.row_466_items(),
    )
    as "the first create is stored"
  assert item_rows(store:) == 7
  assert create_holding(
      store:,
      account:,
      name: "Ef Gh",
      slots: 1,
      items: character_support.row_466_items(),
    )
    == NoFreeSlot
    as "lua.CharacterSelection.OnLoadFromCharacter: an account holds its slots only, so a create past them is refused"
  assert create_holding(
      store:,
      account: other,
      name: "ab cd",
      slots: 1,
      items: character_support.row_466_items(),
    )
    == NameTaken
    as "a name is unique ignoring case"
  assert item_rows(store:) == 7
    as "a refused create stores its character's items with the character or not at all: the table holds only the first character's seven"
  let assert CharacterCreated(character_id: theirs) =
    create_holding(
      store:,
      account: other,
      name: "Ij Kl",
      slots: 1,
      items: character_support.row_466_items(),
    )
    as "another account's create is stored"
  assert item_rows(store:) == 14
  let CharacterId(kept_number) = kept
  assert deleted(store:, account:, character_id: kept_number)
    == CharacterDeleted
  assert item_rows(store:) == 7
    as "a delete removes the character's seven rows with it (character_item_character_exists, on delete cascade)"
  assert list.length(held_by(store:, account: other, character_id: theirs)) == 7
    as "and the other character's rows stay"
  stop(store)
}

pub fn the_table_refuses_a_second_item_in_one_place_a_place_the_client_has_not_and_a_stack_of_0_by_their_names_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(character_id:) =
    create(store:, account:, name: "Ab Cd", slots: 1)
    as "a character that holds nothing yet"
  let put = fn(item2_id, location, bag_index, stack_count) {
    result.replace(
      put_item(
        store:,
        character_id:,
        item2_id:,
        location:,
        bag_index:,
        stack_count:,
      ),
      Nil,
    )
  }
  assert put(81_359, 0, 3, 1) == Ok(Nil)
    as "an item in a free place of the equipped slots is stored"
  assert put(81_344, 0, 3, 1)
    == Error(ItemRefused("character_item_one_per_slot"))
    as "a place holds one item"
  assert put(81_344, 1, 3, 1) == Ok(Nil)
    as "the same index of another location is another place"
  assert put(81_344, 3, 0, 1)
    == Error(ItemRefused("character_item_location_is_held_by_the_client"))
    as "the client holds items at locations 0 (equipped), 1 (inventory) and 2 (bank)"
  assert put(81_344, 0, 30, 1) == Ok(Nil)
    as "the client's move check refuses only equipped indexes above 30"
  assert put(81_344, 0, 31, 1)
    == Error(ItemRefused("character_item_bag_index_is_a_slot_of_its_location"))
    as "the equipped slots end at index 30 (opcode.0x111.shared_item_unnamed)"
  assert put(81_344, 1, 95, 1) == Ok(Nil)
  assert put(81_344, 1, 96, 1)
    == Error(ItemRefused("character_item_bag_index_is_a_slot_of_its_location"))
    as "the inventory's 96 slots end at index 95"
  assert put(81_344, 2, 231, 1) == Ok(Nil)
  assert put(81_344, 2, 232, 1)
    == Error(ItemRefused("character_item_bag_index_is_a_slot_of_its_location"))
    as "the bank's 232 slots end at index 231"
  assert put(81_344, 1, 4, 0)
    == Error(ItemRefused("character_item_stack_count_is_positive"))
    as "the client reads a stack of 0 as 1, so only 1 or more is stored (opcode.0x111.shared_item_unnamed)"
  assert item_rows(store:) == 5 as "only the five accepted rows are stored"
  stop(store)
}

pub fn an_item_keeps_its_guid_when_its_place_changes_and_two_items_swap_places_in_one_update_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(character_id:) =
    create_holding(
      store:,
      account:,
      name: "Ab Cd",
      slots: 1,
      items: character_support.row_466_items(),
    )
    as "a character holding the Novice set"
  let CharacterId(number) = character_id
  let update = fn(sql) {
    let assert Ok(_) =
      pog.query(sql)
      |> pog.parameter(pog.int(number))
      |> pog.execute(store.pool)
      as "the update was accepted"
    Nil
  }
  let before = held_by(store:, account:, character_id:)
  let assert [chest, legs, shoulder, feet, hands, shield, weapon] = before
    as "the Novice set is seven items"
  update(
    "update character_item set location = 1, bag_index = 2 where character_id = $1 and location = 0 and bag_index = 5",
  )
  assert held_by(store:, account:, character_id:)
    == [
      chest,
      legs,
      shoulder,
      feet,
      shield,
      weapon,
      HeldItem(..hands, location: 1, bag_index: 2),
    ]
    as "opcode.0x111.guid: an item moved to another place keeps its guid, its item and its stack"
  update(
    "update character_item set bag_index = case bag_index when 0 then 1 else 0 end where character_id = $1 and location = 0 and bag_index in (0, 1)",
  )
  assert held_by(store:, account:, character_id:)
    == [
      HeldItem(..legs, bag_index: 0),
      HeldItem(..chest, bag_index: 1),
      shoulder,
      feet,
      shield,
      weapon,
      HeldItem(..hands, location: 1, bag_index: 2),
    ]
    as "one update swaps two items' places, each keeping its guid (a plain unique key would refuse it row by row)"
  let assert Ok(made) =
    put_item(
      store:,
      character_id:,
      item2_id: 81_380,
      location: 0,
      bag_index: 5,
      stack_count: 1,
    )
    as "the place the hands left is free"
  assert !list.contains(list.map(before, fn(item) { item.item_guid }), made)
    as "opcode.0x111.guid: a guid is never made again, so an item that takes a freed place does not take the guid of the item that left it"
  stop(store)
}

// ---- moving held items ----

/// The store's answer to the moves of a character's items under a login's epoch.
fn moved(
  store store: Store,
  account account: AccountId,
  character_id character_id: store.CharacterId,
  epoch epoch: Int,
  moves moves: List(store.ItemMove),
) -> store.Answer {
  ask(
    store,
    Items(MoveItems(
      account_id: account,
      character_id:,
      session_epoch: character_support.epoch(epoch),
      moves:,
    )),
  )
}

pub fn a_moved_and_a_swapped_item_are_where_the_next_login_finds_them_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(character_id:) =
    create_holding(
      store:,
      account:,
      name: "Ab Cd",
      slots: 1,
      items: character_support.row_466_items(),
    )
    as "a character holding the Novice set"
  let CharacterId(number) = character_id
  let assert [chest, legs, shoulder, feet, hands, shield, weapon] =
    held_by(store:, account:, character_id:)
    as "the Novice set is seven items"
  let epoch = epoch_of_load(store:, account:, character_id: number)
  assert moved(store:, account:, character_id:, epoch:, moves: [
      ItemMove(
        item_guid: hands.item_guid,
        from: ItemPlace(location: 0, bag_index: 5),
        to: ItemPlace(location: 1, bag_index: 2),
      ),
    ])
    == ForItems(ItemsMoved)
    as "an unequip to a free inventory slot is stored"
  assert moved(store:, account:, character_id:, epoch:, moves: [
      ItemMove(
        item_guid: chest.item_guid,
        from: ItemPlace(location: 0, bag_index: 0),
        to: ItemPlace(location: 1, bag_index: 2),
      ),
      ItemMove(
        item_guid: hands.item_guid,
        from: ItemPlace(location: 1, bag_index: 2),
        to: ItemPlace(location: 0, bag_index: 0),
      ),
    ])
    == ForItems(ItemsMoved)
    as "migration 0019's unique key is deferrable and checked at the end of the statement, so the equipped chest piece and the inventory item trade places in one update"
  assert held_by(store:, account:, character_id:)
    == [
      HeldItem(..hands, location: 0, bag_index: 0),
      legs,
      shoulder,
      feet,
      shield,
      weapon,
      HeldItem(..chest, location: 1, bag_index: 2),
    ]
    as "opcode.0x111.guid: each item is at its new place with the guid, item and stack it had"
  stop(store)
}

pub fn a_move_moves_every_item_or_none_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let other = insert_account(store, "login-2")
  let assert CharacterCreated(character_id:) =
    create_holding(
      store:,
      account:,
      name: "Ab Cd",
      slots: 1,
      items: character_support.row_466_items(),
    )
    as "a character holding the Novice set"
  let CharacterId(number) = character_id
  let before = held_by(store:, account:, character_id:)
  let assert [chest, _, _, _, hands, ..] = before
    as "the Novice set is seven items"
  let chest_to_inventory =
    ItemMove(
      item_guid: chest.item_guid,
      from: ItemPlace(location: 0, bag_index: 0),
      to: ItemPlace(location: 1, bag_index: 2),
    )
  let stale = epoch_of_load(store:, account:, character_id: number)
  let current = epoch_of_load(store:, account:, character_id: number)
  assert current > stale as "a later login raised the epoch"
  assert moved(store:, account:, character_id:, epoch: stale, moves: [
      chest_to_inventory,
    ])
    == ForItems(NothingMoved)
    as "a later login holds the character, so the earlier login's move is dropped (the storing-data fencing rule)"
  assert moved(store:, account:, character_id:, epoch: current, moves: [
      chest_to_inventory,
      ItemMove(
        item_guid: hands.item_guid,
        from: ItemPlace(location: 1, bag_index: 9),
        to: ItemPlace(location: 0, bag_index: 0),
      ),
    ])
    == ForItems(NothingMoved)
    as "a swap with one item not at its old place moves neither item"
  assert moved(store:, account: other, character_id:, epoch: current, moves: [
      chest_to_inventory,
    ])
    == ForItems(NothingMoved)
    as "another account moves nothing of this character's"
  assert moved(store:, account:, character_id:, epoch: current, moves: [
      ItemMove(
        item_guid: chest.item_guid,
        from: ItemPlace(location: 0, bag_index: 0),
        to: ItemPlace(location: 0, bag_index: 31),
      ),
    ])
    == ForItems(MoveRefused(
      constraint: "character_item_bag_index_is_a_slot_of_its_location",
    ))
    as "the equipped slots end at index 30"
  assert moved(store:, account:, character_id:, epoch: current, moves: [
      chest_to_inventory,
      ItemMove(
        item_guid: hands.item_guid,
        from: ItemPlace(location: 0, bag_index: 5),
        to: ItemPlace(location: 1, bag_index: 2),
      ),
    ])
    == ForItems(MoveRefused(constraint: "character_item_one_per_slot"))
    as "a place holds one item"
  assert held_by(store:, account:, character_id:) == before
    as "every move that did not happen left every item where it was"
  stop(store)
}

// ---- the quest log ----

/// A quest the character completed, at Unix seconds 1_700_000_000.
fn completed_quest(quest_id: Int) -> QuestRow {
  QuestRow(quest_id:, state: 3, completed_at: Some(1_700_000_000), active: None)
}

/// A quest the character botched: a state of the client's second list, with no
/// active entry.
fn botched_quest(quest_id: Int) -> QuestRow {
  QuestRow(quest_id:, state: 4, completed_at: None, active: None)
}

/// A quest the character has accepted, with the entry the client's active list
/// carries: a placeholder objective, tracked, objectives 1 and 3 done, three
/// progress values and a timer for each.
fn accepted_quest(quest_id: Int) -> QuestRow {
  QuestRow(
    quest_id:,
    state: 1,
    completed_at: None,
    active: Some(accepted_entry()),
  )
}

fn accepted_entry() -> ActiveQuest {
  ActiveQuest(
    placeholder_objective_id: 4321,
    tracked: True,
    done_mask: 5,
    progress: [3, 0, 1],
    quest_ms_left: 90_000,
    objective_ms_left: [0, 60_000, 0],
  )
}

/// Saves the place under the epoch and sequence of a login with the whole quest
/// log, and the health left unsaved.
fn save_log(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
  epoch epoch: Int,
  sequence sequence: Int,
  quests quests: List(QuestRow),
) -> store.Answer {
  ask(
    store,
    Move(SavePlace(
      account_id: account,
      character_id: CharacterId(character_id),
      session_epoch: character_support.epoch(epoch),
      save_sequence: sequence,
      place: place_facing(
        x: 10.0,
        y: 20.0,
        z: 30.0,
        yaw: 0.0,
        pitch: 0.0,
        roll: 0.0,
      ),
      health: None,
      experience: 0,
      level: 1,
      quests:,
    )),
  )
}

/// The quest log a load answers with, which raises the epoch.
fn quests_of_load(
  store store: Store,
  account account: AccountId,
  character_id character_id: Int,
) -> List(QuestRow) {
  let assert ForWorld(CharacterLoaded(quests:, ..)) =
    ask(store, World(LoadCharacter(account, CharacterId(character_id))))
    as "the account has the character"
  quests
}

/// The quest ids and states the table holds for the character, read straight
/// from the database, in quest id order.
fn quest_states(
  store store: Store,
  character_id character_id: Int,
) -> List(#(Int, Int)) {
  let assert Ok(returned) =
    pog.query(
      "select quest_id, state::int from character_quest where character_id = $1 order by quest_id",
    )
    |> pog.parameter(pog.int(character_id))
    |> pog.returning({
      use quest_id <- decode.field(0, decode.int)
      use state <- decode.field(1, decode.int)
      decode.success(#(quest_id, state))
    })
    |> pog.execute(store.pool)
    as "the quest rows read"
  returned.rows
}

pub fn a_save_writes_the_quest_log_with_the_place_and_the_next_load_reads_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  assert quests_of_load(store:, account:, character_id: id) == []
    as "a character never saved has an empty quest log"
  let log = [completed_quest(1001), botched_quest(1002), accepted_quest(1003)]
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      quests: log,
    )
    == ForMove(PlaceSaved)
  assert quests_of_load(store:, account:, character_id: id) == log
    as "opcode.0x35f: a completed quest keeps its time and an active one its placeholder, tracked flag, done mask, progress and the time left of the quest and of each objective, in quest id order"
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 2,
      sequence: 1,
      quests: [completed_quest(1001), accepted_quest(1003)],
    )
    == ForMove(PlaceSaved)
  assert quests_of_load(store:, account:, character_id: id)
    == [completed_quest(1001), accepted_quest(1003)]
    as "the log is the whole log: a save without the botched quest removes its row"
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 3,
      sequence: 1,
      quests: [completed_quest(1001), completed_quest(1003)],
    )
    == ForMove(PlaceSaved)
  assert quests_of_load(store:, account:, character_id: id)
    == [completed_quest(1001), completed_quest(1003)]
    as "an active quest that was completed is rewritten, its active columns cleared (a completed quest is in the completed list only, opcode.0x35f.adds_not_replaces)"
  stop(store)
}

pub fn a_quest_log_save_naming_an_older_epoch_or_sequence_changes_no_quest_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 4)
  let #(account, id) = one_character(store:)
  let _first_login = epoch_of_load(store:, account:, character_id: id)
  let _second_login = epoch_of_load(store:, account:, character_id: id)
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 2,
      sequence: 1,
      quests: [completed_quest(1001), botched_quest(1002)],
    )
    == ForMove(PlaceSaved)
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 5,
      quests: [accepted_quest(1003)],
    )
    == ForMove(NothingSaved)
    as "the first login's epoch is 1 and the character is at 2: its save changes nothing, neither the place nor any quest row"
  assert quest_states(store:, character_id: id) == [#(1001, 3), #(1002, 4)]
    as "every quest row is as the newer login wrote it: none added, none deleted"
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 2,
      sequence: 3,
      quests: [
        completed_quest(1001),
        botched_quest(1002),
        accepted_quest(1003),
      ],
    )
    == ForMove(PlaceSaved)
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 2,
      sequence: 2,
      quests: [],
    )
    == ForMove(NothingSaved)
    as "a save of this login older than the last stored one changes nothing, for the quest rows too"
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 2,
      sequence: 3,
      quests: [],
    )
    == ForMove(NothingSaved)
    as "the same sequence twice is no newer"
  assert quest_states(store:, character_id: id)
    == [#(1001, 3), #(1002, 4), #(1003, 1)]
    as "an older or repeated save deleted no quest row"
  // The save of the sequence 4 is still open on another connection, which holds
  // the character's row, when the save of the sequence 5 starts: the later save,
  // which drops the accepted quest, must not leave the quest the earlier one wrote
  // (a statement takes its snapshot before it waits for a row lock).
  let earlier = hold_an_earlier_save(store:, character_id: id)
  let later = process.new_subject()
  let _later_save =
    process.spawn(fn() {
      process.send(
        later,
        save_log(
          store:,
          account:,
          character_id: id,
          epoch: 2,
          sequence: 5,
          quests: [completed_quest(1001), botched_quest(1002)],
        ),
      )
    })
  await_a_statement_waiting_for_a_lock(store:)
  release_earlier_save(earlier)
  let assert Ok(answered) = process.receive(later, within: 30_000)
    as "the later save is answered once the earlier one commits"
  assert answered == ForMove(PlaceSaved)
  assert quest_states(store:, character_id: id) == [#(1001, 3), #(1002, 4)]
    as "two saves of one character run one after another: the later log, which dropped the quest, is the whole log"
  stop(store)
}

/// A save of the character that is still open: another connection's transaction
/// that has written the character's row and a quest row of the sequence 4, and
/// holds the row's lock until `release_earlier_save`.
type EarlierSave {
  EarlierSave(release: process.Subject(Nil), committed: process.Subject(Nil))
}

/// Opens the earlier save and returns once it holds the character's row.
fn hold_an_earlier_save(
  store store: Store,
  character_id character_id: Int,
) -> EarlierSave {
  let locked = process.new_subject()
  let committed = process.new_subject()
  let _holder =
    process.spawn(fn() {
      let release = process.new_subject()
      let assert Ok(Nil) =
        pog.transaction(store.pool, fn(connection) {
          let assert Ok(_) =
            pog.query(
              "update character set save_sequence = 4 where character_id = $1",
            )
            |> pog.parameter(pog.int(character_id))
            |> pog.execute(connection)
            as "the earlier save wrote the character's row"
          let assert Ok(_) =
            pog.query(
              "insert into character_quest (character_id, quest_id, state, completed_at) values ($1, 1004, 3, to_timestamp(1700000000))",
            )
            |> pog.parameter(pog.int(character_id))
            |> pog.execute(connection)
            as "and a quest row the later log does not have"
          process.send(locked, release)
          let assert Ok(Nil) = process.receive(release, within: 30_000)
            as "the test released the row"
          Ok(Nil)
        })
        as "the earlier save's transaction ran"
      process.send(committed, Nil)
    })
  let assert Ok(release) =
    process.receive(locked, within: ask_support.event_wait_ms)
    as "the earlier save holds the row"
  EarlierSave(release:, committed:)
}

/// Commits the earlier save and returns once it has.
fn release_earlier_save(earlier: EarlierSave) -> Nil {
  process.send(earlier.release, Nil)
  let assert Ok(Nil) =
    process.receive(earlier.committed, within: ask_support.event_wait_ms)
    as "the earlier save committed"
  Nil
}

/// Returns once a statement of this database waits for a lock, which is the
/// later save waiting for the row the earlier one holds. It reads the database's
/// own wait state, polling every 20 ms for at most `event_wait_ms`.
fn await_a_statement_waiting_for_a_lock(store store: Store) -> Nil {
  let waiting = fn() {
    let assert Ok(returned) =
      pog.query(
        "select count(*)::int from pg_stat_activity where datname = current_database() and wait_event_type = 'Lock'",
      )
      |> pog.returning(decode.at([0], decode.int))
      |> pog.execute(store.pool)
      as "the waiting statements were counted"
    returned.rows != [0]
  }
  await_until(waiting, polls: ask_support.event_wait_ms / 20)
}

fn await_until(done: fn() -> Bool, polls polls: Int) -> Nil {
  case done(), polls {
    True, _ -> Nil
    False, 0 -> panic as "the event did not happen within the deadline"
    False, _ -> {
      process.sleep(20)
      await_until(done, polls: polls - 1)
    }
  }
}

pub fn a_constraint_of_the_quest_table_the_worker_does_not_map_is_refused_as_a_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let _login = epoch_of_load(store:, account:, character_id: id)
  // The primary key and the foreign key of the table share its `character_quest_`
  // start with its checks, and neither is a limit of the client's. A save's upsert
  // cannot break either, so a constraint of the table the worker does not map is
  // put in to stand for them.
  execute(
    store.pool,
    "alter table character_quest add constraint character_quest_test_refuses_1100 check (quest_id <> 1100)",
  )
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      quests: [completed_quest(1001), completed_quest(1100)],
    )
    == ForMove(PlaceRefused(constraint: "character_quest_test_refuses_1100"))
    as "only the ten checks the client's limits name are a refused quest log: any other constraint of the table is a refused place"
  stop(store)
}

pub fn a_quest_row_the_client_would_refuse_is_refused_by_its_named_constraint_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let #(account, id) = one_character(store:)
  let _login = epoch_of_load(store:, account:, character_id: id)
  let refused = fn(quest: QuestRow, constraint: String, why: String) {
    assert save_log(
        store:,
        account:,
        character_id: id,
        epoch: 1,
        sequence: 1,
        quests: [completed_quest(1001), quest],
      )
      == ForMove(QuestLogRefused(constraint:))
      as why
  }
  refused(
    QuestRow(..accepted_quest(1003), state: 4),
    "character_quest_active_has_its_entry",
    "opcode.0x35f.active_state_crash: only states 1 and 2 are in the client's active list, so an entry of any other state is refused (the client crashes on it)",
  )
  refused(
    QuestRow(
      ..accepted_quest(1003),
      active: Some(
        ActiveQuest(
          ..accepted_entry(),
          progress: [1, 1, 1, 1, 1, 1, 1],
          objective_ms_left: [0, 0, 0, 0, 0, 0, 0],
        ),
      ),
    ),
    "character_quest_progress_fits_six_objectives",
    "0x1405510d0: a quest has at most 6 objectives (kQuestMaxObjective), so 7 progress values are refused",
  )
  refused(
    QuestRow(
      ..accepted_quest(1003),
      active: Some(ActiveQuest(..accepted_entry(), objective_ms_left: [0, 0])),
    ),
    "character_quest_timers_match_progress",
    "opcode.0x35f: an objective's time left is sent for each progress value, so 3 progress values with 2 timers are refused",
  )
  refused(
    accepted_quest(32_768),
    "character_quest_id_fits_15_bits",
    "opcode.0x35f: a quest id is 15 bits on the wire, so 32768 is refused",
  )
  assert save_log(
      store:,
      account:,
      character_id: id,
      epoch: 1,
      sequence: 1,
      quests: [completed_quest(1001), accepted_quest(1003)],
    )
    == ForMove(PlaceSaved)
    as "each refusal was one statement that stored nothing and took no sequence, and the store goes on: the next save is written"
  // A row of a state outside the active list that holds only some of the active
  // columns cannot come from a `QuestRow`, so it is put into the table directly.
  let put = fn(column: String, value: String) {
    pog.query(
      "insert into character_quest (character_id, quest_id, state, "
      <> column
      <> ") values ($1, 1009, 4, "
      <> value
      <> ")",
    )
    |> pog.parameter(pog.int(id))
    |> pog.execute(store.pool)
  }
  let assert Error(pog.ConstraintViolated(constraint:, ..)) =
    put("tracked", "true")
    as "the table refused a botched row that holds a tracked flag"
  assert constraint == "character_quest_active_has_its_entry"
    as "opcode.0x35f.active_state_crash: a quest outside the active list has none of the active entry's columns, not some of them"
  let assert Error(pog.ConstraintViolated(constraint:, ..)) =
    put("quest_ms_left", "0")
    as "the table refused a botched row that holds a time left"
  assert constraint == "character_quest_active_has_its_entry"
  assert result.is_ok(put("tracked", "null"))
    as "a botched row with none of them is accepted"
  stop(store)
}
