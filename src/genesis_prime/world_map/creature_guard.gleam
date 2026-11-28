//// A creature's guard: the creature takes no damage until a crowd-control state breaks its
//// charge, then opens to damage for a while. The tutorial's Sim-Turrets have it: Spell4 85474
//// "Turret Immune" guards, Spell4 85472 "Moment of Opportunity" opens. It runs in the creature's
//// process (genesis_prime/world_map/creature); the charge's break is the fight's
//// (genesis_prime/world_map/creature_fight) and the states are creature_control's.
////
//// ```
//// start:     `new` ─▶ Guarded(cast): ─0x7ff(85474) 0x7f4(224666, lifetime 0)─▶ viewers
//// viewer:    `shown`: the guard's or the opening's cast, for that viewer alone
//// interrupt: the fight's `Interrupted(charge_cast)` ─▶ Opened(generation):
////            ─0x7ff(85472) 0x7f4(224705, 224715, 225189) 0x811(guard's cast) 0x87f(states)─▶
////            StartTimer(OpeningEnds)
//// timer end: ─0x880(states) 0x7fe(opening's cast)─▶ viewers; Guarded(a new cast)
//// killed:    Guarded: no frame ─▶ Dormant; Opened: CancelTimer, ─0x7fe─▶ Dormant
//// ```
////
//// - **The guard takes no damage:** the client reads no immunity
////   (`Spell4Effects.effectType.79`); a strike whose offence is damage answers `Immune`
////   (genesis_prime/shared/strike_tell), shown by 0x247 type 18 (`opcode.0x247.immunity`).
//// - **The guard is shown by its cast:** the 85474 cast, 0x7ff and a 0x7f4 of effect 224666 with
////   lifetime 0, never ends; its 0x7fe is held back (`cast.target_node_end`). Taking it off is a
////   0x811 of its cast, putting it back a new cast (`Spell4.85472.viewer`).
//// - **The opening is shown by its cast, then its states:** 0x87f alone shows no target-frame
////   sprite (`TargetFrame.lua UpdateInterruptArmor`); each state's 0x87f goes with its effect's
////   instance id, and each state ends by a 0x880, then the cast's 0x7fe.
//// - **An opening cannot open again while it lasts:** no charge starts under it (Spell4 85469
////   prerequisiteIdCasterCast 41722), so no second interrupt reaches `Interrupted`.
//// - **Casts take ids with the fight's:** `cast_state.mint` mints each against the fight's live
////   casts, and the fight's casts mint against the guard's (`live_casts`).
//// - **Which creature:** a kind with a guard and an opening
////   (genesis_prime/shared/creature_kind) gives one; the load refuses a spell with other effects
////   (`creature_guard_spells.guard_of`); a creature with none is `Bare`.
//// - **A dead creature has no guard up:** `Dormant` shows nothing, holds no cast; the next life
////   starts guarded.
//// - **Instance ids** of the opening's effects are the creature's own counter, from 1, never used
////   twice in its life.

import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import genesis_prime/shared/creature_guard_spells.{type Guard}
import genesis_prime/shared/lasting
import genesis_prime/shared/telegraph_entries
import genesis_prime/shared/unit_news.{type News}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Where the guard stands.
pub type Phase {
  /// The creature has no guard: it takes damage and opens nothing.
  Bare
  /// The creature has a guard and is dead: nothing is shown and no cast is live.
  Dormant
  /// The guard is up: the id of its cast, which the viewers were shown.
  Guarded(cast_id: Int)
  /// The creature is open to damage: the generation of its `OpeningEnds` timer, the monotonic time
  /// it fires at, the id of the opening's cast, and each effect it applied.
  Opened(generation: Int, ends_at_ms: Int, cast_id: Int, held: List(Held))
}

/// An effect the opening applied to the creature: its row, the state it sets (none for Fluff),
/// the instance id the client keeps it by and its lifetime when it was applied.
pub type Held {
  Held(
    effect_id: Int,
    state: Option(CrowdControlState),
    instance_id: Int,
    lifetime_ms: Int,
  )
}

