//// The selection and the checks of the spawn table's rows
//// (`genesis_prime/world_map/spawn`, `select`), run as the pure function it is:
//// rows and the client's tables in, the spawns that start, the refusals and the
//// coverage out. Expected values come from these places.
//// - The decode of issue 375 (its facts `world_data.entity_type`,
////   `world_data.creature_disposition`, `world_data.spawn_checks`, `0x140649e20`,
////   `0x140787760`, `0x140717560`, `0x1403ad540`): only NonPlayer rows start; a
////   faction 0 row, a row Friendly to both player factions, a row whose creature
////   has an NPC link and a row whose health stat is 0 do not; a row with no stats
////   starts, with the creature's own level and health.
//// - The client's faction levels: faction 219 is level 10 to 165 through the
////   parent walk (Friendly to both), faction 1441 is level 0 to 167 and 10 to 166
////   (Hostile to Exile, Friendly to Dominion), faction 189 relates only to 165
////   (Hostile to both) and faction 174 has no relationship (level 5, Neutral).
//// - The client's Creature2 validity rules (`0x140485790`, `0x140483d20`): a row
////   whose creature the client would not load is refused, naming the rule.
//// - The creature trace of the combat core (facts `Creature2.73464` and
////   `Creature2.73465`, `0x1404585c0`): the Virtual Battle Beast is level 1 with
////   Base Health 135.97028 x 1.0 x 0.387 x 1.0 = 52.6205, so 52; the Virtual
////   Defense Dagun is level 1 with the archetype's 0.96, Base Health 50.5157, so 50.
//// - The rule of the creature's values (the module's doc comment): an override
////   of property 7 is Base Health; a difficulty or resist id of 0 needs no row,
////   and the difficulty multiplies by 1.0.
//// Every test loads the client's committed rows, so it runs in CI.

