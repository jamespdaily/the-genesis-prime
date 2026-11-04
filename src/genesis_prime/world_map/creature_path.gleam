//// Where a creature that runs is at any moment: the one straight path it was last
//// sent as a 0x638 of kind 4, and its place along it. The creature keeps it
//// (genesis_prime/world_map/creature_fight), and so does each viewer's connection
//// from the creature's own news (genesis_prime/game/shown), so a player's cast and
//// the creature find the creature at the same place by one function.
////
//// ```
//// creature_fight: chase or home ─▶ toward(from, to, ..) ─▶ Path ─▶ 0x638 [kind 0, kind 4] to its viewers
//// creature and viewer: place_at(path, now) ─▶ the place along it, the end once it is run
//// ```
////
//// - **One straight path of two points**, kind 4 type 0 (straight lines), at the
////   creature's run speed in units a second (`movement_command.kind_4`). The client
////   runs it from the time of the 0x638's kind 0 (`movement_command.kind_0`).
//// - **A path is clipped at the leash circle**: no point of it lies farther from the
////   spawn than `leash_range`, so a creature never runs past the circle it leashes at.
//// - **Time** is the monotonic time of the node in milliseconds, the clock both the
////   creature and its viewers' connections read their inputs at.

import genesis_prime/game/start_place.{type Place}

/// A creature's movement: standing at a place, or running a straight path from
/// `from` to `to`, started at monotonic time `started_ms`, at `speed` units a
/// second.
pub type Path {
  Standing(at: Place)
  Running(from: Place, to: Place, started_ms: Int, speed: Float)
}

/// The circle a creature's paths stay inside: its spawn's place and the leash
/// range (genesis_prime/world_map/game_number).
pub type Circle {
  Circle(centre: Place, radius: Float)
}

/// The place along the path at monotonic time `now_ms`: its start before it began,
/// its end once it is run, and the straight-line point between at `speed`.
pub fn place_at(path path: Path, now_ms now_ms: Int) -> Place {
  case path {
    Standing(at:) -> at
    Running(..) -> todo as "place_at of a running path: the build fills it in"
  }
}

/// The place the path ends at.
pub fn end(path path: Path) -> Place {
  case path {
    Standing(at:) -> at
    Running(to:, ..) -> to
  }
}

/// The path from `from` toward `target` started at `now_ms` at `speed`, ending
/// `stop_short` units before the target and clipped at `circle`; `Standing(from)`
/// when that end is `from` itself.
pub fn toward(
  from from: Place,
  target target: Place,
  stop_short stop_short: Float,
  circle circle: Circle,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Path {
  todo as "toward: the build fills it in"
}

/// The monotonic time the path is run by: `started_ms` plus its length over its
/// speed, or the time a standing path is asked at.
pub fn arrives_ms(path path: Path) -> Int {
  todo as "arrives_ms: the build fills it in"
}
