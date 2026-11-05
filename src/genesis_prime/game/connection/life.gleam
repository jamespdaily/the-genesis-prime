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
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/movement as connection_movement
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
  type ConnectionEffect, type Effect, type Now, LogWarning, OwnEffect,
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
            loadout: entered.loadout,
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
  life_carried(session:, now:, holder:, effects:, before: entered.life)
}

/// What player_life decided, as the connection's effects: its own unit's messages
/// to its client, its news to its viewers, the answer told to the creature, and the
/// start of a fighter's stream at the player's place now. The casts' end and the
/// Holocrypt are `life_carried`'s.
pub fn life_effects(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  effects effects: List(player_life.Effect),
) -> List(Effect(ConnectionEffect(Request))) {
  list.flat_map(effects, fn(effect) {
    case effect {
      player_life.ToClient(written:) -> [
        connection_state.to_client(
          session,
          connection_frames.own_unit_frame(entered:, now:, written:),
        ),
      ]
      player_life.ToViewers(news:) ->
        list.map(connection_state.sorted_viewers(entered:), fn(viewer) {
          connection_state.news_to(entered:, viewer:, news:)
        })
      player_life.Answer(to:, answered:) -> [
        OwnEffect(step.Tell(
          to:,
          request: client_connection.TellStrikeAnswered(answered:),
        )),
      ]
      player_life.StreamTo(unit_id:, life:) -> [
        connection_movement.tells_a_fighter_the_place(
          connection: client_connection.connection(session.link),
          entered:,
          fighter: #(unit_id, life),
          place: movement.place(entered.movement),
          seq: session.move_seq,
        ),
      ]
      player_life.EndCasts | player_life.GoToHolocrypt -> []
    }
  })
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
        before: entered.life,
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

/// What player_life decided, carried out in order, then what the step did to the
/// class resource from the life `before` it (`resource.life_changed`): the frames
/// and news as `life_effects` makes them, `EndCasts` as the cast rule's `died`, whose 0x7fe
/// go out in its place in the order, and `GoToHolocrypt` as the leave of the map
/// that the Holocrypt's join follows (`leaving_for_the_holocrypt`), which comes
/// last.
fn life_carried(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  effects effects: List(player_life.Effect),
  before before: player_life.Life,
) -> client_connection.Handled(Session) {
  let #(session, written, to_the_holocrypt) =
    list.fold(effects, #(session, [], False), fn(so_far, effect) {
      let #(session, written, to_the_holocrypt) = so_far
      case connection_state.entered_of(session.status) {
        None -> so_far
        Some(entered) ->
          case effect {
            player_life.EndCasts -> {
              let #(updated, ended) = cast.died(cast: entered.cast, now:)
              let #(session, more) =
                connection_casting.cast_effects(
                  session: connection_casting.with_cast(session:, cast: updated),
                  now:,
                  effects: ended,
                )
              #(session, list.append(written, more), to_the_holocrypt)
            }
            player_life.GoToHolocrypt -> #(session, written, True)
            player_life.ToClient(..)
            | player_life.ToViewers(..)
            | player_life.Answer(..)
            | player_life.StreamTo(..) -> #(
              session,
              list.append(
                written,
                life_effects(session:, now:, entered:, effects: [effect]),
              ),
              to_the_holocrypt,
            )
          }
      }
    })
  let #(session, resource_written) =
    connection_resource.life_changed(session:, before:)
  let written = list.append(written, resource_written)
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
