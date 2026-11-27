//// The kind of a Spell4Base castBarType number, decoded once: the one place the server
//// names what the client reads of that column. The cast bar rule of the spell plan matches
//// on `Kind`, so a cast bar type the client comes to read apart names every place that
//// must handle it.
////
//// ```text
//// Spell4Base.castBarType -> kind_of -> Kind -> spell_plan's cast bar rule
//// ```
////
//// - The client keeps the column as stored in its spell record word 0x2c and tests it only
////   as zero or not: `SpellShowsCastBar` (`0x1407a1820`), `IsUnitCastBarShown`
////   (`0x140469530`) and `ApplySpellGo` (`0x14053e5a0`) (`Spell4Base.castBarType`).
//// - This module imports nothing, so any game module can name a kind.

/// What a rule reads a castBarType number as.
pub type Kind {
  /// Number 0: the spell has no cast bar (`0x1407a1820`).
  NoBar
  /// Any other number: the spell has a cast bar; the client tests only for non-zero, so
  /// the number is kept as stored (`Spell4Base.castBarType`).
  Bar(number: Int)
}

/// The kind of a castBarType number (`Spell4Base.castBarType`).
pub fn kind_of(number number: Int) -> Kind {
  case number {
    0 -> NoBar
    other -> Bar(number: other)
  }
}