/// A creature's guard: its spells, where it stands, the generation of its next timer, the
/// instance id of its next effect, the number of its next cast and the instance id of the
/// guard's effect while it is up.
pub opaque type State {
  State(
    guard: Option(Guard),
    phase: Phase,
    next_generation: Int,
    next_instance: Int,
    next_cast: Int,
    guard_instance: Int,
  )
}

/// The guard's timer, of the generation it was started with: one of an opening that is over
/// (an end, a death) does nothing when it fires.
pub type Timer {
  /// The opening's time is up: the guard comes back.
  OpeningEnds(generation: Int)
}

/// What the creature's rule turns its messages into for the guard.
pub type Input {
  /// The fight's charge was broken by a state: the creature opens, when it has a guard that is up.
  /// The charge's cast was just finished, and the opening's takes none of its id.
  Interrupted(charge_cast: Int)
  /// The guard's timer fired.
  TimerFired(timer: Timer)
  /// creature_life: a strike killed the creature. The guard ends with no frame, the opening's cast
  /// is finished, and the guard is `Dormant`.
  Killed
  /// creature_life: a DespawnUnit effect removed the creature from the field. The guard ends as
  /// it does at a kill.
  Despawned
}

/// What the guard asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer: the guard's and the opening's casts, a
  /// 0x811 of the guard's cast, 0x87f, 0x880 and 0x7fe.
  ToViewers(news: News)
  /// A timer which the creature's rule makes an id of (genesis_prime/world_map/creature).
  StartTimer(timer: Timer, after_ms: Int)
  CancelTimer(timer: Timer)
}

/// A creature with its guard (none for a creature that has none), up when it has one, with the
/// first cast id of the unit's id space no live cast holds (the fight has none yet).
pub fn new(guard guard: Option(Guard), unit_id unit_id: Int) -> State {
  let phase = case guard {
    Some(..) -> Guarded(cast_id: cast_state.mint(unit_id:, number: 1, live: []))
    None -> Bare
  }
  State(
    guard:,
    phase:,
    next_generation: 1,
    next_instance: 2,
    next_cast: 2,
    guard_instance: 1,
  )
}

/// Whether the guard is up: a strike's damage takes nothing.
pub fn guarded(state state: State) -> Bool {
  case state.phase {
    Guarded(..) -> True
    Bare | Dormant | Opened(..) -> False
  }
}

/// Whether the creature is open: it holds the opening's states, and no charge starts.
pub fn opened(state state: State) -> Bool {
  case state.phase {
    Opened(..) -> True
    Bare | Dormant | Guarded(..) -> False
  }
}

/// The ids of the casts the guard holds live, which the fight's casts take no id of
/// (`cast_state.mint`).
pub fn live_casts(state state: State) -> List(Int) {
  case state.phase {
    Bare | Dormant -> []
    Guarded(cast_id:) | Opened(cast_id:, ..) -> [cast_id]
  }
}

/// One input in, the new state and the effects out. `unit_id` is the creature's, `live` the
/// ids of the casts the fight holds live, which the guard's casts take no id of, and `now_ms` the
/// monotonic time of the input, which the opening's end is counted from. A creature with no
/// guard takes none of it.
pub fn step(
  state state: State,
  unit_id unit_id: Int,
  live live: List(Int),
  place place: Place,
  input input: Input,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case state.guard {
    None -> #(state, [])
    Some(guard) ->
      case input {
        Interrupted(charge_cast:) ->
          case state.phase {
            Guarded(cast_id: guard_cast) ->
              opens(
                state:,
                guard:,
                guard_cast:,
                unit_id:,
                live: [charge_cast, ..live],
                place:,
                now_ms:,
              )
            Bare | Dormant | Opened(..) -> #(state, [])
          }
        TimerFired(timer: OpeningEnds(generation: fired)) ->
          opening_ended(state:, guard:, unit_id:, live:, place:, fired:)
        Killed | Despawned ->
          case state.phase {
            Guarded(..) -> #(State(..state, phase: Dormant), [])
            Opened(generation:, cast_id:, ..) -> #(
              State(..state, phase: Dormant),
              [
                CancelTimer(timer: OpeningEnds(generation:)),
                ToViewers(unit_news.CastFinished(cast_id:)),
              ],
            )
            Bare | Dormant -> #(state, [])
          }
      }
  }
}

