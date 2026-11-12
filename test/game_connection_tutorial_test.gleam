//// The tutorial chain on a running game connection (`genesis_prime/game/tutorial`,
//// `genesis_prime/game/world_entry`, `genesis_prime/game/connection/quest_turn_in`): what the
//// client is told when a character enters World 3460 and when the server completes a
//// tutorial quest. Expected values come from these places.
//// - `opcode.0x35c.add_unaccepted`: the server adds a quest no giver starts with 0x35c
////   {quest, 1, 0}; the client takes it with no dialog and no CanAcceptQuest check. State 3
////   is the completion (`Quest2.10513.completion`).
//// - `opcode.0x35f.entry_order`: 0x35F replaces the whole log, so a grant follows it.
//// - Quest2 10513 and 10527: giver-less quests of the Exile only (questPlayerFactionEnum 0),
////   10513 first, then 10527 once 10513 is completed (the objectives' text, the Client trace).
//// - Creature2 73419 (the tutorial hoverboard): its activate spell 86744 casts for 1500 ms and
////   its ride 85563 restricts the caster, so the press is a cast of the connection, not a
////   refusal 285 (`opcode.0x7fc`, cast_result 285 is "not planned").
//// - QuestObjective 21324 (type 12, data 73419): the use of the hoverboard counts; it is the
////   third objective of Quest2 10527 in slot order (index 2). `opcode.0x361`: an objective's
////   progress.
//// - Failure table: a save that holds a completion and not the next grant is made right at the
////   next entry into World 3460.

import departures_support
import game_connection_support as connection_support
import genesis_prime/client_connection.{AskStore, FromMap}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/quest_log as quest_log_message
import genesis_prime/message/quest_objective_progress.{QuestObjectiveProgress}
import genesis_prime/message/quest_state.{type QuestState, QuestState}
import genesis_prime/message/spell_cast_refused
import genesis_prime/step
import genesis_prime/store.{type QuestRow, Character}
import genesis_prime/table/loader/store as store_tables
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn
import gleam/list
import gleam/option.{None, Some}
import owned_test
import place_support
import quest_support
import quest_turn_in_support
import tutorial_support

/// The tests' Dominion character, made an Exile.
fn exile() -> store.Character {
  Character(
    ..connection_support.world_character(),
    faction_id: spawn.exile_faction,
  )
}

/// A connection made with the tutorial chain of the client's tables, after the store gave
/// `character` and these quest rows: the map is asked.
fn joining(
  character character: store.Character,
  quests quests: List(QuestRow),
) -> #(game_connection.State, step.ConnectionStep(client_connection.Request)) {
  joining_on(tables: connection_support.settings().tables, character:, quests:)
}

/// `joining` on these tables.
fn joining_on(
  tables tables: store_tables.Tables,
  character character: store.Character,
  quests quests: List(QuestRow),
) -> #(game_connection.State, step.ConnectionStep(client_connection.Request)) {
  let fresh =
    connection_support.accepted(
      connection_state.Settings(
        ..connection_support.settings(),
        tables:,
        tutorial_chain: tutorial_support.chain(),
      ),
    ).0
  connection_support.joining_holding(
    in_character_select: connection_support.in_select_from(fresh),
    character:,
    saved_health: None,
    saved_experience: None,
    quests:,
  )
}

/// The connection after the map took the Exile into the world its character stands in, a
/// map of World 3460.
fn entered(
  quests quests: List(QuestRow),
) -> #(game_connection.State, step.ConnectionStep(client_connection.Request)) {
  let #(state, taken) = joining(character: exile(), quests:)
  connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(FromMap(connection_support.map_answer(taken))),
  )
}

