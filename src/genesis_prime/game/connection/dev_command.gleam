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

import genesis_prime/client_connection.{type Request, Asking, Continue, Done}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat
import genesis_prime/game/connection/chat as connection_chat
import genesis_prime/game/connection/experience as connection_experience
import genesis_prime/game/connection/state.{
  type Session, AwaitingHelloReply, Buying, ClaimingSession, EnteringWorld,
  InCharacterSelect, InWorld, LeavingMap, MovingItem, SavingPlace, Selling,
  SpendingCharge, Summoning, TakingSessionKey, TurningIn, WaitingToClaim,
} as connection_state
import genesis_prime/game/connection/vendor_purchase as connection_vendor_purchase
import genesis_prime/game/dev_command
import genesis_prime/game/experience.{type Progress, Already, Lowering, Progress}
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/table/id.{type Item2Id}
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
