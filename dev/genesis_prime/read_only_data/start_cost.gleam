//// What it costs a process to start with a variant: the time from starting
//// the process until it has opened the loaded tables and says it is ready.
//// Persistent terms and ETS only look the tables up; owner state copies them
//// into the new process.

import genesis_prime/read_only_data/variant.{type Loaded}

/// The nanoseconds from starting one process until it is ready to read, for
/// one start.
pub fn time_to_ready(loaded: Loaded) -> Int {
  todo as "body in the build commit"
}
