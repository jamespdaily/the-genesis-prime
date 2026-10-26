//// STUB of the generated module for the client table Spell4: the types and signatures only.

import genesis_prime/table/store
import genesis_prime/table/tbl_file

pub type Spell4 {
  Spell4(
    id: Int,
    description: String,
    spell4_base_id_base_spell: Int,
    tier_index: Int,
    ravel_instance_id: Int,
    cast_time: Int,
    spell_duration: Int,
    spell_cool_down: Int,
    target_min_range: Float,
    target_max_range: Float,
    target_vertical_range: Float,
    caster_innate_requirement0: Int,
    caster_innate_requirement1: Int,
    caster_innate_requirement_value0: Int,
    caster_innate_requirement_value1: Int,
    caster_innate_requirement_eval0: Int,
    caster_innate_requirement_eval1: Int,
    target_begin_innate_requirement: Int,
    target_begin_innate_requirement_value: Int,
    target_begin_innate_requirement_eval: Int,
    innate_cost_type0: Int,
    innate_cost_type1: Int,
    innate_cost0: Int,
    innate_cost1: Int,
    innate_cost_emm_id0: Int,
    innate_cost_emm_id1: Int,
    channel_initial_delay: Int,
    channel_max_time: Int,
    channel_pulse_time: Int,
    localized_text_id_action_bar_tooltip: Int,
    stack_priority: Int,
    spell4_visual_group_id: Int,
    spell4_id_cast_event00: Int,
    spell4_id_cast_event01: Int,
    spell4_id_cast_event02: Int,
    spell4_id_cast_event03: Int,
    spell4_reagent_id00: Int,
    spell4_reagent_id01: Int,
    spell4_reagent_id02: Int,
    spell4_runner_id00: Int,
    spell4_runner_id01: Int,
    runner_target_type_enum00: Int,
    runner_target_type_enum01: Int,
    prerequisite_id_runner00: Int,
    prerequisite_id_runner01: Int,
    ability_charge_count: Int,
    ability_recharge_time: Int,
    ability_recharge_count: Int,
    threshold_time: Int,
    ability_point_cost: Int,
    training_cost: Int,
    spell_channel_flags: Int,
    ignore_follow_time_ms: Int,
    spell4_id_mechanic_alternate_spell: Int,
    spell4_id_pet_switch: Int,
    spell4_tag_id00: Int,
    spell4_tag_id01: Int,
    spell4_tag_id02: Int,
    spell4_tag_id03: Int,
    spell4_tag_id04: Int,
    localized_text_id_caster_icon_spell_text: Int,
    localized_text_id_primary_target_icon_spell_text: Int,
    localized_text_id_secondary_target_icon_spell_text: Int,
    localized_text_id_las_tier: Int,
    localized_text_id_tooltip_cast_info: Int,
    localized_text_id_tooltip_cost_info: Int,
    tooltip_cast_time: Int,
    spell4_aoe_target_constraints_id: Int,
    spell4_conditions_id_caster: Int,
    spell4_conditions_id_target: Int,
    spell4_cc_conditions_id_caster: Int,
    spell4_cc_conditions_id_target: Int,
    spell_cool_down_id_global: Int,
    spell_cool_down_id00: Int,
    spell_cool_down_id01: Int,
    spell_cool_down_id02: Int,
    spell4_group_list_id: Int,
    missile_speed: Int,
    min_missile_speed: Int,
    spell4_client_missile_id00: Int,
    spell4_client_missile_id01: Int,
    spell4_client_missile_id02: Int,
    spell4_client_missile_id03: Int,
    spell4_client_missile_id04: Int,
    spell4_client_missile_id05: Int,
    global_cooldown_enum: Int,
    property_flags: Int,
    ui_flags: Int,
    spell4_stack_group_id: Int,
    prerequisite_id_caster_cast: Int,
    prerequisite_id_target_cast: Int,
    prerequisite_id_caster_persistence: Int,
    prerequisite_id_target_persistence: Int,
    cast_event_condition_enum00: Int,
    cast_event_condition_enum01: Int,
    cast_event_condition_enum02: Int,
    cast_event_condition_enum03: Int,
    cast_event_target_flags00: Int,
    cast_event_target_flags01: Int,
    cast_event_target_flags02: Int,
    cast_event_target_flags03: Int,
    spell_cast_stealth_change: Int,
    prerequisite_id_aoe_target: Int,
    prerequisite_id_aoe_preferred_target: Int,
  )
}

