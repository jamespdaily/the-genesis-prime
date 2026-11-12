//// The activate cast on a running game connection: the map tells the connection which static
//// objects its player sees (`ObjectsSeen`), and the player's 0x97 right-click of one is
//// taken from the bytes to the cast rule. Expected values come from these places:
//// - `opcode.0x262`: the unit's creature id, place and display come from the object's 0x262.
//// - Creature2DisplayInfo 25703 (the Seaspine Mollusk's display) hitRadius 1.0, row 21397
////   hitRadius 2.0, Race 1 hitRadius 1.2: the edge of each unit the range is held to.
//// - Creature2 26462: activateSpellMaxRange 3.0, and its activate spell 1817 behind Prerequisite
////   9358, which a player with no challenge record passes.
//// - `opcode.0x97`: the message is the client's cast id and the unit; the client's cast id 0 is
////   refused by the client's own sender, so the connection ends.
//// - `opcode.0x7fd` and `opcode.0x7fc`: the caster is written a confirmation of a started cast
////   and a refusal of one that is not.
//// - Creature2 73605, the Departures Terminal: activateSpellCastTime 0, activate spell 34681,
////   Spell4Base 20651 of castMethod 5.
//// - `opcode.0x805` and `opcode.0x7f4`: the client's answer 1 to its interaction is followed
////   by the server's go and finish.
//// - Creature2 8047: activateSpellCastTime 0, activate spell 5725 (Spell4Base 5020 of castMethod 1;
////   channelInitialDelay 0, channelMaxTime 3000, channelPulseTime 2999), `cast.channel_sequence`:
////   the channel's last go comes before its finish.

import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/routing
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_result
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/interaction_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/step
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature_life
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/map.{ObjectsSeen}
import genesis_prime/world_map/static_object.{type Created, StaticObject}
import gleam/list
import gleam/option
import owned_test
import quest_support
import spawn_support
import vendor_support

const mollusk_display = 25_703

const display_of_radius_2 = 21_397

const nearby = 5000

const too_far_for_a_small_radius = 5001

const with_a_big_radius = 5002

const clients_cast_id = 9

/// The place `east` units east of where the tests' player stands (`entry_place`): the same
/// height and zone, so the gap between two units' edges is the distance less their radii.
fn east_of_the_player(east east: Float) -> Place {
  connection_support.standing_at(
    x: 29.128599166870117 +. east,
    y: -853.87158203125,
    z: -560.18798828125,
  )
}

/// A Seaspine Mollusk (Creature2 26462) as unit `unit_id`, `east` units east of the player,
/// shown with the display row.
fn mollusk(
  unit_id unit_id: Int,
  east east: Float,
  display display: Int,
) -> Created {
  static_object.create(
    object: StaticObject(
      ..spawn_support.holoring(
        number: unit_id,
        place: east_of_the_player(east:),
      ),
      creature_id: Creature2Id(26_462),
      display_info_id: display,
    ),
    unit_id:,
    server_time_estimate_start: 0,
  )
}

/// The bytes of the client's 0x97 right-click of `unit_id`, inside the client's 0x038C.
fn right_click_bytes(
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
) -> BitArray {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(client_cast_id:, target_unit_id: unit_id))
    as "the message fits"
  connection_support.world_message(message_id: cast_activate.message_id, body:)
}

/// The connection's player has seen the three mollusks of the tests.
fn seeing_three_mollusks() -> game_connection.State {
  let #(state, _) =
    connection_support.feed(
      connection_support.in_world(),
      connection_support.sent_by_the_map(
        ObjectsSeen(units: [
          mollusk(unit_id: nearby, east: 5.0, display: mollusk_display),
          mollusk(
            unit_id: too_far_for_a_small_radius,
            east: 6.0,
            display: mollusk_display,
          ),
          mollusk(
            unit_id: with_a_big_radius,
            east: 6.0,
            display: display_of_radius_2,
          ),
        ]),
      ),
    )
  state
}

/// The ids of the frames the right-click of `unit_id` writes to its player.
fn written_by_the_click(unit_id unit_id: Int) -> List(Int) {
  let #(_, taken) =
    connection_support.read(
      state: seeing_three_mollusks(),
      bytes: right_click_bytes(client_cast_id: clients_cast_id, unit_id:),
    )
  connection_support.written_ids(taken)
}

const confirmed_start = [0x07FD]

