//// Prerequisite type 108, where the check's second unit stands around the first unit's facing
//// (`genesis_prime/game/prerequisite`). Expected values come from these places:
//// - `PrerequisitePositional` 0x14049d940 (`Prerequisite.prerequisiteTypeId.108`, saved C
////   6ba38d868f75acff), whose arithmetic is in 32-bit floats in the client's order. The
////   numbers below were worked out outside the code under test, by a script that repeats
////   that order step by step (start = (angleCenter - half) * k + facing, end = (half +
////   angleCenter) * k + facing, k = pi_f32 * (1/180)_f32, each end wrapped with fmod, the
////   direction atan2(-(x2 - x1), -(z2 - z1)) with each difference negated by a sign flip) and
////   rounds each result to 32 bits. The constants are read from the client's bytes: pi
////   0x40490fdb at 0x140b79fac and 0x140c3b438, 2 pi 0x40c90fdb at 0x140b7a018, 1/180
////   0x3bb60b61 at 0x140b79d28, 0.5 at 0x140b79e48, the sign flip 0x80000000 at 0x140b7b530.
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- PositionalRequirement 18 53`):
////   row 53 is angleCenter 180, angleRange 140, flags 0, the 140 degrees behind the first unit;
////   row 18 is 180, 90, flags 1. `-- Prerequisite 5734 5735`: 5734 is (108, comparison 1,
////   objectId 53) and 5735 the same with comparison 2.
//// - The flags bit 0 swap: 0x14049d984 `test byte [rax+0xc], 1` exchanges the two units.
//// - The no-arc case: 0x14049d95b `test r9, r9` (the second unit), 0x14049d96b `test ecx, ecx`
////   (the objectId) and a missing row all lead to comparison 2 passing and any other failing;
////   the first unit is never tested for none.
//// - The server's choice (the `shown` doc): a struck creature is known by its place alone, so
////   every condition that reads what it holds besides its place is `NotRead`.

import client_tables
import genesis_prime/game/area.{type Pose, Point, Pose}
import genesis_prime/game/prerequisite.{
  type Subject, type Verdict, Fails, NoSecondUnit, NotPlaced, NotRead, Passes,
  PlaceOnly, Placed, Subject,
}
import genesis_prime/table/id.{PrerequisiteId}
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import prerequisite_support
import unitest

/// A unit's ground point and yaw.
fn pose(x x: Float, z z: Float, yaw yaw: Float) -> Pose {
  Pose(at: Point(x:, z:), yaw:)
}

/// The 32-bit float nearest pi / 2, pi, 3 pi / 4 and -pi / 4: the yaws a client holds.
const quarter_turn = 1.5707963705062866

const half_turn = 3.1415927410125732

const three_quarters_of_half_turn = 2.356194496154785

const minus_eighth_turn = -0.7853981852531433

/// The first unit at the origin, facing `yaw`.
fn first_at_origin(yaw yaw: Float) -> Pose {
  pose(x: 0.0, z: 0.0, yaw:)
}

fn gate_of(
  comparison comparison: Int,
  arc arc: positional_requirement.PositionalRequirement,
  value value: Int,
) -> prerequisite.Prerequisite {
  prerequisite_support.prerequisite_of_arcs(
    row: prerequisite_support.row(id: 1, flags: 0, conditions: [
      #(108, comparison, arc.id, value),
    ]),
    arcs: [arc],
  )
}

fn subject_of(positions positions: prerequisite.Positions) -> Subject {
  Subject(
    ..prerequisite_support.holding(held: [], second_unit: Some(2)),
    positions:,
  )
}

/// The verdict of a type 108 condition on this arc and comparison for two units.
fn verdict_of(
  comparison comparison: Int,
  arc arc: positional_requirement.PositionalRequirement,
  first first: Pose,
  second second: Pose,
) -> Verdict {
  prerequisite.check(
    prerequisite: gate_of(comparison:, arc:, value: 0),
    subject: subject_of(positions: Placed(first:, second:)),
  )
}

/// Whether comparison 1 passes: the second unit is in the arc.
fn is_in(
  arc arc: positional_requirement.PositionalRequirement,
  first first: Pose,
  second second: Pose,
) -> Bool {
  case verdict_of(comparison: 1, arc:, first:, second:) {
    Passes -> True
    Fails -> False
    NotRead(..) -> panic as "both units are placed, so the verdict is decided"
  }
}

// ---- item 1: the arc math with the wrap ----

pub fn row_53_at_yaw_0_crosses_the_wrap_and_holds_the_unit_behind_but_not_in_front_or_beside_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  let first = first_at_origin(yaw: 0.0)
  // Start 1.9198625, end -1.9198620: the arc crosses the wrap.
  assert is_in(arc:, first:, second: pose(x: 0.0, z: 5.0, yaw: 0.0))
    as "behind: the direction is atan2(-0, -5) = -pi, below the end -1.9198620"
  assert !is_in(arc:, first:, second: pose(x: 0.0, z: -5.0, yaw: 0.0))
    as "in front: the direction is -0.0, between the end and the start"
  assert !is_in(arc:, first:, second: pose(x: 5.0, z: 0.0, yaw: 0.0))
    as "beside at +x: the direction is -pi/2"
  assert !is_in(arc:, first:, second: pose(x: -5.0, z: 0.0, yaw: 0.0))
    as "beside at -x: the direction is pi/2"
}

pub fn row_53_at_a_quarter_turn_does_not_wrap_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  // Start -2.7925265, end -0.3490651.
  let first = first_at_origin(yaw: quarter_turn)
  assert is_in(arc:, first:, second: pose(x: 5.0, z: 0.0, yaw: 0.0))
    as "the direction -pi/2 lies between the ends"
  assert !is_in(arc:, first:, second: pose(x: 0.0, z: 5.0, yaw: 0.0))
    as "the direction -pi lies below the start"
}

pub fn row_53_at_yaw_3_wraps_both_ends_so_the_unit_in_front_is_inside_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  // Unwrapped the ends are 4.9199 and 7.3633; wrapped they are -1.3633235 and 1.0801380.
  let first = first_at_origin(yaw: 3.0)
  assert is_in(arc:, first:, second: pose(x: 0.0, z: -5.0, yaw: 0.0))
    as "the direction -0.0 lies between the wrapped ends"
  assert !is_in(arc:, first:, second: pose(x: 0.0, z: 5.0, yaw: 0.0))
    as "the direction -pi lies below the start"
}

pub fn a_direction_equal_to_an_end_of_the_arc_is_inside_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Row (90, 180) at yaw 0 starts at 0.0 and its end is -3.1415923, so it crosses the
  // wrap; the unit in front has the direction -0.0, equal to the start.
  assert is_in(
    arc: prerequisite_support.arc_row(id: 1, center: 90, range: 180, flags: 0),
    first: first_at_origin(yaw: 0.0),
    second: pose(x: 0.0, z: -5.0, yaw: 0.0),
  )
    as "equal to the start of a wrapping arc"
  // Row (30, 30) at yaw -pi/4 runs from -0.5235989 to 0.0, with no wrap: the same unit
  // has a direction equal to the end.
  assert is_in(
    arc: prerequisite_support.arc_row(id: 1, center: 30, range: 30, flags: 0),
    first: first_at_origin(yaw: minus_eighth_turn),
    second: pose(x: 0.0, z: -5.0, yaw: 0.0),
  )
    as "equal to the end of an arc with no wrap"
  // Row (30, 30) at yaw 3 pi / 4 runs from 2.6179936 to -3.1415927, which wraps: the unit
  // behind has the direction -pi, equal to the end.
  assert is_in(
    arc: prerequisite_support.arc_row(id: 1, center: 30, range: 30, flags: 0),
    first: first_at_origin(yaw: three_quarters_of_half_turn),
    second: pose(x: 0.0, z: 5.0, yaw: 0.0),
  )
    as "equal to the end of a wrapping arc"
  assert !is_in(
    arc: prerequisite_support.arc_row(id: 1, center: 30, range: 30, flags: 0),
    first: first_at_origin(yaw: minus_eighth_turn),
    second: pose(x: 5.0, z: 0.0, yaw: 0.0),
  )
    as "a unit beside, past the end, is outside the same arc"
}

pub fn the_direction_runs_from_the_first_unit_to_the_second_wherever_they_stand_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  assert is_in(
    arc:,
    first: pose(x: 100.5, z: -20.25, yaw: 0.0),
    second: pose(x: 100.5, z: -15.25, yaw: 0.0),
  )
    as "5 units behind, away from the origin: the difference is taken first, in 32 bits"
  assert !is_in(
    arc:,
    first: pose(x: 100.5, z: -20.25, yaw: 0.0),
    second: pose(x: 100.5, z: -25.25, yaw: 0.0),
  )
    as "5 units in front"
}

// ---- item 2: flags bit 0 swaps the units ----

pub fn flags_bit_0_turns_the_arc_with_the_second_unit_and_measures_from_it_to_the_first_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 18: 180, 90, flags 1. The first unit at the origin, the second 5 units behind it.
  let swapped =
    prerequisite_support.arc_row(id: 18, center: 180, range: 90, flags: 1)
  let plain =
    prerequisite_support.arc_row(id: 18, center: 180, range: 90, flags: 0)
  let first = first_at_origin(yaw: 0.0)
  let second_facing_0 = pose(x: 0.0, z: 5.0, yaw: 0.0)
  let second_facing_pi = pose(x: 0.0, z: 5.0, yaw: half_turn)
  assert is_in(arc: plain, first:, second: second_facing_0)
    as "flags 0: from the first unit the second is behind, direction -pi, in 135 to 225 degrees"
  assert !is_in(arc: swapped, first:, second: second_facing_0)
    as "flags 1: from the second unit the first is in front (direction -0.0), outside the arc turned by the second's yaw 0"
  assert is_in(arc: swapped, first:, second: second_facing_pi)
    as "flags 1 turns with the second unit's yaw: at pi the arc is -45 to 45 degrees and holds -0.0"
  assert is_in(arc: plain, first:, second: second_facing_pi)
    as "flags 0 does not read the second unit's yaw"
}

// ---- item 3: every comparison value ----

pub fn comparison_1_passes_inside_the_arc_and_2_outside_it_and_any_other_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  let first = first_at_origin(yaw: 0.0)
  let behind = pose(x: 0.0, z: 5.0, yaw: 0.0)
  let in_front = pose(x: 0.0, z: -5.0, yaw: 0.0)
  let comparisons = [0, 1, 2, 3, 4, 5, 6, 7]
  assert list.map(comparisons, fn(comparison) {
      verdict_of(comparison:, arc:, first:, second: behind)
    })
    == [Fails, Passes, Fails, Fails, Fails, Fails, Fails, Fails]
    as "inside the arc: 1 passes, 2 fails, and 0, 3 to 7 have no case (0x14049d940's tail)"
  assert list.map(comparisons, fn(comparison) {
      verdict_of(comparison:, arc:, first:, second: in_front)
    })
    == [Fails, Fails, Passes, Fails, Fails, Fails, Fails, Fails]
    as "outside the arc: 2 passes and 1 fails"
}

pub fn the_value_of_the_condition_is_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 26524's value is 24489; no other row has a value that plays a part either.
  let arc = prerequisite_support.behind_arc()
  list.each([0, 24_489, 0xFFFFFFFF], fn(value) {
    let subject =
      subject_of(positions: Placed(
        first: first_at_origin(yaw: 0.0),
        second: pose(x: 0.0, z: 5.0, yaw: 0.0),
      ))
    assert prerequisite.check(
        prerequisite: gate_of(comparison: 1, arc:, value:),
        subject:,
      )
      == Passes
      as "the value changes nothing"
    assert prerequisite.check(
        prerequisite: gate_of(comparison: 2, arc:, value:),
        subject:,
      )
      == Fails
  })
}

// ---- item 4: no arc, no second unit, one point ----

pub fn with_no_arc_comparison_2_passes_and_every_other_comparison_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let placed =
    Placed(
      first: first_at_origin(yaw: 0.0),
      second: pose(x: 0.0, z: 5.0, yaw: 0.0),
    )
  let verdicts = fn(comparison, positions) {
    prerequisite.check(
      prerequisite: prerequisite_support.prerequisite_of(
        row: prerequisite_support.row(id: 1, flags: 0, conditions: [
          #(108, comparison, 0, 0),
        ]),
      ),
      subject: subject_of(positions:),
    )
  }
  assert list.map([1, 2, 3], fn(comparison) { verdicts(comparison, placed) })
    == [Fails, Passes, Fails]
    as "objectId 0 is the client's no-arc case (0x14049d96b)"
  assert list.map([1, 2, 3], fn(comparison) { verdicts(comparison, NotPlaced) })
    == [Fails, Passes, Fails]
    as "the client decides it before it reads either unit's place"
}

pub fn with_no_second_unit_comparison_2_passes_and_every_other_comparison_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  let verdicts =
    list.map([1, 2, 3], fn(comparison) {
      prerequisite.check(
        prerequisite: gate_of(comparison:, arc:, value: 0),
        subject: subject_of(positions: NoSecondUnit),
      )
    })
  assert verdicts == [Fails, Passes, Fails]
    as "a check with no second unit (0x14049d95b) never reads the first unit either"
}

pub fn two_units_on_one_point_are_in_row_53s_arc_at_yaw_0_test() -> Nil {
  use <- owned_test.run(5000)
  // The differences are +0.0, each negated to -0.0, and atan2(-0.0, -0.0) is -pi
  // (0x140b7b530's sign flip), which is below the end -1.9198620 of row 53 at yaw 0.
  let here = pose(x: 3.0, z: 4.0, yaw: 0.0)
  assert is_in(
    arc: prerequisite_support.behind_arc(),
    first: here,
    second: here,
  )
    as "the one caster-apply use of type 108 (Spell4Effects 48979's prerequisite) puts the caster on itself"
}

// ---- item 5: a unit that is not placed, a creature known by its place alone ----

pub fn a_unit_the_picture_no_longer_shows_leaves_type_108_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  list.each([1, 2], fn(comparison) {
    assert prerequisite.check(
        prerequisite: gate_of(comparison:, arc:, value: 0),
        subject: prerequisite.of_struck(
          first: None,
          second: pose(x: 0.0, z: 5.0, yaw: 0.0),
          second_unit: 7,
        ),
      )
      == NotRead(prerequisite_type: 108)
      as "a Hit unit with no pose: the server cannot say what the client would"
  })
}

pub fn a_struck_creature_is_placed_and_checked_with_the_caster_as_the_second_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let arc = prerequisite_support.behind_arc()
  let creature = first_at_origin(yaw: 0.0)
  let subject_with = fn(caster) {
    prerequisite.of_struck(
      first: Some(creature),
      second: caster,
      second_unit: 7,
    )
  }
  assert prerequisite.check(
      prerequisite: gate_of(comparison: 1, arc:, value: 0),
      subject: subject_with(pose(x: 0.0, z: 5.0, yaw: 0.0)),
    )
    == Passes
    as "the caster behind the creature"
  assert prerequisite.check(
      prerequisite: gate_of(comparison: 1, arc:, value: 0),
      subject: subject_with(pose(x: 0.0, z: -5.0, yaw: 0.0)),
    )
    == Fails
    as "the caster in front"
}

pub fn a_struck_creature_gives_not_read_for_every_type_that_reads_what_it_holds_test() -> Nil {
  use <- owned_test.run(5000)
  let creature =
    Subject(
      ..prerequisite.of_struck(
        first: Some(first_at_origin(yaw: 0.0)),
        second: pose(x: 0.0, z: 5.0, yaw: 0.0),
        second_unit: 7,
      ),
      rolls: [50],
    )
  assert creature.seen == PlaceOnly
  // Types 15, 28, 37, 50, 59, 71 and 73, each with a comparison and value that a unit
  // holding what the condition asks would pass.
  list.each(
    [
      #(15, 2, 0, 1000),
      #(28, 2, 0, 0),
      #(37, 4, 0, 1),
      #(50, 2, 0, 39_407),
      #(59, 1, 42_569, 0),
      #(71, 4, 1, 0),
      #(73, 4, 1, 0),
    ],
    fn(condition) {
      assert prerequisite.check(
          prerequisite: prerequisite_support.single(id: 1, condition:),
          subject: creature,
        )
        == NotRead(prerequisite_type: condition.0)
        as "the connection holds none of a creature's casts, combat state, vitals or rolls"
    },
  )
}

// ---- item 6: the rows of the client ----

fn client_rows_of_type_108() -> List(prerequisite_table.Prerequisite) {
  list.filter(prerequisite_table.all(client_tables.shared()), fn(row) {
    list.contains(prerequisite.condition_types(row:), 108)
  })
}

pub fn the_clients_72_rows_with_a_type_108_condition_all_decode_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = client_rows_of_type_108()
  assert list.length(rows) == 72
    as "72 Prerequisite rows hold a type 108 condition (`table_rows -- Prerequisite prerequisiteTypeId0=108`, `1=108` and `2=108`)"
  list.each(rows, fn(row) {
    let assert Ok(_) = prerequisite.of_row(row:, tables:)
      as "every objectId of a type 108 condition names a PositionalRequirement row"
  })
  let conditions =
    list.flat_map(rows, fn(row) {
      list.filter(prerequisite.kept_conditions(row:), fn(condition) {
        condition.0 == 108
      })
    })
  assert list.length(conditions) == 75 as "the 72 rows hold 75 conditions"
  assert list.count(conditions, fn(condition) { condition.1 == 1 }) == 61
    as "61 with comparison 1"
  assert list.count(conditions, fn(condition) { condition.1 == 2 }) == 14
    as "and 14 with comparison 2"
  assert list.all(conditions, fn(condition) { condition.2 != 0 })
    as "none has objectId 0"
  assert list.count(conditions, fn(condition) {
      let assert Ok(arc) =
        positional_requirement.get(
          tables:,
          id: id.PositionalRequirementId(condition.2),
        )
      arc.flags % 2 == 1
    })
    == 25
    as "25 turn with the second unit (flags bit 0) and 50 do not"
  assert set.size(
      set.from_list(list.map(conditions, fn(condition) { condition.2 })),
    )
    <= 52
    as "the PositionalRequirement table has 52 rows"
}

pub fn a_row_naming_a_positional_requirement_the_table_lacks_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert prerequisite.of_row(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(108, 1, 999, 0),
      ]),
      tables: client_tables.shared(),
    )
    == Error(prerequisite.MissingRow(table: "PositionalRequirement", id: 999))
    as "the client would read it as no arc, but no row in the game hits that case, so the load refuses it"
  assert prerequisite.of_row_with(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(108, 1, 999, 0),
      ]),
      find_arc: fn(_) { Error(Nil) },
    )
    == Error(prerequisite.MissingRow(table: "PositionalRequirement", id: 999))
}

pub fn type_108_is_read_by_the_coverage_measure_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite.is_read(type_id: 108)
    as "the measure counts a type as handled when the decode reads it"
}

pub fn the_rows_5734_and_5735_of_impale_decode_as_the_clients_hold_them_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(behind) =
    prerequisite_table.get(tables:, id: PrerequisiteId(5734))
  let assert Ok(not_behind) =
    prerequisite_table.get(tables:, id: PrerequisiteId(5735))
  assert prerequisite.kept_conditions(row: behind) == [#(108, 1, 53, 0)]
  assert prerequisite.kept_conditions(row: not_behind) == [#(108, 2, 53, 0)]
  let assert Ok(arc) =
    positional_requirement.get(tables:, id: id.PositionalRequirementId(53))
  assert #(arc.angle_center, arc.angle_range, arc.flags) == #(180, 140, 0)
}