import character_tables
import fixture_tables
import genesis_prime/content/refusal.{Refusal}
import genesis_prime/game/hit.{Blow}
import genesis_prime/game/start_place
import genesis_prime/table/id.{Creature2Id, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/spawn.{
  type Row, type Selection, Dead, FriendlyToBoth, NoFaction, NpcLink,
}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/static_object.{type StaticObject, StaticObject}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import place_support
import planted_table.{Float, Integer}
import rating_support
import spawn_support

/// The selection of the rows against the client's rows.
fn selected(rows rows: List(Row)) -> Selection {
  spawn.select(
    rows:,
    tables: character_tables.content_tables(),
    formulas: rating_support.formulas(),
    kinds: spawn_support.kinds(),
  )
}

/// The selection of the rows against the content load over these tables, a
/// test's edit of the client's rows.
fn selected_over(
  tables tables: store.Tables,
  rows rows: List(Row),
) -> Selection {
  spawn.select(
    rows:,
    tables: character_tables.content_over(tables:),
    formulas: rating_support.formulas(),
    kinds: spawn_support.kinds(),
  )
}

/// The selection of the rows when the client's Creature2 73464, the Virtual
/// Battle Beast, holds these cells in place of its own.
fn selected_beast_changed(
  changes changes: List(#(String, planted_table.Cell)),
  rows rows: List(Row),
) -> Selection {
  use tables <- fixture_tables.changed(
    table: "Creature2",
    id: 73_464,
    with: changes,
  )
  selected_over(tables:, rows:)
}

/// The ids of the spawns that start, in id order.
fn started(selection: Selection) -> List(Int) {
  dict.values(selection.worlds)
  |> list.flat_map(fn(world) { dict.keys(world.by_id) })
  |> list.map(fn(id) {
    let SpawnId(number) = id
    number
  })
  |> list.sort(int.compare)
}

/// How many NonPlayer rows of the world were left out for the reason.
fn left_out(
  selection selection: Selection,
  reason reason: spawn.LeftOut,
) -> Int {
  let assert Ok(coverage) =
    list.find(selection.coverage, fn(world) { world.world_id == 3460 })
    as "the world has a coverage"
  let assert Ok(found) =
    list.find(coverage.left_out, fn(entry) { entry.0 == reason })
    as "the coverage counts the reason"
  found.1
}

pub fn only_nonplayer_rows_start_and_every_other_type_is_counted_for_the_coverage_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140649e20: type 0 is NonPlayer, 2 Destructible, 5 Harvest (`world_data.entity_type`).
  let selection =
    selected(rows: [
      spawn_support.beast_row(number: 1),
      spawn.Row(..spawn_support.beast_row(number: 2), entity_type: 2),
      spawn.Row(..spawn_support.beast_row(number: 3), entity_type: 5),
      spawn.Row(..spawn_support.beast_row(number: 4), entity_type: 5),
    ])
  assert started(selection) == [1] as "the NonPlayer row starts and no other"
  let assert [coverage] = selection.coverage as "one world"
  assert coverage.started == 1
  assert list.sort(coverage.other_types, fn(first, second) {
      int.compare(first.0, second.0)
    })
    == [#(2, 1), #(5, 2)]
    as "each other type counted: one Destructible and two Harvest"
}

// ------------------------------------------- static objects
//
// The rows of unit types 4 (Door), 8 (Collectible), 10 (Simple), 11 (Platform),
// 12 (Mailbox), 13 (Turret), 14 (InstancePortal) and 32 (SimpleCollidable), which
// load as static objects (`genesis_prime/world_map/static_object`).
// Expected values come from these places.
// - The trace's field table (the issue's "Client trace" of the static objects,
//   `opcode.0x262.simple`): an object carries its row's entity type, Creature2 id,
//   place and facing, both factions (0 included), display, outfit, quest checklist
//   index, `active_prop_id` and WorldSocket id. Types 10 and 11 carry stat 0 and
//   stat 10 when the row records them, truncated, and nothing else; type 32's level
//   and health follow the creature rule (this file's creature tests: minLevel 1
//   and Base Health 52 for the Battle Beast's row, a recorded stat truncated), the
//   coordinator's settlement of the trace's question 1.
// - `0x140485790` and `0x14047c210`, checks 2 and 3 of the trace: a static row whose
//   creature the client would not load, or whose display or outfit has no row,
//   fails the load as a creature row does, naming the rule.
// - `0x140457a53` (check 4, opcode.0x262.simple (2)): type 32 is created dead
//   with health 0, so such a row is left out and counted; types 10 and 11 never
//   are, so a recorded 0 is sent as it stands.
// - `0x140457bc5`: types 4, 8, 12 and 14 are never created dead, as 10 and 11 are,
//   so they carry only the stats their row records; type 13 is not in that set, so
//   a turret follows type 32's rule: the creature's level and Base Health, and one
//   with health 0 is left out and counted.
// - Check 11 and `world_data.entity_type`: types 2, 5, 9 and 19 are other units,
//   counted by type.

/// The static objects of the selection, in id order.
fn objects_in(selection: Selection) -> List(StaticObject) {
  dict.values(selection.worlds)
  |> list.flat_map(fn(world) { dict.values(world.objects) })
  |> list.sort(fn(first, second) {
    let SpawnId(first) = first.id
    let SpawnId(second) = second.id
    int.compare(first, second)
  })
}

pub fn rows_of_types_10_11_and_32_load_as_static_objects_with_every_field_of_the_trace_test() -> Nil {
  use <- owned_test.run(5000)
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 1),
        entity_type: 10,
        area_id: 5967,
        x: 10.5,
        y: 20.25,
        z: -30.0,
        rotation_x: 1.5,
        faction_id: 0,
        base_faction_id: 0,
        checklist_index: 4,
        world_object_id: 0x369123456789,
        world_socket_id: 0x1234,
        health: Some(442.9),
        level: Some(3.0),
      ),
      spawn.Row(..spawn_support.beast_row(number: 2), entity_type: 11),
      spawn.Row(
        ..spawn_support.beast_row(number: 3),
        entity_type: 32,
        faction_id: 1441,
        base_faction_id: 1442,
        health: Some(50.0),
      ),
    ])
  assert selection.refusals == []
    as "every static row passes the client's checks"
  assert started(selection) == [] as "no static object starts a creature"
  let at = fn(x, y, z, yaw) {
    let assert Ok(place) =
      start_place.place(
        world_id: 3460,
        world_zone_id: 5967,
        x:,
        y:,
        z:,
        facing: start_place.Facing(yaw:, pitch: 0.0, roll: 0.0),
      )
      as "World 3460 is a world"
    place
  }
  let origin = fn() {
    place_support.at(world_id: 3460, world_zone_id: 0, x: 0.0, y: 0.0, z: 0.0)
  }
  assert objects_in(selection)
    == [
      StaticObject(
        id: SpawnId(1),
        unit_type: static_object.Simple,
        creature_id: Creature2Id(73_464),
        place: at(10.5, 20.25, -30.0, 1.5),
        level: Some(3),
        health: Some(static_object.Health(
          value: 442,
          source: unit_fields.Recorded,
        )),
        faction_id: 0,
        base_faction_id: 0,
        display_info_id: 26_565,
        outfit_info_id: 0,
        checklist_index: 4,
        world_object_id: 0x369123456789,
        world_socket_id: 0x1234,
      ),
      StaticObject(
        id: SpawnId(2),
        unit_type: static_object.Platform,
        creature_id: Creature2Id(73_464),
        place: origin(),
        level: option.None,
        health: option.None,
        faction_id: 1441,
        base_faction_id: 1441,
        display_info_id: 26_565,
        outfit_info_id: 0,
        checklist_index: 0,
        world_object_id: 0,
        world_socket_id: 0,
      ),
      StaticObject(
        id: SpawnId(3),
        unit_type: static_object.SimpleCollidable,
        creature_id: Creature2Id(73_464),
        place: origin(),
        level: Some(1),
        health: Some(static_object.Health(
          value: 50,
          source: unit_fields.Recorded,
        )),
        faction_id: 1441,
        base_faction_id: 1442,
        display_info_id: 26_565,
        outfit_info_id: 0,
        checklist_index: 0,
        world_object_id: 0,
        world_socket_id: 0,
      ),
    ]
    as "each object holds its row's type, creature, place, factions (0 kept), display, outfit, checklist index and world object link; types 10 and 11 the stats the row records, type 32 the creature rule's level (minLevel 1) and health"
}

