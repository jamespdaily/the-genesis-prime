//// Which rolls a cast needs, and which of its effects pass their gates on the units it reaches.
////
//// - **A go's gains** (`Gain`) are the spell's own gains of the phase and, once
////   for the go and not once per unit, the gains of each Proxy of the phase aimed
////   at each struck unit when the round has a Hit and the Proxy's gate passes
////   (`spell_plan.Gain`). Each is given when its caster apply and target apply
////   prerequisites pass against the caster, the only unit a gain reaches
////   (genesis_prime/game/prerequisite): the spells of the caster's own live
////   casts whose primary target it is, whether it is in combat, its health, shield
////   and the class resource slot it holds as the vitals 1, 3 and 5 to 11, and the
////   rolls the connection drew. A prerequisite of a type or a vital not read, and a
////   ticking gain, give nothing and a debug line. A creature's cast on the player is not
////   held here, so a prerequisite cannot find one (no kit prerequisite tests a
////   creature's spell).
//// - **A go's gates read the caster as it stood before the go's own effects.** The
////   gates of its Proxies and of its gains see the live casts with this go counted,
////   but not the children the go starts and not the cast's removal at its finish: a
////   server choice, since the client applies no Proxy itself
////   (`Spell4Effects.effectType.26.dataBits06`). A gain that asks to be "not under"
////   a spell this same go starts is given (`cast_gate_test`).
//// - **A go's rolls** are one for each type 37 condition among the gates of the
////   Proxies that start a child, of the gains that may be given and of the lasting
////   effects of the phase, and, for a row behind a target apply prerequisite, one set for
////   each unit the row reaches (`rolls_needed`); the connection draws that many from its
////   seed before it calls `cast.went`, and none when there is no such condition, so no other
////   roll of the connection moves.

import genesis_prime/game/cast/state.{
  type Caster, type Effect, type GainVerdict, type GateDecision, type Live,
  type State, type Struck, type TargetVerdict, CannotTell, Deflected, Gain,
  GateFails, Given, Hit, HitCreature, Immune, Log, NotApplied, Starts, Withheld,
} as cast_state
import genesis_prime/game/class_resource
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/spell_area
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Proxy, type Spell}
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{type Spell4EffectsId}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// How many rolls the go of `phase` of the live cast `cast_id` may take once its
/// round closed with `struck`: one for each type 37 condition among the gates of
/// the Proxies that start a child and of the gains that may be given
/// (`prerequisite.rolls_needed`), and, for a row behind a target apply prerequisite, one
/// for each type 37 condition of that prerequisite for each unit the row's aim names
/// (`target_rolls_needed`). The connection draws that many from its seed and no others,
/// so a go with no type 37 condition moves no roll. A cast that is not live takes none.
/// `caster` is the casting unit, which a row aimed at it and past it reaches once.
pub fn rolls_needed(
  cast cast: State,
  caster caster: Int,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
) -> Int {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> 0
    Ok(live) ->
      spell_effect.in_phase(
        effects: live.spell.effects,
        phase:,
        spent: live.spent,
      )
      |> list.map(fn(planned) {
        effect_rolls_needed(
          kind: planned.kind,
          caster:,
          primary_target: live.primary_target,
          struck:,
        )
      })
      |> int.sum
  }
}

