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
////   closed round is the cast rule's `went`, given the pose each Hit creature has in the
////   picture at that moment (`shown.poses_of`) for its Proxies' target gates. A viewer
////   writes a creature's health and
////   death (`Health`, `Died`) for a creature it shows, whatever its own casts.
//// - **Heals** are the cast rule's: a `CasterChangeStarts` whose change is a `ShieldHeal`
////   raises the player's shield by its amount and tells the player's client and its viewers
////   (genesis_prime/game/connection/healing), where one whose change is a `Property` is
////   applied to the player's properties (genesis_prime/game/connection/properties).
//// - **Absorbs** are the cast rule's too: a `CasterChangeStarts` whose change is an `Absorb`
////   gives the player's life a pool, and a `CasterChangeEnds` is carried out for both owners
////   of a caster change in turn, the properties then the life, each by source
////   (genesis_prime/game/connection/absorption).
//// - **Disguises** are the cast rule's too: a `CasterChangeStarts` whose change is a `Look`
////   starts the disguise on the player's look and tells the player's client and its
////   viewers the slots that changed, and each `CasterChangeEnds` ends a property modifier
////   and a disguise of its source, whichever the source holds
////   (genesis_prime/game/connection/look). A death, a type 80 removal, a persistence end
////   and the node's end by time end the disguise as they end a modifier; a camp sends no
////   0x933.
//// - **Modifiers on a creature** are the cast rule's: a `TargetChangeStarts` or
////   `TargetChangeEnds` is told to the creature of the life the go struck, through the
////   creature registry with no watch, as `TellTargetChange`; the creature applies or
////   removes it and tells its viewers (genesis_prime/world_map/creature). With no player
////   in the world it is dropped.
//// - **Stealth** is the cast rule's (genesis_prime/game/cast): its `StealthChanged` is
////   carried out as the owner's 0x8f5, the viewers' news, and last a tell to the run of
////   the player's map, so the map keeps the player out of every creature's ring
////   (genesis_prime/world_map/map `StealthChanged`). The connection tells the map `Moved`,
////   `Ready` and `StealthChanged` from its own process, so the map takes them in the order
////   the connection decided them:
////
////   ```
////   connection (cast rule)                         map                           creature
////   a toggle press, a landed blow on 83834 or a death moves the stealth
////     StealthChanged(s) ─▶ 0x8f5 {owner, s}         ─▶ the owner's client
////                       ─▶ Tell(each viewer, Stealth(s))
////                       ─▶ Tell(map, TellStealthChanged(connection, s))
////                                                    ─▶ a change: Withdrew(connection) when s,
////                                                       Approached when not s ─────────────▶ near
////   ```
////
////   - The tell goes once per change: the cast rule emits only on a change, so a repeat is
////     never sent. A player with no map to tell (no player in the world) tells none.
////   - A camp or the Holocrypt clears the stealth in the cast state with no
////     `StealthChanged`, so no tell follows; the map's `Leave` removes the player with its
////     copy, and the next stay starts unstealthed on both sides.
////   - A connection that ends while stealthed tells nothing: the map's watch removes the
////     player and sends its creatures `Unwatched`.
////   - A tell the map takes after the connection's `Leave` is an error line in the map and
////     changes nothing; the connection sends none, and a map that is not running is
////     the tell's dropped send, as for `Moved`.
//// - **Persistence** is checked at the end of each input of a player in the world
////   (`persisted`, called by the connection's two places that settle an input: the
////   frames it takes and everything else), and the casts it ends are written after what
////   the input wrote itself.

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/activate
import genesis_prime/game/area
import genesis_prime/game/cast
import genesis_prime/game/connection/absorption as connection_absorption
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/healing as connection_healing
import genesis_prime/game/connection/look as connection_look
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/connection/properties as connection_properties
import genesis_prime/game/connection/resource as connection_resource
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/damage
import genesis_prime/game/hit_radius
import genesis_prime/game/loadout
import genesis_prime/game/movement
import genesis_prime/game/objective
import genesis_prime/game/player_life
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/rating
import genesis_prime/game/shown
import genesis_prime/game/spell_area
import genesis_prime/game/strike
import genesis_prime/game/strike_tell.{type Answered}
import genesis_prime/game/target_group
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type TimerId, CancelTimer,
  OwnEffect, StartTimer,
}
import genesis_prime/table/creature2
import genesis_prime/table/id.{RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_path
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result

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
      caster: caster_of(tables: session.settings.tables, entered:),
      plans: connection_state.plans_of(session:),
      now:,
    )
  {
    Ok(#(updated, effects)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: cast.describe(refusal))
  }
}

