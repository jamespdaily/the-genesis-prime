//// A Prerequisite row as the client reads it, and its check against a unit: the
//// gate of an effect such as a resource gain, or of a Proxy
//// (genesis_prime/game/spell_plan `Gain`, `Condition`). The rule is pure: the
//// cast rule (genesis_prime/game/cast) supplies what the unit is, and the
//// connection supplies the rolls from its seed.
////
//// ```
//// Prerequisite row ─▶ of_row: the conditions kept up to the first type 0, AND or OR
////                     (a type 108 condition finds its PositionalRequirement row once)
//// a Subject: the casts it is under, in combat, its vitals, its difficulty, its rolls,
////            where its two units stand
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
//// - **Type 108** passes, by comparison 1, when the check's second unit stands in the arc
////   of the PositionalRequirement row in its objectId around the first unit's facing, and
////   by comparison 2 when it does not; any other comparison fails, and its value is not
////   read. The arc runs from angleCenter - angleRange / 2 to angleCenter + angleRange / 2
////   degrees off the facing, the direction runs from the first unit to the second as
////   atan2(-(x2 - x1), -(z2 - z1)), flags bit 0 swaps the units, each arc end is wrapped
////   into -pi..pi, and an arc whose end is below its start crosses the wrap; both ends are
////   inside. With no second unit, objectId 0 or no row, comparison 2 passes and any other
////   fails. The arithmetic is in 32-bit floats in the client's order, with `atan2` taken
////   in 64 bits and rounded to 32 (the BEAM has no atan2f), so a direction within one
////   32-bit step of an arc end may fall on the other side than the client's
////   (`Prerequisite.prerequisiteTypeId.108`, `0x14049d940`). The client reads an objectId
////   with no row as no arc; no row of the game names one, so the load refuses it
////   (`of_row`), as it refuses any table row that is missing.
//// - **A type with no case** in the client, 0 or one above 295, fails
////   (`0x1404a2100`).
//// - **The units:** a check's first unit is its subject. A caster-side check has the
////   caster for both units (`Spell4Effects.prerequisiteIdTargetApply` gives the target
////   first and the caster second for a target-side one): the subject's `second_unit` and
////   `positions`. A struck creature is known by its place alone (`of_struck`), so every
////   condition that reads what else it holds is `NotRead`.

import genesis_prime/game/area.{type Pose}
import genesis_prime/game/lasting
import genesis_prime/message/float32
import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4Id, PrerequisiteId, Spell4Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam_community/maths

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
  /// Type 116: whether the unit is stealthed
  /// (`Prerequisite.prerequisiteTypeId.116`).
  Stealthed(comparison: Comparison)
  /// Type 179: the unit's difficulty against the objectId
  /// (`Prerequisite.prerequisiteTypeId.179`, `0x14049eeb0`).
  Difficulty(relation: Relation, object_id: Int)
  /// Type 108: whether the second unit stands in the arc around the first unit's
  /// facing, `None` for the objectId 0 that names no arc
  /// (`Prerequisite.prerequisiteTypeId.108`, `0x14049d940`).
  InArc(comparison: Comparison, arc: Option(Arc))
  /// A type the client's check has no case for (`0x1404a2100`): it fails.
  NoCase
  /// A type the client decides and the server does not read.
  Unread(prerequisite_type: Int)
}

/// A PositionalRequirement row, decoded once: the arc's centre and range in degrees and
/// whether it turns with the check's second unit (flags bit 0).
type Arc {
  Arc(center: Int, range: Int, turns_with_second: Bool)
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
    /// The rolls for the type 37 conditions of the check, one for each, in the
    /// order the conditions are tested (`rolls_needed`).
    rolls: List(Int),
    /// Where the check's two units stand, for type 108.
    positions: Positions,
    /// What the check knows of the subject.
    seen: Seen,
  )
}

/// Where the check's units stand, for type 108.
pub type Positions {
  /// Each unit's ground point and yaw.
  Placed(first: Pose, second: Pose)
  /// The check has no second unit.
  NoSecondUnit
  /// A unit's place is not held.
  NotPlaced
}

