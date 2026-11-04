//// What a character holds on entering the world, from the client's tables: the
//// Novice weapon, one ability per level-1 spell of its class, and the gear's
//// properties. The client grants none of it (the server sends it), so the
//// server reads the rows the client keeps for it.
////
//// ```
//// CharacterCreation (start 4, enabled) ─▶ a set per class and faction:
////      its items ─▶ item_property ─▶ the gear's properties, the weapon and its slot
//// SpellLevel (class, level 1, no prerequisite) ─▶ Spell4 ─▶ Spell4Base ids
//// both, once, when the tables load ─▶ Loadouts ─▶ of(class, faction)
//// ```
////
//// - **The set** is the PreTutorial CharacterCreation row (characterCreationStartEnum
////   4) of the character's class and faction: the first row of the pair, in id
////   order, since its other rows differ only in race and sex
////   (`Item2.novice_set`). Every class and faction a player can make has one,
////   or the load fails.
//// - **The weapon** is the set's item whose equipped slot flags hold WeaponPrimary,
////   bit 16 (0x10000), and it is equipped in slot 16: the item's slot index is
////   the bit's (`0x1403afb10`, `lua.ActionBarFrame.InitializeBars`).
//// - **The abilities** are the class's SpellLevel rows of level 1 with no
////   prerequisite, in id order, each as the Spell4Base id of its Spell4 row
////   (`SpellLevel.spell4Id`).
//// - **Health** is CreatureLevel's Base Health at the character's level, rounded,
////   plus the armor's (`player.level1_base_health`, a server rule: the client
////   holds none for a player).

import genesis_prime/game/item_property.{
  type ItemProperties, type ItemPropertyError,
}
import genesis_prime/game/level
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/creature_level
import genesis_prime/table/id.{
  type ClassId, type Item2Id, type Spell4BaseId, ClassId, CreatureLevelId,
  Item2Id, Spell4BaseId, Spell4Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// A character's loadout: the weapon and the slot it is equipped in, the
/// abilities as Spell4Base ids in bar order, and what the gear gives.
pub type Loadout {
  Loadout(
    weapon: Item2Id,
    weapon_slot: Int,
    abilities: List(Spell4BaseId),
    properties: ItemProperties,
  )
}

/// The loadout of each class and faction, built once when the tables load.
type Loadouts {
  Loadouts(by_set: Dict(#(Int, Int), Loadout))
}

/// The CharacterCreation start enum of the Novice (PreTutorial) rows
/// (`Item2.novice_set`).
const novice_start = 4

/// The item columns of a CharacterCreation row, in order.
fn items_of(row row: CharacterCreation) -> List(Int) {
  [
    row.item_id0,
    row.item_id01,
    row.item_id02,
    row.item_id03,
    row.item_id04,
    row.item_id05,
    row.item_id06,
    row.item_id07,
    row.item_id08,
    row.item_id09,
    row.item_id010,
    row.item_id011,
    row.item_id012,
    row.item_id013,
    row.item_id014,
    row.item_id015,
  ]
  |> list.filter(fn(item) { item != 0 })
}

/// The loadouts as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`); a row a formula reads that the
/// tables lack, or a class and faction a player can make with no set, fails the
/// load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: loadouts_key, build: fn(tables) {
    build(tables)
    |> result.map_error(fn(error) { describe(error:) })
  })
}

/// Why the loadouts cannot be built from the tables, each a missing row or an
/// item the formulas do not read.
type LoadoutError {
  /// An item's properties cannot be given.
  ItemFailed(error: ItemPropertyError)
  /// GameFormula row 145, the highest level, is missing.
  NoHighestLevel
  /// CreatureLevel has no row for a level a character can have.
  NoCreatureLevel(level: Int)
  /// A row a player can make has no Novice set for its class and faction.
  NoNoviceSet(creation_id: Int, class_id: Int, faction_id: Int)
  /// A Novice set holds no weapon.
  NoWeapon(creation_id: Int)
  /// A class has no level-1 SpellLevel row without a prerequisite.
  NoAbilities(class_id: Int)
  /// A SpellLevel row names a Spell4 row the table lacks.
  NoSpell(spell_level_id: Int, spell4_id: Int)
}

/// A sentence that says why, naming the table and the row, for the message the
/// server stops with.
fn describe(error error: LoadoutError) -> String {
  case error {
    ItemFailed(error:) -> item_property.describe(error:)
    NoHighestLevel -> "the table GameFormula has no row 145"
    NoCreatureLevel(level:) ->
      "the table CreatureLevel has no row " <> int.to_string(level)
    NoNoviceSet(creation_id:, class_id:, faction_id:) ->
      "the table CharacterCreation has no PreTutorial row for class "
      <> int.to_string(class_id)
      <> " faction "
      <> int.to_string(faction_id)
      <> ", which row "
      <> int.to_string(creation_id)
      <> " makes"
    NoWeapon(creation_id:) ->
      "CharacterCreation row "
      <> int.to_string(creation_id)
      <> " holds no weapon: no item is equipped in WeaponPrimary"
    NoAbilities(class_id:) ->
      "the table SpellLevel has no level-1 row without a prerequisite for class "
      <> int.to_string(class_id)
    NoSpell(spell_level_id:, spell4_id:) ->
      "the table Spell4 has no row "
      <> int.to_string(spell4_id)
      <> ", which SpellLevel row "
      <> int.to_string(spell_level_id)
      <> " names"
  }
}

const loadouts_key: table_store.DerivedKey(Loadouts) =
  table_store.DerivedKey("Loadouts")

