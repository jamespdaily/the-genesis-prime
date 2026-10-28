//// A player character's unit as message 0x262 creates it in the client: the
//// character's own values, alive at its saved place, with the body the
//// character list shows. The map sends other players' units with it in a
//// later card, so it lives with the map, not the connection.
////
//// - **Alive:** stat 0 (health) above 0, or the client creates the player
////   dead (0x140457bc5). The client holds no player health by class and
////   level (0x1404585c0), and no retail record has one yet, so health and
////   property 7 (Base Health) are `stand_in_health`, 136, the client's
////   level-1 creature Base Health (CreatureLevel row 1). Missing: a player's
////   health, listed in the coverage measure until a stats card owns it.
//// - **Place:** one kind 2 movement command at the saved position; after 0xAD
////   the client never drops the player to the ground, so it must be on the
////   floor (0x1404586e0, 0x1403e828a).
//// - **Body:** the item visuals the character list sends
////   (genesis_prime/game/appearance), and the stored bone values
////   (opcode.0x262.player_fields).
//// - **PvP flags** 0: the 3 bits are the unit's PvP flags, not the path
////   (0x1403b48b0).
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.player_fields, opcode.0x262.unit_fields).

import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/store.{type Character}

/// A level-1 player's health until a stats card gives the real one: the
/// client's level-1 creature Base Health (0x1404585c0).
pub const stand_in_health = 136

/// Message 0x262 for the character as the unit `unit_id`, in the realm, with
/// the body `visuals`.
pub fn create(
  character character: Character,
  unit_id unit_id: Int,
  realm_id realm_id: Int,
  visuals visuals: List(ItemVisual),
) -> UnitCreatePlayer {
  todo as "built in the build"
}
