//// The ticks and nodes of a cast, their removals and their ends.
////
//// - **A cast that lingers** is one whose last go has gone while a node of it still
////   has life: every step of its end runs (the current cast cleared, a channel's
////   cooldown, a stage's threshold closed) and only its 0x7fe waits, since the client
////   ends no buff on time (`cast.target_node_end`). A timer of the rule ends the
////   nodes as their time runs out, 0x811 for the units whose node ends and the 0x7fe
////   with the last. A lingering cast holds its id until then. A live cast's nodes end
////   on the same timer, 0x811 for the unit while the cast goes on, and a 0x801 stops a
////   cast the same way: its pending gos are cancelled and it lingers if a node has life
////   left, since a cancel ends no buff.

import genesis_prime/client_connection
import genesis_prime/game/area
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/state.{
  type Aimed, type Caster, type Effect, type GateDecision, type Holder,
  type Paid, type Reached, type State, type StrikeGate, type Struck,
  type TargetVerdict, type TickAsked, type TickKey, type Ticking, type TickingOn,
  type Verdict, Absorb, Accept, CancelTimer, Caster, CasterChangeStarts,
  CasterSide, ChargeLevel, CooldownModifierEnds, CooldownModifierStarts,
  Deflected, Finish, ForcedMoveStart, Go, Heal, Healed, Hit, Immune, Lingering,
  Live, Look, ModifierEnd, ModifierStart, NodesEnd, NotBuilt, PrerequisitesIssue,
  ProcDue, Property, Refuse, RepeatHeld, RestrictionEnd, Send, StartChild,
  StartHeld, Starts, State, StateEnd, TargetChangeEnds, TargetModifierStart,
  Tell, Tick, TickAsked, TickStrike, UnitSide, WindowEnd,
} as cast_state
import genesis_prime/game/class_resource
import genesis_prime/game/cooldown
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Proxy, type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/ticking
import genesis_prime/game/unit_properties
import genesis_prime/message/cast_result
import genesis_prime/message/spell_effect_tick.{
  type SpellEffectTick, SpellEffectTick,
}
import genesis_prime/message/spell_stack_removed.{SpellStackRemoved}
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import genesis_prime/step.{type ConnectionId, type TimerId}
import genesis_prime/table/id.{type Spell4EffectsId}
import genesis_prime/world_map/map
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}

/// The subject of the unit a press named, for the spell's TargetCast: what the caster's
/// live casts hold on it (a live cast whose primary target it is, and the nodes it holds
/// there), and the caster second. The unit is the creature of Creature2 row `creature_id`,
/// the first unit a type 38 condition of the TargetCast compares.
pub fn target_subject_of(
  cast cast: State,
  caster caster: Caster,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  in_combat in_combat: Bool,
  place place: Place,
) -> prerequisite.Subject {
  prerequisite.of_target(
    under: held_by_caster_on(cast:, caster:, unit_id:),
    caster_unit: caster.unit_id,
    in_combat:,
    target: area.pose_of(place:),
    caster: area.pose_of(place: caster.place),
    quests: caster.quests,
    creature_id:,
    checker: caster.checker,
  )
}

/// What the caster's casts hold on the unit `unit_id`: a live cast whose primary target it
/// is, and the nodes the caster's casts hold there, each with the caster as its caster.
fn held_by_caster_on(
  cast cast: State,
  caster caster: Caster,
  unit_id unit_id: Int,
) -> List(lasting.Held) {
  dict.values(cast.casts)
  |> list.filter(fn(live) { live.primary_target == unit_id })
  |> list.map(fn(live) {
    lasting.Held(
      spell4_id: live.spell.spell4_id,
      caster: caster.unit_id,
      count: 0,
      groups: live.spell.groups,
    )
  })
  |> list.append(
    list.map(holds_on(cast:, unit_id:), fn(hold) {
      lasting.Held(
        spell4_id: hold.spell4_id,
        caster: caster.unit_id,
        count: hold.node.count,
        groups: hold.groups,
      )
    }),
  )
}

/// What the spell's caster requirements make of the press: the refusal for the first the
/// caster fails and its waiver does not pass (`0x1403b1780`), none when each is met or
/// waived. A waiver the server cannot read refuses with the requirement's result, as
/// not built (the server's choice, as for a cost in a vital it does not hold).
pub fn requirement_refusal(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
) -> Option(Verdict) {
  list.find_map(spell.requirements, fn(requirement) {
    case cast_cost.meets(requirement:, resources: caster.resources) {
      True -> Error(Nil)
      False ->
        case waiver_verdict(cast:, caster:, spell:) {
          prerequisite.Passes -> Error(Nil)
          prerequisite.Fails ->
            Ok(Refuse(result: cast_result.from_value(requirement.result)))
          prerequisite.NotRead(prerequisite_type:) ->
            Ok(NotBuilt(
              result: cast_result.from_value(requirement.result),
              why: "has a caster requirement whose waiver is a condition of the PrerequisiteType "
                <> int.to_string(prerequisite_type)
                <> ", which the server does not read",
              issue: PrerequisitesIssue,
            ))
        }
    }
  })
  |> option.from_result
}

/// What the spell's waiver makes of a failed requirement: the waiver's prerequisite
/// checked against the caster, and a spell that has none fails (`0x1403b1780`).
fn waiver_verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
) -> prerequisite.Verdict {
  case spell.caster_cast {
    spell_plan.RequirementWaiver(prerequisite: waiver) ->
      prerequisite.check(
        prerequisite: waiver,
        subject: subject_of(cast:, caster:),
      )
    spell_plan.CastGate(..) | spell_plan.NoCasterCast -> prerequisite.Fails
  }
}

