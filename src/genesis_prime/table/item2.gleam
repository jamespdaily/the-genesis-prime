//// STUB of the generated module for the client table Item2: the types and signatures only.

import genesis_prime/table/store
import genesis_prime/table/tbl_file

pub type Item2 {
  Item2(
    id: Int,
    item_budget_id: Int,
    item_stat_id: Int,
    item_rune_instance_id: Int,
    item_quality_id: Int,
    item_special_id00: Int,
    item_imbuement_id: Int,
    item2_family_id: Int,
    item2_category_id: Int,
    item2_type_id: Int,
    item_display_id: Int,
    item_source_id: Int,
    class_required: Int,
    race_required: Int,
    faction2_id_required: Int,
    power_level: Int,
    required_level: Int,
    required_item_level: Int,
    prerequisite_id: Int,
    equipped_slot_flags: Int,
    max_stack_count: Int,
    max_charges: Int,
    expiration_time_minutes: Int,
    quest2_id_activation: Int,
    quest2_id_activation_required: Int,
    quest_objective_activation_required: Int,
    tradeskill_additive_id: Int,
    tradeskill_catalyst_id: Int,
    housing_decor_info_id: Int,
    housing_warplot_boss_token_id: Int,
    generic_unlock_set_id: Int,
    flags: Int,
    bind_flags: Int,
    buy_from_vendor_stack_count: Int,
    currency_type_id0: Int,
    currency_type_id1: Int,
    currency_amount0: Int,
    currency_amount1: Int,
    currency_type_id0_sell_to_vendor: Int,
    currency_type_id1_sell_to_vendor: Int,
    currency_amount0_sell_to_vendor: Int,
    currency_amount1_sell_to_vendor: Int,
    item_color_set_id: Int,
    support_power_percentage: Float,
    localized_text_id_name: Int,
    localized_text_id_tooltip: Int,
    button_template: String,
    button_icon: String,
    sound_event_id_equip: Int,
  )
}

pub const schema =
  tbl_file.Schema(
    table: "Item2",
    file: "Item2",
    record_size: 208,
    columns: [
      tbl_file.Column(name: "ID", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "itemBudgetId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "itemStatId", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "itemRuneInstanceId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "itemQualityId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "itemSpecialId00", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "itemImbuementId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "item2FamilyId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "item2CategoryId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "item2TypeId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "itemDisplayId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "itemSourceId", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "classRequired", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "raceRequired", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "faction2IdRequired",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "powerLevel", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "requiredLevel", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "requiredItemLevel",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "prerequisiteId", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "equippedSlotFlags",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "maxStackCount", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "maxCharges", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "expirationTimeMinutes",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "quest2IdActivation",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "quest2IdActivationRequired",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "questObjectiveActivationRequired",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "tradeskillAdditiveId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "tradeskillCatalystId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "housingDecorInfoId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "housingWarplotBossTokenId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "genericUnlockSetId",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "flags", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "bindFlags", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "buyFromVendorStackCount",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "currencyTypeId0", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "currencyTypeId1", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "currencyAmount0", column_type: tbl_file.Integer32),
      tbl_file.Column(name: "currencyAmount1", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "currencyTypeId0SellToVendor",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "currencyTypeId1SellToVendor",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "currencyAmount0SellToVendor",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "currencyAmount1SellToVendor",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "itemColorSetId", column_type: tbl_file.Integer32),
      tbl_file.Column(
        name: "supportPowerPercentage",
        column_type: tbl_file.Float32,
      ),
      tbl_file.Column(
        name: "localizedTextIdName",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(
        name: "localizedTextIdTooltip",
        column_type: tbl_file.Integer32,
      ),
      tbl_file.Column(name: "buttonTemplate", column_type: tbl_file.Utf16Text),
      tbl_file.Column(name: "buttonIcon", column_type: tbl_file.Utf16Text),
      tbl_file.Column(
        name: "soundEventIdEquip",
        column_type: tbl_file.Integer32,
      ),
    ],
  )

const index = 122

pub fn entry() -> store.Entry {
  todo
}

pub fn get(tables: store.Tables, id: Int) -> Result(Item2, Nil) {
  todo
}

pub fn all(tables: store.Tables) -> List(Item2) {
  todo
}
