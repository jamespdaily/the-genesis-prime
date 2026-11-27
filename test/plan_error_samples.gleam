//// One sample of each plan error the load can fail with, for the tests that ask what a
//// refusal does to the plans (`spell_plan.refusal_of`): whether the ability that holds it
//// is left out or the load fails, and why the server refuses the value.
////
//// A variant a value splits is a row for each side of the split. The outcomes are what
//// the plan did before the refusal was one decision: a skip for an effect or a rule the
//// server does not build, a failure for a missing row or a fault of the data. Each
//// basis names its source: the fact file's record and a phrase of its gap for an open
//// question; a value that record lists and the sample lies outside is unexplained;
//// the code that raises the error says whether the server understands the value and does
//// not build it, or whether the table's structure is at fault.

import genesis_prime/game/amp_spec
import genesis_prime/game/column_reading.{Question}
import genesis_prime/game/forced_move
import genesis_prime/game/innate
import genesis_prime/game/item_property
import genesis_prime/game/spell_plan.{
  type Basis, type PlanError, OpenQuestion, Structure, Unbuilt, Unexplained,
}
import genesis_prime/table/id.{EldanAugmentationId, Spell4Id}

/// A plan error, whether it leaves the ability out of the plans (`True`) or fails the load
/// (`False`), and the basis of the refusal.
pub type Sample {
  Sample(error: PlanError, leaves_out: Bool, basis: Basis)
}

/// The record that says the meaning of a `targetFlags` value is read from rows and not from
/// code: a value no aim reads (0, or a bit 8) is that question.
pub const aim_question =
  Question(
    fact: "Spell4Effects.targetFlags",
    marker: "The meaning of each value is read from rows",
  )

/// The record of the stat modifier, whose gap holds a question for each meaning a parameter
/// kind could have.
pub fn modifier_question(marker marker: String) -> Basis {
  OpenQuestion(Question(fact: "Spell4Effects.effectType.11.change", marker:))
}

/// The prerequisite type of a record the fact file holds that the server has not decoded.
pub const undecoded_prerequisite_with_a_record = 102

/// A prerequisite type the server has not decoded and the fact file holds no record of.
pub const undecoded_prerequisite_without_a_record = 56