/// The press that passed every other check, now against the spell's own cast
/// conditions in the client's order: CasterCast, then TargetCast (`0x1403ace00`). The
/// caster is both units of each check unless the press names a target: the client makes
/// the caster the target of every spell it presses that takes none (the cast module's doc,
/// "The target"), and `target_subject` is the unit a press of an aimed spell names, which
/// TargetCast reads as its first unit. A condition the server cannot read, a type it does
/// not read or a roll (a press draws none), refuses with the check's result as not built.
pub fn cast_conditions(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  paid paid: Paid,
  target_subject target_subject: Option(prerequisite.Subject),
) -> Verdict {
  let caster_gate = case spell.caster_cast {
    spell_plan.CastGate(prerequisite: gate) -> Some(gate)
    spell_plan.RequirementWaiver(..) | spell_plan.NoCasterCast -> None
  }
  use <- bool.guard(
    when: option.is_none(caster_gate) && option.is_none(spell.target_cast),
    return: Accept(paid:),
  )
  let subject = subject_of(cast:, caster:)
  case
    cast_cost.condition_verdict(
      gate: caster_gate,
      subject:,
      result: cast_result.PrereqCasterCast,
    )
  {
    Some(refusal) -> refusal
    None ->
      case
        cast_cost.condition_verdict(
          gate: spell.target_cast,
          subject: option.unwrap(target_subject, subject),
          result: cast_result.PrereqTargetCast,
        )
      {
        Some(refusal) -> refusal
        None -> Accept(paid:)
      }
  }
}

/// The nodes of the cast set, wherever the cast is.
pub fn with_nodes(
  cast cast: State,
  cast_id cast_id: Int,
  nodes nodes: Dict(Int, lasting.Node),
) -> State {
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ ->
      State(
        ..cast,
        casts: dict.insert(cast.casts, cast_id, Live(..live, nodes:)),
      )
    Error(Nil), Ok(lingering) ->
      State(
        ..cast,
        lingering: dict.insert(
          cast.lingering,
          cast_id,
          Lingering(..lingering, nodes:),
        ),
      )
    Error(Nil), Error(Nil) -> cast
  }
}

/// The nodes whose life is over at the time, and the others, each with its unit id. A
/// node whose unit has a tick round open is kept past its end until the round closes
/// (`cast.ticked`), so its 0x811 or the cast's 0x7fe follows the tick's 0x7f8.
pub fn ended_and_kept(
  nodes nodes: Dict(Int, lasting.Node),
  ticking ticking: Dict(TickKey, Ticking),
  now_ms now_ms: Int,
) -> #(List(#(Int, lasting.Node)), List(#(Int, lasting.Node))) {
  dict.to_list(nodes)
  |> list.partition(fn(entry) {
    life_over(life: { entry.1 }.life, now_ms:)
    && !tick_round_open(ticking:, unit_id: entry.0)
  })
}

/// Whether a tick round of the cast on the unit is open.
fn tick_round_open(
  ticking ticking: Dict(TickKey, Ticking),
  unit_id unit_id: Int,
) -> Bool {
  dict.fold(ticking, False, fn(open, key, row) {
    open
    || {
      cast_state.key_unit(key:) == unit_id && cast_state.ticking_open(row:) > 0
    }
  })
}

/// The periodic rows of the cast set, wherever the cast is.
pub fn with_ticking(
  cast cast: State,
  cast_id cast_id: Int,
  ticking ticking: Dict(TickKey, Ticking),
) -> State {
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ ->
      State(
        ..cast,
        casts: dict.insert(cast.casts, cast_id, Live(..live, ticking:)),
      )
    Error(Nil), Ok(lingering) ->
      State(
        ..cast,
        lingering: dict.insert(
          cast.lingering,
          cast_id,
          Lingering(..lingering, ticking:),
        ),
      )
    Error(Nil), Error(Nil) -> cast
  }
}

/// The `Tick` timers of the cast whose row on its unit `matching` accepts, cancelled.
fn tick_timers_cancelled(
  cast cast: State,
  cast_id cast_id: Int,
  matching matching: fn(TickKey) -> Bool,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      Tick(cast_id: waiting, effect_id:, unit_id:, ..) ->
        waiting == cast_id
        && matching(cast_state.tick_key(unit_id:, effect_id:))
      Go(..)
      | Finish(..)
      | StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
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
      | ChargeLevel(..) -> False
    }
  })
}

/// The ticks of the cast `cast_id` due at the time fire, each due tick of each row, a
/// connection fallen behind included, earliest first and at one time in unit and row id
/// order: a damage row asks its unit for the tick (`TickStrike`), whose 0x7f8 waits for
/// `cast.ticked`; a heal row writes its 0x7f8 to the caster, tells the audience
/// (genesis_prime/client_connection `CastTicked`) and heals the caster
/// (`CasterChangeStarts`), reading the vitals the heal ticks before it in the step left,
/// and heals nothing on a dead caster. Then each row that fired has its next tick armed,
/// or none after its last (genesis_prime/game/ticking `next_tick`). Any tick timer of the
/// cast fires every tick due with it, so ticks due together keep that order whichever
/// timer fires first.
pub fn ticks_due(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let #(cast, landed, fired) =
    due_ticks_landed(
      cast:,
      caster:,
      now_ms:,
      cast_id:,
      landed: [],
      fired: set.new(),
    )
  let #(cast, armed) =
    set.to_list(fired)
    |> list.sort(by_tick_key)
    |> list.fold(#(cast, []), fn(so_far, key) {
      let #(cast, effects) = so_far
      let #(cast, more) = next_tick_armed(cast:, now_ms:, cast_id:, key:)
      #(cast, list.append(effects, more))
    })
  #(cast, list.append(landed, armed))
}

