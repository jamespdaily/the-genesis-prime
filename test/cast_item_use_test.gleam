//// The cast rule's use of an item (`genesis_prime/game/cast.use_item`): the player's 0x943 for
//// the quest items of the tutorial zone, on the client's own rows and on a clock the test
//// drives. Expected values come from these places:
//// - `opcode.0x943` (sent only from StartItemUseCast `0x140398cc0`): the client's cast id, the
////   item's place, the target unit and the second place; a body the client's reader refuses
////   or a cast id of 0 is not the client's (its cast counter starts at 1).
//// - UseItem `0x1403998e0`: a place with no item is refused with 22 (`ItemBad`); an item with no
////   spell never sends 0x943.
//// - Item2 12444 (the Incendiary Grenade) -> ItemSpecial 4363 -> Spell4 26663: castTime 0,
////   spellCoolDown 2000, targetMaxRange 30.0, Spell4Base 13157 with the cast group
////   TargetGroup 1691 ({Creature2 17397, 17398, 17399}, the Cartel Slaver Shacks);
////   Spell4Effects 43805 is its Activate row (effectType 7).
//// - Item2 12402 -> ItemSpecial 4350 -> Spell4 1545: castTime 0, targetMaxRange 5.0, no cast
////   group; Spell4Effects 2348 is its Activate row.
//// - Item2 461 -> ItemSpecial 2697 -> Spell4 28, cast at a unit (targetType 1) and holding
////   no effect row: no Activate row, so the creature's activate cast has no plan for it.
//// - Item2 21966 -> ItemSpecial 5410 -> Spell4 41914, cast on its user (targetType 0), whose
////   one effect, Spell4Effects 94446, is a RavelSignal: the client signals a script it does
////   not hold, so the cast lists the row (`effect_kind`).
//// - `opcode.0x97.range` (`0x1403b2240`): the gap between the units' edges is held to the
////   spell's limits.
//// - `opcode.0x7fc`: the refusal carries the client's cast id, the spell and the result.

import cast_support as support
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/activate.{type Target, Usable}
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Effect, type State} as cast_state
import genesis_prime/game/class_resource
import genesis_prime/game/effect_kind
import genesis_prime/game/item_use
import genesis_prime/game/passed_in_value
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/shortcut_spell
import genesis_prime/game/target_group
import genesis_prime/message/crowd_control_state
import genesis_prime/message/item_place.{type ItemPlace, ItemPlace}
import genesis_prime/message/item_use.{ItemUse} as use_message
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_go
import genesis_prime/step.{LogWarning}
import genesis_prime/table/id.{Creature2Id, Faction2Id, Item2Id, UnitRaceId}
import genesis_prime/table/loader/store as table_store
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import item_charge_support
import owned_test
import place_support
import planted_table.{Integer}
import prerequisite_support
import quest_support

pub const grenade = 12_444

const generic_item = 12_402

const a_spell_at_a_unit_with_no_rows = 461

const grenade_quest = 4743

pub const a_slaver_shack = 17_397

pub const a_farmhand = 17_107

pub const its_unit = 5000

pub const clients_cast_id = 9

/// The place of the item the player uses.
const the_item_place = ItemPlace(location: 1, bag_index: 0)

// Hit radii of exactly representable size: the player's and the unit's.
const caster_radius = 0.5

const object_radius = 0.25

fn tables() -> table_store.Tables {
  fixture_tables.shared()
}

/// A level 20 player who holds quest 4743, accepted.
fn throwing() -> cast_state.Caster {
  standing(
    level: 20,
    quests: quest_support.log_of(rows: [
      quest_support.accepted(quest_id: grenade_quest, progress: [0, 0, 0, 0]),
    ]),
  )
}

/// The caster stands at a place of exactly representable numbers.
pub fn standing(
  level level: Int,
  quests quests: QuestLog,
) -> cast_state.Caster {
  let caster = support.caster()
  cast_state.Caster(
    ..caster,
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 4096.0,
      y: 0.0,
      z: 512.0,
    ),
    quests:,
    player: prerequisite.Player(..caster.player, level:),
  )
}

/// A creature standing this far from the caster, edge to edge.
pub fn shown(creature_id creature_id: Int, metres metres: Float) -> Target {
  support.usable_at(
    creature_id:,
    x: 4096.0 +. metres +. caster_radius +. object_radius,
    radius: object_radius,
  )
}

