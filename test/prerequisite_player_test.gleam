//// The prerequisite types that read the player (`genesis_prime/game/prerequisite`):
//// 1 (the first unit's level), 2 (its race), 3 (its class), 26 (the zone it is
//// in), 39 (whether it is a player) and 52 (its path), and what a subject with no
//// player leaves undecided. Expected values come from these places.
//// - The client's types, each with its fact: `Prerequisite.prerequisiteTypeId.1`
////   (the first unit's formula level, compared as `0x1404a2090` compares: 1
////   equal, 2 not equal, 3 greater, 4 at least, 5 less, 6 at most, unsigned
////   32-bit, any other comparison fails; the objectId is not read),
////   `.2` and `.3` (the race and the class: comparison 1 when equal, 2 when not,
////   any other fails), `.39` (comparison 1 passes for a player, 2 for another
////   unit, any other fails), `.52` (the path: 1 equal, 2 different, any other
////   fails) and `.26` (`0x14049e680`: the value is compared with the current
////   zone first, then with each parent zone through the WorldZone table's
////   parentZoneId, until one equals it or a zone has no parent; 1 passes when
////   one does, 2 when none does, any other fails).
//// - The client's evaluator `0x1404a2100`: a check that has no first unit to
////   read, as the creature attack's and the quest turn-in's have none, does not
////   decide a type that reads one.
//// - The client's Prerequisite table, whose every condition of these types the
////   last test decides.

import client_tables
import genesis_prime/game/prerequisite.{
  type Subject, Fails, NotRead, Passes, Player, Subject,
}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support
import quest_support
import unitest

/// A subject that is this player, under no cast.
fn subject() -> Subject {
  Subject(
    ..prerequisite_support.holding(held: [], second_unit: None),
    player: Some(prerequisite_support.player()),
  )
}

/// What a condition (type, comparison, objectId, value) gives for the player.
fn verdict(condition: #(Int, Int, Int, Int)) -> prerequisite.Verdict {
  prerequisite_support.verdict(condition:, subject: subject())
}

