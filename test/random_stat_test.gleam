//// The roll of an item with random stats (`genesis_prime/game/random_stat`). Expected
//// values come from these places.
//// - The client's rows, which the fixture holds as roots: Item2 48169's ItemStat 432 has
////   three kind-2 entries, all on ItemRandomStatGroup 11, whose rows in table order are
////   properties 34, 47, 32, 29 and 57; Item2 48170 is a shield whose ItemStat 439 has four
////   kind-2 entries on group 14, whose rows are the shield properties 41, 175, 176 and 178;
////   Item2 37685 is a weapon whose ItemStat 439 names that shield group; Item2 37683's
////   ItemStat 443 has four kind-4 entries. Every row's weight is 1.
//// - The word's layout and how the client accepts it (0x14040e6d0, 0x14040bdf0): version 1
////   in bits 56 to 63 and entry i's 1-based row in its group in bits 8i to 8i+7. Each
////   word's bytes here are worked out by hand from the rows' order and the pick rule
////   (the first candidate whose running weight is above fraction x total weight), not
////   taken from the code.
//// - A fraction is a 32-bit number over 2^32 (0x80000000 is 0.5, 0xFD70A3D7 is 0.99).

import client_tables
import fixture_tables
import genesis_prime/game/item_property
import genesis_prime/game/item_stat_kind
import genesis_prime/game/random_stat
import genesis_prime/game/random_stat_word
import genesis_prime/table/item2
import gleam/int
import gleam/list
import gleam/result
import owned_test
import planted_table.{Integer}
import unitest

const shield = 48_170

const bracer = 48_169

const weapon_with_shield_group = 37_685

const kind_4_item = 37_683

/// A number sequence that is the same on every run: a linear congruential generator
/// (Knuth's multiplier), so a seeded draw needs no clock and no entropy source.
fn seeded(seed seed: Int, bytes bytes: Int) -> #(Int, BitArray) {
  let next = fn(state) {
    int.bitwise_and(
      state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407,
      0xffffffffffffffff,
    )
  }
  list.fold(list.repeat(Nil, bytes / 4), #(seed, <<>>), fn(acc, _) {
    let state = next(acc.0)
    #(state, <<acc.1:bits, { int.bitwise_shift_right(state, 32) }:size(32)>>)
  })
}

fn chosen(word word: Int, entries entries: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, entries), fn(_, entry) {
    random_stat_word.choice(word:, entry:)
  })
}

pub fn an_item_needs_4_bytes_per_random_stat_entry_and_none_without_one_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  assert random_stat.roll_bytes(
      tables:,
      item2_id: fixture_tables.root("Item2", bracer),
    )
    == 12
    as "ItemStat 432 has three kind-2 entries, a fraction of 4 bytes each"
  assert random_stat.roll_bytes(
      tables:,
      item2_id: fixture_tables.root("Item2", shield),
    )
    == 16
    as "ItemStat 439 has four kind-2 entries"
  assert random_stat.roll_bytes(
      tables:,
      item2_id: fixture_tables.root("Item2", 1375),
    )
    == 0
    as "ItemStat 4 has one kind-1 entry and no kind-2 entry"
}

pub fn each_entrys_bytes_pick_its_groups_row_by_weight_in_table_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item2_id = fixture_tables.root("Item2", bracer)
  // Group 11 has five rows of weight 1. Entry 0 at 0.0 takes the first, row 1. Entry 1 at
  // 0.5 picks from rows 2 to 5 (row 1 is taken): its target is 0.5 x 4 = 2, and the running
  // weights 1, 2, 3 put the third, row 4, first above it. Entry 2 at 0.99 picks from rows
  // 2, 3 and 5: its target is 2.97, and the third, row 5, is the first whose running weight
  // 3 is above it.
  assert random_stat.roll(tables:, item2_id:, entropy: <<
      0x00000000:size(32),
      0x80000000:size(32),
      0xFD70A3D7:size(32),
    >>)
    == 0x0100000000050401
    as "entry 0 takes row 1, entry 1 row 4 and entry 2 row 5: version 1 and the choices 1, 4, 5"
}

