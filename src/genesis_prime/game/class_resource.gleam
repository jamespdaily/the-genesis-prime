//// A player's class resource, a feature of the game connection's rule
//// (genesis_prime/game/connection) kept beside its life (genesis_prime/game/player_life):
//// the one resource slot its class's bar shows, and a healer's Focus, as the client
//// holds them, what a cast pays from them, and their refill over time. The client
//// changes no slot itself (`0x140454380`): the server sets each by the 0x262's stats and
//// by 0x935, so every change here is a 0x935 the connection writes to the player's own
//// client.
////
//// ```
//// entry ─▶ new(the class's resource, properties): the slot at its start, Focus at its pool ─▶ the 0x262's stat slot + 2 (float) and ResourceMax_slot
//// a cast's first go (genesis_prime/game/cast Pay) ─▶ pay ─▶ Changed(slot, value)         ─▶ 0x935 to the player
////                                                 a slot that refills over time: StartTimer(regen_timer, tick)
////                                                 a Medic out of combat: StartTimer(refill_timer, 3000)
//// a Focus cost (slot -1) ─▶ pay ─▶ Changed(-1, value) ─▶ 0x935 of stat 1;  below the pool: StartTimer(focus_timer, 500)
//// focus_timer ─▶ + the pool x the share x 0.5, clamped to the pool ─▶ Changed; below the pool again ─▶ StartTimer(focus_timer)
//// a go's gains (genesis_prime/game/cast Gain) ─▶ gain ─▶ Changed, clamped to the max (slot -1: Focus)
////                                                 a Warrior's slot gain: CancelTimer(drain_timer), StartTimer(drain_timer, 1500)
////                                                 Focus at its pool: CancelTimer(focus_timer)
//// regen_timer ─▶ + per tick, clamped to the max ─▶ Changed; below the max again ─▶ StartTimer(regen_timer)
//// drain_timer ─▶ - per tick, clamped to 0 ─▶ Changed; above 0 still ─▶ StartTimer(drain_timer, tick)
//// the combat flag clears (player_life) ─▶ a Medic below its max: StartTimer(refill_timer)
////                                         an Esper above 0: StartTimer(empty_timer, 10000)
////                                         an Engineer above 0: StartTimer(empty_timer, 5000)
//// the combat flag sets ─▶ CancelTimer(refill_timer), CancelTimer(empty_timer)
//// refill_timer ─▶ the slot at its max ─▶ Changed
//// empty_timer ─▶ the slot at 0 ─▶ Changed
//// died ─▶ every timer cancelled;  came_back ─▶ the slot at its start, Focus at its pool ─▶ Changed when they moved
//// the player's properties change (genesis_prime/game/unit_properties) ─▶ properties_followed: Focus's pool and numbers
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
////   server's to apply and send, clamped to [0, max]. A gain is points of the class slot,
////   points of the slot that names a class vital (a class whose slot names another drops
////   it), or Focus as points or as a share of its maximum (property 5); one call applies
////   them in the order given, the class slot's changes sent before Focus's.
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
//// - **Focus** is a second vital held beside the class slot by an Esper, Medic and
////   Spellslinger, reached as slot -1 (`focus_slot`): stat 1 of the player's unit and
////   0x935 (`ApplyUnitStat` 0x1403d9a60 case 1), with its maximum the player's property 5
////   (`GetMaxFocus` 0x14064a810). The pool is a content row, `focus_pool`, a guess
////   (`UnitProperty2.5.class_pool`): a flat 1000 at every level plus what worn items add, full
////   at entry and when coming back (migration 0048). A cost is paid like a slot's, at the cast's first go; the
////   points are `focus.required_points`. It recovers each `focus.Formulas.tick_ms` by the
////   pool x the share x the tick (genesis_prime/game/focus), on `focus_timer`, which runs
////   exactly while the pool is below its maximum and the player lives. A class that holds
////   no Focus holds 0 of it with a maximum of 0 and ignores a payment of it.
//// - **Death** stops every timer; **coming back** sets the slot to its start (the
////   server's choice, as health and shield come back full). The resources are not
////   saved: each entry starts at the start.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/game/focus
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/message/float32
import genesis_prime/step.{type TimerId, TimerId}
import genesis_prime/table/class
import genesis_prime/table/id.{type ClassId, ClassId}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// Where a class's resource starts at entry, by the client's text
/// (`LocalizedEnum.CRB_StalkerResource`).
type Start {
  Empty
  Full
}

