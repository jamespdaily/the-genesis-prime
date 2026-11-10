//// The frames the game connection's rule writes about units
//// (genesis_prime/game/connection): the player's own unit, its death and its
//// ghost, the combat log, a unit's shield, class resource, combat state, stealth, move,
//// path, creation and removal, and the leave of the world.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/cast
import genesis_prime/game/look
import genesis_prime/game/player_life
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/unit_properties
import genesis_prime/game/vendor.{type Vendor}
import genesis_prime/game/world_entry
import genesis_prime/message/buyback_list.{BuybackList}
import genesis_prime/message/combat_log.{CombatLog}
import genesis_prime/message/combat_log_death.{CombatLogDeath}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_resurrect.{CombatLogResurrect}
import genesis_prime/message/combat_log_stealth.{CombatLogStealth}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/float32
import genesis_prime/message/generic_error.{GenericError}
import genesis_prime/message/half_float
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/leave_world.{LeaveWorld}
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_path.{MovementPath}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/resurrection_window.{ResurrectionWindow}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_cc_state_applied.{UnitCcStateApplied}
import genesis_prime/message/unit_cc_state_ended.{UnitCcStateEnded}
import genesis_prime/message/unit_combat_state.{UnitCombatState}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_create_door
import genesis_prime/message/unit_create_ghost.{UnitCreateGhost}
import genesis_prime/message/unit_create_mailbox
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_create_portal
import genesis_prime/message/unit_create_static
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_death_state.{UnitDeathState}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_dialog_open.{UnitDialogOpen}
import genesis_prime/message/unit_float_stat_changed.{UnitFloatStatChanged}
import genesis_prime/message/unit_item_visuals_changed.{UnitItemVisualsChanged}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_properties_changed.{UnitPropertiesChanged}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/message/unit_stat_absorption.{UnitStatAbsorption}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/message/unit_stat_interrupt_armor.{UnitStatInterruptArmor}
import genesis_prime/message/unit_stat_level.{UnitStatLevel}
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/message/unit_stealth.{UnitStealth}
import genesis_prime/message/vendor_item.{VendorItem}
import genesis_prime/message/vendor_items.{type VendorItems, VendorItems}
import genesis_prime/message/vendor_price_slot.{VendorPriceSlot}
import genesis_prime/step.{type Now}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/map
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/static_object.{
  type Created, CreatedDoor, CreatedMailbox, CreatedPortal, CreatedWithChecklist,
}
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// A yes or no as the 1-bit value a message holds it in: 1 for yes.
pub fn bit(yes: Bool) -> Int {
  use <- bool.guard(when: yes, return: 1)
  0
}

/// 0x88c {unit, dead, 0, 0}: the unit died or came back (`opcode.0x88c`); the
/// 5-bit value is not read and the 32-bit one is used only for a unit under
/// client control that comes back, so both are 0.
pub fn death_state_frame(unit_id unit_id: Int, dead dead: Bool) -> Frame {
  let assert Ok(body) =
    unit_death_state.encode(UnitDeathState(
      unit_id:,
      dead: bit(dead),
      field_3: 0,
      field_4: 0,
    ))
    as "a unit id of 32 bits and the safe values fit the message (opcode.0x88c)"
  Frame(message_id: unit_death_state.message_id, body:)
}

/// 0x247 of type 22 when `died`, else 23, for the unit (`opcode.0x247.death`).
pub fn combat_log_frame(unit_id unit_id: Int, died died: Bool) -> Frame {
  let assert Ok(body) =
    combat_log.encode(
      CombatLog(entry: case died {
        True -> combat_log_entry.Death(CombatLogDeath(unit_id:))
        False -> combat_log_entry.Resurrect(CombatLogResurrect(unit_id:))
      }),
    )
    as "a unit id of 32 bits fits the entry"
  Frame(message_id: combat_log.message_id, body:)
}

