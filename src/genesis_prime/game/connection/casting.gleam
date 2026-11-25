//// The player's casts and strikes on the game connection
//// (genesis_prime/game/connection): the cast messages, the cast and strike
//// timers, the creatures' answers to a strike, and both rules' effects carried
//// out.
////
//// - **Casts** are a feature of their own (genesis_prime/game/cast): the player's
////   `Entered` keeps its cast state, the routing table sends 0x9a, 0x4DB and 0x801 to it
////   from inside 0x038C with the player in the world, and the timers `cast_state.owns`
////   names are its (`other_timer_fired`). The rule turns its
////   effects into writes to the caster, tells of news to the viewers
////   (`CastStarted`, `CastWent`, `CastFinished`, in the run of the player's map),
////   timers and log lines. A viewer writes a 0x7ff only for a caster it shows, and
////   a go or finish only for a start it wrote (`client_casts`, by cast id, kept
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
//// - **Heals** are the cast rule's: a `CasterChangeStarts` whose change is a `Heal`
////   raises the player's health or shield by its amount and tells the player's client and its viewers
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
////   in the world it is dropped. A `CreatureControlsEnd` is told the same way, as the
////   creature's `ControlsEnd`.
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
import genesis_prime/game/ability_book
import genesis_prime/game/activate
import genesis_prime/game/area
import genesis_prime/game/cast
import genesis_prime/game/cast/creature_view
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/persist as cast_persist
import genesis_prime/game/cast/press as cast_press
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/healing as connection_healing
import genesis_prime/game/connection/item_spend as connection_item_spend
import genesis_prime/game/connection/landing as connection_landing
import genesis_prime/game/connection/look as connection_look
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/connection/projector as connection_projector
import genesis_prime/game/connection/resource as connection_resource
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/damage
import genesis_prime/game/forced_move
import genesis_prime/game/gear
import genesis_prime/game/heal_split
import genesis_prime/game/hit_radius
import genesis_prime/game/innate
import genesis_prime/game/interaction
import genesis_prime/game/inventory
import genesis_prime/game/item_property
import genesis_prime/game/item_use
import genesis_prime/game/limited_action_set

import genesis_prime/game/held_changes
import genesis_prime/game/movement
import genesis_prime/game/objective
import genesis_prime/game/objective_link
import genesis_prime/game/passed_in_value
import genesis_prime/game/player_address
import genesis_prime/game/player_life
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/rating
import genesis_prime/game/shown
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/spell_surge
import genesis_prime/game/strike
import genesis_prime/game/strike_tell.{
  type Answered, type PlayerAnswered, type PlayerEvent,
}
import genesis_prime/game/target_group
import genesis_prime/game/unit_state
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/random
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type TimerId, CancelTimer,
  LogWarning, OwnEffect, StartTimer,
}
import genesis_prime/table/creature2
import genesis_prime/table/eldan_augmentation
import genesis_prime/table/id.{
  type Creature2Id, type Item2Id, Creature2Id, Faction2Id, RaceId, Spell4Id,
}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_path
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set

/// What the cast messages do, taken from inside 0x038C, in the world
/// (genesis_prime/game/cast): the press is refused or accepted and its writes,
/// tells and timers are carried out, the cancel ends a cast, and a refusal ends
/// the connection. A dead player's press is checked as the client checks it
/// (`caster_of`), and the unit a press names is judged from the player's picture
/// (`activate_target`).
pub fn cast_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: cast_state.Message,
) -> client_connection.Handled(Session) {
  let WorldCast(caster:, target_of:, ..) = world_cast(session:, now:, entered:)
  case
    cast.take(
      cast: entered.cast,
      message:,
      body: inner.body,
      caster:,
      plans: connection_state.held_plans_of(session:, entered:),
      target_of:,
      now:,
    )
  {
    Ok(#(updated, effects)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: cast_frame.describe(refusal),
      )
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
  let WorldCast(caster:, caster_radius:, target_of:) =
    world_cast(session:, now:, entered:)
  case
    cast.activate(
      cast: entered.cast,
      body: inner.body,
      caster:,
      activations: connection_state.activations_of(session:),
      target_of:,
      caster_radius:,
      now:,
    )
  {
    Ok(#(updated, effects)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: cast_frame.describe(refusal),
      )
  }
}

/// The player's use of an item, its 0x943, from inside 0x038C in the world: the cast rule
/// takes the item from the place the message names among the items the character holds,
/// applies the client's checks of the item (genesis_prime/game/item_use) with the quest log
/// and the level, and starts the activate cast of the item's spell at the unit, which the
/// connection counts at its go as an activate cast's is counted. A refusal of the frame ends
/// the connection.
pub fn item_use_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let tables = session.settings.tables
  let WorldCast(caster:, caster_radius:, target_of:) =
    world_cast(session:, now:, entered:)
  case
    cast.use_item(
      cast: entered.cast,
      body: inner.body,
      caster:,
      held_at: fn(place) {
        inventory.held_at(items: entered.items, place:)
        |> result.map(fn(held) {
          cast_state.ItemAtPlace(
            item2_id: held.item2_id,
            charges: held.words.charges,
          )
        })
        |> option.from_result
      },
      check: fn(
        item,
        charges,
        second_item,
        target_checklist_index,
        prerequisite,
      ) {
        item_use.check(
          tables:,
          item:,
          charges:,
          player_level: caster.player.level,
          quests: caster.quests,
          second_item:,
          target_checklist_index:,
          prerequisite:,
        )
      },
      activations: connection_state.activations_of(session:),
      shortcuts: connection_state.shortcut_spells_of(session:),
      item_cast_of: fn(item) {
        cast_state.Item(
          item_level: passed_in_value.level_of_item(tables:, item2_id: item),
          passed_in: passed_in_value.of_item(tables:, item2_id: item),
        )
      },
      target_of:,
      in_cast_group: fn(group, unit_id) {
        shown.in_group(tables:, picture: entered.shown, group:, unit_id:)
      },
      caster_radius:,
      now:,
    )
  {
    Ok(cast_state.Frames(cast: updated, effects:)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Ok(cast_state.Started(press:, start:)) ->
      connection_item_spend.started(
        session:,
        now:,
        holder:,
        entered:,
        press:,
        start:,
        release: cast_effects,
      )
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: cast_frame.describe(refusal),
      )
  }
}

/// The player's 0x9d, the press of the button an open cast objective gave it, from inside
/// 0x038C in the world: the cast rule refuses the press of a spell the client holds no
/// button for, judges the unit a targeted spell names from the picture (`activate_target`,
/// `shown.in_group`), and starts the cast, whose first go the connection counts for the
/// objectives (`cast.ShortcutCast`). A refusal of the frame ends the connection.
pub fn shortcut_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let tables = session.settings.tables
  let WorldCast(caster:, caster_radius:, target_of:) =
    world_cast(session:, now:, entered:)
  case
    cast.shortcut(
      cast: entered.cast,
      body: inner.body,
      caster:,
      shortcuts: connection_state.shortcut_spells_of(session:),
      held: set.map(entered.buttons, fn(button) { button.spell4_id.value }),
      activations: connection_state.activations_of(session:),
      target_of:,
      in_cast_group: fn(group, unit_id) {
        shown.in_group(tables:, picture: entered.shown, group:, unit_id:)
      },
      caster_radius:,
      now:,
    )
  {
    Ok(#(updated, effects)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: cast_frame.describe(refusal),
      )
  }
}

