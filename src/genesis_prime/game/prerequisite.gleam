//// A Prerequisite row as the client reads it, and its check against a unit: the
//// gate of an effect such as a resource gain, or of a Proxy
//// (genesis_prime/game/spell_plan `Gain`, `Condition`). The rule is pure: the
//// cast rule (genesis_prime/game/cast) supplies what the unit is, and the
//// connection supplies the rolls from its seed.
////
//// ```
//// Prerequisite row ─▶ load: the conditions kept up to the first type 0, AND or OR,
////                          each nested row (type 11) loaded in place; a cycle fails
//// a Subject: the casts it is under, in combat, its vitals, its resource slots,
////            its difficulty, its rolls
////                  ─▶ check ─▶ Passes | Fails | NotRead(type)
//// ```
////
//// - **The conditions** are read in order and cut at the first whose type is 0:
////   that one and every later one are dropped (`0x1404a5190`, `Prerequisite.flags`).
//// - **AND or OR:** the row passes when every kept condition passes, or with flags
////   bit 0 when any does; a row with no kept condition passes under AND and fails
////   under OR (`0x1404a1ca0`).
//// - **Comparisons** 1 to 6 are equal, not equal, greater, at least, less and at
////   most, on unsigned 32-bit numbers; any other fails (`0x1404a2090`).
//// - **Type 15** passes, by comparison 1, when a live cast of the Spell4 in its value
////   has the unit as a target, and by comparison 2 when none has; any other
////   comparison fails, and its objectId is not read
////   (`Prerequisite.prerequisiteTypeId.15`, `0x1404a4ec0`).
//// - **Type 50** passes, by comparison 1, when a live cast of the Spell4 in its value,
////   whose caster is the check's second unit, holds a node on the unit, and by
////   comparison 2 when none does; any other comparison fails. With no second unit,
////   comparison 2 passes and any other fails, and a second unit 0 or a value 0 matches
////   no cast. Its objectId is not read (`Prerequisite.prerequisiteTypeId.50`).
//// - **Type 59** compares the stack count on the unit of the Spell4 in its objectId
////   with the value: the sum of the instance counts of the casts that hold a node on
////   the unit, 0 when none does (`Prerequisite.prerequisiteTypeId.59`).
//// - **Type 28** passes, by comparison 1, when the unit is in combat and by
////   comparison 2 when it is not; any other comparison fails
////   (`Prerequisite.prerequisiteTypeId.28`).
//// - **Type 11** evaluates the Prerequisite its objectId names, whole, with its own
////   flags and the same two units and rolls; comparison 2 passes when it fails and
////   any other comparison gives its result, `NotRead` staying `NotRead`; its value is
////   not read, and an id with no row fails (`Prerequisite.prerequisiteTypeId.11`,
////   `0x1404a1ca0`). The rows are loaded in place, so a check needs no table, and a
////   row that nests itself through the rows on its way fails the load: the server's
////   choice, since the client's evaluator has no guard and its table has no cycle.
//// - **Type 64** compares the subject's resource slot the objectId names (0 to 10; 11 or
////   more reads 0.0, and so does a slot the class does not hold) as a 32-bit float with
////   the value read as a signed 32-bit number, by comparisons 1 to 6; any other fails.
////   A subject that holds no resource slots gives `NotRead`
////   (`Prerequisite.prerequisiteTypeId.64`, `0x1404a24ad`).
//// - **Type 129** passes, by comparison 1, when the unit is under a cast whose spell is in
////   the spell group the objectId names and by comparison 2 when it is under none; any
////   other comparison fails, group 0 matches no spell and the value is not read
////   (`Prerequisite.prerequisiteTypeId.129`, `0x1404a2b5a`).
//// - **Type 37** compares a roll from 1 to 100 with the value, a new roll for each
////   such condition tested; the roll is the server's, 1 + floor(100 r) of a draw r
////   in [0, 1) as the client makes it (`Prerequisite.prerequisiteTypeId.37`).
//// - **Type 71** compares the vital the objectId names, as a percentage of its
////   maximum, with the value, in 32-bit floats; a zero maximum with nothing held
////   is not a number, which counts as equal and fails every other comparison
////   (`Prerequisite.prerequisiteTypeId.71`, `0x1404a4e30`).
//// - **Type 73** compares the vital the objectId names, cut to a whole number
////   toward zero, with the value (`Prerequisite.prerequisiteTypeId.73`).
//// - **Type 116** passes, by comparison 1, when the unit is stealthed and by comparison
////   2 when it is not; any other comparison fails, and its objectId and value are not
////   read. A subject that holds no stealth gives `NotRead`
////   (`Prerequisite.prerequisiteTypeId.116`, `0x1404a2609`).
//// - **Type 179** compares the unit's difficulty with the condition's objectId, not
////   its value, by comparisons 1 to 6; only a creature's side holds a difficulty,
////   so a subject with none gives `NotRead` (`0x14049eeb0`, `of_difficulty`).
//// - **A vital the server does not hold** is `NotRead`, as is a type the client
////   decides and the server does not read.
//// - **A type with no case** in the client, 0 or one above 295, fails
////   (`0x1404a2100`).
//// - **The units:** a check's first unit is its subject, and this module checks
////   caster-side prerequisites only, where the second unit is the caster too
////   (`Spell4Effects.prerequisiteIdTargetApply`): the subject's `second_unit`.

