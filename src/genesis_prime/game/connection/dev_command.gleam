//// The development commands carried out on the game connection
//// (genesis_prime/game/connection): a command line the chat took with the
//// setting on and the tables allowed (genesis_prime/game/dev_command) is run
//// here, with the state the connection holds. The chat cannot run it itself:
//// the commands reach modules that import the connection's effects, which
//// import the chat.
////
//// ```
//// chat_message ─▶ Command(session, written, command) ─▶ run
////   Summon                           ─▶ chat.summoning ─▶ the map is asked
////   GiveItem                         ─▶ info log, vendor_purchase.given ─▶ the store is asked, or one system line
////   RaiseToLevel / RaiseToExperience ─▶ experience.raised(held, target)
////        Ok(credited) ─▶ info log, connection/experience.gained (0x1ac, 0x938 ...), one system line
////        Already, Lowering ─▶ one system line, nothing changes
////   CompleteQuest                    ─▶ quest_log.finished
////        finished ─▶ one system line, nothing changes
////        else ─▶ quest_log.complete, info log, 0x35C state 3, the deadline timer moved,
////                connection/objective.settled, one system line
////   Go ─▶ dead, or the place is in another world ─▶ one system line, nothing changes
////      └ the player's world ─▶ info log, the current cast stopped, projector.placed_at,
////                              one system line, objectives settled
//// ```
////
//// - **The client takes experience only upward**, by 0x1ac adding to it, so a
////   target at or below what the player holds changes nothing and is answered
////   with a line (`opcode.0x1ac`).
//// - **A raise is a gain of kind 1, Cheat**, written as any gain is, with the
////   level rise's frames when it crosses a level (genesis_prime/game/connection/experience).
//// - **Every accepted command is logged once** at info, naming the command and
////   what it changed; a refused one writes its line and no log, since the line is
////   its record.
//// - **A raise asks no process**: the new level and experience are saved with the
////   place by the next save, as any gain is.
//// - **An item is a purchase of no cost**: `GiveItem` asks the store the buy of a vendor
////   asks (genesis_prime/game/connection/vendor_purchase `given`), the connection waits in
////   `Buying`, and the answer is a purchase's with the Cheat reason and a system line in
////   place of the vendor's 0x106. A store that gives no answer ends the connection with
////   reason 8 and saves the place; the statement may have committed, so the next login
////   holds the items though the connection never did.
//// - **A quest is done in the log only**: the entry becomes Completed at now and
////   the client takes state 3 for a quest it holds no entry of
////   (`opcode.0x35c.complete_unheld`), with none of the quest's own rewards. A
////   quest whose Completed entry is of the current period (`quest_log.finished`) is
////   answered with a line; a periodic quest completed in an earlier period is
////   completed again.
//// - **A quest's completion has a turn-in's follow-ups**: the deadline timer is
////   moved from the log before to the log after, and the objectives are settled, so
////   a quest waiting on this one finishes and a finished quest no creature receives
////   is completed by the server through its own store ask
////   (genesis_prime/game/connection/quest_turn_in `completing`). The command's own
////   line comes after those frames.
//// - **A `!go` in the player's world is the client's own in-world placement**: 0x83c,
////   0x639, 0x638 and 0x636 (`opcode.0x83c`), since an in-world 0xAD names a full world
////   change (`opcode.0xad.same_world`). The place carries the commanded zone until the
////   client's next zone report replaces it, which drives the zone chat group and the
////   objectives (`movement.take`). The place is saved by the next save, as a move is.
//// - **A `!go` refuses while the player is dead**, as the departures' move does, and a
////   `!go` into another world is refused with a system line.

