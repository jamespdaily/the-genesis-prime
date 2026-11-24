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

import cast_support as support
import fixture_tables
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/lasting.{LastingRow, LifeOnly, Listed, Node}
import genesis_prime/game/spell_plan
import genesis_prime/game/start_place
import genesis_prime/game/unit_casts.{
  type CastView, type HeldEffect, CastView, HeldEffect, UntilRemoved, ViewTarget,
}
import genesis_prime/message/spell_position
import genesis_prime/message/spell_started.{SpellStarted}
import genesis_prime/message/spell_target_info.{type SpellTargetInfo}
import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4_effects
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import owned_test
import place_support

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
    struck: None,
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

/// Spell4 38784 holds the cooldown modifier row 159128 (type 73, delay 0, duration 0) beside
/// the proc row 178239 (type 14, 3000 ms): a node holds both, and only the proc has a life.
fn cooldown_row() -> lasting.NodeEffect {
  Listed(
    effect_id: Spell4EffectsId(159_128),
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
  )
}

fn proc_row() -> lasting.NodeEffect {
  Listed(
    effect_id: Spell4EffectsId(178_239),
    row: LastingRow(delay_ms: 0, duration_ms: 3000, until_removed: False),
  )
}

/// The client's Spell4Effects row `id`, a root of the fixture, as a node holds it. The
/// lasting row is read by `spell_plan.lasting_row_of`, which the cast rule also uses.
fn client_row(id id: Int) -> lasting.NodeEffect {
  let id = fixture_tables.root(table: "Spell4Effects", id:)
  let assert Ok(row) =
    spell4_effects.get(tables: fixture_tables.shared(), id: Spell4EffectsId(id))
    as "the fixture holds the root row"
  Listed(
    effect_id: Spell4EffectsId(id),
    row: spell_plan.lasting_row_of(effect: row),
  )
}

/// The effects of the node a later go of the cast at 1000 makes on unit 7, from the node an
/// earlier go made there with `earlier` (`lasting.given` keeps its effects and appends the
/// go's).
fn after_a_later_go(
  earlier earlier: List(lasting.NodeEffect),
  later later: List(lasting.NodeEffect),
) -> List(lasting.NodeEffect) {
  let assert Ok(made) =
    lasting.given(
      held: Some(node(effects: earlier)),
      unit_id: 7,
      count: 1,
      effects: later,
      held_until_ms: [],
      longer_of_delay_and_duration: False,
      aura_ends_ms: option.None,
      go_ms: 1000,
    )
    as "the later go's node has a life"
  made.effects
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
          support.listed_effect_info(
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
        [
          support.listed_effect_info(
            effect_id: 67_777,
            instance_id: 1,
            delay_ms: 0,
            lifetime_ms: 1,
          ),
        ],
      ),
      #(
        "an effect that lasts until removed (Power Charge's row 96819, flags 2) has delay 0 and lifetime 0",
        [power_charge_row()],
        False,
        1100,
        [
          support.listed_effect_info(
            effect_id: 96_819,
            instance_id: 1,
            delay_ms: 0,
            lifetime_ms: 0,
          ),
        ],
      ),
      #(
        "for a spell with the longer-of flag the end is the larger of delay and duration, 400, so 300 ms are left",
        [gate_row()],
        True,
        1100,
        [
          support.listed_effect_info(
            effect_id: 67_777,
            instance_id: 1,
            delay_ms: 80,
            lifetime_ms: 300,
          ),
        ],
      ),
      #(
        "an effect that lasts until removed with 1 ms of delay to run is told a delay of 2: its lifetime is all bits in the client's node, so a start of 1 sums to 0 and the node would build no buff (row 105548 of Spell4 45375: type 17, delay 500, flags 2; the go at 1000, now 1499)",
        [client_row(id: 105_548)],
        False,
        1499,
        [
          support.listed_effect_info(
            effect_id: 105_548,
            instance_id: 1,
            delay_ms: 2,
            lifetime_ms: 0,
          ),
        ],
      ),
      #(
        "the earliest start is the node's, so an effect that ends is told 2 as well when the node holds one until removed (Gate's row 67777 at 1179 has 1 ms of delay to run)",
        [client_row(id: 105_548), gate_row()],
        False,
        1179,
        [
          support.listed_effect_info(
            effect_id: 105_548,
            instance_id: 1,
            delay_ms: 321,
            lifetime_ms: 0,
          ),
          support.listed_effect_info(
            effect_id: 67_777,
            instance_id: 2,
            delay_ms: 2,
            lifetime_ms: 401,
          ),
        ],
      ),
      #(
        "the effects a later go of the cast adds are the node's too: Power Charge's row 96819 at delay 0 added to a node holding row 105548 makes the smallest delay 0, so row 105548 keeps its 1 (alone, at 1499, it is told 2)",
        after_a_later_go(earlier: [client_row(id: 105_548)], later: [
          power_charge_row(),
        ]),
        False,
        1499,
        [
          support.listed_effect_info(
            effect_id: 105_548,
            instance_id: 1,
            delay_ms: 1,
            lifetime_ms: 0,
          ),
          support.listed_effect_info(
            effect_id: 96_819,
            instance_id: 2,
            delay_ms: 0,
            lifetime_ms: 0,
          ),
        ],
      ),
      #(
        "a node whose smallest delay is 0 keeps the 1 of an effect that lasts until removed: the client's sum is all bits already (row 105548 with 1 ms to run beside Gate's row 67777, which has run, at 1499)",
        [client_row(id: 105_548), gate_row()],
        False,
        1499,
        [
          support.listed_effect_info(
            effect_id: 105_548,
            instance_id: 1,
            delay_ms: 1,
            lifetime_ms: 0,
          ),
          support.listed_effect_info(
            effect_id: 67_777,
            instance_id: 2,
            delay_ms: 0,
            lifetime_ms: 81,
          ),
        ],
      ),
      #(
        "with 1 ms of delay to run, a node whose effects all end keeps the 1: the lifetime is not all bits, so the sum is not 0",
        [gate_row()],
        False,
        1179,
        [
          support.listed_effect_info(
            effect_id: 67_777,
            instance_id: 1,
            delay_ms: 1,
            lifetime_ms: 401,
          ),
        ],
      ),
      #(
        "an effect that lasts until removed with 2 ms of delay to run keeps the 2",
        [client_row(id: 105_548)],
        False,
        1498,
        [
          support.listed_effect_info(
            effect_id: 105_548,
            instance_id: 1,
            delay_ms: 2,
            lifetime_ms: 0,
          ),
        ],
      ),
      #(
        "an effect with neither delay nor duration is left out of the entry: Spell4 38784's cooldown row 159128 beside its proc row 178239",
        [cooldown_row(), proc_row()],
        False,
        1100,
        [
          support.listed_effect_info(
            effect_id: 178_239,
            instance_id: 1,
            delay_ms: 0,
            lifetime_ms: 2900,
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
        == [
          support.listed_target_info(
            unit_id: 7,
            index: 0,
            count: 1,
            effects: expected,
          ),
        ]
        as reason
    },
  )
}

