//// Entering the world as a rule. The order the server sends comes from the
//// client's own end of loading (CheckWorldLoaded 0x1403E8000, opcode.0xf1,
//// opcode.0x19b, opcode.0x61 and opcode.0xf2): 0xAD gives the world and the
//// position, 0x262 creates the player's unit, 0x19B says that unit is the
//// player (it must exist: an unknown id is an error and loading never ends),
//// 0xF1 sets the flag the end of loading waits for, the client sends 0xF2 when
//// the terrain near the player is loaded, and only then does the server send
//// 0x61, which the client reads the player's position for and so must follow
//// 0x19B. The bits of the position are those of vector.opcode.0xad.body (1.0,
//// -2.5 and 100.25).

import character_support
import genesis_prime/character/character
import genesis_prime/character/server_message.{
  MovementIntervalSet, PlayRefused, PlayerEntered, PlayerUnitSet, UnitCreated,
  WorldEntered,
}
import genesis_prime/character/world_entry.{
  AnswerNobodyAskedFor, AwaitingMap, AwaitingTerrain, BeganTwice, Begin, Close,
  Entered, Failed, JoinMap, Joined, MapRefused, Send, TerrainLoaded,
  TerrainLoadedOutOfOrder, Waiting,
}
import genesis_prime/map/position.{Position}
import genesis_prime/map/unit.{type PlayerUnit, Newcomer, PlayerUnit}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import gleam/int
import gleam/list
import gleam/string
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
    == [Send(PlayRefused(PlayCharacterRefused(field_1: 0))), Failed]
    as "opcode.0xad: a World id with no row fails the load and the client stops at an error; opcode.0x162 sends it back to character select instead"
  assert state == Waiting
}

pub fn the_map_s_unit_is_followed_by_the_world_the_unit_the_player_and_the_interval_in_order_test() -> Nil {
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
          field_20: 0,
          item_visuals: [],
          field_25: 0,
          field_26: 0,
          field_27: 0,
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
        MovementIntervalSet(MovementSendInterval(
          field_1: 0,
          field_2: 0,
          field_3: 0,
          interval_milliseconds: 125,
        )),
      ),
    ]
    as "CheckWorldLoaded 0x1403E8000 and opcode.0x19b: 0xAD, then the unit (0x262), then the player (0x19B, whose unit id must exist), then 0xF1; the player's data is the character's, the realm is the connection's, every value the client's code does not give a meaning is 0 and the interval is the client's own 125 ms (0x140C3A004)"
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
    == [Send(PlayRefused(PlayCharacterRefused(field_1: 0))), Failed]
    as "opcode.0x162: playing the chosen character failed; the client returns to idle character select"
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

/// The message numbers of what a list of effects sends, in order.
fn sent_numbers(effects: List(world_entry.Effect)) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(message) -> {
        let assert Ok(#(number, _)) = server_message.encode(message)
          as "a message the rule sends encodes"
        Ok(number)
      }
      _ -> Error(Nil)
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
  assert sent_numbers(first) == [0x00AD, 0x0262, 0x019B, 0x00F1]
    as "opcode.0xad, opcode.0x262, opcode.0x19b and opcode.0xf1, in the order CheckWorldLoaded 0x1403E8000 needs"
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
      // Each entry that completes sends 0xAD, 0x262, 0x19B, 0xF1 and 0x61 in
      // that order, and an entry that is refused sends nothing but 0x162; so
      // the messages sent, with each 0x162 taken out, are repeats of that
      // sequence, the last of them possibly cut short.
      let entered = list.filter(sent, fn(number) { number != 0x0162 })
      assert follows_the_order(entered, [0x00AD, 0x0262, 0x019B, 0x00F1, 0x0061])
        as "0x61 follows 0x19B, 0x19B follows 0x262 and 0x262 follows 0xAD"
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
      let closed =
        list.any(effects, fn(effect) {
          case effect {
            Close(_) -> True
            _ -> False
          }
        })
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
      [BeganTwice, AnswerNobodyAskedFor, TerrainLoadedOutOfOrder],
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
