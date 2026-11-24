//// What the player's movement keeps and refuses (genesis_prime/game/movement),
//// as pure rules: a state and the commands of a 0x637 in, the new state or a
//// refusal out. Expected values come from these places.
//// - The fact `opcode.0x637`: the position kept is the last kind 2 sent while
////   kind 1 is 0, and a kind 2 sent while kind 1 names a platform unit is in
////   that unit's frame, so it is no world position. The client sends only the
////   commands that changed, so the last kind 1 stands until a new one comes.
//// - The fact `movement_command.position_bound`: the client starts each frame
////   from its unit's clamped drawn position, x and z within +-32768 and y within
////   +-2048, and raises a height below -2048 to -2048 before it sends, so it
////   never sends one in the world's frame; x and z beyond the box and y above
////   2048 reach the server by up to one frame's movement.
//// - The facts `movement_command.kind_24` and `movement_command.kind_27`: the
////   client's own builders send state flags in bits 0 to 17 only (up to 0x3ffff)
////   and a mode of 0, 1 or 3.
//// - The fact `0x140c45dd0`: the move speed setting holds 0 to 2.
//// - The fact `opcode.0x637.sent_kinds`: the client's 0x637 carries only kinds
////   0, 1, 2, 3, 8, 10, 11, 13, 14, 18, 20, 24, 25 and 27. The facts
////   `opcode.0x637.kinds_3_to_6`, `opcode.0x637.kinds_10_13`,
////   `opcode.0x637.kind_18`, `opcode.0x637.kind_20` and `opcode.0x637.kind_25`:
////   the values it writes in kinds 3, 10, 13, 18, 20 and 25.
//// - The fact `0x140c1f070`: each command's kind and layout, so which record is
////   which kind. The fact `0x140715350`: kind 14 is yaw, pitch and roll.
//// - IEEE 754 binary32: an exponent of all ones is infinity (0x7F800000,
////   0xFF800000) or not a number (0x7FC00000, 0x7F800001); 1.0 is 0x3F800000,
////   2.0 is 0x40000000 and -3.0 is 0xC0400000.

import character_support
import genesis_prime/client_connection.{Unwritten}
import genesis_prime/game/limited_action_set
import genesis_prime/game/movement.{
  type Command, type Refusal, type State, BelowTheWorld, Fault, Mode, Moves,
  NotFinite, NotWritten, Note, Other, Position, Rotation, Standing, StateFlags,
  UnknownMode, UnknownSpeedSetting, UnknownStateFlags, Unsent, UnsentKind,
}
import genesis_prime/game/start_place.{type Facing, Facing}
import genesis_prime/message/float32
import genesis_prime/message/movement_command.{type MovementCommand}
import genesis_prime/message/movement_face_point.{MovementFacePoint}
import genesis_prime/message/movement_face_unit.{MovementFaceUnit}
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_half_vector.{MovementHalfVector}
import genesis_prime/message/movement_kind_10.{MovementKind10}
import genesis_prime/message/movement_kind_12.{MovementKind12}
import genesis_prime/message/movement_kind_13.{MovementKind13}
import genesis_prime/message/movement_kind_15.{MovementKind15}
import genesis_prime/message/movement_kind_16.{MovementKind16}
import genesis_prime/message/movement_kind_17.{MovementKind17}
import genesis_prime/message/movement_kind_20.{MovementKind20}
import genesis_prime/message/movement_kind_21.{MovementKind21}
import genesis_prime/message/movement_kind_22.{MovementKind22}
import genesis_prime/message/movement_kind_23.{MovementKind23}
import genesis_prime/message/movement_kind_25.{MovementKind25}
import genesis_prime/message/movement_kind_26.{MovementKind26}
import genesis_prime/message/movement_kind_28.{MovementKind28}
import genesis_prime/message/movement_kind_29.{MovementKind29}
import genesis_prime/message/movement_kind_3.{MovementKind3}
import genesis_prime/message/movement_kind_4.{MovementKind4}
import genesis_prime/message/movement_kind_5.{MovementKind5}
import genesis_prime/message/movement_kind_6.{MovementKind6}
import genesis_prime/message/movement_kind_7.{MovementKind7}
import genesis_prime/message/movement_kind_9.{MovementKind9}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_move_asked.{MovementMoveAsked}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_velocity.{MovementVelocity}
import genesis_prime/message/player_movement.{PlayerMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/store.{
  AccountId, ActionSetRefused, CharacterId, ExperienceRefused, HealthRefused,
  NothingSaved, PlaceRefused, PlaceSaved, SavePlace,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import place_support

/// The infinity, minus infinity and not-a-number patterns of a 32-bit float.
const not_finite = [0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001]

/// The refusal of a value of a command's kind that the client never writes: the
/// shared one, with the kind in its field's words.
fn unwritten(kind kind: Int, field field: String, value value: Int) -> Refusal {
  NotWritten(Unwritten(
    message_id: 0x0637,
    field: "kind " <> int.to_string(kind) <> "'s " <> field,
    value:,
  ))
}

/// A player who entered World 3460, zone 6009, at (1.0, 2.0, 3.0), facing
/// 0, 0, 0, as the login whose epoch is 3.
fn entered() -> State {
  movement.entered(
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 1.0,
      y: 2.0,
      z: 3.0,
    ),
    session_epoch: character_support.epoch(3),
  )
}

/// The 32 bits of a float the test writes.
fn single(value: Float) -> float32.Bits {
  raw(float32.to_bits(value))
}

/// 32 bits by their number, which may be a pattern no finite float has.
fn raw(number: Int) -> float32.Bits {
  let assert Ok(bits) = float32.bits(number) as "the test's pattern is 32 bits"
  bits
}

fn position(x x: Float, y y: Float, z z: Float) -> Command {
  Position(x: single(x), y: single(y), z: single(z))
}

fn rotation(yaw yaw: Float, pitch pitch: Float, roll roll: Float) -> Command {
  Rotation(yaw: single(yaw), pitch: single(pitch), roll: single(roll))
}

fn footing(unit_id: Int) -> Command {
  let assert Ok(footing) = movement.footing(unit_id)
    as "the test's id is 32 bits"
  Standing(footing:)
}

/// What the commands do to the state, with the clock 0x1234.
fn moved(
  state state: State,
  commands commands: List(Command),
) -> Result(State, Refusal) {
  movement.moved(state:, moves: Moves(client_clock: 0x1234, commands:))
}

/// The state after commands that are all kept.
fn kept(state state: State, commands commands: List(Command)) -> State {
  let assert Ok(state) = moved(state:, commands:)
    as "the client's own commands are not refused"
  state
}

/// Where the state says the player stands.
fn at(state: State) -> #(Float, Float, Float) {
  let place = movement.place(state)
  #(start_place.x(place), start_place.y(place), start_place.z(place))
}