/// The opening's timer of generation `fired` fired: when it is the open opening's, each of its
/// states ends, then its cast, and the guard goes up again; any other generation is gone.
fn opening_ended(
  state state: State,
  guard guard: Guard,
  unit_id unit_id: Int,
  live live: List(Int),
  place place: Place,
  fired fired: Int,
) -> #(State, List(Effect)) {
  case state.phase {
    Opened(generation:, cast_id:, held:, ..) if generation == fired -> {
      let #(state, raising) =
        raised(state:, guard:, unit_id:, live: [cast_id, ..live], place:)
      #(
        state,
        list.flatten([
          list.map(states_of(held:), fn(held) {
            ToViewers(unit_news.CrowdControlEnded(
              state: held.0,
              cast_id:,
              instance_id: held.1,
            ))
          }),
          [ToViewers(unit_news.CastFinished(cast_id:))],
          raising,
        ]),
      )
    }
    Bare | Dormant | Guarded(..) | Opened(..) -> #(state, [])
  }
}

/// The guard goes up: a new cast of the creature's id space, `live` the ids of the casts that
/// are live, and the 0x7ff and 0x7f4 of it, with an effect of its own instance id and lifetime 0.
fn raised(
  state state: State,
  guard guard: Guard,
  unit_id unit_id: Int,
  live live: List(Int),
  place place: Place,
) -> #(State, List(Effect)) {
  let cast_id = cast_state.mint(unit_id:, number: state.next_cast, live:)
  let state =
    State(
      ..state,
      phase: Guarded(cast_id:),
      next_cast: cast_state.number_of(cast_id:) + 1,
      next_instance: state.next_instance + 1,
      guard_instance: state.next_instance,
    )
  #(
    state,
    list.map(guard_cast(state:, guard:, unit_id:, place:, cast_id:), ToViewers),
  )
}

/// The creature opens: the opening's cast, the guard's cast taken off, then the states, and the
/// timer that ends it.
fn opens(
  state state: State,
  guard guard: Guard,
  guard_cast guard_cast: Int,
  unit_id unit_id: Int,
  live live: List(Int),
  place place: Place,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let cast_id =
    cast_state.mint(unit_id:, number: state.next_cast, live: [
      guard_cast,
      ..live
    ])
  let #(next_instance, held) =
    list.map_fold(
      guard.opening.effects,
      state.next_instance,
      fn(instance, effect) {
        #(
          instance + 1,
          Held(
            effect_id: effect.effect_id,
            state: effect.state,
            instance_id: instance,
            lifetime_ms: effect.lifetime_ms,
          ),
        )
      },
    )
  let generation = state.next_generation
  let state =
    State(
      ..state,
      phase: Opened(
        generation:,
        ends_at_ms: now_ms + guard.opening.ends_after_ms,
        cast_id:,
        held:,
      ),
      next_generation: generation + 1,
      next_instance:,
      next_cast: cast_state.number_of(cast_id:) + 1,
    )
  #(
    state,
    list.flatten([
      list.map(
        opening_cast(guard:, unit_id:, place:, cast_id:, held:, elapsed_ms: 0),
        ToViewers,
      ),
      [
        ToViewers(unit_news.CastTargetsRemoved(
          removed: SpellTargetsRemoved(cast_id: guard_cast, unit_ids: [unit_id]),
          destroyed: True,
        )),
      ],
      list.map(states_of(held:), fn(held) {
        ToViewers(unit_news.CrowdControlApplied(
          state: held.0,
          instance_id: held.1,
        ))
      }),
      [
        StartTimer(
          timer: OpeningEnds(generation:),
          after_ms: guard.opening.ends_after_ms,
        ),
      ],
    ]),
  )
}

