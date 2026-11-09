//// Other players and creatures on the game connection
//// (genesis_prime/game/connection): what the map sends about who sees the
//// player, and what a viewer writes of news of the units its client shows.
////
//// - **Other players' units.** The map decides who sees whom
////   (genesis_prime/world_map/map) and tells the connection of each player in
////   it, as the message `SentByMap`, who sees its player (`SeenBy(by, stay)` when
////   a player comes to see it, `UnseenBy(by)` when one stops), and `Gone(unit)`
////   when a player's connection has ended. The connection keeps
////   the connections that see its player as its viewers, each with its player's
////   stay, in the player's `Entered`, and sends everything about its own unit to
////   them itself, as
////   `SentByPeer` through the registry (the same path the map's sends take,
////   `genesis_prime/server`'s `connection_reach`); the map sends no unit:
////
////   ```
////   owner's connection (player in the world)                       viewer's connection             client
////   SeenBy(v, stay) from the map ─▶ Tell(v, Appeared(0x262 at its place)) ─▶ writes 0x262 if not shown ─▶ the unit is created
////   0x637 accepted             ─▶ Tell(map, Moved(place)); Tell(each viewer, Moving(0x638)) ─▶ writes 0x638 if shown ─▶ the unit moves
////   UnseenBy(v)                ─▶ Tell(v, Removed)                    ─▶ writes 0x355 if shown   ─▶ the unit is removed
////   its camp (0xC0)            ─▶ Tell(each viewer, Removed), then Leave
////   its connection ends        ─▶ nothing: the map sends each viewer UnseenBy, and every player Gone(unit)
////                                                                     Gone(unit) ─▶ writes 0x355 if shown, and the unit is gone
////   ```
////
////   The shell takes a send between steps, after an ask's outcome and the step it
////   starts, and entering the world writes its whole burst in the one step that
////   takes the map's `Joined`, so no send reaches the connection between the
////   answer and the end of the burst: no status holds sends during entry, and a
////   0x262 of another unit never lands while the client waits on 0x636 (0x1403d9760).
////   A send that arrives while any ask is out, a save among them, waits for its
////   outcome. With no player in the world (after the camp's leave, say) a send is
////   dropped and nothing is written for other units; a player that enters again
////   starts with no viewers and no units shown, and the map's new join sends it a
////   `SeenBy` for each player in sight, whose owners then send it their 0x262s.
//// - **What a viewer writes** is what its client can take, kept by the player's
////   `Entered` for the current run of the map: `shown`, the units it has written
////   a 0x262 of and not a 0x355, and `gone`, the units the map reported `Gone`. A
////   0x262 is written for a unit not shown and not gone, and it is then shown (the
////   client keeps one unit per id until its 0x355, and a unit id 0 would be the
////   controlled unit, 0x1403d9760); a 0x638 and a 0x355 are written for a shown
////   unit only, a 0x355 ends it; `Gone` writes a 0x355 for a shown unit and marks
////   the unit gone, so a 0x262 from the owner that ended, which lands after it,
////   shows no ghost.
//// - **Stays.** Every message another process sends for the player's stay in the
////   world (the map's notices, a peer's or a creature's news, a creature's threat,
////   release and strike) comes in one envelope, `ForStay(stay, ..)`, which names
////   the stay it was sent for (genesis_prime/world_map/stay), and is taken at one
////   entry point (`stay_sent`) only when that stay is the player's: one of an
////   earlier stay, sent before a camp or the Holocrypt, reaches a client that holds
////   none of its units, or a run of the map that gives the same unit ids again,
////   and is dropped. The connection names a new stay in each join's ask, and each
////   viewer's stay, as the map's `SeenBy` gave it, in every news it sends it.
//// - **Static objects** are the map's own units (genesis_prime/world_map/static_object):
////   the map tells the connection the objects its player comes to see,
////   `ObjectsSeen` with each one's 0x262, and the ones it stops seeing,
////   `ObjectsUnseen` with their ids. The viewer writes a 0x262 for each object
////   not shown and not gone, shown then as `ShownObject`, and a 0x355 for each
////   shown one, by the rules below. One sender, the map, speaks of these units.
//// - **A creature's unit** reaches a viewer the same way, as news from the
////   creature's own process (`CreatureAppeared`, then `Removed`), and is shown,
////   removed and marked gone by the same rules: the viewer neither knows nor asks
////   whose process owns a unit (genesis_prime/world_map/creature).
//// - **Order.** For one viewer, an owner's 0x262, 0x638s and 0x355 are that
////   owner's messages only, which the BEAM delivers in the order sent (it orders
////   the signals of one sender to one receiver); the map's `SeenBy` and
////   `UnseenBy` to one owner are the map's only, so the owner's viewers change in
////   order. The one case two senders speak of a unit, `Gone` after the owner has
////   ended, is the viewer's `gone`.
//// - **A player's stealth** is the cast rule's (genesis_prime/game/cast): the owner's
////   connection writes 0x8f5 to its own client and tells each viewer `Stealth`, which
////   the viewer writes as 0x8f5 and then 0x247 of type 24 for a unit it shows. The
////   owner's own client logs its own change from the 0x8f5, so it is sent no type 24
////   (`opcode.0x8f5`, `opcode.0x247.type24`). A viewer that first sees a stealthed
////   player gets its 0x262 with create flag 16 (`opcode.0x262.unit_fields`), and a
////   `Stealth` news follows that 0x262 from the same sender, in order:
////
////   ```
////   owner's connection (cast rule)                 viewer's connection              viewer's client
////   a go, a blow or the death moves the stealth
////     StealthChanged(s) ─▶ 0x8f5 {owner, s}  ─────────────────────────────────────▶ the owner's client
////                       ─▶ Tell(each viewer, Stealth(s)) ─▶ shown? 0x8f5 {owner, s}, 0x247 type 24 {owner, exiting = !s}
////                       ─▶ Tell(the owner's map, TellStealthChanged(owner, s))  (genesis_prime/game/connection/casting)
////   SeenBy(v) while stealthed ─▶ Tell(v, Appeared(0x262, flag 16)) ─▶ writes 0x262 if not shown
////   ```
////
////   - A viewer whose connection is gone, or that no longer sees the owner, is not told
////     (`news_to`), and a tell to a connection that has ended is dropped.
////   - The owner dying or leaving: a death ends the stealth first (`StealthChanged`
////     after the casts' 0x7fe, before 0x247 type 22); a camp or the Holocrypt sends the
////     viewers `Removed` and nothing about stealth, and the next stay starts unstealthed.
////   - A `Stealth` news for a unit the viewer does not show, or no longer shows, is
////     dropped and writes nothing.
//// - **A player's look** is the cast rule's too (genesis_prime/game/look): the owner's
////   connection writes 0x933 to its own client and tells each viewer `LookChanged`, which
////   the viewer writes as 0x933 for a unit it shows and drops otherwise. A viewer that
////   first sees the owner mid-disguise gets its 0x262 with the disguised slots' visuals
////   already in its list (`frames.appearance_at`), so it needs no 0x933; one that comes
////   after the end gets the base visuals:
////
////   ```
////   owner's connection                                viewer's connection              viewer's client
////   a disguise starts or ends
////     0x933 {owner, visuals} ─────────────────────────────────────────────────────────▶ the owner's client
////     Tell(each viewer, LookChanged(visuals)) ─▶ shown? 0x933 {owner, visuals} ────────▶ the unit changes
////   SeenBy(v) mid-disguise ─▶ Tell(v, Appeared(0x262 with the overlay)) ─▶ writes 0x262 if not shown
////   ```
////
////   - A `LookChanged` for a unit the viewer does not show, or no longer shows, is dropped
////     and writes nothing; a viewer that shows the owner again gets a new `Appeared`
////     with the overlay.
////   - The owner dying ends its disguise in the death's step (the 0x933 restore); a camp
////     or the Holocrypt sends the viewers `Removed` and no 0x933.
//// - **A unit's 0x638 and 0x262** are stamped with the map's clock: the connection
////   holds the origin `Joined` carried and takes the time of the input from it
////   (`world_map/map.server_time`, mod 2^32), in the order it takes its inputs, so
////   for a viewer the times of one unit only go forward. More than 31 commands are sent as several 0x638s
////   in order, each of at most 31 (its count is 5 bits, opcode.0x638). A move with
////   no viewer sends none, and one with nothing to relay sends none and tells the
////   map nothing. A viewer that has just been `Unwatched`, or gone, may still be
////   sent one: a send to a process that has ended is dropped, and one for a unit
////   the viewer does not show is dropped by it.

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/cast
import genesis_prime/game/class_resource
import genesis_prime/game/connection/casting as connection_casting
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/life as connection_life
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/shown.{ShownCreature, ShownObject, ShownPlayer}
import genesis_prime/game/strike
import genesis_prime/game/world_entry
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_stat.{type UnitStat}
import genesis_prime/message/unit_target.{UnitTarget}
import genesis_prime/message/unit_threat.{UnitThreat}
import genesis_prime/step.{
  type ConnectionEffect, type ConnectionId, type Effect, type Now,
}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map
import genesis_prime/world_map/static_object
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set