pub const schema =
  tbl_file.Schema(
    table: "Spell4",
    file: "Spell4",
    record_size: 424,
    columns: [
      tbl_file.Column(name: "ID", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "description", column_type: tbl_file.Utf16Text),
      tbl_file.Column(
        name: "spell4BaseIdBaseSpell",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "tierIndex", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "ravelInstanceId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "castTime", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "spellDuration", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "spellCoolDown", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "targetMinRange", column_type: tbl_file.Float32),
      tbl_file.Column(name: "targetMaxRange", column_type: tbl_file.Float32),
      tbl_file.Column(
        name: "targetVerticalRange",
        column_type: tbl_file.Float32,
      ),
      tbl_file.Column(
        name: "casterInnateRequirement0",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "casterInnateRequirement1",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "casterInnateRequirementValue0",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "casterInnateRequirementValue1",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "casterInnateRequirementEval0",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "casterInnateRequirementEval1",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "targetBeginInnateRequirement",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "targetBeginInnateRequirementValue",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "targetBeginInnateRequirementEval",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "innateCostType0", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "innateCostType1", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "innateCost0", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "innateCost1", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "innateCostEMMId0", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "innateCostEMMId1", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "channelInitialDelay",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "channelMaxTime", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "channelPulseTime", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "localizedTextIdActionBarTooltip",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "stackPriority", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "spell4VisualGroupId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4IdCastEvent00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4IdCastEvent01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4IdCastEvent02",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4IdCastEvent03",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ReagentId00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ReagentId01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ReagentId02",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "spell4RunnerId00", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "spell4RunnerId01", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "runnerTargetTypeEnum00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "runnerTargetTypeEnum01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdRunner00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdRunner01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "abilityChargeCount",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "abilityRechargeTime",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "abilityRechargeCount",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "thresholdTime", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "abilityPointCost", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "trainingCost", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "spellChannelFlags",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "ignoreFollowTimeMs",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4IdMechanicAlternateSpell",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4IdPetSwitch",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "spell4TagId00", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "spell4TagId01", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "spell4TagId02", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "spell4TagId03", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "spell4TagId04", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "localizedTextIdCasterIconSpellText",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "localizedTextIdPrimaryTargetIconSpellText",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "localizedTextIdSecondaryTargetIconSpellText",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "localizedTextIdLASTier",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "localizedTextIdTooltipCastInfo",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "localizedTextIdTooltipCostInfo",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "tooltipCastTime", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "spell4AoeTargetConstraintsId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ConditionsIdCaster",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ConditionsIdTarget",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4CCConditionsIdCaster",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4CCConditionsIdTarget",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spellCoolDownIdGlobal",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spellCoolDownId00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spellCoolDownId01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spellCoolDownId02",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4GroupListId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "missileSpeed", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "minMissileSpeed", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "spell4ClientMissileId00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ClientMissileId01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ClientMissileId02",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ClientMissileId03",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ClientMissileId04",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spell4ClientMissileId05",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "globalCooldownEnum",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "propertyFlags", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "uiFlags", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "spell4StackGroupId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdCasterCast",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdTargetCast",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdCasterPersistence",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdTargetPersistence",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventConditionEnum00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventConditionEnum01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventConditionEnum02",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventConditionEnum03",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventTargetFlags00",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventTargetFlags01",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventTargetFlags02",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "castEventTargetFlags03",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "spellCastStealthChange",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdAoeTarget",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "prerequisiteIdAoePreferredTarget",
        column_type: tbl_file.Integer32,
      ),
    ],
  )

const index = 294

pub fn entry() -> store.Entry {
  todo
}

pub fn get(tables: store.Tables, id: Int) -> Result(Spell4, Nil) {
  todo
}

pub fn all(tables: store.Tables) -> List(Spell4) {
  todo
}
