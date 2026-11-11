//// What an item's own rows say of a bag (`genesis_prime/game/item_property`).
//// Expected values come from these places.
//// - `Item2.bags` and `0x1404445d0.proxy`: a bag is an item whose joined flags
////   (type, category and family) hold 0x100, and it opens Item2.maxStackCount
////   inventory slots; the client gives an item whose Item2.flags hold 0x4000 the
////   joined flags 0x10004 and the equipped slot flags 0, so such a proxy is no
////   bag.
//// - The Item2 rows are the client's own, roots of the fixture: 4753 holds 4
////   and has equipped slot flags 0x7FFE0000 (bag indexes 17 to 30), 5423 holds 8
////   (it needs level 18), 4763 is a proxy whose row holds 4 as maxStackCount, and
////   the Novice chest piece is armor.
//// - What a budget gives: the client's code of `AddItemBudgetProperties`
////   (0x14040ca70 to 0x14040db30) and the budget curve (0x14041e670) run on the
////   Item2, ItemBudget, ItemStat, ItemSlot, GameFormula and UnitProperty2 rows each
////   test names; every product is rounded to 32 bits as the client's code rounds it.

import client_tables
import fixture_tables
import game_connection_support
import genesis_prime/game/item_property.{type ItemProperties, ItemProperties}
import genesis_prime/message/float32
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId, UnitProperty2Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import planted_table.{Integer}
import unitest
import world_entry_support

pub fn a_bag_is_a_non_proxy_item_whose_joined_flags_hold_0x100_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let size = fn(item2_id) {
    let assert Ok(size) = item_property.bag_size(tables:, item2_id:)
      as "the item's rows are in the tables"
    size
  }
  assert size(fixture_tables.root("Item2", 4753)) == Some(4)
  assert size(fixture_tables.root("Item2", 5423)) == Some(8)
  let assert [chest, ..] =
    world_entry_support.novice_items(
      character: game_connection_support.world_character(),
    )
    as "the Engineer's set has its chest piece first"
  assert size(chest.item2_id.value) == None
  // The proxy row's own flags say 0x100 through its maxStackCount of 4, and the
  // client's proxy rule drops it.
  let proxy = fixture_tables.root("Item2", 4763)
  assert size(proxy) == None
  let assert Ok(proxy_slots) =
    item_property.equipped_slot_flags(tables:, item2_id: proxy)
  assert proxy_slots == 0
  let assert Ok(bag_slots) =
    item_property.equipped_slot_flags(
      tables:,
      item2_id: fixture_tables.root("Item2", 4753),
    )
  assert bag_slots == 0x7FFE0000
}

/// 5423 holds 8 and has no charges. FillItemInfo (0x140444a27 to 0x140444a45)
/// cuts a bag's size to 1 only when maxStackCount and maxCharges are both above
/// 1; no client row reaches it, so the rows are changed.
pub fn a_bag_that_stacks_and_has_charges_opens_one_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  let bag = fixture_tables.root("Item2", 5423)
  let size = fn(tables) {
    let assert Ok(size) = item_property.bag_size(tables:, item2_id: bag)
      as "the item's rows are in the tables"
    size
  }
  use tables <- fixture_tables.changed(table: "Item2", id: bag, with: [
    #("maxCharges", Integer(2)),
  ])
  assert size(tables) == Some(1)
  use tables <- fixture_tables.changed(table: "Item2", id: bag, with: [
    #("maxCharges", Integer(1)),
  ])
  assert size(tables) == Some(8)
}

/// 11538 sells (its type, category and family flags hold 0x20), 9939's hold no 0x20 (joined
/// 0x10000), 6516 is a Quest Item (Item2Family 24) whose joined flags do hold 0x20 (0x100e4) and
/// 12078 is a proxy, which the client gives the joined flags 0x10004 (`0x1404445d0.proxy`).
pub fn an_item_without_flag_0x20_or_of_the_quest_item_family_is_not_sellable_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let sellable = fn(item2_id) {
    let assert Ok(sellable) = item_property.sellable(tables:, item2_id:)
      as "the item's rows are in the tables"
    sellable
  }
  assert sellable(fixture_tables.root("Item2", 11_538))
    as "0x14040d160.sell_cleared: joined flags with 0x20 and a family other than 24 keep the sell price"
  assert !sellable(fixture_tables.root("Item2", 9939))
    as "0x14040d160.sell_cleared: joined flags 0x10000 lack 0x20, so the price is cleared"
  assert !sellable(fixture_tables.root("Item2", 6516))
    as "0x14040d160.sell_cleared: Item2Family 24 (Quest Item) clears the price whatever the flags hold"
  assert !sellable(fixture_tables.root("Item2", 12_078))
    as "0x14040d160.sell_cleared with 0x1404445d0.proxy: a proxy's joined flags 0x10004 lack 0x20"
  assert item_property.sellable(tables:, item2_id: 1_999_999_999)
    == Error(item_property.NoRow(table: "Item2", id: 1_999_999_999))
    as "a missing Item2 row is an error, not a refusal to sell"
}

pub fn the_client_rule_makes_56437_item2_rows_sellable_and_every_bag_among_them_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let ids = list.map(item2.all(tables), fn(row) { row.id })
  let sellable = fn(item2_id) {
    let assert Ok(sellable) = item_property.sellable(tables:, item2_id:)
      as "every Item2 row has its type, category and family rows"
    sellable
  }
  let bags =
    list.filter(ids, fn(item2_id) {
      let assert Ok(size) = item_property.bag_size(tables:, item2_id:)
        as "every Item2 row has its type, category and family rows"
      size != None
    })
  assert list.length(ids) == 72_106
    as "0x14040d160.sell_cleared: the client's Item2 holds 72,106 rows"
  assert list.length(list.filter(ids, sellable)) == 56_437
    as "0x14040d160.sell_cleared: 56,437 of the 72,106 rows pass the rule and 15,669 do not"
  assert list.length(bags) == 142
    as "item.bags_sellable: the client's Item2 holds 142 bag rows"
  assert list.filter(bags, fn(item2_id) { !sellable(item2_id) }) == []
    as "item.bags_sellable: every bag row is sellable (a worn bag is refused by its location, not by this rule)"
}

// ------------------------------------------------------------------ budgets