/// The rolls the go takes for one effect of its phase, by its kind: a Proxy that has a unit
/// to start a child on takes those of its gate and of the gains lifted onto it; a gain, those
/// of its caster-side gates; the other kinds those of `gates_checked_on_caster`, the gates
/// `control.lasting_applied` draws, and, for a row that reaches units, those of its target
/// apply prerequisite for each unit it reaches (`target_rolls_needed`).
fn effect_rolls_needed(
  kind kind: spell_plan.Kind,
  caster caster: Int,
  primary_target primary_target: Int,
  struck struck: List(Struck),
) -> Int {
  use <- bool.guard(when: !applied_by_go(kind:), return: 0)
  let reached = fn(aim) {
    units_reached(aim:, caster:, primary_target:, struck:)
  }
  let caster_rolls = case gates_checked_on_caster(kind:) {
    Ok(gates) -> gates_rolls_needed(gates)
    Error(Nil) -> 0
  }
  case kind {
    spell_plan.ProxyEffect(proxy:) ->
      case starts_a_child(proxy:, hit: hit_units(struck:) != []) {
        False -> 0
        True ->
          strike_rolls_needed(
            condition: proxy.condition,
            units: case proxy.target {
              spell_plan.OnCaster -> 1
              spell_plan.OnEachStruck -> list.length(hit_units(struck:))
            },
          )
          + int.sum(list.map(lifted_gains(proxy:), gain_rolls_needed))
      }
    spell_plan.GainEffect(gain:) -> gain_rolls_needed(gain)
    spell_plan.LastingEffect(lasting: row) ->
      caster_rolls
      + target_rolls_needed(
        condition: row.condition,
        units_reached: reached(row.aim),
      )
    spell_plan.RemoveEffect(remove: row) ->
      caster_rolls
      + target_rolls_needed(
        condition: row.condition,
        units_reached: reached(row.aim),
      )
    spell_plan.ModifierEffect(modifier: row) ->
      caster_rolls
      + target_rolls_needed(
        condition: row.condition,
        units_reached: reached(spell_plan.modifier_aim(modifier: row)),
      )
    spell_plan.StruckMoveEffect(struck_move: row) ->
      caster_rolls
      + target_rolls_needed(
        condition: row.condition,
        units_reached: reached(row.aim),
      )
    spell_plan.HealEffect(heal: row) ->
      caster_rolls
      + target_rolls_needed(
        condition: row.condition,
        units_reached: reached(row.aim),
      )
    spell_plan.ForcedMoveEffect(..)
    | spell_plan.CooldownEffect(..)
    | spell_plan.StealthEffect(..)
    | spell_plan.RemoveStealthEffect(..)
    | spell_plan.ProcEffect(..)
    | spell_plan.ControlEffect(..) -> caster_rolls
  }
}

/// The rolls the target apply prerequisite of a row takes: one for each type 37 condition
/// of its check, for each of the `units_reached` its aim names, since the gate is checked
/// once for each unit in the order of the units and each test draws a roll of its own
/// (`Prerequisite.prerequisiteTypeId.37`). The count may exceed what a go takes, for a
/// modifier row left out for a unit it does not apply to takes none; the go leaves the
/// rolls it did not take.
fn target_rolls_needed(
  condition condition: spell_plan.Condition,
  units_reached units_reached: Int,
) -> Int {
  case target_gate_of(condition:) {
    Some(target) ->
      units_reached * prerequisite.rolls_needed(prerequisite: target)
    None -> 0
  }
}

/// How many units a row aimed by `aim` reaches in a round that closed with `struck`
/// (`units_aimed_at`: a caster that is its own primary target, or struck, is one unit).
fn units_reached(
  aim aim: spell_plan.Aim,
  caster caster: Int,
  primary_target primary_target: Int,
  struck struck: List(Struck),
) -> Int {
  list.length(spell_plan.units_aimed_at(
    aim:,
    caster:,
    primary_target:,
    area: hit_units(struck:),
  ))
}

/// The rolls the check of these gates takes: one for each type 37 condition among them.
fn gates_rolls_needed(gates: List(prerequisite.Prerequisite)) -> Int {
  int.sum(
    list.map(gates, fn(gate) { prerequisite.rolls_needed(prerequisite: gate) }),
  )
}

/// The gains of a go, in the order `gains_given` checks them: the spell's own of
/// the phase, then those of each of these Proxies.
fn gains_of(
  spell spell: Spell,
  phase phase: Int,
  proxies proxies: List(Proxy),
  spent spent: Option(Int),
) -> List(spell_plan.Gain) {
  list.append(
    spell_plan.gains_in_phase(spell:, phase:, spent:),
    list.flat_map(proxies, lifted_gains),
  )
}

