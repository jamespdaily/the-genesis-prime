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

import client_tables
import content_support
import database_support
import fixture_tables
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal.{Refusal, RowId}
import genesis_prime/game/area
import genesis_prime/game/spell_area
import genesis_prime/game/strike_tell
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/creature_life
import genesis_prime/world_map/creature_special.{type Row, Ref, Row}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import planted_table.{Integer}
import spawn_support
import unitest

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
  refused_on(tables: fixture_tables.shared(), rows:)
}

/// The refusals of the rows over these tables.
fn refused_on(
  tables tables: table_store.Tables,
  rows rows: List(Row),
) -> List(refusal.Refusal) {
  let assert Error(refusals) =
    creature_kind.select(
      rows: [default_row],
      special_rows: rows,
      auto_attack_rows: [],
      tables:,
    )
    as "the rows are refused"
  refusals
}

/// The one refusal of one special row, its sentence.
fn rule_of(row row: Row) -> String {
  rule_on(tables: fixture_tables.shared(), row:)
}

/// The one refusal of one special row over these tables, its sentence.
fn rule_on(tables tables: table_store.Tables, row row: Row) -> String {
  let assert [
    Refusal(table: "creature_special", row: RowId(creature_id), rule:),
  ] = refused_on(tables:, rows: [row])
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

pub fn a_special_with_a_cast_time_of_0_loads_when_its_plan_reads_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each spell has castTime 0 (`table_rows -- Spell4 N`) and a creature the retail record
  // pairs with it (the lowest Creature2 id of the Jabbithole pairing the import reads).
  list.each(
    [
      #(34_262, 4148, "Multiphase, castBarType 1, gos at 200 to 1,600 ms"),
      #(34_252, 35_947, "Multiphase whose first go is at 0"),
      #(70_136, 20_775, "no SpellPhase row: no bar, one go"),
      #(52_150, 17_079, "a channel of eight pulses"),
    ],
    fn(row) {
      let #(spell4_id, creature_id, what) = row
      let assert Ok(_) =
        creature_kind.select(
          rows: [default_row],
          special_rows: [
            Row(..special(spell4_id:), creature_id:),
          ],
          auto_attack_rows: [],
          tables: fixture_tables.shared(),
        )
        as {
          "Spell4 "
          <> int.to_string(spell4_id)
          <> " ("
          <> what
          <> ") loads for Creature2 "
          <> int.to_string(creature_id)
        }
    },
  )
}

pub fn an_auto_attack_listed_as_a_special_is_refused_for_its_missing_area_row_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 33251, `[AUTO-ATTACK]` Yeti Auto-Attack #1: no cast prerequisite, innate cost or
  // target condition, its damage rows 184751 and 184829 (type 8, phaseFlags -1, no tickTime)
  // carry only the difficulty prerequisites, the plan reads one go at 0 that they name, and
  // spell4AoeTargetConstraintsId is 0 (`table_rows -- Spell4`, `-- Spell4Effects spellId=33251`):
  // the area rule is the first it breaks.
  assert rule_of(row: special(spell4_id: 33_251))
    == "the special Spell4 33251 of Creature2 12212 is refused: Spell4 33251 has no area row (spell4AoeTargetConstraintsId 0), so its telegraph selects nobody"
    as "a cast time of 0 is no reason to refuse; the missing area is"
}

pub fn a_channel_the_creatures_round_cannot_carry_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 47977, Forge Lava: castMethod 3 (ChanneledField). The client keeps a channel record
  // for it (`0x14055e180`) that the plan does not read, so its go count is not settled.
  let field = rule_of(row: special(spell4_id: 47_977))
  assert string.contains(field, "47977")
    && string.contains(field, "ChanneledField")
    as "the refusal names the spell and the method"
  // Synthetic, a cell of Spell4 52150's row: pulses at 250 ms steps end at 2,500, 100 ms before
  // a channelMaxTime of 2,600, where the client's cast ends; the round writes its 0x7fe after
  // the last go and has no later finish.
  let late_finish =
    refused_when(spell4_id: 52_150, table: "Spell4", id: 52_150, cells: [
      #("channelMaxTime", Integer(2600)),
    ])
  assert string.contains(late_finish, "52150")
    && string.contains(late_finish, "2600")
    && string.contains(late_finish, "2500")
    as "the refusal names the spell, the channelMaxTime and the last pulse"
  // A channelMaxTime of 100 is before the first pulse at 250: the channel has no pulse, so the
  // refusal is the missing go, not a last pulse at 0.
  let no_pulse =
    refused_when(spell4_id: 52_150, table: "Spell4", id: 52_150, cells: [
      #("channelMaxTime", Integer(100)),
    ])
  assert string.contains(no_pulse, "has no go time")
    && !string.contains(no_pulse, "last pulse")
    as "a channel with no pulse is refused for having no go"
}

