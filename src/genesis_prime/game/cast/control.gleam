//// The lasting modifiers, restrictions and crowd control a cast starts, and the cooldowns it arms.
////
//// - **A go's lasting effects** (genesis_prime/game/lasting): each Fluff (17), Scale (18),
////   ItemVisualSwap (76), RavelSignal (81) and SpellForceRemove (80) effect of the phase whose gate against the
////   caster passes is listed in the target info of each unit its targetFlags aim at, with
////   the effect's delay, a result bit, the instance count 1 and the lifetime 0 the client
////   works out itself; a unit the round did not strike gets an info of its own
////   (`opcode.0x7f4.target_info`, `opcode.0x7f4.effect_time`). A Fluff, Scale,
////   ItemVisualSwap or RavelSignal effect gives the unit a node of the cast that lives as long as its
////   longest effect, kept on the live cast; a type 80 effect takes the matching nodes of the caster's casts off the
////   unit, oldest cast first, each written 0x811 (`opcode.0x811`); and a cast that
////   gives a unit a node it holds none on takes off the caster's oldest casts of its
////   stack at the stack's cap (Jim's decision, `Spell4StackGroup.stackCap`).
//// - **A go's property modifiers** (genesis_prime/game/unit_properties): each type 11
////   and type 145 effect of the phase that has a life (a durationTime, or flags bit 2) and
////   whose gate against the caster passes is listed on the caster like a Fluff effect, gives the
////   caster's node its life, and starts at the go plus its delay and ends after its
////   duration, as `CasterChangeStarts` and `CasterChangeEnds` for the connection to apply to the
////   player's properties. A modifier ends on a timer of its own and not with the node's
////   time (a node can outlive it, or end before it when the spell takes the larger of
////   delay and duration); taking the cast's node off the caster ends its modifiers and
////   cancels their timers; the caster's death ends every modifier of its casts but the
////   innate passive's, and every one still pending but the passive's; a later go of the cast arms each again from that go; the player
////   leaving ends none, since the connection's properties go with its player. These
////   are the server's choices: the client works out no property.
//// - **A go's property modifiers on creatures** (type 11 rows whose targetFlags name a
////   unit other than the caster, a `StruckChange`; 3, 5 and 7 also change the caster, in
////   a row of their own, and a unit the flag names twice takes it once): each is aimed
////   at the creatures the go hit, and at the primary target when the flag's bit 2 names it, in the life and at the
////   time the go struck them (`HitCreature`), listed on each like a Fluff effect and
////   giving its node the row's life. The cast owns the time and the creature the values:
////   the rule tells the creature `TargetChangeStarts` at the go plus the row's delay, in
////   the go's own step when there is none, and keeps what it started in `on_creatures`.
////   It has no end timer of its own: it ends, as `TargetChangeEnds` told once, when the
////   cast's node on that creature ends by time, is taken off by a type 80 removal or a
////   push off by the stack rule, when the creature leaves the caster's sight, when the
////   cast's persistence stops holding, when the caster dies (but for the innate passive's
////   cast) and when the player leaves; a start still waiting for its delay is cancelled
////   with it and told nothing. A later go of the cast on the same creature starts it
////   again from that go. A row aimed at another player is left out until a modifier on
////   another player is built (#570), and the stacking of casters' modifiers on one
////   creature is not built (#569).
//// - **A go's throws of creatures** (type 3 rows whose targetFlags name a unit other than
////   the caster, a `StruckMove`, genesis_prime/game/forced_move; 3, 5 and 7 also move
////   the caster): each is aimed at the creatures the go
////   hit, in the life and at the time the go struck them. The rule tells
////   `ForcedMoveStarts` at the go's own step when the row has no delay, and else arms a
////   `ForcedMoveStart` timer for the go plus the row's delay; the end of the cast's node
////   on that creature cancels a timer still waiting (`creatures_ended`), as it cancels a
////   modifier's start. The connection carries `ForcedMoveStarts` out
////   (genesis_prime/game/connection/casting): it draws the throw's two fractions from its
////   seed then, so a delayed throw draws at its own time, and tells the creature. A
////   connection that is gone has no timers, so nothing is thrown.
//// - **A go's despawns of creatures** (type 97 rows whose targetFlags name a unit other than
////   the caster, a `Despawn`; `Spell4Effects.effectType.97`): each is aimed at the creatures
////   the go hit, in the life and at the time the go struck them. The rule tells each
////   `CreatureDespawns` in the go's own step, with the row's delay and the go's time, and
////   arms no timer: the creature owns the delay (`despawns_told`).
//// - **A go's unit states on creatures** (type 15 rows whose targetFlags name a unit other
////   than the caster, a `UnitState`; `Spell4Effects.effectType.15`): each is aimed at the
////   creatures the go hit, in the life and at the time the go struck them. The rule tells
////   each creature one `CreatureHoldsUnitStates` in the go's own step, with the creature's
////   rows in row order and the go's time, and arms no timer: the creature owns the end of
////   each state (`unit_states_told`).
//// - **A go's disguises** (genesis_prime/game/look): each type 112 effect of the phase
////   that has a life and whose gate against the caster passes is a modifier row whose change is a
////   `Look`, so it is listed, started, ended, cancelled with the node and ended at death
////   by the modifiers' rules above, as `CasterChangeStarts` and `CasterChangeEnds`; the
////   connection turns them into the player's 0x933 and its viewers' `LookChanged`
////   (genesis_prime/game/connection/look). The rule keeps no look: two disguises on one
////   slot, the base and what shows are the look's.
//// - **A go's Interrupt Armor** (`Spell4Effects.effectType.52`): each ModifyInterruptArmor
////   row of the phase that reaches the caster (genesis_prime/game/spell_plan
////   `PropertyModifier.armor`) is a property modifier of property 44, the armor's maximum,
////   and goes through every rule of the property modifiers above: the same listing, node
////   life, start, timer, end and removal. The player's armor follows its maximum
////   (genesis_prime/game/player_life `armor_followed`), so the rule asks nothing more of
////   the connection for it. The client has no case for the effect, so the armor and its
////   maximum are the server's (`Spell4Effects.effectType.52`,
////   `opcode.0x938.interrupt_armor`).
//// - **A go's absorbs** (`Spell4Effects.effectType.29`): each Absorption effect of the phase
////   that reaches the caster, has a lifetime (a durationTime, or flags bit 2), is not
////   periodic and whose gate against the caster passes is listed in the caster's target
////   info like a Fluff effect, gives the caster's node its life, and starts a pool on
////   the caster, as a heal and a property modifier do, from the amount worked out at
////   the go from the caster's stats as they stood before the go's own effects
////   (genesis_prime/game/damage). The plan reads a type 29 row as a property modifier row
////   whose change is an `AbsorbChange` (genesis_prime/game/spell_plan), so it goes
////   through the same listing, node life, timers, end and removal. The sequence of one go:
////
////   ```
////   go ─▶ 0x7f4 lists the row on the caster
////      ─▶ no delay: CasterChangeStarts(source, Absorb(amount, mask)) in the go's step, after its 0x7f4
////         delay:    a ModifierStart timer of the delay
////      ─▶ ModifierEnd timer at delay + duration, none for flags bit 2
////   ModifierStart fires ─▶ CasterChangeStarts(source, Absorb(amount, mask))
////   ModifierEnd fires   ─▶ CasterChangeEnds(source)
////   ```
////
////   A pool ends on a timer of its own, as a property modifier does, and the connection
////   ends it by source (genesis_prime/game/connection/absorption), where a pool the
////   hit rule used up is already gone and the end writes nothing: the cast keeps its
////   node's time when its pool is spent (a server choice). Taking the cast's node off
////   the caster ends the pool of each row and cancels its timers; the caster's death
////   ends every pool of its casts and cancels the pending ones, after the life dropped
////   them; the player leaving ends none, since the life goes with its `Entered`; a later go
////   of the cast arms each pool again from that go, which refills a pool still held.
//// - **A go's forced moves** (`Spell4Effects.effectType.3.player`): each type 3 effect of
////   the phase aimed at the caster whose gate against the caster passes is listed in the
////   caster's target info with its delay, and nothing more: the caster's client works out
////   the destination, moves its own unit and reports the move in its next 0x637, which
////   the movement rule takes as any other. A forced move gives no node a life, starts no
////   timer and changes no property.
//// - **A go's cooldown effects** (`Spell4Effects.effectType.73`,
////   genesis_prime/game/cooldown): the spell's own cooldown and a stage's ability
////   cooldown start before the go's effects apply, as in the client (`0x14053e5a0`), so
////   a type 73 effect of the phase aimed at the caster whose gate passes already sees
////   them. It is listed in the caster's target info with its delay, and it changes the
////   running cooldowns it picks at the go plus its delay: in the go's step with no
////   delay, on a timer with one. An effect whose lifetime (delay plus duration, the
////   larger of the two for a spell with the record flag 0x10000000, never ending with
////   flags bit 2) ends after its start is also kept for the cooldowns that start later
////   and dropped on a timer at the end of its lifetime; any other acts once
////   (`0x14046b7f0`, `opcode.0x7f4.effect_time`). Every such effect gives the caster's
////   node its lifetime, so the 0x7fe, which destroys the effects still pending
////   (`opcode.0x7fe`), waits for them; when the node's end and a pending start are due
////   in the same millisecond the end applies the start first. Taking the cast's node
////   off the caster, the caster's death and its leaving drop the kept effects and
////   cancel their timers, pending starts included, and a later go of the cast keeps
////   each again from that go; the cooldowns an effect changed stay changed. The global cooldown is never changed (`0x14046b920`) and the server sends
////   no 0x804, which would undo the change. After a change a press held for a cooldown's
////   end and the hold's repeat wait for the new end, a timer of 0 ms when it ended: the
////   server's choice. Group cooldowns are not kept.