pub fn a_group_named_twice_in_one_item_never_gives_the_same_row_twice_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  // Three entries that would each take row 1 of group 11: the first takes it, the second
  // the first of the rows left (row 2), the third the first of those left (row 3).
  assert random_stat.roll(
      tables:,
      item2_id: fixture_tables.root("Item2", bracer),
      entropy: <<0:size(96)>>,
    )
    == 0x0100000000030201
    as "no row twice: 1, 2, 3"
  // A shield's four entries are all of group 14, which has four rows: whatever the
  // fractions, the four rows are taken once each.
  let shield_id = fixture_tables.root("Item2", shield)
  list.each(
    [
      <<0:size(128)>>,
      <<
        0xFFFFFFFF:size(32),
        0xFFFFFFFF:size(32),
        0xFFFFFFFF:size(32),
        0xFFFFFFFF:size(32),
      >>,
      <<
        0x80000000:size(32),
        0x00000000:size(32),
        0xC0000000:size(32),
        0x40000000:size(32),
      >>,
    ],
    fn(entropy) {
      let word = random_stat.roll(tables:, item2_id: shield_id, entropy:)
      assert list.sort(chosen(word:, entries: 4), int.compare) == [1, 2, 3, 4]
        as "four entries on a group of four rows take each row once"
    },
  )
}

pub fn a_rolled_word_is_one_the_client_accepts_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let rolled = fn(item2_id, seed) {
    let item2_id = fixture_tables.root("Item2", item2_id)
    let #(_, entropy) =
      seeded(seed:, bytes: random_stat.roll_bytes(tables:, item2_id:))
    let word = random_stat.roll(tables:, item2_id:, entropy:)
    assert random_stat_word.has_data(word:)
      as "a rolled word holds data, so the client reads it"
    assert result.is_ok(item_property.of_item(
      tables:,
      level: 1,
      item2_id:,
      random_stats: word,
    ))
      as "0x14040e6d0: every choice is within its group and names a property the builder takes, so the build does not fail"
  }
  list.each(
    list.index_map(list.repeat(Nil, 1000), fn(_, seed) { seed }),
    fn(seed) {
      rolled(bracer, seed)
      rolled(shield, seed)
    },
  )
}

/// Item2 37685 is a weapon whose ItemStat 439 names the shield group, whose properties the
/// client's builder refuses on an item that is no shield (0x14040db30, 0x95), so no row is
/// a candidate and the item gets no roll.
pub fn an_item_whose_group_holds_no_property_it_accepts_gets_no_roll_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let item2_id = fixture_tables.root("Item2", weapon_with_shield_group)
  assert random_stat.roll_bytes(tables:, item2_id:) == 0
    as "no bytes are drawn for an item that gets no roll"
  assert random_stat.roll(tables:, item2_id:, entropy: <<>>) == 0
    as "the word is 0, which the client reads as no data"
  assert random_stat.roll(tables:, item2_id:, entropy: <<0:size(128)>>) == 0
    as "bytes given to it change nothing"
}