pub fn a_spell_with_another_effect_type_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: special(spell4_id: 42_764))
  assert string.contains(rule, "type 17") && string.contains(rule, "97539")
    as "Spell4Effects 97539 is the first row of Spell4 42764 that is neither damage (8) nor NpcExecutionDelay (35): type 17"
}

/// The special of Rootbrute Grimspore (Creature2 12212) with the Spell4, as the fixture's rows
/// load it: its gos' times and what each strikes with, and its hold.
fn loaded_special(
  spell4_id spell4_id: Int,
) -> #(List(#(Int, option.Option(List(Int)))), Int) {
  let assert [loaded] =
    spawn_support.special_creature(number: 1, creature_id: 12_212, spell4_id:).combat.specials
    as "the kind lists the one special and the spawn carries it"
  let assert creature_life.Charged(gos:, hold_ms:, ..) = loaded.attack.cast
    as "the spell is a charge"
  #(
    list.map(gos, fn(go) {
      #(
        go.at_ms,
        option.map(go.strike, fn(strike) { strike.spell4_effects_ids }),
      )
    }),
    hold_ms,
  )
}

pub fn a_cast_with_two_damage_gos_loads_and_holds_after_its_last_go_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 132757 (damage, phaseFlags 6) names gos 1 and 2 of Ice Breath's four; the delay
  // row 132758 (NpcExecutionDelay, 500 ms, phaseFlags 0xffff0008) names the last, go 3
  // (`table_rows -- Spell4Effects spellId=55635`, `-- SpellPhase spell4IdOwner=55635`).
  let assert Ok(_) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [special(spell4_id: 55_635)],
      auto_attack_rows: [],
      tables: fixture_tables.shared(),
    )
    as "a cast that strikes at two gos is taken"
  assert loaded_special(spell4_id: 55_635)
    == #(
      [
        #(2600, option.None),
        #(3000, Some([132_757])),
        #(3500, Some([132_757])),
        #(3800, option.None),
      ],
      500,
    )
    as "the damage row strikes at gos 1 and 2, and the creature holds 500 ms after go 3"
}

pub fn a_cast_that_strikes_before_its_last_go_loads_test() -> Nil {
  use <- owned_test.run(60_000)
  // Claw Slam 55632: Spell4Effects 132749 (damage, phaseFlags 1) names go 0 of two; the delay
  // row 132750 (NpcExecutionDelay, 1,000 ms, phaseFlags 0xffff0002) names go 1, the last
  // (`table_rows -- Spell4Effects spellId=55632`, `-- SpellPhase spell4IdOwner=55632`).
  let assert Ok(_) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [special(spell4_id: 55_632)],
      auto_attack_rows: [],
      tables: fixture_tables.shared(),
    )
    as "a cast that strikes before its last go is taken"
  assert loaded_special(spell4_id: 55_632)
    == #([#(2900, Some([132_749])), #(3300, option.None)], 1000)
    as "the blow lands at go 0 and the hold follows go 1"
}

pub fn a_special_the_go_rule_hid_is_refused_for_its_own_row_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 54675 strikes at go 2 of 4 (Spell4Effects 159798, phaseFlags 4) and holds another
  // row, 129708, of effect type 4 (crowd control), which a creature's special does not apply.
  let rule = rule_of(row: special(spell4_id: 54_675))
  assert string.contains(rule, "129708") && string.contains(rule, "type 4")
    as "the refusal names the crowd-control row and its type"
  assert !string.contains(rule, "last go")
    as "and no go: the cast's gos are no reason to refuse it"
}

