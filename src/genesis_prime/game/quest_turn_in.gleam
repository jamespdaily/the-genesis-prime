//// The player's turn-in of a quest, the client's 0x035D: a feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in the world. The
//// sequence is genesis_prime/game/connection/quest_turn_in's.
////
//// ```
//// 0x35D {quest, reward, by communicator} ─▶ take(body, asker, standing, picture, progress, currencies, life, ...)
////                                           ├─ refused ─▶ Refused([Log])  or  Refused([Refuse(27)])  or  Refused([Log, Refuse(57)])   nothing asked, nothing changed
////                                           └─ accepted ─▶ Asks(turn_in) ─▶ the connection asks the store (request(..))
//// the store's answer ─▶ answered(turn_in, items, currencies, answer)
////                       TurnedIn(credits, made): the log has the quest Completed, the items, the credits, the
////                                                experience and the level are saved; 0x111, the count changes,
////                                                0x1ac, 0x938 with the Level news, 0x919 and 0xDD, then 0x35C {quest, 3, 0}
////                       ItemsNotSaved:           Warning, nothing sent, nothing changed (the quest stays Achieved)
////                       SaveRefused(c):          Error naming c, nothing sent, nothing changed
//// a quest Achieved that no creature receives ─▶ completed_by_server(quest, asker, progress, currencies, ...)
////                                               the same refusals and Asks(turn_in), and the same answer, as a 0x35D with reward 0
//// ```
////
//// - **The server's completion** (`completed_by_server`) is a turn-in the server makes of a quest
////   `communicator.completed_by_server` names, once it is Achieved, because the client offers no
////   turn-in for it. It takes steps 2 and 3 as they are, with the state exactly Achieved (2), no
////   death check, no receiver or communicator check and no reward chosen, then the rewards
////   below: a quest with a choice row gives its fixed rows only (nothing lets the player pick,
////   and the client's rows do not say which choice the server should give), and one with a full
////   bag is refused (0x106 code 27) and stays Achieved.
//// - **The checks, in the order of the client's turn-in** (`opcode.0x35d`), each a log line
////   once per reason on the connection, because the client sends the message only from a dialog
////   it built from the same tables, so a refusal is a modified or stale client or a gap this
////   server has; the first that fails answers:
////   1. a body the client's reader refuses ends the connection (`NotDecoded`)
////   1a. the player is dead, over the communicator or at a creature: 0x106 code 57
////      (Player_CantDoWhileDead), as a buy answers; the client's dialog closes on death
////      (`0x140554470.communicator_dialog`), so it never sends this
////   2. the quest has no Quest2 row, or a row the client's quest reader refuses
////   3. the log's state for it is not Achieved (2), unless the quest auto-completes (Quest2
////      flags bit 0): it is then taken as `quest.can_accept` takes an accept with the log-full
////      bit masked, and goes from no entry, or a Known one, straight to Completed
////   4. the receiver: a shown creature or static object alive, not Hostile to the player, within
////      reach, whose Creature2 row receives the quest (`spawn.received_quest_ids`, through `quest.in_reach`);
////      with the by-communicator bit set, the communicator's check instead, and no creature is
////      needed (genesis_prime/game/communicator): the quest must be Achieved, with no
////      auto-complete, and the dialog the client opens must offer it, which is flags 0x10000 with a
////      CommunicatorMessages row delivering it, or flags 8 with a receiver whose faction is not
////      Hostile to the player's current faction
////   5. the reward id: 0 only when the quest has no choice rows, else the Quest2Reward id of a
////      choice row the player is offered (`equip_requirement.offered`)
////   6. the quest has a fixed TradeSkillXp row (Quest2Reward type 4): refused, as the client
////      refuses it for a player with no learned tradeskill
////   Then the rewards are computed and placed: a bag with no room for an item is the one refusal
////   the player sees, 0x106 code 27 (Item_InventoryFull).
//// - **The rewards** are the quest's Quest2Reward rows of type 1 (the fixed items and the
////   chosen one), type 3 of currency 1, the experience and the credits. The experience is the
////   quest's override, else the XpPerLevel base at the quest's level times the difficulty's
////   multiplier times the quest's experience multiplier, truncated; the credits are the
////   override when above 0, else the quest's level raised to GameFormula 530's first value
////   times the cash multiplier, plus a half, truncated, at most the currency's cap
////   (`currency.cap`). Reward kinds the server does not build yet (reputation, other
////   currencies, account currency, rotation essence, tradeskill kinds, contracts) are logged
////   once per kind and the turn-in goes on.
//// - **Where the items go** is `inventory.placed`: the stacks below the limit first, then the
////   lowest empty usable slots, each Item2 against the items as the one before it left them.
//// - **The roll.** An item with random stat entries is made with a word rolled when the store
////   is asked (`entropy_needed`, `rolled`, `genesis_prime/game/random_stat`), one for each made
////   stack, in the order of the placed items.
//// - **The save** is the whole turn-in in the one transaction of the store's request: the
////   character's row lock, the place save carrying the log with the quest Completed, the
////   experience and the level, then the credits and the items, so storage holds the whole
////   turn-in or none of it.
//// - **The frames, in this order** (a server choice; the client needs only 0x35C last of the
////   turn-in's): 0x111 (reason 8) for each stack made, a count change for each stack grown,
////   0x1ac of kind 3 when the gain is above 0, 0x938 of the level and the Level news when it
////   rose, 0x919 and the 0xDD of the credits gained when the credits changed (`currency.total_frames`), then 0x35C with state 3, then the frames of the
////   held-item objectives of other quests that the reward items advanced
////   (`connection_objective.settled`, as a pickup does).
////
//// | Point | What happens |
//// |---|---|
//// | the quest's Quest2, Quest2Reward or Item2 row a check reads is missing | a logged refusal |
//// | the store changes nothing or refuses a place | a warning, nothing sent, the quest stays Achieved |
//// | the connection ends while the store works | the store finishes or rolls back; the next login loads whichever |
//// | the same message while the store works | held, then taken against the new log |
//// | the server's completion of a quest not Achieved, or one a creature receives or the communicator turns in | a logged refusal |
//// | the server's completion of a quest with a reward choice | the fixed rewards only, the quest Completed |
//// | the server's completion with no room for a reward item | 0x106 code 27, the quest stays Achieved |

