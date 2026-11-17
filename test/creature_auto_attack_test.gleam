//// The creature_auto_attack table's rows and their checks
//// (`genesis_prime/world_map/creature_auto_attack`, `creature_kind` `select` and `taken`), on
//// the client's committed rows. Expected values come from these places.
//// - The retail record: the Jabbithole pages of the creatures, Abilities tab, list Maul (33251)
////   and Slam (33252) for Yeti Snowstalker (Creature2 51126 and 11945, page `yeti-snowstalker-1`),
////   Punch (5649) and Jab (5652) for Skeech Scratcher (11910), Ram (32761) and Bash (32762)
////   with Reaching Bite (55308) for Bloodstone Oxian (24058), Pinch (25870) and Snap (25871)
////   for Scrab Striker (24054), Swipe (6616) and Claw (6617) with Whirl (55283) for Malverine
////   Stalker (26026), Swipe (33247) and Swing (33248) with Earthen Roar (55317) for Rootbrute
////   Grimspore (12212, 13118, 13549) and Elderoot Deathcap (36173), and Pinch (6651) and Slice
////   (6652) with Venomous Mandible (55327) for Venombite Hatchling (24051).
//// - The client's Spell4 descriptions number the pairs: 33251 "Auto-Attack #1" and 33252
////   "#2", and likewise the others (`table_rows -- Spell4 33251 33252 5649 5652`). The order
////   #1 then #2 is a guess: no client table holds a strike order.
//// - The client holds no attack list for a creature (`creature.ai_data`), so the default kind
////   row 0 is the one every creature takes and an auto-attack for it would be struck by every
////   creature; a creature with no kind row of its own takes the default's fields.
//// - The spells the checks name, from `table_rows -- Spell4 <id>` and
////   `Spell4Effects spellId=<id>`: 33251 has castTime 0 and damage rows 184751 (difficulty up
////   to 6, prerequisite 30526) and 184829 (7 and above, 30527); 55317 has castTime 3000; 6651
////   has damage rows 185104 and 185116 whose formulas read parameter type 2, which the creature
////   formula does not (`damage.creature_unread`); Venombite Hatchling is difficulty 2
////   (`table_rows -- Creature2 24051`).

import content_support
import database_support
import fixture_tables
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal.{Refusal, RowId}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/creature_auto_attack.{type Row, Row}
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/creature_special
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

/// The auto-attack `spell4_id` of Yeti Snowstalker (Creature2 51126) at place `order_index`.
fn yeti_auto(spell4_id spell4_id: Int, order_index order_index: Int) -> Row {
  Row(creature_id: 51_126, spell4_id:, order_index:)
}

/// The kinds the default row and these auto-attack rows make, on the client's rows.
fn kinds_of(rows rows: List(Row)) -> creature_kind.Kinds {
  let assert Ok(kinds) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [],
      auto_attack_rows: rows,
      tables: fixture_tables.shared(),
    )
    as "the rows are taken"
  kinds
}

/// The refusals of the rows, with the default kind row beside them.
fn refused(rows rows: List(Row)) -> List(refusal.Refusal) {
  let assert Error(refusals) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [],
      auto_attack_rows: rows,
      tables: fixture_tables.shared(),
    )
    as "the rows are refused"
  refusals
}

/// The one refusal of one auto-attack row, its sentence.
fn rule_of(row row: Row) -> String {
  let assert [
    Refusal(table: "creature_auto_attack", row: RowId(creature_id), rule:),
  ] = refused(rows: [row])
    as "the one row is refused, under its table and the creature's id"
  assert creature_id == row.creature_id as "the refusal names the creature"
  rule
}

