//// The store's workers: one process per ask, started under the store's
//// factory supervisor, which runs one query on pog's pool, answers the asker
//// and ends. pog's pool caps how many queries reach the database at once.
////
//// ```
//// asker (a shell)                 store supervisor            worker
////   ask(store, pool, request, reply)
////     not running ─▶ Error(Nil): NotRunning
////     start_child ─────────────▶ starts ─────────────────▶ runs the query
////   ◀── Ok(ToWorker(pid)); monitors it
////   ◀──────────────────────────────────────────────────── reply(answer), ends
////   at the deadline, no answer: ends the worker (exit shutdown) ─▶ NoAnswerInTime
////   the worker crashes ─▶ EndedBeforeAnswer
//// ```
////
//// - **Workers are temporary.** The supervisor never restarts one, and a
////   worker the asker ends at its deadline exits with `shutdown`, which the
////   supervisor does not report as a failure.
//// - **A worker's start does no work.** It spawns the worker and returns, and
////   the worker runs its query after, so `start_child`, a supervisor call with
////   no timeout, waits only for the starts queued before it.
//// - **The store not running.** `start_child` on a name no process holds
////   exits the caller with `{noproc, {gen_server, call, _}}` rather than
////   returning an error, and one made while the supervisor stops, which ends
////   with `shutdown` before it takes the call, exits it with `{shutdown,
////   {gen_server, call, _}}`; `ask` (through `service.start_child`) catches
////   those two exits, and only those, as `Error(Nil)`.
//// - **Failures.** One private `attempt` holds them for every request, so each
////   request maps only its rows. pog's `ConnectionUnavailable` and
////   `QueryTimeout` answer `Unavailable`, and so does the pool not running:
////   pgo's checkout exits with `{noproc, {pgo_pool, checkout, _}}` then, which
////   the worker catches, and only that exit. A constraint the database
////   refused is the request's to map, by the name the schema gave it
////   (`mapped_constraints`): a create or a rename maps its name's unique index
////   to `NameTaken` or `NewNameTaken` and the name's rule-0 check to
////   `NameBreaksRule` or `NewNameBreaksRule`, and a save maps the health's
////   check to `HealthRefused`. Any other error is a bug in the query or the
////   schema: the worker crashes with it, and the asker gets `EndedBeforeAnswer`.
//// - **A create is one transaction.** It takes the account's row lock, so one
////   account's creates run one after another, and then inserts the character
////   unless the account already has its slots, in one statement; the name's
////   uniqueness is the index on the ICU-folded `lower(name collate "und-x-icu")`,
////   and its form is the table's rule-0 check. An account that has no row is
////   `CreateForNoSuchAccount`. The insert is followed in the same transaction by
////   one insert of the character's starting items, so a create that is refused
////   stores no item.
//// - **A load is one transaction.** World entry's load of a character names the
////   account's id as well as the character's, so another account's character
////   is never taken; its update raises the character's `session_epoch` by one
////   and returns the new value with the row, so the login that loaded the
////   character holds that epoch, and it locks the row, so the reads of the
////   character's items and of its quest log that follow on the same connection
////   find the items and quests the character had when the row was taken, and a
////   delete of the character cannot land between them. No row is
////   `NotTheAccounts`.
//// - **A save is one statement.** It names the account's id, the character's,
////   the epoch the saving login was told and the save's own sequence number, so
////   a save from an older login, or one that reaches the database after a newer
////   save of its own login, matches no row and changes nothing. It writes the
////   health, the experience and the level with the place. A save that
////   `character_health_is_not_negative` refuses is `HealthRefused`, one that
////   `character_experience_is_not_negative` refuses is `ExperienceRefused`; one that any other check constraint of the table
////   refuses is `PlaceRefused` with that constraint's name; the worker does not
////   crash for either. The statement also writes the character's quest log under
////   the same fence (save_place.sql); a check of the character_quest table that
////   refuses a quest row is `QuestLogRefused` with that check's name.
//// - **A delete and a rename are one statement each.** Both name the account's
////   id, so another account's character is never touched; a rename also
////   clears the character's mark in the same update, and its name's
////   uniqueness and form are the same index and check as a create's.
//// - **The probe.** One more kind of job, which `main` asks to know the database
////   answers and runs the migrations the server was built with
////   (genesis_prime/readiness). It runs `select 1`, and once that returns it
////   reads the `schema_migration` table, one more query on the same worker. It
////   is no `Request`, so no rule's types or recordings hold it; its answer is
////   `Reached`, with what the table held (`NoRecord` for a database without the
////   table, `Unreadable` with the error for a table it cannot read), or
////   `Unreached`, which is every failure a request answers `Unavailable` for.
//// - **The supervisor stopping.** Its workers get its shutdown timeout to end;
////   an asker waiting on one gets `EndedBeforeAnswer`.

