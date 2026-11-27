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
//// - **Type 60** is type 59's count over the casts whose caster is the check's second unit
////   alone; with no second unit comparison 2 passes and every other fails, and a second
////   unit 0 counts 0 (`Prerequisite.prerequisiteTypeId.60`, `0x14046a110`).
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
//// - **Type 40** compares the unit's health as a percentage of its maximum health with the
////   value, as type 71 does for the Health vital; the objectId is not read
////   (`Prerequisite.prerequisiteTypeId.40`, `0x1404a4d90`). A creature holds no health the
////   caster's check can read, so a row that strikes creatures behind it is refused, and a heal
////   row of a friendly area is read for the players the caster's picture holds the health of
////   (`with_health`, `PlaceAndHealth`).
//// - **Type 71** compares the vital the objectId names, as a percentage of its
////   maximum, with the value, in 32-bit floats; a zero maximum with nothing held
////   is not a number, which counts as equal and fails every other comparison, and
////   a zero maximum with something held is infinite, which passes comparisons 2, 3
////   and 4 only; a maximum below zero (Interrupt Armor's -1.0) gives a negative
////   percent (`Prerequisite.prerequisiteTypeId.71`, `0x1404a4e30`).
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
////   `.250`, `0x14049c620`, `0x14049c6a0`). A player's side and a creature's side
////   (`of_creature`) hold factions, so a subject with none gives `NotRead`.
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
////   and the value are not read (`Prerequisite.prerequisiteTypeId.39`). The first
////   unit is read from the subject's `first_unit`: a player is `TheChecker` or
////   `OtherPlayer`, a creature `NonPlayer`, and a unit the check cannot name
////   (`UnknownUnit`) gives `NotRead`.
//// - **A subject known by its place alone** (`Seen`, `of_struck`) holds the player's facts but
////   not the first unit's, so types 1 and 3, which read that unit, give `NotRead` for
////   it; a subject that holds no player gives `NotRead` for all of these types. A
////   creature's own subject (`of_creature`) holds the whole unit: its level (type 1),
////   its class, which is always 23 (type 3: no Class row has that id, so comparison 1
////   fails for every Class id and comparison 2 passes), its factions (4 and 250), its
////   combat state (28), its health, shield, breath and Interrupt Armor (71 and 73), its
////   difficulty (179) and its Creature2 row (38).
//// - **Type 243** always fails: the client's check reads nothing from the unit
////   (`Prerequisite.prerequisiteTypeId.243`, `0x140001ba0`).
//// - **Type 47** never passes on the client, whatever the comparison (its slot is the same
////   `0x140001ba0` as type 243's), so a cast, an effect or a gossip entry behind it fails
////   (`Prerequisite.prerequisiteTypeId.47`). The visibility check leaves it `NotRead`
////   instead (`check_for_visibility`): the creature stays shown. The 1,788 conditions
////   of the type name server-only ids the client never reads, so which creatures it hides
////   is open (Creature2 30305 and 34586 are the spawns of the world database that
////   carry it).
//// - **Type 38** compares the first unit's Creature2 id, 0 for a player, with the value:
////   comparison 1 equal, 2 different, any other fails, and its objectId is not read
////   (`Prerequisite.prerequisiteTypeId.38`, `0x14049ecc0`). A first unit the check cannot
////   name (`UnknownUnit`) gives `NotRead`.
//// - **Type 214** fails when the first unit is a creature; else, by comparison 1, the
////   checker's ability book holds the Spell4Base the objectId names and by comparison 2 it
////   does not, any other fails (`Prerequisite.prerequisiteTypeId.214`, `0x14049d680`,
////   `0x1403bb170`). A subject with no checker gives `NotRead`.
//// - **Types 13, 14 and 246** pass, by comparison 1, when the checker holds the Item2 the
////   value names in the inventory locations of a mask (1, 0x303 and 0x707), and by comparison
////   2 when it does not; any other fails (`Prerequisite.prerequisiteTypeId.13`, `.14`,
////   `.246`, `0x1403ac590`). Bit n of the mask selects the client's location n, whose list
////   the constructor `0x1403faa60` tags with that location; the store saves items only in
////   locations 0, 1 and 2, so bits 5, 8, 9 and 10 read as holding nothing. The
////   checker's satchel is not held, so an item there reads as not held.
//// - **Type 143** compares the checker's world difficulty with the value: comparison 1
////   equal, 2 different, any other fails (`Prerequisite.prerequisiteTypeId.143`,
////   `0x14049ef70`).
//// - **Type 118** compares the status of the public event objective the objectId names with
////   the value: comparison 1 equal, 2 different, any other fails. The server holds no
////   public event, so every objective has status 0 (inactive)
////   (`Prerequisite.prerequisiteTypeId.118`, `0x1404a0590`).
//// - **Type 130** passes, by comparison 1, when the first unit carries a cast of a spell
////   in the spell group the objectId names whose caster is the check's second unit, and by
////   comparison 2 when it does not; any other fails, group 0 matches no spell and the value
////   is not read. With no second unit, comparison 2 passes and any other fails
////   (`Prerequisite.prerequisiteTypeId.130`, `0x140469a70`).
//// - **Type 179** compares the unit's difficulty with the condition's objectId, not
////   its value, by comparisons 1 to 6; only a creature's side holds a difficulty,
////   so a subject with none gives `NotRead` (`0x14049eeb0`, `of_difficulty`).
//// - **Type 6** compares the state of the quest the objectId names, in the quest log of
////   the player whose client runs the check, with the value: the state the client
////   derives (`quest_view.state`, `0x1405fbc40`), states 4 to 7 counted as 0, comparison
////   1 equal and 2 not equal, any other fails. **Type 68** passes, by comparison 1, when
////   objective `value` of that quest is done and by comparison 2 when it is not
////   (`quest_view.objective_done`, `0x1405510d0`). **Type 43** passes, by comparison 1,
////   when that objective is open: the quest is in the active list, the objective is not
////   done and it is reachable, and by comparison 2 when it is not
////   (`quest_view.objective_open`, `0x14049f3d0`). **Types 22, 23, 33, 34, 35 and 36**
////   compare the progress of objective 0, 1, 2, 3, 4 and 5 of that quest with the value
////   by comparisons 1 to 6, progress on the left (`quest_view.objective_progress`,
////   `0x14049f4d0`). A quest with no Quest2 row is the client's unknown quest: state 0,
////   not done, not open, progress 0. Each condition holds its quest, read once at the
////   load, so a check needs no table; a QuestObjective row a quest names and the table
////   lacks fails the load. A subject with no quest log gives `NotRead`
////   (`Prerequisite.prerequisiteTypeId.6`, `.68`, `.43`, `.22`).
//// - **Types 125, 69 and 74** read a flag of the player's challenge objectId: in
////   cooldown (125), active (69), unlocked (74, a guess at the flag's meaning: the
////   client's name for it is not read). Comparison 1 passes when the flag is
////   set, comparison 2 when it is clear, any other fails: a challenge the server has sent
////   no record for has every flag clear, and the server sends none, so comparison 2
////   always passes and comparison 1 never; the objectId and the value are not read
////   (`Prerequisite.prerequisiteTypeId.125`, `.69`, `.74`, `0x14049fac0`,
////   `0x14049f990`, `0x14049fa80`).
//// - **Type 288** passes, by comparison 1, when the client's own set of owned titles holds
////   the title the objectId names, and by comparison 2 when it does not, for a first unit
////   that is a player; any other comparison fails, and so does a creature, and the value is
////   not read (`Prerequisite.prerequisiteTypeId.288`, `0x1404a1830`). The set is the
////   client's single one, filled only by messages 0x018A and 0x018B (`opcode.0x18a`,
////   `opcode.0x18b`); the server sends neither and owns no title, so it is empty and the
////   condition reads it so.
//// - **Type 94** (the target is counted by a checklist objective) reads the check's
////   creature, the first unit unless it is a player and then the second, and the objective
////   `value` of the quest `objectId` (`Prerequisite.prerequisiteTypeId.94`,
////   `0x14049f5b0`). With no creature, or a quest the table lacks, comparison 2 passes and
////   any other fails. Else the creature is counted when the quest is in the log and the
////   objective's mask holds the creature's checklist index (`0x140611680`), which
////   comparison 1 passes and comparison 2 fails; a quest not in the log counts nothing.
////   Only a struck unit carries a creature (`counting`).
//// - **A vital the server does not hold** is `NotRead`, as is a type the client
////   decides and the server does not read. A player's subject holds its Focus as vital 15,
////   0 of 0 for a class with none, and a creature's holds it as 0 of 0, since its 0x262
////   sends no stat 1 (`UnitStat.1.Focus`).
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
////   `positions`. A struck unit the caster only sees is known by its place alone
////   (`of_struck`), so every condition that reads what else it holds is `NotRead`; a struck
////   creature that checks its own gate holds its own facts and the caster as its second
////   unit (`of_creature`), and only types 15, 59 and 129, which read every caster's casts
////   on it, stay unread (`struck_unread_types`).