/// What the map sent for the player's stay (`stay_sent`): who sees its player
/// (`SeenBy`, `UnseenBy`), a unit whose owner ended (`Gone`), and the static
/// objects its player sees (`ObjectsSeen`) and stops seeing (`ObjectsUnseen`),
/// written as `viewer_takes` writes a unit's 0x262 and 0x355. A connection
/// sends everything about its own unit itself: told `SeenBy(by, stay)` it keeps
/// `by` with its stay and sends it its 0x262 at its current place, with its health
/// now, told `UnseenBy(by)` its 0x355. The shell takes a send between steps, after
/// the ask's outcome and the step it starts are done
/// (genesis_prime/connection/shell), and world entry writes its whole burst in the
/// one step that takes the map's `Joined`, so a send of the map, which comes after
/// its answer, is always taken after the burst: no status holds sends during
/// entry.
pub fn map_sent(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  notice notice: map.Notice,
) -> client_connection.Handled(Session) {
  case notice {
    map.SeenBy(by:, stay:) ->
      Continue(viewers_changed(session:, change: dict.insert(_, by, stay)), [
        connection_state.news_to(
          entered:,
          viewer: #(by, stay),
          news: client_connection.Appeared(unit: appearance(entered:, now:)),
        ),
      ])
    map.UnseenBy(by:) ->
      Continue(
        viewers_changed(session:, change: dict.delete(_, by)),
        connection_state.news_to_connection(
          entered:,
          connection: by,
          news: client_connection.Removed,
        ),
      )
    map.Gone(unit_id:) -> {
      let #(life, by_life) = player_life.released(life: entered.life, unit_id:)
      let session =
        marked_gone(
          session: connection_state.with_entered(session:, change: fn(entered) {
            world_entry.Entered(..entered, life:)
          }),
          unit_id:,
        )
      let shown = dict.has_key(entered.shown, unit_id)
      let #(session, ended) = case shown {
        True -> cast_loses_unit(session:, now:, unit_id:)
        False -> #(session, [])
      }
      let #(session, released, _) =
        connection_life.carried(session:, now:, effects: by_life)
      use <- bool.guard(when: !shown, return: Continue(session, released))
      Continue(
        session,
        list.flatten([
          finishes_of_forgotten_casts(session:, entered:, unit_id:),
          [
            connection_state.to_client(
              session,
              connection_frames.unit_removed_frame(unit_id:),
            ),
          ],
          ended,
          released,
        ]),
      )
    }
    map.ObjectsSeen(units:) -> {
      let #(refused, named) =
        list.partition(units, fn(unit) {
          names_own_unit(
            entered:,
            unit_id: static_object.unit_id(created: unit),
          )
        })
      let fresh =
        list.filter(named, fn(unit) {
          !dict.has_key(entered.shown, static_object.unit_id(created: unit))
          && !set.contains(entered.gone, static_object.unit_id(created: unit))
        })
      Continue(
        shown_changed(session:, change: fn(picture) {
          list.fold(fresh, picture, fn(picture, unit) {
            dict.insert(
              picture,
              static_object.unit_id(created: unit),
              ShownObject,
            )
          })
        }),
        list.append(
          list.map(refused, fn(unit) {
            refusal_logged(
              session:,
              unit_id: static_object.unit_id(created: unit),
            )
          }),
          list.map(fresh, fn(unit) {
            connection_state.to_client(
              session,
              connection_frames.object_created_frame(unit:),
            )
          }),
        ),
      )
    }
    map.ObjectsUnseen(unit_ids:) -> {
      let #(refused, named) =
        list.partition(unit_ids, fn(unit_id) {
          names_own_unit(entered:, unit_id:)
        })
      let shown_ids = list.filter(named, dict.has_key(entered.shown, _))
      let #(forgotten, ended) =
        list.fold(shown_ids, #(session, []), fn(so_far, unit_id) {
          let #(session, ended) = so_far
          let #(session, more) =
            cast_loses_unit(
              session: unit_forgotten(session:, unit_id:),
              now:,
              unit_id:,
            )
          #(session, list.append(ended, more))
        })
      Continue(
        forgotten,
        list.flatten([
          list.map(refused, fn(unit_id) { refusal_logged(session:, unit_id:) }),
          list.map(shown_ids, fn(unit_id) {
            connection_state.to_client(
              session,
              connection_frames.unit_removed_frame(unit_id:),
            )
          }),
          ended,
        ]),
      )
    }
  }
}

