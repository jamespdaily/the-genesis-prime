//// A player's turn-in of a quest, 0x035D (`genesis_prime/game/quest_turn_in`). Expected
//// values come from these places, and never from the helpers that build the input.
//// - `0x140553030` (the turn-in's checks) needs the quest Achieved, or an auto-complete
////   quest (Quest2 flags bit 0) the player could accept, and a receiver; `0x140555350`
////   reads the reward id; `0x140557000` refuses a fixed TradeSkillXp row for a tradeskill
////   the player has not learned, and the client's tradeskill list is empty here;
////   `0x1403add00` measures the reach edge to edge. `0x1405fbdc0.state_3`: state 3 puts the
////   quest in the completed set.
//// - `0x140551c60` (IsRewardChoiceOffered): a choice is offered when it has no flags bit 0,
////   has bit 1, is not an item, or its Item2 row allows the player's race, class and
////   proficiency; a quest whose every choice fails offers its first.
//// - `0x1405534b0` (CalcQuestRewardXp): `reward_xpOverride` when above 0, else
////   XpPerLevel.baseQuestXpPerLevel at the quest's level times the difficulty's
////   xpMultiplier times LevelDifferentialAttribute.questXpMultiplier of the quest's level
////   less the player's, from -4 to 4 (row id = value + 5), truncated. `0x1405542b0` (credits):
////   `reward_cashOverride` when above 0, else conLevel ^ 1.93 (GameFormula 530) times the
////   difficulty's cashRewardMultiplier plus 0.5, truncated; at most GetCurrencyCap 500,000.
//// - The fixture's rows: Dorian Walker (Creature2 74812) gives 10528 and receives 10520
////   (five objectives, difficulty 6, `reward_xpOverride` 1055, no reward row); Quest2Difficulty
////   1 has xpMultiplier 0.25 and cashRewardMultiplier 1, difficulty 3 has 1 and 10, difficulty
////   6 has 0 and 0; XpPerLevel 1 to 5 have min experience 0, 655, 1710, 2860, 4320.
//// - Quests of the fixture: 1806 (no condition, level 1, difficulty 1, no reward row), 5859
////   (level 4, difficulty 3, fixed items 81917 and 29661), 5261 (seven item choices, no fixed
////   row), 2909 (flags 8; choices 2368 and 2369, fixed 2370), 5084 (a fixed TradeSkillXp row
////   2471 and a fixed item), 9578 (level 12, difficulty 1; a currency 6 row and an item).

import character_tables
import genesis_prime/game/experience.{GainSent, LevelRose, Progress}
import genesis_prime/game/prerequisite
import genesis_prime/game/quest
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/quest_turn_in
import genesis_prime/game/vendor_trade.{type Effect, Log, Refuse, Send}
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/currency_gained.{CurrencyGained}
import genesis_prime/message/item_added
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/step.{LogDebug, LogWarning}
import genesis_prime/store.{
  type QuestRow, HeldItem, NewStack, Placed, QuestRow, StackGrowth,
}
import genesis_prime/table/id.{Item2Id, Quest2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/world_map/creature_life.{Hostile}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import owned_test
import planted_table.{Float, Integer}
import player_life_support
import quest_support
import quest_turn_in_support as support
import quest_walker_support
import simple_unit_support

const tutorial_quest = 10_520

fn tables() -> table_store.Tables {
  character_tables.shared()
}

/// Every refusal in this module is one log line, once per reason on the connection (a
/// warning, then a debug line), with nothing sent.
fn assert_refused(
  scene scene: support.Scene,
  tables tables: table_store.Tables,
  because because: String,
) -> Nil {
  let #(effects, logged) = support.refused(scene:, tables:)
  let assert [Log(level: LogWarning, ..)] = effects
    as { because <> ": a warning and nothing sent" }
  assert set.size(logged) == 1 as { because <> ": one reason is now logged" }
  let #(again, still) =
    support.refused(support.Scene(..scene, logged:), tables:)
  let assert [Log(level: LogDebug, ..)] = again
    as { because <> ": the same reason is a debug line the second time" }
  assert still == logged as { because <> ": no new reason" }
}

fn assert_asked(
  scene scene: support.Scene,
  tables tables: table_store.Tables,
) -> Nil {
  let #(_, _) = support.asked(scene:, tables:)
  Nil
}

fn rows_of(log log: QuestLog) -> List(QuestRow) {
  quest_log.rows(log:, now_ms: 0)
}

pub fn achieved_quest_at_its_receiver_is_turned_in_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene = support.scene(quest_id: tutorial_quest)
  let #(turn_in, effects) = support.asked(scene:, tables: tables())
  assert turn_in.quest_id == 10_520
  assert rows_of(log: turn_in.log)
    == [
      QuestRow(
        quest_id: 10_520,
        state: 3,
        completed_at: Some(1_700_000_000),
        active: None,
      ),
    ]
    as "the log holds the quest Completed at the Unix second of the turn-in (0x1405fbdc0.state_3)"
  assert effects == []
    as "the quest has no reward row of a kind left out, so nothing is logged"
  // A stored Accepted entry whose five objectives are all done reads Achieved.
  let done =
    support.Scene(..scene, log: [
      quest_support.active(
        quest_id: tutorial_quest,
        state: 1,
        placeholder: 0,
        tracked: True,
        done_mask: 31,
        progress: [1, 1, 1, 1, 1],
      ),
    ])
  let #(from_done, _) = support.asked(scene: done, tables: tables())
  assert rows_of(log: from_done.log) == rows_of(log: turn_in.log)
    as "an Accepted entry with every objective done is turned in as an Achieved one"
}

pub fn turn_in_of_a_quest_not_achieved_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene = support.scene(quest_id: tutorial_quest)
  list.each(
    [
      #("Accepted, objectives to do", [
        quest_support.untouched(quest_id: tutorial_quest),
      ]),
      #("Completed", [
        quest_support.completed(quest_id: tutorial_quest, at: 1000),
      ]),
      #("Known (4 to 7)", [quest_support.known(tutorial_quest, 5)]),
      #("absent", []),
    ],
    fn(case_) {
      assert_refused(
        scene: support.Scene(..scene, log: case_.1),
        tables: tables(),
        because: case_.0,
      )
    },
  )
  assert_refused(
    scene: support.Scene(..scene, quest_id: 32_000, log: []),
    tables: tables(),
    because: "a quest with no Quest2 row",
  )
  let assert Error(quest.NotDecoded(..)) =
    support.taken_from(scene:, body: <<1, 2>>, tables: tables())
    as "a body shorter than the 31 bits the client's reader takes ends the connection"
  Nil
}