import genesis_prime/client_connection
import genesis_prime/game/communicator
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/equip_requirement.{Wearer}
import genesis_prime/game/experience
import genesis_prime/game/interaction
import genesis_prime/game/inventory
import genesis_prime/game/item_property
import genesis_prime/game/player_life
import genesis_prime/game/quest
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/random_stat
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/vendor_trade.{type Effect, Log, Refuse, Send}
import genesis_prime/message/quest_turn_in as quest_turn_in_message
import genesis_prime/step.{LogError, LogWarning}
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemsAnswer,
  type SessionEpoch, HeldItem, ItemsNotSaved, SaveRefused,
}
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Item2Id, GameFormulaId, Item2Id, LevelDifferentialAttributeId, Quest2Id,
  XpPerLevelId,
}
import genesis_prime/table/level_differential_attribute.{
  type LevelDifferentialAttribute,
}
import genesis_prime/table/loader/formula_requirement
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/table/quest2_difficulty
import genesis_prime/table/quest2_reward.{type Quest2Reward}
import genesis_prime/table/xp_per_level
import genesis_prime/world_map/spawn
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// The id of the message this rule takes.
pub const message_id = quest_turn_in_message.message_id

/// The GameFormula row whose first float is the exponent of a quest's credits
/// (`0x1405542b0`).
const credits_formula = 530

/// The Quest2Reward rows of each quest, in record order.
type Rewards {
  Rewards(by_quest: Dict(Int, List(Quest2Reward)))
}

/// The key of the rewards in the tables' store.
const rewards_key: table_store.DerivedKey(Rewards) =
  table_store.DerivedKey("QuestRewards")

/// The rewards as a value the tables' load builds once, under the tables' key, so a turn-in
/// reads the quest's rows without a pass over the table.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: rewards_key, build: fn(tables) {
    Ok(
      Rewards(
        by_quest: list.fold(
          list.reverse(quest2_reward.all(tables)),
          dict.new(),
          fn(by_quest, reward) {
            dict.upsert(by_quest, reward.quest2_id, fn(found) {
              [reward, ..option.unwrap(found, [])]
            })
          },
        ),
      ),
    )
  })
}

/// The Quest2Reward rows of a quest, in record order.
fn rewards_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> List(Quest2Reward) {
  let Rewards(by_quest:) = table_store.derived(tables:, key: rewards_key)
  result.unwrap(dict.get(by_quest, quest_id), [])
}

/// What the tables must hold at load for the credits: GameFormula 530.
pub fn requirements() -> List(table_store.Requirement) {
  [
    formula_requirement.row_present(
      from_table: "the server's quest credits",
      id: credits_formula,
    ),
  ]
}

/// The checks of the client's auto-complete turn-in (`0x140553030`: `mov edx, 0xffffdfff` at
/// `0x1405530d9`): every check of an accept but the one for a full log (bit 13).
const auto_complete_checks = 0xffff_dfff

/// Quest2 flags bit 0: the quest completes without being taken.
const auto_complete_flag = 1

/// Quest2 flags bit 3: the quest is one the communicator turns in.
const communicable_flag = 8

/// Quest2 flags bits 0 and 2: a quest the client completes through a call from the server.
const completes_by_call_flags = 5

/// Quest2Reward flags bit 0: the row is a choice.
const choice_flag = 1

/// Quest2RewardType 1, an item.
const item_type = 1

/// Quest2RewardType 2, reputation.
const reputation_type = 2

/// Quest2RewardType 3, money: the credits when its object is currency 1.
const money_type = 3

/// Quest2RewardType 4, tradeskill experience.
const tradeskill_experience_type = 4

/// Quest2RewardType 5, a new tradeskill.
const tradeskill_grant_type = 5

/// Quest2RewardType 7, an account currency.
const account_currency_type = 7

