//// The tutorial's projectors on a running game connection: a player presses a projector
//// it holds the quest for, and at the cast's go is moved inside its world to the projector's
//// landing by the client's own placement, 0x83c, 0x639, 0x638 and 0x636
//// (genesis_prime/game/in_world_move). Expected values come from these places:
//// - Creature2 73735, 73741, 73743 and 73745 (the Combat, Housing, Mission and Cryo
////   projectors): the cast time 1000 ms (2000 ms for the Cryo projector) and the link to the
////   objective each projector's Prerequisite gives.
//// - Quest2 10527 (the Exile's Combat Simulation) and 10523 (the Dominion's Cryo): the
////   objectives in slot order, the projector's use the fifth (index 4); Quest2 10540 (the
////   Mission quest): the arrival at the hub, objective 21373, is its index 1.
//// - QuestObjective 21325 (type 12, data 73735): the use of the Combat projector counts.
////   QuestObjective 21373 (type 17, data 4964): the arrival in a zone below 4964.
//// - WorldLocation2 51615, 51616 and 51657: the landings, and WorldZone 5968 below 4964.
//// - `opcode.0x7fd`, `opcode.0x7fc`, `opcode.0x7fe`: the confirmation, the refusal and the
////   finish of a cast, which `opcode.0x83c` stops; `opcode.0x361`: an objective's progress.
//// - `opcode.0x83c`, `opcode.0x639`, `opcode.0x638`, `opcode.0x636`: the placement.
////   `opcode.0x635`: the client gives the value of the 0x636 back, so the 0x637 it sends
////   after it holds the new place; an earlier one comes from the old place.
//// - `opcode.0x63a`: the client reports the zone it stands in.

import connection_rule_support as support
import departures_support
import game_client
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request, AskStore, TellMoved}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/float32
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/quest_abandon.{QuestAbandon}
import genesis_prime/message/quest_objective_progress.{QuestObjectiveProgress}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/step.{
  type ConnectionStep, type TimerId, ConnectionId, OwnEvent, TimerFired,
}
import genesis_prime/store
import genesis_prime/world_map/map.{ObjectsUnseen}
import gleam/list
import owned_test
import place_support
import quest_support

const combat = 73_735

const mission = 73_743

const cryo = 73_745

/// WorldLocation2 51615, Warfare Woods: its facing quaternion is (0, 0xb157d016, 0, 1), a
/// turn of 2 * asin(-3.1404900902032296e-9) about the vertical, which is the yaw below.
fn warfare_woods() -> Place {
  let assert Ok(place) =
    start_place.place(
      world_id: 3460,
      world_zone_id: 5967,
      x: -50.53350067138672,
      y: -861.4010009765625,
      z: 307.8080139160156,
      facing: start_place.Facing(
        yaw: -6.280980180406459e-9,
        pitch: 0.0,
        roll: 0.0,
      ),
    )
    as "the landing's world is not 0"
  place
}

/// The Exile's Combat Simulation (Quest2 10527) with the objectives before the use of the
/// projector done (the first, third and fourth: mask 0b1101), so the use is open.
fn combat_quest() -> store.QuestRow {
  quest_support.active(
    quest_id: 10_527,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: 13,
    progress: [1, 0, 1, 1, 0],
  )
}

/// The Dominion's Cryo quest (Quest2 10523), its fifth objective, 21311, open.
fn dominion_cryo_quest() -> store.QuestRow {
  quest_support.active(
    quest_id: 10_523,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: 13,
    progress: [1, 0, 1, 1, 0],
  )
}

fn exile_before_the_combat_projector() -> game_connection.State {
  departures_support.seeing(
    state: connection_support.in_world_as_exile_holding(quests: [
      combat_quest(),
    ]),
    creature_id: combat,
  )
}

/// The client's 0x97 right-click of the projector, at the connection's clock 0, and the
/// cast timers it starts.
fn pressed(
  state state: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request), List(#(Int, TimerId))) {
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
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: cast_activate.message_id,
          body:,
        )),
      ),
    )
  #(state, started, connection_support.cast_timers(steps: [started], ms: 0))
}

/// The steps the cast's timers take up to `until_ms` after the press.
fn run_to(
  state state: game_connection.State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
) -> #(
  game_connection.State,
  List(#(Int, TimerId)),
  List(ConnectionStep(Request)),
) {
  connection_support.casts_left(state:, pending:, until_ms:, steps: [])
}

fn frames_of(steps steps: List(ConnectionStep(Request))) -> List(Frame) {
  list.flat_map(steps, fn(taken) { connection_support.written(taken:) })
}