/// The player's right-click of a unit, its 0x97, from inside 0x038C in the world: the
/// cast rule decides what the unit is to the player from the picture (`activate_target`),
/// refuses or starts the activate cast, and a refusal of the frame ends the connection.
pub fn activate_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let tables = session.settings.tables
  let caster = caster_of(tables:, entered:)
  // The player's Race row is in the tables (the load fails otherwise), so a missing one
  // crashes.
  let assert Ok(caster_radius) =
    hit_radius.of_player(tables:, race_id: RaceId(caster.player.race_id))
    as "hit_radius.requirements fails the load when a playable race has no Race row"
  case
    cast.activate(
      cast: entered.cast,
      body: inner.body,
      caster:,
      activations: connection_state.activations_of(session:),
      target_of: activate_target(tables:, picture: entered.shown),
      caster_radius:,
      now:,
    )
  {
    Ok(#(updated, effects)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: cast.describe(refusal))
  }
}

/// The player's 0xb3, the use of a unit with no activate spell (genesis_prime/game/cast
/// `activate_unit`), whose go the rule raises at once: the connection counts it for the
/// objectives as an activate cast's go is counted.
pub fn activate_unit_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let tables = session.settings.tables
  let caster = caster_of(tables:, entered:)
  // The player's Race row is in the tables (the load fails otherwise), so a missing one
  // crashes.
  let assert Ok(caster_radius) =
    hit_radius.of_player(tables:, race_id: RaceId(caster.player.race_id))
    as "hit_radius.requirements fails the load when a playable race has no Race row"
  case
    cast.activate_unit(
      cast: entered.cast,
      body: inner.body,
      caster:,
      activations: connection_state.activations_of(session:),
      unit_of: used_unit(
        tables:,
        picture: entered.shown,
        quests: entered.quests,
        now_ms: now.monotonic_ms,
      ),
      caster_radius:,
    )
  {
    Ok(effects) -> carry_cast(session:, now:, effects:)
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: cast.describe(refusal))
  }
}

/// What the creature or object a 0xb3 names is to the player, from the units the client
/// shows: its Creature2 id and activate columns, its checklist index, its body now (a
/// creature where its path puts it) and whether the server offers its use now (an open
/// objective of the quest log counts it, `objective.use_targets`), or `Error(Nil)` for
/// another player or no unit.
fn used_unit(
  tables tables: table_store.Tables,
  picture picture: shown.Picture,
  quests quests: QuestLog,
  now_ms now_ms: Int,
) -> fn(Int) -> Result(cast.UsedUnit, Nil) {
  let offered_to = objective.use_targets(log: quests, tables:)
  fn(unit_id) {
    use one <- result.try(dict.get(picture, unit_id))
    case one {
      shown.ShownPlayer -> Error(Nil)
      shown.ShownObject(place:, hit_radius:, ..) ->
        used_unit_at(
          tables:,
          one:,
          offered_to:,
          body: activate.Body(place:, radius: hit_radius),
        )
      shown.ShownCreature(path:, hit_radius:, ..) ->
        used_unit_at(
          tables:,
          one:,
          offered_to:,
          body: activate.Body(
            place: creature_path.place_at(path:, now_ms:),
            radius: hit_radius,
          ),
        )
    }
  }
}

fn used_unit_at(
  tables tables: table_store.Tables,
  one one: shown.Shown,
  offered_to offered_to: fn(target_group.Unit, Int) -> Bool,
  body body: activate.Body,
) -> Result(cast.UsedUnit, Nil) {
  use #(unit, checklist_index) <- result.try(shown.target_of(
    tables:,
    shown: one,
  ))
  // The Creature2 row is in the tables, since the unit's 0x262 was made from it.
  use row <- result.map(creature2.get(tables:, id: unit.creature_id))
  cast.UsedUnit(
    creature_id: unit.creature_id.value,
    creature: activate.creature_of(row:),
    checklist_index:,
    body:,
    offered: offered_to(unit, checklist_index),
  )
}