pub fn the_rows_of_a_creature_load_as_the_kinds_lead_and_alternates_in_order_test() -> Nil {
  use <- owned_test.run(60_000)
  // Listed out of order: the place in the turn, not the list's order, decides.
  let kinds =
    kinds_of(rows: [
      yeti_auto(spell4_id: 33_252, order_index: 1),
      yeti_auto(spell4_id: 33_251, order_index: 0),
    ])
  let yeti = creature_kind.kind_of(kinds:, creature2_id: 51_126)
  assert yeti.attack_spell4_id == Spell4Id(33_251)
    && yeti.alternate_spell4_ids == [Spell4Id(33_252)]
    as "Maul first, then Slam: the page lists both and the Spell4 descriptions number them #1 and #2"
  assert yeti.attack_interval_ms == 1500 && yeti.respawn_ms == 60_000
    as "a creature with auto-attacks and no kind row takes the default kind's other fields"
}

pub fn a_creature_with_no_auto_attack_rows_keeps_the_default_attack_test() -> Nil {
  use <- owned_test.run(60_000)
  // Rootbrute Grimspore (12212) has a special row and no auto-attack row, so it has a kind of
  // its own beside Yeti Snowstalker's.
  let assert Ok(kinds) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [
        creature_special.Row(
          creature_id: 12_212,
          spell4_id: 55_317,
          order_index: 0,
          cooldown_ms: 10_000,
        ),
      ],
      auto_attack_rows: [
        yeti_auto(spell4_id: 33_251, order_index: 0),
        yeti_auto(spell4_id: 33_252, order_index: 1),
      ],
      tables: fixture_tables.shared(),
    )
    as "the rows are taken"
  list.each([12_212, 73_464], fn(creature_id) {
    let kind = creature_kind.kind_of(kinds:, creature2_id: creature_id)
    assert kind.attack_spell4_id == Spell4Id(5649)
      && kind.alternate_spell4_ids == []
      as "the client holds no attack list for a creature, so it strikes with the default kind's 5649"
  })
}

pub fn a_creature_with_autos_and_a_special_loads_both_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(kinds) =
    creature_kind.select(
      rows: [default_row],
      special_rows: [
        creature_special.Row(
          creature_id: 24_058,
          spell4_id: 55_308,
          order_index: 0,
          cooldown_ms: 10_000,
        ),
      ],
      auto_attack_rows: [
        Row(creature_id: 24_058, spell4_id: 32_761, order_index: 0),
        Row(creature_id: 24_058, spell4_id: 32_762, order_index: 1),
      ],
      tables: fixture_tables.shared(),
    )
    as "Bloodstone Oxian's page lists Ram, Bash and Reaching Bite, a cast of 3000 ms"
  let oxian = creature_kind.kind_of(kinds:, creature2_id: 24_058)
  assert oxian.attack_spell4_id == Spell4Id(32_761)
    && oxian.alternate_spell4_ids == [Spell4Id(32_762)]
    && oxian.specials
    == [creature_special.Ref(spell4_id: 55_308, cooldown_ms: 10_000)]
    as "the autos in turn and the special, in the one kind"
}

pub fn an_auto_attack_for_a_creature_the_client_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's Creature2 holds no row 200001.
  let rule =
    rule_of(
      row: Row(
        ..yeti_auto(spell4_id: 33_251, order_index: 0),
        creature_id: 200_001,
      ),
    )
  assert string.contains(rule, "Creature2") && string.contains(rule, "200001")
    as "the refusal names the table and the creature"
  assert string.contains(rule, "33251") as "and its spell"
}

pub fn an_auto_attack_for_the_default_kind_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule =
    rule_of(
      row: Row(..yeti_auto(spell4_id: 33_251, order_index: 0), creature_id: 0),
    )
  assert string.contains(rule, "default") && string.contains(rule, "33251")
    as "creature_kind row 0 is the default every creature takes, so every creature would strike with it"
}

pub fn an_auto_attack_the_client_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: yeti_auto(spell4_id: 5650, order_index: 0))
  assert string.contains(rule, "Spell4") && string.contains(rule, "5650")
    as "the client's Spell4 holds no row 5650"
}

