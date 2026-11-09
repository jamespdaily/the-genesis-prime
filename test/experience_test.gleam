//// A kill's credit on the game connection (`genesis_prime/game/experience`,
//// `genesis_prime/game/connection/experience`), on the client's tables. Expected
//// values come from these places.
//// - `opcode.0x1ac` and `opcode.0x1ac.fields`: the experience message is five 32-bit
////   values, the amount the client adds to its experience, the rest experience used, a
////   third amount, the source kind and the source unit. The kind is 2 for a kill
////   (`CombatFloater.CodeEnumExpReason`, KillCreature).
//// - The amount is the server's choice (Jim, 2026-11-08): `round(XpPerLevel.
////   baseQuestXpPerLevel[creature level, at most 50] x 0.25 x Creature2Difficulty.
////   clusterContributionValueDifficulty x the multiplier of the creature's level minus the
////   player's, clamped to -4..4)`, the multipliers being 0, 0.25, 0.5, 0.75, 1, 1.1, 1.2,
////   1.3 and 1.4. The client's rows: XpPerLevel baseQuestXpPerLevel 100 for levels 1 and 2,
////   152 for 3 to 5, 245 for 6 to 8, 537 for 9 and 10, 75000 for 50; Creature2 73464 has
////   Creature2Difficulty 1 (clusterContributionValueDifficulty 0.2), Creature2 11467 has
////   Creature2Difficulty 2 (0.3).
//// - XpPerLevel.minXpForLevel: level 2 from 655 experience, level 50 from 26,360,090,
////   and 2147483647 for the rows above (GameFormula 145 makes 50 the highest level).
//// - `opcode.0x938`: stat 10 raises the unit's level, for the unit's owner and for each
////   viewer; `opcode.0x262` tail stats: a unit created later lists stat 10.
//// Skipped nowhere: the fixture holds these rows.

import experience_support as experience
import game_connection_support as support
import genesis_prime/client_connection
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/world_map/unit_fields
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test

/// The 0x1ac of a kill's gain as the client reads it: kind 2 and the creature's unit.
fn gain_of(experience experience: Int) -> experience_gained.ExperienceGained {
  ExperienceGained(
    experience:,
    rest_experience_used: 0,
    bonus_experience: 0,
    source_kind: 2,
    source_unit_id: experience.creature_unit_id,
  )
}

pub fn a_kill_credit_sends_experience_gained_of_kind_2_test() -> Nil {
  use <- owned_test.run(10_000)
  // Level 1 player, level 1 Beast (Creature2 73464, difficulty 1): the same level is
  // multiplier 1, so round(100 x 0.25 x 0.2 x 1) = 5.
  let state =
    support.watched_by(
      state: experience.entered_at(level: 1, saved_experience: None),
      viewers: [2],
    )
  let #(_, taken) = experience.credited(state:, creature_id: 73_464, level: 1)
  assert experience.gains(taken:) == [gain_of(experience: 5)]
    as "0x1ac {5, 0, 0, 2, the creature's unit}"
  assert support.written_ids(taken) == [0x01AC]
    as "nothing else is written: the level stands below 655 experience"
  assert support.peer_tells(taken) == []
    as "a viewer is told nothing of a gain that is the player's own"
}

pub fn the_level_gap_and_difficulty_scale_the_gain_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each case: the player's level, the creature's Creature2 row and level, and the
  // gain, worked by hand from the rows in the module's doc; 0 sends nothing.
  let cases = [
    // gap -4 and below: multiplier 0
    #(5, 73_464, 1, 0),
    #(10, 73_464, 1, 0),
    // 152 x 0.25 x 0.2 = 7.6 at gap 0; the gap's multiplier of it:
    // gap -3, 7.6 x 0.25 = 1.9
    #(6, 73_464, 3, 2),
    // gap -2, 7.6 x 0.5 = 3.8
    #(5, 73_464, 3, 4),
    // gap -1, 7.6 x 0.75 = 5.7
    #(4, 73_464, 3, 6),
    // gap 0, 7.6 x 1
    #(3, 73_464, 3, 8),
    // gap 1, 7.6 x 1.1 = 8.36
    #(3, 73_464, 4, 8),
    // gap 2, 7.6 x 1.2 = 9.12
    #(3, 73_464, 5, 9),
    // gap 3, 245 x 0.25 x 0.2 x 1.3 = 15.925
    #(3, 73_464, 6, 16),
    // gap 4, 7.6 x 1.4 = 10.64
    #(1, 73_464, 5, 11),
    // gap 9 weighs as 4, 537 x 0.25 x 0.2 x 1.4 = 37.59
    #(1, 73_464, 10, 38),
    // Creature2Difficulty 2 at gap 0: 152 x 0.25 x 0.3 = 11.4
    #(3, 11_467, 3, 11),
  ]
  list.each(cases, fn(case_) {
    let #(player_level, creature_id, creature_level, expected) = case_
    let state =
      experience.entered_at(level: player_level, saved_experience: None)
    let #(_, taken) =
      experience.credited(state:, creature_id:, level: creature_level)
    let described =
      "a level "
      <> int.to_string(player_level)
      <> " player's credit for Creature2 "
      <> int.to_string(creature_id)
      <> " of level "
      <> int.to_string(creature_level)
    case expected {
      0 -> {
        assert experience.gains(taken:) == []
          as { described <> " gives nothing and sends nothing" }
        assert support.written_ids(taken) == []
      }
      _ -> {
        assert experience.gains(taken:) == [gain_of(experience: expected)]
          as { described <> " gives " <> int.to_string(expected) }
      }
    }
  })
}