pub fn turn_in_away_from_a_receiver_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene = support.scene(quest_id: tutorial_quest)
  let walker = fn(gap, alive, hostile) {
    quest_walker_support.walker(gap:, alive:, hostile:)
  }
  assert_refused(
    scene: support.Scene(..scene, picture: dict.new()),
    tables: tables(),
    because: "no creature shown",
  )
  assert_refused(
    scene: support.Scene(..scene, picture: walker(1.0, False, False)),
    tables: tables(),
    because: "the receiver is dead",
  )
  assert_refused(
    scene: support.Scene(..scene, picture: walker(1.0, True, True)),
    tables: tables(),
    because: "the receiver is Hostile",
  )
  assert_refused(
    scene: support.Scene(..scene, picture: walker(9.1, True, False)),
    tables: tables(),
    because: "the receiver is beyond 9.0, edge to edge",
  )
  assert_asked(
    scene: support.Scene(..scene, picture: walker(8.9, True, False)),
    tables: tables(),
  )
  assert_refused(
    scene: support.scene(quest_id: 10_528),
    tables: tables(),
    because: "Dorian Walker gives quest 10528 and does not receive it",
  )
}

/// Creature2 12545 is a Simple unit (CreationTypeEnum 10, shown as an object) that receives
/// quest 3689 (`questIdReceive00`), which the log holds Achieved with no objective to do
/// (the Quest2 row names none): the client's check of a receiver reads its row, life,
/// disposition and range and not its unit type (`0x140553030`, `0x1403add00`).
pub fn a_quest_is_turned_in_to_a_simple_receiver_in_reach_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene = support.scene(quest_id: 3689)
  let receiver = fn(gap, hostile_to) {
    support.Scene(
      ..scene,
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
  let #(turn_in, _) =
    support.asked(scene: receiver(8.9, friendly), tables: tables())
  assert turn_in.quest_id == 3689
  assert rows_of(log: turn_in.log)
    == [
      QuestRow(
        quest_id: 3689,
        state: 3,
        completed_at: Some(1_700_000_000),
        active: None,
      ),
    ]
    as "the log holds the quest Completed at the Unix second of the turn-in (0x1405fbdc0.state_3)"
  assert_refused(
    scene: receiver(9.1, friendly),
    tables: tables(),
    because: "the Simple receiver is beyond 9.0, edge to edge",
  )
  let hostile = receiver(1.0, Hostile(exile: True, dominion: True))
  assert_refused(
    scene: hostile,
    tables: tables(),
    because: "the Simple receiver is Hostile",
  )
  let #(_, logged) = support.refused(scene: hostile, tables: tables())
  assert set.contains(logged, "no receiver")
    as "the refusal is the receiver's, not the quest's state"
}

pub fn auto_complete_quest_is_turned_in_untaken_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [
    #("Quest2", 1806, [#("flags", Integer(1))]),
    support.receiving(1806),
  ])
  let scene = support.Scene(..support.scene(quest_id: 1806), log: [])
  let #(turn_in, _) = support.asked(scene:, tables:)
  assert rows_of(log: turn_in.log)
    == [
      QuestRow(
        quest_id: 1806,
        state: 3,
        completed_at: Some(1_700_000_000),
        active: None,
      ),
    ]
    as "no entry goes straight to Completed (0x1405fbdc0.state_3 reads no earlier state)"
  let mentioned = support.Scene(..scene, log: [quest_support.known(1806, 5)])
  let #(from_known, _) = support.asked(scene: mentioned, tables:)
  assert rows_of(log: from_known.log) == rows_of(log: turn_in.log)
    as "a Known entry goes to Completed too"
  // A log of forty quests is full: accepting would be refused with code 15.
  let full = list.map(quest_support.plain(), quest_support.untouched)
  let crowded = support.Scene(..scene, log: full)
  let assert Ok(row) = quest2.get(tables:, id: Quest2Id(1806))
  assert quest.can_accept(
      tables:,
      quest: row,
      asker: support.asker(scene: crowded),
      mask: quest.every_check,
    )
    == Ok(quest.Refused(code: 15))
    as "the log is full: 0x140552550 check 15"
  let #(from_full, _) = support.asked(scene: crowded, tables:)
  assert list.any(rows_of(log: from_full.log), fn(row) {
    row.quest_id == 1806 && row.state == 3
  })
    as "a full log does not stop an auto-complete quest"
}

pub fn auto_complete_quest_that_could_not_be_accepted_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [
    #("Quest2", 1806, [#("flags", Integer(1)), #("preq_level", Integer(5))]),
    support.receiving(1806),
  ])
  let scene = support.Scene(..support.scene(quest_id: 1806), log: [])
  assert_refused(
    scene:,
    tables:,
    because: "a level 1 player, the quest needs level 5 (accept check 3)",
  )
  use tables <- support.with_changes(changes: [
    #("Quest2", 1806, [#("flags", Integer(1))]),
    support.receiving(1806),
  ])
  let completed =
    support.Scene(..scene, log: [
      quest_support.completed(quest_id: 1806, at: 1000),
    ])
  let assert Ok(row) = quest2.get(tables:, id: Quest2Id(1806))
  assert quest.can_accept(
      tables:,
      quest: row,
      asker: support.asker(scene: completed),
      mask: 0xffff_dfff,
    )
    == Ok(quest.Refused(code: 2))
    as "a completed quest that does not repeat is refused by accept check 2 itself"
  assert_refused(
    scene: completed,
    tables:,
    because: "a completed one-time quest (accept check 2)",
  )
}

pub fn completed_repeatable_auto_complete_quest_is_turned_in_again_test() -> Nil {
  use <- owned_test.run(10_000)
  // flags 0x21: auto-completes (bit 0) and repeats (bit 5, 0x140552550 check 2 lets a
  // completed quest through when it repeats).
  use tables <- support.with_changes(changes: [
    #("Quest2", 1806, [#("flags", Integer(0x21))]),
    support.receiving(1806),
  ])
  let scene =
    support.Scene(..support.scene(quest_id: 1806), log: [
      quest_support.completed(quest_id: 1806, at: 1000),
    ])
  let #(turn_in, _) = support.asked(scene:, tables:)
  assert rows_of(log: turn_in.log)
    == [
      QuestRow(
        quest_id: 1806,
        state: 3,
        completed_at: Some(1_700_000_000),
        active: None,
      ),
    ]
    as "a Completed repeatable quest is Completed again, at the new time"
  use tables <- support.with_changes(changes: [
    #("Quest2", 1806, [
      #("flags", Integer(1)),
      #("questRepeatPeriodEnum", Integer(1)),
    ]),
    support.receiving(1806),
  ])
  let #(by_period, _) = support.asked(scene:, tables:)
  assert rows_of(log: by_period.log) == rows_of(log: turn_in.log)
    as "a quest with a repeat period is turned in again too"
}

