//// A character's full name by the client's text rule 0, the rule the client
//// checks a name by before it sends a create or a rename request
//// (CheckTextRule 0x1403e1170, rule 0): letters and exactly one space, the
//// space neither first nor last, 5 to 30 characters in all, case free. A
//// letter is A to Z, a to z or one of the 53 Latin-1 and Latin Extended letters
//// the client lists. The client finally gives a text that passed to Windows'
//// IsTextUnicode, which finds no illegal character in a text of letters and
//// one space; this rule does not ask it.

import gleam/list
import gleam/string

/// The fewest and most characters of a full name (rule 0: least 5, bound 31).
const shortest = 5

const longest = 30

/// The Latin-1 and Latin Extended letters of the client's list, beyond A to Z
/// and a to z (IsTextRuleLetter 0x1403e09d0).
const listed_letters = "ÀÁÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÖÙÚÛÜÝßàáâäæçèéêëìíîïñòóôöùúûüýÿŒœŸ"

/// Whether the text is a character's full name by rule 0.
pub fn is_valid(name: String) -> Bool {
  let characters = string.to_utf_codepoints(name)
  let count = list.length(characters)
  let spaces = list.count(characters, is_space)
  let edge_is_space = case characters, list.last(characters) {
    [first, ..], Ok(last) -> is_space(first) || is_space(last)
    [], _ | _, Error(Nil) -> False
  }
  count >= shortest
  && count <= longest
  && spaces == 1
  && !edge_is_space
  && list.all(characters, fn(character) {
    is_space(character) || is_letter(character)
  })
}

fn is_space(character: UtfCodepoint) -> Bool {
  string.utf_codepoint_to_int(character) == 0x20
}

fn is_letter(character: UtfCodepoint) -> Bool {
  let number = string.utf_codepoint_to_int(character)
  { number >= 0x41 && number <= 0x5A }
  || { number >= 0x61 && number <= 0x7A }
  || list.contains(string.to_utf_codepoints(listed_letters), character)
}