import genesis_prime/game/lasting
import genesis_prime/message/float32
import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4Id, PrerequisiteId, Spell4Id,
}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

/// A Prerequisite row as the client keeps it: its id, whether any condition is
/// enough (flags bit 0), and its conditions up to the first of type 0.
pub opaque type Prerequisite {
  Prerequisite(id: PrerequisiteId, any: Bool, conditions: List(Condition))
}

/// How a condition compares a measured number with its value
/// (`0x1404a2090`).
pub type Relation {
  Equal
  NotEqual
  Greater
  AtLeast
  Less
  AtMost
  /// Any other code, which never passes.
  NeverRelation(code: Int)
}

/// The relation a comparison code names (`0x1404a2090`): 1 to 6.
pub fn relation_of(code code: Int) -> Relation {
  case code {
    1 -> Equal
    2 -> NotEqual
    3 -> Greater
    4 -> AtLeast
    5 -> Less
    6 -> AtMost
    other -> NeverRelation(code: other)
  }
}

/// Whether `measured` stands in `relation` to `value`, both read as unsigned
/// 32-bit numbers (`0x1404a2090`).
pub fn compare(
  relation relation: Relation,
  measured measured: Int,
  value value: Int,
) -> Bool {
  holds(relation:, ordering: int.compare(unsigned(measured), unsigned(value)))
}

/// Whether a measured number that orders as `ordering` against the value stands in
/// `relation` to it.
fn holds(relation relation: Relation, ordering ordering: order.Order) -> Bool {
  case relation, ordering {
    Equal, order.Eq -> True
    NotEqual, order.Lt | NotEqual, order.Gt -> True
    Greater, order.Gt -> True
    AtLeast, order.Gt | AtLeast, order.Eq -> True
    Less, order.Lt -> True
    AtMost, order.Lt | AtMost, order.Eq -> True
    Equal, _
    | NotEqual, _
    | Greater, _
    | AtLeast, _
    | Less, _
    | AtMost, _
    | NeverRelation(..), _
    -> False
  }
}

fn unsigned(number: Int) -> Int {
  int.bitwise_and(number, 0xFFFFFFFF)
}

/// The same 32 bits read as a signed number.
fn signed(number: Int) -> Int {
  case unsigned(number) {
    bits if bits >= 0x80000000 -> bits - 0x100000000
    bits -> bits
  }
}

