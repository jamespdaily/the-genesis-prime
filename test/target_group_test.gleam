//// The TargetGroup membership rule (`genesis_prime/game/target_group`). Expected values
//// come from `0x1403b4a20`, which switches on the group's type and skips data words that
//// are 0:
//// - types 1, 3 and 12 name the unit's Creature2 id, current Faction2 id and UnitRace
////   id; each is a member when any non-zero data word equals it, and types 2, 4 and 13
////   are their negations.
//// - types 5 to 9 name a unit's race, class and 0x262 tagged value, which the server
////   does not hold: no unit is a member of them.
//// - type 10 is a member when every sub-group its words name (not the group's own id)
////   is one, type 11 when any is; a missing row is not a member, and neither is a
////   type the client has no case for.
////
//// The client's rows in the fixture (`table_rows -- TargetGroup`):
//// - 307: type 1, Creature2 5006 and 5007.
//// - 847: type 3, Faction2 248.
//// - 12511: type 11 of 12512, which is type 12 for UnitRace 170.
////
//// Every other case is a row added to the table (id 90001 and up) for the one reason
//// of the case: the client's table has no row of that type or shape.

import fixture_tables
import genesis_prime/game/target_group.{Unit}
import genesis_prime/table/id.{Creature2Id, Faction2Id, UnitRaceId}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import owned_test
import planted_table.{Integer}

const creature = 100

const faction = 200

const race = 170

fn unit() -> target_group.Unit {
  Unit(
    creature_id: Creature2Id(creature),
    faction_id: Faction2Id(faction),
    unit_race_id: UnitRaceId(race),
  )
}