pub fn a_static_row_whose_creature_has_no_row_or_is_not_loaded_by_the_client_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let selection =
    selected(
      rows: list.map([10, 11, 32], fn(entity_type) {
        spawn.Row(
          ..spawn_support.beast_row(number: entity_type),
          entity_type:,
          creature_id: 200_002,
        )
      }),
    )
  assert selection.refusals
    == list.map([10, 11, 32], fn(number) {
      Refusal(
        table: "spawn",
        row: refusal.RowId(number),
        rule: "Creature2 200002 has no row",
      )
    })
    as "type 10 would be an invisible unit with no report, 11 and 32 refused by the client: each fails the load"
  list.each([10, 11, 32], fn(entity_type) {
    let selection =
      selected_beast_changed(changes: [#("modelScale", Float(0.0))], rows: [
        spawn.Row(..spawn_support.beast_row(number: 1), entity_type:),
      ])
    let assert [Refusal(table: "spawn", row: refusal.RowId(1), rule:)] =
      selection.refusals
      as "a creature the client would not load refuses the static row"
    assert string.contains(rule, "Creature2 73464")
      && string.contains(rule, "modelScale is not above 0")
      as { "the rule names the creature and the client's rule: " <> rule }
  })
}

pub fn a_static_rows_display_must_be_its_creatures_and_have_a_row_and_its_outfit_a_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let not_in_group =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 1),
        entity_type: 10,
        display_info_id: 12_345,
      ),
      spawn.Row(
        ..spawn_support.beast_row(number: 2),
        entity_type: 32,
        outfit_info_id: 999,
      ),
    ])
  assert not_in_group.refusals
    == [
      Refusal(
        table: "spawn",
        row: refusal.RowId(1),
        rule: "display 12345 is not in the display group of Creature2 73464",
      ),
      Refusal(
        table: "spawn",
        row: refusal.RowId(2),
        rule: "Creature2OutfitInfo 999 has no row",
      ),
    ]
    as "a display outside the creature's group and an outfit with no row each fail the load"
  // The client's rows hold no Creature2DisplayInfo 99999: the beast's display
  // group, 28793, gets one more entry (a copy of its own, 27192) naming it.
  let no_display_row = {
    use tables <- fixture_tables.added(
      table: "Creature2DisplayGroupEntry",
      copy_of: 27_192,
      id: 1,
      with: [#("creature2DisplayInfoId", Integer(99_999))],
    )
    selected_over(tables:, rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 3),
        entity_type: 11,
        display_info_id: 99_999,
      ),
    ])
  }
  assert no_display_row.refusals
    == [
      Refusal(
        table: "spawn",
        row: refusal.RowId(3),
        rule: "Creature2DisplayInfo 99999 has no row",
      ),
    ]
    as "a display in the group with no Creature2DisplayInfo row draws no model: the load fails"
}

pub fn a_type_32_objects_health_follows_the_creature_rule_and_with_0_is_left_out_test() -> Nil {
  use <- owned_test.run(5000)
  let row = fn(number, health) {
    spawn.Row(..spawn_support.beast_row(number:), entity_type: 32, health:)
  }
  let selection =
    selected(rows: [
      row(1, option.None),
      row(2, Some(50.0)),
      row(3, Some(0.0)),
      row(4, Some(0.9)),
    ])
  assert list.map(objects_in(selection), fn(object) {
      let SpawnId(number) = object.id
      #(number, object.level, object.health)
    })
    == [
      #(
        1,
        Some(1),
        Some(static_object.Health(value: 52, source: unit_fields.ClientDefault)),
      ),
      #(
        2,
        Some(1),
        Some(static_object.Health(value: 50, source: unit_fields.Recorded)),
      ),
    ]
    as "no recorded health: the client's Base Health 52 at minLevel 1, above 0; recorded: as recorded; 0 (and 0.9, which truncates to 0) left out"
  let assert [coverage] = selection.coverage as "one world"
  assert coverage.objects_dead == 2
    as "the two type 32 rows the client would create dead are counted"
}

pub fn a_type_10_or_11_object_carries_only_the_stats_its_row_records_test() -> Nil {
  use <- owned_test.run(60_000)
  // The 107 world database spawns of types 10 and 11 whose creatures have minLevel
  // 0 (Creature2 15187 and 13 others, CreationTypeEnum 10) record no stats, and
  // CreatureLevel has no row 0: such a row loads, with no stat to send. The
  // Battle Beast's row stands in, with minLevel and maxLevel 0.
  let selection =
    selected_beast_changed(
      changes: [#("minLevel", Integer(0)), #("maxLevel", Integer(0))],
      rows: [
        spawn.Row(..spawn_support.beast_row(number: 1), entity_type: 10),
        spawn.Row(..spawn_support.beast_row(number: 2), entity_type: 11),
        spawn.Row(
          ..spawn_support.beast_row(number: 3),
          entity_type: 10,
          health: Some(0.0),
        ),
        spawn.Row(
          ..spawn_support.beast_row(number: 4),
          entity_type: 11,
          health: Some(442.9),
          level: Some(3.0),
        ),
      ],
    )
  assert selection.refusals == [] as "every row loads"
  assert list.map(objects_in(selection), fn(object) {
      let SpawnId(number) = object.id
      #(number, object.level, object.health)
    })
    == [
      #(1, option.None, option.None),
      #(2, option.None, option.None),
      #(
        3,
        option.None,
        Some(static_object.Health(value: 0, source: unit_fields.Recorded)),
      ),
      #(
        4,
        Some(3),
        Some(static_object.Health(value: 442, source: unit_fields.Recorded)),
      ),
    ]
    as "no recorded stat: none; a recorded health or level as recorded, 0 included, since types 10 and 11 are never created dead"
  let assert [coverage] = selection.coverage as "one world"
  assert coverage.objects_dead == 0 as "no type 10 or 11 object is left out"
}

