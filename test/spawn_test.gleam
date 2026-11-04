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
import genesis_prime/game/hit.{Blow}
import genesis_prime/table/creature2_difficulty
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/path_mission
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/spawn.{
  type Row, type Selection, Dead, FriendlyToBoth, NoFaction, NpcLink,
}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import novice_tables
import owned_key
import owned_test
import planted_table
import rating_support
import spawn_support

/// The selection of the rows against the planted tables.
fn selected(rows rows: List(Row)) -> Selection {
  spawn.select(
    rows:,
    tables: character_tables.content_tables(),
    formulas: rating_support.formulas(),
    kinds: spawn_support.kinds(),
  )
}

/// The selection of the rows against the tables of these planted files.
fn selected_with(
  files files: List(#(String, BitArray)),
  rows rows: List(Row),
) -> Selection {
  use folder <- planted_table.in_folder(list.append(
    novice_tables.with_creature_attack(files:, padding: True),
    character_tables.content_files(),
  ))
  let assert Ok(server) =
    server_table.load_under(under: owned_key.new(), from: folder)
    as "the planted files load as the server's tables"
  let assert Ok(more) =
    server_table.load_content_tables(over: server, from: folder)
    as "the planted files load as the content-only tables"
  let selection =
    spawn.select(
      rows:,
      tables: more,
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
    )
  table_store.unload(more)
  table_store.unload(server)
  selection
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

/// The planted files with the Virtual Battle Beast's row changed, and the
/// refusal the selection gives the row of the beast.
fn refused_by(changes changes: List(#(String, planted_table.Cell))) -> String {
  let selection =
    selected_with(
      files: character_tables.files_with_beast_changed(changes:),
      rows: [spawn_support.beast_row(number: 1)],
    )
  let assert [Refusal(table: "spawn", row: refusal.RowId(1), rule:)] =
    selection.refusals
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
  // of stat 10 = 3 has the planted CreatureLevel 3 (the client's row, 342.0863)
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
    == #(3, 132, spawn.ClientDefault)
    as "level 3: the formula at the spawn's own level"
  let assert Ok(eighth) = dict.get(world.by_id, SpawnId(2))
  assert #(eighth.level, eighth.health, eighth.health_source)
    == #(8, 663, spawn.ClientDefault)
    as "level 8"
}

pub fn a_recorded_health_is_the_spawns_health_and_maximum_whatever_the_clients_formula_gives_test() -> Nil {
  use <- owned_test.run(5000)
  // The world database's stat 0 is a retail record of each spawn's health
  // (`world_data.spawn_health`): Creature2 11945 at level 3 records 442 where the
  // client's formula gives 274; the 0x262 sends it as stat 0 and property 7, so
  // current and maximum are the one recorded value, whether above or below the
  // formula's 132 for the planted beast at level 3.
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
    == #(3, 442, spawn.Recorded)
    as "recorded 442.9 is the health, truncated as the client truncates"
  let assert Ok(below) = dict.get(world.by_id, SpawnId(2))
  assert #(below.health, below.health_source) == #(50, spawn.Recorded)
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

// ------------------------------------------- a creature's own attack
//
// A creature's own attack as the content load works it out
// (`genesis_prime/world_map/creature_attack`, `genesis_prime/world_map/spawn`
// `Attack`), on the planted tables, which hold the client's rows of the Virtual
// Battle Beast and of Spell4 5649. Expected values come from these places.
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

/// The Beast of spawn 1 as the planted files select it.
fn attack_beast_of(files files: List(#(String, BitArray))) -> spawn.Spawn {
  let selection =
    beast_selection(files: novice_tables.with_creature_attack(
      files:,
      padding: True,
    ))
  let assert [] = selection.refusals as "the Beast's row is taken"
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(beast) = dict.get(world.by_id, SpawnId(1)) as "spawn 1 starts"
  beast
}

/// The selection of the Beast's row, spawn 1, over these files and the content files.
fn beast_selection(files files: List(#(String, BitArray))) -> spawn.Selection {
  use folder <- planted_table.in_folder(list.append(
    files,
    character_tables.content_files(),
  ))
  let assert Ok(server) =
    server_table.load_under(under: owned_key.new(), from: folder)
    as "the planted files load as the server's tables"
  let assert Ok(more) =
    server_table.load_content_tables(over: server, from: folder)
    as "the planted files load as the content-only tables"
  let selection =
    spawn.select(
      rows: [spawn_support.beast_row(number: 1)],
      tables: more,
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
    )
  table_store.unload(more)
  table_store.unload(server)
  selection
}

pub fn an_attack_effect_whose_multiplier_is_not_a_finite_float_refuses_the_spawn_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: the client's effect 184741 has dataBits00 1.0; 0x7F800000 is the
  // 32-bit float's infinity, which the VM cannot hold.
  let selection =
    beast_selection(files: novice_tables.with_creature_attack_multiplier(
      files: character_tables.files(),
      padding: True,
      multiplier_bits: 0x7F800000,
    ))
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

fn nearly(first: Float, second: Float) -> Bool {
  float.absolute_value(first -. second) <. 0.000001
}

pub fn a_creature_of_difficulty_1_strikes_with_effect_184741_for_12_test() -> Nil {
  use <- owned_test.run(60_000)
  let attack =
    { attack_beast_of(files: character_tables.files()) }.combat.attack
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
  assert nearly(attack.offence.crit_chance, 0.016)
    && nearly(attack.offence.crit_severity, 1.275)
    && attack.offence.strikethrough == 0.0
    as "BaseCritChance 0.05 x 0.32, severity 1.5 x 0.85, no strikethrough"
}

pub fn a_creature_of_difficulty_7_strikes_with_effect_184777_for_17_test() -> Nil {
  use <- owned_test.run(60_000)
  let difficulty_7 =
    planted_table.row(creature2_difficulty.schema, [
      #("ID", planted_table.Integer(7)),
      #("unitPropertyMultiplier000", planted_table.Float(0.699999988079071)),
      #("unitPropertyMultiplier007", planted_table.Float(1.0)),
      #("unitPropertyMultiplier035", planted_table.Float(0.699999988079071)),
      #("unitPropertyMultiplier100", planted_table.Float(1.0)),
      #("unitPropertyMultiplier101", planted_table.Float(0.3199999928474426)),
      #("unitPropertyMultiplier102", planted_table.Float(2.0)),
      #("unitPropertyMultiplier104", planted_table.Float(2.0)),
      #("unitPropertyMultiplier127", planted_table.Float(1.0)),
    ])
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("creature2DifficultyId", planted_table.Integer(7)),
    ])
    |> replacing_file(
      file: creature2_difficulty.schema.file,
      with: planted_table.file(creature2_difficulty.schema, [difficulty_7]),
    )
  let attack = { attack_beast_of(files:) }.combat.attack
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

fn replacing_file(
  files files: List(#(String, BitArray)),
  file name: String,
  with replacement: #(String, BitArray),
) -> List(#(String, BitArray)) {
  list.map(files, fn(file) {
    case file.0 == name {
      True -> replacement
      False -> file
    }
  })
}