import genesis_prime/client_connection
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/state.{
  type Aimed, type Applied, type Caster, type CasterChange, type Due,
  type Effect, type HeldRestriction, type Live, type OnCreature, type Reached,
  type Restricting, type State, type Struck, Absorb, Applied, CasterChangeStarts,
  ChargeLevel, CooldownModifierEnds, CooldownModifierStarts, CreatureDespawns,
  CreatureHoldsUnitStates, Deflected, Finish, ForcedMoveStart, ForcedMoveStarts,
  Go, HeldRestriction, Hit, Immune, Look, ModifierEnd, ModifierStart, NodesEnd,
  OnCreature, ProcDue, Property, RepeatHeld, Restricting, RestrictionEnd, Send,
  StartChild, StartHeld, State, StateEnd, TargetChangeEnds, TargetChangeStarts,
  TargetModifierStart, Tell, Tick, WindowEnd,
} as cast_state
import genesis_prime/game/crowd_control
import genesis_prime/game/damage
import genesis_prime/game/forced_move
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties
import genesis_prime/message/crowd_control_state
import genesis_prime/table/id.{type Spell4EffectsId}
import genesis_prime/world_map/map
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The delay of a property modifier on a creature ran out: it starts on the creature
/// (`TargetChangeStarts`) and the cast keeps it in `on_creatures` until an end of its
/// node; a cast that has ended since starts nothing.
pub fn target_modifier_started(
  cast cast: State,
  on on: OnCreature,
  modifier modifier: unit_properties.Modifier,
  struck_at_ms struck_at_ms: Int,
) -> #(State, List(Effect)) {
  let cast_id = on.source.cast_id
  let held = case cast_state.holder_of(cast:, cast_id:) {
    Ok(holder) -> dict.has_key(holder.nodes, on.unit_id)
    Error(Nil) -> False
  }
  use <- bool.guard(when: !held, return: #(cast, []))
  // A later go of the cast strikes the same creature again: its start replaces the
  // earlier one, which the creature replaces by source too.
  let started =
    dict.get(cast.on_creatures, cast_id)
    |> result.unwrap([])
    |> list.filter(fn(kept) {
      kept.unit_id != on.unit_id || kept.source != on.source
    })
  #(
    State(
      ..cast,
      on_creatures: dict.insert(
        cast.on_creatures,
        cast_id,
        list.append(started, [on]),
      ),
    ),
    [
      TargetChangeStarts(
        unit_id: on.unit_id,
        life: on.life,
        struck_at_ms:,
        source: on.source,
        modifier:,
      ),
    ],
  )
}

