//// The kind of a currency type number, decoded once: the one place the server names the
//// numbers of the client's CurrencyType rows. A rule that sorts a price or a reward by its
//// currency matches on `Kind`, so a currency that gains a variant names every place that
//// must handle it.
////
//// ```text
//// currency type number -> kind_of -> Kind -> is_credits / names_a_currency
//// ```
////
//// - Currency 1 is the credits and 2 is Renown (`lua.Money.CodeEnumCurrencyType`); the
////   client's rows are 1 to 7 and 9 to 14, with no row 8 (`CurrencyType.capAmount`). The
////   server names only what a rule reads.
//// - A price slot of currency 0 is unused: with both buy slots 0 the client computes the
////   price (`0x14040bee0`), and with both SellToVendor slots 0 the sell price
////   (`0x14040bfb0`).
//// - A credits slot is scaled by the vendor's multiplier and any other slot is shown as
////   the row gives it (`0x14041bcc0.formula`).
//// - This module imports nothing, so any game module can name a kind.

/// The CurrencyType number of the credits (`lua.Money.CodeEnumCurrencyType`). The number 1
/// is written twice, here and as the `1 ->` pattern of `kind_of` (a pattern cannot name a
/// constant); a test pins that `kind_of(credits_type)` is `Credits`.
pub const credits_type = 1

/// What a rule reads a currency type number as.
pub type Kind {
  /// Number 0: no currency, an unused price slot (`0x14040bee0`).
  NoCurrency
  /// Number 1: the credits (`lua.Money.CodeEnumCurrencyType`).
  Credits
  /// Number 2: Renown (`lua.Money.CodeEnumCurrencyType`).
  Renown
  /// Any other number: a CurrencyType row of the client (3 to 7 and 9 to 14) or a number it
  /// has no row for; no rule of the server reads it.
  Other(number: Int)
}

/// The kind of a currency type number (`CurrencyType`, `lua.Money.CodeEnumCurrencyType`).
pub fn kind_of(number number: Int) -> Kind {
  case number {
    0 -> NoCurrency
    1 -> Credits
    2 -> Renown
    other -> Other(number: other)
  }
}

/// Whether the currency is the credits, the only slot a vendor's multiplier scales
/// (`0x14041bcc0.formula`).
pub fn is_credits(kind: Kind) -> Bool {
  case kind {
    Credits -> True
    NoCurrency | Renown | Other(_) -> False
  }
}

/// Whether the number names a currency: a price slot of 0 is unused (`0x14040bee0`,
/// `0x14040bfb0`).
pub fn names_a_currency(kind: Kind) -> Bool {
  case kind {
    NoCurrency -> False
    Credits | Renown | Other(_) -> True
  }
}