/// What a viewer writes of news of a unit, from the units this connection has
/// shown and the ones the map reported gone: a 0x262 for a unit not shown and not
/// gone, which is then shown (the client keeps one unit per id until its 0x355,
/// and a unit that is gone would be a ghost); a 0x638 for a shown unit; a 0x355
/// for a shown unit, which is then no longer shown. Anything else is dropped. A
/// 0x262 or 0x355 that names unit 0 or this player's own unit is refused with an
/// error line, and writes nothing: the client makes the controlled unit of a
/// 0x262 with either id (0x1403d9760) and removes a unit with a 0x355
/// (0x1403d9590).
pub fn viewer_takes(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  news news: client_connection.PeerNews,
) -> client_connection.Handled(Session) {
  let unit_id = news.unit_id
  let shown = dict.has_key(entered.shown, unit_id)
  let creates_or_removes = case news.news {
    client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Removed -> True
    client_connection.Moving(..)
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastTargetsRemoved(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.CastFinished(..)
    | client_connection.Health(..)
    | client_connection.Died
    | client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged
    | client_connection.CreatureMoved(..)
    | client_connection.CreaturePlaced(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..)
    | client_connection.CrowdControlApplied(..)
    | client_connection.CrowdControlEnded(..)
    | client_connection.InterruptArmor(..)
    | client_connection.Absorption(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..)
    | client_connection.LookChanged(..) -> False
  }
  use <- bool.guard(
    when: creates_or_removes && names_own_unit(entered:, unit_id:),
    return: Continue(session, [refusal_logged(session:, unit_id:)]),
  )
  case news.news {
    client_connection.Appeared(unit:) -> {
      use <- bool.guard(
        when: shown || set.contains(entered.gone, unit_id),
        return: Continue(session, []),
      )
      Continue(
        shown_changed(session:, change: dict.insert(_, unit_id, ShownPlayer)),
        [
          connection_state.to_client(
            session,
            world_entry.unit_created_frame(unit:),
          ),
        ],
      )
    }
    client_connection.CreatureAppeared(
      unit:,
      life:,
      place:,
      hit_radius:,
      attackable:,
    ) -> {
      use <- bool.guard(
        when: shown || set.contains(entered.gone, unit_id),
        return: Continue(session, []),
      )
      Continue(
        shown_changed(session:, change: dict.insert(
          _,
          unit_id,
          ShownCreature(
            path: creature_path.Standing(at: place),
            life:,
            alive: creature_unit.health_of(unit:) > 0,
            hit_radius:,
            attackable:,
          ),
        )),
        [
          connection_state.to_client(
            session,
            connection_frames.creature_created_frame(unit:),
          ),
        ],
      )
    }
    client_connection.Moving(server_time_ms:, commands:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.unit_moved_frame(
            unit_id:,
            server_time_ms:,
            commands:,
          ),
        ),
      ])
    }
    client_connection.Removed -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let #(forgotten, ended) =
        cast_loses_unit(
          session: unit_forgotten(session:, unit_id:),
          now:,
          unit_id:,
        )
      Continue(
        forgotten,
        list.flatten([
          finishes_of_forgotten_casts(session:, entered:, unit_id:),
          [
            connection_state.to_client(
              session,
              connection_frames.unit_removed_frame(unit_id:),
            ),
          ],
          ended,
        ]),
      )
    }
    client_connection.CastStarted(start:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            casts_written: dict.insert(
              entered.casts_written,
              start.cast_id,
              unit_id,
            ),
          )
        }),
        [connection_state.to_client(session, cast.started_frame(start:))],
      )
    }
    client_connection.CastWent(go:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: go.cast_id,
        frame: cast.went_frame(go:),
        forgetting: False,
      )
    client_connection.CastMissed(missed:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: missed.cast_id,
        frame: cast.missed_frame(missed:),
        forgetting: False,
      )
    client_connection.CastTargetsRemoved(removed:, destroyed:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: removed.cast_id,
        frame: cast.targets_removed_frame(removed:),
        forgetting: destroyed,
      )
    client_connection.CastStackRemoved(removed:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: removed.cast_id,
        frame: cast.stack_removed_frame(removed:),
        forgetting: False,
      )
    client_connection.CastFinished(cast_id:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id:,
        frame: cast.finished_frame(cast_id:),
        forgetting: True,
      )
    client_connection.Health(health:, dead:) ->
      creature_news(
        session:,
        entered:,
        unit_id:,
        news: client_connection.Health(health:, dead:),
      )
    client_connection.Died ->
      creature_news(session:, entered:, unit_id:, news: client_connection.Died)
    client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged ->
      life_news(session:, entered:, unit_id:, news: news.news)
    client_connection.CreatureMoved(path:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session =
        shown_changed(session:, change: fn(picture) {
          shown.with_path(picture:, unit_id:, path:)
        })
      Continue(
        session,
        case connection_frames.path_frame(entered:, unit_id:, path:) {
          Some(frame) -> [connection_state.to_client(session, frame)]
          None -> []
        },
      )
    }
    client_connection.CreaturePlaced(place:, at_ms:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session =
        shown_changed(session:, change: fn(picture) {
          shown.with_path(
            picture:,
            unit_id:,
            path: creature_path.Standing(at: place),
          )
        })
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.placed_frame(entered:, unit_id:, place:, at_ms:),
        ),
      ])
    }
    client_connection.Targeting(target_unit_id:, threat:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let assert Ok(body) =
        unit_target.encode(UnitTarget(unit_id:, target_unit_id:, threat:))
        as "unit ids and a threat of 32 bits fit the message"
      Continue(session, [
        connection_state.to_client(
          session,
          Frame(message_id: unit_target.message_id, body:),
        ),
      ])
    }
    client_connection.Threat(other_unit_id:, threat:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let assert Ok(body) =
        unit_threat.encode(UnitThreat(unit_id:, other_unit_id:, threat:))
        as "unit ids and a threat of 32 bits fit the message"
      Continue(session, [
        connection_state.to_client(
          session,
          Frame(message_id: unit_threat.message_id, body:),
        ),
      ])
    }
    client_connection.CombatState(in_combat:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.combat_state_frame(unit_id:, in_combat:),
        ),
      ])
    }
    client_connection.Shield(shield:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.shield_frame(unit_id:, shield:),
        ),
      ])
    }
    client_connection.InterruptArmor(armor:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.interrupt_armor_frame(unit_id:, armor:),
        ),
      ])
    }
    client_connection.Absorption(absorption:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.absorption_frame(unit_id:, absorption:),
        ),
      ])
    }
    client_connection.PropertiesChanged(properties:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.properties_changed_frame(unit_id:, properties:),
        ),
      ])
    }
    client_connection.Stealth(stealthed:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.unit_stealth_frame(unit_id:, stealthed:),
        ),
        connection_state.to_client(
          session,
          connection_frames.stealth_logged_frame(unit_id:, exiting: !stealthed),
        ),
      ])
    }
    client_connection.LookChanged(item_visuals:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.item_visuals_frame(unit_id:, item_visuals:),
        ),
      ])
    }
    client_connection.CrowdControlApplied(state:, instance_id:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.control_applied_frame(
            unit_id:,
            state:,
            instance_id:,
          ),
        ),
      ])
    }
    client_connection.CrowdControlEnded(state:, cast_id:, instance_id:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.control_ended_frame(
            unit_id:,
            state:,
            cast_id:,
            instance_id:,
          ),
        ),
      ])
    }
  }
}