/// Quest2RewardType 10, rotation essence.
const rotation_essence_type = 10

/// The client's code for a turn-in the inventory has no room for (Item_InventoryFull).
const inventory_full = 27

/// The client's code for a request a dead player makes (Player_CantDoWhileDead).
const cant_do_while_dead = 57

/// The reason the turn-in's items are shown for (Item.CodeEnumItemUpdateReason 8, Quest).
const quest_reason = 8

/// A turn-in the store is asked to save: the quest, the log with it Completed, the
/// experience and level after the gain, the credits held and the credits after the reward
/// (capped), and where each item goes.
pub type TurnIn {
  TurnIn(
    quest_id: Int,
    log: QuestLog,
    credited: experience.Credited,
    credits_held: Int,
    credits_after: Int,
    placed: List(store.Placed),
  )
}

/// What the rule made of a turn-in.
pub type Taken {
  /// Refused: the effects to carry out and the log keys met so far.
  Refused(effects: List(Effect), logged: Set(String))
  /// Accepted: the turn-in to ask the store to save, the effects to carry out first (the
  /// log lines of the reward kinds left out) and the log keys met so far.
  Asks(turn_in: TurnIn, effects: List(Effect), logged: Set(String))
}

/// What the store's answer leaves.
pub type Answered {
  /// Saved: the items and currencies after it, the effects before the experience's (the
  /// items) and after it (0x919, 0xDD and 0x35C).
  Saved(
    items: List(HeldItem),
    currencies: Currencies,
    rewards: List(Effect),
    then: List(Effect),
  )
  /// Not saved: the effects (a log line), and nothing changed.
  NotSaved(effects: List(Effect))
}

/// Why a turn-in does not go on: a check broken, logged once for its `key`, or no room
/// for an item, the one refusal the player is told of.
type Stop {
  Declined(key: String, text: String)
  NoRoom
}

/// What the client's 0x035D is answered with: a refusal, or the turn-in to ask the store to
/// save. `Error` ends the connection: a body the client's reader refuses.
pub fn take(
  body body: BitArray,
  asker asker: quest.Asker,
  standing standing: quest.Standing,
  picture picture: Picture,
  progress progress: experience.Progress,
  currencies currencies: Currencies,
  item_proficiencies item_proficiencies: Int,
  life life: player_life.Life,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
  unix_seconds unix_seconds: Int,
  logged logged: Set(String),
) -> Result(Taken, quest.Refusal) {
  use message <- result.map(
    quest_turn_in_message.decode(body)
    |> client_connection.decoded(message_id:)
    |> result.map_error(quest.NotDecoded),
  )
  use <- refused_when_dead(message:, life:, logged:)
  taken_of(
    checked: checked(
      message:,
      asker:,
      standing:,
      picture:,
      progress:,
      currencies:,
      item_proficiencies:,
      tables:,
      now_ms:,
      unix_seconds:,
    ),
    logged:,
  )
}

/// What the checks' outcome is taken as: a logged refusal, the one refusal the player is
/// told of, or the turn-in to ask the store to save.
fn taken_of(
  checked checked: Result(#(TurnIn, List(#(String, String))), Stop),
  logged logged: Set(String),
) -> Taken {
  case checked {
    Error(Declined(key:, text:)) -> {
      let #(level, logged) = interaction.log_level(key:, logged:)
      Refused(effects: [Log(level:, text:)], logged:)
    }
    Error(NoRoom) -> Refused(effects: [Refuse(code: inventory_full)], logged:)
    Ok(#(turn_in, left_out)) -> {
      let #(lines, logged) =
        list.fold(left_out, #([], logged), fn(so_far, kind) {
          let #(lines, logged) = so_far
          let #(level, logged) = interaction.log_level(key: kind.0, logged:)
          #([Log(level:, text: kind.1), ..lines], logged)
        })
      Asks(turn_in:, effects: list.reverse(lines), logged:)
    }
  }
}

/// The server's completion of a quest no creature receives (`communicator.completed_by_server`),
/// taken as a turn-in of it with no reward chosen: the client's 0x035D is never sent for such a
/// quest, so the checks are the ones the server's own act needs. The quest must be in the log
/// Achieved (exactly 2: no auto-complete from another state), and the rewards are computed and
/// placed as a turn-in's. A quest with a reward choice gives its fixed rewards only: nothing
/// lets the player pick.
pub fn completed_by_server(
  quest_id quest_id: Int,
  asker asker: quest.Asker,
  progress progress: experience.Progress,
  currencies currencies: Currencies,
  item_proficiencies item_proficiencies: Int,
  tables tables: table_store.Tables,
  unix_seconds unix_seconds: Int,
  logged logged: Set(String),
) -> Taken {
  let turning = "the server completes quest " <> int.to_string(quest_id)
  taken_of(
    checked: {
      use #(row, state) <- result.try(row_and_state(
        turning:,
        quest_id:,
        asker:,
        tables:,
      ))
      use <- bool.guard(
        when: state != 2,
        return: Error(Declined(
          key: "server state " <> int.to_string(state),
          text: turning
            <> ", whose state in the log is "
            <> int.to_string(state)
            <> " and not Achieved",
        )),
      )
      use <- bool.guard(
        when: !communicator.completed_by_server(tables:, quest: row),
        return: Error(Declined(
          key: "server completion",
          text: turning
            <> ", which a creature receives or the communicator turns in",
        )),
      )
      rewarded(
        turning:,
        row:,
        log: quest_log.complete(
          log: asker.log,
          quest_id:,
          at_seconds: unix_seconds,
        ),
        choosing: FixedRewardsOnly,
        asker:,
        progress:,
        currencies:,
        item_proficiencies:,
        tables:,
      )
    },
    logged:,
  )
}

