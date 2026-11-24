//// The plans a press reads when the player holds tiers above 1 (`genesis_prime/game/held_tier`).
//// Expected values come from these places.
//// - `table_rows -- Spell4 spell4BaseIdBaseSpell=26543`: Paralytic Surge's tiers 1 to 9 are Spell4
////   42352, 51979 to 51984, 51988 and 51989; `-- Spell4Effects spellId=51979` and `spellId=42352`:
////   tier 2's root holds a damage row 122793 (read by the area) and a stun row 122794, tier 1's
////   96125 and 96126.
//// - `-- Spell4 spell4BaseIdBaseSpell=26468`: Pulse Blast's tier 9 is Spell4 56144.
//// - `-- Spell4 spell4BaseIdBaseSpell=27638`: Quick Draw's tier 3 is Spell4 49025, whose
////   `spell4IdMechanicAlternateSpell` is 76006, the tier 3 row of its alternate's base 52215
////   (tier 1 is 43468 with 76002).
//// - `-- Spell4 spell4BaseIdBaseSpell=20685`: Charged Shot's alternate, held in the book only as
////   an alternate, has tier 1 row 34719 and tier rows 48949 to 48956 that no plan holds.

import client_tables
import fixture_tables
import genesis_prime/game/held_tier
import genesis_prime/game/spell_plan
import genesis_prime/game/spell_tier
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import owned_test
import spell_tables
import unitest

const paralytic_surge = 26_543

const pulse_blast = 26_468

const quick_draw = 27_638

const charged_shot_alternate = 20_685

/// A held tier of a base, the Spell4 rows taken out of the tier plans, and the Spell4 id of
/// the plan under the base afterwards.
type Row {
  Row(why: String, base: Int, held_tier: Int, dropped: List(Int), plays: Int)
}

fn rows() -> List(Row) {
  [
    Row(
      "Paralytic Surge held at 2 plays its tier 2 row",
      paralytic_surge,
      2,
      [],
      51_979,
    ),
    Row(
      "Pulse Blast held at 9 plays its tier 9 row",
      pulse_blast,
      9,
      [],
      56_144,
    ),
    Row(
      "tiers 5 to 9 the plans cannot cast: a held 7 plays tier 4",
      paralytic_surge,
      7,
      [51_982, 51_983, 51_984, 51_988, 51_989],
      51_981,
    ),
    Row(
      "no tier above 1 the plans can cast: a held 9 plays tier 1",
      paralytic_surge,
      9,
      [51_979, 51_980, 51_981, 51_982, 51_983, 51_984, 51_988, 51_989],
      42_352,
    ),
    Row("Quick Draw held at 3 plays its tier 3 row", quick_draw, 3, [], 49_025),
    Row(
      "a stored tier of an alternate plays tier 1: the plans hold no tier of it",
      charged_shot_alternate,
      3,
      [],
      34_719,
    ),
  ]
}

pub fn a_held_tier_plays_its_own_plan_or_the_best_lower_tier_the_plans_cast_and_tier_1_at_worst_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let plans = spell_plan.plans_with_later(tables:)
  let tier_plans = spell_plan.tier_plans(tables)
  let tiers = spell_tier.tiers(tables)
  assert held_tier.plans_of(plans:, tier_plans:, tiers:, held: []) == plans
    as "a player who holds no tier above 1 casts the plans as they are"
  let played = fn(row: Row, tier_plans) {
    held_tier.plans_of(plans:, tier_plans:, tiers:, held: [
      #(Spell4BaseId(row.base), row.held_tier),
    ])
  }
  list.each(rows(), fn(row) {
    let kept = dict.drop(tier_plans, list.map(row.dropped, Spell4Id))
    let after = played(row, kept)
    let assert Ok(spell) = dict.get(after, row.base) as row.why
    assert spell.spell4_id.value == row.plays as row.why
    assert dict.delete(after, row.base) == dict.delete(plans, row.base)
      as { row.why <> ": no other ability's plan changes" }
  })
  let unplanned = Row("no plan", 999_999, 3, [], 0)
  assert played(unplanned, tier_plans) == plans
    as "a base the plans do not hold is left alone"
  let assert Ok(surge) =
    dict.get(
      played(Row("", paralytic_surge, 2, [], 0), tier_plans),
      paralytic_surge,
    )
  assert spell_tables.listed_effect_ids(spell: surge) == [122_794]
    as "tier 2's root lists its own stun row 122794 (the damage row 122793 is read by the area), not tier 1's 96126"
  let assert Ok(plain_surge) = dict.get(plans, paralytic_surge)
  assert spell_tables.listed_effect_ids(spell: plain_surge) == [96_126]
    as "the plans' own Paralytic Surge lists tier 1's stun row"
  let assert Ok(drawn) =
    dict.get(played(Row("", quick_draw, 3, [], 0), tier_plans), quick_draw)
  assert option.map(drawn.alternate, fn(alternate) { alternate.spell4_id.value })
    == Some(76_006)
    as "the tier 3 plan holds the alternate's tier 3 row, which a surged press casts"
  let assert Ok(plain) = dict.get(plans, quick_draw)
  assert option.map(plain.alternate, fn(alternate) { alternate.spell4_id.value })
    == Some(76_002)
    as "the plans' own Quick Draw holds the alternate's tier 1 row"
}

pub fn a_held_tier_plan_keeps_the_abilitys_base_and_its_tiers_own_spell4_id_for_every_tier_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let plans = spell_plan.plans_with_later(tables:)
  let tier_plans = spell_plan.tier_plans(tables)
  let tiers = spell_tier.tiers(tables)
  list.each(dict.keys(plans), fn(base) {
    let base = Spell4BaseId(base)
    let highest = result.unwrap(spell_tier.highest(tiers:, base:), 1)
    list.each(tiers_above_1(highest:), fn(held) {
      let name =
        "Spell4Base "
        <> int.to_string(base.value)
        <> " held at "
        <> int.to_string(held)
      let after =
        held_tier.plans_of(plans:, tier_plans:, tiers:, held: [#(base, held)])
      let assert Ok(spell) = dict.get(after, base.value) as name
      let played =
        held_tier.tier_played(tier_plans:, tiers:, base:, held_tier: held)
      assert played >= 1 && played <= held
        as { name <> " plays a tier from 1 to the held one" }
      assert list.all(tiers_between(low: played + 1, high: held), fn(tier) {
        case spell_tier.spell4_id(tiers:, base:, tier:) {
          Ok(spell4_id) ->
            spell_plan.in_tier_plans(tier_plans:, spell4_id:) == Error(Nil)
          Error(Nil) -> True
        }
      })
        as {
          name
          <> " plays the highest tier at or below the held one that the plans cast"
        }
      assert spell.spell4_base_id == base as { name <> " keeps the base" }
      assert Ok(spell.spell4_id)
        == spell_tier.spell4_id(tiers:, base:, tier: played)
        as { name <> " plays the Spell4 row of the tier it plays" }
    })
  })
}

/// The tiers 2 to `highest`, lowest first.
fn tiers_above_1(highest highest: Int) -> List(Int) {
  tiers_between(low: 2, high: highest)
}

/// The tiers from `low` to `high`, lowest first; none when `low` is above `high`.
fn tiers_between(low low: Int, high high: Int) -> List(Int) {
  int.range(from: high, to: low - 1, with: [], run: list.prepend)
}