/// The property modifiers the cast `cast_id` holds on the creatures `ending` names end:
/// each that started is told ended once and forgotten, and each that still waits for
/// its delay has its timer cancelled and is told nothing. A modifier already ended is
/// not told again.
pub fn creature_modifiers_ended(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  creatures_ended(cast:, cast_id:, ending: list.contains(unit_ids, _))
}

/// Every property modifier the cast `cast_id` holds on a creature ends, as a persistence
/// that stops holding destroys all its nodes.
pub fn creature_modifiers_all_ended(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  creatures_ended(cast:, cast_id:, ending: fn(_) { True })
}

fn creatures_ended(
  cast cast: State,
  cast_id cast_id: Int,
  ending ending: fn(Int) -> Bool,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case target_start_of(due:) {
        Ok(waiting) ->
          waiting.source.cast_id == cast_id && ending(waiting.unit_id)
        Error(Nil) -> False
      }
    })
  let #(ended, kept) =
    dict.get(cast.on_creatures, cast_id)
    |> result.unwrap([])
    |> list.partition(fn(on) { ending(on.unit_id) })
  let on_creatures = case kept {
    [] -> dict.delete(cast.on_creatures, cast_id)
    [_, ..] -> dict.insert(cast.on_creatures, cast_id, kept)
  }
  #(
    State(..cast, on_creatures:),
    list.append(
      cancels,
      list.map(ended, fn(on) {
        TargetChangeEnds(unit_id: on.unit_id, life: on.life, source: on.source)
      }),
    ),
  )
}

