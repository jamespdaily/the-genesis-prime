//// The spawn of a development summon (`genesis_prime/world_map/spawn`
//// `summoned`): a creature of a Creature2 row standing where a player stands,
//// checked as a stored spawn is. Expected values come from these places.
//// - The Virtual Battle Beast's numbers are the client's, from the creature
////   trace (`Creature2.73464`): level 1, faction 1441 for both the faction and
////   the base faction (`opcode.0x262.creature`), display 26565, outfit 0,
////   Base Health 52, all read from the client's committed rows.
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
////   faction, friendly to both player factions, only a service link, health 0
////   (`opcode.0x262.creature`); a server choice, so a summon starts only what a
////   spawn starts.

import character_tables
import client_tables
import fixture_tables
import genesis_prime/game/rating
import genesis_prime/game/start_place.{Facing}
import genesis_prime/game/vendor
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/creature_life
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source.{Summoned}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
/// -1, checked over the client's committed rows.
fn summoned_from_client(
  creature_id creature_id: Int,
) -> Result(Spawn, spawn.SummonRefusal) {
  summoned_at_level(creature_id:, level: None)
}

/// The summon of Creature2 `creature_id` at `level` as `summoned_from_client` is.
fn summoned_at_level(
  creature_id creature_id: Int,
  level level: Option(Int),
) -> Result(Spawn, spawn.SummonRefusal) {
  spawn.summoned(
    checks: spawn_support.summon_checks(),
    summoned: Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(creature_id),
      level:,
      place: summoned_place(),
    ),
  )
}

/// The summon of Creature2 `creature_id` over these tables, a test's edit of
/// the client's rows.
fn summoned_over(
  tables tables: store.Tables,
  creature_id creature_id: Int,
) -> Result(Spawn, spawn.SummonRefusal) {
  spawn.summoned(
    checks: spawn_support.summon_checks_over(tables:),
    summoned: Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(creature_id),
      level: None,
      place: summoned_place(),
    ),
  )
}

/// The summon of the Beast when its Creature2 row holds these cells in place of
/// the client's.
fn summoned_beast_changed(
  changes changes: List(#(String, planted_table.Cell)),
) -> Result(Spawn, spawn.SummonRefusal) {
  use tables <- fixture_tables.changed(
    table: "Creature2",
    id: beast,
    with: changes,
  )
  summoned_over(tables:, creature_id: beast)
}

pub fn a_summon_of_the_battle_beast_has_the_client_rows_values_at_the_summoned_place_and_facing_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(spawn) = summoned_from_client(creature_id: beast)
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
      vendors: vendor.none(),
      factions: creature_faction.none(),
    )
  let assert Ok(world) = dict.get(selection.worlds, 3460)
    as "the row starts in world 3460"
  let assert Ok(stored) = dict.get(world.by_id, SpawnId(1))
    as "the stored row starts"
  let assert Ok(summoned) = summoned_from_client(creature_id: beast)
  assert summoned == Spawn(..stored, id: SpawnId(-1))
    as "the load's spawn of that row, but for its id: the same combat, level and health"
}

pub fn a_summon_of_the_dagun_fights_on_sight_as_its_stored_spawn_does_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(summoned) = summoned_from_client(creature_id: 73_465)
  assert summoned.combat.hostile_to.dominion
    && !summoned.combat.hostile_to.exile
    as "faction 1442 is level 0 to Dominion 166 and 10 to Exile 167 (Creature2.73465)"
  assert summoned.faction_id == 1442 && summoned.display_info_id == 26_578
}

