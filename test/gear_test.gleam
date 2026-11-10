//// What a player's worn items give (`genesis_prime/game/gear`), from the client's
//// rows read as the shared tables (`fixture_tables`). Expected values come from
//// these places.
//// - The Novice sets and what they wear: `novice_tables` (`Item2.novice_set`,
////   `opcode.0x262.worn_visuals`), which lists each set's items from the PreTutorial
////   CharacterCreation rows and the displays of the ItemDisplaySourceEntry rows of
////   their source, type and power level, in ItemSlot order.
//// - The sums of a Novice set, `0x14040df10` (ratings), `0x14040e340` (armor),
////   `0x14040e3d0` (Base Health) and `0x14040dbf0` (the shield): Assault Rating
////   167.0625 from the weapon and 9.0 + 9.0 + 7.2 + 5.4 + 5.4 from the five armor
////   pieces, so 203.0625, Support Rating 55.6875, Armor 250 (Warrior, Engineer), 200
////   (Medic, Stalker) or 150 (Esper, Spellslinger), Base Health 600, the shield's
////   ShieldCapacityMax 450, ShieldMitigationMax 0.625, ShieldRegenPct 0.15 and
////   ShieldRebootTime 5125. The slot modifiers 1.25 (chest), 1.25 (legs), 1 (shoulder),
////   0.75 (feet) and 0.75 (hands), which the ratings above show, split Base Health and
////   Armor by piece: the chest gives a quarter of each (150 of the 600) and its Assault
////   Rating 9.0. The client works in 32-bit floats, so a test takes a sum within 0.0001.
//// - Health: CreatureLevel row 1's Base Health 135.97 and the armor's 600, 736 at level
////   1; row 9's 2295.49 and 600, 2895 (`player.level1_base_health`); the table holds
////   the rows 1 to 101.
//// - The properties without a shield: the UnitProperty2 rows' defaultValue of 41
////   (ShieldCapacityMax) 0.0, 175 (ShieldMitigationMax) 0.0, 176 (ShieldRegenPct) 0.25
////   and 178 (ShieldRebootTime) 2500.0 (`UnitProperty2.client_value`).
//// - An item the reader leaves unread: the PvP flags 0x8000 (the PvP gap record, open
////   issue #56), `0x1404445d0` (the flags 0x4000) and `0x14041deb0` (GameFormula
////   1286's armor curve), as `item_property` records.

import fixture_tables
import genesis_prime/game/gear
import genesis_prime/game/item_property.{ItemProperties}
import genesis_prime/game/loadout
import genesis_prime/game/worn_visual
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/store.{type HeldItem, HeldItem}
import genesis_prime/table/id.{ClassId, Item2Id, UnitProperty2Id}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import novice_tables.{type Set}
import owned_test
import planted_table.{Integer}

/// The armor a class's Novice set gives: heavy 250, medium 200, light 150.
fn armor_of(class_id class_id: Int) -> Float {
  case class_id {
    1 | 2 -> 250.0
    4 | 5 -> 200.0
    _ -> 150.0
  }
}

/// The items of a set at a location, each at its bag index, with the guids 1 to 7.
fn held_at(set set: Set, location location: Int) -> List(HeldItem) {
  list.index_map(novice_tables.equipped_of(set:), fn(pair, index) {
    HeldItem(
      item_guid: index + 1,
      item2_id: Item2Id(pair.0),
      location:,
      bag_index: pair.1,
      stack_count: 1,
    )
  })
}

/// The set of Warrior and faction 167, CharacterCreation row 466.
fn warrior_167() -> Set {
  let assert Ok(set) =
    list.find(novice_tables.sets(), fn(set) { set.creation_id == 466 })
    as "the Novice sets hold row 466"
  set
}

/// Whether a value is the source's decimal, to the 32-bit floats' error.
fn close(value value: Float, to expected: Float) -> Bool {
  float.absolute_value(value -. expected) <. 0.0001
}

fn visuals_of(set set: Set) -> List(item_visual.ItemVisual) {
  list.map(
    novice_tables.worn_visuals(
      class_id: set.class_id,
      faction_id: set.faction_id,
    ),
    fn(pair) {
      ItemVisual(slot: pair.0, display_id: pair.1, item_color_set_id: 0, dye: 0)
    },
  )
}

