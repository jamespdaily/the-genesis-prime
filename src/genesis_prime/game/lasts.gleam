//// How long a Spell4Effects row lasts, as `lasting.LastingRow` and `crowd_control.Row`
//// hold it.
////
//// - A row with flags bit 2 lasts until removed, whatever its durationTime
////   (`Spell4Effects.effectType.17`, `lasting.life_of`); the client's table has no row
////   with both (the table test `no_spell_effect_row_both_lasts_until_removed_and_names_a_duration_test`).

import gleam/bool

/// How long one row lasts: until its cast's effects end, or for its durationTime.
pub type Lasts {
  /// Flags bit 2: the row never times out.
  UntilRemoved
  /// No flags bit 2: the row lasts its durationTime, in milliseconds.
  For(duration_ms: Int)
}

/// The row's lasts from its flags bit 2 and durationTime: `UntilRemoved` when the bit is
/// set, else `For` the durationTime.
pub fn of_row(
  until_removed until_removed: Bool,
  duration_ms duration_ms: Int,
) -> Lasts {
  use <- bool.guard(when: until_removed, return: UntilRemoved)
  For(duration_ms:)
}

/// Whether the row lasts until removed.
pub fn is_until_removed(lasts lasts: Lasts) -> Bool {
  case lasts {
    UntilRemoved -> True
    For(..) -> False
  }
}
