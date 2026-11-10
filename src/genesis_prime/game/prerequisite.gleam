//// A Prerequisite row as the client reads it, and its check against a unit: the
//// gate of an effect such as a resource gain, or of a Proxy
//// (genesis_prime/game/spell_plan `Gain`, `Condition`). The rule is pure: the
//// cast rule (genesis_prime/game/cast) supplies what the unit is, and the
//// connection supplies the rolls from its seed.
////
//// ```
//// Prerequisite row ─▶ load: the conditions kept up to the first type 0, AND or OR,
////                          each nested row (type 11) loaded in place, each type 108
////                          condition finding its PositionalRequirement row, each quest
////                          condition its quest; a cycle fails
//// a Subject: the casts it is under, in combat, its vitals, its resource slots,
////            its difficulty, its rolls, where its two units stand, its quest log
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
//// - **Type 4** passes, by comparison 1, when the unit's current faction equals the
////   value and by comparison 2 when it does not; any other comparison fails, a unit
////   with no faction counts as faction 0 and its objectId is not read. **Type 250**
////   is the same on the unit's base faction (`Prerequisite.prerequisiteTypeId.4`,
////   `.250`, `0x14049c620`, `0x14049c6a0`). Only a player's side holds its factions,
////   so a subject with none gives `NotRead`.
//// - **Type 10** passes, by comparison 1, when the player's gender equals the value
////   and by comparison 2 when it does not; any other comparison fails, and its
////   objectId is not read. The gender is the one the unit-create message 0x262
////   carries (0 male, 1 female). Only a subject that holds the player (`Player`)
////   decides it, so another gives `NotRead`
////   (`Prerequisite.prerequisiteTypeId.10`, `0x14049c5e0`).
//// - **Type 109** passes, by comparison 1, when the player's World is the World the
////   objectId names and by comparison 2 when it is another; any other comparison
////   fails, and its value is not read. A subject that holds no player gives
////   `NotRead` (`Prerequisite.prerequisiteTypeId.109`, `0x14049e780`).
//// - **Type 1** compares the first unit's level for formulas (`Player.level`) with
////   the value by comparisons 1 to 6, unsigned, any other fails, and its objectId
////   is not read (`Prerequisite.prerequisiteTypeId.1`, `0x1403b5030`). **Types 2, 3
////   and 52** pass, by comparison 1, when the player's race, class or path equals
////   the value and by comparison 2 when it does not; any other comparison fails,
////   and the objectId is not read (`Prerequisite.prerequisiteTypeId.2`, `.3`,
////   `.52`).
//// - **Type 26** passes, by comparison 1, when the value is a zone the player is in
////   or one above it (`Player.zones`: the zone, then each parent through the
////   WorldZone table's parentZoneId), by comparison 2 when it is none; any other
////   comparison fails, and the objectId is not read
////   (`Prerequisite.prerequisiteTypeId.26`, `0x14049e680`).
//// - **Type 39** passes, by comparison 1, when the first unit is a player and by
////   comparison 2 when it is another; any other comparison fails, and the objectId
////   and the value are not read (`Prerequisite.prerequisiteTypeId.39`). A subject
////   that holds a player has the player as its first unit.
//// - **A subject known by its place alone** (`Seen`) holds the player's facts but
////   not the first unit's, so types 1, 3 and 39, which read that unit, give
////   `NotRead` for it; a subject that holds no player gives `NotRead` for all of
////   these types.
//// - **Type 243** always fails: the client's check reads nothing from the unit
////   (`Prerequisite.prerequisiteTypeId.243`, `0x140001ba0`).
//// - **Type 179** compares the unit's difficulty with the condition's objectId, not
////   its value, by comparisons 1 to 6; only a creature's side holds a difficulty,
////   so a subject with none gives `NotRead` (`0x14049eeb0`, `of_difficulty`).
//// - **Type 6** compares the state of the quest the objectId names, in the quest log of
////   the player whose client runs the check, with the value: the state the client
////   derives (`quest_log.state`, `0x1405fbc40`), states 4 to 7 counted as 0, comparison
////   1 equal and 2 not equal, any other fails. **Type 68** passes, by comparison 1, when
////   objective `value` of that quest is done and by comparison 2 when it is not
////   (`quest_log.objective_done`, `0x1405510d0`). **Type 43** passes, by comparison 1,
////   when that objective is open: the quest is in the active list, the objective is not
////   done and it is reachable, and by comparison 2 when it is not
////   (`quest_log.objective_open`, `0x14049f3d0`). **Types 22, 23, 33, 34, 35 and 36**
////   compare the progress of objective 0, 1, 2, 3, 4 and 5 of that quest with the value
////   by comparisons 1 to 6, progress on the left (`quest_log.objective_progress`,
////   `0x14049f4d0`). A quest with no Quest2 row is the client's unknown quest: state 0,
////   not done, not open, progress 0. Each condition holds its quest, read once at the
////   load, so a check needs no table; a QuestObjective row a quest names and the table
////   lacks fails the load. A subject with no quest log gives `NotRead`
////   (`Prerequisite.prerequisiteTypeId.6`, `.68`, `.43`, `.22`).
//// - **Type 125** passes, by comparison 2, when the player's challenge is not in
////   cooldown and fails by comparison 1 and any other: a challenge the server has sent
////   no record for is not in cooldown, and the server sends none, so comparison 2 always
////   passes; the objectId and the value are not read
////   (`Prerequisite.prerequisiteTypeId.125`, `0x14049fac0`). Gap: the records of
////   challenges are issue 52's.
//// - **Type 94** (the target is counted by a checklist objective) passes by comparison
////   2 and fails every other: the server holds no counted-targets mask yet, so no target
////   is counted (`Prerequisite.prerequisiteTypeId.94`).
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
////   (`load`), as it refuses any table row that is missing.
//// - **A type with no case** in the client, 0 or one above 295, fails
////   (`0x1404a2100`).
//// - **The units:** a check's first unit is its subject. A caster-side check has the
////   caster for both units (`Spell4Effects.prerequisiteIdTargetApply` gives the target
////   first and the caster second for a target-side one): the subject's `second_unit` and
////   `positions`. A struck creature is known by its place alone (`of_struck`), so every
////   condition that reads what else it holds is `NotRead`.

