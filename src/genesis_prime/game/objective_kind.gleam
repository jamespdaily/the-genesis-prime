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
//// - A rule that wants one kind's data asks an accessor (`used_creature`, `cast_spell`,
////   `placed_target` and the like), each the only place that lists every kind for its
////   question, so a site carries no list of kinds that do not answer.
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

/// What a kill of a unit that the server places names: one creature, or a group of
/// them.
pub type PlacedTarget {
  OneCreature(creature2_id: Creature2Id)
  GroupOf(target_group_id: TargetGroupId)
}

/// How a checklist objective names the units it counts.
pub type ChecklistTarget {
  /// Each unit of the TargetGroup.
  UnitsOfGroup(target_group_id: TargetGroupId)
  /// The unit of the PathSoldierActivate row.
  UnitOfSoldier(path_soldier_activate_id: PathSoldierActivateId)
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

/// The creature a use objective names: type 12 (`QuestObjective.type.12`).
pub fn used_creature(kind: Kind) -> Result(Creature2Id, Nil) {
  case kind {
    UseCreature(creature2_id:) -> Ok(creature2_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The zone a visit objective names: type 17 (`QuestObjective.type.17`).
pub fn visited_zone(kind: Kind) -> Result(WorldZoneId, Nil) {
  case kind {
    VisitZone(world_zone_id:) -> Ok(world_zone_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The spell a cast objective names: type 11 (`QuestObjective.type.11`), 0 included.
pub fn cast_spell(kind: Kind) -> Result(Spell4Id, Nil) {
  case kind {
    CastSpell(spell4_id:) -> Ok(spell4_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The TargetGroup a use-one-of-a-set objective names: type 23
/// (`QuestObjective.type.23`).
pub fn used_group(kind: Kind) -> Result(TargetGroupId, Nil) {
  case kind {
    UseGroup(target_group_id:) -> Ok(target_group_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The TargetGroup a use-each checklist objective names: type 14
/// (`QuestObjective.type.14`), not the talk checklist of type 18.
pub fn used_checklist_group(kind: Kind) -> Result(TargetGroupId, Nil) {
  case kind {
    ChecklistUse(target_group_id:) -> Ok(target_group_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// What a kill objective that the server places names: a creature for type 2, a
/// TargetGroup for types 8 and 16 (`QuestObjective.type.2`, `QuestObjective.type.8`,
/// `QuestObjective.type.16`); no other kind is placed.
pub fn placed_target(kind: Kind) -> Result(PlacedTarget, Nil) {
  case kind {
    KillCreature(creature2_id:) -> Ok(OneCreature(creature2_id:))
    KillGroup(target_group_id:) -> Ok(GroupOf(target_group_id:))
    Unconditional
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The creature a talk objective names: type 3 (`QuestObjective.type.3`).
pub fn talked_creature(kind: Kind) -> Result(Creature2Id, Nil) {
  case kind {
    TalkTo(creature2_id:) -> Ok(creature2_id)
    Unconditional
    | KillCreature(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The TargetGroup a talk-to-each checklist objective names: type 18
/// (`QuestObjective.type.18`), not the use checklist of type 14.
pub fn talked_checklist_group(kind: Kind) -> Result(TargetGroupId, Nil) {
  case kind {
    ChecklistTalk(target_group_id:) -> Ok(target_group_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The item a collect objective names: type 4 (`QuestObjective.type.4`).
pub fn collected_item(kind: Kind) -> Result(Item2Id, Nil) {
  case kind {
    CollectItem(item2_id:) -> Ok(item2_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The schematic a craft objective names: type 33 (`QuestObjective.type.33`).
pub fn crafted_schematic(kind: Kind) -> Result(TradeskillSchematic2Id, Nil) {
  case kind {
    CraftItem(tradeskill_schematic2_id:) -> Ok(tradeskill_schematic2_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// The quest a finish objective names: type 24 (`QuestObjective.type.24`).
pub fn finished_quest(kind: Kind) -> Result(Quest2Id, Nil) {
  case kind {
    FinishQuest(quest2_id:) -> Ok(quest2_id)
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | ChecklistActivate(_)
    | Placeholder
    | CollectVirtualItem(_)
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> Error(Nil)
  }
}

/// Whether a use counts for the objective only through the creature the server links
/// to it (`genesis_prime/game/objective_link`): types 5 and 32 (`QuestObjective.type.5`,
/// `QuestObjective.type.32`).
pub fn is_linked_use(kind: Kind) -> Bool {
  case kind {
    Scripted | CollectVirtualItem(_) -> True
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | KillGroup(_)
    | ServerChecklist
    | CastSpell(_)
    | UseCreature(_)
    | ChecklistUse(_)
    | KillByCluster(_)
    | VisitZone(_)
    | ChecklistTalk(_)
    | ReachPlace
    | UseGroup(_)
    | FinishQuest(_)
    | ChecklistActivate(_)
    | Placeholder
    | CraftItem(_)
    | KillByDifficulty(_)
    | Unread(_) -> False
  }
}

/// Whether the objective is a kill of a unit by its cluster: type 15
/// (`QuestObjective.type.15`).
pub fn kills_by_cluster(kind: Kind) -> Bool {
  case kind {
    KillByCluster(_) -> True
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
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
    | KillByDifficulty(_)
    | Unread(_) -> False
  }
}

/// The units a checklist objective counts: the TargetGroup of types 14 and 18, the
/// PathSoldierActivate row of types 27 and 28 (`0x1405517a0`). Types 10 and 13 name
/// none, since their progress comes only from the server; whether a 27 or 28 is a
/// checklist at all is `is_checklist`.
pub fn checklist_target(kind: Kind) -> Result(ChecklistTarget, Nil) {
  case kind {
    ChecklistUse(target_group_id:) | ChecklistTalk(target_group_id:) ->
      Ok(UnitsOfGroup(target_group_id:))
    ChecklistActivate(path_soldier_activate_id:) ->
      Ok(UnitOfSoldier(path_soldier_activate_id:))
    Unconditional
    | KillCreature(_)
    | TalkTo(_)
    | CollectItem(_)
    | Scripted
    | KillGroup(_)
    | ServerChecklist
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
    | Unread(_) -> Error(Nil)
  }
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
