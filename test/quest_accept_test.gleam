//// A player's request to accept a quest, 0x035B, and to retry a botched one, 0x0365
//// (`genesis_prime/game/quest`). Expected values come from these places, and never from
//// the helpers that build the input.
//// - `CanAcceptQuest` (`0x140552550`) checks in this order, and the first that fails
////   gives the code the client shows: 11 not mentioned, 2 already held, 14 faction, 4
////   race, 5 class, 10 episode, 3 level and 8 prerequisite quests (one check when
////   Quest2.preq_flags has bit 2), 9 exclusions, 6 reputation, 7 prerequisite item, 12
////   prerequisite, 13 path, 15 log full, 16 periodic, 17 contract. The server does not
////   read 6, the per-item counter of 7, a prerequisite type it lacks, a periodic draw and
////   17, and says so (`NotRead`) where the client would decide.
//// - `client-facts opcode.0x35b`: the dialog's accept sends location 300 and bag index
////   0xFFFFFFFF; any other place is the item the quest came from, whose Item2
////   `quest2IdActivation` is the quest (Item2 4861 starts quest 2417). `opcode.0x365`:
////   a retry carries only the quest and the client sends it only for a botched one
////   (state 4), and a botched quest goes out as a retry only. The answer is 0x35C
////   {quest, state 1, objective 0}.
//// - The Faction2 ids are Exile 167 and Dominion 166; Quest2.questPlayerFactionEnum is 0
////   Exile, 1 Dominion, 2 either. The active list holds GameFormula 655's dataint0
////   quests, 40 in the client's row, and contracts (Quest2 flags 0x80000) do not count.
//// - The quests used here are rows of the committed fixture (`roots.tsv`): 1806 has no
////   condition at all; 1872 needs a mention (flags 0x404); 2989 is for Dominion and 2545
////   for Exile; 5259 is the quest its episode 411 holds back until 4791 is not
////   completed; 3918 and 5859 and 9299 name prerequisite quests; 3195 names exclusions
////   3215 and 3216; 3243 needs reputation; 3627 and 9793 need an item; 3678, 4943 and
////   5084 name a prerequisite; 4004 and 4940 need a path; 9578, 9713 and 1857 repeat and
////   9880 is a contract.
//// - Dorian Walker (Creature2 74812) gives quest 10528, which needs 10520 completed.

import character_tables
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/interaction
import genesis_prime/game/prerequisite.{Factions, Player}
import genesis_prime/game/quest.{
  type Asker, type Taken, type Verdict, Acceptable, Asker, NotRead, Refused,
}
import genesis_prime/game/quest_log
import genesis_prime/game/shown.{type Picture}
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/quest_retry.{QuestRetry}
import genesis_prime/step.{LogDebug, LogWarning}
import genesis_prime/store.{
  type HeldItem, type QuestRow, ActiveQuest, HeldItem, QuestRow,
}
import genesis_prime/table/id.{Item2Id, Quest2Id, RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2, Quest2}
import genesis_prime/world_map/creature_life.{Hostile}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import prerequisite_support
import quest_support
import quest_walker_support
import simple_unit_support

const exile = 167

const dominion = 166

fn tables() -> table_store.Tables {
  character_tables.shared()
}

fn row(quest_id: Int) -> Quest2 {
  let assert Ok(row) = quest2.get(tables: tables(), id: Quest2Id(quest_id))
    as "the fixture holds the quest"
  row
}

/// The saved row of a quest the player holds accepted: one progress value for each
/// objective the Quest2 row names.
fn accepted(quest_id: Int) -> QuestRow {
  quest_support.untouched(quest_id:)
}

/// A level 20 Exile of race 3, class 5 and path 1 whose log holds these rows.
fn asker(log log: List(QuestRow)) -> Asker {
  Asker(
    player: prerequisite_support.player(),
    factions: Factions(current: exile, base: exile),
    log: quest_support.log_of(rows: log),
    items: [],
  )
}

fn dominion_asker(log log: List(QuestRow)) -> Asker {
  Asker(..asker(log:), factions: Factions(current: dominion, base: dominion))
}

fn at_level(asker: Asker, level: Int) -> Asker {
  Asker(..asker, player: Player(..asker.player, level:))
}

fn on_path(asker: Asker, path: Int) -> Asker {
  Asker(..asker, player: Player(..asker.player, path:))
}

fn holding(
  asker asker: Asker,
  item item2_id: Int,
  location location: Int,
) -> Asker {
  Asker(..asker, items: [
    item(item2_id:, location:, bag_index: 0),
  ])
}

fn item(
  item2_id item2_id: Int,
  location location: Int,
  bag_index bag_index: Int,
) -> HeldItem {
  HeldItem(
    item_guid: 1,
    item2_id: Item2Id(item2_id),
    location:,
    bag_index:,
    stack_count: 1,
    random_stats: 0,
  )
}

fn verdict(quest target: Quest2, asker asker: Asker) -> Verdict {
  let assert Ok(verdict) =
    quest.can_accept(
      tables: tables(),
      quest: target,
      asker:,
      mask: quest.every_check,
    )
    as "the fixture holds every row the checks read"
  verdict
}

fn verdict_of(quest_id: Int, asker: Asker) -> Verdict {
  verdict(quest: row(quest_id), asker:)
}

