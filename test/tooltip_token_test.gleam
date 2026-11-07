//// The list of tooltip tokens (`test/fixture/tooltip_tokens/tokens.tsv`, written by
//// `client_files.py tokens --write`) as the coverage measure reads it. Expected values
//// come from these places.
//// - The list's own columns (`text_id`, `kind`, `id`, `field`): the rows planted below
////   are written as the generator writes them, a field in lower case and empty when the
////   token has none (`376222 spell 72652` with a trailing tab, from text 445006).
//// - The seven Spell4 columns a tooltip reads, in the generator's order
////   (`client_files.py` TEXT_COLUMNS): ActionBarTooltip, CasterIconSpellText,
////   PrimaryTargetIconSpellText, SecondaryTargetIconSpellText, TooltipCastInfo,
////   TooltipCostInfo and LASTier.
//// - `FormatSpellTooltipToken` (`0x1404df2c0`): the fields `abTooltip`, `cTooltip`,
////   `ptTooltip` and `stTooltip` of a `spell` token print the named spell's
////   ActionBarTooltip, CasterIconSpellText, PrimaryTargetIconSpellText and
////   SecondaryTargetIconSpellText text; no other field prints a text.
//// The Spell4 rows are planted (`test/spell_tables`); only their text columns differ.

import genesis_prime/table/spell4
import genesis_prime/tooltip_token.{Found, Token}
import gleam/list
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables

const header = "text_id\tkind\tid\tfield"

fn list_of(rows: List(String)) -> tooltip_token.Tokens {
  let assert Ok(tokens) =
    tooltip_token.parse(string.join([header, ..rows], "\n") <> "\n")
    as "the planted list parses"
  tokens
}

