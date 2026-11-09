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
////   must reach the welcome of its parent 35. The walk is done once, at load, for every
////   zone of the table. A parent id with no row ends the walk with no welcome, as in
////   `top_zone`; a cycle in the chain fails the load.
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
//// | the parent chain of a zone is a cycle | the load stops, naming `WorldZone` and the zone |
//// | a zone has no welcome in its chain, or no row at all | nothing is sent |
//// | the old zone and the new have the same welcome, or are the same zone | nothing is sent |

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/message/server_tutorial.{ServerTutorial}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/tutorial
import genesis_prime/table/world_zone
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set.{type Set}

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
/// WorldZone or Tutorial row the tables lack, a Tutorial row that is not of category 29,
/// and a zone whose parent chain is a cycle.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(ZoneWelcomes, List(Refusal)) {
  select_over(
    rows:,
    parents: list.map(world_zone.all(tables), fn(zone) {
      #(zone.id, zone.parent_zone_id)
    }),
    categories: dict.from_list(
      list.map(tutorial.all(tables), fn(row) {
        #(row.id, row.tutorial_category_enum)
      }),
    ),
  )
}

/// The same over the client's rows given as pairs of a WorldZone's id and its
/// `parentZoneId`, and pairs of a Tutorial id and its category.
pub fn select_over(
  rows rows: List(Row),
  parents parents: List(#(Int, Int)),
  categories categories: Dict(Int, Int),
) -> Result(ZoneWelcomes, List(Refusal)) {
  let parent_of = dict.from_list(parents)
  let row_refusals =
    list.filter_map(rows, fn(row) {
      case refused(row:, parent_of:, categories:) {
        Ok(rule) ->
          Ok(Refusal(
            table: "zone_welcome",
            row: RowId(row.world_zone_id),
            rule:,
          ))
        Error(Nil) -> Error(Nil)
      }
    })
  let own =
    dict.from_list(
      list.map(rows, fn(row) { #(row.world_zone_id, row.tutorial_id) }),
    )
  let #(by_zone, cycle_refusals) =
    list.fold(parents, #(dict.new(), []), fn(so_far, pair) {
      let #(by_zone, cycles) = so_far
      let zone = pair.0
      case walk(zone:, own:, parent_of:, seen: set.new()) {
        Welcomed(tutorial_id:) -> #(
          dict.insert(by_zone, zone, tutorial_id),
          cycles,
        )
        NoWelcome -> #(by_zone, cycles)
        Cycle -> #(by_zone, [
          Refusal(
            table: "WorldZone",
            row: RowId(zone),
            rule: "its parentZoneId chain leads back to itself, so no welcome is found by walking it",
          ),
          ..cycles
        ])
      }
    })
  case list.append(row_refusals, list.reverse(cycle_refusals)) {
    [] -> Ok(ZoneWelcomes(by_zone:))
    [_, ..] as refusals -> Error(refusals)
  }
}

/// Why the row is refused, or `Error(Nil)` when it is not.
fn refused(
  row row: Row,
  parent_of parent_of: Dict(Int, Int),
  categories categories: Dict(Int, Int),
) -> Result(String, Nil) {
  use <- bool.guard(
    when: !dict.has_key(parent_of, row.world_zone_id),
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

/// Where the walk up from a zone ended.
type Walked {
  /// A zone of the chain has this Tutorial row.
  Welcomed(tutorial_id: Int)
  /// No zone of the chain has a row.
  NoWelcome
  /// The chain met a zone twice.
  Cycle
}

/// The welcome of `zone`: its own row, else the walk's result from its parent, which ends
/// when the parent is 0 or has no WorldZone row.
fn walk(
  zone zone: Int,
  own own: Dict(Int, Int),
  parent_of parent_of: Dict(Int, Int),
  seen seen: Set(Int),
) -> Walked {
  use <- bool.guard(when: set.contains(seen, zone), return: Cycle)
  case dict.get(own, zone) {
    Ok(tutorial_id) -> Welcomed(tutorial_id:)
    Error(Nil) ->
      case dict.get(parent_of, zone) {
        Ok(parent) if parent != 0 ->
          case dict.has_key(parent_of, parent) {
            True ->
              walk(zone: parent, own:, parent_of:, seen: set.insert(seen, zone))
            False -> NoWelcome
          }
        Ok(_) | Error(Nil) -> NoWelcome
      }
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
