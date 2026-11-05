//// The rules of a cast's lasting effects (`genesis_prime/game/lasting`): a node's
//// life, what a type 80 row takes off, and what a new cast at its stack cap pushes
//// off. Expected values come from these places:
//// - `opcode.0x7f4.effect_time`: an effect's lifetime is its delay plus its
////   durationTime, the larger of the two for a spell whose propertyFlags have bit
////   0x2000 (the record's flag 0x10000000, `FillSpellRecord 0x140568540`), never
////   ending for flags bit 2; the node takes its longest effect's.
//// - `opcode.0x811` and `opcode.0x813`: a cast that loses its whole count on a unit
////   is 0x811, one that loses a stack is 0x813.
//// - `Spell4Effects.effectType.80`: the selector (1 a spell group, 2 a Spell4, 3 a
////   Spell4Base) and the count of stacks removed; the oldest first is the server's
////   choice.
//// - Jim's decision on stacking (`Spell4StackGroup.stackCap`):
////   a caster keeps at most the group's cap of its own casts of the group on a
////   unit, and a new one at the cap takes the oldest off; a cap of 0 keeps one per
////   spell.

import genesis_prime/game/lasting.{
  type Hold, Base, EndsAt, Group, Hold, LastingRow, NoLife, Node, NodeOff, Spell,
  Stack, StackOff, UntilRemoved,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import gleam/list
import gleam/option.{None, Some}
import owned_test

// ---- the life of a node ----

fn life(
  rows rows: List(lasting.LastingRow),
  larger larger: Bool,
) -> lasting.Life {
  lasting.life_of(
    effects: rows,
    longer_of_delay_and_duration: larger,
    go_ms: 1000,
  )
}

pub fn a_duration_is_the_life_from_the_go_test() -> Nil {
  use <- owned_test.run(5000)
  // Quick Draw's marker 99472: no delay, 990 ms (the trace's §4 row).
  assert life(
      rows: [LastingRow(delay_ms: 0, duration_ms: 990, until_removed: False)],
      larger: False,
    )
    == EndsAt(ms: 1990)
}

pub fn delay_and_duration_add_unless_the_spell_takes_the_larger_test() -> Nil {
  use <- owned_test.run(5000)
  let row = LastingRow(delay_ms: 500, duration_ms: 3000, until_removed: False)
  assert life(rows: [row], larger: False) == EndsAt(ms: 4500)
  assert life(rows: [row], larger: True) == EndsAt(ms: 4000)
}

pub fn flags_bit_2_never_ends_whatever_else_the_node_holds_test() -> Nil {
  use <- owned_test.run(5000)
  // Power Charge's 96819 holds flags 2: it ends only when the server takes it off.
  assert life(
      rows: [LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)],
      larger: False,
    )
    == UntilRemoved
  assert life(
      rows: [
        LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
        LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
      ],
      larger: False,
    )
    == UntilRemoved
}

pub fn no_duration_and_no_flag_is_no_life_test() -> Nil {
  use <- owned_test.run(5000)
  // Mind Burst's 95008 and Pulse Blast's 159547: type 17 with neither, "nothing that lasts".
  assert life(
      rows: [LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False)],
      larger: False,
    )
    == NoLife
  assert life(rows: [], larger: False) == NoLife
}

pub fn the_longest_effect_decides_the_life_test() -> Nil {
  use <- owned_test.run(5000)
  assert life(
      rows: [
        LastingRow(delay_ms: 0, duration_ms: 3000, until_removed: False),
        LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
        LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
      ],
      larger: False,
    )
    == EndsAt(ms: 9000)
}

// ---- a later go on a unit the cast holds a node on ----

fn timed(duration_ms duration_ms: Int) -> lasting.LastingRow {
  LastingRow(delay_ms: 0, duration_ms:, until_removed: False)
}

fn until_removed() -> lasting.LastingRow {
  LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
}

/// The node the first go at 1000 gives the unit 7 from these effects.
fn first_node(effects effects: List(lasting.LastingRow)) -> lasting.Node {
  let assert Ok(node) =
    lasting.given(
      held: None,
      unit_id: 7,
      count: 1,
      effects:,
      longer_of_delay_and_duration: False,
      go_ms: 1000,
    )
    as "the effects give the node a life"
  node
}

