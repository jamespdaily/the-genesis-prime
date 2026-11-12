//// The tutorial quests no creature gives: which one a character is due next, and the
//// rows of the `tutorial_quest` content table the load refuses. No client table or code
//// starts a quest with no giver; the server adds one with 0x35c {quest, 1, 0}, which the
//// client takes with no dialog and no CanAcceptQuest check (`opcode.0x35c.add_unaccepted`).
//// No table links the four quests of a faction either: their order is the objectives' own
//// text, so the chain is the server's choice, stated by the content table's reasons.
////
//// ```
//// content.load: rows ─▶ select(rows, tables) ─▶ Chain | refusals (the load stops)
//// play entry, world 3460 ─▶ after 0x35F ─▶ grant(chain, log, faction) ─▶ [0x35c {q,1,0}] | []
//// the server completes q ─▶ after 0x35c {q,3,0} ─▶ grant(chain, log, faction)  ─▶ [0x35c {next,1,0}] | []
////
//// due(log): the first quest of the faction's chain the log holds no entry of, if its
////   predecessor is none or is Completed
////   Exile    10513 ─▶ 10527 ─▶ 10518 ─▶ 10529        (questPlayerFactionEnum 0)
////   Dominion 10521 ─▶ 10532 ─▶ 10524 ─▶ 10533        (questPlayerFactionEnum 1)
//// ```
////
//// - **One rule for both triggers.** A relog at any point gives the one missing quest and
////   never a second copy: a quest the log holds in any state is not due again, and the next
////   waits for its predecessor to be Completed.
//// - **Only a chain quest gives a next one.** The completion of any other quest asks
////   `is_chain_quest` first, since `due` of a log with no tutorial quest is the first one.
//// - **The grant is an accept with no checks** (`quest_log.accept`), as the client runs
////   none for 0x35c state 1; the connection then settles the log as for an accept, so an
////   objective the player already meets counts.
//// - **The chain's faction** is the Quest2 row's questPlayerFactionEnum: 0 Exile only, 1
////   Dominion only. A character of neither faction crashes (`shown.faction_of`).
////
//// What happens at each failure point:
////
//// | Point | What happens |
//// |---|---|
//// | a row has no Quest2 row, or one of its objectives has no row | the load stops, naming the row |
//// | a creature gives or receives a row's quest | the load stops, naming the row and the creature |
//// | a row's quest is for neither faction enum 0 nor 1 | the load stops, naming the row |
//// | a faction enum has no start, or more than one | the load stops, naming the start rows (every row when none) |
//// | a row is not reached from its faction's start (a cycle, a missing predecessor, a branch) | the load stops, naming the row |
//// | the connection ends after a grant, before the save | the next entry in World 3460 grants it again |
//// | the save holds a completion but not the next grant | the next entry in World 3460 grants it |
//// | a character of neither faction | crash |

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/game/communicator
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/shown
import genesis_prime/table/creature2
import genesis_prime/table/id.{Quest2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/world_map/spawn
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The table's name in the log and in a refusal.
pub const table = "tutorial_quest"

/// The world of the training simulation (World 3460, Map\NewPlayerExperience; fact
/// `World.3460`), where a new character starts and the tutorial quests are given.
pub const training_world = 3460

/// One row of the tutorial_quest table as the load reads it: a quest and the quest
/// it follows, none for the first of its faction.
pub type Row {
  Row(quest_id: Int, follows_quest_id: Option(Int))
}

/// The rows of each faction enum (Quest2 questPlayerFactionEnum), in the order the
/// chain gives them.
pub opaque type Chain {
  Chain(by_faction: Dict(Int, List(Row)))
}

/// A quest the server has given: the log that holds it and the 0x35c that tells the
/// client.
pub type Granted {
  Granted(log: QuestLog, frame: Frame)
}

/// The chain the rows make, or every row the load refuses.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Chain, List(Refusal)) {
  let givers = givers_of(tables:)
  let #(checked, refusals) =
    list.fold(rows, #([], []), fn(done, row) {
      case row_refusal(row:, tables:, givers:) {
        Ok(#(faction_enum, [])) -> #([#(faction_enum, row), ..done.0], done.1)
        Ok(#(_, broken)) -> #(done.0, [refused(row:, broken:), ..done.1])
        Error(broken) -> #(done.0, [refused(row:, broken:), ..done.1])
      }
    })
  case refusals {
    [_, ..] -> Error(list.reverse(refusals))
    [] -> chained(checked: list.reverse(checked))
  }
}

/// The chain of the rows each row check passed, each with its faction enum, or the
/// refusals of each faction whose rows are not one chain from one start.
fn chained(checked checked: List(#(Int, Row))) -> Result(Chain, List(Refusal)) {
  let ordered =
    list.map([0, 1], fn(faction_enum) {
      #(
        faction_enum,
        in_order(faction_enum:, rows: list.key_filter(checked, faction_enum)),
      )
    })
  case list.flat_map(ordered, fn(pair) { pair.1.1 }) {
    [] -> Ok(Chain(by_faction: dict.from_list(list.map(ordered, with_rows))))
    refusals -> Error(refusals)
  }
}

fn with_rows(pair: #(Int, #(List(Row), List(Refusal)))) -> #(Int, List(Row)) {
  #(pair.0, pair.1.0)
}

fn refused(row row: Row, broken broken: List(String)) -> Refusal {
  Refusal(table:, row: RowId(row.quest_id), rule: string.join(broken, "; "))
}

/// The quests a creature gives, each with the first creature that gives it.
fn givers_of(tables tables: table_store.Tables) -> Dict(Int, Int) {
  creature2.all(tables)
  |> list.sort(fn(a, b) { int.compare(b.id, a.id) })
  |> list.fold(dict.new(), fn(givers, creature) {
    list.fold(spawn.given_quest_ids(creature), givers, fn(givers, quest_id) {
      dict.insert(givers, quest_id, creature.id)
    })
  })
}

/// The rule a row breaks by itself: `Error` when its Quest2 row cannot be read, else its
/// faction enum and the rules broken, none when the row is sound.
fn row_refusal(
  row row: Row,
  tables tables: table_store.Tables,
  givers givers: Dict(Int, Int),
) -> Result(#(Int, List(String)), List(String)) {
  let quest_id = row.quest_id
  use _ <- result.try(
    quest_log.quest_of(tables:, id: quest_id)
    |> result.map_error(fn(error) {
      case error {
        quest_log.NoQuestRow -> [
          "the client's Quest2 table has no row " <> int.to_string(quest_id),
        ]
        quest_log.NoObjectiveRow(objective_id:) -> [
          "Quest2 row "
          <> int.to_string(quest_id)
          <> " names QuestObjective "
          <> int.to_string(objective_id)
          <> ", which the client's table lacks",
        ]
      }
    }),
  )
  let assert Ok(quest) = quest2.get(tables:, id: Quest2Id(quest_id))
    as "quest_of found the row"
  let faction_enum = quest.quest_player_faction_enum
  let broken =
    list.flatten([
      case dict.get(givers, quest_id) {
        Ok(creature_id) -> [
          "Creature2 "
          <> int.to_string(creature_id)
          <> " gives the quest, so a dialog starts it",
        ]
        Error(Nil) -> []
      },
      case communicator.receivers_of(tables:, quest_id:) {
        [#(creature_id, _), ..] -> [
          "Creature2 "
          <> int.to_string(creature_id)
          <> " receives the quest, so it is not completed by the server",
        ]
        [] -> []
      },
      case faction_enum {
        0 | 1 -> []
        _ -> [
          "Quest2 questPlayerFactionEnum is "
          <> int.to_string(faction_enum)
          <> ", neither 0 (Exile) nor 1 (Dominion)",
        ]
      },
    ])
  Ok(#(faction_enum, broken))
}

/// The rows of one faction enum in the order the chain gives them, or the refusals: a
/// faction with rows needs exactly one start, and every row must be reached from it by
/// following each row's predecessor.
fn in_order(
  faction_enum faction_enum: Int,
  rows rows: List(Row),
) -> #(List(Row), List(Refusal)) {
  let starts = list.filter(rows, fn(row) { row.follows_quest_id == None })
  case rows, starts {
    [], _ -> #([], [])
    _, [start] -> {
      let walked = walk(rows:, from: start)
      let unreached = list.filter(rows, fn(row) { !list.contains(walked, row) })
      #(
        walked,
        list.map(unreached, fn(row) {
          Refusal(
            table:,
            row: RowId(row.quest_id),
            rule: "no chain of followers from the start "
              <> int.to_string(start.quest_id)
              <> " of faction enum "
              <> int.to_string(faction_enum)
              <> " reaches it: a cycle, a missing predecessor or a second row after one quest",
          )
        }),
      )
    }
    _, [] -> #(
      [],
      list.map(rows, fn(row) {
        Refusal(
          table:,
          row: RowId(row.quest_id),
          rule: "faction enum "
            <> int.to_string(faction_enum)
            <> " has no start, a row that follows no quest",
        )
      }),
    )
    _, _ -> #(
      [],
      list.map(starts, fn(row) {
        Refusal(
          table:,
          row: RowId(row.quest_id),
          rule: "faction enum "
            <> int.to_string(faction_enum)
            <> " has "
            <> int.to_string(list.length(starts))
            <> " starts, rows that follow no quest, and needs one",
        )
      }),
    )
  }
}

