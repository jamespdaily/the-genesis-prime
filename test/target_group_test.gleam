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
import gleam/option.{None, Some}
import owned_test
import planted_table.{Integer}

const creature = 100

const faction = 200

const race = 170

fn unit() -> target_group.Unit {
  Unit(
    creature_id: Creature2Id(creature),
    faction_id: Some(Faction2Id(faction)),
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

  let no_faction = Unit(..unit(), faction_id: None)
  assert target_group.contains(tables:, group: 90_005, unit: no_faction)
    == False
    as "a unit with no known faction is in no type 3 group"
  assert target_group.contains(tables:, group: 90_007, unit: no_faction)
    == False
    as "nor, as the server cannot say, is it outside one"

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
    as "types 5 to 9 and any type the client has no case for are never members"
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
    unit: Unit(..unit(), faction_id: Some(Faction2Id(248))),
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
