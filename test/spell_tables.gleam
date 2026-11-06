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
////   `rows` holds it without its EMM id and effects; `rows_with_mind_burst_spend`
////   holds them as the client's rows do (`Spell4.32809`).
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

import database_support
import genesis_prime/game/spell_plan
import genesis_prime/table/class
import genesis_prime/table/loader/store as table_store
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
    30_900 | 42_297 | 87_353 -> 4
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
    | 80_382 -> 1
    _ -> 43
  }
}

/// The planted Spell4Conditions rows the planted spells name, each the client's
/// (`table_rows -- Spell4Conditions`): 1 (mask 225, value 0) and 43 (mask 1249,
/// value 0), each with the dead bit, and 4 (mask 0), with none.
pub fn spell4_conditions_rows() -> List(List(Cell)) {
  spell4_conditions_rows_of(masks: [#(1, 225), #(4, 0), #(43, 1249)])
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
      class_row(id: 3, slots: [5, 0, 0, 0, 0, 0, 0, 16]),
      class_row(id: 4, slots: [5, 18, 18, 18, 18, 18, 0, 16]),
      class_row(id: 5, slots: [5, 13, 13, 12, 9, 10, 11, 16]),
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
  )
}

/// The UnitProperty2 defaults of the properties the server's rules and plans name, the
/// client's (`table_rows -- UnitProperty2 7 8 35 36 41 42 100 102 104 127 134 175
/// 177`): BaseHealth 1.0, HealthRegenMultiplier 1.0, AssaultRating 0.0, SupportRating
/// 0.0, ShieldCapacityMax 0.0, Armor 0.0, MoveSpeedMultiplier 1.0, BaseCritChance 0.0,
/// BaseAvoidReduceChance 0.0, CriticalHitSeverityMultiplier 1.5,
/// FallingDamageMultiplier 1.0, ShieldMitigationMax 0.0 and ShieldTickTime 500.0.
pub fn unit_property_defaults() -> List(#(Int, Float)) {
  [
    #(7, 1.0),
    #(8, 1.0),
    #(35, 0.0),
    #(36, 0.0),
    #(41, 0.0),
    #(42, 0.0),
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

/// The Prerequisite row Rampage's caster cast column names, the client's
/// (`table_rows -- Prerequisite 19750`): type 15, comparison 1, value 42908.
fn waiver_prerequisite_rows() -> List(List(Cell)) {
  [prerequisite_row(id: 19_750, flags: 0, conditions: [#(15, 1, 0, 42_908)])]
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
    class.entry(),
    unit_property2.entry(),
  ]
}

fn files_of(rows rows: Rows) -> List(#(String, BitArray)) {
  [
    planted_table.file(spell_level.schema, rows.spell_levels),
    planted_table.file(spell4.schema, rows.spell4),
    planted_table.file(spell4_base.schema, rows.spell4_base),
    planted_table.file(spell4_conditions.schema, spell4_conditions_rows()),
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
    planted_table.file(unit_property2.schema, rows.unit_properties),
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
  let files = files_of(rows:)
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) =
    table_store.load(
      under: owned_key.new(),
      from: folder,
      entries: entries(),
      requirements: [],
      derivations:,
    )
    as "the planted spell tables load"
  let result = body(tables)
  table_store.unload(tables)
  result
}

/// The planted rows with Energize, 69450, as a level-1 ability of the Medic. The
/// SpellLevel row 99418 is test data, not the client's: the client holds no
/// SpellLevel row for 69450 (`table_rows -- SpellLevel spell4Id=69450`), which only
/// 78462 reaches, by an effect of type 137. Its Spell4, Spell4Base and VitalModifier
/// rows are the client's (`table_rows -- Spell4 69450`, `-- Spell4Base 46615`,
/// `-- Spell4Effects spellId=69450`); its effects of types 11 and 118 and its
/// Proxies 228915 and 228917, behind prerequisites, are not planted.
pub fn rows_with_energize() -> Rows {
  let rows = rows()
  Rows(
    ..rows,
    spell_levels: [
      planted_table.row(spell_level.schema, [
        #("ID", Integer(99_418)),
        #("classId", Integer(4)),
        #("characterLevel", Integer(1)),
        #("prerequisiteId", Integer(0)),
        #("spell4Id", Integer(69_450)),
      ]),
      ..rows.spell_levels
    ],
    spell4: sorted_by_id([
      method_spell_row(
        id: 69_450,
        base: 46_615,
        cast_time: 0,
        cooldown: 30_000,
        kind: 3,
        global: 0,
        cost: #(0, 0),
        more: [],
      ),
      ..rows.spell4
    ]),
    spell4_base: sorted_by_id([
      planted_table.row(spell4_base.schema, [
        #("ID", Integer(46_615)),
        #("classIdPlayer", Integer(4)),
        #("spell4ValidTargetId", Integer(1)),
      ]),
      ..rows.spell4_base
    ]),
    spell4_effects: sorted_by_id([
      vital_modifier_row(
        id: 228_910,
        spell: 69_450,
        vital: 6,
        amount: 4,
        delay: 0,
        phases: -1,
        prerequisite: 43_811,
        order: 0,
      ),
      vital_modifier_row_with(
        id: 228_918,
        spell: 69_450,
        vital: 6,
        amount: 1,
        delay: 0,
        phases: -1,
        prerequisite: 43_812,
        order: 7,
        more: [#("tickTime", 2000), #("durationTime", 8000)],
      ),
      ..rows.spell4_effects
    ]),
  )
}

/// The Mind Burst damage effects of the client's rows (`table_rows -- Spell4Effects
/// spellId=32809`): 61993 to 61997, each of emmComparison 0 and emmValue 0 to 4, aimed
/// at the area (targetFlags 4).
pub const mind_burst_damage = [
  #(0, 0, 4),
  #(0, 1, 4),
  #(0, 2, 4),
  #(0, 3, 4),
  #(0, 4, 4),
]

/// The planted rows with Mind Burst as the client's rows hold its spend (Spell4 32809:
/// innateCostEMMId0 4 on a cost of type 6 and 1, `Spell4.32809`), with `emm_id` and
/// `cost` as a test changes them: its damage effects 61993 onwards, one for each of
/// `damage` as (emmComparison, emmValue, targetFlags), the Fluff 95008 of type 17,
/// the Proxy 135961 to 57030 (emmComparison 0, emmValue 4, dataBits06 23344) and the
/// Proxy 230116 to 87353 (emmComparison 1, emmValue 2, caster apply prerequisite
/// 44174). The two children's Spell4 and Spell4Base rows and the two prerequisites
/// are the client's too (`table_rows -- Spell4 57030 87353`, `-- Prerequisite 23344
/// 44174`); their own effects are not planted.
pub fn rows_with_mind_burst_spend(
  emm_id emm_id: Int,
  cost cost: #(Int, Int),
  damage damage: List(#(Int, Int, Int)),
) -> Rows {
  let rows = rows()
  Rows(
    ..rows,
    spell4: sorted_by_id([
      method_spell_row(
        id: 32_809,
        base: 19_019,
        cast_time: 0,
        cooldown: 0,
        kind: 0,
        global: 104,
        cost:,
        more: [
          #("innateCostEMMId0", emm_id),
          #("spell4AoeTargetConstraintsId", area_id(32_809)),
        ],
      ),
      method_spell_row(
        id: 57_030,
        base: 36_649,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 0,
        cost: #(0, 0),
        more: [],
      ),
      method_spell_row(
        id: 87_353,
        base: 62_440,
        cast_time: 0,
        cooldown: 0,
        kind: 3,
        global: 100,
        cost: #(0, 0),
        more: [],
      ),
      ..planted_table.without(rows: rows.spell4, ids: [32_809])
    ]),
    spell4_base: sorted_by_id([
      base_row(id: 36_649, method: 0, weapon: 0, bar: 0, class: 3),
      base_row(id: 62_440, method: 0, weapon: 0, bar: 0, class: 3),
      ..rows.spell4_base
    ]),
    spell4_effects: sorted_by_id(
      list.flatten([
        list.index_map(damage, fn(tag, index) {
          mind_burst_damage_row(
            id: 61_993 + index,
            comparison: tag.0,
            value: tag.1,
            target_flags: tag.2,
            order: index,
          )
        }),
        [
          planted_table.row(spell4_effects.schema, [
            #("ID", Integer(95_008)),
            #("spellId", Integer(32_809)),
            #("targetFlags", Integer(1)),
            #("effectType", Integer(17)),
            #("phaseFlags", Integer(-1)),
            #("orderIndex", Integer(5)),
          ]),
          planted_table.row(spell4_effects.schema, [
            #("ID", Integer(135_961)),
            #("spellId", Integer(32_809)),
            #("targetFlags", Integer(1)),
            #("effectType", Integer(26)),
            #("phaseFlags", Integer(-1)),
            #("dataBits00", Integer(57_030)),
            #("dataBits06", Integer(23_344)),
            #("emmComparison", Integer(0)),
            #("emmValue", Integer(4)),
            #("orderIndex", Integer(6)),
          ]),
          planted_table.row(spell4_effects.schema, [
            #("ID", Integer(230_116)),
            #("spellId", Integer(32_809)),
            #("targetFlags", Integer(1)),
            #("effectType", Integer(26)),
            #("phaseFlags", Integer(-1)),
            #("dataBits00", Integer(87_353)),
            #("prerequisiteIdCasterApply", Integer(44_174)),
            #("emmComparison", Integer(1)),
            #("emmValue", Integer(2)),
            #("orderIndex", Integer(8)),
          ]),
        ],
        rows.spell4_effects,
      ]),
    ),
    prerequisites: sorted_by_id([
      prerequisite_row(id: 23_344, flags: 0, conditions: [#(50, 1, 0, 57_027)]),
      prerequisite_row(id: 44_174, flags: 1, conditions: [
        #(15, 1, 0, 87_333),
        #(15, 1, 0, 87_334),
      ]),
      ..rows.prerequisites
    ]),
  )
}

/// One Mind Burst damage effect: Magic damage (damageType 3) of phase 1 with the
/// multiplier 1.0 and the formula the row of its emmValue holds (`table_rows --
/// Spell4Effects spellId=32809`), with the emm columns given.
fn mind_burst_damage_row(
  id id: Int,
  comparison comparison: Int,
  value value: Int,
  target_flags target_flags: Int,
  order order: Int,
) -> List(Cell) {
  let parameters = case value {
    0 -> #(0.25949999690055847, 13.850000381469727)
    1 -> #(0.5195000171661377, 27.690000534057617)
    2 -> #(0.7788000106811523, 41.540000915527344)
    3 -> #(1.0379999876022339, 55.38999938964844)
    _ -> #(1.2979999780654907, 69.2300033569336)
  }
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(32_809)),
    #("targetFlags", Integer(target_flags)),
    #("effectType", Integer(8)),
    #("damageType", Integer(3)),
    #("flags", Integer(1)),
    #("dataBits00", Integer(1_065_353_216)),
    #("emmComparison", Integer(comparison)),
    #("emmValue", Integer(value)),
    #("parameterType00", Integer(12)),
    #("parameterType01", Integer(10)),
    #("parameterValue00", Float(parameters.0)),
    #("parameterValue01", Float(parameters.1)),
    #("phaseFlags", Integer(1)),
    #("orderIndex", Integer(order)),
  ])
}

/// The plans of the rows with Mind Burst's spend as the client's rows hold it,
/// built once per run like `default_plans`.
pub fn plans_with_mind_burst_spend() -> spell_plan.Plans {
  database_support.once("spell_tables_plans_with_mind_burst_spend", fn() {
    let assert Ok(plans) =
      with_loaded(
        rows: rows_with_mind_burst_spend(
          emm_id: 4,
          cost: #(6, 1),
          damage: mind_burst_damage,
        ),
        body: fn(tables) { spell_plan.build(tables:) },
      )
      as "the planted rows with Mind Burst's spend build"
    plans
  })
}

/// The plans of `rows_with_energize`.
pub fn plans_with_energize() -> spell_plan.Plans {
  let assert Ok(plans) =
    with_loaded(rows: rows_with_energize(), body: fn(tables) {
      spell_plan.build(tables:)
    })
    as "the planted rows with Energize build"
  plans
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
