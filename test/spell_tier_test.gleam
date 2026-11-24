//// The tiers of an ability (`genesis_prime/game/spell_tier`): what each costs, what level it
//// needs, which Spell4 row is the tier, and what makes the load refuse. Expected values come
//// from these places.
//// - `Spell4.abilityPointCost`, `Spell4.tierIndex` and `Spell4.spell4BaseIdBaseSpell`
////   (`table_rows -- Spell4 spell4BaseIdBaseSpell=27638`: tiers 1 to 9 are Spell4 43468, 49023,
////   49025 to 49031, costing 0, 1, 1, 1, 5, 1, 1, 1, 5; the same for Shred, base 23148).
//// - `Spell4TierRequirements.levelRequirement` (`table_rows -- Spell4TierRequirements`: tier 2
////   needs level 10, then 15, 20, 25, 30, 35, 40 and tier 9 needs 45).
//// - `0x1403bb2b0`: a change of tier costs the abilityPointCost of each tier it crosses, a
////   rise charging tiers a+1 to b and a fall giving back tiers b+1 to a; tier 1's own cost is
////   never charged.
//// - `0x1403ba550` and `0x1407a1440`: the client's book walks a base's tiers and stores a cost
////   for each, 0 for a tier with no Spell4 row, and a higher tier is taken only when its
////   spell exists. `table_rows -- Spell4 spell4BaseIdBaseSpell=26543` holds tiers 1 and 9 only.

import client_tables
import fixture_tables
import genesis_prime/game/spell_tier
import genesis_prime/table/class
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_tier_requirements
import genesis_prime/table/spell_level
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import unitest

const quick_draw = Spell4BaseId(27_638)

/// The base of a Medic's level 1 ability whose Spell4 rows hold tiers 1 and 9 only.
const base_with_a_missing_tier = Spell4BaseId(26_543)

/// The SpellLevel row of Quick Draw and the Spell4 row of its tier 1.
const quick_draw_spell_level = 1011

const quick_draw_tier_1 = 43_468

