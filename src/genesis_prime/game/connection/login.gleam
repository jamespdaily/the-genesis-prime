//// The game connection's login (genesis_prime/game/connection): the hand-off's
//// answer to the session key, the claim on Sessions and its watch, the takeover,
//// and the claim's wait after Sessions ends.
////
//// - **The claim** makes this connection the account's one session
////   (genesis_prime/account_session). It follows the hand-off's answer, since the
////   account is known only then, and comes before the list, so a client that
////   reaches character select holds the slot. The rule opens its one watch
////   on Sessions (watch 1) with each claim. Sessions answers `Claimed` to the
////   newest login's claim, sending the previous holder `TakenOver` first, and
////   answers `TakenOver` to a claim older than the holder's.
//// - **Taken over.** `Woken(TakenOver)`, when the connection holds the slot or
////   is claiming it again, or Sessions' answer `TakenOver` to a claim, writes
////   0x036A reason 19 (AccountDisconnected) under
////   the cipher the connection holds, logs the takeover at info and ends the
////   connection, after the save of the player's place when one is in the world. The client drops to its error screen and shows "This account
////   has been disconnected" (0x1400168a0, which only picks the text by the
////   reason). The message is taken between steps, never while an ask is out:
////   a takeover that arrives while the connection waits on an ask that then
////   fails is never taken, because the failure ends the connection, so that
////   client gets the failure's text (reason 8) and not the account's. Both
////   texts end the connection; taking a delivery during an ask would make the
////   shell decide by a message's content.
//// - **Sessions ending.** When the watch on Sessions ends (`WatchEnded`) the
////   connection waits `claim_wait_ms` on a timer, since a restarted Sessions
////   is not yet there, then claims again (`TimerFired`), with the frames it
////   holds waiting for the answer; the client sees nothing. The end of a watch
////   is taken only between steps, when no ask of character select is out and
////   its state is at rest, so the connection resumes in a new one. When a
////   newer login of the account claimed first, Sessions answers the claim
////   `TakenOver` and the connection ends as a takeover does. A claim that finds Sessions not running (the
////   outcome `NotRunning`) drops its watch and waits again, up to
////   `claim_retries` times, before the client is told the server failed. A
////   claim Sessions does not answer, or that ends before its answer, is that
////   failure at once. The wait is its own status (`WaitingToClaim`), so the
////   timer's firing is taken only there, and an answer only while the claim's
////   ask is out (`ClaimingSession`); either in the other is a bug.
//// - **Sessions ending in the world.** The claim again keeps where the
////   client is: character select, or the player in the world, whose save, quest
////   reset and quest deadline timers are cancelled while the claim waits and
////   started again when it is answered.

import genesis_prime/account_session
import genesis_prime/client_connection.{
  type Answer, AskSessions, Continue, Done, FromHandOff, FromMap, FromSessions,
  FromStore,
}
import genesis_prime/game/character_select
import genesis_prime/game/connection/state.{
  type Resume, type Session, AwaitingHelloReply, Buying, ClaimingSession,
  EnteringWorld, InCharacterSelect, InWorld, LeavingMap, MovingItem,
  ResumeSelect, ResumeWorld, SavingPlace, Selling, Session, Summoning,
  TakingSessionKey, TurningIn, WaitingToClaim,
} as connection_state
import genesis_prime/game/connection/world as connection_world
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/step.{
  type Now, type Outcome, type TimerId, type WatchId, CancelTimer, LogInfo,
  LogWarning, OwnEffect, Sessions, StartTimer, TimerId, Unwatch, Watch, WatchId,
}
import gleam/list

/// How long a connection waits before it claims again after Sessions ended or
/// was not running. A restarted Sessions is started by its supervisor at once,
/// so a short wait finds it; the client's screen shows nothing meanwhile.
pub const claim_wait_ms = 100

/// How many times a claim that finds Sessions not running is made again.
/// With the wait, it bounds how long a client waits on its prompt for a
/// Sessions that does not come back: half a second, then it is told the
/// server failed, as for the store.
pub const claim_retries = 5

/// The watch on Sessions: the connection's only one. A watch that ends is
/// forgotten by the shell, and one dropped with `Unwatch` leaves nothing behind,
/// so the id is free whenever a claim opens it again, and a watch left open is
/// caught by the shell's refusal of an id already open.
const sessions_watch = WatchId(1)

