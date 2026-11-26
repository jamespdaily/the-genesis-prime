//// Other players and creatures on the game connection
//// (genesis_prime/game/connection): what the map sends about who sees the
//// player, and what a viewer writes of news of the units its client shows.
////
//// - **Other players' units.** The map decides who sees whom
////   (genesis_prime/world_map/map) and tells the connection of each player in
////   it, as the message `SentByMap`, who sees its player (`SeenBy(by, stay, unit_id,
////   generation)` when a player comes to see it, `UnseenBy(by, generation)` when one
////   stops), and `Gone(unit)` when a player's connection has ended. The connection
////   keeps the connections that see its player as its viewers, each with its player's
////   stay and the generation of that sight, in the player's `Entered`, and sends
////   everything about its own unit to them itself, as `SentByPeer` through the
////   registry (the same path the map's sends take, `genesis_prime/server`'s
////   `connection_reach`), and its moves as `SentByMove`; the map sends no unit and
////   carries no move:
////
////   ```
////   owner's connection (player in the world)                       viewer's connection             client
////   SeenBy(v, stay, unit, g) from the map ─▶ Tell(v, Appeared(0x262 at its place, g)) ─▶ writes 0x262 if not shown ─▶ the unit is created
////   0x637 accepted             ─▶ Tell(map, Moved(place)); Tell(each viewer, Move(0x638 chunk, its g)) ─▶ writes 0x638 if the sight is g ─▶ the unit moves
////   UnseenBy(v, g)             ─▶ Tell(v, Departed(g))                ─▶ writes 0x355 if shown   ─▶ the unit is removed
////   its camp (0xC0)            ─▶ Tell(each viewer, Departed(its g)), then Leave
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
//// - **One removal.** A unit leaves the viewer's client at one function, `unit_removed`,
////   whether its owner's `Departed` or `Removed` news, the map's `Gone` or the map's `ObjectsUnseen`
////   ends it, so a unit's casts are finished before its 0x355 the same way for each
////   (`cast.target_node_end`).
//// - **Sight is symmetric.** A pair leaves sight in both directions in one step
////   (`map.goes_out_of_sight`), so the caster's connection takes the viewer out of its
////   casts' audiences on the map's `UnseenBy` and on the viewer's `Departed`, whichever
////   comes first, before any cast the removal ends is finished: the viewer's client
////   reads a cast's 0x7fe before the unit's 0x355 only for a unit it still shows
////   (`cast.target_node_end`).
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
//// - **Casts a viewer's client holds** (genesis_prime/game/client_casts): a player's 0x262
////   lists its own casts and the casts other players' casts hold on it, whether or not the
////   viewer shows their caster (`cast.unknown_caster`); a cast whose caster told the viewer
////   its start ends by the caster's frames, and any other by the unit that listed it:
////
////   ```
////   ally T's create lists cast X of caster C ─▶ viewer: C told it X? no: X is borrowed from T
////   T's go-time tell HeldCastStarted(0x7ff, 0x7f4) ─▶ T shown and X held in no state? write both,
////                                                     borrow X from T
////   T's last source of X ends ─▶ Tell(each viewer, HeldCastEnded(X)) ─▶ borrowed? 0x811 {X, [T]}
////   ```
////
////   - A borrowed cast gets none of its caster's later frames, so the caster's removal does not
////     end it before T's tell does; T's removal drops it with the client's nodes on T.
////   - T's start is written when the viewer shows T and holds the cast in no state (written by
////     its caster, borrowed, or held with no caster): the client restarts a cast id that is
////     live (`opcode.0x7ff`), so one sender wins and the other's start is dropped. A viewer
////     that does not show the caster makes the cast too (`cast.unknown_caster`).
//// - **A player's move at its viewer** is stamped with the generation of the sight the
////   mover's copy holds for that viewer, and taken by the rule of
////   genesis_prime/game/move_stamp: applied for the sight the viewer holds, dropped for an
////   older one or one that ended, held (at most 16 chunks of a unit, a guess) for a
////   newer one or a unit it holds nothing of until that sight's 0x262 comes, which
////   releases the held moves in order. A hold that overflows is warned of once; the
////   holds and the memory of ended sights end with the stay. The viewer's failure rows:
////
////   | Point | What happens |
////   |---|---|
////   | a move of a generation older than the one held, or at most the last that ended | dropped |
////   | a move newer than the one held, or for a unit not held | held until the notice of its generation |
////   | the 0x262 of a generation, with held moves | 0x262, then the held moves of it in order; older dropped; newer kept |
////   | the end of a sight of at least a held move's generation, or the owner's `Gone` | the hold is dropped with one warning that counts its chunks; the generation is remembered |
////   | a hold past 16 chunks | the oldest chunk is dropped with one warning that names the sight held and the one awaited |
////   | the notice never comes | the hold ends with the stay |
////   | the map ends a sight older than the one the player's copy holds for a viewer | an error line; the copy, the audiences and the viewer are left as they are |
////   | the owner's notice of a sight older than the one held or ended, or of a unit the map reported gone | nothing is written; a stale one is an error line, and a gone unit's held moves are dropped with one warning that counts them |
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
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/class_resource
import genesis_prime/game/client_casts
import genesis_prime/game/connection/casting as connection_casting
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/landing as connection_landing
import genesis_prime/game/connection/life as connection_life
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/faction_level
import genesis_prime/game/held_changes
import genesis_prime/game/hit_radius
import genesis_prime/game/move_stamp
import genesis_prime/game/movement
import genesis_prime/game/player_address
import genesis_prime/game/player_life
import genesis_prime/game/player_state.{type PlayerState, PlayerState}
import genesis_prime/game/shown.{ShownCreature, ShownObject, ShownPlayer}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_news
import genesis_prime/game/world_entry
import genesis_prime/message/float32
import genesis_prime/message/relayed_movement
import genesis_prime/message/spell_targets_removed
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_cast.{type UnitCreateCast}
import genesis_prime/message/unit_create_creature.{
  type UnitCreateCreature, UnitCreateCreature,
}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/message/unit_stat.{type UnitStat}
import genesis_prime/message/unit_target.{UnitTarget}
import genesis_prime/message/unit_threat.{UnitThreat}
import genesis_prime/step.{
  type ConnectionEffect, type ConnectionId, type Effect, type Now,
}
import genesis_prime/table/creature2_display_info
import genesis_prime/table/id.{Creature2DisplayInfoId, Creature2Id, RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{type SpawnId}
import genesis_prime/world_map/static_object
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set

/// What the map sent for the player's stay (`stay_sent`): who sees its player
/// (`SeenBy`, `UnseenBy`), a unit whose owner ended (`Gone`), and the static
/// objects its player sees (`ObjectsSeen`) and stops seeing (`ObjectsUnseen`),
/// written as `viewer_takes` writes a unit's 0x262 and 0x355. A connection
/// sends everything about its own unit itself: told `SeenBy(by, stay, unit_id)` it keeps
/// `by` with its stay and unit id, puts `by` in the audience of the casts its 0x262 lists (not when `by`
/// already sees the player: it drops the second 0x262, so it was listed none) and sends it
/// that 0x262 at its current place, with its health now and the cast it holds the bar of;
/// told `UnseenBy(by, generation)` for the sight it holds for `by`
/// it takes `by` out of those audiences and sends its 0x355. The shell takes a send between steps, after
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
    map.SeenBy(by:, stay:, unit_id:, generation:) ->
      Continue(
        connection_casting.with_cast(
          session: viewers_changed(session:, change: dict.insert(
            _,
            by,
            player_address.Viewer(stay:, unit_id:, generation:),
          )),
          cast: case dict.has_key(entered.viewers, by) {
            // A viewer that already sees the player drops the second create, so it
            // was listed no cast by it and is joined to none.
            True -> entered.cast
            False ->
              cast_state.audience_joined(
                cast: entered.cast,
                viewer: by,
                caster_unit_id: entered.unit_id,
              )
          },
        ),
        [
          connection_state.news_to(
            entered:,
            viewer: #(by, stay),
            news: unit_news.Appeared(
              unit: appearance(entered:, now:),
              generation:,
            ),
          ),
        ],
      )
    map.UnseenBy(by: step.ConnectionId(by_number) as by, generation:) ->
      case dict.get(entered.viewers, by) {
        Ok(player_address.Viewer(generation: held, ..)) ->
          case generation.compare(first: generation, second: held) {
            order.Lt ->
              Continue(session, [
                connection_state.log(
                  session:,
                  level: step.LogError,
                  text: "the map ended a sight of viewer "
                    <> int.to_string(by_number)
                    <> " that is older than the one held: "
                    <> int.to_string(generation.number(generation:))
                    <> " against "
                    <> int.to_string(generation.number(generation: held)),
                ),
              ])
            order.Eq | order.Gt ->
              viewer_unseen(session:, now:, entered:, by:, generation:)
          }
        Error(Nil) -> viewer_unseen(session:, now:, entered:, by:, generation:)
      }
    map.UnitUnseen(unit_id:, generation: _) -> {
      let #(session, removal) =
        unit_removed(session:, now:, entered:, unit_id:, keeping: [])
      Continue(session, list.append(removal.written, removal.ended))
    }
    map.Gone(unit_id:) -> {
      let #(life, by_life) = player_life.released(life: entered.life, unit_id:)
      let #(viewing, dropped) =
        move_stamp.gone(viewing: entered.viewing, unit_id:)
      let session =
        marked_gone(
          session: connection_state.with_entered(session:, change: fn(entered) {
            world_entry.Entered(..entered, life:, viewing:)
          }),
          unit_id:,
        )
      let #(session, removal) =
        unit_removed(session:, now:, entered:, unit_id:, keeping: [])
      let #(session, released, _) =
        connection_life.carried(session:, now:, effects: by_life)
      let #(session, held_ended) =
        connection_landing.caster_removed(session:, now:, unit_id:)
      Continue(
        session,
        list.flatten([
          moves_dropped_logged(session:, unit_id:, dropped:),
          removal.written,
          removal.ended,
          held_ended,
          released,
        ]),
      )
    }
    map.ObjectsSeen(units:) -> {
      let #(refused, named) =
        units
        |> list.map(fn(seen) { #(static_object.unit_id(created: seen.1), seen) })
        |> list.partition(fn(unit) { names_own_unit(entered:, unit_id: unit.0) })
      let fresh =
        list.filter(named, fn(unit) {
          !dict.has_key(entered.shown, unit.0)
          && !set.contains(entered.gone, unit.0)
        })
      Continue(
        shown_changed(session:, change: fn(picture) {
          list.fold(fresh, picture, fn(picture, unit) {
            let #(unit_id, #(spawn_id, created)) = unit
            dict.insert(
              picture,
              unit_id,
              object_shown(
                tables: session.settings.tables,
                spawn_id:,
                created:,
                world_place: movement.place(entered.movement),
              ),
            )
          })
        }),
        list.append(
          list.map(refused, fn(unit) {
            refusal_logged(session:, unit_id: unit.0)
          }),
          list.map(fresh, fn(unit) {
            connection_state.to_client(
              session,
              connection_frames.object_created_frame(unit: unit.1.1),
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
      let #(forgotten, removals) =
        list.fold(shown_ids, #(session, []), fn(so_far, unit_id) {
          let #(session, removals) = so_far
          let #(session, removal) =
            unit_removed(session:, now:, entered:, unit_id:, keeping: [])
          #(session, list.append(removals, [removal]))
        })
      Continue(
        forgotten,
        list.flatten([
          list.map(refused, fn(unit_id) { refusal_logged(session:, unit_id:) }),
          list.flat_map(removals, fn(removal) { removal.written }),
          list.flat_map(removals, fn(removal) { removal.ended }),
        ]),
      )
    }
  }
}

/// The place of the last of the position commands, as the player's client holds it: x, y and
/// z of the command in `world_place`'s world and zone, none when there is no command or a
/// float is not finite.
fn player_place(
  commands commands: List(UnitPositionCommand),
  world_place world_place: Place,
) -> Option(Place) {
  case list.last(commands) {
    Ok(UnitPositionCommand(x:, y:, z:, ..)) ->
      option.from_result({
        use x <- result.try(result.try(float32.bits(number: x), float32.value))
        use y <- result.try(result.try(float32.bits(number: y), float32.value))
        use z <- result.try(result.try(float32.bits(number: z), float32.value))
        Ok(start_place.moved(place: world_place, x:, y:, z:))
      })
    Error(Nil) -> None
  }
}

/// What a press judges of a player whose 0x262 the viewer takes, as the viewer's client
/// reads it (genesis_prime/game/player_state): alive when its health stat is above 0, with
/// that health and its Base Health as the maximum (0 when the 0x262 holds none), out of
/// combat and holding no state, the last position command's place in the viewer's world,
/// the Race row's hit radius, the viewer's faction's disposition toward its faction, bit 0 of
/// its PvP flags and its group id.
pub fn player_appeared(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
  unit unit: UnitCreatePlayer,
) -> PlayerState {
  let health =
    result.unwrap(
      unit_fields.stat(tail: unit.tail, stat_id: unit_fields.health_stat),
      0,
    )
  PlayerState(
    alive: health > 0,
    health:,
    maximum_health: result.unwrap(
      player_state.base_health_of(properties: unit.tail.properties),
      0,
    ),
    in_combat: False,
    held: [],
    place: player_place(
      commands: list.filter_map(unit.tail.movement_commands, fn(command) {
        case command {
          start_movement.Position(position) -> Ok(position)
          start_movement.Rotation(_)
          | start_movement.Time(_)
          | start_movement.Platform(_)
          | start_movement.TimedPath(_)
          | start_movement.Path(_)
          | start_movement.Velocity(_)
          | start_movement.VelocityDefault(_)
          | start_movement.MoveAsked(_)
          | start_movement.MoveDefault(_)
          | start_movement.FaceUnit(_)
          | start_movement.FacePoint(_)
          | start_movement.RotationDefault(_)
          | start_movement.StateFlags(_)
          | start_movement.StateDefault(_)
          | start_movement.Mode(_) -> Error(Nil)
        }
      }),
      world_place: movement.place(entered.movement),
    ),
    hit_radius: hit_radius.of_playing(tables:, race_id: RaceId(unit.race_id)),
    disposition: faction_level.disposition(
      levels: faction_level.of(tables:),
      from: entered.unit.tail.faction_id,
      to: unit.tail.faction_id,
    ),
    pvp_flagged: int.bitwise_and(unit.pvp_flags, 1) == 1,
    group_id: unit.group_id,
  )
}

/// What a viewer writes of news of a unit, from the units this connection has
/// shown and the ones the map reported gone: a 0x262 for a unit not shown and not
/// gone, which is then shown (the client keeps one unit per id until its 0x355,
/// and a unit that is gone would be a ghost), then the moves held for its sight; a
/// 0x355 for a shown unit, which is then no longer shown. Anything else is dropped. A
/// 0x262 or 0x355 that names unit 0 or this player's own unit is refused with an
/// error line, and writes nothing: the client makes the controlled unit of a
/// 0x262 with either id (0x1403d9760) and removes a unit with a 0x355
/// (0x1403d9590).
pub fn viewer_takes(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  news news: unit_news.PeerNews,
) -> client_connection.Handled(Session) {
  let unit_id = news.unit_id
  let shown = dict.has_key(entered.shown, unit_id)
  let creates_or_removes = case news.news {
    unit_news.Appeared(..)
    | unit_news.CreatureAppeared(..)
    | unit_news.Departed(..)
    | unit_news.Removed -> True
    unit_news.CastStarted(..)
    | unit_news.CastWent(..)
    | unit_news.CastMissed(..)
    | unit_news.CastTicked(..)
    | unit_news.CastTargetsRemoved(..)
    | unit_news.CastStackRemoved(..)
    | unit_news.CastFinished(..)
    | unit_news.CastInterrupted(..)
    | unit_news.Health(..)
    | unit_news.Died
    | unit_news.CameBack
    | unit_news.DeathLogged
    | unit_news.CameBackLogged
    | unit_news.CreatureMoved(..)
    | unit_news.CreaturePlaced(..)
    | unit_news.CreatureFaces(..)
    | unit_news.Targeting(..)
    | unit_news.Threat(..)
    | unit_news.CombatState(..)
    | unit_news.Shield(..)
    | unit_news.CrowdControlApplied(..)
    | unit_news.CrowdControlEnded(..)
    | unit_news.UnitStateHeld(..)
    | unit_news.UnitStateEnded(..)
    | unit_news.InterruptArmor(..)
    | unit_news.Absorption(..)
    | unit_news.Level(..)
    | unit_news.PropertiesChanged(..)
    | unit_news.Stealth(..)
    | unit_news.LookChanged(..)
    | unit_news.HeldCastEnded(..)
    | unit_news.HeldCastStarted(..) -> False
  }
  use <- bool.guard(
    when: creates_or_removes && names_own_unit(entered:, unit_id:),
    return: Continue(session, [refusal_logged(session:, unit_id:)]),
  )
  case news.news {
    unit_news.Appeared(unit:, generation:) -> {
      use <- bool.guard(when: set.contains(entered.gone, unit_id), return: {
        let #(viewing, dropped) =
          move_stamp.departed(viewing: entered.viewing, unit_id:, generation:)
        Continue(
          viewing_set(session:, viewing:),
          moves_dropped_logged(session:, unit_id:, dropped:),
        )
      })
      use #(viewing, released, dropped) <- snapshot_taken(
        session:,
        unit_id:,
        generation:,
        snapshot: move_stamp.snapshot(
          viewing: entered.viewing,
          unit_id:,
          generation:,
        ),
      )
      let session = viewing_set(session:, viewing:)
      use <- bool.guard(when: shown, return: {
        let #(session, written) = moves_released(session:, now:, released:)
        Continue(
          session,
          list.append(
            moves_dropped_logged(session:, unit_id:, dropped:),
            written,
          ),
        )
      })
      let unit =
        casts_listed(
          unit:,
          caster_unit_id: unit_id,
          viewer_unit_id: entered.unit_id,
        )
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            client_casts: casts_recorded(
              casts: entered.client_casts,
              unit_id:,
              listed: unit.tail.casts,
            ),
          )
        })
      let session =
        shown_changed(session:, change: dict.insert(
          _,
          unit_id,
          ShownPlayer(state: player_appeared(
            tables: session.settings.tables,
            entered:,
            unit:,
          )),
        ))
      let created = [
        connection_state.to_client(
          session,
          world_entry.unit_created_frame(unit:),
        ),
      ]
      let #(session, written) = moves_released(session:, now:, released:)
      Continue(session, list.append(created, written))
    }
    unit_news.CreatureAppeared(
      unit:,
      unit_type:,
      spawn_id:,
      life:,
      place:,
      hit_radius:,
      attackable:,
      hostile_to:,
      fights:,
    ) -> {
      use <- bool.guard(
        when: shown || set.contains(entered.gone, unit_id),
        return: Continue(session, []),
      )
      let unit = creature_casts_kept(unit:, casts: entered.client_casts)
      Continue(
        shown_changed(session:, change: dict.insert(
          _,
          unit_id,
          ShownCreature(
            spawn_id:,
            creature_id: Creature2Id(unit.creature_id),
            faction_id: unit.tail.faction_id,
            checklist_index: unit.checklist_index,
            path: creature_path.Standing(at: place),
            life:,
            alive: creature_unit.health_of(unit:) > 0,
            hit_radius:,
            attackable:,
            hostile_to:,
            fights:,
            in_combat: False,
            held: [],
            unit_states: [],
            face: None,
            faced_yaw: None,
          ),
        )),
        [
          connection_state.to_client(
            session,
            connection_frames.creature_created_frame(unit:, unit_type:),
          ),
        ],
      )
    }
    unit_news.Departed(generation:) -> {
      let #(viewing, dropped) =
        move_stamp.departed(viewing: entered.viewing, unit_id:, generation:)
      let session = viewing_set(session:, viewing:)
      unit_left(
        session:,
        now:,
        entered:,
        unit_id:,
        logged: moves_dropped_logged(session:, unit_id:, dropped:),
      )
    }
    unit_news.Removed ->
      unit_left(session:, now:, entered:, unit_id:, logged: [])
    unit_news.CastStarted(start:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      use <- bool.guard(
        when: client_casts.is_borrowed(
          casts: entered.client_casts,
          cast_id: start.cast_id,
        ),
        return: Continue(session, []),
      )
      Continue(
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            client_casts: client_casts.written(
              casts: entered.client_casts,
              cast_id: start.cast_id,
              caster_unit_id: unit_id,
            ),
          )
        }),
        [connection_state.to_client(session, cast_frame.started_frame(start:))],
      )
    }
    unit_news.HeldCastStarted(start:, go:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      use <- bool.guard(
        when: client_casts.is_held(
          casts: entered.client_casts,
          cast_id: start.cast_id,
        ),
        return: Continue(session, []),
      )
      Continue(
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            client_casts: client_casts.borrow(
              casts: entered.client_casts,
              cast_id: start.cast_id,
              ally_unit_id: unit_id,
            ),
          )
        }),
        [
          connection_state.to_client(session, cast_frame.started_frame(start:)),
          connection_state.to_client(session, cast_frame.went_frame(go:)),
        ],
      )
    }
    unit_news.HeldCastEnded(cast_id:) ->
      case
        client_casts.ally_ended(
          casts: entered.client_casts,
          cast_id:,
          ally_unit_id: unit_id,
        )
      {
        Ok(casts) ->
          Continue(
            connection_state.with_entered(session:, change: fn(entered) {
              world_entry.Entered(..entered, client_casts: casts)
            }),
            [
              connection_state.to_client(
                session,
                cast_frame.targets_removed_frame(
                  removed: spell_targets_removed.SpellTargetsRemoved(
                    cast_id:,
                    unit_ids: [unit_id],
                  ),
                ),
              ),
            ],
          )
        Error(Nil) -> Continue(session, [])
      }
    unit_news.CastWent(go:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: go.cast_id,
        frame: cast_frame.went_frame(go:),
        forgetting: False,
      )
    unit_news.CastMissed(missed:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: missed.cast_id,
        frame: cast_frame.missed_frame(missed:),
        forgetting: False,
      )
    unit_news.CastTicked(tick:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: tick.cast_id,
        frame: cast_frame.ticked_frame(tick:),
        forgetting: False,
      )
    unit_news.CastTargetsRemoved(removed:, destroyed:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: removed.cast_id,
        frame: cast_frame.targets_removed_frame(removed:),
        forgetting: destroyed,
      )
    unit_news.CastStackRemoved(removed:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id: removed.cast_id,
        frame: cast_frame.stack_removed_frame(removed:),
        forgetting: False,
      )
    unit_news.CastInterrupted(cast_id:) ->
      written_cast_frames(
        session:,
        entered:,
        cast_id:,
        frames: [
          cast_frame.interrupted_frame(cast_id:, unit_id:),
          cast_frame.finished_frame(cast_id:),
        ],
        forgetting: True,
      )
    unit_news.CastFinished(cast_id:) ->
      written_cast_frame(
        session:,
        entered:,
        cast_id:,
        frame: cast_frame.finished_frame(cast_id:),
        forgetting: True,
      )
    unit_news.Health(health:, dead:) ->
      creature_news(
        session:,
        entered:,
        unit_id:,
        news: unit_news.Health(health:, dead:),
      )
    unit_news.Died ->
      creature_news(session:, entered:, unit_id:, news: unit_news.Died)
    unit_news.CameBack | unit_news.DeathLogged | unit_news.CameBackLogged ->
      life_news(session:, entered:, unit_id:, news: news.news)
    unit_news.CreatureMoved(path:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session = creatures_resolved(session:, now:)
      let session =
        shown_changed(session:, change: fn(picture) {
          shown.with_path(picture:, unit_id:, path:)
        })
      Continue(
        session,
        case
          connection_frames.path_frame(
            entered:,
            unit_id:,
            path:,
            face: shown.face_of(picture: entered.shown, unit_id:),
          )
        {
          Some(frame) -> [connection_state.to_client(session, frame)]
          None -> []
        },
      )
    }
    unit_news.CreaturePlaced(place:, at_ms:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session = creatures_resolved(session:, now:)
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
    unit_news.CreatureFaces(face:, at_ms:) ->
      case shown.place_of(picture: entered.shown, unit_id:, now_ms: at_ms) {
        Error(Nil) -> Continue(session, [])
        Ok(standing_at) -> {
          let session = creatures_resolved(session:, now:)
          let session =
            shown_changed(session:, change: fn(picture) {
              shown.with_face(picture:, unit_id:, face:)
            })
          Continue(session, [
            connection_state.to_client(
              session,
              connection_frames.face_frame(
                entered:,
                unit_id:,
                standing_at:,
                face:,
                at_ms:,
              ),
            ),
          ])
        }
      }
    unit_news.Targeting(target_unit_id:, threat:) -> {
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
    unit_news.Threat(other_unit_id:, threat:) -> {
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
    unit_news.CombatState(in_combat:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session =
        shown_changed(session:, change: fn(picture) {
          shown.with_in_combat(picture:, unit_id:, in_combat:)
        })
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.combat_state_frame(unit_id:, in_combat:),
        ),
      ])
    }
    unit_news.Shield(shield:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.shield_frame(unit_id:, shield:),
        ),
      ])
    }
    unit_news.InterruptArmor(armor:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.interrupt_armor_frame(unit_id:, armor:),
        ),
      ])
    }
    unit_news.Absorption(absorption:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.absorption_frame(unit_id:, absorption:),
        ),
      ])
    }
    unit_news.Level(level:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.level_frame(unit_id:, level:),
        ),
      ])
    }
    unit_news.PropertiesChanged(properties:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session =
        shown_changed(session:, change: fn(picture) {
          shown.with_base_health(picture:, unit_id:, properties:)
        })
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.properties_changed_frame(unit_id:, properties:),
        ),
      ])
    }
    unit_news.Stealth(stealthed:) -> {
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
    unit_news.LookChanged(item_visuals:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.item_visuals_frame(unit_id:, item_visuals:),
        ),
      ])
    }
    unit_news.CrowdControlApplied(state:, instance_id:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session =
        shown_changed(session:, change: fn(picture) {
          shown.with_held_applied(picture:, unit_id:, state:, instance_id:)
        })
      Continue(session, [
        connection_state.to_client(
          session,
          cast_frame.control_applied_frame(unit_id:, state:, instance_id:),
        ),
      ])
    }
    unit_news.CrowdControlEnded(state:, cast_id:, instance_id:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      let session =
        shown_changed(session:, change: fn(picture) {
          shown.with_held_ended(picture:, unit_id:, instance_id:)
        })
      Continue(session, [
        connection_state.to_client(
          session,
          cast_frame.control_ended_frame(
            unit_id:,
            state:,
            cast_id:,
            instance_id:,
          ),
        ),
      ])
    }
    unit_news.UnitStateHeld(state:, number:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(
        shown_changed(session:, change: fn(picture) {
          shown.with_unit_state_held(picture:, unit_id:, state:, number:)
        }),
        [],
      )
    }
    unit_news.UnitStateEnded(number:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(
        shown_changed(session:, change: fn(picture) {
          shown.with_unit_state_ended(picture:, unit_id:, number:)
        }),
        [],
      )
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

/// What the picture holds of a static object its 0x262 creates: its spawn, the 0x262's creature,
/// where it puts the unit and its display's hit radius, 0.0 for a display with no
/// Creature2DisplayInfo row, and which player factions its faction is Hostile to. The
/// object stands in the world and zone of `world_place`, the player's place. The server
/// wrote the 0x262 with `static_object.create`, which always writes a position of finite
/// numbers.
fn object_shown(
  tables tables: table_store.Tables,
  spawn_id spawn_id: SpawnId,
  created created: static_object.Created,
  world_place world_place: Place,
) -> shown.Shown {
  let assert Ok(#(x, y, z)) = static_object.standing_at(created:)
    as "static_object.create writes a position of finite numbers"
  let hit_radius =
    creature2_display_info.get(
      tables,
      Creature2DisplayInfoId(static_object.display_info_id(created:)),
    )
    |> result.map(fn(display) { hit_radius.of_creature(display:) })
    |> result.unwrap(0.0)
  let faction_id = static_object.faction_id(created:)
  ShownObject(
    spawn_id:,
    creature_id: static_object.creature_id(created:),
    faction_id:,
    checklist_index: static_object.checklist_index(created:),
    place: start_place.moved(place: world_place, x:, y:, z:),
    hit_radius:,
    hostile_to: spawn.hostile_to_players(
      levels: faction_level.of(tables:),
      faction_id:,
    ),
  )
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

/// A player's or a creature's unit leaves the viewer's sight: when its client shows the
/// unit, the audiences it was in are left and the unit's casts it still holds are
/// finished before its 0x355 (`unit_removed`), after the lines `logged`.
fn unit_left(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  logged logged: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !dict.has_key(entered.shown, unit_id),
    return: Continue(session, logged),
  )
  let session =
    audiences_left(
      session:,
      viewers: viewers_of_unit(viewers: entered.viewers, unit_id:),
    )
  let kept =
    list.filter(
      client_casts.written_of_unit(casts: entered.client_casts, unit_id:),
      fn(cast_id) {
        list.contains(
          held_changes.kept_casts_of_unit(held: entered.held, unit_id:),
          cast_id,
        )
      },
    )
  let #(session, removal) =
    unit_removed(session:, now:, entered:, unit_id:, keeping: kept)
  Continue(session, list.flatten([logged, removal.written, removal.ended]))
}

/// The map ended the sight of `by`, the player's viewer, at `generation`: `by` leaves the
/// copy and the audiences of the casts, and is sent the removal for that sight.
fn viewer_unseen(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  by by: ConnectionId,
  generation generation: Generation,
) -> client_connection.Handled(Session) {
  let #(session, ended) =
    connection_landing.caster_unseen(
      session: audiences_left(
        session: viewers_changed(session:, change: dict.delete(_, by)),
        viewers: [by],
      ),
      now:,
      by:,
    )
  Continue(
    session,
    list.append(
      connection_state.news_to_connection(
        entered:,
        connection: by,
        news: unit_news.Departed(generation:),
      ),
      ended,
    ),
  )
}

/// What a viewer does with a chunk of a player's move (`SentByMove`): the move is applied,
/// dropped or held by the generation it is stamped with and the one the viewer holds
/// for the unit (genesis_prime/game/move_stamp); the map's `Gone` and the owner's later
/// notice leave that sight remembered as ended, so its moves are dropped. A hold that overflows is warned of once.
pub fn move_sent(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  move move: move_stamp.Move,
) -> client_connection.Handled(Session) {
  let #(viewing, verdict) = move_stamp.take(viewing: entered.viewing, move:)
  let session = viewing_set(session:, viewing:)
  case verdict {
    move_stamp.Apply -> {
      let #(session, written) = moves_released(session:, now:, released: [move])
      Continue(session, written)
    }
    move_stamp.Drop | move_stamp.Hold | move_stamp.HoldDroppingOldest ->
      Continue(session, [])
    move_stamp.HoldFirstOverflow(sight:) ->
      Continue(session, [
        connection_state.log(
          session:,
          level: step.LogWarning,
          text: "a unit's moves wait for the map's notice of their sight past "
            <> int.to_string(move_stamp.most_held_chunks)
            <> " chunks, so the oldest is dropped: unit "
            <> int.to_string(move.unit_id)
            <> ", the sight held "
            <> case sight {
            Some(move_stamp.Held(generation:)) ->
              int.to_string(generation.number(generation:))
            Some(move_stamp.Departed(generation:)) ->
              "ended at " <> int.to_string(generation.number(generation:))
            None -> "none"
          }
            <> ", the sight awaited "
            <> int.to_string(generation.number(generation: move.generation)),
        ),
      ])
  }
}

/// The owner's notice of a sight taken by the viewer's memory of the unit: the
/// continuation with what the notice releases, or an error line and nothing written
/// when the viewer refused it as older than the sight it holds or has seen end.
fn snapshot_taken(
  session session: Session,
  unit_id unit_id: Int,
  generation generation: generation.Generation,
  snapshot snapshot: Result(
    #(move_stamp.Viewing, List(move_stamp.Move), Int),
    Nil,
  ),
  next next: fn(#(move_stamp.Viewing, List(move_stamp.Move), Int)) ->
    client_connection.Handled(Session),
) -> client_connection.Handled(Session) {
  case snapshot {
    Ok(taken) -> next(taken)
    Error(Nil) ->
      Continue(session, [
        connection_state.log(
          session:,
          level: step.LogError,
          text: "the owner's notice of a sight is older than the sight its viewer holds or has seen end, so nothing is written: unit "
            <> int.to_string(unit_id)
            <> ", the notice's sight "
            <> int.to_string(generation.number(generation:)),
        ),
      ])
  }
}

/// The warning that moves held for a unit were dropped without their notice, none
/// when none were.
fn moves_dropped_logged(
  session session: Session,
  unit_id unit_id: Int,
  dropped dropped: Int,
) -> List(Effect(ConnectionEffect(Request))) {
  case dropped {
    0 -> []
    _ -> [
      connection_state.log(
        session:,
        level: step.LogWarning,
        text: int.to_string(dropped)
          <> " held chunks of a unit's moves were dropped, their sight ended or was replaced before its notice came: unit "
          <> int.to_string(unit_id),
      ),
    ]
  }
}

/// The session with the moves held for a notice that has come applied, in order, and
/// what they write.
fn moves_released(
  session session: Session,
  now now: Now,
  released released: List(move_stamp.Move),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  list.fold(released, #(session, []), fn(held, move) {
    let #(session, written) = held
    let #(session, more) = move_applied(session:, now:, move:)
    #(session, list.append(written, more))
  })
}

/// A move of a unit the client shows: its 0x638 is written and the picture's place
/// follows the move's last position; a unit the client does not show is written
/// nothing.
fn move_applied(
  session session: Session,
  now now: Now,
  move move: move_stamp.Move,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let move_stamp.Move(unit_id:, server_time_ms:, commands:, ..) = move
  case connection_state.entered_of(session.status) {
    Some(entered) ->
      case dict.has_key(entered.shown, unit_id) {
        False -> #(session, [])
        True -> {
          let session = creatures_resolved(session:, now:)
          let positions = position_commands(commands:)
          let session = case
            player_place(
              commands: positions,
              world_place: movement.place(entered.movement),
            )
          {
            Some(place) ->
              shown_changed(session:, change: shown.with_player_at(
                picture: _,
                unit_id:,
                place:,
              ))
            None -> session
          }
          #(session, [
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
      }
    None -> #(session, [])
  }
}

/// The position commands of a move's relayed commands, in order.
fn position_commands(
  commands commands: List(relayed_movement.RelayedMovement),
) -> List(UnitPositionCommand) {
  list.filter_map(commands, fn(command) {
    case command {
      relayed_movement.Position(position) -> Ok(position)
      relayed_movement.Time(..)
      | relayed_movement.Platform(..)
      | relayed_movement.TimedPath(..)
      | relayed_movement.Path(..)
      | relayed_movement.Velocity(..)
      | relayed_movement.VelocityDefault(..)
      | relayed_movement.MoveAsked(..)
      | relayed_movement.MoveDefault(..)
      | relayed_movement.Rotation(..)
      | relayed_movement.RotationDefault(..)
      | relayed_movement.FaceUnit(..)
      | relayed_movement.FacePoint(..)
      | relayed_movement.StateFlags(..)
      | relayed_movement.StateDefault(..)
      | relayed_movement.Mode(..) -> Error(Nil)
    }
  })
}

/// The session with the viewer's hold of players' moves replaced.
fn viewing_set(
  session session: Session,
  viewing viewing: move_stamp.Viewing,
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, viewing:)
  })
}