/// What a message that casts at a unit needs of the player's world: the caster, the
/// radius of its body and what each unit is to the player (`activate_target`).
type WorldCast {
  WorldCast(
    caster: cast_state.Caster,
    caster_radius: Float,
    target_of: fn(Int) -> activate.Target,
  )
}

fn world_cast(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
) -> WorldCast {
  let tables = session.settings.tables
  let caster = caster_of(tables:, entered:)
  // The player's Race row is in the tables (the load fails otherwise), so a missing one
  // crashes.
  let assert Ok(caster_radius) =
    hit_radius.of_player(tables:, race_id: RaceId(caster.player.race_id))
    as "hit_radius.requirements fails the load when a playable race has no Race row"
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  WorldCast(
    caster:,
    caster_radius:,
    target_of: activate_target(
      tables:,
      picture: entered.shown,
      player: interaction.Player(
        race_id: entered.character.race_id,
        faction:,
        place: movement.place(state: entered.movement),
      ),
      now_ms: now.monotonic_ms,
      link_of: link_of(
        tables:,
        activations: connection_state.activations_of(session:),
        state: entered.cast,
        caster:,
      ),
    ),
  )
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
        scripts: session.settings.script_rows,
        entered:,
        link_of: link_of(
          tables:,
          activations: connection_state.activations_of(session:),
          state: entered.cast,
          caster:,
        ),
        now_ms: now.monotonic_ms,
      ),
      caster_radius:,
    )
  {
    Ok(effects) -> carry_cast(session:, now:, effects:)
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: cast_frame.describe(refusal),
      )
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
  scripts scripts: objective.ScriptRows,
  entered entered: world_entry.Entered,
  link_of link_of: fn(Int, creature2.Creature2, Int) -> activate.Link,
  now_ms now_ms: Int,
) -> fn(Int) -> Result(cast_state.UsedUnit, Nil) {
  let use_targets = objective.use_targets(log: quests, tables:, scripts:)
  fn(unit_id) {
    use one <- result.try(dict.get(picture, unit_id))
    let unit = unit_ref(entered:, unit_id:)
    let offered_to = fn(target, checklist_index) {
      use_targets(target, checklist_index, unit)
    }
    let link_of = fn(row, index) { link_of(unit_id, row, index) }
    case one {
      shown.ShownPlayer(..) -> Error(Nil)
      shown.ShownObject(place:, hit_radius:, ..) ->
        used_unit_at(
          tables:,
          one:,
          offered_to:,
          link_of:,
          alive: True,
          body: activate.Body(place:, radius: hit_radius),
        )
      shown.ShownCreature(path:, hit_radius:, alive:, ..) ->
        used_unit_at(
          tables:,
          one:,
          offered_to:,
          link_of:,
          alive:,
          body: activate.Body(
            place: creature_path.place_at(path:, now_ms:),
            radius: hit_radius,
          ),
        )
    }
  }
}

/// The unit `unit_id` of the player's current map run, as the quest log remembers a use of
/// it.
fn unit_ref(
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
) -> quest_log.UnitRef {
  quest_log.UnitRef(
    map: entered.map,
    incarnation: entered.incarnation,
    unit_id:,
  )
}

fn used_unit_at(
  tables tables: table_store.Tables,
  one one: shown.Shown,
  offered_to offered_to: fn(target_group.Unit, Int) -> Bool,
  link_of link_of: fn(creature2.Creature2, Int) -> activate.Link,
  alive alive: Bool,
  body body: activate.Body,
) -> Result(cast_state.UsedUnit, Nil) {
  use #(unit, checklist_index) <- result.try(shown.target_of(
    tables:,
    shown: one,
  ))
  use #(creature, link) <- result.map(creature_and_link(
    tables:,
    creature_id: unit.creature_id,
    checklist_index:,
    link_of:,
  ))
  cast_state.UsedUnit(
    creature_id: unit.creature_id.value,
    creature:,
    checklist_index:,
    link:,
    body:,
    alive:,
    offered: offered_to(unit, checklist_index),
  )
}

/// A shown unit's activate row and its link to the caster's objectives, or `Error(Nil)`
/// when its Creature2 row is not in the tables.
fn creature_and_link(
  tables tables: table_store.Tables,
  creature_id creature_id: Creature2Id,
  checklist_index checklist_index: Int,
  link_of link_of: fn(creature2.Creature2, Int) -> activate.Link,
) -> Result(#(activate.Creature, activate.Link), Nil) {
  use row <- result.map(creature2.get(tables:, id: creature_id))
  #(activate.creature_of(row:), link_of(row, checklist_index))
}

/// Whether the caster's quest log opens a creature's link to an objective, for the unit
/// `unit_id` that stands as the second unit of the creature's prerequisite
/// (genesis_prime/game/objective_link `of`).
fn link_of(
  tables tables: table_store.Tables,
  activations activations: activate.Activations,
  state state: cast_state.State,
  caster caster: cast_state.Caster,
) -> fn(Int, creature2.Creature2, Int) -> activate.Link {
  fn(unit_id, row, checklist_index) {
    objective_link.of(
      tables:,
      activations:,
      subject: cast_press.subject_for_use(
        cast: state,
        caster:,
        unit_id:,
        checklist_index:,
      ),
      quests: caster.quests,
      row:,
      checklist_index:,
    )
  }
}

/// Whether the player's quest log opens the link of the creature a go used, as the press
/// saw it (`link_of`).
fn projector_link(
  session session: Session,
  entered entered: world_entry.Entered,
  target target: target_group.Unit,
  unit_id unit_id: Int,
  checklist_index checklist_index: Int,
) -> activate.Link {
  let tables = session.settings.tables
  case creature2.get(tables:, id: target.creature_id) {
    Ok(row) ->
      link_of(
        tables:,
        activations: connection_state.activations_of(session:),
        state: entered.cast,
        caster: caster_of(tables:, entered:),
      )(unit_id, row, checklist_index)
    Error(Nil) -> activate.NoLink
  }
}

/// What the unit a right-click names is to the player, from the units its client shows:
/// a creature or static object with its creature's activate row, its body now (a creature
/// where its path puts it), whether it lives and whether the client offers it no use (in
/// combat, or hostile to the player), another player or nothing shown.
fn activate_target(
  tables tables: table_store.Tables,
  picture picture: shown.Picture,
  player player: interaction.Player,
  now_ms now_ms: Int,
  link_of link_of: fn(Int, creature2.Creature2, Int) -> activate.Link,
) -> fn(Int) -> activate.Target {
  fn(unit_id) {
    case dict.get(picture, unit_id) {
      Error(Nil) -> activate.Unseen
      Ok(shown.ShownPlayer(..)) -> activate.AnotherPlayer
      Ok(shown.ShownCreature(
        creature_id:,
        checklist_index:,
        path:,
        alive:,
        hit_radius:,
        hostile_to:,
        in_combat:,
        held:,
        unit_states:,
        ..,
      )) ->
        usable(
          tables:,
          creature_id:,
          unit_id:,
          checklist_index:,
          link_of:,
          body: activate.Body(
            place: creature_path.place_at(path:, now_ms:),
            radius: hit_radius,
          ),
          alive:,
          in_combat:,
          held: list.map(held, fn(held) { held.state }),
          unit_states: list.map(unit_states, fn(held) { held.state }),
          withheld: case in_combat {
            True -> Some(activate.InCombat)
            False ->
              case interaction.hostile_to_player(player:, hostile_to:) {
                True -> Some(activate.HostileToPlayer)
                False -> None
              }
          },
        )
      Ok(shown.ShownObject(
        creature_id:,
        checklist_index:,
        place:,
        hit_radius:,
        ..,
      )) ->
        usable(
          tables:,
          creature_id:,
          unit_id:,
          checklist_index:,
          link_of:,
          body: activate.Body(place:, radius: hit_radius),
          alive: True,
          in_combat: False,
          held: [],
          unit_states: [],
          withheld: None,
        )
    }
  }
}