import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/login/guid
import genesis_prime/migration.{
  type Recorded, Migration, NoRecord, Recorded, Unreadable,
}
import genesis_prime/service.{type Sent, ToWorker}
import genesis_prime/store.{
  type AccountId, type Answer, type Character, type CharacterId,
  type CreateAnswer, type DeleteAnswer, type FindAccountAnswer, type HeldItem,
  type ItemsAnswer, type ItemsRequest, type MoveAnswer, type MoveRequest,
  type Naming, type NewCharacter, type NewItem, type QuestRow, type RenameAnswer,
  type Request, type SelectAnswer, type SelectRequest, type WorldAnswer,
  type WorldRequest, Account, AccountFound, AccountId, ActiveQuest, Character,
  CharacterCreated, CharacterDeleted, CharacterId, CharacterLoaded,
  CharacterRenamed, CreateCharacter, CreateForNoSuchAccount, Created,
  DeleteCharacter, DeleteItem, Deleted, ExperienceRefused, FindAccount, ForItems,
  ForLogin, ForMove, ForSelect, ForWorld, HealthRefused, HeldItem, ItemMade,
  Items, ItemsNotSaved, ItemsSaved, ListCharacters, Listed, LoadCharacter, Login,
  MergeItems, Move, MoveItems, NameBreaksRule, NameStands, NameTaken,
  NeedsRename, NewNameBreaksRule, NewNameTaken, NoFreeSlot, NoSuchAccount,
  NoSuchCharacter, NotTheAccounts, NothingSaved, PlaceRefused, PlaceSaved,
  QuestLogRefused, QuestRow, RenameCharacter, Renamed, SavePlace, SaveRefused,
  Select, SplitItem, Unavailable, World,
}
import genesis_prime/store/sql
import genesis_prime/table/id.{ClassId, Item2Id, RaceId}
import gleam/bool
import gleam/erlang/process.{type Name}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import pog

/// The unique index on the ICU-folded lower-cased name (migration 0005), which a
/// create or a rename refused is a name another character holds.
const character_name_unique = "character_name_unique"

/// The table's check that a name is a full name by the client's text rule 0
/// (migration 0014), which a create or a rename refused is a name that breaks it.
const character_name_follows_rule_0 = "character_name_follows_rule_0"

/// The table's check that a saved health is not below 0 (migration 0017).
const character_health_is_not_negative = "character_health_is_not_negative"

/// The table's check that a saved experience is not below 0 (migration 0022).
const character_experience_is_not_negative =
  "character_experience_is_not_negative"

