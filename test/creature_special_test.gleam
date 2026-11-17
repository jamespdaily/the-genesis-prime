//// The creature_special table's rows and their checks
//// (`genesis_prime/world_map/creature_special`, `creature_kind` `select` and `taken`), on the
//// client's committed rows. Expected values come from these places.
//// - The retail record: the Jabbithole pages of the creatures, Abilities tab, list Earthen
////   Roar at tier 1 (Spell4 55317) and tier 2 (55318, which the server leaves out by its own
////   choice) for Rootbrute Grimspore (Creature2 12212, 13118, 13549),
////   Crash (55296) for Mysthoof Trampler (27687) and Mysthoof Doe (28623), Venomous
////   Mandible (55327) for Venombite Spider (24057) and Slime Spray (55330) for Saltwater
////   Snoglug (25979). The 10 000 ms cooldown is a server choice, a guess.
//// - The client holds no spell list for a creature (`creature.ai_data`), so the default kind
////   row 0 is the one every creature takes and a special for it would be cast by every
////   creature; a creature with no kind row of its own takes the default's fields.
//// - The strike deadline (`strike_tell.deadline_ms`, 1000 ms): a cooldown below it would open
////   two strike rounds at once, as `creature_kind` refuses an attack interval below it.
//// - The spells the checks name, from `table_rows -- Spell4Effects spellId=N`:
////   33251 has castTime 0 (a Yeti auto-attack); 42764 has effects of types 8, 17, 71 and 4;
////   55635 (Ice Breath) has damage row 132757 with phaseFlags 6, phases 1 and 2 of 4 gos;
////   54675 (Wallop) has damage row 159798 with phaseFlags 4, go 2 of 4, and 66285 and 55317
////   strike at their last go.

import content_support
import database_support
import fixture_tables
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal.{Refusal, RowId}
import genesis_prime/game/strike_tell
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/creature_special.{type Row, Ref, Row}
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import owned_test
import planted_table.{Integer}

/// The default row as migration 0010 leaves it.
const default_row =
  creature_kind.Row(
    creature_id: 0,
    respawn_ms: 60_000,
    attack_spell4_id: 5649,
    attack_interval_ms: 1500,
    guard_spell4_id: option.None,
    opening_spell4_id: option.None,
  )

/// A special of Rootbrute Grimspore (Creature2 12212): first in its list, cast again after
/// 10 000 ms.
fn special(spell4_id spell4_id: Int) -> Row {
  Row(creature_id: 12_212, spell4_id:, order_index: 0, cooldown_ms: 10_000)
}

/// The refusals of the rows, with the default kind row beside them.
fn refused(rows rows: List(Row)) -> List(refusal.Refusal) {
  let assert Error(refusals) =
    creature_kind.select(
      rows: [default_row],
      special_rows: rows,
      auto_attack_rows: [],
      tables: fixture_tables.shared(),
    )
    as "the rows are refused"
  refusals
}

/// The one refusal of one special row, its sentence.
fn rule_of(row row: Row) -> String {
  let assert [
    Refusal(table: "creature_special", row: RowId(creature_id), rule:),
  ] = refused(rows: [row])
    as "the one row is refused, under its table and the creature's id"
  assert creature_id == row.creature_id as "the refusal names the creature"
  rule
}

pub fn the_rows_for_the_five_creatures_load_as_their_kinds_specials_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads with its specials"
  let kinds = content_creature_kind.kinds(key:)
  let specials = fn(creature) {
    creature_kind.kind_of(kinds:, creature2_id: creature).specials
  }
  list.each(
    [
      #(12_212, 55_317),
      #(13_118, 55_317),
      #(13_549, 55_317),
      #(27_687, 55_296),
      #(28_623, 55_296),
      #(24_057, 55_327),
      #(25_979, 55_330),
    ],
    fn(row) {
      assert specials(row.0) == [Ref(spell4_id: row.1, cooldown_ms: 10_000)]
        as "the creature's retail ability (Jabbithole, Abilities tab) with the guessed cooldown"
    },
  )
  assert specials(73_464) == []
    as "a creature the table does not name casts no special"
  let trampler = creature_kind.kind_of(kinds:, creature2_id: 27_687)
  assert trampler.attack_spell4_id == Spell4Id(5649)
    && trampler.attack_interval_ms == 1500
    && trampler.respawn_ms == 60_000
    as "a creature with specials, no auto-attack rows and no kind row takes the default kind's own fields"
}