/// A shown creature or object as an activate target; one whose Creature2 row is not in
/// the tables is as good as unseen, as a use of it is (`used_unit`).
fn usable(
  tables tables: table_store.Tables,
  creature_id creature_id: Creature2Id,
  unit_id unit_id: Int,
  checklist_index checklist_index: Int,
  link_of link_of: fn(Int, creature2.Creature2, Int) -> activate.Link,
  body body: activate.Body,
  alive alive: Bool,
  in_combat in_combat: Bool,
  held held: List(CrowdControlState),
  unit_states unit_states: List(Int),
  withheld withheld: Option(activate.Withheld),
) -> activate.Target {
  case
    creature_and_link(
      tables:,
      creature_id:,
      checklist_index:,
      link_of: fn(row, index) { link_of(unit_id, row, index) },
    )
  {
    Ok(#(creature, link)) ->
      activate.Usable(
        creature_id: creature_id.value,
        creature:,
        checklist_index:,
        link:,
        body:,
        alive:,
        in_combat:,
        held:,
        unit_states:,
        withheld:,
      )
    Error(Nil) -> activate.Unseen
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
  round_carried(session:, now:, updated:, effects:)
}

/// A healed player's answer to a heal this player told in this stay (`stay_sent`): filed
/// as a creature's is, so the round that closes is the cast rule's `went`
/// (genesis_prime/game/strike `player_answered`).
pub fn player_taken(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  answered answered: PlayerAnswered,
) -> client_connection.Handled(Session) {
  let #(updated, effects) =
    strike.player_answered(strike: entered.strike, answer: answered, now:)
  round_carried(session:, now:, updated:, effects:)
}

/// The events of a blow on the ally `event.unit_id` that its connection told this caster
/// (`PlayerTell.Event`): they are pending as events of that ally, and the pass that draws and
/// fires follows (`raised`), so the entries the cast holds on that ally take their chance words
/// from this connection's seed. A tell for a stay this connection has left is dropped by the stay
/// fence (`connection.stay_sent`), and one for an ally no entry is held on draws and fires nothing.
pub fn ally_event_taken(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  event event: PlayerEvent,
) -> client_connection.Handled(Session) {
  let #(session, fired) =
    raised(
      session: with_cast(
        session:,
        cast: cast.ally_events_raised(
          cast: entered.cast,
          unit_id: event.unit_id,
          events: event.events,
        ),
      ),
      now:,
    )
  Continue(session, fired)
}

/// The strike state an answer left and the effects it asked for, carried out in order.
fn round_carried(
  session session: Session,
  now now: Now,
  updated updated: strike.State,
  effects effects: List(strike.Effect),
) -> client_connection.Handled(Session) {
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
          case cast_persist.persists(cast: entered.cast) {
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

/// What an input decided, with each creature told what the player's casts now hold on it
/// (`creature_view.compared`) after the input's own effects. It runs at the end of each
/// input of a player in the world that goes on, an ask's status included (an input held or
/// dropped while an ask is out), and keeps the compare's record in whatever status the player
/// is held in, so a change is told once: the answer's handler reads the record back from the
/// status. An input that ends in an ask is told at the end of the next input that goes on,
/// the compare being against what each creature was told.
pub fn creatures_told(
  handled handled: client_connection.Handled(Session),
) -> client_connection.Handled(Session) {
  case handled {
    Continue(session:, effects:) ->
      case connection_state.entered_of(session.status) {
        Some(entered) -> {
          let #(compared, told) = creatures_settled(session:, entered:)
          Continue(
            connection_state.with_entered_in_any_status(
              session:,
              change: fn(entered) {
                world_entry.Entered(..entered, cast: compared)
              },
            ),
            list.append(effects, told),
          )
        }
        None -> handled
      }
    client_connection.Asking(..) | client_connection.Done(..) -> handled
  }
}

/// The player's cast state compared against what the creatures were told
/// (`creature_view.compared`), and the tell of each change.
pub fn creatures_settled(
  session session: Session,
  entered entered: world_entry.Entered,
) -> #(cast_state.State, List(Effect(ConnectionEffect(Request)))) {
  let #(compared, changes) =
    creature_view.compared(cast: entered.cast, caster_unit_id: entered.unit_id)
  let connection = client_connection.connection(session.link)
  #(
    compared,
    list.map(changes, fn(change) {
      case change {
        creature_view.ViewSet(unit_id:, life:, struck_at_ms:, view:) ->
          tells_the_creature(
            entered:,
            unit_id:,
            life:,
            request: client_connection.TellCastView(
              connection:,
              change: client_connection.ViewSet(view:, struck_at_ms:),
            ),
          )
        creature_view.ViewEnds(unit_id:, life:, cast_id:) ->
          tells_the_creature(
            entered:,
            unit_id:,
            life:,
            request: client_connection.TellCastView(
              connection:,
              change: client_connection.ViewEnds(cast_id:),
            ),
          )
      }
    }),
  )
}

/// The player as its cast rule takes it: who it is, where it stands, what it
/// holds, who sees it, whether it is dead or in combat and its health and shield.
pub fn caster_of(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
) -> cast_state.Caster {
  let life = entered.life
  let level = entered.character.level
  cast_state.Caster(
    unit_id: entered.unit_id,
    place: movement.place(entered.movement),
    abilities: ability_book.bag(loadout: entered.loadout, level:),
    book: ability_book.book(tables:, loadout: entered.loadout, level:),
    surge_spell: spell_surge.spell(tables:),
    weapon: entered.gear.weapon,
    audience: connection_state.viewer_connections(entered:),
    players_in_sight: player_address.in_sight(
      viewers: entered.viewers,
      picture: entered.shown,
    ),
    other_players: player_address.states_in_sight(
      viewers: entered.viewers,
      picture: entered.shown,
    ),
    hit_radius: hit_radius.of_playing(
      tables:,
      race_id: entered.character.race_id,
    ),
    pvp_flagged: int.bitwise_and(entered.unit.pvp_flags, 1) == 1,
    group_id: entered.unit.group_id,
    dead: player_life.state(life:) == player_life.Dead,
    resources: entered.resources,
    in_combat: player_life.in_combat(life:),
    life_vitals: dict.from_list([
      #(
        cast_state.health_vital,
        prerequisite.Vital(
          current: int.to_float(player_life.health(life:)),
          maximum: int.to_float(player_life.max_health(life:)),
        ),
      ),
      #(
        cast_state.shield_vital,
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
    stats: stats_of(tables:, entered:),
    vitals: player_life.vitals(life:),
    heal_scaling: heal_split.scaling_of(properties: entered.properties),
    quests: entered.quests,
    player: prerequisite_player.of(tables:, entered:),
    checker: prerequisite_player.checker_of(entered:),
  )
}

/// What the player's damage and heals read of it: its level, its Assault and Support
/// Rating, its attributes and the passed-in value at its level.
fn stats_of(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
) -> damage.Attacker {
  let level = connection_state.level_of(entered:)
  damage.attacker_of(
    properties: entered.properties,
    level:,
    passed_in: passed_in_value.of_level(tables:, level:),
  )
}

/// The session with the player's cast state replaced.
pub fn with_cast(
  session session: Session,
  cast cast: cast_state.State,
) -> Session {
  connection_state.with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, cast:)
  })
}

