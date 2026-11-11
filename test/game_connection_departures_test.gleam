//// The departures terminals on a running game connection: a player holding "Bon Voyage"
//// after its talk presses a terminal, answers its window and moves to the terminal's
//// landing. Expected values come from these places.
//// - Creature2 73606, 73605, 74773 and 74772: the activate spells 34680, 34681, 50279 and
////   37270, whose Spell4Base ids are 20650, 20651, 32969 and 22504 (the client's 0x805
////   carries the id plus one: `opcode.0x805.fields`).
//// - `opcode.0x805.fields`: a No on a YesNo window is result 0.
//// - `opcode.0x7fd` and `opcode.0x7fc`: the caster is written the start of a cast, or the
////   refusal of one that is not.
//// - `opcode.0x361` and `opcode.0x35c`: a quest's objective progress and its state.
//// - Quest2 10528 and 10530 ("Bon Voyage"): the objectives in slot order are the talk, the
////   travel, one choice per terminal and an optional one, so the travel is index 1 and the
////   choices are 2 and 3. The travel done makes the quest state 2 (Achieved).
//// - The client's WorldLocation2 rows 42074 (world 426, zone 648) and 8223 (world 870,
////   zone 1236): the landings of the Northern Wilds and Crimson Isle terminals.
//// - `opcode.0xad`: the join's 0xAD is the world and the position the client enters.
//// - `opcode.0x637`: the client moves its old unit until the 0xAD reaches it.
//// - `opcode.0x25e.entry_order` and `opcode.0x35f.entry_order`: a login writes 0x25E and
////   0x35F; the move writes neither.

import connection_rule_support as support
import departures_support
import game_client
import game_connection_support as connection_support
import genesis_prime/client_connection.{AskMap, AskStore, FromMap, Removed}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/departures
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/enter_world
import genesis_prime/message/float32
import genesis_prime/message/interaction_result
import genesis_prime/message/quest_active.{type QuestActive}
import genesis_prime/message/quest_log as quest_log_message
import genesis_prime/message/quest_objective_progress.{
  type QuestObjectiveProgress, QuestObjectiveProgress,
}
import genesis_prime/message/quest_state.{type QuestState, QuestState}
import genesis_prime/step
import genesis_prime/store.{
  AccountId, Character, ListCharacters, SavePlace, Select,
}
import genesis_prime/world_map/map.{Join, Left}
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/spawn
import gleam/list
import gleam/option.{Some}
import owned_test
import quest_support

const northern_wilds = 73_606

const northern_wilds_spell4_base = 20_650

const crimson_isle = 74_772

const crimson_isle_spell4_base = 22_504

const confirmed_start = [0x07FD]

const refused_start = [0x07FC]

/// The place and the map the join the step asks is for.
fn join_of(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> #(MapId, Place, Bool) {
  let assert AskMap(map: map_id, message: Join(place:, alive:, ..)) =
    connection_support.ask_request(taken)
    as "the step asks a map to join the player"
  #(map_id, place, alive)
}

fn assert_landing(
  place place: Place,
  world world: Int,
  zone zone: Int,
  x x: Float,
  y y: Float,
  z z: Float,
  reason reason: String,
) -> Nil {
  assert start_place.world_id(place) == world as reason
  assert start_place.world_zone_id(place) == zone as reason
  assert start_place.x(place) == x as reason
  assert start_place.y(place) == y as reason
  assert start_place.z(place) == z as reason
}

/// The frames of the step that are quest messages, decoded: the progress of each
/// objective and the states.
fn quest_news(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> #(List(QuestObjectiveProgress), List(QuestState)) {
  let frames = connection_support.written(taken:)
  #(
    connection_support.decoded(
      frames,
      quest_objective_progress.message_id,
      quest_objective_progress.decode,
    ),
    connection_support.decoded(
      frames,
      quest_state.message_id,
      quest_state.decode,
    ),
  )
}

/// The map's answer to the step's join, as a map of the landing's world gives it, and the
/// step of the connection taking the answer.
fn joined_at(
  state state: game_connection.State,
  joining joining: step.ConnectionStep(client_connection.Request),
  world world: Int,
) -> #(game_connection.State, step.ConnectionStep(client_connection.Request)) {
  let #(_, answer) =
    connection_support.mapped(
      map_state: connection_support.map_of_world_with_four_players(
        map: MapId(world_id: world, instance: 0),
        run: 5,
      ),
      taken: joining,
    )
  connection_support.answer(
    state:,
    taken: joining,
    outcome: step.Answer(FromMap(answer)),
  )
}

