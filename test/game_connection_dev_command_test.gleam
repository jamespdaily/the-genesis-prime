//// The development commands on the game connection (`genesis_prime/game/connection/dev_command`),
//// run as the pure rule it is: a line said on Say in, the frames and effects out. Expected
//// values come from these places.
//// - `opcode.0x1ac`: the client takes experience only by message, adding the first value to
////   its own; the source kind 1 is Cheat (`opcode.0x1ac.kind.1`). No message lowers it.
//// - `opcode.0x938`: stat 10 is the level. `opcode.0x169`: ability points, 0 for levels 1 to
////   9 (XpPerLevel.abilityPointsPerLevel).
//// - XpPerLevel.minXpForLevel: level 3 from 1710, 4 from 2860, 9 from 17330.
//// - The rise's frames are those of a gain of any source: `experience_book_test` (a Medic's
////   3 to 4 writes 0x1ac, 0x938, 0x111, 0x1a0, 0x93a, with the ability of Spell4Base 26038
////   in slot 4; 5 to 6 adds 25530, 25579 and 38210) and `experience_points_test`.
//// - `SpellLevel.spell4Id.no_prerequisite`: the committed rows hold a Medic's abilities up to
////   level 6 (`ability_book_test`): 614 (level 4, Spell4Base 26038), 1087 (5, 25692), 1191,
////   1194 and 1221 (6, 25530, 25579, 38210). A rise to level 9 grants all five, in that
////   order, in slots 4 to 8 after the bag of 4 items, and one 0x1a0 holds each at tier 1 in
////   the four action sets (`opcode.0x1a0`).
//// - The line each command is answered with is the design's choice (a System line,
////   ChatChannel row 2).

import ability_book_support as book_support
import ability_points_support as points_support
import connection_rule_support as rule_support
import departures_support
import experience_support
import game_client
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{type Request, TellMoved, TellTargetMoved}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/float32
import genesis_prime/message/quest_objective_progress.{
  type QuestObjectiveProgress, QuestObjectiveProgress,
}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/step.{ConnectionId, OwnEffect, OwnEvent, Unwatch, Watch}
import genesis_prime/store
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import place_support
import quest_support

/// A Medic (class 4), level 3, holding 1800 experience: 90 past level 3's 1710.
fn medic() -> game_connection.State {
  dev_support.in_world_at(class_id: 4, level: 3, experience: 1800)
}

