//// The planted Novice tables (`novice_tables`) against the client's own files:
//// every row the tests plant is the real row in the columns the server reads, so
//// the tests that run without the client carry the client's values. Skipped where
//// `GENESIS_NO_CLIENT=1`, as every test of the real files is.

import character_tables
import client_tables
import genesis_prime/table/character_creation
import genesis_prime/table/creature_level
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  CharacterCreationId, CreatureLevelId, GameFormulaId, Item2CategoryId,
  Item2FamilyId, Item2Id, Item2TypeId, ItemDisplayId, ItemDisplaySourceEntryId,
  ItemSlotId, Spell4Id, SpellLevelId,
}
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_display_source_entry
import genesis_prime/table/item_slot
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/list
import novice_tables
import owned_test
import unitest

pub fn the_planted_novice_character_creation_rows_hold_the_real_rows_items_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  list.each(novice_tables.sets(), fn(set) {
    let get = fn(tables) {
      let assert Ok(row) =
        character_creation.get(
          tables:,
          id: CharacterCreationId(set.creation_id),
        )
        as "the row exists"
      #(
        row.class_id,
        row.race_id,
        row.sex,
        row.faction_id,
        row.character_creation_start_enum,
        row.enabled,
        [
          row.item_id0,
          row.item_id01,
          row.item_id02,
          row.item_id03,
          row.item_id04,
          row.item_id05,
          row.item_id06,
          row.item_id07,
        ],
      )
    }
    assert get(planted) == get(real)
      as "CharacterCreation: the planted Novice row has the real row's class, race, sex, faction and items"
    let #(class_id, _, _, faction_id, _, _, items) = get(real)
    assert class_id == set.class_id
      && faction_id == set.faction_id
      && list.take(items, 7) == set.items
      && set.weapon == set.items |> list.drop(4) |> list.first |> unwrap
      as "the planted set's class, faction, items and weapon are the real row's"
  })
}

fn unwrap(result: Result(Int, Nil)) -> Int {
  let assert Ok(value) = result as "the set holds seven items"
  value
}

pub fn the_planted_items_types_families_categories_and_slots_are_the_clients_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  let item_ids = list.flat_map(novice_tables.sets(), fn(set) { set.items })
  assert list.length(item2.all(planted)) == 44
    as "the planted Item2 table holds the 44 items of the twelve Novice sets"
  list.each(item_ids, fn(id) {
    let get = fn(tables) {
      let assert Ok(row) = item2.get(tables:, id: Item2Id(id))
        as "the item exists"
      #(
        row.item2_family_id,
        row.item2_category_id,
        row.item2_type_id,
        row.power_level,
        row.item_display_id,
        row.item_source_id,
        row.flags,
        row.equipped_slot_flags,
        row.item_budget_id,
        row.item_stat_id,
        row.support_power_percentage,
      )
    }
    assert get(planted) == get(real)
      as "Item2: the planted row has the real row's columns the item formulas and the worn visuals read"
  })
  let types =
    list.map(item_ids, fn(id) {
      let assert Ok(row) = item2.get(tables: real, id: Item2Id(id))
        as "the item exists"
      row
    })
  list.each(types, fn(row) {
    let type_of = fn(tables) {
      let assert Ok(type_row) =
        item2_type.get(tables:, id: Item2TypeId(row.item2_type_id))
        as "the type exists"
      #(type_row.item_slot_id, type_row.flags)
    }
    assert type_of(planted) == type_of(real)
      as "Item2Type: the planted row has the real row's slot and flags"
    let family_of = fn(tables) {
      let assert Ok(family) =
        item2_family.get(tables:, id: Item2FamilyId(row.item2_family_id))
        as "the family exists"
      family.flags
    }
    assert family_of(planted) == family_of(real)
      as "Item2Family: the planted row has the real row's flags"
    let category_of = fn(tables) {
      let assert Ok(category) =
        item2_category.get(tables:, id: Item2CategoryId(row.item2_category_id))
        as "the category exists"
      #(category.flags, category.armor_modifier)
    }
    assert category_of(planted) == category_of(real)
      as "Item2Category: the planted row has the real row's flags and armorModifier"
    let assert Ok(type_row) =
      item2_type.get(tables: real, id: Item2TypeId(row.item2_type_id))
      as "the type exists"
    let slot_of = fn(tables) {
      let assert Ok(slot) =
        item_slot.get(tables:, id: ItemSlotId(type_row.item_slot_id))
        as "the slot exists"
      #(slot.equipped_slot_flags, slot.armor_modifier)
    }
    assert slot_of(planted) == slot_of(real)
      as "ItemSlot: the planted row has the real row's equippedSlotFlags and armorModifier"
  })
}

