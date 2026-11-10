//// The player's turn-in of a quest, the client's 0x035D: a feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in the world. The
//// sequence is genesis_prime/game/connection/quest_turn_in's.
////
//// ```
//// 0x35D {quest, reward, by communicator} ─▶ take(body, asker, standing, picture, progress, currencies, ...)
////                                           ├─ refused ─▶ Refused([Log])  or  Refused([Refuse(27)])   nothing asked, nothing changed
////                                           └─ accepted ─▶ Asks(turn_in) ─▶ the connection asks the store (request(..))
//// the store's answer ─▶ answered(turn_in, items, currencies, answer)
////                       TurnedIn(credits, made): the log has the quest Completed, the items, the credits, the
////                                                experience and the level are saved; 0x111, the count changes,
////                                                0x1ac, 0x938 with the Level news, 0x919, then 0x35C {quest, 3, 0}
////                       ItemsNotSaved:           Warning, nothing sent, nothing changed (the quest stays Achieved)
////                       SaveRefused(c):          Error naming c, nothing sent, nothing changed
//// ```
////
//// - **The checks, in the order of the client's turn-in** (`opcode.0x35d`), each a log line
////   once per reason on the connection, because the client sends the message only from a dialog
////   it built from the same tables, so a refusal is a modified or stale client or a gap this
////   server has; the first that fails answers:
////   1. a body the client's reader refuses ends the connection (`NotDecoded`)
////   2. the quest has no Quest2 row, or a row the client's quest reader refuses
////   3. the log's state for it is not Achieved (4), unless the quest auto-completes (Quest2
////      flags bit 0): it is then taken as `quest.can_accept` takes an accept with the log-full
////      bit masked, and goes from no entry, or a Known one, straight to Completed
////   4. the receiver: a shown creature alive, not Hostile to the player, within reach, whose
////      Creature2 row receives the quest (`spawn.received_quest_ids`, through `quest.in_reach`);
////      with the by-communicator bit set, the communicator's check instead: the quest has flags
////      8, or flags 0x10000 with a CommunicatorMessages row delivering it, and some creature that
////      receives it has a faction that is not Hostile to the player's
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
////   currencies, account currency, rotation essence) are logged once per kind and the turn-in
////   goes on.
//// - **Where the items go** is `inventory.placed`: the stacks below the limit first, then the
////   lowest empty usable slots, each Item2 against the items as the one before it left them.
//// - **The save** is the whole turn-in in the one transaction of the store's request: the
////   character's row lock, the place save carrying the log with the quest Completed, the
////   experience and the level, then the credits and the items, so storage holds the whole
////   turn-in or none of it.
//// - **The frames, in this order** (a server choice; the client needs only 0x35C last): 0x111
////   (reason 8) for each stack made, a count change for each stack grown, 0x1ac of kind 3 when
////   the gain is above 0, 0x938 of the level and the Level news when it rose, 0x919 when the
////   credits changed, then 0x35C with state 3.
////
//// | Point | What happens |
//// |---|---|
//// | the quest's Quest2, Quest2Reward, Item2 or CommunicatorMessages row a check reads is missing | the connection ends |
//// | the store changes nothing or refuses a place | a warning, nothing sent, the quest stays Achieved |
//// | the connection ends while the store works | the store finishes or rolls back; the next login loads whichever |
//// | the same message while the store works | held, then taken against the new log |

import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/experience
import genesis_prime/game/quest
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/vendor_trade.{type Effect}
import genesis_prime/message/quest_turn_in as quest_turn_in_message
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemsAnswer,
  type SessionEpoch,
}
import genesis_prime/table/loader/store as table_store
import gleam/option.{type Option}
import gleam/set.{type Set}

/// The id of the message this rule takes.
pub const message_id = quest_turn_in_message.message_id

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
  /// items) and after it (0x919 and 0x35C).
  Saved(
    items: List(HeldItem),
    currencies: Currencies,
    rewards: List(Effect),
    then: List(Effect),
  )
  /// Not saved: the effects (a log line), and nothing changed.
  NotSaved(effects: List(Effect))
}

/// What the client's 0x035D is answered with: a refusal, or the turn-in to ask the store to
/// save. `Error` ends the connection: a body the client's reader refuses, or a table row a
/// check reads that is missing.
pub fn take(
  body _body: BitArray,
  asker _asker: quest.Asker,
  standing _standing: quest.Standing,
  picture _picture: Picture,
  progress _progress: experience.Progress,
  currencies _currencies: Currencies,
  item_proficiencies _item_proficiencies: Int,
  tables _tables: table_store.Tables,
  now_ms _now_ms: Int,
  unix_seconds _unix_seconds: Int,
  logged _logged: Set(String),
) -> Result(Taken, quest.Refusal) {
  panic as "shape: #593"
}

/// The store's request for the turn-in, numbered `save_sequence` and carrying the
/// character's place and `health`.
pub fn request(
  turn_in _turn_in: TurnIn,
  account_id _account_id: AccountId,
  character_id _character_id: CharacterId,
  session_epoch _session_epoch: SessionEpoch,
  save_sequence _save_sequence: Int,
  place _place: Place,
  health _health: Option(Int),
  quests _quests: List(store.QuestRow),
) -> store.Request {
  panic as "shape: #593"
}

/// What the store's answer leaves: the items and the amounts held, and the effects, in order.
pub fn answered(
  turn_in _turn_in: TurnIn,
  items _items: List(HeldItem),
  currencies _currencies: Currencies,
  answer _answer: ItemsAnswer,
) -> Answered {
  panic as "shape: #593"
}

/// What the log line of a failed answer starts with.
pub fn not_turned_in(turn_in _turn_in: TurnIn) -> String {
  panic as "shape: #593"
}