/// The rolls the check of a gain's prerequisites takes; a ticking gain is not
/// checked.
fn gain_rolls_needed(gain: spell_plan.Gain) -> Int {
  case gain {
    spell_plan.TickingGain(..) -> 0
    spell_plan.Gain(condition:, ..) ->
      gates_rolls_needed(only_on_caster_gates(condition:))
  }
}

/// The Proxies of the phase that the cast's n chooses and that have a unit to start a
/// child on: one aimed at the caster always, one aimed at each struck unit when the
/// round has a Hit.
pub fn proxies_with_targets(
  spell spell: Spell,
  phase phase: Int,
  struck struck: List(Struck),
  spent spent: Option(Int),
) -> List(Proxy) {
  let hit = hit_units(struck:) != []
  list.filter(spell_plan.proxies_in_phase(spell:, phase:, spent:), fn(proxy) {
    starts_a_child(proxy:, hit:)
  })
}

/// Whether a Proxy has a unit to start a child on: one aimed at the caster always has, one
/// aimed at each struck unit when the round has a Hit.
fn starts_a_child(proxy proxy: Proxy, hit hit: Bool) -> Bool {
  case proxy.target {
    spell_plan.OnCaster -> True
    spell_plan.OnEachStruck -> hit
  }
}

/// The gains of a Proxy's child that the go of its parent gives once (the gains the
/// plan lifted onto the Proxy); none for a Proxy that is never started.
fn lifted_gains(proxy proxy: Proxy) -> List(spell_plan.Gain) {
  case proxy.condition {
    spell_plan.Always | spell_plan.GatedOnCaster(..) -> proxy.gains
    spell_plan.GatedOnTarget(..) | spell_plan.GatedOnCasterAndTarget(..) -> []
  }
}

/// The units an effect aims at (`Spell4Effects.targetFlags`): each unit the aim's bits name
/// (the caster, the primary target, the units the round hit), once each, in that order
/// (`spell_plan.units_aimed_at`).
fn units_aimed_at(
  aim aim: spell_plan.Aim,
  caster caster: Caster,
  primary_target primary_target: Int,
  struck struck: List(Struck),
) -> List(Int) {
  spell_plan.units_aimed_at(
    aim:,
    caster: caster.unit_id,
    primary_target:,
    area: hit_units(struck:),
  )
}

