//// The ability book on a level rise (`genesis_prime/game/connection/experience`,
//// `genesis_prime/game/ability_book`), on the game connection and the client's committed
//// rows. Expected values come from these places.
//// - `opcode.0x111.ability_level_up`: an ability is added by a 0x0111 of location 4 whose
////   bag index is the slot a press names; reason 49 raises no event, as the entry's does.
////   The next slot is the one after the bag the old level held, which is the entry's
////   order for the new level, so a relog agrees.
//// - `opcode.0x1a0`: the book entry of a base and the alternate it names, tier 1 in each of
////   the four action sets; 0x017B cannot add an entry for a base the book lacks.
//// - `0x1403bb040`: the client's own availability check of an ability reads the unit's
////   level, so 0x0938 stat 10 comes before the first 0x0111.
//// - `XpPerLevel.minXpForLevel`: level 4 from 2860, level 5 from 4320 and level 6 from 6280;
////   a quest of the tests' tables gives 1055 experience (`game_connection_quest_turn_in_test`).
//// - `SpellLevel.spell4Id.no_prerequisite`: the rows and bases of `ability_book_test`; the
////   Medic's 614 (Fissure, Spell4Base 26038), 1191 (25530) and 1194 (25579) and the Warrior's
////   921 (18359) have no plan (`spell_plan.unplanned`; issue #1003 builds them), the others named here do.
//// - `opcode.0x7fc`: a press of a bag slot whose base has no plan is refused with result 4,
////   the unknown spell (`0x14039a040`).

import ability_book_support as support
import character_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{FromMap, FromStore}
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/message/cast_result.{SpellUnknown}
import genesis_prime/step
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import quest_turn_in_support
import quest_walker_support
import world_entry_support

