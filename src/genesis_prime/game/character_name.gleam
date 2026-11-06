//// A character's full name as the game uses it. The client checks a name by its
//// text rule 0 before it sends a create or a rename request (CheckTextRule
//// 0x1403e1170, rule 0): letters and exactly one space, the space neither first
//// nor last, 5 to 30 characters in all, case free. A letter is A to Z, a to z or
//// one of the 53 Latin-1 and Latin Extended letters the client lists
//// (IsTextRuleLetter 0x1403e09d0, `listed_letters`). The client finally gives a
//// text that passed to Windows' IsTextUnicode, which finds no illegal character
//// in a text of letters and one space; the rule does not ask it.
////
//// The server holds the rule once, in the database: the `character` table's
//// `character_name_follows_rule_0` check (migration 0014) refuses a name that
//// breaks it, and the store answers the create or the rename with the client's
//// name-length result (genesis_prime/store). This module holds the letters the
//// check's pattern is written from, which a test reads against the table, and
//// the fold of a name.

import gleam/string

/// The Latin-1 and Latin Extended letters of the client's list, beyond A to Z
/// and a to z (IsTextRuleLetter 0x1403e09d0).
pub const listed_letters =
  "ÀÁÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÖÙÚÛÜÝßàáâäæçèéêëìíîïñòóôöùúûüýÿŒœŸ"

/// The name folded as the database's unique index folds it (migration 0005,
/// ICU's `lower`), which is how two names that differ only in case are one name.
/// A test compares it with the database's fold for every letter the rule takes.
pub fn fold(name name: String) -> String {
  string.lowercase(name)
}
