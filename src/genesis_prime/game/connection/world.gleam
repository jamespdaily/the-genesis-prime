//// The player's stay in the world on the game connection
//// (genesis_prime/game/connection): world entry's answers, the camp, the saves
//// of the player's place and their answers, leaving the map, and joining again
//// at the Holocrypt.
////
//// - **Entering the world** is world entry's own feature
////   (genesis_prime/game/world_entry), as character select is: it asks the
////   store and the map, and the rule turns its effects into writes, the asks
////   and its watch on the map. The map's ask goes through Maps, which starts
////   the map when it is not running (genesis_prime/world_map/registry); a map
////   that cannot be reached, ends before its answer or gives none in time
////   ends the connection with reason 8, as the store does.
//// - **In the world** the connection watches its map (watch 2): the map's
////   end, a crash or a restart of Maps, ends the connection with 0x036A
////   reason 8, since the player is gone from the world. The map watches the
////   connection, so a connection that ends leaves its map. A takeover ends
////   it with reason 19, as in character select.
//// - **A 0xC0 leaves the world in this order**: the save timer is cancelled and
////   the place saved (`SavingPlace` with `Camped`), the map's run is asked to
////   take the player out (`LeavingMap`; the 0x355 of its unit is sent to each
////   viewer in the step that asks), the watch on the map is dropped and
////   0x0594 is written with the bit set and reason 0 (opcode.0x594). The client
////   can pick a character only after 0x0594, so a play never meets a save still
////   out. The client's 0x07E0 is then answered as at login, on the same
////   connection and claim (opcode.0x594.character_select).
//// - **A save or a leave that fails goes on** when the player is no longer in a
////   map: a save with no answer is a warning, and a leave answered `Left`, to a
////   map that is not running or that ended before its answer is done. A leave
////   with no answer in time, or whose find Maps does not answer in time
////   (genesis_prime/world_map/registry `ask_run`), ends the connection with
////   0x036A reason 8: the map may still hold the player, and drops it by its
////   watch on the connection. The server stopping, and an answer that is none
////   the ask's, end it too, with no second save.
//// - **The connection stays the player's process** through a camp: the client
////   asks for nothing that needs a character to outlive its connection, and
////   no text says how long one stays (`LocalizedEnum.8879`). The camp is the
////   connection's own state, so a character is in the world only while its
////   connection is.
//// - **Saving the place.** The connection is the player's own process, so it
////   keeps the place and saves it: every `movement.save_period_ms`, and when
////   any end reaches a connection that holds a player in the world or claims
////   again with one (`end_with`), whatever the cause: the client closing, a
////   socket that fails, a takeover, the map's end, the server stopping, a
////   client that breaks the protocol, a timer or watch the rule did not open. A
////   save is one store ask with the settings' deadline, and the connection
////   takes no other input while it waits. The 60 s save leaves the player in the
////   world whatever the answer, a warning when there is none; an end writes its
////   notice and stops when the answer comes, whatever it is, so a store that does
////   not answer cannot keep a connection open. Its status stays `SavingPlace`, so
////   no input after it, a failed write of the notice among them, saves a second
////   time. The server's stop gives the save the shorter of the settings' deadline
////   and the time its own deadline leaves, and asks nothing when none is left
////   (a warning says the place was not saved). The rate and held-bytes limits end
////   the connection inside `client_connection` and save nothing: the last 60 s
////   save stands, which is all a crash of the connection's process leaves too.
////   A stop that cuts the claim short with the player in the world goes back to
////   the world, and the stop that follows saves.

import genesis_prime/client_connection.{
  type Answer, type Request, AskMapRun, Continue, Done, FromHandOff, FromMap,
  FromSessions, FromStore,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/camp
import genesis_prime/game/character_select
import genesis_prime/game/chat
import genesis_prime/game/connection/effects.{Chats, StartsSaveTimer} as connection_effects
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/select as connection_select
import genesis_prime/game/connection/state.{
  type AfterLeave, type AfterSave, type EntryFrom, type Session,
  AwaitingHelloReply, Camped, ClaimingSession, EnteringWorld,
  FromCharacterSelect, FromHolocrypt, InCharacterSelect, InWorld, JoinAt,
  Leaving, LeavingMap, Playing, SavingPlace, Session, TakingSessionKey,
  ToCharacterSelect, WaitingToClaim,
} as connection_state
import genesis_prime/game/movement
import genesis_prime/game/rating
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/top_zone
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome, LogInfo,
  LogWarning, Unwatch,
}
import genesis_prime/store
import genesis_prime/world_map/map
import genesis_prime/world_map/stay
import gleam/list

