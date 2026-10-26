//// The server's entry point.

import envoy
import genesis_prime/database/pool
import genesis_prime/server
import genesis_prime/telemetry/log
import genesis_prime/telemetry/snapshot
import gleam/erlang/process

/// Starts the server's supervision tree, then keeps the calling process alive
/// while the tree runs. The database pool's settings come from PGHOST, PGPORT,
/// PGUSER, PGDATABASE and PGPASSWORD; the server stops at once, saying which
/// is missing or wrong, when one it needs is. Debug lines are written when
/// GENESIS_DEBUG is 1, and not otherwise.
pub fn main() -> Nil {
  let pool_settings = case
    pool.from_environment(
      name: process.new_name("database_pool"),
      get: envoy.get,
    )
  {
    Ok(settings) -> settings
    Error(error) -> panic as pool.describe(error)
  }
  log.configure(debug: envoy.get("GENESIS_DEBUG") == Ok("1"))
  let snapshot_settings = snapshot.settings(process.new_name("snapshot"))
  let assert Ok(_) = server.start(pool_settings, snapshot_settings)
    as "the server's supervision tree did not start"
  process.sleep_forever()
}
