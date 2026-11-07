//// The tooltip tokens of the client's texts, as the coverage measure reads them.
////
//// ```
//// test/fixture/tooltip_tokens/tokens.tsv ─▶ parse ─▶ Tokens (by text id)
//// Spell4 row ─▶ its seven text columns ─▶ their tokens, a nested
////   `spell=N.abTooltip` (and cTooltip, ptTooltip, stTooltip) followed to N's column
//// ```
////
//// - **The list** holds one row for each token of each text a Spell4 tooltip column
////   names: text id, kind, id and field in lower case, the field empty when the token has
////   none. `.claude/skills/decoding-the-client/scripts/client_files.py tokens --write`
////   writes it from the client's language file as the client's token reader scans it
////   (`FormatTextTokens` `0x1400c12b0`), and the full check compares it with a fresh
////   write where the client is present. It holds no English text.
//// - **The seven columns** a tooltip reads are the localized text ids of Spell4's
////   ActionBarTooltip, CasterIconSpellText, PrimaryTargetIconSpellText,
////   SecondaryTargetIconSpellText, TooltipCastInfo, TooltipCostInfo and LASTier.
//// - **A nested tooltip**: the fields `abTooltip`, `cTooltip`, `ptTooltip` and
////   `stTooltip` of a `spell` token print the named spell's ActionBarTooltip,
////   CasterIconSpellText, PrimaryTargetIconSpellText and SecondaryTargetIconSpellText
////   text (`FormatSpellTooltipToken`, `0x1404df2c0`, reads the spell object's block
////   words 0x20 to 0x2c, which `BuildSpellTables`, `0x14055e180`, fills lines 1347-1350
////   from the Spell4 row's offsets 124, 248, 252 and 256: fact record
////   `Spell4.localizedTextIdActionBarTooltip`); a text is read once.
//// - **A row the load refuses** names its line: the list is written by a tool, so a
////   row the reader cannot take, or a row written twice (the tool writes each token of
////   a text once), is a stale or damaged file, never skipped.

import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4.{type Spell4}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import simplifile

/// Where the committed list is, from the project folder.
const list_path = "test/fixture/tooltip_tokens/tokens.tsv"

const header = "text_id\tkind\tid\tfield"

/// The kinds the client's token reader tries (`ReadKindToken`, `0x1400b8010`).
pub type Kind {
  Eff
  Spell
  Cc
  Smod
  Emod
  Thrsh
  Gf
  Creature
  Item
  Schematic
  Vitem
  Achievement
  Keybinding
  Bindpoint
}

/// A token: its kind, the id after the `=` and the field after the first `.`, in lower
/// case, empty when there is none.
pub type Token {
  Token(kind: Kind, id: Int, field: String)
}

/// A token and the text it is in.
pub type Found {
  Found(text_id: Int, token: Token)
}

/// The tokens of each text, in the order of the text.
pub opaque type Tokens {
  Tokens(by_text: Dict(Int, List(Token)))
}

/// Why the list is not taken.
pub type ListError {
  Unreadable(path: String, reason: String)
  HeaderWrong(found: String)
  RowInvalid(line: Int, row: String, why: String)
}

/// The committed list.
pub fn load() -> Result(Tokens, ListError) {
  use text <- result.try(
    simplifile.read(list_path)
    |> result.map_error(fn(reason) {
      Unreadable(path: list_path, reason: simplifile.describe_error(reason))
    }),
  )
  parse(text:)
}

