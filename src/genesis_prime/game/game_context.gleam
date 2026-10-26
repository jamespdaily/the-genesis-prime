//// What the rules of character select and entering the world read beyond
//// their state, made from the loaded game tables, the server's time and the
//// settings of the game server.

import genesis_prime/character/character.{type Place}
import genesis_prime/game/game_session.{type Context}
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/loader/store.{type Tables}

/// The context for one input. `server_time` is the time as a Windows
/// FILETIME, `realm_id` the realm the connection is on and `start` the place a
/// character made from a CharacterCreation row starts at. The CharacterCreation
/// table gives the rows, the XpPerLevel table the level an experience gives
/// and the World table the worlds that exist.
pub fn build(
  tables tables: Tables,
  start start: fn(CharacterCreation) -> Result(Place, Nil),
  realm_id realm_id: Int,
  server_time server_time: Int,
) -> Context {
  todo as "the context of one input"
}