/// What a check knows of its subject.
pub type Seen {
  /// Every field of the subject holds.
  WholeUnit
  /// Only the place of the subject holds.
  PlaceOnly
}

/// The subject of a unit the caster struck, for a target-side check (a Proxy's target apply
/// prerequisite): the struck unit first with the pose its place and facing give in the
/// caster's picture, `None` when the picture no longer shows it, and the caster second.
/// The connection holds none of a creature's casts, combat state or vitals, so the subject
/// holds none of them either: a condition that reads what else it holds is `NotRead`
/// (`PlaceOnly`), where an empty `under` would read as "under no cast" and pass a
/// condition that asks for the absence of one.
pub fn of_struck(
  first first: Option(Pose),
  second second: Pose,
  second_unit second_unit: Int,
) -> Subject {
  Subject(
    under: [],
    second_unit: Some(second_unit),
    in_combat: False,
    vitals: dict.new(),
    difficulty: None,
    stealthed: None,
    rolls: [],
    positions: case first {
      Some(first) -> Placed(first:, second:)
      None -> NotPlaced
    },
    seen: PlaceOnly,
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
    rolls: [],
    positions: NotPlaced,
    seen: WholeUnit,
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

/// Why a row cannot be decoded.
pub type Error {
  /// A type 108 condition names a PositionalRequirement row the table lacks.
  MissingRow(table: String, id: Int)
}

/// The row as the client keeps it (`0x1404a5190`), its type 108 conditions reading their
/// PositionalRequirement rows from the loaded tables.
pub fn of_row(
  row row: prerequisite_table.Prerequisite,
  tables tables: table_store.Tables,
) -> Result(Prerequisite, Error) {
  of_row_with(row:, find_arc: fn(arc_id) {
    positional_requirement.get(tables:, id: id.PositionalRequirementId(arc_id))
  })
}

/// The row as the client keeps it, its type 108 conditions finding their
/// PositionalRequirement rows with `find_arc`: the decode `of_row` does over the
/// loaded table, for a caller that holds the rows in memory. A type 108 condition whose
/// objectId is not 0 and names no row is `MissingRow`.
pub fn of_row_with(
  row row: prerequisite_table.Prerequisite,
  find_arc find_arc: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
) -> Result(Prerequisite, Error) {
  use conditions <- result.try(
    list.try_map(kept_conditions(row:), fn(condition) {
      condition_read(
        type_id: condition.0,
        comparison: condition.1,
        object_id: condition.2,
        value: condition.3,
        find_arc:,
      )
    }),
  )
  Ok(Prerequisite(id: PrerequisiteId(row.id), any: is_any(row:), conditions:))
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

/// A condition decoded: type 108 reads its arc through `find_arc`, every other type is
/// `condition_of`.
fn condition_read(
  type_id type_id: Int,
  comparison comparison: Int,
  object_id object_id: Int,
  value value: Int,
  find_arc find_arc: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
) -> Result(Condition, Error) {
  case type_id {
    108 ->
      arc_of(object_id:, find_arc:)
      |> result.map(fn(arc) {
        InArc(comparison: comparison_of(comparison), arc:)
      })
    _ -> Ok(condition_of(type_id:, comparison:, object_id:, value:))
  }
}

/// The arc a type 108 condition's objectId names: none for 0, which the client reads as no
/// arc (`0x14049d96b`), else the row's.
fn arc_of(
  object_id object_id: Int,
  find_arc find_arc: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
) -> Result(Option(Arc), Error) {
  case object_id {
    0 -> Ok(None)
    arc_id ->
      case find_arc(arc_id) {
        Ok(row) ->
          Ok(
            Some(Arc(
              center: row.angle_center,
              range: row.angle_range,
              turns_with_second: int.bitwise_and(row.flags, 1) == 1,
            )),
          )
        Error(Nil) ->
          Error(MissingRow(table: "PositionalRequirement", id: arc_id))
      }
  }
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
  case
    condition_read(
      type_id:,
      comparison: 0,
      object_id: 0,
      value: 0,
      find_arc: fn(_) { Error(Nil) },
    )
  {
    Ok(Unread(..)) -> False
    Ok(TargetOfLiveCast(..))
    | Ok(UnderCastBy(..))
    | Ok(StackCount(..))
    | Ok(InCombat(..))
    | Ok(Roll(..))
    | Ok(VitalPercent(..))
    | Ok(VitalCurrent(..))
    | Ok(Stealthed(..))
    | Ok(Difficulty(..))
    | Ok(InArc(..))
    | Ok(NoCase)
    | Error(MissingRow(..)) -> True
  }
}

/// The prerequisite's Prerequisite id.
pub fn id(prerequisite prerequisite: Prerequisite) -> PrerequisiteId {
  prerequisite.id
}

/// How many rolls a check of the prerequisite takes: one for each type 37
/// condition kept.
pub fn rolls_needed(prerequisite prerequisite: Prerequisite) -> Int {
  list.count(prerequisite.conditions, fn(condition) {
    case condition {
      Roll(..) -> True
      TargetOfLiveCast(..)
      | UnderCastBy(..)
      | StackCount(..)
      | InCombat(..)
      | VitalPercent(..)
      | VitalCurrent(..)
      | Stealthed(..)
      | Difficulty(..)
      | InArc(..)
      | NoCase
      | Unread(..) -> False
    }
  })
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
  let #(_, verdicts) =
    list.map_fold(prerequisite.conditions, subject.rolls, fn(rolls, condition) {
      condition_check(condition:, subject:, rolls:)
    })
  let #(decides, otherwise) = case prerequisite.any {
    True -> #(Passes, Fails)
    False -> #(Fails, Passes)
  }
  case list.contains(verdicts, decides) {
    True -> decides
    False ->
      case list.find(verdicts, fn(verdict) { verdict != otherwise }) {
        Ok(not_read) -> not_read
        Error(Nil) -> otherwise
      }
  }
}

/// One condition's verdict, and the rolls left after it. A subject known by its place alone
/// gives `NotRead` for a condition that reads what else the unit holds, and takes no roll.
fn condition_check(
  condition condition: Condition,
  subject subject: Subject,
  rolls rolls: List(Int),
) -> #(List(Int), Verdict) {
  case subject.seen, reads_held_state(condition:) {
    PlaceOnly, Some(prerequisite_type) -> #(rolls, NotRead(prerequisite_type:))
    PlaceOnly, None | WholeUnit, _ ->
      condition_decided(condition:, subject:, rolls:)
  }
}

/// The type of a condition that reads the casts, combat state, vitals or rolls of its
/// unit, which a subject known by its place alone does not hold.
fn reads_held_state(condition condition: Condition) -> Option(Int) {
  case condition {
    TargetOfLiveCast(..) -> Some(15)
    UnderCastBy(..) -> Some(50)
    StackCount(..) -> Some(59)
    InCombat(..) -> Some(28)
    Roll(..) -> Some(37)
    VitalPercent(..) -> Some(71)
    VitalCurrent(..) -> Some(73)
    Stealthed(..) | Difficulty(..) | InArc(..) | NoCase | Unread(..) -> None
  }
}

fn condition_decided(
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
    Stealthed(comparison:) -> #(rolls, stealthed_verdict(comparison:, subject:))
    Difficulty(relation:, object_id:) -> #(rolls, case subject.difficulty {
      Some(difficulty) ->
        verdict_of(compare(relation:, measured: difficulty, value: object_id))
      None -> NotRead(prerequisite_type: 179)
    })
    InArc(comparison:, arc:) -> #(
      rolls,
      arc_verdict(comparison:, arc:, positions: subject.positions),
    )
    NoCase -> #(rolls, Fails)
    Unread(prerequisite_type:) -> #(rolls, NotRead(prerequisite_type:))
  }
}