pub fn the_yes_moves_the_player_to_the_northern_wilds_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = departures_support.exile_seeing(creature_id: northern_wilds)
  let #(state, pressed) = departures_support.press(state:)
  assert connection_support.written_ids(pressed) == confirmed_start
    as "opcode.0x7fd: the right-click of the terminal writes the start, and no go yet"
  let #(state, answered) =
    departures_support.answer(
      state:,
      pressed:,
      result: interaction_result.Succeeded,
      spell4_base_id: northern_wilds_spell4_base,
    )
  assert connection_support.written_ids(answered)
    == [
      0x07F4,
      0x07FE,
      quest_objective_progress.message_id,
      quest_objective_progress.message_id,
      quest_state.message_id,
    ]
    as "the answer 1 sends the go and the finish, then counts the travel, the Northern Wilds choice and the quest's Achieved state"
  assert quest_news(taken: answered)
    == #(
      [
        QuestObjectiveProgress(
          quest_id: 10_528,
          objective_index: 1,
          progress: 1,
        ),
        QuestObjectiveProgress(
          quest_id: 10_528,
          objective_index: 2,
          progress: 1,
        ),
      ],
      [QuestState(quest_id: 10_528, state: 2, objective_id: 0)],
    )
    as "Quest2 10528: the travel (index 1) and the Northern Wilds choice (index 2) are counted; the Everstar Grove choice (index 3) is not"
  assert departures_support.started_timers(taken: answered)
    == [#(departures.timer, 0)]
    as "the move waits for the cast's frames to be carried out: a 0 ms timer"
  let #(state, leaving) = departures_support.timer_fires(state:)
  assert connection_support.ask_request(leaving)
    == connection_support.leave_asked()
    as "the run of the tutorial's map (world 3460) is asked to take the player out"
  let #(state, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(map_id, place, alive) = join_of(taken: joining)
  assert map_id == MapId(world_id: 426, instance: 0)
    as "WorldLocation2 42074 is in world 426: its map is asked"
  assert alive
  assert_landing(
    place:,
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "the join is at the Northern Wilds landing",
  )
  let #(_, burst) = joined_at(state:, joining:, world: 426)
  assert game_client.without_passive_cast(ids: connection_support.written_ids(
      burst,
    ))
    == game_client.holocrypt_entry_ids()
    as "the entry burst, 0xAD first, with no 0x25E and no 0x35F: the client's game object and its quest log are the same"
  let assert [entered] =
    connection_support.decoded(
      connection_support.written(taken: burst),
      enter_world.message_id,
      enter_world.decode,
    )
  assert entered.world_id == 426
    && entered.position_x == float32.to_bits(4098.16015625)
    && entered.position_y == float32.to_bits(-665.9780883789062)
    && entered.position_z == float32.to_bits(-5165.10009765625)
    as "opcode.0xad: the client enters world 426 at the landing"
}

pub fn the_yes_at_crimson_isle_lands_at_mondos_beachhead_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = departures_support.dominion_seeing(creature_id: crimson_isle)
  let #(state, answered) =
    departures_support.yes(state:, spell4_base_id: crimson_isle_spell4_base)
  assert quest_news(taken: answered)
    == #(
      [
        QuestObjectiveProgress(
          quest_id: 10_530,
          objective_index: 1,
          progress: 1,
        ),
        QuestObjectiveProgress(
          quest_id: 10_530,
          objective_index: 3,
          progress: 1,
        ),
      ],
      [QuestState(quest_id: 10_530, state: 2, objective_id: 0)],
    )
    as "Quest2 10530: the travel (index 1) and the Crimson Isle choice (index 3, QuestObjective 21350) are counted"
  let #(state, leaving) = departures_support.timer_fires(state:)
  let #(state, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(map_id, place, _) = join_of(taken: joining)
  assert map_id == MapId(world_id: 870, instance: 0)
    as "WorldLocation2 8223 is in world 870"
  assert_landing(
    place:,
    world: 870,
    zone: 1236,
    x: -8260.708984375,
    y: -995.0770263671875,
    z: -239.0409393310547,
    reason: "the Crimson Isle terminal lands at WorldLocation2 8223",
  )
  let #(_, burst) = joined_at(state:, joining:, world: 870)
  let assert [entered] =
    connection_support.decoded(
      connection_support.written(taken: burst),
      enter_world.message_id,
      enter_world.decode,
    )
  assert entered.world_id == 870 as "opcode.0xad: the client enters world 870"
}

