//// An entry states something the client does that the server does not, or that the
//// client's code does not show. A module whose behaviour has one lists it in
//// `pub fn gaps() -> List(gap.Entry)`, and the coverage measure prints every
//// module's entries (`genesis_prime/coverage/gaps`), so it is stated once, in
//// plain words, beside the code a change closes it in.

/// One thing the server leaves undone, in plain words.
pub type Entry {
  Entry(
    /// The part of the game the entry is in, such as "Quest acceptance".
    area: String,
    /// What the server does not do that the client does, or what the client's code does
    /// not show, as one plain sentence with no row's id in it.
    missing: String,
  )
}
