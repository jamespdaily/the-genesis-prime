//// The comment rule. Expected values are the rule in the writing-gleam skill,
//// section Comments: a comment describes the code as it stands, so history
//// words, links to issues or pull requests, `#` numbers, dates and the name of
//// another codebase are refused. Every comment kind is planted once in a
//// made-up file; the deny list of other codebases is the rule's own list.

import code_rule/comment
import code_rule/planted
import code_rule/repository
import gleam/list
import owned_test

fn commented(comment: String) -> List(String) {
  [
    "//// A planted module.",
    "",
    "/// Reads the build.",
    "pub fn build() -> Int {",
    "  " <> comment,
    "  1",
    "}",
  ]
}

fn breach_lines(comment: String) -> List(Int) {
  planted.file("src/planted.gleam", commented(comment))
  |> comment.breaches
  |> planted.lines
}

pub fn a_comment_with_a_history_word_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let sentences = [
    #("now", "// The cache holds the value it is given, as it is now."),
    #("now", "// Now the cache holds the value it is given."),
    #("no longer", "// The old path is no longer read."),
    #("used to", "// This used to return a list."),
    #("not yet", "// Packets of this kind are not yet handled."),
    #("for now", "// The size is fixed, for now."),
    #("so far", "// This is the only case so far."),
  ]
  list.each(sentences, fn(sentence) {
    let #(word, text) = sentence
    assert breach_lines(text) == [5]
      as { "no breach for the history word: " <> word }
  })
}

pub fn a_doc_comment_and_a_module_comment_are_read_like_a_normal_comment_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted.gleam", [
      "//// This module no longer holds the cache.",
      "",
      "/// This function used to return a list.",
      "pub fn build() -> Int {",
      "  1",
      "}",
    ])
  assert planted.lines(comment.breaches(file)) == [1, 3]
}

pub fn a_comment_with_an_issue_number_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  assert breach_lines("// The layout is the one decided in #12.") == [5]
}

pub fn a_comment_with_an_issue_or_pull_request_link_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let issue = "// See https://github.com/jamespdaily/the-genesis-prime/issues/8"
  let pull = "// See https://github.com/jamespdaily/the-genesis-prime/pull/26"
  assert breach_lines(issue) == [5] as "no breach for an issue link"
  assert breach_lines(pull) == [5] as "no breach for a pull request link"
}

pub fn a_comment_with_a_date_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  assert breach_lines("// Measured on 2026-10-25 against the client.") == [5]
}

pub fn a_comment_naming_another_codebase_from_the_deny_list_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let comments = [
    "// Ported from NexusForever's handler.",
    "// The same layout as Nexus Forever.",
    "// The eldan server reads this differently.",
  ]
  list.each(comments, fn(text) {
    assert breach_lines(text) == [5] as { "no breach for: " <> text }
  })
}

pub fn a_clean_comment_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let comments = [
    "// Reads the build from the index header, as the opcode 0x037E is written.",
    "// A tuple written #(id, name) holds the pair, and 16_042 is the build.",
    "// Gleam 1.19.2 on OTP 29, documented at https://hexdocs.pm/gleam_stdlib/.",
    "// Nothing is known here, and the snow stays out of the cache.",
  ]
  list.each(comments, fn(text) {
    assert breach_lines(text) == []
      as { "a breach for the clean comment: " <> text }
  })
}

pub fn a_string_literal_holding_the_banned_words_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/planted.gleam", [
      "pub fn message() -> String {",
      "  \"no longer now, used to be #12 on 2026-10-25, not yet, for now, so far\"",
      "}",
      "",
      "pub fn others() -> List(String) {",
      "  [\"NexusForever\", \"Nexus Forever\", \"eldan\", \"https://github.com/a/b/issues/8\"]",
      "}",
    ])
  assert comment.breaches(file) == []
}

pub fn no_comment_in_src_or_test_breaks_the_rule_test() -> Nil {
  // Deadline: the body took 3382 to 3475 ms in three runs alone, so 15 s is
  // more than 4 times that. Lexing every file and checking every comment is
  // the cost.
  use <- owned_test.run(15_000)
  let files = repository.sources(["src", "test"])
  assert list.flat_map(files, comment.breaches) == []
}
