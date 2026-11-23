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
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import owned_test
import qcheck

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

// ---- the time left of an effect a unit create lists ----

pub fn the_time_left_of_an_end_is_never_less_than_1_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0x7f4.effect_time: a lifetime of 0 in an effect info plays the row's own
  // time again, so an end that has passed is told as 1, never 0.
  [
    #("an end that has passed", 1500, 2000, 1),
    #("an end that is now", 2000, 2000, 1),
    #("an end still to come", 2750, 2000, 750),
  ]
  |> list.each(fn(row) {
    let #(reason, end_ms, now_ms, expected) = row
    assert lasting.time_left_ms(end_ms:, now_ms:) == expected as reason
  })
}

// ---- a later go on a unit the cast holds a node on ----

/// A listed effect with a timed life; its id is only carried by the node, never read.
fn timed(duration_ms duration_ms: Int) -> lasting.NodeEffect {
  lasting.Listed(
    effect_id: Spell4EffectsId(67_777),
    row: LastingRow(delay_ms: 0, duration_ms:, until_removed: False),
  )
}

/// A listed effect of flags bit 2: Power Charge's row 96819 lasts until removed.
fn until_removed() -> lasting.NodeEffect {
  lasting.Listed(
    effect_id: Spell4EffectsId(96_819),
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
  )
}

/// The node the first go at 1000 gives the unit 7 from these effects.
fn first_node(effects effects: List(lasting.NodeEffect)) -> lasting.Node {
  let assert Ok(node) =
    lasting.given(
      held: None,
      unit_id: 7,
      count: 1,
      effects:,
      held_until_ms: [],
      longer_of_delay_and_duration: False,
      aura_ends_ms: None,
      go_ms: 1000,
    )
    as "the effects give the node a life"
  node
}

