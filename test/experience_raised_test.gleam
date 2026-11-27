//// Raising a player's experience to a target (`genesis_prime/game/experience`
//// `raised`), as the development commands `!level` and `!xp` ask. Expected
//// values come from these places.
//// - `opcode.0x1ac`: the client takes experience only by adding, so a target at
////   or below what the player holds is no raise, and a raise sends the amount
////   added; the source kind 1 is Cheat (`opcode.0x1ac.kind.1`,
////   `CombatFloater.CodeEnumExpReason`).
//// - XpPerLevel minXpForLevel, from the client's rows: level 3 from 1710, 4 from
////   2860, 5 from 4320, 9 from 17330 and 50 from 26360090; GameFormula 145
////   dataint0 makes 50 the highest level.

import fixture_tables
import genesis_prime/game/experience.{
  type NotRaised, type Progress, Already, Credited, GainSent, LevelRose,
  Lowering, Progress, ToExperience, ToLevel,
}
import genesis_prime/shared/level
import genesis_prime/table/id.{XpPerLevelId}
import genesis_prime/table/xp_per_level
import gleam/int
import gleam/list
import gleam/order
import owned_test
import qcheck

fn raised(
  from from: Progress,
  to target: experience.Target,
) -> Result(experience.Credited, NotRaised) {
  experience.raised(progress: from, target:, tables: fixture_tables.shared())
}

pub fn raising_to_a_level_gains_the_difference_to_its_minimum_and_rises_to_it_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(4, 1060, "level 4 starts at 2860, 1060 above 1800"),
      #(9, 15_530, "level 9 starts at 17330, 15530 above 1800"),
    ],
    fn(row) {
      assert raised(
          from: Progress(experience: 1800, level: 3),
          to: ToLevel(row.0),
        )
        == Ok(
          Credited(
            progress: Progress(experience: 1800 + row.1, level: row.0),
            effects: [
              GainSent(gain: row.1, kind: 1, unit_id: 0),
              LevelRose(level: row.0),
            ],
          ),
        )
        as row.2
    },
  )
}

pub fn raising_to_an_experience_gains_the_difference_and_rises_only_across_a_level_test() -> Nil {
  use <- owned_test.run(60_000)
  assert raised(
      from: Progress(experience: 1800, level: 3),
      to: ToExperience(2859),
    )
    == Ok(
      Credited(progress: Progress(experience: 2859, level: 3), effects: [
        GainSent(gain: 1059, kind: 1, unit_id: 0),
      ]),
    )
    as "2859 is one short of level 4's 2860: a gain and no rise"
  assert raised(
      from: Progress(experience: 1800, level: 3),
      to: ToExperience(2860),
    )
    == Ok(
      Credited(progress: Progress(experience: 2860, level: 4), effects: [
        GainSent(gain: 1060, kind: 1, unit_id: 0),
        LevelRose(level: 4),
      ]),
    )
    as "2860 is level 4's minimum: a gain and the rise"
}

pub fn a_target_at_the_held_value_or_level_is_already_and_one_below_is_a_lowering_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        Progress(experience: 1800, level: 3),
        ToExperience(1800),
        Error(Already),
        "the experience held",
      ),
      #(
        Progress(experience: 1800, level: 3),
        ToLevel(3),
        Error(Already),
        "the level held, though its minimum 1710 is below the 1800 held",
      ),
      #(
        Progress(experience: 4320, level: 5),
        ToLevel(3),
        Error(Lowering),
        "a level below the held one",
      ),
      #(
        Progress(experience: 4320, level: 5),
        ToExperience(4000),
        Error(Lowering),
        "an experience below the held one",
      ),
      #(
        Progress(experience: 26_360_090, level: 50),
        ToLevel(50),
        Error(Already),
        "the highest level held",
      ),
      #(
        Progress(experience: 26_360_090, level: 50),
        ToExperience(26_360_090),
        Error(Already),
        "the highest experience held",
      ),
    ],
    fn(row) {
      assert raised(from: row.0, to: row.1) == row.2 as row.3
    },
  )
}

pub fn a_raise_gains_exactly_the_target_minus_the_held_and_never_lowers_test() -> Nil {
  use <- owned_test.run(120_000)
  let tables = fixture_tables.shared()
  let assert Ok(top) = xp_per_level.get(tables:, id: XpPerLevelId(50))
  let held_level = fn(experience) {
    let assert Ok(made) = level.for_experience(tables:, experience:)
    made
  }
  use #(held, by_level, number) <- qcheck.given(qcheck.tuple3(
    qcheck.bounded_int(from: 0, to: top.min_xp_for_level),
    qcheck.bool(),
    qcheck.bounded_int(from: 0, to: top.min_xp_for_level),
  ))
  let progress = Progress(experience: held, level: held_level(held))
  case by_level {
    True -> {
      let target = 1 + number % 50
      let assert Ok(row) = xp_per_level.get(tables:, id: XpPerLevelId(target))
      let result = raised(from: progress, to: ToLevel(target))
      case int.compare(target, progress.level) {
        order.Gt -> {
          let assert Ok(Credited(progress: after, effects:)) = result
          assert after.experience == row.min_xp_for_level
            as "the experience is the level's minimum"
          assert after.level == target
          assert list.contains(
            effects,
            GainSent(gain: row.min_xp_for_level - held, kind: 1, unit_id: 0),
          )
            as "the gain is the target minus the held"
        }
        order.Eq -> {
          assert result == Error(Already)
        }
        order.Lt -> {
          assert result == Error(Lowering)
        }
      }
    }
    False -> {
      let result = raised(from: progress, to: ToExperience(number))
      case int.compare(number, held) {
        order.Gt -> {
          let assert Ok(Credited(progress: after, effects:)) = result
          assert after.experience == number
          assert after.level == held_level(number)
            as "the level is the client's for that experience"
          assert list.contains(
            effects,
            GainSent(gain: number - held, kind: 1, unit_id: 0),
          )
            as "the gain is the target minus the held"
        }
        order.Eq -> {
          assert result == Error(Already)
        }
        order.Lt -> {
          assert result == Error(Lowering)
        }
      }
    }
  }
}
