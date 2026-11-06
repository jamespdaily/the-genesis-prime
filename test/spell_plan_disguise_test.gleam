//// The DisguiseOutfit rows of the plan (`genesis_prime/game/spell_plan` `modifier_of`,
//// `genesis_prime/game/effect_kind`). What the plan refuses is tested on rows in memory
//// and on a load of the three item tables alone, since each planted load of the spell
//// tables puts 4 MiB of terms into the run; the Engineer's own tree is read from the
//// client's tables. Expected values come from these places:
//// - `Spell4Effects.effectType.112`: dataBits02 is an ItemDisplay worn in its item's
////   slot, dataBits01 an ItemDisplay of a WeaponPrimary item, dataBits00 and dataBits08
////   an outfit that only 0x905 draws; dataBits03 is not read. The rows: 112543 (spell
////   47860, targetFlags 1, ItemDisplay 4807, 10,250 ms, behind caster prerequisite
////   30100), 178142 (7221, 30101) and 106894 (spell 45791, dataBits01 119, flags 2).
//// - `-- ItemDisplay 4807 7221 119`: item2TypeId 346, 346 and 51; `-- Item2Type 346 51`:
////   itemSlotId 64 and 20; `-- ItemSlot 64 20`: EngineerMechSuit and WeaponPrimary.
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the area.
//// - CLAUDE.md: a missing row fails the load.

import client_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/look.{Disguise, Shown}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type PropertyModifier, Always, GatedOnCaster, LookChange, PropertyModifier,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{
  ItemDisplayId, ItemSlotId, PrerequisiteId, Spell4BaseId, Spell4EffectsId,
}
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_slot
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/list
import gleam/option.{None}
import owned_key
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

/// The spell the in-memory rows are said to belong to: the Eradication ExoSuit's.
const eradication = 47_860

/// A DisguiseOutfit row in memory aimed at the caster, every other column 0.
fn blank(id id: Int) -> Spell4Effects {
  spell_tables.blank_effect(
    id:,
    spell: eradication,
    effect_type: 112,
    target_flags: 1,
  )
}

/// A DisguiseOutfit row of the Eradication ExoSuit as the client holds it: 112543.
fn exile_suit_row() -> Spell4Effects {
  Spell4Effects(
    ..blank(id: 112_543),
    duration_time: 10_250,
    data_bits02: 4807,
    data_bits03: 1,
    prerequisite_id_caster_apply: 30_100,
  )
}

/// The item rows the reads need, in memory as tables of three: the displays 4807 and
/// 7221 of item type 346 (slot 64) and 119 of item type 51 (slot 20), as the client
/// holds them, and the faults: display 9001 of type 9002, which has slot 0, display
/// 9003 of type 9004, which has no row, and display 9005 of type 9006, whose slot 77
/// has no ItemSlot row.
fn with_items(body body: fn(table_store.Tables) -> a) -> a {
  let display = fn(id, item2_type) {
    planted_table.row(item_display.schema, [
      #("ID", Integer(id)),
      #("item2TypeId", Integer(item2_type)),
    ])
  }
  let item_type = fn(id, slot) {
    planted_table.row(item2_type.schema, [
      #("ID", Integer(id)),
      #("itemSlotId", Integer(slot)),
    ])
  }
  let slot = fn(id) {
    planted_table.row(item_slot.schema, [#("ID", Integer(id))])
  }
  use folder <- planted_table.in_folder([
    planted_table.file(item_display.schema, [
      display(119, 51),
      display(4807, 346),
      display(7221, 346),
      display(9001, 9002),
      display(9003, 9004),
      display(9005, 9006),
    ]),
    planted_table.file(item2_type.schema, [
      item_type(51, 20),
      item_type(346, 64),
      item_type(9002, 0),
      item_type(9006, 77),
    ]),
    planted_table.file(item_slot.schema, [slot(20), slot(64)]),
  ])
  let assert Ok(tables) =
    table_store.load(
      under: owned_key.new(),
      from: folder,
      entries: [item_display.entry(), item2_type.entry(), item_slot.entry()],
      requirements: [],
      derivations: [],
    )
    as "the planted item tables load"
  let result = body(tables)
  table_store.unload(tables)
  result
}

fn modifier_of(
  tables tables: table_store.Tables,
  effect effect: Spell4Effects,
) -> Result(PropertyModifier, spell_plan.PlanError) {
  spell_plan.modifier_of(
    tables:,
    spell4_id: eradication,
    effect:,
    condition: Always,
  )
}

fn suit(display display: Int) -> look.Disguise {
  Disguise(shown: [
    Shown(item_slot: ItemSlotId(64), display: ItemDisplayId(display)),
  ])
}

// ---- the effect kind ----

pub fn type_112_is_read_for_the_rows_that_include_the_caster_only_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 112) == effect_kind.DisguiseOutfit
  assert effect_kind.is_read(effect_type: 112)
  list.each([1, 3, 5, 7], fn(flags) {
    assert effect_kind.is_row_read(effect_type: 112, target_flags: flags)
      as "bit 1 of targetFlags is the caster"
  })
  list.each([2, 4, 6], fn(flags) {
    assert !effect_kind.is_row_read(effect_type: 112, target_flags: flags)
      as "a row aimed only at others cannot change their look from the caster's connection"
  })
}

// ---- the rows of the plan ----

