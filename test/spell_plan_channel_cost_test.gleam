//// The Channeled spells that cost something, in the client's own tables
//// (`genesis_prime/game/spell_plan`, `cast_cost.pulse_costs`): which spells the per-pulse
//// rule reaches and how their costs plan. The tables are read where the client is present.
//// Expected values come from these places, each named at its row:
//// - `UI/ToolTips/ToolTips.lua` 2458-2491: the cost line of a spell wrapped in `$1n/tick`
////   is the one of a spell whose Spell4Base castMethod is Channeled (1), so a spell the rule
////   pays per pulse is a Spell4 row of such a base with a cost type and an amount in either
////   column.
//// - The counts are those of the issue's Design, read with
////   `gleam run -m genesis_prime/table_rows -- Spell4Base | Spell4` and counted on the
////   rows: 139 rows of 70 bases, 146 costs among them (7 rows hold two).
//// - `0x1403b3320`: a cost type of 3, 15 and 16 is a vital the server does not hold, 5 to 8
////   and 10 are the class resource's slots 0 to 3 and 5, 4 a class vital.

import client_tables
import genesis_prime/game/spell_plan.{type Cost}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4.{type Spell4}
import genesis_prime/table/spell4_base
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import owned_test
import spell_tables
import unitest

/// The Spell4 rows of a Channeled base with a cost type and an amount in either column.
fn costed_channel_rows(tables: store.Tables) -> List(Spell4) {
  let channeled =
    spell4_base.all(tables)
    |> list.filter(fn(base) { base.cast_method == 1 })
    |> list.map(fn(base) { base.id })
    |> set.from_list
  spell4.all(tables)
  |> list.filter(fn(row) {
    set.contains(channeled, row.spell4_base_id_base_spell)
    && { costs(row) != [] }
  })
}

