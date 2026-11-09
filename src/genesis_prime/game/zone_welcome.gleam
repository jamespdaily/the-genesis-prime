//// The "Welcome to" popup of a zone: the Tutorial row the server tells the client to
//// show when a player lands in a zone or walks into one whose welcome differs. The
//// client's tables link no zone to a Tutorial row, so the link is the server's choice
//// (the `zone_welcome` content table); the client then decides itself whether to show
//// the row.
////
//// ```
//// content.load: rows ─▶ select(rows, tables) ─▶ ZoneWelcomes | refusals (the load stops)
//// terrain loaded 0xf2 (zone Z)        ─▶ on_terrain_loaded(Z)        ─▶ [0x179 Tutorial] | []
//// zone changed 0x63a (old O, new N)   ─▶ on_zone_changed(O, N)       ─▶ [0x179 Tutorial] | []
////
//// welcome(Z): the row of Z, else of its nearest parent that has one, walking parentZoneId
////   648 Landing Site ─▶ 35 (row 332, the Northern Wilds)
////   1417 ─▶ 1414 (row 331)        6009 ─▶ 4962 ─▶ 4961 (no row: nothing is sent)
//// ```
////
//// - **The rule keeps nothing.** The client refuses a repeat by itself: a Tutorial id in
////   its viewed set (one for the whole character, saved) or its pending set is dropped
////   (TriggerTutorial `0x140437a10`), so a repeated 0x179 costs the client one dropped
////   message. A rule with no state needs no field on the connection.
//// - **The category passes on a fresh client.** The mask TriggerTutorial tests is the
////   client's `tutorial.visibilityFlags` (`0x140c3b380`), which starts with every bit set,
////   so category 29 (the welcomes, `Tutorial.tutorialCategoryEnum.29`) shows unless the
////   player hid the category in the tutorial window.
//// - **Which zone.** Both reports carry the most specific WorldZone under the player and
////   never a parent (`opcode.0xf2`, `opcode.0x63a`), so a landing in 648 Landing Site
////   must reach the welcome of its parent 35. The walk is `top_zone.chain`, done once, at
////   load, for every zone of the table. A parent id with no row ends the chain, as in
////   `top_zone`; the tables' load has already refused a cycle.
//// - **When.** A landing sends the zone's welcome. A walk sends the new zone's welcome
////   only when it differs from the old zone's, so sub-zones of one welcome show it once.
////   The client sends 0x63a with the kept zone as both old and new when it repeats a
////   report (`opcode.0x63a`), which sends nothing.
////
//// What happens at each failure point:
////
//// | Point | What happens |
//// |---|---|
//// | a row names a WorldZone the table lacks | the load stops, naming `zone_welcome` and the row |
//// | a row names a Tutorial row the table lacks, or one not of category 29 | the load stops, naming the row and the reason |
//// | a zone has no welcome in its chain, or no row at all | nothing is sent |
//// | the old zone and the new have the same welcome, or are the same zone | nothing is sent |

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/game/top_zone
import genesis_prime/message/server_tutorial.{ServerTutorial}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/tutorial
import genesis_prime/table/world_zone
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// The Tutorial category of the welcomes (`Tutorial.tutorialCategoryEnum.29`).
const welcome_category = 29

/// One row of the zone_welcome table as the load reads it: the WorldZone and the
/// Tutorial row it shows.
pub type Row {
  Row(world_zone_id: Int, tutorial_id: Int)
}

/// The Tutorial id each WorldZone shows, found by the walk up the parent chain for every
/// zone of the table that has one.
pub opaque type ZoneWelcomes {
  ZoneWelcomes(by_zone: Dict(Int, Int))
}

/// The welcomes of the rows over the client's tables, or every refusal: a row whose
/// WorldZone or Tutorial row the tables lack, and a Tutorial row that is not of
/// category 29. Each zone of the table gets the row of the nearest zone of its chain
/// (`top_zone.chain`) that has one.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(ZoneWelcomes, List(Refusal)) {
  let categories =
    dict.from_list(
      list.map(tutorial.all(tables), fn(row) {
        #(row.id, row.tutorial_category_enum)
      }),
    )
  let refusals =
    list.filter_map(rows, fn(row) {
      refused(row:, tables:, categories:)
      |> result.map(fn(rule) {
        Refusal(table: "zone_welcome", row: RowId(row.world_zone_id), rule:)
      })
    })
  use <- bool.guard(when: refusals != [], return: Error(refusals))
  let own =
    dict.from_list(
      list.map(rows, fn(row) { #(row.world_zone_id, row.tutorial_id) }),
    )
  Ok(
    ZoneWelcomes(
      by_zone: list.fold(world_zone.all(tables), dict.new(), fn(by_zone, zone) {
        case list.find_map(top_zone.chain(tables, zone.id), dict.get(own, _)) {
          Ok(tutorial_id) -> dict.insert(by_zone, zone.id, tutorial_id)
          Error(Nil) -> by_zone
        }
      }),
    ),
  )
}

/// Why the row is refused, or `Error(Nil)` when it is not.
fn refused(
  row row: Row,
  tables tables: table_store.Tables,
  categories categories: Dict(Int, Int),
) -> Result(String, Nil) {
  use <- bool.guard(
    when: top_zone.chain(tables, row.world_zone_id) == [],
    return: Ok(
      "WorldZone "
      <> int.to_string(row.world_zone_id)
      <> " has no row in the client's table",
    ),
  )
  case dict.get(categories, row.tutorial_id) {
    Error(Nil) ->
      Ok(
        "Tutorial "
        <> int.to_string(row.tutorial_id)
        <> " has no row in the client's table",
      )
    Ok(category) if category != welcome_category ->
      Ok(
        "Tutorial "
        <> int.to_string(row.tutorial_id)
        <> " is of category "
        <> int.to_string(category)
        <> ", not category 29, the welcomes",
      )
    Ok(_) -> Error(Nil)
  }
}

/// The frames of the client's terrain loaded (0xf2) in this zone: the zone's welcome, or
/// none.
pub fn on_terrain_loaded(
  welcomes welcomes: ZoneWelcomes,
  world_zone_id world_zone_id: Int,
) -> List(Frame) {
  case dict.get(welcomes.by_zone, world_zone_id) {
    Ok(tutorial_id) -> [server_tutorial_frame(tutorial_id:)]
    Error(Nil) -> []
  }
}

/// The frames of the client's zone changed (0x63a): the new zone's welcome when the
/// old zone's is another row or none, else none.
pub fn on_zone_changed(
  welcomes welcomes: ZoneWelcomes,
  old_world_zone_id old_world_zone_id: Int,
  new_world_zone_id new_world_zone_id: Int,
) -> List(Frame) {
  case
    dict.get(welcomes.by_zone, new_world_zone_id),
    dict.get(welcomes.by_zone, old_world_zone_id)
  {
    Ok(new), Ok(old) if new == old -> []
    Ok(new), Ok(_) | Ok(new), Error(Nil) -> [
      server_tutorial_frame(tutorial_id: new),
    ]
    Error(Nil), _ -> []
  }
}

/// 0x179 with the Tutorial id the client queues to show (`opcode.0x179`).
fn server_tutorial_frame(tutorial_id tutorial_id: Int) -> Frame {
  let assert Ok(body) = server_tutorial.encode(ServerTutorial(tutorial_id:))
    as "a Tutorial id of the table fits the message's 32 bits"
  Frame(message_id: server_tutorial.message_id, body:)
}