pub fn a_special_none_of_whose_strike_gos_has_a_hit_row_drawn_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 47746 is not Multiphase: its one go falls at its cast time, 2,500 ms, and its one
  // hit row, 5529 (phaseFlags -1), ends at 2,000 ms, so no hit row is drawn at the one go its
  // damage row 112217 names (`table_rows -- Spell4Effects spellId=47746`, `-- TelegraphDamage
  // 5529`): the cast strikes nobody, whatever creature casts it.
  let rule = rule_of(row: special(spell4_id: 47_746))
  assert string.contains(rule, "47746")
    && string.contains(rule, "strikes nobody")
    as "the refusal names the spell and says no strike go can strike"
}

pub fn a_special_with_some_strike_gos_that_can_never_strike_loads_and_strikes_at_its_drawn_gos_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 80315: gos at 0 and 750 ms (SpellPhase rows 21538 and 21539); its one damage row,
  // 212555 (phaseFlags -1), names both. Its one hit row, 15196, names go 1 alone
  // (`table_rows -- Spell4Effects spellId=80315`, `-- TelegraphDamage 15196`), so go 0 has no hit
  // row and can never strike; go 1 does (Jim: option A, per go).
  let assert Ok(_) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [special(spell4_id: 80_315)],
      auto_attack_rows: [],
      tables: fixture_tables.shared(),
    )
    as "a cast with a strike go that can strike is taken"
  assert loaded_special(spell4_id: 80_315)
    == #([#(0, option.None), #(750, Some([212_555]))], 0)
    as "nobody is struck at go 0 and the blow lands at go 1"
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
  refused_when(spell4_id: 55_317, table:, id:, cells:)
}

/// The one refusal of the special `spell4_id` of Rootbrute Grimspore when the client's row `id`
/// of `table` holds `cells` in place of its own.
fn refused_when(
  spell4_id spell4_id: Int,
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
      special_rows: [special(spell4_id:)],
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
    "names go 0 and go 1, and the creature's hold follows the cast's last go, go 1, alone",
  )
    as "a delay row in every phase names a go before the last"
  assert string.contains(
    refused_when(spell4_id: 55_635, table: "Spell4Effects", id: 132_758, cells: [
      #("phaseFlags", Integer(4)),
    ]),
    "names go 2, and the creature's hold follows the cast's last go, go 3, alone",
  )
    as "Ice Breath's delay row moved to go 2 names a go before its last, go 3"
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

pub fn the_order_and_target_row_lifts_load_63569_70256_and_55846_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 63569: castTime 160, Spell4AoeTargetConstraints 541 (360 degrees, 1 unit, 0 to 70
  // m, targetSelection 3, Random), no Spell4Telegraph row, no target conditions. 70256 (area
  // row 580, Random) names TelegraphDamage 11230 (tt 2, flags 0: it follows its target) and
  // 55846 (area row 116, Closest) 7874 (tt 2, 0x905000: fixed at it). 46696 names 14428 (tt 4,
  // each struck unit) and 39905 a target condition (spell4CCConditionsIdTarget 2), which the
  // special's own check refuses before its area is read.
  let charge_of = fn(spell4_id) {
    let spawn =
      spawn_support.special_creature(number: 1, creature_id: 12_212, spell4_id:)
    let assert [loaded] = spawn.combat.specials
      as "the kind lists the one special"
    let assert creature_life.Charged(area: row, anchor:, ..) =
      loaded.attack.cast
      as "the spell is a charge"
    #(row, anchor)
  }
  let #(row_541, anchor) = charge_of(63_569)
  assert row_541
    == area.Row(
      min_range: 0.0,
      max_range: 70.0,
      degrees: 360.0,
      target_count: 1,
      order: area.Random,
    )
    as "63569 carries the whole of the area row 541"
  assert anchor == area.FollowsCaster
    as "no telegraph row: the hit follows its caster"
  let #(row_580, anchor) = charge_of(70_256)
  assert #(row_580.order, anchor) == #(area.Random, area.FollowsTarget)
  let #(row_116, anchor) = charge_of(55_846)
  assert #(row_116.order, anchor) == #(area.Nearest, area.FixedAtTarget)
  assert string.contains(
    rule_of(row: special(spell4_id: 46_696)),
    "has no damage row whose phaseFlags name a go",
  )
    as "46696's damage rows name no go, which the special's own check finds before its area"
  assert string.contains(
    rule_of(row: special(spell4_id: 39_905)),
    "target conditions row 2",
  )
    as "a target condition is refused before the area is read"
  // No loadable special holds a row on each struck unit, so 55846's row 7874 is changed to tt 4.
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 7874,
    with: [#("targetTypeFlags", Integer(4))],
  )
  assert string.contains(
    rule_on(tables:, row: special(spell4_id: 55_846)),
    "hit telegraph 7874 placed by flags 4, on each unit the strike finds",
  )
    as "a row on each struck unit is refused by its own sentence"
}