/// Each row with each unit its aim names.
pub fn rows_with_units(
  rows rows: List(row),
  aim aim: fn(row) -> spell_plan.Aim,
  caster caster: Caster,
  primary_target primary_target: Int,
  struck struck: List(Struck),
) -> List(#(row, Int)) {
  list.flat_map(rows, fn(row) {
    units_aimed_at(aim: aim(row), caster:, primary_target:, struck:)
    |> list.map(fn(unit_id) { #(row, unit_id) })
  })
}

/// Whether a modifier row takes effect on `unit_id`, one of the units its aim names.
/// - A property, look, absorb or Interrupt Armor change lands on the caster alone: the
///   server gives no other unit a property, a look, a pool or armor. A part of the aim past
///   the caster (the primary target when it is another unit, the units the round hit) is
///   left out here with no log line; the plan refuses the row where that part would be the
///   unit a Proxy's child is started on (`spell_plan.not_on_a_struck_unit`), and the
///   client's absorb and Interrupt Armor rows with flags 3 or 7 are in no such child.
/// - A property modifier aimed at struck units (`StruckChange`) lands on a creature the go
///   hit; a player it names is left out until a modifier on another player is built (#570).
pub fn modifier_applies(
  row row: spell_plan.PropertyModifier,
  unit_id unit_id: Int,
  caster caster: Caster,
  struck struck: List(Struck),
) -> Bool {
  case row.change {
    spell_plan.StruckChange(..) -> result.is_ok(creature_hit(struck:, unit_id:))
    spell_plan.PropertyChange(..)
    | spell_plan.LookChange(..)
    | spell_plan.AbsorbChange(..) -> unit_id == caster.unit_id
  }
}

/// The life of the creature `unit_id` the round hit and the time it was struck.
pub fn creature_hit(
  struck struck: List(Struck),
  unit_id unit_id: Int,
) -> Result(#(Int, Int), Nil) {
  list.find_map(struck, fn(one) {
    case one {
      Hit(unit_id: hit, unit: HitCreature(life:, struck_at_ms:), ..)
        if hit == unit_id
      -> Ok(#(life, struck_at_ms))
      Immune(unit_id: hit, unit: HitCreature(life:, struck_at_ms:), ..)
        if hit == unit_id
      -> Ok(#(life, struck_at_ms))
      Hit(..) | Immune(..) | Deflected(..) -> Error(Nil)
    }
  })
}

/// The target apply prerequisite of a condition.
pub fn target_gate_of(
  condition condition: spell_plan.Condition,
) -> Option(prerequisite.Prerequisite) {
  case condition {
    spell_plan.GatedOnTarget(prerequisite: target)
    | spell_plan.GatedOnCasterAndTarget(target:, ..) -> Some(target)
    spell_plan.Always | spell_plan.GatedOnCaster(..) -> None
  }
}

/// What a target apply prerequisite gives for the unit `unit_id` its row would reach, as
/// the decision of a gate: a unit that fails it is left alone, and one the server cannot
/// tell is left alone with a line saying so. `what` names the row and `outcome` what
/// follows. The check takes the rolls of its type 37 conditions off the front of `rolls`,
/// and the rolls left follow it.
pub fn unit_gate(
  target target: prerequisite.Prerequisite,
  unit_id unit_id: Int,
  target_verdict target_verdict: TargetVerdict,
  what what: String,
  outcome outcome: String,
  rolls rolls: List(Int),
) -> #(GateDecision, List(Int)) {
  let #(verdict, rolls) = target_verdict(target, unit_id, rolls)
  #(
    case verdict {
      prerequisite.Passes -> Starts
      prerequisite.Fails -> GateFails
      prerequisite.NotRead(prerequisite_type:) ->
        CannotTell(
          why: what
          <> " on unit "
          <> int.to_string(unit_id)
          <> " is behind target prerequisite "
          <> int.to_string(prerequisite.id(prerequisite: target).value)
          <> " of type "
          <> int.to_string(prerequisite_type)
          <> ", which is not read, "
          <> outcome,
        )
    },
    rolls,
  )
}

/// The rolls a go's strike takes for a row behind `condition` that reaches at most `units`
/// units: one for each type 37 condition of its caster apply prerequisites, taken once, and
/// one for each type 37 condition of its target apply prerequisite for each unit, since each
/// test draws a roll of its own (`Prerequisite.prerequisiteTypeId.37`).
pub fn strike_rolls_needed(
  condition condition: spell_plan.Condition,
  units units: Int,
) -> Int {
  gates_rolls_needed(caster_gates(condition:))
  + target_rolls_needed(condition:, units_reached: units)
}

/// The rows with units that pass their row's target apply prerequisite for that unit,
/// and a debug line for each the server cannot tell, and the rolls left. A row with no
/// target gate reaches every unit its aim names; the others are checked in the order of
/// the entries, each taking the rolls its gate needs.
pub fn reaching(
  entries entries: List(#(row, Int)),
  condition condition: fn(row) -> spell_plan.Condition,
  what what: fn(row) -> String,
  target_verdict target_verdict: TargetVerdict,
  rolls rolls: List(Int),
) -> #(List(#(row, Int)), List(Effect), List(Int)) {
  let #(reached, logs, rolls) =
    list.fold(entries, #([], [], rolls), fn(so_far, entry) {
      let #(reached, logs, rolls) = so_far
      case target_gate_of(condition: condition(entry.0)) {
        None -> #([entry, ..reached], logs, rolls)
        Some(target) -> {
          let #(gate, rolls) =
            unit_gate(
              target:,
              unit_id: entry.1,
              target_verdict:,
              what: what(entry.0),
              outcome: "so it is not applied",
              rolls:,
            )
          case gate {
            Starts -> #([entry, ..reached], logs, rolls)
            GateFails -> #(reached, logs, rolls)
            CannotTell(why:) -> #(
              reached,
              [Log(level: LogDebug, text: why), ..logs],
              rolls,
            )
          }
        }
      }
    })
  #(list.reverse(reached), list.reverse(logs), rolls)
}