/// The properties of an item the tables read in full.
fn given(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> ItemProperties {
  given_with(tables:, item2_id:, random_stats: 0)
}

/// What an item gives with the random-stat word `random_stats`.
fn given_with(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  random_stats random_stats: Int,
) -> ItemProperties {
  let assert Ok(properties) =
    item_property.of_item(tables:, level: 1, item2_id:, random_stats:)
    as "the item's rows are in the tables and the reader follows its branches"
  properties
}

/// The bits of the 32-bit float a budget gave a property, if it gave one.
fn bits(
  properties properties: ItemProperties,
  property_id property_id: Int,
) -> Result(Int, Nil) {
  dict.get(properties.budget, UnitProperty2Id(property_id))
  |> result.map(float32.to_bits)
}

/// The ids of the properties a budget gave, in id order.
fn budget_ids(properties properties: ItemProperties) -> List(Int) {
  dict.keys(properties.budget)
  |> list.map(fn(property_id) { property_id.value })
  |> list.sort(int.compare)
}

/// Whether a value is the source's decimal, to the 32-bit floats' error.
fn close(value value: Float, to expected: Float) -> Bool {
  float.absolute_value(value -. expected) <. 0.001
}

/// The budget of an item is the points of its ItemBudget row times the scale, the budget
/// curve at the power level times the slot's armorModifier, times the property's
/// valuePerPoint, each product rounded to 32 bits (AddItemBudgetProperties 0x14040ca70,
/// 0x14040d060, 0x14040d3d0, 0x14040db30). The expected bits come from the client's code
/// run on the rows (the Client trace of this step).
///
/// Item2 1375 (Scout's Thermal Gloves): ItemBudget 3 gives its one entry the share 1.0,
/// ItemStat 4 names property 34, ItemSlot ArmorHands has armorModifier 0.75, the curve at
/// power level 3 is GameFormula 1028's 8.55 (0x4108cccd), UnitProperty2 34 has
/// valuePerPoint 10: 8.55 x 0.75 x 1.0 x 10 = 64.125 (0x42804000).
pub fn scouts_thermal_gloves_give_crit_chance_rating_64_125_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let gloves = given(tables:, item2_id: fixture_tables.root("Item2", 1375))
  assert bits(properties: gloves, property_id: 34) == Ok(0x42804000)
    as "0x14040db30: property 34, Critical Hit Rating, is 64.125"
  assert budget_ids(properties: gloves) == [34]
    as "ItemStat 4 has no other entry of kind 1"
  // The budget leaves the item's own formulas as they are.
  assert close(value: gloves.assault_rating, to: 8.1)
    && close(value: gloves.armor, to: 45.0)
    && close(value: gloves.base_health, to: 135.0)
    as "0x14040df10, 0x14040e340, 0x14040e3d0: the gloves' own Assault Rating, Armor and Base Health"
}

/// Item2 8441 (Unclean Carver): ItemBudget 8 gives 0.6 and 0.4, ItemStat 20 names
/// properties 34 and 32, ItemSlot WeaponPrimary has armorModifier 0.75, the curve at power
/// level 20 is GameFormula 1028's 14.5.
pub fn unclean_carver_gives_crit_chance_and_strikethrough_ratings_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let carver = given(tables:, item2_id: fixture_tables.root("Item2", 8441))
  assert bits(properties: carver, property_id: 34) == Ok(0x42828000)
    as "0x14040db30: property 34 is 65.25"
  assert bits(properties: carver, property_id: 32) == Ok(0x422e0000)
    as "0x14040db30: property 32 is 43.5"
  assert budget_ids(properties: carver) == [32, 34]
    as "the two entries of ItemStat 20"
}

/// Item2 1156 (Bacchanal Probe): ItemBudget 6 gives 0.7 and 0.3, ItemStat 51 names
/// properties 34 and 47, ItemSlot ArmorSystem has armorModifier 1.0, the curve at power
/// level 36 is the 32-bit 20.1, 0x41a0cccc. The client's products are 0x430cb332 and
/// 0x42713332; the 64-bit products are 0x430cb333 and 0x42713334.
pub fn bacchanal_probe_values_are_the_clients_32_bit_products_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let probe = given(tables:, item2_id: fixture_tables.root("Item2", 1156))
  assert bits(properties: probe, property_id: 34) == Ok(0x430cb332)
    as "0x14040db30: property 34, each product rounded to 32 bits"
  assert bits(properties: probe, property_id: 47) == Ok(0x42713332)
    as "0x14040db30: property 47, each product rounded to 32 bits"
}

/// The budget curve is a GameFormula row chosen by the power level, 1028 below 50, 1027
/// from 50 to 129 and 1255 from 130 (0x14041e670), at the level less the row's start
/// (m = L, L - 50, L - 130). Item2 8441's budget at those levels, each product rounded
/// to 32 bits as the client's code gives it, the power through the client's powf
/// (0x1408fbfc0) of the 32-bit e, 2.7182817; the values at levels 75 and 129 are the
/// client's code emulated on these rows.
pub fn the_budget_curve_changes_row_at_power_levels_50_and_130_test() -> Nil {
  use <- owned_test.run(10_000)
  let at_level = fn(level) {
    use tables <- fixture_tables.changed(
      table: "Item2",
      id: fixture_tables.root("Item2", 8441),
      with: [#("powerLevel", Integer(level))],
    )
    let carver = given(tables:, item2_id: fixture_tables.root("Item2", 8441))
    #(
      bits(properties: carver, property_id: 34),
      bits(properties: carver, property_id: 32),
    )
  }
  assert at_level(49) == #(Ok(0x42ddd999), Ok(0x4293e666))
    as "0x14041e670: level 49 is GameFormula 1028 at m 49"
  assert at_level(50) == #(Ok(0x42e10000), Ok(0x42960000))
    as "0x14041e670: level 50 is GameFormula 1027 at m 0, 112.5 and 75.0"
  assert at_level(75) == #(Ok(0x4317dbef), Ok(0x42ca7a93))
    as "0x14040db30: level 75 is GameFormula 1027 at m 25; the curve is 0x4206fc62 (0x14041e670, powf 0x1408fbfc0)"
  assert at_level(129) == #(Ok(0x439127d3), Ok(0x43418a6e))
    as "0x14040db30: level 129 is GameFormula 1027 at m 79; the curve is 0x428106f4 (0x14041e670, powf 0x1408fbfc0)"
  assert at_level(130) == #(Ok(0x440d04cd), Ok(0x43bc0666))
    as "0x14041e670: level 130 is GameFormula 1255 at m 0"
}