fn build(tables: table_store.Tables) -> Result(Loadouts, LoadoutError) {
  let rows = character_creation.all(tables)
  let novice =
    list.filter(rows, fn(row) {
      row.character_creation_start_enum == novice_start
      && row.enabled
      && !row.costume_only
    })
  use Nil <- result.try(health_rows(tables:))
  use sets <- result.try(
    list.try_fold(novice, dict.new(), fn(sets, row) {
      let key = #(row.class_id, row.faction_id)
      case dict.has_key(sets, key) {
        True -> Ok(sets)
        False ->
          build_set(tables:, row:)
          |> result.map(dict.insert(sets, key, _))
      }
    }),
  )
  use Nil <- result.try(
    list.try_each(rows, fn(row) {
      use <- bool.guard(!row.enabled || row.costume_only, Ok(Nil))
      case dict.has_key(sets, #(row.class_id, row.faction_id)) {
        True -> Ok(Nil)
        False ->
          Error(NoNoviceSet(
            creation_id: row.id,
            class_id: row.class_id,
            faction_id: row.faction_id,
          ))
      }
    }),
  )
  Ok(Loadouts(by_set: sets))
}

/// Every level a character can have, 1 to the highest level, has a CreatureLevel
/// row, which `max_health` reads.
fn health_rows(tables tables: table_store.Tables) -> Result(Nil, LoadoutError) {
  use highest <- result.try(
    level.highest_level(tables)
    |> result.replace_error(NoHighestLevel),
  )
  int.range(from: 1, to: highest + 1, with: Ok(Nil), run: fn(checked, level) {
    use Nil <- result.try(checked)
    case creature_level.get(tables:, id: CreatureLevelId(level)) {
      Ok(_) -> Ok(Nil)
      Error(Nil) -> Error(NoCreatureLevel(level:))
    }
  })
}

fn build_set(
  tables tables: table_store.Tables,
  row row: CharacterCreation,
) -> Result(Loadout, LoadoutError) {
  let items = items_of(row:)
  use properties <- result.try(
    list.try_map(items, item_property.of_item(tables:, item2_id: _))
    |> result.try(item_property.sum)
    |> result.map_error(ItemFailed),
  )
  use weapon <- result.try(weapon_of(tables:, row:, items:))
  use abilities <- result.try(abilities_of(tables:, class_id: row.class_id))
  Ok(Loadout(
    weapon: Item2Id(weapon.0),
    weapon_slot: weapon.1,
    abilities:,
    properties:,
  ))
}

/// The set's weapon and the slot it is equipped in: the item whose equipped slot
/// flags hold WeaponPrimary, and the index of that flag's bit.
fn weapon_of(
  tables tables: table_store.Tables,
  row row: CharacterCreation,
  items items: List(Int),
) -> Result(#(Int, Int), LoadoutError) {
  use flagged <- result.try(
    list.try_map(items, fn(item) {
      item_property.equipped_slot_flags(tables:, item2_id: item)
      |> result.map(fn(flags) { #(item, flags) })
    })
    |> result.map_error(ItemFailed),
  )
  case list.find(flagged, fn(pair) { item_property.is_weapon(pair.1) }) {
    Ok(#(item, flags)) -> Ok(#(item, lowest_bit(flags)))
    Error(Nil) -> Error(NoWeapon(creation_id: row.id))
  }
}

/// The index of the lowest bit set in a number above 0: the slot a flag stands
/// for.
fn lowest_bit(flags: Int) -> Int {
  case int.bitwise_and(flags, 1) {
    1 -> 0
    _ -> 1 + lowest_bit(int.bitwise_shift_right(flags, 1))
  }
}

fn abilities_of(
  tables tables: table_store.Tables,
  class_id class_id: Int,
) -> Result(List(Spell4BaseId), LoadoutError) {
  let rows =
    spell_level.all(tables)
    |> list.filter(fn(row) {
      row.class_id == class_id
      && row.character_level == 1
      && row.prerequisite_id == 0
    })
  use <- bool.guard(rows == [], Error(NoAbilities(class_id:)))
  list.try_map(rows, fn(row) {
    spell4.get(tables:, id: Spell4Id(row.spell4_id))
    |> result.replace_error(NoSpell(
      spell_level_id: row.id,
      spell4_id: row.spell4_id,
    ))
    |> result.map(fn(spell) { Spell4BaseId(spell.spell4_base_id_base_spell) })
  })
}

/// The loadout of a class and faction, or `Error(Nil)` for a pair no
/// CharacterCreation row of the Novice start has, which the load refuses for a
/// pair a player can make.
pub fn of(
  tables tables: table_store.Tables,
  class_id class_id: ClassId,
  faction_id faction_id: Int,
) -> Result(Loadout, Nil) {
  let Loadouts(by_set:) = table_store.derived(tables:, key: loadouts_key)
  let ClassId(class_id) = class_id
  dict.get(by_set, #(class_id, faction_id))
}

/// A player's maximum health: the Base Health of CreatureLevel's row of its
/// level plus the gear's, rounded (`player.level1_base_health`). `Error(Nil)`
/// when the table has no row for the level.
pub fn max_health(
  tables tables: table_store.Tables,
  loadout loadout: Loadout,
  level level: Int,
) -> Result(Int, Nil) {
  creature_level.get(tables:, id: CreatureLevelId(level))
  |> result.map(fn(row) {
    float.round(row.unit_property_value07 +. loadout.properties.base_health)
  })
}