/// The Fluff, SpellForceRemove, property modifier, forced move, struck move, cooldown,
/// Stealth, RemoveStealth, Proc, heal and ability restriction effects of the phase whose
/// gates pass against the caster, a debug line for each that cannot be decided, and the
/// rolls left. The effects are walked in the plan's rank order, which is the order their
/// gates are checked in, after the Proxies' and the gains', the restrictions' last
/// (`cast_gate.rolls_needed`).
pub fn lasting_applied(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(Applied, List(Effect), List(Int)) {
  let checked =
    spell_effect.in_phase(effects: spell.effects, phase:, spent:)
    |> list.filter_map(caster_checked)
  let #(passed, logs, rolls) =
    cast_gate.gated(
      rows: checked,
      gates: fn(one: CasterChecked) { one.gates },
      what: fn(one: CasterChecked) { one.what },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  #(Applied(passed: list.map(passed, fn(one) { one.planned })), logs, rolls)
}

/// An effect the go checks against the caster, with its gates and what a debug line calls it.
type CasterChecked {
  CasterChecked(
    planned: spell_effect.PlannedEffect(spell_plan.Kind),
    gates: List(prerequisite.Prerequisite),
    what: String,
  )
}

/// The effect with the gates the go checks against the caster (`cast_gate.gates_checked_on_caster`)
/// and its name. An effect with no gate here is left out: a Proxy's and a gain's gates are
/// checked apart (`cast_gate.proxy_gates`, `cast_gate.gains_given`), a property modifier
/// with no life changes nothing, and a crowd-control state that does not reach the caster
/// is the strike's.
fn caster_checked(
  planned: spell_effect.PlannedEffect(spell_plan.Kind),
) -> Result(CasterChecked, Nil) {
  use gates <- result.try(cast_gate.gates_checked_on_caster(kind: planned.kind))
  use what <- result.map(effect_named(kind: planned.kind))
  CasterChecked(planned:, gates:, what:)
}

/// What a debug line calls an effect of this kind that the go checks against the caster; a
/// Proxy and a gain are named where their own gates are checked.
fn effect_named(kind kind: spell_plan.Kind) -> Result(String, Nil) {
  let named = fn(what: String, effect_id: Spell4EffectsId) {
    Ok(what <> " effect " <> int.to_string(effect_id.value))
  }
  case kind {
    spell_plan.ProxyEffect(..) | spell_plan.GainEffect(..) -> Error(Nil)
    spell_plan.LastingEffect(lasting: row) ->
      named("the lasting", row.effect_id)
    spell_plan.RemoveEffect(remove: row) ->
      named("the SpellForceRemove", row.effect_id)
    spell_plan.ModifierEffect(modifier: row) ->
      named("the " <> modifier_kind_named(row:), row.effect_id)
    spell_plan.ForcedMoveEffect(forced_move: row) ->
      named("the ForcedMove", row.effect_id)
    spell_plan.StruckMoveEffect(struck_move: row) ->
      named("the ForcedMove", row.effect_id)
    spell_plan.DespawnEffect(despawn: row) ->
      named("the DespawnUnit", row.effect_id)
    spell_plan.UnitStateEffect(unit_state: row) ->
      named("the UnitStateSet", row.effect_id)
    spell_plan.CooldownEffect(modifier: row) ->
      named("the ModifySpellCooldown", row.effect_id)
    spell_plan.StealthEffect(stealth: row) ->
      named("the Stealth", row.effect_id)
    spell_plan.RemoveStealthEffect(remove: row) ->
      named("the RemoveStealth", row.effect_id)
    spell_plan.ProcEffect(proc: row) -> named("the Proc", row.effect_id)
    spell_plan.HealEffect(heal: row) ->
      named("the Heal or HealShields", row.effect_id)
    spell_plan.ControlEffect(control: row) ->
      named("the ability restriction", row.effect_id)
  }
}

/// The go's states on the caster, each with its instance id: the one a cast already holds
/// for the effect, or the next of the caster's counter, held with the go's audience.
pub fn restrictions_numbered(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  live live: Live,
  applied applied: Applied,
) -> #(State, List(Restricting)) {
  list.fold(
    cast_state.passed_of(applied:, as_kind: spell_plan.as_control),
    #(cast, []),
    fn(so_far, row) {
      let #(cast, numbered) = so_far
      let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
      let #(cast, restricting) = case dict.get(cast.restrictions, source) {
        Ok(held) -> #(
          cast,
          Restricting(row:, instance_id: held.instance_id, fresh: False),
        )
        Error(Nil) -> {
          let told = cast.restrictions_told + 1
          let instance_id =
            crowd_control.instance_id(
              caster_unit_id: caster.unit_id,
              count: told,
            )
          #(
            State(
              ..cast,
              restrictions: dict.insert(
                cast.restrictions,
                source,
                HeldRestriction(
                  state: row.row.state,
                  instance_id:,
                  audience: live.audience,
                ),
              ),
              restrictions_told: told,
            ),
            Restricting(row:, instance_id:, fresh: True),
          )
        }
      }
      #(cast, list.append(numbered, [restricting]))
    },
  )
}

/// 0x87f to the caster and to the audience of the go, for each state the go gave
/// (`opcode.0x87f`); a state a cast already held is not told again. A Tether on the
/// caster is told its anchor first, the caster's own unit, by a 0x881 to the caster
/// alone: the message sets the anchor of the unit the receiving client controls and
/// names no unit, so the audience, whose clients control other units, gets none
/// (`opcode.0x881`). That the anchor is the caster's own unit is a guess; no client
/// value names it, and the issue "Spells work in depth on the real client: cast times, telegraphs, buffs,
/// crowd control and ticking effects" will settle it.
pub fn restrictions_shown(
  restricting restricting: List(Restricting),
  caster caster: Caster,
  live live: Live,
) -> List(Effect) {
  restricting
  |> list.filter(fn(one) { one.fresh })
  |> list.flat_map(fn(one) {
    let state = one.row.row.state
    list.flatten([
      case state == crowd_control_state.Tether {
        True -> [
          Send(frame: cast_frame.tether_anchor_frame(
            anchor_unit_id: caster.unit_id,
          )),
        ]
        False -> []
      },
      [
        Send(frame: cast_frame.control_applied_frame(
          unit_id: caster.unit_id,
          state:,
          instance_id: one.instance_id,
        )),
        ..list.map(map.sorted_connections(live.audience), fn(viewer) {
          Tell(
            to: viewer,
            news: client_connection.CrowdControlApplied(
              state:,
              instance_id: one.instance_id,
            ),
          )
        })
      ],
    ])
  })
}