/// The checks of the character_quest table (migration 0021), one for each limit of
/// the client's a quest row can break. A save one of them refuses answers
/// `QuestLogRefused` with the check's own name. The table's primary key and its
/// foreign key to the character are not among them: neither is a limit of the
/// client's, and a refused one is a refused place.
const quest_checks = [
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

/// Every constraint or unique index the worker answers for by name. The schema
/// holds each by this name, which a test reads from the catalogue.
pub fn mapped_constraints() -> List(String) {
  [
    character_name_unique,
    character_name_follows_rule_0,
    character_health_is_not_negative,
    character_experience_is_not_negative,
    ..quest_checks
  ]
}

/// What one worker is started with: a rule's ask and how to answer it, or the
/// probe `main` makes to know the database answers.
pub type Job {
  Job(request: Request, reply: fn(Answer) -> Nil)
  Probe(reply: fn(Probed) -> Nil)
}

/// What the probe's reads found. The probe is no rule's request, so it has no
/// `Answer` of its own and no recorded rule can hold it.
pub type Probed {
  /// `select 1` returned its row, and the migrations the database recorded
  /// were read after it.
  Reached(recorded: Recorded)
  /// The pool could not run it: no connection yet, a connection lost, a query
  /// that timed out, or no pool running.
  Unreached
}

/// The store's factory supervisor as a permanent child of the server's
/// supervisor, registered as `name`, its workers running on `pool`.
pub fn supervised(
  name name: Name(factory_supervisor.Message(Job, Nil)),
  pool pool: pog.Connection,
) -> ChildSpecification(factory_supervisor.Supervisor(Job, Nil)) {
  factory_supervisor.worker_child(fn(job: Job) { start_worker(job, pool) })
  |> factory_supervisor.named(name)
  |> factory_supervisor.restart_strategy(supervision.Temporary)
  // A temporary worker is never restarted, so this limit is never reached.
  |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
  // A worker traps no exits, so it ends the moment it is told to.
  |> factory_supervisor.timeout(ms: 1000)
  |> factory_supervisor.supervised
  |> supervision.restart(supervision.Permanent)
}

/// Starts a worker for one ask, for an asker's directory: `Error(Nil)` when
/// the store's supervisor is not running or will not start the worker, else
/// `ToWorker` with the worker the asker monitors and ends at its deadline.
pub fn ask(
  store store: Name(factory_supervisor.Message(Job, Nil)),
  request request: Request,
  reply reply: fn(Answer) -> Nil,
) -> Result(Sent, Nil) {
  service.start_child(supervisor: store, argument: Job(request:, reply:))
  |> service.sent_to_worker
}

/// Starts a worker for the probe, for the readiness ask
/// (genesis_prime/readiness): `Error(Nil)` when the store's supervisor is not
/// running or will not start the worker, else `ToWorker` with the worker the
/// asker monitors and ends at its deadline. The worker runs `select 1` on the
/// pool, then reads the recorded migrations, and answers `Reached` or
/// `Unreached`; any other database error is a bug and ends the worker, as it
/// does for a request.
pub fn probe(
  store store: Name(factory_supervisor.Message(Job, Nil)),
  reply reply: fn(Probed) -> Nil,
) -> Result(Sent, Nil) {
  service.start_child(supervisor: store, argument: Probe(reply:))
  |> service.sent_to_worker
}

/// Runs the probe on a pool that no store serves, as the content load's wait for
/// the database does before the tree exists: a process of its own, not linked to
/// the asker, runs the same two queries and answers `Reached` or `Unreached`;
/// the asker monitors it and ends it at its deadline (`ToWorker`).
pub fn probe_pool(
  pool pool: pog.Connection,
  reply reply: fn(Probed) -> Nil,
) -> Result(Sent, Nil) {
  Ok(ToWorker(pid: process.spawn_unlinked(fn() { reply(probed(pool)) })))
}

/// Spawns the worker and returns at once, so the supervisor's start call
/// waits for no work; the worker runs its query after.
fn start_worker(job: Job, pool: pog.Connection) -> actor.StartResult(Nil) {
  let pid = process.spawn(fn() { run(job, pool) })
  Ok(actor.Started(pid:, data: Nil))
}

/// Runs the job on the pool, answers the asker and ends.
fn run(job: Job, pool: pog.Connection) -> Nil {
  case job {
    Job(request:, reply:) -> reply(run_request(request, pool))
    Probe(reply:) -> reply(probed(pool))
  }
}

/// Runs the probe's two queries, so the pool being away is `Unreached`:
/// `select 1`, through the same `query` the requests use, then the read of the
/// recorded migrations.
fn probed(pool: pog.Connection) -> Probed {
  case query(fn() { sql.select_one(pool) }) {
    Ok(_) ->
      case recorded(pool) {
        Ok(recorded) -> Reached(recorded:)
        Error(Nil) -> Unreached
      }
    Error(Nil) -> Unreached
  }
}

/// What the database recorded of the migrations it ran: its rows, `NoRecord`
/// when it has no `schema_migration` table (Postgres's `undefined_table`,
/// 42P01), or `Unreadable` with the error of any other failure of the read,
/// since the database answered and what it holds cannot be told. `Error(Nil)`
/// when the database is away.
fn recorded(pool: pog.Connection) -> Result(Recorded, Nil) {
  case attempt(fn() { sql.list_migrations(pool) }) {
    Ok(rows) ->
      Ok(
        Recorded(
          list.map(rows, fn(row) {
            Migration(name: row.name, sha256: row.sha256)
          }),
        ),
      )
    Error(Unreachable) -> Error(Nil)
    Error(Unexpected(error: pog.PostgresqlError(code: "42P01", ..))) ->
      Ok(NoRecord)
    Error(Unexpected(error:)) | Error(Refused(error:, ..)) ->
      Ok(Unreadable(reason: describe_query_error(error)))
  }
}

/// The error as a sentence for the log: what Postgres or pog said.
pub fn describe_query_error(error: pog.QueryError) -> String {
  case error {
    pog.PostgresqlError(code:, name:, message:) ->
      name <> " (" <> code <> "): " <> message
    pog.ConstraintViolated(message:, ..) -> message
    pog.UnexpectedArgumentCount(..)
    | pog.UnexpectedArgumentType(..)
    | pog.UnexpectedResultType(..) -> "the query and the table do not match"
    pog.ConnectionUnavailable -> "no connection to the database"
    pog.QueryTimeout -> "the query timed out"
  }
}

/// Runs the ask's query on the pool. `Error(Nil)` is the database being away,
/// the failure every request shares, which the asker is told as `Unavailable`.
fn run_request(request: Request, pool: pog.Connection) -> Answer {
  let answer = case request {
    Login(request: FindAccount(login_name:)) ->
      find_account(pool, login_name)
      |> result.map(ForLogin)
    Select(request:) ->
      select(pool, request)
      |> result.map(ForSelect)
    World(request:) ->
      world(pool, request)
      |> result.map(ForWorld)
    Move(request:) ->
      move(pool, request)
      |> result.map(ForMove)
    Items(request:) ->
      items(pool, request)
      |> result.map(ForItems)
  }
  result.unwrap(answer, Unavailable)
}

/// Runs one of the player's items' requests: each is one transaction, the
/// character's row lock (lock_character_for_save.sql) and then one statement
/// that names the account, the character, the epoch and each item as the request
/// holds it (move_character_items.sql, split_character_item.sql,
/// merge_character_items.sql, delete_character_item.sql). A move answers
/// `ItemsSaved` when it moved as many items as the request has moves, a split
/// `ItemMade` with the new stack's guid, a merge and a delete `ItemsSaved`;
/// each answers `ItemsNotSaved` when it changed nothing and `SaveRefused` when a
/// check or the unique key of the character_item table refused a place;
/// `Error(Nil)` when the database is away.
fn items(
  pool: pog.Connection,
  request: ItemsRequest,
) -> Result(ItemsAnswer, Nil) {
  case request {
    MoveItems(account_id:, character_id:, session_epoch:, moves:) ->
      move_items(pool:, account_id:, character_id:, session_epoch:, moves:)
    SplitItem(account_id:, character_id:, session_epoch:, source:, count:, to:) ->
      split_item(
        pool:,
        account_id:,
        character_id:,
        session_epoch:,
        source:,
        count:,
        to:,
      )
    MergeItems(
      account_id:,
      character_id:,
      session_epoch:,
      source:,
      target:,
      count:,
    ) ->
      merge_items(
        pool:,
        account_id:,
        character_id:,
        session_epoch:,
        source:,
        target:,
        count:,
      )
    DeleteItem(account_id:, character_id:, session_epoch:, item:) ->
      delete_item(pool:, account_id:, character_id:, session_epoch:, item:)
  }
}

/// A split: split_character_item.sql, answered with `ItemMade` and the new
/// stack's guid; a taken place that broke the table's unique key is
/// `SaveRefused`.
fn split_item(
  pool pool: pog.Connection,
  account_id account_id: store.AccountId,
  character_id character_id: store.CharacterId,
  session_epoch session_epoch: store.SessionEpoch,
  source source: store.HeldItem,
  count count: Int,
  to to: store.ItemPlace,
) -> Result(ItemsAnswer, Nil) {
  let AccountId(account_id) = account_id
  let CharacterId(character_id) = character_id
  locked(pool:, account_id:, character_id:, statement: fn(connection) {
    sql.split_character_item(
      connection,
      character_id,
      account_id,
      store.session_epoch_number(session_epoch),
      source.item_guid,
      source.location,
      source.bag_index,
      source.stack_count,
      count,
      to.location,
      to.bag_index,
    )
  })
  |> items_answer(saved: fn(rows) {
    case rows {
      [row] -> ItemMade(item_guid: row.item_guid)
      _ -> panic as "the statement makes one stack or none"
    }
  })
}

/// A merge: merge_character_items.sql, answered with `ItemsSaved` when it
/// changed both stacks.
fn merge_items(
  pool pool: pog.Connection,
  account_id account_id: store.AccountId,
  character_id character_id: store.CharacterId,
  session_epoch session_epoch: store.SessionEpoch,
  source source: store.HeldItem,
  target target: store.HeldItem,
  count count: Int,
) -> Result(ItemsAnswer, Nil) {
  let AccountId(account_id) = account_id
  let CharacterId(character_id) = character_id
  locked(pool:, account_id:, character_id:, statement: fn(connection) {
    sql.merge_character_items(
      connection,
      character_id,
      account_id,
      store.session_epoch_number(session_epoch),
      source.item_guid,
      source.location,
      source.bag_index,
      source.stack_count,
      target.item_guid,
      target.location,
      target.bag_index,
      target.stack_count,
      count,
    )
  })
  |> items_answer(saved: fn(rows) {
    case rows {
      [_, _] -> ItemsSaved
      _ -> panic as "the statement changes both stacks or none"
    }
  })
}

/// A delete: delete_character_item.sql, answered with `ItemsSaved` when it
/// deleted the stack.
fn delete_item(
  pool pool: pog.Connection,
  account_id account_id: store.AccountId,
  character_id character_id: store.CharacterId,
  session_epoch session_epoch: store.SessionEpoch,
  item item: store.HeldItem,
) -> Result(ItemsAnswer, Nil) {
  let AccountId(account_id) = account_id
  let CharacterId(character_id) = character_id
  locked(pool:, account_id:, character_id:, statement: fn(connection) {
    sql.delete_character_item(
      connection,
      character_id,
      account_id,
      store.session_epoch_number(session_epoch),
      item.item_guid,
      item.location,
      item.bag_index,
      item.stack_count,
    )
  })
  |> items_answer(saved: fn(rows) {
    case rows {
      [_] -> ItemsSaved
      _ -> panic as "the statement deletes one stack or none"
    }
  })
}

/// A move or swap: move_character_items.sql, answered with `ItemsSaved` when it
/// moved as many items as the request has moves.
fn move_items(
  pool pool: pog.Connection,
  account_id account_id: store.AccountId,
  character_id character_id: store.CharacterId,
  session_epoch session_epoch: store.SessionEpoch,
  moves moves: List(store.ItemMove),
) -> Result(ItemsAnswer, Nil) {
  let AccountId(account_id) = account_id
  let CharacterId(character_id) = character_id
  locked(pool:, account_id:, character_id:, statement: fn(connection) {
    sql.move_character_items(
      connection,
      character_id,
      account_id,
      store.session_epoch_number(session_epoch),
      list.map(moves, fn(move) { move.item_guid }),
      list.map(moves, fn(move) { move.from.location }),
      list.map(moves, fn(move) { move.from.bag_index }),
      list.map(moves, fn(move) { move.to.location }),
      list.map(moves, fn(move) { move.to.bag_index }),
    )
  })
  |> items_answer(saved: fn(rows) {
    case list.length(rows) == list.length(moves) {
      True -> ItemsSaved
      False -> panic as "the statement moves every item of the request or none"
    }
  })
}

/// The answer to an items request from what its statement gave: `ItemsNotSaved`
/// for no row, `saved` of the rows otherwise, `SaveRefused` for a check or the
/// unique key of the character_item table, and `Error(Nil)` for the database
/// being away.
fn items_answer(
  attempted: Result(List(row), Failure),
  saved saved: fn(List(row)) -> ItemsAnswer,
) -> Result(ItemsAnswer, Nil) {
  case attempted {
    Ok([]) -> Ok(ItemsNotSaved)
    Ok(rows) -> Ok(saved(rows))
    Error(Unreachable) -> Error(Nil)
    Error(Refused(constraint:, ..)) -> Ok(SaveRefused(constraint:))
    Error(Unexpected(error:)) -> exit_with(error)
  }
}

/// Runs one statement in a transaction that first takes the character's row lock
/// (lock_character_for_save.sql), so two statements on a character never
/// overlap, and gives the statement's rows or why it gave none.
fn locked(
  pool pool: pog.Connection,
  account_id account_id: Int,
  character_id character_id: Int,
  statement statement: fn(pog.Connection) ->
    Result(pog.Returned(row), pog.QueryError),
) -> Result(List(row), Failure) {
  attempt(fn() {
    in_transaction(pool, fn(connection) {
      use _ <- result.try(sql.lock_character_for_save(
        connection,
        character_id,
        account_id,
      ))
      statement(connection)
    })
  })
}

/// Runs one of character select's requests.
fn select(
  pool: pog.Connection,
  request: SelectRequest,
) -> Result(SelectAnswer, Nil) {
  case request {
    ListCharacters(account_id:) ->
      list_characters(pool, account_id)
      |> result.map(Listed)
    CreateCharacter(account_id:, character:, character_slots:) ->
      create_character(pool:, account_id:, character:, character_slots:)
      |> result.map(Created)
    DeleteCharacter(account_id:, character_id:) ->
      delete_character(pool:, account_id:, character_id:)
      |> result.map(Deleted)
    RenameCharacter(account_id:, character_id:, name:) ->
      rename_character(pool:, account_id:, character_id:, name:)
      |> result.map(Renamed)
  }
}

/// The account with the login name, if there is one; `Error(Nil)` when the
/// database is away.
fn find_account(
  pool: pog.Connection,
  login_name: String,
) -> Result(FindAccountAnswer, Nil) {
  use rows <- result.map(query(fn() { sql.find_account(pool, login_name) }))
  case rows {
    [] -> NoSuchAccount
    [row] -> {
      let assert Ok(game_account_id) = guid.from_text(row.game_account_id)
        as "the database holds game account ids that are GUIDs"
      AccountFound(Account(
        account_id: AccountId(row.account_id),
        login_name: row.login_name,
        srp_salt: row.srp_salt,
        srp_verifier: row.srp_verifier,
        game_account_id:,
      ))
    }
    _ ->
      panic as "a login name is unique, so the query returns at most one account"
  }
}

/// Runs one of world entry's requests.
fn world(
  pool: pog.Connection,
  request: WorldRequest,
) -> Result(WorldAnswer, Nil) {
  let LoadCharacter(account_id:, character_id:) = request
  load_character(pool:, account_id:, character_id:)
}

/// Runs one of the player's movement's requests: a save is one transaction, the
/// character's row lock (lock_character_for_save.sql) and then one statement that
/// names the account, the character, the epoch and the save's sequence
/// (save_place.sql), so two saves of a character never overlap and the later one
/// reads the quest rows the earlier one committed, answering `PlaceSaved` when it changed a row and
/// `NothingSaved` when it matched none, `HealthRefused` when the table's
/// `character_health_is_not_negative` refused the health, `ExperienceRefused` when
/// `character_experience_is_not_negative` refused the experience, `QuestLogRefused`
/// when a check of the character_quest table refused a quest row and `PlaceRefused` when
/// another check of the table refused the place; `Error(Nil)` when the database
/// is away.
fn move(pool: pog.Connection, request: MoveRequest) -> Result(MoveAnswer, Nil) {
  let SavePlace(
    account_id: AccountId(account_id),
    character_id: CharacterId(character_id),
    session_epoch:,
    save_sequence:,
    place:,
    health:,
    experience:,
    level:,
    quests:,
  ) = request
  let facing = start_place.facing(place)
  // squirrel cannot type a parameter that may be NULL (save_place.sql): the
  // health goes as a number and whether to keep it.
  let #(health, keeps_health) = case health {
    Some(health) -> #(health, True)
    None -> #(0, False)
  }
  case
    locked(pool:, account_id:, character_id:, statement: fn(connection) {
      sql.save_place(
        connection,
        character_id,
        account_id,
        store.session_epoch_number(session_epoch),
        start_place.world_id(place),
        start_place.world_zone_id(place),
        start_place.x(place),
        start_place.y(place),
        start_place.z(place),
        facing.yaw,
        facing.pitch,
        facing.roll,
        save_sequence,
        health,
        keeps_health,
        experience,
        level,
        quests_json(quests),
      )
    })
  {
    Ok([_]) -> Ok(PlaceSaved)
    Ok([]) -> Ok(NothingSaved)
    Ok(_) -> panic as "a character id is unique, so a save changes at most one"
    Error(Unreachable) -> Error(Nil)
    Error(Refused(constraint:, ..))
      if constraint == character_health_is_not_negative
    -> Ok(HealthRefused)
    Error(Refused(constraint:, ..))
      if constraint == character_experience_is_not_negative
    -> Ok(ExperienceRefused)
    Error(Refused(constraint:, ..)) ->
      case list.contains(quest_checks, constraint) {
        True -> Ok(QuestLogRefused(constraint:))
        False -> Ok(PlaceRefused(constraint:))
      }
    Error(Unexpected(error:)) -> exit_with(error)
  }
}