import genesis_prime/client_connection.{type Request, Asking, Continue, Done}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/chat as connection_chat
import genesis_prime/game/connection/experience as connection_experience
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/projector as connection_projector
import genesis_prime/game/connection/state.{
  type Session, AwaitingHelloReply, Buying, ClaimingSession, EnteringWorld,
  InCharacterSelect, InWorld, LeavingMap, MovingItem, SavingPlace, Selling,
  SpendingCharge, Summoning, TakingSessionKey, TurningIn, WaitingToClaim,
} as connection_state
import genesis_prime/game/connection/vendor_purchase as connection_vendor_purchase
import genesis_prime/game/deadline_timer
import genesis_prime/game/dev_command
import genesis_prime/game/experience.{type Progress, Already, Lowering, Progress}
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/quest_log
import genesis_prime/game/start_place
import genesis_prime/game/world_entry
import genesis_prime/gap
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/table/id.{type Item2Id}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// What the chat messages do (genesis_prime/game/connection/chat), with a
/// command line the chat hands back carried out here.
pub fn chat_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: chat.Message,
) -> client_connection.Handled(Session) {
  case
    connection_chat.chat_message(session:, now:, entered:, inner:, message:)
  {
    connection_chat.Taken(handled:) -> handled
    connection_chat.Command(session:, written:, command:) ->
      run(session:, now:, written:, command:)
  }
}

/// Carries out a command, after the effects `written` that come before it (the
/// 0x1c2 that answers its line).
fn run(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  command command: dev_command.Command,
) -> client_connection.Handled(Session) {
  case command {
    dev_command.Summon(creature2_id:, level:) ->
      connection_chat.summoning(
        session:,
        now:,
        creature2_id:,
        level:,
        before: written,
      )
    dev_command.RaiseToLevel(level:) ->
      raised(
        session:,
        now:,
        written:,
        named: "!level " <> int.to_string(level),
        target: experience.ToLevel(level:),
      )
    dev_command.RaiseToExperience(experience: total) ->
      raised(
        session:,
        now:,
        written:,
        named: "!xp " <> int.to_string(total),
        target: experience.ToExperience(experience: total),
      )
    dev_command.GiveItem(item2_id:, count:) ->
      given(session:, now:, written:, item2_id:, count:)
    dev_command.CompleteQuest(quest2_id:) ->
      completed(session:, now:, written:, quest_id: quest2_id.value)
    dev_command.Go(destination:) -> went(session:, now:, written:, destination:)
  }
}

/// The items of an `!item` line put in the bag: the store is asked for them as a purchase of
/// no cost and the answer's frames and one system line follow (genesis_prime/game/vendor_purchase),
/// or one system line says the bag has no room. A status other than `InWorld` cannot have
/// taken the line, so it is a bug that ends the connection.
fn given(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  item2_id item2_id: Item2Id,
  count count: Int,
) -> client_connection.Handled(Session) {
  case session.status {
    InWorld(holder:, entered:) ->
      connection_vendor_purchase.given(
        session:,
        now:,
        holder:,
        entered:,
        written:,
        logged_as: "dev command !item "
          <> int.to_string(item2_id.value)
          <> " "
          <> int.to_string(count),
        item2_id:,
        count:,
      )
    Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
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
        text: "!item was run while the player was not in the world",
      )
  }
}

/// A quest completed in the player's log: one system line when the log holds it
/// finished (a Completed entry of the current period), and else the entry made
/// Completed at now (`completion`).
fn completed(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  quest_id quest_id: Int,
) -> client_connection.Handled(Session) {
  case connection_state.entered_of(session.status) {
    None ->
      connection_state.end_for(
        session:,
        now:,
        text: "!quest "
          <> int.to_string(quest_id)
          <> " done was run while the player was not in the world",
      )
    Some(entered) ->
      case
        quest_log.finished(
          log: entered.quests,
          quest_id:,
          tables: session.settings.tables,
          numbers: session.settings.numbers,
          unix_ms: step.unix_milliseconds(now:),
        )
      {
        True ->
          Continue(
            session,
            list.append(written, [
              line(
                session:,
                text: "quest " <> int.to_string(quest_id) <> " is already done",
              ),
            ]),
          )
        False -> completion(session:, now:, written:, entered:, quest_id:)
      }
  }
}

