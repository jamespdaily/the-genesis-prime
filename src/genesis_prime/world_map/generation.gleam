//// The generation of one relation between two units in one map: the
//// number the map gives each time the pair comes into sight, so that what a creature
//// answers or tells about one sight is told apart from what it told about the sight
//// before it (genesis_prime/world_map/map). Only the map makes one: it takes the next
//// from its own counter, so no two sights of a map share a generation, and a reply
//// that carries an earlier one is known for what it is.

import gleam/int
import gleam/order.{type Order}

/// One sight of a pair. Opaque so that no other module makes a generation from a
/// number.
pub opaque type Generation {
  Generation(number: Int)
}

/// The generation a map gives first.
pub fn first() -> Generation {
  Generation(number: 1)
}

/// The generation a map gives after `generation`.
pub fn after(generation generation: Generation) -> Generation {
  Generation(number: generation.number + 1)
}

/// The order of two generations of one map: the later sight is the greater.
pub fn compare(first first: Generation, second second: Generation) -> Order {
  int.compare(first.number, second.number)
}

/// The number of the sight, for a log line that names it.
pub fn number(generation generation: Generation) -> Int {
  generation.number
}