/// What the unit a right-click names is to the player, from the units its client shows:
/// a static object with its creature's activate row and body, a creature that fights,
/// another player or nothing shown.
fn activate_target(
  tables tables: table_store.Tables,
  picture picture: shown.Picture,
) -> fn(Int) -> activate.Target {
  fn(unit_id) {
    case dict.get(picture, unit_id) {
      Error(Nil) -> activate.Unseen
      Ok(shown.ShownPlayer) -> activate.AnotherPlayer
      Ok(shown.ShownCreature(..)) -> activate.Fighter
      Ok(shown.ShownObject(
        creature_id:,
        checklist_index:,
        place:,
        hit_radius:,
        ..,
      )) -> {
        // The object's Creature2 row is in the tables, since its 0x262 was made from it.
        let assert Ok(row) = creature2.get(tables:, id: creature_id)
          as "a shown object's Creature2 row is in the tables it was made from"
        activate.Object(
          creature_id: creature_id.value,
          creature: activate.creature_of(row:),
          checklist_index:,
          body: activate.Body(place:, radius: hit_radius),
        )
      }
    }
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
          caster: caster_of(tables: session.settings.tables, entered:),
          now:,
        )
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    }
  }
}

/// What an input decided, with the casts whose persistence stopped holding ended after
/// the input's own effects (genesis_prime/game/cast `persisted`). It runs at the end of
/// each input of a player in the world that goes on: with no player in the world, or no
/// cast whose spell has a persistence column, it changes nothing. The input's effects
/// come first, as the server writes them in order.
pub fn persisted(
  handled handled: client_connection.Handled(Session),
  now now: Now,
) -> client_connection.Handled(Session) {
  case handled {
    Continue(session:, effects:) ->
      case connection_state.held_in_the_world(session.status) {
        Some(#(_, entered)) ->
          case cast.persists(cast: entered.cast) {
            False -> handled
            True -> {
              let #(updated, ended) =
                cast.persisted(
                  cast: entered.cast,
                  caster: caster_of(tables: session.settings.tables, entered:),
                  now:,
                )
              let #(session, written) =
                cast_effects(
                  session: with_cast(session:, cast: updated),
                  now:,
                  effects: ended,
                )
              Continue(session, list.append(effects, written))
            }
          }
        None -> handled
      }
    client_connection.Asking(..) | client_connection.Done(..) -> handled
  }
}

/// The player as its cast rule takes it: who it is, where it stands, what it
/// holds, who sees it, whether it is dead or in combat and its health and shield.
pub fn caster_of(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
) -> cast.Caster {
  let life = entered.life
  cast.Caster(
    unit_id: entered.unit_id,
    place: movement.place(entered.movement),
    abilities: loadout.bag(loadout: entered.loadout),
    weapon: entered.gear.weapon,
    audience: connection_state.viewer_connections(entered:),
    dead: player_life.state(life:) == player_life.Dead,
    resources: entered.resources,
    in_combat: player_life.in_combat(life:),
    life_vitals: dict.from_list([
      #(
        cast.health_vital,
        prerequisite.Vital(
          current: int.to_float(player_life.health(life:)),
          maximum: int.to_float(player_life.max_health(life:)),
        ),
      ),
      #(
        cast.shield_vital,
        prerequisite.Vital(
          current: int.to_float(player_life.shield(life:)),
          maximum: int.to_float(player_life.max_shield(life:)),
        ),
      ),
    ]),
    factions: prerequisite.Factions(
      current: entered.unit.tail.faction_id,
      base: entered.unit.tail.base_faction_id,
    ),
    stats: stats_of(entered:),
    vitals: damage.Vitals(
      health: player_life.health(life:),
      max_health: player_life.max_health(life:),
      shield: player_life.shield(life:),
      max_shield: player_life.max_shield(life:),
    ),
    quests: entered.quests,
    player: prerequisite_player.of(tables:, entered:),
  )
}