import genesis_prime/game/area.{type Pose}
import genesis_prime/game/lasting
import genesis_prime/game/top_zone
import genesis_prime/gap
import genesis_prime/message/float32
import genesis_prime/random
import genesis_prime/shared/quest_row.{type Quest, type QuestRowError}
import genesis_prime/shared/quest_view.{type QuestView}
import genesis_prime/store.{type Character, type HeldItem}
import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4BaseId, type Spell4Id, PrerequisiteId,
  Spell4BaseId, Spell4Id,
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
import gleam/string
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
  /// Type 60: the stack count of the Spell4 on the unit, over the casts of the check's
  /// second unit alone, against the value (`Prerequisite.prerequisiteTypeId.60`).
  StackCountByCaster(relation: Relation, spell4_id: Spell4Id, value: Int)
  /// Type 28: whether the unit is in combat
  /// (`Prerequisite.prerequisiteTypeId.28`).
  InCombat(comparison: Comparison)
  /// Type 37: a roll from 1 to 100 against the value
  /// (`Prerequisite.prerequisiteTypeId.37`).
  Roll(relation: Relation, value: Int)
  /// Type 40: the unit's health as a percentage of its maximum health against the value
  /// (`Prerequisite.prerequisiteTypeId.40`, `0x1404a4d90`): type 71's reading of the Health
  /// vital, which the unit's two health slots give.
  HealthPercent(relation: Relation, value: Int)
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
  /// Type 94: whether the check's creature is counted by the quest's checklist objective
  /// `index` (`Prerequisite.prerequisiteTypeId.94`).
  TargetCounted(comparison: Comparison, index: Int, quest: Option(Quest))
  /// Types 22, 23, 33, 34, 35 and 36: the progress of the quest's objective `index`
  /// (0 to 5) against the value (`Prerequisite.prerequisiteTypeId.22`).
  ObjectiveProgress(
    prerequisite_type: Int,
    relation: Relation,
    index: Int,
    value: Int,
    quest: Option(Quest),
  )
  /// Types 125, 69 and 74: a flag of the player's challenge record (in cooldown,
  /// active, unlocked: a guess for 74); the server holds no challenge record, so every flag is clear
  /// (`Prerequisite.prerequisiteTypeId.125`, `.69`, `.74`).
  ChallengeFlag(comparison: Comparison)
  /// Type 288: whether the client's own set of owned titles holds a title
  /// (`Prerequisite.prerequisiteTypeId.288`, `0x1404a1830`). The set is empty, as the server
  /// sends the client no title.
  TitleOwned(comparison: Comparison)
  /// Type 243: never met (`Prerequisite.prerequisiteTypeId.243`, `0x140001ba0`).
  NeverMet
  /// Type 47: never met by a cast, an effect or a gossip entry, as type 243, but
  /// the visibility check does not decide it (`Prerequisite.prerequisiteTypeId.47`).
  ServerGated
  /// Type 38: the first unit's Creature2 id against the value
  /// (`Prerequisite.prerequisiteTypeId.38`, `0x14049ecc0`).
  IsCreature(comparison: Comparison, value: Int)
  /// Type 214: whether the checker's ability book holds the Spell4Base
  /// (`Prerequisite.prerequisiteTypeId.214`, `0x14049d680`).
  SpellKnown(comparison: Comparison, spell4_base_id: Int)
  /// Types 13, 14 and 246: whether the checker holds the Item2 in the inventory locations
  /// of the mask, bit n for the client's location n (`Prerequisite.prerequisiteTypeId.13`,
  /// `.14`, `.246`, `0x1403ac590`, `0x1403faa60`). The store saves items only in
  /// locations 0, 1 and 2, so the other bits read as holding nothing.
  ItemHeld(
    prerequisite_type: Int,
    comparison: Comparison,
    item2_id: Int,
    locations: Int,
  )
  /// Type 143: the checker's world difficulty against the value
  /// (`Prerequisite.prerequisiteTypeId.143`, `0x14049ef70`).
  WorldDifficulty(comparison: Comparison, value: Int)
  /// Type 118: the status of a public event objective against the value
  /// (`Prerequisite.prerequisiteTypeId.118`, `0x1404a0590`). The objective is kept for
  /// the day the server holds public events.
  ObjectiveStatus(comparison: Comparison, objective: Int, value: Int)
  /// Type 130: whether the first unit carries a cast by the second unit whose spell is
  /// in the spell group (`Prerequisite.prerequisiteTypeId.130`, `0x140469a70`).
  CarriesCasterGroup(comparison: Comparison, group: Int)
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
pub type Comparison {
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

/// The player a character is at a place and level: its own row's race, class, path
/// and gender, the World and zone it stands in, and the zone's parents above it in
/// the WorldZone table, which is the walk the client's zone check makes
/// (0x1403c92e0, `Prerequisite.prerequisiteTypeId.26`). A zone with no row has no
/// parent to walk to, so it is the one zone the player is in.
pub fn player_of(
  tables tables: table_store.Tables,
  character character: Character,
  world_id world_id: Int,
  zone zone: Int,
  level level: Int,
) -> Player {
  Player(
    race_id: character.race_id.value,
    class_id: character.class_id.value,
    level:,
    path: character.path,
    gender: character.gender,
    world_id:,
    zones: top_zone.chain_or_zone(tables:, world_zone_id: zone),
  )
}

/// What the player whose client runs the check holds of its own, apart from the check's
/// units: its items as the store saved them, its ability book (the abilities in bar
/// order, then its innate) and the world difficulty the client was told.
pub type Checker {
  Checker(
    items: List(HeldItem),
    book: List(Spell4BaseId),
    world_difficulty: Int,
  )
}

/// The Vital id of Health (Vital.tbl id 1), the vital type 40 reads from a subject's `vitals`
/// (`Prerequisite.prerequisiteTypeId.71`, `0x1404a4d90`).
pub const health_vital = 1

/// What the check's first unit is, for the types that read its identity.
pub type FirstUnit {
  /// The player whose client runs the check.
  TheChecker
  /// Another player.
  OtherPlayer
  /// A creature of this Creature2 row.
  NonPlayer(creature2_id: Int)
  /// A unit the check cannot name: types 38 and 214 are `NotRead`.
  UnknownUnit
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
    /// (genesis_prime/game/cast/state `stealthed`).
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
    quests: Option(QuestView),
    /// The checklist index of the check's creature (`0x262`), which only a struck unit
    /// holds: `None` when the check has no creature, as type 94 reads it
    /// (`Prerequisite.prerequisiteTypeId.94`).
    creature_index: Option(Int),
    /// What the check knows of the subject.
    seen: Seen,
    /// What the checking player holds of its own: `None` when the check runs before
    /// the player's items and abilities are known, so types 13, 14, 246, 143 and 214 are
    /// not read.
    checker: Option(Checker),
    /// Who the check's first unit is, for types 38 and 214.
    first_unit: FirstUnit,
  )
}

