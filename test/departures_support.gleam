//// What the departures tests of a running game connection share
//// (`genesis_prime/game/connection`): a player holding "Bon Voyage" after its talk, in
//// front of a terminal, and the client's 0x97 and 0x805 that press it and answer its
//// window.

import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/departures
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/interaction_result.{type InteractionResult}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/step.{
  type ConnectionStep, type TimerId, OwnEffect, OwnEvent, StartTimer, TimerFired,
}
import genesis_prime/store.{type QuestRow}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/map.{ObjectsSeen}
import genesis_prime/world_map/static_object.{type Created, StaticObject}
import gleam/list
import quest_support
import spawn_support

/// The unit id the terminal has in the player's picture.
pub const terminal_unit = 5000

/// The client's own cast id of the press.
pub const clients_cast_id = 9

/// A display whose hit radius is 1.0 (Creature2DisplayInfo 25703), so the terminal
/// stands within every terminal's activate range from 2.5 east of the player.
const display = 25_703

/// The place `east` units east of where the tests' player stands.
fn east_of_the_player(east east: Float) -> Place {
  connection_support.standing_at(
    x: 29.128599166870117 +. east,
    y: -853.87158203125,
    z: -560.18798828125,
  )
}

/// The terminal Creature2 `creature_id` as a unit 2.5 east of the player.
pub fn terminal(creature_id creature_id: Int) -> Created {
  static_object.create(
    object: StaticObject(
      ..spawn_support.holoring(
        number: terminal_unit,
        place: east_of_the_player(east: 2.5),
      ),
      creature_id: Creature2Id(creature_id),
      display_info_id: display,
    ),
    unit_id: terminal_unit,
    server_time_estimate_start: 0,
  )
}

/// The quest row of Bon Voyage (Quest2 10528, Exile; 10530, Dominion) after the talk,
/// the first objective done.
pub fn after_the_talk(quest_id quest_id: Int) -> QuestRow {
  quest_support.active(
    quest_id:,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: 1,
    progress: [1, 0, 0, 0, 0],
  )
}

/// The player seeing the terminal `creature_id`: an Exile in the world holding
/// quest 10528 after the talk.
pub fn exile_seeing(creature_id creature_id: Int) -> game_connection.State {
  seeing(
    state: connection_support.in_world_as_exile_holding(quests: [
      after_the_talk(quest_id: 10_528),
    ]),
    creature_id:,
  )
}

/// The same for a Dominion player holding quest 10530 after the talk.
pub fn dominion_seeing(creature_id creature_id: Int) -> game_connection.State {
  seeing(
    state: connection_support.entered_with_quests(quests: [
      after_the_talk(quest_id: 10_530),
    ]).0,
    creature_id:,
  )
}

/// `state` after the map told it of the terminal `creature_id`.
pub fn seeing(
  state state: game_connection.State,
  creature_id creature_id: Int,
) -> game_connection.State {
  connection_support.feed(
    state:,
    event: connection_support.sent_by_the_map(
      ObjectsSeen(units: [terminal(creature_id:)]),
    ),
  ).0
}

/// The client's 0x97 right-click of the terminal.
pub fn press(
  state state: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(
      client_cast_id: clients_cast_id,
      target_unit_id: terminal_unit,
    ))
    as "the message fits"
  connection_support.read(
    state:,
    bytes: connection_support.world_message(
      message_id: cast_activate.message_id,
      body:,
    ),
  )
}

/// The cast id the server's 0x7fd named, which the client's 0x805 answers.
pub fn server_cast_id(pressed pressed: ConnectionStep(Request)) -> Int {
  let assert [confirmed] =
    list.filter(connection_support.written(taken: pressed), fn(frame) {
      frame.message_id == spell_cast_confirmed.message_id
    })
    as "the press was confirmed once"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed.body)
  confirmed.server_cast_id
}

/// The client's 0x805 answer of the window the press opened, for the Spell4Base the
/// terminal's activate spell has.
pub fn answer(
  state state: game_connection.State,
  pressed pressed: ConnectionStep(Request),
  result result: InteractionResult,
  spell4_base_id spell4_base_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  answer_cast(
    state:,
    cast_id: server_cast_id(pressed:),
    result:,
    spell4_base_id:,
  )
}

/// The client's 0x805 for the cast `cast_id`.
pub fn answer_cast(
  state state: game_connection.State,
  cast_id cast_id: Int,
  result result: InteractionResult,
  spell4_base_id spell4_base_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Ok(body) =
    client_side_interaction_result.encode(ClientSideInteractionResult(
      cast_id:,
      result:,
      spell4_base_id_plus_one: spell4_base_id + 1,
    ))
    as "the answer fits the message"
  connection_support.read(
    state:,
    bytes: connection_support.world_message(
      message_id: client_side_interaction_result.message_id,
      body:,
    ),
  )
}

/// The press and the yes: the state after the yes and the step of the yes.
pub fn yes(
  state state: game_connection.State,
  spell4_base_id spell4_base_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(pressed_state, pressed) = press(state:)
  answer(
    state: pressed_state,
    pressed:,
    result: interaction_result.Succeeded,
    spell4_base_id:,
  )
}

/// The timers the step starts that are the departures rule's, each with its delay.
pub fn started_timers(
  taken taken: ConnectionStep(Request),
) -> List(#(TimerId, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, after_ms:)) ->
        case departures.owns(timer) {
          True -> Ok(#(timer, after_ms))
          False -> Error(Nil)
        }
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The step of the departures timer firing in `state`.
pub fn timer_fires(
  state state: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.feed(state:, event: OwnEvent(TimerFired(departures.timer)))
}
