//// How a spell with an innate cost EMM id spends and chooses: the one place the
//// server names the EMM ids it reads and the one reader of an effect's emm
//// columns. Every rule that sorts a spell's effects by the points spent calls
//// `applies`, and the coverage measure counts an id as handled when `is_read` says
//// so, so the cost check, the plan, the strike and the measure cannot disagree.
////
//// ```
//// Spell4.innateCostEMMId0, 1 ─▶ spend_of ─▶ AllHeld | Unread      (the cost's payment)
//// Spell4Effects.emmComparison, emmValue ─▶ tag_of ─▶ Tag           (kept on each effect)
//// the cast's n ─▶ applies(tag, n) ─▶ whether the effect is chosen
//// ```
////
//// - **A spend of every point held.** A cost whose Spell4 EMM id is 4 or 7 takes
////   every whole point of its resource slot the caster holds, after the client's
////   check of the base cost alone (`Spell4.innateCostEMMId0`, `0x1403b3320`). The
////   client reads no EMM id, so the server owns the rule.
//// - **n** is the points spent above the base cost. An effect is chosen when its tag
////   holds for n: emmComparison 0 when n equals emmValue, 1 when n is at least
////   emmValue (`Spell4Effects.emmComparison`). A spell with no n, one with no EMM
////   id, chooses nothing: every effect applies, whatever its tag says.
//// - **Any other id** is an unread spend: the client does not say what 2, 5, 9, 10 or
////   11 mean, and the server pays and chooses nothing by them.

import gleam/option.{type Option, None, Some}

/// What the server reads an innate cost EMM id as (`Spell4.innateCostEMMId0`).
pub type Spend {
  /// 4 and 7: every whole point of the cost's resource slot is spent.
  AllHeld
  /// Any other id: no rule of the server reads it.
  Unread(emm_id: Int)
}

/// The spend of an EMM id, or `None` for 0, which is no EMM id: the cost is the
/// base cost alone.
pub fn spend_of(emm_id emm_id: Int) -> Option(Spend) {
  case emm_id {
    0 -> None
    4 | 7 -> Some(AllHeld)
    other -> Some(Unread(emm_id: other))
  }
}

/// Whether some rule reads the EMM id: the coverage measure's "handled".
pub fn is_read(emm_id emm_id: Int) -> Bool {
  case spend_of(emm_id:) {
    Some(AllHeld) -> True
    Some(Unread(..)) | None -> False
  }
}

/// The condition an effect holds on n, from its row's emmComparison and emmValue
/// (`Spell4Effects.emmComparison`).
pub type Tag {
  /// emmComparison 0: the effect applies when n equals the value.
  EqualTo(value: Int)
  /// emmComparison 1: the effect applies when n is at least the value.
  AtLeast(value: Int)
  /// Any other comparison, which the rows do not hold: it chooses nothing, and the
  /// load refuses it on a spell that has an n.
  OtherComparison(comparison: Int, value: Int)
}

/// The tag every n holds: emmComparison 1 with emmValue 0, n at least 0.
pub const always = AtLeast(value: 0)

/// The tag of a row's emmComparison and emmValue.
pub fn tag_of(comparison comparison: Int, value value: Int) -> Tag {
  case comparison {
    0 -> EqualTo(value:)
    1 -> AtLeast(value:)
    other -> OtherComparison(comparison: other, value:)
  }
}

/// Whether the tag is one the rule chooses by: emmComparison 0 or 1.
pub fn tag_is_read(tag tag: Tag) -> Bool {
  case tag {
    EqualTo(..) | AtLeast(..) -> True
    OtherComparison(..) -> False
  }
}

/// Whether an effect with this tag applies to a cast that spent `spent` points above
/// the base cost; every effect applies to a cast with no n.
pub fn applies(tag tag: Tag, spent spent: Option(Int)) -> Bool {
  case spent {
    None -> True
    Some(n) ->
      case tag {
        EqualTo(value:) -> n == value
        AtLeast(value:) -> n >= value
        OtherComparison(..) -> False
      }
  }
}
