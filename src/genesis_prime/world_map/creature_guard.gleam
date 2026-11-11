//// A creature's guard: the feature of the creature's rule (genesis_prime/world_map/creature)
//// that makes a creature take no damage until a crowd-control state breaks its charge, and
//// opens it to damage for a while after. The Sim-Turrets of the tutorial have it: Spell4 85474
//// "Turret Immune" guards, Spell4 85472 "Moment of Opportunity" opens. It runs in the creature's
//// process, so every 0x7ff, 0x7f4, 0x811, 0x87f, 0x880 and 0x7fe of the guard's casts comes from
//// the unit's one owner. The charge's break is the fight's (genesis_prime/world_map/creature_fight);
//// the states are creature_control's; this feature holds only what the guard and the opening are.
////
//// ```
//// P's connection            creature C: fight            creature C: guard             C's viewers
//// the creature stands (a start, or the corpse timer):
////                                                        Stands ─▶ Guarded(cast id)
////                                                        ─0x7ff(85474) 0x7f4(target C, effect 224666,
////                                                           lifetime 0)────────────────────────────▶
//// a viewer arrives:                                      `shown`: the same 0x7ff and 0x7f4 for that
////                                                           viewer alone; Opened: the opening's too
//// the fight's charge is Charging, a state of creature_control lands (`Controlled`):
//// ◀── answer(Landed) ◀── 0x87f(state) from creature_control
////                          the charge breaks: CancelTimer(CastEnds), ─0x7f9(cast, 11) 0x7fe─────▶
////                          ChargeInterrupted ─▶ Interrupted ─▶ Opened(generation):
////                                                        ─0x811(85474's cast, C) 0x7ff(85472) 0x7f4(C: 224705,
////                                                           225189, 224715) 0x87f(C, 9) 0x87f(C, 12)─▶
////                                                        StartTimer(OpeningEnds, ends_after_ms)
//// damage while Opened:                                   the strike lands as on any creature
//// OpeningEnds of the opening's generation:
////                                                        ─0x880(C, 9) 0x880(C, 12) 0x7fe(85472's cast)─▶
////                                                        Guarded(a new cast): ─0x7ff(85474) 0x7f4─────▶
//// C is killed (Guarded or Opened):                       CancelTimer(OpeningEnds); no frame (the death
////                                                           clears the client's states); Dormant, which
////                                                           shows nothing and holds no cast
//// the corpse timer stands C again (`Stands`):            Dormant ─▶ Guarded(a new cast), as at a start
//// ```
////
//// - **The guard takes no damage.** The client reads no immunity: nothing reads Spell4Effects type
////   79, so the guard is the server's alone (`Spell4Effects.effectType.79`). A strike whose
////   offence is damage and whose descriptions the guard emptied answers `Landed` with none, and
////   the striker's connection writes the 0x247 of type 18, the one immunity the client shows
////   (`opcode.0x247.immunity`). A state a strike carries still lands (creature_control).
//// - **The guard is shown by its cast.** The 85474 cast, 0x7ff and a 0x7f4 holding a target info
////   for the creature with effect 224666, a non-zero instance id and lifetime 0, never ends on the
////   client, and its 0x7fe is held back (a 0x7fe destroys the node and the buff: `cast.target_node_end`).
////   Taking the guard off is 0x811 of its cast, putting it back a new cast
////   (`Spell4.85472.viewer`).
//// - **The opening is shown by its cast, then its states.** 0x87f alone does not show the target
////   frame's sprite: that needs the CCStateSet effect on the unit (`TargetFrame.lua
////   UpdateInterruptArmor`). So the 85472 cast goes to every viewer, 0x7ff and a 0x7f4 whose
////   target info for the creature holds effect infos 224705 (state 9), 225189 (state 12) and 224715
////   (Fluff, 15 s), each with its own non-zero instance id, then a 0x87f for each state with its
////   effect's instance id. The 0x87f carries no duration: the effect's lifetime in the go does.
////   A state never ends by time on the client, so the end is 0x880 for each, then the cast's 0x7fe.
//// - **An opening cannot be opened again** while it lasts: no charge starts under it (the fight's
////   `controlled` is true while `opened`: Spell4 85469 prerequisiteIdCasterCast 41722), so no second
////   interrupt reaches `Interrupted`; one that does (two inputs in one step) opens nothing more.
//// - **Casts take ids with the fight's.** The guard's casts are ids of the unit's id space
////   (`cast.cast_id`) taken with `cast.mint`, given the fight's live casts, and the fight's take
////   the guard's (`live_casts`), so neither holds an id the other still has.
//// - **Which creature.** A kind with a guard and an opening (genesis_prime/world_map/creature_kind)
////   gives its creature one; the load refuses a spell whose effects are not the ones the creature
////   applies (`creature_guard_spells.guard_of`). A creature with none has no guard: `Bare`, takes damage, opens nothing.
//// - **A dead creature has no guard up.** `Dormant` is a creature with a guard that is dead: nothing
////   shown, no live cast, no damage immunity, no opening. Only `Stands` raises it again, so a creature
////   killed while open stands guarded when its corpse timer ends.
//// - **Instance ids** of the opening's effects are the creature's own counter, from 1, and are never
////   used twice in its life.
////
//// What happens at each failure point of the guard:
////
//// | Step | Creature killed there | Twice at once | Late |
//// |---|---|---|---|
//// | The creature stands guarded | n/a | a start and `Stands` together: one guard cast, the second finds it `Guarded` | n/a |
//// | A viewer arrives | n/a | the viewer is told the guard (or the opening) by `shown`, as the 0x262 | its 0x262 comes before the casts; a 0x87f for a unit the client does not have yet is skipped (`opcode.0x87f`) |
//// | A state lands outside a charge | nothing opens (`a_state_on_a_guarded_turret_outside_a_charge_lands_and_opens_nothing_test`) | creature_control's own rules | n/a |
//// | A state lands during the charge (`Interrupted`) | the charge's cast is finished by the fight's death branch, and the guard is `Dormant` until `Stands` | two states for one charge: the first breaks the round, the second finds none and opens nothing (`a_second_state_in_the_same_round_opens_nothing_more_test`) | a state after the go: the round is `Striking`, so no interrupt (`an_interrupt_after_the_go_opens_nothing_test`) |
//// | The opening is open, its timer armed | no 0x880: the death clears the states; the timer is cancelled; `Dormant` until `Stands` (`a_turret_killed_while_opened_gives_its_kill_credit_test`) | n/a | n/a |
//// | The opening's timer fires | its generation is gone: nothing (`an_opening_end_after_death_does_nothing_test`) | n/a | the guard returns (`the_opening_ends_after_15_seconds_and_the_guard_returns_test`) |
//// | The corpse timer stands the creature | n/a | n/a | `Dormant` takes `Stands`: it stands guarded with a new cast, no opening (`a_respawned_turret_stands_guarded_test`) |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/cast
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/world_map/creature_guard_spells.{type Guard}
import gleam/option.{type Option, None, Some}