/// What the camp messages do, taken from inside 0x038C, in the world
/// (genesis_prime/game/camp): the camp is kept, its effects are carried out,
/// and a refusal ends the connection.
pub fn camp_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: camp.Message,
) -> client_connection.Handled(Session) {
  case
    camp.take(
      camp: entered.camp,
      message:,
      body: inner.body,
      countdown_ms: session.settings.game.camp_countdown_ms,
    )
  {
    Ok(#(running, effects)) ->
      connection_effects.carry_out(
        session: Session(
          ..session,
          status: InWorld(
            holder:,
            entered: world_entry.Entered(..entered, camp: running),
          ),
        ),
        now:,
        effects: list.map(effects, connection_effects.from_camp),
        written: [],
      )
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: camp.describe(refusal))
  }
}

/// The save timer fired: the player's place is saved and the timer started
/// again, and the player goes on playing once the store answers. The timer
/// runs only while the player is in the world, so a firing in any other status
/// is a bug.
pub fn save_due(
  session session: Session,
  now now: Now,
) -> client_connection.Handled(Session) {
  case session.status {
    InWorld(holder:, entered:) ->
      connection_state.saving(
        session:,
        now:,
        holder:,
        entered:,
        then: Playing,
        before: [connection_effects.start_save_timer()],
        within_ms: session.settings.ask_deadline_ms,
      )
    WaitingToClaim(..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
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

/// The store's answer to the save of the player's place: what it says is
/// logged, and then the player goes on playing or the connection ends, as
/// `then` says. A save that gets no answer is a warning, as for any store ask.
/// The status of a connection that ends stays `SavingPlace`, so an input after
/// its notice, a failed write among them, never saves a second time.
pub fn save_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  then then: AfterSave,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  let lines = case outcome {
    step.Answer(FromStore(store.ForMove(answer))) ->
      Ok(list.map(movement.saved(answer), movement_line(session, _)))
    step.Answer(FromStore(store.Unavailable)) ->
      Ok([
        connection_state.log(
          session:,
          level: LogWarning,
          text: "the place was not saved: the store is unavailable",
        ),
      ])
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      Ok([
        connection_state.log(
          session:,
          level: LogWarning,
          text: "the place was not saved: "
            <> client_connection.without_answer(who: "the store", outcome:),
        ),
      ])
    step.StoppedWaiting -> Ok([])
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForSelect(..)))
    | step.Answer(FromStore(store.ForWorld(..)))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromSessions(..))
    | step.Answer(FromMap(..)) -> Error(Nil)
  }
  case then, lines {
    Playing, Ok(lines) ->
      case outcome {
        step.StoppedWaiting ->
          Done(Session(..session, status: InWorld(holder:, entered:)), [])
        step.Answer(..)
        | step.NotRunning
        | step.NoAnswerInTime
        | step.EndedBeforeAnswer ->
          Continue(
            Session(..session, status: InWorld(holder:, entered:)),
            lines,
          )
      }
    Playing, Error(Nil) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the answer is none a save of the player's place asked for",
      )
    Leaving(notice:), Ok(lines) ->
      connection_state.left(session:, lines:, notice:)
    Leaving(notice:), Error(Nil) ->
      connection_state.left(
        session:,
        lines: [
          connection_state.log(
            session:,
            level: step.LogError,
            text: "the answer is none a save of the player's place asked for",
          ),
        ],
        notice:,
      )
    Camped, Ok(lines) ->
      case outcome {
        step.StoppedWaiting -> connection_state.stopped(session, now)
        step.Answer(..)
        | step.NotRunning
        | step.NoAnswerInTime
        | step.EndedBeforeAnswer ->
          leaving_the_map(
            session:,
            now:,
            holder:,
            entered:,
            before: lines,
            then: ToCharacterSelect,
          )
      }
    Camped, Error(Nil) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the answer is none a save of the player's place asked for",
      )
  }
}