/// A list from its text: the header, then one row for each token.
pub fn parse(text text: String) -> Result(Tokens, ListError) {
  case string.split(text, "\n") {
    [first, ..rows] if first == header -> {
      let rows = case list.reverse(rows) {
        ["", ..rest] -> list.reverse(rest)
        _ -> rows
      }
      rows
      |> list.index_map(fn(row, index) { #(index + 2, row) })
      |> list.try_fold(#(dict.new(), dict.new()), add_row)
      |> result.map(fn(state) {
        let by_text = state.0
        Tokens(
          by_text: dict.map_values(by_text, fn(_, found) { list.reverse(found) }),
        )
      })
    }
    [first, ..] -> Error(HeaderWrong(found: first))
    [] -> Error(HeaderWrong(found: ""))
  }
}

/// The state with one more row: the tokens by text, and the line each row first stood on.
fn add_row(
  state: #(Dict(Int, List(Token)), Dict(String, Int)),
  numbered: #(Int, String),
) -> Result(#(Dict(Int, List(Token)), Dict(String, Int)), ListError) {
  let #(by_text, first_lines) = state
  let #(line, row) = numbered
  case dict.get(first_lines, row) {
    Ok(first) ->
      Error(RowInvalid(
        line:,
        row:,
        why: "repeats line " <> int.to_string(first),
      ))
    Error(Nil) -> {
      use #(text_id, token) <- result.map(parse_row(line:, row:))
      #(
        dict.upsert(by_text, text_id, fn(found) {
          [token, ..option.unwrap(found, [])]
        }),
        dict.insert(first_lines, row, line),
      )
    }
  }
}

fn parse_row(
  line line: Int,
  row row: String,
) -> Result(#(Int, Token), ListError) {
  let invalid = fn(why) { RowInvalid(line:, row:, why:) }
  case string.split(row, "\t") {
    [text_id, kind, id, field] -> {
      use text_id <- result.try(
        int.parse(text_id)
        |> result.replace_error(invalid(
          "text id " <> text_id <> " is not a number",
        )),
      )
      use kind <- result.try(
        kind_of(kind)
        |> result.replace_error(invalid(
          "kind " <> kind <> " is not one the client's reader tries",
        )),
      )
      use id <- result.try(
        int.parse(id)
        |> result.replace_error(invalid("id " <> id <> " is not a number")),
      )
      case id >= 1 {
        True -> Ok(#(text_id, Token(kind:, id:, field:)))
        False ->
          Error(invalid(
            "id "
            <> int.to_string(id)
            <> " is 0 or less, which the client's evaluators refuse",
          ))
      }
    }
    columns ->
      Error(invalid(
        "has " <> int.to_string(list.length(columns)) <> " columns, not 4",
      ))
  }
}

fn kind_of(name: String) -> Result(Kind, Nil) {
  case name {
    "eff" -> Ok(Eff)
    "spell" -> Ok(Spell)
    "cc" -> Ok(Cc)
    "smod" -> Ok(Smod)
    "emod" -> Ok(Emod)
    "thrsh" -> Ok(Thrsh)
    "gf" -> Ok(Gf)
    "creature" -> Ok(Creature)
    "item" -> Ok(Item)
    "schematic" -> Ok(Schematic)
    "vitem" -> Ok(Vitem)
    "achievement" -> Ok(Achievement)
    "keybinding" -> Ok(Keybinding)
    "bindpoint" -> Ok(Bindpoint)
    _ -> Error(Nil)
  }
}

/// A sentence for a list the load refuses.
pub fn describe_error(error: ListError) -> String {
  case error {
    Unreadable(path:, reason:) ->
      "the tooltip token list " <> path <> " cannot be read: " <> reason
    HeaderWrong(found:) ->
      "the tooltip token list does not start with its header ("
      <> string.replace(header, "\t", " ")
      <> "), it starts with "
      <> quoted(found)
    RowInvalid(line:, row:, why:) ->
      "the tooltip token list, line "
      <> int.to_string(line)
      <> " ("
      <> quoted(row)
      <> "): "
      <> why
  }
}

/// A row or a header between quotes, its tabs written `\t`.
fn quoted(text: String) -> String {
  "\"" <> string.replace(text, "\t", "\\t") <> "\""
}

/// The tokens of one text, in the order of the text; none for a text the list lacks.
pub fn of_text(tokens tokens: Tokens, text_id text_id: Int) -> List(Token) {
  dict.get(tokens.by_text, text_id) |> result.unwrap([])
}

/// A token as the text writes it: `eff=196652.input0pct`.
pub fn describe(token: Token) -> String {
  kind_name(token.kind)
  <> "="
  <> int.to_string(token.id)
  <> case token.field {
    "" -> ""
    field -> "." <> field
  }
}

fn kind_name(kind: Kind) -> String {
  case kind {
    Eff -> "eff"
    Spell -> "spell"
    Cc -> "cc"
    Smod -> "smod"
    Emod -> "emod"
    Thrsh -> "thrsh"
    Gf -> "gf"
    Creature -> "creature"
    Item -> "item"
    Schematic -> "schematic"
    Vitem -> "vitem"
    Achievement -> "achievement"
    Keybinding -> "keybinding"
    Bindpoint -> "bindpoint"
  }
}

/// The tokens a spell's tooltips hold, with the text of each: its seven text columns in
/// order, and after the tokens of a text the texts its nested tooltips name. Empty for a
/// spell the table lacks.
pub fn of_spell(
  tables tables: store.Tables,
  tokens tokens: Tokens,
  spell spell: Int,
) -> List(Found) {
  let #(_, found) =
    list.fold(columns_of(tables:, spell:), #(set.new(), []), fn(state, text_id) {
      read_text(tables:, tokens:, text_id:, state:)
    })
  list.reverse(found)
}

/// The text ids of a spell's seven columns, in order, none for a column holding 0.
fn columns_of(tables tables: store.Tables, spell spell: Int) -> List(Int) {
  case spell4.get(tables:, id: Spell4Id(spell)) {
    Ok(row) ->
      list.filter(
        [
          row.localized_text_id_action_bar_tooltip,
          row.localized_text_id_caster_icon_spell_text,
          row.localized_text_id_primary_target_icon_spell_text,
          row.localized_text_id_secondary_target_icon_spell_text,
          row.localized_text_id_tooltip_cast_info,
          row.localized_text_id_tooltip_cost_info,
          row.localized_text_id_las_tier,
        ],
        fn(text_id) { text_id != 0 },
      )
    Error(Nil) -> []
  }
}

/// The found tokens (latest first) and the texts read, with this text read unless it
/// was, and the texts its nested tooltips name read after it.
fn read_text(
  tables tables: store.Tables,
  tokens tokens: Tokens,
  text_id text_id: Int,
  state state: #(Set(Int), List(Found)),
) -> #(Set(Int), List(Found)) {
  use <- bool.guard(set.contains(state.0, text_id), state)
  let own = of_text(tokens:, text_id:)
  let state = #(
    set.insert(state.0, text_id),
    list.fold(own, state.1, fn(found, token) {
      [Found(text_id:, token:), ..found]
    }),
  )
  list.fold(own, state, fn(state, token) {
    case nested_column(tables:, token:) {
      Some(next) -> read_text(tables:, tokens:, text_id: next, state:)
      None -> state
    }
  })
}