/// The earliest due tick of the cast fires, again until none is due, with the caster's
/// vitals as each heal tick leaves them; the rows that fired are gathered.
fn due_ticks_landed(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  landed landed: List(Effect),
  fired fired: Set(TickKey),
) -> #(State, List(Effect), Set(TickKey)) {
  let due = case cast_state.holder_of(cast:, cast_id:) {
    Ok(holder) ->
      earliest_due(ticking: holder.ticking, now_ms:)
      |> result.map(fn(due) { #(holder, due) })
    Error(Nil) -> Error(Nil)
  }
  case due {
    Error(Nil) -> #(cast, landed, fired)
    Ok(#(holder, #(key, tick))) -> {
      let #(cast, caster, more) =
        tick_landed(cast:, caster:, cast_id:, holder:, key:, tick:)
      due_ticks_landed(
        cast:,
        caster:,
        now_ms:,
        cast_id:,
        landed: list.append(landed, more),
        fired: set.insert(fired, key),
      )
    }
  }
}

/// The row and the tick due earliest at the time, at one time the lowest unit id and
/// then row id; none when no tick is due.
fn earliest_due(
  ticking rows: Dict(TickKey, Ticking),
  now_ms now_ms: Int,
) -> Result(#(TickKey, Int), Nil) {
  dict.to_list(rows)
  |> list.filter_map(fn(entry) {
    let #(key, row) = entry
    use next <- result.try(option.to_result(
      ticking.next_tick(
        schedule: cast_state.ticking_schedule(row:),
        tick: cast_state.ticking_tick(row:),
      ),
      Nil,
    ))
    let at_ms =
      ticking.tick_at_ms(
        schedule: cast_state.ticking_schedule(row:),
        from_ms: cast_state.ticking_from_ms(row:),
        tick: next,
      )
    case at_ms <= now_ms {
      True -> Ok(#(at_ms, key, next))
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(first, second) {
    int.compare(first.0, second.0)
    |> order.break_tie(by_tick_key(first.1, second.1))
  })
  |> list.first
  |> result.map(fn(due) { #(due.1, due.2) })
}

/// Rows in unit id order, then row id order.
fn by_tick_key(first: TickKey, second: TickKey) -> order.Order {
  int.compare(cast_state.key_unit(key: first), cast_state.key_unit(key: second))
  |> order.break_tie(int.compare(
    cast_state.key_effect(key: first).value,
    cast_state.key_effect(key: second).value,
  ))
}

/// Tick `tick` of the row `key` of the cast fires (`ticks_due`), with the caster as the
/// heal ticks before it left it.
fn tick_landed(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  holder holder: Holder,
  key key: TickKey,
  tick tick: Int,
) -> #(State, Caster, List(Effect)) {
  case dict.get(holder.ticking, key) {
    Error(Nil) -> #(cast, caster, [])
    Ok(row) -> {
      let #(row, caster, landed) =
        cast_state.on_tick_kind(
          kind: cast_state.ticking_kind(row:),
          damage: fn(blow) {
            #(cast_state.round_opened(row:, tick:), caster, [
              TickStrike(asked: TickAsked(
                cast_id:,
                spell4_id: holder.spell.spell4_id,
                effect_id: cast_state.key_effect(key:),
                unit_id: cast_state.key_unit(key:),
                life: cast_state.ticking_life(row:),
                go: cast_state.ticking_go(row:),
                tick:,
                blow:,
              )),
            ])
          },
          heal: fn(vital, formula) {
            let #(caster, healed) =
              healed_by_tick(
                caster:,
                cast_id:,
                effect_id: cast_state.key_effect(key:),
                audience: holder.audience,
                vital:,
                formula:,
              )
            #(cast_state.with_tick(row:, tick:), caster, healed)
          },
        )
      #(
        with_ticking(
          cast:,
          cast_id:,
          ticking: dict.insert(holder.ticking, key, row),
        ),
        caster,
        landed,
      )
    }
  }
}

/// The row `key`'s tick timer cancelled and its next tick armed, none after its last.
fn next_tick_armed(
  cast cast: State,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  key key: TickKey,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    tick_timers_cancelled(cast:, cast_id:, matching: fn(other) { other == key })
  let next = case cast_state.holder_of(cast:, cast_id:) {
    Ok(holder) ->
      case dict.get(holder.ticking, key) {
        Ok(row) ->
          ticking.next_tick(
            schedule: cast_state.ticking_schedule(row:),
            tick: cast_state.ticking_tick(row:),
          )
          |> option.map(fn(after) { #(row, after) })
        Error(Nil) -> None
      }
    Error(Nil) -> None
  }
  case next {
    None -> #(cast, cancels)
    Some(#(row, after)) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: Tick(
            cast_id:,
            effect_id: cast_state.key_effect(key:),
            unit_id: cast_state.key_unit(key:),
            tick: after,
          ),
          after_ms: int.max(
            0,
            ticking.tick_at_ms(
              schedule: cast_state.ticking_schedule(row:),
              from_ms: cast_state.ticking_from_ms(row:),
              tick: after,
            )
              - now_ms,
          ),
        )
      #(cast, list.append(cancels, [start]))
    }
  }
}

/// A heal tick on the caster: its 0x7f8 with the heal's description, told to the
/// audience, then the heal, the formula read for the caster as it is at the tick and
/// split by the room its vitals have then (`cast_heal.split_of`); the caster comes back with the
/// heal's split added to its vitals, for a heal tick due with it. A dead caster is healed
/// nothing and shown nothing.
fn healed_by_tick(
  caster caster: Caster,
  cast_id cast_id: Int,
  effect_id effect_id: Spell4EffectsId,
  audience audience: Set(ConnectionId),
  vital vital: effect_kind.Vital,
  formula formula: damage.Formula,
) -> #(Caster, List(Effect)) {
  use <- bool.guard(when: caster.dead, return: #(caster, []))
  let amount =
    damage.amount_on_caster(formula:, caster: cast_heal.on_caster_of(caster:))
  let split = cast_heal.split_of(vital:, amount:, caster:)
  let healed = Healed(effect_id:, vital:, delay_ms: 0, amount:, split:)
  #(
    Caster(
      ..caster,
      vitals: damage.Vitals(
        ..caster.vitals,
        health: caster.vitals.health + split.health,
        shield: caster.vitals.shield + split.shield,
      ),
    ),
    list.flatten([
      tick_effects(
        tick: SpellEffectTick(
          cast_id:,
          spell4_effects_id: effect_id.value,
          unit_id: caster.unit_id,
          descriptions: [cast_heal.heal_description(healed:)],
        ),
        audience:,
      ),
      [
        CasterChangeStarts(
          source: unit_properties.Source(cast_id:, effect_id:),
          change: Heal(vital:, amount:),
        ),
      ],
    ]),
  )
}

/// 0x7f8 to the caster and told to the audience.
fn tick_effects(
  tick tick: SpellEffectTick,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  [
    Send(frame: cast_frame.ticked_frame(tick:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastTicked(tick:))
    })
  ]
}

