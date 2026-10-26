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

import gleam/list
import gleam/string

/// The fewest characters a name has (InitTextRules 0x1403E0B60: rule 0's least
/// length, 5, stored at 0x1403e0dc1).
const least_characters = 5

/// The most characters a name has: rule 0's bound is 31 (0x1403e0dcc), and the
/// text must end before it.
const most_characters = 30

/// The Latin-1 and Latin Extended letters the client lists besides A to Z and
/// a to z (IsTextRuleLetter 0x1403E09D0, 53 of them).
const listed_letters = "ÀÁÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÖÙÚÛÜÝßàáâäæçèéêëìíîïñòóôöùúûüýÿŒœŸ"

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
  let characters = string.to_graphemes(name)
  case characters {
    [] -> Error(Empty)
    [first, ..] -> {
      case list.find(characters, fn(character) { !allowed(character) }) {
        Ok(other) -> Error(NotALetter(character: other))
        Error(Nil) -> check_spaces(characters:, first:)
      }
    }
  }
}

/// A letter or the space.
fn allowed(character: String) -> Bool {
  character == " " || is_letter(character)
}

fn is_letter(character: String) -> Bool {
  case string.to_utf_codepoints(character) {
    [codepoint] -> {
      let number = string.utf_codepoint_to_int(codepoint)
      { number >= 0x41 && number <= 0x5A }
      || { number >= 0x61 && number <= 0x7A }
      || string.contains(listed_letters, character)
    }
    _ -> False
  }
}

fn check_spaces(
  characters characters: List(String),
  first first: String,
) -> Result(Nil, NameError) {
  let count = list.length(characters)
  let spaces = list.count(characters, fn(character) { character == " " })
  let last = list.last(characters)
  case first == " " || last == Ok(" "), spaces {
    True, _ -> Error(SpaceAtAnEnd)
    False, 1 -> check_length(count)
    False, _ -> Error(SpacesNotOne(spaces:))
  }
}

fn check_length(count: Int) -> Result(Nil, NameError) {
  case count < least_characters, count > most_characters {
    True, _ -> Error(TooShort(characters: count))
    False, True -> Error(TooLong(characters: count))
    False, False -> Ok(Nil)
  }
}