pub fn a_level_condition_compares_the_level_by_its_relation_test() -> Nil {
  use <- owned_test.run(5000)
  // The player is level 20. Each case: comparison, value, and whether it passes.
  let cases = [
    #(1, 20, Passes),
    #(1, 19, Fails),
    #(2, 19, Passes),
    #(2, 20, Fails),
    #(3, 19, Passes),
    #(3, 20, Fails),
    #(4, 20, Passes),
    #(4, 21, Fails),
    #(5, 21, Passes),
    #(5, 20, Fails),
    #(6, 20, Passes),
    #(6, 19, Fails),
    // The comparison is unsigned 32-bit (0x1404a2090): 0xFFFFFFFF is beyond 20.
    #(5, 0xFFFFFFFF, Passes),
    #(3, 0xFFFFFFFF, Fails),
  ]
  list.each(cases, fn(case_) {
    let #(comparison, value, expected) = case_
    assert verdict(#(1, comparison, 0, value)) == expected
      as {
        "type 1, comparison "
        <> int.to_string(comparison)
        <> ", value "
        <> int.to_string(value)
        <> " against level 20"
      }
  })
  assert verdict(#(1, 1, 9999, 20)) == Passes
    as "the objectId is not read (Prerequisite.prerequisiteTypeId.1)"
  assert verdict(#(1, 0, 0, 20)) == Fails && verdict(#(1, 7, 0, 20)) == Fails
    as "a comparison that is none of 1 to 6 fails (0x1404a2090)"
}

pub fn a_race_condition_reads_the_players_race_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(#(2, 1, 0, 3)) == Passes
    as "comparison 1 on the player's own race"
  assert verdict(#(2, 1, 0, 4)) == Fails as "comparison 1 on another race"
  assert verdict(#(2, 2, 0, 4)) == Passes as "comparison 2 on another race"
  assert verdict(#(2, 2, 0, 3)) == Fails
    as "comparison 2 on the player's own race"
  assert verdict(#(2, 3, 0, 4)) == Fails && verdict(#(2, 3, 0, 3)) == Fails
    as "any other comparison fails (Prerequisite.prerequisiteTypeId.2)"
  assert verdict(#(2, 1, 9999, 3)) == Passes as "the objectId is not read"
}

pub fn a_class_condition_fails_on_an_unknown_comparison_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(#(3, 1, 0, 5)) == Passes
    as "comparison 1 on the player's own class"
  assert verdict(#(3, 1, 0, 1)) == Fails as "comparison 1 on another class"
  assert verdict(#(3, 2, 0, 1)) == Passes as "comparison 2 on another class"
  assert verdict(#(3, 2, 0, 5)) == Fails
    as "comparison 2 on the player's own class"
  assert verdict(#(3, 3, 0, 1)) == Fails && verdict(#(3, 3, 0, 5)) == Fails
    as "comparison 3 is none the client's check knows for a class: it fails (Prerequisite.prerequisiteTypeId.3)"
}

pub fn a_path_condition_passes_on_a_different_path_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(#(52, 1, 0, 1)) == Passes
    as "comparison 1 on the player's own path"
  assert verdict(#(52, 1, 0, 3)) == Fails as "comparison 1 on another path"
  assert verdict(#(52, 2, 0, 3)) == Passes as "comparison 2 on another path"
  assert verdict(#(52, 2, 0, 1)) == Fails
    as "comparison 2 on the player's own path"
  assert verdict(#(52, 3, 0, 3)) == Fails && verdict(#(52, 3, 0, 1)) == Fails
    as "any other comparison fails (Prerequisite.prerequisiteTypeId.52)"
}

pub fn a_player_condition_passes_only_for_a_player_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(#(39, 1, 0, 0)) == Passes
    as "comparison 1 passes for a first unit that is a player"
  assert verdict(#(39, 2, 0, 0)) == Fails
    as "comparison 2 passes only for another unit"
  assert verdict(#(39, 3, 0, 0)) == Fails
    as "any other comparison fails (Prerequisite.prerequisiteTypeId.39)"
  assert verdict(#(39, 1, 77, 88)) == Passes
    as "the objectId and the value are not read"
}

pub fn a_zone_condition_passes_in_the_zone_or_under_it_test() -> Nil {
  use <- owned_test.run(5000)
  // The player stands in 1411, whose parent is 1305, whose parent is 1304
  // (0x1403c92e0 walks the parentZoneId chain).
  list.each([1411, 1305, 1304], fn(zone) {
    assert verdict(#(26, 1, 0, zone)) == Passes
      as {
        "comparison 1 passes for the zone the player is in or one above it: "
        <> int.to_string(zone)
      }
    assert verdict(#(26, 2, 0, zone)) == Fails
      as {
        "comparison 2 fails for the zone the player is in or one above it: "
        <> int.to_string(zone)
      }
  })
  assert verdict(#(26, 1, 0, 4962)) == Fails
    as "comparison 1 fails for a zone that is not in the chain"
  assert verdict(#(26, 2, 0, 4962)) == Passes
    as "comparison 2 passes for a zone that is not in the chain"
  assert verdict(#(26, 3, 0, 1411)) == Fails
    && verdict(#(26, 3, 0, 4962)) == Fails
    as "any other comparison fails"
  assert verdict(#(26, 1, 9999, 1305)) == Passes as "the objectId is not read"
}

pub fn a_subject_with_no_player_does_not_decide_these_types_test() -> Nil {
  use <- owned_test.run(5000)
  let conditions = [
    #(1, 1, 0, 20),
    #(2, 1, 0, 3),
    #(3, 1, 0, 5),
    #(26, 1, 0, 1411),
    #(39, 1, 0, 0),
    #(52, 1, 0, 1),
    #(109, 1, 870, 0),
  ]
  list.each(conditions, fn(condition) {
    assert prerequisite_support.verdict(
        condition:,
        subject: prerequisite.of_difficulty(difficulty: 3),
      )
      == NotRead(prerequisite_type: condition.0)
      as {
        "a creature's difficulty holds no player: type "
        <> int.to_string(condition.0)
        <> " is not decided (0x1404a2100)"
      }
  })
  // A subject known by its place alone holds the player's facts but not the
  // first unit's, so only the types that read the unit are left undecided.
  let place_only =
    prerequisite_support.struck(
      first: None,
      second: prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0),
      player: prerequisite_support.player(),
      quests: quest_support.log_of(rows: []),
    )
  list.each(conditions, fn(condition) {
    let verdict = prerequisite_support.verdict(condition:, subject: place_only)
    let reads_the_unit = list.contains([1, 3, 39], condition.0)
    assert { verdict == NotRead(prerequisite_type: condition.0) }
      == reads_the_unit
      as {
        "a subject known by its place alone holds the player's facts and not the unit: type "
        <> int.to_string(condition.0)
        <> case reads_the_unit {
          True -> " is not decided"
          False -> " is decided"
        }
      }
  })
}

pub fn a_struck_units_condition_reads_the_casters_player_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x1404a2100: the client reads types 2, 10, 26, 52 and 109 from its own
  // player, whoever the unit is that the check is about.
  let caster = prerequisite_support.player()
  let struck_by = fn(player) {
    prerequisite_support.struck(
      first: None,
      second: prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0),
      player:,
      quests: quest_support.log_of(rows: []),
    )
  }
  assert prerequisite_support.verdict(
      condition: #(52, 1, 0, 1),
      subject: struck_by(caster),
    )
    == Passes
    as "a caster on path 1 passes a type 52 condition for path 1"
  assert prerequisite_support.verdict(
      condition: #(52, 1, 0, 1),
      subject: struck_by(Player(..caster, path: 2)),
    )
    == Fails
    as "a caster on path 2 fails it: the struck unit's condition reads the caster's path"
}

pub fn every_condition_of_these_types_is_decided_for_a_player_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let types = [1, 2, 3, 26, 39, 52, 109]
  let conditions =
    prerequisite_table.all(tables)
    |> list.flat_map(fn(row) {
      [
        #(
          row.prerequisite_type_id0,
          row.prerequisite_comparison_id0,
          row.object_id0,
          row.value0,
        ),
        #(
          row.prerequisite_type_id1,
          row.prerequisite_comparison_id1,
          row.object_id1,
          row.value1,
        ),
        #(
          row.prerequisite_type_id2,
          row.prerequisite_comparison_id2,
          row.object_id2,
          row.value2,
        ),
      ]
    })
    |> list.filter(fn(condition) { list.contains(types, condition.0) })
  list.each(types, fn(type_id) {
    assert list.any(conditions, fn(condition) { condition.0 == type_id })
      as {
        "the client's Prerequisite table holds a condition of type "
        <> int.to_string(type_id)
      }
  })
  list.each(conditions, fn(condition) {
    assert verdict(condition) != NotRead(prerequisite_type: condition.0)
      as {
        "a player decides the condition "
        <> string_of(condition)
        <> " of the client's table"
      }
  })
}

fn string_of(condition: #(Int, Int, Int, Int)) -> String {
  "("
  <> int.to_string(condition.0)
  <> ", "
  <> int.to_string(condition.1)
  <> ", "
  <> int.to_string(condition.2)
  <> ", "
  <> int.to_string(condition.3)
  <> ")"
}