/// What a closed tick round of the row does: a hit writes its 0x7f8 to the audience,
/// whichever go's schedule asked it, since the unit took the damage and its health news
/// goes out, and one that kills drops the unit's ticks; a deflect or an immunity writes
/// nothing; no answer for a round of the row's current schedule (the unit is gone, or
/// refused the tick for a life it no longer has) drops the unit's ticks and ends its node
/// now (`node_ended_now`), so the cast's 0x811 or 0x7fe goes when the round closes. No
/// answer for a round of an earlier schedule does nothing: the later go's own ticks ask
/// the unit again.
pub fn tick_outcome(
  cast cast: State,
  audience audience: Set(ConnectionId),
  row row: Ticking,
  asked asked: TickAsked,
  struck struck: Option(Struck),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let cast_id = asked.cast_id
  case struck, cast_state.ticking_go(row:) == asked.go {
    Some(Hit(descriptions:, ..)), _ -> {
      let written =
        tick_effects(
          tick: SpellEffectTick(
            cast_id:,
            spell4_effects_id: asked.effect_id.value,
            unit_id: asked.unit_id,
            descriptions: list.map(descriptions, fn(description) {
              description.damage
            }),
          ),
          audience:,
        )
      let killed =
        list.any(descriptions, fn(description) {
          description.damage.killed != 0
        })
      use <- bool.guard(when: !killed, return: #(cast, written))
      let #(cast, dropped) =
        ticks_dropped(cast:, cast_id:, unit_id: asked.unit_id)
      #(cast, list.append(written, dropped))
    }
    Some(Deflected(..)), _ | Some(Immune(..)), _ | None, False -> #(cast, [])
    None, True -> {
      let #(cast, dropped) =
        ticks_dropped(cast:, cast_id:, unit_id: asked.unit_id)
      #(
        node_ended_now(cast:, cast_id:, unit_id: asked.unit_id, now_ms:),
        dropped,
      )
    }
  }
}

/// The cast's node on the unit ends at the time, so the node end that follows
/// (`cast.nodes_ended`) drops it with its frames.
fn node_ended_now(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> State {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> cast
    Ok(holder) ->
      case dict.get(holder.nodes, unit_id) {
        Error(Nil) -> cast
        Ok(node) ->
          with_nodes(
            cast:,
            cast_id:,
            nodes: dict.insert(
              holder.nodes,
              unit_id,
              lasting.Node(..node, life: lasting.EndsAt(ms: now_ms)),
            ),
          )
      }
  }
}

/// A go arms the first tick of each periodic row on each unit it reached (`TickingOn`),
/// counted from the go's monotonic time `from_ms`; `go` is which go of the cast it is. A
/// row already ticking on the unit for this cast is armed again from this go, as the
/// client sets its node again, and its earlier schedule's tick timer is cancelled; a
/// round of that schedule still open writes nothing when it closes (`cast.ticked`).
pub fn ticks_armed(
  cast cast: State,
  cast_id cast_id: Int,
  go go: Int,
  from_ms from_ms: Int,
  rows rows: List(TickingOn),
) -> #(State, List(Effect)) {
  list.fold(rows, #(cast, []), fn(so_far, on) {
    let #(cast, effects) = so_far
    let key = cast_state.tick_key(unit_id: on.unit_id, effect_id: on.effect_id)
    let #(cast, cancels) =
      tick_timers_cancelled(cast:, cast_id:, matching: fn(other) {
        other == key
      })
    case cast_state.holder_of(cast:, cast_id:) {
      Error(Nil) -> #(cast, list.append(effects, cancels))
      Ok(holder) -> {
        let open = case dict.get(holder.ticking, key) {
          Ok(earlier) -> cast_state.ticking_open(row: earlier)
          Error(Nil) -> 0
        }
        let schedule =
          ticking.within_life(
            schedule: on.schedule,
            longer_of_delay_and_duration: holder.spell.longer_of_delay_and_duration,
          )
        let row =
          cast_state.ticking_started(
            kind: on.kind,
            schedule:,
            go:,
            from_ms:,
            open:,
            life: on.life,
          )
        let cast =
          with_ticking(
            cast:,
            cast_id:,
            ticking: dict.insert(holder.ticking, key, row),
          )
        let #(cast, start) = first_tick_armed(cast:, cast_id:, key:, schedule:)
        #(cast, list.flatten([effects, cancels, start]))
      }
    }
  })
}

/// The timer of the row `key`'s first tick, none when no tick lands within its life.
fn first_tick_armed(
  cast cast: State,
  cast_id cast_id: Int,
  key key: TickKey,
  schedule schedule: ticking.Schedule,
) -> #(State, List(Effect)) {
  case ticking.next_tick(schedule:, tick: 0) {
    None -> #(cast, [])
    Some(first) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: Tick(
            cast_id:,
            effect_id: cast_state.key_effect(key:),
            unit_id: cast_state.key_unit(key:),
            tick: first,
          ),
          after_ms: ticking.tick_at_ms(schedule:, from_ms: 0, tick: first),
        )
      #(cast, [start])
    }
  }
}

