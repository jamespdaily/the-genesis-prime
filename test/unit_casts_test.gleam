//// The casts a unit create lists (`genesis_prime/game/unit_casts`). Expected
//// values come from `opcode.0x262.casts` (the entry's fields and the 9-bit
//// count), `cast.state` (the entry's bit is state 2 for 1 and state 3 for 0),
//// `CreateCast 0x140561780` (a cast id 0 is a pending cast, which makes
//// `ApplyUnitCreateCasts 0x140458fe0` fail and skip the rest of the list),
//// `opcode.0x7f4.effect_delay` and `opcode.0x7f4.effect_time` (an effect info's
//// delay is the delay still to run and its lifetime the time left, 0 only for an
//// effect that lasts until removed) and `opcode.0x7f4.instance_count` (a count of 0
//// still makes the node and a buff of 0 stacks). The effect rows are the client's
//// Spell4Effects rows, each named where it is used.

import genesis_prime/game/lasting.{LastingRow, LifeOnly, Listed, Node}
import genesis_prime/game/unit_casts.{
  type CastView, CastView, HeldEffect, UntilRemoved, ViewTarget,
}
import genesis_prime/message/combat_result
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{
  type SpellEffectInfo, SpellEffectInfo,
}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_target_info.{
  type SpellTargetInfo, SpellTargetInfo,
}
import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import owned_test

fn view(cast_id cast_id: Int) -> CastView {
  CastView(
    caster_unit_id: 21,
    cast_id:,
    spell4_id: Spell4Id(32_893),
    primary_target: 22,
    gone: False,
    current: True,
    targets: [],
  )
}

fn entry(cast_id cast_id: Int, started started: Int) -> UnitCreateCast {
  UnitCreateCast(
    caster_unit_id: 21,
    primary_target_unit_id: 22,
    cast_id:,
    spell4_id: 32_893,
    started:,
    targets: [],
    initial_positions: [],
    telegraph_positions: [],
  )
}

pub fn an_entry_names_its_cast_and_state_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "a cast whose first go has not gone is started (bit 1)",
        view(cast_id: 7),
        entry(cast_id: 7, started: 1),
      ),
      #(
        "a cast whose first go has gone is gone (bit 0)",
        CastView(..view(cast_id: 7), gone: True),
        entry(cast_id: 7, started: 0),
      ),
      #(
        "the caster, the primary target and the Spell4 id are the cast's",
        CastView(
          caster_unit_id: 5,
          cast_id: 9,
          spell4_id: Spell4Id(100),
          primary_target: 6,
          gone: False,
          current: True,
          targets: [],
        ),
        UnitCreateCast(
          ..entry(cast_id: 9, started: 1),
          caster_unit_id: 5,
          primary_target_unit_id: 6,
          spell4_id: 100,
        ),
      ),
    ],
    fn(row) {
      assert unit_casts.entry_of(row.1, now_ms: 0) == Ok(row.2) as row.0
    },
  )
}

pub fn entries_come_in_cast_id_order_stop_at_511_and_never_carry_id_0_test() -> Nil {
  use <- owned_test.run(5000)
  let ids = fn(views) {
    list.map(unit_casts.entries_of(views, now_ms: 0), fn(entry) {
      entry.cast_id
    })
  }
  assert ids([view(cast_id: 30), view(cast_id: 10), view(cast_id: 20)])
    == [10, 20, 30]
    as "entries are in cast id order"
  let many =
    list.index_map(list.repeat(Nil, 600), fn(_, index) {
      view(cast_id: 600 - index)
    })
  assert list.length(ids(many)) == 511
    as "a list holds 511 entries at most (its count is 9 bits)"
  assert ids(many) == list.sort(ids(many), int.compare)
    as "the entries are sorted by cast id"
  assert list.first(ids(many)) == Ok(1) as "the 511 are the lowest cast ids"
  assert list.last(ids(many)) == Ok(511) as "the 511 are the lowest cast ids"
  assert ids([view(cast_id: 0), view(cast_id: 4)]) == [4]
    as "a view with cast id 0 gives no entry"
  assert result.is_error(unit_casts.entry_of(view(cast_id: 0), now_ms: 0))
    as "a cast id 0 is refused by name"
  assert ids([CastView(..view(cast_id: 5), current: False), view(cast_id: 6)])
    == [6]
    as "a view that is not the current cast and holds no target is left out"
  let buff =
    ViewTarget(unit_id: 21, count: 1, effects: [
      HeldEffect(
        effect_id: Spell4EffectsId(96_819),
        starts_ms: 1000,
        ends: UntilRemoved,
      ),
    ])
  assert ids([
      CastView(..view(cast_id: 5), current: False, targets: [buff]),
      view(cast_id: 6),
    ])
    == [5, 6]
    as "a view that is not the current cast but holds a target is listed"
}

