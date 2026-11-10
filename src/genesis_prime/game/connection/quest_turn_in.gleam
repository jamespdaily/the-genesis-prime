//// The player's turn-in of a quest on the game connection (genesis_prime/game/connection): the
//// client's 0x035D, and the store's answer to the turn-in it asked for. The rule's decisions are
//// genesis_prime/game/quest_turn_in's, which holds the checks and the rewards; this module carries
//// them out.
////
//// ```
//// 0x35D ─▶ quest_turn_in.take(entered, picture, body) ─▶ Refused(log once per reason, or 0x106 27)   status stays InWorld
////                                                     └▶ Asks(turn_in) ─▶ AskStore(Items(TurnInQuest ...))   status TurningIn(holder, entered, turn_in), frames held
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
import genesis_prime/game/vendor_trade as trade_rule
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{type Now, type Outcome}
import genesis_prime/store.{ForItems}
import gleam/list
import gleam/option.{Some}

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
      progress: experience.Progress(
        experience: entered.experience,
        level: connection_state.level_of(entered:),
      ),
      currencies: entered.currencies,
      item_proficiencies: character_state.item_proficiencies(
        tables:,
        class_id: entered.character.class_id,
      ),
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
    Ok(quest_turn_in.Asks(turn_in:, effects:, logged:)) -> {
      let tables = session.settings.tables
      let #(link, entropy) =
        client_connection.draw(
          session.link,
          quest_turn_in.entropy_needed(turn_in:, tables:),
        )
      let turn_in = quest_turn_in.rolled(turn_in:, tables:, entropy:)
      let #(advanced, save_sequence) =
        movement.next_save(state: entered.movement)
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
        before: vendor_trade.effects_of(session:, effects:),
      )
    }
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: quest_rule.describe_refusal(refusal:),
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
  let timers =
    list.map(
      quest_log.deadline_moved(
        before: quest_log.next_deadline(log: before),
        after: quest_log.next_deadline(log: entered.quests),
        now_ms: now.monotonic_ms,
      ),
      connection_state.quest_deadline_timer_move,
    )
  case
    connection_experience.gained(
      session:,
      now:,
      entered:,
      credited: turn_in.credited,
    )
  {
    Continue(session, told) -> {
      let #(session, settled) = connection_objective.settled(session:, now:)
      Continue(
        session,
        list.flatten([
          vendor_trade.effects_of(session:, effects: rewards),
          told,
          vendor_trade.effects_of(session:, effects: then),
          timers,
          settled,
        ]),
      )
    }
    client_connection.Asking(..) as ended
    | client_connection.Done(..) as ended -> ended
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
