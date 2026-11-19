//// The issue-citation rule: no line of `src` or `dev` names an issue, and no
//// comment there says gap. Expected values are the rule's own statement: a `#`
//// with two digits or more, or the whole word issue, is a citation; the
//// client's "Auto-Attack #1", hex and tuples are not. Each case is planted once
//// in a made-up file; the last test runs both rules over the tree.

import code_rule/issue_citation
import code_rule/planted
import code_rule/repository
import gleam/list
import owned_test
import unitest

pub fn a_line_naming_an_issue_by_number_or_word_is_a_breach_naming_file_and_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/planted.gleam", [
      "//// A planted module.",
      "",
      "// Handled by #55.",
      "// Waits on issue 66 to land.",
      "// This is an open issue.",
      "// The issue \"A title\" covers it.",
      "const gap_issue = 7",
      "const text = \"not yet (#1054)\"",
      "const fine = 1",
    ])
  assert planted.lines(issue_citation.breaches(file)) == [3, 4, 5, 6, 7, 8]
    as "each marker line is a breach, a string literal too, and a line with none is not"
  assert list.all(issue_citation.breaches(file), fn(breach) {
    breach.path == "src/genesis_prime/planted.gleam"
  })
    as "a breach names its file"
}

pub fn the_word_issue_is_matched_as_a_whole_word_at_its_boundaries_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let cases = [
    #("// The issues remain.", True, "a plural is the word"),
    #("// An ISSUE remains.", True, "any case is the word"),
    #("const a_issue = 1", True, "an underscore is a separator"),
    #("const x = \"issue-name\"", True, "a hyphen is a separator"),
    #("// Then issue2 came.", True, "a digit is a separator"),
    #("// Then 2issue came.", True, "a digit is a separator"),
    #("// The cheque was issued.", False, "issued is another word"),
    #("// A tissue.", False, "a letter before the word makes another word"),
    #("// Issued once.", False, "issued in any case is another word"),
    #("// The client's \"Auto-Attack #1\" and \"#2\".", False, "one digit"),
    #("const address = 0x14049f990", False, "hex has no hash"),
    #("let pair = #(a, b)", False, "a hash before a bracket is a tuple"),
    #("const text = \"#12\"", True, "a hash with two digits"),
  ]
  list.each(cases, fn(row) {
    let #(line, is_breach, reason) = row
    let file = planted.file("src/genesis_prime/planted.gleam", [line])
    let expected = case is_breach {
      True -> [1]
      False -> []
    }
    assert planted.lines(issue_citation.breaches(file)) == expected as reason
  })
}

pub fn a_comment_that_says_gap_is_a_breach_and_an_identifier_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/planted.gleam", [
      "//// A planted module.",
      "",
      "// Gap: the client sends more.",
      "/// This is a gap in the table.",
      "// Gaps, each with a reason.",
      "const edge_gap = 3",
      "const text = \"a gap in a string\"",
      "// The `quest.Gap` type and `edge_gap` are named in backticks.",
      "// The gapped edge is another word.",
    ])
  assert planted.lines(issue_citation.breaches(file)) == [3, 4, 5]
    as "a comment line with the word is a breach; an identifier, a string, a backticked name and a longer word are not"
}

pub fn no_line_in_src_or_dev_names_an_issue_and_no_comment_says_gap_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("code_rule")
  assert list.flat_map(repository.sources(under: ["src", "dev"]), fn(file) {
      issue_citation.breaches(file)
    })
    == []
}
