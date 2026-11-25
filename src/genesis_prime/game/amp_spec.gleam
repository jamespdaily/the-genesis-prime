//// The client's check of the AMPs a player picks (`0x1403d02a0`, CheckAmpSpec), as a pure rule.
//// An AMP is a row of EldanAugmentation: a class, a power cost, the AMP it requires, a category
//// and a tier within the category. The client's name for the AMPs a set holds and the ones picked
//// since the last save is the "spec"; the builder runs its check on each pick and sends the list
//// without checking again, so the server runs the same check (genesis_prime/game/limited_action_set).
////
//// ```
//// load: EldanAugmentation + EldanAugmentationCategory + Class + GameFormula 942 ─▶ Specs
//// level ─▶ power_total(specs, level)                     the power a level gives
//// held ids + picked ids ─▶ check(specs, class_id, level, held, picks) ─▶ Ok, or a Refusal
//// ```
////
//// - **No pick passes** before anything else is read (`0x1403d02a0`), so a list that adds nothing
////   is accepted at any level.
//// - **The power** is 0 below GameFormula 942's `dataint0` (level 10), else
////   `trunc((level - dataint0) * datafloat0) + dataint01`, plus two bonuses the client adds
////   (the Primal Matrix's and the message 0x01A1's) that are 0 here (`0x1403cdbf0`).
//// - **The check, in the client's order**: a total below 1 is result 31; then, for each AMP in list
////   order (the held ones, then the picks): no row 35, the running cost over the total 31,
////   another class 4; then each category whose highest picked tier is 1 or 2 needs
////   `tier2CostAmount00` power spent in its tier 0 AMPs (33), and one whose highest tier is 2 needs
////   `tier3CostAmount00` spent in its tiers 0 and 1 (33), an equal spend passing; last every AMP
////   an AMP requires must be in the list (34). A repeated id is not refused, and a repeated tier 1
////   id is one member of the tier 1 set, so its cost counts once.
//// - **A gap**: a repeated tier 1 id adds its cost to its category's spent power each time it
////   is listed, where the client keeps the tier 1 AMPs in a set and adds each once
////   (`0x1403d02a0`, saved C lines 323 to 331 and 580 to 621). `limited_action_set.take` refuses
////   a repeat (13) before this check runs, so no save reaches it.
//// - **Results the data cannot give** are 32 (an item-unlocked AMP), 36 (no category row) and 37
////   (a tier above 2): the load refuses a row of a playable class that could give one, and a
////   category the client reads through a branch for two shared categories, which no row uses.
////
//// A refusal's number is the client's (`ktAugmentationValidationResult`).

import genesis_prime/game/prerequisite
import genesis_prime/table/class
import genesis_prime/table/eldan_augmentation
import genesis_prime/table/eldan_augmentation_category
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type ClassId, type EldanAugmentationCategoryId, type EldanAugmentationId,
  type Spell4Id, ClassId, EldanAugmentationCategoryId, EldanAugmentationId,
  GameFormulaId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set

/// The AMP rows, their categories and the power formula, read once at the tables' load.
pub opaque type Specs {
  Specs(
    amps: Dict(Int, Amp),
    categories: Dict(EldanAugmentationCategoryId, Category),
    power: Power,
  )
}

/// The columns of an AMP row the check reads.
type Amp {
  Amp(
    class_id: Int,
    power_cost: Int,
    required: EldanAugmentationId,
    category: EldanAugmentationCategoryId,
    tier: Int,
  )
}

/// The power a category's tiers 1 and 2 need spent below them.
type Category {
  Category(tier_1_needs: Int, tier_2_needs: Int)
}

/// GameFormula 942: the level the power starts at, the power there and the power each level
/// above it adds.
type Power {
  Power(first_level: Int, at_first_level: Int, per_level: Float)
}

/// The formula the client reads the AMP power from (`0x1403cdbf0`).
const power_formula = 942

/// The highest tier an AMP row holds in the client's check (`0x1403d02a0`).
const highest_tier = 2

const specs_key: table_store.DerivedKey(Specs) =
  table_store.DerivedKey("AmpSpecs")