pub fn a_press_without_the_quest_opens_no_window_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    departures_support.seeing(
      state: connection_support.in_world_as_exile(),
      creature_id: northern_wilds,
    )
  let #(_, pressed) = departures_support.press(state:)
  assert connection_support.written_ids(pressed) == refused_start
    as "opcode.0x7fc: a player without Bon Voyage is refused before any 0x7fd"
  assert departures_support.started_timers(taken: pressed) == []
    as "and no move starts"
}

pub fn no_leaves_the_player_in_the_simulation_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = departures_support.exile_seeing(creature_id: northern_wilds)
  let #(state, pressed) = departures_support.press(state:)
  let #(state, declined) =
    departures_support.answer(
      state:,
      pressed:,
      result: interaction_result.Failed,
      spell4_base_id: northern_wilds_spell4_base,
    )
  assert departures_support.started_timers(taken: declined) == []
    as "opcode.0x805.fields: a No is result 0, which fails the cast: no move starts"
  assert quest_news(taken: declined) == #([], []) as "nothing is counted"
  assert support.asked(declined) == option.None
    as "the map is not asked to take the player out"
  let #(_, again) = departures_support.press(state:)
  assert connection_support.written_ids(again) == confirmed_start
    as "the travel is still open: the terminal offers its window again"
}

pub fn a_second_yes_in_state_2_moves_the_player_without_counting_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = departures_support.exile_seeing(creature_id: northern_wilds)
  let #(state, pressed) = departures_support.press(state:)
  let cast_id = departures_support.server_cast_id(pressed:)
  let #(state, first) =
    departures_support.answer_cast(
      state:,
      cast_id:,
      result: interaction_result.Succeeded,
      spell4_base_id: northern_wilds_spell4_base,
    )
  assert departures_support.started_timers(taken: first)
    == [#(departures.timer, 0)]
  let #(state, repeated) =
    departures_support.answer_cast(
      state:,
      cast_id:,
      result: interaction_result.Succeeded,
      spell4_base_id: northern_wilds_spell4_base,
    )
  assert departures_support.started_timers(taken: repeated) == []
    as "the cast is over: the yes for it is dropped and starts no second move"
  assert connection_support.written_ids(repeated) == []
    && quest_news(taken: repeated) == #([], [])
    as "and counts nothing more"
  let #(state, pressed_again) = departures_support.press(state:)
  assert connection_support.written_ids(pressed_again) == confirmed_start
    as "Prerequisite 41793's type 6 condition with value 2: the client offers the terminal to a player whose quest is Achieved, so the press is offered the window"
  let #(state, second) =
    departures_support.answer(
      state:,
      pressed: pressed_again,
      result: interaction_result.Succeeded,
      spell4_base_id: northern_wilds_spell4_base,
    )
  assert connection_support.written_ids(second) == [0x07F4, 0x07FE]
    && quest_news(taken: second) == #([], [])
    as "the travel and the choice are done: the second yes sends the go and the finish and counts nothing (no 0x361, no 0x35c)"
  assert departures_support.started_timers(taken: second)
    == [#(departures.timer, 0)]
    as "and asks for the move"
  let #(state, leaving) = departures_support.timer_fires(state:)
  assert connection_support.ask_request(leaving)
    == connection_support.leave_asked()
    as "the player leaves the tutorial's map"
  let #(_, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(map_id, place, _) = join_of(taken: joining)
  assert map_id == MapId(world_id: 426, instance: 0)
    as "WorldLocation2 42074 is in world 426"
  assert_landing(
    place:,
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "the second yes moves the player to the Northern Wilds landing",
  )
}

pub fn a_completed_quest_lands_at_the_yes_without_a_count_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    departures_support.seeing(
      state: connection_support.in_world_as_exile_holding(quests: [
        quest_support.completed(quest_id: 10_528, at: 7),
      ]),
      creature_id: northern_wilds,
    )
  let #(state, pressed) = departures_support.press(state:)
  assert connection_support.written_ids(pressed) == confirmed_start
    as "Prerequisite 41793's type 6 condition with value 3: the client offers the terminal to a player whose quest is Completed"
  let #(state, answered) =
    departures_support.answer(
      state:,
      pressed:,
      result: interaction_result.Succeeded,
      spell4_base_id: northern_wilds_spell4_base,
    )
  assert connection_support.written_ids(answered) == [0x07F4, 0x07FE]
    && quest_news(taken: answered) == #([], [])
    as "the quest is not in the active list: the yes counts nothing"
  assert departures_support.started_timers(taken: answered)
    == [#(departures.timer, 0)]
    as "and asks for the move"
  let #(state, leaving) = departures_support.timer_fires(state:)
  let #(_, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(map_id, place, _) = join_of(taken: joining)
  assert map_id == MapId(world_id: 426, instance: 0)
    as "WorldLocation2 42074 is in world 426"
  assert_landing(
    place:,
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "the player lands at the Northern Wilds landing",
  )
}

pub fn a_move_sent_before_the_landing_is_dropped_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client keeps the old unit until the join's 0xAD reaches it, and moves it: those
  // frames wait in the bytes read while the leave and the join are asked, and are taken
  // after the join's answer.
  let state = departures_support.exile_seeing(creature_id: northern_wilds)
  let #(state, _) =
    departures_support.yes(state:, spell4_base_id: northern_wilds_spell4_base)
  let #(state, leaving) = departures_support.timer_fires(state:)
  let old_unit_move =
    connection_support.moves_message([
      game_client.position_command(x: 500.0, y: 2.5, z: 500.0),
    ])
  let #(state, _) = connection_support.read(state:, bytes: old_unit_move)
  let #(state, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(state, burst) = joined_at(state:, joining:, world: 426)
  assert !support.stops(burst)
    && support.logs_of(step: burst, level: step.LogError) == []
    as "a move sent before the landing does not end the connection"
  assert connection_support.moves_told(burst) == []
    as "opcode.0x637: the move of the old unit is dropped, and the map is told nothing"
  let #(state, late) = connection_support.read(state:, bytes: old_unit_move)
  assert connection_support.moves_told(late) == []
    as "a move that reaches the server after the burst is dropped too, until the client has loaded the world"
  let #(state, _) =
    connection_support.read(
      state:,
      bytes: connection_support.terrain_loaded_message(648),
    )
  let #(_, moved) =
    connection_support.read(state:, bytes: connection_support.a_move(1.5))
  assert connection_support.moves_told(moved) == [1]
    as "after the first 0xF2 of the stay a move moves the player"
}

