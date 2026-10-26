//// The client's rule for a character's name (text rule 0 of CheckTextRule
//// 0x1403E1170: flags 0x506, least length 5, bound 31): letters and exactly
//// one space, the space neither first nor last, 5 to 30 characters in all,
//// case free. The letters are A to Z, a to z and the 53 Latin-1 and Latin
//// Extended letters the client lists (IsTextRuleLetter 0x1403E09D0). The
//// client checks a name before it sends it; the server checks the same rule,
//// because a client that does not is not the client.
////
//// The client's last step hands a passing text to Windows' IsTextUnicode for
//// illegal characters, with 0x100 (IS_TEXT_UNICODE_ILLEGAL_CHARS). A text that
//// passes the rest holds only letters and one space, none of which is an
//// illegal character, so that step cannot refuse it.

/// Why a name breaks the rule.
pub type NameError {
  /// The name is empty.
  Empty
  /// The name has fewer than 5 characters.
  TooShort(characters: Int)
  /// The name has more than 30 characters.
  TooLong(characters: Int)
  /// A character that is neither a letter nor a space.
  NotALetter(character: String)
  /// The first or the last character is a space.
  SpaceAtAnEnd
  /// The name does not hold exactly one space.
  SpacesNotOne(spaces: Int)
}

/// Checks a name against the rule.
pub fn check(name name: String) -> Result(Nil, NameError) {
  todo as "checks a name against the client's rule"
}
