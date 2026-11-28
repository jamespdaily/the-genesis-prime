//// A creature's crowd-control states and its Interrupt Armor: the feature of the creature's
//// rule (genesis_prime/world_map/creature) that takes the states a caster's strike carries,
//// holds each for its time, wears the armor down and refills it, tells the unit's viewers
//// when one takes hold and ends, and tells the fight (genesis_prime/world_map/creature_fight)
//// whether the creature may act.
////
//// ```
//// caster's connection   creature (this feature)                                   viewers
//// Strike(.., controls) ─▶ `land`: at armor 0 a Control per state, with a timer;
////                         above 0 nothing lands, the rows' armor is destroyed,
////                         0x938 stat 21 ─────────────────────────────────────────▶ armor shown
////                         Answered(Landed(..)) ─▶ the caster's go lists the landed
////                         0x87f (unit, state, instance id) ──────────────────────▶ state on;
////                           the fight is held; a running path stops (0x638 of kind 2)
//// ... a control's timer ─▶ `ended`: 0x880 (unit, state, cast id, instance id, 0) ─▶ state off
//// ... the refill timer ─▶ `refilled`: 0x938 stat 21 at the maximum ───────────────▶ armor full
//// ```
////
//// - **Whether a state lands** is the server's rule (the client reads no Interrupt Armor in
////   any CC handler, `UnitProperty2.InterruptArmor_Threshold`): only at armor 0; above 0 the
////   rows' armor is destroyed (dataBits03, never below 0) with 0x938 stat 21 to the viewers.
//// - **Armor refills** to its maximum `interrupt_armor_refill_ms` after the strike that last
////   destroyed a point; the wait is a server choice (genesis_prime/world_map/game_number).
//// - **A change of the maximum** (a modifier on property 44) keeps armor and stat 21 one value:
////   full follows it, worn is clamped; a change is sent as 0x938 (`maximum_changed`).
//// - **How long** a state is held is the row's delay plus durationTime from the tell's
////   arrival, the server's choice (`cc_state.duration_on_creature`).
//// - **A state ends only by the server's 0x880** when its timer fires (`cc_state.end`,
////   `cc_state.instance_id`); a death sends none, the client clearing all states (`SetUnitDead`).
//// - **A cast pushed off the creature takes its states with it** (`ended_by`): each ends with
////   its own 0x880, timer cancelled, the client's node destruction (0x811) ending no state.
//// - **Knockdown is a stun for a creature**: the same flags; its only difference is a
////   player's dash (`GameFormula.614`, `CCStates.flags`).
//// - **What a held state stops** is the fight's to carry out (`Fighter`): `stops_moving` for
////   CCStates flags holding the value 2 (`UnitHasCCStateFlag02`, `0x14045e630`); `refuses` for
////   a state the attack spell's caster conditions mask (Spell4CCConditions ccStateMask);
////   `hard_held` for a Stun, Knockdown or Knockback (a retail record, WildStar wiki, Combat,
////   "Moment of Opportunity"); a charge starts only while no state is held (`holds`).
//// - **Each landed state is its own control**, with its own timer and its own 0x880, its
////   number from the creature's rule (`control_timer`), never used twice in a creature's life.

import genesis_prime/gap
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/shared/creature_combat.{type InterruptArmor}
import genesis_prime/shared/crowd_control
import genesis_prime/shared/lasts
import genesis_prime/shared/strike_tell.{
  type ControlLanded, type Tell, ControlLanded,
}
import genesis_prime/shared/unit_news.{type News}
import genesis_prime/step.{type Address}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

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

/// Whether the creature holds any state: the fight starts no charge while it does
/// (genesis_prime/world_map/creature_fight `Fighter.holds_a_state`).
pub fn holds(state state: State) -> Bool {
  state.controls != []
}

/// Whether the creature holds a state a mask names (bit n is state n): the check the
/// client makes of a caster's states against a spell's caster conditions
/// (`CheckSpellCCConditions`, `0x1403b2c40`), here for the creature's attack.
pub fn refuses(state state: State, mask mask: Int) -> Bool {
  list.map(state.controls, fn(control) { control.state })
  |> crowd_control.first_masked(mask:, held: _)
  |> result.is_ok
}

/// Whether the creature holds a state that stops it moving: one of the states in
/// `stopped_by`, the states whose CCStates flags hold the value 2
/// (genesis_prime/shared/crowd_control `stopping_mask`).
pub fn stops_moving(state state: State, stopped_by stopped_by: Int) -> Bool {
  refuses(state:, mask: stopped_by)
}

/// The states that let a creature cast nothing of any kind, as a mask (bit n is state n):
/// Stun 0, Knockdown 8 and Knockback 16.
///
/// A server choice from a retail record (WildStar wiki, Combat, "Moment of Opportunity"):
/// the client's rows say only what each spell's own conditions mask. CCStates flag 0x10,
/// set on Stun, Sleep, Knockdown, Knockback, Pull, Pushback, Hold, Disable and
/// DisableCinematic, is the likely client signal and is not decoded (fact
/// `CCStates.flags.hard_held`), so the choice stands.
const hard_held_mask = 0x10101