/// The end of each state a go holds on the caster, on a timer of its delay and duration
/// unless it lasts until removed: the client's lifetime for a CCStateSet effect is
/// `trunc(durationTime * m + 0.5)` after its delay (`0x1405d6880`, `0x1405d8770`) and the
/// client never ends the state itself, so the server's timer does, as for a state on a
/// creature. A row of duration 0 without flag 2 lives 0 ms and ends in the go's own
/// step. A later go of the cast arms the state's end again from that go; the node's end
/// or removal cancels it (`cast_proc.effects_ended`).
pub fn restrictions_armed(
  cast cast: State,
  cast_id cast_id: Int,
  restricting restricting: List(Restricting),
) -> #(State, List(Effect)) {
  list.fold(restricting, #(cast, []), fn(so_far, one) {
    let #(cast, effects) = so_far
    let source = unit_properties.Source(cast_id:, effect_id: one.row.effect_id)
    let row = one.row.row
    let #(cast, cancels) = cast_state.cancel_source_timers(cast:, source:)
    case row.until_removed {
      True -> #(cast, list.append(effects, cancels))
      False -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: RestrictionEnd(source:),
            after_ms: row.delay_ms + row.duration_ms,
          )
        #(cast, list.flatten([effects, cancels, [start]]))
      }
    }
  })
}

/// The state the effect `source` gave the caster ends with its row, ahead of its cast's
/// node: 0x880 to the caster and the audience told of it. A state no longer held, because
/// the node ended or was taken off first, or the caster died or left, ends nothing.
pub fn restriction_ended(
  cast cast: State,
  source source: unit_properties.Source,
) -> #(State, List(Effect)) {
  case dict.get(cast.restrictions, source) {
    Error(Nil) -> #(cast, [])
    Ok(held) -> #(
      State(..cast, restrictions: dict.delete(cast.restrictions, source)),
      restrictions_ended(held: [#(source, held)], cast_id: source.cast_id),
    )
  }
}

