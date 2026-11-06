//// The class innate in a loadout (`genesis_prime/game/loadout`), on the client's
//// tables. Expected values come from these places.
//// - `lua.ActionBarFrame.ActionBarInnate`: the innate button finds the class's
////   slot-0 active spell by its Spell4Base in the ability bag (`0x14077dfa0`), so
////   the bag holds it; the server's choice of its bag index is the one after the
////   level-1 abilities, 3 for every class.
//// - `opcode.0x19d`: the innate is in no action set, so the bar holds the three
////   SpellLevel abilities alone.
//// - The abilities (`SpellLevel.spell4Id`, `opcode.0x111.ability_bag`): Warrior
////   18309, 37968, 38017; Engineer 26468, 25473, 25635; Esper 19102, 19019, 19022;
////   Medic 38201, 16322, 26543; Stalker 23148, 23161, 23173; Spellslinger 27638,
////   20684, 20325. The innate bases are the Class rows' (`innate_test`).

import client_tables
import genesis_prime/game/innate.{Passive}
import genesis_prime/game/loadout
import genesis_prime/table/id.{ClassId, Spell4BaseId, Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import unitest

/// A class's id, its three level-1 abilities and its slot-0 innate's Spell4Base.
fn classes() -> List(#(Int, List(Int), Int)) {
  [
    #(1, [18_309, 37_968, 38_017], 30_828),
    #(2, [26_468, 25_473, 25_635], 31_779),
    #(3, [19_102, 19_019, 19_022], 38_012),
    #(4, [38_201, 16_322, 26_543], 46_615),
    #(5, [23_148, 23_161, 23_173], 30_075),
    #(7, [27_638, 20_684, 20_325], 31_213),
  ]
}

pub fn a_loadouts_bag_is_its_three_abilities_in_order_then_the_innate_and_the_bar_is_the_three_alone_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(classes(), fn(class) {
    let #(class_id, abilities, innate_base) = class
    list.each([166, 167], fn(faction) {
      let assert Ok(held) =
        loadout.of(tables:, class_id: ClassId(class_id), faction_id: faction)
        as "the client's tables hold a Novice set for each class and faction"
      assert held.abilities == list.map(abilities, Spell4BaseId)
        as {
          "opcode.0x19d: the bar of class "
          <> int.to_string(class_id)
          <> " holds the three SpellLevel abilities alone"
        }
      assert loadout.bag(loadout: held)
        == list.map(list.append(abilities, [innate_base]), Spell4BaseId)
        as {
          "0x14077dfa0: class "
          <> int.to_string(class_id)
          <> "'s bag is its three abilities, then the innate's Spell4Base at index 3"
        }
    })
  })
}

pub fn a_loadout_holds_the_innate_of_its_class_with_its_passive_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let held = fn(class_id) {
    let assert Ok(held) =
      loadout.of(tables:, class_id: ClassId(class_id), faction_id: 166)
      as "the client's tables hold a Novice set"
    held.innate
  }
  let assert Some(warrior) = held(1)
    as "Class row 1 names Stance: Onslaught as its first innate"
  assert warrior.active == Spell4Id(46_867)
  assert warrior.passive
    == Some(Passive(
      spell4_id: Spell4Id(44_926),
      spell4_base_id: Spell4BaseId(29_035),
    ))
    as "Class.spell4IdInnateAbilityPassive00: Warrior 44926"
  let assert Some(medic) = held(4) as "Class row 4 names Energize"
  assert medic.active == Spell4Id(69_450) && medic.passive == None
    as "Medic has no passive in slot 0"
}
