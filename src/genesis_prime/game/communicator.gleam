//// Whether the communicator may turn a quest in: the client's dialog opened with no unit
//// (`AnswerCommunicatorQuest` `0x14043c700`, then `OpenCommunicatorDialog`, then
//// `QuestGivesReceiverResponse` `0x140553030`), which offers the turn-in of an Achieved
//// quest exactly when the player could press it, so the server accepts 0x035D with its
//// by-communicator bit set on the same terms.
////
//// ```
//// quest, asker ─▶ turn_in ─┬─ flags 0x10000: a receiver exists and a CommunicatorMessages row
//// (quest in the log)       │                 that delivers it passes `0x14043d3d0`
////                          ├─ flags 8:       some receiver's faction is not Hostile to the
////                          │                 player's current faction
////                          └─ neither:       NotCommunicable
//// ```
////
//// - **Flag 0x10000 decides alone** (`0x140553030`): the quest's flag 8 does not rescue a quest
////   no row delivers, and no receiver faction is read.
//// - **A row** is read as `0x14043d3d0` reads it, each condition with the code it returns:
////   2 World, 3 zone (the player's zone or a parent above it), 5 class, 6 race, 7 base
////   faction, 8 reputation, 10 level above the maximum, 9 level below the minimum, 0xb the
////   three quest states (`quest_state_holds`), 0xc the prerequisite, then the row's creature
////   (`0x14043d650`): 0xf the quest lacks flag 0x10000, 0x10 the creature does not receive it,
////   0x11 the quest is Accepted. Code 0xd (the row is already queued to ring) is the client's
////   own queue and is taken as passing; code 0xe is the client's own test and is not read.
////   A row with flags bit 0 set is not read
////   (`0x14043d1f0` mode 1).
//// - **Reputation is not read**: the server keeps none (#674). A row that
////   reaches the condition is reported as unread, never as passing or failing.
//// - **Built once**, when the tables load (genesis_prime/table/loader/derivation): the rows of
////   each quest they deliver (`0x14043add0`'s index by questIdDelivered) and the creatures that
////   receive each quest.
//// - **A quest nobody can turn in** (`completed_by_server`): no receiver, no flag 0x10000 and
////   no flag 0x80000. The client offers its player no turn-in, so the server completes it.

import genesis_prime/game/faction_level
import genesis_prime/game/quest
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/table/communicator_messages.{type CommunicatorMessages}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Quest2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/world_map/spawn
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// What a row needs that the server does not read.
pub type Gap {
  /// The row's reputation condition (factionIdReputation of a row).
  ReputationCondition(row_id: Int, faction_id: Int)
  /// The row's prerequisite has a condition the server does not read.
  PrerequisiteCondition(row_id: Int, gap: quest.Gap)
}