/// The account's characters in creation order; an account with none, or no
/// such account, has an empty list. `Error(Nil)` when the database is away.
fn list_characters(
  pool: pog.Connection,
  account_id: AccountId,
) -> Result(List(Character), Nil) {
  let AccountId(account_id) = account_id
  query(fn() { sql.list_characters(pool, account_id) })
  |> result.map(list.map(_, character))
}

/// The account's character with the id, taken in one transaction: one statement
/// names the account too, so another account's character is never taken, and
/// raises the session epoch, which locks the character's row; the read of the
/// character's items then runs on the same connection before the commit, so a
/// delete of the character waits for the lock and an answer never holds a
/// character without the items it had. `NotTheAccounts` when the account has no
/// such character, and `Error(Nil)` when the database is away.
fn load_character(
  pool pool: pog.Connection,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
) -> Result(WorldAnswer, Nil) {
  let AccountId(account_id) = account_id
  let CharacterId(character_id) = character_id
  let transaction = fn() {
    in_transaction(pool, fn(connection) {
      use loaded <- result.try(sql.load_character(
        connection,
        character_id,
        account_id,
      ))
      use item_rows <- result.try(case loaded.rows {
        [_] -> sql.load_character_items(connection, character_id)
        _ -> Ok(pog.Returned(count: 0, rows: []))
      })
      use quest_rows <- result.map(case loaded.rows {
        [_] -> sql.load_quest_log(connection, character_id)
        _ -> Ok(pog.Returned(count: 0, rows: []))
      })
      pog.Returned(
        ..loaded,
        rows: list.map(loaded.rows, fn(row) {
          LoadedRow(row:, items: item_rows.rows, quests: quest_rows.rows)
        }),
      )
    })
  }
  use rows <- result.map(query(transaction))
  case rows {
    [LoadedRow(row:, items: item_rows, quests: quest_rows)] -> {
      let assert Ok(epoch) = store.session_epoch(row.session_epoch)
        as "a load raises the epoch by one, so it is 1 or more"
      CharacterLoaded(
        character: Character(
          character_id: CharacterId(row.character_id),
          name: row.name,
          gender: row.gender,
          race_id: RaceId(row.race_id),
          class_id: ClassId(row.class_id),
          faction_id: row.faction_id,
          level: row.level,
          path: row.path,
          place: saved_place(
            world_id: row.world_id,
            world_zone_id: row.world_zone_id,
            position_x: row.position_x,
            position_y: row.position_y,
            position_z: row.position_z,
            rotation_yaw: row.rotation_yaw,
            rotation_pitch: row.rotation_pitch,
            rotation_roll: row.rotation_roll,
          ),
          look: store.look(labels: row.look_labels, values: row.look_values),
          bones: row.bones,
          naming: naming(row.needs_rename),
        ),
        session_epoch: epoch,
        saved_health: row.health,
        saved_experience: row.experience,
        items: held_items(item_rows),
        quests: quest_rows_of(quest_rows),
      )
    }
    [] -> NotTheAccounts
    _ -> panic as "a character id is unique, so a read returns at most one"
  }
}

