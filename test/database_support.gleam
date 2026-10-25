//// What the database test helper shares across a test run: where the Postgres
//// server is, one template database migrated from `priv/migrations`, one
//// administration pool, and a watcher that drops what the run made when the
//// VM ends however it ends.

import environment
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import pog
import simplifile

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
  let host = result.unwrap(environment.get("PGHOST"), "/tmp")
  let tcp_host = case string.starts_with(host, "/") {
    True -> result.unwrap(environment.get("PGTCPHOST"), "::1")
    False -> host
  }
  let port =
    environment.get("PGPORT")
    |> result.try(int.parse)
    |> result.unwrap(5433)
  Settings(
    host:,
    tcp_host:,
    port:,
    user: result.unwrap(environment.get("PGUSER"), "postgres"),
    password: option.from_result(environment.get("PGPASSWORD")),
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
  let ip_version = case string.contains(settings.tcp_host, ":") {
    True -> pog.Ipv6
    False -> pog.Ipv4
  }
  pog.default_config(pool_name)
  |> pog.host(settings.tcp_host)
  |> pog.port(settings.port)
  |> pog.database(database)
  |> pog.user(settings.user)
  |> pog.password(settings.password)
  |> pog.pool_size(pool_size)
  |> pog.queue_target(5000)
  |> pog.queue_interval(10_000)
  |> pog.ip_version(ip_version)
}

/// The run's shared state, made by the first caller and the same for every
/// later one. The template is built from `priv/migrations/*.sql` in name order.
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

/// Stops a pool as OTP stops any server, which stops its connections.
@external(erlang, "gen_server", "stop")
pub fn stop_pool(pool: Pid) -> Dynamic

/// Runs `create` once per key in this VM; every caller gets the same value.
@external(erlang, "database_support_ffi", "once")
fn once(key: String, create: fn() -> a) -> a

/// An integer no other call in this VM has returned.
@external(erlang, "database_support_ffi", "unique")
pub fn unique() -> Int

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
  let assert Ok(Nil) =
    execute(on: shared, sql: "create database \"" <> shared.template <> "\"")
    as "the template database was not created"
  let assert Ok(migrations) = migration_files()
    as "priv/migrations could not be read"
  list.each(migrations, fn(file) {
    let assert Ok(_) =
      psql(with: settings, database: shared.template, arguments: [
        "--single-transaction",
        "-f",
        file,
      ])
      as "a migration did not apply to the template"
    Nil
  })
  shared
}

fn migration_files() -> Result(List(String), simplifile.FileError) {
  use names <- result.map(simplifile.read_directory("priv/migrations"))
  names
  |> list.filter(string.ends_with(_, ".sql"))
  |> list.sort(string.compare)
  |> list.map(fn(name) { "priv/migrations/" <> name })
}

fn psql(
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

fn psql_environment(settings: Settings) -> List(#(String, String)) {
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

@external(erlang, "database_support_ffi", "run_command")
fn run_command(
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
