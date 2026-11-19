//// What the client's tables say a pressed ability does: for each ability a class
//// holds, and each class's innate active and passive spell, the tree of
//// casts it starts, built once when the tables load. The cast rule (genesis_prime/game/cast) reads the tree and decides
//// nothing from the tables itself.
////
//// ```
//// SpellLevel (class, no prerequisite) ─▶ Spell4 (the ability) ─▶ Spell4Base
//// Class (the first innate slot, genesis_prime/game/innate) ─▶ Spell4 (the innate's active and passive) ─▶ Spell4Base
////      Spell4Effects (spellId = the Spell4 id), each effect of type Proxy (26) ─▶ the Spell4 it names, as a child
////      Spell4Thresholds (parent = the Spell4 id), by order index ─▶ the Spell4 each tap or charge level casts, as a stage
////      SpellPhase (owner = a Multiphase Spell4) ─▶ the phase delays and flags, in row order
////      SpellCoolDown (the global row) ─▶ the global cooldown's time
////      Class (vitalEnumResource0..) ─▶ the result a short vital gives
//// all of them, once, when the tables load ─▶ Plans ─▶ in_plans(base)
//// ```
////
//// - **Which abilities.** A level-1 ability and an innate must plan or the load fails. An
////   ability a class gains above level 1 with no prerequisite
////   (`SpellLevel.spell4Id.no_prerequisite`) is planned too, and one whose error
////   `is_unbuilt` names is left out and listed by `unplanned`; any other error fails the
////   load. A press of a base with no plan is refused unknown (`cast_press.ability_at`).
//// - **One decision for each effect row.** `read_row` says what the plan makes of a
////   Spell4Effects row in the place its spell is planned (`RowPlace`): in the effects of its
////   spell and applied by a go (`Applied`), in the effects and applied by none (`Held`: a
////   periodic gain, a property change or disguise with no life, an ItemVisualSwap row
////   with a delayTime, a row whose phaseFlags is 0), in none (`LeftOut`), a damage row the area
////   load reads (`ReadByArea`), or an error that fails the load. The effects of a spell are
////   made from these readings into one list ranked by kind (`Spell.effects`, each a
////   `PlannedEffect(Kind)`), which `in_phase` reads one kind at a time, and
////   the coverage measure counts a row read exactly when it
////   is `Applied` (genesis_prime/coverage/effect_row), so the two cannot disagree. A spell
////   a Proxy starts on each struck unit refuses a heal, an Interrupt Armor row and an
////   absorb aimed at its primary target, and a spell that spends every point held refuses
////   an effect with a tag the rule does not read.
//// - **The tree.** A Proxy effect (`Spell4Effects.effectType.26`, dataBits00 the
////   Spell4 id; a row with dataBits00 0 names its spell in dataBits01 and ticks, which
////   the plan does not start: `Spell4Effects.effectType.26.periodic`) starts that spell
////   as a cast of its own, so a `Spell` holds its `Proxy` children, each with the delay
////   the effect gives after its
////   parent's go (`delayTime`) and the phases it fires in (`phaseFlags`: bit n is
////   phase n, every bit for -1, the reading `Spell4.38791` gives). A Proxy with a
////   target apply prerequisite is kept as `GatedOnCasterAndTarget`, with its caster
////   gates and the target gate decoded: the cast rule starts its child on a struck unit
////   when the caster gates pass against the caster and the target gate passes against
////   that unit (`Spell4Effects.prerequisiteIdTargetApply`: the struck unit first, the
////   caster second; Impale's four Proxies, 83818, 83819, 85673 and 85682, pick 39426 or
////   39427 by 38585 or 38587 and 5734 or 5735). A Proxy with a caster apply
////   prerequisite, or with a prerequisite in its dataBits06, is kept as
////   `GatedOnCaster` and started at its phase's go when each passes against the
////   caster (`Spell4.38791`: 79220 and 79229 apply only behind prerequisite 37037;
////   `Spell4Effects.effectType.26.dataBits06`, a reading of the rows that no client
////   code confirms, since the client applies no Proxy itself; the units of a check
////   are `Spell4Effects.prerequisiteIdTargetApply`). Five level-1 Proxies are gated
////   by their dataBits06 so: 177873 (53865 to 60947, 24582), 135961 (Mind Burst
////   32809 to 57030, 23344), 200542 (30900 to 41869, 35913), 212835 (80382 to
////   42569, 33154) and 212838 (80382 to 80383, 32921).
//// - **The gains.** A VitalModifier (`Spell4Effects.effectType.1`) of a tree gives
////   the caster dataBits02 points of the resource slot of its vital (6 is slot 1, 8
////   slot 3), behind its caster apply prerequisite, which the cast rule checks
////   (genesis_prime/game/prerequisite). A child started at each struck unit gives
////   its first phase's gains once per go of its parent, not once per unit (client texts
////   240824 and 314851; retail records: the Tenton Hammer Esper guide and the WildStar
////   fandom Esper Assault list), so the plan moves them onto the `Proxy`. A gain with a
////   tickTime is a `TickingGain`, which the cast rule does not apply. The effect's
////   delayTime is not waited for (the server's choice: 10 ms in each kit row, under
////   a client frame).
//// - **The lasting effects.** A Fluff effect (`Spell4Effects.effectType.17`), a Scale
////   effect (18), an ItemVisualSwap effect (76), a RavelSignal effect (81) and a FullScreenEffect
////   effect (95, `Spell4Effects.effectType.95`) of a tree are each a `Lasting` row: the unit
////   its targetFlags aim at, its delay, durationTime and flags bit 2, which give its spell a life there (genesis_prime/game/lasting). A
////   SpellForceRemove effect (`Spell4Effects.effectType.80`) is a `ForceRemove` row:
////   dataBits00 picks a spell group (1), a Spell4 (2) or a Spell4Base (3) by
////   dataBits01, which must name a row, and the count of stacks is read only where
////   dataBits03 and dataBits04 agree. Each is applied when its caster apply
////   prerequisite passes against the caster, and one behind a target apply
////   prerequisite is applied only to the units that pass it (`GatedOnTarget`). Unlike
////   a Proxy's, their dataBits06 is no prerequisite. A `Spell` also holds its spell groups (`Spell4.spell4GroupListId`)
////   and its stack group with the group's cap (`Spell4.spell4StackGroupId`,
////   `Spell4StackGroup.stackCap`), and whether its lifetimes take the larger of delay
////   and duration (`Spell4.propertyFlags` 0x2000).
//// - **The crowd-control effects.** A CCStateSet effect (`Spell4Effects.effectType.4`)
////   of a tree is a `CrowdControl` row: the unit its targetFlags aim at (the primary
////   target, the area or both: a state on a caster is a player's, which no creature
////   casts; a row aimed at the caster holds Ability Restriction (27) on it, which
////   `restrictions_in_phase` lists apart from the strike's), and its Stun (0),
////   Knockdown (8) or Ability Restriction state, delay, durationTime and the
////   Interrupt Armor it removes (genesis_prime/game/crowd_control). The strike
////   tells the units it selects the row's state, even when its phase has no damage
////   (genesis_prime/game/spell_area `phase`); the cast rule lists the states that
////   landed in the go and keeps a node for their life (genesis_prime/game/cast).
////   Each state's `Spell4Effects.emmComparison` tag chooses it by the points spent,
////   as a gain's does.
//// - **The property modifiers.** A UnitPropertyModifier effect
////   (`Spell4Effects.effectType.11`) whose targetFlags include the caster is a
////   `PropertyModifier` row: the property, mode, multiplier, flat amount and amount for
////   each level (genesis_prime/game/unit_properties), and its delay, durationTime and
////   flags bit 2, which start and end the change and give the caster's node of the cast
////   its life. A row aimed only at other units (targetFlags 2, 4 or 6) is a `StruckChange`
////   that changes the creatures a strike hits, and a row that names the caster and others
////   (3, 5 or 7) changes the caster in a `PropertyModifier` row and the others in a
////   `StruckChange` row. Its caster apply
////   prerequisite, phases and spend tag are a Fluff effect's. A UnitPropertyConversion
////   effect (`Spell4Effects.effectType.145`) whose targetFlags include the caster is a
////   `PropertyModifier` row too, whose change is a `Conversion` of property dataBits00
////   into dataBits01 at the 32-bit float dataBits02; both properties must have a
////   UnitProperty2 row. A DisguiseOutfit effect (`Spell4Effects.effectType.112`) whose
////   targetFlags include the caster is a `PropertyModifier` row too, whose change is a
////   `LookChange`: the displays it shows (genesis_prime/game/look), each in the slot of
////   its item type, from dataBits02 or dataBits01. It starts, ends and gives the node its
////   life as a property change does. A row with an outfit (dataBits00 or dataBits08), no
////   display, or a display whose item type has no slot fails the load
////   (`DisguiseNotRead`); dataBits03 is read as nothing, since no client code reads a
////   type 112 row.
//// - **The Interrupt Armor rows.** A ModifyInterruptArmor effect
////   (`Spell4Effects.effectType.52`) whose targetFlags include the caster (bit 1), or are
////   the primary target alone (2) in a spell cast on the caster, is a `PropertyModifier`
////   row whose `armor` is set: a change of UnitProperty2 44, the maximum, of x * 1.0 +
////   dataBits00, which the player's armor follows (genesis_prime/game/player_life
////   `armor_followed`); dataBits01 1 takes the points back at the end and 0 keeps them,
////   which matters only once armor is worn, and nothing wears a player's armor down yet.
////   Its delay, durationTime, flags bit 2, caster apply prerequisite, phases and spend
////   tag are a type 11 row's. A dataBits01 other than 0 and 1 fails the load. A row aimed
////   only at other units is not read. A child a Proxy starts on each struck unit that
////   holds a row whose aim names its primary target (flags 2, 3 or 7) fails the load:
////   Interrupt Armor on a struck unit is not built. 36 of the 38 type 52 rows are read.
//// - **The absorbs.** An Absorption effect (`Spell4Effects.effectType.29`) whose targetFlags
////   include the caster (bit 1), or are the primary target alone (2) in a spell cast on the
////   caster, is a `PropertyModifier` row whose change is an `AbsorbChange`: the formula of
////   the pool's amount (dataBits00 and dataBits01 as floats and the four parameters, whose
////   kinds must be those the caster's value reads, genesis_prime/game/damage
////   `absorption_formula_of`), the damage types it takes (dataBits04 as a mask) and its
////   aim. It starts, ends and gives the node its life as a type 11 row does. A row with a
////   tickTime, with neither a durationTime nor flags bit 2, with a non-finite number or a
////   parameter kind not read fails the load, as does one whose aim names the primary target in
////   a child a Proxy starts on each struck unit (`AbsorptionPeriodic`,
////   `AbsorptionHasNoLifetime`, `AbsorptionNumberNotFinite`, `ParameterNotRead`,
////   `AbsorptionOnStruckUnit`); a row aimed only at other units is not read.
//// - **The heals.** A Heal effect (`Spell4Effects.effectType.10`) or a HealShields effect
////   (`.118`) whose targetFlags include the caster (bit 1), or are the primary target
////   alone (2) in a spell cast on the caster, is a `Heal` row carrying the vital it
////   restores (health or shield): its formula (dataBits00 as a float,
////   dataBits01 and the four parameters, which must be kinds the caster's value reads,
////   genesis_prime/game/damage `unread`), its delay, aim and caster apply
////   prerequisite, which the cast rule checks, and target apply prerequisite, which it
////   checks for the unit the row heals; a row with a tickTime is a `TickingHeal`, with the schedule of
////   its ticks (genesis_prime/game/ticking), each tick its own 0x7f8. A periodic row that
////   lasts until removed (flags bit 2) is left out (`HealUntilRemoved`, issue 803). A row
////   aimed only at other units (4 and 6) is not read. A child a Proxy starts on each struck unit that holds a heal whose
////   aim names its primary target (flags 2, 3 or 7) fails the load: a heal on a struck unit is not built.
//// - **The shield overloads.** A ShieldOverload effect (`Spell4Effects.effectType.64`)
////   aimed at the area (targetFlags 4) is a `Lasting` row, listed on each struck unit for
////   its durationTime as a Fluff effect is: the client marks the unit overloaded and
////   clears the mark itself. A row aimed at the caster or the primary target is not read:
////   the server's hold of a player's shield at 0 is not built.
//// - **The procs.** A Proc effect (`Spell4Effects.effectType.14`) whose targetFlags are the
////   caster's and whose trigger kind (dataBits00) is one of the holder's own events is a
////   `ProcRow`: 217 entering stealth, 218 leaving it, 44 leaving combat and 0 dying
////   (`Spell4Effects.effectType.14.dataBits00.217_218`, `.0_44`), and the strikes and heals
////   it lands, 12 a hit, 13 a melee hit, 145 a critical, 1 a kill, 20 a heal and 147 a
////   critical heal (`Spell4Effects.effectType.14.dataBits00`, `.13_school`), and nine kinds
////   read by the texts the client holds (`.fairly_sure`): 10 using an ability, 103 spending
////   the class resource, 21 receiving a heal, 52 a foe's deflect, 49 a critical by a finisher
////   or a builder, 11 starting to move, 87 the class resource changing (the holder's gate
////   says to what), 105 the Stalker's suit power dropping and 182 landing a taunt, and the
////   blows a creature lands on the holder: 16 taking damage, 146 a critical, 51 a deflect
////   and 115 a depleted shield (`Trigger`, a guess: the client never reads a Proc row). It holds the
////   spell it casts (dataBits01), planned as a Proxy's child is and on the same chain, so a
////   proc that leads back to a spell on the way fails as a cycle, its chance (dataBits02,
////   a float32: above 0 and at most 1.0), its limit, dataBits05 fires in dataBits04 ms or
////   for the proc's life when that is -1 (`.limits`), its filter on the event's spell
////   (dataBits07 and dataBits08), its holder and event gates (dataBits09 and dataBits06,
////   `.prerequisites`), its aim (dataBits03 bit 4 is the event's other unit) and its delay.
////   The delay, durationTime and flags bit 2 give the holder's node its life
////   (`.lifetime`), and its caster apply prerequisite is a Fluff effect's. A Proc row of
////   another kind is in no list and the load goes on (`proc_read`, `ProcKindNotRead`), as
////   does a row of a kind the texts name that waits on an open issue (`ProcKindWaits`, which
////   names the issue), and a row held by another unit, behind a persistence or target apply prerequisite,
////   with a group and no filter kind, with an aim of 32 or above, or with no life
////   (`ProcIsLeftOut`), and a row whose spell the Spell4 table has no row for, which the
////   client's table keeps because the client never reads a Proc row (`ProcCastsNoSpell`);
////   a row of these kinds with a chance outside 0 to 1.0, a window or
////   count at or below 0 (a window of -1 excepted), a filter kind other than 0, 1 and 2 or a
////   negative delay fails the load naming the column (`ProcNotRead`). The spells the procs
////   cast are in the tree (`tree`).
//// - **The forced moves.** A ForcedMove effect (`Spell4Effects.effectType.3`) whose
////   targetFlags include the caster is a `ForcedMove` row: its delay. The go lists it
////   on the caster and the caster's client moves itself and reports the move
////   (`Spell4Effects.effectType.3.player`); the server works out no destination. A row aimed only at other units is not read. Its caster apply
////   prerequisite, phases and spend tag are a Fluff effect's.
//// - **The cooldown effects.** A ModifySpellCooldown effect
////   (`Spell4Effects.effectType.73`) whose targetFlags include the caster is a
////   `CooldownModifier` row: the selector (dataBits00 and the id of dataBits01, kept as
////   given and looked up in no table) and the operation with its 32-bit float
////   (genesis_prime/game/cooldown), and its delay, durationTime and flags bit 2, which
////   time the change and give the caster's node of the cast its life. A row aimed only
////   at other units is not read. A spell also holds its cooldown groups, the non-zero
////   spellCoolDownId00 to 02, each of which must be a SpellCoolDown row. Its caster
////   apply prerequisite, phases and spend tag are a Fluff effect's.
//// - **The quest advances.** A QuestAdvanceObjective effect (`Spell4Effects.effectType.42`) whose
////   targetFlags include the caster, or name the primary target alone, is a `QuestAdvance` row: the
////   Quest2 id (dataBits00), the objective's index (dataBits01) and the amount (dataBits02), and its
////   delay. The client has no effect for the type, so the go lists none; the cast hands the
////   connection the advance (genesis_prime/game/quest_advance). A row with a column the client does
////   not read that is not 0, or an amount below 1, is left out by name. Its caster apply
////   prerequisite, phases and spend tag are a Fluff effect's.
//// - **The phases** of a Multiphase spell (`Spell.CodeEnumCastMethod` 8) are the
////   SpellPhase rows of its owner kept by the client's rule (`0x14055e180`: order
////   index below 32, and index 0 or a non-zero delay), each delay the gap after
////   the phase before: the client sums the delays into the cast's duration when
////   its castTime is 0 (`0x14053d1f0`), which a gap reading fits, and schedules no
////   phase itself, so the go times are the server's choice
////   (`SpellPhase.phaseDelay`). A phase with the flag 0x200 moves the spell's
////   cooldown to its last phase (`0x14053e5a0`). Any other spell has one go, at
////   the end of its cast time, and a ChargeRelease ability that has stages has
////   none (below).
//// - **A channel** (`Spell.CodeEnumCastMethod` 1) gets (channelMaxTime -
////   channelInitialDelay + channelPulseTime) / channelPulseTime gos, in whole
////   numbers (`0x14053d1f0`); the pulses fall at the initial delay plus each pulse
////   time and the finish timer is set at channelMaxTime, which are the server's
////   choice (`Spell4.channelPulseTime`); the cast ends at the later of that timer
////   and the close of the last go's strike round (`cast.channel_sequence`).
//// - **The stages** of a RapidTap or ChargeRelease ability are the Spell4Thresholds
////   rows whose parent it is, by order index, each a full tree with its
////   thresholdDuration (`Spell4Thresholds.spell4IdToCast`). A press resolves to the
////   row at the open threshold's index, the ability's own spell at -1, and is
////   refused past the last row (`0x1403bfd60`). The threshold lasts the ability's
////   thresholdTime (`opcode.0x816`).
//// - **The cast bar** is decided by the cast method, as the client does
////   (`cast.current_cast`): a spell that shows one is the caster's current cast from
////   its start.
//// - **The cooldowns.** The spell's own is `Spell4.spellCoolDown` in
////   milliseconds, started where the method says (`CooldownStart`,
////   `0x14053e5a0`). The global one is the row `spellCoolDownIdGlobal` names, in
////   effect only for kinds 0 and 1 and a non-zero row (`0x14046afc0`); kinds 0
////   and 2 are refused while it runs (`0x1403b14c0`).
//// - **The costs.** A spell's two innate costs, and a stage's row's two more, each
////   read once into a `Cost` the cast rule checks against the caster's resources
////   (`0x1403b3320`, `0x1405e7980`, `Spell4CastResult.vital_cost`): types 5 to 11
////   are resource slots 0 to 6 (result 50 + the slot; Mind Burst, type 6, is 51);
////   types 4, 12, 13, 14, 18 and 19 go to the class's slots that hold that vital, the
////   last one's result given when none passes (Gamma Rays is 55); on a threshold
////   row's cost the same types go to the first such slot that holds a point
////   (`RowClassCost`). Health (1), shield (3), focus (15)
////   and 16 (slot 7) give their own results (44, 176, 167, 177) and are held by no
////   rule of the server; any other type, the client's slots 8 to 10 (types 27 to 29)
////   among them, is an `UnreadCost`.
//// - **The spend.** A cost's Spell4 EMM id (`Spell4.innateCostEMMId0`, genesis_prime/game/spend)
////   of 4 or 7 on a slot cost makes it a `SpendAllCost`, which takes every point the
////   slot holds; any other id, one on a slot or unheld cost and one on no cost are an
////   `UnreadSpendCost`; a class cost keeps its check whatever its id. Each gain, Proxy
////   and (in genesis_prime/game/spell_area) damage effect keeps its row's tag (`Spell4Effects.emmComparison`), and the cast
////   rule chooses by it with the points spent.
//// - **The caster requirements.** A spell's two caster vital requirements
////   (`0x1403b1780`): types 5 to 11 read the same slots with the same results,
////   compared with the value by the eval code (`0x1407a1750`: 0 to 4
////   on the amount, 5 to 9 the same on the percentage of the slot's maximum, any
////   other never passes); type 0 is none; any other type is an
////   `UnreadRequirement`. A failed requirement is waived when the spell's
////   `RequirementWaiver` passes (below).
//// - **No target.** None of the 18 level-1 abilities nor the six innate actives needs a
////   target the client picks (`Spell4TargetMechanics.targetType`), so the plan holds
////   no range and no target rule.
//// - **A spell's own cast conditions** are its four Prerequisite columns, each loaded with
////   the rows it nests (genesis_prime/game/prerequisite `load`), and kept on every spell
////   of a tree, the stages and children too. The press checks the pressed or staged
////   spell's CasterCast (`CastGate`, failure 151) then its TargetCast (281), after every
////   other check (`0x1403ace00`); a spell whose propertyFlags has bit 2 and whose
////   casterInnateRequirement0, casterInnateRequirement1 or targetBeginInnateRequirement
////   is not 0 holds its CasterCast as a `RequirementWaiver`, which only waives a failed
////   requirement (`0x1403b1780`; Rampage 58524's 19750). The cast rule checks the other
////   two columns, CasterPersistence (282) and TargetPersistence (283), at the end of each
////   input while the cast lasts (genesis_prime/game/cast `persisted`), since the client
////   never evaluates them (`Spell4.prerequisiteIdCasterPersistence`). Four innate actives
////   hold a gate (Warrior 46867, Esper 58586, Stalker 46073, Spellslinger 47273) and
////   Spell Surge's buff 47439 a persistence.
//// - **The innates.** A slot-0 innate's active spell is held as an ability in the
////   bag at the index after the level-1 abilities (genesis_prime/game/loadout), so its
////   plan is the ability's. Its passive is never pressed: the server starts it itself
////   (genesis_prime/game/cast `passive_started`).
//// - **The caster's death.** Bit 0 of the spell's caster condition row says
////   whether its caster must be alive, must be dead or may be either
////   (`Spell4.spell4ConditionsIdCaster`, `CasterDeath`); the row's other
////   conditions are not read. The target row's bit 0 is read the same way
////   (`Spell4.spell4ConditionsIdTarget`, `Spell.target_death`), for the activate cast.
//// - **What fails the load:** a Spell4, Spell4Base, Spell4Conditions, SpellCoolDown,
////   Class or Prerequisite row the tree names that the tables lack (a Prerequisite
////   column of a Spell4 row included), a Prerequisite row that nests itself through the
////   rows it nests, a cost of a type
////   not read, a cycle of Proxy effects, a channel with no pulse time, a gain
////   aimed other than at the caster, of a vital other than 6 or 8, or behind a
////   target apply prerequisite, an effect behind a target apply prerequisite with a
////   condition of a type not read (issue 818) or, past the caster, of a type that reads
////   what the casts held on a struck creature hold (issue 569) or, on a row that does not
////   reach struck units alone or that the strike does not carry to the creature, the
////   creature's own state (issue 851), and an effect of a spell that spends
////   every point held with an emmComparison other than 0 or 1; a Fluff or SpellForceRemove effect
////   aimed other than at the caster, the primary target or the area; a type 80
////   effect with a dataBits00 other than 1 to 3, naming no group, Spell4 or
////   Spell4Base, or whose dataBits03 and dataBits04 differ; a Spell4GroupList or
////   Spell4StackGroup row a spell names that the tables lack; and a CCStateSet effect
////   of a state other than Stun, Knockdown and Ability Restriction, of Stun or Knockdown
////   aimed at the caster or by other flags, of Ability Restriction aimed anywhere but at
////   the caster, or behind an apply prerequisite.

import genesis_prime/game/cast_bar_kind
import genesis_prime/game/cooldown
import genesis_prime/game/crowd_control
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/forced_move
import genesis_prime/game/innate
import genesis_prime/game/lasting
import genesis_prime/game/loadout
import genesis_prime/game/look
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/quest_log.{type Quest, type QuestRowError}
import genesis_prime/game/spell_effect.{type PlannedEffect, PlannedEffect}
import genesis_prime/game/spend
import genesis_prime/game/ticking
import genesis_prime/game/unit_properties
import genesis_prime/game/unit_state
import genesis_prime/game/worn_visual
import genesis_prime/message/crowd_control_state
import genesis_prime/message/float32
import genesis_prime/table/cc_state_additional_data
import genesis_prime/table/id.{
  type ItemSlotId, type PrerequisiteId, type Spell4BaseId, type Spell4EffectsId,
  type Spell4Id, type UnitProperty2Id, CCStateAdditionalDataId, ItemDisplayId,
  PrerequisiteId, Spell4BaseId, Spell4ConditionsId, Spell4EffectsId,
  Spell4GroupListId, Spell4Id, Spell4StackGroupId, SpellCoolDownId,
  UnitProperty2Id,
}
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_slot
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import genesis_prime/table/spell4_stack_group
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import genesis_prime/table/unit_property2
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// How a spell is cast (`Spell.CodeEnumCastMethod`, Spell4Base.castMethod).
pub type CastMethod {
  Normal
  Channeled
  PressHold
  ChanneledField
  ClientSideInteraction
  RapidTap
  ChargeRelease
  Multiphase
  Transactional
  OtherMethod(id: Int)
}

/// Whether the client shows a cast bar for a spell (`SpellShowsCastBar`,
/// `cast.current_cast`), which the spell's cast method decides.
pub type CastBar {
  /// The spell has a cast bar: a Normal spell with a cast time and a castBarType, a
  /// Multiphase one with either, a Channeled one with a castBarType, a ChargeRelease
  /// one with a thresholdTime or else a cast time, and any other method with a cast
  /// time.
  ShowsCastBar
  HidesCastBar
  /// A Channeled spell with no castBarType: it shows the bar only as the pressed
  /// spell itself (the cast's root is the spell).
  ShowsWhenPressed
}

/// Which go of a cast starts the spell's own cooldown (`0x14053e5a0`).
pub type CooldownStart {
  /// The first go: a Normal spell, and a Multiphase one with no phase of the flag
  /// 0x200.
  AtFirstGo
  /// The go that reaches the count: a Multiphase spell with a phase of the flag 0x200
  /// (its last phase) and a channel (its last pulse).
  AtLastGo
  /// No go: a RapidTap ability's cooldown starts when its threshold closes, and a
  /// ChargeRelease ability's at the first go of the stage the release casts.
  NotAtAGo
}

/// Whether the spell needs the weapon (Spell4Base.weaponSlot, `0x1403afb10`).
pub type WeaponSlot {
  /// 0: no weapon is needed.
  NoWeaponNeeded
  /// 1: an item in the equipped slot 16 is needed, or the press is refused 169.
  PrimaryWeapon
  /// 2: the press is always refused 169.
  Refused
  OtherWeaponSlot(id: Int)
}

/// What a spell does to the global cooldown (Spell4.globalCooldownEnum with the
/// SpellCoolDown row of `spellCoolDownIdGlobal`).
pub type GlobalCooldown {
  GlobalCooldown(
    /// A press is refused 14 while the global cooldown runs: kinds 0 and 2
    /// (`0x1403b14c0`).
    refused_while_running: Bool,
    /// The time the global cooldown runs for from the accept, in milliseconds:
    /// kinds 0 and 1 with a non-zero row (`0x14046afc0`); none for the others.
    starts_for_ms: Option(Int),
  )
}

/// Whether a Proxy is started.
pub type Condition {
  Always
  /// The Proxy starts at its phase's go when every one of these prerequisites
  /// passes against the caster: its caster apply prerequisite, then the one its
  /// dataBits06 names (`Spell4Effects.effectType.26.dataBits06`).
  GatedOnCaster(gates: List(Prerequisite))
  /// The effect applies only to the units that pass this target apply prerequisite, the
  /// struck unit first and the caster second (`Spell4Effects.prerequisiteIdTargetApply`);
  /// the cast rule checks it for each unit the row reaches, in the caster's picture of the
  /// world. The plan holds it only where the cast can read it for those units
  /// (`target_gate_read`); a row aimed only at units past the caster whose gate reads each
  /// creature's own state has no condition for it, and the spell's `struck_gates` holds
  /// it instead. Only an effect that is not a Proxy has it.
  GatedOnTarget(prerequisite: Prerequisite)
  /// Only a Proxy has it. The Proxy starts its child on a unit when every one of these caster gates passes
  /// against the caster and the target gate passes against that unit, the struck unit for
  /// a Proxy aimed at the area and the caster for one aimed at the caster
  /// (`Spell4Effects.prerequisiteIdTargetApply`). The caster gates are its caster apply
  /// prerequisite, then the one its dataBits06 names.
  GatedOnCasterAndTarget(caster: List(Prerequisite), target: Prerequisite)
}

/// A resource gain of a spell: a VitalModifier aimed at the caster
/// (`Spell4Effects.effectType.1`), `amount` points of resource slot `slot`, in the
/// phases of `phase_flags`, given when its `condition` passes against the caster, whose
/// own unit is the unit the row reaches, and when its `tag` holds for the points the cast
/// spent (genesis_prime/game/spend).
pub type Gain {
  Gain(
    effect_id: Spell4EffectsId,
    slot: Int,
    amount: Int,
    phase_flags: Int,
    condition: Condition,
    tag: spend.Tag,
  )
  /// A gain each `tick_ms` for `duration_ms` (Spell4Effects.tickTime and
  /// durationTime), which the cast rule does not apply.
  TickingGain(
    effect_id: Spell4EffectsId,
    slot: Int,
    amount: Int,
    phase_flags: Int,
    condition: Condition,
    tag: spend.Tag,
    tick_ms: Int,
    duration_ms: Int,
  )
}

/// Who an effect aims at (`Spell4Effects.targetFlags`), read once for the effects a
/// spell holds: each constructor names the bits its flags hold (bit 1 the caster, bit 2
/// the primary target, bit 4 the area), and a row reaches every unit its bits name.
pub type Aim {
  AimsAtCaster
  AimsAtPrimaryTarget
  AimsAtCasterAndPrimaryTarget
  AimsAtArea
  AimsAtCasterAndArea
  AimsAtPrimaryTargetAndArea
  AimsAtCasterPrimaryTargetAndArea
}

/// The aim of an effect's `targetFlags`: each of 1 to 7 as the bits it holds, the caster
/// (1), the primary target (2) and the area (4). 0 and every value with bit 8 or above
/// have no aim: the client refuses 0 (`Spell4Effects.targetFlags.load`), and bit 8's
/// meaning is not known ([B8]: the guess is that no row holds it in a spell the server
/// plays; it waits for the question under #336).
///
/// [C] That 3, 5 and 7 are the union of their bits is a guess: the client's load
/// refuses only 0 and no other reader of the column was found.
pub fn aim_of(target_flags target_flags: Int) -> Result(Aim, Nil) {
  case target_flags {
    1 -> Ok(AimsAtCaster)
    2 -> Ok(AimsAtPrimaryTarget)
    3 -> Ok(AimsAtCasterAndPrimaryTarget)
    4 -> Ok(AimsAtArea)
    5 -> Ok(AimsAtCasterAndArea)
    6 -> Ok(AimsAtPrimaryTargetAndArea)
    7 -> Ok(AimsAtCasterPrimaryTargetAndArea)
    _ -> Error(Nil)
  }
}

/// Whether the aim names the caster.
pub fn reaches_caster(aim aim: Aim) -> Bool {
  case aim {
    AimsAtCaster
    | AimsAtCasterAndPrimaryTarget
    | AimsAtCasterAndArea
    | AimsAtCasterPrimaryTargetAndArea -> True
    AimsAtPrimaryTarget | AimsAtArea | AimsAtPrimaryTargetAndArea -> False
  }
}

/// Whether the aim names the cast's primary target.
pub fn reaches_primary_target(aim aim: Aim) -> Bool {
  case aim {
    AimsAtPrimaryTarget
    | AimsAtCasterAndPrimaryTarget
    | AimsAtPrimaryTargetAndArea
    | AimsAtCasterPrimaryTargetAndArea -> True
    AimsAtCaster | AimsAtArea | AimsAtCasterAndArea -> False
  }
}

/// Whether the aim names the units the strike hits.
pub fn reaches_area(aim aim: Aim) -> Bool {
  case aim {
    AimsAtArea
    | AimsAtCasterAndArea
    | AimsAtPrimaryTargetAndArea
    | AimsAtCasterPrimaryTargetAndArea -> True
    AimsAtCaster | AimsAtPrimaryTarget | AimsAtCasterAndPrimaryTarget -> False
  }
}

/// Whether the aim names a unit other than the caster: the primary target or the area.
pub fn reaches_past_caster(aim aim: Aim) -> Bool {
  reaches_primary_target(aim:) || reaches_area(aim:)
}

/// The aim with the caster's bit taken away, which is what a row does to the units a
/// strike hits and to the primary target while its caster's part is a row of its own.
/// A caster-only aim has nothing left.
fn past_the_caster(aim aim: Aim) -> Result(Aim, Nil) {
  case aim {
    AimsAtCaster -> Error(Nil)
    AimsAtCasterAndPrimaryTarget -> Ok(AimsAtPrimaryTarget)
    AimsAtCasterAndArea -> Ok(AimsAtArea)
    AimsAtCasterPrimaryTargetAndArea -> Ok(AimsAtPrimaryTargetAndArea)
    AimsAtPrimaryTarget | AimsAtArea | AimsAtPrimaryTargetAndArea -> Ok(aim)
  }
}

/// The aim of a row that holds the caster's bit and the area's bit, read in a spell that
/// hits no foes ([F] `spell_hits_foes`): the area's bit is left out, since a friendly
/// spell's area waits for #834. An aim without the caster's bit is as it is.
fn without_friendly_area(aim aim: Aim) -> Aim {
  case aim {
    AimsAtCasterAndArea -> AimsAtCaster
    AimsAtCasterPrimaryTargetAndArea -> AimsAtCasterAndPrimaryTarget
    AimsAtCaster
    | AimsAtPrimaryTarget
    | AimsAtCasterAndPrimaryTarget
    | AimsAtArea
    | AimsAtPrimaryTargetAndArea -> aim
  }
}

/// Whether the aim holds the area's bit together with the caster's.
fn names_caster_and_area(aim aim: Aim) -> Bool {
  reaches_caster(aim:) && reaches_area(aim:)
}

