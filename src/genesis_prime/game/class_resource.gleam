//// A player's class resource, a feature of the game connection's rule
//// (genesis_prime/game/connection) kept beside its life (genesis_prime/game/player_life):
//// the one resource slot its class's bar shows, as the client holds it, what a cast
//// pays from it, and its refill over time. The client changes no slot itself
//// (`0x140454380`): the server sets each by the 0x262's stats and by 0x935, so every
//// change here is a 0x935 the connection writes to the player's own client.
////
//// ```
//// entry ─▶ new(the class's resource): the slot at its start ─▶ the 0x262's stat slot + 2 (float) and ResourceMax_slot
//// a cast's first go (genesis_prime/game/cast Pay) ─▶ pay ─▶ Changed(slot, value)         ─▶ 0x935 to the player
////                                                 a slot that refills over time: StartTimer(regen_timer, tick)
////                                                 a Medic out of combat: StartTimer(refill_timer, 3000)
//// a go's gains (genesis_prime/game/cast Gain) ─▶ gain ─▶ Changed, clamped to the max
////                                                 a Warrior: CancelTimer(drain_timer), StartTimer(drain_timer, 1500)
//// regen_timer ─▶ + per tick, clamped to the max ─▶ Changed; below the max again ─▶ StartTimer(regen_timer)
//// drain_timer ─▶ - per tick, clamped to 0 ─▶ Changed; above 0 still ─▶ StartTimer(drain_timer, tick)
//// the combat flag clears (player_life) ─▶ a Medic below its max: StartTimer(refill_timer)
////                                         an Esper above 0: StartTimer(empty_timer, 10000)
////                                         an Engineer above 0: StartTimer(empty_timer, 5000)
//// the combat flag sets ─▶ CancelTimer(refill_timer), CancelTimer(empty_timer)
//// refill_timer ─▶ the slot at its max ─▶ Changed
//// empty_timer ─▶ the slot at 0 ─▶ Changed
//// died ─▶ every timer cancelled;  came_back ─▶ the slot at its start ─▶ Changed when it moved
//// ```
////
//// - **The slot** a class's resource lives in is the one its bar reads: 1 for the
////   Warrior, Engineer, Esper and Medic, 3 for the Stalker, 4 for the Spellslinger
////   (`0x14064fdb0`). A slot the class does not hold stays 0 with a maximum of 0
////   (`0x140454380`, `UnitProperty2.ResourceMax_0`).
//// - **The start** is the client's text: the Medic's, Stalker's and Spellslinger's
////   start full, the Warrior's, Engineer's and Esper's empty
////   (`LocalizedEnum.CRB_StalkerResource`).
//// - **The maximum and the refill** are content rows the client lacks
////   (`UnitProperty2.ResourceMax_0`), each with its source (migrations 0011, 0012 and
////   0018): the load refuses a playable class with no maximum, and a class with a row of
////   its refill missing (`select`): the Warrior's drain, the Engineer's and Esper's empty
////   wait, the Medic's refill after combat, and the Stalker's and Spellslinger's
////   regeneration.
//// - **The value** is held as the 32-bit float the client holds, so a check here and
////   the client's own read the same number.
//// - **Paying** is at the cast's first go, which is the accept's own step for a spell
////   that goes at once (genesis_prime/game/cast). Until then the slot holds the points
////   the cast has reserved, so each timer below sees them as held.
//// - **Gaining** is at a go, by the VitalModifiers the cast rule gives
////   (`Spell4Effects.effectType.1`): the client applies none itself, so each is the
////   server's to apply and send, clamped to [0, max].
//// - **The Warrior's drain** takes `drain_amount` each `drain_period_ms`, ticked
////   each `drain_tick_ms`, from `drain_after_ms` after the last gain, in and out of
////   combat, down to 0 (Jim's choice, migration 0012; 500714 gives no rate).
//// - **The Esper's empty** sets the slot to 0 `empty_after_combat_ms` after it
////   leaves combat, and combat again stops the wait (a retail record, migration
////   0012; 500718). **The Engineer's Volatility** goes the same way, after 5000 ms
////   (the server's choice from the rows of Volatility Resource Control, which lets all of
////   it go in one step 5 to 6 s after combat: migration 0018, `Spell4.34630`; 472510
////   and 500719 say it dissipates out of combat). A gain out of combat starts the
////   wait at once, and combat again stops it.
//// - **Over time** the refill ticks each `regen_tick_ms`, in and out of combat; the
////   Medic's slot fills to its max `refill_after_combat_ms` after it is out of
////   combat, from the combat flag clearing or from a payment made out of combat (the
////   server's choice: "regenerate while out of combat", 500710). A full slot sends
////   nothing.
//// - **Death** stops every timer; **coming back** sets the slot to its start (the
////   server's choice, as health and shield come back full). The resources are not
////   saved: each entry starts at the start.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/message/float32
import genesis_prime/step.{type TimerId, TimerId}
import genesis_prime/table/id.{type ClassId, ClassId}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Where a class's resource starts at entry, by the client's text
/// (`LocalizedEnum.CRB_StalkerResource`).
type Start {
  Empty
  Full
}