/// The text id a `spell=N.abtooltip` (or ctooltip, pttooltip, sttooltip) token prints,
/// when the spell has a row and the column holds a text.
fn nested_column(
  tables tables: store.Tables,
  token token: Token,
) -> Option(Int) {
  case token.kind {
    Spell ->
      case spell4.get(tables:, id: Spell4Id(token.id)) {
        Ok(row) ->
          case nested_text_id(row:, field: token.field) {
            Some(0) -> None
            other -> other
          }
        Error(Nil) -> None
      }
    Eff
    | Cc
    | Smod
    | Emod
    | Thrsh
    | Gf
    | Creature
    | Item
    | Schematic
    | Vitem
    | Achievement
    | Keybinding
    | Bindpoint -> None
  }
}

/// The Spell4 column the client's spell object keeps for each nested tooltip field (the
/// block words 0x20 abTooltip, 0x24 cTooltip, 0x28 ptTooltip, 0x2c stTooltip are copied
/// from the row's offsets 124, 248, 252 and 256, 0x14055e180 lines 1347-1350).
fn nested_text_id(row row: Spell4, field field: String) -> Option(Int) {
  case field {
    "abtooltip" -> Some(row.localized_text_id_action_bar_tooltip)
    "ctooltip" -> Some(row.localized_text_id_caster_icon_spell_text)
    "pttooltip" -> Some(row.localized_text_id_primary_target_icon_spell_text)
    "sttooltip" -> Some(row.localized_text_id_secondary_target_icon_spell_text)
    _ -> None
  }
}
