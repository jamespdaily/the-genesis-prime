//// The clock a step reads (`genesis_prime/step`): `Now.filetime` as the Unix
//// milliseconds the quest resets are counted in. Expected values come from the
//// calendar and from the FILETIME definition: it counts 100-nanosecond
//// intervals from 1601-01-01, and 11,644,473,600 seconds (369 years, 89 of
//// them leap) lie between that and 1970-01-01, so the Unix epoch is
//// 116,444,736,000,000,000 intervals in. 2025-04-24 20:26:40 UTC is 1,745,526,400
//// Unix seconds, read off a calendar.

import genesis_prime/step.{Now}
import owned_test

pub fn the_filetime_of_the_unix_epoch_is_unix_millisecond_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert step.unix_milliseconds(Now(
      monotonic_ms: 0,
      filetime: 116_444_736_000_000_000,
    ))
    == 0
    as "the Unix epoch is 11,644,473,600 seconds after the FILETIME epoch"
}

pub fn a_filetime_is_taken_as_whole_unix_milliseconds_test() -> Nil {
  use <- owned_test.run(5000)
  assert step.unix_milliseconds(Now(
      monotonic_ms: 7,
      filetime: 133_900_000_000_000_000,
    ))
    == 1_745_526_400_000
    as "2025-04-24 20:26:40 UTC, whatever the monotonic clock says"
  assert step.unix_milliseconds(Now(
      monotonic_ms: 7,
      filetime: 116_444_736_000_000_000 + 25_000,
    ))
    == 2
    as "a millisecond is 10,000 intervals, and the part of one left over is dropped"
}
