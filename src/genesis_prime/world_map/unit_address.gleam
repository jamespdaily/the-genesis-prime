//// The name of one unit of a player in a run of a map: the map, the run and the
//// number the map issued for the unit's join. A message about a player's unit
//// names it by this address, so a message for a unit that ended never names a
//// unit that took its place.
////
//// - **Why an address and not a unit id.** A unit id is the client's name for a
////   unit and the map gives ids from 1 again in each run, so an id can name two
////   units over time. An address is never issued twice on a node: the run's
////   incarnation is unique for the node (`genesis_prime/world_map/registry`) and
////   the map's number only grows within it.
//// - **Who issues.** Only the map, once for each join, in its join step
////   (`genesis_prime/world_map/map`). Another process holds an address only as
////   the map sent it (`Joined`, `Seen`, `RingMember`) and names it back.
//// - **The connection's stay.** `number` is the map's issue number, not the
////   connection's stay: the connection keeps its own stay count beside the
////   address (`genesis_prime/world_map/stay`), and its fence compares that.

import genesis_prime/world_map/map_id.{type MapId}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/order
import gleam/set.{type Set}

/// One unit of a player in one run of a map. Made only by `issue`.
pub opaque type UnitAddress {
  UnitAddress(map: MapId, incarnation: Int, number: Int, joiner: Int)
}

/// The address the map `map` in the run `incarnation` issues as its `number`th, for the
/// connection numbered `joiner`: the map counts `number` up from 1 and never issues one
/// twice in a run. `joiner` is the order a creature ranks players that tie by
/// (`compare`), so a creature picks among players as it did when it named their
/// connections; it is the connection's number and the creature reads nothing else of it.
pub fn issue(
  map map: MapId,
  incarnation incarnation: Int,
  number number: Int,
  joiner joiner: Int,
) -> UnitAddress {
  UnitAddress(map:, incarnation:, number:, joiner:)
}

/// The number of the connection the address was issued for.
pub fn joiner(address address: UnitAddress) -> Int {
  address.joiner
}

/// The number the map issued the address as.
pub fn number(address address: UnitAddress) -> Int {
  address.number
}

/// The order of two addresses: the number of the connection each was issued for, as a
/// creature ordered connections, then the number of the address, then the run, so two
/// addresses of one connection (it joined again) and of two runs are ordered too. Where a
/// creature picks among players that tie (the first target, a tie of threat), it picks the
/// lowest by this order: a choice of the server's, since the
/// client holds no rule for it, and the one it made before addresses named players.
pub fn compare(
  first first: UnitAddress,
  second second: UnitAddress,
) -> order.Order {
  int.compare(first.joiner, second.joiner)
  |> order.break_tie(int.compare(first.number, second.number))
  |> order.break_tie(int.compare(first.incarnation, second.incarnation))
}

/// The addresses of a set in the order of `compare`, so what is sent to each is the same
/// on every run.
pub fn sorted(addresses addresses: Set(UnitAddress)) -> List(UnitAddress) {
  list.sort(set.to_list(addresses), compare)
}

/// The entries of a dict keyed by address in the order of `compare` of the addresses, so
/// what is sent to each is the same on every run.
pub fn sorted_entries(
  entries entries: Dict(UnitAddress, value),
) -> List(#(UnitAddress, value)) {
  list.sort(dict.to_list(entries), fn(first, second) {
    compare(first: first.0, second: second.0)
  })
}
