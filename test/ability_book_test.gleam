//// The abilities a character holds at a level (`genesis_prime/game/ability_book`), on the
//// client's committed rows. Expected values come from these places.
//// - `SpellLevel.spell4Id.no_prerequisite`: a class's abilities with no prerequisite, by
////   level; `table_rows -- SpellLevel prerequisiteId=0` gives the rows below: Warrior
////   (Class 1) 921 (level 4, Spell4Base 18359), 934 (5, 19778), 929, 933 and 944 (6, 37245,
////   39339, 18578); Medic (Class 4) 614 (4, 26038), 1087 (5, 25692), 1191, 1194 and 1221
////   (6, 25530, 25579, 38210); Spellslinger (Class 7) 1012 (4, 20718), 1270 (5, 30666),
////   1144, 1148 and 1155 (6, 23441, 23479, 23012).
//// - `0x1403bb040`: the client's own availability check asks the rows of the player's
////   class for `characterLevel` at or below the unit's level, with the prerequisite passed.
//// - The innate sits at the index the three level-1 abilities number (3): Class
////   `spell4IdInnateAbilityActive00` (Warrior 30828, Medic 46615, Spellslinger 31213).

import ability_book_support as support
import client_tables
import fixture_tables
import genesis_prime/game/ability_book
import genesis_prime/game/loadout
import genesis_prime/table/id.{type Spell4BaseId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import owned_test
import planted_table.{Integer}
import unitest

/// A class, its innate's Spell4Base, and the abilities after the innate at the levels the
/// committed rows hold: (level, the bases the bag holds after the innate).
type Case {
  Case(class_id: Int, level: Int, after_the_innate: List(Int), why: String)
}

fn cases() -> List(Case) {
  [
    Case(1, 1, [], "level 1 holds the level-1 abilities and the innate only"),
    Case(1, 3, [], "no row of any class falls in levels 2 and 3"),
    Case(1, 4, [18_359], "SpellLevel 921 is at level 4"),
    Case(
      1,
      6,
      [18_359, 19_778, 37_245, 39_339, 18_578],
      "by level, then by SpellLevel id: 929, 933, 944 are all level 6",
    ),
    Case(
      4,
      6,
      [26_038, 25_692, 25_530, 25_579, 38_210],
      "Medic 614, 1087, then 1191, 1194, 1221",
    ),
    Case(
      7,
      6,
      [20_718, 30_666, 23_441, 23_479, 23_012],
      "Spellslinger 1012, 1270, then 1144, 1148, 1155",
    ),
  ]
}

fn innate_of(class_id class_id: Int) -> Int {
  case class_id {
    1 -> 30_828
    4 -> 46_615
    _ -> 31_213
  }
}

fn values(bases bases: List(Spell4BaseId)) -> List(Int) {
  list.map(bases, fn(base) { base.value })
}

pub fn the_bag_at_a_level_is_the_bar_the_innate_then_the_rows_up_to_the_level_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  list.each(cases(), fn(case_) {
    let set = support.loadout_of(tables:, class_id: case_.class_id)
    let bag = values(bases: ability_book.bag(loadout: set, level: case_.level))
    assert list.drop(bag, 3)
      == [innate_of(class_id: case_.class_id), ..case_.after_the_innate]
      as case_.why
    assert list.length(bag) == 4 + list.length(case_.after_the_innate)
      as case_.why
  })
}

pub fn a_row_with_a_prerequisite_or_above_the_level_is_never_in_the_bag_test() -> Nil {
  use <- owned_test.run(10_000)
  // A copy of Warrior's SpellLevel 929 (level 6, base 37245) that names a prerequisite and
  // a level the character has passed: the client's own check gates it by the prerequisite
  // (0x1403bb040), and a level's grant holds no row with one.
  use tables <- fixture_tables.added(
    table: "SpellLevel",
    copy_of: 929,
    id: 99_001,
    with: [#("prerequisiteId", Integer(227)), #("characterLevel", Integer(4))],
  )
  let set = support.loadout_of(tables:, class_id: 1)
  assert values(bases: ability_book.bag(loadout: set, level: 50))
    == [18_309, 37_968, 38_017, 30_828, 18_359, 19_778, 37_245, 39_339, 18_578]
    as "the Warrior's bag at level 50 holds 37245 once, from SpellLevel 929, and nothing from the row with a prerequisite"
  assert values(bases: ability_book.granted(
      loadout: set,
      from_level: 1,
      to_level: 4,
    ))
    == [18_359]
    as "the rise to level 4 grants 921 only: the planted row is at level 4 but has a prerequisite, and 934 is at level 5, above the level"
  assert values(bases: ability_book.bag(loadout: set, level: 4))
    == [18_309, 37_968, 38_017, 30_828, 18_359]
    as "a Warrior at level 4 holds no ability of level 5 or above (0x1403bb040 gates a row by its characterLevel)"
}

pub fn the_bag_at_a_higher_level_is_the_bag_at_a_lower_one_plus_what_the_rise_grants_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each([1, 4, 7], fn(class_id) {
    let set = support.loadout_of(tables:, class_id:)
    list.each(
      int.range(from: 1, to: 51, with: [], run: fn(all, level) {
        [level, ..all]
      }),
      fn(from_level) {
        assert ability_book.granted(
            loadout: set,
            from_level:,
            to_level: from_level,
          )
          == []
          as "a rise to the same level grants nothing"
        list.each(
          int.range(from: from_level, to: 51, with: [], run: fn(all, level) {
            [level, ..all]
          }),
          fn(to_level) {
            assert ability_book.bag(loadout: set, level: to_level)
              == list.append(
                ability_book.bag(loadout: set, level: from_level),
                ability_book.granted(loadout: set, from_level:, to_level:),
              )
              as {
                "class "
                <> int.to_string(class_id)
                <> ": the bag at level "
                <> int.to_string(to_level)
                <> " is the bag at "
                <> int.to_string(from_level)
                <> " and what the rise grants, so a relog and a session hold one order"
              }
          },
        )
      },
    )
  })
}

