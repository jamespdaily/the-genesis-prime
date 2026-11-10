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
//// - **A budget** is the points an item's ItemBudget shares among the entries of
////   its ItemStat (AddItemBudgetProperties 0x14040ca70, which runs before the
////   values above). Each entry of kind 1 names a UnitProperty2 and gives
////   `share x scale x valuePerPoint`, with `scale` the budget curve at the power
////   level (0x14041e670) times the slot's modifier (0x14040d060, 0x14040d3d0,
////   0x14040db30). All of it is 32-bit float arithmetic, step by step, so it is
////   worked out with `genesis_prime/message/float32`. A value adds onto the
////   property's own: Base Health, Assault Rating, Support Rating and Armor are
////   the fields above, every other property is in `budget`. On a shield the
////   shares of properties 41, 175, 176 and 178 replace the 0.5 of their
////   factors. An entry the client refuses (a property that is no item property,
////   is off the item's slot, is a shield property on a non-shield) is
////   `Refused`.
//// - **What the code does not read** is a `Gap`: a level-scaled item
////   (Item2.flags bit 3), a PvP item (flags 0x8000), an imbued item, a rune, a
////   proxy item (flags 0x4000, whose fields FillItemInfo 0x1404445d0 takes from
////   GameFormula 1214's item), a supportPowerPercentage beyond -1 to 1, an armor
////   curve from power level 50 up, and a budget entry on a ResourceMax property
////   are items whose properties the client's code gives by branches this code
////   does not follow, so such an item is an `Unread` error, with its gap, which
////   names the open issue that closes it.
//// - **A random stat entry** (kind 2) names an ItemRandomStatGroup, and the
////   item's random-stat word (`genesis_prime/game/random_stat_word`) says which
////   row of it the entry takes, in table order: that row's property is the
////   entry's, with the entry's own share of the budget (0x14040e6d0). A word
////   with no data gives the entry nothing. A word with data whose choice is 0 or
////   past the group is `RandomStatsRefused`: the client fails the whole build
////   and keeps the item without its instance properties. Two entries that take
////   one property add on a non-shield and give one share on a shield. A kind-4
////   entry (a property crafting picks) gives nothing: the open issue #53
////   closes that, and no client row mixes it with a kind-2 entry.

import genesis_prime/game/random_stat_word
import genesis_prime/message/float32
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type UnitProperty2Id, GameFormulaId, Item2CategoryId, Item2FamilyId, Item2Id,
  Item2TypeId, ItemBudgetId, ItemProficiencyId, ItemSlotId, ItemSpecialId,
  ItemStatId, PrerequisiteId, UnitProperty2Id,
}
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_budget
import genesis_prime/table/item_proficiency
import genesis_prime/table/item_random_stat
import genesis_prime/table/item_slot
import genesis_prime/table/item_special
import genesis_prime/table/item_stat
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/unit_property2
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict.{type Dict}
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
/// Rating (35), Support Rating (36), Armor (42), the shield, and every other
/// property a budget gives, each with its value.
pub type ItemProperties {
  ItemProperties(
    base_health: Float,
    assault_rating: Float,
    support_rating: Float,
    armor: Float,
    shield: Option(Shield),
    budget: Dict(UnitProperty2Id, Float),
  )
}

/// A branch of the client's code that this code does not follow, so an item that
/// takes it is not read. Each names the open issue that closes it, or none.
pub type Gap {
  /// Item2.flags bit 3: the power level scales with the wearer (0x14040f710).
  /// Open issue #666.
  LevelScaled
  /// Item2.flags 0x8000. Open issue #56.
  PvpItem
  /// Item2.flags 0x4000: the client takes the item's fields from GameFormula
  /// 1214's item (FillItemInfo 0x1404445d0). Open issue #333.
  ProxyItem
  /// Item2.itemImbuementId is not 0 (FillItemInfo 0x1404445d0 copies it; what it adds is not decoded). Open issue #666.
  Imbued
  /// Item2Family 33: the budget curve is another (0x14041f1b0). Open issue #666.
  Rune
  /// An armor item from the power level GameFormula 1286 names: its armor curve
  /// is GameFormula 1286's or 1287's. Open issue #666.
  LateArmorCurve
  /// A budget entry on a ResourceMax property. The player's class resource sets
  /// that base (`genesis_prime/game/class_resource`), so nothing is open.
  ResourceMaximum
  /// A supportPowerPercentage beyond -1 to 1, which no client row holds.
  SupportBeyondRange
  /// An ItemStat entry of a kind other than 0, 1, 2 and 4, which no client row
  /// holds.
  StatKind(kind: Int)
}