fn later_go(
  held held: lasting.Node,
  effects effects: List(lasting.NodeEffect),
  count count: Int,
) -> Result(lasting.Node, Nil) {
  lasting.given(
    held: Some(held),
    unit_id: 7,
    count:,
    effects:,
    held_until_ms: [],
    longer_of_delay_and_duration: False,
    aura_ends_ms: None,
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
      held_until_ms: [],
      longer_of_delay_and_duration: False,
      aura_ends_ms: None,
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
    node: Node(
      unit_id: 7,
      count:,
      life: UntilRemoved,
      effects: [],
      armed_ms: 0,
      held_until_ms: None,
      struck: None,
    ),
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
      kept: [],
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
      kept: [],
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
      kept: [],
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
      kept: [],
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
      kept: [],
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
      kept: [],
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
        kept: [],
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

/// A cast of the property below: its spell, stack group, cap and age.
fn drawn_cast() -> qcheck.Generator(#(Int, Int, Int, Int)) {
  qcheck.tuple4(
    qcheck.bounded_int(from: 1, to: 3),
    qcheck.bounded_int(from: 0, to: 2),
    qcheck.bounded_int(from: 0, to: 3),
    qcheck.bounded_int(from: 0, to: 5000),
  )
}

pub fn the_casts_the_stack_rule_names_are_each_taken_off_by_their_node_or_ended_by_their_kept_change_and_never_by_both_test() -> Nil {
  use <- owned_test.run(30_000)
  // Jim's decision on stacking (`lasting.stack_pushed_off`): a caster's casts of one group on a
  // unit count together against the cap, whether a node or a change kept after the caster lost
  // sight of the player holds them. The two paths that end a pushed cast, the node's
  // (`lasting.pushed_off`) and the kept change's (`lasting.kept_pushed_off`), must split the
  // casts the rule names over both sets between them: each named cast by one path, none by both.
  qcheck.given(
    qcheck.tuple3(
      qcheck.list_from(drawn_cast()),
      qcheck.list_from(drawn_cast()),
      qcheck.tuple3(
        qcheck.bounded_int(from: 1, to: 3),
        qcheck.bounded_int(from: 0, to: 2),
        qcheck.bounded_int(from: 0, to: 3),
      ),
    ),
    fn(drawn) {
      let #(with_a_node, kept, new_cast) = drawn
      let #(spell, group, cap) = new_cast
      let spell4_id = Spell4Id(spell)
      let stack = Stack(group_id: group, cap:)
      let holds =
        list.index_map(with_a_node, fn(cast, index) {
          stacked(
            cast_id: 10 + index,
            started: cast.3,
            spell: cast.0,
            group: cast.1,
            cap: cast.2,
          )
        })
      let kept_casts =
        list.index_map(kept, fn(cast, index) {
          lasting.StackedCast(
            cast_id: 1000 + index,
            spell4_id: Spell4Id(cast.0),
            stack: Stack(group_id: cast.1, cap: cast.2),
            started_ms: cast.3,
          )
        })
      let by_node =
        list.map(
          lasting.pushed_off(
            holds:,
            kept: kept_casts,
            spell4_id:,
            stack:,
            unit_id: 7,
          ),
          fn(removal) {
            case removal {
              NodeOff(cast_id:, ..) | StackOff(cast_id:, ..) -> cast_id
            }
          },
        )
      let by_change =
        lasting.kept_pushed_off(
          holds:,
          kept: kept_casts,
          spell4_id:,
          stack:,
          unit_id: 7,
        )
      let named =
        lasting.stack_pushed_off(
          casts: list.append(
            list.map(holds, fn(hold) {
              lasting.StackedCast(
                cast_id: hold.cast_id,
                spell4_id: hold.spell4_id,
                stack: hold.stack,
                started_ms: hold.started_ms,
              )
            }),
            kept_casts,
          ),
          spell4_id:,
          stack:,
        )
      assert list.all(by_node, fn(cast_id) {
        !list.contains(by_change, cast_id)
      })
        as "no cast is taken off by its node and ended by its change"
      assert list.sort(list.append(by_node, by_change), int.compare)
        == list.sort(named, int.compare)
        as "every cast the rule names over both sets is taken off by one of the paths, and each path takes only those"
    },
  )
}

// ---- a crowd-control state's own end ----
//
// A state ends when its creature says (`cc_state.end`), so its time is kept apart from the
// effects a later go arms again from itself (`opcode.0x7f4.instance_count`).

/// The node of unit 7 at a go at `go_ms` that adds these effects and holds the states
/// until these times, from the node `held` the cast has there.
fn with_states(
  held held: Option(lasting.Node),
  effects effects: List(lasting.NodeEffect),
  until until: List(Int),
  go_ms go_ms: Int,
) -> Result(lasting.Node, Nil) {
  lasting.given(
    held:,
    unit_id: 7,
    count: 1,
    effects:,
    held_until_ms: until,
    longer_of_delay_and_duration: False,
    aura_ends_ms: None,
    go_ms:,
  )
}

pub fn a_node_for_a_state_alone_lives_until_the_states_end_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(node) =
    with_states(held: None, effects: [], until: [4000], go_ms: 1000)
    as "a state is a reason for a node"
  assert node.life == EndsAt(ms: 4000)
  assert with_states(held: None, effects: [], until: [900], go_ms: 1000)
    == Error(Nil)
    as "a state that ended before the go gives no node"
}

pub fn a_later_go_arms_its_effects_again_but_not_the_state_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(first) =
    with_states(held: None, effects: [], until: [4000], go_ms: 1000)
    as "a node held until 4000"
  let assert Ok(second) =
    with_states(
      held: Some(first),
      effects: [timed(duration_ms: 100)],
      until: [],
      go_ms: 2000,
    )
    as "the later go adds a 100 ms effect"
  assert second.life == EndsAt(ms: 4000)
    as "the node ends at the state's 4000 and not at 2000 + 3000, which re-arming it would give"
  let assert Ok(longer) =
    with_states(
      held: Some(first),
      effects: [timed(duration_ms: 5000)],
      until: [],
      go_ms: 2000,
    )
    as "a later go with a longer effect"
  assert longer.life == EndsAt(ms: 7000)
    as "the node lasts as long as its longest effect, at least until the state"
}

pub fn a_node_with_an_until_removed_effect_outlasts_the_state_and_the_latest_state_counts_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(removed) =
    with_states(
      held: None,
      effects: [until_removed()],
      until: [4000],
      go_ms: 1000,
    )
    as "an effect that lasts until removed"
  assert removed.life == UntilRemoved
  let assert Ok(two) =
    with_states(held: None, effects: [], until: [3000, 4500], go_ms: 1000)
    as "two states"
  assert two.life == EndsAt(ms: 4500) as "the latest of the states held decides"
}