/// A creature's or a player's health or death news, for a unit this client shows: its picture
/// marks the unit dead at once, which a selection reads, and a player's copy takes the health
/// (genesis_prime/game/player_state), and the frame is
/// written, or held until the go of the caster's own round that names the unit is
/// written, so the client shows the number before the death it caused
/// (genesis_prime/game/strike). Another watcher's connection is not held: it is told
/// the news and the cast by two senders, which no order holds.
fn creature_news(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  news news: unit_news.News,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !dict.has_key(entered.shown, unit_id),
    return: Continue(session, []),
  )
  let session = case news {
    unit_news.Health(health:, dead:) ->
      shown_changed(session:, change: fn(picture) {
        let picture = case dead {
          True -> shown.with_alive(picture:, unit_id:, alive: False)
          False -> picture
        }
        shown.with_player_health(picture:, unit_id:, health:, dead:)
      })
    unit_news.Died ->
      shown_changed(session:, change: fn(picture) {
        shown.with_alive(picture:, unit_id:, alive: False)
      })
    unit_news.CameBack
    | unit_news.DeathLogged
    | unit_news.CameBackLogged
    | unit_news.Appeared(..)
    | unit_news.CreatureAppeared(..)
    | unit_news.Departed(..)
    | unit_news.Removed
    | unit_news.CastStarted(..)
    | unit_news.CastWent(..)
    | unit_news.CastMissed(..)
    | unit_news.CastTicked(..)
    | unit_news.CastTargetsRemoved(..)
    | unit_news.CastStackRemoved(..)
    | unit_news.CastFinished(..)
    | unit_news.CastInterrupted(..)
    | unit_news.CreatureMoved(..)
    | unit_news.CreaturePlaced(..)
    | unit_news.CreatureFaces(..)
    | unit_news.Targeting(..)
    | unit_news.Threat(..)
    | unit_news.CombatState(..)
    | unit_news.Shield(..)
    | unit_news.CrowdControlApplied(..)
    | unit_news.CrowdControlEnded(..)
    | unit_news.UnitStateHeld(..)
    | unit_news.UnitStateEnded(..)
    | unit_news.InterruptArmor(..)
    | unit_news.Absorption(..)
    | unit_news.Level(..)
    | unit_news.PropertiesChanged(..)
    | unit_news.Stealth(..)
    | unit_news.LookChanged(..)
    | unit_news.HeldCastEnded(..)
    | unit_news.HeldCastStarted(..) -> session
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
  news news: unit_news.News,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !dict.has_key(entered.shown, unit_id),
    return: Continue(session, []),
  )
  case news {
    unit_news.CameBack ->
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
    unit_news.DeathLogged ->
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.combat_log_frame(unit_id:, died: True),
        ),
      ])
    unit_news.CameBackLogged ->
      Continue(session, [
        connection_state.to_client(
          session,
          connection_frames.combat_log_frame(unit_id:, died: False),
        ),
      ])
    unit_news.Appeared(..)
    | unit_news.CreatureAppeared(..)
    | unit_news.Departed(..)
    | unit_news.Removed
    | unit_news.CastStarted(..)
    | unit_news.CastWent(..)
    | unit_news.CastMissed(..)
    | unit_news.CastTicked(..)
    | unit_news.CastTargetsRemoved(..)
    | unit_news.CastStackRemoved(..)
    | unit_news.CastFinished(..)
    | unit_news.CastInterrupted(..)
    | unit_news.Health(..)
    | unit_news.Died
    | unit_news.CreatureMoved(..)
    | unit_news.CreaturePlaced(..)
    | unit_news.CreatureFaces(..)
    | unit_news.Targeting(..)
    | unit_news.Threat(..)
    | unit_news.CombatState(..)
    | unit_news.Shield(..)
    | unit_news.CrowdControlApplied(..)
    | unit_news.CrowdControlEnded(..)
    | unit_news.UnitStateHeld(..)
    | unit_news.UnitStateEnded(..)
    | unit_news.InterruptArmor(..)
    | unit_news.Absorption(..)
    | unit_news.Level(..)
    | unit_news.PropertiesChanged(..)
    | unit_news.Stealth(..)
    | unit_news.LookChanged(..)
    | unit_news.HeldCastEnded(..)
    | unit_news.HeldCastStarted(..) -> Continue(session, [])
  }
}

