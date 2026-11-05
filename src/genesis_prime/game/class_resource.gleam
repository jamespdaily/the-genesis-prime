//// A player's class resource, a feature of the game connection's rule
//// (genesis_prime/game/connection) kept beside its life (genesis_prime/game/player_life):
//// the one resource slot its class's bar shows, as the client holds it, what a cast
//// pays from it, and its refill over time. The client changes no slot itself
//// (`0x140454380`): the server sets each by the 0x262's stats and by 0x935, so every
//// change here is a 0x935 the connection writes to the player's own client.
////
//// ```
//// entry ─▶ new(the class's resource): the slot at its start ─▶ the 0x262's stat slot + 2 (float) and ResourceMax_slot
//// a cast accepted (genesis_prime/game/cast Pay) ─▶ pay ─▶ Changed(slot, value)            ─▶ 0x935 to the player
////                                                 a slot that refills over time: StartTimer(regen_timer, tick)
////                                                 a Medic out of combat: StartTimer(refill_timer, 3000)
//// regen_timer ─▶ + per tick, clamped to the max ─▶ Changed; below the max again ─▶ StartTimer(regen_timer)
//// the combat flag clears (player_life) ─▶ a Medic below its max: StartTimer(refill_timer)
//// the combat flag sets ─▶ CancelTimer(refill_timer)
//// refill_timer ─▶ the slot at its max ─▶ Changed
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
////   (`UnitProperty2.ResourceMax_0`), each with its source (migration 0011): the
////   load refuses a playable class with no maximum (`select`).
//// - **The value** is held as the 32-bit float the client holds, so a check here and
////   the client's own read the same number.
//// - **Paying** is at the accept, in the step of the cost check (genesis_prime/game/cast).
//// - **Over time** the refill ticks each `regen_tick_ms`, in and out of combat; the
////   Medic's slot fills to its max `refill_after_combat_ms` after it is out of
////   combat, from the combat flag clearing or from a payment made out of combat (the
////   server's choice: "regenerate while out of combat", 500710). A full slot sends
////   nothing.
//// - **Death** stops both timers; **coming back** sets the slot to its start (the
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
  )
}

