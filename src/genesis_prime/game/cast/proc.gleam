//// The procs and passives a cast holds, and the breaking of stealth.

import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/state.{
  type Aimed, type Applied, type Aside, type Caster, type Due, type Effect,
  type Holder, type Live, type State, Absorb, Activated, Aside, CancelTimer,
  CasterChangeEnding, CasterChangeEnds, CasterChangeStarts, ChargeLevel,
  CooldownEnding, CooldownModifierEnds, CooldownModifierStarts, Finish,
  ForcedMoveStart, ForcedMoveStarts, Gain, Go, Heal, HeldProc, Log, Look,
  ModifierEnd, ModifierStart, NodesEnd, Pay, ProcDue, Property, RepeatHeld,
  RestrictionEnd, Send, ShortcutCast, StartChild, StartHeld, StartTimer, State,
  StateEnd, StealthChanged, Strike, TargetChangeEnds, TargetChangeStarts,
  TargetModifierStart, Tell, Tick, TickStrike, WindowEnd,
} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/cooldown
import genesis_prime/game/hit
import genesis_prime/game/lasting
import genesis_prime/game/proc
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/unit_properties
import genesis_prime/message/combat_result
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{type Spell4Id}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The events of the heals an input's effects start on the caster: for each `Heal` change
/// in order, a `LandsHeal` and then a `ReceivesHeal`, since the caster is the one who
/// heals and the one healed (a heal aimed at another unit starts no change on the caster
/// and raises neither). Two readings are guesses: a heal that moves nothing is one as well,
/// and a heal of the shields or of any other vital counts as a heal as a health heal
/// does (the client reads no Proc row to say what a heal is,
/// `Spell4Effects.effectType.14.dataBits00`). The event's spell is the spell of the cast
/// whose row healed, as `after` holds it or, for a cast the input ended, `before`.
/// `LandsCriticalHeal` is never raised: no heal is rolled a critical yet, and issue 830
/// closes that gap.
pub fn heals_landed(
  before before: State,
  after after: State,
  effects effects: List(Effect),
) -> List(proc.Event) {
  list.flat_map(effects, fn(effect) {
    case effect {
      CasterChangeStarts(source:, change: Heal(..)) -> {
        let spell =
          option.map(
            option.from_result(
              result.lazy_or(
                cast_state.holder_of(cast: after, cast_id: source.cast_id),
                fn() {
                  cast_state.holder_of(cast: before, cast_id: source.cast_id)
                },
              ),
            ),
            fn(holder) { event_spell(spell: holder.spell) },
          )
        [
          proc.Event(trigger: spell_plan.LandsHeal, other_unit: None, spell:),
          proc.Event(trigger: spell_plan.ReceivesHeal, other_unit: None, spell:),
        ]
      }
      CasterChangeStarts(change: Property(..), ..)
      | CasterChangeStarts(change: Absorb(..), ..)
      | CasterChangeStarts(change: Look(..), ..) -> []
      Send(..)
      | Tell(..)
      | StartTimer(..)
      | CancelTimer(..)
      | Log(..)
      | Strike(..)
      | TickStrike(..)
      | Pay(..)
      | Gain(..)
      | CasterChangeEnds(..)
      | TargetChangeStarts(..)
      | TargetChangeEnds(..)
      | ForcedMoveStarts(..)
      | Activated(..)
      | ShortcutCast(..)
      | StealthChanged(..) -> []
    }
  })
}

/// The spell of an event as a proc's filter reads it.
pub fn event_spell(spell spell: Spell) -> proc.EventSpell {
  proc.EventSpell(
    spell4_id: spell.spell4_id,
    groups: spell.groups,
    school: spell.school,
  )
}

/// The triggers one damage description of a strike on a creature raises.
pub fn hit_triggers(
  spell spell: Spell,
  description description: hit.Description,
) -> List(spell_plan.Trigger) {
  let critical = description.damage.combat_result == combat_result.Critical
  list.flatten([
    [spell_plan.LandsHit],
    case spell.school {
      1 -> [spell_plan.LandsMeleeHit]
      _ -> []
    },
    case critical {
      True -> [spell_plan.LandsCritical, spell_plan.LandsFinisherCritical]
      False -> []
    },
    case description.damage.killed != 0 {
      True -> [spell_plan.Kills]
      False -> []
    },
  ])
}

