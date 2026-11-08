//// What the database test helper shares across a test run: where the Postgres
//// server is, one template database migrated from `priv/migrations` by
//// `dev/apply_migrations.sh` (the script `./check` and the play database use
//// too, so a database a test makes is migrated and recorded the one way), one
//// administration pool, and a watcher that drops what the run made when the
//// VM ends however it ends, except when it is killed with its process group
//// and the watcher with it: the next run's `sweep` drops what that run left.

import envoy
import genesis_prime/step/runtime
import gleam/bool
import gleam/erlang/process.{type Name}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import pog

/// Where the Postgres server is. Read from PGHOST, PGPORT, PGUSER and
/// PGPASSWORD with the defaults `./check` uses: the socket directory /tmp,
/// port 5433 and user postgres. A socket directory is reached over TCP at
/// PGTCPHOST (default ::1), because pog connects over TCP only.
pub type Settings {
  Settings(
    host: String,
    tcp_host: String,
    port: Int,
    user: String,
    password: Option(String),
  )
}

/// What one run of the test suite owns in Postgres. `run` begins the name of
/// every database the run creates, `template` is the migrated template and
/// `admin` is a pool on the `postgres` database for creating and dropping.
pub type Shared {
  Shared(
    settings: Settings,
    run: String,
    template: String,
    admin: pog.Connection,
  )
}

/// A program that did not run or did not end well, with what it printed.
pub type CommandFailed {
  CommandFailed(output: String)
}

/// Reads the server's address from the environment.
pub fn settings() -> Settings {
  let host = result.unwrap(envoy.get("PGHOST"), "/tmp")
  let tcp_host = case string.starts_with(host, "/") {
    True -> result.unwrap(envoy.get("PGTCPHOST"), "::1")
    False -> host
  }
  let port =
    envoy.get("PGPORT")
    |> result.try(int.parse)
    |> result.unwrap(5433)
  Settings(
    host:,
    tcp_host:,
    port:,
    user: result.unwrap(envoy.get("PGUSER"), "postgres"),
    password: option.from_result(envoy.get("PGPASSWORD")),
  )
}

/// The configuration of a pool of `pool_size` connections to one database.
/// Waiting for a connection is allowed to take seconds, so a busy run queues
/// instead of dropping a request.
pub fn config(
  for settings: Settings,
  database database: String,
  pool_name pool_name: Name(pog.Message),
  pool_size pool_size: Int,
) -> pog.Config {
  pog.default_config(pool_name)
  |> connect_to(settings, database:)
  |> pog.pool_size(pool_size)
  |> pog.queue_target(5000)
  |> pog.queue_interval(10_000)
}

/// The pool configuration with its connection part set to the Postgres server
/// `settings` describe and the database: host, port, database, user, password
/// and internet protocol. The pool's sizes are the configuration's own.
pub fn connect_to(
  config config: pog.Config,
  settings settings: Settings,
  database database: String,
) -> pog.Config {
  let ip_version = case string.contains(settings.tcp_host, ":") {
    True -> pog.Ipv6
    False -> pog.Ipv4
  }
  config
  |> pog.host(settings.tcp_host)
  |> pog.port(settings.port)
  |> pog.database(database)
  |> pog.user(settings.user)
  |> pog.password(settings.password)
  |> pog.ip_version(ip_version)
}

/// The run's shared state, made by the first caller and the same for every
/// later one. The template is built from `priv/migrations/*.sql` in name order, recorded.
pub fn shared() -> Shared {
  once("shared", fn() { start_for_the_run(create_shared) })
}

/// Runs one statement as the administrator, on the `postgres` database.
pub fn execute(
  on shared: Shared,
  sql sql: String,
) -> Result(Nil, pog.QueryError) {
  pog.query(sql)
  |> pog.timeout(60_000)
  |> pog.execute(on: shared.admin)
  |> result.replace(Nil)
}

/// A database of its own for one test: a copy of the migrated template, with
/// a name no other test has. The run's watcher drops it when the VM ends.
pub fn new_database(on shared: Shared) -> String {
  new_empty_database(
    on: shared,
    options: "template \"" <> shared.template <> "\"",
  )
}

