//// The digest of a rule's types: every custom type its `step` and `new`
//// functions take or return, and every type those reach through their
//// constructors' fields, across the project's modules, read from the source
//// with glance. A recording's header holds the digest it was made under; a
//// replay compares it with the digest as the code stands, so a recording from
//// other types fails with "record again" and never folds into a wrong value.
//// A change to a function body leaves the digest as it is.

/// Why the digest could not be made.
pub type DigestError {
  /// The rule's module has no `pub fn step` or no `pub fn new`.
  NotARule(module: String)
  /// A module the types reach could not be read or parsed.
  Unreadable(module: String, reason: String)
}

/// The digest of the rule module's types, read from `source_root` (the
/// project's `src` folder): the SHA-256 of a canonical print of each type
/// reached, in a fixed order, as lower-case hexadecimal.
pub fn digest(
  rule_module rule_module: String,
  source_root source_root: String,
) -> Result(String, DigestError) {
  todo as "the build follows the shape commit"
}
