//// A creature's crowd-control states and its Interrupt Armor: the feature of the
//// creature's rule (genesis_prime/world_map/creature) that takes the states a caster's
//// strike carries, holds each for its time, tells the creature's viewers when it takes
//// hold and when it ends, wears the armor down and refills it, and tells the fight
//// (genesis_prime/world_map/creature_fight) whether the creature may act. The creature's process owns its unit, its viewers and its timers,
//// so every 0x87f and 0x880 of the unit comes from its one owner, in the order the
//// states landed and ended.
////
//// ```
//// caster's connection        creature (this feature)                                   viewers
//// go phase: Strike(.., controls) ─▶ struck: the hit rule on health, then `land`
////                                   armor already 0: a Control for each state, a timer at its end
////                                   armor above 0: nothing lands, the row's armor is destroyed,
////                                     0x938 stat 21 ─────────────────────────────────────▶ armor shown
////                                     the refill timer starts again
////                                   Answered(Landed(.., controls landed)) ─▶ caster's go lists them
////                                   0x87f (unit, state, instance id) ──────────────────────▶ state on
////                                   the fight: no strike, chase or walk; a running path stops
////                                     (0x638 of kind 2)
//// ... a control's timer fires ─▶ `ended`
////                                   0x880 (unit, state, cast id, instance id, 0) ──────────▶ state off
////                                   the last one ended: the fight acts again from where it stands
//// ... the refill timer fires ─▶ `refilled`
////                                   0x938 stat 21 at the maximum ──────────────────────────▶ armor full
//// ```
////
//// - **Whether a state lands** is the server's rule: the client reads no Interrupt Armor
////   in any CC handler (`UnitProperty2.InterruptArmor_Threshold`). A living creature takes
////   the strike's states only when its current armor is already 0 when the strike
////   arrives (a maximum of 0 is always so). With armor above 0 the strike lands no state
////   and destroys the armor its rows name (dataBits03, never below 0), and the creature's
////   viewers get 0x938 stat 21 with the new value. Infinite armor (-1) takes no state
////   and loses nothing. Which of these the client shows is the stat and the maximum
////   (`opcode.0x938.interrupt_armor`).
//// - **Armor refills** to its maximum `interrupt_armor_refill_ms` after the strike that
////   last destroyed a point of it, with 0x938 stat 21 at the maximum: a strike that
////   destroys more starts the wait again, and one that lands a state at armor 0, or whose
////   rows destroy nothing, leaves it as it is. The time is a server choice
////   (genesis_prime/world_map/game_number): no client value says when armor returns. A
////   death resets it with the creature.
//// - **A change of the maximum** (a modifier on property 44) keeps the armor the controls
////   use and the stat 21 the viewers see one value: armor at full follows the new
////   maximum, armor worn down stays and is clamped to a lowered maximum, and a changed
////   value is sent as 0x938 (`maximum_changed`, `opcode.0x938.interrupt_armor`).
//// - **How long** a creature holds a state is the row's delay plus durationTime from the
////   tell's arrival: a creature's CC resilience is 0 and its duration modifier 1
////   (`cc_state.duration_on_creature`). Counting from the arrival is the server's choice:
////   the creature does not know when the go is written, which is later by the time the
////   round waited for answers, and the caster's node takes the creature's end time.
//// - **A state ends only by the server's 0x880**, which the creature sends when its timer
////   fires, naming the state, the cast and the instance id the go gave (`cc_state.end`,
////   `cc_state.instance_id`). A creature that dies sends none: the client clears every
////   state at a death (`SetUnitDead`).
//// - **Knockdown is a stun for a creature**: the same flags, and its only difference is
////   a player's dash (`GameFormula.614`, `CCStates.flags`).
//// - **Each landed state is its own control**, with its own timer and its own 0x880: two
////   players' states, or one caster's two states of a kind, are held side by side, and
////   the creature acts again when none is held (`cc_state.instance_id`).
//// - **A control's timer** is the creature's rule's to number (genesis_prime/world_map/creature
////   `control_timer`): one for each control's number, which is never used twice in a
////   creature's life. A timer that fires for a control already gone finds none and writes
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
//// | The maximum is raised or lowered by a modifier | the creature restarts at full armor of its own maximum | n/a | the refill timer fires after the change: the armor is back at the maximum then in force |
//// | Armor is worn down or refills | the creature restarts at full armor; the refill timer is cancelled at the death | two strikes in a row: each wears down what is left, the second restarts the refill | the refill timer fires after the death or at full armor: nothing |
//// | The caster's cast lingers past the state's end | the node's life is the effect's, and the cast rule's timer ends it (genesis_prime/game/lasting) | | |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/strike_tell.{
  type ControlLanded, type Tell, ControlLanded,
}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/step.{type Address}
import genesis_prime/world_map/creature_life.{type InterruptArmor}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// One state a creature holds: the state, the cast it came from (the strike's cast id,
/// which its 0x880 names), the instance id the caster's go gave it, the address of the
/// caster's connection, the monotonic time it ends at, and its number for the
/// creature's life, which its timer is made from.
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