/// The entries of rows whose gate on the struck creature the unit passed: a row with no
/// gate (`Spell.struck_gates`) reaches every unit its aim names, and one with a gate
/// reaches a unit only when that unit's answer lists the row's effect id. The gate is the
/// struck creatures' alone, so the entry of a row aimed at the caster as well as past it
/// that stands on the caster passes it (its caster prerequisite is read by `reaching`).
pub fn passing_struck_gates(
  entries entries: List(#(row, Int)),
  effect_id effect_id: fn(row) -> Spell4EffectsId,
  spell spell: Spell,
  caster_unit_id caster_unit_id: Int,
  gates_passed gates_passed: Dict(Int, List(Int)),
) -> List(#(row, Int)) {
  list.filter(entries, fn(entry) {
    entry.1 == caster_unit_id
    || gate_passed(
      effect_id: effect_id(entry.0),
      unit_id: entry.1,
      spell:,
      gates_passed:,
    )
  })
}

/// Whether the row `effect_id` stands on `unit_id`: it has no gate on the struck creature,
/// or the unit's answer lists it as passed.
fn gate_passed(
  effect_id effect_id: Spell4EffectsId,
  unit_id unit_id: Int,
  spell spell: Spell,
  gates_passed gates_passed: Dict(Int, List(Int)),
) -> Bool {
  use <- bool.guard(
    when: !list.any(spell.struck_gates, fn(gate) { gate.effect_id == effect_id }),
    return: True,
  )
  dict.get(gates_passed, unit_id)
  |> result.unwrap([])
  |> list.contains(effect_id.value)
}

/// The units the round hit or found immune, less the periodic rows that have a gate on the
/// struck creature which that unit did not pass.
pub fn struck_gates_applied(
  struck struck: List(Struck),
  spell spell: Spell,
  gates_passed gates_passed: Dict(Int, List(Int)),
) -> List(Struck) {
  let standing = fn(unit_id, rows: List(spell_area.TickingDamage)) {
    list.filter(rows, fn(row) {
      gate_passed(
        effect_id: row.damage.effect_id,
        unit_id:,
        spell:,
        gates_passed:,
      )
    })
  }
  list.map(struck, fn(one) {
    case one {
      Hit(unit_id:, ticking:, ..) ->
        Hit(..one, ticking: standing(unit_id, ticking))
      Immune(unit_id:, ticking:, ..) ->
        Immune(..one, ticking: standing(unit_id, ticking))
      Deflected(..) -> one
    }
  })
}

/// What a prerequisite may read about a player entering a world, before its unit and
/// its casts exist: the player and the factions and the quest log they hold, `health`
/// (the health it enters at against its maximum, the value world entry makes the
/// player's life from; `None` leaves the vital unread), and the values a player starts
/// with: no casts, not in combat, not stealthed and a full shield. The class resource
/// slots and the positions are not held, so a prerequisite that reads those is
/// `NotRead`, never `Fails` (genesis_prime/game/visibility). None of the 68 condition
/// types that the Creature2 rows' `prerequisiteIdVisibility` reach (2285 distinct
/// root rows, nested rows followed) is type 64, which reads a resource slot, or type
/// 108, the only type that reads a position, so no unit's visibility depends on them;
/// types 71 and 73, which read a vital, are not among them either, but the health is
/// held for a prerequisite the tables may add. The first step's check decides it all
/// with the real values. The player's items and abilities arrive with the Joined message,
/// after this check, so the subject holds no checker: types 13, 14, 246, 143 and 214 are
/// `NotRead` and the creatures they gate stay shown until that first step's check.
pub fn entering_subject(
  player player: prerequisite.Player,
  factions factions: prerequisite.Factions,
  quests quests: QuestLog,
  health health: Option(prerequisite.Vital),
) -> prerequisite.Subject {
  let full = prerequisite.Vital(current: 1.0, maximum: 1.0)
  prerequisite.Subject(
    under: [],
    second_unit: None,
    in_combat: False,
    vitals: dict.from_list(case health {
      Some(held) -> [
        #(cast_state.health_vital, held),
        #(cast_state.shield_vital, full),
      ]
      None -> [#(cast_state.shield_vital, full)]
    }),
    difficulty: None,
    stealthed: Some(False),
    resource_slots: None,
    rolls: [],
    positions: prerequisite.NotPlaced,
    factions: Some(factions),
    player: Some(player),
    quests: Some(quests),
    creature_index: None,
    seen: prerequisite.WholeUnit,
    checker: None,
    first_unit: prerequisite.TheChecker,
  )
}

/// The prerequisite checked against the subject with the rolls its type 37
/// conditions take off the front of `rolls`, and the rolls left.
pub fn checked(
  prerequisite gate: prerequisite.Prerequisite,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(prerequisite.Verdict, List(Int)) {
  let #(taken, left) =
    list.split(rolls, prerequisite.rolls_needed(prerequisite: gate))
  #(
    prerequisite.check(
      prerequisite: gate,
      subject: prerequisite.Subject(..subject, rolls: taken),
    ),
    left,
  )
}

/// The gates a go checks against the caster's own unit for a row that may reach other
/// units: its caster apply prerequisites. The row's target apply prerequisite is checked
/// for each unit the row reaches, whose first unit is that unit and whose second the
/// caster (`target_verdict`, `Spell4Effects.prerequisiteIdTargetApply`).
pub fn caster_gates(
  condition condition: spell_plan.Condition,
) -> List(prerequisite.Prerequisite) {
  case condition {
    spell_plan.Always | spell_plan.GatedOnTarget(..) -> []
    spell_plan.GatedOnCaster(gates:)
    | spell_plan.GatedOnCasterAndTarget(caster: gates, ..) -> gates
  }
}

/// The gates a go checks against the caster's own unit for a row that reaches only the
/// caster: its caster apply prerequisites, then its target apply prerequisite, whose first
/// unit is that unit, the caster's whole unit (`cast_tick.subject_of`).
fn only_on_caster_gates(
  condition condition: spell_plan.Condition,
) -> List(prerequisite.Prerequisite) {
  case condition {
    spell_plan.Always -> []
    spell_plan.GatedOnTarget(prerequisite: target) -> [target]
    spell_plan.GatedOnCaster(gates:) -> gates
    spell_plan.GatedOnCasterAndTarget(caster:, target:) ->
      list.append(caster, [target])
  }
}

/// Whether a go applies an effect of this kind at all: a property modifier with no life
/// (`lasting.has_life`) is applied by none, so the go checks no gate of it, caster or
/// target, and draws no roll for it. The roll count (`effect_rolls_needed`) and the check
/// (`gates_checked_on_caster`, which leaves such a row out of the rows the go reaches) both
/// ask it.
fn applied_by_go(kind kind: spell_plan.Kind) -> Bool {
  case spell_plan.as_modifier(kind:) {
    Ok(row) -> lasting.has_life(row: row.row)
    Error(Nil) -> True
  }
}

/// The gates a go checks against the caster's own unit for an effect of this kind, the one
/// choice between `caster_gates` (a row that may reach other units) and `only_on_caster_gates`
/// (a row that reaches only the caster) for each kind: the roll count (`effect_rolls_needed`)
/// and the check (`control.lasting_applied`) both ask it, so they cannot differ. A Proxy's and
/// a gain's gates are checked apart (`proxy_gates`, `gains_given`), a crowd-control state
/// that does not reach the caster is the strike's, and a property modifier with no life is
/// applied by no go (`applied_by_go`), so those have none.
pub fn gates_checked_on_caster(
  kind kind: spell_plan.Kind,
) -> Result(List(prerequisite.Prerequisite), Nil) {
  use <- bool.guard(when: !applied_by_go(kind:), return: Error(Nil))
  case kind {
    spell_plan.ProxyEffect(..) | spell_plan.GainEffect(..) -> Error(Nil)
    spell_plan.LastingEffect(lasting: row) ->
      Ok(caster_gates(condition: row.condition))
    spell_plan.RemoveEffect(remove: row) ->
      Ok(caster_gates(condition: row.condition))
    spell_plan.ModifierEffect(modifier: row) ->
      Ok(caster_gates(condition: row.condition))
    spell_plan.StruckMoveEffect(struck_move: row) ->
      Ok(caster_gates(condition: row.condition))
    spell_plan.HealEffect(heal: row) ->
      Ok(caster_gates(condition: row.condition))
    spell_plan.ForcedMoveEffect(forced_move: row) ->
      Ok(only_on_caster_gates(condition: row.condition))
    spell_plan.CooldownEffect(modifier: row) ->
      Ok(only_on_caster_gates(condition: row.condition))
    spell_plan.StealthEffect(stealth: row) ->
      Ok(only_on_caster_gates(condition: row.condition))
    spell_plan.RemoveStealthEffect(remove: row) ->
      Ok(only_on_caster_gates(condition: row.condition))
    spell_plan.ProcEffect(proc: row) ->
      Ok(only_on_caster_gates(condition: row.condition))
    spell_plan.ControlEffect(control: row) ->
      case spell_plan.reaches_caster(aim: row.aim) {
        True -> Ok(only_on_caster_gates(condition: row.condition))
        False -> Error(Nil)
      }
  }
}

/// Which of the Proxies of a go start a child, with a debug line for each that
/// cannot be decided, and the rolls left (`gated`).
pub fn proxy_gates(
  proxies proxies: List(Proxy),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(List(Proxy), List(Effect), List(Int)) {
  gated(
    rows: proxies,
    gates: fn(proxy: Proxy) { caster_gates(condition: proxy.condition) },
    what: fn(proxy: Proxy) {
      "the Proxy to Spell4 " <> int.to_string(proxy.spell.spell4_id.value)
    },
    outcome: "so it is not started",
    subject:,
    rolls:,
  )
}

/// The rows whose gates let them apply, in order, with a debug line for each the
/// server cannot decide, and the rolls left: a row with no gate applies, one with gates
/// applies when every gate passes against the caster (`gates_gate`).
pub fn gated(
  rows rows: List(row),
  gates gates: fn(row) -> List(prerequisite.Prerequisite),
  what what: fn(row) -> String,
  outcome outcome: String,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(List(row), List(Effect), List(Int)) {
  let #(applying, logs, rolls) =
    list.fold(rows, #([], [], rolls), fn(so_far, row) {
      let #(applying, logs, rolls) = so_far
      let #(gate, rolls) =
        gates_gate(
          gates: gates(row),
          subject:,
          rolls:,
          what: what(row),
          outcome:,
        )
      case gate {
        Starts -> #([row, ..applying], logs, rolls)
        GateFails -> #(applying, logs, rolls)
        CannotTell(why:) -> #(
          applying,
          [Log(level: LogDebug, text: why), ..logs],
          rolls,
        )
      }
    })
  #(list.reverse(applying), list.reverse(logs), rolls)
}

/// What gates give at a go: `what` names the effect in a debug line and `outcome` says
/// what follows when the server cannot decide. No gate lets the row apply.
pub fn gates_gate(
  gates gates: List(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
  what what: String,
  outcome outcome: String,
) -> #(GateDecision, List(Int)) {
  let #(left, verdicts) =
    list.map_fold(gates, rolls, fn(rolls, gate) {
      let #(verdict, left) = checked(prerequisite: gate, subject:, rolls:)
      #(left, #(gate, verdict))
    })
  let not_read =
    list.find_map(verdicts, fn(decided) {
      case decided.1 {
        prerequisite.NotRead(prerequisite_type:) ->
          Ok(#(decided.0, prerequisite_type))
        prerequisite.Passes | prerequisite.Fails -> Error(Nil)
      }
    })
  let failed =
    list.any(verdicts, fn(decided) { decided.1 == prerequisite.Fails })
  case failed, not_read {
    True, _ -> #(GateFails, left)
    False, Error(Nil) -> #(Starts, left)
    False, Ok(#(gate, prerequisite_type)) -> #(
      CannotTell(
        why: what
        <> " is behind prerequisite "
        <> int.to_string(prerequisite.id(prerequisite: gate).value)
        <> " of type "
        <> int.to_string(prerequisite_type)
        <> ", which is not read, "
        <> outcome,
      ),
      left,
    )
  }
}

/// The gains a go gives (`Gain`), and a debug line for each it cannot: the spell's
/// own of the phase, then once each of the Proxies that start a child aimed at each
/// struck unit, which `starting` holds only when one unit was Hit.
pub fn gains_given(
  spell spell: Spell,
  phase phase: Int,
  starting starting: List(Proxy),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
  spent spent: Option(Int),
) -> #(List(Effect), List(Int)) {
  let #(rolls, given, logs) =
    list.fold(
      gains_of(spell:, phase:, proxies: starting, spent:),
      #(rolls, [], []),
      fn(so_far, gain) {
        let #(rolls, given, logs) = so_far
        let #(verdict, rolls) = gain_verdict(gain:, subject:, rolls:)
        case verdict {
          Given(gain: gift) -> #(rolls, [gift, ..given], logs)
          Withheld -> #(rolls, given, logs)
          NotApplied(why:) -> #(rolls, given, [
            Log(level: LogDebug, text: why),
            ..logs
          ])
        }
      },
    )
  let gains = case given {
    [] -> []
    [_, ..] -> [Gain(gains: list.reverse(given))]
  }
  #(list.append(list.reverse(logs), gains), rolls)
}

