//// The player's chat on the game connection (genesis_prime/game/connection):
//// the chat messages the client sends in the world, what other connections
//// tell it, and the chat's effects carried out.
////
//// - **Chat** is a feature of its own (genesis_prime/game/chat): the player's
////   `Entered` keeps its chat, the routing table sends 0x1c3 and 0x1d4 to it from
////   inside 0x038C with the player in the world, and 0xF2 and 0x63A give it the
////   WorldZone id the client reports (the first 0xF2 of a stay also writes the
////   zone channel's 0x1BC again). The rule turns its effects into writes,
////   tells (`TellChat`, to a viewer's `Connection`, to a `ZoneChannel` and to a
////   whisper's `CharacterNamed`), the watch on a whisper's target and the
////   `JoinGroup` and `LeaveGroup` of the player's groups. What other
////   connections tell it (`SentByChat`) is taken by the chat with the player in
////   the world: a whisper that finds none is answered `NotHeard`, and any other
////   tell is dropped. The player joins its groups as the entry burst is written
////   and leaves them in the step that starts the camp's leave, so a new entry
////   joins again (genesis_prime/game/chat has the sequences, the refusals and
////   the failure table).

import genesis_prime/client_connection.{type Request, Continue, TellChat}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/world_entry
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, LogWarning, OwnEffect, Unwatch,
  Watch,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set

/// What the chat messages do, taken from inside 0x038C, in the world
/// (genesis_prime/game/chat): the line or whisper is answered, told or refused,
/// the effects are carried out, and a refusal ends the connection.
pub fn chat_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: chat.Message,
) -> client_connection.Handled(Session) {
  case
    chat.take(
      chat: entered.chat,
      message:,
      body: inner.body,
      viewers: connection_state.viewer_connections(entered:),
      realm_name: session.settings.realm_name,
      connection: client_connection.connection(session.link),
      tables: session.settings.tables,
    )
  {
    Ok(#(updated, effects)) ->
      carry_chat(session: with_chat(session:, chat: updated), effects:)
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: chat.describe(refusal))
  }
}

/// What another player's connection told this one about chat
/// (genesis_prime/game/chat_tell): taken with the player in the world, and by
/// `chat.told`. A whisper that finds no player in the world is answered
/// `NotHeard`; any other tell is dropped.
pub fn chat_sent(
  session session: Session,
  tell tell: chat_tell.Tell,
) -> client_connection.Handled(Session) {
  case connection_state.held_in_the_world(session.status) {
    Some(#(_, entered)) -> {
      let #(updated, effects) = chat.told(chat: entered.chat, tell:)
      carry_chat(session: with_chat(session:, chat: updated), effects:)
    }
    None ->
      case tell {
        chat_tell.Whisper(whisper:, from:, ..) ->
          Continue(session, [
            OwnEffect(step.Tell(
              to: step.Connection(from),
              request: TellChat(chat_tell.NotHeard(whisper:)),
            )),
          ])
        chat_tell.Said(..)
        | chat_tell.ZoneLine(..)
        | chat_tell.Heard(..)
        | chat_tell.NotHeard(..) -> Continue(session, [])
      }
  }
}

/// The session with the chat of the player in the world replaced.
pub fn with_chat(session session: Session, chat chat: chat.Chat) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, chat:)
  })
}

/// Turns what the chat decided into writes, tells, watches, group joins and log
/// lines. A channel the server does not build is logged as unhandled once for
/// each channel on the connection.
pub fn carry_chat(
  session session: Session,
  effects effects: List(chat.Effect),
) -> client_connection.Handled(Session) {
  let #(session, written) = chat_effects(session:, effects:)
  Continue(session, written)
}

/// The connection's effects for what the chat decided, in order, and the session
/// with the channels it logged as unhandled.
pub fn chat_effects(
  session session: Session,
  effects effects: List(chat.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(session, written) =
    list.fold(effects, #(session, []), fn(so_far, effect) {
      let #(session, written) = so_far
      case effect {
        chat.Send(frame:) -> #(session, [
          connection_state.to_client(session, frame),
          ..written
        ])
        chat.Tell(to:, tell:) -> #(session, [
          OwnEffect(step.Tell(to:, request: TellChat(tell))),
          ..written
        ])
        chat.TellWatched(watch:, tell:) -> #(session, [
          OwnEffect(step.TellWatched(watch:, request: TellChat(tell))),
          ..written
        ])
        chat.Watch(watch:, target:) -> #(session, [
          Watch(watch:, target:),
          ..written
        ])
        chat.Unwatch(watch:) -> #(session, [Unwatch(watch:), ..written])
        chat.JoinGroup(address:) -> #(session, [
          OwnEffect(step.JoinGroup(address:)),
          ..written
        ])
        chat.LeaveGroup(address:) -> #(session, [
          OwnEffect(step.LeaveGroup(address:)),
          ..written
        ])
        chat.UnknownZone(world_zone_id:) ->
          case set.contains(session.unknown_zones_logged, world_zone_id) {
            True -> #(session, written)
            False -> #(
              Session(
                ..session,
                unknown_zones_logged: set.insert(
                  session.unknown_zones_logged,
                  world_zone_id,
                ),
              ),
              [
                connection_state.log(
                  session:,
                  level: LogWarning,
                  text: "WorldZone "
                    <> int.to_string(world_zone_id)
                    <> " has no row in the client's table, so the player is in no zone channel",
                ),
                ..written
              ],
            )
          }
        chat.Unhandled(channel_type:) -> {
          let id = chat_channel.id(channel_type)
          case set.contains(session.unhandled_channels_logged, id) {
            True -> #(session, written)
            False -> #(
              Session(
                ..session,
                unhandled_channels_logged: set.insert(
                  session.unhandled_channels_logged,
                  id,
                ),
              ),
              [
                connection_state.log(
                  session:,
                  level: LogWarning,
                  text: "chat channel "
                    <> int.to_string(id)
                    <> " is not built: a line on it is refused with result 3",
                ),
                ..written
              ],
            )
          }
        }
      }
    })
  #(session, list.reverse(written))
}
