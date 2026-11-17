//// The kind of a Quest2Reward row, decoded once from its type and object: the one place
//// the server names the numbers of the client's reward types. A rule that sorts rewards
//// matches on `Kind`, so a type that gains a variant names every place that must handle
//// it. Each variant carries what the row's object names for its type; types with no
//// variant are `Unread`.
////
//// ```text
//// Quest2Reward row (type, object) -> kind_of / of_row -> Kind -> a rule's case
//// ```
////
//// - The client has no table of reward types. Its native code reads only whether the type
////   is 1, an item (`0x140551c60`), and passes the rest to Lua as the reward's type
////   (`0x140665c80`). The names and counts of the other types are the server's, read from
////   the rows of the client's table (`Quest2Reward.quest2RewardTypeId`): 1 an item, 2
////   reputation, 3 money (the object is a currency type), 4 tradeskill experience, 5 a new
////   tradeskill, 7 an account currency, 10 rotation essence; types 6, 8 and 9 have no
////   rows.
//// - A money row's object is its currency type, decoded by `currency_kind`
////   (`lua.Money.CodeEnumCurrencyType`).
//// - A rule that wants one kind's data asks an accessor (`given_item`), the only place
////   that lists every kind for its question.
//// - This module imports only the generated tables, typed ids and `currency_kind`, so any
////   game module can name a kind.

import genesis_prime/game/currency_kind
import genesis_prime/table/id.{type Item2Id, Item2Id}
import genesis_prime/table/quest2_reward.{type Quest2Reward}

/// What a rule reads a Quest2Reward row as.
pub type Kind {
  /// Type 1: an item (`0x140551c60`); the object is an Item2 id.
  Item(item2_id: Item2Id)
  /// Type 2: reputation (`Quest2Reward.quest2RewardTypeId`).
  Reputation
  /// Type 3: money (`Quest2Reward.quest2RewardTypeId`); the object is a currency type.
  Money(currency: currency_kind.Kind)
  /// Type 4: tradeskill experience (`Quest2Reward.quest2RewardTypeId`).
  TradeskillExperience
  /// Type 5: a new tradeskill (`Quest2Reward.quest2RewardTypeId`), one row in the client's
  /// table.
  TradeskillGrant
  /// Type 7: an account currency (`Quest2Reward.quest2RewardTypeId`).
  AccountCurrency
  /// Type 10: rotation essence (`Quest2Reward.quest2RewardTypeId`).
  RotationEssence
  /// Any other type: no row of the client's table has 6, 8 or 9, and none has 0 or 11 or
  /// over; the number is kept for the line that names it.
  Unread(type_number: Int)
}

/// The kind of a reward of type `type_number` with `object_id`
/// (`Quest2Reward.quest2RewardTypeId`, `Quest2Reward.objectId`).
pub fn kind_of(type_number type_number: Int, object_id object_id: Int) -> Kind {
  case type_number {
    1 -> Item(item2_id: Item2Id(object_id))
    2 -> Reputation
    3 -> Money(currency: currency_kind.kind_of(number: object_id))
    4 -> TradeskillExperience
    5 -> TradeskillGrant
    7 -> AccountCurrency
    10 -> RotationEssence
    other -> Unread(type_number: other)
  }
}

/// The kind of a Quest2Reward row.
pub fn of_row(row: Quest2Reward) -> Kind {
  kind_of(type_number: row.quest2_reward_type_id, object_id: row.object_id)
}

/// The item a reward gives: type 1 (`0x140551c60`), the only type whose object is an item.
pub fn given_item(kind: Kind) -> Result(Item2Id, Nil) {
  case kind {
    Item(item2_id:) -> Ok(item2_id)
    Reputation
    | Money(_)
    | TradeskillExperience
    | TradeskillGrant
    | AccountCurrency
    | RotationEssence
    | Unread(_) -> Error(Nil)
  }
}

/// The type number of a reward the server does not read, for the log line that names it.
pub fn unread_type(kind: Kind) -> Result(Int, Nil) {
  case kind {
    Unread(type_number:) -> Ok(type_number)
    Item(_)
    | Reputation
    | Money(_)
    | TradeskillExperience
    | TradeskillGrant
    | AccountCurrency
    | RotationEssence -> Error(Nil)
  }
}
