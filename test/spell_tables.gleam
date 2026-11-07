//// The spell tables a plan test builds from: the client's own rows, which a test
//// may change or add to (`fixture_rows`), and `with_loaded`, which loads the tables
//// the plan reads from them so that a test can take a row away or add one.
////
//// Gap: `planted_rows` plants a few abilities instead of holding the client's rows
//// (issue 326). The abilities, with what the client's rows hold:
//// - Telekinetic Strike, Spell4 32893 (class 3, base 19102): castTime 1250,
////   castBarType 1, no cooldown of its own, global cooldown kind 0 with SpellCoolDown
////   row 213 (1000 ms), a Magic damage effect and a Proxy to 30900 on the caster
////   (`Spell4.32893`).
//// - Mind Burst, 32809 (class 3, base 19019): an innate cost of type 6 (Resource1,
////   the Esper's Psi Points) of 1, kind 0, row 104 (1250 ms) (`Spell4CastResult.vital_cost`).
////   The planted row has no EMM id and no effects; the client's row holds them
////   (`Spell4.32809`).
//// - Crush, 32812 (class 3, base 19022): cooldown 35000, kind 3, and one Proxy,
////   100 ms after the go, to 42297, with the stray emmComparison 0 and emmValue 4
////   (`Spell4.32812`).
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
//// each of cast method 0 but 38780's. Each Spell4 row holds the client's caster
//// condition row (`caster_conditions`), and the three rows they name are planted
//// (`spell4_conditions_rows`).
////
//// The abilities of the cast methods, each row as `table_rows` prints it for the
//// Spell4, Spell4Base, Spell4Thresholds, SpellPhase and Spell4Effects rows of the
//// trees (Proxy effects only):
//// - Pulse Blast 42276 and Quick Draw 43468: Multiphase, SpellPhase rows 5390,
////   5391 and 5882 to 5886; Quick Draw's Proxies sit behind prerequisites 17301
////   and 17302 (`proxy_prerequisite_rows`).
//// - Impale 38779: Multiphase, SpellPhase 3715 and 3716, an innate cost of type 8.
//// - Electrocute 41276 and Discharge 58832: Channeled, the channel columns of
////   their Spell4 rows; Discharge proxies 80382 in every phase.
//// - Shred 38765, Relentless Strikes 32078 and Rampage 58524: RapidTap with a
////   thresholdTime of 4000 and the stages of Spell4Thresholds 238, 9 and 10,
////   1073 to 1075. Shred's two Proxies, 38767 and 39467, each hold one Physical
////   damage effect aimed at the area (Spell4Effects 83788 and 86439: parameters
////   12 0.0967 and 10 4.22).
//// - The gains (`Spell4Effects.effectType.1`): 56858 (+1 of vital 6) in 30900;
////   Relentless Strikes' stage spells 70033, 70045 and 70054 proxy 53865 at the
////   area (177057, 177099, 177122), which holds 127603 (+180, behind 24581),
////   147972 (+200, behind 24582) and the Proxy 177873 to 60947, whose dataBits06
////   names 24582 (`Spell4Effects.effectType.26.dataBits06`); 60947's own effect,
////   147971 of type 17, is not planted. The Prerequisite rows 24581, 24582, 43811
////   and 43812 (`gain_prerequisite_rows`).
//// - Charged Shot 34718: ChargeRelease with a thresholdTime of 8200 and the stages
////   of Spell4Thresholds 125, 123 and 124.
//// The PositionalRequirement table is planted with no row: the plan reads it for the arc of a
//// Proxy's type 108 target gate, and a test that needs one plants its Prerequisite row
//// naming a row the table lacks.

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
import owned_key
import planted_table.{type Cell, Float, Integer}

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
    #("spell4AoeTargetConstraintsId", Integer(area_id(id))),
    #("spell4ConditionsIdCaster", Integer(caster_conditions(id))),
    #("spellCastStealthChange", Integer(stealth_change(id))),
  ])
}