/// One row for each plan error, and for each side of a variant a value splits.
pub fn samples() -> List(Sample) {
  let aim_open = OpenQuestion(aim_question)
  [
    Sample(spell_plan.ProxyAimNotRead(1, 2, 0), True, aim_open),
    Sample(spell_plan.ProxyCycle([1]), True, Structure),
    Sample(spell_plan.UnreadCost(1, 2), True, Unbuilt),
    Sample(spell_plan.UnreadRequirement(1, 2), True, Unbuilt),
    Sample(spell_plan.GainAimNotRead(1, 2, 6), True, Unbuilt),
    Sample(spell_plan.GainAimNotRead(1, 2, 0), True, aim_open),
    Sample(spell_plan.GainAimNotRead(1, 2, 8), True, aim_open),
    Sample(spell_plan.GainVitalNotRead(1, 2, 3), True, Unbuilt),
    Sample(spell_plan.GainShareNotRead(1, 2, 3, 4), True, Unbuilt),
    Sample(
      spell_plan.ApplyPrerequisiteNotRead(
        1,
        2,
        undecoded_prerequisite_with_a_record,
      ),
      True,
      OpenQuestion(Question(
        fact: "Prerequisite.prerequisiteTypeId.102",
        marker: "",
      )),
    ),
    Sample(
      spell_plan.ApplyPrerequisiteNotRead(
        1,
        2,
        undecoded_prerequisite_without_a_record,
      ),
      True,
      OpenQuestion(Question(
        fact: "Prerequisite.prerequisiteTypeId.56",
        marker: "",
      )),
    ),
    Sample(
      spell_plan.TargetPrerequisiteReadsStruckUnit(1, 2, 40),
      True,
      Unbuilt,
    ),
    Sample(spell_plan.TargetPrerequisiteReadsStruckUnit(1, 2, 3), True, Unbuilt),
    Sample(spell_plan.ControlHelperNotRead(1, 2, 3), True, Unbuilt),
    Sample(
      spell_plan.SpendComparisonNotRead(1, 2, 3),
      True,
      Unexplained(fact: "Spell4Effects.emmComparison"),
    ),
    Sample(
      spell_plan.ForceRemoveSelectorNotRead(1, 2, 3),
      True,
      OpenQuestion(Question(
        fact: "Spell4Effects.effectType.80",
        marker: "selector values",
      )),
    ),
    Sample(
      spell_plan.ForceRemoveCountsDiffer(1, 2, 3, 4),
      True,
      OpenQuestion(Question(
        fact: "Spell4Effects.effectType.80",
        marker: "count of stacks or of casts",
      )),
    ),
    Sample(spell_plan.LastingAimNotRead(1, 2, 0), True, aim_open),
    Sample(spell_plan.ControlStateNotRead(1, 2, 28), True, Unbuilt),
    Sample(spell_plan.ControlAimNotRead(1, 2, 0), True, aim_open),
    Sample(spell_plan.FriendlyAreaNotRead(1, 2, 5), True, Unbuilt),
    Sample(spell_plan.PeriodicProxyAtAlliesNotRead(1, 2, 3), True, Unbuilt),
    Sample(spell_plan.ProxyOnEachAllyAtSeveralGos(1, 2, 3), True, Unbuilt),
    Sample(spell_plan.AlliesModifierGateNotRead(1, 2), True, Unbuilt),
    Sample(spell_plan.ControlPersistenceNotRead(1, 2), True, Unbuilt),
    Sample(spell_plan.StealthAimNotRead(1, 2, 0), True, aim_open),
    Sample(spell_plan.StealthAimNotRead(1, 2, 4), True, Unbuilt),
    Sample(spell_plan.StealthTimedNotRead(1, 2), True, Unbuilt),
    Sample(
      spell_plan.StealthBreaksNotRead(1, 2, 3),
      True,
      Unexplained(fact: "Spell4Effects.effectType.83"),
    ),
    Sample(spell_plan.StealthConditionNotRead(1, 2), True, Unbuilt),
    Sample(
      spell_plan.StealthChangeNotRead(1, 2),
      True,
      Unexplained(fact: "Spell4.spellCastStealthChange"),
    ),
    Sample(
      spell_plan.ParameterNotRead(1, 2, spell_plan.ModifierRow, 18),
      True,
      modifier_question(marker: "the passed-in value"),
    ),
    Sample(
      spell_plan.ParameterNotRead(1, 2, spell_plan.ModifierRow, 3),
      True,
      modifier_question(marker: "an attribute"),
    ),
    Sample(
      spell_plan.ParameterNotRead(1, 2, spell_plan.ModifierRow, 24),
      True,
      Unexplained(fact: "Spell4Effects.effectType.11.change"),
    ),
    Sample(
      spell_plan.ParameterNotRead(1, 2, spell_plan.HealRow, 3),
      True,
      Unbuilt,
    ),
    Sample(
      spell_plan.ParameterNotRead(1, 2, spell_plan.AbsorptionRow, 3),
      True,
      Unbuilt,
    ),
    Sample(spell_plan.HealUntilRemovedNotRead(1, 2), True, Unbuilt),
    Sample(spell_plan.HealNoTick(1, 2, 3, 4), True, Structure),
    Sample(spell_plan.ProxyNoTick(1, 2, 3, 4), True, Structure),
    Sample(spell_plan.HealOnStruckUnit(1, 2, 3), True, Unbuilt),
    Sample(
      spell_plan.InterruptArmorTakeBackNotRead(1, 2, 3),
      True,
      OpenQuestion(Question(
        fact: "Spell4Effects.effectType.52",
        marker: "The dataBits01 reading rests on two test spell names",
      )),
    ),
    Sample(spell_plan.InterruptArmorOnStruckUnit(1, 2, 3), True, Unbuilt),
    Sample(
      spell_plan.AbsorptionAmountNotRead(1, 2),
      True,
      OpenQuestion(Question(
        fact: "Spell4Effects.effectType.29",
        marker: "Which column is the amount when the other is 0 is not settled",
      )),
    ),
    Sample(spell_plan.AbsorptionPeriodic(1, 2, 3), True, Unbuilt),
    Sample(spell_plan.AbsorptionHasNoLifetime(1, 2), True, Unbuilt),
    Sample(spell_plan.AbsorptionOnStruckUnit(1, 2, 3), True, Unbuilt),
    Sample(
      spell_plan.ProcKindNotRead(1, 2, 3),
      True,
      OpenQuestion(Question(
        fact: "Spell4Effects.effectType.14",
        marker: "the trigger kinds (dataBits00)",
      )),
    ),
    Sample(spell_plan.SummonedProcNotRead(1, 2, 3, 4), True, Unbuilt),
    Sample(
      spell_plan.StruckMoveNotRead(1, 2, forced_move.UnknownKind(2, 16)),
      True,
      Unexplained(fact: "Spell4Effects.effectType.3"),
    ),
    Sample(
      spell_plan.StruckMoveNotRead(1, 2, forced_move.NotAFloat(2, "dataBits01")),
      False,
      Structure,
    ),
    Sample(
      spell_plan.DisguiseNotRead(1, 2, spell_plan.OutfitNeedsMessage0x905),
      True,
      OpenQuestion(Question(
        fact: "Spell4Effects.effectType.112",
        marker: "Whether the server should use 0x905 for dataBits00 is not read",
      )),
    ),
    Sample(
      spell_plan.DisguiseNotRead(1, 2, spell_plan.NamesNoDisplay),
      True,
      Unexplained(fact: "Spell4Effects.effectType.112"),
    ),
    Sample(
      spell_plan.DisguiseNotRead(1, 2, spell_plan.DisplayHasNoSlot(3)),
      True,
      Unexplained(fact: "Spell4Effects.effectType.112"),
    ),
    Sample(spell_plan.AreaNotBuilt(1, "an area"), True, Unbuilt),
    Sample(spell_plan.NoRow("Spell4", 1), False, Structure),
    Sample(spell_plan.ModifierPropertyHasNoRow(1, 2, 3), False, Structure),
    Sample(
      spell_plan.ModifierPropertyBeyondClientSlots(1, 2, 197),
      False,
      Structure,
    ),
    Sample(
      spell_plan.ModifierNumberNotFinite(1, 2, "dataBits02"),
      False,
      Structure,
    ),
    Sample(spell_plan.CooldownNumberNotFinite(1, 2), False, Structure),
    Sample(spell_plan.HealNumberNotFinite(1, 2), False, Structure),
    Sample(spell_plan.AbsorptionNumberNotFinite(1, 2), False, Structure),
    Sample(spell_plan.ChannelWithoutPulse(1), False, Structure),
    Sample(spell_plan.NoThresholdTime(1), False, Structure),
    Sample(
      spell_plan.ProcNotRead(1, 2, "dataBits02", 3),
      False,
      OpenQuestion(Question(
        fact: "Spell4Effects.effectType.14",
        marker: "not settled by client evidence",
      )),
    ),
    Sample(spell_plan.PrerequisiteCycle([1]), False, Structure),
    Sample(spell_plan.AreaDataFault(1, "an area"), False, Structure),
    Sample(spell_plan.InnateFailed(innate.NoSpell(1, 2)), False, Structure),
    Sample(
      spell_plan.EquipItemNotRead(item_property.NoRow("Item2Type", 1)),
      False,
      Structure,
    ),
    Sample(
      spell_plan.AmpSpellNotRead(amp_spec.AmpSpellNotRead(
        id: EldanAugmentationId(1),
        spell4_id: Spell4Id(2),
      )),
      False,
      Structure,
    ),
    Sample(
      spell_plan.AmpUnlocksClassAbility(amp_spec.Unlocking(
        id: EldanAugmentationId(1),
        spell4_id: Spell4Id(2),
      )),
      True,
      Unbuilt,
    ),
  ]
}
