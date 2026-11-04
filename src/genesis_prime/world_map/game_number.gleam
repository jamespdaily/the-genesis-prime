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
////   otherwise ─▶ GameNumbers, read by every map and creature of the run
//// ```
////
//// - **The aggro range** lies inside sight, so a creature whose ring a player enters
////   is Live, and a player in its ring is one of its viewers
////   (genesis_prime/world_map/sight).
//// - **The leash range** lies outside the aggro range, so a creature at home with a
////   player in its ring does not leash at once.
//// - **Every refusal is collected**, as the other content tables' are
////   (genesis_prime/content); the ranges are checked once every name is there.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import gleam/dict
import gleam/float
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
  )
}

/// Each number the server reads, by name, with its unit.
const expected = [
  #("aggro_range", "units"),
  #("leash_range", "units"),
  #("aggro_threat", "threat"),
  #("chase_stop_fraction", "fraction"),
]

/// The numbers of the rows, or every refusal: a name missing or not known, a unit
/// that is not the name's, a leash range not above the aggro range, and an aggro
/// range not below `sight_range`.
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
    )
  let leash = case numbers.leash_range <=. numbers.aggro_range {
    True -> [
      refused(
        name: "leash_range",
        rule: "a leash range of "
          <> float.to_string(numbers.leash_range)
          <> " is not above the aggro range of "
          <> float.to_string(numbers.aggro_range),
      ),
    ]
    False -> []
  }
  let sight = case numbers.aggro_range >=. sight_range {
    True -> [
      refused(
        name: "aggro_range",
        rule: "an aggro range of "
          <> float.to_string(numbers.aggro_range)
          <> " is not below the sight range of "
          <> float.to_string(sight_range),
      ),
    ]
    False -> []
  }
  case list.append(leash, sight) {
    [] -> Ok(numbers)
    refusals -> Error(refusals)
  }
}

fn refused(name name: String, rule rule: String) -> Refusal {
  Refusal(table: "game_number", row: RowName(name), rule:)
}