pub fn accept_answers_accepted_and_adds_a_tracked_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  let held =
    Asker(..asker(log: []), items: [
      item(item2_id: 4861, location: 1, bag_index: 0),
    ])
  let taken =
    took(
      message: quest.Accept,
      body: accept_body(location: 1, bag_index: 0, quest_id: 2417),
      asker: held,
    )
  assert taken.effects
    == [quest.SendState(quest_id: 2417, state: 1, objective_id: 0)]
    as "0x35C {quest 2417, state 1, objective 0}, the answer the client waits for"
  assert quest_log.rows(log: taken.log, now_ms: 0)
    == [
      QuestRow(
        quest_id: 2417,
        state: 1,
        completed_at: None,
        active: Some(
          ActiveQuest(
            placeholder_objective_id: 0,
            tracked: True,
            done_mask: 0,
            progress: [],
            quest_ms_left: 0,
            objective_ms_left: [],
            kill_mask: [0, 0, 0, 0, 0, 0],
          ),
        ),
      ),
    ]
    as "an Accepted entry the client tracks (a new entry's flag word is 2, 0x1405fbdc0), quest 2417 having no objective"
  assert taken.logged == set.new()
    as "nothing is logged for a request the client sends"
}

pub fn accept_refuses_a_quest_already_accepted_or_achieved_test() -> Nil {
  use <- owned_test.run(10_000)
  assert verdict_of(1806, asker(log: [accepted(1806)])) == Refused(code: 2)
    as "check 2: a quest in the active list in state 1"
  let achieved =
    quest_support.active(
      quest_id: 1806,
      state: 2,
      placeholder: 0,
      tracked: False,
      done_mask: 1,
      progress: [1],
    )
  assert verdict_of(1806, asker(log: [achieved])) == Refused(code: 2)
    as "check 2: state 2, achieved and not yet handed in"
  assert verdict_of(1806, asker(log: [])) == Acceptable
    as "the same quest with no record passes every check"
}

pub fn accept_takes_a_quest_held_in_the_side_list_test() -> Nil {
  use <- owned_test.run(10_000)
  // Check 2 refuses only the states 1 to 3; the second list holds 4 to 7, and the
  // accepted entry replaces the held one. A Botched entry (4) is not taken by an
  // accept: the client sends it as a retry (see the would-not-send test).
  list.each([5, 6, 7], fn(state) {
    let held =
      Asker(..asker(log: [quest_support.known(2417, state)]), items: [
        item(item2_id: 4861, location: 1, bag_index: 0),
      ])
    let taken =
      took(
        message: quest.Accept,
        body: accept_body(location: 1, bag_index: 0, quest_id: 2417),
        asker: held,
      )
    assert taken.effects
      == [quest.SendState(quest_id: 2417, state: 1, objective_id: 0)]
      as "a quest held in state 5 to 7 is accepted"
    assert list.map(quest_log.rows(log: taken.log, now_ms: 0), fn(row) {
        row.state
      })
      == [1]
      as "one entry, now Accepted"
  })
}

pub fn accept_takes_a_completed_quest_again_only_when_it_repeats_test() -> Nil {
  use <- owned_test.run(10_000)
  let done = fn(quest_id) {
    asker(log: [quest_support.completed(quest_id:, at: 1000)])
  }
  assert verdict_of(1857, done(1857)) == Acceptable
    as "1857 is daily (questRepeatPeriodEnum 1)"
  assert verdict_of(3555, done(3555)) == Acceptable
    as "3555 has flags 0x20, the repeat flag"
  assert verdict_of(2347, done(2347)) == Refused(code: 2)
    as "2347 is one-time: no flag, no period"
}

pub fn accept_refuses_an_unmentioned_communicator_quest_test() -> Nil {
  use <- owned_test.run(10_000)
  assert verdict_of(1872, asker(log: [])) == Refused(code: 11)
    as "1872 has flags 0x404: the mention bit, and no state of 4 to 7"
  assert verdict_of(1872, asker(log: [quest_support.known(1872, 5)]))
    == Acceptable
    as "a Mentioned entry lets it through"
}

pub fn accept_refuses_a_quest_for_the_other_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  assert verdict_of(2989, asker(log: [])) == Refused(code: 14)
    as "2989 is for Dominion (enum 1), the asker is Exile 167"
  assert verdict_of(2989, dominion_asker(log: [])) == Acceptable
  assert verdict_of(2545, dominion_asker(log: [])) == Refused(code: 14)
    as "2545 is for Exile (enum 0), the asker is Dominion 166"
  assert verdict_of(2545, asker(log: [])) == Acceptable
  assert verdict(
      quest: Quest2(..row(1806), quest_player_faction_enum: 3),
      asker: asker(log: []),
    )
    == Refused(code: 14)
    as "an enum of 3 or more is refused for either faction"
}

pub fn accept_refuses_another_race_test() -> Nil {
  use <- owned_test.run(10_000)
  // No client row has a race condition, so a row is made with one.
  let needs_race_1 = Quest2(..row(1806), preq_race: 1)
  assert verdict(quest: needs_race_1, asker: asker(log: [])) == Refused(code: 4)
    as "the asker is race 3"
  let needs_race_3 = Quest2(..row(1806), preq_race: 3)
  assert verdict(quest: needs_race_3, asker: asker(log: [])) == Acceptable
}

pub fn accept_refuses_another_class_test() -> Nil {
  use <- owned_test.run(10_000)
  // No client row has a class condition either.
  let needs_class_1 = Quest2(..row(1806), preq_class: 1)
  assert verdict(quest: needs_class_1, asker: asker(log: []))
    == Refused(code: 5)
    as "the asker is class 5"
  let needs_class_5 = Quest2(..row(1806), preq_class: 5)
  assert verdict(quest: needs_class_5, asker: asker(log: [])) == Acceptable
}