// ---- an aura cast's node ----
//
// A castMethod 10 spell's buff lasts to the cast's start plus its spellDuration; its node's
// longest timer extends it only for a node with no flags-2 effect, and a node that holds an
// until-removed row has one (`0x1407180c0`, `0x140718120`, `Spell4.spellDuration`). A sum
// that is not later than now is no end.

/// The node of unit 7 at a go at `go_ms` from these rows, the first of them aimed at the
/// caster, for a cast whose aura ends at `aura_ends_ms`.
fn under_aura(
  rows rows: List(lasting.LastingRow),
  larger larger: Bool,
  aura_ends_ms aura_ends_ms: Option(Int),
  go_ms go_ms: Int,
) -> Result(lasting.Node, Nil) {
  lasting.given(
    held: None,
    unit_id: 7,
    count: 1,
    effects: list.map(rows, fn(row) {
      lasting.Listed(effect_id: Spell4EffectsId(67_777), row:)
    }),
    held_until_ms: [],
    longer_of_delay_and_duration: larger,
    aura_ends_ms:,
    go_ms:,
  )
}

pub fn a_node_that_holds_an_until_removed_row_ends_at_an_aura_after_the_go_whatever_its_timed_rows_test() -> Nil {
  use <- owned_test.run(30_000)
  qcheck.given(
    qcheck.tuple4(
      qcheck.list_from(qcheck.tuple2(
        qcheck.bounded_int(from: 0, to: 5000),
        qcheck.bounded_int(from: 0, to: 5000),
      )),
      qcheck.tuple3(qcheck.bool(), qcheck.bool(), qcheck.bool()),
      qcheck.bounded_int(from: 0, to: 10_000),
      qcheck.bounded_int(from: -5000, to: 20_000),
    ),
    fn(drawn) {
      let #(
        timed,
        #(larger, until_removed, at_the_go),
        go_ms,
        drawn_after_go_ms,
      ) = drawn
      let aura_after_go_ms = case at_the_go {
        True -> 0
        False -> drawn_after_go_ms
      }
      let aura_end_ms = go_ms + aura_after_go_ms
      let timed_rows =
        list.map(timed, fn(row) {
          LastingRow(delay_ms: row.0, duration_ms: row.1, until_removed: False)
        })
      let rows = case until_removed {
        True ->
          list.append(timed_rows, [
            LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
          ])
        False -> timed_rows
      }
      let longest =
        list.fold(timed, 0, fn(longest, row) {
          int.max(longest, case larger {
            True -> int.max(row.0, row.1)
            False -> row.0 + row.1
          })
        })
      let node =
        under_aura(rows:, larger:, aura_ends_ms: Some(aura_end_ms), go_ms:)
      let #(expected, reason) = case until_removed, aura_after_go_ms > 0 {
        True, True -> #(
          Ok(first_aura_node(rows:, life: EndsAt(ms: aura_end_ms), go_ms:)),
          "a node with an until-removed row ends at the aura's end whatever its timed rows (node 0x48 is all bits, so the client's timer branch never applies)",
        )
        True, False -> #(
          Ok(first_aura_node(rows:, life: UntilRemoved, go_ms:)),
          "an aura that ends at or before the go is no end",
        )
        False, _ -> #(
          case longest > 0 {
            True ->
              Ok(first_aura_node(
                rows:,
                life: EndsAt(ms: go_ms + longest),
                go_ms:,
              ))
            False -> Error(Nil)
          },
          "a node with no until-removed row ignores the aura",
        )
      }
      assert node == expected as reason
    },
  )
}

/// The node `under_aura` gives: unit 7, one count, each row listed, armed at the go.
fn first_aura_node(
  rows rows: List(lasting.LastingRow),
  life life: lasting.Life,
  go_ms go_ms: Int,
) -> lasting.Node {
  Node(
    unit_id: 7,
    count: 1,
    life:,
    effects: list.map(rows, fn(row) {
      lasting.Listed(effect_id: Spell4EffectsId(67_777), row:)
    }),
    armed_ms: go_ms,
    held_until_ms: None,
    struck: None,
  )
}