/// The ghost's 0x262 of type 23 at `place`: the character's id, realm, name,
/// race, class, gender and title as the player's own 0x262 has them, the values
/// the client does not read 0 or empty, and the player's tail with the ghost's
/// position and rotation and no stat, since the client reads none of a ghost
/// (`0x140096970`, `opcode.0x262.ghost`).
fn ghost_created_frame(
  entered entered: world_entry.Entered,
  place place: Place,
  now now: Now,
) -> Frame {
  let player = appearance_at(entered:, place:, now:)
  let assert Ok(body) =
    unit_create_ghost.encode(UnitCreateGhost(
      unit_id: map.ghost_unit_id(unit_id: entered.unit_id),
      character_id: player.character_id,
      realm_id: player.realm_id,
      name: player.name,
      race_id: player.race_id,
      class_id: player.class_id,
      gender: player.gender,
      field_9: 0,
      field_10: "",
      field_11: 0,
      field_12: [],
      field_13: [],
      title_id: player.title_id,
      tail: UnitCreateTail(..player.tail, stats: []),
    ))
    as "the player's own 0x262 values fit the ghost's, whose fields are the same"
  Frame(message_id: unit_create_ghost.message_id, body:)
}

/// 0x1b3 with the ghost's id, dead or not, and the server's choices: no cost,
/// penalty, cooldown or forced release, and Wake Here and Holocrypt offered
/// (`player_life.offered_choices`, `opcode.0x1b3`).
fn resurrection_window_frame(
  ghost_unit_id ghost_unit_id: Int,
  dead dead: Bool,
) -> Frame {
  let assert Ok(body) =
    resurrection_window.encode(ResurrectionWindow(
      ghost_unit_id:,
      wake_here_cost: player_life.window_zero,
      death_penalty_ms: player_life.window_zero,
      dead: bit(dead),
      choices: player_life.offered_choices,
      caster_asked: 0,
      wake_here_cooldown_ms: player_life.window_zero,
      forced_release_ms: player_life.window_zero,
    ))
    as "a unit id, three 32-bit values, two bits, 8 bits and two 32-bit values fit the message"
  Frame(message_id: resurrection_window.message_id, body:)
}

/// The frame of a message about the player's own unit to its own client: 0x89a,
/// 0x938 of stat 20, 0x92f with no reason bit (`opcode.0x92f`: the bits name a
/// fall or a breath), and the death's: 0x88c, 0x247, the ghost's 0x262 at the
/// body's place, 0x1b3, the ghost's 0x355 and 0x636 for the ghost or the body.
pub fn own_unit_frame(
  entered entered: world_entry.Entered,
  now now: Now,
  written written: player_life.Written,
) -> Frame {
  let unit_id = entered.unit_id
  let ghost_unit_id = map.ghost_unit_id(unit_id:)
  case written {
    player_life.OwnCombatState(in_combat:) ->
      combat_state_frame(unit_id:, in_combat:)
    player_life.OwnShield(shield:) -> shield_frame(unit_id:, shield:)
    player_life.OwnInterruptArmor(armor:) ->
      interrupt_armor_frame(unit_id:, armor:)
    player_life.OwnAbsorption(absorption:) ->
      absorption_frame(unit_id:, absorption:)
    player_life.OwnHealth(health:) -> {
      let assert Ok(body) =
        player_health.encode(PlayerHealth(unit_id:, health:, reason_mask: 0))
        as "a unit id and a health of 32 bits and a mask of 18 fit the message"
      Frame(message_id: player_health.message_id, body:)
    }
    player_life.OwnDeathState(dead:) -> death_state_frame(unit_id:, dead:)
    player_life.OwnDeathLogged -> combat_log_frame(unit_id:, died: True)
    player_life.OwnCameBackLogged -> combat_log_frame(unit_id:, died: False)
    player_life.GhostCreated(place:) ->
      ghost_created_frame(entered:, place:, now:)
    player_life.OwnResurrectionWindow(dead:) ->
      resurrection_window_frame(ghost_unit_id:, dead:)
    player_life.GhostRemoved -> unit_removed_frame(unit_id: ghost_unit_id)
    player_life.ControlGiven(to: player_life.ControlGhost) ->
      world_entry.control_granted_frame(unit_id: ghost_unit_id)
    player_life.ControlGiven(to: player_life.ControlBody) ->
      world_entry.control_granted_frame(unit_id:)
  }
}

/// 0x89a: the unit is in a fight or out of one (`opcode.0x89a`).
pub fn combat_state_frame(
  unit_id unit_id: Int,
  in_combat in_combat: Bool,
) -> Frame {
  let assert Ok(body) =
    unit_combat_state.encode(UnitCombatState(
      unit_id:,
      in_combat: bit(in_combat),
    ))
    as "a unit id of 32 bits and a bit fit the message"
  Frame(message_id: unit_combat_state.message_id, body:)
}

