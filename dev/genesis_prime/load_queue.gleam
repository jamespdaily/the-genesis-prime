//// The map's message queue as a load run reads it: stub.

/// The longest queue found in one second of a run.
pub type Second {
  Second(second: Int, longest: Int)
}

/// The longest queue of each second that holds a sample: stub.
pub fn by_second(series _series: List(#(Int, Int))) -> List(Second) {
  []
}

/// The second with the longest queue: stub.
pub fn peak(series _series: List(#(Int, Int))) -> Result(Second, Nil) {
  Error(Nil)
}

/// How many messages of each kind, the most first: stub.
pub fn kinds(names _names: List(String)) -> List(#(String, Int)) {
  []
}