const refused_start = [0x07FC]

pub fn objects_seen_hold_creature_place_and_radius_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 26462's activateSpellMaxRange is 3.0, so the cast starts when the gap between
  // the player's edge and the object's is 3.0 or less. The player's radius is Race 1's 1.2.
  assert written_by_the_click(unit_id: nearby) == confirmed_start
    as "opcode.0x262: the object's creature (26462: Prerequisite 9358 passes, spell 1817) and its place (5.0 east) reach the picture; the gap is 5.0 - 1.2 - 1.0 = 2.8 for display 25703's hitRadius 1.0, within 3.0"
  assert written_by_the_click(unit_id: too_far_for_a_small_radius)
    == refused_start
    as "the same object 6.0 east is 6.0 - 1.2 - 1.0 = 3.8 away: out of the creature's 3.0, refused (TargetRangeMax)"
  assert written_by_the_click(unit_id: with_a_big_radius) == confirmed_start
    as "6.0 east with display 21397's hitRadius 2.0 is 6.0 - 1.2 - 2.0 = 2.8 away: the display's own hit radius reaches the picture"
}

pub fn activate_frame_reaches_the_cast_rule_test() -> Nil {
  use <- owned_test.run(10_000)
  assert routing.route(
      routing.AtWorld,
      routing.InsideWorldMessage,
      cast_activate.message_id,
    )
    == Ok(routing.Activation)
    as "opcode.0x97: a 0x97 inside 0x038C is the activation row in the world"
  let #(_, taken) =
    connection_support.read(
      state: seeing_three_mollusks(),
      bytes: right_click_bytes(client_cast_id: clients_cast_id, unit_id: nearby),
    )
  let confirmations: List(Frame) =
    list.filter(
      connection_support.heard(taken:, cipher: connection_support.keyed()),
      fn(frame) { frame.message_id == spell_cast_confirmed.message_id },
    )
  let assert [confirmed] = confirmations
    as "the bytes of a 0x97 to the running connection give one 0x7fd"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed.body)
  assert confirmed.client_cast_id == clients_cast_id
    && confirmed.primary_target_unit_id == nearby
    as "opcode.0x97: the confirmation answers the client's cast id and names the unit"
  let #(_, ended) =
    connection_support.read(
      state: seeing_three_mollusks(),
      bytes: right_click_bytes(client_cast_id: 0, unit_id: nearby),
    )
  assert option.is_some(support.asked(ended))
    as "opcode.0x97: the client never sends cast id 0, so the connection ends, and a connection with a player in the world saves its place first (an ask of the store)"
  assert connection_support.written_ids(ended) == []
    as "nothing is written to the client on the way out"
  assert list.length(support.logs_of(step: ended, level: step.LogError)) == 1
    as "the end is logged once as an error with the refusal's own words"
}

/// The Departures Terminal (Creature2 73605) as unit `nearby`, 3.0 east of the player.
fn terminal() -> Created {
  static_object.create(
    object: StaticObject(
      ..spawn_support.holoring(
        number: nearby,
        place: east_of_the_player(east: 3.0),
      ),
      creature_id: Creature2Id(73_605),
      display_info_id: mollusk_display,
    ),
    unit_id: nearby,
    server_time_estimate_start: 0,
  )
}

