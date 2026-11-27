//// The click_objective content table (read by `genesis_prime/content/objective_set`) and the
//// load's check of its rows (`genesis_prime/game/click_objective`): the visible scripted
//// objectives whose text asks only to click a creature. Expected values come from these places.
//// - `QuestObjective.type.5`: a type 5 objective is done only by the server's 0x361, and
////   `0x140550c50` counts a unit of the objective's reward pane for an objective of any
////   type, so a row's pane is the list of creatures whose activation counts for it.
//// - A row must be a click the server can see done: a visible (flag 0x8 clear), required
////   (flag 0x20 clear) type 5 objective that no creature links (`objective_link.is_linked`),
////   with a marker row, whose pane lists a creature the client offers a click on
////   (`0x140479560`, kind Spell 50: an activate spell, activationFlags bit 0x800 clear, no
////   datacube; `0x14046c6a0`: a creature with uiFlags bit 0x80 is locked to the path kinds)
////   whose activate spells the server builds, and that no spell effect or item names
////   (`Spell4Effects.effectType.42`, `0x140398cc0`).
//// - The fixture's rows (`table_rows -- QuestObjective 16170 6159 5201 9998 15737 4849
////   9659 1962`, `TargetGroup`, `Creature2`): 16170 (quest 6591, type 5, flags 3, pane 6299
////   that lists Creature2 51440 with activate spell 1817, marker WorldLocation2 40836 in World
////   22) is a click; 6159 (quest 4508) has the pane 4654 of Creature2 16595, which has no
////   activate spell; 5201 (quest 3963) and 9998 (quest 6269) have panes of Creature2 27196
////   and 27996, whose uiFlags 175 has bit 0x80; 15737 (quest 8767) has the pane 7657 of
////   Creature2 45780, whose activate spells 44757 and 42154 hold a type 65 effect no rule
////   reads; 4849 (quest 3769) is named by Spell4Effects 89873; 1962 (quest 1859) has no
////   marker; 9659 (quest 6296, type 12) is linked by Creature2 27768.
//// - A row of the migration is a `server_choice`.