pub fn the_display_and_the_outfit_of_a_summon_are_the_first_entries_of_the_creatures_groups_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's display group 29198 holds entries 27751 (display 27010) and
  // 27762 (display 27006), and its outfit group 10115 entries 10355 (outfit
  // 9351) and 10359 (outfit 9350): the first by id is not the one of the lowest
  // display or outfit id. Synthetic: the client gives every entry weight 1, so
  // the second entry of each group is given weight 9 to be the heavier.
  let assert Ok(rows) = {
    use rows <- result.try(
      fixture_tables.change(
        rows: fixture_tables.rows(),
        table: "Creature2",
        id: beast,
        with: [
          #("creature2DisplayGroupId", Integer(29_198)),
          #("creature2OutfitGroupId", Integer(10_115)),
        ],
      ),
    )
    use rows <- result.try(
      fixture_tables.change(
        rows:,
        table: "Creature2DisplayGroupEntry",
        id: 27_762,
        with: [#("weight", Integer(9))],
      ),
    )
    fixture_tables.change(
      rows:,
      table: "Creature2OutfitGroupEntry",
      id: 10_359,
      with: [#("weight", Integer(9))],
    )
  }
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let assert Ok(spawn) = summoned_over(tables:, creature_id: beast)
    as "the Beast with two displays and two outfits passes the checks"
  assert spawn.display_info_id == 27_010
    as "the first entry of the display group, by id: not display 27006, the lower, and not entry 27762, the heavier"
  assert spawn.outfit_info_id == 9351
    as "the first entry of the outfit group, by id: not outfit 9350, the lower, and not entry 10359, the heavier"
}

pub fn a_summon_whose_first_outfit_has_no_creature2_outfit_info_row_is_refused_not_crashed_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140485790: the client's checks of a spawn need a Creature2OutfitInfo row
  // for the row's outfit. The client's outfit group 8181 has one entry (8181),
  // which names outfit 7486, and the client's Creature2OutfitInfo holds no row
  // 7486 (it skips from 7485 to 7487).
  use tables <- fixture_tables.changed(table: "Creature2", id: beast, with: [
    #("creature2OutfitGroupId", Integer(8181)),
  ])
  assert summoned_over(tables:, creature_id: beast)
    == Error(spawn.FailsTheChecks(spawn.NoOutfitRow(outfit_info_id: 7486)))
}

pub fn a_creature2_id_with_no_row_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert summoned_from_client(creature_id: 200_002)
    == Error(spawn.FailsTheChecks(spawn.NoCreatureRow(Creature2Id(200_002))))
  assert spawn.describe_refusal(
      spawn.FailsTheChecks(spawn.NoCreatureRow(Creature2Id(200_002))),
    )
    == "Creature2 200002 has no row"
}

