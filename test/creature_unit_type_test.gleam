//// Whether a creature may move (`genesis_prime/shared/creature_unit_type`).
//// Expected values are the rule itself, a server choice: a Turret
//// never moves, and a NonPlayer moves unless it is placed as part of a map object,
//// the world database's `active_prop_id` not 0.

import genesis_prime/shared/creature_unit_type.{NonPlayer, Turret}
import gleam/list
import owned_test

pub fn only_creation_type_13_is_a_turret_test() -> Nil {
  use <- owned_test.run(5000)
  assert creature_unit_type.of_creation_type(creation_type: 13) == Turret
    as "a Creature2 row of CreationTypeEnum 13 is a Turret, as the world database spawns it"
  list.each([0, 1, 4, 12, 14, 18, 20, 25, 26, 100], fn(creation_type) {
    assert creature_unit_type.of_creation_type(creation_type:) == NonPlayer
      as "any other creation type, a refused one included, is a NonPlayer (server choice)"
  })
}

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