/// What a class's resource is: the slot it lives in, its maximum, its start, and
/// how it refills over time.
pub type Resource {
  Resource(
    slot: Int,
    max: Float,
    start: Float,
    /// The refill each tick, in and out of combat; none for a class whose
    /// resource does not refill over time.
    regen: Option(Regen),
    /// How long after leaving combat the slot fills to its max; none for a class
    /// that has no such refill.
    refill_after_combat_ms: Option(Int),
    /// The drain after a gain; none for a class whose resource does not drain.
    drain: Option(Drain),
    /// How long after leaving combat the slot goes to 0; none for a class whose
    /// resource keeps its value out of combat.
    empty_after_combat_ms: Option(Int),
  )
}

/// A refill over time: `per_tick` points each `tick_ms`.
pub type Regen {
  Regen(per_tick: Float, tick_ms: Int)
}

/// A drain over time: `per_tick` points each `tick_ms`, from `after_ms` after the
/// last gain.
pub type Drain {
  Drain(per_tick: Float, tick_ms: Int, after_ms: Int)
}

/// The resource of each playable class, by its Class id, as the load selected it.
pub opaque type Classes {
  Classes(by_class: Dict(Int, Resource))
}

/// The resource of a class, or `Error(Nil)` for a class that is not playable.
pub fn of_class(
  classes classes: Classes,
  class_id class_id: ClassId,
) -> Result(Resource, Nil) {
  let ClassId(id) = class_id
  dict.get(classes.by_class, id)
}

/// One row of the class_resource table as the load reads it: a number of a class's
/// resource, by its name, with its unit.
pub type Row {
  Row(class_id: Int, name: String, value: Float, unit: String)
}

/// How a class's resource changes with no press, which decides the rows it needs.
type Refill {
  /// The slot drains each tick after its last gain: the amount, its period, the
  /// tick and the wait.
  DrainAfterGain
  /// The slot goes to 0 a while after combat: the wait.
  EmptyAfterCombat
  /// A regeneration each tick, in and out of combat: the amount, its period and
  /// the tick.
  OverTime
  /// The slot fills to its maximum a while after combat: the wait.
  AfterCombat
}

/// The playable classes, by Class id, with the slot each one's bar reads
/// (`0x14064fdb0`), its start (`LocalizedEnum.CRB_StalkerResource`) and how it
/// refills (the design): Warrior, Engineer, Esper, Medic, Stalker and Spellslinger.
const playable = [
  #(1, #(1, Empty, DrainAfterGain)),
  #(2, #(1, Empty, EmptyAfterCombat)),
  #(3, #(1, Empty, EmptyAfterCombat)),
  #(4, #(1, Full, AfterCombat)),
  #(5, #(3, Full, OverTime)),
  #(7, #(4, Full, OverTime)),
]

/// The Class ids of the playable classes: Warrior, Engineer, Esper, Medic, Stalker
/// and Spellslinger.
pub fn playable_class_ids() -> List(Int) {
  list.map(playable, fn(class) { class.0 })
}

