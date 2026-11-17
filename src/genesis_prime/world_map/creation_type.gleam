//// The kind of a Creature2 row, decoded once from its `CreationTypeEnum`: the one place the
//// server names the creation types it treats apart. A rule that reads a creature's creation
//// type matches on `Kind`, so a new variant names every place that must handle it.
////
//// ```text
//// Creature2 row (CreationTypeEnum) -> kind_of -> Kind -> is_accepted / unit_type
//// ```
////
//// - The client refuses a creature whose creation type is 26 or higher
////   (`ValidateCreatureRows 0x140485790`, `Creature2.CreationTypeEnum`), so those are
////   `Refused`; the client's own table holds none.
//// - The client's chooser `0x140479560` keys behaviour on 4 (door), 8 (collectible) and 12
////   (mailbox); the unit type a creature stands as equals its creation type for 0 to 14.
//// - Type 13 is the unit type of a turret (`creature_unit_type`).
//// - 18 (bind point) stands as unit type 19 and 20 (simple collidable) as 32, as the world
////   database stores them (wildstar-knowledge world-data; a guess, the client holds no
////   such pairing).
//// - This module imports nothing, so any module can name a kind.

/// What a rule reads a creation type as.
pub type Kind {
  /// Creation type 0: a creature that fights and moves.
  NonPlayer
  /// Creation type 13: a turret.
  Turret
  /// Creation type 18: a bind point, unit type 19.
  BindPoint
  /// Creation type 20: a simple collidable, unit type 32.
  SimpleCollidable
  /// Any other creation type the client loads (0 to 25): it stands as its own number.
  Other(number: Int)
  /// A creation type of 26 or more, which the client refuses to load.
  Refused(number: Int)
}

/// The kind of the creation type `number` (`Creature2.CreationTypeEnum`).
pub fn kind_of(number: Int) -> Kind {
  case number {
    0 -> NonPlayer
    13 -> Turret
    18 -> BindPoint
    20 -> SimpleCollidable
    n if n >= 26 -> Refused(number: n)
    n -> Other(number: n)
  }
}

/// Whether the client loads a creature of the kind: any but a `Refused` one
/// (`0x140485790`).
pub fn is_accepted(kind: Kind) -> Bool {
  case kind {
    Refused(..) -> False
    NonPlayer | Turret | BindPoint | SimpleCollidable | Other(..) -> True
  }
}

/// The unit type a creature of the kind stands as: its own number, except that a bind
/// point is 19 and a simple collidable 32 (a guess, from the world database). A refused
/// kind gives its own number, as the server has always paired it.
pub fn unit_type(kind: Kind) -> Int {
  case kind {
    NonPlayer -> 0
    Turret -> 13
    BindPoint -> 19
    SimpleCollidable -> 32
    Other(number:) | Refused(number:) -> number
  }
}