/// The ticks of the cast on the unit stop with its node: their timers are cancelled
/// and their rows forgotten. Every path that drops a node calls it: a removal of the
/// unit, a type 80 removal, the stack cap and a node's end; a finish, a persistence
/// end, a death and leaving cancel every tick of the cast.
pub fn ticks_dropped(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    tick_timers_cancelled(cast:, cast_id:, matching: fn(key) {
      cast_state.key_unit(key:) == unit_id
    })
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, cancels)
    Ok(holder) -> #(
      with_ticking(
        cast:,
        cast_id:,
        ticking: dict.filter(holder.ticking, fn(key, _) {
          cast_state.key_unit(key:) != unit_id
        }),
      ),
      cancels,
    )
  }
}

/// The ticks of the cast on each of the units stop (`ticks_dropped`).
pub fn ticks_dropped_on(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  list.fold(unit_ids, #(cast, []), fn(so_far, unit_id) {
    let #(cast, effects) = so_far
    let #(cast, more) = ticks_dropped(cast:, cast_id:, unit_id:)
    #(cast, list.append(effects, more))
  })
}

/// Every tick of the cast stops: a finish or a persistence end ends all its nodes.
pub fn ticks_all_dropped(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    tick_timers_cancelled(cast:, cast_id:, matching: fn(_) { True })
  #(with_ticking(cast:, cast_id:, ticking: dict.new()), cancels)
}

/// What the end of some of a cast's nodes writes: the 0x7fe of a lingering cast left with
/// none, else 0x811 for the units whose node ended, with the cast destroyed on the client
/// when it has no node left and its method is not one the client keeps.
pub fn nodes_ended_frames(
  cast_id cast_id: Int,
  holder holder: Holder,
  ended ended: List(#(Int, lasting.Node)),
  kept kept: List(#(Int, lasting.Node)),
) -> List(Effect) {
  case holder.lingering && kept == [] {
    True -> finished_effects(cast_id:, audience: holder.audience)
    False ->
      targets_removed_effects(
        cast_id:,
        unit_ids: cast_state.sorted_units(ended),
        audience: holder.audience,
        destroyed: kept == []
          && !keeps_without_target(method: holder.spell.method),
      )
  }
}

/// Whether a node's life is over at the time: it ended, or it never had one.
fn life_over(life life: lasting.Life, now_ms now_ms: Int) -> Bool {
  case life {
    lasting.EndsAt(ms:) -> ms <= now_ms
    lasting.NoLife -> True
    lasting.UntilRemoved -> False
  }
}

/// The earliest time a node ends at, none when every node lasts until it is removed
/// or is held by an open tick round on its unit, whose close ends it (`cast.ticked`).
fn earliest_end(
  nodes nodes: Dict(Int, lasting.Node),
  ticking ticking: Dict(TickKey, Ticking),
) -> Option(Int) {
  list.filter_map(dict.to_list(nodes), fn(entry) {
    let #(unit_id, node) = entry
    case node.life, tick_round_open(ticking:, unit_id:) {
      _, True -> Error(Nil)
      lasting.EndsAt(ms:), False -> Ok(ms)
      lasting.NoLife, False | lasting.UntilRemoved, False -> Error(Nil)
    }
  })
  |> list.reduce(int.min)
  |> option.from_result
}

/// The cast's `NodesEnd` timer, started for its earliest ending node; none when no
/// node ends by time.
fn arm_nodes_end(
  cast cast: State,
  cast_id cast_id: Int,
  nodes nodes: Dict(Int, lasting.Node),
  ticking ticking: Dict(TickKey, Ticking),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case earliest_end(nodes:, ticking:) {
    None -> #(cast, [])
    Some(ends_ms) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: NodesEnd(cast_id:),
          after_ms: int.max(0, ends_ms - now_ms),
        )
      #(cast, [start])
    }
  }
}

/// The cast's `NodesEnd` timer cancelled and started again for the nodes it holds
/// now.
pub fn rearmed(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = cancel_nodes_end(cast:, cast_id:)
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, cancels)
    Ok(holder) -> {
      let #(cast, armed) =
        arm_nodes_end(
          cast:,
          cast_id:,
          nodes: holder.nodes,
          ticking: holder.ticking,
          now_ms:,
        )
      #(cast, list.append(cancels, armed))
    }
  }
}

/// The `NodesEnd` timers of the cast cancelled.
pub fn cancel_nodes_end(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      NodesEnd(cast_id: waiting) -> waiting == cast_id
      Go(..)
      | Finish(..)
      | StartChild(..)
      | StateEnd(..)
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
}

/// The player left the world with casts live: every timer is cancelled and nothing is
/// written; each property modifier the casts hold on a creature is told ended
/// (`TargetChangeEnds`), the creature's own, in cast id order.
pub fn left(cast cast: State) -> #(State, List(Effect)) {
  let on_creatures =
    dict.to_list(cast.on_creatures)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      list.map(entry.1, fn(on) {
        TargetChangeEnds(unit_id: on.unit_id, life: on.life, source: on.source)
      })
    })
  #(
    State(
      ..cast,
      casts: dict.new(),
      lingering: dict.new(),
      timers: dict.new(),
      held: None,
      holding: None,
      current: None,
      thresholds: dict.new(),
      cooldowns: cooldown.drop_all(book: cast.cooldowns),
      stealth: dict.new(),
      procs: dict.new(),
      passive: None,
      on_creatures: dict.new(),
      restrictions: dict.new(),
    ),
    list.append(
      list.map(dict.keys(cast.timers), fn(timer) { CancelTimer(timer:) }),
      on_creatures,
    ),
  )
}