/// The timer a connection waits on before it claims again; one runs at a
/// time.
const claim_timer = TimerId(1)

/// The hand-off's answer to taking the session key: the holder, whose account
/// Sessions is asked to claim, or a client that is told it is disconnected.
pub fn key_taken(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromHandOff(hand_off.Taken(holder:))) ->
      claim(session:, now:, holder:, resume: ResumeSelect, retries: 0)
    step.Answer(FromHandOff(hand_off.NoHolder)) ->
      connection_state.told(
        session:,
        now:,
        reason: AccountDisconnected,
        level: LogWarning,
        text: "the hand-off does not hold the session key",
      )
    step.Answer(FromHandOff(hand_off.Kept))
    | step.Answer(FromHandOff(hand_off.AlreadyHeld))
    | step.Answer(FromStore(..))
    | step.Answer(FromSessions(..))
    | step.Answer(FromMap(..)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the hand-off's answer is none a Take gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the hand-off", outcome:),
      )
    step.StoppedWaiting -> connection_state.stopped(session, now)
  }
}

/// Opens a watch on Sessions and asks it to make this connection the account's
/// session; `resume` is where the client is once it answers. The watch is
/// opened with every claim, so a restarted Sessions is watched again.
fn claim(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  resume resume: Resume,
  retries retries: Int,
) -> client_connection.Handled(Session) {
  connection_state.ask(
    session: Session(
      ..session,
      status: ClaimingSession(holder:, resume:, retries:),
    ),
    now:,
    request: AskSessions(account_session.Claim(
      account: holder.account_id,
      connection: client_connection.connection(session.link),
    )),
    before: [Watch(watch: sessions_watch, target: Sessions)],
  )
}

/// Sessions' answer to the claim: `Claimed` puts the client where it was, in
/// character select or in the world, and the frames held are taken. `TakenOver`
/// means a newer login of the account holds the slot: the connection ends as a
/// takeover does. Sessions not running is waited out up to `claim_retries`
/// times, with the watch dropped; any other failure of the ask tells the client
/// the server failed, as the store's do.
pub fn claim_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  resume resume: Resume,
  retries retries: Int,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromSessions(account_session.Claimed)) ->
      case resume {
        ResumeSelect ->
          Continue(
            Session(
              ..session,
              status: InCharacterSelect(holder:, select: character_select.new()),
            ),
            [],
          )
        ResumeWorld(entered:) ->
          connection_world.claimed_again(session:, now:, holder:, entered:)
      }
    step.Answer(FromSessions(account_session.TakenOver)) ->
      taken_over(session, now)
    step.Answer(FromStore(..))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromMap(..)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "Sessions' answer is none a claim gets",
      )
    step.NotRunning if retries < claim_retries ->
      Done(
        Session(
          ..session,
          status: WaitingToClaim(holder:, resume:, retries: retries + 1),
        ),
        [
          Unwatch(watch: sessions_watch),
          OwnEffect(StartTimer(timer: claim_timer, after_ms: claim_wait_ms)),
        ],
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "Sessions", outcome:),
      )
    step.StoppedWaiting ->
      case resume {
        // The stop that cut the claim short comes as the shell's next input
        // and saves the player, so the player goes back to the world.
        ResumeWorld(entered:) ->
          Done(Session(..session, status: InWorld(holder:, entered:)), [])
        ResumeSelect -> connection_state.stopped(session, now)
      }
  }
}

/// A newer login of the account holds the session: the client is told its
/// account was disconnected (0x036A reason 19) and the connection ends, after
/// the save of the player's place when it holds one in the world.
fn taken_over(
  session: Session,
  now: Now,
) -> client_connection.Handled(Session) {
  connection_state.told(
    session:,
    now:,
    reason: AccountDisconnected,
    level: LogInfo,
    text: "a newer login of the account holds the session",
  )
}