fn ids_of(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

/// The position the one 0x638 among the frames puts the player at.
fn placed_at(frames frames: List(Frame)) -> UnitPositionCommand {
  let assert [placement] =
    list.filter(frames, fn(frame) { frame.message_id == 0x0638 })
    as "the move writes one 0x638"
  let assert Ok(moved) = unit_movement.decode(placement.body)
    as "the frame is a 0x638"
  let assert [relayed_movement.Position(position), ..] = moved.commands
    as "the first command is the position"
  position
}

fn bits_of(x x: Float, y y: Float, z z: Float) -> UnitPositionCommand {
  UnitPositionCommand(
    x: float32.to_bits(x),
    y: float32.to_bits(y),
    z: float32.to_bits(z),
    blends: 0,
  )
}

fn told_the_map(
  steps steps: List(ConnectionStep(Request)),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  list.flat_map(steps, connection_support.told_the_map)
}

fn echo_message(echo_value echo_value: Int) -> BitArray {
  let assert Ok(body) =
    client_control_echoed.encode(ClientControlEchoed(echo_value:))
    as "an echo of 32 bits fits"
  connection_support.world_message(
    message_id: client_control_echoed.message_id,
    body:,
  )
}

/// The place the save timer's ask holds.
fn saved_place(state state: game_connection.State) -> Place {
  let #(_, saving) =
    connection_support.feed(
      state:,
      event: OwnEvent(TimerFired(timer: step.TimerId(2))),
    )
  let assert AskStore(store.Move(store.SavePlace(place:, ..))) =
    connection_support.ask_request(saving)
    as "the save timer asks a save"
  place
}

/// WorldLocation2 51616, Solitude of Secrets: its facing is the identity quaternion, which
/// the conversion to angles turns into a yaw of 0, a pitch of -0 and a roll of 0.
fn solitude_of_secrets() -> Place {
  let assert Ok(place) =
    start_place.place(
      world_id: 3460,
      world_zone_id: 5968,
      x: 476.4630126953125,
      y: -393.81201171875,
      z: 254.22799682617188,
      facing: start_place.Facing(yaw: 0.0, pitch: -0.0, roll: 0.0),
    )
    as "the landing's world is not 0"
  place
}

/// An Exile holding the Mission quest (Quest2 10540, no objective done) with the Mission
/// projector in view.
fn exile_before_the_mission_projector() -> game_connection.State {
  departures_support.seeing(
    state: connection_support.in_world_as_exile_holding(quests: [
      quest_support.accepted(quest_id: 10_540, progress: [0, 0, 0]),
    ]),
    creature_id: mission,
  )
}

/// The player after the Mission projector's cast went and moved it. The Mission
/// projector's objective is an arrival, so the use completes no quest and the connection
/// goes on in the world.
fn moved_to_solitude_of_secrets() -> game_connection.State {
  let #(state, _, pending) =
    pressed(state: exile_before_the_mission_projector())
  let #(state, _, _) = run_to(state:, pending:, until_ms: 1000)
  state
}

pub fn the_combat_projector_moves_the_player_to_warfare_woods_at_the_casts_end_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, started, pending) =
    pressed(state: exile_before_the_combat_projector())
  assert list.contains(connection_support.written_ids(started), 0x07FD)
    as "opcode.0x7fd: the press confirms the cast"
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 1000)
  let frames = frames_of(steps:)
  let ids = ids_of(frames:)
  assert list.drop(ids, list.length(ids) - 4)
    == [0x083C, 0x0639, 0x0638, 0x0636]
    as "the placement is the last of the go's frames, in the client's order"
  assert list.contains(ids, 0x07FE) as "opcode.0x7fe: the cast's finish"
  assert connection_support.decoded(
      frames,
      0x0361,
      quest_objective_progress.decode,
    )
    == [
      QuestObjectiveProgress(quest_id: 10_527, objective_index: 4, progress: 1),
    ]
    as "QuestObjective 21325, type 12 data 73735: the use is the fifth objective of Quest2 10527"
  assert placed_at(frames:)
    == UnitPositionCommand(
      x: 0xc24a224e,
      y: 0xc45759aa,
      z: 0x4399e76d,
      blends: 0,
    )
    as "WorldLocation2 51615: the unit stands at Warfare Woods"
  assert told_the_map(steps:)
    == [
      connection_support.map_tell(TellMoved(
        connection: ConnectionId(1),
        place: warfare_woods(),
        seq: 1,
      )),
    ]
    as "the map is told the landing with the move's number"
}