/// The spell the player's standing casts should hold from the loadout's innate passive, as
/// its plan with no item, and a warning when the plans lack its Spell4Base, which leaves it out
/// of the list. The warning is also written at each regear, not only at a join; it cannot be
/// reached, since the load fails without a plan for every class's passive.
pub fn standing_wanted(
  entered entered: world_entry.Entered,
  plans plans: spell_plan.Plans,
) -> #(List(cast_state.Standing), List(cast_state.Effect)) {
  case entered.loadout.innate {
    Some(innate.Innate(passive: Some(passive), ..)) ->
      case spell_plan.in_plans(plans:, base: passive.spell4_base_id) {
        Ok(spell) -> #([cast_state.Standing(spell:, from: None)], [])
        Error(Nil) -> #([], [
          cast_state.Log(
            level: LogWarning,
            text: "the innate passive with Spell4Base "
              <> int.to_string(passive.spell4_base_id.value)
              <> " is in no plan, so it is not started",
          ),
        ])
      }
    Some(innate.Innate(passive: None, ..)) | None -> #([], [])
  }
}

/// The spells the worn items' equip spells put on the player, in worn order, each as its
/// plan from `equip_plans` (`spell_plan.standing_plans`) with the item it is worn from, and the
/// Spell4 ids of those the plans leave out, which the cast rule logs once
/// (`cast.standing_unbuilt`).
pub fn worn_wanted(
  gear gear: gear.Gear,
  tables tables: table_store.Tables,
  equip_plans equip_plans: dict.Dict(Int, spell_plan.Spell),
) -> #(List(cast_state.Standing), List(Int)) {
  wanted_from(
    sources: gear.equip_spells,
    plans: equip_plans,
    spell4_id_of: fn(worn) { worn.spell4_id },
    from: fn(worn) { worn_pressed_from(tables:, item2_id: worn.item2_id) },
  )
}

/// The spells the AMPs of the active set put on the player, in AMP id order, each as its plan
/// from `amp_plans` (`spell_plan.amp_plans`) with no item, and the Spell4 ids of those the plans
/// leave out, which the cast rule logs once (`cast.standing_unbuilt`). Only the active set stands
/// (`limited_action_set.first_set`): the set a player picks into and the only one the server
/// judges. A held AMP has a row: the entry drops a stored list the check refuses, which holds
/// an AMP with no row (`limited_action_set.entering`), and a pick is checked against the rows
/// (`amp_spec.check`).
fn amp_wanted(
  entered entered: world_entry.Entered,
  tables tables: table_store.Tables,
  amp_plans amp_plans: dict.Dict(Int, spell_plan.Spell),
) -> #(List(cast_state.Standing), List(Int)) {
  wanted_from(
    sources: list.map(
      limited_action_set.held_amps(
        saved: entered.action_sets,
        set: limited_action_set.set_number(set: limited_action_set.first_set()),
      ),
      fn(id) {
        let assert Ok(row) = eldan_augmentation.get(tables:, id:)
          as "a held AMP has an EldanAugmentation row: the entry and the pick check it"
        row
      },
    ),
    plans: amp_plans,
    spell4_id_of: fn(amp) { amp.spell4_id_augment },
    from: fn(_) { None },
  )
}

/// The sources whose spell the plans hold, as standing spells in the sources' order with what
/// each is pressed from, and the Spell4 ids of the sources whose spell the plans leave out.
fn wanted_from(
  sources sources: List(source),
  plans plans: dict.Dict(Int, spell_plan.Spell),
  spell4_id_of spell4_id_of: fn(source) -> Int,
  from from: fn(source) -> Option(cast_state.PressedFrom),
) -> #(List(cast_state.Standing), List(Int)) {
  let #(planned, left_out) =
    list.partition(sources, fn(source) {
      dict.has_key(plans, spell4_id_of(source))
    })
  #(
    list.filter_map(planned, fn(source) {
      dict.get(plans, spell4_id_of(source))
      |> result.map(fn(spell) {
        cast_state.Standing(spell:, from: from(source))
      })
    }),
    list.map(left_out, spell4_id_of),
  )
}

/// What a worn item's standing spell is pressed from: the item's level and the passed-in value
/// at it, which the cast tells and its children read. An item with Item2.flags bit 3 has none:
/// the client's curve level for it is the builder's scaling level, not Item2.powerLevel
/// (`0x14040d060`), which the server reads at the wearer's level (`item_property`), so its
/// cast tells 0, as a cast with no item does, and its children read the player's own value.
fn worn_pressed_from(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
) -> Option(cast_state.PressedFrom) {
  let assert Ok(row) = item2.get(tables:, id: item2_id)
    as "a worn item's Item2 row is in the tables: the gear read it"
  case item_property.is_level_scaled(flags: row.flags) {
    True -> None
    False ->
      Some(cast_state.Item(
        item_level: row.power_level,
        passed_in: passed_in_value.of_item(tables:, item2_id:),
      ))
  }
}

/// What the player's standing casts should be: the spells in the order they start, the
/// warnings the innate passive's lookup gives, and the Spell4 ids of the worn items' and the
/// AMPs' spells the plans leave out.
pub type Wanted {
  Wanted(
    standing: List(cast_state.Standing),
    warnings: List(cast_state.Effect),
    left_out: List(Int),
  )
}

/// The player's standing casts: the innate passive first, then the spells of the worn items,
/// then the spells of the AMPs the active set holds in AMP id order (`standing_wanted`,
/// `worn_wanted`, `amp_wanted`).
pub fn wanted_of(
  entered entered: world_entry.Entered,
  tables tables: table_store.Tables,
  plans plans: spell_plan.Plans,
) -> Wanted {
  let #(innate, warnings) = standing_wanted(entered:, plans:)
  let #(worn, worn_left_out) =
    worn_wanted(
      gear: entered.gear,
      tables:,
      equip_plans: spell_plan.standing_plans(tables),
    )
  let #(amps, amps_left_out) =
    amp_wanted(entered:, tables:, amp_plans: spell_plan.amp_plans(tables))
  Wanted(
    standing: list.flatten([innate, worn, amps]),
    warnings:,
    left_out: list.append(worn_left_out, amps_left_out),
  )
}

/// The player's standing casts made what `wanted_of` lists: the cast rule logs each spell
/// the plans leave out, starts each wanted spell that does not stand and ends each standing
/// spell no longer wanted (`cast.standing_changed`), and its effects are carried out as any
/// cast's are.
pub fn standing_changed(
  session session: Session,
  now now: Now,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let assert Some(entered) = connection_state.entered_of(session.status)
    as "the standing spells change while the connection holds a player"
  let wanted =
    wanted_of(
      entered:,
      tables: session.settings.tables,
      plans: connection_state.plans_of(session:),
    )
  let #(logged, unbuilt) =
    cast.standing_unbuilt(cast: entered.cast, spell4_ids: wanted.left_out)
  let #(changed, decided) =
    cast.standing_changed(
      cast: logged,
      caster: caster_of(tables: session.settings.tables, entered:),
      wanted: wanted.standing,
      now:,
    )
  cast_effects(
    session: with_cast(session:, cast: changed),
    now:,
    effects: list.flatten([wanted.warnings, unbuilt, decided]),
  )
}