fn faces(state: State) -> Facing {
  movement.facing(state)
}

// ---- test 6: which position is kept ----

pub fn the_position_kept_is_the_last_kind_2_sent_while_kind_1_is_0_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    kept(state: entered(), commands: [
      position(x: 10.5, y: -20.25, z: 30.0),
      position(x: 11.5, y: -21.25, z: 31.0),
    ])
  assert at(state) == #(11.5, -21.25, 31.0)
    as "opcode.0x637: the last kind 2 of the message, with kind 1 at 0, is the position kept"
  let place = movement.place(state)
  assert start_place.world_id(place) == 3460
    && start_place.world_zone_id(place) == 6009
    as "the world and the zone are the player's, which a move never changes"
  let state =
    kept(state:, commands: [footing(0), position(x: 5.0, y: 6.0, z: 7.0)])
  assert at(state) == #(5.0, 6.0, 7.0)
    as "kind 1 naming no unit is the world's frame, so its position is kept"
}

pub fn a_message_with_no_position_leaves_the_place_test() -> Nil {
  use <- owned_test.run(5000)
  let state = kept(state: entered(), commands: [Other(0), Other(8), Other(11)])
  assert at(state) == #(1.0, 2.0, 3.0)
    as "opcode.0x637: only the commands that changed are sent, so a message without kind 2 changes no position"
  assert faces(state) == start_place.unturned
}

pub fn a_position_sent_under_a_platform_is_in_that_units_frame_and_is_not_kept_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    kept(state: entered(), commands: [
      footing(0x01020304),
      position(x: 10.0, y: 20.0, z: 30.0),
    ])
  assert at(state) == #(1.0, 2.0, 3.0)
    as "opcode.0x637: a kind 2 while kind 1 names a platform unit is in that unit's frame, not a world position"
}

// ---- test 14a: the footing is state ----

pub fn the_last_kind_1_stands_across_messages_and_a_position_or_rotation_is_kept_only_in_the_worlds_frame_test() -> Nil {
  use <- owned_test.run(5000)
  let state = kept(state: entered(), commands: [footing(7)])
  let state =
    kept(state:, commands: [
      position(x: 50.0, y: 60.0, z: 70.0),
      rotation(yaw: 1.5, pitch: 0.5, roll: 0.25),
    ])
  assert at(state) == #(1.0, 2.0, 3.0)
    as "opcode.0x637: the client sends only what changed, so a message with no kind 1 is still under the platform the last one named"
  assert faces(state) == start_place.unturned
    as "the rotation of kind 14 is in the unit's frame too, so it is kept only with the position"
  let state =
    kept(state:, commands: [
      footing(0),
      position(x: 8.0, y: 9.0, z: 10.0),
      rotation(yaw: 1.5, pitch: 0.5, roll: 0.25),
    ])
  assert at(state) == #(8.0, 9.0, 10.0)
  assert faces(state) == Facing(yaw: 1.5, pitch: 0.5, roll: 0.25)
    as "back on the world, both are kept"
  let state = kept(state:, commands: [position(x: 12.0, y: 13.0, z: 14.0)])
  assert at(state) == #(12.0, 13.0, 14.0)
    as "and the world's frame stands for the later messages too"
}

