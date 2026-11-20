//// The required-value rule. Expected values are the rule's own statement: the
//// expansions `${name:?word}` and `${name?word}` are breaches (bash 3.2 ends
//// a script with an EXIT trap with status 0 on them), every other expansion
//// and every comment line is not. Each case is planted once in a made-up
//// file; the last test runs the rule over the play service's scripts.

import code_rule/planted
import code_rule/repository
import code_rule/required_value
import gleam/list
import owned_test
import unitest

pub fn a_required_value_expansion_in_a_code_line_is_a_breach_and_other_lines_are_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let cases = [
    #(": \"${remote:?config.sh sets no remote}\"", True, "the colon form"),
    #("x=${remote?unset}", True, "the form without a colon"),
    #("echo \"${a:-b}\" \"${c:?d}\"", True, "a later expansion on the line"),
    #("echo ${!name:?unset}", True, "an indirect name"),
    #("echo \"${HOME_2:?}\"", True, "digits and underscores are in a name"),
    #(
      "echo \"${x:-y}\" \"${x:+y}\" \"${x}\" \"${#x}\"",
      False,
      "the other forms",
    ),
    #("[ -n \"${!1:-}\" ] || refuse \"$2\"", False, "an indirect default"),
    #("echo '$x:?y' \"${x}:?y\"", False, "a ? outside the braces"),
    #("# a `${x:?word}` is named in a comment", False, "a comment line"),
    #("  # ${x:?word}", False, "an indented comment line"),
  ]
  list.each(cases, fn(row) {
    let #(line, is_breach, reason) = row
    let file = planted.file("dev/play_service/planted.sh", [line])
    let expected = case is_breach {
      True -> [1]
      False -> []
    }
    assert planted.lines(required_value.breaches(file)) == expected as reason
  })
}

pub fn a_breach_names_its_file_and_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("dev/play_service/planted.sh", [
      "set -eu", "", ": \"${x:?unset}\"",
    ])
  assert planted.lines(required_value.breaches(file)) == [3]
    as "the line of the expansion"
  assert list.all(required_value.breaches(file), fn(breach) {
    breach.path == "dev/play_service/planted.sh"
  })
    as "the breach names its file"
}

pub fn no_play_script_requires_a_value_with_a_question_mark_expansion_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("code_rule")
  assert list.flat_map(
      repository.shell_sources(under: ["dev/play_service"]),
      fn(file) { required_value.breaches(file) },
    )
    == []
}