pub fn the_novice_set_held_at_location_0_gives_the_loadouts_properties_visuals_and_weapon_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each(novice_tables.sets(), fn(set) {
    let name =
      "class "
      <> int.to_string(set.class_id)
      <> " faction "
      <> int.to_string(set.faction_id)
    let worn = gear.of_items(tables:, items: held_at(set:, location: 0))
    let properties = worn.properties
    assert close(value: properties.assault_rating, to: 203.0625)
      as { "0x14040df10: the Assault Rating of " <> name <> " is 203.0625" }
    assert close(value: properties.support_rating, to: 55.6875)
      as { "0x14040df10: the Support Rating of " <> name <> " is 55.6875" }
    assert close(value: properties.armor, to: armor_of(class_id: set.class_id))
      as { "0x14040e340: the Armor of " <> name }
    assert close(value: properties.base_health, to: 600.0)
      as { "0x14040e3d0: the Base Health of " <> name <> " is 600" }
    let assert Some(shield) = properties.shield
      as { "0x14040dbf0: the set of " <> name <> " holds a shield" }
    assert close(value: shield.capacity_max, to: 450.0)
      && close(value: shield.mitigation_max, to: 0.625)
      && close(value: shield.regen_percent, to: 0.15)
      && shield.reboot_time_ms == 5125
      as { "0x14040dbf0: the shield of " <> name }
    assert worn.visuals == visuals_of(set:)
      as {
        "opcode.0x262.worn_visuals: the set of "
        <> name
        <> " is drawn as its five armor pieces and its weapon, in slot order"
      }
    assert worn.weapon == Some(Item2Id(set.weapon))
      as { "the item in bag index 16 is the weapon of " <> name }
    assert worn.unread == []
      as { "the Novice items are read in full, " <> name }
    assert gear.max_health(tables:, gear: worn, level: 1) == Ok(736)
      as {
        "player.level1_base_health: the "
        <> name
        <> "'s 135.97 (CreatureLevel row 1) and 600 (the armor) round to 736"
      }
    let assert Ok(loadout) =
      loadout.of(
        tables:,
        class_id: ClassId(set.class_id),
        faction_id: set.faction_id,
      )
      as { "the tables hold a Novice set for " <> name }
    assert list.map(loadout.visuals, worn_visual.item_visual) == worn.visuals
      && loadout.properties == worn.properties
      && Some(loadout.weapon) == worn.weapon
      as "the loadout of the same set draws, gives and wields the same"
  })
}

pub fn items_not_at_location_0_give_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let set = warrior_167()
  let nothing =
    ItemProperties(
      base_health: 0.0,
      assault_rating: 0.0,
      support_rating: 0.0,
      armor: 0.0,
      shield: None,
      budget: dict.new(),
    )
  // The bag (location 1), the bank (location 2) and the ability bag (location 4).
  list.each([1, 2, 4], fn(location) {
    let worn = gear.of_items(tables:, items: held_at(set:, location:))
    assert worn.properties == nothing
      && worn.visuals == []
      && worn.weapon == None
      && worn.unread == []
      as {
        "opcode.0x262.worn_visuals: only location 0 is worn, so the set at location "
        <> int.to_string(location)
        <> " gives nothing"
      }
  })
  let chest_worn =
    list.map(held_at(set:, location: 1), fn(item) {
      case item.bag_index {
        0 -> HeldItem(..item, location: 0)
        _ -> item
      }
    })
  let worn = gear.of_items(tables:, items: chest_worn)
  assert close(value: worn.properties.base_health, to: 150.0)
    && close(value: worn.properties.assault_rating, to: 9.0)
    && worn.properties.shield == None
    && list.map(worn.visuals, fn(visual) { visual.slot }) == [1]
    as "a chest at location 0 among items in a bag gives its own 150 Base Health and 9.0 Assault Rating, and only it is drawn"
}

