//// A Proxy effect whose dataBits00 is 0 (`genesis_prime/game/spell_plan`). Expected values
//// come from these places:
//// - `Spell4Effects.effectType.26.periodic`: a Proxy row with dataBits00 0 names its spell in
////   dataBits01 and ticks (1,808 rows of the client's table, 1,536 with a tickTime), which
////   the plan does not start: the tree holds no child for it and the load goes on. The
////   planted row is of that shape, on Telekinetic Strike's spell.
//// - Telekinetic Strike's own Proxy 62204 to 30900 (`Spell4.32893`), which the plan reads.

import genesis_prime/game/spell_plan
import genesis_prime/table/id.{Spell4Id}
import gleam/list
import owned_test
import planted_table.{Integer}
import spell_tables

pub fn a_proxy_with_data_bits00_0_and_its_spell_in_data_bits01_builds_no_child_and_the_load_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let periodic =
    spell_tables.effect_row_with(
      id: 999_001,
      effect_type: 26,
      target_flags: 1,
      columns: [
        #("dataBits00", Integer(0)),
        #("dataBits01", Integer(30_900)),
        #("tickTime", Integer(1000)),
        #("durationTime", Integer(5000)),
      ],
    )
  let assert Ok(without) =
    spell_tables.planned_strike(rows: spell_tables.rows())
    as "the planted rows plan"
  let assert Ok(with) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(
      effect: periodic,
    ))
    as "a periodic Proxy does not fail the load"
  assert list.map(with.proxies, fn(proxy) { proxy.spell.spell4_id })
    == list.map(without.proxies, fn(proxy) { proxy.spell.spell4_id })
    as "the tree holds the Proxies the client's tables start and none for the periodic row"
  assert list.map(with.proxies, fn(proxy) { proxy.spell.spell4_id })
    == [Spell4Id(30_900)]
    as "Telekinetic Strike's one Proxy, 62204 to 30900, is read; the periodic row, which names 30900 in dataBits01, is not a second child"
  assert spell_plan.go_times_ms(spell: with) == [1250]
}