/// What a class's resource is: the slot it lives in, the vital each of the class's
/// eight slots names, its maximum, its start, and how it refills over time.
pub type Resource {
  Resource(
    slot: Int,
    /// The vital each slot names, slot 0 first (`Class.vitalEnumResource00` to
    /// `07`): what a cost of a class vital is looked up by (`class_cost`).
    vitals: List(Int),
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
    /// The Focus the class holds; none for a class that holds none.
    focus: Option(FocusPool),
  )
}

/// The Focus a class holds: its base pool in points, before what worn items add, and the
/// formulas the pool's numbers are read through.
pub type FocusPool {
  FocusPool(pool: Float, formulas: focus.Formulas)
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

/// The classes that hold Focus: the Esper, Medic and Spellslinger, whose level grants
/// cost it (`Spell4.innateCostType0` 15).
const focus_classes = [3, 4, 7]

/// The Class ids of the classes that hold Focus, in id order.
pub fn focus_class_ids() -> List(Int) {
  focus_classes
}

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
  "focus_pool",
]

/// The numbers a class needs: those of its refill and, for a class that holds Focus,
/// its pool.
fn needed(class_id class_id: Int, refill refill: Refill) -> List(String) {
  let pool = case list.contains(focus_classes, class_id) {
    True -> ["focus_pool"]
    False -> []
  }
  list.append(refill_needs(refill:), pool)
}