fn the_body(
  client_cast_id client_cast_id: Int,
  item item: ItemPlace,
  target_unit_id target_unit_id: Int,
) -> BitArray {
  let assert Ok(body) =
    use_message.encode(ItemUse(
      client_cast_id:,
      item:,
      target_unit_id:,
      second_item: ItemPlace(location: 300, bag_index: 0xffffffff),
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  body
}

/// The use of the item at `item`, held when its place is the one the test names, by the
/// caster; the unit `its_unit` is the one the picture shows.
fn used_with(
  tables tables: table_store.Tables,
  state state: State,
  caster caster: cast_state.Caster,
  held held: Option(Int),
  charges charges: Int,
  body body: BitArray,
  target target: Target,
  at ms: Int,
) -> Result(cast_state.Used, cast_state.Refusal) {
  cast.use_item(
    cast: state,
    body:,
    caster:,
    held_at: fn(place) {
      case place == the_item_place, held {
        True, Some(item) ->
          Some(cast_state.ItemAtPlace(item2_id: Item2Id(item), charges:))
        _, _ -> None
      }
    },
    check: fn(item, charges, second_item, target_checklist_index, prerequisite) {
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
    activations: activate.activations(tables:),
    shortcuts: shortcut_spell.shortcuts(tables:),
    item_cast_of: fn(item) {
      cast_state.Item(
        item_level: passed_in_value.level_of_item(tables:, item2_id: item),
        passed_in: passed_in_value.of_item(tables:, item2_id: item),
      )
    },
    target_of: fn(unit_id) {
      case unit_id == its_unit {
        True -> target
        False -> activate.Unseen
      }
    },
    in_cast_group: fn(group, unit_id) {
      case unit_id == its_unit, target {
        True, Usable(creature_id:, ..) ->
          target_group.contains(
            tables:,
            group:,
            unit: target_group.Unit(
              creature_id: Creature2Id(creature_id),
              faction_id: Faction2Id(0),
              unit_race_id: UnitRaceId(0),
            ),
          )
        True, activate.Unseen
        | True, activate.AnotherPlayer
        | False, Usable(..)
        | False, activate.Unseen
        | False, activate.AnotherPlayer
        -> False
      }
    },
    caster_radius:,
    now: support.at(ms:),
  )
}

/// The use as `used_with` takes it, with what the press started or refused as one pair:
/// the state and effects `Frames` holds, or of the cast `Started` makes at the press's own
/// time, as when the store answers at once.
fn use_with(
  tables tables: table_store.Tables,
  state state: State,
  caster caster: cast_state.Caster,
  held held: Option(Int),
  body body: BitArray,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast_state.Refusal) {
  used_with(tables:, state:, caster:, held:, charges: 1, body:, target:, at: ms)
  |> result.map(pair_of(used: _, state:, at: ms))
}

fn pair_of(
  used used: cast_state.Used,
  state state: State,
  at ms: Int,
) -> #(State, List(Effect)) {
  case used {
    cast_state.Frames(cast:, effects:) -> #(cast, effects)
    cast_state.Started(start:, ..) ->
      cast.item_started(cast: state, start:, now: support.at(ms:))
  }
}

/// The use of item `item`, held at its place, at the unit `its_unit`.
pub fn use_item_at(
  state state: State,
  caster caster: cast_state.Caster,
  item item: Int,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast_state.Refusal) {
  use_item_in(tables: tables(), state:, caster:, item:, target:, at: ms)
}

/// The use of item `item` as `use_item_at` does, on these tables.
pub fn use_item_in(
  tables tables: table_store.Tables,
  state state: State,
  caster caster: cast_state.Caster,
  item item: Int,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast_state.Refusal) {
  use_with(
    tables:,
    state:,
    caster:,
    held: Some(item),
    body: the_body(
      client_cast_id: clients_cast_id,
      item: the_item_place,
      target_unit_id: its_unit,
    ),
    target:,
    at: ms,
  )
}

/// The use is taken, and answered with the one refusal and nothing else.
fn refusal_of(
  taken taken: Result(#(State, List(Effect)), cast_state.Refusal),
) -> #(Int, Int) {
  let assert Ok(#(_, effects)) = taken as "an item use that fits is answered"
  let assert [#(cast_id, spell4_id, result)] = support.refused_with(effects:)
    as "one 0x7fc"
  assert cast_id == clients_cast_id
    as "the refusal answers the client's cast id"
  assert list.length(support.writes(effects:)) == 1
    && support.started_timers(effects:) == []
    && support.tells(effects:) == []
    as "a refused use writes the one 0x7fc and starts nothing"
  #(spell4_id, result)
}

pub fn item_use_with_client_cast_id_0_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  assert use_with(
      tables: tables(),
      state: cast_state.new(),
      caster: throwing(),
      held: Some(grenade),
      body: the_body(
        client_cast_id: 0,
        item: the_item_place,
        target_unit_id: its_unit,
      ),
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    == Error(cast_state.NoClientCastId)
    as "the client's cast counter starts at 1, so a 0x943 of cast id 0 is not the client's"
  Nil
}

pub fn item_use_the_reader_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let body =
    the_body(
      client_cast_id: clients_cast_id,
      item: the_item_place,
      target_unit_id: its_unit,
    )
  let assert Ok(short) = bit_array.slice(body, 0, bit_array.byte_size(body) - 1)
    as "the body has a last byte to drop"
  let assert Error(cast_state.NotDecoded(..)) =
    use_with(
      tables: tables(),
      state: cast_state.new(),
      caster: throwing(),
      held: Some(grenade),
      body: short,
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    as "a body one byte short of the message's fixed size is one the client's reader refuses"
  Nil
}

pub fn item_use_at_an_empty_place_is_refused_22_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = cast_state.new()
  let assert Ok(#(after, effects)) =
    use_with(
      tables: tables(),
      state:,
      caster: throwing(),
      held: Some(grenade),
      body: the_body(
        client_cast_id: clients_cast_id,
        item: ItemPlace(location: 1, bag_index: 5),
        target_unit_id: its_unit,
      ),
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    as "a use of an empty place is answered"
  assert support.refused_with(effects:) == [#(clients_cast_id, 0, 22)]
    as "UseItem 0x1403998e0 gives a place with no item 0x16 (22), and there is no spell to name"
  assert list.length(support.writes(effects:)) == 1
    && support.started_timers(effects:) == []
    as "the one 0x7fc is all it does"
  assert after == state as "the cast state is unchanged"
}

pub fn item_use_of_an_item_with_no_spell_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- fixture_tables.changed(table: "Item2", id: grenade, with: [
    #("itemSpecialId00", Integer(0)),
  ])
  assert use_with(
      tables:,
      state: cast_state.new(),
      caster: throwing(),
      held: Some(grenade),
      body: the_body(
        client_cast_id: clients_cast_id,
        item: the_item_place,
        target_unit_id: its_unit,
      ),
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    == Error(cast_state.NoItemSpell)
    as "UseItem 0x1403998e0 sends no 0x943 for an item with no spell (it answers 0x35b or 0x17), so a held item with none is not the client's"
  Nil
}

pub fn the_grenade_at_a_slaver_shack_starts_the_activate_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    as "the use is taken"
  assert support.refusal_results(effects:) == []
    as "TargetGroup 1691 holds Creature2 17397, and the shack stands within Spell4 26663's 30"
  let assert [confirmed_frame] =
    support.frames_of(message_id: spell_cast_confirmed.message_id, effects:)
    as "the caster is written one 0x7fd"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed_frame.body)
  assert confirmed.client_cast_id == clients_cast_id
    && confirmed.primary_target_unit_id == its_unit
    as "opcode.0x7fd: the confirmation answers the client's cast id and names the unit"
  let assert [#(_, client_news), ..] = support.tells(effects:)
    as "the viewers are told the start"
  let assert CastStarted(start: started) = client_news
  assert started.spell4_id == 26_663
    && started.root_spell4_id == 26_663
    && started.caster_unit_id == 7
    && started.primary_target_unit_id == its_unit
    as "the viewers see Spell4 26663, the item's spell, cast by the caster at the shack"
}

pub fn an_item_cast_at_a_creature_leaves_the_activate_bit_clear_in_the_start_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    as "the use is taken"
  let assert [#(_, CastStarted(start: started)), ..] = support.tells(effects:)
    as "the viewers are told the start"
  assert started.creature_activate == 0
    as "opcode.0x7ff.activate: only CastActivateSpell sets info 0x54; StartItemUseCast writes 0x58, so an item's cast at a creature takes the item spell's own cast time and name"
  Nil
}

pub fn the_grenade_go_raises_activated_for_the_shack_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    as "the use is taken"
  let assert [go_frame] =
    support.frames_of(message_id: spell_go.message_id, effects:)
    as "Spell4 26663's castTime is 0, so the go is written with the start"
  let assert Ok(go) = spell_go.decode(go_frame.body)
  assert list.map(go.targets, fn(target) {
      #(
        target.unit_id,
        list.map(target.effects, fn(info) { info.spell4_effects_id }),
      )
    })
    == [#(its_unit, [43_805])]
    as "the go names the shack with the effect info of Spell4Effects 43805, the spell's Activate row"
  assert support.activated_count(
      effects:,
      unit_id: its_unit,
      creature_id: a_slaver_shack,
      by_item: True,
    )
    == 1
    as "the go raises Activated for the shack once, marked as an item's cast"
}

pub fn the_grenade_at_a_unit_outside_its_cast_group_is_refused_89_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refusal_of(taken: use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: shown(creature_id: a_farmhand, metres: 10.0),
      at: 1000,
    ))
    == #(26_663, 89)
    as "Spell4Base 13157's cast group is TargetGroup 1691, which does not hold Creature2 17107: CheckCastActivateSpell (0x1403b44b0) refuses it 89 (TargetGroup), with the item's spell"
}

/// The grenade thrown at the farmhand, which its cast group does not hold, on tables where
/// the grenade's spell (Spell4 26663) names Spell4CCConditions row 1 for its target: that
/// row's ccStateMask 218960739 has bits 0 (Stun), 1 (Sleep) and 5 (Polymorph) and no bit
/// 21 (Snare). Spell4Conditions row 15 (mask 129, value 0) says the target must be alive.
fn grenade_at_a_farmhand_in_a_state(
  held held: List(crowd_control_state.CrowdControlState),
  alive alive: Bool,
) -> #(Int, Int) {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4",
      id: 26_663,
      with: [#("spell4CCConditionsIdTarget", Integer(1))],
    )
    as "Spell4 26663 and its column are in the fixture"
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let assert Usable(..) as farmhand =
    shown(creature_id: a_farmhand, metres: 10.0)
    as "shown gives a usable target"
  refusal_of(taken: use_item_in(
    tables:,
    state: cast_state.new(),
    caster: throwing(),
    item: grenade,
    target: Usable(..farmhand, held:, alive:),
    at: 1000,
  ))
}

/// An item's spell takes the same road as a press: `0x1403998e0` (UseItem) reaches
/// CheckCastUnitTargetRange (0x1403b2240) through StartItemUseCast (0x140398cc0),
/// StartLocalCast (0x1403988d0), 0x140398800, CheckCastAndPrerequisites (0x1403ace00),
/// 0x1403ae8c0 and CheckCastTarget (0x1403b0880), and that function tests the target's
/// life and states before the cast group (CheckCastActivateSpell, 0x1403b44b0).
pub fn an_item_spell_at_a_held_creature_outside_its_cast_group_is_refused_its_state_test() -> Nil {
  use <- owned_test.run(10_000)
  assert grenade_at_a_farmhand_in_a_state(
      held: [crowd_control_state.Stun],
      alive: True,
    )
    == #(26_663, 122)
    as "0x1403b2240 tests the target's states before its cast group: a Stunned farmhand is refused Target_CannotBe_Stunned (122), not 89"
  assert grenade_at_a_farmhand_in_a_state(
      held: [crowd_control_state.Sleep],
      alive: True,
    )
    == #(26_663, 124)
    as "bit 1 gives its own result, Target_CannotBe_Slept (124)"
  assert grenade_at_a_farmhand_in_a_state(
      held: [crowd_control_state.Snare],
      alive: True,
    )
    == #(26_663, 89)
    as "a state the mask does not name (Snare, bit 21) leaves the cast group's 89"
  assert grenade_at_a_farmhand_in_a_state(held: [], alive: True)
    == #(26_663, 89)
    as "a creature that holds nothing meets the cast group's 89"
  assert grenade_at_a_farmhand_in_a_state(held: [], alive: False)
    == #(26_663, 106)
    as "0x1403b2240 tests the target's life first: a dead target of a spell that needs it alive is refused Target_CannotBe_Dead (106), not 89"
}

pub fn the_grenade_at_another_players_unit_is_refused_100_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refusal_of(taken: use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: activate.AnotherPlayer,
      at: 1000,
    ))
    == #(26_663, 100)
    as "a server choice: Item2 12444 names its quest as a whole (objective -1), so StartItemUseCast (0x140398cc0) tests no unit, and the activate cast's target is a creature: another player's unit is TargetIsNotUseable (100)"
}