/// A migrated database of its own for one test, made with `template0`, the
/// libc locale provider and the given LC_COLLATE and LC_CTYPE (as
/// `createdb --locale` sets both), so a test can show what the schema does on
/// a locale other than the server's. The run's watcher drops it when the VM
/// ends.
pub fn new_database_with_locale(
  on shared: Shared,
  locale locale: String,
) -> String {
  let name =
    new_empty_database(
      on: shared,
      options: "template template0 encoding 'UTF8' locale_provider libc lc_collate '"
        <> locale
        <> "' lc_ctype '"
        <> locale
        <> "'",
    )
  let assert Ok(_) =
    migrate(with: shared.settings, database: name, arguments: [])
    as "the migrations did not apply to the database"
  name
}

/// A database of its own made with `options` after its name in `create
/// database` (a template, a locale, or nothing for the server's default
/// template). The run's watcher drops it when the VM ends.
pub fn new_empty_database(
  on shared: Shared,
  options options: String,
) -> String {
  let name = unused_name(on: shared)
  create_database(on: shared, name:, options:)
  name
}

/// A database name no other test has, for a database the test makes later with
/// `create_database`.
pub fn unused_name(on shared: Shared) -> String {
  shared.run <> "_" <> int.to_string(runtime.unique_id())
}

/// Makes the database `name`, which `unused_name` gave, with `options` after
/// its name in `create database`. The run's watcher drops it when the VM ends.
pub fn create_database(
  on shared: Shared,
  name name: String,
  options options: String,
) -> Nil {
  let assert Ok(Nil) =
    execute(on: shared, sql: "create database \"" <> name <> "\" " <> options)
    as "a database was not made"
  Nil
}

/// Runs `dev/apply_migrations.sh` on the database, with `arguments` before the
/// database's name, as the script is run from a shell.
pub fn migrate(
  with settings: Settings,
  database database: String,
  arguments arguments: List(String),
) -> Result(String, CommandFailed) {
  run_command(
    "bash",
    ["dev/apply_migrations.sh", ..list.append(arguments, [database])],
    psql_environment(settings),
  )
}

/// Drops the databases that runs which ended left behind: those named
/// `genesis_test_<pid>_...` whose pid no program on this machine holds. A run
/// killed with its process group takes its watcher with it, so nothing else
/// would drop them. A pid held by any program is kept, because its run may be
/// going in another worktree.
pub fn sweep(on shared: Shared) -> Nil {
  let assert Ok(listed) =
    psql(with: shared.settings, database: "postgres", arguments: [
      "-At",
      "-c",
      "select datname from pg_database where datname like 'genesis\\_test\\_%'",
    ])
    as "the list of databases was not read"
  let assert Ok(programs) = run_command("ps", ["-A", "-o", "pid="], [])
    as "the running programs were not listed"
  let live_pids =
    string.split(programs, "\n")
    |> list.filter_map(fn(line) { int.parse(string.trim(line)) })
  string.split(listed, "\n")
  |> list.map(string.trim)
  |> abandoned(live_pids:)
  |> list.each(drop_abandoned(on: shared, name: _))
}

/// Of these database names, those of runs that ended: named
/// `genesis_test_<pid>_<rest>`, with a plain positive pid that is not in
/// `live_pids`. Any other name is not a run's, so it is never chosen.
pub fn abandoned(
  names names: List(String),
  live_pids live_pids: List(Int),
) -> List(String) {
  list.filter(names, fn(name) {
    case run_pid(name) {
      Ok(pid) -> !list.contains(live_pids, pid)
      Error(Nil) -> False
    }
  })
}

