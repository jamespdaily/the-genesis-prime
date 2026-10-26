//// What the connection processes write to Erlang's logger. Every line carries
//// the peer's address as metadata, and never a password or session key.

/// An event of a connection's life that the server expects, such as a client
/// leaving: logged at info level.
@external(erlang, "genesis_prime_socket_ffi", "log_info")
pub fn info(message message: String, peer peer: String) -> Nil

/// An outside failure the server recovered from, such as a client that broke
/// a limit: logged at warning level.
@external(erlang, "genesis_prime_socket_ffi", "log_warning")
pub fn warning(message message: String, peer peer: String) -> Nil