pub fn a_spell_with_a_cast_time_is_refused_as_an_auto_attack_test() -> Nil {
  use <- owned_test.run(60_000)
  let rule = rule_of(row: yeti_auto(spell4_id: 55_317, order_index: 0))
  assert string.contains(rule, "55317") && string.contains(rule, "3000 ms")
    as "Spell4 55317, Earthen Roar, has castTime 3000: it is a special, not an auto-attack"
}

pub fn an_auto_attack_the_attack_rule_does_not_evaluate_is_refused_with_its_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: the client's Spell4 33251 has innateCostEMMId0 0.
  let cost = {
    use tables <- fixture_tables.changed(table: "Spell4", id: 33_251, with: [
      #("innateCostEMMId0", Integer(4)),
    ])
    let assert Error([Refusal(table: "creature_auto_attack", rule:, ..)]) =
      creature_kind.select(
        rows: [default_row],
        special_rows: [],
        auto_attack_rows: [yeti_auto(spell4_id: 33_251, order_index: 0)],
        tables:,
      )
      as "a spell that spends is refused"
    rule
  }
  assert string.contains(cost, "Spell4 33251")
    && string.contains(cost, "EMM id 4")
    as "the sentence of the attack rule's refusal: a creature's attack spends no points"
  // Synthetic: the client's Spell4Effects 184751 has tickTime 0.
  let periodic = {
    use tables <- fixture_tables.changed(
      table: "Spell4Effects",
      id: 184_751,
      with: [#("tickTime", Integer(1500))],
    )
    let assert Error([Refusal(table: "creature_auto_attack", rule:, ..)]) =
      creature_kind.select(
        rows: [default_row],
        special_rows: [],
        auto_attack_rows: [yeti_auto(spell4_id: 33_251, order_index: 0)],
        tables:,
      )
      as "a periodic damage row is refused"
    rule
  }
  assert string.contains(periodic, "184751")
    && string.contains(periodic, "1500")
    as "the refusal names the effect and the tick"
}

pub fn an_auto_attack_with_an_unread_damage_formula_is_refused_at_the_kind_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Venombite Hatchling (Creature2 24051, difficulty 2) strikes with Pinch (6651) on the
  // retail page; its damage row 185104, for difficulties up to 6, reads parameter type 2.
  let hatchling = Row(creature_id: 24_051, spell4_id: 6651, order_index: 0)
  let rule = rule_of(row: hatchling)
  assert string.contains(rule, "6651")
    && string.contains(rule, "185104")
    && string.contains(rule, "parameter type 2")
    && string.contains(rule, "difficulty 2")
    as "the refusal names the spell, the effect, the parameter the creature formula does not read and the difficulty"
  let assert Ok(kinds) =
    creature_kind.taken(
      rows: [default_row],
      special_rows: [],
      auto_attack_rows: [hatchling],
      tables: fixture_tables.shared(),
    )
    as "the default row is taken"
  assert creature_kind.kind_of(kinds:, creature2_id: 24_051).attack_spell4_id
    == Spell4Id(5649)
    as "the creature keeps the default attack"
}

pub fn a_creature_with_a_kind_row_and_auto_attack_rows_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 73494 and 74862, the Sim-Turrets, name their charge in a creature_kind row
  // (migration 0029); a row of that kind for Yeti Snowstalker stands for them. One place
  // names a creature's attack.
  let kind_row =
    creature_kind.Row(
      creature_id: 51_126,
      respawn_ms: 60_000,
      attack_spell4_id: 5649,
      attack_interval_ms: 1500,
      guard_spell4_id: option.None,
      opening_spell4_id: option.None,
    )
  let assert Error([
    Refusal(table: "creature_auto_attack", row: RowId(51_126), rule:),
  ]) =
    creature_kind.select(
      rows: [default_row, kind_row],
      special_rows: [],
      auto_attack_rows: [yeti_auto(spell4_id: 33_251, order_index: 0)],
      tables: fixture_tables.shared(),
    )
    as "the auto-attack row is refused, the kind row is not"
  assert string.contains(rule, "creature_kind")
    && string.contains(rule, "33251")
    as "the refusal names the kind row and the spell"
}