fn refill_needs(refill refill: Refill) -> List(String) {
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
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Classes, List(Refusal)) {
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
        Ok(..), True ->
          case
            row.name == "focus_pool"
            && !list.contains(focus_classes, row.class_id)
          {
            True ->
              Ok(refused(
                class_id: row.class_id,
                name: row.name,
                rule: "the server holds no Focus for that class",
              ))
            False -> Error(Nil)
          }
      }
    })
  let by_class = list.group(rows, fn(row) { row.class_id })
  let missing =
    list.flat_map(playable, fn(class) {
      let #(class_id, #(_, _, refill)) = class
      let named = dict.get(by_class, class_id) |> result.unwrap([])
      list.filter_map(needed(class_id:, refill:), fn(name) {
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
  case list.flatten([unknown, missing]) {
    [_, ..] as refusals -> Error(refusals)
    [] ->
      Ok(Classes(
        by_class: list.map(playable, fn(class) {
          let #(class_id, #(slot, start, _)) = class
          let named = dict.get(by_class, class_id) |> result.unwrap([])
          let assert Ok(row) = class.get(tables:, id: ClassId(class_id))
            as "the load requires a Class row for each playable class (character_state.requirements)"
          #(
            class_id,
            resource_of(
              named:,
              slot:,
              vitals: vitals_of(row:),
              start:,
              formulas: case list.contains(focus_classes, class_id) {
                True -> Some(focus.formulas(tables:))
                False -> None
              },
            ),
          )
        })
        |> dict.from_list,
      ))
  }
}

/// The vital each of the class's eight slots names, slot 0 first.
fn vitals_of(row row: class.Class) -> List(Int) {
  [
    row.vital_enum_resource00,
    row.vital_enum_resource01,
    row.vital_enum_resource02,
    row.vital_enum_resource03,
    row.vital_enum_resource04,
    row.vital_enum_resource05,
    row.vital_enum_resource06,
    row.vital_enum_resource07,
  ]
}

fn resource_of(
  named named: List(Row),
  slot slot: Int,
  vitals vitals: List(Int),
  start start: Start,
  formulas formulas: Option(focus.Formulas),
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
    vitals:,
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
    focus: case value("focus_pool"), formulas {
      Ok(pool), Some(formulas) -> Some(FocusPool(pool:, formulas:))
      Ok(_), None | Error(Nil), _ -> None
    },
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
    /// The timers the rule has started and not yet seen fire or cancelled.
    running: Set(TimerId),
    /// The Focus held; none for a class that holds none.
    focus: Option(Pool),
  )
}

/// The Focus held now, the numbers its rules read and the formulas it reads them through.
type Pool {
  Pool(value: Float, numbers: focus.Numbers, formulas: focus.Formulas)
}

/// A cost the cast rule took at an accept: `amount` points of the resource slot
/// `slot`, or of Focus for `focus_slot`.
pub type Payment {
  Payment(slot: Int, amount: Int)
}

/// A gain the cast rule gave at a go (`Spell4Effects.effectType.1`): `amount` points into
/// the resource slot `slot` (Focus for `focus_slot`), a class vital's `amount` points into
/// the class's slot that names the vital (dropped by a class whose slot names another), or a
/// `share` of the Focus maximum.
pub type Gain {
  Gain(slot: Int, amount: Int)
  ClassVitalGain(vital: Int, amount: Int)
  FocusShare(share: Float)
}

/// A gain of the Focus pool, as `gain` applies it: points, or a share of the maximum.
type FocusChange {
  FocusByPoints(amount: Int)
  FocusByShare(share: Float)
}

/// What the rule asks the connection to do, in order.
pub type Effect {
  /// The slot now holds `value`: 0x935 of the player's own unit, stat slot + 2.
  Changed(slot: Int, value: Float)
  StartTimer(timer: TimerId, after_ms: Int)
  CancelTimer(timer: TimerId)
}

/// The slot Focus is reached as: stat 1 of the player's unit, which no class slot of the
/// client is (the slots 0 to 7 are stats 2 to 9).
pub const focus_slot = -1

/// The timer of the refill over time; the connection's own timers are below the
/// cast rule's (genesis_prime/game/cast/state `owns`), and the save, claim and strike
/// timers take 1 to 3.
pub const regen_timer = TimerId(4)

/// The timer of the Medic's refill after combat.
pub const refill_timer = TimerId(5)

/// The timer of the Warrior's drain: its wait after a gain, then each tick.
pub const drain_timer = TimerId(6)

/// The timer of the Esper's empty after combat.
pub const empty_timer = TimerId(7)

/// The timer of Focus's recovery: the next number after the connection's other timers, 1
/// to 13, and below the cast rule's from 1000.
pub const focus_timer = TimerId(14)

/// Every timer of this rule, in timer-id order.
const timers = [
  regen_timer,
  refill_timer,
  drain_timer,
  empty_timer,
  focus_timer,
]

/// Whether the timer is one of this rule's, for the connection to hand it to
/// `timer_fired`.
pub fn owns(timer timer: TimerId) -> Bool {
  list.contains(timers, timer)
}

fn is_running(resources resources: Resources, timer timer: TimerId) -> Bool {
  set.contains(resources.running, timer)
}

fn running_with(
  resources resources: Resources,
  timer timer: TimerId,
) -> Resources {
  Resources(..resources, running: set.insert(resources.running, timer))
}

fn running_without(
  resources resources: Resources,
  timer timer: TimerId,
) -> Resources {
  Resources(..resources, running: set.delete(resources.running, timer))
}

/// A player entering the world: alive, out of combat, its slot at its start and its
/// Focus full, the pool being the maximum its properties give (property 5, the class's
/// pool and what worn items add).
pub fn new(
  resource resource: Resource,
  properties properties: Properties,
) -> Resources {
  Resources(
    resource:,
    value: float32.rounded(resource.start),
    in_combat: False,
    alive: True,
    running: set.new(),
    focus: case resource.focus {
      Some(FocusPool(formulas:, ..)) -> {
        let numbers = focus.numbers(properties:)
        Some(Pool(value: float32.rounded(numbers.maximum), numbers:, formulas:))
      }
      None -> None
    },
  )
}

/// The base pool of Focus the class holds, in points: what the worn items add to,
/// 0 for a class that holds none.
pub fn focus_pool(resource resource: Resource) -> Float {
  case resource.focus {
    Some(FocusPool(pool:, ..)) -> pool
    None -> 0.0
  }
}

/// The base pool of Focus the class of this player holds, in points (`focus_pool`).
pub fn base_focus_pool(resources resources: Resources) -> Float {
  focus_pool(resource: resources.resource)
}

/// The Focus held, none for a class that holds none.
pub fn focus_held(resources resources: Resources) -> Option(Float) {
  option.map(resources.focus, fn(pool) { pool.value })
}

/// The whole points of Focus a cost of `amount` needs of this player: the client's
/// `(int)(m x amount + 0.5)` with the player's cost modifier and intensity
/// (`CheckInnateCost` 0x1403b3320 case 0xe), `amount` itself for a class that holds none
/// (which holds 0 and is refused whatever it asks for).
pub fn focus_required(
  resources resources: Resources,
  amount amount: Int,
) -> Int {
  case resources.focus {
    Some(Pool(numbers:, formulas:, ..)) ->
      focus.required_points(
        formulas:,
        cost: amount,
        modifier: numbers.cost_modifier,
        intensity_fraction: focus.intensity_fraction(formulas:, numbers:),
      )
    None -> amount
  }
}

/// The resource slot the class holds.
pub fn slot(resources resources: Resources) -> Int {
  resources.resource.slot
}

/// The value of the resource slot `slot`: 0 for one the class does not hold.
pub fn value(resources resources: Resources, slot slot: Int) -> Float {
  use <- bool.guard(when: slot == focus_slot, return: case resources.focus {
    Some(pool) -> pool.value
    None -> 0.0
  })
  use <- bool.guard(when: slot != resources.resource.slot, return: 0.0)
  resources.value
}

/// The maximum of the resource slot `slot`: 0 for one the class does not hold.
pub fn max(resources resources: Resources, slot slot: Int) -> Float {
  use <- bool.guard(when: slot == focus_slot, return: case resources.focus {
    Some(pool) -> pool.numbers.maximum
    None -> 0.0
  })
  use <- bool.guard(when: slot != resources.resource.slot, return: 0.0)
  resources.resource.max
}

/// The slots of the class that name the vital, in slot order
/// (`Class.vitalEnumResource00` to `07`).
fn slots_of(resources resources: Resources, vital vital: Int) -> List(Int) {
  list.index_map(resources.resource.vitals, fn(named, slot) { #(slot, named) })
  |> list.filter_map(fn(slot) {
    case slot.1 == vital {
      True -> Ok(slot.0)
      False -> Error(Nil)
    }
  })
}

/// The result of a class cost refused at a slot: 50 + the slot, and 177 for slot 7
/// (`VitalCostResult` 0x1403d3650).
fn refused_at(slot slot: Int) -> Int {
  case slot {
    7 -> 177
    _ -> 50 + slot
  }
}

/// A class vital's innate cost checked as the client checks it
/// (`CheckClassResourceCost` 0x1405e7980): it passes at the first of the class's
/// slots naming the vital where the slot's value less the amount lies in [0, that
/// slot's maximum], and is paid from it. With none passing it is refused with the
/// last such slot's result. A class with no slot naming the vital passes and pays
/// nothing.
pub fn class_cost(
  resources resources: Resources,
  vital vital: Int,
  amount amount: Int,
) -> Result(Option(Int), Int) {
  case slots_of(resources:, vital:) {
    [] -> Ok(None)
    [_, ..] as slots ->
      case
        list.find(slots, fn(slot) {
          let left = value(resources:, slot:) -. int.to_float(amount)
          left >=. 0.0 && left <=. max(resources:, slot:)
        })
      {
        Ok(slot) -> Ok(Some(slot))
        Error(Nil) -> {
          let assert Ok(last) = list.last(slots)
            as "a class cost with no passing slot has slots"
          Error(refused_at(slot: last))
        }
      }
  }
}

/// A class vital's cost on a threshold row checked as the client checks it
/// (`CheckThresholdRowCosts` 0x1403c0620): a cost of 0 passes and pays nothing,
/// else the cost must be at most the whole points of the vital's slot, with no
/// maximum test. The slot is the first naming the vital that holds above 0
/// (`ClassVitalSlot` 0x1405e78c0); a refusal is that slot's result, or 175 when
/// there is none (`VitalCostResult`).
pub fn row_class_cost(
  resources resources: Resources,
  vital vital: Int,
  amount amount: Int,
) -> Result(Option(Int), Int) {
  use <- bool.guard(when: amount == 0, return: Ok(None))
  let held =
    list.find(slots_of(resources:, vital:), fn(slot) {
      value(resources:, slot:) >. 0.0
    })
  case held {
    Ok(slot) ->
      case float.truncate(value(resources:, slot:)) >= amount {
        True -> Ok(Some(slot))
        False -> Error(refused_at(slot:))
      }
    Error(Nil) -> Error(175)
  }
}

/// The resources with the payments taken, and nothing else: what the cast rule
/// checks a second press of the same step against.
pub fn paid(
  resources resources: Resources,
  payments payments: List(Payment),
) -> Resources {
  list.fold(payments, resources, fn(resources, payment) {
    let points = int.to_float(int.absolute_value(payment.amount))
    case payment.slot == resources.resource.slot, payment.slot == focus_slot {
      True, _ ->
        Resources(
          ..resources,
          value: clamped(resources:, value: resources.value -. points),
        )
      False, True ->
        case resources.focus {
          Some(pool) ->
            Resources(
              ..resources,
              focus: Some(
                Pool(
                  ..pool,
                  value: focus_clamped(pool:, value: pool.value -. points),
                ),
              ),
            )
          None -> resources
        }
      False, False -> resources
    }
  })
}

/// The payments taken: a change for each one of the class's slot or of Focus, then the
/// timers a slot below its max starts and the Focus timer a pool below its maximum starts.
pub fn pay(
  resources resources: Resources,
  payments payments: List(Payment),
) -> #(Resources, List(Effect)) {
  let #(resources, changes) =
    list.fold(payments, #(resources, []), fn(so_far, payment) {
      let #(resources, changes) = so_far
      case
        payment.slot == resources.resource.slot
        || { payment.slot == focus_slot && option.is_some(resources.focus) }
      {
        False -> so_far
        True -> {
          let resources = paid(resources:, payments: [payment])
          #(resources, [
            Changed(
              slot: payment.slot,
              value: value(resources:, slot: payment.slot),
            ),
            ..changes
          ])
        }
      }
    })
  let #(resources, timers) = refills(resources:)
  let #(resources, focus_timers) = focus_refills(resources:)
  #(resources, list.flatten([list.reverse(changes), timers, focus_timers]))
}