/// The camp's save is answered, or the player chose the Holocrypt: the map's run
/// that took the player is asked to take it out, after the effects `before` and
/// the unit's 0x355 to each viewer, and the connection waits in `LeavingMap` for
/// what comes `then`.
pub fn leaving_the_map(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  before before: List(Effect(ConnectionEffect(Request))),
  then then: AfterLeave,
) -> client_connection.Handled(Session) {
  let before =
    list.append(
      before,
      connection_state.removes_its_unit_from_the_viewers(entered:),
    )
  connection_state.ask(
    session: Session(..session, status: LeavingMap(holder:, entered:, then:)),
    now:,
    request: AskMapRun(
      map: entered.map,
      incarnation: entered.incarnation,
      message: map.Leave(connection: client_connection.connection(session.link)),
    ),
    before:,
  )
}

/// The map's answer to the camp's leave ask: `Left`, a map that is not running
/// and a run that ended before its answer all put the client back in character
/// select with 0x0594, the map's watch dropped and a new character select; no
/// answer in time ends the connection with 0x036A reason 8, with no second
/// save; the server stopping ends it without one.
pub fn leave_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  then then: AfterLeave,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromMap(map.Left)) | step.NotRunning | step.EndedBeforeAnswer ->
      case then {
        JoinAt(place:) ->
          joining_at_the_holocrypt(session:, now:, holder:, entered:, place:)
        ToCharacterSelect ->
          in_character_select(session:, holder:, written: [
            Unwatch(watch: connection_state.map_watch),
          ])
      }
    step.NoAnswerInTime ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the map", outcome:),
      )
    step.StoppedWaiting -> connection_state.stopped(session, now)
    step.Answer(FromMap(map.Joined(..)))
    | step.Answer(FromMap(map.NotJoined(..)))
    | step.Answer(FromMap(map.Noticed(..)))
    | step.Answer(FromMap(map.Watched(..)))
    | step.Answer(FromMap(map.Unwatched(..)))
    | step.Answer(FromMap(map.Retire))
    | step.Answer(FromMap(map.Approached(..)))
    | step.Answer(FromMap(map.Withdrew(..)))
    | step.Answer(FromStore(..))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromSessions(..)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the answer is none the leave of the map asked for",
      )
  }
}

/// The Holocrypt's second step, after the map's leave: the map of the place's
/// world is asked to take the player at `place` for a new stay, with the earlier
/// stay's movement (`world_entry.rejoining`), the old map's watch dropped, in
/// `EnteringWorld` from the Holocrypt.
fn joining_at_the_holocrypt(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  place place: Place,
) -> client_connection.Handled(Session) {
  let stay = stay.next(session.last_stay)
  let #(entry, effects) =
    world_entry.rejoining(
      entered:,
      place:,
      connection: client_connection.connection(session.link),
      stay:,
    )
  connection_select.entering_world(
    session: Session(..session, last_stay: stay),
    now:,
    holder:,
    entry:,
    from: FromHolocrypt,
    effects:,
    written: [Unwatch(watch: connection_state.map_watch)],
  )
}

/// A line the movement's answer to the save gives, as a log line of the
/// connection.
fn movement_line(
  session: Session,
  effect: movement.Effect,
) -> Effect(ConnectionEffect(Request)) {
  case effect {
    movement.Fault(text:) ->
      connection_state.log(session:, level: step.LogError, text:)
    movement.Note(text:) ->
      connection_state.log(session:, level: LogInfo, text:)
  }
}

