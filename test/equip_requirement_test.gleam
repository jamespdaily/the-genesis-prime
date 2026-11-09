//// Whether a character may wear an item (`genesis_prime/game/equip_requirement`).
//// Expected values come from these places.
//// - `0x1403b4710` (CheckEquipRequirements): the order of the checks and each
////   check's GenericError code, `GameLib.CodeEnumGenericError`: 39
////   Item_WrongRace, 40 Item_WrongClass, 41 Item_FailedProficiency, 42
////   Item_LevelToLow, 132 Item_WrongFaction, 144 Item_EquipPrereqFailed. Race and
////   class are masks of bit `id - 1`; the required level is Item2.requiredLevel,
////   or 1 when it is 0 or Item2.flags holds bit 0.
//// - `0x1403ca2b0` (HasItemProficiency): the character's item proficiencies must
////   hold the mask of the ItemProficiency row of the item's category.
//// - `Prerequisite.prerequisiteTypeId.10`, `.109`, `.19` and `.270`: the gender
////   (0 male, 1 female) and the world the equip prerequisites read, and the two
////   the server does not read, a tradeskill tier and a loyalty.
//// - The test character is the Engineer: class 2, whose
////   Class.startingItemProficiencies is 66 (bits 2 and 64), race Human (1),
////   faction 166 (Exile), gender 0, level 1, in world 870. The Item2 rows are the
////   client's own (roots of the fixture): 12769 (race mask 1, class mask 64), 1133
////   (class mask 4, a category whose proficiency is 8), 1229 (a category whose
////   proficiency is 4), 73672 (prerequisite 37283, in world 2979, and level 50),
////   50770 (required level 3), 12918 (required level 36 with flags bit 0), 90054
////   (prerequisite 18276, gender 1), 77689 (prerequisite 39240, a loyalty) and
////   12631 (its ItemSpecial 4463 holds prerequisite 11693, a tradeskill tier).

import equip_requirement_support
import fixture_tables
import genesis_prime/game/equip_requirement.{
  type Wearer, PrerequisiteNotRead, Refused, Wearable, Wearer,
}
import genesis_prime/table/id.{Item2Id}
import gleam/list
import owned_test
import planted_table.{Integer}

fn verdict(
  item2_id item2_id: Int,
  wearer wearer: Wearer,
) -> equip_requirement.Verdict {
  let assert Ok(verdict) =
    equip_requirement.check(
      tables: fixture_tables.shared(),
      item2_id: Item2Id(item2_id),
      wearer:,
    )
    as "the item's rows are in the tables"
  verdict
}

pub fn the_checks_run_in_the_clients_order_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each row: what it shows, the item, the wearer and the first failing check's
  // code, or Wearable for none.
  let rows = [
    // 0x1403b4710: race before class.
    #(
      "race before class",
      12_769,
      Wearer(..equip_requirement_support.engineer(), race_id: 3),
      Refused(code: 39),
    ),
    #("class", 12_769, equip_requirement_support.engineer(), Refused(code: 40)),
    // The class before the proficiency: 1133's category needs proficiency 8,
    // which the Engineer lacks too.
    #(
      "class before proficiency",
      1133,
      equip_requirement_support.engineer(),
      Refused(code: 40),
    ),
    #(
      "proficiency",
      1229,
      equip_requirement_support.engineer(),
      Refused(code: 41),
    ),
    // 73672 needs world 2979 by its prerequisite and level 50.
    #(
      "prerequisite before level",
      73_672,
      Wearer(..equip_requirement_support.engineer(), world_id: 870),
      Refused(code: 144),
    ),
    #(
      "level after prerequisite",
      73_672,
      Wearer(..equip_requirement_support.engineer(), world_id: 2979),
      Refused(code: 42),
    ),
    #(
      "level",
      50_770,
      Wearer(..equip_requirement_support.engineer(), level: 2),
      Refused(code: 42),
    ),
    #(
      "level reached",
      50_770,
      Wearer(..equip_requirement_support.engineer(), level: 3),
      Wearable,
    ),
    // 12918's requiredLevel is 36, but its flags hold bit 0, so it needs 1.
    #(
      "flags bit 0 sets level 1",
      12_918,
      equip_requirement_support.engineer(),
      Wearable,
    ),
    #(
      "no requirement",
      50_770,
      Wearer(..equip_requirement_support.engineer(), level: 50),
      Wearable,
    ),
  ]
  list.each(rows, fn(row) {
    let #(what, item2_id, wearer, expected) = row
    assert verdict(item2_id:, wearer:) == expected as what
  })
}

pub fn a_faction_other_than_the_items_is_refused_wrong_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  // No Item2 row of the client requires a faction (faction2IdRequired is 0 in
  // every row), so the chest piece 50770 is edited to require faction 167
  // (Dominion): the check is built from the client's code, which no row
  // exercises.
  use tables <- fixture_tables.changed(
    table: "Item2",
    id: fixture_tables.root(table: "Item2", id: 50_770),
    with: [#("faction2IdRequired", Integer(167))],
  )
  let check = fn(wearer) {
    let assert Ok(verdict) =
      equip_requirement.check(tables:, item2_id: Item2Id(50_770), wearer:)
      as "the rows are in the tables"
    verdict
  }
  assert check(
      Wearer(..equip_requirement_support.engineer(), faction_id: 166, level: 3),
    )
    == Refused(code: 132)
    as "0x1403b4710: a faction other than the item's is Item_WrongFaction"
  assert check(
      Wearer(..equip_requirement_support.engineer(), faction_id: 167, level: 3),
    )
    == Wearable
    as "the item's own faction passes, and level 3 reaches its required level"
}

pub fn an_equip_prerequisite_is_read_or_refused_and_logged_test() -> Nil {
  use <- owned_test.run(10_000)
  // 90054's prerequisite 18276 is Equal 1 on the gender (type 10): the player
  // unit's gender is the one 0x262's type 20 data carries, 0 male, 1 female.
  assert verdict(
      item2_id: 90_054,
      wearer: Wearer(..equip_requirement_support.engineer(), gender: 1),
    )
    == Wearable
    as "a female wearer passes the gender prerequisite"
  assert verdict(
      item2_id: 90_054,
      wearer: Wearer(..equip_requirement_support.engineer(), gender: 0),
    )
    == Refused(code: 144)
    as "a male wearer fails it: Item_EquipPrereqFailed"
  // The server reads no loyalty (type 270) or tradeskill tier (type 19): the
  // client would decide them, so the item is refused with 144 and the type is
  // named for the log, as the cast rule does with a condition it cannot read.
  assert verdict(item2_id: 77_689, wearer: equip_requirement_support.engineer())
    == PrerequisiteNotRead(prerequisite_type: 270)
    as "prerequisite 39240 is a loyalty"
  assert verdict(item2_id: 12_631, wearer: equip_requirement_support.engineer())
    == PrerequisiteNotRead(prerequisite_type: 19)
    as "the item's ItemSpecial 4463 holds a tradeskill tier prerequisite"
}