/// What Sessions sent the connection: `TakenOver` tells the client its account
/// was disconnected (0x036A reason 19) and ends the connection. `Claimed` is
/// an answer, never sent, and is a bug, as is a takeover before the connection
/// has claimed.
pub fn sessions_sent(
  session session: Session,
  now now: Now,
  message message: account_session.Outgoing,
) -> client_connection.Handled(Session) {
  case message, session.status {
    account_session.TakenOver, InCharacterSelect(..)
    | account_session.TakenOver, ClaimingSession(..)
    | account_session.TakenOver, WaitingToClaim(..)
    | account_session.TakenOver, EnteringWorld(..)
    | account_session.TakenOver, InWorld(..)
    | account_session.TakenOver, Summoning(..)
    | account_session.TakenOver, MovingItem(..)
    | account_session.TakenOver, Buying(..)
    | account_session.TakenOver, Selling(..)
    | account_session.TakenOver, TurningIn(..)
    | account_session.TakenOver, SavingPlace(..)
    | account_session.TakenOver, LeavingMap(..)
    -> taken_over(session, now)
    account_session.TakenOver, AwaitingHelloReply
    | account_session.TakenOver, TakingSessionKey
    ->
      connection_state.end_for(
        session:,
        now:,
        text: "Sessions sent a takeover before the claim",
      )
    account_session.Claimed, _ ->
      connection_state.end_for(
        session:,
        now:,
        text: "Sessions sent an answer as a message",
      )
  }
}

/// The end of a watch the connection's own rule opened: Sessions or the map.
pub fn own_watch_ended(
  session session: Session,
  now now: Now,
  watch watch: WatchId,
) -> client_connection.Handled(Session) {
  case session.status, watch {
    InCharacterSelect(holder:, ..), id if id == sessions_watch ->
      waiting_to_claim(session:, holder:, resume: ResumeSelect)
    InWorld(holder:, entered:), id if id == sessions_watch ->
      waiting_to_claim(session:, holder:, resume: ResumeWorld(entered:))
    InWorld(..), id
    | ClaimingSession(resume: ResumeWorld(..), ..), id
    | WaitingToClaim(resume: ResumeWorld(..), ..), id
      if id == connection_state.map_watch
    ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: "the map the player is in ended",
      )
    InCharacterSelect(..), _
    | InWorld(..), _
    | ClaimingSession(..), _
    | WaitingToClaim(..), _
    | EnteringWorld(..), _
    | Summoning(..), _
    | MovingItem(..), _
    | Buying(..), _
    | Selling(..), _
    | TurningIn(..), _
    | SavingPlace(..), _
    | LeavingMap(..), _
    | AwaitingHelloReply, _
    | TakingSessionKey, _
    ->
      connection_state.end_for(
        session:,
        now:,
        text: "a watch the rule did not open ended",
      )
  }
}

/// The connection waits on the claim timer before it claims its account
/// again, with the place of the client kept. A player in the world is not
/// saved by the timer meanwhile, and no quest timer fires: the save, quest reset
/// and quest deadline timers are cancelled, and a firing already waiting is dropped
/// by the shell. The claim starts them again (`connection/world.claimed_again`).
fn waiting_to_claim(
  session session: Session,
  holder holder: Holder,
  resume resume: Resume,
) -> client_connection.Handled(Session) {
  let cancelled = case resume {
    ResumeSelect -> []
    ResumeWorld(..) -> [
      OwnEffect(CancelTimer(timer: connection_state.save_timer)),
      OwnEffect(CancelTimer(timer: connection_state.quest_reset_timer)),
      OwnEffect(CancelTimer(timer: connection_state.quest_deadline_timer)),
    ]
  }
  Done(
    Session(..session, status: WaitingToClaim(holder:, resume:, retries: 0)),
    list.append(cancelled, [
      OwnEffect(StartTimer(timer: claim_timer, after_ms: claim_wait_ms)),
    ]),
  )
}

/// The claim timer fired: the connection claims again. A timer the rule did
/// not start, or one that fires when the connection is not waiting on it, is
/// a bug.
pub fn claim_wait_over(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case session.status {
    WaitingToClaim(holder:, resume:, retries:) if timer == claim_timer ->
      claim(session:, now:, holder:, resume:, retries:)
    WaitingToClaim(..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | InWorld(..)
    | Summoning(..)
    | MovingItem(..)
    | Buying(..)
    | Selling(..)
    | TurningIn(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey ->
      connection_state.end_for(
        session:,
        now:,
        text: "a timer the rule did not start fired",
      )
  }
}