pub fn the_tutorials_viewer_sees_the_player_leave_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    connection_support.watched_by(
      state: departures_support.exile_seeing(creature_id: northern_wilds),
      viewers: [2],
    )
  let #(state, _) =
    departures_support.yes(state:, spell4_base_id: northern_wilds_spell4_base)
  let #(_, leaving) = departures_support.timer_fires(state:)
  assert connection_support.news_told(taken: leaving, viewer: 2) == [Removed]
    as "the player's connection tells the viewer in the tutorial the unit's 0x355"
}

pub fn a_relog_after_the_move_enters_at_the_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  // The player says yes, is moved to the landing, loads it, and camps: the save the camp
  // writes holds the landing, whatever the quest log says.
  let state = departures_support.exile_seeing(creature_id: northern_wilds)
  let #(state, _) =
    departures_support.yes(state:, spell4_base_id: northern_wilds_spell4_base)
  let #(state, leaving) = departures_support.timer_fires(state:)
  let #(state, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(state, _) = joined_at(state:, joining:, world: 426)
  let #(state, _) =
    connection_support.read(
      state:,
      bytes: connection_support.terrain_loaded_message(648),
    )
  let #(state, _) =
    connection_support.read(
      state:,
      bytes: connection_support.camp_request_message(True),
    )
  let #(_, saving) =
    connection_support.read(
      state:,
      bytes: connection_support.camp_finished_message(),
    )
  let assert AskStore(request: store.Move(SavePlace(place:, quests:, ..))) =
    connection_support.ask_request(saving)
    as "the camp's end saves the player"
  assert_landing(
    place:,
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "the camp's save is at the Northern Wilds landing, in world 426 and not in the tutorial",
  )
  // A new login of the same character, with what the save wrote.
  let saved =
    Character(
      ..connection_support.world_character(),
      faction_id: spawn.exile_faction,
      place: Some(place),
    )
  let #(state, joining) =
    connection_support.joining_holding(
      in_character_select: connection_support.in_select(),
      character: saved,
      saved_health: option.None,
      saved_experience: option.None,
      quests:,
    )
  let #(map_id, landing, _) = join_of(taken: joining)
  assert map_id == MapId(world_id: 426, instance: 0)
    as "the new login's join is at the Northern Wilds landing's map"
  assert_landing(
    place: landing,
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "the login enters where the save was",
  )
  let #(_, entered) = joined_at(state:, joining:, world: 426)
  let frames = connection_support.written(taken: entered)
  let assert [entering] =
    connection_support.decoded(
      frames,
      enter_world.message_id,
      enter_world.decode,
    )
  assert entering.world_id == 426 as "opcode.0xad: the client enters world 426"
  let assert [log] =
    connection_support.decoded(
      frames,
      quest_log_message.message_id,
      quest_log_message.decode,
    )
    as "a login writes 0x35F"
  let assert [bon_voyage] =
    list.filter(log.active, fn(active: QuestActive) {
      active.quest_id == 10_528
    })
    as "the log holds Bon Voyage"
  assert bon_voyage.state == 2 && bon_voyage.progress == [1, 1, 1, 0, 0]
    as "opcode.0x35f: Bon Voyage is Achieved with the travel 21327 and the choice 21328 counted"
}