pub fn a_height_below_minus_2048_in_a_platforms_frame_is_neither_kept_nor_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    kept(state: entered(), commands: [
      footing(7),
      position(x: 0.0, y: -3000.0, z: 0.0),
    ])
  assert at(state) == #(1.0, 2.0, 3.0)
    as "movement_command.position_bound clamps the unit's world height, not a position in a platform's frame, which a platform high above the floor can put below -2048"
}

// ---- test 7: what a position may not be ----

pub fn a_position_that_is_not_finite_is_refused_in_each_axis_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(not_finite, fn(pattern) {
    let bad = raw(pattern)
    let good = single(1.0)
    list.each(
      [
        Position(x: bad, y: good, z: good),
        Position(x: good, y: bad, z: good),
        Position(x: good, y: good, z: bad),
      ],
      fn(command) {
        assert moved(state: entered(), commands: [command])
          == Error(NotFinite(kind: 2))
          as "IEEE 754 binary32: infinity and not-a-number are no position, which the client's own movement never sends"
      },
    )
  })
}

pub fn a_position_or_rotation_that_is_not_finite_is_refused_under_a_platform_too_test() -> Nil {
  use <- owned_test.run(5000)
  let bad = raw(0x7FC00000)
  let good = single(1.0)
  assert moved(state: entered(), commands: [
      footing(7),
      Position(x: bad, y: good, z: good),
    ])
    == Error(NotFinite(kind: 2))
    as "IEEE 754 binary32: not-a-number is no position in any frame, and the client's own movement never sends one, so the platform's frame does not excuse it"
  assert moved(state: entered(), commands: [
      footing(7),
      Rotation(yaw: good, pitch: bad, roll: good),
    ])
    == Error(NotFinite(kind: 14))
    as "IEEE 754 binary32: not-a-number is no rotation in any frame, a platform's included"
}

pub fn a_height_below_minus_2048_is_refused_and_minus_2048_and_above_are_kept_test() -> Nil {
  use <- owned_test.run(5000)
  assert moved(state: entered(), commands: [
      position(x: 0.0, y: -2048.5, z: 0.0),
    ])
    == Error(BelowTheWorld(y: -2048.5))
    as "movement_command.position_bound: the client raises a height below -2048 to -2048 before it sends, so it never sends one"
  let state =
    kept(state: entered(), commands: [position(x: 0.0, y: -2048.0, z: 0.0)])
  assert at(state) == #(0.0, -2048.0, 0.0)
    as "-2048 is what the client sends at the bottom"
}

pub fn x_and_z_beyond_32768_and_y_above_2048_are_kept_as_sent_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    kept(state: entered(), commands: [
      position(x: 40_000.0, y: 3000.0, z: -40_000.0),
    ])
  assert at(state) == #(40_000.0, 3000.0, -40_000.0)
    as "movement_command.position_bound: the client sends them by up to one frame's movement past the box, so refusing them would refuse its own moves at the edge, and how far one frame goes is not read"
  let state =
    kept(state:, commands: [
      position(x: 1.7014118346046923e38, y: 0.0, z: -1.7014118346046923e38),
    ])
  assert at(state) == #(1.7014118346046923e38, 0.0, -1.7014118346046923e38)
    as "any finite float is kept: 2^127, 0x7F000000, is one a 32-bit float holds exactly"
}

pub fn a_refused_message_keeps_nothing_of_itself_test() -> Nil {
  use <- owned_test.run(5000)
  let state = entered()
  assert result.is_error(
    moved(state:, commands: [
      position(x: 9.0, y: 9.0, z: 9.0),
      Position(x: raw(0x7FC00000), y: single(0.0), z: single(0.0)),
    ]),
  )
    as "the second command is refused"
  assert at(state) == #(1.0, 2.0, 3.0)
    as "the state the rule goes on with is the one before the message: the earlier command of the same message is not kept"
}

// ---- test 14a: the rotation ----