pub fn an_interaction_answer_reaches_the_cast_rule_test() -> Nil {
  use <- owned_test.run(10_000)
  assert routing.route(
      routing.AtWorld,
      routing.InsideWorldMessage,
      client_side_interaction_result.message_id,
    )
    == Ok(routing.Cast(message: cast.Answered))
    as "opcode.0x805: a 0x805 inside 0x038C is a cast row in the world"
  // The terminal's Prerequisite 41793 (the objective 1 of quest 10528 open, or quest
  // 10528 in state 2 or 3) is its anim prerequisite column, so the client offers it
  // only to a player whose objective 1 of quest 10528 is open, and the player here holds
  // the quest Accepted with objective 0 done.
  let #(seeing, _) =
    connection_support.feed(
      connection_support.in_world_as_exile_holding(quests: [
        quest_support.active(
          10_528,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 1,
          progress: [1, 0, 0, 0, 0],
        ),
      ]),
      connection_support.sent_by_the_map(ObjectsSeen(units: [terminal()])),
    )
  let #(clicked, started) =
    connection_support.read(
      state: seeing,
      bytes: right_click_bytes(client_cast_id: clients_cast_id, unit_id: nearby),
    )
  assert connection_support.written_ids(started) == confirmed_start
    as "opcode.0x7fd.csi: the right-click of the terminal writes the start, and no go yet: the cast waits for the client's answer"
  let assert [confirmed] =
    list.filter(
      connection_support.heard(
        taken: started,
        cipher: connection_support.keyed(),
      ),
      fn(frame) { frame.message_id == spell_cast_confirmed.message_id },
    )
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed.body)
  let assert Ok(body) =
    client_side_interaction_result.encode(ClientSideInteractionResult(
      cast_id: confirmed.server_cast_id,
      result: interaction_result.Succeeded,
      spell4_base_id_plus_one: 20_652,
    ))
    as "the answer fits the message"
  let #(_, answered) =
    connection_support.read(
      state: clicked,
      bytes: connection_support.world_message(
        message_id: client_side_interaction_result.message_id,
        body:,
      ),
    )
  assert connection_support.written_ids(answered)
    == [0x07F4, 0x07FE, 0x0361, 0x0361, 0x035C]
    as "opcode.0x805, opcode.0x7f4: the answer 1 sends the go and the finish to the player, and the terminal's travel and choice objectives count (QuestObjective.type.23): two progress frames and the quest's state"
}

/// Creature2 11070, a Trapped Survivor: activate spell 1817 behind its quest's link,
/// activateSpellMaxRange 5.0. Creature2DisplayGroupEntry 24099 puts it on
/// Creature2DisplayInfo 24086, whose hitRadius is 1.4.
const survivor = 11_070

const survivors_display = 24_086

const survivors_radius = 1.4

/// The connection of a player whose quest 3480 is accepted with nothing counted: the link
/// of Creature2 11070 (Prerequisite 2672) is open.
fn holding_quest_3480() -> game_connection.State {
  connection_support.entered_with_quests(quests: [
    quest_support.accepted(quest_id: 3480, progress: [0, 0]),
  ]).0
}

/// The 0x262 news of a Trapped Survivor as unit `unit_id`, standing `gap` from the
/// player's edge straight ahead of the player and hostile to the factions `hostile_to`.
fn survivor_appears(
  unit_id unit_id: Int,
  gap gap: Float,
  hostile_to hostile_to: creature_life.Hostile,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  connection_support.creature_appears(
    unit_id:,
    creature_id: survivor,
    display_info_id: survivors_display,
    outfit_info_id: 0,
    hit_radius: survivors_radius,
    place: vendor_support.ahead_of_the_player(
      hit_radius: survivors_radius,
      gap:,
    ),
    hostile_to:,
  )
}

fn unhostile() -> creature_life.Hostile {
  creature_life.Hostile(exile: False, dominion: False)
}