/// Each number the rule reads, by name. The table holds each name's unit, a
/// value above 0 and a whole number of milliseconds for a time
/// (`class_resource_name_has_its_unit`, `class_resource_value_is_positive` and
/// `class_resource_time_is_whole_ms`, migration 0014).
const expected = [
  "max",
  "regen_amount",
  "regen_period_ms",
  "regen_tick_ms",
  "refill_after_combat_ms",
  "drain_amount",
  "drain_period_ms",
  "drain_tick_ms",
  "drain_after_ms",
  "empty_after_combat_ms",
]

/// The numbers a class's refill needs.
fn needed(refill refill: Refill) -> List(String) {
  case refill {
    OverTime -> ["max", "regen_amount", "regen_period_ms", "regen_tick_ms"]
    AfterCombat -> ["max", "refill_after_combat_ms"]
    DrainAfterGain -> [
      "max",
      "drain_amount",
      "drain_period_ms",
      "drain_tick_ms",
      "drain_after_ms",
    ]
    EmptyAfterCombat -> ["max", "empty_after_combat_ms"]
  }
}

/// The classes' resources of the rows, or every refusal: a class that is not
/// playable, a name not known, and a number a playable class needs that has no row
/// (its maximum, and the amount, period and tick of a refill over time, the wait
/// of a refill after combat, the amount, period, tick and wait of a drain, and the
/// wait of an empty after combat).
pub fn select(rows rows: List(Row)) -> Result(Classes, List(Refusal)) {
  let unknown =
    list.filter_map(rows, fn(row) {
      case
        list.key_find(playable, row.class_id),
        list.contains(expected, row.name)
      {
        Error(Nil), _ ->
          Ok(refused(
            class_id: row.class_id,
            name: row.name,
            rule: "the server knows no playable class of that id",
          ))
        _, False ->
          Ok(refused(
            class_id: row.class_id,
            name: row.name,
            rule: "the server knows no such number",
          ))
        Ok(..), True -> Error(Nil)
      }
    })
  let by_class = list.group(rows, fn(row) { row.class_id })
  let missing =
    list.flat_map(playable, fn(class) {
      let #(class_id, #(_, _, refill)) = class
      let named = dict.get(by_class, class_id) |> result.unwrap([])
      list.filter_map(needed(refill:), fn(name) {
        case list.any(named, fn(row) { row.name == name }) {
          True -> Error(Nil)
          False ->
            Ok(refused(
              class_id:,
              name:,
              rule: "the table has no such row, which this class needs",
            ))
        }
      })
    })
  case list.append(unknown, missing) {
    [_, ..] as refusals -> Error(refusals)
    [] ->
      Ok(Classes(
        by_class: list.map(playable, fn(class) {
          let #(class_id, #(slot, start, _)) = class
          let named = dict.get(by_class, class_id) |> result.unwrap([])
          #(class_id, resource_of(named:, slot:, start:))
        })
        |> dict.from_list,
      ))
  }
}

fn resource_of(
  named named: List(Row),
  slot slot: Int,
  start start: Start,
) -> Resource {
  let value = fn(name) {
    list.find(named, fn(row) { row.name == name })
    |> result.map(fn(row) { row.value })
  }
  let max = value("max") |> result.unwrap(0.0)
  let regen = case
    value("regen_amount"),
    value("regen_period_ms"),
    value("regen_tick_ms")
  {
    Ok(amount), Ok(period_ms), Ok(tick_ms) ->
      Some(Regen(
        per_tick: amount *. tick_ms /. period_ms,
        tick_ms: float.truncate(tick_ms),
      ))
    _, _, _ -> None
  }
  let drain = case
    value("drain_amount"),
    value("drain_period_ms"),
    value("drain_tick_ms"),
    value("drain_after_ms")
  {
    Ok(amount), Ok(period_ms), Ok(tick_ms), Ok(after_ms) ->
      Some(Drain(
        per_tick: amount *. tick_ms /. period_ms,
        tick_ms: float.truncate(tick_ms),
        after_ms: float.truncate(after_ms),
      ))
    _, _, _, _ -> None
  }
  Resource(
    slot:,
    max:,
    start: case start {
      Empty -> 0.0
      Full -> max
    },
    regen:,
    refill_after_combat_ms: value("refill_after_combat_ms")
      |> result.map(float.truncate)
      |> option.from_result,
    drain:,
    empty_after_combat_ms: value("empty_after_combat_ms")
      |> result.map(float.truncate)
      |> option.from_result,
  )
}