/// What the cast rule decided, carried out in order.
fn carry_cast(
  session session: Session,
  now now: Now,
  effects effects: List(cast_state.Effect),
) -> client_connection.Handled(Session) {
  let #(session, written) = cast_effects(session:, now:, effects:)
  Continue(session, written)
}

/// The unit a go's use counts for: a creature or object the player still sees, unless it
/// lived at the press and is shown dead now (the client cancels the cast of a target that
/// dies during it, and not one whose target was dead at the press), or `Error(Nil)`.
fn counted_target(
  tables tables: table_store.Tables,
  picture picture: shown.Picture,
  unit_id unit_id: Int,
  alive_at_press alive_at_press: Bool,
) -> Result(#(target_group.Unit, Int), Nil) {
  use one <- result.try(dict.get(picture, unit_id))
  case one {
    shown.ShownCreature(alive: False, ..) if alive_at_press -> Error(Nil)
    shown.ShownCreature(..) | shown.ShownPlayer(..) | shown.ShownObject(..) ->
      shown.target_of(tables:, shown: one)
  }
}

/// The unit a go's use counts for, with the objective event of that use: a creature or object
/// the player still sees (`counted_target`), as `Activated` counts it.
fn use_event(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  alive_at_press alive_at_press: Bool,
  by_item by_item: Bool,
) -> Result(#(target_group.Unit, Int, objective.Event), Nil) {
  counted_target(tables:, picture: entered.shown, unit_id:, alive_at_press:)
  |> result.map(fn(counted) {
    #(
      counted.0,
      counted.1,
      objective.Used(
        target: counted.0,
        checklist_index: counted.1,
        unit: unit_ref(entered:, unit_id:),
        by_item:,
      ),
    )
  })
}

/// The objective event of a quest button's cast of the spell at the unit the press named, if it
/// took one: none when that unit is no longer counted (`counted_target`), as `ShortcutCast`
/// counts it.
fn cast_event(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
  spell4_id spell4_id: Int,
  target target: Option(cast_state.PressedAt),
) -> Result(objective.Event, Nil) {
  case target {
    None -> Ok(objective.Cast(spell4_id: Spell4Id(spell4_id), target: None))
    Some(cast_state.PressedAt(unit_id:, alive_at_press:)) ->
      counted_target(tables:, picture: entered.shown, unit_id:, alive_at_press:)
      |> result.map(fn(counted) {
        objective.Cast(
          spell4_id: Spell4Id(spell4_id),
          target: Some(objective.CastTarget(
            unit: counted.0,
            ref: unit_ref(entered:, unit_id:),
          )),
        )
      })
  }
}

/// The event of the use or cast a QuestAdvanceObjective row was applied with
/// (`cast_state.AdvanceWith`), as `Activated` and `ShortcutCast` count it, or none when it
/// counted nothing. A unit that has left the picture since the press counts as it did at its
/// go, since a delayed row comes after it: a use that counts a unit new to an objective
/// releases it, so the unit of a delayed row is no longer shown. A use is then rebuilt from the
/// Creature2 row, which names the creature (the objectives a use counts name the creature, not
/// its faction), and a cast at the unit as a cast of the spell with no unit, which an objective
/// of the spell counts all the same. A unit still shown is judged as at the go.
fn advance_event(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
  with with: cast_state.AdvanceWith,
) -> Option(objective.Event) {
  case with {
    cast_state.WithNothing -> None
    cast_state.WithUse(unit_id:, creature_id:, alive_at_press:, by_item:) ->
      case dict.has_key(entered.shown, unit_id) {
        True ->
          use_event(tables:, entered:, unit_id:, alive_at_press:, by_item:)
          |> result.map(fn(used) { used.2 })
          |> option.from_result
        False ->
          creature2.get(tables:, id: Creature2Id(creature_id))
          |> result.map(fn(row) {
            objective.Used(
              target: target_group.Unit(
                creature_id: Creature2Id(creature_id),
                faction_id: Faction2Id(0),
                unit_race_id: creature2.unit_race_id(row),
              ),
              checklist_index: 0,
              unit: unit_ref(entered:, unit_id:),
              by_item:,
            )
          })
          |> option.from_result
      }
    cast_state.WithCast(spell4_id:, target: Some(pressed)) ->
      case dict.has_key(entered.shown, pressed.unit_id) {
        True ->
          cast_event(tables:, entered:, spell4_id:, target: Some(pressed))
          |> option.from_result
        False ->
          Some(objective.Cast(spell4_id: Spell4Id(spell4_id), target: None))
      }
    cast_state.WithCast(spell4_id:, target: None) ->
      cast_event(tables:, entered:, spell4_id:, target: None)
      |> option.from_result
  }
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
  effects effects: List(cast_state.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  carried_out(session:, now:, effects:)
  |> procs_fired(now:)
}

/// The held procs fire for the events raised outside a cast rule's step: a change of the
/// class resource (genesis_prime/game/connection/resource) or the start of a move
/// (`moved`), already pending in the player's cast state. With nothing pending it draws
/// nothing.
pub fn raised(
  session session: Session,
  now now: Now,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  procs_fired(done: #(session, []), now:)
}

/// The held procs fire for a start of moving: the player's movement is not moving in `from`,
/// the movement before a message of the client's, and is moving in the session now
/// (`movement.started_moving`). Nothing is raised, and nothing drawn, when it is not.
pub fn moved(
  session session: Session,
  now now: Now,
  from from: movement.State,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    Some(entered) ->
      case movement.started_moving(from:, to: entered.movement) {
        True ->
          raised(
            session: with_cast(
              session:,
              cast: cast.raised(cast: entered.cast, facts: [
                cast_state.StartedMoving,
              ]),
            ),
            now:,
          )
        False -> #(session, [])
      }
    None -> #(session, [])
  }
}

/// What the move `moved` of an activation writes first: its 0x83c stops the cast the activation
/// made (`opcode.0x83c`), so that cast's end (`cast.activation_stopped`) is carried out before the
/// move's frames. Nothing when the activation moved no one or made no cast.
fn stopped_by_move(
  session session: Session,
  now now: Now,
  cast_id cast_id: Option(Int),
  moved moved: List(Effect(ConnectionEffect(Request))),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case moved, cast_id, connection_state.entered_of(session.status) {
    [_, ..], Some(cast_id), Some(entered) -> {
      let #(stopped, effects) =
        cast.activation_stopped(cast: entered.cast, cast_id:)
      carried_out(session: with_cast(session:, cast: stopped), now:, effects:)
    }
    [], _, _ | _, None, _ | _, _, None -> #(session, [])
  }
}

/// The player's current cast stopped by a placement the server made, as the client's 0x83c
/// stops it (`cast.stopped_by_placement`): the cast's end is written before the placement's
/// frames. A player with no current cast, or none in the world, changes nothing.
pub fn stopped_by_placement(
  session session: Session,
  now now: Now,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    Some(entered) -> {
      let #(stopped, effects) =
        cast.stopped_by_placement(
          cast: entered.cast,
          caster: caster_of(tables: session.settings.tables, entered:),
          now:,
        )
      cast_effects(session: with_cast(session:, cast: stopped), now:, effects:)
    }
    None -> #(session, [])
  }
}

