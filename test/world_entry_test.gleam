//// Entering the world as a rule. The order the server sends comes from the
//// client's own end of loading (CheckWorldLoaded 0x1403E8000, opcode.0xf1,
//// opcode.0x19b, opcode.0x61 and opcode.0xf2): 0xAD gives the world and the
//// position, 0x262 creates the player's unit, 0x19B says that unit is the
//// player (it must exist: an unknown id is an error and loading never ends),
//// 0x636 gives the client control of the unit (it is ignored before 0x19B, and
//// the client answers 0x635 with the value it carried), 0xF1 sets the flag the end of loading waits for, the client sends 0xF2 when
//// the terrain near the player is loaded, and only then does the server send
//// 0x61, which the client reads the player's position for and so must follow
//// 0x19B. The bits of the position are those of vector.opcode.0xad.body (1.0,
//// -2.5 and 100.25).

import character_support
import genesis_prime/character/character
import genesis_prime/character/server_message.{
  ControlGranted, MovementIntervalSet, PlayRefused, PlayerEntered, PlayerUnitSet,
  UnitCreated, WorldEntered,
}
import genesis_prime/character/world_entry.{
  AnswerNobodyAskedFor, AwaitingMap, AwaitingTerrain, BeganTwice, Begin, Close,
  ControlEchoed, ControlEchoedOutOfOrder, ControlEchoedWrongValue, Entered,
  Failed, JoinMap, Joined, MapRefused, Send, TerrainLoaded,
  TerrainLoadedOutOfOrder, Waiting,
}
import genesis_prime/map/position.{Position}
import genesis_prime/map/unit.{type PlayerUnit, Newcomer, PlayerUnit}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/float32
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import gleam/int
import gleam/list
import gleam/string
import message_support
import owned_test
import seeded

fn context() -> world_entry.Context {
  world_entry.Context(
    realm_id: character_support.realm_id,
    world_exists: fn(world_id) { world_id == 51 },
  )
}

fn chosen() -> character.Character {
  character_support.character(id: 0x0102030405060708, name: "Ab Cd")
}

fn unit() -> PlayerUnit {
  PlayerUnit(
    id: 0x1001,
    character_id: 0x0102030405060708,
    name: "Ab Cd",
    race_id: 1,
    class_id: 3,
    gender: 1,
    path: 2,
    faction_id: 167,
    position: Position(x: 1.0, y: -2.5, z: 100.25),
  )
}

pub fn the_chosen_character_is_joined_to_the_map_of_its_world_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    world_entry.decide(world_entry.new(), Begin(chosen()), context())
  assert effects
    == [
      JoinMap(
        world_id: 51,
        newcomer: Newcomer(
          character_id: 0x0102030405060708,
          name: "Ab Cd",
          race_id: 1,
          class_id: 3,
          gender: 1,
          path: 2,
          faction_id: 167,
          position: Position(x: 1.0, y: -2.5, z: 100.25),
        ),
      ),
    ]
    as "opcode.0xad: the world the client loads is the character's, at its position"
  assert state == AwaitingMap(chosen())
}

pub fn a_world_with_no_row_is_refused_before_the_client_is_told_to_load_it_test() -> Nil {
  use <- owned_test.run(5000)
  let elsewhere =
    character.Character(
      ..chosen(),
      place: character.Place(..chosen().place, world_id: 52),
    )
  let #(state, effects) =
    world_entry.decide(world_entry.new(), Begin(elsewhere), context())
  assert effects
    == [Send(PlayRefused(PlayCharacterRefused(field_1: 2))), Failed]
    as "opcode.0xad: a World id with no row fails the load and the client stops at an error; opcode.0x162 sends it back to character select instead"
  assert state == Waiting
}