pub fn a_rotation_that_is_not_finite_is_refused_in_each_angle_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(not_finite, fn(pattern) {
    let bad = raw(pattern)
    let good = single(0.5)
    list.each(
      [
        Rotation(yaw: bad, pitch: good, roll: good),
        Rotation(yaw: good, pitch: bad, roll: good),
        Rotation(yaw: good, pitch: good, roll: bad),
      ],
      fn(command) {
        assert moved(state: entered(), commands: [command])
          == Error(NotFinite(kind: 14))
          as "IEEE 754 binary32: the client turns the unit by these angles, and its own movement never sends one that is not a number"
      },
    )
  })
}

pub fn the_rotation_kept_is_the_last_kind_14_in_the_worlds_frame_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    kept(state: entered(), commands: [
      rotation(yaw: 0.25, pitch: 0.0, roll: 0.0),
      rotation(yaw: -3.0, pitch: 0.5, roll: -0.125),
    ])
  assert faces(state) == Facing(yaw: -3.0, pitch: 0.5, roll: -0.125)
    as "0x140715350: kind 14 is yaw, pitch and roll in radians; the last one stands"
  assert at(state) == #(1.0, 2.0, 3.0)
}

// ---- test 8: state flags and mode ----

pub fn state_flags_above_0x3ffff_are_refused_and_up_to_it_are_kept_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([0, 1, 0x3FFFF], fn(flags) {
    assert result.is_ok(moved(state: entered(), commands: [StateFlags(flags:)]))
      as "movement_command.kind_24: the client's builders send bits 0 to 17"
  })
  list.each([0x40000, 0x80000000, 0xFFFFFFFF], fn(flags) {
    assert moved(state: entered(), commands: [StateFlags(flags:)])
      == Error(UnknownStateFlags(flags:))
      as "movement_command.kind_24: a bit above 17 is one no builder of the client sets"
  })
}

pub fn a_mode_other_than_0_1_and_3_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([0, 1, 3], fn(mode) {
    assert result.is_ok(moved(state: entered(), commands: [Mode(mode:)]))
      as "movement_command.kind_27: the client sends 0, 1 or 3"
  })
  list.each([2, 4, 31, 0xFFFFFFFF], fn(mode) {
    assert moved(state: entered(), commands: [Mode(mode:)])
      == Error(UnknownMode(mode:))
      as "movement_command.kind_27: no other mode is sent"
  })
}

// ---- test 9: the move speed setting ----

pub fn a_move_speed_setting_above_2_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([0, 1, 2], fn(setting) {
    assert movement.speed_setting(setting) == Ok(Nil)
      as "0x140c45dd0: the setting holds 0 to 2"
  })
  list.each([3, 255, 0xFFFFFFFF], fn(setting) {
    assert movement.speed_setting(setting)
      == Error(UnknownSpeedSetting(setting:))
      as "0x140c45dd0: a value above 2 is none the client's setting has"
  })
}

pub fn every_refusal_is_described_for_the_log_by_what_the_client_sent_test() -> Nil {
  use <- owned_test.run(5000)
  assert movement.describe(NotFinite(kind: 2))
    == "0x0637 holds a position that is not finite"
  assert movement.describe(NotFinite(kind: 14))
    == "0x0637 holds a rotation that is not finite"
  assert movement.describe(BelowTheWorld(y: -2048.5))
    == "0x0637 holds a height of -2048.5, below -2048"
  assert movement.describe(UnknownStateFlags(flags: 0x40000))
    == "0x0637 holds state flags 0x40000, above 0x3ffff"
  assert movement.describe(UnknownMode(mode: 2))
    == "0x0637 holds the mode 2, none of 0, 1 and 3"
  assert movement.describe(UnknownSpeedSetting(setting: 3))
    == "0x063B holds the move speed setting 3, above 2"
}

// ---- the kinds and values the client's own code never sends ----

