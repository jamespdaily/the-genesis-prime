//// The client's check of the AMPs a player picks (`genesis_prime/game/amp_spec`): the power a
//// level gives, which list the check accepts and with which result, and what the tables' load
//// refuses. Expected values come from these places.
//// - `GameFormula` 942 (`table_rows GameFormula 942`): dataint0 10, dataint01 7, datafloat0 1.0,
////   and `0x1403cdbf0`: no power below level 10, else `trunc((level - 10) * 1.0) + 7`.
//// - `EldanAugmentation` (`table_rows EldanAugmentation 770 771 772 782 788 798 863 220 221 222
////   259 705 706 707 682 20`): Stalker (class 5) 770 to 772 are tier 0 of category 3, cost 1 and
////   chained by `eldanAugmentationIdRequired`; 782 is tier 0 and cost 1; 788 and 863 are tier 1
////   and cost 4; 798 is tier 2 and cost 6. Spellslinger (class 7) 220 to 222 are tier 0 of category
////   1 and chained, 259 is its tier 1 and costs 4. Medic (class 4) 705 to 707 and 682 are the same
////   shape. 20 is class 0. Ids 12, 0 and 977 have no row.
//// - `EldanAugmentationCategory` (`table_rows EldanAugmentationCategory`): every category's tier 1
////   AMPs need 3 power spent in tier 0 (`tier2CostAmount00`) and its tier 2 AMPs 11 power spent in
////   tiers 0 and 1 (`tier3CostAmount00`).
//// - `0x1403d02a0`, `0x1403d5640`: the order of the client's checks.

import fixture_tables
import genesis_prime/game/amp_spec
import genesis_prime/table/id.{ClassId, EldanAugmentationId}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/result
import gleam/string
import owned_test
import planted_table.{Float, Integer}

const stalker = 5

const warrior = 1

const medic = 4

const spellslinger = 7

/// A level and the power the client gives it (GameFormula 942).
type Power {
  Power(level: Int, total: Int, why: String)
}

pub fn the_power_total_follows_the_clients_formula_at_every_level_test() -> Nil {
  use <- owned_test.run(10_000)
  let specs = amp_spec.specs(tables: fixture_tables.shared())
  list.each(
    [
      Power(1, 0, "below level 10 the client gives no power"),
      Power(9, 0, "level 9 is the last level with none"),
      Power(10, 7, "level 10 gives dataint01, 7"),
      Power(11, 8, "one level above gives one power more (datafloat0 1.0)"),
      Power(20, 17, "trunc(10 * 1.0) + 7"),
      Power(25, 22, "trunc(15 * 1.0) + 7"),
      Power(50, 47, "trunc(40 * 1.0) + 7"),
    ],
    fn(row) {
      let Power(level:, total:, why:) = row
      assert amp_spec.power_total(specs:, level:) == total as why
    },
  )
  // A row no client row holds: dataint0 12, dataint01 3, datafloat0 2.0 gives trunc((14 - 12) * 2.0) + 3.
  use tables <- fixture_tables.changed(table: "GameFormula", id: 942, with: [
    #("dataint0", Integer(12)),
    #("dataint01", Integer(3)),
    #("datafloat0", Float(2.0)),
  ])
  assert amp_spec.power_total(specs: amp_spec.specs(tables:), level: 14) == 7
    as "the power is read from GameFormula 942's row, not kept in the code"
}

/// A list the check judges: who picks, the AMPs held and the AMPs picked, and the result the
/// client gives (`Ok` for accepted, else its number).
type Pick {
  Pick(
    class_id: Int,
    level: Int,
    held: List(Int),
    picks: List(Int),
    result: Result(Nil, Int),
    why: String,
  )
}