/// Whether an input raised events the held procs have not been matched against yet.
pub fn has_pending(cast cast: State) -> Bool {
  cast.pending != []
}

/// The words and the gate rolls the connection draws before the pending events are matched
/// (`procs_fire`): for each pending event, each held proc of its trigger takes what
/// `proc.draws_needed` gives, whether or not an earlier check stops it, so the count is
/// exact. A state with nothing pending needs none.
pub fn proc_draws_needed(cast cast: State) -> #(Int, Int) {
  list.fold(cast.pending, #(0, 0), fn(total, event) {
    list.fold(dict.values(cast.procs), total, fn(total, held) {
      case held.row.trigger == event.trigger {
        True -> {
          let #(words, rolls) = proc.draws_needed(row: held.row)
          #(total.0 + words, total.1 + rolls)
        }
        False -> total
      }
    })
  })
}

/// The units the pending events concern besides the caster, which the event gates read:
/// the connection takes their poses, checklist indexes and kinds from its picture of the
/// caster's world for `procs_fire`.
pub fn pending_units(cast cast: State) -> List(Int) {
  list.filter_map(cast.pending, fn(event) {
    option.to_result(event.other_unit, Nil)
  })
  |> list.unique
}

/// The debug line that says a proc's spell is not cast because its caster condition refuses a
/// caster of the life the caster has, or none.
pub fn proc_refusal(
  caster caster: Caster,
  row row: spell_plan.ProcRow,
  holder holder: Holder,
) -> Option(Effect) {
  case spell_plan.refused_life(spell: row.spell, dead: caster.dead) {
    None -> None
    Some(_) ->
      Some(Log(
        level: LogDebug,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " of Spell4 "
          <> int.to_string(holder.spell.spell4_id.value)
          <> " does not cast Spell4 "
          <> int.to_string(row.spell.spell4_id.value)
          <> ", whose caster condition refuses a caster that is "
          <> case caster.dead {
          True -> "dead"
          False -> "alive"
        },
      ))
  }
}

/// The Proc rows of a go that applied, each held by the cast `cast_id` from this go on;
/// a row the cast already holds keeps its fires, as a later go of the same cast is the
/// same node.
pub fn procs_held(
  cast cast: State,
  cast_id cast_id: Int,
  applied applied: Applied,
) -> #(State, List(Effect)) {
  let #(never, held) =
    list.partition(applied.procs, fn(row) {
      row.trigger == spell_plan.Died && cast.passive != Some(cast_id)
    })
  let procs =
    list.fold(held, cast.procs, fn(procs, row) {
      let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
      dict.upsert(procs, source, fn(found) {
        case found {
          Some(already) -> already
          None -> HeldProc(row:, fires_ms: [])
        }
      })
    })
  #(
    State(..cast, procs:),
    list.map(never, fn(row) {
      Log(
        level: LogDebug,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " of kind 0 is held by a cast that is not the innate passive, which a death ends before the proc is matched, so it is not held",
      )
    }),
  )
}

/// The cast's nodes after some left: a lingering cast with none left is dropped; any
/// other keeps the nodes it has, with its `NodesEnd` timer started again for them.
pub fn nodes_left(
  cast cast: State,
  cast_id cast_id: Int,
  holder holder: Holder,
  nodes nodes: Dict(Int, lasting.Node),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case holder.lingering && dict.is_empty(nodes) {
    True -> {
      let #(cast, cancels) = cast_tick.cancel_nodes_end(cast:, cast_id:)
      #(
        passive_cleared(
          cast: State(..cast, lingering: dict.delete(cast.lingering, cast_id)),
          cast_id:,
        ),
        cancels,
      )
    }
    False ->
      cast_tick.rearmed(
        cast: cast_tick.with_nodes(cast:, cast_id:, nodes:),
        cast_id:,
        now_ms:,
      )
  }
}

