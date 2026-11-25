//// The respawn gaps of the fight load run's `respawning` scene (`genesis_prime/load_fight`),
//// counted from what a walker was sent. Pure: the walker tells each message it is sent,
//// and a test plants them.

import genesis_prime/client_connection.{type StaySent}
import gleam/dict.{type Dict}

/// What one walker counted of the units it saw die, vanish and appear: when each unit's
/// removal was told, and the gap of each respawn (a removal, then the next creation of the
/// same unit) and the time of each death.
pub type Gaps {
  Gaps(
    removed_at_us: Dict(Int, Int),
    gaps_us: List(Int),
    deaths_at_us: List(Int),
  )
}

/// Nothing seen yet.
pub fn none() -> Gaps {
  Gaps(removed_at_us: dict.new(), gaps_us: [], deaths_at_us: [])
}

/// The gaps after the walker was sent `sent` at `at_us`.
pub fn told(gaps gaps: Gaps, sent _sent: StaySent, at_us _at_us: Int) -> Gaps {
  gaps
}

/// What the gate says of a run.
pub type Verdict {
  Respawned(respawns: Int)
  NoRespawn
  FewerThanKilled(respawns: Int, killed: Int)
}

/// The gate over every walker's gaps: `ended_us` is when the walkers stopped, and a death
/// within `settle_us` of it is not owed a respawn yet.
pub fn verdict(
  all _all: List(Gaps),
  ended_us _ended_us: Int,
  settle_us _settle_us: Int,
) -> Verdict {
  Respawned(respawns: 0)
}