/// The states a creature holds, the number of its next control, and its current
/// Interrupt Armor when it is below its maximum (none is the maximum: the state of a
/// creature no strike has worn down, or whose armor refilled).
pub opaque type State {
  State(controls: List(Control), next_number: Int, armor: Option(Int))
}

/// What the feature asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer: its 0x87f, 0x880 or 0x938 of stat 21.
  ToViewers(news: News)
  /// A timer for the control of this number, which the creature's rule makes an id of
  /// (genesis_prime/world_map/creature): it fires `ended`.
  StartTimer(control: Int, after_ms: Int)
  CancelTimer(control: Int)
  /// The refill timer of the creature's armor, which the creature's rule makes an id of:
  /// it fires `refilled`.
  StartRefill(after_ms: Int)
  CancelRefill
}

/// What a strike's states came to: the new state, the states that landed, each with the
/// time it ends at, for the answer's `Landed`, the armor the strike took off the creature
/// (at most the armor it had; the caster's combat log shows it), and the effects to carry
/// out.
pub type Landing {
  Landing(
    state: State,
    landed: List(ControlLanded),
    armor_removed: Int,
    effects: List(Effect),
  )
}

/// A creature that holds no state.
pub fn new() -> State {
  State(controls: [], next_number: 1, armor: None)
}

/// Whether the creature holds a state, which stops it acting: the fight's gate
/// (genesis_prime/world_map/creature_fight `Fighter.controlled`).
pub fn holds(state state: State) -> Bool {
  state.controls != []
}

/// Whether the creature holds anything a death must drop: a state, or armor worn below its
/// maximum with its refill waiting.
pub fn holds_anything(state state: State) -> Bool {
  state.controls != [] || option.is_some(state.armor)
}

/// The strike's states meet a living creature with this Interrupt Armor maximum: with
/// current armor of 0 each becomes a control ending `delay_ms` plus `duration_ms` after
/// `now_ms`, with a timer and its 0x87f (unit, state, instance id); with armor above 0
/// none lands and the rows' armor is destroyed instead (0x938 stat 21 with what is left);
/// with infinite armor none lands and nothing changes. A strike that destroys armor starts
/// the refill wait of `refill_ms` again; one that lands a state at armor 0 leaves the wait
/// as it is. The creature's rule asks only for a creature the strike left alive.
pub fn land(
  state state: State,
  tell tell: Tell,
  armor armor: InterruptArmor,
  refill_ms refill_ms: Int,
  now_ms now_ms: Int,
) -> Landing {
  case armor {
    creature_life.InfiniteArmor ->
      Landing(state:, landed: [], armor_removed: 0, effects: [])
    creature_life.NoArmor -> held(state:, tell:, now_ms:)
    creature_life.Armor(points: maximum) ->
      armored(state:, tell:, maximum:, refill_ms:, now_ms:)
  }
}

/// A strike's states meet armor with this maximum: at 0 they land and a refill already
/// waiting is left alone; above 0 none lands and the rows' armor is destroyed, never below
/// 0, which starts the refill wait again; rows that destroy nothing change nothing.
fn armored(
  state state: State,
  tell tell: Tell,
  maximum maximum: Int,
  refill_ms refill_ms: Int,
  now_ms now_ms: Int,
) -> Landing {
  let current = option.unwrap(state.armor, maximum)
  let restarted = case state.armor {
    Some(_) -> [CancelRefill, StartRefill(after_ms: refill_ms)]
    None -> [StartRefill(after_ms: refill_ms)]
  }
  let destroyed =
    int.sum(list.map(tell.controls, fn(told) { told.row.armor_removed }))
  case current, destroyed {
    0, _ -> held(state:, tell:, now_ms:)
    _, 0 -> Landing(state:, landed: [], armor_removed: 0, effects: [])
    _, _ -> {
      let left = int.max(0, current - destroyed)
      Landing(
        state: State(..state, armor: Some(left)),
        landed: [],
        armor_removed: current - left,
        effects: [
          ToViewers(client_connection.InterruptArmor(armor: left)),
          ..restarted
        ],
      )
    }
  }
}