pub fn the_move_is_written_after_the_casts_finish_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _, pending) = pressed(state: exile_before_the_combat_projector())
  let #(state, pending, early) = run_to(state:, pending:, until_ms: 999)
  assert !list.contains(ids_of(frames: frames_of(steps: early)), 0x083C)
    as "no placement before the cast's end"
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 1000)
  let ids = ids_of(frames: frames_of(steps:))
  let position = fn(id) {
    let assert Ok(index) =
      list.index_map(ids, fn(found, index) { #(found, index) })
      |> list.key_find(id)
      as "the frame is written"
    index
  }
  assert position(0x07FE) < position(0x083C)
    as "opcode.0x83c stops the current cast, so the finish is written before it"
}

pub fn the_dominion_cryo_projector_lands_in_the_dominion_pod_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    departures_support.seeing(
      state: connection_support.entered_with_quests(quests: [
        dominion_cryo_quest(),
      ]).0,
      creature_id: cryo,
    )
  let #(state, _, pending) = pressed(state:)
  let #(state, pending, early) = run_to(state:, pending:, until_ms: 1999)
  assert !list.contains(ids_of(frames: frames_of(steps: early)), 0x083C)
    as "Creature2 73745 casts for 2000 ms: no go before"
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 2000)
  assert placed_at(frames: frames_of(steps:))
    == bits_of(x: -3689.68408203125, y: -436.7900390625, z: -4356.00390625)
    as "WorldLocation2 51657: the Dominion's pod"
}

pub fn a_press_without_the_quest_moves_no_one_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    departures_support.seeing(
      state: connection_support.in_world_as_exile_holding(quests: []),
      creature_id: combat,
    )
  let #(state, started, pending) = pressed(state:)
  assert connection_support.written_ids(started) == [0x07FC]
    as "opcode.0x7fc: the press is refused without the quest"
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 5000)
  assert steps == []
  assert connection_support.told_the_map(started) == []
}

pub fn abandoning_the_combat_quest_during_the_cast_is_refused_and_the_move_stands_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _, pending) = pressed(state: exile_before_the_combat_projector())
  let assert Ok(body) = quest_abandon.encode(QuestAbandon(quest_id: 10_527))
    as "a quest id fits the message"
  let #(state, abandoned) =
    connection_support.read(
      state:,
      bytes: connection_support.world_message(
        message_id: quest_abandon.message_id,
        body:,
      ),
    )
  assert connection_support.written_ids(abandoned) == []
    as "Quest2.flags of 10527 holds 0x4000, so CanAbandonQuest (0x140552930) refuses an Active quest: the abandon is dropped and no 0x35C is written"
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 1000)
  let ids = ids_of(frames: frames_of(steps:))
  assert list.contains(ids, 0x083C) && list.contains(ids, 0x0638)
    as "the quest is still held at the go, so the projector moves the player"
  assert told_the_map(steps:) != []
}

pub fn a_projector_gone_from_the_picture_by_the_go_moves_no_one_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _, pending) = pressed(state: exile_before_the_combat_projector())
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(
        ObjectsUnseen(unit_ids: [departures_support.terminal_unit]),
      ),
    )
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 1000)
  let ids = ids_of(frames: frames_of(steps:))
  assert list.contains(ids, 0x07FE)
    as "opcode.0x7fe: the cast ran to its end, so the absences below are the move's and not a cast that never went"
  assert !list.contains(ids, 0x0361) && !list.contains(ids, 0x083C)
    as "a use of a unit the player no longer sees counts for no objective and moves no one"
  assert told_the_map(steps:) == []
}

pub fn a_move_from_before_the_echo_is_dropped_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = moved_to_solitude_of_secrets()
  let #(state, dropped) =
    connection_support.read(
      state:,
      bytes: connection_support.moves_message([
        game_client.position_command(
          x: 30.0,
          y: -853.87158203125,
          z: -560.18798828125,
        ),
      ]),
    )
  assert connection_support.moves_told(dropped) == []
    as "a 0x637 sent from the old place before the client took the placement is no move"
  assert support.effects_of(dropped) == [] as "no viewer is told of it either"
  assert saved_place(state:) == solitude_of_secrets()
    as "the place stays the landing"
  let #(state, _) =
    connection_support.read(state:, bytes: echo_message(echo_value: 1))
  let #(_, moved) =
    connection_support.read(
      state:,
      bytes: connection_support.moves_message([
        game_client.position_command(
          x: 476.4630126953125,
          y: -393.81201171875,
          z: 254.22799682617188,
        ),
      ]),
    )
  assert connection_support.moves_told(moved) == [2]
    as "opcode.0x635: after the echo of the 0x636's value a 0x637 is a move, numbered after the placement's 1"
}

