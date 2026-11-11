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
//// - Item2 21966 -> ItemSpecial 5410 -> Spell4 41914, whose one effect, Spell4Effects 94446, is a
////   RavelSignal: no Activate row, so the server has no plan for it.
//// - `opcode.0x97.range` (`0x1403b2240`): the gap between the units' edges is held to the
////   spell's limits.
//// - `opcode.0x7fc`: the refusal carries the client's cast id, the spell and the result.

import cast_support as support
import fixture_tables
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/activate.{type Target, Body, NoLink, Usable}
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/item_use
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/target_group
import genesis_prime/message/cast_result
import genesis_prime/message/item_place.{type ItemPlace, ItemPlace}
import genesis_prime/message/item_use.{ItemUse} as use_message
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_go
import genesis_prime/step.{LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Faction2Id, Item2Id, UnitRaceId}
import genesis_prime/table/loader/store as table_store
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import owned_test
import place_support
import planted_table.{Integer}
import quest_support

const grenade = 12_444

const generic_item = 12_402

const objective_item = 21_966

/// Item2 2509, whose maxCharges is 99 and whose spell 1274 has an Activate effect.
const charged_item = 2509

const grenade_quest = 4743

const security_quest = 7833

const a_slaver_shack = 17_397

const a_farmhand = 17_107

const its_unit = 5000

const clients_cast_id = 9

/// The place of the item the player uses.
const the_item_place = ItemPlace(location: 1, bag_index: 0)

// Hit radii of exactly representable size: the player's and the unit's.
const caster_radius = 0.5

const object_radius = 0.25

fn tables() -> table_store.Tables {
  fixture_tables.shared()
}

/// A level 20 player who holds quest 4743, accepted.
fn throwing() -> cast.Caster {
  standing(
    level: 20,
    quests: quest_support.log_of(rows: [
      quest_support.accepted(quest_id: grenade_quest, progress: [0, 0, 0, 0]),
    ]),
  )
}