pub fn a_pick_list_gets_the_clients_result_in_the_clients_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let specs = amp_spec.specs(tables: fixture_tables.shared())
  let assault_chain = [770, 771, 772]
  list.each(
    [
      Pick(
        stalker,
        10,
        [],
        [770, 771, 772, 863],
        Ok(Nil),
        "7 of 7 power; 3 power in tier 0 opens tier 1",
      ),
      Pick(
        stalker,
        10,
        [],
        [863],
        Error(33),
        "a tier 1 AMP with 0 spent in tier 0, under 3",
      ),
      Pick(
        stalker,
        10,
        [],
        [770, 771, 863],
        Error(33),
        "2 spent in tier 0, under 3",
      ),
      Pick(stalker, 10, [], [771], Error(34), "771 needs 770 in the list"),
      Pick(
        stalker,
        10,
        [],
        [770, 771, 772, 863, 782],
        Error(31),
        "8 of 7 power",
      ),
      Pick(
        stalker,
        9,
        [],
        [770],
        Error(31),
        "the total at level 9 is 0, below 1",
      ),
      Pick(stalker, 10, [], [20], Error(4), "20 is an AMP of class 0"),
      Pick(stalker, 10, [], [12], Error(35), "12 has no row"),
      Pick(stalker, 10, [], [0], Error(35), "0 has no row"),
      Pick(stalker, 10, [], [977], Error(35), "977 has no row"),
      Pick(
        stalker,
        10,
        [],
        [863, 12],
        Error(35),
        "the per-AMP check of 12 comes before the category rule's 33 of 863",
      ),
      Pick(
        stalker,
        20,
        [],
        [770, 771, 772, 863, 788, 798],
        Ok(Nil),
        "17 of 17 power: tier 0 is 3 and tier 0 plus tier 1 is 11, and an equal spend passes",
      ),
      Pick(
        stalker,
        20,
        [],
        [770, 771, 772, 863, 798],
        Error(33),
        "tier 0 plus tier 1 is 7, under 11",
      ),
      Pick(
        stalker,
        20,
        [],
        [770, 771, 772, 798],
        Error(33),
        "tier 0 is 3, under 11",
      ),
      Pick(
        stalker,
        10,
        [],
        [770, 770],
        Ok(Nil),
        "the check refuses no repeat: the server's save does",
      ),
      Pick(
        stalker,
        10,
        [],
        [],
        Ok(Nil),
        "no pick passes before the power is tested",
      ),
      Pick(
        stalker,
        9,
        [],
        [],
        Ok(Nil),
        "no pick passes at level 9, where the total is 0",
      ),
      Pick(
        stalker,
        10,
        assault_chain,
        [863],
        Ok(Nil),
        "the held AMPs count: 7 of 7 power",
      ),
      Pick(warrior, 10, [], [863], Error(4), "863 is a Stalker's AMP"),
      Pick(
        spellslinger,
        10,
        [],
        [220, 221, 222, 259],
        Ok(Nil),
        "a Spellslinger's own chain and tier 1",
      ),
      Pick(
        medic,
        10,
        [],
        [705, 706, 707, 682],
        Ok(Nil),
        "a Medic's own chain and tier 1",
      ),
    ],
    fn(row) {
      let Pick(class_id:, level:, held:, picks:, result:, why:) = row
      let judged =
        amp_spec.check(
          specs:,
          class_id: ClassId(class_id),
          level:,
          held: list.map(held, EldanAugmentationId),
          picks: list.map(picks, EldanAugmentationId),
        )
      assert case judged {
          Ok(Nil) -> Ok(Nil)
          Error(refusal) -> Error(amp_spec.result_of(refusal:))
        }
        == result
        as why
    },
  )
}

/// A change to the tables that the load refuses, and the sentence it names the row by.
type Refused {
  Refused(
    edits: List(#(String, Int, List(#(String, planted_table.Cell)))),
    names: String,
    why: String,
  )
}

pub fn the_load_refuses_a_category_or_an_amp_row_the_pick_check_does_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      Refused(
        [
          #("EldanAugmentationCategory", 3, [
            #("eldanAugmentationCategoryIdTier2Category00", Integer(5)),
          ]),
        ],
        "EldanAugmentationCategory 3",
        "the client keys the tier 0 spend by tier2Category00: every row holds its own id",
      ),
      Refused(
        [
          #("EldanAugmentationCategory", 3, [
            #("eldanAugmentationCategoryIdTier2Category01", Integer(5)),
          ]),
        ],
        "EldanAugmentationCategory 3",
        "a category shared by two takes branches the rule does not read",
      ),
      Refused(
        [
          #("EldanAugmentationCategory", 3, [
            #("tier3CostAmount01", Integer(2)),
          ]),
        ],
        "EldanAugmentationCategory 3",
        "the second amounts are read only in the shared branches",
      ),
      Refused(
        [
          #("EldanAugmentation", 770, [
            #("eldanAugmentationCategoryId", Integer(9)),
          ]),
        ],
        "EldanAugmentation 770",
        "a Stalker's AMP naming a category with no row: the client's result 36 can never arise",
      ),
      Refused(
        [#("EldanAugmentation", 770, [#("categoryTier", Integer(3))])],
        "EldanAugmentation 770",
        "a Stalker's AMP of tier 3: the client's result 37 can never arise",
      ),
      Refused(
        [#("EldanAugmentation", 770, [#("item2IdUnlock", Integer(30_462))])],
        "EldanAugmentation 770",
        "a Stalker's AMP with an item unlock: the client's result 32 can never arise",
      ),
    ],
    fn(row) {
      let Refused(edits:, names:, why:) = row
      let assert Ok(rows) =
        fixture_tables.change_all(rows: fixture_tables.rows(), edits:)
        as why
      let assert Error(error) = fixture_tables.load(rows:) as why
      assert string.contains(table_store.describe(error), names)
        as { why <> ": the load names the row" }
    },
  )
  assert result.is_ok(fixture_tables.load(rows: fixture_tables.rows()))
    as "the client's own rows load"
  let assert Ok(without_942) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "GameFormula",
      id: 942,
    )
  let assert Error(error) = fixture_tables.load(rows: without_942)
    as "a load with no GameFormula row 942 fails"
  assert string.contains(table_store.describe(error), "GameFormula 942")
    as "the load names the missing row"
}