fn refused(
  class_id class_id: Int,
  name name: String,
  rule rule: String,
) -> Refusal {
  Refusal(
    table: "class_resource",
    row: RowName(int.to_string(class_id) <> " " <> name),
    rule:,
  )
}

/// A player's resource now: its class's, the slot's value, whether the player is in
/// combat and alive, and which of its timers runs.
pub opaque type Resources {
  Resources(
    resource: Resource,
    value: Float,
    in_combat: Bool,
    alive: Bool,
    regen_running: Bool,
    refill_running: Bool,
    drain_running: Bool,
    empty_running: Bool,
  )
}

/// A cost the cast rule took at an accept: `amount` points of the resource slot
/// `slot`.
pub type Payment {
  Payment(slot: Int, amount: Int)
}

/// A gain the cast rule gave at a go: `amount` points into the resource slot
/// `slot` (`Spell4Effects.effectType.1`).
pub type Gain {
  Gain(slot: Int, amount: Int)
}

/// What the rule asks the connection to do, in order.
pub type Effect {
  /// The slot now holds `value`: 0x935 of the player's own unit, stat slot + 2.
  Changed(slot: Int, value: Float)
  StartTimer(timer: TimerId, after_ms: Int)
  CancelTimer(timer: TimerId)
}

/// The timer of the refill over time; the connection's own timers are below the
/// cast rule's (genesis_prime/game/cast `owns`), and the save, claim and strike
/// timers take 1 to 3.
pub const regen_timer = TimerId(4)

/// The timer of the Medic's refill after combat.
pub const refill_timer = TimerId(5)

/// The timer of the Warrior's drain: its wait after a gain, then each tick.
pub const drain_timer = TimerId(6)

/// The timer of the Esper's empty after combat.
pub const empty_timer = TimerId(7)

/// Whether the timer is one of this rule's, for the connection to hand it to
/// `timer_fired`.
pub fn owns(timer timer: TimerId) -> Bool {
  timer == regen_timer
  || timer == refill_timer
  || timer == drain_timer
  || timer == empty_timer
}

/// A player entering the world: alive, out of combat, its slot at its start.
pub fn new(resource resource: Resource) -> Resources {
  Resources(
    resource:,
    value: float32.rounded(resource.start),
    in_combat: False,
    alive: True,
    regen_running: False,
    refill_running: False,
    drain_running: False,
    empty_running: False,
  )
}

/// The resource slot the class holds.
pub fn slot(resources resources: Resources) -> Int {
  resources.resource.slot
}

/// The value of the resource slot `slot`: 0 for one the class does not hold.
pub fn value(resources resources: Resources, slot slot: Int) -> Float {
  use <- bool.guard(when: slot != resources.resource.slot, return: 0.0)
  resources.value
}

/// The maximum of the resource slot `slot`: 0 for one the class does not hold.
pub fn max(resources resources: Resources, slot slot: Int) -> Float {
  use <- bool.guard(when: slot != resources.resource.slot, return: 0.0)
  resources.resource.max
}

/// The resources with the payments taken, and nothing else: what the cast rule
/// checks a second press of the same step against.
pub fn paid(
  resources resources: Resources,
  payments payments: List(Payment),
) -> Resources {
  list.fold(payments, resources, fn(resources, payment) {
    case payment.slot == resources.resource.slot {
      True ->
        Resources(
          ..resources,
          value: clamped(
            resources:,
            value: resources.value
              -. int.to_float(int.absolute_value(payment.amount)),
          ),
        )
      False -> resources
    }
  })
}

