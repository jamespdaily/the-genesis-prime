//// The rule of a held Proc effect (`genesis_prime/game/proc`): whether one event of its
//// holder fires it. Expected values come from these places:
//// - `Spell4Effects.effectType.14` dataBits02: the chance as 32-bit float bits, 1.0 for
////   most rows and 0.25 here; a draw is a 32-bit word whose fraction (`random.fraction`)
////   is compared with it.
//// - `Spell4Effects.effectType.14.limits`: dataBits05 fires in each dataBits04 ms, or in
////   the proc's life for a dataBits04 of -1 (a guess for the life).
//// - `Spell4Effects.effectType.14.dataBits07` and `0x140561d80`: a filter names a Spell4
////   or a group of Spell4GroupList.
//// - `Spell4Effects.effectType.14.dataBits03`: bit 4 aims at the event's other unit.
//// - `Spell4Effects.effectType.14.prerequisites`: dataBits09 gates the holder and
////   dataBits06 the event's unit. A gate here is one Prerequisite condition of type 28
////   (the unit is in combat, `Prerequisite.prerequisiteTypeId.28`) or of type 37 (a roll,
////   `.37`).
//// - The order of the checks (limit, filter, holder gate, event gate, chance) is the
////   server's own choice, since the client reads no Proc row
////   (`Spell4Effects.effectType.14.client_evaluation`).