/// One command of each kind the client never sends, as a decoded 0x637 holds
/// it, with its kind. The fields do not matter: the kind is what is refused.
fn unsent_kinds() -> List(#(Int, MovementCommand)) {
  let half = MovementHalfVector(x: 0, y: 0, z: 0)
  let float = MovementFloatVector(x: 0, y: 0, z: 0)
  [
    #(
      4,
      movement_command.Kind4(MovementKind4(
        points: [float],
        speed: 0,
        path_type: 0,
        mode: 0,
        time_offset: 0,
        blends: 0,
      )),
    ),
    #(
      5,
      movement_command.Kind5(MovementKind5(
        spline_id: 1,
        speed: 0,
        start_position: 0,
        offset_x: 0,
        offset_y: 0,
        offset_z: 0,
        mode: 0,
        time_offset: 0,
        blends: 0,
        unread_11: 0,
        unread_12: 0,
      )),
    ),
    #(
      6,
      movement_command.Kind6(MovementKind6(
        spline_ids: [1],
        speed: 0,
        start_position: 0,
        takeoff_height: 0,
        landing_height: 0,
        offset_x: 0,
        offset_y: 0,
        offset_z: 0,
        mode: 0,
        time_offset: 0,
        chain_flags: 0,
        blends: 0,
        unread_14: 0,
      )),
    ),
    #(
      7,
      movement_command.Kind7(MovementKind7(
        end_x: 0,
        end_y: 0,
        end_z: 0,
        start_x: 0,
        start_y: 0,
        start_z: 0,
        flight_time_ms: 0,
        gravity: 0,
        time_offset: 0,
        blends: 0,
      )),
    ),
    #(
      9,
      movement_command.Kind9(MovementKind9(
        times: [1],
        velocities: [half],
        path_type: 0,
        time_offset: 0,
        blends: 0,
      )),
    ),
    #(
      12,
      movement_command.Kind12(MovementKind12(
        times: [1],
        moves_asked: [half],
        path_type: 0,
        time_offset: 0,
        blends: 0,
      )),
    ),
    #(
      15,
      movement_command.Kind15(MovementKind15(
        times: [1],
        rotations: [float],
        path_type: 0,
        time_offset: 0,
        blends: 0,
      )),
    ),
    #(
      16,
      movement_command.Kind16(MovementKind16(
        spline_id: 1,
        speed: 0,
        start_position: 0,
        mode: 0,
        time_offset: 0,
        blends: 0,
        unread_8: 0,
      )),
    ),
    #(
      17,
      movement_command.Kind17(MovementKind17(
        spline_ids: [1],
        speed: 0,
        start_position: 0,
        takeoff_height: 0,
        landing_height: 0,
        mode: 0,
        time_offset: 0,
        chain_flags: 0,
        blends: 0,
      )),
    ),
    #(
      19,
      movement_command.FacePoint(MovementFacePoint(x: 0, y: 0, z: 0, blends: 0)),
    ),
    #(21, movement_command.Kind21(MovementKind21(blends: 0))),
    #(22, movement_command.Kind22(MovementKind22(scale: 0, blends: 0))),
    #(
      23,
      movement_command.Kind23(MovementKind23(
        times: [1],
        scales: [0],
        path_type: 0,
        time_offset: 0,
        blends: 0,
      )),
    ),
    #(26, movement_command.Kind26(MovementKind26(blends: 0))),
    #(
      28,
      movement_command.Kind28(MovementKind28(
        times: [1],
        modes: [0],
        time_offset: 0,
      )),
    ),
    #(29, movement_command.Kind29(MovementKind29(unread_2: 0))),
  ]
}

pub fn a_command_kind_the_clients_code_never_sends_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.map(unsent_kinds(), fn(row) { row.0 })
    == [4, 5, 6, 7, 9, 12, 15, 16, 17, 19, 21, 22, 23, 26, 28, 29]
    as "opcode.0x637.sent_kinds: the 16 kinds the client's 0x637 never carries"
  list.each(unsent_kinds(), fn(row) {
    let #(kind, command) = row
    let moves =
      movement.moves(
        PlayerMovement(client_clock: 0x1234, commands: [
          movement_command.Position(UnitPositionCommand(
            x: 0x41200000,
            y: 0x41200000,
            z: 0x41200000,
            blends: 0,
          )),
          command,
        ]),
      )
    assert movement.moved(state: entered(), moves:) == Error(UnsentKind(kind:))
      as "opcode.0x637.sent_kinds: the kind is refused, and the position before it is not kept"
  })
}

/// What the entered player's movement makes of one decoded command, taken
/// through `movement.moves` as the connection takes a 0x637, so each field of
/// the record reaches the rule in its own place.
fn alone(command: MovementCommand) -> Result(State, Refusal) {
  let moves =
    movement.moves(PlayerMovement(client_clock: 0x1234, commands: [command]))
  movement.moved(state: entered(), moves:)
}

/// A kind 3 of `points` points, whose times and points the rule does not read.
fn flight_path(
  points points: Int,
  path_type path_type: Int,
  time_offset time_offset: Int,
  blends blends: Int,
) -> MovementCommand {
  movement_command.Kind3(MovementKind3(
    times: list.repeat(1, points),
    points: list.repeat(MovementFloatVector(x: 0, y: 0, z: 0), points),
    path_type:,
    time_offset:,
    blends:,
  ))
}

/// A kind 25 with one key for each flags word given, at the time offset given.
fn timed_flags(
  state_flags state_flags: List(Int),
  time_offset time_offset: Int,
) -> MovementCommand {
  movement_command.Kind25(MovementKind25(
    times: list.map(state_flags, fn(_) { 1 }),
    state_flags:,
    time_offset:,
  ))
}