/// A frame about a cast, written only for a cast whose start this viewer wrote, which
/// it then forgets when `forgetting`, with any mark that the client holds it with no caster:
/// the client drops a message that names a cast it does not hold.
fn written_cast_frame(
  session session: Session,
  entered entered: world_entry.Entered,
  cast_id cast_id: Int,
  frame frame: Frame,
  forgetting forgetting: Bool,
) -> client_connection.Handled(Session) {
  written_cast_frames(
    session:,
    entered:,
    cast_id:,
    frames: [frame],
    forgetting:,
  )
}

/// The frames of a cast of the unit written in order, when this client was sent the cast's
/// start (`client_casts.is_written`: a cast an ally listed or one held with no caster gets
/// none of its caster's frames); the cast is forgotten after them when `forgetting`.
fn written_cast_frames(
  session session: Session,
  entered entered: world_entry.Entered,
  cast_id cast_id: Int,
  frames frames: List(Frame),
  forgetting forgetting: Bool,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !client_casts.is_written(casts: entered.client_casts, cast_id:),
    return: Continue(session, []),
  )
  let session = case forgetting {
    True ->
      connection_state.with_entered(session:, change: fn(entered) {
        world_entry.Entered(
          ..entered,
          client_casts: client_casts.finished(
            casts: entered.client_casts,
            cast_id:,
          ),
        )
      })
    False -> session
  }
  Continue(
    session,
    list.map(frames, fn(frame) { connection_state.to_client(session, frame) }),
  )
}