/// Item2 16397 has ItemBudget 3 (1.0 and 0.0) and ItemStat 54, which names property 29 and
/// property 0, Strength. UnitProperty2 0 has valuePerPoint 0, so its value is 0 and
/// AddItemProperty adds no entry (0x14040db30). The item is run twice, the second time
/// with a share on the second entry, so that the 0 is the property's and not the
/// share's.
pub fn a_property_worth_0_per_point_gives_no_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 16_397)
  let tables = fixture_tables.shared()
  let item = given(tables:, item2_id:)
  assert bits(properties: item, property_id: 29) == Ok(0x43340000)
    as "0x14040db30: property 29 is 180.0"
  assert budget_ids(properties: item) == [29]
    as "no entry for Strength, whose value is 0"
  use tables <- fixture_tables.changed(table: "ItemBudget", id: 3, with: [
    #("budget01", planted_table.Float(0.5)),
  ])
  let shared = given(tables:, item2_id:)
  assert budget_ids(properties: shared) == [29]
    as "0x14040db30: a share on Strength still gives 0 points of value"
}

/// A budget value and an innate value on one property add (0x14040db30 adds onto the
/// property's entry, and 0x14040ca70 runs before 0x14040df10). Item2 8441's ItemStat 20
/// names property 34 and 32; with the first changed to 35, Assault Rating, the item
/// gives its own 1670.625 and the budget's 65.25, which is 1735.875 as the 32-bit
/// float 0x44d8fc00.
pub fn a_budget_value_and_an_innate_value_on_one_property_add_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 8441)
  let innate = given(tables: fixture_tables.shared(), item2_id:)
  assert close(value: innate.assault_rating, to: 1670.625)
    as "0x14040df10: the carver's own Assault Rating"
  use tables <- fixture_tables.changed(table: "ItemStat", id: 20, with: [
    #("itemStatData00", Integer(35)),
  ])
  let both = given(tables:, item2_id:)
  assert float32.to_bits(both.assault_rating) == 0x44d8fc00
    as "0x14040db30: 1670.625 and 65.25 add on property 35"
  assert budget_ids(properties: both) == [32]
    as "property 35 is Assault Rating, which the item's own field holds"
}

/// Item2 8829 is a shield, with ItemBudget 47 (0.5, 0, 0.75, 0.75) and ItemStat 139, which names
/// 41, 175, 176 and 178. The shares replace the 0.5 of the factors in 0x14040dbf0: the
/// capacity at GameFormula 1260's range half way (2250), the mitigation at the bottom of
/// GameFormula 1261's, 0.25, the regeneration at three quarters of 1260's, 0.2, and the
/// reboot time at three quarters of 1261's range, 2687.
pub fn a_shields_budget_shares_replace_the_middle_of_its_factor_ranges_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let shield = given(tables:, item2_id: fixture_tables.root("Item2", 8829))
  let assert Some(item_property.Shield(
    capacity_max:,
    mitigation_max:,
    regen_percent:,
    reboot_time_ms:,
  )) = shield.shield
    as "0x14040dbf0: the item is a shield"
  assert close(value: capacity_max, to: 2250.0)
    && close(value: mitigation_max, to: 0.25)
    && close(value: regen_percent, to: 0.2)
    && reboot_time_ms == 2687
    as "0x14040dbf0: the shares 0.5, 0, 0.75 and 0.75 in place of the middle"
  assert budget_ids(properties: shield) == []
    as "0x14040db30: the shield properties are given by the shield, not as budget values"
}

/// A shield property (41, 175, 176, 178) on an item that is no shield fails the client's
/// branch (0x14040db30, 0x95): the item is refused, not worth 0. Item2 1375 (gloves) with
/// ItemStat 4 changed to name property 41.
pub fn a_shield_property_on_an_item_that_is_no_shield_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 1375)
  use tables <- fixture_tables.changed(table: "ItemStat", id: 4, with: [
    #("itemStatData00", Integer(41)),
  ])
  assert item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0)
    == Error(item_property.Refused(
      item2_id:,
      property_id: 41,
      why: item_property.ShieldPropertyOnNonShield,
    ))
    as "0x14040db30: a shield property on a non-shield"
}

/// A property whose UnitProperty2.flags lack 4 is no item property, and one whose
/// equippedSlotFlags share no bit with the item's slot is not for the item (0x14040db30,
/// 0x95). Item2 1375 is a glove (slot flags 0x20); property 30's flags are 0.
pub fn a_property_without_flag_4_or_off_the_items_slot_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 1375)
  let without_flag = {
    use tables <- fixture_tables.changed(table: "ItemStat", id: 4, with: [
      #("itemStatData00", Integer(30)),
    ])
    item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0)
  }
  assert without_flag
    == Error(item_property.Refused(
      item2_id:,
      property_id: 30,
      why: item_property.NotAnItemProperty,
    ))
    as "0x14040db30: UnitProperty2 30's flags are 0, without bit 4"
  use tables <- fixture_tables.changed(table: "UnitProperty2", id: 34, with: [
    #("equippedSlotFlags", Integer(1)),
  ])
  assert item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0)
    == Error(item_property.Refused(
      item2_id:,
      property_id: 34,
      why: item_property.OffTheItemsSlot,
    ))
    as "0x14040db30: slot flags 1 share no bit with the gloves' 0x20"
}

/// 0x14040ca70 fails with 0x95 when the ItemStat row or the ItemBudget row is missing, and
/// a 0 id has no row. An item with neither id has no budget and gives its own values. No
/// client row holds one id alone, so the rows are Item2 1375 (ItemBudget 3, ItemStat 4)
/// with one id changed to 0.
pub fn a_budget_id_or_a_stat_id_of_0_while_the_other_is_set_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 1375)
  use tables <- fixture_tables.changed(table: "Item2", id: item2_id, with: [
    #("itemBudgetId", Integer(0)),
  ])
  assert item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0)
    == Error(item_property.NoRow(table: "ItemBudget", id: 0))
    as "0x14040ca70: a stat with no budget row is refused"
  use tables <- fixture_tables.changed(table: "Item2", id: item2_id, with: [
    #("itemStatId", Integer(0)),
  ])
  assert item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0)
    == Error(item_property.NoRow(table: "ItemStat", id: 0))
    as "0x14040ca70: a budget with no stat row is refused"
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Item2",
      id: item2_id,
      with: [#("itemBudgetId", Integer(0)), #("itemStatId", Integer(0))],
    )
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let none = given(tables:, item2_id:)
  assert budget_ids(properties: none) == []
    as "an item with neither id has no budget"
}