pub fn the_map_s_unit_is_followed_by_the_world_the_unit_the_player_the_control_and_the_interval_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    world_entry.decide(AwaitingMap(chosen()), Joined(unit()), context())
  assert effects
    == [
      Send(
        WorldEntered(EnterWorld(
          world_id: 51,
          position_x: 0x3F800000,
          position_y: 0xC0200000,
          position_z: 0x42C88000,
          field_5: 0,
          field_6: 0,
        )),
      ),
      Send(
        UnitCreated(UnitCreatePlayer(
          unit_id: 0x1001,
          character_id: 0x0102030405060708,
          realm_id: character_support.realm_id,
          name: "Ab Cd",
          race_id: 1,
          class_id: 3,
          gender: 1,
          field_9: 0,
          field_10: [],
          field_11: "",
          field_12: 0,
          field_13: [],
          field_14: [],
          path: 2,
          field_16: 0,
          field_17: 0,
          field_18: 0,
          stats: [
            UnitStat(stat_id: 0, value: world_entry.player_health_stand_in),
          ],
          server_time_estimate_start: 0,
          movement_commands: [
            UnitPositionCommand(
              x: 0x3F800000,
              y: 0xC0200000,
              z: 0x42C88000,
              blends: 0,
            ),
          ],
          properties: [
            UnitProperty(property_id: 7, field_2: 0x43080000, value: 0x43080000),
          ],
          item_visuals: [],
          field_25: 0,
          faction_id: 167,
          base_faction_id: 167,
          field_28: 0,
          field_29: 0,
          field_31: 0,
          field_33: 0,
          field_34: 0,
          field_36: 0,
          field_37: 0,
          field_38: 0,
          field_39: 0,
          field_40: 0,
        )),
      ),
      Send(PlayerUnitSet(UnitIsPlayer(unit_id: 0x1001, field_2: 0))),
      Send(
        ControlGranted(ClientControlGranted(
          echo_value: world_entry.control_echo_value,
          reset_movement: 1,
          unit_id: 0x1001,
        )),
      ),
      Send(
        MovementIntervalSet(MovementSendInterval(
          field_1: 0,
          field_2: 0,
          field_3: 0,
          interval_milliseconds: 125,
        )),
      ),
    ]
    as "CheckWorldLoaded 0x1403E8000, opcode.0x19b and opcode.0x636: 0xAD, then the unit (0x262), then the player (0x19B, whose unit id must exist), then the control (0x636, which the client ignores before 0x19B; the reset bit is 1 and the unit id the player's), then 0xF1; the unit's position is the character's (vector.opcode.0x262.position), its health stat 0 and property 7 are the stand-in (vector.opcode.0x262.health, 0x140457bc5); the player's data is the character's, the realm is the connection's, the unit's faction and base faction are the character's stored faction (opcode.0x262, Faction2.ID: 167 is a row), every other value the client's code does not give a meaning is 0 and the interval is the client's own 125 ms (0x140C3A004)"
  assert state == AwaitingTerrain(unit())
}

pub fn the_client_s_0xf2_is_answered_with_0x61_and_the_player_has_entered_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    world_entry.decide(AwaitingTerrain(unit()), TerrainLoaded, context())
  assert effects == [Send(PlayerEntered(PlayerEnteredWorld))]
    as "opcode.0x61: sent after the client's 0xf2, when the terrain near the player is ready (CheckWorldLoaded 0x1403E8000)"
  assert state == Entered
}

pub fn a_0xf2_before_the_world_messages_were_sent_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([Waiting, AwaitingMap(chosen()), Entered], fn(state) {
    let #(_, effects) = world_entry.decide(state, TerrainLoaded, context())
    assert effects == [Close(TerrainLoadedOutOfOrder)]
      as "opcode.0xf2: the client sends it once, while the world loads, after the server's messages"
  })
}

pub fn a_map_that_refuses_the_character_sends_the_player_back_to_character_select_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    world_entry.decide(AwaitingMap(chosen()), MapRefused, context())
  assert effects
    == [Send(PlayRefused(PlayCharacterRefused(field_1: 4))), Failed]
    as "opcode.0x162: the value is PreGameLib.CodeEnumCharacterSelectResults 4, FailedCharacterInWorld, for a character that is on the map already; the client returns to idle character select"
  assert state == Waiting
}