/// The subject of a player in the caster's sight with the health and the maximum health the
/// caster's picture holds of it, which type 40 reads.
pub fn with_health(subject subject: Subject, health health: Vital) -> Subject {
  Subject(
    ..subject,
    vitals: dict.insert(subject.vitals, health_vital, health),
    seen: PlaceAndHealth,
  )
}

/// The subject with a creature in the check, whose checklist index (the one its 0x262
/// carried) type 94 reads.
pub fn counting(
  subject subject: Subject,
  checklist_index index: Int,
) -> Subject {
  Subject(..subject, creature_index: Some(index))
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
  /// The place of the subject and its health, which a player's copy in the caster's picture
  /// holds: type 40 is decided, and every other condition that reads the unit's own state is
  /// not read, as for `PlaceOnly`.
  PlaceAndHealth
}

/// The subject of a unit the caster struck, for a target-side check (a Proxy's target apply
/// prerequisite): the struck unit first with the pose its place and facing give in the
/// caster's picture, `None` when the picture no longer shows it, and the caster second;
/// the quest log and the player's facts are the caster's, whose client runs the check.
/// The connection holds none of a creature's casts, combat state or vitals, so the subject
/// holds none of them either: a condition that reads what else it holds is `NotRead`
/// (`PlaceOnly`), where an empty `under` would read as "under no cast" and pass a
/// condition that asks for the absence of one. The exception is type 130, which reads
/// the second unit's casts alone, as type 50 does: `under` holds the caster's casts on the struck unit and
/// the caster is the second unit. `unit` is who the struck unit is, and `checker` is what
/// the caster holds of its own.
pub fn of_struck(
  first first: Option(Pose),
  second second: Pose,
  player player: Player,
  quests quests: QuestView,
  unit unit: FirstUnit,
  caster_unit caster_unit: Int,
  under under: List(lasting.Held),
  checker checker: Checker,
) -> Subject {
  Subject(
    under:,
    second_unit: Some(caster_unit),
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
    creature_index: None,
    seen: PlaceOnly,
    checker: Some(checker),
    first_unit: unit,
  )
}

/// The subject of a creature a player's press named as the target of its spell, for the
/// spell's TargetCast: the creature first, with what the player's own casts hold on it
/// (`under`), whether the caster's picture shows it in combat, and the pose its place and
/// facing give, and the caster second, with its quest log. The connection holds no life,
/// vital, faction or flag of a creature, so the subject holds none of them either: a
/// condition that reads what else it holds is `NotRead`. Another player's casts on the
/// creature are not in `under`. `creature_id` is the Creature2 row of the pressed creature, which type 38
/// reads, and `checker` is what the caster holds of its own.
pub fn of_target(
  under under: List(lasting.Held),
  caster_unit caster_unit: Int,
  in_combat in_combat: Bool,
  target target: Pose,
  caster caster: Pose,
  quests quests: QuestView,
  creature_id creature_id: Int,
  checker checker: Checker,
) -> Subject {
  Subject(
    under:,
    second_unit: Some(caster_unit),
    in_combat:,
    vitals: dict.new(),
    difficulty: None,
    stealthed: None,
    resource_slots: None,
    rolls: [],
    positions: Placed(first: target, second: caster),
    factions: None,
    player: None,
    quests: Some(quests),
    creature_index: None,
    seen: WholeUnit,
    checker: Some(checker),
    first_unit: NonPlayer(creature2_id: creature_id),
  )
}