/// The gains of a go, each applied in the order given and clamped to [0, max] where it
/// lands: the class slot's (a `Gain` of its slot, or a `ClassVitalGain` of the vital the
/// class's slot names) and Focus's (a `Gain` of `focus_slot`, or a `FocusShare` of the
/// maximum). The effects are a change for each slot gain that moved it, then one for each
/// Focus gain that moved it, then the drain's wait restarted for a class that drains and
/// whose slot a gain landed in, then the timers a living slot and the Focus pool need. A
/// gain the class does not hold, and every gain of a dead player, changes nothing.
pub fn gain(
  resources resources: Resources,
  gains gains: List(Gain),
) -> #(Resources, List(Effect)) {
  let named_here = fn(vital) {
    list.contains(slots_of(resources:, vital:), resources.resource.slot)
  }
  let slot_amounts =
    list.filter_map(gains, fn(gain) {
      case gain {
        Gain(slot:, amount:) if slot == resources.resource.slot -> Ok(amount)
        ClassVitalGain(vital:, amount:) -> {
          case named_here(vital) {
            True -> Ok(amount)
            False -> Error(Nil)
          }
        }
        Gain(..) | FocusShare(..) -> Error(Nil)
      }
    })
  let focus_gains = case resources.focus {
    None -> []
    Some(_) ->
      list.filter_map(gains, fn(gain) {
        case gain {
          Gain(slot:, amount:) if slot == focus_slot ->
            Ok(FocusByPoints(amount:))
          FocusShare(share:) -> Ok(FocusByShare(share:))
          Gain(..) | ClassVitalGain(..) -> Error(Nil)
        }
      })
  }
  use <- bool.guard(
    when: !resources.alive || { slot_amounts == [] && focus_gains == [] },
    return: #(resources, []),
  )
  let #(resources, slot_changes) =
    list.fold(slot_amounts, #(resources, []), fn(so_far, amount) {
      let #(resources, changes) = so_far
      let next =
        clamped(resources:, value: resources.value +. int.to_float(amount))
      let changes = case next == resources.value {
        True -> changes
        False -> [
          Changed(slot: resources.resource.slot, value: next),
          ..changes
        ]
      }
      #(Resources(..resources, value: next), changes)
    })
  let #(resources, focus_changes) =
    list.fold(focus_gains, #(resources, []), fn(so_far, gain) {
      let #(resources, changes) = so_far
      case resources.focus {
        None -> so_far
        Some(pool) -> {
          let points = case gain {
            FocusByShare(share:) ->
              float32.product(left: share, right: pool.numbers.maximum)
            FocusByPoints(amount:) -> int.to_float(amount)
          }
          let next = focus_clamped(pool:, value: pool.value +. points)
          let changes = case next == pool.value {
            True -> changes
            False -> [Changed(slot: focus_slot, value: next), ..changes]
          }
          #(
            Resources(..resources, focus: Some(Pool(..pool, value: next))),
            changes,
          )
        }
      }
    })
  let #(resources, drain, timers) = case slot_amounts {
    [] -> #(resources, [], [])
    [_, ..] -> {
      let #(resources, drain) = case resources.resource.drain {
        Some(Drain(after_ms:, ..)) -> #(
          running_with(resources:, timer: drain_timer),
          list.append(
            case is_running(resources:, timer: drain_timer) {
              True -> [CancelTimer(timer: drain_timer)]
              False -> []
            },
            [StartTimer(timer: drain_timer, after_ms:)],
          ),
        )
        None -> #(resources, [])
      }
      let #(resources, timers) = refills(resources:)
      #(resources, drain, timers)
    }
  }
  let #(resources, focus_timers) = case focus_gains {
    [] -> #(resources, [])
    [_, ..] -> focus_refills(resources:)
  }
  #(
    resources,
    list.flatten([
      list.reverse(slot_changes),
      list.reverse(focus_changes),
      drain,
      timers,
      focus_timers,
    ]),
  )
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
        Some(Regen(tick_ms:, ..)) ->
          started(resources:, timer: regen_timer, after_ms: tick_ms)
        None -> #(resources, [])
      }
      let #(resources, refill) = case
        resources.resource.refill_after_combat_ms,
        resources.in_combat
      {
        Some(after_ms), False ->
          started(resources:, timer: refill_timer, after_ms:)
        Some(_), True | None, _ -> #(resources, [])
      }
      #(resources, list.append(regen, refill))
    }
  }
  let #(resources, emptying) = case
    resources.resource.empty_after_combat_ms,
    resources.in_combat || resources.value <=. 0.0
  {
    Some(after_ms), False -> started(resources:, timer: empty_timer, after_ms:)
    Some(_), True | None, _ -> #(resources, [])
  }
  #(resources, list.append(below_max, emptying))
}

