//// The system clock as a Windows FILETIME, which is how the client reads the
//// server's time (opcode.0x117: "the server's time as a 64-bit Windows
//// FILETIME"). A FILETIME counts 100-nanosecond intervals from the start of the
//// year 1601 in UTC, which is 11,644,473,600 seconds before the Unix epoch
//// (Microsoft's definition of FILETIME and of the Unix epoch's offset from it).

import genesis_prime/connection/clock
import gleam/time/timestamp
import owned_test

pub fn the_unix_epoch_is_a_filetime_of_116444736000000000_test() -> Nil {
  use <- owned_test.run(5000)
  assert clock.filetime_of(unix_seconds: 0, nanoseconds: 0)
    == 116_444_736_000_000_000
    as "11,644,473,600 seconds of 10,000,000 intervals each separate the start of 1601 from the Unix epoch"
}

pub fn a_second_is_10_million_intervals_and_100_nanoseconds_one_test() -> Nil {
  use <- owned_test.run(5000)
  assert clock.filetime_of(unix_seconds: 1, nanoseconds: 0)
    == 116_444_736_000_000_000 + 10_000_000
    as "a FILETIME counts 100-nanosecond intervals, 10,000,000 to the second"
  assert clock.filetime_of(unix_seconds: 0, nanoseconds: 500)
    == 116_444_736_000_000_000 + 5
    as "500 nanoseconds are 5 intervals"
}

pub fn the_system_filetime_is_read_from_the_system_clock_test() -> Nil {
  use <- owned_test.run(5000)
  let before = filetime_of(timestamp.system_time())
  let read = clock.system_filetime()
  let after = filetime_of(timestamp.system_time())
  assert before <= read && read <= after
    as "the clock's reading lies between two readings of the system time"
}

fn filetime_of(time: timestamp.Timestamp) -> Int {
  let #(seconds, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(time)
  clock.filetime_of(unix_seconds: seconds, nanoseconds:)
}