/// 0x880 to the caster and to the audience that was told the state, for each state the
/// cast `cast_id` held, in effect id order (`opcode.0x880`).
pub fn restrictions_ended(
  held held: List(#(unit_properties.Source, HeldRestriction)),
  cast_id cast_id: Int,
) -> List(Effect) {
  held
  |> list.sort(fn(first, second) {
    int.compare({ first.0 }.effect_id.value, { second.0 }.effect_id.value)
  })
  |> list.flat_map(fn(entry) {
    let restriction = entry.1
    [
      Send(frame: cast_frame.control_ended_frame(
        unit_id: cast_state.caster_of(cast_id:),
        state: restriction.state,
        cast_id:,
        instance_id: restriction.instance_id,
      )),
      ..list.map(map.sorted_connections(restriction.audience), fn(viewer) {
        Tell(
          to: viewer,
          news: client_connection.CrowdControlEnded(
            state: restriction.state,
            cast_id:,
            instance_id: restriction.instance_id,
          ),
        )
      })
    ]
  })
}

/// What the row's effect type is called in a log line.
pub fn modifier_kind_named(row row: spell_plan.PropertyModifier) -> String {
  case row.armor, row.change {
    Some(..), _ -> "ModifyInterruptArmor"
    None, spell_plan.AbsorbChange(..) -> "Absorption"
    None, spell_plan.LookChange(..) -> "DisguiseOutfit"
    None, spell_plan.PropertyChange(..) | None, spell_plan.StruckChange(..) ->
      "UnitPropertyModifier or UnitPropertyConversion"
  }
}

/// Whether a cooldown row is kept for the cooldowns that start after it takes effect:
/// its lifetime (delay plus durationTime, the larger of the two for a spell with the
/// record flag 0x10000000) ends after its start, or never ends (flags bit 2). Any other
/// row acts once at its start (`0x14046b7f0`, `opcode.0x7f4.effect_time`). Every row
/// aimed at the caster gives its node the lifetime, kept or not.
pub fn cooldown_kept(
  row row: spell_plan.CooldownModifier,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
) -> Bool {
  row.row.until_removed
  || lasting.lifetime_of(row: row.row, longer_of_delay_and_duration:)
  > row.row.delay_ms
}

/// The crowd-control states the units of a go took, each with its unit, in the order
/// of the units.
pub fn controls_landed(
  struck struck: List(Struck),
) -> List(#(strike_tell.ControlLanded, Int)) {
  list.flat_map(struck, fn(one) {
    case one {
      Hit(unit_id:, controls:, ..) | Immune(unit_id:, controls:, ..) ->
        list.map(controls, fn(control) { #(control, unit_id) })
      Deflected(..) -> []
    }
  })
}

/// The property modifiers a go applies, each armed from this go: the modifier of an
/// earlier go of the cast is armed again, its timers cancelled and started anew; a row
/// with no delay starts in this step, any other on a timer of its delay, and one that
/// does not last until removed ends on a timer after its delay and duration.
pub fn modifiers_armed(
  cast cast: State,
  cast_id cast_id: Int,
  caster caster: Caster,
  aimed aimed: Aimed,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  list.fold(aimed.reached, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    case entry.effect.kind {
      spell_plan.ModifierEffect(modifier: row) -> {
        let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
        let #(cast, more) = case row.change {
          spell_plan.StruckChange(modifier:, ..) ->
            creature_modifier_armed(
              cast:,
              cast_id:,
              row:,
              modifier:,
              unit_id: entry.unit_id,
              struck:,
            )
          spell_plan.PropertyChange(modifier:) ->
            caster_modifier_armed(
              cast:,
              row:,
              source:,
              change: Property(modifier:),
            )
          spell_plan.LookChange(disguise:) ->
            caster_modifier_armed(cast:, row:, source:, change: Look(disguise:))
          spell_plan.AbsorbChange(absorption:) ->
            // An absorb's pool is worked out at the go from the caster as it stood before
            // the go's own effects, as a shield heal's amount is (`cast_heal.healed_on`).
            caster_modifier_armed(
              cast:,
              row:,
              source:,
              change: Absorb(
                amount: damage.amount_on_caster(
                  formula: absorption.formula,
                  caster: cast_heal.on_caster_of(caster:),
                ),
                mask: absorption.mask,
              ),
            )
        }
        #(cast, list.append(effects, more))
      }
      spell_plan.ProxyEffect(..)
      | spell_plan.GainEffect(..)
      | spell_plan.LastingEffect(..)
      | spell_plan.RemoveEffect(..)
      | spell_plan.ForcedMoveEffect(..)
      | spell_plan.StruckMoveEffect(..)
      | spell_plan.CooldownEffect(..)
      | spell_plan.StealthEffect(..)
      | spell_plan.RemoveStealthEffect(..)
      | spell_plan.ProcEffect(..)
      | spell_plan.HealEffect(..)
      | spell_plan.ControlEffect(..)
      | spell_plan.DespawnEffect(..)
      | spell_plan.UnitStateEffect(..) -> so_far
    }
  })
}

/// A property modifier on a creature the go struck, armed from this go: the modifier
/// of an earlier go on the same creature is armed again; a row with no delay starts in
/// this step and any other on a timer of its delay. It has no timer of its end: it ends
/// with the cast's node on the creature (`creature_modifiers_ended`).
fn creature_modifier_armed(
  cast cast: State,
  cast_id cast_id: Int,
  row row: spell_plan.PropertyModifier,
  modifier modifier: unit_properties.Modifier,
  unit_id unit_id: Int,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  case cast_gate.creature_hit(struck:, unit_id:) {
    Error(Nil) -> #(cast, [])
    Ok(#(life, struck_at_ms)) -> {
      let on =
        OnCreature(
          unit_id:,
          life:,
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
        )
      let #(cast, cancels) = target_start_cancelled(cast:, on:)
      case row.row.delay_ms > 0 {
        True -> {
          let #(cast, _, start) =
            cast_state.armed(
              cast:,
              due: TargetModifierStart(on:, modifier:, struck_at_ms:),
              after_ms: row.row.delay_ms,
            )
          #(cast, list.append(cancels, [start]))
        }
        False -> {
          let #(cast, starting) =
            target_modifier_started(cast:, on:, modifier:, struck_at_ms:)
          #(cast, list.append(cancels, starting))
        }
      }
    }
  }
}

/// The creatures a go throws: each struck move among the effects the go `reached` (a struck
/// move of the phase whose caster gates passed with a creature its aim names that the round
/// `Hit` and that passes its target gate, `cast.aimed_at`), in the row then the unit order of `cast_gate.units_aimed_at`. A row with no delay tells the creature
/// `ForcedMoveStarts` in this step; any other arms a `ForcedMoveStart` timer for the go
/// plus its delay; each go's throw is its own, so a later go of the cast leaves an
/// earlier go's waiting throw to start. A unit that is not a `HitCreature` of the
/// round is not thrown (a deflected one included, as for a property modifier), and neither
/// is the caster or another player (a move of another player is issue 570).
pub fn struck_moves_armed(
  cast cast: State,
  cast_id cast_id: Int,
  reached reached: List(Reached),
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  list.fold(reached, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    case entry.effect.kind {
      spell_plan.StruckMoveEffect(struck_move: row) -> {
        let #(cast, more) =
          struck_move_armed(
            cast:,
            cast_id:,
            row:,
            unit_id: entry.unit_id,
            struck:,
          )
        #(cast, list.append(effects, more))
      }
      spell_plan.ProxyEffect(..)
      | spell_plan.GainEffect(..)
      | spell_plan.LastingEffect(..)
      | spell_plan.RemoveEffect(..)
      | spell_plan.ModifierEffect(..)
      | spell_plan.ForcedMoveEffect(..)
      | spell_plan.CooldownEffect(..)
      | spell_plan.StealthEffect(..)
      | spell_plan.RemoveStealthEffect(..)
      | spell_plan.ProcEffect(..)
      | spell_plan.HealEffect(..)
      | spell_plan.ControlEffect(..)
      | spell_plan.DespawnEffect(..)
      | spell_plan.UnitStateEffect(..) -> so_far
    }
  })
}