/// One condition as the client's check reads it, decoded once from its
/// PrerequisiteType, comparison, objectId and value.
type Condition {
  /// Type 15: whether a live cast of the Spell4 has the unit as a target
  /// (`Prerequisite.prerequisiteTypeId.15`).
  TargetOfLiveCast(comparison: Comparison, spell4_id: Spell4Id)
  /// Type 50: whether a cast of the Spell4 by the check's second unit holds a node on
  /// the unit (`Prerequisite.prerequisiteTypeId.50`).
  UnderCastBy(comparison: Comparison, spell4_id: Spell4Id)
  /// Type 59: the stack count of the Spell4 on the unit against the value
  /// (`Prerequisite.prerequisiteTypeId.59`).
  StackCount(relation: Relation, spell4_id: Spell4Id, value: Int)
  /// Type 28: whether the unit is in combat
  /// (`Prerequisite.prerequisiteTypeId.28`).
  InCombat(comparison: Comparison)
  /// Type 37: a roll from 1 to 100 against the value
  /// (`Prerequisite.prerequisiteTypeId.37`).
  Roll(relation: Relation, value: Int)
  /// Type 71: the vital's percentage of its maximum against the value
  /// (`Prerequisite.prerequisiteTypeId.71`).
  VitalPercent(relation: Relation, vital: Int, value: Int)
  /// Type 73: the vital's current value, cut to a whole number, against the
  /// value (`Prerequisite.prerequisiteTypeId.73`).
  VitalCurrent(relation: Relation, vital: Int, value: Int)
  /// Type 11: the Prerequisite `id` evaluated whole with the same units; `row` is
  /// none when the table holds no such row, which fails
  /// (`Prerequisite.prerequisiteTypeId.11`, `0x1404a1ca0`).
  Nested(comparison: Comparison, id: Int, row: Option(Prerequisite))
  /// Type 64: the resource slot of the unit against the value, as floats
  /// (`Prerequisite.prerequisiteTypeId.64`).
  ResourceSlot(relation: Relation, slot: Int, value: Int)
  /// Type 129: whether the unit is under a cast whose spell is in the spell group
  /// (`Prerequisite.prerequisiteTypeId.129`).
  UnderGroup(comparison: Comparison, group: Int)
  /// Type 116: whether the unit is stealthed
  /// (`Prerequisite.prerequisiteTypeId.116`).
  Stealthed(comparison: Comparison)
  /// Type 179: the unit's difficulty against the objectId
  /// (`Prerequisite.prerequisiteTypeId.179`, `0x14049eeb0`).
  Difficulty(relation: Relation, object_id: Int)
  /// A type the client's check has no case for (`0x1404a2100`): it fails.
  NoCase
  /// A type the client decides and the server does not read.
  Unread(prerequisite_type: Int)
}

/// A comparison of a condition that asks whether something holds: 1 passes when it
/// does, 2 when it does not, any other fails (`0x1404a4ec0`,
/// `Prerequisite.prerequisiteTypeId.28`).
type Comparison {
  Found
  NotFound
  OtherComparison(comparison: Int)
}

fn comparison_of(code: Int) -> Comparison {
  case code {
    1 -> Found
    2 -> NotFound
    other -> OtherComparison(comparison: other)
  }
}

/// What a check of a prerequisite gives.
pub type Verdict {
  Passes
  Fails
  /// A condition of this PrerequisiteType decides the row, and the server does not
  /// read that type, or the vital it names: the client would decide it, the server
  /// cannot.
  NotRead(prerequisite_type: Int)
}

/// A vital of the subject: its current value and its maximum.
pub type Vital {
  Vital(current: Float, maximum: Float)
}

/// What a check may read about its subject, the check's first unit.
pub type Subject {
  Subject(
    /// What the casts of the subject's first unit hold on it: the nodes of live and
    /// lingering casts, and a live cast whose primary target it is with count 0
    /// (genesis_prime/game/lasting `Held`).
    under: List(lasting.Held),
    /// The check's second unit: the unit id of the caster for the caster-side checks
    /// of this module (`Spell4Effects.prerequisiteIdTargetApply`); none when the check
    /// has no second unit.
    second_unit: Option(Int),
    /// Whether the subject is in combat.
    in_combat: Bool,
    /// The vitals the server holds for the subject, by Vital id; a vital left out
    /// is not held.
    vitals: Dict(Int, Vital),
    /// The subject's difficulty, which only a creature's side holds: `None` for a
    /// player, so type 179 is not read for it (`0x14049eeb0`).
    difficulty: Option(Int),
    /// Whether the subject is stealthed, which only a player's cast rule holds: `None`
    /// for a creature's side, so type 116 is not read for it
    /// (genesis_prime/game/cast `stealthed`).
    stealthed: Option(Bool),
    /// The caster's resource slots by slot number, which only a player's cast rule
    /// holds: `None` for a creature's side, so type 64 is not read for it. A slot
    /// the class does not hold is left out and reads 0.0.
    resource_slots: Option(Dict(Int, Float)),
    /// The rolls for the type 37 conditions of the check, one for each, in the
    /// order the conditions are tested (`rolls_needed`).
    rolls: List(Int),
  )
}

