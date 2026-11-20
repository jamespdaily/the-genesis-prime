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
////   SetCurrency                      ─▶ info log, store SetCurrency asked, status Granting
////        granted: CurrencySet ─▶ 0x919 (0xdd when higher), one system line
////                 ItemsNotSaved, SaveRefused ─▶ log, one "not set" line, nothing changes
////                 no answer ─▶ reason 8 after one SavePlace (connection/inventory.answered)
////   CompleteQuest                    ─▶ quest_log.finished
////        finished ─▶ one system line, nothing changes
////        else ─▶ quest_log.complete, info log, 0x35C state 3, the deadline timer moved,
////                connection/objective.settled, one system line
////   Go ─▶ dead ─▶ one system line, nothing changes
////      └ the player's world ─▶ info log, the current cast stopped, projector.placed_at,
////                              one system line, objectives settled
////      └ another world ─▶ info log, world.leaving_to (the unit leaves its viewers, the map is asked
////                          to take the player out) ─▶ Left ─▶ the new map's join ─▶ Joined: the
////                          entry burst, the chat burst, one system line
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
//// - **A `!go` into another world is the leave and join of the Holocrypt's move**
////   (`world.leaving_to`): the player keeps its items, credits, quests, level, experience and
////   saved health, and the place is saved by the next stay's timer, so a connection that ends
////   while it leaves or joins makes no final save. The line comes after the join.
//// - **A `!go` refuses while the player is dead**, as the departures' move does.

import genesis_prime/client_connection.{
  type Answer, type Request, Asking, Continue, Done,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/chat as connection_chat
import genesis_prime/game/connection/experience as connection_experience
import genesis_prime/game/connection/inventory as connection_inventory
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/projector as connection_projector
import genesis_prime/game/connection/state.{
  type Session, AwaitingHelloReply, Buying, ClaimingSession, EnteringWorld,
  Granting, InCharacterSelect, InWorld, LeavingMap, MovingItem, SavingPlace,
  Selling, Session, SpendingCharge, Summoning, TakingSessionKey, TurningIn,
  WaitingToClaim,
} as connection_state
import genesis_prime/game/connection/vendor_purchase as connection_vendor_purchase
import genesis_prime/game/connection/world as connection_world
import genesis_prime/game/currency
import genesis_prime/game/deadline_timer
import genesis_prime/game/dev_command
import genesis_prime/game/experience.{type Progress, Already, Lowering, Progress}
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/quest_log
import genesis_prime/game/start_place
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store
import genesis_prime/table/currency_type
import genesis_prime/table/id.{type Item2Id, CurrencyTypeId}
import gleam/float
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
    dev_command.GiveItem(item2_id:, count:) ->
      given(session:, now:, written:, item2_id:, count:)
    dev_command.CompleteQuest(quest2_id:) ->
      completed(session:, now:, written:, quest_id: quest2_id.value)
    dev_command.Go(destination:) -> went(session:, now:, written:, destination:)
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
        text: "!item was run while the player was not in the world",
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

/// The state 0x35C gives a completed quest.
const completed_state = 3

/// A `!go`: the player placed at the destination when it is in their world, taken to
/// the map of its world when it is in another (`crossed`), or one system line and
/// nothing changed when the player is dead or the tables lack what the place needs. A
/// status other than `InWorld` cannot have taken the line, so it is a bug that ends
/// the connection.
fn went(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  destination destination: dev_command.Destination,
) -> client_connection.Handled(Session) {
  case session.status {
    InWorld(holder:, entered:) ->
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
                False ->
                  crossed(session:, now:, holder:, entered:, written:, place:)
              }
          }
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
        text: "!go was run while the player was not in the world",
      )
  }
}

const dead_text = "!go is refused while the player is dead"

/// Where a `!go` put the player, for its log and its system line.
fn described(place place: start_place.Place) -> String {
  "world "
  <> int.to_string(start_place.world_id(place))
  <> ", zone "
  <> int.to_string(start_place.world_zone_id(place))
  <> ", ("
  <> plain_decimal(value: start_place.x(place))
  <> ", "
  <> plain_decimal(value: start_place.y(place))
  <> ", "
  <> plain_decimal(value: start_place.z(place))
  <> ")"
}

/// A position as a plain decimal in the shortest digits that read back the same:
/// the exponent form of `float.to_string` (`-7.7e3`) is written out (`-7700.0`).
pub fn plain_decimal(value value: Float) -> String {
  case string.split(float.to_string(value), "e") {
    [mantissa, exponent] -> {
      let assert Ok(exponent) = int.parse(string.replace(exponent, "+", ""))
        as "float.to_string writes an integer exponent"
      let #(sign, mantissa) = case string.starts_with(mantissa, "-") {
        True -> #("-", string.drop_start(mantissa, 1))
        False -> #("", mantissa)
      }
      let #(whole, fraction) = case string.split(mantissa, ".") {
        [whole, fraction] -> #(whole, fraction)
        _ -> #(mantissa, "")
      }
      // The digits and where the point falls among them.
      let digits = whole <> fraction
      let point = string.length(whole) + exponent
      let #(before, after) = case point <= 0 {
        True -> #("0", string.repeat("0", -point) <> digits)
        False ->
          case point >= string.length(digits) {
            True -> #(
              digits <> string.repeat("0", point - string.length(digits)),
              "",
            )
            False -> #(
              string.slice(digits, 0, point),
              string.drop_start(digits, point),
            )
          }
      }
      sign <> before <> "." <> trimmed_fraction(fraction: after)
    }
    _ -> float.to_string(value)
  }
}

/// A fraction without its trailing zeros, one zero when nothing is left.
fn trimmed_fraction(fraction fraction: String) -> String {
  case string.ends_with(fraction, "0") {
    True -> trimmed_fraction(fraction: string.drop_end(fraction, 1))
    False ->
      case fraction {
        "" -> "0"
        _ -> fraction
      }
  }
}

/// The player taken to `place`, in another world: the info log, then the map is asked
/// to take the player out and, once it has, the map of the place's world to take it
/// in with the saved health (`world.leaving_to`). The system line comes after the
/// entry burst and nothing is saved before it. A departures landing still kept is
/// cleared, so its timer finds nothing.
fn crossed(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  written written: List(Effect(ConnectionEffect(Request))),
  place place: start_place.Place,
) -> client_connection.Handled(Session) {
  let logged =
    connection_state.log(
      session:,
      level: step.LogInfo,
      text: "dev command !go: left for " <> described(place:),
    )
  connection_world.leaving_to(
    session:,
    now:,
    holder:,
    entered: world_entry.Entered(..entered, departing: None),
    place:,
    health: Some(player_life.saved_health(life: entered.life)),
    told: Some("moved to " <> described(place:)),
    before: list.append(written, [logged]),
  )
}

/// The player placed at `place`, in their world: the current cast stopped as the
/// client's 0x83c stops it, the placement's frames, one system line and then the
/// objectives settled at the new place.
fn placed(
  session session: Session,
  now now: Now,
  written written: List(Effect(ConnectionEffect(Request))),
  place place: start_place.Place,
) -> client_connection.Handled(Session) {
  let logged =
    connection_state.log(
      session:,
      level: step.LogInfo,
      text: "dev command !go: placed at " <> described(place:),
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
      [line(session:, text: "moved to " <> described(place:))],
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