/// Telekinetic Strike 32893 and Pulse Blast 42276 with these text columns set.
fn rows_with_texts(
  strike strike: List(#(String, Int)),
  blast blast: List(#(String, Int)),
) -> spell_tables.Rows {
  let rows = spell_tables.rows()
  let set_all = fn(row, columns: List(#(String, Int))) {
    list.fold(columns, row, fn(row, column) {
      spell_tables.with_column(row:, name: column.0, cell: Integer(column.1))
    })
  }
  spell_tables.Rows(
    ..rows,
    spell4: list.map(rows.spell4, fn(row) {
      case row {
        [Integer(32_893), ..] -> set_all(row, strike)
        [Integer(42_276), ..] -> set_all(row, blast)
        other -> other
      }
    }),
  )
}

fn found_in(
  rows rows: spell_tables.Rows,
  tokens tokens: tooltip_token.Tokens,
  spell spell: Int,
) -> List(tooltip_token.Found) {
  spell_tables.with_loaded(rows:, body: fn(tables) {
    tooltip_token.of_spell(tables:, tokens:, spell:)
  })
}

pub fn a_spells_tokens_are_read_through_its_seven_text_columns_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows =
    rows_with_texts(
      strike: [
        #("localizedTextIdActionBarTooltip", 9001),
        #("localizedTextIdCasterIconSpellText", 9002),
        #("localizedTextIdPrimaryTargetIconSpellText", 9003),
        #("localizedTextIdSecondaryTargetIconSpellText", 9004),
        #("localizedTextIdTooltipCastInfo", 9005),
        #("localizedTextIdTooltipCostInfo", 9006),
        #("localizedTextIdLASTier", 9007),
      ],
      blast: [],
    )
  let tokens =
    list_of([
      "9001\teff\t1001\tinput0pct",
      "9002\teff\t1002\tinput0pct",
      "9003\tcc\t1003\tdurationms",
      "9004\teff\t1004\tdata02rawint",
      "9005\teff\t1005\tinput0pct",
      "9006\teff\t1006\tinput0pct",
      "9007\teff\t1007\tinput0pct",
      "9999\teff\t1999\tinput0pct",
    ])
  assert found_in(rows:, tokens:, spell: 32_893)
    == [
      Found(text_id: 9001, token: Token(tooltip_token.Eff, 1001, "input0pct")),
      Found(text_id: 9002, token: Token(tooltip_token.Eff, 1002, "input0pct")),
      Found(text_id: 9003, token: Token(tooltip_token.Cc, 1003, "durationms")),
      Found(
        text_id: 9004,
        token: Token(tooltip_token.Eff, 1004, "data02rawint"),
      ),
      Found(text_id: 9005, token: Token(tooltip_token.Eff, 1005, "input0pct")),
      Found(text_id: 9006, token: Token(tooltip_token.Eff, 1006, "input0pct")),
      Found(text_id: 9007, token: Token(tooltip_token.Eff, 1007, "input0pct")),
    ]
}

pub fn a_nested_tooltip_field_is_followed_to_the_named_spells_column_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows =
    rows_with_texts(
      strike: [#("localizedTextIdActionBarTooltip", 9101)],
      blast: [
        #("localizedTextIdActionBarTooltip", 9201),
        #("localizedTextIdCasterIconSpellText", 9202),
        #("localizedTextIdPrimaryTargetIconSpellText", 9203),
        #("localizedTextIdSecondaryTargetIconSpellText", 9204),
        #("localizedTextIdTooltipCastInfo", 9205),
      ],
    )
  let tokens =
    list_of([
      "9101\tspell\t42276\tabtooltip",
      "9101\tspell\t42276\tctooltip",
      "9101\tspell\t42276\tpttooltip",
      "9101\tspell\t42276\tsttooltip",
      "9101\tspell\t42276\taoetc",
      "9201\teff\t2001\tinput0pct",
      "9202\teff\t2002\tinput0pct",
      "9203\teff\t2003\tinput0pct",
      "9204\teff\t2004\tinput0pct",
      "9205\teff\t2005\tinput0pct",
    ])
  let found = found_in(rows:, tokens:, spell: 32_893)
  assert list.map(found, fn(one) { one.text_id })
    == [9101, 9101, 9101, 9101, 9101, 9201, 9202, 9203, 9204]
    as "each of the four fields reads the matching column of Pulse Blast; aoeTc and TooltipCastInfo are not followed"
  assert list.map(found, fn(one) { one.token.id })
    == [42_276, 42_276, 42_276, 42_276, 42_276, 2001, 2002, 2003, 2004]
}

pub fn a_nested_tooltip_that_names_a_spell_already_read_stops_there_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows =
    rows_with_texts(
      strike: [#("localizedTextIdActionBarTooltip", 9301)],
      blast: [#("localizedTextIdActionBarTooltip", 9302)],
    )
  let tokens =
    list_of([
      "9301\tspell\t42276\tabtooltip",
      "9302\tspell\t32893\tabtooltip",
      "9302\teff\t3002\tinput0pct",
    ])
  assert list.map(found_in(rows:, tokens:, spell: 32_893), fn(one) {
      #(one.text_id, one.token.id)
    })
    == [#(9301, 42_276), #(9302, 32_893), #(9302, 3002)]
    as "the cycle ends: each text is read once"
}

pub fn a_nested_tooltip_that_names_a_spell_the_table_lacks_adds_only_its_own_token_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows =
    rows_with_texts(
      strike: [#("localizedTextIdActionBarTooltip", 9401)],
      blast: [],
    )
  let tokens = list_of(["9401\tspell\t99999999\tabtooltip"])
  assert found_in(rows:, tokens:, spell: 32_893)
    == [
      Found(
        text_id: 9401,
        token: Token(tooltip_token.Spell, 99_999_999, "abtooltip"),
      ),
    ]
}

pub fn a_spell_with_no_text_has_no_tokens_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows = rows_with_texts(strike: [], blast: [])
  let assert Ok(row) =
    list.find(rows.spell4, fn(row) {
      case row {
        [Integer(32_893), ..] -> True
        _ -> False
      }
    })
  assert list.length(row) == list.length(spell4.schema.columns)
  assert found_in(rows:, tokens: list_of([]), spell: 32_893) == []
}

pub fn a_list_row_with_a_missing_column_fails_the_load_naming_the_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let row = "376222\teff\t95337"
  let assert Error(error) =
    tooltip_token.parse(
      header <> "\n376222\teff\t95337\tinput0pct\n" <> row <> "\n",
    )
  assert error
    == tooltip_token.RowInvalid(line: 3, row:, why: "has 3 columns, not 4")
  assert string.contains(tooltip_token.describe_error(error), "line 3")
  assert string.contains(
    tooltip_token.describe_error(error),
    string.replace(row, "\t", "\\t"),
  )
}

pub fn a_list_row_with_an_id_that_is_not_a_number_fails_the_load_naming_the_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let row = "376222\teff\t95x337\tinput0pct"
  let assert Error(error) = tooltip_token.parse(header <> "\n" <> row <> "\n")
  assert error
    == tooltip_token.RowInvalid(line: 2, row:, why: "id 95x337 is not a number")
  assert string.contains(
    tooltip_token.describe_error(error),
    string.replace(row, "\t", "\\t"),
  )
}

pub fn a_list_row_written_twice_fails_the_load_naming_the_row_and_its_first_line_test() -> Nil {
  use <- owned_test.run(10_000)
  let row = "376222\teff\t95337\tinput0pct"
  let assert Error(error) =
    tooltip_token.parse(
      header
      <> "\n"
      <> row
      <> "\n376222\teff\t95337\tinput1pct\n"
      <> row
      <> "\n",
    )
  assert error == tooltip_token.RowInvalid(line: 4, row:, why: "repeats line 2")
  assert string.contains(
    tooltip_token.describe_error(error),
    string.replace(row, "\t", "\\t"),
  )
}

pub fn a_list_row_a_text_shares_with_another_text_is_not_a_repeat_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(tokens) =
    tooltip_token.parse(
      header <> "\n1\teff\t5\tx\n2\teff\t5\tx\n1\teff\t5\ty\n",
    )
  assert tooltip_token.of_text(tokens:, text_id: 1)
    == [
      tooltip_token.Token(tooltip_token.Eff, 5, "x"),
      tooltip_token.Token(tooltip_token.Eff, 5, "y"),
    ]
  assert tooltip_token.of_text(tokens:, text_id: 2)
    == [tooltip_token.Token(tooltip_token.Eff, 5, "x")]
}

