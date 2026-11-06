//// The scripted client's view of the loadout (`game_client.loadout_in`) and of
//// the character sheet (`game_client.sheet`). Expected values come from these
//// places.
//// - An item at location 4 is an ability, its item id the Spell4Base id and its
////   bag index the slot a press names; the weapon is the item equipped at
////   location 0, index 16 (`opcode.0x111.ability_bag`,
////   `lua.ActionBarFrame.InitializeBars`); any other item at location 0 is an
////   equipped armor piece or shield at its bag index
////   (`opcode.0x111.equipped_set`).
//// - The bar shows a type 4 shortcut's ability only while the ability's item is
////   held and a tier is set for action set 0 (`opcode.0x19d`, `opcode.0x1a0`,
////   `0x1403c1bf0`).
//// - The sheet: Assault Power is property 35 times 0.25 (`0x14064c960`),
////   Support Power property 36 times 0.25 (`0x14064ca50`), Max Health property
////   7 cut to a whole number (`0x14064a6d0`) and Max Shields property 41
////   (`0x14064faa0`); 100.0 x 0.25 = 25, 41.0 x 0.25 = 10.25 shows 10, and a
////   health of 735.97 is cut to 735.

import character_support
import character_tables
import game_client.{Loadout, Sheet}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers.{AbilityTiers}
import genesis_prime/message/action_set.{ActionSet}
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/float32
import genesis_prime/message/held_item.{HeldItem}
import genesis_prime/message/innate_index_set.{InnateIndexSet}
import genesis_prime/message/item_added
import genesis_prime/message/shared_item.{type SharedItem, SharedItem}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/game_formula
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/player_unit
import gleam/list
import gleam/option.{None, Some}
import novice_tables
import owned_key
import owned_test
import place_support
import planted_table
import unit_support

fn item(location location: Int, index index: Int, id id: Int) -> SharedItem {
  SharedItem(
    item_guid: id,
    field_2: 0,
    item_id: id,
    location:,
    bag_index: index,
    stack_count: 1,
    charges: 0,
    field_8: 0,
    field_9: 0,
    field_10: 0,
    durability: float32.to_bits(1.0),
    field_12: 0,
    field_13: 0,
    field_14: 0,
    field_15: 0,
    field_16: 0,
    field_17: 0,
    field_18: 0,
    field_19: 0,
    field_20: 0,
    field_21: 0,
    field_22: 0,
    field_23: 0,
    list_a: [],
    list_b: [],
    field_27: 0,
  )
}

fn added(item item: SharedItem) -> Frame {
  let assert Ok(body) =
    item_added.encode(
      item_added.ItemAdded(held_item: HeldItem(item:, reason: 49)),
    )
    as "0x111 encodes"
  Frame(message_id: item_added.message_id, body:)
}

fn tiers(bases bases: List(Int), set set: Int) -> Frame {
  let assert Ok(body) =
    ability_tiers.encode(
      AbilityTiers(
        tiers: list.map(bases, fn(base) {
          AbilityTier(spell4_base_id: base, tier: 1, action_set_index: set)
        }),
      ),
    )
    as "0x1a0 encodes"
  Frame(message_id: ability_tiers.message_id, body:)
}

fn innate_index(index index: Int) -> Frame {
  let assert Ok(body) =
    innate_index_set.encode(InnateIndexSet(innate_index: index))
    as "0x19f encodes"
  Frame(message_id: innate_index_set.message_id, body:)
}

fn bar(objects objects: List(Int)) -> Frame {
  let assert Ok(body) =
    action_set.encode(ActionSet(
      action_set_index: 0,
      field_2: 0,
      result: 1,
      shortcuts: list.index_map(objects, fn(object_id, slot) {
        ActionShortcut(
          shortcut_type: 4,
          location: 4,
          bag_index: slot,
          object_id:,
        )
      }),
    ))
    as "0x19d encodes"
  Frame(message_id: action_set.message_id, body:)
}