pub fn accept_refuses_a_quest_its_episode_holds_back_test() -> Nil {
  use <- owned_test.run(10_000)
  // 5259 is in episode 411 on a row flagged to leave it out of the order; the one other
  // member is 4791. The quest needs a mention (flags 0x404), so the log holds one.
  let mentioned = quest_support.known(5259, 5)
  assert verdict_of(
      5259,
      asker(log: [mentioned, quest_support.completed(4791, at: 1000)]),
    )
    == Refused(code: 10)
    as "episode 411 is not open and every member that counts is completed"
  assert verdict_of(5259, asker(log: [mentioned])) == Acceptable
    as "4791 still to do lets the episode through"
}

pub fn accept_refuses_below_the_quest_level_test() -> Nil {
  use <- owned_test.run(10_000)
  assert verdict_of(2575, at_level(asker(log: []), 39)) == Refused(code: 3)
    as "2575's preq_level is 40"
  assert verdict_of(2575, at_level(asker(log: []), 40)) == Acceptable
}

pub fn accept_joins_level_and_prerequisite_quests_with_preq_flags_2_test() -> Nil {
  use <- owned_test.run(10_000)
  // 3918: preq_level 11, preq_flags 2, preq_quest0 4294.
  let low = at_level(asker(log: []), 10)
  assert verdict_of(3918, low) == Refused(code: 3)
    as "level 10 and the quest not completed: both fail, one check, the level's code"
  assert verdict_of(
      3918,
      at_level(asker(log: [quest_support.completed(4294, at: 1000)]), 10),
    )
    == Acceptable
    as "the joined check refuses only when both fail"
  assert verdict_of(3918, asker(log: [])) == Acceptable
    as "level 20 meets the level, so 4294 is not needed"
  assert verdict(
      quest: Quest2(..row(3918), preq_flags: 0),
      asker: asker(log: []),
    )
    == Refused(code: 8)
    as "without bit 2 the quest check stands alone"
}

