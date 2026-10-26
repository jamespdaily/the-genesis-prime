//// Known rows of five of the client's tables, decoded through their generated
//// modules, against the values the `.tbl` bytes hold. Every expected value
//// names the file offset it was read from: the offset of the field in
//// `<Table>.tbl`, with the layout of the fact file's `game_table.file` (header
//// 0x60 bytes, records from the record block, 4-byte fields at multiples of 4,
//// 8-byte fields at multiples of 8, `game_table.schema`) and the column order of
//// the file's own column table. A string field holds a u64 offset from the
//// record block's start; the text sits at the file offset named beside it, UTF-16
//// little-endian. An id's row is read through the lookup array (`game_table.file`):
//// an entry of 0xFFFFFFFF is an id with no row, and an id at or past the lookup
//// count has none (`GameTableRecordById`, 0x1407c10d0). Row counts are the
//// header's u64 at 0x30 (`game_tables.ClientData`). Floats are IEEE singles
//// held as the Gleam float of the same value.
////
//// The values were read from the files by a script apart from the generator
//// (struct unpacking of the offsets given), not by the code under test.
//// Each test loads one table from the extracted client files and is skipped
//// where `GENESIS_NO_CLIENT=1`.

import client_tables
import environment
import genesis_prime/table/creature2
import genesis_prime/table/item2
import genesis_prime/table/localized_text
import genesis_prime/table/spell4
import genesis_prime/table/spline2_node
import genesis_prime/table/store
import gleam/erlang/reference
import gleam/list
import owned_test
import unitest

/// Loads one table from the extracted client files, or stops the test.
fn load(entry: store.Entry) -> store.Tables {
  let assert Ok(tables) =
    store.load(
      under: reference.new(),
      from: client_tables.folder(),
      entries: [entry],
      requirements: [],
    )
    as "the table did not load from the client's files"
  tables
}

fn client_present() -> Bool {
  environment.get("GENESIS_NO_CLIENT") != Ok("1")
}

pub fn creature2_rows_decode_to_the_values_the_file_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_present())
  let tables = load(creature2.entry())
  let assert Ok(first) = creature2.get(tables, 1)
    as "Creature2.tbl: lookup entry of id 1 (file offset 0x2afa204) is row 0"
  assert first.id == 1 as "Creature2.tbl 0x31f0: u32 ID of row 0"
  assert first.creation_type_enum == 0 as "Creature2.tbl 0x31f4: u32"
  assert first.description == "Generic Creature - Test Unit"
    as "Creature2.tbl 0x31f8: string offset 39232824, UTF-16 text at file offset 39245608"
  assert first.localized_text_id_name == 14_610 as "Creature2.tbl 0x3200: u32"
  assert first.donut_draw_distance == -1.0
    as "Creature2.tbl 0x348c: f32 -1.0, the fact file's game_table.column_type (55,977 rows hold -1.0)"
  let assert Ok(last) = creature2.get(tables, 80_249)
    as "Creature2.tbl: lookup entry of id 80249 (file offset 0x2b487e4) is row 0xdc30"
  assert last.id == 80_249 as "Creature2.tbl 0x256d470: u32 ID"
  assert last.description == "Mechari Female Security Officer"
    as "Creature2.tbl 0x256d478: string offset 45051848, UTF-16 text at file offset 45064632"
  assert last.localized_text_id_name == 781_476
    as "Creature2.tbl 0x256d480: u32"
  assert last.donut_draw_distance == -1.0 as "Creature2.tbl 0x256d70c: f32"
  let assert Ok(other) = creature2.get(tables, 17_404)
    as "Creature2.tbl: id 17404 has a row"
  assert other.donut_draw_distance == 0.0
    as "Creature2.tbl 0x596754: f32 0.0, the first row whose value is not -1.0"
  assert creature2.get(tables, 2) == Error(Nil)
    as "Creature2.tbl: lookup entry of id 2 (file offset 0x2afa208) is 0xffffffff"
  assert creature2.get(tables, 80_250) == Error(Nil)
    as "Creature2.tbl: the lookup count is 80250, so id 80250 is past it"
  assert list.length(creature2.all(tables)) == 56_369
    as "Creature2.tbl header 0x30: 56369 records (game_tables.ClientData)"
  store.unload(tables)
}

pub fn a_32_bit_integer_column_is_read_as_a_signed_number_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_present())
  let tables = load(creature2.entry())
  let assert Ok(first) = creature2.get(tables, 1)
    as "Creature2.tbl: id 1 has a row"
  assert first.quest_anim_objective_index == -1
    as "Creature2.tbl 0x333c holds the bytes ff ff ff ff; 189,158 type-3 values in the files are 0xffffffff, which a signed reading makes -1 (the sign of type 3 is a gap in game_table.column_type)"
  let assert Ok(last) = creature2.get(tables, 80_249)
    as "Creature2.tbl: id 80249 has a row"
  assert last.quest_anim_objective_index == 0 as "Creature2.tbl 0x256d5bc: u32"
  store.unload(tables)
}