/// The refusal of a dead player's turn-in, which the client never sends: its dialog closes
/// on death and AnswerCommunicatorQuest returns (`0x140554470.communicator_dialog`), so the
/// server answers 57 (Player_CantDoWhileDead) as it does a buy. Otherwise `next` decides.
fn refused_when_dead(
  message message: quest_turn_in_message.QuestTurnIn,
  life life: player_life.Life,
  logged logged: Set(String),
  next next: fn() -> Taken,
) -> Taken {
  case
    vendor_trade.refused_when_dead(
      key: "dead player",
      text: "0x035D turns in quest "
        <> int.to_string(message.quest_id)
        <> " while the player is dead: the client sends nothing for a dead player, so the server answers "
        <> int.to_string(cant_do_while_dead),
      code: cant_do_while_dead,
      life:,
      logged:,
    )
  {
    Error(vendor_trade.Declined(effects:, logged:)) ->
      Refused(effects:, logged:)
    Ok(Nil) -> next()
  }
}

/// The turn-in the checks let through, with the reward kinds it leaves out (each a log key
/// and its line), or the first check that fails.
fn checked(
  message message: quest_turn_in_message.QuestTurnIn,
  asker asker: quest.Asker,
  standing standing: quest.Standing,
  picture picture: Picture,
  progress progress: experience.Progress,
  currencies currencies: Currencies,
  item_proficiencies item_proficiencies: Int,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
  unix_seconds unix_seconds: Int,
) -> Result(#(TurnIn, List(#(String, String))), Stop) {
  let quest_id = message.quest_id
  let turning = "0x035D turns in quest " <> int.to_string(quest_id)
  use #(row, state) <- result.try(row_and_state(
    turning:,
    quest_id:,
    asker:,
    tables:,
  ))
  use log <- result.try(case message.by_communicator != 0 {
    True ->
      by_communicator_allows(
        turning:,
        row:,
        state:,
        asker:,
        tables:,
        unix_seconds:,
      )
    False ->
      state_allows(turning:, row:, state:, asker:, tables:, unix_seconds:)
  })
  use <- bool.guard(
    when: message.by_communicator == 0
      && !quest.in_reach(
      quest_id:,
      quest_ids: spawn.received_quest_ids,
      standing:,
      picture:,
      tables:,
      now_ms:,
    ),
    return: Error(Declined(
      key: "no receiver",
      text: turning
        <> " with no shown creature that receives it alive, not Hostile and within reach",
    )),
  )
  rewarded(
    turning:,
    row:,
    log:,
    choosing: Chosen(reward_id: message.reward_id),
    asker:,
    progress:,
    currencies:,
    item_proficiencies:,
    tables:,
  )
}