pub fn the_level_and_quest_checks_each_run_on_their_own_mask_bit_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x140552550` tests bit 1 (level, code 3) and bit 6 (prerequisite quests, code 8)
  // apart and joins them only for preq_flags bit 2 with both bits asked. 3918 has
  // preq_level 11, preq_flags 2 and preq_quest0 4294; 2575 has preq_level 40 alone.
  let verdict_under = fn(mask, quest_id, asker) {
    let assert Ok(verdict) =
      quest.can_accept(tables: tables(), quest: row(quest_id), asker:, mask:)
      as "the fixture holds every row the checks read"
    verdict
  }
  let without_level = int.bitwise_and(quest.every_check, int.bitwise_not(0x2))
  let without_quests = int.bitwise_and(quest.every_check, int.bitwise_not(0x40))
  let low = at_level(asker(log: []), 10)
  assert verdict_under(without_level, 2575, asker(log: [])) == Acceptable
    as "a mask without bit 1 does not refuse a quest of level 40 for a level 20 player"
  assert verdict_under(without_level, 3918, low) == Refused(code: 8)
    as "without bit 1 the joined check does not run, so the quest check stands alone"
  assert verdict_under(
      without_level,
      3918,
      at_level(asker(log: [quest_support.completed(4294, at: 1000)]), 10),
    )
    == Acceptable
    as "without bit 1 the level is not asked, so a met prerequisite quest passes"
  assert verdict_under(without_quests, 3918, low) == Refused(code: 3)
    as "without bit 6 the level stands alone"
  assert verdict_under(quest.every_check, 3918, low) == Refused(code: 3)
    as "with both bits the joined check refuses with the level's code"
}

pub fn accept_needs_prerequisite_quests_all_or_any_test() -> Nil {
  use <- owned_test.run(10_000)
  let done = fn(ids) {
    list.map(ids, fn(id) { quest_support.completed(quest_id: id, at: 1000) })
  }
  // 5859: preq_quest0 5857 and preq_quest01 6789, no flag: all.
  assert verdict_of(5859, dominion_asker(log: done([5857, 6789]))) == Acceptable
  assert verdict_of(5859, dominion_asker(log: done([5857]))) == Refused(code: 8)
    as "one of two is not all"
  assert verdict_of(5859, dominion_asker(log: [])) == Refused(code: 8)
  // 9299: preq_flags 1, preq_quest0 9428 and preq_quest01 9207: any.
  assert verdict_of(9299, asker(log: done([9207]))) == Acceptable
    as "bit 1: one of them is enough"
  assert verdict_of(9299, asker(log: done([9428, 9207]))) == Acceptable
  assert verdict_of(9299, asker(log: [])) == Refused(code: 8)
}

pub fn accept_refuses_a_taken_exclusion_test() -> Nil {
  use <- owned_test.run(10_000)
  // 3195 names exclusions 3215 and 3216.
  assert verdict_of(3195, asker(log: [accepted(3215)])) == Refused(code: 9)
    as "an accepted exclusion"
  assert verdict_of(
      3195,
      asker(log: [quest_support.completed(quest_id: 3216, at: 1000)]),
    )
    == Refused(code: 9)
    as "a completed exclusion"
  assert verdict_of(3195, asker(log: [quest_support.known(3215, 6)]))
    == Acceptable
    as "an abandoned quest (state 6) is not taken"
  let all_of_them = Quest2(..row(3195), preq_flags: 32)
  assert verdict(quest: all_of_them, asker: asker(log: [accepted(3215)]))
    == Acceptable
    as "preq_flags 32 refuses only when every named exclusion is taken"
  assert verdict(
      quest: all_of_them,
      asker: asker(log: [
        accepted(3215),
        quest_support.completed(quest_id: 3216, at: 1000),
      ]),
    )
    == Refused(code: 9)
}

pub fn accept_names_reputation_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  // 3243 names factionIdPreq0 648 and prerequisite quests 3176 and 3185.
  let done =
    asker(log: [
      quest_support.completed(quest_id: 3176, at: 1000),
      quest_support.completed(quest_id: 3185, at: 1000),
    ])
  assert verdict_of(3243, done) == NotRead(gap: quest.Reputation)
    as "the server holds no reputation, so it says so and does not accept"
  assert verdict_of(3243, asker(log: [])) == Refused(code: 8)
    as "check 8 comes before the reputation"
}

pub fn accept_needs_the_prerequisite_item_held_test() -> Nil {
  use <- owned_test.run(10_000)
  // 3627: Dominion, preq_flags 8, preq_item 6873.
  let ready = dominion_asker(log: [])
  assert verdict_of(3627, holding(asker: ready, item: 6873, location: 0))
    == Acceptable
    as "equipped"
  assert verdict_of(3627, holding(asker: ready, item: 6873, location: 1))
    == Acceptable
    as "in a bag"
  assert verdict_of(3627, holding(asker: ready, item: 6873, location: 8))
    == Acceptable
    as "location 8 counts (mask 0x303 of 0x140552550)"
  assert verdict_of(3627, holding(asker: ready, item: 6873, location: 9))
    == Acceptable
    as "location 9 counts"
  assert verdict_of(3627, holding(asker: ready, item: 6873, location: 2))
    == NotRead(gap: quest.PrerequisiteItemCounter)
    as "location 2 is none of the four, and the per-item counter is not read"
  assert verdict_of(3627, ready) == NotRead(gap: quest.PrerequisiteItemCounter)
    as "an item not found in the four places may be in the per-item counter"
  assert verdict_of(
      9793,
      holding(asker: asker(log: []), item: 49_795, location: 1),
    )
    == Acceptable
    as "9793: preq_flags 24, preq_item 49795"
}

pub fn accept_checks_the_prerequisite_for_the_player_test() -> Nil {
  use <- owned_test.run(10_000)
  // 3678 names Prerequisite 2967, which wants the Explorer path (3).
  assert verdict_of(3678, on_path(asker(log: []), 1)) == Refused(code: 12)
  assert verdict_of(3678, on_path(asker(log: []), 3)) == Acceptable
  assert verdict_of(4943, asker(log: [])) == Acceptable
    as "4943's Prerequisite 2968 holds for this player"
  assert verdict_of(5084, asker(log: []))
    == NotRead(gap: quest.PrerequisiteType(prerequisite_type: 19))
    as "5084's Prerequisite 8252 holds a condition of type 19, which the server does not read"
  // Quest 3524 of the client names Prerequisite 2755, which the table lacks, and the
  // client's evaluator fails an id with no row (`0x1404a1ca0`, slot 0x18); the
  // fixture holds no row 2755 either, so quest 1806 is given it.
  use tables <- fixture_tables.changed(table: "Quest2", id: 1806, with: [
    #("prerequisiteId", Integer(2755)),
  ])
  let assert Ok(target) = quest2.get(tables:, id: Quest2Id(1806))
    as "the changed row is in the tables"
  assert quest.can_accept(
      tables:,
      quest: target,
      asker: asker(log: []),
      mask: quest.every_check,
    )
    == Ok(Refused(code: 12))
    as "a prerequisite id with no row fails, so the quest is refused by check 12"
}

pub fn accept_refuses_another_path_test() -> Nil {
  use <- owned_test.run(10_000)
  // 4004 wants path 3 and 4940 path 2 (Quest2.subMissionPathType); the asker is path 1.
  assert verdict_of(4004, asker(log: [])) == Refused(code: 13)
  assert verdict_of(4940, asker(log: [])) == Refused(code: 13)
  assert verdict_of(4004, on_path(asker(log: []), 3)) == Acceptable
  assert verdict_of(4940, on_path(asker(log: []), 2)) == Acceptable
  assert verdict_of(1806, asker(log: [])) == Acceptable
    as "a quest with subMissionPathType -1 wants no path"
}

pub fn accept_refuses_a_full_log_but_not_a_contract_count_test() -> Nil {
  use <- owned_test.run(10_000)
  let full = asker(log: list.map(quest_support.plain(), accepted))
  assert list.length(quest_support.plain()) == 40
  assert verdict_of(1806, full) == Refused(code: 15)
    as "the active list holds 40 (GameFormula 655), all of them accepted"
  let with_contracts =
    asker(
      log: list.flatten([
        list.map(list.take(quest_support.plain(), 39), accepted),
        [accepted(9880), accepted(9881)],
      ]),
    )
  assert verdict_of(1806, with_contracts) == Acceptable
    as "39 plain quests and two contracts: contracts do not count (flags 0x80000)"
  assert verdict_of(9880, at_level(full, 50)) == NotRead(gap: quest.Contract)
    as "a contract needs no room, and the contracts manager is not read"
}

pub fn accept_offers_undrawn_periodic_quests_and_names_drawn_ones_test() -> Nil {
  use <- owned_test.run(10_000)
  assert verdict_of(1857, asker(log: [])) == Acceptable
    as "1857 repeats daily and is in no group (group 0)"
  // PeriodicQuestGroup 1 offers every quest with no limit (-1 and -1).
  assert verdict(
      quest: Quest2(..row(1857), periodic_quest_group_id: 1),
      asker: asker(log: []),
    )
    == Acceptable
  // 9578 is in group 34 (offers 2, holds 2) and 9713 in group 29 (offers all, holds 1).
  assert verdict_of(9578, asker(log: []))
    == NotRead(gap: quest.PeriodicDraw(group_id: 34))
  assert verdict_of(9713, asker(log: []))
    == NotRead(gap: quest.PeriodicDraw(group_id: 29))
  assert verdict(
      quest: Quest2(..row(1857), periodic_quest_weight: 0),
      asker: asker(log: []),
    )
    == Refused(code: 16)
    as "a repeating quest of weight 0 joins no group"
}

pub fn a_periodic_quest_of_no_known_group_takes_group_1s_limits_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x1405a7c90`: the group named by periodicQuestGroupId, or when no group has
  // that id, the group with the lowest id at or above 1. Group 1 is limited here, so
  // a quest that falls to it is a draw the server does not read.
  use tables <- fixture_tables.changed(
    table: "PeriodicQuestGroup",
    id: 1,
    with: [
      #("maxPeriodicQuestsAllowed", Integer(1)),
    ],
  )
  let in_group = fn(group_id) {
    quest.can_accept(
      tables:,
      quest: Quest2(..row(1857), periodic_quest_group_id: group_id),
      asker: asker(log: []),
      mask: quest.every_check,
    )
  }
  assert in_group(0) == Ok(NotRead(gap: quest.PeriodicDraw(group_id: 1)))
    as "group 0 is no group, so group 1"
  assert in_group(999_999) == Ok(NotRead(gap: quest.PeriodicDraw(group_id: 1)))
    as "an id with no row falls to group 1"
  assert in_group(34) == Ok(NotRead(gap: quest.PeriodicDraw(group_id: 34)))
    as "a group with its own row keeps it"
}