pub fn other_unit_types_stay_out_and_the_coverage_counts_static_objects_by_type_and_world_test() -> Nil {
  use <- owned_test.run(5000)
  let others = [2, 5, 9, 19]
  let selection =
    selected(
      rows: list.flatten([
        list.map(others, fn(entity_type) {
          spawn.Row(
            ..spawn_support.beast_row(number: entity_type),
            entity_type:,
          )
        }),
        [
          spawn.Row(..spawn_support.beast_row(number: 100), entity_type: 10),
          spawn.Row(..spawn_support.beast_row(number: 101), entity_type: 10),
          spawn.Row(..spawn_support.beast_row(number: 102), entity_type: 11),
          spawn.Row(..spawn_support.beast_row(number: 103), entity_type: 32),
          spawn.Row(
            ..spawn_support.beast_row(number: 104),
            entity_type: 32,
            world_id: 22,
          ),
        ],
      ]),
    )
  assert list.map(objects_in(selection), fn(object) { object.id })
    == list.map([100, 101, 102, 103, 104], SpawnId)
    as "only the static types load as objects"
  let assert [world_22, world_3460] = selection.coverage
    as "two worlds, in world order"
  assert world_3460.other_types == list.map(others, fn(type_) { #(type_, 1) })
    as "each other type counted, by type"
  assert world_3460.objects_sent
    == list.zip(spawn.object_types, [0, 0, 2, 1, 0, 0, 0, 1])
    as "world 3460's objects sent, by type"
  assert world_22.objects_sent
    == list.zip(spawn.object_types, [0, 0, 0, 0, 0, 0, 0, 1])
    as "world 22's"
  assert spawn.describe_coverage(coverage: world_22)
    == "world 22: 0 spawns start; left out: no faction 0, friendly to both 0, an NPC link 0, health 0 0; static objects sent: type 4 0, type 8 0, type 10 0, type 11 0, type 12 0, type 13 0, type 14 0, type 32 1, left out dead 0; other entity types: none"
    as "the coverage line counts the static objects by type"
}

pub fn turret_health_follows_creature_rule_test() -> Nil {
  use <- owned_test.run(5000)
  let row = fn(number, entity_type, health, level) {
    spawn.Row(..spawn_support.beast_row(number:), entity_type:, health:, level:)
  }
  let selection =
    selected(rows: [
      row(1, 13, option.None, option.None),
      row(2, 13, Some(50.0), option.None),
      row(3, 13, Some(0.0), option.None),
      row(4, 4, option.None, option.None),
      row(5, 8, Some(0.0), Some(3.0)),
      row(6, 12, Some(442.9), option.None),
      row(7, 14, option.None, Some(2.0)),
    ])
  assert selection.refusals == [] as "every row passes the client's checks"
  assert list.map(objects_in(selection), fn(object) {
      let SpawnId(number) = object.id
      #(number, object.level, object.health)
    })
    == [
      #(
        1,
        Some(1),
        Some(static_object.Health(value: 52, source: unit_fields.ClientDefault)),
      ),
      #(
        2,
        Some(1),
        Some(static_object.Health(value: 50, source: unit_fields.Recorded)),
      ),
      #(4, option.None, option.None),
      #(
        5,
        Some(3),
        Some(static_object.Health(value: 0, source: unit_fields.Recorded)),
      ),
      #(
        6,
        option.None,
        Some(static_object.Health(value: 442, source: unit_fields.Recorded)),
      ),
      #(7, Some(2), option.None),
    ]
    as "a turret with no stats: minLevel 1 and the client's Base Health 52 above 0; recorded: as recorded; health 0 left out (0x140457bc5: type 13 is created dead); a door, collectible, mailbox or portal only what its row records, a recorded 0 included"
  let assert [coverage] = selection.coverage as "one world"
  assert coverage.objects_dead == 1
    as "the one turret the client would create dead is counted, and no other type is"
}

pub fn unsent_types_are_sent_and_counted_test() -> Nil {
  use <- owned_test.run(5000)
  let types = [4, 8, 12, 13, 14]
  let selection =
    selected(
      rows: list.map(types, fn(entity_type) {
        spawn.Row(
          ..spawn_support.beast_row(number: entity_type),
          entity_type:,
          world_id: 426,
        )
      }),
    )
  assert selection.refusals == [] as "every row passes the client's checks"
  assert list.map(objects_in(selection), fn(object) { object.id })
    == list.map(types, SpawnId)
    as "each row of types 4, 8, 12, 13 and 14 is sent as an object"
  let assert [coverage] = selection.coverage as "one world"
  assert coverage.world_id == 426
  assert coverage.objects_sent
    == list.zip(spawn.object_types, [1, 1, 0, 0, 1, 1, 1, 0])
    as "each counted by its type, in the coverage's order of the unit types' numbers"
  assert coverage.other_types == []
    as "none of these types is an other type any more"
  assert spawn.describe_coverage(coverage:)
    == "world 426: 0 spawns start; left out: no faction 0, friendly to both 0, an NPC link 0, health 0 0; static objects sent: type 4 1, type 8 1, type 10 0, type 11 0, type 12 1, type 13 1, type 14 1, type 32 0, left out dead 0; other entity types: none"
    as "the coverage line counts them by type"
}