// ---- the targets of an entry ----

/// The node of unit 7 armed by the go at 1000 with these effects, count 1.
fn node(effects effects: List(lasting.NodeEffect)) -> lasting.Node {
  Node(
    unit_id: 7,
    count: 1,
    life: lasting.UntilRemoved,
    effects:,
    armed_ms: 1000,
    held_until_ms: None,
  )
}

/// The view of a current cast with these nodes as targets (a node with no listed effect
/// with a life is no target).
fn view_of_nodes(
  nodes nodes: List(lasting.Node),
  longer_of longer_of: Bool,
) -> CastView {
  CastView(
    ..view(cast_id: 7),
    targets: list.filter_map(nodes, fn(node) {
      unit_casts.target_of(node:, longer_of_delay_and_duration: longer_of)
    }),
  )
}

fn targets_at(
  view view: CastView,
  now_ms now_ms: Int,
) -> List(SpellTargetInfo) {
  let assert Ok(entry) = unit_casts.entry_of(view, now_ms:)
    as "a cast id above 0 has an entry"
  entry.targets
}

/// The info of an effect that tells no value (the bit's value is read by no client code).
fn info(
  effect_id effect_id: Int,
  instance_id instance_id: Int,
  delay_ms delay_ms: Int,
  lifetime_ms lifetime_ms: Int,
) -> SpellEffectInfo {
  SpellEffectInfo(
    spell4_effects_id: effect_id,
    instance_id:,
    delay_ms:,
    lifetime_ms:,
    result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
  )
}

fn target(
  unit_id unit_id: Int,
  index index: Int,
  count count: Int,
  effects effects: List(SpellEffectInfo),
) -> SpellTargetInfo {
  SpellTargetInfo(
    unit_id:,
    index:,
    flags: 0,
    instance_count: count,
    combat_result: combat_result.Hit,
    effects:,
  )
}

/// Spell4Effects 67777 of Gate (34355): type 11, delay 180, duration 400, flags 0.
fn gate_row() -> lasting.NodeEffect {
  Listed(
    effect_id: Spell4EffectsId(67_777),
    row: LastingRow(delay_ms: 180, duration_ms: 400, until_removed: False),
  )
}

/// Spell4Effects 96819 of Power Charge (42569): type 17, no delay, no duration, flags 2
/// (until removed).
fn power_charge_row() -> lasting.NodeEffect {
  Listed(
    effect_id: Spell4EffectsId(96_819),
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
  )
}

