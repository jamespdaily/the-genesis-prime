//// The spawn of a development summon (`genesis_prime/world_map/spawn`
//// `summoned`): a creature of a Creature2 row standing where a player stands,
//// checked as a stored spawn is. Expected values come from these places.
//// - The Virtual Battle Beast's numbers are the client's, from the creature
////   trace (`Creature2.73464`): level 1, faction 1441 for both the faction and
////   the base faction (`opcode.0x262.creature`), display 26565, outfit 0,
////   Base Health 52. `character_tables_test` holds the planted tables to the
////   client's rows.
//// - Commander Durek (Creature2 75048), read from the client's table with
////   `gleam run -m genesis_prime/table_rows -- Creature2 75048`: factionId 171,
////   minLevel 50, display group 25412 whose one entry (22838) is display 22825,
////   outfit group 9757 whose one entry (9774) is outfit 9065.
//// - A summon takes the display and the outfit from the first entry of the
////   creature's groups, a server choice: the client's weighted pick runs only
////   for spawns the client makes itself (`0x1404846c0`). First is the entry of
////   the lowest id, the order of the table.
//// - A summon is refused for what the client's checks of a spawn refuse
////   (`0x140485790`) and for what the load leaves out of a stored spawn: no
////   faction, friendly to both player factions, an NPC link, health 0
////   (`opcode.0x262.creature`); a server choice, so a summon starts only what a
////   spawn starts.

import character_tables
import client_tables
import genesis_prime/game/rating
import genesis_prime/game/start_place.{Facing}
import genesis_prime/table/creature2_display_group_entry
import genesis_prime/table/creature2_display_info
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_outfit_info
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source.{Summoned}
import genesis_prime/world_map/unit_fields
import gleam/dict
import map_spawn_support
import owned_test
import planted_table.{Float, Integer}
import rating_support
import spawn_support
import unitest

const beast = 73_464

const durek = 75_048

/// The place a player stands at when it summons, with a facing of its own.
fn summoned_place() -> start_place.Place {
  start_place.turned(
    map_spawn_support.at(250.0),
    Facing(yaw: 1.5, pitch: 0.25, roll: -0.5),
  )
}

/// The summon of Creature2 `creature_id` at `summoned_place` as run-only spawn
/// -1, checked with the planted tables.
fn summoned_planted(
  creature_id creature_id: Int,
) -> Result(Spawn, spawn.SummonRefusal) {
  spawn.summoned(
    checks: spawn_support.summon_checks(),
    summoned: Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(creature_id),
      place: summoned_place(),
    ),
  )
}

/// The summon of Creature2 `creature_id` over these planted files.
fn summoned_over(
  files files: List(#(String, BitArray)),
  creature_id creature_id: Int,
) -> Result(Spawn, spawn.SummonRefusal) {
  use checks <- spawn_support.with_summon_checks_of(files)
  spawn.summoned(
    checks:,
    summoned: Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(creature_id),
      place: summoned_place(),
    ),
  )
}

pub fn a_summon_of_the_battle_beast_has_the_client_rows_values_at_the_summoned_place_and_facing_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(spawn) = summoned_planted(creature_id: beast)
    as "the Beast passes the checks of a spawn"
  assert spawn.id == SpawnId(-1) && spawn.creature_id == Creature2Id(beast)
  assert spawn.place == summoned_place()
    as "the place and the facing are the summoned ones, in the place's own world and zone"
  assert spawn.level == 1 && spawn.health == 52
    as "the creature's minLevel and its Base Health at it, 52.6205 truncated"
  assert spawn.health_source == unit_fields.ClientDefault
    as "the row has no recorded health, so the 0x262 sends none as property 7"
  assert spawn.faction_id == 1441 && spawn.base_faction_id == 1441
    as "both factions are the Creature2 row's factionId (opcode.0x262.creature)"
  assert spawn.display_info_id == 26_565 && spawn.outfit_info_id == 0
}

pub fn a_summon_has_what_a_stored_spawn_of_the_same_creature_and_place_has_test() -> Nil {
  use <- owned_test.run(5000)
  // The stored row has the beast's values and the summoned place and facing.
  let row =
    spawn.Row(
      ..spawn_support.beast_row(number: 1),
      area_id: spawn_support.warfare_woods,
      x: 250.0,
      rotation_x: 1.5,
      rotation_y: 0.25,
      rotation_z: -0.5,
    )
  let selection =
    spawn.select(
      rows: [row],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
    )
  let assert Ok(world) = dict.get(selection.worlds, 3460)
    as "the row starts in world 3460"
  let assert Ok(stored) = dict.get(world.by_id, SpawnId(1))
    as "the stored row starts"
  let assert Ok(summoned) = summoned_planted(creature_id: beast)
  assert summoned == Spawn(..stored, id: SpawnId(-1))
    as "the load's spawn of that row, but for its id: the same combat, level and health"
}

pub fn a_summon_of_the_dagun_fights_on_sight_as_its_stored_spawn_does_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(summoned) = summoned_planted(creature_id: 73_465)
  assert summoned.combat.hostile_to.dominion
    && !summoned.combat.hostile_to.exile
    as "faction 1442 is level 0 to Dominion 166 and 10 to Exile 167 (Creature2.73465)"
  assert summoned.faction_id == 1442 && summoned.display_info_id == 26_578
}