/// A subject that holds only this difficulty: under no cast, out of combat, with
/// no vital and no roll. A creature's side checks the prerequisites of its
/// attack's effects against it (genesis_prime/world_map/creature_attack).
pub fn of_difficulty(difficulty difficulty: Int) -> Subject {
  Subject(
    under: [],
    second_unit: None,
    in_combat: False,
    vitals: dict.new(),
    difficulty: Some(difficulty),
    stealthed: None,
    resource_slots: None,
    rolls: [],
  )
}

/// The types from 1 to 295 that have no case in the client's condition check
/// (`0x1404a2100`).
const types_without_a_case = [
  17, 21, 32, 45, 57, 58, 72, 75, 132, 144, 156, 157, 158, 161, 165, 181, 202,
  247, 249, 257, 258, 274, 282, 284,
]

/// The highest type the client's condition check has a case for (`0x1404a2100`).
const highest_type = 295

/// Why a prerequisite does not load.
pub type LoadError {
  /// The row the load started from is not in the table.
  NoPrerequisiteRow(id: PrerequisiteId)
  /// A row nests itself through the rows on the way, the ids in order with the
  /// repeated one last.
  PrerequisiteCycle(path: List(PrerequisiteId))
}

/// The prerequisite with this id as the client keeps it (`0x1404a5190`), from the
/// table `rows` reads, each nested row loaded in place.
pub fn load(
  id id: PrerequisiteId,
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
) -> Result(Prerequisite, LoadError) {
  use row <- result.try(
    rows(id) |> result.replace_error(NoPrerequisiteRow(id:)),
  )
  loaded(row:, rows:, above: [id])
}

/// The PrerequisiteType of a nested prerequisite (`Prerequisite.prerequisiteTypeId.11`),
/// whose row `load` follows.
const nested_type = 11

/// The row as a prerequisite; `above` holds the ids of the rows it is nested in,
/// nearest first.
fn loaded(
  row row: prerequisite_table.Prerequisite,
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  above above: List(PrerequisiteId),
) -> Result(Prerequisite, LoadError) {
  use conditions <- result.map(
    list.try_map(kept_conditions(row:), fn(condition) {
      use <- bool.lazy_guard(when: condition.0 == nested_type, return: fn() {
        nested_loaded(
          comparison: comparison_of(condition.1),
          id: PrerequisiteId(condition.2),
          rows:,
          above:,
        )
      })
      Ok(condition_of(
        type_id: condition.0,
        comparison: condition.1,
        object_id: condition.2,
        value: condition.3,
      ))
    }),
  )
  Prerequisite(id: PrerequisiteId(row.id), any: is_any(row:), conditions:)
}

/// A type 11 condition with the row it names loaded, none when the table has none; a
/// row already on the way is a cycle.
fn nested_loaded(
  comparison comparison: Comparison,
  id id: PrerequisiteId,
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  above above: List(PrerequisiteId),
) -> Result(Condition, LoadError) {
  use <- bool.guard(
    when: list.contains(above, id),
    return: Error(PrerequisiteCycle(path: list.reverse([id, ..above]))),
  )
  case rows(id) {
    Error(Nil) -> Ok(Nested(comparison:, id: id.value, row: None))
    Ok(row) ->
      loaded(row:, rows:, above: [id, ..above])
      |> result.map(fn(nested) {
        Nested(comparison:, id: id.value, row: Some(nested))
      })
  }
}

/// The PrerequisiteTypes of the conditions the client keeps from the row, in
/// order: those before the first of type 0 (`0x1404a5190`).
pub fn condition_types(row row: prerequisite_table.Prerequisite) -> List(Int) {
  list.map(kept_conditions(row:), fn(condition) { condition.0 })
}

/// Whether any one kept condition is enough for the row to pass (`Prerequisite.flags`
/// bit 0), rather than all of them (`0x1404a1ca0`).
pub fn is_any(row row: prerequisite_table.Prerequisite) -> Bool {
  row.flags % 2 != 0
}

/// The conditions the client keeps, each as (type, comparison, objectId, value).
pub fn kept_conditions(
  row row: prerequisite_table.Prerequisite,
) -> List(#(Int, Int, Int, Int)) {
  [
    #(
      row.prerequisite_type_id0,
      row.prerequisite_comparison_id0,
      row.object_id0,
      row.value0,
    ),
    #(
      row.prerequisite_type_id1,
      row.prerequisite_comparison_id1,
      row.object_id1,
      row.value1,
    ),
    #(
      row.prerequisite_type_id2,
      row.prerequisite_comparison_id2,
      row.object_id2,
      row.value2,
    ),
  ]
  |> list.take_while(fn(condition) { condition.0 != 0 })
}