/// The pid in a run's database name, or an error for a name that is not a
/// run's.
fn run_pid(name: String) -> Result(Int, Nil) {
  case name {
    "genesis_test_" <> rest -> {
      use #(text, after) <- result.try(string.split_once(rest, "_"))
      use pid <- result.try(int.parse(text))
      case pid > 0 && int.to_string(pid) == text && after != "" {
        True -> Ok(pid)
        False -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

/// Drops one database of a run that ended. A run that started at the same
/// moment may be dropping the same database, so a failed drop is only a
/// failure when the database is still there.
fn drop_abandoned(on shared: Shared, name name: String) -> Nil {
  let dropped =
    execute(
      on: shared,
      sql: "drop database if exists \""
        <> string.replace(name, "\"", "\"\"")
        <> "\" with (force)",
    )
  use <- bool.guard(when: result.is_ok(dropped), return: Nil)
  case database_exists(on: shared, name:) {
    False -> Nil
    True ->
      panic as { "a database of a run that ended was not dropped: " <> name }
  }
}

/// Whether the server holds a database called `name`.
pub fn database_exists(on shared: Shared, name name: String) -> Bool {
  let assert Ok(output) =
    psql(with: shared.settings, database: "postgres", arguments: [
      "-At",
      "-c",
      "select count(*) from pg_database where datname = '"
        <> string.replace(name, "'", "''")
        <> "'",
    ])
    as "the list of databases was not read"
  string.trim(output) == "1"
}

/// Runs `work` in a process that lives as long as the VM and is linked to
/// nothing, so a pool the work starts outlives the test that asked. Returns
/// what the work returned, and panics at once when the work crashes.
fn start_for_the_run(work: fn() -> a) -> a {
  let reply = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      process.send(reply, work())
      process.sleep_forever()
    })
  let monitor = process.monitor(worker)
  let outcome =
    process.new_selector()
    |> process.select_map(reply, Ok)
    |> process.select_specific_monitor(monitor, fn(_down) { Error(Nil) })
    |> process.selector_receive(within: 60_000)
  case outcome {
    Ok(Ok(value)) -> value
    Ok(Error(Nil)) -> panic as "the run's shared database state did not start"
    Error(Nil) ->
      panic as "the run's shared database state did not start within 60 seconds"
  }
}

/// Runs `create` once per key in this VM; every caller gets the same value.
@external(erlang, "database_support_ffi", "once")
pub fn once(key: String, create: fn() -> a) -> a

fn create_shared() -> Shared {
  let settings = settings()
  let run = "genesis_test_" <> run_identifier()
  open_watcher(
    "cat >/dev/null
exec >/dev/null 2>&1
for database in $(psql -X -At -d postgres -c \"select datname from pg_database where datname like '$1%'\"); do
  psql -X -q -d postgres -c \"drop database if exists \\\"$database\\\" with (force)\"
done",
    [run],
    psql_environment(settings),
  )
  let assert Ok(_) =
    psql(with: settings, database: "postgres", arguments: ["-c", "select 1"])
    as "Postgres is not reachable: check PGHOST, PGPORT, PGUSER and PGPASSWORD"
  let pool_name = process.new_name("database_support_admin")
  let assert Ok(started) =
    pog.start(config(
      for: settings,
      database: "postgres",
      pool_name:,
      pool_size: 4,
    ))
    as "the administration pool did not start"
  let shared =
    Shared(settings:, run:, template: run <> "_template", admin: started.data)
  sweep(on: shared)
  let assert Ok(Nil) =
    execute(on: shared, sql: "create database \"" <> shared.template <> "\"")
    as "the template database was not created"
  let assert Ok(_) =
    migrate(with: settings, database: shared.template, arguments: [])
    as "the migrations did not apply to the template"
  shared
}

/// Runs `psql` on the database, stopping at the first error, with `arguments`
/// after its own, and gives what it printed.
pub fn psql(
  with settings: Settings,
  database database: String,
  arguments arguments: List(String),
) -> Result(String, CommandFailed) {
  run_command(
    "psql",
    list.append(
      ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", database],
      arguments,
    ),
    psql_environment(settings),
  )
}

/// The environment that points a program at the Postgres server, as `psql` reads it.
pub fn psql_environment(settings: Settings) -> List(#(String, String)) {
  let base = [
    #("PGHOST", settings.host),
    #("PGPORT", int.to_string(settings.port)),
    #("PGUSER", settings.user),
  ]
  case settings.password {
    option.Some(password) -> [#("PGPASSWORD", password), ..base]
    option.None -> base
  }
}

@external(erlang, "database_support_ffi", "run_identifier")
fn run_identifier() -> String

/// Runs a program to its end with these arguments and environment, and gives
/// what it printed, or what it printed when it failed or was not found.
@external(erlang, "database_support_ffi", "run_command")
pub fn run_command(
  program: String,
  arguments: List(String),
  environment: List(#(String, String)),
) -> Result(String, CommandFailed)

@external(erlang, "database_support_ffi", "open_watcher")
fn open_watcher(
  script: String,
  arguments: List(String),
  environment: List(#(String, String)),
) -> Nil