pub fn a_checklist_item_at_another_players_unit_is_refused_28_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- fixture_tables.changed(table: "Item2", id: grenade, with: [
    #("quest2IdActivationRequired", Integer(1823)),
    #("questObjectiveActivationRequired", Integer(0)),
  ])
  assert refusal_of(taken: use_item_in(
      tables:,
      state: cast_state.new(),
      caster: standing(
        level: 20,
        quests: quest_support.log_of(rows: [
          quest_support.accepted(quest_id: 1823, progress: [0]),
        ]),
      ),
      item: grenade,
      target: activate.AnotherPlayer,
      at: 1000,
    ))
    == #(26_663, 28)
    as "StartItemUseCast (0x140398cc0) tests the open checklist objective 0 of quest 1823 at the unit of another player, whose checklist index is -1: ItemQuestRequirementsNotMet (28)"
}

pub fn a_spell_with_no_cast_group_at_a_creature_with_flags_bit_0_is_refused_89_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = standing(level: 20, quests: quest_support.log_of(rows: []))
  assert refusal_of(taken: use_item_at(
      state: cast_state.new(),
      caster:,
      item: generic_item,
      target: shown(creature_id: a_slaver_shack, metres: 4.0),
      at: 1000,
    ))
    == #(1545, 89)
    as "Spell4 1545 has no cast group and Creature2 17397's flags (16385) has bit 0: CheckCastActivateSpell refuses it 89"
}

pub fn a_creature_whose_activate_spell_is_the_items_spell_passes_the_cast_group_test() -> Nil {
  use <- owned_test.run(10_000)
  let own = fn(spell4_id, creature_id) {
    let target = shown(creature_id:, metres: 4.0)
    let assert Usable(creature:, ..) = target as "shown gives a creature"
    Usable(
      ..target,
      creature: activate.Creature(..creature, columns: [
        activate.Column(prerequisite_id: 0, spell4_id:),
      ]),
    )
  }
  let assert Ok(#(_, outside)) =
    use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: own(26_663, a_farmhand),
      at: 1000,
    )
    as "the use is taken"
  assert support.refusal_results(effects: outside) == []
    as "the farmhand is outside TargetGroup 1691, but its activate spell is the grenade's: the check passes whatever the group"
  let assert Ok(#(_, flagged)) =
    use_item_at(
      state: cast_state.new(),
      caster: standing(level: 20, quests: quest_support.log_of(rows: [])),
      item: generic_item,
      target: own(1545, a_slaver_shack),
      at: 1000,
    )
    as "the use is taken"
  assert support.refusal_results(effects: flagged) == []
    as "the shack has flags bit 0, but its activate spell is Spell4 1545: it passes whatever the flags"
}

pub fn the_grenade_with_no_target_is_refused_91_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refusal_of(taken: use_with(
      tables: tables(),
      state: cast_state.new(),
      caster: throwing(),
      held: Some(grenade),
      body: the_body(
        client_cast_id: clients_cast_id,
        item: the_item_place,
        target_unit_id: 0,
      ),
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    ))
    == #(26_663, 91)
    as "CheckCast gives NoTarget (91) with no target for a spell of targetType 1 (`0x14039a040`)"
  assert refusal_of(taken: use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: activate.Unseen,
      at: 1000,
    ))
    == #(26_663, 91)
    as "a unit the player is not shown is no target"
}

/// The grenade thrown at a shack this far away, edge to edge: the result it is refused
/// with, or Ok when the cast starts.
fn thrown_at(metres metres: Float) -> Result(Nil, #(Int, Int)) {
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target: shown(creature_id: a_slaver_shack, metres:),
      at: 1000,
    )
    as "the use is answered"
  case support.refused_with(effects:) {
    [] -> Ok(Nil)
    [#(_, spell4_id, result)] -> Error(#(spell4_id, result))
    _ -> panic as "at most one refusal"
  }
}

pub fn the_grenade_beyond_30_m_is_refused_105_test() -> Nil {
  use <- owned_test.run(10_000)
  assert thrown_at(metres: 30.0) == Ok(Nil)
    as "Spell4 26663's targetMaxRange is 30.0: a gap of exactly 30.0 is in range"
  assert thrown_at(metres: 30.5) == Error(#(26_663, 105))
    as "a gap of 30.5 is TargetRangeMax (105), edge to edge (`opcode.0x97.range`)"
}

pub fn an_item_check_refusal_carries_the_items_spell_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refusal_of(taken: use_item_at(
      state: cast_state.new(),
      caster: standing(level: 20, quests: quest_support.log_of(rows: [])),
      item: grenade,
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    ))
    == #(26_663, 28)
    as "quest 4743 is not in the log: ItemQuestRequirementsNotMet (28) from StartItemUseCast, with Item2 12444's spell 26663"
}