/// The timer started with a `StartTimer` unless it already runs.
fn started(
  resources resources: Resources,
  timer timer: TimerId,
  after_ms after_ms: Int,
) -> #(Resources, List(Effect)) {
  use <- bool.guard(
    when: is_running(resources:, timer:),
    return: #(resources, []),
  )
  #(running_with(resources:, timer:), [StartTimer(timer:, after_ms:)])
}

/// A timer of the rule fired: a tick of the refill over time, the Medic's refill, a
/// tick of the Warrior's drain, or the Esper's empty. A timer that fires after its
/// cancel, or after death, changes nothing.
pub fn timer_fired(
  resources resources: Resources,
  timer timer: TimerId,
) -> #(Resources, List(Effect)) {
  use <- bool.guard(
    when: !is_running(resources:, timer:),
    return: #(resources, []),
  )
  let resources = running_without(resources:, timer:)
  use <- bool.guard(
    when: timer == focus_timer,
    return: focus_ticked(resources:),
  )
  case timer, resources.resource {
    _, Resource(regen: Some(Regen(per_tick:, ..)), ..) if timer == regen_timer ->
      changed_to(resources:, value: resources.value +. per_tick)
    _, Resource(refill_after_combat_ms: Some(_), ..) if timer == refill_timer ->
      changed_to(resources:, value: resources.resource.max)
    _, Resource(drain: Some(Drain(per_tick:, tick_ms:, ..)), ..)
      if timer == drain_timer
    -> {
      let #(resources, effects) =
        changed_to(resources:, value: resources.value -. per_tick)
      case resources.value >. 0.0 {
        True -> #(
          running_with(resources:, timer:),
          list.append(effects, [
            StartTimer(timer: drain_timer, after_ms: tick_ms),
          ]),
        )
        False -> #(resources, effects)
      }
    }
    _, Resource(empty_after_combat_ms: Some(_), ..) if timer == empty_timer ->
      changed_to(resources:, value: 0.0)
    _, Resource(..) -> #(resources, [])
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

