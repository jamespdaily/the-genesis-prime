//// The cast rule's Proxies behind a target apply prerequisite of type 108: Impale's four,
//// each started on a struck unit only when the caster stands in the arc behind it
//// (`genesis_prime/game/cast` `children`, `proxy_gates`). The spells are planted by hand
//// from the client's rows (`table_rows -- Spell4Effects 83818 83819 85673 85682`, `--
//// Prerequisite 38585 38587 5734 5735`, `-- PositionalRequirement 53`), on a clock the test
//// drives. Expected values come from these places:
//// - `Spell4Effects.prerequisiteIdTargetApply`: the check's first unit is the struck unit
////   and its second the caster, so 5734 (type 108, comparison 1, row 53) passes when the
////   caster stands in the 140 degrees behind the struck creature's facing.
//// - Impale's rows: 83818 (child 39426, caster gate 38587, target gate 5735), 83819 (39427,
////   38585, 5735), 85673 (39427, 38587, 5734) and 85682 (39427, 38585, 5734). 38585 is
////   stealthed or under Combat Stealth, 38587 its complement, 5734 behind and 5735 not
////   behind, so for each struck unit exactly one of the four starts a child.
//// - `PrerequisitePositional` 0x14049d940, as the prerequisite module's tests read it: row 53
////   at yaw 0 holds the unit at (0, 5) from a unit at (0, 0) and not (0, -5) or (5, 0).
//// - The server's choices, in the rule's doc: the target gate is checked once for each unit
////   the child would be made on, against the pose the caster's picture holds of it when the
////   round closes; a unit the picture no longer shows decides nothing and is written as a
////   debug line.

import cast_support as support
import genesis_prime/game/area.{type Pose}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, GatedOnCasterAndTarget, Proxy, Spell,
}
import genesis_prime/game/spend
import genesis_prime/game/start_place
import genesis_prime/message/spell_started
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import owned_test
import prerequisite_support

/// The bag indices of the planted bases 1 and 2 (`cast_support.abilities`): the base 1 spell
/// stealths the caster and Impale is planted in base 2's place.
const bag_of_base_1 = 8

const bag_of_base_2 = 10

// ---- the rows ----

