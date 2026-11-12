//// The player's turn-in of a quest on the game connection (genesis_prime/game/connection): the
//// client's 0x035D, and the store's answer to the turn-in it asked for. The rule's decisions are
//// genesis_prime/game/quest_turn_in's, which holds the checks and the rewards; this module carries
//// them out. It also completes, for the player, each quest no creature receives once its
//// objectives are done (`completing`).
////
//// ```
//// 0x35D ─▶ quest_turn_in.take(entered, picture, body) ─▶ Refused(log once per reason, or 0x106 27)   status stays InWorld
////                                                     └▶ Asks(turn_in) ─▶ AskStore(Items(TurnInQuest ...))   status TurningIn(holder, entered, turn_in), frames held
//// end of each input that goes on with the player in the world, `Entered.completing` not empty
////    ─▶ quest_turn_in.completed_by_server(head) ─▶ Refused(logged once; the next is taken)
////                                              └▶ Asks(turn_in) ─▶ the same ask as above; the answer is `answered`'s
//// store worker: lock_character_for_save, save_place.sql, then turn_in_rewards.sql, one transaction
////    ─▶ TurnedIn(credits, made) ─▶ answered: entered.items, entered.currencies and entered.quests updated; then in order
////                                  0x111 reason 8 per stack made, a count change per stack grown,
////                                  the experience's frames (0x1ac kind 3, 0x938 and the Level news, the Base Health),
////                                  0x919, 0x35C {quest, 3, 0}, then the frames of the held-item objectives the reward
////                                  items advanced (`connection_objective.settled`); status InWorld; held frames replayed
////    ─▶ ItemsNotSaved | SaveRefused(constraint) ─▶ a warning or an error line; nothing in memory changes; status InWorld
////    ─▶ unavailable, not running, past deadline ─▶ the connection ends, reason 8 (as a buy)
//// ```
////
//// | Case | Killed there | Twice at once | Times out |
//// |---|---|---|---|
//// | take, before asking | nothing written, and the client's dialog stays | a second 0x35D is held while TurningIn, then taken against the new log | n/a |
//// | store asked, transaction open | Postgres rolls back; the monitor ends the connection with reason 8; the next login loads the old state | the epoch fence, the save's number and the guard on the credits held make the second change nothing | the connection ends with reason 8, and the result, if it commits, is loaded next login |
//// | store answered, before `answered` runs | the turn-in is saved; the next login loads it | n/a (frames held) | n/a |
//// | connection dies while TurningIn | the store finishes or rolls back; the next login loads whichever | n/a | n/a |

import genesis_prime/client_connection.{Continue, FromStore}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/character_state
import genesis_prime/game/connection/experience as connection_experience
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/quest as connection_quest
import genesis_prime/game/connection/state.{
  type Session, InWorld, Session, TurningIn,
} as connection_state
import genesis_prime/game/connection/vendor_trade
import genesis_prime/game/experience
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/quest as quest_rule
import genesis_prime/game/quest_log
import genesis_prime/game/quest_turn_in
import genesis_prime/game/shown
import genesis_prime/game/tutorial
import genesis_prime/game/vendor_trade as trade_rule
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store.{ForItems}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}

/// The client's 0x035D, taken from inside 0x038C with the player in the world: a refusal is
/// written or logged and the player stays in the world; an accepted turn-in asks the store and
/// the connection waits in `TurningIn`; a body the client's reader would refuse ends the
/// connection.
pub fn turn_in_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  let tables = session.settings.tables
  case
    quest_turn_in.take(
      body: inner.body,
      asker: connection_quest.asker(session:, entered:),
      standing: interaction.Player(
        race_id: entered.character.race_id,
        faction:,
        place: movement.place(state: entered.movement),
      ),
      picture: entered.shown,
      progress: progress_of(entered:),
      currencies: entered.currencies,
      item_proficiencies: proficiencies_of(tables:, entered:),
      life: entered.life,
      tables:,
      now_ms: now.monotonic_ms,
      unix_seconds: step.unix_milliseconds(now:) / 1000,
      logged: session.interaction_logged,
    )
  {
    Ok(quest_turn_in.Refused(effects:, logged:)) ->
      Continue(
        Session(..session, interaction_logged: logged),
        vendor_trade.effects_of(session:, effects:),
      )
    Ok(quest_turn_in.Asks(turn_in:, effects:, logged:)) ->
      asking(
        session:,
        now:,
        holder:,
        entered:,
        turn_in:,
        before: vendor_trade.effects_of(session:, effects:),
        logged:,
      )
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: quest_rule.describe_refusal(refusal:),
      )
  }
}

