//// The unit type a creature's process stands as: the unit type its 0x262 carries
//// (`0x140649e20`, `world_data.entity_type`) among those the server runs as a
//// creature. A NonPlayer creature (type 0) moves and fights; a Turret (type 13)
//// fights from where it stands and never moves. The client reads both types'
//// type data alike (`opcode.0x262.simple`), so the type sets only the number the
//// 0x262 holds and whether the creature may move.

/// The unit types a creature stands as.
pub type CreatureUnitType {
  /// Type 0: a creature that moves and fights.
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
pub fn of_creation_type(creation_type creation_type: Int) -> CreatureUnitType {
  case creation_type {
    13 -> Turret
    _ -> NonPlayer
  }
}

/// The number message 0x262 carries as the unit type.
pub fn entity_type(unit_type unit_type: CreatureUnitType) -> Int {
  case unit_type {
    NonPlayer -> 0
    Turret -> 13
  }
}

/// Whether a creature of this unit type moves: a Turret never does, whatever its
/// display's run speed.
pub fn can_move(unit_type unit_type: CreatureUnitType) -> Bool {
  case unit_type {
    NonPlayer -> True
    Turret -> False
  }
}
