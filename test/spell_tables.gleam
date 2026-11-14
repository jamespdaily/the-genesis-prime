//// The spell tables a plan test builds from: the client's own rows, which a test
//// may change or add to (`fixture_rows`), and `with_loaded`, which loads the tables
//// the plan reads from them so that a test can take a row away or add one.

import database_support
import fixture_tables
import genesis_prime/coverage/effect_row
import genesis_prime/game/server_proxy
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/table/class
import genesis_prime/table/eldan_augmentation
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/level_up_unlock
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import genesis_prime/table/spell4_stack_group
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell4_valid_targets
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import genesis_prime/table/telegraph_damage
import genesis_prime/table/unit_property2
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import planted_table.{type Cell, Integer}

/// The planted rows of each table the plan reads.
pub type Rows {
  Rows(
    spell_levels: List(List(Cell)),
    spell4: List(List(Cell)),
    spell4_conditions: List(List(Cell)),
    spell4_base: List(List(Cell)),
    spell4_effects: List(List(Cell)),
    spell4_thresholds: List(List(Cell)),
    spell4_aoe_target_constraints: List(List(Cell)),
    spell4_valid_targets: List(List(Cell)),
    spell4_telegraph: List(List(Cell)),
    telegraph_damage: List(List(Cell)),
    spell_phases: List(List(Cell)),
    spell_cool_downs: List(List(Cell)),
    classes: List(List(Cell)),
    prerequisites: List(List(Cell)),
    spell4_group_lists: List(List(Cell)),
    spell4_stack_groups: List(List(Cell)),
    unit_properties: List(List(Cell)),
    eldan_augmentations: List(List(Cell)),
    level_up_unlocks: List(List(Cell)),
    positional_requirements: List(List(Cell)),
  )
}

/// The rows in the order of their ids, which the tables' files hold them in.
pub fn sorted_by_id(rows: List(List(Cell))) -> List(List(Cell)) {
  list.sort(rows, by_id)
}

/// A Spell4Effects row of a spell: its type, the unit it names, its delay after
/// the go, its phases and the first data value, which a Proxy (type 26) takes
/// as the spell it starts.
pub fn effect_row(
  id id: Int,
  spell spell: Int,
  type_ type_: Int,
  target_flags target_flags: Int,
  delay delay: Int,
  phases phases: Int,
  data data: Int,
  order order: Int,
) -> List(Cell) {
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(spell)),
    #("targetFlags", Integer(target_flags)),
    #("effectType", Integer(type_)),
    #("delayTime", Integer(delay)),
    #("phaseFlags", Integer(phases)),
    #("dataBits00", Integer(data)),
    #("orderIndex", Integer(order)),
  ])
}

/// A Spell4Effects row in memory with every column 0 but its id, spell, type, aim and
/// phases (every one), for a test of a function that reads one row.
pub fn blank_effect(
  id id: Int,
  spell spell: Int,
  effect_type effect_type: Int,
  target_flags target_flags: Int,
) -> spell4_effects.Spell4Effects {
  spell4_effects.Spell4Effects(
    id:,
    spell_id: spell,
    target_flags:,
    effect_type:,
    damage_type: 0,
    delay_time: 0,
    tick_time: 0,
    duration_time: 0,
    flags: 0,
    data_bits00: 0,
    data_bits01: 0,
    data_bits02: 0,
    data_bits03: 0,
    data_bits04: 0,
    data_bits05: 0,
    data_bits06: 0,
    data_bits07: 0,
    data_bits08: 0,
    data_bits09: 0,
    innate_cost_per_tick_type0: 0,
    innate_cost_per_tick_type1: 0,
    innate_cost_per_tick0: 0,
    innate_cost_per_tick1: 0,
    emm_comparison: 0,
    emm_value: 0,
    threat_multiplier: 0.0,
    spell4_effect_group_list_id: 0,
    prerequisite_id_caster_apply: 0,
    prerequisite_id_target_apply: 0,
    prerequisite_id_caster_persistence: 0,
    prerequisite_id_target_persistence: 0,
    prerequisite_id_target_suspend: 0,
    parameter_type00: 0,
    parameter_type01: 0,
    parameter_type02: 0,
    parameter_type03: 0,
    parameter_value00: 0.0,
    parameter_value01: 0.0,
    parameter_value02: 0.0,
    parameter_value03: 0.0,
    phase_flags: -1,
    order_index: 0,
  )
}