pub fn an_aura_gives_the_node_the_cases_the_client_reads_from_its_buff_timing_test() -> Nil {
  use <- owned_test.run(5000)
  let flagged = LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
  let timed_for = fn(duration_ms) {
    LastingRow(delay_ms: 0, duration_ms:, until_removed: False)
  }
  [
    #(
      "an until-removed row and an aura after the go: the node ends with the aura (Nullifier's field 58868, started at 1000 with 6000)",
      [flagged],
      Some(7000),
      1000,
      Ok(EndsAt(ms: 7000)),
    ),
    #(
      "a timed row that ends later than the aura does not extend it: the flags-2 row 69832 makes node 0x48 all bits, so the client's buff of Spell4 34959 runs out at its start plus 10000 and not at its Fluff 69834's 12000",
      [flagged, timed_for(12_000)],
      Some(10_000),
      1000,
      Ok(EndsAt(ms: 10_000)),
    ),
    #(
      "a timed row that ends before the aura leaves the aura's end too",
      [flagged, timed_for(2000)],
      Some(7000),
      1000,
      Ok(EndsAt(ms: 7000)),
    ),
    #(
      "no aura (castMethod 0, or spellDuration -1): until removed",
      [flagged],
      None,
      1000,
      Ok(UntilRemoved),
    ),
    #(
      "an aura that ends before the go (Spell4 71983: castTime 10000 over spellDuration 2000, started at 1000, goes at 11000): until removed",
      [flagged],
      Some(3000),
      11_000,
      Ok(UntilRemoved),
    ),
    #(
      "an aura that ends at the go (Spell4 66923: castTime 3000 and spellDuration 3000, started at 1000, goes at 4000): until removed",
      [flagged],
      Some(4000),
      4000,
      Ok(UntilRemoved),
    ),
    #(
      "an aura with no effect that has a life holds no node",
      [timed_for(0)],
      Some(7000),
      1000,
      Error(Nil),
    ),
  ]
  |> list.each(fn(row) {
    let #(reason, rows, aura_ends_ms, go_ms, expected) = row
    assert result.map(
        under_aura(rows:, larger: False, aura_ends_ms:, go_ms:),
        fn(node) { node.life },
      )
      == expected
      as reason
  })
  // A second go of the same cast on the unit counts the aura from the cast's start, so its end
  // is the same time.
  let assert Ok(first) =
    under_aura(
      rows: [flagged],
      larger: False,
      aura_ends_ms: Some(7000),
      go_ms: 1000,
    )
  let assert Ok(later) =
    lasting.given(
      held: Some(first),
      unit_id: 7,
      count: 1,
      effects: [],
      held_until_ms: [],
      longer_of_delay_and_duration: False,
      aura_ends_ms: Some(7000),
      go_ms: 3000,
    )
  assert later.life == EndsAt(ms: 7000)
    as "a second go of the same cast keeps the aura's end"
}

pub fn a_kept_cast_counts_against_the_cap_but_is_not_taken_off_by_its_node_test() -> Nil {
  use <- owned_test.run(5000)
  // Cap 2, one cast with a node (20, started at 200) and one kept with no node: the new cast
  // is over the cap's room by one, so the oldest of the two is pushed off. When that is the
  // kept cast, the change it holds ends (`cast_control`) and the node path takes no node off;
  // when it is the cast with the node, the node is taken off.
  let holds = [
    stacked(cast_id: 20, started: 200, spell: 42_569, group: 1450, cap: 2),
  ]
  let kept_at = fn(started_ms) {
    [
      lasting.StackedCast(
        cast_id: 10,
        spell4_id: Spell4Id(42_569),
        stack: Stack(group_id: 1450, cap: 2),
        started_ms:,
      ),
    ]
  }
  assert lasting.pushed_off(
      holds:,
      kept: kept_at(100),
      spell4_id: Spell4Id(42_569),
      stack: Stack(group_id: 1450, cap: 2),
      unit_id: 7,
    )
    == []
    as "the kept cast is the oldest: it is the one pushed off, and it holds no node to take off"
  assert lasting.pushed_off(
      holds:,
      kept: kept_at(300),
      spell4_id: Spell4Id(42_569),
      stack: Stack(group_id: 1450, cap: 2),
      unit_id: 7,
    )
    == [NodeOff(cast_id: 20, unit_id: 7)]
    as "a kept cast started after the cast with the node leaves that cast the oldest: its node is taken off"
}
