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
////
//// The abilities of the cast methods, each row as `table_rows` prints it for the
//// Spell4, Spell4Base, Spell4Thresholds, SpellPhase and Spell4Effects rows of the
//// trees (Proxy effects only):
//// - Pulse Blast 42276 and Quick Draw 43468: Multiphase, SpellPhase rows 5390,
////   5391 and 5882 to 5886; Quick Draw's Proxies sit behind prerequisites 17301
////   and 17302.
//// - Impale 38779: Multiphase, SpellPhase 3715 and 3716, an innate cost of type 8.
//// - Electrocute 41276 and Discharge 58832: Channeled, the channel columns of
////   their Spell4 rows; Discharge proxies 80382 in every phase.
//// - Shred 38765, Relentless Strikes 32078 and Rampage 58524: RapidTap with a
////   thresholdTime of 4000 and the stages of Spell4Thresholds 238, 9 and 10,
////   1073 to 1075.
//// - Charged Shot 34718: ChargeRelease with a thresholdTime of 8200 and the stages
////   of Spell4Thresholds 125, 123 and 124.

import database_support
import genesis_prime/game/spell_plan
import genesis_prime/table/class
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import gleam/int
import gleam/list
import gleam/order
import owned_key
import planted_table.{type Cell, Float, Integer}

/// The planted rows of each table the plan reads.
pub type Rows {
  Rows(
    spell_levels: List(List(Cell)),
    spell4: List(List(Cell)),
    spell4_base: List(List(Cell)),
    spell4_effects: List(List(Cell)),
    spell4_thresholds: List(List(Cell)),
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
    42_276 -> 0x4000002
    43_468 | 32_078 | 32_079 | 32_080 | 66_987 | 71_125 | 71_126 -> 0x4100002
    58_832 | 41_276 -> 0x4000042
    38_765 -> 0x4040003
    38_766 | 38_767 | 39_467 -> 0x40003
    58_524 -> 0x4100006
    34_718 -> 0x4100402
    34_720 | 38_779 -> 0x4000003
    34_722 | 36_691 -> 0x3
    37_302 -> 0x4220002
    80_382 -> 0x100000
    43_498 | 43_499 -> 0x4000000
    70_033 | 70_045 | 70_054 | 70_135 | 71_392 | 71_393 | 71_394 -> 0x4000002
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

/// A Proxy effect that applies only behind a caster prerequisite
/// (`Spell4Effects.prerequisiteIdCasterApply`).
pub fn proxy_behind_prerequisite(
  id id: Int,
  spell spell: Int,
  phases phases: Int,
  data data: Int,
  prerequisite prerequisite: Int,
  order order: Int,
) -> List(Cell) {
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(spell)),
    #("targetFlags", Integer(1)),
    #("effectType", Integer(26)),
    #("phaseFlags", Integer(phases)),
    #("dataBits00", Integer(data)),
    #("prerequisiteIdCasterApply", Integer(prerequisite)),
    #("orderIndex", Integer(order)),
  ])
}

