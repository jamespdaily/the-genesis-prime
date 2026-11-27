//// What Spell Surge changes in the plans and the table load
//// (`genesis_prime/shared/spell_plan`, `genesis_prime/game/spell_surge`). Expected values
//// come from the client's code and rows, each named at its assertion:
//// - `Spell4.spell4IdMechanicAlternateSpell` (`gleam run -m genesis_prime/table_rows --
////   Spell4 43468 34718 34355 76002 34719`): Quick Draw 43468 names 76002 and Charged Shot
////   34718 names 34719; Gate 34355, 76002 and 34719 name none.
//// - Spell4Thresholds 129, 192 and 190 (`table_rows -- Spell4Thresholds spell4IdParent=34719`):
////   the stages of 34719, in order index order.
//// - CastAbilityBagSpell `0x14039a040` through SpellslingerSurgedSpell `0x1405e7e50`, which
////   swaps only to a spell whose base GetAbilityBookSpell `0x1403bad30` finds in the ability
////   book.
//// - IsSpellSurgeActive `0x1405e7d10`: the spell is GameFormula 913's dataint0.
//// A test that reads the client's tables is guarded by `client_tables.present()`; the
//// fixture's rows hold the same rows the client's do for these spells.

import client_tables
import fixture_tables
import genesis_prime/game/ability_book
import genesis_prime/game/spell_surge
import genesis_prime/shared/loadout
import genesis_prime/shared/spell_plan.{type Spell}
import genesis_prime/table/id.{ClassId, Spell4BaseId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import spell_tables
import unitest

fn planned(base base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.fixture_plans(),
      base: Spell4BaseId(base),
    )
    as "the plans hold the ability"
  spell
}

fn stages_of(spell spell: Spell) -> List(#(Int, Int)) {
  list.map(spell.stages, fn(stage) {
    #(stage.spell.spell4_id.value, stage.duration_ms)
  })
}

pub fn alternate_spells_plan_quick_draw_and_charged_shot_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Some(quick_draw) = planned(base: 27_638).alternate
    as "Spell4.43468: spell4IdMechanicAlternateSpell 76002"
  assert quick_draw.spell4_id == Spell4Id(76_002)
  assert quick_draw.spell4_base_id == Spell4BaseId(52_215)
    as "Spell4.76002 is of Spell4Base 52215, the base the ability book must hold"
  assert quick_draw.costs == [spell_plan.ClassVitalCost(vital: 19, amount: 25)]
    as "Spell4.76002: innate cost type 19, 25 (Spell Power)"
  assert quick_draw.alternate == None
    as "Spell4.76002 names no alternate, and the client swaps once"
  let assert Some(charged_shot) = planned(base: 20_684).alternate
    as "Spell4.34718: spell4IdMechanicAlternateSpell 34719"
  assert charged_shot.spell4_id == Spell4Id(34_719)
  assert charged_shot.spell4_base_id == Spell4BaseId(20_685)
  assert charged_shot.method == spell_plan.ChargeRelease
    as "Spell4Base 20685 casts as Charged Shot does"
  assert stages_of(spell: charged_shot)
    == [#(79_679, 0), #(34_766, 600), #(34_767, 800)]
    as "Spell4Thresholds 129, 192 and 190 by orderIndex 0, 1 and 2"
  assert charged_shot.costs == [spell_plan.RowClassCost(vital: 19, amount: 25)]
    as "row 129's cost (19, 25) is paid at the press that opens the charge (the server's choice)"
  let assert [first, ..] = charged_shot.stages
  assert first.spell.costs == []
    as "the opening press paid it, so the stage it casts at release costs nothing more"
  assert planned(base: 20_325).alternate == None
    as "Spell4.34355 (Gate): spell4IdMechanicAlternateSpell 0"
  assert quick_draw.alternate == None && charged_shot.alternate == None
  assert planned(base: 19_102).alternate == None
    as "Telekinetic Strike has none"
  let assert Ok(by_base) =
    spell_plan.in_plans(
      plans: spell_tables.fixture_plans(),
      base: Spell4BaseId(52_215),
    )
    as "the alternate is planned under its own base too, for the book"
  assert by_base.spell4_id == Spell4Id(76_002)
}

pub fn the_spellslinger_book_is_its_bag_then_its_alternates_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let assert Ok(set) =
    loadout.of(tables:, class_id: ClassId(7), faction_id: 166)
  let bag = ability_book.bag(loadout: set, level: 1)
  assert bag
    == [
      Spell4BaseId(27_638),
      Spell4BaseId(20_684),
      Spell4BaseId(20_325),
      Spell4BaseId(31_213),
    ]
    as "the fixture's Spellslinger bag: Quick Draw, Charged Shot, Gate, Spell Surge"
  assert spell_plan.book(plans: spell_tables.fixture_plans(), bag:)
    == list.append(bag, [Spell4BaseId(52_215), Spell4BaseId(20_685)])
    as "the bag, then the alternate base of each bag ability in bag order (Spell4.spell4IdMechanicAlternateSpell); Gate and Spell Surge name none"
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let plans = spell_plan.plans(real)
  list.each([1, 2, 3, 4, 5, 7], fn(class_id) {
    let assert Ok(set) =
      loadout.of(tables: real, class_id: ClassId(class_id), faction_id: 166)
    let bag = ability_book.bag(loadout: set, level: 1)
    let book = spell_plan.book(plans:, bag:)
    case class_id {
      7 -> {
        assert list.take(book, list.length(bag)) == bag
          as "the Spellslinger's book starts with its bag"
        assert list.contains(book, Spell4BaseId(52_215))
          && list.contains(book, Spell4BaseId(20_685))
          as "Quick Draw's and Charged Shot's alternates"
      }
      _ -> {
        assert book == bag
          as {
            "only the Spellslinger's SpellLevel rows name an alternate: class "
            <> int.to_string(class_id)
          }
      }
    }
  })
}

pub fn game_formula_913_loads_as_the_surge_spell_test() -> Nil {
  use <- owned_test.run(60_000)
  assert spell_surge.spell(tables: fixture_tables.shared()) == Spell4Id(47_439)
    as "IsSpellSurgeActive 0x1405e7d10 reads GameFormula 913's dataint0: 47439"
  let assert Ok(rows) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "GameFormula",
      id: 913,
    )
    as "the fixture holds GameFormula 913"
  let assert Error(table_store.DerivationFailed(name: "SpellSurge", reason:)) =
    fixture_tables.load(rows:)
    as "a load without the row the Surge spell is read from fails"
  assert string.contains(reason, "GameFormula")
    && string.contains(reason, "913")
    as "the load names the table and the id"
}