/// The quest's Quest2 row and the state the log holds for it, or the check of a quest the
/// client's reader refuses.
fn row_and_state(
  turning turning: String,
  quest_id quest_id: Int,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
) -> Result(#(Quest2, Int), Stop) {
  use known <- result.try(
    quest_log.quest_of(tables:, id: quest_id)
    |> result.map_error(fn(error) {
      case error {
        quest_log.NoQuestRow ->
          Declined(
            key: "unknown quest",
            text: turning <> ", which has no Quest2 row",
          )
        quest_log.NoObjectiveRow(objective_id:) ->
          Declined(
            key: "quest row",
            text: turning
              <> ", whose QuestObjective row "
              <> int.to_string(objective_id)
              <> " is missing",
          )
      }
    }),
  )
  let assert Ok(row) = quest2.get(tables:, id: Quest2Id(quest_id))
    as "a quest the client's rows read has its Quest2 row"
  Ok(#(row, quest_log.state(log: asker.log, quest: known)))
}

/// How a turn-in picks among a quest's reward choices: the player's 0x035D names a Quest2Reward
/// id (0 when the quest has no choice rows), and the server's own completion names none, so it
/// gives the fixed rows alone.
type Choosing {
  Chosen(reward_id: Int)
  FixedRewardsOnly
}

/// The turn-in of a quest whose state allows it, with the rewards computed and placed: the
/// reward `choosing` picks among the choice rows, the fixed rows, the items placed in the
/// bag, the credits and the experience; with the reward kinds it leaves out (each a log key
/// and its line), or the first check that fails.
fn rewarded(
  turning turning: String,
  row row: Quest2,
  log log: QuestLog,
  choosing choosing: Choosing,
  asker asker: quest.Asker,
  progress progress: experience.Progress,
  currencies currencies: Currencies,
  item_proficiencies item_proficiencies: Int,
  tables tables: table_store.Tables,
) -> Result(#(TurnIn, List(#(String, String))), Stop) {
  let quest_id = row.id
  let rows = rewards_of(tables:, quest_id:)
  let #(choices, fixed) =
    list.partition(rows, fn(reward) {
      int.bitwise_and(reward.flags, choice_flag) != 0
    })
  use chosen <- result.try(case choosing {
    FixedRewardsOnly -> Ok(None)
    Chosen(reward_id:) ->
      chosen_reward(
        turning:,
        reward_id:,
        choices:,
        asker:,
        progress:,
        item_proficiencies:,
        tables:,
      )
  })
  use <- bool.guard(
    when: list.any(fixed, fn(reward) {
      reward.quest2_reward_type_id == tradeskill_experience_type
    }),
    return: Error(Declined(
      key: "tradeskill reward",
      text: turning
        <> ", which has a fixed tradeskill experience reward the client refuses for a player with no learned tradeskill (#677)",
    )),
  )
  let given =
    list.append(fixed, option.unwrap(option.map(chosen, fn(row) { [row] }), []))
  use placed <- result.try(place_items(turning:, given:, asker:, tables:))
  let credits_held =
    currency.held(currencies:, currency_type_id: currency.credits_type)
  let credits_after =
    currency.added(
      held: credits_held,
      paid: credits_paid(row:, given:, tables:),
      cap: currency.cap(tables:, currency_type_id: currency.credits_type),
    )
  let credited =
    experience.gained(
      progress:,
      gain: experience_paid(row:, level: progress.level, tables:),
      kind: experience.quest_kind,
      unit_id: 0,
      tables:,
    )
  Ok(#(
    TurnIn(quest_id:, log:, credited:, credits_held:, credits_after:, placed:),
    left_out(quest_id:, row:, given:),
  ))
}

/// The check of a quest the log holds in a state other than Achieved.
fn not_achieved(turning turning: String, state state: Int) -> Stop {
  Declined(
    key: "state " <> int.to_string(state),
    text: turning
      <> ", whose state in the log is "
      <> int.to_string(state)
      <> " and not Achieved",
  )
}

/// The log with the quest Completed, when its state allows a turn-in: Achieved (2), or, for
/// a quest that completes without being taken (Quest2 flags bit 0), no entry, a Known one or
/// a Completed one (the quest repeats) that passes the accept's checks but the one for a full
/// log.
fn state_allows(
  turning turning: String,
  row row: Quest2,
  state state: Int,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
  unix_seconds unix_seconds: Int,
) -> Result(QuestLog, Stop) {
  let completed =
    quest_log.complete(
      log: asker.log,
      quest_id: row.id,
      at_seconds: unix_seconds,
    )
  let declined = fn(why) {
    Declined(key: "auto-complete", text: turning <> ", which " <> why)
  }
  case state, int.bitwise_and(row.flags, auto_complete_flag) != 0 {
    2, _ -> Ok(completed)
    1, _ -> Error(not_achieved(turning:, state:))
    _, False -> Error(not_achieved(turning:, state:))
    _, True ->
      case
        quest.can_accept(
          tables:,
          quest: row,
          asker:,
          mask: auto_complete_checks,
        )
      {
        Ok(quest.Acceptable) -> Ok(completed)
        Ok(quest.Refused(code:)) ->
          Error(declined(
            "completes without being taken, but the accept's checks refuse it with code "
            <> int.to_string(code),
          ))
        Ok(quest.NotRead(gap:)) ->
          Error(declined(
            "completes without being taken, but its checks need "
            <> quest.describe_gap(gap:),
          ))
        Error(error) ->
          Error(declined(
            "completes without being taken, but its checks cannot be read: "
            <> quest.describe(error:),
          ))
      }
  }
}

/// The log with the quest Completed, when the communicator turns it in: the quest is
/// Achieved (2), as `0x14043c700` requires before it opens the dialog, and
/// `communicator.turn_in` allows it. The communicator does not complete a quest that
/// completes without being taken: the client's path for it needs a side-list entry only a
/// call from the server makes, and the server sends no call (#334).
fn by_communicator_allows(
  turning turning: String,
  row row: Quest2,
  state state: Int,
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
  unix_seconds unix_seconds: Int,
) -> Result(QuestLog, Stop) {
  use <- bool.guard(
    when: state != 2,
    return: Error(Declined(
      key: "state " <> int.to_string(state),
      text: turning
        <> " by the communicator, whose state in the log is "
        <> int.to_string(state)
        <> " and not Achieved"
        <> case
        int.bitwise_and(row.flags, communicable_flag) != 0
        && int.bitwise_and(row.flags, completes_by_call_flags) != 0
      {
        True ->
          ", and with flag 1 or 4 it completes over the communicator only through a side-list entry a call from the server makes, which the server does not send (#334)"
        False -> ""
      },
    )),
  )
  case communicator.turn_in(quest: row, asker:, tables:) {
    Ok(Nil) ->
      Ok(quest_log.complete(
        log: asker.log,
        quest_id: row.id,
        at_seconds: unix_seconds,
      ))
    Error(refusal) ->
      Error(Declined(
        key: communicator.key(refusal:),
        text: turning
          <> " by the communicator, "
          <> communicator.describe(refusal:),
      ))
  }
}