/// One raise: the line said, what the frames start and end with, the gain and
/// the levels written, the abilities the rise adds (bag index and Spell4Base, in order),
/// the line answered and what the player holds afterwards.
type Raise {
  Raise(
    text: String,
    starts: List(Int),
    ends: List(Int),
    gain: Int,
    levels: List(Int),
    added: List(#(Int, Int)),
    line: String,
    held: #(Int, Int),
    why: String,
  )
}

pub fn a_raise_writes_the_frames_of_an_experience_gain_and_the_level_rise_then_one_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Raise(
        text: "!level 4",
        starts: [0x01C2, 0x01AC, 0x0938, 0x0111],
        ends: [0x01A0, 0x093A, 0x01C8],
        gain: 1060,
        levels: [4],
        added: [#(4, 26_038)],
        line: "level 4, experience 2860",
        held: #(4, 2860),
        why: "level 4 starts at 2860, 1060 above 1800; the Medic's 3 to 4 adds Spell4Base 26038",
      ),
      Raise(
        text: "!xp 2859",
        starts: [0x01C2, 0x01AC],
        ends: [0x01AC, 0x01C8],
        gain: 1059,
        levels: [],
        added: [],
        line: "level 3, experience 2859",
        held: #(3, 2859),
        why: "2859 is one short of level 4: a gain and no level",
      ),
      Raise(
        text: "!level 9",
        starts: [0x01C2, 0x01AC, 0x0938],
        ends: [0x01A0, 0x093A, 0x01C8],
        gain: 15_530,
        levels: [9],
        added: [
          #(4, 26_038),
          #(5, 25_692),
          #(6, 25_530),
          #(7, 25_579),
          #(8, 38_210),
        ],
        line: "level 9, experience 17330",
        held: #(9, 17_330),
        why: "level 9 starts at 17330: one 0x938 for the whole jump, and the five abilities the rows hold for levels 4 to 6",
      ),
    ],
    fn(row) {
      let #(state, taken) = dev_support.said(state: medic(), text: row.text)
      let ids = support.written_ids(taken)
      assert list.take(ids, list.length(row.starts)) == row.starts as row.why
      assert list.drop(ids, list.length(ids) - list.length(row.ends))
        == row.ends
        as "the frames end with the player's line"
      assert experience_support.gains(taken:)
        == [
          ExperienceGained(
            experience: row.gain,
            rest_experience_used: 0,
            bonus_experience: 0,
            source_kind: 1,
            source_unit_id: 0,
          ),
        ]
        as row.why
      assert list.map(experience_support.level_writes(taken:), fn(written) {
          written.1
        })
        == row.levels
        as row.why
      let frames = book_support.written(taken:)
      let added = book_support.added_in(frames:)
      assert list.map(added, fn(item) { #(item.bag_index, item.base) })
        == row.added
        as "the rise adds exactly the abilities its levels grant, in order, once each"
      assert list.all(added, fn(item) { item.reason == 49 })
        as "opcode.0x111.ability_level_up: reason 49, as the entry's"
      assert book_support.tiers_in(frames:)
        == book_support.tiers_of(
          bases: list.map(row.added, fn(item) { item.1 }),
        )
        as "one 0x1a0 holds each added ability at tier 1 in the four action sets"
      assert points_support.points_in(frames:) == []
        as "levels 1 to 9 give no ability points"
      assert support.system_lines(taken) == [row.line] as row.why
      let #(_, experience, level) = experience_support.camped(state:)
      assert #(level, experience) == row.held
        as "the player holds the level and experience reached"
    },
  )
}

pub fn a_lowering_or_an_equal_target_changes_nothing_and_says_so_in_one_system_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        "!level 2",
        "!level 2 would lower level 3; the client takes experience only upward: use a character at or below level 2",
        "a level below the held 3",
      ),
      #(
        "!xp 1500",
        "!xp 1500 would lower experience 1800; the client takes experience only upward: use a character at or below experience 1500",
        "an experience below the held 1800",
      ),
      #(
        "!xp 1800",
        "already at level 3, experience 1800",
        "the experience held",
      ),
      #(
        "!level 3",
        "already at level 3, experience 1800",
        "the level held, though 1800 is above its 1710",
      ),
    ],
    fn(row) {
      let #(state, taken) = dev_support.said(state: medic(), text: row.0)
      assert support.written_ids(taken) == [0x01C2, 0x01C8]
        as "opcode.0x1ac: no frame lowers the client's experience, so none is written"
      assert support.system_lines(taken) == [row.1] as row.2
      let #(_, experience, level) = experience_support.camped(state:)
      assert #(level, experience) == #(3, 1800) as "nothing changed"
    },
  )
}

pub fn the_next_save_holds_the_commanded_level_and_experience_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = dev_support.said(state: medic(), text: "!level 4")
  let #(_, taken) =
    support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert client_connection.AskStore(store.Move(store.SavePlace(
    experience:,
    level:,
    ..,
  ))) = support.ask_request(taken)
    as "the save timer asks the store to save the place"
  assert #(level, experience) == #(4, 2860)
    as "XpPerLevel: level 4 starts at 2860, which the save keeps"
}

pub fn each_accepted_command_is_logged_once_at_info_and_a_refused_one_not_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, accepted) = dev_support.said(state: medic(), text: "!level 4")
  let assert [line] = rule_support.logs_of(step: accepted, level: step.LogInfo)
    as "one info line for an accepted command"
  assert string.contains(line.text, "!level 4")
    && string.contains(line.text, "experience 1800")
    && string.contains(line.text, "experience 2860")
    as "it names the command and the values it changed"
  let #(_, refused) = dev_support.said(state: medic(), text: "!level 51")
  assert rule_support.logs(refused) == []
    as "a refused command is its System line, with no log"
}

// A `!go`: the placement the client takes as the server's move within a world
// (`opcode.0x83c`, `opcode.0x639`, `opcode.0x638`, `opcode.0x636`, `opcode.0x635`).

/// The tests' player, standing in World 3460 at the place of `world_character()`.
fn camp_player() -> game_connection.State {
  dev_support.in_world_as(
    character: support.world_character(),
    experience: None,
  )
}

/// A place in World 3460.
fn in_camp(zone zone: Int, x x: Float, y y: Float, z z: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: zone, x:, y:, z:)
}

/// WorldLocation2 51615, Warfare Woods, in World 3460: its facing quaternion is
/// (0, 0xb157d016, 0, 1), a turn of 2 * asin(-3.1404900902032296e-9) about the vertical.
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
    as "the row's world is not 0"
  place
}

