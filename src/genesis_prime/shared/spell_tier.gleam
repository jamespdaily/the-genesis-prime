//// The tiers of an ability: the nine Spell4 rows of one Spell4Base that the ability builder's
//// pips choose between, what each costs in ability points, and the level each needs. The
//// client's own word is `GetSpellIdForTier`; the builder's save (genesis_prime/game/
//// limited_action_set) judges a tier change against this module.
////
//// ```
//// load: SpellLevel + Class innates + the alternates their tier rows name ─▶ the bases the book can hold
////       Spell4 rows by base and tierIndex (1 to 9) + Spell4TierRequirements ─▶ SpellTiers
//// change_cost(base, from, to) ─▶ points a raise costs or a fall gives back
//// level_needed(tier)          ─▶ the level the tier opens at
//// spell4_id(base, tier)       ─▶ the Spell4 row that is the tier
//// alternate_of(base)          ─▶ the base the tier rows name as the ability's alternate
//// ```
////
//// - **A base's tiers** are its Spell4 rows by `spell4BaseIdBaseSpell` and `tierIndex`, tiers 1
////   to 9: the client's writer sends tiers below 10 only (`opcode.0xb1`).
//// - **The bases** are every base the book can hold: the ability of each SpellLevel row (the
////   client's own source, `IsAbilityAvailable` `0x1403bb040`), each class's first innate, and
////   the alternate each tier row of those names (`Spell4.spell4IdMechanicAlternateSpell`). A base
////   outside them has no tier data: `highest` says `Error`, never one tier.
//// - **A tier with no row** cannot be bought and costs 0 when crossed: the client's book walks
////   tiers 1 to the highest and stores each cost from `0x1407a1440`, which gives 0 for a tier
////   with no spell, and `UpdateSpellTier` takes a higher tier only when its spell exists
////   (`0x1403ba550`, `0x140748390`).
//// - **The cost** of a change is the sum of `Spell4.abilityPointCost` over the tiers it crosses:
////   a rise from a to b charges tiers a+1 to b, a fall gives back tiers b+1 to a, and tier 1's own
////   cost is never charged (`0x1403bb2b0`).
//// - **The level** a tier needs is `Spell4TierRequirements.levelRequirement` of its `tierIndex`;
////   tier 1 needs none.
//// - **An alternate** is the Spell4Base that `Spell4.spell4IdMechanicAlternateSpell` of an
////   ability's tier rows names, the tier n row naming the alternate's tier n row; every base of the
////   book that names one names one base (`alternate_of`). The reverse is one-to-one only by the
////   data: five alternates are named by several bases, of which only one is in any class's book
////   (a table test holds it), and a base the book gains that names an already-named alternate has
////   no rule here, since the client keeps one book entry for each base and two held tiers cannot
////   both show in it.
//// - **The load fails** when two Spell4 rows of a base hold one tierIndex from 1 to 9, a tier from
////   2 to 9 that has a row has no Spell4TierRequirements row, two requirement rows name one tier,
////   a SpellLevel row or a named alternate names a Spell4 row the table lacks, or a class's innate
////   cannot be held (genesis_prime/shared/innate). The repeated tier is the server's own refusal:
////   the client's `GetSpellIdForTier` returns one spell and does not check, and the client's rows
////   hold no repeat. A base the book cannot hold is not read, so its rows may repeat a tier.

import genesis_prime/shared/innate
import genesis_prime/table/id.{
  type Spell4BaseId, type Spell4Id, Spell4BaseId, Spell4Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_tier_requirements
import genesis_prime/table/spell_level
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/order
import gleam/result

/// The highest tier the builder sends: the client's writer drops tier 10 and above
/// (`opcode.0xb1`).
const highest_tier = 9

/// The tiers of every base the book can hold, and the level each tier needs.
pub opaque type SpellTiers {
  SpellTiers(
    bases: Dict(Int, Dict(Int, Tier)),
    levels: Dict(Int, Int),
    alternates: Dict(Int, Int),
  )
}

/// One tier of a base: its Spell4 row and what it costs in ability points.
type Tier {
  Tier(spell4_id: Spell4Id, cost: Int)
}

const tiers_key: table_store.DerivedKey(SpellTiers) =
  table_store.DerivedKey("SpellTiers")

/// Why the tiers cannot be built from the tables.
type BuildError {
  /// Two Spell4 rows of one base hold the same tierIndex.
  TierRepeated(base: Int, tier: Int)
  /// A tier from 2 to 9 has a Spell4 row and no Spell4TierRequirements row.
  NoRequirement(base: Int, tier: Int)
  /// Two Spell4TierRequirements rows name the same tier.
  RequirementRepeated(tier: Int)
  /// A SpellLevel row names a Spell4 row the table lacks.
  NoLevelSpell(spell_level_id: Int, spell4_id: Int)
  /// A tier row names an alternate Spell4 row the table lacks.
  NoAlternate(spell4_id: Int, alternate: Int)
  /// A class's innate cannot be held.
  InnateFailed(error: innate.InnateError)
}

/// The tiers as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`).
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: tiers_key, build: fn(tables) {
    build(tables:) |> result.map_error(describe_build)
  })
}