/// The choice row the reward id names: none when the quest has no choice rows (and the id
/// is 0), else one of the rows the player is offered, which are the rows the wearer may
/// equip, or the first row when no row is offered (as the client's dialog shows it).
fn chosen_reward(
  turning turning: String,
  reward_id reward_id: Int,
  choices choices: List(Quest2Reward),
  asker asker: quest.Asker,
  progress progress: experience.Progress,
  item_proficiencies item_proficiencies: Int,
  tables tables: table_store.Tables,
) -> Result(Option(Quest2Reward), Stop) {
  let refused = fn(why) {
    Error(Declined(
      key: "reward choice",
      text: turning
        <> " with reward id "
        <> int.to_string(reward_id)
        <> ", "
        <> why,
    ))
  }
  case choices {
    [] ->
      case reward_id {
        0 -> Ok(None)
        _ -> refused("which the quest has no choice for")
      }
    [first, ..] -> {
      let wearer =
        Wearer(
          faction_id: asker.factions.current,
          level: progress.level,
          player: asker.player,
          item_proficiencies:,
        )
      let offered = case
        list.filter(choices, fn(reward) {
          equip_requirement.offered(tables:, reward:, wearer:)
        })
      {
        [] -> [first]
        offered -> offered
      }
      case list.find(offered, fn(reward) { reward.id == reward_id }) {
        Ok(reward) -> Ok(Some(reward))
        Error(Nil) -> refused("which is not a choice the player is offered")
      }
    }
  }
}

/// The experience the quest gives (`0x1405534b0`): 0 when the XpPerLevel row of the quest's
/// level, the LevelDifferentialAttribute row of the difference to the player's level
/// (`level_differential`) or the Quest2Difficulty row is missing; else the quest's override
/// when it has one, else the base per level times the difficulty's multiplier times the
/// difference's, truncated.
fn experience_paid(
  row row: Quest2,
  level level: Int,
  tables tables: table_store.Tables,
) -> Int {
  case
    xp_per_level.get(tables:, id: XpPerLevelId(row.con_level)),
    level_differential(tables:, difference: row.con_level - level),
    quest2_difficulty.get(tables:, id: quest2.quest2_difficulty_id(row))
  {
    Ok(per_level), Ok(differential), Ok(difficulty) ->
      case row.reward_xp_override {
        0 ->
          float.truncate(
            int.to_float(per_level.base_quest_xp_per_level)
            *. difficulty.xp_multiplier
            *. differential.quest_xp_multiplier,
          )
        override -> override
      }
    _, _, _ -> 0
  }
}

/// The LevelDifferentialAttribute row of a level difference (`0x1404cd1b0`): the difference
/// kept between the table's smallest and largest `levelDifferentialValue` (compared as signed
/// numbers), the row with that value, else row 1.
fn level_differential(
  tables tables: table_store.Tables,
  difference difference: Int,
) -> Result(LevelDifferentialAttribute, Nil) {
  let rows = level_differential_attribute.all(tables)
  let values = list.map(rows, fn(row) { row.level_differential_value })
  let kept = case values {
    [] -> difference
    [first, ..rest] ->
      difference
      |> int.max(list.fold(rest, first, int.min))
      |> int.min(list.fold(rest, first, int.max))
  }
  case list.find(rows, fn(row) { row.level_differential_value == kept }) {
    Ok(row) -> Ok(row)
    Error(Nil) ->
      level_differential_attribute.get(
        tables:,
        id: LevelDifferentialAttributeId(1),
      )
  }
}

/// The credits the quest pays (`0x1405535d0`, `0x1405542b0`): the quest's override when above
/// 0, else its level raised to GameFormula 530's first float times the difficulty's cash
/// multiplier, plus a half, truncated (0 with no difficulty row); plus the amount of each
/// reward row of money in currency 1.
fn credits_paid(
  row row: Quest2,
  given given: List(Quest2Reward),
  tables tables: table_store.Tables,
) -> Int {
  let quest_paid = case row.reward_cash_override > 0 {
    True -> row.reward_cash_override
    False ->
      case
        quest2_difficulty.get(tables:, id: quest2.quest2_difficulty_id(row))
      {
        Ok(difficulty) -> {
          let assert Ok(formula) =
            game_formula.get(tables:, id: GameFormulaId(credits_formula))
            as "the load requires GameFormula row 530"
          let assert Ok(raised) =
            float.power(int.to_float(row.con_level), formula.datafloat0)
            as "no Quest2 row holds a conLevel with bit 31 set (the generator's column-sign check), so the base is not negative and its power is a number"
          float.truncate(raised *. difficulty.cash_reward_multiplier +. 0.5)
        }
        Error(Nil) -> 0
      }
  }
  list.fold(given, quest_paid, fn(total, reward) {
    case is_credits(reward) {
      True -> total + reward.object_amount
      False -> total
    }
  })
}