/// The warning a refused scene gives, with the same asserts as `assert_refused`.
fn refused_text(
  scene scene: support.Scene,
  tables tables: table_store.Tables,
  because because: String,
) -> String {
  assert_refused(scene:, tables:, because:)
  let #(effects, _) = support.refused(scene:, tables:)
  let assert [Log(text:, ..)] = effects as "one log line"
  text
}

/// A turn-in over the communicator: the bit is set and no creature is shown.
fn by_communicator(scene scene: support.Scene) -> support.Scene {
  support.Scene(..scene, by_communicator: 1, picture: dict.new())
}

/// The scene of quest 3673 over the communicator. Its Quest2Reward rows are item choices
/// (flags 1), so the player picks row 2187 and holds every proficiency.
fn choosing_3673() -> support.Scene {
  support.Scene(
    ..by_communicator(scene: support.scene(quest_id: 3673)),
    reward_id: 2187,
    proficiencies: 0x7fffffff,
    world_id: 426,
  )
}

pub fn communicator_turn_in_needs_no_creature_near_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest2 10519 has flags 0x4008 (bit 3); its receiver Creature2 73491 has factionId 171,
  // whose level from the Exile faction 167 is above 2 (Faction2Relationship), so
  // `0x14043c700` opens the dialog and `0x140553030` gives the turn-in.
  let scene = by_communicator(scene: support.scene(quest_id: 10_519))
  assert dict.is_empty(scene.picture) as "no creature is shown"
  let #(turn_in, _) = support.asked(scene:, tables: tables())
  assert turn_in.quest_id == 10_519
  assert rows_of(log: turn_in.log)
    == [
      QuestRow(
        quest_id: 10_519,
        state: 3,
        completed_at: Some(1_700_000_000),
        active: None,
      ),
    ]
    as "the log holds the quest Completed at the Unix second of the turn-in"
}

pub fn communicator_turn_in_of_a_quest_without_flag_8_or_0x10000_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest2 10520 has flags 0x4404: neither bit 3 nor bit 16, so the communicator's dialog
  // gives it no turn-in (`0x140553030`, `0x14043c700`).
  let scene = support.scene(quest_id: tutorial_quest)
  assert_asked(scene:, tables: tables())
  let text =
    refused_text(
      scene: by_communicator(scene:),
      tables: tables(),
      because: "a quest of flags 0x4404 over the communicator",
    )
  assert string.contains(text, "neither flag 8 nor flag 0x10000")
    as "the line gives the flag reason"
}

pub fn communicator_turn_in_with_every_receiver_hostile_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest2 10522 has flags 0x4008; its only receiver Creature2 74861 has factionId 170,
  // level 2 or below from Exile 167 (Hostile) and above 2 from Dominion 166.
  let scene = by_communicator(scene: support.scene(quest_id: 10_522))
  assert string.contains(
    refused_text(
      scene:,
      tables: tables(),
      because: "the only receiver is Hostile to an Exile",
    ),
    "Hostile",
  )
    as "the line says why"
  assert_asked(
    scene: support.Scene(
      ..scene,
      factions: prerequisite.Factions(current: 166, base: 166),
    ),
    tables: tables(),
  )
  assert_refused(
    scene: support.Scene(
      ..scene,
      factions: prerequisite.Factions(current: 167, base: 166),
    ),
    tables: tables(),
    because: "the check reads the current faction and not the base one",
  )
}

pub fn communicator_turn_in_of_a_0x10000_quest_no_row_delivers_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest2 6654 has flags 0x10008. No CommunicatorMessages row has questIdDelivered 6654,
  // and flag 8 does not rescue it: the dialog tests bit 16 first (`0x140553030`). Its
  // receiver Creature2 30336 (faction 170) is not Hostile to the Dominion.
  let scene =
    support.Scene(
      ..by_communicator(scene: support.scene(quest_id: 6654)),
      factions: prerequisite.Factions(current: 166, base: 166),
    )
  assert string.contains(
    refused_text(
      scene:,
      tables: tables(),
      because: "no row delivers a quest of flags 0x10008",
    ),
    "delivers",
  )
    as "the line says no row delivers it"
}