/// A kind 20 whose yaw, pitch and duration are values the rule does not read
/// and that differ from each other and from the three it checks.
fn spin(
  roll roll: Int,
  time_offset time_offset: Int,
  blends blends: Int,
  turn_rate turn_rate: Int,
) -> MovementCommand {
  movement_command.Kind20(MovementKind20(
    yaw: 0x3F800000,
    pitch: 0x3F000001,
    roll:,
    duration_ms: 1500,
    turn_rate:,
    time_offset:,
    blends:,
  ))
}

pub fn a_flight_path_with_a_value_the_client_never_writes_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      flight_path(points: 2, path_type: 1, time_offset: 0, blends: 0),
      unwritten(kind: 3, field: "path type", value: 1),
      "opcode.0x637.kinds_3_to_6: the flight's path type is 0",
    ),
    #(
      flight_path(points: 2, path_type: 0, time_offset: 7, blends: 0),
      unwritten(kind: 3, field: "time offset", value: 7),
      "opcode.0x637.kinds_3_to_6: the flight's time offset is 0",
    ),
    #(
      flight_path(points: 2, path_type: 0, time_offset: 0, blends: 1),
      unwritten(kind: 3, field: "blend", value: 1),
      "opcode.0x637.kinds_3_to_6: the flight's blend bit is 0",
    ),
    #(
      timed_flags(state_flags: [0x100, 0x4], time_offset: 0),
      unwritten(kind: 25, field: "state flags", value: 0x4),
      "opcode.0x637.kind_25: 0x4 is a flag a kind 24 holds, and none of the four words kind 25 writes",
    ),
    #(
      timed_flags(state_flags: [0x10C], time_offset: 0),
      unwritten(kind: 25, field: "state flags", value: 0x10C),
      "opcode.0x637.kind_25: 0x100 and 0xc together mix two of the words: the words are a set, not a mask",
    ),
    #(
      timed_flags(state_flags: [0x100], time_offset: 7),
      unwritten(kind: 25, field: "time offset", value: 7),
      "opcode.0x637.kind_25: the flags' time offset is 0",
    ),
  ]
  list.each(rows, fn(row) {
    let #(command, refusal, why) = row
    assert alone(command) == Error(refusal) as why
  })
}

pub fn a_follow_path_face_unit_or_spin_with_a_value_the_client_never_writes_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      movement_command.Kind10(MovementKind10(blends: 1)),
      unwritten(kind: 10, field: "blend", value: 1),
      "opcode.0x637.kinds_10_13: the bit is always 0",
    ),
    #(
      movement_command.Kind13(MovementKind13(blends: 1)),
      unwritten(kind: 13, field: "blend", value: 1),
      "opcode.0x637.kinds_10_13: the bit is always 0",
    ),
    #(
      movement_command.FaceUnit(MovementFaceUnit(unit_id: 9, blends: 0)),
      unwritten(kind: 18, field: "blend", value: 0),
      "opcode.0x637.kind_18: the bit is always 1",
    ),
    #(
      spin(roll: 0x3F000002, time_offset: 0, blends: 0, turn_rate: 5),
      unwritten(kind: 20, field: "roll", value: 0x3F000002),
      "opcode.0x637.kind_20: DirectionToEulerAngles' roll is 0",
    ),
    #(
      spin(roll: 0, time_offset: 7, blends: 0, turn_rate: 5),
      unwritten(kind: 20, field: "time offset", value: 7),
      "opcode.0x637.kind_20: the offset is 0",
    ),
    #(
      spin(roll: 0, time_offset: 0, blends: 1, turn_rate: 5),
      unwritten(kind: 20, field: "blend", value: 1),
      "opcode.0x637.kind_20: the bit is 0",
    ),
  ]
  list.each(rows, fn(row) {
    let #(command, refusal, why) = row
    assert alone(command) == Error(refusal) as why
  })
}