/// The 32-bit float bits the client's position command carries for a place.
fn position_bits(place place: Place) -> UnitPositionCommand {
  UnitPositionCommand(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
    blends: 0,
  )
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

/// One `!go` in the player's world, with what the player sees of it.
type Placed {
  Placed(
    text: String,
    viewers: List(Int),
    fighter: Bool,
    place: Place,
    line: String,
    why: String,
  )
}

pub fn a_go_in_the_same_world_places_the_player_at_once_and_tells_the_map_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Placed(
        text: "!go 3460 5967 100 -50 200",
        viewers: [],
        fighter: False,
        place: in_camp(zone: 5967, x: 100.0, y: -50.0, z: 200.0),
        line: "moved to world 3460, zone 5967, (100.0, -50.0, 200.0)",
        why: "coordinates: the place is as asked, with the facing the player has",
      ),
      Placed(
        text: "!go 51615",
        viewers: [],
        fighter: False,
        place: warfare_woods(),
        line: "moved to world 3460, zone 5967, (-50.53350067138672, -861.4010009765625, 307.8080139160156)",
        why: "WorldLocation2 51615: a named place is the row's own world, zone, position and facing",
      ),
      Placed(
        text: "!go 3460 5967 100 -50 200",
        viewers: [2],
        fighter: True,
        place: in_camp(zone: 5967, x: 100.0, y: -50.0, z: 200.0),
        line: "moved to world 3460, zone 5967, (100.0, -50.0, 200.0)",
        why: "a viewer is sent the move and a fighter is told the place",
      ),
    ],
    fn(row) {
      let state = support.watched_by(state: camp_player(), viewers: row.viewers)
      let state = case row.fighter {
        True ->
          support.feed(
            state:,
            event: support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
          ).0
        False -> state
      }
      let #(state, taken) = dev_support.said(state:, text: row.text)
      let frames = support.written(taken:)
      assert support.written_ids(taken)
        == [0x01C2, 0x083C, 0x0639, 0x0638, 0x0636, 0x01C8]
        as "the answer to the line, the client's placement, then the system line"
      assert placed_at(frames:) == position_bits(place: row.place) as row.why
      assert support.decoded(frames, 0x0636, client_control_granted.decode)
        == [
          ClientControlGranted(
            echo_value: 1,
            reset_movement: 1,
            unit_id: support.own_unit_id,
          ),
        ]
        as "opcode.0x636: the echo is the next move number, 1, and the player's own unit takes control back"
      assert support.system_lines(taken) == [row.line] as row.why
      assert support.told_the_map(taken)
        == [
          support.map_tell(TellMoved(
            connection: ConnectionId(1),
            place: row.place,
            seq: 1,
          )),
        ]
        as "the map is told the move with the echo's number"
      assert list.count(support.peer_tells(taken), fn(tell) {
          list.contains(row.viewers, tell.0)
        })
        == list.length(row.viewers)
        as "opcode.0x638: each player who sees the unit is sent the move"
      assert support.told_creatures(taken)
        == case row.fighter {
          True -> [
            #(
              7,
              TellTargetMoved(
                connection: ConnectionId(1),
                place: row.place,
                seq: 1,
                stay: support.own_stay(),
                hit_radius: place_support.player_hit_radius,
              ),
            ),
          ]
          False -> []
        }
        as "a creature fighting the player is told the place"
      assert list.length(rule_support.logs_of(step: taken, level: step.LogInfo))
        == 1
        as "one info line for the accepted command"
      assert dev_support.saved_place(state:) == row.place
        as "the next save holds the commanded place"
      let #(state, dropped) =
        support.read(
          state,
          support.moves_message([
            game_client.position_command(
              x: 29.128599166870117,
              y: -853.87158203125,
              z: -560.18798828125,
            ),
          ]),
        )
      assert rule_support.effects_of(dropped) == []
        as "a 0x637 sent from the old place before the client took the placement is no move"
      assert dev_support.saved_place(state:) == row.place
        as "and it moves nothing"
    },
  )
}

/// A 0x635, the client's answer to the 0x636.
fn echo_message(echo_value echo_value: Int) -> BitArray {
  let assert Ok(body) =
    client_control_echoed.encode(ClientControlEchoed(echo_value:))
    as "an echo of 32 bits fits"
  support.world_message(message_id: client_control_echoed.message_id, body:)
}

