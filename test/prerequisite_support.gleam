//// Prerequisite rows for tests that check a prerequisite
//// (`genesis_prime/game/prerequisite`), built as the client's table holds them.

import genesis_prime/game/area.{type Pose, Point, Pose}
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{type Prerequisite, type Subject, Subject}
import genesis_prime/game/quest_log.{type Quest, type QuestRowError}
import genesis_prime/table/id.{PrerequisiteId, Spell4Id}
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None}

/// A Prerequisite row with these conditions, as (type, comparison, objectId,
/// value), and these flags.
pub fn row(
  id id: Int,
  flags flags: Int,
  conditions conditions: List(#(Int, Int, Int, Int)),
) -> prerequisite_table.Prerequisite {
  let at = fn(index) {
    case list.drop(conditions, index) {
      [condition, ..] -> condition
      [] -> #(0, 0, 0, 0)
    }
  }
  let #(type0, comparison0, object0, value0) = at(0)
  let #(type1, comparison1, object1, value1) = at(1)
  let #(type2, comparison2, object2, value2) = at(2)
  prerequisite_table.Prerequisite(
    id:,
    flags:,
    prerequisite_type_id0: type0,
    prerequisite_type_id1: type1,
    prerequisite_type_id2: type2,
    prerequisite_comparison_id0: comparison0,
    prerequisite_comparison_id1: comparison1,
    prerequisite_comparison_id2: comparison2,
    object_id0: object0,
    object_id1: object1,
    object_id2: object2,
    value0:,
    value1:,
    value2:,
    localized_text_id_failure: 0,
  )
}

/// A condition type the server does not read: the lowest of 1 to 300 that
/// `prerequisite.is_read` refuses.
pub fn unread_type() -> Int {
  let lowest =
    int.range(from: 300, to: 0, with: 0, run: fn(lowest, type_id) {
      case prerequisite.is_read(type_id:) {
        True -> lowest
        False -> type_id
      }
    })
  assert lowest > 0 as "some condition type below 301 is not read"
  lowest
}

/// The prerequisite of a row with one condition, as (type, comparison, objectId,
/// value), under AND.
pub fn single(
  id id: Int,
  condition condition: #(Int, Int, Int, Int),
) -> Prerequisite {
  loaded(id:, rows: [row(id:, flags: 0, conditions: [condition])])
}

/// The PositionalRequirement rows of a planted table that holds none.
pub fn no_arcs() -> fn(Int) ->
  Result(positional_requirement.PositionalRequirement, Nil) {
  fn(_) { Error(Nil) }
}

/// The prerequisite with this id as `load` makes it from rows held in memory: the
/// planted table is these rows, and it holds no PositionalRequirement row.
pub fn load_from(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
) -> Result(Prerequisite, prerequisite.LoadError) {
  load_with_arcs(id:, rows:, arcs: [])
}

/// The Quest2 lookup of a planted table that holds no quest: every quest is unknown to
/// the client.
pub fn no_quests() -> fn(Int) -> Result(Quest, QuestRowError) {
  fn(_) { Error(quest_log.NoQuestRow) }
}

/// The same, whose type 108 conditions find their PositionalRequirement rows among
/// `arcs`, as the client's table holds them (`table_rows -- PositionalRequirement 53`).
pub fn load_with_arcs(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
  arcs arcs: List(positional_requirement.PositionalRequirement),
) -> Result(Prerequisite, prerequisite.LoadError) {
  load_with(id:, rows:, arcs:, quests: no_quests())
}

/// The same, whose quest conditions find their quests through `quests`.
pub fn load_with(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
  arcs arcs: List(positional_requirement.PositionalRequirement),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
) -> Result(Prerequisite, prerequisite.LoadError) {
  prerequisite.load(
    id: PrerequisiteId(id),
    rows: fn(wanted) { list.find(rows, fn(row) { row.id == wanted.value }) },
    arcs: fn(wanted) { list.find(arcs, fn(arc) { arc.id == wanted }) },
    quests:,
  )
}

/// The same, which must load.
pub fn loaded(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
) -> Prerequisite {
  loaded_with_arcs(id:, rows:, arcs: [])
}

/// The same with the arcs, which must load.
pub fn loaded_with_arcs(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
  arcs arcs: List(positional_requirement.PositionalRequirement),
) -> Prerequisite {
  let assert Ok(loaded) = load_with_arcs(id:, rows:, arcs:)
    as "the rows held in memory load: every id they name has a row"
  loaded
}

/// The prerequisite of a row that holds no nested row and no type 108 condition.
pub fn prerequisite_of(
  row row: prerequisite_table.Prerequisite,
) -> Prerequisite {
  loaded(id: row.id, rows: [row])
}

/// The prerequisite of a row whose type 108 conditions find their PositionalRequirement
/// rows among `arcs`.
pub fn prerequisite_of_arcs(
  row row: prerequisite_table.Prerequisite,
  arcs arcs: List(positional_requirement.PositionalRequirement),
) -> Prerequisite {
  loaded_with_arcs(id: row.id, rows: [row], arcs:)
}

/// A PositionalRequirement row: its id, angleCenter, angleRange and flags.
pub fn arc_row(
  id id: Int,
  center center: Int,
  range range: Int,
  flags flags: Int,
) -> positional_requirement.PositionalRequirement {
  positional_requirement.PositionalRequirement(
    id:,
    angle_center: center,
    angle_range: range,
    flags:,
  )
}

/// Row 53 of the client's PositionalRequirement table: the 140 degrees behind the first
/// unit (`table_rows -- PositionalRequirement 53`: angleCenter 180, angleRange 140,
/// flags 0).
pub fn behind_arc() -> positional_requirement.PositionalRequirement {
  arc_row(id: 53, center: 180, range: 140, flags: 0)
}

/// A subject holding these nodes (spell, caster, stack count), whose second unit is
/// `second_unit`, out of combat, with no vital, difficulty, stealth or roll.
pub fn holding(
  held held: List(#(Int, Int, Int)),
  second_unit second_unit: Option(Int),
) -> Subject {
  Subject(
    under: list.map(held, fn(node) {
      lasting.Held(
        spell4_id: Spell4Id(node.0),
        caster: node.1,
        count: node.2,
        groups: [],
      )
    }),
    second_unit:,
    in_combat: False,
    vitals: dict.new(),
    rolls: [],
    difficulty: None,
    stealthed: None,
    resource_slots: None,
    positions: prerequisite.NotPlaced,
    factions: None,
    player: None,
    quests: None,
    seen: prerequisite.WholeUnit,
  )
}

/// The row checked against the subject.
pub fn check(
  row row: prerequisite_table.Prerequisite,
  subject subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: loaded(id: row.id, rows: [row]), subject:)
}

/// What the prerequisite with one condition, id 1, gives for the subject.
pub fn verdict(
  condition condition: #(Int, Int, Int, Int),
  subject subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: single(id: 1, condition:), subject:)
}

/// A standing place: the point (`x`, `z`) facing `yaw`.
pub fn pose(x x: Float, z z: Float, yaw yaw: Float) -> Pose {
  Pose(at: Point(x:, z:), yaw:)
}