/// Whether the creature holds a state of `hard_held_mask`.
pub fn hard_held(state state: State) -> Bool {
  refuses(state:, mask: hard_held_mask)
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
    creature_combat.InfiniteArmor ->
      Landing(state:, landed: [], armor_removed: 0, effects: [])
    creature_combat.NoArmor -> held(state:, tell:, now_ms:)
    creature_combat.Armor(points: maximum) ->
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
        effects: [ToViewers(unit_news.InterruptArmor(armor: left)), ..restarted],
      )
    }
  }
}

/// Each state of the strike becomes a control, with its timer and its 0x87f.
fn held(state state: State, tell tell: Tell, now_ms now_ms: Int) -> Landing {
  let #(state, held) =
    list.map_fold(over: tell.controls, from: state, with: fn(state, told) {
      let hold_ms = case told.row.lasts {
        lasts.For(duration_ms:) -> told.row.delay_ms + duration_ms
        lasts.UntilRemoved ->
          panic as "the plan drops a control row that lasts until removed (spell_plan.control_of)"
      }
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
        #(
          ControlLanded(
            tell: told,
            ends_at_ms: control.ends_at_ms,
            interrupted: None,
          ),
          [
            ToViewers(unit_news.CrowdControlApplied(
              state: told.row.state,
              instance_id: told.instance_id,
            )),
            StartTimer(control: control.number, after_ms: hold_ms),
          ],
        ),
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
    Some(_), creature_combat.Armor(points:) -> #(State(..state, armor: None), [
      ToViewers(unit_news.InterruptArmor(armor: points)),
    ])
    Some(_), creature_combat.NoArmor | Some(_), creature_combat.InfiniteArmor -> #(
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
    creature_combat.Armor(points: maximum) ->
      Some(option.unwrap(state.armor, maximum))
    creature_combat.NoArmor | creature_combat.InfiniteArmor -> None
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
    creature_combat.Armor(points: maximum) ->
      State(..state, armor: option.map(state.armor, int.min(_, maximum)))
    creature_combat.NoArmor | creature_combat.InfiniteArmor -> state
  }
  let shown_after = shown(state:, armor: after)
  case shown_after == shown_before {
    True -> #(state, [])
    False -> #(state, [
      ToViewers(unit_news.InterruptArmor(armor: shown_after)),
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
        ToViewers(unit_news.CrowdControlEnded(
          state: control.state,
          cast_id: control.cast_id,
          instance_id: control.instance_id,
        )),
      ],
    )
  }
}

/// The caster at `caster` takes its cast `cast_id` off the creature: each state that cast
/// landed ends at once, in the order they landed, as a timer's end ends it (the viewers'
/// 0x880) with its timer cancelled. The client ends a state only by a 0x880
/// (`cc_state.end`), so a cast that leaves the creature while its state is held needs this
/// to take the state with it. A caster or cast that landed no state held changes nothing.
pub fn ended_by(
  state state: State,
  caster caster: Address,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  list.filter(state.controls, fn(control) {
    control.caster == caster && control.cast_id == cast_id
  })
  |> list.fold(#(state, []), fn(so_far, control) {
    let #(state, effects) = so_far
    let #(state, ending) = ended(state:, number: control.number)
    #(
      state,
      list.append(effects, [CancelTimer(control: control.number), ..ending]),
    )
  })
}

/// The creature died: every control is dropped and its timer cancelled, no 0x880 is sent
/// (`cc_state.end`), and its armor is back at the maximum with the refill timer cancelled,
/// as the creature's next life will be.
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

/// What a creature's held crowd-control states do not do that the client's rows ask for.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Creature crowd control",
      missing: "a charge of a creature that holds a crowd-control state: it starts only while no state is held, although the client's conditions for the charge spells mask nothing",
    ),
    gap.Entry(
      area: "Creature crowd control",
      missing: "a crowd-control state held by a creature when a viewer arrives: the viewer is not told of it, since the 0x262 does not carry it",
    ),
    gap.Entry(
      area: "Creature crowd control",
      missing: "the interrupt line of a creature's cast broken by a throw that carries no state: only a landed state is shown to its caster as the interrupter",
    ),
    gap.Entry(
      area: "Creature crowd control",
      missing: "the interrupt line for a player's own cancelled cast and for a creature that interrupts a player's cast: the client logs those only from a server line, and none is sent",
    ),
    gap.Entry(
      area: "Creature crowd control",
      missing: "the interrupt line when the creature's answer comes after the round's deadline: the go leaves that unit out and writes no line",
    ),
    gap.Entry(
      area: "Creature crowd control",
      missing: "the client's signal that a Stun, Knockdown or Knockback stops every cast (CCStates flag 0x10, not decoded): the server follows a retail record instead",
    ),
  ]
}