/// What a unit's removal gives the client and the cast rule, in the order they go out: the
/// frames written to the client (the finish of each cast, then the unit's 0x355), then what
/// the cast rule asks when the player's casts lose the unit.
pub type Removal {
  Removal(
    written: List(Effect(ConnectionEffect(Request))),
    ended: List(Effect(ConnectionEffect(Request))),
  )
}

/// A unit removed from what the player's client shows: the unit and the casts it listed
/// are forgotten (`unit_forgotten`), the casts in `keeping` held with no caster instead of
/// finished (`casts_orphaned`), and, for a unit the client shows, each cast it was sent the
/// start of is finished before the unit's 0x355 (`finishes_of_forgotten_casts`) and the
/// player's own casts are told the unit is gone (`cast_loses_unit`). A unit not shown is only
/// forgotten and writes nothing. The removal news and the map's `Gone` and `ObjectsUnseen`
/// end a unit through it: the first keeps the casts a held change keeps, the others none.
pub fn unit_removed(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  keeping keeping: List(Int),
) -> #(Session, Removal) {
  let forgotten = unit_forgotten(session:, unit_id:)
  use <- bool.guard(when: !dict.has_key(entered.shown, unit_id), return: #(
    forgotten,
    Removal(written: [], ended: []),
  ))
  let #(session_after, ended) =
    cast_loses_unit(
      session: casts_orphaned(session: forgotten, cast_ids: keeping),
      now:,
      unit_id:,
    )
  #(
    session_after,
    Removal(
      written: list.append(
        finishes_of_forgotten_casts(session:, entered:, unit_id:, keeping:),
        [
          connection_state.to_client(
            session,
            connection_frames.unit_removed_frame(unit_id:),
          ),
        ],
      ),
      ended:,
    ),
  )
}