pub fn the_tiers_of_every_base_the_book_can_hold_have_the_clients_costs_levels_and_count_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let tiers = spell_tier.tiers(tables:)
  let rows = spell4.all(tables)
  let by_id = dict.from_list(list.map(rows, fn(row) { #(row.id, row) }))
  let by_base: Dict(Int, List(spell4.Spell4)) =
    list.group(rows, fn(row) { row.spell4_base_id_base_spell })
  let rows_of = fn(base: Int) {
    result.unwrap(dict.get(by_base, base), [])
    |> list.filter(fn(row) { row.tier_index >= 1 && row.tier_index <= 9 })
  }
  let base_of = fn(spell4_id: Int) {
    dict.get(by_id, spell4_id)
    |> result.map(fn(row) { row.spell4_base_id_base_spell })
  }
  // The bases the book can hold, by the test's own scan: each SpellLevel row's ability, each
  // class's first innate, and the alternate each tier row of those names.
  let leveled =
    list.filter_map(spell_level.all(tables), fn(row) { base_of(row.spell4_id) })
  let innates =
    list.filter_map(class.all(tables), fn(row) {
      case row.spell4_id_innate_ability_active00 {
        0 -> Error(Nil)
        active -> base_of(active)
      }
    })
  let named = list.append(leveled, innates)
  let alternates =
    list.flat_map(named, fn(base) {
      list.filter_map(rows_of(base), fn(row) {
        case row.spell4_id_mechanic_alternate_spell {
          0 -> Error(Nil)
          alternate -> base_of(alternate)
        }
      })
    })
  let held = set.from_list(list.append(named, alternates))
  assert set.size(held) > 0 as "the client's SpellLevel rows name abilities"
  let requirements =
    list.map(spell4_tier_requirements.all(tables), fn(row) {
      #(row.tier_index, row.level_requirement)
    })
    |> dict.from_list
  set.to_list(held)
  |> list.each(fn(base) {
    let tier_rows = rows_of(base)
    let name = "Spell4Base " <> int.to_string(base)
    let highest =
      list.fold(tier_rows, 0, fn(greatest, row) {
        int.max(greatest, row.tier_index)
      })
    assert spell_tier.highest(tiers:, base: Spell4BaseId(base)) == Ok(highest)
      as { name <> ": the highest tier is the greatest tierIndex of its rows" }
    assert highest == 9 || highest == 1
      as {
        name <> ": a class ability or alternate holds nine tiers, an innate one"
      }
    list.each(tier_rows, fn(row) {
      let tier = row.tier_index
      assert spell_tier.spell4_id(tiers:, base: Spell4BaseId(base), tier:)
        == Ok(Spell4Id(row.id))
        as {
          name <> ": tier " <> int.to_string(tier) <> " is the row's own id"
        }
      let crossed =
        list.filter(tier_rows, fn(other) {
          other.tier_index >= 2 && other.tier_index <= tier
        })
      assert spell_tier.change_cost(
          tiers:,
          base: Spell4BaseId(base),
          from: 1,
          to: tier,
        )
        == Ok(
          list.fold(crossed, 0, fn(sum, other) {
            sum + other.ability_point_cost
          }),
        )
        as {
          name
          <> ": a rise from tier 1 to "
          <> int.to_string(tier)
          <> " costs the tiers 2 to it, and never tier 1's own cost"
        }
      use <- bool.guard(when: tier == 1, return: Nil)
      assert spell_tier.level_needed(tiers:, tier:)
        == dict.get(requirements, tier)
        as {
          name
          <> ": tier "
          <> int.to_string(tier)
          <> " needs the level of its Spell4TierRequirements row"
        }
    })
  })
  assert spell_tier.level_needed(tiers:, tier: 1) == Error(Nil)
    as "tier 1 needs no level"
  // A base outside the set has no tier data: it is not a base with one tier.
  let outside =
    list.find(rows, fn(row) {
      !set.contains(held, row.spell4_base_id_base_spell)
    })
  let assert Ok(outside) = outside
    as "the client holds Spell4 rows of other bases"
  assert spell_tier.highest(
      tiers:,
      base: Spell4BaseId(outside.spell4_base_id_base_spell),
    )
    == Error(Nil)
    as "a base the book cannot hold has no tiers"
  assert spell_tier.highest(tiers:, base: Spell4BaseId(0)) == Error(Nil)
    as "base 0 has no tiers"
}

/// A change of tier on one base: the base, from, to, and what it costs.
type Change {
  Change(
    base: id.Spell4BaseId,
    from: Int,
    to: Int,
    cost: Result(Int, Nil),
    why: String,
  )
}

pub fn a_change_costs_the_tiers_it_crosses_and_a_fall_gives_them_back_and_a_tier_with_no_row_cannot_be_bought_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let tiers = spell_tier.tiers(tables:)
  list.each(
    [
      Change(quick_draw, 1, 2, Ok(1), "tier 2 costs 1"),
      Change(quick_draw, 1, 5, Ok(8), "tiers 2 to 5 cost 1 + 1 + 1 + 5"),
      Change(quick_draw, 4, 5, Ok(5), "tier 5 alone costs 5"),
      Change(quick_draw, 5, 9, Ok(8), "tiers 6 to 9 cost 1 + 1 + 1 + 5"),
      Change(quick_draw, 9, 1, Ok(-16), "a fall from 9 gives back tiers 2 to 9"),
      Change(quick_draw, 3, 3, Ok(0), "the same tier costs nothing"),
      Change(quick_draw, 1, 10, Error(Nil), "tier 10 is no tier of the book"),
      Change(quick_draw, 1, 0, Error(Nil), "tier 0 is no tier"),
      Change(
        base_with_a_missing_tier,
        1,
        9,
        Ok(5),
        "tiers 2 to 8 have no row and cost 0, tier 9 costs 5",
      ),
      Change(
        base_with_a_missing_tier,
        1,
        5,
        Error(Nil),
        "a tier with no row cannot be bought",
      ),
      Change(Spell4BaseId(0), 1, 2, Error(Nil), "a base with no tier data"),
    ],
    fn(case_) {
      let Change(base:, from:, to:, cost:, why:) = case_
      assert spell_tier.change_cost(tiers:, base:, from:, to:) == cost as why
    },
  )
  assert spell_tier.highest(tiers:, base: base_with_a_missing_tier) == Ok(9)
    as "a base with tiers 1 and 9 holds nine as its highest"
  assert spell_tier.spell4_id(tiers:, base: quick_draw, tier: 3)
    == Ok(Spell4Id(49_025))
    as "there is no Spell4 49024: tier 3 of Quick Draw is 49025"
  assert spell_tier.spell4_id(tiers:, base: base_with_a_missing_tier, tier: 5)
    == Error(Nil)
    as "a tier with no row has no Spell4"
  assert spell_tier.level_needed(tiers:, tier: 2) == Ok(10)
    as "Spell4TierRequirements: tier 2 needs level 10"
  assert spell_tier.level_needed(tiers:, tier: 9) == Ok(45)
    as "Spell4TierRequirements: tier 9 needs level 45"
  assert spell_tier.spent(tiers:, held: [
      #(quick_draw, 5),
      #(Spell4BaseId(20_718), 2),
    ])
    == 9
    as "the points held tiers cost are each tier's cost from tier 1"
  // The Esper and Stalker abilities cost 1 at tier 1, which the fixture lacks: Quick Draw's
  // tier 1 row says so, and a rise from tier 1 still costs the rows above it.
  use changed <- fixture_tables.changed(
    table: "Spell4",
    id: quick_draw_tier_1,
    with: [#("abilityPointCost", Integer(1))],
  )
  let tiers = spell_tier.tiers(tables: changed)
  assert spell_tier.change_cost(tiers:, base: quick_draw, from: 1, to: 2)
    == Ok(1)
    as "tier 1's own cost is never charged"
  assert spell_tier.change_cost(tiers:, base: quick_draw, from: 2, to: 1)
    == Ok(-1)
    as "and never given back"
}

/// A load with edited rows and the words its refusal must hold.
type Edit {
  Edit(
    rows: Result(fixture_tables.Rows, fixture_tables.Refusal),
    says: String,
    why: String,
  )
}

pub fn a_repeated_tier_a_missing_requirement_row_or_a_level_row_with_no_spell_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows = fixture_tables.rows()
  list.each(
    [
      Edit(
        fixture_tables.add(
          rows:,
          table: "Spell4",
          copy_of: 49_023,
          id: 9_000_001,
          with: [],
        ),
        "27638",
        "a second Spell4 row of Quick Draw's tier 2 names the base",
      ),
      Edit(
        fixture_tables.remove(rows:, table: "Spell4TierRequirements", id: 4),
        "tier 5",
        "Spell4 rows of tier 5 and no Spell4TierRequirements row of it name the tier",
      ),
      Edit(
        fixture_tables.change(
          rows:,
          table: "SpellLevel",
          id: quick_draw_spell_level,
          with: [#("spell4Id", Integer(9_999_999))],
        ),
        "9999999",
        "a SpellLevel row of a Spell4 row the table lacks names the row",
      ),
    ],
    fn(case_) {
      let Edit(rows:, says:, why:) = case_
      let assert Ok(rows) = rows as why
      let assert Error(error) = fixture_tables.load(rows:)
        as { why <> ": the load is refused" }
      assert string.contains(table_store.describe(error), says) as why
    },
  )
  let assert Ok(_) = fixture_tables.load(rows:) as "the committed rows load"
  Nil
}
