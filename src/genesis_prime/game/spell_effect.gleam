//// The envelope every effect row of a planned spell carries, whatever it does: which row it
//// is, the phases it applies in, the points-spent tag that chooses it and when it lands,
//// round the kind-specific payload that `genesis_prime/game/spell_plan` defines.
////
//// - **One list, ranked.** A planned spell holds its effect rows in one list, sorted by the
////   rank of their kinds and, within a kind, in row order, which is the order the cast's
////   gates draw their rolls in (`cast/gate.rolls_needed`) and a go lists its effects in
////   (`cast/control.lasting_applied`).
//// - **Phases and tags are read here once**: a row applies in phase n when bit n of its
////   `phase_flags` is set (every bit for -1) and its tag holds for the points the cast spent
////   (`genesis_prime/game/spend.applies`).
//// - **A periodic row keeps its own shape.** A heal's ticks are a `ticking.Schedule` (delay,
////   tick, life and count); a gain is given each tick for its life with no delay and no
////   count the plan reads, so its tick and life are a `Pulsed` pair; a `Schedule` cannot hold
////   it without inventing the delay and the count.

import genesis_prime/game/lasting
import genesis_prime/game/spend
import genesis_prime/game/ticking
import genesis_prime/table/id.{type Spell4EffectsId}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order

/// When an effect lands after the go of the phase it applies in.
pub type Timing {
  /// At the go.
  Immediate
  /// `delay_ms` after the go (`Spell4Effects.delayTime`).
  Delayed(delay_ms: Int)
  /// At the go, and gives its node a life from `row` (`genesis_prime/game/lasting`).
  Lasts(row: lasting.LastingRow)
  /// At each tick of `schedule` (`genesis_prime/game/ticking`).
  Scheduled(schedule: ticking.Schedule)
  /// Each `tick_ms` for `duration_ms` (Spell4Effects.tickTime and durationTime).
  Pulsed(tick_ms: Int, duration_ms: Int)
}

/// One effect row of a planned spell: the row (`effect_id`), the phases it applies in
/// (`phase_flags`: bit n is phase n, every bit for -1), the tag that chooses it by the points
/// the cast spent, when it lands (`timing`) and the payload of its kind.
pub type PlannedEffect(kind) {
  PlannedEffect(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    tag: spend.Tag,
    timing: Timing,
    kind: kind,
  )
}

/// The Spell4Effects phase flag of a go: bit n is phase n.
pub fn phase_bit(phase phase: Int) -> Int {
  int.bitwise_shift_left(1, phase)
}

/// Whether the flags hold the bit.
pub fn has_flag(flags flags: Int, bit bit: Int) -> Bool {
  int.bitwise_and(flags, bit) != 0
}

/// The effects that apply in phase `phase`, in the order of the list: those whose phase flags
/// hold the phase and whose tag holds for the points the cast spent
/// (genesis_prime/game/spend `applies`).
pub fn in_phase(
  effects effects: List(PlannedEffect(kind)),
  phase phase: Int,
  spent spent: Option(Int),
) -> List(PlannedEffect(kind)) {
  list.filter(effects, fn(planned) {
    has_flag(flags: planned.phase_flags, bit: phase_bit(phase:))
    && spend.applies(tag: planned.tag, spent:)
  })
}

/// The effects sorted by the rank of their kinds, the effects of one rank keeping the order
/// they came in.
pub fn ranked(
  effects effects: List(PlannedEffect(kind)),
  rank rank: fn(kind) -> Int,
) -> List(PlannedEffect(kind)) {
  effects
  |> list.index_map(fn(planned, position) {
    #(rank(planned.kind), position, planned)
  })
  |> list.sort(fn(one, other) {
    int.compare(one.0, other.0)
    |> order.break_tie(int.compare(one.1, other.1))
  })
  |> list.map(fn(entry) { entry.2 })
}
