//// What a turn-in does with each kind of Quest2Reward row (`genesis_prime/game/quest_turn_in`).
//// Expected values come from these places, and never from the helpers that build the input.
//// - `Quest2Reward.quest2RewardTypeId`: the type of a row is 1 an item, 2 reputation, 3 money
////   whose object is a currency type, 4 tradeskill experience, 5 a new tradeskill, 7 an
////   account currency, 10 rotation essence; no row of the client has type 6. The client's
////   native code reads only whether the type is 1 (`0x140551c60`); the rest go to Lua
////   (`0x140665c80`).
//// - `lua.Money.CodeEnumCurrencyType`: currency 1 is the credits.
//// - `0x140557000`: a fixed TradeSkillXp row refuses the turn-in for a player with no learned
////   tradeskill; a type 5 row is not refused (the server's choice, `quest_turn_in`'s own rule).
//// - The lines a turn-in leaves out are the server's own text, one per kind, in the order
////   reputation, currency, rotation, tradeskill, each naming the issue that closes it.
//// - Quest 10520 is the quest Dorian Walker receives: no Quest2Reward row, difficulty 6
////   whose cashRewardMultiplier is 0, so it pays no credits of its own; its rows are
////   added here, each a copy of Quest2Reward 2471 with the cells named.

import fixture_tables
import genesis_prime/game/quest_turn_in
import genesis_prime/game/vendor_trade.{Log}
import genesis_prime/step.{LogWarning}
import genesis_prime/store.{NewStack, Placed}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/string
import owned_test
import planted_table.{Integer}
import quest_turn_in_support as support

const quest_id = 10_520

/// The first id of the rows a test adds: above the client's Quest2Reward ids and within the
/// 15 bits of the message's reward id.
const first_added_id = 32_001

/// One Quest2Reward row: its type, object, amount and flags.
type Reward {
  Reward(type_number: Int, object_id: Int, amount: Int, flags: Int)
}