/// The one row a load's transaction gives: the character whose epoch the
/// update raised, with its items.
type LoadRow {
  LoadedRow(
    row: sql.LoadCharacterRow,
    items: List(sql.LoadCharacterItemsRow),
    quests: List(sql.LoadQuestLogRow),
  )
}

/// The rows of a character's quest log as the rows the store hands the quest log's
/// decode, in the order the query gave them (quest id). A row's completed time is
/// read only for state 3, and its active columns only for states 1 and 2, where
/// the table's checks hold them all (`character_quest_completed_has_a_time`,
/// `character_quest_active_has_its_entry`).
fn quest_rows_of(rows: List(sql.LoadQuestLogRow)) -> List(QuestRow) {
  list.map(rows, fn(row) {
    QuestRow(
      quest_id: row.quest_id,
      state: row.state,
      completed_at: case row.state {
        3 -> Some(row.completed_at)
        _ -> None
      },
      active: case
        row.placeholder_objective_id,
        row.tracked,
        row.done_mask,
        row.progress,
        row.quest_ms_left,
        row.objective_ms_left
      {
        Some(placeholder_objective_id),
          Some(tracked),
          Some(done_mask),
          Some(progress),
          Some(quest_ms_left),
          Some(objective_ms_left)
        ->
          Some(ActiveQuest(
            placeholder_objective_id:,
            tracked:,
            done_mask:,
            progress:,
            quest_ms_left:,
            objective_ms_left:,
          ))
        None, None, None, None, None, None -> None
        _, _, _, _, _, _ ->
          panic as "character_quest_active_has_its_entry holds all the active columns or none"
      },
    )
  })
}