pub fn a_row_whose_creature_has_no_row_or_whose_display_is_not_its_creatures_is_refused_naming_the_rule_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140485790: the client loads no creature without a Creature2 row; the
  // row's own display must be one of the creature's display group's.
  let selection =
    selected(rows: [
      spawn.Row(..spawn_support.beast_row(number: 7), creature_id: 200_002),
      spawn.Row(..spawn_support.beast_row(number: 8), display_info_id: 12_345),
    ])
  assert selection.refusals
    == [
      Refusal(
        table: "spawn",
        row: refusal.RowId(7),
        rule: "Creature2 200002 has no row",
      ),
      Refusal(
        table: "spawn",
        row: refusal.RowId(8),
        rule: "display 12345 is not in the display group of Creature2 73464",
      ),
    ]
    as "each refusal names the table, the row and the rule"
}

/// The refusal the selection gives the row of the beast when its Creature2 row
/// holds these cells.
fn refused_by(changes changes: List(#(String, planted_table.Cell))) -> String {
  let selection =
    selected_beast_changed(changes:, rows: [spawn_support.beast_row(number: 1)])
  let assert [Refusal(table: "spawn", row: refusal.RowId(1), rule:)] =
    selection.refusals
    as {
      "a creature row the client would not load refuses the spawn: "
      <> string.inspect(changes)
    }
  rule
}

// T3c-1 test 4
pub fn a_creature_row_the_client_would_not_load_refuses_its_spawns_naming_the_rule_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140485790: a row is a creature the client loads only when its modelScale
  // is above 0, its CreationTypeEnum is below 26, its archetype row exists, its
  // difficulty and resist are 0 or have a row, and its display group is not 0;
  // 0x140483d20: a soldier mission or an instance portal with no row and an
  // outfit group with no entries fail it too.
  list.each(
    [
      #(
        [#("modelScale", planted_table.Float(0.0))],
        "modelScale is not above 0",
      ),
      #(
        [#("CreationTypeEnum", planted_table.Integer(26))],
        "CreationTypeEnum is not below 26",
      ),
      #(
        [#("creature2ArcheTypeId", planted_table.Integer(99))],
        "Creature2ArcheType row does not exist",
      ),
      #(
        [#("creature2DifficultyId", planted_table.Integer(99))],
        "Creature2Difficulty row does not exist",
      ),
      #(
        [#("creature2ResistId", planted_table.Integer(99))],
        "Creature2Resist row does not exist",
      ),
      #(
        [#("creature2DisplayGroupId", planted_table.Integer(0))],
        "display group is 0",
      ),
      #(
        [#("pathMissionIdSoldier", planted_table.Integer(99))],
        "pathMissionIdSoldier row does not exist",
      ),
      #(
        // The client's InstancePortal holds a row 99 and none of 2.
        [#("instancePortalId", planted_table.Integer(2))],
        "instancePortalId row does not exist",
      ),
      #(
        [#("creature2OutfitGroupId", planted_table.Integer(99))],
        "outfit group has no entries",
      ),
    ],
    fn(case_) {
      let #(changes, words) = case_
      let rule = refused_by(changes:)
      assert string.contains(rule, "Creature2 73464")
        && string.contains(rule, words)
        as { "the rule names the creature and the client's rule: " <> rule }
    },
  )
}

pub fn a_row_with_faction_0_is_left_out_and_counted_test() -> Nil {
  use <- owned_test.run(5000)
  // `opcode.0x262`, `0x14045a950`: a unit with no faction is Neutral, and a 0x262
  // with it fails the client's read.
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 1),
        faction_id: 0,
        base_faction_id: 0,
      ),
    ])
  assert started(selection) == [] as "faction 0 does not start"
  assert left_out(selection:, reason: NoFaction) == 1
}