pub fn accept_names_a_contract_as_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  let contract = Quest2(..row(1806), flags: 0x80000)
  assert verdict(quest: contract, asker: asker(log: []))
    == NotRead(gap: quest.Contract)
  assert verdict_of(9880, at_level(asker(log: []), 50))
    == NotRead(gap: quest.Contract)
}

/// A Quest2 row with one column changed, for a check no client row fails by itself.
fn faction_enum(quest quest: Quest2, enum enum: Int) -> Quest2 {
  Quest2(..quest, quest_player_faction_enum: enum)
}

fn needing_race(quest quest: Quest2, race race: Int) -> Quest2 {
  Quest2(..quest, preq_race: race)
}

fn needing_class(quest quest: Quest2, class class: Int) -> Quest2 {
  Quest2(..quest, preq_class: class)
}

fn with_preq_flags(quest quest: Quest2, flags flags: Int) -> Quest2 {
  Quest2(..quest, preq_flags: flags)
}

fn needing_quest(quest quest: Quest2, quest_id quest_id: Int) -> Quest2 {
  Quest2(..quest, preq_quest0: quest_id)
}

fn needing_reputation(quest quest: Quest2, faction faction: Int) -> Quest2 {
  Quest2(..quest, faction_id_preq0: faction)
}

fn needing_item(quest quest: Quest2, item item: Int) -> Quest2 {
  Quest2(..quest, preq_item: item)
}

fn on_the_path(quest quest: Quest2, path path: Int) -> Quest2 {
  Quest2(..quest, sub_mission_path_type: path)
}

fn weightless(quest quest: Quest2) -> Quest2 {
  Quest2(..quest, periodic_quest_weight: 0)
}

fn with_flags(quest quest: Quest2, flags flags: Int) -> Quest2 {
  Quest2(..quest, flags:)
}

fn done(quest_id: Int) -> QuestRow {
  quest_support.completed(quest_id:, at: 1000)
}

/// Two checks that both fail and the one the client reports: the quest and asker that
/// fail both, the verdict of the earlier check, and, where the earlier can be left out,
/// the quest, asker and verdict of the later check failing alone.
type Order {
  Order(
    name: String,
    quest: Quest2,
    asker: Asker,
    earlier: Verdict,
    later: Option(Alone),
  )
}

type Alone {
  Alone(quest: Quest2, asker: Asker, verdict: Verdict)
}

fn alone(
  quest quest: Quest2,
  asker asker: Asker,
  verdict verdict: Verdict,
) -> Option(Alone) {
  Some(Alone(quest:, asker:, verdict:))
}

fn all_forty() -> List(QuestRow) {
  list.map(quest_support.plain(), accepted)
}

fn mentioned_5259() -> QuestRow {
  quest_support.known(5259, 5)
}

fn order_11_2() -> Order {
  Order(
    name: "11 before 2",
    quest: row(1872),
    asker: asker(log: [accepted(1872)]),
    earlier: Refused(code: 11),
    later: None,
  )
}

fn order_2_14() -> Order {
  let quest = faction_enum(quest: row(1806), enum: 0)
  Order(
    name: "2 before 14",
    quest:,
    asker: dominion_asker(log: [accepted(1806)]),
    earlier: Refused(code: 2),
    later: alone(quest:, asker: dominion_asker(log: []), verdict: Refused(14)),
  )
}