/// Whether a 0x262 or 0x355 would name unit 0 or this player's own unit: the
/// client makes the controlled unit of a 0x262 with either id and removes a unit
/// with a 0x355 (0x1403d9760, 0x1403d9590). `viewer_takes`, `ObjectsSeen` and
/// `ObjectsUnseen` refuse such a unit and write nothing for it.
fn names_own_unit(
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
) -> Bool {
  unit_id == 0 || unit_id == entered.unit_id
}

/// The error line for a unit a 0x262 or 0x355 was refused for (`names_own_unit`).
fn refusal_logged(
  session session: Session,
  unit_id unit_id: Int,
) -> Effect(ConnectionEffect(Request)) {
  connection_state.log(
    session:,
    level: step.LogError,
    text: "a unit's owner sent a 0x262 or 0x355 naming unit "
      <> int.to_string(unit_id)
      <> ", which is this player's own unit or none, so it is refused",
  )
}

/// A creature's health or death news, for a creature this client shows: its picture
/// marks the creature dead at once, which a selection reads, and the frame is
/// written, or held until the go of the caster's own round that names the unit is
/// written, so the client shows the number before the death it caused
/// (genesis_prime/game/strike). Another watcher's connection is not held: it is told
/// the news and the cast by two senders, which no order holds.
fn creature_news(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !dict.has_key(entered.shown, unit_id),
    return: Continue(session, []),
  )
  let session = case news {
    client_connection.Died | client_connection.Health(dead: True, ..) ->
      shown_changed(session:, change: fn(picture) {
        shown.with_alive(picture:, unit_id:, alive: False)
      })
    client_connection.Health(dead: False, ..)
    | client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged
    | client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | client_connection.Removed
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastTargetsRemoved(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.CastFinished(..)
    | client_connection.CreatureMoved(..)
    | client_connection.CreaturePlaced(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..)
    | client_connection.CrowdControlApplied(..)
    | client_connection.CrowdControlEnded(..)
    | client_connection.InterruptArmor(..)
    | client_connection.Absorption(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..)
    | client_connection.LookChanged(..) -> session
  }
  case strike.holds(strike: entered.strike, unit_id:) {
    True ->
      Continue(
        connection_casting.with_strike(
          session:,
          strike: strike.hold(strike: entered.strike, unit_id:, news:),
        ),
        [],
      )
    False ->
      Continue(
        session,
        connection_casting.creature_news_frames(
          session:,
          entered:,
          unit_id:,
          news:,
        ),
      )
  }
}

