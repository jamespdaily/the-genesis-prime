//// The envelope every effect row of a planned spell carries, whatever it does: which row it
//// is, the phases it applies in and the points-spent tag that chooses it, around the
//// kind-specific payload that `genesis_prime/game/spell_plan` defines.
////
//// - **One list, ranked.** A planned spell holds its effect rows in one list, sorted by the
////   rank of their kinds and, within a kind, in row order, which is the order the cast's
////   gates draw their rolls in (`cast/gate.rolls_needed`) and a go lists its effects in
////   (`cast/control.lasting_applied`).
//// - **Phases and tags are read here once**: a row applies in phase n when bit n of its
////   `phase_flags` is set (every bit for -1) and its tag holds for the points the cast spent
////   (`genesis_prime/game/spend.applies`).

import genesis_prime/game/spend
import genesis_prime/table/id.{type Spell4EffectsId}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order

/// One effect row of a planned spell: the row (`effect_id`), the phases it applies in
/// (`phase_flags`: bit n is phase n, every bit for -1), the tag that chooses it by the points
/// the cast spent and the payload of its kind.
pub type PlannedEffect(kind) {
  PlannedEffect(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    tag: spend.Tag,
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

/// Whether a row with these phase flags and this tag applies in phase `phase`: bit n of the
/// flags is phase n (every bit for -1) and the tag holds for the points the cast spent
/// (genesis_prime/game/spend `applies`).
pub fn applies_in_phase(
  phase_flags phase_flags: Int,
  tag tag: spend.Tag,
  phase phase: Int,
  spent spent: Option(Int),
) -> Bool {
  has_flag(flags: phase_flags, bit: phase_bit(phase:))
  && spend.applies(tag:, spent:)
}

/// The effects that apply in phase `phase`, in the order of the list (`applies_in_phase`).
pub fn in_phase(
  effects effects: List(PlannedEffect(kind)),
  phase phase: Int,
  spent spent: Option(Int),
) -> List(PlannedEffect(kind)) {
  list.filter(effects, fn(planned) {
    applies_in_phase(
      phase_flags: planned.phase_flags,
      tag: planned.tag,
      phase:,
      spent:,
    )
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