/// The creatures a go removes: each despawn among the effects the go `reached` (a DespawnUnit
/// row of the phase whose caster gates passed, with a creature its aim names that the round
/// `Hit` and that passes its target gate, `cast.aimed_at`), in the row then the unit order of
/// `cast_gate.units_aimed_at`, each told `CreatureDespawns` in this step, whatever its delay:
/// the creature owns the delay (genesis_prime/world_map/creature `Despawn`), so no timer of
/// the cast is armed and the caster's leaving or dying changes nothing. The delay runs from
/// `went_at_ms`, the go's own time, not from the opening of the strike round, which comes
/// earlier by up to the round's deadline. The effects come after the go's frames, beside
/// the throws'.
///
/// A unit that is not a `HitCreature` of the round is not removed (a deflected one included,
/// as it is not thrown), and neither is the caster or another player. Both are server
/// guesses: the client's tables say what a DespawnUnit row is aimed at but not what a
/// deflected strike or a player does with it, so a deflected creature stays and no player
/// is removed.
///
/// ```
/// cast.went: Send(go 0x7f4), Tell(audience, CastWent)
///   for each despawn row reached on a unit the round Hit as a creature (HitCreature):
///     CreatureDespawns(unit, life, struck_at_ms = the round's, went_at_ms = go time, delay_ms)
///   the connection tells the creature TellDespawn(delay_ms, struck_at_ms, went_at_ms)
///     ─▶ creature.Despawn
/// ```
///
/// | If | Then |
/// |---|---|
/// | the creature never answers by the round's deadline, or refuses | the unit is left out of the round, so it is not `Hit`: no tell |
/// | the go is cancelled during the round | `went` finds no live cast and writes and tells nothing: no tell |
/// | the caster apply prerequisite or the target gate fails | the row is not in `reached`: no tell |
/// | the row aims at the caster alone, or a player stands in its area | units are creatures only: no tell, and no 0x355 for a player (a server guess) |
/// | the row aims at a static object | the object is not a creature, so it is not selected: no tell |
pub fn despawns_told(
  cast _cast: State,
  reached reached: List(Reached),
  struck struck: List(Struck),
  went_at_ms went_at_ms: Int,
) -> List(Effect) {
  list.flat_map(reached, fn(entry) {
    case spell_plan.as_despawn(entry.effect.kind) {
      Ok(row) ->
        case cast_gate.creature_hit(struck:, unit_id: entry.unit_id) {
          Error(Nil) -> []
          Ok(#(life, struck_at_ms)) -> [
            CreatureDespawns(
              unit_id: entry.unit_id,
              life:,
              struck_at_ms:,
              went_at_ms:,
              delay_ms: row.delay_ms,
            ),
          ]
        }
      Error(Nil) -> []
    }
  })
}

/// The creatures a go holds unit states on: each unit state among the effects the go
/// `reached` (a UnitStateSet row of the phase whose caster gates passed, with a creature its
/// aim names that the round `Hit` and that passes its target gate, `cast.aimed_at`), in the
/// row then the unit order of `cast_gate.units_aimed_at`, grouped by creature: each is told
/// one `CreatureHoldsUnitStates` in this step with its rows in row order, whatever their
/// delays, as `despawns_told` tells a despawn: the creature owns the end of each state
/// (genesis_prime/world_map/creature_unit_state), so no timer of the cast is armed and the
/// caster's leaving or dying changes nothing. The delay runs from `went_at_ms`, the go's own
/// time. The effects come after the go's frames, beside the despawns'.
///
/// A unit that is not a `HitCreature` of the round holds no state (a deflected one included),
/// and neither does the caster or another player. Both are server guesses: the client reads
/// no row of this type.
///
/// ```
/// cast.went: Send(go 0x7f4), Tell(audience, CastWent)
///   for each creature the round Hit (HitCreature) that a unit state row reached:
///     CreatureHoldsUnitStates(unit, life, struck_at_ms = the round's, went_at_ms = go time,
///                             rows = Row(state, delay_ms, duration_ms) in row order)
///   the connection tells the creature TellUnitStates(rows, struck_at_ms, went_at_ms)
///     ─▶ creature.UnitStates
/// ```
///
/// | If | Then |
/// |---|---|
/// | the creature never answers by the round's deadline, or refuses | the unit is left out of the round, so it is not `Hit`: no tell |
/// | the go is cancelled during the round | `went` finds no live cast and writes and tells nothing: no tell |
/// | the caster apply prerequisite or the target gate fails | the row is not in `reached`: no tell |
/// | the row aims at the caster alone, or a player stands in its area | units are creatures only: no tell (the row is left out by the plan for the caster alone) |
/// | the row lasts until removed, or is behind a persistence prerequisite | the plan leaves it out by name: no tell |
/// | two rows of one go reach one creature | one tell with both rows, in row order |
pub fn unit_states_told(
  cast _cast: State,
  reached reached: List(Reached),
  struck struck: List(Struck),
  went_at_ms went_at_ms: Int,
) -> List(Effect) {
  let held =
    list.filter_map(reached, fn(entry) {
      use row <- result.try(spell_plan.as_unit_state(entry.effect.kind))
      use #(life, struck_at_ms) <- result.map(cast_gate.creature_hit(
        struck:,
        unit_id: entry.unit_id,
      ))
      #(entry.unit_id, life, struck_at_ms, row.row)
    })
  list.unique(list.map(held, fn(row) { row.0 }))
  |> list.filter_map(fn(unit_id) {
    let mine = list.filter(held, fn(row) { row.0 == unit_id })
    case mine {
      [#(_, life, struck_at_ms, _), ..] ->
        Ok(CreatureHoldsUnitStates(
          unit_id:,
          life:,
          struck_at_ms:,
          went_at_ms:,
          rows: list.map(mine, fn(row) { row.3 }),
        ))
      [] -> Error(Nil)
    }
  })
}