pub fn an_answer_of_the_map_nobody_asked_for_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, joined) = world_entry.decide(Waiting, Joined(unit()), context())
  assert joined == [Close(AnswerNobodyAskedFor)]
  let #(_, refused) = world_entry.decide(Entered, MapRefused, context())
  assert refused == [Close(AnswerNobodyAskedFor)]
}

pub fn a_second_choice_while_a_character_enters_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    world_entry.decide(AwaitingMap(chosen()), Begin(chosen()), context())
  assert effects == [Close(BeganTwice)]
    as "HandleCharacterSelectMessage 0x140020EA0: the client sends 0x7dd only while idle"
}

/// The 0x262 message of the unit's effects, when the rule sent one.
fn unit_created(effects: List(world_entry.Effect)) -> UnitCreatePlayer {
  let created =
    list.filter_map(effects, fn(effect) {
      case effect {
        Send(UnitCreated(message)) -> Ok(message)
        Send(_) | JoinMap(..) | Failed | Close(_) -> Error(Nil)
      }
    })
  let assert [message] = created as "the rule sends exactly one 0x262"
  message
}

pub fn the_player_s_unit_carries_the_character_s_stored_faction_in_both_faction_fields_test() -> Nil {
  use <- owned_test.run(5000)
  let character = character.Character(..chosen(), faction_id: 167)
  let #(_, effects) =
    world_entry.decide(AwaitingMap(character), Joined(unit()), context())
  let message = unit_created(effects)
  assert message.faction_id == 167
    as "opcode.0x262: the unit's faction (record 0xd4) is a Faction2 id, and 167 is a row of Faction2.ID; 0 has none, which leaves the unit without a faction and makes 0x19b fail"
  assert message.base_faction_id == 167
    as "opcode.0x262: the unit's base faction (record 0xd8) is a Faction2 id; HandleMessage019B 0x1403b5ad0 reads it and fails when it is empty"
}

pub fn the_server_s_0x262_for_roxo_is_the_emulator_s_alive_vector_test() -> Nil {
  use <- owned_test.run(5000)
  let roxo =
    character.Character(
      ..chosen(),
      id: 1,
      name: "Roxo Stompstone",
      race_id: 3,
      class_id: 1,
      gender: 0,
      path: 0,
      faction_id: 167,
    )
  let roxo_unit =
    PlayerUnit(
      id: 1,
      character_id: 1,
      name: "Roxo Stompstone",
      race_id: 3,
      class_id: 1,
      gender: 0,
      path: 0,
      faction_id: 167,
      position: Position(x: 4605.65, y: -7.571, z: 494.996),
    )
  let #(_, effects) =
    world_entry.decide(
      AwaitingMap(roxo),
      Joined(roxo_unit),
      world_entry.Context(realm_id: 1, world_exists: fn(_) { True }),
    )
  assert unit_create_player.encode(unit_created(effects))
    == Ok(message_support.hex(
      "0100000054000000000000004000e02105f0068007f006000230054007f006d006000730074007f006e006500630020000000000000000000000000000000001800800000000000010c44cfb639168913c70dfdffd908003000084210000842100000000008053e0140000000000000000000000004000000000000000000040000000000000000000000000",
    ))
    as "vector.opcode.0x262.roxo_alive: the body the client's reader takes in 1120 bits, Roxo's values with faction 167 in both fields (record 0xd4 and 0xd8), one kind 2 command at his position, stat 0 136 and property 7 136.0 twice"
}