pub fn without_the_chest_armor_and_health_fall_by_its_values_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let set = warrior_167()
  let without_chest =
    list.filter(held_at(set:, location: 0), fn(item) { item.bag_index != 0 })
  let worn = gear.of_items(tables:, items: without_chest)
  assert close(value: worn.properties.base_health, to: 450.0)
    as "the chest's quarter of the 600 is gone"
  assert close(value: worn.properties.armor, to: 187.5)
    as "the chest's quarter of a heavy set's 250 is gone"
  assert close(value: worn.properties.assault_rating, to: 194.0625)
    as "the chest's 9.0 of 203.0625 is gone"
  assert close(value: worn.properties.support_rating, to: 55.6875)
    as "the armor gives no Support Rating, so it stays"
  assert gear.max_health(tables:, gear: worn, level: 1) == Ok(586)
    as "135.97 and 450 round to 586"
  assert list.map(worn.visuals, fn(visual) { visual.slot }) == [2, 4, 5, 6, 20]
    as "the chest's slot 1 is not drawn, and the other four armor slots and the weapon are"
  assert worn.weapon == Some(Item2Id(81_346)) as "the weapon stays"
  let assert Ok(health) = gear.bases(tables:, gear: worn, level: 1)
    as "CreatureLevel has row 1"
  assert health
    |> list.key_find(UnitProperty2Id(7))
    |> result_is_close(to: 586.0)
    as "property 7, BaseHealth, is the maximum health"
}

fn result_is_close(
  found found: Result(Float, Nil),
  to expected: Float,
) -> Bool {
  case found {
    Ok(value) -> close(value:, to: expected)
    Error(Nil) -> False
  }
}