pub fn a_row_friendly_to_both_player_factions_is_left_out_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x140787760`, Faction2Relationship (165, 219): faction 219 is level 10 with
  // the parent 165 of both player factions, Friendly to Exile and Dominion
  // (spawn 42, creature 11254).
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 42),
        faction_id: 219,
        base_faction_id: 219,
      ),
    ])
  assert spawn.faction_levels(
      tables: character_tables.content_tables(),
      faction: 219,
    )
    == #(10, 10)
    as "Faction2Relationship 726 (165, 219): level 10 to the parent of both, Friendly"
  assert started(selection) == [] as "Friendly to both does not start"
  assert left_out(selection:, reason: FriendlyToBoth) == 1
}

pub fn a_row_hostile_to_one_faction_and_friendly_to_the_other_starts_test() -> Nil {
  use <- owned_test.run(5000)
  // Faction2Relationship.factionLevel rows 2943 and 2944: faction 1441 is level 0
  // to 167 (Exile) and 10 to 166 (Dominion), so a player of one faction can
  // attack it (`0x1403ad540`): spawn 73464 of world 3460.
  let selection = selected(rows: [spawn_support.beast_row(number: 73_464)])
  assert spawn.faction_levels(
      tables: character_tables.content_tables(),
      faction: 1441,
    )
    == #(0, 10)
    as "Faction2Relationship 2943 and 2944: level 0 to Exile 167, 10 to Dominion 166"
  assert started(selection) == [73_464]
}

pub fn whom_a_creature_fights_on_sight_is_its_factions_hostile_level_to_each_player_faction_test() -> Nil {
  use <- owned_test.run(5000)
  // Faction2Relationship 2943 and 2944: the Beast's faction 1441 is level 0,
  // Hostile, to Exile 167 and 10, Friendly, to Dominion 166; 2946 and 2947: the
  // Dagun's faction 1442 is level 0 to Dominion 166 and 10 to Exile 167
  // (`world_data.creature_disposition`: Hostile is 0 to 2).
  let selection =
    selected(rows: [
      spawn_support.beast_row(number: 1),
      spawn.Row(
        ..spawn_support.beast_row(number: 2),
        creature_id: 73_465,
        display_info_id: 26_578,
        faction_id: 1442,
        base_faction_id: 1442,
      ),
    ])
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let hostility = fn(number) {
    let assert Ok(found) = dict.get(world.by_id, SpawnId(number))
      as "the spawn starts"
    found.combat.hostile_to
  }
  assert hostility(1) == Hostile(exile: True, dominion: False)
    as "the Beast (Creature2 73464, faction 1441) fights Exiles on sight, not the Dominion"
  assert hostility(2) == Hostile(exile: False, dominion: True)
    as "the Dagun (Creature2 73465, faction 1442) fights the Dominion on sight, not Exiles"
}

pub fn a_row_whose_faction_relates_only_to_the_players_parent_faction_is_hostile_to_both_and_starts_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x140787760`, `0x140717560`: the walk takes the relationship of 165, the
  // parent of Dominion 166 and Exile 167: faction 189 (spawn 14, creature 4148).
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 14),
        faction_id: 189,
        base_faction_id: 189,
      ),
    ])
  assert spawn.faction_levels(
      tables: character_tables.content_tables(),
      faction: 189,
    )
    == #(0, 0)
    as "Faction2Relationship 691 (189, 165) is level 0, Hostile, to the parent both player factions have"
  assert started(selection) == [14]
}

pub fn a_row_whose_faction_has_no_relationship_is_neutral_and_starts_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x140787760`'s fallback: with no relationship at all the level is 5, which is
  // Neutral, and a player may attack it: faction 174 (spawn 556).
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 556),
        faction_id: 174,
        base_faction_id: 174,
      ),
    ])
  assert spawn.faction_levels(
      tables: character_tables.content_tables(),
      faction: 174,
    )
    == #(5, 5)
    as "no relationship at all: level 5, Neutral, to both"
  assert started(selection) == [556]
}

pub fn a_row_whose_creature_has_an_npc_link_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2's columns questIdGiven00, trainerClassIdMask and the like: a
  // creature that gives a quest or trains waits for its own system.
  let selection =
    selected_beast_changed(changes: [#("questIdGiven00", Integer(5))], rows: [
      spawn_support.beast_row(number: 1),
    ])
  assert started(selection) == [] as "a quest giver does not start"
  assert left_out(selection:, reason: NpcLink) == 1
}

pub fn a_row_with_health_0_is_left_out_and_a_row_with_no_stats_starts_with_the_creatures_own_values_test() -> Nil {
  use <- owned_test.run(5000)
  // `opcode.0x262.creature`: a NonPlayer unit created with health 0 is created
  // dead. `Creature2.creature2ArcheTypeId` and `0x1404585c0`: a row with no
  // stats takes the creature's minLevel and its Base Health, 52 for the Battle
  // Beast.
  let selection =
    selected(rows: [
      spawn.Row(..spawn_support.beast_row(number: 1), health: Some(0.0)),
      spawn_support.beast_row(number: 2),
      spawn.Row(
        ..spawn_support.beast_row(number: 3),
        health: Some(0.9),
        level: Some(3.0),
      ),
    ])
  assert started(selection) == [2] as "dead is left out, no stats is kept"
  assert left_out(selection:, reason: Dead) == 2
    as "a recorded health that truncates to 0 is 0 to the client"
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(no_stats) = dict.get(world.by_id, SpawnId(2))
  assert #(no_stats.level, no_stats.health) == #(1, 52)
    as "the creature's minLevel and Base Health 52.6205 truncated"
}

pub fn a_spawn_with_no_recorded_health_has_the_base_health_of_its_own_level_not_its_rows_minimum_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x1404585c0`: Base Health is the CreatureLevel row of the level times the
  // difficulty's multiplier. The Battle Beast's row has minLevel 1 (52); a spawn
  // of stat 10 = 3 has the client's CreatureLevel 3 (342.0863)
  // times Creature2Difficulty 1's 0.387 = 132.3874, truncated to 132, and one of
  // level 8 (1715.1594) 663.7667, so 663.
  let selection =
    selected(rows: [
      spawn.Row(..spawn_support.beast_row(number: 1), level: Some(3.0)),
      spawn.Row(..spawn_support.beast_row(number: 2), level: Some(8.0)),
    ])
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(third) = dict.get(world.by_id, SpawnId(1))
  assert #(third.level, third.health, third.health_source)
    == #(3, 132, unit_fields.ClientDefault)
    as "level 3: the formula at the spawn's own level"
  let assert Ok(eighth) = dict.get(world.by_id, SpawnId(2))
  assert #(eighth.level, eighth.health, eighth.health_source)
    == #(8, 663, unit_fields.ClientDefault)
    as "level 8"
}

