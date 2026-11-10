//// What the game connection's features decide, carried out by its rule
//// (genesis_prime/game/connection): character select's, the camp's and world
//// entry's effects as the rule's own decisions, the leave of a stay in the
//// world and the save timer.

import genesis_prime/client_connection.{type Request, AskMap, AskStore, Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/camp
import genesis_prime/game/cast
import genesis_prime/game/character_select
import genesis_prime/game/chat
import genesis_prime/game/connection/casting as connection_casting
import genesis_prime/game/connection/chat as connection_chat
import genesis_prime/game/connection/life_effect as connection_life_effect
import genesis_prime/game/connection/resource as connection_resource
import genesis_prime/game/connection/state.{
  type Session, Camped, Playing, Session,
} as connection_state
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/strike
import genesis_prime/game/world_entry
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, CancelTimer, LogWarning,
  OwnEffect, StartTimer, Watch,
}
import genesis_prime/store
import genesis_prime/table/id.{type Spell4BaseId}
import genesis_prime/world_map/map_id.{type MapId}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// What a feature of the rule decided that the rule carries out, in order.
pub type Decided {
  /// Send the client a message, in the game wrapper under the cipher the
  /// connection holds.
  ToClient(frame: Frame)
  /// Log a warning.
  Warning(text: String)
  /// Make the connection's next ask, which ends the step.
  Asks(request: Request)
  /// Watch the run of the map that holds the player (`map_watch`).
  WatchesMap(map: MapId, incarnation: Int)
  /// Start the timer that saves the player's place (`save_timer`).
  StartsSaveTimer
  /// Start the timer that fires at the next quest reset (`quest_reset_timer`), in
  /// this many milliseconds.
  StartsQuestResetTimer(after_ms: Int)
  /// Start the timer that fires when the earliest running quest's time runs out
  /// (`quest_deadline_timer`), in this many milliseconds.
  StartsQuestDeadlineTimer(after_ms: Int)
  /// Cancel the quest deadline timer; nothing when none is running.
  CancelsQuestDeadlineTimer
  /// Save the player's place and the quest log, which ends the step; the player goes
  /// on playing once the store answers.
  SavesPlace
  /// What the life of the player the connection holds decided
  /// (genesis_prime/game/player_life), carried out as a fight's are
  /// (genesis_prime/game/connection/life_effect).
  Lives(effects: List(player_life.Effect))
  /// Start the player's innate passive, the plans' spell of this Spell4Base.
  StartsPassive(base: Spell4BaseId)
  /// What the chat decided: writes, tells, watches and group joins.
  Chats(effects: List(chat.Effect))
  /// The player leaves the world for character select: the save timer is
  /// cancelled and the place saved, the map's run is asked to take the player
  /// out, and 0x0594 is written (the camp's finish).
  LeavesWorld
}

pub fn from_select(effect: character_select.Effect) -> Decided {
  case effect {
    character_select.Send(frame:) -> ToClient(frame:)
    character_select.Warn(text:) -> Warning(text:)
    character_select.Ask(request:) ->
      Asks(request: AskStore(store.Select(request)))
  }
}

pub fn from_camp(effect: camp.Effect) -> Decided {
  case effect {
    camp.Write(frame:) -> ToClient(frame:)
    camp.LeaveWorld -> LeavesWorld
  }
}

pub fn from_entry(effect: world_entry.Effect) -> Decided {
  case effect {
    world_entry.Send(frame:) -> ToClient(frame:)
    world_entry.AskStore(request:) ->
      Asks(request: AskStore(store.World(request)))
    world_entry.AskMap(map:, message:) -> Asks(request: AskMap(map:, message:))
    world_entry.WatchMap(map:, incarnation:) -> WatchesMap(map:, incarnation:)
    world_entry.Life(effects:) -> Lives(effects:)
    world_entry.StartPassive(base:) -> StartsPassive(base:)
    world_entry.Warn(text:) -> Warning(text:)
  }
}