pub fn a_creature_the_client_would_not_load_is_refused_naming_the_rule_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140485790: the client loads no creature whose modelScale is not above 0.
  assert summoned_beast_changed(changes: [#("modelScale", Float(0.0))])
    == Error(
      spawn.FailsTheChecks(spawn.NotLoadedByTheClient(
        creature_id: Creature2Id(beast),
        rule: spawn.ModelScaleNotAbove0,
      )),
    )
}

pub fn a_creature_with_no_faction_or_a_service_link_would_not_start_as_a_spawn_and_is_refused_test() -> Nil {
  use <- owned_test.run(120_000)
  // opcode.0x262.creature: a unit with no faction is Neutral and a stored row of
  // it is left out; a creature with only a taxi link waits for its own system,
  // and one that gives a quest stands as a stored spawn of it does.
  assert summoned_beast_changed(changes: [#("factionId", Integer(0))])
    == Error(spawn.WouldNotStart(
      creature_id: Creature2Id(beast),
      reason: spawn.NoFaction,
    ))
  assert summoned_beast_changed(changes: [#("taxiNodeId", Integer(1))])
    == Error(spawn.WouldNotStart(
      creature_id: Creature2Id(beast),
      reason: spawn.ServiceLink,
    ))
  let assert Ok(giver) =
    summoned_beast_changed(changes: [#("questIdGiven00", Integer(5))])
    as "a quest creature starts as a spawn, so it summons"
  assert giver.creature_id == Creature2Id(beast)
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
        vendors: vendor.none(),
        factions: creature_faction.none(),
      ),
      summoned: Summoned(
        id: SpawnId(-1),
        creature_id: Creature2Id(durek),
        level: None,
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

/// The summon of Creature2 `creature_id` at `level` with the client's real rows.
fn real_summon_at(
  creature_id creature_id: Int,
  level level: Int,
) -> Result(Spawn, spawn.SummonRefusal) {
  spawn.summoned(
    checks: spawn.summon_checks(
      tables: client_tables.every_table(),
      formulas: rating.formulas(tables: client_tables.every_table()),
      kinds: spawn_support.kinds(),
      vendors: vendor.none(),
      factions: creature_faction.none(),
    ),
    summoned: Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(creature_id),
      level: Some(level),
      place: summoned_place(),
    ),
  )
}

pub fn commander_durek_summoned_at_level_3_has_that_levels_health_and_keeps_his_interrupt_armor_of_18_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let assert Ok(spawn) = real_summon_at(creature_id: durek, level: 3)
    as "Durek at level 3 passes the checks of a spawn and would start as one"
  assert spawn.level == 3 as "stat 10 is the level the summon named"
  // Property 7 of Creature2 75048 at level 3, as three 32-bit products:
  // CreatureLevel 3 unitPropertyValue07 342.0863342285156, times Creature2ArcheType
  // 23's 10.0 (3420.86328125), times Creature2Difficulty 23's 214.0 (732064.75),
  // times Creature2Tier 1's 1.0; the whole part is 732064. At level 50 it is
  // 84971216, the health the same creature has at its own level.
  assert spawn.health == 732_064
    as "the creature's Base Health at level 3, not at its minLevel 50"
  // Property 44: CreatureLevel 3's 1.0 times the archetype's 1.0, Creature2Difficulty
  // 23's 18.0 and the tier's 1.0. Level 50's row has the same 1.0.
  assert spawn.combat.interrupt_armor == creature_life.Armor(points: 18)
    as "the armor is the level's 1.0 times the difficulty's 18.0"
  assert spawn.faction_id == 171 && spawn.display_info_id == 22_825
    as "the rest of the summon is Durek's, as at his own level"
}

pub fn a_summon_with_a_level_the_creature_level_table_has_no_row_for_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  // CreatureLevel has rows 1 to 101, the last of which holds the values of the
  // properties 100 and above (CreatureLevel.101).
  list.each(
    [
      #(0, "below the first row"),
      #(102, "above the last row"),
      #(
        10_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000,
        "a number past any float",
      ),
    ],
    fn(row) {
      assert summoned_at_level(creature_id: beast, level: Some(row.0))
        == Error(spawn.NoCreatureLevelRow(level: row.0))
        as row.1
    },
  )
  assert spawn.describe_refusal(spawn.NoCreatureLevelRow(level: 200))
    == "CreatureLevel 200 has no row"
    as "the sentence the player's system line carries, as for a Creature2 id with no row"
}

pub fn a_summon_of_the_battle_beast_at_level_3_has_that_levels_health_and_no_armor_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(spawn) = summoned_at_level(creature_id: beast, level: Some(3))
    as "the Beast at level 3 passes the checks of a spawn"
  assert spawn.level == 3 as "stat 10 is the level the summon named"
  // CreatureLevel 3 unitPropertyValue07 342.0863342285156 times Creature2ArcheType
  // 1's 1.0, Creature2Difficulty 1's 0.387 and Creature2Tier 1's 1.0 is 132.387,
  // as the Beast's 52.62 at level 1 is 135.97 times the same.
  assert spawn.health == 132 as "the Beast's Base Health at level 3, not 52"
  assert spawn.combat.interrupt_armor == creature_life.NoArmor
    as "Creature2Difficulty 1's property 44 multiplier is 0.0"
  assert spawn.faction_id == 1441 && spawn.display_info_id == 26_565
    as "the rest of the summon is the Beast's, as at level 1"
}

pub fn a_summon_at_level_101_the_row_of_the_properties_from_100_up_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  // CreatureLevel 101 holds the values of the properties 100 and above for every
  // level and none of the properties below (CreatureLevel.101), so it is no
  // level of a creature.
  assert summoned_at_level(creature_id: beast, level: Some(101))
    == Error(spawn.NotACreatureLevel(level: 101))
  assert spawn.describe_refusal(spawn.NotACreatureLevel(level: 101))
    == "CreatureLevel 101 holds the values of the properties from 100 up, and is no level"
    as "the sentence the player's system line carries"
}

pub fn a_creature_with_a_base_health_override_is_refused_at_level_101_too_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Creature2OverrideProperties row 2866 gives Creature2 11467 a Base Health
  // (property 7) of 5000, so its health reads no CreatureLevel row at all and
  // only the level's own check keeps level 101 out.
  assert real_summon_at(creature_id: 11_467, level: 101)
    == Error(spawn.NotACreatureLevel(level: 101))
}

pub fn a_summon_at_the_level_of_the_creatures_own_row_is_the_summon_with_no_level_test() -> Nil {
  use <- owned_test.run(5000)
  assert summoned_at_level(creature_id: beast, level: Some(1))
    == summoned_from_client(creature_id: beast)
    as "the Beast's minLevel is 1 (Creature2.73464), so naming level 1 changes nothing"
}