/// Why the communicator does not turn the quest in.
pub type Refusal {
  /// The quest has neither flag 8 nor flag 0x10000, or is not in the player's log.
  NotCommunicable
  /// Flag 0x10000 and no row that delivers the quest passes: each row read as delivering
  /// and the code `0x14043d3d0` returns for it.
  NoDeliveringRow(failed: List(#(Int, Int)))
  /// Every creature that receives the quest is Hostile to the player's current faction,
  /// or none receives it.
  NoOpenReceiver
  /// A row's condition the server does not read.
  Unread(gap: Gap)
  /// A table row the row's prerequisite needs cannot be loaded.
  Broken(error: quest.CheckError)
}

/// The Quest2 flag of a quest the communicator turns in by a row.
const by_row_flag = 0x10000

/// The Quest2 flag of a quest the communicator turns in for a receiver of any faction but
/// a Hostile one.
const by_receiver_flag = 8

/// The CommunicatorMessages flag bit that keeps a row from delivering (`0x14043d1f0`).
const not_delivering_flag = 1

/// The rows of each quest they deliver and the receivers of each quest.
type Communicator {
  Communicator(
    deliveries: Dict(Int, List(CommunicatorMessages)),
    receivers: Dict(Int, List(#(Int, Int))),
  )
}

/// The key of the communicator's index in the tables' store.
const communicator_key: table_store.DerivedKey(Communicator) =
  table_store.DerivedKey("CommunicatorDeliveries")

/// The index as a value the tables' load builds once, under the tables' key.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: communicator_key, build: fn(tables) {
    Ok(build(tables:))
  })
}

fn build(tables tables: table_store.Tables) -> Communicator {
  let rows =
    communicator_messages.all(tables)
    |> list.filter(fn(row) { row.quest_id_delivered != 0 })
    |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
  let creatures =
    creature2.all(tables)
    |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
  Communicator(
    deliveries: list.group(rows, fn(row) { row.quest_id_delivered })
      |> in_order,
    receivers: creatures
      |> list.flat_map(fn(creature) {
        spawn.received_quest_ids(creature)
        |> list.filter(fn(quest_id) { quest_id != 0 })
        |> list.unique
        |> list.map(fn(quest_id) {
          #(quest_id, #(creature.id, creature.faction_id))
        })
      })
      |> list.group(fn(pair) { pair.0 })
      |> in_order
      |> dict.map_values(fn(_, pairs) { list.map(pairs, fn(pair) { pair.1 }) }),
  )
}

/// The groups of `list.group`, each in the order of the list it was made from (the
/// library lists each group last to first).
fn in_order(groups: Dict(key, List(member))) -> Dict(key, List(member)) {
  dict.map_values(groups, fn(_, members) { list.reverse(members) })
}

fn of(tables tables: table_store.Tables) -> Communicator {
  table_store.derived(tables:, key: communicator_key)
}

/// The ids of the CommunicatorMessages rows whose questIdDelivered is the quest, whatever
/// their flags, in id order.
pub fn delivering_row_ids(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> List(Int) {
  delivering_rows(tables:, quest_id:) |> list.map(fn(row) { row.id })
}

fn delivering_rows(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> List(CommunicatorMessages) {
  dict.get(of(tables:).deliveries, quest_id) |> result.unwrap([])
}

/// The creatures whose questIdReceive00 to 24 name the quest, each with its factionId, in
/// creature id order.
pub fn receivers_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> List(#(Int, Int)) {
  dict.get(of(tables:).receivers, quest_id) |> result.unwrap([])
}

/// Whether the log's state for a quest is the one a row wants of it (`0x14043d870`): a
/// quest 0 passes, a quest the client has no record of fails, a held state of 5 to 7
/// reads as 0, and for a quest in the active list 5 to 10 is objective (wanted - 5) done
/// and 0xe to 0x13 objective (wanted - 0xe) not done; otherwise 0xb is held 0 or 4 (or 3
/// of a quest that repeats), 0xc is held 1 or 2, 0xd is held 2 or 3, and any other state
/// must be the held one.
pub fn quest_state_holds(
  log log: QuestLog,
  quest_id quest_id: Int,
  wanted wanted: Int,
  tables tables: table_store.Tables,
) -> Bool {
  use <- bool.guard(when: quest_id == 0, return: True)
  // A quest with no Quest2 row, or one the client's quest reader refuses, has no record
  // in the client (FindQuestById gives none), so its state is never the wanted one.
  case
    quest_log.quest_of(tables:, id: quest_id),
    quest2.get(tables:, id: Quest2Id(quest_id))
  {
    Ok(known), Ok(row) -> state_holds(log:, known:, row:, wanted:)
    _, _ -> False
  }
}

fn state_holds(
  log log: QuestLog,
  known known: quest_log.Quest,
  row row: Quest2,
  wanted wanted: Int,
) -> Bool {
  let state = quest_log.state(log:, quest: known)
  let held = case state >= 5 && state <= 7 {
    True -> 0
    False -> state
  }
  let active = list.contains(quest_log.active_ids(log:), known.id)
  let repeats = quest.takes_again(quest: row)
  case wanted {
    _ if active && wanted >= 5 && wanted <= 10 ->
      quest_log.objective_done(log:, quest: known, index: wanted - 5)
    _ if active && wanted >= 0xe && wanted <= 0x13 ->
      !quest_log.objective_done(log:, quest: known, index: wanted - 0xe)
    0xb -> held == 0 || held == 4 || { held == 3 && repeats }
    0xc -> held == 1 || held == 2
    0xd -> held == 2 || held == 3
    _ -> held == wanted
  }
}

/// What the client's reading of one row gives.
type Verdict {
  /// Every condition holds (`0x14043d3d0` returns 0).
  Holds
  /// A condition fails, with the code the client returns.
  Fails(code: Int)
  /// A condition the server does not read.
  NotRead(gap: Gap)
  /// A table row a condition needs cannot be loaded.
  Unloadable(error: quest.CheckError)
}

/// Whether the communicator turns a quest the player holds in. The quest must be in the
/// player's active list: the turn-in's state check comes first, and a quest outside the
/// list is not one the communicator turns in.
pub fn turn_in(
  quest subject: Quest2,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
) -> Result(Nil, Refusal) {
  let held = list.contains(quest_log.active_ids(log: asker.log), subject.id)
  let by_row = int.bitwise_and(subject.flags, by_row_flag) != 0
  let by_receiver = int.bitwise_and(subject.flags, by_receiver_flag) != 0
  let receivers = receivers_of(tables:, quest_id: subject.id)
  use <- bool.guard(
    when: !held || { !by_row && !by_receiver },
    return: Error(NotCommunicable),
  )
  case by_row {
    True -> by_a_row(quest: subject, asker:, tables:, receivers:)
    False -> by_a_receiver(asker:, tables:, receivers:)
  }
}

/// Flag 8 alone: some receiver has a faction that is not Hostile to the player's current
/// faction (`0x14043c700`).
fn by_a_receiver(
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
  receivers receivers: List(#(Int, Int)),
) -> Result(Nil, Refusal) {
  let levels = faction_level.of(tables:)
  case
    list.any(receivers, fn(receiver) {
      !faction_level.hostile(
        levels:,
        from: asker.factions.current,
        to: receiver.1,
      )
    })
  {
    True -> Ok(Nil)
    False -> Error(NoOpenReceiver)
  }
}

/// Flag 0x10000: the quest has a receiver and some row that delivers it, with flags bit 0
/// clear, passes.
fn by_a_row(
  quest subject: Quest2,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
  receivers receivers: List(#(Int, Int)),
) -> Result(Nil, Refusal) {
  use <- bool.guard(when: receivers == [], return: Error(NoOpenReceiver))
  let verdicts =
    delivering_rows(tables:, quest_id: subject.id)
    |> list.filter(fn(row) {
      int.bitwise_and(row.flags, not_delivering_flag) == 0
    })
    |> list.map(fn(row) {
      #(row.id, verdict(row:, quest: subject, asker:, tables:, receivers:))
    })
  case list.any(verdicts, fn(pair) { pair.1 == Holds }) {
    True -> Ok(Nil)
    False ->
      case list.find_map(verdicts, unread) {
        Ok(refusal) -> Error(refusal)
        Error(Nil) ->
          Error(
            NoDeliveringRow(
              failed: list.filter_map(verdicts, fn(pair) {
                case pair.1 {
                  Fails(code:) -> Ok(#(pair.0, code))
                  Holds | NotRead(..) | Unloadable(..) -> Error(Nil)
                }
              }),
            ),
          )
      }
  }
}

fn unread(pair: #(Int, Verdict)) -> Result(Refusal, Nil) {
  case pair.1 {
    NotRead(gap:) -> Ok(Unread(gap:))
    Unloadable(error:) -> Ok(Broken(error:))
    Holds | Fails(..) -> Error(Nil)
  }
}

/// One row against the player, in the order of `0x14043d3d0`: the first condition that does
/// not hold decides.
fn verdict(
  row row: CommunicatorMessages,
  quest subject: Quest2,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
  receivers receivers: List(#(Int, Int)),
) -> Verdict {
  let player = asker.player
  let unset_or = fn(column, holds) { column == 0 || holds }
  let states = [
    #(row.quest00, row.state00),
    #(row.quest01, row.state01),
    #(row.quest02, row.state02),
  ]
  let checks = [
    #(2, unset_or(row.world_id, row.world_id == player.world_id)),
    #(
      3,
      unset_or(
        row.world_zone_id,
        list.contains(player.zones, row.world_zone_id),
      ),
    ),
    #(5, unset_or(row.class_id, row.class_id == player.class_id)),
    #(6, unset_or(row.race_id, row.race_id == player.race_id)),
    #(7, unset_or(row.faction_id, row.faction_id == asker.factions.base)),
  ]
  let level_checks = [
    #(10, unset_or(row.max_level, player.level <= row.max_level)),
    #(9, unset_or(row.min_level, player.level >= row.min_level)),
    #(
      0xb,
      list.all(states, fn(pair) {
        quest_state_holds(
          log: asker.log,
          quest_id: pair.0,
          wanted: pair.1,
          tables:,
        )
      }),
    ),
  ]
  case first_failed(checks) {
    Ok(code) -> Fails(code:)
    Error(Nil) ->
      case row.faction_id_reputation != 0 {
        True ->
          NotRead(ReputationCondition(
            row_id: row.id,
            faction_id: row.faction_id_reputation,
          ))
        False ->
          case first_failed(level_checks) {
            Ok(code) -> Fails(code:)
            Error(Nil) ->
              prerequisite_then_creature(
                row:,
                quest: subject,
                asker:,
                tables:,
                receivers:,
              )
          }
      }
  }
}

/// The code of the first check that does not hold.
fn first_failed(checks: List(#(Int, Bool))) -> Result(Int, Nil) {
  list.find_map(checks, fn(check) {
    case check.1 {
      True -> Error(Nil)
      False -> Ok(check.0)
    }
  })
}

/// The row's prerequisite (0xc), then its creature (`0x14043d650`).
fn prerequisite_then_creature(
  row row: CommunicatorMessages,
  quest subject: Quest2,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
  receivers receivers: List(#(Int, Int)),
) -> Verdict {
  case
    quest.prerequisite_holds(
      tables:,
      prerequisite_id: row.prerequisite_id,
      asker:,
    )
  {
    Error(quest.PrerequisiteUnmet) -> Fails(code: 0xc)
    Error(quest.PrerequisiteUnread(gap:)) ->
      NotRead(PrerequisiteCondition(row_id: row.id, gap:))
    Error(quest.PrerequisiteBroken(error:)) -> Unloadable(error:)
    Ok(Nil) -> creature(row:, quest: subject, asker:, tables:, receivers:)
  }
}

/// `0x14043d650` for a quest in the log: it needs flag 0x10000 (0xf), the row's creature
/// among its receivers (0x10), and is not Accepted (0x11).
fn creature(
  row row: CommunicatorMessages,
  quest subject: Quest2,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
  receivers receivers: List(#(Int, Int)),
) -> Verdict {
  let assert Ok(known) = quest_log.quest_of(tables:, id: subject.id)
    as "a quest the turn-in checked has rows the client's reader accepts"
  case
    int.bitwise_and(subject.flags, by_row_flag) == 0,
    list.any(receivers, fn(receiver) { receiver.0 == row.creature_id }),
    quest_log.state(log: asker.log, quest: known) == 1
  {
    True, _, _ -> Fails(code: 0xf)
    False, False, _ -> Fails(code: 0x10)
    False, True, True -> Fails(code: 0x11)
    False, True, False -> Holds
  }
}

/// The log key of a refusal, one per kind, so each kind's first line is a warning.
pub fn key(refusal refusal: Refusal) -> String {
  case refusal {
    NotCommunicable -> "communicator: not communicable"
    NoDeliveringRow(..) -> "communicator: no delivering row"
    NoOpenReceiver -> "communicator: no open receiver"
    Unread(..) -> "communicator: unread condition"
    Broken(..) -> "communicator: unreadable row"
  }
}

/// A sentence that says why the communicator does not turn the quest in, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotCommunicable ->
      "which the communicator does not turn in: the quest has neither flag 8 nor flag 0x10000, or is not in the log"
    NoDeliveringRow(failed:) ->
      "whose flag 0x10000 needs a CommunicatorMessages row that delivers it, and none does"
      <> case failed {
        [] -> " (no row names it)"
        _ ->
          " (row, code: "
          <> string.join(
            list.map(failed, fn(pair) {
              int.to_string(pair.0) <> " " <> int.to_string(pair.1)
            }),
            ", ",
          )
          <> ")"
      }
    NoOpenReceiver ->
      "whose receivers are all Hostile to the player's faction, or which has none"
    Unread(gap: ReputationCondition(row_id:, faction_id:)) ->
      "whose delivering CommunicatorMessages row "
      <> int.to_string(row_id)
      <> " needs the player's reputation with faction "
      <> int.to_string(faction_id)
      <> ", which the server does not hold (#674)"
    Unread(gap: PrerequisiteCondition(row_id:, gap:)) ->
      "whose delivering CommunicatorMessages row "
      <> int.to_string(row_id)
      <> " needs "
      <> quest.describe_gap(gap:)
    Broken(error:) ->
      "whose delivering row's checks cannot be read: " <> quest.describe(error:)
  }
}

/// Whether the server completes the quest itself once it is Achieved: no creature
/// receives it (no Creature2 row's questIdReceive names it), the communicator does not turn
/// it in by a row (flag 0x10000), and it is no contract (flag 0x80000, whose completion is
/// the contract's own). The client shows such a quest no turn-in at all, so without the
/// server's completion it stays Achieved for ever.
pub fn completed_by_server(
  tables tables: table_store.Tables,
  quest quest: Quest2,
) -> Bool {
  receivers_of(tables:, quest_id: quest.id) == []
  && int.bitwise_and(quest.flags, by_row_flag) == 0
  && int.bitwise_and(quest.flags, quest.contract_flag) == 0
}