/// The open issue that closes a gap, `None` when none is open.
pub fn gap_issue(gap gap: Gap) -> Option(Int) {
  case gap {
    LevelScaled | Imbued | Rune | LateArmorCurve -> Some(666)
    PvpItem -> Some(56)
    ProxyItem -> Some(333)
    ResourceMaximum | SupportBeyondRange | StatKind(..) -> None
  }
}

/// Why the client refuses a budget entry (0x95 from 0x14040db30).
pub type Refusal {
  /// A shield property (41, 175, 176, 178) on an item that is no shield.
  ShieldPropertyOnNonShield
  /// A property whose UnitProperty2.flags lack 4, so it is no item property.
  NotAnItemProperty
  /// A property whose UnitProperty2.equippedSlotFlags share no bit with the
  /// item's slot flags.
  OffTheItemsSlot
}

/// Why an item's properties cannot be given.
pub type ItemPropertyError {
  /// A table the formulas read has no row with this id.
  NoRow(table: String, id: Int)
  /// An item whose properties the client's code gives by a branch this code does
  /// not follow (see the module's last point).
  Unread(item2_id: Int, gap: Gap)
  /// An item whose budget has an entry the client refuses (AddItemBudgetProperties
  /// 0x14040ca70 fails with 0x95): the server gives this error in place of the
  /// item's properties.
  Refused(item2_id: Int, property_id: Int, why: Refusal)
  /// A GameFormula row's curve has no value at the power level: a negative
  /// offset to a fractional power.
  NoCurveValue(formula: Int, level: Int)
  /// A set holds two shield items, whose properties would share one property
  /// each.
  TwoShields
  /// An item whose random-stat word has data and a choice the client refuses for
  /// its kind-2 entry `entry` (0 to 4): 0, or past its group's rows (0x14040e6d0
  /// fails the build with 0x70).
  RandomStatsRefused(item2_id: Int, random_stats: Int, entry: Int)
}

/// A sentence that says why, for the load's message: the table and the row
/// that is missing, or the item that is not read.
pub fn describe(error error: ItemPropertyError) -> String {
  case error {
    NoRow(table:, id:) ->
      "the table " <> table <> " has no row " <> int.to_string(id)
    Unread(item2_id:, gap:) ->
      "the item " <> int.to_string(item2_id) <> " is not read: " <> why(gap:)
    Refused(item2_id:, property_id:, why:) ->
      "the item "
      <> int.to_string(item2_id)
      <> " has a budget entry on property "
      <> int.to_string(property_id)
      <> " that the client refuses: "
      <> case why {
        ShieldPropertyOnNonShield -> "it is a shield property on a non-shield"
        NotAnItemProperty -> "the property's flags lack 4"
        OffTheItemsSlot -> "the property is for another slot than the item's"
      }
    NoCurveValue(formula:, level:) ->
      "the curve of GameFormula "
      <> int.to_string(formula)
      <> " has no value at power level "
      <> int.to_string(level)
    TwoShields -> "a set holds two shield items"
    RandomStatsRefused(item2_id:, random_stats:, entry:) ->
      "the item "
      <> int.to_string(item2_id)
      <> " has the random-stat word "
      <> int.to_string(random_stats)
      <> ", whose choice for entry "
      <> int.to_string(entry)
      <> " is 0 or past its group's rows, which the client refuses"
  }
}

fn why(gap gap: Gap) -> String {
  case gap {
    LevelScaled -> "its power level scales with the wearer"
    PvpItem -> "it is a PvP item"
    ProxyItem ->
      "its flags hold 0x4000, so the client takes its fields from a proxy item"
    Imbued -> "it is imbued"
    Rune -> "it is a rune, whose budget curve is another"
    LateArmorCurve ->
      "its armor curve is GameFormula 1286's or 1287's, which are not followed"
    ResourceMaximum ->
      "its budget gives a ResourceMax property, whose base the player's class resource sets"
    SupportBeyondRange -> "its supportPowerPercentage is beyond -1 to 1"
    StatKind(kind:) ->
      "its ItemStat has an entry of kind " <> int.to_string(kind)
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
    budget: dict.new(),
  )
}

/// The properties of the items together: each of the ratings, the armor, the
/// health and the budget properties added, and the one shield an item gives, which
/// is none when no item is a shield.
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
    base_health: sum_in_32_bits(items:, field: fn(item) { item.base_health }),
    assault_rating: sum_in_32_bits(items:, field: fn(item) {
      item.assault_rating
    }),
    support_rating: sum_in_32_bits(items:, field: fn(item) {
      item.support_rating
    }),
    armor: sum_in_32_bits(items:, field: fn(item) { item.armor }),
    shield:,
    budget: list.fold(items, dict.new(), fn(total, item) {
      dict.combine(total, item.budget, float32.sum)
    }),
  ))
}