/// A ResourceMax property is the one of the client's eleven slots, UnitProperty2 9 to 15,
/// 38, 50, 52 and 54 (`unit_fields.resource_max_property`, 0x140466360), whatever its row
/// is named. UnitProperty2 12 renamed is still a resource maximum a budget leaves to the
/// class resource and no budget property of the gear; 34 renamed with the prefix is
/// still the Critical Hit Rating Scout's Thermal Gloves give.
pub fn a_resource_maximum_is_one_of_the_clients_slot_properties_whatever_its_name_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 1375)
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "UnitProperty2",
      id: 12,
      with: [#("enumName", planted_table.Text("Renamed"))],
    )
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "ItemStat", id: 4, with: [
      #("itemStatData00", Integer(12)),
    ])
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  assert item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0)
    == Error(item_property.Unread(item2_id:, gap: item_property.ResourceMaximum))
    as "UnitProperty2 12 is slot 3's maximum by the client's map"
  assert !list.contains(
    list.map(item_property.budget_properties(tables:), fn(id) { id.value }),
    12,
  )
    as "the gear lists no base for a resource maximum"
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "UnitProperty2",
      id: 34,
      with: [#("enumName", planted_table.Text("ResourceMax_Renamed"))],
    )
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  assert bits(properties: given(tables:, item2_id:), property_id: 34)
    == Ok(0x42804000)
    as "34 is no slot's maximum, so the gloves still give 64.125"
  assert list.contains(
    list.map(item_property.budget_properties(tables:), fn(id) { id.value }),
    34,
  )
    as "and the gear lists its base"
}

/// The properties of a set add in 32 bits, as the client's single-precision add gives
/// (IEEE 754 binary32): 16777216.0 is 2^24, past which a 32-bit float holds only even
/// numbers, so 2^24 + 1.0 is 2^24 again, where a 64-bit sum would hold 16777217.0.
pub fn the_sum_of_a_set_adds_in_32_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  let item = fn(value) {
    ItemProperties(
      base_health: value,
      assault_rating: value,
      support_rating: value,
      armor: value,
      shield: None,
      budget: dict.from_list([#(UnitProperty2Id(34), value)]),
    )
  }
  let assert Ok(total) =
    item_property.sum(items: [item(16_777_216.0), item(1.0)])
  assert total == item(16_777_216.0)
    as "2^24 + 1.0 is 2^24 in every sum of the set, the budget's included"
}

/// A budget entry on a ResourceMax property is left to the class resource, which sets that
/// property's base (`genesis_prime/game/class_resource`, the player unit's resource).
/// UnitProperty2 12 is ResourceMax_3, with flags 52 and valuePerPoint 0.2, so a client
/// row would give it; the code does not, and says why, naming no open issue.
pub fn a_resource_maximum_from_a_budget_is_unread_with_its_reason_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 1375)
  use tables <- fixture_tables.changed(table: "ItemStat", id: 4, with: [
    #("itemStatData00", Integer(12)),
  ])
  let result =
    item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0)
  assert result
    == Error(item_property.Unread(item2_id:, gap: item_property.ResourceMaximum))
    as "UnitProperty2 12 is a ResourceMax property"
  let assert Error(error) = result
  assert string.contains(item_property.describe(error:), "class resource")
    as "the reason says the class resource sets that base"
  assert item_property.gap_issue(gap: item_property.ResourceMaximum) == None
    as "no open issue closes it: the class resource sets that base by design"
}

/// What an item gives for a wearer of `level`.
fn given_at(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  level level: Int,
) -> ItemProperties {
  let assert Ok(properties) =
    item_property.of_item(tables:, level:, item2_id:, random_stats: 0)
    as "the item's rows are in the tables and the reader follows its branches"
  properties
}

/// Item2 29495 is an armor item of power level 49 with no budget, below GameFormula
/// 1286's dataint0, 50: its armor is the 20 per level of the first curve (GameFormula 547)
/// times the category's and the slot's armor modifiers (0x14041deb0): 49 x 20 x 0.9375 =
/// 918.75 (0x4465b000), the client's code run on this row.
pub fn armor_below_level_50_is_20_per_level_times_the_modifiers_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item = given(tables:, item2_id: fixture_tables.root("Item2", 29_495))
  assert float32.to_bits(item.armor) == 0x4465b000
    as "0x14041deb0: Armor 918.75 below power level 50"
}

/// Item2 16078 is an armor item of power level 78: from level 50 the armor follows
/// GameFormula 1286 (f0 1000, f02 6.8, from power level 50), every step rounded to 32 bits
/// (0x14041deb0), times the armor modifiers. The expected bits come from the client's code
/// run on the row.
pub fn armor_from_level_50_follows_row_1286_in_single_precision_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item = given(tables:, item2_id: fixture_tables.root("Item2", 16_078))
  assert float32.to_bits(item.armor) == 0x4494cccd
    as "0x14041deb0: Armor at power level 78 from GameFormula 1286"
}

/// Item2 1700 is an armor item of power level 52 whose armor modifier is 0.75: the curve is
/// 1000 + 6.8 x 2 = 1013.6 in 32 bits, and the 32-bit product with 0.75 is
/// 760.199951171875 (0x443e0ccc). The product in double precision, 760.2, rounds to
/// 0x443e0ccd, one unit above the client's.
pub fn armor_band_two_rounds_each_step_to_32_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item = given(tables:, item2_id: fixture_tables.root("Item2", 1700))
  assert float32.to_bits(item.armor) == 0x443e0ccc
    as "0x14041deb0: each step of the armor is a 32-bit float, so it is 760.1999511..., not 760.2"
}

/// Item2 69826 is an armor item of power level 120, where GameFormula 1287 takes over from
/// 1286 (its dataint0 is 120): 2306.25 (0x45102400).
pub fn armor_from_level_120_follows_row_1287_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item = given(tables:, item2_id: fixture_tables.root("Item2", 69_826))
  assert float32.to_bits(item.armor) == 0x45102400
    as "0x14041deb0: Armor at power level 120 from GameFormula 1287"
}