/// The cost types of a row's two columns that hold a cost, a type and an amount, each with
/// its EMM id.
fn costs(row: Spell4) -> List(#(Int, Int)) {
  list.flatten([
    case row.innate_cost_type0 != 0 && row.innate_cost0 != 0 {
      True -> [#(row.innate_cost_type0, row.innate_cost_emm_id0)]
      False -> []
    },
    case row.innate_cost_type1 != 0 && row.innate_cost1 != 0 {
      True -> [#(row.innate_cost_type1, row.innate_cost_emm_id1)]
      False -> []
    },
  ])
}

pub fn every_costed_channeled_row_plans_its_costs_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = costed_channel_rows(tables)

  // 7.1: the issue's count, recounted from the tables.
  assert list.length(rows) == 139
    as "7.1: 139 rows of Channeled bases with a cost"
  assert list.length(
      list.unique(list.map(rows, fn(row) { row.spell4_base_id_base_spell })),
    )
    == 70
    as "7.1: of 70 bases"

  // 7.2: how many rows hold each cost type (a row of two types counts under both).
  let by_type =
    list.flat_map(rows, costs)
    |> list.map(fn(cost) { cost.0 })
    |> list.group(fn(cost_type) { cost_type })
    |> dict.map_values(fn(_, found) { list.length(found) })
    |> dict.to_list
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  assert by_type
    == [
      #(3, 2),
      #(4, 2),
      #(5, 35),
      #(6, 44),
      #(7, 1),
      #(8, 10),
      #(10, 1),
      #(15, 50),
      #(16, 1),
    ]
    as "7.2: the Design's table by cost type (146 costs in 139 rows); type 1, a health cost, is in none"

  // 7.3: each row that plans holds its costs as the kind its type is read as. A row whose
  // tree does not plan (a Proxy cycle, a vital or a cast condition the server does not read)
  // is a spell no class presses: 7.4 holds the four bases a player presses to the plan.
  let sources = spell_plan.sources_of(tables:)
  let #(planned, unplanned) =
    list.map(rows, fn(row) {
      spell_plan.spell_alone(tables:, sources:, spell4_id: row.id, chain: [])
      |> result.map(fn(spell) { #(row, spell) })
      |> result.map_error(fn(error) { #(row.id, error) })
    })
    |> result.partition
  assert list.sort(unplanned, fn(first, second) {
      int.compare(first.0, second.0)
    })
    == [
      #(
        31_404,
        spell_plan.UnreadRequirement(spell4_id: 31_404, requirement_type: 3),
      ),
      #(
        35_689,
        spell_plan.GainVitalNotRead(
          spell4_id: 35_689,
          effect_id: 72_297,
          vital: 9,
        ),
      ),
      #(
        38_863,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 38_863,
          effect_id: 84_122,
          gos: 6,
        ),
      ),
      #(39_054, spell_plan.NoRow(table: "Spell4", id: 0)),
      #(
        41_953,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 41_953,
          effect_id: 94_581,
          gos: 3,
        ),
      ),
      #(
        48_669,
        spell_plan.UnreadRequirement(spell4_id: 48_669, requirement_type: 3),
      ),
      #(
        52_155,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_155,
          effect_id: 123_163,
          gos: 3,
        ),
      ),
      #(
        52_156,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_156,
          effect_id: 123_169,
          gos: 3,
        ),
      ),
      #(
        52_157,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_157,
          effect_id: 123_175,
          gos: 3,
        ),
      ),
      #(
        52_158,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_158,
          effect_id: 123_181,
          gos: 3,
        ),
      ),
      #(
        52_159,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_159,
          effect_id: 123_187,
          gos: 3,
        ),
      ),
      #(
        52_160,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_160,
          effect_id: 123_193,
          gos: 3,
        ),
      ),
      #(
        52_161,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_161,
          effect_id: 123_199,
          gos: 3,
        ),
      ),
      #(
        52_162,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_162,
          effect_id: 123_205,
          gos: 3,
        ),
      ),
      #(
        52_163,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 52_163,
          effect_id: 123_211,
          gos: 3,
        ),
      ),
      #(
        55_653,
        spell_plan.ProxyCycle(chain: [55_653, 80_426, 70_410, 80_424, 70_410]),
      ),
      #(
        60_119,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 60_119,
          effect_id: 145_107,
          gos: 3,
        ),
      ),
      #(
        63_316,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 63_316,
          effect_id: 158_904,
          gos: 7,
        ),
      ),
      #(
        70_922,
        spell_plan.ProxyOnEachAllyAtSeveralGos(
          spell4_id: 70_922,
          effect_id: 181_484,
          gos: 3,
        ),
      ),
    ]
    as "7.3: the 19 rows that do not plan, each by its error: a vital requirement of type 3, a vital modifier of vital 9, the Spell4 row 0 a tree names, Proxies that start a child on each ally at several gos and a Proxy cycle; any other row that stops planning is a coverage loss"
  assert list.length(planned) == 120
    as "7.3: the other 120 rows plan, and each holds its costs as the next check reads them"
  list.each(planned, fn(entry) {
    assert list.map({ entry.1 }.costs, kind_of)
      == list.map(costs(entry.0), expected_kind)
      as {
        "7.3: Spell4 "
        <> int.to_string({ entry.0 }.id)
        <> " plans each cost type as `spell_plan.cost_of` reads it"
      }
  })

  // 7.4: the four bases a player can press, nine rows each: one cost of the same type and
  // amount in all nine, and the go count of its channel.
  list.each(
    [
      #(25_473, 41_276, 6, 8, 6, [
        spell_plan.SlotCost(slot: 1, amount: 8, result: 51),
      ]),
      #(20_628, 34_658, 6, 5, 6, [
        spell_plan.SlotCost(slot: 1, amount: 5, result: 51),
      ]),
      #(23_699, 39_366, 8, 10, 6, [
        spell_plan.SlotCost(slot: 3, amount: 10, result: 53),
      ]),
      #(38_210, 58_841, 15, 15, 3, [spell_plan.FocusCost(amount: 15)]),
    ],
    fn(base) {
      let #(base_id, first_row, cost_type, amount, gos, planned_cost) = base
      assert planned_costs(tables, first_row) == planned_cost
        as {
          "7.4: the ability of base "
          <> int.to_string(base_id)
          <> " plans the one cost, a slot cost of the class resource's slot (5 to 8 are slots 0 to 3) or Focus, which a Spell4 row plans as a FocusCost of its amount"
        }
      let own =
        list.filter(rows, fn(row) { row.spell4_base_id_base_spell == base_id })
      assert list.length(own) == 9
        as {
          "7.4: base " <> int.to_string(base_id) <> " holds nine costed rows"
        }
      assert list.unique(
          list.map(own, fn(row) {
            #(
              row.innate_cost_type0,
              row.innate_cost0,
              row.innate_cost_type1,
              row.innate_cost1,
            )
          }),
        )
        == [#(cost_type, amount, 0, 0)]
        as {
          "7.4: every row of base "
          <> int.to_string(base_id)
          <> " holds the one cost of the Design's table"
        }
      assert list.unique(
          list.map(own, fn(row) {
            list.length(
              spell_plan.channel_go_times_ms(spell_plan.Channel(
                initial_delay_ms: row.channel_initial_delay,
                max_time_ms: row.channel_max_time,
                pulse_time_ms: row.channel_pulse_time,
              )),
            )
          }),
        )
        == [gos]
        as {
          "7.4: every row of base "
          <> int.to_string(base_id)
          <> " has the Design's go count (0x14053d1f0)"
        }
    },
  )

  // 7.5: the rows whose cost an EMM id spends (spend all).
  assert list.length(
      list.filter(rows, fn(row) {
        row.innate_cost_emm_id0 != 0 || row.innate_cost_emm_id1 != 0
      }),
    )
    == 6
    as "7.5: six rows carry an EMM id, the old Bladestorm rows, none pressed by a player: a channel that spends every point pays once (cast_cost.pulse_costs)"
  list.each(
    list.filter(rows, fn(row) {
      row.innate_cost_emm_id0 != 0 || row.innate_cost_emm_id1 != 0
    }),
    fn(row) {
      assert row.innate_cost_emm_id0 == 7 || row.innate_cost_emm_id1 == 7
        as "7.5: the EMM id is 7 (spend all)"
    },
  )
}