fn order_14_4() -> Order {
  let quest = needing_race(quest: row(1806), race: 1)
  Order(
    name: "14 before 4",
    quest: faction_enum(quest:, enum: 0),
    asker: dominion_asker(log: []),
    earlier: Refused(code: 14),
    later: alone(quest:, asker: asker(log: []), verdict: Refused(4)),
  )
}

fn order_4_5() -> Order {
  let quest = needing_class(quest: row(1806), class: 1)
  Order(
    name: "4 before 5",
    quest: needing_race(quest:, race: 1),
    asker: asker(log: []),
    earlier: Refused(code: 4),
    later: alone(quest:, asker: asker(log: []), verdict: Refused(5)),
  )
}

fn order_5_10() -> Order {
  let log = [mentioned_5259(), done(4791)]
  Order(
    name: "5 before 10",
    quest: needing_class(quest: row(5259), class: 1),
    asker: asker(log:),
    earlier: Refused(code: 5),
    later: alone(quest: row(5259), asker: asker(log:), verdict: Refused(10)),
  )
}

fn order_10_3() -> Order {
  Order(
    name: "10 before 3",
    quest: row(5259),
    asker: at_level(asker(log: [mentioned_5259(), done(4791)]), 10),
    earlier: Refused(code: 10),
    later: alone(
      quest: row(5259),
      asker: at_level(asker(log: [mentioned_5259()]), 10),
      verdict: Refused(3),
    ),
  )
}

fn order_3_8() -> Order {
  let quest = with_preq_flags(quest: row(3918), flags: 0)
  Order(
    name: "3 before 8",
    quest:,
    asker: at_level(asker(log: []), 10),
    earlier: Refused(code: 3),
    later: alone(quest:, asker: asker(log: []), verdict: Refused(8)),
  )
}

fn order_8_9() -> Order {
  let quest =
    needing_quest(
      quest: with_preq_flags(quest: row(3195), flags: 0),
      quest_id: 4294,
    )
  Order(
    name: "8 before 9",
    quest:,
    asker: asker(log: [accepted(3215)]),
    earlier: Refused(code: 8),
    later: alone(
      quest:,
      asker: asker(log: [done(4294), accepted(3215)]),
      verdict: Refused(9),
    ),
  )
}

fn order_9_6() -> Order {
  let target = needing_reputation(quest: row(3195), faction: 648)
  Order(
    name: "9 before 6",
    quest: target,
    asker: asker(log: [accepted(3215)]),
    earlier: Refused(code: 9),
    later: alone(
      quest: target,
      asker: asker(log: []),
      verdict: NotRead(gap: quest.Reputation),
    ),
  )
}

fn order_6_7() -> Order {
  let log = [done(3176), done(3185)]
  Order(
    name: "6 before 7",
    quest: needing_item(quest: row(3243), item: 6873),
    asker: asker(log:),
    earlier: NotRead(gap: quest.Reputation),
    later: alone(
      quest: needing_reputation(
        quest: needing_item(quest: row(3243), item: 6873),
        faction: 0,
      ),
      asker: asker(log:),
      verdict: NotRead(gap: quest.PrerequisiteItemCounter),
    ),
  )
}

fn order_7_12() -> Order {
  let target = needing_item(quest: row(3678), item: 6873)
  Order(
    name: "7 before 12",
    quest: target,
    asker: on_path(asker(log: []), 1),
    earlier: NotRead(gap: quest.PrerequisiteItemCounter),
    later: alone(
      quest: target,
      asker: holding(asker: on_path(asker(log: []), 1), item: 6873, location: 1),
      verdict: Refused(12),
    ),
  )
}

fn order_12_13() -> Order {
  Order(
    name: "12 before 13",
    quest: on_the_path(quest: row(3678), path: 3),
    asker: on_path(asker(log: []), 1),
    earlier: Refused(code: 12),
    later: alone(
      quest: row(4004),
      asker: on_path(asker(log: []), 1),
      verdict: Refused(13),
    ),
  )
}

fn order_13_15() -> Order {
  Order(
    name: "13 before 15",
    quest: row(4004),
    asker: on_path(asker(log: all_forty()), 1),
    earlier: Refused(code: 13),
    later: alone(
      quest: row(4004),
      asker: on_path(asker(log: all_forty()), 3),
      verdict: Refused(15),
    ),
  )
}

fn order_15_16() -> Order {
  let quest = weightless(quest: row(1857))
  Order(
    name: "15 before 16",
    quest:,
    asker: asker(log: all_forty()),
    earlier: Refused(code: 15),
    later: alone(quest:, asker: asker(log: []), verdict: Refused(16)),
  )
}

fn order_16_17() -> Order {
  let contract = with_flags(quest: row(1857), flags: 0x80020)
  Order(
    name: "16 before 17",
    quest: weightless(quest: contract),
    asker: asker(log: []),
    earlier: Refused(code: 16),
    later: alone(
      quest: contract,
      asker: asker(log: []),
      verdict: NotRead(gap: quest.Contract),
    ),
  )
}

fn orders() -> List(Order) {
  [
    order_11_2(),
    order_2_14(),
    order_14_4(),
    order_4_5(),
    order_5_10(),
    order_10_3(),
    order_3_8(),
    order_8_9(),
    order_9_6(),
    order_6_7(),
    order_7_12(),
    order_12_13(),
    order_13_15(),
    order_15_16(),
    order_16_17(),
  ]
}