/// The refusals of these specials of the creature on the client's own tables.
fn refused_on_the_clients_tables(
  creature_id creature_id: Int,
  spell4_ids spell4_ids: List(Int),
) -> List(String) {
  refused_over(
    tables: client_tables.with_content_tables(),
    creature_id:,
    spell4_ids:,
  )
}

/// The refusals of these specials of the creature over these content tables.
fn refused_over(
  tables tables: table_store.Tables,
  creature_id creature_id: Int,
  spell4_ids spell4_ids: List(Int),
) -> List(String) {
  let rows =
    list.index_map(spell4_ids, fn(spell4_id, index) {
      Row(..special(spell4_id:), creature_id:, order_index: index)
    })
  case
    creature_kind.select(
      rows: [default_row],
      special_rows: rows,
      auto_attack_rows: [],
      tables:,
    )
  {
    Ok(..) -> []
    Error(refusals) -> list.map(refusals, fn(refusal) { refusal.rule })
  }
}

/// The gos of the special `spell4_id` of the creature `creature_id` over these content tables,
/// each with the blows and the shape it strikes with, or `None` for a go of the cast bar alone.
/// The load must take the pair.
fn strikes_of(
  tables tables: table_store.Tables,
  creature_id creature_id: Int,
  spell4_id spell4_id: Int,
) -> List(option.Option(creature_life.GoStrike)) {
  let assert Ok(spawn) =
    spawn_support.special_creature_over(
      tables:,
      number: 1,
      creature_id:,
      spell4_id:,
    )
    as {
      "Creature2 "
      <> int.to_string(creature_id)
      <> " takes Spell4 "
      <> int.to_string(spell4_id)
    }
  let assert [loaded] = spawn.combat.specials
    as "the kind lists the one special and the spawn carries it"
  let assert creature_life.Charged(gos:, ..) = loaded.attack.cast
    as "the spell is a charge"
  list.map(gos, fn(go) { go.strike })
}