/// A unit the caster's client shows is removed from it (a 0x355 for a unit it was
/// shown): the client destroys that unit's nodes then (`0x1404550d0`), so the
/// unit's nodes are dropped from the live and lingering casts, and nothing is
/// written for them; a lingering cast left with no node sends its finish and is
/// dropped, and one that keeps nodes has its `NodesEnd` timer started again. This
/// bounds the casts that linger by the units in sight, so the caster's cast ids
/// (`mint`) cannot run out. A property modifier a dropped cast node held on a creature
/// ends with it (`TargetChangeEnds`), since nothing else would end it.
pub fn unit_removed(
  cast cast: State,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case due {
        StateEnd(unit_id: waiting, ..) -> waiting == unit_id
        Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | ModifierEnd(..)
        | RestrictionEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | ProcDue(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> False
      }
    })
  list.filter(cast_state.holders(cast:), fn(entry) {
    dict.has_key({ entry.1 }.nodes, unit_id)
  })
  |> list.fold(#(cast, cancels), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(cast_id, holder) = entry
    let nodes = dict.delete(holder.nodes, unit_id)
    let #(cast, ticks) = cast_tick.ticks_dropped(cast:, cast_id:, unit_id:)
    let #(cast, on_creatures) =
      cast_control.creature_modifiers_ended(cast:, cast_id:, unit_ids: [unit_id])
    let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
    let ends = case holder.lingering && dict.is_empty(nodes) {
      True -> cast_tick.finished_effects(cast_id:, audience: holder.audience)
      False -> []
    }
    #(cast, list.flatten([effects, ticks, on_creatures, left, ends]))
  })
}

/// The passive's delayed proc fires dropped with the timers of what a death set aside, and
/// their timers cancelled: the holder is gone, so no cast follows for its hit (a fire the
/// death itself makes is armed after this, by the proc pass).
pub fn proc_fires_dropped(
  aside aside: Option(Aside),
) -> #(Option(Aside), List(Effect)) {
  case aside {
    None -> #(None, [])
    Some(set_aside) -> {
      let #(fires, kept) =
        list.partition(set_aside.timers, fn(entry) {
          case entry.1 {
            ProcDue(..) -> True
            Go(..)
            | Finish(..)
            | NodesEnd(..)
            | Tick(..)
            | ModifierStart(..)
            | ModifierEnd(..)
            | RestrictionEnd(..)
            | CooldownModifierStarts(..)
            | CooldownModifierEnds(..)
            | TargetModifierStart(..)
            | ForcedMoveStart(..)
            | StartChild(..)
            | StateEnd(..)
            | StartHeld
            | RepeatHeld
            | WindowEnd(..)
            | ChargeLevel(..) -> False
          }
        })
      #(
        Some(Aside(..set_aside, timers: kept)),
        list.map(fires, fn(entry) { CancelTimer(timer: entry.0) }),
      )
    }
  }
}

/// The cast without the passive's cast, timers, stealth sources and procs, and what was
/// taken out, when the passive has a cast.
pub fn passive_set_aside(cast cast: State) -> #(State, Option(Aside)) {
  case cast.passive {
    None -> #(cast, None)
    Some(id) -> {
      let live = dict.get(cast.casts, id) |> option.from_result
      let lingering = dict.get(cast.lingering, id) |> option.from_result
      let spell4_id = case live, lingering {
        Some(live), _ -> Some(live.spell.spell4_id)
        None, Some(lingering) -> Some(lingering.spell.spell4_id)
        None, None -> None
      }
      let #(timers, rest) =
        dict.to_list(cast.timers)
        |> list.partition(fn(entry) {
          belongs_to_passive(due: entry.1, id:, spell4_id:)
        })
      let #(stealth, others) =
        cast_tick.split_cast(held: cast.stealth, cast_id: id)
      let #(procs, other_procs) =
        cast_tick.split_cast(held: cast.procs, cast_id: id)
      case live, lingering {
        None, None -> #(cast, None)
        _, _ -> #(
          State(
            ..cast,
            casts: dict.delete(cast.casts, id),
            lingering: dict.delete(cast.lingering, id),
            timers: dict.from_list(rest),
            stealth: others,
            procs: other_procs,
            on_creatures: dict.delete(cast.on_creatures, id),
          ),
          Some(Aside(
            id:,
            live:,
            lingering:,
            timers:,
            stealth:,
            procs:,
            on_creatures: dict.get(cast.on_creatures, id) |> result.unwrap([]),
          )),
        )
      }
    }
  }
}