/// Runs the body on the fixture's tables with these groups added: each is the id, the
/// type and the data words (the rest are 0).
fn with_groups(
  groups groups: List(#(Int, Int, List(Int))),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(groups, fixture_tables.rows(), fn(rows, group) {
      let words =
        list.index_map(pad(group.2), fn(word, index) {
          #("data" <> int.to_string(index), Integer(word))
        })
      case
        fixture_tables.add(
          rows:,
          table: "TargetGroup",
          copy_of: 307,
          id: group.0,
          with: [#("type", Integer(group.1)), ..words],
        )
      {
        Ok(added) -> added
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

fn pad(words: List(Int)) -> List(Int) {
  list.append(words, list.repeat(0, 7 - list.length(words)))
}

pub fn target_group_membership_follows_the_clients_cases_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_groups(groups: [
    // Types 1 and 2 by the creature id; a zero word is skipped.
    #(90_001, 1, [0, 5, creature]),
    #(90_002, 1, [101, 102]),
    #(90_003, 2, [101, 102]),
    #(90_004, 2, [0, creature]),
    // Types 3 and 4 by the faction id.
    #(90_005, 3, [7, faction]),
    #(90_006, 3, [201]),
    #(90_007, 4, [201]),
    #(90_008, 4, [faction]),
    // Types 12 and 13 by the UnitRace id.
    #(90_009, 12, [race]),
    #(90_010, 12, [171]),
    #(90_011, 13, [171]),
    #(90_012, 13, [race]),
    // Types 10 and 11 name other groups; the group's own id is skipped.
    #(90_013, 10, [90_001, 90_005]),
    #(90_014, 10, [90_001, 90_006]),
    #(90_015, 10, [90_013, 90_015]),
    #(90_016, 10, [90_001, 99_999]),
    #(90_017, 11, [90_002, 90_005]),
    #(90_018, 11, [90_002, 90_006]),
    #(90_019, 11, [90_019, 90_001]),
    #(90_020, 11, [90_020]),
    // Types the server has no unit value for, and a type the client has no case for.
    #(90_021, 5, [creature]),
    #(90_022, 6, [creature]),
    #(90_023, 7, [creature]),
    #(90_024, 8, [creature]),
    #(90_025, 9, [creature]),
    #(90_026, 14, [creature]),
    #(90_027, 0, [creature]),
  ])
  let member = fn(group) {
    target_group.contains(tables:, group:, unit: unit())
  }
  assert [90_001, 90_005, 90_009, 90_003, 90_007, 90_011]
    |> list.all(member)
    as "types 1, 3 and 12 name the unit's creature, faction and race, and types 2, 4 and 13 a unit they do not name"
  assert [90_002, 90_006, 90_010, 90_004, 90_008, 90_012]
    |> list.all(fn(group) { !member(group) })
    as "the opposite of each"
  assert target_group.contains(
      tables:,
      group: 90_001,
      unit: Unit(..unit(), creature_id: Creature2Id(0)),
    )
    == False
    as "a zero data word is skipped, not equal to a unit value of 0"
  assert target_group.contains(
      tables:,
      group: 90_003,
      unit: Unit(..unit(), creature_id: Creature2Id(0)),
    )
    == True
    as "a type 2 group's zero words are skipped too: a creature 0 is in none of the others"

  assert member(90_013) as "type 10: every sub-group names the unit"
  assert !member(90_014) as "type 10: one sub-group does not"
  assert member(90_015)
    as "type 10 skips the group's own id: the one sub-group names the unit"
  assert !member(90_016) as "type 10: a sub-group with no row is not a member"
  assert member(90_017) as "type 11: one sub-group names the unit"
  assert !member(90_018) as "type 11: no sub-group does"
  assert member(90_019)
    as "type 11 skips the group's own id and finds the other"
  assert !member(90_020) as "type 11 with only its own id has no sub-group"

  assert [90_021, 90_022, 90_023, 90_024, 90_025, 90_026, 90_027]
    |> list.all(fn(group) { !member(group) })
    as "types 5 to 9 are never members, a gap of the server (it holds no race, class or 0x262 set value; 58 type 9 groups are reached by a server rule, open issue #897 until the coordinator files the one that closes it); any type the client has no case for is never a member"
  assert !member(99_998) as "a group with no row is not a member"

  assert target_group.contains(
    tables:,
    group: 307,
    unit: Unit(..unit(), creature_id: Creature2Id(5007)),
  )
    as "the client's group 307 holds 5007"
  assert !member(307) as "and not creature 100"
  assert target_group.contains(
    tables:,
    group: 847,
    unit: Unit(..unit(), faction_id: Faction2Id(248)),
  )
    as "the client's group 847 holds faction 248"
  assert target_group.contains(
    tables:,
    group: 12_511,
    unit: Unit(..unit(), unit_race_id: UnitRaceId(170)),
  )
    as "the client's group 12511 holds what its type 12 sub-group 12512 holds, race 170"
  assert target_group.contains(
      tables:,
      group: 12_511,
      unit: Unit(..unit(), unit_race_id: UnitRaceId(171)),
    )
    == False
    as "and not race 171"
}

pub fn creatures_of_a_group_are_the_non_zero_words_of_a_type_1_group_only_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_groups(groups: [
    #(90_101, 1, [0, 5, 7]),
    #(90_102, 2, [5]),
    #(90_103, 3, [5]),
    #(90_104, 5, [5]),
    #(90_105, 9, [5]),
    #(90_106, 10, [90_101]),
    #(90_107, 12, [5]),
  ])
  assert target_group.creatures_of(tables:, group: 90_101)
    == [Creature2Id(5), Creature2Id(7)]
    as "0x1403b4a20: a type 1 group tests its non-zero words against the unit's Creature2 id"
  assert list.flat_map(
      [90_102, 90_103, 90_104, 90_105, 90_106, 90_107, 99_998],
      fn(group) { target_group.creatures_of(tables:, group:) },
    )
    == []
    as "a group of another type names no Creature2 ids, and a group with no row none"
}

pub fn listed_creatures_follow_type_1_words_and_the_sub_groups_of_types_10_and_11_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_groups(groups: [
    #(90_101, 1, [0, 5, 7]),
    #(90_102, 2, [5]),
    #(90_103, 3, [5]),
    #(90_104, 5, [5]),
    #(90_105, 9, [5]),
    #(90_107, 12, [5]),
    #(90_111, 1, [7, 9]),
    #(90_112, 11, [90_101, 90_102, 90_111]),
    #(90_113, 10, [90_113, 90_111, 90_101]),
    #(90_114, 11, [90_115]),
    #(90_115, 11, [90_114, 90_111]),
  ])
  let listed = fn(group) { target_group.listed_creatures(tables:, group:) }
  assert listed(90_101) == [5, 7] as "a type 1 group lists its non-zero words"
  assert list.flat_map([90_102, 90_103, 90_104, 90_105, 90_107, 99_998], listed)
    == []
    as "the other types hold a unit by a test of something else, so they list none; a missing row lists none"
  assert listed(90_112) == [5, 7, 9]
    as "a type 11 group lists its sub-groups' creatures depth first, each once"
  assert listed(90_113) == [7, 9, 5]
    as "a type 10 group lists its sub-groups too, skipping its own id and the creature 7 it already listed"
  assert listed(90_114) == [7, 9]
    as "two groups naming each other end where the first is met again"
}
