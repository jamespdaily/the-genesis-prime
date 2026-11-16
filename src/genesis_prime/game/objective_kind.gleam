//// The kind of a QuestObjective row, decoded once from its `type` and `data`: the one
//// place the server names the client's objective types. A rule that sorts objectives
//// by type matches on `Kind`, so a new variant names every place that must handle it,
//// and the coverage measure counts a type through `is_counted`, so a rule and the
//// measure cannot disagree. Each variant carries what the row's `data` names for its
//// type; types with no variant are `Unread`.
////
//// ```text
//// QuestObjective row (type, data) -> kind_of / of_row -> Kind -> a rule's case
//// ```
////
//// - Types 8 and 16, 10 and 13, and 27 and 28 share a variant because the client
////   treats each pair alike (`QuestObjective.type.16`, `0x1405517a0`); a variant splits
////   when a rule first needs the number.
//// - A kill is a type 2, 8, 15, 16 or 46 (`0x140550c50`, `0x1406113b0`); a checklist
////   counts its progress as bits (`0x1405517a0`).
//// - This module imports only the generated tables and typed ids, so any game module
////   can name a kind.

import genesis_prime/table/id.{
  type Creature2DifficultyId, type Creature2Id, type Item2Id,
  type PathSoldierActivateId, type Quest2Id, type Spell4Id, type TargetGroupId,
  type TradeskillSchematic2Id, type VirtualItemId, type WorldZoneId,
  Creature2DifficultyId, Creature2Id, Item2Id, PathSoldierActivateId, Quest2Id,
  Spell4Id, TargetGroupId, TradeskillSchematic2Id, VirtualItemId, WorldZoneId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_soldier_activate
import genesis_prime/table/quest_objective.{type QuestObjective}

/// What a rule reads a QuestObjective row as.
pub type Kind {
  /// Type 0: an objective that is always reachable (`0x140553790`). No row of the
  /// client's table has it.
  Unconditional
  /// Type 2: kill a creature (`QuestObjective.type.2`); the data is a Creature2 id.
  KillCreature(creature2_id: Creature2Id)
  /// Type 3: talk to a creature (`QuestObjective.type.3`); the data is a Creature2 id.
  TalkTo(creature2_id: Creature2Id)
  /// Type 4: collect an item (`QuestObjective.type.4`); the data is an Item2 id.
  CollectItem(item2_id: Item2Id)
  /// Type 5: a scripted objective the client gives no rule of its own
  /// (`QuestObjective.type.5`); its data has no single meaning, so none is read.
  Scripted
  /// Type 8 or 16: kill a unit of a TargetGroup (`QuestObjective.type.8`,
  /// `QuestObjective.type.16`); the data is a TargetGroup id.
  KillGroup(target_group_id: TargetGroupId)
  /// Type 10 or 13: a checklist whose progress comes only from the server
  /// (`QuestObjective.type.10`, `0x1405517a0`); its data is not read.
  ServerChecklist
  /// Type 11: cast a spell a number of times (`QuestObjective.type.11`); the data is a
  /// Spell4 id, or 0 or an id with no row in a few rows.
  CastSpell(spell4_id: Spell4Id)
  /// Type 12: use a creature (`QuestObjective.type.12`); the data is a Creature2 id.
  UseCreature(creature2_id: Creature2Id)
  /// Type 14: use each of a set of units, counted as checklist bits
  /// (`QuestObjective.type.14`); the data is a TargetGroup id.
  ChecklistUse(target_group_id: TargetGroupId)
  /// Type 15: kill a unit whose cluster equals the data (`QuestObjective.type.15`), a
  /// server cluster id that is neither a Creature2 id nor a TargetGroup. The server
  /// counts such a kill by the objective's reward pane (genesis_prime/game/objective),
  /// which is not how the client counts it; the issue "Kill objectives count by cluster,
  /// rank and a unit's tagged value" (#334) closes that.
  KillByCluster(cluster: Int)
  /// Type 17: visit a zone (`QuestObjective.type.17`); the data is a WorldZone id.
  VisitZone(world_zone_id: WorldZoneId)
  /// Type 18: talk to each of a set of units, counted as checklist bits
  /// (`QuestObjective.type.18`); the data is a TargetGroup id.
  ChecklistTalk(target_group_id: TargetGroupId)
  /// Type 22: reach a place the server judges (`QuestObjective.type.22`); the data is
  /// the server's own trigger id, which no client table holds, so none is read: the
  /// place is the row's marker columns.
  ReachPlace
  /// Type 23: use one of a set of units (`QuestObjective.type.23`); the data is a
  /// TargetGroup id.
  UseGroup(target_group_id: TargetGroupId)
  /// Type 24: complete another quest (`QuestObjective.type.24`); the data is a Quest2
  /// id.
  FinishQuest(quest2_id: Quest2Id)
  /// Type 27 or 28: free each of a set of units, counted as checklist bits when the
  /// PathSoldierActivate row the data names has soldierActivateModeEnum 1 or 2
  /// (`QuestObjective.type.28`, `QuestObjective.type.27`, `0x1405517a0`); the data is a
  /// PathSoldierActivate id.
  ChecklistActivate(path_soldier_activate_id: PathSoldierActivateId)
  /// Type 31: a hidden objective with count 0 and no text (`QuestObjective.type.31`, a
  /// guess); the server only treats it as not shown.
  Placeholder
  /// Type 32: collect a virtual item (`QuestObjective.type.32`); the data is a
  /// VirtualItem id.
  CollectVirtualItem(virtual_item_id: VirtualItemId)
  /// Type 33: collect a crafted item (`QuestObjective.type.33`); the data is a
  /// TradeskillSchematic2 id.
  CraftItem(tradeskill_schematic2_id: TradeskillSchematic2Id)
  /// Type 46: kill a hostile unit whose Creature2Difficulty id is at least the data
  /// (`QuestObjective.type.46`).
  KillByDifficulty(creature2_difficulty_id: Creature2DifficultyId)
  /// Any other type: the client's data holds it and no rule of the server reads it.
  Unread(type_number: Int)
}

/// The kind of an objective of type `type_number` with `data`
/// (`QuestObjective.type`, `QuestObjective.data`).
pub fn kind_of(type_number type_number: Int, data data: Int) -> Kind {
  case type_number {
    0 -> Unconditional
    2 -> KillCreature(Creature2Id(data))
    3 -> TalkTo(Creature2Id(data))
    4 -> CollectItem(Item2Id(data))
    5 -> Scripted
    8 | 16 -> KillGroup(TargetGroupId(data))
    10 | 13 -> ServerChecklist
    11 -> CastSpell(Spell4Id(data))
    12 -> UseCreature(Creature2Id(data))
    14 -> ChecklistUse(TargetGroupId(data))
    15 -> KillByCluster(cluster: data)
    17 -> VisitZone(WorldZoneId(data))
    18 -> ChecklistTalk(TargetGroupId(data))
    22 -> ReachPlace
    23 -> UseGroup(TargetGroupId(data))
    24 -> FinishQuest(Quest2Id(data))
    27 | 28 -> ChecklistActivate(PathSoldierActivateId(data))
    31 -> Placeholder
    32 -> CollectVirtualItem(VirtualItemId(data))
    33 -> CraftItem(TradeskillSchematic2Id(data))
    46 -> KillByDifficulty(Creature2DifficultyId(data))
    other -> Unread(type_number: other)
  }
}

/// The kind of a QuestObjective row.
pub fn of_row(row: QuestObjective) -> Kind {
  kind_of(type_number: row.type_, data: row.data)
}

/// Whether the objective sets the kill result when a unit counts for it: types 2, 8,
/// 15, 16 and 46 (`0x140550c50`, `0x1406113b0`).
pub fn is_kill(kind: Kind) -> Bool {
  case kind {
    KillCreature(_) | KillGroup(_) | KillByCluster(_) | KillByDifficulty(_) ->
      True
    Unconditional
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | Unread(_) -> False
  }
}

/// Whether the objective counts its progress as bits (`0x1405517a0`): types 10, 13, 14
/// and 18, and types 27 and 28 whose PathSoldierActivate row (named by the data) has
/// soldierActivateModeEnum 1 or 2; no such row means not a checklist.
pub fn is_checklist(
  tables tables: table_store.Tables,
  kind kind: Kind,
) -> Bool {
  case kind {
    ServerChecklist | ChecklistUse(_) | ChecklistTalk(_) -> True
    ChecklistActivate(path_soldier_activate_id:) ->
      case path_soldier_activate.get(tables:, id: path_soldier_activate_id) {
        Ok(row) ->
          row.soldier_activate_mode_enum == 1
          || row.soldier_activate_mode_enum == 2
        Error(Nil) -> False
      }
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | CastSpell(_)
    | UseCreature(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> False
  }
}

/// Whether a rule of the server advances an objective of this type: the coverage
/// measure's "handled". Types 11 (a cast of the objective's spell), 10, 13, 15, 27, 31
/// and 46 differ from the decode: 10, 13, 15, 31 and 46 decode but advance no objective
/// (progress of 10 and 13 comes only from the server, no kill advances 15 or 46, 31 is
/// not shown); type 27 decodes as 28, but its one row is in no quest
/// (`QuestObjective.type.27`), so it is not counted.
pub fn is_counted(type_number type_number: Int) -> Bool {
  case kind_of(type_number:, data: 0) {
    KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | CollectVirtualItem(_)
    | CraftItem(_) -> True
    ChecklistActivate(_) -> type_number == 28
    Unconditional
    | ServerChecklist
    | KillByCluster(_)
    | Placeholder
    | KillByDifficulty(_)
    | Unread(_) -> False
  }
}