/// Which unit a Proxy's child cast is made on.
pub type ProxyTarget {
  /// The caster of the spell whose Proxy fired.
  OnCaster
  /// Each unit the go struck: a Proxy whose effect aims at the area
  /// (`Spell4Effects.targetFlags` 4), which starts one child for each Hit unit
  /// (genesis_prime/game/cast `went`).
  OnEachStruck
}

/// The times of a Channeled spell, in milliseconds (Spell4.channelInitialDelay,
/// channelMaxTime and channelPulseTime).
pub type Channel {
  Channel(initial_delay_ms: Int, max_time_ms: Int, pulse_time_ms: Int)
}

/// What the spell's caster condition row says of a dead caster: bit 0 of its
/// Spell4Conditions mask, with the same bit of its value
/// (`Spell4.spell4ConditionsIdCaster`). The row's other bits are not read: the
/// rule checks no other condition of the caster.
pub type CasterDeath {
  /// The mask's bit 0 with the value's bit 0 clear: a dead caster is refused 57
  /// Caster_CannotBeDead.
  CannotBeDead
  /// The mask's bit 0 with the value's bit 0 set: a living caster is refused 58
  /// Caster_MustBeDead.
  MustBeDead
  /// No row (id 0), or a row without the mask's bit 0: never refused for death.
  AliveOrDead
}

/// The life of a caster that a spell's caster condition refuses.
pub type RefusedLife {
  /// A dead caster (`CannotBeDead`).
  RefusesDead
  /// A living caster (`MustBeDead`).
  RefusesLiving
}

/// The life of the caster, dead or alive, that the spell's caster condition refuses, when
/// it refuses it: the press (`cast_press.verdict`) and a proc's cast (`cast.proc_cast`) both ask
/// this (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`).
pub fn refused_life(
  spell spell: Spell,
  dead dead: Bool,
) -> Option(RefusedLife) {
  case spell.caster_death, dead {
    CannotBeDead, True -> Some(RefusesDead)
    MustBeDead, False -> Some(RefusesLiving)
    CannotBeDead, False | MustBeDead, True | AliveOrDead, _ -> None
  }
}

/// One stage of a RapidTap or ChargeRelease ability: the spell a tap or a charge
/// level casts, and the time the threshold takes to reach it from the stage before
/// (Spell4Thresholds.thresholdDuration).
pub type Stage {
  Stage(duration_ms: Int, spell: Spell)
}

/// A spell and what it starts. `spell4_id` is the id of the Spell4 row; the cast
/// ids a press makes are the cast rule's (genesis_prime/game/cast).
pub type Spell {
  Spell(
    spell4_id: Spell4Id,
    spell4_base_id: Spell4BaseId,
    /// The spell's school (`Spell4Base.school`, `Spell.CodeEnumSchool`): 0 Spell, 1 Melee,
    /// 2 Ranged, 3 Unarmed.
    school: Int,
    method: CastMethod,
    /// Spell4.castTime; 0 goes at once.
    cast_time_ms: Int,
    /// Spell4.spellCoolDown: the spell's own cooldown, started where
    /// `cooldown_start` says.
    cooldown_ms: Int,
    cooldown_start: CooldownStart,
    /// The index of the first phase with the flag 0x200 of a Multiphase spell: a
    /// cast that has gone past it starts the cooldown at its 0x7fe even when it
    /// ends before its last phase (`0x14053e1b0`).
    cooldown_phase: Option(Int),
    /// Whether the client shows a cast bar for the spell, and so makes it the
    /// unit's current cast (`cast.current_cast`).
    cast_bar: CastBar,
    /// Whether a live cast of this spell leaves the caster free to press another:
    /// Spell4.propertyFlags 0x40 (`Spell4.propertyFlags`).
    free_while_live: Bool,
    /// Whether a press of this spell is never refused 13 for a live cast:
    /// Spell4.propertyFlags 0x10 or 0x1 (`Spell4.propertyFlags`).
    ignores_casting: Bool,
    /// Whether an effect's lifetime is the larger of its delay and durationTime
    /// rather than their sum: Spell4.propertyFlags 0x2000, the spell record's flag
    /// 0x10000000 (`opcode.0x7f4.effect_time`, `0x140568540`).
    longer_of_delay_and_duration: Bool,
    weapon: WeaponSlot,
    /// Whether the caster must be alive or dead to cast it.
    caster_death: CasterDeath,
    /// Whether the target must be alive or dead: bit 0 of the target condition row
    /// (`Spell4.spell4ConditionsIdTarget`).
    target_death: CasterDeath,
    /// The crowd-control states that refuse a press of this spell: the ccStateMask of
    /// the Spell4CCConditions row the Spell4's caster column names, 0 for no row;
    /// bit n is the state n (`CheckSpellCCConditions`, `0x1403b2c40`). The row's
    /// ccStateFlagsRequired is 0 in every row the client has, so it is not read.
    caster_cc_mask: Int,
    /// The crowd-control states that refuse a press of this spell at a target: the
    /// ccStateMask of the Spell4CCConditions row the Spell4's target column names, 0 for
    /// no row; bit n is the state n.
    target_cc_mask: Int,
    global_cooldown: GlobalCooldown,
    /// The innate costs a press pays, in the client's order: the Spell4 row's two,
    /// then a stage's Spell4Thresholds row's two (`0x1403b3320`).
    costs: List(Cost),
    /// The caster vital requirements a press is checked against
    /// (`0x1403b1780`).
    requirements: List(Requirement),
    /// What the spell's prerequisiteIdCasterCast is to a press (`0x1403ace00`,
    /// `0x1403b1780`).
    caster_cast: CasterCast,
    /// The spell's prerequisiteIdTargetCast, which the press checks after
    /// `caster_cast`: failure 281 (`0x1403ace00`).
    target_cast: Option(Prerequisite),
    /// The spell's prerequisiteIdCasterPersistence, which the server checks while the
    /// cast lasts: failure 282 (the client never evaluates it,
    /// `Spell4.prerequisiteIdCasterPersistence`).
    caster_persistence: Option(Prerequisite),
    /// The spell's prerequisiteIdTargetPersistence: failure 283.
    target_persistence: Option(Prerequisite),
    /// The gap before each phase's go, in order; empty for a spell that is not
    /// Multiphase.
    phase_delays_ms: List(Int),
    /// How long the threshold a RapidTap or ChargeRelease ability opens stays open:
    /// Spell4.thresholdTime; 0 for a spell that opens none.
    threshold_ms: Int,
    /// The spells a tap or charge level casts, in order.
    stages: List(Stage),
    /// The pulse times of a Channeled spell.
    channel: Option(Channel),
    /// The spell's effect rows, each an envelope (`genesis_prime/game/spell_effect`) round
    /// its kind, sorted by the rank of the kind and, within a kind, in row order (`rank`).
    /// `in_phase` reads the rows of one kind that apply in a phase. The gains in it are the
    /// spell's own, given at its gos; none of a child started at each struck unit, whose
    /// gains its Proxy holds.
    effects: List(PlannedEffect(Kind)),
    /// The spell groups the spell belongs to (Spell4GroupList's spellGroupId values
    /// of `Spell4.spell4GroupListId`), which a type 80 row selects by.
    groups: List(Int),
    /// The spell's stack group and its cap (`Spell4.spell4StackGroupId`,
    /// `Spell4StackGroup.stackCap`).
    stack: lasting.Stack,
    /// The CCStateSet effects the plan drops: those aimed at another unit that hold their
    /// state until removed, which no rule of the server ends when the spell ends (the
    /// issue "A crowd-control state that lasts until removed ends when its spell ends").
    /// The rest of the spell plans without them, and the cast logs each as a gap.
    dropped_controls: List(Spell4EffectsId),
    /// The target apply prerequisites of rows aimed only at units past the caster whose
    /// conditions all read the struck creature's own state, which the creature checks when
    /// the strike reaches it (`StruckGate`, `prerequisite.checked_by_creature`). Every
    /// such row is here, whatever it does (damage, a crowd-control state or a go row),
    /// and its `condition` holds none of the gate.
    struck_gates: List(StruckGate),
    /// The non-zero cooldown groups of the Spell4 row (`spellCoolDownId00` to `02`),
    /// each a SpellCoolDown row with the time it runs from the go, which a selector 3 of
    /// a cooldown effect tests (`cooldown_groups_of`).
    cooldown_groups: List(cooldown.Group),
    /// What the spell does to the caster's stealth, and at which go (`StealthChange`).
    stealth_change: StealthChange,
    /// The spell the ability's press casts instead while the caster is under Spell Surge
    /// (`Spell4.spell4IdMechanicAlternateSpell`, swapped in by `CastAbilityBagSpell`
    /// `0x14039a040` through `0x1405e7e50`): planned only for the ability a class's bag holds,
    /// and never for the alternate itself, since the client swaps once.
    alternate: Option(Spell),
    /// A RapidTap or ChargeRelease ability with no threshold time: its Proxy rows with a
    /// caster apply prerequisite, in row order, which the press walks to cast the first
    /// whose gate the caster passes (`ResolveProxyByCasterApply` `0x1403d3520`); empty
    /// for every other spell.
    press_proxies: List(PressProxy),
  )
}

/// One Proxy row a threshold-less press may cast: the row, the prerequisite on the
/// caster that lets it through (`Spell4Effects.prerequisiteIdCasterApply`, the only gate
/// the client's walk reads) and the spell its dataBits00 names, planned as a child of the
/// ability.
pub type PressProxy {
  PressProxy(effect_id: Spell4EffectsId, gate: Prerequisite, spell: Spell)
}

/// What a spell's prerequisiteIdCasterCast is to a press (`0x1403ace00`,
/// `0x1403b1780`).
pub type CasterCast {
  NoCasterCast
  /// Checked at the press after every other check: 151 when it fails.
  CastGate(prerequisite: Prerequisite)
  /// propertyFlags bit 2 with a caster requirement block: it only waives a failed
  /// requirement.
  RequirementWaiver(prerequisite: Prerequisite)
}

/// Whether taking damage ends a stealth: a Stealth effect's dataBits02, 0 for
/// `BrokenByDamage` and 1 for `KeptOnDamage` (`Spell4Effects.effectType.83`).
pub type Breaks {
  BrokenByDamage
  KeptOnDamage
}

/// What a spell does to its caster's stealth, from `Spell4.spellCastStealthChange`: the
/// column is read nowhere by the client, so ending stealth on a cast is the server's rule
/// (`Spell4.spellCastStealthChange`, `Spell4.spellCastStealthChange.break`).
/// - 0 ends the stealth of other casts after the effects of a go, at each go.
/// - 1 ends it after the effects of the cast's last go, so effects of an earlier go
///   gated on the caster being stealthed (Impale's Proxies, phase 1) still see it.
/// - 2 leaves it.
/// The stealth a cast's own Stealth rows give is never ended by the cast.
pub type StealthChange {
  EndsStealthAtEachGo
  EndsStealthAfterLastGo
  KeepsStealth
}