/// The player's experience and level, as a turn-in reads them.
fn progress_of(entered entered: world_entry.Entered) -> experience.Progress {
  experience.Progress(
    experience: entered.experience,
    level: connection_state.level_of(entered:),
  )
}

/// The item proficiencies of the player's class, as a turn-in reads them.
fn proficiencies_of(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
) -> Int {
  character_state.item_proficiencies(
    tables:,
    class_id: entered.character.class_id,
  )
}

/// The ask for an accepted turn-in, after the effects `before`: the entropy the rewards need is
/// drawn, the place's save sequence taken and the connection waits in `TurningIn`.
fn asking(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  turn_in turn_in: quest_turn_in.TurnIn,
  before before: List(Effect(ConnectionEffect(client_connection.Request))),
  logged logged: Set(String),
) -> client_connection.Handled(Session) {
  let tables = session.settings.tables
  let #(link, entropy) =
    client_connection.draw(
      session.link,
      quest_turn_in.entropy_needed(turn_in:, tables:),
    )
  let turn_in = quest_turn_in.rolled(turn_in:, tables:, entropy:)
  let #(advanced, save_sequence) = movement.next_save(state: entered.movement)
  connection_state.ask(
    session: Session(
      ..session,
      link:,
      interaction_logged: logged,
      status: TurningIn(
        holder:,
        entered: world_entry.Entered(..entered, movement: advanced),
        turn_in:,
      ),
    ),
    now:,
    request: client_connection.AskStore(quest_turn_in.request(
      turn_in:,
      account_id: holder.account_id,
      character_id: entered.character_id,
      session_epoch: movement.session_epoch(state: entered.movement),
      save_sequence:,
      place: movement.place(state: entered.movement),
      health: Some(player_life.saved_health(life: entered.life)),
      quests: quest_log.rows(log: turn_in.log, now_ms: now.monotonic_ms),
    )),
    before:,
  )
}

/// What an input decided, with the next quest the server owes the player completed after it
/// (`Entered.completing`; `quest_turn_in.completed_by_server`): only an input that goes on with
/// the player in the world takes one, and it takes the oldest. A quest the rule refuses is logged
/// once and left Achieved in the log, and the next one is taken; one it accepts asks the store
/// like a turn-in, and the answer goes through `turn_in_answered`. The quests left wait for the
/// end of that answer's input.
pub fn completing(
  handled handled: client_connection.Handled(Session),
  now now: Now,
) -> client_connection.Handled(Session) {
  case handled {
    Continue(session:, effects:) ->
      case connection_state.standing(session.status) {
        connection_state.Present(holder:, entered:) ->
          case entered.completing {
            [] -> handled
            [quest_id, ..rest] -> {
              let entered = world_entry.Entered(..entered, completing: rest)
              completed(
                session: Session(..session, status: InWorld(holder:, entered:)),
                now:,
                holder:,
                entered:,
                quest_id:,
                before: effects,
              )
            }
          }
        connection_state.Greeting
        | connection_state.Selecting(..)
        | connection_state.Busy(..) -> handled
      }
    client_connection.Asking(..) | client_connection.Done(..) -> handled
  }
}

/// The rule's completion of one quest, after the effects `before`: a refusal is logged and the
/// next quest taken, an accepted one asks the store.
fn completed(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  quest_id quest_id: Int,
  before before: List(Effect(ConnectionEffect(client_connection.Request))),
) -> client_connection.Handled(Session) {
  let tables = session.settings.tables
  case
    quest_turn_in.completed_by_server(
      quest_id:,
      asker: connection_quest.asker(session:, entered:),
      progress: progress_of(entered:),
      currencies: entered.currencies,
      item_proficiencies: proficiencies_of(tables:, entered:),
      tables:,
      unix_seconds: step.unix_milliseconds(now:) / 1000,
      logged: session.interaction_logged,
    )
  {
    quest_turn_in.Refused(effects:, logged:) ->
      completing(
        handled: Continue(
          Session(..session, interaction_logged: logged),
          list.append(before, vendor_trade.effects_of(session:, effects:)),
        ),
        now:,
      )
    quest_turn_in.Asks(turn_in:, effects:, logged:) ->
      asking(
        session:,
        now:,
        holder:,
        entered:,
        turn_in:,
        before: list.append(before, vendor_trade.effects_of(session:, effects:)),
        logged:,
      )
  }
}