/// 5734 and 5735: type 108 of row 53, comparison 1 (behind) and 2 (not behind).
fn target_gate(comparison comparison: Int) -> prerequisite.Prerequisite {
  prerequisite_support.prerequisite_of_arcs(
    row: prerequisite_support.row(
      id: case comparison {
        1 -> 5734
        _ -> 5735
      },
      flags: 0,
      conditions: [#(108, comparison, 53, 0)],
    ),
    arcs: [prerequisite_support.behind_arc()],
  )
}

/// 38585 (stealthed, or under a cast of 39407) and 38587 (not stealthed and not under a cast
/// by 39407).
fn caster_gate(id id: Int) -> prerequisite.Prerequisite {
  case id {
    38_585 ->
      prerequisite_support.prerequisite_of(
        row: prerequisite_support.row(id: 38_585, flags: 1, conditions: [
          #(116, 1, 0, 28_455),
          #(15, 1, 0, 39_407),
        ]),
      )
    _ ->
      prerequisite_support.prerequisite_of(
        row: prerequisite_support.row(id: 38_587, flags: 0, conditions: [
          #(116, 2, 0, 28_455),
          #(50, 2, 0, 39_407),
        ]),
      )
  }
}

/// A Proxy to the child behind these caster gates and this target gate, aimed at each
/// struck unit.
fn proxy(
  effect effect: Int,
  child child: Int,
  caster_gates caster_gates: List(prerequisite.Prerequisite),
  target_gate target_gate: prerequisite.Prerequisite,
) -> spell_plan.Proxy {
  Proxy(
    effect_id: Spell4EffectsId(effect),
    delay_ms: 0,
    phase_flags: -1,
    condition: GatedOnCasterAndTarget(caster: caster_gates, target: target_gate),
    tag: spend.always,
    target: spell_plan.OnEachStruck,
    spell: support.child(spell4_id: child, base: child),
    gains: [],
  )
}

/// Impale's four Proxies in the order of their rows.
fn impales_proxies() -> List(spell_plan.Proxy) {
  [
    proxy(
      effect: 83_818,
      child: 39_426,
      caster_gates: [caster_gate(id: 38_587)],
      target_gate: target_gate(comparison: 2),
    ),
    proxy(
      effect: 83_819,
      child: 39_427,
      caster_gates: [caster_gate(id: 38_585)],
      target_gate: target_gate(comparison: 2),
    ),
    proxy(
      effect: 85_673,
      child: 39_427,
      caster_gates: [caster_gate(id: 38_587)],
      target_gate: target_gate(comparison: 1),
    ),
    proxy(
      effect: 85_682,
      child: 39_427,
      caster_gates: [caster_gate(id: 38_585)],
      target_gate: target_gate(comparison: 1),
    ),
  ]
}

/// A spell of base 2 with these Proxies, in the place of the planted base 2 spell.
fn spell_with(proxies proxies: List(spell_plan.Proxy)) -> Spell {
  Spell(..support.child(spell4_id: 38_779, base: 2), proxies:)
}

fn plans_with(spell spell: Spell) -> Plans {
  support.with_spells(plans: support.plans(), spells: [
    spell,
    support.stealthing(spell4_id: 38_784, base: 1, rows: [
      support.stealth_row(id: 83_834, breaks: spell_plan.KeptOnDamage),
    ]),
  ])
}

// ---- the units ----

/// The caster, unit 7, standing at x and z, facing yaw 0.
fn caster_at(x x: Float, z z: Float) -> Caster {
  let caster = support.caster()
  cast.Caster(
    ..caster,
    place: start_place.moved(
      place: caster.place,
      x:,
      y: start_place.y(caster.place),
      z:,
    ),
  )
}

fn hit(unit_id unit_id: Int) -> cast.Struck {
  cast.Hit(
    unit_id:,
    unit: cast.HitCreature(life: 1, struck_at_ms: 0),
    descriptions: [],
    controls: [],
    armor_removed: 0,
  )
}

/// The child casts a step started, each as (Spell4 id, primary target unit id).
fn children_started(effects effects: List(Effect)) -> List(#(Int, Int)) {
  list.map(
    support.frames_of(message_id: spell_started.message_id, effects:),
    fn(frame) {
      let assert Ok(decoded) = spell_started.decode(frame.body)
        as "a 0x7ff the rule wrote decodes"
      #(decoded.spell4_id, decoded.primary_target_unit_id)
    },
  )
  |> list.sort(fn(first, second) {
    int.compare(first.1, second.1)
    |> order.break_tie(with: int.compare(first.0, second.0))
  })
}

/// The state after the caster pressed the base 1 spell, which stealths it, when `stealthed`.
fn stealthed_or_not(plans plans: Plans, stealthed stealthed: Bool) -> State {
  case stealthed {
    False -> cast.new()
    True ->
      support.pressed_in(
        plans:,
        state: cast.new(),
        caster: caster_at(x: 0.0, z: 5.0),
        bag_index: bag_of_base_1,
        target: 0,
        at: 1000,
      ).0
  }
}

/// The go of a press of base 2 at 2000 ms by the caster, closing a round that Hit these
/// units, whose poses the picture then held, and what it wrote.
fn press_closing(
  spell spell: Spell,
  stealthed stealthed: Bool,
  pressed_by pressed_by: Caster,
  closed_by closed_by: Caster,
  units units: List(#(Int, Pose)),
  hit_units hit_units: List(Int),
) -> List(Effect) {
  let plans = plans_with(spell:)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: stealthed_or_not(plans:, stealthed:),
      caster: pressed_by,
      bag_index: bag_of_base_2,
      target: 0,
      at: 2000,
    )
  support.answered_posed(
    caster: closed_by,
    state:,
    effects: raw,
    at: 2000,
    struck: list.map(hit_units, fn(unit_id) { hit(unit_id:) }),
    rolls: [],
    poses: dict.from_list(units),
  ).1
}

/// Impale struck at the creatures, which the caster stood at `at` for the press and the close.
fn impale_strikes(
  stealthed stealthed: Bool,
  caster_at caster_position: #(Float, Float),
  creatures creatures: List(#(Int, Pose)),
) -> List(#(Int, Int)) {
  let caster = caster_at(x: caster_position.0, z: caster_position.1)
  children_started(effects: press_closing(
    spell: spell_with(proxies: impales_proxies()),
    stealthed:,
    pressed_by: caster,
    closed_by: caster,
    units: creatures,
    hit_units: list.map(creatures, fn(creature) { creature.0 }),
  ))
}

/// A creature, unit 20, at the origin with the yaw its 0x262 gave it.
fn creature_20() -> #(Int, Pose) {
  #(20, prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0))
}

// ---- item 8: Impale from behind ----

pub fn impale_from_behind_starts_exactly_one_child_39427_on_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  assert impale_strikes(stealthed: False, caster_at: #(0.0, 5.0), creatures: [
      creature_20(),
    ])
    == [#(39_427, 20)]
    as "unstealthed (38587 passes, 38585 fails) and behind (5734 passes, 5735 fails): 85673 alone starts, and 39426 does not"
}