/// No row of the client's ItemStat mixes kinds (it holds only whole entries of kind 1, only
/// of kind 2 or only of kind 4), so ItemStat 432 is changed. With entry 0 a kind-1 entry on
/// property 35, only the other two draw bytes and take rows 1 and 2 of group 11; the entry
/// holds choice 0 (0x14040e6d0 reads a kind-2 entry's byte only for a kind-2 entry). With
/// entry 3 also a kind-4 entry the item gets no roll: the client's builder fails a word with
/// data whose kind-4 choice is 0 (0x50), and nothing here fills a kind-4 entry.
pub fn kind_4_and_kind_1_entries_get_byte_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", bracer)
  use with_kind_1 <- fixture_tables.changed(table: "ItemStat", id: 432, with: [
    #("itemStatTypeEnum00", Integer(1)),
    #("itemStatData00", Integer(35)),
  ])
  assert random_stat.roll_bytes(tables: with_kind_1, item2_id:) == 8
    as "two kind-2 entries"
  assert random_stat.roll(tables: with_kind_1, item2_id:, entropy: <<
      0:size(64),
    >>)
    == 0x0100000000020100
    as "entry 0 (kind 1) holds 0, entry 1 takes row 1 and entry 2 row 2"
  use with_kind_4 <- fixture_tables.changed(table: "ItemStat", id: 432, with: [
    #("itemStatTypeEnum00", Integer(1)),
    #("itemStatData00", Integer(35)),
    #("itemStatTypeEnum03", Integer(4)),
    #("itemStatData03", Integer(63)),
  ])
  assert random_stat.roll_bytes(tables: with_kind_4, item2_id:) == 0
    as "an item with a kind-4 entry draws no bytes"
  assert random_stat.roll(tables: with_kind_4, item2_id:, entropy: <<>>) == 0
    as "its word is 0, which the client reads as no data"
  // The client's own kind-4 item: no kind-2 entry, so no bytes and no word.
  let tables = fixture_tables.shared()
  let crafted = fixture_tables.root("Item2", kind_4_item)
  assert random_stat.roll_bytes(tables:, item2_id: crafted) == 0
  assert random_stat.roll(tables:, item2_id: crafted, entropy: <<>>) == 0
}

/// A proxy item (Item2.flags 0x4000) takes its stats from another row, so the client reads
/// no word of its own (`0x1404445d0.proxy`). No client proxy holds a group row its builder
/// would take, so the bracer's row is changed to hold the flag: it draws no bytes and rolls
/// no word, where the bracer as the client has it draws 12.
pub fn a_proxy_item_gets_no_roll_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", bracer)
  assert random_stat.roll_bytes(tables: fixture_tables.shared(), item2_id:)
    == 12
    as "the bracer, with three kind-2 entries, draws 12 bytes"
  use proxy <- fixture_tables.changed(table: "Item2", id: bracer, with: [
    #("flags", Integer(0x4000)),
  ])
  assert random_stat.roll_bytes(tables: proxy, item2_id:) == 0
    as "a proxy item draws no bytes"
  assert random_stat.roll(tables: proxy, item2_id:, entropy: <<>>) == 0
    as "its word is 0, which the client reads as no data"
}

/// Every Item2 row of the client with a kind-2 entry: it rolls to a word, and the word is
/// one the client accepts. The rows that get none are 37685, the weapon whose ItemStat names
/// the shield group, and eight proxy items (flags 0x4000, whose stats the client takes from
/// the Item2 row GameFormula 1214 names, which has no ItemStat: `0x1404445d0.proxy`).
pub fn every_client_random_stat_row_rolls_to_a_word_the_client_accepts_or_none_with_its_reason_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows =
    list.filter(item2.all(tables), fn(item) {
      item_property.stat_entries_of(tables:, item2_id: item.id)
      |> result.map(fn(entries) {
        list.any(entries, fn(entry) {
          result.is_ok(item_stat_kind.random_group_of(entry))
        })
      })
      |> result.unwrap(or: False)
    })
  assert list.length(rows) == 25_828
    as "the client's Item2 holds 25,828 rows with a kind-2 entry"
  let outcomes =
    list.map(rows, fn(item) {
      let #(_, entropy) =
        seeded(
          seed: item.id,
          bytes: random_stat.roll_bytes(tables:, item2_id: item.id),
        )
      let word = random_stat.roll(tables:, item2_id: item.id, entropy:)
      #(
        item.id,
        word,
        item_property.of_item(
          tables:,
          level: 1,
          item2_id: item.id,
          random_stats: word,
        ),
        item_property.of_item(
          tables:,
          level: 1,
          item2_id: item.id,
          random_stats: 0,
        ),
      )
    })
  let unrolled =
    list.filter_map(outcomes, fn(outcome) {
      case outcome.1 {
        0 -> Ok(outcome.0)
        _ -> Error(Nil)
      }
    })
  let proxies =
    list.filter_map(rows, fn(item) {
      case item_property.is_proxy(item) {
        True -> Ok(item.id)
        False -> Error(Nil)
      }
    })
  assert list.length(proxies) == 8 as "eight proxy items hold a kind-2 entry"
  assert list.sort(unrolled, int.compare)
    == list.sort([weapon_with_shield_group, ..proxies], int.compare)
    as "the rows that get no roll are the eight proxy items (the client builds their stats from another row, so no word of theirs is read) and 37685"
  assert list.filter(unrolled, fn(id) { !list.contains(proxies, id) })
    == [weapon_with_shield_group]
    as "the one non-proxy row that gets no roll is 37685, a weapon whose group holds only shield properties, which the builder refuses on a non-shield (0x95)"
  assert list.filter(outcomes, fn(outcome) {
      let #(_, _, rolled, bare) = outcome
      case rolled, bare {
        Ok(_), Ok(_) -> False
        Error(item_property.Unread(gap: rolled_gap, ..)),
          Error(item_property.Unread(gap: bare_gap, ..))
        -> rolled_gap != bare_gap
        _, _ -> True
      }
    })
    == []
    as "a rolled word never turns an item the reader gives into one it refuses, and an unread item stays unread for its own reason"
}

