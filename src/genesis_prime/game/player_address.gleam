//// The other players a player's cast can name: the ones in its picture whose unit address
//// the map named, which a tell to them is addressed by.
////
//// ```
//// map: SeenBy(by, unit_id, generation) ─▶ viewers: Dict(UnitAddress, Viewer)
//// map and peer news: ShownPlayer units ─▶ picture: Dict(unit_id, Shown)
////                                       viewers + picture ─▶ in_sight ─▶ Dict(unit_id, PlayerAddress)
////                                                         ─▶ states_in_sight ─▶ Dict(unit_id, PlayerState)
//// ```
////
//// - A player is in sight when its unit is a shown player of the picture and the map named
////   its address as one that sees this player: the picture alone holds no connection to
////   tell, and a viewer alone is a player the client has not been sent (the client's cast
////   names only a unit it shows, `opcode.0x9a`).
//// - Viewers are keyed by address, so a viewer that camped and came back holds two entries
////   until the old one goes. It holds one because the map sends each owner `UnseenBy` for
////   the old address before `SeenBy` for the new one, in one sender's order, so a player
////   that came back is addressed by its new address only.

import genesis_prime/game/player_state.{type PlayerState}
import genesis_prime/game/shown
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/dict.{type Dict}
import gleam/list

/// A player who sees this connection's player, as the map's `SeenBy` named it: the unit id
/// the map gave it and the generation of its sight, which stamps each move sent to it
/// (genesis_prime/game/move_stamp). The viewer's address is its key.
pub type Viewer {
  Viewer(unit_id: Int, generation: Generation)
}

/// A player in sight, as its notice named it: the address a tell to its connection is
/// sent to, and the unit id its client knows it by.
pub type PlayerAddress {
  PlayerAddress(address: UnitAddress, unit_id: Int)
}

/// The players in sight by unit id: each viewer whose unit the picture shows as a player.
pub fn in_sight(
  viewers viewers: Dict(UnitAddress, Viewer),
  picture picture: shown.Picture,
) -> Dict(Int, PlayerAddress) {
  dict.to_list(viewers)
  |> list.filter_map(fn(entry) {
    let #(address, Viewer(unit_id:, ..)) = entry
    case dict.get(picture, unit_id) {
      Ok(shown.ShownPlayer(..)) ->
        Ok(#(unit_id, PlayerAddress(address:, unit_id:)))
      Ok(shown.ShownCreature(..)) | Ok(shown.ShownObject(..)) | Error(Nil) ->
        Error(Nil)
    }
  })
  |> dict.from_list
}

/// What a press judges of each player in sight, by unit id: the picture's state of each
/// viewer whose unit it shows as a player (the same units as `in_sight`).
pub fn states_in_sight(
  viewers viewers: Dict(UnitAddress, Viewer),
  picture picture: shown.Picture,
) -> Dict(Int, PlayerState) {
  dict.to_list(viewers)
  |> list.filter_map(fn(entry) {
    let #(_, Viewer(unit_id:, ..)) = entry
    case dict.get(picture, unit_id) {
      Ok(shown.ShownPlayer(state:)) -> Ok(#(unit_id, state))
      Ok(shown.ShownCreature(..)) | Ok(shown.ShownObject(..)) | Error(Nil) ->
        Error(Nil)
    }
  })
  |> dict.from_list
}
