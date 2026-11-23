//// The other players a player's cast can name: the ones in its picture whose connection
//// the map named, which a tell to them is addressed by.
////
//// ```
//// map: SeenBy(by, stay, unit_id) ─▶ viewers: Dict(ConnectionId, Viewer)
//// map and peer news: ShownPlayer units ─▶ picture: Dict(unit_id, Shown)
////                                       viewers + picture ─▶ in_sight ─▶ Dict(unit_id, PlayerAddress)
//// ```
////
//// - A player is in sight when its unit is a shown player of the picture and the map named
////   its connection as one that sees this player: the picture alone holds no connection to
////   tell, and a viewer alone is a player the client has not been sent (the client's cast
////   names only a unit it shows, `opcode.0x9a`).
//// - A viewer's stay is the one its latest `SeenBy` named, so a player that camped and came
////   back is addressed in its new stay.

import genesis_prime/game/shown
import genesis_prime/step.{type ConnectionId}
import genesis_prime/world_map/stay.{type Stay}
import gleam/dict.{type Dict}
import gleam/list

/// A player who sees this connection's player, as the map's `SeenBy` named it: the stay
/// its connection is in and the unit id the map gave it.
pub type Viewer {
  Viewer(stay: Stay, unit_id: Int)
}

/// A player in sight, as its notice named it: what a tell to its connection is addressed
/// by.
pub type PlayerAddress {
  PlayerAddress(connection: ConnectionId, unit_id: Int, stay: Stay)
}

/// The players in sight by unit id: each viewer whose unit the picture shows as a player.
pub fn in_sight(
  viewers viewers: Dict(ConnectionId, Viewer),
  picture picture: shown.Picture,
) -> Dict(Int, PlayerAddress) {
  dict.to_list(viewers)
  |> list.filter_map(fn(entry) {
    let #(connection, Viewer(stay:, unit_id:)) = entry
    case dict.get(picture, unit_id) {
      Ok(shown.ShownPlayer(..)) ->
        Ok(#(unit_id, PlayerAddress(connection:, unit_id:, stay:)))
      Ok(shown.ShownCreature(..)) | Ok(shown.ShownObject(..)) | Error(Nil) ->
        Error(Nil)
    }
  })
  |> dict.from_list
}