/// Focus set to `value`, clamped to [0, its maximum] and held as a 32-bit float.
fn focus_clamped(pool pool: Pool, value value: Float) -> Float {
  float32.rounded(float.clamp(value, min: 0.0, max: pool.numbers.maximum))
}

/// Focus set to `value`: a change when it moved, then the timer a living player below its
/// maximum needs (`focus_refills`).
fn focus_changed_to(
  resources resources: Resources,
  value value: Float,
) -> #(Resources, List(Effect)) {
  case resources.focus {
    None -> #(resources, [])
    Some(pool) -> {
      let next = focus_clamped(pool:, value:)
      let change = case next == pool.value {
        True -> []
        False -> [Changed(slot: focus_slot, value: next)]
      }
      let #(resources, timers) =
        focus_refills(
          resources: Resources(
            ..resources,
            focus: Some(Pool(..pool, value: next)),
          ),
        )
      #(resources, list.append(change, timers))
    }
  }
}

/// The Focus timer, which runs exactly while the player lives and the pool is below its
/// maximum: started when it should run and does not, cancelled when it runs and should not.
fn focus_refills(resources resources: Resources) -> #(Resources, List(Effect)) {
  case resources.focus {
    Some(Pool(formulas:, ..) as pool) -> {
      let wanted = resources.alive && pool.value <. pool.numbers.maximum
      case wanted, is_running(resources:, timer: focus_timer) {
        True, False -> #(running_with(resources:, timer: focus_timer), [
          StartTimer(timer: focus_timer, after_ms: formulas.tick_ms),
        ])
        False, True -> #(running_without(resources:, timer: focus_timer), [
          CancelTimer(timer: focus_timer),
        ])
        True, True | False, False -> #(resources, [])
      }
    }
    None -> #(resources, [])
  }
}