import genesis_prime/game/area.{type Pose}
import genesis_prime/game/lasting
import genesis_prime/game/quest_log.{
  type Quest, type QuestLog, type QuestRowError,
}
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
  /// Type 4: whether the unit's current faction equals the value
  /// (`Prerequisite.prerequisiteTypeId.4`, `0x14049c620`).
  CurrentFaction(comparison: Comparison, value: Int)
  /// Type 250: whether the unit's base faction equals the value
  /// (`Prerequisite.prerequisiteTypeId.250`, `0x14049c6a0`).
  BaseFaction(comparison: Comparison, value: Int)
  /// Type 1: the first unit's level for formulas against the value
  /// (`Prerequisite.prerequisiteTypeId.1`, `0x1403b5030`).
  UnitLevel(relation: Relation, value: Int)
  /// Type 2: whether the player's race equals the value
  /// (`Prerequisite.prerequisiteTypeId.2`, `0x14049c4e0`).
  PlayerRace(comparison: Comparison, value: Int)
  /// Type 3: whether the first unit's class equals the value
  /// (`Prerequisite.prerequisiteTypeId.3`, `0x14049c560`).
  UnitClass(comparison: Comparison, value: Int)
  /// Type 26: whether the player is in the WorldZone the value names or under it
  /// (`Prerequisite.prerequisiteTypeId.26`, `0x1403c92e0`).
  InZone(comparison: Comparison, value: Int)
  /// Type 39: whether the first unit is a player
  /// (`Prerequisite.prerequisiteTypeId.39`).
  IsPlayer(comparison: Comparison)
  /// Type 52: whether the player's path equals the value
  /// (`Prerequisite.prerequisiteTypeId.52`, `0x14049fd50`).
  PlayerPath(comparison: Comparison, value: Int)
  /// Type 10: whether the player's gender equals the value
  /// (`Prerequisite.prerequisiteTypeId.10`, `0x14049c5e0`).
  Gender(comparison: Comparison, value: Int)
  /// Type 109: whether the player's world is the World the objectId names
  /// (`Prerequisite.prerequisiteTypeId.109`, `0x14049e780`).
  InWorld(comparison: Comparison, world_id: Int)
  /// Type 6: the state of the quest against the value
  /// (`Prerequisite.prerequisiteTypeId.6`, `0x14049f690`). `quest` is none for a quest
  /// with no Quest2 row, which the client reads as state 0, and for a condition
  /// decoded without a table (`is_read`).
  QuestState(comparison: Comparison, value: Int, quest: Option(Quest))
  /// Type 68: whether the quest's objective `index` is done
  /// (`Prerequisite.prerequisiteTypeId.68`).
  ObjectiveDone(comparison: Comparison, index: Int, quest: Option(Quest))
  /// Type 43: whether the quest's objective `index` is open
  /// (`Prerequisite.prerequisiteTypeId.43`).
  ObjectiveOpen(comparison: Comparison, index: Int, quest: Option(Quest))
  /// Type 94: whether the target is counted by a checklist objective
  /// (`Prerequisite.prerequisiteTypeId.94`).
  TargetCounted(comparison: Comparison)
  /// Types 22, 23, 33, 34, 35 and 36: the progress of the quest's objective `index`
  /// (0 to 5) against the value (`Prerequisite.prerequisiteTypeId.22`).
  ObjectiveProgress(
    prerequisite_type: Int,
    relation: Relation,
    index: Int,
    value: Int,
    quest: Option(Quest),
  )
  /// Type 125: whether the player's challenge is in cooldown; the server holds no
  /// challenge record, so it is never in cooldown
  /// (`Prerequisite.prerequisiteTypeId.125`, `0x14049fac0`).
  ChallengeInCooldown(comparison: Comparison)
  /// Type 243: never met (`Prerequisite.prerequisiteTypeId.243`, `0x140001ba0`).
  NeverMet
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