/// What a creature holds of its own and of the strike it checks a gate of (genesis_prime/game/strike_tell
/// `Gate`), for the subject `of_creature` makes.
pub type CreatureFacts {
  CreatureFacts(
    /// The creature as the client's player record reads it for types 1, 3 and 39: its level,
    /// and class 23, the class a creature has there.
    player: Player,
    /// Its two factions.
    factions: Factions,
    /// Whether it fights.
    in_combat: Bool,
    /// Its health, Vital 1: its health and its maximum health (property 7).
    health: Vital,
    /// Its shield capacity maximum (property 41). Its shield, Vital 3, is always 0: the server
    /// sends it no stat 20.
    shield_maximum: Float,
    /// Its Interrupt Armor, Vital 20: the current armor and its maximum (property 44, -1.0 for
    /// infinite armor, `Vital.20.unit`).
    armor: Vital,
    /// Its Creature2Difficulty, type 179.
    difficulty: Int,
    /// Its Creature2 row, type 38.
    creature_id: Int,
    /// What the strike's caster's casts hold on it.
    under: List(lasting.Held),
    /// The strike's caster, the check's second unit.
    caster_unit: Int,
    /// The creature's pose and the caster's, for type 108; the caster's is `None` when it
    /// is not held.
    creature: Pose,
    caster: Option(Pose),
  )
}

/// The class a creature's unit holds: the value every unit starts with, which no message
/// sets for a creature and no Class row has as its id, so a type 3 condition on a creature
/// fails with comparison 1 and passes with comparison 2
/// (`Prerequisite.prerequisiteTypeId.3.creature`).
pub const creature_class_id = 23

/// The breath maximum of every unit, GameFormula 55's dataint0 (`UnitBreathMax`): a creature's
/// 0x262 sends no stat 19, so its breath, Vital 2, starts at it
/// (`opcode.0x262.absent_stats`).
const breath_maximum = 100.0

/// The subject of a creature that checks a gate of a strike it was told: the creature first,
/// with `facts`, and the caster second. The creature's vitals are its health (1) and Interrupt
/// Armor (20) from `facts`, a shield (3) of 0 and a breath (2) at the breath maximum, which
/// are the values its unit holds when its 0x262 sends no stat 20 or 19
/// (`opcode.0x262.absent_stats`). The caster's own facts are not in it: a gate that reads
/// them is not a creature gate and stays on the caster's side
/// (genesis_prime/game/spell_plan `struck_gates_in_phase`).
pub fn of_creature(facts facts: CreatureFacts) -> Subject {
  Subject(
    under: facts.under,
    second_unit: Some(facts.caster_unit),
    in_combat: facts.in_combat,
    vitals: dict.from_list([
      #(1, facts.health),
      #(2, Vital(current: breath_maximum, maximum: breath_maximum)),
      #(3, Vital(current: 0.0, maximum: facts.shield_maximum)),
      #(15, Vital(current: 0.0, maximum: 0.0)),
      #(20, facts.armor),
    ]),
    difficulty: Some(facts.difficulty),
    stealthed: None,
    resource_slots: None,
    rolls: [],
    positions: case facts.caster {
      Some(caster) -> Placed(first: facts.creature, second: caster)
      None -> NotPlaced
    },
    factions: Some(facts.factions),
    player: Some(facts.player),
    quests: None,
    creature_index: None,
    seen: WholeUnit,
    checker: None,
    first_unit: NonPlayer(creature2_id: facts.creature_id),
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
    creature_index: None,
    seen: WholeUnit,
    checker: None,
    first_unit: UnknownUnit,
  )
}

/// A subject that is a player about to wear an item: its factions and the player's
/// facts, under no cast, out of combat, with no vital and no roll. The equip
/// check's prerequisites (genesis_prime/game/equip_requirement) are checked
/// against it. `checker` is what the wearer holds of its own.
pub fn of_wearer(
  factions factions: Factions,
  player player: Player,
  checker checker: Checker,
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
    creature_index: None,
    seen: WholeUnit,
    checker: Some(checker),
    first_unit: TheChecker,
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

/// A sentence that says which row the load could not read, for the log.
pub fn describe_load_error(error error: LoadError) -> String {
  case error {
    NoPrerequisiteRow(id:) ->
      "the table Prerequisite has no row " <> int.to_string(id.value)
    PrerequisiteCycle(path:) ->
      "Prerequisite rows nest each other: "
      <> string.join(
        list.map(path, fn(id) { int.to_string(id.value) }),
        with: " > ",
      )
    NoPositionalRequirementRow(id:) ->
      "the table PositionalRequirement has no row " <> int.to_string(id)
    NoQuestObjectiveRow(objective_id:) ->
      "the table QuestObjective has no row " <> int.to_string(objective_id)
  }
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
  fn(quest_id) { quest_row.quest_of(tables:, id: quest_id) }
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

/// The Spell4 ids of the live casts the row's kept conditions read (`live_cast_of`), whatever
/// the comparison.
pub fn live_cast_spells(
  row row: prerequisite_table.Prerequisite,
) -> List(Spell4Id) {
  list.filter_map(kept_conditions(row:), fn(condition) {
    live_cast_of(condition:) |> result.map(fn(cast) { cast.1 })
  })
}

/// The comparison and the Spell4 of a condition that reads a live cast: type 15, whether a live
/// cast of the Spell4 has the unit as a target, and type 50, whether a cast of it by the check's
/// second unit holds a node on the unit (`Prerequisite.prerequisiteTypeId.15` and `.50`). The
/// condition is one of `kept_conditions`: (type, comparison, objectId, value). Any other type
/// gives `Error(Nil)`.
pub fn live_cast_of(
  condition condition: #(Int, Int, Int, Int),
) -> Result(#(Comparison, Spell4Id), Nil) {
  let #(type_id, comparison, object_id, value) = condition
  case condition_of(type_id:, comparison:, object_id:, value:) {
    TargetOfLiveCast(comparison:, spell4_id:)
    | UnderCastBy(comparison:, spell4_id:) -> Ok(#(comparison, spell4_id))
    StackCount(..)
    | StackCountByCaster(..)
    | InCombat(..)
    | Roll(..)
    | HealthPercent(..)
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
    | ChallengeFlag(..)
    | TitleOwned(..)
    | NeverMet
    | ServerGated
    | IsCreature(..)
    | SpellKnown(..)
    | ItemHeld(..)
    | WorldDifficulty(..)
    | ObjectiveStatus(..)
    | CarriesCasterGroup(..)
    | InArc(..)
    | Unread(..)
    | NoCase -> Error(Nil)
  }
}

/// The EldanAugmentation ids the row's kept conditions of type 227 name: type 227 asks whether
/// the player holds the AMP in the active set (`Prerequisite.prerequisiteTypeId.227`). The
/// server does not evaluate the condition (`is_read` is false for it); this only reads which
/// AMPs the rows ask for.
pub fn amps_asked_for(row row: prerequisite_table.Prerequisite) -> List(Int) {
  list.filter_map(kept_conditions(row:), fn(condition) {
    let #(type_id, _comparison, object_id, _value) = condition
    case type_id {
      227 -> Ok(object_id)
      _ -> Error(Nil)
    }
  })
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
    6 | 68 | 43 | 94 | 22 | 23 | 33 | 34 | 35 | 36 ->
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
    Error(quest_row.NoQuestRow) -> Ok(None)
    Error(quest_row.NoObjectiveRow(objective_id:)) ->
      Error(NoQuestObjectiveRow(objective_id:))
  }
}

/// A quest condition (types 6, 68, 43, 94, 22, 23, 33, 34, 35 and 36) of this quest.
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
    94 ->
      TargetCounted(
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
    60 ->
      StackCountByCaster(
        relation: relation_of(code: comparison),
        spell4_id: Spell4Id(object_id),
        value:,
      )
    37 -> Roll(relation: relation_of(code: comparison), value:)
    40 -> HealthPercent(relation: relation_of(code: comparison), value:)
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
    125 | 69 | 74 -> ChallengeFlag(comparison: comparison_of(comparison))
    288 -> TitleOwned(comparison: comparison_of(comparison))
    243 -> NeverMet
    47 -> ServerGated
    38 -> IsCreature(comparison: comparison_of(comparison), value:)
    214 ->
      SpellKnown(
        comparison: comparison_of(comparison),
        spell4_base_id: object_id,
      )
    13 -> item_held(type_id:, comparison:, value:, locations: 0x1)
    14 -> item_held(type_id:, comparison:, value:, locations: 0x303)
    246 -> item_held(type_id:, comparison:, value:, locations: 0x707)
    143 -> WorldDifficulty(comparison: comparison_of(comparison), value:)
    118 ->
      ObjectiveStatus(
        comparison: comparison_of(comparison),
        objective: object_id,
        value:,
      )
    130 ->
      CarriesCasterGroup(
        comparison: comparison_of(comparison),
        group: object_id,
      )
    6 | 68 | 43 | 94 | 22 | 23 | 33 | 34 | 35 | 36 ->
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

/// A condition on an item held in the inventory locations of a mask: the value is the
/// Item2 id (`0x1403ac590`).
fn item_held(
  type_id type_id: Int,
  comparison comparison: Int,
  value value: Int,
  locations locations: Int,
) -> Condition {
  ItemHeld(
    prerequisite_type: type_id,
    comparison: comparison_of(comparison),
    item2_id: value,
    locations:,
  )
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
    | StackCountByCaster(..)
    | InCombat(..)
    | Roll(..)
    | HealthPercent(..)
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
    | ChallengeFlag(..)
    | TitleOwned(..)
    | NeverMet
    | ServerGated
    | IsCreature(..)
    | SpellKnown(..)
    | ItemHeld(..)
    | WorldDifficulty(..)
    | ObjectiveStatus(..)
    | CarriesCasterGroup(..)
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
      | StackCountByCaster(..)
      | InCombat(..)
      | HealthPercent(..)
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
      | ChallengeFlag(..)
      | TitleOwned(..)
      | NeverMet
      | ServerGated
      | IsCreature(..)
      | SpellKnown(..)
      | ItemHeld(..)
      | WorldDifficulty(..)
      | ObjectiveStatus(..)
      | CarriesCasterGroup(..)
      | InArc(..)
      | NoCase
      | Unread(..) -> 0
    }
  })
  |> int.sum
}