/// The effects carried out in order, with no proc fired: a strike's own results are carried
/// out inside the effect that asked for them, and the pending events wait for the input's
/// effects to end (`cast_effects`).
fn carried_out(
  session session: Session,
  now now: Now,
  effects effects: List(cast_state.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  list.fold(effects, #(session, []), fn(so_far, effect) {
    let #(session, done) = so_far
    let #(session, more) = case
      effect,
      connection_state.entered_of(session.status)
    {
      cast_state.Send(frame:), _ -> #(session, [
        connection_state.to_client(session, frame),
      ])
      cast_state.Tell(to:, news:), Some(entered) -> #(
        session,
        connection_state.news_to_connection(entered:, connection: to, news:),
      )
      cast_state.Tell(..), None -> #(session, [])
      cast_state.StartTimer(timer:, after_ms:), _ -> #(session, [
        OwnEffect(StartTimer(timer:, after_ms:)),
      ])
      cast_state.CancelTimer(timer:), _ -> #(session, [
        OwnEffect(CancelTimer(timer:)),
      ])
      cast_state.Log(level:, text:), _ -> #(session, [
        connection_state.log(session:, level:, text:),
      ])
      cast_state.Strike(asked:), Some(entered) ->
        strike_begins(session:, now:, entered:, asked:)
      cast_state.Strike(..), None -> #(session, [])
      cast_state.TickStrike(asked:), Some(entered) ->
        tick_strike_begins(session:, now:, entered:, asked:)
      cast_state.TickStrike(..), None -> #(session, [])
      cast_state.FindProxyTickUnits(asked:), Some(entered) ->
        proxy_tick_units_found(session:, now:, entered:, asked:)
      cast_state.FindProxyTickUnits(..), None -> #(session, [])
      cast_state.Activated(unit_id:, alive_at_press:, by_item:, cast_id:, ..),
        Some(entered)
      ->
        // The go is raised even when the unit has left the picture or died, and a use
        // of a creature the player no longer sees, or that died since the press, counts
        // for no objective (`SetUnitDeathState` 0x14045e740 cancels the player's current
        // cast that targets a unit when the unit's death state is set).
        case
          use_event(
            tables: session.settings.tables,
            entered:,
            unit_id:,
            alive_at_press:,
            by_item:,
          )
        {
          Ok(#(target, checklist_index, event)) -> {
            // The projector's link is read before the count, which can close the
            // objective it opens; the move follows the count's writes.
            let link =
              projector_link(
                session:,
                entered:,
                target:,
                unit_id:,
                checklist_index:,
              )
            let #(session, counted) =
              connection_objective.used(session:, now:, target:, event:)
            let #(session, moved) =
              connection_projector.moved(
                session:,
                now:,
                creature_id: target.creature_id,
                link:,
              )
            let #(session, stopped) =
              stopped_by_move(session:, now:, cast_id:, moved:)
            #(session, list.flatten([counted, stopped, moved]))
          }
          Error(Nil) -> #(session, [])
        }
      cast_state.Activated(..), None -> #(session, [])
      cast_state.ShortcutCast(spell4_id:, target:), Some(entered) ->
        // A cast at a unit the player no longer sees, or that died since the press,
        // counts for no objective, as a use does.
        case
          cast_event(
            tables: session.settings.tables,
            entered:,
            spell4_id:,
            target:,
          )
        {
          Ok(event) -> connection_objective.counted(session:, now:, event:)
          Error(Nil) -> #(session, [])
        }
      cast_state.ShortcutCast(..), None -> #(session, [])
      cast_state.QuestAdvanced(advances:, with:), Some(entered) ->
        connection_objective.advanced(
          session:,
          now:,
          advances:,
          with: advance_event(tables: session.settings.tables, entered:, with:),
        )
      cast_state.QuestAdvanced(..), None -> #(session, [])
      cast_state.Pay(payments:), _ ->
        connection_resource.paid(session:, payments:)
      cast_state.Gain(gains:), _ -> connection_resource.gained(session:, gains:)
      cast_state.CasterChangeStarts(
        source:,
        change: cast_state.HeldChange(change:),
      ),
        _
      ->
        connection_landing.started(
          session:,
          now:,
          source:,
          change: held_changes.Applies(change:),
        )
      cast_state.CasterChangeStarts(
        change: cast_state.Heal(vital:, amount:),
        ..,
      ),
        _
      -> connection_healing.healed(session:, now:, vital:, amount:)
      cast_state.CasterChangeStarts(source:, change: cast_state.Look(disguise:)),
        _
      -> connection_look.started(session:, source:, disguise:)
      cast_state.CasterChangeEnds(source:), _ ->
        connection_landing.ended(session:, now:, source:)
      cast_state.OtherPlayerChangeStarts(
        address:,
        source:,
        change:,
        sight:,
        spell4_id:,
        effect:,
      ),
        Some(entered)
      -> #(session, [
        tells_the_player(
          address:,
          change: held_changes.PlayerChangeStarts(
            from: client_connection.connection(session.link),
            from_stay: entered.stay,
            source:,
            change:,
            sight:,
            spell4_id:,
            effect:,
          ),
        ),
      ])
      cast_state.OtherPlayerChangeEnds(address:, source:), Some(_) -> #(
        session,
        [
          tells_the_player(
            address:,
            change: held_changes.PlayerChangeEnds(
              from: client_connection.connection(session.link),
              source:,
            ),
          ),
        ],
      )
      cast_state.OtherPlayerCastWent(address:, cast_id:, audience:), Some(_) -> #(
        session,
        [
          tells_the_player(
            address:,
            change: held_changes.PlayerCastWent(
              from: client_connection.connection(session.link),
              cast_id:,
              audience:,
            ),
          ),
        ],
      )
      cast_state.OtherPlayerChangeStarts(..), None
      | cast_state.OtherPlayerChangeEnds(..), None
      | cast_state.OtherPlayerCastWent(..), None
      -> #(session, [])
      cast_state.StealthChanged(stealthed:), Some(entered) -> #(
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
      cast_state.StealthChanged(..), None -> #(session, [])
      cast_state.TargetChangeStarts(
        unit_id:,
        life:,
        struck_at_ms:,
        source:,
        modifier:,
      ),
        Some(entered)
      -> #(session, [
        tells_the_creature(
          entered:,
          unit_id:,
          life:,
          request: client_connection.TellTargetChange(
            connection: client_connection.connection(session.link),
            change: client_connection.ChangeStarts(
              source:,
              modifier:,
              struck_at_ms:,
            ),
          ),
        ),
      ])
      cast_state.TargetChangeStarts(..), None -> #(session, [])
      cast_state.TargetChangeEnds(unit_id:, life:, source:), Some(entered) -> #(
        session,
        [
          tells_the_creature(
            entered:,
            unit_id:,
            life:,
            request: client_connection.TellTargetChange(
              connection: client_connection.connection(session.link),
              change: client_connection.ChangeEnds(source:),
            ),
          ),
        ],
      )
      cast_state.TargetChangeEnds(..), None -> #(session, [])
      cast_state.ForcedMoveStarts(unit_id:, life:, struck_at_ms:, move:),
        Some(entered)
      -> {
        let #(session, tell) =
          creature_thrown(
            session:,
            entered:,
            unit_id:,
            life:,
            struck_at_ms:,
            move:,
          )
        #(session, [tell])
      }
      cast_state.ForcedMoveStarts(..), None -> #(session, [])
      cast_state.CreatureDespawns(
        unit_id:,
        life:,
        struck_at_ms:,
        went_at_ms:,
        delay_ms:,
      ),
        Some(entered)
      -> #(session, [
        creature_despawned(
          entered:,
          unit_id:,
          life:,
          struck_at_ms:,
          went_at_ms:,
          delay_ms:,
        ),
      ])
      cast_state.CreatureDespawns(..), None -> #(session, [])
      cast_state.CreatureHoldsUnitStates(
        unit_id:,
        life:,
        struck_at_ms:,
        went_at_ms:,
        rows:,
      ),
        Some(entered)
      -> #(session, [
        creature_holds_unit_states(
          entered:,
          unit_id:,
          life:,
          struck_at_ms:,
          went_at_ms:,
          rows:,
        ),
      ])
      cast_state.CreatureHoldsUnitStates(..), None -> #(session, [])
      cast_state.CreatureControlsEnd(unit_id:, life:, cast_id:), Some(entered)
      -> #(session, [
        tells_the_creature(
          entered:,
          unit_id:,
          life:,
          request: client_connection.TellTargetChange(
            connection: client_connection.connection(session.link),
            change: client_connection.ControlsEnd(cast_id:),
          ),
        ),
      ])
      cast_state.CreatureControlsEnd(..), None -> #(session, [])
    }
    #(session, list.append(done, more))
  })
}