/// The one decode of a condition's type: every type the server reads has its own
/// variant, every other is `Unread` or has no case. The coverage measure counts a
/// type as handled when this does not give `Unread` for it (`is_read`).
fn condition_of(
  type_id type_id: Int,
  comparison comparison: Int,
  object_id object_id: Int,
  value value: Int,
) -> Condition {
  case type_id {
    15 ->
      TargetOfLiveCast(
        comparison: comparison_of(comparison),
        spell4_id: Spell4Id(value),
      )
    28 -> InCombat(comparison: comparison_of(comparison))
    50 ->
      UnderCastBy(
        comparison: comparison_of(comparison),
        spell4_id: Spell4Id(value),
      )
    59 ->
      StackCount(
        relation: relation_of(code: comparison),
        spell4_id: Spell4Id(object_id),
        value:,
      )
    37 -> Roll(relation: relation_of(code: comparison), value:)
    71 ->
      VitalPercent(
        relation: relation_of(code: comparison),
        vital: object_id,
        value:,
      )
    73 ->
      VitalCurrent(
        relation: relation_of(code: comparison),
        vital: object_id,
        value:,
      )
    11 ->
      Nested(comparison: comparison_of(comparison), id: object_id, row: None)
    64 ->
      ResourceSlot(
        relation: relation_of(code: comparison),
        slot: signed(object_id),
        value:,
      )
    129 -> UnderGroup(comparison: comparison_of(comparison), group: object_id)
    116 -> Stealthed(comparison: comparison_of(comparison))
    179 -> Difficulty(relation: relation_of(code: comparison), object_id:)
    _ ->
      case
        type_id < 1
        || type_id > highest_type
        || list.contains(types_without_a_case, type_id)
      {
        True -> NoCase
        False -> Unread(prerequisite_type: type_id)
      }
  }
}

/// Whether the server decides a condition of this PrerequisiteType: the types it
/// reads and the types the client's check has no case for, which fail
/// (`0x1404a2100`). The coverage measure's "handled".
pub fn is_read(type_id type_id: Int) -> Bool {
  case condition_of(type_id:, comparison: 0, object_id: 0, value: 0) {
    Unread(..) -> False
    TargetOfLiveCast(..)
    | UnderCastBy(..)
    | StackCount(..)
    | InCombat(..)
    | Roll(..)
    | VitalPercent(..)
    | VitalCurrent(..)
    | Nested(..)
    | ResourceSlot(..)
    | UnderGroup(..)
    | Stealthed(..)
    | Difficulty(..)
    | NoCase -> True
  }
}

/// The prerequisite's Prerequisite id.
pub fn id(prerequisite prerequisite: Prerequisite) -> PrerequisiteId {
  prerequisite.id
}

/// How many rolls a check of the prerequisite takes: one for each type 37
/// condition kept, in the rows it nests too.
pub fn rolls_needed(prerequisite prerequisite: Prerequisite) -> Int {
  list.map(prerequisite.conditions, fn(condition) {
    case condition {
      Roll(..) -> 1
      Nested(row: Some(nested), ..) -> rolls_needed(prerequisite: nested)
      Nested(row: None, ..)
      | TargetOfLiveCast(..)
      | UnderCastBy(..)
      | StackCount(..)
      | InCombat(..)
      | VitalPercent(..)
      | VitalCurrent(..)
      | ResourceSlot(..)
      | UnderGroup(..)
      | Stealthed(..)
      | Difficulty(..)
      | NoCase
      | Unread(..) -> 0
    }
  })
  |> int.sum
}

/// The bytes of one roll: 4, a draw r of a multiple of 2^-32 in [0, 1).
pub const roll_bytes = 4

/// The rolls from 1 to 100 that the bytes make, one for each 4 bytes: 1 +
/// floor(100 r) for the draw r the 4 bytes make as a 32-bit number over 2^32
/// (`Prerequisite.prerequisiteTypeId.37`). Bytes left over after the last whole
/// roll are dropped.
pub fn rolls_of(bytes bytes: BitArray) -> List(Int) {
  case bytes {
    <<word:size(32), rest:bytes>> -> [
      1 + word * 100 / 4_294_967_296,
      ..rolls_of(bytes: rest)
    ]
    _ -> []
  }
}