/// 0x938 of stat 20: the unit's shield (`opcode.0x938`), the one stat the server
/// sends by it (`opcode.0x938.resource_stats`).
pub fn shield_frame(unit_id unit_id: Int, shield shield: Int) -> Frame {
  stat_frame(
    unit_id:,
    change: unit_stat_change.Shield(UnitStatShield(value: shield)),
  )
}

/// 0x1ac of kind 2, a kill: the client adds `gain` to its experience, with no rest
/// experience used and nothing of the third amount, and names the creature's unit
/// (`opcode.0x1ac`, `opcode.0x1ac.fields`, `CombatFloater.CodeEnumExpReason`).
pub fn experience_gained_frame(gain gain: Int, unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    experience_gained.encode(ExperienceGained(
      experience: gain,
      rest_experience_used: 0,
      bonus_experience: 0,
      source_kind: 2,
      source_unit_id: unit_id,
    ))
    as "an amount and a unit id of 32 bits and a kind of 32 bits fit the message"
  Frame(message_id: experience_gained.message_id, body:)
}

/// 0x938 of stat 10: the unit's level, which the client raises to the value
/// (`opcode.0x938`, `0x140029820`).
pub fn level_frame(unit_id unit_id: Int, level level: Int) -> Frame {
  stat_frame(
    unit_id:,
    change: unit_stat_change.Level(UnitStatLevel(value: level)),
  )
}

/// 0x938 of stat 21: the unit's current Interrupt Armor, which the client clamps to 0 and
/// the unit's maximum (`opcode.0x938.interrupt_armor`).
pub fn interrupt_armor_frame(unit_id unit_id: Int, armor armor: Int) -> Frame {
  stat_frame(
    unit_id:,
    change: unit_stat_change.InterruptArmor(UnitStatInterruptArmor(value: armor)),
  )
}

/// 0x938 of stat 22: the unit's absorption, the sum of its absorb pools, which the client
/// stores as sent (`opcode.0x938`, `0x14064fb40`).
pub fn absorption_frame(
  unit_id unit_id: Int,
  absorption absorption: Int,
) -> Frame {
  stat_frame(
    unit_id:,
    change: unit_stat_change.Absorption(UnitStatAbsorption(value: absorption)),
  )
}

/// 0x93a: the unit's `properties` changed, each with its base and its value, which the
/// client stores as sent (`opcode.0x93a`).
pub fn properties_changed_frame(
  unit_id unit_id: Int,
  properties properties: List(UnitProperty),
) -> Frame {
  let assert Ok(body) =
    unit_properties_changed.encode(UnitPropertiesChanged(unit_id:, properties:))
    as "a unit id of 32 bits and at most 197 entries, one for each property id, fit the message"
  Frame(message_id: unit_properties_changed.message_id, body:)
}

fn stat_frame(
  unit_id unit_id: Int,
  change change: unit_stat_change.UnitStatChange,
) -> Frame {
  let assert Ok(body) =
    unit_stat_changed.encode(UnitStatChanged(unit_id:, change:))
    as "a unit id, a stat and a value fit the message"
  Frame(message_id: unit_stat_changed.message_id, body:)
}

/// 0x87f: the unit holds the crowd-control state, the effect of the go that gave it
/// `instance_id` (`opcode.0x87f`, `cc_state.instance_id`).
pub fn control_applied_frame(
  unit_id unit_id: Int,
  state state: CrowdControlState,
  instance_id instance_id: Int,
) -> Frame {
  let assert Ok(body) =
    unit_cc_state_applied.encode(UnitCcStateApplied(
      unit_id:,
      state:,
      instance_id:,
    ))
    as "unit ids and instance ids of 32 bits and a state of 5 fit the message"
  Frame(message_id: unit_cc_state_applied.message_id, body:)
}

/// 0x880: the unit's crowd-control state of that cast and instance ends, its last bit
/// 0 (`opcode.0x880`, `cc_state.end`).
pub fn control_ended_frame(
  unit_id unit_id: Int,
  state state: CrowdControlState,
  cast_id cast_id: Int,
  instance_id instance_id: Int,
) -> Frame {
  let assert Ok(body) =
    unit_cc_state_ended.encode(UnitCcStateEnded(
      unit_id:,
      state:,
      cast_id:,
      instance_id:,
      keeps_flag_4_entries: 0,
    ))
    as "unit ids, a cast id and an instance id of 32 bits, a state of 5 and a bit fit the message"
  Frame(message_id: unit_cc_state_ended.message_id, body:)
}

