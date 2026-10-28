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
////   returning an error; `ask` catches that exit, and only that one, as
////   `Error(Nil)`.
//// - **Failures.** One private `attempt` holds them for every request, so each
////   request maps only its rows. pog's `ConnectionUnavailable` and
////   `QueryTimeout` answer `Unavailable`, and so does the pool not running:
////   pgo's checkout exits with `{noproc, {pgo_pool, checkout, _}}` then, which
////   the worker catches, and only that exit. A constraint the database
////   refused is the request's to map: a create maps its name's unique index to
////   `NameTaken`. Any other error is a bug in the query or the schema: the
////   worker crashes with it, and the asker gets `EndedBeforeAnswer`.
//// - **A create is one transaction.** It takes the account's row lock, so one
////   account's creates run one after another, and then inserts the character
////   unless the account already has its slots, in one statement; the name's
////   uniqueness is the index on `lower(name)`.
//// - **A delete and a rename are one statement each.** Both name the account's
////   id, so another account's character is never touched; a rename also
////   clears the character's mark in the same update, and its name's
////   uniqueness is the same index as a create's.
//// - **The supervisor stopping.** Its workers get its shutdown timeout to end;
////   an asker waiting on one gets `EndedBeforeAnswer`.

import genesis_prime/login/guid
import genesis_prime/service.{type Sent, ToWorker}
import genesis_prime/store.{
  type AccountId, type Answer, type Character, type CharacterId,
  type CreateAnswer, type DeleteAnswer, type FindAccountAnswer,
  type NewCharacter, type RenameAnswer, type Request, Account, AccountFound,
  AccountId, Character, CharacterCreated, CharacterDeleted, CharacterId,
  CharacterRenamed, CreateCharacter, DeleteCharacter, FindAccount,
  ListCharacters, NameStands, NameTaken, NeedsRename, NewNameTaken, NoFreeSlot,
  NoSuchAccount, NoSuchCharacter, RenameCharacter, ToCreateCharacter,
  ToDeleteCharacter, ToFindAccount, ToListCharacters, ToRenameCharacter,
  Unavailable,
}
import genesis_prime/store/sql
import genesis_prime/table/id.{ClassId, RaceId}
import gleam/erlang/process.{type Name}
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import pog

/// What one worker is started with: the ask, and how to answer it.
pub type Job {
  Job(request: Request, reply: fn(Answer) -> Nil)
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
  case
    unless_supervisor_not_running(fn() {
      factory_supervisor.start_child(
        factory_supervisor.get_by_name(store),
        Job(request:, reply:),
      )
    })
  {
    Ok(Ok(started)) -> Ok(ToWorker(pid: started.pid))
    Ok(Error(_)) | Error(Nil) -> Error(Nil)
  }
}

/// Spawns the worker and returns at once, so the supervisor's start call
/// waits for no work; the worker runs its query after.
fn start_worker(job: Job, pool: pog.Connection) -> actor.StartResult(Nil) {
  let pid = process.spawn(fn() { run(job, pool) })
  Ok(actor.Started(pid:, data: Nil))
}

/// Runs the ask's query on the pool, answers the asker and ends.
fn run(job: Job, pool: pog.Connection) -> Nil {
  let answer = case job.request {
    FindAccount(login_name:) ->
      find_account(pool, login_name)
      |> result.map(ToFindAccount)
    ListCharacters(account_id:) ->
      list_characters(pool, account_id)
      |> result.map(ToListCharacters)
    CreateCharacter(account_id:, character:, character_slots:) ->
      create_character(pool:, account_id:, character:, character_slots:)
      |> result.map(ToCreateCharacter)
    DeleteCharacter(account_id:, character_id:) ->
      delete_character(pool:, account_id:, character_id:)
      |> result.map(ToDeleteCharacter)
    RenameCharacter(account_id:, character_id:, name:) ->
      rename_character(pool:, account_id:, character_id:, name:)
      |> result.map(ToRenameCharacter)
  }
  // `Error(Nil)` is the database being away, the failure every request shares.
  job.reply(result.unwrap(answer, Unavailable))
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
    world_id: row.world_id,
    world_zone_id: row.world_zone_id,
    position_x: row.position_x,
    position_y: row.position_y,
    position_z: row.position_z,
    look: store.look(labels: row.look_labels, values: row.look_values),
    bones: row.bones,
    naming: case row.needs_rename {
      True -> NeedsRename
      False -> NameStands
    },
  )
}

/// Makes the character in one transaction: the account's row lock, then the
/// insert, which makes no row once the account has its slots. The name's unique
/// index refusing the row is `NameTaken`.
fn create_character(
  pool pool: pog.Connection,
  account_id account_id: AccountId,
  character character: NewCharacter,
  character_slots character_slots: Int,
) -> Result(CreateAnswer, Nil) {
  let AccountId(account_id) = account_id
  let transaction = fn() {
    pog.transaction(pool, fn(connection) {
      use _locked <- result.try(sql.lock_account(connection, account_id))
      sql.create_character(
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
      )
    })
    |> result.map_error(fn(error) {
      case error {
        pog.TransactionQueryError(error) | pog.TransactionRolledBack(error) ->
          error
      }
    })
  }
  case attempt(transaction) {
    Ok([row]) -> Ok(CharacterCreated(CharacterId(row.character_id)))
    Ok([]) -> Ok(NoFreeSlot)
    Ok(_) -> panic as "one insert of one row makes at most one character"
    Error(Unreachable) -> Error(Nil)
    Error(Refused(constraint: "character_name_unique", ..)) -> Ok(NameTaken)
    Error(Refused(error:, ..)) -> exit_with(error)
  }
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
/// update. The name's unique index refusing the row is `NewNameTaken`;
/// `Error(Nil)` when the database is away.
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
    Error(Refused(constraint: "character_name_unique", ..)) -> Ok(NewNameTaken)
    Error(Refused(error:, ..)) -> exit_with(error)
  }
}

/// Why a unit of work on the pool gave no rows.
type Failure {
  /// The pool is not running, no connection can be had or the query timed out.
  Unreachable
  /// The database refused a change for a constraint, whose name and error are
  /// here.
  Refused(constraint: String, error: pog.QueryError)
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
    Error(Refused(error:, ..)) -> exit_with(error)
  }
}

/// Runs one unit of work on the pool and gives its rows, or why it gave none:
/// the pool not running, as when it restarts, a connection that cannot be had
/// and a query that timed out are `Unreachable`, and a constraint the database
/// refused is `Refused`. Any other error is a bug in the query or the schema,
/// and ends the worker.
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
    | Ok(Error(pog.UnexpectedResultType(..) as error)) -> exit_with(error)
  }
}

@external(erlang, "store_worker_ffi", "unless_supervisor_not_running")
fn unless_supervisor_not_running(run: fn() -> a) -> Result(a, Nil)

@external(erlang, "store_worker_ffi", "unless_pool_not_running")
fn unless_pool_not_running(run: fn() -> a) -> Result(a, Nil)

/// Ends the worker with the error as its exit reason. A query failing in the
/// database or in decoding its rows is a bug in the query or the schema, and
/// the asker gets `EndedBeforeAnswer`.
@external(erlang, "erlang", "exit")
fn exit_with(reason: pog.QueryError) -> a
