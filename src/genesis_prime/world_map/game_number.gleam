//// The numbers the server chooses for a fight, as the content load checks them:
//// the rows of the game_number table (genesis_prime/content/game_number), each a
//// name, a value and its unit, selected into one record the maps and creatures
//// read. The client holds none of them; each row's reason names why its value is
//// what it is (migration 0010).
////
//// ```
//// game_number rows ─▶ select(rows, sight range)
////   a name missing, a name not known, a unit not the name's  ─▶ Refusal
////   leash_range ≤ aggro_range                                ─▶ Refusal
////   aggro_range ≥ the sight range                            ─▶ Refusal
////   aggro_threat ≤ 0, chase_stop_fraction outside (0, 1)     ─▶ Refusal
////   health_regen_fraction outside (0, 1), health_regen_tick_ms < 1  ─▶ Refusal
////   otherwise ─▶ GameNumbers, read by every map and creature of the run, and by
////                a player's connection for its regeneration
//// ```
////
//// - **The aggro range** lies inside sight, so a creature whose ring a player enters
////   is Live, and a player in its ring is one of its viewers
////   (genesis_prime/world_map/sight).
//// - **The leash range** lies outside the aggro range, so a creature at home with a
////   player in its ring does not leash at once.
//// - **The aggro threat** is above 0: an entry of 0 threat is not a foe the client
////   shows hostile (`0x14045a950`), and a target of none is no fight.
//// - **The chase stop fraction** lies strictly between 0 and 1: at 0 the creature
////   stops at the edge of its reach, where the target's first step leaves it, and
////   at 1 it runs onto the target's own place.
//// - **The health regeneration** is the server's choice (text 149418 says only
////   "slowly out of combat"): its fraction lies strictly between 0 and 1, so a
////   tick adds part of the maximum and never all of it, and its tick is at least
////   1 ms, since a tick of 0 would fire again at once (migration 0015).
//// - **Every refusal is collected**, as the other content tables' are
////   (genesis_prime/content); the ranges are checked once every name is there.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// One row of the game_number table as the load reads it.
pub type Row {
  Row(name: String, value: Float, unit: String)
}

/// The numbers of a fight the server chose, each in its unit.
pub type GameNumbers {
  GameNumbers(
    /// How near a ready player comes to a hostile creature's spawn before the
    /// creature fights it, in units.
    aggro_range: Float,
    /// How far from its spawn a creature may run before it gives up the fight and
    /// walks home, in units.
    leash_range: Float,
    /// The threat a player adds by entering a hostile creature's ring.
    aggro_threat: Float,
    /// The share of its reach a creature stops short of its target by, so one step
    /// of the target keeps it in reach.
    chase_stop_fraction: Float,
    /// The share of its maximum health a player regenerates each health tick out
    /// of combat, before HealthRegenMultiplier.
    health_regen_fraction: Float,
    /// The time between a player's health ticks, in milliseconds.
    health_regen_tick_ms: Int,
  )
}

/// Each number the server reads, by name, with its unit.
const expected = [
  #("aggro_range", "units"),
  #("leash_range", "units"),
  #("aggro_threat", "threat"),
  #("chase_stop_fraction", "fraction"),
  #("health_regen_fraction", "fraction"),
  #("health_regen_tick_ms", "ms"),
]

/// The numbers of the rows, or every refusal: a name missing or not known, a unit
/// that is not the name's, a leash range not above the aggro range, an aggro range
/// not below `sight_range`, an aggro threat not above 0 and a chase stop fraction
/// not strictly between 0 and 1.
pub fn select(
  rows rows: List(Row),
  sight_range sight_range: Float,
) -> Result(GameNumbers, List(Refusal)) {
  let unknown =
    list.filter_map(rows, fn(row) {
      case list.key_find(expected, row.name) {
        Error(Nil) ->
          Ok(refused(name: row.name, rule: "the server knows no such number"))
        Ok(unit) if unit != row.unit ->
          Ok(refused(
            name: row.name,
            rule: "its unit is " <> row.unit <> ", not " <> unit,
          ))
        Ok(..) -> Error(Nil)
      }
    })
  let values =
    list.map(rows, fn(row) { #(row.name, row.value) }) |> dict.from_list
  let missing =
    list.filter_map(expected, fn(name_and_unit) {
      case dict.has_key(values, name_and_unit.0) {
        True -> Error(Nil)
        False ->
          Ok(refused(
            name: name_and_unit.0,
            rule: "the table has no such row, which the server reads",
          ))
      }
    })
  case list.append(unknown, missing) {
    [_, ..] as refusals -> Error(refusals)
    [] -> ranges_checked(values:, sight_range:)
  }
}

fn ranges_checked(
  values values: dict.Dict(String, Float),
  sight_range sight_range: Float,
) -> Result(GameNumbers, List(Refusal)) {
  let value = fn(name) { dict.get(values, name) |> result.unwrap(0.0) }
  let numbers =
    GameNumbers(
      aggro_range: value("aggro_range"),
      leash_range: value("leash_range"),
      aggro_threat: value("aggro_threat"),
      chase_stop_fraction: value("chase_stop_fraction"),
      health_regen_fraction: value("health_regen_fraction"),
      health_regen_tick_ms: float.round(value("health_regen_tick_ms")),
    )
  let checks = [
    #(
      numbers.leash_range <=. numbers.aggro_range,
      "leash_range",
      "a leash range of "
        <> float.to_string(numbers.leash_range)
        <> " is not above the aggro range of "
        <> float.to_string(numbers.aggro_range),
    ),
    #(
      numbers.aggro_range >=. sight_range,
      "aggro_range",
      "an aggro range of "
        <> float.to_string(numbers.aggro_range)
        <> " is not below the sight range of "
        <> float.to_string(sight_range),
    ),
    #(
      numbers.aggro_threat <=. 0.0,
      "aggro_threat",
      "an aggro threat of "
        <> float.to_string(numbers.aggro_threat)
        <> " is not above 0",
    ),
    #(
      numbers.chase_stop_fraction <=. 0.0 || numbers.chase_stop_fraction >=. 1.0,
      "chase_stop_fraction",
      "a chase stop fraction of "
        <> float.to_string(numbers.chase_stop_fraction)
        <> " is not between 0 and 1",
    ),
    #(
      numbers.health_regen_fraction <=. 0.0
        || numbers.health_regen_fraction >=. 1.0,
      "health_regen_fraction",
      "a health regen fraction of "
        <> float.to_string(numbers.health_regen_fraction)
        <> " is not between 0 and 1",
    ),
    #(
      numbers.health_regen_tick_ms < 1,
      "health_regen_tick_ms",
      "a health regen tick of "
        <> int.to_string(numbers.health_regen_tick_ms)
        <> " ms is not at least 1",
    ),
  ]
  case
    list.filter_map(checks, fn(check) {
      case check.0 {
        True -> Ok(refused(name: check.1, rule: check.2))
        False -> Error(Nil)
      }
    })
  {
    [] -> Ok(numbers)
    refusals -> Error(refusals)
  }
}

fn refused(name name: String, rule rule: String) -> Refusal {
  Refusal(table: "game_number", row: RowName(name), rule:)
}
