//// What the development command tests share: a player of a class, level and
//// experience in the world with the `dev_commands` setting on, and a line said
//// on Say.

import connection_rule_support as rule_support
import game_connection_support as support
import genesis_prime/client_connection.{
  type Request, AskMap, AskStore, FromMap, SentByMap,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/step.{type ConnectionStep, OwnEvent}
import genesis_prime/store
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map
import gleam/list
import gleam/option.{type Option, None, Some}

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
  let #(_, joined) =
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
}

/// The connection after the player said this text on Say.
pub fn said(
  state state: game_connection.State,
  text text: String,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.read(state, support.chat_line_message(4, text))
}

/// The connection after the player said this text on Say at this system time, as
/// a FILETIME.
pub fn said_at(
  state state: game_connection.State,
  text text: String,
  filetime filetime: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.feed_at(
    state:,
    filetime:,
    event: OwnEvent(step.Read(support.chat_line_message(4, text))),
  )
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