pub fn a_special_for_a_creature_the_client_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's Creature2 holds no row 200001 (as content_load_test's refusal of a kind).
  let rule =
    rule_of(row: Row(..special(spell4_id: 55_317), creature_id: 200_001))
  assert string.contains(rule, "Creature2") && string.contains(rule, "200001")
    as "the refusal names the table and the creature"
  assert string.contains(rule, "55317") as "and its spell"
}

pub fn a_special_for_the_default_kind_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: Row(..special(spell4_id: 55_317), creature_id: 0))
  assert string.contains(rule, "default") && string.contains(rule, "55317")
    as "creature_kind row 0 is the default every creature takes, so every creature would cast it"
}

pub fn a_special_the_client_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: special(spell4_id: 5650))
  assert string.contains(rule, "Spell4") && string.contains(rule, "5650")
    as "the client's Spell4 holds no row 5650"
}

pub fn a_cooldown_below_the_strike_deadline_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let deadline = strike_tell.deadline_ms
  let rule =
    rule_of(row: Row(..special(spell4_id: 55_317), cooldown_ms: deadline - 1))
  assert string.contains(rule, int.to_string(deadline - 1))
    && string.contains(rule, int.to_string(deadline))
    as "the refusal names the cooldown and the deadline"
  let assert Ok(_) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [Row(..special(spell4_id: 55_317), cooldown_ms: deadline)],
      auto_attack_rows: [],
      tables: fixture_tables.shared(),
    )
    as "a cooldown of the deadline itself is taken"
  Nil
}

pub fn a_spell_with_no_cast_time_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: special(spell4_id: 33_251))
  assert string.contains(rule, "33251") && string.contains(rule, "cast time")
    as "Spell4 33251 has castTime 0: a special is a cast with a cast bar"
}

pub fn a_spell_with_another_effect_type_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: special(spell4_id: 42_764))
  assert string.contains(rule, "type 17") && string.contains(rule, "97539")
    as "Spell4Effects 97539 is the first row of Spell4 42764 that is neither damage (8) nor NpcExecutionDelay (35): type 17"
}

pub fn a_spell_with_several_strike_phases_is_refused_naming_its_step_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: special(spell4_id: 55_635))
  assert string.contains(rule, "55635")
    && string.contains(rule, "go 1 and go 2")
    as "Spell4Effects 132757 strikes at phaseFlags 6: go 1 and go 2"
  assert string.contains(rule, "several hits")
    as "the sentence names the step that closes the gap: a creature's cast with several hits"
}

pub fn a_spell_that_strikes_before_its_last_go_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: special(spell4_id: 54_675))
  assert string.contains(rule, "54675")
    && string.contains(rule, "go 2")
    && string.contains(rule, "go 3")
    as "Spell4Effects 159798 strikes at phaseFlags 4, go 2, and the spell's last of 4 gos is go 3"
}

pub fn a_delay_row_behind_a_prerequisite_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: the client's Spell4Effects 131968 has no prerequisite; the load reads none
  // for a delay row, so a row behind one would hold without it.
  let assert [Refusal(table: "creature_special", row: RowId(12_212), rule:)] = {
    use tables <- fixture_tables.changed(
      table: "Spell4Effects",
      id: 131_968,
      with: [#("prerequisiteIdCasterApply", Integer(30_526))],
    )
    let assert Error(refusals) =
      creature_kind.select(
        rows: [default_row],
        special_rows: [special(spell4_id: 55_317)],
        auto_attack_rows: [],
        tables:,
      )
      as "the delay row's prerequisite is refused"
    refusals
  }
  assert string.contains(rule, "131968") && string.contains(rule, "30526")
    as "the refusal names the row and its prerequisite"
}