/// A rise of a class from one level to another, the 0x0111 the rise writes (bag index and
/// base) and the bases the one 0x01A0 holds.
type Rise {
  Rise(
    class_id: Int,
    from: Int,
    to: Int,
    ids: List(Int),
    added: List(#(Int, Int)),
    book: List(Int),
    why: String,
  )
}

fn rises() -> List(Rise) {
  [
    Rise(
      4,
      3,
      4,
      [0x01AC, 0x0938, 0x0111, 0x01A0, 0x093A],
      [#(4, 26_038)],
      [26_038],
      "Medic: SpellLevel 614 is the level 4 row, slot 4 after the bag of 4 items",
    ),
    Rise(
      7,
      3,
      4,
      [0x01AC, 0x0938, 0x0111, 0x01A0, 0x093A],
      [#(4, 20_718)],
      [20_718, 54_909],
      "Spellslinger: 1012's base and the alternate Spell4 34756 names, base 54909, in the one 0x01A0",
    ),
    Rise(
      4,
      5,
      6,
      [0x01AC, 0x0938, 0x0111, 0x0111, 0x0111, 0x01A0, 0x093A],
      [#(6, 25_530), #(7, 25_579), #(8, 38_210)],
      [25_530, 25_579, 38_210],
      "Medic 5 to 6: 1191, 1194 and 1221 by SpellLevel id, slots 6 to 8 after the 6 items of level 5",
    ),
    Rise(
      1,
      3,
      5,
      [0x01AC, 0x0938, 0x0111, 0x0111, 0x01A0, 0x093A],
      [#(4, 18_359), #(5, 19_778)],
      [18_359, 19_778],
      "Warrior 3 to 5: two levels in one gain grant both, slots 4 and 5, one 0x01A0",
    ),
    Rise(
      2,
      1,
      2,
      [0x01AC, 0x0938, 0x093A],
      [],
      [],
      "Engineer 1 to 2: no row falls at level 2, so nothing is added and no 0x01A0 is sent",
    ),
  ]
}

pub fn a_level_rise_writes_the_level_the_new_items_and_one_book_message_in_order_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(rises(), fn(rise) {
    let #(_, taken) =
      support.level_up(class_id: rise.class_id, from: rise.from, to: rise.to)
    let frames = support.written(taken:)
    assert connection_support.written_ids(taken) == rise.ids as rise.why
    assert list.map(support.added_in(frames:), fn(added) {
        #(added.bag_index, added.base)
      })
      == rise.added
      as rise.why
    assert list.all(support.added_in(frames:), fn(added) { added.reason == 49 })
      as "opcode.0x111.ability_level_up: reason 49, as the entry's"
    assert support.tiers_in(frames:) == support.tiers_of(bases: rise.book)
      as rise.why
    // The unit's level reaches the client before the first ability is added: the client's own
    // availability check of the new ability reads it (0x1403bb040).
    assert list.take(connection_support.written_ids(taken), 2)
      == [0x01AC, 0x0938]
      as "0x0938 stat 10 comes before the first 0x0111"
  })
}

pub fn a_quest_reward_that_levels_the_player_grants_its_abilities_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 10520 gives 1055 experience (game_connection_quest_turn_in_test); a Medic of level 3
  // holding 2000 of its 1710 to 2859 has 3055 afterwards, which is level 4 (XpPerLevel).
  let tables = character_tables.shared()
  let #(accepted, _) =
    connection_support.accepted(
      Settings(..connection_support.settings(), tables:),
    )
  let #(state, taken) =
    connection_support.joining_holding(
      in_character_select: connection_support.in_select_from(accepted),
      character: Character(
        ..connection_support.world_character(),
        class_id: ClassId(4),
        faction_id: 166,
        level: 3,
      ),
      saved_health: None,
      saved_experience: Some(2000),
      quests: [quest_turn_in_support.achieved(quest_id: 10_520)],
    )
  let state =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(connection_support.map_answer(taken))),
    ).0
  let state =
    connection_support.feed(
      state:,
      event: quest_walker_support.walker_appears(),
    ).0
  let #(state, taken) =
    connection_support.read(
      state:,
      bytes: connection_support.world_message(
        message_id: 0x035D,
        body: quest_turn_in_support.body(scene: quest_turn_in_support.scene(
          quest_id: 10_520,
        )),
      ),
    )
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(store.ForItems(store.TurnedIn(credits: 0, made: []))),
      ),
    )
  assert connection_support.written_ids(answered)
    == [0x01AC, 0x0938, 0x0111, 0x01A0, 0x093A, 0x035C]
    as "the experience, the level it made, the ability that level grants and its book entry, the properties, then the quest's state last"
  assert list.map(
      support.added_in(frames: support.written(taken: answered)),
      fn(added) { #(added.bag_index, added.base) },
    )
    == [#(4, 26_038)]
    as "the quest path shares the rise with the kill: SpellLevel 614's base at slot 4"
}

pub fn a_second_gain_grants_only_the_levels_it_crosses_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Medic rises 3 to 4 on a kill. A kill of a level 32 creature, whose XpPerLevel row
  // gives 24771 x 0.25 x 0.2 x 1.4 = 1734 experience (the multiplier of a gap of 4 or more),
  // takes 2859 + the first kill's gain past 4320, which is level 5, and not past 6280.
  let #(state, _) = support.level_up(class_id: 4, from: 3, to: 4)
  let #(_, taken) = support.another_kill(state:, level: 32)
  let frames = support.written(taken:)
  assert connection_support.written_ids(taken)
    == [0x01AC, 0x0938, 0x0111, 0x01A0, 0x093A]
    as "one ability and one book entry for the one level crossed"
  assert list.map(support.added_in(frames:), fn(added) {
      #(added.bag_index, added.base)
    })
    == [#(5, 25_692)]
    as "SpellLevel 1087 is the level 5 row and goes in slot 5, the slot after the first rise's"
  assert support.tiers_in(frames:) == support.tiers_of(bases: [25_692])
    as "nothing the first rise sent is sent again"
}

pub fn the_new_ability_is_in_the_casters_bag_and_the_ability_known_prerequisite_in_the_same_session_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let held = fn(level) {
    let #(_, entered) =
      world_entry_support.entry(
        tables:,
        character: world_entry_support.character(class: 7, faction: 166, level:),
      )
    #(
      casting.caster_of(tables:, entered:),
      prerequisite_player.checker_of(entered:),
    )
  }
  let #(before, before_checker) = held(3)
  let #(after, after_checker) = held(4)
  assert list.drop(before.abilities, 4) == []
    as "before the rise the bag holds the three abilities and the innate"
  assert list.drop(after.abilities, 4) == [Spell4BaseId(20_718)]
    as "after it, the level 4 ability is at bag index 4 (SpellLevel 1012)"
  assert list.contains(before.book, Spell4BaseId(20_718)) == False
    && list.contains(before_checker.book, Spell4BaseId(20_718)) == False
    as "the book held neither the base nor its alternate before"
  assert list.contains(after.book, Spell4BaseId(20_718))
    && list.contains(after.book, Spell4BaseId(54_909))
    && list.contains(after_checker.book, Spell4BaseId(20_718))
    as "the cast rule's book holds the base and its alternate, and the ability-known prerequisite's holds the base"
  // The press on the connection: the Spellslinger's slot 4 names no ability before the rise
  // and a planned one after it, which the rule answers as it answers any plan-built ability's
  // press (the rule's own cases are in the cast tests); the rise is the connection's own.
  let state = support.entered_at(class_id: 7, level: 3, saved_experience: 0)
  assert connection_support.refusal_results(taken: support.pressed(
      state:,
      bag_index: 4,
      ms: 1000,
    ))
    == [SpellUnknown]
    as "opcode.0x7fc: slot 4 holds nothing at level 3, so the press is refused unknown"
  let #(state, _) = support.level_up(class_id: 7, from: 3, to: 4)
  assert connection_support.written_ids(support.pressed(
      state:,
      bag_index: 4,
      ms: 1000,
    ))
    == [0x07FD]
    as "opcode.0x7fd: after the rise the press at slot 4 starts the plan-built cast, which the caster is told with its start"
  Nil
}