pub fn a_list_row_with_a_text_id_or_a_kind_the_client_does_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(10_000)
  let text_row = "abc\teff\t95337\tinput0pct"
  let assert Error(tooltip_token.RowInvalid(line: 2, row: text_found, ..)) =
    tooltip_token.parse(header <> "\n" <> text_row <> "\n")
  assert text_found == text_row
  let kind_row = "376222\twidget\t95337\tinput0pct"
  let assert Error(tooltip_token.RowInvalid(line: 2, row: kind_found, why:)) =
    tooltip_token.parse(header <> "\n" <> kind_row <> "\n")
  assert kind_found == kind_row
  assert string.contains(why, "widget")
}

pub fn a_list_with_another_header_fails_the_load_test() -> Nil {
  use <- owned_test.run(10_000)
  assert tooltip_token.parse("text\tkind\tid\tfield\n376222\teff\t1\tx\n")
    == Error(tooltip_token.HeaderWrong(found: "text\tkind\tid\tfield"))
}

pub fn a_token_without_a_field_reads_as_a_link_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let tokens = list_of(["445006\tspell\t72652\t"])
  assert tooltip_token.of_text(tokens:, text_id: 445_006)
    == [Token(tooltip_token.Spell, 72_652, "")]
  assert tooltip_token.of_text(tokens:, text_id: 1) == []
}