pub fn the_display_and_the_outfit_of_a_summon_are_the_first_entries_of_the_creatures_groups_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each group has two entries; the first by id is not the one of the lowest
  // display or outfit id, and not the heavier one.
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("creature2OutfitGroupId", Integer(7)),
    ])
    |> planted_table.replacing(schema: creature2_display_info.schema, rows: [
      display_row(id: 26_565),
      display_row(id: 26_580),
    ])
    |> planted_table.replacing(
      schema: creature2_display_group_entry.schema,
      rows: [
        character_tables.group_entry_row(
          id: 27_192,
          group: 28_793,
          display: 26_580,
        ),
        planted_table.row(creature2_display_group_entry.schema, [
          #("id", Integer(27_250)),
          #("creature2DisplayGroupId", Integer(28_793)),
          #("creature2DisplayInfoId", Integer(26_565)),
          #("weight", Integer(9)),
        ]),
      ],
    )
    |> planted_table.replacing(
      schema: creature2_outfit_group_entry.schema,
      rows: [outfit_entry(id: 1, outfit: 71), outfit_entry(id: 2, outfit: 70)],
    )
    |> planted_table.replacing(schema: creature2_outfit_info.schema, rows: [
      planted_table.row(creature2_outfit_info.schema, [#("ID", Integer(70))]),
      planted_table.row(creature2_outfit_info.schema, [#("ID", Integer(71))]),
    ])
  let assert Ok(spawn) = summoned_over(files:, creature_id: beast)
    as "the Beast with two displays and two outfits passes the checks"
  assert spawn.display_info_id == 26_580
    as "the first entry of the display group, by id"
  assert spawn.outfit_info_id == 71
    as "the first entry of the outfit group, by id"
}

pub fn a_summon_whose_first_outfit_has_no_creature2_outfit_info_row_is_refused_not_crashed_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140485790: the client's checks of a spawn need a Creature2OutfitInfo row
  // for the row's outfit. The outfit group's entry names outfit 71, which has
  // no row.
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("creature2OutfitGroupId", Integer(7)),
    ])
    |> planted_table.replacing(
      schema: creature2_outfit_group_entry.schema,
      rows: [outfit_entry(id: 1, outfit: 71)],
    )
  assert summoned_over(files:, creature_id: beast)
    == Error(spawn.FailsTheChecks(spawn.NoOutfitRow(outfit_info_id: 71)))
}

fn display_row(id id: Int) -> List(planted_table.Cell) {
  planted_table.row(creature2_display_info.schema, [
    #("ID", Integer(id)),
    #("hitRadius", Float(3.0)),
    #("runLand", Float(10.0)),
  ])
}

fn outfit_entry(id id: Int, outfit outfit: Int) -> List(planted_table.Cell) {
  planted_table.row(creature2_outfit_group_entry.schema, [
    #("ID", Integer(id)),
    #("creature2OutfitGroupId", Integer(7)),
    #("creature2OutfitInfoId", Integer(outfit)),
    #("weight", Integer(1)),
  ])
}

pub fn a_creature2_id_with_no_row_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert summoned_planted(creature_id: 200_002)
    == Error(spawn.FailsTheChecks(spawn.NoCreatureRow(Creature2Id(200_002))))
  assert spawn.describe_refusal(
      spawn.FailsTheChecks(spawn.NoCreatureRow(Creature2Id(200_002))),
    )
    == "Creature2 200002 has no row"
}

pub fn a_creature_the_client_would_not_load_is_refused_naming_the_rule_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140485790: the client loads no creature whose modelScale is not above 0.
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("modelScale", Float(0.0)),
    ])
  assert summoned_over(files:, creature_id: beast)
    == Error(
      spawn.FailsTheChecks(spawn.NotLoadedByTheClient(
        creature_id: Creature2Id(beast),
        rule: spawn.ModelScaleNotAbove0,
      )),
    )
}

pub fn a_creature_with_no_faction_or_an_npc_link_would_not_start_as_a_spawn_and_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // opcode.0x262.creature: a unit with no faction is Neutral and a stored row of
  // it is left out; a creature that gives a quest waits for its own system.
  let no_faction =
    character_tables.files_with_beast_changed(changes: [
      #("factionId", Integer(0)),
    ])
  assert summoned_over(files: no_faction, creature_id: beast)
    == Error(spawn.WouldNotStart(
      creature_id: Creature2Id(beast),
      reason: spawn.NoFaction,
    ))
  let quest_giver =
    character_tables.files_with_beast_changed(changes: [
      #("questIdGiven00", Integer(5)),
    ])
  assert summoned_over(files: quest_giver, creature_id: beast)
    == Error(spawn.WouldNotStart(
      creature_id: Creature2Id(beast),
      reason: spawn.NpcLink,
    ))
  assert spawn.describe_refusal(spawn.WouldNotStart(
      creature_id: Creature2Id(beast),
      reason: spawn.NoFaction,
    ))
    == "Creature2 73464 would not start as a spawn: no faction"
}

pub fn commander_durek_summons_with_the_client_rows_faction_display_and_outfit_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let assert Ok(spawn) =
    spawn.summoned(
      checks: spawn.summon_checks(
        tables: client_tables.every_table(),
        formulas: rating.formulas(tables: client_tables.every_table()),
        kinds: spawn_support.kinds(),
      ),
      summoned: Summoned(
        id: SpawnId(-1),
        creature_id: Creature2Id(durek),
        place: summoned_place(),
      ),
    )
    as "Durek passes the checks of a spawn and would start as one"
  assert spawn.faction_id == 171 && spawn.base_faction_id == 171
    as "Creature2.75048 factionId"
  assert spawn.level == 50 as "Creature2.75048 minLevel"
  assert spawn.display_info_id == 22_825
    as "the one entry (22838) of display group 25412"
  assert spawn.outfit_info_id == 9065
    as "the one entry (9774) of outfit group 9757"
  assert spawn.place == summoned_place()
}