/// The cast with what `passive_set_aside` took out put back.
pub fn passive_restored(cast cast: State, aside aside: Option(Aside)) -> State {
  case aside {
    None -> cast
    Some(Aside(id:, live:, lingering:, timers:, stealth:, procs:, on_creatures:)) ->
      State(
        ..cast,
        on_creatures: case on_creatures {
          [] -> cast.on_creatures
          [_, ..] -> dict.insert(cast.on_creatures, id, on_creatures)
        },
        casts: case live {
          Some(live) -> dict.insert(cast.casts, id, live)
          None -> cast.casts
        },
        lingering: case lingering {
          Some(lingering) -> dict.insert(cast.lingering, id, lingering)
          None -> cast.lingering
        },
        timers: dict.merge(cast.timers, dict.from_list(timers)),
        stealth: dict.merge(cast.stealth, dict.from_list(stealth)),
        procs: dict.merge(cast.procs, dict.from_list(procs)),
        passive: Some(id),
      )
  }
}

/// Whether a timer belongs to the passive's own tree: one of its cast `id`, a modifier
/// or cooldown effect of that cast, or the start of a child whose root is its spell.
fn belongs_to_passive(
  due due: Due,
  id id: Int,
  spell4_id spell4_id: Option(Spell4Id),
) -> Bool {
  case due {
    Go(cast_id:, ..)
    | Finish(cast_id:)
    | NodesEnd(cast_id:)
    | Tick(cast_id:, ..) -> cast_id == id
    ModifierStart(source:, ..)
    | ModifierEnd(source:)
    | RestrictionEnd(source:)
    | ProcDue(source:, ..)
    | CooldownModifierStarts(source:, ..)
    | CooldownModifierEnds(source:) -> source.cast_id == id
    TargetModifierStart(on:, ..) | ForcedMoveStart(on:, ..) ->
      on.source.cast_id == id
    StartChild(root:, ..) -> Some(root) == spell4_id
    StateEnd(..) | StartHeld | RepeatHeld | WindowEnd(..) | ChargeLevel(..) ->
      False
  }
}

/// Takes the node off the caster of each cast that holds a source damage breaks
/// (`damage_taken`); nothing when the caster holds none.
pub fn broken_by_damage(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let sources =
    dict.filter(cast.stealth, fn(_, breaks) {
      breaks == spell_plan.BrokenByDamage
    })
    |> dict.keys
  stealth_ended(cast:, caster:, sources:, now_ms:)
}

/// The casts that hold the stealth sources taken off the caster, oldest cast first, each
/// as a type 80 removal takes a cast off a unit (`node_off`: 0x811, and the 0x7fe of a
/// lingering cast of a method the client keeps), which drops every source of the cast
/// with its node (`effects_ended`).
pub fn stealth_ended(
  cast cast: State,
  caster caster: Caster,
  sources sources: List(unit_properties.Source),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let removals =
    list.map(sources, fn(source) { source.cast_id })
    |> list.unique
    |> list.sort(int.compare)
    |> list.map(fn(cast_id) {
      lasting.NodeOff(cast_id:, unit_id: caster.unit_id)
    })
  apply_removals(cast:, removals:, now_ms:)
}

/// Each property modifier the caster's casts may still hold, told ended in order: those
/// of the spells of its live and lingering casts, in cast id order, and those whose end
/// a timer waits for, in timer order; each once.
pub fn modifiers_pending(cast cast: State) -> List(Effect) {
  let held =
    list.flat_map(cast_state.holders(cast:), fn(entry) {
      list.map(cast_control.caster_rows(spell: { entry.1 }.spell), fn(row) {
        unit_properties.Source(cast_id: entry.0, effect_id: row.effect_id)
      })
    })
  let waiting =
    cast_state.timers_in_order(cast:)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        ModifierEnd(source:) -> Ok(source)
        ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | ProcDue(..)
        | RestrictionEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | StateEnd(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> Error(Nil)
      }
    })
  list.unique(list.append(held, waiting))
  |> list.map(fn(source) { CasterChangeEnds(source:) })
}

/// The effects of the cast `cast_id` ended when its node on the caster is among the
/// nodes that leave `unit_ids`, whether taken off or ended by time.
pub fn caster_modifiers_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, cast_state.caster_of(cast_id:)),
    return: #(cast, []),
  )
  effects_ended(cast:, cast_id:, spell:)
}