/// A SpellPhase row of an owner: its delay, flags and place in the owner's order.
pub fn phase_row(
  id id: Int,
  owner owner: Int,
  order order: Int,
  delay delay: Int,
  flags flags: Int,
) -> List(Cell) {
  planted_table.row(spell_phase.schema, [
    #("ID", Integer(id)),
    #("phaseDelay", Integer(delay)),
    #("phaseFlags", Integer(flags)),
    #("orderIndex", Integer(order)),
    #("spell4IdOwner", Integer(owner)),
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
    ..list.map(more, fn(column) { #(column.0, Integer(column.1)) })
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
        #(1111, 2, 42_276),
        #(1011, 7, 43_468),
        #(631, 4, 58_832),
        #(780, 5, 38_765),
        #(919, 1, 32_078),
        #(920, 1, 58_524),
        #(1036, 7, 34_718),
        #(807, 5, 38_779),
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
        global: 100,
      ),
      spell4_row(
        id: 30_436,
        base: 16_838,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 100,
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
        global: 100,
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
        global: 100,
      ),
      spell4_row(
        id: 35_886,
        base: 21_506,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 100,
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
        global: 115,
      ),
      spell4_row(
        id: 38_781,
        base: 23_163,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 100,
      ),
      method_spell_row(
        id: 42_276,
        base: 26_468,
        cast_time: 1250,
        cooldown: 0,
        kind: 0,
        global: 125,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 43_468,
        base: 27_638,
        cast_time: 1000,
        cooldown: 0,
        kind: 0,
        global: 82,
        cost: #(0, 0),
        more: [
          #("channelInitialDelay", 366),
          #("channelMaxTime", 1000),
          #("channelPulseTime", 634),
        ],
      ),
      method_spell_row(
        id: 58_832,
        base: 38_201,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 159,
        cost: #(0, 0),
        more: [
          #("channelInitialDelay", 410),
          #("channelMaxTime", 1250),
          #("channelPulseTime", 410),
        ],
      ),
      method_spell_row(
        id: 41_276,
        base: 25_473,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 125,
        cost: #(6, 8),
        more: [
          #("channelInitialDelay", 500),
          #("channelMaxTime", 3000),
          #("channelPulseTime", 500),
        ],
      ),
      method_spell_row(
        id: 38_779,
        base: 23_161,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 146,
        cost: #(8, 35),
        more: [],
      ),
      method_spell_row(
        id: 38_765,
        base: 23_148,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 115,
        cost: #(0, 0),
        more: [#("thresholdTime", 4000)],
      ),
      method_spell_row(
        id: 38_766,
        base: 23_149,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 115,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 32_078,
        base: 18_309,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 121,
        cost: #(0, 0),
        more: [#("thresholdTime", 4000)],
      ),
      method_spell_row(
        id: 32_079,
        base: 18_310,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 32_080,
        base: 18_311,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 58_524,
        base: 37_968,
        cast_time: 0,
        cooldown: 8000,
        kind: 0,
        global: 103,
        cost: #(0, 0),
        more: [#("thresholdTime", 4000)],
      ),
      method_spell_row(
        id: 66_987,
        base: 44_605,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 107,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 71_125,
        base: 47_921,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 107,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 71_126,
        base: 47_922,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 103,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 34_718,
        base: 20_684,
        cast_time: 0,
        cooldown: 10_000,
        kind: 0,
        global: 82,
        cost: #(0, 0),
        more: [#("thresholdTime", 8200)],
      ),
      method_spell_row(
        id: 34_720,
        base: 20_686,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 82,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 34_722,
        base: 20_688,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 82,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 36_691,
        base: 22_175,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 82,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 37_302,
        base: 22_522,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 125,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 43_498,
        base: 27_668,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 145,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 43_499,
        base: 27_669,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 145,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 43_500,
        base: 27_670,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 100,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 80_382,
        base: 26_759,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 100,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 38_767,
        base: 23_150,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 100,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 39_467,
        base: 23_799,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 100,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 70_033,
        base: 47_099,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 70_045,
        base: 47_103,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 70_054,
        base: 47_104,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 70_135,
        base: 47_164,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 71_392,
        base: 48_101,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 71_393,
        base: 48_102,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 71_394,
        base: 48_103,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [],
      ),
    ]
      |> list.sort(by_id),
    spell4_base: [
      base_row(id: 38_017, method: 0, weapon: 0, bar: 0, class: 1),
      base_row(id: 25_635, method: 0, weapon: 1, bar: 0, class: 2),
      base_row(id: 25_473, method: 1, weapon: 1, bar: 1, class: 2),
      base_row(id: 20_325, method: 0, weapon: 0, bar: 0, class: 7),
      base_row(id: 11_781, method: 0, weapon: 0, bar: 1, class: 7),
      base_row(id: 16_838, method: 0, weapon: 0, bar: 0, class: 7),
      base_row(id: 19_102, method: 0, weapon: 0, bar: 1, class: 3),
      base_row(id: 17_288, method: 0, weapon: 0, bar: 0, class: 3),
      base_row(id: 19_019, method: 0, weapon: 0, bar: 0, class: 3),
      base_row(id: 19_022, method: 0, weapon: 0, bar: 0, class: 3),
      base_row(id: 26_488, method: 0, weapon: 0, bar: 0, class: 3),
      base_row(id: 16_322, method: 0, weapon: 1, bar: 1, class: 4),
      base_row(id: 20_737, method: 0, weapon: 1, bar: 0, class: 4),
      base_row(id: 21_506, method: 0, weapon: 1, bar: 0, class: 4),
      base_row(id: 23_173, method: 0, weapon: 1, bar: 0, class: 5),
      base_row(id: 23_162, method: 8, weapon: 0, bar: 0, class: 5),
      base_row(id: 23_163, method: 0, weapon: 1, bar: 0, class: 5),
      base_row(id: 26_468, method: 8, weapon: 1, bar: 1, class: 2),
      base_row(id: 27_638, method: 8, weapon: 1, bar: 1, class: 7),
      base_row(id: 20_684, method: 7, weapon: 1, bar: 0, class: 7),
      base_row(id: 38_201, method: 1, weapon: 1, bar: 1, class: 4),
      base_row(id: 23_148, method: 6, weapon: 1, bar: 0, class: 5),
      base_row(id: 23_161, method: 8, weapon: 1, bar: 0, class: 5),
      base_row(id: 37_968, method: 6, weapon: 1, bar: 0, class: 1),
      base_row(id: 18_309, method: 6, weapon: 1, bar: 0, class: 1),
      base_row(id: 22_522, method: 8, weapon: 1, bar: 1, class: 2),
      base_row(id: 27_668, method: 0, weapon: 0, bar: 0, class: 7),
      base_row(id: 27_669, method: 0, weapon: 0, bar: 0, class: 7),
      base_row(id: 27_670, method: 0, weapon: 0, bar: 0, class: 7),
      base_row(id: 26_759, method: 0, weapon: 0, bar: 0, class: 4),
      base_row(id: 23_150, method: 8, weapon: 1, bar: 0, class: 5),
      base_row(id: 23_799, method: 8, weapon: 1, bar: 0, class: 5),
      base_row(id: 47_099, method: 0, weapon: 1, bar: 0, class: 1),
      base_row(id: 47_103, method: 0, weapon: 1, bar: 0, class: 1),
      base_row(id: 47_104, method: 0, weapon: 1, bar: 0, class: 1),
      base_row(id: 47_164, method: 0, weapon: 1, bar: 0, class: 1),
      base_row(id: 48_101, method: 0, weapon: 1, bar: 0, class: 1),
      base_row(id: 48_102, method: 0, weapon: 1, bar: 0, class: 1),
      base_row(id: 48_103, method: 0, weapon: 1, bar: 0, class: 1),
      base_row(id: 23_149, method: 6, weapon: 1, bar: 0, class: 5),
      base_row(id: 18_310, method: 6, weapon: 0, bar: 0, class: 1),
      base_row(id: 18_311, method: 6, weapon: 0, bar: 0, class: 1),
      base_row(id: 44_605, method: 6, weapon: 1, bar: 0, class: 1),
      base_row(id: 47_921, method: 6, weapon: 1, bar: 0, class: 1),
      base_row(id: 47_922, method: 6, weapon: 1, bar: 0, class: 1),
      base_row(id: 20_686, method: 7, weapon: 1, bar: 0, class: 7),
      base_row(id: 20_688, method: 7, weapon: 0, bar: 0, class: 7),
      base_row(id: 22_175, method: 7, weapon: 0, bar: 0, class: 7),
    ]
      |> list.sort(by_id),
    spell4_effects: [
      effect_row(
        id: 56_858,
        spell: 30_900,
        type_: 1,
        target_flags: 1,
        delay: 10,
        phases: 1,
        data: 6,
        order: 0,
      ),
      effect_row(
        id: 62_007,
        spell: 32_812,
        type_: 26,
        target_flags: 4,
        delay: 100,
        phases: 1,
        data: 42_297,
        order: 0,
      ),
      effect_row(
        id: 62_159,
        spell: 32_893,
        type_: 8,
        target_flags: 4,
        delay: 0,
        phases: -1,
        data: 1_065_353_216,
        order: 0,
      ),
      effect_row(
        id: 62_204,
        spell: 32_893,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: -1,
        data: 30_900,
        order: 1,
      ),
      effect_row(
        id: 67_778,
        spell: 34_355,
        type_: 26,
        target_flags: 1,
        delay: 200,
        phases: 1,
        data: 25_190,
        order: 2,
      ),
      effect_row(
        id: 67_779,
        spell: 34_355,
        type_: 26,
        target_flags: 1,
        delay: 140,
        phases: 1,
        data: 30_436,
        order: 3,
      ),
      effect_row(
        id: 69_881,
        spell: 29_874,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: -1,
        data: 34_775,
        order: 1,
      ),
      effect_row(
        id: 73_230,
        spell: 29_874,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: -1,
        data: 35_886,
        order: 2,
      ),
      effect_row(
        id: 83_823,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 1,
        data: 38_781,
        order: 0,
      ),
      effect_row(
        id: 83_824,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 2,
        data: 38_781,
        order: 1,
      ),
      effect_row(
        id: 83_825,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 4,
        data: 38_781,
        order: 2,
      ),
      effect_row(
        id: 83_826,
        spell: 38_780,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 8,
        data: 38_781,
        order: 3,
      ),
      effect_row(
        id: 83_829,
        spell: 38_781,
        type_: 8,
        target_flags: 2,
        delay: 0,
        phases: 1,
        data: 1_065_353_216,
        order: 0,
      ),
      effect_row(
        id: 83_853,
        spell: 38_791,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: 1,
        data: 38_780,
        order: 0,
      ),
      effect_row(
        id: 95_950,
        spell: 42_297,
        type_: 8,
        target_flags: 6,
        delay: 0,
        phases: 1,
        data: 1_065_353_216,
        order: 1,
      ),
      effect_row(
        id: 95_881,
        spell: 42_276,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: 2,
        data: 37_302,
        order: 0,
      ),
      proxy_behind_prerequisite(
        id: 196_513,
        spell: 43_468,
        phases: 2,
        data: 43_498,
        prerequisite: 17_301,
        order: 0,
      ),
      proxy_behind_prerequisite(
        id: 196_514,
        spell: 43_468,
        phases: 4,
        data: 43_499,
        prerequisite: 17_301,
        order: 1,
      ),
      proxy_behind_prerequisite(
        id: 196_515,
        spell: 43_468,
        phases: 8,
        data: 43_498,
        prerequisite: 17_301,
        order: 2,
      ),
      proxy_behind_prerequisite(
        id: 196_516,
        spell: 43_468,
        phases: 8,
        data: 43_500,
        prerequisite: 17_301,
        order: 3,
      ),
      proxy_behind_prerequisite(
        id: 196_517,
        spell: 43_468,
        phases: 2,
        data: 43_499,
        prerequisite: 17_302,
        order: 4,
      ),
      proxy_behind_prerequisite(
        id: 196_518,
        spell: 43_468,
        phases: 4,
        data: 43_498,
        prerequisite: 17_302,
        order: 5,
      ),
      proxy_behind_prerequisite(
        id: 196_519,
        spell: 43_468,
        phases: 8,
        data: 43_499,
        prerequisite: 17_302,
        order: 6,
      ),
      proxy_behind_prerequisite(
        id: 196_522,
        spell: 43_468,
        phases: 1,
        data: 43_500,
        prerequisite: 17_302,
        order: 8,
      ),
      effect_row(
        id: 173_926,
        spell: 58_832,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: -1,
        data: 80_382,
        order: 1,
      ),
      effect_row(
        id: 83_776,
        spell: 38_765,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: 1,
        data: 38_767,
        order: 0,
      ),
      effect_row(
        id: 83_782,
        spell: 38_766,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: 1,
        data: 39_467,
        order: 0,
      ),
      effect_row(
        id: 177_146,
        spell: 32_078,
        type_: 26,
        target_flags: 1,
        delay: 266,
        phases: -1,
        data: 70_033,
        order: 0,
      ),
      effect_row(
        id: 177_158,
        spell: 32_079,
        type_: 26,
        target_flags: 1,
        delay: 400,
        phases: -1,
        data: 70_045,
        order: 0,
      ),
      effect_row(
        id: 177_171,
        spell: 32_080,
        type_: 26,
        target_flags: 1,
        delay: 400,
        phases: -1,
        data: 70_054,
        order: 0,
      ),
      effect_row(
        id: 177_439,
        spell: 58_524,
        type_: 26,
        target_flags: 1,
        delay: 333,
        phases: -1,
        data: 70_135,
        order: 0,
      ),
      effect_row(
        id: 177_498,
        spell: 66_987,
        type_: 26,
        target_flags: 1,
        delay: 100,
        phases: -1,
        data: 71_392,
        order: 0,
      ),
      effect_row(
        id: 182_203,
        spell: 71_125,
        type_: 26,
        target_flags: 1,
        delay: 166,
        phases: -1,
        data: 71_393,
        order: 0,
      ),
      effect_row(
        id: 182_204,
        spell: 71_126,
        type_: 26,
        target_flags: 1,
        delay: 400,
        phases: -1,
        data: 71_394,
        order: 0,
      ),
    ]
      |> list.sort(by_id),
    spell4_thresholds: [
      threshold_row(
        id: 238,
        parent: 38_765,
        to_cast: 38_766,
        order: 0,
        duration: 0,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 9,
        parent: 32_078,
        to_cast: 32_079,
        order: 0,
        duration: 0,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 10,
        parent: 32_078,
        to_cast: 32_080,
        order: 1,
        duration: 0,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 1073,
        parent: 58_524,
        to_cast: 66_987,
        order: 0,
        duration: 0,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 1074,
        parent: 58_524,
        to_cast: 71_125,
        order: 1,
        duration: 0,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 1075,
        parent: 58_524,
        to_cast: 71_126,
        order: 2,
        duration: 0,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 125,
        parent: 34_718,
        to_cast: 34_720,
        order: 0,
        duration: 0,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 123,
        parent: 34_718,
        to_cast: 34_722,
        order: 1,
        duration: 1000,
        cost: #(0, 0),
      ),
      threshold_row(
        id: 124,
        parent: 34_718,
        to_cast: 36_691,
        order: 2,
        duration: 1400,
        cost: #(15, 0),
      ),
    ]
      |> list.sort(by_id),
    spell_phases: [
      phase_row(id: 3717, owner: 38_780, order: 0, delay: 166, flags: 0),
      phase_row(id: 3718, owner: 38_780, order: 1, delay: 200, flags: 0),
      phase_row(id: 3719, owner: 38_780, order: 2, delay: 167, flags: 0),
      phase_row(id: 3720, owner: 38_780, order: 3, delay: 167, flags: 0),
      phase_row(id: 5390, owner: 42_276, order: 0, delay: 0, flags: 0),
      phase_row(id: 5391, owner: 42_276, order: 1, delay: 1250, flags: 512),
      phase_row(id: 5882, owner: 43_468, order: 0, delay: 0, flags: 0),
      phase_row(id: 5883, owner: 43_468, order: 1, delay: 366, flags: 512),
      phase_row(id: 5884, owner: 43_468, order: 2, delay: 200, flags: 0),
      phase_row(id: 5885, owner: 43_468, order: 3, delay: 200, flags: 4),
      phase_row(id: 5886, owner: 43_468, order: 4, delay: 234, flags: 0),
      phase_row(id: 3715, owner: 38_779, order: 0, delay: 0, flags: 0),
      phase_row(id: 3716, owner: 38_779, order: 1, delay: 300, flags: 384),
      phase_row(id: 2820, owner: 37_302, order: 0, delay: 0, flags: 0),
      phase_row(id: 2821, owner: 37_302, order: 1, delay: 1, flags: 0),
      phase_row(id: 2822, owner: 37_302, order: 2, delay: 1, flags: 0),
      phase_row(id: 2823, owner: 37_302, order: 3, delay: 1, flags: 0),
      phase_row(id: 3712, owner: 38_767, order: 0, delay: 133, flags: 0),
      phase_row(id: 3713, owner: 38_767, order: 1, delay: 300, flags: 0),
      phase_row(id: 3714, owner: 38_767, order: 2, delay: 333, flags: 0),
      phase_row(id: 4032, owner: 39_467, order: 0, delay: 133, flags: 0),
      phase_row(id: 4033, owner: 39_467, order: 1, delay: 367, flags: 0),
      phase_row(id: 4034, owner: 39_467, order: 2, delay: 266, flags: 0),
    ],
    spell_cool_downs: list.map(
      [
        #(104, 1250),
        #(127, 1250),
        #(155, 750),
        #(159, 1250),
        #(180, 750),
        #(213, 1000),
        #(82, 1000),
        #(103, 500),
        #(107, 333),
        #(115, 1000),
        #(121, 750),
        #(125, 1250),
        #(146, 500),
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
      class_row(id: 5, slots: [5, 13, 13, 12, 9, 10, 11, 16]),
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
      under: owned_key.new(),
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
    spell4_thresholds.entry(),
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
    planted_table.file(spell4_thresholds.schema, rows.spell4_thresholds),
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
      under: owned_key.new(),
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

/// The plans the planted rows build, built once per run from one load of the
/// planted tables that is erased after the build; every test that reads the
/// plans of the unchanged rows takes them from here, so it puts no terms of its
/// own. A test that changes a row loads its own (`with_loaded`).
pub fn default_plans() -> spell_plan.Plans {
  database_support.once("spell_tables_default_plans", fn() {
    let assert Ok(plans) =
      with_loaded(rows: rows(), body: fn(tables) { spell_plan.build(tables:) })
      as "the planted spell rows build"
    plans
  })
}