/// A rune (Item2Family 33) takes its budget scale from the rune curve, GameFormula 991
/// below power level 50, 65 from 50 and 253 from 130 (0x14041f1b0), and its slot modifier
/// is 1. Item2 78256 (power level 20) gives property 34 as 110.0 (0x42dc0000), 78320
/// (power level 80) as 269.97174 (0x4386fc62): the client's code run on the rows.
pub fn a_rune_reads_its_budget_on_the_rune_curve_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let low = given(tables:, item2_id: fixture_tables.root("Item2", 78_256))
  assert bits(properties: low, property_id: 34) == Ok(0x42dc0000)
    as "0x14041f1b0: property 34 at the rune curve of power level 20"
  let high = given(tables:, item2_id: fixture_tables.root("Item2", 78_320))
  assert bits(properties: high, property_id: 34) == Ok(0x4386fc62)
    as "0x14041f1b0: property 34 at the rune curve of power level 80"
}

/// A rune has no ItemSlot for the client's builder (0x14040c610: none for Item2Family 33),
/// and BuildItemProperties adds ratings, armor, Base Health and a shield only when the
/// builder has one (0x14040c310), so a rune gives none of them whatever its budget holds:
/// only the budget property. Item2 80984 is one of the 68 runes whose own Item2
/// equippedSlotFlags are 0x10000, WeaponPrimary, which the ratings would take for a
/// weapon's slot if they went by the flags alone: it gives nothing at all.
pub fn a_rune_gives_no_ratings_armor_or_health_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let rune = given(tables:, item2_id: fixture_tables.root("Item2", 78_256))
  assert rune.base_health == 0.0 as "no Base Health (property 7)"
  assert rune.assault_rating == 0.0 as "no Assault Rating (property 35)"
  assert rune.support_rating == 0.0 as "no Support Rating (property 36)"
  assert rune.armor == 0.0 as "no Armor (property 42)"
  assert budget_ids(properties: rune) == [34]
    as "the one property the rune's budget gives"
  let weapon_flagged =
    given(tables:, item2_id: fixture_tables.root("Item2", 80_984))
  assert weapon_flagged
    == ItemProperties(
      base_health: 0.0,
      assault_rating: 0.0,
      support_rating: 0.0,
      armor: 0.0,
      shield: None,
      budget: dict.new(),
    )
    as "0x14040c310: no ItemSlot for the builder, so no rating, armor or Base Health, and no budget"
}

/// Item2 15052 is a weapon whose itemImbuementId is 106: the client takes an item's
/// imbuement count from the item sent, which is null for every item the server sends, so
/// no imbuement reward applies and the item gives what it gives unimbued.
pub fn an_imbued_item_gives_its_unimbued_properties_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let weapon = given(tables:, item2_id: fixture_tables.root("Item2", 15_052))
  assert float32.to_bits(weapon.assault_rating) == 0x44fa9800
    as "Assault Rating 2004.75, the weapon's own"
  assert float32.to_bits(weapon.support_rating) == 0x44271000
    as "Support Rating 668.25, the weapon's own"
  assert list.filter([32, 25, 57], fn(property_id) {
      bits(properties: weapon, property_id:) != Error(Nil)
    })
    == []
    as "the properties the imbuement would reward are not given"
}

/// Item2 13394 is a level-scaled (flags bit 3) light armor of power level 1: every curve
/// reads the wearer's level in place of the power level (0x14040f710). The expected bits
/// come from the emulator run `scaled_fill.py 13394 L L 0 0 0 0 0 0` for L = 1, 10 and 50:
/// FillItemInfo 0x1404445d0 on Item2 13394, then BuildItemProperties 0x14040c310 with the
/// scaling words 0 and 1 (the player's level and the effective level) set to L (the fact
/// `Item2.flags.level_scaled`).
pub fn a_level_scaled_item_reads_every_curve_at_the_wearers_level_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item2_id = fixture_tables.root("Item2", 13_394)
  let at = fn(level) {
    let item = given_at(tables:, item2_id:, level:)
    #(
      bits(properties: item, property_id: 32),
      float32.to_bits(item.assault_rating),
      float32.to_bits(item.armor),
      float32.to_bits(item.base_health),
    )
  }
  assert at(1) == #(Ok(0x42c44000), 0x40900000, 0x41960000, 0x42960000)
    as "level 1: 98.125, 4.5, 18.75 and 75.0"
  assert at(10) == #(Ok(0x43098000), 0x42340000, 0x433b8000, 0x443b8000)
    as "level 10: 137.5, 45.0, 187.5 and 750.0"
  assert at(50) == #(Ok(0x439c4000), 0x43610000, 0x446a6000, 0x456a6000)
    as "level 50: 312.5, 225.0, 937.5 and 3750.0"
}

/// Item2 13411 is a level-scaled weapon and 13410 a level-scaled shield, each of power
/// level 1: the ratings and the shield's capacity follow the wearer's level. The expected
/// bits come from the emulator runs `scaled_fill.py 13411 L L 0 0 0 0 0 0` and
/// `scaled_fill.py 13410 L L 0 0 0 0 0 0` for L = 10 and 50 (FillItemInfo 0x1404445d0, then
/// BuildItemProperties 0x14040c310 with the scaling words 0 and 1 set to L): for L = 10
/// the weapon gives property 47 = 82.5 (0x42a50000), 35 = 835.3125 (0x4450d400) and 36 =
/// 278.4375 (0x438b3800), the shield 41 = 1687.5 (0x44d2f000), 175 = 0.625 (0x3f200000),
/// 176 = 0.2 (0x3e4ccccd) and 178 = 2687 (0x4527f000).
pub fn a_level_scaled_weapon_and_shield_read_their_curves_at_the_wearers_level_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let weapon = fixture_tables.root("Item2", 13_411)
  let weapon_at = fn(level) {
    let item = given_at(tables:, item2_id: weapon, level:)
    #(
      bits(properties: item, property_id: 47),
      float32.to_bits(item.assault_rating),
      float32.to_bits(item.support_rating),
    )
  }
  assert weapon_at(10) == #(Ok(0x42a50000), 0x4450d400, 0x438b3800)
    as "level 10: 82.5, 835.3125 and 278.4375"
  assert weapon_at(50) == #(Ok(0x433b8000), 0x45828480, 0x44ae0600)
    as "level 50: 187.5, 4176.5625 and 1392.1875"
  let shield = fixture_tables.root("Item2", 13_410)
  let shield_at = fn(level) {
    let assert Some(item_property.Shield(
      capacity_max:,
      mitigation_max:,
      regen_percent:,
      reboot_time_ms:,
    )) = given_at(tables:, item2_id: shield, level:).shield
      as "the item is a shield"
    #(
      float32.to_bits(capacity_max),
      float32.to_bits(mitigation_max),
      float32.to_bits(regen_percent),
      reboot_time_ms,
    )
  }
  assert shield_at(10) == #(0x44d2f000, 0x3f200000, 0x3e4ccccd, 2687)
    as "level 10: capacity 1687.5, mitigation 0.625, regeneration 0.2, reboot 2687"
  assert shield_at(50) == #(0x4603d600, 0x3f200000, 0x3e4ccccd, 2687)
    as "level 50: capacity 8437.5, the rest the same"
}