import cast_support
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite
import genesis_prime/game/proc.{
  type EventSpell, CannotTell, EventGateFails, EventSpell, FilteredOut, Fires,
  HolderGateFails, MissedChance, OutOfLimit,
}
import genesis_prime/game/spell_plan.{
  Always, AnySpell, AtHolder, AtOtherUnit, ForLife, InGroup, InWindow, LandsHit,
  OfBase, OneSpell, ProcRow,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import owned_test
import prerequisite_support

const holder = 7

const struck = 31

/// A proc as row 208200 holds it, in memory, with the checks open: kind 12 casting 79221,
/// chance 1.0, once in 500 ms, any spell, at the holder, no gate, no delay.
fn row() -> spell_plan.ProcRow {
  ProcRow(
    effect_id: Spell4EffectsId(208_200),
    phase_flags: -1,
    holder: spell_plan.HeldByCaster,
    trigger: LandsHit,
    spell: cast_support.child(spell4_id: 79_221, base: 79_221),
    chance: 1.0,
    limit: InWindow(window_ms: 500, count: 1),
    filter: AnySpell,
    aim: AtHolder,
    event_gate: None,
    holder_gate: None,
    delay_ms: 0,
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition: Always,
    tag: spend.always,
  )
}

fn event(spell spell: Option(EventSpell)) -> proc.Event {
  proc.Event(trigger: LandsHit, other_unit: Some(struck), spell:, holder: None)
}

fn spell_of(
  spell4_id spell4_id: Int,
  spell4_base_id spell4_base_id: Int,
  groups groups: List(Int),
) -> EventSpell {
  EventSpell(
    spell4_id: Spell4Id(spell4_id),
    spell4_base_id: Spell4BaseId(spell4_base_id),
    groups:,
    school: 0,
  )
}

/// The subject a gate of type 28 reads: a unit in combat or not.
fn subject(in_combat in_combat: Bool) -> prerequisite.Subject {
  prerequisite.Subject(
    ..prerequisite_support.holding(held: [], second_unit: None),
    in_combat:,
  )
}

/// A gate of one condition of type 28, comparison 1: the unit is in combat.
fn in_combat_gate() -> Option(prerequisite.Prerequisite) {
  Some(prerequisite_support.single(id: 28_001, condition: #(28, 1, 0, 0)))
}

/// A gate of `count` conditions of type 37, which take one roll each.
fn roll_gate(count count: Int) -> Option(prerequisite.Prerequisite) {
  let conditions = case count {
    1 -> [#(37, 6, 0, 50)]
    _ -> [#(37, 6, 0, 50), #(37, 6, 0, 50)]
  }
  Some(
    prerequisite_support.loaded(id: 37_001, rows: [
      prerequisite_support.row(id: 37_001, flags: 0, conditions:),
    ]),
  )
}

/// What `decide` gives for the proc and the event, at 10_000 ms after the fires given,
/// with the holder and the struck unit both in combat and these draws.
fn decided(
  row row: spell_plan.ProcRow,
  fires_ms fires_ms: List(Int),
  now_ms now_ms: Int,
  event event: proc.Event,
  draw draw: Option(Int),
) -> proc.Verdict {
  proc.decide(
    row:,
    fires_ms:,
    now_ms:,
    event:,
    holder_unit: holder,
    holder_subject: subject(in_combat: True),
    event_subject: subject(in_combat: True),
    draw:,
    rolls: [],
  )
}

pub fn a_chance_1_proc_fires_on_every_event_and_takes_no_draw_test() -> Nil {
  use <- owned_test.run(5000)
  assert proc.draws_needed(row: row()) == #(0, 0)
    as "a chance of 1.0 (dataBits02 1065353216) takes no draw"
  assert decided(
      row: row(),
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
  assert decided(
      row: row(),
      fires_ms: [],
      now_ms: 999_999,
      event: event(
        spell: Some(spell_of(spell4_id: 1, spell4_base_id: 1, groups: [])),
      ),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
}

pub fn a_chance_0_25_proc_fires_on_a_draw_below_0_25_and_not_on_one_at_or_above_it_test() -> Nil {
  use <- owned_test.run(5000)
  let quarter = ProcRow(..row(), chance: 0.25)
  assert proc.draws_needed(row: quarter) == #(1, 0)
    as "a chance below 1.0 takes one 32-bit word"
  // 0.25 * 2^32 is 1073741824: the word's fraction is the word over 2^32.
  assert decided(
      row: quarter,
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      draw: Some(1_073_741_823),
    )
    == Fires(at: holder, delay_ms: 0)
    as "a draw of 0.25 * 2^32 - 1 is below 0.25"
  assert decided(
      row: quarter,
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      draw: Some(1_073_741_824),
    )
    == MissedChance
    as "a draw of 0.25 * 2^32 is not below 0.25"
}

pub fn a_window_3000_count_1_proc_fires_once_in_3_seconds_whatever_the_events_test() -> Nil {
  use <- owned_test.run(5000)
  let once = ProcRow(..row(), limit: InWindow(window_ms: 3000, count: 1))
  let at = fn(now_ms, fires_ms) {
    decided(
      row: once,
      fires_ms:,
      now_ms:,
      event: event(spell: None),
      draw: None,
    )
  }
  assert at(10_000, []) == Fires(at: holder, delay_ms: 0)
  assert at(11_000, [10_000]) == OutOfLimit
    as "a fire 1000 ms ago is in the window"
  assert at(12_999, [10_000]) == OutOfLimit
    as "a fire 2999 ms ago is in the window"
  assert at(13_000, [10_000]) == Fires(at: holder, delay_ms: 0)
    as "a fire exactly 3000 ms ago is outside the window, as the old triggers' windows are"
  assert proc.counted(
      limit: InWindow(window_ms: 3000, count: 1),
      fires_ms: [10_000, 5000],
      now_ms: 12_000,
    )
    == [10_000]
    as "the fires that still count"
}

pub fn a_for_life_proc_fires_up_to_its_count_and_then_never_test() -> Nil {
  use <- owned_test.run(5000)
  // A guess: dataBits04 -1 holds no window, and the count is read as the fires of the
  // proc's life (`spell_plan.ForLife`).
  let twice = ProcRow(..row(), limit: ForLife(count: 2))
  let at = fn(fires_ms) {
    decided(
      row: twice,
      fires_ms:,
      now_ms: 1_000_000_000,
      event: event(spell: None),
      draw: None,
    )
  }
  assert at([]) == Fires(at: holder, delay_ms: 0)
  assert at([0]) == Fires(at: holder, delay_ms: 0)
  assert at([0, 10]) == OutOfLimit
    as "two fires, however long ago, are all it has"
}

pub fn a_group_filter_passes_only_an_event_spell_in_the_group_test() -> Nil {
  use <- owned_test.run(5000)
  let grouped = ProcRow(..row(), filter: InGroup(group_id: 463))
  assert decided(
      row: grouped,
      fires_ms: [],
      now_ms: 0,
      event: event(
        spell: Some(
          spell_of(spell4_id: 79_220, spell4_base_id: 54_946, groups: [5, 463]),
        ),
      ),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
    as "a spell of group 463 (Spell4GroupList) passes"
  assert decided(
      row: grouped,
      fires_ms: [],
      now_ms: 0,
      event: event(
        spell: Some(
          spell_of(spell4_id: 79_220, spell4_base_id: 54_946, groups: [5, 464]),
        ),
      ),
      draw: None,
    )
    == FilteredOut
    as "a spell of other groups does not"
}

pub fn a_one_spell_filter_passes_only_that_spell4_test() -> Nil {
  use <- owned_test.run(5000)
  let one = ProcRow(..row(), filter: OneSpell(spell4_id: Spell4Id(79_220)))
  assert decided(
      row: one,
      fires_ms: [],
      now_ms: 0,
      event: event(
        spell: Some(
          spell_of(spell4_id: 79_220, spell4_base_id: 54_946, groups: []),
        ),
      ),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
  assert decided(
      row: one,
      fires_ms: [],
      now_ms: 0,
      event: event(
        spell: Some(
          spell_of(spell4_id: 79_221, spell4_base_id: 54_947, groups: [463]),
        ),
      ),
      draw: None,
    )
    == FilteredOut
}

pub fn a_base_filter_passes_only_an_event_spell_of_that_spell4base_test() -> Nil {
  use <- owned_test.run(5000)
  let based =
    ProcRow(..row(), filter: OfBase(spell4_base_id: Spell4BaseId(54_946)))
  assert decided(
      row: based,
      fires_ms: [],
      now_ms: 0,
      event: event(
        spell: Some(
          spell_of(spell4_id: 79_220, spell4_base_id: 54_946, groups: []),
        ),
      ),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
    as "a Spell4 of the Spell4Base passes"
  assert decided(
      row: based,
      fires_ms: [],
      now_ms: 0,
      event: event(
        spell: Some(
          spell_of(spell4_id: 79_225, spell4_base_id: 54_946, groups: []),
        ),
      ),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
    as "so does another tier of it: the filter names the base, not one Spell4"
  assert decided(
      row: based,
      fires_ms: [],
      now_ms: 0,
      event: event(
        spell: Some(
          spell_of(spell4_id: 79_221, spell4_base_id: 54_947, groups: [463]),
        ),
      ),
      draw: None,
    )
    == FilteredOut
    as "a Spell4 of another Spell4Base does not"
}

pub fn a_filtered_proc_never_fires_for_an_event_with_no_spell_test() -> Nil {
  use <- owned_test.run(5000)
  let none = event(spell: None)
  assert decided(
      row: ProcRow(..row(), filter: InGroup(group_id: 463)),
      fires_ms: [],
      now_ms: 0,
      event: none,
      draw: None,
    )
    == FilteredOut
    as "a stealth, combat or death event has no spell for a group to name"
  assert decided(
      row: ProcRow(..row(), filter: OneSpell(spell4_id: Spell4Id(1))),
      fires_ms: [],
      now_ms: 0,
      event: none,
      draw: None,
    )
    == FilteredOut
  assert decided(
      row: ProcRow(..row(), filter: OfBase(spell4_base_id: Spell4BaseId(1))),
      fires_ms: [],
      now_ms: 0,
      event: none,
      draw: None,
    )
    == FilteredOut
  assert decided(row: row(), fires_ms: [], now_ms: 0, event: none, draw: None)
    == Fires(at: holder, delay_ms: 0)
    as "a proc with no filter fires for it"
}

pub fn a_bit_4_proc_fires_at_the_other_unit_and_one_without_at_the_holder_test() -> Nil {
  use <- owned_test.run(5000)
  assert decided(
      row: ProcRow(..row(), aim: AtOtherUnit, delay_ms: 1000),
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      draw: None,
    )
    == Fires(at: struck, delay_ms: 1000)
    as "dataBits03 bit 4 casts at the creature the hit struck, after delayTime"
  assert decided(
      row: row(),
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
  assert decided(
      row: ProcRow(..row(), aim: AtOtherUnit),
      fires_ms: [],
      now_ms: 0,
      event: proc.Event(
        trigger: LandsHit,
        other_unit: None,
        spell: None,
        holder: None,
      ),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
    as "an event with no other unit falls back to the holder"
}

pub fn a_holder_gate_that_fails_stops_the_fire_and_counts_no_fire_test() -> Nil {
  use <- owned_test.run(5000)
  let gated = ProcRow(..row(), holder_gate: in_combat_gate())
  assert proc.decide(
      row: gated,
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      holder_unit: holder,
      holder_subject: subject(in_combat: False),
      event_subject: subject(in_combat: True),
      draw: None,
      rolls: [],
    )
    == HolderGateFails
    as "dataBits09 is checked against the holder: it is not in combat"
  assert proc.decide(
      row: gated,
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      holder_unit: holder,
      holder_subject: subject(in_combat: True),
      event_subject: subject(in_combat: False),
      draw: None,
      rolls: [],
    )
    == Fires(at: holder, delay_ms: 0)
    as "and passes for a holder in combat, whatever the event's unit does"
}

pub fn an_event_gate_that_fails_stops_the_fire_test() -> Nil {
  use <- owned_test.run(5000)
  let gated = ProcRow(..row(), event_gate: in_combat_gate())
  assert proc.decide(
      row: gated,
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      holder_unit: holder,
      holder_subject: subject(in_combat: True),
      event_subject: subject(in_combat: False),
      draw: None,
      rolls: [],
    )
    == EventGateFails
    as "dataBits06 is checked against the event's unit"
  assert decided(
      row: gated,
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      draw: None,
    )
    == Fires(at: holder, delay_ms: 0)
}

pub fn an_event_gate_condition_the_server_cannot_read_stops_the_fire_with_a_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  let unread = prerequisite_support.unread_type()
  let gated =
    ProcRow(
      ..row(),
      event_gate: Some(
        prerequisite_support.single(id: 99_001, condition: #(unread, 1, 0, 0)),
      ),
    )
  let assert CannotTell(why:) =
    decided(
      row: gated,
      fires_ms: [],
      now_ms: 0,
      event: event(spell: None),
      draw: None,
    )
    as "a gate of a type the server does not read cannot tell, so the proc does not fire"
  assert string.contains(why, "208200")
    && string.contains(why, "event gate")
    && string.contains(why, "type " <> int.to_string(unread))
    as "the line names the proc, the gate and the type"
}

pub fn each_proc_takes_its_draw_and_rolls_even_when_an_earlier_check_stops_it_test() -> Nil {
  use <- owned_test.run(5000)
  let busy =
    ProcRow(
      ..row(),
      chance: 0.5,
      holder_gate: roll_gate(count: 1),
      event_gate: roll_gate(count: 2),
    )
  assert proc.draws_needed(row: busy) == #(1, 3)
    as "one chance word, one roll for the holder gate and two for the event gate"
  assert proc.decide(
      row: busy,
      fires_ms: [0],
      now_ms: 1,
      event: event(spell: None),
      holder_unit: holder,
      holder_subject: subject(in_combat: True),
      event_subject: subject(in_combat: True),
      draw: Some(0),
      rolls: [1, 2, 3],
    )
    == OutOfLimit
    as "a proc out of its limit is stopped, and its draws are the shell's to throw away"
  assert proc.draws_needed(row: busy) == #(1, 3)
    as "the count does not depend on what stopped it"
}

pub fn the_holder_gate_takes_the_first_roll_and_the_event_gate_the_second_test() -> Nil {
  use <- owned_test.run(5000)
  // Both gates are one type 37 condition, roll 50 or less (row 4585,
  // `Prerequisite.prerequisiteTypeId.37`), so a roll of 10 passes it and one of 95 fails it,
  // and the order of the two rolls decides which gate fails.
  let two_gates =
    ProcRow(
      ..row(),
      holder_gate: roll_gate(count: 1),
      event_gate: roll_gate(count: 1),
    )
  let with_rolls = fn(rolls: List(Int)) {
    proc.decide(
      row: two_gates,
      fires_ms: [],
      now_ms: 100,
      event: event(spell: None),
      holder_unit: holder,
      holder_subject: subject(in_combat: True),
      event_subject: subject(in_combat: True),
      draw: None,
      rolls:,
    )
  }
  assert with_rolls([10, 95]) == EventGateFails
    as "the holder gate takes 10 and passes, the event gate takes 95 and fails"
  assert with_rolls([95, 10]) == HolderGateFails
    as "the holder gate takes 95 and fails before the event gate is checked"
}

pub fn the_checks_run_limit_filter_holder_gate_event_gate_then_chance_test() -> Nil {
  use <- owned_test.run(5000)
  // A proc that fails every check, then each check mended in order.
  let failing =
    ProcRow(
      ..row(),
      chance: 0.25,
      filter: InGroup(group_id: 463),
      holder_gate: in_combat_gate(),
      event_gate: in_combat_gate(),
    )
  let verdict = fn(
    row: spell_plan.ProcRow,
    fires_ms: List(Int),
    groups: List(Int),
    holder_in_combat: Bool,
    event_in_combat: Bool,
    draw: Int,
  ) {
    proc.decide(
      row:,
      fires_ms:,
      now_ms: 100,
      event: event(
        spell: Some(spell_of(spell4_id: 79_220, spell4_base_id: 54_946, groups:)),
      ),
      holder_unit: holder,
      holder_subject: subject(in_combat: holder_in_combat),
      event_subject: subject(in_combat: event_in_combat),
      draw: Some(draw),
      rolls: [],
    )
  }
  let miss = 4_000_000_000
  assert verdict(failing, [50], [], False, False, miss) == OutOfLimit
  assert verdict(failing, [], [], False, False, miss) == FilteredOut
  assert verdict(failing, [], [463], False, False, miss) == HolderGateFails
  assert verdict(failing, [], [463], True, False, miss) == EventGateFails
  assert verdict(failing, [], [463], True, True, miss) == MissedChance
  assert verdict(failing, [], [463], True, True, 0)
    == Fires(at: holder, delay_ms: 0)
}
