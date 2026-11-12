//// What the tests of the tutorial chain share: the rows of the eight quests in the two
//// orders the migration seeds, the chain they select to, and the one with no quest in it,
//// which a connection made for another test is given.

import character_tables
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/tutorial.{type Chain, Row}
import gleam/list
import gleam/option.{None, Some}
import quest_support

/// The rows of the Exile chain 10513, 10527, 10518, 10529 and the Dominion chain 10521,
/// 10532, 10524, 10533, each row naming the quest it follows.
pub fn rows() -> List(tutorial.Row) {
  [
    Row(quest_id: 10_513, follows_quest_id: None),
    Row(quest_id: 10_527, follows_quest_id: Some(10_513)),
    Row(quest_id: 10_518, follows_quest_id: Some(10_527)),
    Row(quest_id: 10_529, follows_quest_id: Some(10_518)),
    Row(quest_id: 10_521, follows_quest_id: None),
    Row(quest_id: 10_532, follows_quest_id: Some(10_521)),
    Row(quest_id: 10_524, follows_quest_id: Some(10_532)),
    Row(quest_id: 10_533, follows_quest_id: Some(10_524)),
  ]
}

/// The chain of those rows over the client's committed tables.
pub fn chain() -> Chain {
  let assert Ok(chain) =
    tutorial.select(rows: rows(), tables: character_tables.content_tables())
    as "each row names a quest the committed tables hold, no creature gives or receives it"
  chain
}

/// The chain of no rows: no character is due a quest.
pub fn none() -> Chain {
  let assert Ok(none) =
    tutorial.select(rows: [], tables: character_tables.content_tables())
    as "no rows select"
  none
}

/// A log that holds these quests Completed.
pub fn completed(quests quests: List(Int)) -> QuestLog {
  quest_support.log_of(
    rows: list.map(quests, fn(quest_id) {
      quest_support.completed(quest_id:, at: 1_700_000_000)
    }),
  )
}

/// The quests `due` gives a character of the faction enum one after another, each
/// completed before the next is asked for: the order the chain gives them in.
pub fn order(chain chain: Chain, faction_enum faction_enum: Int) -> List(Int) {
  next_of(chain:, faction_enum:, done: [])
}

fn next_of(
  chain chain: Chain,
  faction_enum faction_enum: Int,
  done done: List(Int),
) -> List(Int) {
  case tutorial.due(chain:, log: completed(quests: done), faction_enum:) {
    None -> done
    Some(quest_id) ->
      next_of(chain:, faction_enum:, done: list.append(done, [quest_id]))
  }
}
