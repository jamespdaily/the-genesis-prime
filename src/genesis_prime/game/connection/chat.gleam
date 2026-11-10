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
//// - **A development summon** (genesis_prime/game/dev_command): a `!summon` line
////   with the setting on is answered by the chat's 0x1c2, then the connection
////   asks the player's map to start the creature and waits in `Summoning`;
////   the answer is told to the player only when it is a refusal, as one System
////   line.
////
//// ```
//// InWorld ─ !summon id [level] ─▶ 0x1c2, AskMapRun(Summon) ─▶ Summoning ─ answer ─▶ InWorld
////                                                               Summoned: nothing
////                                                               otherwise: one System line
//// ```

import genesis_prime/client_connection.{
  type Answer, type Request, AskMapRun, Continue, FromMap, TellChat,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell
import genesis_prime/game/connection/state.{
  type Session, AwaitingHelloReply, Buying, ClaimingSession, EnteringWorld,
  InCharacterSelect, InWorld, LeavingMap, MovingItem, SavingPlace, Selling,
  Session, Summoning, TakingSessionKey, TurningIn, WaitingToClaim,
} as connection_state
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome, LogWarning,
  OwnEffect, Unwatch, Watch,
}
import genesis_prime/table/id.{type Creature2Id}
import genesis_prime/world_map/map
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
      dev_commands: session.settings.game.dev_commands,
    )
  {
    Ok(#(updated, effects)) ->
      case list.reverse(effects) {
        [chat.AskSummon(creature2_id:, level:), ..before] -> {
          let session = with_chat(session:, chat: updated)
          let #(session, written) =
            chat_effects(session:, effects: list.reverse(before))
          summoning(session:, now:, creature2_id:, level:, before: written)
        }
        _ -> carry_chat(session: with_chat(session:, chat: updated), effects:)
      }
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: chat.describe(refusal))
  }
}

/// The connection asks the run of its player's map to start the creature of a
/// `!summon` line (`map.Summon`), after the effects `before`, with the settings'
/// ask deadline, and waits in `Summoning`: the player stays in the world with the
/// client's frames held, as in a save, and the shell takes no other input
/// until the outcome. A status other than `InWorld` cannot have taken the line,
/// so it is a bug that ends the connection.
fn summoning(
  session session: Session,
  now now: Now,
  creature2_id creature2_id: Creature2Id,
  level level: Option(Int),
  before before: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  case session.status {
    InWorld(holder:, entered:) ->
      connection_state.ask(
        session: Session(..session, status: Summoning(holder:, entered:)),
        now:,
        request: AskMapRun(
          map: entered.map,
          incarnation: entered.incarnation,
          message: map.Summon(
            connection: client_connection.connection(session.link),
            creature_id: creature2_id,
            level:,
          ),
        ),
        before:,
      )
    Summoning(..)
    | MovingItem(..)
    | Buying(..)
    | Selling(..)
    | TurningIn(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | EnteringWorld(..)
    | ClaimingSession(..)
    | WaitingToClaim(..)
    | InCharacterSelect(..)
    | AwaitingHelloReply
    | TakingSessionKey ->
      connection_state.end_for(
        session:,
        now:,
        text: "a summon was asked while the player was not in the world",
      )
  }
}

/// The outcome of the summon ask. `Summoned` writes nothing: the creature sent
/// its 0x262 as it started, and that waits in the mailbox for the status to
/// return to `InWorld`. `NotSummoned` writes one system line naming the
/// refusal (`spawn.describe_refusal`), or that the player is not in the map. A
/// map that is not running, that ended before it answered or that gave no
/// answer in time writes the system line "not summoned" and the connection goes
/// on, since the map's own end ends the connection by its watch; the server
/// stopping ends it as a stop does. An answer that is none a summon asks for
/// ends the connection as a bug, as a save's does.
pub fn summon_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  let session = Session(..session, status: InWorld(holder:, entered:))
  case outcome {
    step.Answer(FromMap(map.Summoned(..))) -> Continue(session, [])
    step.Answer(FromMap(map.NotSummoned(reason:))) ->
      not_summoned(session:, because: not_summoned_text(reason:))
    step.NotRunning | step.EndedBeforeAnswer | step.NoAnswerInTime ->
      not_summoned(
        session:,
        because: client_connection.without_answer(who: "the map", outcome:),
      )
    step.StoppedWaiting -> connection_state.stopped(session, now)
    step.Answer(FromMap(..))
    | step.Answer(client_connection.FromStore(..))
    | step.Answer(client_connection.FromHandOff(..))
    | step.Answer(client_connection.FromSessions(..)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the answer is none a summon asked for",
      )
  }
}

/// The System line that tells the player no creature came, with why.
fn not_summoned(
  session session: Session,
  because because: String,
) -> client_connection.Handled(Session) {
  Continue(session, [
    connection_state.to_client(
      session,
      chat.system_line_frame(text: "not summoned: " <> because),
    ),
  ])
}

/// Why the map refused a summon, in words for the player.
fn not_summoned_text(reason reason: map.NotSummoned) -> String {
  case reason {
    map.NoPlayerHere -> "the player is not in the map"
    map.CreatureRefused(refusal:) -> spawn.describe_refusal(refusal:)
    map.CreatureNotStarted(..) -> "the creature did not start"
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
        chat.AskSummon(..) ->
          panic as "an ask for a summon is made by chat_message, which ends the step with it"
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
