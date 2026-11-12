//// The tables a quest's turn-in reads. Expected values come from the fixture's rows
//// (the client's own tables) and from the client's IsRewardChoiceOffered (`0x140551c60`).
////
//// Quest 2909 has the choice rows 2368 (Item2 13005) and 2369 (Item2 6998) and the fixed
//// row 2370. Item2 13005 has no row in the table; a Quest2Reward row names its object by
//// a plain number, so the tables load all the same.

import client_tables
import genesis_prime/game/communicator
import genesis_prime/game/vendor_trade.{Log}
import genesis_prime/step.{LogWarning}
import genesis_prime/table/id.{Item2Id, Quest2RewardId}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/quest2_reward.{type Quest2Reward}
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import quest_turn_in_support as support
import unitest

pub fn reward_choice_without_an_item_row_is_not_offered_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [support.receiving(2909)])
  let assert Ok(missing) = quest2_reward.get(tables:, id: Quest2RewardId(2368))
    as "the tables load with the choice row 2368"
  assert quest2_reward.quest2_id(missing).value == 2909
  assert missing.object_id == 13_005
  assert item2.get(tables:, id: Item2Id(13_005)) == Error(Nil)
    as "Item2 13005 has no row"
  let choosing = fn(reward_id) {
    support.Scene(..support.scene(quest_id: 2909), reward_id:)
  }
  let #(effects, logged) = support.refused(scene: choosing(2368), tables:)
  let assert [Log(level: LogWarning, text:)] = effects
    as "the choice without an item row is refused with a log line and nothing sent"
  assert string.contains(text, "not a choice the player is offered")
    as "it is refused as a choice that is not offered, not for what placing its item finds"
  assert set.size(logged) == 1
  let #(_, _) = support.asked(scene: choosing(2369), tables:)
  Nil
}

/// The quests of the client's tables the server completes that have a Quest2Reward row
/// satisfying `of_kind`, in id order.
fn completed_by_server_with_a_reward_row(
  tables tables: table_store.Tables,
  of_kind of_kind: fn(Quest2Reward) -> Bool,
) -> List(Int) {
  let with_rows =
    quest2_reward.all(tables)
    |> list.filter(of_kind)
    |> list.map(fn(reward) { reward.quest2_id })
    |> set.from_list
  quest2.all(tables)
  |> list.filter(fn(quest) {
    set.contains(with_rows, quest.id)
    && communicator.completed_by_server(tables:, quest:)
  })
  |> list.map(fn(quest) { quest.id })
  |> list.sort(by: int.compare)
}

pub fn ten_quests_the_server_completes_offer_a_reward_choice_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // A Quest2Reward row of flags bit 0 is a choice (IsRewardChoiceOffered `0x140551c60`).
  // No dialog lets the player pick one when the server completes the quest, so the rule
  // gives these quests their fixed rows only: the list is pinned here so that a client
  // update that adds one is seen.
  let tables = client_tables.shared()
  assert completed_by_server_with_a_reward_row(tables:, of_kind: fn(reward) {
      int.bitwise_and(reward.flags, 1) != 0
    })
    == [2909, 3489, 3696, 3697, 3724, 3725, 5297, 6596, 7008, 7019]
}

pub fn thirty_four_quests_the_server_completes_give_tradeskill_experience_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Quest2RewardType 4 is tradeskill experience: a fixed row of it is refused for a player
  // with no learned tradeskill (the client's reader), so the rule refuses these quests
  // until the tradeskill step builds it.
  let tables = client_tables.shared()
  let quests =
    completed_by_server_with_a_reward_row(tables:, of_kind: fn(reward) {
      reward.quest2_reward_type_id == 4 && int.bitwise_and(reward.flags, 1) == 0
    })
  assert list.length(quests) == 34
}
