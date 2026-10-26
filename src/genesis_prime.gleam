//// The server's entry point.

import envoy
import genesis_prime/database/pool
import genesis_prime/server
import gleam/erlang/process

/// Starts the server's supervision tree, then keeps the calling process alive
/// while the tree runs. The database pool's settings come from PGHOST, PGPORT,
/// PGUSER, PGDATABASE and PGPASSWORD; the server stops at once, saying which
/// is missing or wrong, when one it needs is.
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
  let assert Ok(_) = server.start(pool_settings)
    as "the server's supervision tree did not start"
  process.sleep_forever()
}