/// The tiers the tables' load built.
pub fn tiers(tables tables: table_store.Tables) -> SpellTiers {
  table_store.derived(tables:, key: tiers_key)
}

fn build(tables tables: table_store.Tables) -> Result(SpellTiers, BuildError) {
  use levels <- result.try(levels_of(tables:))
  use leveled <- result.try(
    list.try_map(spell_level.all(tables), fn(row) {
      spell4.get(tables:, id: Spell4Id(row.spell4_id))
      |> result.map(fn(spell) { spell.spell4_base_id_base_spell })
      |> result.replace_error(NoLevelSpell(
        spell_level_id: row.id,
        spell4_id: row.spell4_id,
      ))
    }),
  )
  use innates <- result.try(
    innate.held(tables:)
    |> result.map_error(InnateFailed)
    |> result.map(fn(held) {
      list.map(dict.values(held), fn(innate) { innate.active_base.value })
    }),
  )
  let rows_by_base =
    list.group(spell4.all(tables), fn(row) { row.spell4_base_id_base_spell })
  let named = list.append(leveled, innates) |> list.unique
  use alternates <- result.try(
    list.try_map(named, fn(base) {
      alternates_of(tables:, rows: tiers_rows(rows_by_base:, base:))
    }),
  )
  let bases = list.append(named, list.flatten(alternates)) |> list.unique
  let alternate_by_base =
    list.zip(named, alternates)
    |> list.filter_map(fn(pair) {
      list.first(pair.1) |> result.map(fn(alternate) { #(pair.0, alternate) })
    })
    |> dict.from_list
  list.try_fold(bases, dict.new(), fn(held, base) {
    tiers_of(rows: tiers_rows(rows_by_base:, base:), base:, levels:)
    |> result.map(fn(tiers) {
      case dict.is_empty(tiers) {
        True -> held
        False -> dict.insert(held, base, tiers)
      }
    })
  })
  |> result.map(fn(bases) {
    SpellTiers(bases:, levels:, alternates: alternate_by_base)
  })
}

/// A base's Spell4 rows from tier 1 to the highest tier.
fn tiers_rows(
  rows_by_base rows_by_base: Dict(Int, List(spell4.Spell4)),
  base base: Int,
) -> List(spell4.Spell4) {
  dict.get(rows_by_base, base)
  |> result.unwrap([])
  |> list.filter(fn(row) {
    row.tier_index >= 1 && row.tier_index <= highest_tier
  })
}

/// The level each tier needs, by tier index.
fn levels_of(
  tables tables: table_store.Tables,
) -> Result(Dict(Int, Int), BuildError) {
  list.try_fold(
    spell4_tier_requirements.all(tables),
    dict.new(),
    fn(levels, row) {
      case dict.has_key(levels, row.tier_index) {
        True -> Error(RequirementRepeated(tier: row.tier_index))
        False -> Ok(dict.insert(levels, row.tier_index, row.level_requirement))
      }
    },
  )
}

/// The Spell4Bases of the alternates the tier rows name.
fn alternates_of(
  tables tables: table_store.Tables,
  rows rows: List(spell4.Spell4),
) -> Result(List(Int), BuildError) {
  list.try_fold(rows, [], fn(found, row) {
    case row.spell4_id_mechanic_alternate_spell {
      0 -> Ok(found)
      alternate ->
        spell4.get(tables:, id: Spell4Id(alternate))
        |> result.map(fn(spell) { [spell.spell4_base_id_base_spell, ..found] })
        |> result.replace_error(NoAlternate(spell4_id: row.id, alternate:))
    }
  })
}

/// The tiers of a base from its rows: each row is a tier, and a tier above 1 needs a level.
fn tiers_of(
  rows rows: List(spell4.Spell4),
  base base: Int,
  levels levels: Dict(Int, Int),
) -> Result(Dict(Int, Tier), BuildError) {
  list.try_fold(rows, dict.new(), fn(tiers, row) {
    let tier = row.tier_index
    use <- bool.guard(
      when: dict.has_key(tiers, tier),
      return: Error(TierRepeated(base:, tier:)),
    )
    use <- bool.guard(
      when: tier >= 2 && !dict.has_key(levels, tier),
      return: Error(NoRequirement(base:, tier:)),
    )
    Ok(dict.insert(
      tiers,
      tier,
      Tier(spell4_id: Spell4Id(row.id), cost: row.ability_point_cost),
    ))
  })
}

fn describe_build(error error: BuildError) -> String {
  case error {
    TierRepeated(base:, tier:) ->
      "the table Spell4 holds two rows of Spell4Base "
      <> int.to_string(base)
      <> " with tierIndex "
      <> int.to_string(tier)
    NoRequirement(base:, tier:) ->
      "the table Spell4 has a row of tier "
      <> int.to_string(tier)
      <> " of Spell4Base "
      <> int.to_string(base)
      <> ", and the table Spell4TierRequirements has no row of tier "
      <> int.to_string(tier)
    RequirementRepeated(tier:) ->
      "the table Spell4TierRequirements has two rows of tier "
      <> int.to_string(tier)
    NoLevelSpell(spell_level_id:, spell4_id:) ->
      "the table Spell4 has no row "
      <> int.to_string(spell4_id)
      <> ", which SpellLevel row "
      <> int.to_string(spell_level_id)
      <> " names"
    NoAlternate(spell4_id:, alternate:) ->
      "the table Spell4 has no row "
      <> int.to_string(alternate)
      <> ", which Spell4 row "
      <> int.to_string(spell4_id)
      <> " names as its alternate"
    InnateFailed(error:) -> innate.describe(error:)
  }
}

/// The highest tier of a base, or `Error(Nil)` for a base the book cannot hold.
pub fn highest(
  tiers tiers: SpellTiers,
  base base: Spell4BaseId,
) -> Result(Int, Nil) {
  dict.get(tiers.bases, base.value)
  |> result.map(fn(held) { list.fold(dict.keys(held), 1, int.max) })
}

/// The Spell4 row that is a tier of a base, or `Error(Nil)` for a tier with no row.
pub fn spell4_id(
  tiers tiers: SpellTiers,
  base base: Spell4BaseId,
  tier tier: Int,
) -> Result(Spell4Id, Nil) {
  use held <- result.try(dict.get(tiers.bases, base.value))
  dict.get(held, tier) |> result.map(fn(row) { row.spell4_id })
}

/// The tiers 2 to 9 of a base that have a Spell4 row, lowest first, each with its row: none for
/// a base the book cannot hold. A tier with no row is not listed.
pub fn tiers_above_1(
  tiers tiers: SpellTiers,
  base base: Spell4BaseId,
) -> List(#(Int, Spell4Id)) {
  dict.get(tiers.bases, base.value)
  |> result.unwrap(dict.new())
  |> dict.to_list
  |> list.filter(fn(entry) { entry.0 >= 2 })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) { #(entry.0, { entry.1 }.spell4_id) })
}

/// The level a tier needs, or `Error(Nil)` for tier 1, which needs none, and a number that
/// is no tier.
pub fn level_needed(
  tiers tiers: SpellTiers,
  tier tier: Int,
) -> Result(Int, Nil) {
  dict.get(tiers.levels, tier)
}

/// The points a change of a base from one tier to another costs: positive for a raise,
/// negative for a fall (the points given back), 0 for the same tier. `Error(Nil)` for a base
/// with no tier data, and for a tier that is not tier 1 and has no row.
pub fn change_cost(
  tiers tiers: SpellTiers,
  base base: Spell4BaseId,
  from from: Int,
  to to: Int,
) -> Result(Int, Nil) {
  use held <- result.try(dict.get(tiers.bases, base.value))
  let holdable = fn(tier) { tier == 1 || dict.has_key(held, tier) }
  use <- bool.guard(when: !holdable(from) || !holdable(to), return: Error(Nil))
  let crossed = fn(low, high) {
    int.range(from: low + 1, to: high + 1, with: 0, run: fn(sum, tier) {
      let cost =
        dict.get(held, tier)
        |> result.map(fn(row) { row.cost })
        |> result.unwrap(0)
      sum + cost
    })
  }
  case int.compare(from, to) {
    order.Gt -> Ok(-crossed(to, from))
    order.Lt | order.Eq -> Ok(crossed(from, to))
  }
}

/// The points the held tiers cost: each base's change from tier 1 to its tier. A held tier
/// the rule judged has a cost, so a tier with none stops the caller.
pub fn spent(
  tiers tiers: SpellTiers,
  held held: List(#(Spell4BaseId, Int)),
) -> Int {
  list.fold(held, 0, fn(sum, entry) {
    let #(base, tier) = entry
    let assert Ok(cost) = change_cost(tiers:, base:, from: 1, to: tier)
      as {
        "the held tier "
        <> int.to_string(tier)
        <> " of Spell4Base "
        <> int.to_string(base.value)
        <> " was judged by the builder's save or by the entry, so it has a cost"
      }
    sum + cost
  })
}

/// The Spell4Base the tier rows of this base name as its alternate, or `Error(Nil)` for a base
/// that names none or that the book cannot hold.
pub fn alternate_of(
  tiers tiers: SpellTiers,
  base base: Spell4BaseId,
) -> Result(Spell4BaseId, Nil) {
  dict.get(tiers.alternates, base.value) |> result.map(Spell4BaseId)
}
