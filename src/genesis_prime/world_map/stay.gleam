//// A player's stay in the world: one join of a map by its connection, from the
//// map's `Joined` to the leave that ends it (a camp, the Holocrypt) or the end of
//// the connection. Every message another process sends a connection for its
//// player's stay (the map's notices, another player's news, a creature's news,
//// threat, release and strike) names the stay it was sent for, and the connection
//// takes only one that names its own (genesis_prime/client_connection `ForStay`,
//// genesis_prime/game/connection).
////
//// - **Why a stay and not a unit id or a run.** A message sent before a camp or a
////   Holocrypt can arrive after the next join: in the same run of the same map,
////   where the next stay has a new unit id but the creatures and players kept
////   their own, or in a run that restarted and gives unit ids from 1 again, so
////   the old unit id can name the new unit. The stay is the only name of what the
////   message was meant for.
//// - **Why a number cannot match an old stay.** The connection counts its stays
////   (`next`): each join asks with a number above every earlier one, and the
////   number lives in the connection's own state, which only grows. A stay message
////   is delivered to one connection process by its id, which is unique on the
////   node for its life (`erlang:unique_integer`, genesis_prime/connection/shell),
////   and a crash of that process ends the connection, whose client logs in again
////   as a new connection. So a message of an earlier stay names a number the
////   connection gave before, never the current one. The number is the rule's own
////   state, so the rule stays pure and a recorded session replays to the same
////   numbers.

/// One stay of a connection's player in the world. Made only by `next`, from
/// the connection's last one, so no other process can name a stay it was not
/// given.
pub opaque type Stay {
  Stay(number: Int)
}

/// The stay before a connection's first: no join is asked with it, so no message
/// names it.
pub fn none_yet() -> Stay {
  Stay(number: 0)
}

/// The stay after `stay`: a join asks with it, and it names no earlier stay.
pub fn next(stay stay: Stay) -> Stay {
  Stay(number: stay.number + 1)
}