pub fn without_a_shield_its_four_properties_are_the_defaults_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let set = warrior_167()
  let all = held_at(set:, location: 0)
  let without_shield = list.filter(all, fn(item) { item.bag_index != 15 })
  let bare = gear.of_items(tables:, items: without_shield)
  assert bare.properties.shield == None as "no shield is worn"
  let assert Ok(bases) = gear.bases(tables:, gear: bare, level: 1)
    as "CreatureLevel has row 1"
  assert list.filter(list.map(bases, fn(base) { { base.0 }.value }), fn(id) {
      list.contains([7, 35, 36, 41, 42, 175, 176, 178], id)
    })
    == [7, 35, 36, 41, 42, 175, 176, 178]
    as "the gear sets properties 7, 35, 36, 42 and the four shield properties, in id order"
  assert list.filter(bases, fn(base) {
      list.contains([41, 175, 176, 178], { base.0 }.value)
    })
    == [
      #(UnitProperty2Id(41), 0.0),
      #(UnitProperty2Id(175), 0.0),
      #(UnitProperty2Id(176), 0.25),
      #(UnitProperty2Id(178), 2500.0),
    ]
    as "UnitProperty2's defaultValue of ShieldCapacityMax 0, ShieldMitigationMax 0, ShieldRegenPct 0.25 and ShieldRebootTime 2500"
  let shielded = gear.of_items(tables:, items: all)
  let assert Ok(with_shield) = gear.bases(tables:, gear: shielded, level: 1)
    as "CreatureLevel has row 1"
  let shield_part =
    list.filter(with_shield, fn(base) {
      list.contains([41, 175, 176, 178], { base.0 }.value)
    })
    |> list.map(fn(base) { #({ base.0 }.value, base.1) })
  assert list.map(shield_part, fn(pair) { pair.0 }) == [41, 175, 176, 178]
    as "the four shield properties, in id order"
  let assert [#(_, capacity), #(_, mitigation), #(_, regen), #(_, reboot)] =
    shield_part
  assert close(value: capacity, to: 450.0)
    && close(value: mitigation, to: 0.625)
    && close(value: regen, to: 0.15)
    && close(value: reboot, to: 5125.0)
    as "0x14040dbf0: the Novice shield's capacity, mitigation, regeneration and reboot time replace the defaults"
}

pub fn an_item_the_reader_refuses_is_worn_and_shown_but_gives_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let nothing =
    ItemProperties(
      base_health: 0.0,
      assault_rating: 0.0,
      support_rating: 0.0,
      armor: 0.0,
      shield: None,
      budget: dict.new(),
    )
  let chest_slot =
    ItemVisual(slot: 1, display_id: 3838, item_color_set_id: 0, dye: 0)
  // A copy of the Warrior's chest that is a PvP item, flags 0x8000: its budget rows are
  // read, its PvP branches are not, and its warning names the open issue.
  fixture_tables.added(
    table: "Item2",
    copy_of: 81_359,
    id: 99_001,
    with: [#("flags", Integer(0x8001))],
    body: fn(tables) {
      let worn =
        gear.of_items(tables:, items: [
          HeldItem(
            item_guid: 1,
            item2_id: Item2Id(99_001),
            location: 0,
            bag_index: 0,
            stack_count: 1,
          ),
        ])
      assert worn.properties == nothing as "a PvP item gives no properties"
      assert worn.visuals == [chest_slot]
        as "it is worn and drawn all the same, as the chest of its source, type and level"
      assert worn.unread
        == [
          #(
            Item2Id(99_001),
            item_property.Unread(item2_id: 99_001, gap: item_property.PvpItem),
          ),
        ]
        as "it is listed unread, with its id and its reason"
      assert gear.warnings(gear: worn, known: None)
        == [
          "the worn item 99001 gives no properties: the item 99001 is not read: it is a PvP item (open issue 56)",
        ]
        as "one warning names the item, the reason and the open issue that closes it"
    },
  )
  // A copy with the flags 0x4000: not read, and the client never dresses it.
  fixture_tables.added(
    table: "Item2",
    copy_of: 81_359,
    id: 99_001,
    with: [#("flags", Integer(0x4001))],
    body: fn(tables) {
      let worn =
        gear.of_items(tables:, items: [
          HeldItem(
            item_guid: 1,
            item2_id: Item2Id(99_001),
            location: 0,
            bag_index: 0,
            stack_count: 1,
          ),
        ])
      assert worn.properties == nothing
        as "0x1404445d0: an item whose flags hold 0x4000 takes its fields from a proxy item, which the reader does not follow"
      assert worn.visuals == []
        as "0x140444130: an item whose flags hold 0x4000 is never dressed"
      let assert [
        #(Item2Id(99_001), item_property.Unread(item2_id: 99_001, ..)),
      ] = worn.unread
        as "it is listed unread"
      Nil
    },
  )
  // The armor curve of GameFormula 1286 from the item's power level 50 (the row's
  // dataint0): a copy of the chest at that level.
  fixture_tables.added(
    table: "Item2",
    copy_of: 81_359,
    id: 99_001,
    with: [#("powerLevel", Integer(50))],
    body: fn(tables) {
      let worn =
        gear.of_items(tables:, items: [
          HeldItem(
            item_guid: 1,
            item2_id: Item2Id(99_001),
            location: 0,
            bag_index: 0,
            stack_count: 1,
          ),
        ])
      assert worn.properties == nothing
        as "0x14041deb0: an armor item whose power level reaches GameFormula 1286's dataint0, 50, takes the armor curve this reader does not follow"
      let assert [
        #(Item2Id(99_001), item_property.Unread(item2_id: 99_001, ..)),
      ] = worn.unread
        as "it is listed unread"
      Nil
    },
  )
}

pub fn max_health_at_a_level_uses_that_levels_creature_level_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let worn =
    gear.of_items(tables:, items: held_at(set: warrior_167(), location: 0))
  assert gear.max_health(tables:, gear: worn, level: 9) == Ok(2895)
    as "the client's CreatureLevel row 9's 2295.49 and the armor's 600, 2895"
  assert gear.max_health(tables:, gear: worn, level: 102)
    == Error(gear.NoCreatureLevel(level: 102))
    as "the client's CreatureLevel holds the rows 1 to 101 and none for level 102"
  let assert Ok(bases) = gear.bases(tables:, gear: worn, level: 9)
    as "CreatureLevel has row 9"
  assert list.key_find(bases, UnitProperty2Id(7)) == Ok(2895.0)
    as "property 7 at level 9 is the maximum health there"
  assert gear.bases(tables:, gear: worn, level: 102)
    == Error(gear.NoCreatureLevel(level: 102))
    as "no row, no bases"
}

pub fn an_item_whose_display_row_is_missing_is_not_drawn_and_gives_one_warning_test() -> Nil {
  use <- owned_test.run(60_000)
  // A copy of the Warrior's chest naming a display no ItemDisplay row holds. The
  // client draws a worn item from its ItemDisplay row, so there is nothing to draw,
  // and the server says so once, naming the item and the table.
  fixture_tables.added(
    table: "Item2",
    copy_of: 81_359,
    id: 99_001,
    with: [#("itemDisplayId", Integer(99_999_999))],
    body: fn(tables) {
      let worn =
        gear.of_items(tables:, items: [
          HeldItem(
            item_guid: 1,
            item2_id: Item2Id(99_001),
            location: 0,
            bag_index: 0,
            stack_count: 1,
          ),
        ])
      assert worn.visuals == []
        as "an item whose display the tables lack is not drawn"
      assert gear.warnings(gear: worn, known: None)
        == [
          "the worn item 99001 is not drawn: the table ItemDisplay has no row 99999999",
        ]
        as "one warning names the item, the table and the id"
    },
  )
  // A worn item with no display of its own and no source is invisible, not a fault.
  fixture_tables.added(
    table: "Item2",
    copy_of: 81_359,
    id: 99_001,
    with: [#("itemDisplayId", Integer(0)), #("itemSourceId", Integer(0))],
    body: fn(tables) {
      let worn =
        gear.of_items(tables:, items: [
          HeldItem(
            item_guid: 1,
            item2_id: Item2Id(99_001),
            location: 0,
            bag_index: 0,
            stack_count: 1,
          ),
        ])
      assert worn.visuals == [] as "an item with no display is not drawn"
      assert gear.warnings(gear: worn, known: None) == []
        as "and that is not a fault, so there is no warning"
    },
  )
}

/// One item worn at `bag_index`, or held in the bag (location 1).
fn one_item(
  item2_id item2_id: Int,
  location location: Int,
  bag_index bag_index: Int,
) -> List(HeldItem) {
  [
    HeldItem(
      item_guid: 1,
      item2_id: Item2Id(fixture_tables.root("Item2", item2_id)),
      location:,
      bag_index:,
      stack_count: 1,
    ),
  ]
}

/// Item2 1375 gives property 34, Critical Hit Rating, 64.125 (`item_property`'s test of
/// the same item, ItemBudget 3, ItemStat 4, 0x14040db30). Wearing it, `bases` lists
/// property 34 at UnitProperty2 34's defaultValue 0 and 64.125; in the bag it gives
/// nothing (`opcode.0x262.worn_visuals`), and 34 is listed at its default.
pub fn a_budget_rating_is_its_default_plus_the_worn_sum_and_returns_on_unequip_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let rating_of = fn(location) {
    let worn =
      gear.of_items(
        tables:,
        items: one_item(item2_id: 1375, location:, bag_index: 5),
      )
    assert worn.unread == [] as "the gloves are read in full"
    let assert Ok(bases) = gear.bases(tables:, gear: worn, level: 1)
      as "CreatureLevel has row 1"
    list.key_find(bases, UnitProperty2Id(34))
  }
  assert rating_of(0) == Ok(64.125)
    as "0x14040db30: the default 0 and the gloves' 64.125"
  assert rating_of(1) == Ok(0.0)
    as "taken off, property 34 is at its UnitProperty2 default"
}

/// Item2 71653 (an implant, ItemSlot ArmorImplant 0x400, armorModifier 1.0) has ItemBudget 10
/// (0.5, 0.5) and ItemStat 226, which names property 6 and Base Health (7). The curve at
/// power level 21 is GameFormula 1028's 7.5 + 0.35 x 21 = 14.85, so each share is 7.425
/// points; UnitProperty2 7's valuePerPoint is 18, 133.65 as the 32-bit float
/// 0x4305a667. Base Health at level 1 is CreatureLevel row 1's 135.97 (136 alone).
pub fn a_budget_base_health_adds_to_the_maximum_health_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let bare = gear.of_items(tables:, items: [])
  assert gear.max_health(tables:, gear: bare, level: 1) == Ok(136)
    as "CreatureLevel row 1's 135.97"
  let worn =
    gear.of_items(
      tables:,
      items: one_item(item2_id: 71_653, location: 0, bag_index: 10),
    )
  assert worn.unread == [] as "the implant is read in full"
  assert worn.properties.base_health == 133.65000915527344
    as "0x14040db30: Base Health from the budget, the 32-bit float 0x4305a667"
  assert gear.max_health(tables:, gear: worn, level: 1) == Ok(270)
    as "135.97 and 133.65 round to 270"
  let assert Ok(bases) = gear.bases(tables:, gear: worn, level: 1)
    as "CreatureLevel has row 1"
  assert list.key_find(bases, UnitProperty2Id(7)) == Ok(270.0)
    as "property 7 at level 1 is the maximum health there"
  assert list.key_find(bases, UnitProperty2Id(6)) == Ok(74.25)
    as "property 6: 0.5 x 14.85 x 10 = 74.25, 0x42948000, on its default 0"
}