/// Whether the reward row is money of currency 1, the credits.
fn is_credits(reward: Quest2Reward) -> Bool {
  reward.quest2_reward_type_id == money_type
  && reward.object_id == currency.credits_type
}

/// Where each item the rewards give goes: the amounts of one Item2 added together, placed
/// in order of first appearance, each against the items as the one before it left them.
/// `NoRoom` when an Item2 does not fit.
fn place_items(
  turning turning: String,
  given given: List(Quest2Reward),
  asker asker: quest.Asker,
  tables tables: table_store.Tables,
) -> Result(List(store.Placed), Stop) {
  let wanted =
    list.fold(given, [], fn(wanted, reward) {
      case reward.quest2_reward_type_id == item_type {
        False -> wanted
        True ->
          case list.key_find(wanted, reward.object_id) {
            Ok(amount) ->
              list.key_set(
                wanted,
                reward.object_id,
                amount + reward.object_amount,
              )
            Error(Nil) ->
              list.append(wanted, [#(reward.object_id, reward.object_amount)])
          }
      }
    })
  use size <- result.try(
    inventory.size(items: asker.items, tables:)
    |> result.map_error(fn(refusal) {
      Declined(
        key: "bags",
        text: turning
          <> ", whose bags are not read: "
          <> inventory.describe(refusal:),
      )
    }),
  )
  list.try_fold(wanted, #(asker.items, []), fn(so_far, want) {
    let #(working, placed) = so_far
    let #(item2_id, amount) = want
    use limit <- result.try(
      item_property.stack_limit(tables:, item2_id:)
      |> result.map(option.unwrap(_, 1))
      |> result.map_error(fn(error) {
        Declined(
          key: "item " <> int.to_string(item2_id),
          text: turning
            <> ", whose reward item is not read: "
            <> item_property.describe(error:),
        )
      }),
    )
    case
      inventory.placed(
        items: working,
        item2_id: Item2Id(item2_id),
        size:,
        limit:,
        wanted: amount,
      )
    {
      Error(Nil) -> Error(NoRoom)
      Ok(#(grow, make)) ->
        Ok(
          #(after(items: working, item2_id: Item2Id(item2_id), grow:, make:), [
            store.Placed(item2_id: Item2Id(item2_id), grow:, make:),
            ..placed
          ]),
        )
    }
  })
  |> result.map(fn(done) { list.reverse(done.1) })
}

/// The items after stacks grow and new stacks are made (a made stack has no guid yet, 0).
fn after(
  items items: List(HeldItem),
  item2_id item2_id: Item2Id,
  grow grow: List(store.StackGrowth),
  make make: List(store.NewStack),
) -> List(HeldItem) {
  list.append(
    inventory.grown(items:, grow:),
    list.map(make, fn(stack) {
      HeldItem(
        item_guid: 0,
        item2_id:,
        location: stack.location,
        bag_index: stack.bag_index,
        stack_count: stack.stack_count,
        random_stats: stack.random_stats,
      )
    }),
  )
}

/// The reward kinds the quest has that the server does not build, one line for each kind (its
/// log key and text), in the order of their issues.
fn left_out(
  quest_id quest_id: Int,
  row row: Quest2,
  given given: List(Quest2Reward),
) -> List(#(String, String)) {
  let has = fn(types: List(Int)) {
    list.any(given, fn(reward) {
      list.contains(types, reward.quest2_reward_type_id)
    })
  }
  let line = fn(kind: String, issue: String) {
    "quest "
    <> int.to_string(quest_id)
    <> " has "
    <> kind
    <> " the server does not give yet ("
    <> issue
    <> "); the turn-in goes on without it"
  }
  let kinds = [
    #(
      row.faction2_id_reward_reputation00 != 0
        || row.faction2_id_reward_reputation01 != 0
        || has([reputation_type]),
      #("reputation reward", line("a reputation reward", "#674")),
    ),
    #(
      list.any(given, fn(reward) {
        reward.quest2_reward_type_id == money_type && !is_credits(reward)
      })
        || has([account_currency_type]),
      #("currency reward", line("a reward of a currency but credits", "#675")),
    ),
    #(
      has([rotation_essence_type]),
      #("rotation essence reward", line("a rotation essence reward", "#676")),
    ),
    #(
      has([tradeskill_experience_type, tradeskill_grant_type]),
      #("tradeskill reward kind", line("a tradeskill reward", "#677")),
    ),
    #(
      int.bitwise_and(row.flags, quest.contract_flag) != 0,
      #("contract reward", line("a contract reward", "#678")),
    ),
  ]
  let unknown =
    list.filter(given, fn(reward) {
      !list.contains(
        [
          item_type,
          reputation_type,
          money_type,
          tradeskill_experience_type,
          tradeskill_grant_type,
          account_currency_type,
          rotation_essence_type,
        ],
        reward.quest2_reward_type_id,
      )
    })
  let known =
    list.filter_map(kinds, fn(kind) {
      case kind.0 {
        True -> Ok(kind.1)
        False -> Error(Nil)
      }
    })
  case unknown {
    [] -> known
    [reward, ..] ->
      list.append(known, [
        #(
          "unknown reward type",
          "quest "
            <> int.to_string(quest_id)
            <> " has a reward of type "
            <> int.to_string(reward.quest2_reward_type_id)
            <> ", which the client's tables do not name for the server; the turn-in goes on without it",
        ),
      ])
  }
}

