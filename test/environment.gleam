//// Reads the environment for tests that need the machine's client files.

/// The value of an environment variable, or an error when it is not set.
@external(erlang, "environment_ffi", "get")
pub fn get(name: String) -> Result(String, Nil)
