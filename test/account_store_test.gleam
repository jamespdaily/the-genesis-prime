//// The account store: one worker per ask, on pog's pool, against a migrated
//// database of the test's own (`test/database_support.gleam`). Expected values
//// come from these places.
//// - The rows the tests insert, and the table's columns in
////   `priv/migrations/0001_account_and_character.sql`,
////   `priv/migrations/0002_character_list_columns.sql` and
////   `priv/migrations/0003_character_look.sql`.
//// - The create: a new character has the values of its CharacterCreation row
////   at level 1, with its path, look and bones as the client sent them
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
import genesis_prime/login/guid
import genesis_prime/service.{ToWorker}
import genesis_prime/store.{
  type AccountId, Account, AccountFound, AccountId, Character, CharacterCreated,
  CharacterId, Characters, FindAccount, ListCharacters, LookEntry, NameTaken,
  NewCharacter, NoFreeSlot, NoSuchAccount, Unavailable,
}
import genesis_prime/store/worker
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import gleam/result
import gleam/string
import login_support
import owned_test
import pog
import pool_started
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
  assert ask(store, FindAccount("login-1"))
    == AccountFound(Account(
      account_id: AccountId(id),
      login_name: "login-1",
      srp_salt: <<1, 2, 3>>,
      srp_verifier: <<4, 5, 6, 7>>,
      game_account_id:,
    ))
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
  assert ask(store, FindAccount("login-2")) == NoSuchAccount
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
        service.ToService(..) -> Nil
      }
    })
  let client = ask_support.connect(server)
  // A transaction in another connection locks the table, so the query waits.
  let release = lock_table(store.pool)
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
  process.send(release, Nil)
  ask_support.stop(server)
  stop(store)
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
      recorder: None,
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
  assert ask(store, FindAccount("login-1")) == Unavailable
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
      name: "Zed",
      class_id: 4,
      path: 2,
    )
  let second =
    character_support.insert(
      pool: store.pool,
      account:,
      name: "Abe",
      class_id: 12,
      path: 0,
    )
  let _theirs =
    character_support.insert(
      pool: store.pool,
      account: other,
      name: "Cal",
      class_id: 1,
      path: 1,
    )
  assert ask(store, ListCharacters(account))
    == Characters([
      Character(
        character_id: CharacterId(first),
        name: "Zed",
        gender: 1,
        race_id: RaceId(3),
        class_id: ClassId(4),
        faction_id: 166,
        level: 9,
        path: 2,
        world_id: 1387,
        world_zone_id: 1100,
        position_x: 1.5,
        position_y: 2.5,
        position_z: 3.5,
        look: [],
        bones: [],
      ),
      Character(
        character_id: CharacterId(second),
        name: "Abe",
        gender: 1,
        race_id: RaceId(3),
        class_id: ClassId(12),
        faction_id: 166,
        level: 9,
        path: 0,
        world_id: 1387,
        world_zone_id: 1100,
        position_x: 1.5,
        position_y: 2.5,
        position_z: 3.5,
        look: [],
        bones: [],
      ),
    ])
    as "the account's two rows as inserted, in the order of their ids, and not the other account's row"
  stop(store)
}

pub fn an_account_with_no_characters_or_no_account_gives_an_empty_list_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  assert ask(store, ListCharacters(account)) == Characters([])
    as "no row has that account's id"
  assert ask(store, ListCharacters(AccountId(account_id_nobody_has)))
    == Characters([])
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
  assert ask(store, ListCharacters(AccountId(1))) == Unavailable
    as "the pool is not running, so the query cannot reach the database"
  stop(store)
}

