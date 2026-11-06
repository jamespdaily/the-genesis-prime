//// A creature's crowd-control states: the feature of the creature's rule
//// (genesis_prime/world_map/creature) that takes the states a caster's strike carries,
//// holds each for its time, tells the creature's viewers when it takes hold and when
//// it ends, and tells the fight (genesis_prime/world_map/creature_fight) whether the
//// creature may act. The creature's process owns its unit, its viewers and its timers,
//// so every 0x87f and 0x880 of the unit comes from its one owner, in the order the
//// states landed and ended.
////
//// ```
//// caster's connection        creature (this feature)                                   viewers
//// go phase: Strike(.., controls) ─▶ struck: the hit rule on health, then `land`
////                                   alive and no Interrupt Armor: a Control for each state,
////                                     a timer at its end
////                                   Answered(Landed(.., controls landed)) ─▶ caster's go lists them
////                                   0x87f (unit, state, instance id) ──────────────────────▶ state on
////                                   the fight: no strike, chase or walk; a running path stops
////                                     (0x638 of kind 2)
//// ... a control's timer fires ─▶ `ended`
////                                   0x880 (unit, state, cast id, instance id, 0) ──────────▶ state off
////                                   the last one ended: the fight acts again from where it stands
//// ```
////
//// - **Whether a state lands** is the server's rule: the client reads no Interrupt Armor
////   in any CC handler (`UnitProperty2.InterruptArmor_Threshold`). A living creature with
////   an armor maximum of 0 takes every state; one with armor above 0 or infinite takes
////   none, answers it not landed, and logs one line per creature that the armor rules are
////   not built.
//// - **How long** a creature holds a state is the row's delay plus durationTime from the
////   tell's arrival: a creature's CC resilience is 0 and its duration modifier 1
////   (`cc_state.duration_on_creature`). The arrival is when the strike's phase began,
////   which is before the go is written by the time the round waited for answers.
//// - **A state ends only by the server's 0x880**, which the creature sends when its timer
////   fires, naming the state, the cast and the instance id the go gave (`cc_state.end`,
////   `cc_state.instance_id`). A creature that dies sends none: the client clears every
////   state at a death (`SetUnitDead`).
//// - **Knockdown is a stun for a creature**: the same flags, and its only difference is
////   a player's dash (`GameFormula.614`, `CCStates.flags`).
//// - **Each landed state is its own control**, with its own timer and its own 0x880: two
////   players' states, or one caster's two states of a kind, are held side by side, and
////   the creature acts again when none is held (`cc_state.instance_id`).
//// - **A control's timer** is numbered 4n + 1 from n = 1 (5, 9, 13 ...), where n is the
////   control's number for the creature's life: the corpse timer is 1 and the fight's are
////   4g + 2, 4g + 3 and 4g + 4 (genesis_prime/world_map/creature), so none meets
////   another. A timer that fires for a control already gone finds none and writes
////   nothing.
////
//// What happens at each failure point of a state:
////
//// | Step | Creature killed there | Twice at once | Late |
//// |---|---|---|---|
//// | A strike with states reaches the creature | the creature restarts from its spawn with no state; the client keeps the visual until the unit is removed and made again (`0x355` and `0x262` clear states) | two players stun it: two controls, two 0x87f, each its own 0x880; it acts when both ended | a strike after its death is refused as always; no state |
//// | A control is held, its timer armed | as above | one caster's two states of a kind are held separately | n/a |
//// | A control's timer fires | as above | two ending in one millisecond: two 0x880 | fires after the death: no frame |
//// | The creature dies holding a state | no 0x880: death clears the client's states, and the timers are cancelled | | |
//// | A viewer arrives while a state is held | not told: the 0x262 does not carry it (a gap) | | |
//// | The caster's cast lingers past the state's end | the node's life is the effect's, and the cast rule's timer ends it (genesis_prime/game/lasting) | | |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/strike_tell.{type ControlTell, type Tell}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/step.{type Address, type LogLevel, type TimerId, TimerId}
import genesis_prime/world_map/creature_life.{type InterruptArmor}

/// One state a creature holds: the state, the cast it came from (the strike's cast id,
/// which its 0x880 names), the instance id the caster's go gave it, the address of the
/// caster's connection, the monotonic time it ends at, and its number for the
/// creature's life, which its timer is made from (`timer_id`).
pub type Control {
  Control(
    number: Int,
    state: CrowdControlState,
    cast_id: Int,
    instance_id: Int,
    caster: Address,
    ends_at_ms: Int,
  )
}

/// The states a creature holds, the number of its next control, and whether it has
/// logged that armor rules are not built.
pub opaque type State {
  State(controls: List(Control), next_number: Int, logged_armor: Bool)
}

/// What the feature asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer: its 0x87f or 0x880.
  ToViewers(news: News)
  StartTimer(timer: TimerId, after_ms: Int)
  CancelTimer(timer: TimerId)
  Log(level: LogLevel, text: String)
}

/// What a strike's states came to: the new state, the states that landed, as they were
/// told, for the answer's `Landed`, and the effects to carry out.
pub type Landing {
  Landing(state: State, landed: List(ControlTell), effects: List(Effect))
}

/// A creature that holds no state.
pub fn new() -> State {
  State(controls: [], next_number: 1, logged_armor: False)
}

/// Whether the creature holds a state, which stops it acting: the fight's gate
/// (genesis_prime/world_map/creature_fight `Fighter.controlled`).
pub fn holds(state state: State) -> Bool {
  state.controls != []
}

/// The strike's states land on a creature that `alive` after the strike and has
/// `armor`: with no armor each becomes a control ending `delay_ms` plus `duration_ms`
/// after `now_ms`, with a timer and its 0x87f (unit, state, instance id); with any
/// armor none lands, and the first time the creature logs that the armor rules are not
/// built. A dead creature takes none and logs nothing.
pub fn land(
  state state: State,
  tell tell: Tell,
  armor armor: InterruptArmor,
  alive alive: Bool,
  now_ms now_ms: Int,
) -> Landing {
  todo as "hold a control for each state of a living creature with no armor, start its timer, send its 0x87f"
}

/// The control numbered `number` ended: it is dropped and its viewers are sent the 0x880
/// (unit, state, cast id, instance id, 0). A number that names no control, because the
/// creature died or the control was ended already, does nothing.
pub fn ended(state state: State, number number: Int) -> #(State, List(Effect)) {
  todo as "drop the control and send its 0x880"
}

/// The creature died: every control is dropped and its timer cancelled, and no 0x880
/// is sent (`cc_state.end`).
pub fn died(state state: State) -> #(State, List(Effect)) {
  todo as "drop every control and cancel its timer"
}

/// The timer of the control numbered `number`: 4 times it plus 1, so a number from 1
/// gives 5, 9, 13 and none meets the corpse timer's 1 or a fight timer.
pub fn timer_id(number number: Int) -> TimerId {
  TimerId(4 * number + 1)
}

/// The number of the control a timer is for, or `Error(Nil)` for a timer that is not a
/// control's (the corpse timer's 1, a fight timer, or a number below 5).
pub fn number_of(timer timer: TimerId) -> Result(Int, Nil) {
  let TimerId(id) = timer
  case id >= 5 && id % 4 == 1 {
    True -> Ok({ id - 1 } / 4)
    False -> Error(Nil)
  }
}
