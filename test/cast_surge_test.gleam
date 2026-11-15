//// A press under Spell Surge casts the ability's alternate spell (`genesis_prime/game/cast`).
//// Expected values come from these places, each named at its assertion:
//// - CastAbilityBagSpell `0x14039a040`: before the threshold step the client swaps the
////   ability for its alternate through SpellslingerSurgedSpell `0x1405e7e50`, which does so
////   only when IsSpellSurgeActive `0x1405e7d10` finds a node of GameFormula 913's spell
////   (47439) on the player's unit and GetAbilityBookSpell `0x1403bad30` finds the alternate's
////   base in the ability book.
//// - `Spell4.spell4IdMechanicAlternateSpell`: Quick Draw 43468 names 76002, Charged Shot 34718
////   names 34719, Gate 34355 names none.
//// - The costs: Spell4.76002's innate cost (19, 25) with CheckClassResourceCost `0x1405e7980`
////   (refused 50 + 4 below 25), and Spell4Thresholds 129's row cost (19, 25) with
////   CheckThresholdRowCosts `0x1403c0620` and VitalCostResult `0x1403d3650` (refused 54 at 1 to
////   24 and 175 at 0), paid at the press that opens the charge (Jim, 2026-11-15).
//// The bag indices are the Spellslinger's here: 0 Spell Surge, 1 Quick Draw, 2 Charged Shot,
//// 3 Gate. A Surge cast is a press of Spell Surge 47273 (base 31213) at Spell Power 100.

import cast_support as support
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/class_resource.{Payment}
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{type Spell4BaseId, Spell4BaseId}
import gleam/list
import owned_test

const spell_surge = 0

const quick_draw = 1

const charged_shot = 2

const gate = 3

fn book() -> List(Spell4BaseId) {
  [
    Spell4BaseId(31_213),
    Spell4BaseId(27_638),
    Spell4BaseId(20_684),
    Spell4BaseId(20_325),
    Spell4BaseId(52_215),
    Spell4BaseId(20_685),
  ]
}

fn spellslinger(power power: Float) -> Caster {
  cast.Caster(
    ..support.caster_holding(resources: support.holding(
      class_id: 7,
      value: power,
    )),
    abilities: list.take(book(), 4),
    book: book(),
  )
}

/// The state after the Spellslinger's press of Spell Surge at 1000 ms.
fn surging() -> State {
  let #(state, effects) =
    support.press_as(
      plans: support.plans(),
      state: cast.new(),
      caster: spellslinger(power: 100.0),
      bag: spell_surge,
      at: 1000,
    )
  assert support.refusal_results(effects:) == [] as "Spell Surge 47273 is cast"
  state
}

/// The press of the bag index by the caster, at 3000 ms (past every global cooldown of the
/// Surge press), as the rule's effects.
fn pressed(
  state state: State,
  caster caster: Caster,
  bag bag: Int,
) -> List(Effect) {
  let #(_, effects) =
    support.pressed_raw_in(
      plans: support.plans(),
      state:,
      caster:,
      bag_index: bag,
      target: 0,
      at: 3000,
    )
  effects
}

/// The Spell4 id each root cast the press starts, as its viewers are told.
fn started(effects effects: List(Effect)) -> List(Int) {
  list.filter_map(support.tells(effects:), fn(tell) {
    case tell {
      #(ConnectionId(2), CastStarted(start:)) if start.parent_spell4_id == 0 ->
        Ok(start.spell4_id)
      _ -> Error(Nil)
    }
  })
}

pub fn a_surged_press_resolves_to_the_alternate_spell_test() -> Nil {
  use <- owned_test.run(60_000)
  assert started(effects: pressed(
      state: surging(),
      caster: spellslinger(power: 100.0),
      bag: quick_draw,
    ))
    == [76_002]
    as "a node of 47439 is held and the book holds base 52215: Quick Draw's press casts 76002 (0x14039a040 through 0x1405e7e50)"
  assert started(effects: pressed(
      state: cast.new(),
      caster: spellslinger(power: 100.0),
      bag: quick_draw,
    ))
    == [43_468]
    as "with no node of 47439 the press stays Quick Draw 43468 (0x1405e7d10)"
}

pub fn a_surged_press_whose_alternate_is_not_in_the_book_stays_plain_test() -> Nil {
  use <- owned_test.run(60_000)
  let without_alternates =
    cast.Caster(..spellslinger(power: 100.0), book: list.take(book(), 4))
  assert started(effects: pressed(
      state: surging(),
      caster: without_alternates,
      bag: quick_draw,
    ))
    == [43_468]
    as "0x1405e7e50 gives no swap when GetAbilityBookSpell 0x1403bad30 has no entry for 52215, and the press stays plain"
}

pub fn a_surged_press_of_a_spell_with_no_alternate_stays_plain_test() -> Nil {
  use <- owned_test.run(60_000)
  let effects =
    pressed(state: surging(), caster: spellslinger(power: 100.0), bag: gate)
  assert started(effects:) == [34_355]
    as "Spell4.34355: spell4IdMechanicAlternateSpell is 0, so Gate's press stays Gate"
}

pub fn a_surged_quick_draw_at_24_spell_power_is_refused_54_test() -> Nil {
  use <- owned_test.run(60_000)
  let effects =
    pressed(
      state: surging(),
      caster: spellslinger(power: 24.0),
      bag: quick_draw,
    )
  assert support.refusal_results(effects:) == [54]
    as "76002's innate cost (19, 25): slot 4 holds 24 and 24 - 25 < 0, refused 50 + 4 (0x1405e7980)"
  assert started(effects:) == [] as "a refused press starts nothing"
  assert support.payments(effects:) == []
  let paid =
    pressed(
      state: surging(),
      caster: spellslinger(power: 25.0),
      bag: quick_draw,
    )
  assert support.payments(effects: paid) == [Payment(slot: 4, amount: 25)]
    as "at 25 the press passes and pays 25 from slot 4"
}

pub fn a_surged_charged_shot_opening_press_is_refused_54_at_24_and_175_at_0_test() -> Nil {
  use <- owned_test.run(60_000)
  let at_24 =
    pressed(
      state: surging(),
      caster: spellslinger(power: 24.0),
      bag: charged_shot,
    )
  assert support.refusal_results(effects: at_24) == [54]
    as "Spell4Thresholds 129's cost (19, 25) is checked at the press that opens the charge: 24 < 25 gives 50 + 4 (0x1403c0620, 0x1403d3650)"
  assert support.payments(effects: at_24) == []
  let at_0 =
    pressed(
      state: surging(),
      caster: spellslinger(power: 0.0),
      bag: charged_shot,
    )
  assert support.refusal_results(effects: at_0) == [175]
    as "no slot naming 19 holds above 0, VitalCostResult 0x1403d3650 gives 175"
  let at_25 =
    pressed(
      state: surging(),
      caster: spellslinger(power: 25.0),
      bag: charged_shot,
    )
  assert support.refusal_results(effects: at_25) == []
  assert support.payments(effects: at_25) == [Payment(slot: 4, amount: 25)]
    as "the opening press pays the 25 (Jim, 2026-11-15)"
}