/// The held procs fire for the events the input raised (genesis_prime/game/cast
/// `State.pending`), after the input's own effects: the connection draws what the pending
/// events need from its seed (`cast_proc.proc_draws_needed`: the chance words first, then the
/// gate rolls) and gives the rule the poses, checklist indexes and kinds of the units the
/// events name that its picture holds, then carries out the effects of the fires, which end
/// in the same pass for what they raise. A fire's own go is a later input, so the passes end:
/// an input with nothing pending draws nothing and makes no second call.
fn procs_fired(
  done done: #(Session, List(Effect(ConnectionEffect(Request)))),
  now now: Now,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(session, written) = done
  let pending = case connection_state.entered_of(session.status) {
    Some(entered) ->
      case cast_proc.has_pending(cast: entered.cast) {
        True -> Some(entered)
        False -> None
      }
    None -> None
  }
  case pending {
    Some(entered) -> {
      let #(words, rolls) = cast_proc.proc_draws_needed(cast: entered.cast)
      let #(link, bytes) =
        client_connection.draw(
          session.link,
          words * proc_word_bytes + rolls * prerequisite.roll_bytes,
        )
      let assert Ok(word_bytes) =
        bit_array.slice(bytes, 0, words * proc_word_bytes)
        as "the draw is as long as the words it is to give"
      let assert Ok(roll_bytes) =
        bit_array.slice(
          bytes,
          words * proc_word_bytes,
          rolls * prerequisite.roll_bytes,
        )
        as "the draw is as long as the rolls it is to give"
      let unit_ids = cast_proc.pending_units(cast: entered.cast)
      let #(updated, fired) =
        cast.procs_fire(
          cast: entered.cast,
          caster: caster_of(tables: session.settings.tables, entered:),
          now:,
          poses: shown.poses_of(
            picture: entered.shown,
            unit_ids:,
            now_ms: now.monotonic_ms,
            viewer: world_entry.viewer(entered:),
          ),
          indexes: shown.checklist_indexes_of(picture: entered.shown, unit_ids:),
          units: shown.first_units_of(
            picture: entered.shown,
            unit_ids:,
            caster_unit: entered.unit_id,
          ),
          draws: random.words(bytes: word_bytes),
          rolls: prerequisite.rolls_of(bytes: roll_bytes),
        )
      let #(session, more) =
        cast_effects(
          session: with_cast(session: Session(..session, link:), cast: updated),
          now:,
          effects: fired,
        )
      #(session, list.append(written, more))
    }
    None -> done
  }
}

/// The bytes of a chance draw: one 32-bit word (`random.words`).
const proc_word_bytes = 4

/// The tell `request` to the creature `unit_id` of `life`, in the run of the player's
/// map, through the creature registry with no watch, as a strike's tell goes.
/// The change `change` told to the connection of the player `address` names, for the stay
/// it names, through the registry as a strike's tell goes: the player's connection applies
/// it and holds it for this connection.
fn tells_the_player(
  address address: player_address.PlayerAddress,
  change change: held_changes.PlayerChange,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Connection(connection: address.connection),
    request: client_connection.TellPlayer(
      stay: address.stay,
      tell: client_connection.Change(change:),
    ),
  ))
}

fn tells_the_creature(
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  life life: Int,
  request request: Request,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Creature(
      map: entered.map,
      incarnation: entered.incarnation,
      unit_id:,
      life:,
    ),
    request:,
  ))
}

/// The throw of the creature `unit_id` of `life`, in the run of the player's map,
/// through the creature registry with no watch, as a strike's tell goes: the
/// connection draws `forced_move.draw_bytes` from its seed (`client_connection.draw`),
/// reads the two fractions (`forced_move.draws_of`), takes the player's place now and
/// race radius as the `Reference` and tells the creature `TellThrown` with
/// `struck_at_ms`. The session it returns holds the link after the draw.
fn creature_thrown(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  life life: Int,
  struck_at_ms struck_at_ms: Int,
  move move: forced_move.Move,
) -> #(Session, Effect(ConnectionEffect(Request))) {
  let #(link, bytes) =
    client_connection.draw(session.link, forced_move.draw_bytes)
  let reference =
    forced_move.Reference(
      place: movement.place(entered.movement),
      radius: hit_radius.of_playing(
        tables: session.settings.tables,
        race_id: entered.character.race_id,
      ),
    )
  #(
    Session(..session, link:),
    OwnEffect(step.Tell(
      to: step.Creature(
        map: entered.map,
        incarnation: entered.incarnation,
        unit_id:,
        life:,
      ),
      request: client_connection.TellThrown(
        throw: forced_move.Throw(
          move:,
          draws: forced_move.draws_of(bytes:),
          reference:,
        ),
        struck_at_ms:,
      ),
    )),
  )
}

/// The removal of the creature `unit_id` of `life`, in the run of the player's map, through
/// the creature registry with no watch, as a strike's tell goes: the connection tells the
/// creature `TellDespawn` with `delay_ms`, `struck_at_ms` and `went_at_ms`, and draws
/// nothing.
fn creature_despawned(
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  life life: Int,
  struck_at_ms struck_at_ms: Int,
  went_at_ms went_at_ms: Int,
  delay_ms delay_ms: Int,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Creature(
      map: entered.map,
      incarnation: entered.incarnation,
      unit_id:,
      life:,
    ),
    request: client_connection.TellDespawn(
      delay_ms:,
      struck_at_ms:,
      went_at_ms:,
    ),
  ))
}

/// The unit states the go holds on the creature `unit_id` of `life`, in the run of the player's
/// map, through the creature registry with no watch, as a removal goes: the connection tells
/// the creature `TellUnitStates` with the go's `rows` and the two times, and draws nothing.
fn creature_holds_unit_states(
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  life life: Int,
  struck_at_ms struck_at_ms: Int,
  went_at_ms went_at_ms: Int,
  rows rows: List(unit_state.Row),
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Creature(
      map: entered.map,
      incarnation: entered.incarnation,
      unit_id:,
      life:,
    ),
    request: client_connection.TellUnitStates(rows:, struck_at_ms:, went_at_ms:),
  ))
}