/// Why the client's check refuses a list, with the number it names the result by.
pub type Refusal {
  /// The power is not enough: the total is below 1, or the costs up to this AMP pass it (31).
  NotEnoughPower(id: EldanAugmentationId, total: Int, spent: Int)
  /// An AMP has no row (35).
  InvalidId(id: EldanAugmentationId)
  /// An AMP belongs to another class (4).
  InvalidClass(id: EldanAugmentationId, class_id: ClassId)
  /// A category's tier 1 or 2 AMP is picked before enough power is spent in the tiers below it
  /// (33): `tier` is the tier that is locked.
  LockedCategoryTier(
    category: EldanAugmentationCategoryId,
    tier: Int,
    spent: Int,
    needed: Int,
  )
  /// An AMP is picked without the AMP it requires (34).
  InvalidSeries(id: EldanAugmentationId, required: EldanAugmentationId)
}

/// Why the specs cannot be built from the tables.
type BuildError {
  /// GameFormula 942 has no row.
  NoPowerFormula
  /// A category row that is not its own tier 2 category, or has a second one: the client's
  /// branch for a category shared by two is read and unbuilt.
  CategoryShared(row_id: Int)
  /// An AMP of a playable class names a category with no row.
  AmpNamesNoCategory(row_id: Int, category: EldanAugmentationCategoryId)
  /// An AMP of a playable class has a tier the check does not know.
  AmpTierUnknown(row_id: Int, tier: Int)
  /// An AMP of a playable class needs an item unlocked.
  AmpNeedsItem(row_id: Int)
}

/// Why the spells of the AMPs cannot be roots of the plans.
pub type RootError {
  /// An AMP of a playable class names a Spell4 the table has no row for.
  AmpSpellNotRead(id: EldanAugmentationId, spell4_id: Spell4Id)
}

/// The AMPs of a playable class split by what their spell does.
pub type Roots {
  Roots(
    /// The spells that stand while their AMP is held, each once, lowest Spell4 id first.
    spells: List(Int),
    /// The AMPs a type 227 Prerequisite condition names, lowest id first: they unlock a class
    /// ability, and their spell is not a root.
    unlocking: List(Unlocking),
  )
}

/// An AMP that unlocks a class ability and the spell its row names (the ability's own spell).
pub type Unlocking {
  Unlocking(id: EldanAugmentationId, spell4_id: Spell4Id)
}

/// The spell of every AMP of a playable class (`EldanAugmentation.spell4IdAugment`), read from the
/// tables directly so the plans can start from them before the specs are derived. An AMP whose
/// id a type 227 Prerequisite condition names unlocks a class ability: it is left out of the
/// roots, with its spell, as "unlocks a class ability, not built" (`describe_unlocking`). The
/// AMP spell stands while the AMP is held only for the rest. The ability unlock is not built.
pub fn roots(tables tables: table_store.Tables) -> Result(Roots, RootError) {
  let asked_for =
    prerequisite_table.all(tables)
    |> list.flat_map(fn(row) { prerequisite.amps_asked_for(row:) })
    |> set.from_list
  use rows <- result.map(
    list.try_map(
      list.filter(eldan_augmentation.all(tables), is_playable(tables:, row: _)),
      fn(row) {
        let spell4_id = eldan_augmentation.spell4_id_augment(row)
        case spell4.get(tables:, id: spell4_id) {
          Ok(_) -> Ok(#(row, spell4_id))
          Error(Nil) ->
            Error(AmpSpellNotRead(id: EldanAugmentationId(row.id), spell4_id:))
        }
      },
    ),
  )
  let #(unlocking, standing) =
    list.partition(rows, fn(entry) { set.contains(asked_for, { entry.0 }.id) })
  Roots(
    spells: list.map(standing, fn(entry) { { entry.1 }.value })
      |> list.unique
      |> list.sort(int.compare),
    unlocking: list.map(unlocking, fn(entry) {
      Unlocking(id: EldanAugmentationId({ entry.0 }.id), spell4_id: entry.1)
    })
      |> list.sort(fn(first, second) {
        int.compare(first.id.value, second.id.value)
      }),
  )
}

/// Whether the AMP's class is one a player can be: it has a Class row. The AMPs of the other
/// classes (0 and 16) are never offered, held or checked.
fn is_playable(
  tables tables: table_store.Tables,
  row row: eldan_augmentation.EldanAugmentation,
) -> Bool {
  result.is_ok(class.get(tables:, id: ClassId(row.class_id)))
}

/// A sentence for why an AMP's spell is no root.
pub fn describe_root(error error: RootError) -> String {
  let AmpSpellNotRead(id:, spell4_id:) = error
  "EldanAugmentation "
  <> int.to_string(id.value)
  <> " names Spell4 "
  <> int.to_string(spell4_id.value)
  <> ", which Spell4 has no row for"
}

/// A sentence for why an AMP's spell is no root: the AMP unlocks a class ability.
pub fn describe_unlocking(unlocking unlocking: Unlocking) -> String {
  "EldanAugmentation "
  <> int.to_string(unlocking.id.value)
  <> " unlocks a class ability, not built"
}

/// Whether the AMP has a row, and one of the class: the client's check refuses an AMP with no
/// row (35) and one of another class (4), and the entry drops a stored one it would refuse.
pub fn is_of_class(
  specs specs: Specs,
  class_id class_id: ClassId,
  id id: EldanAugmentationId,
) -> Bool {
  case dict.get(specs.amps, id.value) {
    Ok(amp) -> amp.class_id == class_id.value
    Error(Nil) -> False
  }
}

/// The specs as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`).
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: specs_key, build: fn(tables) {
    build(tables:) |> result.map_error(describe_build)
  })
}

