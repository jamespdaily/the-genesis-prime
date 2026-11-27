//// The unit type a creature's process stands as: the unit type its 0x262 carries
//// (`0x140649e20`, `world_data.entity_type`) among those the server runs as a
//// creature. A NonPlayer creature (type 0) moves and fights; a Turret (type 13)
//// fights from where it stands and never moves. The client reads both types'
//// type data alike (`opcode.0x262.simple`), so the type sets only the number the
//// 0x262 holds and, with the spawn's world object link, whether the creature may
//// move (`can_move`).

import genesis_prime/world_map/creation_type

/// The unit types a creature stands as.
pub type CreatureUnitType {
  /// Type 0: a creature that fights, and moves unless it is placed as part of a map
  /// object (`can_move`).
  NonPlayer
  /// Type 13: a creature that fights from its place and never moves.
  Turret
}

/// The creature unit type of a unit type's number: type 0 and type 13 are the
/// ones a creature stands as, and no other number is.
pub fn of_entity_type(
  entity_type entity_type: Int,
) -> Result(CreatureUnitType, Nil) {
  case entity_type {
    0 -> Ok(NonPlayer)
    13 -> Ok(Turret)
    _ -> Error(Nil)
  }
}

/// The creature unit type of a Creature2 row's `CreationTypeEnum` for a creature
/// placed with no spawn row of its own: 13 is a Turret, as the world database
/// spawns such a creature (`Creature2.CreationTypeEnum`, `world_data.entity_type`),
/// and any other value a NonPlayer.
pub fn of_creation_type(creation_type number: Int) -> CreatureUnitType {
  case creation_type.kind_of(number) {
    creation_type.Turret -> Turret
    creation_type.NonPlayer
    | creation_type.BindPoint
    | creation_type.SimpleCollidable
    | creation_type.Other(..)
    | creation_type.Refused(..) -> NonPlayer
  }
}

/// The number message 0x262 carries as the unit type.
pub fn entity_type(unit_type unit_type: CreatureUnitType) -> Int {
  case unit_type {
    NonPlayer -> 0
    Turret -> 13
  }
}

/// Whether a creature moves: a Turret never does, whatever its display's run
/// speed, and a NonPlayer placed as part of a map object (`world_object_id` not 0,
/// the spawn row's `active_prop_id`) never does either, as a bush, a burrow or a
/// nest does not (a server choice with no client
/// source: the client has no rooted flag and its display of such a creature carries
/// a run speed; the world database places each as a fixed object with no spline).
pub fn can_move(
  unit_type unit_type: CreatureUnitType,
  world_object_id world_object_id: Int,
) -> Bool {
  case unit_type {
    NonPlayer -> world_object_id == 0
    Turret -> False
  }
}