/// A unit's two factions, Faction2 ids, as the faction message 0x262 sets them: its
/// current faction (the first faction field) and its base faction (the second). A unit
/// with no faction has 0 (`Prerequisite.prerequisiteTypeId.4`, `.250`).
pub type Factions {
  Factions(current: Int, base: Int)
}

/// What the client's player record holds that the conditions on the player read:
/// the character's race, class, path and gender, its level, the World it is in and
/// the zones it stands in.
pub type Player {
  Player(
    /// The Race id.
    race_id: Int,
    /// The Class id.
    class_id: Int,
    /// The level the client's formulas read: the level override when it is not 0,
    /// else the level.
    level: Int,
    /// The path (0 Soldier, 1 Settler, 2 Scientist, 3 Explorer).
    path: Int,
    /// The gender (0 male, 1 female).
    gender: Int,
    /// The World id the player is in.
    world_id: Int,
    /// The WorldZone ids the player is in: its current zone first, then each
    /// parent zone above it.
    zones: List(Int),
  )
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
    /// Where the check's two units stand, for type 108.
    positions: Positions,
    /// The subject's factions, which only a player's cast rule holds: `None` for a
    /// creature's side, so types 4 and 250 are not read for it
    /// (`Prerequisite.prerequisiteTypeId.4`, `.250`).
    factions: Option(Factions),
    /// The player the check runs for, which only a player's side holds: `None` for
    /// a creature's side, so the types on the player (1, 2, 3, 10, 26, 39, 52 and
    /// 109) are not read for it. The player is the check's first unit.
    player: Option(Player),
    /// The quest log of the player whose client runs the check, which only a player's
    /// cast rule holds: `None` for a creature's side, so types 6, 68, 43 and 22 to 36
    /// are not read for it (`Prerequisite.prerequisiteTypeId.6`, `.68`, `.43`, `.22`).
    quests: Option(QuestLog),
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
/// caster's picture, `None` when the picture no longer shows it, and the caster second;
/// the quest log and the player's facts are the caster's, whose client runs the check.
/// The connection holds none of a creature's casts, combat state or vitals, so the subject
/// holds none of them either: a condition that reads what else it holds is `NotRead`
/// (`PlaceOnly`), where an empty `under` would read as "under no cast" and pass a
/// condition that asks for the absence of one.
pub fn of_struck(
  first first: Option(Pose),
  second second: Pose,
  player player: Player,
  quests quests: QuestLog,
) -> Subject {
  Subject(
    under: [],
    second_unit: None,
    in_combat: False,
    vitals: dict.new(),
    difficulty: None,
    stealthed: None,
    resource_slots: None,
    rolls: [],
    positions: case first {
      Some(first) -> Placed(first:, second:)
      None -> NotPlaced
    },
    factions: None,
    player: Some(player),
    quests: Some(quests),
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
    resource_slots: None,
    rolls: [],
    positions: NotPlaced,
    factions: None,
    player: None,
    quests: None,
    seen: WholeUnit,
  )
}

/// A subject that is a player about to wear an item: its factions and the player's
/// facts, under no cast, out of combat, with no vital and no roll. The equip
/// check's prerequisites (genesis_prime/game/equip_requirement) are checked
/// against it.
pub fn of_wearer(
  factions factions: Factions,
  player player: Player,
) -> Subject {
  Subject(
    under: [],
    second_unit: None,
    in_combat: False,
    vitals: dict.new(),
    difficulty: None,
    stealthed: None,
    resource_slots: None,
    rolls: [],
    positions: NotPlaced,
    factions: Some(factions),
    player: Some(player),
    quests: None,
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

/// Why a prerequisite does not load.
pub type LoadError {
  /// The row the load started from is not in the table.
  NoPrerequisiteRow(id: PrerequisiteId)
  /// A row nests itself through the rows on the way, the ids in order with the
  /// repeated one last.
  PrerequisiteCycle(path: List(PrerequisiteId))
  /// A type 108 condition names a PositionalRequirement row the table lacks. The client
  /// reads an objectId with no row as no arc; no row of the game names one, so the load
  /// refuses it.
  NoPositionalRequirementRow(id: Int)
  /// A quest a condition names has an objective slot whose QuestObjective row the table
  /// lacks. No slot of the game's quests does, so the load refuses it.
  NoQuestObjectiveRow(objective_id: Int)
}

/// The Prerequisite rows of the loaded tables by id, for `load`.
pub fn table_rows(
  tables tables: table_store.Tables,
) -> fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil) {
  fn(id) { prerequisite_table.get(tables:, id:) |> result.replace_error(Nil) }
}

/// The PositionalRequirement rows of the loaded tables by id, for `load`.
pub fn table_arcs(
  tables tables: table_store.Tables,
) -> fn(Int) -> Result(positional_requirement.PositionalRequirement, Nil) {
  fn(arc_id) {
    positional_requirement.get(tables:, id: id.PositionalRequirementId(arc_id))
  }
}

/// The quests of the loaded tables by Quest2 id, for `load`.
pub fn table_quests(
  tables tables: table_store.Tables,
) -> fn(Int) -> Result(Quest, QuestRowError) {
  fn(quest_id) { quest_log.quest_of(tables:, id: quest_id) }
}

/// The prerequisite with this id as the client keeps it (`0x1404a5190`), from the
/// tables `rows`, `arcs` and `quests` read, each nested row loaded in place, each type
/// 108 condition holding the arc of its PositionalRequirement row and each quest
/// condition its quest.
pub fn load(
  id id: PrerequisiteId,
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
) -> Result(Prerequisite, LoadError) {
  use row <- result.try(
    rows(id) |> result.replace_error(NoPrerequisiteRow(id:)),
  )
  loaded(row:, rows:, arcs:, quests:, above: [id])
}

/// The PrerequisiteType of a nested prerequisite (`Prerequisite.prerequisiteTypeId.11`),
/// whose row `load` follows.
pub const nested_type = 11

/// The row as a prerequisite; `above` holds the ids of the rows it is nested in,
/// nearest first.
fn loaded(
  row row: prerequisite_table.Prerequisite,
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
  above above: List(PrerequisiteId),
) -> Result(Prerequisite, LoadError) {
  use conditions <- result.map(
    list.try_map(kept_conditions(row:), fn(condition) {
      use <- bool.lazy_guard(when: condition.0 == nested_type, return: fn() {
        nested_loaded(
          comparison: comparison_of(condition.1),
          id: PrerequisiteId(condition.2),
          rows:,
          arcs:,
          quests:,
          above:,
        )
      })
      condition_read(
        type_id: condition.0,
        comparison: condition.1,
        object_id: condition.2,
        value: condition.3,
        arcs:,
        quests:,
      )
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
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
  above above: List(PrerequisiteId),
) -> Result(Condition, LoadError) {
  use <- bool.guard(
    when: list.contains(above, id),
    return: Error(PrerequisiteCycle(path: list.reverse([id, ..above]))),
  )
  case rows(id) {
    Error(Nil) -> Ok(Nested(comparison:, id: id.value, row: None))
    Ok(row) ->
      loaded(row:, rows:, arcs:, quests:, above: [id, ..above])
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

/// A condition decoded: type 108 reads its arc through `arcs`, the quest types read
/// their quest through `quests`, every other type is `condition_of`.
fn condition_read(
  type_id type_id: Int,
  comparison comparison: Int,
  object_id object_id: Int,
  value value: Int,
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
) -> Result(Condition, LoadError) {
  case type_id {
    108 ->
      arc_of(object_id:, arcs:)
      |> result.map(fn(arc) {
        InArc(comparison: comparison_of(comparison), arc:)
      })
    6 | 68 | 43 | 22 | 23 | 33 | 34 | 35 | 36 ->
      quest_named(object_id:, quests:)
      |> result.map(fn(quest) {
        quest_condition(type_id:, comparison:, value:, quest:)
      })
    _ -> Ok(condition_of(type_id:, comparison:, object_id:, value:))
  }
}

/// The quest a condition's objectId names: none when the table has no Quest2 row for
/// it, which the client reads as an unknown quest (`0x1405a8a40`).
fn quest_named(
  object_id object_id: Int,
  quests quests: fn(Int) -> Result(Quest, QuestRowError),
) -> Result(Option(Quest), LoadError) {
  case quests(object_id) {
    Ok(quest) -> Ok(Some(quest))
    Error(quest_log.NoQuestRow) -> Ok(None)
    Error(quest_log.NoObjectiveRow(objective_id:)) ->
      Error(NoQuestObjectiveRow(objective_id:))
  }
}

/// A quest condition (types 6, 68, 43, 22, 23, 33, 34, 35 and 36) of this quest.
fn quest_condition(
  type_id type_id: Int,
  comparison comparison: Int,
  value value: Int,
  quest quest: Option(Quest),
) -> Condition {
  case type_id {
    6 -> QuestState(comparison: comparison_of(comparison), value:, quest:)
    68 ->
      ObjectiveDone(
        comparison: comparison_of(comparison),
        index: unsigned(value),
        quest:,
      )
    43 ->
      ObjectiveOpen(
        comparison: comparison_of(comparison),
        index: unsigned(value),
        quest:,
      )
    _ ->
      ObjectiveProgress(
        prerequisite_type: type_id,
        relation: relation_of(code: comparison),
        index: progress_index(type_id:),
        value:,
        quest:,
      )
  }
}

/// The objective that type 22, 23, 33, 34, 35 or 36 reads (the client's cases 0x16,
/// 0x17 and 0x21 to 0x24 of `0x1404a2100` pass the index 0 to 5 to `0x14049f4d0`).
fn progress_index(type_id type_id: Int) -> Int {
  case type_id {
    22 -> 0
    23 -> 1
    33 -> 2
    34 -> 3
    35 -> 4
    _ -> 5
  }
}

/// The arc a type 108 condition's objectId names: none for 0, which the client reads as no
/// arc (`0x14049d96b`), else the row's.
fn arc_of(
  object_id object_id: Int,
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
) -> Result(Option(Arc), LoadError) {
  case object_id {
    0 -> Ok(None)
    arc_id ->
      case arcs(arc_id) {
        Ok(row) ->
          Ok(
            Some(Arc(
              center: row.angle_center,
              range: row.angle_range,
              turns_with_second: int.bitwise_and(row.flags, 1) == 1,
            )),
          )
        Error(Nil) -> Error(NoPositionalRequirementRow(id: arc_id))
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
    4 -> CurrentFaction(comparison: comparison_of(comparison), value:)
    250 -> BaseFaction(comparison: comparison_of(comparison), value:)
    1 -> UnitLevel(relation: relation_of(code: comparison), value:)
    2 -> PlayerRace(comparison: comparison_of(comparison), value:)
    3 -> UnitClass(comparison: comparison_of(comparison), value:)
    26 -> InZone(comparison: comparison_of(comparison), value:)
    39 -> IsPlayer(comparison: comparison_of(comparison))
    52 -> PlayerPath(comparison: comparison_of(comparison), value:)
    10 -> Gender(comparison: comparison_of(comparison), value:)
    109 -> InWorld(comparison: comparison_of(comparison), world_id: object_id)
    125 -> ChallengeInCooldown(comparison: comparison_of(comparison))
    243 -> NeverMet
    94 -> TargetCounted(comparison: comparison_of(comparison))
    6 | 68 | 43 | 22 | 23 | 33 | 34 | 35 | 36 ->
      quest_condition(type_id:, comparison:, value:, quest: None)
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
  // Type 108 is decoded by `condition_read`, which needs its arc row.
  use <- bool.guard(when: type_id == 108, return: True)
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
    | CurrentFaction(..)
    | BaseFaction(..)
    | UnitLevel(..)
    | PlayerRace(..)
    | UnitClass(..)
    | InZone(..)
    | IsPlayer(..)
    | PlayerPath(..)
    | Gender(..)
    | InWorld(..)
    | QuestState(..)
    | ObjectiveDone(..)
    | ObjectiveOpen(..)
    | TargetCounted(..)
    | ObjectiveProgress(..)
    | ChallengeInCooldown(..)
    | NeverMet
    | InArc(..)
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
      | CurrentFaction(..)
      | BaseFaction(..)
      | UnitLevel(..)
      | PlayerRace(..)
      | UnitClass(..)
      | InZone(..)
      | IsPlayer(..)
      | PlayerPath(..)
      | Gender(..)
      | InWorld(..)
      | QuestState(..)
      | ObjectiveDone(..)
      | ObjectiveOpen(..)
      | TargetCounted(..)
      | ObjectiveProgress(..)
      | ChallengeInCooldown(..)
      | NeverMet
      | InArc(..)
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
/// unit, which a subject known by its place alone does not hold. A nested row decides by
/// its own conditions, and a resource slot, a stealth and a difficulty that the subject
/// holds none of are not read by their own check.
fn reads_held_state(condition condition: Condition) -> Option(Int) {
  case condition {
    TargetOfLiveCast(..) -> Some(15)
    UnderCastBy(..) -> Some(50)
    StackCount(..) -> Some(59)
    InCombat(..) -> Some(28)
    Roll(..) -> Some(37)
    VitalPercent(..) -> Some(71)
    VitalCurrent(..) -> Some(73)
    UnderGroup(..) -> Some(129)
    UnitLevel(..) -> Some(1)
    UnitClass(..) -> Some(3)
    IsPlayer(..) -> Some(39)
    Nested(..)
    | ResourceSlot(..)
    | Stealthed(..)
    | Difficulty(..)
    | CurrentFaction(..)
    | BaseFaction(..)
    | PlayerRace(..)
    | InZone(..)
    | PlayerPath(..)
    | Gender(..)
    | InWorld(..)
    | QuestState(..)
    | ObjectiveDone(..)
    | ObjectiveOpen(..)
    | TargetCounted(..)
    | ObjectiveProgress(..)
    | ChallengeInCooldown(..)
    | NeverMet
    | InArc(..)
    | NoCase
    | Unread(..) -> None
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
    CurrentFaction(comparison:, value:) -> #(
      rolls,
      faction_verdict(
        comparison:,
        value:,
        subject:,
        prerequisite_type: 4,
        read: fn(factions) { factions.current },
      ),
    )
    BaseFaction(comparison:, value:) -> #(
      rolls,
      faction_verdict(
        comparison:,
        value:,
        subject:,
        prerequisite_type: 250,
        read: fn(factions) { factions.base },
      ),
    )
    UnitLevel(relation:, value:) -> #(rolls, case subject.player {
      Some(player) ->
        verdict_of(compare(relation:, measured: player.level, value:))
      None -> NotRead(prerequisite_type: 1)
    })
    PlayerRace(comparison:, value:) -> #(rolls, case subject.player {
      Some(player) ->
        equality_verdict(
          comparison:,
          equal: compare(relation: Equal, measured: player.race_id, value:),
        )
      None -> NotRead(prerequisite_type: 2)
    })
    UnitClass(comparison:, value:) -> #(rolls, case subject.player {
      Some(player) ->
        equality_verdict(
          comparison:,
          equal: compare(relation: Equal, measured: player.class_id, value:),
        )
      None -> NotRead(prerequisite_type: 3)
    })
    InZone(comparison:, value:) -> #(rolls, case subject.player {
      Some(player) ->
        equality_verdict(comparison:, equal: list.contains(player.zones, value))
      None -> NotRead(prerequisite_type: 26)
    })
    IsPlayer(comparison:) -> #(rolls, case subject.player {
      // The first unit of a subject that holds a player is that player.
      Some(_) -> equality_verdict(comparison:, equal: True)
      None -> NotRead(prerequisite_type: 39)
    })
    PlayerPath(comparison:, value:) -> #(rolls, case subject.player {
      Some(player) ->
        equality_verdict(
          comparison:,
          equal: compare(relation: Equal, measured: player.path, value:),
        )
      None -> NotRead(prerequisite_type: 52)
    })
    Gender(comparison:, value:) -> #(rolls, case subject.player {
      Some(player) ->
        equality_verdict(
          comparison:,
          equal: compare(relation: Equal, measured: player.gender, value:),
        )
      None -> NotRead(prerequisite_type: 10)
    })
    InWorld(comparison:, world_id:) -> #(rolls, case subject.player {
      Some(player) ->
        equality_verdict(
          comparison:,
          equal: compare(
            relation: Equal,
            measured: player.world_id,
            value: world_id,
          ),
        )
      None -> NotRead(prerequisite_type: 109)
    })
    QuestState(comparison:, value:, quest:) -> #(
      rolls,
      with_quest_log(subject:, prerequisite_type: 6, decide: fn(log) {
        let state = case quest {
          Some(quest) -> quest_log.state(log:, quest:)
          None -> 0
        }
        // The client counts the states 4 to 7 as 0 (Unknown).
        let counted = case state > 3 {
          True -> 0
          False -> state
        }
        case comparison {
          Found -> verdict_of(counted == unsigned(value))
          NotFound -> verdict_of(counted != unsigned(value))
          OtherComparison(..) -> Fails
        }
      }),
    )
    ObjectiveDone(comparison:, index:, quest:) -> #(
      rolls,
      with_quest_log(subject:, prerequisite_type: 68, decide: fn(log) {
        let done = case quest {
          Some(quest) -> quest_log.objective_done(log:, quest:, index:)
          None -> False
        }
        asked(comparison:, holds: done)
      }),
    )
    ObjectiveOpen(comparison:, index:, quest:) -> #(
      rolls,
      with_quest_log(subject:, prerequisite_type: 43, decide: fn(log) {
        let open = case quest {
          Some(quest) -> quest_log.objective_open(log:, quest:, index:)
          None -> False
        }
        asked(comparison:, holds: open)
      }),
    )
    // The gap: the server holds no counted-targets mask yet, so no target is counted,
    // which passes comparison 2 only. The mask and what sets it belong to the issue
    // "Checklist objectives progress (objective types 14, 18, 10, 27 and 28)" (#599).
    TargetCounted(comparison:) -> #(rolls, case comparison {
      Found -> Fails
      NotFound -> Passes
      OtherComparison(..) -> Fails
    })
    ObjectiveProgress(prerequisite_type:, relation:, index:, value:, quest:) -> #(
      rolls,
      with_quest_log(subject:, prerequisite_type:, decide: fn(log) {
        let progress = case quest {
          Some(quest) -> quest_log.objective_progress(log:, quest:, index:)
          None -> 0
        }
        verdict_of(compare(relation:, measured: progress, value:))
      }),
    )
    // No 0xc7 is ever sent, so the client's challenge list is empty and no challenge
    // is in cooldown (`opcode.0xc7`, `0x140c65948`). Gap: the challenge records wait
    // for "Public events and challenges work on the real client" (issue 52).
    ChallengeInCooldown(comparison:) -> #(
      rolls,
      asked(comparison:, holds: False),
    )
    NeverMet -> #(rolls, Fails)
    InArc(comparison:, arc:) -> #(
      rolls,
      arc_verdict(comparison:, arc:, positions: subject.positions),
    )
    NoCase -> #(rolls, Fails)
    Unread(prerequisite_type:) -> #(rolls, NotRead(prerequisite_type:))
  }
}