/// Spell4.spell4AoeTargetConstraintsId of the planted rows, as `table_rows -- Spell4
/// <id>` prints it (`Spell4.58591.area`): 0 for a spell with no area row.
fn area_id(id: Int) -> Int {
  case id {
    29_874 | 34_775 | 35_886 -> 701
    30_436 | 41_276 | 41_438 -> 411
    32_809 | 32_893 | 37_302 -> 345
    32_812 | 42_276 -> 404
    34_720 | 34_722 | 36_691 -> 407
    38_767 | 39_467 -> 694
    38_779 -> 699
    38_780 -> 299
    42_297 -> 704
    43_498 | 43_499 -> 405
    58_591 | 70_033 | 70_045 | 70_054 -> 640
    58_832 -> 173
    70_135 | 71_392 | 71_393 | 71_394 -> 342
    _ -> 0
  }
}

/// A Spell4AoeTargetConstraints row: the arc, the count of targets and the range, with
/// the order Closest (1) and no minimum range, as the client's rows of the planted
/// spells hold them.
pub fn aoe_row(
  id id: Int,
  angle angle: Float,
  count count: Int,
  max_range max_range: Float,
) -> List(Cell) {
  aoe_row_selecting(id:, angle:, count:, max_range:, selection: 1)
}

/// The same with the order the area picks its targets in (`targetSelection`).
pub fn aoe_row_selecting(
  id id: Int,
  angle angle: Float,
  count count: Int,
  max_range max_range: Float,
  selection selection: Int,
) -> List(Cell) {
  planted_table.row(spell4_aoe_target_constraints.schema, [
    #("ID", Integer(id)),
    #("angle", Float(angle)),
    #("targetCount", Integer(count)),
    #("minRange", Float(0.0)),
    #("maxRange", Float(max_range)),
    #("targetSelection", Integer(selection)),
  ])
}

/// The rows in the order of their ids, which the tables' files hold them in.
pub fn sorted_by_id(rows: List(List(Cell))) -> List(List(Cell)) {
  list.sort(rows, by_id)
}

/// Spell4.spellCastStealthChange of the planted rows, as `table_rows -- Spell4 <id>`
/// prints it (`Spell4.spellCastStealthChange`): 1 on the Stalker's attacks (Shred and its
/// Proxies, Impale, Stagger and its Multiphase child), 2 on the Stealth toggle and its
/// spells, Tactical Retreat, Stagger's phase spell 38781 and the other classes' 53865 and
/// 87353, and 0 on every other planted spell.
fn stealth_change(id: Int) -> Int {
  case id {
    38_765 | 38_766 | 38_767 | 39_467 | 38_779 | 38_780 | 38_791 -> 1
    46_073 | 38_784 | 38_913 | 38_781 | 53_865 | 87_353 -> 2
    _ -> 0
  }
}

/// Spell4.propertyFlags of the planted rows, as `table_rows -- Spell4 <id>` prints
/// them (`Spell4.propertyFlags`): 0x1 makes a press ignore a live cast.
fn property_flags(id: Int) -> Int {
  case id {
    32_893 | 29_874 | 32_809 -> 0x4000002
    58_591 -> 0x4000102
    41_438 -> 0x4000103
    34_355 -> 0x3
    69_450 -> 0x1
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
    38_784 | 38_913 -> 0x400
    34_722 | 36_691 -> 0x3
    37_302 -> 0x4220002
    80_382 | 53_865 -> 0x100000
    43_498 | 43_499 -> 0x4000000
    70_033 | 70_045 | 70_054 | 70_135 | 71_392 | 71_393 | 71_394 -> 0x4000002
    _ -> 0
  }
}

/// Spell4.spell4ConditionsIdCaster of the planted rows and of the novice tables'
/// spells, as `table_rows -- Spell4 <id>` prints it
/// (`Spell4.spell4ConditionsIdCaster`): 43 for the abilities and most stages, 1
/// for 34355, the creature attack 5649, 57030 and most children, 4 for 30900, 42297
/// and 87353, and none (0) for 60947.
pub fn caster_conditions(id: Int) -> Int {
  case id {
    30_900 | 42_148 | 42_297 | 87_353 -> 4
    60_947 -> 0
    25_190
    | 53_865
    | 30_436
    | 34_355
    | 34_775
    | 35_886
    | 37_302
    | 38_766
    | 38_767
    | 38_780
    | 38_781
    | 39_467
    | 43_498
    | 43_499
    | 43_500
    | 5649
    | 57_030
    | 70_033
    | 70_045
    | 70_054
    | 70_135
    | 71_392
    | 71_393
    | 71_394
    | 80_382
    | 46_073
    | 38_784
    | 38_783
    | 38_913
    | 38_914 -> 1
    _ -> 43
  }
}