/// The entry of the quest made Completed at now, then in order: an info log, 0x35C
/// state 3, the quest deadline timer moved from the log before to the log after, the
/// objectives settled, which can finish a quest that waits on this one, and one system
/// line. A quest that finishes and that no creature receives is completed by the server
/// as any is (genesis_prime/game/connection/quest_turn_in `completing`).
fn completion(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  entered entered: world_entry.Entered,
  quest_id quest_id: Int,
) -> client_connection.Handled(Session) {
  let log =
    quest_log.complete(
      log: entered.quests,
      quest_id:,
      at_seconds: step.unix_milliseconds(now:) / 1000,
    )
  let session =
    connection_state.with_entered(session:, change: fn(entered) {
      world_entry.Entered(..entered, quests: log)
    })
  let timers =
    list.map(
      deadline_timer.moved(
        before: quest_log.next_deadline(log: entered.quests),
        after: quest_log.next_deadline(log:),
        now_ms: now.monotonic_ms,
      ),
      connection_state.deadline_timer_move(
        connection_state.quest_deadline_timer,
        _,
      ),
    )
  let #(session, settled) = connection_objective.settled(session:, now:)
  let quest = int.to_string(quest_id)
  Continue(
    session,
    list.flatten([
      written,
      [
        connection_state.log(
          session:,
          level: step.LogInfo,
          text: "dev command !quest " <> quest <> " done: completed",
        ),
        connection_state.to_client(
          session,
          quest_log.quest_state_frame(
            quest_id:,
            state: completed_state,
            objective_id: 0,
          ),
        ),
      ],
      timers,
      settled,
      [line(session:, text: "quest " <> quest <> " completed")],
    ]),
  )
}

/// The state 0x35C gives a completed quest.
const completed_state = 3

/// A `!go`: the player placed at the destination when it is in their world, or one
/// system line and nothing changed when the player is dead, the tables lack what
/// the place needs, or the place is in another world.
fn went(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  destination destination: dev_command.Destination,
) -> client_connection.Handled(Session) {
  case connection_state.entered_of(session.status) {
    None ->
      connection_state.end_for(
        session:,
        now:,
        text: "!go was run while the player was not in the world",
      )
    Some(entered) ->
      case player_life.state(life: entered.life) {
        player_life.Dead -> refused(session:, written:, text: dead_text)
        player_life.Alive ->
          case
            dev_command.place_of(
              destination:,
              facing: movement.facing(state: entered.movement),
              tables: session.settings.tables,
            )
          {
            Error(refusal) ->
              refused(session:, written:, text: dev_command.describe(refusal:))
            Ok(place) ->
              case
                start_place.world_id(place)
                == start_place.world_id(movement.place(state: entered.movement))
              {
                True -> placed(session:, now:, written:, place:)
                False -> refused(session:, written:, text: another_world_text)
              }
          }
      }
  }
}

const dead_text = "!go is refused while the player is dead"

const another_world_text = "!go to another world is not built"

/// The player placed at `place`, in their world: the current cast stopped as the
/// client's 0x83c stops it, the placement's frames, one system line and then the
/// objectives settled at the new place.
fn placed(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  place place: start_place.Place,
) -> client_connection.Handled(Session) {
  let described =
    "world "
    <> int.to_string(start_place.world_id(place))
    <> ", zone "
    <> int.to_string(start_place.world_zone_id(place))
    <> ", ("
    <> float.to_string(start_place.x(place))
    <> ", "
    <> float.to_string(start_place.y(place))
    <> ", "
    <> float.to_string(start_place.z(place))
    <> ")"
  let logged =
    connection_state.log(
      session:,
      level: step.LogInfo,
      text: "dev command !go: placed at " <> described,
    )
  let #(session, stopped) = casting.stopped_by_placement(session:, now:)
  let #(session, moved) = connection_projector.placed_at(session:, now:, place:)
  let #(session, settled) = connection_objective.settled(session:, now:)
  Continue(
    session,
    list.flatten([
      written,
      [logged],
      stopped,
      moved,
      [line(session:, text: "moved to " <> described)],
      settled,
    ]),
  )
}