/// An item without flags bit 3 reads its own power level: Item2 29495 gives the same at
/// the wearer's level 1 and 50.
pub fn an_item_that_does_not_scale_ignores_the_wearers_level_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item2_id = fixture_tables.root("Item2", 29_495)
  assert given_at(tables:, item2_id:, level: 1)
    == given_at(tables:, item2_id:, level: 50)
    as "no flags bit 3, so no curve reads the level"
}

/// A PvP rune (flags 0x8000, Item2 83331) and a proxy rune (flags 0x4000, Item2 29213)
/// keep their own gaps: the rune's budget does not answer them.
pub fn a_pvp_or_proxy_rune_is_still_refused_with_its_gap_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let gap_of = fn(item2_id) {
    let item2_id = fixture_tables.root("Item2", item2_id)
    case item_property.of_item(tables:, level: 1, item2_id:, random_stats: 0) {
      Error(item_property.Unread(item2_id: unread, gap:))
        if unread == item2_id
      -> Ok(gap)
      _ -> Error(Nil)
    }
  }
  assert gap_of(83_331) == Ok(item_property.PvpItem)
    as "flags 0x8000 is PvP, which issue 56 closes"
  assert gap_of(29_213) == Ok(item_property.ProxyItem)
    as "flags 0x4000 is a proxy, which issue 333 closes"
  assert item_property.gap_issue(gap: item_property.PvpItem) == Some(56)
  assert item_property.gap_issue(gap: item_property.ProxyItem) == Some(333)
}

/// Every wearable client row of the four kinds this step reads (flags bit 3, an
/// imbuement, Item2Family 33, and an armor item that is no shield with a power level from
/// GameFormula 1286's dataint0) is given at a wearer's level of 1 and of 50, or is unread
/// only for another gap: flags 0x8000 is PvP, and the others are the budget's own (an
/// ItemStat kind, a support beyond its range, a resource maximum). A row is counted in its
/// kinds from its own columns, not from the reader.
pub fn every_client_item_of_the_four_kinds_is_read_or_refused_only_for_another_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(late) = game_formula.get(tables:, id: GameFormulaId(1286))
    as "the client's GameFormula holds row 1286"
  let of_the_four_kinds =
    list.filter(item2.all(tables), fn(item) {
      let slot_flags =
        item_property.equipped_slot_flags(tables:, item2_id: item.id)
        |> result.unwrap(0)
      let is_shield = int.bitwise_and(slot_flags, 0x8000) != 0
      !item_property.is_proxy(item)
      && slot_flags != 0
      && {
        int.bitwise_and(item.flags, 8) != 0
        || item.item_imbuement_id != 0
        || item.item2_family_id == 33
        || {
          item.item2_family_id == 1
          && item.power_level >= late.dataint0
          && !is_shield
        }
      }
    })
  let counts = fn(level) {
    let outcomes =
      list.map(of_the_four_kinds, fn(item) {
        item_property.of_item(
          tables:,
          level:,
          item2_id: item.id,
          random_stats: 0,
        )
      })
    let given = list.count(outcomes, result.is_ok)
    let pvp =
      list.count(outcomes, fn(outcome) {
        case outcome {
          Error(item_property.Unread(gap: item_property.PvpItem, ..)) -> True
          _ -> False
        }
      })
    let budget_gaps =
      list.count(outcomes, fn(outcome) {
        case outcome {
          Error(item_property.Unread(gap: item_property.StatKind(..), ..))
          | Error(item_property.Unread(
              gap: item_property.SupportBeyondRange,
              ..,
            ))
          | Error(item_property.Unread(gap: item_property.ResourceMaximum, ..)) ->
            True
          _ -> False
        }
      })
    #(list.length(outcomes), given, pvp, budget_gaps)
  }
  let pvp_rows =
    list.count(of_the_four_kinds, fn(item) {
      int.bitwise_and(item.flags, 0x8000) != 0
    })
  let #(total, given, pvp, budget_gaps) = counts(1)
  assert total == given + pvp + budget_gaps
    as "every row is given or unread for another gap: none is refused, and none is unread for a gap this step closed"
  assert pvp == pvp_rows as "the PvP rows are exactly the flags 0x8000 rows"
  assert counts(50) == #(total, given, pvp, budget_gaps)
    as "the wearer's level changes no row's outcome kind"
  assert #(total, given, pvp, budget_gaps) == #(9802, 7883, 1917, 2)
    as "the counts of the four kinds: wearable rows, given, PvP, and the budget's own gaps"
}

