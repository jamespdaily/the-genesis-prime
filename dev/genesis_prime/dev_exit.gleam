//// How a dev tool's `main` stops the program with an exit status, after its
//// output is written. OTP's `erlang:halt/1` flushes the output first, and no
//// Gleam library stops the VM with a status.

/// Stops the VM with the exit status; the status 0 is success.
@external(erlang, "erlang", "halt")
pub fn halt(status: Int) -> Nil