/// The objectives the prerequisite names as open, as (Quest2 id, objective index): its
/// type 43 conditions of comparison 1, and those of the rows its type 11 conditions of
/// comparison 1 nest (`Prerequisite.prerequisiteTypeId.43`, `.11`). A quest the tables
/// hold no row for names none.
pub fn objective_links(
  prerequisite prerequisite: Prerequisite,
) -> List(#(Int, Int)) {
  list.flat_map(prerequisite.conditions, fn(condition) {
    case condition {
      ObjectiveOpen(comparison: Found, index:, quest: Some(quest)) -> [
        #(quest.id, index),
      ]
      Nested(comparison: Found, row: Some(nested), ..) ->
        objective_links(prerequisite: nested)
      Nested(..)
      | ObjectiveOpen(..)
      | TargetOfLiveCast(..)
      | UnderCastBy(..)
      | StackCount(..)
      | StackCountByCaster(..)
      | InCombat(..)
      | Roll(..)
      | HealthPercent(..)
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
      | TargetCounted(..)
      | ObjectiveProgress(..)
      | NeverMet
      | ServerGated
      | IsCreature(..)
      | SpellKnown(..)
      | ItemHeld(..)
      | WorldDifficulty(..)
      | ObjectiveStatus(..)
      | CarriesCasterGroup(..)
      | InArc(..)
      | ChallengeFlag(..)
      | TitleOwned(..)
      | NoCase
      | Unread(..) -> []
    }
  })
}

/// The PrerequisiteTypes, in the prerequisite and the rows it nests, that a press cannot
/// check a gate of a Proxy with, each once: a type the server has not decoded
/// (`unread_types`), type 37, which draws a roll, and types 50, 108 and 130, which read the
/// second unit, which the client sets to the target of the unit that presses
/// (`ResolveProxyByCasterApply` `0x1403d3520`) while the subject here holds the caster.
pub fn press_unread_types(
  prerequisite prerequisite: Prerequisite,
) -> List(Int) {
  list.flat_map(prerequisite.conditions, fn(condition) {
    case condition {
      Nested(row: Some(nested), ..) -> press_unread_types(prerequisite: nested)
      Unread(prerequisite_type:) -> [prerequisite_type]
      Roll(..) -> [37]
      UnderCastBy(..) -> [50]
      StackCountByCaster(..) -> [60]
      InArc(..) -> [108]
      CarriesCasterGroup(..) -> [130]
      Nested(row: None, ..)
      | TargetOfLiveCast(..)
      | StackCount(..)
      | InCombat(..)
      | HealthPercent(..)
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
      | ChallengeFlag(..)
      | TitleOwned(..)
      | NeverMet
      | ServerGated
      | IsCreature(..)
      | SpellKnown(..)
      | ItemHeld(..)
      | WorldDifficulty(..)
      | ObjectiveStatus(..)
      | NoCase -> []
    }
  })
  |> list.unique
}

/// The PrerequisiteTypes, in the prerequisite and the rows it nests, that a unit the
/// caster struck cannot be checked against, each once: 15, 59 and 129, which read every
/// caster's casts on the unit, so only the unit's owner can hold them (the creature holds
/// none, since the casts are not moved into it). Every other type is one of the
/// creature's own facts (`of_creature`) or the caster's, and is read.
pub fn struck_unread_types(
  prerequisite prerequisite: Prerequisite,
) -> List(Int) {
  list.filter(unread_on_a_struck_unit(prerequisite:), list.contains(
    casts_held_types,
    _,
  ))
}

