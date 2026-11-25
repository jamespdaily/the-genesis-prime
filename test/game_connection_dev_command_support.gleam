//// What the development command tests share: a player of a class, level and
//// experience in the world with the `dev_commands` setting on, and a line said
//// on Say.

import character_support
import connection_rule_support as rule_support
import departures_support
import game_connection_support as support
import genesis_prime/client_connection.{
  type Answer, type Request, AskMap, AskStore, FromMap, FromStore, SentByMap,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{type ConnectionStep, type Outcome, OwnEvent}
import genesis_prime/store
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map
import gleam/list
import gleam/option.{type Option, None, Some}
import place_support
import world_entry_support

/// The tests' player of this class, level and experience in the world, its
/// connection made with the development commands on, its burst taken.
pub fn in_world_at(
  class_id class_id: Int,
  level level: Int,
  experience experience: Int,
) -> game_connection.State {
  in_world_as(
    character: store.Character(
      ..support.world_character(),
      class_id: ClassId(class_id),
      level:,
    ),
    experience: Some(experience),
  )
}

/// The tests' connection made with the development commands on, with this
/// character in the world holding the experience its last save kept, its burst
/// taken.
pub fn in_world_as(
  character character: store.Character,
  experience experience: Option(Int),
) -> game_connection.State {
  support.entered_holding(
    in_character_select: support.in_select_from(
      support.accepted(support.settings_with_dev_commands()).0,
    ),
    character:,
    saved_experience: experience,
  ).0
}

/// The tests' player in the world with the development commands on, whose store held
/// these currency rows (a type with no row is held as 0), its burst taken.
pub fn in_world_holding_currencies(
  currencies currencies: List(store.HeldCurrency),
) -> game_connection.State {
  let character = support.world_character()
  let #(state, taken) =
    support.joining_holding_currencies(
      in_character_select: support.in_select_from(
        support.accepted(support.settings_with_dev_commands()).0,
      ),
      character:,
      saved_health: None,
      saved_experience: None,
      quests: [],
      items: world_entry_support.novice_items(character:),
      currencies:,
      action_sets: support.no_action_sets(),
    )
  support.answer(
    state:,
    taken:,
    outcome: step.Answer(client_connection.FromMap(support.map_answer(taken))),
  ).0
}

/// The tests' player of this class, level and experience entered into the real
/// map of four other players who all see it: the connection's join is stepped
/// through the map's rule, which answers it and sends the player a `SeenBy` for
/// each watcher (connections 2 to 5), and those notices are fed to the
/// connection, so its viewers are the ones the map named.
pub fn entered_among_watchers(
  class_id class_id: Int,
  level level: Int,
  experience experience: Int,
) -> game_connection.State {
  entered_among_watchers_in_a_map(class_id:, level:, experience:).0
}

/// `entered_among_watchers`, with the state of the map that took the player after
/// the join, for a test that steps the map again.
pub fn entered_among_watchers_in_a_map(
  class_id class_id: Int,
  level level: Int,
  experience experience: Int,
) -> #(game_connection.State, map.State) {
  let #(state, joining) =
    support.joining_holding(
      in_character_select: support.in_select_from(
        support.accepted(support.settings_with_dev_commands()).0,
      ),
      character: store.Character(
        ..support.world_character(),
        class_id: ClassId(class_id),
        level:,
      ),
      saved_health: None,
      saved_experience: Some(experience),
      quests: [],
    )
  let assert AskMap(message:, ..) = support.ask_request(joining)
    as "the player's first join is asked of the map"
  let #(map_state, joined) =
    map.step(
      support.map_with_four_players(),
      rule_support.input(
        OwnEvent(step.Asked(caller: step.CallerId(1), message:)),
      ),
    )
  let assert [#(_, answer)] = rule_support.replies(joined)
    as "the map answers the join once"
  let #(state, _) =
    support.answer(
      state:,
      taken: joining,
      outcome: step.Answer(FromMap(answer)),
    )
  let state =
    list.fold(rule_support.sends(joined), state, fn(state, sent) {
      case sent {
        #(1, map.Noticed(stay:, notice:)) ->
          support.feed(
            state:,
            event: support.for_stay(stay:, sent: SentByMap(notice)),
          ).0
        #(_, _) -> state
      }
    })
  #(state, map_state)
}

/// The connection after the player said this text on Say.
pub fn said(
  state state: game_connection.State,
  text text: String,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.read(state, support.chat_line_message(4, text))
}

/// The ask of a `!currency` line of the tests' player: the store sets the currency to
/// `after` while the player holds `held`, under the epoch the tests' connection holds.
pub fn currency_asked(
  currency_type_id currency_type_id: Int,
  held held: Int,
  after after: Int,
) -> Request {
  AskStore(
    store.Items(store.SetCurrency(
      account_id: store.AccountId(7),
      character_id: store.CharacterId(42),
      session_epoch: character_support.epoch(1),
      currency_type_id:,
      held:,
      after:,
    )),
  )
}

/// The store's answer that a currency is set to `amount`.
pub fn currency_set(amount amount: Int) -> Outcome(Answer) {
  step.Answer(FromStore(store.ForItems(store.CurrencySet(amount:))))
}

/// The tests' player at `place`, in whatever world it names, with the development
/// commands on and its burst taken.
pub fn in_world_at_place(place place: Place) -> game_connection.State {
  in_world_as(
    character: store.Character(..support.world_character(), place: Some(place)),
    experience: None,
  )
}

/// The tests' player in World 22 (zone 1189), with the development commands on, its
/// store holding this saved health (`None` for a full one), its burst taken.
pub fn in_world_22(
  saved_health saved_health: Option(Int),
) -> game_connection.State {
  support.entered_saved(
    in_character_select: support.in_select_from(
      support.accepted(support.settings_with_dev_commands()).0,
    ),
    character: store.Character(
      ..support.world_character(),
      place: Some(world_22_place()),
    ),
    saved_health:,
  ).0
}

/// The place of `in_world_22`.
pub fn world_22_place() -> Place {
  place_support.at(world_id: 22, world_zone_id: 1189, x: 1.0, y: 2.0, z: 3.0)
}

/// The leave a `!go` into another world asked of the player's map, answered `Left`: the
/// connection after it and the step that asks the new world's map to take the player.
pub fn left_the_map(
  state state: game_connection.State,
  leaving leaving: ConnectionStep(Request),
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.answer(
    state:,
    taken: leaving,
    outcome: step.Answer(FromMap(map.Left)),
  )
}

/// The map of World 870 answering the join in `joining`, and the step of the connection
/// taking the answer.
pub fn joined_world_870(
  state state: game_connection.State,
  joining joining: ConnectionStep(Request),
) -> #(game_connection.State, ConnectionStep(Request)) {
  departures_support.joined_at(state:, joining:, world: 870)
}

