//// What the tests that hold the server's Proxies share: the set with none in it, which
//// a connection made for another test is given, and whether a set changes the plan of a
//// base.

import character_tables
import genesis_prime/game/server_proxy.{type ServerProxies}
import genesis_prime/game/spell_plan.{type Plans}
import gleam/dict

/// A set with no Proxy in it: the rows of an empty table select to it.
pub fn none() -> ServerProxies {
  let assert Ok(none) =
    server_proxy.select(
      rows: [],
      tables: character_tables.shared(),
      plans: dict.new(),
    )
    as "no rows select"
  none
}

/// Whether planting the Proxies changes the plan of the base.
pub fn changes(
  proxies proxies: ServerProxies,
  plans plans: Plans,
  base base: Int,
) -> Bool {
  dict.get(server_proxy.planted_into(plans:, proxies:), base)
  != dict.get(plans, base)
}