/// The load of each pair (Spell4, a Creature2 the retail record pairs with it, the number of gos
/// its damage rows name) over these content tables: the kind load takes the special, the spawn
/// builds it as a charge whose strike gos are that many, each carrying blows and a hit shape;
/// the shape of a spell in `unshaped`, which has no hit row, is its area row. For each pair, the
/// number of gos the plan gives and the number of strike gos.
fn lifted_over(
  tables tables: table_store.Tables,
  pairs pairs: List(#(Int, Int, Int)),
  unshaped unshaped: List(Int),
) -> List(#(Int, Int)) {
  list.map(pairs, fn(pair) {
    let #(spell4_id, creature_id, strike_gos) = pair
    assert refused_over(tables:, creature_id:, spell4_ids: [spell4_id]) == []
      as {
        "the kind load takes Spell4 "
        <> int.to_string(spell4_id)
        <> " for Creature2 "
        <> int.to_string(creature_id)
      }
    let strikes = strikes_of(tables:, creature_id:, spell4_id:)
    let struck =
      list.filter_map(strikes, fn(strike) { option.to_result(strike, Nil) })
    assert list.length(struck) == strike_gos
      as {
        "Spell4 "
        <> int.to_string(spell4_id)
        <> " strikes at the gos its damage rows name, as the measure counts them"
      }
    list.each(struck, fn(strike) {
      assert strike.spell4_effects_ids != []
        as {
          "each strike go of Spell4 "
          <> int.to_string(spell4_id)
          <> " carries blows"
        }
      assert { strike.inside == area.InsideRow }
        == list.contains(unshaped, spell4_id)
        as {
          "each strike go of Spell4 "
          <> int.to_string(spell4_id)
          <> " carries a hit shape, or its area row where the spell has no hit row"
        }
    })
    #(list.length(strikes), list.length(struck))
  })
}

pub fn the_target_row_lift_loads_the_named_specials_and_two_of_the_three_it_held_back_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // The twenty specials the order, shape and placement lifts make loadable, each with the anchor
  // its rows give (`spell_area.area_of_spell`); 63569 has no telegraph row.
  let tables = client_tables.with_content_tables()
  let following_target = [
    43_989, 46_353, 47_319, 47_518, 47_627, 48_590, 48_591, 61_226, 61_416,
    70_256,
  ]
  let fixed_at_target = [
    39_641, 55_759, 55_760, 55_839, 55_846, 55_847, 55_885, 55_918, 61_275,
  ]
  let anchors = fn(spell4_ids, anchor) {
    list.each(spell4_ids, fn(spell4_id) {
      let assert Ok(Some(spell_area.CreatureArea(anchor: found, ..))) =
        spell_area.area_of_spell(tables:, spell4_id: Spell4Id(spell4_id))
        as { "Spell4 " <> int.to_string(spell4_id) <> " reads" }
      assert found == anchor
        as { "Spell4 " <> int.to_string(spell4_id) <> "'s anchor" }
    })
  }
  anchors(following_target, area.FollowsTarget)
  anchors(fixed_at_target, area.FixedAtTarget)
  assert refused_on_the_clients_tables(
      creature_id: 12_212,
      spell4_ids: list.flatten([[63_569], following_target, fixed_at_target]),
    )
    == []
    as "the twenty load"
  assert refused_on_the_clients_tables(creature_id: 47_430, spell4_ids: [55_846])
    == []
    as "Laser Bolt loads for the Construct of 47430, whose faction keeps it from a fight"
  // Geyser Blast 55840 and 55841 strike at go 0 of two: their one hit row each (7874 and 7875,
  // `table_rows -- TelegraphDamage`) is drawn from the 0x7ff to the last go, so every strike go
  // has its shape.
  list.each([55_840, 55_841], fn(spell4_id) {
    let strikes = strikes_of(tables:, creature_id: 12_212, spell4_id:)
    let shaped =
      list.filter_map(strikes, fn(strike) {
        case strike {
          Some(creature_life.GoStrike(inside: area.InsideShapes(_), ..)) ->
            Ok(Nil)
          _ -> Error(Nil)
        }
      })
    assert shaped != []
      as { "Spell4 " <> int.to_string(spell4_id) <> " strikes with a shape" }
    assert list.length(shaped)
      == list.length(list.filter(strikes, option.is_some))
      as {
        "each strike go of Spell4 "
        <> int.to_string(spell4_id)
        <> " has its shape"
      }
  })
  // Laser Barrage 41187 strikes at several gos, but its damage row 92235 reads a parameter
  // (type 3, `table_rows -- Spell4Effects spellId=41187`) the creature formula does not read:
  // it is refused, for its own row.
  let assert [rule] =
    refused_over(tables:, creature_id: 12_212, spell4_ids: [41_187])
    as "Laser Barrage is refused"
  assert string.contains(rule, "92235")
    && string.contains(rule, "parameter type 3")
    as "the refusal names the row and the parameter"
}