pub fn an_entry_lists_each_held_effect_with_its_delay_and_time_left_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "an effect still in its delay: Gate's row 67777 (delay 180, duration 400), 100 ms after the go, has 80 ms of delay to run and, from now, 480 ms to live",
        [gate_row()],
        False,
        1100,
        [
          info(
            effect_id: 67_777,
            instance_id: 1,
            delay_ms: 80,
            lifetime_ms: 480,
          ),
        ],
      ),
      #(
        "an effect past its end on a node that stays is listed with lifetime 1, since 0 plays the row's own time again",
        [gate_row()],
        False,
        2000,
        [info(effect_id: 67_777, instance_id: 1, delay_ms: 0, lifetime_ms: 1)],
      ),
      #(
        "an effect that lasts until removed (Power Charge's row 96819, flags 2) has delay 0 and lifetime 0",
        [power_charge_row()],
        False,
        1100,
        [info(effect_id: 96_819, instance_id: 1, delay_ms: 0, lifetime_ms: 0)],
      ),
      #(
        "for a spell with the longer-of flag the end is the larger of delay and duration, 400, so 300 ms are left",
        [gate_row()],
        True,
        1100,
        [
          info(
            effect_id: 67_777,
            instance_id: 1,
            delay_ms: 80,
            lifetime_ms: 300,
          ),
        ],
      ),
    ],
    fn(row) {
      let #(reason, effects, longer_of, now_ms, expected) = row
      assert targets_at(
          view: view_of_nodes(nodes: [node(effects:)], longer_of:),
          now_ms:,
        )
        == [target(unit_id: 7, index: 0, count: 1, effects: expected)]
        as reason
    },
  )
  // Spell4 38784 holds the cooldown modifier row 159128 (type 73, delay 0, duration 0) beside
  // the proc row 178239 (type 14, 3000 ms): the node holds both, and only the proc has a life.
  let cooldown_row =
    Listed(
      effect_id: Spell4EffectsId(159_128),
      row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
    )
  let proc_row =
    Listed(
      effect_id: Spell4EffectsId(178_239),
      row: LastingRow(delay_ms: 0, duration_ms: 3000, until_removed: False),
    )
  assert targets_at(
      view: view_of_nodes(
        nodes: [node(effects: [cooldown_row, proc_row])],
        longer_of: False,
      ),
      now_ms: 1100,
    )
    == [
      target(unit_id: 7, index: 0, count: 1, effects: [
        info(effect_id: 178_239, instance_id: 1, delay_ms: 0, lifetime_ms: 2900),
      ]),
    ]
    as "an effect with neither delay nor duration is left out of the entry"
}

pub fn an_entry_lists_the_target_a_node_makes_test() -> Nil {
  use <- owned_test.run(5000)
  let held = fn(count) { Node(..node(effects: [power_charge_row()]), count:) }
  let power_charge = fn(count) {
    [
      target(unit_id: 7, index: 0, count:, effects: [
        info(effect_id: 96_819, instance_id: 1, delay_ms: 0, lifetime_ms: 0),
      ]),
    ]
  }
  assert targets_at(
      view: view_of_nodes(nodes: [held(1)], longer_of: False),
      now_ms: 1100,
    )
    == power_charge(1)
    as "a node's count is its cast's own: a cast that gave 1 stack lists a count of 1"
  assert targets_at(
      view: view_of_nodes(nodes: [held(0)], longer_of: False),
      now_ms: 1100,
    )
    == power_charge(0)
    as "a node stacked off to count 0 lists 0 stacks, and the buff is still made"
  let two_units = [
    node(effects: [power_charge_row(), gate_row()]),
    Node(..node(effects: [power_charge_row(), gate_row()]), unit_id: 8),
  ]
  assert list.map(
      targets_at(
        view: view_of_nodes(nodes: two_units, longer_of: False),
        now_ms: 1100,
      ),
      fn(target) {
        #(
          target.unit_id,
          target.index,
          target.flags,
          target.combat_result,
          list.map(target.effects, fn(effect) { effect.instance_id }),
        )
      },
    )
    == [
      #(7, 0, 0, combat_result.Hit, [1, 2]),
      #(8, 1, 0, combat_result.Hit, [1, 2]),
    ]
    as "each target is indexed by its place in the list with flags 0 and a Hit, its effects numbered from 1 per target"
  let restriction =
    LifeOnly(row: LastingRow(
      delay_ms: 0,
      duration_ms: 5000,
      until_removed: False,
    ))
  assert targets_at(
      view: view_of_nodes(
        nodes: [node(effects: [restriction])],
        longer_of: False,
      ),
      now_ms: 1100,
    )
    == []
    as "a node that holds only an ability restriction or a heal applied at once lists no target: the 0x87f and the go tell them"
  assert targets_at(
      view: view_of_nodes(
        nodes: [Node(..node(effects: []), held_until_ms: Some(4000))],
        longer_of: False,
      ),
      now_ms: 1100,
    )
    == []
    as "a node only a crowd-control state holds (no effect, an end of its own) lists no target: the state takes hold on the 0x87f"
}
