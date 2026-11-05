//// The player's casts and strikes on the game connection
//// (genesis_prime/game/connection): the cast messages, the cast and strike
//// timers, the creatures' answers to a strike, and both rules' effects carried
//// out.
////
//// - **Casts** are a feature of their own (genesis_prime/game/cast): the player's
////   `Entered` keeps its cast state, the routing table sends 0x9a, 0x4DB and 0x801 to it
////   from inside 0x038C with the player in the world, and the timers `cast.owns`
////   names are its (`other_timer_fired`). The rule turns its
////   effects into writes to the caster, tells of news to the viewers
////   (`CastStarted`, `CastWent`, `CastFinished`, in the run of the player's map),
////   timers and log lines. A viewer writes a 0x7ff only for a caster it shows, and
////   a go or finish only for a start it wrote (`casts_written`, by cast id, kept
////   with the caster's unit id, so a removed unit's casts are finished before its
////   0x355 is written).
//// - **Strikes** are a feature of their own (genesis_prime/game/strike): a go the cast
////   rule asks for (`cast.Strike`) selects its targets from the units the client
////   shows, draws the caster's rolls from the connection's seed, and tells each
////   creature a `TellStrike` through the creature registry with no watch. The creature
////   answers by a send, taken as `SentByTarget`; the round closes when each answer is in
////   or the one strike timer, `strike.strike_timer`, fires for its deadline, and the
////   closed round is the cast rule's `went`. A viewer writes a creature's health and
////   death (`Health`, `Died`) for a creature it shows, whatever its own casts.

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/area.{Pose}
import genesis_prime/game/cast
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/resource as connection_resource
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/damage
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/prerequisite
import genesis_prime/game/rating
import genesis_prime/game/shown
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/start_place
import genesis_prime/game/strike
import genesis_prime/game/strike_tell.{type Answered}
import genesis_prime/game/world_entry
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type TimerId, CancelTimer,
  OwnEffect, StartTimer,
}
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// What the cast messages do, taken from inside 0x038C, in the world
/// (genesis_prime/game/cast): the press is refused or accepted and its writes,
/// tells and timers are carried out, the cancel ends a cast, and a refusal ends
/// the connection. A dead player's press is checked as the client checks it
/// (`caster_of`).
pub fn cast_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: cast.Message,
) -> client_connection.Handled(Session) {
  case
    cast.take(
      cast: entered.cast,
      message:,
      body: inner.body,
      caster: caster_of(entered:),
      plans: spell_plan.plans(session.settings.tables),
      now:,
    )
  {
    Ok(#(updated, effects)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: cast.describe(refusal))
  }
}

/// A creature's answer to a strike this player told in this stay (`stay_sent`):
/// the strike rule files it in the round it belongs to, and a round that closes is
/// the cast rule's `went`; an answer for a round that is closed is dropped
/// (genesis_prime/game/strike).
pub fn target_taken(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  answered answered: Answered,
) -> client_connection.Handled(Session) {
  let #(updated, effects) =
    strike.answered(strike: entered.strike, answer: answered, now:)
  let #(session, written) =
    carry_strike(
      session: with_strike(session:, strike: updated),
      now:,
      effects:,
    )
  Continue(session, written)
}

/// The strike timer fired: the rounds whose deadline has passed close with the
/// units that answered (genesis_prime/game/strike `timer_fired`).
pub fn strike_due(
  session session: Session,
  now now: Now,
) -> client_connection.Handled(Session) {
  case connection_state.held_in_the_world(session.status) {
    None -> Continue(session, [])
    Some(#(_, entered)) -> {
      let #(updated, effects) = strike.timer_fired(strike: entered.strike, now:)
      let #(session, written) =
        carry_strike(
          session: with_strike(session:, strike: updated),
          now:,
          effects:,
        )
      Continue(session, written)
    }
  }
}

/// A timer of the player's cast rule fired: its go, child cast or held press.
/// With no player in the world to take it, it is dropped.
pub fn cast_due(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case connection_state.held_in_the_world(session.status) {
    None -> Continue(session, [])
    Some(#(_, entered)) -> {
      let #(updated, effects) =
        cast.timer_fired(
          cast: entered.cast,
          timer:,
          caster: caster_of(entered:),
          now:,
        )
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    }
  }
}

/// The Vital id of Health and of Shield Capacity
/// (`Prerequisite.prerequisiteTypeId.71`: Vital.tbl ids 1 and 3).
const health_vital = 1

const shield_vital = 3

/// The player as its cast rule takes it: who it is, where it stands, what it
/// holds, who sees it, whether it is dead or in combat and its health and shield.
fn caster_of(entered entered: world_entry.Entered) -> cast.Caster {
  let life = entered.life
  cast.Caster(
    unit_id: entered.unit_id,
    place: movement.place(entered.movement),
    abilities: entered.loadout.abilities,
    weapon: Some(entered.loadout.weapon),
    audience: connection_state.viewer_connections(entered:),
    dead: player_life.state(life:) == player_life.Dead,
    resources: entered.resources,
    in_combat: player_life.in_combat(life:),
    life_vitals: dict.from_list([
      #(
        health_vital,
        prerequisite.Vital(
          current: int.to_float(player_life.health(life:)),
          maximum: int.to_float(player_life.max_health(life:)),
        ),
      ),
      #(
        shield_vital,
        prerequisite.Vital(
          current: int.to_float(player_life.shield(life:)),
          maximum: int.to_float(player_life.max_shield(life:)),
        ),
      ),
    ]),
  )
}

