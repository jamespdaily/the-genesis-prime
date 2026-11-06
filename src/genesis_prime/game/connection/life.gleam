//// The player's life on the game connection (genesis_prime/game/connection): a
//// creature's fight on the player, its death, its coming back and the leave
//// for the Holocrypt.
////
//// - **A creature's fight** on the player is a feature of its own
////   (genesis_prime/game/player_life), whose module holds the sequence: the
////   connection tells its map `Ready` at the stay's first 0xF2, numbers each accepted
////   0x637 with its move sequence number (for the connection's life, through a camp),
////   takes `SentByFoe` (a creature's threat, release or strike) and the map's `Gone`
////   of a fighter, streams each move to the creatures that fight the player
////   (`TellTargetMoved`) and answers a strike (`TellStrikeAnswered`). A viewer writes
////   a creature's 0x908, 0x90a, 0x89a and 0x638 path, and a player's 0x938 shield,
////   for a unit it shows; its picture keeps a running creature's path.
//// - **Regeneration** is player_life's too: its health and shield timers (ids 8 and
////   9) are the connection's own timers, started and cancelled by the rule's
////   effects, handed back to the rule as `regeneration_due`, and cancelled at the
////   leave of the stay (`effects.world_left`).
//// - **Death and coming back** are player_life's (its module holds the sequence
////   and the failure table): a strike that leaves the player at 0 kills it; the
////   connection writes the death's frames, ends the player's casts
////   (`cast.died`), and while the player is dead decodes and drops each 0x637, its
////   ghost's (`ghost.movement`), as it does after the Holocrypt's join until the
////   stay's first 0xF2 (`world_entry.GhostLoading`), checks its presses as the client checks a dead
////   caster (`caster_of`, `cast.dead_player`) and takes 0x15a from inside
////   0x038C. Wake Here writes the coming back where the body lies. The Holocrypt
////   writes the same, then leaves the map and joins again at the Holocrypt place
////   (`start_place.holocrypt`, else the place the stay entered at) with no store
////   ask; the save timer stops at the leave and starts again with the burst:
////
////   ```
////   0x15a {P, 2, 0} ─▶ the coming back's frames and news; the unit's 0x355 to each viewer
////                    ─▶ map run: Leave(connection)                       (LeavingMap, JoinAt(place))
////   Left, NotRunning or EndedBeforeAnswer
////                    ─▶ the map's watch dropped; map of place's world: Join(connection, character, place)
////                                                                        (EnteringWorld, FromHolocrypt)
////   Joined           ─▶ 0xAD, 0x262, .. 0x61, the watch, as a play's burst (the client's 0xAD
////                       removes every unit and loads again, 0x1403b6de0); the stay's movement
////                       is kept, placed there (`movement.placed`)
////   NotJoined        ─▶ 0x0594, character select
////   no answer        ─▶ 0x036A reason 8, as the camp's leave or a play's join
////   ```

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/connection/casting as connection_casting
import genesis_prime/game/connection/effects as connection_effects
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/resource as connection_resource
import genesis_prime/game/connection/state.{type Session, JoinAt, Session} as connection_state
import genesis_prime/game/connection/world as connection_world
import genesis_prime/game/hit
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/rating
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type TimerId, LogWarning,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/result

/// A creature's threat, release or strike on the player in the world; a strike
/// that kills carries out the death (`life_carried`).
pub fn foe_taken(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  fight fight: strike_tell.Fight,
) -> client_connection.Handled(Session) {
  let #(session, life, effects) = case fight {
    strike_tell.Threatened(unit_id:, life: creature_life) -> {
      let #(life, effects) =
        player_life.threatened(
          life: entered.life,
          unit_id:,
          creature_life:,
          gone: entered.gone,
        )
      #(session, life, effects)
    }
    strike_tell.Released(unit_id:) -> {
      let #(life, effects) = player_life.released(life: entered.life, unit_id:)
      #(session, life, effects)
    }
    strike_tell.Attacks(tell:) -> {
      let #(link, entropy) =
        client_connection.draw(session.link, hit.roll_bytes)
      let assert Ok(rolls) = hit.rolls_of(bytes: entropy)
        as "the seed gives 12 bytes for a strike's rolls"
      let tables = session.settings.tables
      let #(life, effects) =
        player_life.struck(
          life: entered.life,
          defence: player_life.defence(
            properties: entered.properties,
            level: connection_state.level_of(entered:),
            formulas: rating.formulas(tables:),
          ),
          strike: tell,
          rolls:,
          place: movement.place(entered.movement),
        )
      #(Session(..session, link:), life, effects)
    }
  }
  let session =
    connection_state.with_entered(session:, change: fn(entered) {
      world_entry.Entered(..entered, life:)
    })
  life_carried(session:, now:, holder:, effects:)
}

/// A regeneration timer of the player's life fired (genesis_prime/game/player_life):
/// the tick's news to the player and its viewers, and the next tick's timer. With no
/// player the client holds in the world (a save or a leave is on) it is dropped.
pub fn regeneration_due(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case connection_state.held_in_the_world(session.status) {
    Some(#(_, entered)) -> {
      let #(life, effects) = player_life.timer_fired(life: entered.life, timer:)
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, life:)
        })
      Continue(
        session,
        life_effect.life_effects(session:, now:, entered:, effects:),
      )
    }
    None -> Continue(session, [])
  }
}