/// 0x935 of the stat of resource slot `slot`: the unit's slot now holds `value`,
/// the only message after a unit's creation that sets a resource slot
/// (`opcode.0x935`, `opcode.0x938.resource_stats`).
pub fn resource_frame(
  unit_id unit_id: Int,
  slot slot: Int,
  value value: Float,
) -> Frame {
  let assert Ok(body) =
    unit_float_stat_changed.encode(UnitFloatStatChanged(
      unit_id:,
      stat_id: unit_fields.resource_stat_id(slot:),
      value: float32.to_bits(value),
    ))
    as "a unit id of 32 bits, a stat of slot 0 to 7 plus 2 and a float fit the message"
  Frame(message_id: unit_float_stat_changed.message_id, body:)
}

/// 0x0594 with the bit set and reason 0: the client leaves the world and
/// starts character select on the same connection (opcode.0x594).
pub fn leave_world_frame() -> Frame {
  let assert Ok(body) = leave_world.encode(LeaveWorld(returning: 1, reason: 0))
    as "a bit and a reason of 0 fit the message"
  Frame(message_id: leave_world.message_id, body:)
}

/// 0x8f5 {unit, stealthed}: the unit entered or left stealth (`opcode.0x8f5`).
pub fn unit_stealth_frame(
  unit_id unit_id: Int,
  stealthed stealthed: Bool,
) -> Frame {
  let assert Ok(body) =
    unit_stealth.encode(UnitStealth(unit_id:, stealthed: bit(stealthed)))
    as "a unit id of 32 bits and a bit fit the message"
  Frame(message_id: unit_stealth.message_id, body:)
}

/// 0x933 {unit, item visuals}: the unit's item visuals change, a display 0 emptying its
/// slot (`opcode.0x933`, `opcode.0x933.empty_display`).
pub fn item_visuals_frame(
  unit_id unit_id: Int,
  item_visuals item_visuals: List(ItemVisual),
) -> Frame {
  let assert Ok(body) =
    unit_item_visuals_changed.encode(UnitItemVisualsChanged(
      unit_id:,
      item_visuals:,
    ))
    as "a unit id of 32 bits and a count of 32 bits fit the message"
  Frame(message_id: unit_item_visuals_changed.message_id, body:)
}

/// 0x247 of type 24 for the unit: it entered stealth, or is leaving it
/// (`opcode.0x247.type24`).
pub fn stealth_logged_frame(
  unit_id unit_id: Int,
  exiting exiting: Bool,
) -> Frame {
  let assert Ok(body) =
    combat_log.encode(
      CombatLog(
        entry: combat_log_entry.Stealth(CombatLogStealth(
          unit_id:,
          exiting: bit(exiting),
        )),
      ),
    )
    as "a unit id of 32 bits and a bit fit the entry"
  Frame(message_id: combat_log.message_id, body:)
}

/// The create flag that marks a unit stealthed: its stealth state is 2 from its
/// creation (`opcode.0x262.unit_fields`, flag 16).
const stealthed_create_flag = 16

/// The player's own record at `place`, stamped from the map's clock, from the
/// origin `Joined` carried (`map.server_time`), with the current base and value of each
/// property a live modifier changes (`unit_properties.overlay`), the item visuals a live
/// disguise shows (`look.visuals`), and the create flag 16 while the player is stealthed,
/// which a viewer that first sees the unit needs (`cast.stealthed`).
pub fn appearance_at(
  entered entered: world_entry.Entered,
  place place: Place,
  now now: Now,
) -> UnitCreatePlayer {
  let #(position, rotation) = player_unit.standing(place:)
  UnitCreatePlayer(
    ..entered.unit,
    tail: UnitCreateTail(
      ..entered.unit.tail,
      create_flags: case cast.stealthed(cast: entered.cast) {
        True ->
          int.bitwise_or(entered.unit.tail.create_flags, stealthed_create_flag)
        False -> entered.unit.tail.create_flags
      },
      properties: unit_properties.overlay(
        listed: entered.unit.tail.properties,
        properties: entered.properties,
      ),
      item_visuals: look.visuals(look: entered.look),
      movement_commands: [
        start_movement.Position(position),
        start_movement.Rotation(rotation),
      ],
      server_time_estimate_start: map.server_time(
        origin_ms: entered.clock_origin_ms,
        monotonic_ms: now.monotonic_ms,
      ),
    ),
  )
}