/// The costs the plan of the Spell4 row holds, planned alone as a pressed ability.
fn planned_costs(tables: store.Tables, spell4_id: Int) -> List(Cost) {
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id:)
    as "a spell a player presses plans"
  spell.costs
}

/// The kind of cost a plan holds, as a name.
fn kind_of(cost: Cost) -> String {
  case cost {
    spell_plan.UnheldCost(result:) -> "unheld " <> int.to_string(result)
    spell_plan.FocusCost(..) -> "focus"
    spell_plan.UnreadSpendCost(..) -> "unread spend"
    spell_plan.SlotCost(..) -> "slot"
    spell_plan.SpendAllCost(..) -> "spend all"
    spell_plan.ClassVitalCost(..) -> "class vital"
    spell_plan.RowClassCost(..) -> "row class vital"
  }
}

/// The kind a cost type is read as (`0x1403b3320`), a slot cost with the EMM id 7 spending
/// every point held.
fn expected_kind(cost: #(Int, Int)) -> String {
  case cost.0, cost.1 {
    3, _ -> "unheld 176"
    15, _ -> "focus"
    16, _ -> "unheld 177"
    4, _ -> "class vital"
    5, 7 | 6, 7 | 7, 7 | 8, 7 | 10, 7 -> "spend all"
    5, _ | 6, _ | 7, _ | 8, _ | 10, _ -> "slot"
    other, _ -> "type " <> int.to_string(other)
  }
}