pub fn spell4_rows_decode_to_the_values_the_file_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_present())
  let tables = load(spell4.entry())
  let assert Ok(first) = spell4.get(tables, 1)
    as "Spell4.tbl: lookup entry of id 1 (file offset 0x21c7e24) is row 0"
  assert first.id == 1 as "Spell4.tbl 0x1e40: u32 ID"
  assert first.description == "Spell Used by AI for Evasion - Tier 1"
    as "Spell4.tbl 0x1e48: string offset 28234584, UTF-16 text at file offset 28242328"
  assert first.spell4_base_id_base_spell == 1 as "Spell4.tbl 0x1e50: u32"
  assert first.tier_index == 1 as "Spell4.tbl 0x1e54: u32"
  assert first.cast_time == 0 as "Spell4.tbl 0x1e5c: u32"
  assert first.target_min_range == 0.0 as "Spell4.tbl 0x1e68: f32"
  let assert Ok(last) = spell4.get(tables, 88_879)
    as "Spell4.tbl: lookup entry of id 88879 (file offset 0x221eadc) is row 0x1041e"
  assert last.id == 88_879 as "Spell4.tbl 0x1aeeff0: u32 ID"
  assert last.description
    == "Lopp Grinder Mount - Summon Ground Mount [PMount] - Tier 1"
    as "Spell4.tbl 0x1aeeff8: string offset 34972242, UTF-16 text at file offset 34979986"
  assert last.spell4_base_id_base_spell == 63_701 as "Spell4.tbl 0x1aef000: u32"
  assert last.tier_index == 1 as "Spell4.tbl 0x1aef004: u32"
  assert last.cast_time == 1500 as "Spell4.tbl 0x1aef00c: u32"
  assert spell4.get(tables, 2) == Error(Nil)
    as "Spell4.tbl: lookup entry of id 2 (file offset 0x21c7e28) is 0xffffffff"
  assert spell4.get(tables, 88_880) == Error(Nil)
    as "Spell4.tbl: the lookup count is 88880, so id 88880 is past it"
  assert list.length(spell4.all(tables)) == 66_591
    as "Spell4.tbl header 0x30: 66591 records (game_tables.ClientData)"
  store.unload(tables)
}

pub fn item2_rows_decode_to_the_values_the_file_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_present())
  let tables = load(item2.entry())
  let assert Ok(first) = item2.get(tables, 1)
    as "Item2.tbl: lookup entry of id 1 (file offset 0xe9dfc4) is row 0"
  assert first.id == 1 as "Item2.tbl 0xcf0: u32 ID"
  assert first.item_budget_id == 0 as "Item2.tbl 0xcf4: u32"
  assert first.item_quality_id == 3 as "Item2.tbl 0xd00: u32"
  assert first.item2_type_id == 1 as "Item2.tbl 0xd14: u32"
  assert first.item_display_id == 3954 as "Item2.tbl 0xd18: u32"
  assert first.button_template == ""
    as "Item2.tbl 0xda8: string offset 14998048, a lone zero character at file offset 15001360 (an empty string)"
  assert first.button_icon == "Icon_ItemArmorChest_shirt_0003"
    as "Item2.tbl 0xdb0: string offset 14998050, UTF-16 text at file offset 15001362"
  let assert Ok(last) = item2.get(tables, 93_022)
    as "Item2.tbl: lookup entry of id 93022 (file offset 0xef8d38) is row 0x119a9"
  assert last.id == 93_022 as "Item2.tbl 0xe4e640: u32 ID"
  assert last.item_quality_id == 5 as "Item2.tbl 0xe4e650: u32"
  assert last.item2_type_id == 184 as "Item2.tbl 0xe4e664: u32"
  assert last.item_display_id == 3084 as "Item2.tbl 0xe4e668: u32"
  assert last.button_icon == "Icon_ItemArmorChest_shirt_0003"
    as "Item2.tbl 0xe4e700: string offset 14998050, the same text as row 1's at file offset 15001362"
  let assert Ok(other) = item2.get(tables, 175)
    as "Item2.tbl: id 175 has a row (the next id after 1)"
  assert other.button_icon == "Icon_ItemMisc_fur_0001"
    as "Item2.tbl 0xe80: string offset 14998112, UTF-16 text at file offset 15001424"
  assert item2.get(tables, 2) == Error(Nil)
    as "Item2.tbl: lookup entry of id 2 (file offset 0xe9dfc8) is 0xffffffff"
  assert item2.get(tables, 93_023) == Error(Nil)
    as "Item2.tbl: the lookup count is 93023, so id 93023 is past it"
  assert list.length(item2.all(tables)) == 72_106
    as "Item2.tbl header 0x30: 72106 records (game_tables.ClientData)"
  store.unload(tables)
}