/// Where the guard stands.
pub type Phase {
  /// The creature has no guard: it takes damage and opens nothing.
  Bare
  /// The creature has a guard and is dead: nothing is shown and no cast is live, until `Stands`.
  Dormant
  /// The guard is up: the id of its cast, which the viewers were shown.
  Guarded(cast_id: Int)
  /// The creature is open to damage: the generation of its `OpeningEnds` timer, the monotonic time
  /// it fires at, the id of the opening's cast, and each state it holds with the instance id of its
  /// effect.
  Opened(generation: Int, ends_at_ms: Int, cast_id: Int, held: List(Held))
}

/// A state the opening holds on the creature, with the instance id of the effect that set it.
pub type Held {
  Held(state: CrowdControlState, instance_id: Int)
}

/// A creature's guard: its spells, where it stands, the generation of its next timer and the
/// instance id of its next effect.
pub opaque type State {
  State(
    guard: Option(Guard),
    phase: Phase,
    next_generation: Int,
    next_instance: Int,
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
  /// The creature stands, at a start or when its corpse timer stood it again: the guard is up.
  Stands
  /// The fight's charge was broken by a state: the creature opens, when it has a guard that is up.
  Interrupted
  /// The guard's timer fired.
  TimerFired(timer: Timer)
  /// creature_life: a strike killed the creature. The guard or the opening ends with no frame and
  /// the guard is `Dormant`.
  Killed
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
    Some(..) -> Guarded(cast_id: cast.mint(unit_id:, number: 1, live: []))
    None -> Bare
  }
  State(guard:, phase:, next_generation: 1, next_instance: 1)
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
/// (`cast.mint`).
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
  unit_id _unit_id: Int,
  live _live: List(Int),
  input _input: Input,
  now_ms _now_ms: Int,
) -> #(State, List(Effect)) {
  case state.phase {
    Bare -> #(state, [])
    Dormant | Guarded(..) | Opened(..) ->
      panic as "shape: #655 step: Stands raises a Dormant guard with a new cast, Interrupted opens a guarded creature, OpeningEnds of the opening's generation puts the guard back, Killed makes Guarded or Opened Dormant with no frame"
  }
}

/// The news a viewer that arrives is sent after the creature's 0x262: the guard's cast, or the opening's
/// with the states' 0x87f, for the viewer alone. The opening's lifetime is the time left at `now_ms`.
pub fn shown(
  state state: State,
  unit_id _unit_id: Int,
  now_ms _now_ms: Int,
) -> List(News) {
  case state.phase {
    Bare | Dormant -> []
    Guarded(..) | Opened(..) ->
      panic as "shape: #655 shown is the guard's 0x7ff and 0x7f4, or the opening's with the time left as lifetime, then the 0x87f of each held state"
  }
}