pub fn accept_reports_the_first_failure_in_the_client_order_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(orders(), fn(order) {
    assert verdict(quest: order.quest, asker: order.asker) == order.earlier
      as { order.name <> ": both fail, the earlier check decides" }
    case order.later {
      None -> Nil
      Some(Alone(quest:, asker:, verdict: expected)) -> {
        assert verdict(quest:, asker:) == expected
          as {
            order.name
            <> ": the later check fails alone, so the order is observable"
          }
        Nil
      }
    }
  })
}

pub fn accept_from_an_item_needs_the_item_that_starts_the_quest_test() -> Nil {
  use <- owned_test.run(10_000)
  let body = accept_body(location: 1, bag_index: 0, quest_id: 2417)
  let started = fn(asker) { took(message: quest.Accept, body:, asker:) }
  let sent = [quest.SendState(quest_id: 2417, state: 1, objective_id: 0)]
  assert started(
      Asker(..asker(log: []), items: [
        item(item2_id: 4861, location: 1, bag_index: 0),
      ]),
    ).effects
    == sent
    as "Item2 4861 starts quest 2417 (quest2IdActivation) and is held at the place named"
  assert_declined(started(asker(log: [])), quest: 2417)
  // Item2 1039 starts no quest.
  assert_declined(
    started(
      Asker(..asker(log: []), items: [
        item(item2_id: 1039, location: 1, bag_index: 0),
      ]),
    ),
    quest: 2417,
  )
  assert_declined(
    started(
      Asker(..asker(log: []), items: [
        item(item2_id: 4861, location: 1, bag_index: 1),
      ]),
    ),
    quest: 2417,
  )
}

/// A request that is answered with nothing: one warning line, the log as it was.
fn assert_declined(taken: Taken, quest quest_id: Int) -> Nil {
  let assert [quest.Log(level: LogWarning, text:)] = taken.effects
    as "a request the client would not send is logged and unanswered"
  assert string.contains(text, "quest " <> int.to_string(quest_id))
    as "the line names the quest"
  Nil
}

pub fn accept_from_the_dialog_needs_a_giver_in_reach_or_a_mentioned_call_test() -> Nil {
  use <- owned_test.run(10_000)
  let dialog = fn(quest_id) {
    accept_body(location: 300, bag_index: 0xFFFF_FFFF, quest_id:)
  }
  let done = asker(log: [quest_support.completed(quest_id: 10_520, at: 1000)])
  let from = fn(picture, quest_id, asker) {
    took_in(message: quest.Accept, body: dialog(quest_id), asker:, picture:)
  }
  let sent = [quest.SendState(quest_id: 10_528, state: 1, objective_id: 0)]
  // Reach is 6.0 and a request may add 3.0 (`opcode.0x7ea`), measured edge to edge.
  assert from(
      quest_walker_support.walker(gap: 8.9, alive: True, hostile: False),
      10_528,
      done,
    ).effects
    == sent
    as "Dorian Walker gives quest 10528 and stands within 9.0"
  assert_declined(
    from(
      quest_walker_support.walker(gap: 9.1, alive: True, hostile: False),
      10_528,
      done,
    ),
    quest: 10_528,
  )
  assert_declined(
    from(
      quest_walker_support.walker(gap: 1.0, alive: True, hostile: True),
      10_528,
      done,
    ),
    quest: 10_528,
  )
  assert_declined(
    from(
      quest_walker_support.walker(gap: 1.0, alive: False, hostile: False),
      10_528,
      done,
    ),
    quest: 10_528,
  )
  assert_declined(
    from(
      quest_walker_support.walker(gap: 1.0, alive: True, hostile: False),
      1806,
      done,
    ),
    quest: 1806,
  )
  // A communicator quest the log holds a state of 4 to 7 for needs no creature.
  let called = asker(log: [quest_support.known(1872, 5)])
  assert from(dict.new(), 1872, called).effects
    == [quest.SendState(quest_id: 1872, state: 1, objective_id: 0)]
    as "1872 has Quest2 flag 4, the communicator's, and the log holds it mentioned"
}

/// Creature2 12545 is a Simple unit (CreationTypeEnum 10, shown as an object) that gives
/// quest 3689 (`questIdGiven00`): the client's marking of a giver reads its row and
/// disposition and range and not its unit type (`0x1405a8d40`, `0x1403add00`).
pub fn a_quest_is_accepted_from_a_simple_giver_in_reach_test() -> Nil {
  use <- owned_test.run(10_000)
  let dialog =
    accept_body(location: 300, bag_index: 0xFFFF_FFFF, quest_id: 3689)
  let from = fn(gap, hostile_to) {
    took_in(
      message: quest.Accept,
      body: dialog,
      asker: asker(log: []),
      picture: simple_unit_support.picture(
        creature_id: 12_545,
        faction_id: 219,
        checklist_index: 0,
        gap:,
        hostile_to:,
      ),
    )
  }
  let friendly = Hostile(exile: False, dominion: False)
  assert from(8.9, friendly).effects
    == [quest.SendState(quest_id: 3689, state: 1, objective_id: 0)]
    as "the Simple giver of quest 3689 stands within 9.0, edge to edge"
  assert_declined(from(9.1, friendly), quest: 3689)
  assert_declined(from(1.0, Hostile(exile: True, dominion: True)), quest: 3689)
}

