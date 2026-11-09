//// The numbers the server chooses for a fight, as the content load checks them:
//// the rows of the game_number table (genesis_prime/content/game_number), each a
//// name, a value and its unit, selected into one record the maps and creatures
//// read. The client holds none of them; each row's reason names why its value is
//// what it is (migration 0010).
////
//// ```
//// game_number rows ─▶ select(rows, sight range)
////   a name missing or not known                              ─▶ Refusal
////   leash_range ≤ aggro_range                                ─▶ Refusal
////   aggro_range ≥ the sight range                            ─▶ Refusal
////   otherwise ─▶ GameNumbers, read by every map and creature of the run, and by
////                a player's connection for its health regeneration
//// ```
////
//// - **The aggro range** lies inside sight, so a creature whose ring a player enters
////   is Live, and a player in its ring is one of its viewers
////   (genesis_prime/world_map/sight).
//// - **The leash range** lies outside the aggro range, so a creature at home with a
////   player in its ring does not leash at once.
//// - **The aggro threat** is above 0 and **the chase stop fraction** lies strictly
////   between 0 and 1, each held by the table (`game_number_aggro_threat_is_positive`,
////   `game_number_chase_stop_fraction_is_between_0_and_1`, migration 0014): an
////   entry of 0 threat is not a foe the client shows hostile (`0x14045a950`), and a
////   target of none is no fight; at a fraction of 0 the creature stops at the edge
////   of its reach, where the target's first step leaves it, and at 1 it runs onto
////   the target's own place.
//// - **The health regeneration** is the server's choice (text 149418 says only
////   "slowly out of combat"). Its fraction lies strictly between 0 and 1, so a tick
////   adds part of the maximum and never all of it, and its tick is a whole number of
////   milliseconds of at least 1, since a tick of 0 would fire again at once, each
////   held by the table (`game_number_health_regen_fraction_is_between_0_and_1`,
////   `game_number_health_regen_tick_ms_is_a_whole_positive_ms`, migration 0015).
//// - **The refill time of Interrupt Armor** is a whole number of milliseconds above 0, held
////   by the table (`game_number_interrupt_armor_refill_ms_is_a_whole_positive_ms`,
////   migration 0016): the creature starts a timer of that many, and the client holds no
////   value for it, so it is a server choice that states its reason.
//// - **A kill's experience** is the fraction of the creature's level's base quest
////   experience, above 0 and at most 1, times a level-gap multiplier of 0 or more
////   (`game_number_kill_experience_fraction_is_above_0_up_to_1`,
////   `game_number_kill_experience_multiplier_is_not_negative`, migration 0021). The
////   client holds no kill formula, so each is a server choice that states its reason,
////   and the creature's Creature2Difficulty `clusterContributionValueDifficulty` that
////   weighs it is a client value no client code shows feeding experience.
//// - **The unit of each name** is the table's: `game_number_name_has_its_unit`, a
////   foreign key to `game_number_name`, refuses a row whose unit is not its name's
////   and a name nobody listed (migration 0014).
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
    /// The share of its maximum health a player regenerates each health tick out
    /// of combat, before HealthRegenMultiplier.
    health_regen_fraction: Float,
    /// The time between a player's health ticks, in milliseconds.
    health_regen_tick_ms: Int,
    /// How long a creature's Interrupt Armor takes to return to its maximum after the
    /// last point destroyed, in whole milliseconds (migration 0016).
    interrupt_armor_refill_ms: Int,
    /// The share of the base quest experience of a creature's level that a kill
    /// gives before the creature's difficulty weight and the level gap's multiplier
    /// (migration 0021).
    kill_experience_fraction: Float,
    /// The multiplier of a kill's experience for the creature's level minus the
    /// player's, from 4 or more below to 4 or more above: nine numbers, the gap -4
    /// first and the gap 4 last (migration 0021).
    kill_experience_multipliers: List(Float),
  )
}

/// The names of the nine level-gap multipliers, the creature 4 or more levels below
/// the player first and 4 or more above last.
const kill_experience_multiplier_names = [
  "kill_experience_multiplier_below_4",
  "kill_experience_multiplier_below_3",
  "kill_experience_multiplier_below_2",
  "kill_experience_multiplier_below_1",
  "kill_experience_multiplier_same",
  "kill_experience_multiplier_above_1",
  "kill_experience_multiplier_above_2",
  "kill_experience_multiplier_above_3",
  "kill_experience_multiplier_above_4",
]

/// Each number the server reads, by name.
fn expected() -> List(String) {
  list.append(
    [
      "aggro_range",
      "leash_range",
      "aggro_threat",
      "chase_stop_fraction",
      "health_regen_fraction",
      "health_regen_tick_ms",
      "interrupt_armor_refill_ms",
      "kill_experience_fraction",
    ],
    kill_experience_multiplier_names,
  )
}

/// The numbers of the rows, or every refusal: a name missing or not known, a
/// leash range not above the aggro range and an aggro range not below
/// `sight_range`.
pub fn select(
  rows rows: List(Row),
  sight_range sight_range: Float,
) -> Result(GameNumbers, List(Refusal)) {
  let unknown =
    list.filter_map(rows, fn(row) {
      case list.contains(expected(), row.name) {
        False ->
          Ok(refused(name: row.name, rule: "the server knows no such number"))
        True -> Error(Nil)
      }
    })
  let values =
    list.map(rows, fn(row) { #(row.name, row.value) }) |> dict.from_list
  let missing =
    list.filter_map(expected(), fn(name) {
      case dict.has_key(values, name) {
        True -> Error(Nil)
        False ->
          Ok(refused(
            name:,
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
      interrupt_armor_refill_ms: float.round(value("interrupt_armor_refill_ms")),
      kill_experience_fraction: value("kill_experience_fraction"),
      kill_experience_multipliers: list.map(
        kill_experience_multiplier_names,
        value,
      ),
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