/// The grenade with the prerequisite 624 (the player's level at least 20, type 1
/// comparison 4 value 20), run on these tables.
fn with_prerequisite_624(
  extra extra: List(#(String, planted_table.Cell)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Item2",
      id: grenade,
      with: [#("prerequisiteId", Integer(624))],
    )
    as "Item2 12444 and its column are in the fixture"
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "Prerequisite", id: 624, with: extra)
    as "Prerequisite 624 is in the fixture"
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

pub fn an_item_whose_prerequisite_fails_is_refused_17_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_prerequisite_624(extra: [])
  let thrown = fn(level) {
    use_item_in(
      tables:,
      state: cast_state.new(),
      caster: standing(level:, quests: throwing().quests),
      item: grenade,
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
  }
  assert refusal_of(taken: thrown(19)) == #(26_663, 17)
    as "UseItem (0x1403998e0) runs the prerequisite of Item2.prerequisiteId: Prerequisite 624 is type 1 comparison 4 value 20, the player's level at least 20, and level 19 fails it with SpellPreRequisites (17)"
  let assert Ok(#(_, started)) = thrown(20) as "level 20 meets the prerequisite"
  assert support.refusal_results(effects: started) == []
    as "the use of level 20 passes it and starts"
}

pub fn an_item_whose_prerequisite_the_server_cannot_read_is_refused_285_and_logged_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [unread, ..] = prerequisite_support.unread_types()
    as "the client's Prerequisite types include some the server does not read"
  use tables <- with_prerequisite_624(extra: [
    #("prerequisiteTypeId0", Integer(unread)),
  ])
  let thrown = fn(state, at) {
    let assert Ok(taken) =
      use_item_in(
        tables:,
        state:,
        caster: throwing(),
        item: grenade,
        target: shown(creature_id: a_slaver_shack, metres: 10.0),
        at:,
      )
      as "the use is answered"
    taken
  }
  let #(state, first) = thrown(cast_state.new(), 1000)
  let #(_, second) = thrown(state, 2000)
  assert support.refused_with(effects: first)
    == [#(clients_cast_id, 26_663, 285)]
    && support.refused_with(effects: second)
    == [#(clients_cast_id, 26_663, 285)]
    as "a prerequisite of a type the server does not read cannot be judged: IllegalSpellCast (285), each time"
  let assert [#(LogWarning, line)] =
    list.append(support.logs(effects: first), support.logs(effects: second))
    as "the gap is logged once"
  assert string.contains(line, "type " <> int.to_string(unread))
    as "the log line names the type"
}

pub fn the_grenade_again_within_its_2_s_cooldown_is_refused_15_test() -> Nil {
  use <- owned_test.run(10_000)
  let target = shown(creature_id: a_slaver_shack, metres: 10.0)
  let assert Ok(#(state, first)) =
    use_item_at(
      state: cast_state.new(),
      caster: throwing(),
      item: grenade,
      target:,
      at: 1000,
    )
    as "the first use is taken"
  assert support.refusal_results(effects: first) == [] as "the first use starts"
  // The cooldown starts at the go, which Spell4 26663's castTime 0 puts at the press. A
  // press of an ability with 500 ms or less of a cooldown left is queued, not refused
  // (`player.abilityQueueMax`); a cast the client sent with a cast id is never queued, so
  // the server refuses the press as it refuses a hold (14), and the refusal 15 is a press
  // with more than 500 ms left.
  assert support.refused_with(effects: used_as(
      state:,
      client_cast_id: 10,
      item: grenade,
      target:,
      at: 2499,
    ))
    == [#(10, 26_663, 15)]
    as "1499 ms after the cooldown started, 501 of Spell4 26663's spellCoolDown 2000 are left: SpellCooldown (15)"
  let assert Ok(#(_, again)) =
    use_with(
      tables: tables(),
      state:,
      caster: throwing(),
      held: Some(grenade),
      body: the_body(
        client_cast_id: 11,
        item: the_item_place,
        target_unit_id: its_unit,
      ),
      target:,
      at: 3000,
    )
    as "the use at 2000 ms is taken"
  assert support.refusal_results(effects: again) == []
    as "the cooldown has run out"
  assert list.length(support.frames_of(
      message_id: spell_cast_confirmed.message_id,
      effects: again,
    ))
    == 1
    as "the cast starts"
}

/// The effects of a use of `item` with this client cast id on a state that has taken an
/// earlier press (the client's ids rise with every cast).
fn used_as(
  state state: State,
  client_cast_id client_cast_id: Int,
  item item: Int,
  target target: Target,
  at ms: Int,
) -> List(Effect) {
  let assert Ok(#(_, effects)) =
    use_with(
      tables: tables(),
      state:,
      caster: throwing(),
      held: Some(item),
      body: the_body(
        client_cast_id:,
        item: the_item_place,
        target_unit_id: its_unit,
      ),
      target:,
      at: ms,
    )
    as "the use is taken"
  effects
}

pub fn the_generic_quest_spell_item_at_a_farmhand_starts_within_5_m_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = standing(level: 20, quests: quest_support.log_of(rows: []))
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast_state.new(),
      caster:,
      item: generic_item,
      target: shown(creature_id: a_farmhand, metres: 4.5),
      at: 1000,
    )
    as "the use is taken"
  assert support.refusal_results(effects:) == []
    as "Spell4 1545 has no cast group, and the farmhand is within its targetMaxRange 5.0"
  let assert [#(_, client_connection_news), ..] = support.tells(effects:)
    as "the viewers are told the start"
  let assert CastStarted(start: started) = client_connection_news
  assert started.spell4_id == 1545 as "the cast is Spell4 1545"
  assert support.activated_count(
      effects:,
      unit_id: its_unit,
      creature_id: a_farmhand,
      by_item: True,
    )
    == 1
    as "the go raises Activated for the farmhand"
  assert refusal_of(taken: use_item_at(
      state: cast_state.new(),
      caster:,
      item: generic_item,
      target: shown(creature_id: a_farmhand, metres: 5.5),
      at: 1000,
    ))
    == #(1545, 105)
    as "a gap of 5.5 is beyond Spell4 1545's 5.0: TargetRangeMax (105)"
}

/// Item2 2509, whose maxCharges is 99 and whose spell 1274 has an Activate effect.
const charged_item = 2509

/// What the press of one kind of refusal gives: the tables it runs on, the caster, the
/// item held at the place, the charges held, the target and the 0x7fc the press is
/// answered with.
type Refusing {
  Refusing(
    tables: table_store.Tables,
    caster: cast_state.Caster,
    held: Option(Int),
    charges: Int,
    target: Target,
    refused: #(Int, Int),
    why: String,
  )
}

pub fn an_item_use_spends_only_when_its_cast_starts_test() -> Nil {
  use <- owned_test.run(10_000)
  let level_30_grenade = fn(body) {
    fixture_tables.changed(
      table: "Item2",
      id: grenade,
      with: [#("requiredLevel", Integer(30))],
      body:,
    )
  }
  use level_tables <- level_30_grenade
  let shack = shown(creature_id: a_slaver_shack, metres: 10.0)
  let grenade_row = fn(why, result, target) {
    Refusing(
      tables: tables(),
      caster: throwing(),
      held: Some(grenade),
      charges: 0,
      target:,
      refused: #(26_663, result),
      why:,
    )
  }
  list.each(
    [
      Refusing(
        ..grenade_row("an empty place is 22", 22, shack),
        held: None,
        refused: #(0, 22),
      ),
      Refusing(
        ..grenade_row("a charged item holding none is 25", 25, activate.Unseen),
        held: Some(charged_item),
        caster: standing(level: 50, quests: quest_support.log_of(rows: [])),
        charges: 0,
        refused: #(1274, 25),
      ),
      Refusing(
        ..grenade_row("a player below the item's level is 26", 26, shack),
        tables: level_tables,
      ),
      grenade_row(
        "a target the picture does not show is 91",
        91,
        activate.Unseen,
      ),
      grenade_row("another player's unit is 100", 100, activate.AnotherPlayer),
      grenade_row(
        "a unit outside the spell's cast group is 89",
        89,
        shown(creature_id: a_farmhand, metres: 10.0),
      ),
      grenade_row(
        "a target beyond the spell's 30 m is 105",
        105,
        shown(creature_id: a_slaver_shack, metres: 31.0),
      ),
      Refusing(
        ..grenade_row(
          "a spell cast at a unit with no Activate effect is 285",
          285,
          activate.Unseen,
        ),
        held: Some(a_spell_at_a_unit_with_no_rows),
        caster: standing(level: 50, quests: quest_support.log_of(rows: [])),
        refused: #(28, 285),
      ),
    ],
    fn(row) {
      let assert Ok(cast_state.Frames(cast: after, effects:)) =
        used_with(
          tables: row.tables,
          state: cast_state.new(),
          caster: row.caster,
          held: row.held,
          charges: row.charges,
          body: the_body(
            client_cast_id: clients_cast_id,
            item: the_item_place,
            target_unit_id: its_unit,
          ),
          target: row.target,
          at: 1000,
        )
        as row.why
      assert list.map(support.refused_with(effects:), fn(refused) {
          #(refused.1, refused.2)
        })
        == [row.refused]
        as row.why
      assert after.item_press_watermark == None
        && support.started_timers(effects:) == []
        as "a refusal takes no press id and starts nothing"
    },
  )
  let assert Ok(cast_state.Started(press:, start:)) =
    used_with(
      tables: tables(),
      state: cast_state.new(),
      caster: throwing(),
      held: Some(grenade),
      charges: 0,
      body: the_body(
        client_cast_id: clients_cast_id,
        item: the_item_place,
        target_unit_id: its_unit,
      ),
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: 1000,
    )
    as "an accepted press starts a cast"
  assert press
    == cast_state.ItemPress(
      client_cast_id: clients_cast_id,
      spell4_id: 26_663,
      place: the_item_place,
    )
    as "the press names the client's cast id, the item's spell and the place"
  let #(started, effects) =
    cast.item_started(cast: cast_state.new(), start:, now: support.at(ms: 1000))
  assert started.item_press_watermark == Some(clients_cast_id)
    as "the cast made from the passed press records the press id"
  assert support.frames_of(
      message_id: spell_cast_confirmed.message_id,
      effects:,
    )
    != []
    as "the cast made from the passed press holds the cast's frames"
}

/// What a press with this client cast id is given on this state.
type Pressed {
  Dropped
  Began(cast_state.State)
}

fn pressed_with(
  state state: State,
  client_cast_id client_cast_id: Int,
  at ms: Int,
) -> Pressed {
  let assert Ok(used) =
    used_with(
      tables: tables(),
      state:,
      caster: throwing(),
      held: Some(grenade),
      charges: 0,
      body: the_body(
        client_cast_id:,
        item: the_item_place,
        target_unit_id: its_unit,
      ),
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: ms,
    )
    as "the press is taken"
  case used {
    cast_state.Started(start:, ..) ->
      Began(cast.item_started(cast: state, start:, now: support.at(ms:)).0)
    cast_state.Frames(effects: [], ..) -> Dropped
    cast_state.Frames(..) -> panic as "a repeat or a start, not a refusal"
  }
}

pub fn a_resent_press_starts_nothing_and_spends_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Began(first) =
    pressed_with(state: cast_state.new(), client_cast_id: 9, at: 1000)
    as "the first press starts"
  // The client's ids rise with every cast and never reset (`0x140c1e71c`): an id not
  // above the highest taken is a repeat.
  assert pressed_with(state: first, client_cast_id: 9, at: 1001) == Dropped
    as "the same id at once is a repeat"
  assert pressed_with(state: first, client_cast_id: 9, at: 6000) == Dropped
    as "the same id after the cast is done is a repeat"
  assert pressed_with(state: first, client_cast_id: 5, at: 6000) == Dropped
    as "an id below the highest taken, never seen, is refused"
  assert case pressed_with(state: first, client_cast_id: 10, at: 6000) {
    Began(after) -> after.item_press_watermark == Some(10)
    Dropped -> False
  }
    as "an id one above the highest starts and raises it"
  assert case
    pressed_with(state: cast_state.new(), client_cast_id: 9, at: 6000)
  {
    Began(_) -> True
    Dropped -> False
  }
    as "an id whose start was never adopted (the save was refused) is a new press"
}

/// The grenade pressed at the shack 10.0 away on these tables at `pressed_ms`, whose cast
/// the store's answer makes at `answered_ms`: the state and effects of the cast.
fn grenade_made(
  tables tables: table_store.Tables,
  state state: State,
  client_cast_id client_cast_id: Int,
  pressed_ms pressed_ms: Int,
  answered_ms answered_ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(cast_state.Started(start:, ..)) =
    used_with(
      tables:,
      state:,
      caster: throwing(),
      held: Some(grenade),
      charges: 0,
      body: the_body(
        client_cast_id:,
        item: the_item_place,
        target_unit_id: its_unit,
      ),
      target: shown(creature_id: a_slaver_shack, metres: 10.0),
      at: pressed_ms,
    )
    as "the press passes its checks"
  cast.item_started(cast: state, start:, now: support.at(ms: answered_ms))
}

/// The cast a press checked at one time and made at the store's answer, later, is the cast
/// a press made then makes: its cooldowns, its start, the times its effects carry and the
/// nodes and ticks of the effects it lasts through all run from the answer. The rows are
/// the grenade (Spell4 26663, spellCoolDown 2000, castTime 0, which goes at once) with a
/// castTime of 1000 and none, on a caster that cast the generic item before (its cooldown
/// and global cooldown stay as they were), and with a heal over time on the caster (a
/// lasting effect and four ticks).
pub fn a_cast_made_at_the_answer_is_the_cast_a_press_made_then_makes_test() -> Nil {
  use <- owned_test.run(10_000)
  let delay_ms = 400
  list.each(
    [
      #(
        None,
        False,
        False,
        "an instant cast on a caster that cast nothing before",
      ),
      #(
        Some(1000),
        False,
        False,
        "a cast with a cast time, which a time left is counted from",
      ),
      #(
        None,
        True,
        False,
        "an instant cast after another item's cast, whose stamps stay",
      ),
      #(
        None,
        False,
        True,
        "an instant cast with a heal over time on the caster, whose lasting effect and ticks are stamped at the go",
      ),
    ],
    fn(row) {
      let #(cast_time_ms, after_another, heals, why) = row
      let changes = case cast_time_ms {
        Some(cast_time_ms) -> [#("castTime", Integer(cast_time_ms))]
        None -> []
      }
      let assert Ok(rows) =
        fixture_tables.change(
          rows: fixture_tables.rows(),
          table: "Spell4",
          id: 26_663,
          with: changes,
        )
        as "Spell4 26663 is in the fixture"
      let rows = case heals {
        True -> item_charge_support.with_a_heal_over_time(rows:)
        False -> rows
      }
      use tables <- fixture_tables.on_rows(rows:, reaching: [])
      let before = case after_another {
        True -> {
          let assert Ok(#(earlier, _)) =
            use_item_in(
              tables:,
              state: cast_state.new(),
              caster: throwing(),
              item: generic_item,
              target: shown(creature_id: a_farmhand, metres: 3.0),
              at: 0,
            )
            as "the earlier press is taken"
          earlier
        }
        False -> cast_state.new()
      }
      let made_at_the_answer =
        grenade_made(
          tables:,
          state: before,
          client_cast_id: 10,
          pressed_ms: 2000,
          answered_ms: 2000 + delay_ms,
        )
      let pressed_then =
        grenade_made(
          tables:,
          state: before,
          client_cast_id: 10,
          pressed_ms: 2000 + delay_ms,
          answered_ms: 2000 + delay_ms,
        )
      let made_at_the_press =
        grenade_made(
          tables:,
          state: before,
          client_cast_id: 10,
          pressed_ms: 2000,
          answered_ms: 2000,
        )
      assert made_at_the_answer == pressed_then as why
      assert made_at_the_answer != made_at_the_press
        as { "the answer's time shows in the cast: " <> why }
    },
  )
}

pub const loftite_railgun = 6938

pub const a_chua = 20_794

/// A player of level 50 who holds quest 3769 accepted with its objective open, which the
/// railgun's item row requires (`Item2.quest2IdActivationRequired`, `0x140398cc0`).
pub fn railgunner() -> cast_state.Caster {
  standing(
    level: 50,
    quests: quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 3769, progress: [0]),
    ]),
  )
}

type RailgunCase {
  RailgunCase(why: String, target: Target, refused: Option(Int))
}

/// What the railgun's cast at a Chua holds: no refusal, a go that lists none of the spell's
/// rows, no use of the Chua and the timer of row 89873.
fn railgun_started(effects effects: List(Effect), why why: String) -> Nil {
  assert support.refusal_results(effects:) == [] as why
  let assert [go_frame] =
    support.frames_of(message_id: spell_go.message_id, effects:)
    as "the cast's time is 0, so the go is written with the start"
  let assert Ok(go) = spell_go.decode(go_frame.body)
  assert list.flat_map(go.targets, fn(target) {
      list.map(target.effects, fn(info) { info.spell4_effects_id })
    })
    == []
    as "the go lists no effect of the type 42 rows, the despawn or the unread row"
  assert support.activated_count(
      effects:,
      unit_id: its_unit,
      creature_id: a_chua,
      by_item: True,
    )
    == 0
    as "the spell holds no Activate row, so the cast is no use of the Chua"
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    == [6000]
    as "the row 89873 waits its delayTime of 6000 ms"
}

pub fn an_item_spell_with_a_type_42_row_is_planned_and_cast_without_a_use_of_its_target_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 6938 -> ItemSpecial 3942 -> Spell4 24501: castTime 0, targetMaxRange 25.0, the cast
  // group TargetGroup 2125 ({Creature2 20794, 20795, 20798}); its rows are two type 42, a
  // DespawnUnit and a type 71, and none is an Activate row (type 7).
  list.each(
    [
      RailgunCase(
        "a Chua of the cast group within 25 m starts the cast",
        shown(creature_id: a_chua, metres: 10.0),
        None,
      ),
      RailgunCase(
        "a creature outside TargetGroup 2125 is refused 89",
        shown(creature_id: a_farmhand, metres: 10.0),
        Some(89),
      ),
      RailgunCase(
        "another player's unit is refused 100",
        activate.AnotherPlayer,
        Some(100),
      ),
      RailgunCase(
        "a unit the picture does not show is refused 91",
        activate.Unseen,
        Some(91),
      ),
    ],
    fn(row) {
      let assert Ok(#(_, effects)) =
        use_item_at(
          state: cast_state.new(),
          caster: railgunner(),
          item: loftite_railgun,
          target: row.target,
          at: 1000,
        )
        as row.why
      case row.refused {
        Some(result) -> {
          assert support.refused_with(effects:)
            == [#(clients_cast_id, 24_501, result)]
            as row.why
          Nil
        }
        None -> railgun_started(effects:, why: row.why)
      }
    },
  )
}

// Consumables: the spells items cast on their user (`shortcut_spell`), by the client's rows:
// - Item2 14838 (Basic Medishot: Instant Healing, power level 5, level 1 to use) -> Spell4
//   34985: castTime 0, cooldown group 130 (SpellCoolDown 130: 180,000 ms), globalCooldownEnum
//   3; its Heal row 69917 is parameter 18 x 200.0 (dataBits00 1.0, dataBits01 0).
// - Item2 49372 is the same spell at power level 60 (level 50 to use); the curve at 60 is
//   20.0 x e^(0.01 x 10) (GameFormula 65 at 60 - 50), 22.10, so 200 x it is 4,421.
// - Item2 37649 -> Spell4 34993: Heal row 69936 of 206 every 2,000 ms for 20,000 ms.
// - Item2 4730 -> Spell4 3792: a type 11 row 6403 of 900,000 ms, globalCooldownEnum 0.
// - Item2 14850 -> 35022 (row 69997, type 11 with a type 18 parameter, which the plan does not read), 13027 -> 28682 (row
//   49524, type 38), 2900 -> 1664 (Activate row 2530) and 90021 -> 87129 (rows holding the
//   suspend prerequisite 43393).
// - Item2 461 -> Spell4 28, a Targeted kind with no rows: the creature's activate cast has no
//   plan for it.
// - `opcode.0x7ff.caster_item_level`: an item's cast tells its item level, Item2.powerLevel;
//   `opcode.0x7ff.activate`: no item cast sets the creature-activate bit.

/// What an earlier input of the player did to the state.
type Earlier {
  /// Nothing.
  NothingEarlier
  /// An ability press at this time (bag index 0).
  AbilityAt(ms: Int)
  /// The use of this item at this time, which the stack's store answered at once.
  DrinkAt(item: Int, ms: Int)
}

/// What a consumable's use comes to.
type Comes {
  /// The cast starts at once and its go heals the caster by `amount`, the viewers told the
  /// item level `item_level` in the start.
  Heals(amount: Int, item_level: Int)
  /// The cast starts, and its first tick, due `first_tick_ms` after the press, heals `amount`.
  HealsEvery(amount: Int, first_tick_ms: Int)
  /// The cast starts and its go starts one property change on the caster.
  Buffs
  /// The press is refused with this result, and the stack is not spent.
  RefusedWith(result: Int)
  /// The press is refused 285 and logged once, the text naming these and no issue.
  NotBuilt(naming: List(String))
}

type Drink {
  Drink(
    why: String,
    item: Int,
    level: Int,
    press_target: Int,
    earlier: Earlier,
    at_ms: Int,
    comes: Comes,
  )
}

fn drinker(level level: Int) -> cast_state.Caster {
  standing(level:, quests: quest_support.log_of(rows: []))
}

fn after(earlier earlier: Earlier) -> State {
  case earlier {
    NothingEarlier -> cast_state.new()
    AbilityAt(ms:) ->
      support.pressed(state: cast_state.new(), bag_index: 0, target: 0, at: ms).0
    DrinkAt(item:, ms:) -> {
      let assert Ok(#(state, effects)) =
        use_item_at(
          state: cast_state.new(),
          caster: drinker(level: 50),
          item:,
          target: activate.Unseen,
          at: ms,
        )
        as "the earlier use is taken"
      support.answered_with_no_targets(state:, effects:, at: ms).0
    }
  }
}

fn drink_press(
  state state: State,
  case_ case_: Drink,
) -> Result(cast_state.Used, cast_state.Refusal) {
  used_with(
    tables: tables(),
    state:,
    caster: drinker(level: case_.level),
    held: Some(case_.item),
    charges: 1,
    body: the_body(
      client_cast_id: clients_cast_id + 1,
      item: the_item_place,
      target_unit_id: case_.press_target,
    ),
    target: activate.Unseen,
    at: case_.at_ms,
  )
}

pub fn a_consumables_use_is_decided_by_its_spell_test() -> Nil {
  use <- owned_test.run(20_000)
  list.each(
    [
      Drink(
        "Medishot at player level 1: 200 x the curve at its power level 5 (6.5)",
        14_838,
        1,
        0,
        NothingEarlier,
        1000,
        Heals(amount: 1300, item_level: 5),
      ),
      Drink(
        "the same Medishot at player level 50 heals the same: the player's level is not read",
        14_838,
        50,
        0,
        NothingEarlier,
        1000,
        Heals(amount: 1300, item_level: 5),
      ),
      Drink(
        "Medishot of power level 60: 200 x the curve at 60",
        49_372,
        50,
        0,
        NothingEarlier,
        1000,
        Heals(amount: 4421, item_level: 60),
      ),
      Drink(
        "a press naming a unit starts the same: the target is not read for a Caster kind",
        14_838,
        1,
        its_unit,
        NothingEarlier,
        1000,
        Heals(amount: 1300, item_level: 5),
      ),
      Drink(
        "the heal over time: Spell4Effects 69936 heals 206 a tick, the first 2,000 ms after its delay of 2,000",
        37_649,
        1,
        0,
        NothingEarlier,
        1000,
        HealsEvery(amount: 206, first_tick_ms: 4000),
      ),
      Drink(
        "the buff starts one property change",
        4730,
        1,
        0,
        NothingEarlier,
        1000,
        Buffs,
      ),
      Drink(
        "the buff potion 50 ms after another is refused 14: its globalCooldownEnum 0 starts the global cooldown and is held back by it, and a refusal leaves the stack unspent",
        4730,
        1,
        0,
        DrinkAt(item: 4730, ms: 1000),
        1050,
        RefusedWith(result: 14),
      ),
      Drink(
        "a second Medishot 1 s after the first is refused 16: its go started the group 130 for SpellCoolDown 130's 180,000 ms (0x14046b1e0), and the refusal leaves the stack unspent",
        14_838,
        1,
        0,
        DrinkAt(item: 14_838, ms: 1000),
        2000,
        RefusedWith(result: 16),
      ),
      Drink(
        "another Medishot item of the same spell 1 s after is refused 16 too: the group is the spell's, not the item's",
        49_372,
        50,
        0,
        DrinkAt(item: 14_838, ms: 1000),
        2000,
        RefusedWith(result: 16),
      ),
      Drink(
        "a Medishot when the group's 180,000 ms have run out is taken: 1000 + 180,000",
        49_372,
        50,
        0,
        DrinkAt(item: 14_838, ms: 1000),
        181_000,
        Heals(amount: 4421, item_level: 60),
      ),
      Drink(
        "Medishot 50 ms after an ability press: its globalCooldownEnum 3 passes a global cooldown",
        14_838,
        1,
        0,
        AbilityAt(ms: 1000),
        1050,
        Heals(amount: 1300, item_level: 5),
      ),
      Drink(
        "a type 11 row with a type 18 parameter is not built: the spell cannot be planned",
        14_850,
        50,
        0,
        NothingEarlier,
        1000,
        NotBuilt([
          "UnitPropertyModifier effect 69997 with a parameter of type 18",
        ]),
      ),
      Drink(
        "a type 38 row is not built",
        13_027,
        50,
        0,
        NothingEarlier,
        1000,
        NotBuilt(["49524", "type 38"]),
      ),
      Drink(
        "an Activate row is not built (it was 91)",
        2900,
        50,
        0,
        NothingEarlier,
        1000,
        NotBuilt(["2530", "Activate"]),
      ),
      Drink(
        "a row holding a suspend prerequisite is not built",
        90_021,
        50,
        0,
        NothingEarlier,
        1000,
        NotBuilt(["227562", "43393"]),
      ),
    ],
    fn(case_) {
      let before = after(earlier: case_.earlier)
      let used = drink_press(state: before, case_:)
      case case_.comes {
        Heals(amount:, item_level:) -> {
          let #(state, effects) = started(used:, before:, case_:)
          assert state.global_cooldown_ends_ms == before.global_cooldown_ends_ms
            as "no global cooldown starts: globalCooldownEnum 3"
          assert list.map(support.caster_change_starts(effects:), fn(start) {
              start.1
            })
            == [cast_state.Heal(vital: effect_kind.Health, amount:)]
            as case_.why
          assert support.refusal_results(effects:) == [] as case_.why
          let assert [#(_, CastStarted(start: started))] =
            list.take(support.tells(effects:), 1)
            as case_.why
          assert started.creature_activate == 0 as case_.why
          assert started.caster_item_level == item_level as case_.why
          assert support.started_timers(effects:) == [] as case_.why
        }
        HealsEvery(amount:, first_tick_ms:) -> {
          let #(state, effects) = started(used:, before:, case_:)
          assert first_tick_heals(
              state:,
              effects:,
              case_:,
              first_tick_ms:,
              caster: drinker(level: case_.level),
            )
            == [cast_state.Heal(vital: effect_kind.Health, amount:)]
            as case_.why
        }
        Buffs -> {
          let #(_, effects) = started(used:, before:, case_:)
          assert list.length(support.property_starts(effects:)) == 1
            as case_.why
        }
        RefusedWith(result:) -> {
          let assert Ok(cast_state.Frames(effects:, ..)) = used as case_.why
          assert list.map(support.refused_with(effects:), fn(refusal) {
              refusal.2
            })
            == [result]
            as case_.why
        }
        NotBuilt(naming:) -> {
          let assert Ok(cast_state.Frames(effects:, ..)) = used as case_.why
          assert list.map(support.refused_with(effects:), fn(refusal) {
              refusal.2
            })
            == [285]
            as case_.why
          let assert [#(LogWarning, line)] = support.logs(effects:) as case_.why
          assert string.ends_with(line, ": it is refused with 285")
            && !string.contains(line, "#")
            as case_.why
          assert list.all(naming, fn(word) { string.contains(line, word) })
            as case_.why
        }
      }
    },
  )
}

/// The state and effects of the cast a passed press starts, made at the press's own time,
/// its go answered as a round that struck nobody.
fn started(
  used used: Result(cast_state.Used, cast_state.Refusal),
  before before: State,
  case_ case_: Drink,
) -> #(State, List(Effect)) {
  let assert Ok(cast_state.Started(start:, ..)) = used as case_.why
  let #(state, effects) =
    cast.item_started(cast: before, start:, now: support.at(ms: case_.at_ms))
  support.answered_with_no_targets(state:, effects:, at: case_.at_ms)
}

/// What the cast's first tick heals the caster by: the timer due `first_tick_ms` after the
/// press is fired at its time.
fn first_tick_heals(
  state state: State,
  effects effects: List(Effect),
  case_ case_: Drink,
  first_tick_ms first_tick_ms: Int,
  caster caster: cast_state.Caster,
) -> List(cast_state.CasterChange) {
  let assert [#(timer, _)] =
    list.filter(support.started_timers(effects:), fn(timer) {
      timer.1 == first_tick_ms
    })
    as case_.why
  let #(_, ticked) =
    support.fired_raw_as(
      caster:,
      state:,
      timer:,
      at: case_.at_ms + first_tick_ms,
    )
  list.map(support.caster_change_starts(effects: ticked), fn(start) { start.1 })
}

pub fn a_heal_over_time_with_a_type_18_parameter_ticks_by_the_items_level_test() -> Nil {
  use <- owned_test.run(20_000)
  // Spell4Effects 69936 given Medishot's formula, parameter 18 x 200 with no base: Item2
  // 37649 has power level 15, where the curve is 5.0 + 0.3 x 15 = 9.5 (GameFormula 991), so a
  // tick heals 1,900 whatever the player's level.
  use edited <- fixture_tables.changed(
    table: "Spell4Effects",
    id: 69_936,
    with: [
      #("dataBits01", Integer(0)),
      #("parameterType00", Integer(18)),
      #("parameterValue00", planted_table.Float(200.0)),
    ],
  )
  let case_ =
    Drink(
      "a tick of the heal over time",
      37_649,
      1,
      0,
      NothingEarlier,
      1000,
      HealsEvery(amount: 1900, first_tick_ms: 4000),
    )
  let used =
    used_with(
      tables: edited,
      state: cast_state.new(),
      caster: drinker(level: 1),
      held: Some(37_649),
      charges: 1,
      body: the_body(
        client_cast_id: clients_cast_id,
        item: the_item_place,
        target_unit_id: 0,
      ),
      target: activate.Unseen,
      at: 1000,
    )
  let #(state, effects) = started(used:, before: cast_state.new(), case_:)
  assert first_tick_heals(
      state:,
      effects:,
      case_:,
      first_tick_ms: 4000,
      caster: drinker(level: 1),
    )
    == [cast_state.Heal(vital: effect_kind.Health, amount: 1900)]
    as "each tick reads the passed-in value at the item's level, not the player's"
}

pub fn a_child_an_items_cast_starts_heals_by_the_items_level_test() -> Nil {
  use <- owned_test.run(20_000)
  // Spell4Effects 6403, the buff potion's row (Item2 4730, power level 15), made a Proxy
  // aimed at the caster that starts Medishot's Spell4 34985, whose Heal row 69917 is
  // parameter 18 x 200: at the item's level, the curve at 15 is 9.5 (GameFormula 991), so
  // the child heals 1,900 whatever the player's level (1 would give 200 x 5.3 = 1,060).
  use edited <- fixture_tables.changed(table: "Spell4Effects", id: 6403, with: [
    #("effectType", Integer(26)),
    #("dataBits00", Integer(34_985)),
    #("dataBits01", Integer(0)),
    #("dataBits02", Integer(0)),
    #("dataBits03", Integer(0)),
    #("durationTime", Integer(0)),
  ])
  let case_ =
    Drink(
      "the child of the buff potion's cast",
      4730,
      1,
      0,
      NothingEarlier,
      1000,
      Buffs,
    )
  let used =
    used_with(
      tables: edited,
      state: cast_state.new(),
      caster: drinker(level: 1),
      held: Some(4730),
      charges: 1,
      body: the_body(
        client_cast_id: clients_cast_id,
        item: the_item_place,
        target_unit_id: 0,
      ),
      target: activate.Unseen,
      at: 1000,
    )
  let #(_, effects) = started(used:, before: cast_state.new(), case_:)
  assert list.map(support.caster_change_starts(effects:), fn(start) { start.1 })
    == [cast_state.Heal(vital: effect_kind.Health, amount: 1900)]
    as "the Proxy's child reads the passed-in value at the item's level, as the item's own cast does"
  assert list.unique(
      list.map(
        game_connection_support.cast_starts(
          list.map(support.tells(effects:), fn(tell) { tell.1 }),
        ),
        fn(start) { start.caster_item_level },
      ),
    )
    == [15]
    as "opcode.0x7ff.caster_item_level: every start of the item's cast, its child's too, tells the item's level 15, since its buff reads its tooltip at that level"
}

pub fn an_item_spell_with_no_activate_effect_is_refused_285_and_logged_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let no_target = activate.Unseen
  let assert Ok(#(state, first)) =
    use_item_at(
      state: cast_state.new(),
      caster: drinker(level: 50),
      item: a_spell_at_a_unit_with_no_rows,
      target: no_target,
      at: 1000,
    )
    as "the first use is answered"
  let assert Ok(#(_, second)) =
    use_item_at(
      state:,
      caster: drinker(level: 50),
      item: a_spell_at_a_unit_with_no_rows,
      target: no_target,
      at: 2000,
    )
    as "the second use is answered"
  assert support.refused_with(effects: first) == [#(clients_cast_id, 28, 285)]
    as "Spell4 28 is cast at a unit and has no Activate and no QuestAdvanceObjective row, which is all the creature's activate cast plays: IllegalSpellCast (285)"
  assert support.refused_with(effects: second) == [#(clients_cast_id, 28, 285)]
    as "the second use is refused the same"
  let assert [#(LogWarning, line)] =
    list.append(support.logs(effects: first), support.logs(effects: second))
    as "the gap is logged once"
  assert string.contains(line, "Spell4 28") as "the log line names the spell"
  assert string.ends_with(line, ": it is refused with 285")
    && !string.contains(line, "#")
    as "and what is missing, with no issue named"
}

pub fn using_rations_gives_80_focus_at_a_go_of_their_channel_to_a_healer_test() -> Nil {
  use <- owned_test.run(20_000)
  // Item2 6914 (Rations) -> ItemSpecial 7476 -> Spell4 34776 (Basic Food): a channel (delay
  // 1000, maximum 10000, pulse 1000) whose row 88371 gives 80 points of Focus, vital 15 (text
  // 270070 prints its 80 as "... Focus every second while channeling"). A Medic uses it, and
  // the gains of its first go, applied to 500 of its Focus, hold 580.
  let rations = Drink("Rations", 6914, 1, 0, NothingEarlier, 1000, Buffs)
  let healer =
    cast_state.Caster(
      ..drinker(level: 1),
      resources: support.holding_focus(class_id: 4, focus: 1000.0),
    )
  let #(state, effects) =
    started(
      used: drink_press(state: cast_state.new(), case_: rations),
      before: cast_state.new(),
      case_: rations,
    )
  assert support.refusal_results(effects:) == [] as "the Rations are used"
  let #(_, fired) =
    support.run_timers_each(
      caster: healer,
      state:,
      effects:,
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  let gaining =
    list.filter_map(fired, fn(step) {
      case support.gains(effects: step.1) {
        [] -> Error(Nil)
        gains -> Ok(#(step.0, gains))
      }
    })
  let assert [#(first_go_ms, first_gains), ..] = gaining
    as "a go of the channel gives"
  assert first_go_ms == 2000
    as "the first go is the channel's delay of 1000 ms after the press"
  assert list.all(gaining, fn(go) {
    go.1 == [[class_resource.Gain(slot: class_resource.focus_slot, amount: 80)]]
  })
    as "every go gives 80 points of Focus"
  let #(_, changes) =
    class_resource.gain(
      resources: class_resource.paid(resources: healer.resources, payments: [
        class_resource.Payment(slot: -1, amount: 500),
      ]),
      gains: list.flatten(first_gains),
    )
  assert list.first(changes)
    == Ok(class_resource.Changed(slot: class_resource.focus_slot, value: 580.0))
    as "a healer holding 500 Focus holds 580: one 0x935 of stat 1"
}