pub fn the_table_refuses_a_class_outside_1_to_20_a_path_outside_0_to_3_and_a_name_outside_1_to_32_characters_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let refused = fn(name, class_id, path) {
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
      Error(character_support.NotAConstraint) ->
        "a failure that is no constraint"
    }
  }
  assert refused("Eve", 0, 0) == "character_class_shown_by_the_client"
    as "the client shows ClassIcon_<class> for the classes 1 to 20, so class 0 has no icon"
  assert refused("Eve", 21, 0) == "character_class_shown_by_the_client"
    as "and class 21 has none"
  assert refused("Eve", 1, 4) == "character_path_shown_by_the_client"
    as "the client shows PathIcon_<path + 1> up to 4, so path 4 has no icon"
  assert refused("Eve", 1, -1) == "character_path_shown_by_the_client"
  // The edges the client does show are taken, each with a name of its own: a
  // name is unique ignoring case (migration 0003).
  assert refused("Eve", 1, 0) == "accepted"
  assert refused("Eva", 20, 3) == "accepted"
  // 0x1400201f0: the client copies at most 32 characters of a name (0x21 wide
  // characters with the zero), and a name of none has nothing to show.
  assert refused("", 1, 0) == "character_name_shown_by_the_client"
    as "no name is no name the list can show"
  assert refused(string.repeat("a", 33), 1, 0)
    == "character_name_shown_by_the_client"
    as "the client keeps 32 characters, so a 33rd is one it would cut"
  assert refused(string.repeat("a", 32), 1, 0) == "accepted"
    as "32 characters is the most the client keeps"
  assert refused(string.repeat("é", 32), 1, 0) == "accepted"
    as "the 32 are characters, not bytes"
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
      "Dev",
      1,
      1,
      1,
      167,
    )
    as "the tool's query ran"
  let assert [add_character_sql.InsertCharacterRow(character_id:)] =
    returned.rows
    as "the account of that login name got one row"
  assert ask(store, ListCharacters(account))
    == Characters([
      Character(
        character_id: CharacterId(character_id),
        name: "Dev",
        gender: 1,
        race_id: RaceId(1),
        class_id: ClassId(1),
        faction_id: 167,
        level: 1,
        path: 0,
        world_id: 0,
        world_zone_id: 0,
        position_x: 0.0,
        position_y: 0.0,
        position_z: 0.0,
        look: [],
        bones: [],
      ),
    ])
    as "the tool's doc comment: level 1, path 0, no world, zone or position"
  let assert Ok(none) =
    add_character_sql.insert_character(
      store.pool,
      "nobody",
      "Dev",
      1,
      1,
      1,
      167,
    )
    as "the query ran"
  assert none.rows == [] as "no account of that name gives no row"
  stop(store)
}

// ---- create ----

/// A new character with the values of CharacterCreation row 466 (class 1,
/// race 1, sex 1, faction 167), the path 2 and a look and bones.
fn a_new_character(name: String) -> store.NewCharacter {
  NewCharacter(
    name:,
    gender: 1,
    race_id: RaceId(1),
    class_id: ClassId(1),
    faction_id: 167,
    path: 2,
    look: [
      LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
      LookEntry(label: CharacterCustomizationLabelId(22), value: 4_000_000_000),
    ],
    // 0xBF800000 is -1.0 and has its top bit set; 0x3F800000 is 1.0.
    bones: [0xBF800000, 0x3F800000, 0],
  )
}

fn create(
  store store: Store,
  account account: AccountId,
  name name: String,
  slots slots: Int,
) -> store.Answer {
  ask(
    store,
    store.CreateCharacter(
      account_id: account,
      character: a_new_character(name),
      character_slots: slots,
    ),
  )
}