/// The answer to world entry's ask, which is the store's or the map's: the
/// failures every ask shares tell the client the server failed; any other
/// answer is world entry's to take. A refusal hands the client back to
/// character select.
pub fn entry_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entry entry: world_entry.State,
  from from: EntryFrom,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(store.Unavailable)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: "the store is unavailable",
      )
    step.Answer(FromStore(store.ForWorld(answer))) -> {
      let stay = stay.next(session.last_stay)
      case
        world_entry.loaded(
          entry,
          answer:,
          connection: client_connection.connection(session.link),
          stay:,
        )
      {
        Ok(world_entry.Join(state:, effects:)) ->
          connection_select.entering_world(
            session: Session(..session, last_stay: stay),
            now:,
            holder:,
            entry: state,
            from:,
            effects:,
            written: [],
          )
        Ok(world_entry.Refused(character_id:, warning:)) ->
          connection_select.select_step(
            session:,
            now:,
            holder:,
            step: refused_play(holder:, character_id:, warning:),
          )
        Error(Nil) -> entry_unasked(session, now)
      }
    }
    step.Answer(FromMap(answer)) ->
      case
        world_entry.joined(
          entry,
          answer:,
          realm_id: session.settings.realm_id,
          next_whisper: session.next_whisper,
          classes: session.settings.class_resources,
          numbers: session.settings.numbers,
          formulas: rating.formulas(tables: session.settings.tables),
        )
      {
        Ok(world_entry.InTheWorld(entered:, effects:)) ->
          in_the_world(session:, now:, holder:, entered:, effects:)
        Ok(world_entry.NotInTheWorld(character_id:, warning:)) ->
          case from {
            FromCharacterSelect ->
              connection_select.select_step(
                session:,
                now:,
                holder:,
                step: refused_play(holder:, character_id:, warning:),
              )
            FromHolocrypt ->
              in_character_select(session:, holder:, written: [
                connection_state.log(session:, level: LogWarning, text: warning),
              ])
          }
        Error(Nil) -> entry_unasked(session, now)
      }
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForSelect(..)))
    | step.Answer(FromStore(store.ForMove(..)))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromSessions(..)) -> entry_unasked(session, now)
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(
          who: case world_entry.awaiting(entry) {
            world_entry.AwaitingStore -> "the store"
            world_entry.AwaitingMap -> "the map"
          },
          outcome:,
        ),
      )
    step.StoppedWaiting -> connection_state.stopped(session, now)
  }
}

/// The player is in no map any more (the camp's leave, or a refused join at the
/// Holocrypt): after the effects `written`, 0x0594 puts the client in character
/// select, and a new character select waits for its 0x07E0.
fn in_character_select(
  session session: Session,
  holder holder: Holder,
  written written: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  Continue(
    Session(
      ..session,
      status: InCharacterSelect(holder:, select: character_select.new()),
    ),
    list.append(written, [
      connection_state.to_client(session, connection_frames.leave_world_frame()),
    ]),
  )
}

/// An answer that is none world entry asked for: a bug, so the client is told
/// the server failed.
fn entry_unasked(
  session: Session,
  now: Now,
) -> client_connection.Handled(Session) {
  connection_state.told(
    session:,
    now:,
    reason: LostUserServer,
    level: step.LogError,
    text: "the answer is none world entry asked for",
  )
}

/// The play world entry refused: a warning, then character select sends 0x0162
/// and asks for the list again.
fn refused_play(
  holder holder: Holder,
  character_id character_id: Int,
  warning warning: String,
) -> #(character_select.State, List(character_select.Effect)) {
  let #(select, effects) =
    character_select.play_refused(account_id: holder.account_id, character_id:)
  #(select, [character_select.Warn(text: warning), ..effects])
}

/// The player is in the world: the messages that put it there are written,
/// its map is watched and its place is saved every `movement.save_period_ms`.
fn in_the_world(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  effects effects: List(world_entry.Effect),
) -> client_connection.Handled(Session) {
  let #(updated, burst) =
    chat.entered_world(
      chat: entered.chat,
      world_zone_id: start_place.world_zone_id(movement.place(entered.movement)),
      top_zones: top_zone.top_zones(session.settings.tables),
    )
  connection_effects.carry_out(
    session: Session(
      ..session,
      status: InWorld(
        holder:,
        entered: world_entry.Entered(..entered, chat: updated),
      ),
    ),
    now:,
    effects: list.flatten([
      list.map(effects, connection_effects.from_entry),
      [Chats(effects: burst), StartsSaveTimer],
    ]),
    written: [],
  )
}