/// The specs the tables' load built.
pub fn specs(tables tables: table_store.Tables) -> Specs {
  table_store.derived(tables:, key: specs_key)
}

fn build(tables tables: table_store.Tables) -> Result(Specs, BuildError) {
  use formula <- result.try(
    game_formula.get(tables:, id: GameFormulaId(power_formula))
    |> result.replace_error(NoPowerFormula),
  )
  use categories <- result.try(
    list.try_map(eldan_augmentation_category.all(tables), fn(row) {
      use <- bool.guard(
        when: row.eldan_augmentation_category_id_tier2_category00 != row.id
          || row.eldan_augmentation_category_id_tier2_category01 != 0
          || row.tier2_cost_amount01 != 0
          || row.tier3_cost_amount01 != 0,
        return: Error(CategoryShared(row_id: row.id)),
      )
      Ok(#(
        EldanAugmentationCategoryId(row.id),
        Category(
          tier_1_needs: row.tier2_cost_amount00,
          tier_2_needs: row.tier3_cost_amount00,
        ),
      ))
    }),
  )
  let categories = dict.from_list(categories)
  use amps <- result.map(
    list.try_map(eldan_augmentation.all(tables), fn(row) {
      let playable = is_playable(tables:, row:)
      let category = eldan_augmentation.eldan_augmentation_category_id(row)
      use <- bool.guard(
        when: playable && !dict.has_key(categories, category),
        return: Error(AmpNamesNoCategory(row_id: row.id, category:)),
      )
      use <- bool.guard(
        when: playable && row.category_tier > highest_tier,
        return: Error(AmpTierUnknown(row_id: row.id, tier: row.category_tier)),
      )
      use <- bool.guard(
        when: playable && row.item2_id_unlock != 0,
        return: Error(AmpNeedsItem(row_id: row.id)),
      )
      Ok(#(
        row.id,
        Amp(
          class_id: row.class_id,
          power_cost: row.power_cost,
          required: eldan_augmentation.eldan_augmentation_id_required(row),
          category:,
          tier: row.category_tier,
        ),
      ))
    }),
  )
  Specs(
    amps: dict.from_list(amps),
    categories:,
    power: Power(
      first_level: formula.dataint0,
      at_first_level: formula.dataint01,
      per_level: formula.datafloat0,
    ),
  )
}

fn describe_build(error error: BuildError) -> String {
  case error {
    NoPowerFormula ->
      "GameFormula 942 has no row, which the AMP power (the check of picked AMPs) reads"
    CategoryShared(row_id:) ->
      "EldanAugmentationCategory "
      <> int.to_string(row_id)
      <> " is not its own tier 2 category or holds a second amount, which the check of picked AMPs does not read"
    AmpNamesNoCategory(row_id:, category:) ->
      "EldanAugmentation "
      <> int.to_string(row_id)
      <> " names category "
      <> int.to_string(category.value)
      <> ", which EldanAugmentationCategory has no row for"
    AmpTierUnknown(row_id:, tier:) ->
      "EldanAugmentation "
      <> int.to_string(row_id)
      <> " has tier "
      <> int.to_string(tier)
      <> ", and the check of picked AMPs knows tiers 0 to "
      <> int.to_string(highest_tier)
    AmpNeedsItem(row_id:) ->
      "EldanAugmentation "
      <> int.to_string(row_id)
      <> " of a playable class needs an item unlocked, which the check of picked AMPs does not read"
  }
}