/// The gain given, withheld for a prerequisite that fails, or not applied, and the
/// rolls left after its prerequisite's check.
fn gain_verdict(
  gain gain: spell_plan.Gain,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(GainVerdict, List(Int)) {
  let effect = int.to_string(gain.effect_id.value)
  case gain {
    spell_plan.TickingGain(..) -> #(
      NotApplied(
        why: "the ticking gain of Spell4Effects " <> effect <> " is not applied",
      ),
      rolls,
    )
    spell_plan.Gain(condition:, slot:, amount:, ..) -> {
      let #(gate, rolls) =
        gates_gate(
          gates: only_on_caster_gates(condition:),
          subject:,
          rolls:,
          what: "the gain of Spell4Effects " <> effect,
          outcome: "so it is not given",
        )
      #(
        case gate {
          Starts -> Given(gain: class_resource.Gain(slot:, amount:))
          GateFails -> Withheld
          CannotTell(why:) -> NotApplied(why:)
        },
        rolls,
      )
    }
  }
}

/// Whether a go clears the caster's current cast (`cast.current_cast`): a cast with
/// a cast bar, a cast time and no parent clears whichever cast is current, unless
/// its method is Channeled, PressHold, ChanneledField, ChargeRelease or
/// Multiphase; any other cast clears it only when it is the current cast, has no
/// channel and is not PressHold, ChargeRelease or Multiphase.
pub fn clears_current(
  cast cast: State,
  live live: Live,
  cast_id cast_id: Int,
) -> Bool {
  use <- bool.guard(when: cast.passive == Some(cast_id), return: False)
  let spell = live.spell
  let clears_whichever = case spell.method {
    spell_plan.Normal
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) ->
      spell.cast_time_ms != 0
      && live.parent == None
      && spell_plan.shows_cast_bar(
        spell:,
        pressed: live.root == spell.spell4_id,
      )
    spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ChargeRelease
    | spell_plan.Multiphase -> False
  }
  let clears_itself = case spell.method {
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) ->
      cast.current == Some(cast_id) && option.is_none(spell.channel)
    spell_plan.PressHold | spell_plan.ChargeRelease | spell_plan.Multiphase ->
      False
  }
  clears_whichever || clears_itself
}

/// The units a round Hit, in the round's order; a deflect is none of them.
pub fn hit_units(struck struck: List(Struck)) -> List(Int) {
  list.filter_map(struck, fn(one) {
    case one {
      Hit(unit_id:, ..) | Immune(unit_id:, ..) -> Ok(unit_id)
      Deflected(..) -> Error(Nil)
    }
  })
}
