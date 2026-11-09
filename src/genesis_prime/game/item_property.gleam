//// What one item gives the unit that wears it, by the client's own item
//// formulas: Assault Rating, Support Rating, Armor, Base Health and, for a
//// shield, the shield's capacity, mitigation, regeneration and reboot time. The
//// client builds these for an item's tooltip (BuildItemProperties 0x14040c310)
//// and never adds items into a unit's properties, so the server sums them
//// (`sum`, `player.level1_gear_properties`).
////
//// ```
//// Item2 row ─▶ type, family, category, slot rows ─▶ builder (power level, slot
////              and armor modifiers, shield or not)
////   builder ─▶ ratings 0x14040df10 ─▶ armor 0x14040e340 ─▶ health 0x14040e3d0
////              (a shield item gets 0x14040dbf0 in their place)
//// ```
////
//// - **The builder** reads the Item2 row, its type, family and category rows and
////   the ItemSlot of its type: the slot's armorModifier, the category's times it,
////   the item's power level, and whether it is a shield (0x14040c610).
//// - **Ratings** apply to armor and to any item whose equipped slot flags hold
////   0x10580, never to family 26: the slot's modifier times a curve at the power
////   level (GameFormula 1288's for a weapon, family 2, else 549's) times
////   `(1 - |b|) x GameFormula 1265's first value + 1`, of which Assault Rating
////   takes `1 - (b + 1) / 2` and Support Rating `(b + 1) / 2`, with b the item's
////   supportPowerPercentage (0x14040df10).
//// - **Armor** is armor items' curve times the category's and the slot's
////   modifiers (0x14040e340); **Base Health** is armor items' GameFormula 67
////   curve times the slot's modifier (0x14040e3d0).
//// - **A shield** (the type, category or family flags hold 0x400 and the
////   equipped slot flags 0x8000) gets GameFormula 548's curve times a factor for
////   its capacity, and mitigation, regeneration and reboot time, each read at
////   the middle of its range because the item has no budget (0x14040dbf0).
//// - **A curve** is `f0 x e^(f01 x m) + f02 x m^f03` of the GameFormula row at
////   `m = power level - dataint0` (0x14041da70, 0x14041dc90, 0x14041e450). The
////   armor curve is GameFormula 547's below the power level GameFormula 1286
////   names (0x14041deb0).
//// - **What the code does not read:** an item with a budget or a stat, a
////   level-scaled item (Item2.flags bit 3), a PvP item (flags 0x8000), a proxy
////   item (flags 0x4000, whose fields FillItemInfo 0x1404445d0 takes from
////   GameFormula 1214's item), a supportPowerPercentage beyond -1 to 1 and an armor curve from power level
////   50 up are items whose properties the client's code gives by branches this
////   code does not follow, so such an item is an `Unread` error, which fails the
////   load.

import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  GameFormulaId, Item2CategoryId, Item2FamilyId, Item2Id, Item2TypeId,
  ItemProficiencyId, ItemSlotId, ItemSpecialId,
}
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_proficiency
import genesis_prime/table/item_slot
import genesis_prime/table/item_special
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A shield item's properties: ShieldCapacityMax (property 41),
/// ShieldMitigationMax (175), ShieldRegenPct (176) and ShieldRebootTime (178),
/// in milliseconds.
pub type Shield {
  Shield(
    capacity_max: Float,
    mitigation_max: Float,
    regen_percent: Float,
    reboot_time_ms: Int,
  )
}

/// What an item, or a set of items, gives: Base Health (property 7), Assault
/// Rating (35), Support Rating (36), Armor (42) and the shield.
pub type ItemProperties {
  ItemProperties(
    base_health: Float,
    assault_rating: Float,
    support_rating: Float,
    armor: Float,
    shield: Option(Shield),
  )
}

/// Why an item's properties cannot be given.
pub type ItemPropertyError {
  /// A table the formulas read has no row with this id.
  NoRow(table: String, id: Int)
  /// An item whose properties the client's code gives by a branch this code does
  /// not follow (see the module's last point).
  Unread(item2_id: Int, why: String)
  /// A GameFormula row's curve has no value at the power level: a negative
  /// offset to a fractional power.
  NoCurveValue(formula: Int, level: Int)
  /// A set holds two shield items, whose properties would share one property
  /// each.
  TwoShields
}