/// A tick of Focus's recovery: the pool x the share (in combat or out) x the tick.
fn focus_ticked(resources resources: Resources) -> #(Resources, List(Effect)) {
  case resources.focus {
    Some(Pool(formulas:, ..) as pool) -> {
      let share =
        focus.share(
          formulas:,
          numbers: pool.numbers,
          in_combat: resources.in_combat,
        )
      focus_changed_to(
        resources:,
        value: pool.value
          +. focus.per_tick(formulas:, maximum: pool.numbers.maximum, share:),
      )
    }
    None -> #(resources, [])
  }
}

/// The player's properties changed (genesis_prime/game/unit_properties): Focus takes the
/// new numbers, the pool and the shares the tick reads, the cost modifier and the level,
/// a pool above a lowered maximum is clamped to it (one change), and a raised maximum
/// starts the timer. A class that holds no Focus changes nothing.
pub fn properties_followed(
  resources resources: Resources,
  properties properties: Properties,
) -> #(Resources, List(Effect)) {
  case resources.focus {
    None -> #(resources, [])
    Some(pool) ->
      focus_changed_to(
        resources: Resources(
          ..resources,
          focus: Some(Pool(..pool, numbers: focus.numbers(properties:))),
        ),
        value: pool.value,
      )
  }
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
      let cancels =
        list.filter([refill_timer, empty_timer], is_running(
          resources:,
          timer: _,
        ))
      #(
        list.fold(cancels, resources, fn(resources, timer) {
          running_without(resources:, timer:)
        }),
        list.map(cancels, fn(timer) { CancelTimer(timer:) }),
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

/// The player came back: the slot is set to its start and Focus to its pool, each with a
/// change when it moved.
pub fn came_back(resources resources: Resources) -> #(Resources, List(Effect)) {
  let #(resources, slot) =
    changed_to(
      resources: Resources(..resources, alive: True),
      value: resources.resource.start,
    )
  let #(resources, focus) =
    focus_changed_to(resources:, value: max(resources:, slot: focus_slot))
  #(resources, list.append(slot, focus))
}

/// The player left the world, or its connection ended: every timer is cancelled,
/// and nothing is sent.
pub fn left(resources resources: Resources) -> #(Resources, List(Effect)) {
  let cancels =
    list.filter(timers, is_running(resources:, timer: _))
    |> list.map(fn(timer) { CancelTimer(timer:) })
  #(Resources(..resources, running: set.new()), cancels)
}