/// Each state of the strike becomes a control, with its timer and its 0x87f.
fn held(state state: State, tell tell: Tell, now_ms now_ms: Int) -> Landing {
  let #(state, held) =
    list.map_fold(over: tell.controls, from: state, with: fn(state, told) {
      let hold_ms = told.row.delay_ms + told.row.duration_ms
      let control =
        Control(
          number: state.next_number,
          state: told.row.state,
          cast_id: tell.key.cast_id,
          instance_id: told.instance_id,
          caster: tell.from,
          ends_at_ms: now_ms + hold_ms,
        )
      #(
        State(
          ..state,
          controls: list.append(state.controls, [control]),
          next_number: state.next_number + 1,
        ),
        #(ControlLanded(tell: told, ends_at_ms: control.ends_at_ms), [
          ToViewers(client_connection.CrowdControlApplied(
            state: told.row.state,
            instance_id: told.instance_id,
          )),
          StartTimer(control: control.number, after_ms: hold_ms),
        ]),
      )
    })
  Landing(
    state:,
    landed: list.map(held, fn(one) { one.0 }),
    armor_removed: 0,
    effects: list.flat_map(held, fn(one) { one.1 }),
  )
}

/// The refill timer fired: the armor is back at its maximum `armor`, which the viewers
/// are sent (0x938 stat 21). A timer that fires when the armor is already full, because
/// the creature died or it refilled, does nothing.
pub fn refilled(
  state state: State,
  armor armor: InterruptArmor,
) -> #(State, List(Effect)) {
  case state.armor, armor {
    Some(_), creature_life.Armor(points:) -> #(State(..state, armor: None), [
      ToViewers(client_connection.InterruptArmor(armor: points)),
    ])
    Some(_), creature_life.NoArmor | Some(_), creature_life.InfiniteArmor -> #(
      State(..state, armor: None),
      [],
    )
    None, _ -> #(state, [])
  }
}

/// The current Interrupt Armor a creature's 0x262 carries as stat 21: its points when it
/// has armor above 0 (the maximum, or less after a strike), none for a creature with no
/// armor or infinite armor. The client's maximum is its own property
/// (`UnitProperty2.InterruptArmor_Threshold`), and the create's stat list sets the same
/// stat as a 0x938 (`opcode.0x938.interrupt_armor`). What the client's unit holds in stat
/// 21 when the list has none is not read: it is taken to be 0, which is right for a
/// creature with none and unread for one with infinite armor, whose value the client does
/// not clamp.
pub fn armor_now(
  state state: State,
  armor armor: InterruptArmor,
) -> Option(Int) {
  case armor {
    creature_life.Armor(points: maximum) ->
      Some(option.unwrap(state.armor, maximum))
    creature_life.NoArmor | creature_life.InfiniteArmor -> None
  }
}

/// The creature's Interrupt Armor maximum (property 44) changed from `before` to
/// `after`: armor at full stays full at the new maximum, armor worn down stays as it is
/// and is clamped to a lowered maximum, so the armor the controls use is always the
/// stat 21 the viewers are shown (`opcode.0x938.interrupt_armor`). The viewers are
/// sent 0x938 of the new value whenever it differs from the one they were shown (none
/// for a creature without armor counts as 0).
pub fn maximum_changed(
  state state: State,
  before before: InterruptArmor,
  after after: InterruptArmor,
) -> #(State, List(Effect)) {
  let shown_before = shown(state:, armor: before)
  let state = case after {
    creature_life.Armor(points: maximum) ->
      State(..state, armor: option.map(state.armor, int.min(_, maximum)))
    creature_life.NoArmor | creature_life.InfiniteArmor -> state
  }
  let shown_after = shown(state:, armor: after)
  case shown_after == shown_before {
    True -> #(state, [])
    False -> #(state, [
      ToViewers(client_connection.InterruptArmor(armor: shown_after)),
    ])
  }
}

/// The stat 21 the viewers hold for a creature with this maximum: its current armor, 0
/// for a creature with none or infinite armor.
fn shown(state state: State, armor armor: InterruptArmor) -> Int {
  option.unwrap(armor_now(state:, armor:), 0)
}

/// The control numbered `number` ended: it is dropped and its viewers are sent the 0x880
/// (unit, state, cast id, instance id, 0). A number that names no control, because the
/// creature died or the control was ended already, does nothing.
pub fn ended(state state: State, number number: Int) -> #(State, List(Effect)) {
  case list.find(state.controls, fn(control) { control.number == number }) {
    Error(Nil) -> #(state, [])
    Ok(control) -> #(
      State(
        ..state,
        controls: list.filter(state.controls, fn(held) { held.number != number }),
      ),
      [
        ToViewers(client_connection.CrowdControlEnded(
          state: control.state,
          cast_id: control.cast_id,
          instance_id: control.instance_id,
        )),
      ],
    )
  }
}

/// The creature died: every control is dropped and its timer cancelled, no 0x880 is sent
/// (`cc_state.end`), and its armor is back at the maximum with the refill timer cancelled,
/// as the creature that stands again will be.
pub fn died(state state: State) -> #(State, List(Effect)) {
  #(
    State(..state, controls: [], armor: None),
    list.append(
      list.map(state.controls, fn(control) {
        CancelTimer(control: control.number)
      }),
      case state.armor {
        Some(_) -> [CancelRefill]
        None -> []
      },
    ),
  )
}
