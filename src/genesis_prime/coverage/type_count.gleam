//// Counting how many rows of the client's data use each type of one engine's
//// kind: the weight each type adds to the engine's work.

/// One type and the rows that use it.
pub type TypeCount {
  TypeCount(
    /// The type's number in the client's data.
    type_number: Int,
    /// How many values equal the type number.
    rows: Int,
    /// The part of all non-zero values that are this type, from 0.0 to 1.0.
    share: Float,
  )
}

/// The types in use, heaviest first.
pub type Count {
  Count(
    /// Each type with a row, most rows first, ties by the lower type number.
    types: List(TypeCount),
    /// The values that are not zero.
    rows: Int,
    /// The values that are zero. A zero names no type: it is a column with
    /// nothing in it, so it is left out of the types and the shares.
    zero_values: Int,
  )
}

/// Counts one value per row of the type column (a table with several type
/// columns gives every column's value of every row): each non-zero value is a
/// row of its type, and each zero is counted apart.
pub fn count(values: List(Int)) -> Count {
  todo as "counts the types"
}