pub fn a_databits02_display_is_a_timed_look_change_in_its_item_types_slot_test() -> Nil {
  use <- owned_test.run(60_000)
  // 4807 is of item type 346, whose itemSlotId is 64. The delay, the flags bit 2 and the
  // phases are given values the row 112543 does not hold, so each is read from its column.
  let effect =
    Spell4Effects(
      ..exile_suit_row(),
      delay_time: 500,
      flags: 2,
      phase_flags: 3,
      emm_comparison: 1,
      emm_value: 2,
    )
  assert with_items(body: fn(tables) { modifier_of(tables:, effect:) })
    == Ok(PropertyModifier(
      effect_id: Spell4EffectsId(112_543),
      phase_flags: 3,
      change: LookChange(disguise: suit(display: 4807)),
      row: LastingRow(delay_ms: 500, duration_ms: 10_250, until_removed: True),
      condition: Always,
      tag: spend.AtLeast(value: 2),
      armor: None,
    ))
}

pub fn a_databits01_display_of_a_weapon_is_drawn_in_slot_20_test() -> Nil {
  use <- owned_test.run(60_000)
  // 106894: dataBits01 119, flags 2; ItemDisplay 119 is of item type 51, ItemSlot 20.
  let effect = Spell4Effects(..blank(id: 106_894), data_bits01: 119, flags: 2)
  let assert Ok(row) =
    with_items(body: fn(tables) { modifier_of(tables:, effect:) })
  assert row.change
    == LookChange(
      disguise: Disguise(shown: [
        Shown(item_slot: ItemSlotId(20), display: ItemDisplayId(119)),
      ]),
    )
}

pub fn a_row_with_an_outfit_or_no_display_fails_the_load_naming_the_row_and_the_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  // dataBits00 is a Creature2OutfitInfo id (154 of 156 rows), dataBits08 an ItemDisplay
  // that comes with one: only 0x905 draws them. 2 rows name no display at all.
  let refused = fn(effect: Spell4Effects, reason) {
    assert with_items(body: fn(tables) { modifier_of(tables:, effect:) })
      == Error(spell_plan.DisguiseNotRead(
        spell4_id: eradication,
        effect_id: effect.id,
        reason:,
      ))
  }
  refused(
    Spell4Effects(..exile_suit_row(), id: 99_001, data_bits00: 5),
    spell_plan.OutfitNeedsMessage0x905,
  )
  refused(
    Spell4Effects(..exile_suit_row(), id: 99_002, data_bits08: 4807),
    spell_plan.OutfitNeedsMessage0x905,
  )
  refused(
    Spell4Effects(..blank(id: 99_003), duration_time: 1000),
    spell_plan.NamesNoDisplay,
  )
}

pub fn a_display_with_no_row_or_no_slot_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let refusal = fn(effect: Spell4Effects) {
    with_items(body: fn(tables) { modifier_of(tables:, effect:) })
  }
  assert refusal(Spell4Effects(..blank(id: 99_004), data_bits02: 8999))
    == Error(spell_plan.NoRow(table: "ItemDisplay", id: 8999))
    as "no ItemDisplay row"
  assert refusal(Spell4Effects(..blank(id: 99_005), data_bits02: 9003))
    == Error(spell_plan.NoRow(table: "Item2Type", id: 9004))
    as "the display's item type has no row"
  assert refusal(Spell4Effects(..blank(id: 99_006), data_bits02: 9005))
    == Error(spell_plan.NoRow(table: "ItemSlot", id: 77))
    as "the item type's slot has no row (0x140466d20: the slot is an ItemSlot id)"
  assert refusal(Spell4Effects(..blank(id: 99_007), data_bits02: 9001))
    == Error(spell_plan.DisguiseNotRead(
      spell4_id: eradication,
      effect_id: 99_007,
      reason: spell_plan.DisplayHasNoSlot(item_display_id: 9001),
    ))
    as "itemSlotId 0 is no slot"
}

pub fn a_databits03_of_1_is_read_the_same_as_0_test() -> Nil {
  use <- owned_test.run(60_000)
  // Both ExoSuit rows hold 1 and no client code reads a type 112 row, so the gap is
  // stated in the plan's doc and the row reads as it does with 0.
  let with_one = exile_suit_row()
  let with_zero = Spell4Effects(..with_one, data_bits03: 0)
  assert with_items(body: fn(tables) { modifier_of(tables:, effect: with_one) })
    == with_items(body: fn(tables) { modifier_of(tables:, effect: with_zero) })
}

// ---- the client's own rows ----

pub fn mode_eradicates_two_exosuit_rows_are_read_from_the_clients_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  // Mode: Eradicate, 47866, starts 47860 by its Proxy 112552; 47860 holds 112543 and
  // 178142 (`-- Spell4Effects spellId=47860`).
  let assert Ok(mode) = spell_plan.in_plans(plans:, base: Spell4BaseId(31_779))
    as "Mode: Eradicate, 47866, is of Spell4Base 31779 (`-- Spell4 47866`)"
  let assert Ok(proxy) =
    list.find(mode.proxies, fn(proxy) {
      proxy.spell.spell4_id == id.Spell4Id(eradication)
    })
  let assert [exile, dominion] = proxy.spell.modifiers
  assert exile.effect_id == Spell4EffectsId(112_543)
  assert exile.change == LookChange(disguise: suit(display: 4807))
  assert exile.row
    == LastingRow(delay_ms: 0, duration_ms: 10_250, until_removed: False)
  let assert GatedOnCaster(gates: [exile_gate]) = exile.condition
  assert prerequisite.id(prerequisite: exile_gate) == PrerequisiteId(30_100)
  assert dominion.effect_id == Spell4EffectsId(178_142)
  assert dominion.change == LookChange(disguise: suit(display: 7221))
  assert dominion.row
    == LastingRow(delay_ms: 0, duration_ms: 10_250, until_removed: False)
  let assert GatedOnCaster(gates: [dominion_gate]) = dominion.condition
  assert prerequisite.id(prerequisite: dominion_gate) == PrerequisiteId(30_101)
}