/// What a quest condition gives from the subject's quest log: `NotRead` of its type when
/// the subject holds none (a creature's side).
fn with_quest_log(
  subject subject: Subject,
  prerequisite_type prerequisite_type: Int,
  decide decide: fn(QuestLog) -> Verdict,
) -> Verdict {
  case subject.quests {
    Some(log) -> decide(log)
    None -> NotRead(prerequisite_type:)
  }
}

/// A condition that asks whether something holds: comparison 1 passes when it does, 2
/// when it does not, any other fails.
fn asked(comparison comparison: Comparison, holds holds: Bool) -> Verdict {
  case comparison {
    Found -> verdict_of(holds)
    NotFound -> verdict_of(!holds)
    OtherComparison(..) -> Fails
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
    wrapped(angle: float32.sum(
      left: float32.product(
        left: float32.difference(left: center, right: half),
        right: radians_per_degree,
      ),
      right: yaw,
    ))
  let end =
    wrapped(angle: float32.sum(
      left: float32.product(
        left: float32.sum(left: half, right: center),
        right: radians_per_degree,
      ),
      right: yaw,
    ))
  let direction =
    float32.rounded(maths.atan2(
      float.negate(float32.difference(
        left: float32.rounded(other.at.x),
        right: float32.rounded(turning.at.x),
      )),
      float.negate(float32.difference(
        left: float32.rounded(other.at.z),
        right: float32.rounded(turning.at.z),
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
      float32.sum(
        left: remainder(
          float32.difference(left: angle, right: half_turn),
          full_turn,
        ),
        right: half_turn,
      )
    False ->
      float32.difference(
        left: remainder(float32.sum(left: angle, right: half_turn), full_turn),
        right: half_turn,
      )
  }
}

/// C's `fmod`: the remainder of x over y with the sign of x. No Gleam library has it:
/// `float.modulo` is the floored modulo, which differs for a negative x, and the maths
/// package's modulo is Euclidean.
@external(erlang, "math", "fmod")
fn remainder(x: Float, y: Float) -> Float

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

/// The verdict of a faction condition (type 4 on the current faction, type 250 on the
/// base faction; `read` picks it): comparison 1 passes when the faction equals the value,
/// 2 when it does not, any other fails, and a subject that holds no factions is
/// `NotRead`. The faction and the value are compared as 32-bit numbers
/// (`0x14049c620`, `0x14049c6a0`).
fn faction_verdict(
  comparison comparison: Comparison,
  value value: Int,
  subject subject: Subject,
  prerequisite_type prerequisite_type: Int,
  read read: fn(Factions) -> Int,
) -> Verdict {
  case subject.factions {
    None -> NotRead(prerequisite_type:)
    Some(factions) -> {
      equality_verdict(
        comparison:,
        equal: compare(relation: Equal, measured: read(factions), value:),
      )
    }
  }
}

/// The verdict of a condition that asks whether two numbers are equal: comparison 1
/// passes when they are, 2 when they are not, any other fails.
fn equality_verdict(
  comparison comparison: Comparison,
  equal equal: Bool,
) -> Verdict {
  case comparison {
    Found -> verdict_of(equal)
    NotFound -> verdict_of(!equal)
    OtherComparison(..) -> Fails
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
