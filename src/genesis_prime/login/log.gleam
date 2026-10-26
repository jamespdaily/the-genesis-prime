//// What the login writes to Erlang's logger. Every line carries the account
//// it is about as metadata, and never a password, a verifier or a key.

/// An event of a login the server expects, such as a client that logged in:
/// info level.
@external(erlang, "genesis_prime_login_ffi", "log_info")
pub fn info(message message: String, account account: String) -> Nil

/// An outside failure the server recovered from, such as a client that
/// refused to prove its password: warning level.
@external(erlang, "genesis_prime_login_ffi", "log_warning")
pub fn warning(message message: String, account account: String) -> Nil