/// The check of a target apply prerequisite for the unit it would reach. The first unit
/// is the unit the effect reaches and the second the caster
/// (`Spell4Effects.prerequisiteIdTargetApply`): the caster's whole unit as `subject` has
/// it for the caster, and another unit as the caster's picture shows it (`struck_subject`).
pub fn target_verdict_on(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> TargetVerdict {
  fn(gate, unit_id, rolls) {
    let on_unit = case unit_id == caster.unit_id {
      True -> subject
      False ->
        struck_subject(
          cast:,
          caster:,
          primary_target: unit_id,
          poses:,
          indexes:,
          units:,
        )
    }
    cast_gate.checked(prerequisite: gate, subject: on_unit, rolls:)
  }
}

/// The gate a go's strike checks its damage, periodic damage and crowd-control rows by,
/// in the caster's picture: the caster side against the caster's unit as both units
/// (`cast_gate.gates_gate`), the target side for a unit by its first unit and the caster second
/// (`cast_gate.unit_gate`), so a row behind no target gate starts for every unit. A row the server
/// cannot tell is not applied and a debug line says so.
pub fn strike_gate(
  cast cast: State,
  caster caster: Caster,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> StrikeGate {
  let subject = subject_of(cast:, caster:)
  let target_verdict =
    target_verdict_on(cast:, caster:, subject:, poses:, indexes:, units:)
  fn(condition, side, what, rolls) {
    case side {
      CasterSide ->
        cast_gate.gates_gate(
          gates: cast_gate.caster_gates(condition:),
          subject:,
          rolls:,
          what:,
          outcome: "so it is not applied",
        )
      UnitSide(unit_id:) ->
        case cast_gate.target_gate_of(condition:) {
          None -> #(Starts, rolls)
          Some(target) ->
            cast_gate.unit_gate(
              target:,
              unit_id:,
              target_verdict:,
              what:,
              outcome: "so it is not applied",
              rolls:,
            )
        }
    }
  }
}

/// The heals of the cast `cast_id` that a timer still waits to land, by timer id.
fn pending_heals(
  cast cast: State,
  cast_id cast_id: Int,
) -> List(#(TimerId, unit_properties.Source, effect_kind.Vital, Int)) {
  cast_state.timers_in_order(cast:)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      ModifierStart(source:, change: Heal(vital:, amount:))
        if source.cast_id == cast_id
      -> Ok(#(entry.0, source, vital, amount))
      ModifierStart(..)
      | TargetModifierStart(..)
      | ForcedMoveStart(..)
      | ModifierEnd(..)
      | RestrictionEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | ProcDue(..)
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
}

/// The pending heals of the cast `cast_id` cancelled with their timers: the node
/// of the cast on the caster is gone, and the client's 0x811 or 0x7fe destroys the effect
/// still pending (`opcode.0x7fe`).
pub fn pending_heals_cancelled(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      ModifierStart(source:, change: Heal(..)) -> source.cast_id == cast_id
      ModifierStart(change: Property(..), ..)
      | ModifierStart(change: Absorb(..), ..)
      | ModifierStart(change: Look(..), ..)
      | TargetModifierStart(..)
      | ForcedMoveStart(..)
      | ModifierEnd(..)
      | RestrictionEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | ProcDue(..)
      | Go(..)
      | Finish(..)
      | StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..)
      | Tick(..) -> False
    }
  })
}

/// The heals of the cast `cast_id` that a timer still waits to land, landed now,
/// as the caster's node ends by time: a node lives as long as its longest effect, so a
/// heal's start falls in the millisecond of the node's end or before it, and the end
/// applies it first, whichever timer the shell delivers first. A node taken off lands
/// none (`cast_proc.effects_ended`).
pub fn heals_landed_at_node_end(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, cast_state.caster_of(cast_id:)),
    return: #(cast, []),
  )
  let pending = pending_heals(cast:, cast_id:)
  let #(cast, cancels) = pending_heals_cancelled(cast:, cast_id:)
  #(
    cast,
    list.append(
      cancels,
      list.map(pending, fn(heal) {
        CasterChangeStarts(
          source: heal.1,
          change: Heal(vital: heal.2, amount: heal.3),
        )
      }),
    ),
  )
}

/// What a cast holds by source (its stealth sources, its procs) with the entries of the
/// cast `cast_id` left out.
pub fn without_cast(
  held held: Dict(unit_properties.Source, a),
  cast_id cast_id: Int,
) -> Dict(unit_properties.Source, a) {
  dict.filter(held, fn(source, _) { source.cast_id != cast_id })
}

/// What a cast holds by source, split in the entries of the cast `cast_id` and what is
/// left of it.
pub fn split_cast(
  held held: Dict(unit_properties.Source, a),
  cast_id cast_id: Int,
) -> #(List(#(unit_properties.Source, a)), Dict(unit_properties.Source, a)) {
  let #(of_cast, others) =
    dict.to_list(held)
    |> list.partition(fn(entry) { { entry.0 }.cast_id == cast_id })
  #(of_cast, dict.from_list(others))
}

/// The units a go gives a node: those a Fluff row aims at, those that took a
/// crowd-control state and those a periodic row ticks on, each once, in that order. The state's life is its delay plus
/// its duration, so the caster's cast lingers until the state's effect is over and its
/// time readout stays right (`cc_state.end`).
pub fn nodes_aimed(aimed aimed: Aimed) -> List(Int) {
  list.unique(
    list.flatten([
      list.filter_map(aimed.reached, fn(entry) {
        node_row_of(entry:) |> result.map(fn(_) { entry.unit_id })
      }),
      list.map(aimed.controls, fn(entry) { entry.1 }),
      list.map(aimed.restrictions, fn(entry) { entry.1 }),
      list.map(aimed.ticking, fn(row) { row.unit_id }),
    ]),
  )
}

