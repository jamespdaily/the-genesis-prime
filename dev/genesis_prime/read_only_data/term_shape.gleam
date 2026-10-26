//// Which shape a persistent term holds a table in: a tuple of rows indexed by
//// id, or a map from id to row. Both are read from one process on the same
//// stream, and the faster lookup is the shape the persistent-term variant
//// uses.

import genesis_prime/read_only_data/table_data.{type Source}

/// A way to hold a table in one term.
pub type Shape {
  /// A tuple of rows; the row of id `n` is element `n`.
  TupleByRow
  /// A map from id to row.
  MapById
}

/// What reading from one shape cost.
pub type ShapeCost {
  ShapeCost(shape: Shape, nanoseconds_per_read: Float)
}

/// Reads one round of the stream from each shape, from one process, and
/// returns each shape's median over the rounds, in the order tuple, map.
pub fn measure(source: Source, stream: BitArray) -> List(ShapeCost) {
  todo as "body in the build commit"
}

/// The shape with the lower cost. `costs` is not empty.
pub fn faster(costs: List(ShapeCost)) -> Shape {
  todo as "body in the build commit"
}

/// The shape's name as printed.
pub fn name(shape: Shape) -> String {
  todo as "body in the build commit"
}