pub fn a_landing_map_that_refuses_the_join_returns_to_character_select_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = departures_support.exile_seeing(creature_id: northern_wilds)
  let #(state, _) =
    departures_support.yes(state:, spell4_base_id: northern_wilds_spell4_base)
  let #(state, leaving) = departures_support.timer_fires(state:)
  let #(state, joining) =
    connection_support.answer(
      state:,
      taken: leaving,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(map_id, _, _) = join_of(taken: joining)
  assert map_id == MapId(world_id: 426, instance: 0)
    as "the leave is followed by the join at the landing's map"
  let #(state, refused) =
    connection_support.answer(
      state:,
      taken: joining,
      outcome: step.Answer(
        FromMap(
          map.NotJoined(reason: map.NoLoadout(class_id: 1, faction_id: 166)),
        ),
      ),
    )
  assert connection_support.written_ids(refused) == [0x0594]
    as "the player is in no map: 0x0594 puts the client in character select"
  assert list.length(support.logs_of(step: refused, level: step.LogWarning))
    == 1
    as "the refusal is logged"
  let #(_, listing) =
    connection_support.read(state, connection_support.select_start())
  assert connection_support.ask_request(listing)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "a new character select takes the client's 0x07E0"
}

pub fn a_relog_between_the_yes_and_the_move_enters_at_the_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  // The player says yes and logs out before the 0 ms timer moves it: the save the camp
  // writes holds the quest log with the choice counted and the place in the tutorial.
  let state = departures_support.exile_seeing(creature_id: northern_wilds)
  let #(state, _) =
    departures_support.yes(state:, spell4_base_id: northern_wilds_spell4_base)
  let #(state, _) =
    connection_support.read(
      state:,
      bytes: connection_support.camp_request_message(True),
    )
  let #(_, saving) =
    connection_support.read(
      state:,
      bytes: connection_support.camp_finished_message(),
    )
  let assert AskStore(request: store.Move(SavePlace(place:, quests:, ..))) =
    connection_support.ask_request(saving)
    as "the camp's end saves the player"
  assert start_place.world_id(place) == 3460
    as "the save holds the place in the tutorial"
  // A new login of the same character, with what the save wrote.
  let saved =
    Character(
      ..connection_support.world_character(),
      faction_id: spawn.exile_faction,
      place: Some(place),
    )
  let #(state, joining) =
    connection_support.joining_holding(
      in_character_select: connection_support.in_select(),
      character: saved,
      saved_health: option.None,
      saved_experience: option.None,
      quests:,
    )
  let #(map_id, landing, _) = join_of(taken: joining)
  assert map_id == MapId(world_id: 426, instance: 0)
    as "the new login's join is at the Northern Wilds landing's map"
  assert_landing(
    place: landing,
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "the choice objective 21328 is counted in the log and the saved place is in the tutorial: the login enters at the terminal's landing",
  )
  let #(_, entered) = joined_at(state:, joining:, world: 426)
  let frames = connection_support.written(taken: entered)
  let assert [entering] =
    connection_support.decoded(
      frames,
      enter_world.message_id,
      enter_world.decode,
    )
  assert entering.world_id == 426 as "opcode.0xad: the client enters world 426"
  let assert [log] =
    connection_support.decoded(
      frames,
      quest_log_message.message_id,
      quest_log_message.decode,
    )
    as "a login writes 0x35F"
  let assert [bon_voyage] =
    list.filter(log.active, fn(active: QuestActive) {
      active.quest_id == 10_528
    })
    as "the log holds Bon Voyage"
  assert bon_voyage.state == 2 && bon_voyage.progress == [1, 1, 1, 0, 0]
    as "opcode.0x35f: Bon Voyage is Achieved with the travel 21327 and the choice 21328 counted"
}