/// The power a level gives (`0x1403cdbf0`): none below the formula's first level, else the
/// power there and the formula's per-level power for each level above it, truncated. The two
/// bonuses the client adds are 0.
pub fn power_total(specs specs: Specs, level level: Int) -> Int {
  let Power(first_level:, at_first_level:, per_level:) = specs.power
  case level < first_level {
    True -> 0
    False ->
      float.truncate(int.to_float(level - first_level) *. per_level)
      + at_first_level
  }
}

/// The client's check of the AMPs held in the set followed by the AMPs picked since the last
/// save (`0x1403d02a0`): `Ok` for a list the client accepts, else the first refusal in the
/// client's order. With no pick it passes before the power is read.
pub fn check(
  specs specs: Specs,
  class_id class_id: ClassId,
  level level: Int,
  held held: List(EldanAugmentationId),
  picks picks: List(EldanAugmentationId),
) -> Result(Nil, Refusal) {
  case picks {
    [] -> Ok(Nil)
    [first, ..] -> {
      let total = power_total(specs:, level:)
      use <- bool.guard(
        when: total < 1,
        return: Error(NotEnoughPower(id: first, total:, spent: 0)),
      )
      let listed = list.append(held, picks)
      use spent <- result.try(spend(specs:, class_id:, total:, listed:))
      use _ <- result.try(locked_tiers(specs:, spent:))
      required_held(specs:, listed:)
    }
  }
}

/// What a list spends: the power in each category's tier 0 and tier 1 AMPs and the highest
/// tier each category holds.
type Spent {
  Spent(
    tier_0: Dict(EldanAugmentationCategoryId, Int),
    tier_1: Dict(EldanAugmentationCategoryId, Int),
    highest: Dict(EldanAugmentationCategoryId, Int),
    total: Int,
  )
}

/// The per-AMP checks in list order: a missing row, the running cost over the total, another
/// class.
fn spend(
  specs specs: Specs,
  class_id class_id: ClassId,
  total total: Int,
  listed listed: List(EldanAugmentationId),
) -> Result(Spent, Refusal) {
  list.try_fold(
    listed,
    Spent(tier_0: dict.new(), tier_1: dict.new(), highest: dict.new(), total: 0),
    fn(spent, id) {
      use amp <- result.try(
        dict.get(specs.amps, id.value) |> result.replace_error(InvalidId(id:)),
      )
      let cost = spent.total + amp.power_cost
      use <- bool.guard(
        when: cost > total,
        return: Error(NotEnoughPower(id:, total:, spent: cost)),
      )
      use <- bool.guard(
        when: amp.class_id != class_id.value,
        return: Error(InvalidClass(id:, class_id: ClassId(amp.class_id))),
      )
      Ok(case amp.tier {
        0 ->
          Spent(
            ..spent,
            total: cost,
            tier_0: added(
              by: spent.tier_0,
              category: amp.category,
              cost: amp.power_cost,
            ),
          )
        1 ->
          Spent(
            ..spent,
            total: cost,
            tier_1: added(
              by: spent.tier_1,
              category: amp.category,
              cost: amp.power_cost,
            ),
            highest: raised(by: spent.highest, category: amp.category, tier: 1),
          )
        tier ->
          Spent(
            ..spent,
            total: cost,
            highest: raised(by: spent.highest, category: amp.category, tier:),
          )
      })
    },
  )
}

/// The dict with the cost added to the category's total.
fn added(
  by by: Dict(EldanAugmentationCategoryId, Int),
  category category: EldanAugmentationCategoryId,
  cost cost: Int,
) -> Dict(EldanAugmentationCategoryId, Int) {
  dict.insert(by, category, result.unwrap(dict.get(by, category), 0) + cost)
}

/// The dict with the category's highest tier raised to this tier when it is higher.
fn raised(
  by by: Dict(EldanAugmentationCategoryId, Int),
  category category: EldanAugmentationCategoryId,
  tier tier: Int,
) -> Dict(EldanAugmentationCategoryId, Int) {
  dict.insert(
    by,
    category,
    int.max(result.unwrap(dict.get(by, category), 0), tier),
  )
}