/// 0x7fe for each cast of the unit that this client was sent the start of and no
/// finish, in cast id order, written before the unit's 0x355: the client keeps a
/// cast that never gets its 0x7fe live (`cast.no_answer`), and a cast id used
/// again restarts it (`opcode.0x7ff`). A cast in `keeping` is not finished: the client
/// keeps a cast of a spell with propertyFlags 0x100 and its buff on another unit when
/// its caster's unit is removed (`cast.target_node_end`), and the player's connection
/// finishes it when the last change it holds from it ends
/// (genesis_prime/game/connection/landing).
fn finishes_of_forgotten_casts(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  keeping keeping: List(Int),
) -> List(Effect(ConnectionEffect(Request))) {
  client_casts.written_of_unit(casts: entered.client_casts, unit_id:)
  |> list.filter(fn(cast_id) { !list.contains(keeping, cast_id) })
  |> list.map(fn(cast_id) {
    connection_state.to_client(session, cast_frame.finished_frame(cast_id:))
  })
}

/// The session with the casts `cast_ids` marked as held by the client with no caster.
fn casts_orphaned(
  session session: Session,
  cast_ids cast_ids: List(Int),
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(
      ..entered,
      client_casts: client_casts.orphaned(
        casts: entered.client_casts,
        cast_ids:,
      ),
    )
  })
}