/// The payments taken: a change for each one of the class's slot, then the timers
/// a slot below its max starts.
pub fn pay(
  resources resources: Resources,
  payments payments: List(Payment),
) -> #(Resources, List(Effect)) {
  let #(resources, changes) =
    list.fold(payments, #(resources, []), fn(so_far, payment) {
      let #(resources, changes) = so_far
      case payment.slot == resources.resource.slot {
        False -> so_far
        True -> {
          let resources = paid(resources:, payments: [payment])
          #(resources, [
            Changed(slot: payment.slot, value: resources.value),
            ..changes
          ])
        }
      }
    })
  let #(resources, timers) = refills(resources:)
  #(resources, list.append(list.reverse(changes), timers))
}

/// The gains of a go: a change for each one of the class's slot that moves it,
/// clamped to [0, max], then the drain's wait restarted for a class that drains,
/// then the timers a living slot starts (`refills`). A dead player gains nothing.
pub fn gain(
  resources resources: Resources,
  gains gains: List(Gain),
) -> #(Resources, List(Effect)) {
  let own =
    list.filter(gains, fn(gain) { gain.slot == resources.resource.slot })
  use <- bool.guard(
    when: !resources.alive || own == [],
    return: #(resources, []),
  )
  let #(resources, changes) =
    list.fold(own, #(resources, []), fn(so_far, gain) {
      let #(resources, changes) = so_far
      let next =
        clamped(resources:, value: resources.value +. int.to_float(gain.amount))
      let changes = case next == resources.value {
        True -> changes
        False -> [Changed(slot: gain.slot, value: next), ..changes]
      }
      #(Resources(..resources, value: next), changes)
    })
  let #(resources, drain) = case resources.resource.drain {
    Some(Drain(after_ms:, ..)) -> #(
      Resources(..resources, drain_running: True),
      list.append(
        case resources.drain_running {
          True -> [CancelTimer(timer: drain_timer)]
          False -> []
        },
        [StartTimer(timer: drain_timer, after_ms:)],
      ),
    )
    None -> #(resources, [])
  }
  let #(resources, timers) = refills(resources:)
  #(resources, list.flatten([list.reverse(changes), drain, timers]))
}

/// The timers a living slot starts when none of them runs: below its max, the
/// refill over time and the Medic's refill when out of combat; above 0 and out of
/// combat, the Esper's empty wait.
fn refills(resources resources: Resources) -> #(Resources, List(Effect)) {
  use <- bool.guard(when: !resources.alive, return: #(resources, []))
  let #(resources, below_max) = case
    resources.value >=. resources.resource.max
  {
    True -> #(resources, [])
    False -> {
      let #(resources, regen) = case resources.resource.regen {
        Some(Regen(tick_ms:, ..)) if !resources.regen_running -> #(
          Resources(..resources, regen_running: True),
          [StartTimer(timer: regen_timer, after_ms: tick_ms)],
        )
        Some(..) | None -> #(resources, [])
      }
      let #(resources, refill) = case
        resources.resource.refill_after_combat_ms
      {
        Some(after_ms) if !resources.in_combat && !resources.refill_running -> #(
          Resources(..resources, refill_running: True),
          [StartTimer(timer: refill_timer, after_ms:)],
        )
        Some(..) | None -> #(resources, [])
      }
      #(resources, list.append(regen, refill))
    }
  }
  let #(resources, emptying) = case resources.resource.empty_after_combat_ms {
    Some(after_ms)
      if !resources.in_combat
      && resources.value >. 0.0
      && !resources.empty_running
    -> #(Resources(..resources, empty_running: True), [
      StartTimer(timer: empty_timer, after_ms:),
    ])
    Some(_) | None -> #(resources, [])
  }
  #(resources, list.append(below_max, emptying))
}