pub fn the_bot_reads_the_weapon_the_armor_the_abilities_and_the_bar_from_an_entry_test() -> Nil {
  use <- owned_test.run(5000)
  let frames = [
    added(item: item(location: 0, index: 0, id: 81_359)),
    added(item: item(location: 0, index: 3, id: 81_381)),
    added(item: item(location: 0, index: 15, id: 8534)),
    added(item: item(location: 0, index: 16, id: 81_346)),
    added(item: item(location: 4, index: 0, id: 100)),
    added(item: item(location: 4, index: 1, id: 200)),
    tiers(bases: [100, 200], set: 0),
    bar(objects: [100, 200]),
  ]
  assert game_client.loadout_in(frames:)
    == Loadout(
      weapon: Some(81_346),
      armor: [#(0, 81_359), #(3, 81_381), #(15, 8534)],
      abilities: [#(0, 100), #(1, 200)],
      innate: None,
      bar: [#(0, 100), #(1, 200)],
    )
    as "the weapon at location 0, index 16, the armor and shield at location 0 in their bag indexes, the abilities at location 4 and a bar of the abilities held with a tier in set 0"
}

pub fn the_bar_leaves_out_an_ability_that_is_not_held_or_has_no_tier_in_set_0_and_a_bag_with_no_weapon_has_none_test() -> Nil {
  use <- owned_test.run(5000)
  let frames = [
    added(item: item(location: 4, index: 0, id: 100)),
    added(item: item(location: 4, index: 1, id: 200)),
    tiers(bases: [100], set: 0),
    tiers(bases: [200], set: 1),
    bar(objects: [100, 200, 300]),
  ]
  assert game_client.loadout_in(frames:)
    == Loadout(
      weapon: None,
      armor: [],
      abilities: [#(0, 100), #(1, 200)],
      innate: None,
      bar: [#(0, 100)],
    )
    as "ability 200 has a tier only in set 1 and 300 is not held: neither shows on the bar; no item at location 0, index 16 is no weapon"
}

pub fn the_bot_keeps_the_innate_apart_from_the_bar_test() -> Nil {
  use <- owned_test.run(5000)
  let frames = [
    added(item: item(location: 4, index: 0, id: 100)),
    added(item: item(location: 4, index: 1, id: 200)),
    added(item: item(location: 4, index: 2, id: 300)),
    added(item: item(location: 4, index: 3, id: 400)),
    tiers(bases: [100, 200, 300, 400], set: 0),
    bar(objects: [100, 200, 300]),
    innate_index(index: 0),
  ]
  assert game_client.loadout_in(frames:)
    == Loadout(
      weapon: None,
      armor: [],
      abilities: [#(0, 100), #(1, 200), #(2, 300)],
      innate: Some(#(3, 400)),
      bar: [#(0, 100), #(1, 200), #(2, 300)],
    )
    as "lua.ActionBarFrame.ActionBarInnate: the innate is held in the bag and is no shortcut of an action set (opcode.0x19d), so the item at location 4 that no shortcut names is the innate, and the bar's presses are the three abilities'"
}

/// A player's 0x262 that sets only these properties, each as the pair of its
/// id and value.
fn unit_with(
  properties properties: List(#(Int, Float)),
) -> unit_create_player.UnitCreatePlayer {
  let record =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: character_support.character(number: 1),
        place: place_support.at(
          world_id: 3460,
          world_zone_id: 6009,
          x: 1.0,
          y: 2.0,
          z: 3.0,
        ),
        unit_id: 1,
        body: [],
      ),
      realm_id: 1,
    )
  unit_create_player.UnitCreatePlayer(
    ..record,
    tail: UnitCreateTail(
      ..record.tail,
      properties: list.map(properties, fn(pair) {
        let bits = float32.to_bits(pair.1)
        UnitProperty(property_id: pair.0, base: bits, value: bits)
      }),
    ),
  )
}

pub fn the_sheet_shows_the_ratings_times_a_quarter_rounded_the_health_cut_and_the_shield_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_client.sheet(
      unit: unit_with(properties: [
        #(35, 100.0),
        #(36, 41.0),
        #(7, 735.97),
        #(41, 449.6),
      ]),
      tables: character_tables.shared(),
    )
    == Sheet(
      assault_power: 25,
      support_power: 10,
      max_health: 735,
      max_shield: 450,
    )
    as "0x14064c960: 100 x 0.25 is 25; 0x14064ca50: 41 x 0.25 = 10.25 shows 10; 0x14064a6d0: 735.97 is cut to 735; 0x14064faa0: 449.6 shows 450"
  assert game_client.sheet(
      unit: unit_with(properties: []),
      tables: character_tables.shared(),
    )
    == Sheet(assault_power: 0, support_power: 0, max_health: 0, max_shield: 0)
    as "a property the 0x262 does not set is 0"
}

pub fn the_sheets_power_factors_are_game_formula_1266s_two_values_test() -> Nil {
  use <- owned_test.run(60_000)
  let formulas =
    list.map(novice_tables.formulas(), fn(row) {
      case row.id {
        1266 -> novice_tables.Formula(..row, float0: 0.5, float01: 0.1)
        _ -> row
      }
    })
  let files =
    list.map(character_tables.files(), fn(file) {
      case file.0 == game_formula.schema.file {
        True ->
          planted_table.file(
            game_formula.schema,
            list.flatten([
              character_tables.game_formula_rows(
                ids: [character_tables.highest_level_formula],
                highest: 50,
              ),
              list.map(formulas, novice_tables.game_formula_row),
            ]),
          )
        False -> file
      }
    })
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) =
    server_table.load_under(under: owned_key.new(), from: folder)
    as "the planted tables with a changed GameFormula 1266 load"
  assert game_client.sheet(
      unit: unit_with(properties: [#(35, 100.0), #(36, 41.0)]),
      tables:,
    )
    == Sheet(assault_power: 50, support_power: 4, max_health: 0, max_shield: 0)
    as "0x14064c960: Assault Power is 100 x the row's first value 0.5; 0x14064ca50: Support Power is 41 x its second value 0.1, 4.1 shown as 4"
  table_store.unload(tables)
}
