//// The objectives the place pass reads (`genesis_prime/game/place_objective`), over
//// the client's whole tables and the units of the world database. Expected values come
//// from these places.
//// - `QuestObjective.type.22`: the marker of a place objective is its
////   worldLocationsIdIndicator00 to 03 (`0x140485fa0` tests a place by its WorldLocation2
////   row); of the client's 511 type 22 objectives, 468 name a marker row and 43 name none
////   (counted over `QuestObjective` of the client's files), and the client has no other
////   way to tell where such an objective is done.
//// - `QuestObjective.21294.places`: a type 14 objective whose TargetGroup holds only
////   creatures the client never offers (Creature2 with no activate spell, no
////   prerequisite on an activate spell, no questAnimStateId and no
////   prerequisiteIdAnimState) and whose questDirectionId is not 0 is counted by the
////   player's presence at one of its places. The client's rows name seven: 9730 and 10099
////   (TargetGroup 12202, Creature2 67630, 7 places in World 1068), 16307 (7942, 52632, 5
////   places in World 1061), 16365 (8011, 52989, places 41678 of radius 110 and 25438 of
////   radius 3.1 in World 51), 18202 (10229, Creature2 51952 to 51957, 10 places in World
////   1061) and 21294 and 21307 (14425, 73500, 3 places in World 3460).
//// - The world database's spawns of these creatures, copied as they are
////   (`test/fixture/world_data_places/spawn.tsv`): 29338 to 29340 of 73500 stand each
////   within 0.5 of one of the three places of 21294 and 21307; 30643 to 30647 of 52632
////   stand each within 1.0 of one of 16307's five places; 9719 to 9722 of 52989 stand within
////   110 of 41678 and none within 3.1 of 25438; 29859 of 51957 stands within 1.0 of place
////   46057 of 18202's ten and the other nine places hold none of its four spawns; Creature2
////   67630 has no spawn, so none of the seven places of 9730 and 10099 holds a unit.

import client_tables
import content_support
import database_support
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/place_objective
import genesis_prime/game/rating
import genesis_prime/game/vendor
import genesis_prime/import_world_data
import genesis_prime/table/quest_objective
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import owned_test
import spawn_support
import unitest

pub fn every_type_22_objective_has_a_marker_or_is_reported_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.with_content_tables()
  let type_22 =
    list.filter(quest_objective.all(tables), fn(row) { row.type_ == 22 })
  assert list.length(type_22) == 511
    as "the client's table holds 511 type 22 objectives"
  assert list.count(type_22, fn(row) {
      place_objective.markers(tables:, objective: row) != []
    })
    == 468
    as "468 of them name a marker row"
  assert list.length(place_objective.unmarked(tables:)) == 43
    as "the other 43 are the ones the start reports"
  assert list.all(place_objective.unmarked(tables:), fn(row) {
    place_objective.markers(tables:, objective: row) == []
  })
    as "a reported objective names no marker row"

  // The place-counted checklists and, from the world database's rows of their units,
  // the places that hold none.
  let counted = place_objective.place_counted(tables:)
  assert list.map(counted, fn(row) { row.id })
    == [9730, 10_099, 16_307, 16_365, 18_202, 21_294, 21_307]
    as "the seven type 14 rows of never-offered creatures with places"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder: "test/fixture/world_data_places",
    )
    as "the planted world-database rows import"
  let assert Ok(rows) =
    content_spawn.rows(db: content_support.connect(database:))
    as "the spawn rows read back"
  let selection =
    spawn.select(
      rows:,
      tables:,
      formulas: rating.formulas(tables:),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
    )
  assert selection.refusals == [] as "every row passes the spawn checks"
  let empty =
    place_objective.places_without_unit(tables:, worlds: selection.worlds)
    |> list.map(fn(found) { #(found.0, list.sort(found.1, int.compare)) })
  assert empty
    == [
      #(9730, [52_820, 52_821, 52_822, 52_823, 52_824, 52_825, 52_826]),
      #(10_099, [52_820, 52_821, 52_822, 52_823, 52_824, 52_825, 52_826]),
      #(16_365, [25_438]),
      #(18_202, [
        40_798,
        41_219,
        41_223,
        41_227,
        46_058,
        46_059,
        46_060,
        46_061,
        46_062,
      ]),
    ]
    as "9730 and 10099 have no unit anywhere, 16365's place 25438 and nine of 18202's ten places hold none; 16307, 21294 and 21307 have a unit at every place"
}