pub fn the_multi_hit_lift_loads_the_named_specials_and_leaves_the_rest_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // The 63 retail-listed specials that strike at several gos, or before their last go, a
  // creature the retail record pairs each with (the lowest Creature2 id of the Jabbithole
  // pairing the import reads) and the number of gos the measure counts as strike gos (the
  // gos its damage rows name, `~/.genesis-prime/sweep-1106/drawn_at_go.txt`), over the
  // client's own tables. The measure counts 22 that strike at one go and 41 at two or more.
  let tables = client_tables.with_content_tables()
  let pairs = [
    #(34_050, 17_908, 3),
    #(34_055, 9598, 3),
    #(34_286, 30_635, 8),
    #(35_487, 30_377, 4),
    #(35_727, 12_930, 4),
    #(39_434, 24_229, 2),
    #(39_943, 24_745, 4),
    #(45_335, 13_639, 2),
    #(45_494, 9593, 5),
    #(45_605, 24_038, 3),
    #(45_746, 24_035, 3),
    #(45_756, 24_035, 7),
    #(45_950, 45_809, 4),
    #(45_951, 45_797, 2),
    #(45_995, 24_266, 4),
    #(46_149, 19_892, 4),
    #(46_692, 9794, 4),
    #(46_933, 9570, 2),
    #(47_033, 9794, 2),
    #(51_329, 20_452, 5),
    #(51_586, 53_175, 4),
    #(52_473, 9606, 5),
    #(52_604, 63_533, 3),
    #(52_658, 21_558, 2),
    #(52_789, 26_193, 3),
    #(53_247, 19_873, 5),
    #(53_272, 2409, 2),
    #(54_241, 12_655, 4),
    #(54_327, 12_925, 5),
    #(54_742, 17_080, 4),
    #(55_185, 14_612, 4),
    #(55_286, 27_449, 1),
    #(55_289, 27_878, 1),
    #(55_290, 30_263, 1),
    #(55_292, 11_071, 1),
    #(55_294, 20_811, 1),
    #(55_302, 25_978, 1),
    #(55_303, 26_362, 1),
    #(55_305, 11_925, 1),
    #(55_306, 30_267, 1),
    #(55_311, 27_876, 1),
    #(55_324, 24_054, 1),
    #(55_366, 12_526, 1),
    #(55_433, 24_140, 1),
    #(55_434, 11_951, 1),
    #(55_439, 24_425, 1),
    #(55_440, 61_523, 1),
    #(55_632, 11_948, 1),
    #(55_635, 11_945, 2),
    #(55_721, 27_451, 1),
    #(55_765, 24_216, 1),
    #(55_766, 11_953, 1),
    #(55_843, 11_910, 1),
    #(56_037, 20_957, 5),
    #(56_425, 20_902, 3),
    #(56_614, 13_008, 3),
    #(57_321, 46_403, 3),
    #(57_350, 38_059, 5),
    #(57_624, 15_263, 5),
    #(65_991, 56_967, 3),
    #(71_293, 26_041, 5),
    #(71_861, 55_000, 1),
    #(72_012, 40_168, 8),
  ]
  let strike_counts =
    list.map(lifted_over(tables:, pairs:, unshaped: []), fn(counts) { counts.1 })
  assert list.length(list.filter(strike_counts, fn(count) { count == 1 })) == 22
    as "22 of the 63 strike at one go"
  assert list.length(list.filter(strike_counts, fn(count) { count > 1 })) == 41
    as "41 strike at two to eight"
  let assert [delay_row, crowd_control] =
    refused_on_the_clients_tables(creature_id: 12_212, spell4_ids: [
      34_054,
      54_675,
    ])
    as "34054 and 54675 are refused"
  assert string.contains(delay_row, "34054")
    && string.contains(
      delay_row,
      "the creature's hold follows the cast's last go",
    )
    as "34054's delay row names a go before the last"
  assert string.contains(crowd_control, "54675")
    && string.contains(crowd_control, "129708")
    && string.contains(crowd_control, "type 4")
    as "54675's crowd-control row, not its gos"
}