/// The effects of the cast `cast_id` ended, as its node leaves the caster: each source
/// of its spell's rows has its timers cancelled, and its stealth sources are dropped
/// (`stealth_dropped`). A property modifier that lasts until
/// removed or whose start or end a timer waited for is told ended, and a modifier whose
/// own end already fired is not told again. A cooldown effect is taken out of the kept
/// list; the cooldowns it changed stay changed, as on the client.
pub fn effects_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  let endings =
    list.append(
      list.map(cast_control.caster_rows(spell:), fn(row) {
        CasterChangeEnding(
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
          until_removed: row.row.until_removed,
        )
      }),
      list.map(spell.cooldown_modifiers, fn(row) {
        CooldownEnding(source: unit_properties.Source(
          cast_id:,
          effect_id: row.effect_id,
        ))
      }),
    )
  let #(cast, effects) =
    list.fold(endings, #(cast, []), fn(so_far, ending) {
      let #(cast, effects) = so_far
      let held =
        list.any(dict.values(cast.timers), fn(due) {
          cast_state.source_of(due:) == Some(ending.source)
        })
      let #(cast, cancels) =
        cast_state.cancel_source_timers(cast:, source: ending.source)
      case ending {
        CasterChangeEnding(source:, until_removed:) if until_removed || held -> #(
          cast,
          list.flatten([effects, cancels, [CasterChangeEnds(source:)]]),
        )
        CasterChangeEnding(..) -> #(cast, list.append(effects, cancels))
        CooldownEnding(source:) -> #(
          State(..cast, cooldowns: cooldown.drop(book: cast.cooldowns, source:)),
          list.append(effects, cancels),
        )
      }
    })
  let #(cast, heal_cancels) = cast_tick.pending_heals_cancelled(cast:, cast_id:)
  let #(restrictions, others) =
    cast_tick.split_cast(held: cast.restrictions, cast_id:)
  let cast = State(..cast, restrictions: others)
  let #(cast, restriction_cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case due {
        RestrictionEnd(source:) | ProcDue(source:, ..) ->
          source.cast_id == cast_id
        Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | StateEnd(..)
        | ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | ModifierEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> False
      }
    })
  #(
    procs_dropped(cast: stealth_dropped(cast:, cast_id:), cast_id:),
    list.flatten([
      effects,
      heal_cancels,
      restriction_cancels,
      cast_control.restrictions_ended(held: restrictions, cast_id:),
    ]),
  )
}

/// The stealth sources of the cast `cast_id` dropped, as its node leaves the caster: the
/// stealth lasts as long as the node that holds it.
fn stealth_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, stealth: cast_tick.without_cast(held: cast.stealth, cast_id:))
}

/// The Proc rows of the cast `cast_id` dropped, as its node leaves the caster: a proc is
/// held as long as the node that holds it.
fn procs_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, procs: cast_tick.without_cast(held: cast.procs, cast_id:))
}

/// The nodes a go gives, one for each unit a Fluff row aims at or a crowd-control state
/// landed on: count 1 and the longest life of its rows with the effects the cast's node on
/// the unit already holds (`lasting.given`: a later go keeps and re-arms them, as on the
/// client, `opcode.0x7f4.instance_count`), and at least until the time the creature
/// holds each state, which no later go moves; a unit left with no effect that has a life
/// and no state holds no node of the cast.
pub fn nodes_given(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id), cast_tick.nodes_aimed(aimed:) {
    Error(Nil), _ | _, [] -> #(cast, [])
    Ok(live), units -> {
      let given =
        units
        |> list.map(fn(unit_id) {
          #(
            unit_id,
            cast_tick.node_of(
              spell: live.spell,
              held: dict.get(live.nodes, unit_id) |> option.from_result,
              aimed:,
              unit_id:,
              now_ms:,
            ),
          )
        })
      let #(cast, pushed) =
        list.fold(given, #(cast, []), fn(so_far, entry) {
          case entry.1 {
            Ok(node) -> pushed_by(so_far:, cast_id:, live:, node:, now_ms:)
            Error(Nil) -> so_far
          }
        })
      let nodes = case dict.get(cast.casts, cast_id) {
        Ok(current) -> current.nodes
        Error(Nil) -> live.nodes
      }
      let nodes =
        list.fold(given, nodes, fn(nodes, entry) {
          case entry.1 {
            Ok(node) -> dict.insert(nodes, entry.0, node)
            Error(Nil) -> dict.delete(nodes, entry.0)
          }
        })
      #(cast_tick.with_nodes(cast:, cast_id:, nodes:), pushed)
    }
  }
}