/// The bytes of entropy the turn-in needs to roll the stats of the items it makes: the roll
/// of each made stack, in the order of the placed items.
pub fn entropy_needed(
  turn_in turn_in: TurnIn,
  tables tables: table_store.Tables,
) -> Int {
  list.fold(turn_in.placed, 0, fn(sum, one) {
    sum
    + random_stat.stacks_bytes(
      tables:,
      item2_id: one.item2_id.value,
      stacks: one.make,
    )
  })
}

/// The turn-in with each made stack rolled from `entropy`, which is `entropy_needed` long.
pub fn rolled(
  turn_in turn_in: TurnIn,
  tables tables: table_store.Tables,
  entropy entropy: BitArray,
) -> TurnIn {
  let #(_, placed) =
    list.map_fold(turn_in.placed, entropy, fn(left, one) {
      let #(make, left) =
        random_stat.roll_stacks(
          tables:,
          item2_id: one.item2_id.value,
          stacks: one.make,
          entropy: left,
        )
      #(left, store.Placed(..one, make:))
    })
  TurnIn(..turn_in, placed:)
}

/// The request that asks the store to save the turn-in with the place save.
pub fn request(
  turn_in turn_in: TurnIn,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  session_epoch session_epoch: SessionEpoch,
  save_sequence save_sequence: Int,
  place place: Place,
  health health: Option(Int),
  quests quests: List(store.QuestRow),
) -> store.Request {
  store.Items(store.TurnInQuest(
    account_id:,
    character_id:,
    session_epoch:,
    save_sequence:,
    place:,
    health:,
    experience: turn_in.credited.progress.experience,
    level: turn_in.credited.progress.level,
    quests:,
    credits_held: turn_in.credits_held,
    credits_after: turn_in.credits_after,
    placed: turn_in.placed,
  ))
}

/// What the store's answer leaves. Only the three answers to a turn-in come: the others are
/// answers to other requests, and the connection takes them as an answer it did not ask for.
pub fn answered(
  turn_in turn_in: TurnIn,
  items items: List(HeldItem),
  currencies currencies: Currencies,
  answer answer: ItemsAnswer,
) -> Answered {
  case answer {
    store.TurnedIn(credits:, made:) -> {
      let grow = list.flat_map(turn_in.placed, fn(one) { one.grow })
      let credits_changed =
        credits
        != currency.held(currencies:, currency_type_id: currency.credits_type)
      Saved(
        items: list.append(inventory.grown(items:, grow:), made),
        currencies: currency.with_amount(
          currencies:,
          currency_type_id: currency.credits_type,
          total: credits,
        ),
        rewards: list.map(
          list.append(
            list.map(made, fn(stack) {
              inventory.item_added_frame(
                item_guid: stack.item_guid,
                item_id: stack.item2_id.value,
                location: stack.location,
                bag_index: stack.bag_index,
                stack_count: stack.stack_count,
                random_stats: stack.random_stats,
                reason: quest_reason,
              )
            }),
            list.map(grow, fn(growth) {
              inventory.count_changed_frame(
                guid: growth.item_guid,
                count: growth.new_count,
                reason: quest_reason,
              )
            }),
          ),
          Send,
        ),
        then: list.map(
          case credits_changed {
            True ->
              currency.total_frames(
                currency_type_id: currency.credits_type,
                before: currency.held(
                  currencies:,
                  currency_type_id: currency.credits_type,
                ),
                total: credits,
              )
            False -> []
          }
            |> list.append([
              quest_log.quest_state_frame(
                quest_id: turn_in.quest_id,
                state: 3,
                objective_id: 0,
              ),
            ]),
          Send,
        ),
      )
    }
    ItemsNotSaved ->
      NotSaved([
        Log(
          level: LogWarning,
          text: not_turned_in(turn_in:)
            <> " was not saved: the character's rows were not as the turn-in held them, or a later login took its place; nothing changed",
        ),
      ])
    SaveRefused(constraint:) ->
      NotSaved([
        Log(
          level: LogError,
          text: not_turned_in(turn_in:)
            <> " was not saved: the store refused the change by the constraint "
            <> constraint
            <> "; nothing changed",
        ),
      ])
    store.ItemsSaved | store.ItemMade(..) | store.Bought(..) | store.Sold(..) ->
      panic as "the store answers a turn-in with TurnedIn, ItemsNotSaved or SaveRefused"
  }
}

/// Which turn-in a log line is about.
pub fn not_turned_in(turn_in turn_in: TurnIn) -> String {
  "the turn-in of quest " <> int.to_string(turn_in.quest_id)
}