/// One field of the items added in order, each addition rounded to 32 bits as the
/// client's entry adds (0x14040db30).
fn sum_in_32_bits(
  items items: List(ItemProperties),
  field field: fn(ItemProperties) -> Float,
) -> Float {
  list.fold(items, 0.0, fn(total, item) { float32.sum(total, field(item)) })
}

/// The flags the type, the category and the family of an item hold, joined,
/// that mark an item that may take a slot, and with the slot's the shield
/// (FillItemInfo 0x1404445d0, PrepareItemPropertyBuilder 0x14040c610).
const slotted_flag = 0x400

/// The flags of an item's type, category and family, joined, that mark an item
/// that stacks (0x1406d50f0).
const stackable_flag = 0x4

/// The flags of an item's type, category and family, joined, that mark a bag
/// (`Item2.bags`).
const bag_flag = 0x100

/// The flags of an item's type, category and family, joined, that let a vendor buy the item
/// (`0x14040d160.sell_cleared`).
const sellable_flag = 0x20

/// The Item2Family of quest items, which no vendor buys (`0x14040d160.sell_cleared`).
const quest_item_family = 24

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

/// The Item2Family of an item the slot is never looked up for (0x14040c610): the
/// runes, whose budget curve is another (0x14041f1b0).
const family_without_slot = 33

/// The Item2Family of runes.
const rune_family = family_without_slot

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
  let proxy = is_proxy(item)
  let slotted = !proxy && int.bitwise_and(joined_flags, slotted_flag) != 0
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
  Ok(
    Slotting(
      item:,
      category_armor_modifier: category.armor_modifier,
      slot_modifier: case slot {
        Some(slot) -> slot.armor_modifier
        None -> 1.0
      },
      slotted:,
      equipped_slot_flags: case proxy {
        True -> 0
        False -> int.bitwise_or(slot_flags, item.equipped_slot_flags)
      },
    ),
  )
}

/// Whether the item is a proxy: the client gives it the joined flags 0x10004 and
/// no equipped slot flags, whatever its type, category and family hold
/// (FillItemInfo 0x1404445d0, `0x1404445d0.proxy`).
pub fn is_proxy(item: item2.Item2) -> Bool {
  int.bitwise_and(item.flags, proxy_flag) != 0
}

fn builder(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Builder, ItemPropertyError) {
  use builder <- result.try(slot_builder(tables:, item2_id:))
  let item = builder.item
  use <- bool.guard(
    int.bitwise_and(item.flags, level_scaled_flag) != 0,
    Error(Unread(item2_id:, gap: LevelScaled)),
  )
  use <- bool.guard(
    int.bitwise_and(item.flags, pvp_flag) != 0,
    Error(Unread(item2_id:, gap: PvpItem)),
  )
  use <- bool.guard(
    item.item_imbuement_id != 0,
    Error(Unread(item2_id:, gap: Imbued)),
  )
  use <- bool.guard(
    item.item2_family_id == rune_family,
    Error(Unread(item2_id:, gap: Rune)),
  )
  use <- bool.guard(is_proxy(item), Error(Unread(item2_id:, gap: ProxyItem)))
  Ok(builder)
}

/// The builder's view of the item's slot and power level, whatever its flags: only a
/// missing row is an error.
fn slot_builder(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Builder, ItemPropertyError) {
  use slotting <- result.map(slotting(tables:, item2_id:))
  Builder(
    item: slotting.item,
    power_level: slotting.item.power_level,
    slot_modifier: slotting.slot_modifier,
    armor_modifier: slotting.category_armor_modifier *. slotting.slot_modifier,
    equipped_slot_flags: slotting.equipped_slot_flags,
    is_shield: slotting.slotted
      && int.bitwise_and(slotting.equipped_slot_flags, shield_slot_flags) != 0,
  )
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
  !is_proxy(rows.item) && int.bitwise_and(rows.joined_flags, slotted_flag) != 0
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

/// The load's checks that the rows an item's equip check reads exist, so a
/// table without them fails the server's start and not a player's equip: the
/// Prerequisite row of each Item2 and ItemSpecial that names one, and the
/// ItemSpecial row of each Item2 that names one (CheckEquipRequirements
/// 0x1403b4710 reads all three; an id of 0 names none).
pub fn requirements() -> List(table_store.Requirement) {
  list.append(budget_requirements(), equip_requirement_rows())
}

/// The load's checks that the rows an item's budget reads exist: the ItemBudget
/// and ItemStat rows of each Item2 that names one, and the UnitProperty2 row of
/// each ItemStat entry of kind 1 (AddItemBudgetProperties 0x14040ca70 fails the
/// whole branch without one; an id of 0 names none).
fn budget_requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "Item2",
      column: "itemBudgetId",
      to_table: "ItemBudget",
      missing: fn(tables) {
        item2.all(tables)
        |> list.map(fn(item) { item.item_budget_id })
        |> list.filter(fn(budget_id) {
          budget_id != 0
          && result.is_error(item_budget.get(
            tables:,
            id: ItemBudgetId(budget_id),
          ))
        })
      },
    ),
    table_store.Requirement(
      from_table: "Item2",
      column: "itemStatId",
      to_table: "ItemStat",
      missing: fn(tables) {
        item2.all(tables)
        |> list.map(fn(item) { item.item_stat_id })
        |> list.filter(fn(stat_id) {
          stat_id != 0
          && result.is_error(item_stat.get(tables:, id: ItemStatId(stat_id)))
        })
      },
    ),
  ]
  |> list.append(
    list.index_map(stat_data_columns, fn(column, index) {
      stat_property_requirement(column:, index:)
    }),
  )
}