pub fn the_planted_formulas_levels_and_spells_are_the_clients_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  list.each(novice_tables.formulas(), fn(formula) {
    let get = fn(tables) {
      let assert Ok(row) =
        game_formula.get(tables:, id: GameFormulaId(formula.id))
        as "the formula exists"
      row
    }
    assert get(planted) == get(real)
      as "GameFormula: the planted row has the real row's columns the formulas read"
  })
  assert list.length(creature_level.all(planted)) == 50
    as "the planted CreatureLevel table holds levels 1 to 50"
  list.each(
    list.map(creature_level.all(planted), fn(row) { row.id }),
    fn(level) {
      let get = fn(tables) {
        let assert Ok(row) =
          creature_level.get(tables:, id: CreatureLevelId(level))
          as "the level exists"
        row.unit_property_value07
      }
      assert get(planted) == get(real)
        as "CreatureLevel: the planted row has the real row's Base Health"
    },
  )
  list.each(novice_tables.spell4_ids_and_bases(), fn(pair) {
    let get = fn(tables) {
      let assert Ok(row) = spell4.get(tables:, id: Spell4Id(pair.0))
        as "the spell exists"
      row.spell4_base_id_base_spell
    }
    assert get(planted) == get(real) && get(real) == pair.1
      as "Spell4: the planted row has the real row's Spell4Base id"
  })
  list.each(list.map(spell_level.all(planted), fn(row) { row.id }), fn(id) {
    let get = fn(tables) {
      let assert Ok(row) = spell_level.get(tables:, id: SpellLevelId(id))
        as "the row exists"
      #(row.class_id, row.character_level, row.prerequisite_id, row.spell4_id)
    }
    assert get(planted) == get(real)
      as "SpellLevel: the planted row has the real row's class, level, prerequisite and Spell4"
  })
}

pub fn the_planted_item_display_source_entries_and_displays_are_the_clients_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let planted = character_tables.shared()
  assert list.length(item_display_source_entry.all(planted)) == 42
    as "the planted ItemDisplaySourceEntry table holds the 21 item types of the sets for each of the sources 75 and 76"
  list.each(item_display_source_entry.all(planted), fn(entry) {
    let assert Ok(row) =
      item_display_source_entry.get(
        tables: real,
        id: ItemDisplaySourceEntryId(entry.id),
      )
      as "the real table holds the planted entry's id"
    assert entry
      == item_display_source_entry.ItemDisplaySourceEntry(..row, icon: "")
      as "ItemDisplaySourceEntry: the planted row has the real row's source, type, levels and display"
  })
  list.each(item_display.all(planted), fn(display) {
    let assert Ok(row) =
      item_display.get(tables: real, id: ItemDisplayId(display.id))
      as "the real ItemDisplay table holds the planted display"
    assert row.id == display.id
  })
  let displays =
    list.map(item_display_source_entry.all(planted), fn(entry) {
      entry.item_display_id
    })
  assert list.all(displays, fn(display) {
    list.any(item_display.all(planted), fn(row) { row.id == display })
  })
    as "every display a planted entry names has a planted ItemDisplay row"
}