/// A timer of the rule fired: a tick of the refill over time, the Medic's refill, a
/// tick of the Warrior's drain, or the Esper's empty. A timer that fires after its
/// cancel, or after death, changes nothing.
pub fn timer_fired(
  resources resources: Resources,
  timer timer: TimerId,
) -> #(Resources, List(Effect)) {
  case resources.resource {
    Resource(regen: Some(Regen(per_tick:, ..)), ..)
      if timer == regen_timer && resources.regen_running
    ->
      changed_to(
        resources: Resources(..resources, regen_running: False),
        value: resources.value +. per_tick,
      )
    Resource(refill_after_combat_ms: Some(_), ..)
      if timer == refill_timer && resources.refill_running
    ->
      changed_to(
        resources: Resources(..resources, refill_running: False),
        value: resources.resource.max,
      )
    Resource(drain: Some(Drain(per_tick:, tick_ms:, ..)), ..)
      if timer == drain_timer && resources.drain_running
    -> {
      let #(resources, effects) =
        changed_to(
          resources: Resources(..resources, drain_running: False),
          value: resources.value -. per_tick,
        )
      case resources.value >. 0.0 {
        True -> #(
          Resources(..resources, drain_running: True),
          list.append(effects, [
            StartTimer(timer: drain_timer, after_ms: tick_ms),
          ]),
        )
        False -> #(resources, effects)
      }
    }
    Resource(empty_after_combat_ms: Some(_), ..)
      if timer == empty_timer && resources.empty_running
    ->
      changed_to(
        resources: Resources(..resources, empty_running: False),
        value: 0.0,
      )
    Resource(..) -> #(resources, [])
  }
}

/// The slot set to `value`, clamped to [0, max] and held as a 32-bit float: a
/// change when it moved, then the timers a living slot starts (`refills`).
fn changed_to(
  resources resources: Resources,
  value value: Float,
) -> #(Resources, List(Effect)) {
  let next = clamped(resources:, value:)
  let change = case next == resources.value {
    True -> []
    False -> [Changed(slot: resources.resource.slot, value: next)]
  }
  let #(resources, timers) =
    refills(resources: Resources(..resources, value: next))
  #(resources, list.append(change, timers))
}

fn clamped(resources resources: Resources, value value: Float) -> Float {
  float32.rounded(float.clamp(value, min: 0.0, max: resources.resource.max))
}

/// The player's combat flag changed (genesis_prime/game/player_life): in combat the
/// Medic's refill and the Esper's empty wait no longer; out of it, `refills` starts
/// them.
pub fn combat_changed(
  resources resources: Resources,
  in_combat in_combat: Bool,
) -> #(Resources, List(Effect)) {
  let resources = Resources(..resources, in_combat:)
  case in_combat {
    True -> {
      let refill = case resources.refill_running {
        True -> [CancelTimer(timer: refill_timer)]
        False -> []
      }
      let empty = case resources.empty_running {
        True -> [CancelTimer(timer: empty_timer)]
        False -> []
      }
      #(
        Resources(..resources, refill_running: False, empty_running: False),
        list.append(refill, empty),
      )
    }
    False -> refills(resources:)
  }
}

/// The player died: every timer is cancelled, and nothing is sent.
pub fn died(resources resources: Resources) -> #(Resources, List(Effect)) {
  let #(resources, cancels) = left(resources:)
  #(Resources(..resources, alive: False, in_combat: False), cancels)
}

/// The player came back: the slot is set to its start, with a change when it moved.
pub fn came_back(resources resources: Resources) -> #(Resources, List(Effect)) {
  changed_to(
    resources: Resources(..resources, alive: True),
    value: resources.resource.start,
  )
}

/// The player left the world, or its connection ended: every timer is cancelled,
/// and nothing is sent.
pub fn left(resources resources: Resources) -> #(Resources, List(Effect)) {
  let regen = case resources.regen_running {
    True -> [CancelTimer(timer: regen_timer)]
    False -> []
  }
  let refill = case resources.refill_running {
    True -> [CancelTimer(timer: refill_timer)]
    False -> []
  }
  let drain = case resources.drain_running {
    True -> [CancelTimer(timer: drain_timer)]
    False -> []
  }
  let empty = case resources.empty_running {
    True -> [CancelTimer(timer: empty_timer)]
    False -> []
  }
  #(
    Resources(
      ..resources,
      regen_running: False,
      refill_running: False,
      drain_running: False,
      empty_running: False,
    ),
    list.flatten([regen, refill, drain, empty]),
  )
}