/// A refill over time: `per_tick` points each `tick_ms`.
pub type Regen {
  Regen(per_tick: Float, tick_ms: Int)
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

/// The playable classes, by Class id, with the slot each one's bar reads
/// (`0x14064fdb0`) and its start (`LocalizedEnum.CRB_StalkerResource`): Warrior,
/// Engineer, Esper, Medic, Stalker and Spellslinger.
const playable = [
  #(1, #(1, Empty)),
  #(2, #(1, Empty)),
  #(3, #(1, Empty)),
  #(4, #(1, Full)),
  #(5, #(3, Full)),
  #(7, #(4, Full)),
]

/// Each number the rule reads, by name, with its unit.
const expected = [
  #("max", "points"),
  #("regen_amount", "points"),
  #("regen_period_ms", "ms"),
  #("regen_tick_ms", "ms"),
  #("refill_after_combat_ms", "ms"),
]

/// The parts of a refill over time, which a row holds all of or none of.
const regen_names = ["regen_amount", "regen_period_ms", "regen_tick_ms"]

/// The classes' resources of the rows, or every refusal: a class that is not
/// playable, a name not known, a unit not the name's, a playable class with no
/// max, a refill with a part missing, a number not above 0, and a time that is not
/// a whole number of milliseconds.
pub fn select(rows rows: List(Row)) -> Result(Classes, List(Refusal)) {
  let unknown =
    list.filter_map(rows, fn(row) {
      case
        list.key_find(playable, row.class_id),
        list.key_find(expected, row.name)
      {
        Error(Nil), _ ->
          Ok(refused(
            row:,
            rule: "the server knows no playable class of that id",
          ))
        _, Error(Nil) ->
          Ok(refused(row:, rule: "the server knows no such number"))
        Ok(..), Ok(unit) if unit != row.unit ->
          Ok(refused(row:, rule: "its unit is " <> row.unit <> ", not " <> unit))
        Ok(..), Ok(..) -> checked_value(row:)
      }
    })
  let by_class = list.group(rows, fn(row) { row.class_id })
  let missing =
    list.flat_map(playable, fn(class) {
      let named = dict.get(by_class, class.0) |> result.unwrap([])
      let has = fn(name) { list.any(named, fn(row) { row.name == name }) }
      let max = case has("max") {
        True -> []
        False -> [
          refused(
            row: Row(class_id: class.0, name: "max", value: 0.0, unit: "points"),
            rule: "the table has no such row, which every playable class needs",
          ),
        ]
      }
      let regen = case list.any(regen_names, has), list.all(regen_names, has) {
        True, False ->
          list.filter_map(regen_names, fn(name) {
            case has(name) {
              True -> Error(Nil)
              False ->
                Ok(refused(
                  row: Row(class_id: class.0, name:, value: 0.0, unit: ""),
                  rule: "a refill over time needs its amount, period and tick",
                ))
            }
          })
        True, True | False, _ -> []
      }
      list.append(max, regen)
    })
  case list.append(unknown, missing) {
    [_, ..] as refusals -> Error(refusals)
    [] ->
      Ok(Classes(
        by_class: list.map(playable, fn(class) {
          let #(class_id, #(slot, start)) = class
          let named = dict.get(by_class, class_id) |> result.unwrap([])
          #(class_id, resource_of(named:, slot:, start:))
        })
        |> dict.from_list,
      ))
  }
}

/// A row's value above 0, and a whole number for a time.
fn checked_value(row row: Row) -> Result(Refusal, Nil) {
  case
    row.value <=. 0.0,
    row.unit == "ms" && int.to_float(float.truncate(row.value)) != row.value
  {
    True, _ -> Ok(refused(row:, rule: "its value is not above 0"))
    False, True ->
      Ok(refused(row:, rule: "a time is a whole number of milliseconds"))
    False, False -> Error(Nil)
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
  )
}

fn refused(row row: Row, rule rule: String) -> Refusal {
  Refusal(
    table: "class_resource",
    row: RowName(int.to_string(row.class_id) <> " " <> row.name),
    rule:,
  )
}

/// A player's resource now: its class's, the slot's value, whether the player is in
/// combat and alive, and which of the two timers runs.
pub opaque type Resources {
  Resources(
    resource: Resource,
    value: Float,
    in_combat: Bool,
    alive: Bool,
    regen_running: Bool,
    refill_running: Bool,
  )
}

/// A cost the cast rule took at an accept: `amount` points of the resource slot
/// `slot`.
pub type Payment {
  Payment(slot: Int, amount: Int)
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

/// Whether the timer is one of this rule's, for the connection to hand it to
/// `timer_fired`.
pub fn owns(timer timer: TimerId) -> Bool {
  timer == regen_timer || timer == refill_timer
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

/// The timers a living slot below its max starts when none of them runs: the
/// refill over time, and the Medic's refill when out of combat.
fn refills(resources resources: Resources) -> #(Resources, List(Effect)) {
  use <- bool.guard(
    when: !resources.alive || resources.value >=. resources.resource.max,
    return: #(resources, []),
  )
  let #(resources, regen) = case resources.resource.regen {
    Some(Regen(tick_ms:, ..)) if !resources.regen_running -> #(
      Resources(..resources, regen_running: True),
      [StartTimer(timer: regen_timer, after_ms: tick_ms)],
    )
    Some(..) | None -> #(resources, [])
  }
  let #(resources, refill) = case resources.resource.refill_after_combat_ms {
    Some(after_ms) if !resources.in_combat && !resources.refill_running -> #(
      Resources(..resources, refill_running: True),
      [StartTimer(timer: refill_timer, after_ms:)],
    )
    Some(..) | None -> #(resources, [])
  }
  #(resources, list.append(regen, refill))
}

/// A timer of the rule fired: a tick of the refill over time, or the Medic's refill.
/// A timer that fires after its cancel, or after death, changes nothing.
pub fn timer_fired(
  resources resources: Resources,
  timer timer: TimerId,
) -> #(Resources, List(Effect)) {
  case timer == regen_timer, timer == refill_timer {
    True, _ if resources.regen_running -> {
      let resources = Resources(..resources, regen_running: False)
      let per_tick = case resources.resource.regen {
        Some(Regen(per_tick:, ..)) -> per_tick
        None -> 0.0
      }
      changed_to(resources:, value: resources.value +. per_tick)
    }
    False, True if resources.refill_running ->
      changed_to(
        resources: Resources(..resources, refill_running: False),
        value: resources.resource.max,
      )
    _, _ -> #(resources, [])
  }
}

/// The slot set to `value`, clamped to [0, max] and held as a 32-bit float: a
/// change when it moved, then the timers a slot below its max starts.
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
/// Medic's refill waits no longer; out of it, a slot below its max starts it.
pub fn combat_changed(
  resources resources: Resources,
  in_combat in_combat: Bool,
) -> #(Resources, List(Effect)) {
  let resources = Resources(..resources, in_combat:)
  case in_combat, resources.refill_running {
    True, True -> #(Resources(..resources, refill_running: False), [
      CancelTimer(timer: refill_timer),
    ])
    True, False -> #(resources, [])
    False, _ -> refills(resources:)
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
  #(
    Resources(..resources, regen_running: False, refill_running: False),
    list.append(regen, refill),
  )
}