pub fn spline2_node_rows_decode_to_the_values_the_file_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_present())
  let tables = load(spline2_node.entry())
  let assert Ok(first) = spline2_node.get(tables, 41_581)
    as "Spline2Node.tbl: lookup entry of id 41581 (file offset 0x147bfb4) is row 0"
  assert first.id == 41_581 as "Spline2Node.tbl 0x300: u32 ID"
  assert first.spline_id == 210 as "Spline2Node.tbl 0x304: u32"
  assert first.ordinal == 0 as "Spline2Node.tbl 0x308: u32"
  assert first.position0 == 4093.896728515625 as "Spline2Node.tbl 0x30c: f32"
  assert first.position1 == -1067.3800048828125 as "Spline2Node.tbl 0x310: f32"
  assert first.position2 == -4020.08740234375 as "Spline2Node.tbl 0x314: f32"
  assert first.event_id == 1 as "Spline2Node.tbl 0x328: u32"
  assert first.frame_time == 0.0 as "Spline2Node.tbl 0x32c: f32"
  let assert Ok(last) = spline2_node.get(tables, 755_607)
    as "Spline2Node.tbl: lookup entry of id 755607 (file offset 0x173545c) is row 0x5ce9f"
  assert last.id == 755_607 as "Spline2Node.tbl 0x14535c8: u32 ID"
  assert last.spline_id == 22_927 as "Spline2Node.tbl 0x14535cc: u32"
  assert last.ordinal == 37 as "Spline2Node.tbl 0x14535d0: u32"
  assert last.position0 == 455.3290100097656 as "Spline2Node.tbl 0x14535d4: f32"
  assert last.position1 == -467.2017822265625
    as "Spline2Node.tbl 0x14535d8: f32"
  assert last.position2 == -579.2930297851562
    as "Spline2Node.tbl 0x14535dc: f32"
  assert last.event_id == 0 as "Spline2Node.tbl 0x14535f0: u32"
  assert last.frame_time == 694.4940185546875
    as "Spline2Node.tbl 0x14535f4: f32"
  assert spline2_node.get(tables, 0) == Error(Nil)
    as "Spline2Node.tbl: lookup entry of id 0 (file offset 0x1453600) is 0xffffffff"
  assert spline2_node.get(tables, 41_613) == Error(Nil)
    as "Spline2Node.tbl: lookup entry of id 41613 (file offset 0x147c034) is 0xffffffff"
  assert spline2_node.get(tables, 755_608) == Error(Nil)
    as "Spline2Node.tbl: the lookup count is 755608, so id 755608 is past it"
  assert list.length(spline2_node.all(tables)) == 380_576
    as "Spline2Node.tbl header 0x30: 380576 records (game_tables.ClientData)"
  store.unload(tables)
}

pub fn localized_text_rows_decode_to_the_values_the_file_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_present())
  let tables = load(localized_text.entry())
  let assert Ok(first) = localized_text.get(tables, 1)
    as "LocalizedText.tbl: lookup entry of id 1 (file offset 0xe666d4) is row 0"
  assert first.id == 1 as "LocalizedText.tbl 0x230: u32 ID"
  assert first.sound_event_id == 0 as "LocalizedText.tbl 0x234: u32"
  assert first.sound_event_id_female == 0 as "LocalizedText.tbl 0x238: u32"
  assert first.version == 2 as "LocalizedText.tbl 0x23c: u32"
  assert first.unit_voice_type_id == 0 as "LocalizedText.tbl 0x240: u32"
  assert first.string_context_enum == 0 as "LocalizedText.tbl 0x244: u32"
  assert first.sound_availability_flag_female == 0
    as "LocalizedText.tbl 0x248: u32"
  let assert Ok(last) = localized_text.get(tables, 771_979)
    as "LocalizedText.tbl: lookup entry of id 771979 (file offset 0x11584fc) is row 0x83a72"
  assert last.id == 771_979 as "LocalizedText.tbl 0xe666a8: u32 ID"
  assert last.version == 408_956 as "LocalizedText.tbl 0xe666b4: u32"
  assert last.sound_event_id == 0 as "LocalizedText.tbl 0xe666ac: u32"
  assert localized_text.get(tables, 0) == Error(Nil)
    as "LocalizedText.tbl: lookup entry of id 0 (file offset 0xe666d0) is 0xffffffff"
  assert localized_text.get(tables, 16) == Error(Nil)
    as "LocalizedText.tbl: lookup entry of id 16 (file offset 0xe66710) is 0xffffffff"
  assert localized_text.get(tables, 771_980) == Error(Nil)
    as "LocalizedText.tbl: the lookup count is 771980, so id 771980 is past it"
  assert list.length(localized_text.all(tables)) == 539_251
    as "LocalizedText.tbl header 0x30: 539251 records (game_tables.ClientData)"
  store.unload(tables)
}
