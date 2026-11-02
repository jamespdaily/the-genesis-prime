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
//// - The fact `0x140c1f070`: each command's kind and layout, so which record is
////   which kind. The fact `0x140715350`: kind 14 is yaw, pitch and roll.
//// - IEEE 754 binary32: an exponent of all ones is infinity (0x7F800000,
////   0xFF800000) or not a number (0x7FC00000, 0x7F800001); 1.0 is 0x3F800000,
////   2.0 is 0x40000000 and -3.0 is 0xC0400000.

import character_support
import genesis_prime/game/movement.{
  type Command, type Refusal, type State, BelowTheWorld, Fault, Mode, Moves,
  NotFinite, Note, Other, Position, Rotation, Standing, StateFlags, UnknownMode,
  UnknownSpeedSetting, UnknownStateFlags,
}
import genesis_prime/game/start_place.{type Facing, Facing}
import genesis_prime/message/float32
import genesis_prime/message/movement_command
import genesis_prime/message/movement_kind_29.{MovementKind29}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/player_movement.{PlayerMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/store.{
  AccountId, CharacterId, NothingSaved, PlaceRefused, PlaceSaved, SavePlace,
}
import gleam/list
import gleam/result
import gleam/string
import owned_test
import place_support

/// The infinity, minus infinity and not-a-number patterns of a 32-bit float.
const not_finite = [0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001]

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
    movement_command.Kind29(MovementKind29(field_2: 9)),
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
      Other(29),
      footing(0),
    ]
    as "0x140c1f070: kind 0 and every kind the rule does not act on are `Other` with their kind; kind 1's 0 is the world's frame, any other unit id a platform's"
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
    )
  assert first
    == SavePlace(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(3),
      save_sequence: 1,
      place: movement.place(entered()),
    )
    as "the save names the epoch the login was told (3 here) and is the login's first"
  let state = kept(state:, commands: [position(x: 5.0, y: 6.0, z: 7.0)])
  let #(state, second) =
    movement.save(
      state:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
    )
  assert second
    == SavePlace(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(3),
      save_sequence: 2,
      place: movement.place(state),
    )
    as "the next save carries the place the moves since put the player at, numbered 2: the store keeps only a newer save of a login"
  assert at(state) == #(5.0, 6.0, 7.0)
  let #(_, third) =
    movement.save(
      state:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
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
  let assert [Fault(text:)] = movement.saved(PlaceRefused)
    as "no place the rule keeps breaks a check of the database: a bug"
  assert string.contains(text, "refused")
}
