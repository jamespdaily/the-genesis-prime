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
//// Every test loads planted tables, so it runs in CI.

import character_tables
import genesis_prime/content/refusal.{Refusal}
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/path_mission
import genesis_prime/world_map/spawn.{
  type Row, type Selection, Dead, FriendlyToBoth, NoFaction, NpcLink,
}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import planted_table
import spawn_support

/// The selection of the rows against the planted tables.
fn selected(rows rows: List(Row)) -> Selection {
  spawn.select(rows:, tables: character_tables.content_tables())
}

/// The selection of the rows against the tables of these planted files.
fn selected_with(
  files files: List(#(String, BitArray)),
  rows rows: List(Row),
) -> Selection {
  use folder <- planted_table.in_folder(list.append(
    files,
    character_tables.content_files(),
  ))
  let assert Ok(tables) = server_table.load_for_content(from: folder)
    as "the planted files load as the content load's tables"
  spawn.select(rows:, tables:)
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
  // 0x140649e20: type 0 is NonPlayer, 4 Door, 10 Simple (`world_data.entity_type`).
  let selection =
    selected(rows: [
      spawn_support.beast_row(number: 1),
      spawn.Row(..spawn_support.beast_row(number: 2), entity_type: 4),
      spawn.Row(..spawn_support.beast_row(number: 3), entity_type: 10),
      spawn.Row(..spawn_support.beast_row(number: 4), entity_type: 10),
    ])
  assert started(selection) == [1] as "the NonPlayer row starts and no other"
  let assert [coverage] = selection.coverage as "one world"
  assert coverage.started == 1
  assert list.sort(coverage.other_types, fn(first, second) {
      int.compare(first.0, second.0)
    })
    == [#(4, 1), #(10, 2)]
    as "each other type counted: one Door and two Simple"
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
      Refusal(table: "spawn", id: 7, rule: "Creature2 200002 has no row"),
      Refusal(
        table: "spawn",
        id: 8,
        rule: "display 12345 is not in the display group of Creature2 73464",
      ),
    ]
    as "each refusal names the table, the row and the rule"
}

/// The planted files with the Virtual Battle Beast's row changed, and the
/// refusal the selection gives the row of the beast.
fn refused_by(changes changes: List(#(String, planted_table.Cell))) -> String {
  let selection =
    selected_with(
      files: character_tables.files_with_beast_changed(changes:),
      rows: [spawn_support.beast_row(number: 1)],
    )
  let assert [Refusal(table: "spawn", id: 1, rule:)] = selection.refusals
    as "a creature row the client would not load refuses the spawn"
  rule
}

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
        [#("instancePortalId", planted_table.Integer(99))],
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
  assert started(selection) == [] as "Friendly to both does not start"
  assert left_out(selection:, reason: FriendlyToBoth) == 1
}

pub fn a_row_hostile_to_one_faction_and_friendly_to_the_other_starts_test() -> Nil {
  use <- owned_test.run(5000)
  // Faction2Relationship.factionLevel rows 2943 and 2944: faction 1441 is level 0
  // to 167 (Exile) and 10 to 166 (Dominion), so a player of one faction can
  // attack it (`0x1403ad540`): spawn 73464 of world 3460.
  let selection = selected(rows: [spawn_support.beast_row(number: 73_464)])
  assert started(selection) == [73_464]
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
  assert started(selection) == [556]
}

pub fn a_row_whose_creature_has_an_npc_link_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2's columns questIdGiven00, trainerClassIdMask and the like: a
  // creature that gives a quest or trains waits for its own system.
  let selection =
    selected_with(
      files: character_tables.files_with_beast_changed(changes: [
        #("questIdGiven00", planted_table.Integer(5)),
      ]),
      rows: [spawn_support.beast_row(number: 1)],
    )
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
        health: Some(1234.9),
        level: Some(8.0),
      ),
    ])
  assert started(selection) == [2, 3] as "dead is left out, no stats is kept"
  assert left_out(selection:, reason: Dead) == 1
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(no_stats) = dict.get(world.by_id, SpawnId(2))
  assert #(no_stats.level, no_stats.health) == #(1, 52)
    as "the creature's minLevel and Base Health 52.6205 truncated"
  let assert Ok(with_stats) = dict.get(world.by_id, SpawnId(3))
  assert #(with_stats.level, with_stats.health) == #(8, 1234)
    as "stat 10 and stat 0 truncated"
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

pub fn the_planted_beast_has_the_creature_traces_numbers_test() -> Nil {
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
  let files =
    character_tables.files_replacing(
      schema: creature2_override_properties.schema,
      rows: [
        character_tables.override_row(
          id: 1,
          creature: 73_464,
          property: 7,
          value: 77.9,
        ),
        character_tables.override_row(
          id: 2,
          creature: 73_464,
          property: 40,
          value: 1.0,
        ),
      ],
    )
  let selection =
    selected_with(files:, rows: [spawn_support.beast_row(number: 1)])
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(beast) = dict.get(world.by_id, SpawnId(1))
  assert beast.health == 77
    as "the override's 77.9 truncated, in place of the formula's 52"
}

pub fn a_difficulty_and_a_resist_of_0_need_no_row_and_the_difficulty_multiplies_by_1_test() -> Nil {
  use <- owned_test.run(60_000)
  let selection =
    selected_with(
      files: character_tables.files_with_beast_changed(changes: [
        #("creature2DifficultyId", planted_table.Integer(0)),
        #("creature2ResistId", planted_table.Integer(0)),
      ]),
      rows: [spawn_support.beast_row(number: 1)],
    )
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(beast) = dict.get(world.by_id, SpawnId(1))
  assert beast.health == 135
    as "CreatureLevel 1's 135.97028 x 1.0 x 1.0 x 1.0, truncated"
}

pub fn a_soldier_mission_an_instance_portal_and_an_outfit_group_with_rows_are_loaded_by_the_client_test() -> Nil {
  use <- owned_test.run(60_000)
  let id = fn(schema, number) {
    planted_table.row(schema, [#("ID", planted_table.Integer(number))])
  }
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("pathMissionIdSoldier", planted_table.Integer(5)),
      #("instancePortalId", planted_table.Integer(6)),
      #("creature2OutfitGroupId", planted_table.Integer(7)),
    ])
    |> replacing(schema: path_mission.schema, rows: [id(path_mission.schema, 5)])
    |> replacing(schema: instance_portal.schema, rows: [
      id(instance_portal.schema, 6),
    ])
    |> replacing(schema: creature2_outfit_group_entry.schema, rows: [
      planted_table.row(creature2_outfit_group_entry.schema, [
        #("ID", planted_table.Integer(1)),
        #("creature2OutfitGroupId", planted_table.Integer(7)),
      ]),
    ])
  let selection =
    selected_with(files:, rows: [spawn_support.beast_row(number: 1)])
  assert selection.refusals == []
    as "the creature with a mission and a portal that have rows is one the client loads"
}

/// The files with the file of `schema` holding `rows` in place of its own.
fn replacing(
  files files: List(#(String, BitArray)),
  schema schema: tbl_file.Schema,
  rows rows: List(List(planted_table.Cell)),
) -> List(#(String, BitArray)) {
  list.map(files, fn(file) {
    case file.0 == schema.file {
      True -> planted_table.file(schema, rows)
      False -> file
    }
  })
}