pub fn communicator_turn_in_of_an_accepted_quest_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043c700` takes the turn-in path only for a quest whose state is 2.
  let scene =
    support.Scene(
      ..by_communicator(scene: support.scene(quest_id: 10_519)),
      log: [quest_support.untouched(10_519)],
    )
  assert string.contains(
    refused_text(
      scene:,
      tables: tables(),
      because: "the quest is Accepted with no objective done",
    ),
    "is 1 and not Achieved",
  )
    as "the line names the state in the log"
}

pub fn communicator_turn_in_does_not_auto_complete_test() -> Nil {
  use <- owned_test.run(10_000)
  // Flags 9 (bits 0 and 3): communicable and auto-completing. The communicator's accept path
  // for it needs a side-list entry that only a call (0x757) makes, which the server does not
  // send (#334), so a quest not in the log is not turned in over the communicator.
  use tables <- support.with_changes(changes: [
    #("Quest2", 1806, [#("flags", Integer(9))]),
    support.receiving(1806),
  ])
  let scene = support.Scene(..support.scene(quest_id: 1806), log: [])
  let text =
    refused_text(
      scene: by_communicator(scene:),
      tables:,
      because: "a communicable auto-complete quest not in the log",
    )
  assert string.contains(text, "#334") as "the line names the gap"
  // The unit path completes the same quest with flags 1 (bit 0).
  use tables <- support.with_changes(changes: [
    #("Quest2", 1806, [#("flags", Integer(1))]),
    support.receiving(1806),
  ])
  assert_asked(scene:, tables:)
}

pub fn each_communicator_refusal_has_its_own_log_key_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quests 10520 (neither flag), 10522 (receiver Hostile to an Exile) and 6654 (flag
  // 0x10000, no row delivers it) are refused for three different reasons; a key's first line
  // is a warning and later lines are debug, so each reason has its own key.
  let key_of = fn(quest_id, factions) {
    let scene =
      support.Scene(
        ..by_communicator(scene: support.scene(quest_id:)),
        factions:,
      )
    let #(_, logged) = support.refused(scene:, tables: tables())
    let assert [key] = set.to_list(logged) as "one key"
    key
  }
  let exile = prerequisite.Factions(current: 167, base: 167)
  let dominion = prerequisite.Factions(current: 166, base: 166)
  let keys = [
    key_of(tutorial_quest, exile),
    key_of(10_522, exile),
    key_of(6654, dominion),
  ]
  assert list.length(list.unique(keys)) == 3
    as "three kinds of refusal, three keys"
}

/// A dead player's turn-in of `scene`: refused with the client's code 57 and a log line under
/// the dead player's own key, nothing asked, the same scene alive being accepted.
fn assert_refused_dead(scene scene: support.Scene) -> Nil {
  assert_asked(scene:, tables: tables())
  let dead = support.Scene(..scene, life: player_life_support.dead())
  let #(effects, logged) = support.refused(scene: dead, tables: tables())
  let assert [Log(level: LogWarning, text:), Refuse(code: 57)] = effects
    as "a warning, then 0x106 with enum 57 Player_CantDoWhileDead (the client's dialog closes and sends nothing for a dead player)"
  assert string.contains(text, "dead")
  assert logged == set.from_list(["dead player"])
    as "the dead player's own key, not one of the checks the client's dialog passes"
  let #(again, still) =
    support.refused(scene: support.Scene(..dead, logged:), tables: tables())
  let assert [Log(level: LogDebug, ..), Refuse(code: 57)] = again
    as "the same reason is a debug line the second time, and answered again"
  assert still == logged
}

pub fn a_dead_players_turn_in_at_a_creature_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_refused_dead(scene: support.scene(quest_id: tutorial_quest))
}

pub fn a_dead_players_turn_in_over_the_communicator_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_refused_dead(
    scene: by_communicator(scene: support.scene(quest_id: 10_519)),
  )
}

pub fn communicator_turn_in_with_a_delivering_row_is_accepted_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest2 3673 has flags 0x18004 (bit 16): CommunicatorMessages row 1281 (flags 0, worldId
  // 426, quest00 3673 in state 2, creatureId 11063, which receives 3673) delivers it.
  let scene = choosing_3673()
  let #(turn_in, _) = support.asked(scene:, tables: tables())
  assert turn_in.quest_id == 3673
}

pub fn communicator_turn_in_of_a_0x10000_quest_reads_no_receiver_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  // The same quest for a Dominion player: every receiver (11063, 12959, 16622) has factionId
  // 171, Hostile from 166, and the dialog's 0x10000 branch has no faction test.
  let scene =
    support.Scene(
      ..choosing_3673(),
      factions: prerequisite.Factions(current: 166, base: 166),
    )
  assert_asked(scene:, tables: tables())
}

pub fn chosen_reward_is_one_the_client_offers_test() -> Nil {
  use <- owned_test.run(10_000)
  let choosing = fn(reward_id, proficiencies) {
    support.Scene(..support.scene(quest_id: 5261), reward_id:, proficiencies:)
  }
  // Quest 5261's seven rows are all item choices (flags 1). Their Item2 rows ask for no
  // race or class; ItemProficiency bit masks: 2225 and 7283 need 2, 2196 7277 and 7278
  // need 4, 2213 and 7279 need 8.
  {
    use tables <- support.with_changes(changes: [support.receiving(5261)])
    assert_refused(
      scene: choosing(2196, 2),
      tables:,
      because: "a choice whose proficiency the player lacks",
    )
    assert_refused(
      scene: choosing(32_767, 2),
      tables:,
      because: "an id that is no row at all",
    )
    assert_refused(
      scene: choosing(2369, 2),
      tables:,
      because: "a choice row of another quest",
    )
    list.each([2225, 7283], fn(id) {
      assert_asked(scene: choosing(id, 2), tables:)
    })
    list.each([2196, 7277, 7278], fn(id) {
      assert_asked(scene: choosing(id, 4), tables:)
    })
    // No proficiency offers none of them, so the first row is offered alone.
    assert_asked(scene: choosing(2196, 0), tables:)
    assert_refused(
      scene: choosing(2213, 0),
      tables:,
      because: "when every choice fails only the first is offered",
    )
  }
  {
    use tables <- support.with_changes(changes: [
      support.receiving(5261),
      #("Item2", 28_063, [#("classRequired", Integer(1))]),
    ])
    assert_refused(
      scene: choosing(2225, 2),
      tables:,
      because: "an item for class 1 and the player is class 5",
    )
    assert_asked(scene: choosing(7283, 2), tables:)
  }
  {
    use tables <- support.with_changes(changes: [
      support.receiving(5261),
      #("Item2", 28_063, [#("raceRequired", Integer(1))]),
    ])
    assert_refused(
      scene: choosing(2225, 2),
      tables:,
      because: "an item for race 1 and the player is race 3",
    )
  }
  {
    use tables <- support.with_changes(changes: [
      support.receiving(5261),
      #("Item2", 28_063, [
        #("classRequired", Integer(16)),
        #("raceRequired", Integer(4)),
      ]),
    ])
    assert_asked(scene: choosing(2225, 2), tables:)
  }
  {
    use tables <- support.with_changes(changes: [
      support.receiving(5261),
      #("Quest2Reward", 2213, [#("flags", Integer(3))]),
    ])
    assert_asked(scene: choosing(2213, 2), tables:)
  }
}

pub fn reward_id_zero_only_without_choices_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [
    support.receiving(5261),
    support.receiving_in(5859, slot: 2),
  ])
  let with_reward = fn(quest_id, reward_id) {
    support.Scene(..support.scene(quest_id:), reward_id:)
  }
  assert_refused(
    scene: with_reward(5261, 0),
    tables:,
    because: "id 0 for a quest with choice rows",
  )
  assert_asked(scene: with_reward(5859, 0), tables:)
  assert_refused(
    scene: with_reward(5859, 4819),
    tables:,
    because: "a fixed row's id for a quest with no choice row",
  )
  assert_refused(
    scene: with_reward(5859, 2369),
    tables:,
    because: "another quest's row for a quest with no choice row",
  )
}

pub fn fixed_tradeskill_reward_refuses_the_turn_in_test() -> Nil {
  use <- owned_test.run(10_000)
  {
    use tables <- support.with_changes(changes: [support.receiving(5084)])
    assert_refused(
      scene: support.scene(quest_id: 5084),
      tables:,
      because: "a fixed TradeSkillXp row (Quest2Reward 2471) and no learned tradeskill",
    )
  }
  {
    use tables <- support.with_changes(changes: [
      support.receiving(5084),
      #("Quest2Reward", 2471, [#("flags", Integer(1))]),
    ])
    assert_refused(
      scene: support.scene(quest_id: 5084),
      tables:,
      because: "id 0 while 2471 is a choice row",
    )
    let #(turn_in, effects) =
      support.asked(
        scene: support.Scene(..support.scene(quest_id: 5084), reward_id: 2471),
        tables:,
      )
    assert list.map(turn_in.placed, fn(placed) { placed.item2_id })
      == [Item2Id(13_375)]
      as "the type-4 choice is not refused and gives nothing; the fixed item (row 2486) is placed"
    let assert [Log(level: LogWarning, text:)] = effects
    assert string.contains(text, "#677")
      as "the left-out tradeskill experience names its issue"
  }
}

pub fn quest_experience_is_override_or_formula_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [
    support.receiving(5859),
    support.receiving_in(9578, slot: 2),
  ])
  let gain = fn(scene) {
    let #(turn_in, _) = support.asked(scene:, tables:)
    turn_in.credited
  }
  assert gain(support.scene(quest_id: tutorial_quest))
    == experience.Credited(Progress(experience: 1055, level: 2), [
      GainSent(gain: 1055, kind: 3, unit_id: 0),
      LevelRose(level: 2),
    ])
    as "the override 1055, not scaled"
  let at_level_4 =
    support.Scene(..support.scene(quest_id: 5859), level: 4, experience: 2860)
  assert gain(at_level_4)
    == experience.Credited(Progress(experience: 3012, level: 4), [
      GainSent(gain: 152, kind: 3, unit_id: 0),
    ])
    as "difficulty 3: 152 (XpPerLevel 4) times 1.0 times 1.0"
  assert gain(
      support.Scene(
        ..support.scene(quest_id: 9578),
        level: 12,
        experience: 43_830,
      ),
    )
    == experience.Credited(Progress(experience: 44_072, level: 12), [
      GainSent(gain: 242, kind: 3, unit_id: 0),
    ])
    as "difficulty 1: 968 (XpPerLevel 12) times 0.25"
  difficulty_six_without_an_override_gives_no_experience()
  experience_follows_the_level_difference()
}

fn difficulty_six_without_an_override_gives_no_experience() -> Nil {
  use tables <- support.with_changes(changes: [
    #("Quest2", 10_520, [#("reward_xpOverride", Integer(0))]),
  ])
  let #(turn_in, _) =
    support.asked(scene: support.scene(quest_id: tutorial_quest), tables:)
  assert turn_in.credited
    == experience.Credited(Progress(experience: 0, level: 1), [])
    as "difficulty 6 has xpMultiplier 0: no gain and no 0x1ac"
}

fn experience_follows_the_level_difference() -> Nil {
  use tables <- support.with_changes(changes: [
    support.receiving(5859),
    // The rows of difference 0 (id 5) and -4 or less (id 1) halve the experience.
    #("LevelDifferentialAttribute", 5, [#("questXpMultiplier", Float(0.5))]),
    #("LevelDifferentialAttribute", 1, [#("questXpMultiplier", Float(0.5))]),
  ])
  let gain = fn(level, held) {
    let #(turn_in, _) =
      support.asked(
        scene: support.Scene(
          ..support.scene(quest_id: 5859),
          level:,
          experience: held,
        ),
        tables:,
      )
    turn_in.credited.progress.experience - held
  }
  assert gain(4, 2860) == 76
    as "quest level 4, player level 4: row 5, trunc(152 x 1.0 x 0.5)"
  assert gain(20, 340_950) == 76
    as "a difference of -16 reads row 1, the lowest"
  assert gain(1, 0) == 152 as "a difference of 3 reads row 8, which is 1.0"
}

pub fn quest_credits_are_override_or_rounded_formula_test() -> Nil {
  use <- owned_test.run(10_000)
  let credits = fn(tables, scene) {
    let #(turn_in, _) = support.asked(scene:, tables:)
    #(turn_in.credits_held, turn_in.credits_after)
  }
  let at_receiver = support.receiving(5859)
  {
    use tables <- support.with_changes(changes: [
      at_receiver,
      #("Quest2", 5859, [#("conLevel", Integer(1))]),
    ])
    assert credits(tables, support.scene(quest_id: 5859)) == #(0, 10)
      as "difficulty 3 at level 1: trunc(1 ^ 1.93 x 10 + 0.5)"
  }
  {
    use tables <- support.with_changes(changes: [
      at_receiver,
      #("Quest2", 5859, [#("conLevel", Integer(2))]),
    ])
    assert credits(tables, support.scene(quest_id: 5859)) == #(0, 38)
      as "difficulty 3 at level 2: trunc(2 ^ 1.93 x 10 + 0.5)"
  }
  use tables <- support.with_changes(changes: [at_receiver])
  let scene = support.scene(quest_id: 5859)
  assert credits(tables, scene) == #(0, 145)
    as "difficulty 3 at level 4: trunc(4 ^ 1.93 x 10 + 0.5)"
  assert credits(tables, support.Scene(..scene, credits: 1000)) == #(1000, 1145)
    as "the credits held are added to"
  assert credits(tables, support.Scene(..scene, credits: 499_990))
    == #(499_990, 500_000)
    as "the total stops at the cap, 500,000"
  assert credits(tables, support.Scene(..scene, credits: 500_100))
    == #(500_100, 500_100)
    as "a total already above the cap stays"
  use overridden <- support.with_changes(changes: [
    at_receiver,
    #("Quest2", 5859, [#("reward_cashOverride", Integer(5000))]),
  ])
  assert credits(overridden, scene) == #(0, 5000)
    as "reward_cashOverride above 0 wins over the formula"
}

pub fn quest_experience_raises_the_level_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [
    #("Quest2", 10_520, [#("reward_xpOverride", Integer(655))]),
  ])
  let #(turn_in, _) =
    support.asked(scene: support.scene(quest_id: tutorial_quest), tables:)
  assert turn_in.credited
    == experience.Credited(Progress(experience: 655, level: 2), [
      GainSent(gain: 655, kind: 3, unit_id: 0),
      LevelRose(level: 2),
    ])
    as "655 from 0 is the least experience of level 2: the level rises"
  // Level 50's least experience is 26,360,090 (XpPerLevel 50); it is the highest level.
  let top =
    support.Scene(
      ..support.scene(quest_id: tutorial_quest),
      level: 50,
      experience: 26_360_090,
    )
  let #(at_top, _) =
    support.asked(scene: top, tables: character_tables.shared())
  assert at_top.credited
    == experience.Credited(Progress(experience: 26_360_090, level: 50), [])
    as "at the highest level a gain adds nothing and nothing is sent"
}

pub fn reward_items_fill_stacks_then_lowest_free_slots_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 179 holds one to a stack, Item2 6998 one hundred. Quest 2909's fixed row 2370
  // gives 179 and its choice 2369 gives 6998; the amounts are changed to need more than
  // a stack of each.
  use tables <- support.with_changes(changes: [
    support.receiving(2909),
    #("Quest2Reward", 2370, [#("objectAmount", Integer(3))]),
    #("Quest2Reward", 2369, [#("objectAmount", Integer(150))]),
  ])
  let scene =
    support.Scene(..support.scene(quest_id: 2909), reward_id: 2369, items: [
      support.in_bag(guid: 601, item2_id: 6998, index: 0, count: 90),
      support.in_bag(guid: 602, item2_id: 179, index: 1, count: 1),
    ])
  let #(turn_in, _) = support.asked(scene:, tables:)
  assert turn_in.placed
    == [
      Placed(Item2Id(179), grow: [], make: [
        NewStack(location: 1, bag_index: 2, stack_count: 1, random_stats: 0),
        NewStack(location: 1, bag_index: 3, stack_count: 1, random_stats: 0),
        NewStack(location: 1, bag_index: 4, stack_count: 1, random_stats: 0),
      ]),
      Placed(
        Item2Id(6998),
        grow: [StackGrowth(item_guid: 601, held_count: 90, new_count: 100)],
        make: [
          NewStack(location: 1, bag_index: 5, stack_count: 100, random_stats: 0),
          NewStack(location: 1, bag_index: 6, stack_count: 40, random_stats: 0),
        ],
      ),
    ]
    as "the fixed row first, then the chosen one; 179 never grows, 6998's held stack fills to 100 and the rest takes the lowest free slots after the slots 179 took"
  // The same Item2 twice is placed once, with the counts added.
  use same <- support.with_changes(changes: [
    support.receiving(2909),
    #("Quest2Reward", 2370, [#("objectAmount", Integer(3))]),
    #("Quest2Reward", 2369, [
      #("objectId", Integer(179)),
      #("objectAmount", Integer(2)),
    ]),
  ])
  let #(sum, _) =
    support.asked(
      scene: support.Scene(..support.scene(quest_id: 2909), reward_id: 2369),
      tables: same,
    )
  assert sum.placed
    == [
      Placed(Item2Id(179), grow: [], make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
        NewStack(location: 1, bag_index: 1, stack_count: 1, random_stats: 0),
        NewStack(location: 1, bag_index: 2, stack_count: 1, random_stats: 0),
        NewStack(location: 1, bag_index: 3, stack_count: 1, random_stats: 0),
        NewStack(location: 1, bag_index: 4, stack_count: 1, random_stats: 0),
      ]),
    ]
    as "three fixed and two chosen of one Item2 are five stacks"
}

pub fn full_inventory_answers_inventory_full_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [support.receiving(5859)])
  // Item2 179 holds one to a stack, so a bag of them has no room in its stacks. Quest
  // 5859 gives Item2 81917 and 29661: two stacks to place.
  let filled = fn(slots) {
    int.range(from: 0, to: slots, with: [], run: fn(items, index) {
      [
        support.in_bag(guid: 700 + index, item2_id: 179, index:, count: 1),
        ..items
      ]
    })
  }
  let scene = fn(slots) {
    support.Scene(
      ..support.scene(quest_id: 5859),
      items: filled(slots),
      logged: set.from_list(["kept"]),
    )
  }
  list.each([16, 15], fn(slots) {
    let #(effects, logged) = support.refused(scene: scene(slots), tables:)
    assert effects == [Refuse(code: 27)]
      as "0x106 code 27, Item_InventoryFull, and nothing else"
    assert logged == set.from_list(["kept"]) as "the log keys are as they were"
  })
  assert_asked(scene: scene(14), tables:)
}

pub fn left_out_reward_kinds_are_logged_once_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 9578 has a currency 6 row (10) and the item 49083; a reputation faction is
  // added to its row.
  use tables <- support.with_changes(changes: [
    support.receiving(9578),
    #("Quest2", 9578, [#("faction2IdRewardReputation00", Integer(609))]),
  ])
  let scene =
    support.Scene(
      ..support.scene(quest_id: 9578),
      level: 12,
      experience: 43_830,
    )
  let assert Ok(quest_turn_in.Asks(turn_in:, effects:, logged:)) =
    support.taken(scene:, tables:)
    as "the turn-in passes every check"
  assert list.map(turn_in.placed, fn(placed) { placed.item2_id })
    == [Item2Id(49_083)]
    as "the item is placed"
  assert turn_in.credited.progress.experience == 44_072
    as "the experience is paid: 242"
  assert turn_in.credits_after == 121
    as "the credits are paid: trunc(12 ^ 1.93 x 1 + 0.5)"
  let texts =
    list.map(effects, fn(effect) {
      let assert Log(level: LogWarning, text:) = effect
        as "a warning, the first time"
      text
    })
  assert list.length(texts) == 2 as "one line for each kind left out"
  assert list.any(texts, string.contains(_, "#674"))
    as "reputation names its issue"
  assert list.any(texts, string.contains(_, "#675"))
    as "other currencies name theirs"
  assert set.size(logged) == 2
  let #(_, again) =
    support.asked(scene: support.Scene(..scene, logged:), tables:)
  assert list.all(again, fn(effect) {
    case effect {
      Log(level: LogDebug, ..) -> True
      Log(..) | Send(..) | Refuse(..) -> False
    }
  })
    as "the second time on the connection each is a debug line"
}

/// A quest reward with random stat entries is made rolled: quest 9376's reward is Item2 48169,
/// which has three kind-2 entries, 4 bytes of entropy each. The bytes of `random_stat_test`'s
/// pick (the fractions 0.0, 0.5 and 0.99) give the word 0x0100000000050401, which the stack is
/// made with and the 0x111 carries (`opcode.0x111.shared_item_random_stats`).
pub fn a_quest_reward_with_random_stats_is_made_rolled_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [support.receiving(9376)])
  let #(turn_in, _) =
    support.asked(scene: support.scene(quest_id: 9376), tables:)
  assert quest_turn_in.entropy_needed(turn_in:, tables:) == 12
    as "ItemStat 432 has three kind-2 entries, 4 bytes each, for the one stack made"
  let rolled =
    quest_turn_in.rolled(turn_in:, tables:, entropy: <<
      0x00000000:size(32),
      0x80000000:size(32),
      0xFD70A3D7:size(32),
    >>)
  let word = 0x0100000000050401
  assert rolled.placed
    == [
      Placed(Item2Id(48_169), grow: [], make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: word),
      ]),
    ]
    as "the reward is placed once, its stack carrying the rolled word"
  let made =
    HeldItem(
      item_guid: 900,
      item2_id: Item2Id(48_169),
      location: 1,
      bag_index: 0,
      stack_count: 1,
      random_stats: word,
    )
  let assert quest_turn_in.Saved(items:, rewards:, ..) =
    quest_turn_in.answered(
      turn_in: rolled,
      items: [],
      currencies: support.credits(total: 0),
      answer: store.TurnedIn(credits: 0, made: [made]),
    )
    as "the store's answer is saved"
  assert items == [made] as "the item is held with its word"
  let assert [Send(frame:)] =
    list.filter(rewards, fn(effect) {
      case effect {
        Send(frame:) -> frame.message_id == item_added.message_id
        Log(..) | Refuse(..) -> False
      }
    })
    as "one 0x111 for the one stack made"
  let assert Ok(sent) = item_added.decode(frame.body) as "0x111 decodes"
  assert sent.held_item.item.random_stats == word
    as "opcode.0x111: the item is sent with its word"
}

/// The ids of the messages a turn-in's answer sends after its items, which are all sends.
fn sent_ids(effects effects: List(Effect)) -> List(Int) {
  list.map(effects, fn(effect) {
    let assert Send(frame:) = effect
      as "the effects after the items are all sends"
    frame.message_id
  })
}

/// A credit reward is sent as the new total, then the gain, then the quest's state:
/// quest 5859 at level 4 pays trunc(4 ^ 1.93 x 10 + 0.5) = 145 credits, as
/// `quest_credits_are_override_or_rounded_formula_test` shows from `0x1405542b0`, so a
/// player holding 1000 holds 1145 (`opcode.0xdd.with_0x919`: the 0x919 sets the total and
/// the 0xdd prints the line, so the credits count once).
pub fn a_credit_reward_sends_the_gain_after_the_total_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [support.receiving(5859)])
  let #(turn_in, _) =
    support.asked(
      scene: support.Scene(..support.scene(quest_id: 5859), credits: 1000),
      tables:,
    )
  let assert quest_turn_in.Saved(then:, ..) =
    quest_turn_in.answered(
      turn_in:,
      items: [],
      currencies: support.credits(total: 1000),
      answer: store.TurnedIn(credits: 1145, made: []),
    )
    as "the store's answer is saved"
  assert sent_ids(effects: then)
    == [
      currency_changed.message_id,
      currency_gained.message_id,
      quest_state.message_id,
    ]
    as "opcode.0xdd.with_0x919: the total, the gain, then 0x35C"
  let assert [Send(total), Send(gain), Send(state)] = then as "three sends"
  assert currency_changed.decode(total.body)
    == Ok(CurrencyChanged(kind: 0, total: 1145, field_3: 0, field_4: 0))
    as "opcode.0x919: kind 0 sets the credits to 1145"
  assert currency_gained.decode(gain.body)
    == Ok(CurrencyGained(currency_type_id: 1, amount: 145, signature_amount: 0))
    as "opcode.0xdd: the credits given, 145, in credits (type 1)"
  assert quest_state.decode(state.body)
    == Ok(QuestState(quest_id: 5859, state: 3, objective_id: 0))
    as "opcode.0x35c: the quest is in state 3"
}

/// Quest 10520's difficulty 6 has cashRewardMultiplier 0 (fixture, `0x1405542b0`), so it
/// pays no credits and the player's total does not change.
pub fn a_turn_in_with_no_credits_sends_no_gain_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(turn_in, _) =
    support.asked(
      scene: support.scene(quest_id: tutorial_quest),
      tables: tables(),
    )
  let assert quest_turn_in.Saved(then:, ..) =
    quest_turn_in.answered(
      turn_in:,
      items: [],
      currencies: support.credits(total: 0),
      answer: store.TurnedIn(credits: 0, made: []),
    )
    as "the store's answer is saved"
  assert sent_ids(effects: then) == [quest_state.message_id]
    as "opcode.0xdd: with no credits given there is no gain to show, and no total changed"
}

// The server's completion of a quest no creature receives (`quest_turn_in.completed_by_server`).
// Evidence: `Quest2.10513.completion` says the server decides when a quest with no giver
// ends. In the client's rows quest 2417 (flags 8) and quest 2909 (flags 8, two reward
// choices and a fixed item) have no receiver; quest 5859 has one (Creature2 26071), which
// `support.unreceived_5859` clears where a test needs the quest and its rewards.

/// The same asserts as `assert_refused` for a server completion: one warning and nothing
/// sent, a debug line the second time.
fn assert_server_refused(
  scene scene: support.Scene,
  tables tables: table_store.Tables,
  because because: String,
) -> Nil {
  let #(effects, logged) = support.server_refused(scene:, tables:)
  let assert [Log(level: LogWarning, ..)] = effects
    as { because <> ": a warning and nothing sent" }
  assert set.size(logged) == 1 as { because <> ": one reason is now logged" }
  let #(again, still) =
    support.server_refused(support.Scene(..scene, logged:), tables:)
  let assert [Log(level: LogDebug, ..)] = again
    as { because <> ": the same reason is a debug line the second time" }
  assert still == logged as { because <> ": no new reason" }
}

pub fn a_quest_no_creature_receives_is_completed_by_the_server_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 5859 (flags 0, no receiver once Creature2 26071's is cleared) has the fixed
  // Quest2Reward rows 4819 and 4821: Item2 81917 and 29661. At level 4 it pays
  // trunc(4 ^ 1.93 x 10 + 0.5) = 145 credits (GameFormula 530, `0x1405542b0`).
  use tables <- support.with_changes(changes: [support.unreceived_5859()])
  let scene = support.scene(quest_id: 5859)
  let #(turn_in, effects) = support.server_asked(scene:, tables:)
  assert turn_in.quest_id == 5859
  assert rows_of(log: turn_in.log)
    == [
      QuestRow(
        quest_id: 5859,
        state: 3,
        completed_at: Some(1_700_000_000),
        active: None,
      ),
    ]
    as "the log holds the quest Completed at the Unix second of the completion (0x1405fbdc0.state_3)"
  assert list.map(turn_in.placed, fn(placed) { placed.item2_id })
    == [Item2Id(81_917), Item2Id(29_661)]
    as "the fixed items of its reward rows"
  assert turn_in.credits_after == 145
  assert effects == [] as "no reward kind is left out"
}

pub fn a_server_completion_gives_the_same_turn_in_as_a_0x35d_test() -> Nil {
  use <- owned_test.run(10_000)
  use with_receiver <- support.with_changes(changes: [support.receiving(5859)])
  use unreceived <- support.with_changes(changes: [support.unreceived_5859()])
  let scene =
    support.Scene(..support.scene(quest_id: 5859), credits: 1000, level: 4)
  let #(by_server, server_effects) =
    support.server_asked(scene:, tables: unreceived)
  let #(by_walker, walker_effects) =
    support.asked(scene:, tables: with_receiver)
  assert by_server == by_walker
    as "the rewards, the credits, the experience and the log are the turn-in at Dorian Walker's"
  assert server_effects == walker_effects
}

pub fn a_contract_is_not_completed_by_the_server_test() -> Nil {
  use <- owned_test.run(10_000)
  // Flag 0x80000 is a quest of the contracts manager (`Contract:Complete` `0x1406a3ba0`
  // sends its turn-in).
  use tables <- support.with_changes(changes: [
    support.unreceived_5859(),
    #("Quest2", 5859, [#("flags", Integer(0x80000))]),
  ])
  assert_server_refused(
    scene: support.scene(quest_id: 5859),
    tables:,
    because: "a contract",
  )
}

pub fn a_quest_the_communicator_turns_in_by_row_is_not_completed_by_the_server_test() -> Nil {
  use <- owned_test.run(10_000)
  // Flag 0x10000 is turned in over the communicator (`0x140553030`), which the client
  // sends 0x35D for.
  use tables <- support.with_changes(changes: [
    support.unreceived_5859(),
    #("Quest2", 5859, [#("flags", Integer(0x10000))]),
  ])
  assert_server_refused(
    scene: support.scene(quest_id: 5859),
    tables:,
    because: "a quest the communicator turns in by row",
  )
}

pub fn a_quest_a_creature_receives_is_not_completed_by_the_server_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 10520 is Dorian Walker's (Creature2 74812's questIdReceive00): the player turns
  // it in at him.
  assert_server_refused(
    scene: support.scene(quest_id: tutorial_quest),
    tables: tables(),
    because: "a quest a creature receives",
  )
}

pub fn a_flag_8_quest_with_no_receiver_is_completed_by_the_server_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 2417 (flags 8) has no receiver, and the communicator's flag-8 path needs a
  // receiver (`communicator.turn_in`), so nothing else completes it. It has no reward row.
  let #(turn_in, _) =
    support.server_asked(scene: support.scene(quest_id: 2417), tables: tables())
  assert turn_in.placed == [] as "no reward row, so nothing to place"
  assert rows_of(log: turn_in.log)
    == [
      QuestRow(
        quest_id: 2417,
        state: 3,
        completed_at: Some(1_700_000_000),
        active: None,
      ),
    ]
}

pub fn a_server_completion_of_a_quest_not_achieved_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [support.unreceived_5859()])
  let scene = support.scene(quest_id: 5859)
  list.each(
    [
      #("Accepted, objectives to do", [quest_support.untouched(quest_id: 5859)]),
      #("Completed", [quest_support.completed(quest_id: 5859, at: 1000)]),
      #("Known (4 to 7)", [quest_support.known(5859, 5)]),
      #("not in the log", []),
    ],
    fn(case_) {
      assert_server_refused(
        scene: support.Scene(..scene, log: case_.1),
        tables:,
        because: case_.0,
      )
    },
  )
}

pub fn a_full_bag_refuses_a_server_completion_with_0x106_code_27_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 179 holds one to a stack, so a bag of them has no room in its stacks; quest
  // 5859 gives two stacks (Item2 81917 and 29661).
  use tables <- support.with_changes(changes: [support.unreceived_5859()])
  let filled = fn(slots) {
    int.range(from: 0, to: slots, with: [], run: fn(items, index) {
      [
        support.in_bag(guid: 700 + index, item2_id: 179, index:, count: 1),
        ..items
      ]
    })
  }
  let scene = fn(slots) {
    support.Scene(
      ..support.scene(quest_id: 5859),
      items: filled(slots),
      logged: set.from_list(["kept"]),
    )
  }
  let #(effects, logged) = support.server_refused(scene: scene(15), tables:)
  assert effects == [Refuse(code: 27)]
    as "0x106 code 27, Item_InventoryFull, and nothing else"
  assert logged == set.from_list(["kept"]) as "the log keys are as they were"
  let #(_, _) = support.server_asked(scene: scene(14), tables:)
  Nil
}

pub fn a_server_completion_of_a_quest_with_a_reward_choice_gives_only_its_fixed_rewards_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 2909 (flags 8, no receiver) has two item choices (Quest2Reward 2368, Item2 13005,
  // and 2369, Item2 6998, flags 1) and a fixed item (2370: Item2 179, one, flags 0). No
  // dialog lets the player pick, so the completion gives the fixed row alone.
  let assert quest_turn_in.Asks(turn_in:, ..) =
    support.server_taken(scene: support.scene(quest_id: 2909), tables: tables())
    as "the completion passes every check, so the store is asked"
  assert turn_in.placed
    == [
      Placed(Item2Id(179), grow: [], make: [
        NewStack(location: 1, bag_index: 0, stack_count: 1, random_stats: 0),
      ]),
    ]
    as "only Quest2Reward 2370's item and count; neither choice's item (13005, 6998) is placed"
  let assert quest_turn_in.Saved(then:, ..) =
    quest_turn_in.answered(
      turn_in:,
      items: [],
      currencies: support.credits(total: 0),
      answer: store.TurnedIn(credits: 0, made: [
        HeldItem(
          item_guid: 900,
          item2_id: Item2Id(179),
          location: 1,
          bag_index: 0,
          stack_count: 1,
          random_stats: 0,
        ),
      ]),
    )
    as "the store's answer is saved"
  let assert Ok(Send(last)) = list.last(then)
  assert quest_state.decode(last.body)
    == Ok(QuestState(quest_id: 2909, state: 3, objective_id: 0))
    as "opcode.0x35c: the quest in state 3 with objective 0"
}

pub fn a_turn_in_of_a_quest_with_a_reward_choice_and_reward_id_0_is_still_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // The player's 0x035D names a reward id; for a quest with choice rows, 0 is no choice
  // (IsRewardChoiceOffered `0x140551c60`). Quest 2909 is received by Dorian Walker here.
  use tables <- support.with_changes(changes: [support.receiving(2909)])
  let #(effects, logged) =
    support.refused(scene: support.scene(quest_id: 2909), tables:)
  let assert [Log(level: LogWarning, text:)] = effects
    as "one log line and nothing sent"
  assert string.contains(text, "reward id 0")
    as "the line names the reward id the message carries"
  assert logged == set.from_list(["reward choice"])
}

pub fn a_server_completion_answered_saved_ends_with_0x35c_state_3_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- support.with_changes(changes: [support.unreceived_5859()])
  let #(turn_in, _) =
    support.server_asked(scene: support.scene(quest_id: 5859), tables:)
  let made =
    list.index_map(turn_in.placed, fn(one, index) {
      let assert [
        NewStack(location:, bag_index:, stack_count:, random_stats: 0),
      ] = one.make
        as "one stack of each, the Item2s' counts being 1"
      HeldItem(
        item_guid: 900 + index,
        item2_id: one.item2_id,
        location:,
        bag_index:,
        stack_count:,
        random_stats: 0,
      )
    })
  let assert quest_turn_in.Saved(rewards:, then:, ..) =
    quest_turn_in.answered(
      turn_in:,
      items: [],
      currencies: support.credits(total: 0),
      answer: store.TurnedIn(credits: 145, made:),
    )
    as "the store's answer is saved"
  assert sent_ids(effects: rewards) == [0x0111, 0x0111]
    as "opcode.0x111: an item added for each stack made"
  assert sent_ids(effects: then)
    == [
      currency_changed.message_id,
      currency_gained.message_id,
      quest_state.message_id,
    ]
    as "opcode.0x919 and opcode.0xdd for the credits, then opcode.0x35c last"
  let assert Ok(Send(last)) = list.last(then)
  assert quest_state.decode(last.body)
    == Ok(QuestState(quest_id: 5859, state: 3, objective_id: 0))
    as "opcode.0x35c: the quest in state 3 with objective 0"
}