/// The connection after this news of the unit.
fn told(
  state state: game_connection.State,
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> game_connection.State {
  told_writing(state:, unit_id:, news:).0
}

/// The connection after this news of the unit, and the ids of the frames it wrote.
fn told_writing(
  state state: game_connection.State,
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> #(game_connection.State, List(Int)) {
  let #(state, taken) =
    connection_support.feed(
      state:,
      event: connection_support.news_sent_by_a_peer(unit_id:, news:),
    )
  #(state, connection_support.written_ids(taken))
}

/// The step of the player's right-click of the unit at the monotonic time `ms`.
fn pressed(
  state state: game_connection.State,
  unit_id unit_id: Int,
  at ms: Int,
) -> step.ConnectionStep(client_connection.Request) {
  connection_support.at(
    state:,
    ms:,
    event: step.OwnEvent(
      step.Read(right_click_bytes(client_cast_id: clients_cast_id, unit_id:)),
    ),
  ).1
}

pub fn an_activate_cast_judges_a_creature_where_its_path_puts_it_now_test() -> Nil {
  use <- owned_test.run(10_000)
  let standing =
    connection_support.feed(
      state: holding_quest_3480(),
      event: survivor_appears(
        unit_id: nearby,
        gap: 3.0,
        hostile_to: unhostile(),
      ),
    ).0
  assert connection_support.written_ids(pressed(
      state: standing,
      unit_id: nearby,
      at: 0,
    ))
    == confirmed_start
    as "opcode.0x262: the creature stands 3.0 from the player's edge, within Creature2 11070's activateSpellMaxRange 5.0, so the cast starts"
  let far =
    vendor_support.ahead_of_the_player(hit_radius: survivors_radius, gap: 8.0)
  let #(moved, placed) =
    told_writing(
      state: standing,
      unit_id: nearby,
      news: client_connection.CreaturePlaced(place: far, at_ms: 0),
    )
  assert placed == [0x0638]
    as "opcode.0x638: the news that puts the creature at 8.0 is written to the client, which moves its unit there"
  assert connection_support.refusal_results(taken: pressed(
      state: moved,
      unit_id: nearby,
      at: 0,
    ))
    == [cast_result.TargetRangeMax]
    as "0x1403b2240 judges range against the client's unit, which the server's 0x638 moved to 8.0 from the edge: 105"
  let #(running, run_written) =
    told_writing(
      state: moved,
      unit_id: nearby,
      news: client_connection.CreatureMoved(path: creature_path.Running(
        from: far,
        to: vendor_support.ahead_of_the_player(
          hit_radius: survivors_radius,
          gap: 1.0,
        ),
        started_ms: 0,
        speed: 1.0,
      )),
    )
  assert run_written == [0x0638]
    as "opcode.0x638: the path the creature runs is written to the client, which moves its unit along it"
  assert connection_support.refusal_results(taken: pressed(
      state: running,
      unit_id: nearby,
      at: 2000,
    ))
    == [cast_result.TargetRangeMax]
    as "2.0 s into a run of 1.0 a second from 8.0 the creature is 6.0 away: still out of range"
  assert connection_support.written_ids(pressed(
      state: running,
      unit_id: nearby,
      at: 4000,
    ))
    == confirmed_start
    as "4.0 s into the run it is 4.0 away: the picture's path puts it within the 5.0, and the cast starts"
}

pub fn the_picture_gives_an_activate_cast_the_creatures_life_combat_and_disposition_test() -> Nil {
  use <- owned_test.run(10_000)
  let dead = 41
  let fighting = 42
  let enemy = 43
  let state =
    list.fold(
      [
        #(dead, unhostile()),
        #(fighting, unhostile()),
        #(enemy, creature_life.Hostile(exile: False, dominion: True)),
      ],
      holding_quest_3480(),
      fn(state, creature) {
        connection_support.feed(
          state:,
          event: survivor_appears(
            unit_id: creature.0,
            gap: 1.0,
            hostile_to: creature.1,
          ),
        ).0
      },
    )
  let state = told(state:, unit_id: dead, news: client_connection.Died)
  assert connection_support.refusal_results(taken: pressed(
      state:,
      unit_id: dead,
      at: 0,
    ))
    == [cast_result.TargetCannotBeDead]
    as "Spell4 1817's target row refuses a dead target: Died news reaches the cast rule as 106"
  let state =
    told(
      state:,
      unit_id: fighting,
      news: client_connection.CombatState(in_combat: True),
    )
  assert connection_support.refusal_results(taken: pressed(
      state:,
      unit_id: fighting,
      at: 0,
    ))
    == [cast_result.TargetIsNotUseable]
    as "0x14047a060: a unit in combat offers no click: the CombatState news reaches the cast rule as 100"
  let state =
    told(
      state:,
      unit_id: fighting,
      news: client_connection.CombatState(in_combat: False),
    )
  assert connection_support.written_ids(pressed(
      state:,
      unit_id: fighting,
      at: 0,
    ))
    == confirmed_start
    as "the combat ended with the next CombatState: the unit is usable again"
  assert connection_support.refusal_results(taken: pressed(
      state:,
      unit_id: enemy,
      at: 0,
    ))
    == [cast_result.TargetIsNotUseable]
    as "0x14047a060 withholds the click of a unit Hostile to the player's faction (the tests' player is a Dominion one): 100"
}

/// A Scanning Crystal (Creature2 8047) as unit `nearby`, 1.0 east of the player.
fn crystal() -> Created {
  static_object.create(
    object: StaticObject(
      ..spawn_support.holoring(
        number: nearby,
        place: east_of_the_player(east: 1.0),
      ),
      creature_id: Creature2Id(8047),
      display_info_id: mollusk_display,
    ),
    unit_id: nearby,
    server_time_estimate_start: 0,
  )
}

pub fn using_a_channel_creature_sends_both_gos_before_the_finish_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 8047 casts Spell4 5725, a channel of 3000 ms whose go count the client keeps for an
  // activate cast (`0x14053d1f0.activate_channel`): the gos are at 0 and 2999 ms, and the
  // cast finishes at channelMaxTime, 3000 ms (`cast.channel_sequence`). The clock is the
  // test's: the press is at 1000 ms.
  // The crystal's anim-state link is Prerequisite 1276 (a type 6 condition on quest 2570 in
  // state 1), so the client offers it to a player who holds quest 2570 accepted.
  let #(seeing, _) =
    connection_support.feed(
      connection_support.in_world_as_exile_holding(quests: [
        quest_support.accepted(quest_id: 2570, progress: [0]),
      ]),
      connection_support.sent_by_the_map(ObjectsSeen(units: [crystal()])),
    )
  let #(pressed, started) =
    connection_support.at(
      state: seeing,
      ms: 1000,
      event: step.OwnEvent(
        step.Read(right_click_bytes(
          client_cast_id: clients_cast_id,
          unit_id: nearby,
        )),
      ),
    )
  assert connection_support.written_ids(started) == [0x07FD, 0x07F4]
    as "the confirmation, then the first go at 0 ms"
  let pending = connection_support.cast_timers(steps: [started], ms: 1000)
  let #(waiting, pending, early) =
    connection_support.casts_left(
      state: pressed,
      pending:,
      until_ms: 3998,
      steps: [],
    )
  assert early == []
    as "nothing is written before the second go: no go and no 0x7fe"
  let #(went, pending, second) =
    connection_support.casts_left(
      state: waiting,
      pending:,
      until_ms: 3999,
      steps: [],
    )
  assert list.map(second, connection_support.written_ids) == [[0x07F4]]
    as "the second go at 2999 ms after the accept, alone"
  let #(_, pending, last) =
    connection_support.casts_left(
      state: went,
      pending:,
      until_ms: 4000,
      steps: [],
    )
  assert list.map(last, connection_support.written_ids) == [[0x07FE]]
    as "the finish at 3000 ms after the accept"
  assert pending == [] as "nothing is left to fire"
}