pub fn an_ability_with_no_plan_is_granted_and_its_press_is_refused_unknown_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Medic's 5 to 6 gives 25530 at slot 6 (SpellLevel 1191) and 25579 at slot 7 (1194),
  // which have no plan, and 38210 at slot 8 (1221, Emission), which has one.
  let assert Ok(unplanned) =
    spell_plan.unplanned(
      tables: character_tables.shared(),
      area_checked: spell_area.checker,
    )
    as "the plans build"
  // The base, the Spell4 row the plan refuses, and its own refusal.
  let no_plan = [
    #(
      25_530,
      41_333,
      spell_plan.FriendlyAreaNotRead(41_333, 92_693, 5),
      "Mending Probes hits no foes and has an effect aimed by flags 5, the caster and the area, a friendly spell's area that finds allies, which the server does not read",
    ),
    #(
      25_579,
      41_382,
      spell_plan.AreaNotBuilt(
        41_382,
        "the Spell4 row 41382 has an area row that selects in order 5, which is not built (a player's ability takes Closest, 1; a creature's special 1 to 3)",
      ),
      "Crisis Wave's area row selects in an order the server does not build",
    ),
  ]
  list.each(no_plan, fn(row) {
    let #(_, spell4_id, error, why) = row
    assert list.contains(unplanned, spell_plan.Unplanned(spell4_id:, error:))
      as {
        "the plan refuses Spell4 " <> int.to_string(spell4_id) <> ": " <> why
      }
  })
  let #(state, taken) = support.level_up(class_id: 4, from: 5, to: 6)
  assert list.map(support.added_in(frames: support.written(taken:)), fn(added) {
      added.bag_index
    })
    == [6, 7, 8]
    as "all three are granted, the unplanned ones too: the table says the player holds them"
  assert support.tiers_in(frames: support.written(taken:))
    == support.tiers_of(
      bases: list.append(list.map(no_plan, fn(row) { row.0 }), [38_210]),
    )
    as "and their book entry is sent"
  list.each([6, 7], fn(bag_index) {
    assert connection_support.refusal_results(taken: support.pressed(
        state:,
        bag_index:,
        ms: 1000,
      ))
      == [SpellUnknown]
      as {
        "opcode.0x7fc: the press of slot "
        <> int.to_string(bag_index)
        <> " has no plan, so it is refused unknown"
      }
  })
  assert connection_support.refusal_results(taken: support.pressed(
      state:,
      bag_index: 8,
      ms: 1000,
    ))
    == []
    as "opcode.0x7fc: the press of slot 8 has a plan, so it is not refused unknown; its Spell4 58841 costs 15 Focus (innateCostType0 15), which the Medic holds at its pool of 1000 (class_resource, a guess), so the cast is accepted"
}