pub fn crossing_a_level_sends_stat_10_to_the_player_and_its_viewers_test() -> Nil {
  use <- owned_test.run(10_000)
  // 649 experience is level 1 and 655 level 2 (XpPerLevel.minXpForLevel rows 1 and 2):
  // a kill of 5 reaches 654 from 649 and 655 from 650.
  let #(_, below) =
    experience.credited(
      state: support.watched_by(
        state: experience.entered_at(level: 1, saved_experience: Some(649)),
        viewers: [2],
      ),
      creature_id: 73_464,
      level: 1,
    )
  assert experience.gains(taken: below) == [gain_of(experience: 5)]
  assert experience.level_writes(taken: below) == []
    as "654 is still level 1: no level is written"
  let state =
    support.watched_by(
      state: experience.entered_at(level: 1, saved_experience: Some(650)),
      viewers: [2],
    )
  assert unit_fields.stat(
      tail: support.created_for(state:, viewer: 4).tail,
      stat_id: 10,
    )
    == Ok(1)
    as "the player's unit stands at level 1 before"
  let #(state, taken) =
    experience.credited(state:, creature_id: 73_464, level: 1)
  assert experience.gains(taken:) == [gain_of(experience: 5)]
  assert experience.level_writes(taken:) == [#(support.own_unit_id, 2)]
    as "0x938 {the player's unit, stat 10, 2}: the level the client raises (opcode.0x938)"
  assert support.written_ids(taken) == [0x01AC, 0x0938]
    as "the experience first, then the level it made"
  assert support.news_told(taken:, viewer: 2)
    == [client_connection.Level(level: 2)]
    as "a viewer is told the level, to write the same 0x938 under the unit it shows"
  assert unit_fields.stat(
      tail: support.created_for(state:, viewer: 4).tail,
      stat_id: 10,
    )
    == Ok(2)
    as "a viewer created later is sent the unit at level 2, the stat list of its 0x262"
  let #(_, next) = experience.credited(state:, creature_id: 73_464, level: 1)
  assert experience.gains(taken: next) == [gain_of(experience: 4)]
    as "the next kill weighs the level the player holds now: a creature one level below is 0.75, round(100 x 0.25 x 0.2 x 0.75) = 4, where level 1 would give 5"
}

pub fn the_top_level_gains_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // The player at level 50 holds the least experience of it, 26,360,090 (XpPerLevel
  // row 50): a credit changes and sends nothing.
  let #(state, taken) =
    experience.credited(
      state: experience.entered_at(level: 50, saved_experience: None),
      creature_id: 73_464,
      level: 50,
    )
  assert support.written_ids(taken) == []
    as "the highest level (GameFormula 145) gains nothing, and the client is sent nothing"
  let #(_, saved, level) = experience.camped(state:)
  assert #(saved, level) == #(26_360_090, 50)
    as "and the experience it keeps is the row's, unchanged"
  // A level 49 player 90 short of level 50, killing a level 60 creature: the formula
  // gives round(75000 x 0.25 x 0.2 x 1.4) = 5250 (XpPerLevel row 50's 75000 stands for
  // every level above it), and the experience stops at row 50's minXpForLevel.
  let #(state, taken) =
    experience.credited(
      state: experience.entered_at(
        level: 49,
        saved_experience: Some(26_360_000),
      ),
      creature_id: 73_464,
      level: 60,
    )
  assert experience.gains(taken:) == [gain_of(experience: 90)]
    as "the client is sent what was added, so its experience is the server's"
  assert experience.level_writes(taken:) == [#(support.own_unit_id, 50)]
  let #(state, again) =
    experience.credited(state:, creature_id: 73_464, level: 60)
  assert support.written_ids(again) == []
    as "at level 50 the next credit gains nothing"
  let #(_, saved, level) = experience.camped(state:)
  assert #(saved, level) == #(26_360_090, 50)
    as "the crossing stopped at row 50's minXpForLevel, below the 2147483647 of the rows above"
}

pub fn a_creature_with_no_difficulty_row_gives_no_experience_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 12909 (Hycrest Farmer Male) names Creature2Difficulty 0, which has no
  // row (the table's ids are 1 to 24): the kill gives 0 and sends
  // nothing, as the credit of a gap that gives 0 does.
  let #(state, taken) =
    experience.credited(
      state: experience.entered_at(level: 1, saved_experience: Some(100)),
      creature_id: 12_909,
      level: 1,
    )
  assert experience.gains(taken:) == []
    as "a creature with no Creature2Difficulty row gives no experience"
  assert support.written_ids(taken) == []
  let #(_, saved, level) = experience.camped(state:)
  assert #(saved, level) == #(100, 1)
    as "the experience and level it keeps are unchanged"
}
