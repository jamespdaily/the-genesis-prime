//// The spells a tooltip names that no row reaches: what the tooltips of the reached
//// spells promise and the walk of the trees does not hold, so the coverage measure can
//// show what a tooltip states and no effect row of a tree gives.
////
//// ```
//// reached spells ─▶ their tooltips' tokens (genesis_prime/tooltip_token `of_spell`)
////   ─▶ value tokens  eff=E.f / cc=E.f ─▶ Spell4Effects E ─▶ its spell
////                    spell=N.f        ─▶ Spell4 N
////   ─▶ the spells no tree reaches (the server's Proxies planted), with who names them
//// ```
////
//// - **A value token** reads a value of the spell it names: `eff` and `cc` the row of
////   Spell4Effects, whose spell is the one named, and `spell` with a field the spell's
////   own column (`FormatSpellTooltipToken`, `0x1404df2c0`). A spell with such a token
////   that no tree reaches is **counted**: the tooltip states a value the server does not
////   produce. A nested tooltip (`spell=N.abTooltip`) reads N's text, so the tokens in it
////   count as named by the spell that nests it.
//// - **A link** is a `spell` token with no field: it prints the spell's name and reads no
////   value. The links are listed apart and add nothing to the count; a spell that value
////   tokens also name is in both lists.
//// - **A token that names no row** (an effect or a spell the tables lack) is listed apart:
////   the client prints nothing for it.
//// - **A reason** is the first part the starting abilities' measure leaves out that holds
////   the spell (`starting_ability.left_out_spells`), as it explains why no row reaches it.

import genesis_prime/coverage/starting_ability.{type LeftOut}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import genesis_prime/tooltip_token.{type Found, type Token, type Tokens}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// A token, the text it is in and the reached spells whose tooltips hold that text.
pub type Naming {
  Naming(token: Token, text_id: Int, named_by: List(Int))
}

/// A spell the tooltips name that no tree reaches, with its namings, by text id and
/// token, and the part left out that explains it, when one does.
pub type Entry {
  Entry(spell: Int, namings: List(Naming), reason: Option(LeftOut))
}

/// A token that names a row the tables lack.
pub type NoRow {
  NoRow(table: String, id: Int, token: Token, text_id: Int, named_by: List(Int))
}

/// The spells counted, the spells links name, and the tokens that name no row, each by id.
pub type Named {
  Named(counted: List(Entry), links: List(Entry), no_row: List(NoRow))
}

/// What a token of a reached spell names.
type Target {
  Value(spell: Int)
  Link(spell: Int)
  Missing(table: String, id: Int)
}