pub fn retry_takes_only_a_botched_quest_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 2417 has no time limit in the client's row, so one is set to see it restored.
  use tables <- fixture_tables.changed(table: "Quest2", id: 2417, with: [
    #("maxTimeAllowedMS", Integer(90_000)),
  ])
  let retry = fn(log) {
    quest.take(
      message: quest.Retry,
      body: retry_body(quest_id: 2417),
      asker: Asker(..asker(log:), items: [
        item(item2_id: 4861, location: 1, bag_index: 0),
      ]),
      standing: standing(),
      picture: dict.new(),
      tables:,
      now_ms: 0,
      logged: set.new(),
    )
  }
  let assert Ok(taken) = retry([quest_support.known(2417, 4)])
  assert taken.effects
    == [quest.SendState(quest_id: 2417, state: 1, objective_id: 0)]
    as "a Botched quest (4) is taken again"
  assert quest_log.rows(log: taken.log, now_ms: 0)
    == [
      QuestRow(
        quest_id: 2417,
        state: 1,
        completed_at: None,
        active: Some(
          ActiveQuest(
            placeholder_objective_id: 0,
            tracked: True,
            done_mask: 0,
            progress: [],
            quest_ms_left: 90_000,
            objective_ms_left: [],
            kill_mask: [0, 0, 0, 0, 0, 0],
          ),
        ),
      ),
    ]
    as "the entry has the quest's whole time left (maxTimeAllowedMS)"
  let assert Ok(mentioned) = retry([quest_support.known(2417, 5)])
  assert_declined(mentioned, quest: 2417)
  let assert Ok(none) = retry([])
  assert_declined(none, quest: 2417)
}

pub fn a_request_the_client_would_not_send_is_logged_and_unanswered_test() -> Nil {
  use <- owned_test.run(10_000)
  let unknown = accept_body(location: 1, bag_index: 0, quest_id: 32_000)
  let unchanged = asker(log: [quest_support.known(1806, 5)])
  let first =
    quest.take(
      message: quest.Accept,
      body: unknown,
      asker: unchanged,
      standing: standing(),
      picture: dict.new(),
      tables: tables(),
      now_ms: 0,
      logged: set.new(),
    )
  let assert Ok(first) = first
  let assert [quest.Log(level: LogWarning, ..)] = first.effects
    as "the first request of a reason is a warning: Quest2 has no row 32000"
  assert quest_log.rows(log: first.log, now_ms: 0)
    == quest_log.rows(log: unchanged.log, now_ms: 0)
  let assert Ok(second) =
    quest.take(
      message: quest.Accept,
      body: unknown,
      asker: unchanged,
      standing: standing(),
      picture: dict.new(),
      tables: tables(),
      now_ms: 0,
      logged: first.logged,
    )
  let assert [quest.Log(level: LogDebug, ..)] = second.effects
    as "the same reason again is a debug line"
  let assert Ok(other) =
    quest.take(
      message: quest.Retry,
      body: retry_body(quest_id: 1806),
      asker: unchanged,
      standing: standing(),
      picture: dict.new(),
      tables: tables(),
      now_ms: 0,
      logged: second.logged,
    )
  let assert [quest.Log(level: LogWarning, ..)] = other.effects
    as "another reason warns once again: 1806 is Mentioned, not Botched"
  // 2417 is held Botched and its item is in a bag, so only the message is wrong: the
  // client sends a Botched quest as 0x0365 only (`opcode.0x35b`, `opcode.0x365`).
  let botched = asker(log: [quest_support.known(2417, 4)])
  let from_item =
    Asker(..botched, items: [item(item2_id: 4861, location: 1, bag_index: 0)])
  let assert Ok(accepted_botched) =
    quest.take(
      message: quest.Accept,
      body: accept_body(location: 1, bag_index: 0, quest_id: 2417),
      asker: from_item,
      standing: standing(),
      picture: dict.new(),
      tables: tables(),
      now_ms: 0,
      logged: set.new(),
    )
  assert_declined(accepted_botched, quest: 2417)
  assert quest_log.rows(log: accepted_botched.log, now_ms: 0)
    == quest_log.rows(log: botched.log, now_ms: 0)
    as "an accept for a Botched quest leaves the log as it was"
  let assert Error(quest.NotDecoded(_)) =
    quest.take(
      message: quest.Accept,
      body: <<1>>,
      asker: unchanged,
      standing: standing(),
      picture: dict.new(),
      tables: tables(),
      now_ms: 0,
      logged: set.new(),
    )
    as "a body the client's reader would refuse ends the connection"
  Nil
}

fn standing() -> interaction.Player {
  interaction.Player(
    race_id: RaceId(3),
    faction: shown.Exile,
    place: connection_support.entry_place(),
  )
}

fn accept_body(
  location location: Int,
  bag_index bag_index: Int,
  quest_id quest_id: Int,
) -> BitArray {
  let assert Ok(body) =
    quest_accept.encode(QuestAccept(
      item: ItemPlace(location:, bag_index:),
      quest_id:,
    ))
    as "the request fits its fields"
  body
}

fn retry_body(quest_id quest_id: Int) -> BitArray {
  let assert Ok(body) = quest_retry.encode(QuestRetry(quest_id:))
    as "the request fits its fields"
  body
}

fn took(
  message message: quest.Message,
  body body: BitArray,
  asker asker: Asker,
) -> Taken {
  took_in(message:, body:, asker:, picture: dict.new())
}

fn took_in(
  message message: quest.Message,
  body body: BitArray,
  asker asker: Asker,
  picture picture: Picture,
) -> Taken {
  let assert Ok(taken) =
    quest.take(
      message:,
      body:,
      asker:,
      standing: standing(),
      picture:,
      tables: tables(),
      now_ms: 0,
      logged: set.new(),
    )
    as "the body is one the client's reader takes"
  taken
}