/// The prerequisite checked against its subject (`0x1404a1ca0`).
pub fn check(
  prerequisite prerequisite: Prerequisite,
  subject subject: Subject,
) -> Verdict {
  let #(verdict, _) = evaluated(prerequisite:, subject:, rolls: subject.rolls)
  verdict
}

/// The prerequisite's verdict and the rolls left after the conditions took theirs, in
/// order.
fn evaluated(
  prerequisite prerequisite: Prerequisite,
  subject subject: Subject,
  rolls rolls: List(Int),
) -> #(Verdict, List(Int)) {
  let #(left, verdicts) =
    list.map_fold(prerequisite.conditions, rolls, fn(rolls, condition) {
      condition_check(condition:, subject:, rolls:)
    })
  let #(decides, otherwise) = case prerequisite.any {
    True -> #(Passes, Fails)
    False -> #(Fails, Passes)
  }
  #(
    case list.contains(verdicts, decides) {
      True -> decides
      False ->
        case list.find(verdicts, fn(verdict) { verdict != otherwise }) {
          Ok(not_read) -> not_read
          Error(Nil) -> otherwise
        }
    },
    left,
  )
}

/// One condition's verdict, and the rolls left after it.
fn condition_check(
  condition condition: Condition,
  subject subject: Subject,
  rolls rolls: List(Int),
) -> #(List(Int), Verdict) {
  case condition {
    TargetOfLiveCast(comparison:, spell4_id:) -> #(rolls, case comparison {
      Found -> verdict_of(is_under(subject:, spell4_id:))
      NotFound -> verdict_of(!is_under(subject:, spell4_id:))
      OtherComparison(..) -> Fails
    })
    UnderCastBy(comparison:, spell4_id:) -> #(rolls, case comparison {
      Found -> verdict_of(is_under_cast_by(subject:, spell4_id:))
      NotFound -> verdict_of(!is_under_cast_by(subject:, spell4_id:))
      OtherComparison(..) -> Fails
    })
    StackCount(relation:, spell4_id:, value:) -> #(
      rolls,
      verdict_of(compare(
        relation:,
        measured: int.sum(
          list.filter_map(subject.under, fn(held) {
            case held.spell4_id == spell4_id {
              True -> Ok(held.count)
              False -> Error(Nil)
            }
          }),
        ),
        value:,
      )),
    )
    InCombat(comparison:) -> #(rolls, case comparison {
      Found -> verdict_of(subject.in_combat)
      NotFound -> verdict_of(!subject.in_combat)
      OtherComparison(..) -> Fails
    })
    Roll(relation:, value:) ->
      case rolls {
        [roll, ..left] -> #(
          left,
          verdict_of(compare(relation:, measured: roll, value:)),
        )
        [] -> #([], NotRead(prerequisite_type: 37))
      }
    VitalPercent(relation:, vital:, value:) -> #(
      rolls,
      case dict.get(subject.vitals, vital) {
        Ok(held) -> verdict_of(percent_compares(relation:, vital: held, value:))
        Error(Nil) -> NotRead(prerequisite_type: 71)
      },
    )
    VitalCurrent(relation:, vital:, value:) -> #(
      rolls,
      case dict.get(subject.vitals, vital) {
        Ok(held) ->
          verdict_of(compare(
            relation:,
            measured: float.truncate(held.current),
            value:,
          ))
        Error(Nil) -> NotRead(prerequisite_type: 73)
      },
    )
    Nested(comparison:, row:, ..) -> {
      let #(nested, rolls) = case row {
        Some(nested) -> evaluated(prerequisite: nested, subject:, rolls:)
        None -> #(Fails, rolls)
      }
      #(rolls, case comparison {
        NotFound -> negated(verdict: nested)
        Found | OtherComparison(..) -> nested
      })
    }
    ResourceSlot(relation:, slot:, value:) -> #(
      rolls,
      case subject.resource_slots {
        None -> NotRead(prerequisite_type: 64)
        Some(slots) ->
          verdict_of(floats_compare(
            relation:,
            measured: float32.rounded(slot_value(slots:, slot:)),
            value: float32.rounded(int.to_float(signed(value))),
          ))
      },
    )
    UnderGroup(comparison:, group:) -> #(rolls, case comparison {
      Found -> verdict_of(is_under_group(subject:, group:))
      NotFound -> verdict_of(!is_under_group(subject:, group:))
      OtherComparison(..) -> Fails
    })
    Stealthed(comparison:) -> #(rolls, stealthed_verdict(comparison:, subject:))
    Difficulty(relation:, object_id:) -> #(rolls, case subject.difficulty {
      Some(difficulty) ->
        verdict_of(compare(relation:, measured: difficulty, value: object_id))
      None -> NotRead(prerequisite_type: 179)
    })
    NoCase -> #(rolls, Fails)
    Unread(prerequisite_type:) -> #(rolls, NotRead(prerequisite_type:))
  }
}

