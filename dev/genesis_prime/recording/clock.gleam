//// The clock a recording's times are read from: Erlang's monotonic clock, which
//// never goes backwards while the node runs. Its values have no meaning of
//// their own and can be negative, so a time is always the difference of two
//// readings.

type Unit {
  Microsecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: Unit) -> Int

/// The monotonic clock's reading in microseconds.
pub fn microseconds() -> Int {
  monotonic_time(Microsecond)
}