/// 0x638 for a move of another player's unit, with the reset bit 0 (the unit's
/// movement is not rebuilt) and the kept bit 0 (opcode.0x638).
pub fn unit_moved_frame(
  unit_id unit_id: Int,
  server_time_ms server_time_ms: Int,
  commands commands: List(RelayedMovement),
) -> Frame {
  let assert Ok(body) =
    unit_movement.encode(UnitMovement(
      unit_id:,
      server_time: server_time_ms,
      reset_movement: 0,
      kept: 0,
      commands:,
    ))
    as "a mover sends at most 31 commands and a time of 32 bits"
  Frame(message_id: unit_movement.message_id, body:)
}

/// 0x638 for a creature that runs a path: kind 0, the map's time the path starts at
/// (`movement_command.kind_0`), and kind 4, its two points at its speed as a half
/// float, type 0 (straight lines) and mode 0 (`movement_command.kind_4`). None for a
/// creature that stands, or a speed no half float holds.
pub fn path_frame(
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  path path: creature_path.Path,
) -> Option(Frame) {
  case path {
    creature_path.Standing(..) -> None
    creature_path.Running(from:, to:, started_ms:, speed:) ->
      case half_float.to_bits(value: speed) {
        Error(Nil) -> None
        Ok(speed) -> {
          let time =
            map.server_time(
              origin_ms: entered.clock_origin_ms,
              monotonic_ms: started_ms,
            )
          Some(
            unit_moved_frame(unit_id:, server_time_ms: time, commands: [
              relayed_movement.Time(MovementTime(time:)),
              relayed_movement.Path(MovementPath(
                points: [vector_of(from), vector_of(to)],
                speed:,
                path_type: 0,
                mode: 0,
              )),
            ]),
          )
        }
      }
  }
}

/// 0x638 for a creature that stands at `place` from monotonic time `at_ms`, though
/// the client may still run a path it was sent: kind 0, the map's time, and kind 2
/// at the place with its blend bit 0. A kind 2 with its bit clear starts a new
/// segment in the list the kind 4 path is linked into (`0x1407138f0`
/// ApplyMoveCommandSetPosition, `movement_command.kind_4`), and the client starts
/// due segments in order, so the unit is placed at once and the path no longer
/// runs (`0x140714120` StartDuePositionSegments). The command is the one that
/// puts a unit at a place in its 0x262 (`0x1400ad350` reads it).
pub fn placed_frame(
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  place place: Place,
  at_ms at_ms: Int,
) -> Frame {
  let time =
    map.server_time(origin_ms: entered.clock_origin_ms, monotonic_ms: at_ms)
  unit_moved_frame(unit_id:, server_time_ms: time, commands: [
    relayed_movement.Time(MovementTime(time:)),
    relayed_movement.Position(player_unit.standing(place:).0),
  ])
}

fn vector_of(place: Place) -> movement_float_vector.MovementFloatVector {
  MovementFloatVector(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
  )
}

/// 0x357, which opens the dialog of a unit (`opcode.0x357`): the unit's id and the
/// bit the client's reader needs after it, clear.
pub fn dialog_open_frame(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_dialog_open.encode(UnitDialogOpen(unit_id:, field_2: 0))
    as "a unit id the player's picture holds fits the message's 32 bits"
  Frame(message_id: unit_dialog_open.message_id, body:)
}

/// 0x35c, the state a quest is now in (`opcode.0x35c`): the quest, its state and the
/// objective the client is told of, 0 for none.
pub fn quest_state_frame(
  quest_id quest_id: Int,
  state state: Int,
  objective_id objective_id: Int,
) -> Frame {
  let assert Ok(body) =
    quest_state.encode(QuestState(quest_id:, state:, objective_id:))
    as "a Quest2 id of the table, a state of 1 to 7 and an objective id fit the message"
  Frame(message_id: quest_state.message_id, body:)
}

