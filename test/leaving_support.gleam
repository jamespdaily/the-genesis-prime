//// What the tests' game connections try when the store gives no answer to a
//// leaving player's save.

import genesis_prime/game/leaving_save.{type Retries, Retries}

/// The server's ladder (genesis_prime `game`): 20 s to try, waits of 1, 2, 4
/// and 8 s, then 10 s.
pub fn retries() -> Retries {
  Retries(
    within_ms: 20_000,
    waits_ms: [1000, 2000, 4000, 8000],
    then_ms: 10_000,
  )
}
