//// The decode of a Quest2Reward row's type and object into one kind
//// (genesis_prime/game/quest_reward_kind). Expected values and their sources:
//// - `Quest2Reward.quest2RewardTypeId`: the type of a row is 1 an item, 2 reputation, 3
////   money whose object is a currency type, 4 tradeskill experience, 5 a new tradeskill, 7
////   an account currency, 10 rotation essence; types 6, 8 and 9 have no rows. The client's
////   native code names only type 1 (`0x140551c60`); the rest go to Lua (`0x140665c80`).
//// - `lua.Money.CodeEnumCurrencyType`: a money row's object 1 is the credits, 2 Renown.
//// - The rows of the client's table, counted from the extracted table: 5,415 rows, 4,021 of
////   type 1, 228 of 2, 691 of 3, 378 of 4, 1 of 5, 10 of 7 and 86 of 10.

import client_tables
import genesis_prime/game/currency_kind.{Credits, NoCurrency, Other, Renown}
import genesis_prime/game/quest_reward_kind.{
  type Kind, AccountCurrency, Item, Money, Reputation, RotationEssence,
  TradeskillExperience, TradeskillGrant, Unread,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/quest2_reward
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import unitest

/// An object no row needs to hold: the kind must carry it through.
const object = 7777

pub fn each_type_the_client_tables_use_decodes_to_its_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  let of = fn(type_number) {
    quest_reward_kind.kind_of(type_number:, object_id: object)
  }
  assert of(1) == Item(item2_id: Item2Id(object))
    as "Quest2Reward.quest2RewardTypeId: 1 is an item, 0x140551c60 the only type the native code names; the object is its Item2 id"
  assert of(2) == Reputation
    as "Quest2Reward.quest2RewardTypeId: 2 is reputation"
  assert of(3) == Money(currency: Other(number: object))
    as "Quest2Reward.quest2RewardTypeId: 3 is money, whose object is a currency type"
  assert of(4) == TradeskillExperience
    as "Quest2Reward.quest2RewardTypeId: 4 is tradeskill experience"
  assert of(5) == TradeskillGrant
    as "Quest2Reward.quest2RewardTypeId: 5 grants a tradeskill"
  assert of(7) == AccountCurrency
    as "Quest2Reward.quest2RewardTypeId: 7 is an account currency"
  assert of(10) == RotationEssence
    as "Quest2Reward.quest2RewardTypeId: 10 is rotation essence"
}

pub fn a_type_with_no_variant_carries_its_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let unread = [0, 6, 8, 9, 11, 12, 99, -1]
  assert list.map(unread, fn(type_number) {
      quest_reward_kind.kind_of(type_number:, object_id: object)
    })
    == list.map(unread, fn(type_number) { Unread(type_number:) })
    as "Quest2Reward.quest2RewardTypeId: 6, 8 and 9 have no rows and no table names 0 or 11, so each carries its number to an error line"
}

pub fn a_money_row_carries_its_currency_test() -> Nil {
  use <- owned_test.run(10_000)
  let of = fn(object_id) {
    quest_reward_kind.kind_of(type_number: 3, object_id:)
  }
  assert of(1) == Money(currency: Credits)
    as "lua.Money.CodeEnumCurrencyType: currency 1 is the credits"
  assert of(2) == Money(currency: Renown)
    as "lua.Money.CodeEnumCurrencyType: currency 2 is Renown"
  assert of(4) == Money(currency: Other(number: 4))
    as "currency 4 is no kind the server reads"
  assert of(0) == Money(currency: NoCurrency) as "no currency"
}

pub fn only_an_item_row_gives_an_item_test() -> Nil {
  use <- owned_test.run(10_000)
  let given = fn(type_number) {
    quest_reward_kind.given_item(quest_reward_kind.kind_of(
      type_number:,
      object_id: object,
    ))
  }
  assert given(1) == Ok(Item2Id(object))
    as "0x140551c60: a row of type 1 is an item and its object the Item2 id"
  assert list.map([0, 2, 3, 4, 5, 6, 7, 10], given)
    == list.repeat(Error(Nil), 8)
    as "no other type names an item: its object is a currency, a faction or nothing"
}

pub fn only_an_unread_type_gives_its_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let unread = fn(type_number) {
    quest_reward_kind.unread_type(quest_reward_kind.kind_of(
      type_number:,
      object_id: object,
    ))
  }
  assert list.map([0, 6, 8, 9, 11], unread)
    == [Ok(0), Ok(6), Ok(8), Ok(9), Ok(11)]
    as "a type with no variant gives its number to the error line that names it"
  assert list.map([1, 2, 3, 4, 5, 7, 10], unread) == list.repeat(Error(Nil), 7)
    as "Quest2Reward.quest2RewardTypeId: the types the code reads have a variant, so no number to name"
}

/// A name for each variant the counts below are made by.
fn label(kind: Kind) -> String {
  case kind {
    Item(_) -> "item"
    Reputation -> "reputation"
    Money(_) -> "money"
    TradeskillExperience -> "tradeskill experience"
    TradeskillGrant -> "tradeskill grant"
    AccountCurrency -> "account currency"
    RotationEssence -> "rotation essence"
    Unread(_) -> "unread"
  }
}

fn counted(labels labels: List(String)) -> List(#(String, Int)) {
  list.fold(labels, dict.new(), fn(counts, label) {
    dict.upsert(counts, label, fn(count) {
      case count {
        Some(count) -> count + 1
        None -> 1
      }
    })
  })
  |> dict.to_list
  |> list.sort(by: fn(a, b) { int.compare(b.1, a.1) })
}

pub fn every_reward_row_of_the_client_decodes_to_a_variant_the_code_reads_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let rows = quest2_reward.all(client_tables.shared())
  let kinds = list.map(rows, quest_reward_kind.of_row)
  assert list.length(rows) == 5415
    as "Quest2Reward.quest2RewardTypeId: the extracted table holds 5,415 rows"
  assert counted(labels: list.map(kinds, label))
    == [
      #("item", 4021),
      #("money", 691),
      #("tradeskill experience", 378),
      #("reputation", 228),
      #("rotation essence", 86),
      #("account currency", 10),
      #("tradeskill grant", 1),
    ]
    as "Quest2Reward.quest2RewardTypeId: the counts of types 1, 3, 4, 2, 10, 7 and 5; no row is unread"
  let currencies =
    list.filter_map(kinds, fn(kind) {
      case kind {
        Money(currency:) -> Ok(currency)
        Item(_)
        | Reputation
        | TradeskillExperience
        | TradeskillGrant
        | AccountCurrency
        | RotationEssence
        | Unread(_) -> Error(Nil)
      }
    })
  assert list.count(currencies, fn(currency) { currency == Credits }) == 1
    as "Quest2Reward.quest2RewardTypeId: one money row is of currency 1"
  assert list.count(currencies, fn(currency) { currency == Renown }) == 31
    as "Quest2Reward.quest2RewardTypeId: 31 money rows are of currency 2"
  assert list.count(currencies, fn(currency) { currency == Other(number: 4) })
    == 577
    as "Quest2Reward.quest2RewardTypeId: 577 money rows are of currency 4"
}