/// A row the roll takes as a candidate is a kind 1 row whose property the builder takes;
/// a row of another kind is no candidate, since the client's builder fails a word naming
/// it with 0x70 (`0x14040e6d0`, `0x14040d5d0`). Item2 48169's group 11 has rows 34 to 38
/// of properties 34, 47, 32, 29 and 57. With row 34 changed to kind 2, entry 0 at
/// fraction 0 takes the first row left, position 2, where the table as the client has it
/// gives position 1; with every row of the group changed the item gets no roll.
pub fn a_random_row_of_another_kind_than_1_is_no_candidate_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", bracer)
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "ItemRandomStat",
      id: 34,
      with: [#("itemStatTypeEnum", Integer(2))],
    )
    as "ItemRandomStat 34 is in the fixture"
  use without_first <- fixture_tables.on_rows(rows:, reaching: [])
  assert random_stat.roll(tables: without_first, item2_id:, entropy: <<
      0:size(96),
    >>)
    == 0x0100000000040302
    as "the rows left are positions 2 to 5: the entries at fraction 0 take 2, 3 and 4"
  assert random_stat.roll_bytes(tables: without_first, item2_id:) == 12
    as "the item still rolls three entries"
  let assert Ok(all_rows) =
    list.try_fold([34, 35, 36, 37, 38], fixture_tables.rows(), fn(rows, id) {
      fixture_tables.change(rows:, table: "ItemRandomStat", id:, with: [
        #("itemStatTypeEnum", Integer(3)),
      ])
    })
    as "rows 34 to 38 are in the fixture"
  use none <- fixture_tables.on_rows(rows: all_rows, reaching: [])
  assert random_stat.roll_bytes(tables: none, item2_id:) == 0
    as "no row of group 11 is a candidate: no bytes are drawn"
  assert random_stat.roll(tables: none, item2_id:, entropy: <<>>) == 0
    as "the word is 0, which the client reads as no data"
}

/// Each kind-2 entry takes one fraction, in entry order, and an entry of another kind
/// takes none (`0x14040e6d0`: byte i serves entry i alone). ItemStat 432 with entry 0
/// changed to kind 1: entries 1 and 2 take the first two fractions.
pub fn each_kind_2_entry_takes_one_fraction_in_entry_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let item2_id = fixture_tables.root("Item2", bracer)
  use tables <- fixture_tables.changed(table: "ItemStat", id: 432, with: [
    #("itemStatTypeEnum00", Integer(1)),
    #("itemStatData00", Integer(35)),
  ])
  // Entry 1 at 0.5 picks from the five rows of group 11: its target is 2.5, and the
  // running weights 1, 2, 3 put the third, row 3, first above it. Entry 2 at 0.0 picks
  // the first row left, row 1.
  assert random_stat.roll(tables:, item2_id:, entropy: <<
      0x80000000:size(32),
      0x00000000:size(32),
    >>)
    == 0x0100000000010300
    as "entry 0 (kind 1) holds 0; entry 1 takes the first fraction and entry 2 the second"
}