/// A sentence that says why, for the load's message: the table and the row
/// that is missing, or the item that is not read.
pub fn describe(error error: ItemPropertyError) -> String {
  case error {
    NoRow(table:, id:) ->
      "the table " <> table <> " has no row " <> int.to_string(id)
    Unread(item2_id:, why:) ->
      "the item " <> int.to_string(item2_id) <> " is not read: " <> why
    NoCurveValue(formula:, level:) ->
      "the curve of GameFormula "
      <> int.to_string(formula)
      <> " has no value at power level "
      <> int.to_string(level)
    TwoShields -> "a set holds two shield items"
  }
}

/// No properties.
fn none() -> ItemProperties {
  ItemProperties(
    base_health: 0.0,
    assault_rating: 0.0,
    support_rating: 0.0,
    armor: 0.0,
    shield: None,
  )
}

/// The properties of the items together: each of the ratings, the armor and the
/// health added, and the one shield an item gives, which is none when no item
/// is a shield.
pub fn sum(
  items items: List(ItemProperties),
) -> Result(ItemProperties, ItemPropertyError) {
  let shields =
    list.filter_map(items, fn(item) { option.to_result(item.shield, Nil) })
  use shield <- result.try(case shields {
    [] -> Ok(None)
    [shield] -> Ok(Some(shield))
    [_, _, ..] -> Error(TwoShields)
  })
  Ok(ItemProperties(
    base_health: float.sum(list.map(items, fn(item) { item.base_health })),
    assault_rating: float.sum(list.map(items, fn(item) { item.assault_rating })),
    support_rating: float.sum(list.map(items, fn(item) { item.support_rating })),
    armor: float.sum(list.map(items, fn(item) { item.armor })),
    shield:,
  ))
}

/// The flags the type, the category and the family of an item hold, joined,
/// that mark an item that may take a slot, and with the slot's the shield
/// (FillItemInfo 0x1404445d0, PrepareItemPropertyBuilder 0x14040c610).
const slotted_flag = 0x400

/// The flags of an item's type, category and family, joined, that mark an item
/// that stacks (0x1406d50f0).
const stackable_flag = 0x4

/// Item2.flags 0x10000: the item cannot be destroyed (0x1403c1360).
const undeletable_flag = 0x10000

/// Item2.bindFlags bit 1: only one of the item may be equipped (0x1403ad100,
/// `Item2.bindFlags`).
const unique_equipped_flag = 2

/// Item2.flags bit 0: the item needs level 1 whatever its required level says
/// (0x1403b4710).
const no_level_flag = 1

/// The equipped slot flags of the shield slot, ArmorShields.
const shield_slot_flags = 0x8000

/// The equipped slot flags an item has when the ratings apply to it though it is
/// not armor: 0x10580, of which bit 16 is WeaponPrimary (0x14040df10).
const rated_slot_flags = 0x10580

/// The equipped slot flags of WeaponPrimary, bit 16, in which a weapon is
/// equipped (`equipped_slot_flags`).
const weapon_slot_flags = 0x10000

const armor_family = 1

const weapon_family = 2

const unrated_family = 26

/// Item2.flags bit 3: the item scales with the wearer's level.
const level_scaled_flag = 8

/// Item2.flags 0x8000: a PvP item.
const pvp_flag = 0x8000

/// Item2.flags 0x4000: an item whose fields the client takes from the proxy item
/// of GameFormula 1214 (FillItemInfo 0x1404445d0).
const proxy_flag = 0x4000

/// The Item2Family of an item the slot is never looked up for (0x14040c610).
const family_without_slot = 33

/// The Item2Category of an item the slot is never looked up for (0x14040c610).
const category_without_slot = 143

/// What the builder knows of an item: its row, power level, the modifiers and
/// whether it is a shield (PrepareItemPropertyBuilder 0x14040c610).
type Builder {
  Builder(
    item: item2.Item2,
    power_level: Int,
    slot_modifier: Float,
    armor_modifier: Float,
    equipped_slot_flags: Int,
    is_shield: Bool,
  )
}

/// The rows an item's slot comes from: its own, the category's and the slot's
/// modifiers, whether it may take a slot and its equipped slot flags. Only a
/// missing row is an error: the slot does not depend on the item's budget, stat
/// or flags (FillItemInfo 0x1404445d0, PrepareItemPropertyBuilder 0x14040c610).
type Slotting {
  Slotting(
    item: item2.Item2,
    category_armor_modifier: Float,
    slot_modifier: Float,
    slotted: Bool,
    equipped_slot_flags: Int,
  )
}