pub fn the_new_player_s_unit_is_placed_at_its_position_and_alive_test() -> Nil {
  use <- owned_test.run(5000)
  let placed =
    PlayerUnit(
      ..unit(),
      position: Position(x: 4338.69, y: -1086.72, z: -3854.53),
    )
  let message = world_entry.unit_create(unit: placed, realm_id: 1)
  assert message.movement_commands
    == [
      UnitPositionCommand(
        x: float32.to_bits(4338.69),
        y: float32.to_bits(-1086.72),
        z: float32.to_bits(-3854.53),
        blends: 0,
      ),
    ]
    as "vector.opcode.0x262.position: one kind 2 command at the character's position, with the bit 0 that places the unit at once (0x1407138f0)"
  assert message.movement_commands
    == [
      UnitPositionCommand(
        x: 0x45879585,
        y: 0xC487D70A,
        z: 0xC570E87B,
        blends: 0,
      ),
    ]
    as "vector.opcode.0x262.position: the float32 bits of (4338.69, -1086.72, -3854.53) are 0x45879585, 0xC487D70A and 0xC570E87B"
  assert message.server_time_estimate_start == 0
    as "vector.opcode.0x262.position: the time of the command is 0"
  assert message.stats
    == [UnitStat(stat_id: 0, value: world_entry.player_health_stand_in)]
    as "vector.opcode.0x262.health: stat 0 is the unit's health, and health 0 is created dead (0x140457bc5)"
  assert message.properties
    == [
      UnitProperty(
        property_id: 7,
        field_2: float32.to_bits(136.0),
        value: float32.to_bits(136.0),
      ),
    ]
    as "vector.opcode.0x262.health: property 7 (BaseHealth) is 136.0 in both floats (0x43080000)"
  assert world_entry.player_health_stand_in == 136
    as "vector.opcode.0x262.health: the stand-in health is 136, CreatureLevel row 1's BaseHealth (135.97) rounded"
}

pub fn the_server_s_0x262_for_a_new_player_is_the_emulator_s_health_vector_test() -> Nil {
  use <- owned_test.run(5000)
  let vector_unit =
    PlayerUnit(
      id: 1,
      character_id: 1,
      name: "Ab",
      race_id: 1,
      class_id: 1,
      gender: 0,
      path: 0,
      faction_id: 0,
      position: Position(x: 4338.69, y: -1086.72, z: -3854.53),
    )
  assert unit_create_player.encode(world_entry.unit_create(
      unit: vector_unit,
      realm_id: 1,
    ))
    == Ok(message_support.hex(
      "01000000540000000000000040004010042006100200000000000000000000000000000000018008000000000000104461e56191c2f521f11e3a5cb1800300008421000084210000000000000000000000000000000000000000004000000000000000000040000000000000000000000000",
    ))
    as "vector.opcode.0x262.health: the body the client's reader takes in 912 bits, with the unit alive and at the position"
}

pub fn the_echo_of_the_value_0x636_carried_is_accepted_with_no_reply_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([AwaitingTerrain(unit()), Entered], fn(state) {
    let #(after, effects) =
      world_entry.decide(
        state,
        ControlEchoed(world_entry.control_echo_value),
        context(),
      )
    assert after == state
      as "opcode.0x635: the client's answer to 0x636 changes nothing"
    assert effects == []
      as "opcode.0x635: the client sends it as soon as it handles a 0x636 and expects no reply"
  })
}

pub fn an_echo_of_another_value_than_0x636_carried_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    world_entry.decide(AwaitingTerrain(unit()), ControlEchoed(5), context())
  assert effects == [Close(ControlEchoedWrongValue(5))]
    as "opcode.0x635: the client only sends back the value 0x636 brought, so another value is not the client's"
}

pub fn an_echo_before_the_server_sent_0x636_closes_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([Waiting, AwaitingMap(chosen())], fn(state) {
    let #(_, effects) =
      world_entry.decide(
        state,
        ControlEchoed(world_entry.control_echo_value),
        context(),
      )
    assert effects == [Close(ControlEchoedOutOfOrder)]
      as "opcode.0x635: the client sends it only in answer to a 0x636, which the server sends after the unit exists"
  })
}

/// The message numbers of what a list of effects sends, in order.
fn sent_numbers(effects: List(world_entry.Effect)) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(message) -> {
        let assert Ok(#(number, _)) = server_message.encode(message)
          as "a message the rule sends encodes"
        Ok(number)
      }
      JoinMap(..) | Failed | Close(_) -> Error(Nil)
    }
  })
}