/// The session with the player's cast state replaced.
pub fn with_cast(session session: Session, cast cast: cast.State) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, cast:)
  })
}

/// What the cast rule decided, carried out in order.
fn carry_cast(
  session session: Session,
  now now: Now,
  effects effects: List(cast.Effect),
) -> client_connection.Handled(Session) {
  let #(session, written) = cast_effects(session:, now:, effects:)
  Continue(session, written)
}

/// The connection's effects for what the cast rule decided, with the session as
/// they leave it: a write, a tell of news to a viewer in the run of the player's
/// map, a timer or a log line, a press's costs paid from the class resource and a
/// go's gains given to it (genesis_prime/game/connection/resource), and a go asked,
/// which selects and strikes its targets
/// (`strike_begins`). A tell with no player in the world is dropped.
pub fn cast_effects(
  session session: Session,
  now now: Now,
  effects effects: List(cast.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  list.fold(effects, #(session, []), fn(so_far, effect) {
    let #(session, done) = so_far
    let #(session, more) = case
      effect,
      connection_state.entered_of(session.status)
    {
      cast.Send(frame:), _ -> #(session, [
        connection_state.to_client(session, frame),
      ])
      cast.Tell(to:, news:), Some(entered) -> #(
        session,
        connection_state.news_to_connection(entered:, connection: to, news:),
      )
      cast.Tell(..), None -> #(session, [])
      cast.StartTimer(timer:, after_ms:), _ -> #(session, [
        OwnEffect(StartTimer(timer:, after_ms:)),
      ])
      cast.CancelTimer(timer:), _ -> #(session, [
        OwnEffect(CancelTimer(timer:)),
      ])
      cast.Log(level:, text:), _ -> #(session, [
        connection_state.log(session:, level:, text:),
      ])
      cast.Strike(asked:), Some(entered) ->
        strike_begins(session:, now:, entered:, asked:)
      cast.Strike(..), None -> #(session, [])
      cast.Pay(payments:), _ -> connection_resource.paid(session:, payments:)
      cast.Gain(gains:), _ -> connection_resource.gained(session:, gains:)
    }
    #(session, list.append(done, more))
  })
}

/// A go asked: its targets are selected from the units the client shows, the
/// caster's rolls are drawn from the connection's seed, and the strike rule begins
/// its round (genesis_prime/game/strike).
fn strike_begins(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  asked asked: cast.GoAsked,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let tables = session.settings.tables
  let attacker = attacker_of(session:, entered:)
  let selection =
    strike.select(
      asked:,
      attacker:,
      picture: entered.shown,
      areas: spell_area.areas(tables:),
      now_ms: now.monotonic_ms,
    )
  let #(link, entropy) =
    client_connection.draw(session.link, strike.entropy_needed(selection:))
  let #(updated, effects) =
    strike.begin(
      strike: entered.strike,
      selection:,
      attacker:,
      formulas: rating.formulas(tables:),
      entropy:,
      now:,
    )
  carry_strike(
    session: with_strike(session: Session(..session, link:), strike: updated),
    now:,
    effects:,
  )
}