/// The life a reached effect gives the node on its unit: a Fluff row, a property or
/// cooldown modifier, a stealth and a proc row live their own delay and duration, a heal
/// applied at once lives its delay so the 0x7fe waits for it. The other kinds give the node
/// no life: they land at the go, or their own state (a crowd-control state, a periodic
/// row) gives it.
fn node_row_of(entry entry: Reached) -> Result(lasting.LastingRow, Nil) {
  case entry.effect.kind, entry.product {
    spell_plan.LastingEffect(lasting: row), _ -> Ok(row.row)
    spell_plan.ModifierEffect(modifier: row), _ -> Ok(row.row)
    spell_plan.CooldownEffect(modifier: row), _ -> Ok(row.row)
    spell_plan.StealthEffect(stealth: row), _ -> Ok(row.row)
    spell_plan.ProcEffect(proc: row), _ -> Ok(row.row)
    spell_plan.HealEffect(..), cast_state.Healing(healed:) ->
      Ok(lasting.LastingRow(
        delay_ms: healed.delay_ms,
        duration_ms: 0,
        until_removed: False,
      ))
    spell_plan.HealEffect(..), cast_state.Plain
    | spell_plan.HealEffect(..), cast_state.CooldownKept(..)
    | spell_plan.ProxyEffect(..), _
    | spell_plan.GainEffect(..), _
    | spell_plan.RemoveEffect(..), _
    | spell_plan.ForcedMoveEffect(..), _
    | spell_plan.StruckMoveEffect(..), _
    | spell_plan.RemoveStealthEffect(..), _
    | spell_plan.ControlEffect(..), _
    | spell_plan.DespawnEffect(..), _
    -> Error(Nil)
  }
}

/// The node a go gives one unit from the node its cast holds there and the Fluff rows
/// the go lists for it (`lasting.given`), a periodic row living its own delay and
/// durationTime as the client's node does (`opcode.0x7f4.effect_time`), held past that
/// only while a tick round on the unit is open (`ended_and_kept`); none when no effect has
/// a life.
pub fn node_of(
  spell spell: Spell,
  held held: Option(lasting.Node),
  aimed aimed: Aimed,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> Result(lasting.Node, Nil) {
  let rows =
    list.filter_map(aimed.reached, fn(entry) {
      case entry.unit_id == unit_id {
        True -> node_row_of(entry:)
        False -> Error(Nil)
      }
    })
  let rows =
    list.append(
      rows,
      list.filter_map(aimed.restrictions, fn(entry) {
        case entry.1 == unit_id {
          True ->
            Ok(lasting.LastingRow(
              delay_ms: entry.0.row.row.delay_ms,
              duration_ms: entry.0.row.row.duration_ms,
              until_removed: entry.0.row.row.until_removed,
            ))
          False -> Error(Nil)
        }
      }),
    )
    |> list.append(
      list.filter_map(aimed.ticking, fn(row) {
        case row.unit_id == unit_id {
          True ->
            Ok(lasting.LastingRow(
              delay_ms: row.schedule.delay_ms,
              duration_ms: row.schedule.duration_ms,
              until_removed: False,
            ))
          False -> Error(Nil)
        }
      }),
    )
  let held_until_ms =
    list.filter_map(aimed.controls, fn(entry) {
      case entry.1 == unit_id {
        True -> Ok(entry.0.ends_at_ms)
        False -> Error(Nil)
      }
    })
  lasting.given(
    held:,
    unit_id:,
    count: 1,
    effects: rows,
    held_until_ms:,
    longer_of_delay_and_duration: spell.longer_of_delay_and_duration,
    go_ms: now_ms,
  )
}

/// What the live and lingering casts hold on the unit, as removals, stacking and
/// prerequisites read it.
pub fn holds_on(cast cast: State, unit_id unit_id: Int) -> List(lasting.Hold) {
  list.filter_map(cast_state.holders(cast:), fn(entry) {
    let #(cast_id, holder) = entry
    dict.get(holder.nodes, unit_id)
    |> result.map(fn(node) {
      lasting.Hold(
        cast_id:,
        spell4_id: holder.spell.spell4_id,
        base: holder.spell.spell4_base_id,
        groups: holder.spell.groups,
        stack: holder.spell.stack,
        started_ms: holder.started_ms,
        node:,
      )
    })
  })
}

/// Whether the client keeps a cast that has no target left, so its end must be
/// written (`opcode.0x811`: cast methods 1, 3, 8 and 10).
pub fn keeps_without_target(method method: spell_plan.CastMethod) -> Bool {
  case method {
    spell_plan.Channeled
    | spell_plan.ChanneledField
    | spell_plan.Multiphase
    | spell_plan.OtherMethod(10) -> True
    spell_plan.Normal
    | spell_plan.PressHold
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.ChargeRelease
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> False
  }
}

/// A cast loses one stack on a unit: 0x813 and its node one count lower. A node's
/// count is the 1 of an application, so a removal reaches this only for a node whose
/// count is higher (`opcode.0x7f4.instance_count`, `opcode.0x813`).
pub fn stack_off(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let nodes = case dict.get(holder.nodes, unit_id) {
        Ok(node) ->
          dict.insert(
            holder.nodes,
            unit_id,
            lasting.Node(..node, count: int.max(0, node.count - 1)),
          )
        Error(Nil) -> holder.nodes
      }
      #(
        with_nodes(cast:, cast_id:, nodes:),
        stack_removed_effects(cast_id:, unit_id:, audience: holder.audience),
      )
    }
  }
}

/// 0x811 for the units, to the caster and told to the audience, with whether the
/// client destroys the cast with it.
pub fn targets_removed_effects(
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
  audience audience: Set(ConnectionId),
  destroyed destroyed: Bool,
) -> List(Effect) {
  let removed = SpellTargetsRemoved(cast_id:, unit_ids:)
  [
    Send(frame: cast_frame.targets_removed_frame(removed:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastTargetsRemoved(removed:, destroyed:),
      )
    })
  ]
}

/// 0x813 for the unit, to the caster and told to the audience.
fn stack_removed_effects(
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  let removed = SpellStackRemoved(cast_id:, unit_id:)
  [
    Send(frame: cast_frame.stack_removed_frame(removed:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastStackRemoved(removed:))
    })
  ]
}

/// 0x7fe to the caster and told to the audience.
pub fn finished_effects(
  cast_id cast_id: Int,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  [
    Send(frame: cast_frame.finished_frame(cast_id:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastFinished(cast_id:))
    })
  ]
}

