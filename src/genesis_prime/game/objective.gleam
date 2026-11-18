//// What a talk to a creature, a use of one or a kill does to the open objectives of the
//// player's quest log, and what the client is told. A type 3 objective is a talk and a
//// type 12 objective a use, and the data of both is a Creature2 id
//// (`QuestObjective.type.3`, `0x1404dd4c0.objective_creature`). A checklist objective
//// counts each unit once, by the unit's checklist index: type 14 is a use and type 18 a
//// talk of a unit in the TargetGroup of its data, types 27 and 28 a use of the creature of
//// the PathSoldierActivate row of its data (when that row makes it a checklist,
//// `objective_kind.is_checklist`); the use or talk sets the bit of the unit's index in the
//// objective's mask, and a unit whose bit is set counts for nothing
//// (`opcode.0x361`, `0x140611680`). A kill counts for the
//// objectives of `0x140550c50`: type 2 for a unit of the Creature2 id in its data,
//// types 8 and 16 for a unit in the TargetGroup of its data, and, for a kill objective
//// of any of these types or of types 15 and 46, a unit in the objective's reward pane
//// TargetGroup (the pane counts whatever the type, but only a kill is wanted here:
//// the other types' own tests are not kills). Types 15 and 46 count by a cluster value
//// and a rank the server has no unit data for, so they take a kill only by the pane
//// (a gap, the issue "Kill objectives count by cluster, rank and a unit's tagged
//// value"). A type 15 objective whose pane is a list of creatures (TargetGroup type 1) is
//// a named group: its progress stays 0, and is not sent, until the player's blow has
//// killed every creature of the list, each recorded once as a bit of the objective's
//// kill mask in the log (`group_member`, `quest_log.kill_marked`; the mask is never sent:
//// `opcode.0x361` carries only the progress), and the last one's kill makes it 1 of its
//// count 1 (the client's needed value is 1 for count 1, `0x140551840`). A type 5
//// objective (`QuestObjective.type.5`, a scripted objective) that no creature links takes
//// none of these events: nothing the client sends completes one, so the server completes
//// it by what `script_of` says, and a timed one the server does not complete runs out
//// (`quest_log.expire`):
//// - a hidden one (`QuestObjective.flags.8`) and a visible, required one with no marker
////   are done once the quest's other required objectives are (`stand_in_scripts`, a
////   server choice);
//// - a visible, required one with a marker is done when the quest is accepted, or when it
////   is open if flags 1 and 2 keep it closed until then, whatever else the quest holds
////   (`stand_in_scripts`, a server choice that stands in for the real trigger each
////   objective asks for, the issue "Each kind of scripted quest step that the
////   Tower fix completes on accept gets its real rule");
//// - one of the `arrival_objectives` is done when the player stands at one of its markers
////   (`arrivals`), because its text asks only to go there;
//// - one a spell effect or an item names (`objective_action`) stays open until a cast
////   counts for it: a QuestAdvanceObjective row of the cast's spell advances it
////   (genesis_prime/game/quest_advance);
//// - one of the `held_objectives` stays open whichever of these it is, because only an
////   instance run or a PvP match completes it.
//// An objective takes the event only while it is open (`0x1405510d0`, `0x140553790`): its
//// quest is in the active list, Accepted or Achieved (`0x1405510d0` tests only for state
//// 3), it is not done and it is reachable. Every objective that is open and counts the
//// event counts once for it, so a later objective that the event unlocks waits for the
//// next one.
////
//// An objective that counts a use of a unit (types 5, 12, 23 and 32, and a cast at a
//// unit, type 11) counts each unit once (`quest_log.used`), except an objective in
//// `reused`, whose world holds fewer units than its count
//// (`objective_units.reused`) and which counts the same unit again; a checklist objective
//// counts each unit by its bit. The client keeps no per-unit record for any of them
//// (`0x1405517a0`, `QuestObjective.type.32.repeat_use`), so the once is the server's
//// choice. A use that counts a unit new to an objective also releases the unit
//// (`ReleaseUnit`): a used quest object vanishes for everyone for the release time, once
//// for the use however many objectives and quests counted it. A talk, a kill and a cast
//// at a unit release nothing, and nor does a use of a departures terminal, which every
//// player uses (`departures.is_terminal`). The used sets are not saved: a relog lets a
//// unit count again, and an abandoned quest that is retaken starts them empty. Each
//// player's log is its own, so two players who use a unit before it vanishes for them both
//// each count it, and once it returns the player whose set holds it counts nothing while
//// another counts it.
////
//// A type 11 objective (`QuestObjective.type.11`) is a cast of the spell in its data. The
//// client counts nothing for it: it shows the spell as a button (a 0x176 shortcut of kind
//// 2, keyed by the objective's id) while the objective is open and takes the button away
//// when the objective closes (`buttons`, `button_changes`), and the server counts one
//// for each cast of the spell at its go (`Cast`), for every open objective that names it.
//// A cast at a unit counts only for a unit of the objective's reward pane, any unit when
//// it names none (`0x140550c50`, issue 724's decision 2c), and each unit once, as a type
//// 23 objective does (`quest_log.used`; the client keeps no per-unit record, so the once is
//// the server's choice, and an objective in `reused` counts the same unit again); a cast of a spell aimed at the caster names no unit and counts
//// at each go. Gaps, each closed by the quests, zones and prerequisites issue (#334): the
//// go is the moment a cast counts by a guess, until a retail recording of quest 3915, 4832
//// or 7618 shows it; the place an objective names is not tested; a spell aimed at the
//// caster whose objective sets a reward pane (rows 14187 and 14203) counts at the go, not
//// on a unit of the pane; and the objectives with no Spell4 row (7378, 8042, 9882, 16525,
//// 16577 and 15816) hold no button and stay uncompletable.
////
//// A quest that no creature receives (`communicator.completed_by_server`) is completed by
//// the server once it is Achieved: the effect `CompleteByServer` follows the 0x35c that makes
//// it Achieved, and `server_completions` lists the quests a log already holds Achieved.
////
//// A rule: the log and the event in, the log and the effects out.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/communicator
import genesis_prime/game/departures
import genesis_prime/game/objective_action
import genesis_prime/game/objective_kind
import genesis_prime/game/objective_link
import genesis_prime/game/place_objective
import genesis_prime/game/quest as quest_rules
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/shown
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/target_group
import genesis_prime/store.{type HeldItem}
import genesis_prime/table/id.{
  type Creature2Id, type Item2Id, type PathSoldierActivateId, type Spell4Id,
  Creature2Id, Quest2Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_soldier_activate
import genesis_prime/table/quest2
import genesis_prime/table/spell4
import genesis_prime/table/tradeskill_schematic2
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// The QuestObjective flag that hides an objective from the player
/// (`QuestObjective.flags.8`); it does not change whether the objective is done.
const hidden_flag = 8

/// The state number of an Achieved quest in 0x035C.
const achieved_state = 2

/// What the player did to a creature: talked to it, used it or killed it (the unit as
/// the client's group test reads it), with the unit's checklist index for the first two
/// (the bit the unit stands for in a checklist objective's mask), or cast a spell, at a
/// unit or, for a spell aimed at the caster, at none. A use is by an item (`by_item`) when
/// the player's item spell hit the creature and not the creature's own activate spell: the
/// objectives that count the creature's own activate cast (types 5 and 32) take only the
/// latter.
pub type Event {
  TalkedTo(target: target_group.Unit, checklist_index: Int)
  Used(
    target: target_group.Unit,
    checklist_index: Int,
    unit: quest_log.UnitRef,
    by_item: Bool,
  )
  Killed(target: target_group.Unit)
  Cast(spell4_id: Spell4Id, target: Option(CastTarget))
}

/// The unit a cast was at: as the client's group test reads it, and as the map run's
/// unit that a cast objective counts once.
pub type CastTarget {
  CastTarget(unit: target_group.Unit, ref: quest_log.UnitRef)
}

/// A spell button the client holds for an open cast objective.
pub type Button {
  Button(spell4_id: Spell4Id, objective_id: Int)
}

/// A change to the buttons the client holds.
pub type ButtonChange {
  Remove(button: Button)
  Add(button: Button)
}

/// The buttons of the log's open cast objectives: each open objective of type 11 whose
/// data names a spell that has a Spell4 row (`QuestObjective.type.11.button`). The client
/// refuses a press of a spell with no record (`0x14039b340`, 22), so such a button would
/// be dead and is not given.
pub fn buttons(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> Set(Button) {
  list.flat_map(quest_log.active_ids(log:), fn(quest_id) {
    quest_log.open_objectives(log:, quest: quest_of(tables:, quest_id:))
  })
  |> list.filter_map(fn(open) {
    let objective = open.1
    case objective_kind.cast_spell(objective.kind) {
      Ok(spell4_id) ->
        case spell4.get(tables:, id: spell4_id) {
          Ok(_) -> Ok(Button(spell4_id:, objective_id: objective.objective_id))
          Error(Nil) -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
    }
  })
  |> set.from_list
}

/// The changes that take the client from the buttons it holds to these: the removes
/// first, then the adds, each by objective id so that the order is the same every time.
/// The client keys an entry by spell, kind and id, ignores an add it holds and removes only
/// an exact match (`0x1403b9fb0`), so a button held in both is not sent again.
pub fn button_changes(
  held held: Set(Button),
  now now: Set(Button),
) -> List(ButtonChange) {
  let ordered = fn(buttons: Set(Button)) {
    list.sort(set.to_list(buttons), fn(one: Button, other: Button) {
      int.compare(one.objective_id, other.objective_id)
    })
  }
  list.append(
    list.map(ordered(set.difference(held, now)), Remove),
    list.map(ordered(set.difference(now, held)), Add),
  )
}

/// What the client is told: one objective's new progress (0x361), and a quest's new
/// state (0x35c): 2 (Achieved) once its last open objective is done, 1 (Accepted) when
/// a count fell and an objective is not done again (`0x1405fb830`, `0x1405fbdc0`).
pub type Effect {
  SendProgress(quest_id: Int, objective_index: Int, progress: Int)
  SendState(quest_id: Int, state: Int)
  /// The quest just became Achieved and no creature receives it: the server completes it
  /// (genesis_prime/game/quest_turn_in `completed_by_server`). It sends nothing itself.
  CompleteByServer(quest_id: Int)
  /// A use counted a unit new to an objective: the unit goes out of sight of everyone for
  /// the release time, and the effect follows every progress, state and completion effect
  /// of the same event (`advance`). It sends nothing itself.
  ReleaseUnit(unit_id: Int)
}

/// The log after the event and the effects in order: a quest at a time in quest id
/// order, its progress messages in objective order, then its state when the event moved
/// it. A quest that was Achieved already is not told again.
pub type Advanced {
  Advanced(log: QuestLog, effects: List(Effect))
}

/// Whether a talk to the unit, of the checklist index, counts for an open objective of
/// the log: a type 3 objective that names its Creature2 id (`0x140553110`), or a type 18
/// objective whose TargetGroup holds it while its bit is not yet set (`0x140611680`: the
/// client marks the unit only then). Every quest of the log has its rows in the tables.
pub fn talk_targets(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> fn(target_group.Unit, Int) -> Bool {
  let offered = counted_by(log:, tables:)
  fn(unit, checklist_index) {
    offered(TalkedTo(target: unit, checklist_index:))
  }
}

/// Whether a use of the unit, of the checklist index, counts for an open objective of the
/// log: the objectives a `Used` event counts for (`counts`) while the unit's bit is not
/// yet set, as a talk's is (`talk_targets`), and while this unit is not one the objective
/// counted already (`quest_log.is_used`; an objective in `reused` keeps no such set). A
/// unit no open objective counts a use of is offered no use by the server.
pub fn use_targets(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> fn(target_group.Unit, Int, quest_log.UnitRef) -> Bool {
  let offered = counted_by(log:, tables:)
  fn(unit, checklist_index, ref) {
    offered(Used(target: unit, checklist_index:, unit: ref, by_item: False))
  }
}

fn counted_by(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> fn(Event) -> Bool {
  let open =
    list.flat_map(quest_log.active_ids(log:), fn(quest_id) {
      let quest = quest_of(tables:, quest_id:)
      quest_log.open_objectives(log:, quest:)
      |> list.map(fn(open) { #(quest, open.0, open.1) })
    })
  fn(event) {
    list.any(open, fn(found) {
      let #(quest, index, objective) = found
      counts(tables:, event:, quest_id: quest.id, index:, objective:)
      && !counted_already(log:, quest:, index:, event:)
    })
  }
}

/// Whether the objective at `index` has counted the unit of the event already: the unit's
/// bit is set in a checklist objective's mask (`0x140611680`: the client marks the unit
/// only then), or the objective has counted this unit of the map run
/// (`quest_log.is_used`; an objective in `reused` keeps no such record).
fn counted_already(
  log log: QuestLog,
  quest quest: quest_log.Quest,
  index index: Int,
  event event: Event,
) -> Bool {
  case event {
    TalkedTo(checklist_index:, ..) ->
      quest_log.is_marked(log:, quest:, index:, bit: checklist_index)
    Used(checklist_index:, unit:, ..) ->
      quest_log.is_marked(log:, quest:, index:, bit: checklist_index)
      || quest_log.is_used(log:, quest:, index:, unit:)
    Cast(target: Some(CastTarget(ref:, ..)), ..) ->
      quest_log.is_used(log:, quest:, index:, unit: ref)
    Killed(..) | Cast(target: None, ..) -> False
  }
}

fn quest_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> quest_log.Quest {
  let assert Ok(quest) = quest_log.quest_of(tables:, id: quest_id)
    as {
      "quest "
      <> int.to_string(quest_id)
      <> " of the player's log has its rows in the tables"
    }
  quest
}

/// The log and the messages after the player talked to, used or killed a creature, or
/// cast a spell. `reused` is the objectives whose unit may count again
/// (`objective_units.reused`). A use that counts a unit new to any objective of any quest
/// ends the effects with one `ReleaseUnit`, after every quest's effects, unless the unit is
/// a departures terminal.
pub fn advance(
  log log: QuestLog,
  tables tables: table_store.Tables,
  event event: Event,
  reused reused: Set(Int),
  now_ms now_ms: Int,
) -> Advanced {
  let #(advanced, credited_a_new_unit) =
    list.fold(
      quest_log.active_ids(log:),
      #(Advanced(log:, effects: []), False),
      fn(so_far, quest_id) {
        let #(advanced, credited_before) = so_far
        let #(advanced, credited) =
          advance_quest(
            so_far: advanced,
            tables:,
            quest: quest_of(tables:, quest_id:),
            now_ms:,
            reused:,
            counts: fn(index, objective) {
              counts(tables:, event:, quest_id:, index:, objective:)
            },
            group_member: fn(objective) {
              case event {
                Killed(target:) -> group_member(tables:, objective:, target:)
                TalkedTo(..) | Used(..) | Cast(..) -> Error(Nil)
              }
            },
            checklist_index: case event {
              TalkedTo(checklist_index:, ..) | Used(checklist_index:, ..) ->
                checklist_index
              Killed(..) | Cast(..) -> -1
            },
            used_unit: case event {
              Used(unit:, ..)
              | Cast(target: Some(CastTarget(ref: unit, ..)), ..) -> Ok(unit)
              TalkedTo(..) | Killed(..) | Cast(target: None, ..) -> Error(Nil)
            },
          )
        #(advanced, credited_before || credited)
      },
    )
  case event, credited_a_new_unit {
    Used(target:, unit:, ..), True ->
      case departures.is_terminal(creature_id: target.creature_id) {
        True -> advanced
        False ->
          Advanced(
            ..advanced,
            effects: list.append(advanced.effects, [
              ReleaseUnit(unit_id: unit.unit_id),
            ]),
          )
      }
    Used(..), False | TalkedTo(..), _ | Killed(..), _ | Cast(..), _ -> advanced
  }
}

/// Whether the event counts for the objective at `index` of the quest (`0x140550c50`).
/// Public so that the units `objective_units.units_of` lists can be checked against it
/// for every objective of the client's tables.
pub fn counts(
  tables tables: table_store.Tables,
  event event: Event,
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_log.Objective,
) -> Bool {
  case event {
    TalkedTo(target:, ..) ->
      {
        objective_kind.talked_creature(objective.kind) == Ok(target.creature_id)
      }
      || {
        case objective_kind.talked_checklist_group(objective.kind) {
          Ok(group) ->
            target_group.contains(tables:, group: group.value, unit: target)
          Error(Nil) -> False
        }
      }
    Used(target:, by_item:, ..) ->
      { objective_kind.used_creature(objective.kind) == Ok(target.creature_id) }
      || {
        case objective_kind.used_checklist_group(objective.kind) {
          Ok(group) ->
            target_group.contains(tables:, group: group.value, unit: target)
          Error(Nil) -> False
        }
      }
      || {
        case objective_kind.used_group(objective.kind) {
          Ok(group) ->
            target_group.contains(tables:, group: group.value, unit: target)
            && is_the_terminals_choice(
              objective_id: objective.objective_id,
              creature_id: target.creature_id,
            )
          Error(Nil) -> False
        }
      }
      || {
        case objective_kind.checklist_target(objective.kind) {
          Ok(objective_kind.UnitOfSoldier(path_soldier_activate_id:)) ->
            objective.checklist
            && activates_creature(
              tables:,
              path_soldier_activate: path_soldier_activate_id,
              creature_id: target.creature_id,
            )
          Ok(objective_kind.UnitsOfGroup(_)) | Error(Nil) -> False
        }
      }
      || {
        !by_item
        && objective_kind.is_linked_use(objective.kind)
        && list.contains(
          objective_link.links(tables:, creature_id: target.creature_id),
          #(quest_id, index),
        )
      }
    Cast(spell4_id:, target:) ->
      objective_kind.cast_spell(objective.kind) == Ok(spell4_id)
      && case target {
        Some(CastTarget(unit:, ..)) -> in_pane(tables:, objective:, unit:)
        None -> True
      }
    Killed(target:) -> {
      let by_data = case objective_kind.placed_target(objective.kind) {
        Ok(objective_kind.OneCreature(creature2_id:)) ->
          creature2_id == target.creature_id
        Ok(objective_kind.GroupOf(target_group_id:)) ->
          target_group.contains(
            tables:,
            group: target_group_id.value,
            unit: target,
          )
        Error(Nil) -> False
      }
      by_data
      || {
        objective_kind.is_kill(objective.kind)
        && objective.reward_pane != 0
        && target_group.contains(
          tables:,
          group: objective.reward_pane,
          unit: target,
        )
      }
    }
  }
}

/// Whether the unit is in the objective's reward pane, which counts a unit for any
/// objective type (`0x140550c50`); an objective with no pane counts any unit (issue 724's
/// decision 2c).
fn in_pane(
  tables tables: table_store.Tables,
  objective objective: quest_log.Objective,
  unit unit: target_group.Unit,
) -> Bool {
  objective.reward_pane == 0
  || target_group.contains(tables:, group: objective.reward_pane, unit:)
}

/// The entry of the objective's named group the killed unit is, and how many creatures the
/// group lists: for a type 15 objective whose reward pane is a TargetGroup of Creature2 ids
/// (`TargetGroup.type.1`), the position of the unit's Creature2 id among the pane's
/// non-zero data words. `Error(Nil)` for any other objective or unit, which counts a pane
/// kill as one (`counts`).
fn group_member(
  tables tables: table_store.Tables,
  objective objective: quest_log.Objective,
  target target: target_group.Unit,
) -> Result(#(Int, Int), Nil) {
  use <- bool.guard(
    when: !objective_kind.kills_by_cluster(objective.kind)
      || objective.reward_pane == 0,
    return: Error(Nil),
  )
  let creatures =
    target_group.creatures_of(tables:, group: objective.reward_pane)
  use member <- result.map(
    list.index_map(creatures, fn(creature, at) { #(creature, at) })
    |> list.key_find(target.creature_id),
  )
  #(member, list.length(creatures))
}

/// Whether a use of the creature counts for a type 23 objective: the client counts a use of
/// any unit of the objective's group, and the server holds a departures choice objective to
/// its own terminal (`departures.choice_terminal`).
fn is_the_terminals_choice(
  objective_id objective_id: Int,
  creature_id creature_id: Creature2Id,
) -> Bool {
  case departures.choice_terminal(objective_id:) {
    None -> True
    Some(terminal) -> terminal == creature_id
  }
}

/// What the objectives of one quest have counted so far for one event: the log, the
/// progress effects in reverse order, whether the quest became Achieved, and whether any
/// objective counted a unit new to it.
type Pass {
  Pass(
    log: QuestLog,
    progress: List(Effect),
    became_achieved: Bool,
    credited_a_new_unit: Bool,
  )
}

/// One quest's objectives that are open and that the event counts for, each counted
/// once, and whether any of them counted a unit new to it. An Achieved quest still has its
/// objectives with flag 0x20 open.
///
/// ```
/// an objective the event counts for ─ a named kill group's member ─▶ kill_marked
///                                   ├ a checklist                ─▶ marked (the unit's bit)
///                                   ├ a unit, not in reused      ─▶ used (the unit's record)
///                                   └ no unit, or in reused      ─▶ one more, no record
/// ```
fn advance_quest(
  so_far so_far: Advanced,
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
  now_ms now_ms: Int,
  reused reused: Set(Int),
  counts counts: fn(Int, quest_log.Objective) -> Bool,
  group_member group_member: fn(quest_log.Objective) -> Result(#(Int, Int), Nil),
  checklist_index checklist_index: Int,
  used_unit used_unit: Result(quest_log.UnitRef, Nil),
) -> #(Advanced, Bool) {
  let named =
    quest_log.open_objectives(log: so_far.log, quest:)
    |> list.filter(fn(open) { counts(open.0, open.1) })
  let counted =
    list.fold(
      named,
      Pass(
        log: so_far.log,
        progress: [],
        became_achieved: False,
        credited_a_new_unit: False,
      ),
      fn(pass, open) {
        let #(index, objective) = open
        case group_member(objective), objective.checklist {
          Ok(#(member, members)), _ ->
            case
              quest_log.kill_marked(
                log: pass.log,
                quest:,
                index:,
                member:,
                members:,
              )
            {
              // A kill that leaves a member of the group alive, or kills one already
              // dead, tells nothing: the client's progress stays 0. The kill that
              // fills the group counts as a kill does.
              Ok(#(marked, True)) ->
                progressed_by_one(
                  pass: Pass(..pass, log: marked),
                  quest:,
                  index:,
                  now_ms:,
                )
              Ok(#(marked, False)) -> Pass(..pass, log: marked)
              // An open objective takes the kill, so this does not happen.
              Error(Nil) -> pass
            }
          Error(Nil), True ->
            case
              quest_log.marked(
                log: pass.log,
                quest:,
                index:,
                bit: checklist_index,
                now_ms:,
              )
            {
              // A unit whose bit is set counts for nothing and tells nothing.
              Ok(marked) if marked.changed ->
                counted_a_new_unit(pass:, quest:, index:, counted: marked)
              Ok(_) | Error(Nil) -> pass
            }
          Error(Nil), False ->
            case used_unit, set.contains(reused, objective.objective_id) {
              Ok(unit), False ->
                case
                  quest_log.used(log: pass.log, quest:, index:, unit:, now_ms:)
                {
                  // A unit this objective counted already counts for nothing and tells
                  // nothing.
                  Ok(used) if used.changed ->
                    counted_a_new_unit(pass:, quest:, index:, counted: used)
                  Ok(_) | Error(Nil) -> pass
                }
              // A kill, a talk, a cast aimed at the caster, and an objective whose unit
              // counts again, count one at each event with no record of the unit.
              Ok(_), True | Error(Nil), _ ->
                progressed_by_one(pass:, quest:, index:, now_ms:)
            }
        }
      },
    )
  let state = case counted.became_achieved {
    True -> achieved(tables:, quest_id: quest.id)
    False -> []
  }
  #(
    Advanced(
      log: counted.log,
      effects: list.flatten([
        so_far.effects,
        list.reverse(counted.progress),
        state,
      ]),
    ),
    counted.credited_a_new_unit,
  )
}

/// The pass after the objective at `index` counted a unit new to it (its `marked` or
/// `used` changed the log): the progress it sends and whether it made the quest Achieved.
fn counted_a_new_unit(
  pass pass: Pass,
  quest quest: quest_log.Quest,
  index index: Int,
  counted counted: quest_log.Counted,
) -> Pass {
  Pass(
    log: counted.log,
    progress: [
      SendProgress(
        quest_id: quest.id,
        objective_index: index,
        progress: counted.progress,
      ),
      ..pass.progress
    ],
    became_achieved: pass.became_achieved
      || counted.moved == quest_log.BecameAchieved,
    credited_a_new_unit: True,
  )
}

/// The pass after one more counted for the quest's objective at `index`, added to what the
/// quest's earlier objectives made; a count with no unit record credits no unit.
fn progressed_by_one(
  pass pass: Pass,
  quest quest: quest_log.Quest,
  index index: Int,
  now_ms now_ms: Int,
) -> Pass {
  case quest_log.progressed(log: pass.log, quest:, index:, amount: 1, now_ms:) {
    Ok(progressed) ->
      Pass(
        ..pass,
        log: progressed.log,
        progress: [
          SendProgress(
            quest_id: quest.id,
            objective_index: index,
            progress: progressed.progress,
          ),
          ..pass.progress
        ],
        became_achieved: pass.became_achieved || progressed.became_achieved,
      )
    // An open objective takes progress, so this does not happen.
    Error(Nil) -> pass
  }
}

/// Whether the PathSoldierActivate row is the activation of the creature.
fn activates_creature(
  tables tables: table_store.Tables,
  path_soldier_activate path_soldier_activate_id: PathSoldierActivateId,
  creature_id creature_id: Creature2Id,
) -> Bool {
  case path_soldier_activate.get(tables:, id: path_soldier_activate_id) {
    Ok(row) -> Creature2Id(row.creature2_id) == creature_id
    Error(Nil) -> False
  }
}

/// The log and the messages after what the player holds, the zones they stand in and
/// the place they stand at changed (`zones` is the player's zone and its parents, which
/// a visit names one of; empty when the player is nowhere yet, as at login; `shown` is
/// the units they are shown, none at login).
///
/// The client counts nothing for objective types 4, 33 and 17: it stores the value the
/// server sends and the objective is done once the value reaches its count
/// (`0x140575a80`, `0x14079d700`, `0x1406115a0`). So the server sets each type 4
/// objective to the number of its Item2 held in the locations the accept check counts
/// (`quest.held_count`), a type 33 objective to that of its schematic's output item,
/// and a type 17 objective to done while its zone is among `zones`. A count that falls
/// takes the done bit away, and an Achieved quest with an objective not done is Accepted
/// again. A held count is set whether or not its objective is reachable; a visit counts
/// only once it is open (`0x140553790`), so a visit that an earlier count opens counts
/// in the same pass. A quest at a time in id order, its progress messages in objective
/// order for each objective that changed, then one state message when the quest's state
/// is not what it was.
///
/// The client sends nothing for a type 22 objective (a place) and the position decides
/// (`place_objective`): an open one is done once the player's place is at one of its
/// markers by the client's arrival test (`0x140485fa0`), an optional one (flag 0x20) also
/// once the required type 22 objective of its quest that has the same data is done at a
/// marker the player is at, and a place-counted checklist counts, at each place reached,
/// the checklist index of the shown unit that stands there. A type 22 objective with a
/// count above 1 is left alone: nothing says how many visits it takes, and the server
/// does not count them (the issue "Place objectives with no marker or a count above one
/// complete (objective type 22)"). An objective such a pass opens is settled in the same
/// call.
///
/// The client sends nothing for a type 24 objective either (`QuestObjective.type.24`):
/// it is done once the quest its data names is finished (`quest_log.finished`, at
/// `unix_ms`, the Unix time in milliseconds, whose repeat periods `numbers` sets). The
/// objective counts when it is open, and an objective that this opens counts in the same
/// call. That a completion is what sets it is read from the objective's text and title,
/// not from client code (a gap in the fact's record; the issue "Quests, zones and
/// prerequisites work on the real client" closes it by recording quest 7540 live).
pub fn settle(
  log log: QuestLog,
  tables tables: table_store.Tables,
  items items: List(HeldItem),
  zones zones: List(Int),
  place place: Place,
  shown shown: shown.Picture,
  numbers numbers: GameNumbers,
  arrival_objectives arrival_objectives: Set(Int),
  held_objectives held_objectives: Set(Int),
  unix_ms unix_ms: Int,
  now_ms now_ms: Int,
) -> Advanced {
  list.fold(
    quest_log.active_ids(log:),
    Advanced(log:, effects: []),
    fn(so_far, quest_id) {
      let quest = quest_of(tables:, quest_id:)
      let before = quest_log.stored_state(log: so_far.log, quest_id:)
      let held =
        list.index_fold(
          quest.objectives,
          Settling(log: so_far.log, progress: []),
          fn(settling, objective, index) {
            case held_item(tables:, objective:) {
              Ok(item2_id) ->
                set_count(
                  settling:,
                  quest:,
                  index:,
                  value: quest_rules.held_count(items:, item2_id:),
                  now_ms:,
                )
              Error(Nil) -> settling
            }
          },
        )
      let settling =
        opened(
          settling: held,
          quest:,
          tables:,
          zones:,
          place:,
          shown:,
          numbers:,
          arrival_objectives:,
          held_objectives:,
          unix_ms:,
          now_ms:,
        )
      let after = quest_log.stored_state(log: settling.log, quest_id:)
      let state = case after != before {
        True -> [
          SendState(quest_id:, state: after),
          ..case after == achieved_state {
            True -> completion_of(tables:, quest_id:)
            False -> []
          }
        ]
        False -> []
      }
      Advanced(
        log: settling.log,
        effects: list.flatten([
          so_far.effects,
          list.reverse(settling.progress),
          state,
        ]),
      )
    },
  )
}

/// The visits, place objectives and finished-quest objectives that are done, again while
/// a pass counted anything, because a count can open the objective after it (a type 22
/// objective's flags, a later objective of the quest).
fn opened(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  tables tables: table_store.Tables,
  zones zones: List(Int),
  place place: Place,
  shown shown: shown.Picture,
  numbers numbers: GameNumbers,
  arrival_objectives arrival_objectives: Set(Int),
  held_objectives held_objectives: Set(Int),
  unix_ms unix_ms: Int,
  now_ms now_ms: Int,
) -> Settling {
  let next =
    visits(settling:, quest:, zones:, now_ms:)
    |> arrivals(
      quest:,
      tables:,
      place:,
      shown:,
      arrival_objectives:,
      held_objectives:,
      now_ms:,
    )
    |> finishes(quest:, tables:, numbers:, unix_ms:, now_ms:)
    |> stand_in_scripts(
      quest:,
      tables:,
      arrival_objectives:,
      held_objectives:,
      now_ms:,
    )
  case list.length(next.progress) > list.length(settling.progress) {
    True ->
      opened(
        settling: next,
        quest:,
        tables:,
        zones:,
        place:,
        shown:,
        numbers:,
        arrival_objectives:,
        held_objectives:,
        unix_ms:,
        now_ms:,
      )
    False -> next
  }
}

/// How the rules treat an objective of a quest, decided in one place so no objective falls
/// between two rules.
pub type Script {
  /// Not a type 5 objective: the stand-in and place rules leave it alone.
  NotScripted
  /// A creature's row links it, so a use of that creature counts it (`counts`).
  UsedByCreature
  /// Visible and optional (flag 0x20): the quest does not wait for it, and nothing here
  /// completes it.
  Optional
  /// Visible, required and marked, and a spell effect or an item names it
  /// (`objective_action.named`): it stays open until that cast counts for it.
  NamedAction
  /// Visible, required, marked and listed in the arrival table: done when the player
  /// stands at one of its markers.
  PlaceScript
  /// Visible, required and marked, and none of the above: done when it is open, whatever
  /// else the quest holds.
  StandInOnAccept
  /// Hidden, or visible, required and unmarked: done once every other required
  /// objective of the quest is.
  StandInWithQuest
}

/// The `Script` of the objective at `index` of the quest. A type 5 objective
/// (`QuestObjective.type.5`, done only by the server's 0x361) that a creature links is the
/// use rule's. Of the others, a hidden one (flag 8, `QuestObjective.flags.8`, which shows no
/// marker) waits for the quest, with its data whatever it is and optional or not; a visible
/// optional one (flag 0x20) is left alone because the quest's Achieved rule skips it
/// (`0x1405fbc40`). A visible required one without a marker waits for the quest (a
/// `worldLocationsIdIndicator` that names no WorldLocation2 row is no marker: no position is
/// at it, `0x140485fa0`); one with a marker sends the player to a place (`0x140553890`) and is
/// the named action's, a place script (`arrival_objectives`) or a stand-in on accept, in
/// that order. The held objectives are not looked at here: each rule leaves a held one open.
pub fn script_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_log.Objective,
  arrival_objectives arrival_objectives: Set(Int),
) -> Script {
  use <- bool.guard(objective.kind != objective_kind.Scripted, NotScripted)
  use <- bool.guard(
    objective_link.is_linked(tables:, quest_id:, index:),
    UsedByCreature,
  )
  use <- bool.guard(
    int.bitwise_and(objective.flags, hidden_flag) != 0,
    StandInWithQuest,
  )
  use <- bool.guard(
    int.bitwise_and(objective.flags, quest_log.optional_flag) != 0,
    Optional,
  )
  use <- bool.guard(!objective.marked, StandInWithQuest)
  use <- bool.guard(
    objective_action.named(tables:, quest_id:, index:),
    NamedAction,
  )
  case set.contains(arrival_objectives, objective.objective_id) {
    True -> PlaceScript
    False -> StandInOnAccept
  }
}

/// The quest's stand-in scripts (`script_of`), a held one left open:
/// - those that stand in on accept are done as soon as they are open
///   (`quest_log.objective_open`, so flags 1 and 2 keep one closed behind the objectives
///   before it), whatever the quest's other objectives are;
/// - those that stand in with the quest are done once every other required objective of
///   the quest is done except the stand-ins and the objectives the client keeps closed
///   until a script is done (`other_required_objectives_done`).
/// Such an objective is done by nothing the client or a player does, and the Achieved rule
/// (`0x1405fbc40`) waits for it, so the quest would stay Accepted for ever; this completion
/// is a server choice: a script the server can complete is completed, as a guess until a
/// real trigger replaces it. The quest is Achieved only when every required objective is
/// done, so a stand-in beside an open objective leaves the quest Accepted. A held
/// objective is not waited for, nor is another stand-in, so a quest with several completes
/// the free ones that are open together, and a quest with no other required objective
/// completes at once. A script the client keeps closed (`0x140553790`) behind an objective
/// that is not done stays open for a later settle, and a done objective is not counted
/// again.
fn stand_in_scripts(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  tables tables: table_store.Tables,
  arrival_objectives arrival_objectives: Set(Int),
  held_objectives held_objectives: Set(Int),
  now_ms now_ms: Int,
) -> Settling {
  let scripts =
    list.index_map(quest.objectives, fn(objective, index) {
      #(
        index,
        objective,
        script_of(
          tables:,
          quest_id: quest.id,
          index:,
          objective:,
          arrival_objectives:,
        ),
      )
    })
  let open_and_free = fn(settling: Settling, wanted: Script) {
    list.filter(scripts, fn(triple) {
      triple.2 == wanted
      && !set.contains(held_objectives, { triple.1 }.objective_id)
      && quest_log.objective_open(log: settling.log, quest:, index: triple.0)
    })
  }
  let on_accept =
    list.fold(
      open_and_free(settling, StandInOnAccept),
      settling,
      fn(settling, triple) {
        set_count(
          settling:,
          quest:,
          index: triple.0,
          value: { triple.1 }.count,
          now_ms:,
        )
      },
    )
  let waiting = open_and_free(on_accept, StandInWithQuest)
  case
    waiting != []
    && other_required_objectives_done(
      log: on_accept.log,
      quest:,
      scripts: list.filter_map(scripts, fn(triple) {
        case triple.2 {
          StandInOnAccept | StandInWithQuest -> Ok(triple.0)
          NotScripted | UsedByCreature | Optional | NamedAction | PlaceScript ->
            Error(Nil)
        }
      }),
    )
  {
    True ->
      list.fold(waiting, on_accept, fn(settling, triple) {
        set_count(
          settling:,
          quest:,
          index: triple.0,
          value: { triple.1 }.count,
          now_ms:,
        )
      })
    False -> on_accept
  }
}

/// The rules the objective at `index` of the quest breaks as a visible script a creature
/// does not link, none when it is one: type 5 (`QuestObjective.type.5`, done only by the
/// server's 0x361), flag 0x8 clear (else it is a hidden script), flag 0x20 clear (else the
/// quest does not wait for it), and no creature linking it (`objective_link.is_linked`). A
/// marker does not break it: a marked one is a place script, a stand-in on accept or the
/// named action's (`script_of`). Its data is not read: the server completes it whatever the
/// data, which no client rule gives it.
pub fn visible_script_broken(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_log.Objective,
) -> List(String) {
  list.flatten([
    case objective.kind == objective_kind.Scripted {
      True -> []
      False -> [
        "QuestObjective "
        <> int.to_string(objective.objective_id)
        <> " is of a type that is not 5 (a scripted objective)",
      ]
    },
    case int.bitwise_and(objective.flags, hidden_flag) != 0 {
      True -> ["flag 0x8 hides it, so it is a hidden script"]
      False -> []
    },
    case int.bitwise_and(objective.flags, quest_log.optional_flag) != 0 {
      True -> ["flag 0x20 makes it optional, so its quest does not wait for it"]
      False -> []
    },
    case objective_link.is_linked(tables:, quest_id:, index:) {
      True -> ["a creature links it, so that creature completes it"]
      False -> []
    },
  ])
}

/// Whether every required objective of the quest is done except the `scripts` and the
/// objectives the client keeps closed until a script is done: such an
/// objective is unreachable (`0x140553790`) while the script is not done, so waiting for
/// it would hold the script, and the quest, for ever.
fn other_required_objectives_done(
  log log: quest_log.QuestLog,
  quest quest: quest_log.Quest,
  scripts scripts: List(Int),
) -> Bool {
  let holding =
    list.filter(scripts, fn(index) {
      !quest_log.objective_done(log:, quest:, index:)
    })
  quest_log.required_objectives_done(
    log:,
    quest:,
    ignoring: list.append(
      scripts,
      quest_log.locked_behind(log:, quest:, holding:),
    ),
  )
}

/// Every open type 24 objective of the quest whose quest is finished done. A done
/// objective is not open, so it is not counted again.
fn finishes(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  tables tables: table_store.Tables,
  numbers numbers: GameNumbers,
  unix_ms unix_ms: Int,
  now_ms now_ms: Int,
) -> Settling {
  quest_log.open_objectives(log: settling.log, quest:)
  |> list.filter(fn(open) {
    let #(_, objective) = open
    case objective_kind.finished_quest(objective.kind) {
      Ok(quest2_id) ->
        quest_log.finished(
          log: settling.log,
          quest_id: quest2_id.value,
          tables:,
          numbers:,
          unix_ms:,
        )
      Error(Nil) -> False
    }
  })
  |> list.fold(settling, fn(settling, open) {
    set_count(
      settling:,
      quest:,
      index: open.0,
      value: { open.1 }.count,
      now_ms:,
    )
  })
}

/// The open place objectives of the quest that the place completes or counts, again
/// while a pass opened an objective that the place reaches too: the type 22 objectives at
/// a marker, the place scripts (`script_of`, a held one left open) at a marker, the
/// optional type 22 ones with their required sibling, and the place-counted checklists'
/// units. A done objective is not counted again, which ends the loop.
fn arrivals(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  tables tables: table_store.Tables,
  place place: Place,
  shown shown: shown.Picture,
  arrival_objectives arrival_objectives: Set(Int),
  held_objectives held_objectives: Set(Int),
  now_ms now_ms: Int,
) -> Settling {
  let at_markers =
    quest_log.open_objectives(log: settling.log, quest:)
    |> list.filter(fn(open) {
      let #(index, objective) = open
      {
        { is_place(objective:) && objective.count == 1 }
        || {
          script_of(
            tables:,
            quest_id: quest.id,
            index:,
            objective:,
            arrival_objectives:,
          )
          == PlaceScript
          && !set.contains(held_objectives, objective.objective_id)
        }
      }
      && place_objective.at_marker(
        tables:,
        objective_id: objective.objective_id,
        place:,
      )
    })
    |> list.fold(settling, fn(settling, open) {
      set_count(
        settling:,
        quest:,
        index: open.0,
        value: { open.1 }.count,
        now_ms:,
      )
    })
  let with_siblings =
    quest_log.open_objectives(log: at_markers.log, quest:)
    |> list.filter(fn(open) {
      let #(_, objective) = open
      is_place(objective:)
      && objective.count == 1
      && int.bitwise_and(objective.flags, quest_log.optional_flag) != 0
      && required_sibling_arrived(
        settling: at_markers,
        quest:,
        tables:,
        place:,
        optional: objective,
      )
    })
    |> list.fold(at_markers, fn(settling, open) {
      set_count(
        settling:,
        quest:,
        index: open.0,
        value: { open.1 }.count,
        now_ms:,
      )
    })
  let counted =
    quest_log.open_objectives(log: with_siblings.log, quest:)
    |> list.filter(fn(open) {
      result.is_ok(objective_kind.used_checklist_group({ open.1 }.kind))
    })
    |> list.fold(with_siblings, fn(settling, open) {
      place_objective.indexes_counted(
        tables:,
        objective_id: { open.1 }.objective_id,
        place:,
        shown:,
        now_ms:,
      )
      |> list.fold(settling, fn(settling, bit) {
        mark(settling:, quest:, index: open.0, bit:, now_ms:)
      })
    })
  case list.length(counted.progress) > list.length(settling.progress) {
    True ->
      arrivals(
        settling: counted,
        quest:,
        tables:,
        place:,
        shown:,
        arrival_objectives:,
        held_objectives:,
        now_ms:,
      )
    False -> counted
  }
}

/// Whether the held objective is one of a place (type 22).
fn is_place(objective objective: quest_log.Objective) -> Bool {
  objective.kind == objective_kind.ReachPlace
}

/// Whether a required type 22 objective of the quest with the optional one's non-zero
/// data is done and its marker is where the player is. The optional objectives of the
/// tutorial's places (rotate the camera, follow the arrow, double-jump) hint at what a
/// position cannot show, and share the data, one server trigger, of the required
/// objective they hint at (`QuestObjective.type.22`).
fn required_sibling_arrived(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  tables tables: table_store.Tables,
  place place: Place,
  optional optional: quest_log.Objective,
) -> Bool {
  optional.data != 0
  && list.index_map(quest.objectives, fn(objective, index) {
    #(index, objective)
  })
  |> list.any(fn(sibling) {
    let #(index, objective) = sibling
    is_place(objective:)
    && objective.data == optional.data
    && int.bitwise_and(objective.flags, quest_log.optional_flag) == 0
    && quest_log.objective_progress(log: settling.log, quest:, index:)
    >= objective.count
    && place_objective.at_marker(
      tables:,
      objective_id: objective.objective_id,
      place:,
    )
  })
}

/// The bit of a checklist objective set, with its progress message when the bit was
/// not set. An objective that is not open takes nothing.
fn mark(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  index index: Int,
  bit bit: Int,
  now_ms now_ms: Int,
) -> Settling {
  case quest_log.marked(log: settling.log, quest:, index:, bit:, now_ms:) {
    Ok(marked) if marked.changed ->
      Settling(log: marked.log, progress: [
        SendProgress(
          quest_id: quest.id,
          objective_index: index,
          progress: marked.progress,
        ),
        ..settling.progress
      ])
    Ok(_) | Error(Nil) -> settling
  }
}

/// A quest's log while it is settled and the progress messages so far, latest first.
type Settling {
  Settling(log: QuestLog, progress: List(Effect))
}

/// The Item2 whose held count a type 4 or type 33 objective takes as its progress, or
/// `Error(Nil)` for an objective of another type. A type 33 objective's schematic is a
/// row of the table (the tables test checks every one a quest names), so a missing row
/// ends the process.
fn held_item(
  tables tables: table_store.Tables,
  objective objective: quest_log.Objective,
) -> Result(Item2Id, Nil) {
  case
    objective_kind.collected_item(objective.kind),
    objective_kind.crafted_schematic(objective.kind)
  {
    Ok(item2_id), _ -> Ok(item2_id)
    Error(Nil), Ok(schematic_id) -> {
      let assert Ok(schematic) =
        tradeskill_schematic2.get(tables:, id: schematic_id)
        as "a type 33 objective names a TradeskillSchematic2 row"
      Ok(tradeskill_schematic2.item2_id_output(schematic))
    }
    Error(Nil), Error(Nil) -> Error(Nil)
  }
}

/// The objective at `index` set to `value`, with its progress message when its progress
/// changed. Only a quest in the active list is settled and `index` is one of its
/// objectives, so the count is always taken.
fn set_count(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  index index: Int,
  value value: Int,
  now_ms now_ms: Int,
) -> Settling {
  let assert Ok(counted) =
    quest_log.counted(log: settling.log, quest:, index:, value:, now_ms:)
    as "a settled quest is in the active list and the index is one of its objectives"
  Settling(log: counted.log, progress: case counted.changed {
    True -> [
      SendProgress(
        quest_id: quest.id,
        objective_index: index,
        progress: counted.progress,
      ),
      ..settling.progress
    ]
    False -> settling.progress
  })
}

/// Every open visit of the quest whose zone is among `zones` done, again while a visit
/// that the last one opened is not (`0x140553790`). Data 0 names no zone, though the
/// chain of zone 0 holds it. A done visit is not counted again, which ends the loop.
fn visits(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  zones zones: List(Int),
  now_ms now_ms: Int,
) -> Settling {
  let waiting =
    quest_log.open_objectives(log: settling.log, quest:)
    |> list.filter(fn(open) {
      let #(index, objective) = open
      case objective_kind.visited_zone(objective.kind) {
        Ok(zone) ->
          zone.value != 0
          && list.contains(zones, zone.value)
          && quest_log.objective_progress(log: settling.log, quest:, index:)
          < objective.count
        Error(Nil) -> False
      }
    })
  case waiting {
    [] -> settling
    _ ->
      list.fold(waiting, settling, fn(settling, open) {
        set_count(
          settling:,
          quest:,
          index: open.0,
          value: { open.1 }.count,
          now_ms:,
        )
      })
      |> visits(quest:, zones:, now_ms:)
  }
}

/// What follows the progress that made the quest Achieved: its state 2 (0x35c) and, for a quest
/// no creature receives, the server's completion (`completion_of`).
pub fn achieved(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> List(Effect) {
  [
    SendState(quest_id:, state: achieved_state),
    ..completion_of(tables:, quest_id:)
  ]
}

/// The server's completion of the quest, when no creature receives it and the client's
/// turn-in does not take it (`communicator.completed_by_server`): the effect that follows
/// the 0x35c that makes it Achieved.
fn completion_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> List(Effect) {
  let assert Ok(row) = quest2.get(tables:, id: Quest2Id(quest_id))
    as {
      "quest "
      <> int.to_string(quest_id)
      <> " of the log has a Quest2 row (the load fails without one)"
    }
  case communicator.completed_by_server(tables:, quest: row) {
    True -> [CompleteByServer(quest_id:)]
    False -> []
  }
}

/// The quests of the log that are Achieved and that the server completes, in quest id
/// order: what a login or an entry owes the player when the log already holds them.
pub fn server_completions(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> List(Int) {
  quest_log.active_ids(log:)
  |> list.filter(fn(quest_id) {
    quest_log.stored_state(log:, quest_id:) == achieved_state
    && completion_of(tables:, quest_id:) != []
  })
}

/// The messages the effects tell the client, in the effects' order: each progress as
/// 0x361 and each state as 0x35c. A completion by the server and a release send nothing.
pub fn frames(effects effects: List(Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      SendProgress(quest_id:, objective_index:, progress:) ->
        Ok(quest_log.quest_objective_progress_frame(
          quest_id:,
          objective_index:,
          progress:,
        ))
      SendState(quest_id:, state:) ->
        Ok(quest_log.quest_state_frame(quest_id:, state:, objective_id: 0))
      CompleteByServer(..) | ReleaseUnit(..) -> Error(Nil)
    }
  })
}