/// The unit's record with the casts its client may be given: the entries with a cast id
/// above 0 (`CreateCast 0x140561780` files cast id 0 as a pending cast, which makes the
/// client skip the rest of the list) and a caster that is not the viewer's own unit (the
/// viewer's own cast rule finished such a cast when it dropped its last node,
/// `proc.nodes_left`, and its client holds its casts itself). The client makes a cast whose
/// caster it does not know (`cast.unknown_caster`), so the entries of other players' casts
/// the unit holds stay beside its own. The cast in progress is kept only when an entry of
/// the unit's own holds it (`SetUnitCast 0x1404697a0` looks it up in the list).
fn casts_listed(
  unit unit: UnitCreatePlayer,
  caster_unit_id caster_unit_id: Int,
  viewer_unit_id viewer_unit_id: Int,
) -> UnitCreatePlayer {
  let casts =
    list.filter(unit.tail.casts, fn(cast) {
      cast.cast_id != 0 && cast.caster_unit_id != viewer_unit_id
    })
  let own =
    list.filter(casts, fn(cast) { cast.caster_unit_id == caster_unit_id })
  let cast_id = case
    list.any(own, fn(cast) { cast.cast_id == unit.tail.cast_id })
  {
    True -> unit.tail.cast_id
    False -> 0
  }
  UnitCreatePlayer(..unit, tail: UnitCreateTail(..unit.tail, casts:, cast_id:))
}