/// The store's answer to the turn-in: the player is in the world again with the quest
/// Completed and the rewards the answer leaves, and the frames written; a store that failed
/// ends the connection with reason 8.
pub fn turn_in_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  turn_in turn_in: quest_turn_in.TurnIn,
  outcome outcome: Outcome(client_connection.Answer),
) -> client_connection.Handled(Session) {
  let what = quest_turn_in.not_turned_in(turn_in:)
  case outcome {
    step.Answer(FromStore(ForItems(answer))) ->
      case
        quest_turn_in.answered(
          turn_in:,
          items: entered.items,
          currencies: entered.currencies,
          answer:,
        )
      {
        quest_turn_in.Saved(items:, currencies:, rewards:, then:) ->
          saved(
            session:,
            now:,
            holder:,
            entered: world_entry.Entered(
              ..entered,
              items:,
              currencies:,
              quests: turn_in.log,
            ),
            before: entered.quests,
            turn_in:,
            rewards:,
            then:,
          )
        quest_turn_in.NotSaved(effects:) -> {
          let session = Session(..session, status: InWorld(holder:, entered:))
          Continue(session, vendor_trade.effects_of(session:, effects:))
        }
      }
    step.StoppedWaiting -> connection_state.stopped(session, now)
    step.Answer(FromStore(store.Unavailable)) ->
      lost(session:, now:, text: what <> ": the store is unavailable")
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      lost(
        session:,
        now:,
        text: what
          <> ": "
          <> client_connection.without_answer(who: "the store", outcome:),
      )
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForSelect(..)))
    | step.Answer(FromStore(store.ForWorld(..)))
    | step.Answer(FromStore(store.ForMove(..)))
    | step.Answer(client_connection.FromHandOff(..))
    | step.Answer(client_connection.FromSessions(..))
    | step.Answer(client_connection.FromMap(..)) ->
      lost(
        session:,
        now:,
        text: what <> ": the answer is none a turn-in asked for",
      )
  }
}

/// The player in the world with what the turn-in left (`entered` holds the items, credits and
/// quest log after it, `before` the log before it): the item frames, the experience's frames,
/// then the credits and the quest's state, and the quest deadline's timer moved when the
/// completed quest was the one running out.
fn saved(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  before before: quest_log.QuestLog,
  turn_in turn_in: quest_turn_in.TurnIn,
  rewards rewards: List(trade_rule.Effect),
  then then: List(trade_rule.Effect),
) -> client_connection.Handled(Session) {
  let session = Session(..session, status: InWorld(holder:, entered:))
  case
    connection_experience.gained(
      session:,
      now:,
      entered:,
      credited: turn_in.credited,
    )
  {
    Continue(session, told) -> {
      let #(session, next) = next_tutorial_quest(session:, now:, turn_in:)
      let after = case connection_state.entered_of(session.status) {
        Some(entered) -> entered.quests
        None -> turn_in.log
      }
      let timers =
        list.map(
          quest_log.deadline_moved(
            before: quest_log.next_deadline(log: before),
            after: quest_log.next_deadline(log: after),
            now_ms: now.monotonic_ms,
          ),
          connection_state.quest_deadline_timer_move,
        )
      let #(session, settled) = connection_objective.settled(session:, now:)
      Continue(
        session,
        list.flatten([
          vendor_trade.effects_of(session:, effects: rewards),
          told,
          vendor_trade.effects_of(session:, effects: then),
          next,
          timers,
          settled,
        ]),
      )
    }
    client_connection.Asking(..) as ended
    | client_connection.Done(..) as ended -> ended
  }
}

/// The session with the tutorial quest the completed quest leads to, and the 0x35C that
/// tells the client, when the completed quest is one of the tutorial chain and the log
/// holds the quest due next (`tutorial.grant`); the session and nothing otherwise.
fn next_tutorial_quest(
  session session: Session,
  now now: Now,
  turn_in turn_in: quest_turn_in.TurnIn,
) -> #(Session, List(Effect(ConnectionEffect(client_connection.Request)))) {
  let chain = session.settings.tutorial_chain
  let granted = case connection_state.entered_of(session.status) {
    Some(entered) ->
      case tutorial.is_chain_quest(chain:, quest_id: turn_in.quest_id) {
        True ->
          tutorial.grant(
            chain:,
            log: entered.quests,
            faction_id: entered.character.faction_id,
            tables: session.settings.tables,
            now_ms: now.monotonic_ms,
          )
        False -> None
      }
    None -> None
  }
  case granted {
    Some(tutorial.Granted(log:, frame:)) -> {
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, quests: log)
        })
      #(session, [connection_state.to_client(session, frame)])
    }
    None -> #(session, [])
  }
}

/// The connection ends with reason 8 and asks the store nothing more: the status stays
/// `TurningIn`, whose request saved the place, and a later save would carry the quest log and
/// experience from before the turn-in.
fn lost(
  session session: Session,
  now now: Now,
  text text: String,
) -> client_connection.Handled(Session) {
  connection_state.told(
    session:,
    now:,
    reason: LostUserServer,
    level: step.LogError,
    text:,
  )
}