/// The PrerequisiteTypes that read every caster's casts on a unit: 15, 59 and 129.
pub const casts_held_types = [15, 59, 129]

/// The PrerequisiteTypes of the conditions the client decides and the server does
/// not read, in the prerequisite and the rows it nests, each once.
pub fn unread_types(prerequisite prerequisite: Prerequisite) -> List(Int) {
  list.flat_map(prerequisite.conditions, fn(condition) {
    case condition {
      Unread(prerequisite_type:) -> [prerequisite_type]
      Nested(row: Some(nested), ..) -> unread_types(prerequisite: nested)
      Nested(row: None, ..)
      | TargetOfLiveCast(..)
      | UnderCastBy(..)
      | StackCount(..)
      | StackCountByCaster(..)
      | InCombat(..)
      | Roll(..)
      | HealthPercent(..)
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
      | NeverMet
      | ServerGated
      | IsCreature(..)
      | SpellKnown(..)
      | ItemHeld(..)
      | WorldDifficulty(..)
      | ObjectiveStatus(..)
      | CarriesCasterGroup(..)
      | InArc(..)
      | ChallengeFlag(..)
      | TitleOwned(..)
      | NoCase -> []
    }
  })
  |> list.unique
}

/// The PrerequisiteTypes, in the prerequisite and the rows it nests, that the caster's own
/// check cannot read of a unit it struck, each once: the types its subject, known by its
/// place alone (`of_struck`), gives `NotRead`, and the factions and difficulty it holds none
/// of. A row whose gate the creature does not check (`checked_by_creature`) and that reads one
/// of them cannot be applied, since the caster is the only one left to check it.
pub fn unread_on_a_struck_unit(
  prerequisite prerequisite: Prerequisite,
) -> List(Int) {
  list.flat_map(prerequisite.conditions, fn(condition) {
    case reading_of(condition:) {
      OwnState(prerequisite_type:)
      | PlayerHealth(prerequisite_type:)
      | CastsHeld(prerequisite_type:) -> [
        prerequisite_type,
      ]
      NestedRow(row:) -> unread_on_a_struck_unit(prerequisite: row)
      WhoItIs | ReadElsewhere -> []
    }
  })
  |> list.unique
}

/// The PrerequisiteTypes, in the prerequisite and the rows it nests, that the caster's own
/// check cannot read of a player in its sight it heals, each once: those of
/// `unread_on_a_struck_unit` but the health percentage (type 40), which the caster's picture of
/// the player holds (`of_struck`, `with_health`).
pub fn unread_on_a_player(
  prerequisite prerequisite: Prerequisite,
) -> List(Int) {
  list.filter(unread_on_a_struck_unit(prerequisite:), fn(prerequisite_type) {
    prerequisite_type != 40
  })
}

/// What a condition reads of the unit a gate is tested on: the state the unit holds itself,
/// the casts held on it, who it is, a row it nests, or something else.
type Reading {
  /// The unit's level (1), class (3), factions (4 and 250), fight state (28), vitals (71 and
  /// 73) or difficulty (179).
  OwnState(prerequisite_type: Int)
  /// The health of a player the caster's picture holds (40): a creature holds none of its own
  /// to check against.
  PlayerHealth(prerequisite_type: Int)
  /// The casts held on the unit (15, 59 and 129).
  CastsHeld(prerequisite_type: Int)
  /// Whether the unit is a player (39) or which Creature2 row it is (38): known from its place
  /// alone, and held by a creature.
  WhoItIs
  /// A row the condition nests.
  NestedRow(row: Prerequisite)
  /// A roll, the second unit's casts, the player's own facts, or a condition the server
  /// does not read: nothing the unit holds.
  ReadElsewhere
}

fn reading_of(condition condition: Condition) -> Reading {
  case condition {
    Nested(row: Some(nested), ..) -> NestedRow(row: nested)
    Difficulty(..) -> OwnState(prerequisite_type: 179)
    CurrentFaction(..) -> OwnState(prerequisite_type: 4)
    BaseFaction(..) -> OwnState(prerequisite_type: 250)
    InCombat(..) -> OwnState(prerequisite_type: 28)
    HealthPercent(..) -> PlayerHealth(prerequisite_type: 40)
    VitalPercent(..) -> OwnState(prerequisite_type: 71)
    VitalCurrent(..) -> OwnState(prerequisite_type: 73)
    UnitLevel(..) -> OwnState(prerequisite_type: 1)
    UnitClass(..) -> OwnState(prerequisite_type: 3)
    TargetOfLiveCast(..) -> CastsHeld(prerequisite_type: 15)
    StackCount(..) -> CastsHeld(prerequisite_type: 59)
    UnderGroup(..) -> CastsHeld(prerequisite_type: 129)
    IsCreature(..) | IsPlayer(..) -> WhoItIs
    Nested(row: None, ..)
    | UnderCastBy(..)
    | StackCountByCaster(..)
    | Roll(..)
    | ResourceSlot(..)
    | Stealthed(..)
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
    | NeverMet
    | ServerGated
    | SpellKnown(..)
    | ItemHeld(..)
    | WorldDifficulty(..)
    | ObjectiveStatus(..)
    | CarriesCasterGroup(..)
    | InArc(..)
    | ChallengeFlag(..)
    | TitleOwned(..)
    | NoCase
    | Unread(..) -> ReadElsewhere
  }
}

/// Whether the creature a gate is tested on can check all of it from the state it holds
/// itself: every condition, and every condition of a row it nests, reads only that state or
/// who the creature is (38 and 39), and at least one reads the state; a gate of who the unit
/// is alone stays with the caster, which knows that from its place. A condition that reads the
/// casts held on the unit (15, 59, 129), draws a roll (37) or reads anything else is left to
/// the caster's check.
pub fn checked_by_creature(prerequisite prerequisite: Prerequisite) -> Bool {
  let readings =
    list.map(prerequisite.conditions, fn(condition) { reading_of(condition:) })
  list.all(readings, held_by_the_unit)
  && list.any(readings, fn(reading) { reading != WhoItIs })
}

fn held_by_the_unit(reading reading: Reading) -> Bool {
  case reading {
    OwnState(..) | WhoItIs -> True
    NestedRow(row:) -> checked_by_creature(prerequisite: row)
    PlayerHealth(..) | CastsHeld(..) | ReadElsewhere -> False
  }
}

/// The bytes of one roll: 4, a draw r of a multiple of 2^-32 in [0, 1).
pub const roll_bytes = 4