pub fn impale_from_stealth_starts_one_child_39427_from_behind_or_in_front_test() -> Nil {
  use <- owned_test.run(60_000)
  // Stealthed, 38585 passes and 38587 fails: 85682 (behind) or 83819 (not behind) starts
  // 39427, never both, and 83818 and 85673 stay shut.
  assert impale_strikes(stealthed: True, caster_at: #(0.0, 5.0), creatures: [
      creature_20(),
    ])
    == [#(39_427, 20)]
    as "from stealth behind the creature: 85682"
  assert impale_strikes(stealthed: True, caster_at: #(0.0, -5.0), creatures: [
      creature_20(),
    ])
    == [#(39_427, 20)]
    as "from stealth in front of the creature: 83819, and one child, not two"
}

// ---- item 9: Impale in front and at the side ----

pub fn impale_in_front_or_at_the_side_starts_39426_alone_test() -> Nil {
  use <- owned_test.run(60_000)
  assert impale_strikes(stealthed: False, caster_at: #(0.0, -5.0), creatures: [
      creature_20(),
    ])
    == [#(39_426, 20)]
    as "in front: 38587 passes and 5735 passes: 83818"
  assert impale_strikes(stealthed: False, caster_at: #(5.0, 0.0), creatures: [
      creature_20(),
    ])
    == [#(39_426, 20)]
    as "at the side, outside the 140 degrees behind: 83818"
  assert impale_strikes(stealthed: False, caster_at: #(-5.0, 0.0), creatures: [
      creature_20(),
    ])
    == [#(39_426, 20)]
    as "at the other side"
}

pub fn two_creatures_struck_at_once_each_get_the_child_their_own_position_decides_test() -> Nil {
  use <- owned_test.run(60_000)
  // The caster at (0, 5): creature 20 at (0, 0) has it behind (z grows away from where a
  // creature at yaw 0 faces), creature 21 at (0, 10) has it in front.
  assert impale_strikes(stealthed: False, caster_at: #(0.0, 5.0), creatures: [
      creature_20(),
      #(21, prerequisite_support.pose(x: 0.0, z: 10.0, yaw: 0.0)),
    ])
    == [#(39_427, 20), #(39_426, 21)]
    as "one check for each unit: 85673 on 20 and 83818 on 21"
}

pub fn a_creatures_own_yaw_turns_the_arc_test() -> Nil {
  use <- owned_test.run(60_000)
  // The same creature place with the yaw of a half turn: the caster at (0, 5) is now in
  // front of it, and the one at (0, -5) behind.
  let turned = #(
    20,
    prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 3.1415927410125732),
  )
  assert impale_strikes(stealthed: False, caster_at: #(0.0, 5.0), creatures: [
      turned,
    ])
    == [#(39_426, 20)]
  assert impale_strikes(stealthed: False, caster_at: #(0.0, -5.0), creatures: [
      turned,
    ])
    == [#(39_427, 20)]
}

// ---- item 5: a missing unit ----