pub fn a_second_go_after_the_echo_is_numbered_after_the_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = dev_support.said(state: camp_player(), text: "!go 51615")
  let #(state, _) = support.read(state, echo_message(echo_value: 1))
  let #(_, taken) = dev_support.said(state:, text: "!go 3460 5967 1 2 3")
  assert support.moves_told(taken) == [2]
    as "the connection counts its moves: the second placement is 2"
}

/// What a zone report after a `!go` into a zone leaves.
type Reported {
  Reported(
    commanded: Int,
    reported: Int,
    held: Int,
    written: List(Int),
    groups: List(step.ConnectionEffect(Request)),
    progress: List(QuestObjectiveProgress),
    why: String,
  )
}

pub fn the_zone_the_client_reports_after_a_go_replaces_the_commanded_one_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Reported(
        commanded: 648,
        reported: 648,
        held: 648,
        written: [0x01DA],
        groups: [
          step.LeaveGroup(support.zone_group(4961)),
          step.JoinGroup(support.zone_group(35)),
        ],
        progress: [],
        why: "the report of the commanded zone changes the place's zone to itself, and the chat group follows it from the old top zone 4961 to 35, as the client's own move would",
      ),
      Reported(
        commanded: 648,
        reported: 5968,
        held: 5968,
        written: [0x0361, 0x035C],
        groups: [],
        progress: [
          QuestObjectiveProgress(
            quest_id: 10_540,
            objective_index: 1,
            progress: 1,
          ),
        ],
        why: "the client's own zone replaces the commanded one in the place, and settles the objectives on it: WorldZone 5968 is below 4964, so the arrival counts",
      ),
    ],
    fn(row) {
      let state =
        support.entered_under(
          settings: support.settings_with_dev_commands(),
          character: store.Character(
            ..support.world_character(),
            faction_id: spawn.exile_faction,
          ),
          quests: [
            quest_support.accepted(quest_id: 10_540, progress: [0, 0, 0]),
          ],
        ).0
      let #(state, _) =
        dev_support.said(
          state:,
          text: "!go 3460 " <> int.to_string(row.commanded) <> " 1 2 3",
        )
      assert start_place.world_zone_id(dev_support.saved_place(state:))
        == row.commanded
        as "the `!go` itself sets only the place's zone"
      let #(state, _) = support.read(state, echo_message(echo_value: 1))
      let #(state, reported) =
        support.read(
          state,
          support.zone_changed_message(old: row.commanded, new: row.reported),
        )
      assert support.written_ids(reported) == row.written as row.why
      assert list.filter_map(rule_support.effects_of(reported), fn(effect) {
          case effect {
            OwnEffect(step.JoinGroup(address:)) -> Ok(step.JoinGroup(address:))
            OwnEffect(step.LeaveGroup(address:)) ->
              Ok(step.LeaveGroup(address:))
            OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
              Error(Nil)
          }
        })
        == row.groups
        as row.why
      assert support.decoded(
          support.written(taken: reported),
          0x0361,
          quest_objective_progress.decode,
        )
        == row.progress
        as row.why
      assert start_place.world_zone_id(dev_support.saved_place(state:))
        == row.held
        as row.why
    },
  )
}

pub fn a_go_settles_the_objectives_at_the_new_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    support.entered_under(
      settings: support.settings_with_dev_commands(),
      character: store.Character(
        ..support.world_character(),
        faction_id: spawn.exile_faction,
      ),
      quests: [quest_support.accepted(quest_id: 10_540, progress: [0, 0, 0])],
    ).0
  let #(_, taken) = dev_support.said(state:, text: "!go 3460 5968 1 2 3")
  let frames = support.written(taken:)
  assert support.decoded(frames, 0x0361, quest_objective_progress.decode)
    == [
      QuestObjectiveProgress(quest_id: 10_540, objective_index: 1, progress: 1),
    ]
    as "QuestObjective 21373 (type 17, data 4964): the commanded zone 5968 is below 4964, so the arrival counts at the `!go`, not only at the client's next report"
  assert support.written_ids(taken)
    == [0x01C2, 0x083C, 0x0639, 0x0638, 0x0636, 0x01C8, 0x0361, 0x035C]
    as "the objectives are settled after the placement and its line"
}

