//// Character select on the game connection (genesis_prime/game/connection):
//// character select's messages and the store's answers to its asks, and the
//// play request that starts world entry.
////
//// - **The character list and creating a character** are character select's
////   own feature (genesis_prime/game/character_select): it makes its own store
////   asks and takes the store's answers, and the rule turns its effects into
////   writes in the game wrapper, log lines and the ask. The rule decodes what
////   the client sent into typed values first: 0x025C carries the whole frame
////   of 0x025B (opcode.0x25c), and 0x07DD is the client's play request. The
////   failures every ask shares (no answer, or the store unavailable) are the
////   rule's, so a request added to character select adds no status here.

import genesis_prime/client_connection.{
  type Answer, type Request, FromHandOff, FromMap, FromSessions, FromStore,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/character_select
import genesis_prime/game/connection/effects as connection_effects
import genesis_prime/game/connection/state.{
  type EntryFrom, type Session, Busy, EnteringWorld, FromCharacterSelect,
  Greeting, InCharacterSelect, Present, Selecting, Session,
} as connection_state
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome, LogWarning,
}
import genesis_prime/store
import gleam/list

/// What a message of character select's does (genesis_prime/game/character_select):
/// its effects are carried out, and a body the client's reader would refuse
/// ends the connection.
pub fn select_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
  message message: character_select.Message,
) -> client_connection.Handled(Session) {
  case connection_state.standing(session.status) {
    Selecting(holder:) ->
      case
        character_select.take(
          message:,
          account_id: holder.account_id,
          body: inner.body,
          tables: session.settings.tables,
          character_slots: session.settings.game.character_slots,
          starting_credits: session.settings.numbers.starting_credits,
        )
      {
        Ok(step) -> select_step(session:, now:, holder:, step:)
        Error(refusal) ->
          connection_state.end_for(
            session:,
            now:,
            text: character_select.describe(refusal),
          )
      }
    Greeting | Present(..) | Busy(..) ->
      connection_state.misrouted(session:, now:, inner:)
  }
}

/// Character select's new state and what it decided, carried out.
pub fn select_step(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  step step: #(character_select.State, List(character_select.Effect)),
) -> client_connection.Handled(Session) {
  connection_effects.carry_out(
    session: Session(
      ..session,
      status: InCharacterSelect(holder:, select: step.0),
    ),
    now:,
    effects: list.map(step.1, connection_effects.from_select),
    written: [],
  )
}

/// The client's 0x07DD: world entry asks the store for the character, and the
/// connection waits in `EnteringWorld`.
pub fn play_requested(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case connection_state.standing(session.status) {
    Selecting(holder:) ->
      case world_entry.take(account_id: holder.account_id, body: inner.body) {
        Ok(#(entry, effects)) ->
          entering_world(
            session:,
            now:,
            holder:,
            entry:,
            from: FromCharacterSelect,
            effects:,
            written: [],
          )
        Error(refusal) ->
          connection_state.end_for(
            session:,
            now:,
            text: world_entry.describe(refusal),
          )
      }
    Greeting | Present(..) | Busy(..) ->
      connection_state.misrouted(session:, now:, inner:)
  }
}

/// The store's answer to character select's ask: the failures every store ask
/// shares tell the client the server failed; any other answer is character
/// select's to take. A takeover that waits behind a failing ask is never taken
/// (the connection ends with this failure's text).
pub fn select_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  select select: character_select.State,
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
    step.Answer(FromStore(store.ForSelect(answer))) ->
      select_taken(session:, now:, holder:, taken: case answer {
        store.Listed(characters:) ->
          character_select.listed(
            select,
            characters:,
            filetime: now.filetime,
            realm_id: session.settings.realm_id,
            max_characters: session.settings.max_characters,
            character_slots: session.settings.game.character_slots,
            tables: session.settings.tables,
          )
        store.Created(answer:) -> character_select.created(select, answer)
        store.Deleted(answer:) -> character_select.deleted(select, answer)
        store.Renamed(answer:) -> character_select.renamed(select, answer)
      })
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForWorld(..)))
    | step.Answer(FromStore(store.ForMove(..)))
    | step.Answer(FromStore(store.ForItems(..))) ->
      select_taken(session:, now:, holder:, taken: Error(Nil))
    step.Answer(FromHandOff(..)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the hand-off's answer is none a store ask gets",
      )
    step.Answer(FromSessions(..)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "Sessions' answer is none a store ask gets",
      )
    step.Answer(FromMap(..)) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "a map's answer is none a store ask gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the store", outcome:),
      )
    step.StoppedWaiting -> connection_state.stopped(session, now)
  }
}

/// What character select made of the store's answer: its new state and
/// effects carried out, or, for an answer it has no ask for, the client told
/// the server failed.
fn select_taken(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  taken taken: Result(
    #(character_select.State, List(character_select.Effect)),
    Nil,
  ),
) -> client_connection.Handled(Session) {
  case taken {
    Ok(step) -> select_step(session:, now:, holder:, step:)
    Error(Nil) ->
      connection_state.told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the store's answer is none character select asked for",
      )
  }
}

/// World entry's effects carried out after the effects `written`, with the
/// connection waiting in `EnteringWorld` for the answer to its ask.
pub fn entering_world(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entry entry: world_entry.State,
  from from: EntryFrom,
  effects effects: List(world_entry.Effect),
  written written: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  connection_effects.carry_out(
    session: Session(..session, status: EnteringWorld(holder:, entry:, from:)),
    now:,
    effects: list.map(effects, connection_effects.from_entry),
    written:,
  )
}