import client_tables
import content_support
import fixture_tables
import genesis_prime/content/refusal.{RowId}
import genesis_prime/game/activate
import genesis_prime/game/arrival_objective
import genesis_prime/game/click_objective
import genesis_prime/game/objective
import genesis_prime/game/place_objective
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/shared/effect_kind
import genesis_prime/shared/faction_level
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/id.{Creature2Id, QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4_effects
import genesis_prime/world_map/spawn
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import quest_support
import unitest

/// The objective of quest 6591 the fixture holds as a click: a visible, required, marked,
/// unlinked type 5 whose pane lists one creature the client offers a click on.
const the_face_of_justice = 16_170

/// The pane of objective 16170, which lists Creature2 51440.
const pane_of_16170 = 6299

/// The objectives the migration lists.
const click_ids = [7652, 7653, 7654, 9002, 16_170]

/// What a row of the table does to the load.
type Outcome {
  Accepted
  Refused(saying: String)
}

/// A row to check: the QuestObjective cells edited first (id, column, value), the objective
/// named, what the load does with it and why.
type Case {
  Case(
    why: String,
    edits: List(#(Int, String, Int)),
    objective: Int,
    outcome: Outcome,
  )
}

const no_click_pane = "no creature the client offers a click on"

pub fn the_click_table_refuses_a_row_the_client_offers_no_click_on_or_the_server_cannot_build_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(cases(), fn(row) {
    use tables <- quest_support.with_objectives(edits: row.edits)
    let selected = click_objective.select(ids: [row.objective], tables:)
    case row.outcome {
      Accepted -> {
        assert selected == Ok(set.from_list([row.objective]))
          as { row.why <> ": the load takes the row" }
      }
      Refused(saying:) -> {
        let assert Error([refusal]) = selected
          as { row.why <> ": one refusal for the objective" }
        assert refusal.row == RowId(row.objective)
        assert string.contains(refusal.rule, saying)
          as {
            row.why
            <> ": the rule says "
            <> saying
            <> "; it said "
            <> refusal.rule
          }
      }
    }
  })
}

fn cases() -> List(Case) {
  [
    Case(
      why: "quest 6591's objective 16170 is a click on the creature of pane 6299",
      edits: [],
      objective: the_face_of_justice,
      outcome: Accepted,
    ),
    Case(
      why: "a type 2 row is not a scripted objective",
      edits: [#(the_face_of_justice, "type", 2)],
      objective: the_face_of_justice,
      outcome: Refused("not 5 (a scripted objective)"),
    ),
    Case(
      why: "flag 0x8 hides it",
      edits: [#(the_face_of_justice, "flags", 3 + 8)],
      objective: the_face_of_justice,
      outcome: Refused("flag 0x8 hides it"),
    ),
    Case(
      why: "flag 0x20 makes it optional",
      edits: [#(the_face_of_justice, "flags", 3 + 0x20)],
      objective: the_face_of_justice,
      outcome: Refused("flag 0x20 makes it optional"),
    ),
    Case(
      why: "Creature2 27768 links objective 9659, made a click with the pane of 16170",
      edits: [
        #(9659, "type", 5),
        #(9659, "flags", 0),
        #(9659, "worldLocationsIdIndicator00", 21_383),
        #(9659, "targetGroupIdRewardPane", pane_of_16170),
      ],
      objective: 9659,
      outcome: Refused("a creature links it"),
    ),
    Case(
      why: "no marker row, so no creature can stand at it (objective 1962 of quest 1859)",
      edits: [#(1962, "targetGroupIdRewardPane", pane_of_16170)],
      objective: 1962,
      outcome: Refused(
        "none of its worldLocationsIdIndicator markers names a WorldLocation2 row",
      ),
    ),
    Case(
      why: "pane 0 names no unit",
      edits: [#(the_face_of_justice, "targetGroupIdRewardPane", 0)],
      objective: the_face_of_justice,
      outcome: Refused("has no reward pane"),
    ),
    Case(
      why: "a pane the TargetGroup table has no row for lists no creature",
      edits: [#(the_face_of_justice, "targetGroupIdRewardPane", 4_000_000)],
      objective: the_face_of_justice,
      outcome: Refused("lists no creature"),
    ),
    Case(
      why: "objective 6159 (quest 4508, index 3): Creature2 16595 has no activate spell",
      edits: [],
      objective: 6159,
      outcome: Refused(no_click_pane),
    ),
    Case(
      why: "objective 5201 (quest 3963, index 0): Creature2 27196 has uiFlags bit 0x80",
      edits: [],
      objective: 5201,
      outcome: Refused(no_click_pane),
    ),
    Case(
      why: "objective 9998 (quest 6269, index 2): Creature2 27996 has uiFlags bit 0x80",
      edits: [],
      objective: 9998,
      outcome: Refused(no_click_pane),
    ),
    Case(
      why: "objective 15737 (quest 8767, index 0): Creature2 45780's spells 44757 and 42154 hold an effect no rule reads, so the server does not build the cast",
      edits: [],
      objective: 15_737,
      outcome: Refused(no_click_pane),
    ),
    Case(
      why: "Spell4Effects 89873 names objective 4849, given the click's pane",
      edits: [#(4849, "targetGroupIdRewardPane", pane_of_16170)],
      objective: 4849,
      outcome: Refused("a spell effect or an item names it"),
    ),
    Case(
      why: "the QuestObjective table has no row 4000000",
      edits: [],
      objective: 4_000_000,
      outcome: Refused("QuestObjective table has no row"),
    ),
  ]
}

pub fn a_spell_with_an_effect_no_rule_reads_is_the_reason_creature_45780_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let effect_types_of = fn(spell4_id) {
    spell4_effects.all(tables)
    |> list.filter(fn(effect) { effect.spell_id == spell4_id })
    |> list.map(fn(effect) { effect.effect_type })
  }
  assert effect_types_of(44_757) == [65]
    as "Spell4Effects 103397: the one effect of spell 44757 is type 65"
  assert !effect_kind.is_read(effect_type: 65)
    as "no rule of the server reads effect type 65"
  assert list.all(effect_types_of(1817), fn(effect_type) {
    effect_kind.is_read(effect_type:)
  })
    as "every effect of spell 1817 is of a type a rule reads"
}

pub fn a_creature_hostile_to_a_faction_the_quest_allows_is_no_click_for_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6591 is for the Dominion (questPlayerFactionEnum 1) and Creature2 51440 has factionId
  // 170, which is not Hostile to it. Faction 171 is Friendly to the Exile and Hostile to the
  // Dominion (Faction2Relationship 771 and 685: `spawn.faction_levels(171)` is #(10, 0)), so a
  // creature of it that the Dominion cannot be offered is no click for this quest; quest 5263 is
  // for the Exile (enum 0), whose creatures 21688, 27100 and 27101 are of faction 171 and are
  // clicks (`every_row_of_the_click_table...`).
  assert spawn.faction_levels(tables: fixture_tables.shared(), faction: 171)
    == #(10, 0)
    as "faction 171 is Friendly to the Exile and Hostile to the Dominion"
  fixture_tables.changed(
    table: "Creature2",
    id: 51_440,
    with: [#("factionId", Integer(171))],
    body: fn(tables) {
      let assert Error([refusal]) =
        click_objective.select(ids: [the_face_of_justice], tables:)
        as "the Dominion's quest names a creature hostile to it"
      assert string.contains(
        refusal.rule,
        "not Hostile to the Dominion faction",
      )
    },
  )
}

pub fn the_click_row_left_on_the_stand_in_has_a_pane_friendly_to_both_factions_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // Quest 6959's objective 13760 (index 4) is a click on Creature2 36601 (pane 7665), whose
  // factionId 219 is Friendly to both player factions (Faction2Relationship 711: level 10 to
  // the parent of the Exile and the Dominion faction). The selection leaves out a creature
  // Friendly to both that gives no quest and has no link (`spawn.left_out_of`), so no unit
  // of it stands and no player could click it: the objective stays on the stand-in, as the
  // quest completes today.
  let assert Ok(row) = creature2.get(tables, Creature2Id(36_601))
    as "the creature is a root of the fixture"
  assert row.faction_id == 219
  let levels = faction_level.build(tables:)
  assert spawn.friendly_to(
      levels:,
      player: spawn.exile_faction,
      unit: row.faction_id,
    )
    && spawn.friendly_to(
      levels:,
      player: spawn.dominion_faction,
      unit: row.faction_id,
    )
    as "faction 219 is Friendly to both player factions"
  let listed = quest_log.listed_objectives(tables:)
  let assert Ok([#(quest, index, listed_objective)]) = dict.get(listed, 13_760)
    as "one quest lists the objective"
  assert objective.script_of(
      tables:,
      quest_id: quest.id,
      index:,
      objective: listed_objective,
      arrival_objectives: set.new(),
      scripts: objective.no_rows(),
    )
    == objective.StandInOnAccept
    as "the objective is not a click row, so the stand-in completes it"
  assert content_support.objective_ids(table: click_objective.table)
    |> set.contains(13_760)
    == False
    as "the migration lists no row for it"
}

pub fn every_row_of_the_click_table_is_a_click_script_with_a_built_activate_spell_and_a_placeable_marker_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = content_support.objective_ids(table: click_objective.table)
  assert set.to_list(rows) |> list.sort(int.compare) == click_ids
    as "the migration lists the clicks whose creatures start in their marker's world"
  let scripts = objective.ScriptRows(..objective.no_rows(), clicks: rows)
  let arrivals = content_support.objective_ids(table: arrival_objective.table)
  let activations = activate.activations(tables:)
  let listed = quest_log.listed_objectives(tables:)
  // Each objective with the creature of its pane, that creature's first activate spell and
  // the World of its marker (`table_rows -- QuestObjective <id>`, `TargetGroup`, `Creature2`,
  // `WorldLocation2`).
  let expected = [
    #(7652, 21_688, 40_565, 51),
    #(7653, 27_100, 40_565, 51),
    #(7654, 27_101, 40_565, 51),
    #(9002, 26_436, 1817, 22),
    #(16_170, 51_440, 1817, 22),
  ]
  list.each(expected, fn(row) {
    let #(objective_id, creature_id, spell4_id, world_id) = row
    let name = int.to_string(objective_id)
    let assert Ok(places) = dict.get(listed, objective_id)
      as "a quest lists the objective"
    list.each(places, fn(place) {
      let #(quest, index, listed_objective) = place
      assert objective.script_of(
          tables:,
          quest_id: quest.id,
          index:,
          objective: listed_objective,
          arrival_objectives: arrivals,
          scripts:,
        )
        == objective.ClickScript
        as { name <> " is the click script" }
    })
    let assert Ok(objective_row) =
      quest_objective.get(tables:, id: QuestObjectiveId(objective_id))
      as "the objective's row"
    let assert [creature] =
      pane_creatures(tables:, pane: objective_row.target_group_id_reward_pane)
      as "each pane lists one creature"
    assert creature.id == creature_id
      as { name <> "'s pane lists its creature" }
    assert creature.spell4_id_activate00 == spell4_id
      as { name <> "'s creature's activate spell" }
    assert activate.offers_click(row: creature)
      as { name <> "'s creature is one the client offers a click on" }
    assert is_planned(activations:, spell4_id: spell4_id)
      as { name <> "'s spell is built" }
    assert list.map(
        place_objective.markers(tables:, objective: objective_row),
        fn(marker) { marker.world_id },
      )
      == [world_id]
      as { name <> "'s marker is in a world with stored spawns" }
  })
  assert set.to_list(rows) |> list.sort(int.compare)
    == list.map(expected, fn(row) { row.0 }) |> list.sort(int.compare)
    as "every row of the table is one of these"
  assert click_objective.select(ids: click_ids, tables:) == Ok(rows)
    as "the load takes every row over the client's own tables"
}

/// Whether the activate cast's plan of the spell is built.
fn is_planned(
  activations activations: activate.Activations,
  spell4_id spell4_id: Int,
) -> Bool {
  case dict.get(activations.spells, spell4_id) {
    Ok(activate.Planned(..)) -> True
    Ok(activate.NoSpell4Row) | Ok(activate.CannotBePlanned(..)) | Error(Nil) ->
      False
  }
}

/// The Creature2 rows a TargetGroup pane lists.
fn pane_creatures(
  tables tables: table_store.Tables,
  pane pane: Int,
) -> List(Creature2) {
  list.map(target_group.listed_creatures(tables:, group: pane), fn(creature_id) {
    let assert Ok(row) = creature2.get(tables, Creature2Id(creature_id))
      as "the pane's creature is a row of the client's table"
    row
  })
}
