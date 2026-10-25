//// The server's entry point.

import genesis_prime/server
import gleam/erlang/process

/// Starts the server's supervision tree, then keeps the calling process alive
/// while the tree runs.
pub fn main() -> Nil {
  let assert Ok(_) = server.start()
    as "the server's supervision tree did not start"
  process.sleep_forever()
}