/// The 0x7ff and 0x7f4 of the guard's cast on the creature: its effect with its instance id and
/// lifetime 0, which no 0x7fe ends. It is an effect cast on the creature itself and its 0x7ff
/// carries no telegraph entry (whether a guard spell has a drawn server-placed row is not
/// read; the guard spells come from the importer).
fn guard_cast(
  state state: State,
  guard guard: Guard,
  unit_id unit_id: Int,
  place place: Place,
  cast_id cast_id: Int,
) -> List(News) {
  [
    unit_news.CastStarted(start: cast_frame.creature_started(
      cast_id:,
      spell4_id: guard.spell4_id,
      caster_unit_id: unit_id,
      target_unit_id: unit_id,
      place:,
      opening: telegraph_entries.none,
    )),
    unit_news.CastWent(
      go: cast_frame.creature_applied(
        cast_id:,
        place:,
        target_unit_id: unit_id,
        effects: [
          cast_state.CreatureEffect(
            effect_id: guard.effect_id,
            instance_id: state.guard_instance,
            lifetime_ms: 0,
          ),
        ],
      ),
    ),
  ]
}

/// The 0x7ff and 0x7f4 of the opening's cast on the creature: each effect applied under its
/// instance id, for what is left of its lifetime after `elapsed_ms`.
fn opening_cast(
  guard guard: Guard,
  unit_id unit_id: Int,
  place place: Place,
  cast_id cast_id: Int,
  held held: List(Held),
  elapsed_ms elapsed_ms: Int,
) -> List(News) {
  [
    unit_news.CastStarted(start: cast_frame.creature_started(
      cast_id:,
      spell4_id: guard.opening.spell4_id,
      caster_unit_id: unit_id,
      target_unit_id: unit_id,
      place:,
      opening: telegraph_entries.none,
    )),
    unit_news.CastWent(go: cast_frame.creature_applied(
      cast_id:,
      place:,
      target_unit_id: unit_id,
      effects: list.map(held, fn(effect) {
        cast_state.CreatureEffect(
          effect_id: effect.effect_id,
          instance_id: effect.instance_id,
          lifetime_ms: lasting.time_left_ms(
            end_ms: effect.lifetime_ms,
            now_ms: elapsed_ms,
          ),
        )
      }),
    )),
  ]
}

/// The states the opening holds, each with the instance id of its effect, in the effects' order.
fn states_of(held held: List(Held)) -> List(#(CrowdControlState, Int)) {
  list.filter_map(held, fn(effect) {
    case effect.state {
      Some(state) -> Ok(#(state, effect.instance_id))
      None -> Error(Nil)
    }
  })
}

/// The news a viewer that arrives is sent after the creature's 0x262: the guard's cast, or the opening's
/// with the states' 0x87f, for the viewer alone. The opening's lifetime is the time left at `now_ms`.
pub fn shown(
  state state: State,
  unit_id unit_id: Int,
  place place: Place,
  now_ms now_ms: Int,
) -> List(News) {
  case state.guard {
    None -> []
    Some(guard) ->
      case state.phase {
        Bare | Dormant -> []
        Guarded(cast_id:) ->
          guard_cast(state:, guard:, unit_id:, place:, cast_id:)
        Opened(ends_at_ms:, cast_id:, held:, ..) ->
          list.append(
            opening_cast(
              guard:,
              unit_id:,
              place:,
              cast_id:,
              held:,
              elapsed_ms: guard.opening.ends_after_ms - { ends_at_ms - now_ms },
            ),
            list.map(states_of(held:), fn(held) {
              unit_news.CrowdControlApplied(state: held.0, instance_id: held.1)
            }),
          )
      }
  }
}