/// One of each command the client sends, in the form it writes it, as a
/// decoded 0x637 holds it, with what the row is.
fn sent_forms() -> List(#(String, MovementCommand)) {
  let flight = fn(points) {
    flight_path(points:, path_type: 0, time_offset: 0, blends: 0)
  }
  let flags = fn(keys, words) {
    timed_flags(
      state_flags: list.take(list.flatten(list.repeat(words, keys)), keys),
      time_offset: 0,
    )
  }
  let turning = fn(turn_rate) {
    spin(roll: 0, time_offset: 0, blends: 0, turn_rate:)
  }
  [
    #("kind 0", movement_command.Time(MovementTime(time: 0x1335))),
    #("kind 1", movement_command.Platform(MovementPlatform(unit_id: 7))),
    #(
      "kind 2",
      movement_command.Position(UnitPositionCommand(
        x: 0x3F800000,
        y: 0x40000000,
        z: 0xC0400000,
        blends: 1,
      )),
    ),
    #("kind 3 with 1 point", flight(1)),
    #("kind 3 with 1023 points", flight(1023)),
    #("kind 25 with 1 key", flags(1, [0x100])),
    #("kind 25 with 255 keys", flags(255, [0x100, 0x130, 0xC, 0x3C])),
    #("kind 25 with 0x130", flags(1, [0x130])),
    #("kind 25 with 0xc", flags(1, [0xC])),
    #("kind 25 with 0x3c", flags(1, [0x3C])),
    #(
      "kind 8",
      movement_command.Velocity(MovementVelocity(
        x: 0x3C00,
        y: 0,
        z: 0x4000,
        blends: 1,
      )),
    ),
    #("kind 10", movement_command.Kind10(MovementKind10(blends: 0))),
    #(
      "kind 11",
      movement_command.MoveAsked(MovementMoveAsked(
        x: 0,
        y: 0,
        z: 0x4400,
        blends: 0,
      )),
    ),
    #("kind 13", movement_command.Kind13(MovementKind13(blends: 0))),
    #(
      "kind 14",
      movement_command.Rotation(MovementRotation(
        yaw: 0x3F800000,
        pitch: 0,
        roll: 0,
        blends: 1,
      )),
    ),
    #(
      "kind 18",
      movement_command.FaceUnit(MovementFaceUnit(unit_id: 9, blends: 1)),
    ),
    #("kind 20 with a turn rate", turning(0x0001)),
    #("kind 20 with a turn rate of 0", turning(0)),
    #(
      "kind 24",
      movement_command.StateFlags(MovementStateFlags(flags: 0x3FFFF)),
    ),
    #("kind 27", movement_command.Mode(MovementMode(mode: 3))),
  ]
}

pub fn each_kind_the_client_sends_in_its_own_form_is_taken_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(sent_forms(), fn(row) {
    let #(name, command) = row
    let moves =
      movement.moves(PlayerMovement(client_clock: 0x1234, commands: [command]))
    assert result.is_ok(movement.moved(state: entered(), moves:))
      as {
        name
        <> ": the client writes this form (opcode.0x637.sent_kinds, and the kind's record)"
      }
  })
}

pub fn the_sentence_describing_an_unsent_kinds_refusal_names_the_kind_test() -> Nil {
  use <- owned_test.run(5000)
  assert movement.describe(UnsentKind(kind: 4))
    == "0x0637 holds a command of kind 4, which the client never sends"
}

// ---- test 15: the client's clock ----

pub fn the_clock_of_the_message_and_the_time_command_change_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let commands = [Other(0), position(x: 5.0, y: 6.0, z: 7.0)]
  let early =
    movement.moved(state: entered(), moves: Moves(client_clock: 0, commands:))
  let late =
    movement.moved(
      state: entered(),
      moves: Moves(client_clock: 0xFFFFFFFF, commands:),
    )
  assert early == late && result.is_ok(early)
    as "0x140c3a004, 0x14057a190: the clock is the client's own milliseconds, so no value of it is early or late against the server's"
  let from_message = fn(clock, time) {
    movement.moves(
      PlayerMovement(client_clock: clock, commands: [
        movement_command.Time(MovementTime(time:)),
      ]),
    )
  }
  assert from_message(5, 99) == Moves(client_clock: 5, commands: [Other(0)])
    as "kind 0's time is read and not kept: it is the client's clock too"
}

// ---- the commands of a decoded 0x637 ----

pub fn the_commands_of_a_decoded_message_are_the_rules_commands_by_kind_test() -> Nil {
  use <- owned_test.run(5000)
  let one = 0x3F800000
  let two = 0x40000000
  let minus_three = 0xC0400000
  let commands = [
    movement_command.Time(MovementTime(time: 0x1335)),
    movement_command.Platform(MovementPlatform(unit_id: 0x01020304)),
    movement_command.Position(UnitPositionCommand(
      x: one,
      y: two,
      z: minus_three,
      blends: 1,
    )),
    movement_command.Rotation(MovementRotation(
      yaw: minus_three,
      pitch: one,
      roll: two,
      blends: 0,
    )),
    movement_command.StateFlags(MovementStateFlags(flags: 0x2A)),
    movement_command.Mode(MovementMode(mode: 3)),
    movement_command.Kind29(MovementKind29(unread_2: 9)),
    movement_command.Platform(MovementPlatform(unit_id: 0)),
  ]
  let moves = movement.moves(PlayerMovement(client_clock: 0x1234, commands:))
  assert moves.client_clock == 0x1234
  assert moves.commands
    == [
      Other(0),
      footing(0x01020304),
      Position(x: raw(one), y: raw(two), z: raw(minus_three)),
      Rotation(yaw: raw(minus_three), pitch: raw(one), roll: raw(two)),
      StateFlags(flags: 0x2A),
      Mode(mode: 3),
      Unsent(29),
      footing(0),
    ]
    as "0x140c1f070: kind 0 is `Other`, kind 29 is one the client never sends (opcode.0x637.sent_kinds); kind 1's 0 is the world's frame, any other unit id a platform's"
}