/// A node the go gives a unit its cast holds none on yet makes a new cast on that
/// unit, which pushes the caster's oldest casts of its stack off the unit at the cap
/// (Jim's decision, `lasting.pushed_off`); a unit the cast holds a node on already is a
/// later go of the same cast, which pushes nothing.
fn pushed_by(
  so_far so_far: #(State, List(Effect)),
  cast_id cast_id: Int,
  live live: Live,
  node node: lasting.Node,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: dict.has_key(live.nodes, node.unit_id),
    return: so_far,
  )
  let #(cast, effects) = so_far
  let removals =
    lasting.pushed_off(
      holds: list.filter(
        cast_tick.holds_on(cast:, unit_id: node.unit_id),
        fn(hold) { hold.cast_id != cast_id },
      ),
      spell4_id: live.spell.spell4_id,
      stack: live.spell.stack,
      unit_id: node.unit_id,
    )
  let #(cast, more) = apply_removals(cast:, removals:, now_ms:)
  #(cast, list.append(effects, more))
}

/// What a removal does to the casts, in order: a cast that loses its whole node on a
/// unit is written 0x811 and keeps no node there, one that loses a stack is written
/// 0x813 and keeps its node one count lower. A lingering cast left with no node is
/// dropped, and, when its cast method is one the client keeps with no target
/// (Channeled, ChanneledField, Multiphase or 10), ends with its 0x7fe after the 0x811
/// (`opcode.0x811`).
pub fn apply_removals(
  cast cast: State,
  removals removals: List(lasting.Removal),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(removals, #(cast, []), fn(so_far, removal) {
    let #(cast, effects) = so_far
    let #(cast, more) = case removal {
      lasting.NodeOff(cast_id:, unit_id:) ->
        node_off(cast:, cast_id:, unit_id:, now_ms:)
      lasting.StackOff(cast_id:, unit_id:) ->
        cast_tick.stack_off(cast:, cast_id:, unit_id:)
    }
    #(cast, list.append(effects, more))
  })
}

/// A cast loses its whole node on a unit: 0x811 for the unit, with the cast destroyed on
/// the client when it has no node left and its method is not one the client keeps; a
/// lingering cast with none left is dropped, with its 0x7fe after the 0x811 when the
/// client keeps a cast of its method.
fn node_off(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let #(cast, ticks) = cast_tick.ticks_dropped(cast:, cast_id:, unit_id:)
      let nodes = dict.delete(holder.nodes, unit_id)
      let emptied = dict.is_empty(nodes)
      let kept = cast_tick.keeps_without_target(method: holder.spell.method)
      let removed =
        cast_tick.targets_removed_effects(
          cast_id:,
          unit_ids: [unit_id],
          audience: holder.audience,
          destroyed: emptied && !kept,
        )
      let #(cast, modifiers) =
        caster_modifiers_ended(cast:, cast_id:, spell: holder.spell, unit_ids: [
          unit_id,
        ])
      let #(cast, on_creatures) =
        cast_control.creature_modifiers_ended(cast:, cast_id:, unit_ids: [
          unit_id,
        ])
      let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
      let ends = case holder.lingering && emptied && kept {
        True -> cast_tick.finished_effects(cast_id:, audience: holder.audience)
        False -> []
      }
      #(
        cast,
        list.flatten([ticks, removed, modifiers, on_creatures, left, ends]),
      )
    }
  }
}

/// The cast without the innate passive's id when the cast `cast_id` is the passive and
/// has left both `casts` and `lingering`, so that no later cast the caster mints the
/// same id for is taken for the passive.
pub fn passive_cleared(cast cast: State, cast_id cast_id: Int) -> State {
  use <- bool.guard(when: cast.passive != Some(cast_id), return: cast)
  State(..cast, passive: None)
}