/// A nested row's verdict under comparison 2: passes when it fails, and a row that is
/// not read stays not read.
fn negated(verdict verdict: Verdict) -> Verdict {
  case verdict {
    Passes -> Fails
    Fails -> Passes
    NotRead(..) -> verdict
  }
}

/// The slot's value, read from the slots the subject holds: a slot from 0 to 10 the
/// class does not hold, 11 or more and a number below 0 (the server's choice: no row
/// names one) read 0.0 (`0x1404a24bd`).
fn slot_value(slots slots: Dict(Int, Float), slot slot: Int) -> Float {
  use <- bool.guard(when: slot < 0 || slot >= 11, return: 0.0)
  result.unwrap(dict.get(slots, slot), 0.0)
}

/// Whether the subject is under a cast whose spell is in the spell group; group 0
/// matches none.
fn is_under_group(subject subject: Subject, group group: Int) -> Bool {
  group != 0
  && list.any(subject.under, fn(held) { list.contains(held.groups, group) })
}

/// Type 116's verdict: comparison 1 passes for a stealthed subject and 2 for one that is
/// not, any other fails, and a subject that holds no stealth is `NotRead(116)`
/// (`Prerequisite.prerequisiteTypeId.116`).
fn stealthed_verdict(
  comparison comparison: Comparison,
  subject subject: Subject,
) -> Verdict {
  case subject.stealthed {
    None -> NotRead(prerequisite_type: 116)
    Some(stealthed) ->
      case comparison {
        Found -> verdict_of(stealthed)
        NotFound -> verdict_of(!stealthed)
        OtherComparison(..) -> Fails
      }
  }
}

/// Whether a cast of the Spell4 holds a node on the subject.
fn is_under(subject subject: Subject, spell4_id spell4_id: Spell4Id) -> Bool {
  list.any(subject.under, fn(held) { held.spell4_id == spell4_id })
}

/// Whether a cast of the Spell4 by the subject's second unit holds a node on the
/// subject: with no second unit, a second unit 0 or a Spell4 0 none does
/// (`Prerequisite.prerequisiteTypeId.50`).
fn is_under_cast_by(
  subject subject: Subject,
  spell4_id spell4_id: Spell4Id,
) -> Bool {
  case subject.second_unit {
    None | Some(0) -> False
    Some(second_unit) ->
      spell4_id.value != 0
      && list.any(subject.under, fn(held) {
        held.spell4_id == spell4_id && held.caster == second_unit
      })
  }
}

fn verdict_of(holds: Bool) -> Verdict {
  use <- bool.guard(when: holds, return: Passes)
  Fails
}

/// Type 71's comparison: the vital's percentage of its maximum against the value
/// made a 32-bit float, in 32-bit floats as the client computes it
/// (`0x1404a4e30`). Nothing held of nothing is not a number, which counts as equal
/// and fails every other comparison; something held of nothing is beyond every
/// value.
fn percent_compares(
  relation relation: Relation,
  vital vital: Vital,
  value value: Int,
) -> Bool {
  let wanted = float32.rounded(int.to_float(unsigned(value)))
  case vital.maximum == 0.0, vital.current == 0.0 {
    True, True ->
      case relation {
        Equal -> True
        NotEqual | Greater | AtLeast | Less | AtMost | NeverRelation(..) ->
          False
      }
    True, False -> floats_compare(relation:, measured: 3.4e38, value: wanted)
    False, _ ->
      floats_compare(
        relation:,
        measured: float32.rounded(
          float32.rounded(vital.current *. 100.0) /. vital.maximum,
        ),
        value: wanted,
      )
  }
}

fn floats_compare(
  relation relation: Relation,
  measured measured: Float,
  value value: Float,
) -> Bool {
  holds(relation:, ordering: float.compare(measured, value))
}
