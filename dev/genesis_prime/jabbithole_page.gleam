//// The NPC pages of Jabbithole's local record (`npcs.jsonl`, one page to a line) as the
//// retail-record import reads them: each page's zone, name, address, capture date and the
//// spells its Abilities tab lists. A retail record is a lead for what the client lacks
//// (no client table links a creature to its spells); the import checks every value it
//// takes from a page against the client's own tables.
////
//// `read` parses every line, so a line that is not JSON, or lacks a field the reader needs,
//// refuses the whole file naming its line. It keeps the pages of the plain version of a
//// creature (a `variant` such as "veteran" repeats the name) that have an Abilities tab
//// with at least one spell.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// One spell of an Abilities tab: its Spell4 id and the page's tier column.
pub type Ability {
  Ability(spell4_id: Int, tier: Int)
}

/// A page of the record: the Jabbithole zone (a MapZone id), the creature's name, the
/// page's address, its capture date and the Abilities tab's spells in the order listed.
pub type Page {
  Page(
    zone: Int,
    name: String,
    url: String,
    captured: String,
    abilities: List(Ability),
  )
}

/// Why the file is refused: the line (the first is line 1) and what is wrong with it.
pub type Refusal {
  Refusal(line: Int, why: String)
}

/// The sentence for a refusal.
pub fn describe(refusal refusal: Refusal) -> String {
  "npcs.jsonl line " <> int.to_string(refusal.line) <> ": " <> refusal.why
}

/// A line as parsed: its page and whether it is a variant of the creature.
type Parsed {
  Parsed(page: Page, variant: Option(String))
}

/// Parses the file's text, giving the plain pages that list spells.
pub fn read(text text: String) -> Result(List(Page), Refusal) {
  string.split(text, "\n")
  |> list.index_map(fn(line, index) { #(index + 1, line) })
  |> list.try_fold([], fn(pages, numbered) {
    let #(number, line) = numbered
    case string.trim(line) {
      "" -> Ok(pages)
      line ->
        case json.parse(line, parsed_decoder()) {
          Error(error) -> Error(Refusal(line: number, why: why(error)))
          Ok(Parsed(page:, variant: None)) ->
            case page.abilities {
              [] -> Ok(pages)
              [_, ..] -> Ok([page, ..pages])
            }
          Ok(Parsed(variant: Some(_), ..)) -> Ok(pages)
        }
    }
  })
  |> result.map(list.reverse)
}

fn why(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "the line ends inside its JSON"
    json.UnexpectedByte(byte) -> "the byte " <> byte <> " is not JSON here"
    json.UnexpectedSequence(sequence) ->
      "the sequence " <> sequence <> " is not JSON here"
    json.UnableToDecode(errors) ->
      "a field the reader needs is missing or of another type: "
      <> string.join(
        list.map(errors, fn(error) {
          "wanted "
          <> error.expected
          <> " found "
          <> error.found
          <> " at "
          <> string.join(error.path, ".")
        }),
        "; ",
      )
  }
}

fn parsed_decoder() -> decode.Decoder(Parsed) {
  use zone <- decode.field("zone", decode.int)
  use variant <- decode.field("variant", decode.optional(decode.string))
  use name <- decode.field("name", decode.string)
  use url <- decode.field("url", decode.string)
  use captured <- decode.field("captured", decode.string)
  use tables <- decode.then(decode.optionally_at(
    ["tabs", "Abilities"],
    [],
    decode.list(rows_decoder()),
  ))
  decode.success(Parsed(
    page: Page(zone:, name:, url:, captured:, abilities: list.flatten(tables)),
    variant:,
  ))
}

fn rows_decoder() -> decode.Decoder(List(Ability)) {
  use rows <- decode.field("rows", decode.list(ability_decoder()))
  decode.success(rows)
}

fn ability_decoder() -> decode.Decoder(Ability) {
  use spell4_id <- decode.subfield(["Name", "id"], decode.int)
  use tier <- decode.field("Tier", whole_number_text())
  decode.success(Ability(spell4_id:, tier:))
}

/// A whole number written as text, as the Tier column is.
fn whole_number_text() -> decode.Decoder(Int) {
  decode.then(decode.string, fn(text) {
    case int.parse(text) {
      Ok(number) -> decode.success(number)
      Error(Nil) -> decode.failure(0, "a whole number as text")
    }
  })
}