pub fn a_cast_go_firing_while_the_place_is_saving_is_taken_once_the_save_is_answered_test() -> Nil {
  use <- owned_test.run(10_000)
  // The channel of the test above: the second go and the finish are the cast's two timers,
  // due at 3999 and 4000 ms by the test's clock. The periodic save timer (60,000 ms) fires
  // between the press and them, so the connection waits on the store when they fire: the
  // player is still in the world, so the cast goes on once the save is answered.
  let #(seeing, _) =
    connection_support.feed(
      connection_support.in_world_as_exile_holding(quests: [
        quest_support.accepted(quest_id: 2570, progress: [0]),
      ]),
      connection_support.sent_by_the_map(ObjectsSeen(units: [crystal()])),
    )
  let #(pressed, started) =
    connection_support.at(
      state: seeing,
      ms: 1000,
      event: step.OwnEvent(
        step.Read(right_click_bytes(
          client_cast_id: clients_cast_id,
          unit_id: nearby,
        )),
      ),
    )
  let pending = connection_support.cast_timers(steps: [started], ms: 1000)
  assert list.length(pending) == 2
    as "the second go and the finish are the cast's timers"
  let #(saving, saves) =
    connection_support.at(
      state: pressed,
      ms: 2000,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert option.Some(_) = support.asked(saves)
    as "the save timer asks the store to save the place"
  let #(saving, fired) =
    list.fold(pending, #(saving, []), fn(so_far, due) {
      let #(state, steps) = so_far
      let #(state, taken) =
        connection_support.at(
          state:,
          ms: due.0,
          event: step.OwnEvent(step.TimerFired(due.1)),
        )
      #(state, [taken, ..steps])
    })
  assert list.all(fired, fn(taken) {
    !support.stops(taken)
    && connection_support.written_ids(taken) == []
    && support.logs_of(step: taken, level: step.LogError) == []
  })
    as "the cast's timers firing while the place saves end nothing and write nothing yet"
  let #(_, answered) =
    connection_support.answer(
      state: saving,
      taken: saves,
      outcome: connection_support.place_saved(),
    )
  assert connection_support.written_ids(answered) == [0x07F4, 0x07FE]
    as "once the save is answered the second go and the finish are written, as at 2999 and 3000 ms"
}