/// The start and each row that follows the one before, until none or more than one does.
fn walk(rows rows: List(Row), from current: Row) -> List(Row) {
  let followers =
    list.filter(rows, fn(row) { row.follows_quest_id == Some(current.quest_id) })
  case followers {
    [next] -> [current, ..walk(rows:, from: next)]
    _ -> [current]
  }
}

/// The quest of the faction enum's chain a character with this log is due: the first the
/// log holds no entry of, when its predecessor is none or is Completed.
pub fn due(
  chain chain: Chain,
  log log: QuestLog,
  faction_enum faction_enum: Int,
) -> Option(Int) {
  let rows = dict.get(chain.by_faction, faction_enum) |> result.unwrap([])
  let held = fn(quest_id) { quest_log.stored_state(log:, quest_id:) }
  case list.find(rows, fn(row) { held(row.quest_id) == 0 }) {
    Ok(Row(quest_id:, follows_quest_id: None)) -> Some(quest_id)
    Ok(Row(quest_id:, follows_quest_id: Some(before))) ->
      case held(before) == 3 {
        True -> Some(quest_id)
        False -> None
      }
    Error(Nil) -> None
  }
}

/// Whether the quest is one of the chain's.
pub fn is_chain_quest(chain chain: Chain, quest_id quest_id: Int) -> Bool {
  dict.values(chain.by_faction)
  |> list.any(fn(rows) { list.any(rows, fn(row) { row.quest_id == quest_id }) })
}

/// The quest a character of this faction (its Faction2 id) is due, given: the log that
/// holds it accepted at the monotonic time `now_ms` and the 0x35c that tells the client,
/// or none when nothing is due.
pub fn grant(
  chain chain: Chain,
  log log: QuestLog,
  faction_id faction_id: Int,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> Option(Granted) {
  let assert Ok(faction) = shown.faction_of(faction_id:)
    as "a character is an Exile or a Dominion"
  let faction_enum = case faction {
    shown.Exile -> 0
    shown.Dominion -> 1
  }
  case due(chain:, log:, faction_enum:) {
    None -> None
    Some(quest_id) -> {
      let assert Ok(quest) = quest_log.quest_of(tables:, id: quest_id)
        as "the load refused a chain row with no Quest2 row"
      let assert Ok(row) = quest2.get(tables:, id: Quest2Id(quest_id))
        as "the load refused a chain row with no Quest2 row"
      Some(Granted(
        log: quest_log.accept(
          log:,
          quest:,
          max_time_ms: row.max_time_allowed_ms,
          now_ms:,
        ),
        frame: quest_log.quest_state_frame(quest_id:, state: 1, objective_id: 0),
      ))
    }
  }
}
