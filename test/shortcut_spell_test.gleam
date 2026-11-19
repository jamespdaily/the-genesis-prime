//// The spells an item casts on its user (`genesis_prime/game/shortcut_spell`): which an item's
//// use plays, which it refuses and why, and which stay with the creature's activate cast.
//// Expected values come from these places.
//// - A spell is cast on its user when its Spell4TargetMechanics row is a Caster kind
////   (targetType 0, 2, 6, 7: `0x14055bdc0`); the other kinds are cast at a unit.
//// - The client's rows in the fixture, by Item2 -> ItemSpecial.spell4IdOnActivate:
////   14838 -> Spell4 34985 (Basic Medishot: Heal row 69917, parameter 18); 37649 -> 34993
////   (Heal row 69936, tick 2,000 ms for 20,000 ms); 4730 -> 3792 (a caster-aimed type 11
////   BaseHealth row 6403, no parameter); 14850 -> 35022 (type 11 row 69997 with a type 18
////   parameter); 13027 -> 28682 (type 38 row 49524); 2900 -> 1664 (Activate row 2530);
////   90021 -> 87129 (type 11 rows 227562, 227573 and 227574 holding the suspend
////   prerequisite 43393); 6914 -> 34776 (VitalModifier row 88371 of vital 15, which the
////   plan cannot read); 5733 -> 5640 (a Ground kind); 6017 -> 7103 (which a quest
////   objective also names).

import client_tables
import fixture_tables
import genesis_prime/game/activate
import genesis_prime/game/shortcut_spell.{Aimed, CannotBePlanned, Planned}
import genesis_prime/game/spell_plan
import genesis_prime/game/target_mechanic
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/item_special
import genesis_prime/table/spell4
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import unitest

/// What an item's use of a spell comes to.
type Outcome {
  /// Planned, and an item's use plays every row of it.
  Plays
  /// Planned, and an item's use is refused with a reason that names these.
  Refused(naming: List(String))
  /// Not planned, and an item's use is refused with a reason that names these.
  CannotPlan(naming: List(String))
  /// Not planned for an item's use: the creature's activate cast has it.
  LeftToActivations
}

pub fn an_item_spell_is_planned_or_refused_by_its_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let shortcuts = shortcut_spell.shortcuts(tables: fixture_tables.shared())
  list.each(
    [
      #(34_985, Plays, "Heal row 69917 with parameter 18 is read"),
      #(34_993, Plays, "Heal 69936 ticks every 2,000 ms for 20,000 ms"),
      #(3792, Plays, "a caster-aimed type 11 row 6403 with no parameter"),
      #(
        35_022,
        Refused(["69997", "type 11"]),
        "a type 11 row with a type 18 parameter",
      ),
      #(28_682, Refused(["49524", "type 38"]), "no rule reads type 38"),
      #(1664, Refused(["2530", "Activate"]), "an Activate row is a unit's use"),
      #(
        87_129,
        Refused(["227562", "43393"]),
        "the suspend prerequisite 43393 is not read",
      ),
      #(
        34_776,
        CannotPlan(["15"]),
        "a VitalModifier of vital 15 cannot be planned",
      ),
      #(5640, LeftToActivations, "a Ground kind is cast at a place"),
    ],
    fn(row) {
      let #(spell4_id, outcome, why) = row
      let planned = shortcut_spell.planned_of(shortcuts:, spell4_id:)
      let refusal = shortcut_spell.item_refusal_of(shortcuts:, spell4_id:)
      case outcome {
        Plays -> {
          assert planned_spell(planned) == Ok(spell4_id) as why
          assert refusal == Error(Nil) as why
        }
        Refused(naming:) -> {
          assert planned_spell(planned) == Ok(spell4_id) as why
          assert names(refusal, naming) as why
        }
        CannotPlan(naming:) -> {
          assert is_unplanned(planned) as why
          assert names(refusal, naming) as why
        }
        LeftToActivations -> {
          assert planned_spell(planned) == Error(Nil) as why
          assert refusal == Error(Nil) as why
        }
      }
    },
  )
}