/// A player's news of its own death that its viewer writes for a unit its client
/// shows: 0x88c with the dead bit clear for `CameBack`, which marks the unit alive
/// in the picture, and 0x247 of type 22 or 23 for `DeathLogged` and
/// `CameBackLogged`. Dropped for a unit not shown.
fn life_news(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !dict.has_key(entered.shown, unit_id),
    return: Continue(session, []),
  )
  case news {
    client_connection.CameBack ->
      Continue(
        shown_changed(session:, change: fn(picture) {
          shown.with_alive(picture:, unit_id:, alive: True)
        }),
        [
          connection_state.to_client(
            session,
            connection_frames.death_state_frame(unit_id:, dead: False),
          ),
        ],
      )
    client_connection.DeathLogged ->
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.combat_log_frame(unit_id:, died: True),
        ),
      ])
    client_connection.CameBackLogged ->
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.combat_log_frame(unit_id:, died: False),
        ),
      ])
    client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | client_connection.Removed
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastTargetsRemoved(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.CastFinished(..)
    | client_connection.Health(..)
    | client_connection.Died
    | client_connection.CreatureMoved(..)
    | client_connection.CreaturePlaced(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..)
    | client_connection.CrowdControlApplied(..)
    | client_connection.CrowdControlEnded(..)
    | client_connection.InterruptArmor(..)
    | client_connection.Absorption(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..)
    | client_connection.LookChanged(..) -> Continue(session, [])
  }
}

