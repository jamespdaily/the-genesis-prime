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
////   RaiseToLevel / RaiseToExperience ─▶ experience.raised(held, target)
////        Ok(credited) ─▶ info log, connection/experience.gained (0x1ac, 0x938 ...), one system line
////        Already, Lowering ─▶ one system line, nothing changes
////   SetCurrency                      ─▶ info log, store SetCurrency asked, status Granting
////        granted: CurrencySet ─▶ 0x919 (0xdd when higher), one system line
////                 ItemsNotSaved, SaveRefused ─▶ log, one "not set" line, nothing changes
////                 no answer ─▶ reason 8 after one SavePlace (connection/inventory.answered)
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
//// - **A currency total is saved at once** by the store's `SetCurrency`, fenced by the
////   login's session epoch and the total the connection holds (a missing row is 0), so a
////   repeat of it or a set by another login changes nothing. The connection holds the
////   new total only from the answer: a set the store committed and the connection never
////   heard of is the database's, and the next login loads it.
//// - **The client's wallet is set by 0x919**, with 0xdd for the gain when the total is
////   higher (`opcode.0x919`, `opcode.0xdd.with_0x919`).
//// - **Lines read after an ask**: bytes, map messages and timers that arrive in
////   `Granting` are held until the answer, as in `Buying`, so a second line reads the
////   new total.

import genesis_prime/client_connection.{
  type Answer, type Request, Asking, Continue, Done,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat
import genesis_prime/game/connection/chat as connection_chat
import genesis_prime/game/connection/experience as connection_experience
import genesis_prime/game/connection/inventory as connection_inventory
import genesis_prime/game/connection/state.{
  type Session, AwaitingHelloReply, Buying, ClaimingSession, EnteringWorld,
  Granting, InCharacterSelect, InWorld, LeavingMap, MovingItem, SavingPlace,
  Selling, Session, SpendingCharge, Summoning, TakingSessionKey, TurningIn,
  WaitingToClaim,
} as connection_state
import genesis_prime/game/currency
import genesis_prime/game/dev_command
import genesis_prime/game/experience.{type Progress, Already, Lowering, Progress}
import genesis_prime/game/movement
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store
import genesis_prime/table/currency_type
import genesis_prime/table/id.{CurrencyTypeId}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

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
    dev_command.SetCurrency(
      currency_type_id: CurrencyTypeId(type_number),
      amount:,
    ) -> granting(session:, now:, written:, type_number:, amount:)
  }
}

/// A `!currency` line: the connection logs it, asks the store to set the currency to
/// `amount` while the player holds what `Entered` holds, and waits in `Granting`. A
/// status other than `InWorld` cannot have taken the line, so it is a bug that ends the
/// connection.
fn granting(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  type_number type_number: Int,
  amount amount: Int,
) -> client_connection.Handled(Session) {
  case session.status {
    InWorld(holder:, entered:) -> {
      let held =
        currency.held(
          currencies: entered.currencies,
          currency_type_id: type_number,
        )
      let logged =
        connection_state.log(
          session:,
          level: step.LogInfo,
          text: "dev command "
            <> currency_named(type_number:, amount:)
            <> ": held "
            <> int.to_string(held),
        )
      connection_state.ask(
        session: Session(
          ..session,
          status: Granting(
            holder:,
            entered:,
            grant: dev_command.Grant(currency_type_id: type_number, held:),
          ),
        ),
        now:,
        request: client_connection.AskStore(
          store.Items(store.SetCurrency(
            account_id: holder.account_id,
            character_id: entered.character_id,
            session_epoch: movement.session_epoch(state: entered.movement),
            currency_type_id: type_number,
            held:,
            after: amount,
          )),
        ),
        before: list.append(written, [logged]),
      )
    }
    Summoning(..)
    | MovingItem(..)
    | SpendingCharge(..)
    | Buying(..)
    | Granting(..)
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
        text: "!currency was run while the player was not in the world",
      )
  }
}

/// The command as the player typed it.
fn currency_named(type_number type_number: Int, amount amount: Int) -> String {
  "!currency " <> int.to_string(type_number) <> " " <> int.to_string(amount)
}

/// The store's answer to a `!currency` ask: the player is in the world again with the
/// currency total the answer holds and the client's frames and one system line written,
/// or the failure logged and one system line written with nothing changed; a store that
/// did not answer ends the connection with reason 8 (`connection/inventory.answered`).
pub fn granted(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  grant grant: dev_command.Grant,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  connection_inventory.answered(
    session:,
    now:,
    holder:,
    entered:,
    what: "dev command !currency " <> int.to_string(grant.currency_type_id),
    asked: "a currency set",
    outcome:,
    saved: fn(session, answer) {
      let session = Session(..session, status: InWorld(holder:, entered:))
      case answer {
        store.CurrencySet(amount:) ->
          set(session:, entered:, holder:, grant:, amount:)
        store.ItemsNotSaved ->
          not_set(
            session:,
            grant:,
            level: step.LogWarning,
            because: "the character's total is not the one the connection held, or another login holds the character; nothing changed",
          )
        store.SaveRefused(constraint:) ->
          not_set(
            session:,
            grant:,
            level: step.LogError,
            because: "the store refused the change by the constraint "
              <> constraint
              <> "; nothing changed",
          )
        store.ItemsSaved
        | store.ItemMade(..)
        | store.Bought(..)
        | store.Sold(..)
        | store.TurnedIn(..) ->
          connection_inventory.lost(
            session:,
            now:,
            holder:,
            entered:,
            text: "dev command !currency "
              <> int.to_string(grant.currency_type_id)
              <> ": the answer is none a currency set asked for",
          )
      }
    },
  )
}

/// The player holding `amount` of the currency: the client is sent the total and, when
/// it is higher than before, the gain, then one system line names the currency and the
/// total.
fn set(
  session session: Session,
  entered entered: world_entry.Entered,
  holder holder: Holder,
  grant grant: dev_command.Grant,
  amount amount: Int,
) -> client_connection.Handled(Session) {
  let entered =
    world_entry.Entered(
      ..entered,
      currencies: currency.with_amount(
        currencies: entered.currencies,
        currency_type_id: grant.currency_type_id,
        total: amount,
      ),
    )
  let session = Session(..session, status: InWorld(holder:, entered:))
  let frames =
    currency.total_frames(
      currency_type_id: grant.currency_type_id,
      before: grant.held,
      total: amount,
    )
  Continue(
    session,
    list.append(list.map(frames, connection_state.to_client(session, _)), [
      line(
        session:,
        text: currency_name(session:, currency_type_id: grant.currency_type_id)
          <> " "
          <> int.to_string(amount),
      ),
    ]),
  )
}

/// A currency that was not set: one log and one system line, with the player as it was.
fn not_set(
  session session: Session,
  grant grant: dev_command.Grant,
  level level: step.LogLevel,
  because because: String,
) -> client_connection.Handled(Session) {
  let named = "!currency " <> int.to_string(grant.currency_type_id)
  Continue(session, [
    connection_state.log(
      session:,
      level:,
      text: "dev command " <> named <> " was not set: " <> because,
    ),
    line(session:, text: named <> " was not set"),
  ])
}

/// The currency's name as the CurrencyType table gives it, in lower case. The tables
/// check the type before the command is run, so its row is there.
fn currency_name(
  session session: Session,
  currency_type_id currency_type_id: Int,
) -> String {
  let assert Ok(row) =
    currency_type.get(
      tables: session.settings.tables,
      id: CurrencyTypeId(currency_type_id),
    )
    as "the command's check requires the type's CurrencyType row"
  string.lowercase(row.description)
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