/// The casts the client holds after the create of the unit `unit_id` listed `listed`: an
/// entry of the unit's own cast is one its caster's frames end, and an entry of another
/// player's cast is borrowed from the unit (`client_casts`).
fn casts_recorded(
  casts casts: client_casts.Casts,
  unit_id unit_id: Int,
  listed listed: List(UnitCreateCast),
) -> client_casts.Casts {
  list.fold(listed, casts, fn(casts, cast) {
    case cast.caster_unit_id == unit_id {
      True ->
        client_casts.written(
          casts:,
          cast_id: cast.cast_id,
          caster_unit_id: unit_id,
        )
      False ->
        client_casts.borrow(
          casts:,
          cast_id: cast.cast_id,
          ally_unit_id: unit_id,
        )
    }
  })
}

/// The creature's record with the casts its client was given: an entry of the list
/// stays only when the viewer was told its caster's start (`client_casts.is_written`). A
/// viewer not told of a cast is sent none of its 0x7fe, 0x7f9 or 0x811
/// (`written_cast_frames`), so the node of an entry for it would stay until the creature
/// leaves its sight (`cast.target_node_end`). The tail's cast id stays 0 and the viewer's
/// casts are not changed.
fn creature_casts_kept(
  unit unit: UnitCreateCreature,
  casts casts: client_casts.Casts,
) -> UnitCreateCreature {
  UnitCreateCreature(
    ..unit,
    tail: UnitCreateTail(
      ..unit.tail,
      casts: list.filter(unit.tail.casts, fn(cast) {
        client_casts.is_written(casts:, cast_id: cast.cast_id)
      }),
    ),
  )
}