fn later_go(
  held held: lasting.Node,
  effects effects: List(lasting.LastingRow),
  count count: Int,
) -> Result(lasting.Node, Nil) {
  lasting.given(
    held: Some(held),
    unit_id: 7,
    count:,
    effects:,
    longer_of_delay_and_duration: False,
    go_ms: 2000,
  )
}

pub fn a_first_go_gives_a_node_the_life_of_its_longest_effect_and_none_without_a_life_test() -> Nil {
  use <- owned_test.run(5000)
  assert first_node(effects: [timed(duration_ms: 3000), timed(duration_ms: 500)]).life
    == EndsAt(ms: 4000)
  assert lasting.given(
      held: None,
      unit_id: 7,
      count: 1,
      effects: [timed(duration_ms: 0)],
      longer_of_delay_and_duration: False,
      go_ms: 1000,
    )
    == Error(Nil)
    as "no effect has a life: no node"
}

pub fn an_earlier_until_removed_effect_keeps_the_node_through_a_later_go_with_no_life_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0x7f4.instance_count: a later go keeps the node's effects and adds the go's;
  // Spell4Effects.effectType.17: the node's life is the longest of them.
  let node = first_node(effects: [until_removed()])
  let assert Ok(later) =
    later_go(held: node, effects: [timed(duration_ms: 0)], count: 1)
  assert later.life == UntilRemoved
}

pub fn a_timed_node_is_re_timed_from_the_later_go_test() -> Nil {
  use <- owned_test.run(5000)
  let node = first_node(effects: [timed(duration_ms: 3000)])
  assert node.life == EndsAt(ms: 4000)
  let assert Ok(later) =
    later_go(held: node, effects: [timed(duration_ms: 3000)], count: 1)
  assert later.life == EndsAt(ms: 5000)
    as "each effect is armed again for its first lifetime from the later go at 2000"
}

pub fn an_earlier_timed_effect_still_held_is_re_armed_and_can_outlast_the_new_ones_test() -> Nil {
  use <- owned_test.run(5000)
  let node = first_node(effects: [timed(duration_ms: 8000)])
  let assert Ok(later) =
    later_go(held: node, effects: [timed(duration_ms: 3000)], count: 1)
  assert later.life == EndsAt(ms: 10_000)
    as "the 8 s effect, held at 2000, is armed again for 8 s: 10000, beyond the new 3 s effect's 5000"
}

pub fn an_effect_whose_lifetime_ended_before_the_later_go_has_left_the_node_test() -> Nil {
  use <- owned_test.run(5000)
  // The 500 ms effect ended at 1500: its timer fired and it left the node (0x1405d6b30).
  let node = first_node(effects: [timed(duration_ms: 500)])
  let assert Ok(later) =
    later_go(held: node, effects: [timed(duration_ms: 3000)], count: 1)
  assert later.life == EndsAt(ms: 5000)
  assert later.effects == [timed(duration_ms: 3000)]
}

pub fn a_later_go_sets_the_count_outright_test() -> Nil {
  use <- owned_test.run(5000)
  let node = first_node(effects: [until_removed()])
  let assert Ok(later) = later_go(held: node, effects: [], count: 3)
  assert later.count == 3
  let assert Ok(again) = later_go(held: later, effects: [], count: 1)
  assert again.count == 1
}

// ---- what a type 80 row takes off ----

/// A hold of a cast on unit 7 with this many stacks.
fn hold(
  cast_id cast_id: Int,
  started started_ms: Int,
  count count: Int,
) -> Hold {
  Hold(
    cast_id:,
    spell4_id: Spell4Id(42_569),
    base: Spell4BaseId(20_000),
    groups: [51],
    stack: Stack(group_id: 1450, cap: 2),
    started_ms:,
    node: Node(unit_id: 7, count:, life: UntilRemoved, effects: [], armed_ms: 0),
  )
}

pub fn a_count_of_3_over_three_casts_of_1_takes_all_three_nodes_off_test() -> Nil {
  use <- owned_test.run(5000)
  // 80383's row 212836: Spell4 42569, 3 stacks (the third cast is the newest).
  assert lasting.removals(
      holds: [
        hold(cast_id: 30, started: 300, count: 1),
        hold(cast_id: 10, started: 100, count: 1),
        hold(cast_id: 20, started: 200, count: 1),
      ],
      selector: Spell(Spell4Id(42_569)),
      count: 3,
      unit_id: 7,
    )
    == [
      NodeOff(cast_id: 10, unit_id: 7),
      NodeOff(cast_id: 20, unit_id: 7),
      NodeOff(cast_id: 30, unit_id: 7),
    ]
}