pub fn an_entry_lists_the_target_a_node_makes_test() -> Nil {
  use <- owned_test.run(5000)
  let power_charge = fn(unit_id, index, count) {
    support.listed_target_info(unit_id:, index:, count:, effects: [
      support.listed_effect_info(
        effect_id: 96_819,
        instance_id: 1,
        delay_ms: 0,
        lifetime_ms: 0,
      ),
    ])
  }
  let on_unit_8 = fn(node: lasting.Node) { Node(..node, unit_id: 8) }
  let power_charge_node = node(effects: [power_charge_row()])
  let power_charge_and_gate = node(effects: [power_charge_row(), gate_row()])
  let restriction =
    LifeOnly(row: LastingRow(
      delay_ms: 0,
      duration_ms: 5000,
      until_removed: False,
    ))
  list.each(
    [
      #(
        "a node's count is its cast's own: a cast that gave 1 stack lists a count of 1",
        [power_charge_node],
        [power_charge(7, 0, 1)],
      ),
      #(
        "a node stacked off to count 0 lists 0 stacks, and the buff is still made",
        [Node(..power_charge_node, count: 0)],
        [power_charge(7, 0, 0)],
      ),
      #(
        "each target is indexed by its place in the list with flags 0 and a Hit, its effects numbered from 1 per target",
        [power_charge_and_gate, on_unit_8(power_charge_and_gate)],
        list.map([#(7, 0), #(8, 1)], fn(place) {
          support.listed_target_info(
            unit_id: place.0,
            index: place.1,
            count: 1,
            effects: [
              support.listed_effect_info(
                effect_id: 96_819,
                instance_id: 1,
                delay_ms: 0,
                lifetime_ms: 0,
              ),
              support.listed_effect_info(
                effect_id: 67_777,
                instance_id: 2,
                delay_ms: 80,
                lifetime_ms: 480,
              ),
            ],
          )
        }),
      ),
      #(
        "a node that holds only an ability restriction or a heal applied at once lists no target: the 0x87f and the go tell them",
        [node(effects: [restriction])],
        [],
      ),
      #(
        "a node only a crowd-control state holds (no effect, an end of its own) lists no target: the state takes hold on the 0x87f",
        [Node(..node(effects: []), held_until_ms: Some(4000))],
        [],
      ),
    ],
    fn(row) {
      let #(reason, nodes, expected) = row
      assert targets_at(
          view: view_of_nodes(nodes:, longer_of: False),
          now_ms: 1100,
        )
        == expected
        as reason
    },
  )
}

/// The ally's place of the started cast below: x 1024, y 2, z -512, turned 1.5 radians. Each
/// is a 32-bit float whose bits are exact (0x44800000, 0x40000000, 0xC4000000, 0x3FC00000).
fn ally_place() -> start_place.Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: 1024.0,
    y: 2.0,
    z: -512.0,
  )
  |> start_place.turned(facing: start_place.Facing(
    yaw: 1.5,
    pitch: 0.0,
    roll: 0.0,
  ))
}

