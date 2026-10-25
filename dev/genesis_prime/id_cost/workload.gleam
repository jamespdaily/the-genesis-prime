//// What every variant of the id-cost benchmark hands the harness.

import genesis_prime/id_cost/measurement.{type TermSizes}

/// A variant ready to run: its unit dictionary is built and measured, and
/// `run` reads a stream of messages against it and returns a number that
/// depends on the work done, so the work cannot be skipped.
pub type Prepared {
  Prepared(units_size: TermSizes, run: fn(BitArray) -> Int)
}