/// The connection after the map took the Exile into World 870, the Crimson Isle terminal's
/// landing of the departures (WorldLocation2 8223): a world that is not World 3460.
fn entered_elsewhere(
  tables tables: store_tables.Tables,
  quests quests: List(QuestRow),
) -> #(game_connection.State, step.ConnectionStep(client_connection.Request)) {
  let elsewhere =
    Character(
      ..exile(),
      place: Some(place_support.at(
        world_id: 870,
        world_zone_id: 1236,
        x: 1.0,
        y: 2.0,
        z: 3.0,
      )),
    )
  let #(state, taken) = joining_on(tables:, character: elsewhere, quests:)
  let #(_, answer) =
    connection_support.mapped(
      map_state: connection_support.map_of_world_with_four_players(
        map: MapId(world_id: 870, instance: 0),
        run: 5,
      ),
      taken:,
    )
  connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(FromMap(answer)),
  )
}

/// Every 0x35c the step wrote, in order.
fn states_written(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(QuestState) {
  connection_support.decoded(
    connection_support.written(taken:),
    quest_state.message_id,
    quest_state.decode,
  )
}

/// The quest ids the 0x35F the step wrote holds as active.
fn active_in_log(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(Int) {
  let assert [log] =
    connection_support.decoded(
      connection_support.written(taken:),
      quest_log_message.message_id,
      quest_log_message.decode,
    )
    as "one 0x35F"
  list.map(log.active, fn(quest) { quest.quest_id })
}

/// The quest rows the next save of the connection asks the store to keep.
fn saved_quests(state state: game_connection.State) -> List(QuestRow) {
  let #(_, saving) =
    connection_support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert AskStore(store.Move(store.SavePlace(quests:, ..))) =
    connection_support.ask_request(saving)
    as "the save timer asks the store to save the place"
  quests
}

pub fn a_new_character_entering_world_3460_is_given_10513_after_its_quest_log_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, entry) = entered(quests: [])
  let ids = connection_support.written_ids(entry)
  assert list.filter(ids, fn(id) { id == 0x035F || id == 0x035C })
    == [0x035F, 0x035C]
    as "opcode.0x35f.entry_order: the log, then the one grant after it"
  assert active_in_log(taken: entry) == []
    as "the log the client is told holds no quest: 10513 follows it"
  assert states_written(taken: entry)
    == [QuestState(quest_id: 10_513, state: 1, objective_id: 0)]
    as "opcode.0x35c.add_unaccepted: 10513, the Exile's first tutorial quest, in state 1"
  // The grant is on the connection's log: the next save keeps it, and a relog is told it.
  let saved = saved_quests(state:)
  assert list.map(saved, fn(row) { #(row.quest_id, row.state) })
    == [#(10_513, 1)]
    as "the save holds the quest Accepted"
  let #(_, relog) = entered(quests: saved)
  assert active_in_log(taken: relog) == [10_513]
    as "a relog's 0x35F holds 10513"
  assert states_written(taken: relog) == [] as "a relog gives no second copy"
}

pub fn a_character_entering_another_world_is_given_no_tutorial_quest_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, entry) =
    entered_elsewhere(tables: connection_support.settings().tables, quests: [])
  assert list.contains(connection_support.written_ids(entry), 0x035F)
    as "the entry tells the client its log"
  assert states_written(taken: entry) == []
    as "only an entry into World 3460 gives the first tutorial quest"
}

pub fn the_servers_completion_of_10513_gives_10527_test() -> Nil {
  use <- owned_test.run(10_000)
  // 10513 is saved Achieved, as a player leaves it whose last objective is done and whose
  // connection ended before the server completed it; no creature receives it.
  let #(state, entry) =
    entered(quests: [quest_turn_in_support.achieved(quest_id: 10_513)])
  assert states_written(taken: entry) == []
    as "10513 is held: the entry gives nothing and asks the server's completion"
  let #(state, completed) =
    connection_support.answer(
      state:,
      taken: entry,
      outcome: connection_support.turn_in_saved(taken: entry),
    )
  assert states_written(taken: completed)
    == [
      QuestState(quest_id: 10_513, state: 3, objective_id: 0),
      QuestState(quest_id: 10_527, state: 1, objective_id: 0),
    ]
    as "10513 Completed, then 10527 given at once"
  // A relog holds 10513 Completed and 10527 Accepted.
  let saved = saved_quests(state:)
  assert list.map(saved, fn(row) { #(row.quest_id, row.state) })
    == [#(10_513, 3), #(10_527, 1)]
    as "the save holds 10513 Completed and 10527 Accepted"
  let #(_, relog) = entered(quests: saved)
  assert active_in_log(taken: relog) == [10_527]
    as "a relog's 0x35F holds 10527 as active, and 10513 as completed"
  assert states_written(taken: relog) == [] as "a relog gives no second copy"
}

pub fn a_relog_after_a_completion_with_no_grant_gives_the_next_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, entry) =
    entered(quests: [
      quest_support.completed(quest_id: 10_513, at: 1_700_000_000),
    ])
  assert states_written(taken: entry)
    == [QuestState(quest_id: 10_527, state: 1, objective_id: 0)]
    as "10513 is Completed and 10527 is held by no row: it is given"
}

pub fn the_completion_of_a_quest_outside_the_chain_gives_no_tutorial_quest_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 5859 is Achieved in the saved log and no creature receives it (the edit below), so
  // the server completes it. The Exile is outside World 3460, so the entry gave no tutorial
  // quest: the one thing that stops the first from being due after the completion is that
  // 5859 is not a quest of the chain.
  use tables <- quest_turn_in_support.with_changes(changes: [
    quest_turn_in_support.unreceived_5859(),
  ])
  let #(state, entry) =
    entered_elsewhere(tables:, quests: [
      quest_turn_in_support.achieved(quest_id: 5859),
    ])
  assert states_written(taken: entry) == []
    as "the entry gives no tutorial quest outside World 3460 and asks the server's completion"
  let #(_, completed) =
    connection_support.answer(
      state:,
      taken: entry,
      outcome: connection_support.turn_in_saved(taken: entry),
    )
  assert states_written(taken: completed)
    == [QuestState(quest_id: 5859, state: 3, objective_id: 0)]
    as "opcode.0x35c: 5859 Completed, and no state 1 after it"
}

/// The Exile's Combat Simulation (Quest2 10527) with its first two objectives done: the
/// hoverboard's Creature2 73419 links to it through Prerequisite 41799, whose condition 43010
/// (type 68, objectId 10527, value 1) holds once the objective at index 1 is done, and the
/// use of the hoverboard, the third (21324), is open (`Creature2.prerequisiteIdAnimState`,
/// `Prerequisite.41799`, `Prerequisite.43010`).
fn quest_before_the_hoverboard() -> QuestRow {
  quest_support.active(
    quest_id: 10_527,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: 3,
    progress: [1, 1, 0, 0, 0],
  )
}

pub fn the_tutorial_hoverboard_counts_its_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    departures_support.seeing(
      state: connection_support.in_world_as_exile_holding(quests: [
        quest_before_the_hoverboard(),
      ]),
      creature_id: 73_419,
    )
  let assert Ok(body) =
    cast_activate.encode(CastActivate(
      client_cast_id: departures_support.clients_cast_id,
      target_unit_id: departures_support.terminal_unit,
    ))
    as "the message fits"
  let #(state, started) =
    connection_support.at(
      state:,
      ms: 0,
      event: step.OwnEvent(
        step.Read(connection_support.world_message(
          message_id: cast_activate.message_id,
          body:,
        )),
      ),
    )
  assert connection_support.decoded(
      connection_support.written(taken: started),
      0x07FC,
      spell_cast_refused.decode,
    )
    == []
    as "the press is not refused: a 0x7fc IllegalSpellCast for 86744 says the spell cannot be planned (opcode.0x7fc)"
  assert connection_support.written_ids(started) == [0x07FD]
    as "the press confirms the cast (opcode.0x7fd)"
  let pending = connection_support.cast_timers(steps: [started], ms: 0)
  let #(_, _, steps) =
    connection_support.casts_left(state:, pending:, until_ms: 2000, steps: [])
  let frames =
    list.flat_map(steps, fn(taken) { connection_support.written(taken:) })
  assert connection_support.decoded(
      frames,
      0x0361,
      quest_objective_progress.decode,
    )
    == [
      QuestObjectiveProgress(quest_id: 10_527, objective_index: 2, progress: 1),
    ]
    as "QuestObjective 21324, type 12 data 73419: the use is the third objective of Quest2 10527"
}
