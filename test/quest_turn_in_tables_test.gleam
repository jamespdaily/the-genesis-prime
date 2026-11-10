//// The tables a quest's turn-in reads. Expected values come from the fixture's rows
//// (the client's own tables) and from the client's IsRewardChoiceOffered (`0x140551c60`).
////
//// Quest 2909 has the choice rows 2368 (Item2 13005) and 2369 (Item2 6998) and the fixed
//// row 2370. Item2 13005 has no row in the table; a Quest2Reward row names its object by
//// a plain number, so the tables load all the same.

import genesis_prime/game/vendor_trade.{Log}
import genesis_prime/step.{LogWarning}
import genesis_prime/table/id.{Item2Id, Quest2RewardId}
import genesis_prime/table/item2
import genesis_prime/table/quest2_reward
import gleam/set
import gleam/string
import owned_test
import quest_turn_in_support as support

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