pub fn the_cast_time_0_lift_loads_the_named_specials_on_the_real_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // The 50 spells of the retail-listed specials with a castTime of 0 that the lift loads, each
  // with the lowest Creature2 id of the Jabbithole pairing the import reads, the number of gos
  // its plan gives and the number of gos its damage rows name at which a hit row is drawn
  // (`table_rows -- SpellPhase spell4IdOwner=N`, `-- Spell4Effects spellId=N`, `--
  // TelegraphDamage`), over the client's own tables. Spell4 72808 takes Creature2 61635: the
  // lowest, 26042, is friendly to both player factions and would not start (both have
  // creature2DifficultyId 5). Its damage row 188167 (phaseFlags 0x7e) names gos 1 to 6, but
  // its hit rows 12150 and 12151 (phaseFlags 0x7c) name gos 2 to 6 and a Multiphase cast
  // compares the phase, so the go at 1,000 ms strikes nobody: 5 of its 7 gos. The counts of
  // 52150 (6) and 72808 (5) rest on `telegraph_window`'s marked guess that a hit row is drawn
  // at a go equal to its end. 52150's hit row
  // 7108 ends at 1,500 ms, so its pulses at 1,750 and 2,000 strike nobody; 48482 and 48497
  // hold a go no hit row is drawn at; 42531 and 42533 name every one of 481 gos (phaseFlags
  // -1). 63724 and 63726 have no hit row and strike inside their area row.
  let tables = client_tables.with_content_tables()
  let pairs = [
    #(33_919, 9573, 5, 5),
    #(34_227, 13_768, 4, 4),
    #(34_252, 26_662, 7, 5),
    #(34_262, 4148, 4, 4),
    #(34_564, 13_759, 5, 3),
    #(35_343, 14_863, 2, 1),
    #(35_963, 13_831, 5, 4),
    #(42_531, 30_635, 481, 481),
    #(42_533, 30_635, 481, 481),
    #(44_634, 51_743, 4, 4),
    #(47_284, 32_858, 10, 10),
    #(47_711, 24_249, 7, 6),
    #(48_482, 17_918, 8, 7),
    #(48_497, 17_918, 8, 7),
    #(48_766, 13_636, 7, 3),
    #(49_888, 17_817, 12, 12),
    #(50_027, 26_419, 5, 3),
    #(50_103, 17_817, 8, 6),
    #(50_317, 49_548, 9, 9),
    #(51_993, 13_728, 9, 8),
    #(52_150, 17_079, 8, 6),
    #(52_235, 13_728, 4, 2),
    #(52_475, 14_863, 3, 1),
    #(52_968, 16_632, 3, 1),
    #(53_415, 24_098, 3, 2),
    #(54_823, 9635, 5, 3),
    #(54_923, 9635, 3, 1),
    #(57_420, 10_440, 4, 1),
    #(58_666, 26_677, 1, 1),
    #(58_775, 32_213, 7, 6),
    #(63_724, 14_612, 1, 1),
    #(63_726, 14_612, 1, 1),
    #(70_015, 24_249, 1, 1),
    #(70_136, 20_775, 1, 1),
    #(70_151, 32_213, 7, 6),
    #(70_152, 32_213, 7, 6),
    #(70_153, 46_462, 7, 6),
    #(70_154, 32_213, 7, 6),
    #(70_412, 41_878, 12, 12),
    #(70_497, 41_877, 5, 3),
    #(70_572, 59_831, 5, 4),
    #(71_203, 30_321, 5, 4),
    #(71_259, 55_000, 6, 5),
    #(71_430, 26_041, 2, 1),
    #(71_903, 26_040, 5, 4),
    #(71_980, 38_207, 5, 4),
    #(72_001, 40_168, 6, 4),
    #(72_036, 48_592, 2, 1),
    #(72_808, 61_635, 7, 5),
    #(73_289, 30_317, 5, 4),
  ]
  let counts =
    lifted_over(
      tables:,
      pairs: list.map(pairs, fn(pair) { #(pair.0, pair.1, pair.3) }),
      unshaped: [63_724, 63_726],
    )
  list.zip(pairs, counts)
  |> list.each(fn(found) {
    let #(#(spell4_id, _, go_count, _), #(planned_gos, _)) = found
    assert planned_gos == go_count
      as {
        "Spell4 "
        <> int.to_string(spell4_id)
        <> " is cast as a charge with the gos of its plan"
      }
  })
  assert list.length(pairs) == 50 as "50 spells"
  assert list.length(list.filter(pairs, fn(pair) { pair.2 == 1 })) == 5
    as "5 of them have one go"
}