pub fn the_messages_are_the_clients_numbers_in_the_clients_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(awaiting, _) =
    world_entry.decide(world_entry.new(), Begin(chosen()), context())
  let #(terrain, first) =
    world_entry.decide(awaiting, Joined(unit()), context())
  let #(_, second) = world_entry.decide(terrain, TerrainLoaded, context())
  assert sent_numbers(first) == [0x00AD, 0x0262, 0x019B, 0x0636, 0x00F1]
    as "opcode.0xad, opcode.0x262, opcode.0x19b, opcode.0x636 (ignored before opcode.0x19b) and opcode.0xf1, in the order CheckWorldLoaded 0x1403E8000 needs"
  assert sent_numbers(second) == [0x0061] as "opcode.0x61"
}

/// An input drawn from the generator.
fn drawn_input(state: Int) -> #(world_entry.Input, Int) {
  let #(kind, state) = seeded.up_to(state:, most: 3)
  let input = case kind {
    0 -> Begin(chosen())
    1 -> Joined(unit())
    2 -> MapRefused
    _ -> TerrainLoaded
  }
  #(input, state)
}

pub fn no_order_of_inputs_sends_the_messages_out_of_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let checked =
    int.range(from: 0, to: 500, with: #(20_261_302, 0), run: fn(random, _) {
      let #(random, checked) = random
      let #(sent, random) =
        run_inputs(state: world_entry.new(), random:, steps: 10, sent: [])
      // Each entry that completes sends 0xAD, 0x262, 0x19B, 0x636, 0xF1 and 0x61 in
      // that order, and an entry that is refused sends nothing but 0x162; so
      // the messages sent, with each 0x162 taken out, are repeats of that
      // sequence, the last of them possibly cut short.
      let entered = list.filter(sent, fn(number) { number != 0x0162 })
      assert follows_the_order(entered, [
        0x00AD,
        0x0262,
        0x019B,
        0x0636,
        0x00F1,
        0x0061,
      ])
        as "0x61 follows 0x19B, 0x636 follows 0x19B, 0x19B follows 0x262 and 0x262 follows 0xAD"
      #(random, checked + 1)
    })
  assert checked.1 == 500 as "every sequence was checked"
}

fn run_inputs(
  state state: world_entry.State,
  random random: Int,
  steps steps: Int,
  sent sent: List(Int),
) -> #(List(Int), Int) {
  case steps {
    0 -> #(sent, random)
    _ -> {
      let #(input, random) = drawn_input(random)
      let #(state, effects) = world_entry.decide(state, input, context())
      let state = case list.contains(effects, Failed) {
        True -> world_entry.new()
        False -> state
      }
      // After a breach the connection is closed: nothing more is fed.
      let closed = list.any(effects, is_close)
      let sent = list.append(sent, sent_numbers(effects))
      case closed {
        True -> #(sent, random)
        False -> run_inputs(state:, random:, steps: steps - 1, sent:)
      }
    }
  }
}

/// Whether `numbers` is the sequence `order` repeated, the last repeat possibly
/// short.
fn follows_the_order(numbers: List(Int), order: List(Int)) -> Bool {
  case numbers {
    [] -> True
    _ -> {
      let length = list.length(order)
      let taken = list.take(numbers, length)
      let wanted = list.take(order, list.length(taken))
      taken == wanted && follows_the_order(list.drop(numbers, length), order)
    }
  }
}

pub fn each_breach_has_its_own_sentence_for_the_log_test() -> Nil {
  use <- owned_test.run(5000)
  let sentences =
    list.map(
      [
        BeganTwice,
        AnswerNobodyAskedFor,
        TerrainLoadedOutOfOrder,
        ControlEchoedOutOfOrder,
        ControlEchoedWrongValue(5),
      ],
      fn(breach) { world_entry.describe_breach(breach) },
    )
  assert list.unique(sentences) == sentences
    as "a breach says what happened, and no two say the same"
  assert string.contains(
    world_entry.describe_breach(TerrainLoadedOutOfOrder),
    "0xF2",
  )
    as "the sentence names the client's message"
}

fn is_close(effect: world_entry.Effect) -> Bool {
  case effect {
    Close(_) -> True
    JoinMap(..) | Send(_) | Failed -> False
  }
}