pub fn a_spell_an_objective_and_an_item_both_name_keeps_the_objectives_plan_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let shortcuts = shortcut_spell.shortcuts(tables:)
  let sources = spell_plan.sources_of(tables:)
  let assert Ok(alone) =
    spell_plan.spell_alone(tables:, sources:, spell4_id: 25_306, chain: [])
    as "Spell4 25306 plans on its own"
  assert shortcut_spell.planned_of(shortcuts:, spell4_id: 25_306)
    == Ok(Planned(spell: alone))
    as "the quest button's cast of Spell4 25306 is the plan it had before an item named it"
  assert names(shortcut_spell.item_refusal_of(shortcuts:, spell4_id: 25_306), [
    "Activate",
  ])
    as "an item's use of it is refused for its Activate row, whatever the button does"
}

fn planned_spell(
  planned: Result(shortcut_spell.Planned, Nil),
) -> Result(Int, Nil) {
  case planned {
    Ok(Planned(spell:)) -> Ok(spell.spell4_id.value)
    Ok(Aimed(..)) | Ok(CannotBePlanned(..)) | Ok(shortcut_spell.NoSpell4Row) ->
      Error(Nil)
    Error(Nil) -> Error(Nil)
  }
}

fn is_unplanned(planned: Result(shortcut_spell.Planned, Nil)) -> Bool {
  case planned {
    Ok(CannotBePlanned(..)) -> True
    Ok(Planned(..)) | Ok(Aimed(..)) | Ok(shortcut_spell.NoSpell4Row) -> False
    Error(Nil) -> False
  }
}

fn names(refusal: Result(String, Nil), naming: List(String)) -> Bool {
  case refusal {
    Ok(why) -> list.all(naming, fn(word) { string.contains(why, word) })
    Error(Nil) -> False
  }
}

pub fn every_item_spell_of_the_client_has_one_outcome_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let shortcuts = shortcut_spell.shortcuts(tables:)
  let activations = activate.activations(tables:)
  let item_spells =
    item_special.all(tables)
    |> list.map(fn(row) { row.spell4_id_on_activate })
    |> list.filter(fn(spell4_id) { spell4_id != 0 })
    |> set.from_list
    |> set.to_list
  let kinds =
    list.filter_map(item_spells, fn(spell4_id) {
      case spell4.get(tables:, id: Spell4Id(spell4_id)) {
        Ok(row) ->
          case shortcut_spell.target_type_of(tables:, row:) {
            Ok(target_type) ->
              Ok(#(spell4_id, target_mechanic.kind_of(target_type:)))
            Error(Nil) -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
    })
  let casters =
    list.filter(kinds, fn(found) { found.1 == target_mechanic.Caster })
  assert list.length(casters) > 3000
    as "the client's item spells are mostly cast on the user"
  list.each(kinds, fn(found) {
    let #(spell4_id, kind) = found
    let planned = shortcut_spell.planned_of(shortcuts:, spell4_id:)
    let refusal = shortcut_spell.item_refusal_of(shortcuts:, spell4_id:)
    case kind {
      target_mechanic.Caster ->
        case planned, refusal {
          Ok(Planned(..)), _ | Ok(CannotBePlanned(..)), Ok(_) -> Nil
          Ok(Aimed(..)), _
          | Ok(shortcut_spell.NoSpell4Row), _
          | Ok(CannotBePlanned(..)), Error(Nil)
          | Error(Nil), _
          ->
            panic as {
              "the item spell "
              <> int.to_string(spell4_id)
              <> " has no outcome: it is neither planned nor refused"
            }
        }
      target_mechanic.Targeted
      | target_mechanic.Ground
      | target_mechanic.Unread(..) -> {
        assert refusal == Error(Nil)
          as "a spell cast at a unit or a place has no refusal: it stays with the activate cast"
      }
    }
  })
  let caster_spells = set.from_list(list.map(casters, fn(found) { found.0 }))
  dict.each(activations.spells, fn(spell4_id, _) {
    case set.contains(caster_spells, spell4_id) {
      True -> Nil
      False -> {
        assert shortcut_spell.item_refusal_of(shortcuts:, spell4_id:)
          == Error(Nil)
          as "a spell the activate cast holds that is not cast on the user has no item refusal"
      }
    }
  })
}