pub fn the_oldest_cast_goes_first_whatever_its_cast_id_test() -> Nil {
  use <- owned_test.run(5000)
  // Cast ids wrap, so the age is the start time: the cast with the larger id started first.
  assert lasting.removals(
      holds: [
        hold(cast_id: 5, started: 900, count: 1),
        hold(cast_id: 90, started: 100, count: 1),
      ],
      selector: Spell(Spell4Id(42_569)),
      count: 1,
      unit_id: 7,
    )
    == [NodeOff(cast_id: 90, unit_id: 7)]
}

pub fn a_count_of_1_on_a_cast_of_2_takes_one_stack_off_test() -> Nil {
  use <- owned_test.run(5000)
  assert lasting.removals(
      holds: [hold(cast_id: 10, started: 100, count: 2)],
      selector: Spell(Spell4Id(42_569)),
      count: 1,
      unit_id: 7,
    )
    == [StackOff(cast_id: 10, unit_id: 7)]
}

pub fn a_count_ends_inside_a_cast_with_one_stack_off_for_each_stack_left_test() -> Nil {
  use <- owned_test.run(5000)
  assert lasting.removals(
      holds: [
        hold(cast_id: 10, started: 100, count: 1),
        hold(cast_id: 20, started: 200, count: 3),
      ],
      selector: Spell(Spell4Id(42_569)),
      count: 3,
      unit_id: 7,
    )
    == [
      NodeOff(cast_id: 10, unit_id: 7),
      StackOff(cast_id: 20, unit_id: 7),
      StackOff(cast_id: 20, unit_id: 7),
    ]
}

pub fn a_count_of_999_takes_every_matching_node_off_test() -> Nil {
  use <- owned_test.run(5000)
  assert lasting.removals(
      holds: [
        hold(cast_id: 10, started: 100, count: 1),
        hold(cast_id: 20, started: 200, count: 4),
      ],
      selector: Spell(Spell4Id(42_569)),
      count: 999,
      unit_id: 7,
    )
    == [NodeOff(cast_id: 10, unit_id: 7), NodeOff(cast_id: 20, unit_id: 7)]
}

pub fn a_selector_matches_by_spell_base_or_group_test() -> Nil {
  use <- owned_test.run(5000)
  let held = [hold(cast_id: 10, started: 100, count: 1)]
  let off = [NodeOff(cast_id: 10, unit_id: 7)]
  assert lasting.removals(
      holds: held,
      selector: Spell(Spell4Id(42_569)),
      count: 1,
      unit_id: 7,
    )
    == off
  assert lasting.removals(
      holds: held,
      selector: Base(Spell4BaseId(20_000)),
      count: 1,
      unit_id: 7,
    )
    == off
  assert lasting.removals(
      holds: held,
      selector: Group(51),
      count: 1,
      unit_id: 7,
    )
    == off
}

pub fn a_selector_that_matches_nothing_takes_nothing_off_test() -> Nil {
  use <- owned_test.run(5000)
  let held = [hold(cast_id: 10, started: 100, count: 1)]
  assert lasting.removals(
      holds: held,
      selector: Spell(Spell4Id(1)),
      count: 1,
      unit_id: 7,
    )
    == []
  assert lasting.removals(
      holds: held,
      selector: Base(Spell4BaseId(1)),
      count: 1,
      unit_id: 7,
    )
    == []
  assert lasting.removals(holds: held, selector: Group(1), count: 1, unit_id: 7)
    == []
}

pub fn a_removal_reads_only_the_holds_on_its_unit_test() -> Nil {
  use <- owned_test.run(5000)
  assert lasting.removals(
      holds: [hold(cast_id: 10, started: 100, count: 1)],
      selector: Spell(Spell4Id(42_569)),
      count: 1,
      unit_id: 8,
    )
    == []
}

// ---- what a new cast at the stack cap pushes off ----

fn stacked(
  cast_id cast_id: Int,
  started started_ms: Int,
  spell spell: Int,
  group group: Int,
  cap cap: Int,
) -> Hold {
  Hold(
    ..hold(cast_id:, started: started_ms, count: 1),
    spell4_id: Spell4Id(spell),
    stack: Stack(group_id: group, cap:),
  )
}