/// Every wearable client row is given, or is `Unread` for one of the gaps that remain.
/// A row is wearable when it is no proxy (Item2.flags 0x4000, which issue 333 closes) and
/// its slot flags are not 0, as the client's slot rows say. The remaining gaps are
/// flags 0x8000, PvP, worked out here from the column and open under issue 56, and the
/// budget's own (an ItemStat kind no row holds, a support beyond its range, a resource
/// maximum). The counts are the coverage measure of items' properties: 46,842 wearable
/// rows, 42,343 given, 4,497 PvP and 2 for the budget's own gaps.
pub fn every_client_wearable_row_is_given_or_unread_with_a_named_reason_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let wearable =
    list.filter(item2.all(tables), fn(item) {
      item_property.equipped_slot_flags(tables:, item2_id: item.id)
      |> result.map(fn(slot_flags) {
        !item_property.is_proxy(item) && slot_flags != 0
      })
      |> result.unwrap(False)
    })
  let outcomes =
    list.map(wearable, fn(item) {
      #(
        item,
        item_property.of_item(
          tables:,
          level: 1,
          item2_id: item.id,
          random_stats: 0,
        ),
      )
    })
  assert list.filter(outcomes, fn(outcome) {
      let #(item, outcome) = outcome
      case outcome {
        Ok(_) -> int.bitwise_and(item.flags, 0x8000) != 0
        Error(item_property.Unread(gap: item_property.PvpItem, ..)) ->
          int.bitwise_and(item.flags, 0x8000) == 0
        Error(item_property.Unread(gap: item_property.StatKind(..), ..))
        | Error(item_property.Unread(gap: item_property.SupportBeyondRange, ..))
        | Error(item_property.Unread(gap: item_property.ResourceMaximum, ..)) ->
          False
        Error(item_property.Unread(gap: item_property.ProxyItem, ..))
        | Error(item_property.NoRow(..))
        | Error(item_property.Refused(..))
        | Error(item_property.NoCurveValue(..))
        | Error(item_property.RandomStatsRefused(..))
        | Error(item_property.TwoShields) -> True
      }
    })
    == []
    as "every row is given, or unread for flags 0x8000 or a gap of the budget's own, and none is refused"
  assert list.filter(outcomes, fn(outcome) {
      case outcome {
        #(item, Ok(properties)) ->
          item.item2_family_id == 33
          && item.item_budget_id == 0
          && item.item_stat_id == 0
          && properties
          != ItemProperties(
            base_health: 0.0,
            assault_rating: 0.0,
            support_rating: 0.0,
            armor: 0.0,
            shield: None,
            budget: dict.new(),
          )
        #(_, Error(_)) -> False
      }
    })
    == []
    as "0x14040c310: a rune has no ItemSlot for the builder, so one with no budget gives nothing at all, whatever its own equippedSlotFlags"
  let count = fn(keep) {
    list.count(outcomes, fn(outcome) { keep(outcome.0, outcome.1) })
  }
  let given = count(fn(_, outcome) { result.is_ok(outcome) })
  let pvp = count(fn(item, _) { int.bitwise_and(item.flags, 0x8000) != 0 })
  let budget_gaps = list.length(wearable) - given - pvp
  assert #(list.length(wearable), given, pvp, budget_gaps)
    == #(46_842, 42_343, 4497, 2)
    as "the counts: wearable rows, given, PvP, and the budget's own gaps"
}

/// The load fails when a row the budget reads is missing, naming it: the ItemBudget row of an
/// Item2, its ItemStat row, or the UnitProperty2 row an ItemStat entry of kind 1 names
/// (0x14040ca70, 0x14040db30: no row is 0x95). Item2 1375 names ItemBudget 3 and ItemStat 4,
/// which names UnitProperty2 34.
pub fn the_load_fails_on_a_missing_budget_stat_or_property_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let without = fn(table, id) {
    let assert Ok(rows) =
      fixture_tables.remove(rows: fixture_tables.rows(), table:, id:)
      as "the fixture's rows hold the row"
    fixture_tables.load(rows:)
  }
  assert without("ItemBudget", 3)
    == Error(table_store.RowMissing(
      from_table: "Item2",
      column: "itemBudgetId",
      to_table: "ItemBudget",
      id: 3,
    ))
    as "Item2 1375 names ItemBudget 3"
  assert without("ItemStat", 4)
    == Error(table_store.RowMissing(
      from_table: "Item2",
      column: "itemStatId",
      to_table: "ItemStat",
      id: 4,
    ))
    as "Item2 1375 names ItemStat 4"
  assert without("UnitProperty2", 34)
    == Error(table_store.RowMissing(
      from_table: "ItemStat",
      column: "itemStatData00",
      to_table: "UnitProperty2",
      id: 34,
    ))
    as "ItemStat 4's first entry is kind 1 and names UnitProperty2 34"
}

// ------------------------------------------------------------ random stats

/// The properties of an item the tables read in full, with the item's random-stat word.
fn rolled(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  random_stats random_stats: Int,
) -> ItemProperties {
  let assert Ok(properties) =
    item_property.of_item(tables:, level: 1, item2_id:, random_stats:)
    as "the item's rows are in the tables and the word is one the client accepts"
  properties
}

/// The bits of a value as the client's float.
fn value_bits(value value: Float) -> Int {
  float32.to_bits(value)
}

/// Item2 48169 has ItemBudget 25 (0.3, 0.2, 0.5) and ItemStat 432: three kind-2 entries
/// on ItemRandomStatGroup 11, whose rows in table order are properties 34, 47, 32, 29
/// and 57. The word's byte i is entry i's row (0x14040e6d0), and the entry takes its
/// property with its own share of the budget. The scale is the item's (the budget curve
/// at power level 50 times the slot's armorModifier), so a share 0.3 gives 0x42960001, 0.2
/// 0x42480000 and 0.5 0x42fa0000 on a property whose valuePerPoint is 1 (the Client
/// trace of this step). The item's own Assault Rating, 180, is 0x43340000.
pub fn a_rolled_item_gives_its_picked_rows_as_budget_stats_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item2_id = fixture_tables.root("Item2", 48_169)
  let first = rolled(tables:, item2_id:, random_stats: 0x0100000000030201)
  assert bits(properties: first, property_id: 34) == Ok(0x42960001)
    as "entry 0 takes row 1, property 34, with share 0.3"
  assert bits(properties: first, property_id: 47) == Ok(0x42480000)
    as "entry 1 takes row 2, property 47, with share 0.2"
  assert bits(properties: first, property_id: 32) == Ok(0x42fa0000)
    as "entry 2 takes row 3, property 32, with share 0.5"
  assert budget_ids(properties: first) == [32, 34, 47]
  assert value_bits(value: first.assault_rating) == 0x43340000
    as "property 35 is the item's own innate Assault Rating"
  let second = rolled(tables:, item2_id:, random_stats: 0x0100000000010405)
  assert bits(properties: second, property_id: 57) == Ok(0x42960001)
    as "entry 0 takes row 5, property 57, with share 0.3"
  assert bits(properties: second, property_id: 29) == Ok(0x42480000)
    as "entry 1 takes row 4, property 29, with share 0.2"
  assert bits(properties: second, property_id: 34) == Ok(0x42fa0000)
    as "entry 2 takes row 1, property 34, with share 0.5"
  assert budget_ids(properties: second) == [29, 34, 57]
  assert value_bits(value: second.assault_rating) == 0x43340000
}

/// Two entries that take one property add their values on a non-shield (0x14040db30 adds
/// onto the property's entry): word 0x0100000000020101 has entries 0 and 1 on row 1,
/// property 34, with shares 0.3 and 0.2, and entry 2 on row 2, property 47, with 0.5.
pub fn two_entries_picking_one_property_add_on_a_non_shield_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item =
    rolled(
      tables:,
      item2_id: fixture_tables.root("Item2", 48_169),
      random_stats: 0x0100000000020101,
    )
  assert bits(properties: item, property_id: 34) == Ok(0x42fa0001)
    as "0.3 + 0.2 of the budget on property 34, in 32 bits"
  assert bits(properties: item, property_id: 47) == Ok(0x42fa0000)
    as "entry 2's share 0.5 on property 47"
}