pub fn the_kinds_taken_keep_the_autos_the_load_takes_beside_a_refusal_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = [
    yeti_auto(spell4_id: 33_251, order_index: 0),
    yeti_auto(spell4_id: 33_252, order_index: 1),
    Row(creature_id: 11_945, spell4_id: 5650, order_index: 0),
  ]
  let assert Ok(kinds) =
    creature_kind.taken(
      rows: [default_row],
      special_rows: [],
      auto_attack_rows: rows,
      tables: fixture_tables.shared(),
    )
    as "the default row is taken"
  let yeti = creature_kind.kind_of(kinds:, creature2_id: 51_126)
  assert yeti.attack_spell4_id == Spell4Id(33_251)
    && yeti.alternate_spell4_ids == [Spell4Id(33_252)]
    as "the rows the load takes keep their autos"
  assert creature_kind.kind_of(kinds:, creature2_id: 11_945).attack_spell4_id
    == Spell4Id(5649)
    as "the refused row leaves the default attack"
}

pub fn every_refused_auto_attack_is_collected_test() -> Nil {
  use <- owned_test.run(60_000)
  let refusals =
    refused(rows: [
      Row(..yeti_auto(spell4_id: 33_251, order_index: 0), creature_id: 0),
      Row(..yeti_auto(spell4_id: 33_251, order_index: 0), creature_id: 200_001),
      Row(..yeti_auto(spell4_id: 5650, order_index: 0), creature_id: 11_910),
    ])
  assert list.map(refusals, fn(refusal) { refusal.row })
    == [RowId(0), RowId(200_001), RowId(11_910)]
    as "the default kind, a creature the client lacks and a spell the client lacks, each beside its neighbours, as the other tables' refusals are"
}

pub fn the_rows_of_the_acceptance_creatures_load_on_the_clients_tables_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads with its auto-attacks"
  let kinds = content_creature_kind.kinds(key:)
  let ids = fn(spell4_ids) { list.map(spell4_ids, Spell4Id) }
  // Each: the creature, its lead, its alternates and its specials, from its Jabbithole page
  // (the page named in the row's `reason`) and the Spell4 descriptions "#1" and "#2".
  list.each(
    [
      #(51_126, 33_251, [33_252], []),
      #(11_945, 33_251, [33_252], []),
      #(11_910, 5649, [5652], []),
      #(24_058, 32_761, [32_762], [55_308]),
      #(24_054, 25_870, [25_871], []),
      #(26_026, 6616, [6617], [55_283]),
      #(12_212, 33_247, [33_248], [55_317]),
      #(13_118, 33_247, [33_248], [55_317]),
      #(13_549, 33_247, [33_248], [55_317]),
      #(36_173, 33_247, [33_248], [55_317]),
    ],
    fn(row) {
      let kind = creature_kind.kind_of(kinds:, creature2_id: row.0)
      assert kind.attack_spell4_id == Spell4Id(row.1)
        && kind.alternate_spell4_ids == ids(row.2)
        && list.map(kind.specials, fn(special) { special.spell4_id }) == row.3
        as { "the autos and specials of Creature2 " <> string.inspect(row.0) }
    },
  )
  let hatchling = creature_kind.kind_of(kinds:, creature2_id: 24_051)
  assert hatchling.attack_spell4_id == Spell4Id(5649)
    && hatchling.alternate_spell4_ids == []
    && list.map(hatchling.specials, fn(special) { special.spell4_id })
    == [55_327]
    as "Venombite Hatchling's Pinch and Slice name a damage parameter the creature formula does not read, so it holds no auto-attack row and keeps 5649 and its Venomous Mandible"
  assert content_support.psql(
      database:,
      sql: "select count(*) from creature_auto_attack where source <> 'retail_record' or reason not like '%guess%'",
    )
    |> string.trim
    == "0"
    as "every hand-entered row is a retail record with its guess marked"
}