pub fn a_create_stores_the_character_at_level_1_with_the_values_it_was_given_and_the_list_returns_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let store = start_store(pool_size: 2)
  let account = insert_account(store, "login-1")
  let assert CharacterCreated(character_id:) =
    create(store:, account: account, name: "Ab Cd", slots: 2)
    as "the first create of an account with 2 slots is stored"
  assert ask(store, ListCharacters(account))
    == Characters([
      Character(
        character_id:,
        name: "Ab Cd",
        gender: 1,
        race_id: RaceId(1),
        class_id: ClassId(1),
        faction_id: 167,
        level: 1,
        path: 2,
        world_id: 0,
        world_zone_id: 0,
        position_x: 0.0,
        position_y: 0.0,
        position_z: 0.0,
        look: [
          LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
          LookEntry(
            label: CharacterCustomizationLabelId(22),
            value: 4_000_000_000,
          ),
        ],
        bones: [0xBF800000, 0x3F800000, 0],
      ),
    ])
    as "the card's design: race, sex, class and faction from the creation row, level 1, no world, zone or position until world entry, the look and the bones as the client sent them (32-bit values come back as they went in)"
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
    as "lua.Character.OnCreateCharacterFailed: 6; a name is unique ignoring case, across accounts, held by a unique index on lower(name)"
  assert create(store:, account: account, name: "AB CD", slots: 2) == NameTaken
    as "the same account too"
  assert ask(store, ListCharacters(other)) == Characters([])
    as "nothing was stored for the refused create"
  let assert Characters([_]) = ask(store, ListCharacters(account))
    as "the account still holds its one character"
  let assert CharacterCreated(_) =
    create(store:, account: other, name: "Éb Cd", slots: 2)
  assert create(store:, account: account, name: "éB cD", slots: 2) == NameTaken
    as "the Latin-1 letters the client lists fold too (IsTextRuleLetter 0x1403e09d0), so 'É' and 'é' are one letter"
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
  let assert Characters([_, _]) = ask(store, ListCharacters(account))
    as "nothing was stored for the refused create"
  let assert CharacterCreated(_) =
    create(store:, account: other, name: "Mn Op", slots: 2)
    as "another account's slots are its own"
  assert create(store:, account: account, name: "Ij Kl", slots: 3)
    |> is_created
    as "with 3 slots the same account may make a third"
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
    list.map(numbers(4), fn(_) {
      let assert Ok(answer) = process.receive(answers, within: 30_000)
        as "every create is answered"
      answer
    })
  assert list.count(received, is_created) == 1
    as "storing-data: the slot count is held by Postgres, in one statement under the account's row lock, so racing creates of one account make one character"
  assert list.count(received, fn(answer) { answer == NoFreeSlot }) == 3
  let assert Characters([_]) = ask(store, ListCharacters(account))
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
  assert insert(numbers(28), numbers(28), []) == Error("character_look_pairs")
    as "opcode.0x25b.counts: the label table allows at most 27"
  assert insert([], [], list.repeat(0, 49))
    == Error("character_bones_at_most_48")
    as "opcode.0x25b.counts: at most 48 bone values"
  assert insert(numbers(27), numbers(27), list.repeat(0, 48)) == Ok(Nil)
    as "27 pairs and 48 bones are the most a request carries"
  stop(store)
}

/// 1 to `count`.
fn numbers(count: Int) -> List(Int) {
  list.index_map(list.repeat(0, count), fn(_, index) { index + 1 })
}

fn is_created(answer: store.Answer) -> Bool {
  case answer {
    CharacterCreated(..) -> True
    AccountFound(..)
    | NoSuchAccount
    | Characters(..)
    | Unavailable
    | NameTaken
    | NoFreeSlot -> False
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
  let database = database_support.new_database(on: shared)
  let config =
    database_support.config(
      for: shared.settings,
      database:,
      pool_name: process.new_name("account_pool"),
      pool_size:,
    )
  let store = start_store_on(config)
  assert pool_started.await(config.pool_name, within_ms: 30_000)
    as "the pool opened its connections"
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
    recorder: None,
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

/// Locks the account table in a transaction of another connection, until the
/// returned subject is sent to. Returns once the lock is held.
fn lock_table(pool: pog.Connection) -> process.Subject(Nil) {
  let locked = process.new_subject()
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
      Nil
    })
  let assert Ok(release) =
    process.receive(locked, within: ask_support.event_wait_ms)
    as "the table is locked"
  release
}