/// The one refusal of Earthen Roar (Spell4 55317) as a special of Rootbrute Grimspore when
/// the client's row `id` of `table` holds `cells` in place of its own.
fn roar_refused_when(
  table table: String,
  id id: Int,
  cells cells: List(#(String, planted_table.Cell)),
) -> String {
  use tables <- fixture_tables.changed(table:, id:, with: cells)
  let assert Error([
    Refusal(table: "creature_special", row: RowId(12_212), rule:),
  ]) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [special(spell4_id: 55_317)],
      auto_attack_rows: [],
      tables:,
    )
    as "the changed row is refused by the special's own check"
  rule
}

pub fn the_refusals_each_name_what_the_changed_row_of_earthen_roar_breaks_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: each change is one cell of a real row of Spell4 55317 (Spell4Effects 131967
  // and 131968, SpellPhase 11192), which the client holds as the other tests read it.
  assert string.contains(
    roar_refused_when(table: "Spell4", id: 55_317, cells: [
      #("spell4CCConditionsIdTarget", Integer(1)),
    ]),
    "target conditions row 1",
  )
    as "a target state the cast needs is one no special reads"
  assert string.contains(
    roar_refused_when(table: "Spell4", id: 55_317, cells: [
      #("spell4AoeTargetConstraintsId", Integer(0)),
    ]),
    "no area row",
  )
    as "a cast with no area selects nobody"
  assert string.contains(
    roar_refused_when(table: "Spell4Effects", id: 131_967, cells: [
      #("phaseFlags", Integer(0)),
    ]),
    "no damage row",
  )
    as "a damage row that names no go strikes nobody"
  assert string.contains(
    roar_refused_when(table: "SpellPhase", id: 11_192, cells: [
      #("phaseDelay", Integer(0)),
    ]),
    "no damage row",
  )
    as "the plan drops a later phase with no delay (spell_plan phases_by_owner), so the damage row's go 1 is gone"
  assert string.contains(
    roar_refused_when(table: "Spell4Effects", id: 131_968, cells: [
      #("targetFlags", Integer(2)),
    ]),
    "does not apply",
  )
    as "a delay row aimed at the target is one the plan leaves out"
  assert string.contains(
    roar_refused_when(table: "Spell4Effects", id: 131_968, cells: [
      #("phaseFlags", Integer(-1)),
    ]),
    "go 0 and go 1",
  )
    as "a delay row in every phase names a go before the strike go"
}

pub fn the_kinds_taken_keep_the_specials_the_load_takes_beside_a_refusal_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = [
    special(spell4_id: 55_317),
    Row(..special(spell4_id: 33_251), creature_id: 13_118),
  ]
  let assert Ok(kinds) =
    creature_kind.taken(
      rows: [default_row],
      special_rows: rows,
      auto_attack_rows: [],
      tables: fixture_tables.shared(),
    )
    as "the default row is taken"
  assert creature_kind.kind_of(kinds:, creature2_id: 12_212).specials
    == [Ref(spell4_id: 55_317, cooldown_ms: 10_000)]
    as "the row the load takes keeps its special"
  assert creature_kind.kind_of(kinds:, creature2_id: 13_118).specials == []
    as "the refused row leaves none"
}

pub fn every_refused_special_is_collected_test() -> Nil {
  use <- owned_test.run(60_000)
  let refusals =
    refused(rows: [
      Row(..special(spell4_id: 55_317), creature_id: 0),
      Row(..special(spell4_id: 33_251), creature_id: 13_118),
      Row(..special(spell4_id: 5650), creature_id: 13_549),
    ])
  assert list.map(refusals, fn(refusal) { refusal.row })
    == [RowId(0), RowId(13_118), RowId(13_549)]
    as "each bad row beside its neighbours, as the other tables' refusals are"
}