/// 0x90b that opens a vendor's window with its stock (`opcode.0x90b`): one item for each
/// row in position order, named by its position, with price slots of kind 0 so the client
/// computes each price from its own tables, and no tabs, which the client shows as General.
pub fn vendor_items_frame(
  unit_id unit_id: Int,
  vendor vendor: Vendor,
) -> Frame {
  let items =
    list.map(vendor.items, fn(stocked) {
      let Item2Id(entry_id) = stocked.item_id
      VendorItem(
        unique_id: stocked.position,
        kind: 0,
        entry_id:,
        currency_type_id: 0,
        stock_count: 0,
        prerequisite_id: 0,
        amount: 0,
        tab_id: 0,
        flags: 0,
        field_10: 0,
        field_11: 0,
        price_slot_1: VendorPriceSlot(kind: 0, amount: 0, currency_id: 0),
        price_slot_2: VendorPriceSlot(kind: 0, amount: 0, currency_id: 0),
      )
    })
  vendor_items_message(VendorItems(
    unit_id:,
    tabs: [],
    items:,
    buy_multiplier: float32.to_bits(vendor.buy_multiplier),
    sell_multiplier: float32.to_bits(vendor.sell_multiplier),
    open: 1,
    full_list: 1,
    refuse: 0,
  ))
}

/// 0x90b that refuses a vendor request: the client ends the interaction and returns
/// before it stores the two multipliers (`opcode.0x90b`), so any value is read by no
/// one; 1.0 is the neutral one. There is no stock.
pub fn vendor_refused_frame(unit_id unit_id: Int) -> Frame {
  vendor_items_message(VendorItems(
    unit_id:,
    tabs: [],
    items: [],
    buy_multiplier: float32.to_bits(1.0),
    sell_multiplier: float32.to_bits(1.0),
    open: 1,
    full_list: 0,
    refuse: 1,
  ))
}

fn vendor_items_message(message: VendorItems) -> Frame {
  let assert Ok(body) = vendor_items.encode(message)
    as "a unit id the player's picture holds and a stock of the content load fit the message's fields"
  Frame(message_id: vendor_items.message_id, body:)
}

/// 0xbc with no entries, which the client's vendor window reads after the stock
/// (`opcode.0xbc`): nothing has been sold to a vendor.
pub fn buyback_list_empty_frame() -> Frame {
  let assert Ok(body) = buyback_list.encode(BuybackList(entries: []))
    as "an empty list fits its 32-bit count"
  Frame(message_id: buyback_list.message_id, body:)
}

/// 0x106 with the client's code for why an action is refused (`opcode.0x106`).
pub fn generic_error_frame(code code: Int) -> Frame {
  let assert Ok(body) = generic_error.encode(GenericError(code:))
    as "a refusal code of the interaction rule fits the message's 8 bits"
  Frame(message_id: generic_error.message_id, body:)
}

/// 0x262 for a creature, as its process built it.
pub fn creature_created_frame(unit unit: UnitCreateCreature) -> Frame {
  let assert Ok(body) = unit_create_creature.encode(unit)
    as "a creature's values fit the message's fields: the spawn's checks hold each"
  Frame(message_id: unit_create_creature.message_id, body:)
}

/// 0x262 for a static object, as the map built it.
pub fn object_created_frame(unit unit: Created) -> Frame {
  let #(message_id, encoded) = case unit {
    CreatedWithChecklist(message) -> #(
      unit_create_static.message_id,
      unit_create_static.encode(message),
    )
    CreatedDoor(message) -> #(
      unit_create_door.message_id,
      unit_create_door.encode(message),
    )
    CreatedMailbox(message) -> #(
      unit_create_mailbox.message_id,
      unit_create_mailbox.encode(message),
    )
    CreatedPortal(message) -> #(
      unit_create_portal.message_id,
      unit_create_portal.encode(message),
    )
  }
  let assert Ok(body) = encoded
    as "an object's values fit the message's fields: the spawn's checks and the table's constraints hold each"
  Frame(message_id:, body:)
}

/// 0x355 for another player's unit or a creature, with its one bit 0
/// (opcode.0x355).
pub fn unit_removed_frame(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_destroyed.encode(UnitDestroyed(unit_id:, field_2: 0))
    as "a unit id of 32 bits fits the message"
  Frame(message_id: unit_destroyed.message_id, body:)
}
