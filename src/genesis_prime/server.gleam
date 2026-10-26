//// The top of the server's supervision tree. Every process the server runs
//// is started under it.

import genesis_prime/database/pool
import genesis_prime/shutdown
import genesis_prime/table/loader/store
import gleam/erlang/reference.{type Reference}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Builder, type Supervisor}
import gleam/result

/// The top supervisor before any child is added: one for one, so a child that
/// fails is restarted alone, and 3 restarts in 5 seconds, the server's choice
/// for its top level: a fault that survives three rebuilds from storage in
/// that time is not transient, so the whole server stops and its caller sees
/// it. A test that plants children under the same settings starts from it.
pub fn supervisor() -> Builder {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
}

/// The top supervisor with the database pool as its first child, so the pool
/// starts before every child added after it and stops after them. A rebuilt
/// pool keeps the name in `pool_settings`, so a child that queries through
/// that name carries on across a restart. `start` starts it, and a test that
/// plants children after the pool starts from it.
pub fn supervisor_with_pool(pool_settings: pool.Settings) -> Builder {
  supervisor() |> static_supervisor.add(pool.supervised(pool_settings))
}

/// What the game tables are loaded from: the folder of the client's `.tbl`
/// files, the tables to read from it, the rows the server requires of them,
/// and the key the loaded tables' persistent terms are stored under.
pub type TableSettings {
  TableSettings(
    key: Reference,
    folder: String,
    entries: List(store.Entry),
    requirements: List(store.Requirement),
  )
}

/// Everything the tree is started with, each made once by whoever starts it.
pub type Settings {
  Settings(
    pool: pool.Settings,
    tables: TableSettings,
    shutdown: shutdown.Settings,
  )
}

/// Why the tree did not start.
pub type StartError {
  /// A game table could not be loaded, so nothing was started.
  TablesNotLoaded(store.LoadError)
  /// The top supervisor or one of its children did not start.
  TreeNotStarted(actor.StartError)
}

/// A sentence that says why the tree did not start, for the message the
/// server stops with.
pub fn describe(error: StartError) -> String {
  case error {
    TablesNotLoaded(error) ->
      "a game table did not load: " <> store.describe(error)
    TreeNotStarted(actor.InitTimeout) ->
      "the supervision tree did not start in time"
    TreeNotStarted(actor.InitFailed(reason)) ->
      "the supervision tree did not start: " <> reason
    TreeNotStarted(actor.InitExited(_)) ->
      "a process of the supervision tree ended as it started"
  }
}

/// Loads the game tables, then starts the top supervisor with the database
/// pool as its first child and the shutdown coordinator after it, and every
/// other child the server runs, each added here with its restart and shutdown
/// settings. The tables load first, once, so a child that reads them is given
/// them as a start argument; a load that fails starts nothing. The pool opens
/// its connections in the background, so the tree starts whether or not
/// Postgres is reachable.
pub fn start(
  settings: Settings,
) -> Result(actor.Started(Supervisor), StartError) {
  let tables = settings.tables
  use loaded <- result.try(
    store.load(
      under: tables.key,
      from: tables.folder,
      entries: tables.entries,
      requirements: tables.requirements,
    )
    |> result.map_error(TablesNotLoaded),
  )
  case
    supervisor_with_pool(settings.pool)
    |> static_supervisor.add(shutdown.supervised(settings.shutdown))
    |> static_supervisor.start
  {
    Ok(started) -> Ok(started)
    Error(error) -> {
      store.unload(loaded)
      Error(TreeNotStarted(error))
    }
  }
}