/// Item2 48170 is a shield with ItemBudget 51 (0.75, 0.75, 0, 0.5) and ItemStat 439:
/// four kind-2 entries on group 14, whose rows are 41, 175, 176 and 178. A picked
/// shield property takes its entry's share in place of the middle of its factor's range
/// (0x14040dbf0); a property no entry picks keeps the middle. The expected bits are the
/// client's code run on GameFormula 1260's and 1261's ranges (the Client trace).
pub fn a_shields_picks_move_its_factors_to_their_entries_fractions_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item2_id = fixture_tables.root("Item2", 48_170)
  let shield = fn(random_stats) {
    let assert Some(item_property.Shield(
      capacity_max:,
      mitigation_max:,
      regen_percent:,
      reboot_time_ms:,
    )) = rolled(tables:, item2_id:, random_stats:).shield
      as "the item is a shield"
    #(
      value_bits(value: capacity_max),
      value_bits(value: regen_percent),
      value_bits(value: int.to_float(reboot_time_ms)),
      value_bits(value: mitigation_max),
    )
  }
  assert shield(0x0100000004030201)
    == #(0x4645c100, 0x3d4ccccd, 0x45a02800, 0x3f500000)
    as "entry 0 on 41 (share 0.75), entry 1 on 175 (0.75), entry 2 on 176 (0), entry 3 on 178 (0.5)"
  assert shield(0x0100000001020304)
    == #(0x462fc800, 0x3e4ccccd, 0x4527f000, 0x3e800000)
    as "entry 0 on 178 (0.75), entry 1 on 176 (0.75), entry 2 on 175 (0), entry 3 on 41 (0.5)"
  assert shield(0x0100000003020101)
    == #(0x4645c100, 0x3e19999a, 0x45a02800, 0x3e800000)
    as "41 named by entries 0 and 1 (one share), 175 by entry 2 (0), 176 by entry 3 (0.5); 178 unnamed keeps the middle"
}

/// A word that holds no data gives the entries nothing, whatever it is (0x14040e6d0): 0, the
/// version alone, and choices under version 0 (which 0x14040bdf0 clears). An item's own
/// innate Assault Rating and a shield's middle factors are what is left.
pub fn a_word_without_data_gives_nothing_for_random_entries_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let bracer = fixture_tables.root("Item2", 48_169)
  list.each([0, 0x0100000000000000, 0x0000000000030201], fn(random_stats) {
    let item = rolled(tables:, item2_id: bracer, random_stats:)
    assert budget_ids(properties: item) == [] as "no entry gives a budget value"
    assert value_bits(value: item.assault_rating) == 0x43340000
      as "only the item's own Assault Rating, property 35, is given"
  })
  let assert Some(item_property.Shield(
    capacity_max:,
    mitigation_max:,
    regen_percent:,
    reboot_time_ms:,
  )) =
    rolled(
      tables:,
      item2_id: fixture_tables.root("Item2", 48_170),
      random_stats: 0x0100000000000000,
    ).shield
    as "the item is a shield"
  assert #(
      value_bits(value: capacity_max),
      value_bits(value: regen_percent),
      value_bits(value: int.to_float(reboot_time_ms)),
      value_bits(value: mitigation_max),
    )
    == #(0x462fc800, 0x3e19999a, 0x45a02800, 0x3f200000)
    as "a shield with no picks has the middle of each factor's range"
}

/// A word with data fails the client's whole build when a kind-2 entry's byte is 0 or past
/// its group's rows (0x14040e6d0 fails with 0x70): the item is worn and gives none of its
/// instance properties, so the reader refuses it and names the entry. Version 2 acts as
/// version 1 and counts as data even with every byte 0 (0x14040bdf0).
pub fn a_word_with_data_and_a_bad_byte_is_refused_whole_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let bracer = fixture_tables.root("Item2", 48_169)
  let shield = fixture_tables.root("Item2", 48_170)
  let refused = fn(item2_id, random_stats) {
    item_property.of_item(tables:, level: 1, item2_id:, random_stats:)
  }
  assert refused(bracer, 0x0100000000010106)
    == Error(item_property.RandomStatsRefused(
      item2_id: bracer,
      random_stats: 0x0100000000010106,
      entry: 0,
    ))
    as "entry 0's byte 6 is past group 11's five rows"
  assert refused(bracer, 0x0100000000000201)
    == Error(item_property.RandomStatsRefused(
      item2_id: bracer,
      random_stats: 0x0100000000000201,
      entry: 2,
    ))
    as "entry 2's byte is 0"
  assert refused(bracer, 0x0200000000000000)
    == Error(item_property.RandomStatsRefused(
      item2_id: bracer,
      random_stats: 0x0200000000000000,
      entry: 0,
    ))
    as "version 2 with every byte 0 is data, and entry 0's byte is 0"
  assert refused(shield, 0x0100000000000005)
    == Error(item_property.RandomStatsRefused(
      item2_id: shield,
      random_stats: 0x0100000000000005,
      entry: 0,
    ))
    as "entry 0's byte 5 is past group 14's four rows"
}

/// Item2 9965 has ItemStat 415, one entry of kind 2, a random stat group. With the
/// random-stat word 0 the client reads no data, and an entry then gives nothing
/// (0x14040e6d0). So the item gives what the same item with no entry gives: its own
/// armor and Base Health.
pub fn a_random_stat_entry_gives_nothing_while_the_item_holds_no_roll_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", 9965)
  let tables = fixture_tables.shared()
  let item = given_with(tables:, item2_id:, random_stats: 0)
  assert budget_ids(properties: item) == []
    as "0x14040e6d0: a kind-2 entry with no byte is kind 0"
  assert item.armor >. 0.0 && item.base_health >. 0.0
    as "0x14040e340, 0x14040e3d0: the item's own armor and Base Health"
  use tables <- fixture_tables.changed(table: "ItemStat", id: 415, with: [
    #("itemStatTypeEnum00", Integer(0)),
  ])
  assert given_with(tables:, item2_id:, random_stats: 0) == item
    as "an entry of kind 0 gives the same"
}