/// The rolls from 1 to 100 that the bytes make, one for each 4 bytes: 1 +
/// floor(100 r) for the draw r the 4 bytes make as a 32-bit number over 2^32
/// (`Prerequisite.prerequisiteTypeId.37`). Bytes left over after the last whole
/// roll are dropped.
pub fn rolls_of(bytes bytes: BitArray) -> List(Int) {
  list.map(random.words(bytes:), fn(word) { 1 + word * 100 / 4_294_967_296 })
}

/// The prerequisite checked against its subject (`0x1404a1ca0`).
pub fn check(
  prerequisite prerequisite: Prerequisite,
  subject subject: Subject,
) -> Verdict {
  let #(verdict, _) =
    evaluated(prerequisite:, subject:, rolls: subject.rolls, purpose: Gating)
  verdict
}

/// The prerequisite checked for what a unit's visibility prerequisite decides: as `check`,
/// except that type 47, which fails every cast, effect and gossip entry, is `NotRead`, so
/// a creature behind it stays shown.
pub fn check_for_visibility(
  prerequisite prerequisite: Prerequisite,
  subject subject: Subject,
) -> Verdict {
  let #(verdict, _) =
    evaluated(prerequisite:, subject:, rolls: subject.rolls, purpose: Showing)
  verdict
}

/// What a check decides.
type Purpose {
  /// Whether a cast, an effect or a gossip entry goes ahead.
  Gating
  /// Whether a unit is shown.
  Showing
}

/// The prerequisite's verdict and the rolls left after the conditions took theirs, in
/// order.
fn evaluated(
  prerequisite prerequisite: Prerequisite,
  subject subject: Subject,
  rolls rolls: List(Int),
  purpose purpose: Purpose,
) -> #(Verdict, List(Int)) {
  let #(left, verdicts) =
    list.map_fold(prerequisite.conditions, rolls, fn(rolls, condition) {
      condition_check(condition:, subject:, rolls:, purpose:)
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
  purpose purpose: Purpose,
) -> #(List(Int), Verdict) {
  case subject.seen, reads_held_state(condition:) {
    PlaceOnly, Some(prerequisite_type) -> #(rolls, NotRead(prerequisite_type:))
    PlaceAndHealth, Some(40) ->
      condition_decided(condition:, subject:, rolls:, purpose:)
    PlaceAndHealth, Some(prerequisite_type) -> #(
      rolls,
      NotRead(prerequisite_type:),
    )
    PlaceOnly, None | PlaceAndHealth, None | WholeUnit, _ ->
      condition_decided(condition:, subject:, rolls:, purpose:)
  }
}

/// The type of a condition that reads the casts, combat state or vitals of its unit,
/// which a subject known by its place alone does not hold. A type 50 condition reads the
/// casts of the second unit alone (`is_under_cast_by`), and a type 60 condition counts the
/// stacks of the second unit's casts alone (`stack_count`); the subject holds both as a
/// type 130 condition's do, so both are decided. A roll is no state of the unit
/// (`Prerequisite.prerequisiteTypeId.37`: the units are not read), so a type 37 condition
/// is given its roll for any subject. A nested row decides by
/// its own conditions, and a resource slot, a stealth and a difficulty that the subject
/// holds none of are not read by their own check.
fn reads_held_state(condition condition: Condition) -> Option(Int) {
  case condition {
    TargetOfLiveCast(..) -> Some(15)
    StackCount(..) -> Some(59)
    InCombat(..) -> Some(28)
    HealthPercent(..) -> Some(40)
    VitalPercent(..) -> Some(71)
    VitalCurrent(..) -> Some(73)
    UnderGroup(..) -> Some(129)
    UnitLevel(..) -> Some(1)
    UnitClass(..) -> Some(3)
    Nested(..)
    | UnderCastBy(..)
    | StackCountByCaster(..)
    | Roll(..)
    | IsPlayer(..)
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
    | ChallengeFlag(..)
    | TitleOwned(..)
    | NeverMet
    | ServerGated
    | IsCreature(..)
    | SpellKnown(..)
    | ItemHeld(..)
    | WorldDifficulty(..)
    | ObjectiveStatus(..)
    | CarriesCasterGroup(..)
    | InArc(..)
    | NoCase
    | Unread(..) -> None
  }
}

