//// The rule that a quest remembers an object by its spawn. A unit of a map run (its map,
//// the run's incarnation and the unit id) names an object only until the map restarts, and
//// unit ids start at 1 again in each run (`world_map/map`), so a saved or remembered use
//// keyed by it counts the same object again after a relog or a restart. The quest log keys
//// a use by the object's spawn id (`world_map/spawn_id`), the id of its spawn table row.

import code_rule/repository
import gleam/list
import gleam/string
import owned_test
import unitest

pub fn no_unit_ref_in_src_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let naming =
    repository.sources(["src"])
    |> list.filter(fn(file) { string.contains(file.text, "UnitRef") })
    |> list.map(fn(file) { file.path })
  assert naming == []
}