/// Each category whose highest tier is 1 or 2 needs the power its tier 1 needs spent in tier 0,
/// and each whose highest tier is 2 the power its tier 2 needs spent in tiers 0 and 1, both in
/// category order; an equal spend passes.
fn locked_tiers(
  specs specs: Specs,
  spent spent: Spent,
) -> Result(Nil, Refusal) {
  let categories =
    dict.to_list(spent.highest)
    |> list.sort(fn(a, b) { int.compare(a.0.value, b.0.value) })
  let in_tier_0 = fn(category) {
    result.unwrap(dict.get(spent.tier_0, category), 0)
  }
  let in_tier_1 = fn(category) {
    result.unwrap(dict.get(spent.tier_1, category), 0)
  }
  let needs = fn(category) {
    // The load refuses a row of a playable class with no category, so a held AMP has one.
    let assert Ok(row) = dict.get(specs.categories, category)
      as "the load refuses an AMP of a playable class that names no category"
    row
  }
  let first =
    list.try_each(categories, fn(entry) {
      let #(category, _) = entry
      let spent_0 = in_tier_0(category)
      let Category(tier_1_needs:, ..) = needs(category)
      use <- bool.guard(
        when: spent_0 < tier_1_needs,
        return: Error(LockedCategoryTier(
          category:,
          tier: 1,
          spent: spent_0,
          needed: tier_1_needs,
        )),
      )
      Ok(Nil)
    })
  use _ <- result.try(first)
  list.try_each(categories, fn(entry) {
    let #(category, highest) = entry
    let spent_01 = in_tier_0(category) + in_tier_1(category)
    let Category(tier_2_needs:, ..) = needs(category)
    use <- bool.guard(
      when: highest == 2 && spent_01 < tier_2_needs,
      return: Error(LockedCategoryTier(
        category:,
        tier: 2,
        spent: spent_01,
        needed: tier_2_needs,
      )),
    )
    Ok(Nil)
  })
}

/// Every AMP an AMP of the list requires is in the list (`0x1403d5640`, std::includes).
fn required_held(
  specs specs: Specs,
  listed listed: List(EldanAugmentationId),
) -> Result(Nil, Refusal) {
  list.try_each(listed, fn(id) {
    let assert Ok(amp) = dict.get(specs.amps, id.value)
      as "the per-AMP check found a row for every AMP of the list"
    use <- bool.guard(
      when: amp.required.value == 0 || list.contains(listed, amp.required),
      return: Ok(Nil),
    )
    Error(InvalidSeries(id:, required: amp.required))
  })
}

/// The client's number for the result (`ktAugmentationValidationResult`).
pub fn result_of(refusal refusal: Refusal) -> Int {
  case refusal {
    NotEnoughPower(..) -> 31
    InvalidId(..) -> 35
    InvalidClass(..) -> 4
    LockedCategoryTier(..) -> 33
    InvalidSeries(..) -> 34
  }
}

/// A sentence that says which AMP or category the check refused and why, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotEnoughPower(id:, total:, spent:) ->
      "AMP "
      <> int.to_string(id.value)
      <> case total < 1 {
        True -> " is picked at a level that gives no AMP power (NotEnoughPower)"
        False ->
          " passes the level's power: the costs come to "
          <> int.to_string(spent)
          <> " of "
          <> int.to_string(total)
          <> " (NotEnoughPower)"
      }
    InvalidId(id:) ->
      "AMP " <> int.to_string(id.value) <> " has no row (InvalidId)"
    InvalidClass(id:, class_id:) ->
      "AMP "
      <> int.to_string(id.value)
      <> " belongs to class "
      <> int.to_string(class_id.value)
      <> ", not the player's (InvalidClass)"
    LockedCategoryTier(category:, tier:, spent:, needed:) ->
      "category "
      <> int.to_string(category.value)
      <> " holds a tier "
      <> int.to_string(tier)
      <> " AMP and has "
      <> int.to_string(spent)
      <> " power spent below it, which needs "
      <> int.to_string(needed)
      <> " (LockedCategoryTier)"
    InvalidSeries(id:, required:) ->
      "AMP "
      <> int.to_string(id.value)
      <> " needs AMP "
      <> int.to_string(required.value)
      <> " held (InvalidSeries)"
  }
}
