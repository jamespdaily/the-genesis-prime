//// A gap: something the client does that the server does not, or that the
//// client's code does not show. A module whose behaviour has one lists it in
//// `pub fn gaps() -> List(gap.Entry)`, and the coverage measure prints every
//// module's entries (`genesis_prime/coverage/gaps`), so a gap is stated once, in
//// plain words, beside the code a change closes it in.

/// One gap, in plain words.
pub type Entry {
  Entry(
    /// The part of the game the gap is in, such as "Quest acceptance".
    area: String,
    /// What the server does not do that the client does, or what the client's code does
    /// not show, as one sentence that names no issue and no row.
    missing: String,
  )
}
