//// The zones' welcomes (genesis_prime/game/zone_welcome): which Tutorial row a zone
//// shows when a player lands in it (the client's terrain loaded, 0xf2) or walks into it
//// (the client's zone changed, 0x63a), from the client's own WorldZone rows (the parent
//// chain) and Tutorial rows (the category), and the rows the load refuses.
////
//// The expected frames are written from the wire layout, not built by the encoder: the
//// client reads one 32-bit value from 0x179 (`opcode.0x179`), least significant byte
//// first, so Tutorial 332 is 0x14C and goes as 4c 01 00 00, and 233 is 0xE9.

import character_tables
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/content/refusal.{RowId}
import genesis_prime/game/zone_welcome.{Row}
import gleam/list
import gleam/string
import owned_test
import zone_welcome_support

/// The frame the client reads a Tutorial id from: 0x179 and the id in 32 bits.
fn server_tutorial(tutorial_id tutorial_id: Int) -> Frame {
  Frame(message_id: 0x0179, body: <<tutorial_id:size(32)-little>>)
}

pub fn a_landing_sub_zone_gets_its_parents_welcome_test() -> Nil {
  use <- owned_test.run(5000)
  let welcomes = zone_welcome_support.landings()
  list.each(
    [
      #(648, 332, "WorldZone 648 Landing Site -> 35 (the Northern Wilds)"),
      #(1417, 331, "WorldZone 1417 -> 1414 (Everstar Grove)"),
      #(1411, 330, "WorldZone 1411 -> 1305 -> 1304 (Levian Bay)"),
      #(1236, 329, "WorldZone 1236 -> 623 -> 622 (Crimson Isle)"),
    ],
    fn(landing) {
      let #(zone, tutorial, chain) = landing
      assert zone_welcome.on_terrain_loaded(welcomes:, world_zone_id: zone)
        == [server_tutorial(tutorial_id: tutorial)]
        as chain
    },
  )
  assert zone_welcome.on_terrain_loaded(welcomes:, world_zone_id: 593)
    == [server_tutorial(tutorial_id: 233)]
    as "WorldZone 593 has a row of its own (Settler's Reach), so no walk is needed"
}

pub fn a_zone_change_sends_only_when_the_welcome_changes_test() -> Nil {
  use <- owned_test.run(5000)
  let welcomes = zone_welcome_support.landings()
  assert zone_welcome.on_zone_changed(
      welcomes:,
      old_world_zone_id: 648,
      new_world_zone_id: 593,
    )
    == [server_tutorial(tutorial_id: 233)]
    as "opcode.0x63a: from the Northern Wilds' Landing Site into Settler's Reach the welcome changes from 332 to 233"
  assert zone_welcome.on_zone_changed(
      welcomes:,
      old_world_zone_id: 6009,
      new_world_zone_id: 648,
    )
    == [server_tutorial(tutorial_id: 332)]
    as "from a zone with no welcome into one that has it, the welcome is new"
  assert zone_welcome.on_zone_changed(
      welcomes:,
      old_world_zone_id: 590,
      new_world_zone_id: 596,
    )
    == []
    as "WorldZone 590 and 596 are both under 35: one welcome (332), shown once"
  assert zone_welcome.on_zone_changed(
      welcomes:,
      old_world_zone_id: 648,
      new_world_zone_id: 648,
    )
    == []
    as "opcode.0x63a: the 0x636 path has the client send the kept zone as both old and new"
  assert zone_welcome.on_zone_changed(
      welcomes:,
      old_world_zone_id: 648,
      new_world_zone_id: 6009,
    )
    == []
    as "walking out into a zone with no welcome shows nothing"
}

pub fn a_zone_with_no_welcome_up_its_chain_sends_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let welcomes = zone_welcome_support.landings()
  list.each([6009, 4962, 4961], fn(zone) {
    assert zone_welcome.on_terrain_loaded(welcomes:, world_zone_id: zone) == []
      as "WorldZone 6009 -> 4962 -> 4961, whose parent is 0: no row of the chain has a welcome (the training simulation shows none)"
  })
  assert zone_welcome.on_terrain_loaded(welcomes:, world_zone_id: 0) == []
    as "zone 0 is no zone"
  assert zone_welcome.on_terrain_loaded(welcomes:, world_zone_id: 1132) == []
    as "a zone the table has no row for shows nothing (chat.zone_reach: the client reports such zones)"
}

pub fn a_row_the_tables_refuse_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let tables = character_tables.content_tables()
  let refused =
    zone_welcome.select(
      rows: [
        Row(world_zone_id: 35, tutorial_id: 332),
        Row(world_zone_id: 99_999, tutorial_id: 332),
        Row(world_zone_id: 590, tutorial_id: 99_999),
        Row(world_zone_id: 596, tutorial_id: 1),
      ],
      tables:,
    )
  let assert Error(refusals) = refused
    as "the three bad rows are refused and the good one with them does not save the load"
  assert list.map(refusals, fn(refusal) { #(refusal.table, refusal.row) })
    == [
      #("zone_welcome", RowId(99_999)),
      #("zone_welcome", RowId(590)),
      #("zone_welcome", RowId(596)),
    ]
    as "each bad row is named, in the order of the rows"
  let assert [no_zone, no_tutorial, wrong_category] = refusals
  assert string.contains(no_zone.rule, "WorldZone")
    as "the table holds no WorldZone row 99999"
  assert string.contains(no_tutorial.rule, "Tutorial")
    as "the table holds no Tutorial row 99999"
  assert string.contains(wrong_category.rule, "category 29")
    as "Tutorial.tutorialCategoryEnum.29: Tutorial row 1 has category 0, and only 29 rows are welcomes"
}