pub fn a_hit_unit_the_picture_no_longer_shows_starts_no_child_and_the_others_still_decide_test() -> Nil {
  use <- owned_test.run(60_000)
  let caster = caster_at(x: 0.0, z: 5.0)
  let effects =
    press_closing(
      spell: spell_with(proxies: impales_proxies()),
      stealthed: False,
      pressed_by: caster,
      closed_by: caster,
      units: [creature_20()],
      hit_units: [20, 21],
    )
  assert children_started(effects:) == [#(39_427, 20)]
    as "unit 21 has no pose: no child on it, and unit 20 behind is struck as before"
  let lines =
    list.filter(support.logs(effects:), fn(line) {
      string.contains(line.1, "unit 21")
    })
  assert lines != [] as "a debug line names the unit"
  list.each(lines, fn(line) {
    assert line.0 == LogDebug
    assert string.contains(line.1, "type 108")
      as "and the type the server could not read"
  })
  assert list.all(support.logs(effects:), fn(line) {
    !string.contains(line.1, "unit 20")
  })
    as "the unit with a pose decides, so it is not logged"
}

// ---- item 10: the pose the round closes with ----

pub fn the_pose_given_at_the_close_decides_not_anything_held_at_the_press_test() -> Nil {
  use <- owned_test.run(60_000)
  let caster = caster_at(x: 0.0, z: 5.0)
  let strike = fn(creature) {
    children_started(
      effects: press_closing(
        spell: spell_with(proxies: impales_proxies()),
        stealthed: False,
        pressed_by: caster,
        closed_by: caster,
        units: [#(20, creature)],
        hit_units: [20],
      ),
    )
  }
  assert strike(prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0))
    == [#(39_427, 20)]
    as "the creature at (0, 0) facing yaw 0 has the caster at (0, 5) behind it"
  assert strike(prerequisite_support.pose(x: 0.0, z: 10.0, yaw: 0.0))
    == [#(39_426, 20)]
    as "the creature the picture shows at (0, 10) at the close has it in front"
}

pub fn a_caster_moved_behind_between_the_press_and_the_close_is_judged_where_it_stands_at_the_close_test() -> Nil {
  use <- owned_test.run(60_000)
  let in_front = caster_at(x: 0.0, z: -5.0)
  let behind = caster_at(x: 0.0, z: 5.0)
  assert children_started(
      effects: press_closing(
        spell: spell_with(proxies: impales_proxies()),
        stealthed: False,
        pressed_by: in_front,
        closed_by: behind,
        units: [creature_20()],
        hit_units: [20],
      ),
    )
    == [#(39_427, 20)]
    as "the caster's 0x637s moved it behind the creature after the press: the round closes with the caster behind"
  assert children_started(
      effects: press_closing(
        spell: spell_with(proxies: impales_proxies()),
        stealthed: False,
        pressed_by: behind,
        closed_by: in_front,
        units: [creature_20()],
        hit_units: [20],
      ),
    )
    == [#(39_426, 20)]
    as "and the other way round"
}

// ---- item 11: caster gates decide first, and a Proxy on the caster ----

pub fn a_failing_caster_gate_starts_no_child_wherever_the_units_stand_test() -> Nil {
  use <- owned_test.run(60_000)
  // 83818 alone (38587 and 5735): a stealthed caster fails 38587, in front or behind.
  let only_83818 = [
    proxy(
      effect: 83_818,
      child: 39_426,
      caster_gates: [caster_gate(id: 38_587)],
      target_gate: target_gate(comparison: 2),
    ),
  ]
  assert children_started(
      effects: press_closing(
        spell: spell_with(proxies: only_83818),
        stealthed: False,
        pressed_by: caster_at(x: 0.0, z: -5.0),
        closed_by: caster_at(x: 0.0, z: -5.0),
        units: [creature_20()],
        hit_units: [20],
      ),
    )
    == [#(39_426, 20)]
    as "the control: an unstealthed caster in front passes 38587 and 5735, so the child starts"
  list.each([#(0.0, -5.0), #(0.0, 5.0), #(5.0, 0.0)], fn(position) {
    let caster = caster_at(x: position.0, z: position.1)
    assert children_started(
        effects: press_closing(
          spell: spell_with(proxies: only_83818),
          stealthed: True,
          pressed_by: caster,
          closed_by: caster,
          units: [creature_20()],
          hit_units: [20],
        ),
      )
      == []
      as "38587 fails against a stealthed caster, so the target gate decides nothing"
  })
}

pub fn a_proxy_on_the_caster_checks_its_target_gate_against_the_caster_on_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  // A Proxy aimed at the caster behind 5734 and one behind 5735: the caster stands on
  // its own point, direction -pi, which is inside row 53 at the caster's yaw 0.
  let on_caster = fn(effect, child, comparison) {
    Proxy(
      ..proxy(
        effect:,
        child:,
        caster_gates: [],
        target_gate: target_gate(comparison:),
      ),
      target: spell_plan.OnCaster,
    )
  }
  let effects =
    press_closing(
      spell: spell_with(proxies: [
        on_caster(1, 100, 1),
        on_caster(2, 101, 2),
      ]),
      stealthed: False,
      pressed_by: caster_at(x: 0.0, z: 5.0),
      closed_by: caster_at(x: 0.0, z: 5.0),
      units: [],
      hit_units: [],
    )
  assert children_started(effects:) == [#(100, 7)]
    as "5734 passes against the caster on itself and 5735 fails; the child's primary target is the caster, unit 7"
}

pub fn a_proxy_on_the_caster_reads_the_casters_own_yaw_test() -> Nil {
  use <- owned_test.run(60_000)
  // At yaw 3.0 row 53 runs from -1.3633235 to 1.0801380: the direction -pi of a unit on
  // its own point is outside it.
  let caster = caster_at(x: 0.0, z: 5.0)
  let turned =
    cast.Caster(
      ..caster,
      place: start_place.turned(
        place: caster.place,
        facing: start_place.Facing(yaw: 3.0, pitch: 0.0, roll: 0.0),
      ),
    )
  let on_caster = fn(comparison) {
    Proxy(
      ..proxy(
        effect: 1,
        child: 100,
        caster_gates: [],
        target_gate: target_gate(comparison:),
      ),
      target: spell_plan.OnCaster,
    )
  }
  let started = fn(comparison) {
    children_started(
      effects: press_closing(
        spell: spell_with(proxies: [on_caster(comparison)]),
        stealthed: False,
        pressed_by: turned,
        closed_by: turned,
        units: [],
        hit_units: [],
      ),
    )
  }
  assert started(1) == [] as "behind: -pi is outside the arc at yaw 3.0"
  assert started(2) == [#(100, 7)] as "not behind"
}

pub fn the_caster_gates_of_a_target_gated_proxy_take_their_rolls_in_order_and_the_target_gate_none_test() -> Nil {
  use <- owned_test.run(60_000)
  // Two Proxies, each behind a caster gate of one type 37 condition (a roll of 50 or less
  // passes: comparison 6, value 50) and the target gate 5734.
  let chance = prerequisite_support.single(id: 1, condition: #(37, 6, 0, 50))
  let spell =
    spell_with(proxies: [
      proxy(
        effect: 1,
        child: 100,
        caster_gates: [chance],
        target_gate: target_gate(comparison: 1),
      ),
      proxy(
        effect: 2,
        child: 101,
        caster_gates: [chance],
        target_gate: target_gate(comparison: 1),
      ),
    ])
  let plans = plans_with(spell:)
  let caster = caster_at(x: 0.0, z: 5.0)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 2000,
    )
  let assert [asked, ..] = support.goes_asked(effects: raw)
    as "the press asks for its go"
  assert cast.rolls_needed(
      cast: state,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [hit(unit_id: 20)],
    )
    == 2
    as "one roll for each caster gate; the target gate of a struck creature takes none"
  let went = fn(rolls) {
    support.answered_posed(
      caster:,
      state:,
      effects: raw,
      at: 2000,
      struck: [hit(unit_id: 20)],
      rolls:,
      poses: dict.from_list([creature_20()]),
    ).1
  }
  assert children_started(effects: went([49, 51])) == [#(100, 20)]
    as "the first Proxy's roll of 49 passes and the second's of 51 fails, in the order the Proxies are checked"
  assert children_started(effects: went([51, 49])) == [#(101, 20)]
}