/// The view of cast 7 of Phantasmal Armor tier 5 (Spell4 52341, `table_rows -- Spell4Effects
/// spellId=52341`) that caster 21 put on ally 40, holding these effects.
fn held_view(effects effects: List(HeldEffect)) -> CastView {
  CastView(
    caster_unit_id: 21,
    cast_id: 7,
    spell4_id: Spell4Id(52_341),
    primary_target: 40,
    gone: True,
    current: False,
    targets: [ViewTarget(unit_id: 40, count: 1, effects:)],
  )
}

fn ten_seconds_from(
  effect_id effect_id: Int,
  starts_ms starts_ms: Int,
) -> HeldEffect {
  HeldEffect(
    effect_id: Spell4EffectsId(effect_id),
    starts_ms:,
    ends: unit_casts.EndsAt(ms: starts_ms + 10_000),
  )
}

pub fn a_held_cast_is_started_and_gone_for_a_viewer_with_the_targets_its_create_lists_test() -> Nil {
  use <- owned_test.run(5000)
  let absorb = ten_seconds_from(effect_id: 123_664, starts_ms: 1000)
  let modifier = ten_seconds_from(effect_id: 203_798, starts_ms: 1000)
  let view = held_view(effects: [absorb, modifier])
  let #(started, went) =
    cast_frame.held_start(view:, place: ally_place(), now_ms: 4000)
  // opcode.0x7ff: the caster's unit, the cast and its spell, the spell as its own root with
  // no parent, the ally as primary target at the ally's place and yaw, item level 0 and the
  // two safe bits (opcode.0x7ff.root_parent, .caster_item_level, .own_cast, .activate); the
  // place is a guess (0x14053a210.held_position).
  assert started
    == SpellStarted(
      cast_id: 7,
      spell4_id: 52_341,
      root_spell4_id: 52_341,
      parent_spell4_id: 0,
      caster_unit_id: 21,
      caster_item_level: 0,
      primary_target_unit_id: 40,
      position: spell_position.SpellPosition(
        x: 1_149_239_296,
        y: 1_073_741_824,
        z: 3_288_334_336,
      ),
      yaw: 1_069_547_520,
      initial_positions: [],
      telegraph_positions: [],
      own_cast: 1,
      creature_activate: 0,
    )
    as "the 0x7ff names the caster, the cast and the ally and carries the safe values"
  // opcode.0x7f4: the ally alone with one instance, the ignore-cooldown bit, no positions or
  // missiles, phase 0, and the ally's place as its destination.
  assert went.cast_id == 7 && went.phase == 0 && went.ignore_cooldown == 1
    as "opcode.0x7f4: the go is the cast's, phase 0, with the ignore-cooldown bit set"
  assert went.destination == started.position
    as "its destination is the ally's place"
  assert went.initial_positions == []
    && went.telegraph_positions == []
    && went.missiles == []
    as "it carries no positions and no missiles"
  assert list.length(went.targets) == 1
    && list.map(went.targets, fn(target) { target.unit_id }) == [40]
    && list.map(went.targets, fn(target) { target.instance_count }) == [1]
    as "it lists the ally alone, with one instance"
  assert went.targets == targets_at(view:, now_ms: 4000)
    as "its target is the one the ally's create lists for the same view and clock"
  // opcode.0x7f4.effect_delay, .effect_time: a cast with two effects lists both in start
  // order, each with the delay still to run and the time left.
  let later = ten_seconds_from(effect_id: 203_798, starts_ms: 5000)
  let #(_, two) =
    cast_frame.held_start(
      view: held_view(effects: [absorb, later]),
      place: ally_place(),
      now_ms: 4000,
    )
  assert two.targets
    == [
      support.listed_target_info(unit_id: 40, index: 0, count: 1, effects: [
        support.listed_effect_info(
          effect_id: 123_664,
          instance_id: 1,
          delay_ms: 0,
          lifetime_ms: 7000,
        ),
        support.listed_effect_info(
          effect_id: 203_798,
          instance_id: 2,
          delay_ms: 1000,
          lifetime_ms: 11_000,
        ),
      ]),
    ]
    as "each effect is listed in start order with its delay and its time left"
  // A negative clock (the monotonic time starts below 0): a change told at the go's time
  // -5000 for 10 000 ms, built at -2000, has no delay left and 3000 ms to live.
  let #(_, early) =
    cast_frame.held_start(
      view: held_view(effects: [
        ten_seconds_from(effect_id: 123_664, starts_ms: -5000),
      ]),
      place: ally_place(),
      now_ms: -2000,
    )
  assert early.targets
    == [
      support.listed_target_info(unit_id: 40, index: 0, count: 1, effects: [
        support.listed_effect_info(
          effect_id: 123_664,
          instance_id: 1,
          delay_ms: 0,
          lifetime_ms: 3000,
        ),
      ]),
    ]
    as "at a negative clock the effect has no delay and 3000 ms left"
}