pub fn a_zone_report_after_the_echo_counts_the_landings_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _, pending) =
    pressed(state: exile_before_the_mission_projector())
  let #(state, _, steps) = run_to(state:, pending:, until_ms: 1000)
  assert placed_at(frames: frames_of(steps:))
    == bits_of(x: 476.4630126953125, y: -393.81201171875, z: 254.22799682617188)
    as "WorldLocation2 51616"
  let #(state, _) =
    connection_support.read(state:, bytes: echo_message(echo_value: 1))
  let #(state, _) =
    connection_support.read(
      state:,
      bytes: connection_support.moves_message([
        game_client.position_command(
          x: 476.4630126953125,
          y: -393.81201171875,
          z: 254.22799682617188,
        ),
      ]),
    )
  let #(_, reported) =
    connection_support.read(
      state:,
      bytes: connection_support.zone_changed_message(old: 6009, new: 5968),
    )
  assert connection_support.decoded(
      connection_support.written(taken: reported),
      0x0361,
      quest_objective_progress.decode,
    )
    == [
      QuestObjectiveProgress(quest_id: 10_540, objective_index: 1, progress: 1),
    ]
    as "QuestObjective 21373 (type 17, data 4964): WorldZone 5968 is below 4964, so the arrival counts"
}

pub fn a_save_after_the_move_holds_the_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  assert saved_place(state: moved_to_solitude_of_secrets())
    == solitude_of_secrets()
    as "WorldLocation2 51616: the save writes the movement's place, and no 0x637 has moved it since"
}

pub fn the_entrys_0x635_is_taken_without_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    connection_support.read(
      state: connection_support.in_world(),
      bytes: echo_message(echo_value: 0),
    )
  assert support.logs(taken) == []
    as "opcode.0x635: the client's answer to the entry's 0x636 is taken, so it is no unhandled message"
  assert connection_support.written_ids(taken) == []
  assert connection_support.told_the_map(taken) == []
  assert !support.stops(taken)
}

pub fn a_move_before_the_clients_terrain_is_ready_still_tells_the_map_ready_test() -> Nil {
  use <- owned_test.run(60_000)
  let expected = [
    connection_support.map_tell(client_connection.TellReady(
      connection: ConnectionId(1),
      seq: 1,
    )),
  ]
  // The go runs before the stay's first 0xF2, which then arrives while the placement
  // is not yet echoed.
  let moved = moved_to_solitude_of_secrets()
  let #(state, terrain) =
    connection_support.read(
      state: moved,
      bytes: connection_support.terrain_loaded_message(5968),
    )
  let #(_, echoed) =
    connection_support.read(state:, bytes: echo_message(echo_value: 1))
  assert told_the_map(steps: [terrain, echoed]) == expected
    as "opcode.0xf2 and opcode.0x635 in this order: the map is told ready once, with the move's number"
  // The client answers the placement first and loads its terrain after.
  let #(state, echoed) =
    connection_support.read(state: moved, bytes: echo_message(echo_value: 1))
  let #(state, terrain) =
    connection_support.read(
      state:,
      bytes: connection_support.terrain_loaded_message(5968),
    )
  assert told_the_map(steps: [echoed, terrain]) == expected
    as "opcode.0x635 and opcode.0xf2 in this order: the map is told ready once, with the move's number"
  let #(_, again) =
    connection_support.read(
      state:,
      bytes: connection_support.terrain_loaded_message(5968),
    )
  assert told_the_map(steps: [again]) == []
    as "a second 0xF2 tells the map nothing"
}

pub fn a_creature_fighting_the_player_is_told_the_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    connection_support.feed(
      state: exile_before_the_mission_projector(),
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, _, pending) = pressed(state:)
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 1000)
  assert list.flat_map(steps, connection_support.told_creatures)
    == [
      #(
        7,
        client_connection.TellTargetMoved(
          connection: ConnectionId(1),
          place: solitude_of_secrets(),
          seq: 1,
          stay: connection_support.own_stay(),
          hit_radius: place_support.player_hit_radius,
        ),
      ),
    ]
    as "the fighter holds the landing with the move's number, as it holds each 0x637's place, so it stops striking at the old place"
}

pub fn a_viewer_is_sent_the_move_to_the_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    connection_support.watched_by(
      state: exile_before_the_mission_projector(),
      viewers: [2],
    )
  let #(state, _, pending) = pressed(state:)
  let #(_, _, steps) = run_to(state:, pending:, until_ms: 1000)
  let placement = #(
    2,
    connection_support.moving(
      unit_id: connection_support.own_unit_id,
      server_time_ms: 1000,
      commands: [
        relayed_movement.Position(bits_of(
          x: 476.4630126953125,
          y: -393.81201171875,
          z: 254.22799682617188,
        )),
        // WorldLocation2 51616's identity facing converts to a pitch of -0, whose
        // float32 bits are 0x80000000.
        relayed_movement.Rotation(MovementRotation(
          yaw: 0,
          pitch: 0x80000000,
          roll: 0,
          blends: 0,
        )),
      ],
    ),
  )
  assert list.count(
      list.flat_map(steps, connection_support.peer_tells),
      fn(tell) { tell == placement },
    )
    == 1
    as "opcode.0x638 as the placement writes it, to each player who sees the unit, so it stands at the landing there too"
}