pub fn a_recorded_health_is_the_spawns_health_and_maximum_whatever_the_clients_formula_gives_test() -> Nil {
  use <- owned_test.run(5000)
  // The world database's stat 0 is a retail record of each spawn's health
  // (`world_data.spawn_health`): Creature2 11945 at level 3 records 442 where the
  // client's formula gives 274; the 0x262 sends it as stat 0 and property 7, so
  // current and maximum are the one recorded value, whether above or below the
  // formula's 132 for the Beast at level 3.
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 1),
        health: Some(442.9),
        level: Some(3.0),
      ),
      spawn.Row(
        ..spawn_support.beast_row(number: 2),
        health: Some(50.0),
        level: Some(3.0),
      ),
    ])
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(above) = dict.get(world.by_id, SpawnId(1))
  assert #(above.level, above.health, above.health_source)
    == #(3, 442, unit_fields.Recorded)
    as "recorded 442.9 is the health, truncated as the client truncates"
  let assert Ok(below) = dict.get(world.by_id, SpawnId(2))
  assert #(below.health, below.health_source) == #(50, unit_fields.Recorded)
    as "world_data.spawn_health: a recorded health below the formula's 132 is the health too"
}

pub fn a_level_outside_its_rows_range_is_kept_and_listed_test() -> Nil {
  use <- owned_test.run(5000)
  // `world_data.spawn_checks`: the 6 spawns of world 426 with level 1 on rows with
  // range 0..0 start with the spawn's level; whether the client compares them is
  // not read.
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 1),
        health: Some(50.0),
        level: Some(9.0),
      ),
    ])
  assert started(selection) == [1] as "the spawn starts"
  assert selection.out_of_range_levels == [SpawnId(1)]
    as "and is listed for the info line"
}

pub fn the_beast_has_the_creature_traces_numbers_test() -> Nil {
  use <- owned_test.run(60_000)
  let selection = selected(rows: [spawn_support.beast_row(number: 1)])
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(beast) = dict.get(world.by_id, SpawnId(1))
  assert #(beast.level, beast.health, beast.faction_id, beast.display_info_id)
    == #(1, 52, 1441, 26_565)
    as "Creature2.73464: level 1, Base Health 52.6205 truncated, faction 1441, display 26565"
}

pub fn a_creatures_override_of_property_7_is_its_base_health_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2OverrideProperties row 2866 is the client's: creature 11467,
  // property 7 (base health), 5000.0. Creature2 11467 has no other override.
  let selection =
    selected(rows: [
      spawn.Row(
        ..spawn_support.beast_row(number: 1),
        creature_id: 11_467,
        display_info_id: 26_051,
        faction_id: 171,
        base_faction_id: 171,
      ),
    ])
  assert selection.refusals == [] as "the creature is one the client loads"
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(creature) = dict.get(world.by_id, SpawnId(1))
  assert creature.health == 5000
    as "the override's 5000.0, in place of the formula's"
}

pub fn a_difficulty_and_a_resist_of_0_need_no_row_and_the_difficulty_multiplies_by_1_test() -> Nil {
  use <- owned_test.run(60_000)
  let selection =
    selected_beast_changed(
      changes: [
        #("creature2DifficultyId", Integer(0)),
        #("creature2ResistId", Integer(0)),
      ],
      rows: [spawn_support.beast_row(number: 1)],
    )
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(beast) = dict.get(world.by_id, SpawnId(1))
  assert beast.health == 135
    as "CreatureLevel 1's 135.97028 x 1.0 x 1.0 x 1.0, truncated"
}

pub fn a_soldier_mission_an_instance_portal_and_an_outfit_group_with_rows_are_loaded_by_the_client_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's rows hold PathMission 33, InstancePortal 6 and the outfit
  // group 8170 (Creature2OutfitGroupEntry 8170), all roots of the fixture.
  let selection =
    selected_beast_changed(
      changes: [
        #("pathMissionIdSoldier", Integer(33)),
        #("instancePortalId", Integer(6)),
        #("creature2OutfitGroupId", Integer(8170)),
      ],
      rows: [spawn_support.beast_row(number: 1)],
    )
  assert selection.refusals == []
    as "the creature with a mission and a portal that have rows is one the client loads"
}