/// What a prerequisite may read about the caster, with no roll: the live casts it is
/// the primary target of and what the live and lingering casts hold on it, whether it
/// is in combat, and its vitals: its health and
/// shield, and the one class resource slot it holds as Vital 5 to 11 (slots 0 to 6,
/// `0x1403b3320`: the cost check reads Vitals 5 to 11 as the caster's resource slots
/// 0 to 6; the getter type 71 and 73 call is not read case by case, so the same
/// mapping is taken for it). A slot the class does not hold is no vital, so a
/// prerequisite of it is not read. The same slot is the resource slot a type 64 condition
/// names by its number, and every other slot reads 0.0 as the client's unit holds it
/// (`class_resource`, `0x140454380`). A player holds no difficulty. The caster stands on
/// its own point, facing its own yaw, for both units of a type 108 condition
/// (`Spell4Effects.prerequisiteIdTargetApply`: the caster is both units of a caster-side
/// check).
pub fn subject_of(
  cast cast: State,
  caster caster: Caster,
) -> prerequisite.Subject {
  let slot = class_resource.slot(resources: caster.resources)
  let held = case slot >= 0 && slot <= 6 {
    True -> [
      #(
        slot + 5,
        prerequisite.Vital(
          current: class_resource.value(resources: caster.resources, slot:),
          maximum: class_resource.max(resources: caster.resources, slot:),
        ),
      ),
    ]
    False -> []
  }
  let pose = area.pose_of(place: caster.place)
  prerequisite.Subject(
    under: dict.values(cast.casts)
      |> list.filter(fn(live) { live.primary_target == caster.unit_id })
      |> list.map(fn(live) {
        lasting.Held(
          spell4_id: live.spell.spell4_id,
          caster: caster.unit_id,
          count: 0,
          groups: live.spell.groups,
        )
      })
      |> list.append(nodes_held(cast:, caster:)),
    second_unit: Some(caster.unit_id),
    in_combat: caster.in_combat,
    vitals: dict.merge(dict.from_list(held), caster.life_vitals),
    difficulty: None,
    stealthed: Some(cast_state.stealthed(cast:)),
    resource_slots: Some(case slot >= 0 {
      True ->
        dict.from_list([
          #(slot, class_resource.value(resources: caster.resources, slot:)),
        ])
      False -> dict.new()
    }),
    rolls: [],
    positions: prerequisite.Placed(first: pose, second: pose),
    factions: Some(caster.factions),
    player: Some(caster.player),
    quests: Some(caster.quests),
    creature_index: None,
    seen: prerequisite.WholeUnit,
    checker: Some(caster.checker),
    first_unit: prerequisite.TheChecker,
  )
}

/// What the live and lingering casts hold on the caster's own unit, as a
/// prerequisite reads it.
fn nodes_held(cast cast: State, caster caster: Caster) -> List(lasting.Held) {
  list.map(holds_on(cast:, unit_id: caster.unit_id), fn(hold) {
    lasting.Held(
      spell4_id: hold.spell4_id,
      caster: caster.unit_id,
      count: hold.node.count,
      groups: hold.groups,
    )
  })
}

/// The subject of a Proxy's target gate on a struck unit: as the caster's picture shows it,
/// with the checklist index its 0x262 carried when the picture holds one, what the unit is
/// (a unit the picture does not hold is unknown to a type 38 or 214 condition), and what
/// the caster's own casts hold on it (a type 130 condition's group).
pub fn struck_subject(
  cast cast: State,
  caster caster: Caster,
  primary_target primary_target: Int,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> prerequisite.Subject {
  let struck =
    prerequisite.of_struck(
      first: option.from_result(dict.get(poses, primary_target)),
      second: area.pose_of(place: caster.place),
      player: caster.player,
      quests: caster.quests,
      unit: result.unwrap(
        dict.get(units, primary_target),
        or: prerequisite.UnknownUnit,
      ),
      caster_unit: caster.unit_id,
      under: held_by_caster_on(cast:, caster:, unit_id: primary_target),
      checker: caster.checker,
    )
  case dict.get(indexes, primary_target) {
    Ok(index) -> prerequisite.counting(subject: struck, checklist_index: index)
    Error(Nil) -> struck
  }
}

/// What a Proxy's target gate gives for the unit its child would be made on. The gate's
/// first unit is that unit and its second the caster
/// (`Spell4Effects.prerequisiteIdTargetApply`): a struck unit as the caster's picture
/// shows it (`of_struck`, so a unit with no pose leaves a type 108 condition not read), or
/// the caster for a Proxy aimed at it, which stands on its own point, as `subject` has it.
/// A Proxy with no target gate starts. The plan gives a Proxy no condition but `Always`,
/// `GatedOnCaster` and `GatedOnCasterAndTarget`; a Proxy that holds `GatedOnTarget`, which
/// it never builds for one, starts on a unit that passes the gate, as any row does. The
/// check takes the rolls of its type 37 conditions off the front of `rolls`, and the rolls
/// left follow the verdict.
pub fn target_gate(
  cast cast: State,
  proxy proxy: Proxy,
  caster caster: Caster,
  primary_target primary_target: Int,
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(GateDecision, List(Int)) {
  case proxy.condition {
    spell_plan.GatedOnTarget(prerequisite: target)
    | spell_plan.GatedOnCasterAndTarget(target:, ..) -> {
      let gate_subject = case proxy.target {
        spell_plan.OnCaster -> subject
        spell_plan.OnEachStruck ->
          struck_subject(
            cast:,
            caster:,
            primary_target:,
            poses:,
            indexes:,
            units:,
          )
      }
      cast_gate.unit_gate(
        target:,
        unit_id: primary_target,
        target_verdict: fn(gate, _, rolls) {
          cast_gate.checked(prerequisite: gate, subject: gate_subject, rolls:)
        },
        what: "the Proxy to Spell4 "
          <> int.to_string(proxy.spell.spell4_id.value),
        outcome: "so it is not started",
        rolls:,
      )
    }
    spell_plan.Always | spell_plan.GatedOnCaster(..) -> #(Starts, rolls)
  }
}
