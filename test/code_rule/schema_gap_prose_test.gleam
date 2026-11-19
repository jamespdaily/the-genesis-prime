//// The schema-gap-prose rule: a text of the message schema that says what the client does
//// never states a gap, since a gap is a `gaps` entry the generator turns into the module's
//// `gaps()` (CLAUDE.md: a gap is stated where the coverage measure prints it). Each case is
//// planted in a made-up schema file; the last test reads the real one.

import code_rule/planted
import code_rule/schema_gap_prose
import code_rule/source.{Breach, SourceFile}
import gleam/list
import owned_test
import simplifile
import unitest

const rule = "a schema text that states a gap in prose"

pub fn no_message_summary_states_a_gap_in_prose_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let path = "src/planted/schema.toml"
  let cases = [
    #(
      "a summary that says Gap: is a breach at its line",
      ["[[message]]", "summary = \"what the client does. Gap: a width\""],
      [2],
    ),
    #(
      "a summary that says gaps, in capitals, is a breach",
      ["[[record]]", "summary = \"the fields, and GAPS in them\""],
      [2],
    ),
    #(
      "an open question inside a field's inline table is a breach",
      [
        "[[message]]",
        "fields = [",
        "  { name = \"field_1\", kind = \"unsigned\", bits = 8, open = \"what is it? its gap leaves it unread\" },",
        "]",
      ],
      [3],
    ),
    #(
      "an open tag's question is a breach",
      [
        "[[union]]",
        "open_tags = [",
        "  { tag = 5, question = \"a gap in the kind\" },",
        "]",
      ],
      [3],
    ),
    #(
      "the gaps key and an entry's own sentence are not prose",
      [
        "[[message]]",
        "summary = \"what the client does\"",
        "gaps = [",
        "  { area = \"Quest log\", missing = \"the gap in the width\" },",
        "]",
      ],
      [],
    ),
    #(
      "a word that only holds the letters is no breach",
      ["summary = \"a gapless codec and a gaping read\""],
      [],
    ),
    #(
      "a summary with no gap is no breach",
      ["summary = \"the quest log at login\""],
      [],
    ),
  ]
  list.each(cases, fn(case_) {
    let #(name, lines, expected) = case_
    let breaches = schema_gap_prose.breaches(file: planted.file(path, lines))
    assert planted.lines(breaches) == expected as name
    assert list.all(breaches, fn(breach) {
      breach == Breach(path:, line: breach.line, rule:)
    })
      as { name <> ": each breach names the file and the rule" }
  })
  let real_path = "src/genesis_prime/message/schema.toml"
  let assert Ok(text) = simplifile.read(real_path) as "the schema file reads"
  assert schema_gap_prose.breaches(file: SourceFile(path: real_path, text:))
    == []
    as "no summary, open question or tag question of the real schema holds the word gap"
}