/// What the tokens of the reached spells' tooltips name that none of those spells is.
pub fn find(
  tables tables: store.Tables,
  tokens tokens: Tokens,
  reached reached: List(Int),
  left_out left_out: List(LeftOut),
) -> Named {
  let reached_set = set.from_list(reached)
  let namings =
    list.unique(reached)
    |> list.flat_map(fn(spell) {
      tooltip_token.of_spell(tables:, tokens:, spell:)
      |> list.filter_map(fn(found) {
        target(tables:, token: found.token)
        |> result.map(fn(target) { #(target, found, spell) })
      })
    })
  Named(
    counted: entries(namings:, reached_set:, left_out:, links: False),
    links: entries(namings:, reached_set:, left_out:, links: True),
    no_row: no_rows(namings:),
  )
}

/// What a token names, or an error for a token that names no spell: a kind other than
/// `eff`, `cc` and `spell`, or an `eff` or `cc` with no field, which the generator never
/// writes.
fn target(
  tables tables: store.Tables,
  token token: Token,
) -> Result(Target, Nil) {
  case token.kind, token.field {
    tooltip_token.Eff, "" | tooltip_token.Cc, "" -> Error(Nil)
    tooltip_token.Eff, _ | tooltip_token.Cc, _ ->
      case spell4_effects.get(tables:, id: Spell4EffectsId(token.id)) {
        Error(Nil) -> Ok(Missing(table: "Spell4Effects", id: token.id))
        Ok(row) -> Ok(spell_target(tables:, spell: row.spell_id, link: False))
      }
    tooltip_token.Spell, "" ->
      Ok(spell_target(tables:, spell: token.id, link: True))
    tooltip_token.Spell, _ ->
      Ok(spell_target(tables:, spell: token.id, link: False))
    tooltip_token.Smod, _
    | tooltip_token.Emod, _
    | tooltip_token.Thrsh, _
    | tooltip_token.Gf, _
    | tooltip_token.Creature, _
    | tooltip_token.Item, _
    | tooltip_token.Schematic, _
    | tooltip_token.Vitem, _
    | tooltip_token.Achievement, _
    | tooltip_token.Keybinding, _
    | tooltip_token.Bindpoint, _
    -> Error(Nil)
  }
}

fn spell_target(
  tables tables: store.Tables,
  spell spell: Int,
  link link: Bool,
) -> Target {
  case spell4.get(tables:, id: Spell4Id(spell)), link {
    Error(Nil), _ -> Missing(table: "Spell4", id: spell)
    Ok(_), True -> Link(spell:)
    Ok(_), False -> Value(spell:)
  }
}

/// The entries of the value tokens (or of the links) whose spell no tree reaches, by
/// spell id.
fn entries(
  namings namings: List(#(Target, Found, Int)),
  reached_set reached_set: Set(Int),
  left_out left_out: List(LeftOut),
  links links: Bool,
) -> List(Entry) {
  list.filter_map(namings, fn(naming) {
    case naming.0, links {
      Value(spell:), False | Link(spell:), True ->
        case set.contains(reached_set, spell) {
          True -> Error(Nil)
          False -> Ok(#(spell, #(naming.1, naming.2)))
        }
      Value(..), True | Link(..), False | Missing(..), _ -> Error(Nil)
    }
  })
  |> list.group(fn(named) { named.0 })
  |> dict.to_list
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(group) {
    Entry(
      spell: group.0,
      namings: merged(list.map(group.1, fn(named) { named.1 })),
      reason: reason_of(left_out:, spell: group.0),
    )
  })
}

/// The namings of the same token in the same text as one, with every reached spell that
/// holds the text, by text id and token.
fn merged(named: List(#(Found, Int))) -> List(Naming) {
  list.group(named, fn(one) { #({ one.0 }.text_id, { one.0 }.token) })
  |> dict.to_list
  |> list.map(fn(group) {
    Naming(
      token: group.0.1,
      text_id: group.0.0,
      named_by: list.map(group.1, fn(one) { one.1 })
        |> list.unique
        |> list.sort(int.compare),
    )
  })
  |> list.sort(fn(first, second) {
    case int.compare(first.text_id, second.text_id) {
      order.Eq ->
        string.compare(
          tooltip_token.describe(first.token),
          tooltip_token.describe(second.token),
        )
      other -> other
    }
  })
}

/// The tokens that name a row the tables lack, by id, then table and text.
fn no_rows(namings namings: List(#(Target, Found, Int))) -> List(NoRow) {
  list.filter_map(namings, fn(naming) {
    case naming.0 {
      Missing(table:, id:) -> Ok(#(#(table, id), #(naming.1, naming.2)))
      Value(..) | Link(..) -> Error(Nil)
    }
  })
  |> list.group(fn(named) { named.0 })
  |> dict.to_list
  |> list.sort(fn(first, second) {
    case int.compare(first.0.1, second.0.1) {
      order.Eq -> string.compare(first.0.0, second.0.0)
      other -> other
    }
  })
  |> list.flat_map(fn(group) {
    let #(table, id) = group.0
    merged(list.map(group.1, fn(named) { named.1 }))
    |> list.map(fn(naming) {
      NoRow(
        table:,
        id:,
        token: naming.token,
        text_id: naming.text_id,
        named_by: naming.named_by,
      )
    })
  })
}

/// The first part left out that holds the spell.
fn reason_of(
  left_out left_out: List(LeftOut),
  spell spell: Int,
) -> Option(LeftOut) {
  case
    list.find(left_out, fn(part) {
      list.contains(starting_ability.left_out_spells(left_out: part), spell)
    })
  {
    Ok(part) -> Some(part)
    Error(Nil) -> None
  }
}

/// The counts of a result: spells counted, those with a reason, spells links name and
/// tokens that name no row.
pub fn count_line(named named: Named) -> String {
  "Named by a tooltip, reached by no row: "
  <> int.to_string(list.length(named.counted))
  <> " ("
  <> int.to_string(
    list.count(named.counted, fn(entry) { option.is_some(entry.reason) }),
  )
  <> " with a left-out reason, "
  <> int.to_string(list.length(named.links))
  <> " links, "
  <> int.to_string(list.length(named.no_row))
  <> " tokens naming no row)"
}

/// The list the coverage measure prints: each counted spell, then the links, then the
/// tokens that name no row.
pub fn report(tables tables: store.Tables, named named: Named) -> String {
  string.join(
    list.flatten([
      ["Named by a tooltip, reached by no row:"],
      lines(named.counted, empty: "- none", describe: describe_entry(
        tables:,
        entry: _,
      )),
      ["Named by a link (not counted):"],
      lines(named.links, empty: "- none", describe: describe_entry(
        tables:,
        entry: _,
      )),
      ["Named by a token whose row the tables lack:"],
      lines(named.no_row, empty: "- none", describe: describe_no_row),
    ]),
    "\n",
  )
}

fn lines(
  items: List(a),
  empty empty: String,
  describe describe: fn(a) -> String,
) -> List(String) {
  case items {
    [] -> [empty]
    _ -> list.map(items, fn(item) { "- " <> describe(item) })
  }
}

fn describe_entry(tables tables: store.Tables, entry entry: Entry) -> String {
  "Spell4 "
  <> int.to_string(entry.spell)
  <> spell_name(tables:, spell: entry.spell)
  <> ": "
  <> string.join(
    list.map(entry.namings, fn(naming) { describe_naming(tables:, naming:) }),
    "; ",
  )
  <> case entry.reason {
    Some(part) ->
      " (left out: "
      <> starting_ability.describe_left_out(left_out: part)
      <> ")"
    None -> ""
  }
}

fn describe_no_row(no_row: NoRow) -> String {
  tooltip_token.describe(no_row.token)
  <> " in text "
  <> int.to_string(no_row.text_id)
  <> " of Spell4 "
  <> string.join(list.map(no_row.named_by, int.to_string), ", ")
  <> " names "
  <> no_row.table
  <> " "
  <> int.to_string(no_row.id)
  <> ", which has no row"
}

fn describe_naming(
  tables tables: store.Tables,
  naming naming: Naming,
) -> String {
  tooltip_token.describe(naming.token)
  <> " in text "
  <> int.to_string(naming.text_id)
  <> " of "
  <> string.join(
    list.map(naming.named_by, fn(spell) {
      "Spell4 " <> int.to_string(spell) <> spell_name(tables:, spell:)
    }),
    ", ",
  )
}

/// ` "name"` from the Spell4 row's description, empty when it has none.
fn spell_name(tables tables: store.Tables, spell spell: Int) -> String {
  case spell4.get(tables:, id: Spell4Id(spell)) {
    Ok(row) if row.description != "" -> " \"" <> row.description <> "\""
    Ok(_) | Error(Nil) -> ""
  }
}