/// An Exile holding the Combat Simulation (Quest2 10527) with its projector, Creature2 73735,
/// in view, made with the development commands on: pressing the projector starts a cast.
fn exile_before_the_combat_projector() -> game_connection.State {
  departures_support.seeing(
    state: support.entered_under(
      settings: support.settings_with_dev_commands(),
      character: store.Character(
        ..support.world_character(),
        faction_id: spawn.exile_faction,
      ),
      quests: [
        quest_support.active(
          quest_id: 10_527,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 13,
          progress: [1, 0, 1, 1, 0],
        ),
      ],
    ).0,
    creature_id: 73_735,
  )
}

pub fn a_go_stops_the_cast_in_progress_before_the_placement_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: departures_support.clients_cast_id,
      target_unit_id: departures_support.terminal_unit,
    ))
    as "the message fits"
  let #(state, pressed) =
    support.at(
      state: exile_before_the_combat_projector(),
      ms: 0,
      event: OwnEvent(
        step.Read(support.world_message(
          message_id: cast_activate.message_id,
          body: press,
        )),
      ),
    )
  assert list.contains(support.written_ids(pressed), 0x07FD)
    as "opcode.0x7fd: the press confirms the cast, which runs 1000 ms"
  let #(_, went) =
    support.at(
      state:,
      ms: 500,
      event: OwnEvent(
        step.Read(support.chat_line_message(4, "!go 3460 5967 1 2 3")),
      ),
    )
  let ids = support.written_ids(went)
  let position = fn(id) {
    let assert Ok(index) =
      list.index_map(ids, fn(found, index) { #(found, index) })
      |> list.key_find(id)
      as "the frame is written"
    index
  }
  assert position(0x07FE) < position(0x083C)
    as "opcode.0x83c stops the current cast, so its finish is written before the placement"
  assert support.cast_timers(steps: [pressed, went], ms: 0) == []
    as "the cast's go and finish timers are cancelled: the projector's own move never comes"
}

pub fn a_go_is_refused_while_the_player_is_dead_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #("!go 3460 5967 100 -50 200", "the player's world"),
      #("!go 870 1227 -7700 -941 -659", "another world"),
    ],
    fn(row) {
      let #(state, _) = support.killed(camp_player())
      let before = dev_support.saved_place(state:)
      let #(state, taken) = dev_support.said(state:, text: row.0)
      assert support.written_ids(taken) == [0x01C2, 0x01C8] as row.1
      assert support.system_lines(taken)
        == ["!go is refused while the player is dead"]
        as row.1
      assert rule_support.asked(taken) == None as "no ask is made"
      assert support.told_the_map(taken) == [] as row.1
      assert dev_support.saved_place(state:) == before
        as "the departures' move refuses a dead player the same way: nothing changed"
    },
  )
}

pub fn a_go_the_tables_refuse_never_leaves_the_map_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        "!go 99999 1189 0 0 0",
        "!go: World 99999 is not in the client's tables",
        "a world with no row: the client's load fails on it (opcode.0xad)",
      ),
      #(
        "!go 3460 6009 99999 0 0",
        "!go: x 99999 is outside -32768 to 32768",
        "a position outside the box the client clamps to",
      ),
    ],
    fn(row) {
      let state = camp_player()
      let before = dev_support.saved_place(state:)
      let #(state, taken) = dev_support.said(state:, text: row.0)
      assert support.written_ids(taken) == [0x01C2, 0x01C8] as row.2
      assert support.system_lines(taken) == [row.1] as row.2
      assert rule_support.asked(taken) == None as "no Leave is asked"
      assert support.told_the_map(taken) == [] as row.2
      assert dev_support.saved_place(state:) == before as "nothing changed"
    },
  )
}

pub fn a_go_to_another_world_is_refused_with_one_line_until_it_is_built_test() -> Nil {
  use <- owned_test.run(60_000)
  let origin =
    place_support.at(world_id: 22, world_zone_id: 1189, x: 1.0, y: 2.0, z: 3.0)
  let state = dev_support.in_world_at_place(place: origin)
  let #(state, taken) =
    dev_support.said(state:, text: "!go 870 1227 -7700 -941 -659")
  assert support.written_ids(taken) == [0x01C2, 0x01C8]
    as "the line is answered with one system line and nothing else"
  assert support.system_lines(taken) == ["!go to another world is not built"]
  assert rule_support.asked(taken) == None as "no Leave is asked"
  assert support.told_the_map(taken) == []
  assert rule_support.logs(taken) == [] as "a refused command writes no log"
  assert dev_support.saved_place(state:) == origin as "nothing changed"
}