/// A frame about a cast, written only for a cast whose start this viewer wrote, which
/// it then forgets when `forgetting`: the client drops a message that names a cast it
/// does not hold.
fn written_cast_frame(
  session session: Session,
  entered entered: world_entry.Entered,
  cast_id cast_id: Int,
  frame frame: Frame,
  forgetting forgetting: Bool,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !dict.has_key(entered.casts_written, cast_id),
    return: Continue(session, []),
  )
  let session = case forgetting {
    True ->
      connection_state.with_entered(session:, change: fn(entered) {
        world_entry.Entered(
          ..entered,
          casts_written: dict.delete(entered.casts_written, cast_id),
        )
      })
    False -> session
  }
  Continue(session, [connection_state.to_client(session, frame)])
}

/// 0x7fe for each cast of the unit that this client was sent the start of and no
/// finish, in cast id order, written before the unit's 0x355: the client keeps a
/// cast that never gets its 0x7fe live (`cast.no_answer`), and a cast id used
/// again restarts it (`opcode.0x7ff`).
fn finishes_of_forgotten_casts(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
) -> List(Effect(ConnectionEffect(Request))) {
  dict.to_list(entered.casts_written)
  |> list.filter(fn(written) { written.1 == unit_id })
  |> list.map(fn(written) { written.0 })
  |> list.sort(int.compare)
  |> list.map(fn(cast_id) {
    connection_state.to_client(session, cast.finished_frame(cast_id:))
  })
}