/// The columns of an ItemStat's five entries' data, in the order of `stat_entries`.
const stat_data_columns = [
  "itemStatData00", "itemStatData01", "itemStatData02", "itemStatData03",
  "itemStatData04",
]

/// The kind and the data of each of an ItemStat's five entries.
fn stat_entries(stat stat: item_stat.ItemStat) -> List(#(Int, Int)) {
  [
    #(stat.item_stat_type_enum00, stat.item_stat_data00),
    #(stat.item_stat_type_enum01, stat.item_stat_data01),
    #(stat.item_stat_type_enum02, stat.item_stat_data02),
    #(stat.item_stat_type_enum03, stat.item_stat_data03),
    #(stat.item_stat_type_enum04, stat.item_stat_data04),
  ]
}

/// The check that the UnitProperty2 row the `index`th entry of an ItemStat names
/// exists, for the entries of kind 1, the data of which is a property.
fn stat_property_requirement(
  column column: String,
  index index: Int,
) -> table_store.Requirement {
  table_store.Requirement(
    from_table: "ItemStat",
    column:,
    to_table: "UnitProperty2",
    missing: fn(tables) {
      item_stat.all(tables)
      |> list.filter_map(fn(stat) {
        stat_entries(stat:) |> list.drop(index) |> list.first
      })
      |> list.filter_map(fn(pair) {
        let #(kind, property_id) = pair
        case
          kind == 1
          && result.is_error(unit_property2.get(
            tables:,
            id: UnitProperty2Id(property_id),
          ))
        {
          True -> Ok(property_id)
          False -> Error(Nil)
        }
      })
    },
  )
}

fn equip_requirement_rows() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "Item2",
      column: "prerequisiteId",
      to_table: "Prerequisite",
      missing: fn(tables) {
        item2.all(tables)
        |> list.map(fn(item) { item.prerequisite_id })
        |> missing_prerequisites(tables:)
      },
    ),
    table_store.Requirement(
      from_table: "Item2",
      column: "itemSpecialId00",
      to_table: "ItemSpecial",
      missing: fn(tables) {
        item2.all(tables)
        |> list.map(fn(item) { item.item_special_id00 })
        |> list.filter(fn(special_id) {
          special_id != 0
          && result.is_error(item_special.get(
            tables:,
            id: ItemSpecialId(special_id),
          ))
        })
      },
    ),
    table_store.Requirement(
      from_table: "ItemSpecial",
      column: "prerequisiteIdGeneric00",
      to_table: "Prerequisite",
      missing: fn(tables) {
        item_special.all(tables)
        |> list.map(fn(special) { special.prerequisite_id_generic00 })
        |> missing_prerequisites(tables:)
      },
    ),
  ]
}