/// Type 108's verdict (`0x14049d940`). The client decides "no arc" first, with no unit's
/// place read: no second unit or no arc, and comparison 2 passes while any other fails. Else
/// comparison 1 passes inside the arc and 2 outside it, and any other fails; a unit whose
/// place is not held leaves it `NotRead(108)`.
fn arc_verdict(
  comparison comparison: Comparison,
  arc arc: Option(Arc),
  positions positions: Positions,
) -> Verdict {
  case arc, positions {
    None, _ | Some(_), NoSecondUnit ->
      case comparison {
        NotFound -> Passes
        Found | OtherComparison(..) -> Fails
      }
    Some(_), NotPlaced -> NotRead(prerequisite_type: 108)
    Some(arc), Placed(first:, second:) ->
      case comparison {
        Found -> verdict_of(in_arc(arc:, first:, second:))
        NotFound -> verdict_of(!in_arc(arc:, first:, second:))
        OtherComparison(..) -> Fails
      }
  }
}

/// pi, 2 pi and 1/180 as the client holds them, 32-bit floats: 0x40490fdb at 0x140b79fac
/// and 0x140c3b438, 0x40c90fdb at 0x140b7a018 and 0x3bb60b61 at 0x140b79d28.
const half_turn = 3.1415927410125732

const full_turn = 6.2831854820251465

