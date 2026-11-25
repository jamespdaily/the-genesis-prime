//// What a rule makes of one value of a client column: it reads the value, it leaves a
//// question open that the fact file records, or no record explains it. A rule that
//// refuses a value refuses through this verdict, so the refusal can say which of the
//// three it was.
////
//// ```
//// column value ─▶ the column's classifier ─▶ ColumnVerdict ─▶ Reads: the rule plans it
////                                                          ├▶ Open(question): refused, the record holds the question
////                                                          └▶ Unexplained: refused, no record names the value
//// ```
////
//// - **A question is a record and a phrase of its gap.** The fact file's record holds the
////   question's words (its `gap`); the code quotes a phrase of them, so a test can check
////   the record is there and still says it.

/// A question the fact file records: the record's key, and a phrase the record's gap
/// must hold, empty when the record's whole gap is the question.
pub type Question {
  Question(fact: String, marker: String)
}

/// The verdict on one value of a client column.
pub type ColumnVerdict {
  /// The rule reads the value, as the client's code or the record settles it, or as a
  /// named guess plays it.
  Reads
  /// The value is one the record leaves open: the server refuses it and the question is
  /// the record's.
  Open(question: Question)
  /// No record or rule names the value: the server refuses it, and a test over the
  /// client's tables fails when a row holds one.
  Unexplained
}