/// The ids of these that name a Prerequisite row the tables lack; 0 names none.
fn missing_prerequisites(
  ids ids: List(Int),
  tables tables: table_store.Tables,
) -> List(Int) {
  list.filter(ids, fn(id) {
    id != 0
    && result.is_error(prerequisite_table.get(tables:, id: PrerequisiteId(id)))
  })
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

/// The number of inventory slots the item opens when it is worn in a bag slot:
/// Item2.maxStackCount for a bag, `None` for any other item; the size is 1
/// when maxStackCount and maxCharges are both above 1 (FillItemInfo
/// 0x140444a27 to 0x140444a45). A bag is an item whose joined flags hold 0x100
/// and whose Item2.flags lack 0x4000, because the client gives a proxy the
/// joined flags 0x10004 (FillItemInfo 0x1404445d0, `0x1404445d0.proxy`,
/// `Item2.bags`). Only a missing row is an error.
pub fn bag_size(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Option(Int), ItemPropertyError) {
  use rows <- result.map(rows(tables:, item2_id:))
  case
    !is_proxy(rows.item) && int.bitwise_and(rows.joined_flags, bag_flag) != 0
  {
    True ->
      case rows.item.max_stack_count > 1 && rows.item.max_charges > 1 {
        True -> Some(1)
        False -> Some(rows.item.max_stack_count)
      }
    False -> None
  }
}

/// Whether the client lets the item be sold at all: the rule of BuildItemPrices, which keeps a
/// sell price only when the joined flags hold 0x20 and the family is not Quest Item.
pub fn sellable(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Bool, ItemPropertyError) {
  use rows <- result.map(rows(tables:, item2_id:))
  // A proxy's joined flags are 0x10004 (`is_proxy`), which lack 0x20.
  !is_proxy(rows.item)
  && int.bitwise_and(rows.joined_flags, sellable_flag) != 0
  && rows.item.item2_family_id != quest_item_family
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
  random_stats random_stats: Int,
) -> Result(ItemProperties, ItemPropertyError) {
  use builder <- result.try(builder(tables:, item2_id:))
  use given <- result.try(budget(tables:, builder:, random_stats:))
  use properties <- result.map(case builder.is_shield {
    True -> shield(tables:, builder:, shares: given.shares)
    False -> worn(tables:, builder:)
  })
  with_budget(properties:, values: given.values)
}

/// What an item's budget gives: the value of each property it gives, in the
/// order of the entries, and the shares a shield's properties name.
type Given {
  Given(values: List(#(Int, Float)), shares: Dict(Int, Float))
}

/// The properties of a shield, which a budget's shares set and no value is given
/// for (0x14040db30).
const shield_properties = [
  shield_capacity_property,
  shield_mitigation_property,
  shield_regen_property,
  shield_reboot_property,
]

const shield_capacity_property = 41

const shield_mitigation_property = 175

const shield_regen_property = 176

const shield_reboot_property = 178

/// The properties an item's own formulas give, which a budget's value is added to
/// or, for a shield's, which the shield gives: Base Health, Assault Rating,
/// Support Rating, Armor and the four of a shield.
const base_health_property = 7

const assault_rating_property = 35

const support_rating_property = 36

const armor_property = 42

/// UnitProperty2.flags bit 2: the property is one an item may give (0x14040db30).
const item_property_flag = 4

const resource_slots = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

/// Whether a property is the maximum of one of the client's resource slots 0 to 10
/// (`unit_fields.resource_max_property`), whose base the player's class resource sets
/// (`genesis_prime/game/class_resource`).
fn is_resource_maximum(property_id property_id: Int) -> Bool {
  list.any(resource_slots, fn(slot) {
    unit_fields.resource_max_property(slot:) == property_id
  })
}

/// Whether a UnitProperty2 row is a property a budget gives that is in none of the
/// fields above: an item property worth something per point, that is no resource
/// maximum. The base of each is its default plus what the worn items give.
fn is_budget_property(row row: unit_property2.UnitProperty2) -> Bool {
  int.bitwise_and(row.flags, item_property_flag) != 0
  && row.value_per_point != 0.0
  && !is_resource_maximum(property_id: row.id)
  && !list.contains(
    [
      base_health_property,
      assault_rating_property,
      support_rating_property,
      armor_property,
      ..shield_properties
    ],
    row.id,
  )
}

/// The properties a budget may give that no field above holds, in id order.
pub fn budget_properties(
  tables tables: table_store.Tables,
) -> List(UnitProperty2Id) {
  unit_property2.all(tables)
  |> list.filter(fn(row) { is_budget_property(row:) })
  |> list.map(unit_property2.id)
}

/// The value each entry of the item's budget gives, and the shares of a shield's
/// properties: the points of the ItemBudget row's share times the scale, times the
/// property's valuePerPoint, in 32-bit steps (AddItemBudgetProperties 0x14040ca70,
/// 0x14040d060, 0x14040d3d0, 0x14040db30). An item with neither an ItemStat nor an ItemBudget gives nothing;
/// one with only one of them has no row for the other, which is `NoRow` (id 0).
fn budget(
  tables tables: table_store.Tables,
  builder builder: Builder,
  random_stats random_stats: Int,
) -> Result(Given, ItemPropertyError) {
  let item = builder.item
  let none = Given(values: [], shares: dict.new())
  use <- bool.guard(
    item.item_stat_id == 0 && item.item_budget_id == 0,
    Ok(none),
  )
  use stat <- result.try(
    item_stat.get(tables:, id: ItemStatId(item.item_stat_id))
    |> result.replace_error(NoRow(table: "ItemStat", id: item.item_stat_id)),
  )
  use budget_row <- result.try(
    item_budget.get(tables:, id: ItemBudgetId(item.item_budget_id))
    |> result.replace_error(NoRow(table: "ItemBudget", id: item.item_budget_id)),
  )
  let shares = [
    budget_row.budget00,
    budget_row.budget01,
    budget_row.budget02,
    budget_row.budget03,
    budget_row.budget04,
  ]
  use scale <- result.try(scale(tables:, builder:))
  list.try_fold(
    list.index_map(entries(stat:, shares:), fn(entry, index) { #(index, entry) }),
    none,
    fn(given, indexed) {
      let #(index, entry) = indexed
      give_entry(
        tables:,
        builder:,
        scale:,
        given:,
        entry:,
        choice: random_choice(random_stats:, entry: index),
      )
    },
  )
  |> result.map(fn(given) { Given(..given, values: list.reverse(given.values)) })
}

/// The entries of an ItemStat: each kind, property and share of the ItemBudget.
fn entries(
  stat stat: item_stat.ItemStat,
  shares shares: List(Float),
) -> List(#(Int, Int, Float)) {
  list.zip(stat_entries(stat:), shares)
  |> list.map(fn(entry) { #(entry.0.0, entry.0.1, entry.1) })
}

/// What the item's random-stat word chooses for one entry: nothing when the word
/// holds no data, else the entry's 1-based row in its group, 0 for none.
type Choice {
  NoData
  Chosen(entry: Int, row: Int, word: Int)
}

fn random_choice(random_stats random_stats: Int, entry entry: Int) -> Choice {
  use <- bool.guard(!random_stat_word.has_data(word: random_stats), NoData)
  Chosen(
    entry:,
    row: random_stat_word.choice(word: random_stats, entry:),
    word: random_stats,
  )
}

/// What one ItemStat entry adds to what the earlier ones gave (0x14040e6d0).
fn give_entry(
  tables tables: table_store.Tables,
  builder builder: Builder,
  scale scale: Float,
  given given: Given,
  entry entry: #(Int, Int, Float),
  choice choice: Choice,
) -> Result(Given, ItemPropertyError) {
  let #(kind, property_id, share) = entry
  case kind {
    // None.
    0 -> Ok(given)
    // A random property crafting picks: nothing is given until crafting is
    // built (open issue #53).
    4 -> Ok(given)
    // A random stat group: the word's choice picks the row.
    2 ->
      case choice {
        NoData -> Ok(given)
        Chosen(entry: index, row:, word:) ->
          case
            list.drop(random_group(tables:, group_id: property_id), row - 1)
          {
            [picked, ..] if row >= 1 ->
              give_picked(tables:, builder:, scale:, given:, share:, picked:)
            _ ->
              Error(RandomStatsRefused(
                item2_id: builder.item.id,
                random_stats: word,
                entry: index,
              ))
          }
      }
    // A property.
    1 -> give_property(tables:, builder:, scale:, given:, property_id:, share:)
    _ -> Error(Unread(item2_id: builder.item.id, gap: StatKind(kind:)))
  }
}

fn give_picked(
  tables tables: table_store.Tables,
  builder builder: Builder,
  scale scale: Float,
  given given: Given,
  share share: Float,
  picked picked: item_random_stat.ItemRandomStat,
) -> Result(Given, ItemPropertyError) {
  case picked.item_stat_type_enum {
    1 ->
      give_property(
        tables:,
        builder:,
        scale:,
        given:,
        property_id: picked.item_stat_data,
        share:,
      )
    kind -> Error(Unread(item2_id: builder.item.id, gap: StatKind(kind:)))
  }
}

fn give_property(
  tables tables: table_store.Tables,
  builder builder: Builder,
  scale scale: Float,
  given given: Given,
  property_id property_id: Int,
  share share: Float,
) -> Result(Given, ItemPropertyError) {
  entry_gives(tables:, builder:, scale:, property_id:, share:)
  |> result.map(fn(gives) { add_entry(given:, property_id:, gives:) })
}

/// The rows of an ItemRandomStatGroup in table order, which is the order the client keeps
/// them in: the row a choice b names is the b-th (`ItemRandomStat.itemRandomStatGroupId`).
pub fn random_group(
  tables tables: table_store.Tables,
  group_id group_id: Int,
) -> List(item_random_stat.ItemRandomStat) {
  item_random_stat.all(tables)
  |> list.filter(fn(row) { row.item_random_stat_group_id == group_id })
}

/// The kind and data of each of an item's five ItemStat entries, none for an item with no
/// ItemStat.
pub fn stat_entries_of(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(List(#(Int, Int)), ItemPropertyError) {
  use item <- result.try(
    item2.get(tables:, id: Item2Id(item2_id))
    |> result.replace_error(NoRow(table: "Item2", id: item2_id)),
  )
  use <- bool.guard(item.item_stat_id == 0, Ok([]))
  item_stat.get(tables:, id: ItemStatId(item.item_stat_id))
  |> result.replace_error(NoRow(table: "ItemStat", id: item.item_stat_id))
  |> result.map(fn(stat) { stat_entries(stat:) })
}

/// Whether the client's builder accepts the property for an entry of the item: `False`
/// for the refusals `entry_gives` makes with 0x95 in the client (a shield property on a
/// non-shield, a property that is no item property or is off the item's slot). Any other
/// error, a missing row or a resource maximum this code does not read, is returned. It
/// looks at the item's slot only, so an item this code leaves unread for its flags still
/// has its roll made.
pub fn takes_property(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  property_id property_id: Int,
) -> Result(Bool, ItemPropertyError) {
  use builder <- result.try(slot_builder(tables:, item2_id:))
  case entry_gives(tables:, builder:, scale: 1.0, property_id:, share: 1.0) {
    Ok(_) -> Ok(True)
    Error(Refused(..)) -> Ok(False)
    Error(error) -> Error(error)
  }
}

/// What one entry gives.
type EntryGives {
  /// A shield property: the share the shield reads.
  ShieldShare(share: Float)
  /// A property worth something: its value.
  Value(Float)
  /// A property worth 0, which the client adds no entry for.
  Nothing
}

fn add_entry(
  given given: Given,
  property_id property_id: Int,
  gives gives: EntryGives,
) -> Given {
  case gives {
    ShieldShare(share:) ->
      Given(..given, shares: dict.insert(given.shares, property_id, share))
    Value(value) ->
      Given(..given, values: [#(property_id, value), ..given.values])
    Nothing -> given
  }
}

/// The budget's scale: its curve at the power level times the slot's
/// armorModifier times the factor, which is 1 for an item built from its record
/// (0x14040d060).
fn scale(
  tables tables: table_store.Tables,
  builder builder: Builder,
) -> Result(Float, ItemPropertyError) {
  use curve <- result.map(budget_curve(tables:, level: builder.power_level))
  float32.product(float32.product(curve, builder.slot_modifier), 1.0)
}

/// What one kind-1 entry gives, or why the client refuses it (0x14040db30, 0x95).
fn entry_gives(
  tables tables: table_store.Tables,
  builder builder: Builder,
  scale scale: Float,
  property_id property_id: Int,
  share share: Float,
) -> Result(EntryGives, ItemPropertyError) {
  let item2_id = builder.item.id
  let refused = fn(why) { Error(Refused(item2_id:, property_id:, why:)) }
  use <- bool.lazy_guard(list.contains(shield_properties, property_id), fn() {
    case builder.is_shield {
      True -> Ok(ShieldShare(share:))
      False -> refused(ShieldPropertyOnNonShield)
    }
  })
  use row <- result.try(
    unit_property2.get(tables:, id: UnitProperty2Id(property_id))
    |> result.replace_error(NoRow(table: "UnitProperty2", id: property_id)),
  )
  use <- bool.guard(
    int.bitwise_and(row.flags, item_property_flag) == 0,
    refused(NotAnItemProperty),
  )
  use <- bool.guard(
    row.equipped_slot_flags != 0
      && int.bitwise_and(row.equipped_slot_flags, builder.equipped_slot_flags)
      == 0,
    refused(OffTheItemsSlot),
  )
  use <- bool.guard(
    is_resource_maximum(property_id:),
    Error(Unread(item2_id:, gap: ResourceMaximum)),
  )
  let points = float32.product(share, scale)
  case float32.product(float32.product(points, 1.0), row.value_per_point) {
    0.0 -> Ok(Nothing)
    value -> Ok(Value(value))
  }
}

/// The properties with the budget's values added: onto an item's own Base Health,
/// ratings and armor in 32 bits as the client's entry adds (0x14040db30), and into
/// `budget` for every other property.
fn with_budget(
  properties properties: ItemProperties,
  values values: List(#(Int, Float)),
) -> ItemProperties {
  list.fold(values, properties, fn(properties, entry) {
    let #(property_id, value) = entry
    let add = fn(own) { float32.sum(value, float32.rounded(own)) }
    case property_id {
      7 ->
        ItemProperties(..properties, base_health: add(properties.base_health))
      35 ->
        ItemProperties(
          ..properties,
          assault_rating: add(properties.assault_rating),
        )
      36 ->
        ItemProperties(
          ..properties,
          support_rating: add(properties.support_rating),
        )
      42 -> ItemProperties(..properties, armor: add(properties.armor))
      _ ->
        ItemProperties(
          ..properties,
          budget: dict.upsert(
            properties.budget,
            UnitProperty2Id(property_id),
            fn(held) {
              case held {
                Some(held) -> float32.sum(held, value)
                None -> value
              }
            },
          ),
        )
    }
  })
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
    budget: dict.new(),
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
pub fn curve(
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

/// The GameFormula rows of the budget's curve by power level: 1255 from its
/// dataint0 (130), 1027 from its dataint0 (50), 1028 below (0x14041e670). Each is read
/// at the level less its own dataint0.
const budget_curve_late_formula = 1255

const budget_curve_middle_formula = 1027

const budget_curve_early_formula = 1028

/// The 32-bit float the client's curve raises to the power f01 x m: 2.7182817
/// (0x14041e670), whose exact value is this 64-bit float.
const single_precision_e = 2.7182817459106445

/// The budget's curve at a power level (0x14041e670): `f0 x e^(f01 x m) + f02 x
/// m^f03` of the row the level selects, at `m = level - dataint0`, with each step
/// rounded to 32 bits as the client's single-precision arithmetic gives. The
/// growth term is the client's powf (0x1408fbfc0) of the 32-bit e, not the
/// exponential function: the two differ by one or two ulps at some levels, and
/// 0x14040db30 gives the values of item 8441 at levels 75 and 129.
fn budget_curve(
  tables tables: table_store.Tables,
  level level: Int,
) -> Result(Float, ItemPropertyError) {
  use late <- result.try(formula(tables:, id: budget_curve_late_formula))
  use middle <- result.try(formula(tables:, id: budget_curve_middle_formula))
  use row <- result.try(case level >= late.dataint0, level >= middle.dataint0 {
    True, _ -> Ok(late)
    False, True -> Ok(middle)
    False, False -> formula(tables:, id: budget_curve_early_formula)
  })
  let offset = int.to_float(level - row.dataint0)
  let no_value = NoCurveValue(formula: row.id, level:)
  use power <- result.try(
    float.power(offset, row.datafloat03) |> result.replace_error(no_value),
  )
  use growth <- result.map(
    float.power(single_precision_e, float32.product(row.datafloat01, offset))
    |> result.map(float32.rounded)
    |> result.replace_error(no_value),
  )
  float32.sum(
    float32.product(row.datafloat0, growth),
    float32.product(row.datafloat02, float32.rounded(power)),
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
    Error(Unread(item2_id: item.id, gap: SupportBeyondRange)),
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
    Error(Unread(item2_id: builder.item.id, gap: LateArmorCurve)),
  )
  use row <- result.try(formula(tables:, id: armor_formula))
  use curve <- result.try(curve(row:, level: builder.power_level))
  Ok(curve *. builder.armor_modifier)
}

/// A shield item's properties (0x14040dbf0), each factor read at the share its
/// budget gives the property, or 0.5, the middle of its range, when the budget
/// gives it none.
fn shield(
  tables tables: table_store.Tables,
  builder builder: Builder,
  shares shares: Dict(Int, Float),
) -> Result(ItemProperties, ItemPropertyError) {
  let share = fn(property_id) {
    result.unwrap(dict.get(shares, property_id), 0.5)
  }
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
          *. between(
          low: factors.datafloat0,
          high: factors.datafloat01,
          share: share(shield_capacity_property),
        ),
        mitigation_max: between(
          low: reboot.datafloat0,
          high: reboot.datafloat01,
          share: share(shield_mitigation_property),
        ),
        regen_percent: between(
          low: factors.datafloat02,
          high: factors.datafloat03,
          share: share(shield_regen_property),
        ),
        reboot_time_ms: whole_number_between(
          first: reboot.dataint0,
          second: reboot.dataint01,
          share: share(shield_reboot_property),
        ),
      )),
    ),
  )
}

/// The value a share of the way from `low` to `high`, floored at 0 (0x14041d420).
fn between(low low: Float, high high: Float, share share: Float) -> Float {
  float.max(0.0, low +. { high -. low } *. share)
}

/// The whole number a share of the way between two bounds, as the client cuts it:
/// with the bounds put low to high, `low + (high - low) x share + 0.00001`
/// truncated, the share taken from the high end when the first bound is above the
/// second (0x14041fac0).
fn whole_number_between(
  first first: Int,
  second second: Int,
  share share: Float,
) -> Int {
  let low = int.min(first, second)
  let high = int.max(first, second)
  let share = case first > second {
    True -> 1.0 -. share
    False -> share
  }
  float.truncate(
    int.to_float(low) +. int.to_float(high - low) *. share +. 0.00001,
  )
}