/// The quest log's rows as the JSON array save_place.sql unpacks, one object for
/// each row whose keys are the character_quest columns, a completed time in whole
/// Unix seconds and the active columns null for a row without an active entry.
fn quests_json(quests: List(QuestRow)) -> Json {
  json.preprocessed_array(
    list.map(quests, fn(quest) {
      json.object([
        #("quest_id", json.int(quest.quest_id)),
        #("state", json.int(quest.state)),
        #("completed_at", json.nullable(quest.completed_at, json.int)),
        #(
          "placeholder_objective_id",
          json.nullable(quest.active, fn(active) {
            json.int(active.placeholder_objective_id)
          }),
        ),
        #(
          "tracked",
          json.nullable(quest.active, fn(active) { json.bool(active.tracked) }),
        ),
        #(
          "done_mask",
          json.nullable(quest.active, fn(active) { json.int(active.done_mask) }),
        ),
        #(
          "progress",
          json.nullable(quest.active, fn(active) {
            json.array(active.progress, json.int)
          }),
        ),
        #(
          "quest_ms_left",
          json.nullable(quest.active, fn(active) {
            json.int(active.quest_ms_left)
          }),
        ),
        #(
          "objective_ms_left",
          json.nullable(quest.active, fn(active) {
            json.array(active.objective_ms_left, json.int)
          }),
        ),
      ])
    }),
  )
}