/// The unit of the player's own record as another player is created with it: at
/// the place the player stands at now, with its health now as stat 0, so a dead
/// player is created dead (`0x140457bc5`), its shield now as stat 20
/// (`opcode.0x938`) and its Interrupt Armor as stat 21 while it is above 0
/// (`opcode.0x938.interrupt_armor`: the create's stat list sets it) and its absorption as
/// stat 22 while it is above 0 (`opcode.0x938`, `0x14064fb40`: the create's stat list sets
/// it), without its class resource and its Focus: the stat and the ResourceMax
/// property of the player's own 0x262, and stat 1, are left out, since a 0x935 goes to the
/// player alone (`opcode.0x262.resource_stats`); property 5, the Focus maximum, stays, a gear
/// property like the rest that 0x93a keeps current; stamped from the map's clock,
/// from the origin `Joined` carried (`map.server_time`). Its list holds the player's own
/// casts and the casts other players' casts hold on it (`held_changes.cast_views`), in cast
/// id order.
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
  let focus_stat = unit_fields.resource_stat_id(slot: class_resource.focus_slot)
  let resource_max = unit_fields.resource_max_property(slot:)
  UnitCreatePlayer(
    ..unit,
    tail: UnitCreateTail(
      ..unit.tail,
      casts: unit_casts.entries_of(
        views: list.append(
          cast_state.views(cast: entered.cast, caster_unit_id: entered.unit_id),
          held_changes.cast_views(
            held: entered.held,
            holder_unit_id: entered.unit_id,
            now_ms: now.monotonic_ms,
          ),
        ),
        now_ms: now.monotonic_ms,
      ),
      cast_id: cast_state.current_cast_id(cast: entered.cast),
      stats: list.append(
        list.filter_map(unit.tail.stats, fn(stat) {
          case stat.stat_id {
            id if id == unit_fields.health_stat ->
              Ok(unit_fields.integer_stat(stat_id: id, value: health))
            id if id == unit_fields.shield_stat ->
              Ok(unit_fields.integer_stat(stat_id: id, value: shield))
            id if id == resource_stat || id == focus_stat -> Error(Nil)
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
  change change: fn(Dict(ConnectionId, player_address.Viewer)) ->
    Dict(ConnectionId, player_address.Viewer),
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, viewers: change(entered.viewers))
  })
}

/// The connections of the viewers that own the unit `unit_id`.
fn viewers_of_unit(
  viewers viewers: Dict(ConnectionId, player_address.Viewer),
  unit_id unit_id: Int,
) -> List(ConnectionId) {
  dict.to_list(viewers)
  |> list.filter_map(fn(viewer) {
    case { viewer.1 }.unit_id == unit_id {
      True -> Ok(viewer.0)
      False -> Error(Nil)
    }
  })
}

/// The session with these connections out of every audience of the caster's casts: a
/// player that stops seeing the caster has forgotten its casts, so none of their news
/// goes to it. A player leaves sight in both directions in one step, and the caster's
/// connection hears of it as the map's `UnseenBy` and as the player's removal in either
/// order, so both take the player out of the audiences before they end any cast.
fn audiences_left(
  session session: Session,
  viewers viewers: List(ConnectionId),
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(
      ..entered,
      cast: list.fold(viewers, entered.cast, fn(cast, viewer) {
        cast_state.audience_left(cast:, viewer:)
      }),
    )
  })
}

/// The session with its pictured creatures holding the yaw their clients show now
/// (`world_entry.with_creatures_resolved`).
fn creatures_resolved(session session: Session, now now: Now) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.with_creatures_resolved(entered:, now_ms: now.monotonic_ms)
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
/// written their finish before the unit's 0x355, `finishes_of_forgotten_casts`), the casts
/// it listed no longer held for it (`client_casts.unit_forgotten`) and the news held for it
/// dropped.
fn unit_forgotten(session session: Session, unit_id unit_id: Int) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(
      ..entered,
      shown: dict.delete(entered.shown, unit_id),
      client_casts: client_casts.unit_forgotten(
        casts: entered.client_casts,
        unit_id:,
      ),
      strike: strike.forget(strike: entered.strike, unit_id:),
    )
  })
}

/// The player's casts told that a unit its client no longer shows is gone, so
/// their nodes on it end (genesis_prime/game/cast/proc `unit_removed`): the session with
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
        cast_proc.unit_removed(
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

/// The session with the unit marked gone, so a 0x262 of it that lands after the map's
/// `Gone` writes nothing.
fn marked_gone(session session: Session, unit_id unit_id: Int) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, gone: set.insert(entered.gone, unit_id))
  })
}