/// The caster stands at a place of exactly representable numbers.
fn standing(level level: Int, quests quests: QuestLog) -> cast.Caster {
  let caster = support.caster()
  cast.Caster(
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

fn creature_of(creature_id creature_id: Int) -> activate.Creature {
  let assert Ok(row) =
    creature2.get(tables: tables(), id: Creature2Id(creature_id))
    as "the creature is a root of the fixture"
  activate.creature_of(row:)
}

/// A creature standing this far from the caster, edge to edge.
fn shown(creature_id creature_id: Int, metres metres: Float) -> Target {
  Usable(
    creature_id:,
    creature: creature_of(creature_id:),
    checklist_index: 0,
    link: NoLink,
    body: Body(
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 4096.0 +. metres +. caster_radius +. object_radius,
        y: 0.0,
        z: 512.0,
      ),
      radius: object_radius,
    ),
    alive: True,
    withheld: None,
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
fn use_with(
  tables tables: table_store.Tables,
  state state: State,
  caster caster: cast.Caster,
  held held: Option(Int),
  body body: BitArray,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  cast.use_item(
    cast: state,
    body:,
    caster:,
    held_at: fn(place) {
      case place == the_item_place, held {
        True, Some(item) -> Some(Item2Id(item))
        _, _ -> None
      }
    },
    check: fn(item, second_item, target_checklist_index, prerequisite) {
      item_use.check(
        tables:,
        item:,
        player_level: caster.player.level,
        quests: caster.quests,
        second_item:,
        target_checklist_index:,
        prerequisite:,
      )
    },
    activations: activate.activations(tables:),
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

/// The use of item `item`, held at its place, at the unit `its_unit`.
fn use_item_at(
  state state: State,
  caster caster: cast.Caster,
  item item: Int,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  use_item_in(tables: tables(), state:, caster:, item:, target:, at: ms)
}

/// The use of item `item` as `use_item_at` does, on these tables.
fn use_item_in(
  tables tables: table_store.Tables,
  state state: State,
  caster caster: cast.Caster,
  item item: Int,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
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

/// What the effects refuse: each 0x7fc's cast id, spell and result.
fn refused_with(effects effects: List(Effect)) -> List(#(Int, Int, Int)) {
  list.map(
    support.frames_of(message_id: spell_cast_refused.message_id, effects:),
    fn(frame) {
      let assert Ok(refused) = spell_cast_refused.decode(frame.body)
        as "a 0x7fc the rule wrote decodes"
      #(
        refused.client_cast_id,
        refused.spell4_id,
        cast_result.to_value(refused.result),
      )
    },
  )
}

/// The use is taken, and answered with the one refusal and nothing else.
fn refusal_of(
  taken taken: Result(#(State, List(Effect)), cast.Refusal),
) -> #(Int, Int) {
  let assert Ok(#(_, effects)) = taken as "an item use that fits is answered"
  let assert [#(cast_id, spell4_id, result)] = refused_with(effects:)
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
      state: cast.new(),
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
    == Error(cast.NoClientCastId)
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
  let assert Error(cast.NotDecoded(..)) =
    use_with(
      tables: tables(),
      state: cast.new(),
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
  let state = cast.new()
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
  assert refused_with(effects:) == [#(clients_cast_id, 0, 22)]
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
      state: cast.new(),
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
    == Error(cast.NoItemSpell)
    as "UseItem 0x1403998e0 sends no 0x943 for an item with no spell (it answers 0x35b or 0x17), so a held item with none is not the client's"
  Nil
}

pub fn the_grenade_at_a_slaver_shack_starts_the_activate_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast.new(),
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

pub fn the_grenade_go_raises_activated_for_the_shack_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast.new(),
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
  let activated =
    cast.Activated(
      unit_id: its_unit,
      creature_id: a_slaver_shack,
      alive_at_press: True,
      by_item: True,
    )
  assert list.count(effects, fn(effect) { effect == activated }) == 1
    as "the go raises Activated for the shack once, marked as an item's cast"
}

pub fn the_grenade_at_a_unit_outside_its_cast_group_is_refused_89_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refusal_of(taken: use_item_at(
      state: cast.new(),
      caster: throwing(),
      item: grenade,
      target: shown(creature_id: a_farmhand, metres: 10.0),
      at: 1000,
    ))
    == #(26_663, 89)
    as "Spell4Base 13157's cast group is TargetGroup 1691, which does not hold Creature2 17107: CheckCastActivateSpell (0x1403b44b0) refuses it 89 (TargetGroup), with the item's spell"
}

pub fn the_grenade_at_another_players_unit_is_refused_100_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refusal_of(taken: use_item_at(
      state: cast.new(),
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
      state: cast.new(),
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
      state: cast.new(),
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
      state: cast.new(),
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
      state: cast.new(),
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
      state: cast.new(),
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
      state: cast.new(),
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
      state: cast.new(),
      caster: throwing(),
      item: grenade,
      target: shown(creature_id: a_slaver_shack, metres:),
      at: 1000,
    )
    as "the use is answered"
  case refused_with(effects:) {
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
      state: cast.new(),
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
      state: cast.new(),
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
  let assert [unread, ..] = unread_types()
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
  let #(state, first) = thrown(cast.new(), 1000)
  let #(_, second) = thrown(state, 2000)
  assert refused_with(effects: first) == [#(clients_cast_id, 26_663, 285)]
    && refused_with(effects: second) == [#(clients_cast_id, 26_663, 285)]
    as "a prerequisite of a type the server does not read cannot be judged: IllegalSpellCast (285), each time"
  let assert [#(LogWarning, line)] =
    list.append(support.logs(effects: first), support.logs(effects: second))
    as "the gap is logged once"
  assert string.contains(line, "type " <> int.to_string(unread))
    as "the log line names the type"
}

/// Condition types below 301 the server does not read, lowest first.
fn unread_types() -> List(Int) {
  int.range(from: 300, to: 0, with: [], run: fn(unread, type_id) {
    case prerequisite.is_read(type_id:) {
      True -> unread
      False -> [type_id, ..unread]
    }
  })
}

pub fn an_item_with_charges_is_refused_285_and_logged_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = standing(level: 50, quests: quest_support.log_of(rows: []))
  let no_target = activate.Unseen
  let assert Ok(#(state, first)) =
    use_item_at(
      state: cast.new(),
      caster:,
      item: charged_item,
      target: no_target,
      at: 1000,
    )
    as "the first use is answered"
  let assert Ok(#(_, second)) =
    use_item_at(
      state:,
      caster:,
      item: charged_item,
      target: no_target,
      at: 2000,
    )
    as "the second use is answered"
  assert refused_with(effects: first) == [#(clients_cast_id, 1274, 285)]
    && refused_with(effects: second) == [#(clients_cast_id, 1274, 285)]
    as "Item2 2509 has maxCharges 99, which StartItemUseCast (0x140398cc0) tests first with 25 and the server does not hold (#333): IllegalSpellCast (285), with the item's spell 1274"
  let assert [#(LogWarning, line)] =
    list.append(support.logs(effects: first), support.logs(effects: second))
    as "the gap is logged once"
  assert string.contains(line, "2509") as "the log line names the item"
}

pub fn the_grenade_again_within_its_2_s_cooldown_is_refused_15_test() -> Nil {
  use <- owned_test.run(10_000)
  let target = shown(creature_id: a_slaver_shack, metres: 10.0)
  let assert Ok(#(state, first)) =
    use_item_at(
      state: cast.new(),
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
  assert refusal_of(taken: use_item_at(
      state:,
      caster: throwing(),
      item: grenade,
      target:,
      at: 2499,
    ))
    == #(26_663, 15)
    as "1499 ms after the cooldown started, 501 of Spell4 26663's spellCoolDown 2000 are left: SpellCooldown (15)"
  let assert Ok(#(_, again)) =
    use_item_at(state:, caster: throwing(), item: grenade, target:, at: 3000)
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

pub fn an_item_spell_with_no_activate_effect_is_refused_285_and_logged_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster =
    standing(
      level: 50,
      quests: quest_support.log_of(rows: [
        quest_support.active(
          quest_id: security_quest,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 0b1,
          progress: [1, 0],
        ),
      ]),
    )
  let no_target = activate.Unseen
  let assert Ok(#(state, first)) =
    use_item_at(
      state: cast.new(),
      caster:,
      item: objective_item,
      target: no_target,
      at: 1000,
    )
    as "the first use is answered"
  let assert Ok(#(_, second)) =
    use_item_at(
      state:,
      caster:,
      item: objective_item,
      target: no_target,
      at: 2000,
    )
    as "the second use is answered"
  assert refused_with(effects: first) == [#(clients_cast_id, 41_914, 285)]
    as "Spell4 41914's one effect, Spell4Effects 94446, is a RavelSignal: the server has no plan for it (#334): IllegalSpellCast (285)"
  assert refused_with(effects: second) == [#(clients_cast_id, 41_914, 285)]
    as "the second use is refused the same"
  let assert [#(LogWarning, line)] =
    list.append(support.logs(effects: first), support.logs(effects: second))
    as "the gap is logged once"
  assert string.contains(line, "41914") as "the log line names the spell"
}

pub fn the_generic_quest_spell_item_at_a_farmhand_starts_within_5_m_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = standing(level: 20, quests: quest_support.log_of(rows: []))
  let assert Ok(#(_, effects)) =
    use_item_at(
      state: cast.new(),
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
  assert list.contains(
    effects,
    cast.Activated(
      unit_id: its_unit,
      creature_id: a_farmhand,
      alive_at_press: True,
      by_item: True,
    ),
  )
    as "the go raises Activated for the farmhand"
  assert refusal_of(taken: use_item_at(
      state: cast.new(),
      caster:,
      item: generic_item,
      target: shown(creature_id: a_farmhand, metres: 5.5),
      at: 1000,
    ))
    == #(1545, 105)
    as "a gap of 5.5 is beyond Spell4 1545's 5.0: TargetRangeMax (105)"
}