/// The player's 0x15a, taken from inside 0x038C in the world
/// (genesis_prime/game/player_life): the life is kept and its effects carried
/// out (`life_carried`); a body the client's reader refuses ends the connection,
/// and any other refusal is a warning that changes nothing.
pub fn life_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: player_life.Message,
) -> client_connection.Handled(Session) {
  case
    player_life.take(
      life: entered.life,
      message:,
      body: inner.body,
      unit_id: entered.unit_id,
    )
  {
    Ok(#(life, effects)) ->
      life_carried(
        session: connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, life:)
        }),
        now:,
        holder:,
        effects:,
      )
    Error(refusal) ->
      case refusal {
        player_life.NotDecoded(..) ->
          connection_state.end_for(
            session:,
            now:,
            text: player_life.describe(refusal:),
          )
        player_life.NotThePlayer(..)
        | player_life.NotOffered(..)
        | player_life.NotDead
        | player_life.NonzeroValue(..) ->
          Continue(session, [
            connection_state.log(
              session:,
              level: LogWarning,
              text: player_life.describe(refusal:),
            ),
          ])
      }
  }
}

/// What player_life decided, carried out in order, then what its death, coming
/// back and combat flag did to the class resource (`resource.life_effects`): the
/// frames and news as `life_effects` makes them, `DamageTaken` as the cast rule's
/// `damage_taken`, `CombatLeft` as its `combat_left` and `EndCasts` as its `died`, whose
/// 0x7fe and the procs' casts go out in their place in the order, and `GoToHolocrypt` as the leave of the map
/// that the Holocrypt's join follows (`leaving_for_the_holocrypt`), which comes
/// last.
fn life_carried(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  effects effects: List(player_life.Effect),
) -> client_connection.Handled(Session) {
  let #(session, written, to_the_holocrypt) = carried(session:, now:, effects:)
  case to_the_holocrypt, connection_state.entered_of(session.status) {
    True, Some(entered) ->
      leaving_for_the_holocrypt(
        session:,
        now:,
        holder:,
        entered:,
        before: written,
      )
    True, None | False, _ -> Continue(session, written)
  }
}

/// What player_life decided, carried out in order, with what it did to the class resource
/// after it, as `life_carried` carries it, but for the Holocrypt: whether the effects asked
/// to go there is the last of the three results. The map's `Gone` of a fighter carries the
/// life's effects this way too, so the combat it ends reaches the cast rule
/// (`CombatLeft`), as the last release by a creature's own tell does.
pub fn carried(
  session session: Session,
  now now: Now,
  effects effects: List(player_life.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request))), Bool) {
  let #(session, written, to_the_holocrypt) =
    list.fold(effects, #(session, [], False), fn(so_far, effect) {
      let #(session, written, to_the_holocrypt) = so_far
      case connection_state.entered_of(session.status) {
        None -> so_far
        Some(entered) ->
          case effect {
            player_life.EndCasts -> {
              let #(session, more) =
                cast_carried(
                  session:,
                  now:,
                  taken: cast.died(
                    cast: entered.cast,
                    caster: connection_casting.caster_of(entered:),
                    now:,
                  ),
                )
              #(session, list.append(written, more), to_the_holocrypt)
            }
            player_life.CombatLeft -> {
              let #(session, more) =
                cast_carried(
                  session:,
                  now:,
                  taken: cast.combat_left(
                    cast: entered.cast,
                    caster: connection_casting.caster_of(entered:),
                    now:,
                  ),
                )
              #(session, list.append(written, more), to_the_holocrypt)
            }
            player_life.DamageTaken -> {
              let #(session, more) =
                cast_carried(
                  session:,
                  now:,
                  taken: cast.damage_taken(
                    cast: entered.cast,
                    caster: connection_casting.caster_of(entered:),
                    now:,
                  ),
                )
              #(session, list.append(written, more), to_the_holocrypt)
            }
            player_life.GoToHolocrypt -> #(session, written, True)
            player_life.ToClient(..)
            | player_life.ToViewers(..)
            | player_life.Answer(..)
            | player_life.StreamTo(..)
            | player_life.StartTimer(..)
            | player_life.CancelTimer(..) -> #(
              session,
              list.append(
                written,
                life_effect.life_effects(session:, now:, entered:, effects: [
                  effect,
                ]),
              ),
              to_the_holocrypt,
            )
          }
      }
    })
  let #(session, resource_written) =
    connection_resource.life_effects(session:, effects:)
  #(session, list.append(written, resource_written), to_the_holocrypt)
}

/// A step of the cast rule that the player's life asked for: the rule's new state kept
/// in the session, and its effects carried out.
fn cast_carried(
  session session: Session,
  now now: Now,
  taken taken: #(cast.State, List(cast.Effect)),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(updated, effects) = taken
  connection_casting.cast_effects(
    session: connection_casting.with_cast(session:, cast: updated),
    now:,
    effects:,
  )
}

/// The Holocrypt's first step: the place is the start of the player's race and
/// faction in its world (`start_place.holocrypt`), or, when its world holds none,
/// the place the player entered this stay at (the server's choice,
/// `death.server_choices`); after the effects `before`, the player's unit is
/// removed from its viewers, its chat groups, casts and strikes left, its save
/// timer cancelled and its map asked to take it out, as the camp's leave does with
/// no save, with the Holocrypt's join to follow in place of character select
/// (`LeavingMap` with `JoinAt`). The place is saved by the next stay's timer.
fn leaving_for_the_holocrypt(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  before before: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  let place =
    start_place.holocrypt(
      tables: session.settings.tables,
      faction_id: entered.character.faction_id,
      race_id: entered.character.race_id,
      world_id: start_place.world_id(movement.place(entered.movement)),
    )
    |> result.unwrap(entered.entered_at)
  let #(session, left_behind) =
    connection_effects.world_left(session:, now:, entered:)
  connection_world.leaving_the_map(
    session:,
    now:,
    holder:,
    entered:,
    before: list.append(before, left_behind),
    then: JoinAt(place:),
  )
}