/// The throw of one row on one unit its aim names: nothing unless the round `Hit` the
/// unit as a creature, then the start its delay makes.
fn struck_move_armed(
  cast cast: State,
  cast_id cast_id: Int,
  row row: spell_plan.StruckMove,
  unit_id unit_id: Int,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  case cast_gate.creature_hit(struck:, unit_id:) {
    Error(Nil) -> #(cast, [])
    Ok(#(life, struck_at_ms)) -> {
      let on =
        OnCreature(
          unit_id:,
          life:,
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
        )
      case row.delay_ms > 0 {
        True -> {
          let #(cast, _, start) =
            cast_state.armed(
              cast:,
              due: ForcedMoveStart(on:, move: row.move, struck_at_ms:),
              after_ms: row.delay_ms,
            )
          #(cast, [start])
        }
        False -> throw_started(cast:, on:, move: row.move, struck_at_ms:)
      }
    }
  }
}

/// The delay of a throw ran out, or it has none: the cast tells the creature `on` names,
/// of the life the go struck, `ForcedMoveStarts`. A node of the cast that ended first has
/// cancelled the timer, so nothing is asked of the node here.
pub fn throw_started(
  cast cast: State,
  on on: OnCreature,
  move move: forced_move.Move,
  struck_at_ms struck_at_ms: Int,
) -> #(State, List(Effect)) {
  #(cast, [
    ForcedMoveStarts(unit_id: on.unit_id, life: on.life, struck_at_ms:, move:),
  ])
}

/// The start timer of the modifier `on` names cancelled, whichever go armed it.
fn target_start_cancelled(
  cast cast: State,
  on on: OnCreature,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case target_start_of(due:) {
      Ok(waiting) ->
        waiting.unit_id == on.unit_id && waiting.source == on.source
      Error(Nil) -> False
    }
  })
}

/// The modifier or throw on a creature a timer waits to start, none for any other timer.
fn target_start_of(due due: Due) -> Result(OnCreature, Nil) {
  case due {
    TargetModifierStart(on:, ..) | ForcedMoveStart(on:, ..) -> Ok(on)
    Go(..)
    | Finish(..)
    | StartChild(..)
    | NodesEnd(..)
    | StateEnd(..)
    | ModifierStart(..)
    | ModifierEnd(..)
    | RestrictionEnd(..)
    | CooldownModifierStarts(..)
    | CooldownModifierEnds(..)
    | ProcDue(..)
    | StartHeld
    | RepeatHeld
    | WindowEnd(..)
    | ChargeLevel(..)
    | Tick(..) -> Error(Nil)
  }
}

/// A property modifier on the caster, armed from this go: the modifier of an earlier
/// go of the cast is armed again, its timers cancelled and started anew; a row with no
/// delay starts in this step, any other on a timer of its delay, and one that does not
/// last until removed ends on a timer after its delay and duration.
fn caster_modifier_armed(
  cast cast: State,
  row row: spell_plan.PropertyModifier,
  source source: unit_properties.Source,
  change change: CasterChange,
) -> #(State, List(Effect)) {
  {
    let #(cast, cancels) = cast_state.cancel_source_timers(cast:, source:)
    let #(cast, starting) = case row.row.delay_ms > 0 {
      True -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: ModifierStart(source:, change:),
            after_ms: row.row.delay_ms,
          )
        #(cast, [start])
      }
      False -> #(cast, [CasterChangeStarts(source:, change:)])
    }
    let #(cast, ending) = case row.row.until_removed {
      True -> #(cast, [])
      False -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: ModifierEnd(source:),
            after_ms: row.row.delay_ms + row.row.duration_ms,
          )
        #(cast, [start])
      }
    }
    #(cast, list.flatten([cancels, starting, ending]))
  }
}

/// The modifier rows of a spell that change the caster: the rows aimed at struck units
/// are the creature's (`creature_modifiers_ended`).
pub fn caster_rows(spell spell: Spell) -> List(spell_plan.PropertyModifier) {
  spell_plan.payloads(spell:, as_kind: spell_plan.as_modifier)
  |> list.filter(fn(row) {
    case row.change {
      spell_plan.StruckChange(..) -> False
      spell_plan.PropertyChange(..)
      | spell_plan.LookChange(..)
      | spell_plan.AbsorbChange(..) -> True
    }
  })
}
