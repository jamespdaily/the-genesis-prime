//// Whether a creature may move (`genesis_prime/world_map/creature_unit_type`).
//// Expected values are the rule itself, a server choice (Jim, issue 854): a Turret
//// never moves, and a NonPlayer moves unless it is placed as part of a map object,
//// the world database's `active_prop_id` not 0.

import genesis_prime/world_map/creature_unit_type.{NonPlayer, Turret}
import owned_test

pub fn a_nonplayer_with_no_map_object_moves_test() -> Nil {
  use <- owned_test.run(5000)
  assert creature_unit_type.can_move(unit_type: NonPlayer, world_object_id: 0)
}

pub fn a_nonplayer_placed_as_part_of_a_map_object_never_moves_test() -> Nil {
  use <- owned_test.run(5000)
  assert !creature_unit_type.can_move(
    unit_type: NonPlayer,
    world_object_id: 1_238_827,
  )
}

pub fn a_turret_never_moves_with_or_without_a_map_object_test() -> Nil {
  use <- owned_test.run(5000)
  assert !creature_unit_type.can_move(unit_type: Turret, world_object_id: 0)
  assert !creature_unit_type.can_move(
    unit_type: Turret,
    world_object_id: 1_238_827,
  )
}