/// A Spell4Effects row of a VitalModifier (type 1) aimed at the caster: the vital
/// (dataBits00) and the amount (dataBits01 and dataBits02, which hold the same
/// number in every starting-kit row), its delay, phases and caster prerequisite
/// (`Spell4Effects.effectType.1`).
pub fn vital_modifier_row(
  id id: Int,
  spell spell: Int,
  vital vital: Int,
  amount amount: Int,
  delay delay: Int,
  phases phases: Int,
  prerequisite prerequisite: Int,
  order order: Int,
) -> List(Cell) {
  vital_modifier_row_with(
    id:,
    spell:,
    vital:,
    amount:,
    delay:,
    phases:,
    prerequisite:,
    order:,
    more: [],
  )
}

/// The same with more columns set, such as `tickTime`, `durationTime` or
/// `targetFlags`.
pub fn vital_modifier_row_with(
  id id: Int,
  spell spell: Int,
  vital vital: Int,
  amount amount: Int,
  delay delay: Int,
  phases phases: Int,
  prerequisite prerequisite: Int,
  order order: Int,
  more more: List(#(String, Int)),
) -> List(Cell) {
  let set = list.map(more, fn(column) { column.0 })
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(spell)),
    #("effectType", Integer(1)),
    #("delayTime", Integer(delay)),
    #("phaseFlags", Integer(phases)),
    #("dataBits00", Integer(vital)),
    #("dataBits01", Integer(amount)),
    #("dataBits02", Integer(amount)),
    #("prerequisiteIdCasterApply", Integer(prerequisite)),
    #("orderIndex", Integer(order)),
    ..list.append(
      case list.contains(set, "targetFlags") {
        True -> []
        False -> [#("targetFlags", Integer(1))]
      },
      list.map(more, fn(column) { #(column.0, Integer(column.1)) }),
    )
  ])
}

/// An EldanAugmentation row (an AMP) of a class that names the spell it adds
/// (`EldanAugmentation.spell4IdAugment`).
pub fn eldan_augmentation_row(
  id id: Int,
  class class: Int,
  spell spell: Int,
) -> List(Cell) {
  planted_table.row(eldan_augmentation.schema, [
    #("ID", Integer(id)),
    #("classId", Integer(class)),
    #("spell4IdAugment", Integer(spell)),
  ])
}

/// A Prerequisite row: its id, flags and conditions as (type, comparison,
/// objectId, value).
pub fn prerequisite_row(
  id id: Int,
  flags flags: Int,
  conditions conditions: List(#(Int, Int, Int, Int)),
) -> List(Cell) {
  planted_table.row(prerequisite.schema, [
    #("ID", Integer(id)),
    #("flags", Integer(flags)),
    ..list.flatten(
      list.index_map(conditions, fn(condition, index) {
        let number = int.to_string(index)
        [
          #("prerequisiteTypeId" <> number, Integer(condition.0)),
          #("prerequisiteComparisonId" <> number, Integer(condition.1)),
          #("objectId" <> number, Integer(condition.2)),
          #("value" <> number, Integer(condition.3)),
        ]
      }),
    )
  ])
}

/// A Spell4Thresholds row: the spell it belongs to, the stage it casts, its place
/// and thresholdDuration, and its first cost.
pub fn threshold_row(
  id id: Int,
  parent parent: Int,
  to_cast to_cast: Int,
  order order: Int,
  duration duration: Int,
  cost cost: #(Int, Int),
) -> List(Cell) {
  planted_table.row(spell4_thresholds.schema, [
    #("ID", Integer(id)),
    #("spell4IdParent", Integer(parent)),
    #("spell4IdToCast", Integer(to_cast)),
    #("orderIndex", Integer(order)),
    #("thresholdDuration", Integer(duration)),
    #("vitalEnumCostType00", Integer(cost.0)),
    #("vitalCostValue00", Integer(cost.1)),
  ])
}

/// A LevelUpUnlock row of the Level system (levelUpUnlockSystemEnum 0): the level
/// at which it is offered.
pub fn level_up_unlock_row(id id: Int, level level: Int) -> List(Cell) {
  planted_table.row(level_up_unlock.schema, [
    #("ID", Integer(id)),
    #("levelUpUnlockSystemEnum", Integer(0)),
    #("level", Integer(level)),
  ])
}

/// The client's Spell4.spellCastStealthChange of these spells, and 0 for any other.
fn stealth_change(id: Int) -> Int {
  case id {
    38_765 -> 1
    _ -> 0
  }
}

/// The client's Spell4.propertyFlags of these spells, and 0 for any other.
fn property_flags(id: Int) -> Int {
  case id {
    32_893 -> 0x4000002
    58_832 -> 0x4000042
    38_765 -> 0x4040003
    _ -> 0
  }
}

/// A Spell4 row of a spell of the cast methods: the columns of the client's row
/// that the plan reads, and the more of them (`thresholdTime`, the channel times)
/// that this row sets.
pub fn method_spell_row(
  id id: Int,
  base base: Int,
  cast_time cast_time: Int,
  cooldown cooldown: Int,
  kind kind: Int,
  global global: Int,
  cost cost: #(Int, Int),
  more more: List(#(String, Int)),
) -> List(Cell) {
  planted_table.row(spell4.schema, [
    #("ID", Integer(id)),
    #("spell4BaseIdBaseSpell", Integer(base)),
    #("castTime", Integer(cast_time)),
    #("spellCoolDown", Integer(cooldown)),
    #("innateCostType0", Integer(cost.0)),
    #("innateCost0", Integer(cost.1)),
    #("globalCooldownEnum", Integer(kind)),
    #("spellCoolDownIdGlobal", Integer(global)),
    #("propertyFlags", Integer(property_flags(id))),
    #("spell4ConditionsIdCaster", Integer(43)),
    #("spellCastStealthChange", Integer(stealth_change(id))),
    ..list.map(more, fn(column) { #(column.0, Integer(column.1)) })
  ])
}

/// Every planted row holds its ID in its first cell.
fn by_id(first: List(Cell), second: List(Cell)) -> order.Order {
  let assert [Integer(first_id), ..] = first
    as "a planted row holds its ID first"
  let assert [Integer(second_id), ..] = second
    as "a planted row holds its ID first"
  int.compare(first_id, second_id)
}

/// The tables of these rows and the rows these roots reach with the plan's
/// derivation, which fails when the plan cannot be built: the error, or
/// `Ok(Nil)`.
pub fn derivation_result(
  rows rows: Rows,
  reaching roots: List(#(String, Int)),
) -> Result(Nil, table_store.LoadError) {
  case edited(rows:, roots:, derivations: [spell_plan.derivation()]) {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(error)
  }
}

/// The spell tables, then the server's other tables, which the spell rows name.
fn server_entries() -> List(table_store.Entry) {
  let spell_tables =
    list.map(entries(), fn(entry) { table_store.schema(entry).table })
  list.append(
    entries(),
    list.filter(server_table.entries(), fn(entry) {
      !list.contains(spell_tables, table_store.schema(entry).table)
    }),
  )
}

/// The shared tables edited into the tables of these rows and the rows these
/// roots reach: the rows the roots reach, each row the client's rows do not hold
/// as it is, and the rows those reach. The edit is built on the caller's heap,
/// and the derivations run on it.
fn edited(
  rows rows: Rows,
  roots roots: List(#(String, Int)),
  derivations derivations: List(table_store.Derivation),
) -> Result(table_store.Tables, table_store.LoadError) {
  let given =
    list.fold(tables_of(rows:), fixture_tables.rows(), fn(held, table) {
      dict.insert(held, { table.0 }.table, table.1)
    })
  // The plan's build reads the innate of every class.
  let classes =
    result.unwrap(dict.get(fixture_tables.rows(), class.schema.table), [])
    |> list.map(fn(row) {
      let assert [Integer(id), ..] = row as "a client row holds its ID first"
      #(class.schema.table, id)
    })
  let kept =
    fixture_tables.reached(rows: given, roots: list.append(roots, classes))
  fixture_tables.edited(
    rows: kept,
    entries: server_entries(),
    requirements: [],
    derivations:,
  )
}

fn entries() -> List(table_store.Entry) {
  [
    spell_level.entry(),
    spell4.entry(),
    spell4_base.entry(),
    spell4_conditions.entry(),
    spell4_effects.entry(),
    spell4_group_list.entry(),
    spell4_stack_group.entry(),
    spell4_thresholds.entry(),
    spell4_aoe_target_constraints.entry(),
    spell4_valid_targets.entry(),
    spell4_telegraph.entry(),
    telegraph_damage.entry(),
    spell_phase.entry(),
    spell_cool_down.entry(),
    prerequisite.entry(),
    positional_requirement.entry(),
    class.entry(),
    unit_property2.entry(),
    eldan_augmentation.entry(),
    level_up_unlock.entry(),
  ]
}

fn tables_of(rows rows: Rows) -> List(#(tbl_file.Schema, List(List(Cell)))) {
  [
    #(spell_level.schema, rows.spell_levels),
    #(spell4.schema, rows.spell4),
    #(spell4_base.schema, rows.spell4_base),
    #(spell4_conditions.schema, rows.spell4_conditions),
    #(spell4_effects.schema, rows.spell4_effects),
    #(spell4_group_list.schema, rows.spell4_group_lists),
    #(spell4_stack_group.schema, rows.spell4_stack_groups),
    #(spell4_thresholds.schema, rows.spell4_thresholds),
    #(spell4_aoe_target_constraints.schema, rows.spell4_aoe_target_constraints),
    #(spell4_valid_targets.schema, rows.spell4_valid_targets),
    #(spell4_telegraph.schema, rows.spell4_telegraph),
    #(telegraph_damage.schema, rows.telegraph_damage),
    #(spell_phase.schema, rows.spell_phases),
    #(spell_cool_down.schema, rows.spell_cool_downs),
    #(class.schema, rows.classes),
    #(prerequisite.schema, rows.prerequisites),
    #(positional_requirement.schema, rows.positional_requirements),
    #(unit_property2.schema, rows.unit_properties),
    #(eldan_augmentation.schema, rows.eldan_augmentations),
    #(level_up_unlock.schema, rows.level_up_unlocks),
  ]
}

/// The tables the plan reads, for the body to run on: the shared tables edited
/// on the body's heap, so nothing is stored and nothing is left to unload. The
/// edit holds the rows these roots reach, each row the client's rows do not hold
/// as it is, and the rows those reach.
pub fn with_loaded(
  rows rows: Rows,
  reaching roots: List(#(String, Int)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  with_loaded_deriving(rows:, reaching: roots, derivations: [], body:)
}

/// The same, with these derivations run on the edit, which fails when one does.
pub fn with_loaded_deriving(
  rows rows: Rows,
  reaching roots: List(#(String, Int)),
  derivations derivations: List(table_store.Derivation),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let assert Ok(tables) = edited(rows:, roots:, derivations:)
    as "the spell tables load"
  body(tables)
}

/// The effect ids of the rows a spell's own lists hold, in no order: its gains, lasting
/// rows, removes, controls, property changes, forced moves, cooldown changes, stealth
/// rows, shield heals, procs and Proxies (the rows of its children are theirs).
pub fn listed_effect_ids(spell spell: spell_plan.Spell) -> List(Int) {
  list.flatten([
    list.map(spell.gains, fn(gain) { gain.effect_id.value }),
    list.map(spell.lasting, fn(lasting) { lasting.effect_id.value }),
    list.map(spell.removes, fn(remove) { remove.effect_id.value }),
    list.map(spell.controls, fn(control) { control.effect_id.value }),
    list.map(spell.modifiers, fn(modifier) { modifier.effect_id.value }),
    list.map(spell.forced_moves, fn(move) { move.effect_id.value }),
    list.map(spell.cooldown_modifiers, fn(modifier) { modifier.effect_id.value }),
    list.map(spell.stealth, fn(stealth) { stealth.effect_id.value }),
    list.map(spell.remove_stealth, fn(remove) { remove.effect_id.value }),
    list.map(spell.heals, fn(heal) { heal.effect_id.value }),
    list.map(spell.procs, fn(proc) { proc.effect_id.value }),
    list.map(spell.proxies, fn(proxy) { proxy.effect_id.value }),
  ])
}

/// The place of a spell no Proxy starts on each struck unit and that spends nothing.
pub const pressed = spell_plan.RowPlace(struck_by: None, spends_all: False)

/// The place of a spell the Proxy effect `proxy_effect_id` of Spell4 `spell4_id` starts on
/// each unit its area strikes.
pub fn started_on_each_struck(
  spell4_id spell4_id: Int,
  proxy_effect_id proxy_effect_id: Int,
) -> spell_plan.RowPlace {
  spell_plan.RowPlace(
    struck_by: Some(spell_plan.StruckBy(spell4_id:, proxy_effect_id:)),
    spends_all: False,
  )
}

/// What the plan makes of each of these effect rows in a place (`spell_plan.read_row`),
/// over the client's rows, in the order given.
pub fn read_rows(
  effects effects: List(spell4_effects.Spell4Effects),
  place place: spell_plan.RowPlace,
) -> List(Result(spell_plan.RowReading, spell_plan.PlanError)) {
  let tables = fixture_tables.shared()
  let spell_groups = spell_plan.spell_groups(tables:)
  list.map(effects, fn(effect) {
    spell_plan.read_row(tables:, spell_groups:, place:, effect:)
  })
}

/// What the plan makes of one effect row in a place (`spell_plan.read_row`), over the
/// client's rows.
pub fn read_row(
  effect effect: spell4_effects.Spell4Effects,
  place place: spell_plan.RowPlace,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  let assert [reading] = read_rows(effects: [effect], place:)
  reading
}

/// Whether the coverage measure counts the row read in a place, over the client's rows.
pub fn measure_reads(
  effect effect: spell4_effects.Spell4Effects,
  place place: spell_plan.RowPlace,
) -> Bool {
  use reads <- with_measure
  reads(effect, place)
}

/// The body gets the measure's per-row answer over the client's rows.
pub fn with_measure(
  body body: fn(fn(spell4_effects.Spell4Effects, spell_plan.RowPlace) -> Bool) ->
    a,
) -> a {
  let tables = fixture_tables.shared()
  let spell_groups = spell_plan.spell_groups(tables:)
  body(fn(effect, place) {
    effect_row.is_read(tables:, spell_groups:, place:, effect:)
  })
}

/// Mind Burst's area among these areas.
pub fn mind_burst_in(areas areas: spell_area.Areas) -> spell_area.SpellArea {
  let assert Ok(area) = spell_area.of_spell(areas:, spell4_id: Spell4Id(32_809))
    as "Mind Burst is in the areas"
  area
}

/// Telekinetic Strike's Spell4Base, whose tree the planted rows hold, which the plan
/// tests of one effect type add a row to.
const strike_base = 19_102

/// The plan of Telekinetic Strike built from these planted rows, or why the build fails:
/// each call loads the planted tables once, so a test that needs it asks for it once.
pub fn planned_strike(
  rows rows: Rows,
) -> Result(spell_plan.Spell, spell_plan.PlanError) {
  // SpellLevel 647 is Telekinetic Strike's level-one row, which the plan
  // builds from.
  use tables <- with_loaded_deriving(
    rows:,
    reaching: [#("SpellLevel", 647)],
    derivations: [],
  )
  case spell_plan.build(tables:) {
    Ok(plans) -> {
      let assert Ok(spell) =
        spell_plan.in_plans(plans:, base: id.Spell4BaseId(strike_base))
        as "the plans hold Telekinetic Strike"
      Ok(spell)
    }
    Error(error) -> Error(error)
  }
}

/// The client's rows of the tables the plan reads, which a test may change or add
/// to before `with_loaded` loads them. The fixture holds only the server's tables,
/// so the coverage walk's two are not in it: EldanAugmentation is empty, and
/// LevelUpUnlock holds one planted row, 26, the level the walk's gates read.
/// Gap: LevelUpUnlock 26 is planted, not the client's row (issue 326).
pub fn fixture_rows() -> Rows {
  // The planted row 26 holds the client's levelUpUnlockSystemEnum 0 and level 10
  // (`table_rows -- LevelUpUnlock 26`); its other columns read 0, where the client's
  // row holds levelUpUnlockTypeId 21 and its text and icon.
  let held = fixture_tables.rows()
  let of = fn(schema: tbl_file.Schema) {
    result.unwrap(dict.get(held, schema.table), [])
  }
  Rows(
    spell_levels: of(spell_level.schema),
    spell4: of(spell4.schema),
    spell4_conditions: of(spell4_conditions.schema),
    spell4_base: of(spell4_base.schema),
    spell4_effects: of(spell4_effects.schema),
    spell4_thresholds: of(spell4_thresholds.schema),
    spell4_aoe_target_constraints: of(spell4_aoe_target_constraints.schema),
    spell4_valid_targets: of(spell4_valid_targets.schema),
    spell4_telegraph: of(spell4_telegraph.schema),
    telegraph_damage: of(telegraph_damage.schema),
    spell_phases: of(spell_phase.schema),
    spell_cool_downs: of(spell_cool_down.schema),
    classes: of(class.schema),
    prerequisites: of(prerequisite.schema),
    spell4_group_lists: of(spell4_group_list.schema),
    spell4_stack_groups: of(spell4_stack_group.schema),
    unit_properties: of(unit_property2.schema),
    eldan_augmentations: of(eldan_augmentation.schema),
    level_up_unlocks: [level_up_unlock_row(id: 26, level: 10)],
    positional_requirements: of(positional_requirement.schema),
  )
}

/// The client's rows with this Spell4Effects row added; its spell is Telekinetic
/// Strike when the row says so.
pub fn rows_with_effect(effect effect: List(Cell)) -> Rows {
  let rows = fixture_rows()
  assert !list.any(rows.spell4_effects, fn(row) {
    by_id(row, effect) == order.Eq
  })
    as "a planted effect row of an id the client's table holds would replace the client's row"
  Rows(..rows, spell4_effects: sorted_by_id([effect, ..rows.spell4_effects]))
}

/// A Spell4Effects row of Telekinetic Strike's planted spell of this type aimed by
/// `target_flags`, in every phase, with these columns beside its id, spell and type: the
/// row a plan test of one effect type adds (`rows_with_effect`).
pub fn effect_row_with(
  id id: Int,
  effect_type effect_type: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(32_893)),
    #("effectType", Integer(effect_type)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
  ]
  planted_table.row(
    spell4_effects.schema,
    list.append(
      list.filter(defaults, fn(default) {
        !list.any(columns, fn(given) { given.0 == default.0 })
      }),
      columns,
    ),
  )
}

/// A planted Spell4 row with one column set.
pub fn with_column(
  row row: List(Cell),
  name name: String,
  cell cell: Cell,
) -> List(Cell) {
  list.zip(spell4.schema.columns, row)
  |> list.map(fn(pair) {
    case pair.0.name == name {
      True -> cell
      False -> pair.1
    }
  })
}

/// The client's rows with Telekinetic Strike's Spell4 row changed in one column.
pub fn rows_with_strike(name name: String, cell cell: Cell) -> Rows {
  rows_with_strike_columns(columns: [#(name, cell)])
}

/// The client's rows with Telekinetic Strike's Spell4 row changed in these columns.
pub fn rows_with_strike_columns(
  columns columns: List(#(String, Cell)),
) -> Rows {
  rows_with_spell_columns(spell4_id: 32_893, columns:)
}

/// The client's rows with the Spell4 row `spell4_id` changed in these columns; the
/// row must be held.
pub fn rows_with_spell_columns(
  spell4_id spell4_id: Int,
  columns columns: List(#(String, Cell)),
) -> Rows {
  let rows = fixture_rows()
  assert list.any(rows.spell4, fn(row) {
    case row {
      [Integer(id), ..] -> id == spell4_id
      _ -> False
    }
  })
    as "the client's rows hold the Spell4 row a test changes"
  Rows(
    ..rows,
    spell4: list.map(rows.spell4, fn(row) {
      case row {
        [Integer(id), ..] if id == spell4_id ->
          list.fold(columns, row, fn(row, column) {
            with_column(row:, name: column.0, cell: column.1)
          })
        other -> other
      }
    }),
  )
}

/// The plans the client's rows build, built once.
pub fn fixture_plans() -> spell_plan.Plans {
  database_support.once("spell_tables_fixture_plans", fn() {
    let assert Ok(plans) = spell_plan.build(tables: fixture_tables.shared())
      as "the fixture's spell rows build"
    plans
  })
}

/// Telekinetic Strike's plan from the client's rows, built once.
pub fn fixture_strike() -> spell_plan.Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: fixture_plans(),
      base: id.Spell4BaseId(strike_base),
    )
    as "the plans hold Telekinetic Strike"
  spell
}

/// The areas the client's rows build, built once.
pub fn fixture_areas() -> spell_area.Areas {
  database_support.once("spell_tables_fixture_areas", fn() {
    let assert Ok(areas) = spell_area.build(tables: fixture_tables.shared())
      as "the fixture's spell rows build their areas"
    areas
  })
}

/// The seed row of migration 0018: Pulse Blast's base 26468, go 1, spell 42148.
pub fn volatility_row() -> server_proxy.Row {
  server_proxy.Row(spell4_base_id: 26_468, phase: 1, spell4_id: 42_148)
}

/// The server's Proxies of the seed row, selected over the client's rows
/// (genesis_prime/game/server_proxy), built once. The value holds the planned spell
/// and no table, so a connection made with other tables can plant it.
pub fn server_proxies() -> server_proxy.ServerProxies {
  database_support.once("spell_tables_server_proxies", fn() {
    let tables = fixture_tables.shared()
    let assert Ok(plans) = spell_plan.build(tables:)
      as "the fixture's rows build the spell plans"
    let assert Ok(proxies) =
      server_proxy.select(rows: [volatility_row()], tables:, plans:)
      as "the seed row selects"
    proxies
  })
}

/// The plans of the client's rows with the server's Proxy planted, built once.
pub fn plans_with_server_proxies() -> spell_plan.Plans {
  let proxies = server_proxies()
  database_support.once("spell_tables_plans_with_server_proxies", fn() {
    let assert Ok(plans) = spell_plan.build(tables: fixture_tables.shared())
      as "the fixture's rows build the spell plans"
    server_proxy.planted_into(plans:, proxies:)
  })
}