/// Runs the body on tables where quest 10520 has the rewards, in this order.
fn with_rewards(
  rewards rewards: List(Reward),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.index_fold(rewards, fixture_tables.rows(), fn(rows, reward, index) {
      case
        fixture_tables.add(
          rows:,
          table: "Quest2Reward",
          copy_of: 2471,
          id: first_added_id + index,
          with: [
            #("quest2Id", Integer(quest_id)),
            #("quest2RewardTypeId", Integer(reward.type_number)),
            #("objectId", Integer(reward.object_id)),
            #("objectAmount", Integer(reward.amount)),
            #("flags", Integer(reward.flags)),
          ],
        )
      {
        Ok(added) -> added
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// The scene of the turn-in: the choice row is the first of flags 1, else no choice.
fn scene_for(rewards rewards: List(Reward)) -> support.Scene {
  let choice =
    list.index_map(rewards, fn(reward, index) { #(reward, index) })
    |> list.find(fn(entry) { { entry.0 }.flags == 1 })
  case choice {
    Ok(#(_, index)) ->
      support.Scene(
        ..support.scene(quest_id:),
        reward_id: first_added_id + index,
      )
    Error(Nil) -> support.scene(quest_id:)
  }
}

/// The turn-in the store is asked to save, and the lines logged for what it leaves out.
fn turned_in(
  rewards rewards: List(Reward),
) -> #(quest_turn_in.TurnIn, List(String)) {
  use tables <- with_rewards(rewards)
  let assert Ok(quest_turn_in.Asks(turn_in:, effects:, ..)) =
    support.taken(scene: scene_for(rewards:), tables:)
    as "the turn-in passes every check, so the store is asked"
  let lines =
    list.map(effects, fn(effect) {
      let assert Log(level: LogWarning, text:) = effect
        as "each left-out line is a warning the first time"
      text
    })
  #(turn_in, lines)
}

pub fn a_fixed_tradeskill_experience_reward_declines_the_turn_in_and_a_new_tradeskill_does_not_test() -> Nil {
  use <- owned_test.run(10_000)
  let fixed = fn(type_number) {
    [Reward(type_number:, object_id: 1, amount: 1, flags: 0)]
  }
  {
    use tables <- with_rewards(fixed(4))
    let #(effects, _) =
      support.refused(scene: support.scene(quest_id:), tables:)
    let assert [Log(level: LogWarning, text:)] = effects
      as "0x140557000: a fixed type 4 row refuses the turn-in with one warning"
    assert string.contains(text, "fixed tradeskill experience reward")
      as "the refusal names the reward"
  }
  let #(_, lines) = turned_in(rewards: fixed(5))
  assert list.map(lines, string.contains(_, "#677")) == [True]
    as "a fixed type 5 row does not refuse the turn-in; it is left out with the tradeskill line"
}

pub fn only_money_of_currency_1_pays_credits_test() -> Nil {
  use <- owned_test.run(10_000)
  let paid = fn(object_id) {
    let #(turn_in, _) =
      turned_in(rewards: [
        Reward(type_number: 3, object_id:, amount: 50, flags: 0),
      ])
    turn_in.credits_after - turn_in.credits_held
  }
  assert paid(1) == 50
    as "lua.Money.CodeEnumCurrencyType: currency 1 is the credits, and the quest's own credits are 0 (difficulty 6)"
  assert paid(2) == 0 as "currency 2 is Renown, not credits"
  assert paid(4) == 0 as "currency 4 is not credits"
  assert paid(0) == 0 as "no currency is not credits"
}

pub fn item_rewards_of_one_item_add_together_and_place_in_order_of_first_appearance_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 6998 holds 100 to a stack and 179 holds one (`quest_turn_in_test`). A reputation
  // and a money row give no item, so they place nothing.
  let #(turn_in, _) =
    turned_in(rewards: [
      Reward(type_number: 2, object_id: 6998, amount: 9, flags: 0),
      Reward(type_number: 1, object_id: 6998, amount: 2, flags: 0),
      Reward(type_number: 3, object_id: 179, amount: 9, flags: 0),
      Reward(type_number: 1, object_id: 179, amount: 1, flags: 0),
      Reward(type_number: 1, object_id: 6998, amount: 3, flags: 0),
    ])
  assert turn_in.placed
    == [
      Placed(Item2Id(6998), grow: [], make: [
        NewStack(
          location: 1,
          bag_index: 0,
          stack_count: 5,
          random_stats: 0,
          charges: 0,
        ),
      ]),
      Placed(Item2Id(179), grow: [], make: [
        NewStack(
          location: 1,
          bag_index: 1,
          stack_count: 1,
          random_stats: 0,
          charges: 0,
        ),
      ]),
    ]
    as "the two rows of 6998 are one stack of 5, placed first; 179 follows; the reputation and money rows name 6998 and 179 as objects and place nothing"
}

pub fn each_reward_kind_the_server_leaves_out_has_its_own_line_in_its_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let one = fn(type_number, object_id, flags) {
    let #(_, lines) =
      turned_in(rewards: [
        Reward(type_number:, object_id:, amount: 1, flags:),
      ])
    lines
  }
  let named = fn(lines: List(String), issues: List(String)) {
    list.length(lines) == list.length(issues)
    && list.all(list.zip(lines, issues), fn(pair) {
      string.contains(pair.0, pair.1)
    })
  }
  assert named(one(2, 1, 0), ["#674"]) as "type 2 is a reputation reward"
  assert named(one(3, 4, 0), ["#675"])
    as "type 3 of currency 4 is a reward of a currency but credits"
  assert named(one(7, 1, 0), ["#675"]) as "type 7 is an account currency"
  assert named(one(10, 1, 0), ["#676"]) as "type 10 is rotation essence"
  assert named(one(4, 1, 1), ["#677"])
    as "type 4 chosen is left out with the tradeskill line"
  assert named(one(5, 1, 0), ["#677"]) as "type 5 is left out with it too"
  assert one(3, 1, 0) == [] as "a credits reward is given, not left out"
  assert one(1, 179, 0) == [] as "an item reward is placed, not left out"
  assert one(6, 1, 0)
    == [
      "quest 10520 has a reward of type 6, which the client's tables do not name for the server; the turn-in goes on without it",
    ]
    as "no row of the client has type 6: the one line names the number"
  let #(_, together) =
    turned_in(rewards: [
      Reward(type_number: 6, object_id: 1, amount: 1, flags: 0),
      Reward(type_number: 10, object_id: 1, amount: 1, flags: 0),
      Reward(type_number: 7, object_id: 1, amount: 1, flags: 0),
      Reward(type_number: 5, object_id: 1, amount: 1, flags: 0),
      Reward(type_number: 2, object_id: 1, amount: 1, flags: 0),
      Reward(type_number: 4, object_id: 1, amount: 1, flags: 1),
    ])
  assert named(together, ["#674", "#675", "#676", "#677", "type 6"])
    as {
      "one line for each kind in the order of their issues, and the unknown type last, whatever the order of the rows: "
      <> int.to_string(list.length(together))
    }
}