/// Turns what a feature decided into writes, log lines and a watch, and into
/// its ask, which ends the step with what was decided before it; `written`
/// are the effects so far, the last first.
pub fn carry_out(
  session session: Session,
  now now: Now,
  effects effects: List(Decided),
  written written: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  case effects {
    [] -> Continue(session, list.reverse(written))
    [ToClient(frame:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        connection_state.to_client(session, frame),
        ..written
      ])
    [Warning(text:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        connection_state.log(session:, level: LogWarning, text:),
        ..written
      ])
    [WatchesMap(map:, incarnation:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        Watch(
          watch: connection_state.map_watch,
          target: step.Map(map:, incarnation:),
        ),
        ..written
      ])
    [Lives(effects: decided), ..rest] -> {
      let assert Some(entered) = connection_state.entered_of(session.status)
        as "a life decided while the connection holds a player"
      let converted =
        connection_life_effect.life_effects(
          session:,
          now:,
          entered:,
          effects: decided,
        )
      carry_out(
        session:,
        now:,
        effects: rest,
        written: list.append(list.reverse(converted), written),
      )
    }
    [StartsPassive(base:), ..rest] -> {
      let assert Some(entered) = connection_state.entered_of(session.status)
        as "a passive starts while the connection holds a player"
      let #(started, decided) =
        cast.passive_started(
          cast: entered.cast,
          caster: connection_casting.caster_of(
            tables: session.settings.tables,
            entered:,
          ),
          plans: connection_state.plans_of(session:),
          base:,
          now:,
        )
      let #(session, converted) =
        connection_casting.cast_effects(
          session: connection_casting.with_cast(session:, cast: started),
          now:,
          effects: decided,
        )
      carry_out(
        session:,
        now:,
        effects: rest,
        written: list.append(list.reverse(converted), written),
      )
    }
    [Chats(effects: chat_decided), ..rest] -> {
      let #(session, converted) =
        connection_chat.chat_effects(session:, effects: chat_decided)
      carry_out(
        session:,
        now:,
        effects: rest,
        written: list.append(list.reverse(converted), written),
      )
    }
    [StartsSaveTimer, ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        start_save_timer(),
        ..written
      ])
    [StartsQuestResetTimer(after_ms:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        OwnEffect(StartTimer(
          timer: connection_state.quest_reset_timer,
          after_ms:,
        )),
        ..written
      ])
    [StartsQuestDeadlineTimer(after_ms:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        OwnEffect(StartTimer(
          timer: connection_state.quest_deadline_timer,
          after_ms:,
        )),
        ..written
      ])
    [CancelsQuestDeadlineTimer, ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        OwnEffect(CancelTimer(timer: connection_state.quest_deadline_timer)),
        ..written
      ])
    [SavesPlace, ..] ->
      case connection_state.holds_a_player(session.status) {
        Some(#(holder, entered)) ->
          connection_state.saving(
            session:,
            now:,
            holder:,
            entered:,
            then: Playing,
            before: list.reverse(written),
            within_ms: session.settings.ask_deadline_ms,
          )
        None ->
          connection_state.end_for(
            session:,
            now:,
            text: "a feature saved the place with no player in it",
          )
      }
    [LeavesWorld, ..] ->
      case connection_state.holds_a_player(session.status) {
        Some(#(holder, entered)) -> {
          let #(session, left_behind) = world_left(session:, now:, entered:)
          connection_state.saving(
            session:,
            now:,
            holder:,
            entered:,
            then: Camped,
            before: list.append(list.reverse(written), left_behind),
            within_ms: session.settings.ask_deadline_ms,
          )
        }
        None ->
          connection_state.end_for(
            session:,
            now:,
            text: "a feature left the world with no player in it",
          )
      }
    [Asks(request:), ..] ->
      connection_state.ask(
        session:,
        now:,
        request:,
        before: list.reverse(written),
      )
  }
}

/// What the player leaves behind as it leaves its stay in the world, by its camp
/// or the Holocrypt: its chat groups, its casts and its strikes are left, its
/// class resource's and its life's regeneration timers and the save, quest reset and
/// quest deadline timers cancelled; the session keeps the chat's next whisper number,
/// which counts for the connection's life.
pub fn world_left(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  #(
    Session(..session, next_whisper: chat.next_whisper(chat: entered.chat)),
    list.flatten([
      connection_chat.chat_effects(session:, effects: chat.left(entered.chat)).1,
      connection_casting.cast_effects(
        session:,
        now:,
        effects: cast.left(cast: entered.cast).1,
      ).1,
      connection_casting.carry_strike(
        session:,
        now:,
        effects: strike.left(strike: entered.strike).1,
      ).1,
      connection_resource.left(session:, entered:),
      list.map(player_life.left(life: entered.life), fn(timer) {
        OwnEffect(CancelTimer(timer:))
      }),
      [
        OwnEffect(CancelTimer(timer: connection_state.save_timer)),
        OwnEffect(CancelTimer(timer: connection_state.quest_reset_timer)),
        OwnEffect(CancelTimer(timer: connection_state.quest_deadline_timer)),
      ],
    ]),
  )
}

/// What the quest deadline timer needs when the earliest deadline of the quest log
/// (genesis_prime/game/quest_log `next_deadline`, on the monotonic clock) goes from
/// `before`, the deadline the running timer is set for, or none when no timer runs, to
/// `after`: nothing when it did not move, the timer started when none ran, the running
/// one cancelled and then started for the new deadline, or only cancelled when none is
/// left. A timer that has just fired or been cancelled is not running.
pub fn quest_deadline_timer_moved(
  before before: Option(Int),
  after after: Option(Int),
  now_ms now_ms: Int,
) -> List(Decided) {
  case before, after {
    None, None -> []
    None, Some(deadline_ms) -> [
      StartsQuestDeadlineTimer(after_ms: int.max(0, deadline_ms - now_ms)),
    ]
    Some(_), None -> [CancelsQuestDeadlineTimer]
    Some(was), Some(deadline_ms) if was == deadline_ms -> []
    Some(_), Some(deadline_ms) -> [
      CancelsQuestDeadlineTimer,
      StartsQuestDeadlineTimer(after_ms: int.max(0, deadline_ms - now_ms)),
    ]
  }
}

/// Starts the timer that saves the player's place every `movement.save_period_ms`.
pub fn start_save_timer() -> Effect(ConnectionEffect(Request)) {
  OwnEffect(StartTimer(
    timer: connection_state.save_timer,
    after_ms: movement.save_period_ms,
  ))
}