/// The unit of the player's own record as another player is created with it: at
/// the place the player stands at now, with its health now as stat 0, so a dead
/// player is created dead (`0x140457bc5`), its shield now as stat 20
/// (`opcode.0x938`) and its Interrupt Armor as stat 21 while it is above 0
/// (`opcode.0x938.interrupt_armor`: the create's stat list sets it) and its absorption as
/// stat 22 while it is above 0 (`opcode.0x938`, `0x14064fb40`: the create's stat list sets
/// it), without its class resource: the stat and the ResourceMax
/// property of the player's own 0x262 are left out, since a 0x935 goes to the
/// player alone (`opcode.0x262.resource_stats`), and stamped from the map's clock,
/// from the origin `Joined` carried (`map.server_time`).
fn appearance(
  entered entered: world_entry.Entered,
  now now: Now,
) -> UnitCreatePlayer {
  let unit =
    connection_frames.appearance_at(
      entered:,
      place: movement.place(entered.movement),
      now:,
    )
  let health = player_life.health(life: entered.life)
  let shield = player_life.shield(life: entered.life)
  let armor = player_life.interrupt_armor(life: entered.life)
  let absorption = player_life.absorption(life: entered.life)
  let slot = class_resource.slot(resources: entered.resources)
  let resource_stat = unit_fields.resource_stat_id(slot:)
  let resource_max = unit_fields.resource_max_property(slot:)
  UnitCreatePlayer(
    ..unit,
    tail: UnitCreateTail(
      ..unit.tail,
      stats: list.append(
        list.filter_map(unit.tail.stats, fn(stat) {
          case stat.stat_id {
            id if id == unit_fields.health_stat ->
              Ok(unit_fields.integer_stat(stat_id: id, value: health))
            id if id == unit_fields.shield_stat ->
              Ok(unit_fields.integer_stat(stat_id: id, value: shield))
            id if id == resource_stat -> Error(Nil)
            _ -> Ok(stat)
          }
        }),
        list.flatten([
          stat_above_zero(
            stat_id: unit_fields.interrupt_armor_stat,
            value: armor,
          ),
          stat_above_zero(
            stat_id: unit_fields.absorption_stat,
            value: absorption,
          ),
        ]),
      ),
      properties: list.filter(unit.tail.properties, fn(property) {
        property.property_id != resource_max
      }),
    ),
  )
}

