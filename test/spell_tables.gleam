//// The planted tables of the spell plan's tests: the rows `genesis_prime/game/spell_plan`
//// reads for a few abilities, each with the values the client's own row holds
//// (the fact file's `Spell4.*` records, read with `table_rows`), and a load of
//// just those tables, so a test can take a row away or add one and meet the
//// plan's build with it.
////
//// The abilities and what the real rows hold, which the plan's tests assert:
//// - Telekinetic Strike, Spell4 32893 (class 3, base 19102): castTime 1250,
////   castBarType 1, no cooldown of its own, global cooldown kind 0 with SpellCoolDown
////   row 213 (1000 ms), a Magic damage effect and a Proxy to 30900 on the caster
////   (`Spell4.32893`).
//// - Mind Burst, 32809 (class 3, base 19019): an innate cost of type 6 (Resource1,
////   the Esper's Psi Points) of 1, kind 0, row 104 (1250 ms) (`Spell4CastResult.vital_cost`).
//// - Crush, 32812 (class 3, base 19022): cooldown 35000, kind 3, and one Proxy,
////   100 ms after the go, to 42297 (`Spell4.32812`).
//// - Gamma Rays, 29874 (class 4, base 16322): a cost of type 18 (Actuator) of 2,
////   weapon slot 1, castTime 1250, kind 0, row 159 (1250 ms), and Proxies to
////   34775 and 35886; Class 4's slots 1 to 5 hold vital 18
////   (`Spell4CastResult.vital_cost`).
//// - Stagger, 38791 (class 5, base 23173): cooldown 25000, kind 1, row
////   180 (750 ms), and a Proxy to 38780, a
////   Multiphase spell (base 23162, castMethod 8) of four phases of 166, 200, 167
////   and 167 ms (SpellPhase 3717 to 3720), each phase proxying 38781 by its
////   phaseFlags 1, 2, 4 and 8 (`Spell4.38791`).
//// The child spells' bases are the client's (`table_rows -- Spell4 30900 34775 35886 38781`),
//// each of cast method 0 but 38780's.

import genesis_prime/game/spell_plan
import genesis_prime/table/class
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/order
import planted_table.{type Cell, Float, Integer}

/// The planted rows of each table the plan reads.
pub type Rows {
  Rows(
    spell_levels: List(List(Cell)),
    spell4: List(List(Cell)),
    spell4_base: List(List(Cell)),
    spell4_effects: List(List(Cell)),
    spell_phases: List(List(Cell)),
    spell_cool_downs: List(List(Cell)),
    classes: List(List(Cell)),
  )
}

/// A Spell4 row: its base, cast time, own cooldown, range, innate cost, global
/// cooldown kind and global SpellCoolDown row.
fn spell4_row(
  id id: Int,
  base base: Int,
  cast_time cast_time: Int,
  cooldown cooldown: Int,
  range range: Float,
  cost cost: #(Int, Int),
  kind kind: Int,
  global global: Int,
) -> List(Cell) {
  planted_table.row(spell4.schema, [
    #("ID", Integer(id)),
    #("spell4BaseIdBaseSpell", Integer(base)),
    #("castTime", Integer(cast_time)),
    #("spellCoolDown", Integer(cooldown)),
    #("targetMaxRange", Float(range)),
    #("innateCostType0", Integer(cost.0)),
    #("innateCost0", Integer(cost.1)),
    #("globalCooldownEnum", Integer(kind)),
    #("spellCoolDownIdGlobal", Integer(global)),
    #("propertyFlags", Integer(property_flags(id))),
  ])
}

/// Spell4.propertyFlags of the planted rows, as `table_rows -- Spell4 <id>` prints
/// them (`Spell4.propertyFlags`): 0x1 makes a press ignore a live cast.
fn property_flags(id: Int) -> Int {
  case id {
    32_893 | 29_874 | 32_809 -> 0x4000002
    58_591 -> 0x4000102
    41_438 -> 0x4000103
    34_355 -> 0x3
    42_297 | 30_436 -> 0x100
    32_812 -> 0x4100003
    38_791 -> 0x4000003
    38_780 -> 0x103
    _ -> 0
  }
}