/// The rows of a character's items as the items they hold, in the order the
/// query gave them.
fn held_items(rows: List(sql.LoadCharacterItemsRow)) -> List(HeldItem) {
  list.map(rows, fn(row) {
    HeldItem(
      item_guid: row.item_guid,
      item2_id: Item2Id(row.item2_id),
      location: row.location,
      bag_index: row.bag_index,
      stack_count: row.stack_count,
    )
  })
}

/// Stores the new character's items on the transaction's connection.
fn store_items(
  connection connection: pog.Connection,
  character_id character_id: Int,
  items items: List(NewItem),
) -> Result(Nil, pog.QueryError) {
  sql.create_character_items(
    connection,
    character_id,
    list.map(items, fn(item) { item.item2_id.value }),
    list.map(items, fn(item) { item.location }),
    list.map(items, fn(item) { item.bag_index }),
    list.map(items, fn(item) { item.stack_count }),
  )
  |> result.replace(Nil)
}

/// One row as the character it holds.
fn character(row: sql.ListCharactersRow) -> Character {
  Character(
    character_id: CharacterId(row.character_id),
    name: row.name,
    gender: row.gender,
    race_id: RaceId(row.race_id),
    class_id: ClassId(row.class_id),
    faction_id: row.faction_id,
    level: row.level,
    path: row.path,
    place: saved_place(
      world_id: row.world_id,
      world_zone_id: row.world_zone_id,
      position_x: row.position_x,
      position_y: row.position_y,
      position_z: row.position_z,
      rotation_yaw: row.rotation_yaw,
      rotation_pitch: row.rotation_pitch,
      rotation_roll: row.rotation_roll,
    ),
    look: store.look(labels: row.look_labels, values: row.look_values),
    bones: row.bones,
    naming: naming(row.needs_rename),
  )
}

/// The place a row saves: `None` for world 0, which is no World row, so its
/// zone, position and facing mean nothing (opcode.0xad).
fn saved_place(
  world_id world_id: Int,
  world_zone_id world_zone_id: Int,
  position_x position_x: Float,
  position_y position_y: Float,
  position_z position_z: Float,
  rotation_yaw rotation_yaw: Float,
  rotation_pitch rotation_pitch: Float,
  rotation_roll rotation_roll: Float,
) -> Option(Place) {
  start_place.place(
    world_id:,
    world_zone_id:,
    x: position_x,
    y: position_y,
    z: position_z,
    facing: Facing(
      yaw: rotation_yaw,
      pitch: rotation_pitch,
      roll: rotation_roll,
    ),
  )
  |> option.from_result
}

/// Whether the row's rename mark is set.
fn naming(needs_rename: Bool) -> Naming {
  use <- bool.guard(needs_rename, NeedsRename)
  NameStands
}

/// Makes the character in one transaction: the account's row lock, which finds
/// no row for an account that does not exist, then the insert, which makes no row
/// once the account has its slots. The name's unique index refusing the row is
/// `NameTaken`, and its rule-0 check refusing it is `NameBreaksRule`.
fn create_character(
  pool pool: pog.Connection,
  account_id account_id: AccountId,
  character character: NewCharacter,
  character_slots character_slots: Int,
) -> Result(CreateAnswer, Nil) {
  let AccountId(account_id) = account_id
  let transaction = fn() {
    in_transaction(pool, fn(connection) {
      use locked <- result.try(sql.lock_account(connection, account_id))
      use <- bool.guard(
        locked.rows == [],
        Ok(pog.Returned(count: 1, rows: [NoAccountRow])),
      )
      use made <- result.try(sql.create_character(
        connection,
        account_id,
        character.name,
        character.gender,
        character.race_id.value,
        character.class_id.value,
        character.faction_id,
        character.path,
        list.map(character.look, fn(entry) { entry.label.value }),
        list.map(character.look, fn(entry) { entry.value }),
        character.bones,
        character_slots,
        start_place.world_id(character.place),
        start_place.world_zone_id(character.place),
        start_place.x(character.place),
        start_place.y(character.place),
        start_place.z(character.place),
        character.level,
        start_place.facing(character.place).yaw,
        start_place.facing(character.place).pitch,
        start_place.facing(character.place).roll,
        character.experience,
      ))
      use Nil <- result.map(case made.rows {
        [row] ->
          store_items(
            connection:,
            character_id: row.character_id,
            items: character.starting_items,
          )
        _ -> Ok(Nil)
      })
      pog.Returned(
        ..made,
        rows: list.map(made.rows, fn(row) { MadeRow(row.character_id) }),
      )
    })
  }
  case attempt(transaction) {
    Ok([MadeRow(character_id:)]) ->
      Ok(CharacterCreated(CharacterId(character_id)))
    Ok([NoAccountRow]) -> Ok(CreateForNoSuchAccount)
    Ok([]) -> Ok(NoFreeSlot)
    Ok(_) -> panic as "one insert of one row makes at most one character"
    Error(Unreachable) -> Error(Nil)
    Error(Refused(constraint:, ..)) if constraint == character_name_unique ->
      Ok(NameTaken)
    Error(Refused(constraint:, ..))
      if constraint == character_name_follows_rule_0
    -> Ok(NameBreaksRule)
    Error(Refused(error:, ..)) | Error(Unexpected(error:)) -> exit_with(error)
  }
}