/// An Item2 row with the rows of its type, category and family, and the flags of
/// those three joined (0x1403c1360 and 0x1406d50f0 join them the same way).
type Rows {
  Rows(
    item: item2.Item2,
    type_row: item2_type.Item2Type,
    category: item2_category.Item2Category,
    joined_flags: Int,
  )
}

/// The item's own Item2 row; a missing one is `NoRow`.
fn item_row(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(item2.Item2, ItemPropertyError) {
  item2.get(tables:, id: Item2Id(item2_id))
  |> result.replace_error(NoRow(table: "Item2", id: item2_id))
}

fn rows(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Rows, ItemPropertyError) {
  use item <- result.try(item_row(tables:, item2_id:))
  use type_row <- result.try(
    item2_type.get(tables:, id: Item2TypeId(item.item2_type_id))
    |> result.replace_error(NoRow(table: "Item2Type", id: item.item2_type_id)),
  )
  use family <- result.try(
    item2_family.get(tables:, id: Item2FamilyId(item.item2_family_id))
    |> result.replace_error(NoRow(
      table: "Item2Family",
      id: item.item2_family_id,
    )),
  )
  use category <- result.try(
    item2_category.get(tables:, id: Item2CategoryId(item.item2_category_id))
    |> result.replace_error(NoRow(
      table: "Item2Category",
      id: item.item2_category_id,
    )),
  )
  Ok(Rows(
    item:,
    type_row:,
    category:,
    joined_flags: int.bitwise_or(
      int.bitwise_or(type_row.flags, category.flags),
      family.flags,
    ),
  ))
}

fn slotting(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Slotting, ItemPropertyError) {
  use Rows(item:, type_row:, category:, joined_flags:) <- result.try(rows(
    tables:,
    item2_id:,
  ))
  let slotted = int.bitwise_and(joined_flags, slotted_flag) != 0
  let has_slot =
    item.item2_family_id != family_without_slot
    && item.item2_category_id != category_without_slot
  use slot <- result.try(case has_slot {
    True ->
      item_slot.get(tables:, id: ItemSlotId(type_row.item_slot_id))
      |> result.replace_error(NoRow(
        table: "ItemSlot",
        id: type_row.item_slot_id,
      ))
      |> result.map(Some)
    False -> Ok(None)
  })
  let slot_flags = case slot, slotted {
    Some(slot), True -> slot.equipped_slot_flags
    Some(_), False | None, _ -> 0
  }
  Ok(Slotting(
    item:,
    category_armor_modifier: category.armor_modifier,
    slot_modifier: case slot {
      Some(slot) -> slot.armor_modifier
      None -> 1.0
    },
    slotted:,
    equipped_slot_flags: int.bitwise_or(slot_flags, item.equipped_slot_flags),
  ))
}

fn builder(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Builder, ItemPropertyError) {
  use slotting <- result.try(slotting(tables:, item2_id:))
  let item = slotting.item
  use <- bool.guard(
    item.item_budget_id != 0 || item.item_stat_id != 0,
    Error(Unread(item2_id:, why: "it has a budget or a stat")),
  )
  use <- bool.guard(
    int.bitwise_and(item.flags, level_scaled_flag) != 0,
    Error(Unread(item2_id:, why: "its power level scales with the wearer")),
  )
  use <- bool.guard(
    int.bitwise_and(item.flags, pvp_flag) != 0,
    Error(Unread(item2_id:, why: "it is a PvP item")),
  )
  use <- bool.guard(
    int.bitwise_and(item.flags, proxy_flag) != 0,
    Error(Unread(
      item2_id:,
      why: "its flags hold 0x4000, so the client takes its fields from a proxy item",
    )),
  )
  Ok(Builder(
    item:,
    power_level: item.power_level,
    slot_modifier: slotting.slot_modifier,
    armor_modifier: slotting.category_armor_modifier *. slotting.slot_modifier,
    equipped_slot_flags: slotting.equipped_slot_flags,
    is_shield: slotting.slotted
      && int.bitwise_and(slotting.equipped_slot_flags, shield_slot_flags) != 0,
  ))
}

/// The equipped slot flags of the item: its slot's and its own, joined
/// (FillItemInfo 0x1404445d0). A weapon's hold 0x10000, bit 16, WeaponPrimary,
/// the slot a weapon is equipped in. Only a missing row is an error: an item
/// with a budget, a stat or scaled flags has its slot all the same.
pub fn equipped_slot_flags(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Int, ItemPropertyError) {
  slotting(tables:, item2_id:)
  |> result.map(fn(slotting) { slotting.equipped_slot_flags })
}

/// Whether the item may take an equipped slot at all: the flags of its type,
/// category and family, joined, hold 0x400. The client refuses an item that
/// lacks it at every equipped slot of location 0, whatever equipped slot flags
/// its own row holds (CheckItemEquipSlot 0x1403b11b0). Only a missing row is an
/// error.
pub fn is_slotted(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Bool, ItemPropertyError) {
  use rows <- result.map(rows(tables:, item2_id:))
  int.bitwise_and(rows.joined_flags, slotted_flag) != 0
}

/// Whether only one of the item may be equipped: Item2.bindFlags holds bit 1
/// (CheckItemMove 0x1403ad100, `Item2.bindFlags`). Only a missing row is an
/// error.
pub fn is_unique_equipped(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Bool, ItemPropertyError) {
  use item <- result.map(item_row(tables:, item2_id:))
  int.bitwise_and(item.bind_flags, unique_equipped_flag) != 0
}

/// What the client's equip check reads of an item (CheckEquipRequirements
/// 0x1403b4710): masks of the races and classes that may wear it, the faction
/// it needs, the prerequisites its own row and its ItemSpecial give, the mask
/// of its proficiency and the level it needs.
pub type EquipRequirements {
  EquipRequirements(
    /// Item2.raceRequired: bit race - 1 for each race; 0 for any.
    race_mask: Int,
    /// Item2.classRequired: bit class - 1 for each class; 0 for any.
    class_mask: Int,
    /// Item2.faction2IdRequired; 0 for any.
    faction_id: Int,
    /// The Prerequisite ids that must all pass, those that are 0 left out: the
    /// item's own, then its ItemSpecial's when that special has a spell to
    /// activate.
    prerequisite_ids: List(Int),
    /// ItemProficiency.bitMask of the item's category; 0 for none.
    proficiency_mask: Int,
    /// Item2.requiredLevel, or 1 when it is 0 or the item's flags hold bit 0.
    required_level: Int,
  )
}

/// The item's equip requirements. Only a missing Item2, category or ItemSpecial
/// row is an error; a category with no ItemProficiency row needs no proficiency
/// (HasItemProficiency 0x1403ca2b0).
pub fn equip_requirements(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(EquipRequirements, ItemPropertyError) {
  use rows <- result.try(rows(tables:, item2_id:))
  let item = rows.item
  use special_prerequisite <- result.map(case item.item_special_id00 {
    0 -> Ok(0)
    special_id ->
      item_special.get(tables:, id: ItemSpecialId(special_id))
      |> result.replace_error(NoRow(table: "ItemSpecial", id: special_id))
      |> result.map(fn(special) {
        case special.spell4_id_on_activate {
          0 -> 0
          _ -> special.prerequisite_id_generic00
        }
      })
  })
  let proficiency_mask = case
    item_proficiency.get(
      tables:,
      id: ItemProficiencyId(rows.category.item_proficiency_id),
    )
  {
    Ok(proficiency) -> proficiency.bit_mask
    Error(Nil) -> 0
  }
  EquipRequirements(
    race_mask: item.race_required,
    class_mask: item.class_required,
    faction_id: item.faction2_id_required,
    prerequisite_ids: list.filter(
      [item.prerequisite_id, special_prerequisite],
      fn(id) { id != 0 },
    ),
    proficiency_mask:,
    required_level: case
      item.required_level == 0
      || int.bitwise_and(item.flags, no_level_flag) != 0
    {
      True -> 1
      False -> item.required_level
    },
  )
}

/// The most the item's stack holds, for an item that stacks: Item2.maxStackCount
/// when the flags of its type, category and family, joined, hold 0x4 (the drop
/// handler 0x1406d50f0 merges a drop only onto such an item), `None` for an item
/// that does not stack. Only a missing row is an error. The client takes the
/// fields of an item whose Item2.flags hold 0x4000 from GameFormula 1214's item
/// (FillItemInfo 0x1404445d0), which this does not read: such an item is judged
/// by its own row, a gap open in #333.
pub fn stack_limit(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Option(Int), ItemPropertyError) {
  use rows <- result.map(rows(tables:, item2_id:))
  case int.bitwise_and(rows.joined_flags, stackable_flag) {
    0 -> None
    _ -> Some(rows.item.max_stack_count)
  }
}

/// Whether the player may destroy the item: Item2.flags lacks 0x10000
/// (SendItemDelete 0x1403c1360 refuses with Item_CannotBeDeleted when it holds
/// it). The proxy gap of `stack_limit` applies (#333).
pub fn deletable(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Bool, ItemPropertyError) {
  use item <- result.map(item_row(tables:, item2_id:))
  int.bitwise_and(item.flags, undeletable_flag) == 0
}

/// The bag index an item is equipped at: the index of the lowest bit set in its
/// equipped slot flags, below bit 31 (GetSlot 0x140418a50, `ItemSlot.
/// equippedSlotFlags`). `Error(Nil)` for flags with no such bit.
pub fn equipped_slot_index(slot_flags slot_flags: Int) -> Result(Int, Nil) {
  lowest_slot_bit(slot_flags:, index: 0)
}

fn lowest_slot_bit(
  slot_flags slot_flags: Int,
  index index: Int,
) -> Result(Int, Nil) {
  use <- bool.guard(index >= slot_bits, Error(Nil))
  case int.bitwise_and(slot_flags, 1) {
    1 -> Ok(index)
    _ ->
      lowest_slot_bit(
        slot_flags: int.bitwise_shift_right(slot_flags, 1),
        index: index + 1,
      )
  }
}

/// How many bits of the equipped slot flags name a bag index: the client takes
/// an index below 31 (GetSlot 0x140418a50, `opcode.0x111.shared_item_unnamed`).
const slot_bits = 31

/// Whether the equipped slot flags are a weapon's, WeaponPrimary.
pub fn is_weapon(slot_flags slot_flags: Int) -> Bool {
  int.bitwise_and(slot_flags, weapon_slot_flags) != 0
}

/// The properties one item gives, by the client's formulas.
pub fn of_item(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(ItemProperties, ItemPropertyError) {
  use builder <- result.try(builder(tables:, item2_id:))
  case builder.is_shield {
    True -> shield(tables:, builder:)
    False -> worn(tables:, builder:)
  }
}

/// An armor piece's or a weapon's properties: ratings, armor and health.
fn worn(
  tables tables: table_store.Tables,
  builder builder: Builder,
) -> Result(ItemProperties, ItemPropertyError) {
  let family = builder.item.item2_family_id
  let is_armor = family == armor_family
  use #(assault_rating, support_rating) <- result.try(
    case
      family != unrated_family
      && {
        is_armor
        || int.bitwise_and(builder.equipped_slot_flags, rated_slot_flags) != 0
      }
    {
      True -> ratings(tables:, builder:)
      False -> Ok(#(0.0, 0.0))
    },
  )
  use armor <- result.try(case is_armor {
    True -> armor(tables:, builder:)
    False -> Ok(0.0)
  })
  use base_health <- result.try(case is_armor {
    True ->
      formula(tables:, id: base_health_formula)
      |> result.try(fn(row) { curve(row:, level: builder.power_level) })
      |> result.map(fn(curve) { curve *. builder.slot_modifier })
    False -> Ok(0.0)
  })
  Ok(ItemProperties(
    base_health:,
    assault_rating:,
    support_rating:,
    armor:,
    shield: None,
  ))
}

/// The GameFormula row of Base Health's curve (0x14040e3d0).
const base_health_formula = 67

/// The GameFormula row of the armor curve below the power level 1286 names
/// (0x14041deb0).
const armor_formula = 547

/// The GameFormula row of the power level from which the armor curve is another
/// (0x14041deb0), which this code does not follow.
const armor_curve_change_formula = 1286

/// The GameFormula row of a shield's capacity curve (0x14041d850).
const shield_capacity_formula = 548

/// The GameFormula row of a weapon's rating curve (0x14041dc90).
const weapon_rating_formula = 1288

/// The GameFormula row of the rating curve of every other item (0x14041da70).
const item_rating_formula = 549

/// The GameFormula row that holds the first factor of the ratings' ratio
/// (0x14040df10).
const rating_factor_formula = 1265

/// The GameFormula row of a shield's capacity and regeneration factors
/// (0x14041d420, 0x14041d540).
const shield_factor_formula = 1260

/// The GameFormula row of a shield's mitigation and reboot-time factors
/// (0x14041d660, 0x14041d780).
const shield_reboot_formula = 1261

fn formula(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(game_formula.GameFormula, ItemPropertyError) {
  game_formula.get(tables:, id: GameFormulaId(id))
  |> result.replace_error(NoRow(table: "GameFormula", id:))
}

/// A GameFormula row's curve at a power level: `f0 x e^(f01 x m) + f02 x
/// m^f03` with `m = level - dataint0` (0x14041da70).
fn curve(
  row row: game_formula.GameFormula,
  level level: Int,
) -> Result(Float, ItemPropertyError) {
  let offset = int.to_float(level - row.dataint0)
  use power <- result.try(
    float.power(offset, row.datafloat03)
    |> result.replace_error(NoCurveValue(formula: row.id, level:)),
  )
  Ok(
    row.datafloat0
    *. float.exponential(row.datafloat01 *. offset)
    +. row.datafloat02
    *. power,
  )
}

/// The Assault Rating and Support Rating of an item (0x14040df10).
fn ratings(
  tables tables: table_store.Tables,
  builder builder: Builder,
) -> Result(#(Float, Float), ItemPropertyError) {
  let item = builder.item
  let support = item.support_power_percentage
  use <- bool.guard(
    support <. -1.0 || support >. 1.0,
    Error(Unread(
      item2_id: item.id,
      why: "its supportPowerPercentage is beyond -1 to 1",
    )),
  )
  use curve_row <- result.try(
    formula(tables:, id: case item.item2_family_id == weapon_family {
      True -> weapon_rating_formula
      False -> item_rating_formula
    }),
  )
  use curve <- result.try(curve(row: curve_row, level: builder.power_level))
  use factor_row <- result.try(formula(tables:, id: rating_factor_formula))
  let value =
    builder.slot_modifier
    *. curve
    *. {
      { 1.0 -. float.absolute_value(support) } *. factor_row.datafloat0 +. 1.0
    }
  let support_share = { support +. 1.0 } /. 2.0
  Ok(#({ 1.0 -. support_share } *. value, support_share *. value))
}

/// The Armor of an armor item (0x14040e340): the armor curve at the power level
/// times the category's and the slot's modifiers.
fn armor(
  tables tables: table_store.Tables,
  builder builder: Builder,
) -> Result(Float, ItemPropertyError) {
  use change <- result.try(formula(tables:, id: armor_curve_change_formula))
  use <- bool.guard(
    builder.power_level >= change.dataint0,
    Error(Unread(
      item2_id: builder.item.id,
      why: "its armor curve is GameFormula 1286's or 1287's, which are not followed",
    )),
  )
  use row <- result.try(formula(tables:, id: armor_formula))
  use curve <- result.try(curve(row:, level: builder.power_level))
  Ok(curve *. builder.armor_modifier)
}

/// A shield item's properties (0x14040dbf0), each factor read at 0.5, the
/// middle of its range, which is what an item with no budget gets.
fn shield(
  tables tables: table_store.Tables,
  builder builder: Builder,
) -> Result(ItemProperties, ItemPropertyError) {
  use capacity_row <- result.try(formula(tables:, id: shield_capacity_formula))
  use capacity_curve <- result.try(curve(
    row: capacity_row,
    level: builder.power_level,
  ))
  use factors <- result.try(formula(tables:, id: shield_factor_formula))
  use reboot <- result.try(formula(tables:, id: shield_reboot_formula))
  Ok(
    ItemProperties(
      ..none(),
      shield: Some(Shield(
        capacity_max: capacity_curve
          *. between(low: factors.datafloat0, high: factors.datafloat01),
        mitigation_max: between(
          low: reboot.datafloat0,
          high: reboot.datafloat01,
        ),
        regen_percent: between(
          low: factors.datafloat02,
          high: factors.datafloat03,
        ),
        reboot_time_ms: whole_number_between(
          first: reboot.dataint0,
          second: reboot.dataint01,
        ),
      )),
    ),
  )
}

/// The value halfway between two, floored at 0 (0x14041d420).
fn between(low low: Float, high high: Float) -> Float {
  float.max(0.0, low +. { high -. low } *. 0.5)
}

/// The whole number halfway between two bounds, as the client cuts it: with the
/// bounds put low to high, `low + (high - low) x 0.5 + 0.00001` (0x14041fac0,
/// for a fraction of 0.5, which the swap of the bounds leaves at 0.5).
fn whole_number_between(first first: Int, second second: Int) -> Int {
  let low = int.min(first, second)
  let high = int.max(first, second)
  float.truncate(
    int.to_float(low) +. int.to_float(high - low) *. 0.5 +. 0.00001,
  )
}