/// What the player's damage and heals read of it: its level and its Assault and Support
/// Rating.
fn stats_of(entered entered: world_entry.Entered) -> damage.Attacker {
  damage.Attacker(
    level: connection_state.level_of(entered:),
    assault_rating: unit_properties.value(
      properties: entered.properties,
      property: unit_properties.assault_rating,
    ),
    support_rating: unit_properties.value(
      properties: entered.properties,
      property: unit_properties.support_rating,
    ),
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
/// map, a timer or a log line, a stealth change written to the player, told to its
/// viewers and last to the player's map, a press's costs paid from the class resource and a
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
      cast.Activated(unit_id:, ..), Some(entered) ->
        // The go is raised even when the unit has left the picture, and a use of a
        // creature the player no longer sees counts for no objective.
        case
          dict.get(entered.shown, unit_id)
          |> result.try(fn(shown) {
            shown.target_of(tables: session.settings.tables, shown:)
          })
        {
          Ok(#(target, checklist_index)) ->
            connection_objective.counted(
              session:,
              now:,
              event: objective.Used(target:, checklist_index:),
            )
          Error(Nil) -> #(session, [])
        }
      cast.Activated(..), None -> #(session, [])
      cast.Pay(payments:), _ -> connection_resource.paid(session:, payments:)
      cast.Gain(gains:), _ -> connection_resource.gained(session:, gains:)
      cast.CasterChangeStarts(source:, change: cast.Property(modifier:)), _ ->
        connection_properties.started(session:, now:, source:, modifier:)
      cast.CasterChangeStarts(change: cast.ShieldHeal(amount:), ..), _ ->
        connection_healing.shield_healed(session:, now:, amount:)
      cast.CasterChangeStarts(source:, change: cast.Absorb(amount:, mask:)), _
      -> connection_absorption.started(session:, now:, source:, amount:, mask:)
      cast.CasterChangeStarts(source:, change: cast.Look(disguise:)), _ ->
        connection_look.started(session:, source:, disguise:)
      cast.CasterChangeEnds(source:), _ -> {
        let #(session, properties) =
          connection_properties.ended(session:, now:, source:)
        let #(session, look) = connection_look.ended(session:, source:)
        let #(session, absorption) =
          connection_absorption.ended(session:, now:, source:)
        #(session, list.flatten([properties, look, absorption]))
      }
      cast.StealthChanged(stealthed:), Some(entered) -> #(
        session,
        list.flatten([
          [
            connection_state.to_client(
              session,
              connection_frames.unit_stealth_frame(
                unit_id: entered.unit_id,
                stealthed:,
              ),
            ),
          ],
          connection_state.news_to_viewers(
            entered:,
            news: client_connection.Stealth(stealthed:),
          ),
          // The map keeps a stealthed player out of every creature's ring: Jim's
          // decision, a server choice. Told last, after the owner's 0x8f5 and the
          // viewers' news.
          [
            connection_state.tells_the_map(
              entered:,
              request: client_connection.TellStealthChanged(
                connection: client_connection.connection(session.link),
                stealthed:,
              ),
            ),
          ],
        ]),
      )
      cast.StealthChanged(..), None -> #(session, [])
      cast.TargetChangeStarts(
        unit_id:,
        life:,
        struck_at_ms:,
        source:,
        modifier:,
      ),
        Some(entered)
      -> #(session, [
        tells_the_creature(
          session:,
          entered:,
          unit_id:,
          life:,
          change: client_connection.ChangeStarts(
            source:,
            modifier:,
            struck_at_ms:,
          ),
        ),
      ])
      cast.TargetChangeStarts(..), None -> #(session, [])
      cast.TargetChangeEnds(unit_id:, life:, source:), Some(entered) -> #(
        session,
        [
          tells_the_creature(
            session:,
            entered:,
            unit_id:,
            life:,
            change: client_connection.ChangeEnds(source:),
          ),
        ],
      )
      cast.TargetChangeEnds(..), None -> #(session, [])
    }
    #(session, list.append(done, more))
  })
}

/// The tell of a property modifier's start or end to the creature `unit_id` of
/// `life`, in the run of the player's map, through the creature registry with no
/// watch, as a strike's tell goes.
fn tells_the_creature(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  life life: Int,
  change change: client_connection.TargetChange,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Creature(
      map: entered.map,
      incarnation: entered.incarnation,
      unit_id:,
      life:,
    ),
    request: client_connection.TellTargetChange(
      connection: client_connection.connection(session.link),
      change:,
    ),
  ))
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
/// player faction it is of, what its damage reads of it (its level and its Assault and
/// Support Rating) and its properties.
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
    pose: area.pose_of(place:),
    place:,
    move_seq: session.move_seq,
    stay: entered.stay,
    faction:,
    stats: stats_of(entered:),
    properties: entered.properties,
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
            caster: caster_of(tables: session.settings.tables, entered:),
            now:,
            cast_id: asked.cast_id,
            phase: asked.phase,
            struck:,
            poses: shown.poses_of(
              picture: entered.shown,
              unit_ids: cast.hit_units(struck:),
              now_ms: now.monotonic_ms,
            ),
            indexes: shown.checklist_indexes_of(
              picture: entered.shown,
              unit_ids: cast.hit_units(struck:),
            ),
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
    | client_connection.Level(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..)
    | client_connection.LookChanged(..) -> []
  }
}