/// A Stealth effect (`Spell4Effects.effectType.83`) of a spell, aimed at the caster:
/// whether damage ends the stealth it gives (`breaks`), its `row` (which holds the
/// caster's node of the cast until it is removed: durationTime 0 holds a stealth until it
/// is removed, and a Stealth effect with a delayTime or durationTime is not built), the
/// phases of `phase_flags` it applies in,
/// when its `condition` holds (its caster apply prerequisite against the caster), and
/// when its `tag` holds for the points the cast spent (genesis_prime/game/spend).
pub type StealthRow {
  StealthRow(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    breaks: Breaks,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A RemoveStealth effect (`Spell4Effects.effectType.84`) of a spell, aimed at the
/// caster: it ends every stealth the caster holds, in the phases of `phase_flags`, when
/// its `condition` holds and its `tag` holds for the points the cast spent.
pub type RemoveStealthRow {
  RemoveStealthRow(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// The event of its holder that fires a Proc effect (`Spell4Effects.effectType.14`,
/// dataBits00; the readings are `Spell4Effects.effectType.14.dataBits00.217_218` and
/// `Spell4Effects.effectType.14.dataBits00.0_44`, none of them in the client's code, and
/// `Spell4Effects.effectType.14.dataBits00` for the kinds of a hit, a critical, a kill and
/// a heal).
pub type Trigger {
  /// 217: the holder enters stealth.
  EnteredStealth
  /// 218: the holder leaves stealth.
  LeftStealth
  /// 44: the holder leaves combat.
  LeftCombat
  /// 0: the holder dies.
  Died
  /// 12: a strike of the holder's lands a hit on a creature.
  LandsHit
  /// 13: a strike of the holder's by a spell of school 1 (Melee, `Spell4Base.school`)
  /// lands a hit. A guess: no client code reads a Proc row, and the row groups and the
  /// texts say melee (`Spell4Effects.effectType.14.dataBits00.13_school`).
  LandsMeleeHit
  /// 145: a strike of the holder's lands a critical hit.
  LandsCritical
  /// 1: a strike of the holder's kills the creature it hits.
  Kills
  /// 20: a heal of the holder's lands.
  LandsHeal
  /// 147: a heal of the holder's lands as a critical. No heal is rolled a critical yet,
  /// so a row of this kind is held and never fires; the gap is issue 830.
  LandsCriticalHeal
  /// 10: the holder uses an ability: a press the rule accepts, or a stage of one. A
  /// guess: no client code reads a Proc row, and the texts say 'Using an ability',
  /// 'When casting a Support ability' and 'Activating'
  /// (`Spell4Effects.effectType.14.dataBits00.fairly_sure`).
  UsesAbility
  /// 103: the holder spends a class resource: a payment the rule takes. A guess for the
  /// reading (`.fairly_sure`: 'Volatility, Focus or an Actuator') and for a payment of any
  /// slot counting; the row's gate names the vital.
  SpendsResource
  /// 21: the holder receives a heal. A guess (`.fairly_sure`, text 569376 'On Taking a
  /// Heal'): only a heal the holder lands on itself counts, until another unit can heal
  /// it (issue 570).
  ReceivesHeal
  /// 52: a foe deflects a strike of the holder's. A guess (`.fairly_sure`, texts 364190
  /// and 498616).
  FoeDeflects
  /// 49: a strike of the holder's lands a critical hit, which the row's group filter
  /// narrows to the Finishers or the Builders. A guess (`.fairly_sure`): it is the event
  /// of kind 145, and the texts say 'Landing a Critical Hit with a Finisher'.
  LandsFinisherCritical
  /// 11: the holder starts to move: its movement goes from standing to moving. A guess
  /// for what counts as moving (`.fairly_sure`, texts 'Whenever the target or an enemy
  /// near the target moves').
  StartsMoving
  /// 87: the holder's class resource changes, in either direction; the row's gate says
  /// whether the value is past the row's number. A guess (`.fairly_sure`: 'While above #
  /// Kinetic Energy', 'between # and # Volatility').
  ResourceCrosses
  /// 105: the holder's suit power (the Stalker's slot 3, Vital 8) falls. A guess
  /// (`.fairly_sure`, text 530326): only a fall counts, and the row's gate says whether
  /// it is below the row's number.
  SuitPowerDrops
  /// 182: a strike of the holder's lands a Taunt state on a foe. A guess (`.fairly_sure`,
  /// text 'Landing a Taunt'): what a taunt does to the foe is not part of the event.
  LandsTaunt
  /// 16: a creature's blow lowers the holder's absorbs, shield or health. A guess for the
  /// reading and for a blow fully taken by an absorb counting (`.dataBits00`, the texts say
  /// 'taking damage'; no client code reads a Proc row).
  TakesDamage
  /// 146: a creature's blow on the holder is a critical hit, even when the absorbs took all
  /// of it. A guess for the reading and for the absorbed critical
  /// (`.dataBits00`, `.client_evaluation`).
  SuffersCritical
  /// 51: the holder deflects a creature's blow. It is not kind 52, a foe deflecting the
  /// holder's strike. A guess (`.dataBits00`).
  DeflectsAttack
  /// 115: a creature's blow takes the holder's shield from above 0 to 0. A guess
  /// (`.dataBits00`, 53 rows).
  ShieldDepleted
}

/// How often a Proc fires (dataBits04 and dataBits05,
/// `Spell4Effects.effectType.14.limits`).
pub type ProcLimit {
  /// At most `count` fires in any `window_ms` (dataBits04 above 0); a fire exactly
  /// `window_ms` ago is outside the window.
  InWindow(window_ms: Int, count: Int)
  /// At most `count` fires while the holder holds the proc (dataBits04 -1). A guess: the
  /// rows say -1 holds no window, and the count is read as fires for the proc's life.
  ForLife(count: Int)
}

/// Which spells of an event a Proc fires for (dataBits07 and dataBits08,
/// `Spell4Effects.effectType.14.dataBits07`).
pub type ProcFilter {
  /// dataBits07 0: every event, including those that have no spell.
  AnySpell
  /// dataBits07 2: a spell in the spell group `group_id` (Spell4GroupList, which is how
  /// `0x140561d80` reads a spell's groups).
  InGroup(group_id: Int)
  /// dataBits07 1: the one Spell4.
  OneSpell(spell4_id: Spell4Id)
}

/// Where a fired Proc's spell is aimed (dataBits03, `Spell4Effects.effectType.14.dataBits03`).
pub type ProcAim {
  /// At the holder: bits 1, 2, 8 and 16 and none (a guess for bits 1, 2, 8 and 16).
  AtHolder
  /// Bit 4: at the other unit of the event, the creature a hit struck, or the holder when
  /// the event has none.
  AtOtherUnit
}

/// A Proc effect (`Spell4Effects.effectType.14`) of a spell, aimed at the caster: when
/// the holder's `trigger` happens, the holder casts `spell` at itself or at the event's
/// other unit (`aim`), `delay_ms` later, when the event's spell passes `filter`, the
/// `holder_gate` passes against the holder and the `event_gate` against the event's unit
/// (`Spell4Effects.effectType.14.prerequisites`), within `limit`, and a draw falls below
/// `chance` (dataBits02, float bits). The client reads no Proc row
/// (`Spell4Effects.effectType.14`, graded guess), so two readings are guesses: that the
/// chance is the fraction a draw must fall below, and that the row's delayTime
/// (`delay_ms`) is the wait between the event and the cast; the client's tooltips show
/// both numbers to the player and say no more. Its `row` gives the caster's node of the
/// holding cast its life (a Proc with no durationTime and flags bit 2 lasts until
/// removed, `Spell4Effects.effectType.14.lifetime`), in the phases of `phase_flags`, when
/// `condition` holds (its caster apply prerequisite against the caster) and its `tag`
/// holds for the points the cast spent (genesis_prime/game/spend). The proc's `spell` is
/// planned as a Proxy's child is.
pub type ProcRow {
  ProcRow(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    trigger: Trigger,
    spell: Spell,
    chance: Float,
    limit: ProcLimit,
    filter: ProcFilter,
    aim: ProcAim,
    event_gate: Option(Prerequisite),
    holder_gate: Option(Prerequisite),
    delay_ms: Int,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// What a Proc row's columns say without a table: everything but the Prerequisite rows
/// its gates name (`event_gate` is dataBits06 and `holder_gate` dataBits09, 0 for none)
/// and whether the Spell4 a `OneSpell` filter names exists.
pub type ProcReading {
  ProcReading(
    trigger: Trigger,
    chance: Float,
    limit: ProcLimit,
    filter: ProcFilter,
    aim: ProcAim,
    event_gate: Int,
    holder_gate: Int,
    delay_ms: Int,
  )
}

/// What `proc_read` makes of a Proc row of a kind the server reads.
pub type ProcRead {
  /// The row is read.
  ProcIsRead(reading: ProcReading)
  /// The row is in no list of its spell, and the load goes on.
  ProcIsLeftOut(why: LeftOutReason)
}

/// A ModifySpellCooldown effect (`Spell4Effects.effectType.73`) of a spell whose
/// targetFlags include the caster: the change it makes to the running and later
/// cooldowns (`modifier`), its delay, durationTime and flags bit 2 (`row`, which also
/// give the caster's node of the cast its life, as a Fluff effect's do), the phases of
/// `phase_flags` it applies in, when its `condition` holds (its caster apply
/// prerequisite against the caster, its target apply prerequisite against the caster
/// as the only unit it reaches), and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). A row aimed only at other units is not read, and the
/// part of a row's aim that is not the caster is not applied (`effect_kind.is_row_read`).
pub type CooldownModifier {
  CooldownModifier(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    modifier: cooldown.Modifier,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A ForcedMove effect (`Spell4Effects.effectType.3`) of a spell whose targetFlags
/// include the caster: the `delay_ms` the go lists it with (the move itself, its kind
/// and distance, the caster's client works out and carries out
/// (`Spell4Effects.effectType.3.player`) and no rule of the server reads), the phases of `phase_flags` it applies in, when its `condition`
/// holds (its caster apply prerequisite against the caster, its target apply
/// prerequisite against the caster as the only unit it reaches), and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). A row aimed only at other units is not read, and the part
/// of a row's aim that is not the caster is not applied (`effect_kind.is_row_read`).
pub type ForcedMove {
  ForcedMove(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    delay_ms: Int,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A ForcedMove effect (`Spell4Effects.effectType.3`) of a spell whose targetFlags are 2,
/// 4 or 6, the units a strike hits (a row that includes the caster is a `ForcedMove`
/// and moves the caster only): the `move` its columns decode to
/// (genesis_prime/game/forced_move), the units it strikes (`aim`: the primary target,
/// the area or both), the `delay_ms` after the go the creature is thrown at, the phases
/// of `phase_flags` it applies in, when its `condition` holds (its caster apply
/// prerequisite against the caster, its target apply prerequisite against each struck
/// unit it throws), and when its `tag` holds for the points
/// the cast spent (genesis_prime/game/spend). The cast throws each creature the go
/// `Hit` (genesis_prime/game/cast/control `struck_moves_armed`); a unit that is the caster or
/// another player is not thrown until a move of another player is built (issue 570).
pub type StruckMove {
  StruckMove(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    delay_ms: Int,
    move: forced_move.Move,
    aim: Aim,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A DespawnUnit effect (`Spell4Effects.effectType.97`) aimed past the caster: it removes each
/// creature the go `Hit` at `delay_ms` after the go (`Spell4Effects.delayTime`); the client
/// reads no row of this type and sees the removal only as 0x355 (`Spell4Effects.effectType.97`).
/// `aim` names the units it strikes (the primary target, the area or both, as `StruckMove`
/// does), `phase_flags` the phases it applies in, `condition` when it holds (its caster apply
/// prerequisite against the caster, its target apply prerequisite against each struck unit),
/// and `tag` when it holds for the points the cast spent (genesis_prime/game/spend). The cast
/// tells each creature it removes (genesis_prime/game/cast/control `despawns_told`); a unit
/// that is the caster or another player is not removed.
pub type Despawn {
  Despawn(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    delay_ms: Int,
    aim: Aim,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A UnitStateSet effect (`Spell4Effects.effectType.15`) aimed past the caster with a time:
/// the unit state `row.state` (dataBits00) held on each creature the go `Hit` from the go plus
/// the row's delay for its duration (genesis_prime/game/unit_state `Row`); the client reads no
/// row of this type, so the state shows only through the cast results the server gives.
/// `aim` names the units it strikes (the primary target, the area or both, as `StruckMove`
/// does), `phase_flags` the phases it applies in, `condition` when it holds (its caster apply
/// prerequisite against the caster, its target apply prerequisite against each struck unit),
/// and `tag` when it holds for the points the cast spent (genesis_prime/game/spend). The cast
/// tells each creature it holds the state on (genesis_prime/game/cast/control
/// `unit_states_told`); a unit that is the caster or another player holds none.
pub type UnitState {
  UnitState(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    row: unit_state.Row,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// An NpcExecutionDelay effect (`Spell4Effects.effectType.35`) aimed at the caster with a
/// duration: a creature that casts the spell stands still for `delay_ms` plus `duration_ms`
/// after the go its `phase_flags` name, and acts again after it. The client reads no row of
/// this type (its effect switch has no case 35), so what the row means is the server's
/// reading and the hold's start a guess (genesis_prime/world_map/creature_life `Charged`).
/// A player's cast reads none: no spell a player's route holds has a row of the type.
/// `tag` is when it holds for the points the cast spent (genesis_prime/game/spend).
pub type Delay {
  Delay(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    delay_ms: Int,
    duration_ms: Int,
    tag: spend.Tag,
  )
}

/// A QuestAdvanceObjective effect (`Spell4Effects.effectType.42`) of a spell whose targetFlags
/// reach the caster or the primary target alone (`effect_kind.is_row_read`): `amount`
/// (dataBits02) added to the progress of the objective at `objective_index` (dataBits01) of the
/// quest `quest_id` (dataBits00, a Quest2 id) of the player the cast reaches, `delay_ms` after
/// the go. The client has no case for the type, so what the player sees is the server's 0x361.
/// `aim` is the caster or the primary target alone (`Spell4Effects.targetFlags` has no reader in
/// the client, a guess), `condition` when it holds (its caster apply prerequisite against the
/// caster, its target apply prerequisite against the unit it reaches), `phase_flags` the phases
/// it applies in and `tag` when it holds for the points the cast spent
/// (genesis_prime/game/spend). A quest or an index the tables lack is planned and names no
/// objective at run time.
pub type QuestAdvance {
  QuestAdvance(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    condition: Condition,
    tag: spend.Tag,
    quest_id: Int,
    objective_index: Int,
    amount: Int,
    delay_ms: Int,
  )
}

/// The target apply prerequisite of one row aimed past the caster, which the struck
/// creature checks against its own state (`Spell4Effects.prerequisiteIdTargetApply`): the
/// row's Spell4Effects id, the phases of `phase_flags` it applies in, who it aims at, the
/// prerequisite as the load parsed it, and the `tag` that chooses it by the points the cast
/// spent (genesis_prime/game/spend). The strike tells each unit `aim` names the gate
/// (genesis_prime/game/strike_tell `Gate`), and a go row with a gate applies on a unit only
/// when that unit's answer lists the row's id as passed (genesis_prime/game/cast `went`).
pub type StruckGate {
  StruckGate(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    prerequisite: Prerequisite,
    tag: spend.Tag,
  )
}

/// What a timed row of a spell changes on its caster: a property of the unit
/// (`unit_properties`), the unit's look (`look`) or the pool of damage the unit absorbs;
/// or, for a UnitPropertyModifier row aimed at other units, a property of the creatures
/// a strike hits.
pub type Change {
  /// A UnitPropertyModifier or UnitPropertyConversion row's change on the caster.
  PropertyChange(modifier: unit_properties.Modifier)
  /// A UnitPropertyModifier row's change (`Spell4Effects.effectType.11.change`) on the
  /// creatures a strike hits, for a row aimed only at other units (targetFlags 2, 4 or 6,
  /// which `aim` names: the primary target, the area or both). A row that includes the
  /// caster as well (3, 5, 7) is a `PropertyChange` and changes the caster only.
  StruckChange(modifier: unit_properties.Modifier, aim: Aim)
  /// A DisguiseOutfit row's change (`Spell4Effects.effectType.112`).
  LookChange(disguise: look.Disguise)
  /// An Absorption row's change (`Spell4Effects.effectType.29`).
  AbsorbChange(absorption: Absorption)
}

/// What an Absorption row (`Spell4Effects.effectType.29`) gives the unit it lands on: a pool
/// of the amount its `formula` gives the caster at the go, which takes the damage types
/// `mask` holds (dataBits04: bit 1 Physical, 2 Tech, 4 Magic), on the unit its targetFlags
/// aim at (`aim`: the caster, or the primary target, which a spell cast on the caster
/// makes the caster).
pub type Absorption {
  Absorption(formula: damage.Formula, mask: Int, aim: Aim)
}

/// A UnitPropertyModifier effect (`Spell4Effects.effectType.11`), a
/// UnitPropertyConversion effect (`Spell4Effects.effectType.145`), a DisguiseOutfit
/// effect (`Spell4Effects.effectType.112`) or an Absorption effect
/// (`Spell4Effects.effectType.29`) of a spell whose
/// targetFlags include the caster: the change it makes to the caster (`change`), its delay, durationTime and flags bit 2 (`row`, which also give the
/// caster's node of the cast its life, as a Fluff effect's do), the phases of
/// `phase_flags` it applies in, when its `condition` holds (its caster apply
/// prerequisite against the caster, its target apply prerequisite against the caster
/// as the only unit it reaches), and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). A type 11 row aimed only at other units (2, 4, 6) is a
/// `StruckChange` on the creatures a strike hits; any other row aimed only at other
/// units is not read, and the part of a row's aim that is not the caster is not applied
/// (`effect_kind.is_row_read`).
pub type PropertyModifier {
  PropertyModifier(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    change: Change,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
    armor: Option(InterruptArmor),
  )
}

/// What a ModifyInterruptArmor row (`Spell4Effects.effectType.52`) adds to the change of
/// property 44 it makes, which the player's armor follows. `points` is dataBits00,
/// `takes_back` is dataBits01 (1 takes the points back when the row ends, 0 keeps the
/// armor: it matters only once armor is worn, and nothing wears a player's armor down yet)
/// and `aim` is the unit the row's targetFlags name: the caster, or the primary target,
/// which a spell cast on the caster makes the caster.
pub type InterruptArmor {
  InterruptArmor(points: Int, takes_back: Bool, aim: Aim)
}

/// A CCStateSet effect (`Spell4Effects.effectType.4`) of a spell: the unit it aims
/// at (the primary target, the area or both), its `row` (state, delay, duration and
/// the armor it removes), the phases of `phase_flags` it fires in, and the `tag` that
/// chooses it by the points the cast spent (genesis_prime/game/spend). Its dataBits
/// beyond the state, the armor and the helper spell of dataBits07 need no handling
/// (`Spell4Effects.effectType.4`), and it has no apply prerequisite. `move` is the
/// move a Knockback, Pushback or Pull state throws its creature by: the helper
/// spell's own ForcedMove row (`helper_move_of`), or `None` for any other state and for
/// a spell that holds its own throw of the units it strikes.
pub type CrowdControl {
  CrowdControl(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    row: crowd_control.Row,
    condition: Condition,
    tag: spend.Tag,
    move: Option(forced_move.Move),
  )
}

/// A Fluff effect (`Spell4Effects.effectType.17`), Scale effect (18), ItemVisualSwap effect
/// (76), RavelSignal effect (81), area ShieldOverload effect (64) or caster-aimed FullScreenEffect
/// effect (95) of a spell: it names the unit it aims at in the go's target info and gives the
/// spell a life there, from its `row`, in the phases of `phase_flags`, when its
/// `condition` holds (its caster apply prerequisite against the caster, its target
/// apply prerequisite against each unit the row reaches), and when its `tag` holds for the points
/// the cast spent (genesis_prime/game/spend). Its dataBits need no handling: the client
/// resizes the unit of a Scale effect itself (`Spell4Effects.effectType.18`), swaps and
/// restores the visual of an ItemVisualSwap effect itself (`Spell4Effects.effectType.76`),
/// and a RavelSignal effect is only a life (`Spell4Effects.effectType.81`); the client marks a
/// ShieldOverload unit itself (`Spell4Effects.effectType.64`), and draws a FullScreenEffect itself
/// (`Spell4Effects.effectType.95`).
pub type Lasting {
  Lasting(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A Heal (`Spell4Effects.effectType.10`) or HealShields (`.118`) effect of a spell whose
/// targetFlags reach the caster (`effect_kind.is_row_read`): the unit it heals (`aim`: the caster,
/// or the primary target of a spell cast on the caster), the phases of `phase_flags` it
/// applies in, when its `condition` holds (its caster apply prerequisite against the
/// caster, its target apply prerequisite against the unit it heals), and when its `tag`
/// holds for the points the cast spent (genesis_prime/game/spend). The part of a row's
/// aim that is not the caster is not applied (`effect_kind.is_row_read`).
pub type Heal {
  /// A heal that lands once, `delay_ms` after its go, by `formula` read for the caster
  /// (genesis_prime/game/damage `value_on_caster`).
  Heal(
    effect_id: Spell4EffectsId,
    vital: effect_kind.Vital,
    phase_flags: Int,
    aim: Aim,
    condition: Condition,
    tag: spend.Tag,
    formula: damage.Formula,
    delay_ms: Int,
  )
  /// A heal at each tick of `schedule` (Spell4Effects.tickTime, delayTime and
  /// durationTime), by `formula` read for the caster as it is at the tick, each tick its
  /// own 0x7f8 (`Spell4Effects.effectType.10`, `.118`).
  TickingHeal(
    effect_id: Spell4EffectsId,
    vital: effect_kind.Vital,
    phase_flags: Int,
    aim: Aim,
    condition: Condition,
    tag: spend.Tag,
    formula: damage.Formula,
    schedule: ticking.Schedule,
  )
}

/// A SpellForceRemove effect (`Spell4Effects.effectType.80`) of a spell: it takes
/// `count` stacks of the casts `selector` names off the unit it aims at, in the
/// phases of `phase_flags`, when its `condition` holds (as a Fluff effect's does), and
/// when its `tag` holds for the points the cast spent (genesis_prime/game/spend).
pub type ForceRemove {
  ForceRemove(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    selector: lasting.Selector,
    count: Int,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// One innate cost of a spell, as the client's check reads its type
/// (`0x1403b3320`).
pub type Cost {
  /// `amount` points of resource slot `slot`: refused with `result` when the slot,
  /// as a whole number, holds less (both as absolute values).
  SlotCost(slot: Int, amount: Int, result: Int)
  /// `amount` points of the class vital `vital`, found among the casting class's
  /// slots when the press is checked (genesis_prime/game/class_resource
  /// `class_cost`, `0x1405e7980`): it passes at the first slot naming the vital
  /// whose value less `amount` lies between 0 and the slot's maximum, else is refused
  /// with the last such slot's result; a class with no such slot passes and pays
  /// nothing.
  ClassVitalCost(vital: Int, amount: Int)
  /// `amount` points of the class vital `vital` on a stage's threshold row, checked
  /// as the client checks a row's cost (genesis_prime/game/class_resource
  /// `row_class_cost`, `0x1403c0620`): the points held must be at least `amount`,
  /// with no maximum, and a refusal is the vital slot's result or 175.
  RowClassCost(vital: Int, amount: Int)
  /// A cost in a vital no rule of the server holds (health, shield or focus):
  /// refused with `result`, and logged once.
  UnheldCost(result: Int)
  /// A slot cost whose Spell4 EMM id the server reads as a spend of every point
  /// held (genesis_prime/game/spend `AllHeld`): refused with `result` when the slot
  /// holds fewer whole points than the base `amount`, else it takes every whole
  /// point held, and the points above `amount` are the cast's n.
  SpendAllCost(slot: Int, amount: Int, result: Int)
  /// A cost with an EMM id no rule reads, on a cost that is not a slot cost, or on no
  /// cost at all: refused with `result` (the cost's own, 285 for no cost), and logged
  /// once.
  UnreadSpendCost(result: Int, emm_id: Int)
}

/// One caster vital requirement (`0x1403b1780`): resource slot `slot`, or its
/// percentage of its maximum, compared with `value`; refused with `result`.
pub type Requirement {
  Requirement(
    slot: Int,
    measure: Measure,
    comparison: Comparison,
    value: Int,
    result: Int,
  )
}

/// What a requirement compares: the slot's amount (evals 0 to 4) or its
/// percentage of its maximum (above 4) (`0x1403b1780`).
pub type Measure {
  Amount
  PercentOfMax
}

/// How a requirement compares, by its eval code (`0x1407a1750`).
pub type Comparison {
  /// 0 and 5.
  Equal
  /// 1 and 6.
  Greater
  /// 2 and 7.
  AtLeast
  /// 3 and 8.
  Less
  /// 4 and 9.
  AtMost
  /// Any other code, which never passes.
  NeverPasses(eval: Int)
}

/// One Proxy effect of a spell: the effect row that names the child, when the
/// child starts, and the child's own tree.
pub type Proxy {
  Proxy(
    effect_id: Spell4EffectsId,
    /// Spell4Effects.delayTime: after the go of the phase it fires in.
    delay_ms: Int,
    /// Spell4Effects.phaseFlags: bit n is phase n; -1 every phase.
    phase_flags: Int,
    condition: Condition,
    /// The Proxy starts when its tag holds for the points the cast spent
    /// (genesis_prime/game/spend).
    tag: spend.Tag,
    /// Which unit the child cast is made on, from the effect's `targetFlags`.
    target: ProxyTarget,
    spell: Spell,
    /// The first phase's gains of a child started at each struck unit, given once
    /// at the go of the parent whose units it struck; none for a child on the
    /// caster.
    gains: List(Gain),
  )
}

/// The payload of one effect row of a planned spell, by what the row does. `planned` makes
/// the row's envelope (`genesis_prime/game/spell_effect`) from it, and `rank` fixes its place
/// in the spell's list.
pub type Kind {
  /// A Proxy row: the child spell it starts and when.
  ProxyEffect(proxy: Proxy)
  /// A resource gain the caster is given at a go (`Gain`).
  GainEffect(gain: Gain)
  /// A Fluff, Scale, ItemVisualSwap, RavelSignal, area ShieldOverload or caster-aimed FullScreenEffect row, which gives the spell a life on a unit (`Lasting`).
  LastingEffect(lasting: Lasting)
  /// A SpellForceRemove row, which takes casts off a unit (`ForceRemove`).
  RemoveEffect(remove: ForceRemove)
  /// A property modifier, conversion, disguise, absorb or interrupt armor row (`PropertyModifier`); one with `armor` ranks after the plain ones.
  ModifierEffect(modifier: PropertyModifier)
  /// A ForcedMove row aimed at the caster, which the go lists and the caster's client carries out (`ForcedMove`).
  ForcedMoveEffect(forced_move: ForcedMove)
  /// A ForcedMove row aimed at other units, which the go throws the creatures it hit with (`StruckMove`).
  StruckMoveEffect(struck_move: StruckMove)
  /// A DespawnUnit row aimed past the caster, which the go tells the creatures it hit to leave the field at (`Despawn`).
  DespawnEffect(despawn: Despawn)
  /// A UnitStateSet row aimed past the caster, which the go tells the creatures it hit to hold the state of (`UnitState`).
  UnitStateEffect(unit_state: UnitState)
  /// A ModifySpellCooldown row aimed at the caster (`CooldownModifier`).
  CooldownEffect(modifier: CooldownModifier)
  /// A Stealth row aimed at the caster, a stealth the cast holds on it (`StealthRow`).
  StealthEffect(stealth: StealthRow)
  /// A RemoveStealth row aimed at the caster, which ends every stealth it holds (`RemoveStealthRow`).
  RemoveStealthEffect(remove: RemoveStealthRow)
  /// A Proc row aimed at the caster, whose kind is one of the holder's own events, with the spell it casts (`ProcRow`).
  ProcEffect(proc: ProcRow)
  /// A Heal or HealShields row that reaches the caster, which refills its health or shield (`Heal`).
  HealEffect(heal: Heal)
  /// A CCStateSet row that holds a state on a unit: a stun or a knockdown on a creature, or Ability Restriction on the caster (`controls_in_phase`, `restrictions_in_phase`).
  ControlEffect(control: CrowdControl)
  /// An NpcExecutionDelay row aimed at the caster with a duration, which holds a creature caster still after a go (`Delay`); a player's cast applies none.
  DelayEffect(delay: Delay)
  /// A QuestAdvanceObjective row that reaches the caster, which advances a quest objective of the player (`QuestAdvance`).
  QuestAdvanceEffect(quest_advance: QuestAdvance)
}

/// The effect a payload is: its row, phases and tag, read from the payload itself.
pub fn effect_of(kind kind: Kind) -> PlannedEffect(Kind) {
  case kind {
    ProxyEffect(proxy:) ->
      PlannedEffect(
        effect_id: proxy.effect_id,
        phase_flags: proxy.phase_flags,
        tag: proxy.tag,
        kind:,
      )
    GainEffect(gain:) ->
      PlannedEffect(
        effect_id: gain.effect_id,
        phase_flags: gain.phase_flags,
        tag: gain.tag,
        kind:,
      )
    LastingEffect(lasting:) ->
      PlannedEffect(
        effect_id: lasting.effect_id,
        phase_flags: lasting.phase_flags,
        tag: lasting.tag,
        kind:,
      )
    RemoveEffect(remove:) ->
      PlannedEffect(
        effect_id: remove.effect_id,
        phase_flags: remove.phase_flags,
        tag: remove.tag,
        kind:,
      )
    ModifierEffect(modifier:) ->
      PlannedEffect(
        effect_id: modifier.effect_id,
        phase_flags: modifier.phase_flags,
        tag: modifier.tag,
        kind:,
      )
    ForcedMoveEffect(forced_move:) ->
      PlannedEffect(
        effect_id: forced_move.effect_id,
        phase_flags: forced_move.phase_flags,
        tag: forced_move.tag,
        kind:,
      )
    StruckMoveEffect(struck_move:) ->
      PlannedEffect(
        effect_id: struck_move.effect_id,
        phase_flags: struck_move.phase_flags,
        tag: struck_move.tag,
        kind:,
      )
    DespawnEffect(despawn:) ->
      PlannedEffect(
        effect_id: despawn.effect_id,
        phase_flags: despawn.phase_flags,
        tag: despawn.tag,
        kind:,
      )
    UnitStateEffect(unit_state:) ->
      PlannedEffect(
        effect_id: unit_state.effect_id,
        phase_flags: unit_state.phase_flags,
        tag: unit_state.tag,
        kind:,
      )
    CooldownEffect(modifier:) ->
      PlannedEffect(
        effect_id: modifier.effect_id,
        phase_flags: modifier.phase_flags,
        tag: modifier.tag,
        kind:,
      )
    StealthEffect(stealth:) ->
      PlannedEffect(
        effect_id: stealth.effect_id,
        phase_flags: stealth.phase_flags,
        tag: stealth.tag,
        kind:,
      )
    RemoveStealthEffect(remove:) ->
      PlannedEffect(
        effect_id: remove.effect_id,
        phase_flags: remove.phase_flags,
        tag: remove.tag,
        kind:,
      )
    ProcEffect(proc:) ->
      PlannedEffect(
        effect_id: proc.effect_id,
        phase_flags: proc.phase_flags,
        tag: proc.tag,
        kind:,
      )
    HealEffect(heal:) ->
      PlannedEffect(
        effect_id: heal.effect_id,
        phase_flags: heal.phase_flags,
        tag: heal.tag,
        kind:,
      )
    ControlEffect(control:) ->
      PlannedEffect(
        effect_id: control.effect_id,
        phase_flags: control.phase_flags,
        tag: control.tag,
        kind:,
      )
    DelayEffect(delay:) ->
      PlannedEffect(
        effect_id: delay.effect_id,
        phase_flags: delay.phase_flags,
        tag: delay.tag,
        kind:,
      )
    QuestAdvanceEffect(quest_advance:) ->
      PlannedEffect(
        effect_id: quest_advance.effect_id,
        phase_flags: quest_advance.phase_flags,
        tag: quest_advance.tag,
        kind:,
      )
  }
}

/// A spell's effect rows in the order of its list: by the rank of their kinds, the order
/// the cast's gates draw their rolls in (`cast/gate.rolls_needed`): the Proxies, the gains,
/// the lasting rows, the removes, the property changes (those with armor after the plain
/// ones), the caster's forced moves, the struck units' moves, the cooldown changes, the
/// stealth rows, the stealth removals, the procs, the heals, the crowd-control rows and the despawns;
/// the rows of one kind keep the order they came in (row order).
pub fn ranked(
  effects effects: List(PlannedEffect(Kind)),
) -> List(PlannedEffect(Kind)) {
  spell_effect.ranked(effects, rank:)
}

/// Where the kind sorts among a plan's effects, in tens: every property change shares one
/// rank, so the effects of one kind are the effects of one rank.
pub fn kind_rank(kind kind: Kind) -> Int {
  case kind {
    ProxyEffect(..) -> 10
    GainEffect(..) -> 20
    LastingEffect(..) -> 30
    RemoveEffect(..) -> 40
    ModifierEffect(..) -> 50
    ForcedMoveEffect(..) -> 60
    StruckMoveEffect(..) -> 70
    CooldownEffect(..) -> 80
    StealthEffect(..) -> 90
    RemoveStealthEffect(..) -> 100
    ProcEffect(..) -> 110
    HealEffect(..) -> 120
    ControlEffect(..) -> 130
    DespawnEffect(..) -> 140
    UnitStateEffect(..) -> 150
    DelayEffect(..) -> 160
    QuestAdvanceEffect(..) -> 170
  }
}

/// The sort key of an effect: its kind's rank, a property change with armor 5 after one
/// without.
fn rank(kind kind: Kind) -> Int {
  let armored = case kind {
    ModifierEffect(modifier:) -> option.is_some(modifier.armor)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> False
  }
  case armored {
    True -> kind_rank(kind:) + 5
    False -> kind_rank(kind:)
  }
}

/// The payload of an effect of kind `ProxyEffect`, and nothing for one of another kind.
pub fn as_proxy(kind kind: Kind) -> Result(Proxy, Nil) {
  case kind {
    ProxyEffect(proxy:) -> Ok(proxy)
    GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `GainEffect`, and nothing for one of another kind.
pub fn as_gain(kind kind: Kind) -> Result(Gain, Nil) {
  case kind {
    GainEffect(gain:) -> Ok(gain)
    ProxyEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `LastingEffect`, and nothing for one of another kind.
pub fn as_lasting(kind kind: Kind) -> Result(Lasting, Nil) {
  case kind {
    LastingEffect(lasting:) -> Ok(lasting)
    ProxyEffect(..)
    | GainEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `RemoveEffect`, and nothing for one of another kind.
pub fn as_remove(kind kind: Kind) -> Result(ForceRemove, Nil) {
  case kind {
    RemoveEffect(remove:) -> Ok(remove)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `ModifierEffect`, and nothing for one of another kind.
pub fn as_modifier(kind kind: Kind) -> Result(PropertyModifier, Nil) {
  case kind {
    ModifierEffect(modifier:) -> Ok(modifier)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `ForcedMoveEffect`, and nothing for one of another kind.
pub fn as_forced_move(kind kind: Kind) -> Result(ForcedMove, Nil) {
  case kind {
    ForcedMoveEffect(forced_move:) -> Ok(forced_move)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `StruckMoveEffect`, and nothing for one of another kind.
pub fn as_struck_move(kind kind: Kind) -> Result(StruckMove, Nil) {
  case kind {
    StruckMoveEffect(struck_move:) -> Ok(struck_move)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `DespawnEffect`, and nothing for one of another kind.
pub fn as_despawn(kind kind: Kind) -> Result(Despawn, Nil) {
  case kind {
    DespawnEffect(despawn:) -> Ok(despawn)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `UnitStateEffect`, and nothing for one of another kind.
pub fn as_unit_state(kind kind: Kind) -> Result(UnitState, Nil) {
  case kind {
    UnitStateEffect(unit_state:) -> Ok(unit_state)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | DespawnEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `CooldownEffect`, and nothing for one of another kind.
pub fn as_cooldown_modifier(kind kind: Kind) -> Result(CooldownModifier, Nil) {
  case kind {
    CooldownEffect(modifier:) -> Ok(modifier)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `StealthEffect`, and nothing for one of another kind.
pub fn as_stealth(kind kind: Kind) -> Result(StealthRow, Nil) {
  case kind {
    StealthEffect(stealth:) -> Ok(stealth)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `RemoveStealthEffect`, and nothing for one of another kind.
pub fn as_remove_stealth(kind kind: Kind) -> Result(RemoveStealthRow, Nil) {
  case kind {
    RemoveStealthEffect(remove:) -> Ok(remove)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `ProcEffect`, and nothing for one of another kind.
pub fn as_proc(kind kind: Kind) -> Result(ProcRow, Nil) {
  case kind {
    ProcEffect(proc:) -> Ok(proc)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `HealEffect`, and nothing for one of another kind.
pub fn as_heal(kind kind: Kind) -> Result(Heal, Nil) {
  case kind {
    HealEffect(heal:) -> Ok(heal)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `ControlEffect`, and nothing for one of another kind.
pub fn as_control(kind kind: Kind) -> Result(CrowdControl, Nil) {
  case kind {
    ControlEffect(control:) -> Ok(control)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `DelayEffect`, and nothing for one of another kind.
pub fn as_delay(kind kind: Kind) -> Result(Delay, Nil) {
  case kind {
    DelayEffect(delay:) -> Ok(delay)
    ProxyEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..)
    | QuestAdvanceEffect(..) -> Error(Nil)
  }
}

/// The payload of an effect of kind `QuestAdvanceEffect`, and nothing for one of another kind.
pub fn as_quest_advance(kind kind: Kind) -> Result(QuestAdvance, Nil) {
  case kind {
    QuestAdvanceEffect(quest_advance:) -> Ok(quest_advance)
    ProxyEffect(..)
    | DelayEffect(..)
    | GainEffect(..)
    | LastingEffect(..)
    | RemoveEffect(..)
    | ModifierEffect(..)
    | ForcedMoveEffect(..)
    | StruckMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | ProcEffect(..)
    | HealEffect(..)
    | ControlEffect(..)
    | DespawnEffect(..)
    | UnitStateEffect(..) -> Error(Nil)
  }
}

/// Where a spell is planned, which three of an effect row's refusals depend on: a spell a
/// Proxy starts on each struck unit (`struck_by`), a spell that spends every point held
/// (`spends_all`) and a spell that hits foes (`hits_foes`, `spell_hits_foes`). A fourth
/// field is not a refusal: a spell that throws the units it strikes by its own ForcedMove
/// row (`throws_target`, `spell_throws_target`) reads its crowd control states without a
/// move.
pub type RowPlace {
  RowPlace(
    struck_by: Option(StruckBy),
    spends_all: Bool,
    hits_foes: Bool,
    throws_target: Bool,
  )
}

/// Whether a spell throws the units it strikes by a ForcedMove row of its own: one of
/// its type 3 rows is read as aimed past the caster (`effect_kind.is_row_read`, targetFlags
/// 2, 4 or 6). Such a spell moves its creature once, by that row: a spell holding its own
/// throw drops the state's helper.
fn spell_throws_target(
  effects effects: List(spell4_effects.Spell4Effects),
) -> Bool {
  list.any(effects, fn(effect) {
    effect_kind.kind_of(effect_type: effect.effect_type)
    == effect_kind.ForcedMove
    && effect.target_flags >= 2
    && effect_kind.is_row_read(
      effect_type: effect.effect_type,
      target_flags: effect.target_flags,
    )
  })
}

/// The Spell4 ids of the spells that throw the units they strike (`spell_throws_target`),
/// among the Spell4Effects rows given.
pub fn spells_that_throw_target(
  effects effects: List(spell4_effects.Spell4Effects),
) -> Set(Int) {
  list.fold(effects, set.new(), fn(found, effect) {
    case spell_throws_target(effects: [effect]) {
      True -> set.insert(found, effect.spell_id)
      False -> found
    }
  })
}

/// Whether a spell hits foes, from its own Spell4Effects rows: one of its damage (8) or
/// crowd control (4) rows has a targetFlags from 2 to 7, which names the primary target or
/// the area.
///
/// [F] What "hits foes" means is the server's choice, made by Jim: the client's tables
/// hold no flag for it. A spell that hits none has an area the server reads as a friendly
/// spell's, which waits for #834 ("A friendly spell's area finds the caster's allies").
pub fn spell_hits_foes(
  effects effects: List(spell4_effects.Spell4Effects),
) -> Bool {
  list.any(effects, fn(effect) {
    let kind = effect_kind.kind_of(effect_type: effect.effect_type)
    { kind == effect_kind.Damage || kind == effect_kind.CrowdControl }
    && effect.target_flags >= 2
    && effect.target_flags <= 7
  })
}

/// The Spell4 ids of the spells that hit foes (`spell_hits_foes`), among the Spell4Effects
/// rows given.
pub fn spells_that_hit_foes(
  effects effects: List(spell4_effects.Spell4Effects),
) -> Set(Int) {
  list.fold(effects, set.new(), fn(found, effect) {
    case spell_hits_foes(effects: [effect]) {
      True -> set.insert(found, effect.spell_id)
      False -> found
    }
  })
}

/// The Proxy that starts a spell as a child on each unit its area strikes: `spell4_id`
/// is the spell with the Proxy effect `proxy_effect_id`. The child's primary target is
/// then a struck unit (`target_of`).
pub type StruckBy {
  StruckBy(spell4_id: Int, proxy_effect_id: Int)
}

/// What the plan makes of one Spell4Effects row (`read_row`), the one decision the plan's
/// lists and the coverage measure both take from.
pub type RowReading {
  /// The row is in a list of its spell and a go applies it: the coverage measure counts
  /// it read.
  Applied(row: ReadRow)
  /// The row is in a list of its spell and no go applies it: a periodic gain
  /// (`TickingGain`), a property change or disguise with no life
  /// (`lasting.has_life`), an ItemVisualSwap row with a delayTime (the go lists it, the
  /// client applies an effect from the go only when its delay is 0; the gap is #827) and a row whose
  /// phaseFlags is 0, which no phase selects (`in_phase`). The measure counts it not read.
  Held(row: ReadRow)
  /// The row is in no list of its spell and the load goes on.
  LeftOut(why: LeftOutReason)
  /// A damage row: the area load reads it (genesis_prime/game/spell_area `damage_row_of`),
  /// and the plan holds it in no list.
  ReadByArea
  /// An Activate row: the activate plan lists it (genesis_prime/game/activate), and the
  /// ability's plan holds it in no list.
  ReadByActivation
}

/// Why a row is in no list of its spell.
pub type LeftOutReason {
  /// No rule of the server reads the effect type (`effect_kind.Unread`).
  TypeNotRead
  /// The type is read for the rows that reach the caster (or, for an overload, the area;
  /// for a property modifier, struck units too) and this row's targetFlags do not
  /// (`effect_kind.is_row_read`).
  AimedAtOtherUnits
  /// A Proc of a kind the holder's own events do not make (`proc_read`).
  ProcOfAnotherKind(kind: Int)
  /// A Proc of a kind the server knows a reading for and cannot raise yet: it waits on
  /// the open issue (`proc_read`).
  ProcKindWaits(kind: Int, issue: Int)
  /// A Proc whose targetFlags are not the caster's alone: it lands on the spell's target
  /// or a struck unit, so a unit other than the caster holds it, which no rule of the
  /// server holds yet (issue 829).
  ProcHeldByAnotherUnit(target_flags: Int)
  /// A Proc behind a caster or target persistence prerequisite, which no rule checks
  /// while a proc is held (`Spell4Effects.effectType.14.prerequisites`).
  ProcBehindPersistence
  /// A Proc behind a target apply prerequisite, which no rule checks for a proc.
  ProcBehindTargetApply
  /// A Proc that names a group (dataBits08) with no filter kind (dataBits07 0), which
  /// nothing explains (`Spell4Effects.effectType.14.dataBits07`).
  ProcGroupWithoutFilter
  /// A Proc whose dataBits03 holds a bit of 32 or above, which the texts do not name.
  ProcAimNotRead(data_bits03: Int)
  /// A Proc with no durationTime and no flags bit 2, which gives its holder's node no
  /// life (`Spell4Effects.effectType.14.lifetime`).
  ProcWithoutLife
  /// A Proc whose dataBits01 names a spell the Spell4 table has no row for, so it can cast
  /// nothing. The client never reads a Proc row, so its table keeps such a name and the
  /// holder spell still casts: the row is left out, as a Proxy that names no spell is.
  ProcCastsNoSpell(spell4_id: Int)
  /// A Proxy whose dataBits00 names no spell.
  ProxyNamesNoSpell
  /// A damage row whose phaseFlags is 0: no phase selects it (`spell_area` `phase`).
  InNoPhase
  /// A CCStateSet row aimed at another unit that holds its state until removed
  /// (`Spell4Effects.flags` bit 2), which no rule of the server ends when its spell ends
  /// (the issue "A crowd-control state that lasts until removed ends when its spell
  /// ends"): the plan drops the row, the rest of the spell plans, and the cast logs the
  /// gap (`Spell.dropped_controls`).
  StateUntilRemovedNotRead
  /// A periodic Heal or HealShields row that lasts until removed (`Spell4Effects.flags`
  /// bit 2), which no schedule ends (issue 803).
  HealUntilRemoved
  /// A DespawnUnit row (`Spell4Effects.effectType.97`) whose `column` (dataBits00 or
  /// dataBits01) is not 0: no code of the client reads either column of this type, so what a
  /// value means is not known and the row removes nothing.
  DespawnDataNotRead(column: String)
  /// A DespawnUnit row aimed at the caster alone: only a creature caster could be removed by
  /// it, and a creature's casts are not read, and a player is never removed.
  DespawnAimedAtTheCasterOnly
  /// A UnitStateSet row (`Spell4Effects.effectType.15`) aimed at the caster alone: a player's
  /// own state needs a creature's strike to read it, and a creature's casts are not read.
  UnitStateAimedAtTheCasterOnly
  /// A UnitStateSet row past the caster that lasts until removed (`Spell4Effects.flags` bit 2),
  /// which no schedule ends.
  UnitStateUntilRemoved
  /// A UnitStateSet row past the caster behind a persistence prerequisite
  /// (`Spell4Effects.prerequisiteIdTargetPersistence`), which no creature checks for a state.
  UnitStateBehindPersistence
  /// A UnitStateSet row whose `column` (dataBits01 to dataBits09) is not 0: no code of the
  /// client reads the type, so what a value means is not known and the row holds nothing.
  UnitStateDataNotRead(column: String)
  /// An NpcExecutionDelay row (`Spell4Effects.effectType.35`) aimed at a unit other than the
  /// caster alone: no creature rule holds another unit still.
  DelayOnAnotherUnit
  /// An NpcExecutionDelay row with no durationTime, which holds its caster still for
  /// nothing.
  DelayHasNoDuration
  /// A QuestAdvanceObjective row (`Spell4Effects.effectType.42`) whose `column` is not 0: no
  /// code of the client reads the type, so what a value means is not known and the row
  /// advances nothing.
  QuestAdvanceColumnNotRead(column: String)
  /// A QuestAdvanceObjective row whose amount (dataBits02) is below 1, which advances nothing.
  QuestAdvanceAddsNothing
}

/// A row as its spell holds it. A Proxy's child and a Proc's spell are planned from the
/// reading, by the spell that holds the row.
pub type ReadRow {
  /// The effects the row plans, in order: one, or for a row aimed at the caster and at
  /// other units two, the part on the caster first and the part past it second. Both keep
  /// the row's effect id, which the coverage measure counts once.
  ReadEffects(effects: List(PlannedEffect(Kind)))
  /// A Proc row, whose spell the spell that holds it plans.
  ReadProc(
    reading: ProcReading,
    condition: Condition,
    event_gate: Option(Prerequisite),
    holder_gate: Option(Prerequisite),
  )
  /// A Proxy row: the units it starts its child on, the caster, each struck unit or both
  /// (`target_of`), with one `Proxy` of the spell for each.
  ReadProxy(targets: List(ProxyTarget), condition: Condition)
}

/// Why a DisguiseOutfit row cannot be drawn with 0x933 (`Spell4Effects.effectType.112`).
pub type DisguiseGap {
  /// dataBits00 or dataBits08 names an outfit, which only 0x905 draws.
  OutfitNeedsMessage0x905
  /// Neither dataBits01 nor dataBits02 names an ItemDisplay.
  NamesNoDisplay
  /// The display's item type has no ItemSlot (itemSlotId 0).
  DisplayHasNoSlot(item_display_id: Int)
}

/// The kind of effect row whose parameter the plan does not read (`ParameterNotRead`).
pub type ParameterRow {
  /// A Heal or HealShields row.
  HealRow
  /// An Absorption row.
  AbsorptionRow
  /// A UnitPropertyModifier row.
  ModifierRow
}

/// Why the plans cannot be built from the tables.
pub type PlanError {
  /// A table row the tree names is missing: the table, and the id.
  NoRow(table: String, id: Int)
  /// A Proxy effect of a tree is aimed by a flag value that is not read.
  ProxyAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// The Proxy effects of a spell lead back to a spell on the way to it: the
  /// Spell4 ids from the pressed ability to the one that repeats.
  ProxyCycle(chain: List(Int))
  /// A spell's innate cost is of a type whose check the client's code was not
  /// read for (`0x1403b3320`).
  UnreadCost(spell4_id: Int, cost_type: Int)
  /// A spell's caster vital requirement is of a type whose vital the server does
  /// not read (`0x1403b1780`).
  UnreadRequirement(spell4_id: Int, requirement_type: Int)
  /// A Channeled spell's channelPulseTime is 0, which gives no count of gos
  /// (`0x14053d1f0`).
  ChannelWithoutPulse(spell4_id: Int)
  /// A RapidTap or ChargeRelease ability's thresholdTime is 0, which the client
  /// refuses a press of with 285 (`0x1403bfd60`).
  NoThresholdTime(spell4_id: Int)
  /// A VitalModifier of a tree is aimed other than at the caster, which is not read.
  GainAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A VitalModifier of a tree changes a vital other than 6 or 8, which is not read.
  GainVitalNotRead(spell4_id: Int, effect_id: Int, vital: Int)
  /// An effect of a tree is behind a target apply prerequisite, or, for a lasting, remove,
  /// modifier or heal row, a caster apply prerequisite, with a condition of a type the
  /// server has not decoded (`prerequisite.unread_types`): the issue "The prerequisite
  /// types effects use that the server does not read yet are read" (#818) reads them.
  ApplyPrerequisiteNotRead(
    spell4_id: Int,
    effect_id: Int,
    prerequisite_type: Int,
  )
  /// An effect of a tree aimed past the caster is behind a target apply prerequisite with a
  /// condition that reads what a struck creature holds, and nobody can check it: either the
  /// casts held on it, which the creature does not hold yet (`prerequisite.struck_unread_types`,
  /// issue 569), or the creature's own state, on a row that does not reach struck units alone
  /// or that the strike does not carry, so the caster's check is the only one and it holds none
  /// of that state (`prerequisite.unread_on_a_struck_unit`, issue 851).
  TargetPrerequisiteReadsStruckUnit(
    spell4_id: Int,
    effect_id: Int,
    prerequisite_type: Int,
  )
  /// A ForcedMove effect aimed at the units a strike hits holds columns that are no move
  /// (`forced_move.of_row`).
  StruckMoveNotRead(spell4_id: Int, effect_id: Int, error: forced_move.RowError)
  /// A Knockback, Pushback or Pull state names a helper spell (`helper_move_of`) that has
  /// no single ForcedMove row aimed at the units a strike hits, with no apply prerequisite:
  /// its move is then not known.
  ControlHelperNotRead(spell4_id: Int, effect_id: Int, helper: Int)
  /// An effect of a spell that spends every point held holds an emmComparison other
  /// than 0 or 1, which chooses nothing (`Spell4Effects.emmComparison`).
  SpendComparisonNotRead(spell4_id: Int, effect_id: Int, comparison: Int)
  /// A SpellForceRemove effect of a tree has a dataBits00 other than 1, 2 or 3,
  /// which names no group, Spell4 or Spell4Base to take off
  /// (`Spell4Effects.effectType.80`).
  ForceRemoveSelectorNotRead(spell4_id: Int, effect_id: Int, selector: Int)
  /// A SpellForceRemove effect of a tree has a dataBits03 that differs from its
  /// dataBits04: which is the count of stacks is not settled
  /// (`Spell4Effects.effectType.80`).
  ForceRemoveCountsDiffer(
    spell4_id: Int,
    effect_id: Int,
    data_bits03: Int,
    data_bits04: Int,
  )
  /// A Fluff, SpellForceRemove, Scale, ItemVisualSwap or RavelSignal effect of a tree is aimed by a flag
  /// value that is not read (`Spell4Effects.targetFlags`).
  LastingAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A CCStateSet effect of a tree holds a value that is no state of
  /// `Unit.CodeEnumCCState` (0 to 27).
  ControlStateNotRead(spell4_id: Int, effect_id: Int, state: Int)
  /// A CCStateSet effect of a tree is aimed by a flag value `aim_of` does not read
  /// (`Spell4Effects.targetFlags` 0, or a value with bit 8).
  ControlAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// An effect of a spell that hits no foes (`spell_hits_foes`) is aimed by a flag value
  /// that holds the caster's bit and the area's bit (5 or 7), and the effect's kind keeps a
  /// state or a child on the area's units: a friendly spell's area finds the caster's
  /// allies, which the issue "A friendly spell's area finds the caster's allies" (#834)
  /// builds.
  FriendlyAreaNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A CCStateSet effect of a tree aimed at another unit keeps its state through a death
  /// or a leave by a caster persistence, target persistence or target suspend
  /// prerequisite, which no rule of the server holds (the issue "An effect behind an
  /// apply prerequisite lands only on the units that pass it" closes it).
  ControlPersistenceNotRead(spell4_id: Int, effect_id: Int)
  /// A UnitPropertyModifier or UnitPropertyConversion effect of a tree names a property
  /// that UnitProperty2 has no row for, which the client's 0x93a refuses from id 197
  /// (`opcode.0x93a`).
  ModifierPropertyHasNoRow(spell4_id: Int, effect_id: Int, property: Int)
  /// A UnitPropertyModifier effect of a tree has a multiplier, flat amount or per-level
  /// amount, or a UnitPropertyConversion effect a share, that is not a finite number:
  /// `column` is its dataBits column.
  ModifierNumberNotFinite(spell4_id: Int, effect_id: Int, column: String)
  /// A ModifySpellCooldown effect of a tree has a dataBits03 that is not a finite
  /// number, for an operation that reads it (`Spell4Effects.effectType.73`).
  CooldownNumberNotFinite(spell4_id: Int, effect_id: Int)
  /// A Stealth or RemoveStealth effect of a tree is aimed other than at the caster
  /// alone, which is not read (`Spell4Effects.targetFlags`).
  StealthAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A Stealth effect of a tree has a delayTime or durationTime: timed stealth is not
  /// built (`Spell4Effects.effectType.83`).
  StealthTimedNotRead(spell4_id: Int, effect_id: Int)
  /// A Stealth effect of a tree has a dataBits02 that is not 0 or 1, the two values that
  /// say whether damage ends it (`Spell4Effects.effectType.83`).
  StealthBreaksNotRead(spell4_id: Int, effect_id: Int, value: Int)
  /// A spell of a tree has a caster or target Spell4Conditions row whose mask holds bit
  /// 16, the client's stealth test, whose refusals 65 and 114 are not checked
  /// (`Spell4Conditions.conditionMask.16`).
  StealthConditionNotRead(spell4_id: Int, spell4_conditions_id: Int)
  /// A spell of a tree has a spellCastStealthChange that is not 0, 1 or 2
  /// (`Spell4.spellCastStealthChange`).
  StealthChangeNotRead(spell4_id: Int, value: Int)
  /// An effect of a tree, of the kind `row`, has a parameter with a factor of type
  /// `parameter_kind` that the plan does not read: for a heal or an absorb, a type the
  /// formula for an effect on its caster does not read (`damage.unread_on_caster`); for a
  /// stat modifier, any type, since the plan takes its amount from the data bits alone
  /// (`Spell4Effects.effectType.11.change`).
  ParameterNotRead(
    spell4_id: Int,
    effect_id: Int,
    row: ParameterRow,
    parameter_kind: Int,
  )
  /// A Heal or HealShields effect of a tree has a dataBits00 that is not a finite 32-bit float.
  HealNumberNotFinite(spell4_id: Int, effect_id: Int)
  /// A periodic Heal or HealShields effect lasts until removed (flags bit 2): its reading
  /// leaves it out (`HealUntilRemoved`, issue 803).
  HealUntilRemovedNotRead(spell4_id: Int, effect_id: Int)
  /// A periodic Heal or HealShields effect lives shorter than one tick
  /// (genesis_prime/game/ticking `NoTick`).
  HealNoTick(spell4_id: Int, effect_id: Int, tick_ms: Int, duration_ms: Int)
  /// A Proxy of a tree starts a child on each unit its area strikes, and the child holds
  /// a Heal or HealShields effect whose aim names its primary target, a struck unit:
  /// `spell4_id` is the spell with the Proxy `proxy_effect_id`, and `effect_id` the heal's row.
  HealOnStruckUnit(spell4_id: Int, proxy_effect_id: Int, effect_id: Int)
  /// A ModifyInterruptArmor effect of a tree has a dataBits01 that is not 0 or 1, the two
  /// values that say whether the armor is taken back when it ends
  /// (`Spell4Effects.effectType.52`).
  InterruptArmorTakeBackNotRead(spell4_id: Int, effect_id: Int, value: Int)
  /// A Proxy of a tree starts a child on each unit its area strikes, and the child holds a
  /// ModifyInterruptArmor effect whose aim names its primary target, a struck unit:
  /// `spell4_id` is the spell with the Proxy `proxy_effect_id`, and `effect_id` the row.
  InterruptArmorOnStruckUnit(
    spell4_id: Int,
    proxy_effect_id: Int,
    effect_id: Int,
  )
  /// An Absorption effect of a tree has a dataBits00 or dataBits01 that is not a finite
  /// 32-bit float.
  AbsorptionNumberNotFinite(spell4_id: Int, effect_id: Int)
  /// An Absorption effect of a tree gives 0 to every caster (`damage.gives_nothing`): which
  /// of dataBits00 and dataBits01 is the amount when the other is 0 is not known
  /// (`Spell4Effects.effectType.29`).
  AbsorptionAmountNotRead(spell4_id: Int, effect_id: Int)
  /// An Absorption effect of a tree has a tickTime: a periodic absorb's reading is not known
  /// (`Spell4Effects.effectType.29`).
  AbsorptionPeriodic(spell4_id: Int, effect_id: Int, tick_ms: Int)
  /// An Absorption effect of a tree has neither a durationTime nor flags bit 2: an absorb
  /// with no lifetime is not known (`Spell4Effects.effectType.29`).
  AbsorptionHasNoLifetime(spell4_id: Int, effect_id: Int)
  /// A Proxy of a tree starts a child on each unit its area strikes, and the child holds an
  /// Absorption effect whose aim names its primary target, a struck unit: `spell4_id` is the
  /// spell with the Proxy `proxy_effect_id`, and `effect_id` the row.
  AbsorptionOnStruckUnit(spell4_id: Int, proxy_effect_id: Int, effect_id: Int)
  /// A Proc effect of a kind the server does not read (`proc_read`): the row is in no
  /// list of its spell and the load goes on, so this error is a skip, never a failure.
  ProcKindNotRead(spell4_id: Int, effect_id: Int, kind: Int)
  /// A Proc effect of a kind the server reads has a column the plan does not read: its
  /// name and value. The load fails (`proc_read`).
  ProcNotRead(spell4_id: Int, effect_id: Int, column: String, value: Int)
  /// A DisguiseOutfit effect of a tree aimed at the caster shows nothing the server can
  /// draw with 0x933 (`Spell4Effects.effectType.112`).
  DisguiseNotRead(spell4_id: Int, effect_id: Int, reason: DisguiseGap)
  /// A class's innate cannot be held (genesis_prime/game/innate).
  InnateFailed(error: innate.InnateError)
  /// A Prerequisite row a spell or effect names nests itself through the rows it
  /// nests (type 11): the ids from the named row to the one that repeats.
  PrerequisiteCycle(path: List(Int))
  /// A spell of a tree has an area or a strike the area rule does not build
  /// (genesis_prime/game/spell_area): the reason is the area rule's sentence.
  AreaNotBuilt(spell4_id: Int, reason: String)
  /// A spell of a tree has an area row the client's table leaves incomplete or a
  /// number that is no number: the reason is the area rule's sentence.
  AreaDataFault(spell4_id: Int, reason: String)
}

/// What an aim refusal says of the flag values `aim_of` reads: 1 to 7, and for a value with
/// bit 8 the question that holds it.
pub fn aim_values_read_text(target_flags target_flags: Int) -> String {
  use <- bool.guard(
    when: target_flags >= 8,
    return: "and only the values 1 to 7 are read; bit 8's meaning waits for the bit-8 question of #336",
  )
  "and only the values 1 to 7 are read; the client refuses 0"
}

/// A sentence that says why the plans cannot be built, naming the table and the
/// row, for the message the server stops with.
pub fn describe(error error: PlanError) -> String {
  case error {
    NoRow(table:, id:) ->
      "the table "
      <> table
      <> " has no row "
      <> int.to_string(id)
      <> ", which an ability's tree of casts names"
    ProxyCycle(chain:) ->
      "the Proxy effects of an ability lead round a cycle of spells: "
      <> string_of(chain)
    ProxyAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", "
      <> aim_values_read_text(target_flags:)
    UnreadCost(spell4_id:, cost_type:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an innate cost of type "
      <> int.to_string(cost_type)
      <> ", which the client's check was not read for"
    UnreadRequirement(spell4_id:, requirement_type:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a caster vital requirement of type "
      <> int.to_string(requirement_type)
      <> ", whose vital the server does not read"
    ChannelWithoutPulse(spell4_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " is Channeled with a channelPulseTime of 0, which gives no count of pulses"
    NoThresholdTime(spell4_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " is a RapidTap or ChargeRelease ability with a thresholdTime of 0, which the client refuses"
    GainAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a VitalModifier effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", and only one aimed at the caster is read"
    GainVitalNotRead(spell4_id:, effect_id:, vital:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a VitalModifier effect "
      <> int.to_string(effect_id)
      <> " of vital "
      <> int.to_string(vital)
      <> ", and only vitals 6 and 8 are read"
    ApplyPrerequisiteNotRead(spell4_id:, effect_id:, prerequisite_type:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an effect "
      <> int.to_string(effect_id)
      <> " behind an apply prerequisite with a condition of type "
      <> int.to_string(prerequisite_type)
      <> ", which is not decoded (#818)"
    TargetPrerequisiteReadsStruckUnit(
      spell4_id:,
      effect_id:,
      prerequisite_type:,
    ) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an effect "
      <> int.to_string(effect_id)
      <> " aimed past the caster behind a target apply prerequisite with a condition of type "
      <> int.to_string(prerequisite_type)
      <> case prerequisite_type {
        15 | 59 | 129 ->
          ", which reads what the casts held on the creature it strikes hold (#569)"
        _ ->
          ", which reads the state of the creature it strikes, and the row is not one its strike carries to the creature (#851)"
      }
    ControlHelperNotRead(spell4_id:, effect_id:, helper:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Knockback, Pushback or Pull state "
      <> int.to_string(effect_id)
      <> " whose helper spell "
      <> int.to_string(helper)
      <> " holds no single ForcedMove row aimed at the units a strike hits without an apply prerequisite, so its move is not known"
    StruckMoveNotRead(spell4_id:, effect_id:, error:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a ForcedMove effect "
      <> int.to_string(effect_id)
      <> " aimed at the units a strike hits that is no move: "
      <> case error {
        forced_move.UnknownKind(kind:, ..) ->
          "its dataBits00 is "
          <> int.to_string(kind)
          <> ", which is no kind from 0 to 15"
        forced_move.NotAFloat(column:, ..) ->
          "it holds no finite number in " <> column
      }
    SpendComparisonNotRead(spell4_id:, effect_id:, comparison:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " spends every point held and has an effect "
      <> int.to_string(effect_id)
      <> " of emmComparison "
      <> int.to_string(comparison)
      <> ", and only 0 and 1 are read"
    ForceRemoveSelectorNotRead(spell4_id:, effect_id:, selector:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a SpellForceRemove effect "
      <> int.to_string(effect_id)
      <> " of selector "
      <> int.to_string(selector)
      <> ", and only 1, 2 and 3 are read"
    ForceRemoveCountsDiffer(spell4_id:, effect_id:, data_bits03:, data_bits04:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a SpellForceRemove effect "
      <> int.to_string(effect_id)
      <> " whose dataBits03 "
      <> int.to_string(data_bits03)
      <> " differs from its dataBits04 "
      <> int.to_string(data_bits04)
      <> ", and only a row where they agree is read"
    LastingAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Fluff, SpellForceRemove, Scale, ItemVisualSwap or RavelSignal effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", "
      <> aim_values_read_text(target_flags:)
    ControlStateNotRead(spell4_id:, effect_id:, state:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a CCStateSet effect "
      <> int.to_string(effect_id)
      <> " of state "
      <> int.to_string(state)
      <> ", and only the states 0 to 27 of Unit.CodeEnumCCState are read"
    ControlAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a CCStateSet effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", "
      <> aim_values_read_text(target_flags:)
    FriendlyAreaNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " hits no foes and has an effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", which hold the caster and the area: a friendly spell's area finds the caster's allies, which the server does not read yet (#834)"
    ControlPersistenceNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a CCStateSet effect "
      <> int.to_string(effect_id)
      <> " on another unit kept through death or leaving by a persistence prerequisite, which the server does not read (#787)"
    ModifierPropertyHasNoRow(spell4_id:, effect_id:, property:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a UnitPropertyModifier or UnitPropertyConversion effect "
      <> int.to_string(effect_id)
      <> " of property "
      <> int.to_string(property)
      <> ", which UnitProperty2 has no row for"
    ModifierNumberNotFinite(spell4_id:, effect_id:, column:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a UnitPropertyModifier or UnitPropertyConversion effect "
      <> int.to_string(effect_id)
      <> " whose "
      <> column
      <> " is not a finite number"
    CooldownNumberNotFinite(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a ModifySpellCooldown effect "
      <> int.to_string(effect_id)
      <> " whose dataBits03 is not a finite number"
    StealthAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Stealth or RemoveStealth effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", and only the caster alone is read"
    StealthTimedNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Stealth effect "
      <> int.to_string(effect_id)
      <> " with a delayTime or durationTime, and timed stealth is not built"
    StealthBreaksNotRead(spell4_id:, effect_id:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Stealth effect "
      <> int.to_string(effect_id)
      <> " whose dataBits02 is "
      <> int.to_string(value)
      <> ", and only 0 and 1 say whether damage ends it"
    StealthConditionNotRead(spell4_id:, spell4_conditions_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has the Spell4Conditions row "
      <> int.to_string(spell4_conditions_id)
      <> ", whose mask tests stealth, and the client's refusals 65 and 114 are not checked"
    StealthChangeNotRead(spell4_id:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a spellCastStealthChange of "
      <> int.to_string(value)
      <> ", and only 0, 1 and 2 are read"
    ParameterNotRead(spell4_id:, effect_id:, row:, parameter_kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has "
      <> parameter_row_name(row:)
      <> " effect "
      <> int.to_string(effect_id)
      <> " with a parameter of type "
      <> int.to_string(parameter_kind)
      <> ", which the plan does not read"
    HealNumberNotFinite(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Heal or HealShields effect "
      <> int.to_string(effect_id)
      <> " whose dataBits00 is not a finite number"
    HealUntilRemovedNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a periodic Heal or HealShields effect "
      <> int.to_string(effect_id)
      <> " that lasts until removed, which is not read"
    HealNoTick(spell4_id:, effect_id:, tick_ms:, duration_ms:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a periodic Heal or HealShields effect "
      <> int.to_string(effect_id)
      <> " with a tickTime of "
      <> int.to_string(tick_ms)
      <> " and a durationTime of "
      <> int.to_string(duration_ms)
      <> ", shorter than one tick"
    HealOnStruckUnit(spell4_id:, proxy_effect_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(proxy_effect_id)
      <> " that starts a child on each struck unit, which holds the Heal or HealShields effect "
      <> int.to_string(effect_id)
      <> " whose aim names that unit, and a heal on a struck unit is not built"
    InterruptArmorTakeBackNotRead(spell4_id:, effect_id:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a ModifyInterruptArmor effect "
      <> int.to_string(effect_id)
      <> " whose dataBits01 is "
      <> int.to_string(value)
      <> ", and only 0 and 1 say whether the armor is taken back"
    InterruptArmorOnStruckUnit(spell4_id:, proxy_effect_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(proxy_effect_id)
      <> " that starts a child on each struck unit, which holds the ModifyInterruptArmor effect "
      <> int.to_string(effect_id)
      <> " whose aim names that unit, and Interrupt Armor on a struck unit is not built"
    AbsorptionNumberNotFinite(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " whose dataBits00 or dataBits01 is not a finite number"
    AbsorptionAmountNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " whose multiplier or base is 0 and no parameter gives it a value, so its amount is not read"
    AbsorptionPeriodic(spell4_id:, effect_id:, tick_ms:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " with a tickTime of "
      <> int.to_string(tick_ms)
      <> ", and a periodic absorb is not read"
    AbsorptionHasNoLifetime(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " with no durationTime and no flags bit 2, and an absorb with no lifetime is not read"
    AbsorptionOnStruckUnit(spell4_id:, proxy_effect_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(proxy_effect_id)
      <> " that starts a child on each struck unit, which holds the Absorption effect "
      <> int.to_string(effect_id)
      <> " whose aim names that unit, and an absorb on a struck unit is not built"
    AreaNotBuilt(reason:, ..) | AreaDataFault(reason:, ..) -> reason
    ProcKindNotRead(spell4_id:, effect_id:, kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proc effect "
      <> int.to_string(effect_id)
      <> " of kind "
      <> int.to_string(kind)
      <> ", which is not read"
    ProcNotRead(spell4_id:, effect_id:, column:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proc effect "
      <> int.to_string(effect_id)
      <> " whose "
      <> column
      <> " is "
      <> int.to_string(value)
      <> ", which is not read"
    DisguiseNotRead(spell4_id:, effect_id:, reason:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a DisguiseOutfit effect "
      <> int.to_string(effect_id)
      <> case reason {
        OutfitNeedsMessage0x905 -> " with an outfit, which only 0x905 draws"
        NamesNoDisplay -> " that names no ItemDisplay"
        DisplayHasNoSlot(item_display_id:) ->
          " whose ItemDisplay "
          <> int.to_string(item_display_id)
          <> " has an item type with no ItemSlot"
      }
    InnateFailed(error:) -> innate.describe(error:)
    PrerequisiteCycle(path:) ->
      "the Prerequisite rows nest each other round a cycle: " <> string_of(path)
  }
}

fn string_of(chain: List(Int)) -> String {
  string.join(list.map(chain, int.to_string), " -> ")
}

/// Every class's level-1 abilities and slot-0 innate spells as trees, by
/// Spell4BaseId, as the load keeps them.
pub type Plans =
  Dict(Int, Spell)

/// What the plans' derivation holds: the plans of the level-1 abilities and the innates,
/// and the same with each later ability of a class that the server can plan.
type PlanSet {
  PlanSet(starting: Plans, with_later: Plans)
}

const plans_key: table_store.DerivedKey(PlanSet) =
  table_store.DerivedKey("SpellPlans")

/// The plans as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`): a plan for the Spell4BaseId of
/// each class's level-1 ability and of each class's innate active and passive spell.
/// A missing row, a cost not read or a cycle fails the load. `area_checked` is what a
/// later ability's spells must also pass (`Checker`).
pub fn derivation(
  area_checked area_checked: fn(table_store.Tables) -> Checker,
) -> table_store.Derivation {
  table_store.derivation(key: plans_key, build: fn(tables) {
    plan_all(tables:, checker: area_checked(tables))
    |> result.map(fn(planned) { planned.0 })
    |> result.map_error(fn(error) { describe(error:) })
  })
}

/// What a spell of a later ability must also pass to be planned: the area rule builds every
/// spell of its tree (genesis_prime/game/spell_area `checker`). Its error is a `PlanError`,
/// and `is_unbuilt` says whether the ability is left out or the load fails.
pub type Checker =
  fn(Spell) -> Result(Nil, PlanError)

/// The rows the tree reads, grouped by the spell they belong to.
pub opaque type Sources {
  Sources(
    effects: Dict(Int, List(spell4_effects.Spell4Effects)),
    phases: Dict(Int, List(Phase)),
    thresholds: Dict(Int, List(spell4_thresholds.Spell4Thresholds)),
    /// The spell group ids of each Spell4GroupList row, by the row's id.
    group_lists: Dict(Int, List(Int)),
    /// Every spell group id some Spell4GroupList row holds.
    known_groups: Set(Int),
    /// The spells a Proxy row (dataBits00) or a Proc row (dataBits01) names as its child.
    children: Set(Int),
  )
}

/// The rows the plan reads from the loaded tables, grouped once: what `build` and
/// `spell_alone` plan from.
pub fn sources_of(tables tables: table_store.Tables) -> Sources {
  let group_lists = group_lists_by_id(tables:)
  Sources(
    effects: effects_by_spell(tables:),
    phases: phases_by_owner(tables:),
    thresholds: thresholds_by_parent(tables:),
    group_lists:,
    known_groups: known_groups(group_lists:),
    children: children_named(effects: spell4_effects.all(tables)),
  )
}

/// Whether a Proxy or a Proc row of the tables names this spell as its child, so a spell
/// cast on its own is also started by that row.
pub fn is_child(sources sources: Sources, spell4_id spell4_id: Int) -> Bool {
  set.contains(sources.children, spell4_id)
}

fn children_named(
  effects effects: List(spell4_effects.Spell4Effects),
) -> Set(Int) {
  list.filter_map(effects, fn(effect) {
    let kind = effect_kind.kind_of(effect_type: effect.effect_type)
    case kind == effect_kind.Proxy, kind == effect_kind.Proc {
      True, _ -> Ok(effect.data_bits00)
      False, True -> Ok(effect.data_bits01)
      False, False -> Error(Nil)
    }
  })
  |> set.from_list
}

/// The effects of one spell in the grouped rows, in the order they take effect: none
/// for a spell with no Spell4Effects row.
pub fn effects_of(
  sources sources: Sources,
  spell4_id spell4_id: Int,
) -> List(spell4_effects.Spell4Effects) {
  dict.get(sources.effects, spell4_id) |> result.unwrap([])
}

fn known_groups(group_lists group_lists: Dict(Int, List(Int))) -> Set(Int) {
  set.from_list(list.flatten(dict.values(group_lists)))
}

/// A SpellPhase row the client keeps.
type Phase {
  Phase(delay_ms: Int, flags: Int)
}

/// A class ability above level 1 that no plan is built for: its Spell4 id and the
/// error that names what the server does not build (`is_unbuilt`). Its press is refused
/// as an unknown spell until issue #1003 builds it.
pub type Unplanned {
  Unplanned(spell4_id: Int, error: PlanError)
}

/// Builds every plan from the loaded tables, or why one cannot be built; the
/// derivation's body, and the function a test of a missing row or a cycle runs
/// on planted tables.
pub fn build(tables tables: table_store.Tables) -> Result(Plans, PlanError) {
  use #(held, _) <- result.map(plan_all(tables:, checker: fn(_) { Ok(Nil) }))
  held.starting
}

/// The class abilities above level 1 the plans leave out, by the error that says what
/// the server does not build; a level-1 ability, an innate or any other error
/// fails the load instead (`build`).
pub fn unplanned(
  tables tables: table_store.Tables,
  area_checked area_checked: fn(table_store.Tables) -> Checker,
) -> Result(List(Unplanned), PlanError) {
  use #(_, left_out) <- result.map(plan_all(
    tables:,
    checker: area_checked(tables),
  ))
  left_out
}

/// Whether a plan error names an effect or a rule the server does not build, so the
/// ability that holds it is left out of the plans without failing the load. A missing row
/// or a number that is no number is a fault of the data and is not one of these.
pub fn is_unbuilt(error error: PlanError) -> Bool {
  case error {
    ProxyAimNotRead(..)
    | ProxyCycle(..)
    | UnreadCost(..)
    | UnreadRequirement(..)
    | GainAimNotRead(..)
    | GainVitalNotRead(..)
    | ApplyPrerequisiteNotRead(..)
    | TargetPrerequisiteReadsStruckUnit(..)
    | StruckMoveNotRead(error: forced_move.UnknownKind(..), ..)
    | ControlHelperNotRead(..)
    | SpendComparisonNotRead(..)
    | ForceRemoveSelectorNotRead(..)
    | ForceRemoveCountsDiffer(..)
    | LastingAimNotRead(..)
    | ControlStateNotRead(..)
    | ControlAimNotRead(..)
    | FriendlyAreaNotRead(..)
    | ControlPersistenceNotRead(..)
    | StealthAimNotRead(..)
    | StealthTimedNotRead(..)
    | StealthBreaksNotRead(..)
    | StealthConditionNotRead(..)
    | StealthChangeNotRead(..)
    | ParameterNotRead(..)
    | HealUntilRemovedNotRead(..)
    | HealNoTick(..)
    | HealOnStruckUnit(..)
    | InterruptArmorTakeBackNotRead(..)
    | InterruptArmorOnStruckUnit(..)
    | AbsorptionAmountNotRead(..)
    | AbsorptionPeriodic(..)
    | AbsorptionHasNoLifetime(..)
    | AbsorptionOnStruckUnit(..)
    | ProcKindNotRead(..)
    | DisguiseNotRead(..)
    | AreaNotBuilt(..) -> True
    NoRow(..)
    | StruckMoveNotRead(error: forced_move.NotAFloat(..), ..)
    | ChannelWithoutPulse(..)
    | NoThresholdTime(..)
    | ModifierPropertyHasNoRow(..)
    | ModifierNumberNotFinite(..)
    | CooldownNumberNotFinite(..)
    | HealNumberNotFinite(..)
    | AbsorptionNumberNotFinite(..)
    | ProcNotRead(..)
    | InnateFailed(..)
    | PrerequisiteCycle(..)
    | AreaDataFault(..) -> False
  }
}

/// The plans of every level-1 ability and innate, which fail the load on any error, and
/// of every other class ability with no prerequisite, which a row `is_unbuilt` names is
/// left out of, and listed.
fn plan_all(
  tables tables: table_store.Tables,
  checker checker: Checker,
) -> Result(#(PlanSet, List(Unplanned)), PlanError) {
  let sources = sources_of(tables:)
  use held <- result.try(innate.held(tables:) |> result.map_error(InnateFailed))
  let rows = spell_level.all(tables)
  let abilities =
    rows
    |> list.filter(loadout.is_level_one_ability)
    |> list.map(fn(row) { row.spell4_id })
  let later =
    rows
    |> list.filter(fn(row) {
      loadout.is_class_ability(row:) && !loadout.is_level_one_ability(row:)
    })
    |> list.map(fn(row) { row.spell4_id })
  let innates =
    dict.to_list(held)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      let innate = entry.1
      [
        innate.active.value,
        ..case innate.passive {
          Some(passive) -> [passive.spell4_id.value]
          None -> []
        }
      ]
    })
  use plans <- result.try(
    list.try_fold(
      list.append(abilities, innates),
      dict.new(),
      fn(plans, spell4_id) {
        use spell <- result.map(ability_alone(tables:, sources:, spell4_id:))
        plan_added(plans:, spell:)
      },
    ),
  )
  use #(with_later, left_out) <- result.map(
    list.try_fold(later, #(plans, []), fn(held, spell4_id) {
      let #(plans, left_out) = held
      case
        ability_alone(tables:, sources:, spell4_id:)
        |> result.try(checked(_, checker:))
      {
        Ok(spell) -> Ok(#(plan_added(plans:, spell:), left_out))
        Error(error) ->
          case is_unbuilt(error:) {
            True -> Ok(#(plans, [Unplanned(spell4_id:, error:), ..left_out]))
            False -> Error(error)
          }
      }
    }),
  )
  #(PlanSet(starting: plans, with_later:), list.reverse(left_out))
}

/// The spell when every spell of its tree and of its alternate's tree passes the checker.
fn checked(
  spell spell: Spell,
  checker checker: Checker,
) -> Result(Spell, PlanError) {
  let trees = case spell.alternate {
    Some(alternate) -> [spell, alternate]
    None -> [spell]
  }
  list.flat_map(trees, tree(spell: _, started: fn(_) { True }))
  |> list.try_each(checker)
  |> result.replace(spell)
}

/// The plans with the spell and the alternate it names.
fn plan_added(plans plans: Plans, spell spell: Spell) -> Plans {
  let plans = case spell.alternate {
    Some(alternate) ->
      dict.insert(plans, alternate.spell4_base_id.value, alternate)
    None -> plans
  }
  dict.insert(plans, spell.spell4_base_id.value, spell)
}

/// One ability or innate spell as `build` plans it, its alternate included: the plan of a
/// spell outside a level tree, which a test plants.
pub fn ability_alone(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
) -> Result(Spell, PlanError) {
  use spell <- result.try(planned(tables:, sources:, spell4_id:))
  with_alternate(tables:, sources:, spell:)
}

/// One ability or innate spell as the plan holds it: its tree, a ChargeRelease
/// ability's opening cost lifted, and a threshold time where its method needs one.
fn planned(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
) -> Result(Spell, PlanError) {
  use spell <- result.try(spell_of(
    tables:,
    sources:,
    spell4_id:,
    chain: [],
    threshold_costs: [],
    struck_by: None,
    pressed: True,
  ))
  use Nil <- result.map(has_threshold_time(spell:))
  opening_costs_lifted(spell:)
}

/// The spell with the spell its Spell4 row names as its alternate
/// (`Spell4.spell4IdMechanicAlternateSpell`, which `SpellslingerSurgedSpell`
/// `0x1405e7e50` swaps a press to under Spell Surge); a row naming one the table lacks is a
/// `NoRow`. The alternate names none of its own: the client swaps once.
fn with_alternate(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell spell: Spell,
) -> Result(Spell, PlanError) {
  use row <- result.try(
    spell4.get(tables:, id: spell.spell4_id)
    |> result.replace_error(NoRow(table: "Spell4", id: spell.spell4_id.value)),
  )
  case row.spell4_id_mechanic_alternate_spell {
    0 -> Ok(spell)
    named -> {
      use alternate <- result.map(planned(tables:, sources:, spell4_id: named))
      Spell(..spell, alternate: Some(alternate))
    }
  }
}

/// A ChargeRelease ability pays the row cost of its first stage at the press that opens
/// the charge, and the stage it casts at release pays nothing more: the class costs
/// of stage 0 move to the front of the ability's own costs (a decision of the project, not a
/// client fact: the client checks a threshold row's cost with the row's press).
fn opening_costs_lifted(spell spell: Spell) -> Spell {
  case spell.method, spell.stages {
    ChargeRelease, [first, ..rest] -> {
      let #(lifted, kept) =
        list.partition(first.spell.costs, fn(cost) {
          case cost {
            RowClassCost(..) -> True
            SlotCost(..)
            | ClassVitalCost(..)
            | UnheldCost(..)
            | SpendAllCost(..)
            | UnreadSpendCost(..) -> False
          }
        })
      case lifted {
        [] -> spell
        _ ->
          Spell(..spell, costs: list.append(lifted, spell.costs), stages: [
            Stage(..first, spell: Spell(..first.spell, costs: kept)),
            ..rest
          ])
      }
    }
    ChargeRelease, [] -> spell
    Normal, _
    | Channeled, _
    | PressHold, _
    | ChanneledField, _
    | ClientSideInteraction, _
    | RapidTap, _
    | Multiphase, _
    | Transactional, _
    | OtherMethod(..), _
    -> spell
  }
}

/// A Proxy the server adds to a tree, which starts `child` on the caster at once at
/// each go of the phases `phase_flags` names, with no gate and no gain lifted. It
/// stands for no Spell4Effects row, so its effect id is 0
/// (genesis_prime/game/server_proxy).
pub fn server_proxy(child child: Spell, phase_flags phase_flags: Int) -> Proxy {
  Proxy(
    effect_id: Spell4EffectsId(0),
    delay_ms: 0,
    phase_flags:,
    condition: Always,
    tag: spend.always,
    target: OnCaster,
    spell: child,
    gains: [],
  )
}

/// A RapidTap or ChargeRelease ability opens a threshold of its thresholdTime, so
/// a press of one with none is refused by the client (`0x1403bfd60`) unless a Proxy of its
/// own, gated on the caster, can be cast instead (`ResolveProxyByCasterApply`
/// `0x1403d3520`).
fn has_threshold_time(spell spell: Spell) -> Result(Nil, PlanError) {
  case
    lacks_threshold_time(method: spell.method, threshold_ms: spell.threshold_ms),
    spell.press_proxies
  {
    True, [] -> Error(NoThresholdTime(spell4_id: spell.spell4_id.value))
    True, [_, ..] | False, _ -> Ok(Nil)
  }
}

/// Whether a spell of this cast method and thresholdTime is a RapidTap or ChargeRelease
/// spell with no threshold time: no threshold opens for it, so a press of it casts the
/// first Proxy its caster passes, which its own Proxy rows are walked for and never run as
/// its go, or is refused 285 (`0x1403bfd60`, `ResolveProxyByCasterApply` `0x1403d3520`).
/// Only a spell planned as a pressed ability is walked so: a stage or a Proxy's child runs
/// its own Proxy rows as its go.
pub fn lacks_threshold_time(
  method method: CastMethod,
  threshold_ms threshold_ms: Int,
) -> Bool {
  case method {
    RapidTap | ChargeRelease -> threshold_ms == 0
    Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | Multiphase
    | Transactional
    | OtherMethod(..) -> False
  }
}

/// The effects of each spell, of every type, in the order they take effect
/// (`Spell4Effects.orderIndex`, then the row id): the plans read the Proxies among
/// them and the areas the damage, so the table is grouped once.
pub fn effects_by_spell(
  tables tables: table_store.Tables,
) -> Dict(Int, List(spell4_effects.Spell4Effects)) {
  spell4_effects.all(tables)
  |> list.group(fn(effect) { effect.spell_id })
  |> dict.map_values(fn(_, effects) {
    list.sort(effects, fn(first, second) {
      int.compare(first.order_index, second.order_index)
      |> order.break_tie(int.compare(first.id, second.id))
    })
  })
}

fn phases_by_owner(
  tables tables: table_store.Tables,
) -> Dict(Int, List(Phase)) {
  spell_phase.all(tables)
  |> list.filter(fn(phase) {
    phase.order_index < max_phases
    && { phase.order_index == 0 || phase.phase_delay != 0 }
  })
  |> list.group(fn(phase) { phase.spell4_id_owner })
  |> dict.map_values(fn(_, phases) {
    list.reverse(phases)
    |> list.map(fn(phase) {
      Phase(delay_ms: phase.phase_delay, flags: phase.phase_flags)
    })
  })
}

/// What a Proc's filters read of a spell that is only a Spell4 id: its spell groups and its
/// school.
pub type SpellFacts {
  SpellFacts(groups: List(Int), school: Int)
}

/// The groups and school of the spell `spell4_id` as a Proc's filters read them: the group
/// ids of its Spell4GroupList row (`0x140561d80`), none for the list id 0, and its
/// Spell4Base school. A Spell4, Spell4Base or group list row the tables lack is an error, so a
/// caller never takes a spell whose groups are unknown for one that has none.
pub fn facts_of_spell4(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Spell4Id,
) -> Result(SpellFacts, PlanError) {
  use row <- result.try(
    spell4.get(tables:, id: spell4_id)
    |> result.replace_error(NoRow(table: "Spell4", id: spell4_id.value)),
  )
  use base <- result.try(
    spell4_base.get(tables:, id: Spell4BaseId(row.spell4_base_id_base_spell))
    |> result.replace_error(NoRow(
      table: "Spell4Base",
      id: row.spell4_base_id_base_spell,
    )),
  )
  use groups <- result.map(case row.spell4_group_list_id {
    0 -> Ok([])
    list_id ->
      spell4_group_list.get(tables:, id: Spell4GroupListId(list_id))
      |> result.map(fn(group_list) {
        list.filter(group_ids_of(row: group_list), fn(group) { group != 0 })
      })
      |> result.replace_error(NoRow(table: "Spell4GroupList", id: list_id))
  })
  SpellFacts(groups:, school: base.school)
}

/// The spell group ids each Spell4GroupList row names, by the row's id: its
/// spellGroupId00 to 31 values that are not 0.
fn group_lists_by_id(
  tables tables: table_store.Tables,
) -> Dict(Int, List(Int)) {
  spell4_group_list.all(tables)
  |> list.map(fn(row) {
    #(row.id, list.filter(group_ids_of(row:), fn(group) { group != 0 }))
  })
  |> dict.from_list
}

/// The Spell4Thresholds rows of each spell, by order index
/// (`Spell4Thresholds.spell4IdToCast`: the client sorts them by the row's order
/// index, `0x140566940`).
fn thresholds_by_parent(
  tables tables: table_store.Tables,
) -> Dict(Int, List(spell4_thresholds.Spell4Thresholds)) {
  spell4_thresholds.all(tables)
  |> list.group(fn(row) { row.spell4_id_parent })
  |> dict.map_values(fn(_, rows) {
    list.sort(rows, fn(first, second) {
      int.compare(first.order_index, second.order_index)
      |> order.break_tie(int.compare(first.id, second.id))
    })
  })
}

/// The client keeps phase rows with an order index below 32 (`0x14055e180`).
const max_phases = 32

/// The phase flag that moves a Multiphase spell's cooldown to its last phase
/// (`0x14053e5a0`).
const cooldown_at_last_phase_flag = 0x200

/// The chain of spells from the pressed ability to `spell4_id`, which fails as a
/// `ProxyCycle` naming the whole chain when `spell4_id` is already on it: a Proxy or a
/// Proc effect that leads back to a spell on the way would start it for ever.
pub fn chain_extended(
  chain chain: List(Int),
  spell4_id spell4_id: Int,
) -> Result(List(Int), PlanError) {
  let chain = list.append(chain, [spell4_id])
  case list.contains(list.take(chain, list.length(chain) - 1), spell4_id) {
    True -> Error(ProxyCycle(chain:))
    False -> Ok(chain)
  }
}

/// One Proxy row of the spell `spell4_id` as a `Proxy`: the child it names planned on the
/// same chain, and the gains of a child started on each struck unit lifted onto it.
fn proxy_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
  effect effect: spell4_effects.Spell4Effects,
  target target: ProxyTarget,
  condition condition: Condition,
) -> Result(Proxy, PlanError) {
  use child <- result.map(spell_of(
    tables:,
    sources:,
    spell4_id: effect.data_bits00,
    chain:,
    threshold_costs: [],
    struck_by: case target {
      OnEachStruck -> Some(StruckBy(spell4_id:, proxy_effect_id: effect.id))
      OnCaster -> None
    },
    pressed: False,
  ))
  // Every gain under a Proxy aimed at each struck unit in the client's level-1 trees fires
  // in phase 0 only (`spell_plan_gain_test` reads them all), so lifting by phase 0 loses
  // none to a later phase.
  let #(lifted, kept) = case target {
    OnEachStruck ->
      list.partition(child.effects, fn(planned) {
        result.is_ok(as_gain(kind: planned.kind))
        && spell_effect.has_flag(flags: planned.phase_flags, bit: 1)
      })
    OnCaster -> #([], child.effects)
  }
  Proxy(
    effect_id: Spell4EffectsId(effect.id),
    delay_ms: effect.delay_time,
    phase_flags: effect.phase_flags,
    condition:,
    tag: tag_of(effect:),
    target:,
    spell: Spell(..child, effects: kept),
    gains: list.filter_map(lifted, fn(planned) { as_gain(kind: planned.kind) }),
  )
}

fn spell_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
  threshold_costs threshold_costs: List(#(Int, Int)),
  struck_by struck_by: Option(StruckBy),
  pressed pressed: Bool,
) -> Result(Spell, PlanError) {
  use chain <- result.try(chain_extended(chain:, spell4_id:))
  use row <- result.try(
    spell4.get(tables:, id: Spell4Id(spell4_id))
    |> result.replace_error(NoRow(table: "Spell4", id: spell4_id)),
  )
  use base <- result.try(
    spell4_base.get(tables:, id: Spell4BaseId(row.spell4_base_id_base_spell))
    |> result.replace_error(NoRow(
      table: "Spell4Base",
      id: row.spell4_base_id_base_spell,
    )),
  )
  use global_cooldown <- result.try(global_cooldown_of(tables:, row:))
  let rows = prerequisite.table_rows(tables:)
  let arcs = prerequisite.table_arcs(tables:)
  let quests = prerequisite.table_quests(tables:)
  use caster_cast <- result.try(caster_cast_of(
    prerequisite_id: row.prerequisite_id_caster_cast,
    property_flags: row.property_flags,
    requirement_block: #(
      row.caster_innate_requirement0,
      row.caster_innate_requirement1,
      row.target_begin_innate_requirement,
    ),
    rows:,
    arcs:,
    quests:,
  ))
  use target_cast <- result.try(column_of(
    id: row.prerequisite_id_target_cast,
    rows:,
    arcs:,
    quests:,
  ))
  use caster_persistence <- result.try(column_of(
    id: row.prerequisite_id_caster_persistence,
    rows:,
    arcs:,
    quests:,
  ))
  use target_persistence <- result.try(column_of(
    id: row.prerequisite_id_target_persistence,
    rows:,
    arcs:,
    quests:,
  ))
  use caster_conditions <- result.try(conditions_row_of(
    tables:,
    id: row.spell4_conditions_id_caster,
  ))
  use target_conditions <- result.try(conditions_row_of(
    tables:,
    id: row.spell4_conditions_id_target,
  ))
  use caster_cc_mask <- result.try(cc_mask_of(
    tables:,
    id: row.spell4_cc_conditions_id_caster,
  ))
  use target_cc_mask <- result.try(cc_mask_of(
    tables:,
    id: row.spell4_cc_conditions_id_target,
  ))
  let caster_death = caster_death_of(conditions: caster_conditions)
  let target_death = caster_death_of(conditions: target_conditions)
  use costs <- result.try(costs_of(
    row:,
    innate: [
      #(row.innate_cost_type0, row.innate_cost0, row.innate_cost_emm_id0),
      #(row.innate_cost_type1, row.innate_cost1, row.innate_cost_emm_id1),
    ],
    threshold: threshold_costs,
  ))
  use requirements <- result.try(
    requirements_of(spell4_id:, requirements: [
      #(
        row.caster_innate_requirement0,
        row.caster_innate_requirement_eval0,
        row.caster_innate_requirement_value0,
      ),
      #(
        row.caster_innate_requirement1,
        row.caster_innate_requirement_eval1,
        row.caster_innate_requirement_value1,
      ),
    ]),
  )
  let effects = dict.get(sources.effects, spell4_id) |> result.unwrap([])
  let place =
    RowPlace(
      struck_by:,
      spends_all: spends_all_of(costs:),
      hits_foes: spell_hits_foes(effects:),
      throws_target: spell_throws_target(effects:),
    )
  use Nil <- result.try(
    list.try_each(effects, spend_tag_read(place:, effect: _)),
  )
  let readings =
    list.map(effects, fn(effect) {
      #(effect, read_row(tables:, sources:, place:, effect:))
    })
  // The rows of each list are read in the order the lists were once built, so a spell with
  // two refused rows names the same one first.
  use Nil <- result.try(
    list.try_each(
      [
        [effect_kind.VitalModifier],
        [
          effect_kind.Fluff,
          effect_kind.Scale,
          effect_kind.ItemVisualSwap,
          effect_kind.RavelSignal,
          effect_kind.ShieldOverload,
          effect_kind.FullScreenEffect,
        ],
        [effect_kind.ForceRemove],
        [effect_kind.CrowdControl],
        [
          effect_kind.PropertyModifier,
          effect_kind.PropertyConversion,
          effect_kind.DisguiseOutfit,
          effect_kind.Absorption,
        ],
        [effect_kind.InterruptArmor],
        [effect_kind.ForcedMove],
        [effect_kind.CooldownModifier],
        [effect_kind.Stealth],
        [effect_kind.RemoveStealth],
        [
          effect_kind.Heal(vital: effect_kind.Health),
          effect_kind.Heal(vital: effect_kind.Shield),
        ],
        [effect_kind.Despawn],
        [effect_kind.UnitState],
      ],
      fn(kinds) { rows_read(readings:, kinds:) },
    ),
  )
  use struck_gates <- result.try(struck_gates_of(tables:, place:, readings:))
  use stealth_change <- result.try(stealth_change_of(
    spell4_id:,
    value: row.spell_cast_stealth_change,
  ))
  use procs <- result.try(procs_of(tables:, sources:, readings:, chain:))
  use Nil <- result.try(
    stealth_conditions_read(spell4_id:, conditions: [
      caster_conditions,
      target_conditions,
    ]),
  )
  use cooldown_groups <- result.try(cooldown_groups_of(tables:, row:))
  use groups <- result.try(groups_of(sources:, row:))
  use stack <- result.try(stack_of(tables:, row:))
  let method = method_of(base.cast_method)
  let presses =
    pressed && lacks_threshold_time(method:, threshold_ms: row.threshold_time)
  use proxies <- result.try(case presses {
    True -> Ok([])
    False ->
      rows_of_kind(readings:, kind: effect_kind.Proxy)
      |> list.try_map(fn(row) {
        let #(effect, reading) = row
        use reading <- result.try(reading)
        case reading {
          Applied(ReadProxy(targets:, condition:))
          | Held(ReadProxy(targets:, condition:)) ->
            list.try_map(targets, fn(target) {
              proxy_of(
                tables:,
                sources:,
                spell4_id:,
                chain:,
                effect:,
                target:,
                condition:,
              )
            })
          Applied(ReadEffects(..))
          | Applied(ReadProc(..))
          | Held(ReadEffects(..))
          | Held(ReadProc(..))
          | LeftOut(..)
          | ReadByArea
          | ReadByActivation -> Ok([])
        }
      })
      |> result.map(list.flatten)
  })
  use stages <- result.try(
    dict.get(sources.thresholds, spell4_id)
    |> result.unwrap([])
    |> list.try_map(fn(threshold) {
      use stage <- result.try(spell_of(
        tables:,
        sources:,
        spell4_id: threshold.spell4_id_to_cast,
        chain:,
        threshold_costs: [
          #(threshold.vital_enum_cost_type00, threshold.vital_cost_value00),
          #(threshold.vital_enum_cost_type01, threshold.vital_cost_value01),
        ],
        struck_by: None,
        pressed: False,
      ))
      Ok(Stage(duration_ms: threshold.threshold_duration, spell: stage))
    }),
  )
  use press_proxies <- result.try(press_proxies_of(
    tables:,
    sources:,
    spell4_id:,
    chain:,
    effects:,
    presses:,
  ))
  let phases = dict.get(sources.phases, spell4_id) |> result.unwrap([])
  use delays <- result.try(phase_delays(phases:, method:, spell4_id:))
  use channel <- result.try(channel_of(row:, method:))
  let spell =
    Spell(
      spell4_id: Spell4Id(spell4_id),
      spell4_base_id: Spell4BaseId(row.spell4_base_id_base_spell),
      school: base.school,
      method:,
      cast_time_ms: row.cast_time,
      cooldown_ms: row.spell_cool_down,
      cooldown_start: cooldown_start_of(method:, phases:),
      cooldown_phase: cooldown_phase_of(method:, phases:),
      cast_bar: cast_bar_of(method:, row:, base:),
      free_while_live: spell_effect.has_flag(
        flags: row.property_flags,
        bit: 0x40,
      ),
      ignores_casting: spell_effect.has_flag(
        flags: row.property_flags,
        bit: 0x10,
      )
        || spell_effect.has_flag(flags: row.property_flags, bit: 0x1),
      longer_of_delay_and_duration: spell_effect.has_flag(
        flags: row.property_flags,
        bit: 0x2000,
      ),
      weapon: weapon_of(base.weapon_slot),
      caster_death:,
      target_death:,
      caster_cc_mask:,
      target_cc_mask:,
      global_cooldown:,
      costs:,
      requirements:,
      caster_cast:,
      target_cast:,
      caster_persistence:,
      target_persistence:,
      phase_delays_ms: delays,
      threshold_ms: row.threshold_time,
      stages:,
      channel:,
      effects: ranked(
        effects: list.flatten([
          planted_effects_of(readings:),
          list.map(proxies, fn(proxy) { effect_of(kind: ProxyEffect(proxy:)) }),
          list.map(procs, fn(proc) { effect_of(kind: ProcEffect(proc:)) }),
        ]),
      ),
      groups:,
      stack:,
      dropped_controls: dropped_controls_of(readings:),
      struck_gates:,
      cooldown_groups:,
      stealth_change:,
      alternate: None,
      press_proxies:,
    )
  Ok(spell)
}

/// The Proxy rows of a RapidTap or ChargeRelease spell with no threshold time that the
/// press walks, each with the gate the client reads and its child planned; none for any
/// other spell. A gate the press cannot check (`prerequisite.press_unread_types`) fails
/// the load, as an undecoded gate does.
fn press_proxies_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
  effects effects: List(spell4_effects.Spell4Effects),
  presses presses: Bool,
) -> Result(List(PressProxy), PlanError) {
  use <- bool.guard(when: !presses, return: Ok([]))
  effects
  |> list.filter(is_gated_proxy)
  |> list.try_map(fn(effect) {
    use gate <- result.try(prerequisite_of(
      tables:,
      id: effect.prerequisite_id_caster_apply,
    ))
    use Nil <- result.try(case prerequisite.press_unread_types(gate) {
      [prerequisite_type, ..] ->
        Error(ApplyPrerequisiteNotRead(
          spell4_id:,
          effect_id: effect.id,
          prerequisite_type:,
        ))
      [] -> Ok(Nil)
    })
    use proxy <- result.map(proxy_of(
      tables:,
      sources:,
      spell4_id:,
      chain:,
      effect:,
      target: OnCaster,
      condition: Always,
    ))
    PressProxy(effect_id: proxy.effect_id, gate:, spell: proxy.spell)
  })
}

/// Whether a row is a Proxy with a caster apply prerequisite, the rows a press walks.
fn is_gated_proxy(effect effect: spell4_effects.Spell4Effects) -> Bool {
  effect_kind.kind_of(effect.effect_type) == effect_kind.Proxy
  && effect.prerequisite_id_caster_apply != 0
}

/// The Spell4 ids of the spells a press resolves by a Proxy's caster gate: a spell of a
/// RapidTap or ChargeRelease method with no threshold time and a gated Proxy row, in id
/// order. They hold no SpellLevel row, so `build` plans none of them.
pub fn press_spell_ids(
  tables tables: table_store.Tables,
  sources sources: Sources,
) -> List(Int) {
  spell4.all(tables)
  |> list.filter(fn(row) {
    case
      spell4_base.get(tables:, id: Spell4BaseId(row.spell4_base_id_base_spell))
    {
      Ok(base) ->
        lacks_threshold_time(
          method: method_of(base.cast_method),
          threshold_ms: row.threshold_time,
        )
        && list.any(effects_of(sources:, spell4_id: row.id), is_gated_proxy)
      Error(..) -> False
    }
  })
  |> list.map(fn(row) { row.id })
  |> list.sort(int.compare)
}

/// One VitalModifier row as a gain, which must aim at the caster and change vital 6 or 8;
/// its condition is its caster apply and target apply prerequisites (`condition_of`), the
/// target one checked against the caster, the only unit the row reaches. A row with a
/// tickTime is a `TickingGain`, which the cast rule does not apply.
fn gain_row_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Gain, PlanError) {
  use slot <- result.try(case aim_of(target_flags: effect.target_flags) {
    Ok(AimsAtCaster) -> gain_slot_of(spell4_id:, effect:)
    Ok(_) | Error(Nil) ->
      Error(GainAimNotRead(
        spell4_id:,
        effect_id: effect.id,
        target_flags: effect.target_flags,
      ))
  })
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    reach: OnlyTheCaster,
    data_bits06_names_a_gate: False,
  ))
  let effect_id = Spell4EffectsId(effect.id)
  let amount = effect.data_bits02
  let phase_flags = effect.phase_flags
  let tag = tag_of(effect:)
  Ok(case effect.tick_time {
    0 -> Gain(effect_id:, slot:, amount:, phase_flags:, condition:, tag:)
    tick_ms ->
      TickingGain(
        effect_id:,
        slot:,
        amount:,
        phase_flags:,
        condition:,
        tag:,
        tick_ms:,
        duration_ms: effect.duration_time,
      )
  })
}

/// One Heal (type 10) or HealShields (type 118) row that reaches the caster as a heal of
/// `vital`, the one its type names (`effect_kind.kind_of`), or the error that fails the
/// load: its dataBits00 must be a finite 32-bit float and its formula must read only the
/// parameter types an effect on its caster reads (genesis_prime/game/damage `unread`). It
/// aims at the caster when its targetFlags include it and else at the primary target. A
/// row with a tickTime is periodic, a `TickingHeal` with its schedule
/// (genesis_prime/game/ticking `schedule_of`), or `HealUntilRemovedNotRead` for one that
/// lasts until removed.
fn heal_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  vital vital: effect_kind.Vital,
  condition condition: Condition,
) -> Result(Heal, PlanError) {
  use formula <- result.try(
    caster_formula_read(
      formula: damage.formula_of(effect:),
      not_finite: HealNumberNotFinite(spell4_id:, effect_id: effect.id),
      not_read: ParameterNotRead(
        spell4_id:,
        effect_id: effect.id,
        row: HealRow,
        parameter_kind: _,
      ),
    ),
  )
  let effect_id = Spell4EffectsId(effect.id)
  let aim = reached_aim_of(effect:)
  let phase_flags = effect.phase_flags
  let tag = tag_of(effect:)
  case effect.tick_time {
    0 ->
      Ok(Heal(
        effect_id:,
        vital:,
        phase_flags:,
        aim:,
        condition:,
        tag:,
        formula:,
        delay_ms: effect.delay_time,
      ))
    tick_ms ->
      ticking.schedule_of(row: lasting_row_of(effect:), tick_ms:)
      |> result.map(fn(schedule) {
        TickingHeal(
          effect_id:,
          vital:,
          phase_flags:,
          aim:,
          condition:,
          tag:,
          formula:,
          schedule:,
        )
      })
      |> result.map_error(fn(error) {
        case error {
          ticking.UntilRemoved ->
            HealUntilRemovedNotRead(spell4_id:, effect_id: effect.id)
          ticking.NoTick(tick_ms:, duration_ms:) ->
            HealNoTick(spell4_id:, effect_id: effect.id, tick_ms:, duration_ms:)
        }
      })
  }
}

/// One Fluff, Scale, ItemVisualSwap, RavelSignal or area ShieldOverload row as a lasting row: aimed at a
/// unit the plan reads, with the columns that give its node a life (`Spell4Effects.effectType.17`,
/// `.18`, `.76` and `.81`).
fn lasting_of(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Lasting, PlanError) {
  use aim <- result.try(lasting_aim_of(place:, spell4_id:, effect:))
  use condition <- result.map(applied_condition_of(
    tables:,
    effect:,
    reach: reach_in_place(place:, aim:),
  ))
  Lasting(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    aim:,
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
  )
}

/// The columns of a row that give its node a life: its delay and durationTime and whether
/// its flags have bit 2, until removed (`Spell4Effects.effectType.17`).
pub fn lasting_row_of(
  effect effect: spell4_effects.Spell4Effects,
) -> lasting.LastingRow {
  lasting.LastingRow(
    delay_ms: effect.delay_time,
    duration_ms: effect.duration_time,
    until_removed: spell_effect.has_flag(flags: effect.flags, bit: 2),
  )
}

/// One SpellForceRemove row (`Spell4Effects.effectType.80`): dataBits00 picks what is
/// removed (1 a spell group, 2 a Spell4, 3 a Spell4Base) by dataBits01, which must name a
/// row; the count of stacks is read only where dataBits03 and dataBits04 agree.
fn remove_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ForceRemove, PlanError) {
  use aim <- result.try(lasting_aim_of(place:, spell4_id:, effect:))
  use selector <- result.try(selector_of(tables:, sources:, spell4_id:, effect:))
  use Nil <- result.try(force_remove_counts_read(spell4_id:, effect:))
  use condition <- result.map(applied_condition_of(
    tables:,
    effect:,
    reach: reach_in_place(place:, aim:),
  ))
  ForceRemove(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    aim:,
    selector:,
    count: effect.data_bits03,
    condition:,
    tag: tag_of(effect:),
  )
}

/// A type 80 row's count of stacks is read only where dataBits03 and dataBits04 agree
/// (`Spell4Effects.effectType.80`); a row where they differ fails the load.
fn force_remove_counts_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Nil, PlanError) {
  use <- bool.guard(
    when: effect.data_bits03 == effect.data_bits04,
    return: Ok(Nil),
  )
  Error(ForceRemoveCountsDiffer(
    spell4_id:,
    effect_id: effect.id,
    data_bits03: effect.data_bits03,
    data_bits04: effect.data_bits04,
  ))
}

/// One CCStateSet row (`Spell4Effects.effectType.4`): dataBits00 is one of the 28
/// states (`Unit.CodeEnumCCState`, 0 to 27), aimed at the
/// units its flags name (`aim_of`), behind the apply
/// prerequisites `row_condition_of` reads. Its delayTime, durationTime,
/// flags bit 2 (a state that never times out) and the armor it removes (dataBits03) are
/// read as they are. A row that reaches a unit other than the caster and holds its state
/// until removed (no rule ends a creature's state with its cast's node) is `None`, a row
/// the plan drops,
/// and one that keeps its state through a death or a leave by a caster persistence,
/// target persistence or target suspend prerequisite is refused (no creature rule holds
/// that); on the caster both are the cast's own (`cast.restrictions`).
fn control_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Option(CrowdControl), PlanError) {
  use state <- result.try(case effect.data_bits00 {
    state if state >= 0 && state < 28 ->
      Ok(crowd_control_state.from_value(state))
    other ->
      Error(ControlStateNotRead(spell4_id:, effect_id: effect.id, state: other))
  })
  use aim <- result.try(
    aim_of(target_flags: effect.target_flags)
    |> result.replace_error(ControlAimNotRead(
      spell4_id:,
      effect_id: effect.id,
      target_flags: effect.target_flags,
    )),
  )
  let until_removed = spell_effect.has_flag(flags: effect.flags, bit: 2)
  let persists =
    effect.prerequisite_id_caster_persistence != 0
    || effect.prerequisite_id_target_persistence != 0
    || effect.prerequisite_id_target_suspend != 0
  let past_the_caster = reaches_past_caster(aim:)
  use <- bool.guard(when: until_removed && past_the_caster, return: Ok(None))
  use Nil <- result.try(case past_the_caster && persists {
    False -> Ok(Nil)
    True -> Error(ControlPersistenceNotRead(spell4_id:, effect_id: effect.id))
  })
  use condition <- result.try(applied_condition_of(
    tables:,
    effect:,
    reach: reach_in_place(place:, aim:),
  ))
  use move <- result.map(helper_move_of(
    tables:,
    sources:,
    place:,
    state:,
    effect:,
  ))
  Some(CrowdControl(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    aim:,
    row: crowd_control.Row(
      state:,
      delay_ms: effect.delay_time,
      duration_ms: effect.duration_time,
      armor_removed: effect.data_bits03,
      until_removed:,
    ),
    condition:,
    tag: tag_of(effect:),
    move:,
  ))
}

/// Whether a row aims at a unit other than the caster: the primary target or the area
/// (`aim_of`). The server moves those units itself, where the client moves only the
/// caster's own unit (`Spell4Effects.effectType.3.other_unit`).
fn aims_past_the_caster(effect effect: spell4_effects.Spell4Effects) -> Bool {
  aim_of(target_flags: effect.target_flags)
  |> result.map(reaches_past_caster)
  |> result.unwrap(False)
}

/// The move a Knockback, Pushback or Pull state throws its creature by: `None` for
/// every other state, for a spell that throws its creature by its own ForcedMove row
/// (`place.throws_target`) and for a row whose dataBits07 is 0 or names no
/// CCStateAdditionalData row; otherwise the move of the one type 3 row of the helper spell
/// that row names in dataInt00 (`forced_move.of_row`), which must aim past the caster
/// (`aims_past_the_caster`) and hold no apply prerequisite, or the load fails.
fn helper_move_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  place place: RowPlace,
  state state: crowd_control_state.CrowdControlState,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Option(forced_move.Move), PlanError) {
  let throws =
    list.contains(
      [
        crowd_control_state.Knockback,
        crowd_control_state.Pushback,
        crowd_control_state.Pull,
      ],
      state,
    )
  use <- bool.guard(when: !throws || place.throws_target, return: Ok(None))
  let additional =
    cc_state_additional_data.get(
      tables:,
      id: CCStateAdditionalDataId(effect.data_bits07),
    )
  case effect.data_bits07, additional {
    0, _ | _, Error(Nil) -> Ok(None)
    _, Ok(additional) ->
      helper_row_move(sources:, effect:, helper: additional.data_int00)
  }
}

/// The move of the one ForcedMove row of the spell `helper` that `effect`'s state names, or
/// the error `helper_move_of` states when the spell has no such row, more than one, or one
/// that waits on a prerequisite or aims only at the caster.
fn helper_row_move(
  sources sources: Sources,
  effect effect: spell4_effects.Spell4Effects,
  helper helper: Int,
) -> Result(Option(forced_move.Move), PlanError) {
  let not_read =
    ControlHelperNotRead(
      spell4_id: effect.spell_id,
      effect_id: effect.id,
      helper:,
    )
  case
    list.filter(effects_of(sources:, spell4_id: helper), fn(row) {
      effect_kind.kind_of(row.effect_type) == effect_kind.ForcedMove
    })
  {
    [row] -> {
      use <- bool.guard(
        when: row.prerequisite_id_caster_apply != 0
          || row.prerequisite_id_target_apply != 0
          || !aims_past_the_caster(effect: row),
        return: Error(not_read),
      )
      forced_move.of_row(row:)
      |> result.map(Some)
      |> result.map_error(fn(error) {
        StruckMoveNotRead(spell4_id: row.spell_id, effect_id: row.id, error:)
      })
    }
    [] | [_, _, ..] -> Error(not_read)
  }
}

/// One UnitPropertyModifier, UnitPropertyConversion, DisguiseOutfit or Absorption row as a
/// `PropertyModifier` that holds the caster `condition` it was given, or the error that
/// fails the load. A type 11 row (`Spell4Effects.effectType.11.change`): dataBits00 is the
/// property, which UnitProperty2 must have a row for, dataBits01 the mode, dataBits02 the
/// multiplier, dataBits03 the flat amount and dataBits04 the amount for each level, all
/// three as the 32-bit floats their columns hold, which must be finite; a parameter with a
/// factor makes it `ParameterNotRead`. A type 145 row
/// (`conversion_of`).
pub fn modifier_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  condition condition: Condition,
) -> Result(PropertyModifier, PlanError) {
  use change <- result.map(case effect_kind.kind_of(effect.effect_type) {
    effect_kind.DisguiseOutfit ->
      disguise_of(tables:, spell4_id:, effect:)
      |> result.map(LookChange)
    effect_kind.Absorption ->
      absorption_read(spell4_id:, effect:)
      |> result.map(AbsorbChange)
    effect_kind.PropertyConversion ->
      conversion_of(tables:, spell4_id:, effect:)
      |> result.map(PropertyChange)
    effect_kind.PropertyModifier ->
      {
        use Nil <- result.try(modifier_parameters_read(spell4_id:, effect:))
        change_of(tables:, spell4_id:, effect:)
      }
      |> result.map(fn(modifier) {
        case spell_effect.has_flag(flags: effect.target_flags, bit: 1) {
          True -> PropertyChange(modifier:)
          False ->
            StruckChange(
              modifier:,
              aim: aim_of(target_flags: effect.target_flags)
                |> result.unwrap(AimsAtPrimaryTarget),
            )
        }
      })
    effect_kind.Proxy
    | effect_kind.Damage
    | effect_kind.VitalModifier
    | effect_kind.Fluff
    | effect_kind.ForceRemove
    | effect_kind.CrowdControl
    | effect_kind.ForcedMove
    | effect_kind.CooldownModifier
    | effect_kind.Stealth
    | effect_kind.RemoveStealth
    | effect_kind.Heal(..)
    | effect_kind.ShieldOverload
    | effect_kind.InterruptArmor
    | effect_kind.Proc
    | effect_kind.Scale
    | effect_kind.ItemVisualSwap
    | effect_kind.RavelSignal
    | effect_kind.FullScreenEffect
    | effect_kind.Activate
    | effect_kind.Immunity
    | effect_kind.Despawn
    | effect_kind.UnitState
    | effect_kind.NpcExecutionDelay
    | effect_kind.QuestAdvance
    | effect_kind.Unread(..) ->
      change_of(tables:, spell4_id:, effect:)
      |> result.map(PropertyChange)
  })
  PropertyModifier(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    change:,
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
    armor: None,
  )
}

/// A DisguiseOutfit row's change (`Spell4Effects.effectType.112`): dataBits02 is an
/// ItemDisplay worn in its item type's slot and dataBits01 an ItemDisplay of a
/// WeaponPrimary item, each shown in the ItemSlot of its ItemDisplay's item2TypeId. A row
/// with dataBits00 or dataBits08 set is an outfit (`OutfitNeedsMessage0x905`), one with
/// neither display `NamesNoDisplay`, a display with no ItemDisplay, Item2Type or ItemSlot
/// row `NoRow` and a type with no slot `DisplayHasNoSlot`. dataBits03 is not read.
fn disguise_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(look.Disguise, PlanError) {
  use displays <- result.try(disguise_displays_of(spell4_id:, effect:))
  use shown <- result.map(
    list.try_map(displays, fn(display) {
      use item_slot <- result.map(display_slot(
        tables:,
        spell4_id:,
        effect:,
        display:,
      ))
      worn_visual.WornVisual(slot: item_slot, display: ItemDisplayId(display))
    }),
  )
  look.Disguise(shown:)
}

/// The ItemDisplay ids a DisguiseOutfit row shows, dataBits01 then dataBits02, or why
/// 0x933 cannot draw it: dataBits00 or dataBits08 set is an outfit, which only 0x905 draws,
/// and a row with neither display names nothing to show.
fn disguise_displays_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(List(Int), PlanError) {
  let refused = fn(reason) {
    Error(DisguiseNotRead(spell4_id:, effect_id: effect.id, reason:))
  }
  use <- bool.guard(
    when: effect.data_bits00 != 0 || effect.data_bits08 != 0,
    return: refused(OutfitNeedsMessage0x905),
  )
  case list.filter([effect.data_bits01, effect.data_bits02], fn(d) { d != 0 }) {
    [] -> refused(NamesNoDisplay)
    displays -> Ok(displays)
  }
}

/// The ItemSlot an ItemDisplay is worn in: its row's item type's itemSlotId, which
/// must name an ItemSlot row (`0x140466d20`: the slot of an item visual is an ItemSlot
/// id). A missing row fails the load, and an item type with itemSlotId 0 has no slot.
fn display_slot(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  display display: Int,
) -> Result(ItemSlotId, PlanError) {
  use row <- result.try(
    item_display.get(tables:, id: ItemDisplayId(display))
    |> result.replace_error(NoRow(table: "ItemDisplay", id: display)),
  )
  let item_type = item_display.item2_type_id(row)
  use item_type_row <- result.try(
    item2_type.get(tables:, id: item_type)
    |> result.replace_error(NoRow(table: "Item2Type", id: item_type.value)),
  )
  let slot = item2_type.item_slot_id(item_type_row)
  use <- bool.guard(
    when: slot.value == 0,
    return: Error(DisguiseNotRead(
      spell4_id:,
      effect_id: effect.id,
      reason: DisplayHasNoSlot(item_display_id: display),
    )),
  )
  item_slot.get(tables:, id: slot)
  |> result.replace(slot)
  |> result.replace_error(NoRow(table: "ItemSlot", id: slot.value))
}

/// One ModifyInterruptArmor row as the change of property 44 and the armor it makes, or
/// the error that fails the load: dataBits00 is the points, dataBits01 0 or 1 says
/// whether the end takes them back (`Spell4Effects.effectType.52`), and the row's delay,
/// durationTime and flags bit 2 time it as a type 11 row's do. It aims at the caster when
/// its targetFlags include it and else at the primary target.
pub fn interrupt_armor_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  condition condition: Condition,
) -> Result(PropertyModifier, PlanError) {
  use armor <- result.map(interrupt_armor_read(spell4_id:, effect:))
  PropertyModifier(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    change: PropertyChange(modifier: unit_properties.interrupt_armor_modifier(
      points: armor.points,
    )),
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
    armor: Some(armor),
  )
}

/// The armor a ModifyInterruptArmor row gives: its points, whether the end takes them
/// back, and the unit its targetFlags aim at.
fn interrupt_armor_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(InterruptArmor, PlanError) {
  use takes_back <- result.map(case effect.data_bits01 {
    0 -> Ok(False)
    1 -> Ok(True)
    value ->
      Error(InterruptArmorTakeBackNotRead(
        spell4_id:,
        effect_id: effect.id,
        value:,
      ))
  })
  InterruptArmor(
    points: effect.data_bits00,
    takes_back:,
    aim: reached_aim_of(effect:),
  )
}

/// The unit a timed row aims at: the caster for a type 11 row that includes the caster, a
/// type 145 or a type 112 row, which the plan reads only when its targetFlags include the
/// caster; what its targetFlags name for a type 11 row aimed only at other units
/// (`StruckChange`), a type 52 or a type 29 row, the primary target of a cast on the
/// caster being the caster. Only the caster and the creatures a strike hits are changed:
/// the server gives no other unit a property, an armor or a pool.
pub fn modifier_aim(modifier modifier: PropertyModifier) -> Aim {
  case modifier.armor, modifier.change {
    Some(armor), _ -> armor.aim
    None, AbsorbChange(absorption:) -> absorption.aim
    None, StruckChange(aim:, ..) -> aim
    None, PropertyChange(..) | None, LookChange(..) -> AimsAtCaster
  }
}

/// The units a heal, armor or absorb row aims at when its targetFlags reach the caster or
/// the primary target: what `aim_of` reads, and for a value with bit 8 and the caster's bit
/// (9, 11, 13, 15, which the rows are read as today) the caster alone. A row without the
/// caster's bit aims at the primary target, which a spell cast on the caster makes the
/// caster.
fn reached_aim_of(effect effect: spell4_effects.Spell4Effects) -> Aim {
  use <- bool.guard(
    when: !spell_effect.has_flag(flags: effect.target_flags, bit: 1),
    return: AimsAtPrimaryTarget,
  )
  aim_of(target_flags: effect.target_flags)
  |> result.unwrap(AimsAtCaster)
}

/// A formula the caster's own value reads: `formula` as the row gave it, or `not_finite`
/// when a number is not finite, or `not_read` of the first parameter type an effect on its
/// caster does not read (genesis_prime/game/damage `unread`).
fn caster_formula_read(
  formula formula: Result(damage.Formula, Nil),
  not_finite not_finite: PlanError,
  not_read not_read: fn(Int) -> PlanError,
) -> Result(damage.Formula, PlanError) {
  use formula <- result.try(result.replace_error(formula, not_finite))
  case damage.unread_on_caster(formula:) {
    Some(damage.Unread(parameter_kind:)) -> Error(not_read(parameter_kind))
    None -> Ok(formula)
  }
}

/// The words for a kind of row in a plan error's text.
fn parameter_row_name(row row: ParameterRow) -> String {
  case row {
    HealRow -> "a Heal or HealShields"
    AbsorptionRow -> "an Absorption"
    ModifierRow -> "a UnitPropertyModifier"
  }
}

/// The pool an Absorption row gives (`Spell4Effects.effectType.29`), or the error that
/// fails the load: dataBits00 and dataBits01 must be finite 32-bit floats, the formula
/// must read only the parameter types an effect on its caster reads
/// (genesis_prime/game/damage `unread`), the row must not be periodic (a tickTime)
/// and must have a life (a durationTime or flags bit 2). dataBits04 is the damage types it
/// takes, as a mask, and its targetFlags aim it at the caster when they include it and
/// else at the primary target.
fn absorption_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Absorption, PlanError) {
  use formula <- result.try(
    caster_formula_read(
      formula: damage.absorption_formula_of(effect:),
      not_finite: AbsorptionNumberNotFinite(spell4_id:, effect_id: effect.id),
      not_read: ParameterNotRead(
        spell4_id:,
        effect_id: effect.id,
        row: AbsorptionRow,
        parameter_kind: _,
      ),
    ),
  )
  use Nil <- result.try(case effect.tick_time {
    0 -> Ok(Nil)
    tick_ms ->
      Error(AbsorptionPeriodic(spell4_id:, effect_id: effect.id, tick_ms:))
  })
  use Nil <- result.try(case lasting.has_life(row: lasting_row_of(effect:)) {
    True -> Ok(Nil)
    False -> Error(AbsorptionHasNoLifetime(spell4_id:, effect_id: effect.id))
  })
  use Nil <- result.map(case damage.gives_nothing(formula:) {
    False -> Ok(Nil)
    True -> Error(AbsorptionAmountNotRead(spell4_id:, effect_id: effect.id))
  })
  Absorption(formula:, mask: effect.data_bits04, aim: reached_aim_of(effect:))
}

/// A spell a Proxy starts on each unit its area strikes has that unit as its primary
/// target, so a heal, an Interrupt Armor row or an absorb of the spell whose aim names the
/// primary target, alone or with the caster, fails the load: none is built on a struck
/// unit, and a row that names one would otherwise lose that part without a word. A spell
/// started on the caster, and a row aimed at the caster alone or at the caster and the area,
/// are read (`place`).
fn not_on_a_struck_unit(
  place place: RowPlace,
  aim aim: Aim,
  refused refused: fn(StruckBy) -> PlanError,
) -> Result(Nil, PlanError) {
  case place.struck_by, reaches_primary_target(aim:) {
    Some(by), True -> Error(refused(by))
    Some(..), False | None, _ -> Ok(Nil)
  }
}

/// The refusal of a property row on a struck unit: an absorb gives `AbsorptionOnStruckUnit`
/// and an Interrupt Armor row `InterruptArmorOnStruckUnit`. A `StruckChange` is built on
/// the struck unit, so it is never refused.
fn modifier_not_on_a_struck_unit(
  place place: RowPlace,
  modifier modifier: PropertyModifier,
) -> Result(Nil, PlanError) {
  let effect_id = modifier.effect_id.value
  case modifier.change {
    StruckChange(..) -> Ok(Nil)
    AbsorbChange(..) ->
      not_on_a_struck_unit(
        place:,
        aim: modifier_aim(modifier:),
        refused: fn(by) {
          AbsorptionOnStruckUnit(
            spell4_id: by.spell4_id,
            proxy_effect_id: by.proxy_effect_id,
            effect_id:,
          )
        },
      )
    PropertyChange(..) | LookChange(..) ->
      not_on_a_struck_unit(
        place:,
        aim: modifier_aim(modifier:),
        refused: fn(by) {
          InterruptArmorOnStruckUnit(
            spell4_id: by.spell4_id,
            proxy_effect_id: by.proxy_effect_id,
            effect_id:,
          )
        },
      )
  }
}

/// Whether a UnitPropertyModifier row has no parameter with a factor: the plan takes its
/// amount from the data bits alone, so a row with one is `ParameterNotRead`.
fn modifier_parameters_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Nil, PlanError) {
  case damage.first_parameter_with_factor(effect:) {
    Some(damage.Unread(parameter_kind:)) ->
      Error(ParameterNotRead(
        spell4_id:,
        effect_id: effect.id,
        row: ModifierRow,
        parameter_kind:,
      ))
    None -> Ok(Nil)
  }
}

/// A UnitPropertyModifier row's change (`Spell4Effects.effectType.11.change`): dataBits00
/// is the property, which UnitProperty2 must have a row for.
fn change_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(unit_properties.Modifier, PlanError) {
  use property <- result.try(property_of(
    tables:,
    spell4_id:,
    effect:,
    id: effect.data_bits00,
  ))
  use multiplier <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits02",
    bits: effect.data_bits02,
  ))
  use flat <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits03",
    bits: effect.data_bits03,
  ))
  use per_level <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits04",
    bits: effect.data_bits04,
  ))
  Ok(unit_properties.Change(
    property:,
    mode: effect.data_bits01,
    multiplier:,
    flat:,
    per_level:,
  ))
}

/// A UnitPropertyConversion row's change (`Spell4Effects.effectType.145`): property
/// dataBits01 gains the 32-bit float dataBits02, which must be finite, times property
/// dataBits00; UnitProperty2 must have a row for each property.
fn conversion_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(unit_properties.Modifier, PlanError) {
  use from <- result.try(property_of(
    tables:,
    spell4_id:,
    effect:,
    id: effect.data_bits00,
  ))
  use to <- result.try(property_of(
    tables:,
    spell4_id:,
    effect:,
    id: effect.data_bits01,
  ))
  use share <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits02",
    bits: effect.data_bits02,
  ))
  Ok(unit_properties.Conversion(from:, to:, share:))
}

/// The UnitProperty2 id a modifier row names, which the table must have a row for.
fn property_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  id id: Int,
) -> Result(UnitProperty2Id, PlanError) {
  let property = UnitProperty2Id(id)
  unit_property2.get(tables:, id: property)
  |> result.replace(property)
  |> result.replace_error(ModifierPropertyHasNoRow(
    spell4_id:,
    effect_id: effect.id,
    property: id,
  ))
}

/// One ForcedMove row whose targetFlags include the caster (`effect_kind.is_row_read`;
/// `Spell4Effects.effectType.3.player`). Its caster apply prerequisite is read as a Fluff
/// effect's is (`condition_of`).
fn forced_move_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ForcedMove, PlanError) {
  use condition <- result.map(condition_of(
    tables:,
    effect:,
    reach: OnlyTheCaster,
    data_bits06_names_a_gate: False,
  ))
  ForcedMove(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    delay_ms: effect.delay_time,
    condition:,
    tag: tag_of(effect:),
  )
}

/// The part of a ForcedMove row that moves the units other than the caster (targetFlags
/// 2, 4 or 6, or the part of 3, 5 or 7 past the caster's bit; `effect_kind.is_row_read`):
/// its columns as a `forced_move.Move` (`forced_move.of_row`; a dataBits00 above 15 or a
/// float column that is no number fails the load), the `aim` it was given, and its apply
/// prerequisites as a Fluff effect's are (`condition_of`), the target one read for each
/// struck unit it throws, or checked by each creature that holds all it reads
/// (`struck_gates_of`).
fn struck_move_of(
  tables tables: table_store.Tables,
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
  aim aim: Aim,
) -> Result(StruckMove, PlanError) {
  use move <- result.try(
    forced_move.of_row(row: effect)
    |> result.map_error(fn(error) {
      StruckMoveNotRead(
        spell4_id: effect.spell_id,
        effect_id: effect.id,
        error:,
      )
    }),
  )
  use condition <- result.map(condition_of(
    tables:,
    effect:,
    reach: reach_in_place(place:, aim:),
    data_bits06_names_a_gate: False,
  ))
  StruckMove(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    delay_ms: effect.delay_time,
    move:,
    aim:,
    condition:,
    tag: tag_of(effect:),
  )
}

/// One ModifySpellCooldown row whose targetFlags include the caster
/// (`effect_kind.is_row_read`; `Spell4Effects.effectType.73`): dataBits00 picks the
/// spells (0 a Spell4Base, 1 a Spell4, 2 a spell group, 3 a cooldown group, any other
/// value every spell), dataBits01 is the id it compares, dataBits02 the operation and
/// dataBits03 its float, which must be finite where the operation reads it. The id is
/// kept as given and no row is looked up: the client compares it and looks nothing up
/// (`0x14046b920`), so an id no row holds matches nothing on both sides, where a type
/// 80 row's selector must name a row. Its caster apply prerequisite is read as a Fluff
/// effect's is (`condition_of`).
fn cooldown_modifier_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(CooldownModifier, PlanError) {
  use operation <- result.try(cooldown_operation_of(spell4_id:, effect:))
  use condition <- result.map(condition_of(
    tables:,
    effect:,
    reach: OnlyTheCaster,
    data_bits06_names_a_gate: False,
  ))
  CooldownModifier(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    modifier: cooldown.Modifier(
      selector: case effect.data_bits00 {
        0 -> cooldown.Base(Spell4BaseId(effect.data_bits01))
        1 -> cooldown.Spell(Spell4Id(effect.data_bits01))
        2 -> cooldown.SpellGroup(effect.data_bits01)
        3 -> cooldown.CooldownGroup(effect.data_bits01)
        selector -> cooldown.EverySpell(selector:)
      },
      operation:,
    ),
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
  )
}

/// One Stealth effect (`Spell4Effects.effectType.83`) as a row, or the error that fails the
/// load. It must aim at the caster alone (`Spell4Effects.targetFlags` 1) and have no
/// delayTime or durationTime; its dataBits02 is whether damage ends it (`Breaks`), and its
/// apply prerequisites are read as a Fluff effect's are (`condition_of`), the target one on
/// the caster. With no durationTime the stealth lasts until it is removed whatever
/// the row's flags say (`Spell4Effects.effectType.83`), so the row's node never ends by
/// time.
fn stealth_row_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(StealthRow, PlanError) {
  use breaks <- result.try(stealth_read(spell4_id:, effect:))
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    reach: OnlyTheCaster,
    data_bits06_names_a_gate: False,
  ))
  Ok(StealthRow(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    breaks:,
    row: lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition:,
    tag: tag_of(effect:),
  ))
}

/// What a Stealth row says without a table: whether damage ends it, or the error that
/// fails the load: it must aim at the caster alone, have no delayTime or durationTime, and
/// hold a dataBits02 of 0 or 1.
pub fn stealth_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Breaks, PlanError) {
  use Nil <- result.try(stealth_on_the_caster(spell4_id:, effect:))
  use Nil <- result.try(
    case effect.delay_time != 0 || effect.duration_time != 0 {
      True -> Error(StealthTimedNotRead(spell4_id:, effect_id: effect.id))
      False -> Ok(Nil)
    },
  )
  case effect.data_bits02 {
    0 -> Ok(BrokenByDamage)
    1 -> Ok(KeptOnDamage)
    value ->
      Error(StealthBreaksNotRead(spell4_id:, effect_id: effect.id, value:))
  }
}

/// A Stealth or RemoveStealth effect must aim at the caster alone, or the load fails
/// (`Spell4Effects.targetFlags`). Its target apply prerequisite, if any, is checked on the
/// caster (`condition_of`).
pub fn stealth_on_the_caster(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Nil, PlanError) {
  case aim_of(target_flags: effect.target_flags) {
    Ok(AimsAtCaster) -> Ok(Nil)
    Ok(_) | Error(Nil) ->
      Error(StealthAimNotRead(
        spell4_id:,
        effect_id: effect.id,
        target_flags: effect.target_flags,
      ))
  }
}

/// One RemoveStealth effect (`Spell4Effects.effectType.84`) as a row, or the error that fails
/// the load: it must aim at the caster alone.
fn remove_stealth_row_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RemoveStealthRow, PlanError) {
  use Nil <- result.try(stealth_on_the_caster(spell4_id:, effect:))
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    reach: OnlyTheCaster,
    data_bits06_names_a_gate: False,
  ))
  Ok(RemoveStealthRow(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    condition:,
    tag: tag_of(effect:),
  ))
}

/// The Proc effects of a spell (`Spell4Effects.effectType.14`) whose kind the server
/// reads, each with its spell planned as a Proxy's child is, on the same chain, so a
/// proc that leads back to a spell on the way fails as a cycle. A row of another kind is
/// in no list; a row of a kind read with a column the plan does not read fails the load
/// (`proc_read`).
fn procs_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
  chain chain: List(Int),
) -> Result(List(ProcRow), PlanError) {
  rows_of_kind(readings:, kind: effect_kind.Proc)
  |> list.try_map(fn(row) {
    let #(effect, reading) = row
    use reading <- result.try(reading)
    case reading {
      Applied(ReadProc(reading: proc, condition:, event_gate:, holder_gate:))
      | Held(ReadProc(reading: proc, condition:, event_gate:, holder_gate:)) -> {
        use spell <- result.try(spell_of(
          tables:,
          sources:,
          spell4_id: effect.data_bits01,
          chain:,
          threshold_costs: [],
          struck_by: None,
          pressed: False,
        ))
        Ok([
          ProcRow(
            effect_id: Spell4EffectsId(effect.id),
            phase_flags: effect.phase_flags,
            trigger: proc.trigger,
            spell:,
            chance: proc.chance,
            limit: proc.limit,
            filter: proc.filter,
            aim: proc.aim,
            event_gate:,
            holder_gate:,
            delay_ms: proc.delay_ms,
            row: lasting_row_of(effect:),
            condition:,
            tag: tag_of(effect:),
          ),
        ])
      }
      Applied(ReadEffects(..))
      | Applied(ReadProxy(..))
      | Held(ReadEffects(..))
      | Held(ReadProxy(..))
      | LeftOut(..)
      | ReadByArea
      | ReadByActivation -> Ok([])
    }
  })
  |> result.map(list.flatten)
}

/// What a Proc row says without a table: its reading, or why the row is left out. A row
/// of a kind the server does not read is `ProcKindNotRead`, which the load skips, as is
/// a row of a kind the texts name that waits on an open issue (`ProcKindWaits`, checked
/// first) and any row `ProcIsLeftOut` names, in this order: targetFlags other than the caster's
/// alone, a persistence prerequisite, a target apply prerequisite, a group (dataBits08)
/// with no filter kind, a dataBits03 of 32 or above, and a row with no durationTime and
/// no flags bit 2, which gives its holder's node no life. Any other value outside the
/// readings fails the load, naming the first column: a chance not above 0 and at most
/// 1.0, a window or a count that is not above 0 (a window of -1 is `ForLife`), a filter
/// kind other than 0, 1 and 2, and a negative delay
/// (`Spell4Effects.effectType.14.dataBits03`, `.limits`, `.prerequisites`, `.dataBits07`,
/// `.lifetime`).
pub fn proc_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ProcRead, PlanError) {
  case proc_waits_on(kind: effect.data_bits00) {
    Ok(issue) ->
      Ok(ProcIsLeftOut(why: ProcKindWaits(kind: effect.data_bits00, issue:)))
    Error(Nil) -> proc_read_of_a_kind_to_read(spell4_id:, effect:)
  }
}

/// The open issue that raises the event of a fairly-sure kind the server does not raise
/// yet (`Spell4Effects.effectType.14.dataBits00.fairly_sure`): the row is left out naming
/// it, so the issue has its rows to read.
fn proc_waits_on(kind kind: Int) -> Result(Int, Nil) {
  case kind {
    57 | 40 | 117 | 154 -> Ok(869)
    23 | 50 | 114 | 131 | 234 | 249 -> Ok(870)
    124 | 102 | 112 -> Ok(871)
    152 -> Ok(872)
    155 | 197 | 159 | 41 | 153 | 236 -> Ok(801)
    46 -> Ok(803)
    2 -> Ok(56)
    148 -> Ok(830)
    251 | 253 -> Ok(336)
    _ -> Error(Nil)
  }
}

fn proc_read_of_a_kind_to_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ProcRead, PlanError) {
  use trigger <- result.try(case effect.data_bits00 {
    217 -> Ok(EnteredStealth)
    218 -> Ok(LeftStealth)
    44 -> Ok(LeftCombat)
    0 -> Ok(Died)
    12 -> Ok(LandsHit)
    13 -> Ok(LandsMeleeHit)
    145 -> Ok(LandsCritical)
    1 -> Ok(Kills)
    20 -> Ok(LandsHeal)
    147 -> Ok(LandsCriticalHeal)
    10 -> Ok(UsesAbility)
    103 -> Ok(SpendsResource)
    21 -> Ok(ReceivesHeal)
    52 -> Ok(FoeDeflects)
    49 -> Ok(LandsFinisherCritical)
    11 -> Ok(StartsMoving)
    87 -> Ok(ResourceCrosses)
    105 -> Ok(SuitPowerDrops)
    182 -> Ok(LandsTaunt)
    16 -> Ok(TakesDamage)
    146 -> Ok(SuffersCritical)
    51 -> Ok(DeflectsAttack)
    115 -> Ok(ShieldDepleted)
    kind -> Error(ProcKindNotRead(spell4_id:, effect_id: effect.id, kind:))
  })
  let unit_bits = effect.data_bits03
  let left_out = [
    #(
      effect.target_flags != 1,
      ProcHeldByAnotherUnit(target_flags: effect.target_flags),
    ),
    #(
      effect.prerequisite_id_caster_persistence != 0
        || effect.prerequisite_id_target_persistence != 0,
      ProcBehindPersistence,
    ),
    #(effect.prerequisite_id_target_apply != 0, ProcBehindTargetApply),
    #(
      effect.data_bits07 == 0 && effect.data_bits08 != 0,
      ProcGroupWithoutFilter,
    ),
    #(unit_bits >= 32 || unit_bits < 0, ProcAimNotRead(data_bits03: unit_bits)),
    #(
      effect.duration_time <= 0
        && !spell_effect.has_flag(flags: effect.flags, bit: 2),
      ProcWithoutLife,
    ),
  ]
  case list.find(left_out, fn(reason) { reason.0 }) {
    Ok(#(_, why)) -> Ok(ProcIsLeftOut(why:))
    Error(Nil) -> {
      let not_read = fn(column: String, value: Int) {
        Error(ProcNotRead(spell4_id:, effect_id: effect.id, column:, value:))
      }
      case
        float32.of_column(number: effect.data_bits02),
        proc_limit_of(effect:),
        proc_filter_of(effect:)
      {
        Error(Nil), _, _ -> not_read("dataBits02", effect.data_bits02)
        Ok(chance), _, _ if chance <=. 0.0 || chance >. 1.0 ->
          not_read("dataBits02", effect.data_bits02)
        _, Error(#(column, value)), _ | _, _, Error(#(column, value)) ->
          not_read(column, value)
        _, _, _ if effect.delay_time < 0 ->
          not_read("delayTime", effect.delay_time)
        Ok(chance), Ok(limit), Ok(filter) ->
          Ok(
            ProcIsRead(ProcReading(
              trigger:,
              chance:,
              limit:,
              filter:,
              aim: case int.bitwise_and(unit_bits, 4) {
                0 -> AtHolder
                _ -> AtOtherUnit
              },
              event_gate: effect.data_bits06,
              holder_gate: effect.data_bits09,
              delay_ms: effect.delay_time,
            )),
          )
      }
    }
  }
}

/// A Proc row's limit: a window above 0 is `InWindow`, a window of -1 is `ForLife`; any
/// other window or a count not above 0 is the column and value the plan does not read.
fn proc_limit_of(
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ProcLimit, #(String, Int)) {
  case effect.data_bits04, effect.data_bits05 {
    _, count if count <= 0 -> Error(#("dataBits05", count))
    -1, count -> Ok(ForLife(count:))
    window, count if window > 0 -> Ok(InWindow(window_ms: window, count:))
    window, _ -> Error(#("dataBits04", window))
  }
}

/// A Proc row's filter: kind 0 is every spell, 1 the Spell4 and 2 the group dataBits08
/// names; any other kind is the column and value the plan does not read.
///
/// Gap (issue 870): a filter of kind 1 that names Spell4 0 is read like any other and then
/// refused, because the Spell4 table has no row 0 (`NoRow("Spell4", 0)`). The client never
/// reads a Proc row, so nothing says whether it means "every spell"; 17 Proc rows have it
/// (kinds 12, 16 and 117), 4 of them of kind 16 (Procs 92542, 107509, 162927, 189684).
fn proc_filter_of(
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ProcFilter, #(String, Int)) {
  case effect.data_bits07 {
    0 -> Ok(AnySpell)
    1 -> Ok(OneSpell(spell4_id: Spell4Id(effect.data_bits08)))
    2 -> Ok(InGroup(group_id: effect.data_bits08))
    kind -> Error(#("dataBits07", kind))
  }
}

/// The Spell4 ids among `effects` that a Proxy starts as a child on each struck unit: a
/// Proxy whose aim holds the area (`target_of`), each with the first such Proxy in
/// `effects` order. A Proxy of a spell that hits no foes (`spell_hits_foes`) does so only
/// when its aim has no caster's bit, since the area bit of the others is not read there.
pub fn struck_unit_children(
  effects effects: List(spell4_effects.Spell4Effects),
) -> Dict(Int, StruckBy) {
  let hitting = spells_that_hit_foes(effects:)
  list.fold(effects, dict.new(), fn(found, effect) {
    let starts_on_struck_units = case
      effect_kind.kind_of(effect.effect_type) == effect_kind.Proxy
      && effect.data_bits00 != 0,
      aim_of(target_flags: effect.target_flags)
    {
      True, Ok(aim) ->
        reaches_area(aim:)
        && { !reaches_caster(aim:) || set.contains(hitting, effect.spell_id) }
      True, Error(Nil) | False, _ -> False
    }
    case starts_on_struck_units, dict.has_key(found, effect.data_bits00) {
      True, False ->
        dict.insert(
          found,
          effect.data_bits00,
          StruckBy(spell4_id: effect.spell_id, proxy_effect_id: effect.id),
        )
      True, True | False, _ -> found
    }
  })
}

/// Whether a spell with these innate costs spends every point held, which gives each of
/// its effect rows a tag the rule must read (`spend_tag_read`).
fn spends_all_of(costs costs: List(Cost)) -> Bool {
  list.any(costs, fn(cost) {
    case cost {
      SpendAllCost(..) -> True
      SlotCost(..)
      | ClassVitalCost(..)
      | RowClassCost(..)
      | UnheldCost(..)
      | UnreadSpendCost(..) -> False
    }
  })
}

/// Whether the Spell4 row spends every point held, by its two innate costs, as the plan of
/// the spell reads them; false when a cost or its class row is not one the plan reads, since
/// that spell fails its own plan. A stage's threshold costs carry no EMM id, so they never
/// make a spell spend every point.
pub fn spends_all(row row: spell4.Spell4) -> Bool {
  case
    costs_of(
      row:,
      innate: [
        #(row.innate_cost_type0, row.innate_cost0, row.innate_cost_emm_id0),
        #(row.innate_cost_type1, row.innate_cost1, row.innate_cost_emm_id1),
      ],
      threshold: [],
    )
  {
    Ok(costs) -> spends_all_of(costs:)
    Error(..) -> False
  }
}

/// Plans one spell on its own, as a pressed ability, and every spell below it, or why it
/// cannot be planned: the plan's load of a spell, whichever Spell4 row names it. `chain`
/// holds the Spell4 ids from the pressed ability to the spell that casts it, none for a
/// spell planned as an ability, so a tree that leads back to one of them fails as a
/// `ProxyCycle` (genesis_prime/game/server_proxy).
pub fn spell_alone(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
) -> Result(Spell, PlanError) {
  spell_of(
    tables:,
    sources:,
    spell4_id:,
    chain:,
    threshold_costs: [],
    struck_by: None,
    pressed: False,
  )
}

/// A row's reading or the error that fails the load of its spell.
type Reading =
  Result(RowReading, PlanError)

/// The readings of the rows of these kinds, in row order.
fn rows_of_kind(
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
  kind kind: effect_kind.Kind,
) -> List(#(spell4_effects.Spell4Effects, Reading)) {
  list.filter(readings, fn(row) {
    effect_kind.kind_of({ row.0 }.effect_type) == kind
  })
}

/// Whether no row of these kinds is refused: the first error among their readings, in
/// row order.
fn rows_read(
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
  kinds kinds: List(effect_kind.Kind),
) -> Result(Nil, PlanError) {
  list.try_each(readings, fn(row) {
    case list.contains(kinds, effect_kind.kind_of({ row.0 }.effect_type)) {
      True -> result.replace(row.1, Nil)
      False -> Ok(Nil)
    }
  })
}

/// The effects the `Applied` and `Held` readings hold, in row order; a row aimed at the
/// caster and past it adds both its parts, the caster's first. A Proxy's and a Proc's row are
/// made by the spell itself, which plans the spell each names.
fn planted_effects_of(
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
) -> List(PlannedEffect(Kind)) {
  list.flat_map(readings, fn(row) {
    case row.1 {
      Ok(Applied(ReadEffects(effects:))) | Ok(Held(ReadEffects(effects:))) ->
        effects
      Ok(Applied(ReadProc(..)))
      | Ok(Applied(ReadProxy(..)))
      | Ok(Held(ReadProc(..)))
      | Ok(Held(ReadProxy(..)))
      | Ok(LeftOut(..))
      | Ok(ReadByArea)
      | Ok(ReadByActivation)
      | Error(..) -> []
    }
  })
}

/// The `StruckGate` of each row whose target apply prerequisite the load left to the
/// creatures it strikes (`condition_of`: reach `StruckUnits` and
/// `prerequisite.checked_by_creature`), in row order. A damage row is read by the area
/// load with the reach of its aim alone (`row_condition_of`), and one it leaves out
/// (`TickingUntilRemoved`) has no gate.
fn struck_gates_of(
  tables tables: table_store.Tables,
  place place: RowPlace,
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
) -> Result(List(StruckGate), PlanError) {
  list.try_map(readings, fn(row) {
    let effect = row.0
    let aimed = case row.1 {
      Ok(Applied(planned)) ->
        struck_aim_of(planned:)
        |> result.map(fn(aim) { #(aim, reach_in_place(place:, aim:)) })
      Ok(ReadByArea) ->
        case damage_left_out(effect:) {
          True -> Error(Nil)
          False ->
            aim_of(target_flags: effect.target_flags)
            |> result.map(fn(aim) { #(aim, reach_of_aim(aim:)) })
        }
      Ok(Held(..)) | Ok(LeftOut(..)) | Ok(ReadByActivation) | Error(..) ->
        Error(Nil)
    }
    case aimed, effect.prerequisite_id_target_apply {
      Ok(#(aim, StruckUnits)), id if id != 0 -> {
        use target <- result.map(prerequisite_of(tables:, id:))
        case prerequisite.checked_by_creature(prerequisite: target) {
          True -> [
            StruckGate(
              effect_id: Spell4EffectsId(effect.id),
              phase_flags: effect.phase_flags,
              aim:,
              prerequisite: target,
              tag: tag_of(effect:),
            ),
          ]
          False -> []
        }
      }
      _, _ -> Ok([])
    }
  })
  |> result.map(list.flatten)
}

/// The aim of the part of a planned row that a creature the go struck is checked for, when
/// its kind has one: a lasting, remove or crowd-control row, a struck move, or the struck
/// part of a property modifier.
fn struck_aim_of(planned planned: ReadRow) -> Result(Aim, Nil) {
  case planned {
    ReadEffects(effects:) ->
      list.find_map(effects, fn(effect) {
        struck_aim_of_kind(kind: effect.kind)
      })
    ReadProc(..) | ReadProxy(..) -> Error(Nil)
  }
}

fn struck_aim_of_kind(kind kind: Kind) -> Result(Aim, Nil) {
  case kind {
    LastingEffect(lasting:) -> Ok(lasting.aim)
    RemoveEffect(remove:) -> Ok(remove.aim)
    ControlEffect(control:) -> Ok(control.aim)
    StruckMoveEffect(struck_move:) -> Ok(struck_move.aim)
    DespawnEffect(despawn:) -> Ok(despawn.aim)
    UnitStateEffect(unit_state:) -> Ok(unit_state.aim)
    ModifierEffect(modifier:) ->
      case modifier.change {
        StruckChange(aim:, ..) -> Ok(aim)
        PropertyChange(..) | LookChange(..) | AbsorbChange(..) -> Error(Nil)
      }
    GainEffect(..)
    | ForcedMoveEffect(..)
    | CooldownEffect(..)
    | StealthEffect(..)
    | RemoveStealthEffect(..)
    | HealEffect(..)
    | ProcEffect(..)
    | DelayEffect(..)
    | QuestAdvanceEffect(..)
    | ProxyEffect(..) -> Error(Nil)
  }
}

/// Whether the area load leaves this damage row out: a periodic row that lasts until
/// removed (`ticking.schedule_of`).
fn damage_left_out(effect effect: spell4_effects.Spell4Effects) -> Bool {
  effect.tick_time != 0
  && ticking.schedule_of(
    row: lasting_row_of(effect:),
    tick_ms: effect.tick_time,
  )
  == Error(ticking.UntilRemoved)
}

/// The CCStateSet rows the plan drops (`StateUntilRemovedNotRead`), in row order.
fn dropped_controls_of(
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
) -> List(Spell4EffectsId) {
  list.filter_map(readings, fn(row) {
    case row.1 {
      Ok(LeftOut(why: StateUntilRemovedNotRead)) ->
        Ok(Spell4EffectsId({ row.0 }.id))
      Ok(Applied(..))
      | Ok(Held(..))
      | Ok(LeftOut(..))
      | Ok(ReadByArea)
      | Ok(ReadByActivation)
      | Error(..) -> Error(Nil)
    }
  })
}

/// An effect of a spell that spends every point held must hold an emmComparison the rule
/// reads (0 or 1), since each effect's tag chooses by the points spent; a spell with no
/// such cost chooses nothing and its tags are not looked at.
fn spend_tag_read(
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Nil, PlanError) {
  use <- bool.guard(
    when: !place.spends_all || spend.tag_is_read(tag_of(effect:)),
    return: Ok(Nil),
  )
  Error(SpendComparisonNotRead(
    spell4_id: effect.spell_id,
    effect_id: effect.id,
    comparison: effect.emm_comparison,
  ))
}

/// What the plan makes of one Spell4Effects row, in the place its spell is planned: the
/// one decision the plan's lists are made from and the coverage measure counts by.
///
/// - `Applied` and `Held` rows are in a list of their spell (`Held`: no go applies them,
///   among them a row with no life or with phaseFlags 0), `LeftOut` rows are in none and
///   the load goes on, and a damage row is `ReadByArea`.
/// - An error is what fails the load of the row's spell: a row the tables lack, a column
///   the plan does not read, a spell that spends every point with a tag the rule does not
///   read, or a heal, armor or absorb on the primary target of a spell a Proxy starts on
///   each struck unit (`place`).
/// - Each row is read by the rule of its type: `gain_row_of`, `lasting_of`, `remove_of`,
///   `control_of`, `modifier_of`, `interrupt_armor_of`, `forced_move_of`,
///   `cooldown_modifier_of`, `stealth_row_of`, `remove_stealth_row_of`, `heal_of`,
///   `proc_read`, and for a Proxy `target_of` and `proxy_condition_of`.
///
/// A Proxy's child and a Proc's spell are planned by the spell that holds the row; a
/// refused child is counted on the child's own rows.
pub fn read_row(
  tables tables: table_store.Tables,
  sources sources: Sources,
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  use Nil <- result.try(spend_tag_read(place:, effect:))
  use reading <- result.map(kind_reading(tables:, sources:, place:, effect:))
  held_without_a_phase(reading:, effect:)
}

/// A row whose phaseFlags is 0 is selected by no phase, so no go applies it
/// (`in_phase`): an `Applied` row is `Held`, and a damage row is left out. What the client
/// means by phaseFlags 0 is not known.
fn held_without_a_phase(
  reading reading: RowReading,
  effect effect: spell4_effects.Spell4Effects,
) -> RowReading {
  use <- bool.guard(when: effect.phase_flags != 0, return: reading)
  case reading {
    Applied(row) -> Held(row)
    ReadByArea | ReadByActivation -> LeftOut(why: InNoPhase)
    Held(..) | LeftOut(..) -> reading
  }
}

/// What the rule of the row's type makes of it, before the phases are looked at.
fn kind_reading(
  tables tables: table_store.Tables,
  sources sources: Sources,
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  let spell4_id = effect.spell_id
  let reaches =
    effect_kind.is_row_read(
      effect_type: effect.effect_type,
      target_flags: effect.target_flags,
    )
  case effect_kind.kind_of(effect.effect_type) {
    effect_kind.VitalModifier ->
      gain_row_of(tables:, spell4_id:, effect:)
      |> result.map(fn(gain) {
        case gain {
          Gain(..) -> Applied(read_as(GainEffect(gain:)))
          TickingGain(..) -> Held(read_as(GainEffect(gain:)))
        }
      })
    effect_kind.Fluff | effect_kind.Scale | effect_kind.RavelSignal ->
      lasting_reading(tables:, place:, spell4_id:, effect:)
    effect_kind.ItemVisualSwap ->
      lasting_reading(tables:, place:, spell4_id:, effect:)
      |> result.map(held_while_delayed(reading: _, effect:))
    effect_kind.ShieldOverload | effect_kind.FullScreenEffect -> {
      use <- when_reached(reaches:)
      lasting_reading(tables:, place:, spell4_id:, effect:)
    }
    effect_kind.ForceRemove ->
      remove_of(tables:, sources:, place:, spell4_id:, effect:)
      |> result.map(fn(remove) { Applied(read_as(RemoveEffect(remove:))) })
    effect_kind.CrowdControl ->
      control_of(tables:, sources:, place:, spell4_id:, effect:)
      |> result.map(fn(control) {
        case control {
          Some(control) -> Applied(read_as(ControlEffect(control:)))
          None -> LeftOut(why: StateUntilRemovedNotRead)
        }
      })
    effect_kind.PropertyModifier
    | effect_kind.PropertyConversion
    | effect_kind.DisguiseOutfit
    | effect_kind.Absorption -> {
      use <- when_reached(reaches:)
      modifier_reading(tables:, place:, spell4_id:, effect:)
    }
    effect_kind.InterruptArmor -> {
      use <- when_reached(reaches:)
      interrupt_armor_reading(tables:, place:, spell4_id:, effect:)
    }
    effect_kind.ForcedMove -> {
      use <- when_reached(reaches:)
      planned_in_parts(
        aim: row_aim_of(place:, effect:),
        caster_part: fn() {
          forced_move_of(tables:, effect:)
          |> result.map(fn(forced_move) { ForcedMoveEffect(forced_move:) })
        },
        past_part: fn(aim) {
          struck_move_of(tables:, place:, effect:, aim:)
          |> result.map(fn(struck_move) { StruckMoveEffect(struck_move:) })
        },
      )
      |> result.map(fn(kinds) { Applied(read_kinds(kinds:)) })
    }
    effect_kind.CooldownModifier -> {
      use <- when_reached(reaches:)
      cooldown_modifier_of(tables:, spell4_id:, effect:)
      |> result.map(fn(modifier) { Applied(read_as(CooldownEffect(modifier:))) })
    }
    effect_kind.Stealth ->
      stealth_row_of(tables:, spell4_id:, effect:)
      |> result.map(fn(stealth) { Applied(read_as(StealthEffect(stealth:))) })
    effect_kind.RemoveStealth ->
      remove_stealth_row_of(tables:, spell4_id:, effect:)
      |> result.map(fn(remove) {
        Applied(read_as(RemoveStealthEffect(remove:)))
      })
    effect_kind.Heal(vital:) -> {
      use <- when_reached(reaches:)
      heal_reading(tables:, place:, spell4_id:, effect:, vital:)
    }
    effect_kind.Proc -> proc_reading(tables:, spell4_id:, effect:)
    effect_kind.Proxy ->
      case effect.data_bits00 {
        0 -> Ok(LeftOut(why: ProxyNamesNoSpell))
        _ -> {
          use targets <- result.try(target_of(place:, spell4_id:, effect:))
          use condition <- result.map(proxy_condition_of(tables:, effect:))
          Applied(ReadProxy(targets:, condition:))
        }
      }
    effect_kind.Damage -> Ok(ReadByArea)
    effect_kind.Activate -> Ok(ReadByActivation)
    effect_kind.Despawn -> despawn_reading(tables:, place:, effect:)
    effect_kind.UnitState -> unit_state_reading(tables:, place:, effect:)
    effect_kind.NpcExecutionDelay -> Ok(delay_reading(reaches:, effect:))
    effect_kind.QuestAdvance -> {
      use <- when_reached(reaches:)
      quest_advance_reading(tables:, effect:)
    }
    effect_kind.Immunity | effect_kind.Unread(..) ->
      Ok(LeftOut(why: TypeNotRead))
  }
}

/// An NpcExecutionDelay row (`Spell4Effects.effectType.35`) as a `Delay` when it is aimed at
/// the caster alone (`reaches`, `effect_kind.is_row_read`) and has a durationTime: left out
/// with `DelayOnAnotherUnit` when it is aimed at any other unit and with `DelayHasNoDuration`
/// when it holds its caster still for nothing. Its prerequisites are not read here; the
/// creature special load refuses a row behind one (genesis_prime/world_map/creature_attack
/// `special_checked`), and the coverage measure counts the row read.
fn delay_reading(
  reaches reaches: Bool,
  effect effect: spell4_effects.Spell4Effects,
) -> RowReading {
  case reaches, effect.duration_time > 0 {
    False, _ -> LeftOut(why: DelayOnAnotherUnit)
    True, False -> LeftOut(why: DelayHasNoDuration)
    True, True ->
      Applied(
        read_as(
          DelayEffect(delay: Delay(
            effect_id: Spell4EffectsId(effect.id),
            phase_flags: effect.phase_flags,
            delay_ms: effect.delay_time,
            duration_ms: effect.duration_time,
            tag: tag_of(effect:),
          )),
        ),
      )
  }
}

/// A QuestAdvanceObjective row (`Spell4Effects.effectType.42`) as a `QuestAdvance` on the
/// caster (bit 1 of its targetFlags) or, for a row aimed at the primary target alone, on the
/// primary target, which is the caster in a press: left out with `QuestAdvanceColumnNotRead` when
/// a column the client does not read for the type is not 0 (`quest_advance_unread_column`) and
/// with `QuestAdvanceAddsNothing` when the amount is below 1. Its apply prerequisites are read
/// as a heal's are (`applied_condition_of`). The quest and the index are not looked up: a pair
/// the tables lack names no objective at run time.
fn quest_advance_reading(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  case quest_advance_unread_column(effect:), effect.data_bits02 < 1 {
    Some(column), _ -> Ok(LeftOut(why: QuestAdvanceColumnNotRead(column:)))
    None, True -> Ok(LeftOut(why: QuestAdvanceAddsNothing))
    None, False -> {
      let aim = quest_advance_aim_of(target_flags: effect.target_flags)
      // Both aims land on the caster's own unit, which a target apply prerequisite reads as
      // its first unit; a row aimed at a creature advances nothing, so no creature's state is
      // read for it.
      use condition <- result.map(applied_condition_of(
        tables:,
        effect:,
        reach: OnlyTheCaster,
      ))
      Applied(
        read_as(
          QuestAdvanceEffect(quest_advance: QuestAdvance(
            effect_id: Spell4EffectsId(effect.id),
            phase_flags: effect.phase_flags,
            aim:,
            condition:,
            tag: tag_of(effect:),
            quest_id: effect.data_bits00,
            objective_index: effect.data_bits01,
            amount: effect.data_bits02,
            delay_ms: effect.delay_time,
          )),
        ),
      )
    }
  }
}

/// The aim of a QuestAdvanceObjective row from its `targetFlags`: the caster when bit 1 is set,
/// else the primary target (the plan reads no area for the type, `effect_kind.is_row_read`).
pub fn quest_advance_aim_of(target_flags target_flags: Int) -> Aim {
  use <- bool.guard(
    when: spell_effect.has_flag(flags: target_flags, bit: 1),
    return: AimsAtCaster,
  )
  AimsAtPrimaryTarget
}

/// Whether a QuestAdvanceObjective row aimed by `aim` lands on the caster: its aim names the
/// caster, or names the primary target and the primary target is the caster (a press of a spell
/// on the caster). Any other row reaches a unit with no player quest log and advances nothing (a
/// guess: `Spell4Effects.targetFlags` has no reader in the client). The cast's go and the
/// coverage measure of an activate cast, whose primary target is the activated unit, both read
/// this.
pub fn quest_advance_lands_on_the_caster(
  aim aim: Aim,
  primary_target_is_caster primary_target_is_caster: Bool,
) -> Bool {
  reaches_caster(aim:)
  || { reaches_primary_target(aim:) && primary_target_is_caster }
}

/// The first column of a QuestAdvanceObjective row that the client does not read for the type
/// and that is not 0: the tick and duration, the damage type, the flags, dataBits03 to
/// dataBits09, the four parameter types and the persistence and suspend prerequisites.
fn quest_advance_unread_column(
  effect effect: spell4_effects.Spell4Effects,
) -> Option(String) {
  [
    #("tickTime", effect.tick_time),
    #("durationTime", effect.duration_time),
    #("damageType", effect.damage_type),
    #("flags", effect.flags),
    #("dataBits03", effect.data_bits03),
    #("dataBits04", effect.data_bits04),
    #("dataBits05", effect.data_bits05),
    #("dataBits06", effect.data_bits06),
    #("dataBits07", effect.data_bits07),
    #("dataBits08", effect.data_bits08),
    #("dataBits09", effect.data_bits09),
    #("parameterType00", effect.parameter_type00),
    #("parameterType01", effect.parameter_type01),
    #("parameterType02", effect.parameter_type02),
    #("parameterType03", effect.parameter_type03),
    #(
      "prerequisiteIdCasterPersistence",
      effect.prerequisite_id_caster_persistence,
    ),
    #(
      "prerequisiteIdTargetPersistence",
      effect.prerequisite_id_target_persistence,
    ),
    #("prerequisiteIdTargetSuspend", effect.prerequisite_id_target_suspend),
  ]
  |> list.find(fn(column) { column.1 != 0 })
  |> result.map(fn(column) { column.0 })
  |> option.from_result
}

/// A DespawnUnit row (`Spell4Effects.effectType.97`) as a `Despawn` of the part of its aim
/// past the caster (`past_the_caster`): left out with `DespawnAimedAtTheCasterOnly` when it
/// aims at the caster alone and with `DespawnDataNotRead` when dataBits00 or dataBits01 is
/// not 0, and `Held` when its phaseFlags is 0 (`held_without_a_phase`). A flags value no aim
/// reads is left out as aimed at other units. Its apply prerequisites are read as a throw's
/// are (`applied_condition_of`), the target one checked by each struck creature that holds
/// all it reads (`struck_gates_of`).
fn despawn_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  case aim_of(target_flags: effect.target_flags) {
    Error(Nil) -> Ok(LeftOut(why: AimedAtOtherUnits))
    Ok(aim) ->
      case past_the_caster(aim: aim_in_place(place:, aim:)) {
        Error(Nil) -> Ok(LeftOut(why: DespawnAimedAtTheCasterOnly))
        Ok(past) ->
          case effect.data_bits00, effect.data_bits01 {
            0, 0 -> {
              use condition <- result.map(applied_condition_of(
                tables:,
                effect:,
                reach: reach_in_place(place:, aim: past),
              ))
              Applied(
                read_as(
                  DespawnEffect(despawn: Despawn(
                    effect_id: Spell4EffectsId(effect.id),
                    phase_flags: effect.phase_flags,
                    delay_ms: effect.delay_time,
                    aim: past,
                    condition:,
                    tag: tag_of(effect:),
                  )),
                ),
              )
            }
            0, _ -> Ok(LeftOut(why: DespawnDataNotRead(column: "dataBits01")))
            _, _ -> Ok(LeftOut(why: DespawnDataNotRead(column: "dataBits00")))
          }
      }
  }
}

/// A UnitStateSet row (`Spell4Effects.effectType.15`) as a `UnitState` of the part of its aim
/// past the caster (`past_the_caster`), and `Held` when its phaseFlags is 0
/// (`held_without_a_phase`). It is left out by name when it aims at the caster alone
/// (`UnitStateAimedAtTheCasterOnly`), lasts until removed (`UnitStateUntilRemoved`, flags bit
/// 2: no rule ends a creature's state with its cast), is behind a caster persistence, target
/// persistence or target suspend prerequisite (`UnitStateBehindPersistence`: no creature rule
/// keeps a state through a death or a leave, and the spell still plans) or has a dataBits01 to
/// dataBits09 that is not 0 (`UnitStateDataNotRead`: no client code reads a row of the type).
/// A flags value no aim reads is left out as aimed at other units. Its apply prerequisites are
/// read as a despawn's are (`applied_condition_of`), the target one checked by each struck
/// creature that holds all it reads (`struck_gates_of`).
fn unit_state_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  case aim_of(target_flags: effect.target_flags) {
    Error(Nil) -> Ok(LeftOut(why: AimedAtOtherUnits))
    Ok(aim) ->
      case past_the_caster(aim: aim_in_place(place:, aim:)) {
        Error(Nil) -> Ok(LeftOut(why: UnitStateAimedAtTheCasterOnly))
        Ok(past) ->
          case unit_state_left_out(effect:) {
            Some(why) -> Ok(LeftOut(why:))
            None -> {
              use condition <- result.map(applied_condition_of(
                tables:,
                effect:,
                reach: reach_in_place(place:, aim: past),
              ))
              Applied(
                read_as(
                  UnitStateEffect(unit_state: UnitState(
                    effect_id: Spell4EffectsId(effect.id),
                    phase_flags: effect.phase_flags,
                    aim: past,
                    row: unit_state.Row(
                      state: effect.data_bits00,
                      delay_ms: effect.delay_time,
                      duration_ms: effect.duration_time,
                    ),
                    condition:,
                    tag: tag_of(effect:),
                  )),
                ),
              )
            }
          }
      }
  }
}

/// Why a UnitStateSet row aimed past the caster is left out, in the order the reasons are
/// tried: it lasts until removed, it is behind a persistence prerequisite, or one of its
/// dataBits01 to dataBits09 is not 0 (the first such column is named).
fn unit_state_left_out(
  effect effect: spell4_effects.Spell4Effects,
) -> Option(LeftOutReason) {
  let columns = [
    #("dataBits01", effect.data_bits01),
    #("dataBits02", effect.data_bits02),
    #("dataBits03", effect.data_bits03),
    #("dataBits04", effect.data_bits04),
    #("dataBits05", effect.data_bits05),
    #("dataBits06", effect.data_bits06),
    #("dataBits07", effect.data_bits07),
    #("dataBits08", effect.data_bits08),
    #("dataBits09", effect.data_bits09),
  ]
  case
    spell_effect.has_flag(flags: effect.flags, bit: 2),
    effect.prerequisite_id_caster_persistence != 0
    || effect.prerequisite_id_target_persistence != 0
    || effect.prerequisite_id_target_suspend != 0,
    list.find(columns, fn(column) { column.1 != 0 })
  {
    True, _, _ -> Some(UnitStateUntilRemoved)
    False, True, _ -> Some(UnitStateBehindPersistence)
    False, False, Ok(#(column, _)) -> Some(UnitStateDataNotRead(column:))
    False, False, Error(Nil) -> None
  }
}

/// The row as `LeftOut` when its targetFlags do not reach a unit the type is read for
/// (`effect_kind.is_row_read`), and else what `then` makes of it.
fn when_reached(
  reaches reaches: Bool,
  then then: fn() -> Result(RowReading, PlanError),
) -> Result(RowReading, PlanError) {
  use <- bool.guard(when: !reaches, return: Ok(LeftOut(why: AimedAtOtherUnits)))
  then()
}

/// An ItemVisualSwap row with a delayTime as `Held`: the client applies an effect from
/// the go only when its delay is 0 (`0x1405d6880.delayed_apply`), so the go lists the row
/// with its delay and the visual does not change (the gap is #827). A row with no delay
/// stays `Applied`.
fn held_while_delayed(
  reading reading: RowReading,
  effect effect: spell4_effects.Spell4Effects,
) -> RowReading {
  use <- bool.guard(when: effect.delay_time == 0, return: reading)
  case reading {
    Applied(row) -> Held(row)
    Held(..) | LeftOut(..) | ReadByArea | ReadByActivation -> reading
  }
}

/// A Fluff, Scale, ItemVisualSwap, RavelSignal, area ShieldOverload or caster-aimed
/// FullScreenEffect row as a lasting row.
fn lasting_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  lasting_of(tables:, place:, spell4_id:, effect:)
  |> result.map(fn(lasting) { Applied(read_as(LastingEffect(lasting:))) })
}

/// A UnitPropertyModifier, UnitPropertyConversion, DisguiseOutfit or Absorption row that
/// reaches the caster, or a UnitPropertyModifier row that reaches the units a strike hits:
/// held when, for a disguise, it has no life, which no go applies (`lasting.has_life`).
fn modifier_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  case effect_kind.kind_of(effect.effect_type) == effect_kind.PropertyModifier {
    True -> property_modifier_reading(tables:, place:, spell4_id:, effect:)
    False -> {
      use condition <- result.try(applied_condition_of(
        tables:,
        effect:,
        reach: reach_of_flags(target_flags: effect.target_flags),
      ))
      use modifier <- result.try(modifier_of(
        tables:,
        spell4_id:,
        effect:,
        condition:,
      ))
      let modifier = modifier_in_place(place:, modifier:)
      use Nil <- result.map(modifier_not_on_a_struck_unit(place:, modifier:))
      by_life(modifier:)
    }
  }
}

/// A UnitPropertyModifier row (`Spell4Effects.effectType.11`): a `PropertyChange` on the
/// caster when its aim names the caster, and a `StruckChange` on the units it names past the
/// caster, each behind the condition its units are checked by (the target apply
/// prerequisite is read for the caster alone in the one and for struck units in the other).
fn property_modifier_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  let modifier_with = fn(reach, change_of_modifier) {
    use condition <- result.try(applied_condition_of(tables:, effect:, reach:))
    use modifier <- result.map(modifier_of(
      tables:,
      spell4_id:,
      effect:,
      condition:,
    ))
    ModifierEffect(
      modifier: PropertyModifier(
        ..modifier,
        change: change_of_modifier(modifier.change),
      ),
    )
  }
  planned_in_parts(
    aim: row_aim_of(place:, effect:),
    caster_part: fn() { modifier_with(OnlyTheCaster, fn(change) { change }) },
    past_part: fn(aim) {
      modifier_with(reach_in_place(place:, aim:), fn(change) {
        case change {
          PropertyChange(modifier:) | StruckChange(modifier:, ..) ->
            StruckChange(modifier:, aim:)
          LookChange(..) | AbsorbChange(..) -> change
        }
      })
    },
  )
  |> result.map(fn(kinds) {
    let planned = read_kinds(kinds:)
    case lasting.has_life(row: lasting_row_of(effect:)) {
      True -> Applied(planned)
      False -> Held(planned)
    }
  })
}

/// A row aimed at the caster and past it as its two parts, each planned by the part's own
/// reading: the caster's alone for an aim at the caster, the part past it alone for an aim
/// that does not name the caster, and both, the caster's first, for one that names both.
/// `past_part` is given the aim without the caster's bit (`past_the_caster`).
fn planned_in_parts(
  aim aim: Aim,
  caster_part caster_part: fn() -> Result(Kind, PlanError),
  past_part past_part: fn(Aim) -> Result(Kind, PlanError),
) -> Result(List(Kind), PlanError) {
  case past_the_caster(aim:) {
    Error(Nil) -> caster_part() |> result.map(fn(caster) { [caster] })
    Ok(past) ->
      case reaches_caster(aim:) {
        False -> past_part(past) |> result.map(fn(past) { [past] })
        True -> {
          use caster <- result.try(caster_part())
          use past <- result.map(past_part(past))
          [caster, past]
        }
      }
  }
}

/// The row as the one effect of this kind.
fn read_as(kind: Kind) -> ReadRow {
  read_kinds(kinds: [kind])
}

/// The row as the effects of these kinds, in order.
fn read_kinds(kinds kinds: List(Kind)) -> ReadRow {
  ReadEffects(effects: list.map(kinds, effect_of))
}

/// The aim of a row of a kind the plan reads for the caster and the units past it
/// (`effect_kind.is_row_read`), in this place: what `aim_of` reads, with a friendly spell's
/// area left out (`aim_in_place`), and the caster alone for a value with bit 8 and the
/// caster's bit (9, 11, 13, 15), which the rows are read as today ([B8]).
fn row_aim_of(
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Aim {
  aim_of(target_flags: effect.target_flags)
  |> result.map(aim_in_place(place:, aim: _))
  |> result.unwrap(AimsAtCaster)
}

/// The aim in a place: the area's bit is read only in a spell that hits foes. A friendly
/// spell's area waits for #834, so a row of a kind that reads the caster and the units
/// past it keeps its caster and primary target parts ([F] `spell_hits_foes`).
fn aim_in_place(place place: RowPlace, aim aim: Aim) -> Aim {
  use <- bool.guard(when: place.hits_foes, return: aim)
  without_friendly_area(aim:)
}

/// The modifier with its absorb's or armor's aim as the place reads it (`aim_in_place`).
fn modifier_in_place(
  place place: RowPlace,
  modifier modifier: PropertyModifier,
) -> PropertyModifier {
  case modifier.armor, modifier.change {
    Some(armor), _ ->
      PropertyModifier(
        ..modifier,
        armor: Some(
          InterruptArmor(..armor, aim: aim_in_place(place:, aim: armor.aim)),
        ),
      )
    None, AbsorbChange(absorption:) ->
      PropertyModifier(
        ..modifier,
        change: AbsorbChange(
          Absorption(
            ..absorption,
            aim: aim_in_place(place:, aim: absorption.aim),
          ),
        ),
      )
    None, PropertyChange(..) | None, StruckChange(..) | None, LookChange(..) ->
      modifier
  }
}

/// A property row as `Held` when it has no life (`lasting.has_life`), which the cast rule
/// drops, and else `Applied`.
fn by_life(modifier modifier: PropertyModifier) -> RowReading {
  let planned = read_as(ModifierEffect(modifier:))
  case lasting.has_life(row: modifier.row) {
    True -> Applied(planned)
    False -> Held(planned)
  }
}

/// A ModifyInterruptArmor row that reaches the caster or the primary target.
fn interrupt_armor_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  use condition <- result.try(applied_condition_of(
    tables:,
    effect:,
    reach: reach_of_flags(target_flags: effect.target_flags),
  ))
  use modifier <- result.try(interrupt_armor_of(spell4_id:, effect:, condition:))
  let modifier = modifier_in_place(place:, modifier:)
  use Nil <- result.map(modifier_not_on_a_struck_unit(place:, modifier:))
  by_life(modifier:)
}

/// A Heal or HealShields row that reaches the caster or the primary target: a periodic heal
/// that lasts until removed is left out (`HealUntilRemoved`).
fn heal_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  vital vital: effect_kind.Vital,
) -> Result(RowReading, PlanError) {
  use condition <- result.try(applied_condition_of(
    tables:,
    effect:,
    reach: reach_of_flags(target_flags: effect.target_flags),
  ))
  use heal <- try_heal(heal_of(spell4_id:, effect:, vital:, condition:))
  let heal = heal_in_place(place:, heal:)
  use Nil <- result.map(
    not_on_a_struck_unit(place:, aim: heal.aim, refused: fn(by) {
      HealOnStruckUnit(
        spell4_id: by.spell4_id,
        proxy_effect_id: by.proxy_effect_id,
        effect_id: effect.id,
      )
    }),
  )
  Applied(read_as(HealEffect(heal:)))
}

/// The heal with its aim as the place reads it (`aim_in_place`).
fn heal_in_place(place place: RowPlace, heal heal: Heal) -> Heal {
  let aim = aim_in_place(place:, aim: heal.aim)
  case heal {
    Heal(..) -> Heal(..heal, aim:)
    TickingHeal(..) -> TickingHeal(..heal, aim:)
  }
}

/// Goes on with a heal, or leaves out a periodic heal that lasts until removed.
fn try_heal(
  heal heal: Result(Heal, PlanError),
  then then: fn(Heal) -> Result(RowReading, PlanError),
) -> Result(RowReading, PlanError) {
  case heal {
    Ok(heal) -> then(heal)
    Error(HealUntilRemovedNotRead(..)) -> Ok(LeftOut(why: HealUntilRemoved))
    Error(error) -> Error(error)
  }
}

/// A Proc row: left out when its kind is one the holder's own events do not make or its
/// shape is one a rule does not hold (`proc_read`) or its dataBits01 names a Spell4 the
/// tables lack (`ProcCastsNoSpell`), else its reading with its caster condition and its
/// two gates, the Prerequisite rows its dataBits06 and dataBits09 name; a gate or a
/// one-spell filter naming a row the tables lack fails the load.
fn proc_reading(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  case proc_read(spell4_id:, effect:) {
    Error(ProcKindNotRead(kind:, ..)) ->
      Ok(LeftOut(why: ProcOfAnotherKind(kind:)))
    Error(error) -> Error(error)
    Ok(ProcIsLeftOut(why:)) -> Ok(LeftOut(why:))
    Ok(ProcIsRead(reading:)) ->
      case spell4.get(tables:, id: Spell4Id(effect.data_bits01)) {
        Error(Nil) ->
          Ok(LeftOut(why: ProcCastsNoSpell(spell4_id: effect.data_bits01)))
        Ok(_) -> proc_read_with_gates(tables:, effect:, reading:)
      }
  }
}

/// The reading of a Proc row whose spell has its row, with its condition and its gates.
fn proc_read_with_gates(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
  reading reading: ProcReading,
) -> Result(RowReading, PlanError) {
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    reach: OnlyTheCaster,
    data_bits06_names_a_gate: False,
  ))
  use event_gate <- result.try(proc_gate_of(tables:, id: reading.event_gate))
  use holder_gate <- result.try(proc_gate_of(tables:, id: reading.holder_gate))
  use Nil <- result.map(case reading.filter {
    OneSpell(spell4_id: named) ->
      spell4.get(tables:, id: named)
      |> result.replace(Nil)
      |> result.replace_error(NoRow(table: "Spell4", id: named.value))
    AnySpell | InGroup(..) -> Ok(Nil)
  })
  Applied(ReadProc(reading:, condition:, event_gate:, holder_gate:))
}

/// The Prerequisite a Proc gate column names: none for 0, else its row, which the tables
/// must hold.
fn proc_gate_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Option(Prerequisite), PlanError) {
  case id {
    0 -> Ok(None)
    id -> prerequisite_of(tables:, id:) |> result.map(Some)
  }
}

/// What the spell does to the caster's stealth, from the spell's spellCastStealthChange:
/// 0 is `EndsStealthAtEachGo`, 1 is `EndsStealthAfterLastGo`, 2 is `KeepsStealth`, and
/// any other value fails the load (`Spell4.spellCastStealthChange`).
pub fn stealth_change_of(
  spell4_id spell4_id: Int,
  value value: Int,
) -> Result(StealthChange, PlanError) {
  case value {
    0 -> Ok(EndsStealthAtEachGo)
    1 -> Ok(EndsStealthAfterLastGo)
    2 -> Ok(KeepsStealth)
    value -> Error(StealthChangeNotRead(spell4_id:, value:))
  }
}

/// A spell whose caster or target Spell4Conditions row tests stealth (mask bit 16) fails
/// the load: the client refuses such a cast with 65 or 114, and the server does not
/// check those results (`Spell4Conditions.conditionMask.16`). The place for the check,
/// when a spell needs it, is `cast_press.verdict` after the dead test.
pub fn stealth_conditions_read(
  spell4_id spell4_id: Int,
  conditions conditions: List(Option(spell4_conditions.Spell4Conditions)),
) -> Result(Nil, PlanError) {
  list.try_each(conditions, fn(conditions) {
    case conditions {
      Some(condition) ->
        case spell_effect.has_flag(flags: condition.condition_mask, bit: 16) {
          True ->
            Error(StealthConditionNotRead(
              spell4_id:,
              spell4_conditions_id: condition.id,
            ))
          False -> Ok(Nil)
        }
      None -> Ok(Nil)
    }
  })
}

/// A cooldown effect's operation (dataBits02) with its float (dataBits03): the 32-bit
/// float its column holds, which must be finite. An operation the client has no case for
/// reads no float (`0x14046b920`).
fn cooldown_operation_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(cooldown.Operation, PlanError) {
  let number = fn() {
    float32.of_column(number: effect.data_bits03)
    |> result.replace_error(CooldownNumberNotFinite(
      spell4_id:,
      effect_id: effect.id,
    ))
  }
  case effect.data_bits02 {
    0 -> result.map(number(), cooldown.NoLonger)
    1 -> result.map(number(), cooldown.Multiply)
    2 -> result.map(number(), cooldown.AddMs)
    3 -> result.map(number(), cooldown.SetMs)
    operation -> Ok(cooldown.Unchanged(operation:))
  }
}

/// The cooldown groups of a spell: the non-zero of spellCoolDownId00 to 02, each of
/// which must be a SpellCoolDown row, as the client's StartSpellCooldowns reports an
/// error for a group it finds none for (`0x14046b1e0`). A group runs for its row's
/// `cooldownTime`; a row of 0 gives the spell's own cooldown when one of the spell's tags
/// is 1, 2 or 7 (`0x1404823c0`), the spells whose cooldowns the client scales by the
/// unit's cooldown rate, and no time at all otherwise. The rate itself is not applied.
fn cooldown_groups_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(List(cooldown.Group), PlanError) {
  let scaled =
    list.any(
      [
        row.spell4_tag_id00,
        row.spell4_tag_id01,
        row.spell4_tag_id02,
        row.spell4_tag_id03,
        row.spell4_tag_id04,
      ],
      fn(tag) { tag == 1 || tag == 2 || tag == 7 },
    )
  [row.spell_cool_down_id00, row.spell_cool_down_id01, row.spell_cool_down_id02]
  |> list.filter(fn(group) { group != 0 })
  |> list.try_map(fn(group) {
    use found <- result.map(
      spell_cool_down.get(tables:, id: SpellCoolDownId(group))
      |> result.replace_error(NoRow(table: "SpellCoolDown", id: group)),
    )
    cooldown.Group(id: group, time_ms: case found.cooldown_time, scaled {
      0, True -> row.spell_cool_down
      time_ms, _ -> time_ms
    })
  })
}

/// A modifier row's multiplier, flat amount or per-level amount: the 32-bit float its
/// column holds (`float32.of_column`), which must be finite.
fn modifier_number(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  column column: String,
  bits bits: Int,
) -> Result(Float, PlanError) {
  float32.of_column(number: bits)
  |> result.replace_error(ModifierNumberNotFinite(
    spell4_id:,
    effect_id: effect.id,
    column:,
  ))
}

/// The aim of a Fluff, SpellForceRemove, Scale, ItemVisualSwap or RavelSignal effect: the
/// units its flags name (`aim_of`); any other flag value fails the load, and so does one
/// with the caster's bit and the area's in a spell that hits no foes (`FriendlyAreaNotRead`).
fn lasting_aim_of(
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Aim, PlanError) {
  use aim <- result.try(
    aim_of(target_flags: effect.target_flags)
    |> result.replace_error(LastingAimNotRead(
      spell4_id:,
      effect_id: effect.id,
      target_flags: effect.target_flags,
    )),
  )
  friendly_area_read(place:, spell4_id:, effect:, aim:)
}

/// The aim itself, or `FriendlyAreaNotRead` for an aim that holds the caster's bit and the
/// area's in a spell that hits no foes ([F] `spell_hits_foes`).
fn friendly_area_read(
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  aim aim: Aim,
) -> Result(Aim, PlanError) {
  use <- bool.guard(
    when: !names_caster_and_area(aim:) || place.hits_foes,
    return: Ok(aim),
  )
  Error(FriendlyAreaNotRead(
    spell4_id:,
    effect_id: effect.id,
    target_flags: effect.target_flags,
  ))
}

/// The selector of a type 80 row, whose dataBits01 must name a spell group (one that
/// some Spell4GroupList row holds), a Spell4 or a Spell4Base the tables have.
fn selector_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(lasting.Selector, PlanError) {
  let named = effect.data_bits01
  case effect.data_bits00 {
    1 ->
      case set.contains(sources.known_groups, named) {
        True -> Ok(lasting.Group(spell_group_id: named))
        False -> Error(NoRow(table: "Spell4GroupList", id: named))
      }
    2 ->
      spell4.get(tables:, id: Spell4Id(named))
      |> result.replace(lasting.Spell(spell4_id: Spell4Id(named)))
      |> result.replace_error(NoRow(table: "Spell4", id: named))
    3 ->
      spell4_base.get(tables:, id: Spell4BaseId(named))
      |> result.replace(lasting.Base(spell4_base_id: Spell4BaseId(named)))
      |> result.replace_error(NoRow(table: "Spell4Base", id: named))
    selector ->
      Error(ForceRemoveSelectorNotRead(
        spell4_id:,
        effect_id: effect.id,
        selector:,
      ))
  }
}

/// The spell groups of a spell: the group ids of its Spell4GroupList row, none for
/// the id 0; a row the tables lack fails the load.
fn groups_of(
  sources sources: Sources,
  row row: spell4.Spell4,
) -> Result(List(Int), PlanError) {
  case row.spell4_group_list_id {
    0 -> Ok([])
    list_id ->
      dict.get(sources.group_lists, list_id)
      |> result.replace_error(NoRow(table: "Spell4GroupList", id: list_id))
  }
}

/// The spell's stack group and its cap (Spell4StackGroup.stackCap): no group, cap 0
/// for the id 0; a row the tables lack fails the load.
fn stack_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(lasting.Stack, PlanError) {
  case row.spell4_stack_group_id {
    0 -> Ok(lasting.Stack(group_id: 0, cap: 0))
    group_id ->
      spell4_stack_group.get(tables:, id: Spell4StackGroupId(group_id))
      |> result.map(fn(group) { lasting.Stack(group_id:, cap: group.stack_cap) })
      |> result.replace_error(NoRow(table: "Spell4StackGroup", id: group_id))
  }
}

/// The tag an effect row holds on the points a cast spent: its emmComparison and
/// emmValue (`Spell4Effects.emmComparison`).
pub fn tag_of(effect effect: spell4_effects.Spell4Effects) -> spend.Tag {
  spend.tag_of(comparison: effect.emm_comparison, value: effect.emm_value)
}

/// The resource slot of a gain's vital: 6 (Resource1) is slot 1 and 8 (Resource3)
/// slot 3, the innate cost types' numbering (`Spell4Effects.effectType.1`); the
/// kit holds no other.
fn gain_slot_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Int, PlanError) {
  case effect.data_bits00 {
    6 | 8 -> Ok(effect.data_bits00 - 5)
    vital -> Error(GainVitalNotRead(spell4_id:, effect_id: effect.id, vital:))
  }
}

/// The payloads of the spell's effects of one kind that apply in phase `phase`, those whose
/// tag holds for the points the cast spent, in the order of its list
/// (`spell_effect.in_phase`): `as_kind` is the kind's projection, such as `as_heal`.
pub fn in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
  as_kind as_kind: fn(Kind) -> Result(payload, Nil),
) -> List(payload) {
  spell_effect.in_phase(effects: spell.effects, phase:, spent:)
  |> list.filter_map(fn(planned) { as_kind(planned.kind) })
}

/// Every payload of the spell's effects of one kind (`as_kind` is its projection, such as
/// `as_proxy`), whatever their phases, in the order of its list.
pub fn payloads(
  spell spell: Spell,
  as_kind as_kind: fn(Kind) -> Result(payload, Nil),
) -> List(payload) {
  list.filter_map(spell.effects, fn(planned) { as_kind(planned.kind) })
}

/// The spell with its Proxies replaced by these, which stay first in its list as their kind
/// ranks.
pub fn with_proxies(spell spell: Spell, proxies proxies: List(Proxy)) -> Spell {
  let others =
    list.filter(spell.effects, fn(planned) {
      result.is_error(as_proxy(kind: planned.kind))
    })
  Spell(
    ..spell,
    effects: ranked(effects: list.append(
      list.map(proxies, fn(proxy) { effect_of(kind: ProxyEffect(proxy:)) }),
      others,
    )),
  )
}

/// Whether the client shows a cast bar for the spell, by its method
/// (`cast.current_cast`, `SpellShowsCastBar`).
fn cast_bar_of(
  method method: CastMethod,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
) -> CastBar {
  let has_bar = case cast_bar_kind.kind_of(number: base.cast_bar_type) {
    cast_bar_kind.NoBar -> False
    cast_bar_kind.Bar(..) -> True
  }
  let has_time = row.cast_time != 0
  case method {
    Normal | OtherMethod(10) -> bar_if(shows: has_bar && has_time)
    Multiphase -> bar_if(shows: has_bar || has_time)
    Channeled ->
      case has_bar {
        True -> ShowsCastBar
        False -> ShowsWhenPressed
      }
    PressHold -> ShowsCastBar
    ChanneledField | Transactional -> HidesCastBar
    ChargeRelease -> bar_if(shows: row.threshold_time != 0 || has_time)
    ClientSideInteraction | RapidTap | OtherMethod(..) ->
      bar_if(shows: has_time)
  }
}

fn bar_if(shows shows: Bool) -> CastBar {
  use <- bool.guard(when: shows, return: ShowsCastBar)
  HidesCastBar
}

/// Whether the client shows a cast bar for a cast of the spell, which makes it
/// the caster's current cast from its start (`cast.current_cast`): `pressed` is
/// whether the cast's root is the spell itself.
pub fn shows_cast_bar(spell spell: Spell, pressed pressed: Bool) -> Bool {
  case spell.cast_bar {
    ShowsCastBar -> True
    HidesCastBar -> False
    ShowsWhenPressed -> pressed
  }
}

/// Where the spell's own cooldown starts (`0x14053e5a0`): a Multiphase spell with a
/// phase of the flag 0x200 at its last phase, a channel at its last pulse, a
/// RapidTap, ChargeRelease or PressHold spell at no go.
fn cooldown_start_of(
  method method: CastMethod,
  phases phases: List(Phase),
) -> CooldownStart {
  case method {
    Multiphase ->
      case
        list.any(phases, fn(phase) {
          spell_effect.has_flag(
            flags: phase.flags,
            bit: cooldown_at_last_phase_flag,
          )
        })
      {
        True -> AtLastGo
        False -> AtFirstGo
      }
    Channeled -> AtLastGo
    RapidTap | ChargeRelease | PressHold -> NotAtAGo
    Normal
    | ChanneledField
    | ClientSideInteraction
    | Transactional
    | OtherMethod(..) -> AtFirstGo
  }
}

/// The first phase of a Multiphase spell that moves its cooldown to the end
/// (`0x14053e5a0`).
fn cooldown_phase_of(
  method method: CastMethod,
  phases phases: List(Phase),
) -> Option(Int) {
  case method {
    Multiphase ->
      list.index_map(phases, fn(phase, index) { #(index, phase) })
      |> list.find(fn(pair) {
        spell_effect.has_flag(
          flags: { pair.1 }.flags,
          bit: cooldown_at_last_phase_flag,
        )
      })
      |> result.map(fn(pair) { pair.0 })
      |> option.from_result
    Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Transactional
    | OtherMethod(..) -> None
  }
}

/// The phase delays of a spell: a Multiphase spell's SpellPhase rows the client
/// keeps, which it must have, and none for any other method.
fn phase_delays(
  phases phases: List(Phase),
  method method: CastMethod,
  spell4_id spell4_id: Int,
) -> Result(List(Int), PlanError) {
  case method {
    Multiphase ->
      case phases {
        [_, ..] -> Ok(list.map(phases, fn(phase) { phase.delay_ms }))
        [] -> Error(NoRow(table: "SpellPhase", id: spell4_id))
      }
    Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Transactional
    | OtherMethod(..) -> Ok([])
  }
}

/// The channel of a Channeled spell: its pulse time must give a count of pulses.
fn channel_of(
  row row: spell4.Spell4,
  method method: CastMethod,
) -> Result(Option(Channel), PlanError) {
  case method {
    Channeled ->
      case row.channel_pulse_time > 0 {
        True ->
          Ok(
            Some(Channel(
              initial_delay_ms: row.channel_initial_delay,
              max_time_ms: row.channel_max_time,
              pulse_time_ms: row.channel_pulse_time,
            )),
          )
        False -> Error(ChannelWithoutPulse(spell4_id: row.id))
      }
    Normal
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Multiphase
    | Transactional
    | OtherMethod(..) -> Ok(None)
  }
}

fn method_of(cast_method: Int) -> CastMethod {
  case cast_method {
    0 -> Normal
    1 -> Channeled
    2 -> PressHold
    3 -> ChanneledField
    5 -> ClientSideInteraction
    6 -> RapidTap
    7 -> ChargeRelease
    8 -> Multiphase
    9 -> Transactional
    other -> OtherMethod(id: other)
  }
}

fn weapon_of(weapon_slot: Int) -> WeaponSlot {
  case weapon_slot {
    0 -> NoWeaponNeeded
    1 -> PrimaryWeapon
    2 -> Refused
    other -> OtherWeaponSlot(id: other)
  }
}

/// The units a Proxy starts its child on (`Spell4Effects.targetFlags`): each struck unit
/// for an aim at the area (`aim_of`: 4 or 6), the caster for one at the caster or the
/// primary target (1, 2, 3), and both for one that holds the caster's bit and the area's
/// (5, 7), which a spell that hits no foes refuses (`FriendlyAreaNotRead`). Another value is
/// refused.
fn target_of(
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(List(ProxyTarget), PlanError) {
  use aim <- result.try(
    aim_of(target_flags: effect.target_flags)
    |> result.replace_error(ProxyAimNotRead(
      spell4_id:,
      effect_id: effect.id,
      target_flags: effect.target_flags,
    )),
  )
  use aim <- result.map(friendly_area_read(place:, spell4_id:, effect:, aim:))
  [
    #(OnCaster, reaches_caster(aim:)),
    #(OnCaster, !reaches_area(aim:) && !reaches_caster(aim:)),
    #(OnEachStruck, reaches_area(aim:)),
  ]
  |> list.filter(fn(target) { target.1 })
  |> list.map(fn(target) { target.0 })
  |> list.unique
}

/// Which units a row lands on, for what its target apply prerequisite may read.
type Reach {
  /// Only the caster, whose whole unit the prerequisite reads.
  OnlyTheCaster
  /// Only creatures the go struck: each one checks a prerequisite that reads its own state
  /// against itself and tells the cast rule whether it passed (`StruckGate`,
  /// `prerequisite.checked_by_creature`).
  StruckUnits
  /// The caster and creatures the go struck under one prerequisite, or a unit no strike
  /// names (the primary target of a press, which is the caster), or a row of a kind that
  /// reads its aim from its flags: the cast rule cannot check a prerequisite that reads a
  /// creature's state for these.
  PastTheCaster
}

/// The reach of a row of this aim.
fn reach_of_aim(aim aim: Aim) -> Reach {
  use <- bool.guard(when: !reaches_past_caster(aim:), return: OnlyTheCaster)
  case reaches_caster(aim:) {
    True -> PastTheCaster
    False -> StruckUnits
  }
}

/// The reach of a row of this aim in this place: a press has the caster itself as its
/// primary target, whom no strike names, so a row of a kind the go applies that aims at the
/// primary target there has no creature to check its gate
/// (`StruckUnits` becomes `PastTheCaster`). A spell a Proxy starts on a struck unit has
/// that creature as its primary target.
fn reach_in_place(place place: RowPlace, aim aim: Aim) -> Reach {
  case reach_of_aim(aim:) {
    StruckUnits ->
      case place.struck_by, reaches_primary_target(aim:) {
        None, True -> PastTheCaster
        None, False | Some(..), _ -> StruckUnits
      }
    OnlyTheCaster -> OnlyTheCaster
    PastTheCaster -> PastTheCaster
  }
}

/// The reach of a row of a kind the plan reads for the caster when its targetFlags
/// include it (bit 1) and for the primary target or the struck units otherwise
/// (`effect_kind.is_row_read`).
fn reach_of_flags(target_flags target_flags: Int) -> Reach {
  use <- bool.guard(
    when: spell_effect.has_flag(flags: target_flags, bit: 1),
    return: OnlyTheCaster,
  )
  PastTheCaster
}

/// An effect's condition: its caster apply prerequisite and, for a Proxy
/// (`names_a_gate`), the one its dataBits06 names (`Spell4Effects.effectType.26.dataBits06`:
/// a reading of the rows, since the client applies no Proxy itself), checked against the
/// caster, and its target apply prerequisite, which the cast rule checks for each unit the
/// row lands on, the unit first and the caster second
/// (`Spell4Effects.prerequisiteIdTargetApply`), except a target prerequisite of a row that
/// reaches only struck units and reads only each creature's own state, which the creature
/// checks (`StruckUnits`, `struck_gates_of`). The dataBits06 of a Fluff or SpellForceRemove
/// effect is no prerequisite. A prerequisite the table lacks fails the load, and so does a
/// target prerequisite the cast rule cannot read for the units the row reaches
/// (`target_gate_read`).
fn condition_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
  reach reach: Reach,
  data_bits06_names_a_gate names_a_gate: Bool,
) -> Result(Condition, PlanError) {
  use caster <- result.try(caster_gates_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: names_a_gate,
  ))
  case effect.prerequisite_id_target_apply, caster {
    0, [] -> Ok(Always)
    0, [_, ..] -> Ok(GatedOnCaster(gates: caster))
    target, _ -> {
      use target <- result.try(prerequisite_of(tables:, id: target))
      target_condition_of(effect:, reach:, caster:, target:)
    }
  }
}

/// The condition of a row behind a target apply prerequisite: the creatures a row that
/// reaches only struck units checks it itself when it reads only their own state, so the
/// condition holds the caster gates alone, and else the cast rule checks it, where it can
/// read it (`target_gate_read`).
fn target_condition_of(
  effect effect: spell4_effects.Spell4Effects,
  reach reach: Reach,
  caster caster: List(Prerequisite),
  target target: Prerequisite,
) -> Result(Condition, PlanError) {
  case reach, prerequisite.checked_by_creature(prerequisite: target) {
    StruckUnits, True ->
      Ok(case caster {
        [] -> Always
        [_, ..] -> GatedOnCaster(gates: caster)
      })
    StruckUnits, False | OnlyTheCaster, _ | PastTheCaster, _ -> {
      use Nil <- result.map(target_gate_read(target:, effect:, reach:))
      case caster {
        [] -> GatedOnTarget(prerequisite: target)
        [_, ..] -> GatedOnCasterAndTarget(caster:, target:)
      }
    }
  }
}

/// The condition of a row a go applies to the units it reaches (a lasting, remove, modifier
/// or heal row): `condition_of`, and a caster apply prerequisite with a condition of a type
/// the server has not decoded fails the load too, since a go that cannot tell whether the
/// caster passes applies nothing (`prerequisite.unread_types`).
fn applied_condition_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
  reach reach: Reach,
) -> Result(Condition, PlanError) {
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    reach:,
    data_bits06_names_a_gate: False,
  ))
  let caster = case condition {
    Always | GatedOnTarget(..) -> []
    GatedOnCaster(gates:) | GatedOnCasterAndTarget(caster: gates, ..) -> gates
  }
  case list.flat_map(caster, prerequisite.unread_types) {
    [prerequisite_type, ..] ->
      Error(ApplyPrerequisiteNotRead(
        spell4_id: effect.spell_id,
        effect_id: effect.id,
        prerequisite_type:,
      ))
    [] -> Ok(condition)
  }
}

/// The condition of a damage or CCStateSet row of this aim, which a go's strike checks for
/// each unit the row reaches (`applied_condition_of`): a row whose gate the server cannot
/// read fails the load (`ApplyPrerequisiteNotRead`, `TargetPrerequisiteReadsStruckUnit`).
pub fn row_condition_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
  aim aim: Aim,
) -> Result(Condition, PlanError) {
  applied_condition_of(tables:, effect:, reach: reach_of_aim(aim:))
}

/// Whether the cast rule can check a target apply prerequisite for the units a row
/// reaches: a condition type the server has not decoded is refused, and so is one that
/// reads what the casts held on the creature it strikes hold or the state it holds itself,
/// for a row that lands past the caster and that the creature does not check: the caster's
/// check knows the unit by its place alone (`prerequisite.unread_types`,
/// `prerequisite.struck_unread_types`, `prerequisite.unread_on_a_struck_unit`).
fn target_gate_read(
  target target: Prerequisite,
  effect effect: spell4_effects.Spell4Effects,
  reach reach: Reach,
) -> Result(Nil, PlanError) {
  case prerequisite.unread_types(prerequisite: target), reach {
    [prerequisite_type, ..], _ ->
      Error(ApplyPrerequisiteNotRead(
        spell4_id: effect.spell_id,
        effect_id: effect.id,
        prerequisite_type:,
      ))
    [], OnlyTheCaster -> Ok(Nil)
    [], StruckUnits | [], PastTheCaster -> {
      let #(casts, own_state) =
        list.partition(
          prerequisite.unread_on_a_struck_unit(prerequisite: target),
          list.contains(prerequisite.casts_held_types, _),
        )
      case list.append(casts, own_state) {
        [prerequisite_type, ..] ->
          Error(TargetPrerequisiteReadsStruckUnit(
            spell4_id: effect.spell_id,
            effect_id: effect.id,
            prerequisite_type:,
          ))
        [] -> Ok(Nil)
      }
    }
  }
}

/// A Proxy's condition: its caster gates as `condition_of` reads them and, behind a target
/// apply prerequisite, that prerequisite decoded too, which the cast rule checks against
/// each unit the child is made on (`GatedOnCasterAndTarget`).
fn proxy_condition_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Condition, PlanError) {
  case effect.prerequisite_id_target_apply {
    0 ->
      condition_of(
        tables:,
        effect:,
        reach: OnlyTheCaster,
        data_bits06_names_a_gate: True,
      )
    target -> {
      use caster <- result.try(caster_gates_of(
        tables:,
        effect:,
        data_bits06_names_a_gate: True,
      ))
      use target <- result.try(prerequisite_of(tables:, id: target))
      Ok(GatedOnCasterAndTarget(caster:, target:))
    }
  }
}

/// The prerequisites a row is gated on against the caster: its caster apply prerequisite
/// and, for a Proxy, the one its dataBits06 names, in that order.
fn caster_gates_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
  data_bits06_names_a_gate names_a_gate: Bool,
) -> Result(List(Prerequisite), PlanError) {
  [
    effect.prerequisite_id_caster_apply,
    ..case names_a_gate {
      True -> [effect.data_bits06]
      False -> []
    }
  ]
  |> list.filter(fn(id) { id != 0 })
  |> list.try_map(fn(id) { prerequisite_of(tables:, id:) })
}

/// The Prerequisite row with this id as the client keeps it.
fn prerequisite_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Prerequisite, PlanError) {
  prerequisite_in(
    rows: prerequisite.table_rows(tables:),
    arcs: prerequisite.table_arcs(tables:),
    quests: prerequisite.table_quests(tables:),
    id:,
  )
}

/// The Prerequisite with this id, nested rows loaded, from the rows given: a row
/// the rows lack and a cycle fail the load.
fn prerequisite_in(
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
  id id: Int,
) -> Result(Prerequisite, PlanError) {
  prerequisite.load(id: PrerequisiteId(id), rows:, arcs:, quests:)
  |> result.map_error(fn(error) {
    case error {
      prerequisite.NoPrerequisiteRow(id: missing) ->
        NoRow(table: "Prerequisite", id: missing.value)
      prerequisite.PrerequisiteCycle(path:) ->
        PrerequisiteCycle(
          path: list.map(path, fn(on_the_way) { on_the_way.value }),
        )
      prerequisite.NoPositionalRequirementRow(id: missing) ->
        NoRow(table: "PositionalRequirement", id: missing)
      prerequisite.NoQuestObjectiveRow(objective_id: missing) ->
        NoRow(table: "QuestObjective", id: missing)
    }
  })
}

/// What a Spell4 row's prerequisite column holds: none for 0, else the row it names,
/// which the rows must hold.
pub fn column_of(
  id id: Int,
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
) -> Result(Option(Prerequisite), PlanError) {
  case id {
    0 -> Ok(None)
    _ -> prerequisite_in(rows:, arcs:, quests:, id:) |> result.map(Some)
  }
}

/// What a spell's prerequisiteIdCasterCast is to a press (`0x1403ace00`): a waiver
/// when propertyFlags has bit 2 and its caster requirement block is set
/// (casterInnateRequirement0, casterInnateRequirement1 or targetBeginInnateRequirement
/// is not 0, the block the client tests), else a gate.
pub fn caster_cast_of(
  prerequisite_id prerequisite_id: Int,
  property_flags property_flags: Int,
  requirement_block block: #(Int, Int, Int),
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
) -> Result(CasterCast, PlanError) {
  use column <- result.map(column_of(id: prerequisite_id, rows:, arcs:, quests:))
  let has_block = block.0 != 0 || block.1 != 0 || block.2 != 0
  case column {
    None -> NoCasterCast
    Some(prerequisite) ->
      case spell_effect.has_flag(flags: property_flags, bit: 0x4) && has_block {
        True -> RequirementWaiver(prerequisite:)
        False -> CastGate(prerequisite:)
      }
  }
}

fn global_cooldown_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(GlobalCooldown, PlanError) {
  let kind = row.global_cooldown_enum
  let refused_while_running = kind == 0 || kind == 2
  case { kind == 0 || kind == 1 } && row.spell_cool_down_id_global != 0 {
    False -> Ok(GlobalCooldown(refused_while_running:, starts_for_ms: None))
    True -> {
      use cool_down <- result.try(
        spell_cool_down.get(
          tables:,
          id: SpellCoolDownId(row.spell_cool_down_id_global),
        )
        |> result.replace_error(NoRow(
          table: "SpellCoolDown",
          id: row.spell_cool_down_id_global,
        )),
      )
      Ok(GlobalCooldown(
        refused_while_running:,
        starts_for_ms: Some(cool_down.cooldown_time),
      ))
    }
  }
}

/// The mask bits of a target condition row that the activate cast accounts for, in the
/// order CheckCastUnitTargetRange tests them (`0x1403b2240`), each by what the server
/// checks for it:
/// - bit 0 (106, 107): the target's death, read as `target_death`;
/// - bit 1 (108): the target is not in combat, which is the `InCombat` withheld check of
///   the activate target (the client sends no cast at a creature in combat);
/// - bits 6 and 7 (118, 120): pass, because no unit the server shows is seated on another;
/// - bit 5 (116): passes, pending the decoder question of what the client's unit word
///   0xc4 holds (#334).
/// A mask bit outside these is a condition the server does not judge.
pub const target_mask_read = 227

/// The bit 0 of a condition row of a spell: CheckCastCaster tests it against the caster
/// and CheckCastUnitTargetRange against the target before a cast is sent
/// (`Spell4.spell4ConditionsIdCaster`, `Spell4.spell4ConditionsIdTarget`).
/// A row the Spell4 row names and the table lacks is a `NoRow`.
fn caster_death_of(
  conditions conditions: Option(spell4_conditions.Spell4Conditions),
) -> CasterDeath {
  case conditions {
    None -> AliveOrDead
    Some(condition) ->
      case
        spell_effect.has_flag(flags: condition.condition_mask, bit: 1),
        spell_effect.has_flag(flags: condition.condition_value, bit: 1)
      {
        False, _ -> AliveOrDead
        True, False -> CannotBeDead
        True, True -> MustBeDead
      }
  }
}

/// The Spell4Conditions row an id names, none for the id 0; a row the table lacks fails
/// the load.
fn conditions_row_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Option(spell4_conditions.Spell4Conditions), PlanError) {
  case id {
    0 -> Ok(None)
    id ->
      spell4_conditions.get(tables:, id: Spell4ConditionsId(id))
      |> result.map(Some)
      |> result.replace_error(NoRow(table: "Spell4Conditions", id:))
  }
}

/// The ccStateMask of the Spell4CCConditions row an id names, 0 for the id 0; a row the
/// table lacks fails the load.
fn cc_mask_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Int, PlanError) {
  crowd_control.mask_of(tables:, id:)
  |> result.replace_error(NoRow(table: "Spell4CCConditions", id:))
}

/// The spell's costs in the order the client checks them: the two of the
/// Spell4Thresholds row for a stage first, which hold no EMM id (the threshold step,
/// `0x1403bfd60` calls `0x1403c0620` at `0x1403c012e` and returns on a refusal), then
/// the Spell4 row's two innate costs as (vital type, amount, EMM id) (the cast check,
/// `0x1403ae8c0`, called after the threshold step); a type of 0 or above 30, or an amount of 0, is none
/// (`0x1403b3320`), unless the cost has an EMM id (`spent_by`).
fn costs_of(
  row row: spell4.Spell4,
  innate innate: List(#(Int, Int, Int)),
  threshold threshold: List(#(Int, Int)),
) -> Result(List(Cost), PlanError) {
  use innate <- result.try(
    list.try_map(innate, fn(cost) {
      use fixed <- result.map(cost_of(
        row:,
        cost_type: cost.0,
        amount: cost.1,
        on_row: False,
      ))
      spent_by(cost: fixed, emm_id: cost.2)
    }),
  )
  use threshold <- result.map(
    list.try_map(threshold, fn(cost) {
      use fixed <- result.map(cost_of(
        row:,
        cost_type: cost.0,
        amount: cost.1,
        on_row: True,
      ))
      spent_by(cost: fixed, emm_id: 0)
    }),
  )
  option.values(list.append(threshold, innate))
}

/// The cost as its Spell4 EMM id spends it (genesis_prime/game/spend): a slot cost
/// with an id read as a spend of every point held becomes a `SpendAllCost`; any other
/// slot or unheld cost with an id, or no cost with one, is an `UnreadSpendCost` with
/// the result the cost gives, or 285 when there is none (`Spell4.innateCostEMMId0`:
/// three rows hold an id with no cost, and a cost has no result of its own to give).
/// A class cost keeps its check whatever its id: the client's class check
/// (`0x1405e7980`) reads no EMM id.
fn spent_by(cost cost: Option(Cost), emm_id emm_id: Int) -> Option(Cost) {
  case cost, spend.spend_of(emm_id:) {
    Some(ClassVitalCost(..)), _ | Some(RowClassCost(..)), _ -> cost
    cost, None -> cost
    Some(SlotCost(slot:, amount:, result:)), Some(spend.AllHeld) ->
      Some(SpendAllCost(slot:, amount:, result:))
    other, Some(spend.AllHeld) -> Some(unread_spend(cost: other, emm_id:))
    other, Some(spend.Unread(emm_id:)) ->
      Some(unread_spend(cost: other, emm_id:))
  }
}

fn unread_spend(cost cost: Option(Cost), emm_id emm_id: Int) -> Cost {
  let result = case cost {
    Some(SlotCost(result:, ..))
    | Some(SpendAllCost(result:, ..))
    | Some(UnheldCost(result:))
    | Some(UnreadSpendCost(result:, ..)) -> result
    Some(ClassVitalCost(..)) | Some(RowClassCost(..)) ->
      panic as "a class cost is never read as a spend"
    None -> 285
  }
  UnreadSpendCost(result:, emm_id:)
}

/// The EMM id beside each of the Spell4 row's two innate costs, 0 for a cost that holds
/// none: an id with no cost is no spend (`has_cost`), which `cost_of` refuses the press
/// of, so the measure does not count it as a use.
pub fn spent_emm_ids(row row: spell4.Spell4) -> List(Int) {
  [
    #(row.innate_cost_type0, row.innate_cost0, row.innate_cost_emm_id0),
    #(row.innate_cost_type1, row.innate_cost1, row.innate_cost_emm_id1),
  ]
  |> list.map(fn(cost) {
    case has_cost(cost_type: cost.0, amount: cost.1) {
      True -> cost.2
      False -> 0
    }
  })
}

/// Whether a Spell4 cost column pair holds a cost: a type of 0 or above 30, or an
/// amount of 0, is none (`0x1403b3320`).
fn has_cost(cost_type cost_type: Int, amount amount: Int) -> Bool {
  cost_type != 0 && amount != 0 && cost_type <= 30
}

/// One cost column pair as a cost. The client sends a type to its own check when it has
/// a case for it (`0x1403b3320`) and every other type to the class mechanic's
/// (`0x1405e7980`): those are the class vitals 4, 12, 13, 14, 18 and 19, which a
/// threshold row's cost (`on_row`, `0x1403c0620`) reads through the class's slots too
/// (`UnitVitalValue` `0x140466520`, `ClassVitalSlot` `0x1405e78c0`).
fn cost_of(
  row row: spell4.Spell4,
  cost_type cost_type: Int,
  amount amount: Int,
  on_row on_row: Bool,
) -> Result(Option(Cost), PlanError) {
  use <- bool.guard(when: !has_cost(cost_type:, amount:), return: Ok(None))
  case cost_type, slot_of(vital_type: cost_type) {
    1, _ -> Ok(Some(UnheldCost(result: 44)))
    3, _ -> Ok(Some(UnheldCost(result: 176)))
    15, _ -> Ok(Some(UnheldCost(result: 167)))
    16, _ -> Ok(Some(UnheldCost(result: 177)))
    _, Ok(#(slot, result)) -> Ok(Some(SlotCost(slot:, amount:, result:)))
    4, _ | 12, _ | 13, _ | 14, _ | 18, _ | 19, _ ->
      Ok(
        Some(case on_row {
          True -> RowClassCost(vital: cost_type, amount:)
          False -> ClassVitalCost(vital: cost_type, amount:)
        }),
      )
    _, Error(Nil) -> Error(UnreadCost(spell4_id: row.id, cost_type:))
  }
}

/// The resource slot a cost or requirement type reads and the result its failure
/// gives: 5 to 11 are slots 0 to 6 (50 to 56) (`0x1403b3320`, `0x1403b1780`). The
/// client's types 16 and 27 to 29 read slots 7 to 10, which no class resource of
/// the server uses.
fn slot_of(vital_type vital_type: Int) -> Result(#(Int, Int), Nil) {
  case vital_type {
    _ if vital_type >= 5 && vital_type <= 11 ->
      Ok(#(vital_type - 5, 50 + vital_type - 5))
    _ -> Error(Nil)
  }
}

/// The spell's caster vital requirements, as (type, eval, value): type 0 is none
/// (`0x1403b1780`).
fn requirements_of(
  spell4_id spell4_id: Int,
  requirements requirements: List(#(Int, Int, Int)),
) -> Result(List(Requirement), PlanError) {
  list.try_map(requirements, fn(requirement) {
    let #(requirement_type, eval, value) = requirement
    case requirement_type, slot_of(vital_type: requirement_type) {
      0, _ -> Ok(None)
      _, Ok(#(slot, result)) ->
        Ok(
          Some(Requirement(
            slot:,
            measure: case eval > 4 {
              True -> PercentOfMax
              False -> Amount
            },
            comparison: comparison_of(eval:),
            value:,
            result:,
          )),
        )
      _, Error(Nil) -> Error(UnreadRequirement(spell4_id:, requirement_type:))
    }
  })
  |> result.map(option.values)
}

/// How an eval code compares (`0x1407a1750`).
fn comparison_of(eval eval: Int) -> Comparison {
  case eval {
    0 | 5 -> Equal
    1 | 6 -> Greater
    2 | 7 -> AtLeast
    3 | 8 -> Less
    4 | 9 -> AtMost
    other -> NeverPasses(eval: other)
  }
}

/// The plans of the level-1 abilities and the innates the tables' load built, which the
/// coverage measure and the rules of the starting abilities read by `in_plans`.
pub fn plans(tables tables: table_store.Tables) -> Plans {
  table_store.derived(tables:, key: plans_key).starting
}

/// The plans of the level-1 abilities and the innates and of each later ability the server
/// can plan (`unplanned` lists the others): the ones the cast of any ability a character
/// holds reads by `in_plans`.
pub fn plans_with_later(tables tables: table_store.Tables) -> Plans {
  table_store.derived(tables:, key: plans_key).with_later
}

/// The ability book as the client holds it: the bag, then the alternate each bag
/// ability names, in bag order.
pub fn book(
  plans plans: Plans,
  bag bag: List(Spell4BaseId),
) -> List(Spell4BaseId) {
  let alternates =
    list.filter_map(bag, fn(base) {
      use spell <- result.try(in_plans(plans:, base:))
      case spell.alternate {
        Some(alternate) -> Ok(alternate.spell4_base_id)
        None -> Error(Nil)
      }
    })
  list.append(bag, alternates)
}

/// The tree of the ability held as this Spell4BaseId among the plans, or
/// `Error(Nil)` for a base no class's level-1 ability has.
pub fn in_plans(
  plans plans: Plans,
  base spell4_base_id: Spell4BaseId,
) -> Result(Spell, Nil) {
  dict.get(plans, spell4_base_id.value)
}

/// The time of each go after the start of a cast of the spell, in milliseconds: a
/// channel's pulses, the running sum of a Multiphase spell's phase delays, none
/// for a ChargeRelease ability with stages, whose cast is held until its release
/// (`cast.charge_release_base`), and else the cast time, the one go.
pub fn go_times_ms(spell spell: Spell) -> List(Int) {
  case spell.channel, spell.phase_delays_ms {
    Some(channel), _ -> channel_go_times_ms(channel:)
    None, [] ->
      case opens_threshold(spell:) && spell.method == ChargeRelease {
        True -> []
        False -> [spell.cast_time_ms]
      }
    None, delays -> list.scan(delays, 0, fn(elapsed, delay) { elapsed + delay })
  }
}

/// How many gos a cast of the spell has: a channel's pulses, a Multiphase spell's
/// phases, none for a ChargeRelease ability held until its release, else one
/// (`go_times_ms`).
pub fn go_count(spell spell: Spell) -> Int {
  list.length(go_times_ms(spell:))
}

/// The times of a channel's pulses: (channelMaxTime - channelInitialDelay +
/// channelPulseTime) / channelPulseTime of them, in whole numbers
/// (`0x14053d1f0`), at the initial delay plus each pulse time (the times are the
/// server's choice).
pub fn channel_go_times_ms(channel channel: Channel) -> List(Int) {
  let count =
    { channel.max_time_ms - channel.initial_delay_ms + channel.pulse_time_ms }
    / channel.pulse_time_ms
  list.repeat(Nil, count)
  |> list.index_map(fn(_, pulse) {
    channel.initial_delay_ms + pulse * channel.pulse_time_ms
  })
}

/// The time of a channel's finish timer when that is after its last pulse. The cast
/// ends at the later of that time and the close of its last go's strike round, so
/// the client has all the gos before the 0x7fe (`cast.channel_sequence`). A channel
/// whose last pulse is at channelMaxTime, and every spell that is not Channeled,
/// ends with its last go.
pub fn finish_after_ms(spell spell: Spell) -> Option(Int) {
  case spell.channel {
    None -> None
    Some(channel) ->
      case list.last(channel_go_times_ms(channel:)) {
        Ok(last) if last >= channel.max_time_ms -> None
        Ok(_) | Error(Nil) -> Some(channel.max_time_ms)
      }
  }
}

/// How long a cast of the spell lasts, in milliseconds, which is what the client
/// counts the current cast's time left from (`cast.press_queue`): a channel's
/// channelMaxTime, else the cast time, else the sum of a Multiphase spell's phase
/// delays; none for a ChargeRelease ability that holds its cast until the release.
pub fn duration_ms(spell spell: Spell) -> Option(Int) {
  case spell.channel, spell.phase_delays_ms {
    Some(channel), _ -> Some(channel.max_time_ms)
    None, [] ->
      case go_times_ms(spell:) {
        [] -> None
        [_, ..] -> Some(spell.cast_time_ms)
      }
    None, delays ->
      case spell.cast_time_ms {
        0 -> Some(int.sum(delays))
        cast_time -> Some(cast_time)
      }
  }
}

/// Whether a press of the ability opens a threshold: a RapidTap or ChargeRelease
/// spell with stages.
pub fn opens_threshold(spell spell: Spell) -> Bool {
  case spell.method {
    RapidTap | ChargeRelease -> spell.stages != []
    Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | Multiphase
    | Transactional
    | OtherMethod(..) -> False
  }
}

/// The spell a press casts through the ability's open threshold at `index`: the
/// stage's at 0 or more, the ability's own at -1, and none past the last stage or
/// below -1, which the press is refused for (4) (`0x1403bfd60`).
pub fn stage_at(spell spell: Spell, index index: Int) -> Result(Spell, Nil) {
  use <- bool.guard(when: index == -1, return: Ok(spell))
  use <- bool.guard(when: index < 0, return: Error(Nil))
  list.drop(spell.stages, index)
  |> list.first
  |> result.map(fn(stage) { stage.spell })
}

/// The spell, the stage spells a RapidTap or ChargeRelease ability casts, the spell of
/// each Proxy that `started` accepts and the spell each Proc effect casts, below them,
/// each with its own tree the same way. A proc's spell may be cast whenever its holder
/// holds the proc, so every one is in the tree.
pub fn tree(
  spell spell: Spell,
  started started: fn(Proxy) -> Bool,
) -> List(Spell) {
  let stages = list.map(spell.stages, fn(stage) { stage.spell })
  let proxied =
    payloads(spell:, as_kind: as_proxy)
    |> list.filter(started)
    |> list.map(fn(proxy) { proxy.spell })
  let procced =
    payloads(spell:, as_kind: as_proc)
    |> list.map(fn(proc) { proc.spell })
  let pressed = list.map(spell.press_proxies, fn(proxy) { proxy.spell })
  [
    spell,
    ..list.flat_map(
      list.flatten([stages, proxied, procced, pressed]),
      fn(below) { tree(spell: below, started:) },
    )
  ]
}

/// The units an effect aimed by `aim` reaches (`Spell4Effects.targetFlags`): the caster,
/// the cast's primary target and the units of the area, each of those its bits name, in
/// that order and each once (a caster that is its own target, or in the area, is one
/// unit). One rule for the cast's lasting rows and the strike's crowd-control states.
pub fn units_aimed_at(
  aim aim: Aim,
  caster caster: Int,
  primary_target primary_target: Int,
  area area: List(Int),
) -> List(Int) {
  let caster_unit = case reaches_caster(aim:) {
    True -> [caster]
    False -> []
  }
  let target_unit = case reaches_primary_target(aim:) {
    True -> [primary_target]
    False -> []
  }
  let area_units = case reaches_area(aim:) {
    True -> area
    False -> []
  }
  list.unique(list.flatten([caster_unit, target_unit, area_units]))
}

/// The target apply prerequisites of the spell's rows aimed past the caster that apply in
/// phase `phase`, those whose tag holds for the points the cast spent: the gates the
/// strike tells the units its rows reach.
pub fn struck_gates_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(StruckGate) {
  list.filter(spell.struck_gates, fn(gate) {
    spell_effect.applies_in_phase(
      phase_flags: gate.phase_flags,
      tag: gate.tag,
      phase:,
      spent:,
    )
  })
}

/// The CCStateSet effects of the spell aimed at creatures that apply in phase `phase`,
/// those whose tag holds for the points the cast spent: a row whose aim names the primary
/// target or the area, a row that names the caster as well among them. The states on the
/// caster are `restrictions_in_phase`.
pub fn controls_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(CrowdControl) {
  in_phase(spell:, phase:, spent:, as_kind: as_control)
  |> list.filter(fn(control) { reaches_past_caster(aim: control.aim) })
}

/// The CCStateSet effects of the spell aimed at the caster that apply in phase `phase`,
/// those whose tag holds for the points the cast spent: a row whose aim names the caster,
/// a row that names other units as well among them.
pub fn restrictions_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(CrowdControl) {
  in_phase(spell:, phase:, spent:, as_kind: as_control)
  |> list.filter(fn(control) { reaches_caster(aim: control.aim) })
}

/// The spellGroupId00 to 31 columns of a Spell4GroupList row, in order.
fn group_ids_of(row row: spell4_group_list.Spell4GroupList) -> List(Int) {
  [
    row.spell_group_id00,
    row.spell_group_id01,
    row.spell_group_id02,
    row.spell_group_id03,
    row.spell_group_id04,
    row.spell_group_id05,
    row.spell_group_id06,
    row.spell_group_id07,
    row.spell_group_id08,
    row.spell_group_id09,
    row.spell_group_id10,
    row.spell_group_id11,
    row.spell_group_id12,
    row.spell_group_id13,
    row.spell_group_id14,
    row.spell_group_id15,
    row.spell_group_id16,
    row.spell_group_id17,
    row.spell_group_id18,
    row.spell_group_id19,
    row.spell_group_id20,
    row.spell_group_id21,
    row.spell_group_id22,
    row.spell_group_id23,
    row.spell_group_id24,
    row.spell_group_id25,
    row.spell_group_id26,
    row.spell_group_id27,
    row.spell_group_id28,
    row.spell_group_id29,
    row.spell_group_id30,
    row.spell_group_id31,
  ]
}