pub fn a_unit_id_that_is_no_32_bit_number_is_no_footing_test() -> Nil {
  use <- owned_test.run(5000)
  assert result.is_ok(movement.footing(0)) && result.is_ok(movement.footing(1))
  assert result.is_ok(movement.footing(0xFFFFFFFF))
    as "the largest unit id the 32 bits of kind 1 carry"
  assert movement.footing(-1) == Error(Nil)
  assert movement.footing(0x100000000) == Error(Nil)
    as "kind 1's unit id is 32 bits, so a wider number is no unit id"
  assert movement.footing(7) != movement.footing(0)
    as "unit id 0 is the world, not a platform"
}

// ---- the save ----

pub fn each_save_names_the_logins_epoch_and_is_numbered_one_above_the_last_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    movement.save(
      state: entered(),
      account_id: AccountId(7),
      character_id: CharacterId(42),
      health: Some(512),
      experience: 1234,
      level: 3,
      quests: [],
      action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    )
  assert first
    == SavePlace(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(3),
      save_sequence: 1,
      place: movement.place(entered()),
      health: Some(512),
      experience: 1234,
      level: 3,
      quests: [],
      action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    )
    as "the save names the epoch the login was told (3 here) and is the login's first"
  let state = kept(state:, commands: [position(x: 5.0, y: 6.0, z: 7.0)])
  let #(state, second) =
    movement.save(
      state:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      health: None,
      experience: 1300,
      level: 3,
      quests: [],
      action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    )
  assert second
    == SavePlace(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(3),
      save_sequence: 2,
      place: movement.place(state),
      health: None,
      experience: 1300,
      level: 3,
      quests: [],
      action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    )
    as "the next save carries the place the moves since put the player at, numbered 2: the store keeps only a newer save of a login"
  assert at(state) == #(5.0, 6.0, 7.0)
  let #(_, third) =
    movement.save(
      state:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      health: Some(1),
      experience: 1,
      level: 1,
      quests: [],
      action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    )
  let assert SavePlace(save_sequence: 3, ..) = third
    as "a save asked and never answered still took its number, so an answer that comes late is never taken for a newer save"
  Nil
}

pub fn the_stores_answer_to_a_save_is_logged_by_what_it_says_test() -> Nil {
  use <- owned_test.run(5000)
  assert movement.saved(PlaceSaved) == [] as "a saved place needs no line"
  let assert [Note(text:)] = movement.saved(NothingSaved)
    as "a save that changed nothing is no failure, so an info line"
  assert string.contains(text, "later login")
    && string.contains(text, "newer save")
    && string.contains(text, "no such character")
    as "it names the three causes the store cannot tell apart"
  let assert [Fault(text:)] =
    movement.saved(PlaceRefused(constraint: "character_position_is_finite"))
    as "no place the rule keeps breaks a check of the database: a bug"
  assert string.contains(text, "refused") && string.contains(text, "place")
  assert string.contains(text, "character_position_is_finite")
    as "the line names the constraint that refused it"
  let assert [Fault(text:)] =
    movement.saved(PlaceRefused(
      constraint: "character_no_world_has_no_zone_or_position",
    ))
  assert string.contains(text, "character_no_world_has_no_zone_or_position")
    && !string.contains(text, "character_position_is_finite")
    as "and each refusal names its own"
  let assert [Fault(text:)] = movement.saved(HealthRefused)
    as "no living player has a health of 0 or below, which the table refuses: a bug"
  assert string.contains(text, "refused") && string.contains(text, "health")
  let assert [Fault(text:)] = movement.saved(ExperienceRefused)
    as "no player keeps an experience below 0, which the table refuses: a bug"
  assert string.contains(text, "refused")
    && string.contains(text, "experience")
    && !string.contains(text, "health")
    as "and it names the experience, not the health"
  list.each(
    [
      #(
        "character_action_slot_one_place_per_ability",
        "no bar the rule keeps breaks a check of the slot table: a bug",
      ),
      #(
        "character_ability_tier_is_above_the_first_and_fits_the_message",
        "no tier the rule keeps breaks a check of the tier table: a bug",
      ),
    ],
    fn(row) {
      let #(constraint, why) = row
      let assert [Fault(text:)] = movement.saved(ActionSetRefused(constraint:))
        as why
      assert string.contains(text, "refused")
        && string.contains(text, "a slot or a tier of the action sets")
        && string.contains(text, constraint)
        as "one sentence for every refusal of the action sets, naming the constraint that refused them"
    },
  )
}