/// The tests' player of this level in the world, its connection made with the
/// development commands on, holding these quest rows, its burst taken.
pub fn in_world_holding_quests(
  level level: Int,
  quests quests: List(store.QuestRow),
) -> game_connection.State {
  support.entered_under(
    settings: support.settings_with_dev_commands(),
    character: store.Character(..support.world_character(), level:),
    quests:,
  ).0
}

/// The place the save timer's ask holds: the place the player would be saved at.
pub fn saved_place(state state: game_connection.State) -> Place {
  let #(_, taken) =
    support.feed(
      state:,
      event: OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert client_connection.AskStore(store.Move(store.SavePlace(place:, ..))) =
    support.ask_request(taken)
    as "the save timer asks the store to save the place"
  place
}

/// The quest rows the connection saves at its next save timer: what the log holds.
pub fn saved_quests(
  state state: game_connection.State,
) -> List(store.QuestRow) {
  let #(_, taken) =
    support.feed(
      state:,
      event: OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert AskStore(store.Move(store.SavePlace(quests:, ..))) =
    support.ask_request(taken)
    as "the save timer asks the store to save the place and the quest log"
  quests
}

/// The connection after its save timer fires, and the step of the firing.
pub fn save_timer_fires(
  state state: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.feed(
    state:,
    event: OwnEvent(step.TimerFired(connection_state.save_timer)),
  )
}