pub fn a_third_copy_of_a_cap_2_group_takes_the_oldest_off_test() -> Nil {
  use <- owned_test.run(5000)
  // Cap 2: two stay with the new one beyond the cap's room, so one is pushed off.
  let holds = [
    stacked(cast_id: 20, started: 200, spell: 42_569, group: 1450, cap: 2),
    stacked(cast_id: 10, started: 100, spell: 42_569, group: 1450, cap: 2),
  ]
  assert lasting.pushed_off(
      holds:,
      spell4_id: Spell4Id(42_569),
      stack: Stack(group_id: 1450, cap: 2),
      unit_id: 7,
    )
    == [NodeOff(cast_id: 10, unit_id: 7)]
}

pub fn a_cast_below_the_cap_pushes_nothing_off_test() -> Nil {
  use <- owned_test.run(5000)
  let holds = [
    stacked(cast_id: 10, started: 100, spell: 42_569, group: 1450, cap: 2),
  ]
  assert lasting.pushed_off(
      holds:,
      spell4_id: Spell4Id(42_569),
      stack: Stack(group_id: 1450, cap: 2),
      unit_id: 7,
    )
    == []
}

pub fn the_group_counts_the_casts_of_its_other_spells_too_test() -> Nil {
  use <- owned_test.run(5000)
  let holds = [
    stacked(cast_id: 10, started: 100, spell: 1, group: 9, cap: 2),
    stacked(cast_id: 20, started: 200, spell: 2, group: 9, cap: 2),
  ]
  assert lasting.pushed_off(
      holds:,
      spell4_id: Spell4Id(3),
      stack: Stack(group_id: 9, cap: 2),
      unit_id: 7,
    )
    == [NodeOff(cast_id: 10, unit_id: 7)]
}

pub fn a_cap_of_0_keeps_one_cast_per_spell_test() -> Nil {
  use <- owned_test.run(5000)
  // Charged Shot 34718 is in group 2, cap 0: its second cast takes the first off; a
  // cast of another spell of the group stays.
  let holds = [
    stacked(cast_id: 10, started: 100, spell: 34_718, group: 2, cap: 0),
    stacked(cast_id: 20, started: 200, spell: 99, group: 2, cap: 0),
  ]
  assert lasting.pushed_off(
      holds:,
      spell4_id: Spell4Id(34_718),
      stack: Stack(group_id: 2, cap: 0),
      unit_id: 7,
    )
    == [NodeOff(cast_id: 10, unit_id: 7)]
}

pub fn another_group_is_not_pushed_off_test() -> Nil {
  use <- owned_test.run(5000)
  let holds = [
    stacked(cast_id: 10, started: 100, spell: 42_569, group: 1450, cap: 1),
    stacked(cast_id: 20, started: 200, spell: 42_569, group: 1450, cap: 1),
  ]
  assert lasting.pushed_off(
      holds:,
      spell4_id: Spell4Id(5),
      stack: Stack(group_id: 77, cap: 2),
      unit_id: 7,
    )
    == []
}

pub fn pushing_reads_only_the_holds_on_its_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let holds = [
    stacked(cast_id: 10, started: 100, spell: 42_569, group: 1450, cap: 1),
  ]
  assert lasting.pushed_off(
      holds:,
      spell4_id: Spell4Id(42_569),
      stack: Stack(group_id: 1450, cap: 1),
      unit_id: 8,
    )
    == []
}

pub fn the_cast_ids_listed_are_the_ones_pushed_off_in_age_order_test() -> Nil {
  use <- owned_test.run(5000)
  let holds = [
    stacked(cast_id: 30, started: 300, spell: 1, group: 4, cap: 1),
    stacked(cast_id: 10, started: 100, spell: 1, group: 4, cap: 1),
    stacked(cast_id: 20, started: 200, spell: 1, group: 4, cap: 1),
  ]
  // Cap 1 leaves room for none beside the new cast: all three come off, oldest first.
  assert list.map(
      lasting.pushed_off(
        holds:,
        spell4_id: Spell4Id(1),
        stack: Stack(group_id: 4, cap: 1),
        unit_id: 7,
      ),
      fn(removal) {
        case removal {
          NodeOff(cast_id:, ..) | StackOff(cast_id:, ..) -> cast_id
        }
      },
    )
    == [10, 20, 30]
}
