//// What a heal of a player's vital comes to, as the cast tells it to the client and as the
//// life raises the vital (genesis_prime/game/heal_split works the parts out).

/// A heal worked out: `amount` is what the client is told, `shield` and `health` are what
/// each vital rises by and `overheal` is the rest.
pub type Split {
  Split(amount: Int, shield: Int, health: Int, overheal: Int)
}