/// A go asked: its targets are selected from the units the client shows, the
/// caster's rolls are drawn from the connection's seed, and the strike rule begins
/// its round (genesis_prime/game/strike).
fn strike_begins(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  asked asked: cast_state.GoAsked,
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
  let unit_ids =
    list.append(
      list.map(selection.units, fn(aimed) { aimed.unit_id }),
      list.map(selection.players, fn(address) { address.unit_id }),
    )
  let gate =
    cast_tick.strike_gate(
      cast: entered.cast,
      caster: caster_of(tables:, entered:),
      poses: shown.poses_of(
        picture: entered.shown,
        unit_ids:,
        now_ms: now.monotonic_ms,
        viewer: world_entry.viewer(entered:),
      ),
      indexes: shown.checklist_indexes_of(picture: entered.shown, unit_ids:),
      units: shown.first_units_of(
        picture: entered.shown,
        unit_ids:,
        caster_unit: entered.unit_id,
      ),
    )
  let #(updated, effects) =
    strike.begin(
      strike: entered.strike,
      selection:,
      attacker:,
      formulas: rating.formulas(tables:),
      entropy:,
      gate:,
      now:,
    )
  strike_carried_out(
    session: with_strike(session: Session(..session, link:), strike: updated),
    now:,
    effects:,
  )
}

/// A tick asked: the strike rule begins its round of the one unit the tick lands on,
/// with the caster's rolls drawn from the connection's seed as a go's are.
fn tick_strike_begins(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  asked asked: cast_state.TickAsked,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(link, entropy) =
    client_connection.draw(session.link, strike.tick_entropy_needed(asked:))
  let #(updated, effects) =
    strike.begin_tick(
      strike: entered.strike,
      asked:,
      attacker: attacker_of(session:, entered:),
      formulas: rating.formulas(tables: session.settings.tables),
      entropy:,
      now:,
    )
  strike_carried_out(
    session: with_strike(session: Session(..session, link:), strike: updated),
    now:,
    effects:,
  )
}

/// A tick of a periodic Proxy aimed at the area asked for its units: they are selected
/// from the picture as it is now (`strike.select_proxy_tick`), the poses, checklist indexes
/// and first units its target gate reads are gathered as a go's are, and the cast rule
/// answers in the same input (`cast.proxy_tick_units_found`), its children carried out in
/// place of the ask. No creature is asked and nothing waits.
fn proxy_tick_units_found(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  asked asked: cast_state.ProxyTickAsked,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let tables = session.settings.tables
  let unit_ids =
    strike.select_proxy_tick(
      asked:,
      attacker: attacker_of(session:, entered:),
      picture: entered.shown,
      areas: spell_area.areas(tables:),
      now_ms: now.monotonic_ms,
    )
  let #(updated, effects) =
    cast.proxy_tick_units_found(
      cast: entered.cast,
      caster: caster_of(tables:, entered:),
      now:,
      asked:,
      units: unit_ids,
      poses: shown.poses_of(
        picture: entered.shown,
        unit_ids:,
        now_ms: now.monotonic_ms,
        viewer: world_entry.viewer(entered:),
      ),
      indexes: shown.checklist_indexes_of(picture: entered.shown, unit_ids:),
      first_units: shown.first_units_of(
        picture: entered.shown,
        unit_ids:,
        caster_unit: entered.unit_id,
      ),
    )
  carried_out(session: with_cast(session:, cast: updated), now:, effects:)
}

/// The player as its strikes take it: who it is, where it stands and faces, which
/// player faction it is of, what its damage reads of it (its level and its Assault and
/// Support Rating), its health and shield as they are now (a formula's caster kinds
/// read them) and its properties.
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
    hit_radius: hit_radius.of_playing(
      tables: session.settings.tables,
      race_id: entered.character.race_id,
    ),
    faction:,
    stats: stats_of(tables: session.settings.tables, entered:),
    vitals: player_life.vitals(life: entered.life),
    properties: entered.properties,
    players_in_sight: player_address.in_sight(
      viewers: entered.viewers,
      picture: entered.shown,
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
  strike_carried_out(session:, now:, effects:)
  |> procs_fired(now:)
}

/// The strike's effects carried out in order, with no proc fired: a strike begun inside the
/// effect that asked for it leaves the pending events to the input's end (`cast_effects`).
fn strike_carried_out(
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
      strike.TellPlayerStrike(address:, strike:), Some(_) -> #(session, [
        OwnEffect(step.Tell(
          to: step.Connection(connection: address.connection),
          request: client_connection.TellPlayer(
            stay: address.stay,
            tell: client_connection.Strike(strike:),
          ),
        )),
      ])
      strike.StartTimer(timer:, after_ms:), Some(_) -> #(session, [
        OwnEffect(StartTimer(timer:, after_ms:)),
      ])
      strike.CancelTimer(timer:), Some(_) -> #(session, [
        OwnEffect(CancelTimer(timer:)),
      ])
      strike.Went(asked:, struck:, gates_passed:), Some(entered) -> {
        let needed =
          cast_gate.rolls_needed(
            cast: entered.cast,
            caster: entered.unit_id,
            cast_id: asked.cast_id,
            phase: asked.phase,
            struck:,
          )
        let #(link, bytes) =
          client_connection.draw(session.link, needed * prerequisite.roll_bytes)
        // A row aimed at the primary target reaches it though no hit names it (it
        // deflected the strike), and its target apply prerequisite reads that unit too.
        let unit_ids =
          list.unique([asked.primary_target, ..cast_gate.hit_units(struck:)])
        let #(updated, cast_effects_out) =
          cast.went(
            cast: entered.cast,
            caster: caster_of(tables: session.settings.tables, entered:),
            now:,
            cast_id: asked.cast_id,
            phase: asked.phase,
            spell: result.map(
              spell_area.of_spell(
                areas: spell_area.areas(tables: session.settings.tables),
                spell4_id: asked.spell4_id,
              ),
              fn(area) { area.spell },
            ),
            struck:,
            gates_passed:,
            poses: shown.poses_of(
              picture: entered.shown,
              unit_ids:,
              now_ms: now.monotonic_ms,
              viewer: world_entry.viewer(entered:),
            ),
            indexes: shown.checklist_indexes_of(
              picture: entered.shown,
              unit_ids:,
            ),
            units: shown.first_units_of(
              picture: entered.shown,
              unit_ids:,
              caster_unit: entered.unit_id,
            ),
            rolls: prerequisite.rolls_of(bytes:),
          )
        carried_out(
          session: with_cast(session: Session(..session, link:), cast: updated),
          now:,
          effects: cast_effects_out,
        )
      }
      strike.Ticked(asked:, struck:), Some(entered) -> {
        let #(updated, cast_effects_out) =
          cast.ticked(
            cast: entered.cast,
            caster: caster_of(tables: session.settings.tables, entered:),
            now:,
            asked:,
            struck:,
          )
        carried_out(
          session: with_cast(session:, cast: updated),
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
    | client_connection.CastTicked(..)
    | client_connection.CastTargetsRemoved(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.CastFinished(..)
    | client_connection.CastInterrupted(..)
    | client_connection.CreatureMoved(..)
    | client_connection.CreaturePlaced(..)
    | client_connection.CreatureFaces(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..)
    | client_connection.CrowdControlApplied(..)
    | client_connection.CrowdControlEnded(..)
    | client_connection.UnitStateHeld(..)
    | client_connection.UnitStateEnded(..)
    | client_connection.InterruptArmor(..)
    | client_connection.Absorption(..)
    | client_connection.Level(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..)
    | client_connection.LookChanged(..)
    | client_connection.HeldCastEnded(..)
    | client_connection.HeldCastStarted(..) -> []
  }
}