pub fn a_character_of_any_class_at_level_50_holds_28_bag_entries_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // SpellLevel.spell4Id.no_prerequisite: each class has 3 rows at level 1 and 24 above it,
  // none naming the class's innate base, and no two sharing a base.
  list.each([1, 2, 3, 4, 5, 7], fn(class_id) {
    let held = support.loadout_of(tables:, class_id:)
    let bag = values(bases: ability_book.bag(loadout: held, level: 50))
    assert list.length(bag) == 28
      as "3 level-1 abilities, the innate, and 24 abilities above level 1"
    assert list.length(list.unique(bag)) == 28
      as "no two bag items share a base, which the client finds the spell by (0x14077dfa0)"
    assert option.map(held.innate, fn(innate) { innate.active_base.value })
      == option.from_result(list.first(list.drop(bag, 3)))
      as "the innate stays at index 3 for every level"
  })
}

/// The alternates the Spell4 rows name for the bag's abilities: the base of the Spell4 that
/// each bag ability's tier 1 row names as its mechanic alternate
/// (`Spell4.spell4IdMechanicAlternateSpell`), read from the rows and not from the plans.
fn named_alternates(
  tables tables: table_store.Tables,
  bag bag: List(Spell4BaseId),
) -> List(Int) {
  list.filter_map(bag, fn(base) {
    use row <- result.try(
      list.find(spell4.all(tables), fn(row) {
        spell4.spell4_base_id_base_spell(row) == base && row.tier_index == 1
      }),
    )
    case spell4.spell4_id_mechanic_alternate_spell(row).value {
      0 -> Error(Nil)
      named -> {
        use alternate <- result.map(spell4.get(tables:, id: id.Spell4Id(named)))
        spell4.spell4_base_id_base_spell(alternate).value
      }
    }
  })
}

pub fn the_book_at_a_level_holds_the_bag_and_the_alternates_the_plans_add_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // Spell4Base 52215 is the alternate of Spellslinger 27638's tier 1 (`table_rows
  // Spell4Base 52215`); the book lists it after the whole bag.
  let spellslinger = support.loadout_of(tables:, class_id: 7)
  list.each([1, 4, 10], fn(level) {
    let bag = ability_book.bag(loadout: spellslinger, level:)
    let book = ability_book.book(tables:, loadout: spellslinger, level:)
    assert list.take(book, list.length(bag)) == bag
      as {
        "level "
        <> int.to_string(level)
        <> ": the book starts with each bag id once, in bag order"
      }
    assert list.contains(
      list.drop(book, list.length(bag)),
      id.Spell4BaseId(52_215),
    )
      as {
        "level "
        <> int.to_string(level)
        <> ": Spell4Base 52215, the alternate of 27638's tier 1, is in the book"
      }
  })
  // Every class and faction at level 50: each bag id is in the book once, and each extra
  // is an alternate a bag id's tier 1 row names.
  list.each([1, 2, 3, 4, 5, 7], fn(class_id) {
    list.each([166, 167], fn(faction_id) {
      let assert Ok(held) =
        loadout.of(tables:, class_id: id.ClassId(class_id), faction_id:)
        as "every class has a loadout in both factions"
      let bag = ability_book.bag(loadout: held, level: 50)
      let book = ability_book.book(tables:, loadout: held, level: 50)
      let extras = list.drop(book, list.length(bag))
      let named = named_alternates(tables:, bag:)
      let counts =
        "class "
        <> int.to_string(class_id)
        <> ", faction "
        <> int.to_string(faction_id)
        <> ": "
        <> int.to_string(list.length(bag))
        <> " bag ids, "
        <> int.to_string(list.length(extras))
        <> " alternates in the book, "
        <> int.to_string(list.length(named))
        <> " named by the rows"
      assert list.take(book, list.length(bag)) == bag
        as { counts <> ": the book starts with the bag" }
      assert list.length(list.unique(book)) == list.length(book)
        as { counts <> ": no id twice" }
      list.each(extras, fn(extra) {
        assert list.contains(named, extra.value)
          as {
            counts
            <> ": Spell4Base "
            <> int.to_string(extra.value)
            <> " is no bag id's alternate"
          }
      })
    })
  })
}