const one_over_180 = 0.0055555556900799274

/// Whether the direction from the turning unit to the other lies in the arc turned by the
/// turning unit's yaw, in 32-bit floats in the client's order (`0x14049d940`): the arc's
/// ends are `(center - half) * radians_per_degree + yaw` and `(half + center) *
/// radians_per_degree + yaw` for half the range and radians_per_degree = pi * (1/180), each
/// wrapped into -pi..pi; an end below the start crosses the wrap.
/// Flags bit 0 makes the second unit the turning one. `atan2` has no 32-bit form in the
/// BEAM: it is taken in 64 bits and rounded.
fn in_arc(arc arc: Arc, first first: Pose, second second: Pose) -> Bool {
  let #(turning, other) = case arc.turns_with_second {
    False -> #(first, second)
    True -> #(second, first)
  }
  let yaw = float32.rounded(turning.yaw)
  let radians_per_degree = float32.product(left: half_turn, right: one_over_180)
  let center = float32.rounded(int.to_float(unsigned(arc.center)))
  let half =
    float32.product(
      left: float32.rounded(int.to_float(unsigned(arc.range))),
      right: 0.5,
    )
  let start =
    wrapped(angle: float32.rounded(
      float32.product(
        left: float32.rounded(center -. half),
        right: radians_per_degree,
      )
      +. yaw,
    ))
  let end =
    wrapped(angle: float32.rounded(
      float32.product(
        left: float32.rounded(half +. center),
        right: radians_per_degree,
      )
      +. yaw,
    ))
  let direction =
    float32.rounded(maths.atan2(
      float.negate(float32.rounded(
        float32.rounded(other.at.x) -. float32.rounded(turning.at.x),
      )),
      float.negate(float32.rounded(
        float32.rounded(other.at.z) -. float32.rounded(turning.at.z),
      )),
    ))
  case end <. start {
    True -> direction >=. start || direction <=. end
    False -> direction >=. start && direction <=. end
  }
}

/// An arc end wrapped into -pi..pi: for x at least 0, fmod(x + pi, 2 pi) - pi, else
/// fmod(x - pi, 2 pi) + pi, each step in 32 bits (`0x14049d940`). The remainder of two
/// 32-bit floats is exact.
fn wrapped(angle angle: Float) -> Float {
  case angle <. 0.0 {
    True ->
      float32.rounded(
        remainder(float32.rounded(angle -. half_turn), full_turn) +. half_turn,
      )
    False ->
      float32.rounded(
        remainder(float32.rounded(angle +. half_turn), full_turn) -. half_turn,
      )
  }
}

/// C's `fmod`: the remainder of x over y with the sign of x. No Gleam library has it:
/// `float.modulo` is the floored modulo, which differs for a negative x, and the maths
/// package's modulo is Euclidean.
@external(erlang, "math", "fmod")
fn remainder(x: Float, y: Float) -> Float

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