fn condition_decided(
  condition condition: Condition,
  subject subject: Subject,
  rolls rolls: List(Int),
  purpose purpose: Purpose,
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
        measured: stack_count(subject:, spell4_id:, caster: None),
        value:,
      )),
    )
    StackCountByCaster(relation:, spell4_id:, value:) -> #(
      rolls,
      case subject.second_unit, relation {
        None, NotEqual -> Passes
        None, _ -> Fails
        Some(second_unit), _ ->
          verdict_of(compare(
            relation:,
            measured: stack_count(
              subject:,
              spell4_id:,
              caster: Some(second_unit),
            ),
            value:,
          ))
      },
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
    HealthPercent(relation:, value:) -> #(
      rolls,
      case dict.get(subject.vitals, health_vital) {
        Ok(held) -> verdict_of(percent_compares(relation:, vital: held, value:))
        Error(Nil) -> NotRead(prerequisite_type: 40)
      },
    )
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
        Some(nested) ->
          evaluated(prerequisite: nested, subject:, rolls:, purpose:)
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
    IsPlayer(comparison:) -> #(rolls, case subject.first_unit {
      TheChecker | OtherPlayer -> equality_verdict(comparison:, equal: True)
      NonPlayer(..) -> equality_verdict(comparison:, equal: False)
      UnknownUnit -> NotRead(prerequisite_type: 39)
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
      with_quest_log(subject:, prerequisite_type: 6, decide: fn(view) {
        let state = case quest {
          Some(quest) -> quest_view.state(view:, quest:)
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
      with_quest_log(subject:, prerequisite_type: 68, decide: fn(view) {
        let done = case quest {
          Some(quest) -> quest_view.objective_done(view:, quest:, index:)
          None -> False
        }
        asked(comparison:, holds: done)
      }),
    )
    ObjectiveOpen(comparison:, index:, quest:) -> #(
      rolls,
      with_quest_log(subject:, prerequisite_type: 43, decide: fn(view) {
        let open = case quest {
          Some(quest) -> quest_view.objective_open(view:, quest:, index:)
          None -> False
        }
        asked(comparison:, holds: open)
      }),
    )
    TargetCounted(comparison:, index:, quest:) -> #(
      rolls,
      case subject.creature_index, quest {
        Some(creature_index), Some(quest) ->
          with_quest_log(subject:, prerequisite_type: 94, decide: fn(view) {
            asked(
              comparison:,
              holds: quest_view.is_marked(
                view:,
                quest:,
                index:,
                bit: creature_index,
              ),
            )
          })
        // No creature or an unknown quest: only comparison 2 passes, and the quest log
        // is not read (`0x14049f5b0`).
        None, _ | _, None ->
          case comparison {
            NotFound -> Passes
            Found | OtherComparison(..) -> Fails
          }
      },
    )
    ObjectiveProgress(prerequisite_type:, relation:, index:, value:, quest:) -> #(
      rolls,
      with_quest_log(subject:, prerequisite_type:, decide: fn(view) {
        let progress = case quest {
          Some(quest) -> quest_view.objective_progress(view:, quest:, index:)
          None -> 0
        }
        verdict_of(compare(relation:, measured: progress, value:))
      }),
    )
    // No 0xc7 is ever sent, so the client's challenge list is empty and no challenge
    // flag is set: not in cooldown, not active, not unlocked (`opcode.0xc7`,
    // `0x140c65948`).
    ChallengeFlag(comparison:) -> #(rolls, asked(comparison:, holds: False))
    TitleOwned(comparison:) -> #(rolls, case subject.first_unit {
      UnknownUnit -> NotRead(prerequisite_type: 288)
      TheChecker | OtherPlayer -> asked(comparison:, holds: False)
      NonPlayer(..) -> Fails
    })
    NeverMet -> #(rolls, Fails)
    // Type 47 is never met by a cast, an effect or a gossip entry; the visibility
    // check does not decide it, so the creature stays shown.
    ServerGated ->
      case purpose {
        Gating -> #(rolls, Fails)
        Showing -> #(rolls, NotRead(prerequisite_type: 47))
      }
    IsCreature(comparison:, value:) -> #(rolls, case subject.first_unit {
      UnknownUnit -> NotRead(prerequisite_type: 38)
      TheChecker | OtherPlayer ->
        equality_verdict(comparison:, equal: value == 0)
      NonPlayer(creature2_id:) ->
        equality_verdict(comparison:, equal: creature2_id == value)
    })
    SpellKnown(comparison:, spell4_base_id:) -> #(
      rolls,
      case subject.first_unit, subject.checker {
        UnknownUnit, _ -> NotRead(prerequisite_type: 214)
        NonPlayer(..), _ -> Fails
        TheChecker, None | OtherPlayer, None -> NotRead(prerequisite_type: 214)
        TheChecker, Some(checker) | OtherPlayer, Some(checker) ->
          equality_verdict(
            comparison:,
            equal: list.contains(checker.book, Spell4BaseId(spell4_base_id)),
          )
      },
    )
    ItemHeld(prerequisite_type:, comparison:, item2_id:, locations:) -> #(
      rolls,
      case subject.checker {
        None -> NotRead(prerequisite_type:)
        Some(checker) ->
          asked(
            comparison:,
            holds: list.any(checker.items, fn(item) {
              item.item2_id.value == item2_id
              && int.bitwise_and(
                locations,
                int.bitwise_shift_left(1, item.location),
              )
              != 0
            }),
          )
      },
    )
    WorldDifficulty(comparison:, value:) -> #(rolls, case subject.checker {
      None -> NotRead(prerequisite_type: 143)
      Some(checker) ->
        equality_verdict(comparison:, equal: checker.world_difficulty == value)
    })
    // The server holds no public event, so every objective has status 0
    // (`Prerequisite.prerequisiteTypeId.118`).
    ObjectiveStatus(comparison:, value:, ..) -> #(
      rolls,
      equality_verdict(comparison:, equal: value == 0),
    )
    CarriesCasterGroup(comparison:, group:) -> #(
      rolls,
      case subject.second_unit {
        None -> equality_verdict(comparison:, equal: False)
        Some(second_unit) ->
          asked(
            comparison:,
            holds: group != 0
              && list.any(subject.under, fn(held) {
              held.caster == second_unit && list.contains(held.groups, group)
            }),
          )
      },
    )
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
  decide decide: fn(QuestView) -> Verdict,
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

/// The stack count of the Spell4 on the subject: the sum of the instance counts of the
/// casts that hold a node on it, over every caster (`None`, type 59) or over one caster
/// alone (`Some(unit_id)`, type 60), which counts 0 for unit id 0 (`0x14046a110`).
fn stack_count(
  subject subject: Subject,
  spell4_id spell4_id: Spell4Id,
  caster caster: Option(Int),
) -> Int {
  use <- bool.guard(when: caster == Some(0), return: 0)
  int.sum(
    list.filter_map(subject.under, fn(held) {
      let by_caster = case caster {
        None -> True
        Some(unit_id) -> held.caster == unit_id
      }
      case held.spell4_id == spell4_id && by_caster {
        True -> Ok(held.count)
        False -> Error(Nil)
      }
    }),
  )
}

fn verdict_of(holds: Bool) -> Verdict {
  use <- bool.guard(when: holds, return: Passes)
  Fails
}

/// Type 71's comparison: the vital's percentage of its maximum against the value
/// made a 32-bit float, in 32-bit floats as the client computes it
/// (`0x1404a4e30`). Nothing held of nothing is not a number, which counts as equal
/// and fails every other comparison; something held of nothing is positive infinity,
/// beyond every value. Gleam's `/.` gives 0.0 for a zero divisor, so both cases are
/// decided here and never by the division.
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
  // ucomiss takes -0.0 as equal to 0.0 (`0x1404a2010`), which Gleam's `==` on the BEAM does
  // not, and a 0 current over a negative maximum is -0.0.
  let measured = case measured <. 0.0 || measured >. 0.0 {
    True -> measured
    False -> 0.0
  }
  holds(relation:, ordering: float.compare(measured, value))
}

/// What the prerequisite conditions read that the server does not hold.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Prerequisites",
      missing: "the status of a public event objective (type 118): the server holds no public event, so every objective reads inactive",
    ),
    gap.Entry(
      area: "Prerequisites",
      missing: "a player's challenge records (types 125, 69 and 74): the server holds none, so every flag reads clear",
    ),
    gap.Entry(
      area: "Prerequisites",
      missing: "a player's owned titles (type 288): the server owns no title, so the set reads empty",
    ),
    gap.Entry(
      area: "Prerequisites",
      missing: "an item in the checker's satchel and in the item locations 5, 8, 9 and 10 (types 13, 14 and 246): the server saves items only in locations 0, 1 and 2, so an item there reads as not held",
    ),
    gap.Entry(
      area: "Prerequisites",
      missing: "the real test of a type 47 condition, whose ids the client never reads: a cast, an effect or a gossip entry behind it fails, and a creature it hides stays shown",
    ),
    gap.Entry(
      area: "Prerequisites",
      missing: "the casts of every other caster on a creature or on a player a bag press named (types 15, 59 and 129): the check of a creature a player struck, and of the player a press named, leaves them unread",
    ),
  ]
}