/// A Spell4Base row: its cast method, weapon slot, cast bar type and class.
fn base_row(
  id id: Int,
  method method: Int,
  weapon weapon: Int,
  bar bar: Int,
  class class: Int,
) -> List(Cell) {
  planted_table.row(spell4_base.schema, [
    #("ID", Integer(id)),
    #("castMethod", Integer(method)),
    #("weaponSlot", Integer(weapon)),
    #("castBarType", Integer(bar)),
    #("classIdPlayer", Integer(class)),
  ])
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
) -> List(Cell) {
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(spell)),
    #("targetFlags", Integer(target_flags)),
    #("effectType", Integer(type_)),
    #("delayTime", Integer(delay)),
    #("phaseFlags", Integer(phases)),
    #("dataBits00", Integer(data)),
  ])
}

fn phase_row(id id: Int, delay delay: Int, order order: Int) -> List(Cell) {
  planted_table.row(spell_phase.schema, [
    #("ID", Integer(id)),
    #("phaseDelay", Integer(delay)),
    #("orderIndex", Integer(order)),
    #("spell4IdOwner", Integer(38_780)),
  ])
}

fn class_row(id id: Int, slots slots: List(Int)) -> List(Cell) {
  planted_table.row(class.schema, [
    #("ID", Integer(id)),
    ..list.index_map(slots, fn(vital, slot) {
      #("vitalEnumResource0" <> int.to_string(slot), Integer(vital))
    })
  ])
}