/// The player as its strikes take it: who it is, where it stands and faces, which
/// player faction it is of and what its damage reads of it (its level and the
/// ratings its gear gives).
fn attacker_of(
  session session: Session,
  entered entered: world_entry.Entered,
) -> strike.Attacker {
  let place = movement.place(entered.movement)
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  strike.Attacker(
    unit_id: entered.unit_id,
    connection: client_connection.connection(session.link),
    pose: Pose(at: area.point_of(place), yaw: start_place.facing(place).yaw),
    place:,
    move_seq: session.move_seq,
    stay: entered.stay,
    faction:,
    stats: damage.Attacker(
      level: connection_state.level_of(entered:),
      assault_rating: entered.loadout.properties.assault_rating,
      support_rating: entered.loadout.properties.support_rating,
    ),
  )
}

/// The session with the player's strike state replaced.
pub fn with_strike(
  session session: Session,
  strike strike: strike.State,
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, strike:)
  })
}

/// What the strike rule decided, carried out in order, with the session as they leave
/// it: a strike told to a creature through the creature registry, a timer, a closed
/// round's go (the cast rule's `went`), the news held for the round's units, or a log
/// line.
pub fn carry_strike(
  session session: Session,
  now now: Now,
  effects effects: List(strike.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  list.fold(effects, #(session, []), fn(so_far, effect) {
    let #(session, done) = so_far
    let #(session, more) = case
      effect,
      connection_state.entered_of(session.status)
    {
      _, None -> #(session, [])
      strike.TellStrike(unit_id:, life:, tell:), Some(entered) -> #(session, [
        OwnEffect(step.Tell(
          to: step.Creature(
            map: entered.map,
            incarnation: entered.incarnation,
            unit_id:,
            life:,
          ),
          request: client_connection.TellStrike(tell:),
        )),
      ])
      strike.StartTimer(timer:, after_ms:), Some(_) -> #(session, [
        OwnEffect(StartTimer(timer:, after_ms:)),
      ])
      strike.CancelTimer(timer:), Some(_) -> #(session, [
        OwnEffect(CancelTimer(timer:)),
      ])
      strike.Went(asked:, struck:), Some(entered) -> {
        let needed =
          cast.rolls_needed(
            cast: entered.cast,
            cast_id: asked.cast_id,
            phase: asked.phase,
            struck:,
          )
        let #(link, bytes) =
          client_connection.draw(session.link, needed * prerequisite.roll_bytes)
        let #(updated, cast_effects_out) =
          cast.went(
            cast: entered.cast,
            caster: caster_of(entered:),
            now:,
            cast_id: asked.cast_id,
            phase: asked.phase,
            struck:,
            rolls: prerequisite.rolls_of(bytes:),
          )
        cast_effects(
          session: with_cast(session: Session(..session, link:), cast: updated),
          now:,
          effects: cast_effects_out,
        )
      }
      strike.Released(unit_id:, news:), Some(entered) -> #(
        session,
        creature_news_frames(session:, entered:, unit_id:, news:),
      )
      strike.Log(level:, text:), Some(_) -> #(session, [
        connection_state.log(session:, level:, text:),
      ])
    }
    #(session, list.append(done, more))
  })
}

/// The frame of a creature's news, when its client still shows the creature: 0x937
/// for its health, 0x88c for its death.
pub fn creature_news_frames(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> List(Effect(ConnectionEffect(Request))) {
  use <- bool.guard(when: !dict.has_key(entered.shown, unit_id), return: [])
  case news {
    client_connection.Health(health:, dead:) -> {
      let assert Ok(body) =
        unit_health.encode(UnitHealth(
          unit_id:,
          health:,
          dead: connection_frames.bit(dead),
        ))
        as "a unit id of 32 bits, a health of 32 and a bit fit the message"
      [
        connection_state.to_client(
          session,
          Frame(message_id: unit_health.message_id, body:),
        ),
      ]
    }
    client_connection.Died -> [
      connection_state.to_client(
        session,
        connection_frames.death_state_frame(unit_id:, dead: True),
      ),
    ]
    client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged
    | client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | client_connection.Removed
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastFinished(..)
    | client_connection.CreatureMoved(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..) -> []
  }
}