// ------------------------------------------- a creature's own attack
//
// A creature's own attack as the content load works it out
// (`genesis_prime/world_map/creature_attack`, `genesis_prime/world_map/spawn`
// `Attack`), on the client's committed rows of the Virtual Battle Beast and of Spell4
// 5649. Expected values come from these places.
// - `Spell4Effects.184741`: spell 5649's two Physical damage effects, 184741
//   (Strength 0.55, Assault Power 0.55) for a caster of difficulty at most 6 and
//   184777 (0.8 each) for difficulty at least 7, each threatMultiplier 1.0; the
//   prerequisite type 179 is the caster's difficulty (`0x14049eeb0`).
// - The creature formula (`0x140565600`, GameFormula 712: 70, 100, 1, 1): the stat
//   part S rounded, held under c = (level x 70 + 100) x the mean of the stat
//   parameters. A level-1 Beast of difficulty 1 has Strength 15.392292 x 0.68 =
//   10.4668 and AssaultRating 61.569168 x 0.68 = 41.867, Assault Power 10.4668
//   (CreatureLevel 1, Creature2Difficulty 1, GameFormula 1266): 0.55 x 10.4668 x 2
//   = 11.51, rounded to 12, under c = 93.5. At difficulty 7 (multipliers 0.7)
//   both are 10.7746: 0.8 x 10.7746 x 2 = 17.24, rounded to 17, under c = 136.
// - Its run speed is runLand 10.0 times MoveSpeedMultiplier 1.0 (`0x1405b45e0`,
//   `Creature2.73464`), its reach the spell's targetMaxRange 5.0 (`Spell4.5649`)
//   plus its hit radius 3.0, a server choice.
// - Its critical hit chance is BaseCritChance (CreatureLevel 101's 0.05 x
//   difficulty 1's 0.32 = 0.016), its severity CriticalHitSeverityMultiplier (1.5
//   x tier 1's 0.85 = 1.275), its strikethrough 0 (CreatureLevel 101's 0.0), each
//   with no rating (274's damage trace, `0x140453b60`).

/// The Beast of spawn 1 as the content load over these tables selects it.
fn attack_beast_over(tables tables: store.Tables) -> spawn.Spawn {
  let selection = beast_selection_over(tables:)
  let assert [] = selection.refusals as "the Beast's row is taken"
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(beast) = dict.get(world.by_id, SpawnId(1)) as "spawn 1 starts"
  beast
}

/// The selection of the Beast's row, spawn 1, over the content load of these tables.
fn beast_selection_over(tables tables: store.Tables) -> spawn.Selection {
  selected_over(tables:, rows: [spawn_support.beast_row(number: 1)])
}

pub fn an_attack_effect_whose_multiplier_is_not_a_finite_float_refuses_the_spawn_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: the client's effect 184741 has dataBits00 1.0; 0x7F800000 is the
  // 32-bit float's infinity, which the VM cannot hold.
  let selection = {
    use tables <- fixture_tables.changed(
      table: "Spell4Effects",
      id: 184_741,
      with: [#("dataBits00", Integer(0x7F800000))],
    )
    beast_selection_over(tables:)
  }
  assert selection.refusals
    == [
      Refusal(
        table: "spawn",
        row: refusal.RowId(1),
        rule: "Creature2 73464's attack effect 184741 has a multiplier, dataBits00 2139095040, that is not a finite 32-bit float",
      ),
    ]
    as "the load names the effect, where a multiplier read as 0 would strike for the stat part alone"
}

// T3c-1 test 3
pub fn a_creature_of_difficulty_1_strikes_with_effect_184741_for_12_test() -> Nil {
  use <- owned_test.run(60_000)
  let attack =
    { attack_beast_over(tables: fixture_tables.shared()) }.combat.attack
  assert attack.spell4_id == Spell4Id(5649)
    as "the kind's spell (migration 0010)"
  assert attack.offence.blows
    == [
      Blow(
        spell4_effects_id: 184_741,
        damage_type: 1,
        damage: 12,
        delay_ms: 0,
        threat_multiplier: 1.0,
      ),
    ]
    as "difficulty 1 passes prerequisite 30526 (at most 6) and fails 30527 (at least 7): effect 184741 alone, Physical, 12 by the creature formula"
  assert attack.run_speed == 10.0 && attack.reach == 8.0
    as "runLand 10.0 x 1.0; targetMaxRange 5.0 plus hit radius 3.0"
  assert float.loosely_equals(
      attack.offence.crit_chance,
      with: 0.016,
      tolerating: 0.000001,
    )
    && float.loosely_equals(
      attack.offence.crit_severity,
      with: 1.275,
      tolerating: 0.000001,
    )
    && attack.offence.strikethrough == 0.0
    as "BaseCritChance 0.05 x 0.32, severity 1.5 x 0.85, no strikethrough"
}

pub fn a_creature_of_difficulty_7_strikes_with_effect_184777_for_17_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2Difficulty 7 is the client's row (whole in the fixture): 0.7 for
  // Strength and AssaultRating, 2.5 for Base Health.
  let beast = {
    use tables <- fixture_tables.changed(table: "Creature2", id: 73_464, with: [
      #("creature2DifficultyId", Integer(7)),
    ])
    attack_beast_over(tables:)
  }
  let attack = beast.combat.attack
  assert beast.health == 339
    as "CreatureLevel 1's base health 135.97028 x difficulty 7's 2.5 (x archetype 1's 1.0 x tier 1's 1.0), truncated"
  assert attack.offence.blows
    == [
      Blow(
        spell4_effects_id: 184_777,
        damage_type: 1,
        damage: 17,
        delay_ms: 0,
        threat_multiplier: 1.0,
      ),
    ]
    as "difficulty 7 (Creature2Difficulty 7, multipliers 0.7) fails 30526 and passes 30527: effect 184777 alone, 17"
}