/// The planted rows of the abilities above and their children.
pub fn rows() -> Rows {
  Rows(
    spell_levels: list.map(
      [
        #(647, 3, 32_893),
        #(766, 3, 32_809),
        #(1239, 3, 32_812),
        #(1086, 4, 29_874),
        #(808, 5, 38_791),
        #(925, 1, 58_591),
        #(1188, 2, 41_438),
        #(1185, 2, 41_276),
        #(1236, 7, 34_355),
      ],
      fn(row) {
        planted_table.row(spell_level.schema, [
          #("ID", Integer(row.0)),
          #("classId", Integer(row.1)),
          #("characterLevel", Integer(1)),
          #("prerequisiteId", Integer(0)),
          #("spell4Id", Integer(row.2)),
        ])
      },
    ),
    spell4: [
      spell4_row(
        id: 58_591,
        base: 38_017,
        cast_time: 0,
        cooldown: 20_000,
        range: 7.0,
        cost: #(0, 0),
        kind: 3,
        global: 127,
      ),
      spell4_row(
        id: 41_438,
        base: 25_635,
        cast_time: 0,
        cooldown: 30_000,
        range: 25.0,
        cost: #(0, 0),
        kind: 1,
        global: 0,
      ),
      spell4_row(
        id: 41_276,
        base: 25_473,
        cast_time: 0,
        cooldown: 0,
        range: 25.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 34_355,
        base: 20_325,
        cast_time: 0,
        cooldown: 30_000,
        range: 17.0,
        cost: #(0, 0),
        kind: 1,
        global: 155,
      ),
      spell4_row(
        id: 25_190,
        base: 11_781,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 30_436,
        base: 16_838,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 32_893,
        base: 19_102,
        cast_time: 1250,
        cooldown: 0,
        range: 30.0,
        cost: #(0, 0),
        kind: 0,
        global: 213,
      ),
      spell4_row(
        id: 30_900,
        base: 17_288,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 32_809,
        base: 19_019,
        cast_time: 0,
        cooldown: 0,
        range: 25.0,
        cost: #(6, 1),
        kind: 0,
        global: 104,
      ),
      spell4_row(
        id: 32_812,
        base: 19_022,
        cast_time: 0,
        cooldown: 35_000,
        range: 25.0,
        cost: #(0, 0),
        kind: 3,
        global: 104,
      ),
      spell4_row(
        id: 42_297,
        base: 26_488,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 29_874,
        base: 16_322,
        cast_time: 1250,
        cooldown: 0,
        range: 20.0,
        cost: #(18, 2),
        kind: 0,
        global: 159,
      ),
      spell4_row(
        id: 34_775,
        base: 20_737,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 35_886,
        base: 21_506,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 38_791,
        base: 23_173,
        cast_time: 0,
        cooldown: 25_000,
        range: 8.0,
        cost: #(0, 0),
        kind: 1,
        global: 180,
      ),
      spell4_row(
        id: 38_780,
        base: 23_162,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
      spell4_row(
        id: 38_781,
        base: 23_163,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
    ]
      |> list.sort(by_id),
    spell4_base: [
      base_row(id: 38_017, method: 0, weapon: 0, bar: 0, class: 1),
      base_row(id: 25_635, method: 0, weapon: 1, bar: 0, class: 2),
      base_row(id: 25_473, method: 1, weapon: 1, bar: 0, class: 2),
      base_row(id: 20_325, method: 0, weapon: 0, bar: 0, class: 7),
      base_row(id: 11_781, method: 0, weapon: 0, bar: 1, class: 0),
      base_row(id: 16_838, method: 0, weapon: 0, bar: 0, class: 0),
      base_row(id: 19_102, method: 0, weapon: 0, bar: 1, class: 3),
      base_row(id: 17_288, method: 0, weapon: 0, bar: 0, class: 0),
      base_row(id: 19_019, method: 0, weapon: 0, bar: 0, class: 3),
      base_row(id: 19_022, method: 0, weapon: 0, bar: 0, class: 3),
      base_row(id: 26_488, method: 0, weapon: 0, bar: 0, class: 0),
      base_row(id: 16_322, method: 0, weapon: 1, bar: 1, class: 4),
      base_row(id: 20_737, method: 0, weapon: 0, bar: 0, class: 0),
      base_row(id: 21_506, method: 0, weapon: 0, bar: 0, class: 0),
      base_row(id: 23_173, method: 0, weapon: 1, bar: 0, class: 5),
      base_row(id: 23_162, method: 8, weapon: 0, bar: 0, class: 0),
      base_row(id: 23_163, method: 0, weapon: 0, bar: 0, class: 0),
    ]
      |> list.sort(by_id),
    spell4_effects: [
      effect_row(
        id: 67_778,
        spell: 34_355,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: -1,
        data: 25_190,
      ),
      effect_row(
        id: 67_779,
        spell: 34_355,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: -1,
        data: 30_436,
      ),
      effect_row(
        id: 62_159,
        spell: 32_893,
        type_: 8,
        target_flags: 4,
        delay: 0,
        phases: -1,
        data: 1_065_353_216,
      ),
      effect_row(
        id: 62_204,
        spell: 32_893,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: -1,
        data: 30_900,
      ),
      effect_row(
        id: 56_858,
        spell: 30_900,
        type_: 1,
        target_flags: 1,
        delay: 0,
        phases: -1,
        data: 6,
      ),
      effect_row(
        id: 62_007,
        spell: 32_812,
        type_: 26,
        target_flags: 4,
        delay: 100,
        phases: 1,
        data: 42_297,
      ),
      effect_row(
        id: 95_950,
        spell: 42_297,
        type_: 8,
        target_flags: 6,
        delay: 0,
        phases: 1,
        data: 1_065_353_216,
      ),
      effect_row(
        id: 70_001,
        spell: 29_874,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: -1,
        data: 34_775,
      ),
      effect_row(
        id: 70_002,
        spell: 29_874,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: -1,
        data: 35_886,
      ),
      effect_row(
        id: 83_853,
        spell: 38_791,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: 1,
        data: 38_780,
      ),
      effect_row(
        id: 83_823,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 1,
        data: 38_781,
      ),
      effect_row(
        id: 83_824,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 2,
        data: 38_781,
      ),
      effect_row(
        id: 83_825,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 4,
        data: 38_781,
      ),
      effect_row(
        id: 83_826,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 8,
        data: 38_781,
      ),
      effect_row(
        id: 83_829,
        spell: 38_781,
        type_: 8,
        target_flags: 2,
        delay: 0,
        phases: 1,
        data: 1_065_353_216,
      ),
    ]
      |> list.sort(by_id),
    spell_phases: [
      phase_row(id: 3717, delay: 166, order: 0),
      phase_row(id: 3718, delay: 200, order: 1),
      phase_row(id: 3719, delay: 167, order: 2),
      phase_row(id: 3720, delay: 167, order: 3),
    ],
    spell_cool_downs: list.map(
      [
        #(104, 1250),
        #(127, 1250),
        #(155, 750),
        #(159, 1250),
        #(180, 750),
        #(213, 1000),
      ],
      fn(row) {
        planted_table.row(spell_cool_down.schema, [
          #("ID", Integer(row.0)),
          #("cooldownTime", Integer(row.1)),
        ])
      },
    ),
    classes: [
      class_row(id: 3, slots: [5, 0, 0, 0, 0, 0, 0, 16]),
      class_row(id: 4, slots: [5, 18, 18, 18, 18, 18, 0, 16]),
      class_row(id: 5, slots: [5, 0, 0, 0, 0, 0, 0, 16]),
    ],
  )
}

/// Every planted row holds its ID in its first cell.
fn by_id(first: List(Cell), second: List(Cell)) -> order.Order {
  let assert [Integer(first_id), ..] = first
    as "a planted row holds its ID first"
  let assert [Integer(second_id), ..] = second
    as "a planted row holds its ID first"
  int.compare(first_id, second_id)
}

/// The load of the planted tables with the plan's derivation, which fails when
/// the plan cannot be built: the load's error, or `Ok(Nil)`.
pub fn derivation_result(
  rows rows: Rows,
) -> Result(Nil, table_store.LoadError) {
  let files = files_of(rows:)
  use folder <- planted_table.in_folder(files)
  case
    table_store.load(
      under: reference.new(),
      from: folder,
      entries: entries(),
      requirements: [],
      derivations: [spell_plan.derivation()],
    )
  {
    Ok(tables) -> {
      table_store.unload(tables)
      Ok(Nil)
    }
    Error(error) -> Error(error)
  }
}

fn entries() -> List(table_store.Entry) {
  [
    spell_level.entry(),
    spell4.entry(),
    spell4_base.entry(),
    spell4_effects.entry(),
    spell_phase.entry(),
    spell_cool_down.entry(),
    class.entry(),
  ]
}

fn files_of(rows rows: Rows) -> List(#(String, BitArray)) {
  [
    planted_table.file(spell_level.schema, rows.spell_levels),
    planted_table.file(spell4.schema, rows.spell4),
    planted_table.file(spell4_base.schema, rows.spell4_base),
    planted_table.file(spell4_effects.schema, rows.spell4_effects),
    planted_table.file(spell_phase.schema, rows.spell_phases),
    planted_table.file(spell_cool_down.schema, rows.spell_cool_downs),
    planted_table.file(class.schema, rows.classes),
  ]
}

/// The planted tables the plan reads, loaded from these rows under a key of
/// their own, for the body to run on; unloaded afterwards.
pub fn with_loaded(
  rows rows: Rows,
  body body: fn(table_store.Tables) -> a,
) -> a {
  let files = files_of(rows:)
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) =
    table_store.load(
      under: reference.new(),
      from: folder,
      entries: entries(),
      requirements: [],
      derivations: [],
    )
    as "the planted spell tables load"
  let result = body(tables)
  table_store.unload(tables)
  result
}