/// One system line after the effects `written`, and nothing else changed.
fn refused(
  session session: Session,
  written written: List(Effect(ConnectionEffect(Request))),
  text text: String,
) -> client_connection.Handled(Session) {
  Continue(session, list.append(written, [line(session:, text:)]))
}

/// A raise of the held level or experience to the target: the gain's frames and
/// one system line with the level and experience reached, or one system line and
/// nothing changed when the target is the held value or below it.
fn raised(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  named named: String,
  target target: experience.Target,
) -> client_connection.Handled(Session) {
  case connection_state.entered_of(session.status) {
    None ->
      connection_state.end_for(
        session:,
        now:,
        text: named <> " was run while the player was not in the world",
      )
    Some(entered) -> {
      let held =
        Progress(experience: entered.experience, level: entered.character.level)
      case
        experience.raised(
          progress: held,
          target:,
          tables: session.settings.tables,
        )
      {
        Error(Already) ->
          Continue(
            session,
            list.append(written, [
              line(
                session:,
                text: "already at level "
                  <> int.to_string(held.level)
                  <> ", experience "
                  <> int.to_string(held.experience),
              ),
            ]),
          )
        Error(Lowering) ->
          Continue(
            session,
            list.append(written, [
              line(session:, text: lowering_text(named:, held:, target:)),
            ]),
          )
        Ok(credited) ->
          gained(session:, now:, written:, named:, entered:, held:, credited:)
      }
    }
  }
}

/// The gain carried out, between the log of the command and its system line.
fn gained(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  named named: String,
  entered entered: world_entry.Entered,
  held held: Progress,
  credited credited: experience.Credited,
) -> client_connection.Handled(Session) {
  let reached = credited.progress
  let logged =
    connection_state.log(
      session:,
      level: step.LogInfo,
      text: "dev command "
        <> named
        <> ": level "
        <> int.to_string(held.level)
        <> ", experience "
        <> int.to_string(held.experience)
        <> " to level "
        <> int.to_string(reached.level)
        <> ", experience "
        <> int.to_string(reached.experience),
    )
  case connection_experience.gained(session:, now:, entered:, credited:) {
    Continue(session, told) ->
      Continue(
        session,
        list.flatten([
          written,
          [logged],
          told,
          [
            line(
              session:,
              text: "level "
                <> int.to_string(reached.level)
                <> ", experience "
                <> int.to_string(reached.experience),
            ),
          ],
        ]),
      )
    Done(session, effects) -> Done(session, list.append(written, effects))
    Asking(..) as asking -> asking
  }
}

/// The text that says a target is below what the player holds, and why it is
/// refused.
fn lowering_text(
  named named: String,
  held held: Progress,
  target target: experience.Target,
) -> String {
  let #(held_text, asked_text) = case target {
    experience.ToLevel(level:) -> #(
      "level " <> int.to_string(held.level),
      "level " <> int.to_string(level),
    )
    experience.ToExperience(experience:) -> #(
      "experience " <> int.to_string(held.experience),
      "experience " <> int.to_string(experience),
    )
  }
  named
  <> " would lower "
  <> held_text
  <> "; the client takes experience only upward: use a character at or below "
  <> asked_text
}

/// A system line, written to the player's client.
fn line(
  session session: Session,
  text text: String,
) -> Effect(ConnectionEffect(Request)) {
  connection_state.to_client(session, chat.system_line_frame(text:))
}

/// What `!go` leaves undone.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Development commands",
      missing: "a `!go` into another world than the player's: it is refused with a system line",
    ),
  ]
}