/// Runs the work on one connection of the pool in a transaction: it commits when
/// the work gives rows and rolls back when it gives an error, which is the
/// error given.
fn in_transaction(
  pool: pog.Connection,
  work: fn(pog.Connection) -> Result(pog.Returned(row), pog.QueryError),
) -> Result(pog.Returned(row), pog.QueryError) {
  pog.transaction(pool, work)
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionQueryError(error) | pog.TransactionRolledBack(error) ->
        error
    }
  })
}

/// The one row a create's transaction gives: the character it made, or the
/// account's lock finding no account.
type CreateRow {
  MadeRow(character_id: Int)
  NoAccountRow
}

/// Deletes the account's character with the id in one statement, which names
/// the account too; `Error(Nil)` when the database is away.
fn delete_character(
  pool pool: pog.Connection,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
) -> Result(DeleteAnswer, Nil) {
  let AccountId(account_id) = account_id
  let CharacterId(character_id) = character_id
  use rows <- result.map(
    query(fn() { sql.delete_character(pool, character_id, account_id) }),
  )
  case rows {
    [_] -> CharacterDeleted
    [] -> NoSuchCharacter
    _ -> panic as "a character id is unique, so a delete removes at most one"
  }
}

/// Gives the account's marked character the name and clears the mark in one
/// update. The name's unique index refusing the row is `NewNameTaken` and its
/// rule-0 check refusing it is `NewNameBreaksRule`; `Error(Nil)` when the
/// database is away.
fn rename_character(
  pool pool: pog.Connection,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  name name: String,
) -> Result(RenameAnswer, Nil) {
  let AccountId(account_id) = account_id
  let CharacterId(character_id) = character_id
  case
    attempt(fn() { sql.rename_character(pool, character_id, account_id, name) })
  {
    Ok([row]) -> Ok(CharacterRenamed(name: row.name))
    Ok([]) -> Ok(store.NotRenamable)
    Ok(_) -> panic as "a character id is unique, so a rename changes at most one"
    Error(Unreachable) -> Error(Nil)
    Error(Refused(constraint:, ..)) if constraint == character_name_unique ->
      Ok(NewNameTaken)
    Error(Refused(constraint:, ..))
      if constraint == character_name_follows_rule_0
    -> Ok(NewNameBreaksRule)
    Error(Refused(error:, ..)) | Error(Unexpected(error:)) -> exit_with(error)
  }
}

/// Why a unit of work on the pool gave no rows.
type Failure {
  /// The pool is not running, no connection can be had or the query timed out.
  Unreachable
  /// The database refused a change for a constraint, whose name and error are
  /// here.
  Refused(constraint: String, error: pog.QueryError)
  /// The database failed the query in a way no request expects, with its error:
  /// a bug in the query or the schema, which `query` ends the worker for. Only
  /// the probe's read of `schema_migration` reads it, to tell a database
  /// without the table, or one it cannot read, from a database that is away.
  Unexpected(error: pog.QueryError)
}

/// Runs one read on the pool and gives its rows, or `Error(Nil)` for the
/// failures that answer `Unavailable`. Any other error is a bug in the query
/// or the schema, and ends the worker.
fn query(
  run: fn() -> Result(pog.Returned(row), pog.QueryError),
) -> Result(List(row), Nil) {
  case attempt(run) {
    Ok(rows) -> Ok(rows)
    Error(Unreachable) -> Error(Nil)
    Error(Refused(error:, ..)) | Error(Unexpected(error:)) -> exit_with(error)
  }
}

/// Runs one unit of work on the pool and gives its rows, or why it gave none:
/// the pool not running, as when it restarts, a connection that cannot be had
/// and a query that timed out are `Unreachable`, a constraint the database
/// refused is `Refused`, and any other error is `Unexpected`, which every
/// caller but the probe's read of the record ends the worker with.
fn attempt(
  run: fn() -> Result(pog.Returned(row), pog.QueryError),
) -> Result(List(row), Failure) {
  case unless_pool_not_running(run) {
    Error(Nil) -> Error(Unreachable)
    Ok(Error(pog.ConnectionUnavailable)) | Ok(Error(pog.QueryTimeout)) ->
      Error(Unreachable)
    Ok(Ok(pog.Returned(rows:, ..))) -> Ok(rows)
    Ok(Error(pog.ConstraintViolated(constraint:, ..) as error)) ->
      Error(Refused(constraint:, error:))
    Ok(Error(pog.PostgresqlError(..) as error))
    | Ok(Error(pog.UnexpectedArgumentCount(..) as error))
    | Ok(Error(pog.UnexpectedArgumentType(..) as error))
    | Ok(Error(pog.UnexpectedResultType(..) as error)) ->
      Error(Unexpected(error:))
  }
}

@external(erlang, "genesis_prime_store_worker_ffi", "unless_pool_not_running")
fn unless_pool_not_running(run: fn() -> a) -> Result(a, Nil)

/// Ends the worker with the error as its exit reason. A query failing in the
/// database or in decoding its rows is a bug in the query or the schema, and
/// the asker gets `EndedBeforeAnswer`.
@external(erlang, "erlang", "exit")
fn exit_with(reason: pog.QueryError) -> a