/// The stat the create lists: `value` while it is above 0, and none at 0.
fn stat_above_zero(stat_id stat_id: Int, value value: Int) -> List(UnitStat) {
  case value > 0 {
    True -> [unit_fields.integer_stat(stat_id:, value:)]
    False -> []
  }
}

/// The session with the player's viewers changed by `change`.
fn viewers_changed(
  session session: Session,
  change change: fn(Dict(ConnectionId, Stay)) -> Dict(ConnectionId, Stay),
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, viewers: change(entered.viewers))
  })
}

/// The session with the units its client shows changed by `change`.
fn shown_changed(
  session session: Session,
  change change: fn(shown.Picture) -> shown.Picture,
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, shown: change(entered.shown))
  })
}

/// The session with the unit no longer shown, the casts of it forgotten (the client is
/// written their finish before the unit's 0x355, `finishes_of_forgotten_casts`) and the
/// news held for it dropped.
fn unit_forgotten(session session: Session, unit_id unit_id: Int) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(
      ..entered,
      shown: dict.delete(entered.shown, unit_id),
      casts_written: dict.filter(entered.casts_written, fn(_, caster) {
        caster != unit_id
      }),
      strike: strike.forget(strike: entered.strike, unit_id:),
    )
  })
}

/// The player's casts told that a unit its client no longer shows is gone, so
/// their nodes on it end (genesis_prime/game/cast `unit_removed`): the session with
/// the new cast state and what the cast rule asks written.
fn cast_loses_unit(
  session session: Session,
  now now: Now,
  unit_id unit_id: Int,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let #(updated, effects) =
        cast.unit_removed(
          cast: entered.cast,
          unit_id:,
          now_ms: now.monotonic_ms,
        )
      connection_casting.cast_effects(
        session: connection_casting.with_cast(session:, cast: updated),
        now:,
        effects:,
      )
    }
  }
}

/// The session with the unit marked gone, so it is shown no more, and no longer
/// shown.
fn marked_gone(session session: Session, unit_id unit_id: Int) -> Session {
  let session = unit_forgotten(session:, unit_id:)
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, gone: set.insert(entered.gone, unit_id))
  })
}