/// The planted Spell4Conditions rows the planted spells name, each the client's
/// (`table_rows -- Spell4Conditions`): 1 (mask 225, value 0) and 43 (mask 1249,
/// value 0), each with the dead bit, 15 (mask 129, the target row of the Stealth
/// spells) and 4 (mask 0), with none.
pub fn spell4_conditions_rows() -> List(List(Cell)) {
  spell4_conditions_rows_of(masks: [#(1, 225), #(4, 0), #(15, 129), #(43, 1249)])
}

/// Spell4Conditions rows, each its id and its conditionMask, with value 0.
pub fn spell4_conditions_rows_of(
  masks masks: List(#(Int, Int)),
) -> List(List(Cell)) {
  list.map(masks, fn(row) {
    planted_table.row(spell4_conditions.schema, [
      #("ID", Integer(row.0)),
      #("conditionMask", Integer(row.1)),
      #("conditionValue", Integer(0)),
    ])
  })
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
    #("spell4ValidTargetId", Integer(1)),
  ])
}

/// A Spell4ValidTargets row 1, which every planted base names: the targets a spell
/// may strike (`Spell4ValidTargets.targetBitmask`; the client's row 1 holds 0, the
/// alive).
pub fn valid_targets_row(bitmask bitmask: Int) -> List(Cell) {
  planted_table.row(spell4_valid_targets.schema, [
    #("ID", Integer(1)),
    #("targetBitmask", Integer(bitmask)),
  ])
}

/// A Spell4Effects row of a damage effect (type 8): its damage type, the unit it aims
/// at, its delay, its multiplier as 32 float bits and the formula's parameters as
/// type and value pairs, in every phase.
pub fn damage_effect_row(
  id id: Int,
  spell spell: Int,
  damage_type damage_type: Int,
  target_flags target_flags: Int,
  delay delay: Int,
  multiplier_bits multiplier_bits: Int,
  parameters parameters: List(#(Int, Float)),
) -> List(Cell) {
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(spell)),
    #("targetFlags", Integer(target_flags)),
    #("effectType", Integer(8)),
    #("damageType", Integer(damage_type)),
    #("delayTime", Integer(delay)),
    #("phaseFlags", Integer(-1)),
    #("dataBits00", Integer(multiplier_bits)),
    ..list.flatten(
      list.index_map(parameters, fn(parameter, index) {
        let number = int.to_string(index)
        [
          #("parameterType0" <> number, Integer(parameter.0)),
          #("parameterValue0" <> number, Float(parameter.1)),
        ]
      }),
    )
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

/// A Proxy effect aimed at the caster whose dataBits06 names a prerequisite
/// (`Spell4Effects.effectType.26.dataBits06`), with no apply prerequisite.
pub fn proxy_by_data_bits06(
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
    #("dataBits06", Integer(prerequisite)),
    #("orderIndex", Integer(order)),
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

/// A LevelUpUnlock row of the Level system (levelUpUnlockSystemEnum 0): the level
/// at which it is offered.
pub fn level_up_unlock_row(id id: Int, level level: Int) -> List(Cell) {
  planted_table.row(level_up_unlock.schema, [
    #("ID", Integer(id)),
    #("levelUpUnlockSystemEnum", Integer(0)),
    #("level", Integer(level)),
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

/// The Prerequisite rows the planted Proxies name in their caster apply column,
/// each the client's (`table_rows -- Prerequisite 17301 17302`): Quick Draw's, not
/// under the cast 43500 and under it.
pub fn proxy_prerequisite_rows() -> List(List(Cell)) {
  [
    prerequisite_row(id: 17_301, flags: 0, conditions: [#(15, 2, 0, 43_500)]),
    prerequisite_row(id: 17_302, flags: 0, conditions: [#(15, 1, 0, 43_500)]),
  ]
}

/// The Prerequisite rows the planted gains name, each the client's (`table_rows --
/// Prerequisite 24581 24582 43811 43812`).
pub fn gain_prerequisite_rows() -> List(List(Cell)) {
  [
    prerequisite_row(id: 24_581, flags: 0, conditions: [
      #(15, 2, 0, 42_908),
      #(0, 2, 0, 60_947),
    ]),
    prerequisite_row(id: 24_582, flags: 0, conditions: [
      #(15, 2, 0, 42_908),
      #(15, 2, 0, 60_947),
      #(15, 1, 0, 59_208),
    ]),
    prerequisite_row(id: 43_811, flags: 0, conditions: [#(15, 2, 732, 58_999)]),
    prerequisite_row(id: 43_812, flags: 0, conditions: [#(15, 1, 0, 58_999)]),
  ]
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
    #("spell4ConditionsIdCaster", Integer(caster_conditions(id))),
    #("spellCastStealthChange", Integer(stealth_change(id))),
    ..list.map(more, fn(column) { #(column.0, Integer(column.1)) })
  ])
}

fn class_row(
  id id: Int,
  slots slots: List(Int),
  more more: List(#(String, Int)),
) -> List(Cell) {
  planted_table.row(class.schema, [
    #("ID", Integer(id)),
    ..list.append(
      list.index_map(slots, fn(vital, slot) {
        #("vitalEnumResource0" <> int.to_string(slot), Integer(vital))
      }),
      list.map(more, fn(column) { #(column.0, Integer(column.1)) }),
    )
  ])
}

/// The six playable classes with their Class.startingItemProficiencies, which
/// message 0x025E carries (`table_rows -- Class 1 2 3 4 5 7`): Warrior 18,
/// Engineer 66, Esper 262152, Medic 260, Stalker 1048580 and Spellslinger 4104.
pub fn class_proficiencies() -> List(#(Int, Int)) {
  [
    #(1, 18),
    #(2, 66),
    #(3, 262_152),
    #(4, 260),
    #(5, 1_048_580),
    #(7, 4104),
  ]
}

/// The Class column of a playable class's item proficiencies, from
/// `class_proficiencies`.
fn proficiency(class_id class_id: Int) -> #(String, Int) {
  let assert Ok(mask) = list.key_find(class_proficiencies(), class_id)
    as "the six playable classes have a proficiency"
  #("startingItemProficiencies", mask)
}

/// The planted rows of the abilities above and their children.
/// Gap: these rows are planted, not the client's (issue 326).
pub fn planted_rows() -> Rows {
  Rows(
    spell4_conditions: spell4_conditions_rows(),
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
        id: 53_865,
        base: 35_316,
        cast_time: 0,
        cooldown: 0,
        range: 99.0,
        cost: #(0, 0),
        kind: 3,
        global: 100,
      ),
      spell4_row(
        id: 60_947,
        base: 39_233,
        cast_time: 0,
        cooldown: 0,
        range: 0.0,
        cost: #(0, 0),
        kind: 3,
        global: 0,
      ),
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
        more: [
          #("thresholdTime", 4000),
          #("casterInnateRequirement0", 6),
          #("casterInnateRequirementValue0", 250),
          #("casterInnateRequirementEval0", 2),
          #("prerequisiteIdCasterCast", 19_750),
        ],
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
        more: [#("spell4AoeTargetConstraintsId", 694)],
      ),
      method_spell_row(
        id: 39_467,
        base: 23_799,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 100,
        cost: #(0, 0),
        more: [#("spell4AoeTargetConstraintsId", 694)],
      ),
      method_spell_row(
        id: 70_033,
        base: 47_099,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [#("spell4AoeTargetConstraintsId", area_id(70_033))],
      ),
      method_spell_row(
        id: 70_045,
        base: 47_103,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [#("spell4AoeTargetConstraintsId", area_id(70_045))],
      ),
      method_spell_row(
        id: 70_054,
        base: 47_104,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 121,
        cost: #(0, 0),
        more: [#("spell4AoeTargetConstraintsId", area_id(70_054))],
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
      base_row(id: 35_316, method: 0, weapon: 0, bar: 0, class: 1),
      base_row(id: 39_233, method: 0, weapon: 0, bar: 0, class: 1),
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
      vital_modifier_row(
        id: 56_858,
        spell: 30_900,
        vital: 6,
        amount: 1,
        delay: 10,
        phases: 1,
        prerequisite: 0,
        order: 0,
      ),
      vital_modifier_row(
        id: 127_603,
        spell: 53_865,
        vital: 6,
        amount: 180,
        delay: 10,
        phases: 1,
        prerequisite: 24_581,
        order: 0,
      ),
      vital_modifier_row(
        id: 147_972,
        spell: 53_865,
        vital: 6,
        amount: 200,
        delay: 10,
        phases: 1,
        prerequisite: 24_582,
        order: 1,
      ),
      proxy_by_data_bits06(
        id: 177_873,
        spell: 53_865,
        phases: -1,
        data: 60_947,
        prerequisite: 24_582,
        order: 2,
      ),
      effect_row(
        id: 177_057,
        spell: 70_033,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 1,
        data: 53_865,
        order: 1,
      ),
      effect_row(
        id: 177_099,
        spell: 70_045,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 1,
        data: 53_865,
        order: 1,
      ),
      effect_row(
        id: 177_122,
        spell: 70_054,
        type_: 26,
        target_flags: 4,
        delay: 0,
        phases: 1,
        data: 53_865,
        order: 1,
      ),
      planted_table.row(spell4_effects.schema, [
        #("ID", Integer(62_007)),
        #("spellId", Integer(32_812)),
        #("targetFlags", Integer(4)),
        #("effectType", Integer(26)),
        #("delayTime", Integer(100)),
        #("phaseFlags", Integer(1)),
        #("dataBits00", Integer(42_297)),
        #("emmComparison", Integer(0)),
        #("emmValue", Integer(4)),
        #("orderIndex", Integer(0)),
      ]),
      damage_effect_row(
        id: 62_159,
        spell: 32_893,
        damage_type: 3,
        target_flags: 4,
        delay: 0,
        multiplier_bits: 1_065_353_216,
        parameters: [#(12, 0.335999995470047), #(10, 18.0)],
      ),
      damage_effect_row(
        id: 83_788,
        spell: 38_767,
        damage_type: 1,
        target_flags: 4,
        delay: 0,
        multiplier_bits: 1_065_353_216,
        parameters: [#(12, 0.09669999778270721), #(10, 4.21999979019165)],
      ),
      damage_effect_row(
        id: 86_439,
        spell: 39_467,
        damage_type: 1,
        target_flags: 4,
        delay: 0,
        multiplier_bits: 1_065_353_216,
        parameters: [#(12, 0.09669999778270721), #(10, 4.21999979019165)],
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
    spell4_aoe_target_constraints: [
      aoe_row(id: 173, angle: 180.0, count: 5, max_range: 15.0),
      aoe_row(id: 299, angle: 360.0, count: 5, max_range: 8.0),
      aoe_row(id: 342, angle: 180.0, count: 3, max_range: 8.0),
      aoe_row(id: 345, angle: 360.0, count: 5, max_range: 30.0),
      aoe_row(id: 404, angle: 360.0, count: 1, max_range: 25.0),
      aoe_row(id: 405, angle: 360.0, count: 3, max_range: 25.0),
      aoe_row(id: 407, angle: 360.0, count: 5, max_range: 35.0),
      aoe_row(id: 411, angle: 360.0, count: 5, max_range: 25.0),
      aoe_row(id: 640, angle: 180.0, count: 5, max_range: 8.0),
      aoe_row(id: 694, angle: 360.0, count: 5, max_range: 6.5),
      aoe_row(id: 699, angle: 360.0, count: 2, max_range: 7.0),
      aoe_row(id: 701, angle: 180.0, count: 2, max_range: 25.0),
      aoe_row(id: 704, angle: 360.0, count: 4, max_range: 4.0),
    ],
    spell4_valid_targets: [valid_targets_row(bitmask: 0)],
    spell4_telegraph: list.map(
      [#(118, 133), #(401, 125), #(4069, 2169)],
      fn(link) {
        planted_table.row(spell4_telegraph.schema, [
          #("ID", Integer(link.0)),
          #("spell4Id", Integer(32_893)),
          #("telegraphDamageId", Integer(link.1)),
        ])
      },
    ),
    telegraph_damage: list.map(
      [#(125, 1568, 15), #(133, 4640, 14), #(2169, 64, 0)],
      fn(row) {
        planted_table.row(telegraph_damage.schema, [
          #("ID", Integer(row.0)),
          #("damageShapeEnum", Integer(7)),
          #("param00", Float(3.0)),
          #("param01", Float(20.0)),
          #("param02", Float(29.0)),
          #("zPositionOffset", Float(1.0)),
          #("telegraphDamageFlags", Integer(row.1)),
          #("targetTypeFlags", Integer(1)),
          #("displayFlags", Integer(row.2)),
        ])
      },
    ),
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
      class_row(id: 3, slots: [5, 0, 0, 0, 0, 0, 0, 16], more: [
        proficiency(class_id: 3),
      ]),
      class_row(id: 4, slots: [5, 18, 18, 18, 18, 18, 0, 16], more: [
        proficiency(class_id: 4),
      ]),
      class_row(id: 5, slots: [5, 13, 13, 12, 9, 10, 11, 16], more: [
        proficiency(class_id: 5),
      ]),
    ],
    prerequisites: sorted_by_id(
      list.flatten([
        proxy_prerequisite_rows(),
        gain_prerequisite_rows(),
        waiver_prerequisite_rows(),
      ]),
    ),
    spell4_group_lists: [],
    spell4_stack_groups: [],
    unit_properties: unit_property_rows(),
    eldan_augmentations: [],
    level_up_unlocks: [level_up_unlock_row(id: 26, level: 10)],
    positional_requirements: [],
  )
}

/// The UnitProperty2 defaults of the properties the server's rules and plans name, the
/// client's (`table_rows -- UnitProperty2 7 8 35 36 41 42 44 47 60 100 102 104 127 134
/// 175 177`): BaseHealth 1.0, HealthRegenMultiplier 1.0, AssaultRating 0.0, SupportRating
/// 0.0, ShieldCapacityMax 0.0, Armor 0.0, InterruptArmor_Threshold 0.0,
/// RatingCritSeverityIncrease 0.0, RatingMultiHitAmount 0.0, MoveSpeedMultiplier 1.0,
/// BaseCritChance 0.0, BaseAvoidReduceChance 0.0, CriticalHitSeverityMultiplier 1.5,
/// FallingDamageMultiplier 1.0, ShieldMitigationMax 0.0 and ShieldTickTime 500.0.
pub fn unit_property_defaults() -> List(#(Int, Float)) {
  [
    #(7, 1.0),
    #(8, 1.0),
    #(35, 0.0),
    #(36, 0.0),
    #(41, 0.0),
    #(42, 0.0),
    #(44, 0.0),
    #(47, 0.0),
    #(60, 0.0),
    #(100, 1.0),
    #(102, 0.0),
    #(104, 0.0),
    #(127, 1.5),
    #(134, 1.0),
    #(175, 0.0),
    #(177, 500.0),
  ]
}

/// The planted UnitProperty2 rows of `unit_property_defaults`, with these defaults in
/// place of the client's for the ids named.
pub fn unit_property_rows_with(
  replacing replacing: List(#(Int, Float)),
) -> List(List(Cell)) {
  list.map(unit_property_defaults(), fn(property) {
    let default = case list.key_find(replacing, property.0) {
      Ok(replacement) -> replacement
      Error(Nil) -> property.1
    }
    planted_table.row(unit_property2.schema, [
      #("ID", Integer(property.0)),
      #("defaultValue", Float(default)),
    ])
  })
}

/// The planted UnitProperty2 rows with the client's defaults.
pub fn unit_property_rows() -> List(List(Cell)) {
  unit_property_rows_with(replacing: [])
}

/// The Prerequisite rows the planted spells' cast columns name, each the client's.
pub fn waiver_prerequisite_rows() -> List(List(Cell)) {
  [
    prerequisite_row(id: 19_750, flags: 0, conditions: [#(15, 1, 0, 42_908)]),
  ]
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
  let files = files_with_the_fixtures_others(rows:)
  use folder <- planted_table.in_folder(files)
  case
    table_store.load(
      under: owned_key.new(),
      from: folder,
      entries: entries_with_the_servers_others(),
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

/// The server's tables other than the spell tables, which the spell rows name, so
/// that a load of those rows needs them.
fn entries_with_the_servers_others() -> List(table_store.Entry) {
  let spell_tables =
    list.map(entries(), fn(entry) { table_store.schema(entry).table })
  list.append(
    entries(),
    list.filter(server_table.entries(), fn(entry) {
      !list.contains(spell_tables, table_store.schema(entry).table)
    }),
  )
}

/// The files of these rows and of the server's other tables, which are the client's.
fn files_with_the_fixtures_others(
  rows rows: Rows,
) -> List(#(String, BitArray)) {
  let spell_tables =
    list.map(entries(), fn(entry) { table_store.schema(entry).table })
  let held = fixture_tables.rows()
  list.append(
    files_of(rows:),
    list.filter_map(server_table.entries(), fn(entry) {
      let schema = table_store.schema(entry)
      case list.contains(spell_tables, schema.table) {
        True -> Error(Nil)
        False ->
          Ok(planted_table.file(
            schema,
            result.unwrap(dict.get(held, schema.table), []),
          ))
      }
    }),
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

fn files_of(rows rows: Rows) -> List(#(String, BitArray)) {
  [
    planted_table.file(spell_level.schema, rows.spell_levels),
    planted_table.file(spell4.schema, rows.spell4),
    planted_table.file(spell4_base.schema, rows.spell4_base),
    planted_table.file(spell4_conditions.schema, rows.spell4_conditions),
    planted_table.file(spell4_effects.schema, rows.spell4_effects),
    planted_table.file(spell4_group_list.schema, rows.spell4_group_lists),
    planted_table.file(spell4_stack_group.schema, rows.spell4_stack_groups),
    planted_table.file(spell4_thresholds.schema, rows.spell4_thresholds),
    planted_table.file(
      spell4_aoe_target_constraints.schema,
      rows.spell4_aoe_target_constraints,
    ),
    planted_table.file(spell4_valid_targets.schema, rows.spell4_valid_targets),
    planted_table.file(spell4_telegraph.schema, rows.spell4_telegraph),
    planted_table.file(telegraph_damage.schema, rows.telegraph_damage),
    planted_table.file(spell_phase.schema, rows.spell_phases),
    planted_table.file(spell_cool_down.schema, rows.spell_cool_downs),
    planted_table.file(class.schema, rows.classes),
    planted_table.file(prerequisite.schema, rows.prerequisites),
    planted_table.file(
      positional_requirement.schema,
      rows.positional_requirements,
    ),
    planted_table.file(unit_property2.schema, rows.unit_properties),
    planted_table.file(eldan_augmentation.schema, rows.eldan_augmentations),
    planted_table.file(level_up_unlock.schema, rows.level_up_unlocks),
  ]
}

/// The planted tables the plan reads, loaded from these rows under a key of
/// their own, for the body to run on; unloaded afterwards.
pub fn with_loaded(
  rows rows: Rows,
  body body: fn(table_store.Tables) -> a,
) -> a {
  with_loaded_deriving(rows:, derivations: [], body:)
}

/// The same with these derivations run on the load, which fails when one does.
pub fn with_loaded_deriving(
  rows rows: Rows,
  derivations derivations: List(table_store.Derivation),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let files = files_with_the_fixtures_others(rows:)
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) =
    table_store.load(
      under: owned_key.new(),
      from: folder,
      entries: entries_with_the_servers_others(),
      requirements: [],
      derivations:,
    )
    as "the planted spell tables load"
  let result = body(tables)
  table_store.unload(tables)
  result
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
    list.map(spell.shield_heals, fn(heal) { heal.effect_id.value }),
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
  with_loaded(rows:, body: fn(tables) {
    case spell_plan.build(tables:) {
      Ok(plans) -> {
        let assert Ok(spell) =
          spell_plan.in_plans(plans:, base: id.Spell4BaseId(strike_base))
          as "the plans hold Telekinetic Strike"
        Ok(spell)
      }
      Error(error) -> Error(error)
    }
  })
}

/// The client's rows of the tables the plan reads, which a test may change or add
/// to before `with_loaded` loads them. The coverage walk's two tables are not server
/// tables: EldanAugmentation is empty and LevelUpUnlock holds the one row the walk's
/// gates read.
pub fn fixture_rows() -> Rows {
  // LevelUpUnlock row 26 is the client's (level 10): `table_rows -- LevelUpUnlock 26`.
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
  let rows = fixture_rows()
  Rows(
    ..rows,
    spell4: list.map(rows.spell4, fn(row) {
      case row {
        [Integer(32_893), ..] ->
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

/// The areas the client's rows build, built once.
pub fn fixture_areas() -> spell_area.Areas {
  database_support.once("spell_tables_fixture_areas", fn() {
    let assert Ok(areas) = spell_area.build(tables: fixture_tables.shared())
      as "the fixture's spell rows build their areas"
    areas
  })
}

// The Engineer's Volatility gain as the client holds it (`Spell4.42148`): the hidden
// spell 42148 (base 26342, cast time 0, caster condition row 4), its one effect 95337
// (a VitalModifier of vital 6, +15, phaseFlags 1, behind prerequisite 903) and
// Prerequisite 903 (type 28, comparison 1: the caster is in combat,
// `Prerequisite.prerequisiteTypeId.28`). Nothing in the client's tables casts 42148,
// so no Proxy of the planted rows names it. Pulse Blast's damage spell 37302 holds its
// damage as the client's rows do (`table_rows -- Spell4Effects spellId=37302`,
// `-- Spell4Telegraph spell4Id=37302`, `-- TelegraphDamage 213 217 218`): three
// Physical effects aimed at the area in its goes 1, 2 and 3 (phaseFlags 2, 4 and 8),
// each with a cone of its own. Pulse Blast 42276 holds no CasterPersistence, as the
// client's row has none.

/// The planted rows with the Engineer's Volatility gain and Pulse Blast's damage
/// spell.
/// Gap: these rows are planted, not the client's (issue 326).
pub fn planted_rows_with_volatility() -> Rows {
  let rows = planted_rows()
  Rows(
    ..rows,
    spell4: sorted_by_id([
      method_spell_row(
        id: 42_148,
        base: 26_342,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 100,
        cost: #(0, 0),
        more: [],
      ),
      ..list.map(rows.spell4, fn(row) {
        case row {
          [Integer(37_302), ..] ->
            with_column(
              row:,
              name: "spell4AoeTargetConstraintsId",
              cell: Integer(area_id(37_302)),
            )
          other -> other
        }
      })
    ]),
    spell4_base: sorted_by_id([
      base_row(id: 26_342, method: 0, weapon: 0, bar: 0, class: 0),
      ..rows.spell4_base
    ]),
    spell4_effects: sorted_by_id([
      vital_modifier_row(
        id: 95_337,
        spell: 42_148,
        vital: 6,
        amount: 15,
        delay: 0,
        phases: 1,
        prerequisite: 903,
        order: 0,
      ),
      pulse_blast_damage_row(
        id: 79_090,
        phases: 2,
        order: 0,
        scale: 0.3493,
        flat: 11.07,
      ),
      pulse_blast_damage_row(
        id: 79_092,
        phases: 4,
        order: 1,
        scale: 0.2898,
        flat: 9.18,
      ),
      pulse_blast_damage_row(
        id: 79_093,
        phases: 8,
        order: 2,
        scale: 0.2342,
        flat: 7.42,
      ),
      ..rows.spell4_effects
    ]),
    prerequisites: sorted_by_id([
      prerequisite_row(id: 903, flags: 0, conditions: [#(28, 1, 0, 0)]),
      ..rows.prerequisites
    ]),
    spell4_telegraph: list.append(
      rows.spell4_telegraph,
      list.map([#(2566, 213), #(2569, 217), #(2570, 218)], fn(link) {
        planted_table.row(spell4_telegraph.schema, [
          #("ID", Integer(link.0)),
          #("spell4Id", Integer(37_302)),
          #("telegraphDamageId", Integer(link.1)),
        ])
      }),
    ),
    telegraph_damage: list.append(
      rows.telegraph_damage,
      list.map(
        [
          #(213, 5.0, 29.0, 10.0, 2),
          #(217, 4.0, 18.0, 30.0, 4),
          #(218, 3.0, 13.0, 60.0, 8),
        ],
        fn(row) {
          planted_table.row(telegraph_damage.schema, [
            #("ID", Integer(row.0)),
            #("damageShapeEnum", Integer(8)),
            #("param00", Float(row.1)),
            #("param01", Float(row.2)),
            #("param02", Float(row.3)),
            #("param04", Float(20.0)),
            #("telegraphDamageFlags", Integer(576)),
            #("targetTypeFlags", Integer(1)),
            #("phaseFlags", Integer(row.4)),
          ])
        },
      ),
    ),
  )
}

/// A Physical damage effect of Pulse Blast's damage spell 37302 aimed at the area, in the
/// go `phases` names, with the client's two parameters (types 12 and 10).
fn pulse_blast_damage_row(
  id id: Int,
  phases phases: Int,
  order order: Int,
  scale scale: Float,
  flat flat: Float,
) -> List(Cell) {
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(37_302)),
    #("targetFlags", Integer(4)),
    #("effectType", Integer(8)),
    #("damageType", Integer(1)),
    #("phaseFlags", Integer(phases)),
    #("dataBits00", Integer(1_065_353_216)),
    #("parameterType00", Integer(12)),
    #("parameterValue00", Float(scale)),
    #("parameterType01", Integer(10)),
    #("parameterValue01", Float(flat)),
    #("orderIndex", Integer(order)),
  ])
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
